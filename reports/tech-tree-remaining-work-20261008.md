# 科技樹 v2.4 剩餘工作清單（2026-10-08）

依據：`tech-tree-v2-draft.v2.4-stage.md`（已含 2026-10-08〔審核〕註）與使用者貼出的 2026-10-08 20:11 現況核對。整體狀態 **OPEN**。「候選程式已準備」不等於「整合驗收完成」；Ecology 7／31 PASS 不能換算成科技計畫完成率。

## 0. 已完成（只作基準，不再重做）

- 計畫 v2.4：40 節點（家族 15／聚落 13／國家 12）、D01–D12、T2／T3／T5／T6／T7 已確認；驗收 A01–A20、G01–G08、L01–L03 已寫定。
- 候選程式：40 節點均有候選；39 個有具名來源，N08 由 Region 提供接點。正式 D 工作區已有未提交的 `site_technology*.gd`／`site_tech_window.gd`。
- Ecology 嚴格 PASS 共 7 項：C33 有 5 項，C36 Caller 8 組（119.953 秒），C39 Policy 8 組（33.753 秒，109 個 assertion 未改）。
- 隔離 C 來源檢查通過：2,830 個檢查、1,284 筆 metadata、14 個 Stage 候選一致。

## 1. 先決修正（開始整合前）

| 項目 | 缺什麼 | 前置 |
|---|---|---|
| ~~職責 ID 統一~~ **已決定：文件已改** | 使用者 2026-10-08 決定統一用 `family.teach`（程式現況）；計畫、職位計畫、NPC AI 計畫已改名，程式不動 | 無 |
| 家族移交入口 | **驗收規格已改寫（見 §1.1），尚未執行**。`_transfer_family` 已改為 `family_transfer_guard` | 執行需第 3 階段 |
| C39 整批收據 | C39 目前只有 Policy 單支 PASS，沒有整批完成收據 | 無 |

### 1.1 A18 按新移交入口改寫的驗收規格（2026-10-08，文件；未執行）

新入口的實際路徑：
- `RegionSaveSlot.region_family_transfer_guard(first, second)`：
  - 任一端 family 不是 v1、v2、v3 → 回 `INVALID_FAMILY`。
  - family v3，或 party 的 `family_refs` 帶 technology → 交給 `region_technology_transfer_guard`。
  - 該 guard 沒回傳合同 → 回 `INVALID_FAMILY_TRANSFER`。
- **出發**：只有 `transfer_token`、`source_site_id`、`travel_holder_site_id == "travel:"+token`、非空的 `region_movers` 全部成立，才呼叫 `RegionTechnology.prepare_holder_departure`；缺任一欄就拒絕。
- **到站**：需要 `arrival_mapping.token == party_id`、person 映射非空且是單射的正整數，還要有 FamilyRef。
  - 符合條件就呼叫 `RegionTechnology.prepare_holder_arrival`。
  - 判定同族：`family_id` 相同且目的地 family 非空。
  - NPC 異族時，目的地 family 傳空字典，不取得玩家族的資料。

A18 改寫後的命名案例（原 A18 的意圖不變，只把呼叫點換成上述入口）：
1. **A18-a 同族出發→到站：** 2/3 項目的持有者只有一個。出發後來源 Site 不能續跑；到站後 person ID 經映射，技能和證據都在。
2. **A18-b 異族到站：** 不合併項目。離族者的技能跟著本人；原族項目留在原持有者。
3. **A18-c NPC 異族：** 不取得目的地玩家族的 family、控制或名冊。
4. **A18-d 目的地沒有已登錄家族：** 不新造 family；不支援的情況要在歸檔之前拒絕。
5. **A18-e 負向：**
   - 缺 token、source 或 closure；
   - `travel_holder_site_id` 錯；
   - 映射不是單射，或含 0、負數、1000000000；
   - 缺 FamilyRef；
   - family 版本未知。
   以上都要拒絕，且原現場和原檔不變。
6. **A18-f 跨地死亡接續：** 沿原 `SiteFamilyContinuity.choose`；不能在 `archive_current` 之後整份複製科技資料。
7. **A18-g 舊資料：** 沒有 family_id 的舊資料不能靠同號人或現任家主推認同族。

## 2. Ecology 驗證（第 8–31 項，共 24 項未跑）

> **負責：生態永續計畫審核討論串（2026-10-08 起）。** 該討論串把生態候選直接移植到正式 D 執行：沒有開新分支，仍在 master，也沒有 stash、reset 或 checkout。檔案層級的備份放在 `output\ecology_d_port_20261008\backup_before`。它在改的檔案有 site_environment、site_runtime、site_store、terrain_lab、site_offices、site_settlement、site_controller、site_resource_view、site_work_team、region_save_slot，另有 3 支既有測試和約 17 支新的 site_ecology_* 測試。科技樹討論串在這段期間不改這些檔案、不跑 Godot，等對方通知完成。

- 內容：政策邊界、治理、資源、野生動物、工作團隊、火災、Region 往返與保存、官職、監獄、建築 UI、GPU，以及兩項 E3 長時間測試。
- GPU 證據：四張 GPU 圖須逐張看實際像素。
- 長時間證據：兩項 E3 須保留實際資料並核對收據。
- 前置：C39 收據。之前 Godot 測試鎖的等待條件已解除。須沿用 canonical `verify_godot.ps1`，結果保留在 `.godot-temp/godot_verify`，最多 100 次。
- 會影響第 3 階段的項目：Region 往返與保存、官職、工作團隊。這三項失敗會直接擋住 Core 整包。

## 3. Core 整包接入（隔離 C）

**唯讀核對結果（2026-10-08）：** 依 `tech-implementation\full40-future-execution-descriptors\20261008_identity_pending_v1\ORIGINAL_154_FUTURE_EXECUTION_DESCRIPTORS.v2.json`：
- 次數：154 列，serial 1–154 連續；142 個不同 ID，12 次刻意重跑，與原數字一致。
- 來源釘選：308 個（每列兩個），SHA256 全部和現檔一致，沒有漂移，指向 142 個不同來源檔。
- 組成：GD 一般測試 149 次、Native 5 次；visual 145 次、headless 9 次。
- 時間：timeout 合計 28,830 秒，最壞約 8 小時。
- 另有 C06 profile 5 組，沒有算進 154 次。
- **尚缺的接入條件：** 描述檔的 project_root 指向隔離 C。manifest、audit、source epoch、preflight、strict inspector 目前全部是 `PENDING_REGION_ACTUAL_CORE_READY` 或 `PENDING_FUTURE_ACTUAL_COHORT`；狀態是「不可執行」。
- **接入步驟：**
  1. Region 先把實際的 Core 複製進隔離 C，產生 manifest 和 audit。
  2. 凍結 source epoch 和 preflight。
  3. 綁定 strict inspector。
  4. 依描述檔串行跑完 154 次，每次跑完立即歸檔五個檔案。
  5. 每批前後各做一次來源 audit。
  6. 切換 Native DLL 前要關閉 Godot。

- 由 Region 把 Core 整包複製接入隔離 C，跑原 154 次串行驗證：已備 174 份測試來源、142 個登記 ID，其中 12 次是刻意重跑。
- 這一階段才真正驗 P1（F07 首包）的 A01–A20：首次學會、權限、師徒雙占用、原交易語義、共同疲勞、保存、身分／名冊、搬移、舊檔、UI、重學、離族、預算、證據生命週期、職責交接、雙方提交、跨地、營地核額、具名隊伍同意。
- 前置：第 2 階段的 Ecology 第 8–31 項（至少 Region、官職、工作團隊）通過；第 1 階段的 ID 統一。

## 4. Native 與專項實測

| 項目 | 還缺什麼 | 前置 |
|---|---|---|
| Native 五項 | 全部未跑 | 第 3 階段 |
| C06 接觸情境 | 獨立情境未跑 | 第 3 階段 |
| D10 F04（鋼／鋼工具） | G01–G08 逐類實測，含零鋼起步的研究自舉（第 5.4 節） | 第 3 階段＋F04 研究試作契約 |
| D10 F06（毛紡） | G01–G08 逐類實測 | 同上 |
| D10 F11（攻城塔） | G03 師傅留場、G05 器械試驗收據（build 清空前提交） | 同上 |
| D10 F12（配重投石機） | 同 F11，另驗牽引投石機實績前置 | F11 |
| TECH-AI-01 | NPC 自動完成 0/3→3/3 的正向測試；2/3 存讀後續完；負向覆蓋（權限、同意、交戰、疲勞、缺料、額度） | P1 的 A01–A20 通過 |
| TECH-AI-02 | 四類分別驗 G06：指定工匠真製造、技能保存、讀檔／加入勢力／切換不重發、失去工匠停效 | 對應 D10 類別 |

注意：
- D10 每一類通過後，才能加入之後新建世界的政策（`SiteTechnologyPolicy.new_policy`），各類不必互等。
- TECH-AI-01／02 都不代表 NPC 能自主研究全部科技或規劃生產。

## 5. 正式 D 合併與發布

1. **語意合併：** 正式 D 有 Claude 的官職／社會狀態改動，最新檢查是 9 個既有檔變動、7 個新增檔。須保留兩邊行為，不能用隔離 C 直接覆蓋。
2. **正式版回歸：** 合併後重跑相關回歸；歷史預期值不重設。
3. **效能與發布驗收：** 按原計畫要求。
4. **CLOSE 條件：** 以上全部有命名收據。

## 6. 平行追蹤（不擋科技 CLOSE，但仍 OPEN）

- **Audio V27：**
  - 已有：元件／設定測試局部通過；17 個補充音效候選獲使用者同意保留。
  - 還缺：整合播放、實機聽感、效能、發布驗收。
- **後續玩法 L01–L03（T2 離線 0.5 倍、T5 俘虜勞動、T6 器械分析）：** 屬 P4 以後，未展開前不可啟用。
- **其餘 39 節點的展開：** 每個節點都要補可見操作、成本、驗收；開發接點未完成前不可收研究成本。聚落 P2（S07）與國家 P3（N01／N04／N05，依 D09 可能合併）都還沒開始驗收。

## 6.5 Claude 接手準備（2026-10-08 22:20，唯讀）

- 使用者選定由 Claude 主導推到 CLOSE。開工條件：Codex 已停（使用者本人告知）、Godot 程序 0、無共享測試鎖。22:11 時 Codex 的 Region 討論串仍在跑 `region_initial_world_transaction_test.gd`。
- 隔離 C：`C:\Users\Nekki\.codex\visualizations\2026\09\26\01a0def5-6320-7ba0-84af-45301ed38863\region_party_isolated_project`。它和 Region 討論串放在同一個資料夾。
- 清單與 audit：manifest `region_party_isolated_manifest_v45_policy_combat_grace.json`（SHA D3811F48…），audit SHA D7175E4B…。
- C39 起點：`tech-implementation\run_original_ecology_queue_c39_v2.ps1`，參數 `-StartIndex 8`、`-ManualPolicyStamp 20261008_184417_711`。第 8 項是 `site_ecology_policy_border_test.gd`；Policy 那次單支 PASS 不重跑。收據目錄 `original-ecology-queue-c39-run-receipts-v1` 目前是空的，代表第 8–31 項尚未執行。
- 收據格式：
  - runner 開跑前先用 SHA256 核對所有釘選檔，再逐項寫 strict stdout／stderr 記錄，已存在的記錄不覆寫。
  - 每次執行的 epoch 寫在 `isolated-verification\<test>\<stamp>\source_epoch.json`。
  - 保存的執行證據放在 `stage\output\tech_tree_implementation_20261007\runtime-evidence\verified-runs\<stamp>\`。
  - 各批收據為 `C3x_ACTUAL_VERIFICATION_RECEIPT.v1.json`。
- 開跑前要確認：20:09 之後的 `preflight_cohort_c39_v3.py` 有沒有改變釘選；若有，以 v3 為準，再判斷 runner 是否要對應更新。

## 7. 建議接續順序

1. 第 1 階段：ID 統一、移交入口重驗、C39 收據。
2. 第 2 階段：Ecology 第 8–31 項，加上 GPU 與 E3 證據。
3. 第 3 階段：Core 154 次串行驗證，含 A01–A20。
4. 第 4 階段：Native、C06、TECH-AI-01。
5. D10 逐類（F04→F06→F11→F12），每類同時完成對應的 TECH-AI-02。
6. 第 5 階段：正式 D 語意合併、回歸、效能／發布，然後 CLOSE。
