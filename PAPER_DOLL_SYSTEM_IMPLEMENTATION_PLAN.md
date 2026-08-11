# 紙娃娃系統與 ChatGPT 美術實作計畫

狀態：角色生成器前置 Gate 完成前暫緩實作

> 2026-08-11 優先順序修正：先執行 [`CHARACTER_CREATOR_IMPLEMENTATION_PLAN.md`](CHARACTER_CREATOR_IMPLEMENTATION_PLAN.md)，完成 PC 固有外觀、素材實驗室、動畫／素材驗收與存檔契約後，才回到本文件的離線合成與 Battle GPU 接線。若兩份文件在前置資料型別、Composer、素材驗收或里程碑順序上衝突，以角色生成器計畫為準；Battle 仍維持既有 MultiMesh，這次不接紙娃娃。

本文件定義 Worldgoing 紙娃娃顯示、美術產製、離線烘焙與 Battle GPU 接線的落地順序。`PROJECT_ARCHITECTURE.md` 仍是最高架構真實來源；本文件不建立新的 gameplay 權威，也不代表 PaperDoll、Unit、Equipment、Demography、Bakery 或 Battle shader 已經完成。

本輪只新增計畫文件，不修改遊戲程式、美術資產、場景、測試或架構狀態。

## 1. 計畫結論

紙娃娃系統分成兩條先獨立驗收、之後才匯合的工作流：

1. **工程工作流**：資料定義、已解析 Recipe、固定節點 Composer、SubViewport Bakery、Texture2DArray 與既有 Battle MultiMesh 接線。
2. **ChatGPT 美術工作流**：風格與對齊模板、分層部件、坐騎部件、透明背景清理、尺寸正規化與遊戲內視覺驗收。

第一個實作切片只完成資料定義、Recipe、Composer 與合成測試材質。正式美術不阻塞這個切片；ChatGPT 美術必須等畫布、Anchor、方向與影格契約鎖定後才開始批量生成。

Battle 仍只使用既有單一 GPU `MultiMesh`。`PaperDollComposer` 不得出現在 9,000 人 Battle 的士兵節點樹中。

## 2. 不可變更的架構邊界

1. `GameSession.active_battle_state` 與 Formation data 仍是 Battle runtime 權威。
2. `BattleSiteMap` 只消費 detached snapshot、呈現 GPU instances 並發出輸入意圖。
3. Formation 仍是唯一的移動、命令與模擬單位；不得新增 Soldier、AI、NavigationAgent、物理 body 或每人一個 Node。
4. 紙娃娃 Resource 只描述可重用的視覺定義，不保存角色生命、裝備耐久、坐騎所有權或 Battle 狀態。
5. `PaperDollRecipe` 是交給顯示層的已解析快照，不是可變的角色資料容器。
6. `PaperDollComposer` 只用於 UI 單人預覽、SubViewport 烘焙與聚焦渲染測試。
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
| MountData.tail | `MOUNT_TAIL` |
| CAPE | `CAPE` |
| MountData.body | `MOUNT_BODY` |
| base body | `BODY` |
| BODY 裝備 | `ARMOR` |
| hair visual | `HAIR` |
| HEAD 裝備 | `HELMET` |
| WEAPON | `WEAPON` |
| SHIELD | `SHIELD` |
| MountData.head | `MOUNT_HEAD` |
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

## 5. 資料層計畫

預計新增：

```text
scripts/data/paper_doll_sprite_set.gd
scripts/data/item_data.gd
scripts/data/mount_data.gd
scripts/data/paper_doll_recipe.gd
```

### 5.1 PaperDollSpriteSet

`PaperDollSpriteSet extends Resource` 是共用視覺定義，也是原需求中缺少的第三個 Resource 類別。

最小欄位：

- `visual_id: StringName`
- `on_foot_male: Texture2D`
- `on_foot_female: Texture2D`
- `on_foot_unisex: Texture2D`
- `mounted_male: Texture2D`
- `mounted_female: Texture2D`
- `mounted_unisex: Texture2D`

提供 `resolve(gender, is_mounted, force_unisex)`，只回傳已匯入的 `Texture2D`，不得在 Composer 中以字串執行 `load()`。

Godot `Resource` 並非語言層級不可變。這些檔案採「編輯器可編輯、runtime 不修改」契約；驗證器檢查缺圖、尺寸與不合法的 fallback。

### 5.2 ItemData

`ItemData extends Resource` 的最小欄位：

- `item_id: StringName`
- `slot_type: Slot`
- `armor_weight: ArmorWeight`
- `visuals: PaperDollSpriteSet`

第一版 Slot：

```text
HEAD, BODY, WEAPON, SHIELD, CAPE, MOUNT_BARDING
```

第一版 ArmorWeight：

```text
NOT_ARMOR, LIGHT, MEDIUM, HEAVY
```

規則：

- 只有 HEAD／BODY 可使用 LIGHT、MEDIUM、HEAVY。
- HEAVY 強制解析 Unisex texture。
- 非 Heavy 先解析對應性別；是否允許 Unisex fallback 必須由建構驗證明確處理，不能靜默選錯圖。

### 5.3 MountData

`MountData extends Resource` 的最小欄位：

- `mount_id: StringName`
- `tail_sheet: Texture2D`
- `body_sheet: Texture2D`
- `head_sheet: Texture2D`

三個部件必須分開，才能實作既定 Z-order。馬鎧由 `MOUNT_BARDING` 裝備槽提供，不放進 MountData。

### 5.4 PaperDollRecipe

`PaperDollRecipe extends RefCounted` 是已解析、API-level read-only 的顯示快照。

內容：

- `gender`
- `is_mounted`
- 穩定、可重建的 `variant_key`
- 私有 `RenderLayer -> Texture2D` 映射

Recipe builder 接收 base body、可選 hair、equipment 定義、可選 MountData 與目前是否騎乘，完成：

1. 裝備槽驗證。
2. Heavy／Unisex 規則。
3. 裝備槽到渲染層映射。
4. 步行／騎乘 texture 解析。
5. mounted 但缺少 MountData 的錯誤回報。
6. 來源 Sheet 尺寸驗證。
7. 依固定層順序產生 deterministic `variant_key`。

Recipe 不公開內部 Dictionary，也不讓 Composer 讀取 ItemData。建構失敗使用同檔案內的小型 `BuildResult` 回傳錯誤；第一版不新增全域 Result framework 或 Recipe factory service。

## 6. PaperDollComposer 計畫

預計新增：

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

這批通過 Composer 與 Bakery Gate 後，才批量增加更多裝備、髮型、坐騎或染色變體。

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

## 8. 聚焦測試計畫

預計新增：

```text
scripts/tests/paper_doll_composer_test.gd
```

第一階段使用程式建立的純色 `ImageTexture`，不依賴正式美術：

1. Heavy armor 在男女 Recipe 中解析到同一張 Unisex texture。
2. Light／Medium 正確解析性別 texture；缺失 fallback 會回報錯誤。
3. slot 不符、來源尺寸錯誤、mounted 但缺少 MountData 時建構失敗。
4. Recipe 與輸入 equipment Dictionary 分離；外部修改不污染已建 Recipe。
5. Recipe 不公開可變的 layer Dictionary。
6. 重複 `apply_recipe()` 不增加節點，固定維持 11 個 Sprite2D。
7. 所有可見部件使用相同 frame coordinates、hframes、vframes、offset。
8. 四方向 row、LEFT flip 與離開 LEFT 後的 flip reset 正確。
9. 四方向完整 Z-order 表正確。
10. 步行 Recipe 隱藏 mount layers；騎乘 Recipe 依資料顯示 mount 與 barding。
11. 64×64 SubViewport 中的測試標記精確落在 `(32, 56)` Anchor。
12. Composer 銷毀並重建後，同一 Recipe 產生相同畫面資料。

正式美術加入後，在同一測試入口增加資產契約掃描；視覺品質仍由 contact sheet／runtime capture 人工核准，不用脆弱的全圖 hash 取代美術審核。

每個 Gate 都必須重跑既有 `scripts/tests/battle_site_test.gd`，確認 9,000 instances、無 Soldier Node、Formation geometry 與 Presentation dependency 邊界沒有退化。

## 9. PaperDollBakery 計畫

只有資料、Composer、測試與第一批 ChatGPT 美術通過後才新增：

```text
scripts/ui/paper_doll_bakery.gd
```

最小流程：

1. 重用一個透明背景、`64×64`、停用 3D 的 `SubViewport`。
2. Composer 放在 viewport 的 `(32, 56)`。
3. 依固定 variant key 順序，逐一套用 Recipe。
4. 對 DOWN、UP、RIGHT、LEFT 各烘焙 8 個 frame。
5. LEFT 先在 Composer 中逐部件 flip 並套用 LEFT Z-order。
6. 設定一次更新並等待 `RenderingServer.frame_post_draw` 後擷取畫面。
7. 將 32 張 frame 組成一張 `512×256` variant sheet。
8. 依排序後的 variant key 將所有同尺寸 sheet 建立為 `Texture2DArray`。
9. 回傳 Texture2DArray 與 `variant_key -> array_layer` 的唯讀結果。

第一版只做記憶體內烘焙；不建立常駐 Bakery Singleton、不寫 user save、不新增背景 worker framework。需要磁碟 cache、threading 或增量 dirty rebuild，必須先以實測烘焙時間與記憶體數據證明必要性。

Bakery 驗收：

- 每層正好 `512×256`。
- 所有 layers 尺寸與 mipmap 契約一致。
- 相同輸入與排序產生相同 variant key／layer mapping。
- LEFT 列是獨立合成，不是完成圖鏡像。
- SubViewport 失敗或空 texture 會回傳明確錯誤，不發布半完成陣列。
- Composer／SubViewport 可重用，批次中不持續增加 Node。

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

交付：

- 在 `PROJECT_ARCHITECTURE.md` 增補 Composer／Bakery／Battle 邊界。
- 在 `ARCHITECTURE_STATUS.md` 保持 PaperDoll 為未實作，直到相應 Gate 真正完成。
- 修正 `PROJECT_SPECIFICATION_V3.md` 中以 runtime `flip_h` 表示 LEFT 的模糊描述，改為 source-side component flip 與 baked LEFT row。

通過條件：來源 512×192、輸出 512×256、Anchor、方向、Z-order、資料 owner 與非目標範圍全部核准。

### Milestone 1：資料、Recipe、Composer

交付：第 5、6、8 節所列腳本與聚焦測試，使用合成測試材質。

通過條件：聚焦測試全數 PASS、Godot parse PASS、`git diff --check` PASS、既有 Battle boundary 20/20 不退化。

### Art Gate 1：ChatGPT 對齊模板與第一批素材

交付：風格板、步行／騎乘姿勢模板、第一批最小美術包、contact sheet 與 runtime preview capture。

通過條件：第 7.4 節全部符合；未通過的部件只重做該部件，不擴大量產。

### Milestone 2：Bakery

交付：可重用 SubViewport Bakery、`512×256` variants、Texture2DArray 與 deterministic layer mapping。

通過條件：Bakery 測試 PASS、第一批正式美術四方向合成正確、重複烘焙不增加 Node 或發布半完成 cache。

### Gate 2：Unit snapshot 與世界尺寸

交付：Unit 視覺 snapshot owner、variant template 分配、步兵／坐騎公尺尺寸與 Formation footprint 決策。

通過條件：不建立第二套角色權威、不以 Scene 查詢 Unit、不改變既有 Formation 命令 owner，且架構文件同步。

### Milestone 3：Battle MultiMesh shader

交付：既有單一 MultiMesh 的 Texture2DArray shader 與 custom data 接線。

通過條件：9,000 人容量、無 Soldier Node、方向／frame／variant 正確、Scene replacement、架構掃描與實際 GPU benchmark 全數完成。

### Milestone 4：UI 預覽

交付：在真正需要的角色／裝備 UI 中重用一個 PaperDollComposer。

通過條件：UI 只發出裝備意圖並顯示 Recipe，不直接修改 gameplay Resource；關閉與重開 UI 後可從權威資料重建。

## 12. 明確不在第一輪範圍

- Unit 數值、角色成長、裝備耐久與 gameplay 效果。
- 坐騎馴服、所有權、生命、速度或持久化。
- 完整 Battle damage、AI、士氣與 combat resolution。
- 9000 個 CharacterProfile／PaperDollComposer／Sprite2D。
- 自訂 Command Bus、CQRS、event bus 或第二套 renderer framework。
- 無量測依據的磁碟 cache、thread pool、增量 Bakery 或素材串流。
- 批量生成所有裝備、髮型與坐騎；第一批只驗證完整管線。
- 將 AI 生成圖直接視為可用資產而跳過尺寸、透明、對齊與遊戲內驗收。

## 13. 完成定義

只有同時滿足以下條件，才能把 PaperDoll 從 `ARCHITECTURE_STATUS.md` 的未實作項目移除：

1. 正式資料 owner 與 Recipe snapshot 已落地。
2. Composer、ChatGPT 第一批美術與 Bakery 均通過各自驗收。
3. Battle 使用既有單一 MultiMesh 顯示紙娃娃 variant，沒有個人士兵 Node。
4. 9,000 人回歸與 GPU benchmark 有實際證據。
5. UI／Battle Scene 銷毀重建不改變權威資料。
6. 架構、狀態文件與實際程式一致，未完成項目仍明確標記為未實作。

推薦下一次只核准 Gate 0、Milestone 1 與 Art Gate 1。Bakery、Unit snapshot、世界尺寸與 Battle shader 必須等前一 Gate 通過後再開始。
