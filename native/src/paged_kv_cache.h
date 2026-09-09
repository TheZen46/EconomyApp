#ifndef PAGED_KV_CACHE_H
#define PAGED_KV_CACHE_H

#include <cstddef>
#include <cstdint>
#include <vector>
#include <unordered_map>
#include <memory>
#include <mutex>
#include <cstring>

namespace receipt {

// Block size for virtual KV-cache paging
constexpr size_t KV_BLOCK_SIZE = 16;
constexpr size_t DEFAULT_MAX_TOKENS = 2048;
constexpr size_t LOW_MEMORY_MAX_TOKENS = 1024;

/**
 * Physical Block Frame in the Paged KV-Cache.
 * Stores contiguous Key and Value representations for KV_BLOCK_SIZE tokens.
 */
struct KVBlockFrame {
    int block_id = -1;
    bool is_allocated = false;
    size_t num_tokens = 0; // Number of valid tokens stored (up to KV_BLOCK_SIZE)
    uint64_t last_accessed = 0;

    // Fixed pre-allocated memory buffer for key and value vectors
    // 16 tokens * 32 layers * 128 head_dim * 2 (K+V) * sizeof(float) ~ 512 KB per block
    std::vector<float> data;

    KVBlockFrame() = default;

    void initialize(size_t elements_per_block) {
        data.resize(elements_per_block, 0.0f);
        num_tokens = 0;
        is_allocated = false;
        last_accessed = 0;
    }

    void clear() {
        num_tokens = 0;
        is_allocated = false;
        last_accessed = 0;
    }
};

/**
 * Statistics report for Paged KV-Cache memory and prefix hits.
 */
struct KVCacheStats {
    size_t total_blocks = 0;
    size_t allocated_blocks = 0;
    size_t free_blocks = 0;
    size_t max_token_capacity = 0;
    size_t allocated_bytes = 0;
    uint64_t prefix_cache_hits = 0;
    uint64_t prefix_cache_misses = 0;
    float hit_rate_pct = 0.0f;
};

/**
 * Paged KV-Cache Manager.
 *
 * Implements virtual block paging with static prompt prefix caching to prevent
 * memory fragmentation and eliminate redundant vision/prompt attention evaluations.
 */
class PagedKVCache {
public:
    PagedKVCache(
        size_t max_tokens = DEFAULT_MAX_TOKENS,
        size_t n_layers = 28,
        size_t kv_dim = 1024,
        bool low_memory_mode = false
    ) : max_tokens_(low_memory_mode ? LOW_MEMORY_MAX_TOKENS : max_tokens),
        n_layers_(n_layers),
        kv_dim_(kv_dim),
        total_blocks_((max_tokens_ + KV_BLOCK_SIZE - 1) / KV_BLOCK_SIZE),
        prefix_cache_hits_(0),
        prefix_cache_misses_(0),
        access_counter_(0)
    {
        // Elements per block: KV_BLOCK_SIZE * n_layers * kv_dim * 2 (Key + Value)
        elements_per_block_ = KV_BLOCK_SIZE * n_layers_ * kv_dim_ * 2;
        
        // Cap allocation to 128MB in low-memory architectures
        if (low_memory_mode) {
            size_t max_elements_128mb = (128ULL * 1024 * 1024) / sizeof(float);
            size_t max_blocks_allowed = max_elements_128mb / elements_per_block_;
            if (max_blocks_allowed > 0 && total_blocks_ > max_blocks_allowed) {
                total_blocks_ = max_blocks_allowed;
                max_tokens_ = total_blocks_ * KV_BLOCK_SIZE;
            }
        }

        // Pre-allocate contiguous physical frames in the memory arena
        frames_.resize(total_blocks_);
        free_block_ids_.reserve(total_blocks_);

        for (size_t i = 0; i < total_blocks_; ++i) {
            frames_[i].block_id = static_cast<int>(i);
            frames_[i].initialize(elements_per_block_);
            free_block_ids_.push_back(static_cast<int>(i));
        }
    }

    ~PagedKVCache() = default;

    /**
     * Allocates a physical block frame from the free list.
     * @return Physical block ID, or -1 if the memory arena is exhausted.
     */
    int allocate_block() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (free_block_ids_.empty()) {
            return -1; // Out of memory frames in arena
        }

        int block_id = free_block_ids_.back();
        free_block_ids_.pop_back();

        frames_[block_id].is_allocated = true;
        frames_[block_id].num_tokens = 0;
        frames_[block_id].last_accessed = ++access_counter_;
        return block_id;
    }

    /**
     * Releases a physical block frame back to the free list.
     */
    void free_block(int block_id) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (block_id >= 0 && static_cast<size_t>(block_id) < total_blocks_) {
            frames_[block_id].clear();
            free_block_ids_.push_back(block_id);
        }
    }

    /**
     * Checks if a static prompt prefix is cached.
     *
     * @param prefix_hash 64-bit hash of the prefix prompt string.
     * @param out_block_ids Destination list of cached physical block IDs.
     * @param out_token_count Number of cached tokens in the prefix.
     * @return true on cache hit, false on cache miss.
     */
    bool lookup_prefix_cache(
        uint64_t prefix_hash,
        std::vector<int>& out_block_ids,
        size_t& out_token_count
    ) {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = prefix_cache_.find(prefix_hash);
        if (it != prefix_cache_.end()) {
            prefix_cache_hits_++;
            out_block_ids = it->second.block_ids;
            out_token_count = it->second.token_count;
            for (int bid : out_block_ids) {
                if (bid >= 0 && static_cast<size_t>(bid) < total_blocks_) {
                    frames_[bid].last_accessed = ++access_counter_;
                }
            }
            return true;
        }

        prefix_cache_misses_++;
        return false;
    }

    /**
     * Registers a static prompt prefix in the cache.
     */
    void register_prefix_cache(
        uint64_t prefix_hash,
        const std::vector<int>& block_ids,
        size_t token_count
    ) {
        std::lock_guard<std::mutex> lock(mutex_);
        PrefixEntry entry;
        entry.block_ids = block_ids;
        entry.token_count = token_count;
        prefix_cache_[prefix_hash] = entry;
    }

    /**
     * Computes real-time telemetry statistics.
     */
    KVCacheStats get_stats() const {
        std::lock_guard<std::mutex> lock(mutex_);
        KVCacheStats stats;
        stats.total_blocks = total_blocks_;
        stats.free_blocks = free_block_ids_.size();
        stats.allocated_blocks = total_blocks_ - stats.free_blocks;
        stats.max_token_capacity = max_tokens_;
        stats.allocated_bytes = total_blocks_ * elements_per_block_ * sizeof(float);
        stats.prefix_cache_hits = prefix_cache_hits_;
        stats.prefix_cache_misses = prefix_cache_misses_;

        uint64_t total_lookups = prefix_cache_hits_ + prefix_cache_misses_;
        stats.hit_rate_pct = total_lookups > 0
            ? (static_cast<float>(prefix_cache_hits_) * 100.0f / total_lookups)
            : 0.0f;

        return stats;
    }

    /**
     * Fast 64-bit FNV-1a hash utility for prefix string identification.
     */
    static uint64_t hash_string(const char* str, size_t len) {
        if (!str || len == 0) return 0;
        uint64_t hash = 14695981039346656037ULL;
        for (size_t i = 0; i < len; ++i) {
            hash ^= static_cast<uint64_t>(str[i]);
            hash *= 1099511628211ULL;
        }
        return hash;
    }

private:
    struct PrefixEntry {
        std::vector<int> block_ids;
        size_t token_count = 0;
    };

    size_t max_tokens_;
    size_t n_layers_;
    size_t kv_dim_;
    size_t total_blocks_;
    size_t elements_per_block_;

    mutable std::mutex mutex_;
    std::vector<KVBlockFrame> frames_;
    std::vector<int> free_block_ids_;
    std::unordered_map<uint64_t, PrefixEntry> prefix_cache_;

    uint64_t prefix_cache_hits_;
    uint64_t prefix_cache_misses_;
    uint64_t access_counter_;
};

} // namespace receipt

#endif // PAGED_KV_CACHE_H
