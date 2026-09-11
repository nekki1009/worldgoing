# 形變網格 UV／切線匯入修復

2026-09-10，接續「續修錯誤」。先前 `UVs are required to generate tangents.` 已消除；沒有關閉切線生成、刪除形變或替換法線貼圖材質。

## 原因與修正

Godot 4.6.2 的 glTF 匯入對基礎表面有 UV 檢查，但形變分支仍會對缺少 UV 的表面呼叫切線生成。這與本次資產及日誌相符：每個角色包的旅行披風 600、白纓五個表面各 2、弓弦 3，共 613 次；前次重匯入男女兩個候選包，共 1,226 次。[Godot 4.6.2 glTF 匯入原始碼](https://github.com/godotengine/godot/blob/4.6.2-stable/modules/gltf/gltf_document.cpp#L1631-L1800)

只對沒有貼圖、沒有 UV 的形變網格增加連續投影 UV：

- 男女：`Cape_Travel_01_Main`、`Helmet_Mingguang_01_WhitePlume_Fittings`、`Weapon_Bow_01_String`。
- 馬匹：`Mount_Stirrups_01_L/R`。
- 正式三包及同源候選／重建包，共 **13 個 GLB、82 個材質表面**。完整清單與新 SHA-256 在 `.godot-temp/morph_uv_repair/glb_report.json`。
- 正式男女及馬匹 `.blend` 同步補 UV。歷史候選 `.blend` 保持原樣；會輸出上述問題網格的完整 builder、全模型修復與關節／護腕局部重建入口均已接入同一 helper。

依最小修改原則，GLB 只追加 `TEXCOORD_0` accessor／buffer view／資料；每個原始二進位位元組與其他 JSON 欄位均比對保留。沒有重排頂點、三角面、權重、骨架、材質、貼圖或動畫。`meshes/ensure_tangents=true` 保留，沒有新增匯入外掛或改引擎。

這是純色形變表面的匯入相容修補，不是貼圖用美術 UV atlas；日後要給這些部件繪製貼圖，仍需正式展 UV。既有幾何（包括披風基準姿態的退化封邊）未在本輪重做。

## 驗證

全部 Godot 驗證使用 `C:/Users/Nekki/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64_console.exe`，日誌確認為 **4.6.2.stable.mono.official.71f334935**。經 `godot-runtime-verify` 的限時執行器保留真實退出码、錯誤與輸出時間；GPU 圖使用 D3D12／Forward+、RTX 5060。没有更換使用者正在開啟的其他 Godot 程序。

| 驗證 | 結果 | 秒 | `.godot-temp/godot_verify/` 紀錄 |
|---|---|---:|---|
| 專案 editor 掃描，完成初始化後退出 | PASS、EXIT=0 | 12.356 | `20260910_220405_141` |
| 正式三包原生匯入資源／切線／形變 | PASS、EXIT=0 | 1.362 | `20260910_220921_071` |
| 男女前後四視圖及指定動作截圖 | PASS、EXIT=0 | 18.183 | `20260910_220752_874` |
| 完整角色編輯器功能回歸 | PASS、EXIT=0 | 10.652 | `20260910_220533_993` |

原生資源檢查使用 `load(GLB)` 的 `PackedScene`，不是角色編輯器的直接 `GLTFDocument` 路徑：男 78、女 75 個法線貼圖表面仍有貼圖、完整切線陣列、有限值與單位長度；新增 UV 的表面、613＋613＋12 組形變及其切線也存在。**不宣稱所有切線均通過嚴格正交品質檢查。**

`repair_morph_uv_assets.py` 的 13 包逐位元保留、精確 JSON 差異與重複執行檢查通過。`validate_model_audit_repairs.py --final --with-joint-refinement --with-lining-armor-fit` 的既有全模型→關節→護腕／襯衣連鎖檢查也通過；只容許本輪經公式驗證的 UV 追加，沒有放寬其他網格保留條件。正式動畫數仍為男 43、女 41、馬 4。

Blender 4.2.22 正式三個可編輯來源的 UV 補齊／局部匯出退出 0；補 UV 前後的頂點、法線、三角面、權重與全部形變數值摘要相同。來源再匯出的 7＋7＋4 個表面，其位置、權重與正式 GLB 一致；UV 最大差為女包 `2.98e-8`，男／馬為 0。完整 builder 僅語法檢查及呼叫位置核對，沒有從原始 VRM 重跑整包。

## 外觀保留

最新 `.visual_captures/morph_uv_repair/` 含 28 張 1024×1280 原始 PNG：男女 × 前後版本 × 正／側／背／斜前，以及 `run / attack_bow / ride_idle` 中點。前版讀取本輪備份，後版讀正式 GLB；兩者均走現有角色編輯器與換裝路由。

已逐組檢視四張比較板，核對白纓、披風、弓弦、人物輪廓與馬鐙。14 組配對每組有 0～12 個不同像素，見 `pixel_comparison.json`；不是全部逐位元相同，也不是全部動作／所有插值時點的零穿模認證。比較板只排列原圖，沒有修飾截圖。

![男角色修補前後四視圖](<C:/Users/Nekki/Dropbox/竹北社大/(01)102-103學員資料/share/worldgoing/.visual_captures/morph_uv_repair/male_neutral_comparison.jpg>)

![女角色修補前後動作取樣](<C:/Users/Nekki/Dropbox/竹北社大/(01)102-103學員資料/share/worldgoing/.visual_captures/morph_uv_repair/female_motion_comparison.jpg>)

## 中途失敗紀錄與界線

- `20260910_215755_002` 的整批 `--headless --editor --import` 實際完成包含修正 GLB 的重新匯入，**UV 錯誤為 0**，但 106.363 秒退出時出現 `EditorSettings not instantiated yet ... export/android/android_sdk_path`，所以保持 FAIL，沒有因 EXIT=0 改判。後續改為讓 editor 跑完 300 次迭代、上限 60 FPS，掃描通過；不宣稱已修改／根治引擎退出競態。
- 新測試曾有型別推導錯誤（`220138_649`），補明確型別後通過。額外嚴格的切線／法線正交斷言失敗並於 90 秒被停止（`220602_482`），不算通過證據；保留本次相關的數量、有限值、單位長度及資料保留契約，並加入測試內部 10 秒失敗退出保護。沒有據此重做既有帶貼圖網格。
- 第一版靜態比較沿用上一段動作殘留的披風形變；最終截圖在中性姿態明確清零形變後重拍。只有 `220752_874` 的結果作最終比較依據。
- 根憑證讀取訊息獨立保留為環境雜訊。editor 掃描不是遊戲流程驗收；其他人正在修改的地形／軍隊等系統不屬本輪。

## 重現與復原

- 匯入掃描：`verify_godot.ps1 -Mode headless -GodotArguments @('--editor','--quit-after','300','--max-fps','60') -TimeoutSeconds 120`。
- 原生資源：同 runner、`-Mode headless -GodotArguments @('--script','res://scripts/tests/morph_uv_import_test.gd') -TimeoutSeconds 30`。
- 前後截圖：同 runner、`-Mode visual -GodotArguments @('--script','res://scripts/tests/capture_morph_uv_repair.gd') -TimeoutSeconds 90`。
- GLB 保留檢查：bundled Python 執行 `scripts/tests/repair_morph_uv_assets.py`；不帶 `--apply` 不發布修補。
- 本輪精確原檔備份：`.godot-temp/morph_uv_repair/baseline/`，保留原 `assets/...` 路徑。三個正式 `.blend` 與 13 個 GLB 均可復原；不要誤用更早的備份倒退關節／護腕修正。

正式 `.blend` 新 SHA-256：男 `487FDE517110C9CF47CC29E493403A5298B5BA65547B41D3936B64A3B456A378`；女 `D1A0B3EA597B97C09C8EC3701130CFCD9FF4D0EB610D1651F4E21E1DC4BA89DC`；馬 `1526272DE111633514651897B93BF65F9246C9FDF8163BCD63C8BEE0D497E0EC`。

依裝備技能保留共享模型來源，依最小修改技能沿用既有 builder，依執行驗證技能區分匯入、功能與看圖證據。未 Git 提交，沒有刪除素材或清空快取，保留其他工作樹修改。
