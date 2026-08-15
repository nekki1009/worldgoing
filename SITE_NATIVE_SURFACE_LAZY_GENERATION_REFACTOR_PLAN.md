# Site 原生地表與三層延遲生成重構計畫

**審核日期**：2026-08-12  
**完成日期**：2026-08-12  
**狀態**：P0–P6 已完成並通過資料、Runtime、編輯器與實際 GPU 預覽驗收  
**適用規格**：`PROJECT_SPECIFICATION_V3.md`  
**架構依據**：`PROJECT_ARCHITECTURE.md`、`ARCHITECTURE_STATUS.md`  
**取代範圍**：取代目前以八種 Region 主地形直接充當 Site 地表的生成與美術方向；不改變 World／Region／Site 尺度、座標、Runtime owner 或 Seed + Delta 原則

## 實作完成摘要

- 開局只建立 256×256 packed `WorldOverviewData`；實際 `NavigationController.start()` 驗證 `WorldData.regions` 維持空白。
- 進入 Region 時才建立 packed `RegionSiteContentData`，七種資源配額使用確定性分配並與 `RegionGenerationManifest` 完全守恆。
- 進入 Site 時才建立 50×50 Layout。可佔格原生表面固定為泥土、岩石、河水、海水；峭壁由高度邊界推導。
- 草、果樹、森林、石／鐵／銀／金礦為可疊加 placement；橋、木／石梯、木／石牆與最小 7×5 木屋／9×7 石廳為設施或建築 placement。
- 採集、拆除 generated placement 與玩家新增／拆除設施只寫 Session-owned sparse Site Delta；`TravelRuntime` 重新驗證並解析 Base + Delta。
- `SiteLayoutGenerator` generation version 為 8；World／Region／Site 路徑採四方向 tile 邊，`SiteMap` 只繪製 detached resolved snapshot。
- P6 以實際 GPU 產生五場景各全景／近景共 10 張圖，逐張人工檢查；正交 tile 道路折線與連續乾淨路面已在全景與近景確認。最新 1280×720、VSync 關閉的 uncapped gate 最低量測 2134.40 FPS，僅用來證明通過 30 FPS 門檻，不作一般遊玩幀率承諾。

## 一、審核結論

此方案可行，並且比「先替每個 Strategic Cell 建立完整 Site」更符合目前的三層架構與效能目標。

正確的核心不是把所有內容壓成單一 terrain enum，而是把 Site 拆成互相獨立的四層：

1. **原生表面**：泥土、岩石、河水、海水。
2. **高度／邊界**：每格高度，以及高度差推導出的峭壁面。
3. **資源覆蓋**：草、果樹、森林、礦脈等可生成、採集、移除或再生的內容。
4. **設施／建築覆蓋**：橋、梯、牆及多格建築。

使用者提出的五種原生美術素材仍成立，但資料模型應視為「四種可佔格表面＋一種高度邊界」：

| 原生美術 | 資料語意 | 可站立 | 導航規則 |
|---|---|---:|---|
| 泥土地 | `DIRT` 表面 | 是 | 一般陸地 |
| 岩石地 | `ROCK` 表面 | 是 | 一般陸地，可有不同成本 |
| 峭壁 | 相鄰格高度差形成的邊界面 | 否 | 沒有梯／合法轉接就不可跨越 |
| 河 | `RIVER_WATER` 表面 | 否 | 橋、碼頭或日後的涉水規則才能通過 |
| 海 | `SEA_WATER` 表面 | 否 | 陸上單位不可通過；日後由船舶／港口處理 |

峭壁不能是角色可站立的第五種 floor，否則會出現角色站在垂直崖面、同一格同時是地板與牆等矛盾。現有 `elevation_levels`、`height_edge_flags` 與 `SiteTransitionData` 已具備正確基礎，不需另建第二套高度系統。

## 二、三層延遲生成契約

### 2.1 可預建 65,536 格 World Overview，不可預建完整 Region

目前 World 為 `256×256` World Cells，共 65,536 個 Region；每個 Region又有 `100×100` Strategic Cells。開局為 65,536 個 World tiles 建立數個 byte 的 Overview 是合理的；若為它們配置完整 Region 細格，才會涉及 655,360,000 個 Strategic Cells，與現有 lazy World 契約衝突。

因此「大地圖一開始算好總量與通道」定義為：**開局只建立一份固定大小、packed 的 `WorldOverviewData`，每個 World Cell 記錄資源配額級別、主要通道遮罩與縮圖分類；`RegionData`、`100×100` 配置與所有 Site Layout 仍只在查詢／進入時建立。** 若開局 benchmark 顯示 Overview 超過預算，同一 deterministic generator 可降級為分塊／可見區 lazy 產生，而不改資料結果。

### 2.2 各層輸出

| 層級 | 生成時機 | 只產生／解析 | 不產生 |
|---|---|---|---|
| World | 開局產生 packed Overview；選取／查詢時按需展開單格 Manifest | `WorldOverviewData`＋`RegionGenerationManifest`：生態／資源配額、主要河流與道路的邊界端點、海岸／山脊摘要、POI 身分 | `RegionData` 實例、`100×100` Region 細格、完整 Site Layout、資源物件 |
| Region | 玩家進入 Region，或戰略尋路需要特定格時 | 現有 `RegionTerrainData`、道路覆蓋，以及每個 Strategic Cell 的 `SiteContentProfile`；把 Manifest 配額確定性分配到格 | `50×50` Site 細節、樹木／礦石實體、Scene Node |
| Site | 玩家進入 Site、Battle／玩法明確要求該 Site 時 | `SiteLayoutData`：2,500 格原生表面、高度、峭壁邊、資源斑塊與設施 footprint；再合併 sparse Site Delta | 其他 9,999 個 Site Layout、每格 Node、永久渲染快取 |

### 2.3 上層承諾、下層落位

延遲生成仍須保持跨層一致：

- World Manifest 決定一個 Region 的**配額範圍**與**跨邊界通道端點**。
- Region 生成器只能把這些配額分配到 Strategic Cells，總量必須守恆，且道路、河流、海岸與山口端點必須接續相鄰 Region。
- `SiteContentProfile` 決定某 Strategic Cell 展開後的**資源總量／密度、原生表面比例、入口出口與設施需求**。
- Site 生成器只決定 50×50 格內的具體位置；不能改寫 Region 已承諾的資源量、河流方向、道路出口或隘口通道。
- 清除任何 generated cache 後，使用相同 World Seed、座標與 generation version 必須得到相同結果。

## 三、資料模型

### 3.1 `WorldOverviewData` 與 `RegionGenerationManifest`（新增輕量 Base）

`WorldOverviewData` 是開局可一次產生的 fixed-size packed arrays；每個 World Cell 只保存顯示與下一層生成必需的摘要：

- `biome_code: PackedByteArray`
- `resource_budgets: PackedInt32Array`：以 `[world_index * RESOURCE_COUNT + resource_type]` 保存七種資源的整數預算單位
- `passage_mask: PackedByteArray`：採用 World／Region／Site 共用的四方向 tile 邊，不產生斜向出口
- `coast／river／ridge flags: PackedByteArray`

七種 `int32` 預算加上三個 byte channel 約為 2 MiB；這比自行實作 bit packing 簡單，且不建立 65,536 個 Dictionary／RefCounted 物件。`resource_budgets` 是草覆蓋、樹林材積或礦量等「預算單位」，不是預先建立的植物／礦石數量。

選取或進入某個 World Cell 時，再由相同 Seed 與 Overview 展開一份 `RegionGenerationManifest`，建議包含：

- `world_cell`
- `world_seed_stamp`、`generation_version`
- `climate_summary`：溫度、濕度、高程區間
- `surface_quota`：泥土／岩石／河／海的約束或比例區間
- `resource_quota`：各資源的 Region 總量或密度預算
- `edge_contracts`：北東南西邊界的河、道路、海岸、山脊／可通行口端點
- `poi_ids`／Route 身分參考（沿用既有穩定 ID owner）

Overview 與 Manifest 都是 generated Base／cache，不是 Session state，也不寫入存檔。為避免形成平行系統，應由 `WorldData` 持有查詢與快取，並沿用 `WorldMacroTerrainSampler`、`WorldRoadGenerator` 與既有 Seed API。Overview 只能保存完整生成結果的摘要，不可成為另一套會與 Region 生成不一致的隨機來源。

WorldMap 的全圖底色、資源圖例與主要通道直接讀 Overview；只有玩家放大、選取或進入 World Cell 時，才沿用目前的可見區 thumbnail／POI／Route 查詢。Overview 的 `passage_mask` 表示自然地形可通方向；道路仍由既有 `WorldRoadGenerator` 產生並保留穩定 Route ID，不能在開局為全世界預建詳細道路圖。

### 3.2 `SiteContentProfile`（擴充現有 Site Travel Profile）

每個 Strategic Cell 的輕量資料建議包含：

- 現有：`terrain_type`、`site_landform`、`passable`、travel cost、road／river／crossing、`travel_exit_mask`。
- 新增原生表面摘要：`native_surface_hint`、`rock_ratio`、`river_width_class`、`coast_mask`。
- 新增資源摘要：每類資源的 `amount` 或 `density_class`，以及可選的再生參數 ID。
- 新增設施摘要：必需的橋、梯、牆／建築 footprint 參考；程序生成設施與玩家建造設施要有不同 stable ID namespace。

這份 Profile 應由目前 `WorldData.sample_travel_data()` 的查詢路徑擴充，或改名後保留同一 owner；不可另做一個會與戰略尋路結果不同步的 Resource Manager。

### 3.3 `SiteLayoutData`（重構 generated detail）

保留現有 `50×50`、每格 `2m×2m`，並將 Site 詳細 Base 明確拆成：

- `native_surface_cells: PackedByteArray`：每格 `DIRT／ROCK／RIVER_WATER／SEA_WATER`。
- `elevation_levels: PackedInt32Array`：現有欄位，保留。
- `height_edge_flags: PackedByteArray`：現有欄位，峭壁由高度差推導。
- `resource_placements`：資料記錄陣列；每筆有 stable generated ID、resource type、footprint／cell、quantity、growth state seed。
- `facility_placements`：橋、梯與建築的佔格資料；牆另外保存為共享格邊資料，方向只允許水平／垂直。
- `transitions`：保留現有樓梯、橋等合法高度／水面轉接，並由設施資料衍生或交叉驗證。
- `surface_flags`：保留為現有 Runtime／renderer 的編譯相容層；只能由原生表面、資源／設施與 transition 推導，不能被另一條生成路徑獨立改寫。
- `navigation_flags`：由上述資料編譯出的查詢結果，不成為另一份可獨立修改的真實來源。

初版固定陣列約為數 KB／Site，只有進入時才建立，離開後可釋放；玩家改動仍只保存在 `SiteRuntimeState` 的 sparse Delta。

### 3.4 疊加與佔用規則

- 每格必須且只能有一種原生表面。
- 草、積雪、沙質、濕地等非實體 overlay 可以與地表共存，不單獨佔用導航格。
- 果樹、森林 trunk、礦脈等實體資源必須有 footprint；樹冠等視覺可以越界，但互動與碰撞只認 footprint。
- 橋與樓梯佔格並建立 transition；牆佔兩個相鄰格之間的 shared edge；建築佔一組多格 footprint。
- 實體資源不得與牆、橋、樓梯、門或建築 footprint 重疊；生成順序固定為通道／水系 → 高度／峭壁 → 必要設施 → 建築 → 資源 → 純視覺 overlay。
- 若配額因必要通道／設施沒有合法空間而無法在該 Site 放完，剩餘量必須由 Region 的穩定分配規則移往同 Region 的合法 Site，不能靜默消失或改變 World 總量。

## 四、資源分類與生成規則

### 4.1 初始資源表

| 資源 | 生成條件 | footprint 建議 | 備註 |
|---|---|---:|---|
| 草 | 泥土、有足夠濕度、非水面／設施 | 1格或斑塊 | 草本體可被動物食用；果實是同一資源的產出狀態，不另鋪地表 |
| 果樹 | 泥土、非極端乾冷、預留樹冠間距 | 1格 trunk＋視覺可跨格 | 果實屬樹的產出／庫存 |
| 森林 | 由多棵樹或林分 footprint 組成 | 多格斑塊 | Region 可用 coverage／木材量摘要，Site 才落樹位 |
| 石礦 | 岩石地、高程／地質信號 | 多格礦脈 | 不應均勻撒單格石頭 |
| 鐵礦 | 岩石地＋地質稀有度 | 多格礦脈 | 配額低於石礦 |
| 銀礦 | 岩石地＋更高稀有度 | 多格礦脈 | Region 配額可為 0 |
| 金礦 | 岩石地＋極低稀有度 | 多格礦脈 | 不保證每個 Region／Site 都有 |

資源量必須分成兩個概念：`placement footprint` 是佔據哪些格，`quantity` 是可採集量；不能以「畫了幾棵樹／幾塊石頭」直接當作唯一資源數值。

### 4.2 原八種主地形的重新解釋

World／Region 仍可保留平原、森林、山地、水域、沙地、雪地、沼澤、海洋八種**宏觀生態／戰略分類**，但尋路與道路拓撲統一只沿北／東／南／西 tile 邊；進入 Site 後不要直接使用八套互斥地板：

- 平原：泥土地＋高草覆蓋。
- 森林：泥土地＋高樹木／森林覆蓋。
- 山地：岩石地＋高度／峭壁＋礦脈。
- 水域：泥土／岩石河岸＋河水。
- 沙地：泥土地的乾燥／沙質視覺變體，初版可作 material variant，不增加導航地表種類。
- 雪地：泥土／岩石上的積雪覆蓋或季節 material variant。
- 沼澤：泥土地＋淺水／濕地覆蓋；若日後需要泥濘成本，再加 surface modifier，而非新建一套座標。
- 海洋：海水＋岸邊泥土／岩石。

因此「八種地形」仍服務 World／Region 的宏觀判斷，「四種原生表面」服務 Site 的逐格實體場景，四方向 tile 路徑是跨層共用的幾何契約，兩者不是互相衝突的 enum 替換。

## 五、設施與建築

### 5.1 基本設施

| 設施 | 方向 | 導航／高度語意 |
|---|---|---|
| 橋 | 水平／垂直 | 覆蓋河／水面格，建立合法 crossing；長度由 footprint 決定 |
| 木梯 | 水平／垂直 | 連接不同高度，較低耐久／成本；方向是上升軸，不使用斜圖 |
| 石梯 | 水平／垂直 | 同木梯，但材質／耐久／建造條件不同 |
| 木牆 | 水平／垂直 | 位於相鄰格的 shared edge，阻擋跨邊移動 |
| 石牆 | 水平／垂直 | 同木牆，但耐久／高度不同 |

「只做上下與左右」可行，且符合目前 Site 移動先以 cardinal direction 為主的契約。橋與牆只需保存 `HORIZONTAL／VERTICAL`；樓梯以現有 transition 的低端格／高端格表達上升方向。美術只需兩個軸向基礎素材，再由顯示層旋轉／翻轉，不需要四套獨立玩法資料。

### 5.2 人工建築不可窮舉的處理

不建立一個列完所有房屋、城堡、工坊的超大 enum。建築採資料驅動的多格組合：

- `building_definition_id` 指向 Catalog／資料表。
- `origin_cell`、`footprint_size`、`orientation` 決定佔地。
- definition 內由 floor、wall、door、roof、transition、interaction socket 等部件組成。
- 程序生成與玩家建造都寫相同 placement 格式，但 stable ID namespace 與 Delta 來源不同。
- 大型 POI 仍由多格／多部件構成，不回退成一張巨大貼圖或單一 2m tile。

第一階段只實作能驗證系統的最小 Catalog：一座橋、木梯、石梯、木牆、石牆，以及一個簡單矩形房屋。其他建築在實際玩法需要時增加 definition，不先預建抽象建築框架。

## 六、隘口生成

隘口正式定義為：**兩側不可直接跨越的峭壁／高地之間，連接兩個或以上戰略出口的可通行走廊。**

生成順序：

1. 從 `travel_exit_mask` 取得 Region 已承諾的真實道路出口。
2. 在 Site 內建立連接出口的地面走廊。
3. 走廊兩側提高 `elevation_levels`，由高度差自動推導 `height_edge_flags`／峭壁面。
4. 通道本身保持泥土或岩石可站立表面；峭壁不是通道地表。
5. 只有設計要求登上高地時才放木梯／石梯；樓梯不是每個隘口的必要元素。
6. `TravelRuntime` 與 Site A* 讀同一份高度、峭壁與 transition 結果；`SiteMap` 只渲染。

這會取代目前「MOUNTAIN_PASS corridor 外直接標 `NAV_BLOCKED`」的單一 placeholder 思路，但保留同一 `travel_exit_mask` 與 typed `BLOCKED` 行為。

## 七、Runtime、Delta 與存檔邊界

- `WorldData`：packed World Overview、generated Manifest、Region base、Profile 的唯一查詢／cache owner。
- `WorldData.sample_travel_data()`：仍要能直接由 Global Strategic Cell 取樣供跨 Region A* 使用；它可以讀 Overview／Manifest 與現有 sampler，但不得因此展開整個 Region。進入 Region 才產生完整 `SiteContentProfile` 陣列。
- `RegionData`／既有生成器：可重建 Region Base；不保存玩家採集或建設。
- `RegionStateResolver`：Region Base + Delta 的唯讀解析路徑保持不變。
- `SiteLayoutGenerator`：只從 `SiteData／SiteContentProfile` 產生 detached Site Base。
- `GameSession.site_runtime_states`：只在進入或修改 Site 時建立。
- `SiteRuntimeState`：記錄被採集／移除的 generated resource ID、資源狀態變化、玩家新增／拆除的 facility placement；不複製 2,500 格 Base。
- `TravelRuntime`：保持 Site 移動、尋路、建設／採集命令重新驗證的 owner。
- `SiteMap`：只繪製 resolved snapshot，不保存資源量、碰撞或建築真實狀態。

重生中的草／果實若需要按時間恢復，Delta 只存 `last_harvest_time` 或 depleted state；不為每株植物建立常駐 Timer／Node。

## 八、實作階段

### P0：凍結契約與基準（完成）

- 記錄現有 Seed、POI ID、Route ID、MOUNTAIN_PASS fixture、World／Region／Site 生成 hash 與啟動時間。
- 補一個測試證明 World 初始化只建立 packed Overview，不建立 65,536 個 `RegionData` 或任何完整 Site。
- 記錄 Overview 生成時間與實際 payload；初始 Gate 為開局額外耗時不超過 1 秒、Overview payload 不超過 4 MiB。
- 將本計畫核准後的地表／資源／設施語意同步到 V3 與架構狀態文件。

**Gate**：現有 terrain、road、travel、Site runtime、Site detailed scene 測試維持通過。

### P1：Packed World Overview、Manifest 與 Profile 摘要（完成）

- 新增 `WorldOverviewData`，以 packed arrays 保存 256×256 的配額級別與通道摘要。
- 新增小型 `RegionGenerationManifest` 資料類型與 deterministic generator。
- `WorldData` 開局產生 Overview，但仍按需建立／cache Manifest 與 `RegionData`。
- 由現有 sampler／road owner 產生共享邊界 contract。
- 先擴充現有 lazy Site Travel Profile 的單格查詢，加入原生表面與資源配額摘要；不在 P1 配置全 Region 的 10,000 筆 Profile 物件。

**Gate**：同 Seed 重建相同；相鄰 Region 邊界 contract 完全相等；清 cache 後 hash 不變；Overview ≤ 4 MiB 且目標硬體生成 ≤ 1 秒；開局 `WorldData.regions` 仍為空。若超過時間 Gate，改為每幀分塊產生並先畫已完成區塊，不改生成結果。

### P2：Region 配額分配（完成）

- Region 進入時產生現有 `100×100` Base，並把 Manifest 配額確定性分配到 `SiteContentProfile`。
- Profile 用 packed channels 或一份 Region-sized data object 保存，不建立 10,000 個 Dictionary／RefCounted profile 物件。
- 河、道路、海岸、山脊和隘口必須遵守邊界 contract。
- 使用整數 largest-remainder／穩定排序分配配額，避免四捨五入後總量漂移。
- RegionMap 只顯示彙整圖示／密度，不建立 Site placement。

**Gate**：各資源 Region 分配總量等於 Manifest；相鄰通道接續；未進入 Site 時沒有任何 2,500 格 Site Layout 或 SiteRuntimeState。

### P3：Site 原生表面重構（完成）

- 在 `SiteLayoutData` 加入四種 `native_surface_cells`。
- `elevation_levels` 產生高地，`height_edge_flags` 統一推導峭壁。
- 河／海使用水面；山地使用岩石；其餘以泥土為主。
- 重寫導航編譯：水面、峭壁、橋／梯 transition 來自同一 Base。
- `SiteMap` 先以清楚色塊驗證四種表面與峭壁，再接美術資產。

**Gate**：角色不能站在峭壁面或未設橋的水面；不同高度沒有 transition 時不可跨越；四種表面比例符合 Profile 容差。

### P4：資源 placement 與 sparse Delta（完成）

- 實作草、果樹、森林、石／鐵／銀／金礦的 deterministic placement。
- 每個 generated resource 有 stable ID、footprint 與 quantity。
- 採集／移除只寫 `SiteRuntimeState` sparse Delta；清 Base cache 後可正確重建 resolved state。
- 暫不加入完整生態 AI、經濟、生產鏈或每物件 Node。

**Gate**：Site 資源總量等於 Profile；稀有礦允許為 0；採集後重進 Site 不復活，清 generated cache 也不復活；未修改 Site 不配置 Runtime。

### P5：設施、轉接與最小建築（完成）

- 橋、木／石梯、木／石牆只支援水平／垂直。
- 以現有 `SiteTransitionData` 驗證橋／梯，不建立第二套 crossing 資料。
- 建立一個多格矩形房屋 definition，驗證門、牆、室內地板與 footprint。
- 玩家新增／拆除設施只寫 sparse Delta，命令必須重新驗證佔地、表面、高度與連接。

**Gate**：設施方向、佔地、導航與畫面一致；橋移除後水面恢復不可行；梯移除後高度差恢復阻擋；牆不能被直接穿越。

### P6：美術重接與實際預覽驗收（完成）

- 原生素材只做泥土、岩石、峭壁、河、海五類；沙／雪／沼澤改為 overlay／material variant。
- 資源與設施各自使用可組合 sprite，方向由旋轉／水平垂直變體處理。
- 生成至少五張非 headless 實際預覽：一般草地、森林與果樹、礦區、雙峭壁隘口、河流＋橋＋不同高度樓梯。
- 預覽必須隱藏 debug UI，包含全景與近景，逐張人工檢查；測試通過不能取代視覺驗收。

**Gate**：實際預覽中原生表面、資源、設施、峭壁／高度與導航位置一致；Site 近景維持至少 30 FPS；無 `SCRIPT ERROR`／Parse Error。

### 完成證據

- `site_native_surface_refactor_test.gd`：9/9，涵蓋 Overview 預算與零 Region 啟動、共享邊界、七資源守恆、四原生表面、橋／梯移除、7×5 房屋門牆與 sparse Delta。
- `site_detailed_scene_test.gd`：6/6；`site_visual_scale_test.gd`：8/8；`visual_composition_test.gd`：8/8。
- Site Runtime 36/36、Cross-Region Travel 18/18、Party movement 16/16、Runtime command/query 19/19、Battle 20/20、Persistence 10/10 與相關 terrain／road／architecture 測試皆以 exit 0 通過。
- 隔離 `APPDATA`／`LOCALAPPDATA` 的 Godot editor scan 為 exit 0，沒有專案 `SCRIPT ERROR`、Parse Error 或 `res://` 資源載入錯誤；Windows 根憑證讀取警告屬環境訊息。
- 實際預覽輸出：`.visual_captures/site_native_surface_p6/`；GPU 驗收日誌：`.godot-temp/p6_gpu_final/preview_out.txt`。

## 九、明確不做

- 不在開局配置 65,536 個 `RegionData` 或完整 Region；只允許一次線性產生 packed World Overview。
- 不預建 655,360,000 個 Strategic Cells 或其 Site。
- 不把每棵樹、每塊草、每面牆變成常駐 Node。
- 不新建第二套座標、Seed、尋路、資源 Manager、事件匯流排或 ECS。
- 不把 World／Region 的八種宏觀生態分類直接刪除；只改變其投影到 Site 的方式。
- 不在此重構中一併實作完整農業、生態、採礦加工、建築施工、耐久、船舶或經濟。
- 不先列舉所有人工建築；以資料驅動 definition 按玩法逐步增加。

## 十、完成定義

本重構只有在下列條件同時成立才算完成：

1. World 啟動只建立受預算約束的 packed Overview；`RegionData`、全世界細格與 Site 仍維持 lazy。
2. World Overview／Manifest → Region Profile → Site Layout 的配額與通道可追溯且守恆。
3. 相同 Seed／座標／版本清 cache 後結果一致，相鄰 Region 邊界完全接續。
4. Site 只有泥土、岩石、河水、海水四種可佔格原生表面；峭壁只由高度邊界產生。
5. 草／樹／森林／礦脈與橋／梯／牆／建築是可疊加資料，不污染原生表面 enum。
6. 隘口是兩側峭壁間的真實通道，戰略出口、局部導航與畫面一致。
7. 未進入且未修改的 Site 不建立 Runtime；玩家變更只寫 sparse Delta。
8. focused tests、Main 啟動、實際 GPU 預覽及 30 FPS gate 全部通過。
