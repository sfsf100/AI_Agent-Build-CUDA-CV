# ============================================================================
#  SAD Stereo Matching — CMake Build Configuration
# ============================================================================
#
#  建置步驟：
#    mkdir build
#    cd build
#    cmake ..
#    cmake --build . --config Release
#
#  執行：
#    ./sad_stereo <left_image> <right_image> [kernelSize] [searchRange]
#
# ============================================================================

cmake_minimum_required(VERSION 3.18)

# ── 專案名稱與語言 ──
project(SAD_StereoMatching LANGUAGES CXX CUDA)

# ── C++ 標準 ──
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── CUDA 設定 ──
# 自動偵測 GPU 架構；如需指定，取消下方註解並修改
# set(CMAKE_CUDA_ARCHITECTURES 86)   # RTX 3060 = SM 8.6
# set(CMAKE_CUDA_ARCHITECTURES 72)   # Jetson Xavier NX = SM 7.2

if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
    set(CMAKE_CUDA_ARCHITECTURES native)
endif()

# ── 尋找 OpenCV ──
find_package(OpenCV REQUIRED)

if(OpenCV_FOUND)
    message(STATUS "OpenCV version: ${OpenCV_VERSION}")
    message(STATUS "OpenCV include: ${OpenCV_INCLUDE_DIRS}")
else()
    message(FATAL_ERROR "OpenCV not found! Please install OpenCV 4.x+")
endif()

# ── 建立執行檔 ──
add_executable(sad_stereo
    main.cpp
    sad_kernel.cu
)

# ── Include 路徑 ──
target_include_directories(sad_stereo PRIVATE
    ${OpenCV_INCLUDE_DIRS}
    ${CMAKE_CUDA_TOOLKIT_INCLUDE_DIRECTORIES}
)

# ── 連結函式庫 ──
target_link_libraries(sad_stereo PRIVATE
    ${OpenCV_LIBS}
)

# ── CUDA 編譯選項 ──
target_compile_options(sad_stereo PRIVATE
    $<$<COMPILE_LANGUAGE:CUDA>:
        --expt-relaxed-constexpr
    >
)

# ── Release 模式最佳化 ──
if(CMAKE_BUILD_TYPE STREQUAL "Release" OR NOT CMAKE_BUILD_TYPE)
    target_compile_options(sad_stereo PRIVATE
        $<$<COMPILE_LANGUAGE:CXX>:-O2>
        $<$<COMPILE_LANGUAGE:CUDA>:-O2>
    )
endif()

# ── 印出建置資訊 ──
message(STATUS "")
message(STATUS "═══════════════════════════════════════")
message(STATUS "  SAD Stereo Matching Build Config")
message(STATUS "═══════════════════════════════════════")
message(STATUS "  CUDA Architectures : ${CMAKE_CUDA_ARCHITECTURES}")
message(STATUS "  OpenCV Version     : ${OpenCV_VERSION}")
message(STATUS "  Build Type         : ${CMAKE_BUILD_TYPE}")
message(STATUS "═══════════════════════════════════════")
message(STATUS "")
