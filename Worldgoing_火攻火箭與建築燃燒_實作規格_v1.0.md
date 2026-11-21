# Worldgoing｜火攻、火箭與建築燃燒系統
## 實作規格 v1.0／Codex 工作交付版（2026-10-05 第二次審核修訂）

| 項目 | 定義 |
|---|---|
| 文件編號 | WG-FIRE-001 |
| 建立日期 | 2026-10-04（Asia/Taipei） |
| 修訂日期 | 2026-10-05 第二次審核修訂；原檔就地修訂，保留 v1.0 檔名與引用 |
| 文件狀態 | 審核修訂後的功能與工程規格；首次只執行 P0，達到 CONTRACT_READY 才可於後續輪次進入 P1；不代表已實作或通過測試 |
| 交付對象 | Codex／Worldgoing 開發工作者 |
| 目標環境 | 專案指定的 Godot 4.7.2、Forward+；開工先核對 repository 與實際執行版本，不擅自升降級 |
| 戰場基準 | 本案驗收以每隊 100 人、目標 100 支 Formation／近萬人配置；不藉火攻縮減原合法名冊，實際容量與呈現准入由 P0 核對 |
| 第一個可玩交付 | FireLab：弓兵火箭齊射 → 命中引燃 → 建築受損 → 步兵避火／守方滅火 → 殘火冷卻與損壞保留 |
| 本文件不包含 | 專案程式修改、實際編譯紀錄、效能實測或已完成測試聲明 |

> **總原則：火攻是改變戰場、部署與建築功能的系統，不是遠距離點選建築後直接扣血。火箭必須經過發射、飛行、實際命中、有限引燃與火勢累積。**
>
> MUST／不得＝驗收必要條件。SHOULD／建議＝可提出有證據的替代方案。所有遊戲數值均為可調的設計起始值，不是現實燃燒或武器性能數據。

---

## 目錄

1. 範圍、優先順序與版本處理
2. 不可破壞的既有契約
3. 玩家操作與玩法規則
4. 權威資料、模組責任與介面
5. 座標、燃料所有權與分區
6. 固定步進、事件順序與一致性
7. 普通箭／火箭共用投射物管線
8. Formation 齊射與射擊政策
9. 火勢、引燃、傳播與煙霧
10. 建築受損、失能、倒塌與廢墟
11. Formation 避火、容量與尋路
12. 放火、滅火與作業槽位
13. 角色動畫、視覺與操作介面
14. 存檔、Site 卸載與戰後狀態
15. 設定檔與初始調校
16. 效能、GPU Crowd 相容與量測
17. FireLab 場景與驗收矩陣
18. 分階段工作單與交付閘門
19. 完成定義、交付格式與禁止事項
20. 開工待查核項目與風險處置
21. 依據、技術參考與變更紀錄

---

## 1. 範圍、優先順序與版本處理

### 1.1 必須完成的功能

| 需求 ID | 功能 | 本版界線 |
|---|---|---|
| FR-01 | 火箭彈藥模式 | 普通箭／火箭切換、有限彈藥、準備與中止規則 |
| FR-02 | 真實遊戲投射流程 | 具飛行時間與散布；以實際第一命中物結算，不追蹤目標、不穿牆點火 |
| FR-03 | 隊伍火攻 | Formation 指定建築／區域射擊、非全員同步鎖死的齊射、引燃後停射 |
| FR-04 | 地表火勢 | 有限燃料、受熱、引燃、蔓延、餘燼、冷卻；風雨是輸入參數 |
| FR-05 | 建築燃燒 | 少量分區；結構、燃料、內容物、功能與燃燒狀態分離 |
| FR-06 | 火災危害 | 火傷、短暫灼熱、有限時效角色著火、煙霧視線乾擾、倒塌警戒 |
| FR-07 | Formation 應對 | 避火、緊急撤離、部分重新部署、受困回報，沿用既有中央移動 |
| FR-08 | 接近作業 | 少量成員使用放火／滅火槽位，有限補給、可中斷與撤離 |
| FR-09 | 世界變化 | 城門毀損開通、局部倒塌、廢墟與建築功能停用 |
| FR-10 | 持久化 | 存讀檔、Site 卸載後活動火災接管、跨區事件去重、戰後焦痕與損失 |
| FR-11 | 表現與量測 | 近遠景分級、原有 Near 預算不膨脹、可重現壓力測試與 HUD |

### 1.2 第一個可玩版本與完整 v1.0 分開驗收

第一個可玩版本稱為 **M1 最小閉環**：一支百人弓兵、一支百人步兵、木屋、石牆木門、可燃地表、窄道，以及基本滅火與避火。M1 必須由射出火箭開始，不接受只用 debug 指令直接點燃的展示。

完整 v1.0 另外包含多分區建築、跨隊作業、接近放火、停射政策、風雨遮蔽與煙霧整合、讀檔與卸載、萬人壓力測試。M1 只要求一個真正到位、有限補給、可中斷的基本滅火槽；各功能階段以第 17.1、18 節共同界定。不得把 M1 通過描述成完整 v1.0 通過。

### 1.3 明確不做

不做真實流體煙氣、氧氣與化學燃燒、爆炸與炸藥、遠距飛火／火旋風、每根木板剛體破碎、完整室內消防導航、提水接力物流、全新資源製造鏈、因著火強制所有兵升成 Near Actor，以及新的多人連線同步架構。

火攻補給和火箭彈藥為遊戲抽象資源。本功能不重新引入舊 Multi-Society Simulator 的封閉世界或全資源來源追溯規則。

### 1.4 規格優先順序

1. 使用者在實際工作對話中明確作出的新決策。
2. `AGENTS.md`、`PROJECT_ARCHITECTURE.md` 與現行程式的核心權威、移動、安全性及渲染契約；發現文件與程式不符時須記錄並核對證據。
3. 本文件的火攻目標與 MUST 驗收；不得將本文件本身當作靜默取代正式普通箭、存檔或移動契約的授權。
4. 歷史設計參考、可調數值與建議檔名；未實作的內容不得視為現況。

本次修訂只更新計畫。曲線掃掠與實際接觸是火攻整合目標；普通弓弩如何由現行落點機率制遷移，須在 P0 形成明確決策紀錄。已有使用者決策可直接引用，不重複要求確認；若會改變尚未定案的正式玩法，P0 列為待決事項，不自行用 adapter 掩蓋。

本文件參考既有移動 v3 文件的中央仲裁、持久部署與預算設計 [P1]，並保留後續討論的靜態步進、Aging、權威提交與 GPU Crowd 限制 [P2]。兩者衝突時，P0 工作單必須記錄現況與最小適配方案，不得藉火攻任務重寫全部移動系統。

既有 v3 曾禁止雙人交換；後續曾討論友軍交換與 Dynamic Re-formation。本任務**不新增也不擅自關閉交換能力**，沿用目前通過驗證的仲裁規則。

---

## 2. 不可破壞的既有契約

| 契約 ID | 必要條件 |
|---|---|
| INV-01 | 每個 Site 只有一個權威移動仲裁入口；Formation 只能提出移動方案，不能互相裁決佔用。 |
| INV-02 | 維持 `Prepare → Propose → Resolve → Commit → Finalize`；authoritative cell、occupancy 與持久槽位由既有 owner 管理。 |
| INV-03 | 同一有效成員只有一個權威位置；既有單格佔用限制不得因避火或滅火例外而失效。 |
| INV-04 | 移動快取前進／pop 僅在原權威完成屏障確認承諾步實際抵達後執行。現行 GD 的 Finalize 只確認承諾步，落格與路徑消費由 `complete_committed_moves` → `finish_committed_move` 負責；不得提前 pop 或把原步進壓成單 tick。 |
| INV-05 | 火災是動態危害，不直接改寫靜態地形通行。只有原資源實體（如樹木）、城門／建築／殘骸真正改變阻擋時，才沿原 owner 修改靜態障礙。 |
| INV-06 | 靜態反向搜尋使用既有方向契約；若介面為 `can_step_static(neighbor, current, profile)`，不得反轉參數破壞上下坡可達性。 |
| INV-07 | 保留 Site／Formation 尋路預算及 Aging：呼叫次數與擴展數各自保留至少 50% 給 Aging，先執行 Aging；無需求時才依既有規則借用。 |
| INV-08 | 火災緊急優先權不能吞掉 Aging 保證，也不能用增大 A* 全域上限掩蓋死鎖。 |
| INV-09 | MOVE 不因目的地容量不足而直接拒絕；保留合法分批部署、入口與排隊策略。HOLD 後仍維護安全部署。 |
| INV-10 | 穩定 `member_id`、`formation_id`、`building_id` 與命令序號持久化；不得用 roster index／Godot instance ID 作永久身份。 |
| INV-11 | 畫面、動畫、鏡頭、粒子、LOD 與是否看得見，不決定命中、火勢、傷害、佔用或補給消耗。 |
| INV-12 | 一般兵著火不觸發強制 Near promotion；維持實際已准入的 Near 上限。本規格原設計值 64 須由 P0 對照，不據此新增呈現分層或擴大更嚴的現有限制。 |
| INV-13 | 燃料與結構各只有一個權威 owner；投影到危害格不得複製燃料或重復扣同一筆建築傷害。 |
| INV-14 | 一次事件只結算一次；存讀檔、卸載、重試、視覺回呼不造成重複發射、命中、引燃或物資損失。 |
| INV-15 | 相同版本、設定、seed 與命令時間序列，權威結果不因畫面幀率、LOD 或資料遍歷順序改變。 |

INV-01～03、09～10 的歷史依據見 [P1] 第 2、3、16～18 節；INV-04、06～08、12 與 GPU 分層限制來自後續專案討論 [P2]。這些是需驗證的整合約束，不是本文件已驗證程式符合的聲明。

---

## 3. 玩家操作與玩法規則

### 3.1 指令模型

不建立與現有主命令競爭的第二套命令 owner。由現有 Attack／Work／CombatOrder 介面承載或轉接：

| 指令／設定 | 語意 |
|---|---|
| `AmmoMode.NORMAL / FIRE_ARROW` | 同一遠程兵種的彈藥模式；只有具備能力且有對應庫存者可選。 |
| `TARGET_ENTITY` | 指定建築、分區、城門、設施或敵方 Formation；仍需合法瞄準點。 |
| `TARGET_AREA` | 指定有邊界的區域；分配成員瞄準點，不代表區域自動受傷／起火。 |
| `FirePolicy.IGNITE_ONLY` | 達穩定燃燒條件後暫停／轉換合法分區，考慮在途火箭。 |
| `FirePolicy.DESTROY_FUNCTION` | 持續至指定功能停用或目標失效，不預設整棟必須夷平。 |
| `WorkOrder.IGNITE / SUPPRESS` | 接近放火／滅火，使用作業槽位與有限補給。 |
| `HazardPolicy.AVOID / EMERGENCY_ESCAPE` | 一般避險／緊急最低風險逃生；不等同戰場 RETREAT。 |

不自動把用完的火箭改成普通箭，除非原命令明確允許 fallback；預設暫停並顯示彈藥不足。更改彈藥模式只作用於尚未釋放的箭。

### 3.2 平衡規則

火箭不是普通箭的全面升級。傷害、射程、裝填／準備、散布均由共用 WeaponProfile 決定；首版可使用「較長準備、相同或較低直接傷害、額外有限引燃量」。不設定歷史性能數字。

火焰與落箭不分敵我。友軍可以阻擋、受傷及因落點起火而必須繞路；第一版不加入陣營免疫。火箭不能自帶爆炸範圍傷害。

### 3.3 必須提供的失敗原因

至少區分：`NO_AMMO`、`UNSUPPORTED_AMMO`、`OUT_OF_RANGE`、`NO_VALID_AIM_POINT`、`LINE_OF_FIRE_BLOCKED`、`SCHEDULER_DEFERRED`、`CAPACITY_DEFERRED`、`TARGET_INVALIDATED`、`NO_WORK_SLOT`、`NO_SUPPRESSION_SUPPLY`、`NO_SAFE_ROUTE`、`TRAPPED_DYNAMIC`、`STATIC_BLOCKED_CONFIRMED`。

局部搜尋耗盡預算不等於靜態無路；暫時無安全路線也不等於沒有合法地面。介面需顯示「等待射擊位置」「火勢封鎖安全路線」「地形真正阻斷」等不同資訊。

---

## 4. 權威資料、模組責任與介面

### 4.1 模組所有權

名稱為建議；已有等效模組時直接擴充，不平行建立第二份 state。`BuildingZoneState.structure_hp` 必須引用／映射原 `feature.parts`，不得另存一份可獨立寫入的 HP。燃料依第 5.5 節掛在原資源／部件身分上。

| 模組 | 唯一負責 | 不得負責 |
|---|---|---|
| `CombatProjectileSystem` | 箭矢資料、發射交易、飛行、第一命中、事件序號 | 直接控制建築火勢或人物格位 |
| `FormationRangedController` | 瞄準分配、齊射窗口、射擊政策、在途投入估算 | 每人獨立重算全場戰術、跳過移動仲裁 |
| `SiteFireSystem` | 可燃單元熱量／燃料、接觸火源、傳播、冷卻 | 建築功能、權威 occupancy、視覺動畫 |
| `BuildingDamageSystem` | 結構／內容物／功能／倒塌事件 | 複製可燃分區燃料、直接依粒子命中扣血 |
| `HazardField` | 危害投影、局部版本、暴露與路徑風險查詢 | 成為第二份燃料或建築 HP |
| `FormationHazardController` | 避火、緊急撤離、槽位安全檢查、作業者分派 | 直接改 cell、傳送、私自取消全隊命令 |
| 既有移動 Coordinator | 提案仲裁、佔用、部署槽位、路徑預算 | 逐幀模擬粒子 |
| `CombatWorkSystem` | 放火／滅火工作、作業 lease、補給提交 | 無槽位隔牆作業、重複消耗 |
| 既有存檔／世界模擬 owner | 火災狀態保存、跨 Site 接管與時間 | 以場景節點是否存在判定世界狀態 |
| `FireVisualRenderer` | 粒子、面片、箭尾焰、焦痕與外觀 LOD | 判定任何權威結果 |

### 4.2 資料流

```text
玩家指令 → 既有 Order owner → Formation 射擊／作業控制
                      ↓
           投射物發射與實際接觸事件
                      ↓
        SiteFireSystem ↔ BuildingDamageSystem
                      ↓
                 HazardField
                      ↓
       FormationHazardController → 既有移動 Coordinator
                      ↓
             唯讀呈現快照／存檔快照
```

### 4.3 最低資料結構

以下是欄位契約，不是要求每筆資料實例化為 Node 或 Resource。

| 資料 | 必要欄位 |
|---|---|
| `FireUnitKey` | `world_partition_id`, `surface_id`, `owner_kind`, `owner_id`, `local_zone_id` |
| `BurnableState` | `profile_id`, `fuel_remaining`, `heat`, `moisture`, `burn_state`, `scorch_amount`, `last_sim_time`, `revision` |
| `FireContact` | `contact_id`, `source_projectile_id`, `target_fire_unit_key`, `remaining_heat_budget`, `heat_rate`, `expires_at` |
| `ProjectileState` | `projectile_id`, `source_member_id`, `source_formation_id`, `order_serial`, `ammo_profile_id`, `spawn_tick`, `position`, `velocity`, `life_remaining`, `ember_heat_remaining`, `resolved` |
| `ProjectileImpactEvent` | `event_id`, `projectile_id`, `impact_tick`, `impact_fraction`, `target_key`, `target_component`, `hit_position`, `damage_payload`, `ignition_payload` |
| `BuildingZoneState` | `building_id`, `zone_id`, `fire_unit_key`, `structure_hp`, `contents_integrity`, `function_state`, `collapse_state`, `topology_revision` |
| `HazardCell` | `surface_id`, `thermal_damage_rate`, `smoke_density`, `collapse_risk`, `risk_band`, `revision` |
| `FormationHazardState` | `formation_id`, `hazard_response`, `suspended_order_serial`, `affected_member_ids`, `safe_goal`, `safe_since`, `observed_revisions` |
| `WorkSlotLease` | `slot_id`, `target_key`, `member_id`, `order_serial`, `expires_at`, `approach_cell`, `work_facing`, `escape_anchor` |
| `ExposureRecord` | `member_id`, `interval_id`, `thermal_dose`, `direct_contact_dose`, `applied_event_watermark` |

永久 ID 使用既有安全序列化型別；若採 JSON，避免把 64-bit ID 經不保證精度的數值解析，建議 ID 以字串保存。參數組合保存 `config_hash`，存檔保存 `schema_version`。

### 4.4 概念介面

```text
request_projectile_release(release_request) -> ACCEPTED | reason
query_first_hit(sweep, collision_snapshot) -> HitResult
enqueue_impact(impact_event) -> ACCEPTED | DUPLICATE | INVALID_TARGET
register_burnable(owner_key, profile, initial_state)
submit_ignition(ignition_event)
submit_suppression(suppression_event)
advance_fire_to(authoritative_time) -> FireDelta
sample_hazard(surface_id, position_or_cell) -> HazardSample
integrate_exposure(member_motion_segment, time_interval) -> ExposureDelta
collect_changed_hazard_regions(since_revision) -> RegionDelta
request_hazard_response(formation_id, risk_snapshot)
request_topology_change(building_transition) -> queued_event
capture_fire_snapshot(at_commit_boundary) -> SavePayload
```

每個入口須檢查 ID、命令序號、時戳與重複事件。無效／已銷毀目標不得觸發隱式新建燃料。

### 4.5 目前責任對照與後端准入

以下為 2026-10-05 靜態查核的原始碼入口，供 P0 重新核對；不是執行驗證或火攻完成聲明。

| 路徑 | 現有責任／入口 | 火攻接入要求 |
|---|---|---|
| GD Actor／Army 普通弓弩 | 原人物 `ranged_fire` 與本人 cargo；`TerrainLab._advance_ranged`／`SiteCombatRules.ranged_result` | 明列原落點機率制如何遷移；不讓新 pool 與原 flight 各算一次 |
| Native Crowd | `CrowdSite.step` → `ArmyCrowd.step_clock`；`native/crowd10k/src/combat.cpp` 的 `ranged_commit`／`projectiles_advance` | native CPU 具有玩法權威，不是單純 GPU 呈現；準入前完成彈藥投影、火箭模式與事件回寫 |
| 攻城投射物 | `TerrainLab._advance_siege` 與原集中飛行、接觸結算 | 保留原攻城 owner；可共用經核對的純查詢，不能直接把逐箭全人物掃描搬成萬人方案 |
| 移動 | `SiteCombatMovementCoordinator`／原 Reservation Grid、Army 承諾步 | 延伸原完成屏障及 motion 資料，不把接受提案視為已落格 |
| 建築／資源／庫存 | `SiteRuntime`、`SiteEnvironment`、原 `features.parts`／holder | 原交易提交 HP、燃料對應、資源與物資變更 |
| 保存與冷補算 | `SiteStore`、`SiteController.supply_save_guard`、`RegionSaveSlot._settle_cold_candidate` → `TerrainLab.advance_cold_site`／`replay_site_to` | 擴充原候選驗證、原 shared step 與原子替換；不另建世界或保存權威 |

P0 對 GD Actor、GD Army、Native Crowd、攻城路徑分別記錄 `SUPPORTED / GUARDED / BLOCKED`，列明本階段唯一的發射、扣彈、飛行、命中、傷害 owner。只有各自功能測試通過才可標 SUPPORTED；未支援者由原入口明示拒絕或沿原安全交接轉回已支援模式，拒絕不得改原人、原物、命令及現場。不得默默回到舊箭規則卻仍顯示 FIRE_ARROW 成功。

P1 至少要完成原 GD Actor／Army 的 FireLab 路徑及未准入後端守衛；後續每階段都對其准入後端驗證新增功能。P6 是萬人效能與全部准入的最終關閉點，不能把 P1～P5 的 owner 衝突延後到 P6。GD↔Native 切換時，所有新在途箭、射擊預約、火場、接觸與工作狀態須可完整交接；未具備能力時保留現場並拒絕切換。

---

## 5. 座標、燃料所有權與分區

### 5.1 座標

地圖平面座標轉到 Godot 3D 戰鬥平面時使用專案既有轉換服務；不得在各系統自行假設一格為一公尺。火勢格網第一版對齊現有 Site 戰術導航格，不用 Region 的 100m 大格。

`surface_id`／高度層是必要欄位。同一平面格上的屋頂、屋內、地面、橋面與橋下不可自動合併成同一燃燒／命中／危害單元。

建議資料區塊 `16×16` 格；這只是儲存與更新分組，不更改導航解析度。跨區座標需涵蓋負座標與穩定世界座標。P0 需記錄目前 Site 尺寸與單格尺度。

### 5.2 何者有燃料

LAND、ROCK、FRESH_WATER、SALT_WATER 等底層地形不因類別名稱就有燃料。地表植被、木製設施、帳篷與建築分區提供燃料；裸土、裸岩與水面預設沒有持續燃燒燃料。

同一格可以有多個可燃 owner，但每份實體燃料只能註冊一次。例如樹木既由 TreeState 持有，就不得在 ground patch 再算同一份木材；建築屋頂也不能同時登記成建築燃料與地表木材。

角色第一版的著火是有限時效的狀態效果，不加入可向全隊傳染的地表燃料網路。

### 5.3 四種簡化燃燒設定檔

| Profile | 對象 | 行為定位 |
|---|---|---|
| `GROUND_VEGETATION` | 已存在的草叢／作物／灌木 | 相對易引燃、燃料量較少 |
| `WOOD_COMPONENT` | 木門、木牆、木屋等 | 需累積引燃，持續燃燒損害對應構件 |
| `FABRIC_STRUCTURE` | 帳篷／遮棚 | 起火後較快失去功能，殘骸規模小 |
| `NON_COMBUSTIBLE` | 裸岩、石牆等 | 不提供燃料；木門、屋頂、內容物是別的 owner |

Profile 不是新增開採資源。石造建築可包含木屋頂，但石牆本體首版不因表面火焰直接燃燒殆盡。

### 5.4 傳播圖與導航圖分開

```text
人能否走：can_step_static + movement profile
火能否傳：fire_edge(from_fire_unit, to_fire_unit)
煙能否通：smoke_edge(from_surface, to_surface)
箭能否過：projectile collision／sweep
```

地表第一版採四鄰接；必須檢查高度差、阻隔邊與顯式連接。禁止單純以 XY 鄰近跨越峭壁或石牆。建築內部分區使用作者定義的連接；沒有連接就不傳播。

屋頂火的地面危害投影、建築輻射／接觸熱範圍由資產明確定義，不能整棟 footprint 全部視為腳下火焰。倒塌時才依狀態變更新增地面殘火。

### 5.5 燃料、採集、再生及付費修復

`FireUnitKey` 必須引用原資源 key 或 `feature_id + part_id`，並保存該實體的有效 generation／revision。燃料是原實體狀態的擴充，不是可與原 `remaining` 分開生產物資的第二份帳本；也不直接把一個 heat 單位當成一個木材庫存。

- 可燃自然資源由 profile 定義原 `remaining` 與可燃量的有界映射，包含整數資源與小數燃料間的累積餘量。只適用已註冊的可燃部分；石礦、水、魚或地下儲量不能因同格火勢一起刪除。
- 同一提交邊界先彙整該實體的燃燒損耗，再由原採集／清地交易重驗剩餘可採量及版本。燃燒不產出可用木材，採走部分必須同步退出該火源的可燃量；不得各讀一次舊值後重複消耗或產物。具體換算與 rounding 由 P0 登記，P2 驗收前完成測試。
- 清地、移除或 generation 改變時使舊 contact 與事件失效；原熱量若需留下殘火，只能經第 10.4 節同類有限移交交易，不能隱式補生 fuel。全耗盡後仍由原 recovery 規則決定是否／何時再生。燒耗造成原可採性或樹木等實體阻擋改變時，沿 `SiteEnvironment`／`TerrainData` 原索引與局部通知提交；一般 heat 波動不改靜態圖。
- 再生沿 `SiteRuntime._regenerate`／`SiteEnvironment` 原入口，只為實際新增的可燃資源增加對應 fuel；尚有熱量、接觸或火勢待提交時延後該可燃部分的再生，不能一面補滿一面燃燒。焦痕不因再生被無條件清掉。
- 修復沿原扣料與工時交易。P2 拒絕對尚熱或待倒塌部件開始修復；已備料作業途中起火／待倒塌時暫停，保留已付料及進度，或沿原取消／退款規則處理。完工前重驗冷卻、原部件身分與版本；成功才按實際付料、實際完成修復量增加設定允許的燃料，上限為該部件完整值。P0 記錄修復量到新增 fuel 的映射；不得在 request、重送完成事件、免費恢復外觀時補滿，也不能對已替換的部件補 HP／fuel。
- 同 ID 升級、清理與重建沿原合法世界變更，明定剩餘 fuel、heat、焦痕及新 generation 的去留；原事件不能加熱已被替換的新實體。燃燒後付費修好的木門必須能再次被引燃。

P2 的最小資產應選已存在且可映射的可燃資源與木門，不能為了測試虛構正式 `TreeState` 或草地資源 owner。

---

## 6. 固定步進、事件順序與一致性

### 6.1 時鐘與時間單位

現行專案同時有共同動作秒 `elapsed` 與 Site 遊戲秒 `SiteRuntime.game_seconds(elapsed, combat_left) × simulation_speed`；和平期遊戲秒可為動作秒的 60 倍。此修訂將火攻戰術效果統一使用原共同動作秒，不新增獨立時鐘，也不讓既有經濟倍速加快箭的飛行或耗盡 ember。

| 資料／效果 | 權威時間域 |
|---|---|
| 箭飛行、射擊準備／窗口／冷卻、`life_remaining`、空中 ember 衰減 | 原 action tick／動作秒 |
| 火勢／煙 5Hz、`fire_dt`、contact `expires_at`／有效供熱時間、燃燒與角色火傷 | 原動作秒；每 0.2 動作秒提交一次火勢 |
| 暴露積分、角色著火時限、倒塌倒數、避火 0.5／安全恢復 1.0 秒 | 原動作秒，motion interval 使用同域 |
| 放火／滅火有效工時、補給扣量、工作 lease 時限 | 原動作秒；沿原 action owner 排他處理 |
| 天氣歷程、未活動物件潮濕補算、原資源 recovery／經濟生產 | 原 Site 遊戲秒；有版本與明確起迄時間 |
| 火攻 `spawn_tick`／`last_sim_time`／事件有效 tick／watermark | 明標 action tick 或 action seconds；不得把 Site minute 直接代入 |

`fire_action_cursor` 與 accumulator 只是對原已完成動作區間的進度紀錄，不自行前進或成為第二個時間 owner。風雨參數從同一區間的 Site 遊戲時間查得，供熱／冷卻等 tactical rate 仍只乘 action dt；不同單位不得隱式相乘。保留兩種時鐘及原 `simulation_speed` 行為，不改專案物理 tick rate。

只要已提交狀態中仍有在途火箭、有效 contact、明火／餘燼、未冷卻熱量、受火角色或待提交倒塌，原 Site 的危害活動判定就維持既有 `combat_left`，避免自然跨入和平 60 倍。純焦痕或已冷卻廢墟不維持此狀態。`simulation_speed` 仍按現行規則影響 Site 遊戲時間，並不加速動作秒。

維持危害活動必須發生在原共同步計算遊戲秒之前；現場、直接 combat 入口與 `replay_site_to` 反算動作步必須使用同一 predicate。首次敵對行動沿原中止規則處理；持續續期不得每步清空 `manual.target`／`manual.progress`。可在原 `SiteRuntime.mark_combat` 增加保留手工作業的續期選項，舊 caller 預設行為保留，不新增平行時計。真正移動、受擊或工作位置失效仍按原 action owner 中止。

**跨 Site 共同時間尚須 P0 定案。** 現行 `RegionSaveSlot.record_completed_active_step` 將活動 Site 的遊戲秒發布為共同時間，`TerrainLab.replay_site_to` 再用冷 Site 的 `combat_left` 反算動作秒。若活動和平 Site 在 1 動作秒發布 60 遊戲秒，持續交戰倍率的冷火場就可能補算 60 動作秒；留在火場卻只前進 1 動作秒。相同 predicate、保存 action cursor 或只記錄 `simulation_speed`，均不足以解決這個跨 Site 差異。

P0 必須在原世界／保存 owner 內定義共同 action／game 區間的來源、發布與補算映射，說明離屏危害是否影響共同倍率、Site 切換及最後火源冷卻時如何交接，並用上述雙 Site 數值案例證明第 14 節的一致性可成立。保留單一世界時間 authority；不得另建自行前進的火攻時鐘，也不預設所有 Site 因遠處餘燼一律減速。這是尚未定案的玩法／權威契約，不能只寫「P5 再處理」就標 `CONTRACT_READY`；P1～P4 仍受第 14.0 節交接守衛約束。

**危害續期的既有玩法影響也須定案。** P0 列出全部 `combat_left` consumer，至少包含整隊疲勞恢復、作業、訓練、保存及旅行資格。現行 `_advance_team_fatigue` 將脫戰作為整隊恢復必要條件，`SiteWorkTeam` 疲勞達 80 後等待降至 50 復工；持續餘燼可能使安全區隊伍一直不能輪休。必須明定這是否為預期玩法：若維持全 Site 禁止恢復，記錄此限制及冷卻後復工；若允許安全區休息，在原 owner 內區分時間倍率與休息資格，重驗局部危害、敵人、移動及有效工作，不能直接視為安全。逐一交代 Actor／Army／Native 行為，不以保留 manual 進度代表已處理全部影響。

戰鬥頻率若可整除 5Hz，使用整數 tick 間隔；否則沿原共同步使用確定性的整數／有理數累加器。禁止直接累加渲染 `_process(delta)`、wall-clock 或視覺 callback 決定權威火勢。未到火勢更新點時使用最近已提交危害；新引燃於下一火勢提交點生效，最多延後 0.2 動作秒。

P0 必須把上述欄位映射到真實 symbol；P1 起測 0.5／1／2／4 倍速、`combat_left` 跨零、暫停與慢幀。相同 action 區間、天氣及命令輸入下，飛行／ember／供熱／火傷不因 Site 經濟倍速多乘一次；P5 再證明保存與冷補算的雙時間對齊。

### 6.2 建議整合順序

以下規定可觀察的順序；實際函式放置由 P0 對照既有 combat owner。不得建立能同時改 occupancy 的第二個 coordinator。

1. **邊界處理**：在本 tick Prepare 前，提交上次結束產生的死亡移除與建築拓撲事件，重建必要佔用／碰撞快照。
2. **固定快照**：記錄本區間的靜態碰撞、危害、角色權威狀態與有效命令；所有查詢使用明確版本。
3. **發射與工作決策**：以區間起點狀態接受發射交易／作業準備。成功 release 才消耗彈藥，新增箭矢自起點飛行；動畫不參與確認。
4. **移動與完成屏障**：既有 Coordinator 執行 Prepare／Propose／Resolve／Commit／Finalize，新接受者只啟動原承諾步；原人物照原 duration 推進，原 `complete_committed_moves` 在完成時原子落格。motion segments 必須涵蓋前 tick 已承諾、正在進行或本區間完成的步。沒有在途步且新提案被拒者才是靜止；不得把「本 tick 沒有新接受提案」當成未移動。
5. **投射與暴露**：依本區間靜態快照及 motion segments 掃掠，產生命中；積分既有危害暴露與有效工作時間。
6. **火勢邊界**：到期時，以唯讀舊火勢與已到時戳的事件計算下一快照；新點燃單元本次不得再向外傳播。
7. **傷害與狀態提交**：區間末統一套用有效傷害、工作消耗、建築功能與倒塌排程。死亡與障礙變更在下一次 Prepare 前完成 barrier，不修改正在 Resolve 的快照。
8. **保存與呈現**：在完整提交邊界輸出快照。P5 正式保存包含尚待邊界處理的事件，不保存半套 Commit；P1～P4 先按第 14.0 節守衛拒絕不完整保存及交接。

若現有 combat framework 已有不同但等價的階段，沿用現有順序並寫下等價證明／測試；不得在各 Node callback 中自由執行。

這是固定步進遊戲模型：同一 tick 內移動與受傷在邊界結算，不宣稱完整連續事件物理。第一命中仍須取掃掠內最早接觸，不能因陣列順序射到後面的人。

### 6.3 雙緩衝與穩定排序

火勢更新必須讀 old buffer、寫 new buffer；傳播讀舊狀態、收集增量、再統一提交。固定方向順序與 stable ID 排序，浮點聚合不得依 Dictionary 遍歷順序。

抽樣散布使用與美術 RNG 隔離的穩定亂數子流，例如由 `(world_seed, formation_id, order_serial, volley_id, member_id, shot_index)` 產生。不得用 wall-clock、顯示幀、Godot instance ID 或鏡頭距離作種子。

首版要求相同平台／build 的重播一致；跨 CPU／GPU 的 bitwise determinism 不宣稱已具備。涉及浮點或 GPU reduction 時必須定義量化及容差，不能只比較看起來相似。

### 6.4 事件一致性與負載

事件使用唯一 ID 與 producer sequence；消費端保存 watermark 加上尚未連續到達的少量 ID，或等效去重方式。去重表不能無限增長。

超載時不得跳過燃燒單元、丟棄已釋放箭矢、停止看不見的火或放大 dt。先降視覺成本；權威工作若需分 slice，保持同一提交邊界及積欠計數，未算完不得局部發布。

投射物容量上限是固定設定，不由當下 FPS 改變。達上限時，未釋放射擊回傳 `CAPACITY_DEFERRED`，不扣彈藥；已接受的 projectile 不可回收作為新箭。

---

## 7. 普通箭／火箭共用投射物管線

### 7.1 彈藥與發射交易

已查到正式普通弓弩；須沿第 4.5 節原 owner 擴充，不以「沒有箭矢系統」重建。禁止平行建造火箭專用遠距點火系統。以下是目標管線，P1 前須完成本節規則遷移決策。

**普通弓弩規則遷移閘門：** 現行 `SiteCombatRules.ranged_result` 以能力、訓練、疲勞、距離、移動、盾牌、護甲及技能擲骰判 miss／graze／hit；其正式格射線不能宣稱已等價於第 7.3 節的逐步掃掠。P0 必須列出 NORMAL 弓箭、弩矢、FIRE_ARROW 的遷移範圍及每項因素的新責任：哪些轉為散布／瞄準，哪些留在接觸後防護／傷害，擦傷如何判定。

同一因素不能無決策地在散布與原擲骰重算；也不能為接上 sweep 靜默刪除既有因素。須決定「實際碰撞但防護完全擋下」「擦傷」「完全未接觸」分別如何處理 kinetic 與 ignition。未接觸者不得對原目標給 heat；接觸盾牌時的 direct-contact dose 必須按其 profile 處理，不把原機率 miss 偷改成穿透。P0 記錄明確決策與受影響的舊測試斷言；若玩法決策尚缺，狀態為 `CONTRACT_BLOCKED`，不能自行寫一組新平衡並宣稱 P1 可開工。

**本人彈藥：** release 只扣原持有人 cargo 內所選 ammo item；切換 NORMAL／FIRE_ARROW 不建立 Formation 公共彈匣、不免費轉移或轉換普通箭。準備中的預約與 ammo mode／order serial 綁定，改模式須取消舊預約並重驗新庫存。Native 的單一 ammo 投影及回寫必須先具備兩種 item 的無損契約才可准入，不能把未選中的彈藥刪掉或回寫成另一類。

```text
驗證成員存活、能力、命令序號、彈藥、射程、瞄準點與容量
→ 保留可釋放配額
→ 發射交易提交：扣一支彈藥＋產生唯一 projectile
→ 發出動畫／音效呈現事件
```

預約不等於消耗。準備中死亡、中止、改令或失去合法射擊條件，釋放 reservation；放箭後不退還彈藥。讀檔或動畫重播不得再次扣除。

死亡者已射出的箭繼續存在；發射後改令不使箭消失。暫停停止遊戲時間，包括箭飛行與火勢。

同一持有人彈藥的重入請求由原交易保證只扣一次；跨 Formation 的 projectile 容量競爭使用既有公平排程，或穩定的 Formation epoch round-robin；不得每輪都按低 ID 優先，使尾端隊伍永久無箭可射。延後的 release 不累計移動 stall，且受原命令截止時間約束。

### 7.2 飛行

使用現有 WeaponProfile 的初速／重力／弧線與遊戲尺度。沒有既有彈道時先實作無追蹤的簡化拋物線，並把速度、重力、射程與散布存於設定檔。

射前可以作基本目標預測，但出手後不更新方向追蹤目標。視覺曲線與權威曲線來自同一參數，不得用漂亮弧線掩蓋邏輯直線穿牆。

火箭在空中的 ember budget 依共同動作秒衰減，雨作為帶版本的係數輸入可加速衰減；飛太久可能只剩普通箭傷。飛行和接觸供熱共用同一份有限預算，不能落地重新充值。

### 7.3 碰撞與第一命中

每個固定步進對 `previous_position → next_position` 進行掃掠；不得只在終點測試。曲線段用有誤差上限的細分或等效方法，不能一個大線段直接跨過低牆。

Broad phase 使用既有空間索引／分區；narrow phase 使用資料碰撞代理，不要求一萬名一般兵各建一個物理 Node。處理相對運動：人物位移由權威 motion segment 提供，不能使用畫面插值位置。

命中排序：先按最早接觸時間，再用 stable collider key 作同時事件 tie-break。盾牌、人物、建築、地形、水面以既有碰撞層和 profile 決定，不因陣營忽略。

首版箭矢第一命中即終止飛行；不做穿透、反彈與一箭多目標。發射者的起點避碰僅限必要的出生距離／時間窗口，不能永久忽略全隊友軍。起點在牆內時應拒絕發射或立即命中，不准穿出牆外。

發射原點、盾牌朝向與人物碰撞代理來自權威姿勢／朝向與武器 anchor，而非當前畫面動畫幀。相同裝備與邏輯狀態的碰撞規則不因 REGULAR／SPECIAL 或 Near／Far 切換而改變；不能近景用精細骨骼命中、遠景就直接忽略盾牌。

### 7.4 命中結果

| 第一接觸 | 直接效果 | 引燃效果 |
|---|---|---|
| 木門／木構件 | 共用武器傷害管線 | 對實際分區給有限 heat payload |
| 可燃屋頂／帳篷 | 該分區有效命中傷害 | 只加熱該分區，後續傳播走建築連接 |
| 石牆／裸岩／裸土 | 依既有可破壞規則；非目標可為零傷害 | 無燃料即不生成持續火格 |
| 植被 | 依物件規則 | 實際落點有燃料才可引燃 |
| 人物／盾牌 | 先處理護甲、盾牌和箭傷 | 有限 direct-contact dose；是否著火另判 |
| 水面 | 結束箭矢 | 熄滅 ember，無水面火焰 |
| 出界／壽命到期 | 依專案邊界政策結束或移交相鄰分區 | 不在指定目標位置補一次命中 |

瞄準目標未命中時，仍處理實際落點。被牆攔截不得將原定目標當成 ignition target。目標在飛行期間倒塌時，下一 tick 查詢新拓撲，不追著已不存在的瞄準點結算。

### 7.5 接觸火源

有效可燃接觸可建立 pooled `FireContact`，其熱量輸出滿足：

```text
q = min(remaining_heat_budget, heat_rate × valid_contact_action_seconds)
remaining_heat_budget -= q
```

到期、預算歸零、目標失效或落入水中即結束。尚未耗盡的熱量不自動轉移到其他不相乾物件。多支接觸火源可聚合提交增量，但事件 ID、來源和總預算需可驗證。

每支箭只有一次 kinetic hit；後續 contact heat 不是再次箭傷。角色著火狀態、地面火焰與直接接觸傷害是不同 exposure channel，同一來源同一時間片不得重複套用。

---

## 8. Formation 齊射與射擊政策

### 8.1 隊伍決策、成員執行

本案驗收的 Formation 配置為每隊 100 人，組成仍是隊長、零至數名幹部與士兵；不是修改原合法名冊上限的授權。Formation 決定目標、彈藥模式、射擊節奏與工作分派；成員保有裝填、有效射擊條件與實際命中資料。

不得把一支 Formation 的齊射直接換成對建築的一次抽象大傷害，卻仍宣稱每箭有獨立命中。第一版每支已釋放箭保有邏輯記錄；視覺可批次化或減少尾焰。

### 8.2 瞄準點

建築提供外露 `AimPoint`／`AimSurface`：對應 zone、材質、世界位置／範圍、高度與有效條件。點選建築後依命令政策、可見性、射程及阻擋選點，不能固定射向建築中心或封閉牆後庫存。

區域射擊依 stable member ID 分配分層散布點，再套武器散布；不得所有箭共用完全相同落點，也不得將玩家框選範圍當作必然命中的地面火圈。

射擊判斷沿用既有視野／戰爭迷霧。IGNITE_ONLY 不能讀取不可觀測屋內的真實熱量作作弊停射；FireLab debug 可顯示完整資料，production UI 不可洩漏隱藏狀態。

### 8.3 齊射窗口

每輪建立 `volley_id`、開始 tick、釋放窗口、截止 tick、預備成員名單。已準備完成且仍合法者在窗口內發射；被阻擋、死亡、缺彈藥者跳過本輪，回報原因。

截止後不等待全員準備，也不補發過期命令。重新尋找射擊位置要走原本移動提案與配額，不得為後排一人卡住整隊。高拋可以越過某些遮擋，但仍檢查完整弧線。

首版不允許邊跑邊釋放箭：成員需滿足本區間射擊姿態條件；預備可以中止。未來移動射擊以 WeaponProfile 擴充，不能讓 LOD 決定誰能移動射擊。

### 8.4 在途投入與停射

維護每個可觀測目標分區的 `pending_ignition_estimate`：來自已發射、尚未結束且預期會接觸該目標的火箭。這只是決策估計，不提前寫入真正 heat。

IGNITE_ONLY 遇到「目標已觀測為穩定燃燒」或「在途投入已達下一輪暫停門檻」時，可暫停下一輪並在固定決策時點重新觀察。箭遭攔截、熄滅、出界或超時，必須移除對應估計，不能永遠停射。

穩定燃燒預設需連續 3 個火勢更新符合門檻；實際目標未起火時，觀察等待期限到達後應恢復評估。已出手箭不取消，尚未 release 的預約可撤銷。

DESTROY_FUNCTION 使用可觀測功能／目標有效性，不把隱藏庫存數量當自動瞄準情報。主命令序號變更後，舊射擊排程與瞄準工作必須失效。

---

## 9. 火勢、引燃、傳播與煙霧

### 9.1 燃燒狀態

```text
DORMANT → HEATING → BURNING → EMBERS → COOLING → DORMANT
                  ↑          |
                  └──────────┘ 仍有燃料且再度滿足引燃條件時可復燃
```

`scorch_amount`、剩餘燃料及建築損壞不隨 DORMANT 重置。DORMANT 可以是從未燒過，也可以是已燒焦且冷卻的物件，外觀由燒損資料決定。

BURNING 與 EMBERS 由不同燃燒率及危害倍率表現。BURNING 的維持門檻低於新引燃門檻，避免狀態抖動。燃料歸零不再生成燃燒熱，但殘餘熱必須冷卻後才退出 active set。

### 9.2 最小數學模型

使用抽象遊戲單位，所有戰術增減以相同動作時間區間計算；下式 `fire_dt` 為動作秒。每次更新先算有效輸入，再算下一狀態；多來源不得依事件到達順序各自觸發一次建築傷害。

```text
burned_fuel = min(fuel_old, profile_burn_rate × intensity_old × fire_dt)
combustion_heat = burned_fuel × profile_heat_yield

heat_new = clamp(
    heat_old + impact_heat + contact_heat + incoming_heat + combustion_heat
    - outgoing_heat - cooling_loss - suppression_heat_removal,
    0, profile_heat_capacity_limit
)

fuel_new = max(0, fuel_old - burned_fuel)
```

新被引燃者本次 `intensity_old = 0`，下次才消耗燃料／產生燃燒熱；因此單 tick 不會鏈式燒穿地圖。上式不是要求真實能量守恆的物理求解，但外部箭矢／作業輸入與燃料消耗必須有限，所有狀態不得負值或 NaN。

若使用不同數值模型，須保留單步邊界、有限來源、同時聚合及可重現性，並以相同測試驗收。

### 9.3 傳播規則

對燃燒單元的合法傳播邊分配 outgoing heat。風向只調整邊權重，不新增跨越牆壁／懸崖的邊。總 outgoing heat 受 profile 與可用熱量上限限制，不能四個方向各複製一份無上限熱量。

每條邊的數值以固定順序計算；區塊邊界增量採相同讀舊寫新規則。區塊更新順序、載入順序、同一 tick 是否由不同 worker 處理，不得改變結果。

第一版不做飛火。火箭可以藉合法彈道跨越地形，這與地表火勢傳播是兩種不同能力。

### 9.4 潮濕、天氣與未活動地表

`moisture` 增加引燃門檻／冷卻效果；天氣提供風、降雨、環境乾燥趨勢及時間版本。屋頂、露天草地、被遮蔽的內容物使用不同 `exposure_factor`。

不為了下雨掃描整張世界地圖。未活動物件依保存的 moisture 與時間戳，在首次查詢／激活時根據權威天氣歷程或等效累積量補算；不能用「現在天氣」代替整段過去天氣。

剛滅火的物件可暫時較潮濕，但不是永久防火。未冷卻的餘燼能復燃；無燃料的焦地不能只靠餘熱長出新燃料。

### 9.5 活動集合

活動集合包含：仍有熱量、燃燒中、有效接觸火源、非零煙量、受待處理輸入影響的單元及其必要鄰居。靜止冷卻單元不每幀掃描。

燃料與損壞資料可以持久存在而不參與更新。煙霧仍未散去時，即使明火熄滅也不能把對應區域從所有活動資料中刪除。

### 9.6 煙霧最低實作

第一版煙是稀疏、低解析度的邏輯密度場，不是粒子數量。燃燒單元按 profile 產生密度，沿 smoke edges 以固定權重分配、隨時間衰減；每次 outgoing 權重總和不得大於可轉移量。

風改變合法分配方向。牆壁、地表層與屋頂依 smoke graph 處理；沒有室內模擬時，只做資產宣告的室外煙投影，不猜測完整室內房間。

瞄準／偵測沿視線高度與經過區段積分煙密度，轉成既有視野品質或命中散布修正。不能單看射手腳下或目標腳下有沒有煙。兩軍使用相同規則，UI 遮擋程度不控制命中。

首版不新增窒息致死模型；保留 `smoke_exposure` 介面，避免與火傷混為一條未定義傷害。

---

## 10. 建築受損、失能、倒塌與廢墟

### 10.1 五種狀態互不取代

| 資料 | 意義 |
|---|---|
| 結構完整度 | 該構件是否仍能支撐、阻擋或承載功能 |
| 可燃物剩餘量 | 是否仍有足以持續燃燒的物質 |
| 內容物完整度／實際庫存 | 設備、貨物等仍剩多少 |
| 功能狀態 | `OPERATIONAL / DEGRADED / DISABLED / DESTROYED` |
| 燃燒狀態 | 火勢本身；由 fire unit 唯一管理 |

滅火不回血，熄火不自動恢復功能，功能停用也不代表所有牆已消失。修復、清理、重建沿用原 `SiteRuntime`／建造 owner，燃料變更必須符合第 5.5 節。已有修理不能只恢復 `parts.hp` 而忽略補入材料的可燃量；確實缺少的功能才提供明示介面，不順便開發完整內政。

功能狀態必須接到原服務判定。P0 對每種准入 feature 列出分區依賴與 `OPERATIONAL / DEGRADED / DISABLED / DESTROYED` 的實際效果，接入 `SiteRuntime.feature_usable` 及原加工／供水、`SiteStockpiles.stock_endpoint`、`SiteHousing`、`SiteGarrison`、`SiteTrainingGround` 等適用 consumer；未適用項列理由。這些入口目前主要讀 body HP 或完工狀態，新增火攻旗標本身不會使服務停止。`DESTROY_FUNCTION` 的停射依據須與實際服務使用同一功能判定。

停用後停止對應生產／供水、住宿／駐軍恢復加成與訓練，禁止向失能倉庫新進料；原有物資仍由原 holder 保留，是否可取回另按原操作資格與危害驗證。已付批次、工作進度、住戶／駐營／訓練登記須明定暫停、解除或原取消／退款處理，不因停用被隱式刪除或重複扣料。不得用刪除 feature 或任意改 stage 代替失能，破壞原庫存及人員引用；倒塌使原返家／返營格失效時，同次交易須處理原引用與命令，不留下懸空目標。完成合法修復後重驗依賴，再由原入口恢復服務；P4 驗現場閉環，P5 驗帶原引用的存讀檔。

### 10.2 分區與傷害

小型建築可單區；中大型建築建議 2～8 區，每區提供燃燒 profile、支撐關係、命中代理、功能依賴及倒塌結果。不能把所有建築硬拆成固定八區。

木門對應獨立 zone；門扇毀損只修改門洞通行，不同時摧毀石牆。石造倉庫可出現屋頂燒損、庫存受損、功能停用、石牆仍在。

每個火勢區間以積分後的燃燒強度／熱劑量計算結構火傷一次。直接箭傷由原傷害系統一次處理；火勢投影不得再給同一屋頂第二份建築火傷。

首版石製本體火傷係數預設為零；木結構失效可能透過作者定義的 support graph 導致相關分區倒塌，但不是石材「燃燒」。

### 10.3 內容物損失

已有庫存系統時，火災只能提出帶 event ID 的 `InventoryLossRequest`，由庫存 owner 原子扣除並回報實際損失。不直接改第二份庫存數字。損失量不超過現存數量，capture／轉手不重置損失。

尚無庫存時，使用明確標註的 FireLab `contents_integrity` 代理；不可宣稱已整合真正倉庫。關鍵庫存事件要保存來源及去重資訊。

### 10.4 倒塌狀態與通行交易

```text
INTACT → DAMAGED → COLLAPSE_WARNING → COLLAPSED / RUIN
```

達警戒門檻產生倒塌倒數與危險區，不立即傳送內部／周邊角色。profile 明列警告門檻、倒數長度及受影響原部件；倒數是仍有支撐時的最晚倒塌時間，不保證部件在此期間免於致死傷害。原部件仍提供合法表面時允許撤離；即使沒有可逃位置，也必須回報受困，不作弊移出。

保留原 `parts.hp <= 0` 即失去支撐的規則。倒數內的致死火傷、直接箭傷或攻城傷害，可提前觸發同一權威邊界的倒塌；不可先把 HP 歸零、讓導航表面消失，再等倒數結束才處理人物。倒數到期而原部件仍有效時，向原結構傷害批次提交使其當下剩餘 HP 歸零的有效傷害，不新增第二份 HP，也不沿用警告開始時的舊 HP 當作結算數值。

最終沿原 `TerrainLab.siege_apply_damage_batch`／`SiteRuntime.damage_structure_part`／`resolve_structure_change` 完成一次表面差異、承諾步失效、佔用與墜落處理。提前倒塌後，舊倒數事件只確認已處理，不重複扣血／墜落；同一原實體的普通受傷更新不得無故取消有效倒數，generation 替換或合法取消則使舊事件失效。P0 記錄這些入口的最小接線，P4 以牆上人物及半步撤離驗收。

倒塌在權威邊界提交：

1. 確認 zone／building 身分、generation、當前 revision 與事件仍有效；區分同一實體更新、替換及已完成倒塌。
2. 一次套用結構、功能與障礙差異；更新局部 `topology_revision`。
3. 對新不可站立範圍的佔用者依既有傷害／移除規則結算；不得留下活人佔據永久非法格，也不得任意傳送。首版殘骸模型應盡量使用原 footprint 或可行走 rubble，避免在街道新增隨機硬障礙。
4. 建立殘骸燃燒狀態；原 zone 剩餘燃料／熱量以交易轉移，不在舊區與殘骸各留一份。
5. 使相交的路線、AimPoint 與工作 lease 失效，不觸發全地圖每支隊伍重建。
6. 發出呈現事件；動畫何時播放完不控制障礙。

倒塌區域傷害每次事件只套用一次；數值由 DamageProfile 決定。門洞新開通不表示殘火已安全，靜態可達性與 hazard policy 分別判斷。

### 10.5 缺少室內系統時

只提供 `get_occupants`／`request_evacuation` 適配介面並在 FireLab 使用可驗證代理。正式建築若沒有室內角色，就不憑空生成受困者；也不以火攻為理由強制新增完整室內尋路。

---

## 11. Formation 避火、容量與尋路

### 11.1 分層判定

```text
靜態地形／永久障礙是否允許走？
→ 本命令風險政策是否允許？
→ 與動態佔用及其他預約是否衝突？
→ 既有 Coordinator 是否接受並提交？
```

熱量進出 hazard band 只增加 `hazard_revision`，不增加 `terrain_revision`。原可燃資源實體／建築／城門／殘骸真的變更障礙才沿原入口增加 `topology_revision`。

NORMAL 路線可拒走危險區，但結果為 `NO_SAFE_ROUTE`；EMERGENCY_ESCAPE 在靜態合法路線上，尋找累積風險／預估暴露較低的出口。不得只准向下一格風險下降的方向移動，避免困在局部低點。

### 11.2 複合狀態與優先權

`hazard_response = NONE / AVOIDING / EVACUATING / SUPPRESSING / TRAPPED` 與主命令及 `ENGAGING` 分離。

決策優先：即時致命危害撤離 → 原本戰場撤退 → 有效受令工作／戰術命令 → 原部署恢復。使用者的新命令序號高於舊的 suspended order；威脅解除不得把已取消的命令復活。

EVACUATING 是離開局部火場；RETREAT 才是依既有規則抵達戰場邊界後退出 [P1，第 17.4 節]。不得把火場撤離改成整隊自動離開戰場。

### 11.3 成員暴露

使用原 `cells`、`moving_to`、`move_progress`、duration 與承諾步批次的 action interval 積分，計算在每個 hazard cell 的停留時間；包含尚未完成的半步及當步落格前後時間。P0 明定原 motion curve 與碰撞代理的對應；不得拿渲染插值反推受傷，也不得只在 Finalize 新接受的提案上算暴露。

沒有既有承諾步且新提案被拒絕者仍在原格累積暴露；快速跨越火格也不能免傷。取樣誤差需有固定上限，同一 tick 同一 exposure channel 只套用一次。

角色的短暫灼熱劑量達到裝備／角色 profile 門檻時，可轉為有限時效 BURNING 狀態；傷害率、最長持續時間與刷新上限由 profile 決定，重複命中不產生無上限疊加。可透過有效滅火降低／解除，進入水域的效果沿用角色與水域接觸規則。此狀態不向旁人或地表傳播，也不建立永久燃料。

REGULAR 與 SPECIAL 共用相同傷害語意。隊伍士氣以受威脅比例、有效傷亡與退路狀態彙總；不得讓 100 人各自重複發出全隊士氣懲罰。既有士氣系統未完成時只發布聚合事件，不重造一套士氣。

### 11.4 安全容量與槽位重新分配

維持三種容量：

```text
terrain_capacity：地形可部署位置
available_capacity：扣除其他隊伍合法持久預約
safe_capacity：在 available 內再扣除不符合風險政策的位置
```

範例：平台可容 60 人、隊伍 100 人；其中 20 個平台槽位失火，在進路仍安全且可容納的前提下重新規劃為 **40 人平台＋60 人安全排隊**。若進路也失火，轉往替代集結區；無解則明確受困，不假設永遠有足夠安全槽位。

仍由深至淺配置可用位置並保留進場通道，不能讓等候者堵住撤離出口。安全的槽位不必全部推倒重排，受影響路段與成員才需要適配。

### 11.5 危險預約失效的特殊交易

一般新命令失敗仍保留舊命令與安全預約；但環境已變危險的舊槽位不得因此繼續強制維持。

1. 在安全性驗證邊界標記受影響槽位 `UNSAFE_SUSPENDED`，禁止新成員進入／回補。
2. 保留主命令意圖與仍安全的 lease；移除危險位置的「必須到位」義務，實際 occupancy 不隨預約釋放而消失。
3. 嘗試交易式預約替代位置。失敗時保持安全部分、進入緊急避險／受困狀態，不復活危險部署。
4. 工作成員、撤離中成員與受困成員用互斥的 assignment category 計數，不能既算原槽位又算救火人員。

正常部署仍滿足原平台＋排隊的人數契約；危機期間需以 `safe_platform + safe_queue + relocating + working + trapped = active_deployable_members` 驗證完整且互斥的成員分類，不硬塞回原本兩類。

### 11.6 配額與防抖

保留原有尋路上限，不因火災開 unlimited A*。歷史 v3 參考值為單隊每 tick 8 calls／1024 expansions、Site 8192 expansions [P1，第 16 節]；實際值由 P0 核對，後續 Aging 契約不得倒退。

危害更新先找相交的 Formation route corridor、部署 footprint、工作接近路徑。只在風險跨級、路線失效、倒塌預警或冷卻穩定等事件重排；熱量小數值變化不觸發全員 A*。

同一 Formation 的普通 hazard replan 預設最短間隔 0.5 動作秒；立即危險可跳過節流，但仍受全域公平排程約束。安全恢復預設連續 1.0 動作秒，且重新驗證命令序號、路線與槽位後才恢復。

未輪到排程不累計 stall。受困有固定重試與事件喚醒，不每幀全搜尋，也不宣告永久無路。必要時共用逃生方向場／多源搜尋；不得以大量每人全域路徑取代 Formation 層規劃。

---

## 12. 放火、滅火與作業槽位

### 12.1 工作生命週期

```text
REQUESTED → RESERVED → MOVING_TO_SLOT → WORKING
                                    → INTERRUPTED / COMPLETED / FAILED
```

每個 job 綁定原 Formation、有效命令序號、目標分區、成員與 slot lease。成員不脫離 roster，不另生成消防 NPC。未被選為工作者者維持警戒、候補或原任務。

成員同時只有一個需佔用雙手／武器的權威作業 action slot；不能一邊持續有效滅火，一邊以相同時間再釋放火箭。中斷、切換及恢復均走既有 action／order owner。

作業位置必須可抵達、可面向目標、在有效工作距離內、有合法接觸／視線，且不堵塞主要出入口。隔著完整石牆不能滅屋內的火。

### 12.2 容量

同一 slot 同時只屬於一名有效工作者；多隊共用 Site 級 registry。建築一側只有四個有效位置，最多四人同時工作，不因附近有 100 人就乘上 100 倍效率。

作業等待位置與部署／移動預約協調；失效或到期 lease 需釋放。成員死亡、改令、目標倒塌、位置起火、目標已完成時立即失效，不等待動畫結束。

### 12.3 補給與有效作業時間

接近放火使用抽象 `ignition_supply`；滅火使用 `suppression_supply`。若既有庫存有對應項目，使用既有 item ID；沒有時使用具上限的測試補給，不新增礦產或製造鏈。

只有實際 WORKING、姿態有效、lease 有效的動作秒產生工作量。補給按權威工作量原子扣除；補給不足只允許與剩餘量相稱的部分工作，不得先做滿效果再回報不足。

滅火同時降低 heat、提高 moisture；不增加 structure HP 或補回燃料。目標沒有明火但仍有餘燼，可繼續冷卻；全冷卻後完成，不永久消耗補給。

### 12.4 任務中止與安全

slot 的危害超過工作 profile 容忍度、退路失效、進入倒塌警告或接敵達中止條件時，取消工作輸出並提交避險提案。工作者仍會受暴露傷害，沒有無敵時間。

逃生路徑是適配既有導航的 hint，需再驗證；不能因預先標了 escape_anchor 就直接傳送。工作中斷保留已完成的部分火勢變化，不回滾世界。

自動救火只在具備命令／能力的 Formation 或守備策略中啟用，不讓全場士兵自動搶同一火點。目標評分優先保護出口、尚可輓救的設施與阻止擴散，使用觀測資訊。

---

## 13. 角色動畫、視覺與操作介面

### 13.1 動作需求

| 行為 | 最低動畫／姿態 | 權威注意 |
|---|---|---|
| 普通弓箭 | 搭箭、拉弓、瞄準、放箭、回復 | release tick 由邏輯驅動 |
| 火箭 | 共用弓箭動作，增加準備／點火段與箭頭顯示 | 動畫 callback 不扣彈藥或產生第二支箭 |
| 接近放火 | 接近、作業循環、停止／撤離 | 不因循環次數直接結算熱量 |
| 滅火 | 工作循環、轉向、停止／撤離 | 按有效 work time，不按粒子數量 |
| 受火／撤離 | 沿用受擊、跑步、死亡，可加短暫灼熱表現 | 不強制 ragdoll 或 Near promotion |
| 建築倒塌 | 完整、燒損、警告、廢墟狀態 | collider 更新不等動畫完成 |

可用替代姿態完成 M1；正式資產需求列入交付報告。不得把缺動畫當成無法建立邏輯測試的理由。

### 13.2 近遠景表現

近景：有限數量的 pooled 火焰／煙／火星 emitter、角色著火掛點、建築焦黑與明確火點。中景：分區火焰面片／簡化煙柱。遠景：更少的火光與煙標示；仍保留權威危險資訊與選取辨識。

火箭每支保留邏輯狀態，畫面使用批次箭身；近景才有較詳細尾焰。每支火箭不建立動態燈光。動態火光預設不投影；同時有效數量受固定視覺預算限制。

一般兵的著火旗標透過既有 Crowd 資料／材質通道呈現，不做每人新材質，也不逐幀讀回所有 GPU 世界矩陣。

### 13.3 Godot 技術限制與查核

- 官方 `GPUParticles3D` 文件說明，降低 `amount_ratio` 不會減少按總 `amount` 配置與處理的資源成本；真正粒子 LOD 應切換不同 `amount` 的池或更簡單表現 [G2]。
- 同份文件說明 `visibility_aabb` 影響粒子系統的活動範圍；因此火勢、碰撞與傷害必須完全脫離粒子可見性 [G2]。
- 官方 MultiMesh 教學描述其一般整體剔除限制，並建議以多個空間區域分組 [G3]。該教學目前附有 4.7 尚未完全更新提示；若專案已有 GPU culling／indirect 自訂路徑，沿用並以實測確認，不因教學概括而拆掉現有功能。
- 官方效能文件指出透明物件排序及重疊 billboard 的填充成本；煙霧必須限制透明重疊、screen coverage 與高品質 emitter 數量 [G4]。

以上為技術依據，不保證使用某種節點即可達到效能目標。實際 Godot 版本與 API 需在 repository 核對。

### 13.4 UI／除錯

玩家至少看得懂燃燒中、餘燼未冷卻、已冷卻；建築顯示火勢、結構與功能三項，不合成一條不明確 HP。射擊介面顯示火箭彈藥、射擊政策、可射成員數與阻擋原因。

路徑預覽顯示已知火災風險，框選火攻區域標示己方進路風險；這是提示，不保證將來安全。濃煙不得遮掉必要的選取框、撤離方向與命令結果。

Debug HUD 可切換：燃料 owner、heat／moisture、surface、高度與 fire edges、hazard band、第一命中、事件 ID、AimPoint、工作 lease、Aging 消耗、活動區塊、在途火箭與去重狀態。

---

## 14. 存檔、Site 卸載與戰後狀態

### 14.0 P1～P4 過渡保存及交接守衛

現有 `SiteController` 會定期自存，`supply_save_guard`／`SiteStore` 會拒絕交戰、在途箭及未收束作業。新增 pool 或火源不能繞過原守衛；在尚未能完整序列化／恢復前，所有未收束或尚未持久化的新狀態必須向原守衛回報 `BUSY` 與明確原因，例如 `FIRE_STATE_UNSERIALIZABLE`。

- P1 即納入新 projectile、release reservation、未結算 impact；P2 再納入 heat／fuel／contact／焦痕與燃燒損失、待拓撲事件；P3～P4 納入角色著火、危害命令、工作、煙及去重資料。即使已冷卻，未能完整保存的火災持久變更也不能解除守衛。
- 自存、手存、載入替換、清場、Site／Region 切換、GD↔Native handoff 均走原入口重驗；拒絕時不改既有存檔 bytes、不扣物、不清掉現場新狀態。不得先清火場再讓保存通過。
- 具名 FireLab 測試使用隔離保存路徑；明示「本階段尚未支援保存／卸載」。測試 reset 可丟棄這個明示隔離案例，不可拿正式存檔作測試輸出。
- P5 前的 BUSY 保護只是防資料遺失，不計為 SV-01～07 或卸載完成。P5 完整快照、恢復、候選驗證及接管驗收通過後，才對已支援狀態解除對應限制；未涵蓋的原守衛繼續保留。

### 14.1 保存範圍

保存 schema／config 版本、world seed、原 Site 遊戲時間、原 action cursor／fire accumulator、simulation_speed 與重播所需的倍率／天氣輸入歷程、可燃單元狀態、接觸火源、在途箭矢、有效火攻主命令與 volley 進度、建築分區損傷／功能、補給與已確認庫存損失、角色著火狀態、工作狀態及必要 lease 資訊、待提交倒塌／跨區事件、事件 producer sequence 與去重狀態。

保存 smoke field 或足以精確重建同一時點煙量的權威資料；不得只保存火焰而讓讀檔後煙瞬間清空。

不保存粒子、火星、鏡頭 LOD、GPU visual transform 或動畫中間值作為權威。暫存 A*／proposal 按既有規則重建，不序列化半套 Commit [P1，第 18 節]。

### 14.2 讀檔順序

1. 在原候選資料中驗證版本，載入 Site 遊戲時間、action cursor／fire accumulator、必要倍率歷程、地形 delta、建築與永久 owner ID；失敗不替換現場。
2. 恢復結構拓撲與可燃單元，再重建跨分區連接／空間索引。
3. 恢復火勢、接觸火源、煙、在途箭與唯一事件序列。
4. 重建角色／Formation 權威位置及安全部署；工作 lease 需重新驗證，不有效者中止。
5. 依 saved command serial 重建射擊／避火狀態；不得重發已 release 的箭。
6. 在一致的 barrier 後恢復模擬與外觀。

相同 build、設定及命令／倍率／天氣歷程的持續執行與中途存讀檔，需同時對齊原 action cursor 與 Site 遊戲時間，比對權威 hash／已宣告容差，而不是只看建築外觀。不可拿不同倍速歷程下的同一遊戲分鐘當成相同動作區間。

### 14.3 卸載不是停止模擬

活躍火災的最小權威資料由既有保存／世界流程接管；卸載的是一般 Scene／渲染，不是燃料、熱量與未結束事件。現已有 `RegionSaveSlot._settle_cold_candidate` → `TerrainLab.advance_cold_site`／`replay_site_to` 的原候選冷補算路徑，P5 須擴充這條 shared-step 路徑與原子提交。現有受限冷補算不代表多活動區、在途戰鬥或火災已支援，須分別驗證准入。

同一分區任何時間只有一個 fire simulation owner，採 `owner_epoch`／等效交接版本；交接在完整 tick 邊界進行。原 owner 退出後不得繼續提交，新 owner 不重播已確認事件。

卸載期間若仍有在途箭、受火角色或未結束戰鬥，對應的最小權威碰撞／角色狀態也必須由既有 combat/world owner 保留或接管。只保留火場卻丟掉可被命中的人物是不合格的移交；也不能以卸載當作所有角色免傷。這不要求新增完整離屏戰爭系統，但需要保留直到既有合法結算點的必要權威資料。

跨區熱量、煙與箭矢移交有唯一 event ID、目的 surface／世界座標、有效 action tick 及對應 Site 遊戲時間。接收端依相同火勢步進順序處理，禁止因某個 Site 晚載入就把多個歷史 tick 的熱量全部當作現在一次灌入。

### 14.4 尚未載入的鄰接區

當火勢接近未載入區塊，先以 seed＋持久 delta 取得最小燃料／阻隔資料與必要 halo，不生成完整可視 Site。受影響區塊加入世界活動集合，不能把未載入當水牆，也不能讓查詢隱式產生整張世界。

第一版離屏使用相同固定規則，不做會因鏡頭切換改變結果的簡化結算。若現有冷補算缺少活動火災排程，P5 在原保存／補算流程內補最小接管與排程能力，不另建 world owner；在完成前必須標示卸載功能尚未驗收，不以偷偷禁止離開場景充當完成。

### 14.5 時間、修復與清理

按第 6.1 節的原動作秒／Site 遊戲秒分工運作，關閉遊戲不依現實經過時間自行燒毀建築。暫停時兩種時間域及火勢／煙／投射物／工作一併暫停；Site 經濟倍速不加速火攻動作秒，不放大 fire dt。離屏依 P0 已定案的跨 Site 雙時間契約，在原世界／保存 owner 內記錄並補算相同區間。不得只用活動 Site 發布的共同遊戲秒，加上冷 Site 自己的 `combat_left` 反算，就宣稱 action 一致。缺少必要決策或歷程時保留原存檔與現場並拒絕依賴該能力的交接，不猜測、不另建時計；持續拒絕交接仍不代表 P5 完成。

戰後保存焦痕、剩餘燃料、功能、廢墟與內容物損失。清理／重建由既有建造 owner 執行，作為新的合法世界變更；不能僅換回完整 mesh 就重置損傷或補回燃料。

---

## 15. 設定檔與初始調校

### 15.1 全域初始值

下表為本規格提供的起始配置，皆需放入可調設定，不散落 magic numbers。不能為了讓壓測過關，在執行中偷偷依 FPS 修改權威參數。

| 設定 | 初始值／規則 | 類型 |
|---|---|---|
| `fire_update_hz` | 5 | 權威時間設定；修改需跑重播／平衡回歸 |
| `fire_chunk_width` | 16 個現有導航格 | 資料分組，不改導航尺度 |
| `smoke_update_hz` | 5 | 權威時間設定 |
| `ignite_confirm_steps` | 3 個連續火勢更新 | IGNITE_ONLY 觀測條件 |
| `safe_return_seconds` | 1.0 動作秒 | 防止離開後立即走回火場 |
| `normal_hazard_replan_interval` | 0.5 動作秒 | 緊急危害可略過節流，但仍受預算限制 |
| `volley_release_window_seconds` | 0.25 動作秒 | 測試起點；以戰鬥 tick 量化 |
| `collapse_warning_seconds` | 2.0 動作秒 | 遊戲提示起點，不是現實倒塌時間 |
| `fire_contact_max_seconds` | 2.0 動作秒 | 熱量耗盡可提前結束；不得落地重置熱預算 |
| `projectile_data_capacity` | 8192 | 固定資料上限；壓測可另用 16384 配置，必須另記 config hash |
| `near_actor_budget` | 原設計初始值 64；P0 核對實際准入上限 | 不因火災增加或另建 Near owner |
| `work_slots_per_test_side` | 4 | FireLab 資產配置，不限制所有建築都只能四人 |
| `smoke_damage_enabled` | false | 先做視線／命中品質，不做新增窒息傷害 |
| `actor_to_actor_fire_spread` | false | 不做角色互相點燃的連鎖網路 |
| `long_range_ember_spread` | false | 不做飛火；火箭仍有獨立彈道 |
| `offline_real_time_progress` | false | 不使用關閉遊戲後的現實時間 |

### 15.2 Profile 必備參數

`BurnProfile`：初始燃料、引燃與維持門檻、moisture 修正、燃燒率、熱產量、冷卻率、傳播總上限、煙產量、結構火傷倍率、危害投影方式及 profile version。

`AmmoProfile`：普通／火箭標記、庫存 item ID、共用直接傷害修正、準備倍率、初始 ember budget、空中衰減、雨衰減、接觸供熱率與接觸時限。

`WorkProfile`：工作距離、有效面向、補給每工作量消耗、供熱／冷卻倍率、可承受風險、是否需要接觸或視線。

`HazardPolicyProfile`：正常／緊急路線容忍度、risk weights、hysteresis、反應頻率、工作中止門檻。所有門檻使用抽象游戲尺度。

### 15.3 可重現單元測試數值

建立獨立的 `test_profile_heat_100`，只用於測試，不當 production 平衡：初始 heat 0、fuel 500、引燃門檻 100、單次有效輸入 20；關閉冷卻、潮濕與鄰接輸入。前四筆輸入不得燃燒，第五筆後在火勢提交點轉 BURNING，下個火勢更新才向外傳播。

另建立 `test_profile_no_fuel`，相同 heat 輸入但 fuel 0，永遠不因自身生成持續燃燒。這能驗證「有火箭接觸」與「有燃料可燒」不是同一件事。

### 15.4 版本與配置

Profile 與世界存檔的 schema 必須分開編號；現有存檔載入新 profile 時需要 migration 策略，不允許無提示改變已燃燒物件的初始燃料。每份 benchmark 都記錄設定檔雜湊。

---

## 16. 效能、GPU Crowd 相容與量測

### 16.1 資料與複雜度

預期工作量以活動燃燒單元、活動箭矢、相交碰撞候選與受影響 Formation 為主。禁止 `所有人物 × 所有火源`、`所有箭 × 所有人物`、每個火勢 tick 全圖搜尋，以及每人每幀重建大型 Dictionary。

使用預配置陣列／pool／chunk 索引。CPU 逐支處理少量投射物資料不等於替每支箭建立場景物件；需實測熱點後再決定是否移至 GDExtension／既有 compute pipeline，不先大規模改語言。

保留同時齊射壓力，不能只把所有敵我隊伍強制錯開來掩蓋尖峰。一般 AI 節奏可分散，但最大合法齊射仍需驗收。

### 16.2 邏輯與視覺分開量測

至少記錄：

```text
fire_cpu_ms / fire_tick_p95 / fire_tick_p99
projectile_cpu_ms / projectile_collision_candidates / projectile_sweeps
hazard_exposure_cpu_ms / formation_hazard_cpu_ms
building_transition_cpu_ms / world_handoff_cpu_ms
active_fire_units / active_fire_chunks / active_contacts
active_projectiles / projectile_capacity_deferred
smoke_active_cells / pending_event_count / simulation_debt_ticks
hazard_replans / route_calls / route_expansions / aging_reserved_and_used
visual_emitters / visual_particles_configured / draw_calls / gpu_frame_ms
cpu_frame_ms / frame_p95 / frame_p99 / max_frame_ms / memory
```

平均每幀成本與真正火勢更新幀尖峰都要報；不能將 5Hz 的大尖峰除以幀數後說每幀很便宜。

### 16.3 Benchmark 條件與目標

沿用專案固定機器、相同引擎、Forward+、解析度、相機與 seed；歷史 RTX 5060、seed `123456789` 可作起點，但 CPU／driver／新 renderer 結果須重新記錄，不能把舊 4.6.2 數字貼成 4.7.2 火災實測。

每個場景先暖機，再至少記錄 60 動作秒模擬，重複三次；同報 wall-clock duration、Site 遊戲秒及 simulation_speed，保存原始資料；相同視覺品質與 config hash 才能比較。

| 場景 | 配置 | 驗收用途 |
|---|---|---|
| B0 | 10,000 人、100 Formation、既有 Near 預算；火攻功能關閉 | 現況基線 |
| B1 | 同 B0，火攻啟用但無火、無箭 | 空閒額外成本 |
| B2 | 同 B0，50 建築、1000 活動火勢單元、2048 活動箭矢 | 主要 production 候選負載 |
| B3 | 同 B0，50 建築、5000 活動火勢單元、接近 8192 箭矢 | 壓力與容量邊界；不得丟事件 |
| B4 | 一次大量齊射＋多棟同 tick 倒塌 | 尖峰／拓撲變更／預約完整性 |
| B5 | 同一命令重播，關閉 VFX／移開鏡頭／降低 LOD | 權威結果一致性與渲染成本分離 |
| B6 | 跨區延燒＋Site 卸載再載入 | 持久化與離屏成本 |

**建議接受目標（不是現有實測保證）**：B1 額外 CPU frame p95 不超過 0.3ms；B2 相對 B0 的額外模擬 CPU frame p95 不超過 2.0ms、額外 GPU frame p95 不超過 2.0ms。分別量測 CPU／GPU，不能相加後冒充實際幀時間。

B3 不允許正確性退化、無界積欠或記憶體持續成長；超出效能目標必須附熱點與下一步。通過增量目標不代表整體 60FPS：要宣稱進入穩定 60FPS 的 Combat Vertical Slice，另需整體 frame p95 ≤16.67ms 及既有 p99／尖峰標準。基線已不合格時不能隱藏該事實。

上述目標可在 P0 因實際基線提出書面調整，但不得在測試後為了宣稱通過而偷偷放寬。

### 16.4 GPU Crowd 相容性閘門

P0 先依第 4.5 節辨識 GD Actor／Army、Native Crowd 與攻城的唯一玩法 owner，再回答其位置、碰撞及傷害位於 CPU 或 GPU。現有 C++ native CPU 模擬不能被當成 GD 同一路徑或 GPU 呈現器，不能只看到 MultiMesh 就猜測。

- 若 CPU 持有正式 combat cell／motion，使用既有資料生成輕量碰撞代理；GPU 仍負責畫面與局部視覺，不能新增逐人世界 Transform 上傳迴圈。
- 若 GPU 已持有正式局部移動／碰撞權威，火箭命中與火場暴露必須透過既有同 tick GPU 查詢／批次結果介面，或先完成明確的 `CombatAuthorityAdapter`。不准拿過期 CPU 假位置代替精確命中。
- 不能為火災每幀整體 readback 一萬人的 Transform，也不能新增阻塞式全域 GPU sync。必要的命中／傷亡事件採有限批次、明確 tick／延遲與提交邊界，不能讓 CPU 與 GPU 各扣一份血。
- 若缺少此介面，列為 production 整合阻塞；CPU reference FireLab 可測模型，但不得宣稱萬人 GPU production 已整合。

每階段須驗證當前 SUPPORTED 後端的功能及 GUARDED 後端的拒絕／交接；P6 再完成正式萬人後端准入、全部功能回歸與效能。不得因尚未到 P6 就容許同箭在 GD／native 雙重結算。本任務不改寫既有 GPU buffer layout、render-thread owner 或 promotion／demotion 生命週期；必要變更列出最小 interface diff 與回歸測試。

### 16.5 效能降級順序

先降低視覺 emitter／amount、火星、動態燈與煙透明覆蓋；再優化資料佈局、空間查詢及重複規劃。任何近遠景降級都不能變更火傷、彈藥、命中機率、燃料、風向或傳播規則。

任何模擬細節降級屬下一版功能，需另外定義誤差與一致性，不能藏在 renderer LOD 裡。

---

## 17. FireLab 場景與驗收矩陣

### 17.1 M1 必備場景

建立或擴充 `FireLab`，使用實際 Site／Combat owner，不拷貝一套替代 Formation 移動。

M1 場景包含：一支 100 人可切換彈藥的弓兵、一支 100 人步兵、一個真正到位且有限補給的守方滅火槽、木屋、石牆中的獨立木門、由原 owner 提供的可燃植被／裸土／水面、至少一條窄道與地形高度落差。M1 使用固定、帶版本的天氣輸入；可切換風雨及遮蔽差異在 P4 驗收。

M1 必備操作：選隊、NORMAL／FIRE_ARROW、指定建築／區域、手動持續射擊／停射、MOVE／HOLD、基本 SUPPRESS、暫停／步進及隔離場景重置 seed。`IGNITE_ONLY`／`DESTROY_FUNCTION`、在途估算、自動停射、接近 IGNITE、跨隊工作及風雨效果屬 P4；存讀檔與 Site 卸載屬 P5。尚未准入功能須明示不可用，不以空按鈕或假效果充數，也不因 M1 驗收提前跨階段。

### 17.2 第一個可玩閉環

弓兵射出可看見且可被阻擋的火箭，木門／屋頂累積熱量後起火。守方可降低火勢，步兵不為維持舊槽位走回火場。門扇毀損後形成合法通道，但仍有殘火風險；熄火後損壞保留。任何一步不能以測試專用 teleport、無限補給或直接改 HP 代替正式管線。

Debug 直接引燃只用於隔離測試，不當主驗收。

### 17.3 測試矩陣

所有項目初始狀態都是 **未執行**。實作者需提供自動化結果；必須目視的項目另附短錄影／截圖與操作重現步驟。表中的「通過」是應達條件，不是目前結果。

#### A. 箭矢、彈藥與齊射

| 測試 ID | 情境 | 通過條件 | 最早階段 |
|---|---|---|---|
| AR-01 | NORMAL 箭射固定／移動目標 | 有飛行時間，依實際命中一次扣血 | P1 |
| AR-02 | 高速箭跨越薄牆 | sweep 攔截最早牆面，沒有穿透至後方目標 | P1 |
| AR-03 | 高拋路徑被高牆阻擋 | 檢查完整曲線，不只兩端 | P1 |
| AR-04 | 出手後目標移開 | 不追蹤、不在發射時預扣目標血 | P1 |
| AR-05 | 友軍／盾牌介入 | 最早有效阻擋先結算，後方不再受同箭 kinetic hit | P1 |
| AR-06 | 100 人隊伍，本人 cargo 合計只有 3 支合法箭 | 三支箭的持有人均可合法射擊時恰好 3 次 release／3 次本人扣彈；不跨人免費取用，不產生公共彈匣 | P1 |
| AR-07 | 準備中改令／死亡 | 不 release、不消耗；已射出的箭仍存在 | P1 |
| AR-08 | 容量已滿／多輪隊伍競爭 | 回傳 CAPACITY_DEFERRED、不扣彈藥、不刪舊箭；容量釋出後無固定隊伍飢餓 | P1 |
| AR-09 | 命中事件重送／視覺回呼重播 | 不重複傷害、引燃與消耗 | P1～P2 |
| AR-10 | 火箭偏離後落草地／裸土／水 | 各依實際落點與燃料處理，水熄 ember | P2 |
| AR-11 | 空中燃燒預算耗盡 | 可保留箭傷，無引燃能量充值 | P2 |
| AR-12 | 98 人阻擋、2 人可射 | 合法 2 人按窗口放箭，全隊不永久等待 | P1 |
| AR-13 | IGNITE_ONLY＋大量在途箭 | 估算只影響下一輪決策，不提前加熱 | P4 |
| AR-14 | 在途箭全部被牆攔截 | pending estimate 移除，期限到後恢復評估 | P4 |
| AR-15 | 切鏡頭／動畫降級／不同 FPS | 相同命令下 release／impact／ammo 結果一致 | P1～P6 |
| AR-16 | 依 P0 決策驗普通弓／弩、盾牌、擦傷及火箭接觸 | 原規則保留／取代項逐項對照；無散布加擲骰的未定義雙重 miss，kinetic 與 heat 關係一致 | P1 |
| AR-17 | GD Actor／Army、Native、攻城准入及切換 | SUPPORTED 路徑各只有一次發射／扣彈／傷害；GUARDED 路徑拒絕且原狀態不變；不得以 GD PASS 代表 native PASS | P1～P6 |
| AR-18 | 同本人最後一箭重入發射、NORMAL／FIRE_ARROW 切換 | 最多扣一次；模式／order serial 重驗，兩類實物守恆；native 准入時同驗投影與回寫 | P1 |

#### B. 火勢與建築

| 測試 ID | 情境 | 通過條件 | 最早階段 |
|---|---|---|---|
| FI-01 | heat-100 測試 profile，依次輸入 20 | 前四次不燃燒，第五次於火勢邊界引燃 | P2 |
| FI-02 | 一排可燃格，同 tick 首格達門檻 | 新起火格不在同次更新繼續傳播 | P2 |
| FI-03 | 打亂 active list／區塊迭代順序 | 權威結果 hash／宣告容差相同 | P2 |
| FI-04 | 裸土／石牆／水接受大量輸入 | 不憑空新增燃料形成永久火場 | P2 |
| FI-05 | 峭壁上下／牆兩側／不同 surface | 無合法 fire edge 不傳熱，不以 XY 直接穿越 | P2 |
| FI-06 | 木屋與地面危害重疊 | 燃料一次消耗，同一建築火傷不重算 | P2 |
| FI-07 | 燃料耗盡但仍有餘熱 | 不產生新燃燒熱，冷卻完成才移出熱活動集 | P2 |
| FI-08 | 暴露雨淋與遮蔽內容物 | 依 exposure factor 差異處理，非整棟同時全濕 | P4 |
| FI-09 | 風向朝牆 | 調整合法邊權重，不新增穿牆傳播 | P4 |
| FI-10 | 熄火後仍有煙 | 邏輯煙持續衰減，不因 VFX 隱藏而消失 | P4 |
| FI-11 | 射手／目標無煙，中間有煙 | 視線區段積分生效，不只檢查兩端 | P4 |
| FI-12 | 原可燃資源燃燒→採集、採集→燃燒、同邊界兩者發生 | remaining／fuel 依既定映射單次提交，不燒掉後再產出同一份物資 | P2 |
| FI-13 | 清地／再生／同 ID 重建與舊 contact 重送 | 僅新增實體可燃量；熱態再生延後，舊 generation 事件不加熱新實體 | P2 |
| BL-01 | 火箭命中石倉木屋頂 | 先影響屋頂 zone，非全棟與庫存同時扣火傷 | P4 |
| BL-02 | 木門燒毀 | 只開門洞，石牆不隨門刪除 | P2 |
| BL-03 | 建築熄火 | 結構、燃料、庫存不回血／重置 | P2 |
| BL-04 | 倒塌事件重送／同時多棟倒塌 | 每棟只提交一次，局部拓撲與佔用一致 | P4 |
| BL-05 | 倒塌時保有剩餘燃料 | 舊 zone 與 debris 交易移交，總量不翻倍 | P4 |
| BL-06 | 工作中倒塌 | lease 失效、工作停止、人物按權威規則撤離／受傷 | P4 |
| BL-07 | 燃燒中倉庫物資減少或轉手 | 損失不超現存量、owner 無重複扣除 | P4 |
| BL-08 | 新硬障礙範圍有角色 | 無活人永久留在非法格、無任意傳送 | P4 |
| BL-09 | 燒損木門冷卻後付費修復再引燃；修理途中起火／待倒塌、取消或完成事件重送 | 完工重驗原身分及冷卻；原料與工時守恆，fuel 只按實際完成量增加；可再燃、不免費補滿、不重複補料 | P2 |
| BL-10 | 牆上有人／半步撤離中，預警內再受致死火傷或攻城傷害；另測自然到期、到期與致死傷害同邊界、事件重送及 generation 替換 | 致死傷害提前在原結構邊界倒塌，到期使用當前剩餘 HP；表面、承諾步、墜落及燃料移交各一次，舊事件不影響新實體 | P4 |
| BL-11 | 屋頂失能但 body／牆體尚存；帶庫存、已付批次及原人員登記，冷卻修復後恢復 | 實際服務停用與 DESTROY_FUNCTION 判定一致；禁止新進料，原物／引用不遺失，取貨依資格，修復後合法恢復 | P4；准入 feature 逐項驗 |
| BL-12 | 失能中及修復後保存／載入，含倉庫 holder、已付批次、住戶／駐營／訓練登記 | 原引用及暫停／解除結果可完整恢復；讀檔不復活失能服務、不重扣料、不重新發放加成 | P5 |

#### C. Formation 與作業

| 測試 ID | 情境 | 通過條件 | 最早階段 |
|---|---|---|---|
| FM-01 | MOVE 原路起火 | 增加 hazard 風險，非直接改靜態可達性 | P3 |
| FM-02 | 快速穿過火格 | 按權威停留時間受傷，不漏算 | P3 |
| FM-03 | 無在途步者的新提案被拒；另測已有半步而無新提案 | 前者不 pop 並在原格受傷；後者沿原承諾步積分，實際完成屏障才落格與消費路徑 | P3 |
| FM-04 | 逃生需先走過較高風險一格 | 能搜尋累積風險較低的合法逃生路線 | P3 |
| FM-05 | 60＋40 平台中 20 個平台槽位失火 | 在足夠安全進路前提下重排為 40＋60 | P3 |
| FM-06 | 平台及進路均起火、無替代安全位置 | 明確 TRAPPED／NO_SAFE_ROUTE，不死等舊槽位 | P3 |
| FM-07 | 危險槽位重新預約失敗 | 不復活危險到位義務，保留仍安全預約與實際 occupancy | P3 |
| FM-08 | 全場 100 隊同時避火 | calls／expansions 兩者 Aging 至少 50% 保證不被吞掉 | P3 |
| FM-09 | 沒輪到排程 | 不累計卡死，不宣告 STATIC_BLOCKED | P3 |
| FM-10 | 熄火後又短暫復燃 | 防抖有效，不反覆走回危險原位 | P3 |
| FM-11 | 避火期間收到新主命令 | 不恢復舊 serial 命令，不自動變 RETREAT | P3 |
| FM-12 | 大量 REGULAR 著火 | Near 不超預算，不建立全員角色節點 | P3～P6 |
| WK-01 | 100 人、4 個合法工作位置 | 最多四人同時有效作業，其他人不疊加效率 | P4 |
| WK-02 | 兩隊爭同一工作槽 | 只有一個有效 lease，無同格工作 | P4 |
| WK-03 | 隔石牆／超距離／未到位 | 不輸出冷卻或熱量，不消耗有效工作補給 | P4 |
| WK-04 | 補給僅足半個工作區間 | 輸出相應部分效果，無負補給 | P4 |
| WK-05 | 工作者死亡／改令／slot 起火 | 工作中止、lease 釋放、沿原仲裁避險 | P4 |
| WK-06 | 只剩餘燼／已完全冷卻 | 可冷卻餘燼；完成後停止耗補給，不修 HP | P4 |

P3 先執行 WK-03～06 的單一 SUPPRESS 槽子集（隔牆／未到位、部分補給、中止、餘燼完成）；P4 才驗跨隊、多槽及 IGNITE 完整矩陣，不以延後正式工作為由略過 M1 基本滅火正確性。

#### D. 保存、效能與呈現

| 測試 ID | 情境 | 通過條件 | 最早階段 |
|---|---|---|---|
| SV-01 | 火箭在空中時存讀檔 | 續飛，不重發／退彈／重複命中 | P5 |
| SV-02 | 有接觸供熱與煙時存讀檔 | 熱預算、餘燼、煙與時間相同 | P5 |
| SV-03 | 工作中及準備射擊時存讀檔 | 驗證 lease／serial，已扣項目不重扣 | P5 |
| SV-04 | 倒塌已排程、尚未提交時存檔 | 載入後只執行一次拓撲交易 | P5 |
| SV-05 | Site 卸載後持續遊戲時間 | 火勢繼續，重載不重置、不跳過燃燒 | P5 |
| SV-06 | 跨區火勢到未載入鄰區 | 最小燃料資料被處理，結果不受載入順序影響 | P5 |
| SV-07 | 交接事件重送／owner 轉換 | 始終唯一 authority，無重複燃料／扣血 | P5 |
| SV-08 | 暫停／改畫面 FPS／關遊戲後重開 | 暫停不進度，無現實離線時間燒毀 | P5 |
| SV-09 | 尚無完整保存時，新箭／燃燒／已冷卻未保存損壞遭自存、載入替換、換場或 handoff | 原守衛明確拒絕，存檔 bytes、人物、物品與現場不變；P5 才以完整快照替換對應限制 | P1～P5 |
| TM-01 | 0.5／1／2／4 倍速、慢幀及 combat_left 跨零 | 同 action 區間的 flight／ember 不被遊戲倍速重乘；P2 擴至火勢／contact，P3 擴至暴露／滅火 | P1～P3 |
| TM-02 | 火場持續續期、最後熱量冷卻、原手工作業與冷補算 | 續期不重設有效 manual progress；兩入口同時鐘判定；同 action cursor 與 Site time 的狀態一致 | P2；離屏部分 P5 |
| TM-03 | 冷火場＋活動和平 Site，以及反向切換、最後火源冷卻／倍率變更 | 原世界 owner 提供一致的 action／game 區間；不能因選中／載入不同 Site 出現未定義的 60 倍火勢；比較共同區間內的 hash／容差 | P0 數值契約；P5 執行 |
| TM-04 | 持續餘燼／殘熱期間，安全區隊伍已達疲勞 80，另測威脅進入及危害冷卻 | 80→50 輪休、復工及 Actor／Army／Native 行為符合 P0 明定政策；不得因漏查 consumer 卡住或讓危險工作者無條件恢復 | P0 政策；P2 現場；P3 滅火；准入後端重驗 |
| PF-01 | B0～B6 重複測試 | 原始資料、條件、p95／p99／max 與增量齊全 | P6 |
| PF-02 | 近／遠／隱藏火場 | 邏輯一致，GPU 渲染成本可分離量測 | P6 |
| PF-03 | 5000 火勢單元＋容量箭矢 | 無事件遺失、無界積欠／記憶體成長 | P6 |
| PF-04 | 正式 Native Crowd／目標 GPU 呈現模式 | 第 4.5 節功能准入已完成；萬人命中／暴露沿真 authority，無逐人完整 readback／新增阻塞 sync | P6 |
| PF-05 | 開關新功能比較既有移動案例 | 山頂、髮夾彎、HOLD、Aging、既有交換規則不回歸 | P6 |
| PF-06 | 人物／煙／建築視覺驗收 | 可辨識危險與命令；動畫不改碰撞或射速 | P3～P6 |

### 17.4 關鍵測試詳細條件

**AT-01｜火箭不是遠距離點火。** Given 木屋前方有完整石牆且彈道被擋；When 下令火箭攻擊木屋；Then 火箭命中石牆，木屋沒有收到該箭的 heat／damage event。換成合法高拋路徑才可能命中屋頂。

**AT-02｜同 tick 不連鎖。** Given 連續五個可燃格均未燃燒；When 第一格在本次 fire boundary 被點燃；Then 本次第二至第五格不能因新火開始向外傳播；下一次才計算首格 outgoing heat。

**AT-03｜火不破壞靜態圖。** Given 唯一靜態合法道路中段起火；When 一般 MOVE 無法接受風險；Then 回報 NO_SAFE_ROUTE，而非 STATIC_BLOCKED；緊急逃生仍能評估穿越後的累積暴露。

**AT-04｜安全容量有前提。** Given 平台 60、隊伍 100、20 平台槽失火、進路另有 60 個安全排隊槽；When 危害提交；Then 安全分配為 40＋60 且保留通道。刪除足夠安全進路後，不得仍硬回報 40＋60 成功。

**AT-05｜Aging 不能被搶光。** Given 每個呼叫／擴展配額都有 Aging 需求且全場觸發緊急避火；When 執行一個完整排程週期；Then 兩種計量分開顯示至少 50% 保留並先服務 Aging，不能只保 calls 卻耗完 expansions。

**AT-06｜快取以原完成屏障前進。** Given 沒有在途步的成員提出離開火格但遭衝突拒絕；When Finalize；Then 位置及 cursor 不前進，仍承受原格暴露。另 Given 成員已獲准且正在原 0.38 秒步進；When 後續 tick 沒有新提案；Then 仍按半步 motion 累積暴露，僅在原完成屏障實際落格時消費一次路徑，不提前或漏 pop。

**AT-07｜卸載同結果。** Given 固定 seed、天氣、命令及倍率歷程；When A 持續載入，B 在同 action tick 卸載並於更晚 tick 重載；Then 同時對齊 action cursor 與 Site 遊戲時間後，火勢、燃料、結構、煙與事件序列一致，視覺粒子不需相同。

**AT-08｜門已開但仍燙。** Given 木門燃燒且結構歸零；When 門扇倒塌交易提交；Then 靜態圖可通，但 hazard 尚未冷卻；步兵一般路線仍評估危害，不能因 collision 消失就免傷。

---

## 18. 分階段工作單與交付閘門

### P0｜Repository 基線與整合契約

**目標：** 找到實際 owner、版本與測試入口，確認現有能力，不先重寫。

**必做：** 檢查 `AGENTS.md`、架構文件、`project.godot`、實際 Godot 執行版本、Formation 移動五階段、權威位置來源、武器／命中／傷害／庫存、建築、Site streaming／save、Crowd／Near、現有 benchmark。

**交付：** `FIRE_BASELINE_AUDIT.md`，包含實際檔案／symbol 對照表、現有 vs 缺少 vs 規格要求、版本差異、原始測試指令及結果，並逐項記錄下列契約：

1. 普通弓／弩與火箭規則遷移：各命中因素、盾牌／護甲／擦傷、kinetic 與 heat 關係、受影響的舊測試及決策依據。
2. GD Actor／Army、Native Crowd、攻城的 SUPPORTED／GUARDED／BLOCKED 計畫與唯一 owner；準入後端所需的彈藥投影及 handoff。
3. 第 6.1 節 action／Site game time 的實際 symbol、危害續期與手工進度；原世界共同 action／game 區間、發布／補算映射、跨 Site 切換數值案例；全部 `combat_left` consumer 及安全區 80→50 輪休政策。
4. 原承諾步、完成屏障、半步 motion 與暴露，不把 Finalize 當作落格。
5. 第 14.0 節過渡保存／載入替換／換場／清場守衛及隔離測試路徑。
6. 原可燃資源／parts、remaining↔fuel 映射、同邊界扣減、再生與付費修復；每個新增 profile 的數值與取整策略。
7. 各准入建築的功能依賴與原服務 consumer；停產／進出料、已付批次、住戶／駐營／訓練登記、修復恢復與保存引用的處理。
8. 倒塌警告門檻、致死傷害提前倒塌、到期 HP 零點，以及原結構批次／表面／承諾步／墜落的一次提交；同實體受傷、generation 替換與舊事件的區別。

每項標記已有決策、具體實作方案或待決／阻塞，不以籠統「沿用 owner」代替責任與狀態轉移。

**閘門：** 首輪只完成 P0。八項契約均有可執行方案、無未決玩法／權威衝突，且必要基線有實際結果時，標記 `CONTRACT_READY`；否則標記 `CONTRACT_BLOCKED` 並列具體缺口。跨 Site 共同時間及安全區休息政策在本次文件修訂後仍待 P0 定案，不能以「沿用原時計」或「P5 再接」略過。P0 要完成數值／責任契約，不要求提前宣稱新增火攻的 P2～P5 執行案例已通過。缺環境可交靜態查核並標 NOT_RUN，但不足以開啟依賴該驗證的後續工作。既有失敗須分類並界定影響，無關 baseline failure 不冒充新回歸，也不得隱藏。這是實作進入條件，不代表任何火攻功能已完成；已有授權與證據足夠時不另設重複確認。

### P1｜共用箭矢、彈藥交易與基礎齊射

**前置：** P0 的 `CONTRACT_READY` 與所依賴的基線證據；於後續輪次執行。**單一目標：** 完成普通箭與可切換火箭資料模式的正式投射流程；火箭可先只送出 ignition event，不在本階段直接造整套火災。

**內容：** 依已定案規則沿原 owner 擴充集中式 projectile pool、本人彈藥原子發射、曲線 sweep、第一命中與接觸後傷害、有限 ember payload、命令中止、基礎齊射及模式切換；同步完成未准入後端與新在途狀態的原入口守衛。

**驗收：** AR-01～08、AR-12、AR-15～18 的本階段部分；AR-09 kinetic 去重、TM-01 飛行／ember、SV-09 新投射物與交接守衛，以及 P0 指定的既有普通弓弩回歸。三箭案例是本人 cargo 合計 3 支；容量公平性另驗。結果逐後端列出，不跨模式宣稱。

**禁止：** 直接對指定目標加熱、Node-per-arrow／light-per-arrow、未命中就消失且不檢查落點。

### P2｜稀疏火勢與單區建築

**前置：** P1。**單一目標：** 火箭能對實際可燃落點累積引燃，完成燃燒至冷卻，木門毀損產生正確通道。

**內容：** 原資源／parts 上的 FireUnit、5Hz 動作秒雙緩衝、有限 contact、燃料生命週期、危害續期、基本投影、單區木屋／木門／石牆與焦痕；沿原保存與換場守衛保護尚未完整持久化的火災狀態。

**驗收：** AR-09～11、FI-01～07、FI-12～13、BL-02～03、BL-09、AT-01～02、AT-08 拓撲部分；TM-01 火勢／contact、TM-02 現場續期與手工進度、TM-04 安全區輪休政策、SV-09 活動及已冷卻未保存火災、AR-17 本階段後端准入。

**禁止：** 把地面投影當第二份燃料；Debug 點火取代火箭主流程；同 tick 無限延燒。

### P3｜Formation 避火與 M1 最小可玩閉環

**前置：** P2。**單一目標：** 在既有百人移動框架內完成火箭攻防、避火、安全容量與基本滅火。

**內容：** hazard overlay、權威路徑暴露、命令暫停／恢復、防抖、40＋60 案例、受困回報、Aging／預算適配；加入一個真正可到位、有限補給、可中斷的滅火工作槽，不以全圖冷卻按鈕代替。

**驗收：** FM-01～12、AT-03～06、AT-08、PF-06 基本視覺、WK-03～06 單槽子集、TM-01 暴露／滅火、TM-04 滅火與輪休、SV-09 新角色／作業狀態及 AR-17 准入；第 17.1 節 M1 操作可用，不包含 P4 功能。FM-08 可在原協調器隔離驗預算，但不宣稱正式萬人場景已准入。

**閘門：** P3 通過才可標註 M1 完成。尚無多區、正式保存或萬人整合，不描述成完整系統完成。

### P4｜多分區建築、煙霧與正式作業系統

**前置：** P3。**單一目標：** 補齊戰術功能與建築／工作資料契約。

**內容：** 多區 AimPoint、傳播／支撐圖、庫存損失 adapter、原服務失能／恢復、預警與致死傷害提前倒塌的原結構交易、殘骸轉移、煙霧視線、風雨遮蔽、跨隊工作 lease、接近放火／滅火、引燃後停射與在途估算。

**驗收：** AR-13～14、FI-08～11、BL-01、BL-04～08、BL-10～11、WK-01～06 全矩陣；SV-09 擴至煙／工作／倒塌，AR-17 驗對應准入；此前測試全部回歸。

**禁止：** 偷加爆炸、逐木板破碎、完整室內與水源物流，把任務擴大到無法交付。

### P5｜持久化、重播與 Site 交接

**前置：** P4；P0 已定案原保存與冷補算接線、跨 Site 共同雙時間政策及過渡守衛，包含 TM-03 數值契約。**單一目標：** 載入／卸載／存檔不改變遊戲結果。

**內容：** 版本化 save schema、在途箭與 contact、煙、待倒塌事件、命令／工作重建、owner epoch、跨區事件去重與最小離屏資料模擬。

**驗收：** SV-01～09、AT-07、TM-02 離屏部分、TM-03 跨 Site、BL-12 失能服務及原引用存讀；schema migration、損壞輸入原子拒絕、雙時間／倍率歷程、燃料不補生及 AR-17 交接回歸。只解除經完整恢復驗證的新狀態守衛。

**禁止：** 存 Scene 當權威、讀檔重發箭、以「卸載就暫停火勢」當完成。

### P6｜萬人整合、視覺 LOD 與 production 閘門

**前置：** P5。**單一目標：** 在實際 Crowd／Near production 管線量測、修正熱點並證明無核心回歸。

**內容：** 完成 Native Crowd 與實際 GPU 呈現的剩餘准入及大規模驗證、空間批次、VFX pools／LOD、B0～B6 原始資料、全部測試矩陣與原移動回歸。功能 owner／時鐘正確性在各階段先驗；P6 不作為發現雙重權威後全面重構的理由。

**驗收：** PF-01～06，全矩陣無未解 S0／S1 嚴重度錯誤。效能不達目標時交付可重現報告與剩餘熱點，不假稱完成 production gate。

**禁止：** 減少實際燃燒／命中／傷害來通過 FPS；解除 Near 上限；新增全量 GPU readback。

### 18.1 依賴總表

```text
P0 → P1 → P2 → P3（M1）→ P4 → P5 → P6（完整 v1.0／production 檢核）
```

每階段完成後更新進度檔與測試狀態。第一次工作只做 P0，交付 CONTRACT_READY 或具體 CONTRACT_BLOCKED；後續輪次在前置契約與證據齊全時只處理下一階段及必要小修，不在首次查核後自動跨入 P1，也不跨多階段全面改寫。發現既有符號不同時以責任適配，不因名稱不一致創造重複系統。

---

## 19. 完成定義、交付格式與禁止事項

### 19.1 每階段交付內容

| 交付物 | 必要內容 |
|---|---|
| 程式與設定變更 | 最小範圍、使用既有 owner、無無關重構；列實際檔案／symbol |
| 自動化測試 | 新增測試名稱、對應測試 ID、執行指令、實際 PASS／FAIL／NOT_RUN |
| 可玩場景 | 對應階段的 FireLab；使用正式資料路徑，不依賴無限資源作弊 |
| 手動驗證 | 操作步驟、可觀察預期；必要的錄影／截圖 |
| `FIRE_IMPLEMENTATION_STATUS.md` | 階段狀態、已完成 ID、未完成項目、阻塞與下一個單一目標 |
| `FIRE_TEST_REPORT.md` | engine/build/config hash、平台、測試列表、baseline failure、新 regression、未執行原因 |
| `FIRE_BENCHMARK_REPORT.md` | P6 必備；P0 先記基線，含原始量測檔、p95／p99 與情境 |
| Save schema 說明 | P5 必備；資料型別、migration、事件去重與交接順序 |

建議目錄如下，實際位置由 repository 既有規範決定：

```text
docs/specs/WG-FIRE-001.md
docs/implementation/FIRE_BASELINE_AUDIT.md
docs/implementation/FIRE_IMPLEMENTATION_STATUS.md
docs/testing/FIRE_TEST_REPORT.md
docs/performance/FIRE_BENCHMARK_REPORT.md
```

本次交付的是規格與開工指令，以上程式／測試／狀態報告由實作者在執行各階段時建立；不應預先填寫虛構結果。

### 19.2 每次工作結束回覆格式

```text
本次階段：
實際完成：
修改檔案／主要 symbol：
測試指令與結果（PASS／FAIL／NOT_RUN）：
效能與正確性觀察：
未完成／阻塞／風險：
下一個單一目標：
```

沒有跑過 Godot、沒有 GPU 環境、只有靜態檢查、只有 reference backend，必須明寫。不要用「應該可以」「理論上支援萬人」替代結果。

### 19.3 嚴重度與通過判定

- **S0 阻止交付：** 權威資料毀損、存檔重複消耗、occupancy 破壞、無界記憶體、崩潰。
- **S1 阻止該階段完成：** 火箭穿牆點火、無限燃料／火源、Aging 飢餓、角色被強迫回火場、主要流程不可完成。
- **S2 需記錄並排程：** 已可操作但超出效能目標、視覺辨識差、非關鍵邊緣案例；production gate 仍按第 16 節判斷。

全 v1.0 完成需 FR-01～11 對應功能、INV-01～15、測試矩陣及持久化證據齊全；M1 完成只代表 P3 閘門。未執行測試不得填 PASS。

### 19.4 不可接受的捷徑

不得以每幀找所有火點、每支箭完整剛體與燈光、命中時直接全棟燃燒、視覺碰撞回呼作傷害、視野外停火、以材質變黑當持久化、修改 A* 上限當避火解法、逐人成千上萬 Near promotion、重建全圖導航、無限／免費補給、獨立佔位系統或全場傳送解決問題。

不執行與本任務無關的 repository 刪除、強制重置、套件升級或 engine 升降級；不覆蓋使用者尚未提交的變更。依現有 AGENTS.md 和工作區規範處理版本控制。

---

## 20. 開工待查核項目與風險處置

這些是 P0 必須查 repository 回答及落實的事項，不要求使用者重新解釋已確認玩法。跨 Site 共同時間與安全區休息等尚未定案的核心政策，須列具體選擇、影響及決策依據；不能把本次審查更新當作已批准任一未定方案。

| 查核項目 | 未確認時的處理 |
|---|---|
| 實際 Godot／renderer 版本 | 執行版本查核；維持指定 4.7.2 目標，不擅自更換 |
| 最新移動／Aging／交換行為 | 以實際程式碼與測試建立對照；不得以歷史 v3 覆蓋後續已驗證改進 |
| GD／Native／攻城及 CPU／GPU 權威 | 依第 4.5 節列 owner 與逐階段准入；不能把 native CPU 視為 GD 或純 renderer |
| 普通弓弩規則遷移 | 已有落點遠程；先定命中因素／擦傷／傷害及 ignition 關係，再沿原 owner 擴充 |
| 建築／資源／燃料 owner | 原 parts HP、remaining、holder 與燃料交易對齊；缺少者才用明示代理，不取代已有 owner |
| 建築失能與原服務 | 對齊原生產／倉庫／住宅／駐軍／訓練入口，保留原物與登記；驗修復恢復及保存引用 |
| 倒塌預警與 HP 零點 | 保留原零點失去支撐規則；致死傷害可提前倒塌，原結構批次一次處理表面、承諾步與墜落 |
| Site 尺度／高度／surface | 記錄正式轉換，不能把 Region 的 100m 格直接當火勢格 |
| 角色 motion 與雙時間 | 原完成屏障／半步，action seconds／Site game time、危害續期時點；不能取動畫幀位置 |
| 跨 Site 共同時間 | 原世界發布與冷補算必須對齊 action／game 區間；TM-03 數值契約未定不得標 CONTRACT_READY |
| 危害續期與休息資格 | 查全部 combat_left consumer，明定安全區 80→50 輪休及逐後端規則；不能只保住 manual 進度 |
| 保存與原冷補算 | P1 起加新狀態守衛；P5 擴充原 RegionSaveSlot／TerrainLab 候選補算，不能另起世界 owner |
| 導航拓撲失效通知 | 只通知局部相交計畫；碰撞與視覺障礙在同一權威時點生效 |
| 效能機器與基線 | 先測後談 production；未有 GPU 環境就清楚標示 NOT_RUN |

主要風險依優先度為：權威／GPU 適配不一致、火場重新尋路風暴、煙透明 overdraw、同時倒塌交易尖峰、跨 Site 重複處理與在途箭讀檔。每項都已有對應契約及測試，不以「後續優化」略過正確性。

---

## 21. 依據、技術參考與變更紀錄

### 21.1 專案依據

**[P1] 既有文件**：`Worldgoing_戰鬥隊伍長距離機動與自適應部署_正式實作計畫_v3.md`。本次直接查閱第 1～3、16～18 節相關內容，用於中央五階段仲裁、穩定 ID、部分部署、HOLD、歷史配額及保存重建契約。此文件是設計依據，不代表 repository 已全部完成。

**[P2] 專案後續決策與本次對話**：Formation 最大 100、近萬人、Aging 雙配額 50%、靜態步進方向、完成原承諾步後才前進快取（舊討論稱 Finalize，現行落格入口見 INV-04）、64 Near、GPU Crowd 相容、火攻規劃，以及使用者補充必須包含火箭。這些是原規格引用的歷史設計背景，不代表當前 repository 已有對應上限或 GPU-resident 權威；容量、呈現與完成屏障以本修訂的現況查核及 P0 決策為準，不混用假設。

**[P3] 本文件新增工程細化**：M1／完整 v1.0 分段、事件去重、有限 ember budget、working lease、火勢雙緩衝、collapsed fuel 交易移交、save／handoff epoch、測試 ID 與量測目標。這些為交付規格的新設計，不宣稱已實作。

### 21.2 官方技術參考

查閱日期：2026-10-04。只將下列明確敘述用作技術依據；`stable` 網址可能隨版本更新，實作者應核對目標版本。

**[G1] Godot 官方下載歸檔。** 頁面列有 4.7.2 stable，可用於查核目標版本；實際執行環境仍須從工作區取得。

`https://godotengine.org/download/archive/`

**[G2] GPUParticles3D 官方類別文件。** 用於 `amount`／`amount_ratio` 成本差異，以及 `visibility_aabb` 活動範圍的說明；不據此推論火災邏輯可由粒子負責。

`https://docs.godotengine.org/en/stable/classes/class_gpuparticles3d.html`

**[G3] Optimization using MultiMeshes。** 用於一般 MultiMesh 剔除範圍與空間分組原則。該頁附有尚未為 4.7 完整更新的提示；自訂 GPU culling／indirect 路徑必須另外驗證。

`https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html`

**[G4] Optimizing 3D performance。** 用於透明排序、重疊 billboard 與渲染 LOD 的成本注意事項。

`https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html`

### 21.3 版本紀錄

| 版本 | 日期 | 變更 |
|---|---|---|
| 1.0 | 2026-10-04 | 將火攻、火箭、建築燃燒、Formation 危害、工作、保存及效能整合為可交付規格；加入 M1、P0～P6 工作單與驗收矩陣。 |
| 1.0 審核修訂 | 2026-10-05 | 補普通箭遷移、GD/native 准入、雙時間、原完成屏障、過渡保存、燃料採集／再生／修復、本人彈藥與 M1/P4 界線；首次只做 P0，追加 AR-16～18、FI-12～13、BL-09、SV-09、TM-01～02。只更新文件，所有新增案例仍未執行。 |
| 1.0 第二次審核修訂 | 2026-10-05 | 補跨 Site 共同時間與 combat_left 休息政策決策閘門、原 HP 零點及預警倒塌交易、建築失能到原服務／引用的閉環；P0 擴為八項契約，新增 BL-10～12、TM-03～04 並分派 P2～P5。只更新文件，未完成 P0 政策定案，未執行新增案例。 |

---

**施工順序：首次完成 P0 的實際責任、規則遷移與進入條件；CONTRACT_READY 後依 P1～P3 完成真正射中、有限引燃、建築受損與基本避火／滅火。M1 不包含 P4 自動停射／完整作業或 P5 保存／卸載；任何階段都不以特效或理論 FPS 代替工程驗收。**
