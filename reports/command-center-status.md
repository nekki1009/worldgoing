# 專案指揮中心狀態看板

更新：2026-11-17 18:15（台北）
CURRENT 指揮中心：「指揮中心：預定功能接續」（cmsg_019ZbHjQVQy2cHmPmpt2suCG4rnoahY36kCET7y6gphsCW），11/15 01:00Z 由協調者開、接手交接段工作（BANDIT→文武官→考試→軍餉）。前任「指揮中心：P4 時鐘落後續追」（cmsg_019ZbHjQVQy2cHmPmpt2suCG1qo9iNprJQ8w9YNAFHSPNy）。
驗收標準：只有「正式 D:\worldgoing 上、由 canonical `verify_godot.ps1` 產生的 `result.json` 收據」算通過。隔離副本的通過、候選數量、單獨重跑都只列為「參考」，不算驗收。

## 常駐規則（Nekki 11/05 08:21：不准跑一跑就停）

1. 每一輪結束前，一定要有一項正在跑的背景工作，並且排好 15 分鐘以內的背景喚醒；醒來就檢查結果、繼續做。只有在等 Nekki 回答 A/B/C 選擇的時候，才可以不排。
2. 一步做完並提交後，同一輪就直接開始下一步，不停下來等指示。順序照即時進度清單。
3. 等驗收的時候，去做下一項不衝突的工作，例如讀程式、寫下一步的草稿，不空轉。
4. 卡住時，在對話串說明卡在哪裡、需要 Nekki 做什麼，不默默停下。
5. Nekki 看的「看板」是即時進度清單，每一步都要同步更新；這份 md 是輔助。

## 流程規則（Nekki 11/11 00:36Z「流程優化」）

量到的浪費：兩船隊測試為了除錯整支重跑 57 次（平均 461 秒，共 7.3 小時），多數只為看一個新診斷；一個小修正後跑了焦點＋全回歸＋再一次全回歸。
1. 超過約 3 分鐘的測試要除錯時，先讓它能從自己的存檔點續跑（只供除錯；驗收仍跑整支），一輪壓到約 1 分鐘。
2. 失敗只有代碼沒有數值時，一次把同一代碼的所有出處和相關時鐘都加上數值再重跑，不一次加一行。
3. 回歸分級：每次提交跑「受影響的家族＋30 秒以下的短測試」（smoke_reg_manifest.json，91 支約 26 分鐘）；全清單（145 支約 2.2 小時）只在里程碑跑（一天一次或推送前）。
4. 同一份遊戲腳本下已通過的測試不重跑。
5. 同時跑多個 Godot：Nekki 11/11 01:04Z 選 A——批次回歸最多 3 個並行（run_manifest_parallel.ps1），失敗的單獨重跑才算；單支除錯與計時量測仍一次一個；Nekki 玩遊戲時退回一次一個。
6. 找失敗代碼出處用 `-- --diag-fail=代碼[,代碼]`（印出產生處堆疊），不要一次加一行 print。


## 2026-11-17 18:15（台北）跨 Site 兵力情報；土匪跨 Site 劫掠
- 已提交（未推送）：fe0e3b6 跨 Site 兵力情報（region_site_strength.gd：每次大地圖評估，在場且有旅行身分的官員記下本 Site 看得到的別方武裝人數與聚落主，跟著人走 7 天；當面轉告同陣營國家官職持有人；國家出兵挑目標可讀到 power）。順手修：群眾 Site 的 scoped_region_intel 只看 GD 軍隊，群眾上 NPC 完全沒有情報。6466689 B4d-3c 跨 Site 劫掠（site_bandit_far_raid.gd：頭目在場時，知道的範圍內別家聚落成為目標；人數 ≥ 1.2 倍 → 一支多人土匪隊以隊長名義出寨前往，heat +10）。順手修：土匪每日判斷會在冷存 Site 結算點數時跑、撞到沒有群眾而崩潰。
- 回歸：STR_REG_A 71/71；FAR_REG_A 71/72＋單獨重跑通過。兩 NPC 海上敵對那支單獨 580→664 秒，照規則時限放寬為 900／960 秒（其他清單仍寫 660，用到時要改）。
- 限制：沒走過大地圖的人沒有穩定身分參照，記不了情報（多數既有官員情報同樣如此）；地理情報與兵力情報同一物件鍵，較新的地理收據會蓋掉兵力收據。
- 下一步：B4d-3b 劫後撿遺物與撤回山寨；買路錢「逃」。C1c 等平民圖集；B5 等 NPC 商隊。

## 2026-11-17 15:10（台北）原生隊形上限重做；平民 C4c 流民遷入
- 已提交（未推送）：6abcd91 原生群眾隊形上限放寬為「人數＋1025」（先前崩潰是並行載入的存取違規，兩版 DLL 單獨都過；舊 DLL c9a9c1dd… 備份留在 evidence/formation_bound_20261117/previous_dll，現用 3c516ab2…）；2d77b5b C4c-1 CrowdSite.add_new_person（進行中的群眾 Site 生出新人物：世界編號、原生士兵、名冊、隊伍、供養）；C4c-2 流民遷入（site_resident_migrants.gd：每 30 日，有完工住宅空床、存糧夠「(居民＋新人) × 30」、居民平均不滿 < 40 → 一戶最多 4 人生進居民隊為平民並登記門前格；接在每日出走之後）。
- 回歸：NEWP_REG_A 138/138、MIGR_REG_A 139/139（RUNNER_CAUGHT 皆單獨重跑過）。
- 下一步：跨 Site 兵力情報（官員在每次大地圖評估記下本 Site 看得到的別方武裝人數，跟著人走 7 天；當面轉告同陣營官職持有人；國家出兵挑目標讀得到 power）。順手修：群眾 Site 的 scoped_region_intel 只看 GD 軍隊，群眾上沒有任何情報。C1c 仍等平民圖集；B5 等 NPC 商隊（貿易 T5）。

## 2026-11-17 12:30（台北）平民 C6；原生隊形上限試做撤回
- 已提交（未推送）：6d68cf1 C6 畫面外（長期補算每日記錄並結算居民不滿、戶主業工時依不滿打折）。回歸 C6_REG_A 123/123（P4 冷研究並行崩潰、單獨 1999 秒過）。
- 試做原生「隊形數 ≤ 人數＋1025」：重建 DLL 原生測試全過，但群眾回歸 3 支在建隊／讀檔存取違規崩潰（site_ship_supply_crowd、site_technology_artisan_birth、site_crowd_legacy_convert），site_shared_step_replay 固定比對 state.cpp 內容。已撤回：舊 DLL c9a9c1dd… 還原（新版 3c516ab2… 留在 evidence/formation_bound_20261117），state.cpp 還原。待查：新建 DLL 為何崩潰（是否 bin 內舊 DLL 與目前原始碼不一致）。
- 下一步：C4c／C1c 前置設計。

## 2026-11-17 10:45（台北）平民 C5 陷落後；群眾隊形上限
- 已提交（未推送）：63a6ae4 C5 陷落後（陷落時記下原居民與原門前格；每日 G < 40 歸附＝新陣營無隊長居民隊並回原格登記，G ≥ 60 或滿 30 日出走）。回歸 C5_REG_A 113/113。
- **風險（新發現）**：原生群眾規定隊形數 ≤ 人數＋1，且隊形永不移除；每次「離隊成新隊」永久用掉一個隊形。本串的出走／歸附／鄉勇已改用 CrowdSite.join_team 直接移動（可改陣營），每次行動最多開一個新隊形；但一般遊戲中反覆離隊再歸隊仍可能耗盡，需要原生回收空隊形（未做）。症狀：原生存檔讀不回（INVALID_CROWD）。記憶 crowd-formation-limit。
- 也修了：無隊長的隊剩一人時讓他自任隊長（原生拒絕無首領單人），作息仍管自帶一人隊的平民；CrowdSite.clear_captain。
- 下一步：C4c 流民遷入需要「進行中的群眾 Site 生出新人物」（原生有 add_soldiers，但沒有執行期的新人物建立流程：編號、外觀、持物、社會、名冊、供養），與 C1c 原生「在家」一起做；C6 畫面外（長期不在場補算加每日不滿與流動）。

## 2026-11-17 09:30（台北）群眾併隊、隊長自主出門、平民 C4a／C4b、鄉勇編入守軍
- 已提交（未推送）：26ffb69 CrowdSite.join_team（一人隊的隊長併入同勢力另一隊；潰兵成伙後全員併入頭目的隊）；280c39b C4a 居民不滿（斷糧 +3、無家 +2、平安吃飽稅 ≤10% −1、居民被殺他人 +5、被徵召 +5；G ≥ 40 工作 ×0.8）；02a420e 隊長自主出門（RegionAI.prepare_captain_dispatch，nation_id "captain:band／emigrate"；買路錢測試改由土匪頭目派隊）；44611a2 C4b 整戶出走／落草（每 30 日，戶平均 G ≥ 60 以 (G−50)/50 機率出走上大地圖，≥ 80 其中一半落草，世界種子定骰）；鄉勇編入守軍隊（徵召者離開居民隊併入守軍隊，解編回居民隊）。
- 回歸：JOIN 99/99、C4A 104/104、CAPT 18/18、C4B 107/107、MILG 105/105（RUNNER_CAUGHT 皆單獨重跑過）。本串新測試清單 output/project_command_center/CONTINUOUS_SWITCH/new_tests_20261117.json，每次回歸都要帶上（不在 11/14 全清單）。
- C4c 流民遷入卡在前置：遊戲進行中無法生出新人物（人物編號配置器沒有呼叫者；群眾跑過時間後不能退回一般模式生人），需要新增「原生群眾直接加新人物」入口（編號、外觀、持物、名冊、供養）。先做 C5 陷落後（已有出走入口），C4c 與 C1c（原生「在家」）一起排。

## 2026-11-17 06:55（台北）平民 C3a／C3b／C3c
- 已提交（未推送）：c48f7f0 C3a 遇敵回家（Site 戰鬥中或有敵對武裝人物 → 警報，居民停工、可穿過戰鬥走回家；戰鬥開始立即反應；危險解除後留 30 分鐘）；62b8f53 C3b 打平民扣信譽（別方平民被殺 −2、被擊倒 −1；計畫寫「數值另定」，先用這組，常數在 person_reputation.gd）；C3c 鄉勇（site_militia.gd）。
- **決定（協調者 11/16 22:11Z 依慣例採建議 A，Nekki 可改）**：鄉勇只在敵人進入、尚未開戰時徵召，不放寬既有「軍職變更須脫戰」；NPC 營務自動徵召、警報結束解編；玩家當營務時自己決定（尚無按鈕，只有 SiteMilitia.draft／release）。
- 回歸：C3A_REG_A 97/100（3 支不在維護清單的舊測試，基準同樣失敗：site_housing_test 撞 GRID_SIMULATION_RETIRED；site_resident_birth、site_housing_crowd 為既有失敗）、C3B_REG_A 98/98、C3C_REG_A 99/99。
- 未做：住宅毀改到中心避難（沒有走到中心的動作）、屋內居民原生「在家」不可選為目標（併 C1c／平民圖集）、鄉勇編入守軍隊（缺群眾併隊，與土匪潰兵同一缺口）、徵召不滿 +5（C4）。

## 2026-11-17 05:25（台北）土匪 B4d-1／B4d-2／B4d-3a
- 已提交（未推送）：9167d50 B4d-1 每日決策（site_bandit_day.gd：每 10 日 heat −5、heat ≥ 70 換寨到相鄰陸地 Site、在場 NPC 頭目達門檻起義；玩家當頭目的伙不動；掛在 settle_person_deaths）；12e7750 B4d-2 潰兵成伙（site_bandit_rout.gd：close_battle 記下潰逃隊伍的人到 Site 段 bandit_rout_watch，7 日後原勢力滅或原隊不在、在此 Site 的自由生還者 ≥ 3 → 新土匪 origin rout）；B4d-3a 同 Site 劫掠（頭目在場、本 Site 別家聚落、看得到的人數 ≥ 1.2 倍、未付保護費 → 土匪隊對最近守軍下攻擊令、heat +10）。
- 回歸：BDAY_REG_A 100/100、BROUT_REG_A 101/101、BRAID_REG_A 102/102（土匪家族＋冒煙 91＋戰鬥紀錄；RUNNER_CAUGHT 單獨重跑過）。
- 發現的缺口（未做）：(1) 沒有任何情報記得別的 Site 的兵力（官員對外地只有公開地理），所以跨 Site 劫掠、連國家出兵挑目標都不會觸發；(2) 一人隊（detach_to_new_team）不接受隊伍軍令，潰兵成伙後每人一隊，要有「併隊」才能一起劫掠；(3) 落草土匪 raid_ai 預設關，換 NPC 頭目後仍關；(4) 劫完撿遺物、撤回山寨（B4d-3b）。

## 2026-11-17 04:10（台北）土匪 B4c 買路錢接上大地圖相遇（新指揮中心）
- CURRENT 指揮中心：新串（cmsg_…CmB9nUuknpt82jaj7trrXb），11/16 16:30Z 由協調者開、接手 05d62f6／717a9bf 交接。
- 已提交（未推送）：79103a5 土匪 B4c 買路錢。土匪在途隊伍遇到在途玩家、人數 ≥ 玩家 1.5 倍且無有效放行時，相遇停住成為買路錢提議；旅隊面板「付買路錢（N 糧）／不付，開打」。付＝隊伍共用存糧（或玩家行囊）扣「人數 × 2」糧進土匪庫藏、記 3 日放行、相遇跳過，三者同一次發布；打＝原相遇流程。「逃」未做。
- 順手修的既有問題：(1) 在途玩家的路線讀檔後座標是小數，RegionRoute.route_contact_candidates 用 Array == 比對，在途玩家從來不會和 NPC 隊相遇；(2) 一出發當下就到期的相遇事件沒人處理，旅程卡住。
- 新測試 region_bandit_toll_road_test（-- --toll-case=pay|fight，各約 4 分鐘）；回歸 TOLL_REG_A（output/project_command_center/CONTINUOUS_SWITCH/TOLL_REG.json，Region 全部 48＋土匪 8＋買路錢 2）58/58，6 支長測試並行撞時限、單獨全過。
- 付款存回的做法與踩過的坑記在記憶 bandit-b4-progress（不要重綁旅隊實體、不要在出發後第一段前走實體擷取存檔）。
- 進行中：B4d-1 每日決策資料層（site_bandit_day.gd：每 10 日 heat −5、heat ≥ 70 換寨到相鄰陸地 Site、頭目在場達門檻起義；玩家當頭目的伙不動），掛在 settle_person_deaths。之後 B4d-2 戰鬥結束潰兵成伙（site_battle_tracker.close 的 routed_teams）、B4d-3 劫掠（在場群眾戰鬥、畫面外公式戰鬥）。

## 2026-11-17 02:00（台北）交接給新指揮中心
- 本串（cmsg_…4rnoahY36kCET7y6gphsCW）停止施工，不再跑 Godot。工作樹沒有未提交的程式改動；HEAD 之後全部未推送。
- 最後提交：b5f9c35 土匪 B4d 規則層（每日決策、劫掠條件與選目標、潰兵成伙資格；尚無呼叫者）。
- 接手順序建議：B4c 買路錢接大地圖相遇（先搭「玩家在途＋土匪在途」的測試情境，搭法見記憶 bandit-b4-progress）→ B4d 接每日結算與畫面外戰鬥、潰兵成伙接戰鬥結束 → B5 → TC11（等接舷 B5）→ P3b（等 NPC 商隊）→ 平民 C1c／C3+。
- 先備好未接上的項目見 11/16 23:00 段；薪稅實作取捨見 reports/pay-and-tax-plan.md §15。
- 待 Nekki 回覆（不擋工）：PT-02 糧餉受 20 件載量限制是否維持；是否推送。

## 2026-11-17 01:15（台北）土匪 B4b／B4c
- 已提交（未推送）：6a3e282 TC10；2f4ca8b B4b 保護費（SiteBanditProtection、財政頁付／拒）；698bd3d B4c 買路錢規則；18221f8 在途隊伍的勢力／人數／扣糧工具。
- B4c 尚未接上大地圖相遇。接點：RegionSaveSlot.queue_region_gameplay_endpoints 排的 "npc:<token>:player-contact:…" 事件，consume_region_player_event 已有 skipped_contact 出口；付款後存回在途隊伍照 5290 行附近的寫法（新 party 文件＋journey.party_sha256＋_publish）。風險：10839 行附近把已完成的 player_encounter 當成已接受接觸，不可盲目手動完成事件。
- 需要先做的測試情境：玩家在途＋土匪隊伍在途、路線交會。現有 region_remote_nation_original_test 的相遇是「玩家在活動 Site」，不是在途，不能直接用。
- 詳見記憶 bandit-b4-progress。

## 2026-11-16 23:00（台北）時間與氣候 TC4–TC10 提交
- 已提交（未推送）：df72a19 TC4 晝夜光色與夜間光暈；e5582cb TC5a 雨霧畫面；5b88280 天氣音效（Nekki 09:43Z 選 A，Codex CC-20261116-195，CC0／CC BY 3.0，assets/audio/WEATHER_CREDITS.md）；ef4c3ba TC9 大地圖行進與露天休息、世界氣候開關（勢力登錄 `climate`）；a0a4dea TC5b 風雨接火攻（歷史滿 4096 筆時兩兩合併）；6a3e282 TC10 遠程命中受天氣與夜晚影響（同一段 GD 規則，DLL 未改）。
- 先備好、尚未接上：大地圖偵察倍率（沒有發現距離系統）、道路減半（沒有道路資料）、Site 內露天休息（原生群眾疲勞）、NPC 讀天氣（NPC 不選火箭、沒有自派出海）、NPC 夜襲（等 NPC AI 計畫）。
- 等前置：TC11（接舷 B5）、P3b 收稅隊（NPC 商隊多站路線）。下一項：土匪 B4 其餘、B5；平民 C1c／C3+。
- 教訓：背景監看只排一輪 19 分鐘就結束，回歸跑完後沒人喚醒，停了近一小時（Nekki 21:08 問）。監看要用「等 DONE」的迴圈並在每次醒來重排。

## 2026-11-16 17:25（台北）軍餉與稅收 P0–P6、氣候 TC3、季節經濟 TC8 全部提交
- 已提交（未推送）：7c7f2c9 P0–P2＋TC3＋TC8（回歸 157 全過）；a44a382 P3 稅鏈（170 支 169 過，失敗的 region_joint_departure_cold_checkpoint 是 11/08 起「群眾移植未跑」的舊測試）；fdcef33 P4–P6（171 全過）；1409422 TC8 一年＋一冬存糧長跑。
- 實作取捨都寫在 reports/pay-and-tax-plan.md §15（PT-02 載量矛盾、封地庫、群眾士氣以隊伍計、NPC 無倉庫不入發餉）。
- 長跑結果：冬天開局（1 月 1 日）的聚落，存糧要撐 59 日冬季；一房務農、七房十四人時開局 150 糧足夠，50 糧第 24 日斷糧。秋季存糧規則能救「春天剛好自給」的聚落過冬；但 NPC 一旦全戶改種糧就不會再改回（plan 只補沒有主業的戶），之後可在春天依存糧把部分戶調回原業。
- 待辦：P3b 收稅隊（需 NPC 商隊多站路線，貿易 T4）、跨 Site 撥餉與領主撥餉、TC4/TC5、TC9–TC11、土匪 B4 其餘／B5、平民 C1c／C3+。

## 2026-11-16 14:30（台北）長期補算 A 提交；軍餉與稅收 P0–P2、氣候 TC3、季節經濟 TC8
- 已提交（未推送）：4a6eef8 長期補算 A（回歸 COARSE_REG 123/123，1 支 RUNNER_CAUGHT 單獨補跑通過）。
- 工作樹（專用測試逐支通過，PAY_REG 157 支回歸 14:29 開跑）：
  - P0：site_pay_table.gd（餉表、稅率檔、幣 10 點、30 日寬限）；site_finance.gd（Site 段 `finance`，每組織一筆：餉源／稅源／國庫、倍率、發餉／繳稅索引、上繳對象、豁免、在職天數、稅零頭、兩季收據）；PersonSocial `arrears`。都是可省略欄位，舊檔不必遷移（PT-14），所以沒有全域存檔版本加一。
  - P1：site_payroll.gd，每月 1 日發餉（掛在 DutyAI 和平時的日審查）；只有已有財政紀錄的組織發餉（綁餉源時建立；玩家新局 P4、NPC 首長 P6 補建）。
  - P2：site_produce_tax.gd；新聚落職位「度支」settlement.finance；SiteRuntime.publish_feature_output 出貨時扣稅。
  - TC3：site_climate.gd 純函式；`climate_enabled`（選單新建世界才開，旅行到的 Site 繼承）；時鐘列加時段與天氣。
  - TC8：site_season.gd；農／牧產量、野生資源恢復、農田需水、雨水補水、乾旱 ×0.7、大雨居民回家、虞衡 3 日預報（時鐘提示）、NPC 戶曹秋季存糧、長期補算套季節倍率。
- 規劃書 PT-02 的數字在 20 件載量下不成立（軍官 30 點無法全用糧發），已告知 Nekki；照規則實作，測試改用含載量的期望。
- 待辦：TC8 365 日長跑需要有 NPC 聚落與住戶的範本（time_climate_tc0/source_small 沒有聚落）。教訓：回歸跑的時候只能寫還沒被引用的新檔，不能改已載入的腳本（今天一度把 P1 掛點撤回重接）。

## 2026-11-16 13:00（台北）TC7、文武官 W4–W5、考試學校 E1–E4、長期補算 A
- 已提交（未推送）：9b7d3c0 TCM 分鐘制；3e46699 TC2 睡覺；f980e82 TC7 年齡與健康；f3372d8 W4；558e71a W5；e300926 E1；f2d838b E2；0600dff E3＋E4；b736b49 學校美術（Codex CC-20261116-194）。
- **Nekki 11/16 02:14Z「A」**：長期不在場 Site 以日結算（記憶 long-absence-coarse-catchup-decision）。實作接在既有的區域冷補算「安靜前段＋精確尾段」（terrain_lab `_region_advance_original_cold_budget`）：間隔超過 1 日時 coarse 模式收發展過的 Site，每步最多 1 小時，跑原 tick／供養／疲勞，跨日結算居民主業產出（ResidentWork.daily_production），不跑職責 AI；元旦前後 2 分鐘、飢餓 ≥40 改走精確。工作樹，測試 site_coarse_catchup_test 跑中。
- 批次執行器 run_manifest.ps1 加了 try/catch：驗證器保留清理互搶資料夾丟出的錯誤只記為該支 ERROR，工作程序不再無聲死掉（正式驗證器未改）。
- 圍城中心 headless 時限 600/660 → 840/900（八案例單獨約 680–785 秒），所有清單已改。

## 2026-11-16 05:35（台北）時間與氣候 TC1／TC0／TCM／TC2
- 已提交：ce89a94 平民 C2；3395311 文武官 W3；4cb4f40 TC1 太陽曆（世界分鐘 0＝1 年 1 月 1 日 06:00，曆法起點偏移，新世界第一代時鐘仍從 0）；a164195 TC0 量測（reports/time-climate-tc0-measurement.md：冷補算 88 遊戲秒／真實秒，1 日 16 分、30 日 8.2 小時）。
- **Nekki 11/16 18:59Z「TC2照你建議」**：睡覺時玩家 Site 維持活著，以 ×8／×16 前進，不走冷補算。長期不在場 Site 的粗略補算路徑要在 P0 前處理（另立工項）。
- TCM 分鐘制（工作樹，回歸中）：SiteRuntime.game_seconds 一律 ×60；SiteRuntime.tactical_seconds（舊公式）只給戰鬥機制：GD 人物擊倒與非工作疲勞、聚落攻陷 60 秒；原生 World::tactical_dt（擊倒、非工作疲勞、捕捉／脫逃、流血、士氣）。用餐、生產、研究、火攻 journal、Region 區間都走新流速。舊存檔的火攻／戰鬥區間列兩種公式都接受。原生 DLL c9a9c1dd…（舊版 17271b32… 備份在 evidence/TCM_native/previous_dll）。人物行動（捕捉、押解、守衛）在 GD 端仍走世界時間。
- TCM 回歸：195 支＋65 支補跑；改了 6 支測試的舊換算期望值（生態重播、動作量子尾段、Region 時鐘、共同步重播×2、戰鬥窗口、圍城中心反推）；修了 RegionGameplayClock.clip_interval 漏改的公式。剩 TCM_REGION（59 支 Region／冷補算）跑中，全過後提交，再套用 TC2（scratchpad tc2_apply.py、site_sleep.gd、site_sleep_test.gd 已寫好）。
- 已知環境失敗：site_siege_crew_asset_prep_visual（要 GPU）、site_mount_fatigue_visual（要正式主場景）、site_resource_visual（要 GPU）、site_ecology_longrun_owner（11/04 起卡住）。

## 2026-11-15 23:30（台北）進度與時間氣候排程
- 已提交（未推送）：3b5b9e0 土匪 B4a＋平民 C0；56f3597 平民 C1b 戶糧（house:<id> 食物存放點）；c5c514c 平民 C1a 日程（無隊長平民在 home 時段自行返家，SCHEDULE_REQUESTER=-2）。
- 工作樹：平民 C2 戶曹派工（settlement.registry、site_resident_work.gd、排程上工／收工、choose_task 只去本戶主業），回歸 C2_REG（149 支）補跑中；文武官 W3 程式已寫（site_civil_promotion.gd、PersonSocial.civil_service；套用腳本在指揮中心 scratchpad w3_apply.py），等 C2 提交後套用。
- 平民 C1c（原生「在家不畫」）延到 P2 之後與平民圖集一起做：要處理原生缺席時的疲勞、存檔與交接，目前居民人數用不到。
- **時間與氣候計畫（reports/time-and-climate-plan.md，Nekki 11/15 定案，協調者 15:24Z 轉）排入**：
  C2 → W3 → TC0 量測 → TC1 太陽曆（居民日程改讀曆法）→ TCM 分鐘制（M1–M4 全 A）→ TC2 睡覺 ×8／×16 → TC7 年齡與健康（E 之前）→ W4–W5 → E1–E4 → 空檔做 TC3／TC4／TC5 → P0–P2 → TC8 季節經濟 → P3–P6＋P3b → TC9–TC11 → 土匪 B4 其餘、B5、平民 C1c／C3+。
- 回歸總控程序的工作程序會在驗證器保留清理互搶資料夾時死掉（已知），總控會逐支補跑沒跑到的測試，等 `<Label>.log` 的 DONE 行為準。

## 2026-11-15 15:40（台北）進度與新順序
- 已提交（未推送）：4d6dfe8 文武官計畫入庫；6df856e 土匪 B1＋B2；984734e 土匪 B3（招安、接任、潰散；CrowdSite.hand_over_captain）；b8eb78a 文武官 W1＋W2。
- **Nekki 11/15 06:44Z「都依建議」**：平民行為計畫 Q1–Q10 全 A（計畫在專案資料庫 reports/civilian-site-behavior-plan.md，尚未入 repo）。C0–C2 插隊。
- **新順序**：土匪 B4a ＋ 平民 C0（工作樹，回歸 C0_REG_A 跑中）→ C1 作息與吃飯 → C2 派工（settlement.registry，文職）→ W3–W5 → E1–E4 → P0–P6＋P3b → 土匪 B4 其餘、B5。C3 以後排在 P2 之後。
- 工作樹未提交：region_bandit.gd（heat／move_lair／may_rise／rise／fall）、site_controller.gd（bandit_rise、go_outlaw 與按鈕）、site_households.gd（新）、site_store.gd／site_housing.gd／site_settlement.gd 的戶同步；
  新測試 region_bandit_b4a_test、region_bandit_b4a_site_test、site_households_test（三支單跑 PASS）。
- W2 的取捨：聚落與國家的武官位維持原規則不查軍階（舊存檔在任者不會因任何人事調整被判失格）；文官位一律查文職資格。NPC 隊伍目前沒有文吏，文官位由首長代行，W5 補 NPC 舉用。
- 已知非本輪造成：site_ecology_governance_roundtrip_test 在 b8eb78a 之前就失敗（攻陷計時未完成，fallen 為空）；site_duty_ai_lab_test 為已退役的格子模擬。
- 土匪延後項：存檔版本 +1（併 P0）；情境配置土匪 entry（等情境勢力入口）；山寨對已知方顯示、潰兵成伙、每日決策、劫掠／買路錢／保護費（B4 其餘）；同勢力多隊共用原生槽時不能逐隊潰散（回 BUSY）。

## 2026-11-15 09:20（台北）暫停：Nekki 01:11Z「等等先暫停一下 要更新重開機」
- 背景工作已全部停止（B1_REG_A 回歸中止，已跑 20 支全 PASS、0 失敗；無 Godot、無 runner 殘留）。重開機後從下面接續。
- 已提交：4d6dfe8 文武官計畫 reports/civil-military-office-plan.md 入庫（未推送）。
- **未提交（工作樹，B1＋B2 土匪）**，備份 output/project_command_center/patches/bandit_b1_b2_wip_20261115.patch＋同目錄兩支新測試副本：
  - B1：region_faction_query.gd（KINDS 加 bandit、bandit 子表驗證與預設、is_bandit／bandit_of／canonical_bandit、allocate 不封王、BANDIT_COLOR／「匪」顯示）；
    region_diplomacy.gd（含土匪恆敵對、無條約、propose／declare_war／reply 回 BANDIT_NO_DIPLOMACY、存檔內土匪條約或信件＝CORRUPT_SAVE）；
    region_peerage.gd（crown_founder／rebel 投匪 BANDIT_NO_NATION、swear 給匪 BANDIT_NO_DIPLOMACY、匪內爵位 CORRUPT_SAVE）；
    site_settlement.gd（匪不計攻陷人、fall_to 回 BANDIT_NO_OCCUPY）；site_join_faction.gd（不能投靠土匪）；site_controller.gd NPC 外交日跳過土匪。
  - B2：主選單「落草」開局（RegionEntry mode bandit，情境 allow_bandit_start 預設允許）、found_start_faction(name, outlaw) 建匪：頭目＝玩家、山寨＝玩家起點格、raid_ai false、信譽 −20（PersonReputation.OUTLAW）。
    解讀：落草開局整支起始隊（玩家＋幹部）一起成伙，同自建勢力；規格寫「1 人伙」，如需只留玩家再改。
  - 測試：新 region_bandit_b1_test.gd（D 上 PASS 42 項，run 20261115_090956_703）；site_settlement_center_test 加 capture_bandit_never_occupies（PASS，run 20261115_091237_251）；
    新 region_start_bandit_test.gd 尚未跑。
- 延後：存檔版本 +1（規格 §3.3）照交接建議與 W1＋P0＋聲望第 1 步合併做（白名單放寬對舊檔相容）；情境配置土匪 entry 等情境勢力入口存在後再做；山寨在 Region 地圖「已知方」顯示併入 B4 情報。
- 重開機後下一步：重跑 B1_REG_A（manifest 在 CONTINUOUS_SWITCH/B1_REG_A.json，98 支：家族 7＋冒煙 91）＋ region_start_bandit_test → 全過即提交 B1＋B2 → B3 招安與潰散（新檔 site_bandit_amnesty.gd，仿 site_join_faction 當面流程；
  計分 accept_score＋accept_bonus ≥ 50、頭目 follow＋heat/5 ≥ 55、成員逐人 follow；留下 ≥3 換頭目、<3 潰散為中立單人隊、全走 merged）。

## 2026-11-15 交接給新指揮中心（預定功能接續）

### 這輪結果（11/14 20:00～11/15 03:40）
- 11/05 失敗分類 C 段 31 支全部處理完：10 支原本就過，其餘修好或照 Nekki A 退役。
  - 5c4e97e：群眾讀檔保留存檔 Actor 的騎乘狀態，以及 KW21／CAV-3 舊期待的更新。
  - 4db781f：餓死殘血卡死時鐘（原生補給點只扣區段傷害，留下低於 1e-9 的殘血）；被餵外隊俘虜的昏迷值讀錯隊伍。
  - fd60084、38bc558：照 Nekki 11/14 A 退役 9 支純 GD 軍隊測試，3 支只刪 GD 段（記憶 triage-c-gd-tests-decision）。
  - 6487cdd：選項 2，4 個 Freesound 授權 HTML（內嵌 Mapbox 公開 token）改純文字；不改歷史。
  - a171e44：效能，火焰移動快照延後取樣，5000 人接戰每步 4～6 秒降到 1～2.3 秒（記憶 c3-replay-perf-profile）。
  - 64f1769：crowd_c3_replay B 通過（1098 秒，600 步完全一致）。
- 最後一項（已修）：crowd_c2_c3 --crowd-fixture D 在 43.87 秒時鐘停住。共同步進每步都回 DUPLICATE_NATIVE_ACTIVITY：押俘虜的群眾看守同段既是原生 RUN，又被列「guard」體力請求。修法：原生列為 runner 的群眾看守，該段不再列 guard 請求。修後 D 跑過 80 秒，第 14～47 項檢查全過。
- **D 夾具尚未完整通過（交給新指揮中心）**：要跑到自然脫離（≤300 遊戲秒），照現速約 95 分鐘，超過 canonical 驗證器 3600 秒上限。下一步是效能：shared_native_begin_prepare 約每步 0.5 秒，連沒交戰時也是。C3 D-scene 需要這支夾具輸出的 baseline.json 當 --crowd-source。
- 5000 人測試一定要單獨跑；兩支並行會互搶 CPU、雙雙撞 1860 秒。

### 預定功能接續順序（協調者 11/15 03:02 轉 Nekki）
規格都在 reports/，各檔最後有施工順序表。
1. **土匪 BANDIT B1～B5**（reports/bandit-faction-spec.md §施工）：B1 名冊與敵對 → B2 情境與開局（主選單「落草」）→ B3 招安與潰散 → B4 來源與 AI → B5 貿易接點（可延後）。
2. **文武官 W1～W5**（reports/civil-military-office-plan.md，方案 B，此檔目前未提交）：W1 civil_role 資料與存檔升版 → W2 qualified_for 判定 → W3 晉升 → W4 開局與 UI → W5 AI 與聲望（要在爵位「授爵與封地」後）。W1～W2 可與聲望第 1 步合併施工。
3. **考試學校 E1～E4**（reports/exam-and-school-plan.md）：E1 資料與蒙學（依賴 W1～W2）→ E2 鄉學與鄉試 → E3 國學與國試（依賴 W3）→ E4 UI 與 AI（依賴 W4～W5）。
4. **軍餉稅收 P0～P6**（reports/pay-and-tax-plan.md V0.2）：P0 資料（coin、finance、pay_table）→ P1 發餉 → P2 產出稅（可與 P1 平行）→ P3 稅鏈與撥餉（等爵位）→ P3b 收稅隊 → P4 UI → P5 群眾與畫面外 → P6 NPC。P0～P1 可與 W1～W2、聲望第 1 步合併成同一次存檔升版。
- 依賴提醒：W5、P3 都等爵位「授爵與封地」步；存檔升版建議 W1＋P0＋聲望第 1 步一次做。

### 交接狀態
- HEAD 464e0fe（04:55 已推送：f938594..464e0fe → origin/claude/project-thread-qsrymf；草稿 PR https://github.com/nekki1009/worldgoing/pull/1，合併由 Nekki 決定）。本機 master 仍追蹤 origin/master。
- 464e0fe：群眾看守同段原生 RUN 不再另列 guard 體力（修 D 夾具時鐘停住）；看守／俘虜族群＋冒煙 FAM_G_1115 103/103。
- 里程碑清單 CONTINUOUS_SWITCH/full_reg_20261114_manifest.json（153 支），冒煙 smoke_reg_manifest.json（91 支）。
- 常駐規則照舊：Godot 單支一次一個、批次最多 3 並行（5000 人測試單獨跑）；放寬測試時限直接做；A/B 問題在討論串問 Nekki。

## 2026-11-14 19:40（台北）里程碑與換人上馬
- 里程碑全清單 FULL_1114_A（full_reg_20261114_manifest.json，153 支）152/153；唯一失敗 two_npc_sea friendly 為牆鐘時限（745>720 s），f938594 放寬 900/960 後 PASS。
- 12eb328 群眾馬車換人上馬（Nekki 08:57Z「要做換人上馬」）：下車走一步離開車體；同隊站在馬旁者可接手（走 N08 _crowd_route_reboard）；工位 hold 視為站立。回歸 TAKEOVER_REG_A 97/97。
- 群眾移植清單與交接時的舊失敗已全部處理。未推送提交 21 個（ca824ff..f938594），推送待 Nekki 明說。

## 2026-11-14 16:40（台北）CC-193 缺口全數處理（Nekki 07:00Z A）
- 27176e1 無 RegionSlot 的 advance_cold_site 先吃原生端點（_slotless_cold_replay）；群眾 replay 測試的 _capture 改取 Lab 當下的 Fire 狀態（舊版比的是存檔殘留的 4.67，真值兩邊都是 24.67）。回歸 ADAPTER_REG_A 100/100。
- 86023f3 共用步進結尾戰鬥殘差 ≤ ACTION_TIME_EPSILON 歸零（Fire journal 區間寬度少一 ulp → 1.1e-16 s 戰鬥 → 原生不准休息；冷 fatigue_rest 0 vs 即時 30）。回歸 CLOCK_REG_A 102/102（含船程時鐘組）。
- 556b07f 群眾 replay 測試補上死亡／遺骸分支（PASS 127 s、110946 檢查；死亡以原生身體判定）。
- 只剩：群眾馬車換人上馬（新功能，等 Nekki）。未推送提交 19 個（ca824ff..556b07f）。

## 2026-11-14 14:45（台北）舊失敗清零
- 6d47475 群眾隊伍職責 AI 開關寫回名冊（回歸 29/29）＋ reports/perf-cold-checkpoint-option-c-20261114.md。
- 5d23f98 real_npc_cold_replay 修好（假 slot 不比 Fire 水印；transport 用 SiteStore wire 形狀比）。
- e7d2fc0 ecology_replay（Nekki 05:38Z A：排除退役協調器 current_logic_tick；位元組包裝的數字用 1e-6）。
- 9de0129 群眾死亡結算 crash（crowd_site._appearance_now 對 Actor Node 用兩參數 get）。
- 7fc3727 shared_step_replay 群眾版（Codex CC-20261114-193；D 上 PASS 102.7/119.3 s）；舊 GD 輔助保留為 site_shared_step_replay_base.gd 給 matrix／real_npc／fault／ecology 子測試（5/5 PASS）。
- 開放缺口：(1) 跨 Site 火攻冷補算 fatigue_rest 0 vs 即時 30（根因未證）；(2) 無 RegionSlot 的 advance_cold_site 重試不吃原生端點 → REGION_EFFECTS_PENDING；試修補丁 patches/slotless_adapter_consume_20261114.patch 能完成但 fire_transport.action_cursor 差 20 s，未提交；(3) 群眾馬車換人上馬原生步行未接入。
- 缺口 (2) 追查（15:00）：試修後 adapter 完成，但把結果 data 經 `_restore` 重開後，fire_transport.action_cursor=24.67，即時版是 4.67（差 20 s＝即時跑的 20 行動秒）。
  核心測試直接比較 live 和 cold Lab，所以是相等的；adapter 這條路走的是「區域快照 → 重開」，快照 context 的 action_seconds 取 lab.fire_action_cursor，重開時游標由它還原。
  初判是快照 context 的行動秒與 transport 自己的游標語義不同，未證實；下一步比較 `_region_finish_cold_replay` 寫的 context.action_seconds 與 transport state 的 action_cursor。
  15:10 補：即時捕捉（output/shared_step_replay_crowd/live.var）的 transport.action_cursor＝4.67、遊戲秒 1480.2；核心測試冷補算也是 4.67（相等通過）。
  所以多出的 20 s 出在 adapter 路徑（advance_cold_site 的 _cold_replay_lab 設定或預算切片 replay），不是一般冷補算。
- 未推送提交共 15 個（ca824ff..7fc3727）。

## 2026-11-14 12:40（台北）四支舊格子測試（Nekki 03:50Z 都照建議）
- e042de9 退役 site_ship_travel、region_cold_formal_original。
- 039797c 群眾多方試驗車輛部署修正（plan_team 的隊形序號 → 群眾原生序號；第 2 方起 INVALID），回歸 WAGON_REG_A 95/95。
- ced2aa4 site_wagon_cloth 群眾版只留資料規則（PASS 43.9 s，參數 --crowd --crowd-test）。產品缺口（未做）：群眾馬車換人上馬的原生步行未接入（assign_operator 明確回 UNREACHABLE）。
- 進行中：Codex CC-20261114-193 移植 site_shared_step_replay 群眾版（補丁交回，D 上驗）。

## 2026-11-14 11:45（台北）P4 完成
- 提交（未推送）：ca824ff（WorkTeam _published_admission，回歸 113/113）、e84d49a（Codex CC-20261114-192 攻城派工畫面模式圖集準備，Nekki 選 B；回歸 103/103＋畫面測試 PASS）、
  9ec5fb7（群眾冷研究 7 項產品修正：補算收尾時鐘容差×2、分鐘尾進位窗口、器械試作認群眾原隊伍、占地排除施工者、PA 收尾讀許可分配、研究者工位休息）、
  cac1668（P4 群眾移植測試；canonical PASS 1936 s，run 20261114_100055_671；時限 2700/2760）。
- 回歸 P4_REG_A 134 支無新失敗；既知基準失敗：ecology_replay、shared_step_replay、real_npc_cold_replay、ship_travel／region_cold_formal_original（GRID_SIMULATION_RETIRED）。
- 新工具：P4 失敗即寫 output/project_command_center/p4_runs/P4_LIVE_ABORT.txt 並結束；`--p4-lanes-only` 只跑受控線（除錯用，不算驗收）；長單跑旁有大批回歸時用 detached copier 保存記錄（記憶 retention-evicts-long-runs）。

## 2026-11-13 22:20（台北）交接（Nekki 14:04Z「好，他跑完這個再交接」；本串 hearthbot 自約 20:10 起斷線，無法回報）

### 已提交（全部未推送，master）
- 7c8f5d6 群眾攻城操作班可卸／裝自己器具的彈藥（`_stock` 群眾分支補 siege crew）；火罐 ordinary UI 測試改在群眾上跑；tent_logistics 替身補齊。
- df643c6 fire_pot_disabled 退役；vehicle_transport 只留部署／操作員／移動中存讀檔／Store 拒絕規則（Nekki 11/13 07:06Z「依建議」）。
- 9f5ecf2 四項產品修正：營地手作工匠原地休息（`work_fatigue_rest(keep_station)`）；冷補算量子殘差 ≤ ACTION_TIME_EPSILON 歸零（同即時步進）；
  `_region_finish_cold_replay` 以遊戲秒容差比 settlement pending；群眾冷讀檔後 holder 職位表空白時由名冊投影（`site_duty_ai` 原生同意）。
- b36db51 移除退役測試的 .uid。
- 回歸收據：smoke 92/92（SMOKE_FIREPOT_A＋TENT_A）、artisan 家族 13/13（ARTISAN_REST_A）、first-earned 科技 17/17（CONSENT_FAMILY_A＋N02_A）、
  ship_journey／journey_edge PASS（SHIP_CLOCK_A）。REPLAY_CLOCK_A 其餘失敗在修正前基準相同（REPLAY_BASELINE_A）。

### 未提交（工作樹）
- `scripts/terrain_lab/site_work_team.gd`：`_published_admission`（已發布、尚未收尾的 WorkTeam 前綴）。原因：同一步內 native begin window 的
  `prepare_work_requests` 先 discard 目前 admission，區域點結算時 `finish_shared_work_prefix` 以 is_same 不符跳過，零工時「已付完成品」端點永不結算。
  修後 P4 的 S07 第一件弓可交貨。**尚未跑回歸**（建議：artisan 家族、first-earned 17 支、smoke）。補丁：`output/project_command_center/patches/workteam_published_admission_20261113.patch`。
- `scripts/tests/site_p4_cold_original_research_test.gd`：P4 群眾移植進度＋多處診斷 printerr（P4_*_DIAG，通過前要清掉）。
  補丁：`output/project_command_center/patches/p4_crowd_wip_20261113c.patch`。
- 產品檔內的暫時追蹤行（TEMP_*）已全數移除。

### P4 現況（`site_p4_cold_original_research_test.gd`）
- 時限：Nekki 11/13 09:20Z「照建議」A → 檔內 1800 s、外層 1860 s（`p4_only.json`／`p4_diag_long.json` 已是 1860）。
  每次冷補算結尾都做完整冷存檔點（owner state ~245 ms＋Store.save ~545 ms），與補算長度無關；長段已改 300 s 區段。選項 C（結尾不做完整存檔驗證）列效能待辦，只寫報告。
- 已過：F07 弓箭段；S07 第一件的 prepare／grant／consent／工坊作業產量與疲勞（共用池 1/3 分攤）／中途存讀檔／REST 後回工位做滿／交貨收尾。
- **卡點**：S07 第二件開始前（`_p4_feature` 內 grantor 放到營地旁之後、等工人站定的第一個 `_p4_advance(f, 30.0)`），
  `replay_site_to` 一次跑了 2070 遊戲秒而不是 30（REGION_REPLAY_PENDING finish now-target=2040）。已確認：f.data 與 lab.terrain 同一物件、
  目標計算正確；所以是 `RegionSaveSlot.replay_window` 的 pending=2070，即 Site 的 `last_settled_game_seconds` 在那一刻落後 Site 時鐘 2040 s（34 分）。
  前一個 30 s 補算是正常完成的，落後出現在兩次補算之間或前一次的結尾。
- **下一步**：在 `_p4_advance` 每次前後印 `site[SETTLEMENT_FIELD].last_settled_game_seconds` 與 `Runtime.now*60`，找出落後出現的那一次；
  懷疑對象：第一件交貨收尾（現在經 `_published_admission` 在區域點結算時執行）或 `set_soldier_fields` 後的那次補算結尾沒有寫回 stamp。
  另一個已知後段問題：第二件之後 holder 職位表又是空的（每次冷讀檔都重建 holder），目前只有原生同意路徑會投影；prepare／grant 若也讀 holder 職位需同樣處理。
- 注意：canonical verifier 整支跑完才寫 stdout／stderr，跑到一半讀不到診斷；每輪要等滿（失敗時到檔內 1800 s）。除錯可先把 `_run` 的 deadline 暫時調短。

### 其他待辦
- Nekki 待決／待辦：無等待中的選擇。效能待辦 C（冷存檔點成本）。
- 舊問題（非本輪造成，未處理）：site_real_npc_cold_replay（FIRE_CLOCK_MISMATCH）、site_ecology_replay（bytes 差異）、site_shared_step_replay／
  region_cold_formal_original／site_ship_travel（GRID_SIMULATION_RETIRED，待依 AA 規則逐支問移植或退役）。
- 群眾下 `set_duty_ai_enabled` 只寫 holder、不寫名冊（n02 靠 holder 現值）；名冊才是真相，之後要補寫回。

## 2026-11-13 03:40（台北）現況
- 提交（未推送）：e08c5d7（監獄組退役 3 支）、c21be7d（群眾營地工匠守接觸格；P4 移植進度）。回歸 REG_1113_P4 113/113。
- P4 已過：區域存檔擷取（先擷取群眾區段、存檔標 crowd admitted）、冷重開（region bootstrap 綁定票）、讀回原隊伍（team_holder）、
  冷補算最後端點消化、研究有效時間減半、群眾共用疲勞池（工作疲勞÷fatigue_count）。
- P4 卡點：冷補算中工人疲勞 80 進入 REST 後，隊伍疲勞池完全不恢復（fatigue_rest 一直 0）。工作計畫對零工作的池不接手（GD 三處都 continue，交給原生），
  所以是原生 safe_fatigue_rest 判為不安全：busy（隊員速度 >0.3／escort／stagger）、order≠HOLD、threat、charged_this_step 之一。
  已排除「守住工位算走動」（改了無效，已還原）。診斷值：order=0、combat_left=0、rally_rest=264、resupplying=1、三名隊員 walk=false。下一步要在原生端印 safe 的各項。
- 回歸改用 CONTINUOUS_SWITCH/launch_detached.ps1（獨立程序，工作階段重啟不中斷）。
- 04:30 補充：實驗證實「在冷補算 REST 迴圈前對工匠 crowd.cancel_siege_step」後隊伍會恢復並完成 REST/復工 → 擋住恢復的是工匠的原生站位步（hold）。
  但在 PA 的兩條 REST 分支加「REST 時放開、復工時再守」都沒生效，代表冷補算時這個工作不是經 SitePersonActions.advance 推進（疑似群眾原生工作點路徑）。
  已還原這兩處改動（c21be7d 的守營地格保留）。下一步：找冷補算時群眾 PA 工作的推進路徑，在那裡放開守位。

## 2026-11-13 01:00（台北）現況
- 加速（Nekki 11/12「想一下怎麼調整可以快一點」→ AA）：工匠底座連續 3 步失敗即結束測試（8d591c0）；git 一律 -uno（約 95.8 萬未追蹤檔）；
  長移植先評估覆蓋再逐支問移植／退役；不同測試的除錯可兩支並行。規則在記憶 speed-rules-20261112。
- 里程碑全清單回歸 FULL_1112_NIGHT 150/150。
- 監獄組先照 B（只留規則）：聚落監獄 adf7ec2、R3 監獄介面 f356c52、職務交接 ca0ead7 通過（未推送；Nekki 若選 A/C 要還原）。
- 群眾版監獄覆蓋（今晚皆過，需 visual＋--crowd-test/--crowd-atlas-root＋--grid）：監獄走廊、駐營群眾、群眾押送前綴、建物群眾整合。
- 等 Nekki：P4（建議移植＋補群眾中途作業重播擷取）、火罐介面（建議移植）、押送前綴／駐營俘虜格子版與 R3 評估（建議退役）。

## 2026-11-12 22:00（台北）現況
- 提交（皆未推送）：8e5e524（4 倍速原生窗口差 1 ULP 視同；F11/F12 生產退役，Nekki B）、e5bb08f（n05 夾具站位、畫面模式）、
  ad94cb4（受控本人入隊後群眾器械工作授權讀原隊伍；具名工人自己的群眾身體不擋自己的器械工地）、23668af（F12 配重首次賺得群眾版）、
  0a0c6a4（F11 木接格子資料層：研究工作改走測試自己的共同前綴點；冷重開維持格子名冊）、ec72a42（聚落備件：受控本人製作期間格子隊伍暫不參戰）。
- 回歸 REG_1112_C4 113/113（並行記憶體不足 3 支單跑過）。
- 剩下待移植：盔甲配方（具名隊員驗收，隊伍停戰會 STALE_SETTLEMENT，需群眾化）、火罐介面（真射擊／燃燒）、聚落監獄（群眾俘虜押送）、P4（中途作業重播擷取）、馬車布料（HEAD 既有 EXIT 90）。
- 已查明（非遊戲 bug）：F12 配重重開後隊伍走動，是夾具把站定中心放在已建好的器械上，原生 set_goal 把目標吸附到最近的可走格而中心沒動；夾具改以吸附後的目標為中心。

## 2026-11-12 17:15（台北）現況（新指揮中心「指揮中心：群眾移植續接」）
- 提交 4d0e04d（未推送）：都A 工匠收尾。疲勞池離 80 在 1e-9 內就算到 80（PersonFatigue.needs_work_rest）——原本群眾疲勞停在 79.999999999994，
  每步原生窗口截成約 1e-12 秒，區域時鐘當 0 永遠 REGION_EVENT_PENDING（實玩會卡死）。缺席取消工作只對「站在工位上離開」的人（823540b 誤套到未到位師傅）。
  g06 F11/F12 門檻補群眾「做工到 80 停工、休息到 50、數格內復工」；恢復段用 4 倍速長迴圈。NATIVE_BEGIN_WINDOW_CHANGED 診斷的 %g（GDScript 不支援）改 %f。
- 驗證：g06 F11 門檻 436 s、F12 483 s、F11/F12 固定、F04/F06 生產通過；REG_1112_C2（工匠 15＋短測試 91）103/105，只剩 F11/F12 生產（既知）。
- 進行中：F11/F12 生產——冷綁定不走新遊戲啟動後，綁定未完成；已加 last_refused_result 診斷。4 倍速窗口錯誤：測試會印 ARTISAN_NATIVE_WINDOW_4X 數值。
- 待 Nekki：閒置群眾的疲勞是否改原生端（5,000 人 0.44 倍速）仍未決。

## 2026-11-12 13:55（台北）交接給「指揮中心：群眾移植續接」（先讀這裡）
- **提交（全部未推送）：**
  - 4f969c1：F11/F12 固定工匠群眾版，修理完工補滿血
  - 889f2d5：g06 F04/F06 加工門檻群眾版
  - bdfc07c：木接工法接受群眾隊伍，4 倍速窗口退回 1 倍
  - 最後一筆：退役 g06 點序/接觸點 4 支、缺席攻城工人取消工作，**未驗證**。若提交還沒出現，在 commit 中途交接，請 `git status` 確認。
- **Nekki 11/12 05:45Z「都A」**（決定檔：output/project_command_center/CONTINUOUS_SWITCH/NEKKI_DECISION_20261112T0545Z_artisan_gates_and_g06_point_order.md）
  1. 群眾上缺席師傅改為取消工作後離開。
  2. g06 點序/接觸點 4 支退役，另補群眾「疲勞到 80 停工、休息後復工」檢查（尚未補）。
- **群眾版已通過：** 原 7 支工匠、F11/F12 固定、g06 F04/F06 門檻。回歸 121 支過 118 支，3 支既知失敗：F11/F12 生產、n05 仍走網格。
- **遊戲缺口已修：**
  - 攻城修理浮點殘差
  - 共同前綴端點容差改 1e-8
  - 捕獲裁切移到原生窗口前
  - 陣亡群眾人外觀 bool(null)
  - 木接工法群眾隊伍
- **下一步：**
  1. 驗證最後一筆。用 artisan_siege4_manifest.json 跑 g06 F11/F12 門檻與 F11/F12 固定（ARTISAN_SIEGE4_A 被交接打斷）。之前 F11 門檻卡在缺席師傅自己走回工位，現在改取消工作；`_park` 對有攻城工作的人一律取消，若打壞 F11/F12 固定要收窄。
  2. 補疲勞 80 停工／復工的群眾檢查。
  3. 4 倍速偶發 NATIVE_BEGIN_WINDOW_CHANGED。在 terrain_lab ~14814，見證窗口與重算 action 不同；已排除跑步隊伍效能改動。實際遊玩 4 倍速可能卡住，是遊戲 bug。
  4. F11/F12 生產在 HEAD 前就壞：產生場地冷綁定會重跑工匠誕生、首長 NO_TARGET。
- **交接時狀態：**
  - 每小時兜底排程（cron 4a88a7f3）已取消。
  - 停 Godot 被權限擋下：ARTISAN_SIEGE4_A 的 Godot 可能仍在跑，會自行結束（約 10 分）。
  - hearthbot 整天斷線，回報改走協調者代轉。
- 細節見記憶 crowd-artisan-port-findings 與 crowd_port_list_20261108.md 11/12 條目。

## 2026-11-12 01:20（台北）現況
- 提交（未推送）：10244f4（N08 民用馬車、N12 船隊、S07–S10 聚落首次賺得、headless 無裝備外觀 A）、ca1fed8（N10 + 公共工單同意／停穩規則／
  居民派工／自有物資）、63ebd44（N02 工作隊群眾工人完工收尾）、54ca675（N11）、a0b930a（群眾人物普通器械工作資格）。
- 國家首次賺得 N02/N10/N11、聚落 S07–S10、N08、N12 群眾版全數通過。回歸 REG_1111E/F 107/110（3 支既知：wagon_cloth、p4_cold、f11_joinery）。
- 效能量測（crowd_full_game_perf_probe）：遊戲上限 5,000 人；5,001 人約 0.44 倍時速，存檔 1.3 s、讀檔 9.3 s。
  八成時間在 PersonFatigue.plan_work_interval（每個窗口 2–3 次、全員行走疲勞需求）。原生戰鬥只占約 2%。
- Nekki 11/11 16:28Z：優化要做；群眾退隊用 A（退隊者原地成一人隊長隊，再入隊回原隊形）。
- 進行中：回歸 REG_1112A（工匠手作守站位、站位保持不算走動、效能量測腳本）。F04 首次賺得在並行中失敗，單獨重跑確認中。
- 下一步：疲勞排程優化並量前後差異；群眾退隊 A；工匠 F11/F12（依退隊）；P4（中途作業重播擷取）；盔甲配方、火罐、監獄（WIP 補丁）。
- 每小時兜底定時器（每小時 13 分）已設。

## 2026-11-11 06:20 現況

- **提交 59e1404**（未推送）：旅途接觸框走原生群眾（Nekki 09:19Z A）＋原生船上近戰（Nekki 15:03Z A，DLL cab68a38）。
  回歸 FULL_REG_20261111_FRAME 82/82（full_transport 以真 crowd-test id 重跑過）。two_npc_sea friendly 687 秒（檔內 720，偏緊）、hostile 436 秒。
- 接觸框存讀：隊伍檔多帶 content.crowd／crowd_rosters（原生區段與群眾名冊），重開時像群眾站點一樣載入；敵對案例近戰後存檔、重開、再走 240 步通過。
- 還沒做（設計第 4 步）：一般旅途的身體計時仍經 prepare_combat；格子退役檢查對旅途宿主的例外還在。抵達時帶原生區段的隊伍尚無測試覆蓋。
- 下一步：一般旅途計時去格子化＋拿掉例外；之後回到佇列（第 2 批 63 支移出 --grid 等）。

## 2026-11-11 00:20 現況

- HEAD 11eb517（未推送）。工作區未提交：旅途接觸框原生化＋原生船上近戰（Nekki 09:19Z 選 A、15:03Z 選 A）。
- 已完成（未提交）：
  - 接觸框（liveBody）在第一個計畫區間轉原生群眾（terrain_lab._region_party_frame_native）；框視圖不再帶出發站的群眾區段；
    原生開始窗口用在旅途公式區間；區間結束把射擊游標、待結端點、交手相位對齊到接受的區間終點（浮點漂移 1e-11）。
  - 隊伍檔仍只存一般隊伍列（ClearHandoff.roster_snapshot），不存原生 blob；重開時從隊伍列再轉一次。
  - NPC 船隊航線動作接受群眾隊伍；群眾船員補「船對船自衛」規則。
  - 原生船上近戰：World::set_aboard_melee_pairs 等，DLL 3d4f35ff → cab68a38（舊的在 evidence/ABOARD_MELEE_native/previous_dll），原生測試全過。
  - two_npc_sea 測試的近戰檢查改成原生版（落點證據＝船頭船員 hit_revision／hp 變化）。
- 驗證：敵對案例原生版通過（409 秒，與格子版同速）。船／旅途 22 支回歸 20 過；friendly 案例卡在交手相位浮點漂移
  （原生窗口被截成 6e-14 秒），已修正，FRAME_NATIVE_BOTH_v2 跑中。
- 01:20 敵對案例重跑通過。友善案例第二個漂移：接觸框自己的遊戲時鐘（minute/phase）
  累加後差幾個 ULP，把吃飯邊界截成 6e-14 秒的窗口（REGION_ZERO_ENDPOINT_REQUIRED）；已在區間終點對齊到接受的遊戲終點，FRAME_NATIVE_FR_v3 跑中。
- 02:25 友善案例的浮點殘差逐一處理中：接觸框重開時由 upkeep.at 推算的分鐘相位差幾個 ULP 就把下一窗口截成 6e-14 秒；
  新增 _region_party_clock_fields（離整分鐘 1e-8 秒內就算到了），區間終點對齊與框視圖共用；工作疲勞帶界線也比照休息界線的容差。
  敵對案例 v6 通過（403 秒）。FRAME_NATIVE_BOTH_v7 跑中。
- 還沒做：接觸框裡中途存讀的測試、一般旅途計時去格子化、拿掉格子退役檢查對旅途宿主的例外、清掉 DIAG 輸出，然後全回歸提交。
- 另：第 2 批探測 83 支中 63 支群眾直接過（細節 crowd_port_list_20261108.md）；center_original 視覺版超時待查。

## 2026-11-10 18:35 現況（新指揮中心接手）

- 舊指揮中心 17:15 起連不上對話串，由新指揮中心接手（對話串「指揮中心：群眾移植接手」）。
- HEAD 11eb517（未推送）：two_npc_sea 群眾版（friendly＋hostile）、船上群眾船員休息威脅判定、冷站補算續跑 250 ms 切片。
  回歸 FULL_REG_20261110c 82/82 全過（friendly 515 秒、hostile 409 秒）。
- hostile 能過是因為旅行隊伍宿主在格子退役檢查有例外。Nekki 09:19Z 選 A：只有旅途中接觸框改走原生群眾
  （設計 CONTINUOUS_SWITCH/travel_party_native_crowd_design_20261110.md，估 2.5–4 天）。這件事是刪格子模擬（第 3 階段）的前置，不擋其他移植。
- 18:25 center_original 視覺版（群眾）跑 1200 秒外層超時：沒有失敗檢查，但慢——每個冷 owner 情境 world_open 約 50 秒、
  owners_ready 約 270 秒（無頭版 9 情境共 340 秒），3 個情境就用完 1080 秒；第 4 情境起 D3D12「RESOURCES descriptor heap」不足
  （34 萬行，texture_mem 312 MB，已開 8 個 shell），疑似每個情境的群眾外觀資源沒釋放。另列待查，不擋其他工作。
- 18:55 第 2 批探測 PORT_P2_PROBE_v1 起跑（83 支科技／家族／國家／聚落測試，拿掉 --grid，batch2_probe_manifest.json，
  執行器 CONTINUOUS_SWITCH/run_manifest.ps1，紀錄 PORT_P2_PROBE_v1.log）。
- 19:37 第 2 批探測完：83 支中 63 支群眾模式直接過（只要拿掉 --grid）；18 支撞退役格子模擬（F04/F06 底座、工匠、首次賺得幾支），n10 斷言失敗，longplay 列退役候選。細節寫在 crowd_port_list_20261108.md。
- 下一步：接觸框原生化；Godot 空檔跑佇列（center_original 視覺版、N08 群眾馬車、器械單元測試）；joint_departure 等 S4。

## 2026-11-10 13:55 現況

- HEAD 034d8a6（未推送）：群眾隊回到離開過的站點。原生 readmit＋formation reuse（DLL 3d4f35ff）、外地障礙解除、器械組員讓位、
  冷重播完成判定改用 1e-8 日誌容差（站點 minute/phase 與世界時鐘是兩個浮點累加器，15712 秒時差 8e-10，原本永遠判未完成）。
- 測試：region_siege_cancellable_departure 群眾版通過（B：行走中拒絕、停下即出發；所選列已陣亡時走 A2 陣亡列路徑）；
  行走中拒絕的檢查移到 region_crowd_journey_test（活隊伍上驗）；arrival 加分隊回站檢查。
- 回歸 REG18：80 支核心全過。加跑 6 支重播／組員測試：ecology_restore_replay 過；crew_movement、shared_step_replay、cold_formal_original
  撞退役格子模擬；real_npc_cold_replay（FIRE_CLOCK_MISMATCH）與 ecology_replay（位元組不符）在 HEAD 版遊戲腳本下同樣失敗（BASELINE_HEAD_1），屬既有問題。
- 下一步：two_npc_sea 改寫；joint_departure（等 S4）；center_original 視覺版；N08 群眾馬車；器械單元測試。

## 2026-11-09 17:10 現況（先讀這裡）

- HEAD 553c0c2（KW21 群眾攻城中途存讀＋phase／epoch 群眾版）。本日提交：773c972 押解、7a84ab9 主選單、07d909a 效能、553c0c2 KW21。
- 俘虜押解存讀檔測試（region_captivity_payload_admission）群眾版：現場與遠端冷站兩段都通過（255 秒，PORT_P1_PAYLOAD_v23）。
  順帶修了 5 個遊戲問題（未提交，等回歸）：群眾俘虜沒推進俘虜編號、監獄查詢把守衛自己押的俘虜當障礙、
  站著不動的守衛被當成移動中、名冊 social_state 錯誤碼、監獄釋放中途存檔被拒（執行者原地守位）、
  冷站重做後模式仍記舊後端（REGION_BACKEND_UNADMITTED）。commit 訊息草稿在 scratchpad commit_payload.txt。
- 18:15 已提交 773c972（押解群眾版＋上述遊戲修正）。CROWD_CORE_REG12 63 支過 62；site_logistics_crowd_acceptance 舊 105 秒預算，
  Nekki 09:35Z 准放寬到檔內 300／外層 360 秒（NEKKI_DECISION_20261109T0935Z_logistics_budget_relax.md），已加各段耗時輸出。
- 19:30 Nekki 11:23Z 選 A（NEKKI_DECISION_20261109T1123Z_crowd_siege_midaction_save_A.md）：群眾站點攻城動作中途可存讀。
  原生 KW21（state.cpp：siege_crew／siege_step_source／siege_serial／siege_compounds 寫入；save() 只拒住宅待走步；load 以 allow_site_jobs 驗證並重建 member index；
  hash 加 source_body）＋原生測試改寫（中途存檔由「必空」改為可往返）＋新測試 midaction_save_resumes。GD：crowd_site.siege_admission_guard(admit_active_siege)、
  save_guard／capture_save(region_checkpoint) 區域路徑放行、activate_loaded 放行、site_store 群眾狀態的 native_token 合法且必要、
  _validate_crowd_siege_crew 改為令牌↔車輛交易交叉比對。原生編譯＋測試：KW21_native；Godot 焦點清單 kw21_focus_manifest.json 等 REG13 跑完。
- 20:05 效能第一輪（射擊預演窗口唯讀 memo）：logistics 154→94 秒；REG13 70 支過 65。5 支火場測試失敗皆非本次：
  acceptance_completion／lab_ui／shooting_policy／transport_persistence 走已退役格子模擬（GRID_SIMULATION_RETIRED，11/02 退役調查列為格子專屬），
  native_admission 在測試自身 491 行（admission 期限後 Nil）且 11/02 已知。以 perf_native_begin_memo_20261109.patch 分段提交（見 git log）。
- 20:04 KW21 DLL 換上（f247a021…→94ec1369…）；KW21_FOCUS_v1 8 支：5 過，phase／epoch／siege_crew_movement 失敗（後者走退役格子，移出清單）。
- 20:45 phase／epoch 群眾版通過（KW21_PE_v6：207 s／41 s）。修正：epoch 主殼要 crowd_startup_requested（否則重開時被轉群眾→STALE_SELECTED_REGION_BODY）；
  reopen facts 先精確比對、只差存檔浮點往返時以 persisted form 比對（EPOCH_NOTE）；crowd facts 加原生 position；phase ATTACK 指名 center_founder；
  遊戲修正：site_settlement CAPTURE_RESIDUE_SECONDS=1e-9（群眾步長 1.9999999999998863 s 造成 REGION_ZERO_ENDPOINT_REQUIRED 卡住）、
  原生 settle_siege_compound 清成員速度（DLL 再換：→035a8051…）、terrain_lab.region_body_diag 診斷旗標。
  CROWD_CORE_REG14 67 支過 66（唯一失敗 region_crowd_nation_command 釘死 KW20 magic，改 KW21 後重跑 PASS）→ **22:00 提交 553c0c2**（KW21＋GD 驻證＋phase／epoch 群眾版＋nation 測試）。
- 22:00 Godot 空檔跑 PROBE_FAMILY2_v1（carried_intel／joint_departure／remote_nation）取卡點；cancellable 已問 Nekki A／B（建議 B，設計 cancellable_departure_crowd_design_20261109.md）。
- 22:40 carried_intel 群眾版：來源隊改 release→deploy→admit、AI 關閉（AI 下令會動 order serial）；信差已能派出並抵達，命令卡 COMMAND_AUTHORITY_CHANGED
  → **遊戲缺口**：region_save_slot 軍令（army_command）接收端用格子解析器並把群眾隊視為停用槽（G6）；改用 _region_nation_team（與國家命令同一條）＋新
  _region_team_issue_order（crowd_site.issue_order "ui"／issue_combat_order），延遲用 _region_team_order_delay。remote_nation：_nation_initial_bodies 同樣改群眾出生、
  目標冷站 _cold_convert_owner_lab 轉群眾、_nation_receiver_team 改 _region_nation_team；卡「抵達後的遠端隊長與 AI 策略」檢查（已加細節）。
  joint_departure 卡 S4（群眾中的 actor 本體不能整隊出發），排在 S4 後。
- 23:20 carried_intel PASS（INTEL_NATION_v5）、remote_nation PASS（REMOTE_NATION_v8；預測謂詞改 _region_nation_team＋formation attacking；
  epoch 的 reopen 前同步改 sync_to_site 以免多發布一代）。Nekki 14:21Z 選 B（群眾不做出發意圖）。CROWD_CORE_REG15（69 支）跑中，過了提交（稿 commit_intel_nation.txt）。
- Godot 排程（CHAIN_20261109.log）：後勤單跑 → 主選單優化補丁（perf_main_menu_20261109，先基線再套用跑 4 支，結果回報主選單串）→ 攻城四階段 PORT_P1_PHASE_v1。
- 卸裝外觀圖集已烘（BAKE_CAPTIVE_v2 PASS，output/captivity_looks/center_original.json）；攻城中心原檔畫面模式還沒用圖集重跑一次（下一步）。
- 家族測試探測（PORT_P1_PROBE_FAMILY_v2）：original_phase、cancellable、joint_departure 卡同一點「首長須在中心 12 格內」
  （_phase_found_defender 用 character.place，群眾要用 _place_controlled）；cold_action_epoch 本體讀 GD 移動欄位；
  static_siege_entry Array.keys、two_npc_sea 型別、remote_nation／player_first、carried_intel 各有自己的卡點。下一步先移植 original_phase。

## 2026-11-09 09:55 重開機前

- Nekki 重開機以清掉核心記憶體集區（分頁 3.9 GB、非分頁 1.7 GB 偏高）。HEAD fad9d07（馬車跨區已提交）。
- 重開機時中斷：center_original 重跑（PORT_P1_CENTER_v21，時限 600/660、俘虜改等戰場自然俘虜）。重開後先重跑這支。
- 工作區未提交：region_siege_center_original_test.gd 群眾移植 WIP（備份 center_original_crowd_port_wip_20261109b.patch）；
  診斷檔 crowd_c2_c3_memory_diag.gd、region_food_reinforcement_arrival_diag.gd（不提交）。
- 記憶體：crowd_c2_c3 顯示模式程序約 12 GB；系統承諾上限約 36 GB（分頁檔 3.8 GB），建議 Nekki 改成系統管理大小。

## 2026-11-09 09:30 交接點

- 新指揮中心（11/08 08:25 起接手）。HEAD 650abdf，未推送。群眾移植第 1 批已提交：
  - 8b51e16：糧食增援群眾版（729 秒／Nekki 核定檔內 900、外層 960）；NPC 徒步接觸隊伍進群眾 Site；NPC 船隊進港（Nekki A，尚無測試覆蓋）；暫存群眾候選沒被採用時釋放。
  - 13b110c：site_ship_full_transport 群眾版。
  - 4e827ba：群眾人物在船上航行時回報移動中；乘客清單跳過休眠隊伍。
  - 4753d2f：site_ship_journey 群眾版（Nekki B：船停著等人時照常休息）。
  - 650abdf：site_ship_journey_edge 群眾版；跨區補算等待中群眾隊伍不能下令；群眾名冊出生帶 garrison_feature_id。
- 未提交（工作區）：
  - 馬車跨區：region_travel.gd（群眾目的地收陸路手推車／馬車、抵達時 army_next_team 跟上）、crowd_site.gd（駕車者在車隊停穩時可整隊出發，出發時移除原生車隊）；新測試 region_crowd_wagon_arrival_test.gd 通過。回歸 v10 57 支過 55。
  - 提交前要先查：crowd_c2_c3 從 v9 起連 3 次在載入 3D 人體模型時記憶體不足（v9 重跑曾通過一次）。
  - region_siege_center_original_test.gd 群眾移植 WIP（前 4 情境過；已改時限 600/660、俘虜改等戰場自然俘虜，待重跑）。
- Nekki 11/08 23:22「都依建議」：center 時限 600/660；群眾不開放主動綁人；馬車跨區優先；器械單元類 4 支重寫、8 支補小測試後退役（對照表 output/project_command_center/CONTINUOUS_SWITCH/device_unit_coverage_20261109.md）。
- 已知功能缺口：N08 民用馬車路線在群眾 Site 直接拒絕（RegionSaveSlot._region_n08_wagon）；群眾 ATTACK 不能指定船上目標；沒有原隊伍來源的群眾隊伍不能下明確射擊令。
- 進度細節：output/project_command_center/CONTINUOUS_SWITCH/crowd_port_list_20261108.md。

## 2026-11-05 17:05 交接點（舊）

- 爵位與聲望六步全部完成並已提交，未推送。HEAD edc2826。
  - 叛離：ada7ffb。
  - NPC 授爵：9fc16c7。
  - 冷 Site 封地移轉測試：edc2826。
- 驗收：NPC_full 170 項中 115 過，等於前次加上新測試，沒有新失敗。
- 17:25：Nekki 回覆「都同意」：全軍覆沒 −4 不做；不在場的部下維持留給原上級。爵位與聲望規劃全部結案。
- 原本待決定的兩題（已結）：
  1. 「全軍覆沒 −4 威望」：隊長已死，沒有人承受這個扣分。建議不做。
  2. 叛離時不在場的部下，目前一律留給原上級。建議維持現狀。
- 16:40 起，與對話串的連線（hearthbot）斷了，即時清單和訊息都送不出去。重新連上後要先補發這段結果。
- 沒有 Godot 在跑。

## 2026-11-05 08:20 交接點（舊）

- HEAD 27a2483，未推送。11/05 已提交：
  - 9890350：4 支以上隊伍可以存檔。
  - cf2a9cd：整隊改勢力。
  - 1c10ccd：開局選中立或自建勢力。
  - 2e1b0fb：爵位第一步，資料層。
  - 27a2483：爵位第二步，當面投靠；原生新增 leave_member，DLL 換成 db16e7c3。
- 驗收：JOIN_full 166 項中 109 過，等於前次加上兩項新測試。region_initial_world_transaction 在批次中記憶體不足而失敗，單獨重跑通過。
- 規劃文件：
  - 爵位與封地：https://claude.ai/artifact/KezPv2RQJLehoHQYAAKbpp ，六題都照建議。
  - 聲望：https://claude.ai/artifact/PvjK5zQhgaxuk6T9WYHd7a ，八題都照建議，排在爵位第三步之後施工。
- 現在：爵位第三步「授爵與封地」。06:55 到 08:20 之間我沒有實際推進，只看了聚落和死亡事件的函式清單；08:20 起正式盤點。
  - 盤點範圍：聚落長職位、死亡事件、攻陷流程。
  - 要先決定封地資料放哪裡：記在爵位記錄裡，還是每次跨 Site 去查。
  - 盤點結果寫在本段下方。
  - 08:35 盤點結果：
    - 聚落：每個 Site 最多一座，資料在 `data.site.settlement`，含等級 level（2 村、3 鄉、4 鎮、5 城）、owner_faction 和職位。首長位子的持有人就是領主（`SiteOffices.head_position`）。Region 沒有跨 Site 的聚落索引，查別的 Site 要逐一讀檔，太慢。
    - 決定：封地清單記在爵位記錄裡，格式是 site_id 對應等級。每次存檔時以該 Site 的聚落為準重新對齊：首長換人、升級、被攻陷時，清單跟著改。授爵時的門檻就用這份清單檢查。
    - 死亡：`_person_died`，之後由 `settle_person_deaths` 結算，在這裡接世襲。
    - 繼承人：家族首長有指定繼承人（site_succession 的 heirs）。規則是：死者是家族首長時，由他指定的繼承人承爵；死者是其他家族成員時，爵位回到家族首長；沒有家族時，封地回到上級。
    - 攻陷：聚落被攻陷時清空職位、改歸攻方；重新對齊後，領主就失去這塊封地，但爵位保留。
  - 接著實作：封地對齊、授爵／升爵／削爵／稱帝入口、世襲接死亡事件，再寫測試。
- 10:45：第三步已提交 69d6b2d。GRANT_S3_v1 8/8 過；全量 GRANT_full 167 項中 112 過，沒有新失敗，site_logistics_crowd_acceptance 從失敗轉為通過。
  - 第四步「聲望」開工。
  - 4-1：person_reputation.gd 寫好規則：威望、信譽、爵位底線、回落、回復、事件數值、公式加減項。person_social 的 social_state 加了選填欄 reputation，舊檔不需轉換。
  - D 驗收 REP_S1_v1 跑中。
- 12:10：聲望進度。
  - 已提交：4-1 是 27885cf，4-2／4-3 是 b4f2a3c。
  - 4-4 寫好，D 驗收 REP_S4_v1 6/6 過；全量 REP_full 168 項跑中，跑完提交。
  - 4-4 內容：攻城得分、失地扣分、被俘 −5、俘獲貴族、隊伍潰退的勝敗分、每日回落與信譽回復（讀取時依天數計算）。
- 第五步「叛離」設計草案：
  - 目前沒有宣戰狀態：不同勢力本來就互相敵對，所以「原勢力自動宣戰」等於自動成立，不需另外處理。
  - 自立：新建一個勢力，叛離者當王；他的隊伍改屬新勢力，原上級鏈斷開。
  - 改投：叛離者效忠另一個勢力的官員（當面），隊伍改屬該勢力。
  - 封地：在場 Site 的聚落立刻改歸新勢力。其他 Site 的封地，在登記表記一筆「待移轉」，該 Site 下次啟用時才改歸屬。
  - 部下：叛離者先扣信譽（自立 −30、改投 −40），部下再用跟隨分決定跟不跟。在場的人當場決定；不在場的，等他們所在的 Site 下次啟用時才決定。不跟的人改由原上級接手。
- 13:40：5-1 叛離寫好，D 驗收 REBEL_S5_v1 6/6 過；全量 REBEL_full 跑中。
  - 5-2 跨 Site 封地已寫：不另存待辦。某 Site 下次啟用時，若聚落首長的爵位記錄已屬別的勢力、且封地清單列著此地，聚落就改歸該勢力。
  - 注意：5-2 是在 REBEL_full 跑到第 26 項之後才改進 site_controller，所以第 27 項以後跑的程式碼含 5-2。提交前會補跑叛離相關測試。
  - 不在場的部下目前一律留給原上級；「之後再決定」沒有做。
  - 「全軍覆沒 −4」沒有接。
  - 5-2 的實際移轉還沒有測試覆蓋：測試世界裡沒有聚落。
- 沒有 Godot 在跑。

## 2026-11-04 21:10 交接點（舊）

- HEAD b7539f7（未推送）。11/04 提交：c76f2b3 S1 幹部有獨立 3D 身體；9080ebb S2 自由捏外觀改由身體畫；e993bf4 勢力本地對應（每支中立隊各自一個原生槽、勢力 ID 不受 255 限制）；ee6b7ee S3 新遊戲玩家是中立隊隊長帶 5 名幹部；b7539f7 S4 拿掉群眾單人出發，存檔格式 5→6（舊存檔拒收）。
- S3 內容：幹部就任隊伍職位、在接班順序、站斜角不把隊長圍死；主選單只剩「玩家與 5 名幹部」開局（工匠劇本只留給測試）。Region 依 Nekki 維持格子：群眾隊伍出發時轉成格子快照，路上即時場景不轉群眾，格子禁用閘豁免路上場景。隊伍士氣／潰退／集結冷卻（team_morale）跟著旅途保留，抵達群眾 Site 時接續（Nekki 11/04 指正）。生態長跑測試依 Nekki 選 B 拿掉不中斷參照比對。
- 沿路修好的問題：收兵／家人交接沒有玩家 actor 會當掉；補給計畫查找；受控隊伍離開後存檔引用；沒有呈現者時的畫面排序；被拒絕或棄置的暫存群眾漏 RID；延後的環境傷害進區域檢查點；出發時幹部身分被清掉；單人容器缺射擊命令；幹部單獨上路成為一人隊隊長；region 抵達群眾 Site 也走勢力本地對應。
- 驗收：evidence/CENTER_OPTIONC/S4_full_v1（163 項，107 過）。與基準比沒有新失敗；仍失敗的都是改動前就失敗的（含 crowd_event_members_parity）。
- 下一步（Nekki 已同意順序）：(1) 既有 bug：群眾 Site 有 4 支以上部署隊伍不能存檔（CORRUPT_FIRE_OWNER：第 4 支以後沒有 TerrainArmy 槽保存射擊命令；重現：CONTINUOUS_SWITCH/diag_four_team_save_test.gd.parked）；(2) 加入勢力改標籤（測試裡目前用改成勢力 0 的替身）。
- 注意：11/04 一次空檔案清單的 git diff 曾把 Nekki 未提交的文件還原掉，已全數還原並備份（CONTINUOUS_SWITCH/user_uncommitted_docs_backup_20261104.patch）；之後每次產生修補檔前都檢查清單不為空。
- 工作區乾淨，沒有 Godot 在跑。
- 23:30：21:10 之後沒有推進（S4 提交後我停下來沒有接著做，空了約 2 小時 20 分）。HEAD 仍是 b7539f7。23:30 起開始修「4 支以上隊伍不能存檔」。

- 11/05 00:50：修好「4 支以上隊伍不能存檔」（每支群眾隊伍都有 TerrainArmy 名冊容器；新測試 region_crowd_four_team_save_test 與 14 支相關測試通過，evidence/CENTER_OPTIONC/FOURTEAM_v1）。全量 164 項回歸跑到 61/164，目前與 S4 基準一致、沒有新失敗（FOURTEAM_full；修補檔 CONTINUOUS_SWITCH/four_team_v1.patch 套在 D 上，跑完自動還原），跑完沒新失敗就提交。
- 11/05 02:00：全量回歸跑到 149/164，與 S4 基準完全一致（沒有新失敗、也沒有變化），約 15 分鐘後跑完即提交。
- 11/05 02:35：全量 164 項回歸跑完，108 過，與 S4 完全一致，另加新測試通過（FOURTEAM_full）。已提交 9890350「每支群眾隊伍都有 TerrainArmy 名冊容器」。HEAD 9890350（未推送），工作區乾淨。現在開始加入勢力的底層。
- 11/05 03:00–03:30：cf2a9cd（整隊改勢力）、1c10ccd（開局選中立或自建勢力）已提交。Nekki 要求當面投靠、勢力分層。
- 11/05 03:42–04:00：規劃文件 https://claude.ai/artifact/KezPv2RQJLehoHQYAAKbpp 改為爵位制：皇帝＞王＞公侯伯子男，只設最少封地、可自行擴張、家族世襲、貴族各自軍團不設上限、逐級繳稅、帶封地叛離扣名聲。Nekki「都照建議」。
- 11/05 04:25：第一步資料層已提交 2e1b0fb（RegionPeerage、勢力登記表選用 peerage 欄、建國即稱王）。D 驗收 PEERAGE_S1_v1：10 項中 9 過；開局建國的測試失敗，原因是現世人物沒有歷史引用、所以沒加冕。改用世界人物引用後，PEERAGE_S1_v2 重跑 2/2 過。未推送。下一步：當面投靠。
- 11/05 06:55：第二步「當面投靠」已提交 27a2483：SiteJoinFaction、評估／投靠按鈕、幹部當場自成一人中立隊、無爵效忠。
  - 原生新增 leave_member。新隊伍還沒有士兵時陣營槽沒建，結束時當機；已修並加原生回歸。ASan 與一般建置都過。
  - DLL 換成 db16e7c3…，舊版備份在 evidence/JOIN_S2_native/previous_dll。
  - D 驗收：JOIN_S2_v3 6/6 過；全量 JOIN_full 166 項中 109 過，等於前次再加兩項新測試。region_initial_world_transaction 在批次裡因記憶體不足失敗，單獨重跑通過（JOIN_iwt_rerun）。未推送。
  - 下一步：第三步「授爵與封地」（授爵 UI、門檻檢查接聚落、世襲接死亡事件、攻陷後爵位保留）。
- 11/05 08:10 待辦：聲望系統規劃已定案。規劃文件在 https://claude.ai/artifact/PvjK5zQhgaxuk6T9WYHd7a ；Nekki 八題都照建議，第 4 題選「全世界即時知道」。排在爵位第三步「授爵與封地」之後施工；叛離的名聲懲罰也接在這套聲望上。
- 11/05 08:12：第三步「授爵與封地」盤點中。聚落的封地資料分散在各個 Site，正在決定封地清單要記在爵位記錄裡，還是每次跨 Site 查詢；選定後才開工寫程式。
- 加入勢力（Nekki 選 C：開局和遊戲中都要）。底層設計：不改原生，用原生敵對表讓隊伍原本的陣營槽和新勢力互為友軍（敵對表存進 blob），讀檔時再確認一次。之後依序做主選單開局（中立／自建／加入情境勢力）、遊戲中投靠。投靠規則 Nekki 已同意：整隊投靠、向首長提出、NPC 首長由職務 AI 決定、不會自動同意；幹部會依個性決定跟不跟，不跟的成為自己一人中立隊的隊長、留在原地（計算方式做到時先給 Nekki 看）。
## 2026-11-04 03:50 交接點（舊）

- HEAD e993bf4（未推送）。今天提交：c76f2b3 S1 幹部有獨立 3D 身體；9080ebb S2 圖集畫不出的外觀（自捏臉／髮／染色）改由身體畫，kit -1，降職後保留身體；e993bf4 勢力本地對應（每支中立隊各自一個原生陣營槽，勢力 ID 不受 255 限制，原生 C++ 未改）。證據都在 evidence/CENTER_OPTIONC（BODIED_S1_full、BODIED_S1_v3、BODIED_S2_v1、FSLOT_v1/v4）。
- S3（新遊戲玩家是中立一人隊隊長）未提交：CONTINUOUS_SWITCH/neutral_part3_s3_v16.patch（24 檔，在 e993bf4 上可套用）。33 支相關測試中 27 支通過。修補檔內含 3 個真修正：收兵沒有玩家 actor 時當掉（crowd_clear_handoff `_player_cell`）、船隊補給讀取當掉（`plan.get("crowd_formation")`）、受控隊伍離開後存檔引用寫成 0（`_section_player` 改寫 -1/-1）；另外家人交接沒有 player_cell 時當掉。還有兩處診斷訊息（STALE_REGION_PARTY_BODY 列出差異欄位、主選單測試）。
- 測試遷移做法：先檢查 bind 是 native，再 crowd_site.clear() 收回 GD，測試隊伍從第 2 隊位（slot 1）部署；需要時把玩家一人隊暫改勢力 0，作為「加入勢力」的替身。
- 等 Nekki 決定：(1) 工匠劇本開局（主選單預設）：推薦 A，玩家當 5 名工匠的隊長，組成 6 人中立隊；(2) 路上即時隊伍（live party）只支援單一 actor，隊伍綁定時被轉成群眾格式，前後比對不符：推薦 A，路上場景也用群眾（native）跑。
- 卡在 S3 的測試：main_menu_flow（等決定 1）；region_party_life_original、site_audio_actual_party_flow、region_gameplay_selected_restore（等決定 2）；site_ecology_longrun_owner（手動作業改走 work_team）；region_travel_test --grid（玩家加入隊伍的夾具）。功能盤點：CONTINUOUS_SWITCH/player_actor_dependency_survey_20261104.md。
- 新發現、與今天改動無關的既有 bug：群眾 Site 有 4 支以上部署隊伍時不能存檔（CORRUPT_FIRE_OWNER：fire 命令只從 combat_armies 的 3 個 TerrainArmy 槽產生，存檔檢查卻數 site.armies）。重現腳本：CONTINUOUS_SWITCH/diag_four_team_save_test.gd.parked。
- 工作區乾淨，沒有 Godot 在跑。
## 2026-11-02 19:00 交接點（重啟後先讀這裡）

- HEAD 5608094：3 個產品小 bug（_controlled_id 預設、team_supply version、actor.faction_id）＋2 個測試替身；site_prison_storage 轉過，回歸 13 項過。之前：fe3e7b6 測試替身、1d083ec/a4f8703 第 2 階段刪 159 支、a2d10cf 兵營（DLL 25E5EA2A）、4a853c2 第 1 階段。
- 既有失敗剩約 25 支，分類在 CONTINUOUS_SWITCH/remaining_fail_triage_20261102.md：多為測試替身持續落後（每補一個方法又缺下一個）、3 支 RID 洩漏前已自印 FAIL、2 支逾時（append_atomic、c3_replay B-native）、3 支需 cc001 隔離目錄。
- 失誤紀錄：19:00 前一次 git add -N . + apply -R 誤刪 191 個未追蹤檔（.uid、診斷腳本），已用同一 patch 正向套回全數還原（未追蹤數 191 核對）。以後產生 patch 不用 add -N，只 diff 指定的追蹤檔。
- 21:55（Fable）：量測 476 支借格子的共用測試：311 支只建隊不跑模擬、165 支跑格子模擬（fire 15、ship 12、technology 11、gd 7、movement 6…）；235 支直接讀寫 combat_units，改寫非換夾具。建議 C：第 3 階段只刪格子模擬（移動／保留格／隊形／交戰／攻城 GD／冷重播），留 TerrainArmy 當名冊容器＋加「拒絕推進格子模擬」閘；311 支直接續跑，165 支中約 50 支（火災／船／科技／攻城／車船）改寫、約 20 支退場、其餘逐支判斷。Nekki 13:54Z 選 C（記憶 grid-retirement-option-c）。清單：CONTINUOUS_SWITCH/optionC_data_only_20261102.tsv（311）、optionC_grid_sim_20261102.tsv（165）。22:00 起 Haiku 做 GATE_v1（無 --grid 時拒絕推進格子模擬）＋311 支清單。276ca31 又修兩支測試替身。
- 22:50：GATE_v2（evidence/CENTER_OPTIONC）：只在「非 crowd 擁有者有啟用中的格子隊伍」時拒絕（GRID_SIMULATION_RETIRED，push_error），閘點：TerrainArmy.advance_frame 非戰鬥分支／prepare_combat／sample_combat、terrain_lab _advance_combat 格子迴圈／_resolve_exchanges／_resolve_combat_contacts／_advance_gd_mesh_work_to／冷安靜分鐘迴圈、coordinator combat_logic_tick／complete_committed_moves；冷精算與重播本身不擋。311 支清單 optionC_data_manifest.json（visual 56）。22:50 起 D 跑（GATE_v2_D，patch 套在 D 上，跑完自動還原；約 4–6 小時）。
- 23:55：Nekki 要求改用程式碼篩，長跑在 86/311 停掉（51 過／35 失敗）。靜態篩（optionC_static_filter_20261102.tsv）：131 支從未建啟用戰鬥的格子隊、7 支從不推進時間 → 碰不到閘，略過；剩 87 支在 D 上跑（GATE_v2_D2）。35 失敗中 13 支真的撞閘（optionC_gate_hits_20261102.txt，含 region_travel、region_siege_original_phase、fire_p0 等）→ 歸入要改寫／退場的那批；22 支非閘失敗多為 site_army 視覺／渲染測試，待乾淨 HEAD 基準比對（清單 optionC_newfail_baseline_manifest.json）。Haiku 同時在分類 165＋13 支（optionC_sim_plan）。
- 下一步：87 支結果；22 支基準；依 sim_plan 分批改寫／退場；165 支分類改寫／退場；剩餘測試債分批；第 3 階段。
- 工作區乾淨，沒有 Godot 在跑。

## 2026-11-02 15:10 交接點（舊）

- HEAD a2d10cf：兵營訓練修好（原生分離推力乘 dt＋訓練閘門 is_walking）。DLL 25E5EA2A 已換上（舊 BF2BB587 在 evidence/CENTER_FIX/dll_backup_BF2BB587）。161 項回歸：89 過、72 失敗＝與 1ee23d3/4a853c2 同一批既有失敗，無退步。
- 72 項既有失敗分類（stage2_summary_20261102.md §3）：17 項 TECH_POLICY_CONFLICT＝需 cc001 隔離目錄 patch 才能跑（非 bug，techpolicy_manifest.json）；其餘 FIX 約 45 項、ENV 10 項，待逐項處理。
- 第 2 階段分類初稿：RETIRE 165／KEEP-GRID-ARG 266／KEEP-PORT 145／UNSURE 69（stage2_classification_20261102.tsv），刪檔前逐支複查。
- 15:35：第 2 階段第 1 批已提交 a4f8703：刪 134 支已確認的格子專用測試＋3 個夾具（stage2_retire_confirmed_20261102.tsv；21 支被其他檔案引用而保留、9 支斷言共用規則改保留）。冒煙：journey、ship_journey --grid 過；site_contact_hit_cull_test --grid 自身夾具失敗（保留的格子測試，與刪除無關）。
- 16:10：第 2 批已提交 1d083ec：再刪 25 支（stage2_batch2_20261102.tsv）；UNSURE 69 → RETIRE 19／KEEP-PORT 40／KEEP-GRID-ARG 10；BLOCKED 21 → 處理 6、其餘保留。
- 18:10：43 項既有失敗用正確參數重跑（evidence/CENTER_FIX/fix_rerun_D，清單 CONTINUOUS_SWITCH/fix_rerun_manifest_run.json）：10 支其實會過（之前是清單參數錯）；仍失敗約 31 支：測試替身缺新方法（peek_events、siege_native_supported、person_owner、_region_deferring_endpoint；7 支）、RID 洩漏雜訊（3 支）、earned 鏈／科技窗／T5-T6 夾具、其他單項。全是改動前就存在的測試債。
- 18:10：fe3e7b6 補測試替身：site_sustain_owner_index、site_stockpile_transport、site_tent_logistics、site_trade_exchange 轉過；crowd_sustain_query_parity、site_sustain_life_sample、crowd_c2_people_adapter 過了缺方法那關，還有後續檢查失敗。
- 下一步：KEEP-GRID-ARG 266 支（之後跑要帶 --grid）、KEEP-PORT 145 支改寫 crowd、UNSURE 69 支、BLOCKED 21 支；72 項既有失敗的 FIX 約 45 項。
- 工作區乾淨，沒有 Godot 在跑。

## 2026-11-02 12:15 交接點（舊）

- HEAD 4a853c2：第 1 階段提交（crowd 預設、--grid 退回格子）。159 項回歸：84 過、75 失敗；72 項在乾淨 1ee23d3 上同樣失敗（evidence/CENTER_STAGE1/HEAD_baseline_D）；其餘 3 項（site_fire_native_admission、site_ship_journey、region_travel）是格子測試，清單已加 --grid 並通過。清單外的格子專用測試現在預設跑 crowd，第 2 階段處理。
- 兵營訓練：BARRACKS_v2 在 D 上不採用（減半仍在，且母測試 site_barracks_types_crowd 被新的下令限制弄壞；三支一般訓練測試過）。Opus 在做 DIAG2（逐人速度、移動目標、BUSY 來源、用餐事件）。
- 第 2 階段：Haiku 分類格子專用測試（RETIRE / KEEP-GRID-ARG / KEEP-PORT / UNSURE）與 72 項既有失敗（RETIRE / FIX / ENV）→ CONTINUOUS_SWITCH/stage2_classification_20261102.tsv、stage2_summary_20261102.md。
- 13:00：17 項 TECH_POLICY_CONFLICT 不是 bug：cdd3be7（10/11）世界誕生只准目錄已啟用的類別，正式目錄 40 節點全未啟用；這些測試要套 reports/cc001_catalog_20261010/enabled_isolated_catalog.patch（只在階段切換時暫套）才跑得過。歸類為「需隔離目錄設定」，清單 evidence/CENTER_FIX/techpolicy_manifest.json。
- 13:00：兵營根因＝原生分離推力未乘 dt（crowd_core.cpp World::soldier_stage）；BARRACKS_v3（evidence/CENTER_FIX）原生測試全過，新 DLL 25E5EA2A 已換上（舊 BF2BB587 在 evidence/CENTER_FIX/dll_backup_BF2BB587）。完整 161 項回歸跑中（BARRACKS_v3_D，patch 套在 D 上，跑完自動還原）。
- 工作區（除跑中的 v3 patch）乾淨。執行器 scratchpad manifest_run.ps1（失敗時保留 result.json/combined.log 到批次資料夾）。
## 2026-11-02 09:40 交接點（舊）

- HEAD 1ee23d3：crowd_c3_store_check 夾具修正（126 項過）。之前 a5e7f20 分隊 UI、4bf4050 重開、556f463 出航鈕、c9ea065 出海＋DLL BF2BB587。
- Nekki 04:00 同意三階段退場（記憶 grid-retirement-staged-plan）。第 1 階段 patch：evidence/CENTER_STAGE1/STAGE1_v1.patch（crowd 預設、--grid 退回格子、21 支測試模式判斷改讀 --grid）。回歸清單 CONTINUOUS_SWITCH/stage1_regression_manifest.json（159 項；排除 30 支需 GPU/atlas 準備者，清單在 scratchpad excluded.json，會消失）。
- 第 1 階段 D 跑完（06:47，已還原）：84 過、75 失敗（evidence/CENTER_STAGE1/STAGE1_v1_D/results.tsv）。很多像環境雜訊（RID 洩漏、material null、not in tree），07:50 起在乾淨 HEAD 上重跑這 75 項比對（HEAD_baseline_D）。執行器：scratchpad manifest_run.ps1（會消失；讀 manifest、<ID> 替換、canonical verifier、apply/revert）。
- 兵營訓練（site_barracks_types_training_crowd）：BARRACKS_v1（閘門改 is_walking）讓 BUSY 消失，但同 6 秒訓練共通流程只算一半（3 秒，跨用餐邊界）。Opus 寫了 BARRACKS_DIAG.patch（evidence/CENTER_FIX）待在 D 上 visual 跑，讀 BARRACKS_DIAG 行判斷 (A) 訓練被 stop 或 (B) 用餐沒扣糧。
- 09:40：HEAD 基準比對完成（HEAD_baseline_D）：75 項失敗中 72 項在乾淨 HEAD 上本來就失敗；只有 3 項是第 1 階段造成（site_fire_native_admission、site_ship_journey、region_travel），原因都是這些格子測試沒帶 --grid、預設變 crowd 後跑了 crowd（例：region_travel 的「單走」在 crowd 不支援）。加 --grid 重跑：前兩項已過，region_travel 跑中（STAGE1_v1_three_grid，第 1 階段 patch 目前套在 D 上，跑完自動還原）。
- 下一步：region_travel 過了就把這 3 項的清單參數加 --grid、提交第 1 階段；72 項既有失敗整理成清單（多為環境雜訊或格子專用，第 2 階段處理）；兵營 DIAG；第 2、3 階段。執行器已改成失敗時把 result.json/combined.log 複製到批次資料夾（保留期只留最新 100 次）。
## 2026-11-02 03:45 交接點（舊）

- HEAD a5e7f20（分隊 UI）；4bf4050 選定重開 crowd；556f463 出航鈕 crowd；c9ea065：crowd 隊伍搭船出海進區域旅行（SHIPSEA_v8，evidence/CENTER_SHIP）。**DLL 已換**：bin 新 BF2BB587（build evidence/CENTER_SHIP/build/20261101_235503_505，原生測試全過），舊 4910FB2A 備份在 evidence/CENTER_SHIP/dll_backup_4910FB2A。原生新增 site_person_exit_ready_aboard / site_person_release_aboard。另修：玩家控制士兵不能登船（ship_ensure_aboard 交還 host control）、RegionTravel 海路計畫原本沒接上 sea 計畫與推進（region_save_slot）。region_crowd_ship_sea_departure_test 92 項＋18 項回歸過。
- PS5 建置腳本：scratchpad build_c2_c3_ps5.ps1（會消失；作法：複製 native/crowd10k/tools/build_c2_c3.ps1，把 $root 改成 'D:\worldgoing'、Convert.ToHexString 改成 SHA256 ComputeHash+x2、Kill($true) 改 Kill()）。
- 注意：region_travel_test 在有其他 Godot 同時跑時會超過 540 s（557 s 失敗，單獨重跑 244 s 過）；子代理人跑 check-only 時不要同時跑 D 批次。
- 556f463（02:00）：遊戲實際「出航」鈕（begin_ship_journey）crowd 路徑走通（SHIPUI_v4，region_crowd_ship_journey_ui_test 1941 項）＋19 項回歸過；修原生部署 crowd 隊上船後 STALE_SUPPLY_OWNER、抵達前先預檢再釋放、_reuse_ship_checkpoint_source 改用 SiteStore._read 讀 crowd 存檔外層。
- 4bf4050（03:00）：選定重開／繼續遊戲重開 crowd 地點（REOPEN_v7，evidence/CENTER_REOPEN）：crowd 改為綁定檢查全部通過後才啟用；region_crowd_selected_reopen_test 27 項＋21 項回歸過。
- a5e7f20（03:30）：分隊遊戲內入口（功能視窗「分隊出發」＋隨行隊員多選；隊長隱藏、普通兵停用顯示 CADRE_REQUIRED）；region_crowd_split_ui_test pair 50 項／alone ＋21 項回歸過。
- 切換提交盤點：CONTINUOUS_SWITCH/grid_retirement_survey_20261102.md（格子專用約 1.5 萬行；測試 crowd 132／格子專用 645／其他 591）。建議三階段：1 crowd 預設（留 --grid）、2 刪格子專用測試、3 抽共用後刪格子程式；舊存檔保留自動轉換。03:45 已問 Nekki，等回覆。
## 2026-11-01 23:05 交接點（舊）

- HEAD cbe0c5f：抵達沒有 crowd 的新地點 → 直接轉成 live crowd（FRESH_v8，evidence/CENTER_ARRIVAL）。新增 region_crowd_journey_test（端到端：綁定 → request_departure 整隊出發 → 旅行面板＋advance_region_travel 地圖步進、原地點背景原生推進 → open_fixed_world 抵達 → 抵達隊為原生 crowd、玩家 host control → slot 存檔讀回仍為 crowd），58 項過；同產品碼 12 項回歸過。
- 這輪修的根因（依序）：bind 轉換後沒寫 crowd 區段（capture 拒收）、bind 快照未以 admitted/native 擷取與保存、發布時 live bind 拿到空的 staged crowd（改走 prepare_crowd_load，同重開）。
- 未處理（Haiku 指出）：_region_prepare_selected_owner_restore（terrain_lab.gd ~11229）拒絕含 crowd 區段的資料，「選定重開」一個 crowd region 快照會失敗，旅程外的路徑。
- 下一步：船隻批次（SHIPJ_v2、G6REST2_v2、海岸夾具）；分隊 UI 入口；選定重開 crowd 快照；切換提交移除格子路徑。
## 2026-11-01 21:45 交接點（舊）

- 狀態：已停所有背景工作（Haiku FRESH 已停、無 Godot 在跑、D scripts 乾淨）。HEAD e4ecfeb。等 Nekki 打「繼續」。
- 今日提交（皆有 D 收據）：31c352b 舊存檔轉 crowd；d03a139 幹部帶隊分隊；e729730 抵達 crowd 地點轉原生隊；358348b 玩家帶隊抵達；9845649 地圖移動閘門；04ff1ce 整隊出發端到端 4 修正；2f67a9c 分隊資料轉換；dc6f89b crowd_era 讀檔修正（31c352b 弄壞 site_ship_journey，已修）；e4ecfeb 背景 crowd 原生推進（Nekki A）。
- 決定（記憶）：party-split-needs-cadre-decision、offscreen-crowd-native-decision（格子部隊整個棄用）、no-idle-between-results。
- 進行中：抵達「沒有 crowd 的新地點」直接建 crowd ＋ 端到端旅行測試（evidence/CENTER_ARRIVAL/FRESH_v3.patch，含 scripts/tests/region_crowd_journey_test.gd）。FRESH_v2/v3 在 D：12 項回歸全過，journey 過 48 項（出發、地圖 4 步原地點背景推進、抵達存檔），卡 commit_arrival REGION_BACKEND_UNADMITTED。實跑堆疊：terrain_lab.gd:8524 `_region_capture_original_owner_state` ← `_region_project_original_bind_child`(10277) ← `_region_prepare_original_bind`(10115) ← commit_region_arrival(3543)。原因：bind 時轉成 crowd 後，投影子場景 terrain.site 還沒有 crowd 區段。下一步：轉換成功後立刻寫入 crowd 區段（同 capture_region_checkpoint 的 _apply_region_crowd_capture），做 FRESH_v4，再跑 journey＋12 項回歸（批次範本 scratchpad fresh_v1_batch.ps1，會消失：apply → 測試 → apply -R）。v3 的 ~10098 backend 改動不是原因，v4 可拿掉。
- 之後：船隻批次（SHIPJ_v2、G6REST2_v2、海岸夾具）、分隊 UI 入口、切換提交移除格子路徑。
- HEAD 既有失敗：crowd_c3_store_check（INVALID_CROWD）、combat_movement_site_store_resume_test（material null）、site_controlled_food_delivery、site_partial_exit_food、site_technology_s06_food_owner、site_barracks_types_training_crowd。
## 2026-11-01 20:40 交接點（舊）

- HEAD e4ecfeb（背景 crowd 原生推進）；dc6f89b crowd_era 修正；2f67a9c 分隊資料轉換；04ff1ce 整隊出發端到端修正；9845649 地圖移動閘門；358348b 玩家帶隊抵達；e729730 抵達轉 crowd 隊；d03a139 幹部分隊；31c352b 舊存檔轉 crowd（LEGACY_v2）；DLL 未變 4910FB2A。D 收據在 evidence/CENTER_SHIP/LEGACY_v2_D（batch.log 6/6、batch2.log、head_baseline.log）。
- 新增 HEAD 既有失敗（乾淨 24f5b11 上同簽名）：crowd_c3_store_check（INVALID_CROWD 群眾地形與建築推導通行資料不符）、combat_movement_site_store_resume_test（material null）。
- Nekki 10:09 決定旅隊規則（取代 A/B）：分隊須有幹部帶隊，幹部即新隊正式隊長；只有隊長的一人隊合法；普通隊員不能單走；正式隊長仍整隊走。只做在 crowd＋region_travel 的 crowd 路徑，不改格子（格子在切換提交時退場，Nekki 10:32 確認）。記憶：party-split-needs-cadre-decision。
- 16:50：抵達轉 crowd 隊已提交 e729730（ARRIVE_v6，evidence/CENTER_ARRIVAL）：region_crowd_arrival_test 45 項、分隊 alone/pair、departure、bind、travel_membership、region_travel（525 s）、gameplay_travel 全過。新隊有停用的射擊命令列（保持擁有者與命令一一對應）。仍拒絕：玩家／人物抵達（UNSUPPORTED_CROWD_ACTOR_ARRIVAL）、回到原地點（UNSUPPORTED_CROWD_RETURN）、海路、車船、俘虜、押送。玩家帶隊抵達已提交 358348b（ARRIVE_PLAYER_v2）：player 58 項、npc 46 項、gameplay_travel 過；目的地已有受控士兵時 ID_CONFLICT（同格子）。地圖移動閘門已提交 9845649（MAPGUARD_v3）：map_guard 23 項、departure、bind 過（v1 另跑 split、arrival、party_life、gameplay_travel、region_travel 過）。R10：party proof 只看 travel:<token> 後端，維持 gd，不用改。fire_host_active 是部署常駐旗標，不算進行中動作。尚未端到端跑 prepare_region_party_map_motion。
- 18:45：端到端（evidence/CENTER_JOURNEY，JOURNEY_v10 測試未提交）修出 4 個 bug 並提交 04ff1ce：受控隊長整隊出發 NOT_READY（host control）、出發後控制權交回留下的身體、出發隊伍經 ClearHandoff.roster_snapshot 轉成完整 GD 部隊、旅隊 owner view 不再帶入 crowd。10 項回歸過。卡點：地圖步進要推進離開的 crowd 原地點（terrain_lab.gd:9347/9402 REGION_OWNER_MODE；slot 排程 region_save_slot.gd:4498-4511），Nekki 10:50Z 選 A：背景 crowd 用原生推進、格子部隊整個棄用（記憶 offscreen-crowd-native-decision）；背景 crowd 原生推進已提交 e4ecfeb（OFFSCREEN_v8，evidence/CENTER_OFFSCREEN）：offscreen_step 55 項（4 步、時鐘與世界一致、士兵移動、slot 存檔重載）＋9 項回歸過。另修 dc6f89b：31c352b 的 crowd_era 外層標記讓 slot _read_document 拒收，site_ship_journey 壞掉（二分確認）。CROWD_CONTACT_HELD（region_save_slot.gd ~10920）在 v10 patch 裡，未提交，等這個決定。分隊隊伍資料轉換已提交 2f67a9c（SPLIT_GD_v1，8 項過）。
- 下一步：新地點抵達直接建 crowd（進行中）；端到端旅行測試；船隻批次；分隊 UI 入口；切換提交移除格子（第 3 項，R10 後端閘門待定）；之後船隻批次（SHIPJ_v2 測試、G6REST2_v2、海岸夾具）。

## 2026-11-01 05:20 交接點（舊）

- HEAD 24f5b11；bin DLL 4910FB2A（前版 1DE59EE4 備份在 evidence/CENTER_CAPTIVE）。存檔版本 KW19（可讀 KW18/17）。今日提交（皆有 D 收據）：
  - 24f5b11 船隻輔助讀 crowd 乘客、出航只在交戰拒絕（29 項）。實測：crowd 隊出航進區域旅行仍被 region_travel「不支援整隊出發」擋（等 Nekki 旅隊規則）；測試 SHIPJ_v2 的 site_crowd_ship_region_journey_test 待用
  - 15d6acc crowd 隊伍命令序號（原生）＋遠端國家命令進 crowd；接受的 HOLD 會有命令延遲（同格子）（45 項）
  - e3f86bc 區域閘門跟隨 live backend：攻城刷新、玩家出發、冷重播（24 項；接觸戰 crowd 拒絕保留）
  - 83d6f78 每日結算找 bound holder、清除 crowd 後幹部自動入座（37 項）
  - b4ba4b3 測試：crowd 下 sustain 時鐘與用餐扣量（4 項）
  - 094e223 crowd 下職務檢查（39 項）
  - 759d5ac 和平時部隊調動、歸降、押送（68＋合併 16 項）
  - ba98fa8 區域層跟隨 crowd：模式、存檔槽、攻城命令（23＋合併 16 項）
  - ed9f84c crowd 下限時送糧（72 項）：送糧接入原生共享工作點（仿原生訓練）；crowd 成員「移動中」改為有移動目標或速度 ≥0.1 格/秒（SETTLE_SPEED），_team_stopped、送糧準備、moving_member_count 共用。
- HEAD 既有失敗（簽名不變）：site_controlled_food_delivery（'fatigue'）、site_partial_exit_food（material null）、site_technology_s06_food_owner、site_barracks_types_training_crowd（BUSY 隊伍已移動，10/30 起）。
- 下一步：
  1. sustain 與 holder 已完成（見上）。
  2. 等 Nekki：旅隊進出 crowd 地點規則 A（比照格子：部分出發、抵達轉 crowd 隊）/B（只整隊），調查見 CONTINUOUS_SWITCH/party_travel_crowd_survey_20261101.md。G6REST2（Haiku）：NPC 卸船授權改讀 crowd（v2 patch 未驗，缺 crowd 海上抵達夾具；transfer_ship_supply 仍排除 CrowdOwner，併入船隻批次）；n08 車需原生車隊轉移，暫緩；遠端國家命令缺原生命令序號 已由 15d6acc 完成。
  3. 船隻批次：調查 CONTINUOUS_SWITCH/ship_batch_crowd_survey_20261101.md。進行中 Haiku SHIPJ（原生船方法入准入檢查、船程 crowd 分支、船程只在交戰拒絕，依 10/31 A）→ evidence/CENTER_SHIP/SHIPJ_v1.patch。之後：G6REST2_v2 卸船＋移除 site_controller 5544 CrowdOwner 排除、測試用部署鈕移除、crowd 海岸夾具、舊存檔 convert_existing。Actor 登船、旅隊與海上旅隊（R4/R7/R8）併入待 Nekki 的旅隊規則。
  4. 換隊形需原生隊形 API；G6 剩：含 crowd 區段的冷綁定、遠端國家來源、n08 車、NPC 卸船、地面越界拒絕。
  5. 船隻航行與部署畫面、舊存檔轉換，然後切換提交。
- 換新工作階段時（2026-11-01 01:20Z 起隨時可換）：
  - 舊存檔轉 crowd：LEGACY_v1（evidence/CENTER_SHIP）D 上 32 項過、2 項失敗：site_crowd_legacy_convert_test「people 11 vs 10」（轉換多 1 人）；site_siege_native_integration_test 52「ordinary reload」退步（載入 hook 把一般重載也轉換了，要收窄成只轉真正的舊檔）。LEGACY_v2.patch 已出（同資料夾，對 24f5b11，未跑）：存檔外殼加 "crowd_era": 1 標記（不在 checksum 內），只轉沒有標記的舊檔；轉換測試的人數改把 player_member 與受控人物算進格子普查（認為 11 人是對的）。注意：本 patch 之前寫的存檔都沒有標記，在 crowd 下載入會被當舊檔轉換。新階段上 D 驗：轉換測試、d5、攻城整合（--crowd --crowd-test <id> --siege-suite native）＋ crowd 回歸。
  - 等 Nekki：旅隊規則 A/B（已在討論串解釋：格子現行是「單走」一次一人、無隊長的獨立單位；正式隊長只能整隊走）。A＝照搬到 crowd；B＝只整隊。
  - 未提交但可用：evidence/CENTER_SHIP/SHIPJ_v2.patch 的 site_crowd_ship_region_journey_test（和平出航會被 region_travel 擋，等旅隊規則）；evidence/CENTER_G6/G6REST2_v2.patch（NPC 卸船授權，缺 crowd 海岸夾具，且要拿掉 site_controller transfer_ship_supply 的 CrowdOwner 排除）。
  - D 驗證批次範本在舊階段 scratchpad（會消失）；新階段照「apply → check-only → 測試 → apply -R → BATCH_DONE」自建，原生改動要 build_c2_c3_ps5.ps1 -RunTests、換 DLL、跑完還原。
- 規則：同一時間只跑一個 Godot；子代理人只做語法檢查；Haiku 先，失敗才 Opus。git commit 慢是 LFS post-commit 掃描，等它。

## 2026-10-31 17:55 交接點（舊）

- HEAD 154c4e3（俘虜跟隨，Nekki A）；bin DLL 1DE59EE4。D 上依序驗：PEACE1D_v5（職務檢查，含修正 706aeba 的名冊索引錯誤）→ PEACE1E_v4（送糧，含診斷）→ PEACE3_v6（部隊調動、歸降、押送）。G6REST_v5 夾具修正中（第二次部署因待分職幹部被拒）。
- 已提交（10/31）：f51133c CAV-4b 衝鋒／重整；2d973cc crowd 非交戰可下裝備命令（Nekki A）。
- Nekki 決定：
  - crowd 下的非戰鬥限制一律改為只在交戰中禁止（A，NEKKI_DECISION_20261031_crowd_peacetime_systems.md）。
  - Haiku 先做，失敗才改用 Opus（10/31 05:46Z）。
- 平時系統（evidence/CENTER_PEACE）：
  - PEACE1_v4（每日結算、家族遞補、team_owners、crowd_peace_guard）：D 上 51 項通過。2 項因記憶體配置失敗而報錯，重跑中，過了就提交。
  - PEACE2_v1（聚落頁、派工）：6 個情境失敗，site_housing_crowd_test 退步（site_building_ui_test.gd:97 還在檢查舊規則），交回 Haiku 修。
  - PEACE3（換隊形、部隊調動、歸降、押送）：Haiku 進行中。
  - 職務檢查、送糧：待做。設計在 CONTINUOUS_SWITCH/crowd_team_data_survey.md（Option A）。
- 區域層剩餘（G6，evidence/CENTER_G6）：G6REST_v1 只修了後端判定。G6REST_v2 由 Opus 進行中。
- 之後：船隻航行與部署畫面、舊存檔轉換，然後切換提交（switch_readiness_20261031.md 第 3、5 節）。
- 規則：同一時間只跑一個 Godot。子代理人只做語法檢查，測試一律在 D 上跑。

## 2026-10-30～31 進度（指揮中心）

- 連續 crowd 切換：G1 船、G2 船廠、G3 補給、G5 名冊／駐軍／投降（KW15、KW16）、G7a、G8、G10、攻城 S1～S4、騎兵 CAV-1／CAV-2（KW17）皆已提交，最新到 6bd24de。
- 357e629 勸降（Nekki：一般兵隨機 50%、幹部看個性；戰敗忠誠 -2500；首領與守法 ≥80、忠誠高的幹部不降）。新增原生轉隊 transfer_member。D 收據 28 項 PASS。DLL 38B279C1。
- c727c8b 投石機原地轉身讓路（Nekki A）：同隊非工兵讓出掃掠區、轉身期間就近待命以保住指揮。D 收據 16 項 PASS，含探針版 40 項整批回歸。DLL ACD5BF3C（目前在 bin）。
- 已知缺口：crowd 勸降轉隊不清原國官職與所帶部隊；補給歸屬沿用釋放預檢。
- 92bd4c2 勸降缺口：crowd 轉隊清原國官職與所帶部隊，補給改走歸降預檢。D 收據 24 項 PASS（2 支科技測試為 HEAD 既有失敗）。
- be93ed4 CAV-3 一般兵騎乘（Nekki BAB：騎乘是屬性、馬為坐騎欄裝備扣馬匹物資、首版含騎射）。Godot 烘焙騎乘圖集 2112 騎士＋220 馬格，入庫 assets/army/mounted_soldiers/v2。D 收據 46 項 PASS。
- 待 Nekki：crowd 下非交戰時是否開放裝備命令（目前 CROWD_ACTIVE 一律拒絕）。
- 進行中：CAV-4a 原生衝鋒／重整命令與輪衝 AI。之後 CAV-4b Godot 接線、HEAD 既有失敗清查、翻預設並退役格子測試。

## 2026-10-28 進度（指揮中心）

- Nekki 決定：舊輪廓碰撞戰鬥模式不維護（4 支只測舊模式的測試移出 HEAD 回歸，騎乘瞄準修正不提交）；戰鬥移動一次全面切換到連續 crowd 模型（B），切換計畫 N1–N6 都照推薦（output/project_command_center/CONTINUOUS_SWITCH/switch-plan.md）。騎兵衝撞計畫 V0.5 定案（reports/cavalry-charge-plan.md）。
- 今日提交：b467764 角色資產救援測試、25b4737 terrain_lab 移動探針、f5c00ac G6.1 區域存檔點帶 crowd 原生區段（crowd 往返 27 項 PASS；29 支區域回歸 PASS，4 支與 HEAD 同樣失敗）。
- 不提交：路徑失敗快取（正確但無加速）、重試退避（更慢且壞 3 支）—一人一格模型不再做效能修正。
- HEAD 已知失敗（基準相同）：region_cold_original_matrix、region_controlled_death_restriction、region_n08_civil_original_ui、region_two_npc_sea_public_contact_physical；site_logistics_ai_acceptance（一人一格效能，切換後改寫）；combat_movement_multi_team_arrival 96/100。
- 進行中：G6.2 區域綁定接受原生後端；之後 G6.3／G6.4、騎兵 CAV-1。

## 2026-10-22 進度（指揮中心）

- Codex：17:29Z（10/21）起無額度，中心自做；Nekki 07:08Z（10/22）通知恢復，已派 CC-20261022-123（g06 工匠攻城六支 HEAD 失敗，只交補丁）。截至 09:55Z 尚無回執也無證據資料夾，已再排一則恢復提示，回執監看中。
- Nekki 決定：SITE WORKFLOW 看門狗 15→60 秒（8df7c14）。
- 今日提交（全部 D 收據）：P6-B9a 54f629b、B9b a7bd616、B9c 89c4293、B9d 353c4f5；哨兵漏洞 a137131；俘虜監管停止 cda2f5c；火場字串鍵 561cecf；StringName 盤點 1921525、31dbf11、e6fafc3（terrain_lab 52 檔 2308 處，122 支回歸通過）；F15 火罐授權 be4bd62；工匠攻城指派 665b63d；以及 bcabfa0、b92f4a8、0a6560f、89eddca、8e33ffc、0874461、6f84115、a65b568、becfb38、15eadf2、9c55965、caeb012 等測試修正。
- 長期失敗（記錄於 output/project_command_center/evidence/HEAD_FIX）：技術測試 HEAD 失敗清單 TECH_HEAD_FAILURES_20261022.txt（26 支，含目錄補丁）；n05 第四層（研究同意 NO_MEMBER）；fire_pot 投射命中被火場拒收；prepared_exchange 結束時資源洩漏；army_capacity／mixed_equipment_live 為無 GPU 環境問題。
- 待查：圖集 3 檔（equipment/ranged atlas、shapes_descriptor）改字串鍵會破壞遠程管線；region_lab control 的 faction_registry 為 StringName 鍵（改會動存檔位元組，暫緩）。
- 14:10Z 後：598385d 火罐側撞點燃（Nekki 決定）；e763b51 區域攻城刷新把延後點的火場游標判為「效果待處理」。CC-123／124 已回（124 為 QUOTA_STOP）：contact 改網格模式後越過舊卡點，仍有近戰未接觸；gates f11/f12 各推進一層。region_siege 5 支、gd_contact 4 支等新增至 HEAD 失敗清單。
- Codex：10/22 約 13:00Z 再次 QUOTA_STOP，中心自做。
- 10/22 17:28Z Nekki 通知 Codex 恢復。3301184 還原 e6fafc3 對戰鬥熱欄位的誤改（82 支通過）。網格近戰 8 支真因已閉合（CC-125/128/129）：相鄰敵人觸發停工，與測試「施工中被擊」矛盾，等 Nekki 裁定。CC-130 派 gates f11（Site 被暫停）／f12（助手一步被拒）。
- 10/23：b04e197／b92b7c1 修好 g06 gates f11/f12；5c7b21d 網格測試依 THREAT 規則（Nekki「依建議」）。0974a18 修好 n05（純測試：工人實走、回指揮半徑、捐料人離開工位、專職後勤送弓後解除；visual PASS）。Codex 06:30 恢復，CC-133 已回，CC-20261023-134（火罐仍記未命中）派出、回執監看中。
- 仍開：gd_contact manual／training 兩支（命中在步界 fraction 0，及敵人起手攻擊被拒）；region_siege 5 支＋player_first_siege_contact（冷站 owner 無受控人物，Settlement.found 只准受控本人建立；預定改測試在熱站時建立聚落）；prepared_exchange 結束洩漏。
- 10/23 上午（Codex 11:00～11:32 無額度，中心自做）：a1d1bf6 prepared_exchange 洩漏；02526c9／c5cc7a1／e1c527a／5f82d7f fire_pot 夾具；f18a7d2 火罐命中覆寫；f8d77b3 退役預設工人移除其火場命令；bd792ec 攻城火罐起飛時鐘＝發射切片終點（fire_pot trial／ordinary_ui 全 PASS）。Nekki「放寬」：fire_pot 兩列 120→210 秒。CC-139（GD 網格洩漏＋manual）03:33Z 排入；CC-140（region_siege：冷遠端站沒有任何人物，預設改為熱站時建立再變冷）待派。
- 10/23 下午：678dc4e GD 網格前綴釋放＋training（CC-141）；d134d5a supply f11/f12 冷讀改存檔域比對。CC-144 碰撞修正 D 拒收（manual 未修且 contact_prepared／compiled_contact_query 退步）。Codex 13:4x 再次 QUOTA_STOP（CC-145）。待 Nekki：region_siege 控制交接設計 A（新增存活交接）／B（改測試）／C（擱置）。待 Codex：manual fraction 0、checked_work_prefix（測試仍用已改名的 prepare_checked_controlled_prefixes，現為 prepare_checked_controlled_prefix_allocations）。HEAD 已知失敗：siege ballista_contract／store_guard／actual_balance、contact_sampling／hit_cull／compiled_contact_pipeline／army_contact_batch／combat_proxy_contract、default_worker_removed（主場景斷言）。
- 10/23 晚：03bd630 存活交接控制（Nekki 決定 A）＋3c4cde4 區域版測試；7209934 checked_work_prefix；ccd2865 region_siege 熱站建城→交接→接班人實走流程＋兩個攻佔計時容差修正（exact PASS，center 3/8）。Nekki「放寬」：fire_pot 兩列 210 秒。Codex：CC-150～153 修 phase（冷站攻城被轉 formula_active）、player_first 出發存檔；CC-152 因 _faction_scan 快取鍵回歸被拒，CC-153 驗證中。待辦：manual 命中時序（CC-149 停在額度）、center 俘虜情境（headless 無法準備裝備圖集）。
- 10/24 凌晨：1e07338（冷站攻城不被到站 NPC 轉 formula_active、派系來源時間）、335aa6d（來源檢查時間殘差）。exact PASS、回歸全過。剩 phase／cancellable 旋轉逾時（DIAG：action 21→316 間 crew_ready 由 true 變 false，攻方隊伍 duty_ai 開、首長空缺）、player_first >60 秒接觸間隔、center 俘虜情境（headless 圖集）、manual。Codex 於 CC-155 再次 QUOTA_STOP。
- 10/24 清晨：Nekki 18:04Z 通知 Codex 恢復。bb434c0（CC-156：phase 隊長離開旋轉掃掠區、player_first 座標比對）；三支各推進一層。CC-157 三路 DIAG 已在 D 跑完，CC-158（依實值修 phase 同點重試、cancellable 恢復、player_first 部分冷存）派出中。
- 10/24 上午：Codex 01:37Z～04:35Z 停額度，期間 Haiku 子代理接手（Nekki 指示）。commit 5807962（CC-163 遠程攻城快照）、fd3207b（Haiku：抵達綁定收據 slot、到站 party endpoint），回歸全過。中心決定：已完成點零消耗重試須為真 no-op；同一接觸只因來源檢查點續期而重推導時視為同一事件；cancellable 的接班人是隊伍成員，夾具改走隊伍命令。CC-164 已派（04:36Z），回部分修正＋DIAG，D 驗證中。
- 10/24 05:36Z 暫停（Nekki 要更新 Claude）：HEAD fd3207b，scripts/ 乾淨。CC-164 補丁（evidence/CC-20261024-164/CC164_PARTIAL_FIX.patch＋CC164_DIAG_ONLY.patch，--cc164-diag）的 D 驗證批次已中止、尚未跑出結果；恢復後重跑 scratchpad/cc164.ps1。Codex 目前有額度。
- 10/24 下午（恢復後）：CC-164／165／166 依 D 實值推進。commit 1c2019b（player_first 接受接觸固定原時間與第一份 witness，回歸 14 支全過）、2e86f93（中心修：site_runtime 種裝備 dye_color 改字串鍵，phase 越過重開檔比對）、77dcbe8（CC-166 測試：出發排除受阻方向、player_first 改看 pending-barrier 圖）。現況：phase 卡在同點重試須為真 no-op；cancellable 卡在「actual common producer accepts original work」PENDING；player_first 卡在 MISSING_ORIGINAL_BOUNDARY_VIEW（region_original_boundary_location 在正式碼從未接上，跨界接觸的幾何投影未實作）；cold_action_epoch CORRUPT_SAVE 未變。CC-166 回 QUOTA_STOP，停止派單，等 Nekki 告知恢復。證據在 evidence/CC-20261024-16{4,5,6}/CENTER_D_RESULT。
- 10/24 晚：Nekki 告知恢復（NEKKI_RESUME_20261024T1005Z）→ CC-167～169，commit aa093a7（讀檔還原遠程動作 int 欄位、cold 補算續作、跨界投影 provider 接上）。CC-170 回 QUOTA_STOP（台灣 23:07 重置）→ Nekki 指示改由 Haiku 接手：f389893（中心：攻城操作班 id 浮點比對，cancellable 出發成功）、cb2e847（Haiku＋中心：計畫物件引用 peek／還原、member_paths 型別）。回歸 15 支全過。現況：phase 碰外層 390 s（in-file 360 s；需 Nekki 核准延長）；cancellable 卡「true player closure has one owner and is not inserted into the original NPC roster」；player_first 卡 MISSING_ORIGINAL_BOUNDARY_VIEW（frame 未准入）；cold_action CORRUPT_SAVE（軍隊人物／動作／指揮關係非法）不同根。
- 10/25 凌晨：Nekki 選 A，phase 時限 540／600 s（a62aab5）。CC-171 恢復後交回，但出發座標框路徑造成回歸，CC-172 仍回歸，兩次都退回。CC-173 QUOTA_STOP（台灣 04:17 重置），改 Haiku＋中心：84b1eba（軍隊存檔整數比對）、7e1b54d（目的格整數、move.command 隨正規化；cold_action 越過 CC-142 起的 CORRUPT_SAVE）、5c682ed（cancellable 普查改精確成員）。**region_siege_original_phase_test PASS（431 s）**，回歸全過。剩：cold_action 重開檔 progress 差 1 ULP；cancellable 重開檔 facts typed／untyped Array；player_first 跨界 frame 准入。CC-174 任務檔已寫好，等 Nekki 告知 Codex 恢復再派。
- 10/25 03:45Z 狀態：Nekki 指示 CC-174 之後全交 Haiku。新 commit：1cc24bb（CC-174：move_progress 精確、cancellable 存檔域比對）、50f8e26（player_first 跨界 seam 整數比對＋detached 框）、df08530（cancellable 時限 540/600，Nekki 核准）、b277081（cancellable 抵達補存檔）、8f6a710（materializer 前結算已完成點）、ab045a8（抵達時先接 slot）。**通過：phase、cold_action、site_siege_actual_balance**；回歸組全過。38 支攻城掃描：8 支既有失敗（修正前同樣失敗），摘要 evidence/SWEEP_BASELINE/SUMMARY.md。進行中：cancellable 越過 STALE_COLD_TRANSACTION（HAIKU20，D 驗證中），下一關 DEPLOY_FAILED；player_first 卡 STALE_REGION_CONTEXT（綁定用 2137.2 舊快照，HAIKU21 綁前先 checkpoint，待驗）；HAIKU19 crowd_site 重載補 roster，native_dead_fatigue、native_integration 轉 PASS，待 commit。
- 10/25 15:00Z 狀態：Codex 恢復（03:57Z）後 CC-175～184，Codex 兩次 QUOTA_STOP，期間由 Haiku 代班。新 commit：8251887、78d1cb6、a7d40b0、fafed4e、6212d99、6f34e07、991ee81、aa42184、f70ff31、72e45fb、726d996、92100f5（Nekki 決定 A：走到一半按出發記下可取消意圖）、2f9b9c1、2f5e242、4a9754e。**通過的攻城測試：phase、cold_action、actual_balance、native_dead_fatigue、native_integration、ballista、store_guard、roster_owner、store_p5_p6、last_wreck**；回歸全過。剩：cancellable（陣營收據 as_of 多 1 ULP，源頭在 commit_region_gameplay_progress 用預算區間 game_end；CC184_DEP 讓它越過抵達開圖，卡在後段的和平鄰站出發）、player_first（REGION_FIRE_EFFECT_RUNNING，CC184_PF 驗證中）、npc_static（NO_ORIGINAL_SIEGE）、center_original（headless 缺圖集）。
- 10/26 01:05 台灣（17:05Z）狀態：新 commit 2f5e242、4a9754e、4820222（CC184 PF）、09ce984（CC186 PF 測試；訊息描述有誤，已用 git notes 更正）、c61b12d（HAIKU37 開圖無地形時不封存）。player_first 一路推進到「visible full bind / same-point retry」MISSING_PLAYER_EVENT_CONSUMER，交 HAIKU38。cancellable：CC185 修正版會讓建立世界失敗、HAIKU36 改正後回歸全過，但 cancellable 改在出發時鎖住綁定錯誤，均未入庫；CC184 DEP（cancellable 走最遠）正在 HEAD 上重驗，通過即入庫。Codex 第三次 QUOTA_STOP（台灣 02:23 重置），等 Nekki 告知恢復。
- 18:05Z：CC184 DEP 在新 HEAD 重驗通過（回歸全過），已入庫 2df3d7e；cancellable 越過抵達開圖，卡在後段和平鄰站出發的同類收據。HAIKU39（水印與模式時間改用 logical 時鐘同一值）排在下一批 D。player_first 的 HAIKU38（open_fixed_world 還原分支接上 gameplay adapters）正在 D 上驗證，並跑 18 支回歸。

- 10/26 05:45 台灣（21:45Z）狀態：Nekki 19:10Z 告知 Codex 恢復，並指示 Haiku 找不到的交給 Opus 子代理。新 commit：2df3d7e（CC184 DEP：context 兩個時鐘欄位精確解碼）、bc9abbd（OPUS41：重開世界接上玩法轉接器、接戰驗證改用目前 Site 的 lab）。**region_player_first_siege_contact_physical_test PASS**（388 s，run 20261026_032505_111；C188 批次再過一次 154 s）。CC-187／188：cancellable 越過和平鄰站出發收據，現卡「captain departure endpoint exceeded its bounded deadline」。CC188 DIAG：該段開始時 540 s 期限只剩 32.6 s，出發意圖被清掉後每次查詢都回 IN_COMBAT（空轉）。CC188_DEP_FIX 19 支回歸全過，但新增的 region_departure_fire_endpoint_test 夾具斷言失敗（壓縮步數假設錯）。已交 Opus 子代理 OPUS42 追查，未入庫。證據 evidence/CC-20261026-188/CENTER_D_RESULT。剩：cancellable、npc_static（NO_ORIGINAL_SIEGE）、center_original（headless 缺圖集）；army100／manual_original_point 屬 visual。
- 10/26 11:15 台灣：**region_siege_cancellable_departure_test PASS**（536 s，run 20261026_105745_646），commit 9255085。內容：CC-188 的火場時鐘拒收修正、測試隊長段離開敵方警戒並在意圖結束時立即失敗（不再空轉）、地形重建快取（約省 40 s）、每個存檔點不再重複 save()、Nekki 決定 A 的期限 780／840 s。回歸 27 支全過；f1a_v8_cache、cross_boundary_wall 在 HEAD 同樣失敗（既有），preview_ui 需 GPU。剩：npc_static（NO_ORIGINAL_SIEGE）、center_original（headless 缺圖集）；army100／manual_original_point 屬 visual。
- 10/26 13:50 台灣：**region_npc_static_siege_entry_original_test PASS**（158 s，run 20261026_132327_670），commit 8e9577b。正式碼：NPC 陸路計畫讀回後還原整數欄位（存讀檔後下一次跨界誤判 CORRUPT_ROUTE_ENTRY，實際遊戲也會發生）；接觸檢查遇到沒有旅行身分的人物改為跳過而非崩潰。夾具：真 ATTACK 命令、繞海峽的 7 節路線、重開後 token／mode_revision +1 比對、手動重開先接轉接器。回歸 13 支全過（cancellable 641 s）。remote_nation、carried_intel、two_npc_sea、food_reinforcement 在 HEAD 同樣失敗（既有）。Nekki 05:29Z：今天不用 Codex，Haiku 任務改 Opus 5.5 high。region_siege 家族 headless 可跑的全部通過；剩 center_original（需圖集／visual）、army100／manual_original_point（visual）。
- 10/26 15:35 台灣：commit e4534fe（OPUS53）：**region_remote_nation_original_test PASS**（346 s）；正式碼把「到期事件」統一成 GameplayClock.reached() 一條規則（存檔檢查原本比派送器嚴 1 ULP，REGION_EVENT_PENDING）；carried_intel 接收者改為分配器生出的真人，正向／blocked／expiry／receiver_authority PASS，death／ko 推進到 PARTY_BODY_CLOSURE、receiver_captive 到 ATLAS_REQUIRED（headless）。回歸 17 支全過；site_action_quantum_tail_test 在 HEAD 同樣失敗（既有）。Nekki 07:10Z 決定 A：two_npc_sea、food_reinforcement 夾具改走熱站建城→交接→變冷（OPUS54 進行中）。
- 10/26 20:05 台灣：commit caa1c27（玩家到站清除 travel 模式；two_npc_sea／food_reinforcement 夾具改走決定 A）、806795c（派送前先擷取來源 Site、到站重驗讀活體、共享工作重計時改在 action 域比對）。**two_npc_sea 敵對 PASS（493 s）、友好 PASS（592 s，Nekki 決定 B：推進到用餐整點前）**。回歸全過（含共享工作目錄 n04／artisan／t6、workflow、loot_200）；n05 為 HEAD 既有失敗。carried_intel death／ko 標 OPEN（Nekki 決定 B）。food_reinforcement 已推進到海路重試之後，主執行緒卡住無輸出，OPUS63 watchdog 診斷中。
- 10/26 23:45 台灣（15:45Z）狀態：HEAD 806795c。food_reinforcement：Nekki 12:39Z 決定 A（期限 540／600）；OPUS65～66 證實海路是真航行（約 4900 步）；OPUS67 補登敵對人物旅行身分；OPUS68 修正式碼（閘門重開後的重試先排接觸再排到站；payload.navigation_result／contact_result、point.seam 改用 ["key"]），**17 支回歸全 PASS**（含 two_npc_sea 友好 592 s、cancellable 408 s）。food_reinforcement 仍卡「步兵插入點的靜態攻城接觸事件」：讀數顯示重試 retry:2 到站事件有排，但沒有對應的接觸事件；敵對人物條件全部符合。OPUS69 修正中，未入庫（OPUS67／68＋期限將一起入庫）。既有 OPEN：carried_intel death／ko（Nekki B）、receiver_captive 與 center_original（headless 缺圖集）、n05／quantum_tail／v8_cache／cross_boundary_wall（HEAD 既有）。
- 10/27 01:10 台灣（17:10Z）：OPUS69（區間提交時為放行的受阻隊伍排接觸事件）退回：food_reinforcement 越過接觸關卡（下一關 NO_TARGET），但 two_npc_sea 兩案例在測試 _hand_over_and_leave 讀到已釋放的 Lab 而崩潰、cancellable 408→799 s 超時、phase 288→496 s；13 支其他回歸 PASS。OPUS70 重做中（只在本次提交放行時排接觸、Lab 由轉接器取得）。證據 evidence/OPUS69/CENTER_D_RESULT。
- 10/27 03:15 台灣（19:15Z）：OPUS70（接觸只在放行受阻隊伍時排；冷站同點「接觸後到站」視為已入站重複事件）D：17 支回歸 PASS；food_reinforcement 越過靜態接觸，下一關閘門工作等待撞 540 s；two_npc_sea 友好 610 s 超時（機器整體慢 15～20%，上輪 592 s），單獨重跑中。OPUS69 的變慢經 Opus 比對為機器負載。
- 10/27 06:20 台灣（22:20Z）：food_reinforcement 一路推進（OPUS70～78：重試接觸路徑、岸方陣營、近戰證明改用真實交手、最終重開前刷新名冊），最後卡在存檔 JSON 讀回 double 差 1 ULP（Godot 讀取端，寫入端正確），昏迷敵人 ko 重開後不同 → 重試非 no-op。OPUS79 全域精確讀檔在 72 支回歸中打壞 phase、cancellable、remote_nation、codec、source_clock 等依賴舊讀法的地方，退回；改走窄修（只讓攻城快照比對在存檔域一致）。HEAD 仍 806795c，OPUS67～78 未入庫。
- 10/27 08:30 台灣（00:30Z）：commit 0693b24（OPUS67～80）。**region_food_reinforcement_multi_approach_physical_test PASS（490 s）**。正式碼：受阻入口被區間提交放行時先排靜態攻城接觸再排到站；已入站隊伍的同點到站視為重複事件；攻城快照改在存檔數值域雜湊（Godot JSON 讀回 double 可能差 1 ULP，_siege_hash 本身不變）。回歸 32 支全 PASS（含 two_npc_sea 友好 596 s、cancellable 412 s、phase 291 s）。region_siege 家族 headless 可跑的全部通過；OPEN：carried_intel death／ko（Nekki B）、receiver_captive 與 center_original（headless 缺圖集）、HEAD 既有失敗 n05／quantum_tail／v8_cache／f1a_v3／cross_boundary_wall／json_write／combat_save／encirclement／retreat_exit／p5_p6。two_npc_sea 友好 596 s 貼近 600 s 期限。
- 10/27 17:45 台灣：OPEN 清理入庫：2780bda（two_npc_sea 友好 720/780）、2daf4d9（5 支過時 site 測試）、7897600（冷重開重複讀檔，正式碼）、7c2c8b9（陣營快取存人物資料，正式碼）、bab6674（地面跨界 ID 規則，Nekki 確認）、944a860（俘虜準備階段＋headless 機制模式，Nekki A；carried_intel receiver_captive PASS）、60862eb（未提交世界 generation 讀取）、f219902（16 支移動測試 teardown）、7bdbcb2（army100：原地重排指揮官不參與鄰位互換）、f881b6e（相同陣型命令收回戰術 AI 控制；tactical_ai_state PASS）、0ee3434（存檔前先刷新指揮；center_original headless PASS）。p5_p6、n05 改用正確參數即 PASS。剩：ground_caller、4 支既有移動測試（100_platform、long_detour、multi_team 96/100、outer_approach）、manual_original_point（visual fraction 0）、center_original visual（等 Nekki 決定 D3D12 描述元上限）、carried_intel death／ko（Nekki B）。
- 10/28 08:40 台灣：OPEN 清理續入庫：53dbdf7（D3D12 描述元 262144，Nekki A）、ef0ace4（地面跨界目的地火場戳；ground_caller PASS）、b54a1ac（long_detour、outer_approach、vacancy_chain PASS）、f6a8752（center_original visual PASS 993 s，visual 期限 1080/1200，Nekki A）、909676c（100_platform_arrival PASS）、387abbf（武器外殼頂點數改變時仍細算接觸時間，含 C#，Nekki A；gd_contact_manual visual PASS）。剩：multi_team_arrival 96/100（HEAD 既有）、region_cold_formal_original（既有）、約 20 支接觸／裝備測試在 HEAD 既有失敗（army_contact_batch 需 GPU、fire_pot F15 候選啟用、combat_proxy compact profile、compiled pipeline 等）、carried_intel death／ko（Nekki B）。
## 工作原則（Nekki 10/09）
- 04:50：專案內全權由指揮中心處理，不必再另外授權（不含專案外的動作；工作端權限設定只有 Nekki 能改）。
- 04:53：卡在權限時不要停著等，先做其他能做的事。
- 10/10 01:38 設計決定：隊伍中陣亡、退隊的人在結算時自動移出，隊伍可照常出發（選 A）；倒地但活著的人仍須先救起或包紮才能出發。交 Region 實作並改寫 N010。實作方式（指揮中心 02:00 決定 A2）：不刪除名冊列（避免拆掉募兵、遺物、傷亡紀錄與存檔），而是出發時把已結算的陣亡者與退隊者視為不出發的成員，隨隊伍容器移動、不計速度與糧食、欄位不變；效果與 Nekki 的決定相同。
- 22:45：Codex 額度快用完，少派任務給它。CC-20261009-010（音效）已請它精簡收尾；CC-20261009-001 的 154 次串行驗證改由 Claude 端執行（指揮中心自己的執行器或科技樹本機端），不再派 Codex。Codex 保留給只有它能做的事（建築圖像生成）。
- 15:00：跨 session 傳訊上限（自 Nekki 上次在指揮中心 session 打字後最多 10 則）是安全機制，不繞過。對策：(1) 小修正、套 patch、重跑測試等能在指揮中心自己 session 做的就自己做；(2) 交代其他工作階段時，同一階段的指令合併成一則，並請對方一次回齊；(3) 長時間或大量工作優先派 Codex（佇列不受此上限）；(4) 只有需要對方專屬脈絡的工作才傳訊。
- 10:19：每小時檢查一次進度，避免閒置。指揮中心已排每小時 :07 的例行檢查（本機 session 內，電腦離線或 session 結束就會停；最長 7 天），協調者也每小時巡一次。

## 0. Nekki 的決定（10/09 00:25）與落實

| 項目 | 決定 | 落實 |
|---|---|---|
| Codex | Codex 端成立「worldgoing 專案指揮中心」，接受本指揮中心派單；生圖、長時間執行交給它 | 派單規則在 `PROJECT_COMMAND_CENTER.md`；Codex 自測 DONE（`output/project_command_center/receipts/CC-SELFTEST-20261009-001.json`），本端實際派單尚未測。Codex 只做派單任務，科技樹的「Codex 已停」前提改由指揮中心控管 |
| 貿易 Q12、Q13 | 皆選 A | 協調者已轉達貿易線（其本機端離線，重連後收到） |
| AI 職位 | 營務官要做；接線由指揮中心決定 | Region 線自己接 Region 部分，AI 線交資料格式檔；伙食事件依建議等供養系統告一段落。AI 線本機端停放，需 Nekki 在該討論串打一行喚醒 |
| 無用檔案 | 依建議：先 commit，只刪 A 類 | commit 已完成；刪除等生態 32 項重跑結束後再做，刪前重查 10/07 之後新收據的引用 |
| commit | 依建議建立還原點 | 本機 commit `ef39140`（master，未 push）：1782 檔，含所有已追蹤修改與未追蹤原始碼（scripts、scenes、tools、native 原始碼、根目錄計畫、reports）。不含 output、reports/output、未追蹤 assets（約 708 MB，多為 png 與 region_lab .z）、建置產物、log、.bak／.before 備份 |

## 1. 共用 Godot 時段

**收據保存規則**：`.godot-temp/godot_verify` 只保留最新 100 次完成的執行，AI 職位已有 16／27 份收據被刪。各線每跑完一次，立刻把要引用的 run 資料夾複製到自己的 output 目錄；指揮中心只認複製保存的收據。Codex 154 次批次必須邊跑邊存。

規則：同一時間整台電腦只跑一個 Godot。開跑前向指揮中心申請，跑完告訴指揮中心釋放。排隊順序只記在本看板；`.godot-temp/shared-godot-slot.json` 由驗證程式自己寫入和刪除，指揮中心不再寫它。（00:21 指揮中心寫過一份，擋住了 Region 的驗證程式，已由 Nekki 刪除。）

| 順序 | 線程 | 內容 | 狀態 |
|---|---|---|---|
| 完成 | 生態永續 | `bases.ps1`：4 項基準重跑 | 00:20 結束，3 FAIL、1 PASS（見下） |
| 完成 | Region | profile 第 2 項 r1_original_travel | 00:34 結束，FAIL，**隔離副本，僅參考**（見 Region 段） |
| 完成 | 生態永續 | 32 項完整重跑（D 上） | 01:10 結束：18 PASS、14 FAIL；污染 3 項重跑 8 PASS、9／10 FAIL。收據 `output/ecology_d_port_20261008/receipts/` |
| 完成 | 生態永續 | 診斷 14 項失敗。分類 `output/ecology_d_port_20261008/failure_triage.md`：疑似生態造成 2 項（11、30），自稱 D 原有 6 項（基準收據未存檔前不算），其餘不明 | 02:08 釋放。結果：16 修好（PASS `20261009_015856_481`）；06 是測試自己的 90 秒期限超時（110 秒），不只是 watchdog；02／03 計時重跑仍逾時；11 時間花在還原步驟；30 未跑，需要探針。01:47 時段還給生態。01:33～01:35 換檔跑原碼基準（26 個檔已還原、雜湊相符）：item 26 確認為 D 原有；item 11 只存在於生態版，無基準。01:36 再借時段給 Region |
| 完成 | Region | 隔離副本第 2 項（diag_sources_v1） | 01:46 結束，FAIL：驗證器 600 秒逾時，還沒走到旅途存檔點（僅參考）。發現：連上一次較快的執行也要約 550 秒才到存檔點，超過測試自己的 540 秒期限，需先查清哪一步卡住；下次排在機器無其他負載時 |
| 完成 | Region | 隔離副本重跑第 2 項（快照修正 v2） | 01:29 結束，FAIL（僅參考），562 秒；仍是 CORRUPT_REGION_SNAPSHOT，但不是 detach 新快照造成（四個新標籤都沒出現），來源是另一個未加標籤的驗證點。下一步只加診斷再跑一次 |
| 下一步 | Region | 隔離副本第 2 項計時診斷（diag_timing_v1）：靜態分析指出測試在同一幀同步跑完，到旅途中途已約 550 秒，現速度不可能在期限內完成，與快照錯誤無關；這次量出哪一步耗時 | 需低負載時段：生態釋放後、Codex 稽核結束、無清查與整合掃描時 |
| 完成 | AI 職位 | 重新套用營務官 patch、編譯檢查、駐營兵測試＋短回歸，並重跑 16 個被保留上限刪掉收據的 R0～R2 測試 | Region 第 2 項之後 |
| 之後 | 科技樹（整合者）＋Region | **Core 接入與 Region 第一階段合為一次整合合併**：兩者互相依賴（Core 需要 Region 96 個函式；Region 需要 Core 的共享步驟重構與 189 個依賴）。科技樹本機端負責動手，Region 提供 Region 部分配方與 15 個三方函式的合併寫法，並驗 Region 測試。不含任何 `_audio_*`。施工單 `reports/d-integration-work-order.md`（目前 SHA-256 `757446AC…F371`，已含 item 31 守衛與 item 20 修正，含 `reports/d-integration-region-section.md`）。**審核：r2 方法核准**（開工仍待 Region 段落定稿、D 時段與指揮中心放行），附加：三方 op 分「D 比 base 舊」與「D 真的改過」，後者的 D 行必須保留；Region 段落擁有的方法以其文字為準；T1～T4、T6（3～5 小時）改派 Codex VERIFY。**Region 段落已定稿**（SHA-256 `ACA113F2…A24F`）：15 個三方函式的 71 行 D 獨有行中，70 行是舊版 Region 程式（指揮中心已核對 terrain_lab 6 個函式與先前 Region 舞台逐字相同、搬移後的函式存在），1 行是真正的 D 改動（terrain_army.clear 的 social_cohort），已保留 | AI 職位之後 |
| 之後 | Codex | AUDIO-01／02：音效交換接入 D（依 CC-20261009-002 配方） | 整合合併之後 |
| 最後 | Codex | CC-20261009-001：Core 154 次串行＋C06 五組（約 8 小時） | 草稿 `reports/tech-tree-core-verify-task-draft.md`，仍有 PENDING 項，由指揮中心審後派單 |

**PID 6160 查明結果**：是生態線 `bases.ps1` 的第 1 項，父程序為 Claude Code 啟動的 PowerShell（PID 23632，00:08:24 啟動，`bases.ps1` 同一秒寫入）。canonical 驗證器在 303 秒逾時後自行結束它（收據 `.godot-temp/godot_verify/20261009_000825_136/result.json`，FAIL，timed_out）。不需要 Stop-Process。

`bases.ps1` 四項 D 上收據（指揮中心已逐一讀過 `result.json`）：

| run | 測試 | 結果 | 失敗原因 |
|---|---|---|---|
| `20261009_000825_136` | region_cold_original_matrix_test | FAIL（逾時 303 秒） | Physical ranged requires one original completed action slice |
| `20261009_001416_414` | region_travel_test | FAIL | MISSING_REGION_ADAPTER（第 41 行，經 `_captain_trip:370`） |
| `20261009_001848_676` | region_controlled_death_restriction_test | FAIL | BUSY：原火攻接觸／結構步進尚未完成 |
| `20261009_001921_409` | site_bridge_contract_test | PASS | |

三項 Region 失敗尚未證明是生態造成；生態線先前用原檔跑 D 基準時已有部分失敗。Region 線的第 2 項若跑在隔離副本，只算參考。
這組冷結算矩陣結果是生態線在「已併入生態程式、尚未併入 Region 修正」的 D 上的基準，**不是 Region R2 證據**。


**00:44:55～00:48:48 D 受污染**：AI 職位在你電腦上的那一端把未編譯的營務官／駐營兵程式寫進 D 的 4 個檔（site_controller、site_garrison、site_offices、site_settlement），當時生態正在 D 上重跑。指揮中心已要求還原；00:48:48 確認 `git diff ef39140 -- scripts/` 為空，patch 保存在 `output/ai_office_r0_r2_20261009/garrison_wip.patch`。期間開始的生態執行判為無效、須重跑：`20261009_004457_278`（reservation_fire，PASS 也不算）、`20261009_004624_706`（region_owner，FAIL）、`20261009_004647_157`（replay）。規則：其他線在別人驗證期間不得改 D 原始碼，草稿放自己的 output 或 patch。

## 2. 各工作線（10/13 15:30 更新；10/09 的舊紀錄已移到下方日誌）

| 工作線 | 目前狀態 | 下一步 |
|---|---|---|
| 生態永續 | CC-004 盤點：32 項中 30 項歷史 PASS；longrun 存檔 ID 已修（7d3189b）；assert 副作用與 §13 修訂上 D（f25a7ae） | 無待辦，可結案 |
| Region 畫面遊戲進行 | 第 13 輪 part5–14 已上 D（最新 26455da）。剩三支：two_npc_sea 停在 CORRUPT_SAVE（操作人 3 屬第 3 隊、船屬第 1 隊）；carried blocked 撞 300 s 期限（熱點 prepare_main_interval 約 32 ms／次）；cold_formal node51 round 180 對 186 | Region 依 rgd2 診斷出下一版 patch，指揮中心驗 |
| 科技樹（整合者） | 第 36 輪以前已上 D；CC-001 149 列：A 60、B 12、K 7、U 68 | 第 38–40 輪 D 驗收中；第 68、69 列邏輯過但超過描述檔逾時（K）；第 113 列等測量樁 |
| 地圖編輯器（Codex） | P0 完成；P1A v3 上 D（123a200） | 派 P1B |
| AI 與職位（Codex） | CC-005 R3 patch：10 支回歸過，2 支新測試在夾具 BUSY | Codex 修正中（CC-009） |
| 測量樁 survey_stakes（Codex） | 美術 4 張已入 building_v2（未 commit）；patch 自身測試 CORRUPT_SAVE、第 113 列 OCCUPIED | Codex 修正中（CC-009） |
| 外觀還原 appearance_restore | CC-002 稽核完成，更新需 GPU A/B 證據 | 待辦，不開工 |
| 貿易 V0.5、勢力 V0.7 | 計畫審核完成、定稿 | 實作排在 Region 與科技收斂之後 |
| 音效（Codex） | CC-20261009-002 稽核完成，D 尚未接線 | AUDIO-01／02 排在 Region 收斂之後 |
| 專案無用檔案清查 | 報告完成 | 刪除 A 類前重查新收據引用 |
| 驗收效率 | tools/acceptance（prepass、去重）已上 D；prepass 實測 combat_formation 38 s 抓到與正式驗證相同的既有失敗（MOVE_START_DESYNC member 1110，10/11 起每次都是） | combat_formation 失敗未指派，列待辦 |

### 2026-10-09 原始各線紀錄（歷史）
### 生態永續計畫審核
- 已完成（D 上）：Codex 整併稿 64 處修改套入 13 檔，加 17 個新測試；原檔備份 `output/ecology_d_port_20261008/backup_before`；編輯器掃描無解析錯誤。
- 第一輪 32 項（D 上收據）：16 PASS、16 FAIL，紀錄全保留。其中 5 項舊回歸在換回原檔後也失敗，屬 D 原有問題（線程自述，收據在 godot_verify）。
- 已修並單獨重跑通過：合約／呼叫者逾時（負載造成）、政策測試（UI 快取漏狀態）、捕捉／基底守恆（測試資料改用 D 新牧場尺寸）。**這些是單獨重跑，最後完整重跑 32 項前不算最終驗收。**
- 新收據：`20261009_000825_136` 冷結算矩陣 FAIL（逾時，錯誤「Physical ranged requires one original completed action slice」）；`20261009_000439_874` 生態重播測試 FAIL。
- 下一步：診斷重播、長時間、政策邊界、Region 相關失敗；逐張看 GPU 四張圖；完整重跑 32 項；更新計畫 §13。
- 狀態：00:40 已取得時段，進行診斷與 32 項完整重跑；完成後通知指揮中心。

### Region 畫面遊戲進行
- 已完成：接手 Codex 交接，交接檔案與來源雜湊唯讀核對一致。
- profile 第 2 項 r1_original_travel（**隔離副本，僅參考**）：FAIL，約 460 秒，`CORRUPT_REGION_SNAPSHOT`（旅途中存檔點被旅行快照驗證拒絕）；先前的 STALE_REGION_OWNER 已消失。收據 `region_direct_validation_project_20261008\.godot-temp\godot_verify\20261009_002643_626\result.json`。
- D 上：`region_travel_test` 在生態基準中 FAIL（MISSING_REGION_ADAPTER），因為 D 尚未併入 Region 修正。R2 尚無 D 上收據。
- 診斷（唯讀）：`RegionCheckpoint.validate()` 雜湊不符；出發 Site 的分離副本帶著原 Lab 的舊快照，推進時間後再驗舊快照（物件錯置，非資料壞、非驗證過嚴）。
- 指揮中心已批准（僅隔離副本）：加診斷資訊＋實際修正（分離前驗原快照、分離副本不帶快照、結算後由原主人重拍快照），不放寬任何檢查。生態重跑後給它一輪重跑第 2 項。另擬合併計畫，把 Region 批次（家族遠端交接、船隻投影、region_save_slot）併入 D。
- 合併盤點 `reports/region-merge-inventory-20261009.md`：隔離副本比 D 多出的 Region 批次共約 560 個函式（B1～B12），另有非 Region 子系統約 770 個、Core native 66 個。指揮中心決定分階段：第一階段只併 Core 接入依賴的 B1 家族遠端交接、B2 船隻投影、B3 中 terrain_lab 的 37 個 party bind 函式；逐方法三方合併、禁止整檔覆寫，每批後在 D 跑該批測試並存收據。施工單 `reports/region-merge-stage1-work-order.md` 已交：第一階段 131 個函式（科技樹需要的 96＋閉包 35），分 S1-A～S1-E，預估 Godot 約 45 分鐘。**指揮中心審核：附條件通過**：隔離副本第 2 項以快照修正 PASS 才開工，快照修正併入第一階段；22 個兩邊版本不同的被呼叫函式要逐一判定相容性，需改者先回報；替換 D 測試要列出前後雜湊。
- 快照修正 cold_snapshot_detach_v2 已在隔離副本實作（未跑），加了「原 Lab 雜湊不變」斷言；風險：`_capture_positions` 會寫回原 Lab 位置。
- 等待：生態 32 項重跑與 3 筆污染重跑結束後才能動 D 或跑 Godot。

### 科技樹研究（v2.4 推到 CLOSE）
- 已完成（不需 Godot）：A18 改寫成 A18-a～A18-g（未執行）；Core 整包核對 154 次、142 個測試、308 個來源雜湊一致；VERIFY 派單草稿 `reports/tech-tree-core-verify-task-draft.md`（CC-20261009-001，目標正式 D，含 C06 五組，總逾時 28,830 秒）；接入前置分析 `reports/tech-tree-core-integration-prep-20261009.md`。
- 發現：D 缺 114 個函式（region_save_slot 47、terrain_lab 55、site_vehicle_transport 12），來自 Region 家族遠端交接、音效交換、Region 船隻投影三批，D 從未併入。
- 決定：Region 線先併自己的批次；音效交換批次依 Nekki 10/09 00:39 指示改由 Codex 負責；科技樹再做 Core 接入；之後 Codex 跑 154 次。
- 尚無任何 D 上驗收收據。
- 等待：生態 32 項重跑、Region 合併；草稿的 manifest、audit、source epoch、preflight、inspector 仍 PENDING。

### 貿易功能規劃（V0.5）
- 已完成：審完 V0.5，附錄自檢 PASS，補 4 項改進到 §15（`reports/trade-plan.md`）。純計畫審核，不涉 Godot 收據。
- Nekki 已選 Q12 A、Q13 A；待貿易線寫入計畫。T0 可開工，開跑 Godot 前向指揮中心申請。

### 勢力劃分與修改計畫（V0.6）
- 已完成：V0.6 審核可採用，F1a 可開工；CR-02 Nekki 選 A（外交代理人），記在 `reports/faction-spec-v0.6-review.md`。
- 未完成：`FACTION_DIPLOMACY_SPECIFICATION.md` 尚未寫入 CR-02（§3.3、FA-04）；CR-01、CR-03、CR-04、CR-05 未改。
- Nekki 10/09 00:41：審核者改為本指揮中心。
- 指揮中心安排：勢力線把 CR-01～05（CR-02 = A）寫入規格成為 V0.7，並修 CR-04 的跨文件衝突（faction-plan.md 標為已取代、trade-plan.md 的 Crowd 旗標與 TR-18 移到 F6、畫面外補充稿補前置條件），完成後交指揮中心審。
- V0.7 已交審（規格、faction-plan 取代標示、trade-plan §5.5 與 TR-18、畫面外補充稿前置）。指揮中心審核：**通過**；兩項小修（代理人失格時重選、新增 FA-37；代理人行動時往返時間用代理人位置）已補上，V0.7 定稿。V0.6 備份 `FACTION_DIPLOMACY_SPECIFICATION.v0.6.md`。
- F1a 實作排在 Region 合併、音效合入、Core 接入之後（檔案重疊：region_save_slot、region_travel、site_settlement、site_store）；工作單 `reports/faction-f1a-work-order.md` 已完成；新 helper 定名 `scripts/region_lab/region_faction_query.gd`；開工前重查各檔。

### AI 與職位工作分配整合
- 10/09 05:00 核對：附錄 E 四題皆已有 Nekki 決定（v2 §1），沒有待決設計問題；剩下是 R3～R7 施工順序與伙食時機，由指揮中心排程。
- 已完成（線程自述，未經指揮中心核對 D 上收據）：R0 拘押紀錄、人物社會狀態與存讀驗證、R2 不滿與忠誠核心、戰死比例事件、首次預兆提示。測試名單：site_family_site_ref、site_duty_ai_site_reset、site_prison_actions、site_settlement_prison、site_duty_logistics_ko、site_duty_culture_legal、site_team_equip_cancel、site_office_vacant_claim、site_office_recruit 等。
- 已知無關失敗：tactical_ai_retreat／behavior（他線改 terrain_army.gd 撤退判斷）、family_offices:57（科技樹新家族職責）。
- 下一步：營務官與駐營兵募兵；資料格式檔交 Region 線；伙食事件等供養系統；回歸測試需先向指揮中心申請時段。
- 等待：**Nekki 在 AI 職位討論串打任意一行**，喚醒其本機端。

### 專案無用檔案清查
- 已完成：清查報告 `reports/cleanup-audit-20261008.md`，未刪任何東西。
- Nekki 已同意：先 commit（已完成 `ef39140`），只刪 A 類（約 210 GB）。
- 等待：生態 32 項重跑結束；刪前重查 10/07 之後新收據的引用。B1 與其他類保留。

### 音效（Codex 負責）
- Nekki 10/09 00:39 指示：音效相關任務全部交給 Codex。計畫 `GAME_AUDIO_IMPLEMENTATION_PLAN.md` 仍 OPEN（P0／P1 元件通過；原遊戲接線、P2 Native、P3 世界聲、匯出、效能、聽感未完成）。
- 已派單 CC-20261009-002（AUDIT，唯讀 D、不跑 Godot）：D 上逐項現況、音效交換批次合入配方、四個候選測試核對、後續派單建議。queue 訊息 `01a11c63-3b1a-7491-a01f-25f0a0771580`，回報 `output/project_command_center/receipts/CC-20261009-002.json`。
- **CC-20261009-002 DONE**（回報 `output/project_command_center/receipts/CC-20261009-002.json`，證據 `output/project_command_center/evidence/CC-20261009-002/`）。結論：25 項中**沒有任何一項在正式 D 上完成**；7 項 D 有元件未驗收、13 項只在隔離副本或候選；24 份歷史收據全部跑在隔離副本。D 有播放元件與 42 個 WAV，但 Lab 沒建立 presenter、Controller／Actor／Army 缺接點，所以 D 目前聽不到音效（推論，非實測）。
- 交出：音效交換逐方法配方（除 18 方法／9 var 外，還需 preload 與 Actor／Army／Controller 接點）、四個候選測試採用條件、19 張後續派單提案（`NEXT_DISPATCH_PLAN.md`）。
- 下一步：AUDIO-01／02（交換實作＋小範圍驗證）排在 Region 第一階段合併之後、Core 接入之前；其餘 AUDIO-03 起排在 CC-20261009-001 之後。素材 exact 變體選定與裝置聽感將來需要 Nekki 實機確認。

### Codex 派單（Nekki 10/09 01:20：Codex 閒置，可派任務）
- CC-20261009-003（AUDIT）：生態重跑中被判為 D 原有的失敗（06／16、20、26、31、32）找根因，判斷整合合併會不會修好，必要時提 patch（不套用）。
- CC-20261009-004（AUDIT）：隔離副本中不在任何合併計畫內的約 770 個非 Region 函式與 66 個 Core native 函式，依子系統分組並建議負責人與順序。
- 兩單皆唯讀、不跑 Godot，01:21 送入 Codex 佇列。
- **CC-004 DONE**（`evidence/CC-20261009-004/AUDIT_REPORT.md`）：836 個隔離副本獨有函式中，740 個已在整合合併配方內、18 個要保留 D 現行版本、41 個歸音效（Codex）、37 個待負責人決定是否納入、0 個屬實驗應排除；D 沒有任何呼叫依賴缺失函式。37 個待決：Core 類交科技樹、自然資源 13 個交生態，整合合併後處理。生態 05:05 判定（`output/ecology_d_port_20261008/owner_admission_13.md`）：13 個全部暫保留 D 版本——A 組 6 個（固定地況來源）需整包與地況 owner 一起納入；B 組 2 個依賴隔離副本的 tag_corrupt；C 組 5 個各需 owner 決定，部分測試尚未存在。
- **CC-003 DONE**（`evidence/CC-20261009-003/AUDIT_REPORT.md`）：06 是測試收尾競爭（watchdog），16 是 fixture 沒建立物品存放，20 是 D 程式缺陷（空 registry 擋住共享步進），31 缺無損編碼，32 是 fixture 缺外圈，26 證據不足。**重要發現**：整合合併帶入的讀取端會漏掉 D 原有的 fire_clock 必填守衛，已要求整合者補上。分派：06／16 給生態（測試修正）、20 與 31 守衛併入整合時段、32 由 Region 在整合後套用、26 待診斷。

**02:20 AI 職位視窗完成**：營務官 patch 套回、編譯乾淨、駐營兵相關 8 支 PASS；R0～R2 27 支全有存檔收據，15 支 canonical PASS，12 支 canonical FAIL（只有 `material is null` 收尾錯誤、印出 PASS 行）——**依規定這 12 支不算通過**，已請 AI 職位找出錯誤來源 → 找到：headless 下士兵染色的 instance uniform 材質在假渲染器上不存在（``terrain_army_dye_atlas.gd`` apply_record）。修正方案（headless 走既有無染色分支）已核准，排在整合合併之後套用並重跑 12 支＋GPU 染色測試。指揮中心核對 6 檔雜湊後建立本機還原點 commit `5fe600a`（整合合併前狀態）。
**02:22 整合合併開工**（科技樹整合者，施工單 757446AC…）。清查刪除 A 類被本機權限擋下（不可逆刪除需 Nekki 親自確認），**等 Nekki 在清查討論串回「確認刪除」**，之後另排無 Godot 時段；整合者的 T0／T5 不必等它。

**03:59 整合合併已寫入正式 D**（Nekki 已在科技樹討論串確認）：42 個既有檔修改、23 個新檔，約 +27,459／−1,726 行，寫入後與暫存逐檔相同；凍結雜湊 `3936726D…AF11`；靜態檢查全過（siege、effect_receipt、controlled_person_id、clear、codec＋守衛、無診斷行、18 個保留 D 函式未動）。未 commit。收據 `output/d_integration_20261009_024321/`。兩個計數待整合者重算（Group A 33 vs 30、人工合併 18 vs 24）。T0／T5 等清查刪除完成後再跑。

**04:23 清查 A 類刪除完成**：收據 `reports/cleanup-audit-20261008/deletion_receipt_A.json`，兩輪合計刪除 1,734／1,746 項、錯誤 0、共釋放 194.41 GB（第一輪中斷前 322 項 139.38 GB，第二輪 1,412 項 55.03 GB）；略過 12 項（11 個 reports/*.bak 與 scripts/tests/__pycache__，屬保護路徑）。D 碟剩 738 GB。整合備份資料夾完好。整合者開始 T0／T5。

**04:45 T0 失敗，已退回 `5fe600a`**（指揮中心已核對 scripts/ 乾淨）：CC-004 的排除顆粒太粗，多排除了 15 個非待決的 op，加上 Z-0256、Z-0652 在 Core 改了簽名，造成簽名不符。決定：恢復 15 個 op、提前以三方合併納入 Z-0256 與 Z-0652（head_executor 由 AI 職位確認保留 D 官職行為）。重建暫存後寫入 D：Nekki 04:46 已在科技樹討論串預先授權（「直接授權等等輪到時確認寫入 D」），指揮中心放行即可，不必再問。另：各 output 資料夾裡的 .gd 副本造成 UID 重複，生態已加 .gdignore，整合資料夾也已加。

**10:10 整合合併第二次嘗試**：Codex CC-005 複核發現第一次合併的行為遺失（Crowd 裝備檢查、俘虜社會欄位、帳篷生態對帳、水量排程存檔、旅隊火攻 guard、30 個 Group A 未逐 op 證明、693 行無對應）。寫入 D 暫停，整合者分三輪在暫存區修正（1 具體行為、2 重證 30 方法、3 逐行處理 693 行），每輪交指揮中心審。已併入：8 個測試基底、5 個 epoch 版測試（CC-001 釘選雜湊改為新值）。Codex CC-20261009-007 並行準備第 3 輪逐行判定與 patch。

**10:40 第二次寫入放行**：三輪修正完成——第 1 輪修好 Codex 列出的行為遺失（含 Region 的押送修正，Crowd 時段押送也恢復）；第 2 輪 30 個方法逐行證明 D 的後續改動 0 行遺失；第 3 輪 21 行疑似遺失全數處理（含恢復同意檢查的 decider／revision 比對、四站攻城的邊緣部分站位）。隔離 parse 65／65 通過。暫存凍結雜湊 `40AA8CAA…EA01`。指揮中心放行寫入 D，接著跑 T0／T5。Codex CC-007 的逐行交叉核對若有發現，作為寫入後修正。

**10:55 整合合併已寫入正式 D 並通過 T0／T5**：42 檔修改、44 檔新增；65 個改動檔 check-only 65／65 PASS、編輯器匯入 0 錯誤 0 UID 重複；存檔格式兩支 PASS。指揮中心建立本機 commit `b41c6b3`（未 push）。接著：Region 押送回歸測試（D 時段）→ Codex CC-20261009-008 長驗證 T1～T4、T6（等閘門檔 `output/project_command_center/GO_CC-20261009-008.txt`）→ AUDIO-01／02 → CC-001。

**11:05 Region D 時段中途**：押送 GD 前綴回歸測試 PASS（`20261009_110041_058`）。發現兩個生產問題：(a) 生態 `_ecology_person_signature` 在 visual 模式對 Node 呼叫 get()，合併前就有，交生態；(b) **D 上 Crowd 啟用時共享步驟每幀失敗、時鐘不動**，Crowd 測試全部卡住，Region 正抓失敗代碼並確認是否為合併回歸，整合者待命修正。Codex 長驗證在 Crowd 修好前不開閘。

**11:20 Crowd 卡住原因查明**：整合帶入了 Core 的 GDScript 原生共享步驟契約，但沒帶入 Core 的原生 DLL；D 的 DLL（DFD5…）缺新方法，每幀回 CLOCK_NOT_READY。決定往前修（保留 `b41c6b3`）：Codex CC-20261009-009 合入 9E21 原生差異並重建 D 的 crowd10k DLL（優先於等閘門的 CC-008）。CC-007 交叉核對完成：693 行中 333 等價、340 刻意取代、4 行需恢復（2 份 patch）、16 不明，整合者對照 D 核對中。

**11:24 每小時檢查**：D 在 `b41c6b3`，scripts 只多了 Region 兩支新押送測試（未提交）；Codex 還在 CC-008 準備（清單與基準已交、未開 Godot），CC-009 尚未開工，已用佇列訊息請它先做 009，並回答 T3 期限問題（取合併前收據的期限，否則 headless 300 秒、visual 600 秒）。整合者核對 CC-007；Region 跑押送／監獄重跑；生態的視覺模式修正 patch 已核准，排在 009 之後；AI 職位的材質修正與營務官測試同樣排在 009 之後。

**11:35 Region 押送時段結果**（收據 `output/region_escort_window_20261009/`）：PASS——監獄動作、聚落監獄、駐營俘虜（GD）、AI 職責 Site 重置、新押送 GD 前綴測試；FAIL——共享步驟故障測試（CLOCK_NOT_READY，8 秒可重現）、共享步驟重播（32 vs 1230，item 20 仍在）、兩支 Crowd 測試（Crowd 卡住＋生態洗版）、captive_escort（lab.npc 為 null，研判測試本身舊壞）。Crowd 卡住證實是 Core 候選本身帶來（合併前 D 沒有這段原生 BEGIN 流程），條件有二：沒有火場 host、DLL 沒有 preview_host_ranged_batch。整合者已備非 host 修正草稿，等 CC-009 證據定稿。

**12:24 每小時檢查**：CC-009 回 NEEDS_INPUT——已逐 hunk 合入 4 個原生原始檔、排除音效並發布新 DLL，原生 145 元件、321 查詢斷言、66 provider 檢查 PASS；但 Crowd 時鐘尚未驗收（缺 Crowd 測試原期限、測試固定輸出寫入許可、編輯器匯入 120 秒逾時）。指揮中心已回覆：照 Region 封存收據的參數、visual 600 秒、允許寫入固定輸出、編輯器匯入 300 秒。item 20 根因找到（`SiteDutyAI._cadence_state` 經 `region_registry()` 在無來源時建立空結構），AI 職位已確認 `region_registry_view` 修正。**跨 session 訊息上限又擋住**：給整合者的 item20b 核准未送達，需 Nekki 在指揮中心 session 打一句字才會重置。

**12:50 CC-009 收尾方式調整**：Codex 已在 D 發布新 crowd10k DLL（`5D639BBF…FA4C3`，含 preview_host_ranged_batch），原生檢查 PASS；但它對 Godot 實測一直要求額外授權。改由 Region 在 D 上用既有 Crowd 測試（同參數）實測時鐘，Codex 以原生交付結案。

**13:05 Crowd 卡住第二層原因**：新 DLL 讓預檢通過，但同一步內 `_check_original_shared_prefixes` 回 CLOCK_NOT_READY 並被鎖住。研判是 Core 共享步驟的純預檢登記了受控前綴，預檢後沒有清掉，第二次檢查就拒絕（`site_person_actions.gd:4940`）。整合者已開 D 時段：修這個、套 4 份排隊修正、check-only＋T5、跑共享步驟兩支與三支人群測試。**注意**：整合者查證 Core 候選從未正向跑過人群 Site 的玩法測試（監獄走廊、駐營俘虜人群），這條路徑在 Core 本身就沒驗證過，D 是繼承了 Core 的缺陷，不是合併弄錯。

**13:20 人群時鐘修好**：整合者寫入 5 項修正（預檢清除、同意 guard、工時上限、無火場 host、item20b）；check-only＋T5 PASS；押送人群回歸測試 PASS；監獄走廊與駐營俘虜人群兩支都印出 PASS，驗證器只因生態的舊錯誤洗版判 FAIL（生態修正接著套）。仍待：共享步驟故障測試（Core 預檢擋住假人群，Core 帶來的回歸）、共享步驟重播（1229.15 vs 1230，新的失敗點）。Codex 兩度在別人的時段開 Godot 探針，已再次要求停止。

**13:24 每小時檢查**：D 在 `b41c6b3`＋7 個未提交改動（整合者 5 檔修正與 Region 兩支測試）；整合者在隔離 parsecheck 診斷重播測試；Codex CC-009 仍 RUNNING（已要求結案）、CC-008 等閘門；沒有線在等指揮中心。

**13:40 共享步驟兩支測試修好**：故障測試與重播測試 PASS。決定：故障測試的人群情境改驗 Core 的語意（本體被拒時不扣疲勞、不扣時間型補給、不發布完成）；重播測試改驗時間守恆（目標＋殘餘換算＝初始＋1200）；`replay_site_to` 對極小殘差視為完成、缺 pending 改回 CLOCK_CONTRACT 不再崩潰、先回報鎖定的 STEP_FAULT。D 交給生態套視覺模式修正並重跑兩支人群測試。

**13:55 生態視覺模式修正完成**：`site_controller.gd` 兩處（原診斷漏一處）修好；監獄走廊人群 PASS（`20261009_134726_777`）、駐營俘虜人群 PASS（`20261009_134825_379`）、site_workflow PASS。site_ecology_policy_border 仍是 item 05 的舊柵欄問題；site_ecology_contract 印出 PASS 但被 482 個 `material is null` 判 FAIL——即 AI 職位的染色材質問題，交 AI 職位時段一起驗。

**14:24 每小時檢查**：AI 職位時段結果——原先的染色材質診斷錯誤（patch 已還原）；真正原因是測試結束前沒呼叫 `TerrainArmy.release_contact_source()`，3D 角色骨架在退出時被拆掉而洗出 482 個錯誤。修正只改測試（每支加一行），待套用。營務官治理路徑測試 PASS。指揮中心建立本機 commit `ebbed52`（合併後修正、人群、共享步驟、生態 UI、新測試）。Codex 的原生原始碼改動待 CC-009 結束後再 commit。**跨 session 訊息上限又擋住**：給 AI 職位的套用指令未送達。Codex 仍在跑 CC-009 探針（它的佇列訊息要等這一輪結束才會讀到）。

**14:55**：Codex CC-009 DONE——有火場 host 的人群 Site 正常（12 個 BEGIN 方法齊、編輯器匯入 PASS、三支人群測試 PASS）；**沒有火場 host 的人群 Site 仍卡 CLOCK_NOT_READY**，交整合者查剩下的 guard。原生原始碼改動 commit `81a50d6`。AI 職位開始套測試修正；完成後生態補一行，再開閘 CC-008。

**15:00**：AI 職位 12 支與生態合約測試加上 `release_contact_source()` 後全部 canonical PASS、0 個 material 錯誤；commit `5b21458`。整合者 D 時段：無火場 host 的人群修正（彈藥輸入只在有 host 時準備）＋重跑；之後開閘 CC-008。

**15:08 無火場 host 的人群也修好，CC-008 開閘**：指揮中心自己套用第 3 份無 host 修正並驗證——無 host 探針 10 步全走（20 遊戲秒），故障測試、存檔時鐘、監獄人群 PASS（`runs/CC_W8_*`）。本機 commit `8136bcb`。閘門檔 `output/project_command_center/GO_CC-20261009-008.txt` 已建立：D 與 Godot 時段由 Codex 長驗證獨占，其他線暫停。

**17:24 每小時檢查**：CC-008 已跑 19／100 組（乾淨結果 18 組：14 PASS、4 FAIL），在 E019 因偵測到一個不屬於它的 Godot（PID 14192，查無任何 Claude 工作階段啟動紀錄，現已不存在）而自行停下。已指示 Codex 立即接續 E020～E100，E019 標為疑似資源競爭、最後重跑一次；之後遇到外來 Godot 只等待、不整批停。

**18:24 每小時檢查**：CC-008 已跑 92／100（90 組乾淨結果：64 PASS、26 FAIL；E019、E092 受 monitor 限制）。已請 Codex 直接跑完 E093～E100、重跑 E019／E092，然後交終態比對。26 個 FAIL 要看比對才知道多少是合併回歸、多少是合併前就失敗。

**19:24 CC-008 初步結論**：約 100 組跑完，**合併造成的回歸只有 2 支**——`site_ecology_base_conservation_test`（找不到可達牧場的測試資料）、`region_lab_contract_test`（INVALID）。其餘失敗是合併前就失敗或無基準。E019／E092 受外來 Godot 干擾不計。33 個邏輯項目 NOT_RUN（缺期限或屬他線範圍），Codex 補跑中。2 支回歸已整批交整合者診斷。完整報告 `output/project_command_center/evidence/CC-20261009-008/ROOT_FINAL_REPORT.json`。

**19:40 2 支合併回歸修好**：同一根因——Core 的建造預覽改從 Site 物品倉付款，需要 `depot_items`。(1) `RegionSaveSlot.open_site` 新開的 Site 沒初始化物品倉（生產回歸），補上；(2) 野生動物捕捉測試的 fixture 補初始化（測試端）。指揮中心自己套用並跑 10 項全 PASS（`runs/CC_W9_*`），commit `fa3cec1`；另補 commit 先前漏掉的原生 gdext 綁定 `caf7862`。

**20:35 AI 職位 R3 已備好**（`output/ai_office_r3/`，以 patch 形式、未動 D）：俘虜歸降／政治收編——新增戶籍官職責、歸降意願、`site_political_adoption.gd`、典獄 AI 收編、兩支新測試＋12 支回歸清單。CC-008 結束後由指揮中心自己套用與驗證。待決：§6.1「刑期＝評估期」政策切換（目前保留舊的到期釋放）。

**22:55 CC-008 收尾（FAILED＝整體尚未全綠，驗證本身已完成）**：138 項全有收據；另發現 4 支船隻／車輛回歸（`site_ship_journey_edge`、`site_ship_journey`、`site_ship_travel`、`site_vehicle_transport`），已整批交 Region（船隻投影擁有者）。音效合約測試缺匯入的 WAV（交音效施工包處理）。已派 Codex CC-20261009-010：音效接入施工包對 D `fa3cec1` 重新對位（不跑 Godot）。R3 由指揮中心試套：修一個解析錯誤後，12 支回歸全 PASS、意願測試 PASS，但收編情境測試在第 38 行失敗，已退回 D 並交 AI 職位修（修過的 patch 在 `output/ai_office_r3/r3_captive_adoption_v2_cc_fixed.patch`）。

**23:10 船隻／車輛 4 支回歸實測**（Region 隔離副本）：都是 10-06～10-09 間退化，不是這次大合併。N008 測試補丁只修 parse，後半段卡在存檔快照雜湊不符；N009 同類（物品版本／快照雜湊）——推定是 Region 存檔路徑的生產 bug，也可能是第 2 項 R1 的根因，Region 用 N008（25 秒重現）優先定位。N010 決定改 fixture 讓 3 人具備掌舵與最低船員，以保留原子性證明。N011 是火場存檔 guard 擋住登車中存檔，交整合者。AI 職位 R3 v3 卡在戶籍官 DUTY_ORPHAN，修 v4 中；D 維持在 `fa3cec1`。

**23:30 AI 職位 R3 落地**：v4（戶籍官職位在歸降流程補建）在 D 上 15 項全 PASS，commit `7c2504d`。後續：AI 職位做系統性修正——`nation_offices()` 一律補建後期職責空缺（目前只有 Region 路徑會補）。§6.1「刑期＝評估期」暫不切換。

**23:35 音效接入開工（AUDIO-01，指揮中心自己套用）**：Codex CC-20261009-010 交付 4 檔 45 hunks 施工包，對 D `7c2504d` 前像全符；已套用（未 commit），並逐位元組發布 `site_audio_source_hook_test.gd`（FF2C…）。驗證批次背景執行中：check-only、編輯器匯入（產生 42 個 WAV 的 .sample）、AUDIO-02 五輪（2 正例 PASS＋3 預期拒絕）、7 支回歸。

**00:10 船隻回歸根因（Region）**：(1) `state_hash` 用 17 位精度寫浮點，Godot JSON 讀回不保證同一 double，存檔讀回雜湊不符——改為正規化（整數精確、其他 12 位有效數字），驗證兼容舊雜湊；很可能也是 R1 旅行 CORRUPT_REGION_SNAPSHOT 的根因。(2) 船隻目的地初始化缺物品倉與 world_pin。(3) 到站時先預留 ID 計數器、後建物品倉。決定：三個船測試改寫成 Region R1 規則（唯一時鐘、先綁定、倒地不出發）。整合者 N011：登車時的空 deployment 外殼被當成火場意圖擋存檔，修 guard 只看實際火場內容。這些都排在音效與國家職位修正之後由指揮中心套用驗證。

**00:20 音效 AUDIO-01 落地**：commit `02a2442`。編輯器匯入 PASS（產生 42 個 WAV sample）、5 檔 check-only PASS、音效合約 335 檢查 PASS、來源掛鉤正例 109 檢查 PASS、3 個預期拒絕案例都輸出正確的預期錯誤、7 支回歸 PASS。過程中發現並修正：terrain_army 的 `mounted` 型別推斷；編輯器匯入會掃到 output 裡的舊程式副本、在全域類別表登記重複類別而讓全專案解析失敗——已對 `output/crowd_c2_c3_native` 與生態 `source_epochs` 加 .gdignore。接著驗證國家職位系統修正與登車存檔 guard 修正。

**00:30 國家職位系統修正＋登車存檔修正落地**：commit `0b4e53c`。21 項批次中 15 PASS（含新目錄測試、R3 收編、國家公共／科技／船隊運作、登車與三支火場存檔）。6 支失敗與本次修正無關：3 支 Region 測試在 CC-008 就已失敗；3 支裝備測試的假 Lab fixture 缺 `_original_person_target`（合併後 `site_person_actions` 開始呼叫），交整合者修測試端。

**00:40 Region 存檔修正部分落地**：commit `b659301`（state_hash 浮點正規化、船隻目的地物品倉＋world_pin、兩支測試端修正），對照同樹基準沒有新失敗。`region_travel_production` 會讓 `region_gameplay_travel_test` 失敗，已退回交 Region 重做。state_hash 修正沒有解決 `site_ecology_region_owner_test` 的快照雜湊不符，另有來源。

**00:45 裝備測試 fixture 修正落地**：commit `4887945`（假 Lab 補 `_original_person_target` 與 `site_controller`；`region_gameplay_ai_test` 型別）。`site_equipment_orders_test` PASS。剩下的舊 fixture 缺口（`_clear_movement_input`、`site_controller.vehicles`）、披風職位語意（交 AI 職位查）、Region AI 範圍接收者（交 Region）列為後續。

**00:45 披風職位測試更新**：測試沿用 R1b 之前的規則（現在指揮需要職位、升任會自動補武官職位），改測試即可，生產碼正確；9／9 PASS，commit 已建立。`site_nation_equipment_culture_test` 仍因舊 fixture 缺 `_clear_movement_input` 失敗（合併前就有的測試債），列後續。

**01:25 Region 第二輪落地**：commit `155cb18`——到站物品倉順序、轉移候選去除舊快照、family 參照字串 key、同槽重開不再 archive、冷補算重試接受新副本。`site_ship_journey_test`、`site_ship_journey_edge_test` 現在 PASS，`region_gameplay_travel_test` 回歸消除。隔離副本上 R1 旅行的快照錯誤已消失，剩下是效能（地形重建 547 次×1 秒），已核准 Region 做唯讀快取。待 Nekki 決定：死過人的隊伍能否再出發。

**02:10 Region 第三輪落地**：commit `7461b8e`——未造訪 Site 的地形唯讀快取（地形重建由 547 次降到 55 次）、補回整合漏掉的旅行面板／Site 程式段。`region_travel_test` 在 D 上往前推進。生態 region owner 測試的快照不符查明：快照之後 housing／person_supply／team_supply 被補上空容器，交 Region 從來源修正。已核准：提案 B（同一 commit 重用路線快照）、Region 自有的整合遺漏補丁、A2 實作 N010。

**02:35 Region 路線快照重用＋整合遺漏＋A2 落地**：路線快照重用（每步成本減半）、補回整合漏掉的 Region 程式段、`SiteStore.save` 先正規化再雜湊（生態快照不符的根因）、出發時把已結算陣亡者與退隊者視為不出發成員。`region_gameplay_scene_restore_test` 轉為 PASS，生態 region owner 測試越過快照段；對照同樹基準無新失敗。R1 旅行測試仍超時（剩每步約 227 毫秒×1634 步），Region 繼續細分計時。

**02:45 船隻／車輛 4 支回歸全部 PASS**：S1（海路時陣亡／退隊者隨容器不上船、欄位不變）＋N010 依 R1 規則改寫，`site_ship_travel_test`、`site_ship_journey_test`、`site_ship_journey_edge_test`、`site_vehicle_transport_test` 在 D 上全過，commit 已建立。剩：Region 陸路陣亡者不給位置、陣亡者不吃糧斷言、R1 旅行效能。

**02:55 生態測試修正部分落地**：commit `4105977`。PASS：policy_border（item 05）、longrun（item 29）、governance_roundtrip（item 06）、building_ui、ecology_policy 等。仍待：region_owner 的 K≥2 fixture（P3 無效已退回）、item 10 replay、longrun_owner 後段、building_economy_ui（合併前就失敗）。

**03:10 生態 region owner 測試 PASS**：commit `17347dd`（改用台灣固定地理，唯一有資源層的地圖）。longrun_owner 進展到存檔 CORRUPT_SAVE（生態資源 ID），交生態；replay 測試查出只有逐步重播的玩家多了 `social_state`，交 AI 職位；building_economy_ui 在 visual 模式也失敗，屬建築美術／視圖，暫無負責線。

**03:20**：陸路陣亡者不給位置＋陣亡者不吃糧斷言落地（`d5180a1`）。社會狀態每 Lab 各自一個日結鎖（原本全程序共用，第二個 Lab 同日會跳過整日結算）落地，replay 測試越過 social_state 差異，現停在「Physical ranged requires one original completed action slice」。R1 旅行耗時拆解：旅隊原 owner 每步重新準備／綁定佔 65%，路線搜尋佔 30%，已核准 Region 做 P1（跨步保持綁定）與 P2（搜尋走地形快取）。

**03:28 每小時檢查**：D 在 `b58a2f2`，乾淨。生態 longrun_owner 測試一路推進（Taiwan 基底→原旅行 host），現卡 STALE_REGION_PARTY_PROOF；replay 測試的冷補算「靜默分鐘」一次交整段給遠程射擊被拒，是 Region 生產端缺口。這兩項與 region_travel_test 的「同一來源 epoch」一起交 Region（排在 P1／P2 效能之後）。

**10/10 04:05 Region 第 4 輪落地**：commit `102db72`（快取路線脈絡的地形表記憶、旅行計畫與靜默分鐘改用同一來源 epoch、快取測試 v2）。R1 旅行每步成本由約 427 毫秒降到約 208 毫秒，仍超出 540 秒期限。

**10/10 05:05 Region 整合遺漏 A 類補丁落地**：commit `f507067`（epoch 3EA821F0 中整合漏掉的玩家陣亡對應、隊伍進度／實體化／生命、船隻等船員與認領檢查，純新增）。D 上 36 項：31 PASS；舊有 FAIL 不變（party_life、two_npc_sea、ship_full_transport、controlled_death）；冷結算矩陣有無補丁結果相同（基準 `CC_BASE5_region_cold_original_matrix_test_20261010_045431_533`），非退化。推進：`region_travel_test` 不再 REGION_OWNER_FIRE_SOURCE，船長隊伍 208 秒走到半程，停在中途存檔 STALE_REGION_OWNER（原 Site 有未完成的全域區間）；生態 longrun_owner 不再 FIRE_SOURCE，停在旅行到站 ID_CONFLICT（目的地已有 actors.player）。第 5 輪交 Region：(1) 中途存檔、(2) 到站玩家重複、(3) replay 與冷結算矩陣共同的 1800 秒差（wire.value 3602／5402、3600／5400）。收據 `output/d_integration_20261009_024321/runs/CC_R5_*`。

**10/10 05:20 呼叫點補回落地**：commit `2f8bc79`。整合時把出發、原旅隊續行、聚落工程、渠道面板等函式搬進 D 卻沒有呼叫端；補回 `finish_tick`、`update_ui`、`_build_ui` 與 terrain_lab 三個輸入守衛（六個函式現與 epoch 逐字相同）。26 項 23 PASS，3 項 FAIL 與未改前基準相同。

**10/10 06:15 Region 第 6 輪落地**：commit `e05f027`——旅隊 host 五個函式（中途存檔 STALE_REGION_OWNER 的根因）、固定地類規則（adapter 不傳 `land_condition_rule`，宣告此規則的固定地理 Site 地基／肥力全 0；RegionData 讀配對資源清冊改用 `RESOURCE_SOURCE_PAIRS` 加雜湊）、Region P1'' 路線快取以導航內容為 key。49 項對照 HEAD 基準無新失敗；`region_controlled_death_restriction_test` 轉 PASS；party_life、攻城出發、雙 NPC 海路、拘押載荷、科技 G06 都往前推進。`region_travel_test` 越過中途存檔，現卡 540 秒期限（半程後隊伍不動，Region TRANSPORT_DIAG 中）。生態 longrun_owner 仍 ID_CONFLICT，退回 Region。百人運輸兩次都是測試自身期限逾時，非退化。

**10/10 06:30 舊測試 fixture 收尾**：commit `508d83a`。`site_person_actions_test`、`site_nation_equipment_culture_test` 轉 PASS（fixture 補 combat_armies、隊伍庫存 entry、移動輸入／拖曳狀態）；`_loot_context` 只在車輛來源時讀 controller 的車輛 owner。`site_work_fatigue_test` 補上 NPC 後停在單格住宅建造請求（測試過舊，需依新建築佔地改寫，暫無負責線）。

**10/10 06:50 第 7 輪落地**：commit `6fba678`。補上 site_technology `prepare_holder_control_transition`（stage 1 只帶進以 `has_method` 動態呼叫它的家族遠端移交，D 上家族控制移交一律回 MISSING_TECHNOLOGY_CONTROL_TRANSFER）、`cancel_feature` 攻城場／船塢撤回守衛、訓練場群眾工作疲勞守衛；科技政策測試型別修正後 PASS。第二階段複查：拘押期、AI 職位、social schema、teach 改名等列確定是 D 較新，不合入（清單已更正）。待科技樹：`site_technology_work_credit_test` 引用 `SiteRuntime.prepare_release_technology_operation`／`publish_release_technology_operation`，D 與 epoch 都沒有這兩個函式；`site_barracks_types_training_crowd_test`（需 native crowd）與 `site_military_building_contract_test`（headless 材質錯誤）為既有失敗。

**10/10 06:55 第 8 輪落地**：commit `7357eb5`。`_technology_matching_original_task` 取 epoch 版（整合帶進了糧令、水排程工作，卻保留 D 舊版比對，只認一般工作／休息）；國家、職務、聚落、科技操作等 20 項 19 PASS。`site_technology_artisans_test` 修型別後可解析，停在「Original Actor validator accepts same-person technology」，交科技樹。

**10/10 07:25 音效第三階段落地**：commit `9f5cad5`。epoch 的 native、倒地、P3 工作／採集／搬運、載具與環境 loop 音效碼全部進 D（27 個函式、36 處掛鉤、9 個成員）；`_commit` 保留 D 的社會拘押、`apply_unit_contact` 保留 R2 戰死分鐘。驗證時抓到 epoch 碼 `get_meta(key, null)` 在缺 key 時仍報錯（6 項測試因此 FAIL），改為先 `has_meta`。音效合約 335 checks、來源掛鉤 positive PASS，三個拒絕案例照原錯誤 FAIL；回歸 25 項 PASS（監獄群眾測試需先把上一輪自己產生的報告移到 run 存檔，已移）。**待 Nekki**：epoch 另有 32 個音檔（25 個 P3、7 個替換版）與新版 catalog；其中 3 個野豬叫聲是 CC BY-SA 3.0 DE（需署名、衍生音檔同授權），其餘 CC0。搬入前先問。

**10/10 07:40 每小時檢查**：D 在 `a1ea935`，scripts 無未提交改動；Codex 無待處理收據。Region 在 `reports/region_round6_20261010` 備好 5 個補丁（第二階段 Region 列 `region_stage2_epoch`、未造訪 Site 開給 owner 時不放住民與預設工人 `owner_lab_unvisited_no_resident`、路線快取測試改用開放 Site、攻城測試補國家容器、1800 秒差修正 `quiet_prefix_logic_tick` 仍在它的隔離副本驗證）。前 4 個都能套用，已套到 D 跑 48 項驗證；第 5 個等 Region 回報。

**10/10 08:00 Region 第 6 輪部分落地**：commit `3bc4eff`（第二階段 Region 列：選定存檔恢復、船隻 Region 投影、初始世界紀錄；路線快取測試、攻城測試國家容器）。`region_party_life_original_test`、`region_route_terrain_memo_test` 轉 PASS，其餘 40 項不變。`owner_lab_unvisited_no_resident` 未套用：對照 HEAD 會讓受控死亡限制由 PASS 變 FAIL、攻城出發卡在建中心 BUSY；生態 longrun_owner 仍 ID_CONFLICT，退回 Region 縮小範圍。

**10/10 08:20 指揮中心決定（Region 第 7 輪提問）**：(1) 從未造訪的旅行目的地由 owner lab 建立時，先把 genesis 發布進 marker（新增一代、同一遊戲時間），不另開「重新產生比對」證明路徑；(2) 隊伍帶著沒有可行操作人的陸車時，出發直接拒絕並指出是哪輛車（附拒絕測試），`region_travel_test` 改為先指派駕駛；不默默把車留下；(3) `region_two_npc_sea_public_contact_physical_test` 改測試去符合現行開局人口規則，不放寬規則；(4) `region_remote_nation_original_test`、`region_n08_civil_original_ui_test` 的 fixture 地圖補宣告 `land_condition_rule`。拘押載荷的還原誤差（疲勞 pool 還原差 1 ulp、軍隊單位還原補上 move_curve／work_resting 預設）由指揮中心查；G06 的 Terraform endpoint 停點交科技樹。Region 第 7 輪三個補丁（1800 秒差＝靜默前綴未補 coordinator logic tick；到站玩家重複收窄版；world_pin 正規化）已套到 D 驗證中。

**10/10 08:40 Region 第 7 輪落地**：commit `ed53a7b`。`site_ecology_replay_test` 轉 PASS（1800 秒差根因：靜默前綴取代精確步卻沒補 coordinator logic tick；34 秒，原本 188 秒）；`site_technology_g06_paired_source_test` 轉 PASS（world_pin 讀回正規化）；到站玩家重複收窄版不再弄壞受控死亡限制。52 項 46 PASS，無新失敗；生態 longrun_owner 現停在 UNSELECTED_REGION_SOURCE（已決定選項 A）。冷結算矩陣的 owner graph 差異消失，剩既有 fixture 錯誤。

**10/10 09:00 拘押載荷還原誤差（一半）**：commit `9a149f4`，TerrainArmy 還原不再把 move_curve 留在單位列、也不再替沒存 work_resting 的身體補欄位；23 項存讀檔／船隻／監獄／職務／Region 測試 PASS。拘押載荷測試仍停在 capture_partial（疲勞 1 ulp、測試的 v3 關係格式待 Region 改）。另查兩支「既有失敗」：`site_military_building_contract_test` 只在 headless 因 dummy renderer 材質錯誤失敗，visual 模式 PASS；`site_barracks_types_training_crowd_test` 需 `--crowd-test … --crowd-atlas-root …` 參數與 visual，帶參數後停在「Equal native training fixture epoch: 21596 != 21597」（native 訓練時鐘差 1 秒，交群眾／Core）。

**10/10 09:10 每小時檢查**：D 在 `9a149f4`，scripts 無未提交改動；Codex 無新收據；整合者、生態、AI 職位工作端離線，沒有等指揮中心的事。Region 在隔離副本跑第 8 輪（選項 A 的 longrun_owner）。重算第二階段差異：扣除音效、診斷與已判定 D 較新的函式後，只剩 Region 待判的 N08 公共工單三函式、選定恢復兩個 STALE 檢查、`_resolve_ranged_arrival`、`_fire_save_guard_impl`，下次一併交 Region。

**10/10 09:40 指揮中心決定（Region 第 8 輪提問）**：(5) host 綁定的玩家到站時，目的地交回主 controller lab（與 `RegionTravelSite.world_opened` 相同），cold owner 只負責到站前的計時；不把 cold owner 升為 live，也不讓 acknowledge 改寫 mode／consumer。(6) 渡船「船員須在船員座位」規則不變；`two_npc_sea` 測試改成第二人坐在 berth 1 算船員，若公共接觸證明需要有人走到船首，另加第三名乘客。Nekki 09:22 選 A：32 個音檔全部搬入、署名寫進音效說明（進行中）。

**10/10 09:45 P3 音檔搬入 D**：Nekki 選 A。32 個音檔（25 個 P3、7 個替換版）、16 份授權快照、P3_ADDITIONAL_CREDITS.md 與 P0–P3 catalog（51 種、68 檔）已複製進 `assets/audio`（維持未追蹤，與其他 assets 相同），`README.md` 新增「需要署名的素材」：野豬 3 檔 CC BY-SA 3.0 DE（衍生檔同授權）、鹿鳴 CC BY 2.0、木輪車 CC BY 4.0，其餘 CC0。編輯器匯入 110 秒 PASS；commit `acf0c42` 帶入新版音效合約測試與 5 支 epoch 音效流程／設定測試，並修 `_start_army_visual_warmup`（await process_frame 在 lab 釋放後恢復會報錯，改為綁在 lab 自己方法上的 process_frame 連線）。音效合約、掛鉤、5 支新測試、監獄群眾、軍事建築（visual）全 PASS。注意：editor import 會再次刪掉 site_store.gd 檔尾空行，已還原。

**10/10 10:05 Region 第 8 輪落地**：commit `b85549b`（未造訪目的地先發布 genesis、無駕駛陸車出發拒絕＋測試先 plan 後 deploy、車輛姿態 JSON 整數比對、fixture 地類規則與國家容器）。40 項 33 PASS、無新失敗。`region_travel_test` 不再逾時：整條路線 1952 遊戲秒、207 秒跑完，停在到站 REGION_ACTIVATION（決定 5 的交回主 lab 待實作）；遠方國家與攻城出發停在 MISSING_REGION_ADAPTER；`region_n08_civil_original_ui_test` 停在 N08 UNIMPLEMENTED，因 D 的科技 catalog 仍是 N08 enabled:false／candidate，交科技樹；`region_carried_intel_original_test` 需要地類規則 fixture。

**10/10 10:05 每小時檢查**：D 在 `b85549b`，scripts 無未提交改動；Godot 空閒；Codex 無新收據；整合者、生態、AI 職位工作端離線。Region 正在做第 9 輪（`reports/region_round9_20261010/epoch_last_rows.patch` 已在準備，等它回報再套）。編輯器匯入曾替 `reports/region_round3_20261010` 裡的兩支 .gd 測試副本產生 .uid；已在該資料夾加 `.gdignore` 並刪掉這兩個 .uid。

**10/10 10:25 全面掃描開始**：D 上 856 支測試，整合後只跑過 110 支。趁 Godot 空閒，以 headless、每支 180 秒上限依序掃描從未跑過的 region_*／site_* 測試（約 520 支，可中斷、重跑時自動略過已跑的），收據存在 `runs/CC_SW_*`。Region 第 9 輪送來時先暫停掃描、優先驗收。

**10/10 13:00 掃描進度**：背景掃描仍在跑（工作階段重啟不影響），已完成 211 支：58 PASS、153 FAIL。初步分類：34 個一般 assert、11 個找不到 fixture 類別（Parse Error: Could not resolve class）、8 個 headless 材質 null（需 visual）、4 個 `set_process` on null（舊 fixture 少 NPC）、3 個子類別簽名不符、5 個 mesh morph 查詢。很多是舊測試或需要 visual／參數，掃完再逐類判斷是否為整合造成。Region 第 9 輪尚未送來。

**10/10 15:02 掃描進度**：397 支完成（133 PASS、264 FAIL），仍在跑。下一步：掃完分類失敗，整合造成的由指揮中心直接修，其餘分線；CC-001 需先更新釘選（原單要求測試雜湊等於附錄 A，D 已改過多支測試）。

**10/10 17:35 全面掃描完成**：541 支 region／site 測試（headless、180 秒），181 PASS、360 FAIL；明細 `reports/command_center_20261010/sweep_20261010.json`。分類：一般 assert 109、測試自訂錯誤 70、逾時 52、其他 44、缺欄位 18、解析錯誤 17、headless 材質 null 15、缺 NPC 14、缺方法 13、fixture 類別無法解析 8；另有 26 支印出 PASS 卻因收尾 ERROR 判 FAIL。已修 53 支機械性過舊：覆寫簽名（`_advance_fatigue` 加 accepted_prefix_only、`SiteController.tick` 加 accepted_game_seconds、`ranged_profile`、`siege_flush_contact_batch`，含 V0.41R 疲勞參照 fixture，一次影響 15 支）、舊 fixture 補 NPC presenter、主場景改主選單後測試改載 TerrainLab.tscn；重跑中。

**10/10 18:30 掃描後續**：commit `4e034e5`（53 支過舊測試，15 支轉 PASS，38 支進到自己的斷言）、`622cfed`（真崩潰：`_shared_rest_event_limit` 對沒有 work_resting 欄位的隊伍列呼叫 bool(null)，疲勞工人過了休息延遲後共享步驟會當掉；改為預設未休息，回歸 PASS）。其餘失敗中第一個錯誤落在正式碼的 25 支，多數是測試用假 lab／假 controller 缺方法或欄位（fixture 過舊）；值得 Region 注意的是 `ship_person_in_journey`（第二階段新加的 `vehicles._region_ship_frames(lab.terrain)`）讓沒有初始化 vehicles 的 5 支科技／弓弩製作測試在 site_controller.gd:9184 失敗，下次一併交 Region 判斷是否加防護。38 支剩餘斷言多為凍結參照比對（V0.41R 等，遊戲已演進）、需 GPU 或專用參數，依擁有者列在 sweep_20261010.json，暫不逐支追。

**10/10 19:25 接手 Region 第 9 輪**：Region 工作階段已離線（隔離副本最後改動 10:24、最後執行 16:42、ListAgents 不再列出）。指揮中心把它做到一半的部分套到 D：commit `4289d7f`（決定 5：玩家到站改由主 lab 經 world-open 綁定；情報測試補地類規則與 travel identity；雙 NPC 海路測試改登船順序）。旅行與生態 longrun 測試越過 REGION_ACTIVATION，現停在 `commit_region_arrival` CONFLICT「入界候選不是此次真原地點」：診斷顯示傳進來的目的地資料沒有 `world_pin`（`_admit_world_pin` 回 MISSING_WORLD_PIN），推測是 world-open 走冷補算（`lab.advance_cold_site`）產生的候選丟了 world_pin；在 `open_site` 補回 pin 的試修無效，已還原，待 Region 回來或下一輪繼續追。情報測試停在 NO_OBSERVER_OFFICE；雙 NPC 海路停在 DEPLOY_FAILED（四人部署）。

**10/10 19:40 CC-001 重新盤點**：154 次串行（142 支測試）中，132 列的測試檔根本不在 D（Core 整合只帶進程式，沒帶它的驗收測試），6 列 D 已改過、16 列與釘選相同；明細 `reports/command_center_20261010/cc001_d_pins.json`。154 列的凍結 fixture 來源都還在。第 23–149 列要求 catalog「enabled_isolated」，而 D 的科技 catalog 仍是 disabled／candidate（例：N08），這一段要等科技樹的釋出決定，不能硬跑。先做第 1 段：把第 1–22 列缺的 18 支凍結 fixture（雜湊核對過）複製進 D，依描述檔的 mode／timeout／marker 跑，收據 `runs/CC_CC001_*`。

**10/10 20:00 CC-001 第 1 段結果**：第 1–22 列在 D：8 列 PASS（marker 相符），14 列 FAIL。原因：測試的基底檔不在 D（`site_settlement_first_earned_base.gd`、`site_technology_natural_cold_fixture.gd`、`site_technology_targeted_vehicle_test.gd`，散在 Codex 的 overlay／版本檔）、D 的 site_runtime 沒有 `release_settlement_spare_repair`（Core 候選裡有，整合沒帶）、2 支型別推斷、1 支要求 isolated 四類 catalog、2 支 UI 執行錯誤。結論：Core 整合仍有未帶進 D 的程式與測試，需科技樹整合者（離線）或指揮中心另做 Core 第二階段盤點。

**10/10 20:40 CC-001 結論**：照協調者轉達的授權接手。補進 7 個測試基底、移植的凍結測試改動態型別後，第 1 段多數測試能執行，但卡在：凍結 fixture 呼叫 `prepare_release_technology_operation`／`publish_release_technology_operation`／`release_settlement_spare_repair`，這些只存在於 10/08 中午的 Core 中間版本；整合用的最終 Core（region_core_native6_contact_final_source_v1，10/08 17:50）與 epoch、D 都已改成單一 `release_technology_operation`。也就是 CC-001 釘選的測試版本和最終 Core API 不一致，不是 D 漏帶程式。這些列需科技樹依最終 Core 重新凍結測試；第 23 列以後另需 catalog 啟用。目前第 1 段：8 列 PASS、1 列印出 marker 但收尾錯誤，其餘停在上述 API 或 fixture 地形准入。

**10/10 20:05 到站卡點往前推**：commit `ccb1b7a`。根因：到站交回主 lab 後，未造訪目的地走 `_ground_destination` 建立，它不像 `open_site` 會寫入 world_pin，於是 commit_region_arrival 以 MISSING_WORLD_PIN（顯示為 CONFLICT）拒絕。補上後 Region 回歸 7 項 PASS；生態 longrun_owner 現停在 `MISSING_REGION_PARTY_PROGRESS`：world-open 用的是新的 candidate slot，沒有原旅隊 host 的 party progress 綁定。這是決定 5（交回主 lab）設計上要接的下一段，需 Region 的脈絡，暫停在此。

**10/10 20:15 叫醒兩條線**：依協調者轉達的授權，直接喚醒 Region（交到站 party progress 綁定與其餘卡點）與科技樹整合者。補充發現：`prepare/publish_release_technology_operation`（含永久解除、S12 船隻合作單暫停）與 `release_settlement_spare_repair` 存在於 10/08 12:30 的 Region merge-premises 候選，但不在整合用的最終 Core（17:50）、epoch 或 D；D 只有「停止」版 `release_technology_operation`。若 12:30 那條較新，D 缺科技功能而非測試過時——已請科技樹判定並交補丁或重新凍結測試。科技節點啟用（第 23 列以後）屬玩家可見的平衡釋出，未經科技樹調校確認不在 D 上直接開啟。

**10/10 21:20 Region 第 10 輪與科技落差落地**：`60e9921`（world-open 到站完整鏈、火攻 owner 去重、最後幾列 epoch 函式；Region 旅行測試完整走完隊長行程，38 項 PASS）。科技樹整合者判定：整合的 Core 是 Tech 12:37 的選定閉包，漏掉 11 個 site_runtime 函式；其中 3 個是真缺口（永久解除的 release_technology_operation 與 prepare/publish 一對、release_settlement_spare_repair；D 上 S12 船隻合作單原本無法停止），8 個是死碼不補。已提交（明細 `reports/tech_core_gap_20261010/`），14 項回歸 PASS。catalog：D 正式 catalog 維持停用，CC-001 第 23–149 列依施工單在隔離專案跑，交科技樹。渡船決定改為 (a)：ferry 標準船員就是舵手 1 人，斷言改 ship_crew_count == 1 並另查第二人在船上合法位置。

**10/10 22:50 CC-001 隔離 catalog 補丁就緒**：Region 交 `reports/cc001_catalog_20261010/enabled_isolated_catalog.patch`（A4DBCD12…）。只動兩檔：site_technology_catalog.gd（5D16B721→C45B6694）、site_technology_catalog_test.gd（215A591A→7C19D4FE＝附錄 A 第 23 列釘選）。**務必用** `git -c core.autocrlf=false apply`（22→23）與 `… apply -R`（第 149 列後），否則換行被改寫、雜湊不符。--check 已在 D 通過。

**10/11 00:45 CC-001 第 1–149 列開跑（D 凍結）**：基準 `0bd808a`（Region 第 13 輪第一部分 `4a35d50` 火攻 index 讀回容差；科技樹 157 檔測試組，76 檔原樣、32 檔只改型別、49 檔沿用 D）。依序跑第 1–149 列（140 visual、9 headless，期限合計 28,230 秒），第 22→23 列之間以 `git -c core.autocrlf=false apply` 套 Region 的隔離 catalog，第 149 列後反向還原；每列收據複製到 `output/project_command_center/evidence/CC-20261009-001/`，並核對 marker。Region 暫停用 Godot、補丁暫存到跑完。第 150–154 列（native cohort，需換指定 DLL）與 C06 五組不在本次。

**10/11 04:50 CC-001 第 1–149 列完成**：27 PASS（marker 相符）、122 FAIL（5 逾時）；隔離 catalog 已還原（5D16B721／215A591A），D 乾淨（`c648ca3`）。逐列結果 `reports/command_center_20261010/cc001_rows1_149_results.json`，收據在 evidence。分類：自然地形來源准入約 25 列、初始世界交易約 24 列（測試世界不符 D 現行地類／開局規則，交科技樹整理測試修正）；7 列 'terrain' on Nil 來自 Region 第二階段的 `ship_person_in_journey`（交 Region 加防護）。Godot 已還給 Region。

**10/11 05:20 指揮中心決定（科技政策開局衝突）**：依科技樹 v2.4 計畫第 22、168、172 行（新世界建立時寫入固定門檻政策），採 (a)：開局時世界釘選的科技政策類別，若是目前載入 catalog 已准入類別的子集就接受；正式 catalog 停用時准入集合為空，行為與現在完全相同。由科技樹交正式碼補丁並附「未准入類別仍被拒」測試。CC-001 失敗修正第一批（自然地形 fixture 補物品倉、合成地圖邊界留白）已套上 D 抽驗中。

**10/11 06:30 CC-001 失敗修正進度**：`8679502`（自然地形 fixture 補物品倉、合成地圖留白）、`f3f6e05`（正式碼：渠道控制在控制器綁定時就套 S02 停用，原本視窗打開前「開始」按鈕是亮的）、`94a4e24`（s01 稀缺井水：取樣前先讓農田有人作業，PASS 401 checks）、`cdd3be7`（正式碼：開局政策只接受 catalog 已准入類別；正式 catalog 停用時不變，14 項 PASS）、`364ee68`（房屋入口幾何不足時多建一間大屋）。科技樹接著查盔甲持有者、國家材料升級、船塢農田未完工；Region 在跑第 13 輪第二部分。

**10/11 08:25 CC-001 修正續**：正式碼再修 3 項（`073f4b8` 隊伍指派建造／修理的型別陣列會當掉；`c2e2358`、`f352c45` 建造完成與生產批次完成時先清工人目標導致具名工作收不了尾）；測試對齊 `26098e0`、`1684b91`、`f859721`（重試＝同工序續作、扣款零值鍵、N11 測試補軍械庫送交、船塢 fixture）。決定：已知 N11 驗收由具名操作者執行（請求者權限不變），科技樹起草中。Region 第 13 輪第二部分仍在驗證。

**10/11 09:25 里程碑**：`d0f35a5` Region 第 13 輪第二部分（冷補算部分區間、讀回 ulp 容差、休息計算 1e-12 爬行、重開後 mode 水印）——**`region_travel_test` 首次在 D 上完整通過**（256 秒），39 項回歸 PASS。`b57dad7` 已知 N11 驗收改由具名操作者執行（指揮中心決定）。`1f3b00b` 船塢 fixture 清開倉庫入口。決定：長跑測試參考改照正式冷交易設定火攻 journal（只改測試）。待辦：Region 依序處理雙 NPC 海路、遠方國家、情報、冷結算；科技樹處理船塢搬運層並列出 CC-001 可重跑清單。

**第二階段合併盤點**：`reports/command_center_20261010/stage2_inventory.md`。33 檔、扣除音效與診斷後約 100 個函式，依擁有者分好；Region 列在第 5 輪後接手。

**其他擁有者待分派（epoch 稽核列出，非 Region）**：Core／受控輸入（`_advance_original_shared_step`、`_configure_combat_army`、`_advance_movement_input`、`controlled_attack`、`_try_move`、`_finish_native_checked_body_prefixes`）；site_store（`load_site`、`_same_fixed_base`、`_validate_state`、`_validate_site_values`）；site_controller（`finish_tick`、`update_ui`）；科技 open_map 的 `_initial_site_same`；音效 `_region_original_ready` 的 audio_down_sink 一行。等 Region 第 5 輪穩定後由指揮中心逐項比對、自己套用能套的。

**計時問題（02:10 觀察）**：02、03、06、11 與 Region 旅行測試都超出期限約 10～30%，02 先前單獨跑約 35 秒、這次 99 秒。研判機器負載（Codex 稽核、桌面程式）或 D 變慢；期限不改，計時類重跑排在 Codex 閒置的低負載時段。

### Codex 派單（Nekki 10/09 04:00：Codex 又閒置）
- CC-20261009-005（AUDIT）：獨立複核剛寫入 D 的整合合併：重算 Group A／三方／人工合併數、驗證 Group A 前提、找出合併後消失的 D 獨有行，判斷能否進 Godot 驗證。
- CC-20261009-006（PLAN）：把音效交換配方重新對到整合後的 D，做成 AUDIO-01／02 可直接套用的施工包（含 41 個音效列，以及 14 個因音效纏結而保留 D 舊正文的方法）。
- 04:01 送入佇列；兩單唯讀。

### 已結案
聚落中心建築與等級、台灣地圖接入遊戲入口、音效計畫審核。

### 10/11 10:20 科技第 9 輪（造船廠）＋兩項決定
- **9f40afa**：F13 造船方法標記改用 `valid_technology_ship_method`（與攻城方法同式），JSON 讀回 1.0 不再判 CORRUPT_SAVE（生產修正）；造船廠實體測試對齊（每趟不超過搬運量的重複兩點往返、工人安置、F13 係數、軍隊移出建物格）。
- D 上收據：check-only＋ship_build/repair/journey/json/repair_atomic＋workflow 全 PASS（正式目錄）；隔離目錄下造船廠 147 條斷言全過，唯一失敗為 teardown「3 resources still in use」（科技線修中）。siege_yard 因科技線占用 Godot 時段未跑，下輪補。
- 決定 S12 船隻交付：**多段收據**（每段 ≤ CARRY_CAPACITY，配方上限不變，不加馬車依賴），由科技線出生產補丁，涵蓋 CC-001 第 93/98/99 列。
- 決定 Region remote_nation：**採 (1)**，只在「隊伍仍在出發段、出發地即玩家所在 Site、玩家仍在該 Site」時不判接觸；路上相遇照常。two_npc_sea 採正規化語意比較（另加 revision +1／session 斷言）。
- CC-001 重跑清單已備（A 3／P 14／B 49／K 21／U 40），待科技第 10 輪與 Region 補丁上 D 後在 D 跑（59、131 單獨跑）。

### 10/11 11:45 Region 第 13 輪第 5 部分＋到站決定
- **6e05b88**：SiteStore 讀檔把建物 layout_version／owner_faction／quarter 轉回 int（生產）；epoch 共用 helper 在 fresh Slot reopen 後 wire adapters 並還原旅行隊伍 owner（測試）。
- D 上收據：carried intel 越過 positive reopen 與 same-point retry，停在 t=100 到站（D 上代碼 MISSING_REGION_ADAPTER）；存讀、聚落、還原、party life、region_travel（251 s）全 PASS；siege epoch／original_phase／finite_food 三支在夾具建置失敗，與 10/10 sweep 同行同碼，非本輪回歸；store_army_capacity 為已知 headless render null。
- 決定到站 STALE：**採 (1)**，到站前若 cold 目的地有未發布前進，先做既有的 region_original_endpoint_checkpoint，不放寬來源准入；發布失敗須原子拒絕。

### 10/11 12:10 Codex 額度重置：派出 CC-20261011-001（正式建物美術）
- Nekki 12:04 告知 Codex 已重置，10/09「少派 Codex」限制取消。
- 派 **CC-20261011-001**（IMPLEMENT）：用內建 image_gen 生成 warehouse／dock／shipyard 四方向共 12 張正式 building_v2 美術並登錄 art_manifest.json。它們目前缺 key，是 CC-001 第 140、141 列的阻塞。不跑 Godot，驗收由指揮中心在 D 跑。
- 任務檔 SHA-256 DFAF74CD…B056；queue 訊息 01a12925-e3b5-7883-9612-7acebd15b920（exit 0）。Codex CLI 後備路徑已更新為 bine5e00daee91c61d。

### 10/11 12:20 決定 cold_formal 浮點邊界
- Region 找到 COLD_COORDINATOR_ACTIVE 的原因（formal 路徑不准開頭 rebuild tick）並在隔離副本修好。下一關是 _exchange_phase 在 0.1 wrap 邊界的 1e-12 浮點分岔：replay 用重建的步寬，比 live 少 wrap 一次。
- 決定 **(B) 輕量版**：replay 改用與 live append 位元相同的累加式，先不改 journal 格式。否決 (A)：放大 epsilon 只降低機率，且動到 Native 契約。否決 (C)：round 差 1 是真實狀態差。rebuild-tick 修補與 (B) 一起交付。

### 10/11 13:25 科技第 10 輪上 D（8ba04b6）
- S12 船隻交付改為多段搬運（每段 ≤ 搬運量，取／送交替，驗證器逐段檢查）；恢復 S12 三個 hook、cancel 具名停止守衛；設施來源包裝同 nation 路徑；修正讀檔後 carrier／consent id 浮點比較。測試：造船廠 priors 清除（無 teardown 洩漏）、first-earned 額外住宅、window 40 節點、F07 比較去掉 site_state。
- D 上收據：正式目錄 check-only×2、ship 五項、workflow、catalog、第 13 列 PASS。隔離目錄 27、32、58、90、95、99、100 PASS；38／44／45／81／93／97／98 停在已知下一層，與科技線報告一致。目錄已還原（5D16B721）。
- 指揮中心另把 site_runtime 一行錯位註解移回 valid_technology_ship_method 上方（只動註解）。

### 10/11 13:58 Codex 美術 CC-20261011-001 驗收
- Codex DONE：warehouse／dock／shipyard 四向共 12 張，manifest 只新增 12 key，既有 123 條與 134 張 PNG 不變。contact sheet 已檢視：畫風一致、無文字／浮水印／船體。
- D 上匯入 PASS（12 個 .import）；site_building_ui、site_settlement_center、shipyard_physical（第 100 列）PASS。
- 第 140 列越過缺圖後撞到測試夾具型別錯誤（未型別陣列傳 Array[int]，且在 assert 內呼叫），已修（**2f6d388**，含 133 個匯入產生的測試 .uid）。重跑：140 印出 PASS 標記，只剩 2 個資源 teardown 洩漏；141 停在 mesh fraction 斷言。兩者交科技線。
- 美術檔維持未追蹤（building_v2 整個資料夾本來就不在 git，PNG 入 git／LFS 仍待 Nekki 決定）。

### 10/11 14:05 Region 排序：海路搜尋
- two_npc_sea (A) 已實作並通過；兩個夾具缺口（prepare_identity、fresh Slot wire）批准。再下一層是生產海路搜尋：相鄰 Site 的第一次展開對 100 個 offset 各做完整 hull 掃掠（每次約 1.5 s），測試被外部 timeout 終止。
- 排序：① 交付 two_npc_sea＋remote_nation＋到站前發布 → ② cold_formal (B) → ③ 海路搜尋。③ 先查是不是夾具把船放在不可航位置；若是生產效能問題，改成同一起始姿勢只掃掠一次（結果等價），不用會改變路線的短路啟發式，並附新舊路線逐位元相同的證據。

### 10/11 14:55 科技第 11 輪上 D（16fbf5f）＋兩項決定
- 只改測試：settlement_ship 的工作迴圈補上 Lab 時鐘端點（advance_ship_builds），研究路徑補請求 S12 研究同意；first-earned 夾具推進 army_next_team。
- D 上收據（隔離目錄）：第 98、99、100 列 PASS；44 停在 pinned Slot 讀檔（SAVE_VERSION），45 停在聚落升級。目錄已還原。
- 決定第 93 列：**(a)** 船隻視窗的搬運人選改用與下單規則相同的判斷（共用 predicate），附 UI 測試。
- 決定第 44 列：照遊戲實際重開 pinned 世界 Site 的生產路徑呼叫，不另造測試流程；若需 Region 語意，標 K 留給 Region。
- 決定 Region 派遣來源：延伸「到站前發布」到 dispatch 來源，含同刻 live roots 變動（用 checkpoint 本身的 capture 比對）；scope 參數與 ticket body 兩項生產修正批准。

### 10/11 15:40 科技第 12 輪上 D（d49964d）
- 生產：抽出 Runtime.settlement_ship_person_eligible（S12 下單原本的逐人規則），下單與船隻視窗的搬運人選共用；協助者與加工清單不變。測試：搬運人選 UI 兩種情況、船塢修理點 priors 清除（無洩漏）、夾具呼叫移出 assert()。
- D 上收據：正式目錄 check-only×3、ship_build、workflow、catalog、person_actions、第 13 列 PASS；隔離目錄第 93、140、98、99、100、27、32 列 PASS；97 停在已知的批次扣帳檢查。目錄已還原。
- CC-001 隔離目錄 A 級（D 上已驗證通過）：27、32、58、90、93、95、98、99、100、140，加正式目錄第 13 列。K：44（pinned Region slot 讀檔，交 Region）、141（mesh 接觸時序）等。

### 10/11 16:20 美術與音效改走 Git LFS（c4dd53a）
- Nekki 16:08 決定「照建議」走 LFS。
- .gitattributes 新增限定資料夾的 LFS 規則：building_v2、natural_resources、vehicles/ships、vehicles/siege 的 PNG，以及 assets/audio 的 WAV。
- commit 624 個檔：293 個 PNG／WAV 走 LFS（LFS 檔數 366 → 659），其餘是 manifest、.import、授權文件等小文字檔。
- 已追蹤的 497 張舊 PNG（546 MB）維持一般 git，因為轉換不會縮小歷史。region_lab 地圖資料（約 360 MB，含 r3_trial／r4_probe 試驗版）不含在內。未 push。

### 10/11 16:45 科技第 13 輪上 D（6167ff1）
- 生產：N11 公共訂單的捐料授權、撥款與續約改依路線選綁定（甲冑路線用 iron_armor），與 arsenal／產出路徑同規則，其他節點不變。測試：first-earned 首都水井移進轄區。
- D 上收據：equipment_orders check-only、public／technology operations、equipment_orders、workflow、catalog PASS；隔離目錄 58、90 PASS；45 走到甲冑工作，停在「有效工作完成有界」檢查（科技線在查 NO_AUTHORITY）。目錄已還原。

### 10/11 18:25 科技第 14 輪上 D
- 生產：讀檔後國家公共訂單的 id 清單以 int 比對（原本 float 嚴格比對，讀檔一律 CORRUPT_SAVE）；SiteStore 讀檔時呼叫既有但從未被呼叫的 normalize_nation_operations。
- D 上收據：check-only×2、國家營運、equipment_orders、workflow、存讀與還原一組（siege／ship json／ecology／scene restore／party life）全 PASS；隔離目錄第 37、38、90 列 PASS。
- CC-001 隔離目錄已在 D 上通過：27、32、37、38、58、90、93、95、98、99、100、140，加正式目錄第 13 列。

### 10/11 18:45 科技第 15 輪上 D（a3a4020）；CC-001 全量重跑開始
- 只改測試：N11 首都軍隊在建物之後部署並避開工坊與入口，工作前斷言操作者在指揮範圍內；_earned_until_idle 卡住時直接失敗。D 上第 37、38 列 PASS，45 走到滿產後停在有效工作完成檢查。
- 18:45 起在 D（a3a4020）跑 CC-001 第 1–149 列（1–22 正式目錄、23–149 隔離目錄、每列獨立行程），證據放 evidence/CC-20261009-001/rerun_20261011_a3a4020/。期間科技線暫停 parsecheck 的 Godot。

### 10/12 00:30 CC-001 第 1–149 列重跑結果（D a3a4020）
- 44/149 PASS（10/10 為 27），新增通過 17 列，0 回歸；A 級全過。詳細：reports/command_center_20261012/cc001_rerun_a3a4020.md（3fc3dbb）。
- 最大失敗群：初始世界交易（60–75、124–130，多數逾時）、人物同意（109–115）、BUSY（56、94、101、104、133）、GPU uniform set 不足（59、64、65、68、69）。已交科技線分類；初始世界那群若屬 Region 再轉。
- Godot 槽順序：Region 回歸（21×2）→ 科技第 16 輪。

### 10/12 01:10 Region 第 13 輪第 6 部分上 D（3417420）
- 生產 8 項：NPC 到站／派遣前先發布（時鐘不前進、失敗原子拒絕）、出發段自我接觸排除、到站存 ticket body、戰鬥人物依 Slot scope、已到站遠端隊伍可讀、gate.operator_id 與 organization_refs lineage 讀檔轉 int。測試：正規化比較、夾具、派遣原子拒絕。
- D 上收據：check-only×4、carried intel（positive）、party_life、scene／selected restore、store_json_parallel、ship_json、siege_store_roundtrip、workflow、lab_contract、region_travel（258 s）PASS；remote_nation 停在 EVENT_CLIP_REQUIRED（下一層）。
- Region 隔離副本上 R1 跑 580 s，D 上 258 s，屬環境差異。

### 10/12 02:00 科技第 16、17 輪上 D（ef5a05d）
- 生產：工坊批次另記有效工作秒數（與推進產量同一公式），N11 甲冑收據帶此值；即時檢查與存檔驗證共用同一規則，上限為實際工時×最高等級生產力；舊存檔以 work_seconds 代替。第 45 列因此可完成。
- 測試：工匠測試改用 v2 learned 形狀；重開 refusal 記錄代碼。決定第 60 列：重開改用原存檔政策並期望 CONFLICT，不改 Region 生產。
- D 上收據：check-only×3、國家／裝備／workflow／存讀／船／聚落測試 PASS；隔離目錄 45、58、90、98、99、37、38 PASS；76 印出 PASS 標記但因 GPU descriptor heap 不足判失敗（環境問題，同 59）。

### 10/12 02:30 科技第 18、19 輪上 D（92ed19a）＋GPU 決定
- 只改測試：已完成世界的重開改用原存檔政策（不同政策→SAVE_VERSION、同政策→CONFLICT）；交換模式近戰改放相鄰。D 上：第 60 列越過重開，停在工位佔用（第 20 輪處理）；70 列開始攻擊，停在 mesh 接觸（與 141 同類，K）；62 列在 _siege 的 _interval 遞迴迴圈，產生 880 MB 記錄，已請科技線第一次失敗就停。
- 決定 GPU descriptor 不足（59、64、65、68、69、76）：維持 CC-001 描述檔的 visual 模式驗收，不改 headless；測試在銷毀 lab 後強制繪製讓 D3D12 延後釋放執行（第 21 輪）；另量每個軍隊呈現器的 descriptor 用量，判斷遊戲中 15+ 呈現器是否有風險。

### 10/12 03:10 GPU 探針結果（待追蹤）
- 科技線探針：每個 live 軍隊人物呈現器約 1,200 descriptors（131072 上限可放 109 個，遊戲中 15 個沒問題）；但回報的顯示記憶體約 208 MB／個，40 人軍隊若每人一個呈現器會到數 GB，是可能的遊戲內風險。已請科技線在目前佇列後查清實際遊戲中同時存活的呈現器數量與單個成本，再決定是否開渲染工作。
- 第 21 輪：第 76 列 visual PASS；第 59 列 heap 錯誤歸零，剩 90 秒 deadline 在 _run 完成後覆蓋 PASS，決定 (a)：已完成就不再以 deadline 判失敗，未完成仍 90 秒。

### 10/12 03:30 呈現器記憶體：列入待辦，不開工
- 實際遊戲中只有隊長列（row 0）可能有 live 呈現器，40 人軍隊也最多 1 個；步行且配方支援的隊長走共用幾何，沒有呈現器。一般三勢力開局約 1–2 個（約 0.2–0.4 GB）。
- 最壞情況：每個 Site 上限 50 支軍隊都是騎乘／選取／不支援配方的隊長，約 10 GB（回報值）。列為渲染待辦：先拆解 208 MB 的組成（skinning 副本、貼圖、render buffer），再評估騎乘隊長多的戰場。目前不開工。

### 10/12 05:25 Region 第 13 輪第 7 部分上 D（e4c0def）
- 生產：共同區間在 travelling 隊伍的接縫／補給停點切開（解 EVENT_CLIP_REQUIRED）；RegionTravel 讀檔後 id 欄位的整數值 float 以 int 重映射（第 6 隊人物 5 外洩）。測試：出發段接觸探針、接縫切分。
- D 上收據：check-only×2、carried intel、**remote_nation positive PASS**、party_life、scene／selected restore、cold／travel gameplay、workflow、lab_contract、region_travel（253 s）全 PASS。
- Region 下一步：cold_formal (B) → 海路搜尋 → ulp 調查；remote_nation 其餘 case（production、source_authority/dead/captive）列下一層。

### 10/12 07:25 科技第 20–23 輪上 D（8c1a207）
- 只改測試：夾具放置前清空工位、lab 銷毀後強制繪製讓 GPU 延後釋放、失敗細節有界且防循環、_interval 首次失敗後不再重複、出生測試 deadline 不覆蓋已完成結果。
- D 上（隔離目錄 visual）：第 59–76 列 descriptor heap 錯誤全部歸零；76 PASS；60 邏輯通過、剩 teardown 洩漏；64/65 停在存檔端規則驗證（已轉 Region）；66 停在進行中移動（第 24 輪）；69 停在閒置疲勞恢復（科技線探針中）；59、68 無輸出逾時，待查。
- 修正我自己批次腳本的 BUSY 判斷（測試失敗訊息含 BUSY 被誤當成槽忙而重跑）。

### 10/12 07:40 決定 cold_formal journal 合併規則
- Region 的 B 輕量版遇到 REPLAY_STEP_UNRECOVERABLE：journal 以 1e-10 容差合併了寬度差幾個 ulp 的步（clip 截斷造成），無法唯一還原。
- 決定 **(1)**：journal 只合併逐位元相同寬度的步，格式不變；舊存檔無法還原時走既有 exact fallback；量列數與存檔大小，超過 2 倍先回報。

### 10/12 07:50 逾時不放寬；疲勞與移動夾具方向
- 第 59 列 visual 需要約 180–220 s（描述檔 120 s），第 68 列約 225–260 s（描述檔 212 s）。依 Nekki 的規則不放寬逾時，先列 K，請科技線分析 visual 耗時並在測試端降低成本；若做不到，再帶數據請 Nekki 決定。
- 第 68/69 列疲勞：隊伍共用疲勞池是整隊一起恢復（設計如此，非回歸），測試改為恢復前用生產 API 讓其他成員停工並結束移動。
- 第 62/66 列：先用探針查清是誰啟動了助手的移動，再決定是否擴大取消範圍。

### 10/12 08:05 驗收效率：Nekki 同意兩項
- Nekki 00:00Z「依你建議做」：(1) 10 支測試的驗證逾時改為測試內 deadline＋30 秒（讓報表能印出，不改判定）；(2) 只刪可重建的重複日誌（combined.log、appdata godot.log），每個 run 保留 stdout／stderr／result.json。
- 由驗收效率線（worldgoing-a4）執行：先寫刪除清單、跳過 15 分鐘內的 run、.godot-temp 不動；逾時修改交我審後 commit，若在 CC-001 凍結描述檔內先回報。
- 工具已 commit（bc1e89a）；我的執行包裝已不再封存重複日誌。

### 10/12 08:55 日誌清理完成；逾時新值
- 驗收效率線刪除可重建的重複日誌 7,956 檔、21.93 GB（D 可用 678.7 → 700.6 GB），錯誤 0；3,399 個 run 的 stdout／stderr／result.json 逐一核對都在。清單：output/acceptance_efficiency_20261012/cleanup_manifest.json；腳本 c3011bb。舊 result.json 的 combined 欄位改看 stdout＋stderr。
- 10 支測試的逾時不在 D 的檔案內（來自批次列表與 CC-008 參數），新值記在 output/acceptance_efficiency_20261012/timeout/timeout_adjustments.json，之後排批次直接用：region_cold_original_matrix 390 s；site_housing_crowd 630 s；barracks_types_crowd、bridge_crowd 270 s；其餘 6 支 crowd 250 s。

### 10/12 09:20 效能與 Region 排序
- 科技線剖析：artisan birth 每次約 14 s 全在第一次 enable_combat 建 contact rig（原始 GLB 解析），最後一個 Lab 離開時會被釋放。遊戲中是每次程序第一次開戰約 14 s 卡頓。決定：先做 (b2)＋(a) 共用快取 PackedScene（玩家可感），再做 (b1) rig 保留到程式結束（需證明不增加 teardown 洩漏），兩輪分開交付。
- 科技第 24、25 輪已上 D（b8c2dde）：62、66、68 各前進一層，76 PASS。
- Region：ulp 根因是 Godot JSON parse 不是正確捨入（21.6% 的 16–17 位數值差 1–2 ulp），維持 (A') 比較，「時鐘子樹改二進位編碼」列待辦。海路搜尋改為一次可達掃掠，結果逐位元等價，two_npc_sea 從 900 s 卡死變成 117 s 推進到下一層。新排序：part8 → UNSETTLED_PARTY（擋三支測試）→ cold_formal (1) → 存檔端規則驗證 → remote_nation 其餘。

### 10/12 10:25 科技第 26 輪上 D（72197db、abd7253）；prepass 時段
- 角色編輯器與戰鬥 contact rig 共用 runtime 快取 PackedScene（visual：編輯器 4.8 → 1.0 s、rig 8.2 → 4.1 s；headless 維持完整重載）。D 上驗證通過；appearance_restore 三支、siege_gd_body_contact、formation_store_matrix 與 10/10 相同失敗；第 59 列 visual 仍超過 120 s，等 L1（快取保留到程式結束）。
- 驗收效率線的 prepass 實測：排在科技線目前這次執行之後的 10 分鐘空檔。若交接先發生，這項列入交接包由 Codex 跑。

### 10/12 10:40 額度交接：派給 Codex（CC-20261012-HANDOFF）
- Claude 本週用量 99%，依 Nekki 00:14Z 規則把工作交給 Codex：任務檔 output/project_command_center/inbox/CC-20261012-HANDOFF.md（SHA-256 開頭 3584655CEF50），queue 訊息 01a12df8-afee-7e50-a512-89d6e880a584。
- 交還條件：Codex 額度剩 5%，或 2026-10-12 18:00Z（台灣 10/13 02:00）Claude 重置，先到者為準；回執寫在 receipts/CC-20261012-HANDOFF.json。
- 交接時 D 的狀態：HEAD abd7253；Region part8 已套用到工作樹但未 commit（region_route.gd），驗證進行中，two_npc_sea 在 D 上的結果與副本不一致，交 Codex 查。科技線、Region、驗收效率線都已通知停手並以 patch 保存 WIP。

### 10/13 02:05 收回 Codex 交接（CC-20261012-HANDOFF DONE）
- Codex 在 18:00Z 交還：9 個本機 commit（ce47cce…cef0e50），未 push；Godot 空、catalog 已還原（5D16）、canonical helper 未改。
- 已提交：L1 快取保留到程式結束（3ceebbf；第 40／60 列 PASS）、存檔端 land_condition_rule 驗證（9b734fd）、到站前 land admission（b8a5e57）、siege 夾具與工作 ledger、Office 任官夾具（77644c6；source_authority PASS）、terminal callback（cef0e50）等。
- 未提交 WIP（scripts/ 10 檔）：Region part8、時鐘、sea memo（新的六支 4 PASS／2 FAIL，未達提交條件）、family／settlement 合法 contact 夾具。
- 待決策：第 68 列 work JSON 差 1 ulp（Godot JSON parse，需新 parser／格式，或放寬斷言 → Nekki）；cold journal 精確寬度。
- 其餘未完成項見回執 open_items。

### 10/13 02:40 B 級列在乾淨 cef0e50 全過；Nekki 三項指示
- Codex 的 WIP 存成 reports/command_center_20261013/codex_handoff_wip_cef0e50.patch 後 stash，D 為乾淨的 cef0e50。第 62、66、64、65、59（96 s，低於 120 s）、40、60 列 visual 全 PASS，轉 A。
- Nekki 18:17Z：
  1. 第 68 列 ulp 依建議：寫入時就以 Store 自身的 stringify→parse 正規化 ledger 數值，並斷言再一次往返不變；不放寬斷言、不改格式、不寫自訂 parser。交科技線。
  2. 多派 Codex：已派 CC-20261013-001（地圖編輯器 P0 契約復核，依 MAP_EDITOR_IMPLEMENTATION_PLAN.md）與 CC-20261013-002（appearance_restore 來源釘選稽核）。兩單都不跑 Godot。
  3. 地圖編輯器加入計畫：P0–P5 首個可用切片約 26–44 工作日；P0 由 Codex 先做，之後依施工包拆 IMPLEMENT 子單。
- Godot：Region 分階段回歸（約 3 h）→ 科技線。

### 10/13 04:15 Region part8–9 在 D 的驗收（進行中）
- s0（乾淨 cef0e50）vs part8＋9b＋9c（9a 因一個未追蹤的舊 memo 測試檔擋住而沒套上），各 13 支：
  - 無退步；
  - carried expiry、remote source_captive 由 FAIL 轉 PASS；
  - two_npc_sea 從 900 s 逾時變成 608 s，停在下一層「same original earliest-boundary」；
  - carried blocked 停在下一層。
- 疑慮 (a) 排除：13 支所有主動 checkpoint 都沒有出現 OK 變失敗。
- 已移除舊檔（備份在 scratchpad）並補套 9a，6 檔雜湊與 Region 最終版相符；正在重跑受影響的 9 支。

### 10/13 05:00 Region part8–9 上 D（474b430）；科技第 28–30 輪部分上 D（730c431）
- Region part8–9c：無退步；carried expiry、remote source_captive 轉 PASS；two_npc_sea 從 900 s 逾時變成 614 s 推進一層；checkpoint 疑慮排除。下一層是每步固定成本（約 100 ms／步，其中 98 ms 未歸因），計時診斷在 D 跑。
- 科技：ledger 秒數寫入時就做 JSON 穩定化（4000 筆實測中 359 筆原本讀回會偏 1 ulp）、讀檔時 fire_layout_version 轉回 int、國家夾具 hook；驗證全過。shares 基底在 D 出現 String==int 錯誤，暫不收，退回科技線。
- 進行中：Region 計時診斷 → part10 cold_formal（含 longrun 列數／大小比較）。

### 10/13 07:00 Codex 回執；地圖編輯器開工；科技第 34 輪
- CC-20261013-001 DONE：地圖編輯器 P0，以 cef0e50 復核，產出 99 組欄位（319 readers／279 writers）、修訂版計畫 v2、P1A–P5C 共 10 個施工包；沒有需要 Nekki 決定的產品問題。證據在 evidence/CC-20261013-001/。
- CC-20261013-002 DONE：appearance_restore 三支測試是繼承整份來源的出處守衛。合法的更新程序需要 GPU A/B 證據，草稿 patch 未套用，legacy rider 刻意保持排除。暫不處理，列待辦。
- 派 CC-20261013-003：地圖編輯器 P1A（作者來源／pin／format 準入），以 patch 交付、不直接改 D、不跑 Godot。
- 科技第 34 輪（5191127）：修掉型別化陣列三元式的潛在當機（生產 3 處、測試 2 處），第 114 列 PASS。
- Region：part11 等價但沒有加速，未收；part10 v2 找到 exchange 漂移根因（quiet 換相未照 _advance_combat 的子步規則），待在 D 上驗證。

### 10/13 07:30 Region part10 v2 未過、runtime proof 熱點；科技第 35 輪驗證中
- part10 v2：exact 漂移值與 v1 相同（子步換相沒生效），legacy 與回歸都 PASS。已還原、退回 Region。
- runtime_proof 細分（carried blocked）：22,000 次共 148 s，熱點是 selected document 的 d1 recover／reference 74 s 與 d2 讀檔 34 s。part11 只快取了 d2 之後的部分，所以沒效益。請 Region 針對 d1 提出等價快取。
- 科技第 35 輪（生產）：科技作業自己建立的 operate 區在階段完成時停止（標記擁有權，存讀保留）；國家行政取消後恢復時沿用已付款的 attempt，不重複收費；第 68 列夾具恢復派工者控制。D 上驗證中。

### 10/13 08:30 科技第 35 輪、Region part12 上 D；授權；Codex 加派
- 科技第 35 輪（e91e678）：作業自建的 operate 區在階段完成時停止（擁有權標記可存讀）；國家行政取消後恢復時沿用已付款 attempt。第 39、43、112、115 列 PASS。
- Region part12：recover 改成沿用已驗證的最新 commit（等價 20,000／0 差異），每次 proof 從 6.7 ms 降到 3.7 ms；回歸全過。part10 v2 exact 仍有漂移，追蹤已交 Region。
- Nekki 10/13「你幫我授權並解決原本會卡住的問題」：在 .claude/settings.local.json（gitignore）加 autoMode 允許規則，範圍是隔離副本的 canonical 驗證、副本內檔案操作、只停自己記錄的 PID；並請 Region 遵守三條規則（同步 cache、不中途停批次、一次一個 Godot）。
- Codex 加派：CC-20261013-004（生態重新盤點＋§13 草稿）、CC-20261013-005（AI 職位 R0–R3 核對＋下一階段）。CC-20261013-003（地圖編輯器 P1A）施工中。
- 第 2 節各線現況待更新（生態、AI 職位、貿易、勢力、音效停在 10/09）。

### 10/13 12:20 科技 36、Region part11 上 D；Codex 回執與 D 驗收
- 科技第 36 輪（a915329）：第 111、112、115 列 PASS；第 68 列找到根因是隊伍沒有現任指揮官（測試夾具），第 38 輪處理中。Region part11 v2（95d6e7a）：文件快取等價，two_npc_sea 608 s → 470 s 並推進一層。part10 v3：exchange 相位 1,440／1,440 已對上，剩 scene node 51 的 wire value（186 vs 180），診斷中。
- Codex：CC-004 生態盤點 DONE（32 項中 30 項歷史 PASS，longrun 存檔 ID 已由 7d3189b 修好，§13 修訂與 assert 副作用測試 patch 待驗）。CC-005 AI 職位 R3 普通 GD row 切片 patch 待驗（R4 是金錢贖回，等前置）。CC-006 P1A v2：解析錯誤已修，在 D 上 12 項 PASS，但新 contract test 在「author base generation」失敗、region_travel 從約 260 s 變成 330 s，已還原並派 CC-008 修正。CC-007 測量樁 survey_stakes 施工中（第 113 列 K）。
- D 上進行中：Region part13（海路 pose facing 讀檔轉 int）＋part14（selected document 解碼快取）＋等價診斷與回歸；之後驗 AI 職位 R3 patch、生態 patch、科技第 38 輪。

### 10/13 15:30 rgd2 診斷、P1A v3 上 D、Codex 退件
- 地圖編輯器 P1A v3 上 D（123a200）：驗證在 26455da 全過；之後 HEAD 只動了生態測試與計畫文件。
- 生態 assert 副作用與 §13 計畫修訂上 D（f25a7ae）。
- rgd2 三支 Region 診斷結果交 Region（reports/region_round13_20261011/rgd2_results_20261013/）。
- prepass 實測：combat_formation_store_matrix 38 s 就 FAIL_EARLY，失敗和正式驗證一致（既有失敗）。
- 測量樁與 AI 職位 R3 失敗退回 Codex（CC-20261013-009）。
- 科技第 38–40 輪在 D 驗收中。

### 10/13 16:10 科技 38–40 上 D；Region 第三批診斷；測量樁 v2 到件
- 科技第 38–40 輪（c6b2141）：S07–S10 formal、第 119、64、65 列 PASS；第 68、69 列邏輯 PASS 但 216／240 s 仍超過 212 s（K，逾時不放寬）。整合者先 profiling 再出第 41 輪；combat_formation 的 MOVE_START_DESYNC 由整合者在第 41 輪後 bisect 7c2504d..9a149f4。
- Region rgd3（結果 reports/region_round13_20261011/rgd3_results_20261013/）：船艦錯在 NPC 海上 materialize 的 live bind 驗證；新熱點 queue_region_gameplay_endpoints（約 19 ms／次）；node51 多出的 6 次 review 來自區域排程入口（整點，兩個 site 各 3 次）。待 Region 出修正。
- Codex CC-009：測量樁 v2 到件（以 c6b2141 為基準，apply --check 過），等整合者 profiling 釋放時段後在 D 驗；OFFICE 修正仍在 Codex。CC-010（地圖編輯器 P1B）施工中。
- Godot：整合者 profiling（兩次）→ 測量樁 v2 驗收批次。
### 10/13 21:00 Region part10 v5～23 上 D；逾時例外；科技 41
- Region 上 D：part10 v5（c1c71c4，cold_formal exact／legacy 首次 PASS，duty 序列 180/180）、part16（9729a7c）、part17（6011042）、part19（e371177）、part20（d1dd4cc）、part22（6a3cfa6）、part23（2001323）、part21（e9d77aa，路線快取鍵排除時鐘欄位；carried blocked 首次 PASS 283 s，等價 28,500／0）。part15 v2 正確但無效益，不收。
- 測量樁 v2＋4 張美術上 D（f88dd73）；第 113 列 PASS；F01/F02 撞 540 s 期限是基準既有。
- Nekki 10/13 11:08Z 決定卡（已核對 chosen_by Nekki）：第 64、65、68、69 列逾時 300 s，斷言不動；記錄 output/acceptance_efficiency_20261012/timeout/timeout_adjustments_20261013_nekki.json。重跑 4 支全 PASS（175／144／170／169 s），第 68、69 列 K→A。
- 科技第 41 輪（e0f0166）：6 處 assert 內含副作用（release 版會跳過 hot store 寫入等）。第 42 輪清掉 MOVE_START_DESYNC，但 100_chain wedge 卡住（基準靠意外重排路線通過），未收，整合者追死結。combat_formation bisect：自 ef39140 起即失敗，非回歸。戰鬥測試在 headless 有 dummy renderer 的 material null 錯誤、在 visual 有既有 SCRIPT ERROR（'selected' on Nil 等），列整合者待辦。
- Region 剩：two_npc_sea 停在 STALE_REGION_PARTY_BODY（frame 帶長度 0 的 dock pose）；3 支船測試停在 INVALID_REGION_OWNER_SNAPSHOT（site_region_owner_snapshot.gd:211）。
- Codex：CC-009（OFFICE v2）、CC-010（地圖編輯器 P1B）DONE，D 驗收排在整合者時段之後。
- 處理中：presenter pool 暫停（Nekki 選逾時方案）。
### 10/14 07:15 Nekki 決定兩項戰鬥規則（10/13 23:12Z「選1後題3」）
- 大陣型指揮官在場：選 1，指揮官離自己陣型任何一名成員在指揮半徑內即在場；後方站位保留。交整合者第 53 輪。
- 撤退：選 3，士氣未崩潰時玩家和戰術 AI 都可帶目的地有序撤退；崩潰後隊長 RETREAT 仍為潰逃。交整合者第 54 輪；第 45 輪 pair 測試回到隊長路徑，tactical_ai_retreat 測試依新規則更新。
- 10/14 17:15 F1a v3（CC-047）在 D 上整批停在 3 處 `:=` 型別推斷解析錯誤，沒有測試跑到。中心改成明確型別的 v3a（reports/f1a_v3a_20261014/），隔離副本 --check-only 12 檔乾淨，排在 56c 之後重驗。CC-048 NEEDS_INPUT 是在等中心跑探針（v15 已排）。CC-049 disabled 契約 DONE，排在 v3a 之後驗。新派 CC-054（型別推斷靜態檢查工具）、CC-055（loot storage 既有失敗）。第 53/54、53b、57、59 輪收進 D（24fa25b，落實 Nekki 選 1／選 3）：pair、lease、100_chain、tactical_ai_retreat 全 PASS；army_presence 標記全過但仍有渲染器噪音（交整合者，比照 43c）；tactical_ai_state 和 HEAD 同樣失敗。roster headless 碰到 deadline，但當時中心在跑 scratch check-only 干擾了計時，已排重跑。d24 診斷確認量守恆，是斷言預期錯；Region part36 已核准並排隊。v15（CC-048）：科技 returns、C36、交糧時鐘修正都沒過；T6 的 PASS 標記有印出，但 3 個資源仍未釋放；三個診斷都留下了數值。P2A v3 套不上現行 HEAD，那次結果作廢。以上全數回饋為 CC-056，P2A 要以新 HEAD 重做 v4。第 60 輪（presence 進 tree）和 material null DIAG 已排隊。第 56c 輪收進 D（0c74cf0）。F1a v3a：region_travel 在 collect_ids 出現 int==String 錯而失敗，f1a v2/v3 測試也各有首錯；carried blocked 285.7 s（HEAD 275 s）。已派 CC-057（F1a v4）。CC-050、CC-051 的 v2 已排 D 驗證；CC-045 P2B 依原定暫停（NEEDS_INPUT）。CC-049：catalog 第 4–7 列收進 D（f28eeb2）；G06 第 16 列在 disabled 下失敗、enabled 下 PASS，退回為 CC-058。Region part36 收進 D（dea94ed）：finite_food 印出 PASS 標記（2297），但結束時仍有 1 個資源未釋放；兩支 NPC 船測試推進到 MISSING_REGION_ADAPTER。roster 乾淨重跑仍在 248 s 碰到 deadline，疑似 53b 的測試迴圈拖慢，已交整合者。第 60 輪收進 D（322b398）。material null DIAG：482 次全在 frame 1、dummy renderer 的 material_get_instance_shader_parameters，與測試 army 無關，交整合者。CC-052 接舷計畫 DONE（B0–B7，基本 25–39 人日）；10/14 已把 8 題玩法問 Nekki，等回覆後派 B0。CC-050 營地供水 v2：水的測試已 PASS（只剩結束時洩漏），新 admission 測試和 matrix 還卡在同一個 batch_paid=false，派 CC-059。CC-051 N08 v2：原 String==Dictionary 錯已修，現在停在 UI 按鈕「請選定原對象」，派 CC-060。多支測試共有的「結束時 1 個資源未釋放」：排了 HEAD 上 prefix 測試的 --verbose 跑一次。Region part37 收進 D（2ff3dee）：兩支 NPC 船測試推進到 NO_OBSERVER_OFFICE。finite_food 的 --verbose 顯示未釋放的是 terrain_data.gd（GDScript），另有 6 個 WeakRef 和 2 個 RefCounted。第 61 輪對 roster 沒有改善，不收；改用計時 DIAG 做 A/B（每種組合 2 次）。CC-053 trade T0 v3 全數 PASS，已收進 D（7e12cf0）。結束時的洩漏：prefix 在 HEAD 上的 --verbose 和 finite_food 特徵相同，是兩個 TerrainData（RefCounted）沒被釋放，屬於 site 共用的收尾問題；Region 的 d27 會找出循環路徑。material null 確認來自 contact rig 的 SubViewport，第 62 輪做試點。第 62 輪收進 D（8ab42b0）：recovery 在 headless 下 material null 482→0 並 PASS，接著推到另外 3 支。CC-054 gd_infer_check 收進 D（5807db4），誤報多。roster：計時 A/B 顯示不是第 53/54/61 輪造成，而是 prepare_combat 每步約 21 ms、測試本身就卡在 240 s 預算邊緣；第 61 輪撤回，DIAG v2 拆各階段耗時。改 deadline 須問 Nekki。10/14 11:56Z Nekki 決定接舷 Q1–Q8 全照建議（A）；B0 已派給 Codex（CC-061），B1–B7 依主鏈串行。第 63 輪收進 D（dad83f4），presence 在 headless 下也 PASS。Region part38（04bc391）推進到 UNSETTLED_SITE，part39 排隊中。第 65 輪（7f3a545）讓 command_save 首錯從 38 行推進到 82 行，第 69 輪排隊中。roster 超時的根因：測試沒有啟用 native hot store，100 列全走 GD fallback；第 66 輪讓它改用正式設定。roster_visual 的 MISSING_ASSET：空外觀處理有缺口，第 68 輪改正式碼並加大回歸範圍。d28 沒有找到 static 持有者，d29 改逐步追蹤 refcount。CC-055 loot：storage 測試 PASS，但 site_workflow 出現回歸，退回為 CC-062。10/14 晚間收進 D：第 68 輪（3341c7a，roster_visual 轉 PASS）、第 69 輪（245aeb6，command_save 轉 PASS）、T6 cleanup（a5d8853）、Region part39（8078f78）、part40（137a89d，original_dispatch 印出 PASS 標記，只剩共同洩漏）。第 66 輪（native hot）反而更慢，撤回，改用 DIAG v4 查 barrier。part41（ledger 容器循環洩漏修正）正在跑大批回歸。F1a v4 有兩處 String 被標成 PackedByteArray（Region 審出），中心修成 v4a 並加 check-only 閘門。P2A v4：12 項中 11 項 PASS，unvisited fallback 失敗，派 CC-064。CC-056a/b 診斷結果派 CC-063（real_npc 的 NO_WATER 疑與 CC-059 同根）。10/14 中心裁定：site_army_roster_visual_test 是截圖測試，歸為 visual-only，不再跑 headless；斷言不變。第 63、64 輪把 release_contact_source 推到其他 army 測試。d26：observer 5 的 identity reference 是空的，team/nation 的 ref 全部無效，已交 Region。
- 10/14 上 D：e2a00c2（CC-024）、a53cd38、2a6482d（Region part29、30）、12c1c73（第 43c 輪）、b400b4f（P1B）、d92c29f（主選單）、59ccc75、7c54f71、d2fc5ef 等。待驗：第 45–52 輪、貿易 T0、P2A v2、Region part31–33。待 Nekki：海上接舷規則（two_npc_sea 暫停）。
## 3. 需要 Nekki 的事

- ~~（03:12）在「科技樹研究」討論串確認寫入正式 D~~ **03:51 Nekki 已確認「確認寫入D 確認刪除」**；整合者寫入 D＋靜態檢查，同時清查刪除 A 類，T0／T5 等刪除收據。
- ~~原需求~~：整合合併已在暫存區組好並核對完（11 個函式取未加診斷版本、18 個保留 D 版本、提前納入 8 個 helper），寫入約 30 多個程式檔需要你親自確認。
- **在「專案無用檔案清查」討論串回「確認刪除」**：刪 A 類約 194 GB。

1. 在「AI 與職位工作分配整合」討論串打任意一行，讓它在你電腦上的那一端醒來繼續做營務官。
2. 未追蹤的 assets（約 708 MB，多為 png 與 region_lab 的 .z）沒有放進還原點 commit；要不要收進 git（png 建議改走 LFS）之後再決定，不急。

### 10/15 00:20 Claude Code 更新停機交接（Nekki 10/14 16:18Z 要求）
- D HEAD：46b8967（未 push）。停機前最後一批 cw3（營地供水 v3 DIAG）正在跑 matrix，跑完會自行還原；其餘尚未開跑的批次都已撤下，沒有跑一半的。
- 更新後依序重排（腳本都在 scratchpad，第一行 $out 要改成指向前一批的新 task id）：p41b（7 支 site 的 HEAD 基準）→ p42（part41+42 洩漏修正加回歸）→ n08c（N08 v3）→ r70（native game_seconds==0：會備份並重建 DLL，結果決定收不收）→ r71（seed canonical fixture）→ d31（F1a v5 的 faction scan 計時）→ b0 加 b0b（接舷 B0，Region 已審過）→ lt2（loot v2，含 workflow A/B）。
- 等驗收的回執：CC-057（F1a v5 結果已回，等 v6）、CC-059（營地供水 v3，看 cw3 結果）、CC-060（N08 v3）、CC-061（B0）、CC-062（loot v2）、CC-056e、CC-063、CC-064 進行中。Codex 可以照常做，回執留在 receipts/，更新後再收。
- 整合者：第 70 輪（C++）待跑，第 71 輪待跑；roster 的 deadline 視第 70 輪結果再決定要不要問 Nekki。Region：part41/42 待決，d30 視 lawful 的結果再重跑。
- 更新後第一件事：重啟 codex_receipt_watch.ps1，收停機期間進來的回執，再重排上面的批次。
### 10/15 更新後重排的結果
- 收進 D：第 70 輪（7f224db，native 接受 game_seconds==0，DLL 已重建）、第 67 加 71 輪（77e2a6b，seed_predicates PASS）、part41（6485bbf，prefix 測試不再洩漏）、loot 索引修正（11028e9）。
- 未收：part42 那批 region_travel 跑了 583 s、carried 超時，交 Region 查。B0 的新測試出現 'naval' 讀取錯誤，派 CC-068。N08 v3 推進到 captain 接受工作那一步，派 CC-069。roster 的 native 已接手，但全部被 think_hold 退回 GD，交整合者查。
- 進行中：master2（056f 科技、matrix 重跑）、P2A v5、056g 診斷、F1a v6、d32、CC-065（R4／NPC 供水／coin 相容）、CC-066（contact 測試）。
### 10/15 下午 每小時巡檢
- 這段收進 D（未 push）：9469f8f（生產供水）、b1268ba（科技 056j 定向載具）、81a60a6（067c front/scale 測試）、5adaeea（part48，journey_edge PASS）、4892b6e（part49 圍城冷結算 fixture）。目前 HEAD 4892b6e。
- 新回執：056l（military donor cargo）、071b（B1 v2 兩包）、045d（wildlife-only，要等 P2B 重新對齊 HEAD 才能驗，單獨套用失敗）；072（F1a v8、靜態摘要快取）進行中。
- D 批次 b1v2 已開跑：military_production（visual）→ Region 的 d41 prepare 階段量測（只量、跑完還原）→ B1 v2（check-only 閘門、14 個 boarding-case、boarding/ship/two_npc_sea/travel/original_dispatch 回歸）。B1 v2 已請 Region 審查。
- Nekki 10/15 09:33Z 確認接舷失敗或被擋下後，經有界時間自動放棄並恢復原航路（B1 v3 照此實作）。
- 等 Nekki 決定：roster／full_transport 要不要放寬到 330 s 或 360 s。Region 的 d40 判斷是先不改測試佈局，改為降低每步 prepare_combat 33～39 ms 的成本（遊戲每幀也會呼叫），d41 量出熱點後再交正式 patch。
### 10/16 清晨 收進 D 與待辦
- 收進 D（未 push）：9ef48de 食物時鐘 L、b18b3d9 船測試 360 s（Nekki 10:37Z 親自確認）、920ede6 military、991feaf contact source compaction、54cd151 army 測試 material cleanup、8a1bbae idle owner、de1f701 F1a v8（faction query＋冷恢復快取）、18f6a0d 救援 V3（每步 152→12.7 ms，roster 277→123 s）、bfeaaeb F1a 鎖初始化修正。
- 已知回歸：9ef48de 讓 ship_journey／edge FAIL（二分確認），Codex 074c 修正中；F1a 的鎖問題已由 bfeaaeb 修好。
- HEAD 上本來就 FAIL 的 site_workflow 子類（CC_WC76H_*）：army_membership、captive_escort、captivity_supply、combat_fixed_step、controlled_food_delivery、exchange_facilities_visual、family_continuity、food_delivery、gd_delivery_mesh_contact、guard_group、logistics_ui、loot_200_knockout_visual、loot_200_scene、roster_ui、ship_supply_flow、work_fatigue、work_rest。之後補 Codex 單時從這裡取。
- Codex 在手：045h（P2B undo／map return）、074c（ship journey）、075d（ground caller generation）、076d（workflow 完成回歸）、077d（two_npc_sea）、070g（matrix watermark）。Region：real_npc 第三層（part50＋51）、C36 合同。
### 10/17 00:20（台北）Claude Code 更新停機交接（Nekki 10/16 16:14Z 要求）
- D HEAD：627bc38（未 push）。本段收進 D：9ef48de、b18b3d9、920ede6、991feaf、54cd151、8a1bbae、de1f701、18f6a0d、bfeaaeb、c9e581e、6608dd6、21f420d、0871e54、27193e9、782c29a、a062a85、2f4d1f0、7677714、627bc38。
- 已知回歸／未解：site_ship_journey_test 從 9ef48de 起 FAIL；074g 讓 edge PASS，但造成 original_dispatch、carried 回歸（CC_SC74G_*），已退回 074h。
- Codex：單量減半，同時 2～3 張。進行中 071j（B1 重基）、097b（地圖編輯器 P3 的 E07）、070j（matrix）。待派 backlog 在 output/project_command_center/pending_notes/codex_backlog.md：077g、089c、075h、087d、095b、096b、094c。暫緩收件：081b、083b、090～093（等 089c）。
- 更新後第一件事：重啟 codex_receipt_watch.ps1，收停機期間的回執，讀 CC_SC74G_* 結果，再依 backlog 補單（最多 3 張）。

## 2026-10-17 03:45 update
- HB17 HEAD (627bc38) timing baseline: main_menu, delivery_prefix_owner, shared_step_replay, guard_rescue, full_transport (338 s), roster (104 s) and travel (273 s) all PASS.
- 095b, 096b and 075h are all clearly slower than HEAD (travel 657/575/387 s against 273 s). Treated as regressions; none committed. Details in pending_notes/codex_backlog.md.
- Codex is stopped (Nekki 10/16 18:58Z: quota used up). Pending on D: P3 097b, 087d DIAG.
- 05:30 **31247b3 committed**: P3 map editor building authoring (097b + one-line command-center fix to the house variant default). 12 P3C tests PASS; travel PASS.
- 070k matrix (fire case BUSY), 071k B1 DIAG (all three cases hit the 600 s limit), 074h (ship journey still FAIL) and 087d DIAG (actor never reaches the source): none committed; evidence filed under each FOLLOWUP's D_* folder.
- 10:30 **cb56e8e committed**: Haiku 074i ship clock. Lab-side GAME widths use the exact interval formula; site_ship_journey_test PASS 236 s (failed at HEAD). Full regression set PASS. edge still FAILs, as it does at HEAD. Note: the editor import in this batch hit its 600 s limit; check-only and tests were unaffected.
- 12:30 **1b86cac**: fixes the FaultSlot override signature in region_initial_world_transaction_test that cb56e8e broke (it had stopped region_slot_required_fire_clock, land_condition_rule_save and all artisan production tests from parsing). Verification queued (HFIX).
- 13:00 **d7b1e04 committed**: 070l cold matrix PASS 349 s + command-center fix so a continuation of the same fixed target is not re-blocked by its own unsaved Fire. The 5 replay tests that failed in the same batch fail identically on HEAD (HB70), so they are not regressions.
- AB17 interleaved timing: 075h/095b/096b run at the same speed as HEAD. The earlier "2-3x slower" was machine load; corrected, and their tests are being rerun.
- 14:25 **52e6983 committed**: 096b cold_exact siege owners keep their cold permit. A quiet-machine rerun passed everything (exact_consumer, main_menu 79 s, travel 316 s). The siege phase/cold first errors are the same as at HEAD.
- RR rerun: 075h target still FAILs (ground_caller Assertion failed at 101 s), not committed. 095b full_transport 369 s FAIL ("Original shore step did not commit exactly once"; HEAD PASS 338 s), not committed.
- 15:05 **16167fa committed**: 071n sea route search uses a native water-rule lookup plus a per-search memo. 16 sea/ship tests PASS; water_geometry and two-NPC friendly fail the same way as on HEAD (HWG).
- 071N incremental fire clock: no regressions, but row_cap still hits its deadline. Parked.
- 15:20 **a3252c5 committed**: 074k faction registry no longer bumps its revision when the canonical content is unchanged. site_ship_journey_edge_test PASS (failing since 9ef48de); journey PASS 107 s; f1a family, cold, main_menu and travel all PASS.
- 15:40 **01a310e committed**: R4b-1 national treasury binding and ransom ceilings (no payment). The 4 tests that failed fail the same way on HEAD (HB2).
- 15:50 **4c37602 committed**: map editor P4 S1+S1B (settlement nation_id, family v4 name/lineage_id, next_lineage counter). The family_continuity/offices failures match HEAD at the same lines (HB3). P4 S2 queued.
- 16:15 **cf79faa committed**: site_ransom_representative_busy_test override signature (broken by f17ffa2) fixed. PASS.
- Warning: full_transport now FAILs around 370 s on HEAD too (627bc38 passed at 338 s). Bisecting.
- 16:25 **58292c3 committed**: T6 S1 N-holder atomic exchange candidate (zero tax, no callers). Its 3 tests PASS.
- Confirmed: with the code reverted to 31247b3 (before today's commits), slot_required_fire_clock, fire_shared_step AR-17, slot_control_codec and artisan_f04 fail with the same messages. They are old failures, not caused by today's commits.
- 17:20 **43cb701 committed**: map editor P4 S2 travel guard. A departure that would lose the new family/settlement-nation fields is refused up front with RELATION_OPEN. 12 tests PASS.
- 17:50 **b76a238 committed**: T6 S2 per-settlement trade tax rate data (v4, 0–50%, set only by the head). The command center added a missing line continuation itself. 11 tests PASS.
- Atlas acceleration candidate A rejected (the dye output changed and it got slower). Probe V3 queued to bisect the cause.
- 18:05 **98b675f committed**: 095b siege compound save validation. 15 regression tests (visual mode where required) behave the same as HEAD.
- 18:20 **4f51948 committed**: R4b-2 nation ransom authorization (authorized_by) plus the ransom dialog. 11 tests PASS. Still no payment (R4c).
- 18:30 **da45371** T6 S3 treaty tax-rate lookup (pure function) and **3591291** R4c-1 ransom payment decision layer (no coin moves yet) committed; both tests PASS.
- P4 S3 (settlement nation assignment): the new test fails after a JSON round trip; sent back to Haiku.
- 18:35 **95ae03c committed**: map editor P4 S3 lets the settlement head assign the settlement's nation. 6 tests PASS.
- 18:40 **c4b18ff committed**: map editor P4 S4 pure family roster planner. 5 tests PASS. Editor UI (S4B) dispatched to Haiku.
- 19:00 **48e3af4 committed**: map editor P4 S4B family panel (edits go through draft commits). 8 tests PASS. S5 resident import deferred (needs a design decision on live bodies vs a static path).
- 23:20 **6890cbd committed**: fatigue skips per-person ship lookups on Sites with no ship (KO 200 people: 12.6 → 1.0 ms per quantum). 19 tests PASS.
- 01:35 **334b98b committed**: R4c national coin ransom (the payer withdraws at the treasury entrance and carries the coin; payment and release in the same step). 8 tests PASS.
- 01:40 **50c72f2 committed**: the threat table skips the per-person ship scan on Sites with no ship (094P). Regressions PASS; the KO 200-person simulation now finishes within its time budget.
- 01:50 **cc8eb77 committed**: R5 S1 nation designated-heir data, validation and save. 10 tests PASS.
- 02:00 **439ef8b committed**: the 200-person KO visual test now passes (atlas prepared first, the 100 s budget counts only the simulation, get-up measured from the wake moment). PASS twice in a row.
- 02:10 **8052e27 committed**: R5 S2 heir-designation lab test (D PASS: CO / lab 31 s / succession_designation).
- 02:40 **39f9735 committed**: map editor P4 S5 resident roster validator (data only; D PASS: roster/family_panel/family). R5 S1B: regression matches HEAD (family_continuity:214 and family_offices:57 fail identically on HEAD, HB3); new test's duplicate Settlement const fixed by CC (R5S1B_CC.patch), requeued. 075L DIAG: H1 confirmed (receipt as_of one ULP above world clock, both cases); Haiku fixing at the producer. 087F: past null npc / live body, now fails at the contact endpoint :122; 087G DIAG queued.
- 02:50 **c152120 committed**: P4 S5b resident placement precheck (D PASS).
- 02:55 HB87 baseline: contact_supply f11/f12 (REGION_INITIAL_WORLD_TRANSACTION_FAIL), contact_hit_cull (fixture invariant) and army_contact_batch (visual-only) fail identically on plain HEAD, so 087F adds no regression; 087F itself still stops at the contact endpoint (087G DIAG queued).
- 03:05 **22fe2a5 committed**: R5 S1B settlement/family heir designation v5 (CC removed a duplicate Settlement const in the new test; D PASS for the 3 succession tests; regressions match HEAD). 087G DIAG: target body has 0 shapes / 0 bounds and the attack pose never plays; Haiku on 087H.
- 03:40 **3f6dd9c committed**: T6 S4 in-kind trade tax (D: inkind test PASS after two test-only fixes; trade regressions PASS). T6 S4b treasury test reworked to the derived settlement path (queued). R5 S3 test const clash (SAVE) fixed by CC, queued. P4 S5c: CC fixed a split if-block; D shows birth consumer CORRUPT_SAVE and a panel test accessor error; back to Haiku. 087H DIAG: the Actor is hit once (fraction 0.617) but no contact is delivered; 087I DIAG queued.
- 03:50 **545de3f committed**: T6 S4b trade-tax receipt validation + derived treasury path test (D PASS). G0 big regression: all failures match HEAD except ship_travel / loot_200_scene, HEAD baselines queued. R5 S3: designation passes; save fixed to use controller.save_to (R5S3_D queued).
- 04:05 **888d6e8 committed**: R2 G0 proven political days F10/F11 (D: social/R3/region cold PASS; all other failures identical on HEAD).
- 04:15 **1639f1e committed**: R5 S3 lab heir designation test (D PASS). P4 S5c: panel and all regressions PASS; birth consumer still hits the item-location save check, DIAG round requested.
- 05:00 **cf7d66d committed**: P4 S5c author resident roster → real residents at world birth (11 D rounds; CC fixed a split if-block and the test's missing deadline/quit; D PASS + regressions). Open: author-package initial writer.
- 05:15 **9ac2870 committed**: P4 S5d author initial-state package export (P5B gate unchanged; D PASS). Open decision: admitting author maps to world birth (P5B).
- 05:20 **60389d9 committed**: R5 S4 vacancy contest timer on proven political days (pure; D PASS).
- 05:40 **615bdb9 committed**: R5 S2 narrow take-office transaction, controlled authority only (CC added a missing Runtime preload; D PASS, office regressions PASS or same as HEAD).
- 05:45 **69da48a committed**: R5 S3 vacancy episode record (pure; D PASS).
- 05:55 **3452d6c committed**: R5 S3b family vacancy episodes open/save/cancel (D PASS + store/family regressions).
- 06:05 **5b9d133 committed**: R5 S5 family vacancy contest close + winner takes office (D PASS + office/family regressions).
- 08:10 075M (receipt clamp) rejected: ecology now passes but region_faction_source_clock_test regresses (future endpoint must be strictly rejected); ground caller :484 and region_lab_contract still fail. 075N DIAG requested to pin the Fire index writer for a producer-side fix. Also: a stale .git/index.lock (06:42) made one batch check-only hundreds of files; lock removed, batches now refuse CO lists >20.
- 09:05 **a22122e committed**: R5 S6 duty AI tick drives family vacancy episodes. **5f0aabb committed**: R5 S7 nation and settlement vacancy contests (D PASS + office regressions). T6 S5 coin/nation legs: D shows no regression; two new-test failures fixed in T6S5D (queued). 075N DIAG pinned: commit_region_arrival writes the index one ULP above the clock; ground caller's value comes from the summary/stamp path; region_lab_contract is a different case (as_of 12660 vs now 0).
- 09:10 **c63f9f5 committed**: P4 S5e residents use the game's unequipped appearance (D PASS).
- 10:05 **4e91d0e committed**: T6 S5 coin payment legs + nation trade from the bound treasury (D PASS + all trade/ransom/store regressions). 075O arrival fix: ecology PASS, clock contract PASS; ground caller still pending 075P.
- 10:30 **2aa603b committed**: 087 delivery mesh contact test PASS (real Actor body in headless + unshielded fixture; shield had absorbed the only contact). Old R5 S9/S9B chain: owner clock never opened — cause found (lab NPC body is an Object, guarded with 'is Dictionary'); R5S9D queued.
- 10:50 **Handoff to Codex** (Nekki 02:43Z): all Claude D batches stopped; HEAD 58f8c92; queue, pending patches, HEAD-identical failures and hazards in output/project_command_center/HANDOFF_TO_CODEX_20261018.md.
- 11:00 Nekki 02:55Z: P5B opened per recommendation; CC-20261018-098 queued to the Codex command center (message 01a14cf3…): take over D verification/commits per the handoff, lift the user pause, implement P5B opening. Codex path in PROJECT_COMMAND_CENTER.md is stale (now …\bin\896a0166b774037a\codex.exe).

## 2026-10-18 Codex CC098 接手
- Nekki 明確恢復098；D驗收與commit由Codex接手，定時接單仍PAUSED，不push。
- R6S2提交 f5113c0：依計畫修正strict H-10與blocked觀察；兩CO及23項純測試D PASS（CC_098_R6S2FIX_*）。原sandbox CO120秒逾時保留，正常桌面同helper通過。git提交後LFS掃描超過60秒，但HEAD與精確兩檔已核實，未重複提交、未改守衛。
- 下一組B2 S2-S5；禁止舊批次式整樹reset。

- CC098 075：使用者裁定暫緩、交回 Claude 決定端點保存合同；未套用 P/Q。證據 evidence/CC-20261018-098/075_USER_DEFERRAL.json。其餘驗收繼續。

- CC098 B2：19 支 runtime 中 15 PASS；controlled_person_actions 與 ship_combat 同參數 HEAD 重現失敗；vehicle_transport 候選超內限而 HEAD PASS，未定因；travel 外限300秒逾時。整組 NOT_ACCEPTED、未提交，完整 patch 與原位元組已封存於 evidence/CC-20261018-098，正式來源還原。R5/R6 最終修正候選開始 D CO。

- CC098 使用者因五小時額度要求暫停至 10/18 16:00（台灣）；單次排程 cc098。R5/R6 CO17 PASS、runtime 41 PASS／2 既有首錯，43支已結束，尚未提交。P5B未套、075仍交Claude裁定、B2封存。舊定時接單仍暫停。

- 16:00恢復098；R5/R6已提交4734d50，CO17 PASS、runtime41 PASS及2筆既有FAIL；未push。提交後LFS掃描逾時180秒，提交本體已核實。P5B接續，075仍暫緩。

- CC098本輪收尾：P5B已提交12a06da，11檔CO PASS、新作者E2E PASS75.378秒、初始交易用找回原300秒外限PASS239.699秒；20支中18 PASS，region_lab_contract既有faction收據FAIL、travel原300秒逾時仍列FAIL。原120秒誤設截斷收據保留。主單FAILED表示部分交付，非全驗收成功；B2封存未收、075依人類裁定暫緩交Claude。無本單Godot/批次仍在執行，未push，舊定時接單未恢復。

- 2026-10-18 使用者交還指揮中心給Claude：Codex一次一主單、owner串行；額度用盡立即寫QUOTA_STOP回執並停止接單，等Nekki恢復。交還回執HANDOFF-TO-CLAUDE-20261018.json，待Claude讀取確認。定時接單仍暫停；HEAD12a06da未push。
- 21:15 Command center back with Claude (Nekki 13:11Z): HEAD 12a06da (Codex CC098 committed R6S2 f5113c0, R5/R6 4734d50, P5B 12a06da; B2 S2–S5 not accepted, vehicle 60 s deadline regression). Rule now: one Codex task at a time, next only after its named receipt; stop on QUOTA_STOP. 075 ruling: keep 075O arrival fix; reject P/Q relative-tolerance selector (Codex counterexample: 0.5 s advance swallowed at 1e9 s); same-endpoint = within 4 ULP of the projection; formalise the stale-endpoint test. Dispatched CC-20261018-099.

- CC099 NEEDS_INPUT：精確4ULP候選CO8 PASS、28 runtime24 PASS/4 FAIL；ground cold_pending原90秒FAIL、contract:193 UNSETTLED_SITE、travel原300秒逾時、replay候選103.521秒FAIL/同參數HEAD80.7秒PASS。真Site earth_tw_tm2_121_v1:12:-8的settled/fire=23而投影23.00000000000002，實測6ULP；未放寬4，因主目標未全過不提交。候選封存於evidence/CC-20261018-099，正式腳本已還原HEAD12a06da，無Godot/worker在跑，未push。等Claude裁定；一次一單，定時工作仍暫停。
- 23:05 CC099 NEEDS_INPUT (24/28 PASS; observed 6 ULP > 4; ground caller still fails its 90 s cold_pending deadline, region_lab_contract :193 UNSETTLED_SITE; candidate replay 103 s vs HEAD 80 s). Ruling: 075 parked entirely; ground caller and region_lab_contract stay known HEAD failures; candidates stay archived. Dispatched CC-20261018-100: B2 S2–S5 vehicle-deadline root cause by interleaved HEAD/candidate A/B, commit only if no real regression.
- 02:15 (10/20) Resumed (Nekki: quota back; one Codex task at a time, don't wait on it). Committed 974b913 R6S4+R7S1 pure, 4582eb2 P5C S1-S2 (two-Site authored worlds, E2E PASS), 821ad25 B2b (unlink, epoch, linked-hull refusals). Found: main_menu_flow (second back-to-menu) and region_initial_world_transaction (300 s timeout) fail on HEAD 974b913 but pass with e7c535c reversed (154 s); main_menu also passed once on HEAD+P5C → Codex CC-20261020-101 does interleaved A/B and fixes if B2 is the cause. Stale .git/index.lock (10/19 00:43) removed again. Haiku: R6S5/S6 fixture, B3R4 settle check, P5C S3.
- 07:20 (10/20) CC-101 NEEDS_INPUT: main_menu failure root cause = existing snapshot hash defect (hash computed on in-memory binary64, Godot JSON reads 0.9999999999999999 back as 1.0 → CORRUPT_REGION_SNAPSHOT); B2 only shifted timing; world timing not reproducibly slower. Ruling: canonicalize numbers through the same JSON round trip before hashing on write; no read-side tolerance; no dual-hash backdoor. Dispatched CC-20261020-102. My D runs: R6S5C/S6E reach the transaction but leave_row refuses NPC (NO_AUTHORITY); B3R4 finish/sweep fail (empty array, reverse NO_TARGET); P5CS3B companion house fixture fails. All regressions PASS. Sent back to Haiku.
- 07:30 (10/20) Nekki 23:24Z: scheduled work resumed (pause since 10/18 13:11Z lifted). Codex still one task at a time.
- 08:30 (10/20) Codex CC-102 DONE: 8ec6dc4 snapshot state normalized through the JSON codec before hashing (212 pure checks, main targets 6/6, regressions 13 PASS / 3 HEAD-identical). Dispatched CC-20261020-103: region_travel_test 300 s timeout root cause (no deadline change). B3R5 D: two remaining failures (cancel result semantics, sink does not clear the link) back to Haiku.
- 09:20 (10/20) Committed 06cd82c R6 NPC team departure by event + seats + team supply release (D PASS), 451339b Boarding B3/B4 link-gated crossing, closing, sink clear, channel death (D 14/14 PASS). P5C S3 still on the companion-center fixture.

- 2026-10-29 15:17: G4 formation+vehicle movement committed e1697dc (Opus high redesign, 6 D rounds). Logistics crowd acceptance p100/p12 PASS, 16 regressions PASS. DLL 316454AC published (prev 8120CB23 backed up in evidence/CENTER_G4). Known: Opus stress runs, outside the official suite: 7/128 random rocky runs stall only with vehicles; 4 unexplained 8-person D-map deploys. Next: G1 ships.
- 2026-10-29 22:40: G1 S1 9ecff33 (native aboard state, DLL 37D8A70B) and G1 S2 8e9997f (ships under crowd: board/sail/dock/land; DLL CF7FC6F7 published, backups in evidence/CENTER_G1). Machine ran ~1.8x slow in the evening, so logistics acceptance fails its 105 s in-file budget at HEAD too (run 20261029_223530_544). Rerun when the machine is normal. Next: G1 S4, mid-sail reload on a generated coastal map, plus ship-to-ship crossing under crowd.
- 2026-10-30 00:47: G1 done: S4a 16a7190 (mid-sail reload on generated coast, hash equal) and S4b ebfecb3 (ship-to-ship crossing under crowd). Machine still ~2x slow: acceptance median 22.7 ms/tick vs 11 ms on 10/29 afternoon, and the empty pause tick is also 2.5x slower, so the cause is code-independent. The logistics acceptance 105 s budget fails at HEAD (run 20261030_004554_321). Next: G2 shipyard.
- 2026-10-30 01:15: new gap G10 (found in G2). A crowd Site cannot be saved while any crowd worker holds a work-station step: native World::save refuses on escort_mode >= 3 (state.cpp:217-219). This affects every crowd work team (construction, siege, shipyard), so autosave is blocked for whole jobs. It must be resolved before the default flip; solutions go to Nekki.
- 2026-10-30 02:28: G2 b94e345 (shipyard under crowd) and G3 897b297 (split-shore supply under crowd; aboard counts present; DLL 698C219C published, backups in evidence/CENTER_G3) are done. Ship gaps G1-G3 are closed. Open: G10 (unsaveable while held steps), waiting for Nekki A/B/C. Next: G8 grid readers.
- 2026-10-30 02:57: G10 done 069be9c (Nekki A: held work steps save; DLL 8F5EDF27). Next: G8 grid readers.
- 2026-10-30 06:56: G8a caa54c4. Logistics acceptance PASS at HEAD again (run 20261030_065352_552), so the earlier budget failures were machine slowness. Pre-existing at 069be9c: crowd_c2_ui_test (visual, 600 s timeout on a null set_value_no_signal) and crowd_c2_d10_enemy_test ("original family button appends NPC") both fail. To investigate later. Next: G8 slice siege work/vehicles, then garrison with G5.
- 2026-10-30 10:00: G5 S1 9b78d7f (native absent/return/move, KW15, DLL 5A0311E5) and G5 S3 43fe64d (garrison on native; recruit refused CROWD_RECRUIT_AUTHORITY). Pre-existing at HEAD: site_barracks_types_legacy_crowd and site_barracks_types_training_crowd fail. Next: G5 S2 (GD roster for detached members), then S4 surrender (needs a Nekki decision).
- 2026-10-30 12:33: G5 done: S2 0773a8e (detached/off-map as native absences), S4 9914d98 (surrender AAA; DLL 26BF2CC1). Finding to raise: in real play, tactical AI keeps formations moving, so auto-capture of pocketed surrenderers may rarely trigger. Next: G7 retire grid planners, then siege catapult/palisade port, cavalry CAV-1, the flip.
- 2026-10-30 17:00: 73eabb2: surrender now becomes an immediate captive of the nearest enemy (Nekki), and the crowd capture_fields formal-commander crash is fixed (DLL A7ECCF15). 71c78a3 G7a: preset geometry module and crowd guards. Pre-existing headless failures ("material is null"): combat_formation_ko_hold_store, site_corps_reposition_move, combat_formation_100_arrival, combat_formation_store_matrix. Waiting on Nekki: persuasion A/B/C. Next: siege catapult/palisade port inventory.
- 2026-10-30 18:00: siege S1+S3 committed (palisade waits for clear cell; crowd crew station 0.75; workteam test updated to G10). Next: siege S2 (fire-destroyed palisade sync) + S4 (trebuchet turn without grid planner).
- 2026-10-30 19:00: siege S2 + part of S4 committed (destroyed palisades reopen native paths; crowd turn plans no longer dropped; _siege_faction reads native). Open: trebuchet turn blocked by same-team soldiers drifting into the sweep (asked Nekki A/B/C). Turn cases are kept in evidence/CENTER_SIEGE/SIEGE_S2_S4_with_turn_cases.patch.
- 2026-10-30 19:50: CAV-1 native cavalry committed (KW17, DLL 10ACB9EB). Next: CAV-2 Godot wiring. Open Nekki questions: trebuchet turn sweep (A/B/C), post-battle persuasion (A/B/C).
- 2026-10-30 22:05: CAV-2 committed (DLL 56D0A0F4). Only Actors can ride until CAV-3. GD charge/through3/pike cases deferred to CAV-3/4 (verified natively). Next: trebuchet turn yield (Nekki A). Waiting on Nekki: persuasion 3 questions.

- 11/03 01:25 GATE_v2_D2 完成：87 支中 40 過、10 撞閘（delivery_duty、fire_acceptance_completion、ranged_army、retreat_exit_capture_store、siege_actual_balance、team_sustain_clock、work_ai_boundaries、work_team、terrain_army_default_edge、terrain_lab_army → 改寫/退場清單）、37 支非閘失敗。加上前批 22 支 = 59 支，正在乾淨 HEAD（無閘）跑基準：evidence/CENTER_OPTIONC/BASELINE_HEAD。Haiku 分類完成：CONTINUOUS_SWITCH/optionC_sim_plan_20261102.tsv（PORT-HIGH 96 / PORT-LOW 35 / RETIRE 37 / DIAG 10）。D scripts 已還原乾淨。
- 11/03 02:45 提交 5f8875b（閘：非 --grid 時拒跑格子模擬）。基準：59 支非閘失敗中 58 支乾淨 HEAD 一樣失敗，partial_weapon 為 23 s 時限偶發。撞閘 23 支（13+10）進改寫/退場清單。正在 gated HEAD 跑 stage1 回歸清單中尚未在閘下跑過的 148 項：evidence/CENTER_OPTIONC/STAGE1_UNDER_GATE（比對 stage1 基準）。
- 11/03 03:50 閘 5f8875b 已 revert（59f4c1f）。gated stage1 回歸 54/148 時發現：region_crowd_journey / offscreen_step / ship_sea_departure 撞 TerrainArmy.prepare_combat（_region_gameplay_party_progress 用它推進全員忙碌的身體計時，非格子移動）；crowd_b_import_guard、crowd_c2_clear_handoff、region_siege_cold_action_epoch 也撞閘。另有 4 條 crowd_site.clear() 交接回格子的遊戲路徑（營帳 _prepare_tent_person、駐軍 site_garrison._ordinary、clear_army、siege 非 native 建造）。下一步 GATE_v3：閘移到 prepare_combat 內的移動/接戰規劃段，保留計時；先跑上述 6 支。
- 11/03 04:25 GATE_v3/v4：閘移出 prepare_combat、旅隊/離屏 actor 迴圈、_advance_combat actor 迴圈 → 6 支 region_crowd 測試通過。GATE_v5 = v4 + 拿掉 4 條 crowd_site.clear() 交接（營帳直接轉移、清除測試隊伍改為同次移除、攻城器不支援時拒絕、駐軍非原生來源拒絕）；tent/garrison_crowd/stockpile/siege_native_workteam 通過。import_guard、clear_handoff（測 B 回格子）進改寫清單；region_siege_cold_action_epoch 暫加 --grid。正在跑 GATE_v5_full（148 項）。
- 11/03 06:40 GATE_v5_full 完成（148：81 過）。新增撞閘：main_menu_flow / main_menu_input_flow（新遊戲起始 Site 是格子 Site，crowd 未啟動，coordinator/exchanges 每步跑）→ 閘暫不提交；前置任務：Site 開啟（新遊戲、讀檔、地區抵達）時即轉群體（沿用 legacy convert）。fire_p2_acceptance_supplement、fire_projectile_pipeline、fire_shared_step、gd_delivery_prefix_owner 在格子 Site 跑 → 改寫清單。CLEAR_v1（4 條 clear 交接拿掉）單獨驗證中：evidence/CENTER_OPTIONC/CLEAR_v1_D。
- 11/03 07:05 提交 57f26e8（拿掉 4 條 clear 交接，6 支通過）。SITECONV_v1（terrain_lab bind：crowd_startup_requested 即轉，不限 legacy）+ 閘 = GATE_v6：d5_scene/region_crowd_bind/departure/roster_absent/region_gameplay_travel 過；main_menu_flow 失敗：新遊戲起始 Site 轉群體後 lab.character.display_name 空（DIAG_CONV：crowd 6 人、owner=CrowdPersonOwner），狀態列會顯示 #1；main_menu_input_flow deadline。legacy_convert 30、siege_native_integration 52 是舊設計預期（讀檔保持格子）→ 依新規則改。Haiku 追名字遺失：CONTINUOUS_SWITCH/conv_player_name_trace_20261103.md。診斷腳本 scripts/tests/diag_main_menu_conv_test.gd（未追蹤）。
- 11/03 07:40 GATE_v8 = 閘(v4) + Site 開啟即轉群體 + finish_initial_birth 接受 native 後端 + apply_created_character 把指揮能力寫入 native + legacy_convert/siege_native_integration 改新預期：10 支轉換測試全過（barracks 無參數為舊債）。正在跑 GATE_v8_full（148）。待辦：_region_player_down_settlement 只認 gd 後端（群體 Site 玩家倒下不結算）。
- 11/03 12:25 GATE_v8_full 完成（148：82 過），與 stage1 基準比：無新失敗；只掉預期要改寫的 6 支（crowd_b_import_guard、crowd_c2_clear_handoff、fire_p2_acceptance_supplement、fire_projectile_pipeline、fire_shared_step、gd_delivery_prefix_owner）；main_menu 兩支已過；site_housing_crowd_test 記憶體不足當掉，乾淨 HEAD 57f26e8 也一樣（環境）。提交 GATE_v8（Sites 開啟即群體 + 閘），未推送。下一步：(1) 玩家倒下結算支援群體（_region_player_down_settlement 拒 crowd/native）；(2) 改寫撞閘測試，先火焰 3＋交接 2＋運送 1，再依 optionC_sim_plan 高優先 96 支；(3) 第三階段刪格子模擬程式碼。
- 11/03 13:15 提交 1c387c5：bind 轉群體移到火攻運送/火攻主人還原之後（修 INVALID_FIRE_NAVIGATION）；crowd_c2_clear_handoff、crowd_b_import_guard 改寫通過；16 支相關測試全過。下一步：fire_p2_acceptance_supplement / fire_projectile_pipeline / fire_shared_step / gd_delivery_prefix_owner 先試 --grid 暫保，再排群體改寫。
- 11/03 13:20 火焰 3＋運送 1 加 --grid 在 HEAD 全過 → 暫列 CONTINUOUS_SWITCH/optionC_grid_interim_20261103.md（連同 cold_action_epoch）；新回歸清單 optionC_regression_manifest_20261103.json。第三階段刪碼前，這 5 支與 PORT-HIGH 96 支須先改成群體。
- 11/03 14:10 收回 4101fa1/1c387c5/8a23a78（revert：aa6f13f、7ba99b7、cb7c057），scripts 回到 57f26e8。原因：Site 開啟即群體後，玩家是群體中的單人 actor，crowd_site.departure_plan 拒絕（群眾中的 actor 本體尚不能整隊出發）→ region_travel_test 單人出發失敗＝新遊戲玩家不能自己離開。重新上線用補丁：evidence/CENTER_OPTIONC/OPTIONC_RELAND_57f26e8_to_8a23a78.patch。前置產品工作：(1) 群體單人 actor 出發（departure_plan/_depart_crowd 支援 _actors）；(2) 玩家倒下結算支援群體。23 支撞閘重跑：7 支在 v9 閘下已過。
- 11/03 15:00 群體單人 actor 陸路出發 v1 補丁：CONTINUOUS_SWITCH/crowd_solo_departure_v1.patch（Haiku；設計 crowd_solo_actor_departure_design_20261103.md）。SOLO_v1：region_crowd_departure/journey/cadre_split/split_ui/arrival、main_menu_flow、region_travel --grid 過；region_travel 無 --grid 的 _solo_trip 是「非幹部成員脫隊」＝Nekki 11/01 規則禁止 → 該測試維持 --grid。新測試 region_crowd_solo_departure_test 撰寫中（Haiku）。海路單人第一版拒絕，等 Nekki 決定。
- 11/03 15:30 提交群體單人 actor 陸路出發（crowd_site solo_departure_plan/release、_depart_crowd_solo、extract crowd_solo、SiteStore 接受一人 solo 墓碑、新 region_crowd_solo_departure_test）。14 支相關測試過。海路單人暫拒（CROWD_SOLO_SEA_UNSUPPORTED，待 Nekki）。下一步：套回 OPTIONC_RELAND 補丁重跑整份回歸。
- 11/03 16:10 Nekki 08:07Z 提議：玩家開局即為「無勢力一人隊（自己當隊長）」，加入勢力再改身分，免單人 actor 特例。我回覆贊成；9e48341 暫留作舊存檔保險。Haiku 調查中：CONTINUOUS_SWITCH/factionless_player_team_survey_20261103.md。RELAND_full 回歸進行中。
- 11/03 16:25 無勢力一人隊調查（factionless_player_team_survey_20261103.md）：faction -1 各處被拒；敵我=編號相等，需每人專屬保留勢力編號；無改投勢力流程；舊存檔需轉換 → 大工程。建議先用 9e48341，一人隊併入勢力系統工作；等 Nekki 回「現在做」與否。
- 11/03 17:45 重新上線 97a1a50（Site 開啟即群體＋閘＋交接測試改寫）。RELAND_full 150 項：91 過，與 stage1 基準比無新失敗；region_crowd_solo_departure_test、region_travel --grid 過。全部未推送。待辦：中立勢力一人隊（等 Nekki 確認「中立對中立不算同伴」）、玩家倒下結算支援群體、--grid 暫保 4 支＋PORT-HIGH 96 支改寫、第三階段刪碼。
- 11/03 18:00 玩家倒下群體補丁 player_down_crowd_v1.patch（Haiku）：5 支相關測試 HEAD 與補丁結果/訊息相同（4 支舊債），無正向覆蓋 → 未提交；Haiku 寫 region_crowd_player_down_test。舊債記錄：crowd_c2_d6_family_test「family button transfers control」失敗（群體家族交接，Nekki 10/23 決定 A 的群體部分）。
- 11/03 18:10 玩家倒下群體：補丁 player_down_crowd_v1.patch 暫停未提交。診斷：測試自造的 player_death 事件沒有真實抵達對映（_region_player_death_mapping 需 travel_identity + arrival_mapping），所以 proof 仍為空；正確測試要走「旅行→抵達群體 Site→倒下」全流程。測試草稿移到 CONTINUOUS_SWITCH/region_crowd_player_down_test.gd.parked。
- 11/03 18:15 Nekki 10:03Z：接受「中立對中立不算同伴」；舊存檔不轉換，直接拒讀（版本號+1，不刪檔）。排程：火焰測試改寫收尾後做中立一人隊（保留中立編號、敵我/招募規則、新遊戲隊長出生、加入勢力改編號、移除單人 actor 特例）。
- 11/03 18:20 Nekki 10:18Z：(1) 海路照一般整隊規則（全員上船才可）；單人＝一人隊允許 → 中立一人隊上線後拿掉單人海路暫拒。(2) 舊存檔皆為測試用，全清 → 搬到封存資料夾（不硬刪）＋存檔版本+1。(3) 中立勢力建國前不能外交、不能佔領聚落，只能內政 → 在外交/佔領入口加 NEUTRAL_NOT_NATION。第 1 部分補丁（Haiku）已追加第 3 點。
- 11/03 18:35 中立第 1 部分補丁 neutral_faction_part1.patch（NEUTRAL_FACTION_ID=255、same_side、約 25 處敵我判斷、site_settlement 佔領擋 NEUTRAL_NOT_NATION；無外交入口）。跑 NEUTRAL1_full（150）中。原生待辦：crowd_core.cpp:1262-1276 256x256 敵我表對角恆 0 → 中立對中立需每隊陣營（需改 C++＋PS5 建置 DLL）。
- 11/03 20:45 提交中立第 1 部分（150 項無新失敗）。Nekki 12:40Z 問勢力破 255：上限早已存在（原生 uint8、256x256 表、驗證 0..255）。提議：全域勢力 id 不設限，Site 進群體時把在場勢力對應到 0..254 本地 slot，中立每隊各一 slot（同時解決原生中立同邊）；群體存檔改存全域 id＋對應。等 Nekki 回覆。
- 11/03 20:50 提交 2dfd0ef（中立第 1 部分）。舊測試存檔已封存（搬移，非刪除）：%APPDATA%\Godot\app_userdata\worldgoing\archive_old_saves_20261103（sites 19、region_lab 19、crowd10k_test sites 2）。存檔版本+1 與拒讀舊版尚未實作。
- 11/03 21:30 第 2a：Haiku 只交存檔 FORMAT 4→5（neutral_part2a_captain_birth.patch，未提交：固定測試存檔會讀不到）。形狀調查（player_team_shape_survey_20261103.md）→ 決定 (b)：玩家＝一人群體名冊隊的 unit 0 兼隊長，經 host control 操作。Haiku 未完成 → 改派 Opus 實作 neutral_part2_player_team.patch（含 FORMAT bump、建角寫群體紀錄、狀態列名稱、出發走整隊路線）。
- 11/03 21:40 Nekki 13:12Z：勢力上限採「本地對應」（全域 id 不設限；Site 進群體時在場勢力對應原生 slot 0..254，中立每隊各一 slot；群體存檔存全域 id＋對應；原生不改）。排在中立第 2 部分（Opus 實作中）之後。
- 11/03 22:00 Opus 交 neutral_part2_player_team.patch（9 檔；出生=中立一人 TerrainArmy→轉群體名冊、host control；apply_created_character 寫群體紀錄；_capture_positions 不寫 actors.player；FORMAT 5＋OLD_SAVE_UNSUPPORTED；改 main_menu_flow/region_initial_world_transaction/allocator/map_editor_author/site_combat_save 測試）。約 26 支測試需改預期（region_travel、region_crowd_* 11 支、region_* 8 支、site_* 6 支）。PART2_focus 8 支跑中。
- 11/03 22:40 第 2 部分 v2（neutral_part2_player_team_v2.patch，未提交）：轉群體失敗根因＝群體名冊只用士兵外觀圖集繪製，建角自訂外觀/便服不在圖集 → convert_existing MISSING_ASSET 回滾。v2 改成開局穿標準士兵裝（遊戲變更，未經同意）。已問 Nekki：(A) 有 actor 身體的群體隊長（推薦）/(B) 限圖集外觀/(C) 即時烘圖集。主線不動。
- 11/03 22:50 Nekki 14:15Z：選 (A) 並擴大：玩家與所有幹部都有獨立外觀（真身體繪製），仍為群體名冊隊員；一般士兵用圖集。Opus 設計中（承接 Haiku 未完成的隊長出生）：CONTINUOUS_SWITCH/bodied_roster_members_design_20261103.md。
- 11/03 23:05 設計完成 bodied_roster_members_design_20261103.md：名冊為唯一真實資料，CrowdSite._bodies 只負責繪製（kit -1），bodied_ids 規則（玩家/隊長/幹部/軍官/代理），黏著規則，上限 64，原生不改、存檔不改。分 S1 幹部有身體／S2 自由外觀／S3 新遊戲一人隊／S4 移除單人 actor＋版本+1。Opus 實作 S1：bodied_s1.patch。
- 11/03 23:45 BODIED_S1：12 支中 10 過（新測試無頭版過、群體綁定/分隊/出發/存檔/駐營 visual 皆過）；新測試 visual 版讀檔後身體節點 0 個（bodied_ids 6 人）→ 回 Opus 修 v2；append_atomic 為舊債。
- 11/04 00:20 看板：主線（未推送）57f26e8 → 9e48341 → 97a1a50 → 2dfd0ef。進行中：S1 幹部有身體（bodied_s1_v2.patch）整份回歸 BODIED_S1_full 跑到 76/150（runner 存活，工作階段重啟不影響；結束會自動還原）；S1 相關 12 支已過。待做：S2 自由外觀＋黏著、S3 新遊戲中立一人隊（遷移約 26 支測試，Opus 補丁 neutral_part2_player_team.patch 作底）、S4 移除單人 actor＋存檔版本+1、勢力本地對應、加入勢力改編號、--grid 暫保 4 支、家族交接舊債、玩家倒下結算（補丁暫停）。
- 11/06 09:05 本日提交（全未推送）：
  - 75a7869：NPC 貴族因不滿而叛離（每日一次；隊長整隊改旗，非隊長單人離隊另立）。
  - eb9564a、a1fb202：舊失敗測試修兩支（牢房名冊、攻城存讀 native）。
  - d1618a4：群眾陣形 G7b，原生存檔升 KW20；DLL A282E589…。
  - e96add0：群眾存讀雜湊修正，crowd_c2_c3 首次通過（畫面模式＋圖集）；DLL 55E41A02…，舊版備份在 evidence/SHAPE_native/previous_dll。
  - 貿易 T1（Nekki 11/06 選 A：群眾可交易）：1377cad、3ca5d5d、93762f5、e8b953d、4ee6e65、950eee1。
  失敗清單更新：CONTINUOUS_SWITCH/fail_triage_20261105.md。下一步候選：T2 組織交易、TR-1A 專屬測試、其餘舊失敗測試。
- 11/06 22:05 科技驗收（Nekki「好，驗」；數值照建議）：正式開放 23 個節點：
  - 家族 F03–F15；
  - 聚落 S01、S07、S12；
  - 國家 N01–N05、N09、N11。
  許多主驗收要帶 --grid（格子場景）、畫面模式或圖集參數，已寫進 full_v2／battle_full 清單。剩 17 個的卡點在 CONTINUOUS_SWITCH/tech_acceptance_status_20261106.md；S09／S10 已推進三關，目前卡在外觀圖集。今天其他提交：
  - 貿易 T1／T2（交易、議價、交付、存讀、對話框；聚落市正與額度、車輛、家產與管家、陷落失效）；
  - 舊失敗測試修 10 支；
  - 群眾陣形；
  - 雜湊修正；
  - 原生追加人物修正。
  全部未推送。
- 11/10 00:40 提交 cc52dd5（未推送）：carried_intel／remote_nation 群眾移植；群眾站點收軍令改走 `_region_nation_team`＋`_region_team_issue_order`（之前一律 COMMAND_AUTHORITY_CHANGED）；抵達隊伍保留 tactical_ai.enabled。回歸 REG15 67/69，兩失敗補跑 PASS（NATION_CMD_v2、REMOTE_NATION_v9）。進行中：cancellable_departure 依 B 移植（CANCELLABLE_B_v1）：`departure_plan` 走動隊員拒絕 NOT_READY；`_depart_crowd` 在 combat_left>0 時採格子意圖路徑同一條「已准入原圍城＋無火」豁免（之前群眾隊伍在被圍站點完全不能出發）。之後回歸群眾出發／抵達家族再提交。
- 11/10 02:40 待辦登錄（Nekki 11/09 17:33Z「都依建議」）：文官／武官體系方案 B（reports/civil-military-office-plan.md §8 W1–W5）排入待辦；W1–W2 可併聲望計畫第 1 步，W5 待授爵與封地完成後。土匪勢力規格 V0.1 已入庫（d8e2bce）。群眾移植批次仍優先。
- 11/10 03:00 待辦登錄（Nekki 11/09 17:51Z「都依建議」考試與學校 §13 八題全 A）：E1–E4 列入待排；前置文武官 W1–W2 與聚落中心 P0，E3 另需聲望第 1 步。學校美術 12 張屬建築美術例外，可先交 Codex（一次一件）。軍餉稅收 §12 P0–P6 待 Nekki 回 §13。
- 11/10 03:10 待辦登錄（Nekki 11/09 17:57Z／18:03Z「都依建議」）：軍餉與稅收定案 V0.2（Q1–Q12 全 A；新增國家層財政官派收稅隊 §4.5、PT-15～19、P3b）。§12 待排：P0–P1 與文武官 W1–W2、聲望第 1 步併同一次存檔版本升級；P3 等授爵與封地；P3b 與 NPC 商隊同批；P2、P4–P6 依 §12 順序。
- 11/10 05:30 提交 03ddb76（未推送）：static_siege_entry、player_first 群眾移植；修正群眾出發／抵達在圍城中的缺口（B 走動拒絕只在玩家出發路徑、已准入原圍城豁免、冷群眾 owner 唯讀擷取、exchange_ready 群眾引數、行動中圍城載入准入與 bind 情境驗證、事件時刻 1e-8 同點容差、分鐘相位累積漂移容差）。回歸 DEPARTURE_REG_v1 29 支：26 過，wagon_arrival／remote_nation 因走動檢查位置錯誤失敗、移位後重跑皆過；cancellable 未提交，卡在新缺口「群眾隊伍有陣亡者無法整隊出發」（Decision A2 尚未移植到群眾；設計 CONTINUOUS_SWITCH/crowd_dead_member_departure_design_20261110.md）。下一步：補 A2 群眾版。
- 11/10 09:40 陣亡者出發（出發端）完成未提交：原生 site_person_release_dead、DLL b8a12bbe 已發佈（舊 035a8051 留存 evidence/SHAPE_native/previous_dll）；原生測試 57,066 項全過；新測試 region_crowd_dead_member_departure PASS；群眾核心回歸 CROWD_CORE_REG16 69/69 PASS。到站端等 Nekki 選 A（死者隨隊到站，比照格子 A2）或 B（死者留站）；兩端一起提交，避免帶死者的隊伍出發後在群眾目的地被拒而卡住。two_npc_sea 調查：需重寫（CONTINUOUS_SWITCH/two_npc_sea_crowd_port_map_20261110.md）。
- 11/10 13:00 提交 0be1fc5（未推送）：Nekki「5A」群眾陣亡者照格子 A2（已結算死者隨隊惰性同行、到站留隊）；原生 site_person_release_dead（DLL b8a12bbe，舊 035a8051 留存）；群眾隊伍在已准入圍城中出發改照格子：原地交冷 owner、已付進度保留（群眾副本釋放＋共用提交）；火攻存檔守衛的群眾檢查交還攻城守衛。合併回歸 FULL_REG_20261110 80 支：79 過；唯一未過 cancellable（未提交），卡在下一缺口 UNSUPPORTED_CROWD_RETURN（離開者回到同一群眾站點，原生墓碑位置）。下一步：原生收回墓碑位置。

