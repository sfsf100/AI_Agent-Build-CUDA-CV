/**
 * ============================================================================
 *  SAD Stereo Matching — 主程式
 * ============================================================================
 *  根據 SAD_SKILL.md 規格書實作
 *
 *  功能：
 *    1. 讀取左右立體影像
 *    2. 呼叫 SAD_GPU 計算視差圖
 *    3. 顯示與儲存結果
 *    4. （可選）與 CPU 版本比較正確性和效能
 *
 *  用法：
 *    ./sad_stereo <左圖路徑> <右圖路徑> [kernelSize] [searchRange]
 *
 *  範例：
 *    ./sad_stereo tsukuba_left.png tsukuba_right.png 7 60
 * ============================================================================
 */

#include <opencv2/opencv.hpp>
#include <cuda_runtime.h>
#include <cstdio>
#include <cstdlib>
#include <chrono>
#include <cmath>

/* ── 函數宣告（實作在 sad_kernel.cu）── */
void SAD_GPU(const cv::Mat& leftImage, const cv::Mat& rightImage,
             cv::Mat& disparityMap, int kernelSize, int searchRange);

void SAD_CPU(const cv::Mat& leftImage, const cv::Mat& rightImage,
             cv::Mat& disparityMap, int kernelSize, int searchRange);


/* ═══════════════════════════════════════════════════════════════════════════
 *  輔助函數
 * ═══════════════════════════════════════════════════════════════════════════ */

/**
 * printGPUInfo — 印出目前 GPU 的基本資訊
 */
void printGPUInfo()
{
    int deviceCount = 0;
    cudaGetDeviceCount(&deviceCount);

    if (deviceCount == 0) {
        printf("[Warning] No CUDA-capable GPU detected!\n");
        return;
    }

    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);

    printf("╔══════════════════════════════════════════╗\n");
    printf("║           GPU Information                ║\n");
    printf("╠══════════════════════════════════════════╣\n");
    printf("║  Device  : %-28s  ║\n", prop.name);
    printf("║  Compute : %d.%d                          ║\n", prop.major, prop.minor);
    printf("║  Cores   : %-28d  ║\n", prop.multiProcessorCount);
    printf("║  Memory  : %-4.0f MB                       ║\n",
           prop.totalGlobalMem / (1024.0 * 1024.0));
    printf("╚══════════════════════════════════════════╝\n\n");
}

/**
 * printUsage — 印出使用說明
 */
void printUsage(const char* programName)
{
    printf("\n");
    printf("SAD Stereo Matching — CUDA Accelerated\n");
    printf("═══════════════════════════════════════\n\n");
    printf("Usage:\n");
    printf("  %s <left_image> <right_image> [kernelSize] [searchRange]\n\n", programName);
    printf("Arguments:\n");
    printf("  left_image   : Path to left rectified image\n");
    printf("  right_image  : Path to right rectified image\n");
    printf("  kernelSize   : Matching window size (odd, 3-15, default: 7)\n");
    printf("  searchRange  : Max disparity search range (1-128, default: 60)\n\n");
    printf("Example:\n");
    printf("  %s tsukuba_left.png tsukuba_right.png 7 16\n\n", programName);
}

/**
 * applyColorMap — 將灰階視差圖轉為彩色（方便觀察深度）
 *
 *  亮色（暖色）= 近距離
 *  暗色（冷色）= 遠距離
 */
cv::Mat applyColorMap(const cv::Mat& disparityMap, int searchRange)
{
    cv::Mat normalized, colored;

    // 將視差值正規化到 0~255 範圍
    double minVal, maxVal;
    cv::minMaxLoc(disparityMap, &minVal, &maxVal);

    if (maxVal > 0) {
        disparityMap.convertTo(normalized, CV_8UC1, 255.0 / maxVal);
    } else {
        normalized = disparityMap.clone();
    }

    // 套用 JET 色彩映射（藍→紅）
    cv::applyColorMap(normalized, colored, cv::COLORMAP_JET);

    return colored;
}

/**
 * compareResults — 比較 GPU 和 CPU 結果的差異
 *
 *  用途：驗證 GPU 版本是否正確（對應 Testing > Unit Tests）
 */
void compareResults(const cv::Mat& gpuResult, const cv::Mat& cpuResult)
{
    if (gpuResult.size() != cpuResult.size()) {
        printf("[Compare] Size mismatch! Cannot compare.\n");
        return;
    }

    int totalPixels = gpuResult.rows * gpuResult.cols;
    int matchPixels = 0;
    int maxDiff = 0;
    double sumDiff = 0;

    for (int y = 0; y < gpuResult.rows; y++) {
        for (int x = 0; x < gpuResult.cols; x++) {
            int gVal = gpuResult.at<uchar>(y, x);
            int cVal = cpuResult.at<uchar>(y, x);
            int diff = abs(gVal - cVal);

            if (diff == 0) matchPixels++;
            if (diff > maxDiff) maxDiff = diff;
            sumDiff += diff;
        }
    }

    double matchRate = 100.0 * matchPixels / totalPixels;
    double avgDiff   = sumDiff / totalPixels;

    printf("\n");
    printf("┌───────────────────────────────────────┐\n");
    printf("│   GPU vs CPU Comparison               │\n");
    printf("├───────────────────────────────────────┤\n");
    printf("│  Match Rate : %6.2f%%                  │\n", matchRate);
    printf("│  Avg Diff   : %6.3f pixels             │\n", avgDiff);
    printf("│  Max Diff   : %d pixels                 │\n", maxDiff);
    printf("└───────────────────────────────────────┘\n");
}


/* ═══════════════════════════════════════════════════════════════════════════
 *  Main
 * ═══════════════════════════════════════════════════════════════════════════ */

int main(int argc, char* argv[])
{
    /* ── 參數解析 ── */

    if (argc < 3) {
        printUsage(argv[0]);
        return 1;
    }

    const char* leftPath   = argv[1];
    const char* rightPath  = argv[2];
    int kernelSize  = (argc >= 4) ? atoi(argv[3]) : 7;
    int searchRange = (argc >= 5) ? atoi(argv[4]) : 60;

    printf("\n");
    printf("SAD Stereo Matching\n");
    printf("═══════════════════\n\n");

    /* ── 印出 GPU 資訊 ── */
    printGPUInfo();

    /* ══════════════════════════════════════════════════════════════════════
     *  Step 1: 讀取影像
     * ══════════════════════════════════════════════════════════════════════ */

    printf("[Step 1] Loading images...\n");

    cv::Mat leftColor  = cv::imread(leftPath);
    cv::Mat rightColor = cv::imread(rightPath);

    if (leftColor.empty()) {
        fprintf(stderr, "[Error] Cannot load left image: %s\n", leftPath);
        return 1;
    }
    if (rightColor.empty()) {
        fprintf(stderr, "[Error] Cannot load right image: %s\n", rightPath);
        return 1;
    }

    // 轉灰階（SAD 演算法需要灰階輸入）
    cv::Mat leftGray, rightGray;
    if (leftColor.channels() == 3) {
        cv::cvtColor(leftColor, leftGray, cv::COLOR_BGR2GRAY);
    } else {
        leftGray = leftColor;
    }
    if (rightColor.channels() == 3) {
        cv::cvtColor(rightColor, rightGray, cv::COLOR_BGR2GRAY);
    } else {
        rightGray = rightColor;
    }

    printf("         Left  : %dx%d\n", leftGray.cols, leftGray.rows);
    printf("         Right : %dx%d\n", rightGray.cols, rightGray.rows);
    printf("         Kernel: %d, Range: %d\n\n", kernelSize, searchRange);

    /* ══════════════════════════════════════════════════════════════════════
     *  Step 2: GPU 計算視差圖
     * ══════════════════════════════════════════════════════════════════════ */

    printf("[Step 2] Running SAD on GPU...\n");
    cv::Mat disparityGPU;

    // GPU 預熱（第一次執行較慢，不計入時間）
    SAD_GPU(leftGray, rightGray, disparityGPU, kernelSize, searchRange);

    // 正式計時
    auto gpuStart = std::chrono::high_resolution_clock::now();
    SAD_GPU(leftGray, rightGray, disparityGPU, kernelSize, searchRange);
    auto gpuEnd = std::chrono::high_resolution_clock::now();

    double gpuTimeMs = std::chrono::duration<double, std::milli>(gpuEnd - gpuStart).count();
    double gpuFPS = 1000.0 / gpuTimeMs;

    printf("         GPU Time : %.2f ms (%.1f FPS)\n\n", gpuTimeMs, gpuFPS);

    /* ══════════════════════════════════════════════════════════════════════
     *  Step 3: CPU 計算（用於對照驗證）
     * ══════════════════════════════════════════════════════════════════════ */

    printf("[Step 3] Running SAD on CPU (for comparison)...\n");
    cv::Mat disparityCPU;

    auto cpuStart = std::chrono::high_resolution_clock::now();
    SAD_CPU(leftGray, rightGray, disparityCPU, kernelSize, searchRange);
    auto cpuEnd = std::chrono::high_resolution_clock::now();

    double cpuTimeMs = std::chrono::duration<double, std::milli>(cpuEnd - cpuStart).count();
    double cpuFPS = 1000.0 / cpuTimeMs;

    printf("         CPU Time : %.2f ms (%.1f FPS)\n", cpuTimeMs, cpuFPS);
    printf("         Speedup  : %.1fx\n", cpuTimeMs / gpuTimeMs);

    /* ── 比較 GPU 與 CPU 結果 ── */
    compareResults(disparityGPU, disparityCPU);

    /* ══════════════════════════════════════════════════════════════════════
     *  Step 4: 輸出結果驗證（對應 Edge Cases > Error Handling > 輸出驗證）
     * ══════════════════════════════════════════════════════════════════════ */

    printf("\n[Step 4] Validating output...\n");

    int validPixels = 0;
    for (int i = 0; i < (int)disparityGPU.total(); i++) {
        if (disparityGPU.data[i] > 0 && disparityGPU.data[i] < searchRange) {
            validPixels++;
        }
    }
    double validRatio = 100.0 * validPixels / disparityGPU.total();
    printf("         Valid pixels: %.1f%%\n", validRatio);

    if (validRatio < 50.0) {
        printf("         [Warning] Less than 50%% valid disparities.\n");
        printf("                  Check input images or parameters.\n");
    } else {
        printf("         [OK] Output looks reasonable.\n");
    }

    /* ══════════════════════════════════════════════════════════════════════
     *  Step 5: 儲存與顯示結果
     * ══════════════════════════════════════════════════════════════════════ */

    printf("\n[Step 5] Saving results...\n");

    // 儲存灰階視差圖
    cv::imwrite("disparity_gray.png", disparityGPU);
    printf("         Saved: disparity_gray.png\n");

    // 儲存彩色視差圖（方便觀察）
    cv::Mat colorDisparity = applyColorMap(disparityGPU, searchRange);
    cv::imwrite("disparity_color.png", colorDisparity);
    printf("         Saved: disparity_color.png\n");

    // 顯示視窗
    printf("\n[Done] Displaying results. Press any key to exit.\n\n");

    cv::imshow("Left Image", leftGray);
    cv::imshow("Disparity (Gray)", disparityGPU);
    cv::imshow("Disparity (Color)", colorDisparity);
    cv::waitKey(0);
    cv::destroyAllWindows();

    /* ── 最終摘要 ── */
    printf("╔══════════════════════════════════════════╗\n");
    printf("║              Summary                     ║\n");
    printf("╠══════════════════════════════════════════╣\n");
    printf("║  Resolution : %4d x %-4d                ║\n", leftGray.cols, leftGray.rows);
    printf("║  Kernel     : %-2d                         ║\n", kernelSize);
    printf("║  Range      : %-3d                        ║\n", searchRange);
    printf("║  GPU Time   : %7.2f ms                  ║\n", gpuTimeMs);
    printf("║  CPU Time   : %7.2f ms                  ║\n", cpuTimeMs);
    printf("║  Speedup    : %6.1fx                    ║\n", cpuTimeMs / gpuTimeMs);
    printf("║  Valid Px   : %5.1f%%                     ║\n", validRatio);
    printf("╚══════════════════════════════════════════╝\n");

    return 0;
}
