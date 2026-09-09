cmake_minimum_required(VERSION 3.16)
project(receipt_engine LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Optimization Flags
if(MSVC)
    add_compile_options(/O2 /W4 /fp:fast)
else()
    add_compile_options(-O3 -Wall -Wextra -ffast-math)
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "arm|aarch64")
        add_compile_options(-march=armv8-a+simd)
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64")
        add_compile_options(-mavx2 -mfma)
    endif()
endif()

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

add_library(receipt_engine SHARED
    src/receipt_engine.cpp
)

set_target_properties(receipt_engine PROPERTIES
    OUTPUT_NAME "receipt_engine"
    PREFIX ""
)

# Export headers
target_include_directories(receipt_engine PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)
