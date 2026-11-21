# Worldgoing 大規模戰場架構研究與重規劃依據

研究日期：2026-09-26。範圍：開發者一手資料、目前正式入口與既有失敗證據；本輪沒有修改遊戲程式、場景、DLL、資產，沒有重新啟動效能測試。下列改造是研究建議，未實作，也不代表正式 5,000 人已 close。

後續使用者要求核實「是否早已規劃卻未解決」，已逐項比對舊計畫與封存候選：三個方向確實都曾提出。有限欄位、caller／別名改約、有序副作用及同源機制前置檢查，現已收斂到 [唯一施工計畫](SITE_CROWD_GPU_OPTIMIZATION_PLAN_SOL.md)；本研究保留作依據，不作另一份並行施工指示。

## 1. 結論與前面思路的修正

**反覆失敗的問題，在於把最佳化單位切得太小：一直保留「逐人查詢通用資料 → 推進欄位 → 再讀一次生成呈現 → 重組批次」的整體流程，只加快其中一小段。** C++、MultiMesh、GPU writer 都已存在，卻沒有使這條資料流消失。

不能說前面完全沒想到常駐資料或事件更新：舊 B 計畫已允許內部熱狀態不維持每 tick 的原始 Dictionary bytes；age／think 常駐切片也真的做過。問題是兩欄遷移沒有涵蓋其餘相依熱欄，其餘字典掃描與顯示生成還在。現行 R 計畫也早已要求完整 writer 通知、動畫精度及上游免重算；被拒收的保留批次實作卻仍在生成資料後比較。**這同時是切片範圍不足，以及實作沒有達成已寫明前提的問題。** 再次加一個快取、再搬兩個欄位，不構成新的架構方案。

O(N) 本身也不是錯：百萬個 GPU 工作項目仍要處理百萬份資料。應消除的是每人多次通用查詢、資料轉換、配置和同步；必要的連續數值運算可以保留。不能把所有相位不同、持續動畫中的人也承諾成 O(變更人數)。

其他遊戲提供兩類實證方向：

1. UEBS2 把個體模擬及呈現留在 GPU，避免 CPU 成為每人資料的必經站。
2. Factorio、Bannerlord、Unity 的資料導向案例，重新安排 CPU 權威資料、更新集合及批次邊界，使每次工作少讀無關資料、少跨介面、少重新建立結構。

**對目前正式 2D TerrainLab 的 5,000 人，建議先採第二類：在既有 owner 內完成一段連續資料的遷移，讓呈現直接消費它的變更。** 這是依現況成本與相容邊界作出的工程判斷，還不是新效能實證。GPU 全模擬可以另立長期方案；只搬最後的 MultiMesh buffer 寫入，已經有反例，不應再當主方向。

## 2. 實際參考了哪些遊戲

### UEBS2：值得學的是整條資料路徑

Brilliant Game Studios 在 2021 年明確說明 AI、Transform、動畫、剔除與繪製在 GPU 上，也說每人保有 HP、位置、敵人、決策和骨架動畫。不能把 UEBS2 說成只是沒有個體邏輯的假群眾。官方商店宣稱百萬級可見角色；上述來源沒有提供可跨遊戲直接比較的固定硬體、AI 節拍與完整幀時間方法。[開發者說明](https://steamcommunity.com/app/1468720/discussions/0/3110267314129208740/)、[官方商店](https://store.steampowered.com/app/1468720/Ultimate_Epic_Battle_Simulator_2/)

對本案的推論：CPU 若仍在每一步讀取、修改每名普通兵的狀態，再逐人生成繪圖輸入，就沒有完成這種架構。要照 UEBS2 做，鄰居查詢、格位衝突、生命結算與呈現之間的高頻資料必須能留在 GPU；CPU 只在明定的命令、查詢、保存邊界接觸結果。Worldgoing 現有逐步占格與直接字典回呼需要先重新界定，不能靠一個 compute pass 達成。

原始說明中的兩項要更正：

- 每人 64 bytes 只是示意，沒有查到 UEBS2 開發者公開該結構；不能用它估算本遊戲總顯存。64 bytes × 100 萬 = 64 MB 是單一資料區的容量算術，並非完整模擬成本。
- 百萬 GPU threads 是百萬個邏輯工作項目，硬體以有限駐留區塊分批排程，並非百萬工作在同一瞬間全部執行。[NVIDIA 排程文件](https://docs.nvidia.com/cuda/cuda-programming-guide/02-basics/writing-cuda-kernels.html#kernel-launch-and-occupancy)

### Factorio：最值得移植的不是某段程式，而是減少必要工作的方式

**改資料表示。** 輸送帶物品改存相鄰距離，利用一段物品相對位置不變的性質，只改首尾間隔，避免逐件推進座標。這項方法依賴輸送帶的限制；戰場士兵能獨立移動、受擊及占格，不能直接套成一個共同位移。[FFF #176](https://www.factorio.com/blog/post/fff-176)

**集中高頻資料。** 流體資料由散落於各種實體內，改為依連通系統集中於連續記憶體；不再為了內部管線迫使整個實體每 tick 更新，獨立系統才進一步並行。官方量到的是管線更新局部約 3–6.5 倍，不是整場遊戲或戰鬥的倍數。[FFF #271](https://www.factorio.com/blog/post/fff-271)

**真正停止無事可做的更新。** 無工作 roboport 休眠，有需求才喚醒；官方存檔的該段成本由約 1 降至 0.025 ms/tick。機器人的移動意圖與延後更新則涉及實體位置更新頻率，不能直接套入本案的 30 Hz 逐步占格。同篇也記錄電網並行失敗：記憶體吞吐量成為限制，加執行緒沒有讓整個存檔變快。[FFF #421](https://www.factorio.com/blog/post/fff-421)

**確定性不等於禁止多執行緒。** 輸送帶先找出真正無互動的群組，平行工作只收集喚醒請求，之後按固定群組次序處理。Worldgoing 兩支軍隊會互相攻擊、共用占格依賴，不能只用 team_id 分執行緒，就假設相互獨立。[FFF #364](https://www.factorio.com/blog/post/fff-364)

本案可移植的核心：保留人物獨立性，但讓無變化資料不被不相干的系統反覆讀取；把「哪些人要做哪類工作」由狀態變更處維護，而不是每次全軍重新判斷。

### Bannerlord：個人 AI 與資料導向可以並存，但要公平看規模

TaleWorlds 在 2017 年說明其 CPU 採資料導向設計，支援個人／隊形 AI、動畫及戰鬥計算；當時 800 人／60 FPS 是目標。2021 年官方另報告 GTX 1660 Ti／i7-8700K 的 1,000 人內部戰鬥平均約由 27–30 提高至 47–50 FPS。不能把該整體收益單獨歸給某一技術，也不是百萬高精度戰鬥的證明。[2017 技術說明](https://www.taleworlds.com/en/Games/Bannerlord/Blog/25)、[2021 實測說明](https://www.taleworlds.com/en/News/446)

本案啟示：CPU 個人戰鬥本身不是錯誤方向；資料配置與工作分工才需要檢討。不能只因其他遊戲人多，就推論每種玩法應有相同人數上限。

### They Are Billions：兩萬單位有明確架構取捨

Numantian 官方 FAQ 說其自製引擎讓 AI、物理、繪圖、聲音非同步執行，處理約兩萬單位，代價是沒有確定性同步。文中「若要求確定性就只能單執行緒、約三四千單位」應視為該開發者對自身架構的估計；Factorio 的實作已說明它不是普遍定律。[官方 FAQ](https://steamcommunity.com/app/644930/discussions/0/1692659135919671514/)

本案啟示：先列明需要確定性的提交邊界，再找可並行區段。不能偷偷放棄 RNG／事件／占格次序來換效能，也不能以確定性為由，永遠保留所有逐人跨語言回呼。

### Unity Megacity 與 Unreal City Sample：參考架構，不把展示人數混為戰鬥人數

Unity 2019 年的 ECS 說明把相同組成的資料集中於區塊，讓同一操作連續處理資料；Megacity 的載入、串流、剔除、LOD、動畫採 ECS，最後接間接繪製。這支持資料配置與分階段處理，不等於全部 AI 在 GPU。[Unity 原文](https://unity.com/blog/engine-platform/on-dots-entity-component-system)

Epic 文件描述 MassEntity 管理城市中數千代理，飛行視角可見數百群眾；近處完整骨架，遠處採頂點動畫網格。因此應分別計數「模擬」「可見」「完整骨架」三種人數。Worldgoing 原本的普通兵／特殊人物分工有同類價值；正式 5,000 人測例只有原有兩名 live 隊長，不能把附件的 Near64 當成已驗證現況。[Epic City Sample](https://dev.epicgames.com/documentation/en-us/unreal-engine/city-sample-project-unreal-engine-demonstration)

## 3. 是不是 Godot 的問題

**目前證據不足以判定 Godot 是 5,000 人的硬上限，也不足以替它排除責任。** 問題應分成遊戲的資料流程，以及引擎／繪圖後端實際執行這些操作的成本。

Godot 官方 MultiMesh 文件支持大量實例、shader 動畫及原生連續 buffer 提交；它也提醒單個 MultiMesh 缺乏逐實例剔除。這是可用工具，不是百萬 AI 或特定 FPS 保證。本案已用 MultiMesh，重加一次不會解決上游成本。[MultiMesh 文件](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html)

一個直接相關的反例是 Godot 官方對《Heidi’s Legacy》的分析：少量動畫 Polygon2D 經 Viewport 呈現就很慢，追查後發現每幀重建及釋放網格。改成更新既有網格後，示例單幀約由 35 降至 13 ms。它說明小人數也可能被特定更新路徑拖垮；**尚無證據 Worldgoing 命中相同缺陷，不能套用該倍數或宣稱升級即解決。** [官方分析](https://godotengine.org/article/rendering-cpu-optimizations/)、[對應 PR](https://github.com/godotengine/godot/pull/117334)

Godot 自己也指出：通用引擎 API 不會因呼叫者改成 C++ 就自動便宜；記憶體連續性與外部原生分析器很重要，部分等待不會反映在腳本計時中。[CPU 最佳化文件](https://docs.godotengine.org/en/4.7/tutorials/performance/cpu_optimization.html)

所以本案下一次應在既有正式場景取得一次能看到主執行緒、原生函式、render thread／driver 等待的呼叫堆疊，回答「查字典、配置、同步或繪製哪個佔用慢幀」。不把未歸因餘額命名為 GPU；不先搬引擎、不先買工具，也不把切換 Vulkan／Release 當原 A/B 過關。

## 4. Worldgoing 真正仍在做什麼

本輪核對 `project.godot:15`：正式入口仍是 `res://scenes/terrain_lab/TerrainLab.tscn`。依 `PROJECT_ARCHITECTURE.md`，地圖為 Node2D／Camera2D，特殊人物以 3D SubViewport 投影。附件的「3D 戰場、10,000+64、25–30 ms」不能代替這個入口的實際架構或量測。

目前關鍵控制流：

```text
TerrainLab 的動作步
  → TerrainArmy.prepare_combat
      → 軍令／接敵更新
      → C++ 掃 Dictionary 前綴
      → 遇例外回 GDScript，完成後再續掃
      → 全軍 visual dirty
  → TerrainArmy.advance_frame
      → BatchView.begin 清本輪資料
      → prepare_idle 再讀每人資料，產生七個呈現欄位
      → 例外人物／live 隊長
      → 分地面列、保持透明遮擋次序、組 run
      → pack 或 GPU writer
      → MultiMesh 提交
```

程式依據：

- `scripts/terrain_lab/terrain_army.gd:4969` 的 `prepare_combat`；`:4993` 附近前綴／例外次序；`:5098` 全軍 dirty；`:12654` 的 `advance_frame`。
- `native/army_idle/army_idle.cpp:112` 的 `field` 經 has／字典查找；`:117` 的 `ReadField` 經 Variant 取得欄位；`:159` 的 `advance` 逐列判斷型別、姿態、生命、移動、timer。這是 native 程式讀通用資料，不是 native 連續權威陣列。
- `scripts/terrain_lab/terrain_army_batch_view.gd:119` 的 `begin`，`:143` 的 `prepare_idle`，`:291` 的 `flush`。shader 的 frame 仍取自 CPU 提供的 INSTANCE_CUSTOM；站位不動也不等於動畫 frame 不變。
- `scripts/terrain_lab/site_person_actions.gd:756` 起把原人物列放入 person.body，`:823` 起直接讀寫；`scripts/terrain_lab/site_controller.gd:3728` 起仍直接寫人物狀態。遷移前必須找齊所有 caller；不能留下可任意寫入而不被新儲存觀察到的別名。保存則經 `TerrainArmy.capture_combat_state():5292` 產生原 schema，保存相容不等於內部儲存必須同址。

本輪核對產品 SHA-256：Army `79D735933968E9BF31176E3CA7E2F64324C192B7BBE162D22B546C116303184E`；BatchView `50E02657218B8E6F920AA12FD2C01A94F7072C8A70610FC448C9E3F4155C3353`；native C++ `EE7349F315813A5EF6498D8D306D7D09905D0DFD4C7514CFF6E77F1E394795AF`。行號僅供這份来源導航，後續施工需重新核對。

## 5. 既有數據支持什麼、不支持什麼

以下都是既有證據，本輪沒有新跑分。完整索引見 [本輪執行紀錄](output/site_army_5k_event_update_20260926/EXECUTION.md)。

- 無探針正式 A1：p95 **42.894 ms**，p99 **66.476 ms**，末 10 秒 **28.0 FPS**，未達標。[量測](output/site_army_5k_event_update_20260926/formal_A1/measurements.json)
- R＋G＋yaw：p95 **106.624 ms**；撤回 R 後 G＋yaw：p95 **37.205 ms**、p99 **47.428 ms**，仍未達 p95。R 引入逐索引比較成本，嚴重退化的更深層引擎原因尚未有完整原生 trace。[失敗 R](output/site_army_5k_event_update_20260926/formal_B1_failed/measurements.json)、[G＋yaw](output/site_army_5k_event_update_20260926/formal_G_yaw_failed/measurements.json)
- G＋yaw 晚段普通單步無審查幀：508 幀中 81 幀 >33.33 ms；平均 prepare_rows **5.648 ms**、render_submit **7.708 ms**、render_flush **1.519 ms**。軍令審查雖變快，普通幀仍會超時。[低開銷診斷](output/site_army_5k_event_update_20260926/p1_G_yaw_low_overhead/measurements.json)
- 分段診斷的早段普通幀：prepare_rows 平均 **5.636 ms**，其中 native recovery 呼叫合計 **4.821 ms**，平均約 **166 次呼叫、4,836 列／幀**。時間含資格查詢與呼叫量測開銷；不能把 4.821 ms 全當成可刪算術或已證明的 cache miss。[分段資料](output/site_army_5k_event_update_20260926/prepare_split_diagnostic/measurements.json)
- 早先 age／think 常駐的 A/B p95 中位數 **48.019 → 49.467 ms**；跳過約 58% buffer 指派的另一候選也未達標。表示「搬兩欄」及「末端少上傳」沒有帶來所需的整場收益。[歷史反例](output/site_army_5k_close_20260926/README.md)

不能把不同 run／不同階段的平均時間相加，或用兩個 p95 相減就承諾剩下幾毫秒一定可補。未知時間也不能算成 GPU。這些資料已足夠否決再做相同小修；仍不足以保證下面的遷移達到 30 FPS。

## 6. 建議的新施工單位：一段完整資料生命週期

### 6.1 先改介面約定，再改儲存

沿用 TerrainArmy／SiteRuntime 等現有權責。只把一組高頻欄位的實體儲存移入其 owner 持有的型別化連續區；原共用 ArmyIdleKernel 保持無每軍可變狀態，不能把不同軍隊混在 singleton 中。

施工前要產出一份有限的欄位清單，對每欄列出所有讀者、寫者、回呼時點、保存格式與精度。首個完整切片應涵蓋 `prepare_combat` 普通兵進度／恢復所依賴的熱欄，以及動畫投影的消費端，而不再只選 age／think。格位與 move_progress 已有原陣列可用，先重用；人物 ID、物品、保存及占格仍留在原 owner。

每個被遷移欄位在運行時只能有一個可寫來源。原字典可以保留未遷移的冷資料；被遷移欄位的對外讀取改走 owner 查詢，保存時才展開成相容格式。不得每步全量 Dictionary → packed → Dictionary 往返，或在兩份可寫生命／時間之間做永久同步。

公開別名是需要修正的實際 API，不是不可遷移的定律。先明訂所選欄位不再允許未受控的原字典寫入，盤點並改完現行 caller，改由 owner 查詢／命令處理。外部可以跨回呼持有 raw Dictionary 並在任意時刻修改，單靠 dirty 標記或當列回寫攔不住；沒有完成這項介面改約的路徑，不能宣稱 packed 是唯一權威。

受控展開／回寫僅適用可界定生命週期及影響範圍的借用。回呼可能改其他列，不能只回寫當前列；未受控長期別名仍存在時，相應 owner 維持原儲存路徑，不能只在回呼當步回退。若正式場景頻繁走兼容邊界，該切片不算完成。不能略過回呼來湊效能。

### 6.2 第一步仍保留原時間與提交次序

先用 native 連續資料執行原 30 Hz 算式，包含 double 精度、clamp 與原更新次序。即使暫時仍遍歷 N 個數值，也先消除通用查欄與反覆跨介面；不要同時改成 deadline、降頻或並行結算。

例外會改寫後續人物或命令，所以原本的前綴／例外順序有理由。新 API 應讓 canonical 工作能在同一 native 批次內維持這個順序；尚未遷移的副作用仍在明確邊界由原 owner 提交。只有相依鏈真的被移入同一區段，才可能降低約 166 次回呼；不能僅把同樣的 prefix 呼叫包進另一層。

### 6.3 接著讓變更直接到達呈現端

每個動作步提交時，依現有狀態變更收集受影響的原人物索引，去重並保持必要次序。只分本 renderer 需要的種類：位置／排序、外觀／圖集、動畫片段／相位、可見性／presenter。用簡單 bitset 或既有 packed index 陣列即可；名冊重排／restore 時讓舊索引失效並按穩定 person_id 重建，不建立通用事件框架。

動畫時鐘前進本身也是更新來源。沒有 gameplay 寫入的 idle 兵，仍可能跨 frame 邊界並改變 anchor；未證明可免採樣的動畫持續放在原精度的 native 採樣集合，不能只靠外部 mutation 才更新它。

BatchView 保留可重建的呈現狀態與既有批次。只有跨地面列、同列相對次序改變、圖集頁更換、Sprite 例外插入等真正結構事件才重建受影響 runs。2D 透明遮擋順序、原 atlas anchor 與染色不能被粗略空間分塊破壞；不能把所有同材質角色跨列混成一批。

驗證重點是**上游不再重算**：沒有相應變更的單位不重新查外觀、不重新投影站位、不重新分組。只在最後比較 buffer 是否相等，仍判定沒有完成。

### 6.4 保留待機動畫，但使它不迫使站位與批次重建

呈現需要保留「clip、方向、相位、播放規則」，而非每幀重建整個人物的顯示描述。先沿原烘焙資產與取樣器；現有 shader 的 sequence_data 已能依 frame 查圖集矩形，但尚未證明足以重現原 double 採樣與 anchor。能否直接沿用或需要增補呈現資料，另以動畫邊界及完整 RGBA 驗證，不預先承諾零資產變更，也不新增每兵骨架。

但不能直接用 GPU TIME 減開始時間就宣稱等价。原 CPU repeated double 加法、動畫 frame 分界、anchor、暫停、時間倍率與長時間循環，都可能產生不同像素。先保留原精度的 native 動畫取樣，把「frame／anchor 變更」與「站位／排序重建」拆開；GPU 相位推導只在另行證明原取樣邊界與完整畫面等價後採用。不取消待機動畫。

### 6.5 事件休眠及平行化是有條件的後續工作

只有已證明没有待執行副作用的狀態，才能退出某類更新集合。冷卻到期、命令、受擊、救助、死亡、換裝、玩家接管、名冊變更都必須能喚醒對應工作。處於 idle 不等於所有 timer／作業皆無事可做。

不能用一個截止時間直接替代舊 repeated subtraction，卻仍要求所有中間浮點值逐位相同。先保留連續數值計算；若未來要改時間表示，必須單列語意改變及驗收，而不是隱藏在最佳化中。已為零且保持為零的工作可在完整寫者約定後停做，但不能只用零 timer 小修當本輪成果。

同理，純查詢或無互動區段才適合並行；共享 RNG、占格與傷害提交先留固定順序。不要一開始加入新 ECS 套件、自製排程器或整套 GPU 戰鬥權威。

## 7. 給 SOL 的具體交付與驗收順序

1. **接線圖及欄位邊界。** 重用本次程式索引，補齊首個切片全部讀寫者；標出直接 body 別名及自訂回呼。指出哪些資料讀取、配置及原生往返會被刪除。若計畫完成後仍需每 tick 全軍展開字典，先修計畫，勿動碼。
2. **一份原生全幀堆疊。** 重用真 TerrainLab 5,000 人 fixture，只回答普通幀與軍令幀中的 native／render 等待归因。沒有工具或 symbols 時明列未知，不用新增大量逐人探針取代。若主因與上述切片不符，依堆疊改選題，保留這份研究的未證實標記。
3. **同一 owner 的完整切片。** 儲存、canonical 更新、所有相關讀寫 caller、呈現消費與保存轉換一起完成。動畫及遊戲時鐘不降頻。這是同一條相依資料流，不再把 R／C 設為互斥、一次只允許末端小補丁。
4. **結構驗證先於正式跑分。** 證明被遷移欄位不再每步查 Dictionary；沒有正式全量雙向同步；無結構事件時不重建 rows/runs；回退次數與處理列數可觀察。這些是必要機制證據，仍不是效能 PASS。
5. **行為及呈現驗證。** 先原測例的例外、alias、名冊、保存／restore，再完整 5,000 人固定步 A/B：HP、KO、命令、RNG、事件、格位、預約、物品、動作次序一致；遷移欄位在邏輯投影後比對。保留比較器邊界測試；不把儲存位址當玩法，但原公開引用的可見行為不能失聯。原完整畫面測例與動態連續呈現檢查保持，不以只測首尾或小名冊代替。
6. **正式無探針驗收最後才跑。** 固定來源，原入口、PLAINS seed 581、兩軍各 2,500、原畫質、原時鐘、暖機後 60 秒。兩次 B 均需 p95 ≤33.33 ms、p99 ≤50 ms、每個 10 秒窗口平均 FPS ≥30、action/wall 0.99–1.01，及既有 gate 全通過；A/B 来源可核對。另報最大幀與慢幀數。

不要用一場未完成的中間切片去碰整場門檻，失敗後再發明下一個微小候選。施工分段用必要的正確性及機制檢查；完整資料流能運作才進正式跑分。相同來源的必要檢查通過後不重跑；遇新失敗依 AGENTS 做有針對性的修正，保留失敗紀錄。

上一版 600 秒長 oracle 預算與實際成本不匹配。下一次需先讓既有 oracle 的邏輯投影／比較能支撐必要長度，或事先配置可完成的有界驗證時間；不能等產品寫完才發現驗不了，也不能删掉 1,800 步需求來宣稱 close。

**停損應針對假設失效：** 完整切片仍做同樣全量工作、轉接成本抵消收益、或正式性能無改善，就保留證據停止。不要讓「這次最多只能改兩個欄位／單段小 helper」預先禁止真正需要的相依修改；也不要把研究建議直接說成已保證達標。

## 8. 本輪完成與仍待證明

已完成：核對開發者原文、正式入口與產品來源、比較失敗候選，提出完整資料生命週期的施工方向。已確認的缺口是持續的通用逐列存取、前綴／例外往返及每輪呈現重建；其各自可省時間、記憶體等待比例和引擎後端影響仍需原生堆疊與新切片驗證。

沒有修改產品或跑新 benchmark。正式 5,000 人門檻仍未通過。應保留現有玩法與 owner，重新處理資料存取及更新邊界；不能再用取消待機、加 MultiMesh、加线程或改一個 setter 代替這個工作。
