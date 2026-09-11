# Worldgoing V0.35R — 現行 Site 架構

## 正式入口

唯一遊玩入口為 `scenes/terrain_lab/TerrainLab.tscn`，由 `project.godot` 指定。
這是目前新作的 Site：100×100 格地形、玩家／NPC、騎乘、武器碰撞與百人隊伍。
保留 TerrainLab 名稱，不為發版另造入口或重命名整套程式。

V0.3R 移除已停用的 2D 紙娃娃，以及舊 Main、World、Region、ContinuousWorldMap、
SiteMap、舊 Battle／Formation／Travel／Persistence 流程與專用素材、工具、測試。
本版本沒有 World／Region 旅行，也不將舊存檔遷移至新 Site。
2026-09-11 加入此單一 Site 的天然資源、土地使用、工作、時間與地圖存讀檔。

## 現行責任

| 擁有者 | 責任 |
| --- | --- |
| TerrainPreset／TerrainGenerator | 預設參數與相同 seed 的可重現生成 |
| TerrainData | 唯一地圖資料入口；地形、環境基底、site 稀疏狀態及共用通行／攻擊邊界查詢 |
| TerrainRenderer／TerrainRenderLayer | 消費地形資料並繪製地表、岩壁 |
| TerrainLab | 場景組裝、輸入、Camera2D 與控制介面 |
| SiteEnvironment | 獨立 seed 分流生成九類來源與土地條件；唯讀查詢、可重建阻擋索引 |
| SiteRuntime | 同一時鐘上的採集、清地、建設、批次生產、再生與供水分配；命令回傳 ok/code/message |
| SiteStore | 校驗並原子保存 seed／版本／稀疏差異；重建同一 TerrainData，不保存 Node 或整張生成基底 |
| SiteController | 資源／土地面板及指令轉接；沿用既有 NPC 尋路執行第一名工人，不擁有第二份地圖 |
| SiteResourceView | 每地圖列一個繪製批次，與角色依地面接點排序；不修改資源存量 |
| TerrainTestCharacter／TerrainTestNPC | 角色格位、移動、戰鬥與指令狀態 |
| TerrainWeaponCollision | 與實際投影一致的武器／身體碰撞 |
| TerrainArmy | 百人隊伍資料、路徑、佔格、隊形與共用士兵圖集 |
| CharacterVisualState／CharacterRenderContract | 外觀輸入與共享 3D→2D 投影規格 |
| HumanCharacter3DEditor／MountHorse3D | 男女模組化角色、換裝、染色、動畫與馬匹 |

地圖仍由 Node2D + Camera2D 控制。特寫角色使用透明 SubViewport 呈現既有 3D 模型，
再由 Sprite2D 顯示；刪除舊紙娃娃不代表改成 3D 世界。
百人隊伍的 3D 角色烘焙圖集不是被移除的紙娃娃系統，必須保留。
地形生成、通行資料與呈現維持分離，不另加平行座標或遊戲狀態擁有者。

`TerrainData.site` 是唯一資源／用地／存貨／工人狀態。`resource_base` 與環境陣列
由 seed 重建，`changes`、`features`、`terrain_changes` 保存修改；阻擋、來源索引與
供水服務範圍可重建。`TerrainRenderer` 仍保留四個原有地形子層。
NPC 的原 BFS 共用 `TerrainData.path_between`；角色與軍隊仍持有各自的實體格位及預約。
新增障礙先檢查移動來源、目的地及軍隊通道保護，再透過軍隊既有命令佇列排空並重算路線。

和平 1 現實秒＝1 遊戲分鐘；有效攻擊／受擊期間 1 現實秒＝1 遊戲秒，
攻擊時長加 10 秒脫戰緩衝。工作、生長與供水共用倍率，人物動作不改 `Engine.time_scale`。
離開應用程式或手動暫停時停止模擬，回來須按「繼續」；離線不補產量。
地圖保存不含換裝、軍隊與戰鬥快照；交戰中延後保存，並保留明確的失敗原因。

## 必須保留的資源

- `assets/characters/human/q35/standard_anime_{male,female}_character_pack.glb` 與正式來源。
- `assets/mounts/horse/standard_horse_pack.glb`。
- `assets/characters/terrain_lab_army/standard_soldier/` 的圖集與 metadata。
- `assets/map/terrain_lab/` 中現行草地、水、沙地三張貼圖。
- `assets/map/site/cliffs/cliff_face_inland_highres_v2.png`：仍是現行岩壁來源。
- `assets/map/site/settlement/`：住宅、水井、農田、營地箱圖集與共用去背材質。
- `assets/doll/reference/male_body_v2_highres.png`：僅為 3D builder metadata 指向的美術參考，沒有 2D runtime。

現行 3D 製作來源與獨立 3D benchmark 不在本次舊地圖／紙娃娃刪除範圍。
本機候選模型、備份、工具安裝及驗證截圖不等於發版資產。

## 驗證與限制

操作和既有功能限制見 `TERRAIN_GENERATOR_LAB.md`，本版發版證據見 `V0.35R_RELEASE.md`。
刪除回歸入口是 `scripts/tests/v03r_cleanup_test.gd`。
現行地形、角色／隊伍和武器測試保留在 `scripts/tests/terrain_*.gd`。
3D 製作流程見 `HUMANBASE_V1_3D_PIPELINE_HANDOVER.md`。
天然資源與土地的操作、實作範圍及此次驗證紀錄見 `SITE_RESOURCE_IMPLEMENTATION.md`；
完整設計依據保留於 `SITE_NATURAL_RESOURCES_AND_LAND_CONDITIONS_PLAN.md`。

應分別驗證資源／腳本載入、資料與通行斷言、實際 GPU 畫面；
載入成功不等於全部動畫、萬人效能或完整遊戲流程已通過。
