# 中式皮盔交付（2026-09-10）

## 使用與來源

- 角色編輯器 `scenes/ui/HumanCharacter3DEditor.tscn` → Helmet → `Chinese Leather Helmet 01 / 中式皮盔`（`helmet_chinese_leather_01`）。男女均可選，保留原皮盔、鐵盔、明光盔與「無」。
- 依使用者參考製作分瓣皮革盔頂、交叉加固帶、鉚釘、額前獸面、側護頰／後頸護片、雲紋與下巴繫帶。使用原骨架，未改身體、臉與髮型來源網格；戴盔時依覆蓋範圍遮髮，卸下恢復。
- 參考：`assets/characters/human/q35/chinese_leather_helmet/reference/user_leather_helmet.png`。
- 可編輯來源：同目錄 `leather_helmet_male.blend`、`leather_helmet_female.blend`。內含原角色以保留匯出內容；新部件前綴 `Helmet_Chinese_Leather_01_`。
- 正式輸出：`assets/characters/human/q35/standard_anime_{male,female}_character_pack.{blend,glb,json}`。
- 1024² 皮革顏色、法線、粗糙度貼圖保留原生 PBR 路由，未改全角色渲染風格。

## 重建與保留

男女 builder 已呼叫 `load_authored_chinese_leather_helmet.py`，載入可編輯來源，不重建美術細節。顯式匯出入口為 `scripts/tests/run_chinese_equipment_stages.py --leather-helmet --sex both export`（Blender 每階段硬逾時 180 秒）。`gray/detail` 會重建幾何，手工修模後不要執行。

正式發布前逐一核對六個正式檔與本次備份雜湊一致，才複製候選；備份保留於 `.godot-temp/chinese_leather_helmet_baseline_20260910`。未暫存或提交 Git，其他既有修改保留。

## 驗證範圍

| 項目 | 結果與證據 |
| --- | --- |
| 匯出／資料保留 | `validate_chinese_leather_helmet.py --final` PASS；既有幾何、UV、權重、骨架、動畫 channels 數值及材質／貼圖位元組比對通過。報告在資產目錄 `validation.json`。 |
| 可重用來源 | 男女 loader 測試 PASS，各載入 52 個皮盔網格。 |
| 功能 | 正式模型 Godot visual capture 檢查新／舊選項與無的切換、真實網格可見性、來源貼圖及四種髮型。 |
| 輪廓／材質 | 親自檢查男女中性正／背／側／3⁄4、頂視與近景；可辨識分瓣、包邊、護片、獸面與皮紋。 |
| 動作 | 男女 idle、walk、run、guard、attack_axe、attack_jump_heavy、ride_slash；每動作 16 個時間點，全身及頭部各一組，共 448 張動畫圖；已檢查逐幀接觸表。 |
| 組合 | 皮盔單件、皮甲、完整裝備與披風的指定 idle/run/guard 角度。未見此次皮盔的明顯脫頭、破面或穿出頭髮。 |

Godot 使用 `C:/Users/Nekki/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64_console.exe`，有界 runner 的 visual 模式、150 秒上限；參數 `--script res://scripts/tests/capture_chinese_leather_helmet.gd -- male final`（female 對應）。正式男版 PASS / EXIT=0 / 49.331 秒，結果 `.godot-temp/godot_verify/20260910_091534_578/result.json`；女版 PASS / EXIT=0 / 47.706 秒，結果 `.godot-temp/godot_verify/20260910_091643_282/result.json`。兩者無腳本錯誤或缺圖。根憑證讀取訊息另列環境噪音，不算視覺證據。

## 預覽與限制

最新實際 Godot 畫面位於 `.visual_captures/chinese_leather_helmet/`：`final_overview.jpg`、男女 `helmet_views.jpg` / `views.jpg` / `combinations.jpg`、每動作全身與 `head_` 近景 GIF、原始 PNG 與逐幀表。GIF 是原始渲染幀組合，沒有生成式修圖。

- 這是配合既有動漫素體的風格化版本，不是參考圖精雕的一比一複製；獸面與雲紋有簡化。
- 皮盔男 34,501、女 34,473 三角面，尚未製作 LOD／低模烘焙；不是參考圖標示的 8K 三角面，也未做大軍效能驗證。
- 動作與組合驗收限上述取樣，並非所有動作連續碰撞或全組合零穿模保證。舊皮甲動作時內衣可見的現象未在本次修改。
