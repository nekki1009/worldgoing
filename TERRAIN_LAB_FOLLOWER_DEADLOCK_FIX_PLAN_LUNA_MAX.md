# Terrain Lab 隊員卡住：邏輯稽核與 Luna Max 修改方案

> 2026-09-09 第二輪稽核：第一次實作後仍有山口卡住與假完成缺口。山口導航、讓位、完成判定與驗收請以 [V2 改善計畫](TERRAIN_LAB_FOLLOWER_PASSAGE_FIX_V2_LUNA_MAX.md) 為準；下文保留原始稽核，不代表目前已完成狀態。

日期：2026-09-09。執行對象：gpt-5.6-luna，reasoning effort = max。

狀態：已完成現行程式靜態追查；本輪只新增方案，未修改遊戲程式、未執行 Godot、未重現使用者當下地圖。下列「已確認」指程式分支與資料生命週期；具體發生頻率和玩家案例仍須以回歸測試與實際生成圖確認。

本方案是 `TERRAIN_LAB_FORMATION_MARCH_AND_RUN_PLAN_LUNA_MAX.md` 的卡住修正補充；重疊的導航、預約、過口、完成判定以本方案為準。保留既有跑步、寬陣型與呈現要求。舊文件的現況表已有過時項目，不可據此重做已存在的功能。

稽核基線：`scripts/terrain_lab/terrain_army.gd` SHA256 = `C8DE5FF7D338162FC07EF1C569352D6891963E5BA4CEF69A45F6AEFD1878C32E`。行號供定位，實作前重新查符號。工作區已有大量未提交修改，Army 與相關測試目前是 untracked；不可清理、覆寫或整批提交。

## 1. 先理解目前實際控制流程

`terrain_lab.gd::issue_army_command` → `TerrainArmy.issue_command` → FOLLOW 更新隊長目標／EDGE 選一個邊緣目標 → `_update_formation_targets` 指派隊員格。

`advance_frame` → 固定 0.1 秒 `_simulate_step` → FOLLOW 重規劃 → 完成移動／交換 → 推進 push → EDGE 提前解除瓶頸與 rebind → 更新陣位 → 逐人選格／預約／讓位 → 更新集合數 → 5 秒 rebind。

隊員的路徑入口為 `_next_step(index > 0)` → `_next_follower_step` → 高度不同時選 trail 坡口 → Manhattan 貪心 → 有限 BFS 的第一步 → blocker／push。隊長專用 `_find_path` 已存在所有權保護，本次不要把舊版的 route 被士兵覆蓋當成仍未修復的根因。

## 2. 已確認的缺口與最小反例

| 優先 | 位置（terrain_army.gd） | 程式證據與後果 |
| --- | --- | --- |
| P0 | 1093–1244 `_local_step_toward`／`_next_follower_step` | BFS 只回第一步，不保留路徑；下個 tick 優先走 Manhattan 下降格，會撤銷必要的繞路。即使真的移動，`blocked_time` 也歸零，無法識別折返活鎖。 |
| P0 | 916–935、2010–2026、2099–2106 | EDGE 隊長到邊緣就解除瓶頸；全員同高度且 OPEN 即取消移動並把 desired 改成目前 cells。FOLLOW 在集合少於 90 時，即使仍有人移動也能累計 5 秒後 rebind。散落現地可被改判 99/99。 |
| P0 | 1925、1949、2163–2178 | 遞迴讓位直接預約尚未離開的 source 給 requester；没有對應交易記錄／取消清理。`_complete_move` 只刪目的格預約。requester 改目標、轉向或走其他路後，舊 claim 可能永久留下。 |
| P1 | 1748–1905、1503–1522、1907–1978 | push 只鎖 unit，沒有保留逐段釋放的空格直到 requester 入格；交易完成在 requester 消費前解鎖。隊長交換與遞迴 blocker 未共同遵守 push lock。可能被搶空格、反覆重建或打斷交易；需要競爭案例驗證。 |
| P1 | 768–823、862–883 | 排隊只在 trail 長度 ≥101 才啟用；短坡道不能用此保護。進度以最近 Manhattan trail 格猜，精確重複格回第一個索引；同高度隔牆、S 彎、折返可判錯。FOLLOW 又要求舊 column slots 全部 settled 才解除，目標仍在坡口前就沒有真正的過口終點。 |
| P1 | 978–989、1125–1155 | preferred 只驗 walkable，沒有共享場可達檢查；fallback 才檢查。高度相同直接追 slot，高度不同則找最近的同高度離開邊，沒有路段次序。可能指派孤立平台、錯誤坡口或要求回頭。 |
| P1 | 1158–1172、1225–1244 | EDGE 落後高度 rescue 每人直接 BFS，不扣四次局部預算；其他人可能同一輪 free BFS 後再 occupied BFS。1024 展開用完與真正無路都回 INVALID，反覆重搜仍可能沒有進展。 |
| P1 | 1199、1246、1571–1593、2077 | 普通兵交換只允許 COLUMN；OPEN 的相互占位不能走此解法。主調度雖呼叫交換，guard 仍拒絕，不能把「有呼叫」當「能解開闊地互鎖」。 |

其他已確認事項：`_formation_passed_count` 只有宣告／clear，沒有過口計數；`is_formation_complete` 只對照可被改寫的 desired，未驗證過口或整隊形狀。`_ensure_distance_map` 把 PLAYER/NPC 當障礙，但快取 key 只有 origin；NPC 移開後可能沿用過期不可達結果。`_route_width` 整段用一個 heading、累加 lane 數，未要求橫向連續連通，不能據此保證出口可供整隊展開。

### 2.1 不必依賴大地圖的繞路反例

平地、x/y 非負；隊員 start=(1,1)，goal=(3,1)。堵住 (2,0)、(2,1)、(2,2)，出口在 y=3；其餘需要的格可走，其他人放遠處。

合法路線必須先 (1,1)→(1,2)→(1,3)。現行 BFS 能選到 (1,2)，但到此後 (2,2) 被擋，貪心卻可選 (1,1)，於是回頭。這是由分支可推導的反例；Luna 必須先把它跑成舊版失敗、新版通過的 GDScript 測試，不能把本段當已執行結果。

## 3. 不可變的完成契約

1. 保留 TerrainArmy 單一模擬 owner、隊長專用全圖 route、99 人 baked atlas、既有速度與動畫；不另建導航 manager 或每兵全圖 BFS。
2. `cells` 是已提交格；`moving_to` 是未完成目的格；`_cell_owners` 與預約是一格一 owner。普通移動與交換每一條邊仍須通過 `TerrainData.can_step`。
3. 不以增加速度、提高 timeout、減少兵數、取消一半步、忽略占格、放寬坡道規則修卡住。
4. 完成必須是：99 人都完成要求的通道序列、進入合法集合區、到唯一有效陣位，無未完成移動／交換／push；不是只有隊長抵達、全員同高度或計數回 99。
5. 不夠 99 個集合格就顯示受限／等待集合空間；合法窄陣可以另有明確條件，但不得報已恢復寬陣。
6. 改命令時撤銷未開始的意圖與舊交易，已開始的合法一步正常完成後再接新目標。clear／重新部署是不同生命週期，清除全部陣列和導航狀態。

## 4. 實作階段（依序，不以最後補救掩蓋前面錯誤）

### A. 先建立能抓真卡住的測試，移除假完成

檔案：`scripts/tests/terrain_lab_army_test.gd`、`scripts/tests/terrain_army_formation_smoke_test.gd`；必要時新增單一 `terrain_army_follower_navigation_test.gd` 集中本次反例。

- 先建立第 7 節 A–D 的測試，保存修改前失敗原因。
- 刪除 `_rebind_stalled_open_formation` 的「全員原地改目標」補救與兩個呼叫點。允許在已確認的合法 slot 集合之間重新配對身份，不允許把任意現地集合變成新的 slot 集合。
- 刪除 EDGE 到邊緣就清瓶頸的分支。隊長完成與全員過口分開。
- 不再讓 timeout 修改 desired 或重置集合狀態。只記錄等待原因並觸發有界重規劃。
- `_update_formation_status` 不得蓋掉阻塞原因；可保留簡短 command_status，等待原因用獨立欄位呈現。

階段出口：散落同高度、上層掉隊、仍在動但小於 90 人集合，均不能靠等五秒自動完成。原有測試此時失敗是必要訊號，繼續修正導航，不把 rebind 加回去。

### B. 保留繞路決策，分清搜尋結果

沿用 `_local_step_toward` 的 BFS，調整為產生可消費的小段路徑，保留隊員的局部 route、cursor、goal。資料放 TerrainArmy，僅實際繞路者配置；不要複製隊長全圖工作區 99 次。

- 有有效 detour 時，優先消費下一格，不再先走 Manhattan。cursor 只在 `_complete_move` 確認完成該格後增加。
- 同一陣位／通道階段下，暫時被友軍占住只等待或讓位，保留 route。實際目標改變、地形失效才撤銷；保留已在途的一步。
- 統一所有局部搜尋入口（含 EDGE rescue、遞迴 blocker）使用既有配額：初始仍每 simulation tick 最多 4 次、每次 1024 展開，明確列每 render frame 的累積上限。不得另開免預算救援。
- 回傳至少區分 FOUND／BUDGET_EXHAUSTED／UNREACHABLE／WAITING_OCCUPANCY。無法在預算內找到路不等於地形不可達。
- 遠距離接近坡口使用現有共享地形距離場，不要求局部 BFS 一次搜完整遠端路線。局部 slot 繞路才用上述小路徑。
- 進度計時基於局部 cursor／通道進度或已發布距離場的改善；普通來回步數不能使「無進度時間」永遠歸零。暫時背離目標的合法 detour 以 cursor 推進算進度。

階段出口：牆角反例到達；U 形與同高度 S 彎可通過；被人暫堵能等待後續行；不把 BUDGET_EXHAUSTED 當永久無路。

### C. 收斂讓位與預約生命週期

優先重用 `_pending_pushes`；移除遞迴分支在交易之外寫 source reservation 的做法。單格讓位也視為同一種小交易，避免另一套 lease 管理器。

每筆交易至少記 requester、unit/cell 鏈、cursor、進度時間、尚未消費的格；原有欄位能用就沿用。明確寫出 start → 各 blocker 完成 → requester 完成 → release 的生命週期。

- 找鏈只選可參與且未鎖定的單位。不能找到一條經過鎖定者的鏈後反覆拒絕，而永遠不考慮可用替代鏈。
- 正在移動的單位若不屬此交易就當暫時障礙；不能回傳 true 就視為願意向指定格讓位。
- 保留每次釋放格的下一位消費權，防止被已到位者回填或其他兵搶走。保護到 requester 實際入格才釋放，不在最後 blocker 完成就整筆解鎖。
- 隊長交換、隊員交換、普通排程與遞迴入口全部遵守同一 transaction lock。遇鎖等待；不要用交換偷偷移走 transaction 裡的靜止 unit。
- reserve 只在未被他人持有時提交；禁止覆寫他人的預約。release 使用 `_clear_reservation(cell, owner)`，不能無條件 erase 或清整張字典。
- `_complete_move` 提交前核對 source owner、destination reservation owner、合法邊及無其他 destination occupant；失效保留已提交 source，釋放自己資源並記診斷，不能覆寫別人的 owner。
- 交易逾時以最後一次實際進度計算；命令改變／失效時取消未開始部分。已在途者完成後清理，不能倒回半格動畫。
- 開闊地兩兵互換目標可使用既有原子 swap，但需明確的互換意圖、合法雙向邊與空閒預約；三兵環可用同一讓位交易引入附近空格。不要無條件允許所有兵彼此換位。

階段出口：讓位／取消／命令切換後不存在孤兒預約；競爭者不能搶交易中釋放格；隊長不能交換走被鎖的 blocker；結束後 lock 和 pending 全清。

### D. 真正的過口進度與出口集合

停止以「trail 至少 101 格」作為隊列成立條件，停止用最近 Manhattan trail 格代替通過進度。沿用已有陣型模式，新增最少的通道路段資料和每兵進度，不建立另一個陣型控制器。

- 通道記錄入口、出口、沿合法 route 的路段及寬度。隊長沒全圖 route 的直行段，也須以其合法前看步驟辨識狹口，不能空 route 就永久視為寬路。
- 跨高度／同高度狹道都適用。高度只是通行資料，不能當平台身份或通道完成證據。
- 每兵分辨接近入口／通道內／已出通道；只用已完成合法邊推進。trail 有重複座標時保留路段索引，不從座標反查第一次出現位置。
- 排隊順位由入口接近順序／已提交進度建立，同一通道內固定；不能按 unit id 每次重排。兩格連通坡道維持兩列，離散不連通 lane 不相加。
- 已出通道的人立即移往出口側集合 slot，禁止把入口、通道與必要出口疏散格當 ARRIVED slot；保留後方通行空間。未出者仍走同一入口與路段。
- 隊長停下不影響隊尾出列：前排持續向集合區疏散、後排依次通過。不能要求99人先全部到舊 trail slots，才給出口集合目標。
- 三層下降可同時有隊員處在不同路段；保留隊尾仍需的舊通道，直到所有人通過。隊員不能跳到「最近的同高度坡口」。
- 保留一份可重用的共享地形場來接近當前需要的入口／集合區；若不同階段需要不同根，按需輪替少量仍活躍的場或分批處理，不配置每兵全圖場。明確處理待建構期間的等待與既有有效路徑。
- preferred 與 fallback 使用同一合法性條件：唯一、可達、在指定出口側集合區、不占保護格。可達不是只檢查 walkable，也不能選整張圖上任意近格。
- 距離場只包含靜態地形連通；PLAYER/NPC 的暫時占格在排程時判斷，避免人物一站坡口就把整側永久標無路。若沿用動態場，必須有外部占格版本失效機制，兩種選一種，不混用。

階段出口：短坡道、同高度窄道、三個错位坡道，兩個正式命令都讓99人通過並集合；無足夠空間的案例明確受限而不假完成。

### E. 診斷與驗證後再調效能

沿用 `terrain_lab.gd` 現有 HUD 增加最小資訊：已過當前通道 n/99、已集合 n/99、最久無進度兵號／秒數、主要等待原因。不要每 tick 拼99人的字串。

測試失敗或個人無進度超過5秒時輸出一次快照：unit、cell、goal、下一格、route cursor、通道階段、blocker、reservation owner、push requester／cursor、搜尋結果。完成步數另列，不能替代進度。

## 5. 完成狀態與不變量

`is_formation_complete` 除99人到有效陣位外，須驗證通道全部通過、有效集合區／陣位集合、無 pending push／swap／moving。隊長抵達按所發命令檢查目標；不要僅以碰到任意邊界代替命令目標。

每個 simulation tick 的測試檢查：

- 100個已提交格唯一，`_cell_owners` 與 cells 雙向一致。
- 每個 MOVING 的目的格都有正確預約；swap 是明確的雙人原子例外。
- 每個預約都能追溯到在途移動、swap 或仍活躍的讓位交易，不存在無消費者 claim。
- 每個 lock 都屬於活躍交易；結束、clear、重部署後無殘留。
- 每次提交符合 can_step；沒有因重規劃或 timeout 導致非相鄰位置改變。
- 99個發布陣位合法唯一；集合完成人數另外由測試的通道邊紀錄／集合區判斷，不只讀 production counter。

## 6. 建議修改檔案與停止擴張的界線

| 檔案 | 修改內容 |
| --- | --- |
| `scripts/terrain_lab/terrain_army.gd` | 去 rebind、保留 detour、預約交易、過口進度、合法陣位與完成判斷 |
| `scripts/tests/terrain_lab_army_test.gd` | 強化全隊正式命令與每步不變量 |
| `scripts/tests/terrain_army_formation_smoke_test.gd` | 寬陣實際位置與99人集合，不接受只有90人或偽完成 |
| `scripts/tests/terrain_army_follower_navigation_test.gd`（必要時新增） | 本次小型卡住反例與取消／競爭測試 |
| `scripts/terrain_lab/terrain_lab.gd` | 最小診斷顯示 |
| 既有 army visual／performance tests | 實際幀流程與動態進度證據 |

先不改地形生成器、TerrainData.can_step、戰鬥、角色資產、World/Region/Site。若 oracle 證明生成圖無路，另報地形問題；不能為了通過測試修改地圖通行規則。外部角色過渡占格有另一個呈現／碰撞議題，本次除非實測證明它是阻塞根因，勿擴張重寫角色移動。

## 7. 必跑驗收矩陣

所有整隊行為測試走 `advance_frame(1.0 / 60.0)`，禁止同時開自動 process 造成雙重推進。小型函式反例可直接调用 helper；不能用它代替完整幀流程。

| 案例 | 輸入／要求 | 成功條件 |
| --- | --- | --- |
| A 繞路折返 | 第2.1節牆、U形牆、同高度S彎，其他兵放遠 | 依合法路徑到達，detour cursor前進，不反覆兩格折返 |
| B 假完成 | 散落但同高度、上層留1人、FOLLOW仍有移動且集合<90；各超過5秒 | 不重寫現地為全部slot，不顯示完成 |
| C 孤兒預約 | 一格讓位後requester改目標；遞迴讓位取消；交易中FOLLOW→EDGE | 在途一步完成後預約／lock無殘留，不撤回插值 |
| D 空格競爭 | 三人以上push鏈，第三者爭搶釋放格；隊長欲交換鎖定兵 | 原requester合法進入，第三者等待；無搶占／owner覆寫 |
| E 開闊地互鎖 | 兩兵互換slot、三兵環且旁有空格；100人四向轉彎 | 解鎖並落位；目標slot集合未被任意現地替換 |
| F 短窄道 | trail<101、平地單格道、单格坡道，FOLLOW/EDGE各一次 | 每名隊員提交通過出口邊且集合，不能只看隊長 |
| G 寬坡／受限出口 | 兩格連通坡與兩條不連通lane；小出口平台 | 正確可用寬度；空間不足不誤報寬陣完成 |
| H 三層下降 | 3→2→1→0，错位坡道，只有低地真邊緣 | 每名隊員按序跨必要邊，到出口側集合區並落位 |
| I 外部暫堵／無路 | NPC暫堵唯一入口後移開；另有真正無坡封閉平台 | 前者續行；後者報不可達且不穿崖 |
| J 生命週期 | 在途、swap、push、搜尋中切命令；clear/deploy | 無過期route、claim、lock，舊結果不提交到新軍隊 |
| K 正式生成圖 | TERRACED_HIGHLAND、ROCKY_HIGHLAND，各保存seed/fingerprint/起點/坡道 | 獨立oracle確認可達，再驗99人實際過口；另保留無路案例 |

時間上限在測試開始前固定：小型A/C/D案例10秒；開闊地停止後30秒；短窄道120秒；三層下降240秒。這是初始驗收上限，不是已實測值。若oracle路長／通道數的保守通行時間已超過上限，先列公式與增加理由；不得失敗後只調大timeout。5秒個人無進度先診斷，正常排隊仍可等待，整體deadline到則FAIL。

動態效能沿用既有設備設定，暖機後才計 moving sample，至少包含平地與窄道；列P50/P95/P99/max、每秒實際步數、每兵通過數、搜尋展開／配額、最長無進度。不能用停住後60 FPS宣稱性能通過。

視覺證據至少入口排隊、出口疏散、隊尾通過、最後寬陣；鏡頭包含隊長及坡口。數據通過後仍需看圖，不能只產圖不檢查。

## 8. Luna Max 執行與回報要求

開始前讀本方案、現行檔案與適用技能。Godot驗證依 `godot-runtime-verify`；背景工作依本庫AGENTS要求立即設定watchdog，持續監看，不能背景啟動後遺忘。若工具不提供必要timer，採有明確timeout且前景等待的驗證方式，避免無監看的背景程序。

按A→B→C→D→E實作，每階段保存相關回歸結果，最後跑整合矩陣。不需每改一行重跑全部Godot；完成一個有意義階段再跑對應測試。

最終回報需包含：根因與修改函式、舊版反例失敗／新版結果、每項矩陣PASS/FAIL/未執行、99人通過與集合實數、完整錯誤與exit code、seed與截圖、效能实值、未提交檔案。SCRIPT ERROR/assert失敗即失敗；timeout不是PASS；只有編譯通過不代表隊員不再卡住。

本方案不得因「目前顯示99/99」或「有任意一人在動」提早結案。尚未通過的案例保留明確未完成標記。
