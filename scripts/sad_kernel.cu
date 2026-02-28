/**
 * ============================================================================
 *  SAD Stereo Matching — CUDA Implementation
 * ============================================================================
 *  根據 SAD_SKILL.md 規格書實作
 *
 *  功能：使用 GPU 加速的 SAD (Sum of Absolute Differences) 演算法，
 *        從校正過的立體影像對計算視差圖（disparity map）。
 *
 *  檔案結構：
 *    1. CUDA 錯誤檢查巨集
 *    2. SAD Kernel（GPU 核心運算）
 *    3. SAD_GPU（對外 API，處理記憶體搬移）
 *    4. SAD_CPU（CPU 對照版本，用於驗證與效能比較）
 * ============================================================================
 */

#include <opencv2/opencv.hpp>
#include <cuda_runtime.h>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <chrono>

/* ═══════════════════════════════════════════════════════════════════════════
 *  Section 1: CUDA 錯誤檢查巨集
 * ═══════════════════════════════════════════════════════════════════════════ */

/**
 * CUDA_CHECK — 每次呼叫 CUDA API 後用來檢查是否成功
 *
 * 如果發生錯誤，會印出：
 *   - 出錯的檔案名稱和行號
 *   - CUDA 的錯誤訊息（英文）
 *
 * 用法：
 *   CUDA_CHECK(cudaMalloc(&ptr, size));
 *   CUDA_CHECK(cudaMemcpy(dst, src, size, cudaMemcpyHostToDevice));
 */
#define CUDA_CHECK(call)                                                       \
    do {                                                                       \
        cudaError_t err = call;                                                \
        if (err != cudaSuccess) {                                              \
            fprintf(stderr, "[CUDA Error] %s:%d — %s\n",                      \
                    __FILE__, __LINE__, cudaGetErrorString(err));               \
            exit(EXIT_FAILURE);                                                \
        }                                                                      \
    } while (0)

/* ═══════════════════════════════════════════════════════════════════════════
 *  Section 2: SAD Kernel（GPU 核心運算）
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  對應 SAD_SKILL.md 的 Algorithm > Pseudocode 章節。
 *
 *  每個 GPU thread 負責計算輸出視差圖的「一個像素」：
 *    1. 檢查邊界
 *    2. 對 searchRange 個候選視差逐一計算 SAD
 *    3. 取 SAD 最小值對應的視差寫入輸出
 *
 *  Thread 分配方式（對應 Parallelization Strategy）：
 *    x = blockIdx.x * blockDim.x + threadIdx.x
 *    y = blockIdx.y * blockDim.y + threadIdx.y
 */
__global__ void SAD_kernel(
    const unsigned char* __restrict__ leftImage,   // 左圖（灰階，H×W）
    const unsigned char* __restrict__ rightImage,  // 右圖（灰階，H×W）
    unsigned char*       disparityMap,             // 輸出視差圖（H×W）
    int width,                                      // 影像寬度
    int height,                                     // 影像高度
    int kernelSize,                                 // 匹配窗口邊長（奇數）
    int searchRange                                 // 最大搜尋範圍
)
{
    /* ── 計算此 thread 對應的像素座標 ── */
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;

    /* ── 超出影像範圍的 thread 直接結束 ── */
    if (x >= width || y >= height) {
        return;
    }

    int half = (kernelSize - 1) / 2;

    /* ══════════════════════════════════════════════════════════════════════
     *  邊界檢查（對應 SAD_SKILL.md > Edge Cases > Boundary Handling）
     *
     *  策略：Skip Border（推薦）
     *  - 邊界像素無法提取完整窗口，直接設為 0（無效）
     *  - 有效範圍：x ∈ [half, width-half)，y ∈ [half, height-half)
     * ══════════════════════════════════════════════════════════════════════ */
    if (x < half || x >= width - half ||
        y < half || y >= height - half) {
        disparityMap[y * width + x] = 0;
        return;
    }

    /* ══════════════════════════════════════════════════════════════════════
     *  核心匹配邏輯（對應 SAD_SKILL.md > Algorithm > Detailed Logic）
     *
     *  對每個候選視差 d (0 ~ searchRange-1)：
     *    1. 在左圖以 (x, y) 為中心取 kernelSize×kernelSize 窗口
     *    2. 在右圖以 (x+d, y) 為中心取同樣窗口
     *    3. 計算兩窗口的 SAD（絕對差值總和）
     *    4. 保留 SAD 最小的 d 作為結果
     * ══════════════════════════════════════════════════════════════════════ */
    int minSAD = INT_MAX;      // 目前找到的最小 SAD 值
    int bestDisparity = 0;     // 對應的最佳視差

    for (int d = 0; d < searchRange; d++) {

        /* 確保右圖窗口不超出影像右邊界 */
        if (x + d + half >= width) {
            break;
        }

        int currentSAD = 0;

        /* ── 遍歷窗口內的每個像素 ── */
        for (int dy = -half; dy <= half; dy++) {
            for (int dx = -half; dx <= half; dx++) {

                /* 左圖像素位置 */
                int leftIdx  = (y + dy) * width + (x + dx);
                /* 右圖像素位置（向右偏移 d） */
                int rightIdx = (y + dy) * width + (x + d + dx);

                /* 累加絕對差值 */
                int diff = (int)leftImage[leftIdx] - (int)rightImage[rightIdx];
                currentSAD += (diff < 0) ? -diff : diff;
            }
        }

        /* ── 更新最小值（SAD 相同時保留較小的 d，對應 Edge Cases > 無紋理區域策略）── */
        if (currentSAD < minSAD) {
            minSAD = currentSAD;
            bestDisparity = d;
        }
    }

    /* ── 寫入結果 ── */
    disparityMap[y * width + x] = (unsigned char)bestDisparity;
}

/* ═══════════════════════════════════════════════════════════════════════════
 *  Section 3: SAD_GPU — 對外 API
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  對應 SAD_SKILL.md > Interface > Function Signature
 *
 *  職責：
 *    1. 輸入驗證
 *    2. 分配 GPU 記憶體
 *    3. 將影像從 CPU 傳到 GPU
 *    4. 啟動 kernel
 *    5. 將結果從 GPU 傳回 CPU
 *    6. 釋放 GPU 記憶體
 */
void SAD_GPU(
    const cv::Mat& leftImage,    // 輸入：左圖（灰階 CV_8UC1）
    const cv::Mat& rightImage,   // 輸入：右圖（灰階 CV_8UC1）
    cv::Mat& disparityMap,       // 輸出：視差圖（CV_8UC1）
    int kernelSize,              // 窗口大小（預設 7）
    int searchRange              // 搜尋範圍（預設 60）
)
{
    /* ══════════════════════════════════════════════════════════════════════
     *  Step 1: 輸入驗證（對應 SAD_SKILL.md > Edge Cases > Input Validation）
     * ══════════════════════════════════════════════════════════════════════ */

    // 檢查 1: 影像不可為空
    if (leftImage.empty() || rightImage.empty()) {
        fprintf(stderr, "[Error] Empty input image.\n");
        return;
    }

    // 檢查 2: 左右圖尺寸必須一致
    if (leftImage.size() != rightImage.size()) {
        fprintf(stderr, "[Error] Image size mismatch: left(%dx%d) vs right(%dx%d).\n",
                leftImage.cols, leftImage.rows, rightImage.cols, rightImage.rows);
        return;
    }

    // 檢查 3: 必須是灰階影像
    if (leftImage.type() != CV_8UC1 || rightImage.type() != CV_8UC1) {
        fprintf(stderr, "[Error] Images must be grayscale (CV_8UC1). "
                        "Use cv::cvtColor() to convert first.\n");
        return;
    }

    // 檢查 4: kernelSize 必須是 3~15 的奇數
    if (kernelSize < 3 || kernelSize > 15 || kernelSize % 2 == 0) {
        fprintf(stderr, "[Error] kernelSize must be an odd number in [3, 15]. Got: %d\n",
                kernelSize);
        return;
    }

    // 檢查 5: searchRange 必須在 1~128
    if (searchRange < 1 || searchRange > 128) {
        fprintf(stderr, "[Error] searchRange must be in [1, 128]. Got: %d\n",
                searchRange);
        return;
    }

    /* ══════════════════════════════════════════════════════════════════════
     *  Step 2: 準備尺寸與記憶體
     * ══════════════════════════════════════════════════════════════════════ */

    int width  = leftImage.cols;
    int height = leftImage.rows;
    size_t imageSize = (size_t)width * height * sizeof(unsigned char);

    // 初始化輸出
    disparityMap = cv::Mat::zeros(height, width, CV_8UC1);

    // GPU 記憶體指標
    unsigned char* d_left      = nullptr;
    unsigned char* d_right     = nullptr;
    unsigned char* d_disparity = nullptr;

    /* ══════════════════════════════════════════════════════════════════════
     *  Step 3: 分配 GPU 記憶體（對應 Algorithm > High-Level Steps > Step 1）
     * ══════════════════════════════════════════════════════════════════════ */

    CUDA_CHECK(cudaMalloc(&d_left,      imageSize));
    CUDA_CHECK(cudaMalloc(&d_right,     imageSize));
    CUDA_CHECK(cudaMalloc(&d_disparity, imageSize));

    /* ══════════════════════════════════════════════════════════════════════
     *  Step 4: 將影像從 CPU 複製到 GPU（Host → Device）
     * ══════════════════════════════════════════════════════════════════════ */

    CUDA_CHECK(cudaMemcpy(d_left,  leftImage.data,  imageSize, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_right, rightImage.data,  imageSize, cudaMemcpyHostToDevice));

    // 先清零 disparity（確保邊界為 0）
    CUDA_CHECK(cudaMemset(d_disparity, 0, imageSize));

    /* ══════════════════════════════════════════════════════════════════════
     *  Step 5: 啟動 Kernel
     *
     *  Block 大小：32×32 = 1024 threads（對齊 warp，參見 Parallelization Strategy）
     *  Grid  大小：(ceil(width/32), ceil(height/32))
     * ══════════════════════════════════════════════════════════════════════ */

    dim3 blockSize(32, 32);
    dim3 gridSize(
        (width  + blockSize.x - 1) / blockSize.x,
        (height + blockSize.y - 1) / blockSize.y
    );

    SAD_kernel<<<gridSize, blockSize>>>(
        d_left, d_right, d_disparity,
        width, height,
        kernelSize, searchRange
    );

    // 檢查 kernel 啟動錯誤
    CUDA_CHECK(cudaGetLastError());

    // 等待 GPU 完成並檢查執行錯誤
    CUDA_CHECK(cudaDeviceSynchronize());

    /* ══════════════════════════════════════════════════════════════════════
     *  Step 6: 將結果從 GPU 傳回 CPU（Device → Host）
     * ══════════════════════════════════════════════════════════════════════ */

    CUDA_CHECK(cudaMemcpy(disparityMap.data, d_disparity, imageSize, cudaMemcpyDeviceToHost));

    /* ══════════════════════════════════════════════════════════════════════
     *  Step 7: 釋放 GPU 記憶體
     * ══════════════════════════════════════════════════════════════════════ */

    CUDA_CHECK(cudaFree(d_left));
    CUDA_CHECK(cudaFree(d_right));
    CUDA_CHECK(cudaFree(d_disparity));
}

/* ═══════════════════════════════════════════════════════════════════════════
 *  Section 4: SAD_CPU — CPU 對照版本
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  用途：
 *    1. 驗證 GPU 版本的正確性（比對兩者結果）
 *    2. 測量加速比（GPU 時間 / CPU 時間）
 *
 *  邏輯與 GPU 版本完全相同，只是用 for 迴圈取代平行 thread。
 */
void SAD_CPU(
    const cv::Mat& leftImage,
    const cv::Mat& rightImage,
    cv::Mat& disparityMap,
    int kernelSize,
    int searchRange
)
{
    int width  = leftImage.cols;
    int height = leftImage.rows;
    int half   = (kernelSize - 1) / 2;

    disparityMap = cv::Mat::zeros(height, width, CV_8UC1);

    for (int y = half; y < height - half; y++) {
        for (int x = half; x < width - half; x++) {

            int minSAD = INT_MAX;
            int bestDisparity = 0;

            for (int d = 0; d < searchRange; d++) {

                if (x + d + half >= width) break;

                int currentSAD = 0;

                for (int dy = -half; dy <= half; dy++) {
                    for (int dx = -half; dx <= half; dx++) {
                        int leftVal  = leftImage.at<uchar>(y + dy, x + dx);
                        int rightVal = rightImage.at<uchar>(y + dy, x + d + dx);
                        currentSAD += abs(leftVal - rightVal);
                    }
                }

                if (currentSAD < minSAD) {
                    minSAD = currentSAD;
                    bestDisparity = d;
                }
            }

            disparityMap.at<uchar>(y, x) = (uchar)bestDisparity;
        }
    }
}
