# 勢力與外交規格 V0.6 審核修訂稿

日期：2026-10-08。來源：[勢力與外交規劃 V0.5](reports/faction-plan.md)及使用者貼上的同版全文；兩份正文逐行相同。本檔是本次新增的規格交付，原稿與其備份保留。

**審核結論：玩法方向可保留；V0.5 不宜直接照文施工。** 主要缺口是穩定人物引用、共同保存、旅行中與冷 Site 的勢力變更、首長與國家解散、外交事件生命週期。以下已提出具體修正；§12 保留問題、程式證據與驗收對照。

**狀態：規格完成，功能未實作／未驗收。** FQ1–FQ15 維持來源決定，FQ9 仍另案；本次補充的距離速度、事件排序、資料上限、AI 排程及失敗碼是施工建議基線，不宣稱使用者另行批准過這些細節。本檔不自動取代其他主線文件；同步責任見 §9，施工前須消除同一契約的版本分歧。

審核使用 2026-10-08 工作目錄的現行內容。當時 Git HEAD 為 `24eaf204f4b5a1896d74a2960b4a3a054d4b9541`，但工作目錄含未提交變更，不能以該 HEAD 單獨重建本次來源。遵循 [PROJECT_ARCHITECTURE.md](PROJECT_ARCHITECTURE.md) 的原 owner，不建立第二套人物、國家、戰鬥、物品或時鐘。

## 0. 一句話設計

勢力是戰鬥歸屬與同方權限的 ID；外交只決定不同勢力是否敵對。由原 RegionSaveSlot 保存唯一勢力名冊與外交紀錄，原 Site／party／battle 仍擁有原人物和實物，以共同候選與 checkpoint 完成政治變更。

「和平」不授予軍令、倉庫、車輛、任官或設施使用權。合併、分裂、消滅也不是只改名冊：它們必須同步處理所有受影響的**當前歸屬引用**；歷史收據保留原 ID。

## 1. 現況盤點

### 1.1 已有與尚缺

- `faction_id` 已在 Actor／Army／Crowd／旅隊使用；建物、聚落用 `owner_faction`。Army 的戰鬥歸屬是整隊欄位，不能在同隊 row 偷加另一份 faction authority。
- 本次未找到正式 `faction_registry`、`faction_relations` 或 `diplomacy` 的 Slot 實作；V0.5、貿易文件中所寫的新表與入口屬計畫。
- RegionSaveSlot **已有**共同 generation、世界時鐘、事件、live／cold／party／battle owner 與 checkpoint；沿原機制擴充，不能另造 DiplomacyManager 保存或背景時鐘。
- SiteStore 與 Slot marker／control 都有嚴格 schema、來源及 checksum 檢查；新增欄位必須配套版本、migration、capture、restore、readback。
- 原 Slot 已有建物摘要來源驗證流程，缺的是勢力人口／兵力／資格等政治摘要，不能將「尚無政治摘要」寫成「尚無 Region 摘要」。

### 1.2 人物、國家與首長

- `equipment_nations` 是原國家 owner，不新增 Region 國家真值表。部分成員外派時以原 `organization_refs` 連接；全體出行時原國家紀錄可能移入 party。
- 旅行穩定引用為 `{type, namespace, lineage}`，由 `RegionTravel.validate_identity / prepare_identity` 及 `SiteEquipmentOrders._portable_ref` 使用。**Site＋本地 person_id 不是穩定 PersonRef**；抵達可能重映射本地 ID。
- 正式國家首長沿原 head／office 解析入口；不能假定所有現存國家都已升為有完整 `offices` 的新 schema。
- 現有家族控制接續、家主職位與勢力首長是三種不同權責。`SiteFamilyContinuity.choose` 不等於自動家主繼承或勢力首長任命。
- R2 `social_state`、`SiteSocial.record / settle_person` 已有實作；外交背約尚未接入。不能沿用舊盤點直接聲稱整套 R2 尚不存在。

### 1.3 敵對與原生端

- GD 的近戰、移動接敵、遠射、火箭、戰術 AI、出發守衛、聚落占領、Region 到站／公式戰鬥均需接外交判敵；只搜一種 `faction != faction` 不能證明查核完整。
- C# 候選批算與 `native/army_idle` 也是 consumer，不只 Crowd。若批算只是保守候選超集，可保留其快路徑，由下游正式判敵篩掉和平者；須證明不漏合法敵人。
- `native/crowd10k` **已有** `hostile_ / set_hostile` 與序列化。需要的是 Slot→native 的同版本投影、讀回核對與 ID 容量守衛；不能照貿易舊文再建另一張權威表。
- native Crowd 關係索引使用 8 位範圍，不能將最大 `100000000` 的原 faction ID 直接截成 `a & 255`。首版未支援的 ID／後端組合明確拒絕；正式映射需另驗無碰撞，不因本規格重編持久 ID。

### 1.4 顯示與開局

- Controller 部分面板仍顯示 `faction_id + 1`，其他顯示原值，需統一。
- 軍營旗已有依 faction 推導的配色／紋樣（`SiteResourceView._barracks_flag_draws`）；「grep 沒有 FACTION_COLOR」不能推出完全沒有勢力配色。
- 主選單計畫記錄 P1–P5 完成，當前有 `main_menu.gd`／`region_entry.gd`；這不代表「自建／加入情境勢力」已完成。本次不重驗主選單既有結案。

## 2. 設計原則

1. **一個權威來源。** 名冊／關係／外交由 Slot 擁有；Site、party、nation、office、social state 與物品仍由既有 owner 擁有。摘要是具來源版本的只讀投影。
2. **身分、所在地、權限分開。** typed stable ref 識別原人／原國家；locator 只協助找到 Site／party／battle；是否首長、清醒自由及受控狀態由當刻合法來源重驗。
3. **ID 不重用。** 合併／消滅保留 tombstone；`next_faction_id` 大於全部歷史與情境保留 ID，與建立交易共同提交。`-1` 無主哨兵不是勢力。
4. **舊行為相容。** 缺名冊的合法舊世界採明確遷移；單獨 Site 只讀 fallback。同勢力永不敵對，不同勢力在未登記和平時敵對。
5. **全成或全不成。** 政治交易先建 detached candidate，驗全受影響 owner、版本、人物／物品守恆，再由原 Slot 一次接受。不能先換旗色再補國籍、人物或保存。
6. **時間不倒算。** 使用原 Slot 已發布的 GAME 時間及事件順序；不用現實離線時間。冷 consumer 讀所結算區間的關係版本，不把今日和平套回昨日交戰。
7. **權限不放寬。** `hostile(a,b)==false` 不等於同國、同隊、同方或可當友軍支援。控制者、任官者、實際執行者分開檢查。

## 3. 勢力怎麼分

### 3.1 名冊與摘要

Slot 新增版本化 `faction_registry`：含 `version`、`revision`、`next_faction_id`、遷移完成狀態及 ID→entry。schema 版本用於格式，revision 用於內容競態，不能混用。

每筆 entry 的施工格式：

| 欄位 | 契約 |
| --- | --- |
| `faction_id` | 合法整數 0…`SiteSettlement.MAX_FACTION`；永久不重用 |
| `name`、`color` | 顯示名稱與合法不透明色；建議名稱 trim 後 1–32 字；舊檔顯示「勢力 N」 |
| `kind` | `player / npc / rebel` 是建立來源標籤，不授予玩家權限；目前玩家所屬由原受控人物推導 |
| `leader_ref` | 無國家時才是權威首長 ref，可空；有國家時此欄為空，首長由原 nation head 推導 |
| `nation_ref` | 可空的 typed stable nation ref；一對一限制見 §3.2 |
| `status` | `active / merged / extinct` |
| `merged_into` | merged 時的最終承接勢力 ID；其餘為空，合法終點規則見 §4.2 |
| `founded_at`、`ended_at` | GAME 秒；舊資料成立時間未知用空值，不偽造為遷移日；有效終止時間不得在未來 |
| `duty_ai` | 僅無國家勢力保存外交主動開關；有國家時沿原 nation offices 的 `duty_ai`，不存雙份 |

`faction_relations` 與 `diplomacy` 同在 Slot 的原保存領域，不在每個 Site 複製存一份。

**摘要的完整性是消滅判定前置。** 沿原 Slot 摘要擴充，每個來源記 `source_generation / runtime_revision / checksum或原收據 / as_of_game_seconds / complete`，附：

- 各有效勢力的在世原人數、被俘原人數、成年可戰原人數、擁有建物與聚落清單。
- 首長 stable ref、當前 locator、資格、所讀 `ambition / mercy`、來源 office／person 版本與 `duty_ai`；摘要不任命首長。
- 原 Site／party／battle 唯一所有權與 coverage。玩家旅隊、NPC 旅隊、俘虜及未訪但情境已配置的單位都要被覆蓋；remote membership 不算另一個人。
- 已知陷落事件與目前聚落 owner；收復依可證明的原陷落事件，不能從顏色或舊國名猜領土。

來源不完整標 unknown，UI 顯示未知／最後更新時間，NPC 不將未知當 0，消滅判定拒絕。摘要刷新隨原生命、轉場、任命、控制接續及共同端點更新，不能只在使用者手動存檔時更新。

### 3.2 勢力與國家 FQ1

- 一個 active 勢力最多綁一個正式國家；一個正式國家恰屬一個 active 勢力，雙向映射相符。
- 原 nation schema 新增 `faction_id`，驗證沿 SiteStore／SiteEquipmentOrders。既有國家不能憑 nation 名字或第一名國民猜映射；migration 接受情境明示映射，未映射的 legacy／trial 國保留 legacy 狀態、不得冒充已綁定正式國家。
- 國籍與戰鬥歸屬不同。俘虜／外派國民保持原國籍；本計畫不因和平或合併自動授予另一國國籍。
- 國家本體可能在 Site 或 party；Slot 只存 stable ref 與來源投影，不複製 `members / standards / culture / offices / technology`。

### 3.3 勢力首長 FQ2 FQ3

有國家時唯一首長由原 nation head resolver 取得；無國家時使用名冊 `leader_ref`。首長須在世、清醒、自由且政治權限有效；元首／家主／隊長職稱或本地同號 ID 均不能代替這組檢查。國家首長的 faction 與正式 nation mapping 必須相符；既有混合 faction 國民不因此被整批改方，元首不符則先由原合法任命／移交修正，不從國籍猜其陣營。

無國家首長死亡／永久失格時依已定 FQ3 家族接任：本人是家主，先由原家族繼承入口產生新家主；本人不是家主，由現任家主優先，繼而按同一家族合法順位找本勢力合格原人。暫時 KO／被俘不自動換首長，待恢復。

**不將現有玩家 `choose` 當家主自動繼承。** 原家主繼承、候選排序、任命與勢力首長發布必須是同一候選；該家族入口未完成則此功能尚未准入，不能偷偷新建第二套順位。勢力首長資格較玩家控制接續嚴格，不能反過來限制原玩家死亡後可接續人物。

首版族人搜尋限原批准的首長所在 Site；不將外地或旅行中的族人假搬回。無合格人則空缺；控制者可沿原家族流程選人，但不因此自動取得勢力首長。空缺只阻擋需首長授權的新決策，**既有書信失效處理、停戰到期及歷史記錄仍照時間執行**。不能寫「空缺後靠建國解鎖」，因建國本身須有合格首長；需原合法補任／繼承／情境任命。

接收方首長換人後，尚未回覆的信件可由新首長處理；發信方首長換人使原提案授權失效。已回覆接受但未生效的授權亦不得無條件轉給新首長，按 §11.4 作廢再提。

### 3.4 開局 FQ8 FQ9

- 情境列出所有勢力、保留 ID、名字、顏色、原首長／國家引用及起始關係；Taiwan 勢力數與名稱仍另案。
- 玩家可新建單人勢力，也可加入情境勢力；選擇須經原主選單請求→初始世界候選→原人物 faction→控制／保存一路傳遞，不只新增一列名冊。
- 新建預設與其他勢力敵對；加入不取得情境首長權力。`kind=player` 不用來判断誰受控。
- 情境可從 0 編號，但驗證器不要求連號。新 ID 用完整遷移後的歷史高水位；並行建立以同一 revision 防衝突，耗盡回 `FACTION_ID_EXHAUSTED`，不得回繞。

## 4. 勢力怎麼變

### 4.1 建國 FQ4

1. 勢力 active、尚無正式國家，首長合格且有明示建國授權。
2. **首長實際所在的同一座本勢力聚落已建制且等級 ≥2。** 「身處 1 級聚落，但別處有 2 級」不符合 FQ4。
3. 由原 nation／office owner 在首長所在 Site 建立正式國家、映射本勢力、任命原首長為元首；不能把測試專用 `register_trial_equipment_nation` 改名當正式入口。
4. 首批國民只有首長，其他人沿原 `nation.admission`；聚落國籍關聯另作明示指定，不因 faction 相同自動改全體國籍。
5. 國名、同名策略、國家 ID、原人會員與任命合法性沿原國家格式；失敗不留孤立 nation、半份首長或已消耗 ID。

### 4.2 歸附合併 FQ5

弱方提出、強方接受，走 §11 書信；「弱／強」是提案角色，不另設強弱階級。接受回信送達後，兩方當前授權仍有效、均 active、彼此沒有未結束戰鬥，才可提交。

交易須包含：

- 原人物／整隊、車輛、建物、聚落的當前 faction；captivity 的當前 captor faction、遠端組織引用、contest、旅隊及 battle 的當前參與引用與相關權限。
- 原軍令／攻擊目標、garrison、housing、training、corps、office、接管與未完成作業的重驗。已成同勢力的互相攻擊／占領意圖不得繼續；原已付費與不可逆實物結果不得消失。
- 弱方國家若有，沿原 nation／office／technology／實物 owner 解散。國民取消該國籍但保留原人、私人物品、其他合法任職；不自動入強國，不創造或銷毀國庫物品。
- 國家解散需保留可辨識的終止收據，使冷 Site／旅隊的 membership、office／culture／standards／科技 holder 等依賴在消費前合法失效。各類公共資產／研究／公務由原 owner 明示處置；未有完整解散入口，整筆回 `NATION_DISSOLUTION_UNSUPPORTED`，不可先刪 nation。
- 弱方相關非終態提議作廢，有效協定終止，當前關係項目移除；歷史提議、協定、背約仍可引用弱方 tombstone。

**冷 Site 可延後物化，不能延後語義。** 所有當前 owner 查詢（包含 NPC、旅行與開戰）先解析同一 registry revision 的有效 faction，再使用其權限。未載入 Site 不必立刻寫盤，但下次 consumer／bind 前必須生成經驗證的派生候選；只在 `bind` 改 ID 會讓冷戰鬥仍把已合併者當敵人。

每次合併另保留不可變的原直接事件 `from / to / effective_at / registry_revision / receipt`。冷補算跨 A→B@t1、B→C@t2 時，沿原端點分段，分別用當時歸屬；壓平 A→C 只服務現在查詢，不能套回 t1 前。未能按時刻解析／結算的 consumer 必須先合法推進到合併端點才准入，否則拒絕該合併；不容許帶著未知政治欠時繼續跑。歷史事件的清理受最慢 consumer 水位限制。

連續合併 A→B→C 時，同一提交將既有指 B 的 aliases 壓平到 C。`merged_into` 不允許自指、成環或缺目標；目標是未 merged 的終點，通常 active。C 日後合法 extinct 時，保留 A／B→C 的歷史解析終點，所有 active 操作均拒絕；不能為了維持「永遠指 active」阻止合法消滅或刪歷史。這修正 V0.5 無法同時處理連續合併及最終消滅的限制。

清醒自由的兩首長同意不代表第三方戰場／俘虜等可任意改。未准入的 battle／native／遠端國家解散組合回明確原因，整筆保持原樣；不永久刪候選資料來假裝成功。

### 4.3 消滅

僅在完整 coverage 證明全部 Site、party、battle、情境已配置單位中，該有效勢力無活人、無建物、無聚落時標 extinct。**只剩俘虜仍有活人**，不得消滅；全部人旅行中也不等於無人。

摘要 unknown／來源過期、轉場未完或待處理 owner 無法驗證時跳過判定並顯示原因。停止新提議並終止 active 協定；永久保留勢力 ID、終止時刻、歷史關係事件與必要收據。仍有名義國家／公共 holder／研究引用時，需原 owner 的合法終止候選，保留實物與歷史責任；尚不支援則延後整筆 extinct，不能刪表造成無主實物或活的幽靈國家。

### 4.4 分裂與自立 FQ6

- 隊伍：正式隊長及已確認支持者使用原政治／名冊移交；不跟隨者先有合法原勢力出口與容量，成功後才將剩餘整隊改新 rebel。保留原 ID、holder、生命／人格／社會狀態、共用疲勞與物資合同。
- 車輛、cargo、乘員、俘虜、操作員、供養一併驗閉包；不能用「隨隊全帶走」把不同意者或第三方俘虜身份改成新兵。無合法出口就拒絕整筆。
- 聚落：首長本人及跟隨任職者也須先在同一候選內有合法 Actor／整隊出口，尤其原首長只是某 Army 的一列時，不能只改聚落而把本人留在原 faction，也不能因此強改整個來源隊。須移交原人至合法目的容器，無出口整筆拒絕。只重用 `fall_to` 中可合法轉交的建物篩選與原人引用守衛，提供窄的自立交易；**不能先呼叫完整 fall_to 再補回職位**，其現有流程還會清住宅與訓練。
- 「保留職位」指保留仍合格且支持自立的原任職與職責設定，不是保留敵方任職者。拒絕跟隨／失格者沿原 Office owner 合法空缺；駐軍各自選邊，未選者不被暗改。
- 叛離門檻、預兆、觀察期、支持名單沿職位計畫，不另設 instant rebellion。新勢力首長為此次合法隊長／聚落首長；與原勢力及未明示和平的其他勢力敵對。

### 4.5 不做的事

不新增中立平民勢力、同盟、附庸、割地談判、隱藏逐兵 faction、替身信差或第二套政治模擬；不替受控人物自動同意投奔、歸附或宣戰。

## 5. 資料 保存與 Site 載入

### 5.1 舊檔遷移與輸入邊界

1. 先驗原檔 checksum／原版本 schema，不改原 bytes。讀原 marker 所知 Site、player／NPC parties、remote claims、歷史 faction 與情境保留 ID，收集完整高水位。
2. 合法既有 ID 只新增無名、無首長的 legacy npc 名冊；不為缺資料自動生成元首、國民、人格或和平關係。
3. 全份掃描成功才同代提交 migration version、registry、摘要 coverage 與配置游標。遷移失敗／壞檔保留原檔與舊 marker，不略過壞來源並配置新 ID。
4. Site、nation、Slot control／marker、region registry 若欄位改版，均須明列舊版 reader、version switch、拒絕未知新版及所有 writer 保留新欄位的清單。
5. 只讀無 Slot Site 不新建 Slot；顯示「勢力 N」，同方和平／異方敵對，外交命令回 `UNSUPPORTED`。

### 5.2 型別化變更

先驗舊資料，再以明確 schema 對**當前引用**建立 alias／解散候選，完整驗證後提交。禁止全檔遞迴把所有相等整數替換成新 ID。

必查引用至少包含：Actor、Army、Crowd team、feature、settlement、captivity.captor_faction、contest、organization_refs remote_people／remote_teams、party content／controller、battle participant 與國家映射；各自由原 owner 列出 actual field paths。

`last_fall.from/to`、背約責任人、原協定雙方、捕獲歷史及舊收據不改 ID。現行 `SiteSettlement.validate` 要求 `last_fall.to == owner_faction`，須版本化解除「歷史等於現在」的錯誤耦合並保留歷史完整性驗證；不能篡改陷落史通過驗證。contest 在 canonicalization 後若變成本方，合法清除計時，不產生一次假陷落。

### 5.3 原子性與共同 checkpoint

沿 `RegionSaveSlot` 的原 registry／runtime revision／generation／事件及 marker，候選記預期來源、GAME／ACTION 端點和各受影響 owner revision。過期候選拒絕，重新讀最新真值再評估。

區分兩個已存在的邊界：

- **runtime 接受：** 所有受影響候選、關係版本、摘要、事件／去重收據一次接受；未成功前不向 UI／AI 發布半份結果。live 的合法時間與現場動作仍由原 owner 推進。
- **durable 保存：** 原共同 checkpoint capture 同一 epoch 的 active、cold、party、battle、名冊、外交與社會事件收據，寫候選檔、readback 驗證，最後由原 `_publish` 更新 marker。普通保存 BUSY 不允許只落盤新外交／時鐘和舊人物；未落盤明示未保存。

若某種 ownership 移交需要既有專用 publication／bind 屏障，沿其原票據流程，不用外交略過。磁碟失敗保留完整 runtime 結果和最後正式發布的 durable marker；重開讀最高已發布 marker，忽略未發布孤檔。**最新已發布 marker 或其依賴缺失／checksum 損壞時拒絕恢復，不回退舊 generation**，以免復活已移交的人物。不能為了保存把已合法接受的其中一邊倒退。

### 5.4 Native 與 caller 接線

第一版不新增原生政治 owner。涉及未支援政治變更的 active Crowd，先確認原 `CrowdSite.clear` 能完整回 GD，再重驗同一候選；不能安全交接則整筆 `CROWD_UNSUPPORTED`。

有非預設關係的 native consumer，在 host 同步、relation revision、ID guard、存讀／回寫核對准入前禁止啟用。重用原 `set_hostile`；是否需升 native blob 版本依實際格式差異定，不為既有相同矩陣欄位盲目加版。

原生／GD 的「支援友軍」仍按已批准同 faction 規則；和平第三方不因 `!hostile` 被計入同盟兵力。C# 保守候選可於下游正式傷害／占領／自衛前篩選；**army_idle 的 encirclement_front 不只是候選**，其敵格會直接造成 pinned／停止移動。它未接同一關係版本時，有 peace 的場景必須走關係感知的 GD 路徑或明拒；傷害前才補篩選太晚。

Region 到站原雙方戰鬥模型也須檢查三勢力拓樸：A與B和平、各自敵對C不代表A/B合成同盟。原 consumer 無法表示時保持原事件待處理並回 `BATTLE_TOPOLOGY_UNSUPPORTED`，不得靜默不建 battle 後安全通行；此缺口是 F2 正式多勢力准入項，拒絕案例通過不等於多勢力戰鬥已完成。

## 6. 顯示

- 所有正式面板以同一只讀解析入口取得名稱、顏色、狀態；缺名冊顯示原 ID，不加一。過去事件顯示當時勢力並可附現在承接者，不把史料全改成勝方名字。
- WORLD：勢力、首長、國家、聚落、人口／兵力估計、資料時刻／未知、關係及外交紀錄。
- Region：聚落與旅隊顏色跟原有效 faction；不以顏色決定權限。Site：人物／隊伍／聚落面板一致，軍營旗沿原 View 投影名冊顏色；不改装備物品的染色真值。
- 首長外交面板顯示提案種類、條款、去程／回程時刻、回覆期限、狀態與失敗原因；接受按鈕文案明示「回信送達後生效」。玩家不是本勢力首長時只讀。
- 即時宣戰、對外提案、接受歸附沿同一權限入口；成功才更新畫面。通知以事件 ID 去重，存讀不再彈同一則。

## 7. 分階段

保留 F1–F6 編號，修正相依，不把「貿易 T1-b」當成另一套外交實作。

| 包 | 可交付範圍 | 前置與完成界線 |
| --- | --- | --- |
| F1a 名冊與顯示 | migration、高水位、stable refs、舊 ID 顯示一致、共同保存 | 既有 Slot／Store；不提供新外交／合併；為第一個最小施工切片 |
| F1b 開局 | 情境名冊與玩家新建／加入選擇完整接入 | F1a＋原主選單／初始世界交易；不是只改 UI |
| F2 首長與關係基礎 | 原 head 解析、家族接任接線、摘要、relation query、所有判敵 consumer、情境和平 | F1a；家族接任子項須職位 R5 原繼承入口；貿易 T1-b 共用此接線；**公開宣戰／講和延至 F6** |
| F3 國家綁定與建國 | 正式 nation mapping、建國、admission、聚落 nation 關聯 | F1a／F2 首長＋原國家／地圖編輯器所需切片；未有映射不猜國籍 |
| F4 合併與消滅 | 原子歸附、alias、國家解散、完整 coverage 滅亡 | F2＋F3 解散／引用入口＋F6 歸附信件；缺任一依賴整筆不開放 |
| F5 分裂 | 整隊／聚落自立、原人出口、選邊、權限重驗 | F1a／F2＋職位 R2 社會、R6／R7 所需退出與叛離／原名冊移交；不能只等 R2 就開放 |
| F6 外交 | 書信／回信、宣戰、停戰／講和、背約、每日 NPC、玩家介面 | F2 基礎；歸附提案提交接 F4、通商提交接貿易 T6；未接 consumer 的種類顯示未開放 |

施工 DAG：`F1a → F2 → F6（基本外交）`；`F1a → F1b`；`F2 → F3`；`F3＋F6 → F4`；`F2＋原叛離入口 → F5`。F6 的最小信件核心不依賴 F4／T6，只有對應提案種類在 consumer 完成後開放，避免反向依賴。

第一刀只做 F1a；必驗 FA-01／02／03／21／36，並驗 FA-09 的「名冊與既有 owner 同代保存」、FA-20 的「名冊 typed ref 跟隨既有旅行映射」、FA-30 的「coverage unknown 不當零」子案例。尚未實作的合併／外交事件不冒稱已覆蓋；其餘 FA 子案例留到所屬分包。不得把 F1a 通過寫成 F1b／外交／合併完成。

## 8. 驗收

以下都是**待實作驗收**，不是本輪 PASS；保留 FA-01–FA-19，新增從 FA-20 起。

- **FA-01 舊檔不變**：合法無名冊世界遷移後，既有戰鬥、出發／到站、陷落、Crowd 結果不變；比較原玩法欄位／事件，不把新增 schema／checksum 要求為整檔 bytes 不變。
- **FA-02 顯示一致**：Controller、WORLD、Region、Site、軍營旗同來源；無名册皆顯示原數字，裝備染色不被偷偷改寫。
- **FA-03 ID 不重用**：merged／extinct／冷 Site／party／情境保留最大 ID、並行建立、上限耗盡，不碰撞／不回繞。
- **FA-04 首長**：有國家跟原元首；無國家按家族繼承候選同次提交；KO／拘押禁政治操作但不換人；空缺不停止既有停戰到期；不得混用玩家控制接續。
- **FA-05 建國**：首長所在聚落 1 級而別處 2 級必拒絕；當地 2 級、原首長與映射合格才成功，其他國民不被一鍵改籍。
- **FA-06 歸附**：live／cold／player party／NPC party 的當前歸屬一致，含俘虜、車輛、遠端組織；互戰、未支持 native／國家解散均全拒絕，無半份合併。
- **FA-07 消滅**：只剩俘虜、全部人在路上、只有建物、未訪已配置情境、unknown coverage 均不誤滅亡；完整零集合才 extinct。
- **FA-08 分裂**：不跟隨者有原人合法出口；支持者整隊同方；聚落自立保留合格職位，解除失格者，不丟住宅／供養／cargo 或複製人物。
- **FA-09 存讀**：名冊／relation／外交／Site／party／battle／時鐘共 generation；BUSY、write/readback/marker/bind 失敗和程序重開不半份恢復；最新已發布代損壞明拒，不回退復活原人。
- **FA-10 書信送達**：送達前對方查詢／通知均不可見、不能回覆；同地零延遲、異地距離、在途首長、往返、暫停／慢幀／存讀，不重算已固定時刻。
- **FA-11 提交前重驗**：雙方有效授權、active、source revision、條款、所有前提重驗；發信方在去程／待覆期間換首長即失效，接收方在回覆前可換人；接受後換首長／被俘／國家解散／再開戰不沿用舊同意。
- **FA-12 同對同類唯一**：A→B／B→A 視同無序 pair；去程、待覆、回程均占唯一鍵；拒絕冷卻不能反向繞過。
- **FA-13 停戰到期**：未講和即回 hostile；講和同刻按 §11.8 排序，不閃回敵對；通商失效、交易合法收束，原俘虜不自動釋放。
- **FA-14 宣戰與背約**：對任何 peace 宣戰都寫一筆背約，包括純講和、情境和平、停戰與通商；自然到期不寫背約，重复請求不重記。
- **FA-15 NPC 規則**：依 §11.6，A／M 取 0／50／100、門檻等號、零兵力、unknown、每日去重、duty_ai 關閉仍回覆；受控首長永不由 AI 同意。
- **FA-16 冷 Site 首長**：同批可證摘要得相同決策；不載入 Site、不直寫人物。失效／缺來源不偷讀另一時刻真值補洞。
- **FA-17 合併與消滅**：作廢全部非終態提案（含回程），終止 active 協定；歷史可指 tombstone，無 active 內容懸指非 active 勢力。
- **FA-18 收復宣戰**：真陷落史＋現在外敵和平 owner＋人格／兵力／10 日門檻；換 owner／已收復／無證據不開戰。觸發仍承受同一背約後果。
- **FA-19 背約不滿**：事件當刻固定原國民集合、原責任首長及原國家；首長除外，各原人 +5 一次，原社會 owner 在合法日結算套用，同日正向上限 20；cold 回來不造離線日結算。
- **FA-20 穩定引用**：首長／國家旅行抵達遇本地 ID 碰撞、全國出行、返程／存讀，仍解析原人／原國家；找不到原 owner 必拒絕。
- **FA-21 嚴格遷移**：壞 checksum、未知版本、未完整掃描、只在 party 出現的最大 ID，原檔不被部分補寫；舊 writer 不抹掉新欄位。
- **FA-22 連續合併**：A→B@t1→C@t2、C 再 extinct；原 A 冷檔跨越 t1／t2 分段讀當時歸屬，現在 aliases 壓平、史料 ID 保留；cycle／缺 target／stale revision 拒絕。
- **FA-23 歷史與當前**：含 prison、captor_faction、contest、remote corps、last_fall 的舊檔經合併仍合法，歷史數字未覆寫；重复 bind 無二次 mutation。
- **FA-24 國家解散**：部分／全體在途、遠端元首、研究／公務／稅源 holder／職位資格裝備逐一准入；失敗不先取消國籍或丟實物。
- **FA-25 生效邊界**：live 下宣戰、停戰、自然到期即更新後續選敵／傷害／占領／出發／到站；所有已承諾飛行／作業依原 consumer 合同重驗，不能只更新 UI。
- **FA-26 全 consumer 等價**：GD、C# 候選、army_idle、Crowd、Region 公式同輸入；和平相鄰不 pinned／假包圍；三勢力 A–B peace、B–C hostile、A–C hostile，不把和平第三方算支援同盟，未支持的到站拓樸不靜默漏戰鬥。
- **FA-27 Native ID**：0／255／256／同低 8 位不同 ID；未准入 ID 明確拒絕，不能 alias。host relation 改版、native 讀回失配／handoff 失敗保持原樣。
- **FA-28 回信與期限**：第 7 日前已接受、回信超過第 7 日仍有效；截止當刻按半開期限拒絕；回信途中單方開戰／換首長不能使舊信稍後復活和平。
- **FA-29 協定取代**：停戰升講和清掉原到期效力；同 pair 不疊多個互相覆寫的和平基礎；通商到期不結束和平，停戰到期則終止需和平的通商。
- **FA-30 快照與人口**：轉場、死亡、拘押、元首更替同刻只計原人一次；未知不是零，過期摘要不授權 extinct／NPC 政策。
- **FA-31 遲到社會事件**：收到時事件日已日結算、seen 滿／pending 滿、受眾旅行、已退國／已死亡，按 §11.5 保留收據、日上限與原責任，不丟事件或重加 5。
- **FA-32 時間單位**：GAME 秒／分鐘／日換算、距離米、往返固定端點、日邊界與同時到期可重播；不能用遊戲倍率或 party 疲勞重新改書信速度。
- **FA-33 多目標與取消**：多封信、多敵方、同刻簽約／開戰依固定順序；提案失效理由唯一，舊事件不能修改新 treaty。
- **FA-34 控制與開關**：加入情境勢力不成首長；kind 不授權；首長控制接續後舊 NPC decision 失效；無國家 duty_ai 與國家 duty_ai 遷移只有一個讀取來源。
- **FA-35 退化資料**：legacy 名冊無 leader、過期 locator、未映射國家、缺陷落史、未開 T6，不捏造首長／國籍／戰力／稅率。
- **FA-36 F1a 邊界**：只加名冊／顯示不動 faction／判敵／任官；F1b 玩家歸屬與 F2 以後各自取得證據，不能借 F1a PASS 宣稱完成。

## 9. 其他規劃需要配合的地方

本輪**只新增本規格檔**；以下是對既有文件的同步清單，不能標為已由本輪改完。

- [貿易規劃](reports/trade-plan.md) §5.5／T1-b／T6：改掉「新建 native 關係旗標」，沿既有 native matrix；F2 接 foundation，F6 提供唯一宣戰／講和命令，T6 接通商條款 consumer；同步无有效國家只能稅率 0、live／cold relation epoch、作業收束。
- [AI 與職位第二版](reports/ai-office-duty-integration-v2-plan.md)：對齊當前 R2 已有實作；補 stable ref↔原 social OrgRef 解析、解散原國家、家主／玩家控制／勢力首長三者區分、自立時任職者選邊。
- [AI 畫面外補充](reports/npc-ai-offscreen-addendum.md) §10A：原稿已記錄外交每日 caller 例外及冷 Site 背約事件；需補來源時刻、資格／控制變化、遲到日事件，維持不補造觀察／繼承／叛離日結算。
- [地圖編輯器](MAP_EDITOR_IMPLEMENTATION_PLAN.md) §9／P6：情境作者輸出 typed refs、faction registry、明示 nation mapping 與保留 ID；其現有草案的 world 唯一裸 ID 應先對齊已實作 travel stable ref，不能新增第三套 PersonRef。把 legacy 可空和新正式必填分清，仍保留 base／initial／current 分層。
- [聚落中心](SETTLEMENT_CENTER_LEVELS_PLAN.md)：建國地點必為當地 2 級；自立窄入口不等於 fall_to 全流程；版本化保存歷史陷落、不強迫史料 owner 等於現在。
- [Region 玩法](reports/region-gameplay-plan.md)：原 registry schema、事件種類、排序、共同 checkpoint、摘要與 cold consumer 列入政治區塊；外交不另有未受玩家屏障管控的時間。
- [主選單](MAIN_MENU_PLAN.md)：F1b 的自建／加入勢力需另驗初始世界交易與受控人物 faction，不回填為原 P1–P5 已通過內容。
- [專案架構](PROJECT_ARCHITECTURE.md)：程式真正落地並完成具名驗收後才更新「現行責任」，不能把本規格當既有系統登記。

## 10. 決定紀錄

來源已定 FQ 保留如下；本次沒有重新選案。

| 編號 | 已定內容 |
| --- | --- |
| FQ1 | A：一勢力最多一正式國家，正式國家必屬一勢力 |
| FQ2 | A：建國前名冊首長，建國後原元首 |
| FQ3 | 家族接任；首版限原批准本 Site 家族範圍 |
| FQ4 | A：首長人在本勢力擁有的 2 級以上聚落 |
| FQ5 | A：雙首長同意歸附；無人無建物無聚落才消滅 |
| FQ6 | A：整隊／整座聚落自立 |
| FQ7 | A：不另設中立平民勢力，異勢力預設敵對 |
| FQ8 | A：新建玩家勢力，也可加入情境勢力 |
| FQ9 | Taiwan 數量／名字／分布移出另案 |
| FQ10 | A：距離延遲書信；接受回信送達才生效 |
| FQ11 | A：hostile／peace，加停戰、通商；不做同盟 |
| FQ12 | B：外交只讀原首長野心 ambition、仁厚 mercy |
| FQ13 | A＋人格：NPC 只為收復已失聚落主動宣戰；被背約已成敵對，不重複宣戰 |
| FQ14 | A＋B：背約記錄／NPC 拒絕窗口，加本國民不滿事件 |
| FQ15 | A：Region 每遊戲日外交 caller，冷 Site 不載入、不直寫 |

V0.5 所列「全部定案」指以上玩法選項，不等於跨 owner 提交與相依功能都已存在或技術細節無缺口。

## 11. 外交

### 11.1 關係入口與權限

`SiteFactionRelations.hostile(a,b,context)` 為擬新增的無狀態入口名稱；context 由原 Slot 綁定，不另存一份關係。先驗合法當前 ID／alias；同有效勢力 false，不同勢力明示 peace 為 false，其餘 true。非法 ID／非 active 的命令輸入回錯，不能靠 lookup fallback 授權行動。

以無序 `(min_id,max_id)` 索引當前關係，保存 relation revision／生效 GAME 時刻；冷結算所需歷史版本／事件至少保留到所有 consumer 已越過其時間，不能跟 UI 最近 N 筆一起裁掉。

和平不開放倉庫或指揮權；人員實際移交、通商稅源、任官等另經原權限。active Site 在 relation 接受的同一事件端點失效選敵快取，下一個合法攻擊／占領／移動查詢用新版本。

### 11.2 協定

- **停戰：** 3–60 遊戲日的和平，`starts_at` 為接受回信生效時刻，`ends_at=starts_at+days×86400`。不是從發信／回覆時起算。
- **講和：** 無期限和平；可把有效停戰升為講和，原停戰到期事件保留收據但失去改關係的效力。
- **通商：** 必須當前 peace，稅率、適用方與稅源沿貿易 T6；獨立到期只終止通商。沒有有效國家／稅源 holder 的一方只能簽其適用稅率為 0 的條款。T6 未准入前不得生成不可執行的正式通商。
- **歸附：** 一次性合併交易；成功即 completed，不作永久 treaty buff；F4 未准入前不提供可接受的歸附。

同 pair 只允許一個當前和平基礎（停戰或講和），通商可疊在其上。停戰自然到期回 hostile 時同次終止該 pair 的通商、使基於舊和平授權的未完成交易合法收束；不記背約、不自動放俘。

### 11.3 書信距離 時間與唯一鍵

V0.5 將 `RegionTravel.party_speed` 稱作騎馬速度不準確：現有函式用最慢步行／車輛及疲勞。書信無真人、不用其 party 物資與疲勞模型。

**施工建議基線：** 沿現有 `RegionTravel.WALK_MPS=4000/3600` 米／GAME 秒作抽象書信固定速度，常數版本化；保留 FQ10 延遲設計，不稱為已存在的騎馬速度。未校準，之後調整只影響新發出的信件。

同 Site 的兩首長延遲 0；不同 Site 用 `RegionGrid` 既有投影下的 Site 中心直線米距離。首長在原 party／battle 時使用該 owner 可驗的 Region 位置，未有位置回 `LOCATION_UNAVAILABLE`，不退回出生 Site。距離使用 int64 毫米來源再轉米，不能把格數當米。

去程送達 `deliver_at = sent_at + distance_m / message_speed_mps`；回程在合法回覆當刻重取雙方位置，固定 `reply_deliver_at`。此後人員移動不追逐改道、不重算時刻；通信對象是勢力，所在位置只決定寄信當刻距離。快照保存端點與速度版本供重播。

收到後 7 日的回覆區間是 `[deliver_at, deliver_at+7×86400)`。**7 日限制回覆，不限制回信在途時間**；期限前回覆，超過第 7 日才到仍可提交，前提是接受授權仍有效。

唯一鍵為無序 pair＋proposal kind；去程、待回覆、接受／拒絕回程都占該鍵。拒絕送回提案方時進入 3 日同 pair／同 kind 冷卻；反向送信也不得繞過。同 ID 重送只返回原結果，不創第二事件。

### 11.4 提議狀態機

`outbound → delivered → reply_in_transit → accepted / rejected`；去程／待覆可轉 `invalidated`，待覆達期限轉 `expired`。已回覆回程不再用舊回覆期限取消，但仍受資格與世界變化重驗。

1. **提出：** 真首長授權、雙方 active、類型已開放、唯一鍵與冷卻、條款及來源完整；當刻即固定 proposer stable ref／authority，不能等回覆才補提案人。講和／停戰／歸附要求雙方當下無進行中戰鬥。原文「交戰中主動求和」改為「關係 hostile 且暫無實際交戰時提議」。
2. **送達：** 到原 Slot 事件端點才讓接收方可讀／回覆；同 Site 即時送達仍經相同事件入口，不遞迴繞過排序。
3. **回覆：** 重驗當前接收首長；受控者由 UI 明示，NPC 用同一 policy。保存提案人／接受人 stable refs、office／control／relation revision、原條款與回信端點；拒絕不改關係。
4. **生效：** 接受回信送達後重驗雙方當前首長仍為授權原人、在世清醒自由、權限有效、雙方 active、原提案未失效、戰鬥／條款前提仍成立。成功才同次寫 treaty／關係／歸附收據；失敗 invalidated，雙方獲具體原因。
5. **換首長：** 尚未回覆時，接收方新首長可決定；發信方換首長則原提案立刻失效，由新首長另提，不自動繼承舊人授權。已接受待送回時，任一授權首長換人、controlled 狀態或所需 authority 失效即作廢，須新提案同意。單純空缺也作廢全部非終態信件。
6. **競態：** 宣戰、合併、消滅、被其他協定取代都依 proposal／pair revision 失效舊接受，不能讓舊回信日後自動恢復和平。同刻競合規則見 §11.8。

任一前提不能從同批可信摘要／真 live owner 證明時，回明確缺資料／BUSY，不能載入 cold Site 偷跑政治。NPC 決策與提交使用同一來源契約；互動首長命令另需 live 當刻權限檢查。

### 11.5 宣戰與背約

合格首長對 peace 方單方宣戰，在當前合法 Region 事件端點立即生效，不經書信；不是繞過原玩家屏障的任意即時寫入。已 hostile 的重複宣戰返回原狀，不新增背約／不滿。

**對任何 peace 宣戰都背約**，包含情境和平和僅講和；無 active treaty 也可有空的作廢 treaty 清單。自然停戰到期不背約。宣戰同次終止該 pair 全部有效協定、失效非終態提案、更新 relation epoch、寫一筆 breach。下一個 Region 通知批次可見。

背約記錄含 ID、雙方歷史 faction ID、GAME 秒、原責任首長 stable ref、當刻原國家 ref、終止協定、受影響原國民集合／可驗來源。受害 NPC 30 日、其他 NPC 10 日內拒絕背約者所有提議；以半開時間 `[breach_at, breach_at+window)` 比較，多次事件取仍有效窗口。受控首長只見紀錄，不被 NPC 規則強迫拒絕；提案方向是「背約者提出」，不得錯誤懲罰受害者自己的提案。

**本國不滿沿 R2 原 owner：** 背約提交當刻排入 +5 事件，原國民且當刻已有有效 social state 者、首長本人除外；不是在外交 helper 直接改 G。引用轉接原社會 `{kind,site_id,org_id}` 必須經原組織 mapping，不能把 stable nation ref 原封塞進現行 local OrgRef validator。

以 `(breach_id, person_stable_ref)` 去重，責任屬事件當刻原國家／首長；受眾之後退國、旅行或換首長不改歷史責任。國家不存在、該人物無有效社會狀態或功能未准入時明記 skipped，不日後補建政治狀態。

外交 caller 不直寫 cold 人物；同次發布待投遞收據，回到合法原 owner 區間再沿 `SiteSocial.record`／日結算套用。**延後套用一個已發生事件，不等於補算離線日子。** 同人、同原國家、事件日的正向事件合計仍上限 20。

現有 R2 會把 `entry.day <= day` 的 pending 收進該輪日結算，故多個原日事件不能直接一次塞入再調整段 `settle_person`，那會錯合 +20 上限並補跑 decay／loyalty／omen。若已結算事件日、seen／pending 容量不足或遠端 OrgRef 不可解析，也不能遺失事件或改到今天避開原日上限。F6 需先在原 social owner 補「可證事件日更正」或保留未結算收據的合法入口，逐原日套用 +5 與該日已有正向量，**只套事件，不補未知日的其他政治結果**；未准入回明確阻擋，不能宣稱 FQ14-B 已完成。死亡受眾保留已終止／不再套用收據，不創死人政治運算。

### 11.6 NPC 首長外交

每遊戲日一次，沿原 Region evaluation event，記每勢力 `last_evaluated_day` 及來源 revision。暫停不跑，慢幀按已完成遊戲日順序處理；只有具有該端點輸入證據的區間能執行，不拿最新摘要補造數日前決策。

全體使用同一端點的政治摘要；先處理已到信件，再依穩定 faction ID 處理主動候選。每勢力每天最多一個主動提案／宣戰的施工基線：歸附→求停戰／升講和→收復宣戰；多目標在合格集合按 faction ID，無完整條件就略過。這是補充的確定性排序，不是改門檻。回覆可逐件按 proposal ID，不受一件主動額度限制。

`duty_ai=false` 不主動提案／宣戰，但仍按政策回覆；受控首長兩者都不代決。有國家讀原 nation offices，無國家讀 registry 的唯一開關；舊世界缺值預設 false，情境 NPC 明示設定，建國時一次交接到 nation，不雙讀。

兵力為同批摘要中本勢力**成年、活著、清醒、自由且原軍事資格允許作戰**的原人數；駕駛／乘員依原資格只計一次，俘虜不列可戰但仍列活人。這是政策估值，不等於同時在某戰場可用戰力。來源 unknown 則不作依賴比值的決策。

`r=self/enemy`：enemy>0 正常；self>0 且 enemy=0 視正無窮；雙方皆0視1。實作用整數交叉乘法／分支比較，不將 INF／NaN 寫入存檔。

只讀 `A=ambition`、`M=mercy`，值 0–100，缺合法舊人格包沿原 neutral 50。非法包由原 validator 拒絕；不讀野心以外軍事人格來偷偷改門檻。

| 決策 | 規則，全部還須 §11.4 合法性 |
| --- | --- |
| 回覆講和／停戰 | 對方不在背約窗口；連續 `D=3×(1.5−M/100)` 日沒有實際交戰；`r < 3−2A/100` |
| 回覆通商 | 當前 peace、無背約窗口、條款通過 T6；提案稅率不高於本方原 T6 同類要約稅率。無可驗稅率來源就拒絕，不以空資料當 0或虛構稅率 |
| 回覆歸附 | 無背約窗口，且 F4 所有前提可提交才接受；不是無條件接受 |
| 主動求和 | hostile 且沒有進行中交戰，`r < 0.5+(M−A)/200` 時提15日停戰；有效停戰剩≤3日且>0時提講和，仍受信件唯一鍵／簽署前提 |
| 主動歸附 | 依完整摘要，已無聚落或 `r<0.1`；不是把缺聚落資料當0；目的勢力須有合格首長且 F4可接收 |
| 收復宣戰 | 對方目前 peace 且持有本勢力可證陷落聚落；`A−M≥0`、`r≥1.5−A/100`、和平／最近簽約已滿10日 |

「沒有實際交戰」需 pair 級戰鬥活動／結束收據，包含 live combat／未完有效攻擊與 Region battle／siege；未知不當作無戰鬥。現有 Site 共用 `combat_left` 會受其他戰鬥／攻城／火場影響，不能把它直接當特定兩勢力正在互戰或最後停戰時間。既有 hostile 關係本身不算持續作戰。D 窗口從最後可證戰鬥結束計，無已證歷史的舊世界從政治摘要建立時起算，不捏造已停戰幾天。

剩3日提講和不保證雙程書信來得及；仍依 FQ10 正常延遲，不延長停戰、不偷提早生效。先自然到期後才到的已接受講和回信，若舊停戰自然到期之外沒有新授權變更、無實際交戰且其他前提仍成立，可在送達時建立新和平；兩者間的敵對區間如實保留。此為 pair revision 重驗的明示可接受轉換，須有原到期收據證明僅此變更，不能一律忽略版本差異。宣戰／背約或其他事件造成的失效則不能被舊回信復活。

收復 10 日以雙方最近生效協定與 `peace_since` 的較晚者為基準；只有情境和平也有 peace_since。現有 `last_fall` 只保留最近一次，不足以反推全歷史：遷移只匯入可證事件，之後沿原 fall_to 成功收據更新追索紀錄；歷史 faction aliases 解析與現在 owner 分開。不得憑曾經駐軍推定領土。

人格中性 `A=M=50`：D=3日、接受 r<2、主動求停戰 r<0.5、收復 r≥1；門檻等號依表。宣戰後仍記背約與不滿，派兵由原 `nation.dispatch`／Region AI 決定，外交不移隊。

原文「每軸每條只用一次」與收復同時用 A−M 及兵力門檻不相容；修訂為**每次固定讀同一首長的一份 A／M，按已定公式使用，不追加額外倍率**，不刪既定任一門檻。

### 11.7 玩家外交

WORLD／Site 入口共用同一命令，不各寫一份檢查。只有原受控人物確為目前勢力首長才可操作；加入某勢力或 `kind=player` 都不充分。

可查看關係、協定、歷史背約、自己寄出／已收到信件；送達前接收端查詢也不返回條款，不能只靠 UI 隱藏。收到／接受回信生效／拒絕／作廢／將到期／宣戰通知按事件去重；「接受中」不顯示已和平。

### 11.8 事件 資料與保存

`diplomacy` 至少含 `version / revision / next_id / proposals / treaties / breaches`，冷卻／日評估游標／去重收據納原 owner。ID 不重用；每筆狀態、條款版本、原授權、端點、pair revision、結果理由必經驗證。

**當前與歷史驗證分開：** 新提案、有效 treaty／relation 的雙方須 active；完成／作廢提案、終止 treaty、breach 可引用永久名冊 tombstone。不能一面保存歷史，一面要求所有歷史雙方永遠 active。

事件沿原 `RegionGameplayClock` 擴充 schema／種類／priority／排序，必須經原 next_endpoint 截斷與玩家屏障；不另開 Timer。保留原玩家屏障與 life／supply／work／attack→arrival→battle 的先後，外交在這些同刻原 owner 結果可見後處理，再進當日 AI evaluation。

外交同刻施工基線：已接受的明示命令（含宣戰）→回信生效→協定到期→去程送達／回覆期限→NPC 日評估，同類按原穩定 owner／sequence。先重驗資格與 pair revision；同刻講和回信在舊停戰到期前取代它，同刻宣戰先使舊回信失效。新生成的零延遲事件在同刻按同規則排空，避免跳到下一天或無限同刻提案。邊界固定後，以 FA-13／28／29／32／33 驗證，不依幀順序。

UI 終態紀錄施工基線各留最近 100 筆；**仍被未到回信、cooldown、社會收據、cold relation replay 或追索領土使用的紀錄不得裁掉**。其長期需求保存最小引用／水印，不因清 UI 丟權威。未定所有 consumer 的可回收水位前只做有界新增守衛，滿額拒絕新提案並回 `DIPLOMACY_CAPACITY`，不得靜默吞既有事件。

## 12. 審核發現與修正對照

本節行號是本次讀取快照；施工時以函式符號重新定位。P1 表示會破壞身分、權限、保存或使已定玩法無法執行，P2 表示不一致／邊界未定。

1. **FR-01 P1 穩定引用寫錯。** `region_travel.gd:53/125/241`（validate_identity／prepare_identity／validate_arrival_mapping）、`site_equipment_orders.gd:2728/2908`（_portable_ref／prepare_region_arrival）。已修 §1.2／3.1／3.2／11.3；FA-20。
2. **FR-02 P1 合併與保存未覆蓋所有 owner。** `region_save_slot.gd:541` _publish、`:2845–2886` 共同 checkpoint、`:3707` NPC party 保存。已修 §4.2／5.3；FA-06／09／24。
3. **FR-03 P1 冷 alias 範圍不足、歷史欄位會驗證失敗。** `site_store.gd:1282` _read、`:2068` remote corps、`:3284` prison/captor；`site_settlement.gd:77–83` 歷史 owner 耦合。已修 §4.2／5.2；FA-22／23。
4. **FR-04 P1 摘要不足以滅亡／算兵力。** `region_save_slot.gd:1530` known_saved_sites、`:1741` building_summary、`:2428/2918` party owner；原文只有聚落摘要。已修 §3.1／4.3／11.6；FA-07／30。
5. **FR-05 P1 國家解散不能刪表完事。** `site_equipment_orders.gd:2854–2877` 原國家／membership 出行、`:2928` 跨地抵達引用。已修 §4.2；FA-24。國庫／科技／公務解散是 F4 明確准入依賴，未提供成功實作證據。
6. **FR-06 P1 首長接任混用控制接續。** `site_family_continuity.gd:71/85` head_executor／appoint_head；原 choose 是受控人物出口。已修 §3.3；FA-04／20／34。家主繼承入口未完成不可假稱已有。
7. **FR-07 P1 建國正文違反 FQ4。** 原 V0.5 §4.1 將地點與 2 級分開，§10 FQ4 卻要求同地。已修 §4.1；FA-05，不改既定選項。
8. **FR-08 P1 分裂盲保留職位會失格。** `site_settlement.gd:68–71/407–436` 檢查首長同方、fall_to 清 office／住宅／訓練且保留有原守方引用建物。已修 §4.4；FA-08。
9. **FR-09 P1 F2／F6／T1-b 循環。** 原 faction §7 F2=貿易 T1-b、F6依F2，貿易T1-b又要求F1–F2，公開講和卻依F6書信。已修 §7／9；不加即時講和旁路。
10. **FR-10 P1 判敵清冊與 native 假設不完整。** `terrain_lab.gd:2599/2632/3536/5945` MOVE／近戰／遠射／火箭；`site_person_actions.gd:520/599` 攻擊建物／車輛；`native/army_idle/army_idle.cpp:1419`；`native/crowd10k/tests/scenario_tests.cpp:559–575` 已有外交旗標測試。已修 §1.3／5.4／11.1；FA-25／26／27。
11. **FR-11 P1 背約不滿時點與冷事件不完整。** `site_social.gd:59–68/72–113` 原人 pending／日結算／去重與上限；來源 FA-19 原稱提交直接G+5。已修 §11.5；FA-19／31，需補遲到事件准入。
12. **FR-12 P2 書信來源與期限矛盾。** `region_travel.gd:38–39/717` 非騎馬速度；`region_grid.gd:4–7/18–31` 毫米地理單位。已修 §11.3–11.4；FA-10／28／32。
13. **FR-13 P2 AI 門檻缺零分母、快照和可執行提案時機。** 原「交戰中求和」與發信前無戰鬥矛盾；`person_personality.gd:7–30` 確認 A/M 0–100 正確，保留公式。已修 §11.6；FA-15／16／18／30。
14. **FR-14 P2 歷史與驗收版本未同步。** 原 FA-14 漏純講和／情境和平背約；FA-17／§11.8 要求歷史雙方active與保留紀錄矛盾；連續合併直接active亦不封閉。已修 §4.2／8／11.5／11.8；FA-14／17／22／29。

## 13. 施工前清單與交付界線

施工時先列實際 caller 清冊，至少涵蓋 `scripts/terrain_lab/{terrain_lab,site_controller,site_army_ai,site_person_actions,site_settlement,site_store,site_equipment_orders,site_family_continuity,site_social,site_resource_view,crowd_site}.gd`、`scripts/region_lab/{region_save_slot,region_travel,region_travel_site,region_gameplay_clock,region_gameplay_battle,region_gameplay_ai}.gd`、C# candidate kernel、army_idle 與 Crowd native；新建 helper 只做查詢／候選，不取代原 owner。

優先擴充現存測試，再為新契約加最小必要案例：

- [region_organization_portable_test.gd](scripts/tests/region_organization_portable_test.gd)、[region_travel_test.gd](scripts/tests/region_travel_test.gd)、[region_gameplay_travel_test.gd](scripts/tests/region_gameplay_travel_test.gd)：stable refs、在途 owner、移交／恢復。
- [region_gameplay_clock_test.gd](scripts/tests/region_gameplay_clock_test.gd)、[region_gameplay_snapshot_test.gd](scripts/tests/region_gameplay_snapshot_test.gd)、[region_initial_world_transaction_test.gd](scripts/tests/region_initial_world_transaction_test.gd)：端點／共同保存／初始世界。
- [site_region_building_summary_test.gd](scripts/tests/site_region_building_summary_test.gd)、[site_settlement_center_test.gd](scripts/tests/site_settlement_center_test.gd)：摘要來源、陷落、建國地點／分裂守衛。
- [site_family_continuity_test.gd](scripts/tests/site_family_continuity_test.gd)、[site_family_offices_test.gd](scripts/tests/site_family_offices_test.gd)、[site_social_r2_test.gd](scripts/tests/site_social_r2_test.gd)：控制／家主／首長、原政治事件。
- [site_exchange_batch_test.gd](scripts/tests/site_exchange_batch_test.gd)、[site_encirclement_columns_test.gd](scripts/tests/site_encirclement_columns_test.gd)、[site_move_encounter_lab_test.gd](scripts/tests/site_move_encounter_lab_test.gd)、[site_siege_takeover_ai_contract_test.gd](scripts/tests/site_siege_takeover_ai_contract_test.gd)、[region_gameplay_battle_test.gd](scripts/tests/region_gameplay_battle_test.gd)：判敵與同方支援分離。
- [native Crowd scenario_tests.cpp](native/crowd10k/tests/scenario_tests.cpp)：既有 native 關係旗標案例；需另驗 host同步／ID映射，不能當 Slot 外交已通過。

本輪只讀程式、既有計畫與來源稿，建立此規格並檢查章節、引用、FQ／FA 編號及公式邊界。未修改 gameplay／schema／其他計畫，未執行 Godot、native、GPU、真存檔遷移或效能測試。

文件自檢（2026-10-08）：§0–13 共14章、FQ1–FQ15、FA-01–FA-36、FR-01–FR-14 連續且無重號，27個本地連結目標存在。9組 A/M 邊界組合、中性4項門檻、2個書信速度換算和3個日秒換算通過。這只驗文件結構與數學，不是執行外交 policy 或既有測試通過。

**可採用的結論：** FQ 玩法決定保留，修訂規格可作 F1a 施工及各包准入清單；F2–F6 仍按前置逐包實作與驗收。文件結案不代表外交功能、冷政治、Native 或正式發布完成。
