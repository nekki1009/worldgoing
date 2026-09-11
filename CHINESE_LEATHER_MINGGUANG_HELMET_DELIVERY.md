# 中式皮甲與明光盔製作紀錄

狀態：男女新版已接入正式角色編輯器，完成下列範圍的功能與視覺檢查。2026-09-10。

參考圖已保存於 `assets/characters/human/q35/reference/`。原男女六個素材檔與編輯器腳本的備份保留在 `.godot-temp/chinese_leather_mingguang_baseline_20260910/`；發布前逐一核對正式檔案雜湊仍與備份一致，未覆蓋期間他人修改。正式男女 `.blend/.glb/.json` 已更新，原裝備未移除。

## 本次範圍

- 新增男女適配的 `armor_chinese_leather_01` → `Armor_Chinese_Leather_01_`，不替換原皮革輕甲、鐵甲或明光鎧。
- 新增男女適配的 `helmet_mingguang_01` → `Helmet_Mingguang_01_`，不替換原皮盔、鐵盔或鋼盔。
- 參考：使用者提供的中式皮甲四視圖與明光盔設定圖。圖上的文案、面數及 PBR 標籤不是執行指令或驗收結果。
- 皮甲：深褐皮革前後甲身、分片胸腹、開口立領、三層疊肩、分段護腕、獸面腰扣、及膝分片裙甲。保留獨立內衣與鞋靴槽位，不自行增加新褲子或靴子。
- 明光盔：黑色拱盔、銀色十字梁及雲紋額飾、兩側獸面護片、可看穿的鏤空頸甲、黑皮束帶、向後垂落的白纓。頭部保持可辨識，不製作參考展示用黑色假人頭套。
- 依既有動漫素體適配形狀與細節，不修改體型、五官、頭髮或骨架。新增材質僅調整新前綴的顯示路由。

## 編輯器使用與可編輯來源

- 護甲下拉選單：`Chinese Leather Armor 01 / 中式皮甲`。
- 頭盔下拉選單：`Mingguang Helmet 01 / 明光盔`。
- 正式輸出：`assets/characters/human/q35/standard_anime_{male,female}_character_pack.{blend,glb,json}`。
- 新部件可編輯来源：`assets/characters/human/q35/chinese_leather_mingguang/chinese_gear_{male,female}.blend`，含打包貼圖；不需要改動原始素體。
- 男女 builder 以 `load_authored_chinese_gear.py` 追加新部件，保留既有 helper／骨架／部件列表。皮革新前綴保留 PBR 貼圖；其他舊裝備的渲染路徑不变。
- 明光盔沿用頭部骨骼，白纓有兩個輕量形態通道，合併至發布動作；四款髮型使用此頭盔專用的盔沿裁切模式，卸盔恢復。

## 本次實測

| 項目 | 結果與範圍 |
| --- | --- |
| Blender 灰模與貼合 | 男女按自身骨架／截面建立；修正女胸穿出、肩前缺口與行走裙片上段權重。正／背／側／3⁄4 已檢查。 |
| 載入掛接 | `chinese_gear_loader_test.py` 男女 PASS、EXIT=0；追加 46 個皮甲網格及 22 個頭盔網格；檢查 UV、權重、Armature 指向與白纓 NLA。未重跑所有舊部件的整包生成。 |
| 資產保留 | `validate_chinese_leather_mingguang.py --final` PASS、EXIT=0；原網格頂點屬性／索引、骨架 inverse bind 與原動畫 channels 的取樣數值比對，無差異項目。原始動畫數男 43、女 41，不等於本次目視驗收數。 |
| 正式編輯器 | Godot 4.6.2 Mono，visual 模式，直接由正式 GLB 路徑載入。最後一輪男女 PASS、EXIT=0，分別 18.333／18.310 秒，硬上限 150 秒。 |
| 選項與材質 | 新部件→無→舊部件→新部件的顯示断言通過；實際材質為 StandardMaterial3D，帶 UV 樣片和皮革貼圖已看圖確認。 |
| 動畫 | 男女各 `idle / walk / run / guard / attack_axe / attack_jump_heavy / ride_slash`，每項 16 幀，共 224 張原始動作圖、14 份完整 contact sheet 和 14 個 GIF。已逐張檢查輪廓與關節區；另斷言各動作白纓形態值確實變化。 |
| 組合 | 男女各四種髮型、卸盔恢復、皮甲單件、頭盔單件，以及新皮甲＋明光盔＋原中式披風／皮靴／劍盾在 idle/run/guard 的前後斜視圖。未涵蓋任意裝備的全排列。 |

正式驗證紀錄：`.godot-temp/godot_verify/20260910_075955_246/result.json`（男）、`20260910_080050_435/result.json`（女）。最後修正僅將髮型近景改為中性姿態，避免待機歪頭裁切；模型內容不變。唯一已知環境訊息為根憑證讀取警告，退出碼仍為 0，無 SCRIPT ERROR、assertion 或逾時。Blender 最後製作／匯出紀錄在 `.godot-temp/chinese_equipment_runs/20260910_074812/`，各階段 EXIT=0。

## 最新圖像與動畫

所有原始編輯器圖為 1024×1280，均晚於正式來源輸出；未用 Blender 圖代替正式編輯器證據。GIF 時長按匯入動作時間產生，並非 FPS 效能測量。

- 總覽：`.visual_captures/chinese_leather_mingguang/final_overview.jpg`。
- 男女多角度：同目錄 `male_views.jpg`、`female_views.jpg`；細節為 `male_details.jpg`、`female_details.jpg`。
- 髮型與組合：`{male,female}_hair.jpg`、`{male,female}_combinations.jpg`。
- 動畫：`{male,female}_{idle,walk,run,guard,attack_axe,attack_jump_heavy,ride_slash}.gif`。
- 完整逐幀表：對應動畫檔名加 `_sheet.jpg`；原圖為 `_00.png` 至 `_15.png`。
- 完整編輯器畫面：`male_editor_selected.png`、`female_editor_selected.png`。遊戲尺度另存 `_gameplay_scale.png`，未修改共享投影尺度。

## 品質界線與限制

- 這是適配既有動漫素體的風格化版本。獸面與雲紋有幾何浮雕，但未逐筆複製參考圖的寫實高密度雕刻；不是一比一寫實復刻。
- 裙甲是獨立分片，抬腿、蹲姿及騎乘時會展開，露出原內衣／大腿；沒有添加長褲遮掩。不同於皮膚穿過封閉胸甲，這是目前開片結構的可見限制。
- 白纓有烘入動作的輕微擺動，不是即時布料／毛髮物理。未證明全動作、全組合與所有插值時間完全零穿模。
- 目前每性別新皮甲 50,266 三角面、頭盔 38,480 三角面。鏤空孔洞和纖維使用實際幾何；這是編輯器細節版，未製作低模 LOD，也未測多人戰場效能。參考圖標示的 12,348 面不是此輸出的面數。
- 本次不更改原始姿態設計、舊皮靴、盾牌背負或披風的歷史外觀問題。

## 重建與修改

`author_chinese_leather_mingguang.py -- --sex male --stage export` 只匯出已編輯的來源到候選檔；female 對應。`gray`／`detail` 會明確重建該階段，不應在手工修模後當作一般匯出。保留本次 scoped baseline，供來源重建與保留比對使用。

可用 `scripts/tests/run_chinese_equipment_stages.py --sex male export` 執行 180 秒上限的 Blender 階段並保存日誌。候選檔通過檢查後再發布至正式男女包，最後執行 Godot `capture_chinese_leather_mingguang.gd -- male final`（female 對應）並重新檢查圖像。

## 執行限制

目前未提供專案規定的 `schedule` 工具。使用者已同意此次使用硬性逾時與持續檢查，並要求改進 `worldgoing-3d-equipment`。技能已改為能力檢查與有界執行，不再把固定工具名稱當成所有環境必備；保留上層專案规则及已取得授權的界線。

原先問題是把固定工具名稱直接寫成通用必備條件，卻未驗證當前工具是否提供，也沒有明確的替代流程。現在先確認可用能力，保存實際工作 ID、套用硬性逾時、持續檢查；如上層規則要求指定工具而不可用，先取得一次替代授權並在同任務沿用。已更新 SKILL.md 和 pipeline 參考，未修改上層 AGENTS.md；技能格式檢查通過。

所有變更保留在工作樹，不建立 commit，不刪除其他工作資料。
