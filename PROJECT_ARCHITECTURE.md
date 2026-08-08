# Worldgoing 專案架構與開發順序

## 目的

本專案採用「世界層 → Region 層 → Site 層」的三層架構：

- 世界層負責 Region 之間的關係、Party 所在位置與全局時間。
- Region 層負責 100×100 的戰略地形資料、探索移動與大型建設。
- Site 層負責村莊、洞穴、遺跡等小尺度地圖與細部玩法。

核心原則：資料模型先於顯示、程序生成可重現、世界不保存不必要的完整地圖。

## 一、三層架構與座標模型

### 1. World 層

World 層只處理跨 Region 的狀態與流程：

- `RegionCoord`: Region 在世界中的整數座標，例如 `(3, -2)`。
- Party 所在的 Region 與 Strategic Cell。
- 全局時間、跨 Region 移動與載入相鄰 Region。
- Region 的 Seed 與玩家造成的 Delta 索引。

World 層不直接持有 TileMap，也不負責繪製地形。

### 2. Region 層

每個 Region 是固定大小的戰略資料區：

- 大小：`100 × 100 Strategic Cell`。
- 每格代表：`100m × 100m`。
- Region 實際範圍：`10km × 10km`。
- `RegionCoord` 決定 Region 的世界位置。
- `RegionData.seed` 決定該 Region 的程序生成結果。
- Region 資料可被重新生成，不依賴 TileMap 是否存在。

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
- Site 有自己的局部座標與場景資料。
- Site 不取代 Region；Region 只保存 Site 的索引、入口與狀態。
- 從 Region 進入 Site 時，才載入 Site 的細部地圖與玩法。

Site 座標不可直接當成 Region 座標使用；兩者之間必須透過明確的入口錨點轉換。

## 二、資料與顯示的分離

資料層是唯一的真實來源，顯示層只是消費者：

```text
RegionCoord + seed
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
- Site 使用自己的局部資料與場景。
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

### 9. 戰鬥與更細的 Site Gameplay

最後加入戰鬥、互動與 Site 內的細部玩法。這些系統必須建立在前面已穩定的 Region、Site、Unit 與持久化契約上。

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
