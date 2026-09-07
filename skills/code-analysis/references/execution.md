# 執行與續跑

## 一份可攜 skill

以目前載入的 SKILL.md 所在資料夾解析 references／assets／scripts；以下 SCRIPT 代表該目錄的 `scripts/checkpoint.mjs`。
不依賴工作目錄恰好是 skill 根目錄，不依賴平台專屬環境變數、模型名稱或舊 agent 註冊。
Claude／Codex 使用實際可用的原生工具。子代理不存在或被禁止時，走主檔的 self_reviewed 分支，持續完成可做的分析。

## 連續工作

預設在同一工作流程自動完成。完成來源盤點、文件、審查／修補等有用里程碑時保存進度，**保存後立即接續**，不要求換 session。
很小的分析可把來源與文件里程碑合併，不逐檔寫 checkpoint。長時間盤點則在足以復用的來源群組完成後保存，以限制意外中斷的損失。
若需要提前保存已完成來源盤點，可先將簡短行為表存入分析草稿，避免重複建立中間文件。
只有使用者明確暫停、平台中斷、或必要資訊無法取得時才停；非阻擋未知放到限制中，其他工作繼續。

## 檔案快照

Node.js 輔助工具無外部套件，僅保存選定檔案 SHA-256、進度與 revision，不分析程式也不裁定品質。
ROOT 為已授權工作區；RUN_RELATIVE 是其中的 run.json 路徑，父目錄先建立。跨 repo 時選擇已授權共同工作區根，不擴大掃描範圍。
只有真正使用的來源、影響行為的設定、需求、分析文件、證據、圖片與審查紀錄列入 files；不收集整個 repo 或機密檔案。
ROOT 外的來源需以獲准且去除機密的摘錄保存於範圍內並標記原始版本／無法自動核對的限制，不偷偷改用更大根目錄繞過權限。

將下列 JSON 改成實際內容，寫到暫存 INPUT_JSON（這是工具輸入，不是額外交付文件）：

```json
{
  "schema_version": 1,
  "run_id": "feature-analysis-001",
  "target": "本次明確的分析目標",
  "status": "running",
  "completed": ["source-inventory", "draft"],
  "pending": ["independent-review", "finalize"],
  "partial_note": "",
  "invalidation_reason": "",
  "files": [
    {"path": "src/entry.js", "role": "source"},
    {"path": ".analysis/docs/feature/ANALYSIS.md", "role": "deliverable"}
  ]
}
```

命令（引號保留，路徑替換成真實值；不直接複製佔位文字執行）：

```text
node "SCRIPT" save "ROOT" "RUN_RELATIVE" "INPUT_JSON" 0
node "SCRIPT" check "ROOT" "RUN_RELATIVE"
```

首次 expected revision 為 0，更新時用最近實際讀到的 revision。`save` 成功返回新 revision 與 snapshot_sha256；`check` 失敗返回 changed 或錯誤並以非零退出。
檔案路徑使用相對 ROOT 的 `/` 分隔格式，即使在 Windows 也相同；支援 source／requirement／deliverable／evidence／asset／review。
completed／pending 由實際任務決定，不要求固定階段名；next_action 永遠從 pending 第一項推導，不能另填一個不同的下一步。

`snapshot_sha256` 涵蓋所有非 review 檔案的路徑、角色與內容指紋。Reviewer 引用它及審查輸入 revision。
Review 完成後，先對審查前快照執行 check，確認未變，再將 REVIEW.md 加入 files（role=review）保存最終狀態。
Review 不參與它所引用的 snapshot hash，避免循環；其實際檔案指紋仍包含於 run.json 的 files 與 state_sha256，check 仍會檢查。
最終 revision 可以高於 reviewed_revision；是否過期以 reviewed_snapshot_sha256 與當前 snapshot_sha256 核對。
若之後修改來源／文件／證據／圖片，新 snapshot 必須重新審查；不可只改 REVIEW.md 的 hash 假裝重審。

## 恢復

1. 讀確切 run.json，不憑最新檔名猜不同任務。先 `check`，再讀 pending／partial_note、當前文件、相關來源與未解發現。
2. 指紋未變：沿用完成成果，從 pending 第一項繼續；未完成的修補／審查接續同一輪。
3. 指紋改變：列出影響；用來源→行為→文件映射判斷重查範圍，不全量重跑。必要時將受影響 completed 移回 pending，填明確 invalidation_reason，再 save。只換 hash 不算重新核對。
4. 來源不存在／無法判斷影響時，相關結論保留為未驗證；完成獨立部分，重要交付受影響才 blocked。
5. 新增／刪除路由、條件檔等不會被既有檔案清單自動偵測；續跑需做限於入口相關目錄的檔案盤點或 Git diff，確認來源集合是否變動，再更新快照。

若中斷時文件有部分寫入，check 應回報 changed；讀實際 diff 確認哪些修正已落地，記入 partial_note／invalidation_reason 後保存新 checkpoint，不把正常中途中斷當成無法恢復的損壞。
不把額度中斷計入修補失敗，不因狀態顯示 running 就假定仍有代理在跑。

## 實作界線

save 使用同一 run 的排他鎖、expected revision 與單檔暫存 rename，防止配合此工具的並行寫入互相覆蓋。沒有跨檔交易或所有派工都必經的攔截器。
若程序被強制殺死可能留下 `.lock`／`.tmp`；先確認沒有活動 writer，再清除該次殘留，不能自動刪除未知鎖。正常錯誤會清理自己取得的鎖。
Hash 可偵測未同步變更，不是簽章，不能防止同時改檔與重算 hash 的惡意行為；也不能證明主張正確、檔案清單齊全、review 真獨立或 agent 沒跳過步驟。
輔助工具未執行時，skill 的保存規則只是流程要求；不能宣稱機械保證不中斷或每一步一定留存。
