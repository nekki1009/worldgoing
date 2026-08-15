# Site 高低差、樓梯與精細場景實作計畫

**審核日期**：2026-08-12  
**狀態**：規劃完成，尚未實作  
**適用範圍**：Site 詳細場景；不改 World／Region 座標契約

## 一、審核結論

目前 Site 的基礎契約是正確的：`50×50` 局部格、每格 `2m×2m`、總範圍 `100m×100m`，且每個 Region Strategic Cell 都能懶生成 Site。現有程式也已保留正確的資料邊界：`SiteLayoutData`／`SiteLayoutGenerator` 產生 detached base，`TravelRuntime` 擁有移動驗證，`SiteMap` 只負責顯示與輸入。

但目前仍是「平面 Site」：

| 審核項目 | 目前狀態 | 影響 |
|---|---|---|
| 局部高度 | 只有 Site 的單一 `source_elevation` | 無法表現台地、城牆與室內高台 |
| 轉接資料 | 沒有樓梯／斜坡／橋的高度連接 | 尋路只判斷目標格 `NAV_BLOCKED` |
| 渲染層 | `SiteMap` 主要是平面底材加覆蓋物 | 沒有峭壁面、牆面、平台陰影與高度排序 |
| 近景密度 | 目前 256px 底材是 100m Site 的低成本 composite | 適合預覽／縮圖，不應當作參考圖等級的最終近景密度 |
| POI | 目前只畫 2m hub anchor | 城堡、殿堂、碼頭仍需多 tile 組合 |
| 測試 | 現有 Site 測試只覆蓋隘口 blocked slice 與平面比例 | 尚無高度、樓梯、橋樑及跨高度尋路驗證 |

因此本計畫採用「保留現有資料與 Runtime owner，增加局部高度與轉接」的最小垂直切片，不改成 3D 世界、不建立第二套座標系，也不把每格變成 Scene Node。

## 二、修正後的目標規格

### 2.1 邏輯與美術比例

- Site 仍固定 `50×50`、每格 `2m×2m`，一格最多容納一名人物的比例基準不變。
- `256px` 保留為 V1 的 Site base／Region thumbnail 低成本來源；近景 Detail Layer 另設可調的 `SITE_DETAIL_TILE_PIXELS`，初版以 `16px／2m tile` 驗證，必要時升到 `32px`。
- Site 近景使用像素清晰的 nearest-neighbor；World／Region 可繼續使用目前的手繪底材與縮圖規則。這是對照參考圖後的美術方向修正。
- Detail Layer 是 Presentation cache，不能寫入 `WorldData`、`RegionRuntimeState`、`SiteRuntimeState` 或存檔。

### 2.2 局部高度資料

在 `SiteLayoutData` 增加固定 2,500 格的可重建資料：

- `elevation_levels: PackedInt32Array`：每格一個整數高度；初版 `1 level = 1m`。
- `surface_flags: PackedByteArray`：平台、水面、道路、樓梯、斜坡、橋等表面語意。
- `height_edge_flags: PackedByteArray`：由相鄰格高度差推導的峭壁／牆面方向；不是另一套尋路圖。
- `transitions: Array[SiteTransitionData]`：只保存實際的 `STAIR`、`RAMP`、`BRIDGE` 連接。

`source_elevation` 仍代表 Region 的宏觀高程，不直接當作每格高度。沒有重疊樓層的第一版，每個局部格只有一個高度；未來若真的需要同 XY 多層，再另訂 Layer 契約。

### 2.3 高度與通行規則

- 相同高度：依原本 blocked／river／crossing 規則通行。
- 不同高度：必須有 `RAMP` 或 `STAIR` 轉接，不能因為相鄰就自動爬上去。
- 沒有轉接的高度邊界：產生峭壁／牆面並阻擋。
- 水面不視為可走的負高度；河流／海岸由 `BRIDGE`、碼頭或登岸階梯連接。
- 第一版保留既有 `BLOCKED` typed failure；除非測試需要，不先擴張一批新的 Runtime failure code。

## 三、確定性生成規則

### 3.1 一般 Strategic Cell

- 平原、森林、沙地、雪地、沼澤：以 0 層為主，只生成少量 1 層自然台階。
- 山地：生成 0／1／2 層階梯地形；高差達到峭壁門檻時產生 `height_edge_flags`。
- 河流：河床與水面低於兩側河岸；道路 crossing 生成橋面高度。
- 海洋：水面不可行走，岸線保持 0 層，碼頭或登岸階梯作為唯一連接。
- 道路、河流、既有 `travel_exit_mask` 優先保持連續，不讓裝飾性高度切斷戰略出口。

### 3.2 `MOUNTAIN_PASS`

- 保留現有 `travel_exit_mask` 與通道中心線規則。
- 通道設為可走的 0／1 層，兩側山壁設為較高層或 `NAV_BLOCKED`。
- 若道路需要跨越高度，沿道路放置連續樓梯／斜坡；不能只畫 cliff 貼圖。

### 3.3 POI 模板

初版只做三種可驗證模板：

1. **Castle Courtyard**：0 層庭院、+2m 城牆／高台、城門與一段樓梯。
2. **Hall／Dais**：0 層主廳、+1 或 +2 層講台、側階與柱列。
3. **River Dock**：岸邊 0 層、低水面、木橋／碼頭與上下岸階梯。

模板使用穩定 Site Seed 與固定 generation salt 產生；大型結構仍是多個 2m tile 的 footprint，不恢復單一大型 POI 圖示。

## 四、資料、尋路與渲染接點

### 4.1 資料與生成器

- `scripts/data/site_layout_data.gd`：加入高度陣列、表面旗標、峭壁邊緣與轉接資料的最小型別。
- `scripts/core/site_layout_generator.gd`：先生成高度，再由高度推導邊緣、表面與 navigation flags。
- `SiteLayoutData.is_valid()`、`copy()` 與 Site snapshot 必須一併驗證／複製新增陣列，避免近景 renderer 改到下一次重建的資料。
- `SiteLayoutGenerator.GENERATION_VERSION` 在此切片實作時升到下一版；`SiteData.BASE_GENERATION_VERSION` 只有在外部 Base 欄位改變時才升版。
- `generate_cell_base_thumbnail()` 保持現有 8×8 `visual_cells` 契約，不展開完整 Site；若日後要在 Region 顯示高度，再另加可選的 8×8 height band，不把高度 bit 偷塞進既有 terrain／road／river flags。

### 4.2 Runtime 尋路

- `TravelRuntime.move_party_in_site()` 改由 `SiteLayoutData` 的相鄰格轉接查詢驗證移動。
- 仍使用現有 `Vector2i` 局部座標；高度是格子的屬性，不新增 `Vector3i` 或第二套 Site 座標。
- 先完成 cardinal 一格移動與樓梯／橋通過，再把相同規則提供給 Site A*；不可讓展示層自行判定可否爬坡。
- Party 不在 Site 時仍可 detached 檢視；不新增 Party、Formation 或 Occupancy 系統。

### 4.3 `SiteMap` 渲染

保留目前 `Node2D` 與 detached snapshot 邊界，繪製順序改為：

1. 地表／水面；
2. 平台與高台地板；
3. 峭壁／牆面／高度陰影；
4. 樓梯、斜坡、橋、碼頭；
5. POI 建築、門、柱、地毯；
6. 角色、Party marker 與互動覆蓋。

單位排序以 `screen_y + elevation_level × height_pixels_per_level` 計算。所有物件仍用批次繪製或圖片 cache，不為每格建立 Node，也不讓 renderer 產生 collision。

## 五、分階段實作

### P0 — 契約與測試骨架

修改 `SiteLayoutData` 的資料型別、generation version 常數與 debug state；建立高度／轉接測試資料。先不接正式美術。

### P1 — 確定性高度生成

修改 `SiteLayoutGenerator`，完成平地、山地、河岸與 `MOUNTAIN_PASS` 的高度場、峭壁邊界與至少一段樓梯。驗證同一 Seed 重建完全一致。

### P2 — 色塊渲染垂直切片

修改 `SiteMap` 及 `MapArtCatalog`，用色塊完成 0／+2／+4m 三層、峭壁面、樓梯與橋。先產出一張可驗證截圖，不等待正式素材。

### P3 — Runtime 移動與 Site A*

修改 `TravelRuntime` 與 Site 測試：平地可走、峭壁不可走、樓梯可走、橋可跨水；再將同一轉接規則接入局部 A*。

### P4 — 多 tile POI 模板

先完成 Castle Courtyard、Hall／Dais、River Dock，包含建築邊界、門口、樓梯與出口接線；大型 POI 仍維持 lazy。

### P5 — 正式素材與近景品質

製作地板、牆面、峭壁四方向、樓梯四方向、平台、橋、碼頭、門與陰影素材，替換色塊並驗證接縫、nearest filter、zoom 與 FPS。

## 六、驗收條件

1. 一張 Site 同時看得到至少 0／+2／+4m 三個高度層、峭壁面與樓梯。
2. 角色站在不同高度時沒有 z-fighting，陰影與腳底位置一致。
3. A*／cardinal movement 不能穿越沒有轉接的峭壁；必須能找到並走過樓梯與橋。
4. Site 邊界的道路／河流／入口與父 Region 的出口方向保持一致。
5. 同一 Site Seed 的高度、轉接、縮圖與畫面結果可重建；不同 Seed 不污染其他 Site。
6. Generic Site 仍只在需要時生成；Region／World 不載入完整 2,500 格 Detail Layer。
7. 現有座標、Site entry、MOUNTAIN_PASS、Site zoom 與既有測試不回歸；正式畫面維持至少 30 FPS。

## 七、明確不做

- 不改成完整 3D 地形、物理坡度或高度碰撞體。
- 不建立第二套 Site 座標、第二個 Pathfinder 或新的全域 Manager。
- 不把每個通用 Site 都生成城堡或室內；建築只由 POI 模板觸發。
- 不在這一切片加入 NPC Occupancy、戰鬥 AI、Party lifecycle 或 Site persistence。
## Implementation status (2026-08-12)

The P0-P3 vertical slice is implemented against the existing World/Region/Site
owners. `SiteLayoutGenerator.GENERATION_VERSION` is 6. Every generated 50x50
layout now carries packed local elevation levels, surface flags, derived height
edges, and explicit stair/bridge transition records. Mountain terraces, mountain
pass cliffs, castle courtyards, ruins, caves, river water, and crossing bridges
are deterministic color-block placeholders; formal art and large POI composition
remain intentionally deferred to P4/P5.

`SiteLayoutData.can_traverse()` is the shared local height/water rule. Cardinal
Party movement and `TravelRuntime.query_site_path()` both call it, while
`SiteMap` only renders detached snapshots. The existing 256px base remains the
low-cost surface; SiteMap uses the 800px (16px per 2m tile) detail surface when
building the near-camera texture and draws height faces/transitions on top.

Completed verification:

- `scripts/tests/site_detailed_scene_test.gd`: 5/5 PASS (determinism, detached
  copy, castle walls/stairs, bridge/water, Runtime A*, detail surface).
- `scripts/tests/site_visual_scale_test.gd`: 8/8 PASS (the original 7 checks
  plus the 800px/height-array contract).
- `git diff --check`: PASS.

The Godot headless runtime emits the environment's existing root-certificate
warning but these focused scripts exit 0. A real viewport capture is still a
P5/non-headless verification item; the dummy headless renderer has no viewport
texture in this environment.

## Status correction

The implementation status above supersedes the original phase labels in this
planning document: P0 through P3 are complete in the current checkout, while
P4 multi-tile POI composition and P5 formal art polish remain future work.
