# 提案：鎮上每幀的「雙重檢查」能不能少做一次

狀態：提案，只寫不動。2026-11-28 指揮中心。等 Nekki 決定要不要做、做哪一層。

## 為什麼寫這份

劇本 A 溪前鎮（選現成人物、首長、37 人、有畫面），圖集烘完後的穩定每幀約 47.6 ms（約 21 fps），其中 Lab 模擬約 40 ms（量測：`scenario_existing_person_capture.gd --role=leader --wait-atlas --frames=900 --profile`，證據 `output/project_command_center/evidence/TOWNFRAME_1127/EXATLAS1_stdout.log`）。

11/27 已做的「答案不變」捷徑（40ed312、405c2a9、6196a31、5b2af05、426dacc）把容易的部分削完了。剩下的大頭幾乎都是共同工作管線裡刻意的「先純檢查、再實際做」：

| 階段（每幀） | 毫秒 | 做什麼 |
|---|---|---|
| 收集共同工作 `nb_collect_work` | 13.3 | 選工作、工作預檢、跑者與恢復輸入、補給結算 |
| └ 工作預檢 `cw_preflight` | 2.9 | `apply_shared_preflight` 對每個工作群再跑一次 `_prepared_context`（選工作時已跑過一次 `work_preflight`） |
| 前綴擷取 `nb_capture_prefixes` | 3.0 | 各 provider 的合法起點擷取 |
| 開步窗口 `shared_window` | 3.6 | `validate_native_begin_shared_window`：用「預估計畫」把全部前綴純檢查一次＋補給點驗證 |
| 生命結算／身體前綴 `life_body_prefixes` | 4.1 | `_finish_native_checked_body_prefixes`：用「實際計畫」再檢查一次全部前綴＋補給點驗證，然後發布 |
| 原生開步界限 `nb_bound` | 3.2 | 兩份工作疲勞計畫（下界、上界） |
| 補給點 `nb_sustain` | 1.9 | 整份建補給列＋兩次投影 |

同一份 captured 前綴在一幀裡被驗兩次（`_check_original_shared_prefixes`：開步前用 projected_plan、身體走完後用實際 plan），補給點也驗兩次；工作群在選工作時和預檢時各算一次。

## 兩次檢查不是完全一樣

- 第一次（開步前、`before_body = true`）用預估計畫，目的是在「射箭扣箭、原生 READY」之前就擋掉會失敗的前綴，失敗時什麼都還沒花掉。
- 第二次（身體走完後）用實際計畫，並且把訓練掛到原生 World 的點上（`prepare_work_training_point`）。實際計畫可能和預估不同（戰鬥、疲勞帶、補給結果）。

所以不能直接刪掉任何一次。能省的只有「兩次的輸入完全相同」的情況：和平時期多數幀，實際計畫等於預估計畫，中間也沒有任何來源被寫過。

## 選項

**A. 什麼都不改（目前狀態）。** 穩定 21 fps；之後的優化只做「答案不變」的小捷徑，每次約 1–2 ms。

**B. 同一幀、輸入相同就重用第一次的純檢查結果（建議先評估）。**
- 第一次檢查時，記下它讀過的來源的「版本」：每個工作群的任務／貨物／物品欄的版本、地點環境版本 `environment_revision`、倉庫與補給紀錄的 `revision`、訓練與運補紀錄，加上 projected_plan 本身。
- 第二次檢查前，比對實際 plan 是否與 projected_plan 相同（同一份分配、同樣秒數）且所有版本都沒變；都相同就直接用第一次的結果，只補做「把訓練掛到原生點」那一步。
- 任何不同（含戰鬥中、計畫被切短、有人收工、有貨進出）就照舊完整檢查。
- 預估省下：約 3–4 ms／幀（身體前綴那次的大部分）。
- 風險：版本沒涵蓋到某個被讀的來源，第二次就可能漏擋。需要逐一列出 `_check_original_shared_prefixes` 讀過的每一種來源；現在多數來源沒有版本號，要補。這是改設計，不是捷徑。

**C. 工作預檢只做一次。** `prepare_work_requests` 選工作時已經算過 `work_preflight`，`apply_shared_preflight` 再用 `_prepared_context` 算一次，是為了在「付款與移除其他請求之後」重新確認水量與產能。可以改成只在有請求被移除、或有付款改變水量時才重算。預估省 1.5–2.5 ms。風險比 B 小，但同樣需要證明「沒移除、沒付款」時兩次答案一樣。

**D. 補給點只建一次列。** `settle_native_supply_begin_endpoint`（收集時，會寫）和 `prepare_native_sustain_point`（開步時）各整份建一次補給列（含深複製倉庫）。改成第二次重用第一次寫完之後的列，需要證明兩者之間沒有任何補給來源被寫過。預估省 1–1.5 ms。

## 怎麼驗

- 每個選項都要有「兩條路答案相同」的探針：同一個存檔跑 N 步，一次走重用、一次強制完整檢查，比較每步的世界摘要（`--replay-trace`、共同步進重播測試 `site_shared_step_replay_test` 的雜湊）。
- 完整回歸 290 項，外加工作／住宅／補給／船／攻城家族；劇本 A 長跑（16 倍、15 遊戲日）不能出現新的 STALE 或時鐘停住。

## 建議

先做 C（範圍小、可證明），量到效果再決定 B。B 要先盤點來源版本號，可能是半天到一天的工作。D 最後。三個都不碰畫面或圖集。

## 要 Nekki 決定的

1. 要不要開始 C？
2. B 值不值得投入（約 3–4 ms，換來要維護一組來源版本號）？
