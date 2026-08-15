# Site 美術與資源分配改善計畫

**日期**：2026-08-13  
**狀態**：A5 八種地形場景切片完成；八種 terrain 與河橋回歸預覽已通過人工視覺檢查，資源群聚與大型 POI 仍依原計畫維持後續工作
**目標風格**：接近《Stardew Valley》的清楚 tile 場景與《First Queen 4》的探索地圖可讀性，但降低裝飾密度；玩家不用看 UI 就能辨識地形、通道、高低差與主要資源區。

## 一、審核結論

> 2026-08-13 驗收更正：前一版只證明 Godot 能輸出截圖，沒有通過美術可讀性驗收。宏觀地表貼圖在 Site 近景被放大成泥土／沙丘紋理，資源也沒有形成清楚的群聚，因此不視為 Stardew Valley／First Queen 4 風格完成。重構後必須檢查實際新截圖，而不是只看 capture 數量與 FPS。

可行，而且現有架構不用重做。這一輪已先完成四種最能驗證構圖的場景底圖，並保留資料層與渲染層分離。現在已具備：

- 固定 `50×50`、每格 `2m×2m` 的 Site；
- 泥土、岩石、河水、海水四種逐格原生表面，峭壁由高度差推導；
- 草、果樹、森林、石／鐵／銀／金礦七種資源；
- World 資源預算 → Region packed 配額 → Site placement 的懶生成與總量守恆；
- 道路、河流、橋、樓梯、牆、建築 footprint 與 sparse Site Delta。

問題不在缺少另一套系統，而在現有表現與落位規則太粗：

1. Site 底圖仍大量沿用宏觀地形貼圖縮放；泥地上的碎石／斑點密度過高，畫面像鋪滿裝飾噪點。
2. 草原、森林、沙地、雪地、沼澤等宏觀地形沒有形成各自清楚的 Site「地表主題」，多數只是同一原生泥地加不同物件。
3. 資源目前只檢查「泥土或岩石、避開道路／水／設施」，其餘以 deterministic hash 排序；結果確定但不具生態可解釋性。
4. 資源 placement 幾乎都是單格、等距散點；森林不像林地、礦石不像礦脈，遠景也無法一眼看出資源帶。
5. 道路、河與峭壁仍有部分獨立覆蓋流程，容易出現底圖與覆蓋層接縫、疊圖或比例不一致。
6. 正式 `show_region()` 目前只展開 Region terrain／road，沒有呼叫 `get_or_generate_region_site_content()`；一般 Site 因而可能使用 lazy fallback，POI 也先走 `SiteData.travel_data_from_poi()` 再被覆寫。現行測試證明 packed 配額生成器可用，尚未證明正式 Region → Site 流程始終使用它。

本輪應做的是「重整可讀性與生成規則」，不是增加大量裝飾、第二套 TileMap、資源 Manager 或預建所有 Site。

## 二、固定的視覺語言

### 2.1 一格一個地面答案

每個 Site cell 的正式底層只由以下資料決定：

1. `native_surface_at(cell)`：泥土、岩石、河水或海水；
2. `terrain_type`：決定泥土／岩石的氣候主題與色票，不新增第五種玩法表面；
3. `elevation_level_at(cell)` 與 `height_edge_flags_at(cell)`：決定平台與峭壁；
4. road／path／bridge／stair／wall：是清楚的設施或通道層；
5. resource placement：最後才放在可用 footprint 上。

同一位置不得再同時畫「宏觀山地底圖、程序峭壁、山壁 sprite、岩石裝飾」四種同義內容。正式視圖只保留一個主表現，Debug 才可疊資料線。

### 2.2 八種宏觀地形如何在 Site 被看懂

| Region `TerrainType` | Site 主色與地面 | 必須一眼可見的輪廓 | 低密度次要細節 |
| --- | --- | --- | --- |
| Plains | 偏綠的泥土地／短草覆蓋 | 大片開闊區、少量草叢與孤樹 | 小花、裸土邊，不鋪滿碎石 |
| Forest | 深綠泥地／落葉地 | 成片森林群、清楚林緣、林中空地 | 樹根、蕨類只放林緣 |
| Mountain | 冷灰岩地 | 岩台、連續峭壁、坡腳、礦脈 | 少量裂縫／苔，不重複大石底紋 |
| Water | 河水＋河岸泥地 | 連續河槽、兩側河岸、橋位 | 蘆葦只在緩岸 |
| Sand | 暖黃泥地材質變體 | 大片乾燥裸地、少量沙丘帶 | 乾灌木，不生成森林地毯 |
| Snow | 雪覆泥地／露岩 | 白色大面積覆蓋、露岩帶、雪岸 | 少量雪堆，不用均勻白點噪聲 |
| Swamp | 暗褐泥地＋濕泥覆蓋 | 淺濕地斑塊、蘆葦群、可走乾地島 | 枯木少量且集中 |
| Ocean | 海水＋海岸 | 海面、岸線、沙／岩岸、河口 | 浪花只沿岸，不鋪滿海面 |

沙、雪、濕泥、短草仍是泥土／岩石的 presentation theme；導航與採集不增加平行的地表 enum。

### 2.3 素材規格

沿用現有 `16px` 表示一個 `2m` Site cell，nearest-neighbor。第一批只製作能決定輪廓的素材：

- 地面：每種主題 3 個無方向中心變體；變體只改小紋理，不能改碰撞語意。
- 邊界：泥／岩、泥／河、泥／海、岩／水的四方向邊與內外角；由鄰格 mask 選圖。
- 高度：平台頂、連續峭壁正面、左右端帽、內外角；樓梯另為設施。
- 道路：水平、垂直、四種轉角、T 字、十字、端點；表面乾淨，碎石最多只在道路邊緣。
- 水系：直線、轉角、岸線、河口；橋在水與路之上，不能用道路色帶穿過河面。
- 資源：草斑、果樹、森林樹、四種礦；每類先做成熟／可採狀態一套，不先做季節動畫。

一般 fallback 地面不做 256px 單張場景底圖；由 cell 規則組成一張快取 Image／texture，保留現有一次生成、一次繪製的效能方式，不建立 2,500 個 Node。只有已核准的核心場景（平原村落、森林果園、礦區、山隘）使用完整 curated scene painting，並由 `FileAccess` 讀取 `res://` PNG 作為 presentation-only 底圖；尋路、高度與資源仍由 LayoutData 決定。

## 三、資源分配規則

### 3.1 保留現有三層守恆

不改 owner：

```text
WorldOverviewData.resource_budgets
  → RegionGenerationManifest.resource_budgets
  → RegionSiteContentData.resource_amounts（決定哪些 Strategic Cell 有多少）
  → SiteLayoutGenerator.resource_placements（進 Site 才決定 50×50 內的位置）
  → SiteRuntimeState.removed_feature_ids（採集後的 sparse Delta）
```

改善點只在兩個既有函式：

- `RegionSiteContentGenerator._resource_weight()`：決定資源應落在哪些 Region cell；
- `SiteLayoutGenerator._generate_resources()`：在 Site 中用 habitat score 與群聚規則落位。

### 3.2 Region 層適生規則

把「只看濕度／高度」改為清楚的硬限制加權重。總配額仍完全等於 Manifest。

| 資源 | 不得出現 | Region 高權重條件 |
| --- | --- | --- |
| 草 | Ocean、Water；Mountain 只允許少量土區 | Plains 最高；Forest 林間、Swamp 乾地、Sand／Snow 低量 |
| 果樹 | Ocean、Water、純 Mountain、極乾 Sand | Plains／Forest 的中高濕度；Swamp 僅乾地邊緣 |
| 森林 | Ocean、Water、Sand；純岩區 | Forest 最高，Plains 次之，Swamp 只在乾地島，Snow 為低密針葉林 |
| 石礦 | 水域、無露岩的低地 | Mountain／Snow 高，其他地形只在高海拔或岩脊摘要 |
| 鐵礦 | 非岩脊、低海拔 | Mountain 高，Snow 岩脊次之 |
| 銀礦 | 非高山岩脊 | 高海拔 Mountain，稀有 |
| 金礦 | 非最高等級岩脊 | 高海拔 Mountain 的極少數 cell，允許整個 Region 為 0 |

進入 Region 時必須實際建立該 Region 的 `RegionSiteContentData`，讓其中 10,000 個 packed profile 成為 Region 內 Site 配額的正式來源。`_site_content_profile_for()` 的未展開 Region fallback 與 `SiteData.travel_data_from_poi()` 也必須共用同一組 eligibility／weight 規則；不能保留 `_site_profile_resource_max()` 與 POI 簡化公式兩條平行規則，否則正式流程可能繞過 Region 守恆或在不同查詢時機得到不同資源量。

### 3.3 Site 層 habitat score

每個候選 cell 先通過硬限制，再計算整數分數；相同分數才用現有 deterministic hash 破同分。建議分數只讀現有資料，避免新增 2,500 格長期狀態：

```text
score = terrain_theme
      + moisture_band
      + elevation_band
      + distance_to_water
      + distance_to_cliff_or_rock
      + cluster_field
      - road_clearance
      - entrance_clearance
      - facility_clearance
```

固定規則：

- 所有實體資源避開道路／主要路徑至少 1 格，入口與樓梯至少 2 格，橋與門不得被遮住。
- 草：泥地；偏好平坦、中高濕度、距水 1–5 格；形成 2–8 格不規則斑塊，但不阻塞主要通道。
- 果樹：泥地；偏好林緣或開闊地，樹幹 footprint `1×1`，樹冠可越格；彼此至少相隔 2 格，不散成均勻點陣。
- 森林：泥地；以少量 deterministic cluster seeds 長成 3–12 棵相連群，保留 2 格寬林間通路；森林資源量是 quantity，不等於畫面上每片葉子。
- 石礦：岩地，優先坡腳、峭壁旁或岩地邊界；形成 2–6 格礦帶。
- 鐵／銀／金：只能在岩地且接近峭壁／高平台；同一礦脈以主礦種為主，不把四色礦均勻混灑。稀有礦沒有合適位置就記入 `resource_unplaced_*`，不可違規塞進泥地。
- 河岸與海岸：第一版不新增可採水生資源；只作 presentation 植被，避免把裝飾誤認為可採資源。

### 3.4 群聚與可讀性

使用現有候選掃描加少量 deterministic cluster seeds，不引入 noise library 或新的 manager：

1. 依資源量決定 `1..N` 個 cluster seed；
2. 依 habitat score 選 seed；
3. 以四方向 bounded flood／ring growth 擴展 footprint；
4. 每次放置維持 stable ID、quantity 與 occupied footprint；
5. 生成後驗證總 quantity 等於 Profile 或被明確記為 unplaced。

這會讓玩家在全景看到「草帶、林塊、礦脈」，而不是均勻散落的小圖示。

## 四、渲染層次與效能

正式 Site 固定繪製順序：

1. 原生表面主題 tiles；
2. 岸線、地面交界與高度面；
3. 峭壁正面；
4. 道路／河槽；
5. 橋、樓梯、牆與建築；
6. 資源 footprint sprite；
7. 角色；
8. 必要的前景樹冠；
9. F1／F2 Debug overlay。

`SiteMap` 仍只消費 resolved snapshot。地面、邊界、峭壁、道路與水系先烘成少量 ImageTexture；資源先沿用批次 draw，數量實測後才決定是否需要 MultiMesh。不可因美術重構建立每格 Sprite2D。

核心 curated scene 上只疊加縮小的 runtime resource marker；不再疊加舊的道路、峭壁或大型資源 sprite，避免把完整場景重新蓋成除錯圖。

刪除或停用未接正式流程的重複 helper，例如同義的裝飾／峭壁 accent 分支；正式畫面不得同時從底圖與物件層畫同一塊岩石或同一條路。

## 五、實作階段

### A0 — 凍結基準與可讀性樣本

- 固定 8 個 terrain fixtures，加上河橋、山隘、海岸各 1 個，共 11 個 Site。
- 保存相同 seed 的 full／close 預覽與每類資源座標、quantity、habitat reason。
- 先將現況問題標註為：底圖噪聲、地形不明、資源散點、通道遮擋、重複疊圖。

**Gate**：不改行為；現有懶生成、資源守恆、Site Runtime 與移動測試維持通過。

### A1 — Site 地面主題與邊界素材

- 重畫低噪聲地面 tile 與必要邊界／角落。
- `MapArtCatalog` 已加入 curated Site scene 查詢；八種 terrain 加上河橋場景都以完整俯視構圖底圖呈現，導航與資源仍由 LayoutData 提供。
- Plains、Forest、Mountain、Water、Sand、Snow、Swamp、Ocean 已完成第一版輪廓語言；後續只做針對性素材迭代，不再回退到宏觀地圖放大。

**Gate**：8 種 terrain fixture 均有專用素材；每張 full 預覽都可先讀到主地表，再讀到通道與高低差。

### A2 — 高度、水路與道路統一

- 以鄰格 mask 產生連續峭壁與岸線。
- 將道路、水、橋、樓梯收斂為單一正式繪製來源，移除同義疊圖。
- 保留 cardinal 通道；不新增斜向道路或斜向設施。

**Gate**：近景中沒有懸空路、道路穿水、橋下無水、樓梯未接上下層、峭壁中斷或重複岩壁。

### A3 — Region 適生權重統一

- 抽出一份純函式規則，供 Overview／Region allocation／lazy profile fallback 共用。
- `NavigationController.show_region()` 在 terrain 之後呼叫現有 `get_or_generate_region_site_content()`；只建立一份 packed Region data，不建立任何 Site Layout／Runtime。
- 一般 Site 與 POI Site 都從該 `region_cell` 的同一份 profile 套入 `SiteData`，移除 POI 專用資源量分支。
- 加入 terrain、moisture、elevation、ridge／river／coast 的硬限制。
- bump 相關 generation version，清除舊的 rebuildable cache；不碰 sparse Runtime Delta 語意。

**Gate**：同 seed 重建一致；Region 七資源總量等於 Manifest；正式進 Region 後 `region.site_content_data` 有效但 `site_runtime_states` 仍空；一般 Site／POI Site 都取同一 profile；進入 Region 前後同一 Site Profile 不漂移；水域沒有陸生資源。

### A4 — Site habitat placement 與群聚

- 將 hash-only 排序改為 habitat score + hash tie-break。
- 實作草斑、果樹間距、森林群、坡腳礦脈。
- 主要通道、入口、門、橋與樓梯建立固定 clearance。

**Gate**：所有 placement 符合規則；Profile quantity 守恆；同 seed stable ID／位置一致；採集後重進不復活；主要出入口始終有可走路徑。

### A5 — 資源 sprite 與正式預覽

- 只重畫七種現有資源，不在本輪加入新資源、季節、成長動畫或採集特效。
- 每種資源以輪廓和色相辨識，礦物不能只靠一個微小色點。
- 使用 `$godot-runtime-verify` 跑一次 editor、一次 focused headless、一次 GPU visual；任一失敗即停止，不反覆開 Godot。

目前以 11 個 fixture（22 張 full／close）作為回歸集；a28 已實際輸出並逐張檢查八種 terrain 與河橋場景。Godot 能輸出圖片不代表美術驗收通過；本輪確認縮小視圖先讀到地形構圖，再讀到資源與通道。

**Gate**：11 個 fixtures 各有 full／close 預覽；八種 terrain 與河橋場景已人工確認地形、資源、通行與疊圖；全景最低 30 FPS，a28 無 `SCRIPT ERROR`／Parse Error。後續 Gate 轉為資源群聚與正式遊戲流程覆蓋。

## 六、驗收矩陣

### 資料與效能

- 開局仍只有 packed World Overview，`WorldData.regions` 為空。
- 進 Region 才建立該 Region 的 packed Site content；進 Site 才建立 2,500 格 Layout。
- `RegionSiteContentData` 維持 packed、無 10,000 個 Dictionary／RefCounted profile。
- 七資源 Region 總量守恆；Site placed + unplaced 等於 Profile。
- 同 seed、版本、座標產生相同 layout、stable IDs 與預覽 signature。

### 視覺與玩法一致

- 不看 UI 可辨識八種 terrain theme。
- 河、海、岸線、道路、橋、樓梯、峭壁皆連續且位置與 navigation 一致。
- 草在濕潤開地，果樹在林緣／開闊地，森林成片，礦在露岩／坡腳；沒有平均灑點。
- 道路與入口乾淨，沒有資源、石頭或裝飾蓋住必要通道。
- 正式視圖沒有重複底圖、同義 overlay、Debug 線或隨機垃圾感。

## 七、明確延後

- 大型 POI 多 tile 建築與室內地圖；
- 季節切換、資源成長／再生模擬、掉落物與採集動畫；
- 新增魚、藥草、黏土等資源類別；
- 動物生態、NPC occupancy、每格 Node、第二套尋路或資源 manager；
- 為了模仿參考遊戲而複製其素材、UI 或高裝飾密度。

完成 A1–A5 後，Site 應先達到「像一張可探索、可判讀的遊戲地圖」，再考慮增加裝飾；裝飾不是本輪品質 Gate。



