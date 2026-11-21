# 昏迷恢復與近身自衛修正計畫 — SOL

日期：2026-09-26。正式入口：`project.godot` → `res://scenes/terrain_lab/TerrainLab.tscn`。

## 1. 任務與交付

使用者回報：昏迷者醒來後，旁邊有敵人仍站著不動；昏迷恢復太快。要求先讀目前專案、擬定詳細計畫，再由 SOL 實作。最新明確指示：「這是昏迷又不是暈眩，應該用遊戲裡面的小時做單位吧」。本版已取代先前動作秒／分鐘方案。

本文件先完成靜態稽核與可執行規格，再交 SOL 實作及驗證。稽核尚未重現使用者當時的整場戰鬥，不能把以下命令死結說成所有發呆現象的唯一原因。

交付必須包括：最小正式修改、可重現原缺口的整合測試、相關原回歸、正式場景畫面、失敗紀錄及驗收範圍。禁止只把動畫改成攻擊來假裝已作戰。

## 2. 已查明的實際流程

### 2.1 失去指揮後的近身交鋒死結

- `scripts/terrain_lab/terrain_army.gd` 的 `apply_unit_contact()`（稽核時約 5010 行）保留原人物與格位，將暈眩達門檻的存活人物設為 `down`／`ko`。
- `TerrainLab` 每共同小步呼叫 `settle_combat_command()`；Army 約 2552 行找不到合格指揮者時，設 `needs_attack_order=true`、`combat_attacking=false`、清除舊 target，並轉 `HOLD`（既有撤退例外）。
- Army `prepare_combat()` 約 4895 行扣 KO，交 `_wake_unit()` 約 4802 行檢查占格並切 `get_up`。`_advance_exchange_pose()` 約 4258 行完成原 2.2 秒起身後回到 idle。兩處都有標記指揮狀態需更新。
- 指揮恢復不會自動恢复舊進攻；這是 `SITE_COMBAT_DESIGN.md` D50 與 `site_army_command_save_test.gd` 的既有必要規則。
- Army `exchange_initiates()` 約 2904 行僅准一般隊員在有指揮、非待令、非潰退的 ATTACK/PURSUE 發起交鋒。
- Lab `_resolve_exchanges()` 約 1514 行又要求雙方至少一方能發起。因此雙方皆失去指揮、之後醒來並留在 HOLD 時，即使相鄰、清醒、冷卻完成也可以永遠不交鋒。
- `SiteExchangeSnapshot` 每輪重建；現有證據不支持另造目標快取修復器。任一方仍有合法攻擊令時，原流程能讓另一方參與交鋒，不能泛稱所有醒來者都壞了。

### 2.2 醒得快有兩條路徑

- `site_combat_rules.gd:9` 的 `KNOCKOUT_SECONDS=30.0`，Actor 與 Army 都直接扣未倍速動作 delta。
- `terrain_lab.gd` 約 959 行已有日曆／工作／疲勞共用的 `game_seconds`（含 `simulation_speed`）；約 974／978 行傳入身體 owner 的仍是 `elapsed`。昏迷要改用這個既有遊戲時間增量，不修改整體時鐘或 `Engine.time_scale`。
- Actor `start_rescue()`／`start_rescue_unit()` 直接設定 `_rescue_left=4.0`；Army 以原 `unit.age` 達到 `POSE_SECONDS.rescue=4.0` 完成救助。
- HOLD 中原自動安全救助可能讓人約 4 秒就開始起身。因此只改自然甦醒不涵蓋救醒。
- 原生 recovery 對將跨過甦醒邊界的列交回 GDScript，get_up 亦走原 owner；未發現原生倒數偷跑證據。

### 2.3 不能漏掉的保存與文字

- Actor `SAVED_FLOAT_FIELDS` 約 152 行限制 `knockout_left<=30`，約 156 行限制 `_rescue_left<=4`。
- Army `valid_combat_state()` 約 5572 行限制 `ko<=30`，約 5625 行限制救助者 `age<=4`。
- Army `_wake_unit()` 未更新 `unit.status`，醒後可能仍顯示 Unconscious；Actor 已設 Awake/Captive。此為文字殘留，並非作戰資格根因。
- Lab 救助按鈕有「相鄰四秒」字樣。不能只改倒數而保留錯誤說明。

## 3. 本次玩法規格

### 3.1 恢復時間

使用者已決定單位是「遊戲小時」。本次採 **自然甦醒 4 遊戲小時（14,400 遊戲秒）**、**成功救助將剩餘等待縮短至最多 1 遊戲小時（3,600 遊戲秒）** 作為可調初版。精確的 4／1 小時是本次設計預設，不是使用者指定數字，也不是現實醫療恢復時間。

- 共用自然上限應明確命名遊戲時間，例如 `KNOCKOUT_GAME_SECONDS`；改前搜尋所有呼叫。救助後上限亦集中於同一規則檔。新昏迷及倒地再受有效暈眩衝擊均重設至自然上限，不疊加。
- 施救動作仍是原 4 動作秒、原 `_rescue_left`／`unit.age`；完成時改為把傷員原 KO 剩餘值 `min(目前值, 3600)`，不立即呼叫 `_wake_up/_wake_unit`。只有自然剩餘遊戲時間到零才進原起身流程。
- 傷員 KO 已不大於 3600 時，救助已沒有縮短效果，開始／自動選人時拒絕，避免 HOLD 同伴每四秒反覆做無效救助。不新增已救助旗標或另一份醫療帳本。
- `CharacterCombatTimings.POSE_SECONDS.rescue=4.0`、down=2.875、get_up=2.2 都保留；無需延長救助動畫、重烘焙或新增動畫映射。
- 暫停不倒數；0.5／1／2／4 倍速與和平／交戰切換讓 KO 按原 Site 日曆同樣速度消耗，當且僅當遊戲時鐘累計過 4 小時才自然醒。攻擊、硬直、施救、起身動畫仍用動作秒，不得隨日曆加速。
- 甦醒不補 HP、物品、裝備、疲勞，不解除俘虜；死人不能救醒。有效受擊／移動／換令仍依原規則中斷救助。
- 原格被占用時維持昏迷並沿原短重試，不穿人、不瞬移、不強占預約、不重設整個 4 小時等待。若原 0.1 剩餘值沿 KO 欄位表示，明確其現為遊戲秒，於下一共同動作步重試即可，不另造重試時鐘。

### 3.1.1 時鐘傳遞與原生快路

- Lab 每共同小步將已算出的 `game_seconds` 傳入 Actor／Army 既有 advance／prepare 入口，只讓 KO 扣此增量；其他原欄位照 `elapsed`。函式可新增具名含義明確的可選參數，直接測試用明確 1:1 遊戲秒預設並記錄，不自行再乘倍率。Actor `_process` 的非 Lab 正式呼叫亦須讀原 Site 遊戲時間；純預覽無 Site 時才能明確採 1:1，不可留下另一條正式舊時鐘路徑。
- `native/army_idle/army_idle.cpp` 的 recovery 快路目前也扣 KO，不能把所有 delta 換成 game_seconds，否則冷卻和動畫也會加速。
- 不重編 DLL 的最小安全方案：當 game_seconds 與 action elapsed 相等時保留 recovery 快路；不等時使用已存在的 `advance_prefix`（只接無 KO 的 idle），讓昏迷列走原 GD 扣正確遊戲秒。保留普通靜止兵加速，不全局關閉 native_queries／renderer。
- 將此快路限制寫進證據：這是正確性修正，不宣稱性能收益，也不改另一個 GPU 工作的呈現實驗。

### 3.1.2 舊檔單位遷移

- 這次是計時單位改變，不能只把舊 17 動作秒默默當成 17 遊戲秒。優先將原 Actor／Army 身體快照 `schema=1` 升為 `schema=2` 表示 KO 遊戲秒；SiteStore 外層 FORMAT 不必連帶更動，不新增第二份 KO 值。
- 舊 schema=1 先依舊 0–30 動作秒上限驗證，再按 `old_remaining / 30.0 * 14400.0` 轉成新遊戲秒，保留昏迷等待的剩餘比例；零值仍為零，HP、俘虜、起身鎖不變。這是明確遷移政策，不能宣稱可還原舊檔未保存的歷史遊戲倍率。
- 新 schema=2 按 0–14400 驗證，重複保存／載入不得重複乘倍；未知版本、非有限值、負數、超上限拒絕。迁移必须在原 restore／normalize 邊界處理，驗證函式不偷偷修改外部字典，SiteStore 仍須先驗證才原子替換。載入訊息／交付說明明記舊版一次比例換算。
- 舊進行中救助動作保留剩餘／已過動作秒，但完成套用新規則（縮短 KO，不立即醒）。這是明確玩法遷移，不宣称旧救助完成效果不變。
- 無 editor 的 Actor 原 `visual_state.animation_time` 會累加，但 `valid_state` 的 pose_time 上限是 60。必須重現長昏迷保存，再將 unconscious 等原循環姿態時間正規化為素材取樣範圍；不可全面放寬所有姿態／數值守衛。

### 3.2 起身後近身自衛

保留 D50：失去指揮後即使隊長回來，也不自动恢復 ATTACK/PURSUE，不擅自追人或開遠射。

在既有 Lab 四向相鄰近戰配對入口，補上原 Army 提供的自衛資格：

1. 非受控、仍有正式隊籍的原人物。
2. `combat_order==HOLD && needs_attack_order`，且非潰退、非原工作／運補／拘押等忙碌人物。
3. 仍通過原 exchange_ready／exchange_can_receive：清醒、起身完成、自由、站定、未救助、原冷卻及硬直限制。
4. 對方異陣營、四向相鄰且 `terrain.can_attack_across()` 合法；仍由原 Lab 一輪配對、去重、數值與傷害 owner 結算。

這個資格只給「近身交鋒」使用。遠程仍採原 `exchange_initiates()` 的嚴格主動命令資格，不得讓 HOLD／MOVE／RETREAT 因殘留 target 開火。優先在原方法增加明確的近身參數或一個小資格函式，不建立新管理器、長期敵人名冊、每兵定時器或全圖敵人掃描。

規則邊界須明說：`needs_attack_order` 不是「剛醒」旗標，而是曾失去指揮、尚未收到新進攻令。它也會涵蓋原本和平 HOLD 全隊失能之後，以及其後手動 HOLD 的情況。此窄規則允許這些人接鄰敵時自衛；正常初始 HOLD（此旗標為 false）仍不自行開戰。MOVE／RETREAT／RETURN、玩家／受控士兵、非隊員不新增自動發起資格。兩格以上不追敵、不射箭。

完成起身且對方亦符合受擊資格時，應在下一次原交鋒查詢節拍內（0.1 秒，加一個 1/30 秒動作步容差）重新交鋒；有正當冷卻／硬直／占格阻擋時按原限制等待，不把它判成發呆。

### 3.3 呈現與文字

救助沿用原 4 秒素材。完成後施救者停止動作，傷員繼續 unconscious 等待剩餘遊戲時間；狀態或救助說明應寫明「縮短昏迷等待」，不能說「立即喚醒」。自然醒再播原 get_up。Army 成功起身時同步更新 Awake/Captive，避免站起仍標昏迷。普通兵 Sprite／MultiMesh、原隊長即時呈現與 Actor 皆須核對。

## 4. 依序實作

### A. 留下實作前證據

- 重新讀目前檔案與局部 dirty diff；本工作區已有大量未提交修改，另有 GPU 呈現工作進行中。
- 將預計修改檔案的基線複本或局部 diff／hash 留在 `output/site_knockout_recovery_20260926/`，只比較本次改動；不覆寫他人修改，不 reset、checkout 還原整檔，不 commit/push。
- 新增一個精簡 `scripts/tests/site_knockout_recovery_test.gd`，使用原 TerrainLab／Army／Actor，不做假戰鬥 owner。先重現真 KO→無指揮→自然醒→雙方 HOLD 不交鋒，保留這次預期失敗；再進正式修正。測試不可用直接設 attack=true 代替真命令／受擊路徑。

### B. 正式修正位置

- `scripts/terrain_lab/site_combat_rules.gd`：共用自然／救助後遊戲時間上限及必要舊版遷移常數。
- `scripts/terrain_lab/terrain_army.gd`：窄近身自衛資格、KO 遊戲時間消耗、原生准入限制、救助縮短等待及避免重複無效救助、保存上限／版本遷移、醒來 status。
- `scripts/terrain_lab/terrain_lab.gd`：傳遞原 game_seconds；僅 melee gate 使用新增自衛資格；救助 UI 說明。原 ranged gate 不放寬。
- `scripts/terrain_lab/terrain_test_character.gd`：KO 遊戲时间消耗、救助兩入口及完成效果、保存版本／上限／遷移、無 editor 循環姿態時間正規化；保留 Actor 明確命令行為。
- `scripts/terrain_lab/site_store.gd`：僅在原 owner restore/normalize 無法完整涵蓋時，補必要驗證／正規化接點，不新建保存系統。
- `SITE_COMBAT_DESIGN.md` D50/D72 及驗收段、`SITE_COMBAT_EXCHANGE_V1.md` 恢復／自衛段、`PROJECT_ARCHITECTURE.md` 最新補記：同步最終數值、owner、範圍與證據。

保存沿原身體 schema 的版本升級。新狀態可保存小時計的 KO，救助動作仍是 4 秒；舊合法快照按上節明確遷移。數字有限性、非負、上限、姿態／救助關聯、唯一施救者、原子拒絕等檢查不得放寬成任意大值。

### C. 測試與接受條件

新增整合檢查至少涵蓋下列核心斷言。使用小名冊與原 Site 時間換算推進至邊界，不需牆鐘空等四小時；日曆一致性須看真 Lab 接線，不能只手設 KO 後驗局部函数：

- Actor／Army 從真受擊開始的新 KO 都是 14400 遊戲秒；遊戲時鐘未滿四小時不醒，達上限才起身，完整 2.2 動作秒起身前不能行動。
- 雙方全體失能後，恢復者仍 HOLD／needs_attack_order／combat_attacking=false，但合法相鄰者在原節拍內發出真交鋒事件、改變 HP 或 stun。另驗一方仍有指揮／原 ATTACK 保留的個別 KO 回場。
- 救助施作 4 動作秒完成，但傷員仍昏迷且剩餘 KO=min(原值,3600)；再過剩餘遊戲時間才沿自然甦醒入口起身。包含 Actor→Actor、Actor→Army、Army→Army、Army→玩家；剩餘不足一小時不被救助延長、不反覆開啟無效救助。
- 正常初始 HOLD 不互打；既有待令 HOLD 的新自衛不續追擊，不改命令，不賦予遠射。弓弩有真彈藥且距離≥2時不發射、不耗彈；相鄰仍按原近戰。
- 同陣營、斜向、隔牆、距離≥2、未完成 get_up、死者、俘虜、受控人物、非隊員、忙碌、潰退／撤退不得走新增自衛資格。
- 原格被別人或預約占用不能起身；解除阻擋後可正常起身，無雙占位／身份替換。保留途中 KO 完成合法已提交步的既有規則。
- 暫停、不同 simulation_speed、和平／交戰切換、正常／慢幀分割：KO 消耗必須等於原 Site 遊戲時間增量，其他动作秒不變。不要靠單次巨大 delta 略過起身鎖後宣稱通過。
- 新長倒數／施救中途保存讀回續算；舊 17 秒 KO 明確轉為 8160 遊戲秒，新版 17 遊戲秒則保持 17；二次載入不重複放大。超上限／負數／非有限值、未知版本、錯誤救助關聯仍拒絕且不破壞現場。讀回仍保留待令與自衛邊界。
- 無 editor Actor 累積超過 60 動作秒的長昏迷仍可保存，姿態取樣時間保持合法，不靠擴大所有姿態上限。
- 原生快路開關、exchange snapshot 批次／回退結果一致；不以只走自訂子類回退的測試聲稱原生已驗。

相關原測試選擇性執行：`site_combat_rules_test`、`site_army_guard_rescue_test`、`site_player_soldier_test`、`site_combat_save_test`、`site_army_command_save_test`、`site_exchange_flow_test`、`site_exchange_actor_test`、`site_exchange_army_test`、`site_ranged_behavior_test`（以實際檔名確認）、`site_npc_combat_orders_test`、`site_army_recovery_test`、`combat_movement_contact_ko_occupancy_test`。先查哪些直接受新規則影響，必要者全部完成，不為擴大清單而反覆跑無關性能測試。

區分舊測試數字：直接注入運行時 ko=30 現在是合法短遊戲剩餘值，不能全域替換；舊無版本快照 ko=30 則按完整比例遷移。驗證新受擊必產生 30 秒、施救即醒、動作秒直接扣 KO 的預期需要改成新明確規格。`scripts/tests/fixtures/*.gd.txt` 是歷史對照，不能大批改寫來湊 PASS；舊 frozen prepare oracle 因時鐘刻意變更不再適用全部情境，保留檔案，新增同遊戲增量的 native/GD 對照，並記錄不再聲稱逐字未改。`site_combat_save_test` 如仍直接依賴已移除的預設 npc，沿現在正式 player／部署隊伍修 fixture，不重加正式 NPC。

### D. 正式畫面與交付

- 正式 TerrainLab 場景：截取昏迷中、施救完成仍昏迷、起身中、起身後相鄰交鋒；至少看普通兵與原隊長／Actor 的姿態。倒數可靠性靠整合測試，畫面靠真 renderer，兩種證據分開。
- 場景可預先用共同動作步及原日曆換算推進至接近邊界，必須明記，不能宣稱已牆鐘實測四小時。
- 保存 `result.json`、stdout/stderr、測試資料、截圖及 README 至本次 output 資料夾；每個失敗及修正原因一併保留。
- README 分「已實作」「已驗證」「仍有缺口」；列正式檔案、參數、原生／回退、保存與視覺邊界，不用 exit 0 代替所有驗收。

## 5. 執行約束

- 套用 ponytail：修共享根因、不建第二份人物／HP／座標／命令／保存 owner，不全面恢復舊攻擊令。
- Godot 驗證使用原封不動的 `C:/Users/Nekki/.codex/skills/godot-runtime-verify/scripts/verify_godot.ps1`；本機可用 `C:/Users/Nekki/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe`，執行前確認存在。
- 每次明確 `-TimeoutSeconds`（小型 headless 建議 120，正式場景／visual 可 180–240），只用原 helper 設環境與保留最近 100 筆完成紀錄；不得改 helper 或繞過保留規則。
- 原 AGENTS 授權失敗後針對修正自主重驗；保留失敗，不盲重試。視覺若觸發 DESKTOP_USER_REQUIRED，依標準工具批准機制處理。
- 無 schedule 工具時使用原生 session/status/wait 主動監看，不建 recurring automation。不同 Godot 驗證串行，避免其他 GPU 實驗互相干擾；這次不發布 FPS 結論、不重編原生 DLL、不更動美術資產。
- 若稽核發現另一個確定甦醒根因，先在原測試重現，再將修正限定在本次 owner；不把無法解釋的失败全部歸因環境。
