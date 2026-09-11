# 男女素體手肘／手腕局部修正

2026-09-10。使用者同意局部調整關節，仍保留體型比例、既有骨架及其他部件。

## 已交付

正式男女 `.blend`、`.glb` 已更新；選項與 JSON 清單不變。只在左右肘部／腕部增加細分，改善蒙皮權重過渡，未移動原有身體頂點、未改骨架或任何動畫。

| 身體網格 | 原三角面 | 修正後 | 原頂點位置／Rest 表面 |
|---|---:|---:|---|
| 男 Body_Standard_Male | 7,340 | 11,192 | 原頂點全保留；新頂點落在原表面，最大浮點誤差 0.000000139 m |
| 男 Body_Standard_Male_Full | 7,340 | 11,192 | 同上；編輯器切換「無」時可正常顯示 |
| 女 Body_Standard_Female | 8,644 | 12,712 | 原頂點全保留；最大表面誤差 0.000000138 m |

男角 446 個、女角 442 個非身體網格，全部材質／貼圖、骨架、43／41 個動畫均維持本輪開始時的 GLB 原資料與二進位內容。身體非關節區域權重／UV 保留；原法線經 Blender 量化回存的最大差約 0.023 度，不是重新平滑全身。沒有新增骨骼、即時變形節點或平行動畫系統。

## 實際驗證

- Blender 4.2.22，兩性候選建置退出碼 0；原表面距離檢查通過，同一 helper 重複呼叫不會再次細分。男女來源分別有 43／59 張內嵌貼圖，所有檔案型圖像均無未內嵌連結，正式 `.blend` 搬回原目錄不依賴候選相對路徑。
- `validate_body_joint_refinement.py --final` 通過：正式檔局部幾何、原頂點、UV、非局部權重、原非身體資料逐項檢查。
- `validate_model_audit_repairs.py --final --with-joint-refinement` 通過：原全模型修復檢查加上本次明確授權的身體例外及獨立驗證。馬匹檔案未改動。
- Godot 4.6.2 Mono／NVIDIA RTX 5060。正式檔 editor 重匯入退出碼 0，5.324 秒；男女 visual 分別退出碼 0、30.745／31.368 秒。使用 `godot-runtime-verify/scripts/verify_godot.ps1`，`-Mode visual -GodotArguments @('--script','res://scripts/tests/capture_body_joint_refinement.gd','--','male或female','final') -TimeoutSeconds 120`。
- 四視圖、左右肘 0／45／90／135 度、腕 -55／0／55 度；六個動作 `run/guard/attack_bow/attack_crossbow/attack_spear/attack_hammer` 各掃描 61 個時點尋找彎曲極值，另保存 16 幀完整週期取樣。腕角以手腕到中指根部方向量測，不等同臨床關節活動角度。
- 兩種內層 × 五種護甲狀態（無、皮革輕甲、鐵甲、明光鎧、中式皮甲）× 六動作 × 三取樣幀，兩性合計 360 張組合圖。這是指定取樣的新增問題檢查，不是全組合穿模認證。
- 正式原圖為 1024×1024，每性別 318 張。關節極值近景暫時隱藏臉／髮網格以排除遮擋，拍完立即恢復；一般四視圖與動作週期保留完整頭部。GIF 是 16 幀檢視用取樣，非遊戲原生幀率。
- 第一次測試把中式內襯 ID 寫錯，導致 assertion 並由 120 秒上限終止，列為失敗。修正測試後的執行皆另有新紀錄；未將失敗算作通過。正式成功紀錄只含既知根憑證環境訊息，無 SCRIPT ERROR／assertion／逾時。

正式重匯入／截圖紀錄：`.godot-temp/godot_verify/20260910_192433_043/`、`20260910_192446_448/`、`20260910_192606_285/`。

近景另修正「旋轉相機會恢復髮型可見性」的測試拍攝順序，男女聚焦重拍在 `20260910_192915_218/`／`20260910_192946_438/`，退出碼均為 0，11.600／12.438 秒；新增斷言確認近景不受臉／髮遮擋。只改測試的臨時顯示，正式角色材質與髮型沒有修改。

## 視覺結果與限制

135 度屈肘原本突出的折角已變成較圓順的外緣；正、反屈腕過渡改善，保留原有低面數手掌／手指風格。指定畫面未見此次關節修正新增的肘／腕穿出。沒有重新設計握姿或手指解剖。

**當時遺留的中式襯衣 × 鐵甲／明光鎧袖面交疊，已依後續指示接續修復。** 原尺寸圖 `baseline/male_outfit_chinese_lining_01_armor_mingguang_01_attack_bow_1.png` 保留作歷史問題證據。本報告只記錄當時的身體關節修正；後續護腕幾何、襯衣修形、換裝覆蓋及最新實測見 [LINING_ARMOR_OVERLAP_REPAIR_2026-09-10.md](LINING_ARMOR_OVERLAP_REPAIR_2026-09-10.md)，不可把本報告的舊圖當成新裝備驗收。

未窮舉所有動畫、插值時點、視角、披風／盔／靴組合，未做連續網格碰撞求解或多人效能量測。男女既有 builder 已接入 helper，語法檢查通過；本輪實跑的是局部來源重建／匯出，沒有再從頭重建全部裝備。

## 檔案與復原

入口：`scripts/tools/blender/refine_body_joints.py`，由男女 `build_standard_anime_*_character_pack.py` 在既有裝備修復之後、匯出之前呼叫。局部候選重建：Blender `--background --python-exit-code 1 --python scripts/tests/build_body_joint_candidate.py -- male或female`，外層需硬性逾時及持續追蹤。

正式資產：`assets/characters/human/q35/standard_anime_{male,female}_character_pack.{blend,glb}`。候選保留在 `assets/characters/human/q35/joint_refinement/`；本輪開始時的六個正式檔備份在 `.godot-temp/joint_refinement/baseline/`。不要以更早的全模型修復備份重建而倒退其他美術修正。

最新圖與 GIF：`.visual_captures/body_joint_refinement/final/`，對照／週期圖在 `boards/`。本輪沒有 Git 提交，未處理其他工作樹修改，沒有刪除素材或快取。

![男女關節修正前後](<C:/Users/Nekki/Dropbox/竹北社大/(01)102-103學員資料/share/worldgoing/.visual_captures/body_joint_refinement/final/boards/joint_comparison.jpg>)
