# 任務 CC-20261009-TBD（草案，待指揮中心編號）

任務 ID：CC-20261009-TBD（科技樹 Core 整包 154 次串行驗證）

模式：VERIFY

> 草案說明：由科技樹討論串（Claude）起草，經協調者轉交指揮中心審核、編號後派給 Codex。**目前不可執行**，必須先滿足下方「開跑前置」。本單只負責驗證，不寫程式；程式接入 D 由科技樹討論串另外施工。

## 目標

在 Core 整包接入完成的目標專案上，依序執行原定的 154 次串行驗證（142 個不同測試，加 12 次刻意重跑），取得每一次的嚴格 PASS 證據與收據。用來判定科技樹 v2.4 的 Core 整包，含 P1 的 F07 首包 A01–A20 對應測試，是否通過整合驗收。

C06 的 5 個獨立 profile 不算在 154 次內，見附錄 B；是否併入本單由指揮中心決定。

## 可改檔案

僅本單證據與回報。不得修改任何 `.gd`、測試、Catalog、manifest、wrapper、canonical `verify_godot.ps1`，也不得修改 DLL 或 C++ 來源。

## 開跑前置（全部成立才可轉 RUNNING）

1. **目標專案已綁定。** 描述檔 `future_actual_binding` 原本全是 `PENDING_*`。執行前必須寫定：
   - 目標專案根目錄：隔離 C 或接入後的 D，由指揮中心擇一；
   - manifest 的路徑與 SHA256；
   - audit 的路徑與 SHA256；
   - source epoch 的檔案數；
   - 每批前後的 epoch 釘選；
   - readonly preflight 的路徑與 SHA256；
   - strict inspector 的綁定。
2. **測試檔一致。** 每列的 `actual_copied_fixture_sha256` 都必須回讀成實際雜湊，而且等於附錄 A 的來源雜湊。任一列不同就整單不開跑，回報差異。
3. **沒有其他施工。** 生態討論串的 32 項驗證已結束；本單 RUNNING 期間，沒有任何代理修改目標專案。
4. **Godot 時段。** 指揮中心已核發唯一 Godot 時段；機器上原有的 Godot 程序數為 0，也沒有共享 slot 或鎖。
5. **Native 準備（第 150–154 次）。** 切換 cohort 前先關閉 Godot。
   - 指定 DLL：`9E213E432467DEC49CC05A45A620F575A3EEAB0CCD7C961C345DF8A4FC2108E5`。
   - build_id：`7680d7664946c582ea7b97401f39ab4c181c136377714853eb073485cb0b7e92`。
   - 記錄切換前的 DLL 雜湊、複製的 DLL 與 CPP manifest 雜湊、當下 GD source epoch。
   - 不得用正式 D 的 DLL 跑這 5 次正向案例。

## 執行規則

- **順序固定。** serial 1 → 154，不重排、不跳過、不平行。
- **分三段，段與段之間要交接：**
  - 第 1–22 次：catalog `disabled`。
  - 第 22→23 次之間：先停止並釋放 Godot，由 Region 唯一發布 `enabled_isolated` 的 Catalog 與配對測試，再重新取得時段。執行端不得自動改 flag。
  - 第 23–149 次：catalog `enabled_isolated`。
  - 第 149→150 次之間：Catalog 不變，只切換 Native cohort；依前置第 5 點換 DLL，然後啟動全新的程序。
  - 第 150–154 次：Native cohort。
- **呼叫方式。** 沿用原 wrapper（附錄 A 的 wrapper 欄：v3／v4／v5），參數用 `-ProjectRoot <目標> -Script <res://…> -TimeoutSeconds <該列 timeout>`。wrapper 內部轉呼 canonical `C:\Users\Nekki\.codex\skills\godot-runtime-verify\scripts\verify_godot.ps1`。canonical helper 不得修改，也不得移除 `Clear-CompletedVerificationHistory`。
- **畫面需求。** visual 共 145 次，需要可見視窗與 GPU；headless 共 9 次。
- **時間。** timeout 合計 28830 秒，約 8.0 小時，這是上限。
- **遇到真正失敗就停。** 立刻停下來診斷並回報，不自動重試未修改的失敗，也不跳到下一列。

## 驗收條件（每一次都要全部成立才算 PASS）

1. canonical 結果為 PASS，且 exit code 為 0。
2. stdout 出現該列的 strict marker（附錄 A 的 marker 欄），而且完全相符。
3. 實際耗時沒有超過該列 timeout；有內部期限的列（第 139–149 次、第 150–154 次）也沒有超過內部期限。**超時一律判失敗，即使有印出 PASS。**
4. 所有 warning、error、orphan 都逐條評估，沒有過濾；`ERROR_whitelist` 為空。
5. 測試檔、owner 與相依來源的雜湊，和開跑前置第 2 點的釘選完全一致；每批前後的 source audit 一致。
6. 缺少外部相依直接判失敗，不能當成 skip，也不能升級為 PASS。
7. 禁止：修改 assertion 或期望值、跳過或隔離測試、延長 timeout、放寬 marker、用舊結果冒充新結果。

整單 PASS 的條件：154 次全部 PASS，而且三段交接都有收據。部分通過時逐列列出，不換算成百分比完成度。

本單**不含**：C06 的 5 個 profile（除非指揮中心併入）、正式 D 的語意合併回歸、效能與發布驗收、Audio V27、D10 G01–G08 與 TECH-AI-01／02 的專項實測、Ecology 第 8–31 項。

## 來源

- 執行描述檔：`C:\Users\Nekki\.codex\visualizations\2026\10\02\01a0fcb4-b140-7861-8f45-82f28a42bccd\tech-implementation\full40-future-execution-descriptors\20261008_identity_pending_v1\ORIGINAL_154_FUTURE_EXECUTION_DESCRIPTORS.v2.json`（SHA256 `8599302172E76B8C80C93C024B3D9FFAC91250B40C9D01286DBECD26B8EB3DDA`；schema `ORIGINAL_154_FUTURE_EXECUTION_DESCRIPTORS_PENDING_V2`；status `SOURCE_ONLY_PENDING_DESCRIPTORS_NOT_EXECUTABLE_NOT_RUN_NOT_ACCEPTED`）。
- 描述檔的輸入：
  - `C:\Users\Nekki\.codex\visualizations\2026\09\26\01a0def5-6320-7ba0-84af-45301ed38863\region_core_native6_contact_final_source_v1\FINAL_174_FIXTURE_154_PROFILE_GUARDS.v1.json`（SHA256 `EE84D08FF940BA59BD0BF35CA9FC77D41D1F180C408D559CE6364F61EEF33D7D`）
  - `C:\Users\Nekki\.codex\visualizations\2026\10\02\01a0fcb4-b140-7861-8f45-82f28a42bccd\tech-implementation\full40-v6-correction-v2\FS_FULL40_CONSOLIDATED_RUN_PACKAGE.v6.2.json`（SHA256 `8A9AE6EC05222BD782D765B04C7AE2E543CBC3783B258B8EA35CB3F838CCB6A2`）
  - `C:\Users\Nekki\.codex\visualizations\2026\10\02\01a0fcb4-b140-7861-8f45-82f28a42bccd\tech-implementation\full40-v6-correction-v2\FS_FULL40_SERIAL_RUN_MAPPING.v6.2.json`（SHA256 `8C75E62ACD5FD70BD07353AA38D4D9EBDBE8BF10D9996A4CE78CCC495D16FE8D`）
- 歷史 Core 來源 manifest：`C:\Users\Nekki\.codex\visualizations\2026\09\26\01a0def5-6320-7ba0-84af-45301ed38863\region_core_native6_contact_final_source_v1\manifest.method_local_final.v1.json`（SHA256 `6671441A5DA5E9014EDFF8E73840002431B4D8A9F75E4CC73F9B59D2A848CF46`）。
- Native 編譯收據：`C:\Users\Nekki\.codex\visualizations\2026\10\02\01a0fcb4-b140-7861-8f45-82f28a42bccd\tech-implementation\stage\output\tech_tree_implementation_20261007\NATIVE_TIME_AUDIO_UNION_COMPILE_RECEIPT.v1.json`（SHA256 `8B61C8FFFA34A22F831D11421C7BC583F3CC4CE819992CB97F9A37E195D5D8C8`）。
- 計畫：`C:\Users\Nekki\.codex\visualizations\2026\10\02\01a0fcb4-b140-7861-8f45-82f28a42bccd\tech-tree-v2-draft.v2.4-stage.md`，以及 `D:\worldgoing\reports\tech-tree-remaining-work-20261008.md` 第 3 節。
- 2026-10-08 唯讀核對：154 列，serial 連續；142 個不同 ID，12 次重跑；308 個來源釘選全部和現檔一致。

## 與其他施工的關係

- **生態永續計畫審核討論串：** 正在 D 跑 32 項驗證，也改了 D 的 site_environment／site_runtime／site_store／terrain_lab／site_offices／site_settlement／site_controller／site_resource_view／site_work_team／region_save_slot 等檔案。本單必須等它結束才能開跑。
- **科技樹討論串（Claude）：** 負責把 Core 整包接入 D 的程式改動。接入完成並凍結之前，本單不開跑；本單 RUNNING 期間，科技樹討論串不改目標專案。
- **Region 討論串：** 負責唯一發布第 22→23 次的 Catalog stage，以及隔離 C 的 manifest 與 audit。
- **共用資源：** 唯一的 Godot 時段、GPU、`.godot-temp/godot_verify`（保留最新 100 次）、隔離 C 的資料夾。

## 回報

- 主收據寫入 `D:\worldgoing\output\project_command_center\receipts\CC-20261009-TBD.json`，內容包含：
  - 目標專案，以及 manifest、audit、preflight、inspector 的雜湊；
  - 每列的 serial、id、script、mode、timeout、實際耗時、exit code、canonical 結果、marker 是否命中、是否超時；
  - 每列的 stdout、stderr、result 的 SHA256；
  - 每列前後的 source epoch 雜湊；
  - 三段交接的紀錄；
  - 失敗列的診斷摘要。
- 每次跑完立刻把該次完整的五個檔案歸檔，放到 `D:\worldgoing\output\project_command_center\evidence\CC-20261009-TBD\<serial 三位數>_<id>_<catalog_stage>_<cohort>\`。原記錄不覆寫，因為 canonical 只保留最新 100 次。
- 回報給指揮中心與科技樹討論串：通過幾次、失敗幾次（逐列列出）、哪些超時、下一步。

## 附錄 A：154 次串行清單（依執行順序）

標「重跑#n」的列，是同一測試第 n 次刻意重跑。共 12 個測試有重跑，合計 12 次。wrapper 欄 v3 表示 `verify_isolated_region_v3.ps1`（SHA256 `0E022657DD7CC975AF386A121F93DE7967C528C8664A4DF94E723CD7508CD99C`），v4 表示 `verify_isolated_region_v4.ps1`（SHA256 `A8AC907D82A6837E2B5B89C2F27DEAD780A826359B29477EFAE932498CBAA9F8`），v5 表示 `verify_isolated_region_v5.ps1`（SHA256 `B9E42C753551182724F6A98D17347C995A08DD903A67ACC4BF22872898337ABF`）。來源雜湊欄只列前 16 碼，完整 SHA256 以描述檔 `rows[].original_profile_source_binding.sha256` 為準。

| # | 測試（scripts/tests/） | 模式 | timeout 秒 | catalog | wrapper | strict marker | 來源 SHA256 | 備註 |
|---|---|---|---|---|---|---|---|---|
| 1 | `site_f07_joint_work_test.gd` | headless | 120 | disabled | v3 | `F07_JOINT_WORK_MATH PASS` | `6E5D88D2AEACD826…` |  |
| 2 | `site_f11_joinery_disabled_test.gd` | visual | 120 | disabled | v4 | `SITE_F11_JOINERY_DISABLED_SOURCE_FIXTURE:` | `BD093318D73808EB…` |  |
| 3 | `site_fatigue_master_groups_test.gd` | headless | 120 | disabled | v3 | `SITE_FATIGUE_MASTER_GROUPS_PASS` | `2967DA166C4CB05D…` |  |
| 4 | `site_settlement_engineering_test.gd` | visual | 120 | disabled | v4 | `S09_S10_DISABLED_BOUNDARY_PASS` | `1656956CC137EC01…` |  |
| 5 | `site_settlement_irrigation_test.gd` | visual | 120 | disabled | v4 | `S02_DISABLED_BYTE_BOUNDARY_PASS` | `BF6F0641072FA012…` |  |
| 6 | `site_settlement_metal_chain_test.gd` | visual | 120 | disabled | v4 | `S04_DISABLED_BYTE_BOUNDARY_PASS` | `4FEC44573697FEE3…` |  |
| 7 | `site_settlement_spares_test.gd` | visual | 120 | disabled | v4 | `S08_DISABLED_BOUNDARY_PASS` | `53F6974A5B3B8587…` |  |
| 8 | `site_technology_catalog_test.gd` | headless | 120 | disabled | v3 | `SITE_TECHNOLOGY_CATALOG_PASS` | `215A591A2809F5DB…` |  |
| 9 | `site_technology_fire_pot_disabled_test.gd` | visual | 120 | disabled | v4 | `SITE_TECHNOLOGY_FIRE_POT_DISABLED_PASS` | `2423072C8BA8F383…` |  |
| 10 | `site_technology_policy_test.gd` | headless | 120 | disabled | v3 | `SITE_TECHNOLOGY_POLICY_HELPER_PASS` | `CAA7FBEDA085DEED…` |  |
| 11 | `site_technology_s01_water_owner_test.gd` | visual | 210 | disabled | v4 | `SITE_TECHNOLOGY_S01_WATER_OWNER_PASS` | `BC3AA031CB4890B9…` |  |
| 12 | `site_technology_scope_test.gd` | headless | 120 | disabled | v3 | `SITE_TECHNOLOGY_SCOPE_PASS` | `29F44191997B1D19…` |  |
| 13 | `site_technology_window_scope_test.gd` | visual | 120 | disabled | v4 | `SITE_TECHNOLOGY_WINDOW_SCOPE_PASS` | `A20CE164A4404890…` |  |
| 14 | `site_t5_supervised_public_ui_test.gd` | visual | 180 | disabled | v4 | `SITE_T5_SUPERVISED_PUBLIC_UI_PASS` | `FB5D1BE401DC5AFD…` |  |
| 15 | `site_t6_analysis_public_ui_test.gd` | visual | 180 | disabled | v4 | `SITE_T6_ANALYSIS_PUBLIC_UI_DISABLED_PASS` | `9526EE12A384F171…` |  |
| 16 | `site_g06_source_rule_ui_test.gd` | visual | 90 | disabled | v4 | `SITE_G06_SOURCE_RULE_UI_PASS` | `441796EC06D82CF5…` |  |
| 17 | `site_s07_first_earned_workshop_test.gd` | visual | 240 | disabled | v4 | `S07_ORIGINAL_SETTLEMENT_FIRST_EARNED_DISABLED_PASS` | `2BA71D32BBE77C32…` |  |
| 18 | `site_s08_first_earned_spares_test.gd` | visual | 240 | disabled | v4 | `S08_ORIGINAL_SETTLEMENT_FIRST_EARNED_DISABLED_PASS` | `F9369376F62CF039…` |  |
| 19 | `site_s09_first_earned_engineering_test.gd` | visual | 240 | disabled | v4 | `S09_ORIGINAL_SETTLEMENT_FIRST_EARNED_DISABLED_PASS` | `8D3E5BE05A5DFBB9…` |  |
| 20 | `site_s10_first_earned_defense_test.gd` | visual | 240 | disabled | v4 | `S10_ORIGINAL_SETTLEMENT_FIRST_EARNED_DISABLED_PASS` | `0B315AA947EF1D30…` |  |
| 21 | `site_gd_contact_lesson_cold_math_test.gd` | headless | 30 | disabled | v3 | `TECH_GD_CONTACT_LESSON_COLD_MATH:` | `CDADF3AA8E165BC1…` |  |
| 22 | `site_gd_contact_boundary_math_test.gd` | headless | 30 | disabled | v3 | `TECH_GD_CONTACT_BOUNDARY_MATH:` | `E6ED5D022C0F123B…` |  |
| 23 | `site_technology_catalog_test.gd` | headless | 60 | enabled_isolated | v3 | `SITE_TECHNOLOGY_CATALOG_PASS` | `7C19D4FE33EF7866…` | 只有外部 timeout |
| 24 | `site_controller_work_team_water_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_CONTROLLER_WORK_TEAM_WATER_PASS` | `456F8EAFFF0134B6…` |  |
| 25 | `site_f01_farm_protocol_test.gd` | visual | 120 | enabled_isolated | v4 | `F01_BOUNDED_FARM_PROTOCOL_PASS` | `D2467AF330F54101…` |  |
| 26 | `site_f07_army_consent_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_F07_ARMY_CONSENT_PASS` | `CBC141FC3578F52B…` |  |
| 27 | `site_f07_authority_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_F07_AUTHORITY_PASS` | `EB278D3A6C081DB2…` |  |
| 28 | `site_f07_cold_jobs_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_F07_COLD_JOBS_PASS` | `0FD6DE272E48859D…` |  |
| 29 | `site_f07_person_state_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_F07_PERSON_STATE_PASS` | `1E7448FC11356193…` |  |
| 30 | `site_f07_research_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_F07_RESEARCH_PASS` | `5ABCFF9EE87305EA…` |  |
| 31 | `site_f08_new_job_duration_test.gd` | visual | 120 | enabled_isolated | v4 | `F08_NEW_ORIGINAL_CRAFT_DURATION_PASS` | `87154613260DE407…` |  |
| 32 | `site_f08_scope_camp_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_F08_SCOPE_CAMP_PASS` | `A166B6E30545E68F…` |  |
| 33 | `site_f09_survey_stakes_test.gd` | visual | 120 | enabled_isolated | v4 | `F09_TRUE_SURVEY_STAKES_PASS` | `DA1BDED5DD18572B…` |  |
| 34 | `site_f10_construction_method_test.gd` | visual | 120 | enabled_isolated | v4 | `F10_NEW_CONSTRUCTION_METHOD_PASS` | `EB34DD72E4E48F6E…` |  |
| 35 | `site_f11_joinery_scope_ui_test.gd` | visual | 600 | enabled_isolated | v4 | `SITE_F11_FIRST_EARNED_NATURAL_SHARED_COLD_FIXTURE:` | `B6DFBE1212A2DF05…` |  |
| 36 | `site_family_recipe_effect_test.gd` | visual | 120 | enabled_isolated | v4 | `FAMILY_RECIPE_REAL_EFFECT_PASS` | `F01A6985CE78BF2D…` |  |
| 37 | `site_n01_procurement_earned_test.gd` | visual | 150 | enabled_isolated | v4 | `N01_ORIGINAL_TWO_DELIVERIES_ADMIN_EARNED_FIXTURE_PASS` | `D43221E67A7BABD1…` |  |
| 38 | `site_n02_first_earned_labor_test.gd` | visual | 270 | enabled_isolated | v4 | `N02_FIRST_EARNED_ORIGINAL_LAB_POINT_FIXTURE_PASS` | `2044676E3252D45C…` |  |
| 39 | `site_n03_aid_ui_earned_test.gd` | visual | 210 | enabled_isolated | v4 | `N03_ORIGINAL_UI_TRANSFERS_SHARED_WORK_COLD_EARNED_PASS` | `C91B2CA54A4C1AF8…` |  |
| 40 | `site_n04_workshop_earned_test.gd` | visual | 150 | enabled_isolated | v4 | `N04_ORIGINAL_BOW_AND_INSPECTION_EARNED_FIXTURE_PASS` | `89BA53E3232E3E3B…` |  |
| 41 | `site_n05_military_issue_earned_test.gd` | visual | 210 | enabled_isolated | v4 | `N05_ORIGINAL_MANUFACTURE_AND_FIVE_SECOND_ISSUE_EARNED_FIXTURE_PASS` | `9676079ED11177F6…` |  |
| 42 | `site_n07_first_earned_course_test.gd` | visual | 150 | enabled_isolated | v4 | `N07_FIRST_EARNED_TWO_FINITE_REAL_COURSES_PASS` | `36D8CA2C15695599…` |  |
| 43 | `site_n09_tax_ui_earned_test.gd` | visual | 210 | enabled_isolated | v4 | `N09_ORIGINAL_UI_TRANSFERS_SHARED_WORK_COLD_EARNED_PASS` | `00C54D6B67341B64…` |  |
| 44 | `site_n10_first_earned_mandate_test.gd` | visual | 270 | enabled_isolated | v4 | `N10_FIRST_EARNED_TRUE_SLOT_MANDATE_FIXTURE_PASS` | `66C07037582FAB31…` |  |
| 45 | `site_n11_first_earned_armor_test.gd` | visual | 270 | enabled_isolated | v4 | `N11_FIRST_EARNED_ARMOR_ORIGINAL_LAB_POINT_FIXTURE_PASS` | `BE3CCEB13344A2BE…` |  |
| 46 | `site_n12_first_earned_fleet_test.gd` | visual | 150 | enabled_isolated | v4 | `N12_FIRST_EARNED_REAL_SHIPS_ADMIN_PASS` | `6426B23179A0F91A…` |  |
| 47 | `site_nation_fleet_operation_test.gd` | visual | 120 | enabled_isolated | v4 | `NATION_FLEET_REAL_SHIP_OPERATION_PASS` | `BD96B16F0DDFD083…` |  |
| 48 | `site_nation_public_operations_test.gd` | visual | 120 | enabled_isolated | v4 | `NATION_PUBLIC_SCHEMA_GRAIN_TRANSFER_PASS` | `8AC5E6765D25DB68…` |  |
| 49 | `site_nation_technology_operations_test.gd` | visual | 120 | enabled_isolated | v4 | `NATION_TECHNOLOGY_SCHEMA_N01_TRANSFER_PASS` | `903FF797299A18F7…` |  |
| 50 | `site_person_actions_shared_prefix_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_PERSON_ACTIONS_SHARED_PREFIX_PASS` | `FE139F5ADE1F7122…` |  |
| 51 | `site_person_actions_shared_prefix_vehicle_owner_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_PERSON_ACTIONS_SHARED_PREFIX_PASS` | `91EEEA915B5B831A…` |  |
| 52 | `site_settlement_engineering_test.gd` | visual | 120 | enabled_isolated | v4 | `S09_S10_ACTIVATED_ORIGINAL_PLAN_NAMED_WORK_COLD_CANCEL_PASS` | `1656956CC137EC01…` | 重跑#1 |
| 53 | `site_settlement_irrigation_test.gd` | visual | 120 | enabled_isolated | v4 | `S02_ACTIVATED_TRUE_CHANNEL_SCOPE_PAYMENT_NAMED_WORK_WATER_BOUND_DAMAGE_REPAIR_COLD_PASS` | `BF6F0641072FA012…` | 重跑#1 |
| 54 | `site_settlement_metal_chain_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_SETTLEMENT_METAL_CHAIN_PASS` | `4FEC44573697FEE3…` | 重跑#1 |
| 55 | `site_settlement_spares_test.gd` | visual | 120 | enabled_isolated | v4 | `S08_ACTIVATED_ORIGINAL_PRODUCT_REPAIR_PASS` | `53F6974A5B3B8587…` | 重跑#1 |
| 56 | `site_shared_vehicle_master_groups_v2_test.gd` | visual | 210 | enabled_isolated | v4 | `SITE_SHARED_VEHICLE_MASTER_GROUPS_V2_PASS` | `33D7871F5582D50E…` |  |
| 57 | `site_t5_captive_production_test.gd` | visual | 270 | enabled_isolated | v4 | `SITE_T5_CAPTIVE_PRODUCTION_PASS` | `A7B9ADC616841930…` |  |
| 58 | `site_technology_armor_recipes_test.gd` | visual | 210 | enabled_isolated | v4 | `SITE_TECHNOLOGY_ARMOR_RECIPES_PASS` | `4A5F50195B64A66A…` |  |
| 59 | `site_technology_artisan_birth_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_TECHNOLOGY_ARTISAN_BIRTH_PASS` | `C695EE34DA2966D6…` |  |
| 60 | `site_technology_artisan_f04_production_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_ENGINEERING_SUBSET_F04_PASS` | `2E1A699E994CA07E…` |  |
| 61 | `site_technology_artisan_f06_production_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_ENGINEERING_SUBSET_F06_PASS` | `70EADC0B5B33E27B…` |  |
| 62 | `site_technology_artisan_f11_production_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_ENGINEERING_SUBSET_F11_PASS` | `0839B10A056CD0E9…` |  |
| 63 | `site_technology_artisan_f12_production_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_ENGINEERING_SUBSET_F12_PASS` | `3984F89BC02F096E…` |  |
| 64 | `site_technology_artisan_fixed_f04_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_FIXED_D10_F04_PASS` | `2A321B6D6D02D8B3…` |  |
| 65 | `site_technology_artisan_fixed_f06_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_FIXED_D10_F06_PASS` | `D22C5DF7E4E627B0…` |  |
| 66 | `site_technology_artisan_fixed_f11_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_FIXED_D10_F11_PASS` | `BB6B24355A4B625E…` |  |
| 67 | `site_technology_artisan_fixed_f12_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_FIXED_D10_F12_PASS` | `C158E018311D0737…` |  |
| 68 | `site_technology_artisan_g06_f04_gates_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_G06_INCREMENT_F04_PASS` | `89FCBD5A4A61A94F…` |  |
| 69 | `site_technology_artisan_g06_f06_gates_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_G06_INCREMENT_F06_PASS` | `B3ABEE134AC54F0C…` |  |
| 70 | `site_technology_artisan_g06_f11_contact_point_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_G06_CONTACT_POINT_F11_PASS` | `ABF27D3D0541B4B5…` |  |
| 71 | `site_technology_artisan_g06_f11_gates_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_G06_INCREMENT_F11_PASS` | `5A32DB9DFF764838…` |  |
| 72 | `site_technology_artisan_g06_f11_point_order_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_G06_POINT_ORDER_F11_PASS` | `0E0B4FA177CCFB4A…` |  |
| 73 | `site_technology_artisan_g06_f12_contact_point_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_G06_CONTACT_POINT_F12_PASS` | `C4FCDD1FDD4323AB…` |  |
| 74 | `site_technology_artisan_g06_f12_gates_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_G06_INCREMENT_F12_PASS` | `06A8B30D7CD4CF53…` |  |
| 75 | `site_technology_artisan_g06_f12_point_order_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_G06_POINT_ORDER_F12_PASS` | `89EF3C3799ABE3A2…` |  |
| 76 | `site_technology_artisan_g06_three_birth_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_G06_THREE_BIRTH_PASS` | `A9470D48494FE9B1…` |  |
| 77 | `site_technology_artisans_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_TECHNOLOGY_ARTISANS_CANDIDATE_PASS` | `0039B5A114A7EE51…` |  |
| 78 | `site_technology_checked_work_prefix_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_TECHNOLOGY_CHECKED_WORK_PREFIX_PASS` | `D8CFC96CB3BE750A…` |  |
| 79 | `site_technology_completed_vehicle_lineage_test.gd` | visual | 210 | enabled_isolated | v4 | `SITE_TECHNOLOGY_COMPLETED_VEHICLE_LINEAGE_PASS` | `27E7B85D55E8C183…` |  |
| 80 | `site_technology_controller_prefix_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_TECHNOLOGY_CONTROLLER_PREFIX_PASS` | `AD780B6B8CE29784…` |  |
| 81 | `site_technology_f13_named_ferry_test.gd` | visual | 210 | enabled_isolated | v4 | `SITE_TECHNOLOGY_F13_NAMED_FERRY_PASS` | `791AB98DD320FA88…` |  |
| 82 | `site_technology_family_ai_original_test.gd` | visual | 240 | enabled_isolated | v4 | `SITE_TECHNOLOGY_FAMILY_AI_ORIGINAL_PASS` | `C53512B3F63FD079…` |  |
| 83 | `site_technology_feature_output_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_TECHNOLOGY_FEATURE_OUTPUT_PASS` | `9FAB2E2883032EB7…` |  |
| 84 | `site_technology_fire_pot_ordinary_ui_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_TECHNOLOGY_FIRE_POT_ORDINARY_UI_PASS` | `653072598DAD669D…` |  |
| 85 | `site_technology_fire_pot_scope_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_TECHNOLOGY_FIRE_POT_SCOPE_PASS` | `91DE0BFB0226518F…` |  |
| 86 | `site_technology_fire_pot_trial_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_TECHNOLOGY_FIRE_POT_TRIAL_PASS` | `16E8692729E29EB4…` |  |
| 87 | `site_technology_g06_paired_source_test.gd` | visual | 210 | enabled_isolated | v4 | `G06_PAIRED_SOURCE_ORIGINAL_READER_PIN_COLD_PASS` | `2842BE6BCD2BA3A9…` |  |
| 88 | `site_technology_holder_test.gd` | visual | 120 | enabled_isolated | v4 | `TECHNOLOGY_HOLDER_CANDIDATE PASS` | `83C340FBCE3FEFC0…` |  |
| 89 | `site_technology_military_production_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_TECHNOLOGY_MILITARY_PRODUCTION_PASS` | `499182DB8F2DAE4E…` |  |
| 90 | `site_technology_nation_material_test.gd` | visual | 120 | enabled_isolated | v4 | `TECHNOLOGY_NATION_SOURCE_BUILD_OUTPUT_FIXTURE_PASS` | `10F7AED4639DBE7A…` |  |
| 91 | `site_technology_paid_feature_resume_test.gd` | visual | 120 | enabled_isolated | v4 | `TECHNOLOGY_PAID_FEATURE_RESUME_PASS` | `0AB16C8931DD22DF…` |  |
| 92 | `site_technology_productive_processing_window_test.gd` | visual | 210 | enabled_isolated | v4 | `SITE_PRODUCTIVE_PROCESSING_WINDOW_SOURCE_FIXTURE:` | `92E1280C9B48934F…` |  |
| 93 | `site_technology_productive_ship_window_test.gd` | visual | 210 | enabled_isolated | v4 | `SITE_PRODUCTIVE_SHIP_WINDOW_SOURCE_FIXTURE:` | `BE134CB16BE528AD…` |  |
| 94 | `site_technology_productive_yard_window_test.gd` | visual | 210 | enabled_isolated | v4 | `SITE_PRODUCTIVE_YARD_WINDOW_SOURCE_FIXTURE:` | `43DEF5DE842FB4D0…` |  |
| 95 | `site_technology_s01_water_owner_test.gd` | visual | 210 | enabled_isolated | v4 | `SITE_TECHNOLOGY_S01_WATER_OWNER_PASS` | `BC3AA031CB4890B9…` | 重跑#1 |
| 96 | `site_technology_s06_food_owner_test.gd` | visual | 210 | enabled_isolated | v4 | `SITE_TECHNOLOGY_S06_FOOD_OWNER_PASS` | `25BB3FB050DC8C4F…` |  |
| 97 | `site_technology_settlement_processing_test.gd` | visual | 210 | enabled_isolated | v4 | `SITE_TECHNOLOGY_SETTLEMENT_PROCESSING_PASS` | `18E5AA1C6582E8A6…` |  |
| 98 | `site_technology_settlement_ship_test.gd` | visual | 210 | enabled_isolated | v4 | `SITE_TECHNOLOGY_SETTLEMENT_SHIP_PASS` | `54C590DBA40B88E8…` |  |
| 99 | `site_technology_ship_target_config_test.gd` | visual | 210 | enabled_isolated | v4 | `SITE_TECHNOLOGY_SHIP_TARGET_CONFIG_PASS` | `F85BB516D2D3766D…` |  |
| 100 | `site_technology_shipyard_physical_test.gd` | visual | 210 | enabled_isolated | v4 | `SITE_TECHNOLOGY_SHIPYARD_PHYSICAL_PASS` | `4522BBC3129034B0…` |  |
| 101 | `site_technology_siege_yard_test.gd` | visual | 210 | enabled_isolated | v4 | `SITE_TECHNOLOGY_SIEGE_YARD_PASS` | `E77BE4681606277D…` |  |
| 102 | `site_technology_targeted_vehicle_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_TECHNOLOGY_TARGETED_VEHICLE_PASS` | `02657AD5B661B7B4…` |  |
| 103 | `site_technology_work_credit_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_TECHNOLOGY_WORK_CREDIT_PASS` | `0CBDEA205D9FDC51…` |  |
| 104 | `site_work_team_master_groups_v2_test.gd` | visual | 210 | enabled_isolated | v4 | `SITE_WORK_TEAM_MASTER_GROUPS_V2_PASS` | `CB54A7678465B896…` |  |
| 105 | `site_work_team_plan_integration_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_WORK_TEAM_PLAN_INTEGRATION_PASS` | `B184CBB9F55B4A13…` |  |
| 106 | `site_work_team_t6_weights_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_WORK_TEAM_T6_WEIGHTS_PASS` | `B5791D1AB89C8256…` |  |
| 107 | `site_t5_supervised_public_ui_test.gd` | visual | 180 | enabled_isolated | v4 | `SITE_T5_SUPERVISED_PUBLIC_UI_PASS` | `FB5D1BE401DC5AFD…` | 重跑#1 |
| 108 | `site_t6_analysis_public_ui_test.gd` | visual | 180 | enabled_isolated | v4 | `SITE_T6_ANALYSIS_PUBLIC_UI_PASS` | `9526EE12A384F171…` | 重跑#1 |
| 109 | `site_f01_family_first_earned_test.gd` | visual | 600 | enabled_isolated | v4 | `F01_ORIGINAL_FAMILY_FIRST_EARNED_SHARED_COLD_PASS` | `DCA9ADCD24D700C1…` |  |
| 110 | `site_f02_family_first_earned_test.gd` | visual | 600 | enabled_isolated | v4 | `F02_ORIGINAL_FAMILY_FIRST_EARNED_SHARED_COLD_PASS` | `F930133DC80E5E36…` |  |
| 111 | `site_f03_family_first_earned_test.gd` | visual | 210 | enabled_isolated | v4 | `F03_ORIGINAL_FAMILY_FIRST_EARNED_SHARED_COLD_PASS` | `043C9FAC45C128D7…` |  |
| 112 | `site_f05_family_first_earned_test.gd` | visual | 210 | enabled_isolated | v4 | `F05_ORIGINAL_FAMILY_FIRST_EARNED_SHARED_COLD_PASS` | `3BC2F08DB077078B…` |  |
| 113 | `site_f09_family_first_earned_test.gd` | visual | 210 | enabled_isolated | v4 | `F09_ORIGINAL_FAMILY_FIRST_EARNED_SHARED_COLD_PASS` | `2EC7928B2952225C…` |  |
| 114 | `site_f10_family_first_earned_test.gd` | visual | 210 | enabled_isolated | v4 | `F10_ORIGINAL_FAMILY_FIRST_EARNED_SHARED_COLD_PASS` | `43C2EE8B1C72DCE5…` |  |
| 115 | `site_f14_family_first_earned_test.gd` | visual | 210 | enabled_isolated | v4 | `F14_ORIGINAL_FAMILY_FIRST_EARNED_SHARED_COLD_PASS` | `16A9BBFEDAA54175…` |  |
| 116 | `site_f04_fixed_first_earned_test.gd` | visual | 210 | enabled_isolated | v4 | `SITE_F04_FIXED_FIRST_EARNED_PASS` | `4EB7CE8C009ADA57…` |  |
| 117 | `site_f06_fixed_first_earned_test.gd` | visual | 210 | enabled_isolated | v4 | `SITE_F06_FIXED_FIRST_EARNED_PASS` | `274BB55BD9CAE95F…` |  |
| 118 | `site_g06_source_rule_ui_test.gd` | visual | 90 | enabled_isolated | v4 | `SITE_G06_SOURCE_RULE_UI_PASS` | `441796EC06D82CF5…` | 重跑#1 |
| 119 | `site_s07_first_earned_workshop_test.gd` | visual | 240 | enabled_isolated | v4 | `S07_ORIGINAL_SETTLEMENT_FIRST_EARNED_SHARED_COLD_PASS` | `2BA71D32BBE77C32…` | 重跑#1 |
| 120 | `site_s08_first_earned_spares_test.gd` | visual | 240 | enabled_isolated | v4 | `S08_ORIGINAL_SETTLEMENT_FIRST_EARNED_SHARED_COLD_PASS` | `F9369376F62CF039…` | 重跑#1 |
| 121 | `site_s09_first_earned_engineering_test.gd` | visual | 240 | enabled_isolated | v4 | `S09_ORIGINAL_SETTLEMENT_FIRST_EARNED_SHARED_COLD_PASS` | `8D3E5BE05A5DFBB9…` | 重跑#1 |
| 122 | `site_s10_first_earned_defense_test.gd` | visual | 240 | enabled_isolated | v4 | `S10_ORIGINAL_SETTLEMENT_FIRST_EARNED_SHARED_COLD_PASS` | `0B315AA947EF1D30…` | 重跑#1 |
| 123 | `site_f12_first_earned_counterweight_test.gd` | visual | 600 | enabled_isolated | v4 | `F12_ORIGINAL_FIRST_EARNED_TRACTION_COUNTERWEIGHT_SHARED_COLD_PASS` | `7E3E248D2360530E…` |  |
| 124 | `site_technology_f11_gd_mesh_work_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_G06_CONTACT_POINT_F11_PASS` | `F993AA7479C37F9F…` |  |
| 125 | `site_technology_f12_gd_mesh_work_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_G06_CONTACT_POINT_F12_PASS` | `213B8C8418DCFE7E…` |  |
| 126 | `site_gd_contact_manual_original_point_test.gd` | visual | 210 | enabled_isolated | v4 | `GD_CONTACT_MANUAL_ORIGINAL_POINT PASS` | `62D0D81A185E80B8…` |  |
| 127 | `site_gd_contact_controlled_f11_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_G06_CONTACT_POINT_F11_PASS` | `0AF5B4C891990E54…` |  |
| 128 | `site_gd_contact_controlled_f12_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_AI_02_G06_CONTACT_POINT_F12_PASS` | `806C9416F43A06B4…` |  |
| 129 | `site_gd_contact_supply_f11_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_GD_CONTACT_SUPPLY_F11_PASS` | `29FED51283EE38AF…` |  |
| 130 | `site_gd_contact_supply_f12_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_GD_CONTACT_SUPPLY_F12_PASS` | `195774CC375C3449…` |  |
| 131 | `region_n08_civil_original_ui_test.gd` | visual | 210 | enabled_isolated | v4 | `REGION_N08_CIVIL_ORIGINAL_UI_PASS` | `1939340C46C0BD51…` |  |
| 132 | `site_gd_contact_training_original_point_test.gd` | visual | 210 | enabled_isolated | v4 | `TECH_GD_CONTACT_TRAINING_ORIGINAL_POINT_PASS` | `157C4E369AFAB523…` |  |
| 133 | `site_gd_same_unit_sum_original_point_test.gd` | visual | 210 | enabled_isolated | v4 | `GD_SAME_UNIT_SUM_ORIGINAL_POINT_PASS` | `FF099ED37EEAF642…` |  |
| 134 | `site_p4_cold_original_research_test.gd` | visual | 660 | enabled_isolated | v5 | `P4_COLD_ORIGINAL_RESEARCH_COMPONENT_PASS` | `B5C33F8F97D99288…` |  |
| 135 | `site_ranged_terminal_batch_owner_test.gd` | visual | 210 | enabled_isolated | v4 | `RANGED_TERMINAL_BATCH_OWNER_COMPONENT_PASS` | `24A7E09AB14241A1…` |  |
| 136 | `site_gd_rest_terminal_source_test.gd` | visual | 210 | enabled_isolated | v4 | `GD_CONTACT_REST_TERMINAL_SOURCE_PASS` | `BF4F53AE1499F660…` |  |
| 137 | `site_gd_delivery_prefix_owner_test.gd` | visual | 210 | enabled_isolated | v4 | `GD_CONTACT_DELIVERY_OWNER_PASS` | `AE266E3B070A8174…` |  |
| 138 | `site_gd_delivery_mesh_contact_test.gd` | visual | 210 | enabled_isolated | v4 | `GD_CONTACT_DELIVERY_MESH_PASS` | `38FD9CD1EF65749B…` |  |
| 139 | `site_runtime_typed_terminal_prepare_test.gd` | headless | 150 | enabled_isolated | v3 | `RUNTIME_TYPED_TERMINAL_PREPARE_COMPONENT_PASS` | `75B6299F1A898DDD…` | 內部期限 120s |
| 140 | `site_gd_shiprepair_point_test.gd` | visual | 210 | enabled_isolated | v4 | `GD_CONTACT_SHIP_REPAIR_POINT_PASS` | `635D5F6014C4ACB0…` | 內部期限 180s |
| 141 | `site_gd_shiprepair_mesh_test.gd` | visual | 210 | enabled_isolated | v4 | `GD_CONTACT_SHIP_REPAIR_MESH_PASS` | `03F7378AF6F1FBA2…` | 內部期限 180s |
| 142 | `site_equipment_original_prepared_exchange_test.gd` | visual | 210 | enabled_isolated | v4 | `EQUIPMENT_ORIGINAL_PREPARED_EXCHANGE_PASS` | `E40A7612C6FD4974…` | 內部期限 180s |
| 143 | `site_gd_opened_loot_supply_test.gd` | visual | 210 | enabled_isolated | v4 | `GD_OPENED_LOOT_SUPPLY_COMPONENT_PASS` | `492CE4CB85CFB80E…` | 內部期限 180s |
| 144 | `site_gd_custody_terminal_point_test.gd` | visual | 210 | enabled_isolated | v4 | `GD_CUSTODY_TRUE_POINT_TERMINAL_PASS` | `658AD8EE3AFD6C58…` | 內部期限 180s |
| 145 | `site_n07_funded_lesson_terminal_point_test.gd` | visual | 210 | enabled_isolated | v4 | `N07_FUNDED_LESSON_TRUE_POINT_TERMINAL_PASS` | `BC11FB0DEA2228AF…` | 內部期限 120s |
| 146 | `site_t5_captive_terminal_point_test.gd` | visual | 210 | enabled_isolated | v4 | `T5_CAPTIVE_TRUE_POINT_TERMINAL_PASS` | `C421D94290788BE1…` | 內部期限 180s |
| 147 | `site_gd_typed_loot_point_test.gd` | visual | 210 | enabled_isolated | v4 | `GD_TYPED_LOOT_POINT_PASS` | `BA8CAB6385F43A69…` | 內部期限 180s |
| 148 | `site_gd_typed_loot_mesh_test.gd` | visual | 210 | enabled_isolated | v4 | `GD_TYPED_LOOT_MESH_PASS` | `7A8709E0986E9584…` | 內部期限 180s |
| 149 | `site_gd_original_action_endpoint_point_test.gd` | visual | 210 | enabled_isolated | v4 | `GD_ORIGINAL_ACTION_ENDPOINTS_POINT_PASS` | `4FFD68DC7CFA1855…` | 內部期限 180s |
| 150 | `site_controller_native_checked_point_v2_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_CONTROLLER_NATIVE_CHECKED_POINT_V2_PASS` | `5497716AEBB5857D…` | Native 9E21；內部 90s |
| 151 | `site_native_begin_original_caller_v5_test.gd` | visual | 120 | enabled_isolated | v4 | `NATIVE_BEGIN_ORIGINAL_CALLER_V5_PASS` | `76DCDE2FA597C043…` | Native 9E21；內部 90s |
| 152 | `site_native_begin_siege_zero_endpoint_v7_test.gd` | visual | 120 | enabled_isolated | v4 | `NATIVE_BEGIN_SIEGE_ZERO_ENDPOINT_V7_PASS` | `C4FD84E2D39ED366…` | Native 9E21；內部 90s |
| 153 | `site_native_begin_source_endpoint_v6_test.gd` | visual | 120 | enabled_isolated | v4 | `NATIVE_BEGIN_SOURCE_ENDPOINT_V6_PASS` | `7CC8251AF57C4C0E…` | Native 9E21；內部 90s |
| 154 | `site_scope_native_consent_test.gd` | visual | 120 | enabled_isolated | v4 | `SITE_SCOPE_NATIVE_CONSENT_PASS` | `6C80C3DBF7E9AA26…` | Native 9E21；內部 90s |

## 附錄 B：C06 獨立 profile（不在 154 次內）

| # | 測試 | 參數 | 模式 | 內部／外部秒數 | marker |
|---|---|---|---|---|---|
| 1 | `region_player_first_siege_contact_physical_test.gd` | --player-witness-case=positive | headless | 480/540 | `REGION_PLAYER_FIRST_CONTACT_PHYSICAL_PASS` |
| 2 | `region_player_first_siege_contact_physical_test.gd` | --player-witness-case=moved | headless | 480/540 | `REGION_PLAYER_FIRST_CONTACT_PHYSICAL_PASS` |
| 3 | `region_player_first_siege_contact_physical_test.gd` | --player-witness-case=dead | headless | 480/540 | `REGION_PLAYER_FIRST_CONTACT_PHYSICAL_PASS` |
| 4 | `region_player_first_siege_contact_physical_test.gd` | --player-witness-case=ended | headless | 480/540 | `REGION_PLAYER_FIRST_CONTACT_PHYSICAL_PASS` |
| 5 | `region_food_reinforcement_multi_approach_physical_test.gd` |  | headless | 420/480 | `REGION_FOOD_REINFORCEMENT_MULTI_APPROACH_PASS` |
