# Terrain Lab V4／V5 最終驗收 — 2026-09-10

狀態：COMPLETE。預設 TERRACED_HIGHLAND／seed 12345／正式 deploy／MOVE_TO_EDGE 已修好；V4／V5 指定功能、交易安全、幾何／生成／dt 矩陣、GPU 畫面與七個活動效能時段均有最終版本證據。本頁取代先前 PARTIAL 狀態；原始失敗 log 保留，不混入本次 PASS。

最終封存：[TERRAIN_LAB_V5_EVIDENCE.json](TERRAIN_LAB_V5_EVIDENCE.json)。包含 133 個 headless case／參數組合、8 個 GPU 功能重播、7 個效能時段、1 次 editor scan，以及每份 log、源碼、測試、圖像／metadata 的 SHA256。133 是執行組合數，不是宣稱有 133 個獨立測試檔。

## 1. 操作結果與修正原因

在 `scenes/terrain_lab/TerrainLab.tscn` 保留預設地圖，部署軍隊後執行「走到地圖邊緣」。隊長正常到達 `(99,75)`，99 名隊員完成五個必要坡口，清空受保護出口，落入同一個已發布的合法 10×10 footprint 內的 99 個獨立陣位，再穩定至少 5 秒。

原始原因不是人數或速度不足：坡口寬度把相鄰同高度邊誤算為下坡 lane，令真實五段 passage 沒有啟動；舊 trail／101 格門檻、出口目標重配、階段判定與交易釋放又會阻斷隊尾。修正集中在既有 `TerrainArmy`：單一合法連通寬度、逐段通過／出清、階段優先調度、固定陣位、在途交易安全排空及有界共用結構分析。HUD 僅讀真實 summary，沒有新增導航或 reservation 框架。

效能修正沿用已有搜尋與 trail cache：拒絕已知不可能的局部目標、避免重複掃描同一 trail；曾造成 seed 12346 退步的 APPROACH 距離場捷徑已撤回，保留原有有界 A*。沒有調速度、增加配額、降低 99 人門檻或延長完成期限。

## 2. 最終版本與工作樹

| 檔案 | SHA256 | 最後修改 UTC |
| --- | --- | --- |
| `scripts/terrain_lab/terrain_army.gd` | `eb2a7bb8c5d8db026c98ae6385ff700680dce6f2504df66196ee3cb49c3f896b` | 2026-09-10T04:06:54.727Z |
| `scripts/terrain_lab/terrain_lab.gd` | `6bf08fe98c935c727e872a3fc8d49589d64994344c4c22163b1fb3f1f9fc8ea1` | 2026-09-09T23:21:38.425Z |
| `scripts/terrain_lab/terrain_generator.gd` | `7682d17637499d721e1fe11d2673b11f5b6419e5fc9ddef64c02262752ef37ee` | 2026-09-07T07:35:20.183Z |
| `scripts/tests/terrain_army_default_edge_test.gd` | `eca832ad5ba8a40b6d406a425cc091fbc5fae9a84d721acb39d998044634726a` | 2026-09-10T04:10:40.712Z |
| `scripts/tests/terrain_army_width_transaction_test.gd` | `736b6d600fb69e93c16b6b7fbe4cc9f482a9e8e6d8ba895f73eb22bf996c6683` | 2026-09-10T04:40:28.124Z |
| `scripts/tests/terrain_lab_army_visual_test.gd` | `3b714f71d23c92484d8212f343eb4ca341ad478b7be01e352968a379666f3385` | 2026-09-10T04:45:08.423Z |
| `scripts/tests/terrain_army_entrance_clearance_test.gd` | `0538b24006e05f8288a556411e143ed855c6f1bbbeca65f3393d435cda733d4d` | 2026-09-10T04:22:01.561Z |
| `scripts/tests/terrain_army_formation_smoke_test.gd` | `2f79a1bdacd3b36a94a53c0ade6f3a3edaaefd891e4abe4191efc4b1fdd330ba` | 2026-09-10T03:03:57.955Z |
| `scripts/tests/terrain_army_captain_route_test.gd` | `92cb0f5ea4bcd03e69a48e1b5961e17ccba5f5df9cbf944ef0d19bdab09b6205` | 2026-09-10T04:23:11.951Z |
| `scripts/tests/terrain_army_passage_test.gd` | `2a79620159eb26edc549e045186f84e62b1467e54dae4459478f3eb356b919f3` | 2026-09-10T03:51:46.274Z |
| `scripts/tests/terrain_lab_army_test.gd` | `395b073648e730d344ecca822780d7d75cfb840228a44d55fa093221a7bc9798` | 2026-09-10T03:07:35.540Z |
| `scripts/tests/terrain_lab_default_edge_performance_test.gd` | `d16d6f30688d95437f304682588aa68d4e9a3f7e27f1e6f80d508eedd533bed9` | 2026-09-10T03:44:17.450Z |

實際實作變更：`terrain_army.gd`、`terrain_lab.gd`；驗收變更為上表 9 個測試檔，以及 V4／V5 狀態文件與本證據封存。生成器列在表內是核對未變更，不是本次修改。相關程式與文件原為 untracked，仍留在工作樹；沒有 stage、commit、還原或覆蓋無關變更。

保留原值：100 人（隊長＋99 隊員）、MOVE=0.24s、RUN=0.18s、SIM_STEP=0.10s、每 frame 最多 2 個 simulation ticks、captain／structure 每 frame 256 expansions、local 每 tick 最多 4 次且每次 1024、push 每 tick 至多一個新交易且最多 512 expansions、formation columns=10。地形 fingerprint 仍為 `c8a3021229df7f5f4324c39ee75fada205999efd74ec4f2cb13b481f12bc3367`。

## 3. 功能與安全驗收

| 範圍 | 當前結果／證據 |
| --- | --- |
| D01 60Hz | PASS；142.8s 完成，input=185s、sim=185s、drop=0；[20260910_122328_579](.godot-temp/godot_verify/20260910_122328_579/combined.log) |
| D01 30Hz | PASS；144.6s 完成，5s 穩定，input=sim=185s、drop=0；[20260910_122554_090](.godot-temp/godot_verify/20260910_122554_090/combined.log) |
| D01 交替 1/120、1/40 | PASS；142.8s 完成，5s 穩定，input=sim=185s、drop=0；[20260910_123058_685](.godot-temp/godot_verify/20260910_123058_685/combined.log) |
| D01 物理不變量 | 五個 gate 的 crossed 與 cleared 均為 [99,99,99,99,99]；逐人有序、無逆向／重複事件；captain 253 條實際邊＝獨立 BFS 253；99 個唯一合法 slot 與實際佔位相等；最終沒有殘留 move/swap/push/claim/lock |
| W01–W05、取消與 large dt | PASS；真實五口寬度為 1，兩個寬度 caller 一致；兩種取消保留在途邊。大 dt：input 1.0＝sim 0.2＋drop 0.7＋retained 0.1；[20260910_124028_539](.godot-temp/godot_verify/20260910_124028_539/combined.log) |
| E01／E02 | 60Hz 各 73.8s 完成，crossed=cleared=99、initial exempt=0、穩定5s；30Hz／交替 dt 也 PASS；[20260910_122358_384](.godot-temp/godot_verify/20260910_122358_384/combined.log)、[20260910_122401_948](.godot-temp/godot_verify/20260910_122401_948/combined.log) |
| E03／E04／E07–E12、terminal | 14 組入口幾何 × 3 種 dt＝42 組，全 PASS；容量不足案例正確回報 failure reason 並保持未完成，不把負例誤寫成全隊收齊 |
| E05／中間小平台 | 55 條轉彎通道邊各有99人依序通過；中間小平台無須容納全隊即可交接；兩案 × 3 種 dt 全 PASS |
| E06 0→1→0／3→2→1→0 | 兩案 × 3 種 dt 全 PASS；60Hz 完成85.3s／129.3s，每段crossed=cleared=99，末尾穩定5s |
| F01／F02／F03 | F01 三種dt都18.7s完成99人，未改20s期限，另穩定5s。F02 slot 身分／綁定契約 PASS；F03 正式100人部署、99個持續eligible requester ≤25 ticks全部獲得服務，單人每tick不重複消耗配額 |
| Q01–Q05／M01–M02／X01 | 中間空格、三 blocker 推擠、搶格、環境變更、lock／owner／phase／direction、commit 驅動 timeout、requester 保護、出口方向、shared goal／detour、取消均 PASS；逐組參數與 log 見證據 JSON |
| 換命令 | MOVING／captain swap／follower swap／push × EDGE→FOLLOW、FOLLOW→EDGE，共8組全 PASS；保留在途邊與 claim，排空舊命令後執行最新命令 |
| 既有 full／captain／passage／formation | 全部 PASS；完整 army 回歸 [20260910_123723_823](.godot-temp/godot_verify/20260910_123723_823/combined.log)。C01 actual=oracle=10、C02 zero-route=0，穩定goal5s，三種dt均 PASS |
| Editor | PASS、EXIT=0、未timeout、5.539s；[20260910_124748_504](.godot-temp/godot_verify/20260910_124748_504/result.json) |

每個正式案例從 `advance_frame` 進入；小型純 helper fixture 明確另列，不冒充正式100人場景。共用 oracle 每次實際 commit 檢查 legal four-direction edge、100個唯一 owner、claim／lock 所有人及外部占格。最終通過案例 overlap、illegal edge、owner mismatch、invalid claim、lock leak、非法回流均0。

完成判定不依賴單一 formation_count：独立封 gate flood 建立必要名單，逐人實際跨邊、出清、全序完成後才驗固定陣位與5s穩定。可行性證明也獨立找同高度10×10合法 footprint，不拿 production 已選 slot 當證明。通道有 ready 人員而5s沒有真正前向事件即失败；其他人的移動不會重設該計時。外部阻塞／真容量不足另行判定。

### E01／E02 10–40 秒快照

兩案60Hz的物理計數一致，完整逐人 crossing／clearing 時間及最終集合保存在上述各自 log：

| 輸入秒 | crossed | cleared | settled |
| --- | --- | --- | --- |
| 10 | 11 | 10 | 1 |
| 20 | 27 | 27 | 16 |
| 30 | 44 | 44 | 31 |
| 40 | 61 | 60 | 47 |
| 73.8 完成 | 99 | 99 | 99 |

最終上游 slot=0。E09 的外部 NPC 阻塞移除後恢復，沒有跳過阻塞檢查。E12_BYPASS 封住所選 gate 後仍有繞路，故不以同一 flood component 假冒已通過；本次99人仍真正通過所選gate。E12_DOWNSTREAM 另有10人初始位於經獨立分隔證明的下游，正確 EXEMPT；其餘89人實際 crossing／clearing，最後仍99人落位。E10 逆向測試、E11真容量不足、同高度terminal與真坡terminal皆保留各自語義，不共用「99人已跨」聲明。

## 4. 生成地形完整矩陣

TERRACED_HIGHLAND／ROCKY_MOUNTAINS × seed 12345、24680、12346 × EDGE／FOLLOW，共12候選；每個候選均有 preflight fingerprint、初始部署、獨立可行性／必要gate名單。無 seed 排除、無 SKIP。每個再跑60Hz／30Hz／交替dt，共36組全PASS，完成後各穩定5s；最慢173.7s，保留180s期限。

下表為完成輸入秒／對應 log；input、sim、drop、逐人名單等原始欄位在各 log 中。

| preset / seed / command | 60Hz | 30Hz | 交替dt |
| --- | --- | --- | --- |
| terraced / 12345 / edge | 142.8 / [20260910_121513_682](.godot-temp/godot_verify/20260910_121513_682/combined.log) | 144.6 / [20260910_122801_972](.godot-temp/godot_verify/20260910_122801_972/combined.log) | 142.8 / [20260910_123352_474](.godot-temp/godot_verify/20260910_123352_474/combined.log) |
| terraced / 24680 / edge | 130.1 / [20260910_121524_498](.godot-temp/godot_verify/20260910_121524_498/combined.log) | 131.8 / [20260910_122831_764](.godot-temp/godot_verify/20260910_122831_764/combined.log) | 130.1 / [20260910_123427_918](.godot-temp/godot_verify/20260910_123427_918/combined.log) |
| terraced / 12346 / edge | 159.9 / [20260910_121544_038](.godot-temp/godot_verify/20260910_121544_038/combined.log) | 161.6 / [20260910_122859_621](.godot-temp/godot_verify/20260910_122859_621/combined.log) | 159.9 / [20260910_123511_914](.godot-temp/godot_verify/20260910_123511_914/combined.log) |
| terraced / 12345 / follow | 141.4 / [20260910_121557_699](.godot-temp/godot_verify/20260910_121557_699/combined.log) | 143.1 / [20260910_122809_343](.godot-temp/godot_verify/20260910_122809_343/combined.log) | 141.4 / [20260910_123416_407](.godot-temp/godot_verify/20260910_123416_407/combined.log) |
| terraced / 24680 / follow | 133.0 / [20260910_121620_781](.godot-temp/godot_verify/20260910_121620_781/combined.log) | 134.6 / [20260910_122842_509](.godot-temp/godot_verify/20260910_122842_509/combined.log) | 133.0 / [20260910_123459_790](.godot-temp/godot_verify/20260910_123459_790/combined.log) |
| terraced / 12346 / follow | 164.5 / [20260910_121632_217](.godot-temp/godot_verify/20260910_121632_217/combined.log) | 166.2 / [20260910_122910_902](.godot-temp/godot_verify/20260910_122910_902/combined.log) | 164.5 / [20260910_123538_600](.godot-temp/godot_verify/20260910_123538_600/combined.log) |
| rocky / 12345 / edge | 147.1 / [20260910_121653_655](.godot-temp/godot_verify/20260910_121653_655/combined.log) | 152.3 / [20260910_122939_382](.godot-temp/godot_verify/20260910_122939_382/combined.log) | 147.1 / [20260910_123551_860](.godot-temp/godot_verify/20260910_123551_860/combined.log) |
| rocky / 24680 / edge | 113.5 / [20260910_121704_366](.godot-temp/godot_verify/20260910_121704_366/combined.log) | 116.2 / [20260910_122954_368](.godot-temp/godot_verify/20260910_122954_368/combined.log) | 113.5 / [20260910_123622_407](.godot-temp/godot_verify/20260910_123622_407/combined.log) |
| rocky / 12346 / edge | 163.4 / [20260910_121722_384](.godot-temp/godot_verify/20260910_121722_384/combined.log) | 168.7 / [20260910_123015_452](.godot-temp/godot_verify/20260910_123015_452/combined.log) | 163.4 / [20260910_123654_253](.godot-temp/godot_verify/20260910_123654_253/combined.log) |
| rocky / 12345 / follow | 146.7 / [20260910_121733_093](.godot-temp/godot_verify/20260910_121733_093/combined.log) | 151.5 / [20260910_122947_029](.godot-temp/godot_verify/20260910_122947_029/combined.log) | 146.7 / [20260910_123612_411](.godot-temp/godot_verify/20260910_123612_411/combined.log) |
| rocky / 24680 / follow | 116.5 / [20260910_121753_405](.godot-temp/godot_verify/20260910_121753_405/combined.log) | 119.1 / [20260910_123008_905](.godot-temp/godot_verify/20260910_123008_905/combined.log) | 116.5 / [20260910_123645_898](.godot-temp/godot_verify/20260910_123645_898/combined.log) |
| rocky / 12346 / follow | 168.5 / [20260910_121802_645](.godot-temp/godot_verify/20260910_121802_645/combined.log) | 173.7 / [20260910_123022_905](.godot-temp/godot_verify/20260910_123022_905/combined.log) | 168.5 / [20260910_123713_427](.godot-temp/godot_verify/20260910_123713_427/combined.log) |

## 5. 真實 GPU 畫面與 HUD

8個 GPU 重播皆使用實際 Terrain Lab 場景、EXIT=0、未timeout，源碼／測試SHA與最終版本一致。D01／E01／E02各四個必要階段共12張新圖均實際檢視；地形高度／遮擋、隊尾繼續前進與最終陣形一致。所有 PNG 保留，SHA與逐張時刻見JSON；JPEG僅為閱讀預覽，不取代原圖。

HUD 顯示真實 captain goal、到邊界、待過口／core-egress／已完成通道／已落位；GPU測試對 `_update_info()` 前後的 cells、desired、claims與搜尋計數做只讀核對。

| 案例 | GPU log | 截圖階段與輸入時刻 | 完整索引 |
| --- | --- | --- | --- |
| D01 | [20260910_124650_671](.godot-temp/godot_verify/20260910_124650_671/combined.log) | 01_approach: 2.700s; 02_captain_arrived_tail_waiting: 78.000s; 03_last_exit_cleared: 132.800s; 04_all_99_settled: 147.800s | [metadata](.visual_captures/terrain_lab/v5/D01_metadata.json) |
| E01 | [20260910_125136_885](.godot-temp/godot_verify/20260910_125136_885/combined.log) | 01_approach: 1.200s; 02_captain_arrived_tail_waiting: 6.300s; 03_last_exit_cleared: 64.300s; 04_all_99_settled: 78.800s | [metadata](.visual_captures/terrain_lab/v5/E01_metadata.json) |
| E02 | [20260910_125211_609](.godot-temp/godot_verify/20260910_125211_609/combined.log) | 01_approach: 1.200s; 02_captain_arrived_tail_waiting: 6.300s; 03_last_exit_cleared: 64.300s; 04_all_99_settled: 78.800s | [metadata](.visual_captures/terrain_lab/v5/E02_metadata.json) |
| V_MOVE | [20260910_125647_050](.godot-temp/godot_verify/20260910_125647_050/combined.log) | 00_frame_000: 0.000s; 01_frame_003: 0.050s; 02_frame_006: 0.100s; 03_frame_009: 0.150s; 04_frame_012: 0.200s; 05_frame_015: 0.250s; 06_frame_018: 0.300s; 07_frame_024: 0.400s; 08_frame_036: 0.600s; 09_frame_054: 0.900s; 10_frame_072: 1.200s; 11_frame_096: 1.600s | [metadata](.visual_captures/terrain_lab/v5/V_MOVE_metadata.json) |
| V_CAPTAIN_SWAP | [20260910_125733_061](.godot-temp/godot_verify/20260910_125733_061/combined.log) | 00_frame_000: 0.000s; 01_frame_003: 0.050s; 02_frame_006: 0.100s; 03_frame_009: 0.150s; 04_frame_012: 0.200s; 05_frame_015: 0.250s; 06_frame_018: 0.300s; 07_frame_024: 0.400s; 08_frame_036: 0.600s; 09_frame_054: 0.900s; 10_frame_072: 1.200s; 11_frame_096: 1.600s | [metadata](.visual_captures/terrain_lab/v5/V_CAPTAIN_SWAP_metadata.json) |
| V_FOLLOWER_SWAP | [20260910_125815_809](.godot-temp/godot_verify/20260910_125815_809/combined.log) | 00_frame_000: 0.000s; 01_frame_003: 0.050s; 02_frame_006: 0.100s; 03_frame_009: 0.150s; 04_frame_012: 0.200s; 05_frame_015: 0.250s; 06_frame_018: 0.300s; 07_frame_024: 0.400s; 08_frame_036: 0.600s; 09_frame_054: 0.900s; 10_frame_072: 1.200s; 11_frame_096: 1.600s | [metadata](.visual_captures/terrain_lab/v5/V_FOLLOWER_SWAP_metadata.json) |
| V_PUSH | [20260910_125901_011](.godot-temp/godot_verify/20260910_125901_011/combined.log) | 00_frame_000: 0.000s; 01_frame_003: 0.050s; 02_frame_006: 0.100s; 03_frame_009: 0.150s; 04_frame_012: 0.200s; 05_frame_015: 0.250s; 06_frame_018: 0.300s; 07_frame_024: 0.400s; 08_frame_036: 0.600s; 09_frame_054: 0.900s; 10_frame_072: 1.200s; 11_frame_096: 1.600s | [metadata](.visual_captures/terrain_lab/v5/V_PUSH_metadata.json) |
| V_HANDOFF | [20260910_124530_203](.godot-temp/godot_verify/20260910_124530_203/combined.log) | 00_frame_000: 0.000s; 01_frame_003: 0.050s; 02_frame_006: 0.100s; 03_frame_009: 0.150s; 04_frame_012: 0.200s; 05_frame_015: 0.250s; 06_frame_018: 0.300s; 07_frame_024: 0.400s; 08_frame_036: 0.600s; 09_frame_054: 0.900s; 10_frame_072: 1.200s; 11_frame_096: 1.600s | [metadata](.visual_captures/terrain_lab/v5/V_HANDOFF_metadata.json) |

連續動作每案97個60Hz更新；各留12張圖，實際檢視前7張（frame 0、3、6、9、12、15、18），並對所有97幀檢查ground position連續性、方向無回彈、owner／claim與commit。單步、隊長swap、隊員swap、三blocker推擠、在途換命令全PASS。推擠commit順序[4,3,2,1]，requester最後。V_HANDOFF舊推擠的在途成員先完成，其後是新FOLLOW合法活動，所以末幀仍可有新命令移動，不宣稱整個新命令已收隊。

[預設山地99人完成圖](.visual_captures/terrain_lab/v5/D01_04_all_99_settled.png)。

## 6. 七個活動時段效能

硬體：Intel i5-14400F／NVIDIA RTX5060；Godot 4.6.2 Mono、D3D12 Forward+、2560×1440、VSync disabled、max_fps=0。每階段先60個真實渲染幀warmup；同一存活army到活動時刻後，使用自然render frame delta量測約3秒。各次均有實際commit或settled前進，不用卡住後idle FPS。

這是行軍、五個坡口、收隊的七段獨立活動取樣，並非完整180秒跑程的合併百分位，也不是排除所有其他應用程式的隔離硬體基準。功能完成時間取第3節正式重播，不把加速GPU截圖時間當效能。

ms欄依序P50／P95／P99／max；expansions為該時段單frame最大structure／local／push，與全程結構建置上限分開。

| 時段 | frames | frame ms | army CPU ms | expansions | input / sim / drop 秒 | log |
| --- | --- | --- | --- | --- | --- | --- |
| march | 329 | 8.969 / 10.877 / 11.778 / 13.152 | 0.098 / 1.958 / 3.024 / 3.534 | 0 / 45 / 7 | 3.0062 / 3.0000 / 0 | [20260910_125247_911](.godot-temp/godot_verify/20260910_125247_911/combined.log) |
| gate1 | 340 | 8.623 / 10.659 / 11.564 / 12.673 | 0.097 / 1.862 / 2.595 / 3.176 | 0 / 59 / 14 | 3.0079 / 3.0000 / 0 | [20260910_125324_759](.godot-temp/godot_verify/20260910_125324_759/combined.log) |
| gate2 | 343 | 8.464 / 10.663 / 11.516 / 17.096 | 0.097 / 1.914 / 2.464 / 4.233 | 0 / 31 / 4 | 3.0157 / 3.0000 / 0 | [20260910_120707_802](.godot-temp/godot_verify/20260910_120707_802/combined.log) |
| gate3 | 334 | 8.651 / 11.085 / 12.016 / 13.175 | 0.099 / 1.772 / 2.450 / 3.082 | 0 / 61 / 2 | 3.0054 / 3.0000 / 0 | [20260910_125412_669](.godot-temp/godot_verify/20260910_125412_669/combined.log) |
| gate4 | 344 | 8.591 / 9.566 / 10.665 / 15.536 | 0.097 / 0.658 / 1.731 / 4.116 | 0 / 0 / 0 | 3.0027 / 3.0000 / 0 | [20260910_125510_954](.godot-temp/godot_verify/20260910_125510_954/combined.log) |
| gate5 | 327 | 8.792 / 10.677 / 19.397 / 22.371 | 0.100 / 0.874 / 10.052 / 12.595 | 0 / 1072 / 1 | 3.0100 / 3.0000 / 0 | [20260910_125541_120](.godot-temp/godot_verify/20260910_125541_120/combined.log) |
| regroup | 331 | 9.003 / 10.228 / 10.946 / 11.974 | 0.097 / 1.141 / 1.643 / 1.936 | 0 / 69 / 8 | 3.0114 / 3.0000 / 0 | [20260910_125613_842](.godot-temp/godot_verify/20260910_125613_842/combined.log) |

七段全部達到 frame P95≤16.7ms、P99≤25ms、army CPU P95≤2ms；每段>50ms frame數均0，drop均0。最差frame P95=11.085ms、P99=19.397ms；最差army CPU P95=1.958ms。gate5 CPU單幀最大12.595ms照實保留，不把CPU P95目標偷換成最大值保證。

各時段真實committed_steps＝184／341／516／752／1000／904／57；合計前向gate commit/s＝1.663／2.992／3.979／4.991／5.662／4.983／0。收隊段settled由83→89，因此最後的0 gate/s是已全數過口而仍在收隊，不是停滯。細項每gate起訖人數、warmup耗時與所有原始值在 `.godot-temp/terrain_v5_performance/{march,gate1..gate5,regroup}.json`。

正式完整功能跑程也檢查配額：D01單frame structure≤256、local≤1125、push≤175；F01觀察local上限4096（4×1024），99個持續eligible人員25ticks內全服務。大dt丟棄獨立計帳，正常三種dt的drop為0。

## 7. V4／V5 靜態反查結果

以下是逐caller核對，不以零搜尋命中代替功能測試：

| 殘留／風險 | 當前用途與 guard |
| --- | --- |
| 兩套lane加總 | `_route_width` 使用同一 `_route_edge_width`；合法邊、相同轉換高度及側向連通才算同一lane，沒有另一套放寬加總 |
| 101格／舊queue | `_assign_bottleneck_queue_targets` 與舊slot擴充分支保留trail長度條件，但入口先拒絕 `_passage_active`；不再阻止新passage啟動或隊尾服務 |
| `cells==desired` 提前退出 | passage phase優先；只有RALLY／EXEMPT才可計入完成，APPROACH／IN_PASSAGE／EXIT_CLEAR繼續處理，Q03_PHASE與D01覆蓋 |
| 隊長高度／boundary | `_all_followers_on_captain_height` 無live caller；EDGE的boundary僅用於合法舊終點語義／顯示，passage直接擁有固定slot，FOLLOW不被邊界guard擋住 |
| 舊exit-slot重配／width=10／OPEN | active passage由已驗證合法的99-slot footprint持有；普通重配早退。OPEN／10列出現在無passage正常陣形或真正settled後，不強制當作過口 |
| 一次crossed／route被消耗 | `_record_passage_commit` 逐段、逐人更新物理crossed／cleared；完整snapshot與follower descriptor不隨captain route cursor刪除；EXEMPT有初始下游證明 |
| 裸yield／swap／claims | `_find_yield_cell` 無live caller；實際讓位走同一push交易。captain與follower swap的共用begin核對owner、phase、lock及在途狀態；完成原子commit |
| 取消MOVING／WAITING寫入 | `_release_push_transaction` 僅撤銷未開始意圖；MOVING／SWAPPING保留插值、目的claim，完成後釋放。兩取消分支與8組換命令均已執行 |
| 全圖排序／每兵BFS／双window配額 | 結構flood／distance／layout經 `_take_structure_expansion` 每frame256計帳及revision失效；只排序已選99-slot，不排序全圖。局部搜尋單一cursor計帳，無每兵全圖BFS／雙window重扣；trail cache沿既有mutator失效 |

## 8. 歷史失敗、執行邊界與未完成項

本次必驗範圍：沒有未完成、FAIL、TIMEOUT或SKIP。所有最後程式／測試修改後，受影響組合已按當前SHA補驗；資料封存後僅寫驗收文件，未再改runtime。

歷史證據仍可讀，不能將它們誤列當前失敗或冒充最新PASS：

- F01舊版76/99失敗：`20260910_074840_057`；現版三種dt18.7s完成99人。
- 舊多級下降斷言與虛假成功行：`20260910_074720_891`；測試已修正失敗退出與真實事件，現版三種dt及full皆PASS。
- 舊full wall timeout：`20260910_074533_500`；不是永久死鎖證據，現版full正常完成。
- 舊editor Android設定初始化錯誤：`20260910_074831_504`；未改無關全域設定，最終scan `20260910_124748_504` 正常PASS。
- 中途不安全的APPROACH捷徑造成生成12346失敗，已撤回；該seed全部EDGE／FOLLOW／dt組合重新PASS。
- 早期效能報告含2.9s尖峰或較舊源碼，不列入第6節最終效能；原檔與profiling診斷保留。

執行器保存真實exit code、timeout、stdout／stderr／result；唯一保留的已知環境noise為root certificate store讀取警告，與EXIT0並列，未把script/assertion/leak錯誤忽略為noise。缺少schedule工具時依V5使用有界前景驗證，沒有失聯背景程序，未停止使用者另開的Godot視窗。

本頁只聲明Terrain Lab V4／V5契約完成，不聲明正式World–Region–Site、存檔、戰鬥或整個Worldgoing全面通過；也未提交Git。
