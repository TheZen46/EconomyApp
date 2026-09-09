#ifndef IMAGE_PREPROCESSOR_H
#define IMAGE_PREPROCESSOR_H

#include <stdint.h>
#include <stddef.h>
#include <vector>

namespace receipt {

/**
 * Decoded raw image representation in 8-bit RGB interleaved format.
 */
struct DecodedImage {
    int width = 0;
    int height = 0;
    int channels = 0; // Exactly 3 for RGB
    std::vector<uint8_t> data; // Contiguous row-major RGB pixel buffer (size: width * height * 3)

    bool isValid() const {
        return width > 0 && height > 0 && channels == 3 && !data.empty() &&
               data.size() == static_cast<size_t>(width) * height * 3;
    }
};

class ImagePreprocessor {
public:
    ImagePreprocessor() = default;
    ~ImagePreprocessor() = default;

    /**
     * Decodes raw compressed image bytes (JPEG, PNG, WebP, BMP) from memory into 8-bit RGB pixels.
     *
     * @param compressed_data Pointer to image bytes buffer.
     * @param compressed_len Length of the buffer in bytes.
     * @param out_image Destination DecodedImage struct.
     * @return true on success, false if the image data is corrupted or invalid.
     */
    static bool decodeImage(
        const uint8_t* compressed_data,
        size_t compressed_len,
        DecodedImage& out_image
    );

    /**
     * Resizes the image to target dimensions using SIMD (AVX2/NEON) and OpenMP multi-threading.
     *
     * @param input Source image.
     * @param target_width Target width in pixels.
     * @param target_height Target height in pixels.
     * @param output Destination resized image.
     * @return true on success, false on invalid parameters.
     */
    static bool resizeBilinear(
        const DecodedImage& input,
        int target_width,
        int target_height,
        DecodedImage& output
    );

    /**
     * Resizes and pads (letterboxes) the image to fit inside target dimensions while strictly
     * preserving the original aspect ratio. Pads borders symmetrically with SIMD/OpenMP acceleration.
     *
     * @param input Source image.
     * @param target_width Target bounding box width (e.g. 448).
     * @param target_height Target bounding box height (e.g. 448).
     * @param output Destination letterboxed image.
     * @param pad_value Padding fill color value (0-255, default: 128 / neutral gray).
     * @return true on success, false on invalid parameters.
     */
    static bool letterbox(
        const DecodedImage& input,
        int target_width,
        int target_height,
        DecodedImage& output,
        uint8_t pad_value = 128
    );

    /**
     * Converts uint8_t [0..255] RGB pixels into normalized float32 tensor for CLIP ViT vision encoder.
     * Uses AVX2 / ARM NEON vector instructions and OpenMP parallelization.
     *
     * CLIP Normalization Constants:
     * - Mean: [0.48145466, 0.4578275, 0.40821073] (R, G, B)
     * - Std:  [0.26862954, 0.26130258, 0.27577711] (R, G, B)
     *
     * @param input Source image.
     * @param out_floats Output vector of normalized float32 values.
     * @param planar If true, formats as [3, H, W] (CHW planar format). If false, [H, W, 3] (HWC).
     * @return true on success, false on invalid parameters.
     */
    static bool normalizeForClip(
        const DecodedImage& input,
        std::vector<float>& out_floats,
        bool planar = true
    );

    /**
     * Contrast Limited Adaptive Histogram Equalization (CLAHE).
     *
     * Enhances low-contrast thermal receipts by dividing the image into contextual grid tiles,
     * clipping histogram spikes to prevent noise over-amplification, and bilinearly interpolating
     * tile transfer functions with AVX2/NEON SIMD and OpenMP acceleration (< 15ms latency).
     *
     * @param input Source 8-bit RGB image.
     * @param output Destination enhanced RGB image.
     * @param clip_limit Contrast clipping limit (default: 3.0f).
     * @param grid_cols Number of horizontal contextual tiles (default: 8).
     * @param grid_rows Number of vertical contextual tiles (default: 8).
     * @return true on success, false on invalid parameters.
     */
    static bool applyCLAHE(
        const DecodedImage& input,
        DecodedImage& output,
        float clip_limit = 3.0f,
        int grid_cols = 8,
        int grid_rows = 8
    );

    /**
     * Runs a self-contained latency benchmark for 4K / 12MP image letterboxing and normalization.
     *
     * @param width Image width (default 3840 for 4K UHD).
     * @param height Image height (default 2160 for 4K UHD).
     * @param target_dim Target square resolution (default 448).
     * @return Preprocessing latency in milliseconds.
     */
    static double benchmarkPreprocessing(
        int width = 3840,
        int height = 2160,
        int target_dim = 448
    );

    /**
     * Runs a self-contained latency benchmark for SIMD CLAHE on high-res receipt images.
     *
     * @param width Image width (default 3840 for 4K UHD).
     * @param height Image height (default 2160 for 4K UHD).
     * @return CLAHE execution latency in milliseconds.
     */
    static double benchmarkCLAHE(
        int width = 3840,
        int height = 2160
    );
};

} // namespace receipt

#endif // IMAGE_PREPROCESSOR_H
