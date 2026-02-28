一個人就是一家公司】
Michael Galpert 於 2025 年在 GitHub 上啟動了名為 Contains Studio 的開源項目。
 "Contains Studio AI Agents"  AI 代理模板庫。

📁 專案內容重點:
    ✅27 個 AI agents，分屬 7 大部門
    ✅依照部門與職能分類：engineering、design、marketing、product、testing、project management 等
    ✅每個 agent 都是一個清楚定義的角色（如 AI 工程師、快速原型設計、內容創作者、行銷助理等）
    ✅以 Markdown 定義，可直接複製、修改、客製化
    ✅設計目標是 加速開發流程、內容產出與跨角色協作
每個代理都包含角色說明、任務範圍與使用方式，可直接整合至支援 Agent 架構的工具或系統中使用，
用於建立多代理協作的工作流程。



技能（Skill）是一組指令，用來教 Claude 如何處理特定任務或工作流程。

依規格產生前端設計、用固定方法做研究、產出符合團隊風格文件、或協調多步驟流程。


技能就是一個資料夾，內容通常包含：

SKILL.md（必要）：以 Markdown 撰寫，含 YAML frontmatter
scripts/（選用）：可執行程式（Python、Bash 等）
references/（選用）：需要時才載入的參考文件
assets/（選用）：產出時用的模板、字型、圖示

核心設計原則
1. 漸進式揭露（Progressive Disclosure）
技能採三層載入：

第一層（YAML frontmatter）：固定載入到 Claude 系統提示，提供「何時該用此技能」的最小必要資訊。
第二層（SKILL.md 內文）：Claude 判定相關時才載入完整指令。
第三層（連結檔案）：技能資料夾內的其他檔案，僅在需要時才進一步讀取。
這能在保留專業能力的同時，降低 token 消耗。


. 可組合性（Composability）
Claude 可同時載入多個技能。你的技能應該能和其他技能共存，不要假設自己是唯一能力來源。

3. 可攜性（Portability）
技能可跨 Claude.ai、Claude Code、API 使用。只要環境支援相依需求，一份技能可跨介面重用。

MCP 與技能分工
MCP（連通性）：讓 Claude 連到你的服務（如 Notion、Asana、Linear）
技能（知識）：教 Claude 如何高品質使用該服務
MCP 提供即時資料與工具呼叫
技能封裝流程與最佳實務

藉助Asana，讓遠端和分佈各地的團隊，以及您的整個組織，都能專注於他們的目標、專案和任務。


定義成功標準
如何判斷技能有效？

這些是方向性目標，不是絕對門檻。請追求嚴謹，但也接受早期會帶有主觀評估成分。

##量化指標：

90% 相關查詢可正確觸發技能
測法：跑 10-20 組應觸發查詢，記錄自動載入率
在 X 次工具呼叫內完成流程
測法：比較「有技能 / 無技能」的工具呼叫與 token 用量
每個流程 0 次失敗 API 呼叫
測法：看 MCP 日誌、重試率、錯誤碼
質化指標：

使用者不用一直提醒下一步
流程可完成且少需人工修正
跨多次對話結果一致


關鍵規則

必須完全是 SKILL.md（區分大小寫）

技能資料夾命名：
必須用 kebab-case，例如 notion-project-setup
不可空白、底線、大寫

YAML frontmatter：最重要的區塊
Claude 會用 frontmatter 判斷要不要載入技能。

最小必要格式

---
name: your-skill-name
description: 做什麼。當使用者提到 [特定語句] 時使用。
---

欄位要求
name（必要）：

只能 kebab-case
不可空白或大寫
應與資料夾名一致
description（必要）：

必須同時寫出：
技能做什麼
何時使用（觸發條件）
長度小於 1024 字元
不可含 XML 標籤（<、>）
要包含使用者真實會說的任務語句
若有關聯檔案類型，也應寫出
license（選用）：

開源發布時建議填
常見為 MIT、Apache-2.0
compatibility（選用）：

1-500 字元
用來說明環境需求（目標產品、系統套件、網路需求等）
metadata（選用）：

可放任意 key-value
建議至少含 author、version、mcp-server

metadata:
  author: ProjectHub
  version: 1.0.0
  mcp-server: projecthub

安全限制
frontmatter 禁止：

XML 角括號（<、>）
技能名稱含 claude 或 anthropic（保留字）
原因：frontmatter 會進系統提示，惡意內容可能造成指令注入。


主指令撰寫

---
name: your-skill
description: [...]
---

# 技能名稱

## Instructions
### Step 1: [主要步驟]
說明、命令與預期結果

## Examples
### Example 1: [常見情境]
使用者會說什麼、執行哪些動作、結果是什麼

## Troubleshooting
### Error: [常見錯誤]
Cause: [原因]
Solution: [解法]


ch3 test

使用 skill-creator
skill-creator 可幫你快速產生、檢視與迭代技能。

可做：

由自然語言產生技能草稿
產出格式正確的 SKILL.md
建議觸發詞與結構
找出常見問題（描述模糊、漏觸發詞、結構不佳）
提供測試案例建議
注意：skill-creator 偏向設計與改善，不會直接代你跑完整自動化評估。

依回饋持續迭代
欠觸發訊號：

該觸發卻沒載入
使用者要手動啟用
常被問何時該用
解法：補強 description 的細節、語意與關鍵詞（尤其技術詞）。

過觸發訊號：

無關查詢也觸發
使用者常關閉技能
技能用途混淆
解法：加入負向觸發條件、收斂描述範圍。

執行問題訊號：

結果不一致
API 失敗
需要大量人工修正
解法：改善步驟指令，補足錯誤處理。



第 4 章：發布與分享

技能可讓 MCP 整合更完整。使用者比較不同 connector 時，帶技能的方案通常更快產生價值。

個人用戶怎麼安裝？

如果你是個人開發者：

下載技能資料夾

（可選）壓縮成 zip

到 Claude.ai：

Settings → Capabilities → Skills

上傳技能

或放到 Claude Code 的技能資料夾

👉 就像安裝一個外掛。


最核心概念  這三件事：

技能怎麼安裝

技能怎麼發布

技能怎麼說明才會有人用

好寫法（講成果）

「ProjectHub 技能可讓團隊在幾秒內建立完整專案工作區，不用再花 30 分鐘手動設定。」

這樣大家立刻知道：

它幫我省時間

它幫我解決痛點  🔥 MCP + Skills 的組合，能不能讓使用者「更快得到成果」？