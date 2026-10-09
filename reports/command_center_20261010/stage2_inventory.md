# 第二階段合併盤點（隔離副本 epoch → D HEAD）2026-10-10

產生：指揮中心以函式層級比對 `region_direct_validation_project_20261008`（Region 隔離副本）與 D 工作樹（`f507067` 加上本輪呼叫點補丁）。原始資料：`stage2_inventory.json`（每檔 missing／A／B／C／D 獨有）與 `stage2_direction.json`（每個 A／B 函式的 epoch 獨有行是否曾出現在 D 的 git 歷史）。

判讀：
- A＝epoch 多出行、D 沒有自己的行；B＝兩邊各有獨有行；C＝只有 D 多出行（D 較新，不處理）。
- 「epoch 新增」＝該行（去掉縮排）從未出現在 D 該檔的 git 歷史（ef39140 起），是 D 缺的。「D 歷史有」＝該行文字在 D 該檔出現過，可能只是縮排不同或在別的函式，也可能被 D 刪掉；不能單憑這欄判斷 D 較新，要看 json 裡的 commit 與 D 獨有行。
- 限制：ef39140 之前沒有 git 歷史，那之前 D 刪掉的行會被誤判成「epoch 新增」，套用前仍需人工確認。

## 1. 總量

33 個程式檔有差異：missing 40、A 116、B 97、C 35。扣除音效（交 AUDIO-02）、診斷專用行（time_mark／tag_corrupt／REGION_DIAG，不合入）與空白／註解差異後，實際需判斷約 100 個函式。D 上「有定義、沒有呼叫端」的只剩 `_initial_technology_categories`（region_save_slot）與 `_region_party_bind_admission`（terrain_lab）。

## 2. 已由指揮中心處理

- 呼叫點補回（`epoch_callsites.patch`）：`finish_tick` 完成可取消出發、`update_ui` 原旅隊續行按鈕與營建視窗刷新、`_build_ui` 改用 `request_departure`、續行按鈕、聚落工程與渠道面板、國家制度按鈕；terrain_lab `_advance_movement_input`／`controlled_attack`／`_try_move` 出發暫緩守衛。
- 進行中：旅隊 host 一組由 Region 第 5 輪 `party_host_epoch.patch` 交付（`_region_capture_original_owner_state`、`_prepare_region_main_interval`、`record_completed_region_travel_step`、`_region_player_down_settlement`），正是 region_travel_test 中途存檔 STALE_REGION_OWNER 的那一行；固定地類規則一組（region_data `_read_resource_manifest`／`load_manifest`／`_validate_manifest`、region_terrain_adapter `build`、site_store `_same_fixed_base`／`load_site`）。D 的 SiteEnvironment 已會讀 `fixed_land_condition_rule`，但 adapter 從不設定它，宣告 `land_condition_rule` 的固定地理 Site 會得到全 0 的地基／肥力；遊戲入口的第二個台灣選項（地形衍生建設與水井條件）也會因舊版 `_read_resource_manifest` 只認舊配對而沒有資源層。

## 3. 待各線處理（epoch 新增、D 未有）

| 擁有者 | 檔案：函式 | 內容 |
|---|---|---|
| Region | site_controller `load_from`、`_load_compatible_site` | 選定存檔的原 owner 恢復（selected restore） |
| Region | site_controller `ship_journey_active`／`ship_vehicle_in_journey`／`ship_person_in_journey`；site_vehicle_transport `_claims`、`ship_person_ground`／`ship_person_cell`／`ship_loot_ground`、`transfer`、`_transfer_ship`；site_vehicle_view `_refresh_ship_loot`、`_ship_in_journey`；terrain_army `_hide_journey_person` | 船隻 Region 投影 |
| Region | region_save_slot `open_map`、`_initial_site_same`（D 缺）、`_initial_complete_ok`、`_check_initial_record`、`prepare_initial_site`；`_initial_technology_categories` 無呼叫端 | 初始世界紀錄（科技 open_map 一起） |
| Region | region_save_slot `_read_document`、`_save_checked` | 存檔信封解析與讀回 |
| Region | region_save_slot `_region_player_down_settlement`（已併入 Region 第 5 輪 party_host_epoch）、terrain_lab `_region_bind_original_terrain`、`_region_bind_ticket_admission` 的 party 分支 | 需 Region 判斷 |
| Region | region_route `table_from_terrain`、`clear_memory_cache`、`_navigation_content_hash`（D 缺） | 第 4 輪 P1' 已用另一寫法落地，判斷是否仍需要 |
| Region | site_equipment_orders `_normalize_public_order`、`_valid_public_order`、`_public_receipt_matches_order` | N08 公共路線工單的跨 Site 操作者引用與 transfer_token（與 region_n08 測試一起） |
| Region（測試） | region_captivity_payload_admission_test | 測試寫的是 epoch 舊版 v3 拘押關係（10 欄、episode 字串）；D 已是 AI 職位社會計畫 4.2／6.1 的 v3（13 欄、loyal_org、rank_snapshot），測試要改成 D 格式，程式不回退 |
| 音效（素材） | assets/audio 的 25 個 P3 WAV、7 個替換版 WAV、catalog.json、P3_ADDITIONAL_CREDITS.md | 程式已於 `9f5cad5` 落地；素材含 CC BY-SA 3.0 DE 野豬叫聲，等 Nekki 決定 |

**已由指揮中心補上（第 7 輪）**：site_technology `prepare_holder_control_transition`（stage 1 只帶了呼叫端，region_save_slot 以 `has_method` 動態呼叫，D 上家族遠端移交一律回 MISSING_TECHNOLOGY_CONTROL_TRANSFER）、site_runtime `cancel_feature` 的攻城場／船塢撤回守衛、site_training_ground `inspect` 的群眾工作疲勞守衛；第 8 輪 site_person_actions `_technology_matching_original_task`（糧令、水排程與具名移動任務的科技工作比對）。

**複查後確定 D 較新、不合入**：拘押期（crowd_site `_commit_captivity`、site_person_actions `new_capture_fields`／`publish_gd_custody_terminal`、site_store `_normalize_state`／`_validate_captivity`）；AI 職位（site_controller `_office_orgs`、site_duty_ai `review`、terrain_army `apply_office_plan`／`_install_roster`／`transfer_members_to`、site_garrison `_authority`）；social schema（site_store `save`／`_validate_state`／`_validate_unadmitted_social_state`）；科技 teach 改名（`begin_technology_lesson` 等四個）；crowd_person_owner 射擊彈藥（D 已把 assert 內的副作用移出）；site_store `_validate_site_values` 的水排程檢查（D 已移到 `_validate_fs_targets`）。

## 4. 測試

只在 epoch 的測試 7 支（5 支音效、`region_direct_fixture_load_check`、`region_npc_duplicate_arrival_event_guard_original_test`）。兩邊不同的測試 32 支，多數是 D 較新（AI 職位、生態），不整檔覆寫。
