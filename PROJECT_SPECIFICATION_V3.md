# Worldgoing 專案規格書

**版本**：v3.0.0（256×256 有限可擴充世界與動態 Formation 版）
**引擎需求**：Godot Engine 4.6+（Forward Plus / D3D12、Jolt Physics 3D）
**核心原則**：資料模型先於顯示、確定性程序生成、Seed + Delta 稀疏持久化、顯示層不可成為 gameplay 權威。

V3 supersedes V2；V2 保留為需求演進與差異比較基線。

## V3 範圍與狀態

V3 將 World Layer 定義為**有限但可擴充**的平面整數網格。初始世界邊界為 256×256 個 World Cells；每個 World Cell 代表一個 10km×10km Region，因此初始世界約為 2,560km×2,560km。擴充只能增加邊界，不得重新編排既有 World Cell、Seed、POI ID、Route ID 或存檔座標。

世界不得因規模而預先建立完整地形、Site、道路圖或 Scene。未修改內容由 Seed 依座標重建，玩家修改內容由 Sparse Delta 保存；只生成目前視窗、旅行查詢或玩法需要的資料。

目前已落地的基線包含：三層座標、確定性地形／POI／道路生成、輕量 Site Travel Profile 與山地隘口方向遮罩、GameSession 與 TravelRuntime、Region Seed + Sparse Delta、Region Outpost、Seed + Delta Persistence、九區 Battle composite、Formation 移動、命令延遲、傳令攔截與隊長自治。

目前已完成 V3 的 256×256 packed World Overview 與三層 lazy 生成、World／Region／Site 三層視覺組成、任意 Region tile 的 Site 入口、四種 Site 原生表面、局部高度／峭壁、橋與木／石梯、木／石牆、七種資源 placement、最小多格建築、sparse Site Delta、Site 2m 視覺比例 metadata／scale guide、紙娃娃素材實驗室、reference-derived Art Gate 1 runtime pack 與實際 GPU 預覽驗證。尚未完成的功能包含：大型 POI 多 tile 組合、正式美術師版 Site 邊界／岸線 polish、沙／雪／沼澤 overlay polish、資源再生與完整採集／建造玩法、擴充紙娃娃美術庫、MapBaker dirty-cell 烘焙、Formation Breadcrumb／CHOKE／REGROUPING、Battle paper-doll variant cache／shader與完整戰鬥解析。大型 POI 圖示目前僅保留在 catalog，SiteMap 不繪製，待多 tile 組合實作後再接入。

## 一、專案總覽與系統目標

Worldgoing 是一款以 Godot 4.6 開發的程序化沙盒戰略 RPG。世界從宏觀 World Layer、戰略 Region Layer 到局部 Site／Battle Layer，均由資料與可重建快照驅動。

### 1.1 資料與顯示分離

1. GameSession、WorldData、RegionData、SiteData、Runtime State 是資料與 gameplay 權威。
2. WorldMap、RegionMap、SiteMap、BattleSiteMap 是不可持有權威 gameplay state 的可重建 Presentation。
3. WorldMap 與 RegionMap 可以接收唯讀資料上下文及 Runtime command/query 介面；SiteMap 與 BattleSiteMap 優先接收 detached snapshot。
4. Camera、hover、preview、插值與繪圖快取可以存在於視圖，但 Scene 銷毀不得改變 Session 或 Runtime 權威。

### 1.2 Site art 與 Region 微縮烘焙

專案視覺資產以 Site Layer 的 2m×2m 規格為主。Region Layer 不建立第二套獨立大地圖 Tileset。

目前由 `SiteLayoutGenerator` 依需求產生 50×50 Site visual cells；RegionMap 只取每個 Strategic Cell 的低成本 8×8 thumbnail，WorldMap 開局只讀 256×256 packed Overview，不會為世界畫面展開 Region 或 Site。正式 MapBaker 是 V3 後續功能，應接收已解析的 Site visual data，使用同一套 Site 視覺規則輸出 32×32 nearest-neighbor Region cell thumbnail。烘焙結果是可丟棄的 generated cache，不是 Session state。

Site 視覺比例固定由 `SiteLayoutData` 提供：50×50、每格 2m（200cm）、100m×100m；`MapArtCatalog` 的 256px presentation surface 只負責公尺尺寸換算，近景層以 16px／2m 格生成 800px nearest-neighbor 表面。F2 scale guide 可視化 2m 網格與 0.60m×1.80m 人物參考框；它不建立 Occupancy、collision 或第二套尋路資料。已實作的 7×5 木屋與 9×7 石廳是用來驗證 footprint、牆與入口的最小 building definition；大型 POI 仍延後，未來應由多個 2m tiles 組合 footprint、入口與接線。

### 1.3 Site 詳細場景與原生地表（已完成基礎重構）

Site 詳細場景採局部離散高度，而不是完整 3D 地形：每個 2m 格有可重建的 `elevation_level`，高度邊界推導峭壁／牆面，樓梯與橋以明確轉接資料連接相鄰格。`source_elevation` 仍是 Region 的宏觀高程，不能直接當作局部格高度。斜坡／碼頭可沿用同一 transition 契約，但本階段沒有新增獨立玩法。

Site 逐格原生表面固定為 `DIRT`、`ROCK`、`RIVER_WATER`、`SEA_WATER`；峭壁是高度邊界而非第五種可站立 floor。草、果樹、森林、石／鐵／銀／金礦是資源 placement；橋、木／石梯、木／石牆與建築是設施 placement。沙／雪／沼澤保留為宏觀 Region terrain，投影到 Site 時使用原生表面加 overlay／material variant，不增加互斥 floor enum。

Runtime 由 `TravelRuntime` 驗證相鄰格、牆、水面與高度轉接，`SiteMap` 只顯示 detached resolved snapshot；沒有橋的水面、沒有樓梯的高度差及牆邊界都必須阻擋。生成 Base 可依 Seed 重建；採集、拆除及玩家新增／拆除設施只寫 Session-owned sparse Site Delta。完整重構與 P0–P6 證據以 [SITE_NATIVE_SURFACE_LAZY_GENERATION_REFACTOR_PLAN.md](SITE_NATIVE_SURFACE_LAZY_GENERATION_REFACTOR_PLAN.md) 為準。

MapBaker 必須支援 lazy／dirty-cell 更新，快取至少受 world seed、generation version、art version 與相關 Delta revision 影響。不得在載入時預先烘焙整個 256×256 世界。

## 二、三層架構與座標契約

### 2.1 三層地圖層級

| 地層 | 初始網格尺寸 | 單格實際尺寸 | 初始總範圍 | 權威資料 | 視圖 |
|---|---:|---:|---:|---|---|
| World Layer | 256×256 World Cells，可向外擴充 | 10km×10km | 2,560km×2,560km | WorldData、PartyData | WorldMap |
| Region Layer | 100×100 Strategic Cells | 100m×100m | 10km×10km | RegionData、RegionRuntimeState | RegionMap |
| Site Layer | 50×50 Local Cells | 2m×2m | 100m×100m | SiteData、SiteRuntimeState | SiteMap |

World Cell 是 Region 的外部座標；Region 的 100×100 Strategic Cells 不因 World 擴充而改變。每個 Strategic Cell 都可依座標查詢一份輕量 Site Travel Profile，並可在選定時懶生成對應的 Site Base；POI 只是該 Site 的可選內容 overlay，不是進入條件。完整 50×50 Layout 與 SiteRuntimeState 只在進入玩法、Battle 或其他明確需要時生成，不得為所有 Strategic Cells 常駐完整 Site Runtime。

### 2.2 座標換算

Global Strategic Cell：

    global_cell = world_cell * 100 + region_cell

Global Meters：

    global_meters = global_cell * 100m + intra_cell_offset

反向換算必須使用數學 floor division 與 posmod，負數 Global Cell 需能得到正確的 World Cell 與 Region Cell。Site 固定為 50×50、每格 2m，Party 進入 Site 時預設局部格為 (25,25)。

### 2.3 世界邊界與未來擴充

1. 初始合法 World Cell 數量為 256×256；實作以集中設定的 World bounds 表示，不得散落硬編碼。
2. 未來擴充只改 bounds 或載入的世界分區，不得使既有座標位移。
3. 既有 World Cell 的 Region Seed、POI ID、Route ID、生成版本與 Save wire 座標必須保持穩定。
4. 超出目前 bounds 的查詢、旅行與 Battle preview 回傳 typed failure，不得偷偷建立越界 gameplay state。
5. V3 不要求球面經緯度、極點或經度環繞；目前是有限平面網格。若未來改成地球球面，必須另訂 projection contract。

## 三、程序化生成、地形、POI 與道路

### 3.1 確定性雜湊與 Seed

DeterministicHash 是跨執行階段的整數雜湊工具。Region 與 Site Seed 必須使用現有 owner 與 generation version，不得引入第二套 Seed API。

Region Seed：

    RegionData.seed = DeterministicHash.value(
        world_seed,
        world_cell,
        REGION_SEED_SALT + generation_version
    )

POI Site Seed 由 POI 的穩定生成資料、Global Region Cell、Site generation version 與 POI type 推導；無 POI 的 Strategic Cell Site Seed 則由 World Seed、Global Region Cell 與 Site generation version 推導。既有 Site Seed 不得因 World bounds 擴大而改變。

### 3.2 Region 地形

RegionTerrainGenerator 使用 WorldMacroTerrainSampler 的多層 FastNoiseLite 欄位，依 Global Strategic Cell 取樣，以確保相鄰 Region 邊界一致。V3 不把 Cellular Automata 列為現行必要演算法；若未來加入，必須維持相同的 global-coordinate 與 generation-version 契約。

### 3.3 POI

WorldPOIGenerator 以穩定座標與 Seed 產生 VILLAGE、TOWN、CASTLE、RUINS、CAVE。每個 POI 必須有穩定且全域唯一的 poi_id；重新生成、清除 generated cache 或擴充 World bounds 不得改變既有 POI ID。

### 3.4 道路

WorldRoadGenerator 依地形移動成本、POI settlement graph 與四方向 WeightedGridPathfinder 產生 Route。道路結果寫入 RegionRoadOverlay，Route 使用穩定 route_id；World／Region／Site 的道路折線只沿 tile 邊繪製。

Site 的道路顯示為連續、不透明的人工清理帶；道路本體不再重複鋪設帶碎石／草邊的裝飾貼圖，資源與自然裝飾維持在道路清除範圍外。這是顯示層規則，不改變道路資料、出口或尋路成本。

MOUNTAIN_PASS 的抬高平台不再複製帶碎石的原始地表 tile，再以獨立的窄道路帶繪製東西／南北出口；平台底色、峭壁立面與通行道路分層，避免原生岩石底圖穿透或與道路重疊。

道路具備：

- 依 POI 類型限制 degree；
- 依 terrain、river、crossing 計算成本；
- 48 Cells 是 route search corridor margin／bounded search 的限制，不宣稱為所有道路的最大長度；
- generated graph、path、overlay 都是可清除的 cache，不是 Runtime authority。

### 3.5 Site Travel Profile、Region 內容責任與隘口

World 開局只建立 256×256 packed `WorldOverviewData`，保存每個 World Cell 的宏觀 biome、通道、海岸／河／山脊旗標與七種資源總配額；不得因此建立 65,536 個 `RegionData`。進入 Region 時才由 `RegionGenerationManifest` 與 100×100 Region terrain 產生 packed `RegionSiteContentData`，以確定性 largest-remainder／穩定排序把七種配額分配到 Strategic Cells。RegionMap 只讀摘要與 thumbnail，不建立任何 50×50 Site placement。

每個 Strategic Cell 的基礎地形、資源／內容摘要與通行資料由 World／Region Seed、Global Cell、generation version 及 Region Delta 解析；任意有效 Strategic Cell 都能展開成 Site，POI 只補充該格內容。詳細資源／設施 placement 與 50×50 Site Layout 只在進入 Site 或玩法明確需要時展開，不得先配置 10,000 個完整 Site 物件。

所有戰略尋路統一讀取輕量 Site Travel Profile，不得展開路徑沿線的 50×50 局部格。Profile 至少包含：

- terrain_type、site_landform、passable 與 travel cost／speed；
- road、river、river_crossing；
- travel_exit_mask 與實際 road connection offsets；
- native_surface_hint、rock_ratio、river_width_class、coast_mask 與七種 resource_amounts 摘要。

現行 World／Region／Site 尋路統一使用四方向 tile 邊（北、東、南、西）；`travel_exit_mask` 使用 4 bit cardinal 位元，斜向出口與斜向移動一律無效。一般可通行 Site 為四方向全開，完全不可通行 Site 為 0；山地主地形中具有至少兩個實際 Route 出口的道路格解析為 MOUNTAIN_PASS，遮罩只保留該格的真實道路出口。

同一份 MOUNTAIN_PASS 遮罩必須投影到 `SiteLayoutData`：生成器建立連接真實出口的正交可通行走廊，走廊兩側抬高成岩石高地，由 `height_edge_flags` 推導峭壁；只有明確的 stair transition 能跨越高低差。`TravelRuntime.move_party_in_site()` 與 Site A* 讀同一份 resolved layout 並以 typed `BLOCKED` 拒絕穿崖。SiteData Base generation version 為 3，`SiteLayoutGenerator` generation version 為 8。

目前 MOUNTAIN_PASS 只限制隘口 Site 自身的進出方向；一般 Mountain 仍可用既有低速成本通行。因此它已能表現局部／道路型隘口，但尚未把整條高山稜線變成宏觀不可穿越障壁。若未來需要真正的世界級唯一關口，應在同一 Profile 規則中加入可重建的 ridge／high-mountain blocked landform，不得另建第二套尋路資料。

## 四、Runtime 與狀態管理

### 4.1 GameSession

GameSession 擁有 world_seed、world_time_seconds、PartyData、travel state，以及延遲建立的：

- region_runtime_states：Dictionary[Vector2i, RegionRuntimeState]
- site_runtime_states：Dictionary[String, SiteRuntimeState]

### 4.2 TravelRuntime

TravelRuntime 提供唯讀 query：

- query_travel_preview()
- query_site_snapshot()
- query_site_entry()／query_site_entry_at()

並擁有：

    start_travel() → commit_travel_step() → finish_travel()
    start_travel() → cancel_travel()

TravelRuntime 是 pathfinding、travel cost、Site tile entry query 與 authoritative Party／World Time mutation 的唯一 Runtime owner；`query_site_entry_at()` 不以 Party 位置或 POI 存在作為進入門檻。Presentation 不得提交未重新驗證的 preview path。

### 4.3 RegionRuntime 與 Delta

RegionData 只保存 deterministic identity、Seed、生成版本與可重建 generated base references。RegionRuntimeState 擁有 sparse RegionDelta；RegionStateResolver 是 Base + Delta 的唯讀解析路徑。

Region Outpost 使用：

- query_outpost_preview()
- place_outpost()
- remove_outpost()

穩定 ID 格式為 outpost:x:y:cell_x:cell_y。命令必須重新驗證 Party 位置、Region／Cell、通行性、佔用與既有 feature，不能信任 Presentation preview。

## 五、Battle、Formation 與紙娃娃

### 5.1 Battle composite

Battle 由中心 Strategic Cell 周圍 3×3 個 Site-sized Base 組成：

- 150×150 derived navigation cells；
- 300m×300m；
- 使用 SiteLayoutGenerator 的 CELL_BASE；
- 不建立九個 POI SiteRuntimeState；
- BattleSiteGenerator 不讀取 Scene、TileMap 或 Presentation。

### 5.2 動態 Formation 尺寸

Formation 是命令與模擬的最小單位，但**不是固定 100 人，也沒有固定 20m×10m 尺寸**。

1. 每個 Formation 的 personnel_count 為 1–100 人，100 是上限。
2. Formation 的 width、depth、visual footprint 與 deployment footprint 由實際人員數量、個人實際尺寸、隊形間距、列／排布局及 Formation state 計算。
3. 人數減少時，Formation 應縮小；不得只保留固定 100 人的空間。
4. 9,000 personnel 是 Battle 的目標總容量，可由最多 90 個、每個最多 100 人的 Formation 組成；實際 MultiMesh instance count 必須等於實際 personnel_count 總和。
5. 目前既有 Formation geometry 與 MultiMesh dot 是基線；動態尺寸的完整驗證需新增測試。

### 5.3 Breadcrumb Trajectory 與窄道狀態

這是 V3 後續實作，不得在尚未完成時宣稱已通過：

- 只對 Formation leader／anchor 尋路；
- Leader 寫入有限歷史軌跡與方向；
- 部下依實際行距從軌跡取樣，不能建立 99 個獨立 pathfinder；
- NORMAL、CHOKE、REGROUPING 狀態必須有明確 transition、寬度比例、速度補償與離開窄道條件；
- 若要求跨 frame／跨平台 replay 一致，Runtime 需另訂 fixed-tick 與 replay input contract。

### 5.4 PaperDoll 與 GPU

目前只有 Presentation 素材實驗室：固定 11 個 Sprite 的 `PaperDollComposer`、由 `assets/doll/` reference board 產出的 Art Gate 1 Catalog、純 Image contact sheet 與 UI 預覽。它沒有 PC／Unit 權威資料、Texture2DArray 或 Battle 接線。

Battle PaperDoll variant cache 是 V3 後續功能，依賴未來的 Unit、Equipment、Demography 與美術資產 owner。它應：

- 將 captain／hero 與 subordinate template 組合成可重建的 Texture2DArray；
- 來源 sheet 只含 DOWN／UP／RIGHT；離線合成時先逐部件鏡像 LEFT 並套用 LEFT Z-order，再產生四方向完成圖；
- 以 variant layer、frame_x、facing_row 等 instance data 驅動 shader，不以完成圖 runtime `flip_h` 取代 LEFT 遮擋；
- 維持 BattleSiteMap presentation-only；
- 以實測資料驗證 GPU instance 數、顯示品質與目標 FPS。

目前實作的 9,000 人測試只證明 MultiMesh instance capacity 與無 Soldier Node，不等同 Battle paper-doll variant cache 或 shader 已完成。

### 5.5 命令、傳令與自治

目前已完成的命令切片包含：

- Commander Formation 的直屬命令；
- subordinate Formation 的 deterministic delayed simple orders；
- data-only BattleDispatchData fine orders；
- line-segment interception；
- direct contact 時的 captain autonomy 與 deferred order。

## 六、持久化與狀態隔離

PersistenceService 使用 Seed + Delta JSON snapshot。保存：

- world_seed；
- generation_versions；
- world_time_seconds；
- Party 基本狀態；
- sparse RegionRuntimeState／RegionDelta。

不保存 generated terrain cache、Node tree、TileMap、Camera、UI、preview path、active Travel、active Site-local position 或 active Battle。

不穩定狀態必須回傳 typed failure：

- TRAVEL_IN_PROGRESS；
- SITE_ACTIVE；
- BATTLE_ACTIVE。

Load 必須先完整解析與驗證 wire payload，失敗時不得替換現有 Session。

## 七、Navigation 與 View

NavigationController 負責 World、Region、Site、Battle Scene 的生命週期與 Runtime orchestration。

Presentation contract：

- WorldMap、RegionMap 可接收唯讀 read context 與 typed Runtime query／command；
- SiteMap、BattleSiteMap 接收 detached snapshot；
- 所有 View 只能發送 input intent、顯示資料與 detached snapshot；
- View 的銷毀、替換或重建不得改變 Session、Runtime、Party、World Time、Region Delta 或 Site Runtime。

DebugUI 顯示 World Time、座標、Party、旅行 preview、Region construction、Battle order／dispatch 狀態。

## 八、測試與驗證

目前 `scripts/tests/` 有 22 個可執行 GDScript 測試檔案，靜態超過 1,000 個 `assert()` 呼叫。

目前已驗證的基線：

- Coordinate 4/4；
- Terrain 9/9；
- POI 10/10；
- Road 14/14（含正交 tile 邊檢查）；
- Party movement 16/16；
- Cross-Region Travel 18/18；
- Cross-Region Runtime PASS；
- Runtime command/query 19/19；
- Region Seed + Delta 22/22；
- Site runtime 36/36；
- Region construction 13/13；
- Persistence 10/10；
- Battle boundary 20/20；
- Architecture smoke PASS。
- Site native surface refactor 9/9：Overview 預算與零 Region 開局、共享邊界、七資源守恆、四原生表面、橋／梯移除、7×5 房屋門牆及 sparse Delta；
- Site detailed scene 6/6：高度、峭壁、樓梯、橋、Runtime A* 與 detail surface；
- Site visual scale 8/8：50×50／2m／200cm／100m／256px、800px detail surface、人物參考框、八張地形接縫、Site bounds 與 wheel zoom clamp；
- 實際非 headless map art scale capture（最新 renderer）：World engine 61 FPS、Site scale guide 147.36 FPS、Site debug engine 112 FPS、Battle engine 30 FPS、全流程 measured 147.34 FPS；均達到 30 FPS gate。輸出在 `.visual_captures/map_art_scale_v1/`。
- P6 實際 GPU Site capture：草地聚落、森林果樹、礦區、雙峭壁隘口、河流＋橋＋樓梯，各有全景與近景，共 10/10 張並逐張人工檢查；道路折線已驗證為正交 tile 邊，且道路顯示為連續乾淨清理帶。1280×720、VSync 關閉的 uncapped gate 最新最低量測 3488.07 FPS；此數字只證明通過 30 FPS gate，不作一般遊玩幀率承諾。輸出在 `.visual_captures/site_native_surface_p6/`。

Battle 20/20 目前涵蓋九區合成、typed query、命令權、延遲命令、傳令攔截、隊長自治、Formation 基本幾何、移動、9,000 MultiMesh instance 與 Scene replacement；不涵蓋 Breadcrumb、CHOKE／REGROUPING、PaperDoll shader 或 60 FPS benchmark。

V3 必須新增：

1. 256×256 bounded World query、越界拒絕、lazy generation 已由 visual composition test 覆蓋；未來仍需補 bounds expansion regression；
2. Seed／POI／Route ID 在擴充前後保持穩定；
3. 動態 personnel_count 與依實際人員尺寸計算的 Formation geometry；
4. Breadcrumb、窄道狀態與 fixed-tick replay（若納入目標）；
5. MapBaker 的 deterministic output、dirty-cell invalidation、cache key 與 memory budget；
6. PaperDoll variant／frame／flip custom data 與 GPU benchmark。

## 九、明確不在 V3 首批實作

本次 Site 重構只完成 deterministic 生成、導航規則、資源／設施資料 placement、最小建築 definition、sparse Delta 命令與實際美術預覽；不因此加入完整採集收益、資源再生、生態 AI、建造成本／工期／耐久、建築室內玩法、NPC、經濟、生產鏈或船舶。大型 POI 多 tile 組合、沙／雪／沼澤正式 overlay polish、Site movement time／animation、Site-local Party persistence、Site Runtime persistence、active Travel persistence、Save UI、多槽存檔、事件、天氣、任務、遷徙與完整 Combat damage／AI／resolution 仍屬後續範圍。
