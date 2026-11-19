# tools/acceptance — 驗收效率工具

這組腳本只處理「驗收流程」：讀回執、分群、排序、預跑分流、日誌體檢。
它們**不改遊戲程式、不改測試、不改 canonical 驗證器**。

硬規則（來自 AGENTS.md 與專案指揮中心）：

- 正式收據只有一種：`~/.codex/skills/godot-runtime-verify/scripts/verify_godot.ps1` 寫出的 `result.json`。這裡沒有任何腳本取代它、包裝它或修改它。
- `godot_prepass.ps1` 的結果標為 `"acceptance": false`，放在 `.godot-temp/godot_prepass/`（或 `-OutRoot`），**不得**放進 `output/d_integration_*/runs`。
- `trim_run_logs.ps1` 只試算與加摘要檔，**不刪任何檔案**。
- `timeout_baseline.ps1` 的數字只是參考；驗收逾時不因它放寬，調整要經指揮中心、由 Nekki 決定。
- 跑 Godot 之前照舊向專案指揮中心申請時段；prepass 一樣佔 Godot 槽。

## 建議流程

1. 批次前：`triage_receipts.ps1` 讀最近收據 → `batch_plan.ps1` 排序（先跑上次 PASS 的、再跑每個「同一首錯群」的代表列、其餘同群列延後）。
2. 已知失敗要定位時：`godot_prepass.ps1` 先跑（首錯後數秒即停、日誌上限、重複行折疊），拿到首錯與回溯後再改；修好後才用 canonical 跑一次取正式收據。
3. 批次後：`triage_receipts.ps1` 產生 `triage.md`，直接貼進狀態板；`timeout_baseline.ps1` 列出「驗證器逾時 < 測試內 deadline」與「別處 PASS 很快卻逾時」的列。
4. 確認是過時測試（fixture／API 脫節）後，經擁有線同意登記到 `stale_tests.json`，之後統計會把它們獨立列出、批次預設跳過。

## 腳本

| 腳本 | 動作 | 讀／寫 |
|---|---|---|
| `triage_receipts.ps1 -RunsRoot <runs…> -OutDir <dir> [-StaleRegistry stale_tests.json]` | 分類每筆 result.json，輸出 `triage.json` / `triage.md`（類別、同首錯群、重複跑、日誌洪水、逾時判讀、過時候選） | 只讀收據；寫 OutDir |
| `godot_prepass.ps1 -ProjectPath <proj> -Mode headless\|visual -GodotArguments @(…) [-TimeoutSeconds] [-GraceSeconds 5] [-MaxLogMB 20] [-NoStopOnFirstError] [-OutRoot] [-Label]` | 分流預跑；只殺自己以 PID 啟動的 Godot | 寫 OutRoot |
| `trim_run_logs.ps1 -RunsRoot <runs…> [-ReportPath] [-WriteDigest] [-LargeMB 50]` | 找出逐位元組相同的重複日誌與超大日誌；`-WriteDigest` 在超大日誌旁新增 `log_digest_*.txt` | 不刪檔 |
| `timeout_baseline.ps1 -TriageJson <triage.json> -OutDir <dir> [-TestsRoot scripts/tests]` | 每支測試 PASS p50／max、測試內 deadline、參考逾時、錯配與疑似卡死 | 只讀；寫 OutDir |
| `batch_plan.ps1 -TriageJson <triage.json> -TestList <txt 或 json> -OutDir <dir> [-StaleRegistry] [-IncludeStale]` | 批次排序（PREVIOUS_PASS → REPRESENTATIVE → UNIQUE_FAIL → DEFERRED → TIMEOUT_LAST → UNKNOWN） | 只讀；寫 OutDir |
| `dedupe_run_logs.ps1 -RunsRoot <runs…> -ReceiptPath <json> [-Apply] [-MinAgeMinutes 15] [-KeepGodotLog]` | 刪可重建的重複副本：`combined.log`（僅當大小 = stdout＋換行＋stderr）與 appdata `godot.log`；一律保留 stdout.log、stderr.log、result.json；跳過剛修改的 run；拒絕 `.godot-temp/godot_verify`；`-Apply` 前先寫含雜湊的清單 | 無 `-Apply` 只試算；**刪除需 Nekki 親自同意**（2026-10-12 已對 runs 與 evidence 執行一次） |

注意：`godot_prepass.ps1` 的 `-GodotArguments` 是陣列，從外層 shell 呼叫時要用 `powershell -Command "& '…\godot_prepass.ps1' -GodotArguments @('--script','res://…')"`，用 `-File` 會把陣列當成字串。prepass 的輸出行序來自兩條串流的事件，跨串流的先後只是近似；首錯行本身與回溯內容不受影響。
