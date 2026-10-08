# D:\worldgoing 無用檔案清查報告（只剖析、未刪除）

- 日期：2026-10-08
- 範圍：整個 `D:\worldgoing`（不含 `.git\`），以 Python 長路徑掃描 374,017 個檔案，合計 **537.4 GB**。
- 工具：`git ls-files`（3,272 個追蹤檔）、`git status`（431 個已修改的追蹤檔）、對 `scripts/ scenes/ tools/` 的 `res://` 與 `output/` 路徑引用掃描、對 1,617 份頂層收據/交接文件的快照引用掃描。
- 詳細清單在 [`reports/cleanup-audit-20261008/`](cleanup-audit-20261008/)（TSV，欄位為位元組大小、狀態、路徑）。

## 先講重點

| 分類 | 大小 | 建議 | 信心 |
|---|---:|---|---|
| A1 驗證用的「專案原始碼快照」，沒有任何收據引用 | **188.7 GB** | 刪 | 高 |
| B1 驗證快照，但被火攻／船隻收據引用 | **206.5 GB** | 確認後刪 | 中 |
| A2 `.godot-temp` 中 10/01 以前的子目錄 | **21.7 GB** | 刪 | 中高 |
| C1 `.godot\` 匯入快取（可重建） | 9.6 GB | 只有空間不夠才刪 | 中 |
| B2 V0.5R 之前、無程式引用的 output 目錄 | 4.0 GB | 確認後刪 | 中 |
| B3 已被 .gitignore 排除的 q35 試作 .blend | 1.18 GB | 確認後刪 | 中高 |
| B4 `.visual_captures\` 截圖證據 | 1.28 GB | 確認後刪 | 中 |
| 其他小型垃圾（備份、暫存、空目錄等） | 約 0.2 GB | 刪 | 高 |

只做 A 類就能回收約 **210 GB**；連同 B1 可回收約 **420 GB**。

**重要提醒：** 最後一次 commit 是 V0.5R（2026-09-27）。之後火攻、船隻、建築、攻城、科技樹、音效、生態等工作全部都還沒 commit（431 個修改檔、`scripts\` 有 1,178 個未追蹤檔、`assets\` 也有新資源）。這些都不是垃圾，本報告一律不列入。建議刪除前先 commit 一次。

---

## A. 高信心，可直接刪

### A1. 未被引用的驗證原始碼快照：547 個，188.7 GB
- 路徑：`output\<任務>\verification\source-<測試名>-<時間戳>\`
- 內容：每跑一次驗證就把整份專案（`assets\ scenes\ scripts\ native\ project.godot`）複製一份，每份約 1.1 GB。
- 分布：`fire_implementation_20261006` 297 個／139.0 GB；`site_ship_close_20261004` 157 個／48.4 GB；`site_building_close_20261004` 93 個／1.4 GB。
- 理由：任務頂層的收據、交接、README 都沒有引用這些快照名稱。每次驗證的結果目錄（`verification\<時間戳>\result.json`、`source_hashes.json`、log）會保留，原始碼雜湊證據不會消失。
- 清單：`verification_snapshots.tsv` 中狀態為 `UNCITED` 的列。
- 信心：高

### A2. `.godot-temp\` 舊子目錄：1,170 個，21.7 GB
- 路徑：`.godot-temp\*`，但不含 `godot_verify\`（723 MB，有自動保留最新 100 次的規則，依 AGENTS.md 不碰）。
- 最大的幾個：`a0_a1_shadow` 4.5 GB（09-26）、`site_combat_assets` 1.8 GB、`mingguang_low_pose_20260912` 1.8 GB、`morph_uv_repair` 1.6 GB、`weapon_refresh_20260913` 1.6 GB、`western_plate_20260913` 1.4 GB、`crossbow_stance_20260914` 1.3 GB、`equipment_dye_publish` 1.0 GB，以及一堆 `*_baseline_20260910` 和 `lining_current_*.blend` / `.blend@`。
- 理由：都是 Blender 發佈或驗證的中間檔，已被 .gitignore 排除，最後修改都在 09-26 之前，那些工作已在 V0.35R 到 V0.5R 釋出。
- 不刪：10/01 之後還有更新的 25 個子目錄（合計約 50 MB，例如 `crowd_fire_p6`、`site_combat`、`region_*`），可能還有測試在用。
- 清單：`godot_temp_subdirs.tsv`（第 3 欄是最後修改日）。
- 信心：中高（舊的 `*_baseline_*` 理論上可當比對基準，但對應的版本都已釋出）

### A3. 審核留下的備份檔：22 個，約 1 MB
| 路徑 | 理由 |
|---|---|
| `GAME_AUDIO_IMPLEMENTATION_PLAN.before-review.md`、`.before-review2/3/4.md`、`.before-decisions2.md` | 音效計畫審核的中間版，正式版 `GAME_AUDIO_IMPLEMENTATION_PLAN.md` 已存在，審核討論串已結束 |
| `SITE_NATURAL_RESOURCES_AND_LAND_CONDITIONS_PLAN.md.bak-20261008`、`b`、`c`、`d` | 生態計畫審核的中間版，正式版存在 |
| `SITE_UI_FORMAL_AND_TEST_WINDOW_PLAN.before-review4.md` | 和正式版逐位元組相同 |
| `SITE_UI_FORMAL_AND_TEST_WINDOW_PLAN.before-audio.md` | 加入音效前的舊版 |
| `reports\npc-ai-offscreen-addendum.md.bak-20261007*`（5 個） | 正式版存在 |
| `reports\region-gameplay-plan.md.bak-20261007*`（5 個） | 正式版存在 |
| `reports\tech-tree-v2-draft.before-v2.1.md` | 舊版草稿 |
- 都沒有被 git 追蹤。信心：高

### A4. 其他小型垃圾
| 路徑 | 大小 | 理由 | 信心 |
|---|---:|---|---|
| `native\army_idle\bin\~army_idle.windows.x86_64.dll~RF*.TMP`（9 個）、`native\crowd10k\bin\~crowd10k...~RF*.TMP` | 4.7 MB | 替換被鎖住的 DLL 時 Windows 留下的暫存檔 | 高 |
| `0.35`、`mat_out.txt`、`scratch_stdout.txt`、`editor_scan_out.txt`、`editor_scan_err.txt` | 7 KB | 舊的 Godot 4.6 輸出，.gitignore 已排除 | 高 |
| `worldgoing.csproj.old.5` | 571 B | 舊 csproj 備份 | 高 |
| `vc140.pdb`（根目錄） | 1.9 MB | 10-03 編譯 native 時落到根目錄的 MSVC 除錯檔 | 中高 |
| `scripts\tests\__pycache__\` | 0.3 MB | Python 位元碼快取 | 高 |
| `Godot\`（只有 `editor_settings-4.6.tres` 等 2 個檔） | <1 MB | 舊的 Godot 4.6 編輯器設定，專案已改用 4.7.2 | 中高 |
| `.godot-user-cache\`、`.godot-user-data\`、`.godot-temp-archive\` | 39 MB | 8 月的舊使用者資料與 log | 中高 |
| 空目錄：`lfs\`、`NVIDIA Corporation\`、`.godot_tmp\`、`art_source\`、`addons\`、`export_templates\`、`feature_profiles\`、`script_templates\`、`text_editor_themes\` | 0 | 空的，多半是把 APPDATA 導向專案時產生的。之後工具可能會再建出來 | 中高 |

---

## B. 中信心，建議刪，但要你確認

### B1. 被收據引用的驗證快照：188 個，206.5 GB
- 火攻 155 個／172.1 GB，被 `P1_GATE_RECEIPT`、`P2_GATE_RECEIPT`、`P3_*`、`P4_*`、`P6_CLOSE_RECEIPT`，以及 `fire_p0_close_20261005\P0_FINAL_*` 引用。
- 船隻 33 個／34.5 GB，被 `site_ship_close_20261004` 的結案文件引用。
- 理由：火攻 P1 到 P6 已在 10-06 功能結案（`CURRENT_PROGRESS.json` 寫的是 `FUNCTIONAL_CLOSE_COMPLETE`，效能部分延後），船隻也有 `FINAL_ACTIVE_BASELINE.json`。刪掉後收據還在，結果與原始碼雜湊也還在，只是不能再用當時那份原始碼重跑。
- 折衷做法：只保留 `P6_CLOSE_RECEIPT` 和船隻 `FINAL_*` 直接引用的少數幾份，其餘刪除。
- 清單：`verification_snapshots.tsv` 中 `CITED` 的列，第 4 欄是引用它的文件。

### B2. V0.5R 之前、沒有任何程式引用的 output 目錄：75 個，4.0 GB
- 最大的：`terrain_army_jump_heavy_20260918` 2.7 GB、`medieval_cloth_armor_rule_20260916` 505 MB、`site_combat_move_20260913_0000` 340 MB，其餘多是 `site_army_scale_phase*`（每個 10 到 50 MB）。
- 理由：這些是已釋出版本的驗收證據，`scripts\ scenes\ tools\` 都沒有讀寫這些路徑。
- 清單：`old_output_dirs_unreferenced.tsv`

### B3. .gitignore 已排除的 q35 角色試作檔：約 1.18 GB
- `assets\characters\human\q35\audit_repair\` 726 MB（含 `rebuild\candidate_male/female.blend` 各約 325 MB）
- `assets\characters\human\q35\lining_armor_fit\` 418 MB（`candidate_*.blend`）
- `assets\characters\human\q35\joint_refinement\` 35 MB
- 理由：.gitignore 註解寫明是「duplicate trial exports」，遊戲沒有引用。`hair_gendered\candidate_*.blend` 有被明確保留，不列入。
- 信心：中高

### B4. 其他
| 路徑 | 大小 | 理由 | 信心 |
|---|---:|---|---|
| `.visual_captures\`（106 個子目錄） | 1.28 GB | 截圖證據，已被 .gitignore 排除；最新的寫入是 10-07，可能還有討論串在看 | 中 |
| `.benchmarks\` | 123 MB | 09-11 的隊形 benchmark 輸出 | 中 |
| `tmp\` | 21 MB | 8 月的暫存（imagegen、inspect 腳本） | 中 |
| `scratch\`（35 個除錯 .gd） | <1 MB | 09-22 前的一次性除錯腳本，沒有 .gitignore，Godot 會掃到 | 中 |
| `Claude outputs\` | 2.3 MB | 一份計畫副本加 2 張 gif | 中低 |
| `.codex-remote-attachments\` | 0.4 MB | 8 月的附件 | 中 |

---

## C. 低信心或不建議刪

| 路徑 | 大小 | 說明 |
|---|---:|---|
| `.godot\`（`imported\` 9.4 GB、`mono\` 167 MB 等） | 9.6 GB | 可以重建，但刪掉後要重新匯入 2.6 萬個資源，耗時很長；只建議在 Godot 關閉且空間不夠時刪 |
| V0.5R 之前、但有程式引用的 output 目錄（76 個） | 34.4 GB | 測試腳本會把結果寫進這些路徑，部分還會讀基準檔（例如 `site_combat_performance_20260913`、`equipment_matrix_20260918`）。要刪需要逐個確認，清單在 `old_output_dirs_code_referenced.tsv` |
| `output\` 中 09-27 之後的非快照內容 | 約 53 GB | 尚未 commit 工作的唯一證據，而且部分測試直接讀取，例如 `site_ship_close_20261004\ship_reference_metadata_v4_tower.json`、`preview_regions_v4_tower.json`，以及 `fire_implementation_20261006\p1_coverage_candidate`。**不要刪** |
| `tools\region_lab\.tmp\` | 1.3 GB | 台灣地圖的原始下載資料（DEM、OSM、Copernicus、GSHHS）和 Python 套件，要重建地圖時需要；能重新下載，但很慢 |
| `.tools\`（Blender 4.2 可攜版、VRM 外掛） | 1.04 GB | 美術發佈流程在用，保留 |
| `assets\region_lab\earth_tw_tm2_121_v1_r3_trial\`、`_r4_probe\` | 118 MB | 名稱看起來像試作，但掃描顯示 r3_trial 有被引用，不建議刪 |
| 靜態掃描標為「無引用」的資源 | 6.9 GB | 大部分是誤判：q35 的 `.blend` 美術原始檔（已追蹤）、用動態路徑載入的 dye JSON，以及 751 個用 `--script` 執行的 `scripts\tests\*.gd`。**不要刪** |
| 根目錄的舊計畫和交付文件（`*_LUNA_MAX.md`、`*_DELIVERY.md`、`*_SOL.md` 等，約 60 份） | 約 3 MB | 已過時，但很小，而且是設計歷史；建議搬到 `docs\archive\`，不要刪 |
| `Worldgoing_火攻火箭與建築燃燒_實作規格_v1.0.md` 等 2 份 | 119 KB | 火攻規格正本（檔名在 git bash 顯示為亂碼），保留 |

## 刪除時要注意
1. 先 commit 目前的工作（09-27 之後都還沒 commit）。
2. 刪除前先關閉 Godot 和 Blender，也確認沒有討論串正在跑驗證。
3. `output\` 有很多路徑超過 260 字元，一般檔案總管或 `Remove-Item` 會失敗，要用 `\\?\` 長路徑或 `robocopy /MIR` 空目錄的方式刪。
4. 不要動 `.godot-temp\godot_verify\` 的保留規則，也不要動 `tools\lfs-clean-guard` 的設定（見 AGENTS.md）。
