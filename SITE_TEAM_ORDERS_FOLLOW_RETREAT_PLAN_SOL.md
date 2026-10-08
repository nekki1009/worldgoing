# 隊伍跟隨、隨時換陣、撤出 Site 與進場方位 — SOL 修改計畫

日期：2026-09-28，修訂 r2。狀態：**根因查核與施工計畫，尚未實作修正**。

r2 依使用者新規則取代舊版的「可手動／因兵力不利撤退、無出口就持續等待」：**只有士氣崩潰才觸發撤退；可達邊界離圖第一優先，否則退往友方或建築，兩類退路皆無則原地投降待俘。未崩潰時隊長不得下令撤退；軍團長可命令所屬部隊轉進指定位置，轉進不是士氣潰退。** 以下施工、權限、保存及驗收均以本版為準。

本輪只新增這份交接文件與 `output/team_orders_audit_20260928/` 診斷證據，未修改正式遊戲程式。根據目前工作目錄查核；不是只讀 HEAD。SOL 開工時必須重新比對該目錄的 `source_evidence.json`，保留所有既有未提交工作。

## 1. 使用者要求與本次行為契約

1. **目的地不必容納全隊完整陣型。** 能進去的人逐步進去，其餘原隊員沿來路跟隨、排隊或等待合法空間。容量不足不能整單拒絕，也不能刪人、重疊或瞬移。
2. **有效指揮者隨時能改變要求陣型。** 行軍、交戰、追擊、返回、撤退、潰退與暫停都可接受最新選擇；物理變陣沿原步進漸進完成。換陣本身不能取消原戰術任務。仍保留軍籍、指揮權、失能與有效 preset 校驗。
3. **士氣崩潰才觸發撤退，目的地依序為：可達地圖邊界 → 可達友方或建築 → 原地投降待俘。** 邊界有路即優先離圖，不能因友方較近先選友方；友方與建築同為第二層，依可達性／風險／距離選擇，不自行增加兩者先後規則。不得把一次尋路預算耗盡當作無路。
4. **第三隊選北方，就使用北方的部署來源。** 一起部署、只追加第三隊、混合工作／後勤分支都不得悄悄忽略方位或換邊。
5. **未崩潰的隊長不能下令撤退；轉進位置由軍團長要求。** 轉進沿原 MOVE／跟隨／換陣系統執行，是有權限來源的戰术命令，不降低士氣、不設 routed，也不在目的地無路時自動投降。

「選陣已接受」「部分展開」「全隊整陣完成」「轉進」「潰退離圖」「退抵友方／建築」「投降待俘」「已被俘」是不同結果，UI 與測試須分清。第 1 項解除目的地／陣型的全容量門檻，不解除每個在場人物必須有唯一合法實體格的規則。

正式入口仍為 `project.godot:15` → `scenes/terrain_lab/TerrainLab.tscn`。依 `PROJECT_ARCHITECTURE.md:133–169,189–191`，沿用 TerrainArmy、TerrainLab、原 Plan／Grid／Registry、SiteStore 與原渲染。當前正式 Site 沒有 World／Region 旅行；本次撤出保存在原隊伍的場外狀態，不擅自接舊 Travel 或假造下一張地圖。

## 2. 已查明的根因

### 2.1 空間限制來自完整終點指派契約

實際路徑：SiteController 預覽／下令 → TerrainArmy `_preflight_combat_move()` → FormationDestinationPlanner → Registry 取得租約 → CombatMovePlan／Transit → Grid 原子步進。

- `formation_destination_planner.gd:308–314`：固定陣型要求全部模板槽位合法，任一格不合就回 null。
- 同檔 `411–484,547–553`：auto 雖有平台與後方 queue，仍須先找到足夠所有人的固定平台／queue 格；少一個仍失敗。
- `terrain_army.gd:3037–3064`：把以上失敗轉為 `INSUFFICIENT_SPACE`；固定陣型另有整個 footprint 的人物／車輛／在途占格拒絕。
- AI 撤退 `terrain_army.gd:3195–3257` 也使用全員集結規劃並要求 slot map 人數等於有效成員數。

不能只刪容量 return：`formation_destination_planner.gd:1890` 對無 final slot 的成員回 `NO_ACTIVE_PLAN`；`formation_transit_planner.gd:477–486` 未把他們列為 flow；`terrain_army.gd:1435–1446,1533–1548` 又只檢查有槽位的人，可能前排到位就 HOLD 並清掉整條移動計畫。尾隊會被留在原地。

### 2.2 換陣目前是另一個 MOVE 命令

- `terrain_army.gd:3105–3139`：預覽與套用直接拒絕 RETREAT／RETURN／routed，套用另拒絕暫停；其餘狀態最後呼叫 `issue_combat_order(... MOVE ...)`。
- 同檔 `3300–3364`：全槽預檢和租約成功後才提交 `formation_preset_id`；新 MOVE 會清掉攻擊／追擊意圖。因此 ATTACK／PURSUE 換陣實際停止原任務。
- `site_controller.gd:1296–1299` 明示上述限制；不是只有按鈕灰掉。
- `site_store.gd:903,957–981` 把隊伍要求 preset 與物理 deployment preset 綁成相同，固定陣型還要求完整模板。只改 UI 或只提前更新偏好，存檔就可能被判壞檔。
- 現行 CombatOrder 是 HOLD／ATTACK／MOVE／RETREAT／PURSUE／RETURN；ENGAGING 是 MOVE 的接戰覆層，不是另一條軍令。

### 2.3 撤退只有圖內退避／集結，沒有真正出場

- `site_army_ai.gd:292–358`：局部搜尋最深 12 格，挑最多 4 個較安全點；距離足夠時選 HOLD 休整，找不到能容納隊伍的退路也 HOLD。
- 同檔 `197–211` 以低 HP、低可戰比例、疲勞>=80、士氣<25、缺彈或兵力劣勢引發 recovering／withdraw；這些都不是使用者新指定的唯一「士氣崩潰」門檻，必須移除其直接撤退權。
- `terrain_army.gd:3429–3431`：手動 RETREAT 平移現有 combat_slots；AI 預檢則準備全員集結槽位。`3801–3804` 抵達後回 HOLD。
- `site_controller.gd:4275–4304`：供養／士氣潰退另有512格、深度16的局部安全格搜尋，直接平移槽位；這是第三條必须一起修的撤退入口。
- `terrain_army.gd:11261–11299` 已有尋找可達邊界開口的舊非戰鬥行軍邏輯，可重用純候選／距離部分；`Command.MOVE_TO_EDGE` 本身只是到邊界，不能直接冒充戰鬥撤出。
- 目前没有完整的軍隊 Site 退場提交。`clear_army()` 是清測試隊伍，會走物資／供養清理，不是撤退。

**不要直接把正常撤出寫成 `departed=true`。** `terrain_army.gd:2497–2500` 的 `member_gone()` 將 departed 視為永久離去，`2877–2882` 會改正式隊長，`2862–2865` 影響幹部，`6678–6680` 拒絕 departed 正式隊長快照，SiteStore 也會影響披風任職資格。`present` 則已有指揮在場語意，也不能當作一般可見性旗標。

### 2.4 北方第三隊落在西方：已由正式入口重現

UI 的 enum／字串沒有對錯：`site_controller.gd:632–637,801–803` 正確傳入 `third_entry="north"`。

主因有兩條：

1. **追加第三隊漏掉方位。** `site_controller.gd:830–831` → `terrain_lab.gd:add_melee_trial_team():2671`。`_trial_side_settings():2624–2669` 沒保留 entry，追加分支 `2700–2733` 從原敵對隊伍周圍找接戰位置，沒有讀 `third_entry`。原我方在西邊，第三隊就可能生在西邊。
2. **一起部署仍有越界 fallback。** `_find_directional_team_formation():2340` 的 `2408–2416` 找不到指定區域後改搜全圖。上層 `find_melee_trial_layout():2493–2499` 只檢查人數，不重查方向。指定區域內 BFS 也只約束 seed、不約束全部隊員或真正入口。第二輪還會放棄與目標連通性。

另外，`start_melee_trial():2593–2600` 有任一支援隊就走 `_independent_trial_formations()`；該分支依營地排序，同樣不讀各隊 entry。舊 `_directional_third_trial_formation():2297` 沒有正式 caller，修它不會修好 UI。

**實測，未改正式地形：** `TERRACED_HIGHLAND, seed=12345`，100×100；地形 fingerprint `c8a3021229df7f5f4324c39ee75fada205999efd74ec4f2cb13b481f12bc3367`。

- 一起部署 100／100／100，西／東／北：第三隊 seed `(49,2)`，範圍 `(42,0)..(57,9)`，正確在北侧。
- 原 UI handlers 先部署西／東各 100，再按「只追加第三隊」100 人：UI 資料仍為 north、標籤仍為北；實際第三隊 seed **`(0,56)`**，範圍 `(0,53)..(9,69)`，落在西側。
- 另用記憶體內合成地形隔離 fallback：北區無可用地，要求 north 最後得到 `(1,17)` 的西側位置。此例是合成診斷，不冒稱使用者原圖。

既有 `site_battle_spawn_direction_test.gd:59–65` 第三隊只測 50 人且只驗 seed.y < 45%；西北角也能通過。後段 UI 部署未啟用第三隊，沒有追加按鈕的方向驗收。測試輸出雖寫 true edge deployment，實際並未驗證逐員跨界進場。

### 2.5 r2 新查核：士氣、軍團長與投降是不同資料責任

- `site_sustain.gd:276–280,285–300` 已由原 sustain 狀態管理 morale／routed；目前 morale<=20 進入崩潰，安全且休整滿1800遊戲秒、morale>=50 才解除。新計畫沿用此唯一判斷與現有數值，不另用 AI 平均士氣<25 或兵力比造第二個崩潰來源。
- `site_controller.gd:4271–4273` 的 `team_is_routed()`／Army `is_sustain_routed()` 是現成讀取接點；`4220–4228` 是崩潰觸發與持續處理入口。即使 tactical AI 關閉，真實士氣崩潰仍要執行逃離／避難／投降流程。
- 目前相關正式程式只有本隊正式／代理指揮權，及 `equipment_nations` 的國家軍事首長配裝權；未找到可直接用的「軍團長→所屬隊伍」轉進授權模型。兩者不能混同，也不能把 faction_id、玩家控制或測試選隊當作軍團長授權。
- 現有 `SitePersonActions.begin_capture()`、SiteCaptivitySupply、SiteCaptiveEscort 可重用實際拘束、看守、供餐與押送流程；「已投降」需與原 `captive` 分開，不能無拘押者就建立 captivity 關係，也不能把清醒投降者強制寫成 KO 來通過舊抓捕守衛。
- `site_person_actions.gd:671–688` 目前只接受 KO 抓捕目標，`521–543` 才提交原拘束／實物封存／供養交易；r2 延伸前者接受清醒待俘，保留後者的交易和最終重查。
- `site_runtime.gd:19–38,668–701` 的建設定義與實體入口、`site_store.gd:587–600` 的完成建物驗證可供後備目的地使用；`terrain_army.gd:9995–10009,10174–10184` 已區分 deferred／capped／exhausted／success，可用來避免搜尋中途誤判投降。

## 3. 固定保留的擁有者與安全界線

- TerrainArmy 原 combat_units、person_id、軍籍、正式／代理指揮、原裝備 holder、共享疲勞仍唯一；禁止為跟隨或離場複製人物。
- `cells` 是已完成的實體位置；`moving_to/move_progress` 是已承諾步進。原 0.38 秒、曲線、在途 batch、Grid Propose／Resolve／Commit 不變。
- CombatDeploymentPlan 管實際終點指派；CombatMovePlan／FormationTransitPlanner 管路線、軟目標與跟隨；Registry 只管真正取得的終點租約。
- 計畫替換保持預檢→原子換租約→提交；失敗保留原物理計畫與已承諾步。選陣意圖可先接受，但不能偽造物理提交成功。
- 原生 C++ 仍是同一份原資料的派生計算。新語意必須在 GD／native 一致，禁止永久關閉 native 作為完成條件。
- 人物／車輛／懸崖／建物不因空間不足被刪除、推開或改地形。非戰鬥隊的作業、車輛掃掠與玩家自主操作仍沿原守衛。

## 4. SOL 施工順序

### P0 — 保存基線，先留下會抓到舊錯誤的檢查

1. 讀本文件、PROJECT_ARCHITECTURE 與現行相關函式；比對 `source_evidence.json`。若檔案已變，重新定位而不套用舊行號覆蓋。
2. 保存原命令、人物 ID／位置／在途步、租約與存檔樣本。延伸原測試，將北方追加與部分容量列為新期待的 regression。
3. 下方 audit probe 是重現舊行為；它的 PASS 表示診斷完成，**不是修復驗收**。修正後的測試應斷言北方來源、不能保留「得到西側」的舊期待。

### P1 — 統一方位資料與所有部署入口

修改重心：`terrain_lab.gd`、必要的 `site_controller.gd`、原方向測試。

1. `_trial_side_settings()` 對每隊統一解析 entry；UI 使用固定 ID metadata 或既有穩定字串。未指定舊 API 才維持明確 legacy 行為；無效非空字串不能悄悄當未指定。
2. 一起部署、只追加第三隊與支援分支使用同一指定方位搜尋接點，帶入已存在人物、移動目的格、車輛、租約、營地通道等阻擋。追加不得移動／清空既有兩隊。
3. 指定方位是硬限制。刪除「指定區域失敗就全圖找」的行為；不得為了接敵距離把北方改成西方，也不得回報北方但使用西側 seed。
4. 區分「來源邊」和「面向敵人」：部署／入場來源留在北邊，初始 facing 可依實際敵方位置決定。方向不能由隊伍編號或 faction 推回。
5. 方位搜尋以該邊可達開口及向內連通格作穩定排序；保持地形通行／車輛限制，不只測地圖半邊或隊伍平均座標。角落應有明確來源邊，不能用模糊平均位置判斷。
6. 同側窄入口不必有一塊完整 N 人模板；沿原連通搜尋及本次跟隨契約向內排列。若整個合法來源區沒有足夠可安置的實體格，顯示真實原因／等待，不可改邊或疊人。這一條不另造場外複製名冊；若要讓尚未進場的原人物逐員排入，必須在原 Army 的 Site 在場狀態明確表示「待進場」，並與 P4 的「已撤出」區分後一同驗收，不能用 INVALID_CELL 偽造已部署。
7. 明確座標與方向同時提供時，沿既有明確座標優先規則且 UI 要顯示座標模式；自動方位模式則清除舊手動座標，不可悄悄被殘留值覆寫。

完成條件：正式地形追加第三隊走北方來源；四方位、100 人、近戰／弓／弩、支援混合、同陣營均不漏傳方向。北邊無路時絕不從西邊出現。

### P2 — 部分展開與真實尾隊跟隨

修改重心：DestinationPlanner、DeploymentPlan、TransitPlanner、TerrainArmy；同批修改 SiteStore 與 native readers。

1. 在原 CombatDeploymentPlan 增加明確 `following_member_ids`（名稱可依現有風格調整）。`member_slot_map/member_role_map` 仍只保存有真正終點的人，不塞 INVALID_CELL，也不把遺漏資料默認成 follower。
2. 固定陣型保留要求 preset／anchor／facing／模板規模；實際 platform 是合法且可達的模板子集。auto 可保留既有合法 queue，但不再要求預建 queue 湊齊全隊才能接令。
3. 部分模板格被占用時分出 followers；anchor 或整條必要路徑真正不可達仍誠實拒絕或等待原有可重試條件。預覽與下令使用同一結果，預覽不取租約。
4. Followers 納入原 Transit flow，沿已驗證 macro cross-sections、原間距與 `pre_route_staging_slots` 跟進；短路徑排不下時保留原合法尾部位置。目標仍使用原 `kind="transit"`，另附 FOLLOW／WAIT_SPACE 原因，避免漏掉既有批次／進度判斷。
5. 目標 resolver 在 final-slot 缺失拒絕前辨認明確 followers；Grid 決定每一步能否真的走。已落位前排仍是實體阻擋，不能穿人。
6. 前排到位不代表全隊整陣完成。存在 followers 時保留必要的 MovePlan／跟隨更新，顯示「已展開 X、跟隨／待空間 Y」。不能因只遍歷 slot map 就 HOLD 清計畫。
7. 空間釋出時，在原軍令節拍有界重查，透過 Registry 原子取得真槽位，才將 follower 轉為 assigned。禁止每幀全隊／全圖重算。
8. 隊首已站定且下一格確實無合法空間屬 WAIT_SPACE，不觸發原 12 秒擁塞取消。若已有可達合法待走目標卻長期不進展，仍由原 Recovery 處理；不能全部不動都標正常等待。
9. 下一次 MOVE、換陣、撤退取原有效名冊，不能只取有 slot 的人。同步 `remove_member()`、KO／甦醒／死亡／除隊處理；無槽位 follower 的 KO 不得偽造 absent slot。
10. 每個命令成員必須有可驗證去向：assigned、following、暫時失能／缺席等互斥且完整。可由原人物狀態重建的失能集合不另外造第二份名冊；存檔不得因 map 漏人而默默忽略。

Native 必改接點：`native/army_idle/movement_core.inc:108–151` 的無 slot 判斷、`movement_transit.inc:191–224` 的 flow 選取。原 `movement_projection.inc` 的名冊／中心計算亦須配合 P4 過濾真正不在場者。

完成條件：100 人進只有 1／10／49 格可展開的小平台，且預建 queue 放不下所有人仍接令；尾隊真實跟進／等空間；原 ID 守恆、無重疊、無假抵達。開闊地原百人完整 exact arrival 繼續通過。

### P3 — 選陣意圖獨立，保持原戰術任務

1. 原 `TerrainArmy.formation_preset_id` 明確作為「要求陣型」；原 DeploymentPlan preset 表示「目前已提交的幾何」。避免再加一個 formation manager。
2. `issue_formation_change()` 先驗隊伍／指揮／preset，接受最新意圖；不再一律呼叫 MOVE。未知 preset、失效 requester、非戰鬥隊仍拒絕且不改 AI／租約。
3. 暫停時可提交選陣意圖，場景時間、原物理步與計畫執行不前進；恢復時重查指揮權和地形後執行。保留的是陣型選擇，不是偷偷跑一個 simulation tick。
4. HOLD：可走原整隊移動；MOVE：保留目的地、方向與已承諾步，只改未執行安排。ENGAGING：立即接受意圖，原接觸約束仍優先，解除接觸後自動續用最新陣型。
5. ATTACK／PURSUE：不清攻擊／追擊目標、origin、倒數；安全可動成員沿原 combat_slots／路徑漸進重排。既有射手安全距離、接戰與包圍先於整陣，不能加第二份目標擁有者。
6. RETREAT／RETURN／ROUT：接受新陣型但保留原撤退優先序／返回任務；通過狹道仍以跟隨為先，不停下等待完整陣型，不解除 routed。RETURN 是追擊返回，不能誤改成離圖。投降待俘可保存陣型偏好，但不得因換陣恢复攻擊或移動逃跑；已被俘仍遵原權限拒絕下令。
7. 抽出既有 MOVE 預檢／租約／計畫提交的最小共用段；同一 Army 按當前軍令安排物理重排，不複製整套 `issue_combat_order()`。新物理計畫未成功時保留舊計畫，只顯示要求待實現。
8. 連續 A→B→C 只保留最新 C；同一已實現 preset no-op。成功人工選陣沿既有手動接管政策關閉該隊 AI，但不能取消崩潰處理、投降待俘或上級已下達的轉進；無效／無權操作不得關 AI。追擊原任務也保持。
9. UI 顯示要求陣型、實際形態、進度／等待原因。移除「撤退期間不能換陣」和「換陣必停接敵」舊文案，不能只改文案而不改 owner。

等待意圖必須能自行喚醒：在原 Army 命令節拍的 HOLD 早退／MOVE gate 之前做有界 reconcile，讓 coordinator 的 idle 判斷將尚未實現的陣型意圖視為待處理工作。若無現成欄位可無歧義區分「從未要求整隊」與「已接受但沒有物理計畫」，只在原 Army 增加一個可保存的 pending 標記；不另造命令佇列。無 plan 的 HOLD、空間恢復、接觸解除、暫停恢復都必須能自動續做，不能等待下一次使用者按鍵。

實際 callers：`site_controller.gd:_apply_formation_change()` 的 trial/test 與 `terrain_lab.gd:issue_player_formation_change()` 的 player 都須覆蓋。原 `_translate_combat_slots()` 的 RETREAT、PURSUE、RETURN、供養潰退四條來源須統一優先順序。

### P4 — 士氣觸發、三級退路、投降，以及軍團長轉進

#### P4-A：唯一崩潰觸發與軍團長權限

1. 只由原 SiteSustain 的 `routed` 轉態開始或延續撤退。低 HP、傷亡、疲勞、缺彈、兵力比可以影響原士氣計算／戰鬥選擇，但不得跳過崩潰判斷直接呼叫 RETREAT；本輪不另改士氣公式或門檻。AI 的 recovering 不得被當作 routed 的別名。
2. 士氣未崩潰時，隊長／代理隊長／隊伍 AI 的直接 RETREAT 一律在 Army 正式入口拒絕，且保留原令、位置、租約與 AI 開關。UI 隱藏／停用原隊長「撤退」操作並說明原因；不能只擋按鈕而留下 API／測試直通後門。崩潰後由原 owner 自動執行，不依賴隊長另按一次或仍然清醒，也不因 AI 停用而停止。
3. 軍團長可向**所屬隊伍**下「轉進至所選位置」。沿原 TerrainData.site 的既有持久資料邊界補最小指揮關係記錄（軍團ID、原軍團長person_id、所屬team_id引用），SiteStore 驗證原人／隊伍存在、從屬關係及唯一有效任職；Army／Lab 只查此關係，不複製人物或新建軍團模擬系統。真實遊戲任職不足的測試場景須由明示設定選原人物與隊伍，不能自動把每隊隊長、玩家、國家配裝首長或同勢力任何人升為軍團長。
4. 轉進命令查當前原下令者的軍團長資格、可行動／未被俘狀態、該隊是否隸屬及目前未崩潰；命令經原 MOVE、Plan、Registry、Grid 執行，保存下令者／受令隊伍的必要來源。這不是先假冒受令隊長再調既有入口，也不是全域放寬 `requester==current_commander`。普通隊內行軍／整隊的既有範圍不擴張，但新「轉進」操作不可藉命名為 MOVE 繞過上級權限。
5. 轉進不設 routed／surrender、不消失出圖，目的地不可達則失敗或按原移動等待；**絕不因轉進無路而投降**。已接受的上級轉進不能被本隊 AI 下一輪反向下令覆寫；沿原人工接管機制保留它。途中原士氣真的崩潰時，先安全完成已承諾步，再由崩潰流程接管；軍團長也不能用轉進強行清除 routed 或投降待俘。

#### P4-B：嚴格三級目的地與可達性

1. **第一層，離圖。** 重用 `_choose_edge_targets()` 純邊界枚舉／可達距離，查目前連通區可走到的真正邊界開口。有可達出口即選此層，不能因較近的友方／建築或12格局部搜尋界線而跳到第二層；同層再依威脅、路長與穩定順序挑選。合法繞路不可要求每一步都更遠離敵人。
2. **第二層，退往友方或建築。** 只有邊界被證實無可達退路時才查此層。友方候選沿原 faction／敵友規則，排除自己、已出場、被俘、投降或同樣潰退而不能接應的對象；朝其可達鄰近合法格靠攏，不占對方人物格。建築取原 `site.features` 的完成建物及其合法入口／相鄰可通行格，不走進 solid footprint；排除施工中、被毀／移除、敵方占據或不具安全落腳點的候選。現有建物無 faction／owner 欄位，不能虛構「友方建物」所有權，也不因這次任務另造領地系統。友方／建築在此層同級，按可用性、威脅及實際路程選擇。
3. 退抵友方／建築後顯示「潰退避難／待整補」，仍在圖內、持續占格與保存；不設 site_exited、不自動捕俘、不當全隊恢復戰力。沿原 Sustain 安全、休整與士氣恢復條件解除 routed，解除後只守位待新令，不自動接敵。不能只因抵達就把士氣寫回100。
4. **第三層，原地投降待俘。** 邊界與友方／建築兩層都已完成有效可達性判斷、確無可用退路時提交投降；不可無限 HOLD 自衛或不停搜尋。友方／建築不是任意安全空格，沒有合格第二層目標就不能臨時用空地替代。
5. 有界搜尋的 RUNNING／預算耗盡、暫態 Grid 衝突、首步有人尚在移動，都不等於 UNREACHABLE。延續原搜尋工作／原子步，顯示「正在判斷退路／等待通行」；但確認封死後必须進下一層，不能用 WAIT_SPACE 永久逃避投降。重查地形／目標移動／占據變化時作廢過期的無路結論。
6. 友方移動、建築失效或路線中斷時，對仍在場人員由第一層重新判斷；已退出者不拉回。散開且被分隔的成員按各自實際可達區處理，不能只看隊長有路便宣稱每個人都能逃，也不能因尾隊被截斷讓已可撤出的前隊原地投降。重用原路徑／地形連通查詢與暫態結果，不建立新的分隊人物 owner。
7. 所有目的地都沿 P2 的部分展開／跟隨，不要求友方、建築門口或出口容納完整全隊陣型。已有可達窄路就應排隊，不能以容量不足假判無路而投降。

威脅高、路長或敵軍較強本身只是同層排序成本，不等同不存在退路；不能用固定敵距圈把所有實際可通過的路刪掉再宣稱「都沒得撤」。只有原通行／合法落腳點與當前真實阻斷等可驗證條件才能得出不可達；搜尋分類直接保留原 deferred／capped／exhausted／success 的差別。

建築候選先從原 FEATURES 明確選建物種類：住宅、鹽場／磚瓦窯／炭窯及冶煉／鐵匠／製革／織布作坊等完成設施的合法外部入口；原完成防禦陣地亦可作掩護位置。道路、整地、農田與一段木柵不因是 feature／solid 就冒充可避難建築。這是原目標類型的明確篩選，不新增建築、防護加成或室內空間。

#### P4-C：離圖分支的逐員提交與資料保全

1. 邊界分支不要求 N 個終點槽位，利用原跟隨順序逐員通過出口；無可達邊界則轉 P4-B 第二／第三層，不保留舊版的永久出口等待政策。
2. 已承諾原 MOVE／RETREAT pair 或 vacancy chain 先按原 barrier 完成；只有成員到达指定合法邊緣、無未完成物理步且符合行動條件，才在原 Army 做一次離場提交。不可由距邊界若干格或安全距離直接消失。
3. 在原人物列增加 **Site 離場狀態**（最小為 `site_exited`），與永久 `departed`、指揮 `present` 分開。離場保留 person_id、member、正式幹部任職、身體、裝備、貨物與 holder；不呼叫 clear、不丟物到地面、不造第二隊副本。
4. 原 Army 保存本次出口／撤出階段等最低必要資料；已離場人物 `cell` 可保留最後合法邊緣格作歷史位置，必須從場內占格排除，不能寫越界格繞過原 validator。人員進度以原列狀態計算，UI 計數不另存為真相。
5. 離場一次釋放該人的占格／預約／終點租約、跟隨指派、接戰／追擊／救助引用，取消不再合法的場內作業。原整隊撤出命令保留給尚在場人員；隊長先出場只能失去場內即時指揮，不能被視為死亡或永久卸任。
6. 全面接入場內資格讀取：GD／native 有效名冊與中心、AI 摘要、敵人／彈體／交鋒查詢、點選、占格、Sprite／MultiMesh／女性原呈現者、供養／訓練／救助。`_sync_visual_positions():13697` 目前會設 visible=true，不能只在提交當下 hide 一次。
7. `member_gone()` 保持永久離隊語意；原正式幹部／披風资格校驗按軍籍與任職，場內 `command_eligible()` 按在場。不得為讓離場存讀通過就卸掉裝備或重派正式隊長。
8. 有傷員／起身者不能自行瞬移出場；顯示「已撤出 X、在場 Y、失能 Z」。醒來且仍受撤退命令時沿原行動流程續撤。玩家／受控人物仍自主，不由軍令傳送，未主動離開前不得宣稱全隊已退出。
9. 動態堵路依 P4-B 區分尚待解決的占格與已確認無路；後者必須轉友方／建築或投降。已撤出者不因新軍令／載入而重新冒出。
10. 崩潰撤退不能因敵距達12格或 AI 的疲勞恢復就改 HOLD 重新進攻；移除局部 RETREAT 全容量要求。只有原 Sustain 真正解除 routed 才進守位待令；若已投降則仍按 P4-D 保持待俘，不因士氣回升自行恢復戰鬥。
11. 本輪只撤離當前 Site。沒有下一張地圖的正式接點時保留同一 Army 的場外資料，不接歷史 World／Travel、不重新部署到另一邊。既有最多三隊／300 NPC 保存界線不因退場而偷偷清掉名冊騰位。

具體接線要點：

- 遠程退路使用原 `FormationTransitPlanner.build_macro_path()` 與分段目標；`_common_order_route_step():10254–10290` 的256格局部搜尋不足以保證跨整張山地，不可只換一個遠端 goal 就宣稱可走。
- 最低必要退路資料沿原 Army snapshot 記錄版本、原因=`morale_collapse`、目的類別=`edge/ally/building/surrender` 及原目標ID／方向；可用原 `combat_goal` 表達的格位不另存第二份。規劃中和已確認無路必須可區分；計數、候選、路徑快取與可達性證明在載入後重建，不作第二套永久狀態。採 `retreat_resolution` 等涵蓋三層的名稱，不能只存 `retreat_exit` 而丟失避難／投降。
- 新旗標須接 `terrain_army.gd:81–85,4718` hot columns 與 `native/army_idle/army_idle.cpp` 的欄位／flags／restore／materialize；原 `movement_core.inc:77–84` 的 can-act、`movement_projection.inc:32–40` 的名冊／中心與原生渲染須同語意。
- `terrain_army_batch_view.gd:203–239`、原 retained render 與原女性 presenter 都需測真正退場當幀。不能只測 Sprite.hide 或角色數量。
- `TerrainLab._combat_target():2990–3002` 同時用於原人物／物資資料查詢，不能粗暴讓 exited ID 全域查不到。保留原 owner 查找，在攻擊／點選／救助／搜刮／配裝等空間操作處拒絕場外目標。
- 玩家自願離場採原 SiteController 中明確的「離開此地圖」操作，只在受控原 Actor 已到合法出口且無未完成動作時可提交；團隊命令不代按。`PLAYER_MEMBER` 引用原 TerrainTestCharacter，並不在 combat_units，因此 Actor 原快照／SiteStore／可控性／顯示也要保存相同 Site 離場語意。退出後停用該人的場內操作，保留當前 Site 畫面與退出結果；不自動換控制者、不建立另一個玩家、不假切到未接好的 World。
- `SiteController._team_members()` 與 `SiteCaptivitySupply._original_members/_all_members()` 是供養／軍籍關係，不可為顯示人數刪 exited ID；`_team_safe():4139–4145` 等現場安全查詢則要排除場外歷史 cell。`advance_team_sustain():4220–4233` 只能按原真實 regroup 條件解除潰退、轉守位，不可覆寫投降待俘／已俘狀態；不得從 AI 自行偽造 regrouped。

Site 供養／共享疲勞須沿原 owner 明確處理：部分撤出不能生成第二份 fatigue pool、反覆按剩餘人數加權丟失總量、重複吃糧或把離場者當地圖工人。完成撤出時結清原場內已發生成本，保存原值；未實作的場外模擬不能持續產出工作成果。

#### P4-D：投降待俘不等於已被俘

1. 在原 Army 人物列／Actor 原身體狀態保存最小 `surrender_pending`（或等義明確狀態），與 KO、member、departed、site_exited、captive 分開。只標記真正仍在場、尚未被俘的原人物；死亡不叫投降，KO者不被治好／搬動，醒來仍受已確立的待俘限制。
2. 決定投降後停止新增攻擊、自衛還擊、追擊、走路、逃逸與戰術換令；收束已承諾的物理批次和已發生的攻擊／彈體效果，不能倒轉時間或讓人物因設旗標獲得無敵。就地保留唯一占格、身體、軍籍、裝備、貨物和可見的「投降待俘」呈現，不移到集合點、不掉落所有物品、不直接消失。
3. 不立即寫 `captive=true`、不憑最近敵軍指定拘押者、不自動更換供養或裝備 holder。實際敵方接近後，沿 SitePersonActions 原抓捕預檢／耗時／接觸／最終重查／提交，才建立原 captivity 關係；原看守容量、距離、供養、封存與押送規則保持。清醒且待俘也應成為合法抓捕目標，不能先製造 KO。
4. 新的待俘狀態要接 GD／native 戰鬥／AI／移動資格與指揮、目標查詢、UI、渲染、Actor、SiteStore。不要把「不能戰鬥／自主移動」誤作「人物不存在或不能被原抓捕流程查到」。投降者保持可受擊，不額外發明攻擊免疫。
5. 抓捕交易成功才清待俘並成為 captive；失敗、敵方離開、看守容量滿或無敵人來接收都保留待俘，不憑空建立俘虜。兩名捕俘者同時操作仍以原版本／最終守衛保證一次提交，人與物不重複。
6. 士氣回升、道路之後打開、AI切換、換陣、轉進、存讀都不能默默撤銷已成立的投降。解除投降／受降拒絕等額外玩法未由本次要求定義，不自行補造；既有真正被俘後的釋放、贖回、逃脫仍沿原流程。

### P5 — 同批完成保存版本、相容與呈現

不能等「功能做完後」才想到存讀；P2／P3／P4 每個可用階段要同批更新原 serialization 與 validation。

- 建議 Deployment shape version 3：v1／v2 保留原解釋，followers 為空；v3 驗模板合法子集、assigned／following／absence 身份、唯一 ID、有效槽位、合法租約、原物理步。
- v3 用 deployment 自己的 preset 驗物理幾何，獨立驗隊伍要求 preset。舊版矛盾的 plan/team preset 仍拒絕，不能因新功能全面放寬舊存檔檢查。
- 「新意圖搭配舊物理計畫」另由原 Army 的明確 `formation_intent_version=1` 辨識：載入舊 v1/v2 plan B 後接受 C，可保留 B 的版本、完整幾何／租約／在途步，保存時標示新意圖版本，以 B 自己的規則驗幾何、以新欄位驗 C。未標新版意圖的舊矛盾快照仍拒絕；不可單純把 legacy plan 改成v3而失去原幾何解釋。此版本也適用没有 deployment 但已有 pending 意圖的狀態。
- Army 快照加可識別的版本／欄位規則，舊檔缺 Site 離場欄位預設未離場；非法型別、非出口位置卻 exited、exited 還有在途 claim／attack／救助、重複人或物等必須拒絕並保留原檔。
- 原身體 schema 2 的 KO 遊戲秒語意保持不變，退路決策／軍團命令來源使用自己的小版本。舊 RETREAT 檔先保留已承諾步；原 routed 為真才遷移為三級撤退；未崩潰且沒有合法上級轉進來源的舊「手動／AI退避」收束至安全守位待新令，不偽造士氣崩潰或軍團長授權。舊檔沒有軍團關係則預設未授權，不自動任命。
- 保存原軍團長任職／隊伍從屬與已接受轉進來源；存讀重查一致性，拒絕偽造issuer、錯誤從屬、已死亡／被俘者新下令等不合法來源。有效既有命令的存讀／執行與下新命令的資格分清，不因歷史下令者後來失能便抹除人物或未完物理步。
- 保存三級目的類型、避難目標ID與各原人物 surrender_pending；舊檔缺待俘欄位預設false。投降待俘與已俘／已出場互斥；不得有無captor的假captivity。投降剛成立時可仍有**先前已承諾**的合法步進／批次，存讀必須完成同一步後原地待俘，不能為要求靜止而提前釋放預約或拒絕這種有效快照。
- 已撤出正式隊長和原合法披風能 roundtrip，場內代理資格重新查核；不能複用 `departed` 的永久離隊校驗。
- 保存「要求 C、物理仍 B」「前排到位尾隊跟隨」「軍團轉進」「出口排隊」「退往友方／建築」「原地待俘」「逐員受俘」「部分人已出場」「全體已出場」；載入不重新放人、不恢復舊 AI 進攻，無路證明按當前地形重查，已成立的投降不因重查自動撤銷。
- 全隊離場仍由原 `_capture_positions()` 保存 Army snapshot；不能關掉 `combat_enabled` 或以沒有可見人物為由漏存整隊。已離場不是待入場，不能載入時放回入口。
- Grid／Registry／native soft targets／渲染列只從原狀態重建，不新增第二份位置、人物、物品或存檔 owner。原受交戰限制不能為了測試而放寬。

## 5. 必跑驗收與舊測試修訂

### A. 方位（真 UI handler 加座標證據）

- 正式 seed 12345：西／東各100，第三隊北100，一起部署和只追加兩路都記錄原設定、來源邊、首格、全員範圍；追加前後原兩隊位置／人／物不變。
- 四個方向輪換、第三隊50／100、三種兵種、第三隊各 faction、混合支援隊；無合法指定側開口不能默默改側。
- 使用 `site_battle_spawn_direction_test.gd` 延伸，不能只驗 label、seed 位於上半圖或兩隊配置。

### B. 容量／跟隨

- 100 人、平台1／10／49格、短進路、一格通道、90°彎；包括目前連平台＋固定 queue 都放不下的情況。
- 實體腳步／到達順序與全員 ID 守恆；前排站定後尾部繼續，等待>12秒不誤取消，堵路解除自動續走。
- 玩家、車輛、另一隊租約、地形修訂、follower KO／醒來／死亡／除隊；再下 MOVE／換陣／撤退時尾隊全部仍受原令。
- 修改 `combat_formation_shape_test.gd:148` 的「一格受阻整單拒絕」舊期待；保留開闊地 hook／六陣完整幾何驗收。
- `combat_movement_exact_capacity_test.gd` 的60+40／49+51以及既有百人完整到達仍精確通過，不能改成部分到位即 PASS。

### C. 隨時換陣

- HOLD、MOVE途中、MOVE+ENGAGING、ATTACK、PURSUE、RETREAT、RETURN、ROUT、暫停；每例驗意圖即時接受與原命令／目標／timer 保持，以及真正跨格重排或明確可恢復的等待。
- A→B→C、同 preset、失效 requester、指揮 KO／代理、普通兵 KO；失敗命令不改 AI，成功人工意圖沿既有接管規則只停該隊 AI。
- HOLD 原本無 plan、全部展開空間暫被擋時先接受選陣；移走阻擋後不按第二次即可開始真實整隊。暫停接受後恢復也要自動啟動。載入 v1/v2 的 B 計畫後接受 C、暫保 B，必須成功 roundtrip 並續行。
- 原 `combat_formation_switch_test.gd`、pairwise／100_chain／store_matrix、`site_tactical_ai_state_test.gd` 延伸；不得僅新增 UI 選項即宣稱通過。

### D. 士氣、轉進、三級撤退、投降／資料完整

- 士氣未崩潰，即使疲勞80以上、缺彈、低HP、傷亡或敵軍較多，隊長／AI也不自行RETREAT；直接呼叫正式API同樣拒絕。士氣崩潰由原Sustain觸發，AI開關及隊長失能不阻止流程。
- 合法軍團長對所屬隊伍轉進成功，隊長／假冒下令者／同勢力非上級／非所屬隊伍拒絕；轉進無路不投降、不設routed。途中士氣真的崩潰才轉三級撤退；換陣與存讀保留原上級命令來源。
- 邊界可達但比友方／建物更遠，仍選邊界；需要超過512格搜尋或多幀規劃也不能提前降級。單格／彎道出口、繞山、暫態堵口照原步進完成，不靠手點有效目標才自動撤退。
- 全邊封閉但友軍可達→退往友軍；只有完成建築可達→退往入口／周邊；两者都可達按同層排序。敵占建物、木柵、施工建物、正在潰逃的友隊不能假冒可用接應處。
- 邊界與友方／建物都不可達→原地投降待俘；原ID／物品／占格仍在，captive=false且尚無captivity關係。區域被分隔時一部分可退出、一部分避難／待俘，不能以隊長單點結果概括全隊。
- 清醒待俘者可經原拘束耗時／接觸／看守容量正式被俘；抓捕失敗／看守滿／無人接收保持待俘。並發抓捕不重複轉人物或封物；士氣恢復、換陣、普通命令、轉進及存讀都不令待俘者復戰。
- 真正未完成的搜尋／Grid臨時衝突不投降，真正窮盡退路則不得永久自衛等待；友方移動／建物失效／地形變更會重查目標。RETURN仍是追擊返回。
- 在原0.38秒途中換令，原子 pair／chain 不斷裂；不能同一人既場內占格又 exited。
- 正式隊長先退出、男女幹部／普通兵顯示、披風／染色、彈藥／貨物 holder、疲勞／供餐、KO留場與玩家自主；全員／全物守恆。
- UI 不再選得到退出者，敵軍／彈體不再命中退出者，空出的邊界格可被下一人合法使用；全隊退出後仍能保存原資料。
- `site_tactical_ai_retreat_test.gd:116,218–267` 目前以圖內 destinations 全到且 HOLD 為完成，須按新撤出契約重寫期望，保留物理合法、失敗回滾、中途存讀檢查。
- `site_tactical_ai_behavior_test.gd:271–274,710–712` 移除「疲勞／缺箭／兵力比直接撤退」期待，分開測未崩潰不撤與真崩潰三級處理。補箭仍用合法在場隊伍，不能對已退出／投降者隔空補給；退抵友方／建築的整補依原規則測。
- `site_tactical_ai_ui_test.gd:79–80` 及原手動撤退矩陣改測「未崩潰隊長無RETREAT權」「崩潰不需按鍵即處理」「軍團長有權轉進、無權者拒絕且不改AI」。無邊界出口不再一概拒絕，而是第二／第三層的正常分支。
- 延伸 `site_person_actions_test.gd`、`site_captivity_supply_test.gd` 與原Actor／Army存讀測試，驗清醒投降抓捕、拘束前後唯一holder與供養、在途投降存讀、四人看守容量、封存原物；保留舊KO抓捕／釋放／押送回歸。
- `combat_movement_retreat_pair_swap_test.gd`、`combat_movement_retreat_pair_store_resume_test.gd`、`combat_movement_supply_rout_transition_test.gd` 保留原子步與中斷存讀守衛；將新出口規劃與原子步 fixture 分清，不能為保留舊目標而繞過新正式命令。

### E. 存讀／native／正式畫面

- 舊 v1／v2、部分陣型新版、要求與實際不同、尾隊 KO、轉進權限、出口排隊、友方／建物避難、待俘／實際捕俘、部分／全隊已撤出 roundtrip；破壞身份、權限來源、槽位、租約、在場／待俘旗標各自拒絕。
- GD／native on/off 比對目標、有效名冊、占格、in-flight、跟隨進度與退出結果；延伸 `combat_movement_native_transit_parity_test.gd` 等既有比較入口。
- 使用原 canonical verifier：先 bounded headless contracts，再 editor parse/import，再正式 TerrainLab GPU 圖像序列。正式畫面至少包含北方追加、百人窄道跟隨、戰鬥中換陣、軍團長轉進、士氣崩潰後離圖／退往友方或建築／無路投降與後續抓捕三分支。
- 視覺序列需有開始／途中／結果，不能只看最後人數或一張截圖。原完整陣型抵達後5秒穩定仍測；本案不代替既有5000人效能驗收。

## 6. 驗證工具與交付要求

原 helper 不得修改，保留最新100個完成 run 的 retention；重要 evidence 複製到本任務專屬 output。失敗先診斷、針對性修正再重跑；不重跑未改的同一失敗、不刪失敗紀錄、不放寬物理驗收。

目前已查得執行檔：`C:\Users\Nekki\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe`。執行形式：

```powershell
& 'C:\Users\Nekki\.codex\skills\godot-runtime-verify\scripts\verify_godot.ps1' `
  -ProjectPath (Get-Location).Path `
  -GodotExecutable 'C:\Users\Nekki\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe' `
  -Mode headless -TimeoutSeconds 120 `
  -GodotArguments @('--script','res://scripts/tests/<對應既有測試>.gd')
```

Timeout 要依場景事前合理設定；大量行軍／GPU 測試不把120秒當通用預算。沿專案 AGENTS 使用可用的原生 session／subagent status 與有界 wait 主動監測，不為缺少 schedule 建立重複 automation。

SOL 完成交付：逐 P0–P5 列「已實作／已驗證／仍有缺口」，附精確變更檔、各測試 result／log、正式畫面、存讀／人員／物品守恆證據。同步更新 PROJECT_ARCHITECTURE 對本次新語意的說明；不得宣稱已完成 World 旅行或大規模 FPS。未經另行要求不 commit／push，不用 `git add -A`。

## 7. 本輪證據界線

- 原碼 audit 已追完整相關 callers、UI、Plan／Grid、存讀與 native readers。
- 已跑兩次有時限 headless 診斷：第一次3.906秒、第二次6.594秒，兩次 exit 0，無 script／parse／assertion 錯誤。第二次增加原 UI handler 追加第三隊重現。
- 僅有 Windows root certificate store 訊息，依 canonical verifier 分類為已知環境雜訊，原 stderr 留存。
- **本輪未實作四項修正，未跑修復後驗收，未做 GPU 視覺／FPS 驗收。** 診斷 PASS 是證明舊行為與程式原因，不代表需求已完成。
- 證據入口：`output/team_orders_audit_20260928/README.md`、`ui_append/combined.log`、`source_evidence.json`、`spawn_direction_probe.gd`。
- r2 只補查現行士氣、指揮權、建物與拘束／俘虜接點並修改本計畫；補充來源指紋見 `source_evidence_r2.json`。沒有新增Godot測試執行。r1兩次診斷僅證明部署問題，不是新撤退／投降規則的驗收。
