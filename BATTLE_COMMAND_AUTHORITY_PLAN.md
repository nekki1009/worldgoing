# Battle 指揮權、延遲命令、可攔截傳令與隊長自治實作計畫

狀態：已加入傳令攔截規則，待批准後實作

本文件只定義下一階段的實作邊界；本輪不修改 Battle 玩法程式。`PROJECT_ARCHITECTURE.md` 仍是專案架構真實來源，本文件只提供 Battle 指揮系統的落地順序與驗收條件。

## 0. 本次再審查結論

原計畫只描述傳令抵達與失敗，沒有明確讓傳令兵在途中成為可被敵方 Formation 攔截的 runtime 物件；這不足以實現「傳令兵可以被攔截」。本次修正如下：

- `BattleDispatchData` 代表一名正在傳遞精細命令的傳令兵，擁有目前公尺位置、路徑進度、速度與 delivery state；它是 data-only，不是個人 NPC／Node。
- 傳令兵沿既有 Battle pathfinder 路徑移動；每個 `advance_battle()` tick 依序檢查起點、移動線段攔截，最後才判定抵達。
- 被攔截時命令狀態變為 `MESSENGER_INTERCEPTED`，記錄攔截者與位置，精細命令永不套用；簡單命令與指揮官本隊的直接精細命令不產生傳令，因此不適用此攔截規則。
- 攔截判定檢查傳令本 tick 移動的整段線段，而不是只看 tick 結束點，避免大步進時間更新時穿過敵隊卻漏判。
- `issue_order()` 只回報「已建立傳令」；抵達、攔截或目標失效是非同步終態，透過 `query_order(order_id)`／Debug 狀態查詢，不把晚到結果偽裝成同一個立即回傳值。
- `BattleSiteMap` 只顯示傳令位置與攔截結果；Runtime 才擁有移動、攔截、抵達與命令失敗判定。

這個修正保留既有最小化邊界：不建立傳令兵 AI、物理 body、NavigationAgent 或全域 Command Bus。

## 1. 目前實作審核結果

目前 Battle 已有九個 Site base、Session-owned `BattleRuntimeState`、100 人 Formation、Formation 移動與每人 `MultiMesh` 視覺，但尚未有指揮權或命令傳遞層：

| 現有 owner | 目前責任 | 本計畫的延伸 |
| --- | --- | --- |
| `BattleParticipantData` / `BattleSiteContext` | 參戰方、兵力、入口方向與 9,000 人總上限 | 增加 PC/NPC 指揮官身份與指揮官 Formation 定義 |
| `BattleFormationData` | 100 人 Formation 的位置、朝向、路徑與狀態 | 增加「指揮官本隊／一般隊伍／隊長自治」所需的最小標記 |
| `BattleRuntimeState` | Session 內的 Formation authoritative state | 擁有待執行簡單命令、傳令位置／路徑／攔截狀態、接敵狀態與命令時間 |
| `BattlePreviewRuntime` | Battle 建立、重新驗證、Formation 命令與時間推進 | 唯一的命令驗證、延遲計算、傳令移動／攔截／抵達與隊長決策執行 owner |
| `NavigationController` | Battle view 建立、Runtime 呼叫與 refresh | 只轉送帶有來源身份的 typed order，不決定誰可指揮 |
| `BattleSiteMap` | 選取、畫面與輸入意圖 | 顯示控制權／延遲／傳令狀態，只發出 order intent，不直接改 Formation |
| `BattleRuntimeResult` | Typed Battle 命令結果與錯誤碼 | 增加指揮權、order id／狀態、延遲、傳令路徑與接敵自治結果；`query_order()` 重用此 typed result，不新增服務層 |

目前 `BattleFormationData.is_controllable()` 以「攻擊方」判斷可控，這不符合新規則；實作時必須移除這個 side-based shortcut，改由 Runtime 根據命令來源、指揮官身份與目標 Formation 判斷。

## 2. 必須維持的設計不變量

1. PC 預設是己方參戰方的指揮官。PC 身份以 `GameSession.party.party_id` 對應 `BattleParticipantData.commander_id`，不新增全域 Singleton。
2. NPC 指揮官使用完全相同的指揮規則；差別只有 `commander_kind` 與命令來源，不另建一套 NPC 指揮框架。
3. 指揮官自己的 Formation 可以立即執行精細命令；其他 Formation 不可被直接瞬間控制。
4. 其他 Formation 可先接收高階簡單命令，但命令必須經過可重現的通訊延遲。
5. 精細命令必須建立可移動、可攔截的傳令資料；傳令抵達目標 Formation 後才可執行，抵達前不得偷套用目標位置、朝向或目標鎖定。
6. Formation 仍是唯一的移動／模擬單位；傳令與隊長是 data-only runtime state，不建立個人 Soldier、NPC、AI 或 Navigation Node。
7. 直接接敵時，隊長的局部決定暫時優先於遠端命令；完整傷害、士氣與戰鬥結算仍不在本階段。
8. Region、Site、300m Battle composite、100 人 Formation、9,000 人上限與現有 MultiMesh 個人視覺契約不變。

## 3. 命令模型

### 3.1 指揮身份

在 `BattleParticipantData` 增加最小欄位：

- `commander_id: String`：PC 或 NPC 指揮官穩定身份。
- `commander_kind`：`PLAYER`／`NPC`。
- `commander_formation_index: int`：預設為 0，明確指出該方哪一個 Formation 是指揮官本隊。

在 `BattleFormationData` 增加：

- `is_commander_formation: bool`：建立 Formation 時由 Runtime 設定。
- `captain_id: String` 或等價穩定欄位：隊長自治事件的來源標記。
- 接敵／自治所需的最小狀態，例如 `contact_target_id` 與 `autonomy_state`；不要把隊長擴成個人 AI。

Runtime 只允許每一方有一個指揮官本隊。若身份缺失、指揮官 Formation 索引越界或同方出現多個指揮官本隊，Battle 建立直接回傳 typed failure。

### 3.2 簡單命令

第一版只提供五種高階 intent：

- `ADVANCE`：前進。
- `FALL_BACK`：後退並保持接觸距離。
- `ATTACK`：向敵方或指定敵方 Formation 接近攻擊。
- `WITHDRAW`：撤退至己方入口／指定撤離區。
- `FLANK_REAR`：繞至敵後；只傳達意圖，不把精確路徑當成命令內容。

對指揮官本隊，簡單命令可立即轉成 Formation intent。對其他隊伍，Runtime 建立 `execute_at`，使用固定基礎延遲加上指揮官與目標 Formation 的距離／通訊速度計算；在時間到達前不得改變目標 Formation 的 intent。

簡單命令不需要建立可見傳令個體，避免把每一個高階 intent 都擴成昂貴的 Agent；但延遲仍必須在 `BattleRuntimeState` 中可查詢、可測試、可顯示。

### 3.3 精細命令

第一版精細命令限定為：

- `MOVE_TO`：指定精確公尺位置。
- `SET_FACING`：指定精確朝向。
- `HOLD_POSITION`：指定位置與保持時間／直到新命令。
- `FOCUS_TARGET`：指定敵方 Formation 作為目標。

精細命令使用一個 typed `BattleOrderData` 加上一個 data-only `BattleDispatchData`：

`BattleOrderData` 至少包含：`order_id`、來源 commander／formation、目標 formation、order kind、payload、issued_at、狀態。

`BattleDispatchData` 至少包含：`order_id`、傳令起點、目前 `position_m`、上一 tick 的 `previous_position_m`、目標 Formation、既有 Battle path、path index、`speed_mps`、預估抵達時間、delivery state、`intercepted_by_formation_id` 與 `intercepted_at_m`。

傳令路徑重用 `BattlePreviewRuntime` 現有的 `WeightedGridPathfinder` 與地形通行／速度資料。傳令抵達才將 `BattleOrderData` 放入目標 Formation 的可執行佇列；無路徑時回傳 `NO_MESSENGER_ROUTE`，不得退化成瞬間套用。

`issue_order()` 成功時只回傳 `order_id` 與 `DISPATCH_CREATED`。新增 read-only `query_order(order_id)`，以現有 `BattleRuntimeResult` 回傳 `QUEUED`、`EN_ROUTE`、`DELIVERED`、`INTERCEPTED`、`TARGET_UNAVAILABLE` 或 `FAILED`；Battle 結束前保留必要的終態資料供 UI 與測試讀取。

### 3.4 傳令攔截規則

- 只有敵方 Formation 可以攔截傳令；己方 Formation、地形細節與簡單命令不會誤觸發攔截。
- 傳令開始移動前先檢查目前位置；之後每次沿 path 前進，使用 `MESSENGER_INTERCEPT_RADIUS_M` 與「上一位置到目前位置的線段」對敵方 Formation footprint／中心距離做 deterministic 判定。第一版採固定半徑與既有 Formation 佔位資料，不建立物理碰撞系統。
- 若同一時間有多個敵方 Formation 可攔截，依距離最短、再依穩定 `formation_id` 排序取一個攔截者，保證重跑結果一致。
- 攔截後 `delivery_state = INTERCEPTED`，記錄攔截 Formation 與位置；`query_order()` 回傳 `MESSENGER_INTERCEPTED`，目標 Formation 不會收到精細 payload。
- 攔截不自動重派、不複製命令；未來若要重派，必須由指揮官重新下達新 order。這避免隱含的無限重試。
- 同一目標 Formation 同時只允許一個 `EN_ROUTE` 精細傳令；新的精細命令回傳 `ORDER_IN_TRANSIT`，不在第一版引入取消／取代競賽。

## 4. 權限與命令流程

所有命令都走同一個 Runtime typed API，建議入口為：

```text
BattlePreviewRuntime.issue_order(source_id, target_formation_id, order)
```

Runtime 依下列順序驗證：

1. Battle 是否仍 active、來源身份是否屬於己方指揮鏈。
2. 目標 Formation 是否存在、是否同方、是否已被摧毀或離場。
3. 來源是否為該方指揮官，以及目標是否為指揮官本隊。
4. 若是指揮官本隊：簡單／精細命令立即套用。
5. 若是其他隊伍且為簡單命令：建立延遲命令，時間到才套用高階 intent。
6. 若是其他隊伍且為精細命令：建立傳令，抵達才套用精確 payload。
7. 每次 Battle tick 先更新 Formation 與接敵狀態，再更新傳令的移動線段；只有線段未被攔截且傳令抵達目標時才套用精細 payload。
8. `query_order()` 讀取傳令終態；攔截不透過延遲的同步回傳值冒充即時成功或失敗。
9. 若目標正處於直接接敵自治：命令保持 queued／deferred，不直接奪回隊長控制權。

`NavigationController` 只把 PC 身份與 UI order intent 轉交給此 API；NPC 指揮官測試則使用同一 API 但以 NPC `commander_id` 作為來源，確保規則不依賴 `Side.ATTACKER` 或 UI。

## 5. 直接接敵與隊長自治

### 5.1 接敵判定

在既有 `advance_battle()` 的 Formation 移動後加入最小接敵檢查：

- 以敵我 Formation 的 footprint／中心距離判定是否直接接觸。
- 只在狀態由未接敵變為接敵時建立一次自治事件，避免每幀重複下令。
- 接敵判定與結果留在 `BattleRuntimeState`，不由 `BattleSiteMap` 判斷。

### 5.2 隊長決策

接敵後由目標 Formation 的隊長產生 `CAPTAIN_AUTONOMY` 決策。第一版只決定局部 intent，不做傷害結算：

- 已收到 `ATTACK` 或敵方進入接觸範圍：`ATTACK`／保持接觸。
- 已收到 `FALL_BACK` 或 `WITHDRAW`：朝安全方向脫離。
- 沒有明確命令：`HOLD`，直到接敵狀態改變。

隊長自治的優先順序高於尚未抵達的精細命令，但不刪除該命令；接敵解除後由 Runtime 再決定是否恢復。這讓「直接遇敵由隊長下決定」可觀察、可測試，也不提前引入完整 AI。

## 6. 實作階段

### Phase 0：契約與測試夾具

- 擴充 `BattleParticipantData`／`BattleSiteContext` 的指揮官欄位與驗證。
- 將 debug Battle fixture 明確標記 PC commander；新增 NPC commander fixture。
- 移除 `is_controllable() == attacker` 的既有假設，先保留 typed `NOT_CONTROLLABLE` 失敗碼相容性。
- 先建立 command／dispatch／authority 的最小資料型別與 enum，不接 UI。

驗收：PC 與 NPC 各有一個指揮官本隊；攻擊方／防守方不再決定可控性；無效 commander identity 被拒絕。

### Phase 1：指揮官本隊直接控制

- `BattleRuntimeState` 記錄雙方 commander formation。
- `BattlePreviewRuntime.issue_order()` 完成來源、同方、目標與本隊直接控制驗證。
- 既有右鍵移動只保留為本隊 `MOVE_TO` 的最小精細命令。
- 將目前 Formation movement 測試改成驗證「PC 本隊可立即移動，非本隊不能以右鍵瞬移」。

驗收：PC 與 NPC commander 的本隊都能立即套用精細命令；任何 subordinate 目標不會因為是 attacker 而直接可控。

### Phase 2：簡單命令延遲

- 加入五種簡單 intent 與 `BattleRuntimeState.pending_orders`。
- 在 `BattleRules` 集中保存基礎通訊延遲／通訊速度常數，避免散落在 Scene。
- `advance_battle()` 到達 `execute_at` 才套用 subordinate 的簡單 intent。
- Debug panel 顯示 queued、remaining delay、已套用 intent。

驗收：命令提交後目標保持原 intent；時間未到不執行；時間到只改變高階 intent，不產生精確路徑偷跑。

### Phase 3：傳令與精細命令

- 加入 `BattleOrderData`／`BattleDispatchData` 的 queue 與 typed result codes。
- 傳令重用既有 Battle pathfinder 與地形速度，逐步更新 path／ETA。
- 在 `BattleRules` 集中保存 `MESSENGER_SPEED_MPS` 與 `MESSENGER_INTERCEPT_RADIUS_M`，不把攔截調整值散落在 Scene。
- 傳令擁有可查詢的 `position_m` 與 delivery state，沿 path 移動而不是只等待一個計時器。
- 每次 tick 在傳令抵達前檢查上一位置至目前位置的移動線段與敵方 Formation 攔截半徑；攔截即結束傳令並讓 `query_order()` 回傳 `MESSENGER_INTERCEPTED`。
- 傳令抵達才執行 `MOVE_TO`、`SET_FACING`、`HOLD_POSITION`、`FOCUS_TARGET`。
- 在 BattleSiteMap 以現有 MultiMesh／debug text 顯示傳令位置、剩餘時間與攔截結果；不建立傳令 Node。

驗收：抵達前精細命令不生效；傳令可在途中被敵方 Formation 攔截；即使一次 tick 跨過敵隊也不能漏判；攔截後 `query_order()` 回傳唯一終態且命令不執行；抵達後只執行一次；無路徑與目標失效都有 typed failure；PC／NPC 使用同一流程。

### Phase 4：接敵與隊長自治

- 加入接敵狀態、隊長自治 intent 與命令優先順序。
- 接敵只觸發一次自治決策；接敵解除後恢復 queued 命令判斷。
- 暫不加入傷害、死亡、士氣、個人 AI 或戰鬥結算。

驗收：直接接敵時隊長決策先執行；遠端精細命令不會奪回控制權；接敵事件不產生個人 AI／Soldier Node。

### Phase 5：Presentation、文件與回歸

- `BattleSiteMap` 顯示五種狀態：`DIRECT`、`SIMPLE_DELAY`、`MESSENGER_EN_ROUTE`、`MESSENGER_INTERCEPTED`、`CAPTAIN_AUTONOMY`。
- 更新 `PROJECT_ARCHITECTURE.md` 與 `ARCHITECTURE_STATUS.md` 的 Battle boundary。
- 保留目前 100 人 Formation、9,000 人 MultiMesh、Region／Site 尺寸與 Persistence `BATTLE_ACTIVE` 拒絕契約。

## 7. 必要測試

在 `scripts/tests/battle_site_test.gd` 延伸以下 focused checks：

1. PC commander 本隊的精細命令立即生效。
2. NPC commander 本隊的精細命令也立即生效。
3. PC／NPC 對 subordinate 發出精細命令時建立傳令，抵達前不生效。
4. 五種簡單命令均能排入延遲佇列，時間到才套用。
5. 不同地形／距離產生 deterministic delay；相同輸入重跑結果一致。
6. `issue_order()` 建立傳令後，`query_order()` 只回報正確的非同步狀態轉移。
7. 傳令沿 path 移動，敵方 Formation 進入攔截線段半徑時回傳 `MESSENGER_INTERCEPTED`，且精細命令不執行。
8. 一次大步進時間跨過敵隊時仍可攔截；攔截者排序與結果 deterministic。
9. 簡單命令與指揮官本隊直接命令不會產生可攔截傳令；同一目標的第二個精細命令回傳 `ORDER_IN_TRANSIT`。
10. 傳令無路徑、目標不存在、敵我不同方、非指揮官來源都回傳 typed failure。
11. 直接接敵觸發一次隊長自治，且不建立個人 Soldier／AI／Navigation Node。
12. 既有 100 人 Formation、9000 人 MultiMesh、五隊一列、Region → Battle → Region 回返測試仍通過。
13. 靜態依賴檢查持續保證 `BattleSiteMap` 不依賴 Runtime owner，Runtime 不依賴 Scene／UI。

此外執行既有 editor parse、`git diff --check`、Persistence、Site Runtime、Runtime command/query 與 architecture smoke 測試；Godot 的環境錯誤或 timeout 必須單獨標示，不能當成 PASS。

## 8. 明確不在本階段

- 不建立全域 Command Bus、CQRS、Event Bus、權限 DSL 或新的 Battle Manager。
- 不建立每名士兵、傳令兵或隊長的 Node、NavigationAgent、物理 body 或個人 AI。
- 不把傳令攔截擴成完整潛行、視野、追逐或捕虜系統；第一版只做固定半徑的 deterministic interception。
- 不實作傷害、死亡、士氣、補給、戰後結算與 Battle persistence。
- 不讓 `BattleSiteMap` 直接修改 Formation、pending order 或 messenger state。
- 不改變 World／Region／Site ownership、Site 100m × 100m 邊界、Battle 300m × 300m composite 或 9,000 人總上限。

## 9. 完成定義

本計畫完成時，使用者能清楚看到並測試：

- PC 是指揮官，但只有 PC 本隊可立即精細控制。
- 其他隊伍收到的是延遲中的簡單 intent；精細命令會顯示傳令中，傳令到達後才執行。
- 傳令在途中可能被敵方 Formation 攔截；被攔截的精細命令不會執行，且不會自動重派。
- 把 PC 換成 NPC commander 不改變上述規則。
- 直接遇敵時由隊長先做局部決定，遠端命令不會瞬間奪權。
- 所有狀態都由 Session／Battle Runtime 保存，畫面只是 detached snapshot 的呈現。
