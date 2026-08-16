# Worldgoing 專案架構與開發順序

## 目的

本專案採用「世界層 → Region 層 → Site 層」的三層架構：

- 世界層負責 Region 之間的關係、Party 所在位置與全局時間。
- Region 層負責 100×100 Strategic Cells 的生成／彙整、輕量 Site 通行摘要、資源內容索引、探索移動與大型建設。
- Site 層負責每個 Strategic Cell 的小尺度地圖與細部玩法；村莊、洞穴、遺跡等 POI 是可選的 Site 內容。

核心原則：資料模型先於顯示、程序生成可重現、世界不保存不必要的完整地圖。

## 一、三層架構與座標模型

### 1. World 層

World 層只處理跨 Region 的狀態與流程，並在開局建立一份受預算約束的 256×256 packed Overview：

- `RegionCoord`: Region 在世界中的整數座標，例如 `(3, -2)`。
- Party 所在的 Region 與 Strategic Cell。
- 全局時間、跨 Region 移動與載入相鄰 Region。
- Region 的 Seed 與玩家造成的 Delta 索引。
- `WorldOverviewData` 的宏觀 biome、共享通道、海岸／河／山脊旗標與七種 Region 資源總配額。

World 層不直接持有 TileMap，也不負責繪製地形。建立 Overview 不得配置 65,536 個 `RegionData`；Region Manifest、Region Base 與 Site 內容都維持按需生成。

### 2. Region 層

每個 Region 是固定大小的戰略資料區：

- 大小：`100 × 100 Strategic Cell`。
- 每格代表：`100m × 100m`。
- Region 實際範圍：`10km × 10km`。
- `RegionCoord` 決定 Region 的世界位置。
- `RegionData.seed` 決定該 Region 的程序生成結果。
- Region 資料可被重新生成，不依賴 TileMap 是否存在。
- 每個 Strategic Cell 都是一個可進入的 Site 來源；進入 Region 時才由 Manifest 生成 packed 100×100 `RegionSiteContentData`，保存原生表面提示與七種資源配額，不保存 10,000 個完整 Site Layout 或 Runtime。

Region 內座標限制：

```text
StrategicCellCoord.x ∈ [0, 99]
StrategicCellCoord.y ∈ [0, 99]
```

建議的座標換算契約：

```text
global_cell = region_coord * REGION_SIZE + local_cell
            = region_coord * 100 + local_cell

world_meters = global_cell * CELL_SIZE_METERS + intra_cell_offset
             = global_cell * 100m + 格內偏移
```

其中：

- `region_coord` 是 Region 座標。
- `local_cell` 是 Region 內的 Strategic Cell 座標。
- `global_cell` 是整個世界的 Strategic Cell 座標。
- `intra_cell_offset` 只在需要更細的位置時使用，不應混入 Region 生成索引。

### 3. Site 層

Site 是掛在某個 Region Strategic Cell 上的小尺度場景：

- 例：村莊、洞穴、遺跡。
- 固定大小：`50 × 50 Site Cell`。
- 每格代表：`2m × 2m`。
- Site 實際範圍：`100m × 100m`，正好對應一個 Region Strategic Cell 的實際範圍。
- Site 有自己的局部座標與場景資料；每個 Strategic Cell 都能依 Global Cell 懶生成一份 Site Base。
- Site 不取代 Region；Region 只保存 Site 的座標索引、入口與狀態。POI 是選定 Site 的可選附加內容，不是進入條件。
- 從 Region 選定任意有效 Strategic Cell 進入 Site 時，才載入該 Site 的細部地圖與玩法。
- Strategic A* 以 Site Travel Profile 為 100m 尋路節點，但不展開沿途 Site 的 50×50 局部格。

Site 的 `50 × 50` 是座標與邊界契約，不代表必須保存 2,500 筆格子資料；未改動內容仍應由 Seed 重建，玩家改動使用稀疏 Delta。

Site 座標不可直接當成 Region 座標使用；兩者之間必須透過位於父 Strategic Cell 中央的入口錨點轉換。Site 的 `100m × 100m` 局部邊界必須與父 Strategic Cell 的世界公尺邊界一致，但不改變 Region 的 `100 × 100` 戰略格大小。

若 Party 與選定 Site 位於同一 Strategic Cell，進入時可從 `(25, 25)` 顯示；若 Party 不在該格，Site 仍可作為 detached map 檢視，且不建立 Party 顯示標記。`PartyData.current_site_local_cell` 仍是局部位置的唯一真實來源；進入、退出與每次上下左右一格的基本移動都由 `TravelRuntime` 驗證及修改，移動不得進入 generated `NAV_BLOCKED` 格。`SiteMap` 只送出 WASD／方向鍵意圖並顯示 Runtime Snapshot，不能直接改位置。

戰略通行資料使用同一個 Site 契約：一般可通行格持有北／東／南／西四方向遮罩，不可通行格為 0；山地主地形中具有至少兩個實際道路出口的格為 `MOUNTAIN_PASS`，以 4 bit cardinal `travel_exit_mask` 保存真實 Route 連接。World、Region、Site 的 WeightedGridPathfinder 與道路繪製都只沿 tile 邊移動，不產生斜向步驟或斜向出口。進入完整 Site 後，`SiteLayoutGenerator` 用同一遮罩生成正交中央可通行走廊、兩側岩石高地與推導峭壁。Region 的 packed Profile 負責 Site 資源／內容摘要；詳細 placement 與 Layout 保持 lazy，玩家改動只寫稀疏 Delta。

### Site 原生地表與詳細場景邊界（已實作）

`SiteLayoutData` 以 `DIRT`、`ROCK`、`RIVER_WATER`、`SEA_WATER` 四種逐格原生表面，加上整數 `elevation_level`、相鄰格高度邊界及少量 `SiteTransitionData` 表達台地、峭壁、樓梯與橋；峭壁不是第五種 floor。草、果樹、森林、石／鐵／銀／金礦是資源 placement；橋、木／石梯、木／石牆與最小 building definition 是設施 placement。`SiteMap` 只繪製 resolved snapshot，`TravelRuntime` 才能決定水面、高度差及牆是否可跨越。不建立 3D 世界、第二套座標、每格 Scene Node 或平行資源／建築 manager。完整 P0–P6 分期與驗收見 `SITE_NATIVE_SURFACE_LAZY_GENERATION_REFACTOR_PLAN.md`。

## 二、資料與顯示的分離

資料層是唯一的真實來源，顯示層只是消費者：

```text
RegionCoord + seed
```

## PC 外觀與紙娃娃素材實驗室邊界

角色生成器先落地的 Gate 0／Milestone 1 只建立 Presentation 素材實驗室，不建立 Character、Equipment 或 Mount gameplay：

- `PaperDollLayerVisual` 與 `PaperDollMountVisual` 是 runtime 不修改的視覺 Resource；它們只保存穩定 visual ID、渲染層、性別政策與 Texture。
- `PaperDollCatalog` 是素材候選的查找與驗證入口；角色生成器正式預覽使用 `assets/paper_doll/reference_parts/` 的拆分部件，並提供 Body、Armor、Hair、Helmet、Cape、Weapon、Shield、Mount Barding 與 Mount parts 的獨立選擇。`reference_match` 完整板只保留為離線驗收 fixture，不是正式輸出；舊 `debug_*` Catalog 只保留為工程 fallback，不得寫入存檔。
- `PaperDollPreviewDraft` 是素材實驗室的可變 View 草稿，永不進入 `GameSession` 或 Persistence。
- `PaperDollRecipe` 是從 Catalog 解析出的 detached 顯示快照；`PaperDollComposer` 只消費 Recipe，固定重用 11 個 `Sprite2D`。`PaperDollAnimation` 支援 IDLE、WALK、RUN、ATTACK、SPRINT_ATTACK、WORK、HIT、DOWN；缺少逐部件動作圖時由 `PaperDollActionSheet` 產生保持 512×192 契約的程序化分件動作片。Hair+eyebrows、Armor、Cape、Mount 是四個獨立的暫時染色群組。
- `CharacterCreator` 目前只啟用素材實驗室，且以白髮銀甲 approved reference 為唯一預覽輸出；正式畫面不顯示金髮紫披風等未通過對位的分層候選，也不顯示離線 Check All／Contact Sheet／failure 導覽。PC 外觀頁明確停在 Milestone 2 placeholder。腳本沒有 `GameSession`、Persistence 或 Battle 依賴。
- `PaperDollContactSheet` 使用純 `Image.get_region()`、逐部件 LEFT 鏡像與 `blend_rect()` 合成 4×8 驗收表；UI 的 `SubViewport` 只負責單人即時預覽，不作 Battle Bakery。

來源素材契約固定為每格 `64×64`、`8×3` sheet（`512×192`），row 為 DOWN／UP／RIGHT；LEFT 使用 RIGHT row 並逐部件 `flip_h`。所有部件的 frame 內世界 Anchor 固定為 `(32,56)`，Composer 使用 `centered = false` 與 `offset = (-32,-56)`。11 個 render layers 與方向 Z-order 由 `PaperDollLayerVisual.RenderLayer`／`PaperDollComposer.z_index_for()` 單一實作。

### Paper Doll V2 standalone 工程邊界（2026-08-16）

V2 以 `PAPER_DOLL_V2_ARCHITECTURE.md` 為細部契約，已完成工程標準化、參考圖校準基線與預覽管線；目前 calibrated reference baseline 已通過，但 split-part 自由換裝仍未完成。它不覆寫上述 V1 角色生成器，也不代表 PC persistence 或 Battle variant 已完成：

- `PaperDollV2BodyTemplate`、`PaperDollV2AssetManifest`、`PaperDollV2Validator`、`PaperDollV2Catalog` 是 V2 的素體／Manifest／admission 邊界；錯誤尺寸、狀態、透明格式或缺少模板的部件不得進 Catalog。
- V2 固定步行每幀 `64×64`、騎乘每幀 `64×96`，來源 `8×3`（`512×192`／`512×288`），Anchor 分別為 `(32,56)`／`(32,88)`；LEFT 由 RIGHT mirror。V2 使用 12 layers，另有獨立 `BOOTS`。
- `PaperDollV2Recipe` 是 detached 快照，`PaperDollV2Composer` 只重用固定 12 個 `Sprite2D`；單一 `PaperDollV2Animation` frame API 同步所有圖層，禁止 `AnimatedSprite2D` 與 per-layer timer。
- V2 pack 與實驗室位於 `assets/paper_doll/v2/`、`scenes/ui/PaperDollV2Lab.tscn`；男女校準板位於 `assets/paper_doll/reference_match/`，原始女性三視角板位於 `assets/doll/reference/`，工程輸出位於 `.visual_captures/paper_doll_v2/`。目前為 4 templates、66 normalized PNG entries、0 pack failures；`verify_paper_doll_v2_reference.gd` 已對男性與女性參考板完成 256/256 strict GPU checks（min IoU 1.0、max BBox delta 0 px）。這只代表參考板基線通過，不代表 split-part 自由換裝素材完成。
- V2 仍是 Presentation／QA only。`GameSession.player_appearance`、Equipment／Mount owner、Persistence v2、Battle MultiMesh variant 與 9,000 人 Soldier Node 禁止由 V2 取得或持有。

Milestone 2 才允許加入 PC 權威外觀。已鎖定的資料契約為 `GameSession.player_appearance` 持有一份 `PlayerAppearanceData extends RefCounted` 深拷貝，只包含 `gender`、`body_visual_id`、`hair_visual_id`；唯一 mutation 入口為 `GameSession.apply_player_appearance()`。Persistence v2 只逐欄位保存這三項，v1 讀取遷移使用 male 預設；正式 Catalog 必須提供以下穩定 ID：

```text
body_male_default
body_female_default
hair_male_default
hair_female_default
```

Art Gate 1 已提供 reference-derived runtime 素材包與 PC 預設 visual ID 候選；角色生成器正式畫面鎖定白髮銀甲 approved sheet，分層合成仍只在離線 QA 使用。Milestone 2 仍必須先建立 `GameSession.player_appearance`、深拷貝套用與 Persistence v2，且不得把 synthetic `debug_*` ID 寫入存檔。Equipment／Mount owner 未建立前，盔甲、武器、盾牌、披風、馬匹與騎乘狀態都只能存在 Preview Draft。Battle 仍只使用既有單一 MultiMesh；角色生成器的 Sprite、SubViewport、Recipe 或 Catalog 不得成為 9,000 人 Battle runtime state。

## Battle composite and runtime boundary

Battlefields are composed from nine adjacent Site-sized bases, not a second tactical world:

- Each base is the canonical `SiteLayoutData` 50x50 grid at 2m per cell (100m x 100m).
- The 3x3 composite is 150x150 derived navigation cells and 300m x 300m; `Region` and normal Site sizes do not change.
- `SiteLayoutGenerator.generate_cell_base()` supplies compact deterministic terrain/road/river navigation flags. It does not allocate nine POI `SiteRuntimeState` objects.
- `GameSession.active_battle_state` owns formations, continuous meter positions, paths, revision and elapsed battle time. `BattleSiteMap` consumes detached snapshots and emits movement intents.
- A Formation represents 100 personnel with a 20m x 10m footprint and 20 x 5 visual slots. The Battle context caps both sides together at 9,000 personnel.
- `BattleSiteMap` renders one circular marker per person through one GPU-instanced `MultiMesh`; a 100-person Formation therefore owns 100 visual instances. Formation state remains the only runtime command/simulation unit. Reserve personnel are presentation-only staging instances until a future command activates them.
- Active Battle is currently a movement slice only. Damage, AI, combat resolution and Battle persistence are deliberately deferred; saves return typed `BATTLE_ACTIVE` while a battle is running.

Battle command authority is also Session-owned and Formation-level:

- `BattleParticipantData` identifies a `PLAYER` or `NPC` commander and the commander's Formation index. Only that Formation is directly controllable by its commander.
- Simple subordinate intents (`ADVANCE`, `FALL_BACK`, `ATTACK`, `WITHDRAW`, `FLANK_REAR`) enter `BattleRuntimeState.pending_orders` and execute after a deterministic signal delay.
- Fine subordinate intents (`MOVE_TO`, `SET_FACING`, `HOLD_POSITION`, `FOCUS_TARGET`) are data-only `BattleOrderData` payloads carried by `BattleDispatchData`. The messenger follows a bounded path and can be intercepted by an enemy Formation; interception discards the payload and is observable through `query_order()` as `MESSENGER_INTERCEPTED`.
- `BattleFormationData` records captain autonomy on direct contact. Orders arriving while a Formation is engaged are deferred until contact clears; no Soldier, AI, NavigationAgent, Command Bus, or event-bus node is introduced.

```text
        ↓
RegionGenerator
        ↓
RegionData / StrategicCellData
        ↓
TileMap、地形預覽、探索 UI
```

必須維持以下界線：

- Generator 不讀取或修改 TileMap。
- TileMap 不決定地形資料，也不保存唯一的遊戲狀態。
- 重新進入同一 Region 時，使用相同 Seed 與 Delta 得到相同資料。
- 顯示層可以重建，不應影響程序生成結果。

## 三、固定開發順序

### 1. 三層架構 + 座標模型（現在）

建立 World、Region、Site 的責任邊界與座標契約。

完成條件：

- 能清楚表示 `RegionCoord`、Region 內 `StrategicCellCoord` 與 Site 局部座標。
- 能在世界座標、Region 座標、Region 內座標之間穩定換算。
- 沒有把 TileMap 當成資料庫或世界狀態擁有者。

### 2. Region 100×100 地形資料模型 + 程序生成 Seed

對任意 `RegionData.seed`，可重現生成同一張 100×100 Region 地形資料。

本階段只處理資料正確性：

- Region 資料模型。
- Strategic Cell 資料模型。
- Seed 驅動的確定性生成器。
- 同一 Seed 重建結果完全一致。
- 生成資料與 TileMap 顯示分離。

本階段不急著製作漂亮地圖、不加入探索、不加入建設、不加入 Site。

### 3. Region 邊界一致性

處理相鄰 Region 的邊界出口，使河流、道路與地形能夠接續：

- 相鄰 Region 的接點必須使用一致規則。
- 不能只靠顯示層補縫。
- 邊界資料應可獨立驗證。

### 4. Region 探索移動

讓 Party 在 100m Strategic Cell 上移動並推進時間：

- 移動先更新資料，再更新顯示。
- 進入邊界時切換或載入相鄰 Region。
- 移動規則不依賴 TileMap 的暫時畫面狀態。

### 5. Region 持久化

只保存 `Seed + Delta`，不保存整張未修改的世界：

- Seed 重建原始 Region。
- Delta 保存玩家改動，例如採集、建設、道路或其他狀態。
- 讀檔後結果必須與離開前一致。

### 6. Site 系統

加入村莊、洞穴、遺跡等真正的小尺度地圖：

- Site 由 Region 入口索引。
- Site 使用固定 `50 × 50`、每格 `2m` 的局部座標與場景。
- Site 邊界對應父 Region Strategic Cell 的 `100m × 100m` 實際範圍。
- 不預先建立完整格子狀態；維持可重建 Base + 稀疏 Delta。
- Party 從 `(25, 25)` 進入，基本移動一次一格；位置由 `PartyData` 擁有並由 `TravelRuntime` 驗證修改。
- `SiteMap` 只負責輸入訊號、Party 標記與其他顯示。
- 從 Site 返回 Region 時保留必要狀態。

### 7. Construction Mode

先只做 Region 層的大型建設：

- 城牆、道路、農地、據點等戰略尺度內容。
- 建設寫入 Region Delta。
- Site 內的細部建造留到 Site Gameplay。

### 8. Unit + 紙娃娃

加入可移動 Unit 與紙娃娃顯示：

- Unit 的位置仍由資料層管理。
- 紙娃娃是 Unit 狀態的顯示結果。
- 不讓紙娃娃節點成為位置或生命週期的唯一真實來源。
- 已完成的素材實驗室只是 Unit 前置 Presentation 工具；PC 外觀 owner、正式素材、Unit snapshot 與 Battle shader 仍需依各自 Gate 後續實作。

### 9. 戰鬥與更細的 Site Gameplay

最後加入戰鬥、互動與 Site 內的細部玩法。這些系統必須建立在前面已穩定的 Region、Site、Unit 與持久化契約上。

目前已先落地 Battle composite 的最小移動切片：戰場由九個 Site base 組成，Formation 是 100 人的執行單位，個人只作為 GPU 視覺實例；完整戰鬥解析仍留在後續階段。

## 四、後續實作的共通驗證原則

- 相同輸入必須得到相同資料。
- 顯示層重建不應改變資料層結果。
- 座標換算必須可逆，且明確處理負數 Region 座標。
- 每完成一階段，先做該階段的最小驗證，再進入下一階段。
- 沒有完成前一階段的資料契約，不提前加入後續玩法。

## 五、下一個可直接餵給 Codex 的 Prompt

```text
請先閱讀目前 Godot 專案，並只處理「Region 100×100 地形資料模型 + 程序生成 Seed」這一個目標。

目標：
給定任意 RegionData.seed，都能確定性地生成同一張 100×100 Region 地形資料；重新進入或重新生成同一 Region 時，結果完全一致；地形資料與 TileMap 顯示分離。

必要條件：
1. 建立最小可用的 RegionData 與 StrategicCellData 資料模型。
2. 建立由 RegionData.seed 驅動的確定性 RegionGenerator。
3. 生成結果必須只由 Region 座標、Seed 與明確的生成參數決定，不依賴場景中的 TileMap 或節點順序。
4. 同一個 Seed 生成兩次時，100×100 每一格的資料必須完全相同。
5. 生成器輸出的資料可以交給 TileMap 顯示，但生成器本身不能依賴 TileMap。
6. 加入一個最小的可執行驗證，檢查同 Seed 結果一致，並檢查尺寸確實為 100×100。

限制：
- 這一輪不要製作漂亮地圖或複雜美術顯示。
- 不要實作 Region 邊界接續、探索移動、持久化、Site、建設、Unit 或戰鬥。
- 不要新增平行的世界、地形或 TileMap 架構；先尋找並重用目前專案已有的資料與場景入口。
- 若目前架構不足，做最小必要修改，並說明實際修改的檔案與責任。

完成後請回報：
1. 修改了哪些檔案。
2. RegionData、StrategicCellData、RegionGenerator 的實際擁有者。
3. 確定性驗證如何執行，以及驗證結果。
4. 尚未處理的邊界條件或後續工作。
```
## Site 原生地表重構狀態（2026-08-12）

`SiteData` base generation version 3、`WorldOverviewData` version 2、`WorldRoadGenerator` version 5 與 `SiteLayoutGenerator` generation version 8 已完成 `WorldOverviewData` → `RegionGenerationManifest`／packed `RegionSiteContentData` → lazy `SiteLayoutData` 的三層生成路徑。`SiteLayoutData` 擁有 deterministic 原生表面、高度、峭壁邊界、資源／設施 placement、牆邊與 transition；`TravelRuntime` 解析生成 Base + Session sparse Delta，擁有採集、增刪設施、逐格移動與 bounded Site A* 的重新驗證；`SiteMap` 只渲染 detached snapshot。

P0–P6 已以 9/9 focused refactor tests、既有 Runtime／跨區／持久化回歸、隔離 editor scan，以及五種實際 GPU 場景共 10 張預覽完成驗收。大型 POI 組合、完整採集／建造玩法及正式邊界／岸線 polish 仍延後，且不新增第二座標、3D world、per-cell Node 或平行 manager。
