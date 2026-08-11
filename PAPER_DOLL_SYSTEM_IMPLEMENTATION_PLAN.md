# 紙娃娃系統與 ChatGPT 美術實作計畫

狀態：角色生成器 Gate 0／Milestone 1 已完成；Art Gate 1 與 Battle 前置 Gate 待執行

> 2026-08-11 優先順序修正：[`CHARACTER_CREATOR_IMPLEMENTATION_PLAN.md`](CHARACTER_CREATOR_IMPLEMENTATION_PLAN.md) 的 Gate 0／Milestone 1 已完成。下一步是 ChatGPT Art Gate 1；PC 外觀持久化、Battle variant cache 與 GPU 接線仍不得提前。若兩份文件衝突，以角色生成器計畫與 `PROJECT_ARCHITECTURE.md` 為準。

本文件定義 Worldgoing 紙娃娃顯示、美術產製、離線合成與 Battle GPU 接線的落地順序。`PROJECT_ARCHITECTURE.md` 仍是最高架構真實來源；本文件不建立新的 gameplay 權威，也不代表 Unit、Equipment、Demography、Battle variant cache 或 Battle shader 已經完成。

目前已新增 synthetic 素材實驗室、Recipe、Composer、純 Image contact sheet、UI 場景與聚焦測試；尚未新增正式美術、PC gameplay owner、存檔欄位或 Battle 接線。

## 1. 計畫結論

紙娃娃系統分成兩條先獨立驗收、之後才匯合的工作流：

1. **工程工作流**：presentation 視覺定義、已解析 Recipe、固定節點 Composer、純 Image 離線合成、Texture2DArray 與既有 Battle MultiMesh 接線。
2. **ChatGPT 美術工作流**：風格與對齊模板、分層部件、坐騎部件、透明背景清理、尺寸正規化與遊戲內視覺驗收。

第一個實作切片只完成資料定義、Recipe、Composer 與合成測試材質。正式美術不阻塞這個切片；ChatGPT 美術必須等畫布、Anchor、方向與影格契約鎖定後才開始批量生成。

Battle 仍只使用既有單一 GPU `MultiMesh`。`PaperDollComposer` 不得出現在 9,000 人 Battle 的士兵節點樹中。

## 2. 不可變更的架構邊界

1. `GameSession.active_battle_state` 與 Formation data 仍是 Battle runtime 權威。
2. `BattleSiteMap` 只消費 detached snapshot、呈現 GPU instances 並發出輸入意圖。
3. Formation 仍是唯一的移動、命令與模擬單位；不得新增 Soldier、AI、NavigationAgent、物理 body 或每人一個 Node。
4. 紙娃娃 Resource 只描述可重用的視覺定義，不保存角色生命、裝備耐久、坐騎所有權或 Battle 狀態。
5. `PaperDollRecipe` 是交給顯示層的已解析快照，不是可變的角色資料容器。
6. `PaperDollComposer` 只用於 UI 單人預覽；離線 contact sheet／未來 variant sheet 使用純 Image 合成。
7. Texture2DArray、烘焙結果與 UI preview 都是可重建的 Presentation cache，不得進入 Seed + Delta 存檔。
8. ChatGPT 產生的是視覺素材；裝備規則、性別規則、坐騎狀態、Formation 分配與 shader instance data 仍由程式契約決定。

## 3. 統一圖像與 Anchor 契約

### 3.1 部件來源 Sheet

所有角色與坐騎部件來源統一為：

- PNG、RGBA8、透明背景。
- 每個 frame 為 `64×64`。
- 每列 8 個橫向 frame。
- 共 3 列：`DOWN = 0`、`UP = 1`、`RIGHT = 2`。
- 完整來源尺寸為 `512×192`。
- LEFT 不另畫來源列；Composer 使用 RIGHT 列逐部件 `flip_h = true`，並套用 LEFT 專屬 Z-order。

`frame_x` 的動作語意不由 Composer 推測。第一批美術開始前，必須先核准共用的步行與騎乘姿勢參考 Sheet；所有身體、頭髮、裝備與坐騎部件都必須對應同一組 8 個姿勢。動畫速度與 frame 時序由未來的呼叫端決定。

### 3.2 最終烘焙 Sheet

每個完整角色 variant 烘焙為：

- 每個 frame `64×64`。
- `8×4` frames。
- 完整尺寸 `512×256`。
- 輸出列：`DOWN = 0`、`UP = 1`、`RIGHT = 2`、`LEFT = 3`。

LEFT 必須是逐部件鏡像、重新套用 LEFT Z-order 後的獨立烘焙列。完成圖的 runtime `flip_h` 無法同時改變武器與盾牌的前後遮擋，因此不能取代 LEFT 烘焙。

### 3.3 世界 Anchor

統一目標 Anchor 為每個 64×64 frame 中的 `(32, 56)`：

- `Sprite2D.centered = false`
- `Sprite2D.offset = Vector2(-32, -56)`
- Composer 的 Node2D `(0, 0)` 代表人腳或馬蹄的著地中心。

舊 32×32 步行內容若要放入 64×64 frame，內容左上角固定為：

```text
(32, 56) - (16, 32) = (16, 24)
```

不得使用一般置中 `(16, 16)`，否則上下馬會產生 8 px 的垂直跳動。

64 px 是紋理畫布尺寸，不直接等於 Battle 世界公尺尺寸。`SOLDIER_CANVAS_SIZE_METERS` 與坐騎 Formation footprint 必須在 Battle 接線 Gate 另行核准，不能由像素尺寸反推。

## 4. 渲染層與 Z-order 契約

裝備槽與渲染層是不同概念。Recipe builder 負責明確映射：

| 裝備／來源 | 渲染層 |
| --- | --- |
| PaperDollMountVisual.tail | `MOUNT_TAIL` |
| CAPE | `CAPE` |
| PaperDollMountVisual.body | `MOUNT_BODY` |
| base body | `BODY` |
| BODY 裝備 | `ARMOR` |
| hair visual | `HAIR` |
| HEAD 裝備 | `HELMET` |
| WEAPON | `WEAPON` |
| SHIELD | `SHIELD` |
| PaperDollMountVisual.head | `MOUNT_HEAD` |
| MOUNT_BARDING | `MOUNT_BARDING` |

Composer 必須固定重用以上 11 個 `Sprite2D`，並遵守下表：

| Render layer | DOWN | UP | RIGHT | LEFT |
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

## 5. Presentation 視覺資料（Milestone 1 已完成）

已新增：

```text
scripts/data/paper_doll_layer_visual.gd
scripts/data/paper_doll_mount_visual.gd
scripts/data/paper_doll_catalog.gd
scripts/data/paper_doll_preview_draft.gd
scripts/data/paper_doll_recipe.gd
```

- `PaperDollLayerVisual extends Resource` 集中 Gender、Facing、11 個 RenderLayer、64×64／8×3／Anchor 常數，以及 GENDERED／UNISEX Texture 解析與尺寸驗證。
- `PaperDollMountVisual extends Resource` 只組合 tail／body／head 三個 presentation layer visual，不表示坐騎所有權或 gameplay 狀態。
- `PaperDollCatalog extends Resource` 負責穩定 ID 查找、預設 body／hair、重複 ID／texture matrix 驗證，以及從 Preview Draft 解析 Recipe。
- `PaperDollPreviewDraft extends RefCounted` 保存素材實驗室的可變選擇；它沒有 Session 或 Persistence 路徑。
- `PaperDollRecipe extends RefCounted` 只保存已解析的固定 11 層 Texture 與 mounted flag，交給 Composer／contact sheet 消費。

Gate 0 撤銷了先建立 gameplay `ItemData`／`MountData`／ArmorWeight 的舊方案。Heavy Armor → UNISEX 是未來 Equipment owner 的規則；目前素材層只驗證被標記為 UNISEX 的 visual 在男女選擇下解析到同一 Texture。這避免素材實驗室搶先成為裝備或坐騎權威。

## 6. PaperDollComposer（Milestone 1 已完成）

已新增：

```text
scripts/ui/paper_doll_composer.gd
```

`PaperDollComposer extends Node2D` 的責任：

1. `_ready()` 預先建立 11 個固定 `Sprite2D`。
2. `_ensure_layers()` 保持可重入，允許測試或 SubViewport 在 `_ready()` 前後安全套用 Recipe。
3. `apply_recipe(recipe)` 只更新 texture 與 visibility。
4. `update_frame(facing, frame_x)` 同步更新所有可見部件。
5. 來源 sprites 固定 `hframes = 8`、`vframes = 3`、`centered = false`、`offset = Vector2(-32, -56)`。
6. LEFT 使用來源 SIDE row 與逐部件 `flip_h = true`；切換其他方向時必須重設 `flip_h = false`。
7. 每次方向改變都重新套用完整 Z-order 表。
8. 非 mounted Recipe 隱藏所有坐騎部件與馬鎧。

Composer 明確不負責：

- `_process()` 動畫時間。
- gameplay 裝備規則。
- Resource 路徑載入。
- Texture2DArray 建立。
- Unit／Formation 狀態。
- Battle instance 分配。

「無狀態」在此代表不保存權威遊戲狀態；Composer 可以保存固定 Sprite 參考與目前顯示用的 transient frame。

## 7. ChatGPT 美術工作流

### 7.1 ChatGPT 的責任

ChatGPT 負責：

1. 產生原創風格確認板，不模仿指定在世藝術家或既有遊戲 IP。
2. 依核准模板製作 base body、hair、equipment、mount 與 barding 部件。
3. 使用同一 reference image／對齊模板反覆編修，而不是每張從零生成。
4. 清除背景、文字、Logo、水印、陰影底板與非目標部件。
5. 將結果正規化為規定的透明 PNG、frame 尺寸、方向列與 Anchor。
6. 產生供人工審核的四方向 contact sheet 與遊戲內預覽截圖。
7. 對未通過尺寸、對齊、遮擋或風格一致性的素材重新生成或局部修正。

ChatGPT 不負責決定：

- ItemData 的 gameplay 數值。
- 哪個 Unit 穿戴哪件物品。
- 男女／Unisex 規則。
- 坐騎所有權與騎乘狀態。
- Battle variant 分配與 Formation footprint。
- Runtime cache、shader 或持久化權責。

### 7.2 美術目錄與命名

預計建立：

```text
assets/paper_doll/concepts/
assets/paper_doll/parts/body/
assets/paper_doll/parts/hair/
assets/paper_doll/parts/items/
assets/paper_doll/parts/mounts/
```

`concepts/` 只保存風格板、姿勢／Anchor 模板與 contact sheet，不作為 runtime texture。

Runtime 部件命名：

```text
{visual_id}_{pose}_{gender}.png
{mount_id}_{part}.png
```

其中：

- `pose`：`on_foot`／`mounted`
- `gender`：`male`／`female`／`unisex`
- `part`：`tail`／`body`／`head`

命名只使用小寫 ASCII、數字與底線。產生的 Texture2DArray 第一版只存在記憶體，不提交 `generated/` 快取；若未來量測證明啟動烘焙過慢，再規劃版本化磁碟快取。

### 7.3 第一批最小美術包

第一批只製作足以驗證全部渲染層與性別規則的素材：

- 男、女 base body：步行與騎乘。
- 一組 hair：步行與騎乘。
- 一件男女版本的 LIGHT armor。
- 一件 Unisex HEAVY armor。
- 一頂 helmet。
- 一件 cape。
- 一把 weapon。
- 一面 shield。
- 一匹 mount：tail、body、head。
- 一件 mount barding。

這批通過 Composer、Catalog、contact sheet 與 runtime preview Gate 後，才批量增加更多裝備、髮型、坐騎或染色變體。

### 7.4 每張部件的美術驗收

1. 尺寸正好為 `512×192`，RGBA8 透明 PNG。
2. 每個 64×64 frame 的非透明像素不得溢出相鄰 frame。
3. 人腳或馬蹄對齊 `(32, 56)`；相同方向與 frame 的所有部件誤差不得超過 1 px。
4. 三列方向、八個姿勢與核准模板一致，不能改變攝影機角度或角色比例。
5. 部件只包含自身內容；armor 不重畫頭髮，weapon 不附帶手臂，mount head 不包含 body。
6. 不包含背景、文字、Logo、水印、整體地面陰影或 UI。
7. LEFT 逐部件鏡像後，武器、盾牌、披風與馬頭遮擋正確。
8. Nearest filtering 下沒有半透明髒邊、背景殘色或 frame 間滲色。
9. 步行與騎乘切換時，世界 Anchor 不跳動。
10. 通過程式尺寸檢查、Composer contact sheet 與人工視覺審核後才可登記為 runtime asset。

## 8. 聚焦測試（Milestone 1 已完成）

已新增 `scripts/tests/character_creator_test.gd`，使用程式產生的 asymmetric RGBA8 `ImageTexture`，不依賴正式美術。7 個案例涵蓋：

1. Catalog ID、GENDERED／UNISEX、512×192 texture matrix、預設 body／hair 與 Mount 三部件驗證。
2. Preview Draft 深拷貝、步行／騎乘 Recipe、mount-only visibility 與缺 Mount 失敗。
3. 固定 11 Sprite 節點池、重複套用零增生、8×3、Anchor、nearest filter、四方向 frame／flip reset 與完整 z-order。
4. 純 Image 4×8 contact sheet，以及 LEFT 確實由 RIGHT source frame 鏡像。
5. 素材實驗室單一 Timer、播放、方向、mounted 切換、全 Catalog 檢查與 34 張 contact sheet 匯出。
6. DebugUI lazy entry、同一 CharacterCreator 重用與 NavigationController 輸入狀態恢復。
7. 靜態依賴掃描：素材實驗室沒有 GameSession、Persistence、AnimatedSprite2D、Battle、ItemData 或 gameplay MountData。

正式美術加入後，在同一測試入口增加資產契約掃描；視覺品質仍由 contact sheet／runtime capture 人工核准，不用脆弱的全圖 hash 取代美術審核。

每個 Gate 都必須重跑既有 `scripts/tests/battle_site_test.gd`，確認 9,000 instances、無 Soldier Node、Formation geometry 與 Presentation dependency 邊界沒有退化。

## 9. 未來 Battle variant cache

Milestone 1 已用 `PaperDollContactSheet` 證明純 Image 合成路徑：逐 texture `get_region()`、LEFT component `flip_x()`、按方向 z-order `blend_rect()`，直接得到 `512×256` 四方向完成圖。未來 Art Gate 與 Unit snapshot 通過後，優先延伸同一路徑建立排序後的 variant sheets／Texture2DArray；不另建 SubViewport Bakery、常駐 Singleton、背景 worker 或磁碟 cache。

未來最小流程：

1. Unit snapshot 提供已核准且數量受限的 deterministic variant keys。
2. 依 key 解析 Recipe，使用既有 Image 合成器產生 `512×256` sheet。
3. 驗證所有 sheet 尺寸、format 與 mipmap 契約後，才一次發布 Texture2DArray 與唯讀 key→layer mapping。
4. 先量測 variant 數量、峰值記憶體與產製時間，再決定是否需要磁碟 cache 或非同步處理。

只有未來加入無法由 CPU Image 重現的 per-part shader 效果，且實測證明必要時，才另行審核 SubViewport capture；目前沒有此需求。

## 10. Battle GPU 接線 Gate

接入 Battle 前必須先有兩項正式決策：

1. **Unit 視覺快照 owner**：未來 Unit／Equipment／Demography 必須提供 compact、detached 的視覺 variant 資料；不得讓 `BattleSiteMap` 直接查詢角色 Resource，也不得為 9,000 人建立 9,000 份 CharacterProfile。
2. **世界尺寸契約**：分別核准步兵與坐騎的 visual quad 公尺尺寸，以及它們是否改變 Formation footprint／spacing。這項決策不能從 64 px 畫布自動推導。

通過後只延伸既有 `BattleSiteMap` MultiMesh：

- 在設定 instance count 前啟用 custom data。
- 使用一個 ShaderMaterial 取樣 PaperDoll Texture2DArray。
- 每個 instance 只保存最小資料，例如 `variant_layer`、`frame_x`、`facing_row`、保留 flags。
- LEFT 使用烘焙後第 4 列；不依賴完成圖 runtime flip 修正遮擋。
- captain／hero 可有獨立 variant；一般部下使用 Formation snapshot 提供的少量 subordinate template keys 與 deterministic 分配。
- Battle 場景中不得實例化 PaperDollComposer、Sprite2D 士兵或個人動畫 Node。

Battle 驗收必須包含：

1. 實際 personnel count 等於 MultiMesh visible instance count。
2. 9,000 人仍無 Soldier Node，Scene node count 不因人數線性增加。
3. 四方向、八 frame、variant layer 與 mounted／on-foot 顯示正確。
4. Scene replacement 後資料與畫面可重建。
5. Battle runtime 仍不依賴 Presentation classes。
6. 在明確記錄的參考硬體與 rendering method 上執行 GPU／FPS benchmark；未實測前不得宣稱達成 60 FPS。

## 11. 分階段執行與核准 Gate

### Gate 0：契約同步

狀態：**完成（2026-08-11）**

交付：

- 在 `PROJECT_ARCHITECTURE.md` 增補 Composer／Image 合成／Battle 邊界。
- 在 `ARCHITECTURE_STATUS.md` 分開記錄已完成的 synthetic asset lab 與仍未完成的 PC／正式美術／Battle 部分。
- 修正 `PROJECT_SPECIFICATION_V3.md` 中以 runtime `flip_h` 表示 LEFT 的模糊描述，改為 source-side component flip 與 baked LEFT row。

通過證據：來源 512×192、輸出 512×256、Anchor、方向、Z-order、presentation visual owner、未來 PC owner／存檔欄位、LEFT component flip、純 Image 合成與非目標範圍已同步至三份架構／規格文件。

### Milestone 1：資料、Recipe、Composer

狀態：**完成（2026-08-11）**

交付：第 5、6、8 節所列腳本與聚焦測試，使用合成測試材質。

通過證據：`character_creator_test.gd` 7/7、Godot 4.6.2 class scan、Main startup、Architecture smoke、專案預設 D3D12 Forward+ 實際 UI capture 與既有 Battle boundary 20/20 PASS；`git diff --check` PASS。

### Art Gate 1：ChatGPT 對齊模板與第一批素材

交付：風格板、步行／騎乘姿勢模板、第一批最小美術包、contact sheet 與 runtime preview capture。

通過條件：第 7.4 節全部符合；未通過的部件只重做該部件，不擴大量產。

### Gate 2：Unit snapshot 與世界尺寸

交付：Unit 視覺 snapshot owner、variant template 分配、步兵／坐騎公尺尺寸與 Formation footprint 決策。

通過條件：不建立第二套角色權威、不以 Scene 查詢 Unit、不改變既有 Formation 命令 owner，且架構文件同步。

### Milestone 2：Battle variant cache

交付：延伸既有純 Image 合成器，產生 `512×256` variants、Texture2DArray 與 deterministic layer mapping。

通過條件：variant cache 測試 PASS、第一批正式美術四方向合成正確、相同輸入 mapping 穩定，且不發布半完成 cache。

### Milestone 3：Battle MultiMesh shader

交付：既有單一 MultiMesh 的 Texture2DArray shader 與 custom data 接線。

通過條件：9,000 人容量、無 Soldier Node、方向／frame／variant 正確、Scene replacement、架構掃描與實際 GPU benchmark 全數完成。

### Milestone 4：PC／裝備 UI 整合

交付：在素材實驗室以外的真正 PC／裝備 UI 中重用一個 PaperDollComposer。

通過條件：UI 只發出裝備意圖並顯示 Recipe，不直接修改 gameplay Resource；關閉與重開 UI 後可從權威資料重建。

## 12. 明確不在第一輪範圍

- Unit 數值、角色成長、裝備耐久與 gameplay 效果。
- 坐騎馴服、所有權、生命、速度或持久化。
- 完整 Battle damage、AI、士氣與 combat resolution。
- 9000 個 CharacterProfile／PaperDollComposer／Sprite2D。
- 自訂 Command Bus、CQRS、event bus 或第二套 renderer framework。
- 無量測依據的磁碟 cache、thread pool、增量 variant cache 或素材串流。
- 批量生成所有裝備、髮型與坐騎；第一批只驗證完整管線。
- 將 AI 生成圖直接視為可用資產而跳過尺寸、透明、對齊與遊戲內驗收。

## 13. 完成定義

只有同時滿足以下條件，才能把 PaperDoll 從 `ARCHITECTURE_STATUS.md` 的未實作項目移除：

1. 正式資料 owner 與 Recipe snapshot 已落地。
2. Composer、ChatGPT 第一批美術與純 Image variant cache 均通過各自驗收。
3. Battle 使用既有單一 MultiMesh 顯示紙娃娃 variant，沒有個人士兵 Node。
4. 9,000 人回歸與 GPU benchmark 有實際證據。
5. UI／Battle Scene 銷毀重建不改變權威資料。
6. 架構、狀態文件與實際程式一致，未完成項目仍明確標記為未實作。

Gate 0／Milestone 1 已完成。推薦下一次只執行 Art Gate 1；PC 外觀持久化、Unit snapshot、世界尺寸、Battle variant cache 與 shader 必須等各自前置 Gate 通過後再開始。
