# 專案指揮中心狀態看板

更新：2026-10-09 00:20（台北）。維護者：專案指揮中心討論串。
驗收標準：只有「正式 D:\worldgoing 上、由 canonical `verify_godot.ps1` 產生的 `result.json` 收據」算通過。隔離副本的通過、候選數量、單獨重跑都只列為「參考」，不算驗收。

## 1. 共用 Godot 時段

規則：同一時間整台電腦只跑一個 Godot。開跑前向指揮中心申請，跑完告訴指揮中心釋放。排隊順序只記在本看板；`.godot-temp/shared-godot-slot.json` 由驗證程式自己寫入和刪除，指揮中心不再寫它。（00:21 指揮中心寫過一份，擋住了 Region 的驗證程式，刪除被權限擋下，已請 Nekki 刪除。）

| 順序 | 線程 | 內容 | 狀態 |
|---|---|---|---|
| 完成 | 生態永續 | `output/ecology_d_port_20261008/bases.ps1`：4 項基準重跑 | 00:20 結束，3 FAIL、1 PASS（見下） |
| 現在 | Region 畫面遊戲進行 | profile 第 2 項 r1_original_travel（`region_travel_test.gd`），只跑一項 | 00:21 已放行，租約在 Region |
| 3 | 生態永續 | 剩餘失敗診斷、最後完整重跑 32 項 | 每批向指揮中心申請 |
| 4 | 科技樹 | Core 整包接入、154 次串行（最壞約 8 小時，145 次需可見視窗） | 另需 Nekki 確認 Codex 已停 |

**PID 6160 查明結果**：是生態線 `bases.ps1` 的第 1 項，父程序為 Claude Code 啟動的 PowerShell（PID 23632，00:08:24 啟動，`bases.ps1` 同一秒寫入）。canonical 驗證器在 303 秒逾時後自行結束它（收據 `.godot-temp/godot_verify/20261009_000825_136/result.json`，FAIL，timed_out）。不需要 Stop-Process。

`bases.ps1` 四項 D 上收據（指揮中心已逐一讀過 `result.json`）：

| run | 測試 | 結果 | 失敗原因 |
|---|---|---|---|
| `20261009_000825_136` | region_cold_original_matrix_test | FAIL（逾時 303 秒） | Physical ranged requires one original completed action slice |
| `20261009_001416_414` | region_travel_test | FAIL | MISSING_REGION_ADAPTER（第 41 行，經 `_captain_trip:370`） |
| `20261009_001848_676` | region_controlled_death_restriction_test | FAIL | BUSY：原火攻接觸／結構步進尚未完成 |
| `20261009_001921_409` | site_bridge_contract_test | PASS | |

三項 Region 失敗尚未證明是生態造成；生態線先前用原檔跑 D 基準時已有部分失敗。Region 線的第 2 項若跑在隔離副本，只算參考。
這組冷結算矩陣結果是生態線在「已併入生態程式、尚未併入 Region 修正」的 D 上的基準，**不是 Region R2 證據**。

## 2. 各工作線

### 生態永續計畫審核
- 已完成（D 上）：Codex 整併稿 64 處修改套入 13 檔，加 17 個新測試；原檔備份 `output/ecology_d_port_20261008/backup_before`；編輯器掃描無解析錯誤。
- 第一輪 32 項（D 上收據）：16 PASS、16 FAIL，紀錄全保留。其中 5 項舊回歸在換回原檔後也失敗，屬 D 原有問題（線程自述，收據在 godot_verify）。
- 已修並單獨重跑通過：合約／呼叫者逾時（負載造成）、政策測試（UI 快取漏狀態）、捕捉／基底守恆（測試資料改用 D 新牧場尺寸）。**這些是單獨重跑，最後完整重跑 32 項前不算最終驗收。**
- 新收據：`20261009_000825_136` 冷結算矩陣 FAIL（逾時，錯誤「Physical ranged requires one original completed action slice」）；`20261009_000439_874` 生態重播測試 FAIL。
- 下一步：診斷重播、長時間、政策邊界、Region 相關失敗；逐張看 GPU 四張圖；完整重跑 32 項；更新計畫 §13。
- 等待：時段（見上表）。

### Region 畫面遊戲進行
- 已完成：接手 Codex 交接；交接檔案齊全，profile 第 2 項與交接一致，來源雜湊重算一致（唯讀核對）。
- 未完成：交接說正式 D 尚未併入 Region 修正，但 D 上已有 `region_cold_original_matrix_test.gd`（10/08 00:52 修改）。R2 證據尚無 D 上收據。
- 下一步：取得時段後跑第 2 項，結果交指揮中心。
- 等待：時段第 2 順位。

### 科技樹研究（v2.4 推到 CLOSE）
- 已完成（不需 Godot）：A18 移交驗收改寫成 A18-a～A18-g（尚未執行）；Core 整包核對 154 次串行、142 個測試、308 個來源雜湊一致。清單：`reports/tech-tree-remaining-work-20261008.md`。
- 尚無任何 D 上驗收收據。Ecology 8～31 已改由生態線負責。
- 下一步：Core 整包接入與 154 次串行；Native、C06、D10 四類、兩個 NPC AI 實測；正式 D 合併、回歸、效能與發布驗收。
- 等待：Nekki 說「Codex 已停」；時段第 4 順位。注意：D 現在已含生態程式，Core 接入計畫需納入。

### 貿易功能規劃（V0.5）
- 已完成：審完 V0.5，Codex 17 項意見成立（抽 4 項對原碼重核）；附錄自檢 PASS；補 4 項改進到 §15（`reports/trade-plan.md`）。純計畫審核，不涉 Godot 收據。
- 下一步：T0 可開工；T6 需 Q12、Q13。
- 等待：Nekki 回答 Q12、Q13。

### 勢力劃分與修改計畫（V0.6）
- 已完成：V0.6 審核可採用，F1a 可開工；CR-02 Nekki 選 A（外交代理人），記在 `reports/faction-spec-v0.6-review.md`。
- 未完成：`FACTION_DIPLOMACY_SPECIFICATION.md` 尚未寫入 CR-02（§3.3、FA-04）；CR-01、CR-03、CR-04、CR-05 未改。
- 下一步：依 Nekki 指示先與審核者（Codex）溝通，再動手。
- 等待：與 Codex 溝通結果。

### AI 與職位工作分配整合
- 已完成（線程自述，已測、未 commit）：R0 拘押紀錄、人物社會狀態與存讀驗證、R2 不滿與忠誠核心、戰死比例事件、首次預兆提示。D 上收據路徑未在回報中列出，**尚未經指揮中心核對**。
- 待做：營務官與駐營兵募兵、資料格式交給 Region 線接線、伙食不足事件、回歸測試並更新 v2 計畫。
- 等待：Nekki 在該討論串打字確認三件事（見第 3 節）。

### 專案無用檔案清查
- 已完成：清查報告 `reports/cleanup-audit-20261008.md`（537 GB，可清約 420 GB），未刪任何東西。
- 等待：Nekki 決定刪哪幾類。建議清理前先 commit（最後一次 commit 是 09-27 V0.5R）。
- 注意：生態、Region、科技樹都還在用 `.godot-temp` 與 output，清理要排在 Godot 批次之間，不可與它們同時進行。

### 已結案
聚落中心建築與等級、台灣地圖接入遊戲入口、音效計畫審核。

## 3. 需要 Nekki 回答的問題

1. **科技樹**：Codex 停了嗎？停了請在科技樹討論串說「Codex 已停」。
2. **貿易 Q12**（和平和通商的差別）：建議 A，和平就能做所有當面交易，通商協定只多給稅率優惠。
3. **貿易 Q13**（稅怎麼收）：建議 A，只對資源課實物稅，按交易地稅率取整數；裝備和 coin 先不課。
4. **AI 職位**：請在該討論串打一行，三件都要回：Region 由 Region 討論串自己接線嗎？營務官要做嗎？伙食不足事件要等供養系統那邊告一段落再接（建議），還是「伙食現在接」？
5. **無用檔案清查**：刪哪幾類？建議先 commit，再只刪 A 類（約 210 GB 無引用快照與舊暫存）；B1（火攻、船隻收據引用的快照）等你確認不需重跑再刪。
6. **commit**：09-27 之後的工作都沒 commit，多條線同時改 D。要不要在生態批次結束後先 commit 一次當作還原點？（建議要）
</content>
</invoke>
