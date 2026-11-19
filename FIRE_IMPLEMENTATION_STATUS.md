# 火攻實作進度

更新：2026-10-06。**P4 已按具名功能範圍 close；P5 原 owner 保存／恢復／冷地點回放正在接續，完整 WG-FIRE-001 尚未完成。**

目前沒有執行中的 Godot 驗證；最近一次程序檢查沒有 Godot process。最新具名結案見 [P4_CLOSE_RECEIPT.json](output/fire_implementation_20261006/P4_CLOSE_RECEIPT.json)，完整交接狀態見 [LIVE_HANDOFF.json](output/fire_implementation_20261006/LIVE_HANDOFF.json)。一般額度最後檢查為 98% 已用，仍允許一般使用；不使用點數，達 100% 或一般使用不可用時停止並交接。

P1／P2／P3 具名門檻 PASS。P4 PASS_NAMED_FUNCTIONAL_SCOPE：41/41 回歸通過，現行 roof-under-rain 視覺 948 checks、M1 完整場景 2125 checks、Actor collapse／付費修復／多人工作／IGNITE 中斷／presentation 與 final editor gate 均有具名證據；目前共同來源結果與歷史失敗分列在 P4 收據。

P4 Army 邊界已明確收束：既有 GD Army 火場暴露與避火導航屬已接入 owner；Actor 倒塌 sink 已驗；不宣稱 Army 專屬墜落傷害封包，Native 留待 P6。這是範圍界線，不是缺少的 P4 測試。

P5 尚未准入保存：13 類原存檔／載入／交接入口、所有者原子恢復、共同 action/game 時間 journal、transport rebind 及 cold-Site replay/index 都須沿既有 owner 完成與驗證；在完整 roundtrip 前原 Save／Handoff guards 維持 BUSY。P6 Native 仍 GUARDED，凍結 DLL 未變。

本輪已完成 P5 的雙時鐘 shared-step 子片：RegionSaveSlot 在原始世界時鐘成功發布後記錄 ACTION／GAME 區間，固定地理 Site 儲存與載入會核對結算水印；clock journal、原 fire shared-step、ground/cold pending、shared-step fault、ship travel／clock／journey 與 editor scan 有具名 PASS。這只證明原時鐘子片，不代表 P5 保存恢復准入；完整證據與保留的失敗見 [P5_CLOCK_STEP_INTEGRATION.json](output/fire_implementation_20261006/P5_CLOCK_STEP_INTEGRATION.json)。

效能測試依使用者指示延至全部功能階段 close；既有 GPU reference FAIL 與所有歷史失敗保持原樣，raw process PASS 不當作效能接受。


## P0 已完成的歷史交付


更新：2026-10-06 00:12:21 +0800；主規格 WG-FIRE-001。

**P0 已完成，CONTRACT_READY；P1 尚未開始。** 24 個必要原基線 case 均已具名 PASS，最終 current／retained 來源閉包一致，船艦已實際交接來源與引擎。此結論只關閉 P0 契約與原基線缺口。

## 已實作與已驗證

- 正式 production 僅 1 個 Lab 既有 Controller 空值守衛的縮排修正；有 Controller 的原結構攻擊推進順序不變，沒有新增火攻時鐘、人物、物資、移動或保存 owner。
- 原測試 fixture／接受前提依目前 owner 修正，G1–G4 與 A／B／C 24 個 required case 均具名通過。完整命令、case 參數、RunID、timeout、失敗歷史與來源閉包見 [測試報告](FIRE_TEST_REPORT.md)、[coverage](output/fire_p0_close_20261005/P0_FINAL_COVERAGE.json) 及 [delivery receipt](output/fire_p0_close_20261005/P0_FINAL_DELIVERY_RECEIPT.json)。
- 最終變更共 10 檔，其中 9 個測試／fixture 檔；實際清單如下，沒有把最初 source8 當作固定最終數量。

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

Work 的全隊含受控者共享 count3／同 pool、控制身份、80→50、本人 cargo 與真實保存／載入保留；最終具名 PASS 為 `20261005_233730_872`，canonical 21.872 秒。原診斷 `233530_734` 的 18.943 秒是全部斷言完成的相對耗時，該診斷仍 FAIL；依量測只將 work leaf workflow 期限設為30秒，parent15秒／canonical60秒／outer90秒不改，不能解讀為性能接受。

Actor 原 flight 已為16欄，按當前 source／goal 與 eye height 1 核對，KO 邊界使用原常數；最終具名 PASS 為 `20261005_234008_150`，4.236 秒。Orders 及其他後續 fixture 的最小差異以以上動態清單為準，不從早期草案推定已實作。

## 八項契約狀態

1. 普通箭：實際接觸、一次散布、幾何 graze／kinetic／heat 與舊斷言遷移規則已定；原遠程基線已驗，新管線未實作。
2. 後端：GD Actor／Army、Native CPU、攻城責任與本人交易／handoff 已定；原後端交接／拒絕小案例已驗，新 fire 仍未准入。
3. 時間與休息：RegionSaveSlot 完成區間／journal／雙水印／permit、冷火場同步、共享池全員安全政策已定；原共同步與 work 基線已驗，TM-03／04 新接線未實作。
4. 半步：原承諾步／曲線／落格與完成 barrier 已具名驗證；新火場暴露與滅火工作槽尚未實作。
5. 保存：原入口與 P1–P4 BUSY 矩陣已定，計畫列明的原保存／交接基線已驗；新 fire schema／完整 P5 roundtrip 尚未開始。
6. 燃料：TIMBER／house／gate、Q1024／floor／同界順序／再生／付費修復已選；原資源／建築交易基線與独立算術分別已有證據，新 burn 交易仍未實作。
7. 功能：原服務用途與引用保全、P4 roof／軍營 parts／DEGRADED 依賴已定；新失能接線未實作，BL-11／12 留 P4／P5。
8. 倒塌：原 HP 零點／結構 batch／一次墜落基線已驗；新 generation／collapse 收據與 BL-10 留 P4。

三項人類政策及 profile 工程初值保持已定案，不重開決策。具體內容見 [八項契約](FIRE_BASELINE_AUDIT.md) 與原三份附錄。

## 保留歷史與未完成範圍

首次 P0 為7 run、3 PASS／4 FAIL，另有具名 borrowed replay；原 Army FAIL 與專用 P0 fixture PASS 並列保留。第一有限 loan 為12 run、7 PASS／5 FAIL。本次 closure ledger 累計 36 run、24 PASS／12 FAIL；24 是最後 required case 覆蓋數，不能拿它覆寫累計失敗。

條件式回歸 `housing`, `garrison`, `training`, `ship_repair_atomic`, `ship_water_facility_guard` 本次未觸發，未宣稱已跑。P0 算術仍標 `production_runtime_verified=false`；原 Store／handoff PASS 不代替新 fire 保存。

FIRE_ARROW 目前 Actor、Army、Native、攻城均未實作／未驗證，不標 SUPPORTED。P1 目標只先准入 GD Actor／Army；Native 新管線與新在途 handoff 仍 GUARDED，原攻城 NORMAL 保留原器具 cargo／flight／batch。

船艦 release 是來源／引擎交接。其具名 100 人量測保留航行 13.94 FPS、靠泊 16.39 FPS；原 `fps_threshold=null` 且不宣稱效能目標達標。本輪 P0 不擴成 SHIP、GPU、FPS 或發布驗收。原船艦失敗與限制仍由其收據保存。

下一階段是後續輪次 P1 共用箭矢、本人扣彈及基礎齊射；本次沒有開始 P1。P2–P6、M1、GPU／畫面、火攻效能與完整 v1.0 均未驗收。

## 發布前原始文件封存

- [FIRE_BASELINE_AUDIT.md 原始位元副本](output/fire_p0_close_20261005/doc_candidates/publication_20261005_161221_415113/original/FIRE_BASELINE_AUDIT.md)
- [FIRE_IMPLEMENTATION_STATUS.md 原始位元副本](output/fire_p0_close_20261005/doc_candidates/publication_20261005_161221_415113/original/FIRE_IMPLEMENTATION_STATUS.md)
- [FIRE_TEST_REPORT.md 原始位元副本](output/fire_p0_close_20261005/doc_candidates/publication_20261005_161221_415113/original/FIRE_TEST_REPORT.md)
- [FIRE_P0_GAP_CLOSURE_PLAN.md 原始位元副本](output/fire_p0_close_20261005/doc_candidates/publication_20261005_161221_415113/original/FIRE_P0_GAP_CLOSURE_PLAN.md)
