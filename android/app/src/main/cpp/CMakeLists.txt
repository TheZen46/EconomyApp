cmake_minimum_required(VERSION 3.14)
project(receipt_engine LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Define source directory for native C++ engine
set(NATIVE_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../native/src")

# Native source and header files
set(SOURCES
    "${NATIVE_SRC_DIR}/receipt_engine.cpp"
    "${NATIVE_SRC_DIR}/image_preprocessor.cpp"
)

set(HEADERS
    "${NATIVE_SRC_DIR}/receipt_engine.h"
    "${NATIVE_SRC_DIR}/image_preprocessor.h"
)

# Shared library for Android JNI / Dart FFI (libreceipt_engine.so)
add_library(receipt_engine SHARED ${SOURCES} ${HEADERS})

target_compile_definitions(receipt_engine PRIVATE RECEIPT_ENGINE_EXPORTS)
target_include_directories(receipt_engine PUBLIC "${NATIVE_SRC_DIR}")

# Architecture optimizations for Android
target_compile_options(receipt_engine PRIVATE -O3 -ffast-math)

if(ANDROID_ABI STREQUAL "arm64-v8a")
    target_compile_options(receipt_engine PRIVATE -march=armv8-a+simd)
    target_compile_definitions(receipt_engine PRIVATE __ARM_NEON=1)
elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
    target_compile_options(receipt_engine PRIVATE -march=armv7-a -mfloat-abi=softfp -mfpu=neon)
    target_compile_definitions(receipt_engine PRIVATE __ARM_NEON=1)
elseif(ANDROID_ABI STREQUAL "x86_64")
    target_compile_options(receipt_engine PRIVATE -mavx2 -mfma)
    target_compile_definitions(receipt_engine PRIVATE __AVX2__=1)
endif()

# Find OpenMP in NDK if available
find_package(OpenMP)
if(OpenMP_CXX_FOUND)
    target_link_libraries(receipt_engine PRIVATE OpenMP::OpenMP_CXX)
    target_compile_definitions(receipt_engine PRIVATE _OPENMP=1)
else()
    target_compile_options(receipt_engine PRIVATE -fopenmp)
    target_link_libraries(receipt_engine PRIVATE -fopenmp)
endif()

# Link Android system libraries
find_library(log-lib log)
find_library(android-lib android)
find_library(vulkan-lib vulkan)

target_link_libraries(receipt_engine PRIVATE
    ${log-lib}
    ${android-lib}
)

if(vulkan-lib)
    target_compile_definitions(receipt_engine PRIVATE GGML_USE_VULKAN=1)
    target_link_libraries(receipt_engine PRIVATE ${vulkan-lib})
endif()
