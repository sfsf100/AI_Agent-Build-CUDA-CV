/**
 * ============================================================================
 *  SAD Stereo Matching — 驗證版（Verified Version）
 * ============================================================================
 *
 *  本檔案融合：
 *    - references/SAD.cu 的原始演算法邏輯與程式風格
 *    - scripts/sad_kernel.cu 的安全性、彈性與最佳實務
 *
 *  改進摘要：
 *    1. kernelSize / searchRange 改為參數（保留預設值 7 / 60）
 *    2. 新增右圖越界保護
 *    3. 初始 SAD 改用 INT_MAX
 *    4. 加入 CUDA 錯誤檢查
 *    5. cudaEventRecord(start) 移至 kernel launch 之前
 *    6. 邊界像素明確寫入 0
 *    7. 保留 main() 方便直接執行測試
 * ============================================================================
 */

#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include <cuda.h>
#include "opencv2/imgproc/imgproc.hpp"
#include <opencv2/highgui.hpp>
#include <iostream>
#include <string>
#include <cstdio>
#include <climits>

/* ── CUDA 錯誤檢查巨集 ── */
#define CUDA_CHECK(call)                                                       \
    do {                                                                       \
        cudaError_t err = call;                                                \
        if (err != cudaSuccess) {                                              \
            fprintf(stderr, "[CUDA Error] %s:%d — %s\n",                      \
                    __FILE__, __LINE__, cudaGetErrorString(err));               \
            exit(EXIT_FAILURE);                                                \
        }                                                                      \
    } while (0)

#define BLOCK_SIZE 32

using namespace std;
using namespace cv;

/* ═══════════════════════════════════════════════════════════════════════════
 *  SAD Kernel（GPU 核心運算）
 *
 *  對應原始 SAD.cu 的核心邏輯，增加以下改進：
 *  - kernelSize / searchRange 改為參數
 *  - 邊界像素明確寫入 0
 *  - 右圖越界保護 (x + d + half >= width 時 break)
 *  - 初始 SAD 改用 INT_MAX
 * ═══════════════════════════════════════════════════════════════════════════ */
__global__ void SAD(
    const unsigned char* __restrict__ srcImage,
    const unsigned char* __restrict__ srcImage2,
    unsigned char* dstImage,
    unsigned int width,
    unsigned int height,
    int kernelSize,
    int searchRange
)
{
    int x = blockIdx.x * blockDim.x + threadIdx.x;  // 核心座標
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    int half = (kernelSize - 1) / 2;

    // 超出影像範圍的 thread 直接結束
    if (x >= (int)width || y >= (int)height) {
        return;
    }

    // 邊界像素無法取完整窗口，設為 0
    if (x < half || x >= (int)(width - half) ||
        y < half || y >= (int)(height - half))
    {
        dstImage[y * width + x] = 0;
        return;
    }

    int min_sad = INT_MAX;  // SAD 最小值（改用 INT_MAX 取代原本的 100000）
    int minx = 0;           // 灰階差值最小時的位移量

    for (int r = 0; r < searchRange; r++)  // search range
    {
        // ★ 新增：右圖越界保護
        if (x + r + half >= (int)width) {
            break;
        }

        int error = 0;
        for (int a = -half; a <= half; a++) {
            for (int b = -half; b <= half; b++) {
                error += abs(srcImage[((y + a) * width + (x + b))]
                           - srcImage2[((y + a) * width + (x + r + b))]);
            }
        }
        if (error < min_sad) {
            min_sad = error;
            minx = r;
        }
    }
    dstImage[(y * width + x)] = minx;
}

/* ═══════════════════════════════════════════════════════════════════════════
 *  SAD_GPU — Host API
 *
 *  改進：
 *  - 輸入驗證（影像非空、尺寸一致、灰階檢查）
 *  - CUDA API 錯誤檢查
 *  - cudaEventRecord(start) 移至 kernel launch 之前
 *  - kernelSize / searchRange 作為參數
 * ═══════════════════════════════════════════════════════════════════════════ */
void SAD_GPU(const Mat& input, const Mat& input2, Mat& output,
             int kernelSize = 7, int searchRange = 60)
{
    /* ── 輸入驗證 ── */
    if (input.empty() || input2.empty()) {
        fprintf(stderr, "[Error] Empty input image.\n");
        return;
    }
    if (input.size() != input2.size()) {
        fprintf(stderr, "[Error] Image size mismatch: (%dx%d) vs (%dx%d).\n",
                input.cols, input.rows, input2.cols, input2.rows);
        return;
    }
    if (input.type() != CV_8UC1 || input2.type() != CV_8UC1) {
        fprintf(stderr, "[Error] Images must be grayscale (CV_8UC1).\n");
        return;
    }
    if (kernelSize < 3 || kernelSize > 15 || kernelSize % 2 == 0) {
        fprintf(stderr, "[Error] kernelSize must be odd in [3, 15]. Got: %d\n", kernelSize);
        return;
    }
    if (searchRange < 1 || searchRange > 128) {
        fprintf(stderr, "[Error] searchRange must be in [1, 128]. Got: %d\n", searchRange);
        return;
    }

    /* ── 計時器 ── */
    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);
    double time0 = static_cast<double>(getTickCount());  // 計時器開始

    /* ── 計算大小 ── */
    const int inputSize = input.cols * input.rows;
    const int outputSize = output.cols * output.rows;
    unsigned char* d_input;
    unsigned char* d_output;
    unsigned char* d_input2;

    /* ── 分配 GPU 記憶體 ── */
    CUDA_CHECK(cudaMalloc<unsigned char>(&d_input, inputSize));
    CUDA_CHECK(cudaMalloc<unsigned char>(&d_input2, inputSize));
    CUDA_CHECK(cudaMalloc<unsigned char>(&d_output, outputSize));

    /* ── Host → Device 複製 ── */
    CUDA_CHECK(cudaMemcpy(d_input, input.ptr(), inputSize, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_input2, input2.ptr(), inputSize, cudaMemcpyHostToDevice));

    // 清零輸出（確保邊界像素為 0）
    CUDA_CHECK(cudaMemset(d_output, 0, outputSize));

    /* ── 設定 Block / Grid ── */
    const dim3 block(BLOCK_SIZE, BLOCK_SIZE);
    const dim3 grid((output.cols + block.x - 1) / block.x,
                    (output.rows + block.y - 1) / block.y);

    /* ── ★ 修正：先記錄 start，再啟動 kernel ── */
    cudaEventRecord(start);

    SAD<<<grid, block>>>(d_input, d_input2, d_output,
                         output.cols, output.rows,
                         kernelSize, searchRange);

    // 檢查 kernel 啟動錯誤
    CUDA_CHECK(cudaGetLastError());

    /* ── 記錄 stop ── */
    cudaEventRecord(stop);

    /* ── Device → Host 複製 ── */
    CUDA_CHECK(cudaMemcpy(output.ptr(), d_output, outputSize, cudaMemcpyDeviceToHost));

    /* ── 釋放 GPU 記憶體 ── */
    CUDA_CHECK(cudaFree(d_input));
    CUDA_CHECK(cudaFree(d_input2));
    CUDA_CHECK(cudaFree(d_output));

    /* ── 計時輸出 ── */
    cudaEventSynchronize(stop);
    float milliseconds = 0;
    cudaEventElapsedTime(&milliseconds, start, stop);
    printf("GPU Event 計時：%.3f ms\n", milliseconds);

    time0 = ((double)getTickCount() - time0) / getTickFrequency();
    printf("GPU 的運算時間：%f s\n", time0);

    cudaEventDestroy(start);
    cudaEventDestroy(stop);
}

/* ═══════════════════════════════════════════════════════════════════════════
 *  main() — 保留原始測試流程
 * ═══════════════════════════════════════════════════════════════════════════ */
int main(int argc, char* argv[])
{
    /* ── 預設路徑（可用命令列參數覆寫）── */
    string leftPath  = (argc > 1) ? argv[1] : "im2.png";
    string rightPath = (argc > 2) ? argv[2] : "im1.png";
    string outPath   = (argc > 3) ? argv[3] : "depth_map.png";
    int kernelSize   = (argc > 4) ? atoi(argv[4]) : 7;
    int searchRange  = (argc > 5) ? atoi(argv[5]) : 60;

    Mat img1 = imread(leftPath, 1);
    Mat img2 = imread(rightPath, 1);

    if (img1.empty()) {
        fprintf(stderr, "[Error] Cannot open left image: %s\n", leftPath.c_str());
        return -1;
    }
    if (img2.empty()) {
        fprintf(stderr, "[Error] Cannot open right image: %s\n", rightPath.c_str());
        return -1;
    }

    Mat depth_map = Mat::zeros(img2.rows, img2.cols, CV_8U);
    cvtColor(img1, img1, COLOR_BGR2GRAY);
    cvtColor(img2, img2, COLOR_BGR2GRAY);

    printf("影像大小：%d x %d\n", img1.cols, img1.rows);
    printf("KernelSize：%d, SearchRange：%d\n", kernelSize, searchRange);

    SAD_GPU(img1, img2, depth_map, kernelSize, searchRange);

    imwrite(outPath, depth_map);
    printf("深度圖已儲存至：%s\n", outPath.c_str());

    return 0;
}
