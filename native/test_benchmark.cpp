#include "src/image_preprocessor.h"
#include <iostream>
#include <iomanip>

int main() {
    std::cout << "==================================================================" << std::endl;
    std::cout << " Native Preprocessor Benchmark: 4K UHD (3840x2160) -> 448x448 CLIP" << std::endl;
    std::cout << " Accelerations: AVX2 SIMD + OpenMP Multi-Threading" << std::endl;
    std::cout << "==================================================================" << std::endl;

    double latency_ms = receipt::ImagePreprocessor::benchmarkPreprocessing(3840, 2160, 448);

    std::cout << std::fixed << std::setprecision(2);
    std::cout << "Average Preprocessing Latency (4K): " << latency_ms << " ms" << std::endl;

    if (latency_ms < 35.0) {
        std::cout << "[SUCCESS] Preprocessing latency is below the 35ms target threshold!" << std::endl;
        std::cout << "==================================================================" << std::endl;
        return 0;
    } else {
        std::cout << "[WARNING] Preprocessing latency exceeded 35ms: " << latency_ms << " ms" << std::endl;
        std::cout << "==================================================================" << std::endl;
        return 1;
    }
}
