# Terrain Lab 隊長領軍、連續下山與集合陣型修正方案

> 2026-09-09 後續修訂：陣型／集合／跑步規劃由 `TERRAIN_LAB_FORMATION_MARCH_AND_RUN_PLAN_LUNA_MAX.md` 取代。下方保留歷史結果；不代表已完成整隊通過與恢復陣型。現行 EDGE 實際仍強制 COLUMN，與原預期行為不符。

交付對象：Luna Max。2026-09-09。狀態：第一版已實作並完成編譯、資料、視覺與效能驗證；「狹口 99 人全數通過並重新展開」仍是後續限制，不宣稱已完成。

本方案取代 TERRAIN_LAB_ARMY_NAVIGATION_PRESENTATION_FIX_LUNA_MAX.md 中的邊緣目標分配與多人搜尋排程方案。不要再實作 100 人各自前往地圖邊緣，也不需要為普通兵建立全圖路徑請求佇列。

## 0. 本輪實作結果（2026-09-09）

- `terrain_army.gd` 已改成隊長單一路徑所有權：普通兵不會呼叫或覆蓋 `_find_path`，隊長的 FOUND route/cursor 可跨全軍步進保留。
- `MOVE_TO_EDGE` 現在只產生一個真實邊界目標；隊員只由隊長位置、共享距離場與局部 slot 集合，不再各自跑向邊界。
- `FOLLOW_PLAYER` 只更新隊長目標；隊員不再追 PLAYER 的遠端終點。開闊地使用固定 slot，路徑狹窄時可切 COLUMN；邊緣命令採隊長先到、邊界集合。
- 部署保持靜止，只有按 FOLLOW/EDGE 後才重建集合目標；HUD 顯示隊長位置、邊界目標、formation mode 與已集合數。
- 通過 `terrain_lab_army_test.gd`：隊長單目標、三層 3→2→1→0 真實 EDGE、唯一占格、坡道合法、交換、route ownership。
- 通過 `terrain_lab_army_visual_test.gd`：隊長 live presenter、99 人 baked atlas、交換前／中／後截圖。
- 通過 `terrain_lab_army_performance_test.gd`：D3D12/NVIDIA RTX 5060、1666 nodes、moving P50 16.669ms、P95 16.795ms、P99 16.888ms、FPS 60（max 108.099ms；採樣完成 24 steps、7 swaps、28 arrived）。

目前尚未把「狹口中 99 人全部通過後自動重新展開」當作完成；當隊員被互相占格卡住時仍會停留在局部集合，這是下一個明確的導航/讓位工作項，不可用 `arrived_count()` 假裝完成。
本輪 headless 夾具仍以既有固定 tick `_simulate_step` 驗證資料與占格；視覺/效能測試走實際 `process_frame`。因此它不是完整的 99 人狹口幀預算驗收。

## 1. 本次行為契約

按「移往地圖邊緣」：僅隊長選擇一個可達的真實地圖邊緣並尋路。99 人跟隨隊長，在其附近集合；開闊地維持陣型，狹口收成縱隊，離開狹口後恢復陣型。隊長抵達後停止，全隊完成集合才顯示完成。

按「跟隨 PLAYER」：僅隊長根據 PLAYER 更新行軍目標。普通兵完全沿用同一套跟隨隊長與集合邏輯，不直接追 PLAYER 的遠端座標。

沿用 100×100 TerrainData、64px 格、隊長 index 0、一格一人、0.24 秒步行時間、隊長單一 live 3D source、99 人 baked atlas。所有移動使用 terrain_cell 與 TerrainData.can_step；禁止瞬移、穿崖、忽略占格、加速士兵掩蓋掉隊。此次不接入 World/Region/Site。

## 2. 已確認的程式缺口

以目前檔案與函式為準；行號只供定位，實作前重新確認。

| 位置 | 現況 | 後果 |
|---|---|---|
| terrain_army.gd::_find_path，約 741 行 | 只阻止其他人覆寫隊長 PENDING；FOUND 後其他請求會執行 _clear_path_route | 隊長剛取得完整路徑，士兵就能刪掉尚未消費的路徑 |
| 同函式 | 預算檢查在 _start_path_job 之後 | 即使不能展開，也能先清空／重建搜尋工作 |
| _next_step | 無有效 route 就回 Manhattan 貪心 | 下一坡道需要先遠離目標時可能折返或停滯 |
| _replan_follow，約 491 行 | 隊長換格仍呼叫 _find_follow_goal | 不清 route 仍可能換 goal，使 route 不再匹配 |
| _choose_edge_targets，約 566 行 | 將 100 個目標直接指定 desired_cells | 全軍各自跑向地圖邊緣，並非領軍 |
| _formation_goal | 以最終 leader_goal 為錨，永遠在 +Y 放陣型 | 隊員橫切遠處目標，無法跟隨轉彎／下山 |
| _verify_multi_level_descent | 只改隊長目標，99 人停在原地；直接呼叫 _simulate_step | 沒有驗證全隊工作干擾，也未使用實際幀預算 |
| performance test | 暖機前記步數，允許 moving_count > 0 當通過 | 60 FPS 不能證明採樣期間隊長繼續下山或全隊集合 |

上述是可由程式確認的缺口。使用者當前生成地圖是否也缺少合法坡道，尚未重現；不得把所有停滯都歸因同一原因。上一輪 PASS 不等於目前需求驗收通過。

## 3. 縮減資料責任

全部先放在既有 TerrainArmy，不建立 Army2、獨立每人導航 manager 或每兵 NavigationAgent。

- `march_goal`：僅隊長持有的最終目標。
- `captain_route: PackedInt32Array`、`captain_route_cursor`：隊長專用完整路徑，普通兵無權修改。
- `command_revision`、`terrain_revision`：Generate／clear／換指令時遞增；搜尋結果附版本，過期結果不得提交。
- 隊長搜尋狀態：NONE / SEARCHING / READY / UNREACHABLE。搜尋工作區仍使用現有 Packed previous/frontier，與已發布 route 分開。
- 全軍狀態：ASSEMBLING / MARCHING / COLUMN / REGROUPING / COMPLETED / BLOCKED；WAITING_PATH、WAITING_OCCUPANCY 等是等待原因，勿與完成混用。
- `formation_heading`：由隊長已提交的行進方向更新，不能用每幀像素抖動決定。
- `rally_anchor`：隊長當前位置或已走過的附近安全集合點，不能超前指向終點。
- 隊員的 `slot_id`、`slot_cell`、`queue_rank`：固定身份、唯一格；只保存小型陣型資料。
- 隊長已走過的 trail（Packed cell indices）：在隊尾不再需要以前不得裁掉；清圖一起清除。
- 一份全軍共享的「到集合點」反向距離場，含 building/published 緩衝與版本；不是 99 張搜尋圖。

`cells / moving_to / reservations` 仍是唯一移動狀態。desired_cells[1..99] 若保留，只代表局部集合／陣型格，不可存地圖邊缘目標。

## 4. 隊長完整尋路

### 4.1 真實邊緣

MOVE_TO_EDGE 從隊長格在 can_step 圖上做一次有預算的 BFS，選最短可達真實邊緣：x=0、y=0、x=width-1、y=height-1。固定鄰居順序決定同長路徑的選擇，保持 deterministic。找到後直接回溯路徑，不再把全圖排序成 100 個目標。

隊長已在邊緣：保留位置，進入集合。沒有任何可達邊緣：報 UNREACHABLE_BOUNDARY；不能選內側「最靠近邊緣」的格子當成功。預設停在圖內邊緣，不刪除軍隊、不自動離圖。

終點是否有足夠陣型空間，交給到達集合邏輯：邊緣內側尋找可達集合區；必要時採縱隊或較窄陣型，不能強求 100 人都站邊界。

### 4.2 route 的生命週期

搜尋只由隊長目標變更發起。普通兵不再呼叫 _find_path。advance_frame 每幀一次推進搜尋，建議起始限額 512 展開、1ms 軟上限，每 32 格檢查時間；100 人的循環不得觸發 100 次展開。

READY 後，每次只取 route[cursor]，檢查 can_step 與占格，合法才啟動移動。僅在普通移動完成或原子交換完成後 cursor++。不能在選取、reserve 或渲染時先推進。cursor 單調，不因一格完成、士兵目標或陣型更新歸零。

友軍阻擋時保留 route，走交換／讓位；不得回 Manhattan 選另一方向。PLAYER/NPC 暫時占格先等待；持續阻擋超過可調門檻才重搜，不能每幀重建。地形版本改變、使用者換指令、目標真正失效才取消舊 route。

FOLLOW_PLAYER：僅 PLAYER 離開跟隨死區、舊目標失效或換指令才更新 march_goal；隊長換格本身不能改 goal。合併頻繁 PLAYER 更新，每次新搜尋從已完成格開始；進行中的合法一步先完成。

## 5. 隊員集合與陣型

### 5.1 開闊地

每個隊員取得穩定 slot，圍繞隊長已到達的 rally_anchor。沿現有十列陣型定義確切的 99 個唯一偏移，列出 slot 1、10、11、99 的單元例子確認沒有多一列／缺格。整體以 heading 旋轉 90 度；隊長格不當普通 slot。

不要每次隊長走一格就全員重新搶最近格。初始建議每前進 3 格、重要轉彎或跨層後更新集合點。維持已發布場直到新場完成；新目標合併，不能不停取消尚未完成的建構。

全軍共享一份以 rally_anchor 為根的反向距離場。隊員先走合法且距離下降的鄰格，再經占格仲裁；進入集合區後才做局部 slot 落位。局部落位可用半徑 12 格、最多 625 展開的有界 BFS，每 tick 最多 2 次，結果可暫存消費；它是解決局部阻擋，不得退回每兵全圖 BFS。不能用純 Manhattan 落位穿過峭壁。

已發布場對未覆蓋／不可達格回 WAITING_FIELD 或 UNREACHABLE_RALLY，不可直接走直線。第一版場可遍歷完整 100×100 can_step 圖；至多兩份 Packed 距離緩衝，採共享預算，約 O(cells) 記憶體。

### 5.2 狹口／坡道

「保持陣型」在開闊地是隊形，在一格坡道是有序縱隊；不能硬塞十列進一格。

當接下來約 8 格 route 的橫向連通寬度不足現陣型，或遇只容單列的 reciprocal ramp，進 COLUMN。寬度沿 can_step 邊查詢，不能只看附近 walkable=true。最初採保守收成單列，不必開發任意寬度最佳化。

隊長 route 與已提交 trail 定義通行走廊。隊員依穩定 queue_rank 追前方隊員已釋出的格／trail 進度；禁止追前人「未到達的遠端格」或隔著山直接插隊。入列時未在 trail 的人透過共享集合場到隊尾入口，完成合法接入後才推進自身 trail cursor。一次只准一個順位取得入口 reservation；普通兵不能占用隊長前方 route 當 ARRIVED 位置。

轉彎、下到新平台後，隊長先離開出口至安全可站區，再等待隊伍。出口與緊鄰通道格禁止當最終停靠點。後到者有路徑可通往其 slot；先到者不得把出口圍死。

偵測到 100 个唯一且可達的站位、局部連通足夠後進 REGROUPING，完成才恢復 MARCHING。小平台容不下則保留 COLUMN，不宣告全部已恢復寬陣型。Heading 在收列／重整過程鎖定，避免每一步重排。

### 5.3 隊長等隊伍

同速隊長不能永遠走、又要求落後隊員追上。以路徑距離／trail 進度測量落後，初值最落後者超過 12 格時在下一安全點等待，縮至 8 格再走。轉彎窄口可按實際縱隊長度調整基準，不能拿 99 人縱隊天然長度當永遠掉隊。

用「相對於該順位應處的 trail 進度」計算隊列誤差。等待點不能在唯一坡道、入口或出口。若沒有安全停靠區，允許隊長走到下一平台再停；依舊保留完整 route。個別不可達者明確報出 unit/cell/原因，整軍標 BLOCKED，不能跳過該人就宣告完成。

## 6. 仲裁與每幀執行順序

1. 每 render frame 推進隊長搜尋與集合場建構，共用總預算；隊長高優先，但給集合場至少固定少量展開以免長搜餓死它。
2. 固定 simulation tick 完成已到時的移動／交換，驗證 source、destination、reservation owner。
3. 更新隊長進度、trail、隊形模式與必要集合目標。
4. 隊長先提出下一步；全部 99 人提出廉價下一步意圖。
5. 統一以「隊長／通道先到隊列／等待年齡／固定 unit id」仲裁目的格；一格一 owner。
6. 若隊長下一步被靜止士兵占住，沿用合法原子交換；普通兵局部讓位只能走合法相鄰空格，目的必須離開受保護通道，不建立遞迴推擠。
7. 提交、更新動畫與插值；動畫不得因每個格子重新選 walk 而重播首幀。

一步仍 0.24s；保留完成後剩餘時間，避免固定 0.1s tick 每步丟掉 0.06s。不可在一個 tick 無上限連走多格。外部 PLAYER/NPC 的正在離開格及到達格用其唯讀過渡占格查詢；不得從像素位置猜。

clear / Generate / 重新部署：清搜尋、route、trail、場版本、slot、queue、reservation、交換。舊結果不能套到新 TerrainData。

## 7. HUD 與完成定義

保留原按鈕，邊緣按鈕文字改「隊長帶隊前往邊緣」。顯示：隊長 cell/height、march_goal、route cursor/length、SEARCHING/READY、全軍模式、已集合 n/99、隊尾誤差、最久無進度秒數、當前等待原因。

隊長在真實邊緣並無未完成一步：CAPTAIN_AT_BOUNDARY。99 人已在合法唯一集合 slot（或明確的窄陣型站位）且無活動移動：COMPLETED。不得再用 arrived_count()==100 個邊緣目標判斷。FOLLOW_PLAYER 的集合完成是暫時穩定狀態，PLAYER 再移動後仍能續行。

## 8. 實作順序與檔案

| 階段 | 檔案 | 必須完成才往下 |
|---|---|---|
| 1 | scripts/tests/terrain_lab_army_test.gd | 先重現 FOUND 隊長 route 被另一人清掉，記錄失敗輸出；建立全隊命令測試 |
| 2 | scripts/terrain_lab/terrain_army.gd | 邊緣指令只給隊長；隊長專屬 route；刪普通兵全圖 _find_path 呼叫；隊長能下三層 |
| 3 | 同上 | 共享集合場、穩定 slot、方向旋轉；開闊地全隊完成集合 |
| 4 | 同上 | 狹口排隊、讓位、出口保護、隊長安全等待；99 人全部過坡道並集合 |
| 5 | terrain_lab.gd；必要時 terrain_test_character.gd | HUD／完成狀態；必要唯讀過渡占格 API |
| 6 | army_visual_test.gd、army_performance_test.gd（實際檔名前綴 terrain_lab_） | 真實地圖錄影／連續截圖、动态效能及完成量 |
| 7 | TERRAIN_GENERATOR_LAB.md、此文件 | 實測值、限制、可重現 seed/cell、操作方法 |

不預先重寫 terrain_generator。只有獨立 can_step oracle 證明生成地圖缺連通，才記錄地形缺口並做必要最小修正，仍不得放寬通行規則。

## 9. 必跑驗收，禁止以局部 PASS 代替全隊完成

所有模擬測試使用 advance_frame(1/60)，不以直接 _simulate_step 取代幀預算。失敗要向上傳遞並 quit(1)；任一 SCRIPT ERROR／assert 失敗即 FAIL，不能後續照印 PASS。

### A. 舊 bug 重現

先在舊程式讓隊長搜尋 FOUND，保存 route/cursor，立即提出普通兵不同目的地請求，證明 route 被清除。新程式普通兵不能操作隊長搜尋入口；模擬全軍步進時 route hash 保持不變、cursor 單調直到完成。測 PENDING、READY、預算耗盡三種狀態。

### B. 真正指令的三層下降

確定性夾具 3→2→1→0，三個错位 reciprocal ramp，至少一次必须先遠離終點。高台四周不能碰到任何真實地圖邊緣；只在低地保留一個可達的邊界出口，避免選到同高度邊緣使測試失效。圖上足夠放 100 人與出口集合區。

呼叫 issue_command(MOVE_TO_EDGE)，99 人全程啟動跟隨，不手寫只有 desired_cells[0] 的孤立測試。独立 oracle 確認存在合法路徑。要求隊長造訪 [3,2,1,0]、到真實邊緣、99 人全到低地集合區。逐步檢查 can_step、唯一 owner、有效 reservation。

隊長時間上限取 oracle 路長×實際步行時間＋搜尋與隊伍等待額度，整軍至少給 120s、依窄口數量／路長提高到合理上限；時間到列位置、階層、route cursor、blocker，不能放寬到「有任何人還在動」。

### C. 陣型與集合

開闊地東南西北各走 20 格；隊員跟隊長當前位置，不能朝未抵達終點散開。保持 slot 身份，拐彎不重複格。PLAYER 停止後 20s 內完成合法集合；繼續移動能再次跟隨。

無衝突夾具100人各走20格：95%首次啟動≤0.3s；完成時間≤5.5s（0.24×20=4.8s＋調度）。此為排程測試，不代替實際隊形測試。

### D. 狹口

單格雙坡道、S 形彎路、出口只有小平台各一例。所有99人必須通過，不允許已到達士兵封出口。完整寬陣型無法容納的小平台須保留縱隊／受限陣型。記錄最長無 committed step 時間；未完成時超过5s無進度需輸出 blocker 診斷，不可靜默僵住。

### E. 無路與生命週期

封閉高台無 reciprocal ramp → UNREACHABLE_BOUNDARY，不能穿崖或選內側目標。途中改 FOLLOW／EDGE、交換中換指令、Generate後部署、連續 clear/deploy，均不得使用舊 route、舊 reservation。

### F. 實際生成圖與視覺

挑 TERRACED_HIGHLAND／ROCKY_HIGHLAND 各一個確有3層可達邊緣的 seed，保存 fingerprint、起點、終點、坡道座標。全隊使用正式按鈕命令。若 seed 無足夠連通，記錄並另選可達案例，同時保留無路案例；不可改測試資料後冒稱原始生成圖。

相機對準隊長與坡道，暫停自動 simulation 後按固定 advance_frame 推進，等待 frame_post_draw 再截圖。畫面需顯示：高台開始、第一/第二/第三坡道、隊尾過口、最後集合。可另附全景，但局部證據必須看清隊長。上一輪截圖隊長在上緣被裁掉，不能繼續用它宣稱方向與下山通過。

四向動畫以實際走格測，查 editor 真正 yaw／動畫播放時間並看圖；不可只把預期映射函式回傳值跟同一映射比較。

### G. 效能與前進量

2560×1440、100×100、100人；記錄GPU、renderer、zoom、VSync/cap。平原跟隨、三層下山、狹口各暖機5s、動態採樣20s。採樣起點在暖機後重置。

列 P50/P95/P99/max、>33.3ms/>50ms幀數、每秒 captain committed steps／全軍 committed steps、最長停滯、已集合數、搜尋展開量、丟棄simulation時間。完成後的 idle 單独列，不能混入動態樣本；效能目標P95≤20ms、P99≤33.3ms，若未達報實值。先滿足全隊真的通過與集合，不能降低模擬吞吐量換FPS。

## 10. Luna Max 完成回報

列主要修改檔案、隊長route失效根因的回歸結果、正式EDGE命令下跨層序列和邊界座標、99人過口／集合結果、實測耗時与FPS、已人工檢查的圖片／影片，以及仍未通過的具體案例。

只有隊長尋路成功、隊員持續跟隨、狹口全隊通過且恢復可用陣型，才算完成本方案。尚未完成的階段保留未完成標記，不寫「已完成最小切片」代替三項要求。
