# Site 200 人即時戰鬥優化

2026-09-14 最新短動畫修正：不改交鋒節奏／傷害／移動，只接入短招與連箭視覺接續。同場原 200 人／40 射手／60 秒，修改前 **282.39 FPS／P95 14.884 ms**，最終 **254.97 FPS／17.673 ms**；1,031 次交鋒、800 發、218 包圍步、3,935 Nodes 相同，26 項原門檻通過。**仍有可觀測退步，不是已證明的加速或零代價**；同次取樣去重亦未量到整場收益。[本輪各次數據、來源與限制](output/site_exchange_animation_20260914/README.md)。下方包圍輪 305.02 FPS 是較早資產／時點，不代替本輪基準。

2026-09-14 最新接戰包圍：原 200 人含 40 射手、60.026 現實秒，218 個包圍步、1031 次交鋒、800 發，平均 **305.02 FPS／P95 14.142 ms**，26 項門檻通過；[資料、真畫面及邊界](output/site_encirclement_20260914/README.md)。平地／全軍可見 zoom 0.35，非任意場景保證；下方遠程初版 340.24 FPS 是未包圍版本，戰鬥工作量不同。

2026-09-14 最新遠程實測：相鄰近戰＋落點遠程，200 人含 40 射手、60.005 現實秒，平均 **340.24 FPS／P95 13.853 ms**，800 發實際扣彈與結算、25 項門檻全通過。[原始資料／操作／驗證界線](output/site_ranged_20260914/README.md)。指定平地、zoom 0.35、全軍位於正常 HUD 左側；不可與下方不同鏡頭／精確規則直接計算加速，也不是全地圖 FPS 保證。

2026-09-14 最新玩法替換：使用者已授權相鄰能力交鋒。新模式實作／首版數值見 [交鋒規則](SITE_COMBAT_EXCHANGE_V1.md)，目前驗收與原始資料見 [新模式實測](output/site_exchange_20260914/README.md)。下列精確碰撞 FPS 是歷史基線，不是新模式當前狀態。

新授權接續：[GPU 骨架／頂點批次與原 200 人流暢驗收計畫](SITE_COMBAT_GPU_PLAN.md)。先驗傳輸／同步淨成本與原值，再擴同一步批次；尚未取得 GPU 流暢 PASS，以下所有舊結果原樣保留。

2026-09-13 使用者新要求：優化到可以流暢戰鬥。前一輪首版功能完成不代表本目標已完成；本輪仍在實作與驗收，不以短測或手動批次 FPS 宣稱成功。

## 目前狀態（2026-09-14 03:08；附近候選對照完成，未證明穩定收益）

已完成 5,091 案與原六人各 141 步真命中重播，完整接觸／人物／封包／Source 鍵順序一致。修正兩個測試錯誤後，首次 full60 發現相機縮放不一致，保留但不當嚴格 FPS 對照；補上自動測試相機／視窗逐幀守衛，再跑同來源 `970195c88e362386`、固定視角的 200 人 OFF／ON。

修正版 OFF／ON 平均 **16.611786→18.022862 FPS**、P95 **218.934→208.707 ms**，但最後完整十秒 **6.6→5.9 FPS**。這組平均差約 +8.49%，不是等工作量／穩定收益保證；查詢量、原生幀間隔與戰鬥進度不同。ON 確實將本場遍歷列數 **12,946,000→6,442,219**，但兩場各自同尾段輸入的搜尋中位數皆更慢（ON 輸入 **3,627→4,249 µs**；OFF 輸入 **578→2,173 µs**，均含建索引與排序）。少掃人未能解決尾段卡頓，不將此候選設為預設。

**交付 `contact_buckets_enabled=false`；原疲勞、200 人、120 Hz 與命中規則未改，流暢計畫仍未完成。** 11 次驗證全部紀錄保留（2 個修前 FAIL／9 PASS，PASS 不等於性能過關），四場最終畫面實際檢視。使用者已取消每次失敗停下詢問的規則，`AGENTS.md` 改為明確定位後自主修正重驗，canonical helper 不變。[全部規則、數據、驗證與限制](output/site_contact_buckets_20260914/README.md)

## 前次狀態（附近候選索引首測失敗已修，當時待重驗）

依新同意試作本步 256 px 位置分區，只減少碰撞前遍歷名冊，保留原 anchor 排除、倒地／移動列、第一列特例、候選順序與原幾何／傷害。`contact_buckets_enabled=false`，未啟用正式路徑；本輪沒有更改疲勞規則。新增候選計數、5,091 案契約、原六人命中重播與 realtime 尾段原輸入重播入口。

第一個 headless `20260914_025047_200` **FAIL／exit 0／2.911 秒**：条件運算式產生未定型 Array，不能賦值給 `Array[int]`。已改成明確整數陣列後 append，並加「5,091 案必須全完成」檢查，避免腳本錯誤後僅印出的 27 案 PASS 誤導；canonical helper 正確判 FAIL。依驗證技能首錯停止重跑，**修後未重驗，GPU／full60／收益均未取得**。上一輪 18.36 FPS 不是這次索引的結果。[實作、失敗紀錄與待續順序](output/site_contact_buckets_20260914/README.md)

## 02:29 歷史狀態（簡化碰撞試版有改善，仍未流暢）

使用者同意試作放寬模型輪廓精度。以同來源原 200 人／120 Hz 最大子步／60 現實秒比較，原版 **15.863350 FPS／P95 322.800 ms**，簡化初版 **19.496032 FPS／196.669 ms**，末十秒 **3.6→6.5 FPS**。這是一組不同碰撞規則與不同戰鬥歷史的觀測，不是等工作量或穩定 +22.9% 保證。最後修正 Actor／Army 代理肩點並加既有輸入重用為 **18.360606 FPS／196.077 ms／末十秒 6.2 FPS**；來源已不同，沒有額外加速證據。

試版用原離線資料生成 289,112 bytes 的十部位矩形、武器／盾／招架輪廓，按真實動作時間插值；護甲改讀命中部位的實裝防護。保留空間連續掃掠、原人物／疲勞／死亡搜刮／物品守恆，不改成人數減少或機率扣血。共享 Source 量測窗口新增取樣為 0，但原 Actor 呈現／IK、逐步收集、威脅與導航工作尚在；不是 GPU 實作或已移除全場骨架成本。

**交付：`combat_proxy=null`，只在 `--coarse-proxy` 測試注入；正式戰鬥未替換。** 140 軌／四向、插值、缺裝、部位護甲、快取與真掃掠契約通過，八次驗證均完整結束；候選独立性能門檻仍 false，原 30 FPS／P95／尾段／現實跟時目標均未完成。兩張靜態畫面已檢視，不是動態手感或全武器／騎乘驗收。本輪不再追加試驗。[規則、完整量測與證據](output/site_combat_proxy_20260914/README.md)

## 01:58 歷史狀態（延後輪廓無有效改善，已撤回）

同來源、200 人、各完整 60 秒：原版 **14.5351 FPS / P95 338.289 ms**，延後輪廓候選 **14.6823 FPS / P95 346.734 ms**；末十秒皆 **3.7 FPS**。teams_sample **33.045→33.219 秒**，query＋exact 幾何收集 **17.738→18.024 秒**；只是把一部分成本搬到 query_bounds，沒有證明整场淨收益，兩場 targets_met=false。姿態取樣與投影仍在，不能把本次說成完整 bounds-only 或 GPU 實作。

64 組查詢／141 步實際傷害重播通過，但只讀審查另發現尚未覆蓋的 128-key 淘汰姿態歷史缺口。已撤回本次 runtime／測試修改並驗證與原 hash 相同，只留測量與可恢復試版快照；不疊加無收益開關。[全部數據與驗證紀錄](output/site_deferred_hulls_20260914/README.md)。流暢目標沒有完成。

## 前次紀錄（2026-09-14 01:28；Source幾何接入無淨收益，預設不啟用）

已接回原Source的真實geometry miss與armor miss，保留原姿勢/快取/partial/first-fit與結算owner。這是幾何後端，不是前一節離線完整Pose/Query/Batch取樣直接上線。實際扣血141步/1 hit＋後續8步、三組原歷史4/65/8 cases及35項生命期檢查通過；修正過回傳Dictionary鍵型別與managed view退出釋放，不回改原FAIL。

| 同來源、同200人/裝備/observer，完整60秒 | 原版 | C#幾何 | C#＋既有輸入重用 |
| --- | ---: | ---: | ---: |
| 平均FPS | 14.4705 | 14.3292 | 14.7064 |
| P95 ms | 330.283 | 353.875 | 348.532 |
| 末完整十秒FPS | 3.8 | 3.1 | 3.3 |
| 推進戰鬥秒 | 35.7301 | 33.9439 | 34.3198 |
| teams_sample 秒（含子段） | 32.7474 | 34.2296 | 33.6409 |

三場来源指紋完全相同、各200人/20死亡/180存活/1,018物品/4,781 Nodes；完整量完不等於效能PASS，三場都`targets_met=false`，且render delta/戰鬥進度不同，不能宣稱等工作量或穩定的百分比收益。C#確實處理18,442次完整幾何與74次護甲；但準備5.002秒、幾何3.976秒，前段整理抵銷局部節省。ordinary bounds16.935秒包含在collect_geometry19.968秒，narrow只有0.592秒，不能把嵌套時間加總或只搬narrow便外推全段收益。

**交付設定：compiled_geometry=false、contact_input_reuse=false，兩者都不採用為預設優化。** 原GPU仍未接入；全計畫未完成流暢驗收。下一段需減掉既有owner中的request/view/bounds重複整理，保留同步命中歷史，先做完整輸入/結算等價，再量含資料轉換的全成本。原200人/120Hz/30FPS/P95/尾段/現實跟時門檻不降。[原始JSON、全部失敗及驗證記錄](output/site_compiled_contact/README.md)

## 00:42 歷史狀態（C#受限離線流程試驗通過，非本次Source接法）

使用者已同意試作 C# 建置與批次純計算方向。`worldgoing.csproj` 與四個 test-only helper 已建置，原動畫／原骨架／原網格、同一原人物 owner 與傷害规则保持；**沒有切换正式戰鬥入口、改 120 Hz、減人、改命中精度或改存檔**。候選實際仍混合 C# 與 Godot 原生插值／幾何／排序，尚未多執行緒化或使用 GPU 計算。

最終原流程捕獲重播含姿勢、幾何、接觸、護甲與原傷害封包；每組同一程序內三輪暖機中位數如下。描述／view 編譯、場景建立、人物前進、HP 結算及畫面不在計時範圍。

| 真配裝測試流程 | 原路徑 | 候選 | 耗時減少 | 正確性 |
| --- | ---: | ---: | ---: | --- |
| 持盾、輕皮甲，56 次查詢 | 76.848 ms | 49.146 ms | 36.05% | 2 shield contacts／2 原封包，護甲值 (12,4) exact |
| 同原人物不配盾，330 次查詢 | 281.603 ms | 147.891 ms | 47.48% | 135 contacts／2 去重後 body 封包，待結算 30 HP＋24 stun exact |

新 13 案原 pose／effective time／geometry oracle、268 案／831 hits query gate、雙 view 隱藏換裝歷史 134 checks 通過；人物 HP／KO／物品全程未被套用或修改。未新增任何 200 人 full60／FPS／人工動態畫面驗收，不以局部收益乘到舊 14 FPS 結果。最初直搬 C# 曾更慢，保留失敗計時與後續分段定位，不只報有利版本。[完整實作與原始證據](output/site_compiled_contact/README.md)

下一個必要關卡是沿原 Source 的**實際 cache-miss 序列**接回完整歷史，保持 cache-hit 不 seek、partial weapon／armor restore、配方／held／morph／first-head-fit invalidation；再擴其他動畫／瞄準／裝備與原結算。此試驗仍只准入兩種真配方、左右向 idle／walk_slash，不能直接按人物分割可變共享 Source 或稱整個計畫完成。

## 20:34 歷史狀態（兩項減少重複工作的試作已完成，當時尚無 C# 模組）

**仍未達流暢／30 FPS。** 本次只實作並驗證「武器只遍歷原 `Weapon_*`」與「原 Lab 同一批次重用 Source 結果」。沒有改 200 人、1,018 物品、原 120 Hz 最大子步、命中規則、時間尺度或傷亡／搜刮；沒有建立 C# 模組、降低頻率或實作 Actor 延遲姿態。

交付選擇：`weapon_mesh_filter_enabled=true`；`same_batch_result_reuse_enabled=false`。武器篩選只縮小原生有序候選，原即時可見性、武器鞘排除、柄／護手格擋、徒手與弓弩分支保留。依 ponytail 的最小修改原則沿用既有 Geometry／Source／Army／Lab，不新增碰撞或存檔 owner。第二項保留為關閉的測試候選：有局部 exact 證據，但整場沒有額外加速證據；OFF 直接呼叫原 Source，不建立結果項目或深複製輸入，仍有少量旗標／generation／解除引用成本。

### 最終預設優化配置的 60 秒對照

兩場同一份來源（`7581d07b02ec281f`）與初態，只有武器篩選開關不同；cheap／centered／fatigue-zero／contact-inputs／result-reuse／dedup／fixed120／strict／cull 全關。這是 **預設優化開關組合**，但仍用 test-only scalar m25 catalog 與原量測 observer，不是正式 32 配方全資產准入或完全無量測負擔的發行版。

| 指標 | 關閉對照 `203106_250` | 交付配置：武器篩選開啟 `202910_495` |
| --- | ---: | ---: |
| frames／現實秒 | 906／60.064757 | 914／60.219254 |
| 平均 FPS | 15.083720 | 15.177870 |
| P95／最大間隔 ms | 349.176／459.278 | 327.452／518.605 |
| 動作秒／input-wall | 35.333333／0.588254 | 36.553439／0.607006 |
| 原 Lab CPU ms／動作秒 | 1,340.076 | 1,287.638 |
| Source 武器 μs／產生次數 | 2,014,422／7,302 | 644,463／7,446 |
| 最後完整十秒 FPS | 4.0 | 4.6 |
| `targets_met` | false | false |

武器區段每次成本約下降 **69%**，但整場平均只差 **0.094 FPS**，不能宣稱有明顯整場加速或流暢。P95 仍約 0.33 秒且最大單幀反而較長。兩場 native delta、動作時間、補位／疲勞狀態不同，並非完全等量的全場重播；CPU／動作秒正規化也不能消除工作量差異。原報告：[關閉](output/site_army_combat_realtime/7581d07b02ec281f/mixed_equipment_full60/1789302669_2037954/measurements.json)、[交付配置](output/site_army_combat_realtime/7581d07b02ec281f/mixed_equipment_full60_weapon_filter/1789302553_2017420/measurements.json)。

兩場都保留原 200 身分、144 有效命中、20 死亡／20 地面容器、180 存活、1,018 物品守恆、4,781 Nodes 不增、HUD／BUSY／來源穩定。helper PASS／exit 0 僅表示完整量完，FPS、P95、六段各 30 FPS、跟上現實時間、55 動作秒連戰覆蓋仍全部未達標。

### 前三場隔離比較與精確性

同一份候選來源 `f75da2aa1d893981`，共同開 centered＋fatigue-zero＋contact-inputs，依序測新增兩項 OFF/OFF、weapon ON、both ON：**14.009095 → 15.864962 → 15.346657 FPS**。這組 15.86 FPS 不是目前交付配置的結果。both 有 52,709 次借用命中，但每動作秒 CPU 比 weapon-only 增加約 4.76%；沒有獨立 miss 計時，不把差額全歸因於 deep-copy，也不聲稱所有情況必然更慢。五場數據、比較限制與永久原始紀錄見 [完整比較](output/site_combat_performance_20260913/redundant_work/comparison.md)。

- 男女各 88 組、共 **176 組**原 Actor／Source 武器與格擋完整多邊形／位元對照通過；四向、換裝、近戰武器、盾、徒手、弓弩等原分支均有覆蓋。原 547 個 mesh 中只遍歷 54 個 `Weapon_*`；暖機 ABBA 的長劍局部耗時下降約 67–70%，不是整場 FPS。
- 結果重用的六組實際原人物查詢／女性／瞄準／移動對照通過，最終來源再驗 `203302_303` PASS 13.741 秒；group 1 `201726_448` 五項補驗涵蓋值變更、Source 更換、128 筆步快取及 64 筆 terminal 快取清除。generation 保護包含 terminal overflow，借用只在原 contact batch 有效，結算前解除引用。
- 原 Lab `--redundant-work` 兩路各 **141 步、1 真 hit packet＋8 個命中後步驟**，逐步 HP／人物／武器軌跡／格擋與 packet 完全一致（`201809_520`）；不是全 200 人整場傷害等價證明。
- 兩次初期解析 FAIL（動態屬性的 `reuse_pose` 型別推導）原樣保留；改成明確 `bool` 後定向解析與上述 GPU 數值／整場測試通過，不回改舊 FAIL。主控已逐一查看五場各一張 `02_final.png`，共五張靜態畫面；沒有把截圖當成動態流暢驗收。

接續優先項仍是原角色姿態與接觸查詢成本；最終開啟場原 Lab `teams_sample=32.094918 s`，內含 `collect_geometry=17.261423 s`，Source 姿態為 6.326824 秒，Actor advance 為 4.623914 秒。這些計時互有包含，不相加或直接外推收益。先前提出的 Actor 按需姿態與 13 格近敵查詢 **尚未實作／未獲本次量測證明**；本次局部試作完成不等於整個流暢戰鬥計畫完成。

## 18:38 歷史狀態（保留當時等待新增建置流程確認的敘述）

**仍未達流暢／30 FPS。** 最新 centered static bound＋fatigue-zero＋contact-inputs full60 `20260913_182234_441`：919 幀／60.238876 現實秒、15.255929 FPS／P95 334.282 ms、input-wall 0.611233，`targets_met=false`；只完成約 36.820018 動作秒，最後十秒 4.4 FPS。前次 centered 的 15.594072 FPS／P95 344.144 ms、static84 的 15.050476 FPS／P95 363.779 ms 與 dynamic 的 15.025168 FPS／P95 357.818 ms 均保留，不把多項改動／不同原生 delta 的觀測差異稱為單變因收益。helper PASS 僅表示量測完整。

centered 候選的原 240 poses／309,246 頂點包含檢查保留；新增 contact-inputs 的 Army 7＋5 組數值對照與 141 步／1 真實 packet 重播通過，仍不是整場傷害等價或流暢證明。cheap-bound／centered／fatigue-zero／contact-inputs 及 dedup／fixed120／strict／cull 預設仍 false，本輪沒有改動執行頻率。原 200 人／1,018 物品、4,781 Nodes 與來源穩定不抵銷效能失敗；當前配置也不等於候選 full60 的啟用配置。另 Actor constant-morph 精確測試 `182951_249` 未通過，骨姿位元差異仍在調查，不先歸因於 compactor 或改標 PASS。

18:33–18:38 定位補充：同一原 Actor／原資源 AAAA 重播 45 組位元對照通過；但只 duplicate、不減任何 key 的 copy-only 仍重現首筆約 `7.45e-9` 骨姿差異。調查縮至 clone／資源替換／cache 流程，尚未定位內部原因；Actor production 完全未改，沒有放寬 exact 標準或新增效能結果。新的 anchor 排序提案確認與已拒絕的 `155842_280` 原型同方案，沒有新增 flag 或 production 改動。

主控已向使用者詢問是否採取 **C# 批次純運算的結構調整**：保留原規則、120 Hz 精度與原 owner，但增加建置步驟。環境已有 .NET 8／Godot Mono 不代表此新增流程已獲同意；目前等待方向確認，**尚未建立 csproj／module，也不承諾此路線必能達標**。本輪文件／證據收束不是流暢戰鬥完成。

### 先前狀態與量測歷史（保留當時敘述）

預設路徑最新已完成整場量測為 `20260913_160052_088`：**完整混合配裝 60 秒現實窗口已量完，仍 `targets_met=false`，沒有流暢戰鬥／30 FPS PASS。** 原 200 人自動 GPU full60：927 幀／60.175594 現實秒，15.404916 FPS／P95 332.980 ms，input-wall 0.598662；只完成約 36.024863 動作秒，最後完整十秒僅 3.9 FPS。148 真有效命中、20 原人物死亡／20 地面容器、180 存活；1,018 原物品守恆、4,781 Nodes 不增、BUSY、HUD、來源穩定通過，但這些不抵銷長幀、未跟上現實時間及 55 秒連戰覆蓋不足。本次已包含 Cape 啟用、八種嚴格無瞄準 attack 範圍、TerrainData 單次守衛與 fatigue frontier；前次 `153920_375` 的 14.403307 FPS／P95 368.153 ms 及舊逐段數據保留，不把多項變更／不同原生 delta 的平均差異當單變因收益。anchorX 只是測試候選，正面交戰更慢，因此未採用。scalar m25 仍是 test-only，不是正式 32 配方修復，局部 PASS 不冒充完工。

16:18 最新 **fixed120 候選** full60 `161837_569` 亦已量完：1,024 幀／60.236422 現實秒、16.999682 FPS／P95 330.414 ms、input-wall 0.589278，最後十秒 3.5 FPS；`targets_met=false`。原 4,259 個 120 Hz 子步共 35.491667 動作秒，末端 0.004353333 秒餘時保留，扣餘時後未對帳量約 `1.396e-12` 秒。這不等於已跟上現實；候選 `fixed_action_steps_enabled` 仍預設 false，沒有啟用或流暢完成結論。

16:22–16:31 歷史局部驗證：fixed120 原 clock 的 12 種 render 切分回歸通過但仍 default false；rigid hull 精確頂點去重經 synthetic／男女對照後曾暫設 default true。去重只省原武器／盾投影，不改 armor／head／IK 的完整頂點次序；後續暖機隔離量測沒有明確收益，主控已改回 false，詳見 16:46–16:48 節。bounds-only 路線因收益未明、牽涉四個 owner，暫不實作。

16:34 最新 **strict-cull 候選** full60 `163440_200` 完整量完：904 幀／60.007699 秒、15.064734 FPS／P95 322.197 ms、input-wall 0.599910，最後十秒 3.7 FPS，仍 `targets_met=false`。候選執行時明確開 strict＋cull，dedup true／fixed120 false；交付時 strict 與 cull 仍 default false。窄相交 CPU 減少不等於 FPS 成功，Source 姿態／幾何仍是主要成本。後續 `164605_403` 新整合測試 check-only 因型別推導 FAIL，保留待定向修正，不能把它算成已通過。

最新開關判斷：**dedup／fixed120／strict／cull 全部 default false**。男女暖機後隔離投影合計 `171,830→171,047 μs`，僅 −0.46%，低於同 flag 階段波動，不足以支持啟用 dedup；保留精確性證據，但不再投入其 guard 微優化。沒有新 FPS run，因此與目前「候選皆關閉」配置相對應的最後 full60 仍為 `160052_088` 的 15.404916 FPS／P95 332.980 ms／未達標，**不是** strict-cull 候選的 15.064734 FPS。這是配置對應的歷史量測，不宣稱現行所有檔案 SHA 與該 run 相同。60 Hz 方案尚未獲回覆、未實作。

16:53 最後補驗 `165356_375` strict-cull GPU 整合 PASS：12 原 owner contact 對照／8 packet＋HP 對照、22 原物品守恆、最大誤差 0。這與 headless 144 checks 都是 **strict 自身 uncull/cull 的對照，不是 legacy approximate-sort 等價**；舊 parry assertion／逾時保留，不能把兩次的多個變更武斷歸因於 dedup。全部候選仍關閉，沒有新的 FPS run。

以下 14:39–15:09 為逐次保留的當時狀態；後續 full60 的完成結果另列下節，最新候選為 16:34 節，不回改舊 FAIL 或局部驗收界線。

14:39 新增局部 `143912_828` capsule ring headless PASS：10,018 exact cases、原／重用 30,645→20,498 μs。只是原固定方向向量重用的原生多邊形對照，當時沒有新增 full60 或 FPS 收益證據；當時最新整場量測為 `142201_842`。

14:55 constant morph 私有 key 精簡仍未啟用（`constant_morph_keys_enabled=false`）：`145506_000` native headless PASS 1.217 s、37 guards／306 samples；後續 `145526_776` GPU group 0 **FAIL** 15.309 s，失敗為「Full native snapshot bytes, including scalar signed zero, must also match」。雖 Godot exit 0 且 stdout 印 PASS，canonical helper 已檢出 GDScript assertion 並判 FAIL，不能採信子函式失敗後的 PASS 字樣或當作完整模型一致。兩批原四檔共 8 檔已永久歸檔、SHA-256 與 runner 原檔逐一相同；沒有新增 FPS 或完整視覺驗收通過。

15:07 後續局部驗收補充：NodePath 原生序列化的未初始化 padding 已用實際重複編碼與官方原碼定位，測試改驗完整路徑／型別及所有數值位元，不放寬正負零或幾何精度。constant morph 的 native／GPU 兩組已真正 PASS，主控才將 `constant_morph_keys_enabled=true`；**保守非攻擊範圍候選已存在但仍 `conservative_nonattack_bounds_enabled=false`，尚無完整准入／整合驗收**。本次只補至 `150756_011` 的指定結果，未新增 full60／FPS 結果；最新整場已完成量測仍為上列 `142201_842`，流暢目標未完成。14:55 及所有後續 FAIL 均保留，具體順序見下節。

15:09 追加：`150912_269` 為 constant 預設啟用後的真正 native PASS；`150932_212`／`150957_626` 兩組 bounds GPU 數值／fallback 驗收已 PASS。這補上先前拒絕後的局部結果，但 **bounds 仍未預設啟用，實際 Lab 整合與 FPS 未由這些數值測試證明**；進行中的新 full60 不列結果。

對 `142201_842` 最後十秒低幀率的[唯讀追查](output/site_combat_performance_20260913/full60_142201_tail_review.md)：慢幀在 48 秒左右已持續出現，非 50 秒 checkpoint 才觸發；50–60 秒原 Lab process CPU 佔所分配 draw intervals 約 91.75%。最後截圖／保存與 hash 均在停止計量後，不能解釋這段退化。原傷亡後自然補位與 shared pose／body／shield 投影耗時增長有實證，但目前沒有分段 cache-miss／各階段完整計數，不能把全部增量武斷歸到單一函式或搜刮。

## 17:25–17:36 動態 cheap-bound 與 fatigue-zero 候選證據

本批原 `result.json`／`stdout.log`／`stderr.log`／`combined.log` 共 **11 批、44 檔、333,270 bytes** 已複製至 `output/site_combat_performance_20260913/verification/<run>/`；兩輪逐檔 SHA-256 與大小均和原 runner 檔相同，清單為 [archive_172552_173636_sha256.json](output/site_combat_performance_20260913/verification/archive_172552_173636_sha256.json)。沒有刪除原檔、覆寫不同內容或更改原報告／圖表；以下效能「未達標」保留原 helper PASS 與 `targets_met=false` 的不同層次，不偽造 canonical FAIL。

| Canonical run | 層次／結果 | helper s | 實際證據 |
| --- | --- | ---: | --- |
| `172552_856` | Geometry check-only PASS | 1.150 | 僅解析 |
| `172602_707` | query-bounds check-only PASS | 1.769 | 僅解析 |
| `172629_833` | Geometry GPU 數值 PASS | 7.766 | 20 poses、28,344 vertices、7 guards；原骨／head first-fit／fallback |
| `172651_453` | query-bounds GPU group 0 PASS | 13.061 | 6 組完整 contact 順序／數值位元、cold-head 與完整幾何對照 |
| `172751_185` | query-bounds GPU group 1 PASS | 13.064 | 5 組女性 live／down／terminal／原移動步對照 |
| `172838_250` | fatigue-zero check-only PASS | 1.586 | 僅解析 |
| `172857_625` | fatigue fixture **FAIL** | 19.735 | 原 off 路徑的缺工具等待進度假設錯誤，當時待 watchdog 收束 |
| `172926_646` | realtime check-only PASS | 1.681 | 僅解析 |
| `173002_699` | full60 完整量測；**效能未達標** | 89.135 | canonical PASS／exit 0，`targets_met=false` |
| `173241_741` | fatigue fixture **FAIL** | 6.868 | 原 off 路徑把非受控人物的 WALK 誤當 RUN；已立即失敗退出 |
| `173636_441` | fatigue-zero headless PASS | 7.885 | 58 原小步 A/B 精確相同；11 eligible／候選跳過 11 次 helper |

[Geometry 原報告](output/site_combat_performance_20260913/incoming_geometry_bounds/1789291597_1455213/measurements.json) 的保守框包含實際原生姿態多邊形，不替換骨架、護甲或首個 head-fit；`geometry_usec=10,533`／`bounds_usec=13,099` 含冷快取，不是收益證明。[group 0](output/site_combat_performance_20260913/query_bounds/group0/1789291613_1978162/measurements.json) 與 [group 1](output/site_combat_performance_20260913/query_bounds/group1/1789291673_1942586/measurements.json) 各沿同一批 4 原 rows／22 原物品，完整 6＋5 組依原 approximate sorter 對照。涵蓋 A bounds-only→B→A 補齊、實際盾／無盾 parry／徒手、瞄準 fallback、女性 live 與原移動；**不是 200 人傷害等價、FPS 或全部畫面人工驗收**，也不能移作後續 static 候選的證據。

### 動態 cheap-bound full60：完整窗口仍不流暢

[原 measurements.json](output/site_army_combat_realtime/bad939488a0f7ae8/mixed_equipment_full60_cheap_bounds/1789291805_1976010/measurements.json) 明列 `--m25-scalar-catalog --cheap-bounds`，fatigue-zero／dedup／fixed120 均 false。902 幀／60.032605 現實秒、15.025168406 FPS／P95 357.818 ms，最長間隔 459.894 ms；六個完整十秒段 FPS 為 **16.0／18.0／17.4／18.3／16.4／4.0**。原輸入 `34.9875556666667` 秒、動作 `34.9875556666656` 秒、4,778 原步，input-wall `0.5828092195`；最大內部 delta 債約 `1.151e-12` 秒只表示算完引擎交付時間，不代表跟上現實。55 秒連戰覆蓋、30 FPS／P95 及各十秒段門檻均 false。

144 真有效命中、20 原人物死亡／20 地面容器、180 存活，原 200 身分／1,018 物品守恆、4,781→4,781 Nodes、BUSY、HUD、來源在窗口內穩定。主控已人工看過本次 **一張** `02_final.png` 靜態畫面；不是 motion proof 或逐幀人工檢查。scalar m25 仍為 test-only，未宣稱正式 32 配方修復。

診斷計時為 `collect_query_bounds=16.485170 s`、`collect_geometry=2.121899 s`、`teams_sample=33.324004 s`；Source `pose=5.859786 s`、body `0.736170 s`、shield `0.859730 s`。它們有巢狀包含，不能相加，也不能將完整幾何減少直接當 FPS 收益。fatigue-zero 計數只觀察到 760,229 個 eligible rows、跳過 0 次，**並未在這次 full60 啟用該捷徑**。動態路徑之後已撤回；static 替代版正在驗證，本節不預報結果。

### fatigue-zero：精確性通過，未證明效能收益

[原報告](output/site_combat_performance_20260913/fatigue_zero_fast/1789292204_7463603/measurements.json) 使用同一 Lab 經原 Store 重播，3 原 Army rows＋2 原 Actor；58 個原 `_advance_fatigue` 小步逐次比對 fatigue／rest 的 IEEE 位元及型別、HP／KO、工作、供養與物權狀態。涵蓋 ±0、integer→float、零 elapsed、暫停、真正交糧與訓練扣時、原派工／缺工具、guard／RUN／attack 正速率及原受擊進入 KO。profiling 關閉時 counters 不增；開啟時兩路 eligible 都為 11，原 helper 不跳過，候選恰好跳過 11。

兩次 fixture FAIL 均保留：第一版誤認缺工具跨兩步仍保留採集進度；實際第一步 `_work` 清 target／回 idle，第二步 `choose_task→assign_task` 因重新指定 target 歸零。修正版按原兩步逐次精確比較，負零未改為寬鬆近似。第二版把 `running=true` 誤當任何 row 都跑；原 `_reserve_combat_step` 的第 3 參數是 escort ID，只有真正受控人物才使用 RUN_DURATION。修正先沿原控制入口綁定 row，再驗原預約／未完成進度；沒有改移動規則。外層 checked-run 使內層 assertion 失敗立即清理／exit 1，不再等 watchdog；18 秒內限與 20 秒 helper 保留。

小 fixture 的 `fatigue_people_usec` 為原 `2,213`／候選 `2,272`（內含 threat `939`／`962`）；這種短小、非隔離整場量測**不能聲稱加速**。候選仍 default false，完整 FPS／命中精度證明不由這次 headless 結果替代。

## 17:39–17:43 static84＋fatigue-zero：局部精確，整場未達標

追加六批原四檔共 **24 檔、395,773 bytes** 至相同永久 `verification/<run>/`；两輪逐檔 SHA-256／大小一致，清單為 [archive_173936_174311_sha256.json](output/site_combat_performance_20260913/verification/archive_173936_174311_sha256.json)。原 JSON／圖表／FAIL 全數保留，沒有把之前動態版的 PASS 改標成此版。

| Canonical run | 層次／結果 | helper s |
| --- | --- | ---: |
| `173936_579` | query-bounds check-only PASS | 1.797 |
| `173955_179` | static query-bounds GPU group 0，6 組 exact PASS | 12.827 |
| `174133_959` | static query-bounds GPU group 1，5 組 exact PASS | 13.377 |
| `174233_528` | Geometry check-only PASS | 1.118 |
| `174240_922` | static Geometry GPU 數值 PASS | 7.860 |
| `174311_662` | full60 完整量測；**效能未達標**，canonical PASS／exit 0 | 89.592 |

[static Geometry 原報告](output/site_combat_performance_20260913/static_incoming_bounds/1789292562_1457980/measurements.json) 保留原連續姿態／四向／實際裝備、20 poses／28,344 vertices／8 guards，20 次暖 face 查詢沒有新增 seek；原 head first-fit、bones／armor／完整值與 cold／unsupported fallback 仍驗。當批 fixture 由原 proof 得到 local radius 84，不是拿固定 84 代替證明。局部 `geometry_usec=61,644`／`bounds_usec=437` 不是 FPS 或畫面人工驗收。

[static group 0](output/site_combat_performance_20260913/query_bounds/group0/1789292397_1977667/measurements.json) 與 [group 1](output/site_combat_performance_20260913/query_bounds/group1/1789292496_1995543/measurements.json) 的 6＋5 組全部 `cold_head_first_fit_bits_exact`／`full_geometry_bits_exact`／`ordered_contact_bits_exact=true`；各為同一批 4 原 rows／22 原物品，沿原 approximate sorter、冷 full A→B→暖 no-seek A→full A、盾／parry／徒手、瞄準 fallback、原女性與移動／terminal。這是此 static84 來源的定向數值證据，不能外推成 200 人全傷害或下一輪 centered 版通過。

[static84＋fatigue-zero full60 原報告](output/site_army_combat_realtime/d0cf58055d943ddf/mixed_equipment_full60_static_bounds_fatigue_zero/1789292594_1872364/measurements.json) 明確以 `--cheap-bounds --fatigue-zero` 啟用兩候選：905 幀／60.130989 現實秒、15.050475887 FPS／P95 363.779 ms、最長間隔 554.346 ms；六段 FPS **16.5／15.6／20.0／15.3／18.8／4.2**。原輸入 `34.9546780000001` 秒、action `34.9546779999988` 秒、4,809 步，input-wall `0.5813088822`；最大內部 delta 債約 `1.286e-12` 秒，最長連戰 `34.946345` 動作秒。跟不上現實、FPS／P95／每段 30 FPS 及 55 秒連戰覆蓋仍 false；`targets_met=false`。

146 真有效命中、20 死亡／20 原地面容器、180 存活，200 原身分／1,018 物品守恆、4,781→4,781 Nodes、BUSY／HUD／來源穩定仍 true。主控對本次及前次 dynamic full60 **各只人工看一張 `02_final.png`**，不是 motion proof。本次 fatigue-zero 實際 eligible／skipped 均 765,198；Source `query_bounds_calls=67,232`、hits 同數、fills=0。原 `collect_query_bounds=11.971367 s`、`collect_geometry=6.547866 s`、`teams_sample=33.699954 s`，fatigue_people inclusive `3.698791 s` 內含 threat `1.339125 s`；巢狀計時不可相加，兩候選和不同 delta 一起改變也不是單變因收益證明。所有新開關仍 default false。

下一輪僅在準備／驗證 centered bound 與移除動態方案留下的 active fallback，沒有新結果可列；本節不把 static84 原數字、原錯誤紀錄或時序改寫成後續成功。

## 17:58–18:06 centered 邊界與最新 full60

`175824` 至 `180632_906` 共找到 10 批未封存結果，原四檔 **40 檔／518,867 bytes** 已永久保留；兩輪逐檔 SHA-256／大小核對一致，見 [archive_175824_180632_sha256.json](output/site_combat_performance_20260913/verification/archive_175824_180632_sha256.json)。原檔、測量 JSON、既有 FAIL 與圖表沒有改寫。

| Canonical run | 已完成證據 | helper s |
| --- | --- | ---: |
| `175824_533` | Source bounds check-only PASS | 2.111 |
| `175901_767` | Source bounds GPU group 0 PASS：75 cases／13,525 vertices | 8.834 |
| `180336_475`／`180338_680`／`180341_929` | Geometry／Army query／realtime check-only PASS | 1.129／1.970／2.054 |
| `180400_809` | centered Geometry group 0 PASS：120 poses／162,258 vertices／9 guards | 8.848 |
| `180426_386` | centered Geometry group 1 PASS：120 poses／146,988 vertices／9 guards | 9.691 |
| `180454_803` | centered Army group 0 PASS：7 組 exact | 13.501 |
| `180542_301` | centered Army group 1 PASS：5 組 exact | 13.392 |
| `180632_906` | full60 完整量測，**性能未達標**；canonical PASS／exit 0 | 89.797 |

原 native proof 現有 18 個 centered clips，各自半徑 47–62 px；兩個 crossbow clips 仍保留原 origin84 fallback，不憑抽樣極值裁切範圍。[Geometry group 0](output/site_combat_performance_20260913/static_incoming_bounds/centered/group0/1789293842_1414169/measurements.json)／[group 1](output/site_combat_performance_20260913/static_incoming_bounds/centered/group1/1789293868_2209061/measurements.json) 各測 10 個原 native clips × 起／中／末 × 四向，原 body／shield 頂點全包含，first-fit／bones／armor／完整值與 cold／unsupported fallback 保留，各 120 次暖查詢未增加 seek。這些取樣是回歸檢查，不冒充所有連續時間的数学證明或畫面人工驗收。

[Army group 0](output/site_combat_performance_20260913/query_bounds/centered/group0/1789293896_1924681/measurements.json)／[group 1](output/site_combat_performance_20260913/query_bounds/centered/group1/1789293944_1911196/measurements.json) 仍為 4 原 rows／22 原物品、原 approximate sorter；7＋5 組 cold head／full geometry／ordered contact 位元旗標全部 true。新增原無瞄準 UP active 暖查詢且保留完整武器，並保留瞄準／parry、女性 live、down terminal 與原移動案例；不外推為 200 人全傷害等價。

[最新 full60 原報告](output/site_army_combat_realtime/57d162e05ee9c1c2/mixed_equipment_full60_static_bounds_centered_fatigue_zero/1789293996_2133387/measurements.json) 為 `--centered-bounds --fatigue-zero` 明確 opt-in，1400×900／VSync disabled／time scale 1，原自動 process 938 次、4,934 動作步。938 幀／60.151064 秒＝15.594071619 FPS，P95 344.144 ms、最長幀 459.863 ms；六段 FPS **16.7／18.6／17.2／21.8／15.0／4.4**。input `36.252407` 秒、action `36.2524069999987` 秒，input-wall `0.6026893722`；內部最大 delta 債約 `1.286e-12` 秒只表示完成交付時間，不代表跟上現實。最長連戰 36.244074 動作秒，FPS／P95／每段 30 FPS／現實時間追隨及 55 秒覆蓋均 false。

153 真有效命中、20 死亡／20 地面容器、180 存活，200 原身分／1,018 物品守恆、4,781→4,781 Nodes、BUSY／HUD／來源穩定 true。fatigue eligible＝skipped＝784,421；centered query hits＝calls＝126,552、fills＝0。原 Lab process CPU 46.860 s，`teams_sample=32.910688 s`；其內 `collect_query_bounds=5.882471 s`、`collect_geometry=5.890784 s`、`collect_narrow=0.676273 s`。另 actors_advance `4.574249 s`、navigation/team prepare `4.193984 s`，fatigue_people inclusive `3.870442 s` 內含 threat `1.482248 s`。Source pose／body／shield／weapon 分別 `3.748862／1.244355／1.675335／2.583093 s`，這些和外層互相包含，**不能相加或換算成已達 FPS 收益**。本節只記原 JSON 與數值驗證，不新增未確認的看圖或 motion proof 聲明；所有新候選預設仍關閉。

## 18:16–18:31 contact-inputs：局部通過，最新 full60 仍未達標

本段 **11 批、44 原檔、732,146 bytes** 已永久封存於 `output/site_combat_performance_20260913/verification/<run>/`；每批 `result.json`／`stdout.log`／`stderr.log`／`combined.log` 的兩輪 SHA-256 與大小均同 runner 原檔，清單為 [archive_181600_183117_sha256.json](output/site_combat_performance_20260913/verification/archive_181600_183117_sha256.json)。未更改原報告、FAIL 或圖像。

| Canonical run | 層次／結果 | helper s | 範圍 |
| --- | --- | ---: | --- |
| `181600_489`／`181915_938` | realtime check-only PASS | 1.711／1.684 | 僅解析 |
| `181632_215` | no-stage-profile short10 完整量測；未達標 | 38.832 | 非 full60，`targets_met=false` |
| `181957_606` | query-bounds check-only PASS | 1.691 | 僅解析 |
| `182023_813` | centered inputs GPU group 0 PASS | 15.162 | 7 組 contact／完整幾何精確、8 input checks |
| `182148_040` | centered inputs GPU group 1 PASS | 14.669 | 5 組 contact／完整幾何精確、6 input checks |
| `182234_441` | full60 完整量測；效能未達標 | 89.164 | canonical PASS／exit 0，`targets_met=false` |
| `182933_376` | Actor constant-morph check-only PASS | 1.249 | 僅解析，不能替代下一批 |
| `182951_249` | Actor constant-morph GPU **FAIL**／exit 1 | 14.886 | case 0 骨姿 scalar bits 不同；原因調查中 |
| `183025_305` | contact-inputs flow check-only PASS | 1.585 | 僅解析 |
| `183117_403` | contact-inputs flow GPU 數值 PASS | 14.505 | 每路 141 步／1 真 packet，逐步 rows／packet 位元相同 |

[short10 原報告](output/site_army_combat_realtime/15b16ab75cfdbfa5/mixed_equipment_short10_static_bounds_centered_fatigue_zero_no_stage_profile/1789294595_1923987/measurements.json) 為 168 幀／10.091962 現實秒、16.646912 FPS／P95 351.189 ms，input/action 約 5.702103 秒、input-wall 0.565014；40 有效命中、807 原步。`--no-stage-profile` 使原 Lab 詳細階段表為空，但原外層觀測與 Source profiling 仍存在，**不是完全無量測負擔，也不是 full60 或效能 PASS**。

[query inputs group 0](output/site_combat_performance_20260913/query_bounds/centered_inputs/group0/1789294825_1986497/measurements.json)／[group 1](output/site_combat_performance_20260913/query_bounds/centered_inputs/group1/1789294910_1988844/measurements.json) 皆沿同一批 4 原 rows／22 原物品，12 組 `cold_head_first_fit_bits_exact`／`full_geometry_bits_exact`／`ordered_contact_bits_exact=true`。涵蓋 cold A→B→warm A、盾／無盾 parry／徒手、aim fallback、女性 live／down、terminal／原移動，以及 8＋6 項同 batch input-slot 重用、解除引用、下一 batch 變更與 live blocked 資格檢查；不是 200 人完整傷害或畫面人工驗收。

[flow 原報告](output/site_combat_performance_20260913/contact_inputs_flow/1789295479_1925473/measurements.json) 使用同一原 owner 的 flag false／true 重播：4 原 rows、2 原 live presenters、24 原物品，兩路各 **141 個 1/120 秒原步**；首個真命中在 step 132，後續再驗 8 步，每路 1 真實 packet，候選實際取用 164 個 input slots。`all_step_row_packet_bits_exact=true` 比較完整 rows／HP／KO／blocked／hits／previous 與 queued packets；本次 `ko_observed=false`，不冒稱已覆蓋 KO 或持續整場。

### 最新 full60：只有量測完成，沒有流暢結論

[182234 原報告](output/site_army_combat_realtime/0bdc2e3280ad857b/mixed_equipment_full60_static_bounds_centered_fatigue_zero_contact_inputs/1789294957_1882205/measurements.json) 在同一 1400×900、Forward+／D3D12、VSync disabled、time scale 1 下，以 `--centered-bounds --fatigue-zero --contact-inputs` 執行原自動 common-clock。919 幀／60.238876 現實秒，**15.255928746 FPS／P95 334.282 ms**，最長間隔 568.8 ms；六個完整十秒段為 **16.5／23.6／11.6／23.2／12.5／4.4 FPS**。原輸入 36.8200183333333 秒、action 36.820018333332 秒、5,037 原步，input-wall 0.6112334887；最大內部 delta 債約 `1.243e-12` 秒仍只表示結完引擎交付時間，不能當成跟上現實。FPS／P95／各十秒段、input-wall 及 55 秒連戰覆蓋皆未通過，最長連戰僅 36.811685 動作秒。

155 真有效命中、172 resolved packets（含 17 shield 零傷害結果）、20 原人物死亡／20 容器、180 存活、0 KO；200 原身分、1,018 原物品守恆、4,781→4,781 Nodes、BUSY、正常 HUD 與窗口來源穩定均成立。主控只人工檢視本次 **一張 `02_final.png`**；這是靜態画面，不是 motion proof。scalar m25 仍為 test-only，未宣稱正式 32 配方修復。

原 Lab full-clock CPU 46.836776 s；`teams_sample=32.478611 s`，內含 `collect_query_bounds=6.382246 s`、`collect_geometry=4.798515 s`、`collect_narrow=0.680079 s`。另 `actors_advance=4.665699 s`、navigation／prepare `4.271386 s`、fatigue people inclusive `3.992797 s`（含 threat `1.544125 s`）；Source pose `3.812803 s`／body `1.362592 s`／shield `1.794992 s`／weapon `2.689091 s`。這些計時相互巢狀，不能相加或把某欄減少當成 FPS 成功。fatigue eligible／skip 各 800,558，centered query hits／calls 各 130,308，只有局部捷徑確實被執行的證據。

Actor 的[原 FAIL log](output/site_combat_performance_20260913/verification/20260913_182951_249/combined.log) 首筆為 `$actor[bones][1][0].basis.axis[0].y`，原 `-0.00791506096721`／候選 `-0.00791505351663`（約 `7.45e-9`）；後續亦有其他骨姿分量不同，**此值不是全模型最大誤差**。當批確實 exit 1／未逾時，保留嚴格位元標準；fixture／歷史狀態／候選的因果仍待隔離，不能據此宣稱 compactor 錯誤或通過，也不把原 Source 的局部證據搬作 Actor PASS。

## 18:33–18:38 Actor 資源複製差異：定位補充，沒有啟用候選

追加 **2 批、8 原檔、77,103 bytes** 至永久 verification，原四檔兩轮 SHA-256／大小一致，清單為 [archive_183355_183809_sha256.json](output/site_combat_performance_20260913/verification/archive_183355_183809_sha256.json)。兩批均正常收束、未逾時；保留原 FAIL，不再跑同一候選或降低精度門檻。

| Canonical run | 結果 | helper s | 真正覆蓋範圍 |
| --- | --- | ---: | --- |
| `183355_358` | raw-repeat GPU PASS／exit 0 | 34.310 | 同一原 Actor／native player 的 AAAA；4 路各 15 cases、45 exact pairs、9 geometry pairs，最大數值誤差 0 |
| `183809_490` | copy-only GPU **FAIL**／exit 1 | 13.414 | pass 1／case 0；只 duplicate、不減 key 仍產生同一首筆骨姿差異 |

[raw-repeat 原 stdout](output/site_combat_performance_20260913/verification/20260913_183355_358/stdout.log) 明列 `candidate_evaluated=false`、`original_resources_unchanged=true`，保留同一原 Actor／player／Skeleton。比較包括所有可見／隱藏 morph 與 bones 位元、少量原 body／shield／weapon 幾何；雖報告也列 private-library audit，**AAAA 沒有評估該減鍵候選，不能當成減鍵准入、完整畫面或 FPS 驗收**。

[copy-only 原 FAIL](output/site_combat_performance_20260913/verification/20260913_183809_490/combined.log) 的 `$actor[bones][1][0].basis.axis[0].y` 仍為原 `-0.00791506096721`／duplicate `-0.00791505351663`。因此「減鍵本身造成此差異」不是現有證據能支持的因果；目前只把下一步定位範圍縮至複製／資源替換／cache 流程，沒有斷言其中某個內部實作是原因。Actor production SHA-256 仍 `EB1D41837F49B77CDD8DC16A87BCDC8232CFEF5F5F906DEEC78AC830ABC7B947`，與原測試記錄相同；未修改 Actor，未新增 full60，最新效能仍為上列 `182234_441`／未達標。

## 使用者目標、代表情境與本輪工程驗收來源

- 使用者目標是「優化到可以流暢戰鬥」。下列數字與具體方法是本輪工程方案／驗收設定，不冒稱使用者逐項明確要求、永久不可變的產品規格。
- 本輪保真策略：沿原 TerrainLab／原人物／原物品與共同 120 Hz 動作步，保留原傷害／命中精度／生效段／護甲／疲勞及接觸、速度公平性。120 Hz 是目前採用的工程策略，不代表使用者指定這個執行頻率；本次來源標示修正並未改動它或其他 production 行為。
- 目前 Site 的代表壓力情境是原兩隊 200 人與混合實際裝備、正常場景自動更新及 HUD、真實畫面時間。固定此負載有利前後比較，不以暗中減人換取較高 FPS；它不是要求每場遊戲都固定 200 NPC。
- 本輪設定的工程驗收為先達穩定 30 FPS、P95 ≤33.334 ms，爭取 60 FPS；量測 60 秒現實窗口與六個完整十秒段、保留各段 FPS／P95、無 >1 s 停頓及原時間追隨檢查。這些是將「流暢」具體化的本輪標準，不是使用者原話。
- 55 秒連續交戰屬本輪負載覆蓋設定。正常戰鬥若較早結束，只表示未覆蓋這項連戰情境，不能單獨稱為 FPS 失敗；應分開讀 FPS／P95／時間追隨與覆蓋旗標。既有報告的 `targets_met`、每項旗標、數字及 FAIL 均保留，不回改判定；目前實測即使不看連戰覆蓋，幀率、長幀與半速仍不流暢。
- 不使用假傷亡、截斷模擬時間、掉時間、慢動作或畫面空轉換取 FPS；同時核對原 delta、實際模擬時間及單調現實時間。精確對照保留未改前來源／原角色參考，局部幾何一致不代替整場命中或畫面。人物／物品守恆、Nodes 與 BUSY 是資源／既有存檔保護檢查，不冒充使用者另訂的 FPS 規格。

## 已有基準

原 `20260913_073548_879`：60.091667 連續交戰秒、184 有效命中，實際執行 1,379.043 秒；完整步進 CPU 1,338,155.163 ms，接觸 CPU 1,196,112.486 ms，shared pose 計時 1,080,317.682 ms。這是有界手動批次吞吐，不是即時 FPS。原報告旗標錯誤及獨立覆核完整保留於 `output/site_army_combat_longrun/README.md`。

## 本輪真實 FPS 短測：均未達標

下表逐筆讀取該次 `measurements.json`，不是以 helper 的退出狀態推算。七次皆為原 200 人、原 1,018 物品、正常 Site HUD、自動 Lab／Actor／Army `_process`，`manual_simulation_calls=0`；但使用 `--baseline-equipment --short=10`，是**原全裝診斷，不是本輪工程設定的混合配裝完整驗收**。Godot 4.6.2、D3D12／Forward+、RTX 5060／i5-14400F，視窗與內容 1400×900，VSync disabled、max FPS 0、time scale 1。

FPS 是呈現幀數除以單調現實時間；P95 是真實畫面間隔的 nearest-rank 百分位。以下窗口不含初始化／暖身，並非整個 helper 執行秒數。

| Canonical run（2026-09-13）／原量測 | 呈現幀 | 現實窗口 s | FPS | P95 ms | 動作 s | input／wall |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| [102311_244](output/site_army_combat_realtime/25c7e57adbf1bff5/baseline_equipment_diagnostic_short10/1789266194_1897719/measurements.json) | 68 | 10.027339 | 6.781 | 601.336 | 4.309215 | 0.429747 |
| [102534_836](output/site_army_combat_realtime/cc19774a32abab07/baseline_equipment_diagnostic_short10/1789266338_2179098/measurements.json) | 70 | 10.014068 | 6.990 | 568.582 | 4.393570 | 0.438740 |
| [102850_191](output/site_army_combat_realtime/a9a359f72f9ed15f/baseline_equipment_diagnostic_short10/1789266533_1912812/measurements.json) | 71 | 10.036751 | 7.074 | 570.362 | 4.381530 | 0.436549 |
| [103402_387](output/site_army_combat_realtime/c2c78546ba26c8bd/baseline_equipment_diagnostic_short10/1789266845_1899544/measurements.json) | 65 | 10.017759 | 6.488 | 566.965 | 4.252932 | 0.424539 |
| [104321_529](output/site_army_combat_realtime/a2a18ab988bcf52b/baseline_equipment_diagnostic_short10/1789267404_1907704/measurements.json) | 78 | 10.610593 | 7.351 | 570.161 | 4.766846 | 0.449253 |
| [105014_191](output/site_army_combat_realtime/87f5fbf0ad1c45b2/baseline_equipment_diagnostic_short10/1789267817_1855116/measurements.json) | 88 | 10.378778 | 8.479 | 446.475 | 5.044850 | 0.486074 |
| [110035_591](output/site_army_combat_realtime/ad677b557b2b35b6/baseline_equipment_diagnostic_short10/1789268438_1800632/measurements.json) | 87 | 10.269039 | 8.472 | 447.722 | 5.050000 | 0.491769 |

七次 helper 均正常結束且標 PASS，但報告均明列 `SITE_ARMY_COMBAT_REALTIME_TARGETS_NOT_MET`／`targets_met=false`。全程原人物／物品守恆、Node 4,341 前後不增、戰中存檔 BUSY、無非預期暫停、單次最長間隔未超過 1 秒等旗標通過；這不抵銷 FPS、P95、現實時間追隨率、完整 60 秒與混合配裝等失敗旗標。七次 `effective_hit_events=0`、死亡／KO 均 0，不能宣稱已驗到有效命中長期交戰或戰線重排。

`maximum_abs_debt_seconds` 最多約 `3.82e-14`，只證明原模擬算完了**引擎交付的 delta**；input／wall 僅約 0.425–0.492，因此 `input_tracks_wall_time=false`。這仍是遠慢於現實時間，不能以「沒有內部時間債」宣稱即時正常。各次來源指紋在其自身窗口內不變，但跨次程式與觀測欄位有變；這是逐次診斷結果，不是受控單變因效益 A/B。

最新上述短測的原 Lab CPU 共 8,841.566 ms；分段中 `teams_sample=6,256.985 ms`、`collect_geometry=3,156.642 ms`、`collect_narrow=7.193 ms`、Actor advance 934.960 ms。這些是**巢狀計時，不能相加**，支持繼續定位精確取樣／投影負擔，不證明省略幾何或降低命中精度合理。`TIME_PROCESS` 是引擎週期發布的 process 最大值，不是獨立每幀 CPU，表中 P95 不使用它。

所有七次 canonical result／log 副本位於 `output/site_combat_performance_20260913/verification/`，各 run 與原報告均保留，沒有回改為達標。

### 11:10 後新增短測與來源失效

仍為正常 HUD、原人物／物品、自動 `_process`；下列完成量測的五批同樣不是 60 秒窗口，且全部 `targets_met=false`。混合配裝與 baseline 分開列，來源不穩定的一批不能用於效益比較。

| Canonical run／原量測 | 模式 | 幀／現實 s | FPS | P95 ms | 動作 s／input-wall | 真有效命中 | 來源穩定 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| [111306_450](output/site_army_combat_realtime/8fbec5ad13d64392/mixed_equipment_short10/1789269189_1850338/measurements.json) | mixed，m25 test catalog | 60／10.149323 | 5.911724 | 639.898 | 3.887682／0.383048 | 20 | true |
| [111605_401](output/site_army_combat_realtime/1cc336460388bb45/baseline_equipment_diagnostic_short10/1789269368_1995203/measurements.json) | baseline diagnostic | 67／10.180444 | 6.581245 | 493.156 | 4.783333／0.469855 | 0 | true |
| [112531_573](output/site_army_combat_realtime/b52d54bdfc09cdf0/baseline_equipment_diagnostic_short10/1789269934_1879471/measurements.json) | baseline diagnostic，**非公平比較** | 77／10.019860 | 7.684738 | 516.173 | 4.892679／0.488298 | 0 | **false** |
| [114031_679](output/site_army_combat_realtime/02516f05025689a3/baseline_equipment_diagnostic_short10/1789270834_1999397/measurements.json) | baseline diagnostic | 86／10.201312 | 8.430288 | 433.737 | 5.307601／0.520286 | 0 | true |
| [121311_737](output/site_army_combat_realtime/3f9ca74864c1696b/baseline_equipment_diagnostic_short10/1789272794_1921426/measurements.json) | baseline diagnostic | 80／10.305896 | 7.762547 | 419.477 | 5.435172／0.527385 | 0 | true |

`111306_450` 的 `required_mixed_equipment_fixture`、真有效命中、原 200 row 身分／1,018 物品守恆、正常 HUD、Node 不增、戰中存檔 BUSY 與來源穩定旗標皆 true；仍未達 FPS、P95、input-wall、55 秒連續交戰或完整 60 秒門檻。上表五批 helper 分別正常結束於 35.599、36.461、35.696、34.690、37.208 秒，不能將 helper PASS 換稱效能 PASS。

先前 `114031_679` 是 `--baseline-equipment --short=10`，**全裝短測，不是完整流暢戰鬥**。來源在該窗口內穩定、原 200 row／1,018 物品／4,341 Nodes 與 BUSY 保護通過；有效命中仍 0、`required_mixed_equipment_fixture=false`。內部時間債最多約 `4.88e-14 s`，但現實 10.201312 s 僅交付／完成約 5.307601 s，`input_tracks_wall_time=false`。當次 `armor_calls=36`／`armor_hits=18`、`armor_geometry_usec=205629`、`seek_usec=681066`、`select_clip_usec=614891` 只是該來源／窗口的診斷，不把局部重複查詢微秒收益換算為整場 FPS。

最新 `121311_737` 同樣為原全裝 short10，`targets_met=false`；來源於窗口內穩定，原 200 row／1,018 物品／正常 HUD／BUSY 保護仍通過，**Node 此次為 4,781→4,781**，不能沿用先前 4,341。80 幀／10.305896 現實秒，原動作只完成 5.435172 秒、input-wall 0.5273847126；內部 delta 債最多 `5.68e-14 s` 仍不代表跟上現實時間。真有效命中、死亡、KO 都為 0，最長連續交戰 5.426839 動作秒，最長幀間隔 447.199 ms；沒有完整 60 秒／混合配裝／30 FPS PASS，亦不把跨版本短測數字解讀為單變因效益。

該次新增原 Army 計數：兩隊各 `ordinary_bounds_calls=16128`，局部耗時 952,670／1,570,715 μs；live 武器省略 280／279 次、實際補齊各 2 次、`live_partial_fills=0`。原 shared source 另記 `sample_calls=38240`、`step_hits=36826`、`partial_fills=280`、`partial_restores=0`、`weapon_fills=564`、`weapon_omissions=850`。這些只是現有取樣路徑的窗口計數，並非省略真命中或時間，也不是 FPS 收益；不同 owner／巢狀計時不可直接相加。

另保留 [112329_831 的原 UNAVAILABLE 報告](output/site_army_combat_realtime/2acd268c251394ed/mixed_equipment_short10/1789269812_1834565/measurements.json)：helper **FAIL、exit 1、21.726 秒**；`measurement_complete=false`、`source_items_moved=0`、`initial_loadout_transfers=[]`，沒有進入 FPS 量測。HumanEditor 檔案時間已為 2026-09-13 11:20:40，報告記錄 SHA256 `23096424753c50c540c9d921a92e2ba0e157600df07c89bf3ca90c32929ff7b8`；本次唯讀核對 MD5 `950bba02b53ab71daefa0572b75cda3a`，不等於 m25 test catalog 鎖定的 `0dd145a1980550d740305d2d9faf9533`。守衛因新版來源拒絕舊 m25，並未扣物，不能竄改舊指紋消除失敗。

`112531_573` 明列 `source_fingerprints_unchanged=false`；開始時 Geometry SHA256 `9ec24056…b3519`，同次啟動期間 geometry 子代理落地了新候選，故不適合作為該候選前後效益對照。原報告細分 `seek_usec=566344`、`select_clip_usec=561500`、`armor_geometry_usec=1019139` 僅保留為當次診斷，不能歸因成新候選的效能收益。

本次新增歸檔 `111034_962`、`111159_730`、`111306_450`、`111605_401`、`112329_831`、`112531_573`、`112837_592`、`112909_963`：各原 `result.json`／`combined.log`／`stdout.log`／`stderr.log` 共 **32 檔**，已複製至本輪 `verification/` 並逐檔核對 SHA-256 與原 runner 檔相同；不刪原檔、不覆寫不同內容、不更改 FAIL。

後續 `113318_938`、`113410_849`、`114031_679`、`114138_330`、`114250_368` 五批亦已歸檔；另查得歷史 m25 test publisher `111015_170` 原四檔尚未永久留存，本次一併補入相同 `verification/`。這次新增 **24 檔**全部與 runner 原檔 SHA-256 相同；原測量／FAIL／來源資料未修改。

本次再新增 GPU `115952_202`、`120510_276`、`120556_543`、`120657_397`、`120832_237`，以及對應 headless check-only `115913_578`、`120447_740`、`120647_640`，共 **8 批／32 檔**原四檔至相同 `verification/`，逐檔 SHA-256 與 runner 原檔相同。三次 check-only 分別為 1.136／1.226／1.169 s、exit 0，僅是解析檢查；五次 GPU 的具體契約另列下節。沒有改寫原報告或刪除原紀錄。

12:10 後 check-only `121038_833`（1.226 s）與 GPU `121055_602`、`121148_567`、`121220_951`、`121311_737` 的原四檔亦已歸檔，共新增 **5 批／20 檔**，逐檔 SHA-256 一致；沒有覆寫不同內容或刪原檔。最後一批 helper PASS 只表示正常完成報告，原 `TARGETS_NOT_MET` 未改。

12:20–12:27 的 check-only `122037_169`／`122413_402`／`122657_866`（1.135／1.606／1.229 s），與 GPU `122103_351`／`122449_853`／`122542_067`／`122708_799`，再新增 **7 批／28 檔**原四檔至永久 `verification/`；逐檔 SHA-256 相同、原檔與既有結果不變。check-only 不當作執行測試，四次 GPU 的契約與版本順序如下。

### 12:31–12:42 新增量測與精確驗收

[123112_835 原量測](output/site_army_combat_realtime/78a527b572e20abc/baseline_equipment_diagnostic_short10/1789273875_1893288/measurements.json) 為全裝 short10 診斷，helper PASS／exit 0／38.296 s，**報告仍為 `targets_met=false`**。88 畫面／10.225236 現實秒，8.606158 FPS、P95 362.109 ms、最長幀 415.836 ms；引擎交付及原動作完成各 5.714733 s，input-wall 0.558885，內部差約 `7.19e-14 s`。原 200 row／1,018 物品守恆、4,781 Nodes 前後不增、正常 HUD、戰中 BUSY 與窗口內來源穩定都通過；真有效命中／死亡／KO 仍為 0，既非混合配裝也非 60 秒即時驗收。不能把相較前批的數字變化當成單一優化的受控效益。

此次原生引擎設定實際記錄為 `native_max_physics_steps_per_frame=8`、`native_physics_ticks_per_second=60`；不以改引擎上限或補造 delta 隱藏 input-wall 不足。原 full-clock CPU 8,695.283 ms、contact CPU 4,415.694 ms；新增兩隊 `sample_current_weapon_usec` 為 717,607／84,499 μs，`sample_protection_usec` 為 144,015／135,531 μs。它們屬原呼叫的巢狀分項，不能與 contact／整步直接相加，也不是 FPS 收益證明。

| 新切片 | 原結果與界線 |
| --- | --- |
| 標準配裝 canonical key | check-only `123351_543` PASS 1.127 s；GPU `123359_714` PASS 9.636 s。[原 JSON](output/site_combat_performance_20260913/baseline_key/1789274048_9156534/measurements.json) 的同 source 開／關各 9 完整骨架／morph／armor／sample／protection／camera snapshots 完全相同，最大誤差 0；32 masks、七個 scalar 欄位、重排、同 caller A→B→A、完整六欄 pose key、dispose 留存鍵不變均由原測試驗證。36,826 次純 key 呼叫 176,726→28,447 μs，屬局部字典鍵計時，不能換算整場 FPS。Source SHA256 `58f4bcd4…5d8596`。 |
| 同批原目標索引槽 | check-only `123640_189` PASS 1.562 s；GPU `123744_999` PASS 12.827 s。更新後的原 contact-batch 測試在同批重複／uncached 路徑逐頂點及完整有序 contact 欄位完全相同；仍逐一驗原四目標 bounds、僅真正相交者展開 polygons、第二 Army 遠處 index 0、live 女性／普通兵真配裝與 guard／移動／卸裝、直接移動與下一步失效。没有新時間或碰撞近似；以該次原 log 為證，不另造 measurements 或 FPS 結論。 |
| 原 Editor 三處按需骨架更新 | check-only `124054_034` PASS 1.113 s；男／女 GPU `124100_626`／`124214_656` PASS 22.842／22.695 s。每體原 54 子步＋18 畫面對 exact，原自動 Editor、手動／非 Lab 立即更新與 ammo sync 守衛均通過；與先前 cloth 批次是不同候選，詳見下段。 |

三處新守衛僅控制原 `_update_combat_props`／`_update_scabbard_pose`／`_update_combat_cloth` 內的全骨架 force；原生 bone getter 仍同步所需骨鏈，**三個函式的原呼叫頻率、順序、原 seek／動畫／120 Hz 時鐘均不改**。對照兩路皆關閉 Actor cloth 批次、維持三呼叫立即執行，以免後續碰撞查詢先清掉 dirty 骨架而遮蔽問題。原 [男組 JSON](output/site_combat_performance_20260913/actor_visual_lazy_bones/body0/1789274462_1452713/measurements.json) 與 [女組 JSON](output/site_combat_performance_20260913/actor_visual_lazy_bones/body1/1789274536_1389230/measurements.json) 各含完整 18 案，body／weapon／shield／armor／bones／props 的 54 子步及原生畫面後 cloth／scabbard／props／morph／material／1280×1536 像素對照完全相同。原測試總耗時男 20,969.588／女 20,879.511 ms 不是分路效益量測，更不是 200 人 FPS。

主控已實際檢視男、女各 `full_force_bow_reload.png`、`lazy_getters_bow_reload.png`、`lazy_getters_get_up_low.png`，合計六張代表圖；不宣稱人工逐張檢過全部案例。測試 HumanEditor SHA256 `f8b48fa3…2dde18`，A/B 明確切 false／true；通過後主控才令 `lazy_combat_visual_bones_enabled=true`。未改前原檔已保留於 `before/human_character_3d_editor_112040.gd.txt`，本次核 SHA256 為 `23096424753c50c540c9d921a92e2ba0e157600df07c89bf3ca90c32929ff7b8`。這是此版本的局部 exact 證據，不當作 live damage／正式 atlas admission 或新全場 FPS PASS。

上述 **8 批／32 檔**原 `result.json`、`stdout.log`、`stderr.log`、`combined.log` 已複製到既有永久 `verification/`，每檔均和 runner 原檔 SHA-256 一致；具體來源／目的／雜湊列於 [本批封存清單](output/site_combat_performance_20260913/verification/archive_123112_124214_sha256.json)。不覆寫不同內容、不刪原檔、不修改 helper／原測量／FAIL 歷史。三次 check-only 只代表解析檢查，不冒充執行驗收。

### 12:43 原 200 人全裝短測：仍未達標

[124321_258 原量測](output/site_army_combat_realtime/0c000f9d597dc40e/baseline_equipment_diagnostic_short10/1789274604_1929510/measurements.json) 已完整結束，helper PASS／exit 0／36.613 s、未逾時，但仍為 **`targets_met=false`**。90 幀／10.083048 現實秒，8.925872 FPS、P95 331.172 ms、最長幀 365.173 ms；原輸入與原動作完成各 5.972058 s，input-wall 0.592287，內部 delta 差約 `8.70e-14 s`。來源在該次窗口穩定；200 原 row 身分、1,018 原物品、4,781 Nodes 前後相同、正常 HUD 與戰中保存 BUSY 均通過。有效命中／自然死亡／KO 仍全部為 0，`required_mixed_equipment_fixture=false`，不得宣稱流暢、完整混合配装或 60 秒驗收。

本次 full-clock CPU 8,549.336 ms，contact CPU 4,214.813 ms；原 `teams_sample=5,518.462 ms`、`collect_geometry=3,506.027 ms`，實際窄相交只有 6.188 ms。原 source sample 共 47,110 calls／45,371 step hits，sample CPU 2,309.327 ms，pose 1,144.039 ms；Actors advance 1,148.659 ms、navigation／team prepare 851.468 ms、fatigue／supply 884.330 ms。這些是巢狀診斷，**不能相加或轉算未驗候選的 FPS 收益**；目前大項仍是原姿態／投影與全人物更新，不支持把幾毫秒窄相交當作主要瓶頸。這一批執行時 morph／rotation 尚未取得後續驗收，故不能將本批數字歸因為它們啟用後的效益；後續局部 PASS 另列下節，仍不推估 FPS。

此 run 的原四檔已另封存至 `verification/20260913_124321_258/`，全部 SHA-256 與原 runner 相同，見 [四檔雜湊清單](output/site_combat_performance_20260913/verification/archive_124321_sha256.json)。原報告、較早未達標结果及此前全部 PASS／FAIL 紀錄不改；本段只補這一次完成量測，沒有新增執行或素材產生。

### 12:54–13:05 morph／preview rotation 與小查詢驗收

| 切片 | 原結果與精確界線 |
| --- | --- |
| 私有查詢 morph reset | check-only `125438_385` PASS 1.181 s；男 GPU `125455_761` PASS 16.837 s、女 GPU `125821_009` PASS 19.376 s。[男 JSON](output/site_combat_performance_20260913/morph_reset/group_0.json)／[女 JSON](output/site_combat_performance_20260913/morph_reset/group_1.json) 各 14 exact pairs、最大誤差 0，另各 7 lookup、2 history、2 same-clip、2 pre-seek seed checks。兩路皆驗完整原骨架、全部 morph（含未穿著者）、原護甲頂點、shapes／protection；不是畫面人工驗收或 FPS。 |
| 原 Actor 實際相等 rotation setter | check-only `125620_924` PASS 1.603 s；男 GPU `125942_252` PASS 25.658 s、女 GPU `130041_363` PASS 26.371 s。[男 JSON](output/site_combat_performance_20260913/actor_preview_rotation/body0/1789275583_1450709/measurements.json)／[女 JSON](output/site_combat_performance_20260913/actor_preview_rotation/body1/1789275642_1499732/measurements.json) 各 54 子步＋18 畫面对 exact、111 rotation probes，其中 39 actual-equal、36 外部 pivot 改動、111 原 hair uniform 檢查；手動／非 Lab 與 ammo sync 守衛亦通過。 |
| Army 兩處唯讀查詢縮減 | `130522_232` headless PASS 7.151 s：原 pose-clock 的 1,080 authored boundaries、1,189 lunge comparisons，另 988 eager／guard-only clip 查詢 exact；涵蓋原九種武器（含徒手）、盾有無／空配裝、四向與 13 種姿勢。非 guard 查詢 0 次、guard 1 次，未改動作／命中。另一處 live `combat_frame` 僅在原 fresh／missing-weapon 同步前取得，保留原 `_sync(frame,index)` 與計時範圍；**新增四向 frame 次數／原多邊形驗收仍待 partial-weapon group 2 GPU，不挪用較早 group 2 PASS**。 |

morph 候選只對固定私有 query owner 重用原有序 lookup，且僅在 morph 的**實際當前值完全相等**時省掉相同 setter；未穿著護甲／披風與非零極小值不排除。每個 pass 都播種 4,072 個原 morph 狀態，包含 2,100 hidden armor、954 hidden cloth、1,018 tiny-nonzero 檢查計數。原／候選局部 `armor_lookup` 男 1,928→267 μs、女 2,751→315 μs；整個 pass elapsed 男 2,432,113→2,404,020 μs、女 2,808,864→2,684,379 μs，包含此測試矩陣，不是 200 人 FPS。兩體報告 Source SHA256 都是 `17f21b9f…67e473`；主控在男女 PASS 後才令 `morph_reset_reuse_enabled=true`。

保留女組最初 `125525_472` **FAIL**：原 `restore_appearance` 斷言後又達 helper timeout，exit null、25.142 s。原因是男性 baseline 換 body 卻仍帶男性 hair 的非法 fixture；後續只改用該原 body 的 canonical default hair、保留原裝備及全部精確檢查，才取得 `125821_009`。沒有刪除原失敗，也不把非法 fixture 的斷言稱為遊戲 morph 不等價。

preview rotation 只在原 `preview_pivot.rotation` 已與完整 `Vector3(pitch, PI + yaw, 0)` **實際完全相等**時省掉 setter；原 yaw／visual-state 寫入與 auto hair-mask 呼叫仍全保留，不依賴 facing 記憶。四向、反向、非零 pitch、外部 pivot 改動、原頭髮／配裝切換、騎乘／地面、低姿態與弓弩歷史均在同一原 Actor 上對照。各 54 子步的 bones／body／weapon／shield／armor／props／hair uniforms 及各 18 原 1280×1536 畫面後的 morph／material／parts／camera／pixels exact；主控已檢視**男女各 original_setter_bow_reload、actual_equal_guard_bow_reload、actual_equal_guard_get_up_low，共六張代表圖**，不宣稱逐張人工檢過全部案例。兩體測試 HumanEditor SHA256 為 `752e765b…95bca6`；主控於 PASS 後才令 `exact_preview_rotation_guard_enabled=true`。

較早男組 `125637_544` **TIMEOUT／FAIL** 的 [原報告](output/site_combat_performance_20260913/actor_preview_rotation/body0/1789275399_1482519/measurements.json) 保留 `exact=false`、54 子步／17 畫面、108 probes，helper 25.106 s／exit null。不是完整 PASS，也沒有已記錄的像素失配；當時停止原因為子測試 23 秒上限。後續只將這個擴充的 rotation 子測試改為 33 秒、canonical helper 改用 35 秒，父 cloth fixture 仍維持原 23 秒；**沒有減案例、少比欄位或放寬 exact**，才完成兩次 54／18／111。延長有界執行時間與效能達標是不同事項，兩次完整 helper 耗時不當作局部收益或 FPS。

以上及 m25 預檢／realtime 解析檢查合計 **11 批／44 檔**原 `result.json`、`stdout.log`、`stderr.log`、`combined.log` 已永久封存，逐檔 SHA-256 與原 runner 相同，見 [本批雜湊清單](output/site_combat_performance_20260913/verification/archive_125438_130522_sha256.json)。名單為 `125438_385`、`125455_761`、`125525_472`、`125620_924`、`125637_544`、`125821_009`、`125942_252`、`130041_363`、`130207_709`、`130450_781`、`130522_232`；同秒但屬其他工作的 `125637_747` 沒混入。`130450_781` 只為 realtime test check-only PASS 1.589 s，**沒有新增 FPS 量測**；`130522_232` 的 root-certificate noise 保留，無 script／assertion failure。未改任何原輸出、舊 FAIL 或 helper。

### 13:06–13:25 新混合短測與回歸：仍非流暢 PASS

[131152_801 原量測](output/site_army_combat_realtime/41ec572b2fb9c990/mixed_equipment_short10/1789276315_1839308/measurements.json) 使用明確 `--m25-performance-catalog --short=10`，helper PASS／exit 0／37.020 s、未逾時；**`measurement_complete=true`，但 `targets_met=false`**。115 幀／10.172254 現實秒，11.3052623341887 FPS、P95 466.731 ms、最長幀 526.749 ms；原輸入 5.150000 s、動作 5.15000000000004 s，input-wall 0.5062791393，內部差約 `3.82e-14 s`。原 200 row／1,018 物品守恆、4,781 Nodes 前後不增、正常 HUD、戰中保存 BUSY、混合配裝與窗口來源穩定旗標均通過；40 次真有效命中、20 人受傷、0 死亡／KO。仍未達 FPS／P95／現實時間追隨率或完整 60 秒門檻；不與較早 baseline 跨版本數字當作單變因 A/B，也不把 helper PASS 稱為流暢戰鬥。

本次 full-clock CPU 8,354.871 ms、contact CPU 4,975.383 ms；`teams_sample=6,301.335 ms`、`collect_geometry=4,076.614 ms`、`collect_narrow=107.910 ms`。新增疲勞分段為 providers 13.513 ms、people-inclusive 631.585 ms，其中 threat 255.189 ms；**threat 已包含在 people，且其他取樣／整步亦巢狀，不可相加**。navigation／team prepare 388.651 ms、Actors advance 897.808 ms。Source 記錄 41,501 sample calls／40,037 step hits、1,468 true pose evaluations，sample CPU 2,969.764 ms；原 pose 1,355.535 ms、body 264.475 ms、weapon 428.845 ms、shield 254.077 ms。這些支持下一步熱點診斷，不證明可以少算人員、原幾何或 120 Hz 時間。

| 本批切片 | 原結果及範圍 |
| --- | --- |
| partial-weapon 最新三組 | GPU group 2 `130601_032` PASS 8.847 s，已含新增四向 live frame 查詢次數／原多邊形，8 cases；group 0 `131027_281` PASS 11.126 s，4 cases；group 1 `131111_607` PASS 9.287 s，65 cases。原欄位／骨架／armor、partial 補齊與原姿態還原、terminal 歷史／上限、live 女性與實際攻擊資格沿原 exact 驗；這補上前節截至 13:05 尚待 group 2 的項目，不回改舊證據。 |
| 思考短路、距離早拒與局部 fatigue eligibility | headless `132005_378` PASS 6.410 s。沿既有 tactics 原 100+100 rows／兩 Actor fixture，小條件 oracle、距離 0／1／2／3／9 及存活／被俘／KO／get-up 邊界，真兩個 120 Hz prepare 步保留正在攻擊、攻擊結束、think 到零／尚差一步、KO→get-up→idle 與控制人；每步 eligibility 5／control 2。全疲勞保存欄位 exact，原／新 eligibility 次數 `[3,3,300,300] → [2,2,200,200]`，保留威脅種子查詢。沒有跨整步存活快照、新模擬 owner 或供餐改動。 |
| 原疲勞整合回歸 | headless `132120_810` PASS 9.052 s：144 timing combinations，原 work partition／休息威脅／共同時鐘／暫停、原 Actor 狀態／保存／legacy／action-start snapshot 回歸；不是 GPU 或新增供養制度完整驗收。 |
| 單一已驗配裝值重用 | GPU `132253_034` PASS 15.848 s。[原 JSON](output/site_combat_performance_20260913/appearance_validation/1789276988_15405478/measurements.json)：原同 Source 開／關各 10 完整幾何 snapshots，最大誤差 0；37 malformed cases、caller mutation／生命週期仍走原驗證。41,501 次 validation 為 937,024→35,435 μs，只留 1 份已完整驗證的非 baseline 深拷貝，輸入結構值改變就回原完整驗證；不改 atlas admission。主控於 PASS 後才將 `appearance_validation_reuse_enabled=true`；Source SHA256 `057b7ba2…59ce8`，局部計時不是整場 FPS。 |
| 原 contact clock metadata | headless `132509_374` PASS 4.947 s。原 `_combat_bake` 只保留已載入 clip／方向的固定時間描述，不是姿態／碰撞結果快取；1,080 authored sample boundaries／loop-end、1,189 原 Actor／soldier lunge、988 eager／guard-only clip 查詢精確對照，含 training／fatigue／aim 原公式。沒有未來姿態或放大 reach；本次 headless 不冒充連續 mesh／GPU parity。 |

本批 **16 runs／64 檔**原 `result.json`、`stdout.log`、`stderr.log`、`combined.log` 已永久封存於既有 `verification/`，每檔與 canonical 原檔 SHA-256 一致，见 [完整清單](output/site_combat_performance_20260913/verification/archive_130601_132509_sha256.json)。名單包含上表、`131152_801`，以及 m25 validate／prepare／五批 GPU／publisher；全部 exit 0／未逾時，headless 的已知 root-certificate noise 仍保留。沒有覆寫不同內容、刪除原 run、改 helper 或修改原測量。本次文件／歸檔子任務未啟動 Godot。

### 13:26–13:44 lining／scalar 局部回歸及新混合短測

[133506_359 原量測](output/site_army_combat_realtime/72292909da52fb55/mixed_equipment_short10/1789277709_1953344/measurements.json) 為原 `--m25-performance-catalog --short=10`；helper PASS／exit 0／39.288 s，**`targets_met=false`**。98 幀／10.420150 現實秒，9.40485501648249 FPS、P95 462.523 ms、最長幀 488.157 ms；input 與原動作完成約 5.267584 s，input-wall 0.5055190184、內部 delta 差最多 `5.95e-14 s`。200 原 row／1,018 物品守恆、4,781 Nodes 前後不增、正常 HUD、戰中 BUSY、混合配裝及窗口來源穩定皆通過；40 真有效命中、20 人受傷、0 死亡／KO，最長交戰僅 5.259251 動作秒。此批確實使用當時可用的 test-only m25，`manual_simulation_calls=0`；主控已人工檢視當次 `02_final.png`，不宣稱看過全部畫面。FPS／P95／input-wall、完整 60 秒與 55 秒連續交戰均未通過，不把正常完成報告或單張畫面稱為流暢戰鬥。

此批 full-clock CPU 8,762.555 ms、contact CPU 5,126.361 ms；`teams_sample=6,446.149 ms`、`collect_geometry=4,128.087 ms`、`collect_narrow=121.000 ms`、Actors advance 1,038.258 ms。Source 記錄 44,428 sample calls／42,850 step hits，sample CPU 2,874.879 ms，`apply_appearance_usec=522679`。這些為原 owner 的巢狀診斷，不可相加；與 `131152_801` 的跨版本／原生不同 delta 短測也不是受控單變因 A/B，不能宣稱某局部優化已提高 FPS。

| 新切片 | 原結果與界線 |
| --- | --- |
| 私有 Source lining 批次 | 男 GPU `132638_456` PASS 12.530 s、女 `132757_041` PASS 14.231 s；[男 JSON](output/site_combat_performance_20260913/lining_batch/group_0.json)／[女 JSON](output/site_combat_performance_20260913/lining_batch/group_1.json) 各 10 exact pairs、最大誤差 0，另各 1 deliberate failure-path pair、2 outside-batch checks。原完整骨架／morph／armor／geometry／protection、真 body mesh 身分及 surface arrays、所有 mesh 可見性與 hair uniforms 對照相同。lining 實際更新各 61→13 次，候選 60 deferred／12 flushes；局部整個 pass 男 1,848,635→1,759,889 μs、女 1,962,920→1,813,664 μs。主控讀取兩體結果後啟用 lining；這不是 200 人 FPS 或人工逐圖驗收。 |
| 私有隱藏 footer | GPU `132921_154` PASS 12.638 s；[group 2 JSON](output/site_combat_performance_20260913/lining_batch/group_2.json) 單獨用男體、兩路 lining batch 都關閉，只切私有 labels／footer。10 exact pairs、1 failure-path pair、2 outside-batch checks，最大誤差 0；lining 皆實際 61 次。局部 pass 1,894,669→1,784,367 μs，不混為 lining 或整場收益，也不冒充女體 footer 獨立驗收。三份 lining JSON 的 Source SHA256 均為 `67d53cc9fd4827ca02bd9becafd171c0063c6e92db61c34e56e6acd1a59cfc23`。 |
| 原 timing scalar fast path | headless `133827_944` PASS 0.755 s；[原 JSON](output/site_combat_performance_20260913/scalar_timings/1789277908_475080/measurements.json) 包含原 12 clips、288 duration／4,896 sample 的 `==` 對照，training／fatigue 曲線及 windup／active／end 邊界 ±1e-9，最大誤差 0；12 份有效 public events 與無效 clip 的 fresh Dictionary 檢查通過。各 41,501 sample＋41,501 duration 呼叫原 events oracle **118,967→45,144 μs**，sample／duration checksum 完全相同。公開 events 與 invalid scalar 原慢路徑未改，但 `invalid_scalar_error_calls_executed=false`，不宣稱刻意觸發錯誤的 scalar 呼叫已在此成功測試執行。這是 headless 純函式計時，不是碰撞／畫面／FPS 驗收。 |

保留 `134433_269` 的 canonical **FAIL／exit 0／5.540 s**：`ComponentQueryEditor._active_hair_nodes`（當時 HumanEditor 第 2224 行）將無型別 `Array` 指派給 `Array[MeshInstance3D]`，經 `_update_hair_mask`／原配裝還原與 Source 初始化反覆產生 SCRIPT ERROR。雖最後 stdout 印出 pose-clock 的 1,080／1,189／988 PASS 文字，整批仍有 runtime error，**不可當成 scalar 後 pose-clock 回歸 PASS**。主控已定位 hair 型別修正；本節只核對這批既有失敗，不提前算尚未提供的重驗結果。

timings 的新 SHA256 為 `2b4a7fd047fa437437d5f2a71bd9fb2fedd293d3f3b265d8fd971ba35d2699bb`、MD5 `9f51fd6bc484e4ac86235bd076a463fb`，不等於舊 m25 六來源中鎖定的 MD5 `a5eb93aaa94212c3bb7dddbdba932ae4`。截至本批指定核對，新的 scalar staging 尚未 prepare／烘圖；舊 test catalog 的歷史量測保留，但當前來源 admission 必須拒絕它，不改舊指紋使其假裝同源。

以上 **6 批／24 檔**原 `result.json`、`stdout.log`、`stderr.log`、`combined.log` 已複製至既有永久 `verification/`，每檔和 canonical 原檔 SHA-256 一致，見 [本批封存清單](output/site_combat_performance_20260913/verification/archive_132638_134433_sha256.json)。完整保留 FAIL、原 stdout PASS 文字、錯誤及 root-certificate noise；不覆寫不同內容、不刪原 run。本次只更新文件／封存紀錄，未啟動 Godot 或修改 production／tests。

### 13:45–13:53 原 hair／validated key 與新 scalar m25 完成

`134540_057` 為真正完成的 pose-clock **headless PASS／exit 0／4.834 s**：原 1,080 authored sample boundaries／loop-end、1,189 Actor／soldier lunge 及 988 eager／guard-only clip exact，沒有 SCRIPT ERROR。它是前節 `134433_269` hair typed-array 錯誤修正後的獨立回歸，不能把旧 FAIL 改成 PASS，也不是 continuous mesh／GPU parity。

| 切片 | 新結果與界線 |
| --- | --- |
| 原當前 model／hair ID 查詢重用 | 男 GPU `134652_684` PASS 15.642 s、女 `134755_554` PASS 15.639 s；[男 JSON](output/site_combat_performance_20260913/actor_hair_lookup/body0/1789278414_1419167/measurements.json)／[女 JSON](output/site_combat_performance_20260913/actor_hair_lookup/body1/1789278477_1419168/measurements.json) 各 23 hair exact pairs、58／66 current-head shader checks，`shared_source_invalidation=true`。原同 Actor 的全部八款 hair／A→B→A／none、盔甲與頭盔、同 yaw 不同 head pose、真 body replacement／clear，以及完整 bones／morphs／body／weapon／parry／shield／armor 與六項 shader uniforms 對照相同。 |
| 單一已驗非 baseline canonical key | GPU `134951_966` PASS 15.072 s；[原 JSON](output/site_combat_performance_20260913/validated_key/1789278606_14610819/measurements.json) 兩路都開原 appearance validation reuse，僅切 key reuse；每路 14 exact geometry／bones／morphs／armor／protection snapshots、最大誤差 0。caller mutation／重排／A→B→A／原本允許的額外欄位及原生命週期仍測；僅保留既有一份已完整驗證配裝對應的一份 canonical key，不按 caller 身分猜測。41,501 次 validation＋key 局部計時 243,006→71,368 μs，產生的 key values 都為 664,016，非 200 人 FPS。 |

hair 的 658 次原 mask 呼叫，原／重用 lookup 搜尋 658→1、hits 0→657；男 `lookup_usec=293132→914`、整個 mask `297895→3870`，女 `361930→1146`／`372893→4612`。這只是固定原 model 的局部 A/B，不少算 mask 呼叫、head pose 或 shader 更新。主控讀取男女 JSON 並人工檢視各 `current_body.png`＋`replacement_body.png`，共四張代表圖；報告明列 `frame_pairs=0`、`step_pairs=0`，**不是完整畫面的 pixel A/B**，不借用舊 cloth 的 54／18 數字。當時 HumanEditor SHA256 `f78a33ef…51695`、Source `33acc4b1…cd50e`；主控在各自 PASS 後才啟用 hair reuse 與 validated key reuse。

另保留 hair test 最初 `134602_356` **FAIL／exit 1／1.426 s**：測試把 preload 的 QuerySource 當作有靜態 `resource_path` 成員，解析失敗，未取得 hair 驗收。主控只把該測試的來源路徑改為明確常數，`134624_982` check-only PASS 1.116 s 後，才執行上述男女 GPU；解析檢查本身不當作運行 PASS。

新配方使用獨立 `output/terrain_army_m25_scalar_20260913/`：`135027_223` validate-only PASS 2.225 s、`135046_120` prepare PASS 2.690 s，鎖定 scalar timings MD5 `9f51fd6bc484e4ac86235bd076a463fb`、HumanEditor `236a5b4eb826e87845682646553d0414` 及其餘原四來源。以下均是沿原 640×768 視窗／AnimationPlayer／裁切與錨點的真實 GPU 烘圖，沒有借舊 PNG 重標新指紋：

| 新 scalar m25 batch | Canonical GPU run | helper s | 原始／PNG／RES decoded pixel SHA 與前版 |
| --- | --- | ---: | --- |
| `000_128`（0–127） | `135104_911` PASS | 7.784 | 三者一致且與 v1 同值；本輪主控人工重看 |
| `128_128`（128–255） | `135146_299` PASS | 7.986 | 三者一致且與 v1 同值；本輪只核對摘要 |
| `256_128`（256–383） | `135223_854` PASS | 8.292 | 三者一致且與 v1 同值；本輪只核對摘要 |
| `384_128`（384–511） | `135246_067` PASS | 8.167 | 三者一致且與 v1 同值；本輪只核對摘要 |
| `512_024`（512–535） | `135311_121` PASS | 7.041 | 三者一致且與 v1 同值；本輪主控人工重看 |

本次唯讀覆核五份新／舊 manifest，確認全部 `pixel_sha256 == png_decoded_sha256 == resource_decoded_sha256`，且各批與 v1 同值；主控先前已看 v1 五頁，**本次只人工再看新 000_128／512_024 兩頁，不宣稱新五頁都人工重看**。`135351_114` test-only publisher **headless PASS／exit 0／2.571 s**，確認五批完整 536 keys、另外 31 masks 拒絕、正式 catalog 不變，輸出 [新 test catalog](output/terrain_army_m25_scalar_20260913/test_catalog.json)。後續測試選擇器為 `--m25-scalar-catalog`；這補上前節 13:44 尚未 prepare／重烘的歷史待辦，不改舊 m25 指紋，也不宣稱正式 32 配方或全場效能驗收已完成。

上述 **14 批／56 檔**原四檔已永久歸檔，逐檔 SHA-256 與 canonical 相同，見 [本批封存清單](output/site_combat_performance_20260913/verification/archive_134540_135351_sha256.json)。唯一 FAIL 為 `134602_356`，其他指定 run 都 exit 0／無逾時；原解析錯誤及已知 root-certificate noise 保留，不覆寫不同內容、不刪原 run。此文件／封存子任務未改 production／tests，也未啟動 Godot；進行中的新 full60 必須另讀完成報告才判定，不先沿用 helper、短測或局部 PASS。

### 13:54 完整 60 秒現實窗口：量测完成，但流暢目標失敗

[135413_446 原 full60 量測](output/site_army_combat_realtime/6f5dbfd39fbeab0c/mixed_equipment_full60/1789278856_1903547/measurements.json) 使用 `--m25-scalar-catalog`，沒有 `--short`；helper PASS／exit 0／88.501 s、無逾時，只表示正常完成報告。原自動 Lab／Actor／Army、200 原 row、正常 HUD 及混合真裝備，**`completed_60_wall_seconds=true`，但 `targets_met=false`**。762 畫面／60.343224 現實秒，12.6277641380248 FPS、P95 415.893 ms、P99 631.588 ms、最大間隔 686.818 ms；距 30 FPS／P95 ≤33.334 ms 仍很遠。

| 完整現實窗口 | 畫面 | FPS | P95 ms |
| --- | ---: | ---: | ---: |
| 0–10 s | 142 | 14.2 | 391.746 |
| 10–20 s | 107 | 10.7 | 446.148 |
| 20–30 s | 195 | 19.5 | 387.924 |
| 30–40 s | 108 | 10.8 | 414.849 |
| 40–50 s | 192 | 19.2 | 350.968 |
| 50–60 s | 17 | **1.7** | **686.818** |

另有尾端 0.343224 s／1 畫面，不冒充第七個完整十秒段。六段全部低於 30 FPS，最後一段尤其差；本報告没有提供足以將最後一段衰退歸因於單一機制的受控比較。input 30.2409253333335 s、原動作 30.2409253333323 s，input-wall 0.5011486515；內部 delta 債最多 `1.123e-12 s`，只是完成引擎交付的時間，**不是跟上現實時間**。最長連續交戰僅 30.232592 動作秒，`continuous_combat_at_least_55_seconds=false`。無單次 >1 s 停頓與無內部時間債通過，不抵銷低 FPS／P95／時間追隨失敗。

本次 142 真有效命中、22 人曾受傷，最終 20 原人物死亡且 20 已結算地面容器、180 存活、KO 0；原 200 row 身分與 1,018 物品／cargo 守恆、4,781→4,781 Nodes、正常 HUD、戰中存檔 BUSY、無非預期暫停、所有來源在窗口內不变皆 true。主控已人工檢視 `02_final.png`；這是實際傷亡／地面物資與守恆證據，不是即時效能 PASS，亦不把其跨版本 FPS 和較早 short10 當作單一候選收益。

full-clock CPU 50,443.960 ms、contact CPU 29,763.874 ms；`teams_sample=35,818.801 ms`、`collect_geometry=24,761.174 ms`、`collect_narrow=540.873 ms`。原疲勞 `people_inclusive=5,993.469 ms` 內含 `fatigue_threat=3,444.729 ms`；Actors advance 3,837.232 ms。Source 235,319 sample calls／216,561 step hits／5,273 terminal hits，sample CPU 19,552.347 ms；13,485 sample pose evaluations 與 13,509 true pose evaluations 是原報告兩個不同計數，不互換。原 seek 4,477.201 ms、select clip 2,596.888 ms、shared pose 9,706.588 ms。**上述多項互相包含，不可相加或轉算未量測的 FPS 收益**；此 full60 也早於下面 two-hop 啟用，不能聲稱含其後收益。

### 14:00–14:04 方向 0 角色替換與疲勞 two-hop 局部回歸

`140037_090` GPU **PASS／exit 0／39.697 s**，僅 `--direction=0 --direction-suite --performance-run`：source／target 各 idle、guard、ally、moving，共 8 原 player／NPC baseline 對真普通 row 替換 pairs。完整 packets／HP／contact tick 及 moving 原目的格一致；idle 傷害 15／tick 145、guard 傷害 15／tick 146、ally 被擋且無封包、moving 傷害 6／tick 136 沿各 baseline 原值，沒有改成理想化結果。當批八張 baseline PNG 已產生但主控尚未人工檢視；**不宣稱人工畫面驗收或新完整四向 PASS**，其餘方向另待完成結果。

`140430_635` headless **PASS／exit 0／5.290 s**：105 checks，17 個新增 two-hop positive witnesses、46 retained BFS cases；開／關兩路皆與原 forward eight-step BFS exact，整個測試共 45 positive-fast／109 original-BFS-fallback。使用原 TerrainData 的 reciprocal ramps／障礙、原 Actor＋100 Army rows、原 movement seed 及 headless projectile fallback，不造單向圖，不省略無正面證明時的原 BFS。主控在 PASS 後才啟用 `fatigue_two_hop_witness_enabled=true`；這是有界正面可達性證明，不改疲勞規則，也不是 GPU／新 FPS 驗收。

這三批原 `result.json`／`stdout.log`／`stderr.log`／`combined.log` 共 **12 檔**已永久封存並逐檔核對 canonical SHA-256，見 [本批清單](output/site_combat_performance_20260913/verification/archive_135413_140430_sha256.json)。原 full60 的 `TARGETS_NOT_MET` 與已知 root-certificate noise 完整保留，不改舊量測、不刪原 run。本次僅補文件／封存，沒有執行 Godot 或修改 production／tests。

14:05 補驗 `140518_567`：方向 1 的原角色替換 suite **GPU helper PASS／exit 0／34.676 s／無逾時**。本次只據原 stdout 的 source／target × idle／guard／ally／moving 共 8 組 baseline／replaced exact pairs：idle 盾接觸 HP 0／stun 0／tick 128，guard 盾接觸 HP 0／stun 3／tick 126，ally 無封包，moving 盾接觸 HP 0／stun 0／tick 128、原目的格 `[31,31]`，兩路完整封包及 HP 相同。沒有將「GPU 執行」混稱人工畫面驗收；方向 0 當時僅讀 JSON、尚未人工看八張 PNG，方向 1 此處也未新增 JSON／人工檢圖結論。仍只涵蓋方向 0／1，不稱四向完成。本 run 原四檔已永久歸檔、逐檔 SHA-256 與 canonical 相同，見 [四檔清單](output/site_combat_performance_20260913/verification/archive_140518_sha256.json)。本次沒有修改驗收目標或 production／tests，也沒有啟動 Godot。

14:11 補驗 `141129_599`：方向 2 suite **GPU helper PASS／exit 0／39.455 s／無逾時**，原 stdout 共八組 baseline／replaced exact pairs。source／target 各 idle 是 body HP 傷害 30／stun 18／tick 144，guard 為相同傷害／stun、tick 163；ally 被擋且無封包，moving 兩路都無封包、HP 100、目的格 `[29,31]`。完整 packets／HP／contact tick 及原目的格一致，不補造 baseline 未有的命中。本次只核對這些執行紀錄，主控尚待看代表 PNG，不宣稱人工畫面驗收；方向 3 當時仍在執行，沒有列成 PASS。本 run 原四檔永久封存且逐 SHA-256 與 canonical 相同，見 [四檔清單](output/site_combat_performance_20260913/verification/archive_141129_sha256.json)。需求來源標示修正沒有改動任何舊量測數字／`targets_met=false`／FAIL、production 或 tests；本次未啟動 Godot。

### 14:12–14:17 四向角色替換數值完整及男組 mesh lookup

`141255_238` 方向 3 suite **GPU helper PASS／exit 0／34.535 s／無逾時**，原 stdout 八組 source／target × idle／guard／ally／moving 的 baseline／replaced exact pairs。idle 盾接觸 HP 傷害 0／stun 0／tick 128，guard 盾接觸 HP 傷害 0／stun 3／tick 126，ally 無封包，moving 同 idle 接觸／tick、兩路原目的格 `[29,29]`。與前述方向 0／1／2 共 **四向 32 pairs 的 packets／HP／contact tick 數值對照通過**；此段補上先前尚待 direction 3 的歷史狀態，不改原紀錄。

主控現已實際檢視四張代表 baseline PNG，分別為 [dir0 target_moving](.visual_captures/site_role_matrix_performance_20260913/1789279239_1892595/target_moving_direction0_baseline.png)、[dir1 target_guard](.visual_captures/site_role_matrix_performance_20260913/1789279520_1852474/target_guard_direction1_baseline.png)、[dir2 target_ally](.visual_captures/site_role_matrix_performance_20260913/1789279891_1921710/target_ally_direction2_baseline.png)、[dir3 target_moving](.visual_captures/site_role_matrix_performance_20260913/1789279977_1845021/target_moving_direction3_baseline.png)。**不是全部 32 張人工看圖，也不是 FPS 或整個畫面的 pixel A/B**；早前未看圖文字為當批歷史狀態，此處明確補上實際已看的四張。

新 `_combat_mesh_nodes`／Geometry `_mesh_nodes` 沿私有 Source 既有 `_component_nodes` invalidation，只重用原 `find_children` 有序節點參照；原一般 Actor 保留 native 遍歷，原可見性／mesh／skin／pose／護甲判斷仍每次執行。男 GPU `141748_972` **PASS／exit 0／10.353 s**；[男組原 JSON](output/site_combat_performance_20260913/collision_mesh_lookup/body0/1789280278_9900109/measurements.json) 為 11 原完整 snapshots exact、最大誤差 0，含實際配裝／可見性／morph、一般 Actor fallback、唯讀回傳陣列、root 替換及同 root 明確清除後的節點順序。6,000 次 lookup 兩路均數到 668,000 個節點參照，局部計時 590,377→6,170 μs；11 snapshots 整段 619,230→526,358 μs。Source SHA256 `1d7e7b74…3e85c6`、Geometry `50f93d23…672340`；**是男體局部幾何回歸，不是人工畫面或整場 FPS 收益**。截至這次指定核對，`collision_mesh_lookup_enabled=false`，女組尚未取得完成證據，不先稱男女皆過或已啟用。

上述兩 run 原四檔共 **8 檔**已永久歸檔，逐檔 SHA-256 與 canonical 相同，見 [本批清單](output/site_combat_performance_20260913/verification/archive_141255_141748_sha256.json)。本次只做文件／封存及限定 getter／測試唯讀檢查，未修改 production／tests 或啟動 Godot；全部既有未達標數字與失敗歷史保留。

### 14:18–14:21 女組 mesh lookup、原生匯出與排序反例

`142002_167` 女組 mesh lookup **GPU helper PASS／exit 0／10.844 s**；[女組 JSON](output/site_combat_performance_20260913/collision_mesh_lookup/body1/1789280412_10392552/measurements.json) 同樣 11 exact pairs／最大誤差 0。6,000 次 lookup 原／重用均回報 666,000 個節點參照，590,382→6,375 μs；11 snapshots 整段 645,633→543,620 μs。測試初態先修為原 `default_appearance(body).parts.hair`，避免只改 female body 卻保留男髮的非法 fixture；未改比較門檻，亦沒有把這個執行前唯讀發現造作一次實際 FAIL。男女 Source／Geometry SHA256 與前節相同。限定 getter 覆核未見目前私有固定模型的確定問題：只回傳原有序參照，正常 Actor 原遍歷、每次可見性／姿態／護甲判斷及原 root／explicit invalidation 保留；未來同 root 的新增／刪除／改名／重排仍須原 owner 明確清除。主控在男女 PASS 後啟用，這次唯讀確認 `collision_mesh_lookup_enabled=true`。局部微秒不是新 FPS，沒有新增人工畫面驗收。

`141845_157` 原生資料 exporter **GPU helper PASS／exit 0／10.530 s**，原 log 記 32 animations、68 meshes、2,210,300 keys、`sample_calls=0`，匯出器本體 8,462,101 μs。輸出 [native.json](output/site_combat_performance_20260913/native_bounds/1789280332_1413052/native.json) 的記錄 SHA256 為 `5d35a6efc512f6138d8d5d67db8e55bd9bf68c0bea3a91879bcfb5d589d79d63`；明列 **`curve_contract=UNSUPPORTED`、`bound_proven=false`**，唯一列出的 unsupported 為有 morph 的 `Weapon_Bow_01_String`，不能假設其界限。這只證明資料匯出完成，沒有 native bound 正確性／新裁切／碰撞精度或 FPS PASS，也不把 GPU 執行稱為人工看圖。

`142100_577` 原排序反例 **headless PASS／exit 0／1.506 s**，其成功意思是**成功確認 `direct_cull_safe=false`**，不是准許一般提前剔除。原三目標排序 `[5,3,4]` 後再移除已命中的 3 得 `[5,4]`，先剔除再排序卻得 `[4,5]`；六種 permutation 都保存相應反例。另有 24 個最多只剩一個 survivor 的特例檢查，但不能外推為一般候選安全。原 Lab sorter／comparators 不變，scope 明列沒有 production culling／新 geometry／整場戰鬥或效能驗收。

三批原四檔共 **12 檔**永久封存並逐 SHA-256 核對 canonical 相同，見 [本批清單](output/site_combat_performance_20260913/verification/archive_141845_142100_sha256.json)。保留原 `UNSUPPORTED`／`bound_proven=false`／反例及已知 root-certificate noise；沒有改舊資料、production／tests 或執行 Godot。

### 14:22 第二次 full60：包含 two-hop／mesh lookup，仍未達標

[142201_842 原量測](output/site_army_combat_realtime/7063a3c9320a6da3/mixed_equipment_full60/1789280524_1841919/measurements.json) 為原 `--m25-scalar-catalog` 自動完整窗口，helper **PASS／exit 0／88.327 s／無逾時**，stdout 與 JSON 仍明列 **`TARGETS_NOT_MET`／`targets_met=false`**。877 幀／60.000758 現實秒，14.6164820117773 FPS、P95 385.505 ms、P99 532.075 ms、最長幀 657.719 ms；相同 1400×900／正常 HUD／原混合配裝場景，不以手動 batch 或少算人物代替 FPS。

| 完整現實窗口 | 幀 | FPS | P95 ms |
| --- | ---: | ---: | ---: |
| 0–10 s | 165 | 16.5 | 366.223 |
| 10–20 s | 174 | 17.4 | 376.589 |
| 20–30 s | 176 | 17.6 | 368.453 |
| 30–40 s | 172 | 17.2 | 368.372 |
| 40–50 s | 168 | 16.8 | 345.811 |
| 50–60 s | 21 | **2.1** | **649.207** |

原報告另留不足完整窗口的尾端 0.000758 s／1 畫面，不將它的瞬間比值當作有效效能段。六個完整十秒段均未達 30 FPS，最後段仍有明顯長幀。input 31.6173780000001 s、action 31.617377999999 s，input-wall 0.5269496429；內部 delta 差最多 `1.105e-12 s` 仍只是完成引擎交付時間，不是現實時間跟上。最長連續交戰 31.609045 動作秒，本輪 55 秒連戰覆蓋旗標 false；此場即使不將覆蓋不足當作 FPS 判斷，幀率、P95 與時間追隨本身仍失敗。

本次 141 真有效命中、21 人曾受傷，最終 20 死亡／20 已結算容器、180 存活、KO 0；原 200 rows、1,018 items／cargo 守恆、4,781→4,781 Nodes、正常 HUD、戰中 BUSY、無非預期暫停／>1 s 單次停頓及窗口全部 fingerprints 穩定皆通過。主控讀取關鍵 JSON／stdout，並實際看 `02_final.png`；不宣稱人工看完整 60 秒每張畫面。

這批包含已啟用的 `fatigue_two_hop_witness_enabled` 與 `collision_mesh_lookup_enabled`，前次 `135413_446` 不含兩者。兩次觀測為 FPS 12.627764→14.616482、P95 415.893→385.505 ms、input-wall 0.501149→0.526950；**同時有多項改動且原生 delta／命中歷史不同，不能當作其中任一候選的受控單變因收益**，更不是目標完成。native bound 當時仍未落地，此量測沒有包含它或證明其安全。

新 full-clock CPU 48,537.962 ms、contact CPU 27,751.930 ms；`teams_sample=33,898.697 ms`、`collect_geometry=22,672.778 ms`、`collect_narrow=537.579 ms`。`fatigue_people_inclusive=5,530.478 ms` 內含 threat 2,802.362 ms，Actors advance 3,994.539 ms。Source 242,118 sample calls／219,784 step hits／6,682 terminal hits，sample CPU 17,343.630 ms；15,652 sample pose／15,678 true pose evaluations，seek 5,006.665 ms、shared pose 10,429.072 ms。巢狀分項不可相加；取樣次數亦不同，不能只拿兩批微秒相減稱保證收益。

本 run 原四檔已永久封存，逐檔與 canonical SHA-256 相同，見 [四檔清單](output/site_combat_performance_20260913/verification/archive_142201_sha256.json)。原測量、`targets_met=false` 與之前所有失敗紀錄不改；本次只做文件／歸檔，未執行 Godot 或修改 production／tests。

### 14:39 capsule 固定環方向局部驗收

`143912_828` **headless PASS／exit 0／1.282 s／無逾時**，原 [combined.log](output/site_combat_performance_20260913/verification/20260913_143912_828/combined.log) 記 **10,018 exact cases／最大誤差 0**；只將原固定 ring directions 計算一次，保留原生多邊形結果。原／重用局部計時 30,645→20,498 μs，Geometry SHA256 `c7806e32bd8c158f940ff8cc25406de2e79cea5ea4de3a4c5c95614ee482c3f0`。這不是 GPU 人工看圖、整場命中或 FPS 驗收，也沒有新增 full60；不將局部微秒換稱流暢目標完成。

本 run 原 `result.json`／`stdout.log`／`stderr.log`／`combined.log` **四檔**已永久保留並逐檔核對 SHA-256 與 canonical 相同，見 [四檔清單](output/site_combat_performance_20260913/verification/archive_143912_sha256.json)。已知 root-certificate noise 保留，未改原結果、production／tests 或執行 Godot。

### 14:59–15:07 私有 constant morph 精確驗收與 bounds 尚待

| Canonical run | 原結果／helper s | 實際範圍與失敗保留 |
| --- | --- | --- |
| `145937_079` | **FAIL**、exit 0、15.854 | GPU constant group 0 同時記錄新 bounds helper 的 `Basis.get_column` 解析錯誤與整包 snapshot byte assertion。遞迴診斷指向相同 NodePath 的 padding；stdout 的 PASS 不採信，不把兩類失敗消失後的結果回填此批。 |
| `150104_907` | check-only **PASS**、exit 0、1.134 | 只解析 `site_army_source_bounds_test.gd`，不是實際模型准入／碰撞或 FPS 驗收。 |
| `150132_590` | **FAIL**、exit null、25.138、timed_out | 首次 GPU bounds group 0 回傳 `radius=256`／`SKELETON_MODIFIER_OR_MOTION_SCALE`，斷言後達原 helper 上限。保留原拒絕及逾時，未取得較小 bounds PASS。 |
| `150403_021` | **FAIL**、exit 1、5.834 | 改為即時回報診斷後，仍由同一原守衛拒絕；原 evidence 為 `motion_scale=1`、`show_rest_only=false`、自動 `PhysicalBoneSimulator3D`／`active=true`／`influence=1`。後續對空 simulator 的處理不屬本批通過證據。 |
| `150509_310` | native headless **PASS**、exit 0、1.216 | 37 guards／306 原生插值 samples；同一 NodePath 64 次編碼得 47 種 bytes，完整路徑語義相同，正負零仍拒絕。已知 root-certificate noise 保留。 |
| `150526_809` | GPU group 0 **PASS**、exit 0、21.260 | 8 個完整 exact snapshots、678,096 次原生插值比對；同 Source、同 seed／歷史、倒地終點→另一姿勢→倒地／反向 seek、卸裝再穿、護甲／防守／瞄準。 |
| `150606_884` | GPU group 1 **PASS**、exit 0、20.898 | 10 個完整 exact snapshots、678,096 次原生插值比對；原長劍／長槍／弓／弩／徒手配裝與 guard／aim。`history_completed=true`，非子函式失敗後誤印 PASS。 |
| `150756_011` | **FAIL**、exit 0、1.216 | native 重跑遇新 bounds helper 的 `empty_native_simulator` bool 型別無法推導及相依編譯錯誤。雖仍印 37 guards／306 samples、50 種 NodePath bytes 與 PASS，整批 canonical 仍 FAIL，不當作啟用後完整回歸。 |

原 [native 診斷](output/site_combat_performance_20260913/constant_morph/1789283110_949996/measurements.json) 以 native float bits 區分 `+0`／`-0`，並驗 Linear／Nearest、三種 loop／wrap、壓縮、非 morph、非零／NaN／Inf、transition、首時間／重複時間／逆序／超長／空單 key 等守衛。Godot 4.6.2 [NodePath 編碼原碼](https://github.com/godotengine/godot/blob/4.6.2-stable/core/io/marshalls.cpp#L1389-L1430) 寫字元後跨過未初始化 pad；測試 oracle 因此只改為遞迴比較原型別、字典原 key 順序、typed containers、NodePath 全 string／absolute／各 names／subnames，**所有 scalar／Vector／Basis／Transform／PackedArray 數值位元（含正負零）仍 exact**。原 native library digest 同樣保留完整值位元與路徑 metadata，不再宣稱含未初始化 padding 的整包序列化 bytes 相同；新增反例驗證路徑／型別／正負零的真正差異仍會失敗。這是測試 oracle 修正，不是放寬 production 幾何或 interpolation。

兩組 [GPU 0 原 JSON](output/site_combat_performance_20260913/constant_morph/1789283147_20926760/measurements.json)／[GPU 1 原 JSON](output/site_combat_performance_20260913/constant_morph/1789283187_20574900/measurements.json) 皆實際掃過普通男兵 Source 的 **59 clips／44,221 tracks**，原 **2,720,390 keys → 私有 465,506 keys**；37,672 條合格恆正零 morph track 各保留原第 0 key，共刪除私有重複 2,254,884 keys。全部原 tracks／paths／enabled／loop／length 保留，骨 position／rotation／scale 與非合格曲線不改；兩路完整骨架、所有含未穿著者 morph、實際護甲頂點、sample／protection 及原 native 參照完整值／路徑 digest 相同。這是原一個非渲染查詢 owner 的初始化精簡，沒有逐兵 rig、未改原 HumanEditor／GLB／Timings／atlas，也不外推為女性 live owner 的新驗收。

原 Source 初始化計時 group 0／1 分別 4,985,565／3,662,221 μs；重建私有複本並執行精簡 1,789,599／1,786,710 μs。二者工作範圍不同，**不能相減稱單項加速，也不是戰鬥 FPS**。兩個 GPU PASS 當次 Source SHA256 為 `fe0c71d34379b3f51632bcb87f219f6ab091269bf63328c9d48dc51faf4cb8ed`；通過後只將 constant 預設改 true、測試每個 `Source.new()` 明確 false 作原始 A/B 起點。啟用後交接 Source SHA256 `92aaabe26380bd9c582a336d213c4a2cb55a6b01d505c451d8af1a1f834c459f`，test `1f7ba233c7b6f57a2135a6ccae80926db3c89fca8cb710f1cc877d0e9a7efbe0`；bounds 仍關閉，其後來源變更須另驗。沒有新增 PNG／人工畫面驗收、正式 32 atlas 或完整即時 FPS PASS。

上述 **8 批／32 檔**原 `result.json`、`stdout.log`、`stderr.log`、`combined.log` 已永久複製至既有 `verification/`，逐檔 SHA-256 與 canonical 原檔一致，見 [本批完整封存清單](output/site_combat_performance_20260913/verification/archive_145937_150756_sha256.json)。所有 FAIL、原錯誤後 PASS 字樣、25.138 秒 timeout 與已知 certificate noise 都保留；不覆寫不同內容、不刪原 run、不改 helper／原 JSON。本次只補文件與 archive，未改 production／tests、未執行 Godot，也不提前列尚未完成的新 full60。

### 15:09 constant 啟用回歸與 bounds 兩組局部 PASS

`150912_269` **headless PASS／exit 0／1.186 s**，為前節 `150756_011` 相依型別錯誤修正後的獨立 run；原 37 guards／306 native samples 通過。同一 NodePath 64 次編碼得 50 種 bytes，但完整路徑相同，真正正負零差異仍被拒絕。當時 Source 預設 constant true，測試明確從 false 起點再驗 true；只證明原 native guards／copy gate，不稱 GPU 或 FPS 回歸。

`150932_212` bounds group 0 **GPU helper PASS／exit 0／7.998 s**：43 cases、7,173 個實際 body／shield 頂點；`150957_626` group 1 **PASS／exit 0／8.154 s**：7 cases，主要為不符契約的 fallback，`vertices_checked=0`，不可沿用 group 0 頂點數。兩組原輸出皆為 `NATIVE_CONTINUOUS_NONATTACK`，連續實數界 `114.305518688431 px`、明列浮點外擴 1 px、候選 radius 128 px、世界座標限制 16,384；讀取 1,791 個原 position keys、四個 face 與十個 shield。允許 clips 是 idle／walk／run／hit／hit_back／knockback／down／unconscious／get_up／rescue／reload_bow／reload_crossbow，沒有將 attack／guard 或未知條件納入較小界。

group 0 採樣最大含 offset 半徑為 `97.4170150756836 px`，**樣本頂點不是全時間的數學證明**；較小界依原 native 資料／操作契約建立，而 samples 只作定向回歸。原 fallback 覆蓋 modifier／motion scale、正交 viewport／camera、model root、single-clip、非原普通步兵模型，以及 group 1 的 native time／transition、未知軌、骨鏈 numeric envelope、collider mesh／skin、已保留 head-fit envelope；原 256 路徑仍保留。此處只核對已執行的數值／拒絕結果，不自行補宣稱所有可能契約變更都已驗證。

兩組 Source SHA256 `92aaabe26380bd9c582a336d213c4a2cb55a6b01d505c451d8af1a1f834c459f`、bounds helper `fb7b0e5525858fade9041738067eef9fb73aa8b91949f0814a75daf99c02ef61`；原 build 計時 146,421／147,172 μs 只是建界局部耗時。**`conservative_nonattack_bounds_enabled=false` 仍保留；沒有外觀圖人工驗收、原全場 contacts 排序等價或 200 人 FPS 收益結論。** 正在執行的 constant-only full60 尚未納入本次文件，不將待驗整合或新完整窗口先寫 PASS。

此追加 **3 批／12 檔**原四檔亦已永久封存、逐 SHA-256 與 canonical 相同，見 [追加清單](output/site_combat_performance_20260913/verification/archive_150912_150957_sha256.json)。連同前段共 **11 批／44 檔**；全部舊 FAIL／timeout／noise 不改，本次無新 Godot 執行與 production／test 編輯。

### 15:10 constant true／bounds false 的新完整窗口：仍未流暢

`20260913_151040_958` 原 visual helper **PASS／exit 0／90.602 s**，只表示有界測試正常完成；[原 measurements.json](output/site_army_combat_realtime/1d0e2e08c5cb8f9a/mixed_equipment_full60/1789283443_1857667/measurements.json) 明列 `measurement_complete=true`、`targets_met=false`。這次是 `--m25-scalar-catalog` 的原 200 人混合實装、自動 `_process`／正常 HUD，constant key 精簡 true、保守非攻擊界 false，沒有手動補幀或改原動作時鐘。

868 呈現幀／60.072320 現實秒，**14.4492505 FPS，P95 385.891 ms，P99 526.213 ms，最大 596.974 ms**。引擎交付／實際動作約 31.618769 秒，input-wall `0.5263450621`；最長連續交戰僅 31.610436 動作秒。內部 delta 債約 `1.04e-12 s` 只證明已處理引擎交付時間，不能抵銷半速。FPS、P95、時間追隨、六完整十秒皆 30 FPS、55 秒連戰覆蓋旗標仍 false。

| 完整現實區段 s | 幀 | FPS | P95 ms | 最大 ms |
| --- | ---: | ---: | ---: | ---: |
| 0–10 | 161 | 16.1 | 377.136 | 529.338 |
| 10–20 | 171 | 17.1 | 369.220 | 401.057 |
| 20–30 | 182 | 18.2 | 355.285 | 497.678 |
| 30–40 | 133 | 13.3 | 382.046 | 449.291 |
| 40–50 | 198 | 19.8 | 298.146 | 567.130 |
| 50–60 | 22 | 2.2 | 581.859 | 596.974 |

另有 60–60.072320 秒的一幀尾段，不作第七個完整十秒。最終仍 200 個原 rows：180 活人、20 dead／20 settled、KO 0、13 attacking；142 有效命中、22 原人物曾受傷、20 原地面容器，1,018 件物品守恆。Nodes `4,781→4,781`，memory `729,999,472→734,801,856 bytes`；原身分／物品／HUD／BUSY／來源穩定／無非預期暫停與無 >1 秒單次停頓旗標通過。主控已讀 stdout／JSON 並檢視 [當場最終圖](output/site_army_combat_realtime/1d0e2e08c5cb8f9a/mixed_equipment_full60/1789283443_1857667/02_final.png)；這不抵銷長幀與原時間追隨失敗，也不宣稱正式 32 配方完成。

原 full-clock CPU `48,613.828 ms`，contact CPU `27,523.056 ms`；Lab `teams_sample=33,731,096 μs`、`collect_geometry=21,333,642 μs`。Source 的 241,399 sample calls／218,396 step hits／7,026 terminal hits 中，`true_pose_evaluations=16,001`、`seek_usec=3,364,718`、`select_clip_usec=2,848,957`；原 clip-reset 計時 armor `1,199,879 μs`、cloth `602,069 μs`。這些是**巢狀計時，不能相加**；即使假設整個 seek 成本消失也僅是此 full-clock CPU 的約 6.9% 理論上限，常值 morph 只是其中一部分，不能推算 30 FPS。相較先前 `142201_842` 的 14.616482 FPS，本次沒有證據支持宣稱整體幀率改善；不同來源／姿態／命中數也不構成單項受控收益 A/B。

本批原四檔已永久複製至 `verification/20260913_151040_958/`，與 runner 原檔逐一 SHA-256 及大小相同，見 [封存清單](output/site_combat_performance_20260913/verification/archive_151040_sha256.json)。保留先前所有 FAIL、量測 JSON 及本批 `TARGETS_NOT_MET`，沒有改 production／test、啟動 Godot或修改原結果。

### 15:21–15:24 原生保守界 v4 與原 collector 整合 PASS

本批逐一讀取 canonical 四檔與實際 JSON，五批都 exit 0、未逾時，沒有 script／assertion 錯誤；check-only 與執行驗收分開列。

| Canonical run | 模式／helper 秒 | 實際範圍 |
| --- | --- | --- |
| `152126_592` | headless check-only PASS／1.694 | 只解析新 `site_army_nonattack_bounds_integration_test.gd`；不是執行或 FPS 驗收。 |
| `152157_054` | GPU helper v4 group 1 PASS／8.263 | [12 cases／821 個真頂點](output/site_combat_performance_20260913/native_bounds/runtime_group1/1789284125_1491560/measurements.json)，含原 approximate-key lookup 微量外插、密集時間／缺端点、改值／skin／head-fit 等回退與還原。 |
| `152221_051` | GPU helper v4 group 0 PASS／8.110 | [43 cases／7,173 個真頂點](output/site_combat_performance_20260913/native_bounds/runtime_group0/1789284148_1416966/measurements.json)，四向 body／shield、實際幾何範圍、loop／原模型與投影條件回退。 |
| `152305_385` | GPU integration group 0 PASS／13.794 | [40 組完整 ordered contacts 精確對照](output/site_combat_performance_20260913/nonattack_bounds_integration/group0/1789284187_2352375/measurements.json)；同 4 個原 row、22 件原軍隊物品、1 位原女性呈現者與同一 Source。 |
| `152352_309` | GPU integration group 1 PASS／26.555 | [11 組完整 ordered contacts 精確對照](output/site_combat_performance_20260913/nonattack_bounds_integration/group1/1789284234_1914748/measurements.json)；同 5 個原 row、29 件原軍隊物品、2 位原女性呈現者，以及原男性玩家／女性 NPC。 |

v4 是實際 native 曲線／skin／投影建界，非手填碰撞半徑：連續界 `114.305518688431 px`、外加原生浮點誤差墊 1 px 後向外取整為 128 px；1,791 position keys、4 faces／10 shields。新 `maximum_position_extrapolation_metres=0.000111059354949567` 將原 approximate-find 的未 clamp 線性微量外插納入，而非假定所有 LINEAR 都是凸組合；密集／缺少端點等未證明條件拒絕。原 helper SHA256 `fd3c289b4e2d139c6b6a20a4605370184e17016a6940978bd663dd66791d5780`；數學條件與限制見 [PROOF.md](output/site_combat_performance_20260913/native_bounds/PROOF.md)。

整合 A/B 在同一原 Lab post-advance batch 內切換 false／true，以原動畫 body 多邊形及其平移診斷掃掠呼叫原 `_collect_army_contacts`／`_collect_unit_contacts`。完整 target／identity／fraction／point／shield／body／distance 與排序相等，不使用容差放寬。四向 idle／原合法 committed walk／down 的 12 組 far cases，原 Source 原生 pose／sample call 實際 `1／1→0／0`；近端真接觸保留，guard／attack 遠端仍 `1／1→1／1`。這證明具體無交集候選不再取樣，不是以空結果冒稱所有碰撞正確。

group 1 經**原名冊轉移**將同一女性／原 presenter 搬至 index 1，並讓原男性成為 index 0；兩者維持 256／原無條件檢查。兩次 mixed sweep 各收到原玩家、NPC、軍隊三個接觸且完整順序一致。世界 sweep 超过 ±16,384 與暫時超界的原 cell 仍走既有 exact bounds；後者明列為不可能由当前 128×128 生成器生成的數值回退 fixture，**不是更大遊戲地圖或合法超距攻擊的驗收**。同一 A/B 內原 HP／blocked／完整 state 不變、骨架數不增加、原人物 Dictionary／女性 presenter／Source 身分保持，並未在此測試結算一場傷害戰鬥。

主控完整讀取 stdout 後才將 `conservative_nonattack_bounds_enabled=true`；當次 A/B Source hash 為 `92aaabe2…459f`，單行啟用後為 `e3ea4d5eb85cce317c61091cdf737098acfeaee5bdb00ce2f6a5d697657a7343`。**這不是 200 人完整傷害／HP 時序 A/B、人工像素／畫面驗收或啟用後 FPS PASS**；進行中的新 full60 待其實際結果，不能預先更新達標結論。

本次新增 **5 批／20 檔**原 `result.json`／`stdout.log`／`stderr.log`／`combined.log` 到既有永久 `verification/`，逐檔 SHA-256 與大小一致，見 [封存清單](output/site_combat_performance_20260913/verification/archive_152126_152352_sha256.json)。未改原輸出或 production／test，未啟動 Godot；舊 FAIL 與 `151040_958` 的未達標結論保留。

### 15:25 啟用保守界後 full60：仍未達標，尾段 exact sharing 急降

`20260913_152520_132` 原 visual helper **PASS／exit 0／89.599 s／無逾時**，只代表正常完成量測；[原 measurements.json](output/site_army_combat_realtime/20e25c3e2a767961/mixed_equipment_full60/1789284323_2027375/measurements.json) 與 stdout 明列 **`measurement_complete=true`、`targets_met=false`**。原 `--m25-scalar-catalog`、200 原 row／混合實裝／正常 HUD，自動 Lab／Actor／Army；1400×900、D3D12 Forward+、RTX 5060、i5-14400F、VSync disabled、Engine max FPS 0／time scale 1，未用手動補幀。所有六個 checkpoints 的 constant／nonattack bounds flags 皆 true，窗口 fingerprints 不變；Source `e3ea4d5e…a7343`、bound helper `fd3c289b…1d5780`。

871 幀／60.086860 現實秒，**14.4956817513846 FPS、P95 408.115 ms、P99 458.631 ms、最長幀 579.733 ms**。完整六個十秒 FPS 依序 `16.3／12.8／22.8／11.5／21.0／2.6`，P95 依序 `397.805／428.234／351.325／426.853／353.523／545.843 ms`；60–60.086860 秒另有一幀，不冒充第七個完整段。input 31.237995 秒、action 31.237994999999 秒，input-wall `0.519880636132426`；最大 input−action 債只有 `1.04805e-12` 秒，是吃完**引擎實際傳入 delta**，不是追上現實時間。最長連戰 31.229662 秒，不覆蓋本輪 55 秒連戰設定。

144 真有效命中、24 原人物曾受傷，最終 20 dead／20 settled／20 容器、180 活人、KO 0、9 attacking；1,018 原物品與 cargo、原 200 身分、4,781→4,781 Nodes、HUD／BUSY／無非預期暫停／無 >1 秒單次停頓皆通過。memory `730,017,752→734,765,636 bytes`。這些是原玩法守恆及量測保護，不抵銷 FPS／P95／現實時間追隨失敗；本節沒有新增人工畫面驗收，也不以任何截圖當效能證據。

#### 六個 checkpoints 的約十秒增量

以下直接相減原 JSON 全部六個累積 checkpoints，邊界是**實際完成該幀**的時間，不是上面嚴格 0／10／20 秒 FPS bins。Source `query_profile`／`pose_clip_profile` 未另存量測起點副本，因此首列 `*` 是首次累積讀值，不能冒称已扣除所有 setup 的純增量；之後五列是完整差分。Lab shared steps 從原測試開始累計、Army geometry counters 在量測開始歸零。`sample poses` 是未被兩層結果重用返回的 sample 求值，`native poses` 是實際 seek 次數，亦包含護甲還原；不互換兩者。I／S／W／D 為 idle／walk_slash／walk／down 的 native pose clip 增量。

| 實際現實秒區間 | 共同步 | Source calls | step hits（占 calls） | terminal hits | sample／native poses | native clips I／S／W／D |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 起點→10.249757* | 742 | 36,130 | 34,456（95.37%） | 0 | 1,674／1,678 | 560／1,118／0／0 |
| 10.249757→20.043662 | 656 | 38,581 | 36,803（95.39%） | 0 | 1,778／1,780 | 593／1,187／0／0 |
| 20.043662→30.399200 | 932 | 30,012 | 28,634（95.41%） | 0 | 1,378／1,382 | 460／922／0／0 |
| 30.399200→40.170910 | 639 | 38,325 | 36,553（95.38%） | 0 | 1,772／1,774 | 591／1,183／0／0 |
| 40.170910→50.195001 | 907 | 14,703 | 13,613（92.59%） | 72 | 1,018／1,021 | 334／569／18／100 |
| 50.195001→60.086860 | 428 | 16,389 | 5,654（34.50%） | 4,888 | 5,847／5,854 | 1,769／3,960／125／0 |

下表為同一區間 CPU 增量（毫秒）；ordinary bounds 是兩原 Army 合計。各項互相包含，尤其 bounds／Source／collect／fatigue，不可相加。

| 區間約秒 | ordinary bounds calls | bounds ms | Source sample ms | seek／select ms | collect geometry／narrow ms | fatigue threat ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 起點→10* | 20,704 | 2,311.132 | 2,045.569 | 369.837／190.218 | 3,023.620／131.129 | 42.319 |
| 10→20 | 22,248 | 2,530.787 | 2,187.337 | 387.323／194.353 | 3,308.324／132.874 | 42.962 |
| 20→30 | 17,242 | 1,924.843 | 1,666.439 | 296.153／151.631 | 2,523.700／108.728 | 84.963 |
| 30→40 | 22,030 | 2,510.830 | 2,170.805 | 386.177／189.026 | 3,278.860／140.348 | 51.822 |
| 40→50 | 9,043 | 1,332.234 | 1,282.688 | 294.282／201.580 | 1,793.688／42.163 | 491.904 |
| 50→60 | 13,933 | 3,723.955 | 4,021.039 | 1,063.096／766.085 | 3,819.793／34.233 | 1,835.821 |

尾段只有 3.467214 動作秒／428 共同步，sample poses 卻由前段 1,018 增為 5,847（5.744 倍），每共同步 `1.122→13.661`；每動作秒 `158.926→1,686.369`。即使把 terminal hits 算入，結果重用比例仍由 `93.076%→64.324%`。原 Source key 仍是完整 clip／time／direction／aim／weight／appearance 精確值；資料直接證明**精確結果分享減少、原求值與投影工作增加**，但沒有逐次 key 差異分解，不能武斷只歸因某一時間／方向／配裝欄位，也不是授權量化 key 或降低命中精度。

兩原女性 live presenter 的 cache miss／sync／body／weapon／shield 全部增量為 0；普通兵 bounds 卻增加 13,933 次與 3,723.955 ms。死亡／settled 在約 50 秒已是 20，尾段無新增，最終 20 個容器；原自然補位完成步由 24→35，moving 2→1、攻擊者 10→9、有效命中 141→144，down clip 增量 0。這排除「新死亡／新 down 動作／女性 live 同步」是該段新增工作的直接來源；既有傷亡後普通兵變化與疲勞威脅成本仍在，不把所有成本稱為搜刮或 UI。

原逐幀 samples 對同一 `50.195001→60.086860` 區間回算：26 幀、9,891.859 ms，Lab CPU 8,886.410 ms（89.836%）。最後截圖／fingerprints 在量測終止後；原 checkpoint 序列化真成本仍包含於下一幀，未偷偷排除，但不能解釋這些已量到的 Lab／Source 求值增量。整段 full-clock CPU 48,726.008 ms、contact CPU 28,212.854 ms；Source sample 累積 13,373.877 ms、collect geometry 17,747.985 ms、narrow 589.475 ms。此結果沒有達到流暢；相較上一場的傷害及補位歷程也不同，不把跨場平均微差當精確 A/B 收益。

原四檔已永久複製且兩次逐檔 SHA-256／大小與 canonical 一致，見 [152520 封存清單](output/site_combat_performance_20260913/verification/archive_152520_sha256.json)。分析所讀原 JSON SHA256 `84ba9a53d763a8dc552723fe999e18b6a95eb090577c0a607a5b067839d39179`；原檔、`TARGETS_NOT_MET`、所有舊 FAIL 完整保留。本次只補文件／封存，未改 production／tests、未啟動 Godot。

### 15:37–15:38 同 batch anchor_radius 重用：完整接觸／生命週期回歸

原 Lab 的同一 post-advance contact batch，將 `anchor_radius` 放入既有 target slot；同一原 row 被多條 sweep 查詢只解析一次半徑。遠端 slot 可先只有半徑，真正需要時才在**同一 Dictionary** 補原 bounds／body／shield／parry，沒有另建人物／碰撞表、跨步快取或重用上次「未命中」結論。各次 sweep 的有限世界域守衛仍獨立判斷，index 0 保持原無條件路徑，batch 外仍現查不保留 slot。

| Canonical run | 結果／helper 秒 | 實際證據 |
| --- | --- | --- |
| `153710_683` | headless check-only PASS／1.705 | 只解析更新後整合測試，不作執行或 FPS 證據。 |
| `153732_547` | GPU group 0 PASS／13.025 | [46 個 exact comparison records](output/site_combat_performance_20260913/nonattack_bounds_integration/group0/1789285054_1948000/measurements.json)：原四向 40 組，加 idle／下一 guard 的 4 組完整接觸及 2 組 radius-cache 生命週期序列。原 4 row／22 軍隊物品／同 Source。 |
| `153807_942` | GPU group 1 PASS／25.180 | [11 組完整 ordered contacts exact](output/site_combat_performance_20260913/nonattack_bounds_integration/group1/1789285090_1978352/measurements.json)：原男性 index 0、名冊實轉後女性 index 1、原玩家／NPC 與超界回退。原 5 row／29 軍隊物品／同 Source。 |

兩個新生命週期序列都驗到 `far→far→positive→positive` 的原完整接觸順序／內容不變、四次 query 只有 **1 次 radius 呼叫**；idle 的遠端先只有 `anchor_radius`，正接觸才升級同一 slot，guard 仍取原 exact bounds。`far→outside→outside` 保留半徑但每次域外查詢仍回原 exact bounds，沒有把前次排除錯用到新 sweep；batch 外兩次查詢正好 **2 次 radius 呼叫**且不留快取。下一個原 guard batch 重建為 256，不沿用 idle 的 128。這些生命週期 records 各內含多個原完整接觸對照，不把 46+11 誤稱 57 個獨立傷害戰鬥。

三批都 exit 0／無逾時／無 script 或 assertion 錯誤；這是原 contacts、HP／blocked／state 不變與 cache 守衛回歸，**不是 200 人完整傷害時序 A/B、人工畫面／像素驗收或新 FPS PASS**。本輪 Lab SHA256 `4b7c5a9cde55b7e208ef950ab5e5ad1799206458432e957d55bfe31593e3270d`；Source 仍 `e3ea4d5e…a7343`、helper 仍 `fd3c289b…1d5780`。下一個 `153920_375` full60 在本節交付時仍進行中，待實際完成報告後另記，不能用這三批先判達標。

三批原四檔共 **12 檔**已永久封存，逐檔兩輪 SHA-256／大小與 canonical 一致，見 [153710–153807 封存清單](output/site_combat_performance_20260913/verification/archive_153710_153807_sha256.json)。未覆寫不同檔、未刪原 run／舊 FAIL，沒有修改 production／tests 或啟動 Godot；最新已核對整場結果仍為上節 `152520_132` 的 `targets_met=false`。

### 15:39 同批半徑重用後 full60：仍未達標

`153920_375` visual helper **PASS／exit 0／90.272 s／無逾時**，只表示量測正常結束；[原 JSON](output/site_army_combat_realtime/4557770a4cc5dd46/mixed_equipment_full60/1789285163_1911274/measurements.json) 與 stdout 仍明列 `targets_met=false`。同原 1400×900、VSync disabled、自動 Lab／Actor／Army、兩隊 200 原 row／混合裝備、正常 HUD；870 幀／60.402796 秒，**14.4033067608327 FPS、P95 368.153 ms、P99 477.357 ms、最大間隔 539.125 ms**。六個完整十秒 FPS 是 `15.9／18.8／16.9／22.1／10.5／2.7`；其後 0.402796 秒的一幀不列完整段。

input 32.982658 秒、action 32.982657999999 秒；input-wall `0.546045219496132`，原傳入 delta 與 action 債僅 `1.12976e-12` 秒，仍非跟上現實。最長連戰 32.974325 秒，55 秒覆蓋 false。145 真有效命中、24 原人物曾受傷，20 dead／20 settled／20 地面容器、180 活人、KO 0、19 attacking；1,018 items／cargo 守恆、原 200 身分、4,781→4,781 Nodes、HUD／BUSY／來源穩定、無非預期暫停及無 >1 秒停頓皆通過。memory `730,037,196→734,924,292 bytes`；主控已看原最終圖，沒有以圖或 exit 0 宣稱 FPS PASS。

當次 Lab hash `4b7c5a9c…e3270d` 包含同 batch 半徑重用；Source `e3ea4d5e…a7343`、helper `fd3c289b…1d5780` 仍是當時**只准非攻擊**的範圍。後續八攻擊准入／Cape／fatigue-frontier 不包含在本測量。full-clock CPU 48,667.734 ms、contact CPU 26,021.996 ms；Source 179,920 calls、15,946 sample poses／15,975 native poses、sample 15,070.163 ms、seek 3,285.186 ms；collect geometry 19,151.753 ms、narrow 582.906 ms、fatigue threat 3,522.972 ms。分項巢狀不可相加；跨場傷害／補位歷程不同，平均小幅變化不是嚴格單變因 A/B 收益。

原四檔已永久歸檔、兩輪 SHA-256／大小相同，見 [153920 封存清單](output/site_combat_performance_20260913/verification/archive_153920_sha256.json)；原 JSON SHA256 `e2bb37648e643f0bd689555914144fa85c333d62854798aadb974727f4c13e28`。舊 FAIL、`TARGETS_NOT_MET` 与原資料不改。

### 15:52–15:54 局部守衛／frontier 與 Cape metadata，未新增 FPS PASS

| Canonical run | 結果／helper 秒 | 已完成的實際範圍 |
| --- | --- | --- |
| `155237_550` | headless PASS／2.722 | 原 TerrainData can-step 的相同守衛只檢一次；60,384 結果 exact。300,000 個 open-edge calls 局部原／重用 `1,130,902→698,986 μs`，不是 FPS。 |
| `155424_415` | headless check-only PASS／1.118 | 只解析 Cape query 測試，不是 geometry／actor 實測。 |
| `155426_701` | headless PASS／6.858 | 67 原 oracle checks（positive fast 14／原 BFS fallback 28）＋4 個依查詢順序恢復同一原 forward queue 的序列；原 Actor／100 Army rows、committed destination／地形換批及原 headless projectile fallback。 |
| `155448_952` | GPU Cape group 0 PASS／20.507 | [metadata／9 guards JSON](output/site_combat_performance_20260913/cape_query/group0_1789286109_20015927/measurements.json)：59 clips、44,221 tracks、2,720,390 keys 全部保留，只將 30,528 個 Cape-only tracks 的 enabled true→false。**exact_pairs=0、actor_checks=0、passes=[]**，不是碰撞／Actor／畫面 A/B 已通過。 |

fatigue frontier 的單 seed 先查近處只用 15 次原 can_step，相對 eager 139；同一批查完遠處／負結果後共 139，相等而非丟掉未完成工作。原 100 rows 加一個 committed destination 共 101 seeds：首次 96／eager 442，整批負查詢後同為 442。反轉查詢順序時第一次即用 139／442，保留原 complete-node forward queue 與順序效果；不把所有情境稱為固定倍數提升，也不換掉原可達性判斷。

Cape 是既有私有、**不顯示**的 Source 候選，只停播其原 Cape-only tracks，所有 tracks／keys／非 Cape 碰撞與護甲 owner 保留；不是已退回的「props／披風全延後」候選。當次 Source hash `e3b3d5b2…aa86c7`，default **`cape_track_omission_enabled=false`**。GPU group 1 尚未納入本節驗證，metadata 中的 0 error 沒有 query pairs，不能當完整碰撞或渲染等價證據。

八種原生無瞄準攻擊範圍擴展在本節 15:54 截點已完成限定程式／測試並凍結，**當時定向測試待跑，不列 PASS**。它只把原已納入 32 曲線數學 envelope 的八種攻擊加入 clips；原 31.5 offset／浮點 padding／128 推導不改。DOWN＋兩值 saved aim 即使 weight 0 仍回 256；全 guard／transition、女性、index 0、未知 clip 與既有數值守衛保留。詳見 [PROOF 的擴展界線及後續結果](output/site_combat_performance_20260913/native_bounds/PROOF.md#unaimed-native-attack-extension)。不能拿先前 46＋11 records 當作擴展後的新測試結果。

本批 **4 runs／16 原檔**已永久封存且兩次 SHA-256／大小核對相同，見 [155237–155448 清單](output/site_combat_performance_20260913/verification/archive_155237_155448_sha256.json)。兩個 headless 執行的已知 certificate-store noise 保留；沒有 script／assertion 錯誤或逾時。本次文件／歸檔不修改 production／tests、不啟動 Godot，最新 full60 仍未達流暢目標。

### 15:55–16:00 Cape 與無瞄準攻擊範圍回歸通過；anchorX 不採用

| Canonical run | 結果／helper 秒 | 新增實際證據 |
| --- | --- | --- |
| `155546_971` | GPU Cape group 1 PASS／25.594 | [12 組 query／non-Cape snapshots exact，8 次原 Actor 對照](output/site_combat_performance_20260913/cape_query/group1_1789286172_25136859/measurements.json)；query 最大誤差 0，Actor 既有 <0.01 投影界線實際最大 `0.0000189298953046091`。 |
| `155706_984` | GPU native bounds group 0 PASS／8.262 | [75 cases／13,525 原頂點](output/site_combat_performance_20260913/native_bounds/runtime_group0/1789286234_1442041/measurements.json)，20 clips（12 nonattack＋8 native attack）、四方向、原 fallback，推導仍為 `114.305518688431→128`。 |
| `155735_692` | GPU collector group 0 PASS／13.136 | [67 exact records](output/site_combat_performance_20260913/nonattack_bounds_integration/group0/1789286257_1955840/measurements.json)：64 完整 contacts 對照、2 個 radius cache 生命週期、1 個 unknown-clip **radius-only** 診斷；4 原 rows／22 原 army items。 |
| `155855_036` | GPU collector group 1 PASS／26.934 | [11 完整有序 contacts 對照](output/site_combat_performance_20260913/nonattack_bounds_integration/group1/1789286337_2103865/measurements.json)，5 原 rows／29 army items、2 原 female presenters、原 player／NPC 與域外 fallback。 |
| `155842_280` | headless anchorX TEST ONLY PASS／7.141 | [4,000 queries／128 numeric edges exact](output/site_combat_performance_20260913/anchor_x_candidates/1789286329_1305428/measurements.json)，200 原 rows／實際 committed movement；正面交戰候選反而更慢，未進 production。 |
| `160019_195` | 原 fatigue headless PASS／7.980 | 144 timing combinations；原工作分割、rest／threat／clock／pause、Actor state／save／legacy／action snapshots 回歸，不是 GPU／FPS。 |

Cape 僅作用於不顯示的原私有 query Source，所有原 tracks／keys、raw model 保留；每路仍觀察到 **1,272 個非零 hidden Cape shape 值**。A/B 比較的 collider、非 Cape morph、bones、worn armor／protection 完全相同，並未聲稱 Cape scalar 或渲染畫面相同；8 次原 Actor 對照也不是 exact-zero。局部 seek `43,073→25,120 μs`、兩路 elapsed `4,355,398→4,166,640 μs` 包含測試操作，不是 FPS。主控在此驗收後才將 `cape_track_omission_enabled=true`；驗收時 Source `e3b3d5b2…aa86c7`、啟用後／bounds 整合時 `5eea3f09…43e78`，raw SHA256 `219f82c0…b8caa2` 保持原樣。不是曾撤回的三項 cosmetic 批次，也未新增人工畫面驗收宣稱。

新的 native attack 整合已真測 DOWN 兩值 saved aim 的 windup（weight 0）／active（weight 1）均保留 256；未知有限 aim target 仍保留 256。UP／RIGHT／LEFT 同樣保留 saved aim 但原 native weight 0，及 DOWN 清空 aim 後，才准 128；全 guard raise／lower／break 和未知 clip 保留 fallback。原女性與 index 0 仍原路徑，域外輸入不靠 tighter gate 排除。所有完整 contacts 的順序／身分／fraction／point／shield 及原狀態 exact；這不是 200 人傷害時序 A/B、像素或 FPS 驗收。本次重跑 native **group 0**，先前 group 1 的歷史數據保留，不冒稱又重跑該組。

anchorX 的 stationary frontline 原兩次 `7.454／7.519 ms`，候選 `8.739／8.655 ms`；原 quarter-step frontline 也由 `7.238／7.232` 變成 `8.469／8.451 ms`。每次含每 10 queries 重建、各案 500 queries；只有 distant 案兩路都較快（stationary 原 `5.666／5.869`、候選 `2.587／2.622 ms`）。因此主控拒絕導入，而不是把 exact correctness PASS 改成失敗，亦不把遠處收益當真實交戰加速。

以上 **6 runs／24 原檔**已永久封存、兩輪 SHA-256／大小與 canonical 相同，見 [155546–160019 清單](output/site_combat_performance_20260913/verification/archive_155546_160019_sha256.json)。兩個 headless 執行只有已知 certificate-store noise；沒有 script／assertion 錯誤或逾時。新 full60 尚在執行，最新已核對整場仍是 `153920_375` 的 `targets_met=false`；本次只更新文件／證據，不修改 production／tests 或啟動 Godot。

### 16:00 Cape／無瞄準攻擊範圍／frontier 啟用後 full60：仍未達流暢

`20260913_160052_088` visual helper **PASS／exit 0／90.889 s／無逾時或 script／assertion 錯誤**，只代表量測完整結束；stdout 明確是 `SITE_ARMY_COMBAT_REALTIME_TARGETS_NOT_MET`，[原 JSON](output/site_army_combat_realtime/7b9604e5eeb79b88/mixed_equipment_full60/1789286455_1967284/measurements.json) 保留 `targets_met=false`。同原 1400×900、Forward+／D3D12、RTX 5060、VSync disabled、原自動 Lab／Actor／Army 與正常 HUD，未用手動快轉或減人換取幀率。

927 幀／60.175594 現實秒，**15.4049164849125 FPS、P95 332.980 ms、P99 365.763 ms、最大間隔 453.972 ms**。六個完整十秒段如下；60 秒後多出的 0.175594 秒／一幀不混作第七個完整段。

| 現實秒 | 呈現幀 | FPS | P95 ms |
| --- | ---: | ---: | ---: |
| 0–10 | 166 | 16.6 | 343.526 |
| 10–20 | 232 | 23.2 | 318.591 |
| 20–30 | 131 | 13.1 | 346.161 |
| 30–40 | 236 | 23.6 | 308.242 |
| 40–50 | 122 | 12.2 | 306.815 |
| 50–60 | 39 | 3.9 | 373.839 |

input `36.0248626666667` 秒，action `36.0248626666654` 秒，input-wall `0.598662352492385`；傳入 delta 對 action 最大差僅 `1.25055521493778e-12` 秒，但 **input 本身未追上現實時間**，不能用 no-simulation-debt=true 說已即時。最長連戰 36.016529 秒、55 秒覆蓋 false；FPS／P95／每段 ≥30 FPS 也都 false，並非只差連战覆蓋。

148 真有效命中、25 原人物曾受傷、20 原 dead／20 settled／20 地面容器、180 活人、KO 0、16 attacking；原 200 身分與 1,018 items／cargo 守恆、4,781→4,781 Nodes、HUD／BUSY／來源穩定、無非預期暫停、無 >1 秒停頓皆通過。memory `729,837,624→734,547,632 bytes`，最終圖輸出 error 0。後續主控已檢視此輪 `02_final.png`，確認原 200 兵情境的 HUD／倒下人物畫面存在；這只是一張靜態代表圖，不證明動作連續性或流暢，也不取代 FPS。

本次來源含 Source `5eea3f09…43e78`（Cape／constant 皆 true）、Army `9f077383…b6e7d5`、helper `6a27fbe3…10744b`（20 原 native clips、連續推導 `114.305518688431→128`）、Lab `48aa035a…7f0c34` 與 TerrainData `00eb9d3b…3f7999`。這些與 15:39 來源不同；兩次原生 input delta／進展及傷害補位歷史亦不同，平均 FPS `14.403307→15.404916`、P95 `368.153→332.980 ms` 只能列觀測變化，**不能歸因某一優化、更不能稱已流暢**。

full-clock CPU 47,353.123 ms、contact CPU 26,058.698 ms；Source 189,568 sample calls／21,481 sample pose evaluations／21,517 native pose evaluations，sample 14,615.045 ms、seek 1,062.619 ms、select clip 2,529.830 ms。collect geometry 18,568.799 ms、narrow 600.782 ms、fatigue threat 1,406.440 ms；以上巢狀計時不能相加。最後兩個 checkpoint 實際位於 50.046901 與 60.175594 秒，增量是 645 shared steps／19,302 samples／8,965 pose evaluations／4,057.842 ms collect geometry；它不是精確 50–60 bin 計量，但再次顯示尾段 pose 成本仍高，不武斷歸到單一原因。

原四檔已永久封存、兩輪 SHA-256／大小相同，見 [160052 封存清單](output/site_combat_performance_20260913/verification/archive_160052_sha256.json)。原 measurements SHA256 `e95907411996b80fd8e26f4d4a99f0946e23d2133f5c87eb9f7ab525c9f4a731`。這次只更新 docs／archive，舊數據與 `targets_met=false` 不改，沒有 production／test 變更或另啟 Godot。

### 16:11 導航回歸；fixed120 仍只是待驗候選

`20260913_161142_821` 原 `site_army_navigation_test.gd` **headless PASS／exit 0／2.054 s／424 steps**：100 unique occupants、移動中命令 drain、新 blocker replan、passage construction guard。這是 TerrainData can_step 守衛重用後的原導航回歸，不是 GPU、FPS 或新的碰撞／fixed120 驗收。只有已知 certificate-store noise，無 script／assertion 錯誤或逾時；原四檔已永久保存、兩輪 SHA-256／大小一致，見 [161142 封存清單](output/site_combat_performance_20260913/verification/archive_161142_sha256.json)。

主控正製作另一個 **fixed120 待驗候選，未列啟用／成功**：保留原每人 120 Hz 子步，把不足一步的餘時帶到下一個 render frame，不再每幀追加 partial step。正常最大 phase 差為一個 8.333… ms 步；約 `1e-12` 的 signed rounding carry 必須保留而不能 clamp。這是候選的預定契約，尚不是驗證結果；不降更新頻率、不丟 elapsed，也不把既有導航 PASS 挪用到它。最新完整性能结果仍是 `160052_088` 的 `targets_met=false`。

### 16:17–16:18 fixed120 候選 full60：時間餘量保留，性能未達

`20260913_161733_281` check-only **headless PASS／exit 0／1.596 s**，只驗 realtime script 解析。接著 `20260913_161837_569` 以 `--m25-scalar-catalog --fixed120` 真正自動 GPU 量測，canonical **PASS／exit 0／91.611 s／無逾時或 script／assertion 錯誤**；[原 measurements](output/site_army_combat_realtime/7b55cbe0688fb1aa/mixed_equipment_full60_fixed120/1789287522_3545298/measurements.json) 與 stdout 均是 **`targets_met=false`**。這是候選明確開關的測量，`TerrainLab.fixed_action_steps_enabled` 仍 default false，不能說已正式啟用或已驗收完成。

同原 1400×900／VSync disabled、原 200 rows／混合裝備／正常 HUD／原生自動 frame，1,024 幀／60.236422 秒：**16.9996816876009 FPS、P95 330.414 ms、P99 367.713 ms、最大間隔 456.000 ms**。六完整十秒 FPS 為 `18.6／26.7／14.9／28.2／10.4／3.5`，P95 分別 `331.258／319.293／333.450／276.723／349.198／376.162 ms`；60 秒後多 0.236422 秒／一幀。整體／每段 30 FPS、P95 與 input 跟上現實的旗標仍 false，不以平均較高掩蓋尾段。

原 input `35.4960200000000` 秒、4,259 原 fixed 子步／action `35.4916666666653` 秒，input-wall `0.589278360524137`。原每人仍在 120 Hz 子步處理，不降頻；不足一步餘量跨 render frame 留存。最終 input−action `0.00435333333473409` 秒，其中 retained fraction `0.00435333333333823` 秒；扣除後 unaccounted 僅 `1.39585912273255e-12` 秒。整場最大絕對 input−action `0.00832566666700885` 秒，小於一步 `1/120=0.00833333333333333` 秒；此模式報告的允許值含原數值容差為 `0.00834333333333333` 秒，明列而不把它當零相位差。`no_simulation_time_debt=true` 的這個餘時定義，不抵銷 input 本身只跟上約 58.9% 現實的問題；最長連戰 35.483333 秒，55 秒覆蓋 false。

150 真有效命中、25 原人物受傷、20 dead／20 settled／20 地面容器、180 活人、KO 0；原 200 身分／1,018 items 與 cargo 守恆、4,781→4,781 Nodes、HUD／BUSY／來源穩定皆通過。memory `730,027,757→734,926,269 bytes`。主控後續已檢視此輪 `02_final.png`，只屬靜態代表圖，不是 motion proof。full-clock CPU 46,465.937 ms、contact 26,239.591 ms；collect geometry 18,799.182 ms、narrow 609.979 ms、fatigue threat 1,261.797 ms。Source 187,967 sample calls／22,149 sample poses／22,184 native poses，sample 15,293.575 ms、seek 1,238.241 ms；各項巢狀不可相加。

本次 Lab SHA256 `44ec754fba1aec857a73d594cc36e9b87759bcb6f91bb6f76f29bc417f9a99b6`，realtime test `1e375ea4bbac98313b066f7b8c586b0d854d4e935d89023a8da0b19f60878c79`。與預設路徑 `160052_088` 相比，原生 delta 序列、子步切分、完成 action 秒與命中事件均不同；`15.404916→16.999682 FPS` 不是同輸入的封包／傷害時序等價證據，也不是性能達標。此報告保存了每幀 input／action／draw 等時間陣列與 resolved 數量，不冒稱已附完整逐封包 timeline。存檔保存的是已結算 Site／人物時間快照，與這些報告陣列或動作影片不同；其餘時／讀回規則由下節原 clock 測試另驗。

兩 runs 的 **8 原檔**已永久保存、兩輪 SHA-256／大小相同，見 [161733–161837 封存清單](output/site_combat_performance_20260913/verification/archive_161733_161837_sha256.json)。原 measurements SHA256 `307f82f7c714a3510c839de1cc0060927d916b614c374bbe1b53d2f6bc27182c`，舊檔／旗標原樣保留；本次僅 docs／archive，沒有 production／tests 修改或另啟 Godot。

### 16:22–16:31 clock 回歸與 rigid hull 去重；保留負零 fixture FAIL

| Canonical run | 結果／helper 秒 | 已驗範圍 |
| --- | --- | --- |
| `162243_096` | headless PASS／10.615 | 原 fixed clock 的 12 種 exact render partitions；原 Site／body／fatigue／items、首命中時鐘 barrier、signed 時間守恆、平時／步中暫停、snapshot timeline reset、legacy partial fallback。**不是 200 人 geometry／FPS**。 |
| `162430_345` | headless check-only PASS／1.233 | rigid hull test 解析，不是執行驗收。 |
| `162512_142` | GPU group 0 **FAIL／1.792／exit 1** | `_synthetic_dedup` 原 line 72 負零 fixture assertion。字面負零被 fold，後續改以原 IEEE bytes 建立並先驗 `00000080`；保留失敗，不放寬 signed-zero 比較。 |
| `162622_997` | GPU group 0 PASS／1.835 | [11 guards／8 exact pairs](output/site_combat_performance_20260913/rigid_hull_dedup/group0_1789287984_1525053/measurements.json)，最大誤差 0；包含真負零、degenerate／非剛性／morph／skin 更換等原 fallback。此組未量真模型節省。 |
| `162640_178` | GPU male PASS／15.160 | [10 exact pairs、31 次更短投影](output/site_combat_performance_20260913/rigid_hull_dedup/group1_1789288015_1919569/measurements.json)，省去 3,564 次重複 local vertex 投影；原／候選局部 `3.634765→3.254889 s`。 |
| `162711_655` | GPU female PASS／14.784 | [10 exact pairs、31 次更短投影](output/site_combat_performance_20260913/rigid_hull_dedup/group2_1789288046_1692897/measurements.json)，省去 3,114 次重複 local vertex 投影；原／候選局部 `3.744902→3.146473 s`。 |
| `163121_303` | headless check-only PASS／1.564 | 更新後 realtime test 解析；不代表已執行另一輪整場量測。 |

原 clock 回歸明確驗證：普通暫停不接收新 elapsed 且保留舊餘量；若在已結算的小步內暫停，可暫存多於一步的**先前已接收時間**，恢復時續處理而不是丟棄。清隊／換控制者不重設 Site timeline；保存不清 live 餘時，原存檔保存已結算 Site／人物時間，顯式 load／bind 才重設原 live phase，避免把舊執行的餘時注入新快照。這是候選時鐘的局部驗證，`fixed_action_steps_enabled` 仍 false。

rigid 去重只在既有已驗證單骨 weight-one、無 morph 的武器／盾 hull 路徑重用原 exact local vertices；每案比較 ordered closed hull 的完整數值位元，最大誤差 0。保留 armor 三角形索引、head／IK 頂點順序及原非剛性／morph 路徑，不刪正式 mesh／surface／原始資料。去重記錄的 removed vertices 是該 fixture 中省去的重複投影，不是永久刪掉模型頂點。男女 raw SHA256 各為 `219f82c0…b8caa2`／`47eaea94…aa1d12`，A/B Geometry SHA256 `2cea9ba3ec15b1a29b49f61de258329af1e4b67b8457149e8caca24e622b84f4`；驗收後主控才將 `rigid_hull_dedup_enabled=true`，啟用版 SHA256 `0b68dea07e9f3037d76efe643762b3e21323c4d90596ba74b00b1442ac31c6a2`。這些局部秒數不是 FPS，不能回填到較早 Source 或 `161837_569` 的整場歷史。

七 runs 的 **28 原檔**已永久封存、兩輪 SHA-256／大小核對一致，見 [162243–163121 清單](output/site_combat_performance_20260913/verification/archive_162243_163121_sha256.json)。只有 clock headless 的已知 certificate-store noise；舊 FAIL 原樣保存，其餘列出的 PASS 無 script／assertion 錯誤或逾時。bounds-only 只完成唯讀設計查核，收益未明且跨四個 owner，主控決定暫不實作；不新增候選幾何或另一套模型。這次只更新 docs／archive，無 production／test 修改或 Godot 啟動。

### 16:33–16:46 strict 順序／已命中排除候選：窄相交減少，性能仍未達

`20260913_163308_258` 原 native sorter／owner hit-set routing **headless PASS／exit 0／1.690 s**，[144 strict survivor checks](output/site_combat_performance_20260913/strict_contact_order/1789288389_1372922/native.json)。原 approximate comparator 在反例的 native order 為 `[5,3,4]`，新 strict 為 `[5,4,3]`，所以這是明確的比較規則候選，**不是宣稱舊排序與新排序處處相同**；驗證 strict 前提下的保留對象順序。NaN contact 不丟棄，逐欄排於數字之後再依原 identity，不稱 NaN 具數值大小順序。這份 native／routing 檢查不是 mesh、200 人 gameplay 或 FPS 驗收；只有已知 certificate-store noise。

`20260913_163440_200` 用 `--m25-scalar-catalog --strict-cull` 自動原 200 人 GPU full60，helper **PASS／exit 0／91.156 s／無逾時或 script／assertion 錯誤**；[原 measurements](output/site_army_combat_realtime/c4aa799a0e24d631/mixed_equipment_full60_strict_cull/1789288483_1900139/measurements.json) 和 stdout 保留 **`targets_met=false`**。量測中 `strict_contact_order_and_melee_hit_cull=true`、rigid dedup true、fixed120 false；交付時 `strict_contact_order_enabled`／`melee_hit_cull_enabled` 皆仍 default false，不能把測試開關當正式啟用。

904 幀／60.007699 現實秒，**15.0647336102656 FPS、P95 322.197 ms、P99 376.626 ms、最大 481.075 ms**。六個完整十秒 FPS `16.2／23.0／13.3／24.9／9.2／3.7`，P95 `328.622／308.071／326.027／297.507／364.032／364.177 ms`；60 秒後多出 0.007699 秒的一幀不算完整段。input `35.999195` 秒、action `35.9991949999988` 秒、4,917 原子步，input-wall `0.599909604932527`；最大 delta/action 差約 `1.187e-12` 秒，但仍只有約六成現實時間的進展。最長連戰 35.990862 秒；幀率／P95／逐段 ≥30 FPS／時間追隨／55 秒覆蓋皆 false。

149 真有效命中、25 原人物受傷、20 原 dead／20 settled／20 containers、180 活人、KO 0、18 attacking；原 200 身分、1,018 items／cargo、4,781→4,781 Nodes、HUD／BUSY／來源穩定、無非預期暫停及無 >1 秒停頓皆通過。memory `730,508,014→735,289,218 bytes`。主控後續已檢視此轮 `02_final.png` 的原 200-row 情境、HUD 與死亡人物靜態畫面，不能由此推論動作流暢。

full-clock CPU 47,198.588 ms、contact 25,183.114 ms；collect geometry **17,755.831 ms**、narrow **55.668 ms**。Source sample 170,453 calls／21,020 sample poses／20,998 native pose evaluations，sample 14,914.761 ms、seek 1,067.689 ms；measurement pose 6,232.308 ms、body 1,844.101 ms、shield 2,942.493 ms。這些數值巢狀不可相加；相對較早原 full60 的 narrow 600.782 ms，工作量雖大幅降低，Source 原姿態／幾何仍重，且本輪 FPS 不達標。不同來源／原生 delta／命中歷程並非嚴格單變因 A/B，不推導全場加速或舊／新封包歷史等價。

本輪 Lab SHA256 `1a71b398e22484313927611b6d749084d13f5476618362c2609e9db3857a415a`、Geometry `0b68dea07e9f3037d76efe643762b3e21323c4d90596ba74b00b1442ac31c6a2`、realtime test `3a92869d24f6cf8bf7f48811eb15c91b3700951ab3e0be5516d44754e258bb11`；measurements SHA256 `c6b821eeb7ff5145575beee269cc3ceedb4d77fabc8c587b402e455dc0516455`。兩 runs 共 **8 原檔**已永久保存、兩輪 SHA-256／大小相同，見 [163308–163440 清單](output/site_combat_performance_20260913/verification/archive_163308_163440_sha256.json)。

另保留 `20260913_164605_403` **headless check-only FAIL／exit 1／0.688 s**：`site_contact_hit_cull_test.gd:261` 的 `initial_items` 無法推導型別，腳本未成功載入，不算任何 gameplay 對照完成。定向修正的後續執行結果尚未納入本節。此 FAIL 的四原檔同樣永久保存及双輪 SHA／大小核對，見 [164605 清單](output/site_combat_performance_20260913/verification/archive_164605_sha256.json)。本次僅 docs／archive，不改 production／tests 或另啟 Godot。

### 16:46–16:48 暖機隔離計時：dedup 改回關閉，精確性證據保留

兩體型重新沿同一原 Actor／十個姿態做 false→true→true→false，每階段八組 weapon_shapes＋shield_shapes；每體 640 calls，計時外完成暖機，不把 armor、pose reset、loading、cache warm 或 reduction 計数混進隔離區間。

| Canonical run | 結果／helper 秒 | 暖機後隔離原／候選總 μs |
| --- | --- | ---: |
| `164631_886` male | GPU PASS／14.835；10 exact pairs | `88,388→88,763`（候選 +0.424%） |
| `164835_819` female | GPU PASS／14.271；10 exact pairs | `83,442→82,284`（候選 −1.388%） |
| 合計 | 不當作統計顯著收益 | `171,830→171,047`（−0.456%） |

這個微小合計差低於同一 flag 各階段的波動，男體甚至稍慢；**不足以啟用**。早前整份 snapshot 的 `3.634765→3.254889 s` 等數字保留為當時測試耗時，不能繼續引用成 dedup 隔離收益或整場加速。原 ordered hull bits／armor／head／IK 完整性通過仍有效，但「正確」不等於「值得常開」。主控已只將 `rigid_hull_dedup_enabled` 的預設改回 false 並註明沒有明確暖機收益，不再投入這個候選的 guard 微優化；fixed120／strict／cull 亦仍 false。

同批 `20260913_164703_744` strict GPU **FAIL**：`site_contact_hit_cull_test.gd:276` 的 parry fixture assertion，後續 helper **55.154 s timed_out=true／exit_code=null**。不能以逾時掩蓋已發生斷言失敗，也不代表整合已通過；夾具仍由主控分工定向查核，不重標成遊戲故障或 PASS。

上述三 runs 的 **12 原檔**已永久封存、兩輪 SHA-256／大小一致，見 [164631–164835 清單](output/site_combat_performance_20260913/verification/archive_164631_164835_sha256.json)。沒有新的 FPS 量測，最後與全部候選關閉配置相符的完整測量仍是 `160052_088`（15.404916 FPS／P95 332.980 ms／input-wall 0.598662／`targets_met=false`）；`163440_200` 的 strict-cull 結果單獨保留，不能冒充目前預設 FPS。60 Hz 方案尚待回覆、尚未實作；本次只更新文件，不改 production／tests 或執行 Godot。

### 16:53 strict 自身 cull 整合通過；不回改舊 FAIL

`20260913_165356_375` **GPU PASS／exit 0／18.156 s／stderr 空／無逾時**：12 actual-owner contact comparisons、12 次略過原 geometry、8 packet＋HP comparisons、22 原 items 守恆，最大誤差 0。沿原 raw female／ordinary／Actor 投影與原 once-per-swing／projectile handlers，使用 diagnostic polygon sweeps；不是 authored trajectory／FPS 或舊 approximate-sort 等價。前面的 headless 144 與這次 GPU 12／8 都只驗 **strict uncull versus strict cull**，不能跨成舊排序規則完全相同。

本次 Geometry SHA256 `b5ef2dbd56c18fdb88c367765b9d33b6262a571f59aed926548ce9231dee5e0a`、dedup false；早先 `164703_744` parry assertion FAIL 時 dedup true。除 fixture 的 fail-return／徒手修正外，production 預設也變了；這不是單變因對照，**不能據此認定舊 parry 失敗由 dedup 引起**。本次沒有印 PARRY diagnostics 且後续斷言通過，parry 非空檢查通過；舊 FAIL／55.154 秒逾時原樣保留。四原檔已永久保存、兩輪 SHA-256／大小相同，見 [165356 清單](output/site_combat_performance_20260913/verification/archive_165356_sha256.json)。所有候選仍 off，無新 FPS 結果；本次只更新文件與歸檔，之後凍結，未修改 production／tests 或啟動 Godot。

### 已撤回的降頻選項；繼續保留原 120 Hz 最大子步

先前提出的 60 Hz 候選沒有實作，且不再當作繼續優化的前提。使用者以 Total War 提出質疑後要求繼續優化；本輪保留原共同 120 Hz 最大子步、原人員／物品／傷害／移動／動畫與精細判定。僅改善既有 owner 的查詢成本，不把降低判定頻率、減人或時間落後當作流暢。新的保守 incoming 查詢與零疲勞窄分支先保持 opt-in，待原路徑等價及完整即時量測；定向測試通過也不等於 FPS 達標。

## 已通過的局部精確驗收（不是 FPS PASS）

| 切片 | 已取得證據與界線 |
| --- | --- |
| 原 seek+advance 對 seek-only | `exact_seek/group_0.json`–`group_6.json` 共 69 組 exact pairs；保留原 HumanEditor 參考、完整骨架／幾何。GPU `101704_148`（group 6）、`101801_685`、`101813_689`、`101825_409`、`101834_943`、`101843_940`、`101857_638` 全 PASS。當時 source SHA256 `22210fd6…2a9385`，不代表後續 source 變更已驗。 |
| 原蒙皮矩陣共用（skin palette） | synthetic／male／female 共 1,916 次比較、1,207,392 頂點，最大誤差 0、failures 空；native rigid 與原 scalar 分別對照封存函式，保留原 morph／多 surface／姿態變化。GPU `104217_031`、`104218_948`、`104225_882` PASS；`skin_palette/*.json` 有完整明細。 |
| 同次攻擊 prepared contact | `prepared_contacts.json` 526 例，完整原 Dictionary 接觸／人物／招架相等，涵蓋 256 seeded 多部件例及 255 個二分 hull key；headless `103326_245` PASS。只在同次攻擊內暫存，不是跨時間命中快取。 |
| 疲勞威脅查詢快路徑 | headless `104250_618` PASS：60 checks、14 positive fast、28 原 BFS fallback，真 TerrainData 對向坡道／障礙、原 Actor＋100 Army rows、原移動種子與 headless 投射物 fallback。沒有改疲勞增減規則。 |
| 同一步原目標 contact batch／lazy projection | GPU `104939_082` PASS：cached／uncached 原頂點及有序接觸欄位 exact；原 live 女角及普通兵的實際裝備／格擋／移動／移除、遠程排除招架、下一步失效、僅 active 段保留武器歷史。早先 `104625_277` 的斷言與越界 FAIL（25.161 s）保留；後續新增 grounds 重用不包含在這次較早 PASS 中。 |
| source 相同 rotation 守衛 | GPU `111034_962` PASS，12.558 s、13 exact pairs、最大誤差 0；原 unconditional setter 對實際 rotation 完全相等才略過 setter，完整 samples／bones／morphs／worn armor vertices／protection 相等。當時 source SHA256 `e275a884…bef7f2`；原／guard 局部 elapsed 2,850,915／2,781,174 μs，不是 FPS。 |
| 同一步 grounds 重用 | GPU `111159_730` PASS，12.046 s；原 ground 錨點與 ordered contact 欄位、第二支 Army 的遠處 index 0、原 live 女角與普通兵裝備／格擋／移動／移除、直接移動與下一步失效、遠程排除招架、active-only history 均經專用對照。 |
| armor triangle 重用 | 男女 GPU `112837_592`／`112909_963` 均 PASS，helper 6.945／7.151 s；每體 `mesh=77`、`armor=12`、`positive=58`，原判斷式／顺序、實際盔甲盾與低姿態、微小邊緣偏移、world+5000、混合 topology／cache miss 精確對照。原／reuse 局部耗時男 1,055,789→614,563 μs，女 1,043,297→612,989 μs；**只是 nonvisual 幾何驗收，不是手動檢圖或 200 人 FPS PASS**。 |
| 同一步 exact armor memo | GPU `113318_938`／`113410_849` PASS，helper 8.835／10.013 s；`armor_query_reuse/group_0.json`／`group_1.json` 各 14／130 exact cases，最大誤差 0。重用前仍還原原姿態，原 point／direction／配裝等輸入不近似，不改三角形、人物或時間；包含獨立 128 上限的驗證。原／重複 query 局部耗時各 785,683→938 μs、1,813,212→3,787 μs，只是同一步重複查詢，不是 FPS。當時 source SHA256 `6c113e65…987d2f`。 |
| exact held-state 重用 | GPU `114138_330`／`114250_368` PASS，helper 8.135／7.466 s；`held_state_reuse/group_0.json`／`group_1.json` 各 13／7 exact cases，最大誤差 0。原 super visibility owner 對完整 held-state 輸入，原姿態／幾何不變；group 0 的 19-call 對照中更新局部耗時 4,436→506 μs，非 FPS／畫面驗收。當時 source SHA256 `22dc8482…56b3ad`。 |
| private query labels | GPU `115952_202` PASS，helper 10.989 s；`query_labels.json` 的 9 exact pairs、最大誤差 0。僅略過非渲染私有查詢 editor 的隱藏文字更新，原 timeline Range／clamp signals、camera、animation、完整 bones／morphs／geometry／armor 保留；兩路 range events 完全相同，不改可見玩家 UI。當時 source SHA256 `d14188e2…71e98d`；pose 局部計時 67,017→30,615 μs，不是 FPS 或完整畫面驗收。 |
| Geometry 原骨架按需查詢 | 男／女 GPU `120510_276`／`120556_543` PASS，helper 18.196／18.408 s；`lazy_bone_queries/male.json`／`female.json` 各 21 exact pairs、所有最大誤差 0。每案在首個 body／weapon／shield 查詢前重寫同一原 local pose 為 dirty，原全骨架 force 路徑與原生 getter 按需更新對照；骨架／mesh／polygon／armor 與完整 Dictionary 相等。每體一組原／lazy 呈現，`render_byte_differences=0`；主控已檢視男、女合計四張 PNG。局部 query 計時男 205,587→197,047 μs、女 211,520→196,080 μs，只有小幅局部差異，不是 200 人 FPS 證據。Geometry SHA256 `b37bf4be…0dc961f`。 |
| Actor 披風／劍鞘兩項批次 | 男／女 GPU `120657_397`／`120832_237` PASS，helper 23.644／24.547 s；每體 54 子步／18 畫面对、`exact=true`。props 保留每原子步及原 ammo sync 順序，不含已撤回的 props 批次。每子步原碰撞／骨架／props 與原生畫面更新後 cloth／scabbard／props／morph／material／像素 exact，手動／非 Lab immediate 與 ammo sync 亦通過；詳見下節。沒有整場 FPS 或實際傷害長跑結論。 |
| partial-weapon 精確按需補齊 | GPU `121055_602`／`121148_567`／`121220_951` 三組 PASS，helper 10.530／9.629／8.964 s，原 log 分別記 group 0／1／2 的 4／65／4 cases。涵蓋只取受擊所需欄位後補武器、交錯姿態的原 owner 還原／骨架與護甲、64 份 terminal 上限及第 65 筆、原 live 女角與普通兵移動／真裝備轉移、shieldless parry、原攻擊資格與 active 預取；不改原資料字典欄位結果、命中精度或取樣時間。此測試以三批 canonical log 保存契約與 counters，未產生另份 measurements JSON；不是 FPS 或人工看圖驗收。 |
| Actor 同批受擊範圍拒絕 | 男／女 GPU `122449_853`／`122542_067` PASS，helper 7.843／7.961 s；`actor_batch_bounds/body_0_1789273497.json`／`body_1_1789273549.json` 每體 40 原姿態、1,632 exact contacts、1,088 positive、544 skip-narrow，最大誤差 0。原 limb／shield／parry 投影在同批開關兩路及 uncached 原接觸結果完全相等；`batch_actor_bounds_enabled=true`，沒有省略有效接觸。Lab 報告 SHA256 `55e5b205…d96e39`；這是幾何／接觸驗收，不是 FPS 或人工畫面驗收。 |
| 私有查詢 paused-assigned 播放 | v1 GPU `122103_351` PASS 14.819 s，v2 `122708_799` PASS 16.279 s；各 14 組原 play/seek 對 paused assigned/seek 完全相等，另有 8 原 Actor 與 8 fallback checks。v2 再含 8 分類快取失效檢查；完整骨架／morph／盔甲／可見性保留，版本／精度與局部計時界線詳列下一節。v1 當時保持關閉，v2 驗收後主控才將預設改為啟用；沒有整場 FPS 收益結論。 |

上述已列出的 JSON 位於 `output/site_combat_performance_20260913/`，沒有獨立 JSON 的測試以該批 `verification/` 原 log 為準。各局部微秒量測只代表該函式／測試負擔；完整 200 人即時門檻仍以下一輪正常場景量測為準。

### 12:21–12:27 paused-assigned 的兩版證據

原私有查詢 editor 的第一版 [group_0.json](output/site_combat_performance_20260913/paused_assigned/group_0.json) 已通過 14 exact pairs，native mixer applications 25→15，但每次重查允許的動畫 track 帶來 `guard_usec=73594`；当時仍維持預設停用。測試局部總 elapsed 1,209,471／1,355,418 μs 也不支持直接宣稱較快，該版歷史保留。

第二版 [group_0_cached_v2.json](output/site_combat_performance_20260913/paused_assigned/group_0_cached_v2.json) 對同一分類結果重用，並以 `Animation.changed`、允許／拒絕分類的變動、回復、重建來源等共 8 checks 驗證失效。兩路原完整 sample／bones／morph／armor vertices／protection／visibility 的 14 exact pairs 最大誤差 0；另 8 次原 Actor 投影對照實测最大差約 `0.0000191813`，沿用既有 `<0.01` 的投影界線，原 protection exact，**不把這 8 次寫成 bit-exact 零差**。8 項 fallback 保留不符資格動畫／播放狀態的原路徑。

v2 分類計時各 8 calls：cold guard 41,443 μs、warm guard 28 μs；完整測試兩 pass elapsed 為 1,220,693／1,777,809 μs，包含測試專用動畫變更、raw-copy／fallback 操作，不能當作 FPS 或公平總吞吐對照。原報告的 source SHA256 `f9205355…ea6c48` 對應該次測試版本；測試明確各跑 `false`／`true`，通過後主控才令 `paused_assigned_playback_enabled=true`。截至此節，還沒有同一新預設下的整場即時 FPS 結果，不能將 25→15 次 mixer 或 41,443→28 μs 分類快取推算成整場收益。

### 已撤回：Actor 三項 cosmetic batch（含 props）

同時延後 props／scabbard／cape 更新的舊候選已撤回，當時 Actor 恢復原三呼叫立即執行，其他人的 contact 優化未撤回；後續縮小為僅兩項的實作與新測試另列下一節，不是復活舊候選。男組 GPU 三次 FAIL：`105950_249`（13.481 s，初態未隔離）、`110257_994`（14.072 s，弓弦 morph 初態殘留）、`110551_967`（17.818 s，補齊初態後仍有 Arrow transform 浮點尾數差）。末次已有 9 個 exact 畫面對與 30 個 exact 碰撞／骨架子步，但在 `bow_reload` 的 `0.4442088`／`0.44420883` 等變換值未完全相同；兩張圖像素 SHA256 仍相同。

未放寬 exact 標準，沒有女組或完整 18-case PASS，也沒有確定效益；這不是已診斷的遊戲缺陷。測試、依賴已撤回候選的說明及三次 canonical FAIL 留在 `output/site_combat_performance_20260913/rejected/`，由 `.gdignore` 排除，不再當 current test。

### 12:06–12:08 新縮小版：只批次披風／劍鞘

目前 `batch_cloth_updates_enabled=true` 只在 `combat_driven_by_lab && is_processing()` 時，將 `_advance_combat_pose` 末尾 scabbard／cloth 設為 dirty，於原 Actor `_process` 的既有 `_sync_ammo_visual()` **之後**補齊兩呼叫。props 每原子步仍更新，ammo／fire／attack／seek／120 Hz 動作時鐘不變；手動／非 Lab 路徑立即更新。延後的 cloth registry 只含 `Cape_*`，不是碰撞護甲或 outfit morph，沒有新增角色／裝備 owner。

新 `site_actor_cloth_batch_test.gd` 以同一原 Actor／Editor 重播完整武器歷史，兩路只在整段開始重設相同全部模型 blend shapes 與 props 初態，**不每案清掉歷史**。`bow_reload` 排第一，涵蓋 idle／兩種 guard／down→unconscious／起身高低姿勢／rescue／弓弩裝填及武器切換／空彈藥／徒手／兩款披風，共 18 案；每案同樣三個 delta（1/120、1/120、0.00371 s）。原 Editor 自動更新保留，原 1280×1536 viewport 每案精確像素 SHA 與全部呈現狀態一致，男／女各 54 子步及 18 畫面對完整通過。原數據：[男組](output/site_combat_performance_20260913/actor_cloth_batch/body0/1789272418_1413709/measurements.json)、[女組](output/site_combat_performance_20260913/actor_cloth_batch/body1/1789272513_1455616/measurements.json)。

主控已補完人工檢視**男、女各 immediate_bow_reload／batched_get_up_low／batched_rescue，共六張代表圖**；這不是逐張人工看過全部 18 案圖片，全部案例的像素 exact 另由 GPU 測試證明。較早「女組代表圖未檢視」為當時狀態，現已補驗。兩次 A/B 內來源不變，Actor SHA256 `62f9293c…348431`、Geometry `b37bf4be…0dc961f`、HumanEditor `23096424…29ff7b8`；只是此來源下的精確等價證據，最新全裝 short10 仍未達標，不將本候選稱為已證實整場 FPS 收益，也不取代 live damage 或完整即時混合配裝验收。

### rotation／grounds 的驗收進展與剩餘界線

較早版本曾將兩者列為待驗；現已取得上表各自的 `111034_962`／`111159_730` exact PASS，不是挪用 seek-only 或舊 batch 的結果。其後混合／baseline 短測仍未達標。最新 armor triangle 通過的是 nonvisual 幾何對照，主控尚未以 GPU 畫面手動檢驗此候選，亦尚無來源穩定且達標的完整混合配裝 60 秒即時結果；不能把後續尚在進行的 run 預先写成結果。

### m25 僅測試 staging，不是正式 32 配方修復

`output/terrain_army_m25_weapon_refresh_20260913/` 的五批真 GPU result 已為 PASS，共 536 原取樣，helper 合計 39.378 s；`test_catalog.json` 明列 `test_only=true` 且只有 `standard_soldier_v2/m25`。這是新版來源的卸盾＋卸甲測試配方，**不是**正式 `recipes/v1/catalog.json` 的 32 配方重建／修復或完整發布。

歷史 test-only publisher `111015_170` headless PASS、2.707 s：原 log 明列五批／536 keys、其他 31 masks 拒絕、formal catalog unchanged。該次原四檔本次補永久歸檔；此歷史准入不抵銷下述 11:20:40 來源變更後的失效。

只有測試明確切到該 test catalog 才使用它；其他 31 缺裝配方不得冒充已准入。本節以真五批結果及 catalog 為準；該 staging README 頂部「尚未執行」是較早準備狀態，本次只更新此效能文件，不回改舊 output。後續來源若再變仍須照原指紋守衛重新驗，不改舊指紋讓它強行通過。

主控已檢視這五批 m25 圖像，且 `111306_450` 曾沿此 test catalog 完成混合短測；但之後 HumanEditor 11:20:40 變更令其指紋失效，`112329_831` 已真實拒絕。五圖已檢、歷史准入與**目前來源可用性**是不同證據，不得把失效後的舊 staging 當最新正式資產。

新 test-only 目錄為 `output/terrain_army_m25_performance_20260913/`；較早「只有工具、尚未執行」是當時準備狀態。指定新目錄的預檢 `130207_709` 已實際 **FAIL、exit 2、1.583 s**，原 log 指出 baker／baseline 未通過完整 536-key 計畫相等守衛。診斷為 JSON `clips.samples` 是 float、原 Baker 是 int，完整 Dictionary equality 對數值型別嚴格；後續程式只將驗過有限／正整數／範圍內的 sample count 正規化為 int，保留其餘欄位、次序與完整比較。**此修正的後續驗收、plan 鎖定與五批烘圖不在本段截至 `130522_232` 的指定核對清單，不能由目錄或 plan 存在推斷通過**；原 FAIL 不改。

後續仍必須由穩定六來源鎖定五個原批次，取得 536 keys／五批原 GPU PASS／PNG-RES proof／原 Reader 全驗，才可發布新的 test catalog；不修改舊 catalog 指紋或正式 32 配方規則。本次文件／歸檔工作未啟動任何烘焙或 Godot。

**13:06–13:10 後續已完成證據：**前段「仍待」保留為截至 13:05 的歷史狀態。`130629_309` headless validate PASS 2.015 s，原完整 536 unique keys／五分段且不寫檔；`130646_082` prepare PASS 2.490 s，才鎖定當時六來源＋baseline，建立新的原 plan。後續五個原 GPU batches 均完成如下，合計 helper 39.157 s；每批原 log 皆記錄 PNG／RES decoded SHA 相同，主控已人工檢視五張 `page_000.png`。未修改舊失敗、旧 m25 目錄或正式資產。

| 新 m25 分段 | Canonical GPU run | helper s | 原批次與原四檔目錄 |
| --- | --- | ---: | --- |
| 0＋128 | `130715_435` | 7.794 | `full/m25/000_128/`、其 `verification/` |
| 128＋128 | `130742_073` | 7.957 | `full/m25/128_128/`、其 `verification/` |
| 256＋128 | `130805_364` | 8.263 | `full/m25/256_128/`、其 `verification/` |
| 384＋128 | `130828_084` | 8.199 | `full/m25/384_128/`、其 `verification/` |
| 512＋24 | `130923_482` | 6.944 | `full/m25/512_024/`、其 `verification/` |

表內相對根為 `output/terrain_army_m25_performance_20260913/`，原四檔亦另收入本輪永久 archive。`131006_854` test-only publisher headless PASS 2.510 s，原 Reader 驗五批／536 keys、其他 31 masks 拒絕、formal catalog unchanged；[新 test_catalog.json](output/terrain_army_m25_performance_20260913/test_catalog.json) 明列 `test_only=true` 且僅一個 `standard_soldier_v2/m25`。後續 `131152_801` 已沿它完成原物品轉移後的混合短測，但效能仍未達標。這是該六来源鎖下的測試准入，**不是正式 32 配方重烘／修復／完整發布**；來源再變仍須原守衛重新核對，不改舊 hash 假稱像素相同。

## 本輪最小改動

1. 只在既有非渲染共用查詢 editor 保留原動畫原精確時間，避免相同 loop_mode 寫入與 play／pause 往返重建原生動畫快取。初始化仍走原 editor；測試可切回原路徑，沒有另建每兵骨架。
2. 原瞄準解算只移除每次關節迭代內的全骨架同步；原 getter 會更新需要的父骨鏈，保留最前／最終與長槍分支的同步。64 輪上限、原式與精度不變，必須和封存舊函式逐骨／逐頂點比較。
3. 原精確 down.length、LOOP_NONE、無瞄準終態使用最多 64 份完整輸入 local sample；每步暫存仍 128、裝備變更／來源重建全清，跨步回傳不冒充目前 editor 姿態。兩組原 owner／三步交錯／護甲回復／完整 key／65 筆溢位 GPU 通過（`101157_798`、`101206_928`），不快取世界位置或點護甲結論。

原生快取與骨架更新行為查核自 [Godot 4.6 AnimationPlayer](https://github.com/godotengine/godot/blob/4.6/scene/animation/animation_player.cpp)、[AnimationMixer](https://github.com/godotengine/godot/blob/4.6/scene/animation/animation_mixer.cpp)、[Skeleton3D](https://github.com/godotengine/godot/blob/4.6-stable/scene/3d/skeleton_3d.cpp)。是否實際改善仍以本機同場景測量為準。

## 證據及並行變動

原共用來源與碰撞函式已逐檔 SHA-256 封存於 `output/site_combat_performance_20260913/before/`，不回改舊結果。早期紀錄為動畫快取六組測試中的 0–3 組已通過原骨／護甲／完整 sample 精確對照；後續獨立 seek-only 等測試的實證另列上節，不把兩套測試或不同來源混成一次驗收。這不是即時效能達標。

瞄準 lazy-bone 對照六組均 GPU PASS：男女地面／騎乘長劍、男女地面長槍，共 36 例，所有原骨、实际持物頂點、碰撞／護甲最大誤差皆為 0。首組單獨瞄準計時 5,109 → 2,942 微秒，是局部計時而非 FPS。結果在 `output/site_combat_performance_20260913/aim_lazy_bones/`；原 verifier 執行 `100630_178`、`100717_036`、`100729_030`、`100741_051`、`100753_266`、`100806_759`。

真實自動 `_process`／GPU 測試已加入 `site_army_combat_realtime_test.gd`，headless check-only `101137_423` PASS。第一次 short10 `101224_402` **FAIL 142.847 秒**：缺裝圖集來源鎖拒絕變更後的 HumanEditor，前置配裝回傳 UNSUPPORTED，尚未進入量測。不是 FPS 失敗，也沒有可報的幀率；舊報告保留在 `output/site_army_combat_realtime/3b70b31f33cd9480/short10/1789265546_2090188/`。其後已補前置失敗即停與明確「原全裝、非完整驗收」診斷模式，不繞過正式來源守衛。另保留 `102008_542` **FAIL 142.555 秒**：測試誤要求原 SiteController 主動隱藏的 optional debug UI 也可見；修為只要求原 Site HUD，並記錄 debug UI 實際狀態，這也不是一次 FPS 量測。

保留 `20260913_100008_736` group 4 FAIL：同目錄另一項美術工作先註冊 wood_axe_01 候選選項，但正式 GLB 尚無該 mesh，舊／新查詢皆拒絕。測試改為完整驗實際模型提供的武器，候選明列 UNAVAILABLE，而不是替缺失物品造幾何；舊 FAIL／逾時與錯誤後印出的 PASS 字樣不抹除。後續武器正式發布仍需重新驗證，不混用候選與正式來源。

較早唯讀任務快照曾顯示「建立 HumanBase_v1 標準人體」為 active，當時原模型與 HumanEditor 的那些變更不是本輪優化改動。主控後續唯讀確認該素材任務已 idle 完成後，才以已封存的 11:20:40 原 HumanEditor 為基準，實作本輪三處有開關的骨架同步守衛；不把這三處新改動再歸給另一任務。未跨任務傳訊或干預，亦不據此宣稱整個 HumanBase 生產驗收完成。正式圖集仍鎖定來源指紋，最新來源／圖集一致性必須另外核對；不能把舊六來源指紋當成現況。較早跨任務傳送協調通知曾被安全檢查拒絕，歷史保留；未獲新許可不改道傳送。

尚未提交 Git、未改正式玩家存檔，保留其他工作樹變更。Godot 使用原未修改的有界 helper；本任務子代理不另啟 Godot，其他任務的驗證／桌面程式不擅自終止。
