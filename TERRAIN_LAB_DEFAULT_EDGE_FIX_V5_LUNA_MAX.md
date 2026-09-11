# Terrain Lab V5：預設山地走到邊界修正計畫

日期：2026-09-10。實作交接：Luna，沿用 max 推理設定。

狀態：**已完成實作與 V4／V5 驗收（2026-09-10）。預設 EDGE 60Hz 在142.8秒完成99人通過五口、出清與落位，另穩定5秒；133組功能、8組GPU重播、7段活動效能與editor全PASS。當前版本、完整矩陣與證據見 `TERRAIN_LAB_V5_ACCEPTANCE_STATUS.md`、`TERRAIN_LAB_V5_EVIDENCE.json`。下列開工基線與原始失敗保留為歷史記錄，不是目前狀態。**

使用者確認的操作是「走到地圖邊緣，就是預設的 site 地圖」。本次已沿 Terrain Lab 實際預設生成與部署流程重現。範圍為 `TerrainArmy`，不是要求重寫正式 Site／World 系統。

本文件取代 V4 重疊的寬度計算、通道啟動、多段交接、舊隊列整合、驗收次序與完成聲明；V4 的合法移動、原子交易、固定槽位、99 人、效能及視覺驗收要求繼續有效。衝突依使用者指示、`PROJECT_ARCHITECTURE.md`、V5、V4 的次序處理。

## 1. 任務完成的意思

在不改預設地形、出生位置、速度與 99 人門檻的前提下：

1. 啟動 `scenes/terrain_lab/TerrainLab.tscn`，保留預設 TERRACED_HIGHLAND／seed 12345，部署軍隊，執行 MOVE_TO_EDGE。
2. 隊長走到正常選出的邊界目標；99 名隊員繼續依序通過必要坡口，不因隊長走遠或已到邊界而停在高台。
3. 每名隊員完成所有必要通道，離開受保護出口，到達發布的合法陣位；穩定 5 秒，沒有殘留移動、交換、推擠交易、claim 或 lock。
4. 正式 60Hz 更新流程、預設場景畫面與回歸測試都有對應證據。

`passage_active=true`、偵測到 5 個坡口、隊長到邊界、E01/E02 PASS、編輯器 PASS，都只是中間證據。只有完成上述行為及 §10 門檻，才可報「預設 EDGE 修好」；V4 其餘驗收未齊時，另列未完成，不能報整個 V4/V5 完成。

## 2. 開工基線與已確認證據

### 2.1 版本

工作目錄：`C:\Users\Nekki\Dropbox\竹北社大\(01)102-103學員資料\share\worldgoing`。

| 檔案 | 本文件核對的 SHA256 |
| --- | --- |
| `scripts/terrain_lab/terrain_army.gd` | `38708AE08CD94F360FD24853861F1BD7D541E0C7D925057063A0D9D458B2F242` |
| `scripts/tests/terrain_army_entrance_clearance_test.gd` | `C536203BECB0F145ABFD3AB261F59494BD29F6A19F125B274232E6CF38ACAA2D` |
| `scripts/terrain_lab/terrain_generator.gd` | `7682D17637499D721E1FE11D2673B11F5B6419E5FC9DDEF64C02262752EF37EE` |
| `scripts/terrain_lab/terrain_lab.gd` | `2F3FF58C1C5BF16C28E7B762C23B63E6451EAC46BD413B20E757D755F21E3D0C` |

這與前次宣告完成時的 army hash `F535F17FB1D7D8B94DD2F7276249E2C36547403CBFA5F26BED280F57C095C552` 不同。使用目前檔案作基線；不要覆蓋兩次之間的變更。相關檔案 untracked，Git HEAD 不能用來還原它們。

先保存將修改檔案的副本與 hash，再逐檔看差異；保留無關工作樹變更，不自行 stage、commit。下文行號是此基線的定位提示，修改前重新按函式名搜尋所有 caller。

### 2.2 真正的預設案例 D01

| 項目 | 已核對值 |
| --- | --- |
| 生成入口 | `TerrainGenerator.generate(TerrainPreset.Kind.TERRACED_HIGHLAND, 12345)`，不傳 overrides |
| 尺寸 | 100×100 |
| fingerprint | `c8a3021229df7f5f4324c39ee75fada205999efd74ec4f2cb13b481f12bc3367` |
| PLAYER／NPC | `(50,50)`／`(50,49)`；NPC 為 STOP，NPC 出生取實際 `_find_npc_spawn_cell()` |
| 正式 deploy 後隊長 | `(61,52)` |
| 正常 EDGE 目標 | `(99,75)` |
| 隊長靜態最短路線 | 254 個格點／253 條邊；這是目前生成資料的診斷值，正式最短距離另以測試 BFS 求得 |
| 初始 100 格 | 存於下方重播 log 的 `INITIAL_CELLS`；使用正式 deploy 重建並核對，不把該陣列灌回 runtime 幫測試過關 |

五条 route 高度轉換邊：

| 高度 | 實際邊 | 現版錯誤寬度 |
| --- | --- | --- |
| 5→4 | `(66,52) → (66,53)` | 11 |
| 4→3 | `(33,50) → (33,49)` | 11 |
| 3→2 | `(54,25) → (54,24)` | 5 |
| 2→1 | `(50,74) → (50,75)` | 3 |
| 1→0 | `(78,74) → (78,75)` | 9 |

独立同高度 flood 確認：隊長起始最高層連通區有 293 格，唯一合法離層邊是 `(66,52) → (66,53)`。相鄰平臺上的同高度邊不能算成並排下坡通道。

### 2.3 證據與限制

- `.godot-temp/entrance_failure_audit.gd`：隔離診斷，預設生成、正式 deploy、EDGE、`advance_frame(1/60)`；`--route-only` 為靜態路線／寬度調查。
- 重播：`.godot-temp/godot_verify/20260910_013036_810/stdout.log`。10～50 秒均有 93 名隊員停留在高度 5；18 秒 wall-time 診斷限制停止於輸入 55.7167 秒。此時 all 99 phase=NONE、active=false、capacity=0、assembled=0，多人等待約 48 秒。
- 這份重播沒有跑完 180 秒，也尚未看到隊長到邊界；不能聲稱已量完最終完成時間或永久死鎖。它確實證明隊伍長時間不過第一口，以及新流程完全沒啟動。
- 寬度獨立調查：`.godot-temp/godot_verify/20260910_013147_794/stdout.log`。整條路線最小錯誤寬度 3、descriptors=0；可見逐 lane 被誤加進來的同高度邊。
- 對照：`.godot-temp/entrance_frame_control.gd`、`.godot-temp/godot_verify/20260910_013235_287/stdout.log`。原 E01/E02 改用 60Hz 正式入口，獨立觀察兩條 gate，仍於輸入 68.317 秒 99 人通過、穩定 5 秒。
- 因此 `_simulate_step` 與 `advance_frame` 的測試差異是驗收缺口，但不是本次已證實的直接成因。已證實成因是坡口辨識錯誤，人工牆體案例未涵蓋真實山地。
- 舊 formation smoke：`.godot-temp/godot_verify/20260910_011625_101/result.json` 記錄 `Open flat follow did not reform the broad ranks`，83/99，並 timeout。沒有受控比較就不能稱它「與本次無關」。
- 診斷腳本的 EXIT=0／helper PASS 表示診斷正常執行；不能拿它的 `complete=false` 輸出當功能 PASS。

## 3. 修改範圍及沿用的 owner

| 位置 | 本輪責任 |
| --- | --- |
| `terrain_army.gd:_route_edge_width` 約2114、`_route_width` 約810 | 一份真正相連的 lane 寬度計算；兩個 caller 統一 |
| `_ensure_passage_plan` 約2208、`_passage_descriptor_for_segment` 約2175 | 完整 route 分析、五個必要 gate 覆蓋、各段入口／出口／段間連接 |
| `_clear_navigation_paths`、`_clear_passage_plan`、`_replan_follow`、`issue_command` | route／command 版本與在途動作交接 |
| `_next_passage_step` 約1703、`_record_passage_commit` 約1814、`_passage_ready_for_entry` 約1601 | 每人每段進度、准入、前進與下一段交接 |
| `_passage_step_to_goal`、`_find_passage_route` | 階段目標、合法連接與有界路線搜尋；中間目標不得改最終綁定 |
| `_assign_bottleneck_queue_targets`、`_refresh_bottleneck_queue_targets`、`_publish_exit_rally_targets` | 移除與新 passage 同時寫目標的舊路徑 |
| `_find_push_chain`、`_queue_push_chain`、`_schedule_push_unit`、release／swap guards | 同一資格判定、claim／lock、在途提交與取消 |
| `_repair_passage_slot_binding`、`_passage_complete`、`_finish_passage`、status | 固定陣位、唯一完成條件與如實狀態 |
| `terrain_lab.gd:_update_info` | 讀取真實 goal／待過口／出清／落位數；不得反向修改模擬 |
| 現有 entrance／passage／formation／captain／full／visual／performance 測試 | 補主案例、獨立 oracle、受控反例及完整驗收 |

沿用 `TerrainArmy`、`TerrainData.can_step`、route/cursor、occupancy/reservation、pending push、swap。保留 Node2D 地圖、99 人 baked atlas、隊長既有呈現及所有速度。生成器、地形 flags/ramp 資料、World–Region–Site、存檔與戰鬥不屬本次避錯手段。

遵循既有最小修改方式：先在共用 owner 修正，避免新增第二套導航服務、每兵全圖 BFS 或通用測試框架。

## 4. 第一個修改包：寬度與必要 gate 辨識

### 4.1 `_route_edge_width` 的明確規則

對合法四方向邊 `A→B`，令 `side=(-heading.y, heading.x)`：

1. `A→B` 本身非法或非相鄰四方向：回傳 0。
2. 中央 lane 計 1。分別向 side 正、負兩側，從 offset=1 起連續檢查至原 scan radius。
3. 新 lane 的 `A'→B'` 必須合法；上一條已接納 lane 的入口必須能一步到 `A'`，出口也必須能一步到 `B'`。
4. 任一條邊不合法，立即停止該側；另一側獨立繼續。不得跳過斷點再數更遠格子。
5. 四方向合法性統一用 `TerrainData.can_step`。目前地形採 reciprocal ramp；不得透過高度相同、walkable flag 或近似距離替代。

參考偽碼（需依 GDScript 型別實作）：

```text
if not legal(A, B): return 0
width = 1
for sign in [-1, +1]:
    previous_a, previous_b = A, B
    for offset in 1..SCAN_RADIUS:
        lane_a = A + sign * offset * side
        lane_b = B + sign * offset * side
        if not legal(lane_a, lane_b): break
        if not legal(previous_a, lane_a): break
        if not legal(previous_b, lane_b): break
        width += 1
        previous_a, previous_b = lane_a, lane_b
return width
```

`_route_width()` 不再保留另一套 ±5 加總。逐 route edge 取各自 heading，呼叫上述共用函式；保留既有 lookahead 範圍與顯示 clamp。轉彎後不得沿用第一段 heading。

**不可把 `PASSAGE_MAX_NARROW_WIDTH` 從2提高到11來使案例啟動。** 這會把錯誤幾何當成正確分類；也不可依 seed、五個座標或特定高度差特判 production。

### 4.2 寬度測試先行

| Case | Fixture／獨立預期 |
| --- | --- |
| W01 default-gates | 使用真實 seed 資料；五條高度 gate 的連通 lane 寬度應為1。最高層唯一離層邊先由獨立同高度 flood 確認 |
| W02 connected-two-lane | 至少6×6；左右平台 x≤2／x≥3，高度0／1；只在 y=2、3 給 reciprocal crossings `(2,y)↔(3,y)`，平台內可連通：width=2 |
| W03 disconnected-second-gap | 同上但 crossings 在 y=2、4，y=3 不可跨界：y=2 那條 width=1，不得將隔開的第二口相加 |
| W04 blocked-wall | 保留 E01/E02 人工單口，width=1 |
| W05 open-and-turn | 足夠大的同高度平地中央邊保留正常寬度；L形 route 每邊方向分別驗算 |

W02/W03 尺寸、旗標、ramp bits 在測試內明寫；不要呼叫被測寬度函式來算 expected。再做旋轉與正反方向對稱檢查。

## 5. 第二個修改包：啟動新流程後必須接好的部位

以下是現碼可見的整合缺口；尚未全部以啟動後的預設地圖跑完，因此應先各補反例再修，不能說它們都已造成同一個實測卡點。

### 5.1 舊、新隊列只能有一個目標 owner

- 現在 `_update_formation_targets()` 會在 passage active 時返回，但 `_simulate_step()` 後半仍可能走 `_refresh_bottleneck_queue_targets()`。預設路線253邊，舊101格條件可能成立，這是人工短路線不會碰到的分支。
- 新 passage 擁有命令時，舊 trail 排列、boundary rally 發布、舊高度推進判定都不得寫 `desired_cells`、`_formation_slot_cells` 或清掉通道狀態。
- 路線／結構分析尚未完成時，保留已開始的move／swap並讓它提交，暫不發布新的隊員通道移動意圖。bounded分析完成後一次交接owner，避免隊員先走進未被記錄的gate，再被初始化成APPROACH。若承接命令時已有隊員在core，須按其權威位置與已完成提交的證據初始化正確階段；不能回推、清空在途動作或僅按高度猜測。
- 明確在共用入口 guard／路由；不要在三個 caller 各補不一致條件。尚無 passage 的普通平地命令仍保留正常隊形行為。
- `_unit_is_before_bottleneck()` 現在只比較隊員與邊界隊長的高度。新流程應以每人的 passage phase 決定前進／讓位資格；不能讓 `_simulate_step()` 約3380 的舊高度 guard 封死合法上游推擠。
- 保留舊函式時，寫明適用範圍。發布 passage 及完成後槽位的期間，對目標寫入作 debug 證據，確認只有當前 owner 寫入。

### 5.2 每人必須依序通過全部必要 gate

- 五個高度 gate 依 route 順序處理。descriptor 可以因其他窄邊而多於5，也可合併相鄰窄段；驗收要確保五條必要 gate 各自被涵蓋、方向正確、沒有漏段，不以 descriptor 數量恰為5作唯一判斷。
- 現版 `_unit_passage_crossed` 只從0設成1一次，進入下一段未重設，且 service owner 寫入也包在該條件內。改成清楚區分「本段進度」與「已完成出口序號」；每段統計不得共用一個全程 boolean。
- 最小資料可沿用 `_unit_passage`、cursor、phase，加上已完成段數／每段計數；全程 crossed 顯示若保留，明定為已完成全部必要 gate 的人数，不能把第一次進口當整程完成。
- 初始 EXEMPT 需要逐段位置／連通證據。預設主案例先核對99人的初始位置，不能把最高層人員因全圖 flood 連通就全數豁免。

狀態轉移：

```text
APPROACH(p)
  -- 合法提交 entry→第一個 core，且本段准入合法 --> IN_PASSAGE(p)
IN_PASSAGE(p)
  -- 沿本段合法 corridor 提交到 landing --> EXIT_CLEAR(p)
EXIT_CLEAR(p)
  -- 已越過本段出清邊，解除本段占用 --> APPROACH(p+1)／末段前往最終slot
全部必要段已出清 + 到本人最終slot --> RALLY
```

- 只到 entry 不代表已進 core。現版約1828的 `new_cell==entry` 就改 IN_PASSAGE，會繞過 APPROACH 的 ticket guard，必須修正。
- next entry 被占時仍等待／排程下一段；到 next entry 不能直接跳成 IN_PASSAGE(p+1)，更不能跳過該段准入。
- corridor cursor、crossing／clear 統計都在權威 move／swap commit 後更新。普通步、隊長交換、隊員交換必須走同一個進度 hook。
- 全程只往尚未完成的 gate 前進；0→1→0 也不能用與隊長同高判定完成。
- 終點相同、`cells==desired`、slot暫未綁定，都不能讓未完成 passage 的隊員在 `_next_step()` 或 scheduler 提前 continue。

### 5.3 多段之間的路線與准入

- 保留完整 route snapshot，包括段間的合法連接。隊長走完後不得刪除隊尾仍需的資料。
- 隊員由已知出口 route index 往下一 entry 前進時，优先使用同一條已驗證的連接及單調 cursor；有阻擋再付費做局部 detour。避免每名隊員都搜索遠方下一入口。
- 現版 `_passage_step_to_goal()` 可因中間 entry 被占，就把 goal 和 `desired_cells` 改成最終 slot。把最終綁定修復限制在「最後一段已出清、正前往最終陣位」的分支；中間導航目標不能觸發它。
- 一條全域 `protected` mask 不能誤封閉當前必須通過的邊。每階段只能開放自己的 entry/core/egress 合法邊，禁止從其它位置斜插 core 或回流。
- ticket 是准入排序，不是要求前人先抵達下一坡口／最終陣位，後人才可進場。以前人實際離開相關容量格為放行依據；一格 corridor 應允許前後保持合法格距的流水前進。
- 在單格入口處，對已到准入位置的 eligible units 用穩定順序服務，且每個空出的 core 格只授權一名；不得為仍在遠方或尚未 eligible 的較小 ticket 永久保留入口。
- 多段各自管理可用格；第一段釋放不等待第五段完成。兩段沒有可停中間空間時，將所需連接納入同一受控段，避免出口站在下一入口上互相等待。

### 5.4 EDGE 專有出口限制與終端窄支路

- `_ensure_passage_plan()` 現在發布 `_passage_final_slots`，並設 `_exit_rally_assigned=true`，但未同步 `_exit_rally_slots`。
- `_push_endpoint_allowed()` 約2821仍用 `captain_at_boundary()` + 舊 `_exit_rally_slots` 過濾；隊長到邊界時，空舊陣列可使所有 endpoint 都不合法。
- 讓 passage 推擠及完成檢查查詢同一份新槽位／egress資料。舊 `_exit_rally_slots` 若作相容介面，只能讀同一個發布結果，不能自生成另一份集合。
- 每個 descriptor 應分開 gate、landing、受保護出清格、合法散開區。現版 route終點若也是core，flood起點可能被自身protected遮掉，不能直接把這當成全圖沒有容量。
- EDGE 的邊界格是隊長目標；不要求99人站到同一邊界格。對最後同高度、無後續出口、僅通往隊長邊界格的末端窄支路，先用地形證明隊伍可在最後必要gate之後的合法平台集合，將該支路標成 captain-only terminal，不強塞成全隊必經gate。
- 這個終端分類須有明確反例：同高度單格邊界口前有99格空間應可集合；若末端跨高度後真的不足99格，回報真實容量不足。不能用 captain-only 名義略過預設地圖五條必要下坡邊。

## 6. 第三個修改包：陣位、交易與搜尋預算

### 6.1 最終陣位及局部綁定

1. 固定陣位在最後必要gate之後、靠近命令終點的可達集合區生成，排除PLAYER、NPC、隊長goal、core及尚需保護的出口。
2. 沿用10 columns／最多10 ranks 的99格布局規則。可以在合法區域平移／旋轉模板；以实际布局量得有效寬度，不能強設 OPEN／width=10 冒充寬隊形。
3. 現版 `_sort_cells_by_depth()` 把整個 flood component 用 O(n²) 選取排序，再拿最深99格；在100×100圖會又慢又可能選到遠離終點的角落。改為有界候選布局選擇；若仍需排序，使用內建排序及穩定tie-break，且僅排序必要候選，不能以全圖最遠99格代替陣位布局。
4. 公布的 slot set 固定；只有在無相關在途動作／claim 的安全邊界局部重綁身份。重綁不能補進入口側格或把任意當前格視為新slot。
5. 所有人已在原slot set且只是身份排列不一致時，可保留實際佔有格作綁定，但必須先確認所有必經段都出清、集合唯一且完整；不能以此跳過通行。
6. 真正容量不足須回報明確原因；仍允許隊長合法到goal，但整隊不能完成。未完成的 bounded 搜尋不是容量不足。

### 6.2 推擠與交換共用資格

- 搜尋、queue、實際排程、commit 使用相同通道方向與phase規則。已完成一段的人不得被推回該段上游；APPROACH也不能被裸推擠送入尚未取得准入的core。
- 推擠鏈必須是連續被占格＋一個空終點；空格即搜尋終止，不穿越空格再找後面的占格。保留requester入口claim，requester最後進入。
- `_can_captain_swap_with`／`_can_follower_swap` 現在沒有檢查 `_push_lock` 與 passage資格；補齊兩方的來源、目的、phase與lock核對，避免用swap繞過禁回流與交易鎖。
- `_release_push_transaction(false)` 現在也先清所有目的claim；其「保留在途claim」註解與實際動作不一致。取消只釋放未啟動尾段；MOVING/SWAPPING的目的claim必須保留到其合法提交。
- `_cancel_pending_pushes()` 現在會呼叫 `cancel_moving=true`，以及多處release會將MOVING改WAITING；沿caller清查，命令更換／replan／timeout不能把插值中的人拉回源格。
- pending transaction保存command／route版本及其進度；版本變更時排掉未開始尾段，已開始的邊按上述契約落地。不要再另建一套transaction管理器。
- 每一項都有Q01–Q05及兩類swap對應反例；相同fixture須先在舊碼顯示違規，再驗修正。

### 6.3 符合原預算的服務

- 現版 `_find_passage_route()` 本身最多1024 expansions，但呼叫點沒有消耗共用 `_local_path_requests_remaining`，99人一tick可各自搜索多次。所有昂貴局部搜尋在共用入口計費，每tick最多原4次×1024 expansions；free／occupied重試各算一次。
- 舊 captain search與新增結構分析共用原每frame256 expansions 的預算，使用 TerrainArmy 內的一份pending分析狀態分批完成；完整結果才發布，不能發半張slot/component。
- phase不變、terrain／route版本不變時，重用已知的protected、component、段間route，不每人每tick重建全圖flood。
- 配額用盡是 PENDING；下tick輪到尚未服務的eligible單位，不可返回「不可達」後反覆抖動。沿用旋轉cursor，消除多層window造成的末尾飢餓。
- 保持普通直接一步意圖可每tick處理100人；不要把昂貴搜尋預算錯套在所有移動人數上。
- 連續eligible的99人，在4個搜尋名額下，每人最晚25tick獲得一次服務；如果服務有不同優先級，測試必須驗到末尾，不能只驗前幾個index。
- 記錄每類expansions、input／sim／dropped秒數。正常60Hz／30Hz／jitter不得靠丟失大量模擬時間降低CPU數字。

## 7. 正式測試怎麼寫才不再漏掉

### 7.1 測試入口與退出

- 延伸現有 `terrain_army_entrance_clearance_test.gd`／`terrain_army_passage_test.gd`，加入 `--case=...`；共用小型fixture helper即可，無需新測試框架。
- 正式100人功能案例使用 `advance_frame(1.0/60.0)`；如果入SceneTree，關閉army自動process以免雙跑。純算法／單交易測試可以直接呼叫內部函式，但必須標明範圍。
- 失敗輸出具體case、seed、hash、剩餘成員與原因，回傳false，由最外層 `quit(1)` 並return。禁止裸assert中止協程後等timeout。
- 最外層PASS只能在全部選定case成功後輸出；主案例專用標記 `ARMY_DEFAULT_EDGE_V5_PASS`。helper的EXIT0不能代替這個語義結果。
- 診斷腳本可EXIT0完成採樣，但輸出應明確標 `DIAGNOSTIC_ONLY`，不得混進功能PASS統計。

### 7.2 D01 的獨立 oracle

1. 以正式生成器、預設資料、NPC出生、deploy、issue_command建立主案例；核對fingerprint與起終點，差異須先解釋。
2. 測試側獨立BFS求隊長最短路線長度，獨立收集高度平台與合法離層邊，驗證上述必要gate；不要呼叫 runtime 的 `_route_edge_width()`／`_passage_complete()` 來算預期。
3. 初始99人是否都需要通過各gate，由生成地形與初始位置證明。對此固定主案例，各gate預期名單必須明列；任何豁免都要有證據，不能讓 runtime EXEMPT 自行降低測試數目。
4. 每frame比較已提交 `cells`，逐人記錄有向 gate 邊及相應出清邊。推擠／交換後也看實際source→destination，不看 `_passage_crossed_count` 代替。
5. 五個必要gate的順序不能倒退／跳過；每個gate的應過名單都完成，才算全程通過。把物理觀察結果與runtime counters交叉核對。
6. 每次單格提交驗 `can_step`；每frame驗唯一occupancy、owner一致、外部占格、reservation及lock都有合法持有者。
7. 最後驗固定slot set、99人唯一綁定、實際佔位集合、出清、空transactions／claims／locks及5秒穩定。開啟render的驗收另在實際scene執行。

D01期限：180秒輸入時間完成，之後再驗5秒穩定。隊長路線253邊不等於隊尾期限可任意延長；不能提高速度／擴配額來繞過演算法停滯。輸出10、20、30、40、60、120、180秒快照，完成較早則輸出完成時刻及5秒穩定終點。

### 7.3 有意義的卡住判定

- 每段記錄「目前待處理的前沿」及前向commit／cursor進度。5秒無通行進度且有eligible等待者、下游可服務、無外部阻擋，標 `NO_PASSAGE_PROGRESS` 並輸出原因。
- 前人仍在長corridor合法向前走屬進度；反覆兩格來回、別段或別人的無關步數增加不重設此計時。
- gate暫時空著但隊尾還沿合法段間路線接近，觀察該前沿的前進，不把距離遠誤報成死鎖；一直被內部slot堵住不能當外部阻擋豁免。
- capacity不足、等待外部NPC、分析pending、缺claim等原因分開記錄，不能全寫「waiting for legal opening」。

### 7.4 反例矩陣

| 優先級／case | 必驗内容 | 通過條件 |
| --- | --- | --- |
| P0 W01–W05 | 真實坡口／連續lane／隔離坡口／轉彎 | 正確寬度、共用兩個caller、五條必要gate被涵蓋 |
| P0 D01 | 預設12345，正式deploy＋EDGE | 180秒內所有必要通行與99落位，穩定5秒 |
| P0 D02 | D01第一次下坡後隊長繼續前行直至邊界 | 隊尾各段持續前進，舊101格queue不改新slot，邊界時合法推擠仍可用 |
| P0 M01 | 兩段單口，中間平台不足99格；fixture先證明可通行 | 中間流水通過，不能等全員中場集合，不能等前人最终落位才放後人 |
| P0 M02 | 到下一entry但core被占 | 不跳階段、不錯計crossed、不把下一entry換成final slot |
| P0 X01 | 新final slots已有99格、舊exit slots空、隊長在boundary | 合法egress讓位不被舊空陣列封殺；不可回流 |
| P0 Q01–Q05 | 中間空格／requester／鎖／取消在途／yield | atomic owner／claims無違規 |
| P0 E01/E02 | 原人工同高／單坡FOLLOW | 兩條實體gate各99、180秒＋5秒穩定；保留對照 |
| P0 F01/F02/F03 | 平地99人、2/3人slot排列、公平搜尋 | 延續20秒收隊＋5秒穩定、25tick服務上限，不能只≥90 |
| P1 terminal | 同高末端窄支路與跨高度容量不足各一案 | 隊長邊界格語義正確；容量不足如實拒絕整隊完成 |
| P1 switch | 普通move／swap／push途中EDGE↔FOLLOW、反向 | 在途提交完成、舊方向停止新入場、無claim／lock洩漏 |
| P1 geometry | V4 E03–E12的彎道、雙lane、多級／回到同高度、bypass、NPC、容量 | 保留逐人實體進度證據，不能以高度或Manhattan近似PASS |
| P1 generated | V4指定2預設×3seeds×2commands | 記錄12候選與獨立可行性；每preset×command至少1完整可行，固定預設D01不可排除 |
| P1 dt | 60Hz、30Hz、交替1/120與1/40；另測大dt | 合法性／公平／完成與時間統計一致；大dt丟時如實記錄 |

M01等新增fixture在看修後結果前，先寫完整地圖／起點／命令／獨立oracle，沿用V4規格。不能挑會過的seed、把主案例改成PLAINS、縮成40×30、降低軍隊人數或關掉正式預算。

## 8. Luna 逐階段執行順序

| Stage | 實作與檢查 | 本階段離開條件 |
| --- | --- | --- |
| S0 保存與失敗驗收 | 核對hash／備份；正式化D01、W01–W05與安全退出；保存當前診斷 | 舊版W01可正常非零失敗，指出唯一gate被算11；D01可輸出實際phaseNONE／等待，不能只等程序timeout |
| S1 修共用寬度 | §4；統一`_route_width`與`_route_edge_width` | W01–W05過；原captain shortest不退步；暫不稱全隊修好 |
| S2 發布與owner隔離 | §5.1、descriptor、route版本、必要gate、終端分類；先處理結構分析預算 | 真實五gate都有方向與順序；舊queue不再覆寫；無在途強制重置；發布狀態完整 |
| S3 段間與交易 | §5.2–5.4、§6.2、phase導航預算／公平 | M01/M02/X01/Q01–Q05過；第二段以後也有物理crossed與clear；不再靠單段boolean |
| S4 收隊與主案例 | §6.1、固定layout、唯一completion；跑D01/D02及E01/E02/F01–F03 | D01每必要gate99人證據、180秒落位與5秒穩定；平地與人工對照無退步 |
| S5 完整驗收 | 剩餘矩陣、既有full/captain/passage/formation、UI、GPU、性能 | §9、§10所有必驗項有當前版本證據；失敗項不隱藏、不標整體完成 |

S1啟動了以前沒跑到的程式後，如果出現新錯誤，按S2/S3反例定位，不准只調門檻／反覆試參數。每包說明「違反哪條契約 → 共用修改位置 → 舊例失敗 → 新例結果 → 尚未完成」。

已授權實作後，這些例行修正與驗證不需要再逐包請使用者同意。任何FAIL先保留log、檢查具體原因並修復；有程式／fixture或環境更正依據後再驗。禁止無變更反覆重跑賭一次PASS。

## 9. UI、畫面與效能交付

### 9.1 實際場景

- `terrain_lab.gd:_update_info()` 顯示目前命令的真實隊長goal，並分開「隊長到邊界」「仍待過口」「core／egress內」「已完成全部通道」「已落位」。不要僅顯示總步數與一個99/99。
- 詳細per-person資料寫診斷檔；HUD讀取廉價summary，不能每frame重跑地形分析。
- `terrain_lab_army_visual_test.gd` 使用預設地圖與EDGE，補四個與模擬證據對齊的GPU畫面：接近第一口、隊長走遠而隊尾未出、最後一人出清必要出口、99人最終落位。
- 圖上確認仍在Node2D地形正確高度／遮擋位置，隊尾沒有停在高台；交換／推擠用必要的連續幀確認沒有回彈、瞬移。
- 既有PLAINS部署圖、headless skip或檔案存在不等於這次視覺驗收。只能交付自己實際檢视過的新圖。

### 9.2 時間及性能

- 原move/run/SIM_STEP、captain/local/push預算維持。收集行軍、每坡口、收隊時段的frame p50/p95/p99、army CPU、最大expansions、輸入／模擬／丟時。
- 延續V4性能目標：未限速frame P95≤16.7ms、P99≤25ms，army CPU P95≤2ms/frame；正常活動不能反覆>50ms尖峰。
- 先報硬體、渲染模式與實際量測。診斷headless最慢一次`advance_frame`為149.145ms，不是FPS/GPU測量，也不作正式性能基線。
- 錯誤的全圖O(n²)候選排序、每人多次1024搜索必須依計数證據處理。不可使用卡住後idle FPS或降低模擬速度來宣告改善。

### 9.3 有界執行

使用已安裝 `godot-runtime-verify` 的 `verify_godot.ps1`，保存真實EXIT、stdout/stderr/result。headless驗功能、editor驗parse/import、visual驗畫面，證據分開。

遵守 `AGENTS.md`：背景命令／subagent須立即設定 `schedule` watchdog。工具不存在時使用有界前景執行；不要自行建立定時自動化替代，也不要留下失聯程序。

主案例較長，可用runner的合理wall-time監督；它與180秒輸入期限是兩個量。若工具必須分批，使用**同一個存活的SceneTree與army**保存連續狀態，批次間只讓出執行控制，禁止每批重新deploy／重設指令／只拼接數字。若要跨程序續跑，必須先驗完整checkpoint round-trip等價；不要為趕測試臨時加不完整恢復。

目前 D01 使用獨立的預設地圖測試檔；可重播命令如下。E01／E02等入口fixture仍用 `terrain_army_entrance_clearance_test.gd -- --case=E01`。真正已執行的exit／時間／hash以驗收文件連結的result與log為準：

```powershell
& 'C:\Users\Nekki\.codex\skills\godot-runtime-verify\scripts\verify_godot.ps1' `
  -ProjectPath (Get-Location) `
  -GodotExecutable 'C:\Users\Nekki\Godot_v4.6.2-stable_mono_win64\Godot_v4.6.2-stable_mono_win64_console.exe' `
  -Mode headless -TimeoutSeconds 45 `
  -GodotArguments @('--script','res://scripts/tests/terrain_army_default_edge_test.gd')
```

## 10. 完成前逐項核對

1. 最終runtime／test／generator hash与每份log的版本相符；最後一個修正後，受影響測試重新驗。
2. W01五個真實gate寬度正確；route分析涵蓋必要gate，並由獨立oracle反查。
3. D01完整180秒期限內的結果，而非55.7秒採樣；每gate應過名單逐人通過／出清、隊長最短距離、99個合法slot與5秒穩定。
4. `overlap`、`illegal edge`、`owner mismatch`、`invalid claim`、`lock leak`、通道回流均0；取消與swap測試過。
5. E01/E02與F01–F03、既有full／captain／passage／formation都有結果；不能因「以前也失敗」就標成無關PASS。
6. 剩餘生成／換命令／幾何／dt矩陣列全，不跳過已知可行失敗；所有SKIP說明是否阻止整體完成。
7. 場景預設及EDGE操作的四階段新圖實際檢視，HUD與物理觀察數據一致。
8. 真實活動期間的預算／時間／性能數據及未達項目。
9. 搜尋並逐caller核對殘留：兩套lane加總、101格gate、非RALLY的`cells==desired`退出、按隊長高度判過口、邊界舊exit-slot過濾、全程一次crossed flag、裸yield、取消MOVING、全圖排序／每兵BFS。
10. 最終報告先給使用者操作是否已修好的答案，再列證據與未完成項；測試資料及源碼留在工作樹，不自行提交。

### 可直接交給 Luna 的指令

> 請依 `TERRAIN_LAB_DEFAULT_EDGE_FIX_V5_LUNA_MAX.md`，沿用 max 推理，實作 Terrain Lab 預設山地走到邊界的修正。先核對§2版本並保存副本，從S0正式失敗測試開始，依S1–S5完成。
>
> 使用者問題是預設TERRACED_HIGHLAND／seed12345／正式deploy／MOVE_TO_EDGE；目前最高層唯一出口 `(66,52)→(66,53)` 被錯算成11格，整條路線五個坡口都未建立passage，重播55.7秒仍93人在最高層。E01/E02人工FOLLOW的PASS不能代表此案例完成。
>
> 先修兩個寬度caller的連通lane判定，再接好舊queue排除、多段phase／准入／出清、EDGE舊槽位限制、共用push/swap/取消安全、固定陣位與搜尋預算。只到入口不能標已進core；第一次crossed不能當五段全過；隊長到邊界後隊尾仍須前進。不要改地形、速度、人數、期限、seed或擴配額讓結果好看。
>
> D01必須走正式advance_frame，以獨立物理gate事件驗每名隊員，180秒內完成99人所有必要通行與落位，再穩定5秒。完成舊回歸、矩陣、預設場景GPU四階段與性能量測；FAIL/TIMEOUT不能用helper PASS覆蓋。已授權的修正持續完成，不需逐包重新詢問；需要新權限或外部資訊才明確提出。不要自行stage/commit；最後依§10交付當前版本證據。
