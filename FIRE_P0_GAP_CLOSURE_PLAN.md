# 火攻 P0 缺口補齊計畫：執行結案

更新：2026-10-06 00:12:21 +0800。先前「先規劃補缺口」後，使用者授權「先把缺口補齊」；已按有限計畫完成 P0，**CONTRACT_READY，P1 未開始**。

原計畫與全部 G1–G4 接受條件／失敗分支已於發布前[逐位元封存](output/fire_p0_close_20261005/doc_candidates/publication_20261005_161221_415113/original/FIRE_P0_GAP_CLOSURE_PLAN.md)。本檔更新實際執行狀態，不把原計畫、候選 patch、原 FAIL 或舊 source epoch 改稱已通過。

## 完成的順序與結果

1. 船艦先提供18:00–18:20有限 SOURCE6／Engine loan，再收回；本案按時交還且留下 [return receipt](output/fire_p0_close_20261005/SOURCE_ENGINE_RETURN_RECEIPT.json)。其後拒絕新 loan 期間只做 output 準備，沒有把暫時 Godot0 當成授權。
2. 船艦完成後實際交接 SOURCE／ART／BUILD／ENGINE，本案核對 [handoff acceptance](output/fire_p0_close_20261005/SHIP_HANDOFF_ACCEPTED.json)，保持 ART／BUILD immutable，沒有新增 Native build。
3. G1–G4 原缺口逐一關閉；第一 loan 的7 PASS／5 FAIL、其後量測與 fixture 首錯全部保留。原 Phase 與正式 Controller shared-step witness 分別具名驗證，沒有用 legacy PASS 代替正式共同步。
4. A／B／C 的24個 required case 全部具名 PASS；其中可承接項逐筆核對 current／retained 完整閉包，不為湊數重跑。完整命令、timeout、RunID 與原始證據見 [coverage](output/fire_p0_close_20261005/P0_FINAL_COVERAGE.json)／[測試報告](FIRE_TEST_REPORT.md)。
5. 最終 source_changes 共 10 檔：1 個 production Lab 原空值守衛的一層縮排與 9 個原測試／fixture 檔；逐檔 hash 和實際差異由 [delivery receipt](output/fire_p0_close_20261005/P0_FINAL_DELIVERY_RECEIPT.json) 固定，不以最初 source8 草案代替。

## 有證據才採用的例行修正

- [scripts/terrain_lab/terrain_lab.gd](scripts/terrain_lab/terrain_lab.gd)：僅一層縮排，將原結構攻擊推進移入相鄰既有 Controller 非空守衛。
- [scripts/tests/site_combat_phase_test.gd](scripts/tests/site_combat_phase_test.gd)：原 standalone Lab／Actor／Army 明示原 legacy exchange 模式。
- [scripts/tests/site_building_surface_test.gd](scripts/tests/site_building_surface_test.gd)：核對原結構傷害公式；原和平前置付費建造與 Controller 30 Hz 正向共同步案例；完整資源收尾。
- [scripts/tests/site_work_team_clock_test.gd](scripts/tests/site_work_team_clock_test.gd)：明示原 NPC／正式工作按鈕；原隊長與兩工人同 count3 池，載入保留控制身份；量測後 leaf30秒，parent15／canonical60不變。
- [scripts/tests/combat_movement_physical_cadence_test.gd](scripts/tests/combat_movement_physical_cadence_test.gd)：成功／失敗都在完整原 female／曲線／占格案例結束後 deferred 收尾；比較數值不變。
- [scripts/tests/site_ranged_army_test.gd](scripts/tests/site_ranged_army_test.gd)：核對已準備的原 contact source identity／sample_calls，沿原 release 收尾。
- [scripts/tests/site_ranged_actor_test.gd](scripts/tests/site_ranged_actor_test.gd)：精確核對現行16欄 flight，含 source_eye／goal_eye；救援與倒地使用原 KO 常數。
- [scripts/tests/site_ranged_orders_test.gd](scripts/tests/site_ranged_orders_test.gd)：原供養士氣潰退准入、未崩潰命令拒絕保留舊目標、完整邊界退出／占格清空與不射箭；案末原 contact cleanup。
- [scripts/tests/site_ranged_crafting_test.gd](scripts/tests/site_ranged_crafting_test.gd)：明示原人物查詢與現行車船 guard 所需原 Controller，fixture 結束釋放；全部付料交易斷言保留。
- [scripts/tests/region_lab_contract_test.gd](scripts/tests/region_lab_contract_test.gd)：preserve_simulation 載入保留原 work／action／入口，直接續工，不手動覆寫載入 mode。

Work 實際越過原 UI／NPC 前置條件後，舊 count2／受控隊長私人池斷言與現行全隊含受控者共享契約不符，已改 count3／同 pool 並保留控制身份。完整保存／載入診斷在相對18.943秒才完成全部斷言，因此只將 leaf workflow 設30秒；parent15秒／canonical60秒不變，原診斷仍 FAIL。最終 work `20261005_233730_872` canonical PASS、21.872 秒。

Actor 最终 `20261005_234008_150` PASS、4.236 秒；目前16欄 shot／source／goal／eye height 1／原 KO 常數取代過期表示前提，未減少本人交易與 reload 接受條件。其他追加 leaf 依動態差異清單及具名結果，不以「尚待原測試」或「只是 fixture」掩蓋未通過的原 owner 契約。

## P0 gate 已滿足

- 實際共享來源與 Engine 交接已取得，最終來源／輸入與 retained copies 一致。
- G1／G2／G3 及原 G4 測試均 canonical PASS；原接受斷言與歷史 FAIL 留存。
- 24 required case 的最後證據已完整覆蓋，沒有以函式定位、stdout marker 或算術模型代替執行結果。
- 條件式未觸發項：`housing`, `garrison`, `training`, `ship_repair_atomic`, `ship_water_facility_guard`。理由：本次 production 僅 Lab 既有 Controller 空值守衛；其餘為原測試 leaf，未改服務、結構傷害、船修／水域 guard 或休息 consumer。
- 八項已選工程契約與三項人類政策保持不變；profile 數值不重開批准。
- 三份 FIRE 根報告與本計畫依新 coverage／delivery receipt 同步收束；寫入前原文件 bytes 另存，原 P0／loan 收據不覆寫。

首次 P0 的7 run／3 PASS／4 FAIL、borrowed replay 與專用 Army fixture 保留；第一 loan 的12 run／7 PASS／5 FAIL亦保留。本次 closure ledger 累計 36 run／24 PASS／12 FAIL。24是最終必要 case 覆蓋，不是把失敗刪掉後聲稱只跑24次。

## 後續階段保持原界線

P1新箭／準備／ember／新BUSY；P2 burn／harvest同界、fuel餘數／再生與局部安全休息；P3暴露／滅火及作業互斥；P4多區roof／DEGRADED／collapse receipt；P5 fire schema／冷火場／半步保存；P6 Native／GPU／效能仍未實作或驗收。若後續實際修改某 consumer，其必要原回歸隨修改驗證，不以階段名稱推遲。

船艦 release 是來源／引擎交接。其具名 100 人量測保留航行 13.94 FPS、靠泊 16.39 FPS；原 `fps_threshold=null` 且不宣稱效能目標達標。本輪 P0 不擴成 SHIP、GPU、FPS 或發布驗收。原船艦失敗與限制仍由其收據保存。

**本次停在 P0 CONTRACT_READY。後續輪次的單一目標才是 P1 共用箭矢、本人扣彈與基礎齊射；本次沒有開始 P1。**

## 發布前原始文件封存

- [FIRE_BASELINE_AUDIT.md 原始位元副本](output/fire_p0_close_20261005/doc_candidates/publication_20261005_161221_415113/original/FIRE_BASELINE_AUDIT.md)
- [FIRE_IMPLEMENTATION_STATUS.md 原始位元副本](output/fire_p0_close_20261005/doc_candidates/publication_20261005_161221_415113/original/FIRE_IMPLEMENTATION_STATUS.md)
- [FIRE_TEST_REPORT.md 原始位元副本](output/fire_p0_close_20261005/doc_candidates/publication_20261005_161221_415113/original/FIRE_TEST_REPORT.md)
- [FIRE_P0_GAP_CLOSURE_PLAN.md 原始位元副本](output/fire_p0_close_20261005/doc_candidates/publication_20261005_161221_415113/original/FIRE_P0_GAP_CLOSURE_PLAN.md)
