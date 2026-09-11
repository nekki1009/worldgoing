# 中式皮靴交付 — 2026-09-10

已新增男女各一套可選中式皮靴，未替換舊皮靴、鐵靴或明光戰靴。依裝備技能採用男女各自的腳／小腿表面量測、同側原生權重轉移與既有骨架載入流程，沒有改身體比例或另建骨架。

## 使用與素材

- 角色編輯器：`scenes/ui/HumanCharacter3DEditor.tscn` → **Boots / 鞋靴 → Chinese Leather Boots 01 / 中式皮靴**。
- 選項 ID：`boots_chinese_leather_01`；網格前綴：`Boots_Chinese_Leather_01_`。
- 設計：高筒栗棕皮革、深色靴口、鞋頭／後跟補強、低跟鞋底、斜踝帶、外側四瓣盤扣及垂繩、後接縫與靴口細邊。
- 參考圖與原始提示：`assets/characters/human/q35/chinese_leather_boots/reference/`。
- 可編輯來源：同目錄上一層的 `chinese_leather_boots_male.blend`、`chinese_leather_boots_female.blend`；來源包含既有角色包與新靴。
- 正式輸出：`assets/characters/human/q35/standard_anime_{male,female}_character_pack.{blend,glb,json}`，共 6 個正式檔已更新。
- 每性別 32 個新網格；男 28,436、女 28,224 三角面。這是編輯器美術版本，尚未做 LOD 或大量角色效能驗收。

## 可重建範圍

男女既有 builder 透過 `load_authored_chinese_leather_boots.py` 載入新靴並加入既有輸出清單，不會日常重造美術。

明確美術入口為 `scripts/tools/blender/author_chinese_leather_boots.py`：

- `gray`：依本次不可變基準重建大形，會重造新靴。
- `detail`：保留 Main/Cuff/Sole/Heel，重建裝飾並轉移同側權重。手動修過裝飾後不要執行。
- `probe`：重套同側權重及低跟接縫修正並匯出；不是唯讀檢查。
- `export`：從可編輯來源匯出，不重建幾何或權重。
- `preview`：只拍 Blender 四視圖。

有界入口：`python scripts/tests/run_chinese_equipment_stages.py --leather-boots --sex male export`，female 對應。每階段有 180 秒子程序逾時與獨立日誌。

正式發布前比對全部六個正式檔與 `.godot-temp/chinese_leather_boots_baseline_20260910`，再逐檔複製與 SHA-256 核對。記錄在素材目錄的 `publication.json`；原基準可恢復。發布腳本刻意不能直接重跑覆蓋已改變的正式包。

## 驗證證據

| 項目 | 結果與範圍 |
|---|---|
| 正式 GLB 比對 | `validate_chinese_leather_boots.py --final` PASS / exit 0；既有節點變換、mesh attributes／indices、骨架 inverse bind、所有原動畫 channels、所有原 morph targets 與材質圖片保持一致。男保留 43、女保留 41 個 raw clips；這不是逐一視覺驗收的動作數。 |
| 可重建載入 | `chinese_leather_boots_loader_test.py` 男／女 PASS / Blender exit 0；32 個部件、同一 Armature、UV、權重正規化、禁止左右腿交叉權重。沒有重新建置整套舊人物美術。 |
| 正式 editor 匯入 | Godot 4.6.2 Mono，exit 0，5.328 秒；`.godot-temp/godot_verify/20260910_123322_712/result.json`。 |
| 正式男 visual | exit 0，16.209 秒；`.godot-temp/godot_verify/20260910_123341_575/result.json`。 |
| 正式女 visual | exit 0，15.721 秒；`.godot-temp/godot_verify/20260910_123433_471/result.json`。 |
| 選項與材質 | 實際新網格存在；新靴 → 無 → 舊皮靴 → 新靴可切換；皮革材質在 Godot 保留 UV 圖片。 |
| 四視圖與動畫 | 已親自檢查男女正式正／側／背／3⁄4 圖及六種動作的各 16 幀：idle、walk、run、attack_axe、attack_jump_heavy、ride_slash。修正初版左右腿誤綁造成的拉裂，最新序列未見該問題。 |
| 組合 | 中式皮甲在跑步 0.22 秒、35°／145°抽樣未見新靴穿破。舊冒險長褲的男性組合仍有局部褲面穿出靴筒，未通過全部組合相容。 |

Godot 執行檔：`C:/Users/Nekki/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64_console.exe`。

視覺測試指令形狀：`verify_godot.ps1 -ProjectPath <專案根> -GodotExecutable <上述執行檔> -Mode visual -GodotArguments @('--script','res://scripts/tests/capture_chinese_leather_boots.gd','--','male','final') -TimeoutSeconds 120`，female 對應。日誌只有已知 root certificate store 環境訊息，沒有 script／parse／assertion 錯誤。

早期錯誤有保留：系統 Python 缺少 numpy，改用 Blender bundled Python 後資產檢查通過；Python 檢查曾誤包含 GDScript，分開檢查後 Python 編譯與 Godot 實際執行均通過。這些不計作原先的成功驗證。

## 最新預覽與限制

`.visual_captures/chinese_leather_boots/`：`boots_overview.jpg`、`male_views.jpg`、`female_views.jpg`、每性別六種動作的 `*_sheet.jpg`／`*.gif`、`*_combinations.jpg`。原始 PNG 為 1024×1280，引擎直接輸出；總覽只作排列、縮放、透明背景襯底，沒有修掉瑕疵。預覽晚於正式 GLB。GIF 使用實際動畫時長，run 0.875 秒／15 間隔，依 GIF 的 10ms 精度量化。

未宣稱全動作、所有視角、全部裝備、地面接觸／IK 或多人效能通過。跳躍與騎乘為全身序列抽樣，不是每個踝關節角度的微距掃描；初版過窄鏡頭已放寬，最新跑步可看完整雙靴。模型未逐一還原參考的皺褶、雙排縫線與多層鞋底紋理。舊衣物本身的缺口不屬於這次靴子修正。

沒有 Git stage／commit；其他既有工作樹變更保留。
