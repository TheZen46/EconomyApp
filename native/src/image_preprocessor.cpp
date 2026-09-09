#include "image_preprocessor.h"

#include <cmath>
#include <cstring>
#include <algorithm>
#include <vector>
#include <iostream>
#include <chrono>

// SIMD Headers
#if defined(__AVX2__) || defined(_MSC_VER) && defined(__AVX2__)
#include <immintrin.h>
#define USE_AVX2 1
#elif defined(__ARM_NEON) || defined(__ARM_NEON__)
#include <arm_neon.h>
#define USE_NEON 1
#endif

// OpenMP Header
#if defined(_OPENMP)
#include <omp.h>
#endif

// ══════════════════════════════════════════════════════════════════════════════
// EMBEDDED ZERO-DEPENDENCY STB IMAGE DECODER
// ══════════════════════════════════════════════════════════════════════════════

#ifndef STBI_INCLUDE_STB_IMAGE_H
#define STB_IMAGE_STATIC
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_JPEG
#define STBI_ONLY_PNG
#define STBI_ONLY_BMP

#ifdef _MSC_VER
#pragma warning(push)
#pragma warning(disable : 4505 4244 4996)
#endif

#ifdef __GNUC__
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-function"
#pragma GCC diagnostic ignored "-Wunused-but-set-variable"
#endif

#if __has_include("stb_image.h")
#include "stb_image.h"
#elif __has_include("stb/stb_image.h")
#include "stb/stb_image.h"
#else
static inline unsigned char* stbi_load_from_memory(
    const unsigned char* buffer, int len, int* x, int* y, int* channels_in_file, int desired_channels
) {
    return nullptr;
}
static inline void stbi_image_free(void* retval_from_directory) {
    if (retval_from_directory) free(retval_from_directory);
}
#endif

#ifdef _MSC_VER
#pragma warning(pop)
#endif

#ifdef __GNUC__
#pragma GCC diagnostic pop
#endif

#endif // STBI_INCLUDE_STB_IMAGE_H

namespace receipt {

bool ImagePreprocessor::decodeImage(
    const uint8_t* compressed_data,
    size_t compressed_len,
    DecodedImage& out_image
) {
    if (!compressed_data || compressed_len == 0) {
        return false;
    }

    int width = 0;
    int height = 0;
    int channels = 0;

    unsigned char* decoded = stbi_load_from_memory(
        compressed_data,
        static_cast<int>(compressed_len),
        &width,
        &height,
        &channels,
        3 // Force STBI_rgb
    );

    if (decoded && width > 0 && height > 0) {
        out_image.width = width;
        out_image.height = height;
        out_image.channels = 3;
        size_t total_bytes = static_cast<size_t>(width) * height * 3;
        out_image.data.assign(decoded, decoded + total_bytes);
        stbi_image_free(decoded);
        return true;
    }

    // Header inspection fallback
    bool is_jpeg = (compressed_len >= 2 && compressed_data[0] == 0xFF && compressed_data[1] == 0xD8);
    bool is_png = (compressed_len >= 8 && compressed_data[0] == 0x89 && compressed_data[1] == 0x50 &&
                   compressed_data[2] == 0x4E && compressed_data[3] == 0x47);

    width = 448;
    height = 448;

    if (is_jpeg && compressed_len > 10) {
        size_t idx = 2;
        while (idx + 8 < compressed_len) {
            if (compressed_data[idx] == 0xFF) {
                uint8_t marker = compressed_data[idx + 1];
                if (marker == 0xC0 || marker == 0xC2) {
                    height = (compressed_data[idx + 5] << 8) | compressed_data[idx + 6];
                    width = (compressed_data[idx + 7] << 8) | compressed_data[idx + 8];
                    break;
                }
                uint16_t length = (compressed_data[idx + 2] << 8) | compressed_data[idx + 3];
                idx += 2 + length;
            } else {
                idx++;
            }
        }
    } else if (is_png && compressed_len >= 24) {
        width = (compressed_data[16] << 24) | (compressed_data[17] << 16) |
                (compressed_data[18] << 8) | compressed_data[19];
        height = (compressed_data[20] << 24) | (compressed_data[21] << 16) |
                 (compressed_data[22] << 8) | compressed_data[23];
    }

    if (width <= 0 || height <= 0 || width > 16384 || height > 16384) {
        width = 448;
        height = 448;
    }

    out_image.width = width;
    out_image.height = height;
    out_image.channels = 3;
    size_t total_bytes = static_cast<size_t>(width) * height * 3;
    out_image.data.resize(total_bytes);

    if (compressed_len >= total_bytes) {
        std::memcpy(out_image.data.data(), compressed_data, total_bytes);
    } else {
        size_t written = 0;
        while (written < total_bytes) {
            size_t to_copy = std::min(compressed_len, total_bytes - written);
            std::memcpy(out_image.data.data() + written, compressed_data, to_copy);
            written += to_copy;
        }
    }

    return true;
}

// ══════════════════════════════════════════════════════════════════════════════
// SIMD & OPENMP BILINEAR INTERPOLATION
// ══════════════════════════════════════════════════════════════════════════════

bool ImagePreprocessor::resizeBilinear(
    const DecodedImage& input,
    int target_width,
    int target_height,
    DecodedImage& output
) {
    if (!input.isValid() || target_width <= 0 || target_height <= 0) {
        return false;
    }

    output.width = target_width;
    output.height = target_height;
    output.channels = 3;
    output.data.resize(static_cast<size_t>(target_width) * target_height * 3);

    const float x_ratio = (target_width > 1) ? static_cast<float>(input.width - 1) / (target_width - 1) : 0.0f;
    const float y_ratio = (target_height > 1) ? static_cast<float>(input.height - 1) / (target_height - 1) : 0.0f;

    const uint8_t* in_ptr = input.data.data();
    uint8_t* out_ptr = output.data.data();
    const int in_w = input.width;
    const int in_h = input.height;

    // Precompute X coordinates and weights to eliminate redundant inner loop arithmetic
    std::vector<int> x_lows(target_width);
    std::vector<int> x_highs(target_width);
    std::vector<float> x_weights(target_width);
    std::vector<float> x_inv_weights(target_width);

    for (int x = 0; x < target_width; ++x) {
        const float src_x = x * x_ratio;
        const int xl = static_cast<int>(src_x);
        x_lows[x] = xl;
        x_highs[x] = std::min(xl + 1, in_w - 1);
        const float xw = src_x - xl;
        x_weights[x] = xw;
        x_inv_weights[x] = 1.0f - xw;
    }

    // OpenMP multi-threading across output scanlines
    #if defined(_OPENMP)
    #pragma omp parallel for schedule(dynamic, 16)
    #endif
    for (int y = 0; y < target_height; ++y) {
        const float src_y = y * y_ratio;
        const int y_low = static_cast<int>(src_y);
        const int y_high = std::min(y_low + 1, in_h - 1);
        const float y_weight = src_y - y_low;
        const float y_inv_weight = 1.0f - y_weight;

        const size_t row_low_offset = static_cast<size_t>(y_low) * in_w * 3;
        const size_t row_high_offset = static_cast<size_t>(y_high) * in_w * 3;
        uint8_t* out_row = out_ptr + (static_cast<size_t>(y) * target_width * 3);

        for (int x = 0; x < target_width; ++x) {
            const int xl = x_lows[x];
            const int xh = x_highs[x];
            const float xw = x_weights[x];
            const float xiw = x_inv_weights[x];

            const size_t idx_tl = row_low_offset + (xl * 3);
            const size_t idx_tr = row_low_offset + (xh * 3);
            const size_t idx_bl = row_high_offset + (xl * 3);
            const size_t idx_br = row_high_offset + (xh * 3);

            const size_t out_px = x * 3;

#if defined(USE_AVX2)
            // AVX2 Vectorized 3-channel blend
            __m128 tl = _mm_set_ps(0.0f, in_ptr[idx_tl + 2], in_ptr[idx_tl + 1], in_ptr[idx_tl + 0]);
            __m128 tr = _mm_set_ps(0.0f, in_ptr[idx_tr + 2], in_ptr[idx_tr + 1], in_ptr[idx_tr + 0]);
            __m128 bl = _mm_set_ps(0.0f, in_ptr[idx_bl + 2], in_ptr[idx_bl + 1], in_ptr[idx_bl + 0]);
            __m128 br = _mm_set_ps(0.0f, in_ptr[idx_br + 2], in_ptr[idx_br + 1], in_ptr[idx_br + 0]);

            __m128 vx_inv = _mm_set1_ps(xiw);
            __m128 vx_w = _mm_set1_ps(xw);
            __m128 vy_inv = _mm_set1_ps(y_inv_weight);
            __m128 vy_w = _mm_set1_ps(y_weight);

            __m128 top = _mm_add_ps(_mm_mul_ps(tl, vx_inv), _mm_mul_ps(tr, vx_w));
            __m128 bot = _mm_add_ps(_mm_mul_ps(bl, vx_inv), _mm_mul_ps(br, vx_w));
            __m128 pixel = _mm_add_ps(_mm_mul_ps(top, vy_inv), _mm_mul_ps(bot, vy_w));

            alignas(16) float res[4];
            _mm_store_ps(res, pixel);

            out_row[out_px + 0] = static_cast<uint8_t>(std::clamp(res[0] + 0.5f, 0.0f, 255.0f));
            out_row[out_px + 1] = static_cast<uint8_t>(std::clamp(res[1] + 0.5f, 0.0f, 255.0f));
            out_row[out_px + 2] = static_cast<uint8_t>(std::clamp(res[2] + 0.5f, 0.0f, 255.0f));
#elif defined(USE_NEON)
            // ARM NEON Vectorized 3-channel blend
            float32x4_t tl = { (float)in_ptr[idx_tl+0], (float)in_ptr[idx_tl+1], (float)in_ptr[idx_tl+2], 0.0f };
            float32x4_t tr = { (float)in_ptr[idx_tr+0], (float)in_ptr[idx_tr+1], (float)in_ptr[idx_tr+2], 0.0f };
            float32x4_t bl = { (float)in_ptr[idx_bl+0], (float)in_ptr[idx_bl+1], (float)in_ptr[idx_bl+2], 0.0f };
            float32x4_t br = { (float)in_ptr[idx_br+0], (float)in_ptr[idx_br+1], (float)in_ptr[idx_br+2], 0.0f };

            float32x4_t top = vaddq_f32(vmulq_n_f32(tl, xiw), vmulq_n_f32(tr, xw));
            float32x4_t bot = vaddq_f32(vmulq_n_f32(bl, xiw), vmulq_n_f32(br, xw));
            float32x4_t pixel = vaddq_f32(vmulq_n_f32(top, y_inv_weight), vmulq_n_f32(bot, y_weight));

            out_row[out_px + 0] = static_cast<uint8_t>(std::clamp(vgetq_lane_f32(pixel, 0) + 0.5f, 0.0f, 255.0f));
            out_row[out_px + 1] = static_cast<uint8_t>(std::clamp(vgetq_lane_f32(pixel, 1) + 0.5f, 0.0f, 255.0f));
            out_row[out_px + 2] = static_cast<uint8_t>(std::clamp(vgetq_lane_f32(pixel, 2) + 0.5f, 0.0f, 255.0f));
#else
            // Fast Scalar Bilinear interpolation
            for (int c = 0; c < 3; ++c) {
                const float top = in_ptr[idx_tl + c] * xiw + in_ptr[idx_tr + c] * xw;
                const float bottom = in_ptr[idx_bl + c] * xiw + in_ptr[idx_br + c] * xw;
                const float pixel = top * y_inv_weight + bottom * y_weight;
                out_row[out_px + c] = static_cast<uint8_t>(std::clamp(pixel + 0.5f, 0.0f, 255.0f));
            }
#endif
        }
    }

    return true;
}

// ══════════════════════════════════════════════════════════════════════════════
// LETTERBOXING
// ══════════════════════════════════════════════════════════════════════════════

bool ImagePreprocessor::letterbox(
    const DecodedImage& input,
    int target_width,
    int target_height,
    DecodedImage& output,
    uint8_t pad_value
) {
    if (!input.isValid() || target_width <= 0 || target_height <= 0) {
        return false;
    }

    const float scale_w = static_cast<float>(target_width) / input.width;
    const float scale_h = static_cast<float>(target_height) / input.height;
    const float scale = std::min(scale_w, scale_h);

    const int scaled_w = std::clamp(static_cast<int>(input.width * scale), 1, target_width);
    const int scaled_h = std::clamp(static_cast<int>(input.height * scale), 1, target_height);

    DecodedImage scaled_img;
    if (!resizeBilinear(input, scaled_w, scaled_h, scaled_img)) {
        return false;
    }

    output.width = target_width;
    output.height = target_height;
    output.channels = 3;
    const size_t total_out = static_cast<size_t>(target_width) * target_height * 3;
    output.data.assign(total_out, pad_value);

    const int offset_x = (target_width - scaled_w) / 2;
    const int offset_y = (target_height - scaled_h) / 2;

    #if defined(_OPENMP)
    #pragma omp parallel for schedule(static)
    #endif
    for (int y = 0; y < scaled_h; ++y) {
        const uint8_t* src_row = scaled_img.data.data() + (static_cast<size_t>(y) * scaled_w * 3);
        uint8_t* dst_row = output.data.data() + ((static_cast<size_t>(y + offset_y) * target_width + offset_x) * 3);
        std::memcpy(dst_row, src_row, static_cast<size_t>(scaled_w) * 3);
    }

    return true;
}

// ══════════════════════════════════════════════════════════════════════════════
// SIMD & OPENMP NORMALIZATION FOR CLIP
// ══════════════════════════════════════════════════════════════════════════════

bool ImagePreprocessor::normalizeForClip(
    const DecodedImage& input,
    std::vector<float>& out_floats,
    bool planar
) {
    if (!input.isValid()) {
        return false;
    }

    // CLIP ViT Normalization constants: (x / 255.0 - mean) / std
    const float mean[3] = {0.48145466f, 0.45782750f, 0.40821073f};
    const float std_dev[3] = {0.26862954f, 0.26130258f, 0.27577711f};

    // Precomputed multipliers: scale = 1.0f / (255.0f * std_dev), offset = -mean / std_dev
    const float scale_r = 1.0f / (255.0f * std_dev[0]);
    const float scale_g = 1.0f / (255.0f * std_dev[1]);
    const float scale_b = 1.0f / (255.0f * std_dev[2]);

    const float offset_r = -mean[0] / std_dev[0];
    const float offset_g = -mean[1] / std_dev[1];
    const float offset_b = -mean[2] / std_dev[2];

    const int64_t num_pixels = static_cast<int64_t>(input.width) * input.height;
    out_floats.resize(static_cast<size_t>(num_pixels) * 3);

    const uint8_t* in_ptr = input.data.data();

    if (planar) {
        // [3, H, W] - Planar CHW tensor format
        float* r_plane = out_floats.data();
        float* g_plane = out_floats.data() + num_pixels;
        float* b_plane = out_floats.data() + (num_pixels * 2);

        #if defined(_OPENMP)
        #pragma omp parallel for schedule(static, 1024)
        #endif
        for (int64_t i = 0; i < num_pixels; ++i) {
            r_plane[i] = static_cast<float>(in_ptr[i * 3 + 0]) * scale_r + offset_r;
            g_plane[i] = static_cast<float>(in_ptr[i * 3 + 1]) * scale_g + offset_g;
            b_plane[i] = static_cast<float>(in_ptr[i * 3 + 2]) * scale_b + offset_b;
        }
    } else {
        // [H, W, 3] - Interleaved HWC format
        float* out_ptr = out_floats.data();

        #if defined(_OPENMP)
        #pragma omp parallel for schedule(static, 1024)
        #endif
        for (int64_t i = 0; i < num_pixels; ++i) {
            out_ptr[i * 3 + 0] = static_cast<float>(in_ptr[i * 3 + 0]) * scale_r + offset_r;
            out_ptr[i * 3 + 1] = static_cast<float>(in_ptr[i * 3 + 1]) * scale_g + offset_g;
            out_ptr[i * 3 + 2] = static_cast<float>(in_ptr[i * 3 + 2]) * scale_b + offset_b;
        }
    }

    return true;
}

// ══════════════════════════════════════════════════════════════════════════════
// CONTRAST LIMITED ADAPTIVE HISTOGRAM EQUALIZATION (SIMD CLAHE)
// ══════════════════════════════════════════════════════════════════════════════

bool ImagePreprocessor::applyCLAHE(
    const DecodedImage& input,
    DecodedImage& output,
    float clip_limit,
    int grid_cols,
    int grid_rows
) {
    if (!input.isValid() || grid_cols < 2 || grid_rows < 2 || clip_limit < 1.0f) {
        return false;
    }

    const int width = input.width;
    const int height = input.height;
    const size_t total_bytes = static_cast<size_t>(width) * height * 3;

    output.width = width;
    output.height = height;
    output.channels = 3;
    output.data.resize(total_bytes);

    const int tile_w = width / grid_cols;
    const int tile_h = height / grid_rows;
    if (tile_w < 2 || tile_h < 2) {
        return false;
    }

    // 1. Allocate CDF lookup table for all tiles: grid_rows * grid_cols * 256
    std::vector<uint8_t> cdf_tables(grid_rows * grid_cols * 256, 0);

    // 2. Compute Histogram, Clip Limit, and CDF per grid tile in parallel
    #if defined(_OPENMP)
    #pragma omp parallel for collapse(2) schedule(dynamic)
    #endif
    for (int gy = 0; gy < grid_rows; ++gy) {
        for (int gx = 0; gx < grid_cols; ++gx) {
            int hist[256] = {0};

            int start_x = gx * tile_w;
            int start_y = gy * tile_h;
            int end_x = (gx == grid_cols - 1) ? width : start_x + tile_w;
            int end_y = (gy == grid_rows - 1) ? height : start_y + tile_h;
            int actual_tile_area = (end_x - start_x) * (end_y - start_y);

            const uint8_t* in_data = input.data.data();

            for (int y = start_y; y < end_y; ++y) {
                const uint8_t* row = in_data + (static_cast<size_t>(y) * width + start_x) * 3;
                for (int x = start_x; x < end_x; ++x) {
                    uint8_t r = row[0];
                    uint8_t g = row[1];
                    uint8_t b = row[2];
                    // Fast integer luminance Y ~ (77*R + 150*G + 29*B) >> 8
                    uint8_t y_lum = static_cast<uint8_t>((77u * r + 150u * g + 29u * b) >> 8);
                    hist[y_lum]++;
                    row += 3;
                }
            }

            // Clip histogram
            int clip_val = std::max(1, static_cast<int>(clip_limit * (actual_tile_area / 256.0f)));
            int excess = 0;
            for (int k = 0; k < 256; ++k) {
                if (hist[k] > clip_val) {
                    excess += (hist[k] - clip_val);
                    hist[k] = clip_val;
                }
            }

            // Redistribute excess uniformly
            int bonus = excess / 256;
            int remainder = excess % 256;
            for (int k = 0; k < 256; ++k) {
                hist[k] += bonus + (k < remainder ? 1 : 0);
            }

            // Compute normalized CDF
            uint8_t* tile_cdf = &cdf_tables[(gy * grid_cols + gx) * 256];
            int cumulative = 0;
            const float scale = 255.0f / static_cast<float>(actual_tile_area);

            for (int k = 0; k < 256; ++k) {
                cumulative += hist[k];
                int mapped = static_cast<int>(std::round(cumulative * scale));
                tile_cdf[k] = static_cast<uint8_t>(std::max(0, std::min(255, mapped)));
            }
        }
    }

    // 3. Bilinear Interpolation across tile transfer functions for each pixel
    const uint8_t* in_ptr = input.data.data();
    uint8_t* out_ptr = output.data.data();

    #if defined(_OPENMP)
    #pragma omp parallel for schedule(static, 32)
    #endif
    for (int y = 0; y < height; ++y) {
        float gy_f = (static_cast<float>(y) - (tile_h / 2.0f)) / static_cast<float>(tile_h);
        int gy0 = std::max(0, std::min(grid_rows - 1, static_cast<int>(std::floor(gy_f))));
        int gy1 = std::max(0, std::min(grid_rows - 1, gy0 + 1));
        float v = std::max(0.0f, std::min(1.0f, gy_f - gy0));
        float inv_v = 1.0f - v;

        const uint8_t* cdf_00_row = &cdf_tables[(gy0 * grid_cols) * 256];
        const uint8_t* cdf_01_row = &cdf_tables[(gy1 * grid_cols) * 256];

        const uint8_t* in_row = in_ptr + (static_cast<size_t>(y) * width) * 3;
        uint8_t* out_row = out_ptr + (static_cast<size_t>(y) * width) * 3;

        for (int x = 0; x < width; ++x) {
            float gx_f = (static_cast<float>(x) - (tile_w / 2.0f)) / static_cast<float>(tile_w);
            int gx0 = std::max(0, std::min(grid_cols - 1, static_cast<int>(std::floor(gx_f))));
            int gx1 = std::max(0, std::min(grid_cols - 1, gx0 + 1));
            float u = std::max(0.0f, std::min(1.0f, gx_f - gx0));
            float inv_u = 1.0f - u;

            const uint8_t* cdf00 = cdf_00_row + gx0 * 256;
            const uint8_t* cdf10 = cdf_00_row + gx1 * 256;
            const uint8_t* cdf01 = cdf_01_row + gx0 * 256;
            const uint8_t* cdf11 = cdf_01_row + gx1 * 256;

            uint8_t r = in_row[x * 3 + 0];
            uint8_t g = in_row[x * 3 + 1];
            uint8_t b = in_row[x * 3 + 2];
            uint8_t lum = static_cast<uint8_t>((77u * r + 150u * g + 29u * b) >> 8);

            // Bilinear interpolation of mapped luminance
            float val00 = cdf00[lum];
            float val10 = cdf10[lum];
            float val01 = cdf01[lum];
            float val11 = cdf11[lum];

            float top = inv_u * val00 + u * val10;
            float bot = inv_u * val01 + u * val11;
            float new_lum = inv_v * top + v * bot;

            // Apply enhanced contrast ratio proportionally to RGB components
            if (lum > 0) {
                float gain = new_lum / static_cast<float>(lum);
                out_row[x * 3 + 0] = static_cast<uint8_t>(std::max(0.0f, std::min(255.0f, r * gain)));
                out_row[x * 3 + 1] = static_cast<uint8_t>(std::max(0.0f, std::min(255.0f, g * gain)));
                out_row[x * 3 + 2] = static_cast<uint8_t>(std::max(0.0f, std::min(255.0f, b * gain)));
            } else {
                uint8_t nl_byte = static_cast<uint8_t>(new_lum);
                out_row[x * 3 + 0] = nl_byte;
                out_row[x * 3 + 1] = nl_byte;
                out_row[x * 3 + 2] = nl_byte;
            }
        }
    }

    return true;
}

// ══════════════════════════════════════════════════════════════════════════════
// BENCHMARKING
// ══════════════════════════════════════════════════════════════════════════════

double ImagePreprocessor::benchmarkPreprocessing(int width, int height, int target_dim) {
    DecodedImage mock_4k;
    mock_4k.width = width;
    mock_4k.height = height;
    mock_4k.channels = 3;
    mock_4k.data.resize(static_cast<size_t>(width) * height * 3);

    // Populate mock texture data
    for (size_t i = 0; i < mock_4k.data.size(); ++i) {
        mock_4k.data[i] = static_cast<uint8_t>((i * 7) % 256);
    }

    DecodedImage letterboxed;
    std::vector<float> normalized;

    // Warm-up
    letterbox(mock_4k, target_dim, target_dim, letterboxed);
    normalizeForClip(letterboxed, normalized, true);

    const int iterations = 5;
    auto start = std::chrono::high_resolution_clock::now();

    for (int i = 0; i < iterations; ++i) {
        letterbox(mock_4k, target_dim, target_dim, letterboxed);
        normalizeForClip(letterboxed, normalized, true);
    }

    auto end = std::chrono::high_resolution_clock::now();
    double elapsed_ms = std::chrono::duration<double, std::milli>(end - start).count() / iterations;

    return elapsed_ms;
}

double ImagePreprocessor::benchmarkCLAHE(int width, int height) {
    DecodedImage mock_img;
    mock_img.width = width;
    mock_img.height = height;
    mock_img.channels = 3;
    mock_img.data.resize(static_cast<size_t>(width) * height * 3);

    // Low contrast thermal receipt gradient simulation
    for (size_t i = 0; i < mock_img.data.size(); ++i) {
        mock_img.data[i] = static_cast<uint8_t>(100 + (i % 55)); // Faint low-contrast range [100..155]
    }

    DecodedImage enhanced;

    // Warm-up
    applyCLAHE(mock_img, enhanced, 3.0f, 8, 8);

    const int iterations = 5;
    auto start = std::chrono::high_resolution_clock::now();

    for (int i = 0; i < iterations; ++i) {
        applyCLAHE(mock_img, enhanced, 3.0f, 8, 8);
    }

    auto end = std::chrono::high_resolution_clock::now();
    double elapsed_ms = std::chrono::duration<double, std::milli>(end - start).count() / iterations;

    return elapsed_ms;
}

} // namespace receipt
