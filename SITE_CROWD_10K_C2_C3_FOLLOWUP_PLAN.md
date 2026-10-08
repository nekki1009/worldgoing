# C2／C3 後續施工計畫：收兵 B 與 Atlas 入場去重

**2026-10-01 Native 核准後續結果（18:41；必要新build功能回歸完成，C3性能仍FAIL）**：使用者「繼續」核准的兩Native source修法、隔離build／test、正式DLL發布與獨立新D已落地。新DLL SHA `53fc43f50d9d672b2328e3ec1f2b5f426bc26ef8feba23ea9b04c3b4669b9c13`、build identity `e6a09c15bbc3f9a3035a709856bc39be3c5f1de7369e80245009d88aa330bd3f`；Native例外精確限定三條path，其他19條、原immutable D、Atlas／舊資產與正式16 Site／60 cache的保全核對及各實際時間見[新build實際證據](output/crowd_c2_c3_b_atlas_20261001/native_full_import_20261001_163744_009/IMPLEMENTATION_REPORT.md)。真正完整DR `170545_282` **PASS256.065s／5,417checks**，production SOURCE_STATE、自然命運／實物、全B、普通動作／完整保存載入／首幀與再D5均通過；ordinary新程序 `171106_463` PASS17.734s／10checks。新build B7兩輪真GPU rollback各182checks、B11完整56,015checks／新程序11、ammo escape67／death58及所列普通回歸通過。最終C252 B10 `181941_690` **PASS541.803s／14,946checks**，本次82d696成功保存基準的ordinary新程序 `183033_535` PASS20.240s／11checks、完整450tick MOVE新程序 `183144_947` **PASS463.446s／14checks**；沒有沿用不同07058／0286來源的舊診斷。原完整MOVE保存／載入必要正向保留；4758新普通死亡後的晚期BUSY只作額外原SaveGuard／state／queue／items／file SHA保全負向。既有ammo與B10的test-only fixture由固定V3 exact兩路徑manifest及P0／pre-Native／intermediate／final四層證據保護，所有先前FAIL與manifest保留。新DLL GPU C3 `171228_318` **35功能／artifact通過，2性能FAIL**：完整保存 **1,109.138ms**／fresh載入 **6,775.413ms**超過原300／500ms，938,895bytes通過4MiB；600步hash／A／C／全座標、IDs／cold refs／拘押／items及真GPU首幀通過。本輪收兵B功能及Atlas去重／重驗發布／正式runtime安裝／GPU抽樣範圍已完成；**整份v8、C3性能與正式10k release仍未通過**。最後sourceaudit／current-only census／canonical封存的actual結果與時間集中在上述新報告；本段先於sourceaudit固定，SOL不在audit後改寫。下方15:51與更早敘述、當時未套用提案、old-build B9 SOURCE_STATE及舊C3942.570／6,140.111ms FAIL均保留作歷史，舊DLL PASS不計入新DLL。

2026-10-01，第 1 版；施工結果更新至 **2026-10-01 15:51（Asia/Taipei）**。使用者選定的收兵 B 與 Atlas 優化已施工。**B7 GPU 故障回滾、B10 完整 D9／途中 MOVE／兩個新程序、B11 最大普通容量與新程序均通過；B9 自然 DR 在再部署時被原 Native SOURCE_STATE 守門拒絕，收兵 B 尚未完整驗收。Atlas 入場去重、版本重驗發布、正式 runtime 安裝與 GPU 抽樣通過；C3 性能仍 FAIL。** 最後同版 C3 `154219_416` 的 600 步 hash／A／C／全座標及首幀通過，完整保存 **942.570 ms**、載入 **6,140.111 ms**、912,031 bytes；原 300／500 ms／4 MiB 門檻保持，完整 v8／正式 10k release 尚未通過。

本文件保留原施工範圍與驗收定義，接續 [v8 施工與測試辦法](SITE_CROWD_10K_C2_C3_TEST_PLAN.md)、[上層計畫](SITE_CROWD_10K_PLAN_SOL.md) 與 [04:50 實作證據](output/crowd_c2_c3_20261001/IMPLEMENTATION_REPORT.md)。各實際 run、逐人位移、來源／資產／正式存檔 SHA、所有 FAIL 及剩餘關卡見 [本輪實作與驗證報告](output/crowd_c2_c3_b_atlas_20261001/IMPLEMENTATION_REPORT.md)。Native 兩檔修法僅備妥供範圍例外審閱，尚未套用；不可把分項 PASS 或待審 patch 當成 B9／完整 v8 通過。

## 1. 已定案的範圍與驗收修正

### 1.1 收兵採 B：整體重新落到合法普通格位

- 收兵允許位置調整。由原人物、TerrainArmy、既有地形／部署／預約 owner，先完成全部候選位置與移動計畫的驗證，再一次交接。
- 放寬 v8 §4.2 的**收兵前 native `px/py` 與收兵後普通位置相等**要求；改驗證合法格位、必要的互斥預約、完整人物保全，以及逐人位移紀錄。重新部署必須從收兵後的真實位置開始。
- 格位、插值起點、槽位、路徑，以及由人物位置推導的隊伍中心／指揮參考點，隨新位置重建。這些是幾何資料，不是額外的傷勢或命令重設許可。§4.3 明列哪些欄位可以重建、哪些仍須精確保留。
- HP、暈眩、KO、起身、疲勞、士氣、彈藥、技能、人物及隊伍 ID、實物、拘押／看守關係、命令意圖、AI 所有權，仍依原欄位契約保存。`face` 與命令 `goal_facing` 不因落位而任意改向。
- 沒有完整合法配置時保留原群眾現場並回傳原因；不能刪人、恢復開戰前狀態、把命令改成 HOLD，或只交接能放下的部分人物。
- 此決定取代 [舊收兵決策文件](output/crowd_c2_c3_20261001/CLEAR_BOUNDARY_DECISION.md) 的待選 A／B 狀態。A 的任意連續位置普通移動擴充不在本輪施工範圍。

### 1.2 Atlas：同一次入場共用真實來源指紋

- 原 Atlas 自行計算來源指紋，同一次同步入場的不同 recipe 共用該次結果；每份 manifest、frame、page、mask、外觀仍各自完整驗證。
- 允許必要 Atlas 接線及實際受影響的圖集版本重新發布；不能略過驗證、接受 caller 宣稱可信的 hash、刪除來源依賴，或只改 manifest 字串冒充新版本。
- 第一輪的精確目標是消除 **mixed／female 各配方重複計算同一組 DyeSources**。不預先宣稱整個程序每個檔案只讀一次，也不保證單靠此項達到 500 ms。
- 此決定取代 [舊圖集範圍提案](output/crowd_c2_c3_20261001/LOAD_PERFORMANCE_BOUNDARY.md) 的待批准狀態。保存 300 ms、載入 500 ms 及其餘 v8 門檻不變。

### 1.3 權威與工作方式

遵守 `PROJECT_ARCHITECTURE.md` 的原 owner；本計畫是 v8 §4.2、§7 的狹窄補充，其他條款維持。群眾戰鬥仍由 native 推進，收兵後由普通 Actor／TerrainArmy 與原 Site coordinator 接手；不新增另一套人物、坐標、庫存或預約權威。

原計畫發布時交付的是文件；以下施工規則維持。後續施工按本文件的分段與白名單執行，不需重新詢問已決定的 A／B 或圖集範圍。若遇到實際超出這兩項決定的玩法變更，先完成不受影響的工作，再單獨呈報具體缺口。

## 2. 施工前凍結基準：當時通過什麼、仍缺什麼

以下數字與「未完成 MOVE 仍 BUSY」等狀態是本計畫發布時的施工前基準，保留作對照；最後 B5／B10 MOVE 與 B9／C3 結果以本文開頭及本輪報告為準。

| 項目 | 既有證據／數字 | 本輪用途 |
|---|---|---|
| 收兵 | 合法普通格位布局已可交接；任意連續位置、同格活人、未完成 MOVE 仍會 BUSY | 保留原成功案例，擴充 B 的合法重新配置及 MOVE 接續 |
| 完整 D replay | 5,001 人、600 步 hash／A／C／全座標一致；保存 1,034.890 ms、載入 10,915.244 ms、912,347 bytes | 功能及不可變存檔基準；兩項耗時仍 FAIL |
| prepare 子階段 | 9,896.918 ms；register kits 9,346.198 ms；5,000 次 appearance 324.935 ms；8 次 make kit 10.167 ms | 先處理有來源證據的重複驗證，不把人物投影當主因 |
| 圖集共同來源 | 男女 GLB 合计 525,229,520 bytes；至少 6 個 recipe 重複走同組指紋 | 驗證去重次數；尚非 MD5／decode 各自耗時的實測 |
| B action step | 平均 18.520 ms、p99 83.364 ms；此範圍不含 GPU 繪製 | 保留 FAIL，不解讀成完整渲染 FPS |
| B 事件／host | 事件平均 6.524 ms、最大 104.547 ms；host 平均 17.258 ms | 這兩项不由本輪 Atlas 優化自動解決 |
| 未完成驗收 | 完整 DR 收兵往返、L3 人工、使用者整支 launcher、UBSan 環境、正式 10k release | 分別列狀態，不能用新小測試取代 |

來源與巢狀計時限制見上述兩份邊界文件及 [實作報告](output/crowd_c2_c3_20261001/IMPLEMENTATION_REPORT.md)。不同場景、fresh candidate／同場景、debug／release 不混算，inclusive 子階段不相加。

施工開始前保存：精確來源清單與 SHA、DLL/build 身分、正式資產與測試 cache 的 manifest/page/mask 清單、舊失敗結果、不可變 D baseline SHA、正式使用者 Site 檔案清單與 SHA。新證據使用獨立命名目錄，例如 `output/crowd_c2_c3_b_atlas_20261001/`，不覆寫舊 run。

## 3. 檔案白名單與既有呼叫鏈

### 3.1 收兵 B

| 檔案／owner | 預定責任與修改邊界 |
|---|---|
| `scripts/terrain_lab/crowd_clear_handoff.gd` | 主要變更：全體候選落位、狀態分類、原命令接續的準備、完整驗證與單次提交；延用現有 `prepare`／`commit`，不另建長期服務 |
| `scripts/terrain_lab/crowd_site.gd` | 收兵入口、原 row／actor 交接資料、新座標 envelope、重新匯入有效性；保留事件／存檔守門及原人查詢 |
| `scripts/terrain_lab/terrain_army.gd` | 僅抽取／接用既有 MOVE 純準備與 restore 接點，支援候選 snapshot 及可檢查的預約提交；普通命令的規則、AI、時間、介面保持原行為 |
| `scripts/terrain_lab/formation_destination_planner.gd`、`formation_transit_planner.gd` | 優先直接使用原能力。僅在現有回傳無法區別「合法配置／搜尋失敗」時增加狹窄、可驗證接點；不更換尋路與陣型系統 |
| `scripts/terrain_lab/site_combat_movement_coordinator.gd`、`site_deployment_reservation_registry.gd` | 優先使用既有 API；需要時補原 owner 的候選 lease／只重接返回隊伍接點，保留非群眾隊伍的在途預約與 retained occupancy |
| `scripts/terrain_lab/terrain_lab.gd` | 僅必要的收兵掛鉤、coordinator 重接與 UI 結果；現有 `clear_army`／D9 模式復原路徑繼續使用 |
| `scripts/terrain_lab/site_store.gd`、`site_controller.gd`、`terrain_test_character.gd` | 先視為既有 validator／capture／restore 的使用者，不預定放寬它們。只有證明現有窄接點不足時，才補 B 所需保存／restore 接線並附回歸，不接受任意連續位置 schema |
| 原 `scripts/tests/crowd_c2_clear_handoff_test.gd`、狀態交接／C3 測試 | 在原測試增加有行為意義的案例，移除已被正向測項取代的 `not_covered`；保留仍未涵蓋項目 |

原鏈：`TerrainLab.clear_army` → `CrowdSite.clear` → 原事件／save guard → `CrowdClearHandoff.prepare` → `commit` → 原 Actor／TerrainArmy → Site coordinator → 普通保存／移動／再次部署。

已確認的接點限制：

1. 現有 prepare 會因 Actor 不在格心、重複格位或 native MOVE 未完成而拒絕；這些正是 B 要補的地方。
2. `SiteMovementReservationGrid.resolve_all`／`commit_all` 是相鄰步進仲裁，不能當作任意遠距離收兵落位器。
3. `FormationDestinationPlanner.plan_deployment` 可能回傳平台＋排隊／partial 結果。收兵不能因此漏人，每人仍須有合法的當下位置。
4. Transit 的 `_legalize_unique_slot` 目前搜尋有界，失敗可能回傳原 ideal；任何 caller 都不能僅因取得 Vector2i 就視為成功。
5. `TerrainLab._configure_army_blockers` 只重接 blocker reader，不會完成 occupancy rebuild。
6. coordinator 的 `reset_for_site_replacement` 會清全 Site 的在途資料。本次是同 Site 交接，不能拿它清掉未參與群眾的隊伍。
7. Army restore 目前有降成 HOLD 的防護分支，也有未回傳 reservation admission 結果的接點；B 必須在提交前排除這些分支，或補可檢查的狹窄提交，不能把 void restore 當成成功證明。

### 3.2 Atlas

第一輪 production 僅修改 `scripts/terrain_lab/terrain_army_equipment_atlas.gd` 與上述 `crowd_site.gd`。保持 `scripts/terrain_lab/terrain_army_dye_atlas.gd`、`scripts/tools/terrain_army_recipe_bake_plan.gd`、`scripts/terrain_lab/terrain_army_batch_view.gd` 及 native 不變；避免無必要地改變所有 dye 的來源指紋。

原鏈：`CrowdSite.prepare_load` → Store 完整候選驗證 → 原 Army atlas prewarm → 每人 `_appearance` → `_register_kits` → 原 `BatchView._describe` → 原 Atlas recipe／dye admission → page／mask／frame → native tracks；另由 `_prewarm_captivity_atlases` 準備卸裝外觀。

現有 `_register_kits` 已按完整外觀去重，BatchView 也有 page 去重。重複点是 Atlas 不同 recipe 目錄各次呼叫 `DyeAtlas.fingerprints()`；不能再做一套 renderer 或把每人的 appearance 投影全部搬進新快取。

發布工具的條件白名單：`scripts/terrain_lab/terrain_army_atlas_capture.gd`、`scripts/tools/publish_terrain_army_female_ranged.gd`；既有 fixture 為 `scripts/tests/crowd_c2_captivity_atlas_fixture.gd`。只有 DyeAtlas 確實需要追加修改時，才涉及 `scripts/tools/bake_terrain_army_dyes.gd`、`scripts/tools/publish_equipment_dye_assets.gd` 與 `scripts/tools/finish_equipment_dye_publication.ps1`。沿原驗證流程補狹窄入口，新增測試與實際受影響產物逐檔列明，不將全部 assets 納入可修改範圍。

## 4. 收兵 B：候選、驗證、提交

### 4.1 在穩定同步點取得完整輸入

先沿既有 `_consume_events`／`settle_events`／`save_guard`；待必要死亡、俘虜、彈藥與實物交易完成，才截取候選。既有戰鬥中、在途彈體或未完成交易的限制維持。這些正常結算與「候選落位失敗不能修改現場」分開記錄；失敗前後比較從候選開始的同一同步點起算。

準備階段不推進 native、不呼叫一般下令、不發訊號觸發新交易，也不先修改 live roster／actor／lease。候選只在本次同步呼叫內存在，完成或失敗後釋放。

按 `person_id` 收集人物，actor 成員與 roster 引用只算一次；保留原 row、holder、cargo、actor 物件的身份對照。先驗完整容量：每隊 ≤ 200、Site ≤ 50 隊／5,000 名冊人物，並包含同場非群眾名冊。不能為了讓未來 10k 收兵過關而悄悄放大本輪普通模式容量。

### 4.2 全體合法落位

1. 固定不能挪动的現場：非群眾 Actor／Army 的當下格、在途來源／目的格、車輛與地形 blockers、他隊 deployment leases、retained occupancy。只排除這次返回隊伍自己過期的群眾前幾何與 lease。
2. 選位以每人現有模擬位置為起點，优先合法原格的格心；衝突時按既有 TerrainData／movement profile 的合法邊搜尋鄰近格。不得穿牆、跨非法崖邊或移到不可達的另一平台。群眾自身重疊不應全部當成不可穿越的外部障礙，否則無法解開同格布局。
3. 所有隊伍及 actor 共用**同一份本次候選 claimed 集合**；隊伍與人物採明確的穩定排序，例如 team_id／person_id，鄰居順序沿既有 planner。候選集合不是 runtime 新占位系統，提交後由原 coordinator 接手。
4. 站立、起身及清醒俘虜依原普通占位規則取互斥格。死亡與 KO 的位置仍須符合原 validator，是否占格依原規則；不為它們創造新的站立預約。已存在的遺物、ground loot、封存箱維持原位置與 ID，不能跟著人物收兵搬家或再生成一次。
5. 原部署 planner 用於槽位／陣型及 MOVE 目的配置；partial layout 仍須為跟隨／排隊者保留合法當下位置，不把沒有平台槽位的人刪除或強制收滿編陣型才接受命令。
6. 最小落位函式留在既有 handoff／planner。搜尋必須有可報告上限；優先按相同 movement profile 共用本次連通性資料，不逐人無限全圖重搜。達到搜尋預算回 `SEARCH_LIMIT`，無合法配置回 `NO_LEGAL_LAYOUT`，兩者不混稱「整張地圖已滿」。
7. 本輪不求全局最小位移，不新增最佳化套件；採決定性的鄰近可行配置。逐人記錄舊／新位置與距離，彙總 moved_count、平均／p95／最大位移、候選搜尋數、失敗人物／隊伍。若有可保留的合法原格，不為了外觀整齊把全隊搬到地圖入口。

拘押者與看守者 ID 保存之外，候選必須再走原 `SitePersonActions.has_effective_guard`／`_within_guard_range` 的關係判定；原本有效的看守不能僅因 B 重新落位而突然失效。將這類 guard／captive 視為同一候選配置的關係約束，包含固定在群眾外的 guard；無法保留原有效關係時拒絕候選，不靠重設 escape timer 掩蓋。已無有效看守者繼續原逃脫規則。

### 4.3 欄位交接政策

| 類別 | 本次處理 |
|---|---|
| 人物位置 | `cell`、`position`／`crowd_position` 改為準備好的真實格位／格心；普通 `slot`、`destination`、進度與 Actor movement start/from 由新位置建立，沒有假的在途插值 |
| 隊伍幾何 | `cx/cy`、以成員位置推導的 `reference/ref_x/ref_y`、普通槽位與 route 由新位置重建；保留原指揮人物引用，不藉機重新選隊長／抽 RNG。`ref_valid`、present 等判定須符合原 owner 與原語意，若落位使保留的指揮／presence 契約無法成立，該候選拒絕 |
| 命令意圖 | HOLD／MOVE／ATTACK／PURSUE／RETREAT／RETURN、goal、goal_facing、origin、target_person、pursuit_left、order_delay、attacking、needs_attack_order、AI 開關及冷設定精確保留；不同 enum 值仍走原映射 |
| 傷勢與能力 | [R2 完整表](output/crowd_c2_c3_20261001/R2_state_handoff.md) 的 HP、stun、grace、KO、getup、bandaged、cooldowns、escape_t、技能、角色、訓練等保持原契約；不重設計時或回到部署前數值 |
| 隊伍狀態 | fatigue／fatigue_rest／count、morale／rally_rest／routed、指揮／幹部引用、補給與隊伍 ID 維持；不能因重建普通 owner 再收費或補一餐 |
| 冷資料與實物 | 原 row／actor、holder／cargo／appearance 引用；物品 ID、耐久、彈藥、封存／遺物、家族、工作、控制權、captor_id／guard_id 保全；只有既有事件已結算的改變會反映其中 |
| 交接 envelope | 原 `crowd_return_handoff`、row `crowd_position`、roster `crowd_state`、actor `crowd_handoff.solo_formation` 都必須與新真實位置一致；完成後才計算原 SHA guard |

`face` 的任意角度仍由現有 handoff 保存，普通四方向呈現沿原投影；普通模式後來移動／轉向／改物品時，既有來源 SHA guard 必須使舊快照失效。不能只改顯示位置而留下重新匯入會採用的舊坐標。

「精確保留命令」沿用原表達差異：native 已過期的 `pursuit_left/order_delay` 可以為合法負尾值，普通欄位依原 validator 寫 0，原精確值仍留有效 envelope；正剩餘值不得重設。連續 `goal_x/y` 保留在原 `crowd_state`，普通 `goal` 採既有格位投影；不得將這種表示轉換變成重新下令或改變目的地的授權。

對 R2「原 movement/deployment/reservation 快照保持原值」的補充：群眾期間可以保存作歷史來源，但 **B 成功返回時不復活群眾前路徑或租約**；保留命令意圖，幾何與目前契約重建。active crowd blob 的保存／重播仍維持全狀態精確，不受 B 的收兵例外影響。

### 4.4 未完成 MOVE 也要有完整交接路徑

從 `TerrainArmy._preflight_combat_move` 與 `_issue_combat_order` 中現有 MOVE plan 建立段，抽出可用候選 snapshot／新 cells 作輸入的純準備。原下令與 B 共用這段，仍用原 `FormationMovementProfile`、`CombatDeploymentPlan`、`CombatMovePlan` 及序列化格式。

- 新路徑從落位後的原指揮／原 medoid 選擇規則起算；保留原 goal、最終朝向、陣型意圖、目標與 AI 所有權。
- **不呼叫公開 `issue_combat_order` 重發一次 MOVE**：它會改 origin、remaining/delay 並停用 AI，與交接不同。
- 在候選 lease view 中對全部返回隊伍執行原 `try_replace_reservations` 等 admission；別隊 lease 與 token／serial 保留。所有返回隊伍都成功才允許發布；逐隊 live reserve 到一半失敗不算原子交接。
- ordinary MOVE plan 必须通過原 refresh_derived_ingress、Store movement schema、來源／目的格及預約交叉檢查；restore 不可偷偷降成 HOLD。
- 不能完成新路徑／命令語意時，帶具體原因拒絕且維持 native 現場。這是失敗路徑；**不能一直保留舊 `MOVE_NOT_SETTLED` 分支而宣称 B 完工**。至少要有未完成 MOVE 成功收兵、接著真走路和在途中存讀的正向證據。

### 4.5 單次提交與失敗保全

prepare 的最終產物包含候選 Site、每個原 owner 的 snapshot、新幾何、MOVE plan、候選預約及逐人位移證據。先跑原 Actor valid_state、`Store._validate_state`、`_validate_armies(..., true)`、`_validate_army_assets`，再檢查人物／實物／拘押／容量及跨隊預約一致性。

提交順序：

1. 在同一同步邊界重新確認來源 epoch／人物集合與候選仍相符；提交途中不 await、不推進時鐘。
2. 使用原 Actor／Army restore 接點安裝已驗證候選。actor 採 prepared geometry，不能再被 `_sync_actor` 的舊 native `px/py` 覆蓋；原 row／holder／cargo 引用保持。
3. 只重接此次返回 formations 的 coordinator／batches／leases；保留非群眾在途來源、目的、token 與 retained occupancy。必要的 restore 調整放在原 owner，使 admission 可檢查；預檢通過後的 publish 不再做會默默失敗的新選擇。
4. 呼叫原 occupancy rebuild request／barrier，對完整現場驗證新占位。外部 blocker 接線與 occupancy rebuild 兩者都做；清舊群眾前 lease 不等於清全部 Site。
5. 候選 owner 與預約已安裝且 barrier 成立後，在普通設備／人物 callbacks 前**可回滾地切換 `active=false`**，讓原 `equipment_changed`／人物查詢分派到普通 owner。native 實例及回復資料仍保留；不得切換後又查 Crowd 當作權威。
6. 完成普通設備同步後，寫入新位置的 envelope 與 SHA、原 Site snapshots、當前控制人及 UI。全部成功才釋放 native／batch view、恢復普通 process，並依 D9 還原啟動模式。若此段失敗，原 owner／lease／active／啟動模式一併回滾。

若仍有任何會失敗的 commit 操作，先保存足以回復該操作的原 owner／預約狀態並提供局部回滾；在回滾可測之前不得將其列為已完成。故障注入至少涵蓋最後一隊預約衝突、資產驗證失敗與最後 barrier 不一致，結果不可留下半普通／半群眾現場。

## 5. Atlas 入場去重與版本發布

### 5.1 最小實作

在原 EquipmentAtlas 增加同步批次入口，例如 `admit_crowd_appearances(appearances)`；名字可以隨現有風格調整，不新增另一個快取 owner。

1. Crowd 先整理本次實際人物必需外觀，以及未來俘虜卸裝的 optional prewarm 外觀，按完整外觀內容去重；性別、武器、裝備及 palette 的差異保留。兩類共用來源計算，但沿原流程保留不同的失敗處理。
2. Atlas 在本次呼叫內執行一次真實 `DyeAtlas.fingerprints()`；依原 `Plan.SOURCE_PATHS`、RangedAtlas 額外來源宣告投影各 recipe 所需的來源集合。該 bundle 未涵蓋的 Atlas／capture 來源仍實際讀檔 hash，不能憑名稱填值。
3. 只把這份局部資料傳入 Atlas 自己的私有 admission。普通 `supports`／`mixed_recipe`／`dye_entry` 等入口保持原行為，不接受外部可信 hash 參數。
4. 逐 recipe 執行所有原 manifest／appearance／frame／page／mask／尺寸及 provenance 檢查，準備既有快取供 BatchView 使用；不改 `_describe`／tracks／render 語意。
5. 每次新批次重新驗證實際來源；既有 recipe cache 必須受本次來源身分約束，不能因 `has(key)` 就沿用來源已變的結果。局部來源 bundle 結束即丟棄，不新增跨場景／跨讀檔信任期限。
6. 必需 recipe 失敗時保留原 live scene，回傳具體失敗項；候選資源依既有釋放路徑回收。optional captivity prewarm 缺失仍依現行語意允許載入，真正俘虜交易仍由原 BUSY／MISSING_ASSET 守門；不可因去重變成整份拒載。稍後重新入場或使用 recipe 時不能沿用未完整驗證的成功標記。

`CrowdSite._register_kits` 中的批次準備仍在原載入計時區間內，接著使用原 BatchView／kit 建立。普通 base／ranged 第一次 admission 如仍自己算來源，照實計入；第一輪不為追求「全程序一次」而改 DyeAtlas／RecipePlan。

有現成 plan 時，若 `_single_page_recipe` 仍先建一份稍後被覆蓋的 plan，可在同一 Atlas 小改消除；前提是所有呼叫者等價測試證明沒有依賴該次副作用，不另做泛用快取。

### 5.2 實際受影響產物

| 產物 | 只改 EquipmentAtlas 時的處理 |
|---|---|
| mixed runtime cache：`user://equipment_atlas/v1/<namespace>/<recipe>/` | Atlas 自身在 source fingerprints 中，產生新 namespace；舊 namespace 保留供回復／比對 |
| 測試 mixed cache：`output/crowd_c2_c3_20261001/atlas/<namespace>/<recipe>/` | 依明確 recipe 清單建立新版本，不整包盲複製未知 cache |
| 女弓／女弩：`assets/characters/terrain_lab_army/standard_female/ranged/v1/{bow_01,crossbow_01}/` | female_ranged_sources 明列 EquipmentAtlas，必須按下節重驗發布或重烘 |
| 女標準：`assets/characters/terrain_lab_army/standard_female/v1/` | 先保持；僅在來源清單比對證明受影響時納入 |
| 男 base／ranged、原 dye 發布 | DyeAtlas／RecipePlan 未變則保持；不能為省事重寫整個 assets tree |

先凍結 validator、必要 publisher 修改和本次來源清單，再產生對應指紋／namespace；不一邊修改來源一邊持續補 manifest。

### 5.3 先證明像素等價，再選重驗發布或重烘

沿原 `site_component_atlas_revalidation_test.gd`、`site_loop_atlas_revalidation_test.gd` 已有的嚴格做法：

- 以 before 來源與產物為基準，允許差異只限列出的純驗證／去重函式；其餘舊來源 hash 仍全部相符。
- 證明角色／武器／動畫、frame plan、capture、mask 算法等生成像素輸入未變。所有 frame、rect、anchor、timing、appearance、PNG／RES／mask hash 保持。
- 新發布保存 previous source hash、重驗證據及 `rebaked:false`。扣除逐項允許的 provenance、namespace 路徑及父 manifest hash 變更後，完整 manifest 必須與 before 等價。
- 新版本仍通過原 runtime admission、像素及首次畫面檢查；不能只以檔案存在或 texture 可載入當作發布成功。

任一等價條件無法證明，便沿原 GPU capture／bake 重新生成該受影響 recipe。這兩條都屬已同意的版本重建工作；重驗發布報告必須明示沒有重新烘像素。

mixed 沿 `CrowdSite.prepare_captivity_recipe` → `Atlas.mixed_plan` → 原 `terrain_army_atlas_capture.gd`；12 組 GPU fixture 沿 `crowd_c2_captivity_atlas_fixture.gd` 指定同一新 atlas root，report 與 cache 分開。

女 ranged 原 `publish_terrain_army_female_ranged.gd` 目前是固定來源、additive 發布，不能直接當覆寫工具。必要時在它增補狹窄重驗發布入口，保留原 `_check`、lossless／逐 frame admission；在暫存目錄驗完整、備份具體舊產物，全部成功才切換。失敗恢復原發布；不留下 manifest 新、page 舊的混合版本。

只有實測證明第一輪仍需改 DyeAtlas 時，才擴充實際受影響的 mask 清單及原 `bake_terrain_army_dyes.gd`／`publish_equipment_dye_assets.gd` prepare/recovery。`finish_equipment_dye_publication.ps1` 只涵蓋男標準目錄，不能套去處理女圖集。此為條件後續，不預先擴充本輪來源白名單。

## 6. 驗收矩陣

### 6.1 收兵 B：先小案例，後完整 DR／D9

| 關卡 | 必測內容 | 通過依據 |
|---|---|---|
| B1 原成功行為 | 原合法布局、原 player／NPC／roster 成員、非預設傷勢與實物 | 既有成功案例保留；人物／holder／cargo 引用與完整欄位一致 |
| B2 重新落位 | actor 離格心、同隊與跨隊同格、多個 actor／roster 混合、地圖邊緣、坡道、斷崖與隔牆空格 | 全人合法且必要占位唯一，逐人 before/after 可追溯；固定輸入產生同一配置 |
| B3 容量與拒絕 | 全滿、搜尋上限、不可達空格、>200／>50／>5,000、最後一隊衝突、缺資產 | 明確分類；native hash、人物／物品、控制模式及所有外隊預約保持 |
| B4 傷亡與拘押 | KO、起身、死亡、清醒俘虜、原 guard 在群眾外、captor/guard 不同隊、牆邊及一人看守多名俘虜 | ID、傷勢、計時與有效看守關係保留；醒來／逃脫依普通規則；遺物不移動不重複 |
| B5 MOVE 接續 | 未走完 MOVE、partial formation、外隊在途、原 AI 開啟／關閉 | 原 goal／方向／AI 保留，真普通步進可走；在途中存檔、重新程序載入後繼續合法 |
| B6 其他命令 | HOLD／ATTACK／PURSUE／RETREAT／RETURN，原 origin／target／delay／routed；計時正值、零、合法負尾值與連續 goal | 收兵不代下新命令、不重置計時；普通表示與精確 envelope 符合 §4.3，返回後真普通流程可運作 |
| B7 原子性 | 候選預檢與提交邊界故障注入，重複失敗後再成功 | 無半提交／遺失 lease；不產生第二人物或物品 owner |
| B8 防回捲 | 收兵立即重部署；普通走路／轉向／換物後再部署；存讀後再部署 | 一律採當下真實坐標／物品；native-only 非幾何欄位依有效 guard 保留 |
| B9 完整 DR | 原 v8 場景 DR 真戰鬥、含帶 7 箭者，依既定期限自然脫戰，再收兵→普通動作→保存／載入→重部署 | 完整人物欄位與實物守恆，含真射擊減彈；只對 B 明列幾何欄位比較新合法值，不跳過其他欄位 |
| B10 完整 D9 | 普通啟動→載入 crowd baseline→B 收兵→再部署 | 最後用原 TerrainArmy，無殘留 crowd process／native owner；普通操作／存讀有效 |
| B11 最大普通容量 | 50 隊、5,000 名册人物加原 actor 的合法案例；含外隊時按總數限制 | 全部交接、可存讀及再次部署；記錄規劃時間／位移／記憶體，不宣稱 10k 收兵已支援 |

B2 不能只手工把所有人放格心；B9 不能以小場景代替自然戰鬥。一般模式原移動、陣型意圖、預約原子性與保存測試要在無 `--crowd` 下回歸；TerrainArmy 共用段抽取須證明原人工下令仍按原規則停 AI，而 handoff 不停 AI。

### 6.2 Atlas：正確性、失敗拒絕、版本、耗時分開

| 關卡 | 必測內容 | 通過依據 |
|---|---|---|
| A1 admission 等價 | 同批與原單次途徑、重複 appearance、不同 palette／男女／武器／卸裝；缺 optional prewarm | recipe 身分、frame、page、mask、palette 與 tracks 完整相等；不同外觀不誤合併；optional 缺失仍可載入，實際俘虜交易守門不變 |
| A2 去重證據 | test-only 函式呼叫／來源讀取計數，區分 batch、原 base/ranged 首次讀取 | 同批共同 DyeSources 不隨 recipe 數倍增；每個實際來源仍被驗證，報告剩餘重複 |
| A3 負向 | source hash、manifest、frame、page、mask、尺寸、appearance、路徑非法 | 非法 recipe 皆明確拒絕；必需 recipe 失敗不替換原場景，optional 分支依 A1；正式產物不被污染 |
| A4 下一次重驗 | 同程序兩次 admission 間來源變更、不同 root／namespace、前次部分失敗 | 第二次不接受第一次的過期 hash 或未完整驗證 entry；新程序也驗證 |
| A5 版本發布 | 舊版本留存、12 組 cache、女弓／弩、重驗等價證據或真重烘 | 原 publisher 與 runtime admission 全過，before/new 來源及 pixel hash 有完整清單 |
| A6 GPU 外觀 | 原 recipe admission 的 7 組正式 recipe、男女弓弩、卸裝、dye palette、四方向動畫與首幀 | 實際 screenshot／像素驗證，無錯頁、錯色、透明／mask 或動作偏移 |
| A7 普通回歸 | 原 Atlas／dye／female-ranged 測試，普通載入與 publisher validate | 普通入口行為一致，不依賴先跑 crowd 才能成功 |
| A8 完整 C3 | 同一不可變 D baseline、新程序、原 Controller load、600 步 hash／A／C／全座標／人物與實物 | 功能無退化；首幀正確；單列保存／完整載入及子階段耗時 |

所有來源變造、損壞 page 等負向測試用隔離副本與測試根，不能修改正式 GLB／圖集再嘗試還原。若新增極小測試接點，限定測試可觀察計數，不新增 runtime 可跳過驗證的開關。

### 6.3 性能與完成標準

- 完整保存 ≤ 300 ms、完整載入 ≤ 500 ms、5,000 人檔案 ≤ 原 v8 容量門檻；來源 hashing、page／mask admission、decode、必要 GPU 資源準備全留在應計區間。
- 用相同 baseline、硬體、build 與明示 process 狀態比較 before/after；新程序不等於 OS 磁碟冷快取。warm-cache 數字可以另列，不能取代正式完整路徑。
- v8 action step 平均 ≤ 12 ms、p99 ≤ 25 ms；事件平均 ≤ 0.1 ms、最大 ≤ 2 ms；新增 host 成本 ≤ 0.3 ms，維持各自原量測定義。現有包含共通尾段的 host 數字不可冒稱精確新增差分。
- Atlas 第一輪完工的證明是語意等價、重複來源工作確實減少、版本與 GPU 驗證成立。若完整 load 仍超標，明列「Atlas 優化完成、C3 性能 FAIL」，再依 profile 排定 Store／bind／decode 等後續，不放寬門檻。
- 收兵 B 完工必須 B1–B11 對應正向／負向測項完成；允許合法拒絕不等於所有布局都成功，也不允許以 BUSY 代替未完成 MOVE 或自然 DR 的必要正向案例。
- 這兩項完成仍不等於完整 C2／C3 或 10k release PASS。事件／host、L3、UBSan、launcher、上層正式 release 的缺口繼續逐項列出。

## 7. 施工順序與每段交付

| 段落 | 工作與依賴 | 可審閱交付／進入下一段條件 |
|---|---|---|
| P0 凍結 | 保存來源／產物／正式 Site 清單與現有證據；補 B 欄位及測試期望 | before manifest、精確修改白名單、測試清單；尚無新 PASS |
| P1 B 候選與 MOVE | 先加會失敗的 B2／B5／B7 案例，再補原 prepare、MOVE 共用準備與 metadata；小案例通過後提交接線 | 完整候選與原子失敗證據，原 row／引用保全，未完成 MOVE 真接續 |
| P2 B 整合 | P1 後跑普通移動／在途存讀／防回捲／完整 DR／D9／5,000 人 | B1–B11 結果、逐人位移、任何仍合法 BUSY 的範圍；不能只報 assert 數 |
| P3 Atlas 去重 | 可與 P1 的唯讀盤點並行；`crowd_site.gd` 由同一整合者串接，避免同檔互蓋 | 凍結程式與精確 source diff，先驗純函式及可獨立的負向項目；不暫時接受舊 hash 讓正向測試過關 |
| P4 Atlas 發布 | 依 P3 凍結來源，先於隔離 staging 做像素等價重驗或必要 GPU 重烘；用新產物完成 A1–A4 後才切換發布 | 新 namespace、來源計數、manifest／page／mask、A5–A7；每份產物可回復，失敗不替換正式版 |
| P5 合併验收 | P2、P4 同一版來源；跑 A8、B9／B10 與必要普通回歸、完整性能 | 同版功能／GPU／性能分列；300／500 ms 結論及剩餘熱點 |
| P6 報告與手動階段 | 整理 PASS／FAIL／未跑，接續仍欠的 L3／launcher／release | 更新原實作報告与本計畫狀態；只有完成所需正式驗收才關閉 C2／C3 |

P1／P3 可以分工，但共享 `crowd_site.gd` 的實際修改順序必須串行整合。普通 Army 的共用 MOVE 抽取與 Atlas 來源版本變化分別留清晰 diff，禁止夾帶無關清理、改人物規則或整批格式化。

## 8. 執行、資料安全與最終回報

- Godot 一律使用原 `godot-runtime-verify/scripts/verify_godot.ps1` bounded helper，不修改其 retention。依專案規則保留最新 100 個完成 run、全部未完成 run；本任務必要舊證據另複製到命名 output。
- 所有長程序有明確 timeout、PID/session/run ID；用可用 native status／wait 工具監看。無 schedule 工具時不建立代替用的週期 automation。
- 失敗保留 result／stdout／stderr，診斷後針對修正再驗；不反覆重跑未改變的失敗、不弱化測項。editor exit 0、headless、GPU、手動遊玩、性能分別記錄。
- 正式使用者 Site 不作試驗目的地；所有測試顯式指定隔離根，前後比對正式檔案。baseline 不自動存回；autosave/current/archive 各走原測試約束。
- 版本發布只操作列出的資產／cache，保留舊版及既有 LFS clean guard；不強制重設 LFS、不全目錄 stage、不推送／發布未列入的成果。
- 最終報告至少包含：修改檔案、B 人物／命令／預約結果與位移統計、Atlas 去重實測與版本清單、完整保存／載入及 action/event/host 數字、普通回歸、正式 Site SHA、失败及未跑項目。

**原計畫發布時狀態（保留歷史）：P0–P6 是後續施工安排。當時僅完成計畫與已定案狀態更新，沒有執行新程式、Godot 驗證、烘圖或資產發布。最後施工結果以上方狀態及本輪報告為準。**
