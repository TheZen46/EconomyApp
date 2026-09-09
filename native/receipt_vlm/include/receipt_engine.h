/**
 * Zero-Copy Native C FFI Interface for On-Device Receipt VLM Engine.
 * Thread-safe wrapper over llama.cpp / clip.cpp.
 */

#ifndef RECEIPT_ENGINE_H
#define RECEIPT_ENGINE_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
  #define RECEIPT_API __declspec(dllexport)
#else
  #define RECEIPT_API __attribute__((visibility("default")))
#endif

// Status Error Codes
#define RECEIPT_SUCCESS             0
#define RECEIPT_ERR_MODEL_INIT     -1
#define RECEIPT_ERR_IMAGE_DECODE   -2
#define RECEIPT_ERR_INFERENCE      -3
#define RECEIPT_ERR_BUFFER_OVERFLOW -4
#define RECEIPT_ERR_INVALID_PARAM  -5

/**
 * Initializes the quantized VLM engine, mmap-ing model weights and allocating KV cache.
 *
 * @param model_path Path to the GGUF model file on disk.
 * @param n_threads Number of CPU execution threads (recommended: physical core count).
 * @param n_gpu_layers Number of layers to offload to GPU/NPU (0 = pure CPU).
 * @return RECEIPT_SUCCESS (0) on success, or negative error code.
 */
RECEIPT_API int receipt_engine_init(
    const char* model_path,
    int n_threads,
    int n_gpu_layers
);

/**
 * Executes multimodal spatial inference with GBNF grammar constraints.
 * Operates directly on the in-memory image buffer without disk roundtripping.
 *
 * @param image_bytes Pointer to raw compressed image buffer (JPEG/PNG/WebP).
 * @param len Size of the image buffer in bytes.
 * @param few_shot_context Optional dynamically retrieved few-shot examples (can be NULL or empty).
 * @param output_buffer Pre-allocated char buffer to receive output JSON.
 * @param max_len Capacity of the output buffer.
 * @return Number of characters written on success, or negative error code.
 */
RECEIPT_API int receipt_engine_process_image(
    const uint8_t* image_bytes,
    size_t len,
    const char* few_shot_context,
    char* output_buffer,
    size_t max_len
);

/**
 * Returns current memory RSS and VRAM statistics.
 *
 * @param out_ram_bytes Pointer to receive current RAM usage in bytes.
 * @param out_vram_bytes Pointer to receive current VRAM usage in bytes.
 */
RECEIPT_API void receipt_engine_get_memory_stats(
    uint64_t* out_ram_bytes,
    uint64_t* out_vram_bytes
);

/**
 * Safely releases model context, KV caches, and multimodal projector resources.
 */
RECEIPT_API void receipt_engine_free(void);

#ifdef __cplusplus
}
#endif

#endif // RECEIPT_ENGINE_H
