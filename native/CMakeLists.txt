cmake_minimum_required(VERSION 3.14)
project(receipt_engine LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# ══════════════════════════════════════════════════════════════════════════════
# ACCELERATION OPTIONS & BACKENDS
# ══════════════════════════════════════════════════════════════════════════════
option(GGML_USE_VULKAN "Enable Vulkan GPU backend for Windows, Linux, and Android" ON)
option(GGML_USE_METAL  "Enable Apple Metal GPU backend for macOS and iOS" ON)
option(GGML_USE_OPENMP "Enable OpenMP multi-threading acceleration" ON)
option(GGML_USE_OPENCL "Enable OpenCL backend for Android Adreno/Mali GPUs" OFF)

# Source and Header files
set(SOURCES
    src/receipt_engine.cpp
    src/image_preprocessor.cpp
)

set(HEADERS
    src/receipt_engine.h
    src/image_preprocessor.h
    src/paged_kv_cache.h
    src/receipt_token_ring.h
    src/gpu_zero_copy.h
    src/hnsw_vector_index.h
)

# Build Shared Library
add_library(receipt_engine SHARED ${SOURCES} ${HEADERS})

target_compile_definitions(receipt_engine PRIVATE RECEIPT_ENGINE_EXPORTS)
target_include_directories(receipt_engine PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src")

# ══════════════════════════════════════════════════════════════════════════════
# SIMD & COMPILER OPTIMIZATIONS (AVX2, FMA, NEON, OpenMP)
# ══════════════════════════════════════════════════════════════════════════════
if(MSVC)
    target_compile_options(receipt_engine PRIVATE 
        $<$<NOT:$<CONFIG:Debug>>:/O2>
        /arch:AVX2 /fp:fast
    )
    if(GGML_USE_OPENMP)
        find_package(OpenMP)
        if(OpenMP_CXX_FOUND)
            target_link_libraries(receipt_engine PRIVATE OpenMP::OpenMP_CXX)
        else()
            target_compile_options(receipt_engine PRIVATE /openmp)
        endif()
    endif()
else()
    target_compile_options(receipt_engine PRIVATE -O3 -ffast-math)
    
    # Check Architecture for SIMD Vectorization
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "(x86_64|AMD64|i686)")
        target_compile_options(receipt_engine PRIVATE -mavx2 -mfma -mpopcnt)
        target_compile_definitions(receipt_engine PRIVATE __AVX2__=1)
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "(arm64|aarch64|ARM64)")
        target_compile_options(receipt_engine PRIVATE -march=armv8-a+simd)
        target_compile_definitions(receipt_engine PRIVATE __ARM_NEON=1)
    endif()

    if(GGML_USE_OPENMP)
        find_package(OpenMP)
        if(OpenMP_CXX_FOUND)
            target_link_libraries(receipt_engine PRIVATE OpenMP::OpenMP_CXX)
            target_compile_definitions(receipt_engine PRIVATE _OPENMP=1)
        else()
            target_compile_options(receipt_engine PRIVATE -fopenmp)
            target_link_libraries(receipt_engine PRIVATE -fopenmp)
        endif()
    endif()
endif()

# ══════════════════════════════════════════════════════════════════════════════
# PLATFORM-SPECIFIC GPU BACKENDS & LINKING
# ══════════════════════════════════════════════════════════════════════════════
if(WIN32)
    target_compile_definitions(receipt_engine PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
    if(GGML_USE_VULKAN)
        target_compile_definitions(receipt_engine PRIVATE GGML_USE_VULKAN=1)
        find_package(Vulkan QUIET)
        if(Vulkan_FOUND)
            target_link_libraries(receipt_engine PRIVATE Vulkan::Vulkan)
        endif()
    endif()

elseif(APPLE)
    set_target_properties(receipt_engine PROPERTIES
        MACOSX_RPATH ON
        INSTALL_NAME_DIR "@rpath"
    )
    if(GGML_USE_METAL)
        target_compile_definitions(receipt_engine PRIVATE GGML_USE_METAL=1)
        find_library(METAL_LIB Metal REQUIRED)
        find_library(FOUNDATION_LIB Foundation REQUIRED)
        find_library(METALKIT_LIB MetalKit QUIET)
        target_link_libraries(receipt_engine PRIVATE ${METAL_LIB} ${FOUNDATION_LIB})
        if(METALKIT_LIB)
            target_link_libraries(receipt_engine PRIVATE ${METALKIT_LIB})
        endif()
    endif()

elseif(ANDROID)
    target_link_libraries(receipt_engine PRIVATE log android)
    if(GGML_USE_VULKAN)
        target_compile_definitions(receipt_engine PRIVATE GGML_USE_VULKAN=1)
        target_link_libraries(receipt_engine PRIVATE vulkan)
    elseif(GGML_USE_OPENCL)
        target_compile_definitions(receipt_engine PRIVATE GGML_USE_OPENCL=1)
        target_link_libraries(receipt_engine PRIVATE OpenCL)
    endif()

elseif(UNIX AND NOT APPLE)
    target_link_libraries(receipt_engine PRIVATE pthread dl)
    if(GGML_USE_VULKAN)
        target_compile_definitions(receipt_engine PRIVATE GGML_USE_VULKAN=1)
        find_package(Vulkan QUIET)
        if(Vulkan_FOUND)
            target_link_libraries(receipt_engine PRIVATE Vulkan::Vulkan)
        endif()
    endif()
endif()

# ══════════════════════════════════════════════════════════════════════════════
# INSTALLATION RULES
# ══════════════════════════════════════════════════════════════════════════════
# ══════════════════════════════════════════════════════════════════════════════
# TEST & BENCHMARK EXECUTABLES
# ══════════════════════════════════════════════════════════════════════════════
add_executable(native_engine_test
    test/native_engine_test.cpp
    src/image_preprocessor.cpp
    src/receipt_engine.cpp
)
target_include_directories(native_engine_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
if(MSVC)
    target_compile_options(native_engine_test PRIVATE 
        $<$<NOT:$<CONFIG:Debug>>:/O2>
        /arch:AVX2 /fp:fast
    )
    if(GGML_USE_OPENMP)
        find_package(OpenMP)
        if(OpenMP_CXX_FOUND)
            target_link_libraries(native_engine_test PRIVATE OpenMP::OpenMP_CXX)
        else()
            target_compile_options(native_engine_test PRIVATE /openmp)
        endif()
    endif()
else()
    target_compile_options(native_engine_test PRIVATE -O3 -ffast-math)
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "(x86_64|AMD64|i686)")
        target_compile_options(native_engine_test PRIVATE -mavx2 -mfma -mpopcnt)
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "(arm64|aarch64|ARM64)")
        target_compile_options(native_engine_test PRIVATE -march=armv8-a+simd)
    endif()
    if(GGML_USE_OPENMP)
        find_package(OpenMP)
        if(OpenMP_CXX_FOUND)
            target_link_libraries(native_engine_test PRIVATE OpenMP::OpenMP_CXX)
        else()
            target_compile_options(native_engine_test PRIVATE -fopenmp)
            target_link_libraries(native_engine_test PRIVATE -fopenmp)
        endif()
    endif()
endif()

if(DEFINED CMAKE_INSTALL_PREFIX)
    install(TARGETS receipt_engine
        RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
        LIBRARY DESTINATION "${CMAKE_INSTALL_PREFIX}"
        ARCHIVE DESTINATION "${CMAKE_INSTALL_PREFIX}"
    )
else()
    install(TARGETS receipt_engine
        LIBRARY DESTINATION lib
        ARCHIVE DESTINATION lib
        RUNTIME DESTINATION bin
    )
endif()
