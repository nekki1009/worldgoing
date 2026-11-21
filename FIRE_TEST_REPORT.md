# 火攻實作進度

更新：2026-10-06。**P4 已按具名功能範圍 close；P5 原 owner 保存／恢復／冷地點回放正在接續，完整 WG-FIRE-001 尚未完成。**

目前沒有執行中的 Godot 驗證；最近一次程序檢查沒有 Godot process。最新具名結案見 [P4_CLOSE_RECEIPT.json](output/fire_implementation_20261006/P4_CLOSE_RECEIPT.json)，完整交接狀態見 [LIVE_HANDOFF.json](output/fire_implementation_20261006/LIVE_HANDOFF.json)。一般額度最後檢查為 98% 已用，仍允許一般使用；不使用點數，達 100% 或一般使用不可用時停止並交接。

P1／P2／P3 具名門檻 PASS。P4 PASS_NAMED_FUNCTIONAL_SCOPE：41/41 回歸通過，現行 roof-under-rain 視覺 948 checks、M1 完整場景 2125 checks、Actor collapse／付費修復／多人工作／IGNITE 中斷／presentation 與 final editor gate 均有具名證據；目前共同來源結果與歷史失敗分列在 P4 收據。

P4 Army 邊界已明確收束：既有 GD Army 火場暴露與避火導航屬已接入 owner；Actor 倒塌 sink 已驗；不宣稱 Army 專屬墜落傷害封包，Native 留待 P6。這是範圍界線，不是缺少的 P4 測試。

P5 尚未准入保存：13 類原存檔／載入／交接入口、所有者原子恢復、共同 action/game 時間 journal、transport rebind 及 cold-Site replay/index 都須沿既有 owner 完成與驗證；在完整 roundtrip 前原 Save／Handoff guards 維持 BUSY。P6 Native 仍 GUARDED，凍結 DLL 未變。

本輪已完成 P5 的雙時鐘 shared-step 子片：RegionSaveSlot 在原始世界時鐘成功發布後記錄 ACTION／GAME 區間，固定地理 Site 儲存與載入會核對結算水印；clock journal、原 fire shared-step、ground/cold pending、shared-step fault、ship travel／clock／journey 與 editor scan 有具名 PASS。這只證明原時鐘子片，不代表 P5 保存恢復准入；完整證據與保留的失敗見 [P5_CLOCK_STEP_INTEGRATION.json](output/fire_implementation_20261006/P5_CLOCK_STEP_INTEGRATION.json)。

效能測試依使用者指示延至全部功能階段 close；既有 GPU reference FAIL 與所有歷史失敗保持原樣，raw process PASS 不當作效能接受。


## P0 已完成的歷史測試報告


更新：2026-10-06 00:12:21 +0800；階段 P0。

**最終必要覆蓋：24／24 required case PASS，current／retained 來源閉包一致；P0 CONTRACT_READY，P1 未開始。** 這是具名原基線接受，沒有新增 fire 功能、GPU、FPS 或完整 v1.0 驗收。

## 本輪來源與執行方式

Godot `4.7.2.stable.mono.official.ed1daf0bf`；本案 headless／dummy renderer。船艦已實際交接 SOURCE／ART／BUILD／ENGINE，見 [接受收據](output/fire_p0_close_20261005/SHIP_HANDOFF_ACCEPTED.json)；ART／BUILD 輸入維持不變，未新增 Native build。

執行沿 `verify_ship.ps1` 包裝 unchanged canonical `godot-runtime-verify/scripts/verify_godot.ps1`，保留100份完成 run 的原 retention 與錯誤判定。每次只有一個 Godot；各 case timeout 見下列清單及完整命令。原始 result、stdout、stderr、combined、source_hashes 均保存於具名 output；known_noise 原樣保留，canonical PASS 不被擴寫成 stderr 完全為空。

[P0_FINAL_COVERAGE.json](output/fire_p0_close_20261005/P0_FINAL_COVERAGE.json) 綁定24個具名 case、完整命令／Native 參數、canonical result／stderr hashes 與 188 項合併來源輸入；[P0_FINAL_DELIVERY_RECEIPT.json](output/fire_p0_close_20261005/P0_FINAL_DELIVERY_RECEIPT.json) 記最終差異與 P1Started=false。發布前再逐項比對目前檔案和 retained snapshot，不能只讀 PASS 字串。

## 最終24個 required case

Native `crowd_handoff_actor_busy` 為原 Actor 一箭／BUSY／settle／返 Native 本人彈藥冷卻小案例；`crowd_transaction_restore` 與 `crowd_transaction_barrier` 分別計數。它們是原交接／拒絕回歸，不是 Native FIRE_ARROW 准入。

- **PASS** `site_combat_phase_test`；RunID `20261005_180413_141`；5.538 秒；canonical 60／outer 90 秒；158 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_180413_141/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_180413_141/source_hashes.json)。
- **PASS** `site_work_team_clock_test`；RunID `20261005_233730_872`；21.872 秒；canonical 60／outer 90 秒；159 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_233730_872/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_233730_872/source_hashes.json)。
- **PASS** `combat_movement_physical_cadence_test`；RunID `20261005_181007_608`；12.675 秒；canonical 60／outer 90 秒；159 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_181007_608/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_181007_608/source_hashes.json)。
- **PASS** `site_ranged_army_test`；RunID `20261005_181043_854`；13.687 秒；canonical 60／outer 90 秒；158 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_181043_854/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_181043_854/source_hashes.json)。
- **PASS** `site_building_surface_test`；RunID `20261005_181624_763`；21.211 秒；canonical 120／outer 150 秒；161 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_181624_763/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_181624_763/source_hashes.json)。
- **PASS** `site_shared_step_replay_test`；RunID `20261005_181733_801`；29.566 秒；canonical 120／outer 150 秒；158 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_181733_801/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_181733_801/source_hashes.json)。
- **PASS** `site_ranged_rules_test`；RunID `20261005_181700_305`；0.609 秒；canonical 60／outer 90 秒；158 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_181700_305/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_181700_305/source_hashes.json)。
- **PASS** `site_ranged_flow_test`；RunID `20261005_181715_591`；4.057 秒；canonical 60／outer 90 秒；158 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_181715_591/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_181715_591/source_hashes.json)。
- **PASS** `site_ranged_actor_test`；RunID `20261005_234008_150`；4.236 秒；canonical 20／outer 50 秒；158 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_234008_150/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_234008_150/source_hashes.json)。
- **PASS** `site_ranged_orders_test`；RunID `20261005_235128_253`；17.156 秒；canonical 60／outer 90 秒；158 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_235128_253/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_235128_253/source_hashes.json)。
- **PASS** `site_ranged_crafting_test`；RunID `20261005_235159_958`；4.639 秒；canonical 60／outer 90 秒；158 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_235159_958/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_235159_958/source_hashes.json)。
- **PASS** `site_combat_save_test`；RunID `20261005_234509_086`；7.836 秒；canonical 60／outer 90 秒；158 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_234509_086/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_234509_086/source_hashes.json)。
- **PASS** `site_resource_contract_test`；RunID `20261005_234540_463`；10.084 秒；canonical 60／outer 90 秒；158 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_234540_463/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_234540_463/source_hashes.json)。
- **PASS** `region_lab_contract_test`；RunID `20261005_235227_648`；39.428 秒；canonical 90／outer 120 秒；158 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_235227_648/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_235227_648/source_hashes.json)。
- **PASS** `site_building_runtime_contract_test`；RunID `20261005_235324_394`；32.564 秒；canonical 60／outer 90 秒；158 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_235324_394/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_235324_394/source_hashes.json)。
- **PASS** `site_building_economy_upgrade_test`；RunID `20261005_235413_008`；30.045 秒；canonical 90／outer 120 秒；158 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_235413_008/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_235413_008/source_hashes.json)。
- **PASS** `site_stockpile_transport_test`；RunID `20261005_235507_760`；29.951 秒；canonical 90／outer 120 秒；160 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_235507_760/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_235507_760/source_hashes.json)。
- **PASS** `site_siege_surface_batch_contract_test`；RunID `20261005_235553_737`；29.525 秒；canonical 120／outer 150 秒；160 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_235553_737/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_235553_737/source_hashes.json)。
- **PASS** `site_ship_clock_test`；RunID `20261005_235912_661`；17.117 秒；canonical 120／outer 150 秒；159 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_235912_661/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_235912_661/source_hashes.json)。
- **PASS** `site_ship_journey_edge_test`；RunID `20261005_235956_025`；55.251 秒；canonical 270／outer 300 秒；160 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_235956_025/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_235956_025/source_hashes.json)。
- **PASS** `site_ship_journey_test`；RunID `20261006_000105_869`；35.042 秒；canonical 270／outer 300 秒；159 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261006_000105_869/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261006_000105_869/source_hashes.json)。
- **PASS** `crowd_handoff_actor_busy`；RunID `20261005_235657_369`；31.819 秒；canonical 270／outer 300 秒；158 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_235657_369/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_235657_369/source_hashes.json)。
- **PASS** `crowd_transaction_restore`；RunID `20261005_235744_845`；26.263 秒；canonical 270／outer 300 秒；158 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_235744_845/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_235744_845/source_hashes.json)。
- **PASS** `crowd_transaction_barrier`；RunID `20261005_235830_278`；26.188 秒；canonical 270／outer 300 秒；158 inputs、current／retained exact。 [result](output/fire_p0_close_20261005/verification/20261005_235830_278/result.json)、[source hashes](output/fire_p0_close_20261005/verification/20261005_235830_278/source_hashes.json)。

## 完整失敗歷史與計数

首次 P0 的7筆 Godot結果維持 **3 PASS／4 FAIL**。四筆 FAIL 為原 Army `20261005_160026_508`、Phase `20261005_162007_950`、cadence `20261005_162304_721`、work `20261005_162441_310`；其首錯、timeout／exit、material-null、來源 hash 与全部 logs 保留在 `output/fire_p0_20261005/` 和發布前原報告封存。原 Phase Nil 只指 standalone 相容性，沒有擴稱正式主場崩潰。

專用 `fire_p0_site_ranged_army_test` 的 `20261005_162544_271` PASS 與原 Army FAIL 並列；借用 shared replay `20261005_161352_428` 仍標其原執行者及 epoch，不改稱本案重跑。它們不另湊成第25／26個 required case。原算術檢查為獨立 Python 模型，`production_runtime_verified=false`，不計入 Godot case 或 TM-03／04。

第一個18:00–18:20有限 loan 共 **12 run、7 PASS／5 FAIL**，原 [SOURCE_ENGINE_RETURN_RECEIPT.json](output/fire_p0_close_20261005/SOURCE_ENGINE_RETURN_RECEIPT.json) 不變。本次 closure ledger（含第一 loan）累計 **36 run、24 PASS／12 FAIL**；以下動態列出其全部非 PASS 紀錄。修正後 PASS 只新增結果，不回頭改判。

- **歷史 FAIL** `site_building_surface_test`／`20261005_180502_803`：SCRIPT ERROR: Assertion failed.；[result](output/fire_p0_close_20261005/verification/20261005_180502_803/result.json)。
- **歷史 FAIL** `site_building_surface_test`／`20261005_180720_533`：SCRIPT ERROR: Assertion failed: { "kind": "palisade", "cells": [3030], "entrance": 3130, "source": "", "stage": "building", "progress": 0.11666666666667, "solid": true, "cost": { "wood": 4 }, "work": 6.0, "clearing": [], "level": 0, "production": 0.0, "batch_paid": false, "status": "待施工", "layout_version": 1, "variant": "", "quarter": 0, "material": "wood", "owner_faction": 1, "parts": { "c:3030": { "hp": 100.0 } } }；[result](output/fire_p0_close_20261005/verification/20261005_180720_533/result.json)。
- **歷史 FAIL** `site_work_team_clock_test`／`20261005_180838_641`：SCRIPT ERROR: Cannot call method 'find_child' on a null value.；[result](output/fire_p0_close_20261005/verification/20261005_180838_641/result.json)。
- **歷史 FAIL** `site_building_surface_test`／`20261005_181307_449`：ERROR: Parameter "material" is null.；[result](output/fire_p0_close_20261005/verification/20261005_181307_449/result.json)。
- **歷史 FAIL** `site_work_team_clock_test`／`20261005_181421_125`：SCRIPT ERROR: Assertion failed: The controlled captain is personal; both original workers share the real team pool；[result](output/fire_p0_close_20261005/verification/20261005_181421_125/result.json)。
- **歷史 FAIL** `site_work_team_clock_test`／`20261005_233141_978`：ERROR: SITE WORKFLOW did not complete；[result](output/fire_p0_close_20261005/verification/20261005_233141_978/result.json)。
- **歷史 FAIL** `site_work_team_clock_test`／`20261005_233530_734`：ERROR: SITE WORKFLOW did not complete；[result](output/fire_p0_close_20261005/verification/20261005_233530_734/result.json)。
- **歷史 FAIL** `site_ranged_actor_test`／`20261005_233806_043`：原結果詳見收據；[result](output/fire_p0_close_20261005/verification/20261005_233806_043/result.json)。
- **歷史 FAIL** `site_ranged_orders_test`／`20261005_234026_013`：SCRIPT ERROR: Assertion failed.；[result](output/fire_p0_close_20261005/verification/20261005_234026_013/result.json)。
- **歷史 FAIL** `site_ranged_crafting_test`／`20261005_234319_233`：SCRIPT ERROR: Invalid call. Nonexistent function '_original_person_target' in base 'RefCounted (Fixture)'.；[result](output/fire_p0_close_20261005/verification/20261005_234319_233/result.json)。
- **歷史 FAIL** `region_lab_contract_test`／`20261005_234614_986`：SCRIPT ERROR: Assertion failed.；[result](output/fire_p0_close_20261005/verification/20261005_234614_986/result.json)。
- **歷史 FAIL** `site_ranged_crafting_test`／`20261005_234807_496`：SCRIPT ERROR: Invalid access to property or key 'vehicles' on a base object of type 'Nil'.；[result](output/fire_p0_close_20261005/verification/20261005_234807_496/result.json)。

首錯與追加 fixture 修正理由見 [追加基線診斷](output/fire_p0_close_20261005/ADDITIONAL_BASELINE_FIXTURE_DIAGNOSIS.md)；Work 期限的量測另見 [完整診斷](output/fire_p0_close_20261005/work_clock_deadline_diagnosis.md)。

## 具名修正的解釋

- Lab production 僅既有 Controller 空值守衛的一層縮排；原 Phase 明示 legacy，正式 Surface witness 則走原 Controller／30 Hz 共用步，兩條證據各自保留。
- Work 最終 PASS `20261005_233730_872` 的 canonical 耗時是 21.872 秒。診斷 `20261005_233530_734` 全部斷言於相對18.943秒完成，證明原15秒 workflow 不足；它仍是 FAIL。只在 leaf 設30秒，parent15秒、canonical60秒與 outer90秒保留；全隊含受控者 count3／同 pool、80→50、本人實物、原 UI 與保存斷言不減。這是有量測依據的測試預算調整，非遊戲性能接受。
- Cadence 保留原 female fixture、0.38秒、途中比例、獨立曲線與占格／完成 barrier 斷言；原共享 contact source 正常 release 後取得 canonical PASS。它不能反推每筆舊 material-null 的精確材質呼叫者。
- Actor 最終 `20261005_234008_150` PASS，4.236 秒；表示斷言改驗目前16欄 shot、原 source／goal／eye height 1 與原 KO 常數，本人 cargo／拒絕不變／reload 等原 owner 接受條件保留。
- 原 Army fixture 修正已回原測試；Orders／其他追加 fixture 的實際變更依最終 source_changes 記錄，不將早期候選 patch 或未跑版本寫成 PASS。

## 未跑／不在接受範圍

條件式原回歸 `housing`, `garrison`, `training`, `ship_repair_atomic`, `ship_water_facility_guard` 本次未觸發，理由：本次 production 僅 Lab 既有 Controller 空值守衛；其餘為原測試 leaf，未改服務、結構傷害、船修／水域 guard 或休息 consumer。

新 fire AR／FI／BL／WK／AT／SV／TM 案例仍未實作／NOT_RUN。原資源、建築、保存、surface batch 與 Native handoff 的 PASS 不替代新燃料、roof、collapse receipt、fire snapshot 或跨 Site 冷火場驗收。M1、P1–P6、GPU／D3D12畫面、火攻效能及發布尚未驗收。

船艦 release 是來源／引擎交接。其具名 100 人量測保留航行 13.94 FPS、靠泊 16.39 FPS；原 `fps_threshold=null` 且不宣稱效能目標達標。本輪 P0 不擴成 SHIP、GPU、FPS 或發布驗收。原船艦失敗與限制仍由其收據保存。

## 發布前原始文件封存

以下副本保留原 bytes；原先「仍凍結／NOT_RUN／CONTRACT_BLOCKED」是相應歷史時點的狀態，不當作本輪現況，也未被改寫成成功：

- [FIRE_BASELINE_AUDIT.md 原始位元副本](output/fire_p0_close_20261005/doc_candidates/publication_20261005_161221_415113/original/FIRE_BASELINE_AUDIT.md)
- [FIRE_IMPLEMENTATION_STATUS.md 原始位元副本](output/fire_p0_close_20261005/doc_candidates/publication_20261005_161221_415113/original/FIRE_IMPLEMENTATION_STATUS.md)
- [FIRE_TEST_REPORT.md 原始位元副本](output/fire_p0_close_20261005/doc_candidates/publication_20261005_161221_415113/original/FIRE_TEST_REPORT.md)
- [FIRE_P0_GAP_CLOSURE_PLAN.md 原始位元副本](output/fire_p0_close_20261005/doc_candidates/publication_20261005_161221_415113/original/FIRE_P0_GAP_CLOSURE_PLAN.md)
