# 包圍交鋒缺口修補與完整驗收計畫 — 給 SOL

日期：2026-09-26（來源稽核自 9/25 接續）。狀態：**本輪只完成來源稽核與修補計畫，尚未執行本計畫的修正或新增驗證。**

接續 [原包圍修改計畫](SITE_ENCIRCLEMENT_SIMULTANEOUS_EXCHANGE_PLAN_SOL.md) 與 [上輪實作紀錄](output/encirclement_simultaneous_20260925/README.md)。目的：使失敗測試回到現行合法前置狀態，補齊同輪多人交鋒的時序、共享疲勞、移動、存讀與近景證據；發現真實缺陷才修原 owner。

## 1. 接手基線與不可改掉的需求

- 正式入口仍為 project.godot:15 → res://scenes/terrain_lab/TerrainLab.tscn。本次稽核分支 master，HEAD 39f14442a576df22557dcefddecc2f6e2ce3efa1；工作樹含大量既存修改，HEAD 不是目前程式基線。
- 接手前核對 [來源與 Git 狀態快照](output/encirclement_gap_plan_20260925/source_snapshot.json)。本文行號是本輪定位，若來源已變動，先依函式名重新查 caller。
- 已落地：同輪全部合格鄰接敵對 pair、每對獨立勝負、逐對 HP／暈眩／疲勞累計、每人一次呈現；多人只有全勝才呈現勝利。單對平手仍防禦；多人含平手呈現受擊，但平手沒有 HP 傷害。
- 舊方向 −8／−16／−24 能力扣分維持移除；一秒個人冷卻、技能資格、原實裝規則不變。本次不重新決定傷害封頂、包圍倍率或勝率公式。
- **疲勞以現行架構為準：同隊所有活人包含受控者共用一池；未入隊者才用個人值。** 控制切換不拆池。原計畫 §5 第 10 項曾寫「受控玩家保留個人值」，誤沿用舊政策；本輪已同步校正文案，不代表本輪修改正式程式。依據 PROJECT_ARCHITECTURE.md 的 2026-09-18 人馬疲勞統一，以及 TerrainArmy.sync_shared_fatigue。
- 人物與生命仍由 TerrainTestCharacter／TerrainArmy 持有；物品、死亡、保存由 SiteRuntime／SiteController／SiteStore 持有。不得建立第二套戰鬥、位置、疲勞或存檔狀態。
- 本計畫不要求重烘圖集、修改 GLB、改兵數上限、更新引擎／DLL、重寫尋路或還原無關髒檔。若後續真正受素材阻擋，先留下精確資產與守衛證據。

### 1.1 已有證據保留，不能全部重做或誤稱失效

上輪已通過 14 個 Actor 案例、圖狀交鋒、64 位元 pair 去重、反转遍歷、Actor 退格占位、原 Army phased API、200／5000 人批次／回退、1 對 3 GPU 與有程序內部署設定的 200 人 60 秒量測。原始 PASS／FAIL 與畫面都在上輪 output，不能覆寫。

本輪補的是以下證據差距：

- 手動呼叫 phased API 的共享疲勞測試，尚不等於真 Lab 多人 resolver 加同輪死亡與反序。
- 現有 ClockLab 只計算被消耗時間，尚不等於真人交鋒在慢幀下逐值一致。
- Actor 的小型第三勢力案例，尚不等於原三隊 UI／部署／保存整合。
- 1 對 3 的畫面，尚不等於 1 對 4 或普通圖集士兵作中心。
- 保存舊箭拒絕、戰後成功存讀、在途 cell 箭 BUSY，是不同合同，必須分開驗。

### 1.2 本輪查到的證據表述修正

1. site_ranged_flow_test 的錯誤源在 run:49。合併日誌先出 PASS、後出 SCRIPT ERROR，是 stdout／stderr 合併呈現，不能當成執行先後；實際是第 49 行保存守衛報錯，腳本仍抵達末端 PASS／exit 0，canonical verifier 正確列 FAIL。
2. site_encirclement_1v3_visual_test.gd:81 寫入 Army row.combat_ability，但 TerrainArmy.exchange_stats():3951–3964 實際取固定 TROOP_COMBAT_ABILITY=50。該欄不能用來設計新畫面的期望勝負。既有畫面的真 pair 結果仍有效，但常數 ABILITIES 不等於各 Army 的有效能力。
3. 歷史 9/14 動畫 parity 是舊方法掛在目前宣告／相依上的混合環境，不能因第一個欄位差異就推論本輪破壞單挑，也不能刪掉新欄位硬湊等價。

## 2. G1 — 修 Actor 保存樣本的披風資格（P0）

**已確認原因**

scripts/tests/site_exchange_actor_test.gd:111–119 從 HumanCharacter3DEditor.default_appearance() 複製衣裝並 seed 實物；預設含 cape_travel_01，人物沒有正式軍官資格。SiteStore._validate_cape_roles():285–312 拒絕是正確行為。失敗 run：20260925_230129_238。

**指定修改**

1. 在建立 appearance 後、複製 npc_appearance 與 seed_person_equipment 之前，明確設 appearance.parts.cape = "none"。
2. seed 後斷言兩個實物 holder 都沒有 equipped.cape；保留武器、明光甲、盾與原 item ID／數量守恆檢查。
3. 保留 _snapshot_preflight():279 的完整流程：舊精確箭樣本寫入／讀取、現行模式拒絕、歷史模式准入、UI 載入與家族轉移拒絕、原檔 hash 不變。
4. 整支測試必須跑到最後才 PASS。若合法衣裝後又發現舊工人遷移等新失敗，保留第一個實際失敗，依 Store／Controller 真路徑修該 fixture，不預先宣稱一行修正即可全過。

**不能採取的方式**

不授予假軍官職位、不跳過 cape guard、不刪除真正玩家現有披風。本項只是在 seed 前建立合法的全新測試衣裝。處理真實既有披風應走 SiteEquipmentOrders.retire_capes 或原換裝作業，但這不是 G1 所需。

**通過條件**

site_exchange_actor_test 整支 exit 0、無 SCRIPT ERROR、末端 PASS；原本明確的非法披風保存拒絕仍由 site_cape_role_policy_test 保持有效。

## 3. G2 — 補遠程 fixture 的原服務初始化（P0）

**已確認原因**

scripts/tests/site_ranged_flow_test.gd:47–49 只有 controller.lab = lab。supply_save_guard → cape_policy_guard → person_actions._person 時，person_actions.lab 尚為 null，導致 site_person_actions.gd:631 呼叫 _combat_target 失敗。run：20260925_230546_546。

**指定修改**

1. 設 controller.lab 後呼叫 controller.person_actions.init(lab)，再呼叫 controller.equipment_orders.init(lab, controller.person_actions)。順序沿 site_controller.gd:181、204；小型 fixture 參考 site_cape_role_policy_test.gd:27–32。
2. 先檢查初始化成功，再驗 supply_save_guard().code == "BUSY"。
3. _tiered_arrivals():120 建立的全新衣裝也先明確 cape="none"，再 seed。
4. 保留真扣彈、延遲落點、友傷攔截、相鄰近戰、射手 KO／死亡後已飛出箭與裝備級差檢查。
5. 本次触及的守衛／收尾採明確的失敗回傳，失敗後立即 quit(1)／return；末端 PASS 僅在所有區段成功後印出。仍以 verifier 結果判定，不以某行 PASS 或 exit 0 單獨判定。

這個最小 fixture 有三名裸 Actor，沒有完整物品／cargo／Site 保存上下文。它只驗遠程與保存入口的拒絕，**成功戰後存檔另由 G7 做**。不能一路往這個小 fixture 補假的服務，使它冒充正式 Site。

## 4. G3 — 把共享疲勞 runtime 測試遷到現行人物配置（P0）

**已確認原因**

scripts/tests/site_team_fatigue_runtime_test.gd:24、43–62 及後續多处依賴 lab.npc。現行 TerrainLab._ready():108–130 預設只建立玩家。只加 null 判斷會直接漏掉成員、控制、供養和存讀驗收。

**指定修改與明確預期**

1. 啟動正式主場景，斷言 lab.npc == null；使用現存 combat_actors 查空格，再部署四名原 Army rows。deploy_at 的可選 npc 參數可傳 null。
2. 原玩家未入隊時，保留個人 fatigue=72／rest=12、隊伍 pool=40 的獨立性；需要保存這個狀態時，另做加入前快照。
3. 以 lab.character 取代舊 NPC 作加入者：原四 rows 的 pool 設為 41、玩家個人值 11，沿原 join_player(lab.character) 加入。期望 (4×41+11)/5=35。
4. 沿原 _actor_supply_adapter(lab.character,true) 收取 5 的成本，期望共同 pool 變為 36；全五名活人讀同一池，count=5，rest aliases 一致。
5. 保存 actors 只含 player；讀回／bind 後五人綁新 pool，按數值及新場景內共享引用核對，不要求跨載入仍是同一 Dictionary 物件。
6. actor_mismatch、old_horse 負案例改寫 actors.player；保留 row mismatch、excluded_player_id 的拒絕及原檔保護。
7. 控制切換至少一案走原 SiteController._control_family_person(null, row_identity)，不能只寫 controlled_person_id 再重建池。斷言 pool 引用、count、fatigue、rest 均不因控制權切換改變。另保留「存檔控制 ID 指向 row，再 bind」的恢復案例。
8. 保留 v1→v2 疲勞遷移：舊 player_member／excluded_player_id 指向真玩家；高值 91、舊 horse=97 的案例依現有保守合併規則驗收，結果不低於 97，rest 不大於原較小值；重存只輸出現行 v2 欄位。
9. 保留供養 adapter copy-back 不憑空設 active；核對真玩家狀態與 Army summary 顯示同一共享值。
10. PASS 說明改為真玩家 Actor／控制 row 的涵蓋範圍，不再聲稱預設 NPC 成員。

原 owner 定位：terrain_army.gd:2140–2171 pool、:2302／2330 join/leave；site_controller.gd:2506–2525 控制切換、:2952–2962 供養 adapter。

## 5. G4 — 修三隊邏輯及三隊 UI 的舊交鋒 oracle（P0）

**必改兩支測試**

- scripts/tests/site_three_armies_test.gd
- scripts/tests/site_three_armies_visual_test.gd

後者同樣在 :133–145 禁止同人同輪多對，不能只修 headless 就宣稱三隊整合完成。

**身分與有效 pair**

1. _index_people():148 的 identity>2 改為驗正式合法 ID、全域唯一、與實際 Actor ID 不碰撞。現行 Army.valid_person_ids() 的合法域保持不變（1..2147483647）；ID 2 現在可屬 Army，不能恢復預設工人占掉它。
2. 原 resolver 的 64 位元去重／roll 測試仍保留。正式 roster 保存 ID 合法域與底層 pair 演算法寬度是兩個不同合同，不因本項縮窄 resolver。
3. 去重 key 改為 (round_id,min_id,max_id)。同輪只禁止同一 pair 重複，允許一人參與多個不同 pair。round_id 取原 Lab._exchange_round，不用畫格序號代替；一個慢畫格可能跨多個檢查輪。
4. 累計每人的 degree；專用包圍小情境必須真正出現 degree>=2，不能只靠全戰場總 pair 數代表多人交鋒。
5. _clear_patch():232 及其他 lab.npc 存取改為遍歷實際 Actor 清單。

**逐對事件轉成每人合計驗收**

1. _exchange 回呼只記 pair 與當下所有相關原 owner 的快照，不用單一 pair 傷害立即推算人物 HP。
2. 在同輪全部事件取得後，按 person ID 加總 hp_a/hp_b、stun_a/stun_b、fatigue_a/fatigue_b，正確處理 winner=1/-1/0。
3. 精確數值放在固定時刻直接呼叫原 _resolve_exchanges() 的三隊小情境：HP_after=max(0,HP_before−本輪合計)，有效合計受擊只增加一次 hit_revision，單次一秒冷卻、一次反應，KO／死亡優先。共享疲勞依 G6，不能把每人的費用當池直接加值。
4. 每個事件所見狀態都必須等於本批最終狀態，第一個事件也不能看見半輪。
5. 移除「受擊必須覆寫 persistent target」的舊斷言。HOLD 自衛不得製造新命令目標；有真攻擊命令者保留該命令直到原規則清除。
6. 完整 300 人時鐘跑動仍驗身分、合法 pair、占格、傷亡、事件與三種 faction 配對；避免用畫格前後差直接當本輪傷害，因其間還有恢復、移動與供養。

**正式 UI／部署／存讀**

沿既有 visual 測試 :47–94 的原 UI：先兩隊，再追加第三隊，確認原兩隊人物與命令未被重建；另測勾選第三隊一次部署。至少沿真按鈕 signal 完成 StartMeleeTrial／AddThirdMeleeTrial 與一個 SaveSite／LoadSite 流程，而非僅私有函式後聲稱按鈕驗收。

保留三勢力敵對、男女比例、隊長、第三隊占格／選敵、隊伍失能後剩餘兩隊仍交鋒、撤退及自然脫戰保存。每隊 100 人在正式上限內，不要用 5000 人 benchmark 的 guard 改寫。

## 6. G5 — 補現行單挑合同與真戰鬥慢幀一致（P1）

### 6.1 歷史 parity 的處理

scripts/tests/site_exchange_animation_gameplay_parity_test.gd:4、11–29 固定載入 9/14 舊方法並繼承目前宣告。run 20260925_231449_481 的首個差異是 bow shooter 缺舊版沒有的 weapon／armor 欄位。

- 保留歷史腳本、before_source、失敗與舊數據，明確列為「歷史差異診斷」，從本次必過 gate 中替換，不能悄悄重錄 9/14 基線。
- 在現有 site_exchange_flow_test.gd 擴充現行單對案例，作為替代 gate；不用另外造一份戰鬥實作。
- Actor 與 Army 的單對勝／小敗／大敗／平手，驗明確 HP、暈眩、疲勞、一次冷卻、技能、合法／阻擋擊退及近接弓弩。保留單對平手防禦，不能用多人受擊期望套到它。
- 必須有獨立的固定預期值與原 owner 狀態，不能只讓直接入口和批次入口彼此相比。若比較 apply_exchange 與 Lab 的單 pair，比較範圍需排除已明確改正的舊逐人命中回報覆寫，並單獨驗最終角色狀態；不能刪除生命、位置、預約或彈藥欄位。
- 已飛出箭與 shooter.weapon／armor 由 G2/G7 的現行遠程合同驗收，不刪掉 shots 或新裝備欄位讓歷史測試變綠。

### 6.2 慢幀須走真 _advance_action_time

現有 flow test:69–85 的 ClockLab 覆寫 _advance_combat 只累加時間；保留它作簡單時鐘測試，新增真人狀態案例。

1. 以相同 seed、ID、有效裝備、命令、起始冷卻／位置建立兩份獨立原 Lab+owner；停止自動 _process，只由測試送入時間。
2. 呼叫原 _advance_action_time，不能覆寫 _advance_combat，也不能只各自 advance_combat 後手動補一個 _resolve_exchanges。
3. 正常分割用 1/60 秒；慢幀分割含 0.017、0.184、0.4 秒等，總時間嚴格相同。至少跨第一次交鋒、約 1 秒再次可交鋒、一次已承諾步完成，共 3–4 秒。每個可比較檢查點的累計模擬時間一致，保留末尾不足 1/30 秒的 remainder。
4. 用同一模擬 tick 安排命令／地形變更，不按外層畫格號安排。記錄每個 round 的規範化 pair、勝負／margin、HP/stun、一次成本及 owner state。
5. 比較：_exchange_round、_exchange_phase、_action_time_remainder、HP/stun/KO、fatigue/rest、冷卻／技能、cell/source/destination/progress、Army 保留格、命令與事件。浮點只用有理由的極小容差，不能把不同 pair、漏輪或多輪用容差放過。
6. 加真 Site pause 和 SceneTree pause：暫停期間生命／技能／移動與交鋒輪不推進；恢復後只完成原本應發生的步進，不補發暫停時間的交鋒。
7. 此項若失敗，先定位是測試沒有走共同時鐘，還是真 _advance_action_time():898／_advance_combat():946 漏餘量。只有後者才改原時鐘，不增加第二份計時器或限制慢幀累計。

注意：既有 site_movement_input_clock_test.gd:40 也仍有 lab.npc.place，不能拿未修的它作現成 PASS；可借測試方式，勿盲目宣稱可直接沿用。

## 7. G6 — 補真 Army／混合 owner 的同輪邊界（P1）

優先擴充 site_encirclement_simultaneous_exchange_test.gd；原 owner 單独的移動與技能邊界繼續放 site_exchange_army_test.gd／site_exchange_actor_test.gd。只在兩個以上測試實際共用時，才抽一個小 fixture helper。

### 7.1 死亡前共享分母与反轉順序

- 原同 pool 至少四名活人：一人本輪多對後死亡，一人多對但存活，至少一名未參戰隊友。另有同輪 KO 而不死亡案。
- 直接走真 Lab._resolve_exchanges。期望 pool_after=clamp(pool_before+本隊逐對總費用/N_before,0,100)。本輪所有費用先付，死亡才減 count；KO 仍是活人，不能減池人數。
- 同 ID／seed／位置／技能，改 combat_armies 名冊順序及 batch 開關；規範化 pair 和每人生命、pool/rest/count、死亡次數與技能消耗一致。
- 不直接 reverse Army rows：它有 cells、moving_to、combat_units 等平行結構；只調合法 owner 遍歷順序，或重建相同身份的等價 fixture。
- 含受控隊員與玩家 Actor 已入隊的案；控制權不造成額外個人疲勞。用現有 _received_effective_hit／hit_revision 和原死亡 signal 計數，不新增 production 計數器。

### 7.2 多人硬直、競爭退格與已承諾步

至少包含：

1. 中心同輪兩次大敗：HP／stun 累計，硬直取最大一次，最多一個擊退目的格；同級來源按原確定性選取，反轉 pair 不改結果。
2. 四周已占或牆邊：留原格，不追加撞牆傷害，全部 pair 仍生效。
3. 兩名不同 owner 同輪想退往同一合法空格：最多一人取得原預約；固定 person ID 的提交順序下結果穩定，無疊格與兩份 claim。
4. Actor／Army 已在原步中被多人打中：不更換原 destination；到達後保留一次完整最大硬直，不重收 movement remaining，也不憑空再退一格。
5. 阻擋者在本輪生命階段死亡／KO：擊退發生於生命提交前，不能先利用尚未釋放的格；生命與移動結束後依原 owner 釋放。
6. 同輪中心死亡但有局部勝利：被它擊敗的人照收傷，死亡 signal／遺物處理每人一次。

斷言依原 occupies_cell／blocks_cell 與原預約查詢；不把本來已依規則釋放占位的倒地人物判成新重疊，也不忽略進行中一步的 source／destination。

可能修正位置僅限 TerrainLab._settle_exchange_batch、Actor.exchange_batch_*、Army.exchange_batch_* 與原預約入口；先有失敗重現再改。不可放寬 _reserve_combat_step 一般守衛。

### 7.3 多對技能與反應只觸發一次

固定原合法隊長／受控人物，開 power 或 brace，同輪面對 3–4 人。確認所有 pair 讀到同一輪前技能，每人只清一次 queued skill／開始一次 8 秒冷卻；無合格 pair 不消費，普通兵不能突然取得技能。全平本輪新增 fatigue 成本為 0，既有疲勞不歸零，rest／active 仍依原 PersonFatigue.charge 合約處理；混合勝平依原逐對成本。最後事件是本人獲勝，也不得蓋掉其整輪受擊。

## 8. G7 — 新增包圍戰後真實存讀驗收（P1）

**新增一支** scripts/tests/site_encirclement_save_test.gd，使用正式 TerrainLab.tscn＋原玩家／真正部署的 Army，沿 SiteController 與 SiteStore；不改保存 schema。

既有 site_combat_save_test.gd:17 仍依賴 lab.npc，:47–64 主要驗舊 attack/projectile snapshot，這次不把它混成現行新模式 gate。可參考 site_ranged_deployment_test.gd:99–113 的等待／capture／save/load/bind，以及 site_cape_role_policy_test.gd:381–420 的檔案不變檢查。

### 8.1 成功保存與讀回

1. 使用生成地圖上的合法空格及合法真實物品 holder；非軍官無披風。若必須修改地形，透過已保存的 terrain_changes 和原重建入口，不能只改 RAM 平地卻期望讀回相同。
2. 先產生一份成功基準檔於本測試唯一 output 路徑，保留 hash。透過真多人交鋒形成中心存活但 HP/stun/fatigue 已變的案；另設一名包圍者 KO／死亡案，確認局部勝利仍有真效果。
3. 發原 HOLD／RETREAT 等命令令雙方真正分離，再由共同時鐘自然收束：飛行、原步、硬直、combat_left、_pending_deaths／遺物。HOLD 本身不保證脫戰，仍相鄰時應用合法撤離命令；不得直接歸零 combat_left、清 pending、clear_army 或 reset_combat 來通過。
4. 保存前一刻按 person ID 拍「可保存狀態」期望。等待期间 stun 可能自然恢復，不能拿交鋒瞬間的數值硬比保存後狀態。
5. 經 controller.save_current 寫測試路徑，再 Store.load_site／lab.bind_terrain 恢復。核對 ID／隊伍／勢力／控制者、HP/stun/grace/KO、pool/count/rest、位置／命令／部署、彈藥、item IDs/holder/equipped/dyes、死亡與遺物引用；沒有免費治療、復活、補彈或再發物品。
6. 同一檔再次載入，確認不重複扣血、成本、死亡掉落或增加 roster；actors 仍無預設 NPC。瞬態依現行 restore 契約重置，不要求保存一個尚未完成的 pending round，也不新增相關欄位。
7. 遺物及正式 item_records 數量／ID／holder 守恆；原死亡 owner 完成一次，不只看最後總 HP。

### 8.2 拒絕保存與原檔保護

同一基準檔分别驗：

- 真多人交鋒造成 combat_left>0：save_current 最終 BUSY、檔案 hash 不變。Store.save:25–26 持有此 guard，不能只用 supply_save_guard 替代。
- 原弓／弩已發射未抵達：supply_save_guard BUSY、save_current 不覆檔、archive_before_replace 拒絕、直接 bind_terrain 不替換 terrain 或丟掉 flight。射手已扣彈不還原。
- 射手中途 KO／死亡：已飛出箭仍只在到期結算一次，後續收束才可保存。
- 尚有 _pending_deaths／遺物工作：仍 BUSY；自然完成後保存成功。
- 舊精確箭：依原 exchange_snapshot_guard 回 UNSUPPORTED_ACTIVE_PROJECTILES；與新 cell 箭的 BUSY 分開驗。

拒絕前後核對檔案 hash 與原人物／物品／flight 等權威狀態；不要要求正常推進中的所有暫態欄位永遠不變。若保存守衛前會更新可重建的保存投影，也不能誤判為扣血或改物。

## 9. G8 — 擴充 1 對 4 與 Army 中心的 GPU 證據（P1）

沿 scripts/tests/site_encirclement_1v3_visual_test.gd，加入少量 --case 參數；預設保留既有 1v3。每次程序只建一個正式場景與一個案例，獨立輸出子目錄，不覆蓋原畫面。

1. 使用原玩家＋Army 四 rows；仍只用原隊長即時來源與圖集士兵，不建立四個 Actor editor。原第一個 GPU 失敗已證明 D3D12 資源可耗盡。
2. 四個必做 case：1v4-all-win、1v4-mixed、1v4-draw、1v4-blocked-push。mixed／draw 至少另有普通 Army 圖集兵作中心的 case，用原兩支 Army 呈現；不能只驗玩家／live 隊長。
3. 有效能力取 actual exchange_stats／_exchange_context。移除或改正目前對 row.combat_ability 的無效設定；以真支援的玩家能力、隊伍訓練、有效配裝、合法技能、固定 seed／ID 選出能重現的案例，預先寫死預期。不可 override exchange_stats、注入最終 result 或每輪重擲直到中想要的結果。
4. 配装必須在畫面、實際讀出的 stats 和案例描述一致；保存測試一定用真 holder。若近景採既有人工平地／受控配裝 fixture，報告明列其範圍，不把它當原始地形或存檔驗證。
5. 交鋒前、同輪提交後、0.1 秒後、反應結束後各擷取。每張 PNG 對應 JSON：round、原 ID/owner/row、四個 pair、effective stats、margin、HP/stun/fatigue 合計、全勝旗標、冷卻／技能、反應與原占格／目的格。
6. 全勝中心無損且四名敗方各受傷；混合中心受擊且局部勝利不取消；draw 不增加額外 HP；四面被占的大敗只留原格、單次硬直、沒有重疊。
7. 每人同輪動畫起始次數用現有 animation／reaction 狀態或測試端觀察檢查，不在 production 加永久每幀日誌。
8. 程序 PASS、ExpectedOutput 全新寫入、JSON 真值與人工看圖三者缺一不可。中心失能時應看到原 down／KO，不能為了指定 hit 而取消真實暈眩。

## 10. G9 — 消除 200 人效能證據的部署來源替換限制（P2）

這是測試工具設定修正，不是新的效能優化。若要宣稱「現行 source 的正式主場景 200 人驗收完整」，本項必做；否則只能保留上輪 410 FPS 的原限制，不能自行升格證據。

指定修改 scripts/tests/site_army_scale_realtime_test.gd:760–790：

1. 只有 per_team > TerrainArmy.MAX_ROSTER_SIZE 才替換部署 guard。現行 MAX_ROSTER_SIZE=200，100/隊不需要任何替換。
2. 沒有其他試驗來源替換且文字相同時，不賦值 source_code、不 reload。保留 5000 人受控測試原有模式，不改 production 上限。
3. 報告分列 disk_source_changed、runtime_source_changed、deployment_override_applied；舊 source_files_edited 若保留則給明確相容說明，不再固定填 true 混淆磁碟與程序。
4. 普通接受 run 只用 --per-team=100 --seconds=60，不帶 reference／profile／renderer 實驗參數。初始化完成與收尾都核對原 Lab、Army、Actor、Rules 及用到的 renderer／snapshot 來源與磁碟；字串比較可一致處理換行，但磁碟原始 hash 另外保存，不忽略任意內容。
5. 原場景、原地圖、原人物與圖集；平均>=30 FPS、P95<=33.334ms、每段完整10秒窗>=30 FPS，保留全 frame_ms/frame_at。
6. 舊 410 FPS 數據／限制保留，新結果另存，不將測試條件改變叫做效能增益。只有新的程式修改或未解決的性能疑慮，才需要額外 A/B，不例行無限重跑。

## 11. SOL 的檔案與工作分配

### 11.1 預期修改的既有測試

- site_exchange_actor_test.gd：合法披風 fixture；保留舊箭保存拒絕。
- site_ranged_flow_test.gd：原服務初始化、合法新衣裝、失敗即停止。
- site_team_fatigue_runtime_test.gd：現行玩家／隊員／控制權／共享 v2。
- site_three_armies_test.gd 與 site_three_armies_visual_test.gd：ID 與同輪 pair／aggregate oracle、實際 UI。
- site_exchange_flow_test.gd：現行單挑與真時鐘分割。
- site_encirclement_simultaneous_exchange_test.gd：混合 owner、死亡分母、競爭退格與技能；必要時只擴充原 Actor／Army owner test 的對應斷言。
- site_encirclement_1v3_visual_test.gd：案例參數與 1v4／Army 中心。
- site_army_scale_realtime_test.gd：G9 的條件式測試 override 與真實報告。

預期只需新增 site_encirclement_save_test.gd（及 Godot 產生的 uid）。若某既有測試因過度膨脹需要拆檔，按一個明確合同拆，不為每條 assert 新建框架。

### 11.2 正式程式只在新反例證明必要時修改

可能涉及原 terrain_lab.gd、terrain_test_character.gd、terrain_army.gd、person_fatigue.gd、site_controller.gd／site_store.gd／site_person_actions.gd。這是條件性名單，不是要求全部改動。每次 production 變更需在報告記「最小失敗案例 → 真 caller → 原 owner 修正 → 修正後 PASS」。

不為合法 cape 拒絕削弱保存政策，不為 null fixture 增加靜默忽略，不把具體 bug 擴大成系統重寫。

### 11.3 可平行的開發切片

- A：G1/G2，獨立處理兩份小 fixture。
- B：G3/G4，共同處理疲勞、三隊与 UI 的現行資料合同。
- C：G5/G6，處理時序與多人原 owner；此組獨占 flow／simultaneous 測試，避免多人同改。
- D：G7 存讀，依 A/B 的合法 fixture 成果接續。
- E：G8/G9 GPU 与量測，等核心測試穩定後驗。

程式編輯可平行；Godot editor／headless／GPU 程序在此工作樹依序跑，避免 import、原生模組與 GPU 資源互相干擾。使用原生 agent/status/wait 主動監看，不另外建立 recurring automation。

## 12. 執行順序與有界驗證

1. 接手讀 AGENTS.md、PROJECT_ARCHITECTURE.md、原計畫與本文，核對來源 hash／相關 diff；保存本輪前置快照。
2. 先 G1/G2 小修並各跑整支，確認那些 FAIL 不再掩蓋後段錯誤。
3. G3/G4 的 headless，加 G5/G6。只有新實際反例才改 production。
4. G7 成功存讀及全部拒絕案例；接著原 cape 政策回歸，確認並未降低守衛。
5. 一次 editor/import；G8 逐 case GPU 與 G4 三隊 UI GPU，逐張檢視。
6. 若 G9 完成，跑現行來源 200 人60秒一次；若曾改 Lab／Army 結算，再跑既有 200／5000 batch parity。若只是文件修正，不重跑性能。
7. git diff --check、明確檔案清單與來源 hash、回填報告；不要 git add -A，不自動 commit／push。

本次已確認可用引擎絕對位置，接手先 Test-Path 驗證仍存在。所有 Godot 用原 helper，不複製／改寫 helper：

    $verify = Join-Path $env:USERPROFILE '.codex\skills\godot-runtime-verify\scripts\verify_godot.ps1'
    $godot = 'C:\Users\Nekki\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe'
    & $verify -ProjectPath (Get-Location).Path -GodotExecutable $godot -Mode headless -TimeoutSeconds 120 -GodotArguments @('--script','res://scripts/tests/site_exchange_actor_test.gd')

其他 headless 換 script；editor 用 -Mode editor。G8 預計加入的 --case 參數實作後才可使用：

    & $verify -ProjectPath (Get-Location).Path -GodotExecutable $godot -Mode visual -TimeoutSeconds 150 -GodotArguments @('--script','res://scripts/tests/site_encirclement_1v3_visual_test.gd','--','--case=1v4-mixed') -ExpectedOutput @('output/encirclement_gap_closure_20260925/visual/1v4-mixed/result.json','output/encirclement_gap_closure_20260925/visual/1v4-mixed/03_reaction.png')

實際 case 輸出以實作一致命名；不能讓舊 PNG 滿足 ExpectedOutput。200 人60秒程序上限180秒：

    & $verify -ProjectPath (Get-Location).Path -GodotExecutable $godot -Mode visual -TimeoutSeconds 180 -GodotArguments @('--script','res://scripts/tests/site_army_scale_realtime_test.gd','--','--per-team=100','--seconds=60')

AGENTS.md 已授權分析失敗、針對性修正及重新驗證，不需每次測試失敗再要求批准。Crash／timeout 要先調查；不加長期限掩蓋停滯、不反覆重跑相同失敗。保留 helper 的最新100次完成與全部未完成 run 機制，重要 result.json／stdout／stderr／combined.log 複製到本任務 output。

## 13. 完成門檻與交付

新增 output/encirclement_gap_closure_20260925/README.md，逐 G1–G9 寫「已修正／已驗證／仍有缺口」，附來源 hash、引擎、命令、run ID、退出碼、耗時、首個錯誤與修正、畫面及原始 JSON。不要覆寫上輪 output。

本需求可宣稱完整補齊，至少要有：

1. G1 Actor、G2 ranged、G3 fatigue runtime、G4 三隊 logic 與 UI 整支通過；舊失敗仍可追溯。
2. 現行單挑 gate 取代無效的9/14 oracle，所有保留／排除欄位與原因明示；不能把歷史差異說成歷史全等。
3. 真共同時鐘下正常／慢幀／暫停、真混合 owner 的死亡分母／技能／原步與競爭退格通過。
4. 真戰後成功保存、重複載入、不治療／不重發物品，以及戰鬥／飛行／死亡待結算／舊箭拒絕全部有證據。
5. 1v4 全勝、混合、平手受擊、退路阻擋，以及 Army 圖集中心有狀態對照和可檢視近景。
6. 若宣稱無程序來源替換的正式效能，G9 必須有新 run 與磁碟／程序來源一致證明；否則把該限制明確保留，不冒稱完成。

若仍受真正資產准入或保存資料問題阻擋，SOL 必須附具體第一個反例與原 owner 定位，完成所有不受阻的項目。不得只拿本輪新增局部 PASS 取代原本失敗的整合測試。

**給 SOL 的執行摘要：先把測試的合法人物、原服務初始化、共享疲勞及無向 pair oracle 修正，再补真時鐘／多人 owner／戰後存讀／1v4與三隊 UI；只有實際失敗證明需要時才動正式程式。保持已確認的包圍玩法與現任 owner，最後用完整證據關閉各缺口。**
