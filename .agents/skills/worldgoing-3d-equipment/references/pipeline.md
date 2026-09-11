# 已核對的接入路徑（2026-09-09）

以下路徑相對專案根目錄；開始任務時再次核對，不將文件中的尺寸或動作數視為固定契約。

## 實際擁有者

| 用途 | 路徑／符號 |
| --- | --- |
| 流程與歷史 | `HUMANBASE_V1_3D_PIPELINE_HANDOVER.md` |
| 男角色建置 | `scripts/tools/blender/build_standard_anime_male_character_pack.py` 的 `main()` |
| 女角色建置 | `scripts/tools/blender/build_standard_anime_female_character_pack.py` |
| 鐵靴部件 | `scripts/tools/blender/make_chinese_iron_boots.py` 的 `make_chinese_iron_boots` |
| 其他裝備範例 | 同目錄 `make_chinese_iron_armor.py`、`make_chinese_iron_helmet.py` |
| Blender 啟動入口 | `scripts/tools/blender/run_blender.ps1` |
| 模型输出 | `assets/characters/human/q35/standard_anime_male_character_pack.{blend,glb,json}`；female 對應名稱 |
| 編輯器 | `scripts/ui/human_character_3d_editor.gd`；`scenes/ui/HumanCharacter3DEditor.tscn` |
| 功能／圖像測試 | `scripts/tests/human_character_3d_editor_test.gd`、`human_character_3d_editor_clipping_test.gd` |
| 預覽 | `.visual_captures/human_character_3d_editor/`；`.visual_captures/standard_anime_male_character_pack/blender/` |

目前男 builder 匯入並呼叫 `make_chinese_iron_boots(armature, source_raw_body=body_skin, is_female=False, create_rigid_fn=create_bone_rigid_component)`，加入 `all_boots_objects`。修改前查看 helper 實作、女 builder 的對應呼叫與來源表面內容；此處 `body_skin` 與提取之前的 raw clothed VRM 不是相同來源。

## 一個部件從 Blender 到下拉選單

1. 建模函式回傳所有屬於該部件的物件（包括甲片、扣具、內靴），統一且唯一的前綴；確保骨架、材質、法線與變換有效。
2. 在男女 builder 中按需求呼叫，加入部件集合與 `export_objects`。只建出物件卻未加入選取匯出集合，不會出現在 GLB。
3. 匯出選取物件時包括骨架、skins、所需 actions；檢查實際 `export_animations`、`export_animation_mode`、frame range，保留現有動作與其他部件。更新 JSON 部件清單。`.blend` 是可编辑来源，`.glb` 才是編輯器載入資料。
4. 編輯器 `PART_SLOTS` 目前靴子選項包含 `boots_leather_01`→`Boots_Leather_01`、`boots_iron_01`→`Boots_Iron_01` 及無。新增品項需加入唯一 ID／prefix；有意替換鐵靴則保留現有映射。不能只新增文字選項。
5. `EQUIPMENT_PREFIXES` 決定装備風格處理範圍；新增前綴時一併檢查。`_refresh_part_options()` 根據真實節點可用性啟用選項，`_apply_part_selection()` 切換可見性並更新身體遮罩。檢查相關 `_component_has_nodes`、`_find_component_nodes` 的實際匹配行為，避免前綴互相包含造成串選。
6. `_apply_equipment_style()`／`_apply_toon_surfaces()` 目前把裝備轉成 ShaderMaterial，只傳 `base_color`、`base_metallic`、`base_roughness`。PBR 紋理、normal、AO 不會因此自動保留。若任務要求貼圖細節，先追查 shader 並在所需範圍增加支援，再實測；不要改全角色風格來補一件裝備。
7. 更新 GLB 後確認 Godot 重匯入。若顯示舊模型，檢查載入路徑、import 時間與日誌；需要時做一次有界 editor import，不刪整個 `.godot` 當通用修法。

## 執行方式

先檢查 runner、執行環境與監控規則。以下指令在專案根目錄執行；男女只執行本次有影響的包。

```powershell
& '.\scripts\tools\blender\run_blender.ps1' --background --python '.\scripts\tools\blender\build_standard_anime_male_character_pack.py'
& '.\scripts\tools\blender\run_blender.ps1' --background --python '.\scripts\tools\blender\build_standard_anime_female_character_pack.py'
```

閱讀現有 test 後選擇相關 capture；一般測試可能只選預設皮靴，並未覆蓋新增鐵靴。若沒測到目標，補一個聚焦的選取／動畫／截圖案例。不要用預設裝備的成功截圖驗收另一個選項。

```powershell
& (Join-Path $env:USERPROFILE '.codex\skills\godot-runtime-verify\scripts\verify_godot.ps1') -ProjectPath (Get-Location).Path -GodotExecutable 'Godot_v4.6.2-stable_mono_win64_console.exe' -Mode visual -GodotArguments @('--script','res://scripts/tests/human_character_3d_editor_test.gd') -TimeoutSeconds 120
```

以當次 test 的實際輸出設定 `-ExpectedOutput`，核對新檔案並看圖。退出碼、錯誤日誌、功能断言、视觉观察分开記錄。檔名含 clipping 不代表測試做了幾何碰撞檢查。

`-ExpectedOutput` 接檔案路徑，不能填 stdout 的 PASS 文字；文字標記由日誌核對。缺檔、腳本失敗與視覺不合格是不同原因，不改寫原日誌來掩蓋失敗。

## 中式披風的可編輯來源

`make_chinese_cape.py` 現在載入 `assets/characters/human/q35/chinese_cloak/chinese_cloak_{male,female}.blend`，不再每次重建舊布板。`load_authored_chinese_cape.py` 的 `bind_cape_action_tracks` 在男女 builder 的既有動作建立後執行。顯式美術入口為 `author_chinese_cape.py`；`finish` 會重建披風，日常手動修形後只用 `export`，避免沖掉編輯。

編輯器對 `Cape_Chinese_01_`、`Armor_Chinese_Leather_01_`、`Helmet_Mingguang_01_` 保留來源貼圖材質並略過粗描邊，其他裝備仍走原路由。披風聚焦檢查：Blender `scripts/tests/chinese_cloak_loader_test.py`、Python `scripts/tests/validate_chinese_cloak_assets.py`、Godot `scripts/tests/capture_chinese_cloak_candidate.gd -- male final`（female 對應）。前兩者使用本次 scoped baseline；第三者的 `final` 直接驗證正式資產。不可把來源動畫的未公開 raw clips 計入披風支援動作數。

## 中式皮甲與明光盔（2026-09-10）

新增選項為 `armor_chinese_leather_01`、`helmet_mingguang_01`。男女 builder 透過 `load_authored_chinese_gear.py` 載入 `assets/characters/human/q35/chinese_leather_mingguang/chinese_gear_{male,female}.blend`，保留手動修改；再將頭盔白纓的 shape-key NLA 與既有骨骼動作合併。沒有新增平行骨架。

顯式製作入口：`author_chinese_leather_mingguang.py` 的 `gray` 重建灰模、`detail` 重建裝飾，`export` 僅匯出可編輯來源。不要在手工修模後重跑 `gray/detail`。`scripts/tests/run_chinese_equipment_stages.py` 使用每階段 180 秒硬逾時、Blender `--python-exit-code 1` 與獨立日誌；背景仍需持續追蹤實際工作 ID。專案指定計時工具不可用時，沿用已取得的替代授權，不能宣稱存在該工具。

聚焦檢查為 `scripts/tests/chinese_gear_loader_test.py`、`validate_chinese_leather_mingguang.py --final`、`capture_chinese_leather_mingguang.gd -- male final`（female 對應）。資產比對包括既有網格、骨架、原動畫 channels 的數值保留；視覺測試包括新選項／無／舊選項、PBR 貼圖、白纓即時形變、四種髮型、七種指定動作與穿戴組合。這不是全動作、全組合或多人效能證明。範圍與限制見根目錄 `CHINESE_LEATHER_MINGGUANG_HELMET_DELIVERY.md`。

## 美術預覽與材質易錯處

`select_animation_by_id()` → `_play_selected_animation()` → `_update_preview_framing()` 會重設為 `CharacterRenderContract` 相機。美術 capture 應在選動畫／seek 後設檢視相機，直接保存 `preview_viewport`；整個 UI 圖另存。不要為放大驗收圖而改動共享地圖投影比例。

`_is_equipment_node()` 的細節排除曾同時跳過描邊與 Toon 轉換，含 `_Lining` 的名稱因此與外布走不同材質。以當前路由核對，將是否描邊與是否保留來源材質作明確選擇。新增紋理前先確認 GLB 有 UV、來源貼圖存在，且引擎實際取樣；新增形態校正先用短動作驗證 morph target 和動畫 channel，不以 `export_morph=True` 本身驗收。

## 明光鎧戰靴參考圖的使用範例

圖片是設計參考，並未提供可用 3D 網格。拆成：貼腿黑皮內靴、腳底與腳跟、前脛覆疊甲片、鞋頭護甲、側護片、皮帶扣、鉚釘、獸面飾件。先確認靴口相對膝蓋的位置與穿戴輪廓，再做甲片孔洞和裝飾。

主要镂空孔洞如果會看穿且影響輪廓，要有實際幾何或經確認可用的透明材質；遠景細節可烘焙，但須驗證 Toon 是否保留。獸面浮雕不等於一個球體，無法完成時明確標為未完成細節。不要從 Temp 路徑長期引用圖片；真正開始建模時將使用者指定參考保存到專案的 reference 目錄並記錄來源。

第一輪拍左右靴穿在素體上與靴子單獨四視圖；第二輪拍編輯器中選中目標靴的正背側及行走、跑步關鍵幀。圖片裡有開口、浮動帶子或身體露出甲片時逐一判斷是設計開口還是穿模，不能一律算正常。
