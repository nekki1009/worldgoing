# Worldgoing 火攻系統｜Codex 開工指令 v1.0（2026-10-05 第二次審核修訂）

建立日期：2026-10-04；修訂日期：2026-10-05 第二次審核修訂（Asia/Taipei）  
主規格：`Worldgoing_火攻火箭與建築燃燒_實作規格_v1.0.md`（WG-FIRE-001，同日第二次審核修訂）

本檔是執行入口，不取代主規格或現行架構。兩個 Markdown 檔須一併閱讀。**第一次只完成 P0；契約及必要證據達到 CONTRACT_READY 後，後續輪次才執行 P1。** 本次文件修訂不代表已開工、已批准未決普通箭平衡／跨 Site 時間／安全區休息政策，或已通過任何執行驗收。

---

## 可直接交付的指令

你正在處理《Worldgoing》火攻系統。先讀 repository 的 `AGENTS.md`、`PROJECT_ARCHITECTURE.md`，再完整閱讀主規格與目前工作進度，核對實際程式。沿用原人物、物品、建築、移動、戰鬥與保存 owner，不因建議類別名稱不同另建一套權威。

### 本輪範圍

若尚未完成 P0，本輪只執行 **P0：Repository 基線與整合契約**，交付基線查核、具體責任／規則決策、測試證據與狀態。不要在同輪自動開始 P1。P0 不是泛泛重寫計畫；須完成下列八項契約的實際 symbol、既有資料流、最小改動方案及前置驗證。

若已有進度，先讀 `FIRE_IMPLEMENTATION_STATUS.md` 及實際程式／測試，確認前置階段證據。只有 P0 為 `CONTRACT_READY` 才可於後續輪次開始 **P1：共用箭矢、本人彈藥交易與基礎齊射**；其後每輪只完成下一個階段及必要小修。進度檔寫完成不等於證據完成。

核心玩法或權威尚未定案時列 `CONTRACT_BLOCKED`，指出缺少哪項決策／介面／基線，不用「最小 adapter」掩蓋規則變更。有已確認的使用者決策就引用，不重複要求確認；只有實際未決、會改變正式玩法的選擇才需取得決策。

### P0 必須查核及交付

核對 engine 實際執行版本、`project.godot`、renderer、Site 尺度／surface、現有測試與 benchmark。目標仍為專案指定 Godot 4.7.2；有差異只記錄，不升降級。建立 `FIRE_BASELINE_AUDIT.md`，不得把規格建議的類別、100 人／64 Near 目標或 GPU 推測當成已驗證現況。

必須逐項完成：

1. **普通箭規則遷移。** 現有正式弓弩採落點格射線＋`SiteCombatRules.ranged_result`；曲線 sweep 與實體盾牌攔截是遷移目標。列明普通弓、弩、火箭的能力／疲勞／距離／移動／盾牌／護甲／擦傷因素、散布與接觸後傷害、kinetic 與 heat 的唯一關係；不要同時重算未定義的散布 miss 與原擲骰，也不要靜默刪掉原規則。列要保留與明示取代的舊測試斷言及決策依據。
2. **後端准入。** 分別查 GD Actor、GD Army、Native Crowd 及攻城投射物的發射、本人扣彈、飛行、命中、傷害 owner，列 SUPPORTED／GUARDED／BLOCKED 計畫。Native CPU 戰鬥不是 GPU 畫面；GD FireLab 不能代表 Crowd 已整合。列 NORMAL／FIRE_ARROW 的實物、native 投影／回寫及模式切換契約。
3. **時間單位與跨 Site 政策。** 依主規格第 6.1 節，飛行／ember／火勢／暴露／工作／lease／倒塌使用共同動作秒，天氣與原經濟仍使用 Site 遊戲秒。查原 60 倍和平換算、simulation_speed、火場危害續期入口；續期在算遊戲秒之前，且不反覆清除 manual.target／progress。沿原 `RegionSaveSlot.record_completed_active_step` 世界發布與 `TerrainLab.replay_site_to` 定義共同 action／game 區間來源、補算映射及交接；不能以活動和平 Site 的 60 遊戲秒讓冷火場自行反算成 60 動作秒，就宣稱與現場 1 動作秒一致。交 TM-03 雙 Site 數值契約，不另建時鐘或預設全世界減速。另列全部 combat_left consumer，明定安全區隊伍 80→50 輪休及 Actor／Army／Native 行為，包含保存、作業、訓練與旅行影響；不能只保住 manual 進度。
4. **移動完成與半步。** 保留 Prepare → Propose → Resolve → Commit → Finalize；現行承諾步由 `complete_committed_moves` → `finish_committed_move` 實際落格及 pop。定義原半步 motion／暴露，不把 Finalize 新接受視為完成，也不把無新提案者一律當靜止。
5. **過渡保存與交接。** 查原自存、手存、載入替換、清場、Site 切換及 GD↔Native handoff。P1 新箭及預約、P2 起新火場與未保存損壞均須納入原 BUSY 守衛；拒絕保留存檔與現場。P5 沿原 `RegionSaveSlot`／`TerrainLab.advance_cold_site`／`replay_site_to` 補完整保存／接管，不另建世界 owner。
6. **燃料與原物交易。** 火源對應原資源 key／feature.parts。定義 remaining↔fuel 映射及取整、同邊界燃燒／採集順序、清地／再生、付費修復與再次引燃；不讓燒完仍採原滿額，也不讓修好的木門永久無燃料。
7. **建築功能與服務。** 列各准入 feature 的功能依賴，接到原 feature_usable、加工／供水、倉庫、住宅、駐軍及訓練適用入口，使實際服務與 DESTROY_FUNCTION 判定一致。明定失能後停產、禁止新進料、合法取貨、已付批次及人員登記的暫停／解除／恢復；保留原物與必要引用，不藉刪 feature 或改 stage 停用服務，失效返家／返營格須同步處理原引用與命令。P4 驗 BL-11 現場閉環，P5 驗 BL-12 存讀。
8. **倒塌預警與原 HP 零點。** 預警為最晚倒塌時間，保留 parts.hp<=0 立即失去支撐規則；致死火傷或攻城可提前在原結構邊界倒塌。到期時提交當前有效部件剩餘 HP 的致死傷害，沿原 siege_apply_damage_batch／damage_structure_part／resolve_structure_change 一次處理表面、承諾步與墜落。舊事件不得重複結算或影響新 generation；同一實體繼續受傷不無故取消倒數，不另存支撐 HP。P4 驗 BL-10 牆上人物／半步撤離。

八項均有可執行方案、無未決核心衝突，且依賴的基線驗證完成，才標 `CONTRACT_READY`。跨 Site 共同時間與安全區休息政策在本次修訂後仍待定案，不能延至 P5 才選擇；未定案時標 `CONTRACT_BLOCKED`。P0 完成數值／責任契約，不提前宣稱 P2～P5 新功能案例已執行。缺少環境或有影響後續的未解基線時標 `CONTRACT_BLOCKED` 並列 `NOT_RUN`／失敗證據；無關既有失敗另列，不偽造 PASS，也不把它們一律當新回歸。

### P1 工作單（僅後續已符合前置條件的輪次）

依 P0 決策擴充已有箭矢 owner：普通箭／火箭模式、原子 release 與本人彈藥消耗、命令中止、集中 projectile 資料、固定動作步弧線／sweep、第一命中、接觸後傷害去重、有限 ember、基礎齊射窗口與公平容量排程。新 pool 不得繞過原飛行／保存／handoff 守衛。

P1 至少完成 GD Actor／Army FireLab 與未准入後端守衛。尚未接完整火勢時，以 event recorder 驗 ignition payload；不得直接令指定建築起火，也不宣稱 Native Crowd 已完成。火箭消耗原持有人對應 item，不從隊伍公共彈匣取用，不免費將普通箭轉成火箭。

至少執行 AR-01～08、AR-12、AR-15～18 的本階段部分、AR-09 kinetic 去重、TM-01 flight／ember、SV-09 投射物／交接守衛及 P0 列明的普通弓弩回歸。包含薄牆、移動目標、友軍／盾牌、準備中改令、容量耗盡與 **100 人隊伍的本人 cargo 合計只有 3 支合法箭**；三支箭的持有人均可射時恰好 release／扣彈 3 次，跨隊容量公平性另由 AR-08 驗證。

### 全程硬性限制

1. 本案百人隊、目標近萬人與 64 Near 為待 P0 核對的設計／准入條件；保留現有隊長／幹部／士兵及呈現分層，不為火攻縮減合法名冊、放寬人數或增加 Near 節點。
2. 保留原單一移動 authority、預約及完成屏障；不直接改 cell、傳送、穿人或提前 pop。保留靜態步進方向、Aging calls／expansions 各 50% 保證及已驗證交換規則。
3. 火災 hazard 與靜態地形分開；真正原資源實體（如樹木）／部件／殘骸改變阻擋才沿原資源或結構變更入口提交。容量不足仍走原部分部署，不直接拒絕 MOVE。
4. 已射箭不追蹤、不在發射時扣目標血、不穿牆點火；第一命中及未命中落點依唯一管線處理。每箭只扣一次本人彈藥與一次 kinetic，contact 有限且不重新充值。
5. GD／Native 不可各扣一次彈藥或 HP；逐階段完成准入功能驗證，P6 才作萬人最終效能與全回歸，不能延後處理權威衝突。
6. 畫面、粒子、動畫、LOD、FPS 不控制命中、火傷、燃料或射速；不用 Node-per-arrow、light-per-arrow、全員×全火源、每幀全量 GPU readback 或阻塞全域 sync。
7. P1～P4 原保存／替換／換場守衛須涵蓋所有未收束或尚未完整持久化的新狀態；P5 通過後才解除已支援部分，不能以暫時禁卸載宣稱持久化完成。
8. 不另造人物、建築 HP、燃料對應之外的可採資源帳本或世界 owner；不新增完整製造鏈、爆炸、流體煙氣、木板剛體、水源物流或舊封閉世界規則。
9. 不覆蓋無關檔案與未提交變更，不執行無關引擎／套件升級或全面重構，依 AGENTS.md 處理版本控制。

### 工作結束交付

更新 `FIRE_IMPLEMENTATION_STATUS.md` 與 `FIRE_TEST_REPORT.md`，首次另交 `FIRE_BASELINE_AUDIT.md`。列實際 engine／build／config、檔案與 symbol、逐後端准入、P0 契約狀態、測試指令與 PASS／FAIL／NOT_RUN、baseline failure、新回歸、未決事項與下一個單一目標。

沒有跑過 Godot、沒有 GPU 環境、只有 reference backend 或靜態查核必須直說；不把文件修訂或 P0 查核稱為功能實作，不用理論萬人代替實測，不將 M1 稱為完整 v1.0。

```text
本次階段／P0 契約狀態：
實際完成：
修改檔案／主要 symbol：
各後端准入／過渡守衛：
測試指令與結果（PASS／FAIL／NOT_RUN）：
效能與正確性觀察：
未完成／阻塞／待決：
下一個單一目標：
```

---

## 後續工作階段

| 階段 | 單一交付目標 |
|---|---|
| P0 | 首次只做基線及八項契約，包含跨 Site 時間與休息政策，交 CONTRACT_READY 或具體 CONTRACT_BLOCKED |
| P1 | 依已定案規則擴充普通箭／火箭、本人彈藥、齊射及逐後端／新狀態守衛 |
| P2 | 引燃、稀疏火勢、原資源／單區建築／木門、燃料生命週期、TM-04 現場休息政策與過渡保存保護 |
| P3 | 避火、半步暴露、單槽基本滅火與 M1、TM-04 滅火／輪休；不含 P4 自動停射／接近放火 |
| P4 | 多分區、煙／風雨、正式作業、停射政策與在途估算；BL-10 原倒塌交易、BL-11 實際服務失能／恢復 |
| P5 | 原保存／冷補算上的雙時間、在途與 Site 交接；TM-03 跨 Site 一致性、BL-12 失能服務及原引用存讀 |
| P6 | 完成萬人 production 准入、LOD、效能與全回歸；不替代各階段正確性驗證 |

M1 操作只含主規格第 17.1 節列出的 P3 功能；P3 先驗 WK-03～06 單槽 SUPPRESS 子集，P4 再驗完整工作矩陣。完整細節、數值與驗收以同日修訂的 WG-FIRE-001 為準。本檔不代表任何階段已實作或測試。
