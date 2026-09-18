# Worldgoing HumanBase_v1 3D 角色建模與模組管線交接手冊
(3D Character Modeling & Modular Pipeline Handover Specification)

> **2026-09-18 中性五官**：保留原 Face 01–04，男女各新增 Face 05–08（圓杏、長杏、平直細、寬距柔眼）。生成參考圖後只改眼周結構，眉嘴、UV、權重、原骨架與動畫保留。可編輯來源在 `assets/characters/human/q35/neutral_faces`，builder 經 `load_authored_neutral_faces.py` 載入四個新物件；`gray` 明確重建，手改後只用 `preview/export`。原編輯器、618張新臉預覽、282張舊畫面RGBA等價及8例男女存讀通過；254份舊圖集僅更新有等價證據的來源紀錄。普通兵／騎乘的新五官圖集尚未烘焙。來源、驗證及失敗紀錄見 `output/neutral_faces_20260918/README.md`。

> **2026-09-18 布帽**：新增中式布帽、日式布烏帽、西式軟呢帽，男女各自量測頭皮與獨立額頭網格；放在原 Helmet 欄，原頭盔不取代。`Helmet_Cloth_{Chinese,Japanese,Western}_01_*` 綁原 Head，帽冠、帽帶與縫線沿原 helmet 染色；NPC16／玩家首長自由色不變。開口布帽只裁切帽冠內的頭髮，摘帽恢復；不套封閉鐵盔的整束收髮規則。可編輯來源在 `assets/characters/human/q35/cloth_hats`，`author_cloth_hats.py` 的 gray/detail 是顯式重建，手改後只用 export；男女 builder 透過 `load_authored_cloth_hats.py` 載入，不再另造骨架或整包覆寫。既有模型 bytes／動畫保留，舊圖集以原版／新版 240 張固定姿態 RGBA 等價及來源守衛檢查保留，不冒稱重烘；布帽普通兵／騎乘圖集仍未新增。驗收与失敗記錄見 `output/cloth_hats_20260918/README.md`。

> **2026-09-17 普通兵圖集續作**：44 個四材質武器／工具已接入原標準男性皮革輕甲、原內衣／皮靴、無盾的 2D 配方，每個 19 動作／四方向／584 幀與獨立染色遮罩；原鐵劍盾兵保留。延伸原 ranged reader／baker 和既有 Sprite／MultiMesh，不重匯出或改動男女 GLB，不為普通兵增加 3D 骨架。其他服裝、髮型、女普通兵、持盾與騎乘組合仍需自己的完整配方，不可借圖繞過來源守衛。製作、實際畫面、逐像素／場景驗收邊界與失敗紀錄見 `output/weapon_materials_npc_20260917/README.md`。

> **2026-09-17 武器／工具材質**：七種武器與伐木斧／鎬／工具錘／鏟各有木、石、鐵、鋼，共44選項，男女原骨架。舊ID與網格保留且列鐵製；`wood_axe_01` 是伐木斧，木製版為 `wood_axe_01_wood`。單一目錄 `scripts/ui/weapon_materials.gd` 同時供 Blender 與 Godot 使用；弓弩依箭頭外觀分級。可編輯來源在 `assets/characters/human/q35/weapon_materials`，此離線目錄設 `.gdignore`；正式角色包仍在父目錄。來源重載、弓弦形變別名、實際畫面與普通兵圖集界線見 `output/weapon_materials_20260917/README.md`，不得以重新全包建置覆寫現有服裝美術調整。

> **2026-09-16 布甲配鞋**：另加中式布鞋、日式足袋草鞋、歐式軟皮短鞋，男女分別貼合，歸 Boots／鞋靴，不取代原鞋。`Boots_Medieval_*` 沿用原骨架、鞋部染色與物品保存；不觸發高筒靴褲管收束。可編輯來源、接入入口與實際驗證界線見 `output/medieval_shoes_20260916/README.md`。

> **2026-09-16 最新使用者規格**：新作中、日、歐式男女六套（上衣＋褲／裙）整套改列 Armor／護甲的布甲類，與皮甲、鐵甲共用槽位；不再是 Outfit 選項。原 `outfit_underlayer_01` 與 `outfit_chinese_lining_01` 留在內衣欄，不覆寫。保留原網格／動作識別與骨架，染色改走 armor；NPC 十六組與玩家自由配色政策不變。這項最新要求取代下文 Outfit 的舊限制；來源、正式畫面與普通兵圖集界線以 `output/medieval_cloth_armor_20260916/README.md` 為準。

> **2026-09-10 驗證更新**：全模型修正範圍見 [ALL_MODEL_REPAIRS_2026-09-10.md](ALL_MODEL_REPAIRS_2026-09-10.md)；後續男女手肘／手腕局部修正見 [BODY_JOINT_REFINEMENT_2026-09-10.md](BODY_JOINT_REFINEMENT_2026-09-10.md)；中式襯衣 × 鐵甲／明光鎧交疊、護腕適配與可還原換裝覆蓋見 [LINING_ARMOR_OVERLAP_REPAIR_2026-09-10.md](LINING_ARMOR_OVERLAP_REPAIR_2026-09-10.md)；缺 UV 的形變網格與切線匯入修復見 [MORPH_UV_IMPORT_REPAIR_2026-09-10.md](MORPH_UV_IMPORT_REPAIR_2026-09-10.md)。以下固定尺寸、動作數與「完美」「徹底零穿模」等歷史敘述不是目前的全組合認證；請區分最新的 editor 掃描、原生匯入資源、角色功能與指定畫面驗證範圍。

> **交接聲明**：本文件供後續接手的 AI（如 ChatGPT / Claude / Antigravity 等）直接閱讀與接續開發。文件中詳述了本專案 3D 角色管線的完整歷史背景、架構原則、拓撲提取規則、骨骼權重標準與自動化驗證流程。

---

## 一、專案根目錄與重要檔案路徑

### 1. 專案路徑
- **專案根目錄**：
  ```text
  c:\Users\Nekki\Dropbox\竹北社大\(01)102-103學員資料\share\worldgoing
  ```
- **原始 VRM 基礎素材目錄**：
  ```text
  c:\Users\Nekki\Dropbox\竹北社大\(01)102-103學員資料\share\worldgoing\.tools\standard_anime_base\HairSample_Male.vrm
  ```
- **核心 3D 建置腳本**：
  ```text
  scripts/tools/blender/build_standard_anime_male_character_pack.py
  ```
- **匯出 3D 產物路徑**：
  ```text
  assets/characters/human/q35/standard_anime_male_character_pack.blend
  assets/characters/human/q35/standard_anime_male_character_pack.glb
  ```
- **Godot 3D 角色編輯器場景與測試腳本**：
  ```text
  scenes/ui/human_character_3d_editor.tscn
  scripts/ui/human_character_3d_editor.gd
  scripts/tests/human_character_3d_editor_test.gd
  ```

---

## 二、不可違反之核心原則 (Core Constraints)

1. **不可修改身體與臉部基準**：
   - 保留目前已驗證通過的身體比例與第一套/第二套五官模型，嚴禁因重做衣物裝備而破壞身體皮膚或臉部網格。
2. **所有裝備部件獨立模組化**：
   - `Body`（身體）、`Face`（五官）、`Hair`（頭髮）、`Outfit`（內衣）、`Armor`（護甲）、`Cape`（披風）、`Weapon`（武器）、`Shield`（盾牌）、`Boots`（靴子）**必須是獨立部件**。
   - 所有裝備槽位在 Godot 編輯器中皆支援 `None`（無 / 卸下）選項。
3. **Outfit 定位為薄底四角內衣**：
   - `Outfit` 部件僅作為貼身輕薄底層內衣，不可做成厚重大衣、長褲或外甲。
4. **按材質結構選擇形變，按實際動作驗收**：
   - 貼身衣物以原生 VRM 權重為起點；硬件使用既有骨骼錨點；離身長布以肩頸承重、連續曲面及必要的動作修形處理。繼承權重不等於已證明零穿模。
   - 驗收需列出已測性別、裝備組合、動作與極值幀。`T-Pose` 和 `Walk` 不能代表跳躍、抬臂、扭身或騎乘。布料流程見 `.agents/skills/worldgoing-3d-equipment/references/cloth-cape.md`。

---

## 三、架構演進與技術轉型背景 (Architecture Evolution)

### 1. 舊流程缺陷（已全面廢棄）
- **舊做法**：採用純程序化數學公式（三角函數超橢圓 `super_ellipse_pt` 等）手動計算頂點網格，並透過手動粗略指派骨骼權重。
- **後果**：
  1. 內褲背面半徑估算過大，腰部後方翹起像浮空托盤（尿布感/翅膀感）。
  2. 走路邁步時，大腿內側與胯部權重無法精準對齊，產生嚴重網格扯裂（Tearing）。
  3. 剛性裝備（護肩、護臂、護膝、武器、盾牌）未鎖定 Rest-Pose 骨骼頭部軸心，導致動作時脫離人體。

### 2. 貼身衣物與剛性配件流程（不適用所有離身布料）
- **核心架構**：**同構網格提取（Conformal Sub-mesh Extraction）+ 骨骼 Rest-Pose 局部錨定（Bone Rest-Pose Local Anchoring）**。
- **做法優勢**：
  1. 直接由 VRM 模型之封閉服飾拓撲（Material 2 褲子、Material 3 鞋靴、Material 0 皮膚）提取服飾幾何。
  2. 保留來源骨骼權重（`J_Bip_{L/R}_UpperLeg`、`LowerLeg`、`Foot`、`ToeBase`、`Hips`、`Spine`、`Chest`），裁切、加厚後仍需重查接縫與形變。
  3. 沿用來源曲面可降低貼身衣物錯位風險，但不保證無鋸齒、翹起或動作撕扯；長披風不能以身體拓撲提取取代布量設計。

---

## 四、VRM 拓撲材質槽位剖析 (VRM Mesh Slot Anatomy)

原始素材 `HairSample_Male.vrm` 的 `Body` 包含以下材質槽位：

| 材質索引 (Slot) | 材質名稱 | 面數 (Faces) | 高度範圍 (Z Range) | 用途說明 |
| :--- | :--- | :--- | :--- | :--- |
| **Material 0** | `M00_001_01_Body_00_SKIN` | 7,340 | `0.000 ~ 1.500` | 身體皮膚層（頭、頸、臂、軀幹、裸腿）。用於提取胸甲 `Bodice` 與肩帶。 |
| **Material 1** | `M00_006_01_Tops_01_CLOTH` | 2,990 | `0.848 ~ 1.579` | 上衣/連帽衫拓撲。 |
| **Material 2** | `M00_001_01_Bottoms_01_CLOTH` | 1,624 | `0.060 ~ 1.113` | 完整閉合下半身四邊形網格（自腰部延伸至踝部）。用於提取四角內褲、腰帶與靴筒。 |
| **Material 3** | `M00_001_01_Shoes_01_CLOTH` | 540 | `0.000 ~ 0.120` | 完整立體冒險鞋靴網格（鞋底、鞋跟、鞋頭）。用於提取皮靴腳部。 |

---

## 五、各模組部件生成與分層規格 (Part Specifications & Layering)

下表是特定男體版本的歷史起始尺寸，不是所有性別與裝備組合的通用保證。新部件需重新量測目前素體及內甲包絡，並用實際穿戴與動作圖驗證偏移量：

```text
+=======================================================================+
| Z Range      | 部件名稱                            | 提取來源   | 法線偏移  |
+=======================================================================+
| 1.072 - 1.445| Armor 01 - 冒險背心 (Leather Vest)  | Mat 0 軀幹 | +0.0080m  |
| 1.390 - 1.445| Armor 01 - 立領包邊 (Stand Collar)  | Mat 0 頸部 | +0.0105m  |
| 1.035 - 1.070| Armor 01 - 腰帶 (WaistBand)         | Mat 2 腰部 | +0.0065m  |
| 0.935 - 1.035| Armor 01 - 臀部戰裙皮甲片 (Tassets) | Mat 2 裙擺 | +0.0080m  |
| 0.320 - 1.035| Armor 01 - 冒險長褲 (Trousers/Pants)| Mat 2 下身 | +0.0025m  |
| 0.440 - 0.570| Armor 01 - 前臂皮護腕 (Bracers)     | Mat 0 前臂 | +0.0065m  |
| 0.990 - 1.018| Outfit 01 - 內褲腰帶 (WaistBand)    | Mat 2      | +0.0020m  |
| 0.755 - 1.018| Outfit 01 - 四角褲主體 (Briefs)     | Mat 2      | +0.0000m  |
| 0.755 - 0.775| Outfit 01 - 褲管收口 (Leg Cuffs)    | Mat 2      | +0.0020m  |
+-----------------------------------------------------------------------+
| 0.370 - 0.418| Boots 01 - 靴口包邊 (Top Cuff)      | Mat 2      | +0.0055m  |
| 0.060 - 0.418| Boots 01 - 靴筒 (Boot Shaft)        | Mat 2      | +0.0035m  |
| 0.115 - 0.145| Boots 01 - 腳踝皮帶 (Ankle Strap)   | Mat 2      | +0.0055m  |
| 0.000 - 0.120| Boots 01 - 立體鞋底 (Foot & Sole)   | Mat 3      | +0.0035m  |
+=======================================================================+
```

### 1. 內衣模組 (`Outfit_Underlayer_01`)
- **定位**：低腰俐落運動四角褲（Low-rise Athletic Boxer Briefs）。
- **主體網格**：`Outfit_Underlayer_01_UnderwearBottom`（Material 2，`Z ∈ [0.755, 1.018]`）。
- **腰帶邊條**：`Outfit_Underlayer_01_UnderwearWaistband`（Material 2，`Z ∈ [0.990, 1.018]`，偏移 0.002m）。
- **褲管收口**：`Outfit_Underlayer_01_UnderwearLegOpening_L/R`（Material 2，`Z ∈ [0.755, 0.775]`，偏移 0.002m）。
- **特點**：腰部上限止於 `Z = 1.018`（髂骨下方），與皮甲腰帶（`Z >= 1.035`）保有乾淨間隔，**絕不互相重疊或交錯穿模**。

### 2. 皮甲模組 (`Armor_Light_Leather_01`)
- **冒險者合身長褲**：`Armor_Light_Leather_01_Pants`，由 Material 2（下半身 `Z ∈ [0.320, 1.035]`）提取，偏移 0.0022m，褲管平順收納於皮靴筒（`Z <= 0.418`）內，完美承接雙腿走動動畫骨骼權重。
- **冒險者真皮背心**：`Armor_Light_Leather_01_Vest`，由 Material 0（皮膚層 `Z ∈ [1.072, 1.445]`，`|X| <= 0.165`）透過 `bmesh.ops.bisect_plane` 平整裁切提取，偏移 0.0055m。保留 100% 脊椎/胸腔原生權重。
- **立領包邊與胸前飾線**：`Armor_Light_Leather_01_Collar`（`Z ∈ [1.390, 1.445]`，偏移 0.0075m）與 `FrontSeam`。
- **斜跨皮帶與金屬胸扣**：`Armor_Light_Leather_01_CrossStrap` 與 `StrapBuckle`。
- **立體順肩弧形護肩**：`Armor_Light_Leather_01_Pauldron_Upper/Lower_L/R` 與 `Pauldron_Rivets_L/R`，雙層弧面圓頂貼合肩峰，綁定 `J_Bip_{L/R}_UpperArm`。
- **貼身真皮護腕**：`Armor_Light_Leather_01_Bracer_L/R` 與 `BracerStraps_L/R`，由 Material 0 前臂皮膚（`|X| ∈ [0.440, 0.570]`）提取，偏移 0.0055m，完美隨手腕擺動。
- **腰帶與臀部戰裙皮甲片**：
  - `Armor_Light_Leather_01_WaistBand`（Material 2，`Z ∈ [1.035, 1.070]`，偏移 0.0055m）+ 金屬皮帶扣 `BeltBuckle`。
  - `Armor_Light_Leather_01_Tasset_L/R`（Material 2，`Z ∈ [0.935, 1.035]`，偏移 0.0065m），四片獨立懸掛皮革戰裙。
  - `Armor_Light_Leather_01_Pouch_L/R`（左右腰部隨身皮包，綁定 `J_Bip_C_Hips`）。

### 3. 皮靴模組 (`Boots_Leather_01`)
- **鞋底與鞋面**：`Boots_Leather_01_Foot_L/R`，由 Material 3（`Z <= 0.120`）+ Material 2（`Z ∈ [0.060, 0.418]`）合成，偏移 0.0035m。
- **靴口包邊**：`Boots_Leather_01_Cuff_L/R`（Material 2，`Z ∈ [0.370, 0.418]`），偏移 0.0055m。
- **踝部皮帶**：`Boots_Leather_01_Strap_L/R`（Material 2，`Z ∈ [0.115, 0.145]`），偏移 0.0055m。

### 4. 披風模組 (`Cape_Travel_01`)
- **定位**：貴族冒險者旅行斗篷披風（Adventurer Travel Cape），依據官方美術設定圖《重甲與劍盾.png》設計。
- **雙肩胸針鎖扣與前胸飾帶**：
  - `Cape_Travel_01_Brooch_L/R`：左右雙肩前胸立體金質圓盤胸針（`Z = 1.405, Y = -0.120, X = ±0.085`），鑲嵌銀質中心凸球寶石（`Cape_Travel_01_Gem_L/R`）。
  - `Cape_Travel_01_FastenerBand`：橫跨前胸鎖骨的金屬緊固橫帶（`Z ∈ [1.395, 1.405]`），固定披風不位移。
- **雙肩過肩披領 (Shoulder Mantle)**：
  - `Cape_Travel_01_ShoulderMantle`：自前胸胸針位置（`Y = -0.120`）跨越肩峰頂部（`Z = 1.448, Y = 0.005`）一路延伸至後背上緣（`Y = +0.080, Z = 1.425`），**徹底消滅披風與肩背之間的懸空浮動空隙**。
- **後背立體貼合波浪垂墜布料**：
  - `Cape_Travel_01_Main`：由肩頸後背上緣（`Z = 1.435, Y = 0.075`）順著脊椎背部自然微拱下垂至大腿下緣（`Z = 0.620, Y = 0.105`）。
  - 網格採用 16×18 參數化曲面，緊密貼合皮甲背部輪廓（Clearance ~0.010m），自帶 4 重立體波浪起伏摺痕與自然傘狀下擺（Hem Flaring `0.130m -> 0.315m`），整體厚度 0.004m。
  - 骨骼綁定：`J_Bip_C_UpperChest`（隨胸腔軀幹自然擺動）。

### 5. 多武器模組 (Multi-Weapon Pack: 7 Weapon Types)
所有武器模組皆採用標準冒險者外觀比例，精準錨定於右手掌心（`J_Bip_R_Hand`）或左手掌心（`J_Bip_L_Hand`）：

| 武器名稱 | 零件名稱 | 綁定骨骼 | 幾何與設計特徵 |
| :--- | :--- | :--- | :--- |
| **長劍** (`Weapon_Longsword_01`) | `Grip`, `Blade`, `Guard`, `Pommel` | `J_Bip_R_Hand` | 精鋼雙面開刃長劍身（長度 0.72m），弧形黃金護手，皮革防滑纏帶握柄，雙層金質圓盤劍首。 |
| **長槍** (`Weapon_Spear_01`) | `Shaft`, `Head`, `Collar`, `Tassel`, `Ferrule` | `J_Bip_R_Hand` | 2.1m 白蠟木桿長槍，柳葉菱形高碳鋼槍尖，黃金加固套筒，赤紅絲綢戰穗，金屬防滑配重尾鐏。 |
| **戰斧** (`Weapon_Axe_01`) | `Haft`, `Head`, `BackSpike`, `Cap`, `Grip` | `J_Bip_R_Hand` | 粗獷重型戰斧，月牙寬刃開山斧刃（刃寬 0.30m），後背穿甲破甲錐，硬木柄身配交叉皮帶纏裹。 |
| **戰鎚** (`Weapon_Hammer_01`) | `Haft`, `Head`, `BackBeak`, `Crown`, `Rings` | `J_Bip_R_Hand` | 破甲破盾重型戰鎚，八角立體淬火鋼鎚面（斜角包邊），後側烏鴉嘴破甲鉤喙，金屬加固防滑環。 |
| **匕首** (`Weapon_Dagger_01`) | `Grip`, `Blade`, `Guard`, `Pommel` | `J_Bip_R_Hand` | 敏捷輕巧雙刃短匕（長度 0.36m），血槽幾何刃面，反向彎曲月牙黃金護手，水滴金屬配重柄頭。 |
| **長弓** (`Weapon_Bow_01`) | `Grip`, `Limb_Upper`, `Limb_Lower`, `Tips`, `String` | `J_Bip_L_Hand` | 反曲複合實木長弓（弓長 1.30m），左手握柄皮革包覆，雙端黃金上弦卡榫，張緊強化弓弦。 |
| **十字弩** (`Weapon_Crossbow_01`) | `Stock`, `Prod`, `Stirrup`, `String`, `Trigger` | `J_Bip_R_Hand` | 重裝滑鐵盧鋼弩（Arbalest），雕花實木弩托（0.62m），52cm 高拉力鋼質弩臂，前端腳蹬與黃金扳機座。 |

### 6. 盾牌模組 (`Shield_Heater_01`)
- **定位**：騎士級紋章加熱盾 / 鳶盾（Heater Shield），依據官方美術設定圖《重甲與劍盾.png》設計。
- **前臂中心穿戴座標**：盾面本體中心平貼於左前臂外側（`X = 0.580, Y = -0.078, Z = 1.365`）。
- **盾面主體 (Field)**：`Shield_Heater_01_Field`，皇家深藍曲面盾板，具備水平弧形偏斜拱度（Horizontal Deflection Bow `R = 0.350m`）與經典圓弧收尖（`290mm × 400mm`）。
- **加固金邊 (Border/Rim)**：`Shield_Heater_01_Border`，全外圍立體斜角加固金屬邊框，增強視覺層次與立體感。
- **紋章飾紋 (Heraldic Crest)**：
  - `Shield_Heater_01_Cross_H / Cross_V`：金色立體十字紋章。
  - `Shield_Heater_01_Cross_Center`：中央菱形銀質核心盾徽。
- **握把與前臂皮帶固定 (Handle & Arm Strap)**：
  - `Shield_Heater_01_Handle`：內側前端握柄置於左手掌心（`X = 0.678, Y = -0.022, Z = 1.365`），左手五指緊握握柄。
  - `Shield_Heater_01_ArmStrap`：後端固定皮帶環繞左前臂（`X = 0.500, Y = -0.020, Z = 1.365`），將盾牌穩固固定於手臂上。
- **骨骼綁定**：`J_Bip_L_Hand`（左手與前臂，隨左臂走動自然防禦擺動）。

---

## 六、主要骨骼 Rest-Pose 錨定座標參照表 (Rig Anchoring Reference)

| 骨骼名稱 (Bone Name) | 世界座標 (X, Y, Z) | 綁定之剛性裝備部件 |
| :--- | :--- | :--- |
| `J_Bip_R_Hand` (右手掌心) | `(-0.6780, -0.0220, 1.3650)` | 長劍、長槍、戰斧、戰鎚、匕首、十字弩 |
| `J_Bip_L_Hand` (左手/前臂) | `(+0.5800, -0.0780, 1.3650)` | 盾牌本體與皮帶、長弓本體與弓弦 (`Weapon_Bow_01`) |
| `J_Bip_C_UpperChest` | `(0.0000, -0.1200, 1.4050)` | 披風胸針、過肩披領、前胸橫帶與背部垂墜本體 (`Cape_Travel_01`) |
| `J_Bip_L_UpperArm` | `(+0.1650, -0.0040, 1.4150)` | 左肩雙層弧形護肩與鉚釘 (`Armor_Pauldron_Upper/Lower/Rivets_L`) |
| `J_Bip_R_UpperArm` | `(-0.1650, -0.0040, 1.4150)` | 右肩雙層弧形護肩與鉚釘 (`Armor_Pauldron_Upper/Lower/Rivets_R`) |
| `J_Bip_C_Chest` | `(0.0000, -0.1080, 1.3100)` | 胸前斜跨皮帶與金屬搭扣 (`Armor_CrossStrap / StrapBuckle`) |
| `J_Bip_C_Hips` | `(0.0000, -0.0920, 1.0550)` | 皮帶金屬扣 (`Armor_BeltBuckle`) |
| `J_Bip_C_Hips` | `(±0.1450, 0.0050, 0.9700)` | 左右腰部收納包 (`Armor_Pouch_L/R`) |

---

## 七、完整 15 種角色動作系統 (15-Action Animation System)

| 動作名稱 (Action ID) | 中文名稱 | 類型 / 時長 | 動作設計特徵與骨骼控制 |
| :--- | :--- | :--- | :--- |
| `T-Pose` | 基準姿勢 | 靜態 (0.04s) | 雙臂水平展開，雙手手指緊閉握持武器與盾牌。 |
| `idle` | 待機姿態 | 循環 (2.00s / 48f) | 冒險者戰鬥戒備步態，胸部與脊椎呼吸起伏，左臂持盾防禦胸口，右手提武器待發。 |
| `walk` | 走動步態 | 循環 (1.00s / 24f) | 冒險者步伐行進，交替邁步、膝關節屈曲與骨盆側擺，武器隨步伐自然向外下方延伸擺動。 |
| `run` | 跑步衝刺 | 循環 (0.83s / 20f) | 身體前傾衝刺，大幅度交替跨步與高抬膝，雙臂高頻率擺動，武器與盾牌緊隨衝刺姿態。 |
| `guard` | 盾牌防禦 | 循環 (2.00s / 48f) | 沉穩架盾防禦：雙腿微屈沉重心，左臂將盾牌垂直豎起護於胸口前方正對正面，右手提武器貼肋隨時預備反擊。 |
| `hit` | 受擊反震 | 單次 (0.83s / 20f) | 遭受衝擊硬直：軀幹與頭部大幅後仰、右腿明顯後撤一步踩地緩衝、左手提盾格擋卸力、恢復重心站姿。 |
| `knockback` | 被擊退 | 單次 (1.25s / 30f) | 遭受強大衝擊被猛烈向後推擠（位移 `Z = 0.70m`）、身體大仰角受力、落地時雙腿深蹲下沉呈摩擦煞車姿態（Brake Crouch）穩定回正。 |
| `down` | 擊倒倒地 | 單次 (1.50s / 36f) | 雙膝脫力跪倒（Knee Buckle）→ 骨盆下降至地面（`Z = -0.85m`）→ 平躺於地面平台，武器與盾牌自然落於身側。 |
| `attack_sword` (`attack`) | 長劍連招 | 單次 (1.25s / 30f) | 參考 2D 精靈圖設計：蓄力收刀（Windup）→ 正前方水平直刺（Thrust）→ 爆發性斜下前伸斬擊（Diagonal Slash）→ 慣性收刀（Follow-through）→ 恢復站姿。 |
| `attack_spear` | 長槍突刺 | 單次 (1.25s / 30f) | 右側腰際收槍蓄力 → 大步向前弓步猛烈水平貫穿直刺（Forward Piercing Lunge）→ 俐落收槍復位。 |
| `attack_axe` | 戰斧劈砍 | 單次 (1.33s / 32f) | 雙手高舉過頂蓄力 → 全身重量下壓之重裝垂直劈擊（Overhead Cleave Chop）→ 碎地後拔斧回防。 |
| `attack_hammer` | 戰鎚橫掃 | 單次 (1.33s / 32f) | 側身大角度旋轉蓄勢 → 大範圍前向水平重擊橫掃（Sweeping Crush Arc）→ 順應慣性收勢。 |
| `attack_dagger` | 匕首連擊 | 單次 (1.00s / 24f) | 敏捷低身前刺（Low Stab）→ 上挑斜抹喉斬擊（Upward Throat Slash）→ 輕巧後撤步拉開距離。 |
| `attack_bow` | 弓箭射擊 | 單次 (1.25s / 30f) | 左臂前伸舉弓瞄準目標 → 右手搭弦後拉至臉頰滿弓（Full Draw）→ 鬆手釋放產生強烈後座力反彈。 |
| `attack_crossbow` | 十字弩發射 | 單次 (1.25s / 30f) | 雙手端弩舉至胸口平視瞄準 → 扣動扳機產生向上劇烈後座力跳動（Trigger Kick）→ 微傾弩身進行上弦復位。 |

---

## 八、建置、匯出與測試指令流程 (Commands & Verification)

### 1. 執行 Blender 建置管線
在專案根目錄下執行以下 PowerShell 指令，重新提取模型並產生 `.blend` 與 `.glb` 檔案：
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\scripts\tools\blender\run_blender.ps1' --background --python '.\scripts\tools\blender\build_standard_anime_male_character_pack.py'
```

### 2. 執行 Godot 自動化單元測試
驗證 UI 零件切換、16 種動畫切換與所有 7 種武器顯示：
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "& (Join-Path $env:USERPROFILE '.codex\skills\godot-runtime-verify\scripts\verify_godot.ps1') -ProjectPath (Get-Location).Path -GodotExecutable 'Godot_v4.6.2-stable_mono_win64_console.exe' -Mode visual -GodotArguments @('--script','res://scripts/tests/human_character_3d_editor_test.gd') -TimeoutSeconds 120"
```

### 3. 執行 Godot 自動化視覺截圖驗證
測試產生的截圖位於 `.visual_captures/human_character_3d_editor/clipping/`：
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "& (Join-Path $env:USERPROFILE '.codex\skills\godot-runtime-verify\scripts\verify_godot.ps1') -ProjectPath (Get-Location).Path -GodotExecutable 'Godot_v4.6.2-stable_mono_win64_console.exe' -Mode visual -GodotArguments @('--script','res://scripts/tests/human_character_3d_editor_clipping_test.gd') -TimeoutSeconds 120"
```

---

## 九、後續擴充指南（給接手 AI）

1. **若需新增其他服飾套裝（如法袍、重甲等）**：
   - 務必遵循本文件之「分層高度與法線偏移」規則。
   - 凡穿戴於身體之薄層布料，優先使用同構網格提取或 `DATA_TRANSFER` 獲取精確權重。
   - 凡金屬硬塊或外掛飾品，優先錨定至對應骨骼 Rest-Pose 局部座標。
2. **若需修改材質顏色或貼圖**：
   - 在 `build_standard_anime_male_character_pack.py` 的 `material()` 區塊微調 Base Color、Roughness 或 Metallic。
   - 保持 PBR 著色節點與 Godot StandardMaterial3D 兼容。
3. **武器攻擊動作路由機制**：
   - 在 [`scripts/ui/human_character_3d_editor.gd`](file:///c:/Users/Nekki/Dropbox/竹北社大/(01)102-103學員資料/share/worldgoing/scripts/ui/human_character_3d_editor.gd) 中，透過 `WEAPON_ATTACK_MAP` 字典自動將裝備中的武器對應到專屬的攻擊動作（如 `spear_01` -> `attack_spear`），並支援手動下拉選單切換 16 種動作。
