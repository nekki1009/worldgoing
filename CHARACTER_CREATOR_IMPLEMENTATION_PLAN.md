# Worldgoing 角色生成器與紙娃娃素材實驗室實作計畫

狀態：規劃完成，待核准後實作

日期：2026-08-11

`PROJECT_ARCHITECTURE.md` 仍是最高架構真實來源。本文件只規劃第一個 PC 固有外觀資料切片、角色生成器 UI，以及供 ChatGPT 美術使用的紙娃娃素材／動畫驗收工具；不代表 Character、Equipment、Mount、PaperDoll 或 Battle shader 已經實作。

本輪只修改計畫文件，不修改程式、場景、美術、存檔格式或架構狀態。

## 1. 審核結論

先做角色生成器是合適的，但第一版必須同時提供兩種嚴格分離的模式：

1. **PC 外觀模式**：編輯並保存角色固有外觀，只包含性別、身體外觀 ID 與髮型外觀 ID。
2. **素材實驗室模式**：暫時掛載全部紙娃娃層、坐騎、方向與動畫，供逐項驗收美術；所有選擇都是 View 草稿，絕不寫入 PC、裝備、坐騎或存檔。

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
- 一組合成測試材質，讓工程驗證不必等待正式美術。
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

- Body、Armor、Hair、Helmet、Cape、Weapon、Shield、Mount、MountBarding 各一個選擇器；非必要層可選 `None`。
- Mounted 開關；未選 Mount 時不可啟用 mounted，並顯示可讀錯誤。
- DOWN／UP／RIGHT／LEFT 四方向按鈕。
- frame 0–7 滑桿、上一格／下一格、播放／暫停與 FPS（1–16）控制。
- 切換性別、姿勢、方向或素材時保留目前 frame，方便直接比較 Anchor 與抖動；關閉視窗時 Timer 停止。
- 「檢查全部」依 `visual_id` 排序，列出 PASS／FAIL、錯誤原因與下一個失敗項目。
- 「匯出 Contact Sheets」產生每項素材的 4×8 邏輯方向表；LEFT 必須是實際鏡像後的結果，而非複製 RIGHT 像素。

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

修改：

- `PROJECT_ARCHITECTURE.md`：新增最小 PC 外觀 owner，以及角色生成器／素材實驗室的 Presentation 邊界。
- `ARCHITECTURE_STATUS.md`：仍標為未實作，直到對應驗證通過；不得只因新增檔案就改成 Implemented。
- 本文件與紙娃娃總計畫：同步 sheet、Anchor、Layer 與優先順序。

通過條件：owner、存檔欄位、預設 visual IDs、11 層與 ChatGPT 輸入契約沒有未決項。

### Milestone 1：顯示核心與素材實驗室

預計新增：

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

預計修改：`scripts/main.gd`、`scenes/Main.tscn`、`scripts/ui/debug_ui.gd`、`scenes/ui/DebugUI.tscn`。

通過條件：合成測試材質可在四方向 × 八影格切換；LEFT 正確鏡像與復位；11 個 Sprite 不隨套用次數增加；所有 z-index、Anchor、mounted visibility 與 contact sheet 測試 PASS；開關 UI 時地圖輸入確實停用／恢復。

### Art Gate 1：ChatGPT 最小素材包

依第 6.2 節生成第一批素材，只有自動檢查與兩組完整疊層 capture 都通過者才加入 Catalog。

通過條件：PC 的 male／female body 與 hair 有有效預設值；每個 layer 至少一件測試素材；Mount 三部件完整；素材實驗室「檢查全部」為 PASS；人工／ChatGPT 複核 contact sheets 沒有可見錯位。

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

單元與資料驗證 PASS 不等於美術驗收 PASS；headless 測試也不取代 Forward Plus 畫面檢查。最終交付需分別報告自動測試、實際 UI capture 與仍需人工判斷的動畫美感。

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
