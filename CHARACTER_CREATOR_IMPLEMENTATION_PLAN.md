# Worldgoing 角色生成器與紙娃娃素材實驗室實作計畫

## 2026-08-13 目前實作狀態（可直接驗收）

### 已完成

- `CharacterCreator` 是 presentation-only 素材實驗室；不寫入 `GameSession`、Persistence、gameplay Item/Mount 或 Battle。
- `PaperDollPreviewDraft` 可逐槽替換 Body、Armor、Hair、Helmet、Cape、Weapon、Shield、Mount Barding，以及三個坐騎部件；正式預設為白髮銀甲，Helmet/Shield 可由選單主動加入。
- `PaperDollComposer` 只建立並重用固定 11 個 `Sprite2D`，統一控制 8×3 影格、LEFT 鏡像、Anchor `(32,56)`、Z-order；禁止 `AnimatedSprite2D`。
- 動作選單可選 `IDLE/WALK/RUN/ATTACK/SPRINT_ATTACK/WORK/HIT/DOWN`。尚未有通過人工輪廓審核的逐動作分件美術時，`PaperDollActionSheet` 以同一套部件產生同步 fallback；UI 明確顯示 `reference-locked split layers + synchronized fallback`。
- 染色分組已完成且互斥：
  - `HAIR_BROWS`：頭髮與眉毛同色；眼睛像素保持不變。
  - `ARMOR`：鎧甲與 Mount Barding。
  - `CAPE`：披風。
  - `MOUNT`：馬尾、馬身、馬頭；不會改到馬鎧。
- 替換部件與染色皆為暫時預覽狀態，不污染原始 `Texture2D`；每個染色路徑先複製 `Image`。
- 目前唯一的開啟預設已鎖定為「白髮／銀甲／深海軍藍披風」；Horse Dye 只在騎乘時影響馬匹，部件選單仍完整保留。
- 已生成新的白髮銀甲攻擊板候選 `art_source/paper_doll/action_generated/worldgoing_attack_board_v2.png`，並成功離線拆出候選 sheets；因人工檢視仍未達正式分件品質，維持候選區，不接入 Catalog。

### 驗收證據

- Godot 4.6.2 editor scan：PASS，無腳本解析錯誤。
- `scripts/tests/character_creator_test.gd`：PASS，10 cases；涵蓋逐槽替換、8 個動作、固定 Sprite pool、四方向、Anchor、Z-order、染色與 UI lifecycle。
- `scripts/tools/verify_paper_doll_actions.gd`：PASS，8 actions × on-foot/mounted；逐方向確認 frame row、LEFT mirror、Z-order 與部件同步。
- `scripts/tools/verify_paper_doll_visual.gd`：PASS，256 runtime frames；另外檢查 alternate alpha geometry、chroma-key、armor/body、horse clearance 與 dye ownership。
- GPU capture：PASS，最新輸出位於 `.visual_captures/paper_doll/`，包含 `character_creator_split_on_foot_default_white_hair.png`、`character_creator_alternate_mounted_dyes.png`、`character_creator_split_mounted_sprint_dyed.png`；人工確認預設配色與獨立坐騎染色。

### 尚未完成／不得誤標為完成

- 目前 7 個非 IDLE 動作仍是可驗收的同步程式化 fallback，不是逐動作、逐部件的正式 ChatGPT 美術。第一張 ImageGen WALK board 雖通過尺寸與去背，但人工輪廓／比例未通過，因此沒有掛進正式 Catalog。
- RUN、ATTACK、SPRINT_ATTACK、WORK、HIT、DOWN，以及 mounted 版本的正式分件動作素材仍需生成、拆層、對位、人工檢視後才可啟用。
- PC 外觀持久化、gameplay equipment/mount owner、Battle `Texture2DArray`/shader 接線仍不在本計畫切片。

### 下一個實作切片

1. 以 `assets/doll/reference` 的白髮銀甲與騎乘範例為唯一比例基準，生成一個動作 board；禁止直接把完整 composite 當成單一部件。
2. 先拆成每個 render layer 的 512×192 RGBA8 sheets，再跑去背、64×64 frame、Anchor、alpha mask、方向同步與染色回歸。
3. 只有通過數值 gate 且人工查看四方向 contact sheet 與 GPU capture 後，才將該動作加入 `APPROVED_AUTHORED_ACTIONS`；失敗素材留在 `art_source/paper_doll/action_generated/`，不得進正式 Catalog。
4. 每次啟用一個動作後，重跑 editor、character creator、action QA、visual QA 與 GPU capture；任何錯位都維持 fallback，不得退回完整板按鈕。

狀態：Gate 0、Milestone 1 工程驗證完成；角色生成器正式預覽只驗收白髮銀甲完整 reference

日期：2026-08-11

`PROJECT_ARCHITECTURE.md` 仍是最高架構真實來源。目前已完成角色生成器的 Presentation 素材實驗室、reference-derived Recipe／Composer／contact sheet 與聚焦測試；`artgate1_*` 22 張 runtime PNG 已由專案 `assets/doll/` 與 ChatGPT reference board 產出並接入 Catalog，但合成後的視覺品質仍未通過人工驗收，正在重做對位。Character、PC 權威外觀、Equipment、Mount gameplay、擴充紙娃娃美術與 Battle shader 尚未實作。

Gate 0 已同步架構與規格文件；Milestone 1 已新增程式與場景，但沒有修改存檔格式或建立 PC gameplay owner。

## 1. 審核結論

先做角色生成器是合適的；第一版以白髮銀甲 reference 作為唯一可見生成器輸出，分層候選只由離線 QA 驗證：

1. **PC 外觀模式**：編輯並保存角色固有外觀，只包含性別、身體外觀 ID 與髮型外觀 ID。
2. **素材實驗室模式**：生成器以白髮銀甲作為預設，顯示由 Catalog 解析的獨立分層部件、動作與暫時染色；完整 reference 仍由 contact sheet 與離線 verifier 驗收，不作正式輸出。

這個切分避免在 Equipment、Mount 與 Character gameplay 尚未建立前，讓一個開發工具搶先成為其資料 owner。角色生成器會產生可重用的外觀快照與已解析 Recipe；目前的 World／Region Party 標記維持原狀，Battle 也不在本計畫接入紙娃娃。

```text
PC 外觀模式  -> detached draft -> GameSession.apply_player_appearance() -> 存檔
                                      |
                                      +-> 只保存穩定 ID，不保存 Texture／Node

素材實驗室    -> preview draft -> Catalog -> Recipe -> Composer／contact sheet
                                      |
                                      +-> 沒有任何 Session 寫入路徑
```

## 2. 第一版範圍

### 2.1 必須完成

- 一個可重用的 `CharacterCreator` 全螢幕覆蓋層，含「PC 外觀」與「素材實驗室」頁籤。
- 一個固定 11 層 `Sprite2D` 節點池的 `PaperDollComposer`；切換選項時只改 texture、visibility、frame 與 z-index。
- PC 外觀的 Session owner、原子套用、取消不寫入，以及存檔 round-trip。
- 可列舉 Catalog 全部素材的檢查面板、逐項上一個／下一個、播放／暫停、方向、影格與騎乘切換。
- 由純 `Image` 合成的四方向 contact sheet 匯出，供自動檢查與 ChatGPT 視覺複核。
- 一組 reference-derived runtime 素材，以及一組合成測試材質供負向／格式驗證使用。
- ChatGPT 美術的 staging、正規化、Catalog 登錄與驗收 Gate。

### 2.2 明確不做

- 不建立 Character 屬性、種族、職業、技能、數值、背包或 NPC 生成框架。
- 不保存盔甲、頭盔、披風、武器、盾牌、坐騎或騎乘狀態；它們只存在素材實驗室草稿。
- 不新增 gameplay `ItemData`、`MountData` 或 Equipment owner。
- 不把 Texture、Resource 路徑、Recipe、目前方向、影格、播放速度或 UI 選項寫入存檔。
- 不做 Battle Texture2DArray、GPU shader、變體快取、SubViewport Bakery 或每名士兵 Node。
- 不一次測試所有裝備排列組合；採「每件素材獨立驗收 + 固定完整疊層壓力組合」，避免組合爆炸。
- 不在第一版加入臉型、五官、膚色染色、髮色染色、隨機生成或角色命名；等實際美術契約需要後再擴充。

## 3. 資料與顯示 owner

| Owner | 保存內容 | 允許依賴 | 禁止保存／依賴 |
| --- | --- | --- | --- |
| `GameSession` | `player_appearance` 的權威副本 | 純資料型別 | Texture、Node、Catalog、UI 草稿 |
| `PlayerAppearanceData` | `gender`、`body_visual_id`、`hair_visual_id` | 穩定 ID 與基本驗證 | 裝備、坐騎、方向、影格、資源引用 |
| `PaperDollCatalog` | 已核准的顯示素材定義與穩定查找 | `Resource`、Texture | gameplay 所有權、耐久、能力值 |
| `PaperDollPreviewDraft` | UI 本次預覽的所有選擇 | Catalog ID | Session mutation、存檔 |
| `PaperDollRecipe` | 已解析、邏輯唯讀的 11 層 Texture 快照 | 顯示型別 | gameplay Resource、可變共用狀態 |
| `PaperDollComposer` | 11 個可重用 Sprite 與瞬時 frame／facing | Recipe | PC 真實資料、裝備規則、存檔 |
| `CharacterCreator` | 控制項、草稿、動畫 Timer、檢查結果 | Session command、Catalog、Composer | 直接改 Session 欄位、地圖狀態 |

### 3.1 PC 外觀快照

新增 `PlayerAppearanceData extends RefCounted`，第一版只有：

- `gender: Gender`，只接受 `MALE` 或 `FEMALE`。
- `body_visual_id: StringName`。
- `hair_visual_id: StringName`。

它是資料值物件，不使用可被 Godot 快取共用的 `.tres` 作為玩家存檔狀態。`copy()` 必須產生獨立副本；UI 開啟時取得副本，按「套用」前不碰權威資料。

`GameSession.apply_player_appearance(snapshot) -> int` 是唯一提交入口，回傳 `PlayerAppearanceData.ValidationCode`：

- `OK`
- `NULL_SNAPSHOT`
- `INVALID_GENDER`
- `EMPTY_BODY_VISUAL_ID`
- `EMPTY_HAIR_VISUAL_ID`

成功時 Session 保存深拷貝，避免 UI 後續修改草稿污染權威資料。資料層只驗證結構，不載入 Catalog 或 Texture；Catalog 缺少某個舊 ID 時由顯示層使用預設素材並報告問題，不得靜默改寫存檔。

### 3.2 顯示素材型別

不建立假 gameplay Item／Mount。第一版只需要下列 presentation-specific 型別：

- `PaperDollLayerVisual extends Resource`
  - `visual_id`
  - `render_layer`
  - `gender_policy: GENDERED | UNISEX`
  - 步行與騎乘的 male／female／unisex Texture 欄位
  - `resolve(gender, is_mounted)`
- `PaperDollMountVisual extends Resource`
  - `mount_visual_id`
  - tail／body／head 三個 mounted-unisex layer visual
- `PaperDollCatalog extends Resource`
  - 已核准 layer visuals 與 mount visuals
  - 穩定 ID 查找、按 layer 列舉、重複 ID 檢查、預設 body／hair 查找
- `PaperDollPreviewDraft extends RefCounted`
  - gender、is_mounted、各 render layer 的 visual ID、mount visual ID
  - 僅為 UI 可變草稿，永不持久化
- `PaperDollRecipe extends RefCounted`
  - 固定 render-layer 索引對應的已解析 Texture
  - 建立後視為唯讀，不保留 Catalog、Draft 或 gameplay 物件

`UNISEX` 是視覺素材政策，不等於 gameplay 的 Heavy Armor 規則。未來 Equipment owner 建立後，才由 gameplay 將 Heavy Armor 映射到 UNISEX visual；素材實驗室只驗證標記為 UNISEX 的項目在男女選擇下解析到同一套貼圖。

## 4. 紙娃娃顯示契約

### 4.1 Sheet、方向與 Anchor

- 每格固定 `64 × 64`，sheet 固定 `8 × 3`，完整尺寸 `512 × 192`。
- Row 0 = DOWN、Row 1 = UP、Row 2 = RIGHT。
- LEFT 使用 RIGHT row 並令所有可見 Sprite `flip_h = true`；離開 LEFT 時必須復位為 `false`。
- 所有 Sprite 設定 `hframes = 8`、`vframes = 3`、`centered = false`。
- 所有步行與騎乘素材共用 `offset = Vector2(-32, -56)`，腳底／馬蹄 Anchor 為 frame 內 `(32, 56)`。
- Composer 設定 nearest texture filtering，避免像素縮放模糊。

步行角色不是把 32×32 圖直接放在 64×64 正中央。原 32×32 腳底 Anchor `(16, 32)` 對齊新 Anchor `(32, 56)` 時，內容左上角應落在 `(16, 24)`；ChatGPT 素材與正規化工具都必須遵守此對齊。

### 4.2 固定 render layers

Composer 只在 `_ready()` 建立一次 11 個 `Sprite2D`：

| Layer | DOWN | UP | RIGHT | LEFT |
| --- | ---: | ---: | ---: | ---: |
| MountTail | -10 | -10 | -10 | -10 |
| Cape | -5 | 15 | 5 | 5 |
| MountBody | 0 | 0 | 0 | 0 |
| Body | 10 | 10 | 10 | 10 |
| Armor | 11 | 11 | 11 | 11 |
| Hair | 12 | 12 | 12 | 12 |
| Helmet | 13 | 13 | 13 | 13 |
| Weapon | 14 | -1 | 14 | -1 |
| Shield | 15 | -2 | -2 | 15 |
| MountHead | 20 | -5 | 20 | 20 |
| MountBarding | 21 | 1 | 21 | 21 |

`apply_recipe()` 只更新 Texture 與 visibility。`update_frame(facing, frame_x)` 驗證 `frame_x` 在 `0..7`，再一次更新所有 Sprite 的 `frame_coords`、`flip_h` 與 z-index；不得使用 `AnimatedSprite2D`，也不得為每層建立獨立動畫播放器。

## 5. 角色生成器 UI

### 5.1 掛載與輸入

- 新增 `scenes/ui/CharacterCreator.tscn`，根節點為全螢幕 `CanvasLayer/Control`。
- `Main` 是顯示組裝點：第一次開啟時才實例化角色生成器，之後重用同一實例。
- 暫時在既有 `DebugUI` 放一個「角色生成器／素材實驗室」按鈕；不占用 `B`、`C`、`T`、`ESC` 等現有地圖操作鍵。
- 開啟覆蓋層時由 `Main` 暫停 `NavigationController` 的 `_unhandled_input`；關閉時必須恢復。不能靠 UI 焦點碰巧攔住地圖輸入。
- `ESC` 在有未套用 PC 草稿時等同取消並關閉；素材實驗室一律直接丟棄草稿。
- 每次開啟 PC 模式都從 `navigation_controller.get_session()` 取得目前 Session 的新副本，避免未來讀檔替換 Session 後保留舊引用。

### 5.2 PC 外觀模式

- 性別切換。
- Body 與 Hair 選擇器，只顯示 Catalog 中對應 layer 且支援該性別的項目。
- 中央即時預覽與播放／暫停；方向與影格只是 View state。
- 「套用」：先做 Catalog 可解析檢查，再呼叫 Session command；成功後刷新原始快照。
- 「取消」：丟棄草稿，不呼叫 Session。
- 若切換性別後目前 Body／Hair 不再有效，使用 Catalog 中明確標記的該性別預設項；不得依陣列第一筆或檔名猜測。

### 5.3 素材實驗室模式

- 角色生成器以 `reference_parts` 的拆分部件作正式預覽，並以白髮銀甲作為 deterministic default；`reference_match_body_on_foot_unisex.png` 與 `reference_match_body_mounted_unisex.png` 只作離線人工驗收 fixture。
- UI 不提供「Accepted reference／Layer preview」切換按鈕；金髮紫披風及其他未通過對位的分層組合只保留在離線 `reference_parts` Catalog，避免誤成為驗收畫面。
- Mounted 開關只切換 approved reference 的步行／騎乘板，並保留同一 Anchor、方向與 frame 控制契約。

- Body、Armor、Hair、Helmet、Cape、Weapon、Shield、Mount、MountBarding 的選擇器節點保留給離線 Catalog QA，但正式生成器畫面隱藏並鎖定 disabled，不得切換到未通過對位的分層組合。
- Mounted 開關只切換 approved reference 的步行／騎乘板；未選 Mount 時不可啟用 mounted，並顯示可讀錯誤。
- DOWN／UP／RIGHT／LEFT 四方向按鈕。
- frame 0–7 滑桿、上一格／下一格、播放／暫停與 FPS（1–16）控制。
- approved reference 支援步行／騎乘、四方向與統一 frame row；若 reference sheet 的 8 格是靜態複製，播放／scrub 控制會誠實停用，避免假動畫。關閉視窗時 Timer 停止。
- `Check All`、`Export Contact Sheets` 與 failure 導覽只保留給離線測試入口；正式預覽介面不顯示它們，避免把未通過對位的候選重新帶回驗收畫面。

素材實驗室不得取得 `GameSession.apply_player_appearance` 的 Callable，也不得在切換頁籤時把裝備／坐騎選擇拷入 PC 草稿。這項隔離需要自動測試，而不只靠程式註解。

## 6. ChatGPT 美術工作流

### 6.1 目錄與輸入邊界

```text
art_source/paper_doll/              # ChatGPT 原始輸出與參考圖；以 .gdignore 排除 Godot 匯入
assets/paper_doll/parts/            # 通過尺寸與對齊 Gate 的 runtime PNG
assets/paper_doll/catalog/          # LayerVisual、MountVisual 與 Catalog .tres
.visual_captures/paper_doll/        # 本機 contact sheets／UI capture，不自動提交
```

ChatGPT 先小批量產生，再由確定性工具組裝或正規化成 runtime sheet。工具只能做明確的裁切、透明畫布放置、鏡像與 frame 打包；不得自動拉伸、猜 Anchor 或修補缺格，否則應直接 FAIL 並退回重生／修圖。

### 6.2 第一批最小素材

第一批只求完整走通契約：

- male、female 各一個 base body。
- 至少一個 gendered 或 unisex hair。
- Armor、Helmet、Cape、Weapon、Shield 各一個。
- 一套明確標記為 UNISEX 的盔甲素材，用來驗證性別解析。
- 一匹 Mount（tail、body、head）與一個 MountBarding。
- 每個角色／裝備部件都有 on-foot 與 mounted sheet；Mount 部件只需 mounted sheet。

通過第一批後才擴充風格與數量。視覺 ID 一旦進入 PC 存檔測試就視為穩定契約；改圖可以覆蓋同 ID，改 ID 必須有明確遷移或 alias。

### 6.3 每批素材驗收

自動檢查：

- ID 非空、唯一，並符合小寫 ASCII `snake_case`。
- PNG 可讀、具 alpha、尺寸精確為 `512 × 192`。
- `GENDERED` 的必要 male／female、on-foot／mounted 組合齊全。
- `UNISEX` 的必要 unisex、on-foot／mounted 組合齊全，男女解析結果相同。
- 每個 sheet 的 24 個 frame 都可切出；必要 frame 不能全透明。
- Catalog 的預設 male／female body 與 hair 都存在且 layer 正確。
- Mount 必須同時具備 tail、body、head，且只能在 mounted Recipe 顯示。

視覺檢查：

- Contact sheet 顯示 `(32, 56)` Anchor 與 64×64 frame 邊界。
- 四方向、八格動畫沒有身體／裝備相對滑動、抖動或越格污染。
- LEFT 的持物手與遮擋符合 LEFT z-order，不只是畫面方向相反。
- 分別檢查「每件素材 + 標準身體」；另檢查一組全層步行與一組全層騎乘壓力配方。
- ChatGPT 可協助看 contact sheet 與 runtime capture，但自動尺寸／ID／解析 PASS 才是進 Catalog 的前提。

## 7. 存檔契約

現有 `SessionSaveData.FORMAT_VERSION == 1` 且 wire schema 採明確白名單。實作 PC 外觀時必須：

1. 將格式升為 v2，在 top-level `player_appearance` 保存 `gender`、`body_visual_id`、`hair_visual_id`。
2. v2 capture／wire／parse／validate／restore 全部逐欄位處理，不序列化物件或任意 Dictionary。
3. 提供最小 v1 → v2 讀取遷移：舊檔補上明確的預設 PC 外觀；不因新增外觀欄位讓既有 v1 檔直接損毀。
4. v2 的空 ID 或非法 gender 以 typed persistence failure 拒絕；Catalog 暫時缺圖不應讓資料檔無法讀取。
5. 測試存檔後再修改原 UI draft，確認 restored Session 與已套用 Session 都不受影響。

## 8. 分階段實作與 Gate

### Gate 0：架構與格式鎖定

狀態：**完成（2026-08-11）**

修改：

- `PROJECT_ARCHITECTURE.md`：新增最小 PC 外觀 owner，以及角色生成器／素材實驗室的 Presentation 邊界。
- `ARCHITECTURE_STATUS.md`：分開標示 reference-derived Art Gate 1 素材實驗室已實作，以及 PC 權威外觀、擴充美術庫與 Battle 接線仍未實作；不得用局部完成掩蓋後續範圍。
- 本文件與紙娃娃總計畫：同步 sheet、Anchor、Layer 與優先順序。

通過證據：owner、未來 v2 存檔欄位、正式 male／female 預設 visual IDs、11 層、512×192 來源 sheet、Anchor、LEFT component flip 與 ChatGPT 輸入契約均已寫入最高架構文件及 V3 規格；synthetic `debug_*` ID 明確禁止進入存檔。

### Milestone 1：顯示核心與素材實驗室

狀態：**完成（2026-08-11）**

已新增：

```text
scripts/data/paper_doll_layer_visual.gd
scripts/data/paper_doll_mount_visual.gd
scripts/data/paper_doll_catalog.gd
scripts/data/paper_doll_preview_draft.gd
scripts/data/paper_doll_recipe.gd
scripts/ui/paper_doll_composer.gd
scripts/ui/paper_doll_contact_sheet.gd
scripts/ui/character_creator.gd
scenes/ui/CharacterCreator.tscn
scripts/tests/character_creator_test.gd
```

已修改：`scripts/main.gd`、`scripts/ui/debug_ui.gd`、`scenes/ui/DebugUI.tscn`。`Main.tscn` 不需修改；`Main` 在第一次按下入口時才 lazy instantiate，之後重用同一實例。

工程通過證據：`character_creator_test.gd` 10/10 PASS；approved reference 的步行／騎乘、方向／鏡像、Anchor 與 UI 啟動均由實際 Godot runtime capture 驗證。`reference_parts` Catalog 仍由離線 `verify_paper_doll_visual.gd` 逐格檢查 256 格與 42 張 contact sheet；這些是工程護欄，不等同於美術驗收。

### Art Gate 1：ChatGPT 參考素材導入

目前對位修正集中在 reference packer：armor 不再裁掉鞋底，並以 Body 每條 scanline 作為水平骨架；側向 weapon／shield 以手持側／背側偏移；騎乘 DOWN/UP 的馬頭僅在騎士胸口以下覆蓋。逐格 QA 同時驗證中心線、腳底線、silhouette 外溢與側向武器位置，避免「測試有像素但頭／衣服／武器仍漂移」的假通過。

狀態：**工程管線完成；視覺驗收未通過（2026-08-11）**。`assets/paper_doll/reference_parts/` 的 22 張 `512×192` RGBA8 runtime PNG 由 `scripts/tools/build_paper_doll_reference_pack.gd` 從 reference board 去背、裁切、nearest 對齊後產出；pack tool 會先檢查 `assets/doll/` 六張專案 reference image 仍存在，避免素材來源被悄悄換掉。`PaperDollCatalog.create_art_gate1_catalog()` 已優先載入這些 Texture，缺檔才回退到工程用 procedural fallback；但整體角色／坐騎合成仍需人工視覺複核與對位重工。

通過證據：角色生成器可由拆分 Catalog 開啟白髮銀甲預設，mounted toggle 切換同一組拆分部件的馬匹層且保留 frame；UI 不提供完整板切換。`reference_match` 仍由 Catalog、42 張 contact sheets 與 verifier 作離線驗收 fixture。

reference source：`art_source/paper_doll/reference_generated/` 的角色／裝備／坐騎 reference board；runtime pack 與 UI 仍沿用同一 Catalog／Composer／ContactSheet，不另建第二套渲染管線。

生成器初始素材實驗室預覽會清除 Helmet／Shield，保留 Body、Armor、Hair、Cape、Weapon 以確保臉部與 Anchor 可直接目視；Helmet／Shield 仍可由選擇器加入，完整壓力配方與逐格 QA 不省略任何 layer。

### Milestone 2：PC 外觀 owner、套用與持久化

預計新增：

```text
scripts/data/player_appearance_data.gd
```

預計修改：

```text
scripts/core/game_session.gd
scripts/persistence/session_save_data.gd
scripts/persistence/persistence_service.gd
scripts/tests/persistence_test.gd
scripts/ui/character_creator.gd
```

通過條件：PC Apply 成功保存獨立副本；Cancel 零 mutation；素材實驗室零 Session mutation；v2 round-trip 與 v1 migration PASS；非法資料有 typed failure；替換／重建 CharacterCreator 不改變 Session 外觀。

### Milestone 3：擴充素材與動畫回歸

ChatGPT 依小批次擴充 Catalog。每批都執行相同自動檢查、逐素材 contact sheet、兩組完整疊層 capture 與實際 Forward Plus UI capture；不得因素材量增加另建第二套 Catalog 或 Composer。

通過條件：Catalog 全量 PASS，沒有未登錄 runtime PNG、重複 ID、缺 pose／gender 變體或視覺驗收失敗項。

### 後續 Gate：不屬於本計畫

只有當 Character／Equipment／Mount gameplay owner 與 Unit snapshot 已明確落地後，才重新審核紙娃娃總計畫的離線 Image 合成、Texture2DArray 與 Battle MultiMesh shader。角色生成器的 Sprite2D／SubViewport 不得直接搬進 9,000 人戰場。

## 9. 驗證矩陣

| 類別 | 必驗項目 | 證據 |
| --- | --- | --- |
| Data | snapshot copy、typed validation、PC Apply／Cancel | headless assertions |
| Catalog | ID、layer、gender policy、pose、尺寸、預設項 | 全 Catalog 報告 |
| Composer | 11 nodes、8×3、4 facing、flip reset、Anchor、z-order | synthetic texture assertions |
| Animation | 單一 Timer、同步 frame、pause／scrub、切換保留 frame | headless + UI capture |
| Lab isolation | 所有裝備／坐騎操作前後 Session 深比較一致 | headless assertions |
| Persistence | v2 round-trip、v1 migration、corrupt typed failure | `persistence_test.gd` |
| Visual | 每素材 contact sheet、步行／騎乘全層壓力配方 | `.visual_captures/paper_doll/` |
| Runtime UI | 開關、ESC、輸入停用／恢復、Forward Plus 實畫面 | 實際執行與 exit code |

- `scripts/tools/verify_paper_doll_visual.gd` 已通過逐格工程視覺護欄：不經 UI／guides，直接合成完整壓力配方與臉部可讀預覽配方，男女各跑步行／騎乘 4 方向 × 8 影格（共 256 格），檢查去背殘留、影格越界、Anchor 下緣、Body head→torso→feet 連通、Armor 肩線／中心／腳底／silhouette 外溢、側向 weapon／shield 手持側、Armor/Body face ROI 交集、頭部可見性與馬頭／馬身關係，並輸出放大 QA 圖至 `.visual_captures/paper_doll/qa/`。披風各方向在打包時清除高於頭部的肩線溢出，UP 列另保留既定 z-index 並清出頭部開口；MountHead 只允許 DOWN/UP 胸口以下前景重疊，MountBarding 不得覆蓋騎士。這仍不是最終美術簽核。

單元與資料驗證 PASS 不等於美術驗收 PASS；headless 測試也不取代 Forward Plus 畫面檢查。騎乘素材特別要求：`MountBarding` 即使維持規格 z-index，也必須在 pack 階段對 Body+Armor 建立透明 rider-clearance；`MountHead` 僅允許 DOWN/UP 胸口以下的前景重疊，不能覆蓋臉部。否則會出現「頭在馬腿上」的假通過。最終交付需分別報告自動測試、實際 UI capture 與仍需人工判斷的動畫美感。

本輪另補上 row-packed 素材的漏像素 gate：reference packer 在 trim 前清除 Helmet／Armor 的下一列連通島，並逐 frame 清理 Cape／Weapon／Shield 的外來像素；runtime QA 逐格拒絕 Weapon 多連通元件、Shield foreign-row band 與非紫色 Cape 孤島。驗證順序固定為重建 PNG、強制 Godot import、runtime Texture2D QA、最後才看 OpenGL UI capture，避免匯入快取造成舊圖假通過。工程漏像素 gate 已 PASS；人工 Art Gate 仍需依最新 montage 簽核。

## 10. 完成定義

只有同時滿足以下條件，角色生成器第一版才算完成：

1. PC 外觀有唯一 Session owner，關閉／重建 UI 後不遺失，且 v1／v2 存檔行為已驗證。
2. PC 模式只能提交性別、Body ID、Hair ID；裝備與坐騎永不進入權威外觀快照。
3. 素材實驗室可以走訪 Catalog 的每個素材、兩種姿勢、兩種性別、四個方向與八個影格。
4. 全部紙娃娃層由同一 frame controller 更新，沒有 `AnimatedSprite2D` 或節點增生。
5. ChatGPT 第一批素材通過尺寸、Anchor、解析、遮擋、動畫連續性與 runtime capture Gate。
6. World／Region／Site／Battle 的既有資料 owner、控制鍵與 MultiMesh 邊界沒有被改寫。
7. `PROJECT_ARCHITECTURE.md`、`ARCHITECTURE_STATUS.md` 與兩份實作計畫反映相同的實際完成狀態。

完成後的下一個合理工作是擴充 ChatGPT 素材庫；不是立即接 Battle。Battle 接線仍要等待真正的 Character／Equipment／Unit snapshot 契約。
## 2026-08-13 Split Parts / Action / Dye Revision

The formal generator now uses split parts, action clips, and transient dyes. Complete reference sheets remain offline acceptance fixtures only.

- `CharacterCreator` is presentation-only and does not write `GameSession`, Persistence, gameplay equipment, mount ownership, or Battle state.
- `PaperDollCatalog` resolves independent Body, Armor, Hair, Helmet, Cape, Weapon, Shield, Mount Barding, and Mount Tail/Body/Head parts from `assets/paper_doll/reference_parts/`.
- `PaperDollComposer` reuses one fixed pool of 11 `Sprite2D` nodes. `AnimatedSprite2D` and per-soldier Nodes are forbidden.
- `PaperDollAnimation.Action` exposes `IDLE`, `WALK`, `RUN`, `ATTACK`, `SPRINT_ATTACK`, `WORK`, `HIT`, and `DOWN`. Authored action sheets remain optional; when absent, `PaperDollActionSheet` generates a deterministic 512x192 sheet per split part, keeping weapon swing, cape sway, recoil, knockdown and all frame changes synchronized.
- Hair + eyebrows share one dye group; Armor, Cape, and Mount have independent dye groups. Dyes are transient preview state and are never persisted.
- `reference_match` complete boards and the accepted reference image are QA fixtures, not formal split-part generator output.

Verification evidence for this revision:

- Godot 4.6.2 editor scan: PASS, no project parse/script errors.
- Canonical headless `character_creator_test.gd`: PASS, 10 cases, including split recipe visibility, all seven non-idle distinct action sheets, clip advance, four dye groups, mounted toggle, fixed Sprite pool, mirror, anchor, z-order, and dependency boundary.
- Focused action QA: PASS for all 8 actions in on-foot and mounted recipes, with fixed-pool frame/mirror/z-order synchronization; montages are in `.visual_captures/paper_doll/qa/`.
- Canonical GPU capture: PASS; inspect `.visual_captures/paper_doll/character_creator_action_*.png`, `character_creator_split_on_foot_walk_dyed.png`, and `character_creator_split_mounted_sprint_dyed.png`.
- Dedicated per-layer action art is not yet present. The ImageGen attack candidate remains a staged composite and is not attached to a single split layer. The procedural action fallback has headless and GPU evidence; authored replacement art must pass the same size, alpha, anchor, synchronization and visual capture gates.

Revision note: the current Asset Lab intentionally exposes independent split
part selectors and transient dye controls. The default acceptance capture is
white hair with silver armor; Helmet is opt-in and suppresses Hair to prevent a
double head. The ImageGen attack candidate at
`assets/paper_doll/action_candidates/worldgoing_attack_candidate.png` is a
complete composite source, so it is staged for layer extraction and is not
attached to any split layer.

### 2026-08-13 multi-visual and dye verification correction

- The Catalog now exposes 16 layer visuals and two mount bundles. `artgate1_*`
  remains the default; `alt_*` entries are selectable and resolved per slot.
- Alternate geometry inherits approved reference sheets and is recoloured by
  the deterministic packer. The raw ImageGen board remains staged because its
  direct crops failed the anchor/scale gate.
- Runtime tests switch armor, hair, cape, weapon, shield, and the complete
  alternate horse bundle, then capture both on-foot and mounted states. Dye
  isolation is checked in both poses: hair+brows, armor+barding, cape, and
  horse coat have no cross-layer mutations.
- Accepted captures:
  `.visual_captures/paper_doll/character_creator_alternate_on_foot_dyes.png`
  and
  `.visual_captures/paper_doll/character_creator_alternate_mounted_dyes.png`.
- Visual QA compares each alternate alpha mask with its approved base for
  armor, hair, cape, weapon, shield, barding, and all three horse parts; this
  prevents a colour-only variant from hiding a new alignment regression.

### 2026-08-14 Asset Lab shared-base correction

- The accepted white-hair/silver-armor preset keeps the same calibrated
  `reference_match_body_*` BODY sheet for every Asset Lab action. Selecting
  `WALK`, `RUN`, `ATTACK`, or another action changes the unified frame column;
  it must not replace the complete base with a legacy split/procedural body
  sheet.
- The catalog revision now contains 26 layer visuals, including eight approved
  hairstyle silhouettes plus the light armor and light armor helmet; the older
  16/24-visual counts above are historical.
- The mounted checkbox is exercised through the real `CheckBox.toggled`
  signal. Mounted preview uses the calibrated rider+horse BODY board, so the
  intrinsic MountBody Sprite2D remains hidden instead of drawing a second horse.
- Approved hairstyles are composited into that same base. Front/profile rows
  align the hairstyle face opening to the calibrated head; the UP row keeps its
  rear-head placement. The dye mask uses the identical row placement.
- `scripts/tools/capture_character_creator_lab_visual.gd` now captures on-foot,
  mounted, WALK, and mounted hairstyle direction states and asserts the shared
  base plus actual OptionButton/CheckBox signal paths. The latest visual files
  are under `.visual_captures/paper_doll/lab_visual/`.
- The eight approved hairstyle IDs now use `GenderPolicy.GENDERED`: each owns
  separate male/female 512x192 hair-only source sheets (16 PNGs total), while
  the Asset Lab still exposes eight style choices for whichever gender is
  selected. Mounted recipes reuse the corresponding gender's calibrated hair
  source so gender switching cannot change alignment.
- A later Godot verification attempt was blocked by a Mono signal-11 startup
  crash after the code change; that timeout/crash is not treated as a pass and
  requires a fresh isolated runtime before accepting new captures.

### 2026-08-15 Gendered hairstyle acceptance

- The isolated `.gender_lab_probe` runs the production `CharacterCreator`,
  production `PaperDollCatalog._gendered_hair_visual`,
  `PaperDollComposer`, and scene with the same 16 runtime
  hairstyle sheets. The focused GPU run exits 0 in 7.69 s and writes
  `.visual_captures/gendered_hair_lab/report.json`.
- Reported gates: `male_styles=8`, `female_styles=8`, `hair_option_count=9`
  (None + eight styles), real `GenderOption` signal `PASS`, distinct source
  resources, and distinct source pixels for every male/female pair. The same
  probe toggles `Mounted pose` and captures all 16 mounted combinations;
  `mounted_signal=PASS`, `mounted_gendered_styles=16`.
- The full Dropbox project launch remains a separate unverified boundary because
  its 60-second headless startup timed out without script output; the isolated
  result is the accepted focused evidence and is not misreported as a full
  project runtime pass.

### 2026-08-15 Light armor and crafting recipe acceptance

- `PaperDollCatalog.create_art_gate1_catalog()` now exposes the unisex
  `light_armor` and `light_armor_helmet` visuals for both on-foot and mounted
  poses. All four checked-in sheets are 512x192, 8x3, RGBA PNGs with transparent
  corners and are loaded directly from source PNGs before any optional Godot
  import cache.
- The Asset Lab keeps Armor and Helmet as independent OptionButton selections.
  `PaperDollCraftingRecipe` records presentation-only costs using existing
  canonical resource IDs (`forest`, `grass`, `iron_ore`) and exposes a pure
  affordability query; it does not mutate inventory or become a gameplay owner.
- The focused production-Catalog GPU probe writes four captures under
  `.gender_lab_probe/.visual_captures/light_armor_lab/` and reports PASS for
  both selectors, on-foot/mounted resolution, anchor-aligned rendering, and
  sufficient/insufficient material queries. Full-project Editor startup remains
  an independent environment boundary and is not claimed by this probe.
