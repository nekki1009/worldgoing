# Terrain Lab 山口卡住：第二輪改善與驗收計畫（Luna Max）

日期：2026-09-09。實作模型：gpt-5.6-luna，reasoning effort=max。

本文件是實作交接計畫。本輪只查核現行程式與測試、編寫計畫，未修改遊戲程式，未執行 Godot，未重現使用者當下的生成圖。下列程式缺口已靜態確認；哪一項觸發使用者這次卡住，仍需第一階段固定案例證明。

本文件取代 `TERRAIN_LAB_FOLLOWER_DEADLOCK_FIX_PLAN_LUNA_MAX.md` 中與山口導航、讓位、完成判定及驗收重疊的要求。保留舊文件作歷史稽核，不能將其「計畫」當作已完成項目。其他編隊／跑步文件的呈現契約繼續適用。

查核基線：`scripts/terrain_lab/terrain_army.gd` SHA256 `7D829AE66DCFBC9E4BF0AF9F31719D51F47A2CEA26C81608E272DFACBBA55F9A`。行號供定位，實作前依函式名稱重查。TerrainArmy 與相關測試目前仍是 untracked，工作區有大量其他修改；先保存相關檔案的比較基線，不能用 Git HEAD 當作這些檔案的修改前版本，也不能整批清理或提交。

## 1. 這次必須交付的結果

在地形確實可通行、出口有足夠集合空間、外部角色未永久封路的條件下，1 位隊長帶 99 位隊員完成：接近山口 → 排隊進入 → 合法逐格穿越 → 出口疏散 → 真正落位。FOLLOW_PLAYER 與 MOVE_TO_EDGE 共用同一套山口流程；隊長在內陸停下也必須讓隊尾繼續出山口。

必須把「隊長抵達」「99 人通過」「99 人落位」「恢復寬陣」分開。沒有空間或真正無路時，回報具體受限原因；不能把原地隊形改名為已集合，也不能靠穿崖、重疊、瞬移、加速、增加搜尋配額或拉長 timeout 達成驗收。

保留 TerrainArmy 單一模擬 owner、TerrainData.can_step 通行權威、cells/moving_to 分離、隊長專用 route，以及現有 baked atlas／2D 呈現。依 ponytail 原則重用現有 BFS、陣型與 push 結構；不新增每兵 NavigationAgent、99 份全圖搜尋、通用導航服務或另一套陣型管理器。

## 2. 上次 PASS 為什麼不等於修好

上次的正式測試及 smoke 確實回傳 PASS，但測試觀測不足。以下是現在仍存在的程式，不是舊版推測。

| 優先 | 現行位置 | 已確認缺口及影響 |
| --- | --- | --- |
| P0 | `_all_followers_in_exit_rally` 930、`_settle_exit_rally` 944 | 條件只有隊長抵達、同高度、Manhattan 距離 ≤24；隨後把 desired、slot、offset 改成目前 cells，直接設定 OPEN、width=10、99/99。未查是否位於出口側、是否經過山口或是否形成十列。舊 rebind 雖刪掉，等效的假完成又出現。 |
| P0 | `_cancel_follower_motion_for_rally` 972 | 可以清掉隊員 MOVING/SWAPPING 的目的地與進度、解鎖並清空整張 reservation；正在走的一步被撤回。計數完成不是正常移動收斂。 |
| P0 | `_assign_bottleneck_queue_targets` 845、`_refresh_bottleneck_queue_targets` 897 | 軌跡不足101格不啟用 queue；出口 slots 只在 captain_at_boundary 時建立。短山口與 FOLLOW 內陸停靠缺少完整排隊／出口流程。不能把門檻改成較小常數就算修好。 |
| P0 | `_follower_navigation_goal` 1285、`_captain_trail_progress` 795、`_unit_is_before_bottleneck` 2175 | 高度相同直接追陣位；不同高度則找最近同高度離開邊；進度以最近 Manhattan trail 格猜。高度不是平台身份，S彎、同高度隔牆、重複高程、多山口會挑錯入口或往回走。 |
| P0 | `_simulate_step` 2257 附近 | 隊長到邊界且全隊同高度就解除瓶頸，未驗證每人通道進度。改成高度一致仍不足以修正提前解除。 |
| P1 | `_exit_rally_targets` 816 | BFS 只是不把 trail 格加入結果，搜尋仍會穿越 trail 和坡道；未限制出口側，可能繞回入口平台找 slots。cache 只看 anchor，沒有路線／集合版本。 |
| P1 | `_schedule_follower_blocker` 2103，尤其2144 | 遞迴分支仍直接 `_reserved_cells[pushed_cell] = index`，沒有交易 owner；MOVING blocker 直接回 true，並不證明它正往所需方向讓位。刪掉一個 source reservation 寫入點不等於消除了整類問題。 |
| P1 | `_advance_pending_pushes` 2059 | 最後 blocker 完成後便釋放交易，requester 未入格；空格可被其他兵搶走。age 是固定總時長4秒，沒有依實際完成重置；長鏈即使持續前進仍可能被中途取消。 |
| P1 | `_can_captain_swap_with` 1683、`_can_follower_swap` 1772、`_find_push_chain` 1950 | 未完整檢查 push lock；找鏈時不排除其他交易成員，提交時才拒絕。外層排程跳過鎖定 requester，不能保護遞迴入口與被交換的 partner。 |
| P1 | `_begin_follower_swap` 1796、`_simulate_step` 2304 附近 | 最終 occupied-next 分支直接開始 swap，begin 未強制檢查 `_follower_swap_requested`。新增意圖 helper 並沒有封住所有入口；REGROUPING 又被 swap guard 排除。 |
| P1 | `_complete_move` 2400、`_prune_stale_reservations` 1733 | 提交無條件 erase reservation、覆寫 destination owner，沒有提交前 ownership 核對。prune 允許「desired 等於被占格」存活，仍非可追溯交易證明。 |
| P1 | `issue_command` 547、`_replan_follow` 670 | 命令入口只清 follower route，未一致取消舊 push／rally／bottleneck 狀態；FOLLOW 目標变化才重置部分 rally flags。需要明確 command/route 版本，不能靠分散布林值接續上次命令。 |
| P1 | `_update_formation_targets` 1092、`_ensure_distance_map` 1523 | preferred 只驗 walkable；距離場混入PLAYER/NPC，但cache只以origin判定有效。孤立同高度平台及NPC離開後的可達性沒有完整契約。 |
| P1 | `_find_local_route` 1209、`_next_follower_step` 1317 | detour route 已保留，值得保留；但空結果仍混淆預算耗盡與無路。逐兵選最近坡口會改 navigation_goal、清掉既有route；不等於有稳定的通道進度。 |
| P1 | `_route_width` 744 | 無隊長route直接回10；隊長可先貪心走，因此無route不表示寬路。整段用單一heading，lane不要求連續連通，轉角及離散坡口可能錯判。 |

已實作而應保留的部分：局部 follower route/cursor、隊長 route ownership、防重疊的原子交換基本結構、固定tick與搜尋配額、atlas呈現。這輪改正它們的使用條件和生命週期，不重寫已有效的基礎。

測試缺口也已確認：

- `terrain_lab_army_test.gd::_verify_ramp_corridor` 只要求完成步数>0、隊長到坡口或有人移動；没有要求99人過口。
- `_verify_multi_level_descent` 只記隊長經過的高度，隊員完成讀 production 的 formation_count；可被原地改目標污染。
- `terrain_army_formation_smoke_test.gd` 只要求 ≥90 人，width只讀變數，没有檢查真實陣型。
- `_verify_follower_detour_route` 只驗前兩步，不證明繞完整堵牆並落位。
- 整隊測試直接呼叫 `_simulate_step`，避開 `advance_frame` 的正式每幀預算與累積時間；visual測試主驗部署／交換，performance測試的「有移動」也不是全員過口證據。

## 3. P0：先留下會失敗的證據，再動導航

### 3.1 固定重現資料

新增一個集中測試檔 `scripts/tests/terrain_army_passage_test.gd`，不要建立新測試框架。保留原有測試並逐步補強。整隊案例走 `army.advance_frame(1.0 / 60.0)`；手動推進時關閉自動process，避免雙重模擬。小型狀態反例可直接測helper，但不能代替正式命令案例。

每個固定案例記錄：case id、preset、seed、parameters、size、TerrainData.fingerprint()、100個起始cells、PLAYER/NPC位置與移動時間線、命令與發出時間、dt序列、預期山口邊／集合區。fingerprint不包含全部重播狀態，所以不能只存hash或seed。

正式生成入口是 `TerrainGenerator.generate(preset, seed, overrides)`。先用 TERRACED_HIGHLAND／ROCKY_HIGHLAND，各測 seed 12345、24680、12346，並保存重現資料；這些是固定候選，尚未證明會卡住。若不足，再作有界種子搜尋，保留第一個失敗種子，不每次換地圖。若後續取得使用者實際seed與操作，加入同一回歸，不阻止先完成合成反例。

在修改前保存相關檔案副本或hash及測試輸出；禁止覆寫使用者其他修改來跑舊版。所有失敗均寫狀態快照並主動以非零退出，避免GDScript assert中斷後SceneTree不退出，最後只得到timeout。

### 3.2 必先建立的四個反例

1. **短山口、內陸停靠**：100×100平地，在x=50建立牆，只有(50,50)可穿；兩側有足夠容納100人的空地。隊長路程不足101格，FOLLOW目標停在右側內陸，逐人記錄(49,50)→(50,50)→(51,50)。另做一級高度差版本，坡道雙向bit依can_step正確建立。起始100格都在左側且唯一，不能把人放進牆內；正式呼叫issue_command。
2. **同高度、距離24內卻未過口**：隊長(45,50)，99人分布在x=34..43、y=44..53的合法唯一格，x=44為牆、唯一缺口在y=10；隊長FOLLOW目標已抵達，發布集合slots在牆右側。所有人同高度且距離≤24，卻仍在入口側。新版必須維持未完成，不能改寫陣位集合或取消在途移動。此fixture專門測假完成，允許設定初始狀態，但不得用它取代第1項正式流程。
3. **隊長停下、隊尾仍在山口前**：通道4–12格，出口側可容納100人。隊長越過出口數格即停；先出的人不得ARRIVED在出口疏散路上。記錄最後一人跨出口邊，不能只看moving_count或總步數。
4. **push空格競爭**：至少3個blocker及1個requester，第三方嘗試搶交易釋放格；再做隊長交換鎖定blocker、長鏈持續進度超過4秒、途中切命令。requester必須消費空格後才釋放交易；在途一步不能因逾時或切命令倒退。

反例的BLOCKED格要移除WALKABLE位；目前TerrainData.is_walkable以WALKABLE位判斷，不能只OR一個BLOCKED旗標而保留WALKABLE。

### 3.3 獨立驗收者

測試用自己的前後cells比較記錄每名隊員的合法提交邊、通道順序和出口側成員；不得呼叫 production 的passed/count/helper作為唯一oracle。合成圖以固定入口／出口邊及明確矩形區域判定；生成圖可用測試側BFS驗證路線和切口兩側連通性。

所有tick驗證：100格唯一、owner雙向一致、每次位移相鄰且can_step、MOVING有自己的目的預約、每個claim/lock有活躍owner、已發布slots唯一有效。swap須按兩人原子提交驗證，不能逐人更新oracle造成假重疊。最終另驗「所有必經出口已跨越＋位於出口集合區＋真實占用slot集合＋無pending/moving/swap」。

**P0出口條件：**舊版至少留下假完成反例FAIL和一個真山口不前進／不出列FAIL。若某反例舊版已過，誠實記錄，不刻意破壞fixture；另找與缺口匹配的案例。先鎖住失敗，不調大原有timeout來製造PASS。

## 4. P1：完成判定先去除自我證明

修改 `_settle_exit_rally` 及呼叫點：刪除以實際cells覆蓋desired/slots/offsets、強設count/width，以及為完成而取消移動的行為。若helper不再需要直接刪除；保留名稱時只允許唯讀判定／狀態轉換。

集合slot集合必須由地形、出口側範圍與已選陣型生成，不由目前兵的位置定義。可以重新配對「哪名兵去哪個已存在合法slot」，不能偷偷換掉slot集合；重新配對需要版本與原因。

`is_formation_complete`驗證：隊長達該命令的實際goal；99人通過自己尚需的通道序列；99人落在發布且合法唯一的slots；無MOVING/SWAPPING/pending push；所有等待claim已釋放。`captain_at_boundary`仍可用來顯示，但不能代替EDGE goal相等判定。

OPEN和width=10只能在已驗證十列布局真的形成後顯示。普通平地以既有10列×10排布局（99個slot）為優先；邊界／障礙可選事前生成的合法替代布局，寬度由真實可用連通橫列決定。空間不足時保留COLUMN/REGROUPING與容量理由；不能強設10。

階段完成後原本smoke可能失敗，這是露出真問題。繼續下一階段，不恢復原地完成補丁。

## 5. P2：在TerrainArmy內明確表示「正在通過哪個山口」

### 5.1 最小資料

用現有TerrainArmy內的小型Array/Dictionary及PackedInt32Array即可。欄位語意如下，名稱可配合現有碼，但不可缺少其生命週期：

| 資料 | 用途／釋放條件 |
| --- | --- |
| command_epoch、route_revision | 辨別新命令與同命令重規劃，阻止舊route／rally／push結果寫回新命令 |
| 活躍passage序列 | 每段含有向入口邊、出口邊、合法有序路徑、可用連通lane、出口疏散格；最後使用者通過後釋放 |
| 每兵passage cursor／phase／queue ticket | APPROACH、IN_PASSAGE、EXIT_CLEAR、RALLY；只在合法已完成步驟後更新 |
| rally revision、區域／slot集合 | 與所選出口及地形版本一致，變更有原因、不可每tick重建 |
| 每兵last_progress、wait reason | 診斷真無進度；route cursor／通道進度增加才算進度，普通往返不算 |

不把軍隊所有人綁在同一個布林瓶頸；多層下降可同時有人在前一個口、下一個口和出口。保留隊尾仍使用的段，不要因隊長前進把舊通道資料丟掉。

### 5.2 通道取得與真實側別

重用隊長已發布合法route及can_step。對route每一條邊使用該邊自己的方向，取得連續合法横向lane；把相鄰窄路段合併，跨高程坡道也記錄為段。相距很遠的兩條坡道不能累加成寬2。無route但隊長走貪心合法步時，必須對同樣的前看步驟做狹口檢查；不能把空route視為寬10。

段的入口／出口應在路線上可識別的位置，出口要有可疏散的下游格。彎道沿其有序路徑導航，不用單一heading投影整個S彎。短路段不需要存放99個trail位置，等候人可以排在入口區。

對生成圖，局部所需的平台身份可在TerrainArmy內以同高度合法連通flood一次建立；`TerrainGenerator._connect_platforms`已有生成時union-find，但沒有對runtime公開平台索引，不要修改生成器去耦合軍隊。高度相同也可能是不同component；同高度狹道仍需通道切口／有向route進度，單靠component不能表示「已通過」。

出口集合區：在所選出口下游作有界flood，禁止穿回該入口、未完成的通道邊及需保護的疏散格來找slots。保護格可以用於合法通行但不能作終止陣位。若切口不是拓撲割邊、有其他繞路，不能靠切圖假定兩側；沿選定通道先到已驗證下游錨點，再在其局部合法區域集合。替代路線需明確更新route revision和該兵所需段，不得以最近座標跳段。

### 5.3 推進規則與排隊

- 每兵先接近自己的下一個入口，再逐段通過，最後疏散／集合。導航goal由phase決定；刪除「挑最近同高度坡口」的用途。
- gate/route索引只由提交邊推進，包括普通move及原子swap；同一座標重複出現在route仍是不同序次。不得每tick從目前座標重新猜最近索引。
- 入口排隊ticket在實際加入該段時建立，以到達時序排序、同tick用unit id作穩定tie-break。通道內禁止無原因重排；雙lane使用各自連續通路，不能假定可横向穿崖換列。
- 優先讓出口的人前進，讓路段前方釋放空格，後方依序進入。只在下一格有合法空間與預約時排程；不要在窄道內用任意push／互換讓隊列逆行。
- EXIT_CLEAR不是ARRIVED：先離開出口保護路徑，再進入指定rally slot。最早出來的人優先取得不堵住後續疏散的較深slot；slot距離依合法路徑，不能依穿牆Manhattan。
- 隊長停靠內陸與到EDGE都触發同樣下游疏散。尾隊追上與否獨立於隊長是否繼續走；若隊長goal占唯一出口，選附近合法停靠／等候安排，不能讓goal本身永久堵住隊尾。
- 初始deploy若跨平台或跨口，依合法側別判定各人尚需通道；已在下游者不必倒回入口補刷通過。測試須記錄初始側別豁免，不能假報其「曾跨邊」。
- command反向或FOLLOW跨山口改目標時，先讓已進窄道者走完安全出口，再切新方向；新方向入口暫停，不准兩股在單格道迎面鎖死。command_epoch清掉未開始意圖，在途一步仍正常完成；不能保留舊隊列又直接用新goal。

**P2出口條件：**兩命令的短平地窄道、一級坡道、隊長內陸停止案例99人依oracle通過；不再依賴trail≥101、同高度或碰邊界。

## 6. P3：導航搜尋穩定、有界且能分辨等候

保留現有follower detour route/cursor；route goal綁定phase及revision，暫時占格不能清route。每步執行前核對can_step與占用；目標或地形真的失效才重建。route完成進度由提交更新，交換造成路線起點改變時顯式失效／更新。

長距離接近入口用共享靜態距離場，沿合法下降方向前進；局部BFS只解slot附近／隊列外的障礙繞路。靜態場不把PLAYER/NPC寫成永久障礙，動態占格在排程時處理。先重用一份field分批處理活躍入口；只有量測證明重建抖動，再加小型有上限cache，禁止每兵全圖field。

局部結果明確區分FOUND、WAITING_OCCUPANCY、BUDGET_EXHAUSTED、UNREACHABLE。BFS碰到預算上限不能報無路；可保留有界待續工作，或使用共享field接近後重試。不要每tick從相同起點做同樣1024次無效展開。

保留目前4次局部搜尋／simulation tick、每次1024展開、最多2個tick／render frame，故局部上限8次8192展開／frame。隊長現有每frame搜尋門檻與256展開分開記錄。push的512展開及遞迴深度32是另一類工作，必須加總計數和獨立有限配額，不能聲稱所有導航都已受4次限制。

搜尋請求用單一輪替順序，避免 `_detour_window_allows` 與 `_local_path_cursor` 雙窗口交集使最後幾人長期拿不到occupied search。等待預算、等候前兵、外部占格與地形無路各有reason；無進度超過5秒輸出快照，不能自動宣告失敗，也不能改寫目標為目前位置。

**P3出口條件：**完整U牆／S彎／錯位多坡口都到達；NPC暫堵後離開可續行；最後一個落後兵也能獲得搜尋；高幀間隔案例不超配額、不靠跳過模擬時間假裝更快。

## 7. P4：讓位交易閉合，所有入口遵守同一套ownership

保留並修正 `_pending_pushes`，只允許隊列外及出口集合區需要的局部讓位。刪除 `_schedule_follower_blocker` 在交易外寫source claim的分支；單格yield也走同一筆小交易，不再與遞迴預約並存。

交易最低欄位：id/epoch、requester、units/cells鏈、cursor、下一空格消費者、last_progress、狀態。生命週期是「鎖鏈 → 最末兵走向空格 → 逐步向前釋放 → requester真正入格 → release」。

1. 找鏈就排除其他交易鎖定者、在途非成員、隊長與外部角色；避免先找不可提交鏈再反覆拒絕。
2. 已釋放格保留下一消費者的權利直到提交；沿用owner-checked reservation並讓活躍transaction提供存活證明。不要新增平行占格系統。
3. 所有普通move、captain swap、follower swap、遞迴入口都檢查unit lock和格claim。把必要guard放共同begin/commit入口；只修外層caller不算。
4. `_begin_follower_swap`本身必須驗明確互換意圖或已驗證的隊列修復規則。REGROUPING的相互slot交換要能合法解開；不任意開放沿隊列前後互換。三兵環以既有空格讓位交易解。
5. 交易age改成實際無進度時間；blocker或requester完成一步才重置。取消未開始部分；已在途者正常完成後回收，不重置move_progress。命令切換、clear和deploy的處理分開。
6. `_complete_move`與swap commit核對source owner、destination claim、其他occupant和合法邊；釋放只可 `_clear_reservation(cell, owner)`。不應以overwrite掩蓋衝突。驗證版遇不一致輸出完整快照並FAIL；正常command切換不應造成此分支。
7. `_prune_stale_reservations`只做可追溯性檢查與孤兒回收，不用「desired剛好等於該格」當存活證明。回收數非零要能追到原因，不能每tick靜默掃掉真正生命週期錯誤。
8. `issue_command`集中失效旧route/rally和未開始交易；陣型更新不得在active transaction中改其目標。原clear可以整體清空，正常命令／完成流程不可清整張reservations。

**P4出口條件：**空格競爭、長鏈、兩兵互換、三兵環、命令中斷、鎖定partner交換、clear/deploy均滿足逐tick不變量，最終pending/lock/claim歸零。

## 8. P5：整合診斷、生成圖與視覺驗收

沿用 `terrain_lab.gd::_process` 440附近既有army_info顯示；低頻更新（例如每秒2次），不要每tick拼99人字串。至少顯示：隊長狀態、當前段已通過n/99、尾隊尚需段、集合n/99、有效寬度、最久無進度unit/秒、主要wait reason。

新增最小debug snapshot方法供test與HUD共用：seed/fingerprint/epoch、unit/cell/goal/moving_to、phase/段索引/route cursor、blocker/reservation owner、transaction id/cursor/last_progress、搜尋結果/展開數。卡住時輸出一次，狀態有變或測試截止再輸出，不刷滿console。不必新增複雜回放UI；資料重播由測試入口讀即可。

生成圖先以獨立BFS判斷隊長目標可達；還要判斷出口可容納隊員、疏散路未被最終slots封死。個人可達不等於100人可集合，分開記錄。達不到容量者是CAPACITY_LIMITED案例，不算導航PASS，也不能混入成功比率。FOLLOW的遠端玩家目標及全部初始cells要保存，以免換seed後測到不同路線。

## 9. 必跑矩陣與固定判準

| ID | 案例 | 觀測與通過條件 |
| --- | --- | --- |
| A | 同高度24格內隔牆、1人未過口、仍在途中 | 不改目標集合、不假報99/99、不撤回在途步 |
| B | 短平地單格道，FOLLOW/EDGE | 每個需要過口的人實際跨出口，落位99/99；trail<101仍有效 |
| C | 短一級坡、隊長停在內陸，FOLLOW/EDGE | 尾隊持續出列，入口／出口保護格無ARRIVED堵塞 |
| D | 同高度U/S道、重複高程、多個候選山口 | 按合法指定路段推進，不以高度／最近座標跳段 |
| E | 3→2→1→0错位坡道，沿用現有fixture | 每兵按序通過三條必要邊；最後在低地合法slots，無pending |
| F | 真正兩格連通坡、兩條不相連lane、轉角 | 寬度按連續合法通道；不把離散lane合併，不穿崖 |
| G | 出口容量不足、僅一格出口、隊長占疏散格 | 正確受限／停靠安排，無假寬陣完成 |
| H | NPC暫堵後離開、真正無路地形 | 前者可續行；後者靜態oracle一致不可達、無非法移動 |
| I | push競爭、鎖定partner、長鏈、兩兵互換、三兵環 | requester消費後release；其他人不能搶claim，逐tickowner一致 |
| J | FOLLOW轉EDGE、EDGE重發、FOLLOW反向、初始跨口 | 舊意圖失效，在途一步完整，無迎面永久卡死或倒回補刷 |
| K | 兩種高地×固定3 seed×兩命令 | 每例保存oracle/通過數/落位數/時間/容量；可達且足容者全隊完成 |
| L | 正式60Hz、30Hz、帶0.1–0.2秒抖動的advance_frame | 相同合法終態、配額不超限；分別列送入時間與實際simulation時間 |
| M | 原有smoke/army/visual/performance回歸 | smoke改為真實99slot落位；視覺和效能不得只驗有人動 |

每個完整案例的deadline在執行前固定。初始建議：局部反例10秒、平地停止後30秒、短口120秒、三層240秒 simulation time。對比理論時間必須使用固定tick後實際步長：0.24秒走一步在0.1秒tick至少約0.3秒；還需計入本排程是否多一tick才能讓後兵起步、入口接近路長、99人通道吞吐和出口最長合法路徑。不要直接以RUN_DURATION乘99作保證。

生成圖在跑前根據路長與通道數列出保守期限計算；容量未知或路線根本不可達先分類。不得看到失敗才反覆加timeout。模擬deadline與外部process watchdog分開；外部timeout不是功能PASS，效能變慢導致模擬沒跑完亦須報告。

視覺證據：選一個已保存的實際高地seed，GPU模式走同一命令，捕捉「入口排隊」「隊長已出、尾隊仍在內」「隊尾跨出口」「最後陣型」四個階段；畫面能看見山口、隊長、隊尾，必要時用總覽＋近景。對照每張的oracle數與tick，逐張檢查；只產圖、靜止畫面或HUD 99/99不算通過。

效能沿用現有runner的硬體與設定，暖機後量測真正行進區間。報P50/P95/P99/max、simulation步數、每兵通過數、搜尋及push展開數、最久無進度。停住的60FPS不能當導航性能成果；本計畫不預先聲稱特定FPS。

## 10. 檔案分工與交付順序

| 檔案 | 交付內容 |
| --- | --- |
| `scripts/terrain_lab/terrain_army.gd` | 完成判定、通道路段及每兵進度、穩定導航goal、出口slots、交易生命週期、最小診斷 |
| `scripts/tests/terrain_army_passage_test.gd`（新增） | 固定卡住反例、獨立通過oracle、重播、逐tick不變量及非零失敗退出 |
| `scripts/tests/terrain_lab_army_test.gd` | 多層全員實際過口與合法落位，完整detour，不只隊長／counter |
| `scripts/tests/terrain_army_formation_smoke_test.gd` | 平地真寬陣99人、停止後穩定，不允許≥90替代完成 |
| `scripts/terrain_lab/terrain_lab.gd` | 既有HUD補通道／等待診斷 |
| 既有army visual/performance test | 擴充固定高地動態驗收，重用capture／量測設施 |

順序：P0鎖反例 → P1取消假完成 → P2真通道／出口流程 → P3穩定導航 → P4交易闭合 → P5完整驗收。各階段只跑對應小案例；整合後再跑矩陣。若P2被已證明的ownership衝突擋住，可提前修P4共同guard並留測試，不能跳過最終任一驗收。

不要修改TerrainGenerator、TerrainData.can_step、人物資產、戰鬥或World/Region/Site架構來使本測試變綠。若oracle證明生成拓撲無路，保存資料並另外列出；不要把真無路解讀為軍隊AI需要穿崖。

Godot執行使用 `C:/Users/Nekki/.codex/skills/godot-runtime-verify/scripts/verify_godot.ps1`，editor／headless／visual選正確模式，保留實際exit code、result.json與combined.log。遵循AGENTS背景watchdog規則；沒有schedule工具時採明確timeout的前景驗證並主動監看，不能遺留背景程序。失敗先分析輸出及改正對應原因，再跑相關案例，禁止原樣盲目重試。

Luna最終交付 `TERRAIN_LAB_FOLLOWER_PASSAGE_FIX_V2_RESULTS.md`，列：實際根因與函式、修改前後反例、矩陣各項PASS/FAIL/未執行、每個生成案例seed/fingerprint/99人過口和落位實數、最長等待、圖像與效能、Godot版本/退出碼/日誌、修改與未提交清單。不能將靜態掃描、舊測試PASS或本計畫寫成新的遊戲驗證結果。

## 11. 可直接交给Luna Max的任務文字

請以gpt-5.6-luna、reasoning=max，依 `TERRAIN_LAB_FOLLOWER_PASSAGE_FIX_V2_LUNA_MAX.md` 完成TerrainArmy山口卡住修正。先核對現行檔案與hash、保存未提交基線，建立短山口FOLLOW及同高度假完成的舊版失敗證據。依P0–P5逐階段落實全隊通道進度、出口疏散、合法固定slots、交易ownership與独立oracle。保留現有owner、速度、通行規則與呈現。必須跑兩正式命令及固定生成高地案例，99人真正過口落位才算完成；capacity limited與不可達須分開。不要以原地重綁desired、強設99/99、放寬deadline或移動中取消來通過測試。保存全部證據與results文件；保留其他工作樹修改，未獲額外指示不提交Git。
