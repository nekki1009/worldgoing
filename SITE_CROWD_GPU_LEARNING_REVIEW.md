# GPU Resident Crowd：附件學習與現況核對

日期：2026-09-25。依附件《Worldgoing：GPU Resident Crowd 架構學習規格》完成只讀研究。本輪沒有修改程式／場景、啟動 Godot、重跑效能測試或更換正式入口；僅修訂計畫及保存證據。

附件 SHA256：`F3DDD11574852A5B78872913CE5ABD3CF76E105E905123A8D681F18373290D96`。本輪來源指紋見 [source_manifest.json](output/site_crowd_learning_20260925/source_manifest.json)。修訂後唯一施工入口為 [Sol 計畫](SITE_CROWD_RESIDENT_CORE_PLAN_SOL.md)；[修訂前版本](output/site_crowd_learning_20260925/resident_core_plan_before_learning.md) 保留供比對。

先修正理解：附件給出新的 3D GPU Crowd 目標；現有正式入口仍是 `TerrainLab.tscn` 的 Node2D，另有獨立 3D Crowd／Promotion／FormationSpace 測試場景。不能把附件所有背景敘述當作已實作現況，也不能用舊正式場景限制否定新的 3D 原型方向。**第一階段按附件在現有 3D 路徑證明 GPU Formation Command → instance buffer，正式場景接入另有邊界。**

## A. 現有架構地圖

下表行號為本輪閱讀位置，函式名是主要定位；`scripts/benchmark/3d_crowd/` 簡稱 `crowd/`。

| 檔案／主要 class | 責任 | 呼叫者 | 輸入 | 輸出／下游 |
|---|---|---|---|---|
| `project.godot:16`；`scenes/terrain_lab/TerrainLab.tscn:5` | 正式入口，Node2D | 引擎啟動 | 專案設定 | `TerrainLab`；不是 3D benchmark |
| `scenes/benchmark/3d_crowd/FormationSpaceCrowdBenchmark3D.tscn` | 現有可重用的 3D 實驗入口 | formation-space runner | 場景實例 | 同一 promotion controller、renderer、special pool |
| `scripts/benchmark/3d_crowd_promotion/crowd_promotion_benchmark_controller.gd:142`／`CrowdPromotionBenchmarkController` | 每幀 simulation→promotion→pool→render 與量測 | 場景 `_process`、runner | delta、相機、測試選項 | shared simulation、promoted IDs、分段統計 |
| `crowd/battle_crowd_simulation.gd:159`／`BattleCrowdSimulation` | CPU Formation 移動、純資料士兵欄位、測試動畫 | controller | seed、delta、mode、active count | Formation state、可選 world cache、animation dirty IDs |
| `crowd/formation_state.gd`／`CrowdFormationState`；`formation_slot_generator.gd` | 中心、朝向、目的地、spacing；居中矩形 slot 算法 | simulation、batch | Formation／slot index | CPU macro motion、local slot；沒有正式平台規劃 |
| `crowd/crowd_renderer_3d.gd:278`／`CrowdRenderer3D` | 選 per-instance 或 formation-parent、LOD／分組／提交 | controller | simulation、camera、external Near IDs | MultiMesh groups／FormationRenderBatch、呈現計數 |
| `crowd/crowd_chunk_3d.gd`／`CrowdChunk3D` | 舊路徑空間 chunk 與 LOD/archetype batches | renderer | mesh/material、group capacity | MultiMeshInstance3D、CPU buffer consumer |
| `crowd/formation_render_batch.gd:34`／`FormationRenderBatch` | 每 Formation 一個 MultiMesh；局部槽位、父變換、custom data | formation-parent renderer | center/facing、spacing、slot mask/animation | instance Transform 初始化；常態父節點 transform |
| `crowd/crowd_promotion_policy.gd:52`／`CrowdPromotionPolicy` | 選 promoted IDs、穩定 pool slots | promotion controller | camera、CPU Formation＋slot位置、前次slots | desired Near slot IDs |
| `crowd/crowd_special_actor_pool.gd:113`／`CrowdSpecialActorPool` | 模組化 Special、骨架／動畫、render bundle、rigid裝備 | promotion controller | desired IDs、simulation、camera | 可見完整角色；promote/demote計數 |
| `crowd/crowd_near_actor_pool.gd`／`CrowdNearActorPool` | 基礎 CrowdBenchmark 的簡化 Near pool | renderer | Near candidates、simulation | 基礎 Near；與上列完整 Special pool 不混稱 |
| `crowd/formation_space_crowd_benchmark_runner.gd`、`formation_space_crowd_contract_test.gd` | 已有 per-instance／parent 比較及零全量位置寫入契約 | 有界測試啟動 | case、frames、camera | stdout 統計／斷言；非正式戰鬥驗收 |
| `scripts/terrain_lab/terrain_army.gd`／`TerrainArmy` | 正式 Army 人物、命令、隊長／幹部、格位及移動入口 | Lab／coordinator／Site | 命令、地形、occupancy、人物狀態 | 原戰鬥狀態、move proposals、2D呈現 |
| `formation_destination_planner.gd`、`formation_transit_planner.gd`、`formation_recovery_controller.gd`（皆在 terrain_lab） | 正式合法終點／平台排隊、corridor寬度、停滯恢復 | Army movement入口 | macro path、人物IDs、地形、leases／registry | 有版本的deployment/transit/queue slots與恢復提案 |
| `scripts/terrain_lab/site_combat_movement_coordinator.gd:187` | 原多隊移動協調與原子提交 | Lab action tick | 各隊提案、occupancy/reservations | resolved commits；不是自由GPU位置場 |
| `scripts/terrain_lab/terrain_army_batch_view.gd`、`native/army_idle/army_idle.cpp` | 正式Canvas row/page排序、呈現投影／packing | Army frame callback | CPU人物／外觀／動畫 | MultiMeshInstance2D 12-float output |
| `scripts/terrain_lab/terrain_army_gpu_buffer_writer.gd` | 已有 main RD→Canvas buffer 寫入試驗 | BatchView受控開關 | **CPU已算好的**逐run 5-float packet | GPU展成12-float；不是GPU AI |
| `scripts/terrain_lab/terrain_gpu_skinner.gd` | 舊 local RD 幾何取樣試驗 | 對應幾何測試 | CPU bone palettes | submit/sync後完整回讀；不屬主renderer常駐呈現 |

正式 MOVE 呼叫鏈已核對：`TerrainArmy::_preflight_combat_move:2672` 建 movement profile／macro path，再於 `2708` 呼叫 destination planner；Lab `971–980` 先 coordinator tick，再 Army prepare／complete；coordinator `187–240` 依 occupancy→prepare→propose→reservation resolve→atomic commit→finalize 執行。

## B. 現有 Crowd 每幀資料流

### B1. 3D 舊 per-instance 路徑

`controller._process → simulation.step → promotion_policy.resolve → actor_pool.sync → renderer.set_external_near_soldiers → renderer.sync_from_simulation`。

- simulation `159–194` 每 Formation 更新中心／朝向；`229–257` 每人更新動畫及可選 world position。它是測試行為，前排週期 ATTACK 不是正式交鋒。
- renderer `729–1038` 管理 Near、chunk/LOD membership、穩定slot；增減以 swap/remove 等操作維護 `_group_soldiers`，必要時 resize group arrays／buffer、重配 instance_count。
- `_write_group_data:1120` 掃 group；`1193–1195` 呼叫 `set_instance_transform` 並建立每人 Basis／Transform3D。
- `_write_group_buffer:1239` 另一分支在 CPU 按 16 floats／人準備連續 buffer，再 bulk upload；減少 API 呼叫不等於取消 CPU 逐人準備。
- custom data／dirty flags／layout arrays 也有CPU處理；不能只看draw calls判斷工作量。

### B2. 已存在的 Formation parent 路徑

`controller.set_crowd_render_path:266–276` 選 `FORMATION_PARENT_TRANSFORM` 時關閉全軍 world-position cache。renderer `317–455` 每隊改父節點 transform；`FormationRenderBatch:75–97` 只在初始化／spacing改變時建立local slots，`102–114` 常態改整隊position/rotation。

動畫事件仍於 renderer `398–408` 更新custom data；simulation仍有逐人動畫迴圈。少量Near／選擇查詢可由CPU Formation＋slot公式即時計算。**剛體隊形移動的每人Transform工作已能為0，GPU新候選必須與這條路徑比較。** 不把它重做一次算新成果。

現有shader嵌於 `crowd_renderer_3d.gd:532`；`INSTANCE_CUSTOM=(phase,state,active,variant)`，時間讀shader `TIME`，只是簡化頂點擺動，不是BAT／VAT。附件建議的 clip/phase/variant/flags 順序不可直接覆盖現有ABI。Phase1保留現有動畫、暫停行為與材質；不藉遷移順帶改動畫。

### B3. SPECIAL／Near與結構更新

promotion controller `162–175` 先同步Special pool，再將desired IDs遮掉Crowd proxies。pool `391–455` 會為Near設定Transform、外觀、動畫；`507–511` 的位置來自CPU simulation。`_demote_actor:496` 隱藏角色與清ID，**沒有GPU狀態讀回／寫回交易**。

rigid裝備的socket transform與render bundle切換屬Near成本：pool `162` 呼叫rigid renderer更新，promotion／外觀變化可能重綁結構。Phase1保持64人預算及相同socket/陰影設定，單列成本；不要把這部分與普通兵Transform時間合計後全算成Crowd收益。

現有10,000是simulation總人物數；其中64人promote時，理想守恆是 **9,936 Crowd proxies＋64 Near＝10,000**，不是新增64個人物。要測10,000普通兵外加64位獨立角色，需另列10,064人的fixture，不能沿用舊計數冒稱。

### B4. 正式 TerrainLab 是另一條鏈

正式目前是 CPU Army Dictionary/native prepare → query／交鋒 → native/CPU animation projection → row/page/Sprite分段 → MultiMeshInstance2D。此前模擬74.46%的診斷屬這條路徑，不能拿它否定獨立3D Transform原型，也不能用3D的PASS宣稱正式萬人已解決。

## C. 已確認瓶頸與證據等級

**有既存量測支持：**

- 正式 `run_1790327946/measurements.json`：60.058469秒中互斥模擬44.721632秒、CPU角色呈現8.013073秒；native calls 876,092、成功rows 16,167,316。這是含profile的歸因，非本輪新FPS。
- 正式presence同來源ABBA只有8.347→8.695 FPS；此前GPU writer 5k ABBA比CPU慢9.56%。證據分别在 `output/site_presence_delta_20260925/`、`output/site_crowd_gpu_20260925/`，都不能外推新3D indirect方案。
- 本機保存的Canvas probe通過0/1/65/1000、全RGBA比較；支持main RD direct buffer通路，不支持3D indirect已驗。

**由程式碼確定／成本仍需量測：**

- per-instance路徑有O(N) Transform準備與提交；parent路徑已移除剛體整隊移動的這項工作，仍有動畫、Near政策、mask與結構工作。
- `_write_group_data` 的 `last_multimesh_upload_cpu_ms` 計時涵蓋迴圈／判斷／Transform/API，不是純上傳；parent的transform準備時間也含LOD/custom/visibility工作。不能依欄位名稱直接相加歸因。
- 現有 `formation_gpu_transform_supported()` 回false並引用4.6.2限制，是舊程式旗標，不是對4.7.2 API的新探針。

**尚未確認：**

- 附件「10k＋64≈25–30ms」本輪未定位到可歸屬目前3D來源的原始報告。runner主要print；保留為待重測假設，不填入新的baseline。
- `.benchmarks/site_formation/*10000*near64*` 檔案指向較早 `scripts/runtime/formation_*`、Godot4.6.2的另一條來源，不是目前3D Crowd。不能因檔名相似拿来補證據。
- 新3D compute→indirect count、本機GPU時間／render-thread時間、真正VRAM用量與三路收益，均待實作指令後的有界測試。residual wall time不等於GPU time。

## D. 現有系統到目標架構對照

| 現有模組 | 保留 | 修改 | 替換 | 原因 |
|---|:---:|:---:|:---:|---|
| CPU Formation state／macro movement | ✓ | 僅command輸出／測試adapter | — | 100人編隊為第一層；GPU Phase1不改戰術 |
| per-instance renderer | fallback | backend選路 | GPU候選中的逐人Transform路徑 | 留作對照，非唯一baseline |
| Formation parent renderer | ✓ | 僅新路徑整合所需 | — | 已有零全軍Transform準備，必須保留作較強baseline |
| 原 mesh／material／custom ABI | ✓ | 單surface／格式斷言 | — | 不用換裝／畫質差異製造收益 |
| GPU instance producer | — | — | 新增最小compute backend | GPU讀Formation commands直接寫output，不讀CPU完整Transform |
| Near64／Special pool／promotion policy | ✓ | Phase1只接mask；獨立移動前加有界state交接 | — | 現有CPU公式僅在rigid-slot等價時仍正確 |
| 正式地形／平台／corridor planners | ✓ | 後續adapter | — | Phase1平地原型不重寫正式移動 |
| 完整native普通兵模擬改造 | 作獨立候選保留 | 降為正式整合工作 | 不列Phase1前置 | 此次單一目標是Transform資料流 |
| GPU grid、BAT/VAT、LOD compaction、戰鬥 | 現有功能保持 | 後續分期 | — | 尚無完整實作，不一起加入第一包 |
| 舊封閉社會／物資來源／完整歷史規則 | — | — | 不引入 | 本附件明確排除；現有正式code不因本輪文檔刪除 |

新3D規格每Formation最多100，含1隊長及幹部；現3D fixture只有100個普通slot、沒有職務欄位。正式Army預設100／上限200且有隊長幹部。後續需明定Army包含多個≤100 Formation的映射，不默認Army等於Formation、不直接截斷舊名冊。

## E. Phase 1 最小修改範圍

本輪僅設計，以下是收到下一個實作指令後的預計修改。

- 修改 `crowd_renderer_3d.gd`：新增GPU backend選路，接Formation commands／custom dirty／Near mask；沿用現有resources及fallback。
- `formation_render_batch.gd` 保留作B baseline，第一包預設不改。GPU backend持有純RS MultiMesh＋visual instance，沿用原World3D／camera／mesh／material；避免把Resource的快取欄位與手動RS配置混用。這只改低階呈現，不建第二套模擬owner。
- 修改 `crowd_promotion_benchmark_controller.gd`：第三路選項與cache關閉、計数，不改promotion算法、Special內部動畫或裝備。
- 修改既有 `formation_space_crowd_benchmark_runner.gd`：A/B/C、可機讀JSON、原始frame intervals、時間域與scope明示。
- 預計新增 `scripts/benchmark/3d_crowd/crowd_gpu_formation_writer.gd` 與同目錄 `crowd_gpu_formation.glsl`：只做render-thread resources／command upload／direct output／indirect count；不新增通用backend框架。
- 預計新增 `scripts/benchmark/3d_crowd/crowd_gpu_formation_contract_test.gd`：renderer-level 0/1/65/100/10000、columns切換、count／teardown驗證。不是另一個正式戰鬥場景。
- 暫不改 `project.godot`、正式 `TerrainLab.tscn`、native戰鬥、正式Formation規則、地形、裝備資產、save schema與promotion/demotion權威。Phase1動態columns只是input contract測試，不冒稱山地玩法已接上。

詳細資料契約、第一包內的小步順序及驗收見修訂計畫。

## F. API 可行性檢查

`worldgoing.csproj` 要求 `Godot.NET.Sdk/4.7.2`；專案Forward+／Windows D3D12。保存於 `output/site_army_scale_phase26_20260915/api/extension_api.json` 的header是4.7.2 official single precision，下列方法皆存在。本輪未啟動引擎，**綁定快照存在、歷史本機runtime成功、未來新3D實測是三種證據**。

| API／格式 | 已找到的證據 | 仍須驗證 |
|---|---|---|
| `multimesh_allocate_data(...,use_indirect)` | 本機API快照有；官方4.7.2支援 | 新3D consumer實際indirect配置與重建 |
| `multimesh_get_buffer_rd_rid()` | 本機Canvas probe／writer已用 | 3D output stride／motion-vector政策 |
| `multimesh_get_command_buffer_rd_rid()` | 綁定及官方source有 | 本機GPU改count真的影響可見繪製 |
| `get_rendering_device()` | 歷史Forward+ D3D12 probe成功 | headless／Compatibility為null的fallback |
| `call_on_render_thread()` | 現有writer／probe已用 | 新backend排程、reload與queued callback取消 |
| `compute_list_add_barrier()` | 綁定有 | 現有writer單pass，多pass依賴未驗 |
| 3D transform＋custom、無color | 12＋4 floats＝64 bytes | row-major、非對稱basis／translation測例 |
| Canvas transform＋custom | 8＋4 floats＝48 bytes | 不能套用3D stride與indirect假設 |
| indirect command | 每surface 5 uint／20 bytes，count在surface×5＋1 | 只寫count，保留引擎geometry欄位；Phase1單surface |

官方4.7.2 [RenderingServer](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/RenderingServer.xml)、[RenderingDevice](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/RenderingDevice.xml) 為具體API依據；附件的 `chatgpt-content-reference` 是不可解析引用，已換成來源連結。

[Canvas source](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/renderer_canvas_render_rd.cpp) 用CPU count及一般draw；[ForwardClustered source](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp) 有indirect draw分支。兩條不能混稱。

必要技術修正（官方source分析，尚待本機3D probe）：

1. [mesh_storage.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/storage_rd/mesh_storage.cpp) 的allocate同配置early-return未比較`use_indirect`。應用fresh RID→allocate indirect→設有效mesh→取得兩個borrowed RID；不能先普通配置後只原地翻開關。command buffer依mesh/surface建立，allocate後不一定已存在。
2. capacity固定，active=0清count，不重配零容量、不dispatch零groups。CPU visible-count setter不可在GPU接管後覆蓋count；getter亦不是GPUcount的證據。
3. buffer重配置／mesh變更／motion vectors可能換borrowed handles。用generation及uniform有效性守衛；只free自有RD資源，RS RID依其真正owner釋放。command stride見 [mesh_storage.h](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/storage_rd/mesh_storage.h)。
4. uploads在compute/draw list外；相依compute dispatch用barrier。global RD不submit/sync，deprecated `full_barrier()`不補同步。已enqueue不等於GPU已完成。
5. 原型單列TAA／motion vectors／physics interpolation設定及output offset契約；不得暗中改全專案設定過關。現有writer的uniform失效修補／錯誤回報可重用，其每run CPU packet介面不可沿用為常駐架構。
6. 4.7.2的MultiMesh Resource沒有`use_indirect` setter；其`set_instance_count`只走預設非indirect配置並快取count。直接RS allocate不更新Resource快取，MultiMeshInstance3D也沒有包裝任意MultiMesh RID的公開Resource介面。首個GPU backend使用純RS MultiMesh／visual instance，明確scenario／visibility／global transform／shadow／AABB；不要用`set_base`留下null或舊Resource的AABB／interpolation／nav資料。依據：[MultiMesh source](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/multimesh.cpp#L219)、[MultiMeshInstance3D source](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/3d/multimesh_instance_3d.cpp#L63)。
7. 原FormationRenderBatch透過Node.material_override套用shader；純RS instance要明確`instance_geometry_set_material_override`，並保留Material強引用及LOD切換同步，否則mask／動畫不會自然沿用。新output包含Formation中心，custom AABB也須採renderer-local並覆蓋移動範圍，不能複製舊formation-local小框。

## G. Phase 1 驗收計畫

- **資料流：**常態一般兵CPU world-position cache updates、Basis／Transform constructions、逐instance transform setter、全量Transform upload、GPU readback均為0；一次性初始化、結構事件、Near64與離線oracle分開計數。CPU仍有動畫／promotion迴圈，不能把Transform gate說成全部GDScript O(N)消失。
- **功能：**0/1/65/100/10000、靜止／直線／90度轉向、10×10↔3×34、場景reload、renderer disable/enable、視窗切換、相機進出與bounds。一般simulation把active至少取100且上限10k，所以0/1用renderer-level probe，25k要另擴fixture，不能假報已支援。
- **Near：**先保留既有rigid-slot CPU公式與policy；promoted proxy mask、穩定ID、無漏人／分身、ready後可見交接。GPU接管独立局部位置前，必須有有界selected-agent query與版本交接，不延到完整戰鬥Phase7才處理。
- **count：**未compact前`draw span`不是`active visible count`。mask中間有洞不能直接把indirect count改成活人數，否则尾端有效slot會被裁掉；Phase1保留span＋原active mask並分開統計，GPU仍處理孔洞vertices。真正compaction留後期。
- **性能：**1k/5k/10k×Near0/64，核心A/B/C固定相同mesh／material／LOD及每幀Transform輸出，保持seed、相機、shadow與simulation trace相同；另列各路原LOD政策的端到端case。因legacy逐兵LOD／FAR每3幀提交，parent按隊中心LOD／每幀改父變換，不能直接當成同條件（renderer `457/1023/1128`）。先短diagnostic，再60秒無探針交錯比較。GPU對parent有利才預設啟用，僅打敗per-instance不算整體完成。記錄main thread、render thread、GPU、Transform prep、upload、Near、counts與記憶體；無法直接量的欄位標 unavailable。
- **錯誤／生命期：**無RD／編譯失敗／無效borrowed RID／resize／reload等原因明示並fallback。Phase1 GPU只是CPU Formation的呈現投影，可由CPU狀態重建；Phase2 GPU獨立位置後另需一致checkpoint，不能用過期CPU公式回退。

這些是未來驗收安排，本輪不宣稱任何新PASS／FPS。

## H. 風險與未知項目

1. **主線整合：**獨立3D成功後要接何種正式戰場／SubViewport／新3D入口，尚未實作。本附件支持研究3D方向，本輪不擅改正式main scene或把3D當成當前formal現況。
2. **Formation契約：**benchmark目前居中10×10、沒有columns欄位；附件用前排中心。先沿用center pivot。正式平台60＋queue40已存在，但只有連合法排隊空間也不足才可拒令；64B矩形command不能表達不規則地形，後續需要revisioned SlotTarget／Corridor buffers。
3. **數量與身份：**平台容量／alive／queue／proxy／draw span／Near都是不同數值；StableAgentID、slot assignment與output index分開。100人目標不等於直接縮減formal200人的保存上限。
4. **CPU/GPU權威：**Phase1公式投影可不readback；Phase2有局部位置後，選人、Near、同tick正式occupancy不能繼續查舊CPU位置。mixed spatial phase與原救援／交鋒語義是未來formal integration gate，不是Phase1重寫所有戰鬥的理由。
5. **GPU收益尚未證明：**parent路徑已省掉大部分剛體Transform準備，新compute可能更慢。先如實量出差異，保留parent為可用預設；GPU的後續價值需由獨立位置／局部移動及完整資料流證明。
6. **後續grid與地形：**3×3鄰格必須符合最大作用半徑與cell size；32人/cell的overflow不能只計數後漏鄰居。避免OOB只是安全底線，還需不漏人的處理策略。soft separation不能直接替代formal的合法占格／reservations。

已修訂計畫的優先序：先完成本學習，再等下一個實作指令做Phase1；完整native戰鬥核心、GPU避讓／動畫／LOD／戰鬥和正式容量遷移分別交付，不一起重寫。
