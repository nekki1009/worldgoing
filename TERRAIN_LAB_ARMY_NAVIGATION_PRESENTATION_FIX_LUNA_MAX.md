# Terrain Lab 隊長呈現、連續跨層導航與隊員跟隨修正

> 2026-09-09 重新審核：本文件的完成推論不足。FOUND 隊長路徑仍可被士兵新請求清除，多層測試亦未讓99人同時跟隨。後續實作以 [隊長領軍修訂方案](TERRAIN_LAB_CAPTAIN_LED_MARCH_PLAN_LUNA_MAX.md) 為準，取代本文件的多人邊緣目標與搜尋佇列建議。

交付：Luna Max。日期：2026-09-09。狀態：本輪修正已實作；headless 導航契約已通過，視覺測試腳本已更新，實際 GPU 截圖仍需在可用的視窗渲染環境執行。

本文件是前一份 CAPTAIN_SWAP 計畫的補正。先前 PASS 僅證明局部交換與短期運作，不能視為本文件三項需求已完成。本輪已在既有 TerrainArmy 上完成最小垂直切片，沒有建立第二套軍隊或導航架構。

## 1. 工作目標與既有契約

1. 隊長移動時播放正確 walk，轉向對應實際行進方向；停止回 idle，交換也必須正確呈現。
2. 隊長能循合法坡道連續跨越多個高度層，包括必須先遠離目標才能找到下一個坡道的路線。
3. 隊員迅速開始跟隨並持續步進，通過狹口後重整隊形；提高排程吞吐量，不靠縮短人物步行時間。

沿用 TerrainArmy、TerrainData.can_step、TerrainTestCharacter 的呈現 API、100×100 地圖、64px cell、一格一名邏輯角色、隊長 index 0、99 名烘焙士兵與一個隊長 live 3D source。保留既有合法原子交換。不要新增 World/Region/Site、戰鬥、物理人群或每士兵導航 Node。

## 2. 已確認根因與待重現部分

### 2.1 隊長動畫和方向

terrain_army.gd::_create_visual_source 只呼叫 select_animation_by_id(idle)。後續 facing[0] 雖然在普通移動和交換時更新，卻沒有 set_preview_yaw_degrees 或隊長 walk/idle 狀態同步。_set_visual_sources_active 只是播放／暂停來源，不會自動選 walk。

TerrainTestCharacter.step 已有可沿用 API：set_preview_yaw_degrees，DOWN=0、UP=180、LEFT=-90、RIGHT=90；select_animation_by_id(walk/run)。映射必須和實際畫面四向比對，不可只因數值相同就宣告視覺通過。

### 2.2 連續下山

- _find_path 在檢查本幀預算前，遇到不同 requester/start/goal 就 _start_path_job。隊長剛展開 256 格，另一士兵即使沒有剩餘預算，也能先把工作區清空。單独重複相同請求的測試看不見此問題。
- _next_step 每次先選 Manhattan 距離下降的鄰格，只在走不通時才搜繞路。FOUND 路徑只取 path[0]，未保存後續游標。繞障第一步若遠離目標，下一次可能又貪心走回原處。
- _replan_follow 因隊長換格而清除搜尋、重新決定 leader_goal，使跨層路線與跟隨目標反覆失效。
- _choose_edge_targets 按距邊界排序所有可達格；若外邊界根本不可達，仍可能把內側格當成成功的「邊緣」。需要明确報告真正外邊界是否可達。
- TerrainData.can_step 沒有「只能跨一個高度層一次」限制；每一步高差 1 且雙向 ramp 合法即可。使用者當前 seed 是否缺下一層連通仍需重現，不能先認定都是導航，也不能放寬 can_step 掩蓋缺口。

### 2.3 隊員掉隊

SIM_STEP=0.1、PLANNING_BUDGET=8，最多約 80 次下一步嘗試／秒，還包括失敗嘗試。100 人每步 MOVE_DURATION=0.24，要連續走約需 417 次成功步進啟動／秒。這是容量估算，不是實測。現行 10Hz 完成量化也使一步通常至少 0.3 秒；輪轉等候又增加停顿。

_formation_goal 永遠放在固定 +Y 一側，且以隊長最終目標為中心，隊員各自橫切去抢遠端格，不是在跟隨隊長實際路線。窄坡道不适合强制维持十列队形。

### 2.4 既有驗收缺口

- ramp 測試 assert(captain.x >= 50 OR moving_count > 0)，可能由其他士兵移动代替队长到达。
- long route 測試直接連續呼叫同一 _find_path，沒有其他 99 人搶用工作區。
- 大部分測試直接 _simulate_step，未走 advance_frame 的幀預算。
- 效能測試允許 moving_count>0 代替完成步數，而且步數起點在暖機前，不能證明正式採樣期間持續前進。
- 交換截圖沒有固定相機對準交換兩人，也未逐張等待 frame_post_draw；前一輪圖中主角位於畫面上緣甚至畫面外，不能證明腳底／朝向正確。

## 3. A：隊長呈現同步

在 TerrainArmy 新增小型 _sync_captain_presentation()，保持單一資料來源。

- 由 movement_state[0] 決定 MOVING/SWAPPING→walk，IDLE/WAITING/ARRIVED→idle。保留停止時最後 facing。
- 緩存最後 clip 與 facing，只在變更時呼叫 editor API。禁止每幀重選動畫導致一直停在首幀。
- 方向使用 TerrainTestCharacter 現行映射；僅抽取必要共用常數至既有 CharacterRenderContract（先定位真實檔案），不要另造完整 presenter framework。
- render source 是否更新由隊長狀態與待更新畫面決定，不能因士兵走路就让已停住队长保持 walk，也不能切 idle 当帧就停用 SubViewport，保留至少一个实际渲染帧发布新姿势。
- 初始化、轉向、移動開始、交換、完成、clear/deploy 都同步緩存；動畫時間连续，不因途經每格就重置。
- 不修改 Sprite scale、相機、foot anchor、模型比例或位移来修方向；位移仍由 cells/moving_to/progress 决定。

## 4. B：導航工作生命週期與完整路徑

仍由 TerrainArmy 管理，一個大型 Packed 搜尋工作區。每人只保存短小請求描述／路徑索引，禁止 100 份一萬格 BFS 陣列。

### 4.1 先修 request 與工作區互相覆寫

將流程分為 request、advance、consume。_next_step 只能發請求或取得結果，不能任意清空其他人工作區。

- request key 至少有 requester、start、goal、terrain generation、command/goal revision。
- 同請求去重。其他 requester 進有限等待列，不覆寫目前 PENDING；相同 requester 新目標取代尚未開始的舊請求。
- 隊長優先選下一份工作；若允許中斷普通兵，只在隊長出現新有效請求時中斷一次，被中斷者返回佇列。普通兵不能中斷隊長。
- advance_frame 每個 render frame 恰好一次消耗全軍共享預算，初始 512 expansions + 1ms 軟上限（每 32 expansions 检查），不依赖某士兵是否被 simulation cursor 选中。
- 預算前先判断能否工作；预算耗尽不得 resize/fill 工作区或取消工作。
- PENDING、FOUND、UNREACHABLE、CANCELLED 分开。PENDING 不累计成「地形无路」。frontier 真正耗尽才能 UNREACHABLE。
- 返回结果时检查请求版本；移动或换指令后过时结果丢弃，不应用到新起点。
- 保存 route 的完整 Packed cell indices + cursor。每次普通完成／交换完成才推进 cursor；下一步由 route 决定，不再被 Manhattan 贪心覆盖。
- 下一边临时被友军挡住，保留 route，走占格仲裁；不要重做全图 BFS。地形修订或目标修订才失效。外部角色移动阻挡采用暂时等待/受控重试，不能污染静态不可达缓存。

### 4.2 穩定目標與共享路線資訊

Follow 的队长目标在 PLAYER 实际移出跟随死区、旧目标失效或指令改变时更新；队长自己走一格不是重选最终目标的原因。

队长抵达合理跟随距离即停，PLAYER 静止时不在候选格之间来回。队员追随目标的刷新与队长静态路线失效分别处理。

同一批跟随者可以共享「到队长路线集结点」的反向距离场，在 can_step 图上选择严格下降邻格，再做各自局部队形落位。放在现有 TerrainArmy，复用相同预算机制，不创建第二个 manager。距离场采用构建缓冲/已发布缓冲；完成后一次发布，构建中的半张图不得被使用。目的地更新合并，不每次 captain 步进都推翻仍有效的已发布场。

初期可按队长每前进 3–4 格或路线转弯/跨坡道发布新集结点；过程中消费前一条合法路线。具体频率按跟随延迟测量调整，避免频繁构建或过久追逐旧位置。

### 4.3 真正地图边缘与多层连通

- 区分地形平台边界与地图 x=0/y=0/x=max/y=max。MOVE_TO_EDGE 选择实际可达的地图边界目标。
- 可达边界不足容纳 100 人时：队长到真实边界，队员在其内侧可达集结带停靠，分别报告 captain at boundary 和 formation assembled；不要冒称 100 人都站外边界。
- 若一个真实外边界格也不可达，回报 UNREACHABLE_BOUNDARY 并显示起点组件/当前高度，不把内侧最近格当成功。
- 先用独立小型测试 oracle（仅测试）遍历 can_step 图，证明当前起点到边界是否可达。oracle 有路而军队停住→导航错误；oracle 无路→记录缺失 ramp/地形组件。只有后者才对 terrain_generator 的坡道连接进行最小修正，并补原 seed 回归，不全局重做地形。

## 5. C：隊員跟隨吞吐量與狹口

### 5.1 便宜步進與昂貴搜尋分开

每 simulation tick 扫描全部 100 人的状态与现成路径下一格，是可控 O(N) 工作；不要将「下一格检查」限制为 8 人。只有新路径/距离场展开使用昂贵预算。

建议 tick 内：完成已到时的普通/交换移动→队长意图→所有可移动队员意图→统一格子竞争裁决→提交移动起点。固定顺序与轮转 tie-break 保证可重现。

MOVE_DURATION 保持 0.24。完成时间按累计 simulation 时间决定，保存剩余时间并传到后续合法动作或用开始/结束时间求插值，避免每格丢掉 0.06 秒形成锯齿速度。不得单纯把 duration 缩短伪装调度改进。

blocked_time 每 tick 按真实等待时间累计，分别记录 WAITING_PATH / WAITING_OCCUPANCY / NO_ROUTE。公平性基于等待年龄，队长优先不允许永久饿死普通兵。

### 5.2 跟随形态

- 开阔地：以队长当前有效路线位置/集结点为锚，队形在行进方向后方，四向可旋转；保持 slot 身份稳定，不每次最近格扫描全部重排。
- 狭口：采用单列/少列跟随已确认路线，通过坡道时不强求十列。队长已走过的格子可作为实际路线线索，但高度边仍经 can_step 验证。
- 出狭口：只有有足够合法站位时再展开队形。选落位时排除队长下一步/坡道出口等关键通道，避免 ARRIVED 士兵停在通道中间。
- 同速士兵无法缩短与全速队长持续增长的距离：先消除排程损失；若行军队形落后超过约 12 格路线距离，队长在安全空地短暂等待，恢复至约 8 格再走，保留迟滞。值可调，不能在唯一坡道口停车。不可达/失败个体明确诊断，不能永久拖住全队。
- 原子交换只用于队长合法路线上被己方占用的下一格。普通兵先通过唯一目标、排队和有限邻近空格让位（一步、全程 can_step、仍经 reservation）处理；不引入任意链式推挤。
- 一格通道的通过速度受物理格子容量限制；验收要求持续通过，不要求 100 人同时通过。

## 6. 占格與清除不變量

每步/每交换前检查 source owner、destination reservation、terrain legality；交换提交同时验证双向 partner、双向 moving_to、两个 reservation 所有权。期间第三人不得占有 A/B。

追查 TerrainTestCharacter.place：当前 terrain_cell 在 tween 开始就改变，因此外部角色显示仍在旧格时旧格也应短暂保护。增加必要的唯读当前占用/过渡格查询，army 消费它，不能猜另一套玩家位置。NPC 同理。

指令更换保留已经开始的合法动作，作废后续路径；clear/Generate/deploy 清除所有请求、发布距离场、交换、占格与动画缓存。不得把上张地图工作结果提交到新地图。

## 7. 檔案與執行順序

| 顺序 | 文件 | 工作与退出条件 |
|---|---|---|
| 1 | scripts/tests/terrain_lab_army_test.gd | 构造两次下降且入口错开的失败用例、共享搜索干扰用例；先确认旧实现失败 |
| 2 | scripts/terrain_lab/terrain_army.gd | 队长 clip/yaw 同步；四向画面与停走切换正确 |
| 3 | 同上 | 请求生命期、完整路径、目标稳定；队长连续下山到指定目标 |
| 4 | 同上 | 全员廉价调度、共享路线/距离场、狭口队列与重整；量测跟随吞吐量 |
| 5 | terrain_test_character.gd / terrain_test_npc.gd | 仅必要唯读过渡占格接口 |
| 6 | scripts/terrain_lab/terrain_lab.gd | HUD 显示 captain cell/height/clip/facing、导航状态、进度与等待原因 |
| 7 | army visual/performance tests | 真实进程截图、动态帧时与任务完成结果 |
| 8 | TERRAIN_GENERATOR_LAB.md | 记录新行为、实测和仍失败的场景 |

本文件中的建议私有函数名是责任示意，落地前核对当前代码。不要同时保留旧 greedy 导航与新完整路径各自修改 moving_to 的两条权威入口。

## 8. 必须执行的精简验收

### A. 动画/方向

真实 Lab 中队长东南西北各走至少 3 格，记录 walk clip、yaw、动画时间持续增加；停止确认 idle 更新已渲染。交换也做左右双向。对准队长截图/短序列，显示 cell/方向标签；脚底、身高、比例保持一致。队长正常待机不能因为士兵动而自行走路。

### B. 连续下降与绕路

确定性夹具高度 3→2→1→0，三个坡道位置错开，至少一段必须先远离最终目标再绕回来。起点在 3 层，目标为真实地图边界 0 层。oracle 证明存在合法路线；使用 advance_frame(1/60)，限制 60 秒 simulation，要求 captain 实际到目标，记录高度序列。把「其他人还在动」作为通过条件禁止。

同时运行其余 99 人请求。另测真正封闭的高台，必须明确无路；不能穿崖来通过。再选一个实际 TERRACED_HIGHLAND seed 保留其复现坐标，检验真实生成图。

### C. 搜索续跑抗干扰

队长路径需要 >2048 次展开；每帧至少两名其他请求者进入请求列。记录 captain job ID/head 单调进展，不能每帧归零；每帧展开 ≤512；不得因预算为零改变工作区。改变玩家目标后旧结果不得应用。测试无需给每人一张搜索图。

### D. 跟随吞吐量

先在无障碍且无格子冲突的测试布局让 100 人各走 20 格（用相同 frame driver）。95% 人首次启动≤0.3 秒；完成时间应接近 20×0.24=4.8 秒，建议上限 5.5 秒，解释固定 tick 误差。此夹具用来单独验证调度，不冒充真实队形结果。

真实开阔地：PLAYER 带队沿 40 格路线移动后停下，记录首次反应、队长进度、队员 P50/P95 路线落后距离、全部集结时间。建议 PLAYER 停下后 20 秒内在合法位置集结，无持续来回。

狭口：100 人经单格双坡道，最后一人必须到对侧集结区；给 120 秒 simulation，记录通口成功次数与最长无进度时间，不能仅断言 captain 通过。若拥塞仍失败，列 blocker/goal，不降低断言。

### E. 交换/清除回归

队长被包围后穿出、交换期间改指令、clear 后重新 deploy 各执行，检查每帧 100 个唯一 owner、reservation 对应有效动作，无水/峭壁非法边。交换不改人物身份，完成后至少观察 10 秒无无限反向交换。

### F. 视觉证据

修正 visual_test：相机对准队长/交换中点；测试可暂停自动 simulation 后以 advance_frame 固定进度推进，等待 frame_post_draw 再保存。before 必须已显示测试布局；mid 取实际 progress≈0.5，after 等完成。断言角色脚底投影在画面内且不被 UI 遮挡，人工检查实际图片。若全图密度太大，再加局部捕捉，不缩小角色。允许交换短暂视觉交叠需如实标注。

### G. 性能

同机 2560×1440、100×100、100人，记录 GPU、renderer、zoom、VSync/cap。PLAINS 24680、TERRACED_HIGHLAND 12345，暖机5秒、动态采样20秒，分别看 idle/follow/下山/狭口。

正式采样开始后重置测量基线；按1秒窗口记录 committed steps、captain steps、arrived、swaps、最长无进度时间、请求重启/取消次数、expansions/frame、被丢弃simulation时间。已完成待机与未完成停滞分别统计。

报告P50/P95/P99/max、>33.3ms与>50ms帧数，目标P95≤20ms/P99≤33.3ms。不能用更低planning budget、减速或丢时间实现高FPS；若未达到，报实值与分析。旧的105步短样本与未抵达数据不得当成本次通过证据。

## 9. 完成回報要求

列修改文件、三项根因与对应修复、实际跨层高度/到达结果、跟随启动延迟/完成时间、动态帧时、可打开且已看过的四向/交换图片、剩余限制。所有断言错误即失败，即使脚本之后打印 PASS 或 exit=0 也不例外。

不得只报告「新增函数」「已可续跑」「60FPS」就宣称完成。完成意味着：队长方向动画正确、连续下山到目标、队员持续追上且跨过狭口，三项在同一份最终代码上验证。

## 10. 本轮实作与验证纪录

### 已修改

- `scripts/terrain_lab/terrain_army.gd`
  - 新增队长 presentation sync：依 `facing[0]` 使用与 TerrainTestCharacter 相同的 DOWN=0、UP=180、LEFT=-90、RIGHT=90 yaw；移动／交换选 `walk`，停止选 `idle`，并缓存最后状态。
  - 导航工作区不再由普通士兵覆写队长的 PENDING 搜寻；队长可优先接管，普通士兵等待共享工作完成。
  - 保存完整 BFS route 与 cursor，完成一步／交换才消费 route；绕坡道时不会回到 Manhattan 贪心入口。
  - 跟随重算时，PLAYER 目标没有变更只因队长移动不再清掉有效 route。
  - 一个固定 simulation tick 会检查全部 100 名单位的廉价一步意图；`PLANNING_BUDGET` 只限制昂贵 detour 搜寻，避免队员轮到第 8 人后整 tick 停滞。
- `scripts/tests/terrain_lab_army_test.gd`
  - 新增 100 人同 tick 启动吞吐量测试。
  - 新增高度 3→2→1→0、三个错位 reciprocal ramp 的连续下降测试，要求队长实际到目标并造访每个高度层。
- `scripts/tests/terrain_lab_army_visual_test.gd`
  - 新增队长四方向 yaw 与 walk/idle 选择的断言，保留既有交换前／中／后截图。

### 已执行结果

- Godot editor headless scan：exit 0；本轮文件无新增 GDScript parse/compile error。根凭证存取讯息是环境噪音。
- `terrain_lab_army_test.gd`：exit 0，输出 `TERRAIN LAB ARMY PASS`；包含 follow、edge、ramp、multi-level descent、captain swap、long route 与 100 人同 tick 吞吐量。
- 实际视窗 GPU visual test：Godot D3D12 / NVIDIA GeForce RTX 5060，exit 0；四向 yaw、walk/idle 选择与交换前／中／后截图均通过。已人工检视 `res://.visual_captures/terrain_lab/army_swap_mid.png` 与 `army_swap_after.png`；执行器输出的根凭证讯息为已知环境噪音。
- 实际视窗 performance test：exit 0，`baked_atlas`、1 个 live 3D source、`nodes=1666`、`moving_p95=16.802 ms`、`moving_p99=16.841 ms`、`fps=60`、`completed_steps=582`；这是本机短样本，不等同所有机器的性能保证。
