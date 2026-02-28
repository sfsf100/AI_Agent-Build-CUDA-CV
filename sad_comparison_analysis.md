# SAD.cu 比對分析報告

## 比較對象

| 項目 | [references/SAD.cu](file:///e:/claude_0227/references/SAD.cu) | [scripts/sad_kernel.cu](file:///e:/claude_0227/scripts/sad_kernel.cu) |
|------|------|------|
| 總行數 | 119 行 | 334 行 |
| 結構 | Kernel + Host API + main() | Kernel + Host API + CPU 版本（無 main） |
| 註解語言 | 中文 少量 | 中文 詳細，對應 SKILL.md |

---

## 1. 核心演算法（Kernel）比對

### ✅ 一致的部分

| 邏輯 | `SAD.cu` | `sad_kernel.cu` |
|------|----------|-----------------|
| 座標計算 | `blockIdx.x*blockDim.x + threadIdx.x` | 相同 |
| 半徑計算 | `(kernel - 1) / 2` | `(kernelSize - 1) / 2` |
| 搜索迴圈 | `for (int r = 0; r < 60; r++)` | `for (int d = 0; d < searchRange; d++)` |
| 窗口遍歷 | `for a = -half..half, for b = -half..half` | `for dy = -half..half, for dx = -half..half` |
| SAD 計算 | `abs(srcImage[...] - srcImage2[...])` | `(diff < 0) ? -diff : diff` |
| 最小值更新 | `if (error < min)` → 記錄 `minx = r` | `if (currentSAD < minSAD)` → 記錄 `bestDisparity = d` |
| 結果輸出 | `dstImage[(y*width + x)] = minx` | `disparityMap[y * width + x] = bestDisparity` |

> [!NOTE]
> **核心 SAD 匹配邏輯完全一致**：兩版在滑動窗口比對、絕對差值累加、最小值追蹤的演算法邏輯上完全相同。

### ⚠️ 差異項

| 差異點 | `SAD.cu`（您的版本） | `sad_kernel.cu`（Skill 版本） | 影響 |
|--------|---------------------|-------------------------------|------|
| **kernel/searchRange 參數化** | 硬編碼 `#define kernel 7`、搜索範圍硬編碼 60 | 作為 kernel 參數傳入 `kernelSize`, `searchRange` | Skill 版更靈活 |
| **邊界像素處理** | 超出邊界的 thread 不寫入（該像素值不確定） | 超出邊界的 thread 明確寫入 0 | Skill 版更安全 |
| **右圖邊界檢查** | 無（`x+r+b` 可能越界） | `if (x + d + half >= width) break` | Skill 版防止越界讀取 |
| **初始 SAD 值** | `min = 100000` | `minSAD = INT_MAX` | Skill 版更嚴謹 |
| **越界 thread 處理** | 僅靠 `if (x >= kernel/2 && ...)` | 先 `if (x >= width)` 提前 return | Skill 版有雙重保護 |
| **`__restrict__` 修飾** | 無 | 有 | Skill 版可能有更好的編譯器優化 |

---

## 2. Host API（`SAD_GPU` 函式）比對

| 差異點 | `SAD.cu` | `sad_kernel.cu` |
|--------|----------|-----------------|
| **輸入驗證** | 無 | 5 項完整檢查（空圖、尺寸、灰階、kernel 奇數、searchRange 範圍） |
| **記憶體分配** | `cudaMalloc<unsigned char>` | `CUDA_CHECK(cudaMalloc(...))` 帶錯誤檢查 |
| **計時方式** | `cudaEvent` + `getTickCount` 混用 | 無內建計時（由外部控制） |
| **Block 大小** | `dim3(32, 32)` | `dim3(32, 32)` — **一致** |
| **Grid 計算** | `(cols + block.x - 1) / block.x` | 相同 |
| **GPU 同步** | `cudaEventSynchronize(stop)` | `cudaDeviceSynchronize()` |
| **記憶體釋放** | `cudaFree` 三次 | `CUDA_CHECK(cudaFree(...))` 帶檢查 |
| **輸出初始化** | 外部 `Mat::zeros` | 函式內 `Mat::zeros` + `cudaMemset` |

> [!IMPORTANT]
> `SAD.cu` 中的計時邏輯有一個 bug：`cudaEventRecord(start)` 放在 kernel launch **之後**，導致 `cudaEvent` 計時不準確（不包含 kernel 執行時間）。不過您的程式使用了 `getTickCount` 作為實際計時，所以最終結果仍正確。

---

## 3. main() 函式

| 項目 | `SAD.cu` | `sad_kernel.cu` |
|------|----------|-----------------|
| **是否包含 main()** | ✅ 有 | ❌ 無（設計為 library） |
| **圖片路徑** | 硬編碼 `D://im2.png`, `D://im1.png` | N/A |
| **灰階轉換** | `cvtColor(img, img, COLOR_BGR2GRAY)` | 由呼叫者處理 |
| **輸出** | `imwrite("depth_map.png", ...)` | 由呼叫者處理 |

---

## 4. 額外功能（Skill 版新增）

| 功能 | 說明 |
|------|------|
| `CUDA_CHECK` 巨集 | 統一 CUDA API 錯誤檢查，出錯時印出檔案行號 |
| `SAD_CPU` 函式 | CPU 對照版本，用於驗證 GPU 正確性 |
| 輸入驗證（5 項） | 防止空圖、尺寸不符、非灰階等錯誤 |
| `cudaMemset` 清零 | 確保未處理的邊界像素為 0 |

---

## 5. 綜合評估

```
              正確性   健壯性   可維護性  彈性
SAD.cu         ★★★★    ★★      ★★       ★★
sad_kernel.cu  ★★★★★   ★★★★★   ★★★★★    ★★★★★
```

> [!TIP]
> **結論**：兩版的 **核心 SAD 演算法邏輯一致**，會產生相同的視差計算結果。Skill 版在參數彈性、錯誤處理、安全性上有全面改進，但不改變核心演算法的行為。

---

## 6. 建議修正項（原始 SAD.cu）

1. **右圖越界風險**：`srcImage2[((y+a)*width+(x+r+b))]` 當 `x+r+b >= width` 時將越界
2. **`cudaEventRecord(start)` 位置**：應移至 kernel launch 之前
3. **硬編碼路徑**：`D://im2.png` 應改為可配置
4. **`min = 100000`**：建議改用 `INT_MAX`
