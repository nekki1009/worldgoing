# Worldgoing 多陣營百人隊伍效能計畫 r5（交 SOL 施工）

修訂日期：2026-09-29。
**狀態：r5 已開始施工；F5K 正式效能、S10K 擴展及 K1 release 啟動驗收仍 OPEN。實測與未結項見 `output/site_movement_plan_r5_20260929/execution.md`。**
本文件是唯一後續施工依據，取代 r4 的範圍與順序。保留第三版附件的有效技術條文，依使用者最新編制／Site 容量決定重訂工程主線。

專案根目錄：C:/Users/Nekki/Dropbox/竹北社大/(01)102-103學員資料/share/worldgoing。
下文程式路徑相對此根目錄；行號只是本次查核位置，施工以函式、當時來源雜湊為準。
r4 備份：output/site_movement_plan_r5_20260929/plan_r4_before.md。
備份 SHA-256：981EB73F090926721AF0928EB5DC176C679797840D86AD0BFE1E7562CFF855F6。
前兩輪審閱：output/site_movement_opus_review_20260929/REVIEW.md、REVIEW_V3.md。
最新重貼第三版附件 SHA-256：116D29D3ACCD7B0CDEE9FEB1E3AEE70C080C4157481FB199AF497F383AEE0170。

## 1. 使用者已定案的玩法、容量與完成條件

### 1.1 固定編制，不重新要求選擇

每隊約 100 人，每隊可獨立選取、下令、換目標、行軍、交戰、撤退與恢復。正式主目標是同一 Site 約 50 隊、合計約 5,000 人；人數是所有陣營合計，不能每個陣營各取得五千人額度。

同一 Site 可同時有兩個或更多陣營。主要驗收配置：
- 兩陣營：25＋25 隊，每隊 100 人。
- 三陣營：17＋17＋16 隊，每隊 100 人。
- faction_id 表示陣營；team_id 表示一支獨立隊伍；person_id 表示同一真實人物，三者不得互相代用。

軍隊名冊中的隊長已包含在人數內。Player 入隊、獨立 Actor、車輛與乘員按既有真實身分及占格規則計一次，報表同時列軍隊行數、全場唯一人物數與占格數；不能重複計人，也不能把額外占格單位藏在軍隊總數之外。

正式 TerrainLab 入口、Node2D/Camera2D 與地理合同保留。目前大型 Site 為 100×100 格、一格 2 公尺，即 200×200 公尺。本案不擅自改成 128×128、不縮小格子、不容許人員重疊來增加正式容量。

### 1.2 五千是功能與效能目標，不是任意地圖的保證

總格數 10,000 不等於可部署 10,000 人。容量同時受不可走格、外部阻擋、連通區、現有人員、終點租約與交通空間限制。
- 記錄總格／靜態可走格／各連通區／當下唯一占格／合法部署槽位；在途格與租約分開列示，不直接當作不同人物相加。
- 部署依原完整預檢與原子提交；不足時明確拒絕，原名冊、人物 ID 分配、租約與物資都不能半套寫入。
- 驗收 fixture 固定合法部署區、可通行道路與撤退區；不能為湊數刪除障礙、塞在孤島，或占滿唯一道路後把無路可走當成效能故障。
- 正式政策先以最多 50 支隊伍、軍隊名冊合計 5,000 行為本期支持範圍，並經逐次空間驗證；此上限不是動態導航的替代品。既有單隊 200 人相容上限保留，但主驗收一律使用百人編制。

### 1.3 分開命名兩個交付結果

**F5K：正式 Site 五千級實戰。** 真實入口、50 支百人隊伍、兩／三陣營、獨立下令、自然 AI、MOVE／HOLD／遭遇／撤退、堵口恢復、合法存讀、近遠景顯示、30 FPS 與即時模擬全部達標。不能只以兩支 2,500 人 ATTACK 的舊壓測替代。

**S10K：萬人架構擴展。** 相同百人編制擴至 100 隊；使用既有 128×128 專用場地與正式 TerrainLab owner 驗證，實測合法容量與交通空間。它是架構壓測，不改正式 200 公尺 Site 地理與正式保存上限，也不能用兩支五千人大隊代替。

F5K 通過可寫「本期正式 Site 五千人交付完成」；S10K 未過時，萬人目標仍 OPEN。兩者都通過才能寫「本計畫效能目標全部完成」。萬人正式地理擴容／跨 Site 戰場及萬人產品存讀不包含在 S10K 壓測，另列產品範圍；禁止混稱已完成。

使用者後續已指示「實作」；本段原先的唯讀授權限制不再適用。本輪實作與驗證狀態見 execution.md。

## 2. 已有證據與現在不能再重做的工作

### 2.1 最新可用的正式短測

來源：output/site_movement_batch_implementation_20260928/formal_smoke/run_1790612967_3450375/measurements.json。
情境為 PLAINS seed 581、三隊各 100 人、1800×1100、實際 TerrainLab UI、細分探針關閉，使用具編輯器能力的 Godot 執行檔，**不是 release 匯出版基線**。

- 牆鐘 30.012535 秒、737 幀、平均 24.556406 FPS。
- frame p95 62.694 ms、p99 106.853 ms、最大 177.499 ms。
- 完成 24.266667 動作秒，action/wall 0.808551。
- pending 峰值與結尾約 5.797257 秒。
- 三個 10 秒窗：32.606／21.235／19.800 FPS；第一窗也未同時守住模擬時鐘。

判定：來源與地形身分、自然 AI 發令／移動通過；FPS 與即時模擬未通過。其後未取得本版本的三次長測及 5,000 人通過結果。

### 2.2 最新常態成本與事件尖峰

來源：output/site_movement_event_audit_20260928/profiled_1790612674.json。
450 步排除前 30 步暖機，再分開 7 個 AI 發令步，留下 413 個常態步。這份開探針診斷只能用來排序成本，不能與上一節拼成同一個 FPS 帳目。

- 完整 action：mean 25.239 ms、median 24.502 ms、p95 31.999 ms。
- coordinator：20.840 ms，其中 prepare 11.617、propose 4.037、finalize 2.772、resolve 0.676、commit/register 0.934、occupancy 0.479、begin 0.299 ms。
- prepare 內：transit slots 2.282、route cache 2.151、phase 1.863、target context 1.344、life/deploy 1.069、target apply 1.060、ingress width 0.764、recovery 0.610 ms。
- route cache 已含 A* 約 0.074 ms；不能把整個 route cache 當 A*。
- finalize cursor 約 2.094 ms 已含 projection 約 0.631 ms；sort 約 0.727 ms，父子不可重複加總。
- AI 發令事件仍有 macro 約 12–39 ms、deployment 約 11–18 ms、egress 約 0–34 ms 的個別段落，完整事件步可達約 80–97 ms；它們不是每個常態步都付出的成本。

舊外層診斷中的約 9.322 ms 未歸屬時間不是已量到的 GPU 時間；約 4 ms frame setup 與隊長 viewport 的因果也尚未證實。

### 2.3 已完成，禁止再包裝成新修正

來源：output/site_movement_cold_impl_20260929/RESULT.md 及同目錄 final_source_manifest。
- transit reverse BFS 的 cold distance field 已有 native 實作，保留快取 key、順序與 fallback。
- egress 的未 settled target 集合已移到每次呼叫的搜尋迴圈外。
- native 定向案例及 451 狀態精確重播已有通過證據；部分 cold event 顯著下降，AI 發令尖峰仍在。
- 現有 target／route／transit／projection／crowd rendering native 路徑已存在。先讀、擴充原 owner，不再另建同名核心。
- 2026-09-29 現有結果記錄的 DLL SHA-256：32378AFE850F8EF4C6A996B6F729F658315C3531250C2669DEB8606AEDA963EB。

來源變動後須重新確定身分；這個 DLL 指紋不是未來建置可以跳過檢查的固定 PASS。

### 2.4 已有萬人數據，必須納入而非重新忘記

來源：output/site_army_10k_20260925/README.md、ARCHITECTURE_REVIEW.md 與 architecture_review/profile_summary.json。
2026-09-25 的舊版本，兩隊各 5,000 人、128×128 PLAINS 581、正式 TerrainLab 60 秒：
- 無細分探針：8.028 FPS，p95 183.370 ms、p99 202.253 ms；action/wall 約 0.924。
- 另一次有探針診斷：CPU 模擬約占牆鐘 75.93%，CPU 角色呈現準備約 12.49%。
- 其中 prepare_rows、orders、presence 等是當時主要成本；部分已經後續優化，必須對目前原始碼逐項核對，不能拿舊熱點再做一次。
- 試驗性 GPU buffer writer 只做末端資料轉換，舊單輪 7.760 FPS，不是 GPU 常駐 AI；不因已有 compute dispatch 就宣告完成架構改造。

這些是舊版／不同隊數的定位資料，不能充當當前 50／100 支隊伍的成績。現有 ten_thousand_acceptance 只驗人數、合法格、可見與交戰，不含完整萬人效能門檻。

**核心缺口：從未證明目前版本在 50 支百人隊伍、多陣營、完整行軍流程下達標。** 本版直接補這條主線，不再只優化三隊後外推。

## 3. 施工順序、責任與收益判定

SOL 是本案唯一產品寫入者；子代理負責有限範圍唯讀查核。多份 Army／DLL 同時修改時先等待，不混用量測來源。每包都交付改檔、功能證據、完整父階段成本與下一個實際阻塞。

依序施工：
1. **K0／第 4 節：**凍結來源、盤點已完成優化、保留 r4 及歷史失敗資料。
2. **K1／第 5 節：**完成 release 及原驗證器適配；先用原三隊場景驗包能正確運作。
3. **M1／第 6 節：**原 TerrainLab 的動態隊伍集合、隊伍／陣營身分、部署與容量接點；原 SiteStore 同時能安全保存合法新格式。先做 5×100，再 10×100，最後 50×100，均使用同一正式呼叫鏈。
4. **當前尺度基線：**在 M1 功能成立後取得短而有界的 10 隊／50 隊數據，並量同地圖同總人數不同隊數的差異。三百人 FPS 未過不禁止這次定位；功能或來源不成立才禁止報成績。
5. **D1／第 7 節：**完成有狀態的常駐熱資料切片、共用當步空間索引、刪除高頻全軍搬運與重建。這是工程主線，不能再被一串微型 helper 優化取代。
6. **K2A/K2B/K2D／第 8–10 節：**同步精確重構後按證據實施規劃分層、受阻喚醒及發令尖峰削減；一次一條候選鏈。
7. **V1／第 11 節：**50／100 隊長與普通兵呈現，保留精確戰鬥資料，驗各個 camera 距離。
8. **P3／第 12 節：**常駐資料／單一寫者前置是主線；單 worker 是計畫內的解耦工作，必須先滿足完整步資料依賴及吞吐條件。若 F5K 與 S10K 在同步版已完整通過，可用證據取消不再必要的 worker，不能只以300人通過跳過大規模工作。
9. **存讀與功能整合／第 13 節：**50 隊同版保存、載入、控制與退場；每包先驗相關切片，不拖到最後才發現雙權威。
10. **F5K／第 15 節、S10K／第 16 節：**正式實戰與擴展分別驗收，報最差輪與所有未結項。

局部 helper 沒淨收益且非必要正確性改動時撤回；必要容量／權威隔離即使本包不加速也可保留，但必須標示「功能前置」，不能冒充性能成果。當某條優化路徑連續兩個版本在相同完整父階段沒有改善，停止加補丁，依現有 log 改處理真正主因。

一次 FPS 失敗不觸發盲目長測；也不再以三百人未過為理由永遠不看50隊實際成本。缺資料時說明具體缺哪個欄位，補最短診斷。

## 4. K0：來源、權威與基準

負責者：SOL 主代理；原始碼／DLL 同一時間只有一位寫入者，其他人只作唯讀審查。

必讀 PROJECT_ARCHITECTURE.md，追到以下真實 owner：
- TerrainData／Site 管地形與占格來源；TerrainArmy 管隊伍、成員、命令、動作。
- SiteCombatMovementCoordinator／SiteMovementReservationGrid 管提案、租約、批次原子提交。
- Actor、戰鬥、道具、SiteController／SiteStore 繼續承擔既有職責。
- 正式普通兵是現有 atlas／MultiMesh；每隊目前各有 live 隊長。64 Near Actor 只存在於其他 benchmark／舊方案，不能寫成正式場景已接入。不得暗換展示情境。

建立 output/site_movement_plan_r5_20260929/ 下單一 execution.md 與 manifest.json：
- Git HEAD、dirty 清單、所有實際修改／載入的 GD/C#/C++/shader/scene/config、DLL、EXE、PCK、資產旁檔指紋。
- 包含 Coordinator/Grid、Actor、時鐘、renderer、存讀與後續新增 runtime；不要只沿用漏掉新檔的舊 13 檔清單。
- 定義 B0 為最新已修 cold field、egress 集合、其餘既有選項全開的版本。不得用早期慢版當新收益基準。
- 每包 B 為上一個已驗收版本；C 只變更當包。保留 B0 的玩法回歸 corpus。
- 工作樹既有未提交工作逐項保留，不 reset、不全量 stage、不刪 output 或 cache 證據。

若另一任務正持有相關 DLL／Godot 或修改同一 owner，記下任務／程序 ID，使用有界 status/wait 等待；不終止他人的程序、不拿正在改動的來源測效能。

## 5. K1：先建立可信的 release 起點

### 5.1 先解決目前工具與匯出的實際不相容

Godot：現用 4.7.2 Mono、Forward+／D3D12，記錄 RTX 5060、驅動、作業系統、視窗／實際 viewport 尺寸與電源狀態。
驗證器保持原樣：
C:/Users/Nekki/.codex/skills/godot-runtime-verify/scripts/verify_godot.ps1。

該 helper 固定要求 ProjectPath 中有 project.godot，且固定傳 --path。既有匯出試驗顯示標準 template 曾拒絕此參數；先前成功的是修改過 path override 設定的 debug template，且使用原始碼絕對路徑 harness，**不證明自足 release 包能測試**。

施工：
1. 沿用 export_presets.cfg 與既有 Mono 匯出方式，加專用 Windows release preset，不改正式 main_scene。
2. 先確認匹配 4.7.2 的 release template 能否接受 helper 的參數。不支援時，沿既有建置路線取得同版本、target=template_release、disable_path_overrides=no 的 Mono template。
3. 記錄引擎 revision、建置選項與 EXE/template 雜湊。自建 release template 如實標示，不冒稱官方預編譯執行檔；editor/debug feature 都必須為 false。
4. 不修改 canonical helper、不移除 retention、不以另一個無記錄 launcher 偷渡。若相容性仍失敗，保留失敗結果並定點修匯出適配，K1 不得假通過。

### 5.2 包含原正式 harness、資產及可寫輸出

修改接點為 scripts/tests/site_tactical_ai_formal_visual_test.gd、site_army_scale_realtime_test.gd、export_presets.cfg 與最小必要的匯出支援。保留同一份情境邏輯，不另寫較輕的 benchmark；兩個 harness 都明列包內相依與可寫輸出，先驗包內載入，效能長測仍依順序執行。

- 明列包內 harness 與相依腳本；目前試驗 preset 排除了 scripts/tests，不能假設自動包含。
- log、JSON、截圖、隔離存檔改到專用 user:// 子目錄或明確指定的絕對輸出目錄。不得寫入 PCK 的 res://，不得碰玩家存檔。
- 現有 atlas／GLB 等存在 globalize_path、FileAccess、Image.load_from_file 原始檔讀取。沿用 output/site_animation_cache_retention_20260917/package_raw_sidecars.ps1 的打包模式，按目前相依生成旁檔清單。
- 歷史旁檔為 505 個、約 765 MB，僅供追溯，不當作新包固定完整性答案。新包逐檔 SHA 驗證，確認男女角色、裝備、馬、atlas、JSON、染色等實際相依物。
- 原 harness 執行時雜湊 .gd/.cpp/.inc 的 editor 檢查保留；release 改讀建置時來源 manifest，另驗 EXE／PCK／DLL／旁檔在測前測後未改。缺檔或空雜湊不能略過。
- 5,000 人 harness 另有 GDScript.source_code 對照及 .godot/mono/temp/bin/Debug/worldgoing.dll 固定路徑；一起適配為實際 release C# assembly、來源 manifest 與原生 DLL 指紋，保留來源凍結強度，不能只修 300 人入口。
- 舊兩隊大軍 harness 靠改寫 source_code／reload(true) 放寬單隊 guard，release 不沿用這種方式。新的 F5K 使用正式 M1 部署50支百人隊，單隊不必超量；S10K 只在專用驗收包顯式放寬隊數／總數並使用128×128場地，不更改正式地理與存檔上限。舊大隊比較測試如仍需要，隔離為 legacy 診斷，不作主驗收。
- release 會省略部分 assert；效能與正式功能關卡使用明確失敗輸出及非零退出碼，不能只靠 assert。原精確契約測試仍可用 debug 執行。

### 5.3 自足包啟動檢查，通過才開始計時

建立隔離 staging 目錄，只有測試所需 release package、已列明旁檔及供 helper 檢查的最小 project.godot。不要複製原始遊戲腳本或 C++ 來掩蓋漏包。

以原 helper 的 Mode visual、GodotExecutable 指向 release console exe、ProjectPath 指 staging，追加 --main-pack <絕對 PCK>、--script res://scripts/tests/site_tactical_ai_formal_visual_test.gd 及原測試參數。必要時明確測試指向 bundle 的第二個 --path 之解析優先序。

這是待驗證的啟動方法，不是已成功的事實：
- harness 必須從 PCK 啟動，正式 TerrainLab 場景成功建立。
- 若 --script 在包內不可行，只加入最薄的包內啟動分支，重用原 harness，並維持正常使用者入口。
- 參數不得引用 SOURCE/test.gd；staging 不含遊戲來源。記錄實際資源解析位置，確認沒有讀回開發目錄。
- Mono、native extension、atlas 必須實際啟用；三隊 sprite mode 應為 baked_atlas。
- output 可寫、隔離存檔、日誌與診斷正常；無 parse、missing asset、extension 或 debugger 警告。
- 另外掃描保存的 stdout/stderr 與 debugger warning 清單；原 helper 不會因一般 WARNING: 自動失敗，所以 GODOT_VERIFY=PASS 只是其中一項條件。歷史匯出版曾有 Image.load_from_file 的資源載入警告，旁檔齊全不代表警告已解決；若再出現，沿原資源 owner 修正匯出載入路徑並驗圖像，不以忽略警告取得通過。
- 不重命名或刪除使用中的原始 checkout 來做隔離證明。

### 5.4 初始基線與多隊測試入口

先跑一次原三隊30秒 release smoke，細分探針關閉。無 parse／功能／來源錯誤，即使 FPS 未達標也可記為基線；不以性能失敗阻擋 M1 容量工作。

沿 site_tactical_ai_formal_visual_test.gd 的正式操作與 site_army_scale_realtime_test.gd 的時鐘／可見性記錄增加百人多隊 fixture。使用明確相同的隊數、總人數、陣營分配、seed、地圖、鏡頭、命令時間表；如需一個新的多隊測試腳本，只作薄組裝，重用原量測／部署邏輯，不新增 benchmark 場景。M1 通過後補10隊及50隊各一次30秒定位，允許 fail 並保存，不能先跑三次長測。

同版本另外取得兩項有限診斷：
1. 完整 frame 與規模帳目：記 N 人數、F 隊數、有效敵對接觸候選數、移動／受阻／交戰人數、live viewport 數、全軍掃描次數與跨語言搬運 bytes；分清人數成本、隊伍固定成本與接觸密度。原腳本 action、Army 顯示、外層腳本／提交、render CPU/GPU 時間與空白餘額；記錄量測包含關係，不把 CPU/GPU 重疊時間相加。使用 Godot debugger／visual profiler；若仍有未知餘額，明列其大小，不猜成 viewport。
2. 可跳過工作帳目：按階段記輸入版本、精確重用條件、規劃 due、喚醒原因、次數與含開銷時間。區分「輸入沒變可精確重用」與「輸入變了但政策允許稍後決策」。少量目標沒變不能代表完整 read set 沒變。

診斷版成績不作正式 FPS。第一批資料取得後即選取最大完整成本投入施工；不再承諾一週診斷或3–8週工程工期。可選診斷最多一次定向補充，未定位的餘額如實列出；時限不豁免 release／來源／時鐘基線。可推進不依賴缺失資料的精確修正，不能盲開依賴該資料的降頻。

## 6. M1：在原 TerrainLab 支援50支獨立百人隊

### 6.1 先改集合與身分，不另建軍隊系統

實際接點：
- terrain_lab.gd 的 _ready（約146–164行）、restore／clear（約423–462）、_next_army_identity、add_melee_trial_team、_deploy_trial_teams。
- site_controller.gd 的三隊部署表單（約554–684）、選隊與下令（約791–911）、capture/load。
- site_combat_movement_coordinator.gd 的 register/unregister（約51–120）、SiteDeploymentReservationRegistry。
- terrain_army.gd 的既有 deploy／軍令／序號／快照；其單隊上限200不必為百人隊改大。

combat_armies 繼續是唯一現場隊伍集合，按真實隊數建造／撤除原 TerrainArmy。保留原三隊快捷入口作相容介面，但不再用三個 slot 或第一／第二／第三隊代表完整現場。

穩定 team_id 不依陣列位置重編、不因退場立刻重用；person_id 沿原分配器保持全場唯一。所有 target、selection、callback、存檔、命令與租約依穩定身分解析，失效 ID 明確拒絕，不落到下一支隊伍。

每個新增隊沿同一條設定流程接入 coordinator、target_query、command callback、blockers、AI、supply、visual、save；每個移除隊在原子安全邊界清理在途依賴／claim／租約／選取／追擊引用後退場。保留清圖、死亡／俘虜與新 Site 生命週期，不留下幽靈占格。

### 6.2 保留正常操作，部署不能只靠測試特權

沿原表單加入「所屬陣營、百人隊數、部署區」並顯示預檢結果；沿原選隊控件列出穩定隊伍編號、陣營、狀態，列表可捲動／分頁，不產生50份一直刷新的人物詳細面板。

必修現有戰鬥視窗摘要路徑（site_controller.gd約1519–1555、2174行）：三元素陣營／隊名陣列不能再用全隊index索引，第4隊即會越界。顯示名稱由team_id及faction取得，選取也依team_id。取消每幀重建全50隊文字及每隊重掃全車輛；車輛按原owner的team_id一次聚合，名冊結構只在增刪／重排時刷新。普通統計初始每0.25秒更新可見列，選中隊摘要最多0.1秒更新；命令結果、控制與選取變更立即刷新。沿原控件實作，不為此新增UI框架。

每隊可單獨點選與發令；敵軍由既有 AI 管理，玩家權限仍由原 commander／控制人物授權。批次測試也走相同部署與軍令 API，不能直接寫 army.cells 當成正式部署成功。

在原 Site 合同集中正式隊數／總名冊額度，deployment、load、UI 使用同一來源；不要分散把300改5000後形成不同上限。正式部署用約50×100配置，不能用25×200或2×2500取得漂亮成績。

多隊部署採先預檢全批、再提交；失敗時不留下部分新隊、租約、已扣物資或重複人物。預檢占格與原有軍隊、Actor、車輛共用，不能各陣營各建一份互相看不到的阻擋。

### 6.3 陣營與跨隊互動

保留現有敵我規則；本期不另建外交系統。相同 faction_id 的不同 team_id 不能互相攻擊，但仍競爭物理通道；不同陣營按原敵對判定接敵，不能把「不同隊」直接當成「敵人」。

_configure_army_blockers 的原兩隊快路、第三隊初始朝向與預設敵軍引用都改成全隊的既有共用查詢。UI 重排、陣營篩選、刪除目標、讀檔後仍選對隊。

SiteArmyAI 已遍歷 combat_armies 並按 faction 分組，不重寫決策。保留同一輪凍結觀測；先重用當輪摘要／cell index，減少 _touching 對每個隊伍配對重建格集合。裁掉候選必須保守，不能漏掉遠程威脅或原最近目標；同分順序固定。

_resolve_exchanges 已有凍結回合、相鄰候選與 person-pair 去重，延伸原路徑。不能把50隊改成各自結算，造成跨隊同一交鋒重複扣血、共享疲勞重複結算或 Grid 雙寫。

### 6.4 本包完成條件

先驗5支百人隊（同陣營至少兩隊）、再10隊，最後50隊：
- 每隊都可被選取、以自身指揮者下令；重排／清隊／存讀後仍對應同一 ID。
- 全場 person_id 唯一，同一人只有一份 HP／位置／裝備／存讀權威。
- 跨隊占格、租約、相鄰對穿／vacancy chain 規則與舊版相同；同 faction 不誤擊，敵對接敵仍真扣血。
- 合法批次部署成功；故意超額、非法格、重複槽位與資產失敗原子拒絕，舊場景及原存檔不變。
- 50隊可經正式存讀往返，無截斷為前三隊。完整時序與邊界驗收見第13節。

本包是必要容量功能，不保證加速；功能通過後立即量50隊，不能只報三队PASS。

## 7. D1：常駐熱資料與共用當步查詢（主要效能工程）

目的：削掉全軍高頻往返與重複掃描，不只是將同一圈 GDScript 翻成 C++。沿既有 native/army_idle、ArmyCombatHot、TerrainArmy 與 Coordinator/Grid 擴充，不新增另一套 ECS／人物／地圖／戰鬥權威。

### 7.1 盤點現況，先對仍存在的成本下手

建立一份欄位清單：原 owner、讀者／寫者、型別、更新頻率、dirty 原因、保存出口、目前是否已常駐。cells、moving_to/progress、動作／HP／KO／cooldown、command/presence、animation 與 draw 欄位分開；身份、裝備、家庭等冷資料不隨每步全量搬運。

對目前程式核對9月25日萬人診斷與9月29日移動診斷，將每項標為「已解決」「仍存在且已量」「尚未確認」。既有 HotStore、native distance field／projection 不重做；現有 GD fallback 的次數與原因必須計入。

### 7.2 最小垂直切片

1. 選取完整父階段中跨語言搬運／全掃描最多的現存鏈，優先 prepare/propose/finalize 共用輸入與 index；只做當次真正需要的欄位。
2. 在原 native 模組用固定型別連續資料跨步保留熱狀態，穩定 person_id＋slot generation 防索引重用。從原 Army 逐欄轉移唯一寫權；舊 Dictionary 欄位改為必要時的版本化輸出，不保留另一份可寫 mirror。
3. 原命令／傷害／KO／換裝／load 在既有提交點更新該 owner。每步輸入命令與變更，輸出必要事件／dirty range，禁止全軍 serialize→native→deserialize。
4. 每組欄位先同步執行、用上一個已驗收同政策版本做精確 oracle；確認完整父成本下降再擴下一組。後續 worker 使用同一份資料，不再搬一次。
5. 冷資料需要同步資料時由明確 boundary 讀取；存讀在完整步一次取得一致快照，不因高頻路徑提速而失去完整人物內容。

### 7.3 重用索引、presence 與生命週期更新

- 當步空間／人物索引由原 owner 在已提交移動、生命／名冊變更的邊界更新。AI、exchange、ranged、HOLD救援只讀同版本索引，不各自重新建全名冊 Dictionary／HashSet。
- 既有 presence／command_dirty 分清參考位置變動與個體資格變動。單人命中但隊伍參考位置不變時，不能無條件排序全軍；遲滯、玩家成員、KO、死亡與在途位置仍依原時機更新。
- 若仍有每名射手掃全場、每名待機者掃所有敵軍／待救者，使用原範圍與順序的局部候選集合。只改候選取得，不改射線、命中、護甲、彈藥、救助資格與裁決順序。
- 以活動集合處理移動中、到期、受阻、待救、待發布顯示的成員；跨組轉移必有事件或到期保障，避免為省掃描讓停止者永不喚醒。
- O(N)的必要緊湊批次可以保留；要求拿掉的是同一批輸入的多輪重建與不必要字典往返，不能為追求零掃描加昂貴比對。

### 7.4 每包要交付的收益證據

同場景同輸入記錄完整父階段 ms、全員讀／寫行數、跨語言 bytes、配置次數、空間索引重建次數、native／fallback 次數。同步資料版必須在10隊與50隊各驗一次；兩队大軍改善不能抵銷50隊惡化。

不承諾某一段可固定省50%；理論上限只用互斥父成本、實際命中／失效頻率計算。必要容量與單一寫者前置可標零收益，但接下來的減量包必須拿出含維護開銷的淨省量。

## 8. K2A：把每步必做和規劃重算分開

### 8.1 K2A-1：同頻切開，先證明沒有改壞

接點：terrain_lab.gd 的 _advance_action_time／_advance_combat，terrain_army.gd 的 prepare／propose／finalize，以及原 Coordinator/Grid。

保留三種不同時鐘：
- ACTION_STEP = 1/120 秒是原底層積分步。
- 戰鬥／移動協調以 1/30 秒執行。
- exchange 查詢 0.1 秒及原 AI review 週期先不改。

每個既有步仍必做：接受有效時間、順序一致的 AI／命令處理、在途 progress、完成落格、player/Actor 占格、提案合法性、原子提交、租約與命令 serial 檢查、KO／死亡／成員變更、到期 timer、接敵與戰鬥必要更新。

從 prepare 中只抽出真正可重用的純規劃／派生資料：target context、transit assignment、phase 幾何、目的地 footprint、ingress 幾何、route 需求整理等。實際候選由 read set 與測量決定；不能整段 prepare 每三步才呼叫，因為它同時處理生命週期、遲滯、等待、恢復與計時。

失效輸入至少盤點：order/control serial、roster、地形 revision、phase、落格／在途、相關 occupancy/reservation、接敵、目的地／slot 指派、到期時間、恢復狀態。採既有 owner 的版本／局部變更集；不要每步雜湊全名冊來省下另一個全掃描。

先仍以 30 Hz 呼叫；在相同設定下通過原 450 步／451 狀態精確重播、功能與存讀。量完整父階段，包含建立 context、打包、native 呼叫、回寫、版本比較、失效與 fallback。

### 8.2 K2A-2：10 Hz 規劃政策與事件喚醒

只有 K2A-1 通過，且影子排程顯示有足夠淨省量時，啟用此包。此包有意改變非緊急決策時機，不能宣稱與原 30 Hz 決策逐位元相同。

一般規劃每三個 30 Hz tick 到期，依穩定隊伍 ID 錯開；安全／實體動作仍每 tick。每次事件帶 reason、首次生效 tick、deadline，合併不得延後最早 deadline。

統一起算方式：事件 E 為「第一個在規劃截止前可看到該權威變更的 30 Hz tick」。若變更發生在當步規劃之後，E 為下一 tick；規劃前已可見的事件，E 就是當步。
- 新命令、控制／名冊／地形變更、接敵進出、目標失效、相關堵路解除、到期事件：在 E 處理，繞過普通到期輪替。
- 一般落格、外部占格、指派或 claim 的局部變更：最遲 E+1 重評估。這可能比每三步輪替更早喚醒，必須計入成本。
- 每 tick 提案與提交仍查當下權威狀態；舊規劃不得令單位穿越 player、搶占租約、重複落格或攻擊不合法對象。
- 期限是模擬 tick，不是使用者輸入到顯示的牆鐘 67 ms 保證；另由時鐘與輸入延遲驗收約束牆鐘。
- 超齡即失敗，不得只輸出警告後仍 PASS。可暫回同頻同步安全路徑並記錄，但正式效能必須把回退成本算入。

具體進展門檻：單一路口、無競爭、命令延遲已結束且唯一下一格合法時，玩家移開後最遲 E+2 開始已提交的步，最遲 E+14 完成該 0.38 秒步。分別記 commit 與 completion tick。無阻擋連續步不得因排程多出超過一個 30 Hz tick 的空檔。

完整 prepare 降頻的理想估算不能當收益：即使可降頻部分達 10.5 ms，25.239 − 10.5×2/3 也仍為約 18.239 ms；尚未算喚醒、比較和回寫。實際四段候選若共 6.837 ms，理想上限才約 4.558 ms，而且未證明全部可省。每包都用實際 due／wake 次數與完整成本更新估算。

50 隊的一個全域 occupation 變更不能喚醒全部隊伍；按各隊實際讀集／相關區域標記失效，terrain 大範圍變更等真正全局事件才全醒。原 AI 0.5 秒判斷、交鋒0.1秒與本節10Hz規劃分開計數，不能把普通規劃降頻當作可延後全部接敵。

本節新命令的 E 指已正式接受並寫入權威的軍令，不包括仍顯示 pending 的提交。命令佇列等待另依第12節驗收，不能重設 E 隱藏前端等待。

## 9. K2B：只對被證實昂貴的無效重試退避

這是條件候選，不是必做架構。先按「失敗原因＋權威輸入是否改變」查 propose／commit 次數和父階段成本；不能僅看 wait count 推定卡住者就是主要耗時來源。

保留既有 player 占格、失敗回饋、等待年齡、公平排序與 recovery。相同 blocker／相同輸入的下一次昂貴規劃最多延後兩個協調 tick；相關阻擋解除、命令、租約、地形與接敵立即依 K2A 緊急事件喚醒。

不能把「嘗試次數」偷偷改為「elapsed time」而不修其所有使用者；選擇原意後統一計數單位。不要用跳過嘗試導致永不增加等待或永不到期。退避 state 依第 13 節存讀。

驗收：玩家堵口解除、head-on passing bay、vacancy chain、isolated recovery fairness、最終全員抵達。若喚醒帳目顯示成本不足以抵銷記帳，保留正確性修正，刪除額外退避機制。

## 10. K2D：消除新命令尖峰，保持原搜尋答案

優先做同一次 preflight 重複的 footprint，再按完整事件成本決定 macro／egress native 化。

### 10.1 同一次 MOVE preflight 重用 footprint

terrain_army.gd 的 _preflight_combat_move 已先建立 platform footprint，FormationDestinationPlanner.plan_deployment 又建一次。以最小可選尾參數傳入當次 fp_info，其他 caller 維持原行為。

只在同一同步呼叫、相同 terrain revision／path／profile／roster 下重用，不新增跨命令 cache。驗完整 preflight 回覆、deployment slots、失敗回退、lease 不變；收益計整個 issue/preflight。

### 10.2 macro A* 精確 native fast path

接點：formation_transit_planner.gd 的 build_macro_path 與既有 native terrain adapter。保留 GD fallback，先用最小結構維持原行為，沒有量到需要時不加新 heap 框架。

必須相同：鄰居 N/E/S/W、terrain/profile/ramp、動態 occupancy 原本是否參與、strict f 比較、平手取目前 open set 插入順序、較佳路徑更新、goal 與截止順序。

原版先判 pop 出的是不是 goal，再增加 expansions；expansions > 10000 才停止。因此第 10001 次 pop 若是 goal 仍成功；非 goal 才停止且不再展開鄰居。不可直接套用語意不同的既有 native movement_route。

定向測空路、起終點相同、不可達、坡／水／邊界、tie/decrease-key、截止邊界；路徑逐格精確一致。量打包、搜尋、回傳、套用及 fallback 的完整父成本。

### 10.3 egress 只處理剩餘熱區

每呼叫只建一次 unsettled 集合已完成，不重做。只有剩餘 egress 有足夠事件成本時才移整段；保留 bucket LIFO、各路徑 4096／8192 budget、pause/resume 狀態、reachability、settled 順序、空／已抵達集合。

_order_delay 在 preflight 成功與租約替換之後才設定，不能拿它隱藏同步搜尋，也不能把返回 ok 提前到規劃完成以前。非同步發令屬 P3 的命令合同，不夾帶在本包。

50隊同 tick 提交命令另作尖峰測例；不把所有 AI 新令集中在一幀做同步完整路徑，也不能偷偷改到達／lease 結果。優先共用同版地形／同目標規劃資料與 native 計算；若採分段或非同步規劃，走第12節 pending→accepted/rejected 合同，每次接受前重驗命令序號、地形與目標租約，過期結果丟棄且明確回覆。

腳本混合負載只發合法 MOVE／HOLD／ATTACK；目前 RETREAT enum 需已 is_sustain_routed，不能強迫正常隊伍接受它。AI 的戰術退讓沿原策略，士氣潰退另用真實條件的定向fixture驗。

## 11. V1：50／100隊長顯示與普通兵批次呈現

接點：TerrainArmy._sync_captain_combat，combat_shapes、contact_protection、aim shoulder 與顯示呼叫；presenter 建立、轉移、啟用、換裝與騎乘生命週期。

這個函式同時服務戰鬥幾何與畫面。不能整段降頻，否則武器、盾牌、護甲、瞄準與碰撞取樣會使用過期姿態。

施工分兩步：
1. 先精確去重。同一完整 pose key 不重做 seek／必要 presenter 同步；key 涵蓋 actor/presenter identity、動作 sample、方向、身體、裝備、騎乘、readiness 等實際影響項。props／cloth／hair 若另受時間驅動，要納入條件或保留其必要更新，不能只看 animation time。
2. 骨架同步版本與圖像待更新版本分開。幾何先同步後，顯示使用同 pose 仍須補畫 dirty 圖像。UPDATE_ONCE 是排程一次，不代表呼叫時已畫完；維持 render_dirty/requested generation，經有效繪製消費才清除。

重建、transfer、disable→enable、viewport／解析度／相機、裝備、外觀、readiness、vehicle 改變均失效。隱藏或未完成 warmup 時不得把圖像標成已刷新；post_draw 通知本身也不能證明停用的 viewport 畫過。顯示最後提交前若戰鬥又改了骨架，必須確認這次畫的是要求姿態。

完成精確去重後，在原 TerrainLab 顯示階段集中排程既有 viewport；只管理 presenter ID、可見性、dirty 與期限，不擁有HP、動畫時計或戰鬥狀態。初始顯示政策：選中／受控或投影高度≥96px者30Hz，32–95px者15Hz，低於32px者5Hz，離屏UPDATE_DISABLED；閾值在V1同鏡頭A/B後固定並記錄，不在正式驗收中任意調低。Sprite地面位置照原頻率，精確戰鬥幾何按每次原查詢同步。

每個presenter一幀最多提出一次重畫，普通到期按穩定ID錯峰。總重畫配額以V1量得的CPU／GPU成本設定並列入manifest；配額是工程控制，不能豁免時效：可見圖像年齡≤該檔週期加一個顯示幀。命中、KO、外觀／裝備、動作切換與重新可見須下一個可見幀提出更新，最遲第二個可見繪製幀呈現；只有實際draw消費該generation才算完成。miss／超齡均記錄並使視覺驗收失敗，不能永遠排在佇列後方。

同屏50個隊長都可能可見，必測全景各LOD人數、更新次數、圖像年齡與CPU／GPU成本。每隊仍有自己的live3D骨架／裝備／可變材質；先查 HumanCharacter3DEditor 的 CACHE_MODE_IGNORE 使用者，只共享可確認為唯讀的GLB、mesh、texture、動畫原件，不共享可變Skeleton或整個角色實例。

先不建通用角色池。若viewport固定成本仍超預算，才在原presenter拆最小顯示RenderTexture／viewport重用；精確姿態和人物權威不能被顯示配額回收。現有64 Near benchmark不代表本場景已接入64人池。顯示策略不得停止普通兵／離屏隊伍的模擬。

驗收：
- 原武器／盾／parry／armor／aim、男女、坐騎幾何與戰鬥 trace 精確不變。
- 幾何先同步而顯示同 pose、同時間換裝／轉向、首次建立、停用再啟用、轉移、load、warmup，全部有有效圖像且不永久凍結。
- 性能測試不做逐幀 GPU readback；必要視覺取樣獨立於計時。
- 普通兵 RGBA 精確合同保留；若 live 顯示有意降頻，另固定相同新政策的圖像 reference 與事件新鮮度驗收，不能單純刪除舊 RGBA gate。

普通兵沿原 atlas／MultiMesh 排序與分組，使用常駐熱資料直接產生必要更新；凍止且輸入未變的 chunk 不逐幀重建，移動者優先用開始／終點／時間的既有插值合同減少提交。相機變化、圖層遮擋、KO、裝備、死亡、load 的 invalidation 全部列出，不能拿降低可見人數換 FPS。

V1 驗兩種視角：全場可見50隊長／5000軍隊成員，以及近景帶資源遮擋與隊長動作。前者量最壞隊數固定成本，後者驗像素覆蓋／圖層／清晰度；各自同鏡頭 B/C。報50個presenter的實際RAM/VRAM、建立時間與峰值，不用色彩貼圖大小冒充總記憶體。

## 12. P3：完整步單一寫者與畫面／模擬解耦

### 12.1 啟動判定與吞吐先決條件

單一寫者與常駐資料是第7節主線，從早期就做，不等待三百人反覆失敗。開 worker 前仍須完成本節安全依賴與實測吞吐，不用背景化掩蓋載入、圖像、GPU或計時錯誤。

先用50支百人隊的混合行動與自然AI trace確認吞吐，不以兩支2,500人ATTACK代替。P3a完成後、P3b前，再量同一資料版3／10／50隊的完整模擬步服務時間；S10K再量100隊。平均仍 ≥33.333 ms 或長期不足 30 步／秒，就須繼續削減模擬工作並留下餘裕；搬 worker 本身不增加單一步吞吐，也不視為解決。

這些無畫面阻塞的 CPU 數據只作架構判定，不代替 GPU 正式 FPS。

### 12.2 P3a：先同步搬 owner 資料，逐包維持唯一寫者

先列欄位 inventory：原寫入者、所有讀／寫 caller、生命週期、存讀與快照需求。現有 native ArmyCombatHot 只持有 COMBAT_HOT_FIELDS，不代表整套 cells、命令、Actor 都已在 native。

逐組將需要 worker 操作的欄位移到原 owner 的純資料 runtime；Army Node 變為該組資料的 facade／投影，刪掉舊寫入口。不要同時保留 SimCore 與 Army 兩份可寫狀態再互相同步。

Coordinator 現握 Army Node；Grid 會呼叫 terrain／army 方法與 begin_committed_move，complete 也直接修改 Army 陣列。改成穩定 ID、純資料 view 與原子 owner 操作，清掉 worker 範圍內所有 SceneTree／Node 回呼；RefCounted 不等於執行緒安全。

仍在主線同步執行；保留原步序：Site tick、玩家輸入、fatigue、AI、Coordinator、Army/Actor、完成落格、ranged/exchange。會改變同一步結果的死亡、名冊、接敵等事件必須當步處理，只有 UI、音效、繪圖通知可延後。

每組搬遷以同政策上一版精確 oracle、原命令結果、存讀及功能測試通過後才進下一組。沒有證據需要搬的系統先不搬。

P3a→P3b 的硬門檻：盤點並打通完整固定步的因果鏈，包含必要的 120 Hz 子步、Site／輸入／AI／Actor／戰鬥依賴，使 worker 能按原順序獨立推進，而不是每個 30 Hz 步都等主線先處理半步。主線只提供帶 tick 的輸入與版本化資料、接收完整結果；對 SceneTree／可變 Resource 的 worker 回呼及等待主線的同步 fallback 次數均須為 0，marshalling 全成本列入帳目。若此門檻未達，維持 P3a 同步，不宣稱已解開主線阻塞。

其中隊長精確姿態是明確前置：目前combat_shapes／護甲／瞄準會進入live presenter的Node同步，不能直接在worker呼叫。先沿現有TerrainArmyContactSource／TerrainWeaponCollision盤點可重用的動畫與裝備幾何資料，將worker所需部分轉為同版不可變數值及純取樣；對原精確姿態與碰撞結果驗證後才使用。顯示仍由原獨立角色處理。若尚無等價純資料取樣，保持同步版並列明缺口，不能用過期的畫面骨架快照代替當步戰鬥幾何。

### 12.3 P3b：單一 worker、命令明確生效、快照有生命週期

只使用一個順序模擬寫者，禁止每隊平行寫共享占格。terrain 使用不可變、帶 revision 的必要資料 view，地形變更在步邊界套用；禁止每幀複製整個世界，亦禁止把可變 Node/Resource 容器別名交給 worker。

沿既有 WorkerThreadPool／生命週期能力完成：
- 命令帶 session generation、目標 tick、sequence、order serial；有界佇列不能默默丟棄命令。滿載回傳明確尚未受理／忙碌，UI 可重試。
- 原 issue_combat_order 同步 preflight／替換 lease／回傳成功。非同步版需顯示 pending，收到 worker 接受才回成功或拒絕；不能先偽造 ok。
- 同步回覆的使用者包括 SiteController（本次定位 893／1486／1887 行）、TerrainLab（2084 行）及 TerrainArmy 內部發令（3342／3413 行）。逐一改接 accepted/rejected 結果、命令序號與舊租約釋放；若保留同步 preflight，須把這筆主線尖峰算回帳目。
- 以「命令在哪個 tick 生效」作同步 P3a 與 worker 的同輸入 reference。定義低負載單令自提交到正式結果最多兩個30Hz tick；50隊同tick尖峰另允許最多30個tick完成各令結果，這是新增的明示佇列政策，須在實作前固定。隊伍已正式接受命令後的步進期限仍依第8節。全程記 received／accepted或rejected／effect tick與牆鐘延遲；pending不等於成功，超齡即失敗，不能不停延後目標tick。
- 一個模擬步保持原子，不從中途截斷或丟棄。只可略過已過時的顯示快照，不得丟模擬時間／步／命令。
- 快照含 generation、committed tick、publish wall time 及必要顯示資料。用有讀者生命週期的不可變發布或固定三槽 buffer；worker 不覆寫主線正在使用的槽，不讓佇列隨時間增長。
- 每幀不等待 worker；完成任務仍按原 API 安全回收，load/exit 停止接新任務、作廢舊 generation，在明確安全邊界等候回收，避免背景任務訪問已釋放資料。

### 12.4 存讀與背景時鐘不得縮水

SiteController 目前先檢查保存 guard，再 capture Actor／Army，最後交 SiteStore。背景版必須在完整步 barrier 鎖定同一版本，對該版本檢查 guard、擷取資料，再交 SiteStore，避免檢查與擷取之間 worker 跨步。明確處理或拒絕未決命令；保留 projectile、死亡、person action、交付等原保存 guard 與 SiteStore atomic replace。

同時記錄：已接收有效牆鐘推算應完成的 tick、最新 committed tick、畫面 snapshot tick、snapshot 發布時間。只記 latest committed−displayed 會在 worker 停住時錯誤顯示 0。

正式量測期間 snapshot tick 相對應完成 tick 與最新完成 tick 的落後均 ≤2 個 30 Hz tick；所有超限記錄並使快照關卡失敗。暫停／失焦依原明示時鐘政策，不算應推進時間，也不得漏收本應推進的有效時間。再疊加第 15 節全部 action／pending／FPS 門檻。

P3a 功能失敗留在同步修；P3b 畫面順但 action、pending 或 snapshot 失敗時仍不 close。保留最後已驗收同步路徑供回退。

如果尚未開 worker，同樣需要明確的主線分段規劃 budget／pending 合同才能處理50隊命令尖峰；不能把舊同步 issue_combat_order 任意變成回 ok 的假非同步。原子接受、舊命令持續執行／被替換時點與取消規則全部納入 reference，單一命令權威只實作一份。

## 13. 行為、精確對照與存讀合同

### 13.1 三類驗證不能混在一起

- 不改語意的重構：B/C 同輸入、同政策，450 步／451 狀態逐步精確比較。包含 cells、moving_to/progress、命令、租約、等待／恢復、戰鬥結果與必要 scheduler state。
- K2A-2／K2B及命令排隊有意改時序：獨立舊政策與候選世界，驗預先列明的可延後決策、每tick安全性、事件期限、進展與公平；另以兩個相同候選世界作451狀態精確確定性驗證。排隊先在同步資料版固定received／accepted／effect政策，worker再對該同步版精確比較；不能只餵事後錄好的接受序列而漏驗真實命令延遲。
- 性能：單世界、關閉逐步 hash 與細分探針。不能把正確性 oracle 的雙世界執行時間拿來報產品效能。

debug 全量對照使用隔離世界、唯讀快照或無副作用純計算；不可在同一 live owner 上再跑一次會改狀態的 prepare。

### 13.2 擴容保存與精確續玩

F5K 是正式可用場景，保存不再維持三隊／300人的限制。最小接點為 site_store.gd 的 _validate_armies、人物／車輛總額、拘押關係上限、MAX_BYTES，以及 TerrainLab／SiteController 的capture／restore。
- 逐一消除 armies.size()>3、總行數>300、車輛／人物合計300、相關302筆引用等固定假設，改按第1節同一容量政策與實際合法集合驗證；不刪除重複person/team/claim、dangling reference、單隊上限、terrain／行軍合同檢查。
- 另有live_presenters總數>3的保存拒絕（site_store.gd約792–793、858–860行）；改成與正式50隊容量一致，保留每隊最多一位原live隊長及合法visual_role驗證。只改armies／300上限仍會使50隊保存失敗。
- 原8MiB envelope限制可能容不下50隊。先測完整JSON envelope含checksum包裝及escaping的實際 bytes、peak memory、save/load時間，再設定有證據的固定有限上限並同步writer/reader；不取消檔案大小保護、不按不可信輸入動態放寬，超額保留舊檔且明確失敗。
- 載入依保存的team_id建立需要的原Army集合，再復原人物／跨隊引用／租約／AI／UI選取；失敗回滾原場景，不留下前幾隊。保留舊三隊存檔及既有格式遷移。
- 50隊全量保存為必要驗收；選擇符合既有保存guard的非交戰在途MOVE邊界，含Actor／物品／車輛合法相依。戰鬥／projectile等不允許保存狀態照舊拒絕或延後，不能關掉guard求PASS。

在原 TerrainArmy／SiteStore 存讀格式增補會影響決策的排程狀態：每隊模式、距下次普通規劃剩餘 tick、待處理 wake 及 deadline、必要 backoff 的到期／原因／公平狀態。不要只存重置後無法對應的 coordinator 絕對 tick。

新格式在完整原子步邊界保存。50隊／5,000人先驗全量身分、命令、租約及初態，再做至少120個tick精確續玩；不得只抽前三隊。對三種 modulo-3 相位、在途步、堵路／待喚醒各取樣，比較「候選不中斷」與「同候選 save→load」往後至少 120 個 30 Hz tick 的完整權威與排程狀態。排除項只限診斷時間與不具語意的 object identity，列明清單。

舊格式預設維持原 30 Hz 規劃直到下一道新命令才採新模式，保存後明記模式；不得 load 後強制第一步全算而宣稱只有第一步有差。原 SiteStore schema 相容、驗證與 atomic replace 保留。

### 13.3 直接擴充現有測試，不新造整套框架

- 重播：site_movement_formal_replay_test.gd、site_movement_r3_replay_test.gd；單變因 fixture 參照 site_transit_distance_field_formal_replay_test.gd。
- 節奏／玩家：combat_movement_physical_cadence_test.gd、combat_movement_player_block_test.gd，補第 8 節 tick 斷言。後者既有步長為 0.05 秒；另加明確的 1/30 秒案例，分別記錄提交與完成 tick，不能直接拿舊步號套新門檻。
- 公平／抵達：combat_movement_multi_team_arrival_test.gd 保留 30 模擬秒內各隊有進展、首次進展差 ≤200 tick、120 模擬秒內精確最終位置；head_on_passing_bay、isolated_recovery_fairness、100_choke_bend_arrival 保留原硬門檻及穩定 5 秒。
- 存讀：combat_movement_multiphase_store_resume_test.gd、combat_movement_site_store_resume_test.gd、combat_movement_vacancy_chain_store_resume_test.gd、test_save_load_movement_runtime_state.gd；保留 runtime ID 變化後的穩定仲裁。
- 遭遇：site_move_encounter_test.gd、site_move_encounter_lab_test.gd、site_move_encounter_formal_visual_test.gd。
- 原子性：combat_movement_lease_lifecycle_test.gd、invalid_batch、ko_absence、200_capacity_rollback 與 test_route_budget_aging_fairness.gd。
- 尖峰：test_egress_retry_resume.gd、test_egress_contiguous_ranking.gd 與新增最小 macro 邊界案例。
- 山地／在途：combat_movement_formal_mountain_arrival_test.gd、combat_movement_inflight_soft_target_roundtrip_test.gd。先查現有結果身分；不可假設歷史紅燈已修，也不重跑已有效覆蓋且未受改動的全部資料。

省略列示前綴的測試名稱均指同 scripts/tests 目錄內既有對應腳本，執行清單要填完整實際路徑與檔案雜湊。

保存IO不混入固定120秒戰鬥性能窗，另報實際存／讀耗時及畫面阻塞；恢復後重新開始正式性能窗。原因是存檔操作有獨立契約，不是允許在性能窗遇到長幀後事後排除它。正式功能仍須完成保存／載入、失敗保留原檔與再次獨立下令。

多隊最小新增回歸：同陣營兩隊與第三敵隊、50隊非連續ID／重排／刪隊／load、同一敵對人物pair只結算一次、全場唯一占格、51隊或超總名額原子拒絕、損壞檔／重複引用拒絕。沿既有測試擴充fixture，不新增泛用框架。

## 14. 成本核算與少跑但有效的測量

每包報告同一父階段 B/C：
- inclusive mean／median／p95／p99、次數、總成本與包裝／計算／回寫拆帳。
- cache hit/miss、due/wake/fallback、規劃年齡、每隊進展與命令事件。
- 總淨省 = 原完整路徑 − 新完整路徑；父子重疊只扣一次。快取比較與 wake 引入的成本不能藏到「其他」。
- 常態步與 AI／新令／重建事件分開列，同時保留全部事件的整體 frame 百分位。

先最小功能驗證，再一組配對短 trace；值得保留才做合併版 B/C/C/B 450 步測量，前 30 步只在暖機後統計排除，原始資料照存。不得每改一個細節重跑三次長測。

初次3／10／50隊的各一次短測是定位，允許記FAIL後推進減量工程；不得因3隊FPS不過就停止取得50隊必需數據。相同候選的正式30秒smoke通過後才啟動重複長測；有一次失敗就停剩餘同版本長測，先分析已保存資料。修正後重新開始該版正式次數，不能混搭不同版本湊成三次 PASS。

人數、隊數、地圖大小與接觸密度分開：
- 100×100、同1,000人，在5×200與10×100作一次配對診斷，可看隊數固定成本；這不是正式百人隊驗收替代品。
- 同100×100場地依3×100→10×100→50×100量分段成本；不得把N增長全部視作線性或宣稱一次全局O(N²)。
- S10K使用128×128時，先保留同版本50×100在128×128的短控制組，再比較100×100人；100×100地圖五千和128×128萬人的差異不單歸因人數。
- 大規模完整雙世界oracle與逐人hash只在功能模式；正常性能log採聚合計數、命令／狀態變更事件與慢幀環形記錄，不能每幀序列化5,000個字典。

## 15. F5K：正式五千級多陣營實戰驗收

### 15.1 所有正式性能 run 共用硬門檻

以下是規格，不是已達成的結果。release、細分探針與雙世界對照關閉，同一版本、硬體、驅動、窗口／viewport、相機與fixture。
- frame nearest-rank p95 ≤33.333 ms、p99 ≤50 ms；每個完整10秒窗平均FPS ≥30。
- 整段及每個完整10秒窗 action/wall 0.99–1.01；保留既有明列的取樣量化epsilon，不能擴張HOLD例外。
- 有效時間守恆：accepted = completed + pending增量；不丟delta、不截斷欠時、不降低time_scale來過關。
- pending peak ≤0.25秒，結尾 <1/30秒加既有量化epsilon；無 ≥1000ms幀。所有 >100ms幀連同前後事件保留且計入百分位。
- 來源／EXE／PCK／DLL／資產測前測後一致；無腳本／載入／native錯誤及未處理相關warning。
- 全場身分守恆，所有應顯示者有有效圖像；不得透過少建立隊伍、移出視野、不結算後排或自動刪除戰敗者取得FPS。
- P3啟用時，再驗命令期限、快照年齡與完整模擬吞吐。畫面順、人物停住仍FAIL。

### 15.2 fixture成立先於性能判定

正式100×100、PLAINS seed581、1800×1100及記錄的實際viewport；普通兵／隊長／資產走原正式路徑。固定部署位置、陣營分布、通道、接觸線及撤離方向，不改地形來湊數。

依序通過3×100、10×100、50×100的功能初始化。需要的部署區與目的地租約均由原預檢產生，將完整fixture保存供重播；不要每輪隨機找較容易的路。

在性能計時前驗：50個不同team_id、50份獨立命令狀態、軍隊總數5,000、陣營人數、唯一person_id、合法占格、可通行接觸／退讓路線、native實際啟用。全景攝影機下核對所有預期在場人物；近景按真正視錐核對，不要求離屏者也提交GPU。

先在功能模式證明下列工作量真的會發生，再凍結fixture；若場景無合法路／無權下令，標記fixture失敗，不能稱性能不達或把測例放寬後沿用舊分數。

### 15.3 功能與工作量關卡

A. **獨立命令與50隊混合行動，60秒。**
- 每隊至少一次透過原UI／授權callback收到自身合法命令；記team_id、requester、order serial、結果、實際生效tick。成功與預期拒絕分開，不把送出請求當作動作發生。
- 腳本保證MOVE、HOLD、ATTACK負載同時存在，預選通道與目標。AI退讓沿原策略，RETREAT enum另在符合士氣潰退條件的定向測例驗；禁止要求每隊任意輪換四命令且全部成功。
- 腳本控制隊沿原人工接管流程關閉自主覆令，指定的AI退讓隊另列team_id與數量；逐10秒核對各組實際軍令。不能以AI自行改成另一命令後的活動替腳本MOVE／HOLD／ATTACK通過驗收。全部隊伍的獨立選取／授權發令在前置操作測例完成，AI組進性能窗前恢復原自主模式。
- 每陣營至少80%隊伍在60秒內有一次合法實體步完成或真實交鋒：25隊至少20隊；17／17／16隊至少14／14／13隊。這是新fixture門檻，先固定再測。其餘隊必須有可從權威狀態核對的占格／敵情／恢復原因，不能默默停機。
- 每個完整10秒窗至少半數隊伍有MOVE／ATTACK／追擊／戰術退讓意圖，且至少10支不同隊伍有實際步完成或交鋒。後段全軍HOLD不能冒充混合戰鬥成績。
- HOLD在已承諾的步完成後不新增非法移動；跨隊lease不重疊；每一person-pair的同回合交锋只結算一次。
- 不要求50隊在擁擠地圖60秒內全部抵達；精確最後槽位與長期抵達另沿已有可解fixture驗證。

B. **自然AI實戰。**
- 所有合格戰鬥隊啟用原AI，按同輪凍結事實決策，量測窗不以私有欄位強制替它選令；人工操作測例與此項分開。
- 每方都有真實敵對交鋒，並有預置可解的弱勢／休整條件使每方至少一隊依原AI選擇退讓且完成離開威脅方向的合法步。
- 正常隊伍和士氣潰退隊分開；後者先沿原士氣／供養機制或合法初始化狀態建立條件，再驗撤離與安全整補，不能改掉NOT_ROUTED規則。
- 參與率、每窗工作量與身份守恆同A。若既有AI本身無法完成必要玩法，修原AI／資料取得，不以假發令填補。
- 80%參與率在A的60秒牆鐘量測窗結束前達標；B即使跑120秒，也須在前60秒牆鐘達標，全部10秒工作量門檻涵蓋完整120秒。個別步進／軍令期限仍按模擬tick驗，兩種時間不能混用。
- 傷亡／離圖／拘押依原owner記帳；報互斥狀態與去向，不能刪行。主要性能fixture不預置大量立即出場，避免後半工作量消失。

C. **玩家堵口與MOVE遭遇，60秒。**
- 在50隊全場負載中選兩支百人隊走已知可解入口，其餘維持正常行動；Player在第20秒前移開，之後保留合法出口。
- 相關隊在第8節E喚醒，propose／commit仍驗真正player占格；解除後30模擬秒內受測每隊至少完成有效前進。
- 無競爭單兵fixture仍嚴格驗E+2提交／E+14完成；百人竞爭不能套同一無競爭期限。
- MOVE接觸合法敵人後進入原遭遇流程，接觸結束能續行原命令／槽位；相關小規模原子步／山地回歸保留。

D. **50隊同tick命令尖峰，至少30秒量測窗。**
- 初始穩定、每隊有權指揮者、已知合法且互不重疊的目標；同一tick送入50筆命令，不能在測試送入前偷偷算完全部macro／部署。
- 若採佇列，逐筆received→pending→accepted/rejected與deadline完整記錄；正常合法的請求不能全回BUSY來通過。故意衝突的第二個fixture才驗明確拒絕／舊令保留。
- 已接受且下一步合法的隊伍，自受理起1模擬秒內完成有效提案／開始步進，或有可核對的真實新阻擋；不要求全部一秒到達。排隊結果期限依第12節。
- 尖峰全部計入本節FPS／時鐘門檻，不從樣本剔除。

E. **存讀、呈現與生命週期。**
- 第13節50隊全量精確續玩；每隊load後仍能被正確選取與下令；故意損壞／超限檔保留原場景。
- 第11節全景50隊長與近景遮擋／選取／重新可見；武器、盾、護甲幾何不受顯示降頻影響。
- 建隊／刪隊／切Site／load後無幽靈claim、洩漏的viewport或背景任務。記憶體固定場景穩態不得持續成長，先量暖機後趨勢並保存原始數據。

### 15.4 測試次數與停止規則

不再把三百人3×120秒當作主交付；三百人保留一次30秒release回歸與受影響契約測試。穩定性重複移到真正50隊：
1. 初始定位：3、10、50隊各一次30秒；允許記性能FAIL，功能／來源失敗先修。測過且未變來源的基線不重跑。
2. 每個值得保留的候選：相關功能＋一次50隊30秒smoke。失敗就分析這批log，不排三次長測。
3. F5K最終：兩陣營25＋25、三陣營17＋17＋16各一次120秒自然AI；依較差p99、再p95、再action ratio選較差配置，另獨立跑兩次120秒。共四個run，每輪單獨過關，兩種配置不可混算百分位。
4. 混合命令、堵口／遭遇與命令尖峰各跑一次所需完整窗口；已有同來源自然AI run完整覆蓋的條目可引用，不能重複算不同未覆蓋操作。
5. 存讀與近景圖像在計時窗外測，另交耗時／警告／圖像結果。未變相關程式與資產的既有小規模精確證據可沿用，記理由。
6. 任一正式run失敗，停止同版本後續重複長測，保留全部資料，定點修正後驗相關關卡；最終證據集必須对应同一候選版本。

### 15.5 歷史缺口與結案

沿用carried_open：geometry prefilter矩陣、inflight soft target roundtrip、山地／存讀未覆蓋及舊300秒約4秒停頓。先查已有證據是否能結案。

若4秒停頓仍不明，先具備有限慢幀事件紀錄，再做一次最長300秒定向run；不先重跑三次。與本期相關缺口沒有有效修復／驗證就保留OPEN。

F5K close checklist：50隊獨立操作、兩與三陣營、部署／回退、50隊MOVE／接敵／退讓、原子占格、公平與進展、5,000人存讀、圖像／幾何、全窗FPS與時鐘、warning、生命週期／歷史缺口。任一未完成只能寫局部通過。

## 16. S10K：保留萬人目標，另外驗100支百人隊

### 16.1 場地與產品邊界

沿 scripts/tests/site_army_scale_realtime_test.gd 現有128×128 PLAINS seed581產生器與真TerrainLab，使用M1同一隊伍建立／指令／模擬／呈現流程，100隊各100人。兩陣營50＋50；三陣營34＋33＋33。

容量上限只由專用驗收包明示放寬隊數與總人數，不讀改GDScript原始碼，不改正式100×100地理或產品存檔上限。驗10,000合法唯一人物格、各隊終點／交通空間、原CPU／native128格邊界；不足先修測試配置並保留原因，不能減少人數後仍叫萬人。

50隊功能與資料主線成立後，可以先做一次100隊30秒有界定位，不必等F5K全部長測完成才首次觀察擴展性。正式S10K長測則在F5K基本性能／功能通過後執行。

### 16.2 不能沿用舊萬人PASS字樣

舊ten_thousand_acceptance只驗人數、可見、交戰和時間，缺FPS／pending等完整效能關卡。新增明確S10K gate，重用第15.1節全部幀／時鐘／來源／警告／快照標準。

至少驗：
- 真正100份獨立隊伍與命令，10,000人物／原子占格／50或更多敵友隊伍互動，初末狀態與離場帳目完整。
- 一次混合MOVE/HOLD/ATTACK與原AI退讓，另驗自然AI；每方至少80%隊伍有實際步完成或交鋒。10秒工作量門檻擴為至少50隊有活動意圖、至少20隊有實際事件。
- 100位獨立隊長圖像來源／精確幾何與顯示新鮮度，無「超過64就停止模擬／缺圖」。
- 與50隊的差異按同128×128地圖控制組比較，不線性外推，也不把單純增加map成本當成人數成本。

最終最少兩次獨立60秒：兩陣營一次、三陣營一次；各輪獨立通過。先單次30秒smoke；若失敗，停止長測並交最大殘餘成本與下一包修改位置。已通過F5K不因S10K未過而被冒稱萬人完成。

### 16.3 只有有證據時才增加GPU常駐工程

先完成常駐CPU批次與可擴展更新，預設不重寫整個引擎。若S10K剩餘主要為可平行狀態推進／顯示資料生成，再沿原native／2D renderer選一條完整GPU常駐切片。

該切片必須直接消除CPU全軍準備與來回傳輸；命令／事件容量、溢出、必要有界讀回、確定性仲裁與唯一權威先寫清。不得保留CPU全量計算再把末端幾個乘加搬GPU。跨人HP、占格、交換順序不能一人一thread任意競寫。

若工程需要改精確戰鬥／占格規則才能過門檻，先交具體衝突、成本與玩法差異供使用者決定；在此之前保留正確版本，不能自行弱化規則。GPU不是完成條件；100隊萬人實際通過才是。

## 17. 執行安全、除錯與有界等待

所有 Godot 以原 canonical helper 執行，保留隔離環境、真實退出碼、stdout/stderr/result.json、timeout、ExpectedOutput 與最新 100 個已完成 runs 的 retention。需保留較舊證據時複製指定 run 到本案 output，不更動 helper。

分離 debugger 警告檢查、headless 契約測試、GPU 視覺檢查與性能計時；editor/import exit 0 不等於零警告或正式驗收。必要回歸啟用 debugger並把相關警告列為失败；零警告的正式性能模式不能代替這次掃描。

預先設定最大執行時間：原3隊30秒smoke 120秒；多隊30秒run初值240秒、60秒run 360秒、120秒run 480秒、300秒診斷660秒（含多隊建立／warmup）。分開記啟動／warmup／計時；功能初始化太慢就修生命週期，不任意延長等待掩蓋hang。匯出初值 600 秒、必要 template 建置初值 1800 秒；若實際建置需求不同，在啟動前記理由與新上限。CPU 契約測試依既有 helper 設定，不無限等候。

使用有界 session/task status 與 wait 主動監控。schedule 不可用時以原生工具監控，不另建 recurring automation 當計時器。GPU runs 序列執行。

失敗保存完整結果，定位後作範圍內修正再測；不重跑完全相同的未知失敗、不壓掉 warning、不放寬門檻。只有真正外部阻擋或重大範圍決策才需使用者處理。管理員權限不是本計畫的效能解法，也不是一般測試前提。

本案是計畫交付，這一輪不建置、不啟動Godot或效能run。後續施工按本節規則執行；讀計畫不等於已完成產品擴容。

## 18. 交付檔案、工作量帳目與 SOL 第一包

沿用本主計畫，結果集中 output/site_movement_plan_r5_20260929/，不再產生第二份相互矛盾的主計畫：
- execution.md：每包改動、來源、功能結果、完整父成本、省下的真實工作與下一個阻塞。
- manifest.json：完整GD/C#/C++/shader/scene/config、EXE／PCK／native DLL／C# assembly、資產旁檔、編制／陣營／地圖／相機／命令fixture，及每次run對應。
- verification_manifest.json：原helper參數／result／退出碼、warnings/errors、性能或功能模式、有效證據沿用理由、失敗與未執行項。
- measurements原始資料與可重算summary：保留每次failed run，不只留最後PASS；數據同時報N人數、F隊數與接觸工作量。
- decision.md：F5K、S10K各自結論，已實作／已驗證／缺口／是否close；不能只有一個籠統PASS。
- PROJECT_ARCHITECTURE.md 只在施工真正落地後更新原owner的多隊與容量合同，不在規劃階段宣稱正式產品已擴容。

最小必要log：
- frame／wall／accepted delta／completed action／pending／steps per frame、每10秒窗與全窗統計。
- 各階段inclusive成本、名冊掃描行數／dirty人數／索引重建／跨語言bytes／native fallback。
- 隊伍／陣營／命令ID、received／結果／effect、AI理由、實體步完成、交鋒、撤離、blocked cell與blocker、規劃wake/deadline。
- 全場唯一人物、在場／死亡／KO／離場等互斥去向、實際可見數、每隊參與與每窗活動。
- live presenter／可見viewport／本幀重畫數／圖像年齡／exact pose成本、RAM/VRAM與生命週期。
- worker預期／完成／展示tick、發布wall time、generation與queue長度。
- >100ms幀前後有限事件；正常run不逐人每幀輸出大字典。診斷開銷單獨標示。

**SOL 第一包具體交付：**
1. 核對K0，記當前版本與正在持有DLL／修改owner的其他任務；必要時有界等待。
2. 完成K1匯出／可寫輸出／身分／警告檢查，原三隊30秒取得release起點，性能失敗如實保留。
3. 完成M1最小5隊（同陣營至少2隊）→10隊→50隊的原部署／ID／UI／Grid／存讀通路；單隊仍100，不擴成兩支巨軍。
4. 取得50隊一次30秒短測，列出人數成本、隊數固定成本、接觸成本、全量搬運與live呈現帳目。若初始化／存讀失敗，先修同包，不繞過正式入口。
5. 依帳目立即施工第7節最大完整鏈的常駐／共用索引切片，不以又一份研究報告代替優化。每包更新本文件狀態及execution，不重新發明玩法。

## 19. 官方工具依據

Godot 官方文件用於工具合同；專案實際 owner、行為與歷史成績以上述程式及 log 為準。
- 匯出需要 preset 與 matching template：[Exporting projects](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html)。
- user:// 的可寫輸出與 res:// 差異：[File paths](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html)。
- SceneTree／共享容器的執行緒限制：[Thread-safe APIs](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html)。
- UPDATE_ONCE 的一次繪製合同：[SubViewport](https://docs.godotengine.org/en/stable/classes/class_subviewport.html)。
- 等待與任務回收：[WorkerThreadPool](https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html)。

