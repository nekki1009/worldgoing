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

建立 `assets/map/poi/`，每個圖示 96×96 PNG，透明背景、中心對齊：

- `village.png`
- `town.png`
- `castle.png`
- `ruins.png`
- `cave.png`

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
