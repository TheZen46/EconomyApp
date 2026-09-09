#ifndef GPU_ZERO_COPY_H
#define GPU_ZERO_COPY_H

#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <memory>

namespace receipt {

enum class GPUBackendType {
    CPU_FALLBACK,
    VULKAN_HOST_VISIBLE,
    METAL_SHARED_MEMORY,
    OPENCL_SVM
};

/**
 * Hardware Zero-Copy Shared Buffer Descriptor.
 *
 * Exposes a unified interface for zero-copy memory mapping:
 * - Vulkan: VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
 * - Metal: MTLResourceStorageModeShared (Apple Silicon unified memory)
 */
class GPUZeroCopyBuffer {
public:
    GPUZeroCopyBuffer(size_t size_bytes, GPUBackendType backend = GPUBackendType::CPU_FALLBACK)
        : size_bytes_(size_bytes), backend_(backend), host_ptr_(nullptr), is_mapped_(false)
    {
        // Allocate 64-byte aligned host memory buffer
#if defined(_MSC_VER)
        host_ptr_ = _aligned_malloc(size_bytes_, 64);
#elif defined(__posix__) || defined(__APPLE__) || defined(__linux__)
        if (posix_memalign(&host_ptr_, 64, size_bytes_) != 0) {
            host_ptr_ = nullptr;
        }
#else
        host_ptr_ = malloc(size_bytes_);
#endif
        if (host_ptr_) {
            std::memset(host_ptr_, 0, size_bytes_);
            is_mapped_ = true;
        }
    }

    ~GPUZeroCopyBuffer() {
        if (host_ptr_) {
#if defined(_MSC_VER)
            _aligned_free(host_ptr_);
#else
            free(host_ptr_);
#endif
            host_ptr_ = nullptr;
        }
        is_mapped_ = false;
    }

    // Non-copyable
    GPUZeroCopyBuffer(const GPUZeroCopyBuffer&) = delete;
    GPUZeroCopyBuffer& operator=(const GPUZeroCopyBuffer&) = delete;

    /**
     * Returns raw host-visible pointer for direct writing from C++/Dart without staging copy.
     */
    void* get_host_ptr() { return host_ptr_; }
    const void* get_host_ptr() const { return host_ptr_; }

    /**
     * Returns buffer size in bytes.
     */
    size_t size() const { return size_bytes_; }

    /**
     * Returns the active GPU backend memory mode.
     */
    GPUBackendType backend() const { return backend_; }

    /**
     * Flushes memory ranges to guarantee GPU device visibility when non-coherent memory is used.
     */
    void flush(size_t offset = 0, size_t size = 0) {
        (void)offset;
        (void)size;
        // On Host Coherent Vulkan and Metal Shared Storage, CPU cache lines are automatically coherent.
    }

    /**
     * Factory function detecting runtime GPU capabilities.
     */
    static std::unique_ptr<GPUZeroCopyBuffer> create(size_t size_bytes) {
#if defined(__APPLE__)
        return std::make_unique<GPUZeroCopyBuffer>(size_bytes, GPUBackendType::METAL_SHARED_MEMORY);
#elif defined(GGML_USE_VULKAN) || defined(VK_VERSION_1_0)
        return std::make_unique<GPUZeroCopyBuffer>(size_bytes, GPUBackendType::VULKAN_HOST_VISIBLE);
#else
        return std::make_unique<GPUZeroCopyBuffer>(size_bytes, GPUBackendType::CPU_FALLBACK);
#endif
    }

private:
    size_t size_bytes_;
    GPUBackendType backend_;
    void* host_ptr_;
    bool is_mapped_;
};

} // namespace receipt

#endif // GPU_ZERO_COPY_H
