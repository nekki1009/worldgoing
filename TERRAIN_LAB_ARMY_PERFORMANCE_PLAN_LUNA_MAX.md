# Terrain Lab：100 人軍隊效能改善實作方案（交付 Luna Max）

日期：2026-09-09。狀態：第一階段已實作並完成 GPU-backed 量測；MultiMesh 仍依停止條件暫不加入。

## 0. 本次實作結果（2026-09-09）

- 99 名制式士兵已由即時 3D SubViewport 改為一張共享 `standard_soldier_atlas`（idle/walk、四方向）；隊長仍使用一個即時 3D presenter。
- 執行時只保留一個活躍 3D 來源；普通兵的方向、idle/walk 幀與腳底 anchor 由 packed 陣列/manifest 控制。
- 圖集同時輸出 PNG 與 Godot `.res` 資源；runtime 優先載入 `.res`，剛烘焙且尚未建立 import sidecar 時才使用開發回退載入。
- Follow 目標未變時不重建距離場；繞路 BFS 改用 PackedInt32Array，單一 render frame 最多啟動一個、單次最多展開 2048 格；模擬 planning budget 調為 8。
- 實際測試（Godot 4.6.2 / D3D12 / RTX 5060 / 2560×1440 / 100 人 / PLAINS seed 24680）：BASE P95 16.775ms、軍隊閒置 P95 16.779ms、邊緣移動 P50 16.668ms、P95 16.830ms、P99 26.556ms、最大 27.209ms、Engine FPS 60；活躍 3D 來源 1、SceneTree nodes 1666。
- 因上述第一候選已達到目前 Lab 的 60 FPS 穩態門檻，尚未加入 MultiMesh；若日後 GPU/提交分析顯示仍有瓶頸，再依第 6 節做 A/B。

## 1. 任務與完成範圍

在現有 Terrain Generator Lab 的 100×100 地圖上，改善一支 100 人軍隊的部署、待機、跟隨 PLAYER、往地圖邊緣前進時的效能與幀時間穩定性。

保留 TerrainArmy 的資料與指令入口、TerrainData.can_step 的移動權威、每格一人、預約格防重疊，以及角色目前的尺寸與腳底位置。地圖維持 Node2D + Camera2D，cell 為 64×64 邏輯像素，zoom 0.1–10。此次不加入多軍隊管理、士兵戰鬥、World/Region/Site、資源或存檔。

建議交付架構：99 名制式士兵使用現有 3D 模型離線烘焙的動畫圖集；隊長、PLAYER、測試 NPC 保留目前即時 3D 投影。一般士兵的模型來源不換成其他美術，改的是執行時呈現方式。先以共享 atlas 的 Sprite2D 驗證成本；僅在量測證明繪製提交仍是瓶頸時，加上分組 MultiMeshInstance2D。

此方案不是「100 個 Node 必定太多」或「GPU 使用不足」的診斷結論。必須先建立本機基準，再依下述關卡完成改善。

## 2. 已核對的程式現況

### 2.1 實作前基線：不是 100 套 3D 骨架

`scripts/terrain_lab/terrain_army.gd` 的 `_create_visual_source()` 建立兩個 HumanCharacter3DEditor：制式士兵 body_index=0、隊長 body_index=1。`_rebuild_visual_instances()` 建立 100 個 Sprite2D，分別引用這兩個 SubViewport 的 texture。

- 每個共享 viewport 為 1280×1536，約 197 萬像素；兩個約 393 萬像素。這是 render target 面積，不是 GPU 實測耗時。
- 移動時兩個來源 UPDATE_ALWAYS；全部停止後 UPDATE_DISABLED，並停用 editor processing。
- 有兩幀 warmup，避免第一張尚未繪製的黑色 texture 被保留下來。
- 100 個 Sprite 目前引用完整、具有大量透明邊界的畫面。投影尺寸約 243×292 地圖像素，人物本身小得多。透明區重疊可能增加 fragment 成本，需量測。
- `facing` 陣列有更新，但目前軍隊呈現並未依每位士兵套用不同朝向與走路動畫；共享來源初始化選的是 idle。不能把現有低 FPS 解讀成已完成 100 人獨立動畫的成本。

### 2.2 實作前基線：已有優化仍沒有約束最壞情況

同檔案的 SIM_STEP=0.10 秒，即 10Hz；註解中「100 Hz planning slice」並不正確，實作時修正註解。

- `_process()` 限制每 frame 最多兩個 simulation steps，但每一步內的搜尋工作沒有展開格數上限。
- `_simulate_step()` 每 0.5 秒呼叫 `_replan_follow()`；後者先 `_clear_navigation_paths()`，即使目標未改變也會重新準備導航。
- `_ensure_distance_map()` 雖使用 packed 陣列，仍會一次完成整張可達地圖 BFS。
- `_next_step()` 受阻後呼叫 `_find_path()`；後者使用 Dictionary、Array，完整 BFS 後逐項 push_front 重建路徑，但呼叫者只使用第一步。
- PLANNING_BUDGET=12 是每 tick 嘗試士兵數，不是 BFS 展開量。極端情況同一 frame 兩次 tick 可觸發多次大搜尋。
- `_find_path()` 不把其他士兵的占格納入路徑，因此擁擠時可重複找出當下不能走的同一路徑；後面的預約檢查防止重疊，卻不避免搜尋浪費。
- `_choose_edge_targets()` 建立可達格列表並排序，100×100 時可能涉及約一萬項。
- `moving_count()` 多次掃描、100 次 Sprite transform 更新也有成本，但不能在量測前視為首要瓶頸。

### 2.3 地圖、PLAYER 與 NPC 是獨立基準成本

`terrain_renderer.gd` 使用四個保留繪圖層。draw commands 一旦生成，Camera 移動原則上不需要重建；但 10,000 格內容仍有渲染成本。`terrain_test_character.gd` 包含即時 3D、戰鬥姿態與碰撞取樣，不能把整個 Lab 的耗時都算在軍隊。

前次 deterministic/headless PASS 與截圖正常只能證明部分功能。前次約 181ms 的數字是「生成一張地圖」的時間，不是每幀耗時，也不是 100 人穩定 FPS。現有 army test 主要驗證短時間合法移動，沒有證明全員能到達邊緣。

## 3. 第一關：可重現基準與瓶頸隔離

新增一個小型效能腳本，呼叫真正的 TerrainLab.tscn 與 TerrainArmy，不建立假地圖 Demo 取代實際流程。紀錄使用的 Godot 版本、CPU/GPU、driver、renderer/backend、build、OS window 尺寸、實際 viewport 像素、VSync、FPS cap、seed、preset、zoom。

正式比較使用同一台機器、同一 renderer、2560×1440 實際 viewport；目前 1600×900 OS window 另做相容性確認。先用未限 FPS 的模式診斷，再使用 VSync/60FPS 遊玩條件驗證。不要把 frame cap 等待時間当成計算成本。

每案例暖機 5 秒，取樣 20 秒。先跑一輪；最後候選與基準的關鍵案例各跑三輪。以 process_frame 間實際牆鐘間隔統計 frame-time median/P95/P99/max、超過 33.3ms 與 50ms 的幀數。FPS 可另列，但不要只讀 Engine.get_frames_per_second()。部署時間、首次 shader/import、生成時間分開列，不混進 steady-state 數字，也不要隱藏尖峰。

固定 PLAINS seed=24680、TERRACED_HIGHLAND seed=12345，保留 100×100。若指定位置不可達，從資料 deterministic 選取合法位置並寫進報告，不能靜默換 seed。

| 模式 | 模擬 | 軍隊繪製/來源 | 用途 |
|---|---|---|---|
| BASE | 無軍隊 | 無軍隊來源 | Lab 本身成本 |
| DATA_ONLY | 同一份100人指令與移動 | 不建立來源及士兵 Sprite | CPU 模擬成本 |
| VISUAL_ONLY | 重播固定合法移動軌跡，不做尋路 | 原兩個來源與100 Sprite | 軍隊呈現成本 |
| FULL_LIVE | 完整 | 原共享即時3D | 修改前基準 |
| FULL_BAKED | 完整 | 99 atlas + 即時隊長 | 第一候選 |
| FULL_BATCHED | 完整 | 僅必要時加入 MultiMesh | 第二候選 |

先在 zoom=1.0 跑待機、跟隨、往邊缘三情境。確認最慢情境後，另跑 Fit map、2.2×、10×，以及軍隊完全在視野外。移動腳本須真的令士兵移動並記錄 completed_steps、平均 moving_count、到達數；「100 人卡住不動但 FPS 很高」不算通過。往邊緣案例必須在樣本期間還有移動，提早抵達則另列移動區段和到達後區段。

必要的局部計時（預先分配記錄陣列，結束才寫檔，不每幀 print）：

- army_sim_us、replan_us、distance_field_us、path_search_us、visual_submit_us。
- 每 frame 的 BFS 展開格數、搜尋啟動/完成/取消數、pending jobs、導航版本。
- moving_count、arrived_count、completed_steps、blocked_count、模擬落後/捨棄時間。
- Node 數、軍隊 Skeleton/AnimationPlayer/SubViewport 數與活躍來源數。
- draw calls、render objects、texture/video memory（註明 API 是根 viewport 或全部 viewport 統計）。
- GPU frame time 使用 Godot Visual Profiler 或實際 GPU 工具；無法取得填 N/A，不能拿腳本耗時相減推算 GPU 時間。

隔離時只 hide Sprite 不會自動停用 source viewport，必須分別控制。若停止 shader/3D 工作，需先成功得到一張有效 texture，再凍結來源。完整基準不得省略正常遊戲的 PLAYER/NPC。

判讀：DATA_ONLY 慢，優先修導航；VISUAL_ONLY 慢，細分來源渲染與 Sprite overdraw；BASE 已慢，先列出地形/PLAYER/NPC 基準問題，不能宣稱只改軍隊就達標。GPU 使用率低也可能是主執行緒或 VSync 等待，不以「提高 GPU 百分比」為驗收指標。

## 4. 第二關：導航搜尋有界、保留可走規則

在 TerrainArmy 內改，不另建 ArmySystem2。

### 4.1 地形連通資料與動態占格分離

每次 generate/deploy 對應一個 terrain revision。從 `TerrainData.can_step()` 建立四方向靜態通行遮罩與必要的連通資訊，使用 packed 陣列；重新生成清空舊快取。玩家/NPC/士兵位置變化只影響動態占格與 reservation，不讓整張靜態圖因此失效。

導航快取 key 至少含 terrain revision、起點/目標及用途。不得把來源不同的距離圖混用。不要只改 `_clear_navigation_paths()` 讓它永不失效；隊長起點或所需目標真的改變時仍須更新。

### 4.2 搜尋改成可續跑工作

沿用 BFS，第一版不引入 AStar、執行緒或 GPU 尋路。將 frontier、head/tail、previous/distance、job purpose、revision 保留到下一 frame。完成後一次發布結果，禁止讀到半張 field。

起始調校值（不是已測性能）：每 render frame 全軍隊合計至多展開 512 格；同時使用約 1ms 軟時間預算，每32格檢查一次。時間限額到或格數用完就 yield。任何單一非搜尋工作也要計時，不能用 1ms 的搜尋限額宣称整個 simulation 只有 1ms。

每 frame 只建立一份共享預算，兩次 simulation tick、follow/edge/deploy/search 全部共用，不能各自重設。排程 cursor 公平輪轉；必要時允許一個持久 BFS 工作區與去重 FIFO，避免每位士兵複製一萬格陣列。

未完成時繼續使用仍有效路徑或等待；不可穿峭壁、走水、跳格、瞬移。新 generate/clear/command 以 revision 取消舊工作；完成回呼不得寫入已清除的 army 或新地圖。

### 4.3 避免重複與無效工作

- 0.5 秒是檢查 follow 需求的節流，不是無條件重建。player cell/formation goal 未變、靜態版本未變且路徑有效時沿用。
- 保留每人的已完成路徑和游標，只在目標/地形改變或證明失效時重算。可先用既有 Array 路徑，100人規模不需要複雜路徑儲存系統。
- 靜態 BFS 不處理所有擠塞；執行下一步時再用 owner/reservation 做安全檢查。暫時被友軍擋住先等待及局部讓路，不每 tick 再跑同一 BFS。
- 同一 start/goal/revision 的 pending job 去重；受阻重試採有上限的延遲與輪轉，避免所有人同一 frame 重試。若要避開暫時堵塞格，記錄該路徑的 blocker revision，不污染靜態快取。
- 路徑由終點 append 反推後 reverse 一次，避免 push_front；單步需求可回溯求第一步，但若會繼續走同一目標，保留完整路徑更合理。
- `_choose_edge_targets()` 可按到邊緣距離逐圈檢查、收集100個合法目標後停止；同距離用固定 cell index 破同分。若連通區接不到邊界，UI 明確顯示「最近可達位置」而非假稱到達邊缘。
- 部署也可跨幀搜尋，pending 期間按鈕顯示準備中，完成100格才原子發布。不足100格完整失敗，不能留下半支軍隊。
- moving/arrived 統計每 tick 計算一次或在狀態轉換維護；讀 UI 不觸發額外搜尋。

### 4.4 模擬時間不能靠丟幀假裝加速

保留 0.24秒/格的軍隊速度與平滑插值。搜尋 pending 不阻止已開始的合法移動完成。現有 accumulator 上限可能在慢機讓世界時間變慢，需記錄落後與丟棄量；不得藉提高丟棄量達成 FPS 指標。優化後驗證同一路徑不同顯示幀率的行走時間接近，停走、預約釋放、路徑取消不跳動。

## 5. 第三關：從既有3D模型烘焙一般士兵

### 5.1 保留範圍

PLAYER、測試 NPC、隊長仍用現有 live presenter。99 名普通士兵共用一套 atlas，不建立各自 Skeleton、AnimationPlayer、SubViewport 或角色編輯器。隊長仍維持現有 body_index=1，不能未經要求換模型。先保留隊長原先功能；其獨立朝向/idle/walk要對應資料。

一般士兵第一版只烘焙實際需要的 idle、walk，四個真實方向。不要鏡像左/右導致盾牌和武器換手。run、攻擊、死亡、騎馬不在此次100人軍隊指令範圍；保留擴充 manifest 的方式即可，不能把 PLAYER 的騎馬功能移除。

### 5.2 烘焙來源與相機契約

離線工具使用 `HumanCharacter3DEditor` 現有組裝/選部件/動畫 API 與 `CharacterRenderContract`，先搜尋是否已有可用3D baker；舊2D紙娃娃合成器不能宣稱能直接輸出此模型。

固定 body、部件 ID、動畫 ID、相機 profile、光源、朝向。使用 clip duration 等距取樣，idle 起始12fps、walk起始24fps；loop clip 不重複最後一幀，必要時增加取樣率消除頓挫。必須包含實際 editor 初始化及 procedural 附加動作的姿勢更新，不能只 seek AnimationPlayer 就假定所有部件已同步。

烘焙來源可沿用1280×1536；輸出裁切尺寸由所有方向/idle/walk的 alpha bounds 決定。不得把這整張 render target 當成每幀atlas tile。

採「全方向全動作聯集裁切框」與共同腳底 anchor，再用同一縮放率處理所有幀。禁止每幀自動貼滿格子、把人物縮小塞進格子、移動腳底或對動畫單獨改 scale。

設來源腳底投影為 A、共同裁切起點 C、來源到atlas比例 r、原本 source sprite scale 為 s：

    atlas_anchor = (A - C) * r
    map_scale = s / r
    畫面左上角 = rendered_foot_position - atlas_anchor * map_scale

atlas frame 的有效尺寸包含 padding，anchor 同步加上 padding。Sprite 的 centered/offset 設定必須與公式一致。驗證與 live source 相同時間點、方向、腳底比較，不拿 viewport 中心當腳底。

目前 MAP_PIXELS_PER_METRE=37.12841796875、TEXTURE_FILTER=NEAREST。保留契約；atlas分辨率以1×、2.2×、10×實圖比較決定。先輸出每地圖像素約4個來源像素的版本供檢查，若10×明顯退化再提高；這是品質候選，不是以256px幀等固定尺寸硬套。不得為達效能目標悄悄調低 PLAYER或隊長尺寸。

### 5.3 圖集與 manifest

輸出建議 `assets/characters/terrain_lab_army/standard_soldier/`。每頁建議不大於4096×4096，放不下就分頁；實際上限與GPU驗證後記錄。採共同 frame extent，動畫幀依方向/clip固定排序並記錄 rect/page，避免程式猜列數。

manifest 至少保存：schema_version、source_hash、body/part IDs、renderer/contract版本、方向與yaw、clip duration/sample rate/frame count、頁路徑/尺寸、frame rect、共同anchor、map_scale、padding、filter/mipmap政策。

source_hash 包含模型與部件依賴、動畫來源、baker程式、render contract及烘焙參數。hash可重現不代表跨GPU烘焙pixels保證逐位元相同；兩者分開檢查。

透明底、邊緣至少2–4px extrusion並保護UV；若使用mipmap，padding必須按使用的mip層驗證，不可直接套2px。第一版沿用nearest且關mipmap；遠景閃爍如不合格，再做帶足padding的mip版本比較。不得把UI/背景/地面一起烘入，不得有黑框、白框、重影。

普通未壓縮4096² RGBA8每頁約64MiB（不含mip）；以頁數計算上限，不拿PNG檔案大小當VRAM。初版常駐士兵atlas目標≤128MiB；如果保留原品質需要超過，列出實際品質/記憶體差异，不默默降畫質。所有99人共享同一Texture資源。

工具先寫入新version輸出並完整驗證後切換manifest，失敗保留已驗證版本。正式運行走 Godot `.res`/imported resource；只有剛烘焙且尚未建立 import sidecar 的開發測試才允許 `Image.load_from_file()` 回退，不能把回退路徑當成正式匯出依賴。

### 5.4 執行時呈現

先用既有 `_sprites` 更新方式接atlas：依每人的 UnitState、facing、clip time 查frame rect，僅在幀號/方向/clip改變時更新texture region；位置仍每render frame平滑插值。世界移動採terrain cell，烘焙像素不決定碰撞或占格。

不為每個士兵建立AnimatedSprite2D+AnimationPlayer組合；使用資料陣列控制clip time。phase可依unit index穩定錯開，不用每幀random；idle/walk轉換保持腳底和模型比例。

正常烘焙模式不建立 `_soldier_editor`。隊長來源可暫沿用現有editor式來源，但只保留一套，且只在必要時更新；不得把不顯示的完整UI成本複製99次。live A/B模式只保留開發開關。

atlas缺失/過期時清楚顯示錯誤與重烘焙命令；不能静默退回慢路徑後仍標示 baked。開發者可明確選live fallback，HUD與報告必須註記。

## 6. 第四關：GPU批次，僅在需要時啟用

先比較同一導航版本 FULL_LIVE 與 FULL_BAKED。若atlas Sprite已達標，100人階段停在此處，報告MultiMesh未實作的量測理由。100個簡單Sprite不值得以錯誤遮擋換取Node數減少。

若繪製提交/CPU transform仍佔顯著成本，新增一個小型 `terrain_army_renderer.gd`，由TerrainArmy餵資料，採MultiMeshInstance2D+QuadMesh+atlas shader。已有BattleSiteMap的MultiMesh可參考資源初始化，但不可搬Battle模擬進Lab。

- 一個instance對應一名士兵；設定2D transform、colors/custom data後才配置instance_count，容量不每幀重建。
- custom data可存atlas rect（normalized uv origin/size）；CPU在frame變動時更新。第一版不強制shader時鐘或GPU移動，把可驗證的簡單路徑做好。
- 批次按atlas page、繪製層分組；可見範圍依完整frame extent外擴，不能只用foot cell裁切。
- MultiMesh整批視為同一可見物件，沒有逐instance自動裁切，也不能假設每個instance各有CanvasItem z_index。不要一口氣把99人塞進一個永遠蓋住PLAYER的batch。
- 初版沿用現有 `10 + int(rendered_foot_y / 64)` 的排序鍵，按有人的Y列及atlas頁分桶；每桶一個CanvasItem，只有列/頁改變才移桶。再以PLAYER/NPC/隊長穿插案例驗證同列的穩定順序。若同列需精確交錯，可分開少量重疊角色或沿用Sprite；不能只在報告說排序已處理。
- 不預建100列×多頁空Node；空桶可保留小池或移除，記錄其上限。若桶數/上傳成本抵銷收益，回用atlas Sprite並記錄結果。
- 設定包含裁切框/anchor的正確bounds，避免邊缘角色突然消失。畫面外只停止繪製提交，保留必要模擬及占格。
- shader不讀回GPU，不每frame get_image()，不每士兵建立ImageTexture。避免每幀整張atlas上传。

GPU instancing減少提交，不會自動解決導航或透明overdraw。參考：[Godot 4.6 MultiMesh](https://docs.godotengine.org/en/4.6/classes/class_multimesh.html)、[GPU optimization](https://docs.godotengine.org/en/4.6/tutorials/performance/gpu_optimization.html)。

## 7. 建議修改檔案與責任

| 檔案 | 本次責任 |
|---|---|
| scripts/terrain_lab/terrain_army.gd | 預算搜尋、快取、revision取消、atlas呈現接入、共享來源生命週期 |
| scripts/terrain_lab/terrain_lab.gd | 準備中/模式/atlas錯誤與精簡效能資訊，不加入新玩法 |
| scripts/ui/character_render_contract.gd | 原則上唯讀；baker引用其相機/尺度，不為普通兵另定比例 |
| scripts/ui/human_character_3d_editor.gd | 優先引用現有API；若缺離線姿勢同步入口，只加入必要入口，不重寫編輯器 |
| scripts/tools/bake_terrain_army.gd（若無可用既有工具） | 離線模型/動畫/透明裁切/atlas及manifest產生 |
| scripts/terrain_lab/terrain_army_renderer.gd（條件新增） | 僅MultiMesh關卡需要時拆出顯示責任 |
| shaders/terrain_army_atlas.gdshader（條件新增） | 僅MultiMesh的UV取样，不持有軍隊資料 |
| assets/characters/terrain_lab_army/standard_soldier/ | 烘焙頁及版本manifest |
| scripts/tests/terrain_lab_army_test.gd | 擴充重要移動/取消/預算契約，不為每個getter建測試 |
| scripts/tests/terrain_lab_army_visual_test.gd | 由硬寫_soldier_editor改驗baked/live模式契約、方向及anchor |
| scripts/tests/terrain_lab_army_performance_test.gd（新增） | 真Lab基準、隔離模式、幀時間CSV/摘要 |
| TERRAIN_GENERATOR_LAB.md | 操作、重烘焙、效能實測與限制 |

建檔前用搜尋確認已有同責任工具，能擴充就不再新增。保留工作區既有未提交內容，不整批還原/刪除。

## 8. 執行順序與停止條件

1. 讀本文件、PROJECT_ARCHITECTURE.md、TerrainLab/Army/Data/RenderContract及本地驗證指引，核對變動。先保存基準報告。
2. 完成有預算導航工作；跑合法移動、狹口與取消測試，與同CPU基準比較。不要只降低tick頻率。
3. 完成制式士兵idle/walk四方向bake、atlas與固定anchor對照；先用少數士兵證明外觀等比例。
4. 接99人atlas＋即時隊長，更新視覺測試，實際走動/zoom/重部署。停用普通兵live來源後重測。
5. 達標即交付；未達標且提交成本顯著才做MultiMesh關卡。若是地圖或PLAYER/NPC主因，先提供隔離證據，僅做与本次效能相關的最小修正，不能任意降低素材品質或停用功能。
6. 收尾測試與實測報告。不要自動開始1000人、裝備自由組合烘焙或完整戰鬥。

每關寫結果與下一步，不需要每關重問是否繼續。本文件本身僅是規劃；使用者交付「照方案實作」後按此順序執行。

## 9. 必做驗收（精簡但能抓到原問題）

### 功能

- 100人部署：1隊長+99兵，全部合法唯一cell；pending/不足格不留下半成品。
- 跟隨與邊缘移動：追踪真實completed_steps和完成時間，完整測到可達目標；不能只跑40 ticks就宣稱成功。
- 有一條坡道跨高度、一格狹口、被友軍暫時堵塞：必須通過合法入口；過程不重疊、不穿水/峭壁；壅塞解除後恢復推進。為100人通過設置例如180秒模擬時間的有界timeout並報未到達數。
- 連續換指令、搜尋中clear/generate、部署清除20次：沒有舊job結果污染、殘留reservation、額外來源/Node增長。
- 搜尋上限有計數assert；時間門檻只做性能報告，不做易抖動的CI assertion。
- 不同顯示幀率下起步/結束不漂移，移動時間保留；CPU renderer不改can_step。

### 視覺

- 真TerrainLab截圖與短動畫：四方向idle/walk，1×/2.2×/10×，至少包括側向盾牌/披風與腳底位置。
- atlas與原模型同部件/姿勢/相機對照：尺寸相同、anchor誤差目標≤1個地圖像素、武器不裁切、不浮空、不每frame呼吸縮放。
- PLAYER/NPC/隊長穿過普通兵前後、坡道、地圖邊界：沒有錯誤覆蓋、突然消失或可走格變化。
- 親自打開生成圖與觀看動作；輸出檔存在或測試print PASS不能當美術驗收。PNG是baked model render，不是假稱新生成美術。

### 性能目標（待實測，非承諾已有成績）

- 參考本機/相同backend與2560×1440，暖機後100人走動目標接近穩定60FPS；未限速的frame time P95≤16.7ms、P99≤25ms，正常跟隨/導航沒有反覆>50ms尖峰。
- 軍隊CPU（sim+navigation+提交）目標P95≤2ms/frame；若BASE本身已超16.7ms，完整場景60FPS明確記為未達標，不能用軍隊增量達標取代。
- 與基準同情境比較P95/P99與移動吞吐；如果未達绝對目標，報實際差距。不得把等待/停止士兵、關閉GPU工作、減少實際人數當作改善。
- steady-state普通兵Skeleton/AnimationPlayer/SubViewport為0；隊長仍至多1套來源；PLAYER/NPC另計。圖片模式一般兵共享atlas頁、無持續烘焙/CPU讀回。
- clear/redeploy20次之後有暖機平台，記錄RAM/VRAM與Node plateau；資源快取不必每次歸零，但不能每次增加一套。

實測只要求100人與0人基準；不要為本次驗收建多隊管理。

## 10. Luna Max完成回報格式

1. 實際瓶頸：CPU導航/來源3D/透明重疊/提交/場景基準，逐項以隔離結果支持。
2. 實際修改檔案與替換路徑；說明普通兵是否baked、MultiMesh是否需要且已做。
3. 烘焙規格：方向、clip/frame數、尺度/anchor、頁數/尺寸、來源hash、VRAM估算/實测、重建命令。
4. 同機前後表：preset/seed/zoom/人數/模式、frame median/P95/P99/max、CPU區段、GPU（無則N/A）、completed_steps/到達數、Node與活躍來源。
5. 實際開啟檢查的預覽/動畫路徑；列出10×品質是否通過。
6. 已跑的功能/性能測試、exit code、是否timeout；列出未達成條件，禁止把headless PASS寫成FPS PASS。
7. 不自行開始下一階段。

## 11. 本次規劃依據與限制

以上根據2026-09-09現有程式靜態檢查與先前對話的測試紀錄。此次沒有新跑遊戲、GPU profiler或FPS基準，瓶頸優先度是待量測假設。Godot CPU計時方法參考：[CPU optimization](https://docs.godotengine.org/en/4.4/tutorials/performance/cpu_optimization.html)。所有效能數字目標與計算面積已和實測結果區別。
