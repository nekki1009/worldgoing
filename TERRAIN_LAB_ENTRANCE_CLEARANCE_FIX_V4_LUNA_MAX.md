# Terrain Lab V4：入口卡住修正實作與驗收契約

日期：2026-09-10。交接對象：Luna，reasoning effort=`max`。

狀態：**已依 V5 整合完成實作與驗收（2026-09-10）。E01／E02三種dt均完成99人通過、出清、合法落位並穩定5秒；交易／換命令／幾何／生成矩陣、GPU連續動作、七段效能與editor均有最終版本PASS。完整結果見 `TERRAIN_LAB_V5_ACCEPTANCE_STATUS.md`、`TERRAIN_LAB_V5_EVIDENCE.json`。** 以下保留開工時的基線與驗收契約，歷史失敗不代表目前版本。本文件取代 V2/V3 中重疊的 follower、通道、出口、交易與驗收指示；V3 的隊長最短路徑要求繼續保留。矛盾依使用者指示、`PROJECT_ARCHITECTURE.md`、V5、V4處理，不能用較早版本PASS替代當前證據。

目標：在地形確實可通行、出口有足夠集合空間的情況下，99 名隊員都能通過入口、清空出口、走到合法陣位；隊長在內陸停止 FOLLOW 後，隊尾仍會繼續前進。此任務完成前，不得只交付「隊長有動／大部分人有過／編譯通過」。

## 0. 給 Luna 的執行規則

1. 先完成 §8 的 S0，再依 S1→S2→S3→S4→S5 推進。每階段有具體證據門檻；失敗表示繼續定位該階段，不表示任務完成，也不需重新詢問已授權的修正。
2. 每個修正先指出「哪個共用函式違反哪條不變量」，再修改並跑指定反例。禁止反覆改速度、等待秒數或配額，以單次人數較高作選擇依據。
3. 通道問題必须由實際跨格／出口清空事件驗收。`formation_count`、`moving_count`、高度相同、距離近、總步數增加都不能單獨證明通過。
4. 使用既有 `TerrainArmy`、`TerrainData.can_step`、route/cursor、reservation、swap、pending push。不要另建 NavigationAgent、每兵全圖 BFS、第二套 reservation、通用導航服務或外部依賴。
5. 保留 `Node2D` 地圖、隊長既有呈現、99 人 baked atlas、合法四方向邊、既有行走／跑步速度。不得改地形生成、World–Region–Site、存檔、戰鬥與其他角色來避開失敗。
6. 不准降低 99 人門檻、把入口側目前位置改成最終陣位、強設 OPEN／width=10、瞬移、穿崖、重疊或取消半途動作回源格。
7. 禁止將 MOVING/SWAPPING 改成 WAITING 來「等全隊靜止」。只有尚未開始的意圖可以暫停；已開始的動作與其 claim 必須完成或輸出真正的不變量錯誤。
8. 保留使用者工作區變更。相關檔案目前 untracked，不能從 Git HEAD 還原基線。實作前保存相關檔案副本與 SHA256；最後列出實際改動，不自行 stage、commit 或啟動其他使用者任務。
9. 遵守 `AGENTS.md` 的背景 watchdog 規則。若環境沒有 `schedule`，使用前景有界檢查；不要以失聯的背景程序替代 timer。驗證失敗後先檢查錯誤與程式，再有理由地重跑，不能無修改重試同一失敗。
10. 完成報告依 §10 的證據表。缺任一必驗項即標「部分完成／未通過」並繼續處理可完成工作，不能用更寬泛的 PASS 字樣覆蓋它。

## 1. 已確認的基線，不要重新猜原因

### 1.1 實作前核對檔案

工作目錄：`C:\Users\Nekki\Dropbox\竹北社大\(01)102-103學員資料\share\worldgoing`。

| 檔案 | 本計畫基線 SHA256 |
| --- | --- |
| `scripts/terrain_lab/terrain_army.gd` | `BF5D6E7029FF388A1BA8DA949724CDAA7335ADD5000069641EC75CE9A070D7B6` |
| `scripts/tests/terrain_lab_army_test.gd` | `B45D7ADC5C53A5815D9479BBC559E1457684C95D25C566264B842A4CDCBE1C3D` |
| `scripts/tests/terrain_army_passage_test.gd` | `2F4FCD8BEBB742589B0C108D460EE248C1203C6C14B695CC659A517C4562238E` |
| `scripts/tests/terrain_army_formation_smoke_test.gd` | `B26C86C69BD7DABA771285A85C22A5EDCBCC23EC704383447AA7A992259DD624` |
| `scripts/tests/terrain_army_captain_route_test.gd` | `9CFFCF7A5AFC1BE04908F3ACCABE63CEAB31ACFB8598C1071CC20D37D8C61BE4` |

Hash 不同先看差異、更新基線，不能覆蓋新版本。下文行號僅作定位，修改前依函式名重新查所有 caller。

### 1.2 入口重現證據

隔離診斷：`.godot-temp/army_entrance_review_20260910.gd`。

原始紀錄：`.godot-temp/godot_verify/20260910_000918_350/{result.json,stdout.log,stderr.log}`。

執行：Godot `4.6.2 stable mono`，headless，EXIT=0，20.000 秒 wall time，未 timeout。**此 EXIT=0／helper PASS 只代表診斷正常結束；腳本有輸出失敗現象，沒有斷言所有隊員成功，所以絕不能寫成「入口修復 PASS」。** stderr 另有 root certificate store 訊息。

兩個正式 FOLLOW 案例皆為 40×30，所有人由 `deploy` 建立，使用 `set_process(false)` + `advance_frame(1/60)`，輸入共40秒：

| 案例 | 隊長 | 40秒入口側人數 | 實際曾跨入口人數 | 關鍵觀測 |
| --- | --- | --- | --- | --- |
| 同高度單格口 E01 | 10秒內到 `(31,15)` | 79/99 | 20/99 | 20、30、40秒跨口人數都是20；總步數仍981→1019→1053，屬通道無進度，不能被其他移動掩蓋 |
| 單級坡口 E02 | 10秒內到 `(31,15)` | 68/99 | 31/99 | 40秒時仍有隊員等待36–38秒；仍有通過活動，這份40秒紀錄不證明每人永久死鎖 |

兩案都：trail=18、COLUMN、width=1、bottleneck=true、exit_assigned=false；**21個 desired 陣位仍在入口側**。本次觀測沒有非法邊或重疊，但這不代表通道安全性已全面驗證。

E01 fingerprint：`070758d90fc655376c889eae12f8c82456743c52068463f9fdc553bcdf6acc86`。

E02 fingerprint：`df0cd9eef10867b115b6dab512bf8a284bc73a765b01738afbdad63a22c5ee73`。

推擠 helper 反例 Q01：搜尋回傳 `[(2,1),(3,1),(4,1)]`，其中 `(3,1)` 已是空格；`_queue_push_chain` 拒絕，pending=0、claims=0。這是搜尋與提交契約矛盾，與 E01 的 FOLLOW 缺口分開驗證。

這些是可重播的固定反例，不是使用者原始山地 seed。不能宣稱已重播原場景。

### 1.3 保留／未完成清單

| 現有內容 | 判斷與處理 |
| --- | --- |
| `_next_step` 隊長先走完整 BFS route，`start==goal` 是 FOUND | 保留；現有 U 巷 helper 已能走10步。它手動套用 cells，不等於正式命令100人驗收 |
| `_complete_move` 的 owner／claim／合法邊檢查；prune 不再保留純 desired 孤兒 claim | 保留核心檢查，補錯誤診斷與共同提交進度；不要照 V3 舊敘述重新修同一段 |
| push 有實際 commit 才重設 age、timeout 不取消正在走的成員 | 部分改善；其他 cancel 路徑與 swap 仍要稽核，不能宣稱已完成所有交易安全 |
| `_repair_open_slot_permutation` | 只處理 OPEN、無 bottleneck；不是入口 COLUMN 的解法；目前依賴全隊 idle 的觸發也未證明可靠 |
| 101格門檻、邊界限定出口、同高度捷徑、nearest-trail 進度、無逐人 passage cursor | 尚未完成；是本輪主要工作 |
| passage 測試 | 目前只有平地「不要誤報 rally」，沒有牆／窄口／全員通過，必須擴充 |
| formation smoke | 仍以200次私有 `_simulate_step`、≥90及變數width=10驗收；不足以驗證真正99人收隊 |

固定參數：`SIM_STEP=0.10`、`MOVE_DURATION=0.24`、`RUN_DURATION=0.18`、每幀最多2個sim tick、captain/結構搜尋共享每幀256 expansions、局部每tick最多4份且每份≤1024。前輪加快速度、改等待門檻或將局部配額4→8→12都沒有完成修復，部分造成完整測試 timeout；不要重走這條調參路線。

## 2. 修改責任表

主要 runtime 改動集中於 `scripts/terrain_lab/terrain_army.gd`。HUD 僅可改 `scripts/terrain_lab/terrain_lab.gd` 的讀取顯示；測試擴充既有檔案。

| 現行入口（基線行） | 必須完成的責任 |
| --- | --- |
| `issue_command` 548、`_replan_follow` 675 | 命令版本、在途動作交接、固定PLAYER時穩定goal；註解聲稱取消的舊claims必須真的有生命週期 |
| `_find_path` 1754、`_consume_path_route_step` 1673、`_clear_path_route` 1667 | 發布完整route與版本；隊長走完不能刪除隊尾仍需的 passage |
| `_route_width` 749、`_captain_trail_progress` 800 | 每條edge的連通寬度；刪除以Manhattan最近trail推算「已通過」的權威用途 |
| `_assign_bottleneck_queue_targets` 850、refresh 902 | 移除101格前置条件；短通道與FOLLOW使用同一份進度，舊trail排99格方法退場 |
| `_follower_navigation_goal` 1382、`_next_follower_step` 1414、`_unit_is_before_bottleneck` 2362 | 以unit index查逐人階段，先通口再收隊；不可用同高度／captain_at_boundary分支取代進度 |
| `_update_formation_targets` 1130、preferred 781、exit targets 821 | 最終slot集合、臨時排隊目標分離；出口側拓撲、保護走道、唯一與容量檢查 |
| `_find_push_chain` 2065、queue 2133、schedule blocker 2288、schedule push 2103 | 搜尋與commit同條件；單格yield也走交易；合法但會把出口堵回去的move要被拒絕 |
| `_release_push_transaction` 2182、advance 2212、cancel 1067 | 保留在途claim，只取消未開始尾段；由實際提交推進交易 |
| captain/follower swap guards 1790/1887、complete 1958/1991、move commit 2592 | 同時核對lock、source、兩方claim、edge與通道方向；共同更新逐人進度 |
| `_simulate_step` 2413、planning order 2368、`advance_frame` 2722 | phase-aware排程、公平服務、可觀测預算／模擬時間；不能因抵達臨時格而停止通道服務 |
| `is_formation_complete` 644、status 1099、mode 1072、settle 1047 | 唯一唯讀完成predicate；其他函式消費結果，避免多處硬設完成 |

## 3. 先固定資料語義與不變量

### 3.1 最終位置與當下意圖是兩件事

- `cells[i]`：只記已提交的實際格；`moving_to[i]`：正在插值的一步，必須有對應claim。
- `desired_cells[i]`：保留為該人正式最終slot綁定。入口／臨時queue／egress目標由 phase-aware navigation goal 決定，不塞回最終slot計數。尚未綁定可用 INVALID，但不能因此跳過有合法通道目標的人。
- `slot_set`：地形驗證後發布的99個最終格與revision。`unit→slot`：獨立的綁定；可以在安全局部重新配對，不能把任意當前格加入slot_set。
- 同一入口可以是多人的導航waypoint，但**不是多人同時擁有的陣位或reservation**。只有被放行的人可預約下一個格；其餘人停在合法上游格。
- `cells[i]==desired_cells[i]` 只有在該人所需passages全數完成、已到RALLY且無在途動作时，才可作為「不用再排程／已到位」。

### 3.2 必要狀態；放在既有 TerrainArmy 內

| 狀態 | 內容／唯一寫入時機 |
| --- | --- |
| command epoch | 正式接受新命令或PLAYER新目標時增加；標記舊的未開始意圖，不覆寫正在執行的一步 |
| route revision | 路線起點、實際goal、完整合法cells、必要障礙快照、發布原因；搜尋完成才整批發布 |
| passages | route上的有序窄段、entry/core/exit、合法lane連接、保護egress、拓撲component或已驗證的走道範圍；由route分析產生 |
| 每名隊員 | 當前passage、APPROACH/IN_PASSAGE/EXIT_CLEAR/RALLY、corridor cursor、ticket、已完成出口序號；只由合法commit或可證明的初始位置分類更新 |
| slot set / binding revision | 集合變更與人員重配分開記原因；completion只讀 |
| 交易 | id、epoch、requester、成員、claims、cursor、最後真正commit時間、取消未開始尾段的狀態 |
| 診斷 | wait reason、最後commit tick、最後搜尋服務tick、per-passage最後通過tick、所有搜尋expansions、輸入/模擬/丟棄秒数 |

名稱可調整，責任不可省略。重用既有Array/Dictionary；不要為這些欄位建立平行manager。

### 3.3 每一tick都必須成立

1. 100個實際cells唯一且owner表雙向一致；一次commit只走一條 `can_step` 合法邊。swap兩方一起更新。
2. MOVING的目的格claim屬於本人；SWAPPING兩個互換目的格claim配對正確。WAITING的人不得保留無交易來源的claim。
3. 每筆claim/lock都可追到一個在途動作或有效交易；取消交易不擦掉其他owner的記錄。
4. 未過口的人不能因高度相同、距離近、站到某個舊slot就標已過；已過口的人不能在同一命令中被重新安排回上游。
5. 還有人需要經過的core/egress不是最終停留slot；保護不代表全部鎖死，依法前進的通行動作仍可使用。
6. 通道服務不依賴隊長是否仍在走、trail有多少格、是否位於地圖邊界。
7. 候選最終格不足99時輸出容量限制，不能以入口側格補數，也不能宣告完成。
8. 診斷、HUD、completion查詢不得修改cells、slots、ticket、通過計數或movement state。

## 4. 通道與出口的明確算法

### 4.1 路線發布與生命週期

保留已完成的隊長「先BFS後行走」修正。PLAYER不動且路線有效時，固定同一goal與route revision。FOLLOW保留PLAYER周圍Manhattan 3–5格停止帶；EDGE仍選真正最短可達邊界，不為出口容量偷偷改成另一個較遠goal。

隊長route發布時保留完整路線。可以擴充既有route使cursor到尾仍保留cells，或保存其不可变command snapshot；兩者擇一，不維護兩份可獨立修改的route。`_captain_trail` 可留作呈現／診斷，不能再成為排隊啟動門檻或逐人通過的唯一依據。

隊長步行與swap消費相同route；搜尋PENDING凍結當前合法起點。普通formation replan不能清掉命令route或重設通過狀態。

### 4.2 找出真正相連的窄段

1. 沿完整route逐edge取局部方向 `route[k+1]-route[k]`，不能用第一段heading掃完整轉彎。
2. 從route所在lane往兩侧連續擴展；每條lane須有合法平移前進邊，與相鄰lane亦要合法相連；遇阻隔停止該側，不能把另一個分離坡口加進寬度。
3. 相鄰窄edge合併。彎道檢查轉角連通，不能只檢查兩條直線；各lane允許前進的對應關係必須可追蹤。
4. descriptor至少含窄段前的entry、core、窄段後的exit與下一個安全散開處。若相鄰出口直接接下一段窄口、没有合法暫停容量，合併成同一段；長路線不得要求每個中間小平台容納99人。
5. 最小實作先以單lane跑通E01/E02，然後通過彎道／雙lane等必驗；單lane作法不能冒充所有地形已支援。

### 4.3 出口側只能靠地形連通證據

對唯一缺口案例，以**規劃查詢遮罩**暫時封住core／完整gate截面，從exit作合法邊flood，得到下游component；不能修改 `TerrainData` 的真實flags或 `can_step`。入口所在component必須與下游分離。

E01/E02的oracle明確：封住 `(20,15)` 後，上游 `x<20` 與下游 `x>20` 分離；entry=`(19,15)`，core=`(20,15)`，exit=`(21,15)`。正式runtime不能硬編碼這些座標或x比較；只有固定測試可以這樣做獨立判斷。

反例處理也要明確：

- 同高度的兩個區域依component分，不依height分；不同高度但合法連接的出口可屬同一可達區域。
- 多坡口或有繞行時，關閉一個core可能仍連通。記錄NON_SEPARATING；**不得把包含入口的整個component當安全出口集合**。以已發布ordered corridor及其出口局部連通範圍維持通行方向；若允許繞行，須保存不經core的合法bypass route，實際消費後才算該人免走該口。
- NON_SEPARATING的第一版採保守規則：既有單位仍依選定corridor逐格通過；出口slot候選須有不經core／entry的合法egress路徑，再用封口圖上的出口／入口兩份地形距離排除更靠入口及同距離的候選。這個篩選只限制slot候選，不得用它直接增加已過口人數。若採bypass，需另存完整合法路徑並由commit確認，不能只設旗標。
- 初始EXEMPT只可由已驗證的下游component或已完成的bypass證明，不能用「距離exit比較近」推定。EXEMPT與實際crossed分開計數。
- 計算尚未完成顯示PLANNING；搜尋budget耗盡保留job。真正無法證明的地形標PASSAGE_UNRESOLVED，不能猜測完成；固定可行驗收案例不允許以UNRESOLVED過關。

### 4.4 每人的通道狀態轉移

| 階段 | 下一步目標 | 何時轉移 | 絕對不能做 |
| --- | --- | --- | --- |
| APPROACH | 目前必經口的入口／合法上游排隊位置；入口距離用共用地形場 | 真正提交entry→core的合法邊 | 追最終slot穿過牆、站在上游slot後停止服務 |
| IN_PASSAGE | 所屬corridor下一合法格／lane | 真正消費該段exit邊 | 用nearest-trail跳cursor、逆向互換、任意往回yield |
| EXIT_CLEAR | 清空出口所需的合法egress路徑 | 真正離開core與保護出口範圍 | 一跨到exit格就停下、立即宣告ARRIVED |
| RALLY | 合法最終slot；若還有下一passage，改為該段APPROACH | 全部必經出口完成且到本人slot | 回到前一段入口側、把暫停格改成正式slot |

navigation goal 必須能依 `unit index` 取進度；現行只收start/goal的 `_follower_navigation_goal` 不足，調整簽章後查遍所有caller。通道狀態與UnitState（IDLE/MOVING/SWAPPING/WAITING）互相獨立；「尚未開始一步」不代表「已完成通道」。

共同的commit hook接收 `(unit, old_cell, new_cell)`，在普通move與兩種swap成功更新owner後调用。swap兩人都逐一驗證相應的通道邊；任何一方需要倒退、跨錯段或帶lock時，begin-swap就拒絕。commit不因更新兩人而重複計同一人的過口事件。

### 4.5 排隊、放行與出口優先

- 初始ticket按合法入口距離與unit id作穩定排序；已在通道內的人依實際cursor排前。只有claim/位置真正可用的人進候選。
- ticket決定同時ready者的順序，不能讓尚在遠處的人堵住已站入口的合法候選。已到入口的非首ticket者若擋住前者，必須有明確合法讓位或有紀錄的ticket交接。
- entry/core只用既有格reservation控制pipeline，不要為每人預約整條passage直到最終落位。前人離開第一格後，後人可合法進入。
- 當前出口清空優先於新入口放行；front core優先於rear core。上游approach與不衝突的rally仍可並行。
- 不把99人塞進18格trail，不需要99個歷史格才排隊。上游等待是暫態，不能計入最終formation。
- 隊長若在路線中途因隊員占用而要swap，必須遵守上述通道方向；不能藉隊長特例把已過口隊員換回上游。等待或安全讓路不增加隊長未記錄的繞路步數。

### 4.6 最終slot與保護egress

1. 先從出口側拓撲產生slot候選，再綁定人；最終set排除core、尚須使用的egress、隊長格／goal、外部角色、不可達格。
2. E01/E02出口有充分空間：例如 `x=21..30,y=16..25` 的100格方塊可作測試側容量見證，排除其中1格即可容納99人。runtime自由選擇合法布局，不能把這組座標寫死。
3. 從exit到散開區保存一条合法egress spine；現有已走trail不應整條都禁止，也不能讓flood經它繞回入口找slot。保護期限是最後一名必經者出清。
4. 最终布局採原10 columns ×最多10 ranks 的99格模板，在出口可達範圍按固定候選順序平移／旋轉。有效寬度來自實際布局；不能以「前99個flood格」冒充十列。
5. 下游先到者綁較深、較不阻擋通行的slot；深度用出口可達距離排序，不用跨牆Manhattan。可在入場／出清時逐人綁定尚未分配的slot，set保持不變，binding另記原因。任何時點已綁定slot唯一。
6. 若理想十列必須用到egress，先發布獨立的下游staging位置疏散；staging不算settled。最後必經者出清後，以EGRESS_RELEASED原因發布最終slot revision，再真正走到位。
7. 中間平台小時讓人繼續下一段，不要求在中間聚齊99人。終點出口不足99人的受限案例回報INSUFFICIENT_RALLY_CAPACITY，隊長仍可完成其合法命令goal，但整隊狀態不能完成。
8. `OPEN` 錯位修復可重用「固定slot set、局部改binding」概念；只改受影響、未MOVING、未SWAPPING、未被交易鎖定且通道資格相容的人。其他人在走不妨礙它，不等待全軍idle。
9. 重配後只清除受影響者的舊局部route。未來stage／egress人不得參與終點slot錯位重配；不能用全域洗牌把尚未過口者的當前格合法化。

## 5. 推擠、yield、交換與換命令

### 5.1 推擠鏈的唯一合法形狀

`[occupied_0, occupied_1, ..., occupied_n, one_empty_endpoint]`。

requester必須與第一格相鄰、且本次navigation意圖需要進入該格。中間所有owner都是可參與的靜止成員；末格是合法、可預約的空格。所有邊須同時符合can_step、claim/lock與通道方向規則。

搜尋遇鄰格時，按此順序：

```text
不合法edge／外部阻擋／別人的claim／不允許的通道邊 → 跳過
空格：
    允許作endpoint → 立即返回鏈
    不允許作endpoint → 停止此分支，不能enqueue後繼續展開
有人：
    captain／requester／MOVING／SWAPPING／其他交易lock → 跳過
    合法可搬移成員 → 記predecessor並enqueue
```

queue提交重新核對完整鏈、requester鄰接與末格可用，再一次取得全部claims與locks。失敗時reservation/lock表與提交前完全相同；不可先保留部分claim、失敗後靠prune碰運氣。

### 5.2 共用合法性不能只放一個caller

- 把「格邊是否符合此人當前phase／交易」收斂成一個既有owner內的小判定，ordinary move、push search、push schedule、swap都使用。
- `_schedule_follower_blocker` 的裸yield／遞迴直接寫claim分支移除或改用同一個短鏈交易。遞迴深度上限不能當狀態安全的替代品。
- 單格yield也必須保護requester即將取得的source；不讓第三者在blocker離開後搶走它。
- 出口合法性由passage/egress資格決定，移除 `_exit_rally_assigned && captain_at_boundary()` 作為唯一保護開關。
- swap共用begin入口自己檢查兩方意圖、lock、claim與通道資格。允許合法的OPEN/REGROUPING陣位互換；不因caller曾檢查就省略共用guard。

### 5.3 交易進度、timeout與取消

保留首輪一筆全域push交易的簡化，程式加 `ponytail:` 註明吞吐上限與何時改成不相交交易；普通合法移動不能因此全停。pending期間不重搜同一筆鏈；需要新鏈者进入公平的ready隊列。

交易由空端逐步commit，最後requester真正進入第一格後才完整釋放。每個成功commit更新last_progress；插值、重新排程與其他人的步數不算。

4秒無commit才判stalled；取消未開始的尾段，正在執行的一步繼續保有目的claim直到提交。刪除「取消就清moving_to／progress回0」的正常控制路徑；source/claim不變量真的破壞時輸出精確錯誤並停止該案例，不能默默回彈後仍印PASS。

### 5.4 新命令與反向通道

1. 保存最新待生效命令／epoch；舊epoch未啟動意圖取消，在途move/swap先原子完成。
2. 舊passage仍有人在core／egress時，停止舊方向新入場，只讓已入場者沿舊方向出清；不得同時放兩股人對撞。
3. 被清空路徑下游的人仍要執行必要的egress疏散，不能因「新命令等待」把出口封死。無外部阻擋的反向案例需有界完成drain。
4. 舊active core出清後，从每人的已提交格重新規劃新方向。已出者按新route重新分類，不沿用舊cursor，也不改cells。
5. PLAYER持續改位置時合併成最新待規劃目標；不能每0.5秒把正走中的99人路線、slot與ticket全部重設。

## 6. 固定步進與完成判定

### 6.1 `_simulate_step` 的順序

```text
記錄待生效command；推進現有move/swap
    ↓
原子commit → 更新逐人passage/route/交易進度
    ↓
釋放已完成工作；處理舊epoch未開始尾段；prune只清無主claim
    ↓
發布已完成的route/passage/slot分析結果；維持舊的有效snapshot
    ↓
更新phase導航目標與ready隊列；局部安全binding修復
    ↓
先出口清空、再core前進、再入口放行；其餘合法移動正常排程
    ↓
公平發放有界局部搜尋與新push搜尋
    ↓
唯讀計數／completion／HUD摘要
```

此順序只是要求責任先後，不要拆成第二個simulation loop。任何pause判斷都放在「排新一步」部分；前段現有MOVE/SWAP一律能推進。

### 6.2 公平性與預算保持原上限

- 局部搜尋：每tick4份、每份最多1024 expansions；一名eligible人一次服務只用一份。若free路由查找失敗，occupied策略下一輪再處理，或在同份上限內處理，不能先吃free配額再吃occupied配額把其他人擠掉。
- 只有一個服務cursor／ready隊列，移除互相交疊的 `_detour_window_allows` 與其他window門檻。連續eligible且未被lock的人，在最多25tick內得到一次局部搜尋機會。
- 新push搜尋：沿用V3每tick最多1份、≤512 expansions；先服務出口清空／已ready的通道前端，普通錯位請求公平輪轉；同一無解請求不能永遠佔住首位。記錄requester等待，不以全局「有pending」隱藏飢餓。
- captain與新增component/slot結構搜尋共享每幀256 expansions，結果完成後才發布。現有同步 `_ensure_distance_map` 等整圖掃描須改成可續作且版本化的owner內job或重用已算好的場；不能在每名隊員／每tick背後偷做完整flood。
- 便宜的相鄰合法步仍每tick評估所有100人，不能把「4份搜尋」誤解為「每tick最多4人動」。
- 兩tick/frame时，局部expansions≤8192、push≤1024，結構共享≤256。每一種搜尋都計實際數字，包含失敗與預算未完成作業。
- 保留 `input_seconds`、`sim_ticks`、`simulated_seconds`、`dropped_seconds`。固定60/30Hz與不過catch-up上限的jitter，應無丟棄；大dt壓力案例允許既定丟時但須正確報告，不能拿高FPS掩蓋模擬少跑。

### 6.3 唯一的唯讀完成predicate

對有passage的命令，以下同時成立才true：

1. 隊長已在這次真正goal，沒有在途動作；EDGE位於「某個邊界」不夠。
2. 每人所需出口序列都有合法commit證據或已驗證的EXEMPT/bypass原因；全部離開仍受保護的core/egress。
3. 最終slot set為99個合法、唯一、符合layout的格；每人恰在自己的綁定slot，實際cells集合與slot set相等。
4. 沒有MOVING/SWAPPING、pending push、活躍入場許可、殘留claim或lock。
5. OPEN/width由完成且已驗證的layout導出；不是predicate內重新寫desired或強設計數。

無passage平地命令的第2項為空集合，仍必須驗其餘條件。將 `_settle_exit_rally`、status、mode中相互矛盾的完成寫入統一；舊函式名稱可保留為小包裝，不再各有一套真相。

## 7. 測試規格：必須讓錯誤自己暴露

### 7.1 固定fixture與獨立oracle

**E01：40×30同高度唯一缺口，必須按原診斷重播。** 全圖height=0、flags=WALKABLE；`x=20`整列除了`y=15`都BLOCKED。PLAYER初始`(3,15)`、NPC`(2,15)`，正式deploy；驗100人全部`x<20`。移PLAYER到`(36,15)`發FOLLOW。使用實際deploy輸出，基線隊長`(15,16)`、goal`(31,15)`；若換了合法選兵方式，仍須保留原initial cells作額外replay，不能換fixture消掉失敗。

**E02：E01單級坡口變體。** `x>=20`高度=1；`(19,15)`右向ramp bit與`(20,15)`左向ramp bit互相對應。其餘參數完全相同。

測試自己记录每人 `(19,15)→(20,15)` 與 `(20,15)→(21,15)` 的提交，順序必須正確；曾入core不等於已出清。獨立計「仍在入口側／core內／已出出口／正在疏散／最終落位」。不能直接讀production passed數字作答案。

**E03：兩案的EDGE變體。** 保持40×30尺寸；封所有外邊界，只留`(39,15)`可走，PLAYER/NPC仍在左側合法格。驗獨立BFS只可能選到該出口，不能讓隊長從左側就近邊界離開而沒經過通道。height/ramp依E01/E02各跑一案。

**Q01：中間空格。** 8×4；僅`(1..4,1)`及captain`(7,1)`可走；requester1在`(1,1)`、blocker2在`(2,1)`、`(3,1)`空但禁止當endpoint、`(4,1)`為允許的空endpoint。查詢不能輸出包含中間空格的push chain；應回無合法鏈或經另一条全占用合法支路的鏈。這是helper fixture，不要求這張小圖放100人。

**Q02：真正3人推擠。** 單格通道依序requester、3個blocker、合法空endpoint；逐tick驗最末blocker先走，第三者搶格失败，最後requester取得第一格，結束時claims/locks乾淨。另測commit前環境改變必須全退未開始意圖而不污染owner。

**F01：原平地FOLLOW。** 100×100全walkable，PLAYER`(50,50)`、NPC`(51,50)`；正式deploy與FOLLOW，再PLAYER`(80,50)`、FOLLOW。保留原200tick（20模擬秒）診斷，新增正式`advance_frame`20秒內99/99並保持5秒的驗收；不能把期限改30秒或≥90。

**C01：保留隊長10步U巷。** 現有helper繼續跑；再依V3 §5 C01正式100人fixture補正式command/advance_frame實際走過邊數。獨立BFS當oracle，不呼叫production `_find_path`計答案。

### 7.2 必跑案例矩陣

| Case | 預期攔住的錯誤 | 成功證據 |
| --- | --- | --- |
| E01 / E02 | <101格不排隊、同高度跳過、FOLLOW沒有出口 | 正式100人命令，全99人通過兩條指定gate邊、入口0人、最終99格穩定 |
| E03-flat / E03-ramp | 只修FOLLOW或EDGE选錯近邊界 | 唯一goal=(39,15)，全員真的跨口、清空、落位 |
| E04-last | 前98人都出、最後1人仍在core，completion誤true | 最後1人出清前一直false；出口可用；完成後保持5秒 |
| E05-turn | 同高度S形／U形狹道，最近trail跳進度 | 每人有序消費彎道合法邊，無跨牆、倒退重進或提前RALLY |
| E06-multi | 0→1→0或3→2→1→0多級口，高度猜錯階段 | 每人依序完成各出口；中間小平台可流水通過，不要求聚齊99 |
| E07-lanes | 雙lane／分離坡口被相加當10寬 | 寬度只計連通lane；每人有合法lane轉移，出口不回流 |
| E08-near | 隔牆但與隊長同高、距離很近 | 不因距離／height/舊slot相等而完成，仍走真實入口 |
| E09-external | NPC暫擋entry／exit或目的slot，再移開 | WAIT_EXTERNAL有具體格；移開後恢復，沒有永久UNREACHABLE cache |
| E10-reverse | MOVE/SWAP/push途中換命令與窄口反向 | 在途動作完成、舊方向出清後才換向，舊epoch claims清淨 |
| E11-capacity | 出口只有不足99可停格 | 正確容量限制；沒有入口補slot或假完成 |
| E12-bypass | 兩個可通坡口、關閉單gate仍連通、初始有人已下游 | 不把整圖當downstream；EXEMPT/bypass有證據且與crossed分開 |
| Q01 / Q02 | 無效push鏈、交接搶格 | 鏈形狀正確、交易全成或全不留claim，requester最後進入 |
| Q03-lock | locked/moving partner仍被push/swap | 共用begin直接拒絕，所有caller一致 |
| Q04-timeout | 有進度長鏈>4秒被取消／半步回彈 | 真正commit更新進度；無進度取消未開始尾段；在途邊不重置 |
| Q05-yield | 裸yield繞過claim與egress限制 | 最短交易保護requester source，不能把出口成員推回core |
| F01 / F02-cycle | 平地尾端與2/3人錯位活鎖 | 20秒99/99、固定slot set、局部配對合法、保持5秒 |
| F03-fair | 固定index或雙window吃光配額 | 連續eligible的最後一名≤25tick獲得局部搜尋服務 |
| C01 / C02 | 隊長恢復貪心／target不穩／零步錯誤 | 正式route實走=BFS最短；PLAYER不動goal/revision穩定 |

E04/E05等額外fixture在S0先寫下完整尺寸、walkable/ramp資料、initial cells與oracle，再測baseline；**不能先看修復結果，再挑一張會過的圖。** 每個case都可單獨執行；不新增一套測試框架，可在現有測試以 `OS.get_cmdline_user_args()` 讀 `--case=...`。

### 7.3 時限、進度與失敗出口

- E01/E02/E03等短通道：延續V3總期限180秒**輸入時間**，完成後額外保持5秒；40秒保留診斷快照，不把40秒未全員通過直接等同永久死鎖。
- `NO_PASSAGE_PROGRESS`：待過口者存在且入口前端ready、下游無外部封路／真實容量阻擋時，5秒沒有任何front/core/exit前向提交就失敗。等待一個確有進度的長corridor隊列以該段前向cursor推进判斷；不可用全軍總步數替代。重複兩格來回不能重設這個計時。
- NPC暫時封路不計無阻擋停滯時間，但須顯示WAIT_EXTERNAL及格；NPC移開後5秒內恢復通道前進。內部slot堵出口不屬可无限豁免的外部阻擋。
- F01截止20秒；F03服務時限25tick。沒有任意延長測試期限或修改速度的權限。
- 60Hz、30Hz、固定jitter `[1/120,1/40]` 交替：在相同輸入秒數下檢查全員通過、合法性、預算與丟時；兩種tick/frame交錯不能破壞owner。另測大dt catch-up有正確dropped time。
- 真正失敗先輸出case、source hash、seed/terrain fingerprint、dt、初始100格、命令事件、目前各phase、gate、slot set/binding revision、卡住成員、owners/claims/transactions，再`quit(1)`並return；fixture錯誤非零退出且標FIXTURE_INVALID。
- 不依赖裸assert中斷SceneTree後等timeout。用現有腳本的小型check/boolean回傳即可；不要寫generic testing platform。
- 測試不准於開始後修改runtime cells/desired來幫它過。合法fixture初始化可直接設資料，但必須標明與正式deploy測試的差別。

## 8. 逐階段實作包與出口門檻

| 階段 | 先改／先驗的內容 | 本階段必交證據；未過不能說完成 |
| --- | --- | --- |
| S0 基線與可失敗測試 | 保存hash/副本；將E01/E02/Q01搬入既有passage測試；補case選擇與正常失敗退出；先寫完整矩陣fixture | E01通道無進度與Q01契約矛盾應被測試攔下並非零退出；E02保留40秒快照，完整期限結果如實記錄，不能強造FAIL；診斷EXIT0不冒充功能PASS |
| S1 共用交易安全 | §5：push搜尋／提交一致、單格yield、鎖、原子commit、進度timeout | Q01–Q05通過；原captain/follower swap與owner測試通過；尚未修好的入口case照實失敗 |
| S2 路線與通道資料 | §3、§4.1–4.3：完整route保留、版本、連通寬度、gate/egress/component | 純資料oracle驗E01/E02僅18格點的路線也有passage；E05/E06/E07分類正確；隊長走完route後passage仍有效；C01未退步 |
| S3 單入口100人完整閉合 | §4.4–4.6、§6：phase目標、出口slot集合、局部綁定、出口優先、唯一完成predicate | E01/E02/E03與E04全部通過；全99人跨口、入口0、無回流、最終99格；F01/F02/F03同時通過，不能留下平地尾端問題 |
| S4 複雜入口與命令交接 | 多段、轉彎、雙lane、bypass、NPC、反向／換命令、容量不足 | E05–E12；三種正常dt；普通／swap／push中途換命令都有逐格證據與乾淨claims |
| S5 完整驗收與呈現 | 全部指定測試、生成山地、HUD與GPU四階段、正式budget/時間量測 | §9、§10全滿；最後檔案版本與每份log對應，不能用更早版本PASS代替 |

每一階段的patch說明格式固定：`違反的不變量 → 共用修改入口 → 對應失敗例 → 修後結果 → 仍未完成項目`。若考慮另一策略，先寫可觀測的原因；不做前輪那種多輪速度／配額試值。

## 9. 完整回歸、生成地形與可見畫面

1. 必跑既有 `terrain_lab_army_test.gd`（含swap/ramp/multi-level/ownership）、強化後passage/formation smoke、captain route。full regression驗每名隊員通過，不只隊長高度與production formation count。
2. 生成入口用 `TerrainGenerator.generate`：TERRACED_HIGHLAND、ROCKY_HIGHLAND × seeds `12345,24680,12346` × FOLLOW/EDGE，共12候選。先獨立驗地形可達／出口容量，至少每preset×command各1可行完整案例；列出所有被排除與失敗seed。既定可行失敗不能偷偷換seed。
3. 使用者原seed若可從目前場景／操作紀錄取得，保存並重播；沒有就明列尚無原場景重播，不阻止先完成固定與生成驗收。
4. 在 `terrain_lab.gd:_update_info` 讀真正FOLLOW/EDGE goal；顯示「隊长已到、待過口、core內、已出清、正式落位、最久停滯原因」。per-passage與binding詳細資料留診斷，HUD不重建全部100人trace。
5. 擴充 `terrain_lab_army_visual_test.gd`：接近入口、隊長已出而隊尾未出、最後一人離開core/egress、99人最終落位，各一張實際GPU截圖；至少E01與E02。既有部署／swap圖仍保留，不可充當新入口圖。
6. 影像檢查實際格／高度／遮擋與插值；遇swap、push、命令切換無瞬移／回彈。需要看時間行為時保留連續幀或短片。headless skip與圖片檔存在都不等於視覺PASS。
7. 沿用原效能腳本擴充「行軍、過口、收隊」取樣。報frame p50/p95/p99、army CPU、每類最大expansions、模擬／輸入／丟棄時間、每秒前向通道進度与完成時間。卡住後的idle FPS不能作效能改善證據。
8. 延續V3比較目標：未限速frame P95≤16.7ms、P99≤25ms、army CPU P95≤2ms/frame，正常行軍不反覆>50ms尖峰。記錄硬體/render mode；wall time效能未達須明列，不能把它改成容易漂移的硬性CI斷言，也不能編造FPS/GPU數字。

### 驗證命令與執行範圍

使用已安裝的 `godot-runtime-verify` skill helper；具體路徑先確認。以下是**未來S0加入case選擇後**的命令範例，不代表目前測試已支援或已跑過：

```powershell
& 'C:\Users\Nekki\.codex\skills\godot-runtime-verify\scripts\verify_godot.ps1' `
  -ProjectPath (Get-Location) `
  -GodotExecutable 'C:\Users\Nekki\Godot_v4.6.2-stable_mono_win64\Godot_v4.6.2-stable_mono_win64_console.exe' `
  -Mode headless -TimeoutSeconds 120 `
  -GodotArguments @('--script','res://scripts/tests/terrain_army_passage_test.gd','--','--case=E01')
```

每案各自有界，透過背景執行時必須依AGENTS立即設定watchdog。沒有schedule且單一程序太長，先選可前景完成的個案或使用實際工具所支援的有界監督方式，不留孤立程序。wall time timeout是未完成驗證，不是程式正確，也不等同已證明演算法無解；保留原始log後檢查。

editor模式驗parse/import；headless模式驗模擬契約；visual模式必須有GPU與新生成影像並實際檢視。root certificate store單獨訊息只在EXIT0且無其他錯誤時記為環境噪音。

## 10. 防止再次誤報的最後交付檢查

### 10.1 靜態反查（查到須逐項說明）

- `SOLDIER_COUNT + 1`／101還能否阻止passage服務？
- `captain_at_boundary()`還能否阻止FOLLOW的入口／出口／讓位？它只應處理EDGE目標語義與顯示。
- 高度相同／Manhattan最近trail還能否直接標已通過、RALLY或提前完成？
- 非RALLY的 `cells==desired` 是否仍讓scheduler直接continue？
- `_reserved_cells[...]`／`_push_lock[...]`／`movement_state=WAITING` 的所有寫入是否走共用規則？是否有取消半步的支路？
- `width=10`、OPEN、`desired=cells`、全體idle重配、裸yield是否仍繞過新契約？
- `_consume_path_route_step`是否仍在隊長到goal時刪掉隊尾資料？
- 每tick同步全圖flood、兩次消耗局部配額、舊版window gate是否仍存在？
- 新的通過counter是否只在成功commit或明確EXEMPT寫入？測試oracle是否獨立？

靜態零命中不等於功能通過；查到合理的EDGE顯示或fixture初始化不需機械刪除，說明caller與用途。

### 10.2 必交證據表

| 項目 | 必填欄位 |
| --- | --- |
| 版本 | runtime/test SHA256、修改檔案、最後改動時間；untracked/staged/committed狀態 |
| 每個case | fixture/seed/fingerprint、dt、input與sim秒數、預期/實際crossed與cleared/settled、剩餘者、EXIT、timeout、log路徑 |
| E01/E02特別項 | 10/20/30/40秒快照、最後通過時間、上游最終slot數必須0、99人逐人入口/出口事件 |
| 安全性 | overlap/illegal edge/owner mismatch/invalid claim/lock leak皆0，換命令與timeout的證據 |
| 正確收隊 | 正式slot集合與實際cells相等、99人綁定唯一、穩定5秒、completion未提前true |
| 公平／效能 | 最大eligible等待、每類最大expansions、丟棄秒數、正在通道活動時的CPU/frame數據 |
| 視覺 | 四階段新圖、各圖對應case/sim時刻、實際檢視結果 |
| 未完成 | 明列FAIL/TIMEOUT/SKIP/未測；不能以總稱PASS覆蓋 |

最後一次改程式後，受影響測試須重新驗證；數值還原後也要核對檔案hash，不能憑記憶套用早前PASS。**不用「應該會過」「大部分恢復」「只差幾名」「helper正常退出」作完成理由。**

### 可直接貼給 Luna 的交接指令

> 請以本工作區的 `TERRAIN_LAB_ENTRANCE_CLEARANCE_FIX_V4_LUNA_MAX.md` 實作入口卡住修復，採 max 推理。先核對 §1 hash與既有改動，完成S0正式失敗測試，再依S1–S5執行。現版同高度短通道40秒仍79人在上游、20–40秒跨口人数停在20；坡口40秒仍68人在上游。兩案trail僅18格、21個最終目標仍在入口側；Q01還會產出含中間空格的無效push鏈。
>
> 保留已修好的隊長BFS與owner檢查；完成逐人passage進度、FOLLOW內陸出口疏散、固定最終slot集合、共用交易安全、公平搜尋與唯一完成predicate。禁止調速度/配額/期限、只降低101門檻、用當前入口格作slot、取消半步或把≥90人當99人完成。所有正式100人案例經advance_frame，逐人實際跨gate與出清才算通過。每階段按文件交失敗例、修改入口與修後log；持續完成已授權的修正，最後依§10交付完整證據及實際未測邊界。不要自行stage/commit。
