# 驗收流程效率檢討（2026-10-12）

- 範圍：只看驗收工具與流程，不動遊戲程式與測試本身。資料來源：`output/d_integration_20261009_024321/runs` 下 3,398 筆 canonical `result.json`（10/09 02:24 起到 10/12 07:20），加上 CC-001 第 1–149 列 a3a4020 重跑、科技線逐列分類、指揮中心狀態板第 2 節、`cc_run.ps1` 與 `cc001_rerun.ps1`。
- 產物：`tools/acceptance/`（5 支腳本＋README＋過時測試登記檔，詳第 4 節）；分析輸出在 `output/acceptance_efficiency_20261012/`（`triage/triage.md`、`timeout/timeout_baseline.csv`、`batch_plan/batch_plan.md`、`trim_run_logs_report.json`）。
- 未做：沒有跑 Godot（prepass 只用假執行檔驗過早停與日誌上限）；沒有刪任何檔；canonical `verify_godot.ps1` 未改。

## 1. 驗收時間花在哪裡

| 項目 | 數字 |
|---|---|
| Godot 總時數 | 38.4 小時（3,398 次；1,902 PASS、1,496 FAIL） |
| PASS 佔用 | 10.3 小時（中位數 11 秒，94% 在 60 秒內） |
| FAIL 佔用 | 28.1 小時（73%） |
| 其中逾時 | 116 次、7.0 小時 |
| 同一測試＋同一首錯重複跑 | 711 次、10.3 小時（第一次之後的都算） |
| 日誌 | 22.4 GB；22 個 run 超過 50 MB 就佔 20.7 GB |
| 空轉 | 連續 run 之間的間隔中位數 0.5 秒，槽本身沒有閒置問題 |

結論：**近四分之三的 Godot 時間花在失敗的 run，而失敗 run 裡最貴的兩塊是「失敗後不中止直到逾時」與「同樣的失敗反覆再跑」。** 通過本身很便宜。

## 2. 失敗分類（首個錯誤）

| 類別 | 次數 | 小時 | 判讀 |
|---|---|---|---|
| ASSERT（測試斷言） | 560 | 11.1 | 真正要看的：程式缺陷或夾具脫節，需逐群判讀 |
| OTHER_ERROR（測試基底自訂 `*_FAIL:`） | 260 | 3.3 | 同上 |
| PARSE_STALE（解析錯誤、父類別找不到） | 247 | 0.8 | 過時測試／基底檔當時壞掉的連鎖；164 支測試受影響，一支基底壞就拖垮整批 |
| TIMEOUT | 116 | 7.0 | 見第 3 節，大多不是負載 |
| API_MISMATCH（屬性不存在、型別不符、null 呼叫） | 105 | 1.3 | 幾乎都是測試或夾具跟不上生產碼（過時測試） |
| NO_MESSAGE（只有退出碼） | 77 | 0.2 | 驗證器抓不到失敗行；退出碼 2 多半是 Godot 參數或場景錯 |
| INITIAL_WORLD（`REGION_INITIAL_WORLD_TRANSACTION_FAIL`） | 73 | 3.4 | 共用同一基底的 26 支測試；一個基底問題重複算了 73 次 |
| TEARDOWN_NOISE（material is null、await 後實例消失） | 27 | 0.2 | 收尾雜訊，測試印了 PASS 仍被判 FAIL |
| LEAK_AT_EXIT | 25 | 0.5 | 退出洩漏，7 支測試 |
| GPU_DESCRIPTOR | 3 | 0.3 | 3 次就寫了 2.8 GB 日誌 |
| DICT_RECURSION | 3 | 0.1 | 第 62 列那類遞迴印字 |

同一首錯跨測試的群很集中：93 支測試共用 `Assertion failed.`（無訊息的 assert），20 支共用 `material is null`，17 支共用 `set_process on null`，16 支共用同一個 `mounted` 型別推斷解析錯誤，14 支共用 `tick()` 簽名不符。**先跑每群一支代表列，代表過了再跑其餘，是最省的排法。**

估各類佔比（以 FAIL 的 28.1 小時計）：真正要人判讀的程式缺陷或夾具脫節（ASSERT＋OTHER＋INITIAL_WORLD）約 63%；流程與環境（逾時、洪水日誌、GPU、洩漏、收尾雜訊、無訊息）約 29%；明確過時測試（解析錯、API 脫節）約 8% 的時間但佔 24% 的失敗次數。扣掉重複跑，實際需要人看的新失敗遠少於 1,496 次。

## 3. 最花時間又最沒價值的部分

1. **失敗後不中止。** 116 次逾時中有 60 次的測試在別處曾經 PASS，33 支測試 PASS 最長時間不到逾時的三分之一（例如 `site_technology_window_scope_test` PASS 8 秒卻 8 次逾時 120 秒、`fire_pot_*` PASS 8 秒逾時 120 秒、artisan 系列 PASS 12–36 秒逾時 210 秒以上）。這些是斷言失敗後迴圈繼續跑、每幀重印同一條錯誤，直到驗證器逾時殺掉；不是負載。
2. **洪水日誌。** 最大的 run 2.8 GB，是同一條 assert 每幀重印；canonical 把 stderr 寫成 `stderr.log`，再與 stdout 合併成 `combined.log`，Godot 自己又在 appdata 寫一份 `godot.log`，所以同一段文字在一個 run 裡就有三份；`cc_run.ps1` 把 run 複製到 `output/.../runs`，`cc001_rerun.ps1` 再複製到 evidence，於是同一段文字共有九份。目前 runs 22.4 GB 中，`combined.log` 可由 stdout＋stderr 重建的有 7.5 GB，appdata `godot.log` 7.4 GB；evidence 另有 14.7 GB、`.godot-temp/godot_verify` 3.9 GB。
3. **同樣的失敗再跑一次。** 711 次、10.3 小時是「同一測試、同一首錯」的第二次以後。最多的是 `site_technology_siege_yard_test` 同一個 BUSY 錯誤跑了 35 次、artisan f11 同一個 INITIAL_WORLD 錯誤 17 次、`site_n11_first_earned_armor_test` 同一個 assert 14 次。
4. **驗證器逾時比測試內 deadline 短。** 10 支測試（crowd 系列 180 秒 vs 測試內 220–600 秒、`region_cold_original_matrix_test` 300 vs 360）會被驗證器先殺，測試自己的報表與退出碼來不及印，收據只剩「逾時」，診斷資訊全丟。
5. **基底檔壞掉拖垮整批。** 247 次解析錯誤中大多是父類別或 preload 當時解析失敗的連鎖，整批跑完才知道；這類在批次開始前用一次 check-only 就能擋下。
6. **CC-001 重跑的結構。** a3a4020 那次 212.6 Godot 分鐘：PASS 只佔 18.5 分鐘，逾時 74.5 分鐘，其餘失敗 119.6 分鐘。以新排序看：上次 PASS 的 42 列 22 分鐘、19 個代表列 24 分鐘、19 個獨特失敗 34 分鐘、可延後的 51 列 76 分鐘、上次逾時的 17 列 56 分鐘。

## 4. 已落地的工具（`tools/acceptance/`，只新增檔案）

| 腳本 | 解決什麼 | 已驗證 |
|---|---|---|
| `triage_receipts.ps1` | 讀 result.json 自動分群、同首錯群與代表列、重複跑、洪水日誌、逾時判讀（HANG_OR_FLOOD／LOAD_OR_REGRESSION／NEVER_PASSED）、過時候選；輸出 `triage.json`＋`triage.md` 可直接貼狀態板 | 對 3,398 筆跑過，結果即本報告數字 |
| `godot_prepass.ps1` | 分流預跑：串流讀輸出，首錯後寬限 5 秒即停、日誌上限 20 MB、連續重複行折疊；只殺自己以 PID 啟動的程序；結果標 `acceptance: false`，寫到 `.godot-temp/godot_prepass/`，不進正式 runs | 假執行檔：每幀重印的 assert 2.5 秒就停（原本會跑滿逾時）、1 MB 上限 21,909 行折成一行 |
| `trim_run_logs.ps1` | 日誌體檢：找逐位元組相同與可重建的重複、超大日誌；`-WriteDigest` 在超大日誌旁加 head／tail／重複行直方圖摘要。**不刪任何檔** | 對 runs 跑過：可重建 7.5 GB、appdata 7.4 GB、22 個大 run 20.7 GB |
| `timeout_baseline.ps1` | 每支測試 PASS p50／max、測試內 deadline、參考逾時、「驗證器逾時 < deadline」錯配、疑似卡死；**只是參考，不改驗收逾時** | 832 支：10 個錯配、33 個疑似卡死 |
| `batch_plan.ps1` | 批次排序：上次 PASS → 每群代表 → 獨特失敗 → 同群延後 → 上次逾時 → 無收據；登記為過時的測試預設跳過 | 對 CC-001 149 列排過：42／19／19／51／17／1 |
| `stale_tests.json` | 過時測試登記檔（空），需擁有線同意才登記 | — |

## 5. 建議的流程改法（需要指揮中心採用，部分要 Nekki 決定）

1. **批次照 `batch_plan` 排，延後列等代表過了再跑。** 以 CC-001 為例，先跑 PASS＋代表＋獨特失敗 80 列約 80 分鐘就能得到全部新資訊；51 個延後列只在代表修好後補跑。
2. **已知失敗先用 prepass 定位，修好才用 canonical 取收據。** 逾時 17 列從 56 分鐘降到約 5 分鐘；洪水日誌不再產生。canonical 仍是唯一收據，規則不變。
3. **批次前先跑一次 check-only 的編輯器掃描**（已有 T0 做法），任何解析錯誤直接擋住整批，避免 247 次連鎖失敗。
4. **evidence 與 runs 只留一份日誌。** 建議 `cc_run.ps1` 複製時略過 `combined.log` 與 `appdata/`（兩者都可由 stdout＋stderr 重建或是同一內容），evidence 再從 runs 做硬連結或只放 `result.json`＋`log_digest`。對既有 22 GB＋15 GB 是否清理，請 Nekki 決定；本線沒有刪任何東西。
5. **逾時錯配的 10 支測試**：驗證器逾時至少要大於測試內 deadline 加 30 秒，否則收據沒有診斷價值。這是「加長到能印出報表」而不是放寬驗收，但依規則仍請指揮中心轉 Nekki 決定。
6. **過時測試登記。** 解析錯與 API 脫節共 235 支測試候選；由各擁有線確認後登記到 `stale_tests.json`，統計與批次就不再把它們算成程式缺陷。
7. **測試基底在失敗後應該停止迴圈**（第 62 列遞迴、fire_pot 每幀重印）。這是測試程式的事，不在本線範圍，已在分群表裡標出，交科技線。

## 6. 證據路徑

- 分群：`output/acceptance_efficiency_20261012/triage/triage.md`（含前 25 名群、重複跑、洪水、逾時判讀、過時候選）
- 逾時基線：`output/acceptance_efficiency_20261012/timeout/timeout_baseline.csv`、`timeout_baseline.json`（`deadline_mismatch`、`hang_suspects`）
- CC-001 排序：`output/acceptance_efficiency_20261012/batch_plan/batch_plan.md`
- 日誌體檢：`output/acceptance_efficiency_20261012/trim_run_logs_report.json`
- prepass 假執行檔驗證：本線 scratchpad `stub/prepass/`（不屬專案，未保留）
