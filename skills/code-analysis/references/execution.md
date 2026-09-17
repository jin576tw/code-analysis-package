# 續跑與選用快照

一般分析不需要本檔。只在長時間盤點、預期會中斷，或使用者要求保存／續跑時使用。

## 續跑要達到的結果

- 不重做已完成且來源未變的部分；來源或文件已變時，只重查受影響的主張。
- 不憑最新檔名猜測是哪個任務；以使用者指定的輸出目錄或 run.json 為準。
- 新增／刪除的路由或設定不會被既有檔案清單偵測，續跑時對入口相關目錄做 Git diff 或檔案盤點。
- 平台中斷不算修補失敗；狀態顯示 running 不代表仍有代理在跑。

## 選用快照工具

`scripts/checkpoint.mjs`（相對於本 SKILL.md 所在資料夾，Node.js 內建模組、零依賴）只記錄選定檔案的 SHA-256、進度與 revision，用來偵測檔案是否在中斷後被改動；不判斷分析品質。

輸入 JSON（暫存檔，不是交付物）：

```json
{
  "schema_version": 1,
  "run_id": "feature-analysis-001",
  "target": "本次分析目標",
  "status": "running",
  "completed": ["source-inventory"],
  "pending": ["draft"],
  "partial_note": "",
  "invalidation_reason": "",
  "files": [
    {"path": "src/entry.js", "role": "source"},
    {"path": ".analysis/docs/feature/ANALYSIS.md", "role": "deliverable"}
  ]
}
```

```text
node "SCRIPT" save "ROOT" "RUN_RELATIVE" "INPUT_JSON" EXPECTED_REVISION
node "SCRIPT" check "ROOT" "RUN_RELATIVE"
```

- ROOT 為已授權工作區；路徑相對 ROOT、一律用 `/`（Windows 亦同）。role：source／requirement／deliverable／evidence／asset／review。
- 首次 EXPECTED_REVISION 為 0，之後用最近讀到的 revision。`check` 有變動時非零退出。
- 只列真正使用的來源、設定、需求與交付檔；不收整個 repo 或機密檔。
- 若以快照支撐 `verified`：REVIEW.md 記錄審查時的 `snapshot_sha256`；之後改了非 review 檔案就需重新審查。
- 強制終止可能留下 `.lock`／`.tmp`，確認無活動 writer 後再清除。
- 無 Node.js 時照常分析，說明未使用自動快照即可。
