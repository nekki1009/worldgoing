# 萬人同屏：其他遊戲怎麼做，worldgoing 差在哪

研究日期：2026-09-29。範圍：公開的開發者一手資料＋worldgoing 現行程式與既有量測（`scripts/terrain_lab/`、`native/army_idle/`、`SITE_CROWD_*`、第三版效能計畫）。本輪沒有改程式、沒有新跑分；所有 FPS／毫秒都是既有紀錄，而且是編輯器執行檔的數字。

## 一句話結論

**差距不在某一段程式慢，而在「模擬的單位」。** 能做到萬人的遊戲，都讓「每名士兵每步的成本」壓到約 1 µs 左右：決策以整隊為單位，士兵只在連續空間裡追自己的位置再互相推開，資料是連續陣列、分到多核或 GPU。worldgoing 目前是讓每名士兵每 1/30 秒各自提案、在離散格子上做全域仲裁與原子提交，成本約 **84 µs／人／步**，差了約 **70 倍**。而且驗收規則要求新版跟舊版行為逐位元相同，只能把同一套演算法加速，沒辦法換掉它，所以十八個效能階段每次只多 1–16%。

9/26 那份研究（`SITE_CROWD_ARCHITECTURE_RESEARCH_20260926.md`）已經指出資料流的問題：Dictionary 逐列查詢、呈現每輪重建。本文同意，但要再往前一步：**只要保留現行的移動語意（一人一格、每步全域仲裁、每人路徑與目的地規劃），不管資料怎麼搬，都到不了萬人。**

---

## 1. 先把數字對齊

| 項目 | worldgoing 現況 | 萬人 @30 FPS 需要的量級 | 差距 |
|---|---|---|---|
| 常態模擬步（正式 300 人，MOVE） | 25.2 ms／步 → **約 84 µs／人／步** | 模擬分到約 12 ms 的話 → **約 1.2 µs／人／步** | 約 70× |
| 整體（正式 300 人） | 24.6 FPS、p95 62.7 ms、action/wall 0.81 | 30 FPS、p95 ≤33 ms | 300 人都還沒過 |
| 5k 測例（ATTACK，大多原地交戰） | 末 10 秒 28.0 FPS、p95 42.9 ms | — | 靜態為主的情況也沒過 |
| 5k 普通兵顯示 CPU | prepare_rows 5.6＋render_submit 7.7 ms ≈ **13 ms／幀**（≈2.7 µs／人） | 靜止的兵應接近 0 | 10k 時光顯示就約 27 ms |
| 規模契約 | 正式存檔最多 3 隊／300 NPC，單隊上限 200；5k 沒有合法的整軍 MOVE | 1 萬人要能下令移動 | 資料契約本身就還不支援 |

說明：84 µs 是 25.2 ÷ 300 的平均，裡面混了規劃、仲裁、提交，不是單一函式的成本。release 匯出可能比編輯器快一些，但幅度不會是幾十倍。就算把整個 33 ms 幀都給模擬，每人也只有 3.3 µs，仍差約 25 倍。

---

## 2. 其他遊戲怎麼做（依手法分類）

### A. 決策以「隊」為單位，士兵只負責跟上

- **Supreme Commander 2（Flow Field Tiles）**：原本逐單位 A* 一碰撞就重算路徑，「會讓遊戲停擺」；改成把地圖切成 10×10 的 sector，先在 portal 圖上做高層 A*，再產生**所有單位共用**的 flow field，同一條走廊的單位共用快取。[Game AI Pro 第 23 章](https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter23_Crowd_Pathfinding_and_Steering_Using_Flow_Field_Tiles.pdf)
- **Songs of Syx**（獨立開發者、自製引擎）：戰場最多 96 個 division × 每隊 150 人，約 14,400 名士兵。[開發日誌](https://songsofsyx.itch.io/songs-of-syx/devlog/129935/battles-and-kickstarter)
- **Total War 系列**：玩家與戰術 AI 的指令對象是整個 unit；戰術層（最早的 Shogun 約有 220 條規則）負責隊形與戰術，個別士兵是反應式的底層行為。[Game Developer: The AI of Total War](https://www.gamedeveloper.com/programming/the-road-to-war-the-ai-of-total-war-part-1-)
- **Continuum Crowds**：以「群組」為單位維護密度／速度場，再用 Eikonal 填出流場，成本隨群組數而不是人數成長。[How to RTS 整理](https://howtorts.github.io/2014/01/09/continuum-crowds.html)

共通點：**昂貴的搜尋每隊做一次（或全體共用），不是每人做一次。**

### B. 連續空間＋局部避讓，不做每步的全域仲裁

- SupCom2 的單位可以互相推擠、貼牆滑動，爆炸也能把單位推開；碰撞靠物理和 steering 處理，不重新規劃路徑。（同上 Game AI Pro）
- 現代 RTS 的做法：高層用 navmesh／HPA*＋flowfield，近距離用 boids 式的 separation／avoidance。原因是「在大量動態障礙的環境，不斷發新的路徑請求並不實際」。其中單一 50×50 tile 的 flowfield 約 0.3 ms。[jdxdev RTS Pathfinding 系列](https://www.jdxdev.com/blog/author/jdtec/)
- **UEBS2**：每個角色都有自己的 HP、位置、敵人、決策與數百種動畫，「AI、transform、動畫、剔除、繪製全部在 GPU 上跑，CPU 只負責播放本地音效」。[開發者說明](https://steamcommunity.com/app/1468720/discussions/0/3110267314129208740/)

共通點：**允許短暫重疊或推擠，衝突靠局部力量慢慢化解，所以每名士兵可以各自獨立計算**，能平行，也能上 GPU。

### C. 資料導向＋多核

- **Bannerlord**：資料導向設計，每幀 60–70% 可完全平行；當時的目標是 800 人 60 FPS。[TaleWorlds 技術部落格](https://www.taleworlds.com/en/Games/Bannerlord/Blog/25)
- **Total War: Warhammer II**：改用多核，「戰鬥邏輯與動畫管線跟顯示解耦」，可以跨多個顯示幀預先算出未來狀態；另外靠動態 LOD 降 GPU 負載。[Game Developer 訪談](https://www.gamedeveloper.com/design/designing-i-total-war-warhammer-ii-i-to-handle-tons-of-units-and-massive-battles)
- **Ashes of the Singularity**：把工作切成小 job 分到所有核心，排程時考慮快取區域性。[VentureBeat](https://venturebeat.com/2017/05/18/why-threading-matters-for-ashes-of-the-singularity/)
- **They Are Billions**：AI、物理、繪圖、聲音非同步執行，約 2 萬單位；開發者估計如果要確定性、只能單執行緒，會掉到 3–4 千。[官方 FAQ](https://steamcommunity.com/app/644930/discussions/0/1692659135919671514/)
- **Factorio**：確定性仍然可以平行，前提是先切出真正互不影響的群組，平行階段只收集請求，之後依固定順序提交。（見 9/26 研究引用的 FFF #364）

### D. 模擬頻率與顯示分開

- **Age of Empires**：同步模擬、每個通訊 turn 約 200 ms，指令排在兩個 turn 之後執行；顯示幀與模擬步分開。[1500 Archers on a 28.8](https://www.gamedeveloper.com/programming/1500-archers-on-a-28-8-network-programming-in-age-of-empires-and-beyond)
- Total War 讓邏輯跑在顯示前面（見上）。Epic City Sample 把「模擬人數」「可見人數」「完整骨架人數」分開計算。（見 9/26 研究）

### E. 呈現：實例化＋GPU 動畫＋LOD

- NVIDIA GPU Gems 3 的群眾渲染：動畫存成貼圖，由 GPU instancing 在 shader 裡取樣。[GPU Gems 3 第 2 章](https://developer.nvidia.com/gpugems/gpugems3/part-i-geometry/chapter-2-animated-crowd-rendering)
- Godot 本身：場景樹「處理每幀要跑的數萬個實例可能成為瓶頸」，這時應直接用 Server API；Server API 大多是 thread-safe，場景樹不是。[Using servers](https://github.com/godotengine/godot-docs/blob/master/tutorials/performance/using_servers.rst)、[Thread-safe APIs](https://github.com/godotengine/godot-docs/blob/master/tutorials/performance/thread_safe_apis.rst)
- Godot 4 社群範例用 RenderingDevice compute 做 boids，約 4 萬隻時開始變慢。[godot-boids](https://github.com/DevPoodle/godot-boids/)

---

## 3. worldgoing 差在哪（依影響大小排序）

### 差距 1：移動模型是「每人、每步、離散格、全域仲裁」 — 最根本

**業界**：連續位置＋局部避讓，衝突在局部慢慢化解，每人可以各自獨立計算。

**worldgoing**：`SiteCombatMovementCoordinator.combat_logic_tick` 每 1/30 秒依序執行：
重建全場占格 `_rebuild_occupancy()` → `SiteMovementReservationGrid.begin_tick()` 把占格 Dictionary **整份 `duplicate()` 兩次** → 各隊 prepare → 每人 `propose_move()` 產生一個 `MoveProposal` 物件 → `resolve_all()`（同格競爭、六鍵排序、反互換、依賴、長循環拒絕）→ `commit_all()` 原子提交 → finalize。

這是一個**帶順序依賴的全域約束問題**：一個人能不能走，取決於別人這一步有沒有讓出位置。所以它：
- 很難平行（Factorio 的做法要先切出互不影響的群組，但兩軍接觸時正好互相依賴）；
- 很難上 GPU（UEBS2 能上 GPU，是因為它不需要全域原子提交）；
- 成本跟「有多少人在動」成正比，還會再乘上仲裁和提交的常數。

### 差距 2：決策粒度是「每名士兵」

**業界**：一隊一條路徑或共用 flow field，士兵只追自己的隊形槽位。

**worldgoing**：每人有自己的 route cache 和 A*（`_refresh_member_route_caches`）、transit 槽位指派、目的地平台排隊（60＋40）、租約、vacancy-chain、recovery。第三版計畫把隊形決策降到 10 Hz，這是對的方向，但降的只是「決策頻率」，每次決策仍然是逐人算。發令尖峰（macro path 12–39 ms、deployment 11–18 ms）也來自這一層。

### 差距 3：資料是 `Array[Dictionary]`＋巨型 GDScript

**業界**：SoA／ECS 連續陣列，放在原生程式裡。

**worldgoing**：
- 士兵是 `combat_units: Array[Dictionary]`，`terrain_army.gd` 有 14,639 行，出現 487 次 `Dictionary`、77 次 `.duplicate(`，全名冊迴圈至少 45 處（粗略 grep）。
- `native/army_idle` 的 README 自己寫明：「不是新的模擬或 ECS」。它是借用原本的 Dictionary 列，經 Variant 讀欄位，遇到例外再回 GDScript。某次 60 秒量測有 876,092 次 native 呼叫、1,617 萬列。
- Godot 官方文件：GDScript「易用性比效能重要」，C++「通常最快」，也建議記憶體要線性存取。[CPU optimization](https://github.com/godotengine/godot-docs/blob/master/tutorials/performance/cpu_optimization.rst)

### 差距 4：全部在主執行緒同步執行

**業界**：Bannerlord 60–70% 平行；TW 讓邏輯與顯示解耦；Ashes 用 job 分配到所有核心。

**worldgoing**：`terrain_lab.gd` 在 `_process` 裡用 `while` 迴圈跑完每個 1/30 秒的 action step，`scripts/terrain_lab/` 裡找不到 `WorkerThreadPool` 或 `Thread`。第三版的 P3 是「單一寫者 → 單一 worker」，**只是把負載移出主執行緒，最多用到一顆核心**，300 人會有幫助，但對萬人不是倍數等級的解法。

### 差距 5：驗收規則把演算法凍結了

**業界**：換掉演算法本身。SupCom2 用 flow field 取代逐單位 A*；Factorio 改變輸送帶的資料表示。

**worldgoing**：大多數項目要求跟舊版在 451 個狀態上**逐位元相同**（使用者已經同意，只有刻意改頻率的項目改用行為等價）。在這個規則下，唯一合法的最佳化就是「用更快的方式執行同一套演算法」。結果就是這樣：

- 5k 從第 15 到第 18 階段：17.3 → 21.5 FPS，每階段 +1.4% 到 +16%；
- 300 人的 MOVE 經過 r2／r3 兩輪 native 化，coordinator 從 41.9 降到 22.5 ms，仍是 24 FPS。

如果目標是萬人，**需要被重新定義的是「正確」**：改成遊戲規則層級的斷言（不穿牆、不重疊超過容許值、會到位、會接敵、存讀一致），不再要求跟舊實作逐位元相同。

### 差距 6：呈現仍由 CPU 逐人逐幀算動畫與排序

**業界**：shader 用（clip、開始時間）自己算出幀，CPU 只在狀態改變時寫資料；遮擋交給深度緩衝。

**worldgoing**：批次 shader 從 `INSTANCE_CUSTOM.y` 讀取 CPU 算好的 frame；BatchView 每輪 `begin → prepare_idle → 分地面列 → 組 run → pack／flush`，每個地面列一個 `MultiMeshInstance2D`、用 `z_index = row` 保持透明遮擋順序。2D 精靈圖集這條路線本身是對的（跟 They Are Billions 同類），問題是**上游每幀逐人重算**。有一個值得評估的選項：士兵改畫在正交 3D 視角的 quad 上，用 alpha scissor＋深度排序，就不需要 CPU 逐列排序；代價是半透明邊緣要改用 alpha-to-coverage，也要重新驗證畫面。

### 差距 7：規模契約只到 300

正式存檔最多 300 NPC、單隊 200；5k 只是 ATTACK 測例，還沒有「合法的 5k 整軍 MOVE」。要萬人，隊伍數、槽位、存檔格式、UI 都要先支援，這一點跟效能無關。

---

## 4. 哪些不是主因

- **Godot 本身**：MultiMesh／RenderingServer 畫一萬個精靈不成問題；社群的 compute boids 在 Godot 4 跑到幾萬隻。瓶頸在你怎麼使用引擎（GDScript＋Dictionary＋主執行緒），不在引擎的渲染能力。換引擎也不會自動解決差距 1、2、5。
- **2D 圖集路線**：方向正確，而且比每人一個 3D 骨架便宜得多。
- **隊長 live 3D**：只有少數幾人，屬於 Near LOD，算是合理的「完整骨架人數」預算；300 人規模下值得收斂，但不是萬人的主因。
- **GPU**：目前沒有證據顯示 GPU 是瓶頸，未歸屬的餘額不能直接算給 GPU。

---

## 5. 如果萬人真的是目標，架構應該長這樣

| 層 | 頻率 | 單位 | 內容 | 預算（10k） |
|---|---|---|---|---|
| 戰術／隊形 | 2–10 Hz＋事件 | 每隊（約 100 隊） | 高層路徑（粗格 HPA* 或共用 flow field）、隊形槽位、接敵決策 | ≤2 ms，可分攤到多幀 |
| 士兵局部移動 | 30 Hz | 每人，互相獨立 | 追槽位＋separation（空間雜湊）＋地形高度／可走性查表；C++ SoA，WorkerThreadPool 分塊平行（之後可再考慮 compute） | ≤8 ms（約 0.8 µs／人，4–8 核） |
| 占格／接觸 | 10 Hz | 空間雜湊格 | 只用來判定誰跟誰相鄰、誰能交鋒；不再每步原子提交單人格位 | ≤2 ms |
| 戰鬥結算 | 10 Hz（現行已是） | 交鋒對 | 依固定順序提交 HP／KO，保持確定性 | ≤2 ms |
| 呈現 | 每幀 | 每人 | GPU 自行算動畫幀；CPU 只寫有變化的列（位置用 buffer 直寫） | 靜止的兵約 0 |
| Near LOD | 每幀 | ≤數十人 | live 3D 隊長／特寫 | 固定上限 |

確定性可以保留（用 Factorio 的方式：平行階段只讀、只收集請求，最後依固定順序提交），但「跟舊實作逐位元相同」不能保留。

---

## 6. 建議的下一步

1. **先確認產品目標。** 如果正式玩法只需要 300 人流暢，第三版計畫是對的路，繼續做就好。如果萬人是真正的目標，第三版做完也不會通往萬人（尤其 P3 是單一 worker），兩條路需要分開規劃。
2. **萬人路線先做一個有時限的原型（約 2 週）**，不動正式入口：
   - 在 `native/army_idle` 旁邊另寫一個 C++ SoA 的局部移動核心：10,000 人、20 隊、槽位追隨＋separation＋地形查表，接到現有 2D 圖集的 MultiMesh；
   - 量「每人每步 µs」與「10k 時的完整幀時間」（release 匯出、無探針）；
   - **通過標準**：單核 ≤3 µs／人／步、多核 ≤1 µs，10k 時 p95 ≤33 ms。達不到就停下來，保存數據。
3. **原型通過後，才談遷移。** 重新定義移動的驗收規則（規則層級斷言取代逐位元 oracle），再把正式的 MOVE 換上新核心；平台排隊、租約這些語意，改成隊形層的規則，不再是每人每步的格位交易。

---

## 來源

外部：
- [Game AI Pro Ch.23 — Crowd Pathfinding and Steering Using Flow Field Tiles（Supreme Commander 2）](https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter23_Crowd_Pathfinding_and_Steering_Using_Flow_Field_Tiles.pdf)
- [UEBS2 開發者說明](https://steamcommunity.com/app/1468720/discussions/0/3110267314129208740/)
- [Designing Total War: Warhammer II to handle tons of units](https://www.gamedeveloper.com/design/designing-i-total-war-warhammer-ii-i-to-handle-tons-of-units-and-massive-battles)
- [The Road To War — The AI of Total War](https://www.gamedeveloper.com/programming/the-road-to-war-the-ai-of-total-war-part-1-)
- [TaleWorlds Bannerlord 技術部落格](https://www.taleworlds.com/en/Games/Bannerlord/Blog/25)
- [Why threading matters for Ashes of the Singularity](https://venturebeat.com/2017/05/18/why-threading-matters-for-ashes-of-the-singularity/)
- [They Are Billions 官方 FAQ](https://steamcommunity.com/app/644930/discussions/0/1692659135919671514/)
- [1500 Archers on a 28.8（Age of Empires）](https://www.gamedeveloper.com/programming/1500-archers-on-a-28-8-network-programming-in-age-of-empires-and-beyond)
- [Songs of Syx 開發日誌：Battles](https://songsofsyx.itch.io/songs-of-syx/devlog/129935/battles-and-kickstarter)
- [jdxdev RTS Pathfinding 系列](https://www.jdxdev.com/blog/author/jdtec/)
- [How to RTS: Continuum Crowds](https://howtorts.github.io/2014/01/09/continuum-crowds.html)
- [GPU Gems 3 Ch.2 — Animated Crowd Rendering](https://developer.nvidia.com/gpugems/gpugems3/part-i-geometry/chapter-2-animated-crowd-rendering)
- Godot 官方文件：[Using servers](https://github.com/godotengine/godot-docs/blob/master/tutorials/performance/using_servers.rst)、[CPU optimization](https://github.com/godotengine/godot-docs/blob/master/tutorials/performance/cpu_optimization.rst)、[Thread-safe APIs](https://github.com/godotengine/godot-docs/blob/master/tutorials/performance/thread_safe_apis.rst)
- [godot-boids（Godot 4 compute）](https://github.com/DevPoodle/godot-boids/)

專案內：`scripts/terrain_lab/site_combat_movement_coordinator.gd`（combat_logic_tick、_rebuild_occupancy）、`site_movement_reservation_grid.gd`（begin_tick／resolve_all）、`terrain_army.gd`（combat_units、prepare_combat_movement_tick、advance_frame）、`terrain_army_batch_view.gd`、`terrain_lab.gd:_advance_action_time`、`native/army_idle/README.md`、`PROJECT_ARCHITECTURE.md`（第 15–18 階段）、`SITE_CROWD_GPU_OPTIMIZATION_PLAN_SOL.md`、`SITE_CROWD_ARCHITECTURE_RESEARCH_20260926.md`、專案文件 `claude/perf-optimization-plan-v2.md`。
