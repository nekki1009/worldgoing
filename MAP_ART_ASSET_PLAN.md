# 地圖美術素材製作規劃

## 目標

把目前的八種地形色塊，逐步替換成一致的俯視角地圖美術，同時保留現有的：

- 256×256 World Map 尺寸與跨 Region 座標契約
- World／Region／Site 三層地圖所有權
- TerrainType 的八種語意與地形比例
- 河流入海、道路、POI、旅行與 Battle 的 Runtime 判定
- 由世界種子決定的可重現結果

AI 產生的是貼圖、圖示與裝飾素材；地形分類、河流、道路與可通行性仍由既有程式生成器負責。

目前已生成第一版風格確認板：

[map_terrain_style_board_v1.png](<C:/Users/Nekki/Dropbox/竹北社大/(01)102-103學員資料/share/worldgoing/assets/map/concepts/map_terrain_style_board_v1.png>)

這張圖只作美術基準，不直接取代遊戲內的地形資料或貼圖。

依現有地形總覽再生成一張保留大陸、海洋與河流構圖的世界地圖美術概念稿：

[world_map_art_concept_v1.png](<C:/Users/Nekki/Dropbox/竹北社大/(01)102-103學員資料/share/worldgoing/assets/map/concepts/world_map_art_concept_v1.png>)

## 統一美術方向

- 俯視角、略帶手繪質感的策略地圖；不使用等角透視
- 遠距離先讀得出海陸與八種主地形，近距離再看出材質細節
- 無文字、無 Logo、無水印、無角色、無 UI 元件烘焙在素材內
- 地形底材必須可平鋪；邊緣不能有明顯接縫或固定方向的地平線
- 顏色以目前 TerrainType 色票為基準，AI 只增加明暗、顆粒與局部細節
- 素材不改變碰撞、尋路、河流或 POI 的資料判定

參考圖審核後，Site 近景與 World／Region 遠景分成兩個美術密度：World／Region 維持目前手繪底材與縮圖規則；Site 近景改以清晰像素風、nearest-neighbor 與可調的 detail tile density 為目標。這不改變 2m 邏輯格，也不把近景貼圖寫入 Runtime。

目前的語意色票：

| TerrainType | 既有色票 | 美術重點 |
|---|---|---|
| Plains | `#6F9B5B` | 低矮草地、少量土色變化 |
| Forest | `#3F7857` | 林冠群聚、可讀的林間空隙 |
| Mountain | `#777B83` | 岩脊、坡面方向、少量裸岩 |
| Water | `#4D87A1` | 淺水、湖泊、河岸水色 |
| Sand | `#C9AD6A` | 沙丘、風紋、乾燥地表 |
| Snow | `#DCE8ED` | 雪面、冷色陰影、稀疏裸地 |
| Swamp | `#66734A` | 濕地草叢、泥水斑、蘆葦 |
| Ocean | `#294F68` | 深水層次、低對比波紋 |

## 素材清單與製作順序

### 0. 風格確認板（先做）

一張不直接進遊戲的風格板，包含八個地形材質方格、河流、道路、POI 圖示與一小段三層地圖示意。用途是確認筆觸、明暗、飽和度與俯視角，之後所有素材沿用同一風格。

### 1. 八種主地形底材（第一批可進遊戲）

建立 `assets/map/terrain/`：

- `plains.png`
- `forest.png`
- `mountain.png`
- `water.png`
- `sand.png`
- `snow.png`
- `swamp.png`
- `ocean.png`

規格：每張 256×256 PNG、可平鋪、無透明需求、保留中心細節但不要畫大型固定地標。World Map 使用縮小取樣，Region／Site 使用較高細節取樣。

### 2. 海岸與地形邊界

建立 `assets/map/terrain_edges/`：

- 海洋／淺水的 8 方向岸線與泡沫邊
- 淺水／陸地的 8 方向邊界
- 沙地、雪地、沼澤與平原的低對比過渡邊
- 山地與森林的山腳／林緣過渡

第一版只做海岸、河岸與山腳；其餘邊界先由 TerrainType 色塊加材質取樣處理，避免一次產生大量組合貼圖。

### 3. 河流與道路覆蓋層

建立 `assets/map/overlays/`，以透明 PNG 製作 64×64 覆蓋片：

- 河流：直線、彎角、T 字、交會、源頭、入海口、橋／渡口
- 道路：土路、石路、主幹道、彎角、交會、橋面
- 河岸只畫水面與岸邊細節，不在貼圖內畫地形底色

程式仍使用現有 `RegionRoadOverlay` 與 river flags 決定要放哪一片，素材不持有路網資料。

### 4. POI 圖示

建立 `assets/map/poi/`，每個圖示 128×128 PNG，透明背景、中心對齊：

- `village.png`
- `town.png`
- `castle.png`
- `ruins.png`
- `cave.png`
- `outpost.png`

圖示要能在 World Map 的小尺寸仍讀得出類型；Region Map 可以使用同一圖示的放大版或細節版。圖示不包含名稱文字，名稱由現有 UI 顯示。

### 5. 地形局部裝飾（第二批）

建立 `assets/map/decorations/`，以少量可重複的小型素材增加近景層次：

- 森林：樹冠群、倒木、林間空地
- 山地：岩塊、雪線、山徑
- 沙地：小沙丘、乾枯灌木
- 雪地：雪堆、冰塊、裸地
- 沼澤：蘆葦、泥坑、枯木
- 平原：草叢、田地色塊

裝飾由穩定種子散佈，不得成為尋路或碰撞判定的第二套資料。

### 6. 地圖 UI 美術（最後）

- 地形圖例：八色票與名稱
- 選取框、Region 邊界、Party marker
- POI hover／selected 狀態
- 河流、道路與渡口的圖例

這一批優先使用現有 Debug UI 的資料來源，不把文字烘焙進 AI 圖片。

## 與現有程式的接點

素材接入時只改表現層：

- `scripts/world/world_map.gd`：World Map 地形縮圖與河流／POI 覆蓋
- `scripts/region/region_map.gd`：Region Map 細節貼圖與道路／河流覆蓋
- `scripts/site/site_map.gd`：Site Map 地形、道路、河流與 POI 細節
- `scripts/data/terrain_type.gd`：維持語意、色票與水域判定的唯一來源

不把 PNG 載入 `WorldData`、`RegionRuntime` 或 `BattlePreviewRuntime`；Runtime 只提供已解析的 terrain／river／road／POI 資料給畫面。

## 每批素材的驗收條件

1. 圖片尺寸、色彩模式與命名符合清單。
2. 底材四邊平鋪後沒有明顯接縫。
3. 八種地形在 World、Region、Site 都能辨識，海洋與淺水不混淆。
4. 河流覆蓋能沿既有河流資料連續顯示，至少包含入海口與道路渡口。
5. 同一 World Seed 重開後畫面一致，換 Seed 後仍只改資料決定的區域。
6. PNG 不含文字、Logo、水印或固定 UI。
7. 視覺回歸維持現有 30 FPS 門檻與既有地形比例／河流驗證。

## AI 繪圖工作流

1. 先生成風格確認板，確認後固定 prompt 的視角、筆觸與色彩描述。
2. 再逐張生成八種可平鋪底材；每次只改一個地形主題。
3. 生成河流、道路與 POI 透明覆蓋素材，做去背與邊緣檢查。
4. 將通過檢查的 PNG 放入 `assets/map/`，再接入對應 Presentation renderer。
5. 每完成一批就重跑比例、河流、視覺與 FPS 驗證，不等到全部素材完成才整合。

## 實作版決策（2026-08-12）

本節把上面的素材清單收斂成可以直接落地的 V1 實作順序。若「完整素材清單」與本節的分期有衝突，以本節為準。A0、A1、A3、A4、A5 已完成；道路／河流／橋／隘口目前採既有程序 polyline、visual code 與 navigation flag 的低成本表現，缺素材時仍可 fallback，不阻斷 Runtime。

### 目前渲染邊界

- Site 是固定 `50×50`、每格 `2m` 的 `100m×100m` 畫布；它是第一個正式美術整合點。
- 一般 Site 的底材仍是一種 `TerrainType`。道路、河流、POI 與山隘口是覆蓋層，不另造第二套地形資料。
- `MOUNTAIN_PASS` 使用既有 `travel_exit_mask` 與 `NAV_BLOCKED`：通道沿出口遮罩生成，兩側山壁由 blocked 格顯示。它不是第九種地形。
- Region 的正常視圖是每個 Strategic Cell 取一份 `8×8` Site 縮圖；World 是 Region thumbnail 的再組合。兩層都不可載入完整 Site 場景或完整 Site 貼圖。
- Battle 的九格 composite 也重用同一個 Site 底材／道路／河流／隘口解析，不建立 Battle 專用素材目錄。
- `TerrainType`、`SiteLayoutData.visual_cells`、`navigation_flags`、`RegionRoadOverlay`、river connection offsets、POI ID 與 seed 仍是唯一資料來源；美術只負責 Presentation。

### V1 最小素材包

| 素材 | 路徑 | 原始規格 | 首次用途 | 備註 |
|---|---|---|---|---|
| 八種主地形底材 | `assets/map/terrain/{plains,forest,mountain,water,sand,snow,swamp,ocean}.png` | `256×256`、RGB/RGBA、可平鋪 | Site、Region、World | 不畫路、河、POI、文字或固定地標 |
| 道路／河流覆蓋 | `RegionRoadOverlay`、`visual_cells`、river flags | V1 程序 polyline／色彩覆蓋 | Site／Region／World | 方向與長度取自既有連線資料，避免先做大量轉角 atlas |
| 橋／渡口 | `river_crossing`、crossing visual flag | V1 程序 crossing 覆蓋 | Site／Battle | 專用透明橋素材列入 V2 polish |
| 山隘口山壁 | `travel_exit_mask`、`NAV_BLOCKED` | V1 blocked 格與通道覆蓋 | Site／Battle | 專用 cliff 素材列入 V2 polish，不能遮斷出口 |
| POI 圖示 | `assets/map/poi/{village,town,castle,ruins,cave}.png` | `128×128`、透明背景 | Region／Site／World | 同一穩定 ID 可使用不同縮放，不含名稱 |
| 哨站圖示 | `assets/map/poi/outpost.png` | `128×128`、透明背景 | Region | 由 Region runtime feature 定位，沒有時回退程序矩形 |

本輪已補齊 Site 物件 atlas：道路直線／彎道／T 字／交叉、河流直線／彎道／源頭／入海、橋、山隘口岩壁、入口、地標與八種地形對應裝飾。正式視圖仍由 layout 的 path、connection offsets、river crossing、travel exit mask 決定方向；程序線只保留為接縫底線與 Debug 可讀性，不再是唯一的美術表現。

### 實作順序與程式接點

#### A0 — Presentation 素材入口與 fallback

新增一個純查找／快取的 `MapArtCatalog`（不持有 World、Region、Session 或 Runtime 狀態），集中處理：

- `TerrainType → base texture`；
- overlay／POI 路徑與載入錯誤；
- 從主地形底材產生 Region／World 所需的小尺寸 thumbnail；
- 素材缺檔時回退到現有 `TerrainType.to_color()` 與程序繪線。

這個入口只會被 `SiteMap`、`RegionMap`、`WorldMap`、`BattleSiteMap` 使用；不把 `Texture2D` 寫入 `WorldData`、`RegionData`、`SiteRuntimeState` 或存檔。

#### A1 — Site 第一個可玩美術切片

1. Site 底層改為繪製主地形底材，不再把 50×50 格直接放大成色塊。
2. `visual_cells` 只決定道路、河流、交叉、hub、landmark 等覆蓋；`navigation_flags` 只決定 blocked／通行，不被美術反向修改。
3. 道路與河流沿既有 `primary_path_meters`、connection offsets 與 crossing 資料繪製；底材四邊不含方向性地標，因此同一張圖可重用在任意 Site。
4. 保留 Debug View 的色票模式，讓資料驗證不被正式材質遮住。

驗收畫面至少包含 Plains、Forest、Mountain、Water、Sand、Snow、Swamp、Ocean 八種 Site，以及一個有河流／道路交會的 Site。

#### A2 — Mountain Pass 與水路接合

- 由 `travel_exit_mask` 旋轉／鏡像 `mountain_pass_cliff`，blocked 區必須包住通道兩側，但不能遮斷出口。
- 河流與道路 crossing 使用同一個 bridge overlay；橋的位置只取 `river_crossing`／既有 flags。
- 隘口的視覺方向、戰略可通行方向與 Site 內的通道必須是同一份遮罩結果。

#### A3 — Region 組合

- `RegionMap` 正常視圖以 `generate_cell_base_thumbnail()` 的 visual code 為索引，從八張底材取得每格的 `8×8` 取樣，再疊加道路／河流／crossing。
- Region 不建立 10,000 個完整 Site texture，也不把 POI、道路或裝飾寫回生成資料。
- `ELEVATION`、`MOISTURE`、`RIVER`、`ROAD`、`TRAVEL` 等 Debug View 維持目前色票／熱圖。

#### A4 — World 投影與 POI

- `WorldMap` 以 Region thumbnail 的 8×8 取樣建立可見區域 texture；鏡頭移動只重建可見 bounds。
- POI 改用透明圖示與既有穩定 `poi_id` 定位，選取框、Party marker、旅行預覽仍由程式繪製。
- 256×256 World 的 lazy query、terrain 比例與主要河流入海驗證完全不變。

#### A5 — Battle 重用

`BattleSiteMap` 對九個 Site base 使用相同 `MapArtCatalog` 與 overlay 解析；Formation、選取框、部署區與指令預覽仍是獨立的 Presentation overlay。此步不增加新的戰場地形資料或素材目錄。

#### A6 — V2 polish（先不阻擋可玩切片）

- 海洋／淺水／陸地岸線與河岸邊界；
- 沙地、雪地、沼澤、森林與山地的低對比邊界；
- 轉角／T 字／交叉的專用 atlas（只有實際畫面顯示接縫時才加入）；
- 種子散佈的樹冠、岩塊、蘆葦、沙丘、雪堆與小型建築裝飾。

### 素材與整合驗收

每個 A 階段都要同時檢查：

1. PNG 尺寸、色彩模式、alpha、命名與匯入設定正確；
2. 底材重複 `3×3` 沒有接縫、明顯邊框或固定方向地標；
3. 同一 Site seed 重開結果一致，換 seed 只改資料選到的 terrain／road／river／POI；
4. 河流入海、道路轉角、橋與山隘口的接合沒有斷線；
5. Region／World 的縮圖仍能辨識八種主地形，且沒有載入完整 Site 資料；
6. 正式材質與 Debug View 可互相切換，缺圖時 fallback 不會讓場景失效；
7. `visual_composition_test.gd` 維持既有 50×50／8×8／256×256 契約，`visual_runtime_capture_test.gd` 在 World／Region／Site／Battle 均維持至少 30 FPS。

正式截圖請寫入新的 `.visual_captures/map_art_v1/` 子目錄，不覆蓋既有 `.visual_captures/` 驗證證據。

### P4 close 實作與嚴格驗收（2026-08-12）

本輪將 A2／A5 與 Site 物件接線收斂為 P0–P4；大型 POI 圖示則在後續比例尺重構中退出 Site renderer：

- **P0 正式／Debug 邊界**：`SiteMap` 正式視圖以 `build_layout_base_image()` 加物件 atlas；F1 只開啟資料覆蓋，不改變生成資料。缺素材才退回程序色線。
- **P1 交通物件**：`primary_path_meters` 逐段貼 `path_straight`，轉折貼 `road_bend`；Strategic Cell 的 road offsets 貼同一套 path；河流依實際出口方向使用 river strip、source、mouth。
- **P2 聚落／地標／運輸**：入口使用 `entrance_gate`，landmark 使用 `stone_marker`，crossing 使用旋轉後的 `bridge`；POI hub 目前只畫 2m anchor，大型 POI 圖示待多 tile footprint 後再接回。
- **P3 地形裝飾**：依 `terrain_type` 與 deterministic landmark index 選取樹叢、岩塊、沙丘、乾灌木、雪堆、蘆葦、枯木；Mountain 一般地形只用岩塊，`mountain_pass_cliff` 僅由 `MOUNTAIN_PASS` 分支放置；不寫入 World／Region／Session state。
- **P4 Battle 重用**：Battle 九個 Site base 共用 `MapArtCatalog`；道路／河流／junction／bridge 與 Site 同源，Battle detail 以生成的 trees／rocks／bushes 接上手繪物件，Formation 仍由 GPU instance owner 管理。

嚴格驗收腳本：

- `visual_composition_test.gd`：8 cases，檢查 8 種地形、POI、全部 Site art key 的 alpha／圖像可載入，並驗證實際生成 Site 的 path／landmark／hub。
- `visual_runtime_capture_test.gd`：實際 256×256 世界視窗；輸出 World、Site formal／scale guide／debug、POI 地形、Strategic Cell 的 Water／Ocean／River／Mountain Pass（若該 seed 有可通行山口）、Battle，並以實際視窗 FPS 驗證至少 30。
- 畫面檔案寫入 `.visual_captures/map_art_v2/`，不覆蓋 V1 證據；目前已產生 `world_actual_256x256`、`site_formal_actual`、`site_debug_overlay_actual`、`site_terrain_*_actual`、`site_river_cell_actual`、`battle_site_actual`。

### 已完成與下一步

### 2m Site 視覺比例重構與大型 POI 延後（2026-08-12）

本輪以既有 Site 座標契約為唯一比例尺來源：

- `SiteLayoutData.GRID_SIZE = 50×50`、`CELL_SIZE_METERS = 2`、Site 範圍 `100m×100m`；
- `MapArtCatalog` 目前將 V1 base／thumbnail 底材畫布固定為 `256px`，因此視覺換算為 `2.56px/m`，每個 tile 為 `5.12px` 的低成本 composite 尺寸；參考圖等級的 Site 近景另由後續 Detail Layer 提供可調 tile density；
- 顯示用人物參考框為 `0.60m×1.80m`，放在一個 2m tile 內，作為美術比例檢查，不新增 Occupancy 或第二套碰撞／尋路資料；
- SiteMap 的 F2 `2m Scale Guide` 顯示完整 2m 網格、每 10m 強線、單格高亮、人物參考框與 2m 尺規；F1 資料覆蓋仍維持原本語意。

單 tile 物件改由 `MapArtCatalog.SITE_ART_METADATA` 提供公尺尺寸與連接寬度：道路、河流、源頭／入海口、橋、山隘口、入口、地標，以及森林／山地／沙地／雪地／沼澤／平原裝飾均不再在 `SiteMap` 散落硬編碼尺寸。Metadata 是 Presentation 描述，不擁有 Runtime 狀態，也不改變 `navigation_flags`。

大型 POI（村莊、城鎮、城堡、遺跡、洞穴）本輪明確標記為 `DEFERRED`：SiteMap 不繪製現有 128px 大圖示，只保留一個 2m hub anchor；圖示留在 catalog 供未來多 tile 組合使用，不納入單 tile 尺寸、接縫或人物比例驗收。後續以多個 2m tiles 組成 POI footprint，再另做建築邊界、入口與接線素材。

新增高門檻檢查：

1. `scripts/tests/site_visual_scale_test.gd`：6 cases，檢查 50×50／2m／200cm／100m／256px 契約、人物參考框、20 個 Site 單 tile art metadata、POI renderer deferred policy、八張地形素材 256×256 邊界差量測，以及生成 Site 的 anchor/path/landmark/edge tile 不越界。
2. 接縫驗收不假設目前手繪底材四邊像素完全相同；測試記錄每種地形 horizontal／vertical edge mean，現行最大值 ocean vertical `149.74`，bounded-blend gate 為 `≤160`。若要提高近景品質，下一批應優先重繪 snow／swamp／ocean 的垂直接縫。
3. `visual_runtime_capture_test.gd` 改寫入 `.visual_captures/map_art_scale_v1/`，另外擷取 `site_scale_guide_actual.png`，並在實際非 headless 視窗量測 Scale Guide FPS `≥30`；不覆蓋 `map_art_v2` 舊證據。

本節只處理美術比例與驗證導引；「一格最多一人」是視覺尺寸基準，實際 Occupancy／NPC 佔用仍待明確 Runtime owner 後另行實作。

- **已完成（A0）**：`MapArtCatalog` 集中載入八種地形、五種 POI 與哨站貼圖，缺圖回退既有色票／程序繪線。
- **已完成（A1）**：Site 使用 256px 地表合成，既有 visual/navigation flags 保持資料權威；八種底材與 POI 已放入 `assets/map/`。
- **已完成（A3／A4）**：Region／World 由同一份地形素材低頻縮圖組合，Region 道路沿既有 route path 連續繪製，World POI 受上限控制並使用縮小圖示。
- **已完成（A5）**：Battle 地面格共用八種地形材質，Formations 與戰鬥 overlay 維持原 owner。
- **已完成（P0–P4）**：Site formal/debug 邊界、交通／河流／橋／隘口／入口／地標／地形裝飾、Battle 共用物件目錄與實際地圖預覽均已接線；`mountain_pass_cliff` 只沿 `travel_exit_mask` 放置，不遮斷通道。大型 POI 圖示已退出本輪 renderer，僅保留 2m hub anchor。

V1 輸出仍保留在 `.visual_captures/map_art_v1/`；本輪 P4 輸出在 `.visual_captures/map_art_v2/`。V1／V2 的素材接線與比例驗證已完成；下一步是 [Site 高低差、樓梯與精細場景實作計畫](SITE_DETAILED_SCENE_IMPLEMENTATION_PLAN.md)，之後才進行對應的正式近景素材與岸線／邊界 polish。這項擴充仍不改動 World／Region ownership，但會在 Site 內加入可重建高度與轉接資料，並由同一份資料供 Runtime 與 renderer 使用。
### Detailed Site scene implementation update (2026-08-12)

The previously planned local-height slice is now implemented through P0-P3.
`SiteMap` keeps the 256px base for low-cost composite views, builds an 800px
near-camera surface at 16px per 2m tile, and draws deterministic color-block
platforms, water, walls, cliffs, stairs and bridges from `SiteLayoutData`.
`TravelRuntime` and the renderer consume the same transition rules. Formal
multi-tile POI art, hand-painted cliff faces, shoreline polish and non-headless
visual capture remain the next art tasks.
