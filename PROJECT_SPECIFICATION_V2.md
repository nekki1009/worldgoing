### Worldgoing 專案規格書 (Project Specification Document)
**版本** ：v2.0.0 (微縮烘焙與動態紙娃娃整合版)
**引擎需求** ：Godot Engine 4.6+ (Forward Plus / D3D12, Jolt Physics 3D)
**核心架構原則** ：資料模型先於顯示 (Data-First) [1]、確定性程序生成 (Deterministic PCG) [1]、單一美術資產依賴 (Site-Only Art Assets)、三層獨立地圖與微縮烘焙契約 (Three-Tier Map & Minimap Baking)、Seed + Delta 稀疏持久化 (Sparse Persistence) [1]。

--------------------------------------------------------------------------------

#### 一、 專案總覽與系統目標 (Project Overview)
##### 1.1 專案簡介
Worldgoing 是一款基於 Godot 4.6 引擎開發的高自由度沙盒戰略 RPG [2]。遊戲世界採用程序化生成技術，提供從全局宏觀世界到局部細部戰術場景的無縫切換體驗 [2]。

##### 1.2 設計哲學與核心原則
1.  **資料與顯示嚴格分離 (Data-View Separation)** [2]：
    *  資料層 (GameSession, WorldData, RegionData, SiteData) 為唯一的真實來源 (Single Source of Truth) [2]。
    *  顯示層 (WorldMap, RegionMap, SiteMap, BattleSiteMap) 僅作為無狀態消費者 (Stateless Consumers) [2]，可以隨時銷毀並由資料或快照重建 [2]，不保存任何獨占遊戲邏輯。
2.  **單一美術資產依賴與微縮烘焙 (Site-Only Art & Minimap Baking)**：
    *   **美術資產零冗餘**：專案**僅維護與繪製 Site Layer 規格（2m × 2m 比例）的地形與裝飾美術瓷磚**。Region Layer（戰略層）不維護任何獨立的大地圖 Tileset。
    *   **動態微縮烘焙契約**：在遊戲載入或區域編譯時，系統利用後台 `SubViewport` 將各個 Site（50×50 局部網格）的地形數據以 Site 級美術自動繪製，再透過**最近鄰插值（Nearest Neighbor）**等比例降採樣為 $32 \times 32$ 像素的微縮瓷磚，拼接組合成 `RegionMap` 的動態紋理集（Dynamic Texture Atlas）。這在保證 100% 戰術與戰略地標視覺一致性的同時，降低了美術資源生產量 50% 以上。
3.  **三層地圖無縫契約 (Three-Tier Map Architecture)** [2]：
    *   **世界層 (World Layer)** ：全局時間、Region 間地理關係與 Party 戰略位置 [2]。
    *   **戰略層 (Region Layer)** ：100×100 戰略格子 (10km × 10km 範圍) [2]，地形由 Site 級微縮貼圖動態拼裝。
    *   **局部場景層 (Site Layer)** ：50×50 局部格子 (100m × 100m 範圍) [2]，負責村莊、遺跡、洞穴等微觀互動與戰術探索 [2, 5]。
4.  **可重現的程序生成與稀疏變更 (Deterministic PCG & Sparse Delta)** [2]：
    *  不保存大量未修改的地形與地圖陣列；僅保存 World Seed + Sparse Delta [2]。
    *  同一 Seed 與參數在任何平台均能確定性地重建完全相同的世界 [2]。

--------------------------------------------------------------------------------

#### 二、 三層架構與座標契約 (Architecture & Coordinate Systems)
##### 2.1 三層地圖層級定義
| 地層名稱 | 網格尺寸 (Grid Size) | 單格實際尺寸 (Cell Extent) | 整區實際範圍 (Total Extent) | 權威資料結構 | 視圖組件 (View Node) | 美術資產來源 |
| ------ | ------ | ------ | ------ | ------ | ------ | ------ |
| **World Layer** [3] | 無限整數網格 (x, y) [3] | 10km × 10km [3] | 無上限 [3] | WorldData, PartyData [3] | WorldMap [3] | 特製 POI 圖示包 [6] |
| **Region Layer** [3] | 100 × 100 Strategic Cells [3] | 100m × 100m [3] | 10km × 10km [3] | RegionData, RegionRuntimeState [3] | RegionMap [3] | **後台動態微縮烘焙 (32x32px)** |
| **Site Layer** [3] | 50 × 50 Local Cells [3] | 2m × 2m [3] | 100m × 100m [3] | SiteData, SiteRuntimeState [3] | SiteMap [3] | 標準 2m 規格 Autotiles & Decals |

##### 2.2 座標系統與數學換算契約 (WorldCoordinates) [4]
專案提供 WorldCoordinates (scripts/core/world_coordinates.gd) 靜態工具，實現跨層級座標的可逆換算，並嚴格處理負數座標的地板除法 (Floor Division) [4]：
1.  **戰略格全域座標 (Global Region Cell)** [4]：  $$\text{global\_cell.x} = \text{world\_cell.x} \times 100 + \text{region\_cell.x}$$   $$\text{global\_cell.y} = \text{world\_cell.y} \times 100 + \text{region\_cell.y}$$
2.  **全域公尺座標 (Global Meters)** [4]：  $$\text{global\_meters} = \text{global\_cell} \times 100\text{m}$$
3.  **負數座標安全逆向換算 (Global to Region)** [4]：
    *  world_cell.x = floori(global_cell.x / 100.0) [4]
    *  region_cell.x = posmod(global_cell.x, 100) [4]
4.  **Site 座標對齊契約** [4]：
    *  一張 50×50（每格 2m）的 Site 局部地圖，總範圍為 100m×100m，精確相等於其父 Strategic Cell 的世界公尺邊界 [4]。
    *  進入 Site 時，Party 預設錨點為局部中央座標 (25, 25) [4]。

--------------------------------------------------------------------------------

#### 三、 程序化生成與地形道路系統 (Procedural Generation Engine)
##### 3.1 確定性雜湊與 Seed 衍生 (DeterministicHash) [5]
專案採用自研確定性雜湊演算法 (scripts/core/deterministic_hash.gd) [5]，確保跨平台、跨執行階段的完全一致性 [5]：
*   **Region Seed 衍生公式** [5]： RegionData.seed = DeterministicHash.combine_seeds(world_seed, world_cell.x, world_cell.y, gen_version)
*   **Site Seed 衍生公式** [5]： SiteData.site_seed = DeterministicHash.combine_seeds(world_seed, poi_id.hash(), version)

##### 3.2 戰略地形微縮烘焙管線 (Strategic Terrain & Viewport Map Baker)
*  **資料層確定性計算**：針對 100×100 網格，`RegionTerrainGenerator` 結合多層噪聲 (Noise) 與細胞自動機 (Cellular Automata) 產生基本地形分佈 [6]。
*  **微縮烘焙器 (MapBaker)**：
   1. 載入載入畫面時，系統調用後台 `SubViewport` 節點。
   2. 針對該 Region 的每個 50×50 Site 資料，利用 Site 級別的 2m 地面自動瓷磚（Autotiles）在 Viewport 內進行高速、無節點虛擬繪製。
   3. 繪製完成後，透過 GLSL 著色器或 Godot Image 介面，使用 **最近鄰插值（Nearest Neighbor）** 算法將其縮小為一張 $32 \times 32$ 像素的獨立貼圖（代表該 100m×100m 的 Strategic Cell）。
   4. 將這 $100 \times 100$ 張微縮貼圖動態拼裝成大紋理集（Dynamic Texture Atlas）推送至 GPU 進行 Region Layer 渲染，達成極致的 $O(1)$ 繪製呼叫 (Single Draw Call) 效能。
*  相鄰 Region 邊界透過全域座標邊界噪聲與確定性接點規則，保證跨區地形流暢接續 [6]。

##### 3.3 POI 興趣點生成器 (WorldPOIGenerator) [6]
*  程序化於世界戰略網格中分散放置 POI 點位，包含：VILLAGE (村莊)、CASTLE (城堡)、RUINS (遺跡)、CAVE (洞穴) [6]。
*  每個 POI 擁有穩定且全域唯一的 poi_id [6]。

##### 3.4 跨區道路圖網絡生成器 (WorldRoadGenerator) [6]
*  建立基於地形移動成本的跨區道路圖 (Graph Pathfinding) [6]。
*  使用 AStar2D / WeightedGridPathfinder 計算跨 POI 最優路徑，並寫入 RegionRoadOverlay [6]。
*  自動限制道路分支度 (Degree Limit) 與長度 (Corridor Bound 48 Cells) [6]，防止道路無限蔓延。

--------------------------------------------------------------------------------

#### 四、 運行時服務與狀態管理 (Runtime Layer & Architecture Boundaries) [7]
專案嚴格區分「靜態生成資料」、「運行時 Session 權威」與「顯示介面」 [7]：
##### 4.1 核心 Session (GameSession) [7]
*  擁有全局世界 Seed (world_seed)、遊戲時間 (world_time_seconds) [7]。
*  擁有玩家隊伍權威資料 (PartyData) [7]。
*  以字典形式延遲持有各區變更狀態：region_runtime_states (Dictionary[Vector2i, RegionRuntimeState]) 與 site_runtime_states (Dictionary[String, SiteRuntimeState]) [7]。

##### 4.2 移動與旅程運行時 (TravelRuntime) [7]
*  提供唯讀查詢 API：query_travel_preview()、query_site_snapshot()、query_site_entry() [7]。
*  掌控移動生命週期：start_travel() $\rightarrow$ commit_travel_step() $\rightarrow$ finish_travel() / cancel_travel() [7]。
*  移動時自動更新 PartyData.current_global_region_cell 並推進 GameSession.world_time_seconds [7]。

##### 4.3 戰略建置與 Delta 解析 (RegionRuntime & RegionStateResolver) [8]
*   **Base + Delta 模型**：原始地形由 Seed 重建 (Base)，玩家改動寫入 RegionDelta (Sparse Overrides) [8]。
*   **哨所建置 (Outpost Construction)** [8]：
    *  query_outpost_preview()：驗證通行性與隊伍位置，回傳唯讀預覽結果 [8]。
    *  place_outpost() / remove_outpost()：將穩定紀錄 outpost:x:y:cell_x:cell_y 寫入/刪除於 RegionDelta 中 [8]。

--------------------------------------------------------------------------------

#### 五、 戰術戰場、指揮權與兵裝紙娃娃系統 (Battle Engine, Command & Graphics)
##### 5.1 戰術地圖合成 (Battle Composite) [9]
*  戰場由 9 個相鄰 Site 大小 (50×50 Grid, 2m/cell) 之 Base 拼接而成 [9]，總網格為 **150×150** [9]，實際尺寸為 **300m × 300m** [9]。
*  `BattleSiteGenerator` 確定性生成戰場地形、道路與河流渡口標記 [9]，不建立 9 個 POI 實體 [9]。

##### 5.2 隊形控制與「領隊軌跡跟隨（Breadcrumb Trajectory）」
*  **隊形結構**：以 **Formation (100人隊形)** 為最小命令與模擬單位 [9]，開闊地形佔用空間為 20m × 10m（$20 \times 5$ 的視覺偏偏移網格） [9]。
*  **領隊歷史軌跡 (Breadcrumbs)**：在資料層中，僅對 Formation 的領隊（Leader/Anchor）進行尋路 [9]。領隊在行進時寫入一組最近通過的歷史坐標點與方向朝向。
*  **距離追溯與二分插值**：後方 99 名部下不進行任何物理或 RVO 碰撞避障。各士兵依據其排數（Row）與列數（Col），在 $O(\log M)$ 時間內透過二分搜尋定位其在領隊歷史軌跡上的目標距離點，利用 LERP（線性座標插值）與 SLERP（球面角度插值）算出精確世界公尺坐標，保障 **100% 確定性重播**。
*  **窄道狀態機與寬度壓縮 (State Machine & Scale Morphing)**：
   *  `NORMAL`（開闊地形）：隊形寬度比例 $1.0$（20m寬），速度補償 $1.0$。
   *  `CHOKE`（窄道/河流渡口）：當領隊探測到前方窄道時，隊形寬度比例平滑收縮至 $0.1 \sim 0.2$（2m寬縱隊），且速度補償提升至 $1.2 \sim 1.3$（防止尾端脫節滯後）。
   *  `REGROUPING`（出口重組）：領隊抵達開闊出口，速度降低至 $0.5$ 等待後排，寬度漸變恢復至 $1.0$，當最後一名部下離開窄道判定區時，恢復為 `NORMAL` 狀態。

##### 5.3 紙娃娃動態烘焙與 GPU MultiMesh 著色渲染
*  **GPU 實例化繪製**：`BattleSiteMap` 使用單一 `GPU MultiMeshInstance2D` 繪製個人圓形標記 [9]。一隊 100 人即擁有 100 個繪製實例 [9]，整場戰鬥雙方總兵力支持 **9,000 人**（90 個 Formations）[9]，並穩定在 60 FPS [9]。
*  **動態貼圖集烘焙器 (PaperDollBakery)**：
   1. **部下兵裝統一化**：同一個 Formation 的 99 名部下身穿統一的該兵種「男女兵裝模板」，僅有 1 位隊長與特殊英雄擁有動態獨立外觀。此舉讓 9,000 人戰場的動態紙娃娃節點數由 9,000 降至 90，大幅削減 CPU 負載。
   2. **確定性性別比例**：部隊中男女比例（Gender Ratio）由背後城鎮人口與兵源資料庫之真實生物學結構（Demographic Census）確定性賦值，不使用隨機權重，確保存檔與模擬的 100% 一致性。
   3. **重型裝甲男女共用 (Unisex Armor)**：金屬板甲、鎖子甲等重裝，不論男女皆載入同一個 Unisex 貼圖；輕型/中型裝備則微調胸腰線，共用相同骨骼坐標，節省美術工作量。
   4. **貼圖陣列（Texture2DArray）與著色器**：加載畫面中，`SubViewport` 將這 90 個隊長外觀與 10 個兵種男女模板的外觀組合、動作、4方向影格動態烘焙成貼圖集，封裝進一個 `Texture2DArray`。
   5. 運行時，將每個單位的「變體 ID (variant_id)」、「動畫幀 (frame_index)」與「左右鏡像 (flip_h)」透過 Color 格式傳入 MultiMesh 的 `Instance Custom Data`。GPU CanvasItem Shader 根據此數據進行 1 Draw Call 的並行極速採樣繪製。

##### 5.4 指揮權與命令發送鏈 (BattlePreviewRuntime) [9]
| 命令類型 | 代表命令 | 適用對象 | 通訊機制與行為 |
| ------ | ------ | ------ | ------ |
| **直屬命令** [9] | MOVE_TO, SET_FACING 等 [9] | 指揮官本隊 (Commander Formation) [9] | **立即生效** ，無通訊延遲 [9]。 |
| **簡單命令** [9] | ADVANCE, FALL_BACK, ATTACK, WITHDRAW, FLANK_REAR [9] | 下屬隊伍 (Subordinate Formation) [9] | **確定性延遲** (Deterministic Signal Delay) [9]，排入 pending_orders [9]，時間到達後套用意圖。 |
| **精細命令** [9] | MOVE_TO, SET_FACING, HOLD_POSITION, FOCUS_TARGET [9] | 下屬隊伍 (Subordinate Formation) [9] | **Data-only 傳令兵 (Dispatch)** [9] 攜帶 BattleOrderData 沿路徑移動 [9]。 |

##### 5.5 傳令兵攔截與隊長自治 [10]
*  **傳令兵攔截 (Messenger Line-Segment Interception)**：傳令兵為 `BattleDispatchData`（Data-only 結構，無物理節點） [10]。每 tick 更新位置，檢查其**移動線段 (Line Segment)** 是否進入敵方 Formation 之攔截半徑。若遭攔截，命令狀態改為 `MESSENGER_INTERCEPTED`，精細命令永不套用 [10]。
*  **隊長自治 (Captain Autonomy)**：當 Formation 與敵方直接接觸（Direct Contact）時，觸發 CAPTAIN_AUTONOMY 局部決策。接敵期間遠端傳令命令保持佇列（Deferred），脫離接觸後恢復執行 [10]。

--------------------------------------------------------------------------------

#### 六、 持久化與狀態隔離契約 (Persistence & File Security) [11]
##### 6.1 持久化哲學 (Seed + Delta Save) [11]
專案持久化服務由 `PersistenceService` 執行，採取嚴格的輕量化 JSON 快照機制 [11]：
*   **存檔內容**：world_seed、generation_versions、world_time_seconds、party 狀態，以及 sparse RegionDelta 變更字典 [11]。
*   **排除內容**：不序列化生成的地形快取 (Generated Caches)、Node 樹、TileMap、Camera 狀態或 UI 畫面 [11]。

##### 6.2 存檔安全拒絕碼 (Save Validation Safety) [11]
當遊戲處於不穩定運行狀態時，`PersistenceService.save_session()` 會直接安全拒絕並回傳錯誤碼 [11]：
*  `TRAVEL_IN_PROGRESS` (旅途中禁止存檔) [11]
*  `SITE_ACTIVE` (局部 Site 場景中暫停存檔) [11]
*  `BATTLE_ACTIVE` (戰鬥中暫停存檔) [11]

--------------------------------------------------------------------------------

#### 七、 導覽控制器與視圖層 (Navigation Controller & Views) [12]
`NavigationController` 負責視圖間的切換與生命週期調度 [12]：
*   **無狀態視圖 (Stateless Views)**：WorldMap, RegionMap, SiteMap, BattleSiteMap 均只接受分離快照 (Detached Snapshots) 與發送輸入意圖 (Emit Signals) [12]。
*   **偵錯介面 (DebugUI)**：顯示當前全域時間、座標資訊、隊伍狀態、旅程預覽與戰場命令佇列狀態 [12]。

--------------------------------------------------------------------------------

#### 八、 測試與品質驗證體系 (Test Suite & Verification) [12]
專案內建完整的單元與整合測試套件 (位於 scripts/tests/) [12]，包含 **15 個專門測試檔案**、**超過 200 項單元與邊界斷言** [12]：
*   所有基礎座標轉換、地形、POI 與道路生成測試皆維持 **100% 通過（PASS）狀態** [13]。
*   `battle_site_test.gd`：整合了「九區戰場合成」、「Formation 軌跡與壓縮移動」、「傳令兵攔截」與「9000人 GPU MultiMesh 著色器」之聯合斷言測試（20/20 PASS） [13]。
