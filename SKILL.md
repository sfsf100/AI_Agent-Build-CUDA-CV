---
name: cuda-image-processing
description: >
  CUDA 影像處理技能框架。當使用者需要以 GPU 加速進行影像處理任務時使用，
  包括但不限於：立體匹配(SAD/SSD/NCC)、影像濾波(Gaussian/Median/Bilateral)、
  邊緣偵測(Sobel/Canny)、形態學操作、色彩空間轉換、直方圖處理等。
  本 Skill 作為總入口，可依需求調用對應的子 Skill（如 SAD_SKILL）。
license: MIT
compatibility: >
  需要 NVIDIA GPU (Compute Capability >= 3.5)、CUDA Toolkit 11.0+、
  OpenCV 4.x+、CMake 3.18+。支援 Windows / Linux。
metadata:
  author: shuyo
  version: 1.0.0
  category: Computer Vision > GPU Acceleration
---

# CUDA 影像處理技能框架 (SKILL.md)

> 本文檔是「**主規範**」——定義了一套標準化結構，讓你（或 AI 代理）能快速開發任何 CUDA 影像處理程式。
> 你不需要從零學起，只要照著這個框架填寫，就能產出一份完整的子 Skill。

---

## 一、本文檔是什麼？三層架構總覽

```
┌─────────────────────────────────────────────────┐
│  第 1 層：SKILL.md（你正在讀的這份）               │
│  ─ 定義通用框架、調用規則、資料夾結構              │
│  ─ AI 自動載入，判斷「該用哪個子 Skill」            │
├─────────────────────────────────────────────────┤
│  第 2 層：子 Skill 文檔（如 SAD_SKILL.md）         │
│  ─ 某個具體演算法的完整規格書                      │
│  ─ 包含介面、演算法、效能目標、測試方法              │
├─────────────────────────────────────────────────┤
│  第 3 層：實作檔案                                 │
│  ─ scripts/ 裡的 .cu / .cpp / .py 原始碼          │
│  ─ references/ 裡的學術論文或 API 文件              │
│  ─ assets/ 裡的測試影像或模板                      │
└─────────────────────────────────────────────────┘
```

**白話文**：
- **SKILL.md** = 目錄 + 規則手冊（你現在看的）
- **子 Skill** = 具體食譜（例如 `SAD_SKILL.md` 教你做「SAD 立體匹配」）
- **scripts / references / assets** = 食材和工具

---

## 二、資料夾結構

```
cuda-image-processing/          ← 技能根目錄
│
├── SKILL.md                    ← 【必要】本文檔，主入口
├── SAD_SKILL.md                ← 【子 Skill】SAD 立體匹配規格書
├── (未來可新增更多子 Skill)
│   ├── GAUSSIAN_SKILL.md       ← 高斯模糊
│   ├── SOBEL_SKILL.md          ← Sobel 邊緣偵測
│   └── HISTOGRAM_SKILL.md      ← 直方圖均衡化
│
├── scripts/                    ← 【選用】可執行程式碼
│   ├── sad_kernel.cu           ← CUDA kernel 原始碼
│   ├── main.cpp                ← 主程式 / 測試入口
│   ├── CMakeLists.txt          ← 建置設定
│   └── utils.py                ← 輔助工具腳本
│
├── references/                 ← 【選用】參考資料
│   ├── stereo_matching_survey.pdf
│   └── cuda_best_practices.md
│
└── assets/                     ← 【選用】測試素材 / 模板
    ├── tsukuba_left.png
    ├── tsukuba_right.png
    └── ground_truth.png
```

---

## 三、子 Skill 的標準結構（寫作模板）

> 每個子 Skill（如 `SAD_SKILL.md`）都必須包含以下章節。
> 這就是你要「照著填」的模板。

### 📋 完整章節清單

| # | 章節名稱 | 必要性 | 說明 |
|---|---------|--------|------|
| 1 | **Metadata（元資料）** | ✅ 必要 | 名稱、版本、分類、難度、標籤 |
| 2 | **Purpose（目的）** | ✅ 必要 | 要解決什麼問題？用在哪裡？ |
| 3 | **Interface（介面）** | ✅ 必要 | 函數簽名、輸入輸出、參數表 |
| 4 | **Algorithm（演算法）** | ✅ 必要 | 步驟拆解、數學公式、虛擬碼 |
| 5 | **Performance（效能目標）** | ⭐ 建議 | 目標硬體、FPS 目標、記憶體限制 |
| 6 | **Optimization（最佳化策略）** | ⭐ 建議 | 瓶頸分析、Shared Memory、Texture 等 |
| 7 | **Edge Cases（邊界情況）** | ⭐ 建議 | 輸入驗證、邊界處理、特殊情況 |
| 8 | **Testing（測試驗證）** | ✅ 必要 | 單元測試、效能測試、驗證方法 |

---

### 模板詳解：每個章節怎麼寫

#### 📌 章節 1：Metadata（元資料）

放在文檔最前面，提供快速識別資訊。

```markdown
# [演算法名稱] Skill

## Metadata
- **Skill Name**: [英文名稱，如 SAD_StereoMatching]
- **Version**: [版本號，如 1.0.0]
- **Category**: Computer Vision > [子類別] > [細分類別]
- **Author**: [作者名]
- **Date**: [日期]
- **Difficulty**: [Beginner / Intermediate / Advanced]
- **Tags**: #[標籤1] #[標籤2] #[標籤3]
```

#### 📌 章節 2：Purpose（目的）

讓讀者在 30 秒內理解「這個 Skill 是做什麼的」。

```markdown
## Purpose

### Problem Statement
[一段話描述：什麼問題？為什麼需要 GPU 加速？]

### Use Cases
- **[應用場景 1]**: [具體說明]
- **[應用場景 2]**: [具體說明]

### Background
[補充背景知識，讓新手能理解上下文]
```

#### 📌 章節 3：Interface（介面）

**這是最關鍵的章節**——定義「程式的進出口」。

```markdown
## Interface

### Function Signature
（用虛擬碼或 C++ 列出函數長相）

### Inputs
| Name | Type | Shape/Size | Constraints | Description |
|------|------|------------|-------------|-------------|
| [名稱] | [型別] | [維度] | [限制條件] | [說明] |

### Outputs
| Name | Type | Shape/Size | Description |
|------|------|------------|-------------|
| [名稱] | [型別] | [維度] | [說明] |

### Parameters
| Name | Type | Default | Valid Range | Description |
|------|------|---------|-------------|-------------|
| [名稱] | [型別] | [預設值] | [有效範圍] | [說明] |
```

#### 📌 章節 4：Algorithm（演算法）

把演算法拆成「人看得懂的步驟」，不要直接貼程式碼。

```markdown
## Algorithm

### High-Level Steps（概要步驟）
1. [步驟 1 的白話文]
2. [步驟 2 的白話文]
3. ...

### Detailed Logic（詳細邏輯）
（用虛擬碼搭配文字說明每一步）

### Mathematical Formula（數學公式）
（列出核心公式，並解釋每個符號）

### Pseudocode（虛擬碼）
（完整虛擬碼，可直接翻譯為 CUDA 程式）
```

#### 📌 章節 5：Performance（效能目標）

```markdown
## Performance Requirements

### Target Hardware
- **主要目標**: [GPU 型號, 架構, CUDA Cores, 記憶體]
- **次要目標**: [嵌入式設備等]

### Performance Targets
| Metric | Target Value | Measurement Condition |
|--------|--------------|----------------------|
| 處理延遲 | < ?? ms | [條件] |
| 吞吐率 | > ?? FPS | [條件] |
| vs CPU 加速比 | > ??x | [對比基準] |
```

#### 📌 章節 6：Optimization（最佳化策略）

```markdown
## Optimization Strategy

### 瓶頸分析
（找出程式慢在哪裡、為什麼慢）

### 優化優先級
#### 🔴 Priority 1: [最重要的優化]
#### 🟠 Priority 2: [第二重要的優化]
#### 🟡 Priority 3: [次要優化]

### Parallelization Strategy（平行化策略）
（Thread 怎麼分配、Block 怎麼設定）
```

#### 📌 章節 7：Edge Cases（邊界情況）

```markdown
## Edge Cases & Constraints

### Input Validation（輸入驗證）
（列出所有需要檢查的條件）

### Boundary Handling（邊界處理）
（影像邊緣怎麼辦）

### Special Cases（特殊情況）
（列出可能出問題的場景和處理方式）

### Error Handling（錯誤處理）
（CUDA 錯誤怎麼處理、記憶體不足怎麼辦）
```

#### 📌 章節 8：Testing（測試驗證）

```markdown
## Testing & Validation

### Unit Tests（單元測試）
#### Test 1: [測試名稱]
- **目的**: [測什麼]
- **輸入**: [用什麼資料]
- **預期輸出**: [應該得到什麼]
- **驗證方式**: [怎麼判斷對不對]

### Performance Benchmark（效能測試）
（量測方法、對照組、結果表格）
```

---

## 四、如何調用子 Skill（調度規則）

當使用者提出需求時，AI 會根據以下對照表決定調用哪個子 Skill：

### 調度對照表

| 使用者可能說的話 | 調用的子 Skill | 說明 |
|----------------|---------------|------|
| 「計算深度圖」「立體匹配」「視差圖」 | `SAD_SKILL.md` | SAD 立體匹配 |
| 「模糊影像」「降噪」「高斯濾波」 | `GAUSSIAN_SKILL.md` | 高斯模糊（待建） |
| 「邊緣偵測」「找輪廓」「Sobel」 | `SOBEL_SKILL.md` | Sobel 邊緣偵測（待建） |
| 「直方圖均衡」「增強對比」 | `HISTOGRAM_SKILL.md` | 直方圖均衡化（待建） |
| 「中值濾波」「去椒鹽噪聲」 | `MEDIAN_SKILL.md` | 中值濾波（待建） |

### 調度流程

```
使用者提出需求
    │
    ▼
AI 讀取 SKILL.md（本文檔）的調度對照表
    │
    ▼
根據關鍵詞匹配 → 找到對應的子 Skill
    │
    ▼
AI 讀取子 Skill 的完整內容（如 SAD_SKILL.md）
    │
    ▼
根據子 Skill 的 Interface 和 Algorithm 章節
    │
    ▼
生成對應的 CUDA 程式碼
```

### 調用規則

1. **精確匹配優先**：若使用者明確指定演算法名稱（如「SAD」），直接調用對應子 Skill
2. **語意推斷**：若使用者描述需求（如「計算兩張圖的深度」），AI 推斷最適合的子 Skill
3. **不存在時提示**：若對應的子 Skill 尚未建立，告知使用者並建議替代方案
4. **組合調用**：複雜任務可依序調用多個子 Skill（如：先降噪 → 再立體匹配）

---

## 五、環境需求與前置準備

### 硬體需求

| 項目 | 最低要求 | 建議配置 |
|------|---------|---------|
| GPU | NVIDIA Kepler 架構以上 (CC≥3.5) | RTX 3060 以上 |
| GPU 記憶體 | 2 GB | 6 GB 以上 |
| 系統記憶體 | 4 GB | 16 GB 以上 |

### 軟體需求

| 軟體 | 版本 | 用途 |
|------|------|------|
| CUDA Toolkit | 11.0+ | GPU 程式編譯與執行 |
| OpenCV | 4.x+ | 影像讀寫與前後處理 |
| CMake | 3.18+ | 跨平台建置系統 |
| C++ Compiler | C++14 以上 | 主程式編譯 |

### 建置流程概要

```
1. 安裝 CUDA Toolkit + OpenCV
2. 用 CMake 設定專案
3. 編譯 .cu 和 .cpp 檔案
4. 連結 OpenCV 和 CUDA runtime 函式庫
5. 執行程式
```

---

## 六、命名規範與慣例

### 檔案命名

| 類型 | 規則 | 範例 |
|------|------|------|
| 子 Skill 文檔 | `[演算法名]_SKILL.md`（大寫） | `SAD_SKILL.md` |
| CUDA Kernel | `[演算法名]_kernel.cu`（小寫） | `sad_kernel.cu` |
| 主程式 | `main.cpp` 或 `[演算法名]_main.cpp` | `sad_main.cpp` |
| 測試程式 | `test_[演算法名].cpp` | `test_sad.cpp` |
| 建置設定 | `CMakeLists.txt` | — |

### 函數命名

| 類型 | 規則 | 範例 |
|------|------|------|
| GPU Kernel 函數 | `[演算法]_kernel` | `SAD_kernel` |
| 主要 API 函數 | `[演算法]_GPU` | `SAD_GPU` |
| CPU 對照版本 | `[演算法]_CPU` | `SAD_CPU` |

---

## 七、如何新增一個子 Skill（快速指南）

想為這個框架新增一個演算法？只要 **4 步**：

### Step 1：建立文檔

在根目錄新建 `[演算法名]_SKILL.md`，複製第三節的模板。

### Step 2：填寫 8 個章節

按照模板，逐一填寫：
1. Metadata → 寫上名稱、分類
2. Purpose → 描述要解決什麼問題
3. Interface → 定義輸入輸出
4. Algorithm → 說明演算法步驟
5. Performance → 設定效能目標
6. Optimization → 分析瓶頸與加速策略
7. Edge Cases → 列出邊界情況
8. Testing → 規劃如何驗證

### Step 3：更新調度表

回到本文檔（SKILL.md）的第四節，在調度對照表中新增一行。

### Step 4：（日後）撰寫程式碼

根據子 Skill 文檔的 Interface 和 Algorithm，在 `scripts/` 資料夾中撰寫 `.cu` 和 `.cpp` 檔案。

---

## 八、常見問題 (FAQ)

### Q1：我完全沒用過 CUDA，可以用這個框架嗎？
**可以。** 子 Skill 文檔會把演算法拆解到「虛擬碼」等級，你只需要理解基本的 C/C++ 語法。你也可以讓 AI 讀取子 Skill 文檔，直接為你生成 CUDA 程式碼。

### Q2：子 Skill 和 SKILL.md 的關係是什麼？
**SKILL.md 是目錄和規則手冊**，負責告訴 AI「有哪些能力可以用、什麼情況用哪個」。**子 Skill 才是具體的技術文件**，包含完整的演算法規格。

### Q3：為什麼要把文檔和程式碼分開？
因為「先想清楚，再動手寫」效率最高。文檔先定義好介面和演算法，程式碼就是照著翻譯，出錯也容易追蹤。

### Q4：我可以只用其中一個子 Skill 嗎？
**可以。** 每個子 Skill 都是獨立且完整的。你可以只用 SAD_SKILL 來做立體匹配，不需要用到其他子 Skill。

---

## 九、版本記錄

| 版本 | 日期 | 變更說明 |
|------|------|---------|
| 1.0.0 | 2026-02-27 | 初版：框架結構、調度規則、子 Skill 模板、SAD 範例 |
