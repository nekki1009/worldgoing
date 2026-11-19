# 火攻 P0：Repository 基線與八項整合契約

更新：2026-10-06 00:12:21 +0800；工作區 `D:/worldgoing`；依據 WG-FIRE-001 與既定開工指令。

**P0 已完成，狀態 CONTRACT_READY；P1 尚未開始。** 八項工程接線與三項玩法政策已定案，24 個 required case 均具名 PASS，且 current／retained 來源閉包再次核對一致。這是原基線與契約可開工的結案，不是新火攻功能完成。

## 本輪來源與驗證邊界

- 實際船艦 SOURCE／ART／BUILD／ENGINE 交接見 [接受收據](output/fire_p0_close_20261005/SHIP_HANDOFF_ACCEPTED.json)；本案仍維持 ART／BUILD 不變，沒有新增 Native build。
- 本輪原碼／測試變更共 10 檔：1 個 production Lab 空值守衛窄修與 9 個原測試／fixture 檔。最終逐檔 hash 與差異摘要見 [delivery receipt](output/fire_p0_close_20261005/P0_FINAL_DELIVERY_RECEIPT.json)。Controller 存在時的原結構攻擊順序保留，沒有新 clock 或 owner。
- [24-case coverage](output/fire_p0_close_20261005/P0_FINAL_COVERAGE.json) 記錄具名 RunID、完整命令、各自 timeout、canonical 結果與來源閉包；合併輸入 188 項。有限窗口通過項只有完整 live／retained hash 仍吻合才承接，不要求為湊次數重跑。
- 原引擎仍為 Godot `4.7.2.stable.mono.official.ed1daf0bf`。本案為 headless／dummy renderer 原基線；正式專案仍使用 D3D12，不能從 headless 證據推稱畫面或效能。
- 初次資料／函式錨點與三份附錄保留其原 source epoch；附錄當時的 NOT_RUN 不覆寫本輪具名結果，新 fire 接線仍未實作。實際結果以 [FIRE_TEST_REPORT.md](FIRE_TEST_REPORT.md) 與最終收據為準。

三项既定政策保持：普通弓弩轉實際接觸命中，能力等只進一次散布、盾甲處理防護；任何活動火場讓原世界維持戰術倍率；局部安全沿原疲勞 owner 恢復，共享池所有成員均須安全／閒置。數值與 profile 是已選工程初值，不新增人類批准閘門。

## 1. 普通箭遷移：實際接觸政策已定案

現況為格射線＋到期 `SiteCombatRules.ranged_result`（`site_combat_rules.gd:101–146`）；Native對應 `rules.hpp:210–235`。弓range8／cooldown2／hold0.25／speed10，弩10／3／0.4／14；相鄰維持近戰。原chance含ability、training、fatigue、distance、moving、shield、armor、facility、power、brace；hit/graze另保留材質／護甲、小數HP、stun/stagger，不給knockback。

使用者已選實際接觸：ability/training/fatigue/distance與目標release時moving只影響一次穩定瞄準散布；power的accuracy進同一aim quality，原stun效果只在實際接觸加一次。盾牌只負責原朝向/姿態實體first contact，護甲合併到原材質接觸防護，facility改為真實結構掩護，brace改為contact防護倍率。新准入管線不再用舊chance/roll決定miss，不疊加第二次機率失手。

不變項：launch stats固定、arrival讀原當下防護、未接觸無kinetic/target heat、每箭一次kinetic與有限contact/ember。幾何擦傷以相對入射/接觸法線cosine<0.35判定，保留0.5傷害與小數HP；盾first contact終止箭，持盾者kinetic為0，有限heat只給真正接觸者，不能傷後方目標。初始brace倍率0.8，弓/弩普通profile保留原range/cooldown，fire先bow-only、額外prepare0.8action秒、item fire_arrow；弩fire明拒。原arrow5/cloth1/charcoal1付料加工5 fire_arrow，60game秒，原craft/loot/transfer入本人cargo。這些是有版本的工程初值，須P1/後續調校，沒有新增人類決策閘門。散布公式/seed、彈道/有限budget、保留與替代舊斷言見 [契約1／2附錄](output/fire_p0_20261005/combat_contract_fragment.md)。

**契約設計已定案；P0 原基線已具名通過，P1 新管線尚未開始。**

## 2. 四路後端與本人彈藥

- GD Actor：`TerrainTestCharacter.ranged_fire:1328`在本人`ammo_inventory`扣一次（Controller與原cargo保持引用），本人projectiles收flight；Lab `_resolve_ranged_fire:3018`／`_advance_ranged:3116`／`_resolve_ranged_arrival:3140`集中过濾及結算，原`ranged_apply_hit:1375 → apply_contact`寫HP。
- GD Army：`TerrainArmy.ranged_fire:6076`讀原row實裝／cargo，6107本人扣一次，圖集未准入則拒絕；`ranged_apply_hit:6136 → apply_unit_contact:7661`維持原KO／救援／半步。上游`SiteExchangeSnapshot.ranged_people:90`已有ammo篩選，新mode必須同步修改這個原查詢。
- Native CPU：`World::ranged_commit`（`combat.cpp:429–459`）在本人`ammo[i]`扣一次；`projectiles_advance:463`及native `apply_contact`寫HP；GD只消費EV_SHOT並回寫原cargo。現有投影僅一個arrow或bolt key，未完整無損支援雙mode前不得准入新fire或遷移NORMAL。
- 攻城：原器具cargo是彈藥owner，`SiteRuntime.release_siege_ammo:1270`原子扣物；Lab原siege flight／contact batch寫原人與parts HP。保留原ballista穿透／石彈落點契約，不把火箭第一接觸規則套掉攻城玩法。

P1方案：沿原Lab時鐘的一個集中projectile資料pool，原Actor／Army保留release交易，不再發布第二份可結算flight；原軍令接typed target、ammo mode及所有成功改令的serial，HOLD/MOVE/stop/改mode取消未釋放reservation，已射不退料。本人ready、原item/holder version、命令、目標及容量在無yield commit重驗，成功才一扣一建；拒絕保留原state。新物資沿原ITEM_NAMES／craft／loot／transfer，不造公共彈匣或免費轉換。

**新火攻現況全部未實作。** P1目標GD Actor／Army SUPPORTED，未完成逐案前仍GUARDED；Native新管線GUARDED；攻城原路保留、新ammo拒絕。原native舊NORMAL能力不等同新sweep支持。全部新在途、reservation、未結算impact與mode需接原import/clear/handoff/save guard；完整快照前回BUSY。

## 3. 共同時間、危害續期與休息：兩項政策已定案

原鏈為 `_advance_original_shared_step:1332 → SiteController.tick:2406 → SiteRuntime.advance:3701 → 原body/contact/work → record_completed_region_step:235 → RegionSaveSlot.record_completed_active_step:1105`。action是原固定30Hz exchange或120Hz舊路徑；game為combat1:1、peace1:60再乘原simulation_speed。新flight／ember／fire／exposure／lease／collapse用action；天氣／經濟／原疲勞使用game。

危害續期須在Lab1358–1359 pre-step換算前完成。在原`mark_combat:3690`增只續期不取消manual的明確選項，舊真交戰caller保留原中止語意。原世界只有共同game cursor；冷候選`replay_site_to:1395`現在依冷Site的combat_left/speed反算action，不能代表共同action區間。

使用者已選任何活動火災Site讓原世界維持戰術倍率。原RegionSaveSlot control/settlement擴版，原completed active step同批發布action/game起訖、speed及戰術片段，冷replay只消費已發布區間、不再自行反算或發布世界時間；下一active-step permit前把登記冷火場同步到當前世界水印，純fire摘要只引用原Site快照/水印，不另倒數、複製燃料或建世界owner。冷replay不遞迴觸發hazard同步，permit固定區間與來源epoch，拒絕保留原candidate/現場，避免兩邊互等。

TM-03數值：舊政策1action秒在和平Site發布60game，持續熱冷Site會燒60action；已定政策讓同一區間發布1game、冷火場也消費1action。0.5/1/2/4倍均保持1action對共同相應game秒。最後火冷卻沿原combat_left grace歸零才恢復peace，speed變更切分原journal區間；4個1action秒在1/2/0.5/4倍持續戰術時合計4action/7.5game。pause/resume/存讀及最後冷火場收束的完整数值/歷程/保留策略見runtime附錄§1.3。

TM-04使用者已允許局部安全休息：仍在原Actor/Army/Native/船上fatigue owner驗局部敵人、heat/smoke/collapse、原移動/工作；共享池所有成員都安全/閒置才恢復，不能拆第二疲勞池。當步接觸可能使恢復失效時，在原settle階段重驗候選再一次提交。住宅attendance/recovery局部安全化、設施可用性仍驗；新分配/返家/軍職/換裝/訓練/旅行/保存等原交戰guard保留，休息資格不授權這些操作。

原WorkTeam80休息、50復工，PersonFatigue延遲30game秒、恢復20/3600不改。連續安全且無加成80→50需5430game秒；最慢原speed0.5的持續戰術區間需10860action秒，再至多一原shared步讀到復工門檻。不提供wall-clock或有新危險時的恢復保證，原加成1～1.25不改。

全部直接combat_left consumer已列 [契約3／4／5附錄](output/fire_p0_20261005/runtime_contract_fragment.md:49)，包括Runtime時鐘／manual、Controller work/autosave/load/exit、Actor/Army/ship疲勞、housing、garrison、training、equipment、tent/craft、roster/officers、family wait、journey、Crowd clear/native clock/state。只保manual進度不足以符合本契約。

獨立 [算術查核](output/fire_p0_20261005/contract_arithmetic_result.json) 已PASS，亦記三個已確認政策；它只驗公式/數值，沒有調用production，**不代表TM-03/04執行PASS**。

**契約設計／數值已定案；原基線已修正並具名通過，新 clock/rest 接線尚未實作。**

## 4. 半步及動作互斥

維持原Prepare→Propose→Resolve→Commit→Finalize。`begin_committed_move:2665`先保留來源cells、moving_to/progress/duration/curve；body進行後，Coordinator `complete_committed_moves:516`整組檢查，再`finish_committed_move:2760`實際落格並pop。Finalize新接受不等於完成；無新提案者仍可能半步中。

後續sweep/exposure每個action slice從原owner前後讀motion，不建立位置副本。Army使用`movement_weight=p*(2-p)`及舊legacy curve；Actor的terrain_cell可先指目的，必須讀movement_from_cell和elapsed/duration；不能混用兩者語意。畫面exchange offset不參與碰撞。完成barrier與surface變更分段積分；船/native未准入則拒絕新fire。

滅火／接近放火沿`SitePersonActions._jobs`與原busy/duty接新kind、action-domain分支，原game advance排除同一job；接觸後才重驗並提交有效work/扣物。handled時間透過同一action→game區間映射回原fatigue，不能把action秒直接減game秒。P3先單SUPPRESS槽，P4再完整多lease/IGNITE。本輪原完成／互斥基線的具名範圍見 FIRE_TEST_REPORT.md；新 fire 作業仍待後續階段驗收。

## 5. 保存及交接

在原SiteStore純fire能力查詢＋Lab暫態hook整合拒絕原因，不另持有fire state。P1含projectile/reservation/pending impact；P2起含fuel/heat/焦痕/原資源parts損壞及persistent dirty；P3–P4另含exposure/job/lease/smoke/collapse收據。已冷卻但不能完整恢復仍BUSY。

必接原自存、save_to/capture、直接Store/RegionSlot save、同路徑load、async load候選提交、生成/地圖替換、exit、原地面跨界、船旅、冷候選、bind_terrain、GD↔Native import/clear；完整13類入口清單見runtime附錄。拒絕必須發生在寫檔、clear或替換之前，保留原save bytes／現場／cargo／命令。P5只解除已驗roundtrip的能力，延伸原Store schema及RegionSaveSlot候選重播；未解契約3不能啟完整跨Site接管。

## 6. 原燃料交易與取整

原自然key `kind:cell_index`、remaining/cleared/next_recovery在SiteEnvironment；原harvest:669、_regenerate:3991、rebuild_indexes維持唯一原物/導航。P2最小資源TIMBER，工程方案採Q=1024刻度/木材，原remaining=R加小數殘料r，F=Q×R+r派生，不能另存可獨立加減的完整fuel庫存。部分烧損產品以floor不再產出完整木材；未燃仍原批採4。

同界先原key/generation彙整burn，再重驗harvest/clear，最後一次索引/水/必要導航通知；現況Runtime工作早於擬接fire，實作必須在原交易入口分段／暫存重驗提交，不只改呼叫名稱。初次火耗也設原next_recovery；熱態延後原game-minute再生，清地不再生，r不退款成木材，恢復夾原capacity。算術4木燒256後R3/r768，採3後只餘768；4097種损耗守恆已驗，但production交易未實作。

P2最小已存在資產：complete standard house/body（8木4石，候選Fmax8192）與stone gate兩片wood leaf（各候選4096，frame=0 fuel）；不是新造門/屋頂owner。parts.hp唯一结构HP；fuel不按每幀HP重充。付費修復沿原request_repair/_feature_work完工guard，deltaF取缺料、實際deltaHP及已付可燃材料三者上限；全修成本沿原_repair_terms。不因取消、重送或upgrade免費補滿；熱/待倒塌時暫停已付job，保留cost/progress。

固定點/profile為本P0選定工程初值，供P2實作/平衡，不另要求批准數字、不另造物資鏈。P2守衛仍拒絕不能保存的新損壞；P5才擴原嚴格schema（resource changes已知欄位、parts目前只有hp、repair固定6欄），不放寬任意字典。其他建築／自然物／未完工素材未准入明列GUARDED。詳見 [契約6／7／8附錄](output/fire_p0_20261005/building_contract_fragment.md)。

## 7. 功能與實際服務

功能判定沿原`feature_usable:1418`，供DESTROY_FUNCTION與實際consumer共用。加工/供水原已有部分接入，其他入口仍需P4最小擴充：stock_endpoint只允許合法withdraw、拒新進料；已付batch/原holder保留，停增量不重扣料；housing/garrison保留原登記並停返回服務/加成，原在途命令沿原完成/取消；training停止原命令增量但保留成果。

OPERATIONAL照舊、DEGRADED只停profile列明功能、DISABLED停該feature服務、DESTROYED同步原結構結果。P2只驗上述單區與門洞，P4才多part依賴/BL-11。不能改stage或刪feature以停服務、使住宅/倉庫/駐軍引用懸空；真正失效return slot須在原關係owner原子重置命令/slot並通過Store，不能傳送人物。碼頭/船塢原水域/船修receipt guard保留，第一P2不准入這些船艦資產。P5 BL-12才證明失能服務/引用可存讀。

P4工程方案已列逐類功能依賴：house/warehouse/加工沿原parts擴版加roof，燃料從單區剩餘量守恆拆分不補滿；roof/body分別為原實體部件HP而非body鏡像。住宅依body+roof，倉庫新進料依body+roof/失能仍可withdraw，加工停未完批次但保留已付/完成品，井/取水依body，門完整關閉依原四part，牆通行按原逐part，軍營quarters/hq按入住/訓練分開。石倉及軍營parts是P4新增設定，現在尚未存在/實作；具體初值、舊布局遷移與拒絕未准入實體的邊界見building附錄§P4。

## 8. 倒塌警告與HP零點

保留原`damage_structure_part:3305`零HP立即失去支撐規則。warning只記part/generation/collapse序號/due action tick，為最晚倒塌時點；普通/火傷/攻城致死可提前崩塌，同一實體再受傷不重置倒數。到期用當前原part剩餘HP提交致死傷害，無第二份支撐HP。

火傷/到期/直接傷害合併原Lab `siege_apply_damage_batch:2584`，沿原damage結果收consequential_parts（frame連帶leaf），統一before→final差異，只一次 `resolve_structure_change:1636`／承諾步／墜落／lease失效。原guard拒絕時不先造殘骸或消費成功收據；generation真正替換才使舊事件no-op。P4 BL-10驗牆上/半步、提前致死、到期同界、重送及換代；原batch測試PASS不能替代新火攻事件。

## P0 閘門結案

G1 standalone Controller 空值守衛及正式共用步正向 witness、G2 完整 work clock、G3 原 female cadence 資源收尾、G4 原 Army fixture 歸併均已具名關閉。A／B／C 共 24 個 required case 均有本輪可核對的 PASS；原基線 PASS 不替代未實作的 fire 案例。

條件式未觸發回歸：`housing`, `garrison`, `training`, `ship_repair_atomic`, `ship_water_facility_guard`。原因：本次 production 僅 Lab 既有 Controller 空值守衛；其餘為原測試 leaf，未改服務、結構傷害、船修／水域 guard 或休息 consumer。

首次 P0 的 7 run（3 PASS／4 FAIL）、原 Army FAIL 與衍生 fixture PASS、borrowed replay，以及第一有限 loan 的 12 run（7 PASS／5 FAIL）均保留原結果；後續失敗與修正後 PASS 另列於測試報告。舊 receipt 不改成新來源的證據。

船艦 release 是來源／引擎交接。其具名 100 人量測保留航行 13.94 FPS、靠泊 16.39 FPS；原 `fps_threshold=null` 且不宣稱效能目標達標。本輪 P0 不擴成 SHIP、GPU、FPS 或發布驗收。原船艦失敗與限制仍由其收據保存。

P1 新箭／準備／本人扣彈與齊射、P2 燃料／局部安全休息、P3 暴露／滅火、P4 roof／功能／collapse、P5 fire 保存與冷火場、P6 Native／GPU／效能均仍是後續階段。此次停在 P0，沒有自動跨入 P1。

## 發布前原始文件封存

以下由發布腳本在寫入前保存原始 bytes，沒有重寫歷史內容：

- [FIRE_BASELINE_AUDIT.md 原始位元副本](output/fire_p0_close_20261005/doc_candidates/publication_20261005_161221_415113/original/FIRE_BASELINE_AUDIT.md)
- [FIRE_IMPLEMENTATION_STATUS.md 原始位元副本](output/fire_p0_close_20261005/doc_candidates/publication_20261005_161221_415113/original/FIRE_IMPLEMENTATION_STATUS.md)
- [FIRE_TEST_REPORT.md 原始位元副本](output/fire_p0_close_20261005/doc_candidates/publication_20261005_161221_415113/original/FIRE_TEST_REPORT.md)
- [FIRE_P0_GAP_CLOSURE_PLAN.md 原始位元副本](output/fire_p0_close_20261005/doc_candidates/publication_20261005_161221_415113/original/FIRE_P0_GAP_CLOSURE_PLAN.md)
