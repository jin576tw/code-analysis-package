# 專案整合與套件更新指引

code-analysis 在不同專案會產出不同文件。原則：**套件只放通用邊界與完成判準；專案差異一律放在專案側**，更新套件時就不會覆寫專案客製。

## 客製位置

| 位置 | 放什麼 | 平台 |
|---|---|---|
| `.analysis-profile.md`（專案根） | 來源根、入口定位方式、輸出目錄、交付文件清單與必要內容、讀者 | 共用 |
| 專案模板目錄（如 `docs/templates/*.md`） | 各文件的章節結構 | 共用 |
| `CLAUDE.md`／`AGENTS.md` | 專案額外邊界（排除目錄、契約來源、禁止事項） | Claude Code 讀前者、Codex 讀後者；兩平台都用時兩邊都寫或互相引用 |

套件內 `skills/code-analysis/` 不寫專案路徑、專案專屬文件或業務名詞。

**優先序**：本次使用者要求 > 專案設定 > skill 預設骨架。專案設定內分工：專案指引管安全與工作區邊界、profile 管來源導覽與交付位置、模板管文件章節；同一欄位衝突時代理會詢問，避免在兩處寫同一設定。

## 加入新專案

目標：不改套件內容，就能產出符合該專案格式的文件。

1. 安裝（見 [README](../README.md#安裝)）；同一平台只選 plugin 或獨立 skill 其一。
2. 以 [profile 模板](../skills/code-analysis/assets/analysis-profile.template.md) 建立 `.analysis-profile.md`；可請代理依實際建置檔與目錄整理，路徑需查證。
3. 有固定文件格式時放入專案模板，並在 profile 的文件表填模板位置與必要內容。

完成判準：
- profile 內每個路徑都存在。
- 每份預設交付物有模板，或明確採用 skill 預設骨架。
- 以一個小功能試跑，輸出位置、檔名與章節符合 profile；Claude Code 與 Codex 都會用時，兩邊各試一次。

## 新增一種交付文件

例如專案需要 `TEST-CASE.md`：

- 放專案模板，並在 profile 文件表列「必要內容」與讀者。不需修改套件。
- 只有多個專案都需要、且必要內容一致時，才回饋到套件 `references/deliverables.md` 的文件表。

完成判準：試跑後該文件的必要內容都有證據 ID 或列為 gap。

## 更新套件

目標：取得新版通用規則，專案產出格式不被破壞。

1. 確認套件目錄沒有手改；有的話先把該內容移到專案側（profile、模板或 `CLAUDE.md`／`AGENTS.md`）。
2. 讀 [CHANGELOG](../CHANGELOG.md) 對應版本的「專案相容性影響」。
3. 以原安裝方式與範圍重新安裝（`npx skills add` 重跑同一指令；plugin 使用 `claude plugin update` 或重新安裝），並開新 session。
4. 對同一個小功能重跑，比對與舊產出的差異。

完成判準：
- 套件目錄與新版來源一致（無殘留手改、無巢狀重複目錄、未同時安裝 plugin 與獨立 skill）。
- 試跑產出的位置與章節仍符合 profile；差異都能對應到 CHANGELOG 所列變更。
- 受影響的 profile／模板已更新。

## 維護者：發版時

- CHANGELOG 每版寫「專案相容性影響」：是否影響 profile 欄位、模板解讀、輸出檔名或狀態值；無影響寫「無」。
- `plugin.json`、`marketplace.json` 版本一致；`agents/openai.yaml` 描述與 SKILL.md 行為一致。
- SKILL.md 與 references 不出現平台專屬工具名稱。
