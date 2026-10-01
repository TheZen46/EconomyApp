#ifndef RECEIPT_ENGINE_H
#define RECEIPT_ENGINE_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
  #if defined(RECEIPT_ENGINE_EXPORTS)
    #define RECEIPT_ENGINE_API __declspec(dllexport)
  #elif defined(RECEIPT_ENGINE_STATIC)
    #define RECEIPT_ENGINE_API
  #else
    #define RECEIPT_ENGINE_API __declspec(dllimport)
  #endif
#else
  #if defined(__GNUC__) && __GNUC__ >= 4
    #define RECEIPT_ENGINE_API __attribute__((visibility("default")))
  #else
    #define RECEIPT_ENGINE_API
  #endif
#endif

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Opaque handle representing the initialized multimodal receipt processing engine.
 * Encapsulates the llama.cpp LLM context, CLIP vision projector, GBNF grammar parser, and thread locks.
 */
typedef struct receipt_engine_t receipt_engine_t;

/**
 * Callback function signature for streaming token generation.
 *
 * @param token The newly generated UTF-8 text token chunk.
 * @param is_done Non-zero (1) when generation has completed (last invocation), 0 otherwise.
 * @param user_data Arbitrary pointer forwarded from the caller.
 */
typedef void (*receipt_token_callback_t)(const char* token, int is_done, void* user_data);

/**
 * Initializes the Vision-Language Model inference engine.
 *
 * Loads the language model via memory-mapped I/O (mmap) for zero-copy weight access,
 * initializes the CLIP vision projector context, and compiles the GBNF grammar parser.
 *
 * @param model_path Path to the quantized language model GGUF file (e.g. qwen2_vl_2b.Q4_K_M.gguf).
 * @param mmproj_path Path to the multimodal CLIP vision projector GGUF (e.g. mmproj-model-f16.gguf). Can be NULL.
 * @param grammar_path Path to the receipt.gbnf grammar file. Can be NULL for unconstrained decoding.
 * @param n_threads Number of CPU compute threads (0 for auto-detection based on hardware concurrency).
 * @param n_gpu_layers Number of layers to offload to GPU / Metal / Vulkan (0 for CPU only).
 * @param n_ctx Context window token capacity (e.g. 2048 or 4096).
 * @return Non-null pointer to initialized engine on success, NULL on failure. Fails when the
 *         model or its context cannot be loaded, and always when the library was built
 *         without llama.cpp.
 */
RECEIPT_ENGINE_API receipt_engine_t* receipt_engine_init(
    const char* model_path,
    const char* mmproj_path,
    const char* grammar_path,
    int n_threads,
    int n_gpu_layers,
    int n_ctx
);

/**
 * Releases all native allocations, contexts, models, CLIP structures, and memory mappings.
 * Thread-safe and safe to invoke with a NULL pointer.
 *
 * @param engine Pointer to active engine instance.
 */
RECEIPT_ENGINE_API void receipt_engine_free(receipt_engine_t* engine);

/**
 * Returns 1 if the engine is successfully loaded and ready for inference, 0 otherwise.
 *
 * @param engine Active engine handle.
 */
RECEIPT_ENGINE_API int receipt_engine_is_ready(const receipt_engine_t* engine);

/**
 * Processes an input receipt image and produces structured JSON strictly constrained by the GBNF grammar.
 *
 * Preprocesses the raw image buffer, constructs the composite multimodal prompt with
 * injected few-shot episodic memory context, evaluates vision embeddings, and performs
 * grammar-constrained autoregressive decoding.
 *
 * @param engine Active engine handle.
 * @param image_bytes Pointer to raw compressed image bytes (JPEG/PNG/WebP).
 * @param image_len Length of the image bytes buffer.
 * @param few_shot_context Optional string containing historical user corrections/few-shot examples (NULL if none).
 * @param system_prompt Optional override for the VLM system prompt (NULL for default receipt extractor prompt).
 * @param output_buffer Destination buffer for the generated JSON string.
 * @param max_output_len Size of the destination buffer in bytes.
 * @return 0 on success, negative error code on failure: -1 invalid engine, -2 invalid
 *         parameters, -3 undecodable image, -4 letterbox failure, -5 output buffer too small,
 *         -6 generation produced no output (see receipt_engine_get_last_error).
 */
RECEIPT_ENGINE_API int receipt_engine_process_image(
    receipt_engine_t* engine,
    const uint8_t* image_bytes,
    size_t image_len,
    const char* few_shot_context,
    const char* system_prompt,
    char* output_buffer,
    size_t max_output_len
);

/**
 * Processes an input receipt image and streams generated tokens synchronously via callback.
 *
 * @param engine Active engine handle.
 * @param image_bytes Pointer to raw compressed image bytes.
 * @param image_len Length of the image bytes buffer.
 * @param few_shot_context Optional few-shot context string (NULL if none).
 * @param system_prompt Optional system prompt override (NULL if default).
 * @param callback Function called synchronously as tokens are produced.
 * @param user_data Passed directly to callback.
 * @return 0 on success, negative error code on failure.
 */
RECEIPT_ENGINE_API int receipt_engine_process_image_streaming(
    receipt_engine_t* engine,
    const uint8_t* image_bytes,
    size_t image_len,
    const char* few_shot_context,
    const char* system_prompt,
    receipt_token_callback_t callback,
    void* user_data
);

/**
 * Dynamically reloads the GBNF grammar (e.g. when user modifies custom categories or taxonomy).
 *
 * @param engine Active engine handle.
 * @param grammar_path Path to new .gbnf grammar file.
 * @return 0 on success, negative error code on failure.
 */
RECEIPT_ENGINE_API int receipt_engine_reload_grammar(
    receipt_engine_t* engine,
    const char* grammar_path
);

/**
 * Applies AVX2/NEON SIMD-accelerated CLAHE preprocessing to raw image bytes.
 * Enhances low-contrast thermal receipts and writes enhanced image to out_bytes.
 *
 * @param in_bytes Pointer to raw compressed image bytes (JPEG/PNG/WebP).
 * @param in_len Length of raw image buffer.
 * @param out_bytes Destination buffer for enhanced raw image bytes.
 * @param out_len Maximum capacity of destination buffer.
 * @param clip_limit Contrast clipping limit (default 2.0 - 4.0).
 * @return Number of output bytes written on success, negative error code on failure.
 */
RECEIPT_ENGINE_API int receipt_engine_apply_clahe(
    const uint8_t* in_bytes,
    size_t in_len,
    uint8_t* out_bytes,
    size_t out_len,
    float clip_limit
);

/**
 * Pops the next available token chunk from the lock-free SPSC token ring buffer.
 * Wait-free call for the Dart FFI / event loop thread.
 *
 * @param engine Active engine handle.
 * @param out_buf Destination character buffer for token piece.
 * @param max_len Size of destination buffer.
 * @param out_is_done Destination pointer set to 1 if generation complete, 0 otherwise.
 * @return 1 if a token was successfully popped, 0 if queue was empty, negative on error.
 */
RECEIPT_ENGINE_API int receipt_engine_pop_token(
    receipt_engine_t* engine,
    char* out_buf,
    size_t max_len,
    int* out_is_done
);

/**
 * Retrieves virtual paged KV-cache statistics and prefix cache hit rate.
 *
 * @param engine Active engine handle.
 * @param out_total_blocks Destination pointer for total virtual blocks in arena.
 * @param out_allocated_blocks Destination pointer for active allocated blocks.
 * @param out_hit_rate Destination pointer for prefix cache hit rate percentage.
 */
RECEIPT_ENGINE_API void receipt_engine_get_kv_cache_stats(
    const receipt_engine_t* engine,
    size_t* out_total_blocks,
    size_t* out_allocated_blocks,
    float* out_hit_rate
);

/**
 * Runs a SIMD CLAHE benchmark over a synthetic image of given dimensions.
 *
 * @param width Image width in pixels (e.g. 4096).
 * @param height Image height in pixels (e.g. 3072).
 * @return Execution duration in milliseconds.
 */
RECEIPT_ENGINE_API double receipt_engine_benchmark_clahe(
    int width,
    int height
);

// ══════════════════════════════════════════════════════════════════════════════
// HNSW VECTOR GRAPH INDEX C FFI INTERFACE
// ══════════════════════════════════════════════════════════════════════════════

typedef struct receipt_hnsw_index_t receipt_hnsw_index_t;

/**
 * Creates an on-device HNSW Vector Graph Index (128-dimensional dense embeddings).
 */
RECEIPT_ENGINE_API receipt_hnsw_index_t* receipt_engine_hnsw_create(
    int m,
    int m0,
    int ef_construction,
    int ef_search
);

/**
 * Releases the HNSW Vector Graph Index memory.
 */
RECEIPT_ENGINE_API void receipt_engine_hnsw_free(
    receipt_hnsw_index_t* index
);

/**
 * Inserts a 128-d float vector into the HNSW graph.
 */
RECEIPT_ENGINE_API int receipt_engine_hnsw_add(
    receipt_hnsw_index_t* index,
    int id,
    const float* vector
);

/**
 * Searches top-k nearest neighbors within cosine distance threshold.
 */
RECEIPT_ENGINE_API int receipt_engine_hnsw_search(
    const receipt_hnsw_index_t* index,
    const float* query_vector,
    int k,
    float max_distance,
    int* out_ids,
    float* out_distances,
    float* out_similarities
);

/**
 * Persists HNSW graph directly to binary file.
 */
RECEIPT_ENGINE_API int receipt_engine_hnsw_save(
    const receipt_hnsw_index_t* index,
    const char* filepath
);

/**
 * Loads HNSW graph directly from binary file.
 */
RECEIPT_ENGINE_API int receipt_engine_hnsw_load(
    receipt_hnsw_index_t* index,
    const char* filepath
);

/**
 * Returns total number of indexed vectors in HNSW graph.
 */
RECEIPT_ENGINE_API size_t receipt_engine_hnsw_size(
    const receipt_hnsw_index_t* index
);

/**
 * Returns the last error message recorded by the engine on the calling thread.
 *
 * @param engine Active engine handle.
 */
RECEIPT_ENGINE_API const char* receipt_engine_get_last_error(const receipt_engine_t* engine);

#ifdef __cplusplus
}
#endif

#endif // RECEIPT_ENGINE_H
