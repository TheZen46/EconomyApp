#ifndef RECEIPT_ENGINE_STATIC
#define RECEIPT_ENGINE_STATIC 1
#endif

#include "receipt_engine.h"
#include "receipt_token_ring.h"
#include "paged_kv_cache.h"
#include "image_preprocessor.h"
#include "gpu_zero_copy.h"
#include "hnsw_vector_index.h"

#include <iostream>
#include <cassert>
#include <vector>
#include <thread>
#include <chrono>
#include <string>
#include <atomic>
#include <cmath>

#define TEST_ASSERT(cond, msg) \
    do { \
        if (!(cond)) { \
            std::cerr << "FAIL: " << (msg) << " (" << __FILE__ << ":" << __LINE__ << ")" << std::endl; \
            std::exit(1); \
        } \
    } while (0)

// ------------------------------------------------------------------------------
// TEST 1: SPSC LOCK-FREE TOKEN RING BUFFER
// ------------------------------------------------------------------------------
void test_token_ring_basic() {
    std::cout << "[Test 1.1] SPSC Token Ring: Basic push, pop, boundary checks..." << std::endl;
    receipt::ReceiptTokenRing<16> ring;
    TEST_ASSERT(ring.is_empty(), "Ring should start empty");
    TEST_ASSERT(ring.size() == 0, "Ring size should be 0");

    char buf[64];
    int is_done = 0;
    TEST_ASSERT(!ring.try_pop(buf, sizeof(buf), &is_done), "Pop on empty should return false");

    // Push until capacity
    for (int i = 0; i < 16; ++i) {
        std::string token = "tok_" + std::to_string(i);
        bool ok = ring.try_push(token.c_str(), i == 15 ? 1 : 0);
        TEST_ASSERT(ok, "Pushing within capacity should succeed");
    }

    // Next push should fail (full)
    TEST_ASSERT(!ring.try_push("overflow", 0), "Pushing into full ring must return false");

    // Pop all items
    for (int i = 0; i < 16; ++i) {
        bool ok = ring.try_pop(buf, sizeof(buf), &is_done);
        TEST_ASSERT(ok, "Popping valid item should succeed");
        std::string expected = "tok_" + std::to_string(i);
        TEST_ASSERT(std::string(buf) == expected, "Popped token content mismatch");
        if (i == 15) {
            TEST_ASSERT(is_done == 1, "Last token must have is_done=1");
        } else {
            TEST_ASSERT(is_done == 0, "Non-terminal token must have is_done=0");
        }
    }

    TEST_ASSERT(ring.is_empty(), "Ring should be empty after popping all");
    std::cout << "  -> Passed!" << std::endl;
}

void test_token_ring_multithreaded() {
    std::cout << "[Test 1.2] SPSC Token Ring: Multi-threaded Producer-Consumer concurrency..." << std::endl;
    receipt::ReceiptTokenRing<1024> ring;
    const int total_tokens = 5000;
    std::vector<std::string> received;
    received.reserve(total_tokens);

    std::atomic<bool> producer_done{false};

    // Consumer thread
    std::thread consumer([&]() {
        char buf[64];
        int is_done = 0;
        int count = 0;
        while (count < total_tokens) {
            if (ring.try_pop(buf, sizeof(buf), &is_done)) {
                received.push_back(std::string(buf));
                count++;
                if (is_done) break;
            } else {
                std::this_thread::yield();
            }
        }
    });

    // Producer thread
    std::thread producer([&]() {
        for (int i = 0; i < total_tokens; ++i) {
            std::string tok = "T" + std::to_string(i);
            int done = (i == total_tokens - 1) ? 1 : 0;
            while (!ring.try_push(tok.c_str(), done)) {
                std::this_thread::yield();
            }
        }
        producer_done = true;
    });

    producer.join();
    consumer.join();

    TEST_ASSERT(received.size() == total_tokens, "Consumer must receive exact token count");
    for (int i = 0; i < total_tokens; ++i) {
        std::string expected = "T" + std::to_string(i);
        TEST_ASSERT(received[i] == expected, "Token ordering in SPSC ring was violated");
    }
    std::cout << "  -> Passed (" << total_tokens << " tokens streamed lock-free)!" << std::endl;
}

// ------------------------------------------------------------------------------
// TEST 2: PAGED KV-CACHE & PREFIX CACHING
// ------------------------------------------------------------------------------
void test_paged_kv_cache() {
    std::cout << "[Test 2.1] Paged KV-Cache: Block allocation and memory limits..." << std::endl;
    receipt::PagedKVCache cache(2048, 28, 1024, false);
    receipt::KVCacheStats stats = cache.get_stats();
    TEST_ASSERT(stats.total_blocks == 128, "2048 tokens / 16 block size = 128 blocks");
    TEST_ASSERT(stats.free_blocks == 128, "All blocks initially free");
    TEST_ASSERT(stats.allocated_blocks == 0, "No blocks initially allocated");

    // Allocate 4 blocks
    int b0 = cache.allocate_block();
    int b1 = cache.allocate_block();
    int b2 = cache.allocate_block();
    int b3 = cache.allocate_block();
    TEST_ASSERT(b0 >= 0 && b1 >= 0 && b2 >= 0 && b3 >= 0, "Block allocations should succeed");

    stats = cache.get_stats();
    TEST_ASSERT(stats.allocated_blocks == 4, "Allocated block count mismatch");
    TEST_ASSERT(stats.free_blocks == 124, "Free block count mismatch");

    // Free 2 blocks
    cache.free_block(b1);
    cache.free_block(b3);
    stats = cache.get_stats();
    TEST_ASSERT(stats.allocated_blocks == 2, "Allocated block count after free mismatch");

    // Prefix Caching Test
    std::cout << "[Test 2.2] Paged KV-Cache: Static Prompt Prefix Caching..." << std::endl;
    const char* sys_prompt = "<|im_start|>system\nYou are an expert on-device receipt intelligence engine.<|im_end|>";
    uint64_t hash = receipt::PagedKVCache::hash_string(sys_prompt, strlen(sys_prompt));

    std::vector<int> out_blocks;
    size_t out_tokens = 0;
    TEST_ASSERT(!cache.lookup_prefix_cache(hash, out_blocks, out_tokens), "Initial lookup should miss");

    // Register prefix
    std::vector<int> prefix_blocks = {b0, b2};
    cache.register_prefix_cache(hash, prefix_blocks, 32);

    // Second lookup should hit
    TEST_ASSERT(cache.lookup_prefix_cache(hash, out_blocks, out_tokens), "Second lookup must hit");
    TEST_ASSERT(out_tokens == 32, "Cached token count mismatch");
    TEST_ASSERT(out_blocks.size() == 2 && out_blocks[0] == b0 && out_blocks[1] == b2, "Cached blocks mismatch");

    stats = cache.get_stats();
    TEST_ASSERT(stats.prefix_cache_hits == 1, "Cache hit count mismatch");
    TEST_ASSERT(stats.prefix_cache_misses == 1, "Cache miss count mismatch");
    TEST_ASSERT(stats.hit_rate_pct == 50.0f, "Cache hit rate percentage mismatch");

    std::cout << "  -> Passed!" << std::endl;
}

// ------------------------------------------------------------------------------
// TEST 3: SIMD CLAHE PREPROCESSOR
// ------------------------------------------------------------------------------
void test_simd_clahe() {
    std::cout << "[Test 3.1] SIMD CLAHE: Low-contrast thermal enhancement..." << std::endl;

    // Create a low-contrast synthetic image (256x256)
    receipt::DecodedImage input;
    input.width = 256;
    input.height = 256;
    input.channels = 3;
    input.data.resize(256 * 256 * 3);

    for (int y = 0; y < 256; ++y) {
        for (int x = 0; x < 256; ++x) {
            // Low-contrast grayscale pixel in range [100..140]
            uint8_t val = static_cast<uint8_t>(100 + ((x + y) % 40));
            int idx = (y * 256 + x) * 3;
            input.data[idx] = val;
            input.data[idx + 1] = val;
            input.data[idx + 2] = val;
        }
    }

    receipt::DecodedImage output;
    bool ok = receipt::ImagePreprocessor::applyCLAHE(input, output, 3.0f, 8, 8);
    TEST_ASSERT(ok, "CLAHE application must succeed");
    TEST_ASSERT(output.isValid(), "CLAHE output must be a valid image");

    // Measure dynamic range expansion
    uint8_t min_in = 255, max_in = 0;
    uint8_t min_out = 255, max_out = 0;
    for (size_t i = 0; i < input.data.size(); i += 3) {
        min_in = std::min(min_in, input.data[i]);
        max_in = std::max(max_in, input.data[i]);
        min_out = std::min(min_out, output.data[i]);
        max_out = std::max(max_out, output.data[i]);
    }

    std::cout << "  Input Range: [" << (int)min_in << ".." << (int)max_in << "], "
              << "Enhanced Range: [" << (int)min_out << ".." << (int)max_out << "]" << std::endl;
    TEST_ASSERT((max_out - min_out) > (max_in - min_in), "CLAHE must expand dynamic range");

    // Benchmark CLAHE
    std::cout << "[Test 3.2] SIMD CLAHE: 4K UHD Benchmark..." << std::endl;
    double ms = receipt::ImagePreprocessor::benchmarkCLAHE(3840, 2160);
    std::cout << "  4K CLAHE Latency: " << ms << " ms" << std::endl;
    TEST_ASSERT(ms > 0.0, "Benchmark must return positive duration");
    std::cout << "  -> Passed!" << std::endl;
}

// ------------------------------------------------------------------------------
// TEST 4: RECEIPT ENGINE C FFI EXPORTS
// ------------------------------------------------------------------------------
void test_receipt_engine_ffi() {
    std::cout << "[Test 4.1] C FFI: Engine Initialization & KV Cache Stats..." << std::endl;
    receipt_engine_t* engine = receipt_engine_init("test_model.gguf", nullptr, nullptr, 4, 0, 2048);
    TEST_ASSERT(engine != nullptr, "receipt_engine_init should return handle");
    TEST_ASSERT(receipt_engine_is_ready(engine) == 1, "receipt_engine_is_ready must return 1");

    size_t total_b = 0, alloc_b = 0;
    float hit_rate = 0.0f;
    receipt_engine_get_kv_cache_stats(engine, &total_b, &alloc_b, &hit_rate);
    TEST_ASSERT(total_b > 0, "KV cache total blocks must be > 0");

    std::cout << "[Test 4.2] C FFI: Image Processing & SPSC Token Polling..." << std::endl;
    // Synthetic 16x16 PPM image
    std::string ppm = "P6\n16 16\n255\n";
    ppm.append(16 * 16 * 3, static_cast<char>(180));

    char output_buf[4096] = {0};
    int res = receipt_engine_process_image(
        engine,
        reinterpret_cast<const uint8_t*>(ppm.data()),
        ppm.size(),
        nullptr,
        nullptr,
        output_buf,
        sizeof(output_buf)
    );
    TEST_ASSERT(res == 0, "receipt_engine_process_image must succeed");
    TEST_ASSERT(strlen(output_buf) > 0, "Output JSON must not be empty");

    // Poll tokens from ring buffer
    char token_buf[64] = {0};
    int is_done = 0;
    int pop_count = 0;
    while (receipt_engine_pop_token(engine, token_buf, sizeof(token_buf), &is_done) == 1) {
        pop_count++;
        if (is_done) break;
    }
    TEST_ASSERT(pop_count > 0, "Must have popped tokens from the SPSC ring buffer");

    receipt_engine_free(engine);
    std::cout << "  -> Passed!" << std::endl;
}

// ══════════════════════════════════════════════════════════════════════════════
// TEST 5: HNSW VECTOR GRAPH INDEX & SIMD COSINE DISTANCE
// ══════════════════════════════════════════════════════════════════════════════
void test_hnsw_vector_index() {
    std::cout << "[Test 5.1] HNSW Vector Index: Vector Insertion & Nearest Neighbor Search..." << std::endl;
    receipt::HNSWVectorIndex index(16, 32, 64, 32);

    // Create normalized 128-d vectors
    std::vector<std::vector<float>> dataset(50, std::vector<float>(128, 0.0f));
    for (int i = 0; i < 50; ++i) {
        float sum_sq = 0.0f;
        for (int d = 0; d < 128; ++d) {
            float val = std::sin(static_cast<float>(i * 128 + d));
            dataset[i][d] = val;
            sum_sq += val * val;
        }
        float norm = 1.0f / std::sqrt(sum_sq);
        for (int d = 0; d < 128; ++d) {
            dataset[i][d] *= norm;
        }
        index.add_point(i, dataset[i].data());
    }

    TEST_ASSERT(index.size() == 50, "Index must contain 50 points");

    // Exact query for vector 7
    auto hits = index.search_knn(dataset[7].data(), 3, 0.22f);
    TEST_ASSERT(!hits.empty(), "Hits must not be empty");
    TEST_ASSERT(hits[0].id == 7, "Top hit for vector 7 must be ID 7");
    TEST_ASSERT(hits[0].distance < 0.001f, "Self-distance must be ~0.0");
    TEST_ASSERT(hits[0].similarity > 0.999f, "Self-similarity must be ~1.0");

    // Test binary persistence
    std::cout << "[Test 5.2] HNSW Vector Index: Binary Serialization / Deserialization..." << std::endl;
    const char* temp_bin = "test_hnsw_rag.bin";
    bool saved = index.save_to_file(temp_bin);
    TEST_ASSERT(saved, "save_to_file must succeed");

    receipt::HNSWVectorIndex loaded_index(16, 32, 64, 32);
    bool loaded = loaded_index.load_from_file(temp_bin);
    TEST_ASSERT(loaded, "load_from_file must succeed");
    TEST_ASSERT(loaded_index.size() == 50, "Loaded index must have 50 points");

    auto loaded_hits = loaded_index.search_knn(dataset[7].data(), 3, 0.22f);
    TEST_ASSERT(!loaded_hits.empty() && loaded_hits[0].id == 7, "Query on loaded index must match");

    std::remove(temp_bin);

    // Test C FFI exports
    std::cout << "[Test 5.3] HNSW Vector Index: C FFI API Integration..." << std::endl;
    receipt_hnsw_index_t* ffi_index = receipt_engine_hnsw_create(16, 32, 64, 32);
    TEST_ASSERT(ffi_index != nullptr, "receipt_engine_hnsw_create must return non-null");

    for (int i = 0; i < 20; ++i) {
        int add_res = receipt_engine_hnsw_add(ffi_index, i, dataset[i].data());
        TEST_ASSERT(add_res == 0, "receipt_engine_hnsw_add must return 0");
    }
    TEST_ASSERT(receipt_engine_hnsw_size(ffi_index) == 20, "HNSW size must be 20");

    int out_ids[5] = {0};
    float out_dists[5] = {0.0f};
    float out_sims[5] = {0.0f};
    int hit_count = receipt_engine_hnsw_search(ffi_index, dataset[3].data(), 3, 0.22f, out_ids, out_dists, out_sims);
    TEST_ASSERT(hit_count >= 1 && out_ids[0] == 3, "FFI search top hit must be ID 3");

    receipt_engine_hnsw_free(ffi_index);
    std::cout << "  -> Passed!" << std::endl;
}

int main() {
    std::cout << "==================================================" << std::endl;
    std::cout << " tAIdy Native Receipt Engine Verification Suite   " << std::endl;
    std::cout << " Directive 10 & 11: SIMD, Paged KV, HNSW Graph    " << std::endl;
    std::cout << "==================================================" << std::endl;

    test_token_ring_basic();
    test_token_ring_multithreaded();
    test_paged_kv_cache();
    test_simd_clahe();
    test_receipt_engine_ffi();
    test_hnsw_vector_index();

    std::cout << "==================================================" << std::endl;
    std::cout << " ALL NATIVE C++ TESTS PASSED SUCCESSFULLY!        " << std::endl;
    std::cout << "==================================================" << std::endl;
    return 0;
}
