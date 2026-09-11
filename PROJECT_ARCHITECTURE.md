# Worldgoing V0.3R — 現行 Site 架構

## 正式入口

唯一遊玩入口為 `scenes/terrain_lab/TerrainLab.tscn`，由 `project.godot` 指定。
這是目前新作的 Site：100×100 格地形、玩家／NPC、騎乘、武器碰撞與百人隊伍。
保留 TerrainLab 名稱，不為發版另造入口或重命名整套程式。

V0.3R 移除已停用的 2D 紙娃娃，以及舊 Main、World、Region、ContinuousWorldMap、
SiteMap、舊 Battle／Formation／Travel／Persistence 流程與專用素材、工具、測試。
本版本沒有 World／Region 旅行與存讀檔功能，也不將舊存檔遷移至新 Site。

## 現行責任

| 擁有者 | 責任 |
| --- | --- |
| TerrainPreset／TerrainGenerator | 預設參數與相同 seed 的可重現生成 |
| TerrainData | 表面、高度、坡口與 can_step() 通行判斷 |
| TerrainRenderer／TerrainRenderLayer | 消費地形資料並繪製地表、岩壁 |
| TerrainLab | 場景組裝、輸入、Camera2D 與控制介面 |
| TerrainTestCharacter／TerrainTestNPC | 角色格位、移動、戰鬥與指令狀態 |
| TerrainWeaponCollision | 與實際投影一致的武器／身體碰撞 |
| TerrainArmy | 百人隊伍資料、路徑、佔格、隊形與共用士兵圖集 |
| CharacterVisualState／CharacterRenderContract | 外觀輸入與共享 3D→2D 投影規格 |
| HumanCharacter3DEditor／MountHorse3D | 男女模組化角色、換裝、染色、動畫與馬匹 |

地圖仍由 Node2D + Camera2D 控制。特寫角色使用透明 SubViewport 呈現既有 3D 模型，
再由 Sprite2D 顯示；刪除舊紙娃娃不代表改成 3D 世界。
百人隊伍的 3D 角色烘焙圖集不是被移除的紙娃娃系統，必須保留。
地形生成、通行資料與呈現維持分離，不另加平行座標或遊戲狀態擁有者。

## 必須保留的資源

- `assets/characters/human/q35/standard_anime_{male,female}_character_pack.glb` 與正式來源。
- `assets/mounts/horse/standard_horse_pack.glb`。
- `assets/characters/terrain_lab_army/standard_soldier/` 的圖集與 metadata。
- `assets/map/terrain_lab/` 中現行草地、水、沙地三張貼圖。
- `assets/map/site/cliffs/cliff_face_inland_highres_v2.png`：仍是現行岩壁來源。
- `assets/doll/reference/male_body_v2_highres.png`：僅為 3D builder metadata 指向的美術參考，沒有 2D runtime。

現行 3D 製作來源與獨立 3D benchmark 不在本次舊地圖／紙娃娃刪除範圍。
本機候選模型、備份、工具安裝及驗證截圖不等於發版資產。

## 驗證與限制

操作和既有功能限制見 `TERRAIN_GENERATOR_LAB.md`，發版證據見 `V0.3R_RELEASE.md`。
刪除回歸入口是 `scripts/tests/v03r_cleanup_test.gd`。
現行地形、角色／隊伍和武器測試保留在 `scripts/tests/terrain_*.gd`。
3D 製作流程見 `HUMANBASE_V1_3D_PIPELINE_HANDOVER.md`。

應分別驗證資源／腳本載入、資料與通行斷言、實際 GPU 畫面；
載入成功不等於全部動畫、萬人效能或完整遊戲流程已通過。
