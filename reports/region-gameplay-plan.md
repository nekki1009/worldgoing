# Region 畫面下的遊戲進行：規劃 V0.4.5

日期：2026-10-07（Asia/Taipei）。工作樹：`D:\worldgoing`。

狀態：使用者已於 2026-10-07 授權「開始實作至 close」，2026-10-08 再指定「先不要叫人家做，把 Region 計畫先做好」。目前為**Region 本線實作與驗證中，尚未 close**。本線由本聊天自行處理，不新增派給其他聊天或代理的工作。V0.4.5 規格、使用者決定與歷史結果保留；施工候選、正式接入及具名驗收分別記錄。

**2026-10-08 晚間 Region 優先更新：**

- Region 相關候選已沿原 Slot、Travel／Route、人物、原 Site owner、Store 與 UI 準備；這些候選尚未整包接入、解析與實跑，不能由 Source 檔案存在宣稱 R0–R5 完成。
- R5 候選已有原官員觀測、實體旅隊攜帶回報／軍令、真到站收件、接收身分與職權再驗、有效期及送達失敗；目前證明的是候選接線，不是正式 D 或 gameplay PASS。相關流程與原 fixture 見 §7.5。
- 原 **30 個 RG04 案例**仍是 Region 的驗收主索引。科技整包的 174 份 fixture／154 次執行、生態整包及音效整包各有自己的範圍，不能拿其數量代替 Region 的案例結果，也不由 Region 宣告那些整包結案。
- 先依 §9.1 完成 Region 自身的必要接點及驗收；共享 owner 只整合 Region 實際使用的相容接點，保留他人現行變更。尚無本批 Region 完整 close 收據。

**施工進度歷史快照（2026-10-08 凌晨 canonical cohort；以下原結果保留）：**

- **R0：部分已接入，整包未驗收。** 原 Slot 共同時鐘／事件、typed-ref 與資產映射、專用 owner snapshot／Store／Slot selected restore、兩相端點及受控死亡的受限收束已施工。最新編譯及 selected restore 通過；多隊伍完整 graph／跨來源 paid flight／Native 共同步進尚未完成全鏈證明。
- **R1／R1.5／R1-U：程式與整合中，整包未驗收。** 原旅行／路線／在途 Sustain 與共享疲勞有正式接點；完整 body frame、船隻連續原 move、遠端家族控制接續有未合併 staging。最新舊 R1 與 pure Travel 仍 FAIL，已定位 NPC 容器鍵型別、單人疲勞端點錯誤預期，以及 Packed polygon alias 平移污染；修正後須重跑。死亡續接 fixture 亦須從原 down 常數讀取，不能把 get-up 時數當 down。
- **R2：比較入口及測試已接入，准入未完成。** 原精算／混合比較 bridge、S01/S02 時間內容矩陣及真 Slot cold gate 已施工；最新兩個新 fixture 因 Variant 推型錯誤未實際執行。尚無可用的本輪成本／誤差矩陣結果；正式混合 caller 尚未開放。
- **R3-A／R3-B／R4：接點與部分 fixture 已施工，整包未驗收。** 原 NPC 派遣／最小情報／策略入口／battle callback／materialize 接點存在；同刻多 owner 真 caller、公式對照校準、C01–C09 攻城／任意介入／commit-bind 故障重開仍有缺項。新 AI fixture 本輪 parse FAIL，未執行不能計 PASS。
- **R5：未完成。** R3 前置最小 known-intel 接點不代表完整迷霧／官員回報／命令延遲／送達失敗已施工或驗收。
- **30 案及 V01：未完成整份驗收。** 現有局部 PASS 不等於 RG04 全覆蓋或正式 GPU／輸入流程完成；目前沒有完整 close 收據，也不給推估完成百分比。

本輪同版原測試槽結果：compile `20261008_004228_152` PASS、selected restore `20261008_004248_625` PASS、原 Fire/shared point `20261008_004928_942` PASS；controlled death `20261008_004353_368`、pure Travel `20261008_004559_599`、舊 R1 `20261008_004713_385` FAIL；R2 matrix `20261008_004816_792`、R2 formal `20261008_004837_181`、AI `20261008_004908_901` parse FAIL（未執行）；Native provider `20261008_004945_892` FAIL。全部失敗保留為歷史證據；沒有把已修 staging 算成 runtime PASS。下一步先關閉本輪已定位錯誤，整合完整隊伍 caller，再取得 R2 實測與後續全鏈證明。

**V0.4.5（2026-10-07）：** 補全部可移轉資產身分／引用映射、家族隔離、端點區間／待處理效果／bind 三種完成收據、記憶體時間與共同持久 checkpoint、實際戰時需求、合法受擊池的軍階偏好、策略情報與解析真值分工，以及水岸來源／跨 Site 車輛通行一致性。擴充原 29 案並新增 U03 跨 owner 家族接續，共 30 案；V0.4.4 保留為 `region-gameplay-plan.md.bak-20261007-v0.4.4`。

**V0.4.4（2026-10-07）：** 再核原 caller／consumer 後，補齊遠地戰時需求與唯一 journal、端點兩相提交、模式消費 permit、專用快照的讀回／主選單續玩與 bind 完成收據、離場意圖與固定候選分離、原中心節流欠時、在途搬運／本人死亡／遺物清理及共享疲勞；更正全島產表成本。新增 T04／C09，擴充原案例；V0.4.3 保留為 `region-gameplay-plan.md.bak-20261007-v0.4.3`。

**V0.4.3（2026-10-07）：** 補齊畫面外攻城途中玩家抵達的部署、部分輪次、原動作／已付費彈體交接、操作班／彈藥、修理與破壞事件、有效破口／封鎖、原中心占領及離場續行合同；限定全隊失能的玩家場景切換範圍，新增 C02–C08 驗收並清除 D5 尚待答覆的舊字句。V0.4.2 保留為 `region-gameplay-plan.md.bak-20261007-v0.4.2`。

**V0.4.2（2026-10-07）：** 記錄使用者對 §12 的答覆（D5 批准、軍階傷亡與人格撤離成為共同規則、攻城用較複雜公式；在途規則與地類速度由我們訂），並更正海路說明：既有船隊旅程可跨 Site，缺的是 Region 旅隊路線不走海、旅隊不能上船。V0.4.1 保留為 `*.bak-20261007b`。

**V0.4.1 審核修訂（2026-10-07）：** 對照使用者決定、R1 實作與 [REGION_TRAVEL_R1_RESULT.md](../REGION_TRAVEL_R1_RESULT.md)、NPC AI §10A 現行併入文後修正：D1／D2／D3／D7／D8／D9 改列為已決定；補齊 R1 實際出發拒絕條件、自動離住、無海路、旅行 journal 固定倍率、已量測成本與尚未執行的回歸；驗收矩陣加「首次可執行包」對照，並把 V01 與四項回歸列入 R1 補完條件。原 V0.4 保留為 `region-gameplay-plan.md.bak-20261007`。

本版承接使用者提供的 Region v0.3 與 NPC 畫面外補充，取代 v0.3 過時的現況、四邊布林通行表、僅載入時補算、統一失血、撤退映射及 R3／R4 分離順序。原始 v0.3 貼文保留為歷史來源。

責任依 [PROJECT_ARCHITECTURE.md](../PROJECT_ARCHITECTURE.md)、[NPC AI 計畫 §10／§10A](../NPC_AI_IMPLEMENTATION_PLAN.md)、[AI 官職整合第二版](ai-office-duty-integration-v2-plan.md)、[科技樹第二版](tech-tree-v2-draft.md)與 [船艦計畫](../SHIP_ARCHITECTURE_PLAN.md)。畫面外活動與 AI 決策清單放在 [NPC AI 畫面外補充 V0.4.5](npc-ai-offscreen-addendum.md)；本文件定 Region 的時間、旅行、事件、交接與驗收接點。NPC AI 主文件由原討論串維護，本次提供同步稿，不改其其他主線。

## 0. 定案、提案與版本優先級

### 0.1 已確認的要求

- **D4：** 玩家是隊長才能整隊出發；非隊長出發是沿原規則脫隊單走，其他人留在來源 Site。受控 Army row 非隊長尚有實作缺口，不能因已有 Actor 路徑就宣稱 D4 全部完成。
- **D6：** 畫面外活動的清單及 AI 決策歸 NPC AI 計畫。本版補充稿供其 §10A 同步，Region 不另維護一份不同的 AI 清單。
- **D10：** NPC 會移動、會互相打仗；NPC 之間的公式戰鬥必須持續遊戲時間，玩家可以中途趕去參戰。玩家所在 Site、玩家旅隊的遭遇與事件必須截停並在現場處理，不提供略過或公式代打。
- 規劃審核當時的授權是補缺口、修訂計畫；後續「開始實作至 close」依本版 Region 規格執行。新增玩法、數值或後端規則仍分別記錄批准、候選、實作與驗收狀態，不由文件或候選存在推定完成。

### 0.2 承接的施工建議與待定

- **D1／D2／D3／D7／D8／D9 已由使用者決定照 v0.3 建議：** 看圖暫停、旅行時流動、Region 預設每現實秒 600 遊戲秒並沿原 0.5／1／2／4 速度鍵、沿原出發守衛（戰鬥中／附近敵人／有人倒地不能出發）、路線通行與實際 Site 地形一致、經過的 Site 不展開也不建立存檔。R1 已實作其基本行為（見 §2），但數值細節（如地類速度係數）仍屬施工參數。
- **D5 已批准（2026-10-07）：** 冷 Site 民生採「長區間公式前段＋原 shared step 精算後段」。仍須通過 §4 的支援範圍、水印、對照誤差與成本門檻才能接到正式 Slot；不支援的 owner 繼續精算或停在合法邊界。
- 「最後兩遊戲小時精算」是待測參數，不是等待時間已受保證的結論。公式係數、容許誤差、支援內容與性能門檻須在各施工包凍結並保留測量證據。
- 本版新增的事件排序、資料責任與恢復流程是施工規格提案。人格撤離與軍階傷亡順序沿 §12 的明示共同規則授權；普通模式失血、被動 HP 回復及任意戰鬥中手動存檔沒有因本次修訂獲准。§8 的專用交接快照須接原 owner 准入，不是關閉現有 BUSY 守衛。

- **§12 已全部答覆（2026-10-07）**，見 §12。目前沒有待決的編號決定；數值仍屬施工初值，須在各包校準。

### 0.3 文件優先級

1. 使用者直接要求及目前原始碼／具名驗收邊界。
2. 本版明示的 Region 契約與配套補充 V0.4.5，取代舊版相同範圍的衝突敘述。
3. AI 官職整合第二版對其已明示修訂範圍優先；NPC AI 的戰術 A1、Crowd A2、B1 數值及驗收仍沿原主線。
4. NPC AI §10A 原併入文與 §10A.5 是歷史基線：七個非軍事軸已於職位附錄 D 批准並有讀取點，不能再列為全部待批准；「一律 25 HP」「risk 直接管撤退」亦須按本版核對結果修正。

## 1. 玩家會看到的流程

看台灣地圖時暫停。合法出發後，原人物與整隊／單人轉成 Region 旅隊，時間才流動；途中可以停、改路與保存已完成進度。抵達、遭遇、手動暫停或交接待處理時停止自動推進。

NPC 使用相同旅隊資料格式，在同一世界時間移動；其派遣由原職位／AI 入口決定。遠方 NPC 戰鬥逐段結算，大地圖顯示「交戰中」及按可知情報產生的估計，不保證固定幾小時或幾天。玩家進場前凍結時間與戰鬥結果，驗證原人物／物品並接回正式 Site。

最小可玩切片：先關閉現有 R1 的人物／物品守恆、有效路線及阻塞恢復缺口，再加入在途消耗，最後加入一種最小 NPC 派遣與持續戰鬥。R3 首次開放就包含玩家不可略過的遭遇。完整巡邏、增援、運糧、政治活動與情報延遲是後續包，不一次堆入首包。

## 2. 本次原始碼核對的現況

### 2.1 已有程式路徑，尚不能由本次推定驗收通過

- 玩家陸路旅行：`SiteController` 功能入口 → `RegionTravelSite.depart` → `RegionSaveSlot.begin_region_travel` → `RegionTravel.extract` → `RegionTravelPanel` → `commit_region_arrival` → 原 Site 綁定／保存。
- 原人物、隊伍、cart／wagon、實物、供養帳與火攻命令保存在原 Slot commit 引用的 party 文件；來源 Site 抽離，不同時留第二份人物。
- Region 預設每現實秒 600 遊戲秒，速度 0.5／1／2／4。現有 publisher 以原 peace/fire journal 的 **8 遊戲秒**完整步前進，抵達量化誤差小於一個步長；不能寫成已能精確停在任意秒數。
- 途中 checkpoint、暫停、改路及主選單繼續已有路徑；已訪問目的地仍用原 `open_site`／`advance_cold_site`／`replay_site_to` 精算到目標。
- 路線已由 `RegionRoute.table_from_terrain` 沿 `TerrainData.can_step` 計算邊界 offset 與 Site 內連通分量，以 component-aware 搜尋跨 Site；不是四個布林值。表為 lazy build/cache（記憶體＋`user://region_lab/route_tables`），版本 pin 包含地理、資源、坡口與表版本。**未做全島預算表**：沿 R1 報告每 Site 約 0.25 秒的單站量測，90 萬張串行乘算為 225,000 秒，即約 **62.5 小時**，尚未含 I/O；舊報告的 6–8 小時不是此串行估算結果。全島實測、可用並行度與離線工具成本待測，不能由單站量測宣稱完成時間。搜尋為加權 A*（路線可長於最短 1.4 倍以內），在背景執行緒。
- 速度：步行 4 km/h、cart 3.5、wagon 3，取最慢成員；地形係數只依 Site 內一級坡比例（1–3 倍），**尚未有地類係數**。
- 旅行時間以 journal **固定 scale 4、每步 1/30 action 秒（8 遊戲秒）**發布，與玩家選的地圖速度鍵無關；冷 Site 之後以此步長精算。
- **R1 歷史證據（沿上述結果報告，本輪未重跑）：** `scripts/tests/region_travel_test.gd` headless PASS（隊長整隊、非隊長 Actor 單走、守恆、三種拒絕、海峽繞行、玉山跨界以原 `boundary_surfaces_can_step`／`path_between` 重證、途中重開、時鐘相等、已訪問 Site 冷補算）；GPU 截圖 `.visual_captures/region_travel/r1_20261007c/travel_map.png`。**報告仍列未執行：** `region_lab_contract_test`、`region_lab_preview_contract_test`、`site_ship_journey_test`、`main_menu_flow_test` 四項回歸，以及遊戲內手動完整流程；本輪文件審核沒有補做這些驗證。
- 已量測：玉山 900 m 路線首次約 2 秒（5–6 次建表）、快取後約 0.5 ms；返回落後約 57 遊戲分鐘的已訪問 Site，原精算約 6.2 秒（26 幀）。長途返程等待隨落後時間線性增加，是 §4.4 的起點數據，不是上限保證。
- 官職 owner `SiteOffices` 與部分 `SiteDutyAI` 已接線。十軸人格已有各自批准的讀取點；每日冷地版與跨 Site 派遣尚未因此成立。

### 2.2 現有 R1 的明確限制

- Crowd 不准入；普通 Actor 非隊長可沿原退隊單走，受控 Army row 非隊長目前拒絕。
- cart／wagon 可隨陸路旅隊；騎乘須下馬，屬本隊的船／攻城器須先脫離本隊。
- **海路現況：** 遊戲已有船隊旅程（`SiteController.begin_ship_journey` → `RegionSaveSlot.prepare_ship_transfer`／`checkpoint_ship_transfer`／`commit_ship_transfer`，`site_ship_journey_test.gd`）：在 Site 畫面的「世界地圖與船隊旅行」把全隊和共糧裝上船，船隊在固定地圖上真的航到另一張 Site，旅途中時間、糧食、疲勞照常。限制是每次只能直航到東西南北**相鄰**的 Site，且從 Site 畫面發動、不經 Region 地圖。**R1 缺的是：** Region 旅隊的路線只走陸地（海與內陸水視為不可通行）、旅隊不能在海岸上船／下船、Region 地圖上不能規劃多段航線。這歸 §6.4 的 R1.5-S 補上。
- 拒絕出發的實際條件：Site 在戰鬥（`combat_left`>0）或 24 格內有可行動敵人；有人倒地、被俘、投降中；正在救助／攻擊／移動／作業；隊伍不在守位、仍有救助或駐營；隊內有陣亡者或已退隊者（R1 不拆隊伍容器）；未停穩車輛；隊伍共糧仍存放在據點（未裝車或未由隊員攜帶）；拘押／押送；國別職務或軍團仍連到留下的人；任何已登記 Site 的火場仍在燃燒（一律阻擋）。不得繞過原 guard。
- 出發者若有住處會**自動離住**（同原「離住」），結果訊息會提示。
- 到站時車輛停在入口附近並解除駕駛綁定（`operator_id`=0），需重新指派。
- 出發地的家族名冊把出發者標為 `travel:<token>`；抵達只更新旅隊攜帶與目的地的名冊，出發地名冊要等該 Site 下次載入／交接才會同步。
- **旅途 meals／hunger／fatigue 暫時凍結，到站重定位餐份時鐘。** 不是 AI 冷 Site 清單已處理的項目；NPC 補給與公式戰鬥開放前須完成第 5 節。
- Slot 現在只有一個玩家 `journey`；`begin_region_travel` 清空活動 Site，`advance_region_travel` 要求沒有活動 Site。多 NPC 不能逐支照用這個生命週期。
- route table 未含已訪問 Site 的玩家造牆／整地差量，也未保證所有車輛 footprint 可過；目的地實際配置仍可能失敗。
- 已到站的面板目前優先重試原入口，尚無完整 `arrival_blocked` 改入口／返程流程。

### 2.3 目前缺少的接點

多旅隊登記及事件排程、事件前冷 owner 結算、公式／現場模式水印、在途 upkeep、冷事件共同提交、持續戰鬥保存、玩家介入、有效地形路線覆核、到站失敗恢復，以及派遣／最小情報入口，均須按後述分包實作。

V0.4.4 再核的原入口限制：`begin_active_step` 目前僅由 cold Fire 索引取得遠地戰時需求；Region 旅行 preview 固定 tactical=0，而 cold replay 遇攻城會強制戰時，兩者不能直接共用換算。原 shared step 內 work／命中／P0 可能在發布時間之前已提交端點效果；普通 Store 讀回、`open_site` 冷補算與 boot 保存尚未識別專用熱快照。`bind` 先設 terrain 指標，後續 restore 仍可失敗；離場 `_region_pending` 又會凍結 elapsed。這些都是下述 R0／交接包要改的現有接點，不能當作 V0.4.3 已實作的能力。

## 3. R0：時間、身分與事件契約

### 3.1 唯一時間與既有 owner

- 同一 Slot 只有 `logical_game_seconds`。活動 Site 完成步與 Region 旅行發布互斥；NPC 旅隊、組織與戰鬥只消費同一段時間，不自行加鐘。
- 多旅隊登記、battle 引用與已處理事件沿原 `RegionSaveSlot` generation／commit marker 擴充；沿 `RegionTravel` 格式承接人物，不新增另一個 World、人物、庫存、旅行或保存權威。
- 只排程已存在的旅隊、已登記組織、受影響的保存 Site 與事件；不能每輪掃描約 90 萬張地理 Site。未存在的人口／生產不能憑查路補造。
- 地圖查看、手動暫停與首次玩家 `materializing`／`arrival_blocked` 時不發布新區間；已是 live 的場內 NPC 候入隊列依 §8.2 處理，不因此凍結玩家。新事件不能因玩家仍在 Site 就停止遠方 NPC 時間。

### 3.2 身分與旅隊／戰鬥資料責任

- 原 NPC 計畫 §10 的永久人物／組織身分是多 NPC 前置。現地 `person_id` 或 `PersonRef {site_id, person_id}` 不等於已保證全球永久唯一；R0 須核定原 namespace／分配與移交對照，驗證跨 Site 同號及返回來源反例。
- 沿 AI 官職整合第二版 §4：目前授權引用隨原人物移交映射更新；捕獲 episode、事件發生時的責任組織與歷史引用／去重號保留，不隨目前位置改寫。組織同號重建不能繼承舊 lineage。
- 旅隊沿原 party 保存完整原人／隊／車輛／實物／供養閉包，新增的多旅隊位置、路段、controller、任務與時間進度由 Slot 引用；原人物只存在 Site 或 party 之一。
- battle 保存穩定 battle ID、地點／接敵範圍、參與 owner 引用、開始／最後完成時間、下一輪時間、輪次序號、公式規則版本、模式及必要 RNG seed／counter；攻城另保存 §8.2 的角色／部署引用、封鎖與部分輪次端點。原人物 cell、器具 pose／crew、建物部件及 work/action 始終由原 owner 持有；battle 不保存第二份可修改真人名冊、位置、HP、物資或城防。
- 新欄位版本須同時接入原 capture／normalize／validate／restore、SiteStore、Slot、party 及到站候選；缺少必要 schema／來源時整份拒絕，不能只恢復其中一半。

**完整資產身分：** R0 的 namespace／移交合同不限人物／組織，亦涵蓋 team、vehicle、實物 item、ground loot／remains 容器及其 holder。穩定引用以原 Slot／原 owner 核定的「型別＋來源 namespace＋建立 lineage／配置序號」辨識同一物；generation 是狀態版本，不當永久身分。Slot 的定位／移交索引只指向原 owner，不持有第二份可修改人／物資料。

既有局部 ID 保留原 owner 格式；跨 Site 碰號由原分配器預留目的地未用 ID，將完整原 typed-ref → 目的局部 ID 映射與 transfer token／目標 generation 共同保存。三個來源各有 item/vehicle/remains `1` 是三件真實資產；同一穩定引用已被另一 owner 持有才是重複所有權。retry／重開復用已核定映射，不重新配置或覆蓋原物。返回來源也按現有映射／可用號處理，不承諾復用已被占用的舊局部號。

現在有效的 crew／operator／embarked、隊伍／軍令、裝備／cargo／供養位置、患者／搬運、地面遺物、family／office、work／target／compound／reservation 與未完 flight 引用逐項 remap；source token、歷史事件／付款收據及已命中去重號保留原穩定引用／責任 lineage，不能因換了局部 ID 失去已付款／已處理證明。item definition 是版本化定義，不是實物：同鍵同版本同內容才可共用，異內容須原版本／定義映射或整份拒絕，不能取第一份覆寫。映射 schema 必須接 capture／validate／restore、Store、Slot、陸／船到站與專用快照全鏈；到站的 ID_CONFLICT 只作真正衝突／不支援狀態的守衛，不作合法跨來源碰號的永久解法。

### 3.3 先找最早事件，再推進

公式戰鬥的 10 遊戲分鐘是結算頻率，不是遭遇偵測頻率。每次推進先找下一個路段到達／離開、接敵、玩家事件、增援、AI 評估、戰鬥輪次，以及會改變規則輸入的缺糧、死亡、醒來、完工等端點。

在事件時間 `t` 讀守軍、倉庫、工作、職位或戰力前，先把受影響 Site／party 的區間進度結算至 `t`；恰在 `t` 的離散結果尚須依 §3.4 排序，不能因某 consumer 先跑就提前提交。同一事件讀取其排序之前已合法提交的狀態；不得用戰後人口倒算戰前多天生產。

跨多張 Site 的大步以路段時間區間檢查，同邊反向相遇、追上、同刻抵達均不能只比幀末座標。同 Site 是遭遇候選；互不連通且無原合法接敵能力的隊伍不能強行合併成一場戰鬥。

### 3.4 同刻排序與步長

本版施工建議的穩定順序如下；事件同序再按原組織／party／battle ID 與保存的事件序號排序，不依容器遍歷順序：

1. **第一相：** 原 owner 積分半開區間 `[前端點, t)`，可保存到 `t` 的 work／action／生命／供養進度；達門檻、發射／命中、修理完成、死亡／醒來與陷落等恰在 `t` 的離散效果先進原 owner 端點佇列，不在積分內套結果。各子系統的同刻生命規則沿原後端，事件 ID／排序持久化。
2. **第二相先判玩家屏障：** 收集同刻到達／接敵、受控本人死亡及其他必須現場處理的玩家事件。若涉及玩家，先凍結並準備現場；`t` 的尚未提交攻城／生命／work／P0 點效果留在原佇列，由成功接管的 live consumer 依同一順序接續，不能先套公式輪次。已提交歷史指 `t` 之前的合法結果，不含為搶在交接前而先跑的同刻效果。同刻多事件依保存序號排隊，先解一個玩家屏障而不丟其餘事件；原本人死亡出口只在必要死亡交易完成後執行。
3. 無玩家屏障時，沿凍結的原子系統排序提交 `t` 的生命／供養／工作與攻擊點效果，完成必要死亡清理及權限失效；再處理純 NPC 到達、加入／離開與增援。新參與者只承擔實際加入後的區間，不追扣此前戰損。
4. 對仍為純 NPC 的 battle 結算應完成輪次，接續原生命／士氣／拘押／陷落出口。
5. 更新可知情報及到點的派遣／職責評估；新的派遣從這次事件時間開始。
6. 原 Slot 依 §3.7 一次接受完整區間／事件收據；記憶體 runtime 完成不等於持久 commit。合法共同 checkpoint 才保存全體受影響 owner；玩家端點屏障依 §3.8 的專用合同提交，不以本版批准任意手動戰鬥保存。

現有 8 秒步長只是 R1 基線。**R3 採下一個最早事件端點；共同步 caller 在原人／work／供養／移動改動前裁定 action／game delta，所有必要 consumer 同時支援「積分進度／端點效果」兩相。** 依排序完成或合法入原待處理佇列後，原 Slot 才一次接受 interval receipt／世界時間／水印／journal；未提交的點效果另有完成狀態，不能用整步完成 stamp 冒充。持久化依 §3.7–3.8；不先跑完整 Site 步再裁秒，不讓修理／命中／P0 搶先完成。原承諾移動與 Reservation Grid 原子性保留；R0 驗裁步、延後提交、恢復及三種收據，任一不成立則保持最後完整狀態、阻擋 R3。

「餘量」分開處理：已接受區間的合法未完成尾段記其 action／game 端點、scale、tactical 秒數及來源／模式 revision；`RegionTravelPanel._accumulated` 的現實幀／倍率執行預算不是世界欠時。遭遇、暫停、切場或 owner／模式改變後重驗事件與原步合同，不能把未開始的高倍速 Region 預算自動補進 Site。尾段恢復亦不得越過新事件或沿用失效換算。

戰鬥完整輪次與最後不足一輪的區間須使用實際經過時間；玩家於 `t` 介入時只能處理 `t` 之前純 NPC 已完成的區間，不預支下一輪、不對玩家套公式。輪次起算／部分區間規則在公式版本中凍結。攻城另保存實際 `Δgame / Δaction`、當前攻擊／作業 stage 與 elapsed、下一個發射／命中／破口／完工／占領到點；部分輪次不能只按十分鐘比例攤平傷害或丟掉小數進度。例：玩家在輪次第四分鐘抵達，先到該事件端點交接，剩餘六分鐘不提前結算。

### 3.5 模式消費 permit

沿原 `RegionSaveSlot.begin_active_step / record_active_step` 與 shared-step caller 擴充同一 permit。**任何人物、work、物資或戰鬥改動前**，核定 owner／來源 generation、runtime revision、已完成 action／game 邊界、模式及其 revision、原 consumer／backend schema 與該模式的啟用收據。區間完成發布時再驗同一 permit 的來源及本段 receipt／預期終態 revision；本段合法改動不誤當來源失效，外部來源變更則整份拒絕，不發布半份進度。

- `live` 只准持 §8.3 完整現場 bind 收據的原現場 consumer；`formula_active` 需原 owner／規則版本驗證與公式 consumer 啟用收據；`cold_exact` 需原快照驗證／restore 與原 replay consumer 啟用收據。三者都驗來源／端點／backend；冷模式不要求玩家現場 bind 或 controlled-input 收據。
- `materializing / dematerializing` 及 `committed-unbound` 只准驗證／capture／restore／bind／恢復交易，不准任一模擬 consumer 推進。`dematerializing` 從 §8.4 真正凍結候選才開始，離場意圖期間仍是 live。
- 模式錯誤、過期來源、缺少必要後端能力或該模式啟用收據未完成，保持最後完整狀態與恢復入口；不降級普通載入、不清狀態、不改回 formula，也不以檔案讀成功代替消費許可。

恰在目前時間的待提交點效果須有原 owner 的**零世界時間**事件消費入口，使用同一來源／模式及事件 receipt，只提交尚未完成效果。不能為觸發 shared step 的正 elapsed 守衛而製造假正 delta、再積分一次或額外推鐘。達 work 門檻而效果待處理的 job 須由專用 schema 保存 progress＋queued event；原普通 job 驗證拒絕 `progress >= work` 的邊界不能靠壓回 progress 或先完工繞過。

### 3.6 遠地戰時需求與唯一 journal

在原 Slot 戰時需求索引／permit 中登記活動 combat／grace、cold Fire 與已准入 cold battle／siege 的**實際 tactical 需求區間**，含來源 generation／runtime revision、起訖與模式。重用同一原 active／威脅／grace／有效攻擊承諾／飛行條件，battle ID 或圍城 phase 尚存不等於全段戰時；純建具、修理、HOLD、無彈等待若無原威脅條件仍沿原和平分類。開始攻擊、彈盡／停止、最後飛行與 grace 收束均為端點，索引重核後才 preview。兩 publisher 共同取各 Site 需求時間範圍的聯集／最大值，不把多 Site 秒數相加；缺少必要來源不悄悄視為和平，也不因長期圍城而永久改全世界速率。

`Δaction` 指原 action cursor 的實際增量，未再乘玩家速度；對已裁開、scale 固定的區間，`Δgame = [Δtactical + 60 × (Δaction − Δtactical)] × scale`。各必要 consumer 使用同一原 Slot journal／preview 與分類；game delta 已含 scale，不再乘一次。最早 game 事件先用未提交 preview 求合法 action 端點，再積分／提交，最後一次發布。cold 公式／精算不能自行挑另一種和平／戰時計算、另設冷 action 鐘或事後改寫已發布 journal。既有 R1 固定 8 game 秒／peace 路徑是歷史能力，遠地戰鬥啟用前先通過 T04；多場戰鬥只讓一段共同時間前進一次。

### 3.7 記憶體進度與共同持久 checkpoint

沿原 Slot 區分 **volatile runtime revision** 與 durable generation：完整區間由原 Slot 一次接受所有必要 owner 的 interval／event receipts，世界 action／game／journal 只前進一次；持久 marker 不逐 tick 更新。已接受的冷結果保留在其原 owner 與同一 runtime revision，後續事件讀最新合法狀態，不反覆讀舊 durable 檔再 cold replay。尚未完成的候選不給 AI 讀，已完整接受的結果不因 checkpoint 尚未落盤而再扣一次。

活動 Site 普通保存 BUSY 時，沿原 guard 繼續完整 live 模擬與合法控制，延期**整個共同 checkpoint**；不能先 `_publish` 遠地結果／新世界時間卻仍引用活動 Site 的舊快照，也不能為等保存而停住收束 BUSY 所需的原動作時間。合法保存點固定新時間／runtime revision，capture 活動 owner＋未持久 epoch 的全部受影響 Site／party／battle／事件收據與完整 journal，驗證後一次更新原 marker。任何來源變更就捨棄過期候選重新 capture；保存／commit 失敗保留舊 durable marker 和完整 volatile 結果，不回滾半邊、不重套冷結果。普通手動保存仍可回 BUSY。

原 Slot 的 affected／待 checkpoint 索引不因熄火、戰結束、退出 active 索引或候選快取淘汰而丟掉未持久 owner 結果；保留至共同提交完成，取代先逐筆 `_flush_cold_fire_candidates` 再保存 active 的順序。journal 裁剪以可恢復原快照／完成收據下界為證，不能只看較高 volatile 水印。此索引只是原保存生命週期，不新增模擬／資料權威。

重開從最高完整 durable commit 一起恢復 clock、active、cold、party／battle 與事件；未持久 epoch 不獨留某方結果。只有合法保存的 input／event 證據才准確定重播，無證據不重造玩家微觀戰鬥。一般 checkpoint 延期／失敗不等於已保存；不可略過的玩家事件另需下節專用屏障 checkpoint，不能借普通 BUSY 永遠延後玩家介入。

### 3.8 玩家端點的三種完成收據

**interval-complete、effects-complete、bind-complete 是三件事。** 玩家事件在 `t` 截停：所有必要 owner 已完成 `[前端點,t)` 並已將 `t` 點效果加入原佇列後，由原 Slot 以專用用途提交 `interval-complete / effects-pending` 屏障 generation。world／action／game journal、各原水印到 `t`，原 owner 狀態、未消費點效果／事件序號、玩家屏障及必要映射在**同一完整 commit**；不能只提交時鐘或 ahead-of-world 快照。這可與成功 materialize 合為一次 commit；容量／入場失敗時仍保存不需插人的完整來源屏障，重開先恢復它。

屏障候選涵蓋 §3.7 同一 epoch 的全部必要 owner，含原 active／在途玩家；使用已准入原內部 checkpoint schema，普通保存 BUSY 不阻擋已支援的原交接，但也不藉此開放任意手動保存。寫入／commit 失敗只保留完整 volatile 來源及原 durable marker，不宣稱 `t` 已持久化、不套半份。已成功提交屏障重開必回同一 `t`／佇列；未成功時，僅最後完整 commit 能證明的 input／event 可重建 `t`，否則整體回最後完整保存時間，不拼孤立的新檔／水印或捏造未保存玩家行為。R3 准入須正向通過屏障保存／恢復；磁碟失敗的保存不能冒稱跨重開成功。

`bind-complete` 僅給相應 live **零世界時間事件 permit** 與合法恢復 UI；原 owner 按保存順序消費當刻效果／receipt，不再加正 delta journal、不再積分同段。`t` 的必要效果和同刻屏障尚未處理時，不准新戰術輸入／正世界步；家族選擇／合法恢復按鈕不能一併鎖死。未來點事件不必全清才能續走。

若當刻效果已完成、僅待原死亡 down 動畫／已承諾步的未來合法收束，明確進入原 live 的受限收束狀態：依原 journal／最早事件推進必要完整 owner 區間，保留承諾、不接受新的玩家戰術動作，也不對玩家公式代打；不能把需正 elapsed 的死亡清理永遠卡在零時間。必要死亡交易完成後才接原 Family 選擇；等待選擇／容量／失敗 bind 的屏障不推鐘。`effects-complete`／控制接續完成才按原條件取得正常正步／輸入許可。事件 receipt／mode 更新仍經原 Slot，已持久 `t` 不被第二次推進。

## 4. R0／R2：冷 owner 結算與精度切換

### 4.1 觸發與來源

冷結算不只在玩家載入時觸發。派遣、供應、接敵、增援、公式輪次、陷落、玩家載入等事件，都須先取得與事件時間一致的受影響 owner。

每個候選固定來源 generation／hash 與目標時間。補算 `PENDING` 只能續同一來源與目標；源版本已改則重新準備，不能把兩份狀態拼起來。未完成前不發布完成時間或讓後續 AI 讀半份結果。

### 4.2 混合路徑的准入

- D5 已批准；但在 S01／S02 通過前，混合路徑只在隔離比較中執行，不寫回正式 Slot。
- 短區間沿原步進；長區間公式前段加精算後段。支援範圍由 AI 補充稿定，不能把所有 owner 都當成固定日產率。
- 公式遇糧食耗盡、死亡、工人／職位改變、完工、服務停效／恢復等端點必須分段並重取速率。
- 公式每段記來源版本、區間、模式與已消費子系統。精算後段不再執行已處理的戰鬥、供養、死傷、被俘、政治或陷落事件。
- 原精算會進入完整 `_advance_combat`；必須以原 owner 的模式守衛及完成紀錄銜接，不能只更新 `last_settled_game_seconds`。

### 4.3 水印、火場與不支援內容

保留原 Fire 的 `epoch / sequence / action_seconds / game_seconds`、連續 journal、owner／transport 快照及 Site／供養水印一致性。公式接點必須有可驗證的已完成邊界，不刪 journal、不重設 epoch、不偽造已結算水印。

尚未有摘要合同的火場、投射物、攻城動作、救援、押送與移動／reservation，由原 owner 精算或停在合法待處理邊界。若內容超出支援範圍，明示原因與可續跑進度；不能清空動作換取快進。

原 AI 官職整合第二版不允許憑經過天數補造未執行的政治事件。時間已前進不表示投票、不滿、接任或研究已模擬；這些須有各原 owner 的區間及事件證據才准入。保留已證明的觀察／爭奪持續秒數及最後區間端點，未知離線區間不增加也不清零，返回合法 active 區間後續行。`duty_ai=false` 只停官員主動命令，不凍結已有時間證據的日社會狀態、預兆、本人意向及指定繼承／永久空缺接任。

冷補算、混合尾段與回冷都先取得 §3.5 的對應消費 permit，並按 §3.6 的共同 journal／前向戰時需求接續；專用交接快照另走 §8.3 的 mode-aware 讀回路徑，不能先套普通 `open_site` 冷補算，再看 battle mode。

### 4.4 等待成本

量測 2 小時、1 天、1 週及 1 月，在無居民、聚落、100 人以上、原保存最大合法內容與不支援動作下的精算／混合成本。記來源、內容、人數、步數、CPU 預算、等待與結果誤差。

精算尾段長度與每幀 CPU 預算是不同參數。凍結可支援內容及性能門檻後才可宣稱等待上限；超預算時維持凍結、顯示進度、可取消未提交候選或續跑。未完成不得把玩法時間假推至目標。

## 5. R1-U：在途消耗與恢復

R1 的凍結需求是歷史切片限制，需獨立施工包升級，不能由冷 Site 生產清單代替。

- party 保存原供養帳、原共享隊伍疲勞與各人物生命狀態，另記已完成的在途結算端點；每段只消費一次。
- 餐份覆蓋、車上／個人口糧、開封零頭、hunger、士氣、缺糧與事件去重沿原 `SiteSustain`，不另建「人數乘天數」糧帳。
- 行走／休息／停留的疲勞與傷勢沿該後端已批准規則。現有一般 HP 被動回復與普通模式 KO 失血不能憑本版新增。
- 中途停、改路、出入 Site、返回、保存及重開均不能延長已吃餐份、抹除供養欠時或重扣消耗。抵達不再以舊 R1 `rebase_clocks` 代替完整 upkeep。
- 缺糧、失能、死亡或事件發生時截斷路段，沿 §3.4 排序、原生命／物品清理及下述旅行處置；已消耗內容與人物位置共同提交。死亡資格立即失效，物品清理在原合法 action 端點完成，不能延到下次到站。
- 首包仍保留倒地／拘押等出發限制。

**在途規則（2026-10-07 使用者授權由我們訂；施工初值，沿既有後端）：**

| 項目 | 規則 |
| --- | --- |
| 行進疲勞 | 步行者每遊戲小時 effort 初值為原 `WORK_RATE`（+10）；沿原共享池把各合法角色 effort 加總、除原 pool count，只 advance 一次，不能每人再對整池加 +10。原 slowdown 是時長因子：`v = v_base / (1 + slowdown)`，0–0.30 對應最低約 76.9% 原速，不能誤作速度 ×0.70。 |
| 紮營 | 共享疲勞達原 `WORK_REST_AT`（80）停止距離推進；合法安全休息過原 `REST_DELAY`（30 秒）後才沿原 `RECOVERY_RATE`（每遊戲小時 −20）恢復，降至 `WORK_RESUME_AT`（50）重驗供養／運送／威脅後續行。玩家可提早停留，但遇敵、候入封鎖或 active 承諾作業不自動算 safe_rest。 |
| 糧食 | 每段沿原 `SiteSustain.advance_to` 從旅隊實際攜帶的共糧位置（車上、隊員身上）與個人餐份扣除；照原挨餓、士氣、缺糧傷害規則。不再到站時平移餐份時鐘。 |
| 傷勢 | HP 不在路上自動回復（現有後端沒有一般被動回 HP，和 Site 內一致）；KO 照原倒數醒來；包紮／救助沿原規則，紮營時才可進行。 |
| 途中倒地 | 先按下述原車輛載人 schema／容量預檢，否則每名患者指定兩名互斥、可行動的抬運者；成功徒步抬運時整隊基礎步速乘 0.5 一次。有患者未分配、貨載／駕駛或人手不足，立即停距離、保留 party 並續供養／生命，不把「尚有清醒者」當能繼續走。 |
| 途中死亡 | 死者立即失去新行動／職位／運送資格；保留原下倒動畫／承諾步，停在下一個合法原 action 端點收束後完成原死亡交易。個人裝備、cargo、開封口糧、拘押／住宅與唯一 `remains_id / loot_settled` 經原出口處理。旅隊承接原遺體／remains 與 holder 引用；下次落地只移交／配置已完成結果，不再清理或重掉落一次。未完成死亡不得走普通安全保存。 |
| 全隊不能行動 | 立即停止該旅隊距離推進。受控玩家旅隊依 §3 最早事件／同刻排序展開所在 Site，保留原人物、遺物及屏障；本人死亡另依下述原家族接續，不必等全隊失能。NPC 旅隊只更新遠地原 party／生命／物品與任務，必要時沿原冷 Site 交易，不改玩家 active_site_id／journey 或切走玩家攻城現場。 |

**搬運准入與初值：** cart／wagon 現有 capacity=100／300 是原物品容量，沒有已實作的載人席位。本版在原車輛 schema 增加患者引用、承載／解除端點與容量預留：cart 最多 1 名、wagon 最多 2 名患者，每名預留 **50 原容量點**（施工單位，非公斤；從原貨物可用容量扣除）。原貨載加預留不得超容量，並驗原駕駛、合法 pose／通路與患者移交；不另建載人庫存。未完成此 schema 的包明示車載患者不准入，只用可行的二人抬運或停留，不能把舊 capacity 直接解作座位。

患者與每名搬運者均以原人物引用保存；搬運者不能同時抬另一人、當車輛 operator、參與 crew 或 work。步行／抬運者 effort 初值均為 +10／遊戲小時，載運中的 KO 患者無步行 effort，車輛 operator 使用原車輛角色 effort；其他原 pool 成員依原政策保留分母，不以本版重分配共享池。KO 醒來、上下車／解除抬運、少員、貨載與駕駛改變均為獨立端點，重驗容量與角色後更新速度。安全休息只在原 no-threat／無 active 作業守衛成立時恢復；停止距離不代表所有成員已在休息。

**速度與剩餘路程：** 每段取仍實際步行成員的疲勞修正速度與實際車速的最小值，再套地類／坡度及單次抬運係數；按該段合法角色 effort 積分共享疲勞，於 slowdown 門檻、80／50、rest_delay、生命／運送／供養事件截段重取速度。保存已完成距離與同一結算端點，重算 ETA，不把出發速度固定用到終點。

**受控本人死亡：** 本人 HP 死亡即為最早玩家事件，其他隊員尚可行動亦不得帶著已死玩家繼續旅行。先由原死亡出口安全提交，再沿 `SiteFamilyContinuity.death_tick / choose` 的既有家族／可接續人物規則辦理；原人物查找須能解析 Slot party、battle 與待處理轉場，不限已保存 Site。沒有合法接續者就沿原失敗／結束入口；不造繼承人、不復活死者。KO／被俘不等於死亡，不自動換人；軍隊隊長繼任不等於玩家控制接任。控制轉換與原名冊／輸入／Slot／journey／battle 事件屏障共同重驗，不能保留舊 controlled ID 或把未解的同刻遭遇丟掉。

**死亡控制接續的同代交易：** 原 `SiteFamilyContinuity.choose / archive_current / control_selected`、controller 歸檔／控制 callback 也要接 §3.8 已准入的內部共同 checkpoint。死者必要交易完成後，選同一家族原已登記在世家人；原資格不被改成必須成年／清醒／未被俘，接續不使未成年長大、不解拘押、不轉送死者財物。目標以穩定人物引用讀其當刻真正 Site／party／battle owner，先到同一事件時間並重驗資格，不傳送到舊名冊位置。

跨 owner 時，原 Slot 共同保存舊場完整人／物／殘骸／未完 action／battle 的合法 cold_exact／formula 後繼、目標原 owner／控制名冊／family／必要 offices 及全部受影響 epoch；同 Site 只改合法控制引用，不搬人。目標在 party 時只承接該原旅隊與未解玩家事件，不複製其人至第二個 Site；目標在 battle 時按同一不可略過現場入口，不能繼承後繼續讓受控者被公式代打。所有 capture／readback／restore／bind、映射與 receipt 仍沿 §8，全程不要求一次 ordinary `archive_current → save_to` 成功，也不要求舊攻城／flight 全結束才可選外地家人。這是死亡後原控制出口的專用用途，非在世者主動撤離／出發守衛豁免；未准入船／Crowd／必要 schema 仍整份拒絕，不能借接續越過後端範圍。

commit 前失敗保持原完整 owner／死亡屏障；後只讀已提交目標與舊場後繼，不二次歸檔／變控制。成功 bind 並處理同刻效果才開原合法輸入，舊場照原後繼續行。選擇 UI 等待本身不推鐘；若保留原「等待安全歸檔」按鈕，必須明示退出 UI、重新取得原受限 live permit 讓合法原動作續行，不新戰術輸入、不永久重試舊 candidate。正常支援內容應能正向專用交接，不以這個等待選項代替整場攻城中的接續准入。

**死亡接點：** 死亡資格失效、動畫／承諾步收束及遺物交易分成可追蹤的原事件，保存已完成 receipt 與下一合法端點。party capture／restore 須准入原 remains／開封餐份／唯一 holder 及 pending death 狀態；未准入的未清理內容停在原安全邊界，或走已准入專用快照，不能靠延至下一張 Site、清 pending 標旗或重套死亡換取保存。

D9 限制的是未修改地理 Site 的普通經過。玩家失能、必須現場處理的遭遇，以及 NPC／攻城確實修改原人／物／建物的事件，沿各自原 owner 合同保存必要狀態；不能稱玩家失能是所有建檔情形的唯一例外。

## 6. R1／R1.5：有效通行與抵達恢復

### 6.1 路線沿現有 RegionRoute

- 保留原邊界 offset 配對、Site 內 component 與 `TerrainData.can_step`；四邊有坡口不能代替內部連通。
- 地理／坡口／資源／表版本 pin 不相符，表失效並沿原 build 重算；離線產表若需要，只是同格式快取，不另設較弱規則。
- 已訪問 Site 使用保存差量形成有效導航，覆核造牆／整地、入口與出口連通；記有效拓樸版本及失效接點。途中未修改 Site 的查路快取不建立玩法 Site 存檔。
- 隊伍速度沿最慢成員；車輛能力須納入原 footprint／swept footprint／轉向與地類。步行可過不代表 wagon 可過，不能等到站才當作全程合法。

**地類速度與車輛通行（2026-10-07 授權由我們訂；施工初值）。** 原 Site 內沒有此地類速度成本；下表是新增旅行政策。八種資源地類沿 `RegionData.site_resource_cover` 的 10×10／100 格計覆蓋比例，以原 manifest 0–7 定義加權，不把粗地理 `mixed` 當濕地。水岸另由有效 `TerrainData.water_kind` 細格遮罩求比例，與資源地類分開。

| 地類 | 速度倍率 |
| --- | ---: |
| grass_meadow（草地） | 1.00 |
| built（聚落、農舍） | 1.00 |
| unclassified（未分類） | 0.90 |
| farmland_vineyard（農地） | 0.90 |
| orchard（果園） | 0.85 |
| quarry（採石場） | 0.80 |
| scrub_heath（灌叢） | 0.75 |
| forest（森林） | 0.60 |
| 水岸政策覆寫（有效細格 water_kind 1／2／3／4 合計占 Site ≥10%） | 0.50 |

先以原有效導航／水域來源證明路線可走，再算旅行成本。八地類加權值為基礎；細水域達 10% 才用水岸 0.50 覆寫，沒有「mixed 整張一律濕地」的假推論，不能以速度係數讓人／車涉過不可通行水域。合法舊／合成來源沒有資源 cover 時，依其明示相容規則用 unclassified=0.90；固定來源必要檔缺失／hash 或細水域版本失配則拒絕重建，不默認乾地。水岸是本版旅行政策初值，不宣稱資料已提供濕地類別。

- 每 Site 通行時間依 §5 當段速度積分；速度單位先統一為 m／遊戲秒，再以 200 m ÷（當段最慢合法速度 × 地類倍率）× R1 既有坡度係數 1–3。疲勞／運送／供養端點重取速率，不沿用整路固定出發 ETA。
- **車輛禁止新跨 Site 進入的政策**：cart 為森林占 ≥50%、坡度係數 >2.0 或上述細水域 ≥10%；wagon 為森林占 ≥30%、灌叢占 ≥50%、坡度係數 >1.6 或細水域 ≥10%。這是使用者授權的新增純政策，與原 footprint／sweep／轉向／表面幾何守衛共同生效；資源百分比按同一 100 格，不能只以 coarse mixed 判禁。
- 在原 owner 中設同一無狀態旅行入界政策，接 RegionRoute 表／搜尋、原陸路與船路到站預檢及 SiteVehicleTransport 跨 Site 入界／相關移交入口；不可只讓 Region 表拒絕而現場入口仍允許同一新車隊駛入。表版本及政策 revision 一併 pin，地類組成／水岸比例／車型可通行旗標由同一有效來源派生；Local move 仍走原幾何守衛。

既有或讀回後已在政策禁入 Site 的車輛不刪除／不判存檔損壞；保留原合法局部操作及從來源 node 規劃合法退場，跨入下一 Site 才用同一新入界規則。這個來源退場例外不授權再次進入禁入 Site、忽略封鎖／車型幾何或改寫地形；無合法出口則保留原車與明確 blocked 恢復。
- 冷 Site 拓樸若因事件變更，失效後續路段並停在已完成位置；重規劃不回退世界時間。

### 6.2 可恢復的到站狀態

沿原 owner 設定 `arrival_ready → arrival_blocked / committing → committed → bound`，由原 token／generation 判定唯一所有權，不新增另一個保存機制。

1. 到站先暫停。目的地補算、有效入口、原人／實物閉包、容量、車輛配置、SiteStore 及 bind 預檢均在 `_publish` 前；`PENDING` 保留同候選。
2. `_publish` 未成功：party 仍唯一持有原人／物，來源不復活。保存 `arrival_blocked` 原因；可回地圖選同一合法通行分量的其他入口、改目的地或計時返程，沒有無限自動重試。
3. `_publish` 成功：目的地 generation 已唯一持有原人／物，旅隊不再在途。後續 bind／顯示／再次保存失敗只重讀已提交目的地，不重插 party、不還原舊來源、不重扣 upkeep。
4. capacity、封口、ID_CONFLICT、候選寫入、commit 與 bind 失敗須分開提示與恢復；不為放下隊伍清除住民、地形或物品。

### 6.3 出發與官職／作業

補完 Army row 非隊長的原退隊單走接點；失敗不先退隊或改官職。真正移出人物時沿原官職及移交引用合同，不複製整個組織到目的地。

沿 AI 官職整合第二版 §5：未接受候選重驗 revision；已接受軍令／job 不因改名或免職全部取消。依賴移出者在場／資格的部分在出發前安全完成或明示收束；合法留在原 Site 的工作繼續。看守離開不能把非旅隊囚犯變成 followers，須原拘押／供養合法接手。

**家族與玩家控制隔離：** 以原組織 namespace 中的穩定 FamilyRef／lineage 識別同一家族，只同步其原已登記成員及目前位置／引用。不同家族不聯集成員、不取第一份 offices；NPC arrival 不覆蓋玩家 controlled ID、family 或家族 offices。NPC 只攜帶與自身原人相關的引用／已准入家族 payload，不能因來源 Site 有玩家 family 就把整份控制名冊當本隊資產。

同家族分隊／返程按穩定人物引用更新，不因局部碰號漏人或重複；不同家族保留各自原 owner／組織引用，首包未准入的新家族 schema 整份明示拒絕，不拼進玩家名冊。只有沿原 `SiteFamilyContinuity` 成功的玩家控制接續，才在同一 Slot 交易切其原已登記家族／輸入／必要 offices。foreign NPC 入玩家場後死亡可選名冊仍只含玩家原明確登記家人；未準備完整家族身分／控制閉包不得先以 union 開放多 NPC 到站。

### 6.4 R1.5-S：海路與上下船

- 沿既有船隊旅程的人物／船／共糧閉包與 `checkpoint`／`commit` 合同，不另造船運系統。
- Region 路線增加海上節點：沿岸 Site 的上下船點須有原船可停靠的合法水域與岸格；航段沿既有「明示海洋航路」判定（`_adjacent_ship_route` 的海洋遮罩與船體掃掠），由相鄰直航延伸為多段連續航線。
- 旅隊帶船（或在有船的港口登船）才可走海段；沒有船的旅隊海段不可通行。船速沿原 `Ship.speed`（人數、載重、船員）。
- 上船／下船在路線中是事件端點，各需原登船時間與空間；下船點空間不足即視為 arrival_blocked。

## 7. R3：持續公式戰鬥與 NPC 派遣接點

### 7.1 派遣與最小情報

派遣清單、人格、權限與評估頻率依配套 AI 補充稿。首包先完成一種真「派兵到指定地點」入口；出征、巡邏、增援逐任務准入。運糧延至真實跨 Site 實物交接包，不能同時寫「首版運糧」與「排除跨 Site 物流」。

國家 `SiteOffices` 現有 corps／配裝職責不自動授權派遣。新職責 ID 必須有原 caller、requester、scope、revision、holder／首長代行資格及隊伍指揮者執行接點，接線後才進目錄；職位不能繞過軍令／人物實體守衛。

**最小可知情報屬 R3 前置。** 保存觀測者、時間、位置、對象／可知欄位、估計／有效期及來源事件，決策只讀該決策者合法 knownIntel；unknown 不當零、過期不作現值，大地圖不讀隱藏真兵力。無必要敵情時只作已知合法任務／等待合法觀測，不以全世界真值補空。完整迷霧、回報與命令延遲留 R5。

解析與策略分工：合法傷害／通行／供養／資產解析器可讀原實態以驗合法性並產生真結果；派遣、投入／風險、撤離及**新軍令目標比較**只讀決策者己方狀態與合法觀測，不能把解析器內部真輸入或預檢失敗細節回流為情報。真接觸／可觀測結果沿原觀測入口更新；隱藏駐軍／內牆不同可令實際結果不同，但相同觀測的決策意圖應相同。此 R3 規則須在其公式與 materialize 後的原現地策略 caller 同時接線；NPC 主線 §3.2 原 A1 全 Site 真值只作未啟用該規則的歷史／測試基線，不能到場就悄悄改回全圖知情。已承諾攻擊的合法解析與低層原接觸守衛不因策略資訊不足而重抽／重發。

### 7.2 公式版本及生命規則

- 公式是 D10 允許的畫面外解析度；改寫的仍是原人／物／隊伍狀態。每輪輸入從已結算 owner 取得能力、兵種、供養、疲勞、士氣、地形與城防，具體係數需校準後凍結。
- Lanchester 類型保留為評估候選，不以模型名稱代表係數已驗證。用現行正式 Site 對照等兵力、兵種差異、疲勞／缺糧、城防與增援場景，記時間、HP／KO／死亡、士氣及勝負容許差異；保存失敗與不適配案例。
- **軍階傷亡偏好已批准為共同規則（2026-10-07）：** 在本次真正合法的投入／新受擊候選池內，一般士兵優先、幹部其次、隊長最後；公式與即時戰鬥共用同一新目標／投入／護衛偏好。射界、接觸、部位／在場與可行動等原守衛先決定合法池，不把牆後士兵當裸露隊長的替身。已承諾命中、散射／墜落、挨餓等按原實際人物結算，不轉嫁傷害、不以軍階免疫。原戰鬥／AI 主線同步接入，存讀一致仍靠候選排序與 RNG receipt。
- 分清 **休整／停止投入、指揮撤離、士氣潰退**。**人格主動撤離已批准為共同規則（2026-10-07）：** 公式戰鬥與即時戰鬥都由當輪指揮者人格（`risk`、`casualty`）決定撤離門檻，原士氣潰退仍保留為硬下限。門檻映射須由 NPC AI 主線 §4.3 定案後兩邊同用；在映射定案前，公式版不得先行使用。
- 普通 Actor KO 目前只倒數醒來，救助縮短等待而不立即醒；Crowd 失血排除已包紮、被俘與已醒者。HP、KO、stun、疲勞各自沿原後端；禁用 blanket 25 HP／小時與未批准被動 HP 回復。Crowd 未完成全鏈准入前明示不支援。

### 7.3 傷亡與陷落不是名冊扣數

由原人物生命與清理出口處理死傷、被俘、遺物、開封口糧、住宅、拘押、家族／官職引用及士氣事件去重。原物品 ID／holder 不因公式轉換而消失或複製。

公式勝利不直接等於陷落；畫面外攻城的分階段公式見 [AI 補充稿 §10A.3「畫面外攻城公式」](npc-ai-offscreen-addendum.md)。占領沿原 `SiteSettlement.capture_zone / zone_people / advance_capture / fall_to`：守方阻擋者為區內 HP > 0、KO ≤ 0 且非俘虜的原人物，不額外限定成年、持武器或軍階；攻方才使用原 `_fit` 且非 civilian 的資格。戰力名冊與占領阻擋名冊分開。保存原 `contest_faction / contest_seconds`、具體占領者與位置／有效區域、最後合法端點及多方競逐，勝出 faction／平票順序沿原 P0；計時屬該 faction，同方合格人員交替且條件持續不清零。原阻擋、無人、控制方改變與 60 遊戲秒判定均沿同一純規則接原出口；60 秒為獨立最早事件，不等下一個十分鐘輪次。介入當刻重驗合法性：仍合法就接續已有進度，失效才按原規則中斷，不重置有效的 59 秒，也不讓被移回邊緣的假占領者繼續計時。陷落按原 owner 處理建物、住宅、職位與臨時首長；未有合法區域／人物映射的場景不得直接改 faction。

原 `SiteController` 另有 `_settlement_elapsed / _settlement_game_seconds` 的 0.25 action 秒節流欠時，尚未寫入 `contest_seconds`；bind 目前會清零。專用快照須保存或依原已提交區間確定重建這份 **P0 未消費 accrual**、來源 action／game 端點與各段合法 occupancy／faction 資格證據。資格改變時截段，不用到場後新位置回算整個舊 buffer；bind／回冷不漏、不重計。可由原 P0 入口消費已證明區間，不創第二占領鐘；60 秒效果仍走 §3.4 的同刻端點佇列。

### 7.4 冷事件共同提交

候選計算、完整 runtime 接受與 durable 發布分開。依 §3.7，原 Slot 一次接受受影響原 owner 的完整結果／runtime revision；合法共同 checkpoint 再發布全 epoch 的 Site／party／battle／供養／事件與必要 active 快照，檔案完整驗證後才更新 marker。不能只逐筆 cold commit 新時鐘而留舊 active。

冷事件使用保留活動 owner 的原 Slot 擴充入口；**不能直接用 `save_site` 搶走玩家的 `active_site_id`，也不能覆蓋玩家 journey。** 多個事件依來源 generation 檢查後串行發布；來源已變則重取候選，不能覆寫另一事件。

共同候選寫入／commit 失敗保留最後完整 durable generation 與本程序完整 volatile 狀態，按 §3.7 重取合法 checkpoint，不重套事件。重開整體回最高完整 commit；原遺物、士氣、供養、陷落與政治去重 receipt 一起恢復。玩家屏障另走 §3.8／§8.3 的已准入內部快照，普通手動 BUSY 不繞過。

### 7.5 R5：完整情報、實體回報與命令

本包沿 `RegionGameplayAI` 的原 observations／reports、Slot 共同事件與 checkpoint、原官職／人物／旅隊及軍令入口施工。`RegionTravelPanel`／Region 地圖只呈現受控人物合法取得的情報；不建立另一份情報人物、旅隊、世界時鐘或存檔權威。

1. **可知範圍與迷霧：** 公開 Atlas 地理沿原地圖來源呈現；駐軍、人物、戰況及玩家建物等動態內容，只有合法觀測／接觸／收到的回報才可用。以 stable receiver-ref 與來源 scope 判定，不按局部同號或同陣營自動共享。未知顯示未知，不作零兵力；過期內容不作現況。解析器仍讀原實態驗合法性，派遣、風險、新軍令目標與 UI 只用相應 known-intel。
2. **官員觀測與來源時間：** 原人物須在原 Site 完成 bind 與端點結算，且原官職／可見範圍合格，才產生來源 receipt；保存 observer／receiver／object 的 typed-ref、來源 scope、觀察時間、可知 value、有效期與來源事件。同一原觀測重試去重；不把開圖或讀檔當新觀測。已有候選把戰術視野與官員可見建物回報分開，60／3600 遊戲秒為各自候選 policy，仍須具名驗證，不延長原戰術情報壽命。
3. **實體攜帶與延遲：** 回報或命令跟隨原合法派遣的實體 courier／party、不可變路線與共同 checkpoint 保存。`due` 是預估，不能單靠時間到點授予情報；真到站／入場映射及接受端點後才轉成 ready，由原收件 consumer 提交 `received_at`。途中休息、供養、KO、改路、封口與存讀都沿原旅隊，不另設固定倒數代替移動。
4. **收件與權限：** 接收者須仍是正確 stable person、所在 Site、原職務與 revision；命令按其種類再查原軍權、隊伍、指揮者與政策。國家派遣不因此取得遠方 Army 的現場戰術控制。完成後以原 order serial、原 command delay／accepted receipt 證明單次執行；同 id 重試不再發令、付時間或重觀測。
5. **失敗、過期與重開：** courier 死亡／失能、接收者被俘／職權改變、目的地錯誤、路線封鎖及有效期到點都必須留下原結果。封口期間仍綁原 party，不能當收到；失敗／過期不授予新情報、不替發另一個 courier。同刻按原事件排序，checkpoint／重開保存相同來源觀測、原 route、交接映射、result 與時鐘端點，terminal retry 不重演。
6. **原 fixture 與可見驗收：** 沿既有 `region_carried_intel_original_test.gd` 的 positive／death／ko／receiver_authority／receiver_captive／blocked／expiry 七個實體情境及原 300 秒內部期限，另由 `region_remote_nation_original_test.gd` 驗原國家派遣入口；先核其實際覆蓋，缺的正向 caller／restore／map 路徑在原 fixture 補齊。A01 承接策略與真值隔離；V01 驗真玩家面板／地圖的未知、觀察時間、收到時間、過期與失敗顯示。這些是原 R5 範圍的執行對照，不增加 RG04 案例編號，也不把 fixture 存在算成 PASS。

候選定位：`RegionGameplayAI.observe / view / validate_carried_report / deliver_carried_report`；Slot `record_region_officer_feature_observation / prepare_region_carried_report / prepare_region_carried_command / _region_consume_carried_report / _region_check_carried_deliveries / region_player_known_intel`，以及原 remote-nation dispatch 接點。施工／驗收前重核實際來源，不以本節行號或方法名稱認定正式版本已接入。

## 8. R3／R4：玩家介入與不可略過

### 8.1 共同切換與提交屏障

- 模式至少為 `formula_active → materializing → live`，另有已結束狀態。介入時凍結事件時間、參與 owner、完成輪次與公式規則，`materializing` 不再獲公式輪次。
- 從原人物、隊伍、車輛、裝備、供養、HP／KO／stun／疲勞、拘押、遺物、合法軍令及占領進度建立現場候選。原場內 RNG／人格／指揮者不因 materialize 重置。
- 同刻玩家到達優先於新公式輪次。純 NPC 既已完成的區間可保留；玩家旅隊及玩家所在位置任何接敵／事件均不公式代打。
- `_publish` 前：有效入口、容量、原人／物、保存與 bind 預檢失敗，保持原 battle／party／Site 唯一所有權；停在待處理事件，提供恢復入口，不讓玩家略過。
- 待處理玩家事件依 §3.8 保存 interval-complete／effects-pending 的完整屏障 generation，或由最後完整 commit 的合法 input／event 確定重建。已持久屏障在 PENDING／容量／handoff 失敗後，continue 仍先恢復同一 `t`／序號；未持久保存失敗不假裝有 `t`，整體按最後完整 commit 恢復而不拼孤檔。所有同刻事件保留隊列，只啟用下一屏障；未解不得繞過或讀回 formula 自動走過。
- `_publish` 後現場 generation 是唯一權威；bind 失敗重讀已提交現場，不回 formula、不復活 party／重插。完成 bind 後先依 §3.8 消費同刻點效果，正常時間／戰術輸入仍受剩餘屏障與控制資格限制。
- 玩家留在活動 Site 時 NPC 實際從合法邊界進入，沿原移動／占格／容量 guard；沒有空間就保留待入場，不刪除 NPC 或改用公式。
- 路線遇敌、最早事件、同刻到站、追上與反向跨邊的截停與恢復，和 R3 同一開放門檻。R4 保留驗收名稱，不作 R3 之後才補的功能包。

### 8.2 圍城部署與入場

攻城 battle 必須引用原中心、參與 Site／party generation、siege phase、各方角色與來向、封鎖入口、原目標部件／器具／梯塔 ID、有效拓樸版本，以及下一個攻擊／作業端點。以下內容保存在原 owner，候選共同驗證後才沿原 Slot 發布，不另設一份 siege 人物／城防存檔：

- 人／隊：永久引用、原 cell／表面／component、占格及已承諾步／目的槽／租約、HP／KO／stun／疲勞、供養、拘押／遺物、角色、指揮與合法軍令。守方保留牆內／牆頂部署；攻方分營地、遠射、門前操作班、破口／梯塔突擊、中心占領。公式推進部署時修改同一原人物狀態，不能到場才憑空把人送進城。
- 器具／梯塔：原 ID、kind／definition version、team／holder／cargo version、錨格與 facing、footprint／有效部署表面、HP／phase／不可逆受損旗標、具體 crew_slots 與每人原工位、command／action／move、attack_seq／RNG、已付 build／repair 的 cost／work／progress／applied。梯沿原 feature／部件／部署 phase；塔另保留 deployed_pose、頂台／橋與承載人物。
- 建物／作業：原 feature_id＋part_id、材質／HP／支承關係、門／梯操作、修理工人與工位／已付材料／未完進度、失效表面／墜落／導航變更收據；糧食與開封餐份仍在原 holder／Sustain。

既有交戰者按上述原部署接續；**玩家與新援軍才走各自真到達邊。不得直接以 `RegionTravel.insert` 的單一入口重排全部交戰者，或清成 HOLD／解除操作班。** 聯合預檢原位置、層面、occupancy、footprint、crew 互斥／phase 合法性、梯塔表面、射程／接觸、修理與占領資格；ready 的 crew 必須在真工位，前往／解除／轉向中的 crew 則按原瞬態與整組承諾驗證，不能強套 ready 條件。不足則保留同事件待處理，不能傳送、刪人或降低原驗證。

封鎖是各陸路入口／港口／登岸點／補給路段的實際控制與合法接敵能力，不因攻方抵達就視為所有外地補給中斷。未封且合法的通道仍可通行；補給／玩家／援軍經受控通道先觸發接敵端點，不能普通 arrival 繞過封鎖。互不連通的圍城兵不能跨 component 控制全部入口。玩家已在被圍 Site 時，本場始終由 live owner 接敵，遠方新增圍城軍從合法邊界入場，不啟動同場公式。

已有 live 場內若來軍無合法空位，保留原 party、真到達時間、來向與去重 token 作為待入場隊列；玩家可沿原合法步騰出空間／應戰，隊列依同一發布時間續供養／生命及重驗來源版本，不公式代打、不中斷玩家控制。這與首次整場 materializing 的凍結屏障不同；再次檢查只重取候選，不重複到達／插人，也不把既有場內人物推走。

### 8.3 任意到場的原動作交接准入

「任何時刻抵達」表示先在到達端點凍結，再接續同一圍城；不要求玩家等一整輪或等飛彈命中。須在原 `TerrainLab / SiteVehicleTransport / SiteWorkTeam / SiteStore / RegionSaveSlot` 擴充**專用 materializing 交接 schema、capture／validate／restore／bind**，逐項准入原承諾步、裝填／瞄準／撞擊／恢復、架梯／收梯、塔部署、已離手彈體與待提交接觸。普通現場手動保存、卸載及 Native 接管的既有 BUSY 守衛保留；不能加一個略過驗證的 allow 標旗。

專用快照須有來源 owner／generation／token、同一 action／game 端點及 Fire epoch／sequence／journal、stage／elapsed／remaining、target、attack_id／attack_seq／RNG、已扣疲勞／實物彈藥的原收據、彈體位置／飛行進度／已命中過濾集合與待提交 batch、相關人／部件／器具引用和 reservation。已扣不重扣、已發射不重射、未命中續行、已命中不重傷；來源器具變殘骸或被清除不抹掉已離手彈體。

原 P0 已寫入進度與尚未消費節流 accrual 依 §7.3 一併保存；到點未提交的 work／生命／攻擊／占領事件依 §3.4–3.5 接續，不用普通驗證把 progress 壓低、提前套結果或再積分一段湊保存條件。

crew 就位／解除、推運與轉向保留原 compound_id／backend token 的來源證明、participants 的原 ID／slot／from／to、duration／elapsed／progress、器具 from／to pose、sweep／source_heights、pending release／command resume。由原 Coordinator／Reservation Grid／World 驗證並恢復或確定重建同一整組承諾；新程序不能盲用失效的舊執行 token，也不能逐人重新提案或清除未完成步。後端若尚未准入此 restore，沿原支援範圍拒絕，不宣稱已支援。

純公式首次展開按已提交的攻擊端點及保存的部分 stage 建立候選；未發射不捏造彈體，已發射未命中保留原 paid receipt 和可驗證的飛行表示，不在到場時重抽 RNG。曾為 live 的戰場只能承接其原 owner 快照，不能用平均傷害抹掉微觀承諾。未有摘要映射的少量在途動作沿原 owner 精算至下一個既定端點，其他可支援區間仍可用公式；不要求整個冷戰場逐人全程精算。

凍結點要求當刻原子交易／來源狀態一致，不要求 action／crew／flight 全空。未提交 batch 以穩定 ID／事件序號的原 owner 佇列持久化；若原交易已提交，快照只保存其完成收據，不能再套一次。預檢失敗或 schema 尚未准入時保留最後完整來源及可恢復事件屏障，**不清 action、不重置 journal、不推完到場後時間來湊安全保存點**。攻城包開放前須覆蓋其支援器具／人物後端的所有可到場階段；不能開放後才以原 BUSY 為由永遠擋住玩家。提交前／後恢復均沿 §8.1，現場正式接管後公式 consumer 停止。

**專用快照的完整讀回路由：** 原 `SiteStore` 的 save 後 readback、`RegionSaveSlot._save_checked / open_site / load`、主選單 continue／fixed-world boot、旅行 world-opened 與原 controller bind，須先識別 snapshot 的用途、schema、模式及 commit 引用，再走同一原 owner 的 mode-aware validate／restore。必要快照若不支援便整份拒絕並保留恢復入口，不能退回 ordinary load、先冷補算或要求一次普通 `save_to` 成功才承認接管完成；普通手動保存仍保持原 BUSY。

提交前核目前來源 generation／hash、時間與 token；提交後以**最高完整 commit 所選的目的 owner／generation、快照 hash、用途與交接 token** 驗證續玩。來源 party 的舊 hash／token 只作歷史來源證明，不再要求舊 party 仍持有人／物，也不回退至已失效來源。快照載入成功只代表可恢復，未取得 §3.5 相應模式的消費 permit 前不得模擬。

**bind 完成收據：** 原 bind 回結構化 SUCCESS／失敗原因，證明 commit generation／snapshot token 的全部原 owner、人物／物品 registry、crew／compound／flight、P0 欠時／端點佇列與 controlled-person 的隊伍／inventory／輸入引用已在本程序恢復。只設 terrain 指標不是 bound；後段 restore 失敗仍 committed-unbound，只重讀目的 generation，不復活 party、不補跑冷時間、不用舊程序 token。receipt 先給 §3.8 的零世界時間消費與合法恢復 UI，**不能立即開正步或新戰術輸入**；必須按序處理同刻效果／控制屏障，必要原死亡收束走明示受限 live 入口。auto-save 只在完整事件 receipt／原保存用途及 BUSY 守衛成立時允許，不能把恢復佇列誤稱效果已完成。

### 8.4 玩家離場後仍圍城的續行

模式補齊 `live → dematerializing → formula_active / cold_exact`；結束則走原結束出口。`cold_exact` 是原冷精算路徑的模式標記，不新增模擬／保存 owner。玩家仍在本 Site，或 departure／bind 尚未提交完成時，本場不得改公式。

離場除原 combat_left、附近敵人及旅行／船隊守衛，還要驗 battle 模式、現場作業與可承接快照。安全邊界能完整摘要時，凍結最後完成 action／game、水印、部署、原作業／彈體／reservation、占領計時、下一事件與 RNG；以原 Slot 一次提交玩家 party 和戰場後繼 generation，再由下一個未完成端點續算。封鎖內的離場沿原通行／遭遇處理，不能利用切 Region 逃過封鎖。

仍有不能摘要的已准入動作時，保留原快照走 `cold_exact` 直到該承諾合法收束，再共同提交轉公式；原冷精算承諾尾段及公式不能消費同一 attack／work 或 action／game 區間。合法脫離戰鬥但暫未到保存邊界時，可接受可取消的**離場意圖**，沿原 live 精算收束已承諾作業，只暫緩新一輪未承諾操作而保留原軍令。意圖不是現行固定來源 `_region_pending`，不能令 elapsed=0；live 改變來源即使已預檢過也丟棄舊候選。到新的合法端點重驗受控人物、出發／封鎖／資產／模式與 schema，重新 capture 才切 `dematerializing` 並凍結來源，後續 PENDING／retry 只續這份固定候選。意圖取消不清 job／action／軍令；捕捉後取消僅能在 commit 前沿原候選恢復 live，commit 後只走已提交後繼。若連原冷精算／交接也未准入，原狀拒絕並列作業／進度，不能永久重試過期來源或清作業放行。

攻城包不得依賴未有後繼 consumer 的永遠 live 狀態，也不能要求玩家等待敵方整場攻城結束；原正在接戰的出發條件保留。`dematerializing` 候選未提交不移走玩家，已提交只讀後繼 generation；重開或再次介入接同一 battle，不重扣費、不重插軍隊、不重算前段占領。

## 9. 施工順序與完成條件

1. **R0 契約及最小原型：** 核定人物／組織／完整資產 stable typed-ref 與移交映射、家族隔離、多旅隊／唯一時間、兩相端點／零時間效果、三種 receipt、模式 permit、真 tactical／共同 journal、volatile／durable checkpoint 及舊檔讀回。驗裁步／原 consumer 延後提交與 T04；任一不成立 R3 不准入。
2. **R1／R1.5 既有切片補完：** 先重跑四項未執行回歸（`region_lab_contract_test`、`region_lab_preview_contract_test`、`site_ship_journey_test`、`main_menu_flow_test`）並完成一次遊戲內手動流程（即 V01 的玩家旅行部分）；再補 Army row 非隊長、陣亡者／已退隊者容器拆分、有效差量與車輛路線、§6.1 地類速度與車輛通行、§6.4 海路與上下船（R1.5-S）、arrival_blocked 恢復、出發地家族名冊同步及原資產閉包。保留並擴充現有 `region_travel_test.gd`、`region_travel_visual_capture.gd`，不另造旅行系統。
3. **R1-U 在途 upkeep：** 原 Sustain／共享疲勞／生命區間、動態速度與搬運不足停止、本人死亡／原家族接續、遺物交易及到站合同完成，大步／細步／存讀一致；擴充原 party schema，車載患者未准入時明示停止／抬運。NPC 消耗與公式戰鬥開放前必須完成。
4. **R2 冷結算：** D5 已批准；S01／S02 通過後才正式接混合路徑；先限定支援 owner，做精算對照與成本測量。驗收前只做隔離比較，不阻擋 R1 完善；若 R3 所需事件前精算無法滿足其預算，R3 也不得繞過 R2 門檻。
5. **R3-A＋R4 最小 NPC 活動：** 一種真派遣、最小策略情報與解析分工、兩支原 NPC 旅隊、持續公式戰鬥、合法共同 checkpoint、玩家介入與活動 Site 抵達同包開放。首次 materialize 需完整屏障 checkpoint／bind／端點消費正向成功；多方未准入不派相應任務。共同軍階／人格新規則也須在原現地 caller 同步，不能只開公式一側。
6. **R3-B 後續任務：** 巡邏／增援／多方戰鬥、合法畫面外攻城及實物運糧分別依 AI／物流／陷落合同接入。攻城先完成 §7.3、§8.2–8.4 與補充稿原規則／輪內事件，再驗 C01–C09；同包包含四階段任意介入、完整 mode-aware 讀回／continue／bind、P0 欠時與離場續行，不把快照恢復或玩家遭遇留給事後補丁。
7. **R5 完整情報與命令：** 迷霧、官員回報、延遲、有效期與送達失敗。保留 R3 的最小觀測責任，不能到此才取消偷讀真值。

AI 主線 B1、科技研究、社會／接任／叛離與遠地政治各有自己的前置和批准範圍；本順序不代表這些功能一併實作或驗收。

### 9.1 Region 本線的執行順序與結案記錄（2026-10-08）

按使用者最新優先順序，由本聊天自行完成 Region；不再新增其他聊天／代理的施工或測試任務。先用既有來源與隔離驗證流程，按下列順序處理必要缺口，保留每次失敗及來源版本。

1. **先關 R0 基礎與 R1 最小旅行。** 先查必要 caller／consumer、解析與最小正向全鏈，再做原四項回歸與 V01 旅行流程；收束單一時鐘、typed-ref、共同 checkpoint、端點 effects／bind 和原人物資產守恆。只通純 helper 不能准入後續 NPC／公式戰鬥。
2. **完成 R1.5／R1-U。** 逐一驗原 Army 非隊長、已死／退隊容器、地類／車輛／海路、blocked 改入口／返程、在途供養／疲勞／生命、搬運不足及原家族接續；保留大步／細步／存讀對照及單次遺物交易。
3. **完成 R2。** 用原精算與混合 bridge 取得 S01／S02 的內容誤差與成本矩陣，再決定可支援 owner 與尾段／預算；未測不宣稱成本上限，也不開未准入混合 caller。
4. **完成 R3-A＋R4，再完成 R3-B。** 先做一種真 NPC 派遣、兩支原旅隊、持續戰鬥、玩家不可略過介入及成功 checkpoint→restore→bind→端點消費；其後驗巡邏／增援／多方、攻城 C01–C09、實物運糧及再次介入。成功恢復與原現場續行必須實跑，不能以拒絕反例代替。
5. **完成 R5 與完整 V01。** 依 §7.5 驗觀測→簽發→真 courier 行進→到站→收件→原命令／顯示、全部失敗與正向重開；核對策略及地圖同時不洩漏動態真值。
6. **正式整併及 close。** 隔離驗證通過後，重讀正式 D 的現行來源，在原方法內保留官職／social／captivity、資源、科技與音效既有接點，再按原授權做受保護發布及必要正式回歸。30 個 RG04、R5 對照與 V01 的必要情境均有具名結果，成本／誤差與未准入邊界明確、正式來源及保存／重開一致後，才更新 Region 結案狀態。

每個 RG04 案例的記錄必須包含：原案例 ID、對應實際 script／profile／正向 caller、必要情境、Source epoch、模式與 backend、原時限、實際 result／stdout／stderr／退出碼、保存與重開證據；可見案例另附實際 GPU 圖及輸入流程。尚無對應 script／profile 或缺正向情境時，明列缺口，先在原 owner／fixture 補齊，再實跑，不先填 PASS。既有腳本可覆蓋多案，但須逐案指明實際證據。

原資料准入、三種 receipts、模式 permit、Source／revision 檢查、Native／Crowd 與船舶邊界、原 BUSY／未知 schema 整份拒絕仍按本計畫執行。其他功能整包的 PASS、Source 候選檔數、測試來源數與過往效能數字，分別保留其自身範圍，不折算為 Region 完成率。

## 10. 具名驗收矩陣

以下都是**待實作／待執行**案例名稱，可併入現有測試，不表示已有同名腳本或 PASS。R0 先凍結輸入、允許誤差與故障注入點；歷史失敗與來源版本保留。

- **RG04-T01 唯一發布者：** 玩家 live Site 同時兩支 NPC 行軍／多輪交戰；active 攻城 BUSY、遠地熄火／戰結束、checkpoint 拒絕／來源變更及續模擬。世界 interval 只接受一次，未持久 affected 結果／receipt 不丟，冷寫不改 active／journey。合法共同 checkpoint／重開恢復全體同刻；延期／失敗不只落盤新 clock＋舊 active，volatile 不獨留。
- **RG04-T02 最早與同刻事件：** 高倍速一幀跨多 Site、反向跨邊、追上、玩家到站與戰鬥輪次同刻；先截停，沒有玩家公式傷亡。原 consumer 只到同一端點，journal／尾段連續。截停後存讀、換速度、切 Site 不延後事件、不消費舊 Region 幀倍率預算。
- **RG04-T03 事件前結算：** 離開多天的聚落遭 NPC 派遣／接敵／供應；工作、糧食、生命、職位先到事件時間，返場不按戰後人口倒算。

- **RG04-T04 前向時鐘與端點兩相：** peace Site／Region，同時一／多個 cold Fire／battle／siege，純圍城建修／HOLD／無彈→合法攻擊→停止／最後飛行→grace；各倍率／preview 來源失效，真 tactical 聯集與 journal 一次接受，不以 battle 尚在永久戰時。玩家與命中／完工／死亡／醒來／60 秒同刻：interval-complete→effects-pending 屏障→handoff→bind→零時間 effects-complete 各故障重開，原 clock／原 queue 同代、不重推鐘。未准模式先拒絕；down 動畫／已承諾步在合法受限 live 可收束，不鎖死／偷開新戰術輸入。
- **RG04-ID01 身分與引用：** 三個來源各用 person／team／item／vehicle／remains 局部同號，援軍合併、返程、原號被他物占用、重複 stable-ref／組織重建。現在引用／crew／患者／裝備／cargo／supply／work／flight／family／holder 與映射正確、retry 不另配號；歷史付款／命中／捕獲／責任 lineage 不變，異內容定義不覆寫。不同家族 A／B 入玩家場後 A 僅可選 A 原登記家人，B 不改 controlled／family／offices；同家族分旅隊同步不漏人。
- **RG04-R01 原資產閉包：** 隊長整隊＋cart／wagon、Actor 與 Army row 非隊長單走；中途存讀、主選單續行與往返。拒絕不先退隊，每項人／物只存在一個 owner。
- **RG04-R02 有效路線：** 不同 component／offset、保存牆封口、wagon sweep／轉向／政策不可過、表 pin 失配。無細水的 mixed 海岸不冒稱水岸；細水域 10%／森林／灌叢／坡度門檻在 Route 與原跨 Site 入界同判，基礎權重與覆寫一致。既有禁入 Site 原車不刪，可合法局部操作／退場，不能返入或免除封鎖幾何；查路不建未改玩法檔。
- **RG04-R03 抵達恢復：** 入口滿員、封口、車輛放不下、ID_CONFLICT；注入候選保存與 commit 前失敗、commit 後 bind 失敗。前者保留 party，後者只重讀目的地；可換合法入口／改路／返程，沒有無限重試或時鐘倒退。
- **RG04-U01 在途分段一致：** 同十天行程，大步／細步／各速度／改路／存讀；餐份、hunger、士氣、共享池與生命／車貨一致。驗不同 pool count／步行／operator／抬運／患者角色、slowdown 30 與 80／50／rest_delay、威脅中不恢復、動態剩餘路程／ETA；共享池只 advance 一次，v 除 `(1 + slowdown)`。不能停走延長餐份或重置欠時。
- **RG04-U02 失能處置：** 1 清醒＋1 KO、3 清醒＋2 KO、車載患者／滿貨／operator 失能、同人重複抬運、醒來解除；不能搬就停距離但續生命／供養。原患者席位／容量點與 holder 准入守恆，未准入車載明示拒絕。本人死亡而其他隊員仍清醒亦觸發原家族接續，KO／被俘不換人，隊長繼任不代替控制接任；無合法接續者沿原出口。死亡動畫／半步收束、remains／開封餐份、pending death 專用存讀與到站只落地驗單次交易。只有受控旅隊觸發玩家屏障，遠地 NPC 不切場；同刻死亡／遭遇隊列不漏事件。

- **RG04-U03 原家族跨 owner 接續：** 玩家必要死亡清理已完成、舊場仍攻城／flight，唯一原在世家人在另一保存 Site；專用 choose/archive/control checkpoint 正向成功，不等戰結束／普通save，不轉送死者物、不改接續者年齡／拘押。同場、已登記家人在party／battle／待轉場各驗真位置與單一owner；受控後不再公式代打，未准入船/Crowd/schema整份拒絕。archive／commit／control／bind前後故障重開只讀同一完整generation；等待按鈕退出UI後才有受限live permit，不能UI暫停＋ordinary BUSY永久重試。
- **RG04-S01 混合接點：** 公式前段＋原精算尾段與世界／Site／Fire／供養水印一致，戰鬥及民生不重算；不支援內容精算或停在合法邊界。
- **RG04-S02 成本與誤差：** 第 4.4 節時間／內容矩陣，記等待、預算、步數與差異；包含取消未提交候選／續跑與超預算。未測不得宣稱兩小時參數保證等待上限。
- **RG04-B01 每輪只提交一次：** 輪次前後、volatile 接受／共同 checkpoint 候選／commit 前後中斷；active BUSY 時 cold 多輪、戰結束與 journal prune 不丟未持久原 owner 結果。重開同一 durable epoch，HP／KO／死亡、供養／士氣／俘虜／遺物／陷落一次；不把未保存前後兩半拼成世界。
- **RG04-B02 玩家介入：** 進行中戰鬥的前／中／後段及同刻輪次到場；兩方原人／物／傷勢／指揮／占領進度一致，公式停止，僅原現場戰鬥接續。
- **RG04-B03 介入失敗：** 容量／原資產缺失／保存／handoff／bind 失敗；分 interval 屏障 commit、交接 commit、bind、零時間消費故障。成功持久屏障 continue 回同一 `t`／queue，未成功只恢復完整舊 epoch 或有合法證據的重建，不冒稱新端點已保存。未解不跳遭遇、不雙人／雙owner／重公式，恢復 UI 可用，bind 成功不能搶在同刻效果前出手。
- **RG04-L01 生命規則：** 普通 Actor／Army 與 Crowd 各自原 KO、醒來、救助、包紮、被俘與死亡邊界；無 blanket 失血／被動回 HP，遺物及真人引用守恆。未准入 Crowd 明示拒絕。
- **RG04-C01 原中心陷落：** 戰力住民與原占領阻擋者分開；清醒未武裝／未成年守方也阻擋，KO／被俘不阻擋，攻方 fit／非 civilian 及多方沿原規則。驗 59／59.x 秒介入、0.25 action 節流未滿且仍有 P0 accrual、資格改變前後捕捉／bind／重開；來源合法區間只計一次，不能用新 occupancy 回算。有效同方換人不清零，失效才中斷；60 秒同刻玩家優先。原建物／住宅／官職／臨時首長單次移交。
- **RG04-C02 四階段部署：** 圍城／破城／突擊／占領各在途中及同刻端點介入；原人物位置／表面、攻守部署、器具 ID／pose／crew 工位、梯塔／頂台、合法軍令、糧食與占領進度守恆。玩家／不同邊援軍各走實際來向；玩家本來已在城內也不啟動同場公式。live 場入口滿員時玩家仍可合法騰出位置，候入 party 供養接續、不重插、不被公式代打；不能把全部人重排入口或清成 HOLD。
- **RG04-C03 動作與部分輪次：** 第四分鐘到場、0.5／1／2／4 倍速及戰／和平混段；裝填／瞄準／飛行／衝車 collision／recovering／架梯／塔部署，以及 crew 就位／解除、推運 translate、轉向 approach／rotate／return 各插入介入。途中少員／停止／毀具亦做故障重開正向 restore，整組原參與者／compound 恢復、不套 ready 工位或逐人重提。action／game／Fire journal 端點一致，stage 與剩餘進度接續；已付疲勞／彈藥只一次、已發射續飛、已命中不重傷。候選前後／commit 前後／bind 失敗注入並重開，事件屏障、原引用／receipt／RNG 不丟失；不額外跑到場後時間。
- **RG04-C04 操作班與實物：** 滿員、最低、低於最低／失能途中、彈盡、兩具搶最後一發與補給未送達；倍率只改原操作速率、單次傷害不變，最低以下不開新操作。原 cargo／holder／seq／RNG／已付疲勞交易守恆；formula、live 與存讀均不得有免費射擊。
- **RG04-C05 工作與破壞排序：** 半建造／半修理存讀及介入、已付材料與 progress／applied／受損旗標一致；牆修理未完不補 HP。命中與修理完成前後互換、同刻事件沿原排序，支承毀壞／門操作失效／梯塔表面喪失／墜落／移動失效各只結算一次；不以輪末淨 HP 抹掉已形成破口或提前完工。
- **RG04-C06 通路與封鎖：** 厚牆只破外層、屋頂毀壞、梯／塔不可用與不同 component；只有原有效導航可穿透的通路算破口。陸門被圍而港口未封、多來向援軍、運糧／玩家突破封鎖與 blocked 入場，控制範圍和最早接敵一致，不一律禁補給或直接送人入城。
- **RG04-C07 離場與再次介入：** 介入→仍圍城→合法離場→重開→再次介入，安全摘要／cold_exact 均續同一 battle、水印、原作業／彈體／P0 欠時及下一端點。可取消意圖期間 live 時間正常走、候選隨來源變更失效；新合法端點重驗後才 capture／凍結，取消不清承諾。原出發 guard 拒絕、固定候選／commit 前後／bind 故障不半移走、不雙 owner、不重播；未准入冷交接原狀拒絕。
- **RG04-C08 遠地失能隔離：** 玩家正在 live 攻城 Site 時，遠方 NPC 增援隊缺糧／全隊倒地／死亡；冷 party／物品／任務接續，active_site_id／玩家 journey／現場 mode 不被替換。受控旅隊失能／本人死亡與圍城到場同刻，保留全部事件但只處理下一個玩家屏障；其餘不漏、不提前公式算。

- **RG04-C09 專用恢復全鏈：** save-readback／Slot load-open／旅行 opened／主選單 continue-boot／bind 全部 mode-aware；terrain 已設但 registry／crew／compound／flight／P0／controlled 失敗再正向重開。分驗 interval／effects／bind receipts，已恢復 queue 尚未消費時不能放正步／新戰術輸入，原恢復／家族 UI 仍可用；原死亡承諾收束不因零時間規則鎖死。commit 前來源失配拒絕，後按最高完整目的 commit；冷模式用自己activation，不要求玩家bind。不支援整份拒絕，不退普通 load／fake catchup／formula。
- **RG04-A01 派遣權限與情報：** 正任／代行／失能／revision／控制變更；國家不越軍權，新任務caller守原資料。相同觀測但不同隱藏駐軍／內牆、未知／過期、預檢失敗與 materialize 前後：策略意圖同、解析真結果可異，不洩真值或忽改A1全圖。驗隊長裸露而士兵牆後、合法同池軍階偏好／已命中／墜落／挨餓，不轉嫁／免疫。未接線任務不顯示可執行，運糧不製造物資。
- **RG04-A02 政治 payload 與拘押：** 旅行／移監／存讀不重置捕獲或真入監起點、歷史責任引用與已接受工作；未知必要 schema 整份拒絕。忠誠完整日從捕獲算，典獄處置期從真入監算；D0 06:00 被俘、D1 00:00 未滿一日、D1 08:00 解除前只補一日。失敗預檢不消耗未提交日計數／去重號；已獨立提交的完整日不回滾或重扣。
- **RG04-A03 政治進度續行：** 三日門檻已證明觀察兩日，未知離線十日後仍須一日合法區間；持續秒數／端點不增加、不清零。`duty_ai=false` 不凍結有證據的日社會狀態、預兆、本人意向、指定繼承／永久空缺接任，不補造未知離線投票／接任。
- **RG04-V01 正式玩家流程：** 功能選單出發、暫停／改路、看圖、blocked 提示、進場與主選單續行，做普通模式 GPU／輸入驗證。headless 守恆不代替可見流程；Crowd、船／騎乘與效能保留各自准入邊界。

### 10.1 首次可執行包

案例要在其前置能力存在後才能真正執行；在更早的包只能寫契約或以拒絕驗證支援邊界。

| 首次可執行 | 案例 |
| --- | --- |
| R0（多旅隊原型） | T01、T02（純旅隊與玩家到站部分）、T04（時鐘／模式與一般端點部分）、ID01 |
| R1／R1.5 | R01、R02、R03、V01（玩家旅行部分；現有 `region_travel_test.gd` 已涵蓋 R01 的 Actor／隊長部分與 R02 的連通／坡口部分） |
| R1-U | U01、U02、U03（普通同 Site／保存 Site 與原玩家旅隊部分） |
| R2（D5 已批准，接入前仍需驗收） | S01、S02 |
| R3-A＋R4 | T02（輪次同刻）、T03、T04（cold battle）、U03（多 party／battle 接續）、B01–B03、L01、A01–A03、V01（遭遇／介入）；C09 通用 mode-aware 恢復先驗 |
| 攻城包 | C01–C09、T04 的 siege／work／P0 端點部分；重用 B01–B03 的 commit／事件屏障故障注入 |

T03 需要事件前結算：R2 未通過驗收時以原精算執行，等待成本受 §4.4 限制。

R3-A 的開放門檻至少包括 T01–T04、ID01、R01–R03、U01–U03、B01–B03、L01、A01、V01、C09 通用 mode-aware 恢復與 A02–A03 資料承接。後兩案未准入政治玩法時先驗 payload保留／版本拒絕／未知區間不補造，真政策仍隨原主線。R2另需S01–S02，攻城另需C01–C09、T04攻城端點及正式Site校準；U03舊場攻城中的家族接續與C03／C09須正向成功走專用capture／validate／readback／restore／continue／bind全鏈，拒絕不能作成功接續／任意介入PASS。模式／消費權／原子交易是硬條件，結果分開記錄。

## 11. 本次核對定位與交付邊界

關鍵來源定位：

- `scripts/region_lab/region_save_slot.gd`：`save_site` 175、活動 owner 205、`_publish` 421、`_settle_cold_candidate` 461、Fire 驗證 2122／2149、旅行 2383／2495、到站 2528。
- `scripts/region_lab/region_travel.gd`：R1 凍結 12、`extract` 109／國別閉包 190、供養時鐘重定位 351、有效落點 365、`insert` 421／落點準備 448。
- `scripts/region_lab/region_route.gd`：固定表限制 15、連通表 57；`region_travel_site.gd` 出發 47、非隊長 Army row 限制 68；`region_travel_panel.gd` arrived 優先重試 152。
- `scripts/terrain_lab/terrain_lab.gd`：完整戰鬥步 1487、重播 1534、冷 Fire journal 5152；`site_duty_ai.gd` 未保存評估輪數 49。
- `scripts/terrain_lab/site_army_ai.gd`：休整／HOLD 291–308；`site_sustain.gd`：原硬潰退 432；`terrain_test_character.gd`：KO 427。
- `native/crowd10k/src/combat.cpp`：KO 失血及豁免 837–845；`site_settlement.gd`：占領 327、守方／攻方資格 336–340、陷落移交 `fall_to`。
- V0.4.3 攻城接點：`SiteStore.siege_save_guard / _validate_siege_vehicle`（原 BUSY 與 crew／位姿）、`SiteRuntime.release_siege_ammo / damage_structure_part / advance_siege_work / game_seconds`、`TerrainLab` 原攻城 stage／飛行／contact batch／resolve_structure_change、`SiteWorkTeam` 原 productive work 與建物修理完成出口。先核這些原符號，再擴充專用交接快照，不把新文稿欄位當成已支援 schema。

- V0.4.4 再核接點：Slot `begin_active_step`／`record_active_step`、Region preview tactical=0 與 `TerrainLab.replay_site_to` 攻城分類；shared step 的 `controller.tick`、work 完成／contact flush 與原 P0 0.25 action 節流／bind 清零；Store／Slot save-readback／`open_site`、fixed-world boot、`TerrainLab.bind` 及 controller／travel world-opened 判定；`_region_pending` elapsed／resume 固定來源；`SiteFamilyContinuity.death_tick / choose`、party 人物 lookup、`settle_person_deaths`／pending-death 保存與共享 pool effort／duration slowdown。上述目前程式均尚無本版完整新合同。

- V0.4.5 再核接點：`SiteRuntime` 原 next_item／next_vehicle／ground_loot holder；`RegionTravel.insert` 同鍵拒絕與 family union、`SiteFamilyContinuity.choose` 家人名冊；Slot `record_completed_active_step`／`_sync_cold_fire_sites`／`_flush_cold_fire_candidates`／journal prune 的 volatile／durable 邊界；原 `_siege_active`、實際人物命中出口與 NPC §3.2 策略可知範圍；`RegionData.site_resource_cover` 0–7／coarse mixed 與 TerrainData.water_kind 細水域。新增合同須沿這些原接點施工，不把新欄位當目前已有。

這些定位是 2026-10-07 本輪讀取的工作樹快照。施工前重核來源及共享測試時段，不能把舊行號、文件已有或歷史 PASS 當成目前功能／效能證據。只執行各包必要的有界測試，一次一個 Godot，保留失敗與具名結果。

V0.4 已補先前十項缺口，V0.4.3 增為 27 案、V0.4.4 為 29 案；V0.4.5 擴充原案並新增 U03，共 **30 案**，擴充本輪資產／家族／時鐘屏障／checkpoint／策略及通行反例。文稿審核與實作驗收分開：本次不宣稱新增 schema、公式、玩法平衡、性能或發布已完成。

### 11.1 本輪文稿審核結果

本輪對照原始碼、修訂後再交叉審核，最後一輪在時間／模式／共同保存／恢復與死亡接續、旅行／完整資產／家族／通行、AI／情報／戰鬥／攻城／分包門檻三個範圍，**未處理計畫問題為 0**。兩稿版本、必要合同、案例與首次准入範圍一致；此為文稿及接點審核結論。

係數／容許誤差／成本凍結、schema／caller／consumer 施工與 30 案執行是已明示的後續包門檻，不能由本結論省略；本次未執行 Godot，沒有新增實作／runtime／性能或發布 PASS。

## 12. 使用者答覆（2026-10-07）

1. **D5 混合冷結算：批准。** 見 §0.2、§4.2。
2. **在途疲勞、傷勢與全隊失能：由我們訂。** 見 §5 表格。
3. **人格主動撤離、軍階傷亡順序：批准為共同規則**，同時改即時戰鬥；須 NPC AI／戰鬥主線同步，見 §7.2 與 AI 補充稿。
4. **畫面外攻城：用較複雜的公式。** 規格放 AI 補充稿 §10A.3「畫面外攻城公式」，陷落仍走原中心 P0。
5. **地類速度與車輛通行：由我們訂。** 見 §6.1 表格。

另：海路現況與待補內容見 §2.2、§6.4。
