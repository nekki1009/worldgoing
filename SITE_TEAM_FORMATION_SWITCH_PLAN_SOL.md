# 隊伍切換中國古代陣型：詳細修改計畫 — 給 SOL

日期：2026-09-26。狀態：**已進入實作與本輪 Godot 驗證；最新通過項與仍待驗項見 [實作紀錄](output/team_formation_switch_impl_20260926/README.md)。**

目標：在正式 TerrainLab 的既有隊伍命令介面，讓玩家選擇陣型、預覽占地並下令換陣；同一批原人物必須實際逐格走到新位置。行軍途中沿用原狹道通行，抵達再排回所選陣型。下文保留原設計與驗收界線；實作結果以連結的紀錄和實際程式為準。

## 1. 建議定案與範圍

第一版完整目標是「既有自適應 + 六種中國陣型」：方陣、圓陣、錐行陣、雁行陣、鉤行陣、疏陣。依 §10 分階段落地；前三種可先驗收一個垂直切片，但不能因此宣稱全部完成。

陣名依據《孫臏兵法・十陣》的方、圓、錐行、雁行、鉤行、疏等記載。原文有缺簡與異體；本計畫的格點、厚度、朝向與用途說明是**遊戲化設計，不是古陣圖的精確復原**。來源：[《孫臏兵法・十陣》原文轉錄](https://zh.wikisource.org/zh-hant/%E5%AD%AB%E8%87%8F%E5%85%B5%E6%B3%95#十陣)。

本版納入：

- 既有戰鬥隊伍的原地換陣、MOVE 途中改終點陣型、選陣後點地／拖曳指定面向。
- 唯讀預覽、空間／占格預檢、成功才提交、失敗保留舊命令。
- 四個正方向、圓陣朝外、隊伍設定保存、舊檔相容、拆併隊規則。
- 真正自動隊員的逐格移動、完成／缺員／中斷狀態，以及正式 UI 和 GPU 畫面驗收。

本版不增加戰鬥加成、攻防倍率、速度倍率、士氣公式、額外換陣讀條、免費瞬移、混兵編制、八卦機關、鴛鴦陣兵種協作、火攻／水戰、跨隊大陣或新 AI 選陣策略。陣型的差別先由實際占地、接觸面、射線與面向產生；不能在介紹寫出未實作的攻防收益。

## 2. 本輪來源審查與接手基線

主場景：`project.godot:15` → `res://scenes/terrain_lab/TerrainLab.tscn`。HEAD 為 `39f14442a576df22557dcefddecc2f6e2ce3efa1`；審查開始時有 839 筆既有 dirty/untracked entries。**HEAD 不是現行程式基線。** 來源雜湊與 Git 狀態見 [本輪來源快照](output/team_formation_switch_plan_20260926/source_snapshot.json)。接手先比對；行號只供本轮定位，函式名與當前 callers 優先。

### 2.1 已有可延伸的正式流程

- `scripts/terrain_lab/site_controller.gd:471` `_build_combat_window` 建立原戰鬥視窗；`:773` `_trial_team_order` 是既有選定測試队命令入口；`:835` `_update_facing_move_preview` 已有拖曳面向預覽。
- `scripts/terrain_lab/terrain_lab.gd:1934` `issue_player_army_order` 對玩家控制者查權限，再進 Army；不應繞過玩家／NPC 命令權限差異。
- `scripts/terrain_lab/terrain_army.gd:2672` `_preflight_combat_move` 共用路徑、方向、終點計畫；`:2717` `preview_combat_move`；`:2737` `issue_combat_order` 才正式換令。
- `scripts/terrain_lab/formation_destination_planner.gd:124` `plan_deployment` 現在從同高平台選錨點附近的緊湊格位；不足時才形成平台成員 + 進路待命。`:340` 起依物理入口順序與幹部安排槽位。
- `scripts/terrain_lab/combat_deployment_plan.gd:9` 起持有一次命令的 anchor、facing、width/depth、shape_version、固定槽位、member↔slot、角色及租約狀態。這裡已經是終點布陣 owner。
- `CombatMovePlan`／`FormationTransitPlanner` 是途中順序與软目標；`current_width` 的 1–4 列不是玩家選擇的戰鬥陣型寬度。Army 的舊 `_formation_width`／`formation_cohesion` 也不是本功能入口。
- `SiteCombatMovementCoordinator`／`SiteMovementReservationGrid` 仲裁逐格移動；`SiteDeploymentReservationRegistry` 管跨隊終點租約。維持各自原責任。
- `scripts/terrain_lab/site_store.gd:814` `_valid_combat_movement_snapshot` 先獨立驗 deployment，再驗 MOVE。Army `:5219` 序列化、`:5276` 反序列化、`:5816` 起還原計畫與租約。

### 2.2 已確認、必須處理的接點

1. **目前沒有可選陣型 ID。** `final_width` 是結果，不能只增加下拉選單並改 width 就算完成。
2. **一格平移快路會保留舊形狀。** Army `_short_translation_deployment_plan:2608` 使用 `cells + step`，目前未檢查形狀／朝向相等；換陣與轉向必須排除不合條件的快路。
3. **自然抵達仍留有 deployment。** Army `:1297–1315` 與 `:3052–3067` 只清 move_plan、轉 HOLD，保留布陣合同與租約。顯式 HOLD／ATTACK 則在 `:2791–2794` 清兩 plan。保存與 UI 必須分清兩者。
4. **現有 recovery 沒有任意改掉平台形狀。** 本輪搜尋確認其主要透過既有固定槽位交換 member 指派；本案補形狀不變量與反例，不預先重寫恢復系統。
5. **角色標記會隨人物交換。** `CombatDeploymentPlan.swap_member_slots:119`、`rotate_vacancy_chain_targets:146` 會搬 COMMANDER／OFFICER 標記；圓陣的朝外方向是地理屬性，不能塞進同一角色 map。
6. **原地重排需單獨證明。** 宏觀路徑 start==goal 會回單格 path；原地成員可以經既有目標解析走 final slots，但部分 ingress 邏輯在空 buffer 時提早返回。長距離 PASS 不涵蓋此案。
7. **地形 footprint 有界。** 目前 `MAX_PLATFORM_RADIUS=12`，相當於最多 25×25 的同高可达候選。200 人疏陣不能硬塞在原範圍，也不能生成 100 人單層大圓環後指望 planner 自動成功。
8. **架構文件有陳舊一句。** `PROJECT_ARCHITECTURE.md:179` 仍寫兩人對穿拒絕，現行 Grid `is_same_formation_pair_swap:92` 與測試已允許同隊、同起始軍令、相鄰 reciprocal pair。保留此窄規則，實作時修正文案；跨隊 pair、不同軍令及三人以上封閉循環仍拒絕。
9. **受控人物例外原本就存在。** `_get_active_member_ids:255` 列出原有效 Army rows，可能包含目前受控 row，但不加入獨立 PLAYER_MEMBER；`_automatic_deployment_settled:1239` 跳過目前受控者。不可為了畫出完整陣形強迫玩家移動或複製替身。
10. **隊伍 ID 不是陣型 ID。** 現有 `formation_id` 是隊伍／執行身分；新增 `formation_preset_id`，不可改用既有 identity 欄位裝陣名。

## 3. 陣型清單與可見行為

ID 使用固定小寫字串，顯示名獨立，不能把下拉選單 index 寫入存檔。定義放在現有 `FormationDestinationPlanner` 的純資料／純函式即可；不用每陣一個 Resource、類別、策略介面或新 manager。

### 3.1 `auto`／自適應（既有）

新隊與舊檔預設值。完全保留原緊湊平台 + 進路待命策略及原 footprint 半徑。UI 可以明確顯示「平台 60／進路 40」；不能把這個結果標成已完成某個指定古陣。

### 3.2 `square`／方陣

- 密集近方形，適合作為一般集結與比較基準；每人仍占一格。
- `w=ceil(sqrt(N))`，逐列填入，最後不足一列置中；左右平手時用固定方向決定，不能每次隨機。
- 100 人為 10×10；25 人為 5×5。所有自動隊員完成後朝命令方向。
- 幹部沿既有後方、靠近入口的可達槽位政策，不把隊長固定塞到最前端。

### 3.3 `wedge`／錐行陣

- 前窄後寬的實心楔形，呈現集中前端、後方加厚的隊列。
- 由前往後列寬依序 1、3、5、7……，最後不足列置中；到 N 格即止。100 人剛好十列，最後列 19 格；25 人五列，最後列 9 格。
- 指揮者沿後方槽位；「尖端」不等於自動指定隊長，也不增加衝鋒或傷害倍率。

### 3.4 `goose`／雁行陣

- 採多列梯次斜列的遊戲表示，不與鶴翼、V 形或歷史唯一復原混稱。
- 以方陣相同的 w 與列數，每往後一列在側向錯開一格；各列內仍是相鄰整數格。100 人十列、外框側寬 19 格，避免單列 100 格長蛇。
- 全員完成後朝主方向；實際能否射擊仍由原射線／友軍攔射判定，不能宣稱必然沒有友傷或具有射程加成。

### 3.5 `circle`／圓陣

- 採緊密、近圓形的實心格點分布，外沿朝外；本版不做需另外入場調度的空心環陣或中心車輛保護。
- 以整數格距離平方排序選最靠中心的 N 格；同距離採固定、四象限交替的 tie-break，避免邊緣餘數集中一侧。模板在本地座標產生一次，四向只做整數旋轉。
- 面向從 slot 相對 anchor 的向量取主軸，得到四個正方向；斜角相等時按固定本地座標規則選軸，再隨整隊旋轉，中心格沿主方向。
- 幹部先沿原可達後方槽位，第一版不強制穿過全部友軍進中心。實際接敵／攻擊時由原戰鬥朝向接管，不能每幀強制拉回圓陣朝向。

### 3.6 `hook`／鉤行陣

- 前列加兩側向後折回的厚鉤形，呈現前方戰線與兩翼；不新增兩翼獨立人物群組或獨立指揮。
- 用有厚度的離散 U 形框架：`t=max(1,ceil(sqrt(N)/4))`，`L=max(t,ceil((N+2*t*t)/(3*t)))`。在 L×L 方框中選前 t 列，以及其後各列的左右 t 格，候選容量在 L≥2t 時為 `3*t*L-2*t*t`，小人數則按去重後實際容量。共用端點只列一次，必須至少能取 N 格。
- 由前往後逐列、每列左右成對交替取恰好 N 格。前橫列由中央向外，後方兩翼由外向內，平手固定先本地左側；最後餘數允許左右相差一人。100 人 t=3、L=14，200 人 t=4、L=20，不會形成百格長線。
- 保留 U 形凹口的可辨識度；生成器以 25／100／200 人固定期望點集測試證明，不得在模板外補格或把缺額補成矩形。
- 主方向為前橫列外側；第一版全員主朝向，兩翼接敵轉向仍用原戰鬥。這是幾何換陣，尚非兩翼包抄 AI。

### 3.7 `loose`／疏陣

- 以方陣格點放大為二格中心間距，行列之间留一格；100 人外框 19×19，200 人約 29×27。
- 仍是一人一個真實占用格；中間空格不預約為本隊私有地，別隊與人物能按原規則通行。
- 禁止縮小人物、武器或碰撞體來假造疏密；不增加閃避倍率。

所有模板支援 N=1–200。N 沿原 `_get_active_member_ids` 在下令時的有效 Army rows 凍結，包含其中可能受控的 row；獨立 PLAYER_MEMBER 沿原自主規則，不為本功能新增虛構名額或槽位。受控 row 的槽位只作提示、不強制移動，完成統計另列；不能把 N 說成「自動到位人數」。N=0 拒絕；N 很少時可退化成點／短列，但保留所選 ID，介紹說明人數少時外形不明顯。原隊伍名冊上限、最多三隊／總 NPC 保存上限維持不變。

## 4. 幾何、通行與角色合同

### 4.1 唯一座標與有界計算

使用 `Vector2i` 槽位。令前方 `F=final_facing`，側向 `R=(-F.y,F.x)`，世界槽位為 `anchor + R*u + F*v`。方／錐／雁／鉤／疏模板依外框作確定性整數置中：每軸減去 `floor((min+max)/2)`，偶數尺寸多出的一格固定留在正軸側。圓陣固定以本地 `(0,0)` 為選點與朝外中心，不再依剩餘邊緣格做第二次外框置中。不得浮點旋轉後逐格四捨五入造成重疊。

模板輸出恰好 N 個唯一格點。`final_width/final_depth` 對新陣必須是本地外框實際寬深，不能沿用 `min(10,N)` 或 `ceil(N/width)`，後者不適用疏陣和楔形。

指定陣形的 footprint 查詢半徑由模板推導：`max(12, 模板最大絕對格偏移 + 1)`，本版硬上限 24；模板本身須在 1–200 人全部落入這個有界範圍。沿現有 `build_platform_footprint(..., max_radius, profile)` 傳參，不更改 auto 預設 12。`refresh_derived_ingress` 也須由同一模板規則推導，不能讀檔後又縮回 12。

半徑 24 是本功能針對較寬幾何的明示上限，僅用於下令／預覽／必要重建的 footprint；**不放寬原宏觀／局部搜尋預算、每步提案量或舊測試時限。** 不合格模板應修幾何，不能不斷加大範圍。

### 4.2 指定陣形必須完整可放

`auto` 繼續原平台／進路容量規則；六種指定陣型則需要完整 N 格合法，且每格位於原 profile 可達的同高平台中。平台可走不代表目前沒有外部占用，還要核對既有 actor、非參與隊員、失能者、車輛、在途 claims 與其他隊終點租約。

- 可接受本隊本次參與重排的人目前占用目标格；交給原逐步仲裁搬移。
- 受控人物、非參與者與外部人物的位置不能當作可被直接覆寫的空格。受控 row 若已位於自己的提示槽可接受，不能把該格再配給另一自動隊員；若阻擋候選陣型又無合法指派，預覽應提示先移開或另選位置。
- 保留入口／暫存空間的原用途；入場次序不能藉刪掉模板中一格解決。若模板包含 ingress，規劃進入顺序／原软目標，不能沿舊過濾直接把該格刪掉再找别格補。
- 無法完整放下就回 `INSUFFICIENT_SPACE`／`BLOCKED`／`RESERVATION_CONFLICT`，顯示原因及候選占地。指定陣型不自動降級成 auto、擠成另一形狀或把一半人留在進路卻顯示完成。
- 錨點仍可沿原 `_resolve_combat_goal` 對不合法點進行既有解析，但 preview 必須顯示真正 resolved anchor；原地換陣若必須移動錨點，也須在提交前看得見。

平台 footprint 是可走域；platform_slots 是最後要站的格。疏陣和鉤形空隙可以是行走路徑，不必是最終槽位。不能用「槽位彼此不相鄰」錯判整個地形不連通。

### 4.3 晚綁定、角色、圓陣面向

先產生固定槽位集合，再沿原 planner 的幹部／物理到達順序分配與晚綁定。原 recovery 可交換既有格中的 member↔slot；對任意交換斷言固定幾何集合不變、assignment_epoch 正確、受影響 route cache 失效。

COMMANDER/OFFICER 仍沿原人物任職與接替政策。不要把軍官標記誤當槽位固定朝向；也不要求只因換陣就更換軍官、裝備或兵種。

圓陣增加 deployment 的純查詢，例如 `get_facing_for_slot(cell)`，由已凍結的 preset/anchor/facing 推導；不用另存一份逐兵面向表。Army `_orient_settled_combat_members` 消費此結果，預覽也用同一查詢。受控人物保留自由面向。

## 5. 換陣命令的完整語意

### 5.1 介面與當前命令的行為

在原戰鬥隊伍命令區增加「陣型」選單、简短占地說明、候選預覽及「套用陣型」。玩家隊命令入口和選中測試隊命令入口都可使用；以原權限決定能否操作。

- 選單切換先更新 **UI 候選值**，不立即改 Army 偏好、serial、人物位置或租約。
- HOLD 中套用：若仍有合法且已完成的 deployment，保留其 resolved_anchor 與面向；沒有／已取消／失效時，才使用當前實際路由錨點／medoid 與原指揮朝向。先判斷相同合同是否 no-op，避免楔形質心與幾何中心不同導致每按一次就平移。不得沿上次已取消的遠方 goal 走回去。
- MOVE 中套用：保留原 requested goal 與本次 final_facing，重新預檢目的地形狀；成功替換終點合同，繼續原移動規則。不能只改顯示名稱或保留舊 member_slot_map。
- ATTACK/PURSUE 中套用：明確顯示「停止目前接敵／追擊，原地整隊」，成功後與原 MOVE 一樣取消舊攻擊意圖，完成回 HOLD；不暗中恢復攻擊。
- RETREAT、RETURN、潰退／失去有效指揮時拒絕新的換陣，顯示原因；不因選陣打斷強制撤退。
- 暫停時可唯讀選擇／預覽，正式送令沿原 BUSY 拒絕；不新增恢復後自動發令佇列。
- 工作、後勤／帶車隊本版不提供戰鬥換陣；保持其原工作與運輸命令。若之後經原合法流程轉成戰鬥用途，才啟用。
- 選定陣型後點地／拖曳面向：把候選 ID 和方向一併帶入原 move preview／commit。ESC、關窗、換隊、GUI 放開或取消拖曳撤銷候選；Army 保留上一次成功設定。

避免另設「待換陣」永久命令系統。換陣就是帶新終點幾何的既有 MOVE，完成沿原規則進 HOLD；必要時只新增一個薄的 `issue_formation_change` 入口來決定 anchor/goal，其餘仍共用 `issue_combat_order`。

### 5.2 提交與回滾順序

1. 查原 requester/current_commander、用途、暫停、潰退及 preset 合法性。
2. 用候選 preset 生成新計畫，查路徑／完整形狀／外部占用／租約；過程唯讀。
3. 使用下一個候選 serial 做原 registry 的 `try_replace_reservations`。預約成功前不得清原 plan、覆寫偏好或取消原攻擊目標。
4. 成功後一次發布新 serial、隊級偏好、move/deployment、目標與原換令清理。
5. 保留已承諾 `moving_to/move_progress`、原 batch 成員與起始 MOVE／RETREAT 種類，讓原 0.38 秒步進安全完成；下一步才依新計畫。未開始的提案仍須通過現行 order_serial 檢查。現有已開始 batch 並無獨立持久化軍令 serial，不為此功能新增該欄位；禁止直接寫入新 `cells`。

Army 現行 `:2775` 在租約替換前呼叫 `_next_order_serial()`；SOL 必須核對失敗是否提前消耗 serial，必要時把發布延後。回滾測試比較軍令／計畫／租約／格位等受此操作控制的狀態，不把獨立發生的指揮接替誤判成回滾失敗。

一格平移捷徑僅在「本次與原合同同 preset/version、同槽位朝向規則、目標集合恰為原集合平移、有效名冊相容」時才可使用。第一個切片可讓六種新陣全部走一般部署路徑，保留 auto 原快路；有收益證據後再開放新陣快路，不需要預先優化。

重複套用相同陣型不一定是 no-op：若站位已散、已中斷、方向改變或有缺員，應重新預檢整隊。只有原合同仍有效、參數相同、且已完成／正在前往同一完整目標時才可直接回傳現況而不重置行軍。

### 5.3 中斷、傷亡與完成

- 新命令成功才取代舊令；A→B→C 快速切換只有 C 決定之後目標，A/B 已承諾步進照原批次完成。
- 明確 HOLD／ATTACK／RETREAT、強制取消、清隊與地形失效沿原释放入口；清理本次 plan/lease，不清上次成功的隊級偏好。
- 地形改變使指定陣形失效：重新檢查同一固定形狀；不能静默換形。原有界恢復仍無法完成時安全停止、釋放失效租約並報原因；偏好可保留供下次再下令。
- KO 沿原暫離槽租約（目前 4 秒）、回歸及失能者實體占格；死亡沿原移除 mapping／釋放租約。當次原 platform_slots 幾何不縮小，不每少一人就全隊重排。
- 需補驗「仍有 KO 暫缺租約、其他人已先完成」：目前 Army 轉 HOLD 會清 absent_slots，而 Store 要求暫缺 lease owner 存在於 absent_slots。沿原完成後「傷員原地待新令」語意，本版在結束 MOVE 時同步結束暫缺等待、清除對應四種 slot_lease maps 並同步 registry，再清 absent_slots；復起者待新令。不藉此釋放仍有正式 owner 的完成槽位租約。這是有具體來源反例的完成接點修正，須先重現再修，不能放寬 Store 接受不一致快照。
- `requested_count` 是這次下令凍結的 N；傷亡後存檔用它驗幾何，不能用目前 alive count 重建另一套點集。可動員完成但存在缺員時顯示「可動隊員已整隊；缺員 X」，不能顯示原 N 人全滿。
- 下一次明確換陣／MOVE 才按新有效名冊重新生成。受控人物依原例外自由行動，UI 分列「自動隊員到位 a/b、受控者自主、缺員 c」。

「已整隊」至少要求：所有本次仍有效的自動成員 `cells==member_slot_map[id]`、`moving_to` 清空、原 batch/claims 排空、槽位租約 owner/serial 正確、完成朝向正確；不能用平均位置、有人移動或預覽成功代替。

## 6. 最小資料與保存契約

### 6.1 隊級偏好與一次命令快照

- `TerrainArmy.formation_preset_id: String = "auto"`：上一次成功設定；是之後 MOVE 的預設，也是無活動 plan 時仍需保存的隊伍偏好。
- `CombatDeploymentPlan.formation_preset_id`：該次命令凍結的陣型。沿既有 `shape_version` 區分新舊合同，不新增平行版本系統；新輸出使用 v2，現有 v1／缺欄位只走明確 legacy 分支。
- plan 現有 anchor/facing/requested_count/platform_slots/member maps 繼續作正式合同；模板不可取代人物真實位置。純模板結果与 footprint 半徑可由 preset/version/N 推導，不新增永久快取。
- UI 不持有第二份正式隊形。顯示「所選：錐行／正在整隊／已完成／已中斷」，由 Army 偏好、現有 plan、原步進與占格計算。

### 6.2 保存與嚴格讀取

在 Army `capture_combat_state:5154`／`restore_combat_state:5692` 增加隊級偏好，並在 `valid_combat_state:5464` 嚴格驗型別與白名單；restore 會先 clear，偏好必須在其後恢復。在 `_serialize_deployment_plan`／`_deserialize_deployment_plan` 增加陣型 metadata；SiteStore 同步驗證，不能先 `str()`/`int()` 把非法值轉成合法資料。

- 缺少新欄位的舊隊預設 auto；既有 v1 deployment 的原槽位／指派／進路隊列原樣保存恢復，不按新方陣重新生成。
- v2 必填 preset；未知 ID、錯誤型別、未知 version、非法四方向、N 越界、重複槽、越界格、錯誤 width/depth、member/slot/lease 關係錯誤均拒絕。
- 頂層偏好與有效 v2 deployment 的 preset 必須一致；UI 候選不進快照。兩者不同代表部分提交，拒絕，不能以讀檔時擅自同步來遮掩。
- 六新陣 v2 的完整 platform_slots 必須等於模板在所存 anchor/facing/N 產生的格集合；隊員 mapping 可因原死亡／缺席規則是其子集。不得將缺席誤判為必須重新生滿 N 人。
- auto v2 繼續驗其原自適應合同，不要求等於方陣模板。v1 的既有 width/depth 語意不回溯套用新陣外框標準；新陣 v2 必須嚴格驗真正外框。
- 向外面向由 slot 純查詢還原；member↔slot 交換後也仍依位置朝外。
- **HOLD 且 move_plan=null、deployment 非空是合法完成狀態。** 陣形驗證必須放在 deployment 獨立區，不能藏在 MOVE 專屬分支。
- 保留 SiteStore 先完整驗證再替換現場、原子寫檔、checksum、交戰保存限制。非法檔案不得動到合法原檔或目前場景；不新增繞過 BUSY 的強制保存。
- 對已承諾步進沿原 batch 起始軍令還原；目前換陣後的軍令不能覆寫舊 MOVE／RETREAT 批次身分。

### 6.3 名冊與用途生命週期

在原 `_roster_metadata`／`_install_roster` 保存恢復偏好，避免後者 `clear()` 意外重設。拆出新隊繼承來源偏好；併入既有隊採接收隊偏好；來源仍有成員則保留自身偏好。新建／全清空才重設 auto。

拆併仍沿原限制與原 row/cargo/gear references，不為保留形狀複製人物或物品。不直接搬動格位來維持新隊外形；名冊改完需要新命令才重新整隊。用途轉換仍由現有工作／後勤 owner 執行。

## 7. 介面與預覽的具體要求

沿原 `SiteController` 戰鬥視窗新增少量控件，勿另造陣型編輯器。保留隊伍選擇、權限訊息、既有點地／拖曳方向操作。

- 七個選項使用上述名稱，輔以簡短幾何說明與目前所需外框；兵數變更即更新候選資訊。
- 預覽畫原槽位輪廓與方向箭頭，新增圆陣槽位箭頭亦讀同一純查詢；本版用原繪圖即可，不新增貼圖／模型／烘焙資產。
- 文字區分「候選」「正在整隊」「已整隊」「缺員」「已中斷」，另顯示空間不足／被占用／無權限原因；不能只靠紅綠色。
- 選中另一隊、關窗、取消拖曳、原隊被清除時清 UI 候選，不能把上一隊的未提交選項套到下一隊。
- 原 `_facing_order_source` 目前只辨識 trial/player/test；新增候選時綁定實際 team ID、控制者 ID、preset 與預覽參數。正式送令重驗，避免預覽 A 隊卻對選單新選的 B 隊提交；讀檔或控制者改變也使候選失效。
- preview 與 commit 使用同一 `_preflight_combat_move` 幾何入口。若預覽後地形／名冊／占用改變，正式送令重新預檢；有變化就顯示新結果或拒絕，不能照過期預覽覆寫位置。
- 預覽只在候選 ID、目標格、方向、名冊／地形版本等有關输入改變時重算；不要在每幀為全隊重建形狀或逐兵尋路。正式送令仍要查即時外部占用，不把 UI 快取當權威。

## 8. 預計修改檔案與責任

原則上正式實作集中以下既有檔案；實際檔名與行號接手再核對。

1. `scripts/terrain_lab/formation_destination_planner.gd`：preset 清單、純模板、幾何合法化、指定陣的完整放置分支、半徑推導、對應入口重建。保留 auto 路徑。
2. `scripts/terrain_lab/combat_deployment_plan.gd`：凍結 preset/version、純槽位朝向查詢及幾何不變量；沿用既有指派與生命週期。
3. `scripts/terrain_lab/terrain_army.gd`：隊級偏好、共用 preflight/preview/commit 參數、薄換陣入口、short_translation 限制、完成面向／狀態、snapshot/restore、名冊 metadata。
4. `scripts/terrain_lab/terrain_lab.gd`：玩家命令轉送與原預覽繪圖所需欄位，不建立正式陣型狀態。
5. `scripts/terrain_lab/site_controller.gd`：原視窗控件、測試隊／玩家命令接線、候選取消、用途與權限提示。
6. `scripts/terrain_lab/site_store.gd`：v1→auto 兼容、v2 嚴格合同、HOLD 和 MOVE 保存驗證。
7. `PROJECT_ARCHITECTURE.md`：完成後記錄實際 owner、陣型語意、pair-swap 正確界線與驗收證據；不先寫「已驗收」。

`FormationTransitPlanner`／Coordinator／Grid／Registry 原則上不需改演算法。若新增反例證明某個真接點不支援原地換陣，再於原 owner 做最小定向修正，記錄原因，禁止另起平行導航或 reservation 系統。

新增測試原則上只有 `combat_formation_shape_test.gd` 與 `combat_formation_switch_test.gd`；UI、存讀、名冊、狹道與多隊沿 §9 既有測試擴充。不用每陣複製一套測試框架。

## 9. 驗收矩陣與不得放寬的條件

### A. 純形狀與預覽

- 六陣 N=1..200 全範圍檢查 count／唯一性／整數／有界；對 1、2、3、5、10、25、100、200 做四向、穩定排序及旋轉等價。
- 25／100 人各陣留下人工可辨識點集／預覽圖，並有獨立幾何期望：方陣寬深、楔形逐列、雁行錯列、圓陣距離分布與朝外、鉤形凹口、疏陣間距。只測 N 格不足以證明陣型不同。
- 擴充 `combat_movement_preview_test.gd`：preset、anchor、方向、完整槽集合、外框、朝向與正式送令相等；preview 不改 serial、格位、plan、lease、隊級偏好。
- 未知 ID／非法方向／0 人／空間不足／他隊租約冲突要返回明確失敗；確認失敗没有換成 auto。

### B. 實際換陣與生命週期

- 正式 Army 的 100 人、六陣逐一從 auto 換入並換回；至少一組方→錐→雁→圓→鉤→疏→方連續轉換。另以 25 人涵蓋六陣的所有有向兩兩轉換，避免只測 auto 入口。
- HOLD 原地、同 anchor 不同形狀、同形狀四向轉身、一格目的地但不同形狀、MOVE 中途、A→B→C、同參數不重置，以及已散隊的同陣重整。
- 原相鄰 pair 在 move_progress 中途換陣、空尾鏈、另一隊固定阻擋；沿原 `combat_movement_physical_pair_swap_test.gd`／`test_move_cycle_rejection.gd` 核對合法與非法循環。
- KO／回歸／死亡／指揮接替／無指揮／受控人物切換；原人物 ID、物品、HP、共享疲勞不因改陣被重建。
- 部署完成須逐人到自己的合法槽位、面向正確、租約正確、無 claims/batch，之後至少 5 模擬秒無漂移／抖動。失能／自主控制例外另列，不減分母掩蓋未到位。
- 平地每案先固定最多 300 模擬秒，超限保留失敗；不能在看到卡住後直接加時。純平地換陣若需接近此上限，交付時明示實測換陣耗時，不能只列 PASS。

### C. 失敗原子性

擴充 `combat_movement_200_capacity_rollback_test.gd` 與 `combat_movement_task4_test.gd`：合法舊 MOVE 在途 → 新陣無完整空間／租約衝突／過期 serial → 舊 goal、preset、serial、plans、combat_slots、moving_to、lease 保留且下一步能續行。預覽可行後再加入合法阻擋，也必須如此。

### D. 行軍、山頂與多隊

- 原 auto 的 `combat_movement_100_choke_bend_arrival_test.gd` 完整回歸：100 人、真 4→1→4 牆隘、90° 彎、原 8000 ticks、全員過障礙並 exact final + 5 秒穩定。
- 最寬／最深的新陣在出口有完整空間的相同狹道、彎道案例完成；過道收窄不改所選 preset，出口恢復原固定幾何。
- `combat_movement_multi_team_arrival_test.gd` 保留原每案 2400 ticks／150000 ms：2×100、3×100，含不同陣型鄰接目的地；總 200／300 leases 不重疊，各隊 exact arrival 與 5 秒穩定。
- `combat_movement_formal_mountain_arrival_test.gd` 保留原 auto、TERRACED_HIGHLAND、seed 12345、目標 (49,37)、100 人、30 Hz、300 模擬秒／240 wall 秒，地形不變且無傷亡縮分母。
- 新陣在山頂若真容得下，至少取一種完整到位；若全部不合幾何，據實列出各陣預檢失敗原因與保持舊令證據，不改山體、改錨點偷放寬或把拒絕說成到位。
- 原 auto 的 60 平台 + 40 進路案例保留；指定陣型對同樣不足平台應拒絕，二者是刻意不同的產品合同。

### E. 保存、載入、拆併

- 擴充 `combat_movement_multiphase_store_resume_test.gd`，真正走 SiteStore 寫檔／讀檔／重新綁定後續行；覆盖行軍中換陣、入場、最後幾人整隊、自然完成 HOLD、取消後只有偏好，以及在途 pair。
- 現有測試只 assert 至少兩個 genuine phases（含 TRANSIT），歷史某輪恰好跑到四個，不等於自動涵蓋四階段。要宣稱四階段便須逐一觀察並 assert；原地換陣可以合法跳過 TRANSIT/QUEUE，不捏造階段。
- 與未存讀的對照比較 final slots／朝向／人物与物品狀態／租約清理；只有真的逐步比對過，才可宣稱 deterministic 續行。
- 舊缺欄位、v1 auto、v2 六陣、N200、HOLD 有 deployment 无 move，以及死亡後 mapping 子集。
- KO 發生後未滿四秒，其餘自動隊員完成 → 立即保存／讀回：確認暫缺 lease maps、absent_slots、registry 一致，傷員依完成後語意原地待新令；保留活人已完成槽位的租約。
- 非法 preset／version／型別／槽位／方向／N／外框，即使重算 checksum 仍拒絕，合法原檔 hash 與目前場景不變。
- 在 `site_army_roster_test.gd` 增加拆分繼承、併隊接收者設定、clear 重設；保留原 100→80+20→100→200 與 row/cargo/gear 引用不複製斷言。

### F. 正式 UI、畫面與效能界線

- 擴充 `combat_movement_facing_gui_cancel_test.gd`，實際選隊／選陣／預覽／套用／取消／關窗／換隊／GUI 放開；玩家權限與 NPC 測試命令都走正式接線。
- 正式 TerrainLab 100 人至少留六陣各一張完成全景；另留圓陣多方向近景、原地換陣的起／中／末段、狹道出入口及失敗預覽。畫面必須來自原 Sprite/MultiMesh，不以示意圖替代。
- 200 人或三隊場景記錄下令耗時、換陣完成秒數、最大等待、route 預算耗盡、預覽重算次數；同硬體同場景比較原 auto 基線，報 median/p95/max frame time 和样本长度。
- 本功能不承諾 5000 人、百萬人或 GPU 常駐完成；不降低解析度、動畫更新頻率、兵數或碰撞品質來讓新陣過關。不觸碰模型／圖集／DLL，除非真有必要且已另釐清範圍。

## 10. SOL 執行順序與階段出口

**P0：接手核對。** 讀本檔、AGENTS.md、現行架構與 source_snapshot；確認正在變動的 Army/Store/UI 差異。先建立原 auto 的必要基線，記錄既存資產或測試 fixture 失敗。禁止重置大量 dirty files。

**P1：方／錐／雁的完整垂直切片。** 純模板 → deployment metadata → 同一 preflight/commit → 原 UI → 保存 → 原地與途中換陣。先以方陣跨完整流程，再加入錐／雁。出口：三陣可從正式介面逐格完成，失敗不破壞旧命令，旧 auto 可讀可走。

**P2：圓／鉤／疏。** 加逐槽朝向、U 形／疏形模板、有界 footprint 推導；完成小隊與100人精確到位，確認不受舊密集矩形假設影響。不另加第二套進場或位移系統。

**P3：邊界閉合。** 傷亡、受控者、指揮接替、暫停、中斷、拆併、v1/v2 和 HOLD 保存、非法檔拒絕；補上具體失敗反例後定向修正。

**P4：整體驗收。** 完整狹道／彎道／多隊／正式山頂 auto 回歸、新陣可放／拒絕、UI GPU 與持續畫面。整理實測耗時、未涵蓋邊界及全部失敗結果；更新架構與交付紀錄。

若 P1 通過但 P2 或 P4 尚未通過，交付狀態必須寫清楚已實作／已驗證／仍有缺口，不把部分可用當全功能完成。

## 11. 驗證操作與證據保存

使用原 `godot-runtime-verify` 有界 helper，不修改腳本、錯誤掃描或 newest-100 retention。根 AGENTS.md 已授權失敗後診斷、範圍內修正與定向重驗；禁止無改動重跑同一失敗或降低驗收門檻。無 schedule 時使用原生 status/wait 監控，不能為計時建立 recurring automation。

接手先核對實際 Godot 路徑，以下是目前測試環境的命令形式；檔案未建立前不可聲稱已執行：

```powershell
$verifyPath = "$env:USERPROFILE\.codex\skills\godot-runtime-verify\scripts\verify_godot.ps1"
$godotPath = 'C:\Users\Nekki\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe'
& $verifyPath -ProjectPath (Get-Location).Path -GodotExecutable $godotPath `
  -Mode headless -TimeoutSeconds 120 `
  -GodotArguments @('--script','res://scripts/tests/combat_formation_shape_test.gd')
```

完整移動測試按其已訂內部 wall limit 設定 wrapper 額外診斷餘裕；例如正式山頂 wrapper 270 秒、測試內仍 240 wall 秒。GPU 測試沿 `-Mode visual`、已支援的 Vulkan 路徑與 `-ExpectedOutput`，檢查新產出並目視；不得以 headless 結果取代畫面。

實作證據建議存 `output/team_formation_switch_YYYYMMDD/`：README、各案 result.json/stdout/stderr、陣形與指派摘要、失敗原因、完整圖與來源 hash。從 `.godot-temp/godot_verify` 複製需長留的指定結果，不能停用 retention。

本輪只查閱的歷史依據為 [尋路實作與驗收紀錄](output/pathfinding_impl_20260924/README.md)：其中已有 100 人高地 252.333 模擬秒抵達的 headless 證據；同頁仍保留未完成、timeout、圖形錯誤及 GPU／完整存讀矩陣缺口。這些不是本功能本輪重測成績。

## 12. 交付完成清單

- [ ] 七個選項接入正式隊伍介面；六種新形狀在100人畫面上可辨識。
- [ ] 原地／途中／點地拖曳換陣使用原人物與原步進，完全到位而非只更改名稱。
- [ ] 指定陣無空間時清楚拒絕，旧命令與租約可續行；auto 原行為保留。
- [ ] 新形狀不誤走一格平移捷徑；圓陣按槽位朝外；原戰鬥出招仍可接管朝向。
- [ ] preview 唯讀且与正式幾何一致，UI 取消不留下任何正式狀態。
- [ ] 原 Grid 合法 pair／非法循環規則、原移動時間與共享疲勞不被改变。
- [ ] HOLD/MOVE、新舊存檔、傷亡、受控者與拆併規則完整驗證。
- [ ] 100 人狹道、彎道、2/3隊、正式山頂 auto 的原門檻未放寬。
- [ ] 正式 GPU 全景／近景／換陣過程證據與實測耗時齐備。
- [ ] 已實作、已驗證、仍有缺口分開報告，保留每次失敗；未經要求不 stage/commit/push。

## 13. 可直接交給 SOL 的指令

> 先讀 `SITE_TEAM_FORMATION_SWITCH_PLAN_SOL.md`、根 `AGENTS.md`、現行 `PROJECT_ARCHITECTURE.md` 與本輪來源快照，再核對當前 working tree。依計畫在原 TerrainArmy／CombatDeploymentPlan／FormationDestinationPlanner／SiteController／SiteStore 上增加隊伍切換陣型：保留自適應，加入方、錐行、雁行、圓、鉤行、疏六陣。照 P0–P4 完成正式 UI、逐格原地／途中換陣、完整形狀預檢、保存與驗收。不得建立第二套人物、座標、導航、租約或戰鬥權威；不得為指定陣型不足空間默默換成另一形狀。保留所有既有 dirty work、原 0.38 秒步進、合法 reciprocal pair、原測試時限與素材守衛。失敗先保留證據，修原 owner 的範圍內缺陷後有界重驗；最後分別報告已實作、已驗證、仍有缺口，附畫面、量測與檔案清單，不自行提交或推送。
