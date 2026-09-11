# 甲內襯衣與中式披風跑步修正

交付日期：2026-09-10。正式男女模型包已更新；未提交 Git。功能與資料保留檢查通過，近距離細節／全裝備組合尚非完整零穿模驗收。

## 使用方式與改動

- 3D 角色編輯器 → `Outfit / 內衣` → `Chinese Lining 01 / 甲內襯衣`，ID `outfit_chinese_lining_01`。男女分別建模，保留舊內衣與「無」。
- 造型為米白薄亞麻長袖、灰藍交領包邊、收口袖與及髖短襬，另附原內褲形狀的獨立副本；不改原身體、五官、髮型或舊內衣。新女裝不再重複疊穿一件底衫。
- 穿甲時僅新襯衣切換 `UnderArmor` 收合形態，並隱藏被護甲覆蓋的交領、後領邊與下襬邊條；卸甲恢復。身體沒有縮小或刪除。
- `Cape / 披風` → 既有 `cape_chinese_01`。原跑步下襬使用按高度、隨腿部包絡投影的修形，造成下方被局部撑寬與 S 形彎折；現在改為由肩頸承重的連續後揚布面，修正內外層間距。男、女使用不同後揚幅度，留出後踢腳的空間。
- 只改既有主披風 `run_00` 至 `run_12` 共 13 個修形。Basis、網格拓撲、其餘修形、原動畫時間軌與材質保留。沒有增加骨架或即時布料物理系統。

## 輸出

以下路徑均相對專案根目錄 `C:/Users/Nekki/Dropbox/竹北社大/(01)102-103學員資料/share/worldgoing`。

- 正式包：`assets/characters/human/q35/standard_anime_{male,female}_character_pack.{blend,glb,json}`。
- 內襯可編輯来源：`assets/characters/human/q35/chinese_lining/chinese_lining_{male,female}.blend`。
- 披風可編輯來源：`assets/characters/human/q35/chinese_cloak/chinese_cloak_{male,female}.blend`，從原專用來源移入上述 13 個修形，未以其他整包取代。
- 參考圖：`assets/characters/human/q35/chinese_lining/reference/lining_concept.png`。
- 原始引擎截圖、四視圖、逐幀接觸表與 GIF：`.visual_captures/lining_cloak/`。正式披風序列使用 `male_final_*`、`female_final_*`；內襯使用 `*_lining_*`。
- 素材比對紀錄：`assets/characters/human/q35/chinese_lining/validation.json`。
- 修改前的八個正式檔備份：`.godot-temp/lining_cloak_baseline_20260910/`。更新前核對全部目標與備份雜湊相同，更新後核對正式檔與候選檔相同。

新男裝共 13 個網格、17,823 三角面；女裝共 10 個網格、20,973 三角面。含短褲與包邊；未製作 LOD 或量測多人效能。1024×1024 布紋顏色／粗糙度貼圖隨 GLB 匯出，Godot 實際讀取來源 PBR 材質。

## 驗證結果與界線

| 項目 | 結果與實測範圍 |
| --- | --- |
| 匯出與正式資料保留 | PASS。男女 Blender 匯出 exit 0；正式 GLB 比對無非目標網格、UV、權重、原骨骼／inverse-bind、舊動畫 channel 數值或材質差異；唯一舊資產差異為各 13 個主披風跑步修形。原材質男 82、女 79 個均保留。 |
| 原動作資料 | 男 43、女 41 個 raw clips 保留。此數字不是本次視覺驗收或編輯器公開動作數。 |
| 可編輯來源重載 | PASS。`lining_cloak_loader_test.py --with-cloak` 從正式內襯／披風來源附加到原骨架，檢查權重正規化、UV、父節點、Armature、UnderArmor、披風 revision 2 與 337 個含 Basis 的形態；exit 0。 |
| 編輯器功能 | PASS。男女新內衣→無→舊內衣→新內衣切換；穿甲收合及卸甲還原；來源貼圖存在；披風即時播放、暫停不變、重設一致、跨循環與卸下／重穿。 |
| 輪廓與材質 | 已親看男女正／背／側／3⁄4、領部近景與 UI 選中截圖。保留薄長袖與交領主輪廓；參考中的小腰繫帶未建，女短褲沿用基準斜腿口。 |
| 內襯動作 | 已拍攝並檢視男女各 6 段：idle、walk、run、attack_axe、attack_jump_heavy、ride_slash，每段 16 個時間點；包含抬臂、跨步、跳躍及騎乘。GIF 依實際片段時長播放。 |
| 披風跑步下襬 | 男女各 25 個時間點 × 正面斜角／側面／背面，合計 150 張。已親看序列與抬腳極值，未再觀察到原下襬被局部拉扯鼓起、S 形折彎或後踢腳穿過後襬中央的現象。 |
| 裝備組合 | 已測舊皮甲、中式皮甲、鐵甲、明光鎧，男女各前斜角與後斜角、run 0.2 秒。只驗證這些時間點；不是四套盔甲全部動作的完整驗收。 |

仍有的視覺限制：單穿襯衣的袖根在近距離可見零星皮膚細點；舊皮甲肩緣仍有少量布面交疊。舊甲的腿部／裙甲鋸齒與接縫沒有在本次重製。披風上肩與非跑步動作沿用原資產，未宣稱全動作、全視角、全組合零穿模。

正式 Godot 驗證使用 `Godot_v4.6.2-stable_mono_win64_console.exe`，來源 `C:/Users/Nekki/Godot_v4.6.2-stable_mono_win64/`。入口為 `C:/Users/Nekki/.codex/skills/godot-runtime-verify/scripts/verify_godot.ps1`，`-Mode visual -GodotArguments @('--script','res://scripts/tests/capture_lining_cloak.gd','--','male','final') -TimeoutSeconds 150`，female 對應。

- 男：PASS / exit 0 / 22.898 秒；`.godot-temp/godot_verify/20260910_102519_152/result.json`。
- 女：PASS / exit 0 / 23.163 秒；`.godot-temp/godot_verify/20260910_102556_088/result.json`。
- 記錄只有已知根憑證讀取訊息，沒有 script/parse/assertion/timeout。這是角色編輯器聚焦驗證，不是整個遊戲或多人戰場測試。
- Blender 來源附加完整日誌：`.godot-temp/lining_cloak_loader_final.log`。

中途修正過两個檢查／入口問題：獨立啟動披風来源轉移程式時缺少模組搜尋路徑；移除新女裝重複底衫後，沿用的盔甲驗證器仍要求超過 10 個網格。已分別補正入口，並以新衣物精確部件清單與 13／10 數量驗證，未略過任何舊資料保留檢查。先前的失敗日誌仍保留，未當作通過。

## 可重建入口

男女正式 builder 已接入 `load_authored_chinese_lining.py`，只附加新前綴 `Outfit_Chinese_Lining_01_`，沿用原 Armature；披風仍由既有 `load_authored_chinese_cape.py` 附加與绑定原動作。

`author_chinese_lining.py --sex male --stage export`（female 對應）只匯出可編輯來源，輸出候選包，不自動覆蓋正式包。`gray` 從本次備份重新生成衣物與跑步修形；`detail` 更新穿甲收合和材質，會覆蓋這些美術細節，手動修模後不要誤跑。正常執行使用已有每階段 180 秒硬逾時的 `scripts/tests/run_chinese_equipment_stages.py --lining --sex both export`。

`repair_chinese_cloak_run.py` 的獨立入口只將候選來源中的 13 個跑步修形轉入舊披風專用來源，產生 `chinese_lining/chinese_cloak_{male,female}.blend` 候選；不直接發布。候選通過後才按明確檔案清單更新正式檔。來源保存使用唯一暫存檔再複製，以避免 Dropbox 的舊檔更名鎖定。

## 自行生成的參考圖與提示

使用內建 ImageGen 生成，非 CLI／API fallback；圖片已保存至上列專案 reference 路徑。以下為實際完整提示。此圖僅為設計參考，3D 模型、貼圖與 Godot 截圖均是另外製作／實際渲染，驗收圖片未用生成式工具修補。

> Use case: stylized-concept. Asset type: 3D game modeling reference sheet, Chinese-inspired thin under-armor lining shirt, not armor. Plain warm gray studio background, restrained production character costume concept. Show exactly the same practical garment on neutral adult male and female mannequins, each in front, side, back orthographic views, arms slightly apart, no faces needed. The garment is a close-fitting lightweight ecru unbleached linen long-sleeved under-shirt with narrow crossed lapel and modest V neckline, thin muted slate blue gray bindings at collar and wrists, subtle woven texture and sparse seams, short hem to upper hip to tuck beneath armor, no bulky padding, no skirt, no straps or metallic fittings. Sleeves taper cleanly to wrist; understated cloth tie at side waist, practical enough under the existing leather cuirass. Both mannequins wear plain matching modest fitted shorts as neutral coverage, feet visible. Preserve consistent garment construction across all six views. Small inset fabric weave / collar seam detail. Stylized clean 3D render visual, high enough detail to model silhouettes, light soft shadows. No weapons, no armor, no cloak, no hats, no long coat, no transparency, no lingerie, no decorative embroidery, no exaggerated anatomy. No claims of verified topology, no labels other than simple FRONT SIDE BACK.
