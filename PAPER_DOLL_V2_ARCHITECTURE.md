# Worldgoing Paper Doll V2 架構文件

狀態：**男女參考圖基線視覺驗收 PASS；拆件素材／自由換裝 Gate 尚未完成**
日期：2026-08-16
適用範圍：角色生成器、素材實驗室、UI 預覽、離線接觸表與未來 GPU variant 烘焙

本文件定義紙娃娃系統 V2 的資料、素材、標準化、合成與動畫契約。它針對目前紙娃娃「部件尺寸不一致、Anchor 漂移、方向錯置、騎乘圖層混用、染色污染」的根本問題重新設計。

本版本已完成獨立的 V2 契約、標準化 pack、Catalog、Recipe、固定 Sprite pool、單一幀動畫資料與素材實驗室。男女四組參考圖校準板已通過嚴格 GPU 像素驗收；舊的 split-part 部件仍只在 staging，尚未宣稱可以任意換裝或取代 V1 角色生成器。V1 角色生成器仍維持原狀，直到另一次明確的 V1→V2 遷移核准。

最高架構邊界仍遵守 `PROJECT_ARCHITECTURE.md`：紙娃娃是 Presentation 資料與顯示管線；不得成為角色 gameplay、裝備所有權、坐騎所有權、存檔或 Battle 單位的資料權威。9,000 人戰場不得建立個人 `Node`、`Sprite2D` 或 `PaperDollComposer`。

---

## 1. V2 核心決策

1. **素體先行**：男女各自擁有步行與騎乘素體。素體包含眼睛、臉、身體、四肢、腳與光頭；所有部件都覆蓋在素體上。
2. **狀態尺寸分離**：步行每幀固定 `64×64`；騎乘每幀固定 `64×96`。不再用 64×64 強行容納馬匹。
3. **部件標準化**：頭髮、護甲、鞋子、披風、武器、盾牌、馬匹與馬鎧都必須使用同一套 frame、Anchor、方向與透明邊界契約。
4. **先驗證、後登錄**：未通過尺寸、透明、對稱、Anchor、遮擋與染色遮罩檢查的素材，不得加入正式 Catalog。
5. **合成器不猜測**：Normalizer 可以執行已宣告的固定轉換；不能自動猜 Anchor、猜部件範圍或用任意縮放掩蓋錯誤素材。
6. **單一幀時鐘**：所有圖層由一個動畫控制器推送同一個邏輯 frame，禁止每個部件使用獨立 `AnimatedSprite2D` 或獨立 Timer。
7. **參考板只走明確的 QA preset**：完整角色參考板可進入 `is_reference_composite` 校準預覽與離線驗收；它不是正式的 Body、Armor、Mount split manifest，也不能寫入 gameplay 外觀。

## 2. 參考圖與工程指令的區分

附件是美術驗收基準，不是可直接執行的程式指令。真正的工程規格以使用者列出的五點為準。

| 參考來源 | 可作為的基準 | 未指定、不可臆測的內容 |
| --- | --- | --- |
| `ChatGPT Image 2026年8月12日 下午03_28_06.png` | 步行白髮、銀甲、披風的男女／三視角比例與輪廓 | 像素尺寸、Anchor、動畫幀數 |
| `ChatGPT Image 2026年8月12日 下午03_38_33.png` | 無武器騎乘時的人馬比例、馬蹄接地與騎士位置 | 64×96 內的實際 Anchor 座標 |
| `ChatGPT Image 2026年8月12日 下午03_53_06.png` | 頭盔、盾牌、長槍、馬鎧的騎乘遮擋關係 | 數值 Z-Index、動作時間與來源 sheet 排列 |

圖片展示的是三個視角：正面、背面、側面。V2 建議仍以 `DOWN`、`UP`、`RIGHT` 三列作為美術來源，`LEFT` 由 `RIGHT` 逐部件鏡像產生；若美術日後需要獨立左側圖，必須在 Manifest 明確標記，而不能默認混用。

## 3. 架構邊界與資料流

```text
ChatGPT 原始圖／人工繪製
		↓
V2 Normalizer（只做宣告的固定轉換）
		↓
V2 Asset Validator（產生 JSON 報告與接觸表）
		↓ 只有 PASS 才能通過
PaperDollCatalog（已核准視覺素材）
		↓
PaperDollRecipe（唯讀顯示快照）
		↓
PaperDollComposer（UI／SubViewport 顯示）
		↓
Contact Sheet／人工驗收／未來離線 Image variant
```

| 元件 | 唯一責任 | 不可擁有的資料 |
| --- | --- | --- |
| `PaperDollV2BodyTemplate` | 男女、步行／騎乘素體與固定 guides | 角色屬性、裝備所有權 |
| `PaperDollV2AssetManifest` | 一個已標準化部件的尺寸、Anchor、方向、遮罩與驗證結果 | runtime 角色狀態 |
| `PaperDollV2Catalog` | 只查找已通過驗證的 Manifest／Texture | 裝備數值、坐騎所有權 |
| `PaperDollV2Recipe` | 傳給顯示層的唯讀部件快照 | 可變共用 Resource、存檔狀態 |
| `PaperDollV2Composer` | 重用固定 Sprite pool、套用 Texture、frame、方向與 z-order | gameplay 邏輯、素材修正 |
| `PaperDollV2Animation` | 動作名稱、frame 序列、fps、loop 與事件標記 | 每層自己的動畫時鐘 |
| `PaperDollAnimationPlayer`／角色生成器 Timer | UI 預覽的單一時間來源 | Battle 單位狀態 |
| `PaperDollV2Validator` | 統一呼叫 Template／Manifest／Catalog 驗證並輸出可追溯報告 | 自動放行錯誤素材 |

## 4. 素體模板契約

### 4.1 四個基準模板

V2 必須先建立以下四個模板，未完成前不得批量產生部件：

```text
body_male_on_foot     64×64
body_female_on_foot   64×64
body_male_mounted     64×96
body_female_mounted   64×96
```

每個模板必須提供：

- 透明背景與 Nearest-friendly 像素邊緣。
- 眼睛、臉、身體、手臂、腿、腳與光頭。
- `anchor_px`、`foot_line`／`hoof_line`、頭部區域、臉部保護區與身體碰撞 guide。
- 允許部件覆蓋的 slot mask。
- 不允許部件進入的 protected mask，例如眼睛、鼻子、另一個部件的區域。
- `template_version`，任何 guide 變更都必須升版。

素體是對位的幾何權威。部件不可各自攜帶另一套比例或自行調整位置。

### 4.2 Anchor

Anchor 是**每個狀態一個固定值**，不是每個部件一個值：

```text
Sprite2D.centered = false
Sprite2D.offset = -template.anchor_px
Composer Node2D (0, 0) = 世界接觸點
```

V2 工程契約已固定步行 `(32, 56)`、騎乘 `(32, 88)`。兩者分別由 `PaperDollV2Contract.anchor_px()`、Template 驗證與 Composer offset 套用；生成 pack 的四個模板與 headless／GPU 檢查均使用相同數值。美術若要改變馬蹄或腳底基準，必須升版 Template 並重新跑完整 Gate，不可在 Composer 內局部補償。

V2 不接受「看起來差不多」的 Anchor。每個方向、每個 frame 的接觸點誤差應不超過 1 px；超過即 FAIL，回到素材修正流程。

### 4.4 參考圖校準輸入

女性參考板由 `assets/doll/reference/female_*_source.png` 保存，來源是以白髮銀甲男性 approved board 的比例、座高、馬蹄線與三視角排列為約束重新生成的女性完整角色板。`build_female_reference_calibrated_sheets.gd` 只做固定去背、三視角分割、側面鏡像與 56 px 高度標準化，輸出四張 `reference_match_female_*` sheet。它不把舊的橘色錯位拆件重新拼接，也不把完整板誤登錄成可自由換裝的單一部件。

來源是白底圖時，兩個 calibrated-sheet builder 只從來源邊界做「容許抗鋸齒灰階」的背景 flood-fill；不在縮放後或完成 sheet 上做顏色式外圈刪除，避免把白髮、銀甲與馬具高光誤判成白邊。這個清理屬於離線素材正規化，不放到 Composer 或 Battle runtime。

### 4.3 來源 sheet

第一版 V2 來源 sheet 建議固定為：

| 狀態 | Frame | 欄數 | 來源列 | Sheet 尺寸 |
| --- | ---: | ---: | ---: | ---: |
| On Foot | 64×64 | 8 | 3 | 512×192 |
| Mounted | 64×96 | 8 | 3 | 512×288 |

來源列固定為：`DOWN = 0`、`UP = 1`、`RIGHT = 2`。`LEFT` 預設使用 `RIGHT` frame 的水平鏡像；若採用獨立左側素材，必須在 Manifest 宣告 `AUTHORED_LEFT`。

若需要四列完成圖：

```text
On Foot baked   512×256
Mounted baked   512×384
```

這些 baked 尺寸不能與來源三列 sheet 混用。未來若使用 `Texture2DArray`，所有 slice 必須同尺寸；可以選擇將步行儲存時補透明邊界至 64×96，或使用步行／騎乘兩個 Array。不能依賴 Godot 在載入時隱式補齊。

## 5. 圖層與遮擋契約

V2 新增明確的 `BOOTS` 層，避免鞋子被迫塞入 Armor 或 Body。建議 render layers：

```text
MOUNT_TAIL
CAPE
MOUNT_BODY
BODY
BOOTS
ARMOR
HAIR
HELMET
WEAPON
SHIELD
MOUNT_HEAD
MOUNT_BARDING
```

V2 初始 z-order 延續 V1 的視覺關係，並為 Boots 留出獨立位置：

| Layer | DOWN | UP | RIGHT | LEFT |
| --- | ---: | ---: | ---: | ---: |
| MountTail | -10 | -10 | -10 | -10 |
| Cape | -5 | 15 | 5 | 5 |
| MountBody | 0 | 0 | 0 | 0 |
| Body | 10 | 10 | 10 | 10 |
| Boots | 11 | 11 | 11 | 11 |
| Armor | 12 | 12 | 12 | 12 |
| Hair | 13 | 13 | 13 | 13 |
| Helmet | 14 | 14 | 14 | 14 |
| Weapon | 15 | -1 | 15 | -1 |
| Shield | 16 | -2 | -2 | 16 |
| MountHead | 20 | -5 | 20 | 20 |
| MountBarding | 21 | 1 | 21 | 21 |

這張表是 V2 的候選契約，必須在 mounted armed 參考板完成後由人工 Gate 確認。任何為了掩蓋素材錯位而在 runtime 臨時調 z-index 的做法都不接受。

### 5.1 部件邊界

- Body 只包含素體，不包含頭髮、護甲、鞋子、武器或盾牌。
- Hair 只包含頭髮與眉毛遮罩，不得包含臉、鼻子、耳朵或披風。
- Armor 只包含護甲，不得重新繪製頭、頭髮、鞋子或身體底色。
- Boots 只包含鞋／靴，不得延伸到膝蓋以上，除非 Manifest 明確標記長靴。
- Weapon 只包含武器，不得附帶手臂或手掌。
- Shield 只包含盾牌，不得附帶身體或手臂。
- MountBody、MountHead、MountTail、MountBarding 必須分開；馬鎧不得把馬頭或騎士身體包進去。

## 6. 標準化 Manifest

每一個正式部件都必須有一份 `PaperDollAssetManifest`。最低欄位如下：

```text
visual_id
source_path
slot
state: ON_FOOT | MOUNTED
gender_policy: MALE | FEMALE | UNISEX
frame_size
sheet_size
frame_columns
source_rows
authored_directions
anchor_px
content_bbox_per_frame
symmetry_policy
allowed_template_version
protected_mask_id
dye_mask_ids
normalization_version
validation_status
validation_report_path
```

### 6.1 對稱策略

```text
MIRROR_RIGHT       使用 RIGHT 原圖產生 LEFT
AUTHORED_LEFT      LEFT 有獨立來源，必須個別驗證
ASYMMETRIC_ALLOWED 只允許武器、盾牌或明確標記的造型例外
```

未拿武器／盾牌前，Body、Armor、Boots、MountBody 預設必須使用 `MIRROR_RIGHT`。Hair、馬鬃、馬尾與披風可以是例外，但必須明確標記，不能因輸入圖左右不同就默默放行。

「左右對稱」指 RIGHT 與 LEFT 的方向對應關係，不是要求側面角色在同一張圖內左右兩側都呈現正面對稱。側面透視仍由 RIGHT 的原圖決定。

## 7. Normalizer 與驗證流程

### 7.1 允許的固定轉換

Normalizer 只能做下列已宣告操作：

1. 確認檔案為 RGBA PNG。
2. 依 Manifest 切割預期 frame。
3. 使用已知透明規則清理背景；不能對未知背景自行猜 chroma key。
4. 使用核准的整數倍 Nearest scale。
5. 將整個部件平移到模板 Anchor；平移量必須寫入報告。
6. 依 `MIRROR_RIGHT` 產生 LEFT。
7. 產生 slot mask 與 dye mask。
8. 輸出標準化 PNG 與 JSON 報告。

禁止任意拉伸、非整數平滑縮放、按畫面猜位置、把整張角色板拆成多個猜測部件，或在失敗後自動調整到看似通過。

### 7.2 必須通過的 Gate

- 檔案格式與尺寸正確。
- 每個 frame 不接觸相鄰 frame。
- 非透明像素不越過模板安全框。
- Anchor／腳底／馬蹄誤差不超過 1 px。
- 需要鏡像的部件，其 RIGHT／LEFT 幾何差異只允許抗鋸齒誤差。
- Body 的眼睛、臉、四肢與腳仍可讀。
- Hair 不進入鼻子與眼睛 protected mask。
- Armor 不覆蓋錯誤的頭部或披風區域。
- Boots 不漂浮、不穿入地面、不高於模板允許的膝部線。
- MountHead 不倒置、不覆蓋騎士臉部與軀幹的禁止區。
- MountBarding 不覆蓋騎士身體，且前後方向符合參考板。
- 染色只修改對應 dye mask，不依賴全圖色相猜測。
- 每個 frame 皆有可追溯的驗證結果。

輸出必須包含：原圖、標準化圖、四方向接觸表、Anchor guide、mask overlay、JSON 報告與失敗原因。只有 `PASS` 的 Manifest 才能加入 Catalog。

## 8. Recipe 與 Composer

### 8.1 `PaperDollRecipe`

Recipe 是 detached、唯讀、可重建的顯示快照，至少包含：

```text
gender
render_state: ON_FOOT | MOUNTED
body_template_id
layer_manifest_ids
mount_manifest_ids
dye_selection
animation_profile_id
```

Recipe 不保存原始圖路徑以外的 gameplay 資料，不保存裝備耐久、馬匹所有權、角色生命、Formation 或 Session 引用。缺少騎乘 Mount 時，`render_state = MOUNTED` 必須是 typed failure，不得顯示半匹馬或沿用步行 Body。

### 8.2 `PaperDollComposer`

Composer 的責任：

1. 在 `_ready()` 建立固定 Sprite pool。
2. `apply_recipe()` 只更新已驗證 texture、visibility、狀態尺寸與 offset。
3. `update_frame(direction, frame_x)` 同時更新所有可見 Sprite2D。
4. 每次方向切換完整重設 `flip_h` 與 z-order。
5. 依 `ON_FOOT`／`MOUNTED` 套用不同 frame size、vframes、viewport size 與 Anchor。
6. 清楚隱藏不適用的 mount layers。

Composer 不負責：

- `_process()` 動畫計時。
- 修正錯誤素材。
- 載入未驗證的原始圖。
- 裝備規則、性別規則、坐騎所有權。
- Texture2DArray 建立。
- Battle 單位分配。

Battle 仍只使用未來的 detached variant key 與既有 GPU MultiMesh；不把 Composer 或 Sprite pool 搬入戰場。

## 9. V2 動畫設計

### 9.1 動畫資料

保留現有單一幀控制方向，但把動作從「直接假定 8 格」提升成可驗證的 clip：

```text
PaperDollAnimationClip
  clip_id
  render_state: ON_FOOT | MOUNTED
  action: IDLE | WALK | RUN | ATTACK | HIT | DOWN | ...
  frame_sequence
  fps
  loop
  hold_last_frame
  event_frames
```

同一個 `frame_x` 是所有 layer 的共同邏輯索引。動畫播放器可以存在素材實驗室或 UI 預覽，但只能有一個 Timer／時間來源：

```text
Timer → AnimationClip → frame_x → Composer.update_frame()
```

不能讓 Hair、Armor、Weapon 或 Mount 各自播放。

### 9.2 動畫資產規則

- 每個已啟用動作必須同時驗證全部圖層、全部方向與步行／騎乘狀態。
- 所有圖層 frame count、frame size、Anchor 與方向語意必須一致。
- 攻擊、受擊、倒地等動作必須使用完整同步幀；不能用某一層的獨立動畫補救其他層。
- 尚未通過人工輪廓審核的動作，可以保留 deterministic fallback 供工程測試，但 UI 必須標示為 fallback，不能宣稱為正式美術。
- 攻擊事件只由動畫 clip 的 `event_frames` 提供給 UI／預覽，不改變 gameplay 戰鬥權威。

### 9.3 動畫驗收

每個 clip 必須輸出：

- 4 方向 × 全 frame contact sheet。
- 步行與騎乘各一份。
- Anchor overlay。
- layer visibility／z-order debug sheet。
- frame drift 報告。
- 人工審核截圖。

驗收重點是腳底／馬蹄接觸穩定、頭部不跳動、武器不瞬移、盾牌不穿身、馬頭不倒置，以及左右方向一致。

## 10. 染色契約

V2 的染色必須由顯式遮罩控制，禁止使用全圖色相猜測：

```text
HAIR_BROWS   頭髮與眉毛
ARMOR        護甲
BOOTS        鞋子
CAPE         披風
MOUNT        馬匹本體
MOUNT_BARDING 馬鎧
```

Hair mask 不得包含鼻子、臉或披風；Mount mask 不得包含騎士；Cape mask 不得包含頭髮與身體。染色驗證必須比較 mask 外像素，任何非目標層變色即 FAIL。

染色是預覽 Presentation state；在 PC gameplay owner 與 Persistence v2 尚未另行核准前，不得寫入存檔或 `GameSession`。

## 11. 素材實驗室與 UI 契約

素材實驗室必須直接顯示 V2 的實際契約，不提供容易誤導的舊版切換按鈕：

- 顯示目前狀態：`ON FOOT 64×64` 或 `MOUNTED 64×96`。
- 顯示 Anchor crosshair、template guide 與 frame 邊界。
- 顯示目前 layer 清單與 validation status。
- 體驗四方向、frame scrub、播放／暫停、動作與騎乘切換。
- 顯示每個部件的 manifest ID、尺寸、Anchor 與失敗原因。
- 輸出 V2 contact sheet，而不是只截 UI 畫面。
- `assets/doll/reference/` 產生的 calibrated board 是素材實驗室的唯一驗收基線；UI 以明確的 `reference_body_*` QA preset 顯示它，並標示 `REFERENCE PASS`。它不是可寫入 PC 外觀的正式 split 裝備路徑。
- 女性在目前沒有對應參考板時必須顯示 `REFERENCE FAIL` 並隱藏預覽，不得回退到錯位的舊拆件組裝。

所有部件選擇都先經 Catalog；UI 不直接讀 `art_source/`，也不直接修改 Resource。

## 12. 分階段 Gate

### Gate V2-0：契約鎖定（工程 PASS）

交付：

- 男女步行／騎乘素體草圖與像素模板。
- 確認四個 template 的 Anchor、foot／hoof line、protected masks。
- 確認 64×64／64×96 的來源與 baked sheet 策略。
- 確認 3 authored rows + LEFT mirror 是否正式採用。
- 確認 Boots layer 與 V2 z-order。

工程結果：`PASS`。V2 已採用 64×64／64×96、3 authored rows + LEFT mirror、Boots layer 與固定 z-order；正式美術若要修改這些數值，需開新契約版本，不得直接覆寫。

### Gate V2-1：素體驗收（參考板 PASS；拆件 FAIL）

- 男女步行與騎乘四模板通過尺寸、Anchor、方向、臉部可讀性與腳底／馬蹄接地。
- `assets/doll/reference/` 校準出的四個基線板已通過 4 方向 × 8 frame 的像素輪廓與 Anchor 驗收；現有 `reference_parts` split parts 仍未通過同一輪廓 Gate。

### Gate V2-2：標準化工具（PASS）

- Normalizer、Manifest 與 Validator 可產生可追溯 PASS／FAIL 報告。
- 錯誤素材停在 staging，不會被 Catalog 讀取。

### Gate V2-3：第一批部件（參考板 PASS；拆件 FAIL）

最小包：

- 男女 Body。
- 至少四種 Hair。
- 一件男女版輕甲。
- 一件 Unisex 重甲。
- Boots、Helmet、Cape、Weapon、Shield。
- 一匹 Mount 的 Tail、Body、Head 與 Barding。

校準參考板的步行／騎乘組裝已通過；split-part 部件的逐層遮罩、染色、換裝與輪廓仍未通過，因此本 Gate 尚未完成。

### Gate V2-4：Composer／Recipe（工程 PASS；參考板 PASS；拆件視覺待補）

- Composer 支援兩種狀態尺寸。
- 固定 Sprite pool 不增生。
- 方向、鏡像、z-order、Anchor 與 mounted visibility 通過 headless 測試。
- calibrated reference composite 只作明確 QA preset；不會被誤認為正式 split fallback。

### Gate V2-5：動畫（工程 PASS；美術 clip 簽核另列）

- IDLE、WALK、RUN、ATTACK、HIT、DOWN 至少各有一個可驗收 clip。
- 單一幀時鐘、所有 layer 同步、接觸表與人工審核通過。
- fallback 與正式 authored action 清楚分離；本次 `IDLE/WALK/RUN/ATTACK/HIT/DOWN` 均有 deterministic frame sequence，並由單一 Composer frame API 驗證同步。尚未提供新繪製的逐動作分層美術，不能把工程 fallback 稱為正式 authored action。

### Gate V2-6：未來 Battle variant

只有在 Unit 視覺 snapshot 與世界尺寸契約另行完成後，才評估純 Image variant、Texture2DArray 與既有 MultiMesh shader 接線。V2 不直接建立 9,000 個角色 Node。

## 13. V1 遷移策略

1. 保留 V1 檔案與測試，直到 V2-4 通過。
2. 新增 V2 Manifest／Template／Validator，先以平行資料格式驗證，不直接覆寫 V1 Catalog。
3. V2 素材通過後，讓角色生成器改讀 V2 Catalog；UI 不保留 V1 完整板切換按鈕。
4. 將 `reference_match` 完整板降級為離線 QA fixture。
5. 將 V1 的 11 層 Composer 改為 V2 layer contract，加入 Boots 並支援狀態尺寸。
6. 更新接觸表、runtime capture、headless verifier 與素材實驗室報告格式。
7. 重新執行既有 World／Battle 邊界測試，確認沒有引入 Soldier Node、第二套角色權威或 Session mutation。
8. V2 完成後才決定是否移除 V1 fallback；不得在 V2 尚未通過前刪除可追溯的 QA fixture。

## 14. 必須在 Gate V2-0 決定的項目

以下項目不能由 Composer 或 AI 自行猜測：

1. 騎乘 Anchor 的正式 `(x, y)`。
2. 步行素材是否在 Texture2DArray 儲存階段補透明至 64×96。
3. 來源是否固定三列加鏡像 LEFT，或允許四列獨立作畫。
4. Boots 是否允許長靴延伸至膝部以上。
5. Cape、Hair、馬鬃與馬尾的左右獨立例外規則。
6. 每個正式動作的 frame sequence、fps 與 event frame。
7. Mount Barding 是否固定為單一層，或拆成 front／body／rear 三層。
8. 透明邊緣與抗鋸齒的 alpha 閾值。

## 15. 實作與驗證證據（2026-08-16）

V2 standalone 工程交付物如下：

- `scripts/data/paper_doll_v2_contract.gd`：狀態尺寸、Anchor、方向、12 層與 z-order 單一契約。
- `scripts/data/paper_doll_v2_body_template.gd`、`paper_doll_v2_asset_manifest.gd`、`paper_doll_v2_validator.gd`、`paper_doll_v2_catalog.gd`：素體、部件 admission 與 Catalog 邊界。
- `scripts/data/paper_doll_v2_recipe.gd`、`paper_doll_v2_animation.gd`：detached recipe 與單一幀動畫序列。
- `scripts/ui/paper_doll_v2_composer.gd`：固定 12 個 `Sprite2D` pool、`centered=false`、狀態 offset、LEFT mirror 與 z-order；沒有 `AnimatedSprite2D` 或 `_process`。
- `scripts/tools/build_paper_doll_v2_pack.gd`：從 `assets/paper_doll/reference_parts/` 產生標準化 V2 pack；目前報告為 4 templates、66 PNG entries、0 failures，並把鞋子由已宣告的 armor bottom band 固定抽出。
- `scenes/ui/PaperDollV2Lab.tscn` 與 `scripts/ui/paper_doll_v2_lab.gd`：獨立素材實驗室，直接顯示 V2 狀態、尺寸、Anchor、方向、frame 與 dye。
- `scripts/tests/paper_doll_v2_test.gd`、`paper_doll_v2_lab_test.gd`：headless 契約、固定 pool、recipe、mount visibility、LEFT mirror、染色隔離與每個 action 的同步 frame 檢查。
- `scripts/tools/capture_paper_doll_v2_visual.gd`、`capture_paper_doll_v2_lab.gd`：由 calibrated QA preset 產生 GPU contact sheet 與 UI 預覽輸出。
- `scripts/tools/build_female_reference_calibrated_sheets.gd`：以女性三視角參考板固定去背、分割、側面鏡像與 Anchor 標準化，輸出男女共用格式的四張女性 reference-match sheets。
- `scripts/tools/verify_paper_doll_v2_reference.gd`：以 `assets/doll/reference/` 產生的 calibrated `reference_match` sheets 做 4 方向 × 8 frame 的像素輪廓／BBox 驗收；目前男女共 `256/256` checks PASS，報告在 `.visual_captures/paper_doll_v2/reference_acceptance.json`。

開啟 V2 實驗室：在 Godot 編輯器開啟 `scenes/ui/PaperDollV2Lab.tscn`，使用 `F6` 執行目前場景。現有 `Main.tscn`／V1 `CharacterCreator` 不會被這個入口偷偷切換；要把 V2 接到 PC 外觀頁，必須另開 V1→V2 遷移變更與驗收。

最後一次 Godot 4.6.2 驗證的預期結果：

```text
PAPER_DOLL_V2_PACK_PASS files=66 entries=66
PAPER_DOLL_V2_TEST_PASS templates=4 manifests=16 layers=12
PAPER_DOLL_V2_LAB_TEST_PASS state=1 gender=0 frame=4
FEMALE_REFERENCE_SHEETS_PASS sheets=4
PAPER_DOLL_V2_REFERENCE_CAPTURE_PASS captures=8
PAPER_DOLL_V2_LAB_CAPTURE_PASS outputs=4
PAPER_DOLL_V2_REFERENCE_PASS checks=256 groups=8
```

輸出目錄：`.visual_captures/paper_doll_v2/`。GPU strict verifier 的 process exit code 為 `0`；256 個檢查的最小 IoU 為 `1.0`、最大 BBox 位移為 `0 px`。這次驗證同時涵蓋男女、步行／騎乘、無武器／武器版、DOWN、UP、RIGHT、LEFT（LEFT mirror）與全部 8 個 frame，避免只驗單張 DOWN 圖造成假通過。

## 16. 完成定義

V2 的完成分成兩個不能混稱的層級：

**本次已完成的工程閉合**

- 每個已收錄部件都有 Manifest、Anchor、尺寸與可追溯驗證報告。
- 錯誤尺寸／狀態／格式部件無法進入 Catalog。
- 步行 `64×64`、騎乘 `64×96` 的 Composer 預覽與接觸表一致。
- LEFT mirror、z-order、固定 12 Sprite pool、單一幀控制器與染色群組已通過 headless／GPU 檢查。
- V2 實驗室不建立 gameplay owner，也不污染 `GameSession`；Battle 仍沒有個人 Soldier Node、PaperDollComposer 或 Sprite2D。
- 文件、程式、素材 pack 與驗證報告的尺寸與命名契約一致。

**尚未宣稱完成的美術／產品 Gate**

- 目前通過的是白髮銀甲男性與女性完整參考板基線；髮型／護甲／鞋子／武器／盾牌／馬鎧的 split-part 可替換版本仍需逐件重建、遮罩驗證與人工美術簽核。
- PC 外觀 persistence、正式 gameplay equipment／mount owner、戰場 GPU variant 與 9,000 人 Battle 接線仍保留在 Gate V2-6 之後。

因此本文件目前標記的是 **V2 校準參考基線已通過，但自由換裝的 split-part 美術尚未完成**；不得把 QA composite PASS 誤稱為整套紙娃娃產品完成。

## 17. Component Pack 02 規格

第一批新增部件的槽位、命名、內容框、Anchor、鏡像、Z-Order、染色遮罩與進件 Gate 已獨立鎖定於：

- `PAPER_DOLL_V2_COMPONENT_PACK_02_SPEC.md`（美術／工程共用規格表）
- `assets/paper_doll/v2/pack_02_spec.json`（Normalizer／Validator 使用的機讀規格）

Pack 02 目前是 `STAGING_SPEC_ONLY`。新素材必須先寫入 `assets/paper_doll/v2/staging/pack_02/`，通過 V2 Validator、GPU contact sheet 與人工輪廓審核後，才可進入正式 `parts/` 與 `manifest.json`；不得因新增素材而改動已通過的男女 reference-match 基線。
