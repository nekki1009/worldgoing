# Site 交戰：目前 3D 角色裝備與動作缺口

更新日期：2026-09-13。狀態：角色補件及持械移動圖集已接入正式資產；**不是整套 Site 交戰、全裝備組合或百人效能完工證明**。

01:10 連續命中更新：沒有重輸出角色或圖集。普通兵畫面仍用下方 1,080 幀圖集，碰撞已改用原動畫精確時間及原瞄準計算；兩個女隊長呈現骨架外，新增全隊共用的一份非渲染查詢來源，沒有每兵骨架。原烘焙碰撞／護甲檔保留作離線參考，執行期不再載入該全表。原生匯入動畫因改變非取樣時刻而拒用；只在來源雜湊相符並配對原始動畫副本時重用匯入網格。四方向 32 姿態／128 護甲點及兩隊 GPU 通過，13 張本批圖已檢視，見 `output/site_continuous_contact_20260913_0100/README.md`。下方較早的「離散取樣／動態瞄準待接續」由此更新取代；三者完整攻守、移動公平性及全裝備矩陣仍未閉合。

本輪已在男女正式包各新增 16 個動作，補入箭／弩矢與箭袋道具、共用事件時序、1,000 幀普通士兵圖集及逐姿態碰撞資料。續作另修正明光鎧十個下襬部件的低姿態，以及 get_up 的腿部／鞋底軌跡。原有素體、骨架、材質、非目標網格及既有骨骼動畫資料保留，以作業前備份比對；沒有重做角色或增設每兵 Skeleton3D。
明光鎧低姿態已通過本文所列的男女聚焦驗證。原完整場景 GPU 逾時與軍隊存讀檔不一致已在後續程式續作修復；20:30 的兩隊部署／接觸／倒地／玩家入隊與指揮救助驗證已通過。21:22 另修正攻擊後待機循環殘留，完成男女八種武器／徒手、馬上長劍／長槍對步行者的 160 個玩家／NPC 攻守互換案例與 80 張方向截圖；這是無盾、卸除主要護具的真實模型基準，未改正式素材。全方位武器格擋、全裝備組合、普通士兵三者互換與長時間效能仍未完成。第 6、8 節保留歷史證據，最新完成與未完成邊界以實作進度文件為準。
交戰程式目前的完成與驗證邊界另見 `SITE_COMBAT_IMPLEMENTATION.md`。
21:50 續作修正普通士兵取樣時刻與共用出步。22:23 再追加持械待機四方向 16 幀，原 1,000 幀像素／索引／碰撞／護甲逐項完整保留；當時圖集為 1,016 幀、33 動作組、4096 × 6031。2026-09-13 續作保留這 1,016 幀，僅追加持械 walk／run 的四方向各八幀；正式圖集現為 1,080 幀、35 動作組、4096 × 6404。新增四方向同姿態幾何／護甲、實際預約移動／暫停／JSON 續接及完整兩隊 GPU 回歸通過；男女模型未改。兩次備份與 SHA-256 分見 `output/site_combat_idle_20260912_2210/README.md`、`output/site_combat_move_20260913_0000/README.md`。普通士兵離散取樣、動態瞄準與完整移動公平性仍待接續；同原始姿態對照不是連續出招公平性或全裝備驗收。

## 1. 已有的裝備，不需要重做

男女正式 GLB 中，以下編輯器選項所對應的模型前綴均存在；這是檔案結構核對，尚不表示每套裝備都已通過動作穿模檢查。

| 類別 | 已有內容 | 本輪結論 |
| --- | --- | --- |
| 近戰武器 | 長劍、長槍、戰斧、戰鎚、匕首 | 首版近戰所需基本武器已存在 |
| 遠程武器 | 長弓、十字弩 | 武器本體存在；不能因此認定彈藥模型與裝填流程完整 |
| 盾牌 | 一種加熱盾 `shield_heater_01`，含手持與收納部件 | 可作首版實體格擋；不必先增加盾牌種類 |
| 頭盔 | 皮盔、中式鐵盔、鋼盔、明光盔、中式皮盔，共 5 種 | 已有 |
| 身甲 | 皮革輕甲、中式鐵甲、明光鎧、中式皮甲，共 4 種 | 已有；護臂、肩甲等目前屬各整套護甲的子部件 |
| 內衣 | 基本內衣、甲內襯衣，共 2 種 | 已有 |
| 鞋靴 | 皮靴、中式皮靴、鐵靴、明光鎧戰靴，共 4 種 | 已有 |
| 披風 | 旅行披風、中式披風 | 已有；不能把披風當成人體受擊範圍 |
| 騎乘 | 現有馬匹及男女騎乘接點 | 保留既有功能；本輪未重新驗證騎乘穿模 |

目前沒有獨立手套／護臂／護腿換裝槽；這不等於現有護甲沒有那些幾何部件。只有未來明確要「各自換裝」時才拆槽，不為交戰公式先重建整套裝備系統。

## 2. 真正缺少或尚未正式接入的裝備／道具

| 優先級 | 缺口 | 現況與最小補法 |
| --- | --- | --- |
| P1：保留弓弩玩法 | 可見的箭、弩矢，以及在手／搭弦／飛行的呈現 | 已補 `combat/combat_props.glb` 的 Arrow／Bolt，共用原骨架接點；另由該 GLB 烘焙 `arrow.png/.res`、`bolt.png/.res`，場景飛行改用實際彈體圖像。發射與扣彈共用一次事件，不為飛行彈體建角色骨架 |
| P1：遠程可讀性 | 箭袋／弩矢袋 | 已補 QuiverArrow／QuiverBolt 與分離內容物，掛在既有髖骨；可見支數為實際存量的至多三支，空彈隱藏內容，不取代存貨所有者 |
| 待制度確認 | 俘虜拘束道具 | 沒有已接入的繩索／拘束物；是否使用、裝備如何處置與押送方式仍屬未決制度，不擅自把手銬等指定為首版必做 |
| 待制度確認 | 攜糧包、交付袋、拾取包 | 既有甲上小袋不能當作已完成的可交付糧袋。待載量、交付、遺落物規則確認後，優先以共用道具呈現 |
| 後續攻城切片 | 重弩彈／石彈、攻城器械及操作接點 | 未接入首版近戰步兵；不應為這些缺口阻止既有劍、槍、斧、鎚的交戰驗收 |

首版近戰最急迫的瓶頸不是再增加武器或護甲種類，而是下列動作、碰撞資料及普通士兵圖集。

## 3. 已有的動作

男女 GLB 都包含：

- 待機與移動：`idle`、`walk`、`run`。
- 防禦與受擊：`guard`、`hit`、`hit_back`、`knockback`、`down`。
- 近戰：`walk_slash`、`attack_sword`、`attack_spear`、`attack_axe`、`attack_hammer`、`attack_dagger`、`attack_unarmed`、`attack_jump_heavy`。
- 遠程：`attack_bow`、`attack_crossbow`。
- 騎乘：`ride_idle`、`ride_walk`、`ride_run`、`ride_slash`、`ride_thrust`、`ride_attack`。
- 基準：`T-Pose`。

男性 GLB 額外有 `attack`，女性沒有同名匯出 clip；編輯器的通用「attack」是依武器映射的入口，因此不能直接把這個名稱差異判定為女性缺少全部攻擊動作。GLB 裡的原始匯入別名也不額外算作已接線玩法。

## 4. 本輪動作與事件補件狀態

| 優先級 | 動作／資料 | 目前狀態 | 驗證與邊界 |
| --- | --- | --- | --- |
| P0 | 舉盾、放盾過渡 | 已補 `guard_raise`、`guard_lower`，各 0.15 秒 | 既有手腕與盾面一起移動；GPU 測試核對過渡與返回 guard／idle |
| P0 | 破防後露出空檔 | 已補 `guard_break`，0.4 秒 | 盾仍可見且其實際覆蓋中心移位，不以隱藏盾面代替 |
| P0 | 昏迷後維持倒地 | 沿用 down 進入，新增 `unconscious` 2.4 秒循環 | HP／昏迷／死亡仍由既有狀態分開；支援暫停及存讀檔姿態 |
| P0 | 甦醒／起身 | 已補 `get_up`，2.2 秒 | 倒地→坐起→半跪→站立；完整起身期不可操作，占位阻擋站起，不補 HP |
| P0 | 友軍現場救助 | 已補 `rescue`，4 秒 | 男女互換施救者，手掌膠囊與倒地者人體幾何有接觸；視覺位移仍在原格內，完成後接 get_up，無搬運系統 |
| P0 | 無盾武器格擋的實際接觸 | 已補 `guard_weapon`、`guard_polearm`，各含持續／raise／lower／break，共 8 clip | 編輯器按盾與武器映射；格擋使用整把實際手持武器幾何。四方向劍對劍、劍對槍、槍對槍測試中，側向劍招有真實 parry，其餘部分先接觸身體；不宣稱所有攻向都能擋住，不格擋箭矢 |
| P0 | 各攻擊的有效段、收招段標記 | 已補 `character_combat_timings.gd` 的 24 fps 原始幀事件表 | 編輯器、角色及烘焙器共用，取代通用比例；測試訓練只縮前搖／收招、有效段不變。劍入口依編輯器正規化為 walk_slash |
| P0 | 普通士兵交戰圖集＋碰撞資料 | 已烘焙 32 動作組、4 方向、1,000 幀及相應 body／weapon／parry／shield／armor 資料 | 素材階段有 48 姿態逐點比對；17:27 續作已接長劍攻擊、倒地與起身資料，定向資料測試通過，完整場景 GPU 尚未通過 |
| P1 | 弓弩裝填與發射可見同步 | 已補 `reload_bow` 1.15 秒、`reload_crossbow` 1.5 秒 | 實測裝填不先扣彈、指定 release 才扣一發並生成一次，空彈不假裝裝填，被打昏中止不扣彈；弩裝填使用左手，右手保留弩身 |
| P1 | 撤退、潰退動作表意 | 保留既有 walk／run，未增加專用動作 | 本輪為角色素材切片，未將命令、AI 退卻與玩家控制列為新完成項目 |
| 待制度確認 | 拘束、被俘待機、押送、解救 | 沒有正式配對動作 | 先確認拘押與押送規則，再補相符動作；現場喚醒不能被當成解除拘押 |
| 待制度確認 | 裝糧、交付、拾取與搬運 | 沒有正式後勤動作 | 等交付條件與時間定案，沿用人物／存貨及共用道具 |

以上 16 個新增 clip 已存在於男女正式 GLB 與可編輯 `.blend`。0.15 秒舉／放、0.4 秒破防與 1.2 秒無盾持續格擋為三套姿態共用時長，名稱不是尚待製作的預留值。

## 5. 普通士兵與特寫角色要分開驗收

最初完整烘焙為 1,000 幀、4 方向、32 動作組，4096 × 5850；追加持械 idle 16 幀、walk／run 64 幀後正式為 **1,080 幀、4 方向、35 動作組**，4096 × 6404。既有 idle 4 幀、walk 8 幀、run 8 幀的 ID、時長、取樣時間與全部原像素保留。圖集含步兵近戰、弓弩、三種 guard、受擊、倒地、昏迷、起身、救助與裝填；不含新騎兵或跳躍攻擊烘焙。combat_idle／combat_walk／combat_run 是原動畫的裝備狀態變體，不是新增骨骼動畫；run 呈現讀取既有移動時長，並未新增軍隊奔跑指令。
metadata schema 2 保留 anchor／rect，增加取樣時間、碰撞索引、逐動作武器／盾及事件表。`standard_soldier_collision.bin` 是無物件的 Godot Variant/ZSTD，含人體膠囊、實際武器與盾輪廓、護甲的投影索引三角面；護甲不是填平空洞的凸包。所有座標為相同格位地面接點的地圖像素。

資產大小：PNG 7,162,166 bytes，Texture2D `.res` 95,846,866 bytes，碰撞 `.bin` 223,451,218 bytes。`.bin` 已加精確路徑的 Git LFS 規則。17:27 續作改為啟用近戰測試時載入一次並由兩隊共用，非逐兵載入；目前仍整份解壓，尚未做記憶體／吞吐最佳化。一般未啟用交戰的既有隊伍仍走原移動路徑；新增資料接線不等於完整 GPU 或效能驗收。

所以「3D 編輯器能播放攻擊」不能等同「99 名普通士兵能公平攻擊」。後者必須同時交付畫面與該姿態的碰撞資料，保持相同地面接點與尺寸。
玩家及近景 NPC 仍使用透明 SubViewport → Sprite2D；地圖仍由 Node2D + Camera2D 控制。

## 6. 驗收邊界與仍需處理項目

1. 男女共用既有骨架與投影，保留素體、現有裝備、騎乘及既有動作，不以重做整個角色包解決單一缺口。
2. 每個新增／修正動作拍攝正面、背面、側面、3/4 與實際 Site 視角；真的開圖檢查，不只確認檔案存在。
3. 帶盾／無盾、短兵器／長槍、裸露部位／護甲覆蓋、腳部與格位接點分別驗證。
4. 同一姿態在特寫角色與普通士兵圖集中的武器接觸結果一致；一揮一次／一人一次、友軍阻擋及箭矢第一接觸均有測試。
5. 倒地、持續昏迷、救助、起身與死亡畫面能區分；沒有靠切 idle 瞬間站立的正式驗收捷徑。
6. 另測慢幀、暫停、鏡頭縮放與合法存讀檔；美術截圖不等於這些行為或百人效能通過。

上述為驗收要求，不表示全部已完成。當前證據：男女非目標網格／骨架／舊骨骼動畫資料保留、16 clip 時長、男女相互施救接觸、盾面移位、慢幀攻擊一次事件、2×／4× 縮放幾何不變、暫停、起身占位、存讀檔與遠程扣彈時機均通過聚焦測試。

明確限制：

- 明光鎧中央布襬、前垂片與左右／後裙甲共十部件已補 down／unconscious／get_up／rescue 修形；布襬收折、甲片與鑲邊整組轉動。男女完整取樣最低裙甲分別為 0.04682／0.05287 模型單位，回 idle／T-Pose 與裸甲／皮甲切換均無殘留修形。這是四個動作的聚焦驗收，不是全裝備／騎乘零穿模證明。舊 matrix 中的裙襬穿地截圖保留為失敗歷史，不代表目前正式版本。
- get_up 改以既有腿骨 IK 校正腳底，48 fps 製作、約 96 fps 執行取樣。男女皮靴最低點為 -0.00076／-0.00581 模型單位，在明示的 0.008 容差內；不宣稱數學上完全零穿地，也未重驗其他三種鞋靴的所有姿態。
- 護甲碰撞先用 Godot 原生 blend-shape 混合結果再套既有蒙皮，避免畫面已收裙、命中面仍是原長襬。沒有新增碰撞架構或每兵運算；因這也涵蓋已有衣物修形，本輪重烘焙整份普通士兵碰撞資料。
- 披風在新低姿態使用局部呈現校正；昏迷保留舊 down 終點修形，起身淡出該修形，跪姿收攏懸垂長度。這不是布料物理，也不改人體／護甲命中幾何；未宣稱所有服裝與動作零穿模。
- 武器格擋必須真的先相交，不能由選 guard 就保證擋住刺擊或所有角度。
- 普通士兵同規則交戰接線、實際多人友軍阻擋／箭矢第一接觸整合矩陣，以及 100／9,000 人效能未驗收。資料層接觸排序與本輪雙角色幾何測試不取代它們。
- 騎乘、俘虜拘束、後勤與攻城不在本輪補件範圍；未修改其制度。

## 7. 盤點來源

- 正式模型：`assets/characters/human/q35/standard_anime_male_character_pack.glb`、`standard_anime_female_character_pack.glb`，本輪直接讀取 GLB 的 JSON chunk。
- 編輯器：`scripts/ui/human_character_3d_editor.gd` 的 `PART_SLOTS`、`ANIMATION_SLOTS`、`WEAPON_ATTACK_MAP` 及盾牌收納流程。
- 士兵 metadata：`assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json`。
- 既有烘焙器：`scripts/tools/bake_terrain_army_soldier.gd`。
- 戰鬥接入：`scripts/terrain_lab/terrain_test_character.gd`、`terrain_weapon_collision.gd`、`site_combat_rules.gd`。

未把舊版 HumanBase／舊 Battle 的功能、原始 builder 裡未匯出的函式或未開啟的歷史截圖當作目前正式可用資產。

## 8. 重建入口與本輪驗證紀錄

正式角色檔仍是 `assets/characters/human/q35/standard_anime_{male,female}_character_pack.{blend,glb,json}`；共用道具在同層 `combat/`。動畫製作入口 `scripts/tests/run_site_combat_asset_stage.py author male`（female 同理），採 180 秒硬逾時並保存日誌，輸出候選而不自動覆寫正式檔。已有手修候選時只用 `export`；以 `rescue` 或 `guard_polearm_break` 等本輪 clip ID 取代 `author`，只重製該 clip。基準優先使用本次保留的 `.godot-temp/site_combat_assets/baseline`，不存在時讀正式來源。舊動作／網格以 additive GLB append 保留。

道具使用同入口 `props male`，烘焙入口為 `scripts/tools/bake_site_combat_projectiles.gd`、`scripts/tools/bake_terrain_army_soldier.gd`。修改來源後需重新匯出、比對再提升候選，並執行 Godot `--editor --import`；只跑短 editor scan 不代表完整匯入。

明光鎧續作入口為 `scripts/tests/run_site_combat_asset_stage.py mingguang male`（female 同理）。輸入保留在 `.godot-temp/mingguang_low_pose_20260912/grounded_baseline/{male,female}.{blend,glb,json}`：先由同一 runner 的 `get_up` 階段重製腳底軌跡，確認 `inspect_mingguang_low_pose.py -- <sex> feet combat` 的 213 個 Blender 取樣通過後，才複製候選到 grounded_baseline；再製作裙甲。裙甲階段使用 24 fps shape keys，僅替換十個目標 mesh 並在四個既有 clip 追加 weights 通道，保留原 binary prefix、節點、材質、皮膚與其餘動畫。沒有 grounded_baseline 時只可回到保留的未修裙 baseline，不可把已含 shape keys 的正式檔當成首次輸入。`site_combat_asset_files_test.py --candidate` 與男女完整 Godot 測試通過、看圖後才提升六個正式檔；不加 `--candidate` 再核對 SHA-256。最初六檔備份及本次重烘焙前四檔圖集備份均保留在同一作業目錄。

下列 Godot 執行均使用 `godot-runtime-verify/scripts/verify_godot.ps1`，專案内獨立環境，Godot **4.6.2 stable mono console**；headless 為 `--headless --path ...`，visual 不使用 headless。表內每次均退出碼 0、無腳本／斷言錯誤；根憑證讀取訊息另列為已知環境雜訊。

| 驗證入口 | 模式／秒數 | 本輪結果紀錄 |
| --- | --- | --- |
| `site_combat_asset_files_test.py` | Python；PASS | 男女原始 GLB binary prefix、非目標 JSON 陣列、原骨骼通道與正式／候選 SHA-256；僅准十個裙甲網格與四個 clip 的 weights 追加，含道具正式檔一致性 |
| `mingguang_low_pose_test.gd -- male candidate_grounded full` | visual／52.233s | `.godot-temp/godot_verify/20260912_162930_740/result.json`；down 139／unconscious 117／get_up 213／rescue 193 姿態，以及 T-Pose／idle 各五姿態、真實連續截圖 |
| 同上，female | visual／52.891s | `.godot-temp/godot_verify/20260912_163346_378/result.json`；相同取樣矩陣 |
| `mingguang_low_pose_test.gd -- male final`／female | visual／10.966s、11.109s | `.godot-temp/godot_verify/20260912_163642_243/result.json`、`20260912_163747_701/result.json`；正式包關鍵姿態、四視圖與裸甲／皮甲／明光鎧切換重設 |
| `site_combat_character_assets_test.gd` | visual／21.672s | `.godot-temp/godot_verify/20260912_164039_133/result.json`；男女互換施救、實際 parry、慢幀、暫停、縮放、裝填發射；每性別 54 個起身劍鞘及 41 個長槍破防離地取樣；另含男女明光鎧五姿態 Site 呈現與護甲快照 |
| `site_combat_atlas_test.gd` | visual／16.619s | `.godot-temp/godot_verify/20260912_163947_543/result.json`；1,000 幀結構，48 個 live／baked 姿態比對 |
| `--editor --import` | headless／84.250s | `.godot-temp/godot_verify/20260912_164050_299/result.json`；最新正式角色與圖集完整匯入。另有既存 `output/verification-probe` 子專案略過警告，未移除無關 output |
| `site_combat_rules_test.gd` | headless／1.787s | `.godot-temp/godot_verify/20260912_163846_956/result.json` |
| `site_combat_save_test.gd` | headless／2.714s | `.godot-temp/godot_verify/20260912_163850_357/result.json` |
| `bake_terrain_army_soldier.gd` | visual／50.809s | `.godot-temp/godot_verify/20260912_163819_025/result.json`；最新起身／原生 morph 碰撞修正後全量重烘焙 |
| `capture_site_combat_assets.gd -- male final` | visual／20.407s | `.godot-temp/godot_verify/20260912_131644_324/result.json`；128 張四視圖／關鍵姿態 |
| `capture_site_combat_assets.gd -- female final` | visual／18.793s | `.godot-temp/godot_verify/20260912_131723_642/result.json`；128 張四視圖／關鍵姿態 |
| `capture_site_combat_assets.gd -- male motion` | visual／22.764s | `.godot-temp/godot_verify/20260912_131913_105/result.json`；16 動作完整 12 fps 序列 |
| `capture_site_combat_assets.gd -- female motion` | visual／22.733s | `.godot-temp/godot_verify/20260912_132008_081/result.json`；16 動作完整 12 fps 序列 |

最後兩項局部修正已重拍：起身劍鞘從腰側向外擺，避免過渡幀穿地／橫跨屈膝；長槍破防改為側向偏轉，不沿用短兵器的朝下手腕。起身 final 男／女紀錄為 `20260912_133939_867`（11.572s）／`20260912_134007_326`（13.070s），motion 為 `20260912_133811_275`（13.960s）／`20260912_133917_008`（14.268s）；長槍破防 final 為 `20260912_134623_600`（10.886s）／`20260912_134659_500`（11.388s），motion 為 `20260912_134710_927`（11.101s）／`20260912_134722_039`（11.223s）。均在同一 `.godot-temp/godot_verify/<紀錄>/result.json` 下，退出碼 0；這兩個動作以前次整批後的局部重拍為準。

上述 13 點批次保留為前次證據；get_up 的最新腿部軌跡以 16 點後明光鎧四視圖／完整序列、Site 與圖集截圖為準，不能用舊 get_up 圖像取代。Blender 最新 get_up 男／女日誌為 `.godot-temp/site_combat_assets/get_up_male_20260912_162514.log`／`get_up_female_20260912_162525.log`；裙甲為 `.godot-temp/mingguang_low_pose_20260912/mingguang_male_20260912_162726.log`／`mingguang_female_20260912_162736.log`，皆退出碼 0。

Blender 局部動作匯出仍有來源 Face 材質多張 texture sampler 的警告；正式 GLB 保留原始材質與影像。失敗日誌保留：`20260912_161934_675` 的起身鞋底低於容差已定向修正；`20260912_164002_738` 是新增 Site fixture 的區域變數型別推導錯誤，已明示 Dictionary 後通過 `164039_133`。桌面權限預檢曾回報 DESKTOP_USER_REQUIRED，之後經標準權限核准以桌面使用者執行 GPU 測試，沒有移除安全守衛。所有程序有硬逾時並主動追蹤；本輪停用執行器歷史清理呼叫以保留證據，未改動其他守衛。

最新圖像位於 `.visual_captures/site_combat_assets/{final,motion,matrix,site,atlas}`。`scripts/tests/site_combat_review_boards.py final`／`motion` 將真實截圖組成檢查板及可播放 GIF，入口為各 `boards/index.html`；沒有用繪圖修掉測試畫面中的問題。GPU fixture 使用真實 `TerrainTestCharacter`、透明 SubViewport 與 Camera2D，但不是完整 TerrainLab 百人戰場。

明光鎧最新完整序列／GIF 位於 `.visual_captures/mingguang_low_pose/candidate_grounded/boards/index.html`，由 `site_combat_review_boards.py mingguang candidate_grounded` 整理；該候選與正式六檔 SHA-256 相同。正式包另拍 `.visual_captures/mingguang_low_pose/final/`；實際地圖投影為 `.visual_captures/site_combat_assets/site/mingguang_*.png`。已逐張檢查男女四視圖、起身全序列與 Site／圖集對照，沒有將數值 PASS 單獨當成外觀結論。

本輪檔案尚未提交或推送。磁碟滿載時的 12:53／12:59 圖像不可作驗收依據，以本節 13 點後重新輸出為準。
