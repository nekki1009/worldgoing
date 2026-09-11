# Terrain Lab 隊長交換位置與導航解卡實作計畫

交付對象：Luna Max。日期：2026-09-09。
狀態：已實作第一版；保留本文作為驗收契約，實測結果見文末。
本文修正 `TERRAIN_LAB_ARMY_PERFORMANCE_PLAN_LUNA_MAX.md` 中與本問題相關的導航驗收；原本短時間 FPS 結果不能作為移動完成證明。

## 1. 目標與範圍

在現有 100×100 Terrain Lab、1 隊長 + 99 名普通士兵的 TerrainArmy 中，讓隊長可以與相鄰己方隊員交換位置，穿出被己方包圍的隊形並繼續跟隨 PLAYER／執行邊緣移動。

交換是兩個角色交換所在格，絕對不是交換角色 index、模型、隊長身份或整筆人物資料。隊長固定 index 0。每格一個邏輯占有者，雙方通行都必須符合 TerrainData.can_step。

本次沿用 TerrainArmy、Packed 資料、99 人烘焙圖集和既有即時隊長呈現。維持 terrain_cell、64px cell、MOVE_DURATION、相機及腳底 anchor。不要新增軍隊系統、物理角色碰撞系統、MultiMesh、戰鬥或 World/Region/Site 整合。

第一版只允許隊長主動發起隊長↔隊員交換；普通兵之間不做任意交換或連鎖推擠。普通兵壅塞另以等待／空格讓位處理，不能宣稱雙人交換解決所有多角色導航。

## 2. 已核對的根因

| 位置 | 現況 | 必須修正的行為 |
|---|---|---|
| terrain_army.gd::_next_step | 先排除所有其他隊員占格 | 隊長的靜態路線意圖可以指向己方隊員，交給交換檢查處理 |
| _simulate_step | 第二次遇到 _cell_owners.has(next) 就等待 | 分流普通移動與交換，不可只刪掉占格 guard |
| _complete_move | 逐人 erase 舊格再寫新 owner | 雙人交換必須一次提交，禁止分別呼叫此函式 |
| _find_follow_goal | 己方占用的候選全部排除 | 允許可交換友軍所在格成為候選；外部角色／非法地形仍拒絕 |
| _replan_follow | player/captain 沒換格就直接返回 | 己方讓位後可能有新機會，需有局部阻擋重試，不能永久沿用失敗結果 |
| _find_path | 2048 frontier 上限用完直接回傳空路徑 | 預算耗盡是 PENDING，不是 UNREACHABLE；保留搜尋並於下幀繼續 |
| blocked_time | 只有被 planning cursor 選到才增加 delta | 改為每 simulation tick 累計實際等待時間，讓超時與退讓一致 |
| army_test::_verify_ramp_corridor | 未斷言抵達，地形只有上坡沒有跨牆下坡 | 建立確實可達的測試，斷言越過入口／到達目標 |
| army_performance_test | 只採樣 180 frames，不記錄完成步數 | 必須證明取樣期間軍隊真的前進，不能以停滯換取高 FPS |

另外，現有 headless 測試直接呼叫 _simulate_step，沒有走 _process 的導航預算。必須增加共用 frame 驅動入口，讓測試和遊戲走相同預算流程。

## 3. 資料與交換不變量

沿用 cells、moving_to、movement_state、move_progress、facing、_cell_owners、_reserved_cells。新增最小資料：

- UnitState.SWAPPING：明確區分普通移動與交換。
- swap_partner: PackedInt32Array，100 筆，預設 -1；雙方互相記錄 index。
- 一個 active swap 記錄：因只有隊長可以發起，同時最多一組；包含 partner、原始 A/B 格、共同 progress、開始時 command/terrain generation、完成後重整標記。
- 同一 pair 的 cooldown／上次交換邊，防止立即反向交換；初始 cooldown 0.5 秒，以 simulation 時間計算。
- 必要的導航 generation 與有限診斷 counters，不新增每人 Node。

交換開始：隊長在 A，隊員在 B。

1. cells 和 _cell_owners 保持 captain→A、soldier→B。
2. _reserved_cells[B]=captain；_reserved_cells[A]=soldier。
3. 雙方 moving_to 設成對方原格，state=SWAPPING；使用同一進度，初始 0。
4. A/B 均對第三者保持阻擋；第三者不能認領原格、目標格或交換中的角色。
5. 交換中的雙方跳過普通 planning、普通 _complete_move 和其他交換。

交換完成：同一同步函式內完成所有資料變更，中途不 await、不發出會觸發其他移動的 signal。

1. 先驗證雙方 owner、reservation、partner、原格仍與交易相符。
2. 一次更新 cells[captain]=B、cells[soldier]=A。
3. 覆寫 _cell_owners[A]=soldier、_cell_owners[B]=captain；不呼叫兩次 _complete_move。
4. 只移除本交易所持有的兩個 reservation。
5. 清除雙方 moving_to、swap_partner、progress，恢復 IDLE／正確 ARRIVED。
6. 再發布計數／隊形失效通知。

每個 tick 後驗證：100 個唯一 cells；每個 cell 的 owner 和 index 一致；每個 reservation 對應一個有效移動／交換；沒人同時參與兩項動作。交換途中 owner 和 destination reservation 不同是受控例外，普通移動不允許這種情況。

## 4. 交換資格與排程

在隊長下一步意圖被己方阻擋時呼叫 _try_begin_captain_swap(blocker_index)。全部條件成立才能一次寫入，任何失敗都不得部分預約：

- initiator 必須是 index 0，另一方是同一 TerrainArmy 的 index 1..99。
- A/B 曼哈頓距離恰為 1，不允许斜向／隔格交换。
- 雙方不處於 MOVING/SWAPPING，沒有既有 moving_to，原格沒有其他動作的 reservation。
- TerrainData.can_step(A,B) 與 can_step(B,A) 都成立。水、非法峭壁、高差大於 1 拒絕；合法雙向 ramp 可交換。
- A/B 不被 PLAYER/NPC 當前位置或移動中目的地占用／預約。先追查 TerrainTestCharacter 的真實 movement 欄位，不另猜一份位置資料。
- swap generation 與現地圖有效；cooldown 通過；新的交換確實沿有效路線向隊長目標前進。
- 被交換隊員即使為 ARRIVED 也能讓位；提交後若離開目標，必須撤銷 ARRIVED。

排程順序：先完成已開始的普通移動／交換，再決定 captain 意圖和交換，最後依原輪轉 cursor 處理普通兵。captain 優先占用既有 planning budget 的一個名額，不因優先權額外放大預算。

交換參與者不可在同 tick 再開始普通動作；交換完成後至少到下個 tick 才開始下一次交換。已 MOVING 的隊員不可被中途拉回原格；隊長等待其到達後重新判定。

## 5. 下一步意圖、路徑與防震盪

將地形路線和動態占格裁決分開，但仍放在 TerrainArmy 內：

1. 用 TerrainData.can_step 決定靜態可達路線／下一步意圖。己方士兵不能直接被當成永久地形牆。
2. 下一格空閒：普通 move。
3. 下一格是可交換隊員：隊長啟動 swap。
4. 下一格是正在移動／預約的己方：等待、之後重新判定。
5. 下一格為外部角色：等待或有效繞路，禁止交換 PLAYER/NPC。
6. 靜態無路：報真正不可達；搜尋未完成：報 PENDING。

隊長不能每次挑任意相鄰隊員交換。使用完成的靜態路徑游標／到固定目標的距離下降作為前進依據，允許必要的繞障而不只依 Manhattan 距離。若沒有有效路線，先等待有預算的搜尋結果。

Follow：PLAYER 停住時保持有效 leader_goal，隊長按路線前進；不要因 captain 每換一格就選另一個近似目標導致來回。PLAYER 真正換格、地形失效、目標失效才重新選取。

隊員讓位後保持其人物身份與原隊形目標。若原目標已被隊長的新位置占用，延遲至交換完成後重分配受影響的隊形格，並排除隊長已占／預約格；不得在交換中改寫 active moving_to。

同 pair cooldown 是第二道保護，不能只靠冷卻掩蓋無進度震盪。固定 PLAYER 情境下，連續交换需有可測的路徑進度；真正改變指令／PLAYER 方向可讓 captain 規劃返程，仍等現有交易完成。

## 6. 指令切換與清除

- Follow→Edge 或 Edge→Follow：已開始的合法交換繼續到完成；更新下一個命令、取消舊 pending search，完成後依新命令規劃。
- 重新 Generate／clear／重新 deploy：同步取消舊交換、搜尋、reservation 和視覺狀態；新地圖不能收到舊 job 的結果。
- 同一地圖的停止／安全取消若需要保留軍隊：完成當前合法交換再停住，避免畫面中途回跳。
- 若未來允許 runtime 地形突變，單獨處理；本次禁止動畫期間任意改地形去測出假成功。
- clear 後 has_army=false、所有交換標記 -1、reservation 空；重新 deploy 100 人無殘留。

## 7. 顯示與占格的界線

沿用兩名人物的實際身高、縮放、foot anchor 和各自模型；普通兵在 SWAPPING 時播放 walk，隊長也應呈現移動方向／動作。moving_count 要包含交換參與者，避免交換動畫期間錯誤停用 live 來源。

雙方從 A/B 中心以共同 progress 同步插值，完成時腳底精確對齊新格；不可一人先瞬移，另一人稍後跟上，也不可顯示兩個隊長。

必須誠實處理幾何限制：一格寬的封閉通道容不下兩個有體積人物實體錯身。本階段接受邏輯雙人交換，插值中間可短暫交疊；這不代表角色物理碰撞通過。第一版使用現有深度排序並展示中段截圖。不要為掩蓋交疊，讓角色橫向踏進峭壁／水、縮小身體或飛起。若要求嚴格實體錯身，需要寬度／側邊空格規則，那會使某些一格通道交換不可行，屬另外的玩法取捨。

## 8. 導航效能：禁止以找不到路換 FPS

把目前截斷的 _find_path 改成可續跑 BFS：一個共用 Packed 工作區，保存 frontier/head/tail/previous、start/goal、requester、generation。frontier 容量能容納完整地圖，單幀只展開有限格數，不能限制整個搜尋只能發現 2048 格。

- 建议起始每 render frame 合計 512 格 + 約 1ms 軟時間預算（每 32 格檢查時間），依實測調整。
- head/tail 未耗盡且 budget 已用完：PENDING；真正走完 frontier 沒有終點才 UNREACHABLE。
- 搜尋可續跑，不能下個 tick 從原點重做相同前 2048 格。相同請求去重，結果消費前驗證 requester 起點／目標／generation。
- Captain 優先，其他請求公平輪轉；不得每個士兵配置一張一萬格搜尋陣列。
- 路徑反推 append 後 reverse 一次，或存可直接消費的完整路徑；不再重複 push_front。
- 距離場與 follow 重搜也共用預算。無路不重新每幀重算，地形或相關目標變動才失效；動態阻擋用局部重試。
- 抽出 advance_frame(delta) 或同等入口，_process 與 headless scenario 都呼叫它，確保預算在兩次 simulation tick 間共享。
- 保留 MOVE_DURATION=0.24、既有 SIM_STEP，先恢復 planning budget 12 作為比較基準；不可再降低軍隊前進吞吐量來宣稱優化。若 budget 8 保留，須量測相同任務完成時間並說明差異。

交换本身為 O(1)，不觸發整張地圖 BFS。這輪不做 GPU 尋路、多執行緒或新框架。

## 9. 檔案與實作順序

| 檔案 | 修改責任 |
|---|---|
| scripts/terrain_lab/terrain_army.gd | SWAPPING、原子 begin/commit、captain 意圖裁決、follow 目標穩定、可續跑 BFS、統計 |
| scripts/terrain_lab/terrain_lab.gd | 既有 army_info 顯示交換中／waiting 原因、completed steps、swap count；不建立新 UI 系統 |
| scripts/terrain_lab/terrain_test_character.gd | 只有當現有 API 無法查詢移動目的地時，補最小唯讀查詢；不重寫移動 |
| scripts/tests/terrain_lab_army_test.gd | 修正假通過測試，加入原子交換、拒絕條件、取消、實際抵達 |
| scripts/tests/terrain_lab_army_visual_test.gd | 真 Lab 的交換開始／中間／完成、腳底與身份驗證 |
| scripts/tests/terrain_lab_army_performance_test.gd | 相同 frame driver、進度計數、較長採樣、真正完成情境 |
| TERRAIN_GENERATOR_LAB.md | 新行為、測量、已知限制與操作方式 |

執行順序：

1. 讀目前檔案與上列測試，保留其他未提交修改。建立相鄰阻擋／隊長被包圍的失敗案例。
2. 實作並驗證雙人交換交易及清除行為；先不接所有自動策略。
3. 接入 captain 下一步意圖、優先排程、雙向地形檢查、目標重分配與防震盪。
4. 修復 BFS PENDING/UNREACHABLE，接共用 frame budget，驗證長路真的能搜完。
5. 接呈現、狀態資訊、實際 Lab 截圖；維持比例和腳底。
6. 跑下面精簡功能矩陣與效能測量；先修正卡死再宣稱性能通過。
7. 更新操作文件與實測結果，不自行擴大為全軍隊避碰／戰鬥系統。

## 10. 必須通過的功能與畫面驗收

### A. 最小交換

在平地將隊長置於 (40,40)，隊員置於 (41,40)，captain 目標在右方。實際觸發自動交換，非測試直接覆寫 cells。記錄開始／中間／完成，斷言雙方位置互換、身份不變、100 個 owner 完整、兩格 reservation 完整釋放。

### B. 第三者與移動中角色

交換期間另一名隊員、PLAYER、NPC 嘗試進入 A/B 都必須被拒絕。目標隊員正在普通移動時不得啟動交換；待其到達後可重新判定。把瞬間的外部角色 destination 納入測試。

### C. Terrain 拒絕／坡道成功

水、非法高度差、非相鄰、缺少雙向 ramp 都拒絕且不留殘餘預約。合法雙向 ramp 接近後交換成功。修正 _ramp_data：牆兩側必須有完整可通過的上／下坡或右側整片高台；不能只有上去、沒有下去的牆。

### D. 隊長穿出包圍

平地 100 人，隊長四周均為己方，PLAYER 在圈外固定位置。至少成功一筆交換，captain 在 30 秒 simulation 內到達有效 follow 距離；不能測試前把队长放在隊伍外圍。逐 frame 斷言 owner/reservation 完整，記錄 captain 路徑進度，不能只是 moving_count>0。

### E. 防止對換震盪與指令切換

PLAYER 固定，隊長不能在同一邊 A↔B 無限交換。完成後觀察至少 10 秒；隊長停止於合理 follow 範圍，受影響隊員有合法目標。中途切換指令，交換完成一次且服從新指令；Generate／clear 中途取消不留舊 job。重複部署／清除 10 次無殘留。

### F. 長路和完整抵達

設計必須探索超過 2048 格才能找到出口的合法地形，用同一 frame budget 跑到 FOUND；設計真正隔離地形則回 UNREACHABLE。驗證每幀展開量符合預算、pending 可續跑。

平地 edge 指令最多觀察 180 秒 simulation，要求 100 人到達分配的合法目標、最後 reservations 空。未達者輸出 index/cell/goal/blocker/status，判 FAIL，不能只檢查未穿牆。狹口情境至少要求 captain 實際跨越並繼續前進；若全軍仍壅塞，明確列為未完成，禁止混稱全員通過。

### G. 畫面檢查

真 TerrainLab，zoom 1×/2.2×：捕捉交換前、中段、交換後和隊長穿出隊伍。檢查人物尺寸／腳底／朝向／圖集、無黑框、無殘影、無瞬移和錯誤繞進障礙。檢查圖片實際可開啟，不能只報檔案存在。中段短暫交疊按第 7 節誠實標記。

## 11. 效能與完成判定

固定 100×100、100 人、2560×1440；PLAINS seed 24680，加 TERRACED_HIGHLAND seed 12345。每情境暖機 5 秒、取樣 20 秒，最慢案例重複 3 次；完整任務完成時間另外量測，與同 seed/goal 基準比較。

至少測無軍隊、待機、跟隨、邊緣前進、隊長被包圍後解卡。記錄環境／zoom／VSync/FPS cap、P50/P95/P99/max、>33.3ms 和 >50ms 幀數、completed_steps、captain_steps、swap_count、arrived_count、最長無進度時間、BFS expansions/frame、job pending/完成/取消、丟棄 simulation 時間。

目標為正常 60FPS 遊玩條件下 P95≤20ms、P99≤33.3ms；這是目標不是已驗證結果。若不符，報實值與瓶頸，不能靠少走路／停止模擬／丟更多時間通過。樣本期間若全員不動又未完成，效能案例直接不合格；全員抵達後的待機另列。

只有自動交換成功、合法通行、原子占格、解除包圍、無持續反向交換、長路搜尋可完成，且實際遊戲畫面和輸出通過，才回報功能完成。遊戲程式可運作、測試 PASS 字串或單一 FPS 數字都不足以替代上述條件。

## 12. Luna Max 完成回報

列主要修改檔案與用途、交換開始／完成的資料契約、觸發與拒絕規則、BFS 預算与續跑行為、實際到達／交換數、實測 frame-time 與完成時間、可開啟的真 Lab 截圖、剩餘問題。只列真正執行的測試，不把計畫或未跑的案例列成通過。

## 13. 本輪實作與驗證紀錄（2026-09-09）

已修改：

- `scripts/terrain_lab/terrain_army.gd`
  - 新增 `UnitState.SWAPPING`、雙向 `swap_partner`、0.5 秒交換冷卻與交換／完成步數計數。
  - 隊長只可與相鄰己方隊員交換；雙向 `TerrainData.can_step`、外部角色、reservation、移動中狀態都會先拒絕。
  - 交換以共同進度插值，完成時一次更新兩格 `cells` 與 `_cell_owners`，不經過兩次普通移動提交。
  - `moving_count`、士兵 walk 動畫、視覺插值都包含 `SWAPPING`。
  - 導航繞路改成單一 Packed frontier/previous 工作區，256 格一段續跑；不再用 2048 格上限把合法長路誤判成無路。
  - 新增 `advance_frame(delta)`，`_process` 與測試可使用同一套 frame 驅動邏輯。
- `scripts/terrain_lab/terrain_lab.gd`
  - HUD 顯示交換次數與已完成步數。
- `scripts/tests/terrain_lab_army_test.gd`
  - 新增平地四向包圍解卡、原子交換、非法峭壁拒絕、合法 ramp 入口、長路跨預算搜尋測試。
  - 修正 ramp 測試為雙側可往返的完整入口，並要求隊長實際越過入口。

已執行：

- Godot editor scan：PASS，EXIT=0。
- `terrain_lab_army_test.gd`：PASS；100 格唯一性、follow、edge、四向包圍交換後繼續前進、非法 cliff 拒絕、ramp 越過、198 格長路續跑。
- `terrain_lab_test.gd`：PASS，EXIT=0。
- `terrain_lab_army_visual_test.gd`：PASS；已檢查實際 `army_100_deployed.png` 與交換前／中段／完成截圖，99 名士兵使用 baked atlas、隊長保留單一 live 3D source，HUD 顯示 `Swaps / completed steps`。
- `terrain_lab_army_performance_test.gd`：PASS（GPU/D3D12/RTX 5060，2560×1440，PLAINS seed 24680）；baseline P95 16.793ms、idle P95 16.792ms、moving P95 16.775ms、P99 16.804ms、max 17.145ms、60 FPS；取樣期間完成 105 步，非停滯樣本。

目前未宣稱：完整 20 秒 GPU frame-time 矩陣、普通兵之間任意交換、嚴格實體寬度的雙人錯身。交換中段截圖已產生，但仍依本文第 7 節允許短暫視覺交疊；邏輯格子與地形通行不會因此穿越 cliff 或 water。
