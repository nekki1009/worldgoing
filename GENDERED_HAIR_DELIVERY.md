# 男女獨立八款 3D 髮型

## 接入與操作

`scenes/ui/HumanCharacter3DEditor.tscn` → Body 選男女 → Hair 顯示該性別八款，另有「無」。男女各自記住本次編輯器中的髮型選擇，不再共用一個選項 ID。

| 編號 | 男角 | 女角 |
| --- | --- | --- |
| 01 | 層次短髮 | 雙馬尾 |
| 02 | 側分短髮 | 垂肩長髮 |
| 03 | 狂野狼尾 | 俐落短髮 |
| 04 | 戰士束髮 | 戰鬥高馬尾 |
| 05 | 中分簾髮 | 精靈短髮 |
| 06 | 後梳背頭 | 雙丸子髮 |
| 07 | 低束編辮 | 側垂編辮 |
| 08 | 清爽短寸 | 半束波浪 |

01–04 保留原模型；05–08 為本次新增的實際網格，不是選單佔位。新 ID 為 `hair_male_01`–`08` 與 `hair_female_01`–`08`。舊 `hair_short_01`–`04` 只作為測試／呼叫相容輸入，按目前性別轉換，UI 不再顯示混合男女名稱。

髮色控制使用既有頭盔遮髮 shader 路徑，保留來源明暗與幾何陰影，只替換髮色；`_Band` 髮飾不染，皮膚、臉與裝備不變。「原色」關閉染色，恢復每個原始材質。更換髮型、切換男女、選無再裝回都保留本次染色設定。

既有 2D `PaperDollComposer`／`CharacterCreator` 的染色機制沒有修改。3D 編輯器原先沒有髮色選擇器，本次補上；此面板仍是 presentation-only，不新增 GameSession 存檔或外部角色狀態。

頭盔 Auto／Hide／Off 保留。目前五種頭盔沒有馬尾出口；Auto 保留面部開口中的瀏海，以及護片孔洞後與後頸處的貼頭髮層，收起外凸長髮、髮球、後方散髮與髮束繫帶。短髮仍保留原本較高的髮際，不額外延長到頸部。脫盔完整恢復，Off 可查看未遮罩的完整模型。後續修正證據見文末。

## 參考圖與製作來源

內建 **imagegen** 生成男女各一張、每張八款三視圖設定表，沒有使用 CLI/API fallback。參考圖是造型指引，不是實機驗收圖。

- `assets/characters/human/q35/hair_gendered/reference/male_eight_styles.png`
- `assets/characters/human/q35/hair_gendered/reference/female_eight_styles.png`
- 最終生成提示：`assets/characters/human/q35/hair_gendered/reference/prompts.md`
- 可編輯來源：`assets/characters/human/q35/hair_gendered/candidate_male.blend`、`candidate_female.blend`。
- 正式資產：`assets/characters/human/q35/standard_anime_{male,female}_character_pack.{blend,glb,json}`。

新增髮型按男女各自當前頭部表面取樣貼合，不是把男髮等比例套到女頭。沿用原 Armature；短髮與髮根用 Head，長髮末端漸變到 UpperChest，沒有額外髮骨或平行動作系統。

顯式重作入口：Blender `scripts/tools/blender/author_gendered_hair.py -- male --gray`（female 對應）。這會重作 05–08，不能在手工修改後無意執行。一般男女 builder 透過 `load_authored_gendered_hair.py` 載入已保存網格，不重新製作髮型。第一次工作的原資產备份在 `.godot-temp/hair_gendered/baseline/`；重作先明確準備正確基線，不能以包含新增髮型的正式包當成未新增基線。

## 驗證範圍

- 資產契約：男女各八款有網格、UV、有限座標和正常權重；原有全部二進位資料不變，僅追加新髮型資料。原男 448／女 443 個 mesh 和原男 43／女 41 段 animation 資料保留，不代表此次逐一播放所有動畫。
- 來源 loader：男 5／女 8 個新增 mesh 可載入既有骨架，Scene 只有一個 Armature，所有 modifier 指向它；不等同整包從 VRM 重新建置。
- 編輯器：16 款、各性別 8+無、對方性別 ID 拒絕、切換／無不殘留、男女各自選擇、兩種染色及還原、髮飾不染、非髮材質不變。
- 輪廓：Blender 新髮正／側／背灰模；Godot 全八款正／背／側／3/4。看圖後修過浮動辮根、髮球、耳部覆蓋與後梳弧度。
- 組合：八款各配五種頭盔，三種遮罩模式；新增長髮 07／08 配甲內襯衣＋中式皮甲＋中式披風，idle／run 各六幀。
- 動作：每款 idle／walk／run／attack_jump_heavy 各六個樣本；新增 05–08 另有固定背側視角 24 幀完整 run 序列。診斷鏡頭跟隨頭部以免跳躍極值被裁切，未改編輯器或地圖的共享鏡頭契約。

限制：沒有髮絲物理模擬；沒有測完所有服裝／所有動畫／所有身體或臉部組合；沒有測戰場多人效能。沒有以參考圖、截圖數量或測試 PASS 宣稱全組合零穿模。

### 可重跑檢查

Python：`scripts/tests/validate_gendered_hair.py --final`。

Blender：`--background --python-exit-code 1 --python scripts/tests/gendered_hair_loader_test.py`，外層子程序硬逾時 90 秒。製作階段硬逾時 180 秒，錯誤退出碼與日誌保留。

Godot 使用 `C:/Users/Nekki/.codex/skills/godot-runtime-verify/scripts/verify_godot.ps1`，`-Mode visual -TimeoutSeconds 180`，參數 `--script res://scripts/tests/capture_gendered_hair.gd -- male final`（female 對應；加 quick 只跑款式／染色／切換）。引擎 `C:/Users/Nekki/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64_console.exe`，D3D12 Forward+。未停止使用者開著的 Godot 4.7.2。

實機截圖：`.visual_captures/hair_gendered/final/`，總覽／檢視表／可播放 run GIF 在 `boards/`。檢視表只排列實際截圖，不重繪模型或修補截圖。

### 發佈紀錄

2026-09-11 已核對正式六個檔案仍等於本次基線後，覆入已驗證的男女 `.blend/.glb/.json`；沒有覆寫中途變更的他人檔案。工作樹原本包含大量未追蹤檔案，本次沒有 commit、stage 或刪除其他工作。

| 檢查 | 結果 | 證據 |
| --- | --- | --- |
| 正式 GLB 資料保留／八款／權重／UV | PASS，退出 0 | `.godot-temp/hair_gendered/contract.json` |
| Blender authored loader | 男女 PASS，退出 0 | `gendered_hair_loader_test.py` |
| GDScript check-only | PASS，退出 0，0.590 秒 | `.godot-temp/godot_verify/20260911_024536_844/result.json` |
| 男角正式 visual 完整測試 | PASS，退出 0，40.004 秒 | `.godot-temp/godot_verify/20260911_025945_467/result.json` |
| 女角正式 visual 完整測試 | PASS，退出 0，45.180 秒 | `.godot-temp/godot_verify/20260911_030130_884/result.json` |
| Godot 編輯器匯入快取更新 | PASS，退出 0，66.967 秒 | `.godot-temp/godot_verify/20260911_030319_400/result.json` |
| 正式匯入 PackedScene 八款／單骨架 | 男女 PASS，退出 0，1.233 秒 | `.godot-temp/godot_verify/20260911_030533_498/result.json` |

正式 GLB 更新後已重建 Godot 匯入快取，並從正式資源路徑載入 PackedScene 驗證男女各八款與單一 Skeleton3D；不只驗證直接載入的原始 GLB。

兩次正式 visual 均有 `GENDERED_HAIR_EDITOR_PASS` 與八款逐項標記；root certificate store 警告是退出 0 且沒有其他錯誤時的環境雜訊。Blender factory-settings 的 extensions cache 警告也未使 loader 失敗。原男角固定鏡頭的跳躍圖曾不可判讀，已改跟隨頭部，正式圖重拍後檢查。

## 第一輪戴盔遮髮修正（2026-09-11，已被後續修正取代）

本節保留歷史紀錄，不是目前的驗收標準。使用者指出背面變成「光頭戴頭盔」後，確認「背面 Auto 等於 Hide」是錯誤判準；以下 PASS 只代表舊斷言成立，不能代表外觀正確。現在要求保留後腦髮層，見下一節。

修改範圍只有 `human_character_3d_editor.gd` 的共用遮髮 shader／參數，以及聚焦測試和本文件；沒有修改 GLB、Blender 來源、骨架、動畫或染色運算。

舊遮罩只在頭部高度以上裁掉後髮，因此留下懸空且上緣平切的長髮末端；固定的明光盔裁切高度又低於實際額帶，形成額頭空帶。現在使用頭骨局部座標中的面部開口，後方髮束完整收起，額緣按目前頭盔高度重設。兩側寬度收至 0.060，避免舊女髮髮束彎回開口時漏出斷片。這是五種現有封閉式頭盔的設定，不是任意新帽型的通用包絡。

實際量測男女額帶在 Head-bone 空間的高度相同，並非直接共用世界座標。鐵盔額帶的對稱尖角經 Auto／Hide 對照確認是原有金屬飾片，不是髮尖，未改模型。原腳本的可恢復副本：`.godot-temp/hair_mask_repair/human_character_3d_editor.before.gd`。

### 本輪驗證

- 五種頭盔 × 男女各八款 = 80 組：Auto／Hide／Off 斷言、正／側／背及兩個 3/4 角度截圖。已查看各性別五種頭盔的正側檢視表，以及修正點的近景與前後對照。
- 80 組背面 Auto 與 Hide 同姿態像素比對：RGBA 通道差大於 24/255 才計數，全部為 0；主要有瀏海的款式在正面至少保留 142 個差異像素，避免以全隱藏假裝 Auto 正常。原男 03／女 02 的負例分別有 31,271／61,803 個背面差異像素，會被同一檢查拒絕。
- 皮盔／明光盔 × 全 16 款，染淺髮後抽查 `run`／`attack_jump_heavy` 各六個時間點；脫盔恢復八款完整髮型、保留染色、非髮材質不变。這次不是全動畫／全幀／全服裝組合驗收。
- 第一輪功能測試退出 0，但像素檢查仍抓到女角舊髮側邊殘片（最多 1,196 個像素）；已修正兩側寬度並重新拍攝、重跑，不以第一輪 PASS 代替視覺驗收。

| 檢查 | 結果 | 證據 |
| --- | --- | --- |
| 女角最終 visual | PASS，退出 0，44.561 秒 | `.godot-temp/godot_verify/20260911_161942_365/result.json` |
| 男角最終 visual | PASS，退出 0，36.870 秒 | `.godot-temp/godot_verify/20260911_162043_500/result.json` |
| 新測試 check-only | PASS，退出 0，0.554 秒 | `.godot-temp/godot_verify/20260911_162409_244/result.json` |
| 80 組影像回歸與原始負例 | PASS，退出 0 | `.visual_captures/helmet_hair_mask/final2/boards/pixel_report.json` |

當時引擎與 runner 同上，visual 使用 `--script res://scripts/tests/capture_helmet_hair_mask.gd -- male final2`（female 對應），硬逾時 120 秒。當時影像檢查為 `scripts/tests/verify_helmet_hair_images.py final2`，外層子程序硬逾時 60 秒；目前檢查已修改，因此舊 final2 圖應被新的髮層覆蓋檢查拒絕。保留 root certificate store 環境警告；當時執行沒有 parse/script/assertion 錯誤。未停止使用者開著的 Godot 4.7.2，也未提交 Git。

上一輪過度遮罩畫面：`.visual_captures/helmet_hair_mask/final2/`；前後對照為 `boards/before_after.png`，檢視表只排列真實截圖，不修補圖中模型。

## 後腦髮層保留修正（2026-09-11）

Auto 改成兩個保留區：既有面部瀏海開口，加上貼合後腦、低處逐漸收窄的髮根區。保留區在額帶以下，避免頭髮穿出盔頂；後頸髮際隨頭部弧度略微起伏，避免整圈平切。耳前的長髮回折殘片不屬於後腦區，另以局部前界收掉。這是裁切原髮網格，不是新增一層假髮、改頭皮顏色或修改截圖。

本輪仍只修改共用 shader、聚焦測試與本文件。沒有改素體、GLB、Blender 來源、骨架、動畫或染色運算。過度遮罩版本可恢復副本為 `.godot-temp/hair_mask_repair/human_character_3d_editor.overmasked.gd`。

檢查不再要求背面沒有頭髮，而是分開檢查：明光盔全部款式與皮盔 01–04 必須保留可見後腦髮層；盔頂及頸部以下不得出現外漏／懸空髮片；主要有瀏海款式必須保留面部開口髮束。短款 05–08 原髮際較高，在不透明皮盔下可不露出頸部頭髮，但明光盔上方孔洞後仍須有髮層。固定診斷鏡頭為 768×960，像素差閾值為 24/255；檢查只涵蓋明示的區域，不代表任意角度與所有動畫零穿模。

新圖位於 `.visual_captures/helmet_hair_mask/scalp_retained/`。`boards/before_after.png` 每對左圖是上一輪過度遮罩、右圖是保留後腦髮層的修正版。

### 修正版驗證結果

- 男女各八款 × 五種頭盔，共 80 組：Auto／Hide／Off 斷言、五個固定角度與 Auto／Hide 同姿態圖像比對通過。明光盔後腦區最少保留 4,068 個髮層差異像素；背面盔頂區與頸部以下區差異均為 0，主要瀏海保留條件亦通過。
- 負例確認：上一輪男／女 01 明光盔的後腦髮層差異均為 0，會被新覆蓋條件拒絕；原始男 03／女 02 懸空長髮在頸部以下分別有 19,101／52,775 個差異像素，仍會被尾端檢查拒絕。此處只統計指定區域，與上一節全背面數字不同。
- 皮盔／明光盔 × 全 16 款，染淺髮後擷取 `run`／`attack_jump_heavy` 各六個時間點；檢查後腦髮層跟隨頭部。脫盔恢復完整髮型、保留染色且非髮材質不變。已查看背側對照、正側圖、動作抽樣與脫盔圖，不宣稱全動畫／全幀／全服裝零穿模。
- 最終修正前曾發現女 02 耳旁殘片，已局部收窄後腦區的前界並重新拍攝男女完整測試；沒有再次整片隱藏後腦。

| 檢查 | 結果 | 證據 |
| --- | --- | --- |
| 女角最終 visual | PASS，退出 0，43.415 秒 | `.godot-temp/godot_verify/20260911_175241_297/result.json` |
| 男角最終 visual | PASS，退出 0，35.992 秒 | `.godot-temp/godot_verify/20260911_175348_528/result.json` |
| 80 組影像回歸與兩類負例 | PASS，退出 0 | `.visual_captures/helmet_hair_mask/scalp_retained/boards/pixel_report.json` |

重跑使用同一 runner，visual 參數為 `--script res://scripts/tests/capture_helmet_hair_mask.gd -- male scalp_retained`（female 對應），硬逾時 120 秒。影像檢查為 `scripts/tests/verify_helmet_hair_images.py scalp_retained`，外層子程序硬逾時 60 秒。最終兩次執行均未逾時、沒有 parse/script/assertion 錯誤，僅保留既知 root certificate store 環境警告。未停止使用者原有 Godot，修改尚未提交 Git。
