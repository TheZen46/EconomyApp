#ifndef RECEIPT_TOKEN_RING_H
#define RECEIPT_TOKEN_RING_H

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <new>

namespace receipt {

// 64-byte alignment to prevent false sharing across CPU cache lines
#ifndef CACHE_LINE_SIZE
#define CACHE_LINE_SIZE 64
#endif

/**
 * Token chunk container stored directly in the lock-free ring buffer.
 * Inlines up to 64 bytes of UTF-8 characters to prevent dynamic heap allocations.
 */
struct TokenChunk {
    static constexpr size_t MAX_CHUNK_LEN = 60;
    char text[MAX_CHUNK_LEN];
    int is_done;

    TokenChunk() : is_done(0) {
        text[0] = '\0';
    }

    TokenChunk(const char* token, int done) : is_done(done) {
        if (token) {
            size_t len = 0;
            while (token[len] != '\0' && len < MAX_CHUNK_LEN - 1) {
                text[len] = token[len];
                len++;
            }
            text[len] = '\0';
        } else {
            text[0] = '\0';
        }
    }
};

/**
 * Single-Producer Single-Consumer (SPSC) Lock-Free Token Ring Buffer.
 *
 * Guarantees wait-free / lock-free streaming of generated token chunks
 * from the native C++ inference worker thread to the Dart FFI / event loop thread.
 *
 * Designed with 64-byte cache line separation to eliminate CPU cache invalidation.
 */
template <size_t Capacity = 4096>
class alignas(CACHE_LINE_SIZE) ReceiptTokenRing {
    static_assert((Capacity & (Capacity - 1)) == 0, "Capacity must be a power of 2");

public:
    ReceiptTokenRing() : head_(0), tail_(0) {
        buffer_ = new TokenChunk[Capacity];
    }

    ~ReceiptTokenRing() {
        delete[] buffer_;
    }

    // Non-copyable and non-movable for atomic safety
    ReceiptTokenRing(const ReceiptTokenRing&) = delete;
    ReceiptTokenRing& operator=(const ReceiptTokenRing&) = delete;

    /**
     * Producer: Enqueues a new token chunk into the ring buffer.
     * Called strictly from the C++ inference worker thread.
     *
     * @param token UTF-8 text chunk string.
     * @param is_done Flag indicating whether generation has finished.
     * @return true if enqueued successfully, false if the buffer is full.
     */
    bool try_push(const char* token, int is_done) {
        const size_t current_tail = tail_.load(std::memory_order_relaxed);
        const size_t current_head = head_.load(std::memory_order_acquire);

        // Check if buffer is full
        if (current_tail - current_head >= Capacity) {
            return false; // Ring buffer full
        }

        const size_t index = current_tail & (Capacity - 1);
        buffer_[index] = TokenChunk(token, is_done);

        // Publish written chunk with release semantics
        tail_.store(current_tail + 1, std::memory_order_release);
        return true;
    }

    /**
     * Consumer: Dequeues a token chunk from the ring buffer.
     * Called strictly from the Dart FFI polling / event loop thread.
     *
     * @param out_buf Destination character buffer.
     * @param max_len Size of destination buffer.
     * @param out_is_done Destination pointer for is_done flag.
     * @return true if a token was popped, false if the buffer is currently empty.
     */
    bool try_pop(char* out_buf, size_t max_len, int* out_is_done) {
        const size_t current_head = head_.load(std::memory_order_relaxed);
        const size_t current_tail = tail_.load(std::memory_order_acquire);

        // Check if buffer is empty
        if (current_head == current_tail) {
            return false; // Ring buffer empty
        }

        const size_t index = current_head & (Capacity - 1);
        const TokenChunk& chunk = buffer_[index];

        if (out_buf && max_len > 0) {
            size_t i = 0;
            while (chunk.text[i] != '\0' && i < max_len - 1) {
                out_buf[i] = chunk.text[i];
                i++;
            }
            out_buf[i] = '\0';
        }

        if (out_is_done) {
            *out_is_done = chunk.is_done;
        }

        // Advance head with release semantics
        head_.store(current_head + 1, std::memory_order_release);
        return true;
    }

    /**
     * Returns true if the ring buffer is empty.
     */
    bool is_empty() const {
        return head_.load(std::memory_order_acquire) == tail_.load(std::memory_order_acquire);
    }

    /**
     * Returns the approximate number of pending items in the ring buffer.
     */
    size_t size() const {
        const size_t head = head_.load(std::memory_order_relaxed);
        const size_t tail = tail_.load(std::memory_order_relaxed);
        return (tail >= head) ? (tail - head) : 0;
    }

    /**
     * Resets ring buffer indices.
     */
    void reset() {
        head_.store(0, std::memory_order_release);
        tail_.store(0, std::memory_order_release);
    }

private:
    // Align atomic variables on separate cache lines to avoid false sharing
    alignas(CACHE_LINE_SIZE) std::atomic<size_t> head_;
    alignas(CACHE_LINE_SIZE) std::atomic<size_t> tail_;

    TokenChunk* buffer_;
};

} // namespace receipt

#endif // RECEIPT_TOKEN_RING_H
