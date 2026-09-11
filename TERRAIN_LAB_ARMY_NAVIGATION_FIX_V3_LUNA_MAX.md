# Terrain Lab V3：隊長最短路徑與 99 人卡住修正計畫

日期：2026-09-09。交接對象：`gpt-5.6-luna`，reasoning effort=`max`。

本輪是診斷與實作計畫，**沒有修改遊戲程式或既有正式測試，也沒有啟動 Luna 任務**。新增一支隔離診斷腳本並執行一次，已重現「隊長先走錯方向」及「平地 FOLLOW 大量未就位」。下列 P0–P6 都是待實作工作，不是完成紀錄。

本文件取代 `TERRAIN_LAB_FOLLOWER_PASSAGE_FIX_V2_LUNA_MAX.md` 中重疊的導航、通道、讓路與驗收要求；保留 V2 作歷史資料。舊版某些假完成寫法已被修改，不可不看現況就再套用舊 patch。原有 baked atlas、隊長呈現、跑步及 2D 場景契約不變。

## 1. 本輪證據與交付目標

### 1.1 現行基線

`scripts/terrain_lab/terrain_army.gd` SHA256：

`36628F5A0E6745F871074EDA1E7B63A2813FA6A82C456EB2FD90F6C158DE153D`

行號只對應本次基線，實作前依函式名稱重查。相關檔案仍有 untracked 狀態，工作區另有大量使用者修改／刪除；不得整批還原、清理、stage 或提交。修改前保存相關檔案副本與 hash，不能假設 Git HEAD 包含其基線。

### 1.2 已執行的兩個診斷

診斷腳本：`.godot-temp/army_navigation_v3_audit.gd`。

| 案例 | 輸入與觀測方式 | 現行結果 | 證據邊界 |
| --- | --- | --- | --- |
| 隊長 U 形死巷 | 12×10；可走格為 `(x=1..6,y=5)`、`(x=1..8,y=3)`、`(1,4)`；起點 `(2,5)`，目標 `(8,3)`；獨立 BFS 作距離 oracle | 最短 10 格；現行 `_next_step` 策略走 18 格。先向右走到 `(6,5)`，再回頭至 `(1,5)` 出巷 | 隔離下一步策略測試：無外部角色／隊員，手動套用合法 next cell。不是完整 100 人命令／動畫測試；P1 要補正式命令驗收 |
| 平地 FOLLOW | 100×100 全 WALKABLE；PLAYER `(50,50)`，NPC `(51,50)`；正式部署與 FOLLOW，再把 PLAYER 放到 `(80,50)`、發 FOLLOW；停用自動 process，呼叫 `advance_frame(1/60)` 共 1200 幀 | 輸入 20 秒後，隊長已在 goal `(75,50)`；依每人實際 `cell==desired` 且不在 MOVING/SWAPPING 計得 **43/99**；仍有 1 人移動和 pending push；多名隊員 blocked_time 約 13–15 秒 | 正式每幀入口的 headless 模擬，未作視覺驗證；當前 desired 仍是 production 值，不能用這個計數反過來證明將來的陣位設計正確 |

平地 fingerprint：`60410055268bdd79dc93436897e4d0a4031a935bf6b50820d521aabdc0c6a40d`。完整 100 個起始 cells、路徑、卡住樣本與 pending push 在原始輸出中。

執行紀錄：`.godot-temp/godot_verify/20260909_230115_933/` 下的 `result.json`、`stdout.log`、`stderr.log`。Godot `4.6.2 stable mono`，headless，耗時 3.182 秒，EXIT=1，未 timeout。診斷在重現缺陷時刻意以非零退出，因此是 **baseline FAIL／缺陷重現**，不是修復 PASS。stderr 另有 root certificate store 訊息；不要把它當成功，也不要掩蓋已記錄的導航失敗。

這兩個反例不是使用者當時的山地 seed；目前尚未取得該地圖／操作重播，也未在本輪測完多山口、生成山地或 GPU 畫面。

### 1.3 必須完成的結果

1. 地形固定、無外部動態阻擋時，隊長從本次路線起點到實際命令目標，走過的合法格邊數等於独立 BFS 的最短距離。不能只驗 BFS helper 的輸出。
2. 平地先做到 99 名隊員全部落在合法、唯一、事前發布的陣位，並穩定保持；再要求短通道、同高度窄口、多級坡道也能全員通過和集合。
3. FOLLOW_PLAYER 與 MOVE_TO_EDGE 共用通道／讓路流程。隊長停在內陸後，隊尾仍須繼續出通道。
4. 「隊長抵達」「通過出口」「落位」「恢復十列」分開統計。永久外部封路、真正不可達、出口空間不足都回報具體原因，不偽造完成。

不能用穿崖、重疊、瞬移、重設目前 cells 為目標、取消在途一步、提高速度、放大搜尋配額或延長原驗收期限來取得 PASS。

## 2. 根因與修改入口

以下是現行控制流缺口；除了 §1 的兩個實測外，其餘是靜態確認，仍須由對應反例證明影響。

| 優先 | 位置 | 現行問題與要改的責任 |
| --- | --- | --- |
| P0 | `_next_step` 2455，特別 2465–2506 | 有 route 才跟 route；否則先回傳 Manhattan 下降的鄰格，走不動且 blocked≥0.3 才 BFS。因此「有 BFS」仍不保證隊長走最短。改為先完整發布最短 route，再執行其下一步 |
| P0 | `_find_follow_goal` 699、`_choose_edge_targets` 1504、`_ensure_distance_map` 1551 | 找目標時已有完整距離搜尋，卻丟掉 predecessor，實際走路又回到貪心。命令目標與 route 應由同一筆搜尋結果產生；不要同步全圖搜尋後再重搜一次 |
| P0 | `_replan_follow` 674、`issue_command` 547 | PLAYER 未動也可隨隊長移動重選 goal；命令切換註解說取消 queued claims，但未完整處理 pending push／通道狀態。需要命令與路線版本，避免舊工作污染新命令 |
| P0 | `_find_push_chain` 1990，尤其 2014；`_queue_push_chain` 2058 | 新增的出口陣位限制只拒絕空格作終點，仍把這些空格加入搜尋並繼續展開。可能產出「中間已有空格」的鏈，提交端卻要求中間全部有人，反覆拒絕。搜尋與提交必須使用相同可行條件 |
| P0 | `_schedule_follower_blocker` 2198、`_schedule_push_unit` 2028 | 全域 pending gate、遞迴讓位及搜尋／提交限制不一致；搜尋未完整排除鎖定成員。單格 yield 仍可能繞過交易與出口限制。統一共用入口檢查 |
| P0 | `_advance_pending_pushes` 2137、`_release_push_transaction` 2107 | age 按總時間增加；長鏈有進度也可能到 4 秒被取消，cancel_moving 會重設在途動作。改為無提交進度 timeout；已開始的邊必須原子完成 |
| P1 | `_route_width` 748、`_captain_trail_progress` 799 | route 空即推定寬10；以單一 heading 掃多步並累加不連續 lane；以最近 Manhattan trail 推進度。轉彎、同高度隔牆、分離坡口都可能誤判 |
| P1 | `_assign_bottleneck_queue_targets` 849、refresh 901、`_follower_navigation_goal` 1315 | trail 少於101不排隊；出口只在邊界啟用；同高度直接追 slot。欠缺逐人、逐通道、有方向的進度，不是調小101即可修好 |
| P1 | `_exit_rally_targets` 820、`_publish_exit_rally_targets` 957 | BFS 可以穿過 trail 繞回入口側；前99個 flood 格不代表十列；依 Manhattan 重新配對缺少版本與原因。出口集合呼叫又依賴邊界、全隊無移動與無 pending，無法救援持續交換／讓路的活鎖 |
| P1 | `_settle_exit_rally` 994、`_update_formation_status` 1046、`is_formation_complete` 643 | 現在已比舊版嚴格，不能再宣稱仍有原地覆寫的同一段舊碼；但仍有多處直接設 OPEN/width10，完成條件缺隊長實際 goal、逐人通道進度、pending/claim 與實際幾何核對 |
| P1 | `_update_formation_targets` 1077 | preferred 只驗 walkable，不足以證明可達；部署 offset 不是十列布局。保留既有 slot-set 穩定性修正，另補可達性與真正布局 |
| P1 | swap guards 1711／1812、`_begin_follower_swap` 1836、`_complete_move` 2508、prune 1761 | swap 共用入口未涵蓋所有 push lock／意圖；commit 會直接 erase／覆寫 owner；prune 仍可能讓只有 desired 相等、無交易的 claim 存活。必須在共享入口驗 owner，不只在某個 caller 加 guard |
| P1 | `_next_follower_step` 1347、`_detour_window_allows` 1461、`_find_local_route` 1239 | 两個輪轉窗口交集、先到先消耗局部搜尋額度，可使部分隊員長期得不到機會；空 route 又混合預算不足、等待與無路。改單一公平游標並區分搜尋結果 |
| P2 | `advance_frame` 2605、HUD `terrain_lab.gd` 約 444 | catch-up cap 會丟模擬時間卻無計數；其他全圖／push 搜尋未完整納入每幀預算。HUD 的 captain goal 只從 edge_targets 讀，FOLLOW 看不到真正目標 |

## 3. 邊界與最小設計

### 3.1 保持單一 owner

- 所有命令、路線、格占用、交易及隊形狀態仍由 `TerrainArmy` 擁有；`TerrainData.can_step` 是唯一合法相鄰邊判斷。
- 保留 `Node2D`、`cells`／`moving_to` 分離、99 人 baked atlas、隊長既有呈現、合法交換及固定 simulation tick。禁止每兵新增 NavigationAgent、全圖 BFS 或每兵 SceneTree 模擬節點。
- 重用现有 incremental BFS、predecessor、follower route/cursor、pending push；不新增通用導航服務、通用事件系統、依賴套件、CBS／全局多智能體求解器。
- 不修改地形生成以繞過測試，不改 World–Region–Site、存檔、戰鬥或其他角色控制器。架構以 `PROJECT_ARCHITECTURE.md` 為準。

### 3.2 明確定義「最短」

目前 `can_step` 是四方向、每條合法邊等成本；此輪最短指**格邊數**，不是含等待的最短秒數，也不是最少動畫幀。

- EDGE：在合法且地形可達的實際邊界格中取 BFS 距離最小者。多個同距離目標依既有 boundary 枚舉順序決定；對同一目標，鄰居 tie-break 固定沿用 `TerrainData.DIRECTIONS`。
- FOLLOW：保留現有 PLAYER 周圍 Manhattan 距離 3–5 格的合法停止帶，選其中 BFS 距離最小者。不要悄悄改成一定距離3；目前已在合法停止帶就應是零步完成。
- 隊員是可協調占用：不從隊長的靜態地形圖永久刪除。下一格被隊員占用時等待／讓位／合法交換，不擅自偏離 route。
- PLAYER 本體格與當前不可用外部目標不作 terminal；外部角色的即時阻擋另處理。固定外部障礙的繞行測試以同一障礙快照作 oracle。
- 動態角色改變後，以「重規劃起點＋當時障礙快照」驗新 route 的最短性；記錄每次 revision，不能聲稱動態全程有全局最優保證。暫停等待不增加步數，繞路則要有失效原因。
- 最近邊界出口若沒有足夠集合容量，隊長目標最短性與整隊集合限制分別回報。不可為湊99人偷偷改選較遠邊界並仍宣稱原目標最短。

### 3.3 僅補必要狀態

欄位名稱可依現行風格調整，不要求新增 class；每個欄位只有一個寫入責任，重複旗標能移除就移除。

| 狀態 | 最小内容／失效條件 |
| --- | --- |
| `command_epoch` | 正式換命令／重新指派命令時遞增；舊搜尋、未啟動交易與 slot 綁定失效 |
| `route_revision` | 隊長從已提交格發布新 route 時遞增；記錄 start、goal、reason、地形版本及必要的外部障礙快照 |
| route 與 passages | 保留完整命令 route 及消費游標；從完整路線建立必要的窄口段描述，不依已走 trail 長度啟用。隊長到終點後，隊尾仍需的 passages 不得被清空 |
| 每名隊員進度 | 所屬 passage、階段、已提交出口序號、穩定排隊 ticket；只由已完成的合法移動／交換更新，不以高度或 Manhattan 距離猜測 |
| slot set | 地形產生的目標集合、layout／heading、revision、發布原因；unit→slot 配對與 slot 集合分開保存 |
| push transaction | id、epoch、成員／鎖、所需 claims、cursor、requester 的最終進入格、最後提交進度時間；優先擴充既有 Dictionary |
| 診斷 | 每人 wait reason、上次真正提交時間、最後獲得搜尋機會時間；每幀各類 expansions、輸入／實際模擬／丟棄時間 |

`PathStatus` 的 start==goal 必須是零步已完成而非 UNREACHABLE。局部搜尋至少區分 FOUND、PENDING/BUDGET、WAIT_OCCUPIED、UNREACHABLE；只有完整耗盡可搜索空間才可宣稱無路。

## 4. 實作順序與逐階段出口條件

依序 P0 → P1 → P2 → P3 → P4 → P5 → P6。每階段先有獨立失敗例，再改根因，通過對應 gate 後才擴大。過程可以出現「安全性已過、全隊尚未收斂」，但不可包裝成整體完成。

### P0：鎖住基線、獨立 oracle 與失敗退出

1. 將 §1 兩個小反例搬入既有測試檔，保留重播資料；隔離腳本不用加入遊戲。隊長策略反例放 `terrain_lab_army_test.gd`，平地正式入口反例強化 `terrain_army_formation_smoke_test.gd`。
2. 既有 `terrain_army_passage_test.gd` 目前只有弱的 false-rally 案例。直接擴充此檔，不再新建平行測試框架。
3. 測試自己用 `can_step` 做 BFS oracle，不能呼叫 production `_find_path` 當最短答案；自己追蹤前後 cells 的合法提交，不用 formation_count／passed 變數當唯一完成證據。
4. 正式整隊測試必須 `set_process(false)` 後走 `advance_frame(dt)`。小型 swap／queue helper 測試仍可直接驅動，但要標明邊界。兩種入口不能互相冒充。
5. 失敗先輸出 case id、seed/parameters、terrain fingerprint、100 個初始 cells、角色位置／命令時間線、dt 序列、route/slot revision、卡住者和交易，再 `quit(1)`；fixture 配置失敗另記 `FIXTURE_INVALID` 並非零退出。不要讓 assert 停在 SceneTree 內，最後只留下 timeout。
6. 全程每個提交後檢查：100 格唯一；owner↔cells 雙向一致；每一步相鄰且 can_step；MOVING 目的格有自己的 claim；swap 成對原子提交；claim/lock 均可追到正在移動或尚有效的交易。

**Gate P0：**保留 U 巷 10 vs 18、平地 43/99 的 baseline FAIL；後續測試成功時正常 EXIT=0。診斷重現的非零退出不可以沿用為「修復測試成功」。

### P1：隊長先發布真正最短 route，再開始走

1. 重用 `_start_path_job`／`_advance_path_job`／`_path_result`。讓同一筆 BFS 從固定起點找 terminal set，並保留 predecessor；找到最小距離層後完成該層必要的 tie-break，再同時發布 goal 與 route。
2. 不再讓 `_find_follow_goal`／`_choose_edge_targets` 先同步掃全圖、丟掉路徑，稍後才做另一次 BFS。保留外部呼叫契約或小包裝，核心搜尋只能有一個 owner；命令接受但還在搜尋時可顯示 PLANNING。
3. `_next_step(index=0)`：PENDING 就等待；FOUND 只取 route 下一條邊；零步即到達；UNREACHABLE 明確報告。刪掉 route 發布前的 Manhattan 走法與「堵0.3秒才搜尋」。
4. 搜尋期間起點凍結。若命令在 MOVING/SWAPPING 中改變，先讓該原子動作提交，再以實際 cells[0] 啟動新 epoch 搜尋；禁止在舊邊走一半時用舊 source 搜新 route。
5. PLAYER 不動、地形不變、route 仍合法時，FOLLOW goal 不隨隊長移動每0.5秒重選。PLAYER 改目標才合併成最新待規劃請求；發布時核對 epoch、start、目標快照，過期结果不得提交。
6. 靜態距離場不得混入可移動 NPC 卻只用 origin 作 cache key。地形場只存靜態拓撲；需要避開持續外部阻擋時，用版本化 obstacle snapshot 做有原因的重規劃。可沿用 BLOCKED_REPORT=5秒作持续阻擋診斷門檻，但角色離開必須能恢復，不把等待快取成永久無路。
7. 重用路線資訊供編隊，不讓 `_clear_navigation_paths` 被一般 slot 更新呼叫而清掉隊長命令 route。普通 movement 和 captain swap 都由同一提交入口消費 route；畫面插值不推進 route cursor。
8. 發布前檢查每條邊合法、終點等於 goal、長度等於當次搜尋距離。保存整條 route 供通道分析，別在隊長到終點時把隊尾仍需的描述一起刪掉。

**Gate P1：**U 巷正式走法恰10格；另有繞牆時必須先離目標更遠、先上坡才能下坡、EDGE 多出口、FOLLOW 停止帶、零步到達、無路、搜尋未完成與途中換命令案例。完整正式命令的實際隊長提交邊數也要與獨立 oracle 相等。等待隊員可以增加秒數，不能增加未記錄理由的繞路步數。

### P2：先封住讓路／交換／提交的狀態破口

1. `_find_push_chain` 必須只展開符合交易條件的占用格；遇到合法可用空格立即作終點；遇到不允許作終點的空格就停止該分支，不能把它當「中間有人」繼續走。
2. 搜尋時便排除其他交易 lock、MOVING/SWAPPING 成員、外部角色、非本人 claim，以及不能移出／移入的通道或 slot 邊。`_queue_push_chain` 以同一規則再次核對當前狀態，失敗不留下部分 reservation。
3. 單格 yield 也轉成既有 pending transaction 的最短形式，不再由遞迴分支直接寫 `_reserved_cells`。空格路由和 blocker chain 不要混成一種不明 path。
4. transaction 從空端逐格完成 blocker 移動，最後由原 requester 真正進入取得的格，才釋放剩餘 claims／locks；第三方不能在交接間搶走空格。
5. 首輪可保留一筆全域 push transaction，以降低修改面，但要有公平待辦輪轉、後述上限及測試。若保留這個簡化，在程式以 `ponytail:` 註明「全域序列化的吞吐上限；只有實測未達通過期限才升級互不相交交易」。普通互不衝突移動不得因此全部停止。
6. 4秒改為**無真正提交進度**的 timeout。每個 blocker／requester 的合法提交更新 last_progress；僅重新排程、插值或換意圖不算進度。timeout 取消未開始尾段，已在途那條邊及其安全 claim 保留到提交，禁止 move_progress 歸零回源格。
7. `issue_command` 遞增 epoch 並取消舊 epoch 未啟動意圖；在途 move/swap 完成後，依 owner 精確釋放舊交易。不 `clear()` 整張 reservation，也不把舊通道 ticket 誤接新路線。
8. captain swap、follower swap、遞迴 blocker、普通 begin-move 均在**共用入口**核對双方 lock／claim。`_begin_follower_swap` 本身必須要求明確互換意圖，不依賴 caller 記得 guard；REGROUPING 的合法 slot 置換不能一律禁止。
9. `_complete_move` 提交前核對 source owner、destination claim owner、legal edge、允許的 destination owner。任何不一致先回報 invariant failure，不 erase 別人的記錄或覆寫占用。swap 先檢查整對，再一次更新兩方；不能只成功一半。
10. prune 只依實際 in-flight movement 或活躍 transaction 保留 claims。`desired==cell` 不代表 reservation 有合法 owner。將相關寫入點收斂到共用 begin/commit/release，不逐個 caller 補丁。

**Gate P2：**中間空格反例、3 blocker 尾端空格、第三方搶格、requester 最後入格、鎖定 partner、單格 yield、超4秒仍持續進度長鏈、真正無進度取消、MOVING／SWAPPING／push 中換命令，全部 ownership／合法邊不變量成立；未要求此時已修好所有山口。

### P3：平地 99 人真正就位與公平排程

1. 先生成與地形相容的陣位集合，再配對人。空曠平地以10個橫向 column、最多10排的99格為優先；省略格位置固定，由朝向／anchor 決定，不看哪些人剛好停在哪裡。隊長格、角色格及保護的通道出口不能算隊員 slot。
2. 用有限候選 anchor／朝向尋找合法布局，每個候選都查 walkable、靜態可達、唯一性與容量。原 `_formation_offsets` 的部署菱形不能直接當十列證據。若無十列但有較窄的合法99格布局，發布真實寬度；不足99格則報 `INSUFFICIENT_RALLY_CAPACITY`，不能填上不可達點。
3. 保留可用的 slot-set 穩定性；只在 anchor、命令、路線、地形或布局條件真的變化時換 set。重新配對 unit→既有slot 不等於換 set，需另記 revision/reason。
4. 初始配對用穩定的 row/lane 次序，通路深處的 slot 先服務；距離比較以同一可達場／局部合法路線為準。不要每 tick 用 Manhattan 最近重新洗牌，也不要先引入99×99最優匹配器。
5. 平地排列中的2人互換：要求双方確實需要對方格，走原子 swap。3人以上錯位環：先在固定 slot set 內做一次有原因的局部重新配對（每人仍是唯一合法slot、路線／通道資格一致）；若仍需位移，借鄰近合法空格做 P2 的 vacancy transaction。已發布集合不變，不能把 arbitrary current cells 加入集合。
6. 移除兩個 detour 輪轉窗口相交的機會限制，只留一個 round-robin service cursor；收到 BUDGET/PENDING 時保留 route/goal/cursor，不增加「永久無路」狀態。每個被服務的請求最多用一份局部搜尋配額。
7. 每名持續 eligible 隊員在最多 `ceil(99 / MAX_LOCAL_PATHS_PER_STEP)=25` 個 sim tick 內得到一次局部搜尋服務。暫被交易鎖／外部角色擋住者記 WAIT_LOCK／WAIT_EXTERNAL，不得藉這些理由掩蓋無鎖可服務者的飢餓；解鎖後回公平隊列。
8. 不等「全隊 moving=0 且 pending=0」才允許處理錯位；可以在受影響成員穩定時做局部配對修正。保持每筆交易有限，避免為救1人持續移動同樣幾人但其餘人永遠得不到服務。
9. 完成 predicate 保持唯讀：隊長已到實際 goal、99 名隊員占滿已發布 slot set、各自 binding 正確、無 in-flight／pending／孤兒 claim；OPEN／width 由布局事實導出，不由「大家沒動」硬設。

**Gate P3：**§1平地正式 FOLLOW 在原20秒輸入期限內達99/99，另保持5秒穩定；2人／3人 slot 錯位、最後一名永遠需要detour、公平輪轉及 NPC 移開恢復均通過。不再以90人、較寬距離或強設width=10作通關條件。若20秒未達，記錄最後進度與剩餘原因，繼續修復，不靜默改期限。

### P4：短通道與多通道的逐人通過流程

1. route 發布時，從完整合法路線分析窄段；不等隊長走出101格，也不依「route空所以寬10」。沒有已知 route 時顯示 PLANNING／UNKNOWN，而不是假定OPEN。
2. 寬度沿每一條 route edge 的局部 heading 量測。從 route 所在 lane 向兩側逐格拓展，要求橫向連通且平移後的前進邊也合法；遇缺口立即停止，不加總互不相連的坡口。彎道查轉角內外的實際邊，採瓶頸寬度，不用第一段 heading 代替整段。
3. 合併相鄰／出口尚未有疏散空間的窄段為同一 passage；保存入口 gate、ordered corridor、出口 gate 及受保護的 egress。連續多級坡道可成一組或多組，但每人的必經出口序列必須明確。
4. 出口側不能由 height 或半平面近似。優先使用局部封閉 corridor/gate 後的地形連通域，集合區須從出口可达且不得經過受保護通道繞回入口；有限局部分析若无法安全區分，保留 COLUMN 並報 `PASSAGE_UNRESOLVED`。不能換成曼哈頓猜測並標已過；P6固定可行案例不得留此未解狀態。
5. 每人依次為 APPROACH → IN_PASSAGE → EXIT_CLEAR → RALLY。APPROACH 追本段入口／合法排隊格；IN_PASSAGE 追有序 corridor；EXIT_CLEAR 優先清空出口；RALLY 才追最終slot。狀態只從合法提交邊更新。
6. 固定 ticket 以合法到入口距離、unit index tie-break 建立，不以直線近遠每tick重排。只給前方確有空間的人發入場許可，入口排隊格必須唯一／合法；其餘人在原側合法等待，不把99人目標塞同一格。
7. 同高度的 FOLLOW 也必經 passage，不再走 `_follower_navigation_goal` 的同高捷徑。新 route 出現時若某人已在下游，可用經驗證的出口側連通域標成不需過舊口，記錄 initial-exempt 原因；不能偽造跨口事件。
8. 路線反向：已在單格 passage 內者先按原方向走到安全出口，未入場者暫停；清空後再交接新方向與 tickets。正反向不得同時放行而形成無法相遇的兩股人。這是有界 drain，不是永久忽略新命令；用反向案例驗完成。
9. 通道資料屬 route revision；換 revision 時只能依已提交位置與明確 gate／component 對應遷移，不能用最近 trail 點硬跳過數段。找不到映射者從安全側重新排隊，不重設 cells。

**Gate P4：**同高隔牆唯一缺口、短坡口、S彎、分離lane、多級且重複高度，逐人出口順序正確；路程<101也啟用。FOLLOW 與 EDGE 都進入同一通道流程，隊長在內陸停住仍持續有隊尾通過，無逆向回流／非法跨崖；完整99人出口疏散與最終落位是下一階段P5的出口條件。

### P5：出口疏散與收隊，不再讓前排堵住隊尾

1. route 中每段 egress 由出口到可散開處的合法格邊組成，最後必經者離開前不可發布為最終 ARRIVED slot。保護區有清楚範圍與釋放條件，不能把整張圖都保護到無空間可動。
2. 從出口可達區建立 P3 的 slot set，明確排除入口側、未過通道與 egress。若十列布局暫需占用 egress，先用合法 staging slots 疏散；最後一人出清後，以明確原因發布最終 layout revision。
3. staging 不是完成，臨時位置不能自動成為正式slot。出口靠近邊界時，可平移／旋轉事前定義的有限布局候選；容量不足要真實回報。
4. 出口先出者先往深處或側面可達slot移动，避免把最近出口的一圈全部停滿。調用 P2 交易與 P3 公平服務，不能另外寫一套山口专用 reservation／swap。
5. 移除 `_publish_exit_rally_targets` 只在 captain_at_boundary 才工作的限制；是否到達使用實際 goal，是否可放行使用逐人 passage 進度。隊長到任意邊界不代表已達 EDGE 選中的那個 goal。
6. 合併 `_settle_exit_rally`、`_update_formation_status`、`_desired_formation_mode` 中重疊完成轉換。唯一 predicate 驗證目標、逐人進度、slot集合及靜止狀態；其他函式只讀結果。不在 completion helper 修改 desired/slots/offsets，不強設99或10。

**Gate P5：**隊長已停、前98人已出、最後1人仍在口內時必須保持未完成且出口暢通；最後1人出清後99人占滿正式slot並穩定5秒。FOLLOW內陸與EDGE邊界兩種皆過；同高且近在24格內但隔牆者绝不可假完成。

### P6：正式每幀預算、生成案例與畫面驗收

1. 搜尋配額由 `advance_frame` 發放，在正式路徑中計數。隊長／共享結構 BFS 每幀最多現有256 expansions，由同一搜尋工作機制消費；無sim tick的畫面幀也可推進待完成搜尋，但不得多處重複發額度。
2. follower 仍最多每sim tick 4份局部搜尋，每份≤1024；兩個tick/frame時硬上限8192。保留所有無搜尋的合法直接步排程能力，不為了公平搜索把100人的便宜移動限成每tick只動4人。
3. push 探索先限制每sim tick最多1份、每份≤既有512 expansions，以round-robin選 requester；最多2tick/frame即1024。slot／出口區／距離場不能另偷跑無上限全圖 BFS，結構搜尋使用上項共享256配額，結果完成後才發布，保留原有效snapshot等待。
4. 若現有程式無法同時供 route 與 formation 搜尋，排隊優先處理命令 route、再處理必要出口／slot結構；使用既有 BFS 核心及最少job metadata，不新增導航框架。陣位每tick微調不能反覆重啟全圖作業。
5. 增加 `input_seconds`、`simulated_ticks/seconds`、`dropped_seconds`、最大每幀tick與各類 expansions。60Hz、30Hz及固定jitter序列在相同輸入秒數下比較；不可用掉時後只前進半段卻FPS高來宣稱改善。
6. HUD 每0.1秒更新即可：兩種命令真實goal、route revision／長度／已走邊數、passed/99、settled/99、待服務人數、最久無進度與wait reason。詳細100人trace留測試／診斷輸出，不每frame重建大字串。
7. 生成矩陣使用 `TerrainGenerator.generate` 正式入口：TERRACED_HIGHLAND、ROCKY_HIGHLAND × seeds `12345, 24680, 12346` × FOLLOW/EDGE，共12組候選。固定初始化／操作，存完整重播；無路或容量不足組應測正確受限狀態，不計入可行成功數。至少取得每種preset×命令各1個經獨立查核可行的完整通過案例；可有界補搜seed，但必須列明試過哪些、為何排除，禁止默默換掉失敗seed。
8. GPU視覺用既有測試入口擴充：接近口、隊長出口而隊尾未出、全員出清、99人正式落位四階段。核對實際cell／高度／遮擋與畫面一致，隊長／一般兵行走跑步及交換無回彈、滑行／瞬移。新圖必須存在且人工檢視，只有截圖檔名不算視覺PASS。
9. 效能量測必須涵蓋正在行軍／通口／收隊，而非卡住後idle高FPS。報硬體／Godot／render mode、frame p50/p95/p99、simulation耗時、各類最大expansions、每秒合法提交／過口人數及完成秒數。沿用 `TERRAIN_LAB_ARMY_PERFORMANCE_PLAN_LUNA_MAX.md` 的比較条件與目標：未限速P95≤16.7ms、P99≤25ms、軍隊CPU P95≤2ms/frame、正常走動不反覆出現>50ms尖峰；時間指標作實測報告，不塞成易抖動CI斷言。既有performance腳本只檢查「有移動」便印PASS，必須分開功能PASS和效能是否達標，未實測的FPS/GPU數字寫未測。

**Gate P6：**全部固定契約案例通過、生成可行案例完整通過、受限案例正確分類、預算／時間證據合格、實際畫面檢視通過，才能宣稱「本輪導航與卡住修復完成」。未拿到使用者原seed仍需明列此邊界。

## 5. 必備回歸矩陣與判定方式

所有整隊測試須保存完整初始cells與timeline。合成圖的 BLOCKED 格必須移除 WALKABLE 位；坡道建立相鄰兩格雙向合法 ramp bits，不能單憑畫面像斜坡。建立測試狀態時可以一次設定合法fixture，模擬開始後禁止測試幫production瞬移、取消移動或配陣。

| ID | 固定案例 | 不能省略的斷言 |
| --- | --- | --- |
| C01 | §1 U巷策略反例＋下述100人正式命令擴充圖 | 各自oracle=10，策略與正式移動步數各=10；等待期間不推cursor；不能往12×10小反例硬部署100人 |
| C02 | 繞牆、必須先上坡、同距離雙出口；FOLLOW停止帶 | 以獨立BFS驗goal選擇與實走步數；HEIGHT不是目標選擇捷徑 |
| C03 | start已在停止帶／邊界、完全無路、搜尋跨多幀 | 零步正常完成；PENDING不誤報UNREACHABLE；沒有先貪心偷走 |
| F01 | §1平地100人FOLLOW原fixture | 20秒內99/99，之後5秒穩定；真實十列幾何、slot-set未被目前cells污染 |
| F02 | 2人互換、3人錯位、合法空格在不同側 | 依P2/P3收斂，目的唯一；未因REGROUPING關掉所有交換；不得不停ABAB回跳 |
| F03 | 99名均持續需要局部搜尋，index99最後入隊 | eligible者≤25tick獲服務；另驗有lock解除後恢復，預算不超額 |
| T01 | 100×100、x=50整道牆只有(50,50)開口，兩側可容100人；EDGE版另封所有邊界只留(99,50) | 初始100人全左側；FOLLOW PLAYER停右側內陸；逐人記錄(49,50)→(50,50)→(51,50)；路線<101仍全員過口；EDGE不得因就近選左邊界而根本沒測到缺口 |
| T02 | T01改一級合法坡口；通道長4與12格 | 不跨非法崖；隊長早停不終止队尾；保護egress而非卡滿出口 |
| T03 | S彎、同高隔牆／分離坡道、重複高程、多級坡道 | 每名隊員逐口順序與通行合法；不以最近trail／同高度跳過通道；相隔lane不加總寬度 |
| T04 | 隊長右側(45,50)，99人左側x34..43/y44..53，x44牆僅y10有口 | 隊長已到FOLLOW目標、所有人近且同高度仍不能假完成；此為靜態錯誤狀態fixture，不能取代T01正式命令 |
| T05 | 前98人出清，最後1人未出；出口容量不足另1例 | 未出清前不占egress；容量不足報原因而非99/99；可行版最後一人落位後穩定5秒 |
| D01 | NPC暫時封唯一口後離開、NPC持續封路、有替代路 | WAIT_EXTERNAL與真正地形無路分開；離開後恢復；重規劃有revision/reason且以新快照驗最短 |
| D02 | MOVE／SWAP／push途中FOLLOW↔EDGE；單格口反向 | 在途邊原子完成、舊epoch未啟動claims清除；反向有界drain後新命令完成，無死鎖或跨格撤回 |
| R01 | push鏈含中間空格、3 blocker、第三方搶格、長鏈>4秒 | 搜尋/提交條件一致、requester最後入格、有進度不timeout、無owner覆寫 |
| B01 | 60Hz、30Hz、固定jitter及一個超cap壓力序列 | 正式advance_frame；記input/sim/drop；正常序列不丟時且完成；超cap序列正確記丟時，不當成相同時長PASS |

固定fixture補充，避免測試配置先把問題繞開：

- **C01正式命令版**：100×100先全BLOCKED；開啟下列格：下橫道`x=14..24,y=50`、上橫道`x=19..26,y=48`、接點`(19,49)`、上游房間`x=5..14,y=50..59`、下游房間`x=26..45,y=30..47`，以及PLAYER格`(31,48)`。隊長初始`(20,50)`；99名隊員放在上游10×10房間中、排除固定的`(5,50)`，初始化owner/claim後再開始模擬。PLAYER在`(31,48)`，無NPC阻擋。正式發FOLLOW；停止帶最短合法goal是`(26,48)`，最短距離10，先往右進死巷則多8步。此為一次性合法fixture初始化，不是deploy測試；模擬開始後只呼叫正式命令／advance_frame，不手動改cells或desired。正式deploy整合由F01/T01覆蓋。P1觀測隊長實走距離，房間提供後續隊員測試所需空間，不以全隊完成取代隊長最短斷言。
- **T01命令版**：正式deploy時PLAYER可置`(20,50)`、NPC`(18,50)`，先驗全部100個起始格在牆左側並記錄實際cells，再移PLAYER到`(80,50)`發FOLLOW。EDGE變體保留NPC非阻擋位置、封閉其他邊界後發EDGE，獨立BFS確認唯一goal`(99,50)`及路線確經缺口；不得只驗某個任意邊界。
- **B01固定jitter**：循環`[1/120, 1/40, 1/60, 1/30]`，按累積輸入秒數截止；超cap壓力另插入一次`0.5`秒delta並單獨分類。不要依frame數相同就聲稱模擬時長相同。

### 5.1 時限先固定，不能失敗後改寬

- F01保持既有20秒輸入期限，另外5秒穩定檢查；本次新診斷也用此期限，不以較長測試掩蓋43人的問題。
- T01/T02短通道先固定180秒輸入總期限；隊長停下後，若入口持續有人等待且出口下一格可用，5秒無任何通道合法提交即輸出 `NO_PASSAGE_PROGRESS`。有外部封路／正在有界交易者另列原因與持續時間，不無限豁免。
- 既有 multi-level 測試1800×0.1秒=180秒期限保留，改走正式每幀入口並逐人驗證；不可拉長原期限換PASS。
- 全部需集合案例均在最後必要出口出清／隊長到goal兩者較晚者起30秒內收隊，且不得突破各案例總期限；這是新增收斂上限，不替換F01的20秒要求。
- D／R微型狀態案例按交易長度、原移動時間與安全drain界線在P0寫死上限；動態外部永遠不離開的情況只驗受限狀態及不變量，不要求不可能的到達。
- wall-clock runner timeout與模擬時間不同。timeout一律是該次run未通過，不是算法確定無路，也不是PASS；先查失敗輸出／代碼／環境再作針對修改，不能原封不動反覆啟動。

### 5.2 獨立計數，不讓 production 自我證明

測試的 `passed` 用每人前後提交格是否跨過fixture指定的有向gate；測試的 `settled` 用已發布slot-set快照及實際唯一占用核對；測試的十列以heading投影到row/column檢查，不能只讀 `_formation_width`。swap的兩人變化同批驗證，避免逐人觀測產生假重疊。

Generated地圖用測試側BFS驗route合法最短與候選出口／集合連通區；保留production選中的route及passage供比對，不能直接信任production的passed結論。重播中每次真正變更slot set／binding／route需留下reason，防止看似收斂其實每秒改終點。

## 6. 檔案修改範圍與執行方式

預期修改集中在：

- `scripts/terrain_lab/terrain_army.gd`：唯一運行時導航／隊形／交易修改owner。
- `scripts/terrain_lab/terrain_lab.gd`：必要HUD可觀測性，不承接模擬寫入。
- `scripts/tests/terrain_lab_army_test.gd`、`terrain_army_formation_smoke_test.gd`、`terrain_army_passage_test.gd`：補強既有測試。
- `scripts/tests/terrain_lab_army_visual_test.gd`、`terrain_lab_army_performance_test.gd`：最終正式視覺／效能驗證。
- 重播與結果：使用現有測試輸出目錄；本輪`.godot-temp`僅是診斷證據，不能成正式測試依賴。

非必要不拆新runtime檔、不改TerrainData.can_step、不更新資產。若確需改其他owner，先報具體caller與不改會失敗的證據，不能擴大成另一輪系統重寫。

驗證依 `godot-runtime-verify` 的 canonical helper，使用真實exit code、隔離可寫環境與獨立logs。以下是單一headless測試的命令形狀，Luna要先確認本機路徑：

```powershell
& 'C:\Users\Nekki\.codex\skills\godot-runtime-verify\scripts\verify_godot.ps1' `
  -ProjectPath (Get-Location) `
  -GodotExecutable 'C:\Users\Nekki\Godot_v4.6.2-stable_mono_win64\Godot_v4.6.2-stable_mono_win64_console.exe' `
  -Mode headless `
  -GodotArguments @('--script', 'res://scripts/tests/terrain_army_passage_test.gd')
```

先editor/check-only看parse，再headless固定回歸，最後visual與performance；編譯成功不等於動作成功，headless成功不等於畫面正確。技能規定一次有界執行，遇錯先處理對應原因再執行新版本，不作無修改重跑。

本專案AGENTS要求任何背景工作都立即設schedule watchdog並主動監看。若當前沒有schedule工具，不可把長測試丟背景後放著；改用工具支援範圍內、helper有硬timeout的前景分段驗證。不要啟動无監看的子程序或多代理。

## 7. 最終交付清單與禁止的結案方式

Luna交付時依P0–P6列 PASS／FAIL／未測，附：

1. 修改檔案、刪掉／統一的舊控制流、仍保留的限制；和修改前基線的實際差異。
2. C01「oracle距離／實走格數」、F01「20秒到位數／穩定5秒」、各T例「99人各口通過／最終落位／秒數」。不可只印單行PASS。
3. 所有test的mode、Godot版本、exit code、耗時、logs／replay路径；timeout與fixture-invalid分開報。
4. 每幀budget上限／觀測最大值、最長eligible等待、sim/drop時間及實測行軍效能；沒有量測的項目明寫未測。
5. 四階段實際畫面與檢視結論；最後畫面必須對應同一seed、命令及格狀態，而非另開平地拍照。
6. 未提交項目、使用者原seed是否重現、可行但仍失败的個案及下一個精確阻擋點。

以下都不能結案：「隊長已到所以完成」「99人同高度」「大家距離≤24」「有任何人移動」「formation_count變99」「width顯示10」「把目標改成目前位置」「測試只跑helper」「把timeout加大後PASS」「卡住後FPS很好」。

## 8. 可直接交給 Luna Max 的實作指令

> 請以 gpt-5.6-luna、reasoning effort=max 實作 `TERRAIN_LAB_ARMY_NAVIGATION_FIX_V3_LUNA_MAX.md`。這次要實際修復隊長非最短路徑與99人卡住，不是再寫計畫。先確認現行TerrainArmy與本文件hash差異並保留使用者所有未提交修改；依P0→P6逐階段完成，每階段附真實測試證據。
>
> 已有兩個基線：無角色U巷獨立BFS=10格、現行_next_step策略=18格；平地正式advance_frame(1/60)跑20秒只有43/99落位。先把反例納入正式測試，修成「先發布最短route再走」及「平地99人真落位」，接著完成交易安全、逐人通道cursor、FOLLOW內陸出口疏散、正式預算及生成／視覺驗收。
>
> 重用TerrainArmy現有BFS、route、slot與pending push，can_step仍是通行權威。不新增平行導航架構、不用原地改desired、取消在途動作、瞬移、強設99/10、增加配額／速度或延長原期限充當修復。不把假完成舊碼當成仍存在；按本文件現行函式缺口逐一核對。
>
> 全程驗100格唯一、owner/claim/lock可追溯、合法相鄰提交、無飢餓；真正完成須隊長到實際goal、99人通過各自必經出口、占滿事前發布的合法slot且穩定5秒。每階段失敗先保留快照再改對應原因；不要無修改重跑Godot，不得留下無watchdog的背景工作。不自動提交或推送Git。最後分列PASS／FAIL／未測、實走最短格數、每口通過／到位數、時間／預算、圖像證據與尚未重現的使用者seed邊界。
