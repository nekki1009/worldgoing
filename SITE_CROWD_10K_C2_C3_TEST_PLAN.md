# 群眾模式 C2／C3：施工與測試辦法（交給接手的 AI）

**2026-10-03 01:54 最新補給／UI 優化與可沿用基線**：使用者核准的 same-call native 生命驗證／checkpoint 批次及隊伍摘要去重已落地；渲染抽樣後保留原 renderer，沒有加入未證實收益的 cache。原 probe v2 新一輪正式 5000 人結果：待命 **71.53**、行軍 **67.31**、交戰 **62.67**、戰後 **57.75 FPS**，**11250 幀，0 幀超過 50ms**；自然 20 秒安靜恢復、原時鐘／命運事件、25006 件實物守恆和來源前後核對通過。局部完整補給 A/B 中位數 **25.225 → 11.949ms**；新／舊 gameplay 自然戰況不同，待命／行軍略低，不宣稱固定 FPS 提升百分比或全面加速。完整新基線、patch、測試、失敗、渲染觀測限制和來源指紋在 [本輪紀錄](output/crowd_sustain_frame_20261003/README.md)，有效索引為 [baseline.json](output/crowd_sustain_frame_20261003/baseline.json)。**無相關變更先沿用紀錄；保存 300ms／載入 500ms 已不再硬性追求，原保存安全要求保留；不是整份 C2／C3、10k 或 release 驗收。** 下段 00:45 基線與更早结果保留為各自來源的歷史證據。

**2026-10-03 00:45 歷史使用者指示與即時遊戲基線**：遊戲過程優先，存讀檔稍有停頓可以接受，舊保存 300ms／載入 500ms 不再作硬性追求目標；原功能與資料安全要求保留。正式 TerrainLab Crowd 5000 人的可沿用基線、完整逐幀 log、來源／硬體指紋、失敗與觀測干擾紀錄，集中在 [2026-10-03 遊戲基線](output/crowd_gameplay_baseline_20261003/README.md)。該輪有效版本為 probe v2／`run_1790959338`：8463 幀，待命 75.60／行軍 70.74／交戰 56.34／戰後 31.66 FPS，0 幀超過 100ms；自然命運、20 秒佇列清空觀察及實物守恆通過。**先讀紀錄與相關來源差異，沒有相關變更就沿用，不因換對話而例行重跑；不是整份 C2／C3、10k 或 release 通過。** 下方舊門檻及當時 FAIL 保留為歷史，不覆寫舊結果。

**2026-10-01 Native 核准後續結果（18:41；必要新build功能回歸完成，C3性能仍FAIL）**：使用者「繼續」核准的兩Native source修法、隔離build／test、正式DLL發布與獨立新D已落地。新DLL SHA `53fc43f50d9d672b2328e3ec1f2b5f426bc26ef8feba23ea9b04c3b4669b9c13`、build identity `e6a09c15bbc3f9a3035a709856bc39be3c5f1de7369e80245009d88aa330bd3f`；Native例外精確限定三條path，其他19條、原immutable D、Atlas／舊資產與正式16 Site／60 cache的保全核對及各實際時間見[新build實際證據](output/crowd_c2_c3_b_atlas_20261001/native_full_import_20261001_163744_009/IMPLEMENTATION_REPORT.md)。真正完整DR `170545_282` **PASS256.065s／5,417checks**，production SOURCE_STATE、自然命運／實物、全B、普通動作／完整保存載入／首幀與再D5均通過；ordinary新程序 `171106_463` PASS17.734s／10checks。新build B7兩輪真GPU rollback各182checks、B11完整56,015checks／新程序11、ammo escape67／death58及所列普通回歸通過。最終C252 B10 `181941_690` **PASS541.803s／14,946checks**，本次82d696成功保存基準的ordinary新程序 `183033_535` PASS20.240s／11checks、完整450tick MOVE新程序 `183144_947` **PASS463.446s／14checks**；沒有沿用不同07058／0286來源的舊診斷。原完整MOVE保存／載入必要正向保留；4758新普通死亡後的晚期BUSY只作額外原SaveGuard／state／queue／items／file SHA保全負向。既有ammo與B10的test-only fixture由固定V3 exact兩路徑manifest及P0／pre-Native／intermediate／final四層證據保護，所有先前FAIL與manifest保留。新DLL GPU C3 `171228_318` **35功能／artifact通過，2性能FAIL**：完整保存 **1,109.138ms**／fresh載入 **6,775.413ms**超過原300／500ms，938,895bytes通過4MiB；600步hash／A／C／全座標、IDs／cold refs／拘押／items及真GPU首幀通過。本輪收兵B功能及Atlas去重／重驗發布／正式runtime安裝／GPU抽樣範圍已完成；**整份v8、C3性能與正式10k release仍未通過**。最後sourceaudit／current-only census／canonical封存的actual結果與時間集中在上述新報告；本段先於sourceaudit固定，SOL不在audit後改寫。下方15:51與更早敘述、當時未套用提案、old-build B9 SOURCE_STATE及舊C3942.570／6,140.111ms FAIL均保留作歷史，舊DLL PASS不計入新DLL。

- **第 8 版**，2026-10-01。第 2 版依第一次審閱修正八個問題與四項小修正；第 3 版依第二次審閱再修正十個問題，另補一項自查發現（原生命令不驗證參數）；第 4 版依第三次審閱再修正九個問題與一個測試設定矛盾，另外自行對照程式碼再修正十二項；第 5 版依第四次審閱再修正七項，並把所有待決事項集中到 §9.1；第 6 版依第五次審閱再修正五項施工缺口與一項測試文字；第 7 版依第六次審閱再修正兩項規則與一項驗收缺口；第 8 版依第七次審閱修正一項測試期望與一項施工前提。各版的修正對照見文末附錄。
- **對象**：接手做 C2（命令、人物交接、事件回寫）和 C3（存檔讀檔）的 AI 助理。
- **專案**：`D:\worldgoing`，Godot 4.7.2 mono，以 git 管理。
- **上層計畫**：`SITE_CROWD_10K_PLAN_SOL.md`。

**2026-10-01 施工狀態補充（15:51，Asia/Taipei）：使用者選定的收兵 B 與 Atlas 優化已施工。B7／B10／B11 與所列新程序通過；B9 再部署因 Native SOURCE_STATE 仍未通過，收兵 B 尚未完整驗收。Atlas 去重、重驗發布、正式 runtime 安裝與 GPU 抽樣通過，C3 性能 FAIL。** 範圍依 [後續施工計畫](SITE_CROWD_10K_C2_C3_FOLLOWUP_PLAN.md)，最後完整 DR／GPU 回滾／D9／最大普通容量／新程序及 C3 結果見 [本輪報告](output/crowd_c2_c3_b_atlas_20261001/IMPLEMENTATION_REPORT.md)。收兵位置條款按已核准 B 修正；其餘功能、600 步完整存讀重播、300／500 ms／4 MiB 及正式 release 門檻保持。C3 同版 `154219_416` 完整保存／載入 **942.570／6,140.111 ms**，兩項性能 FAIL、912,031 bytes 通過大小門檻；完整第 8 版仍須原剩餘關卡，不能把分項 PASS 當作整體通過。Native 兩檔 patch 只備妥供例外審閱，尚未套用。

這份文件同時是**施工規格**和**測試規格**。每一項功能都要先寫好測試，並且跑過，才算完成。完成後照第 9 節的格式回報數字。

**標示「決策」的項目要先請使用者確認，確認後才能寫程式。**

---

## 0. 現況（C1 已完成）

### 0.1 群眾模式是什麼

原生群眾模擬器 `ArmyCrowd`（C++17、GDExtension）取代 TerrainLab 裡由 `TerrainArmy` 負責的戰鬥。

- **只在 `--crowd` 參數下生效**：`Godot --path D:\worldgoing -- --crowd`。**不帶參數時，遊戲必須和原本完全一樣**，這是所有測試共用的回歸關卡。
  - **唯一的例外（決策 D9）**：不帶參數時讀到含群眾的存檔，遊戲會**自動切換成群眾模式**再讀。見 §6.4。
  - 自動切換只持續到這場群眾戰鬥收兵為止。收兵後，新的部署回到啟動時的模式。
- **使用者決策（不可更動）**
  - 玩家是群眾中的一名士兵，所有士兵規則都適用。只有「想往哪走」和「要不要出手」來自輸入：WASD 走、Shift 跑、按住空白鍵在攻擊距離內交手。
  - 擊暈先於死亡。倒地後每遊戲小時 −25 HP，直到被救或被俘。
  - 救傷兵預設找 8 格內；AI 隊伍自動俘虜 8 格內的倒地敵人。
  - 單機，不做 lockstep。確定性只要求：同一個 build、同樣的輸入，得到同樣的結果，而且不受執行緒數影響。

### 0.2 檔案地圖

| 路徑 | 內容 |
|---|---|
| `native/crowd10k/src/*.cpp, *.hpp` | 原生核心：`crowd_core`（步進、移動、推擠）、`combat`（交手、射擊、救援、俘虜）、`command`、`ai`、`state`（存讀、匯入匯出）、`render` |
| `native/crowd10k/godot/crowd10k_gdext.cpp` | Godot 綁定（類別 `ArmyCrowd`） |
| `native/crowd10k/bin/crowd10k.windows.x86_64.dll` | 遊戲載入的 DLL（MinGW 靜態建置） |
| `native/crowd10k/tests/scenario_tests.cpp` | 原生規則測試（目前 195 項全過） |
| `scripts/terrain_lab/crowd_site.gd` | 群眾模式控制器：部署、步進、繪製、玩家呈現、即時面板 |
| `scripts/terrain_lab/terrain_lab.gd` | 群眾模式的掛鉤，全部以 `if crowd_site != null and crowd_site.active` 開頭 |
| `scripts/tests/crowd10k_*_bench.gd` | P2 各階段的測試腳本 |
| `native/crowd10k/run_*.bat` | 給使用者雙擊執行的批次檔 |

### 0.3 C1 的掛鉤，以及 C1 留下的暫時行為

| 遊戲原本流程 | C1 的做法 |
|---|---|
| `TerrainLab._deploy_trial_teams` | `crowd_site.deploy(sides, formations)`，士兵站在遊戲找到的部署格上 |
| `TerrainLab._advance_combat` 每一步 | `crowd_site.step(elapsed, game_seconds, combat_left)`，接著 **`continue`** |
| `SiteRuntime.mark_combat` | 把 `crowd.combat_mark()` 轉交給它 |
| 移動輸入、Space、Shift | `crowd_site.set_input(...)`、`crowd_site.engage` |
| `TerrainLab._process` | `crowd_site.render(delta)` |
| `bind_terrain`、`clear_army` | `crowd_site.clear()` |

**C1 的暫時行為。C2／C3 必須把這些全部移除或取代，並用測試證明已經不存在：**

1. **跳過了每步的結算尾段。** `_advance_combat` 的群眾分支用 `continue` 跳過了這些呼叫：
   - `site_controller.settle_person_deaths`
   - `person_actions.settle_after_contacts`
   - `settle_supply_deliveries`
   - `team.settle_combat_command`
   - `check_family_death`

   就算人物查詢補好了，死亡倒數也不會執行（詳見 §4.3）。
2. **沒有從 Site 匯入人物狀態。** 玩家用固定裝備（鐵製長劍、皮甲、盾）加入群眾。部署的士兵不會建立任何實物紀錄：沒有 `item_state`、沒有 `cargo`，彈藥只存在原生陣列裡。
3. **清除時「恢復部署前」的狀態。** `crowd_site._end_player()` 會把玩家的 HP 和暈眩還原成部署前的值，這會讓傷亡不守恆。
4. **不存檔。** 讀檔或換場時，群眾直接被清掉。
5. **只記錄事件、沒有寫回。** 事件被 `drain_events()` 取出後就丟掉了。

### 0.4 `ArmyCrowd` 目前的方法

- **建置**
  - `setup(threads, seed)`
  - `set_terrain(w, h, heights, flags, ramp_edges, static_blocked, facility)`
  - `add_formation(team, cx, cy, facing, cols, spacing, troop, training) -> f`
  - `add_soldiers(f, person_ids, equip, roles, ammo) -> first_index`
  - `set_start_positions(first, xy)`
  - `finalize()`
- **決策權**：`set_hostile(a, b, bool)`、`set_order_owner(f, ai_owned)`、`set_ai(bool)`
- **命令**：`order(f, kind, gx, gy, x)`
  - kind：0 守位、1 移動（x 為朝向）、2 攻擊（x 為目標士兵**索引**）、3 撤退、4 追擊（x 為目標索引）
  - 這一層會拒絕對「AI 擁有」的隊伍下令。現在回傳 false；改版後回傳結果碼 `NOT_OWNER`（見 §3.1 的結果碼表）。這是底層的單一決策者保護，**不是**遊戲的 UI 規則。
  - **現況缺陷（必修，見 §3.1）**：通過權限檢查後，綁定一律回傳 true。原生的 `order_move/attack/hold/pursue/retreat` 都是 `void`，**不檢查**目標索引範圍、座標是否有限、目的地是否可走，也不檢查潰退規則。目標索引越界時會直接讀 `px[tp]`，屬於未定義行為。
- **步進**：`step(dt)`、`step_clock(dt, game_seconds, combat_left)`、`combat_mark()`
- **事件**：`drain_events() -> PackedInt64Array`，每 4 個值一筆：`[kind, person_id, other_person_id, formation]`。
  - kind 依序為：0 DEATH、1 KO、2 WAKE、3 RESCUED、4 CAPTURED、5 ESCAPED、6 SUCCESSION、7 COMMAND_LOST、8 ROUT、9 RALLY、10 SHOT。
- **`stats()`**：`PackedFloat64Array`，共 **40** 個值（以 `crowd10k_gdext.cpp` 的 `m_stats` 為準；測試開頭先斷言長度等於 40，不符就 GATE FAIL，避免索引錯位）。分成三組：
  - **A 組：規則計數（0–17）**，比較時要完全相同
    - 0 總數、1 存活、2 倒地、3 被俘、4 交手中、5 接敵中、6 潰退隊數
    - 7 死亡、8 失血死亡、9 擊暈數、10 交手次數、11 射擊
    - 12 救援完成、13 俘虜完成、14 非法格、15 非法邊、16 冷卻違規、17 深度重疊
  - **B 組：耗時（18–32）**，**永遠不比較**：18 上一步耗時、19 打包耗時、20–32 各階段耗時（hash、fields、command、ai、formation、contact、soldier、timers、exchange、ranged、actions、fatigue、compact）
  - **C 組：時鐘與其他計數（33–39）**，比較時要完全相同，**另列一行回報**：33 `combat_left`、34 `game_dt`、35 `time`、36 `tick`、37 潰退次數、38 逃脫次數、39 醒來次數
  - **注意**：`state_hash()` 包含 `tick`、`time`，但**不包含**統計計數、`combat_left`、`game_dt`。所以「雜湊相同」不能代替 A 組與 C 組的比較，三者都要比。
- **查詢**
  - `soldier_count()`、`state_hash()`
  - `soldier_view(i)`，共 15 個值：畫出的 x、y；方向；動作格；動作時間；hp；ko；狀態；被俘；**模擬** x、y；面向；目標；陣營；暈眩
  - `nearest_enemy(i, r)`、`standing_near(x, y, r)`
- **存讀**：`save_state()`、`load_state(bytes)`。格式代號 `KW02`，**只保證同一個 build 讀得回來**。**現有的 `load` 不安全**，見 §6.1。
- **玩家**：`set_host_control(i, bool)`、`host_input(i, vx, vy, run, engage)`

C API（`src/crowd_c_api.h`）已有、**但 Godot 綁定還沒有**的功能：

- `order_capture`
- `set/get_soldier_state`、`set/get_formation_state`
- `soldier_index(person_id)`、`get_formation`

需要時照 `crowd10k_gdext.cpp` 現有寫法補上：寫一個 `m_xxx(CALL_ARGS)`，再加一行 `add_method(...)`。

**RETURN 不是對外命令**：C API 和綁定都沒有 RETURN。它只在原生內部使用：追擊結束時（20 秒或 20 格），原生自動把隊伍切換成 RETURN（crowd_core.cpp 約第 527 行），讓隊伍回到出發點。本計畫**不新增**對外的 RETURN 命令。

### 0.5 建置

- **Windows DLL**（MinGW-w64）：
  `x86_64-w64-mingw32-g++-posix -O2 -std=c++17 -Wall -Wextra -shared -static -static-libgcc -static-libstdc++ src/crowd_core.cpp src/combat.cpp src/command.cpp src/ai.cpp src/state.cpp src/render.cpp godot/crowd10k_gdext.cpp -o bin/crowd10k.windows.x86_64.dll -Wl,--no-undefined`
- **原生測試**：
  - Linux：`cmake -B build && make -C build && build/crowd_scenario_tests`
  - Windows：`bin\crowd_scenario_tests.exe`，或在 VS 開發人員命令列執行 `build_msvc.bat`（/W3 /WX）。
- **編譯關卡**：`-Wall -Wextra` 零警告；MSVC 的 /W3 /WX 通過。
- **遊戲必須關閉才能替換 DLL**，否則檔案被鎖住。
- **Build 識別**：見 §6.2。每次重編都會改變識別，舊的群眾存檔就讀不回來。這是設計上的預期行為，不是錯誤。

---

## 1. 資料安全規則（一切測試的前提）

**測試絕不能改動使用者的正式存檔。**

正式存檔預設在 `user://sites/current.json`，由 `SiteStore.DEFAULT_PATH` 和 `SiteController.save_path` 決定。以下幾個地方也會寫入 `user://sites/`，同樣可能覆寫正式存檔：

- 每 30 秒的自動保存（`finish_tick`，只在脫戰時執行）
- `archive_before_replace()`，寫到 `user://sites/<site.id>.json`
- 離開遊戲時的保存對話框
- `_load_path` 的封存流程

**規則：**

1. **測試模式開關**：所有 C2／C3 的自動測試都帶 `--crowd-test <run_id>` 參數。`crowd_site`（或測試腳本）在**建立或載入任何 Site 之前**做完以下設定：
   - `site_controller.save_path = "user://sites/crowd_test/<run_id>/current.json"`
   - 測試產生的 Site 使用唯一的 `site.id = "crowd_test_<run_id>"`，封存檔因此只會寫進測試名稱。
   - 自動保存、封存、離開保存，全部改寫到 `user://sites/crowd_test/<run_id>/`。實作方式可以是集中一個「存檔根目錄」變數，不要逐處改路徑。
2. **前後快照關卡**：批次檔在啟動 Godot **之前**與**之後**，各列出 `%APPDATA%\Godot\app_userdata\<專案名>\sites\` 底下所有檔案的路徑、大小和 SHA-256，排除 `crowd_test\` 子目錄。前後有任何差異，就是 **GATE FAIL（資料安全）**。
3. **先備份**：批次檔開始前，把整個 `sites\` 資料夾**複製**（不是移動）到本輪輸出資料夾的 `backup_user_sites\`。
4. **需要用舊存檔、壞檔測試時**，只能用**複本**，放在 `user://sites/crowd_test/<run_id>/fixtures/`，絕不拿正式檔直接測。
5. **離開遊戲**：測試腳本用 `get_tree().quit(code)` 結束，不經過保存對話框。另外單獨寫一個 L2 項目，驗證在 `--crowd-test` 下按關閉視窗，對話框的保存目標也是測試路徑。

---

## 2. 測試分層與共通關卡

| 層級 | 在哪裡跑 | 用途 |
|---|---|---|
| **L0 原生規則測試** | `crowd_scenario_tests`（Linux 另外用 `-fsanitize=address,undefined` 跑一次） | 規則、存讀、確定性、壞資料 |
| **L1 替身場景測試** | 無頭或 xvfb 的 Godot，用替身的 lab 和 SiteController（只提供被呼叫的函式，並記錄參數） | 在沒有完整遊戲的地方驗證 `crowd_site.gd` 的邏輯 |
| **L2 正式場景自動測試** | 使用者電腦上的 `run_c2.bat`、`run_c3.bat`，以 `--crowd --crowd-test` 啟動正式 TerrainLab，用腳本操作 | 真正接上 SiteController、SiteStore、人物與實物 |
| **L3 手動遊玩清單** | 使用者照清單操作 | 手感、畫面、UI |

**執行規則：**

- **接手的 AI 自己在 Windows 跑 Godot 驗證時**，一律使用專案規定的 canonical helper：`godot-runtime-verify/scripts/verify_godot.ps1`。
  - 原樣使用，不可修改。
  - 它有執行逾時，結果保留在 `.godot-temp/godot_verify`，保留最新 100 次。
  - 需要引用某次舊結果時，先把那份 `result.json` 複製到本任務的 `output` 資料夾。
  - 規定見 `AGENTS.md`。
- **給使用者雙擊的批次檔**要做到以下幾點：
  - **有逾時**：用 PowerShell `Start-Process -PassThru` 啟動 Godot，再以 `WaitForExit(毫秒)` 等待，逾時就 `Kill()`，並記為 exit code 124。
  - **腳本自己也要有期限**：用 `create_timer(秒).timeout` 觸發 `quit(3)`，兩層逾時都要有。
  - **每一輪輸出寫到新資料夾**：`native/crowd10k/out_c2/<yyyyMMdd_HHmmss>/`（C3 用 `out_c3`），**絕不覆寫**先前的結果，失敗的證據要保留。
  - 每個輸出資料夾第一次建立時，放一個空的 `.gdignore`。
  - 路徑含 `(` 或 `)` 時，不要放在 `if (...)` 區塊內；檔案用 CRLF 換行。
- **每個測試腳本的結尾**
  - 印出 `GATE OK`，或 `GATE FAIL: <項目>`。
  - exit code：0 表示成功、2 表示關卡失敗、1 表示執行錯誤、3 表示腳本逾時、124 表示批次檔逾時。
- **失敗訊息**要印出第一個違規例子的具體數值，例如：哪位人物、哪個欄位、期望值是多少、實際值是多少。

**每一輪都必須通過的共通關卡：**

1. **原生測試**：0 failures。新功能要新增測試，並在測試名稱寫明對應本文件的哪一節。
2. **語法檢查**：`--headless --check-only --script` 逐一檢查所有改過的 `.gd`，不能出現 `SCRIPT ERROR` 或 `Parse Error`。
3. **模擬不變量**：`stats[14]`、`stats[15]`、`stats[16]` 都必須是 0。
4. **一般模式回歸**：不帶 `--crowd`，只帶 `--crowd-test` 以隔離存檔，然後：
   - 部署兩隊交戰，照 §2.1 場景 D 的原則設計成一定會脫戰（一強一弱、沒有弓弩）；脫戰後存檔、讀檔。
   - log 不能出現新的錯誤。
   - 行為要和改動前相同。
5. **沒有崩潰**：log 裡不能有 `CrashHandlerException`。萬一出現：
   - 用同一份原始碼加 `-g` 重編一份 DLL。
   - 用 `x86_64-w64-mingw32-addr2line -f -C -e dbg.dll <ImageBase + 偏移>` 找出原始碼行號。
6. **資料安全**：§1 的前後快照完全一致。
7. **效能**：5,000 人、debug 編輯器執行檔，每幀平均 ≤ 12 ms、p99 ≤ 25 ms（C1 約 8～9 ms）。C2／C3 新增的每步成本要單獨量，目標 ≤ 0.3 ms。

### 2.1 標準測試場景

**不要用「全軍 MOVE 後退就會脫戰」當前提。** MOVE 在接敵時會停步（`crowd_core.cpp` 約第 543 行，encounter pause），潰退的隊伍又會拒絕 MOVE，所以雙方各自後退不保證能脫戰。需要脫戰的測試一律用下面的**場景 D**。

| 場景 | 用途 | 內容 |
|---|---|---|
| **場景 B（大戰）** | 效能、事件量、命令 | 25＋25 隊，全部 AI，有弓兵隊，自動俘虜開啟。**不要求脫戰。** |
| **場景 D（可脫戰）** | 需要脫戰才能做的檢查：存檔守門、自動保存、讀檔、`_pending_deaths` 清空 | 見下 |
| **場景 DR（可脫戰，含弓兵）** | §4.2 的交接往返測試；全場物品守恆（計入射擊） | 場景 D 的變體，差別見下 |

**場景 D 的規格：**

- **強方**：AI 開啟，有訓練，有武器與甲，**全部近戰**。
- **弱方**：手動、守位，訓練 0，無甲，**全部近戰**。
- **雙方都沒有弓弩隊**，所以不會有「箭矢仍在飛行」卡住存檔。
- **人數**：總人數 ≥ 5,000，強弱約 4：1；玩家在強方，不給輸入。
- **固定種子**，照同一個 build 的確定性，結果可以重現。
- **玩家所在的隊伍設為手動**（不是 AI），在後方守位，不參戰，讓讀檔後的主控檢查有意義。強方其餘隊伍都是 AI。玩家如果仍然倒地或被俘，就 GATE FAIL，並調整場景。

**場景 D 的脫戰判定：**

- 弱方全部倒地、死亡或被俘後，沒有新的有效命中，`combat_left` 會歸零。
- 脫戰的定義：`combat_left <= 0`，而且 `supply_save_guard()` 回傳 ok。
- 達到脫戰後，**立刻**做需要脫戰的檢查。原因：倒地的人醒來後可能重新接敵。
- **期限**：300 秒遊戲時間內沒有脫戰，就 GATE FAIL，並印出擋住的項目：`combat_left`、擋住存檔的守門碼，以及仍在交手的人數。
- **場景要先在 L1 校準**：同一個種子要穩定脫戰。L2 沒有脫戰時，要調整場景參數，例如強弱比，**不能**放寬期限或跳過檢查。

**場景 DR 和場景 D 的差別：**

- **強方多一支弓兵隊**，在後方守位射擊。其中一名弓兵就是 §4.2 往返測試裡「帶 7 支箭」的那位。
- 弱方仍然全部近戰。
- **脫戰判定相同**。弱方全倒之後就沒有射擊目標，飛行中的箭落地後，「箭矢仍在飛行」的守門就會解除，所以一樣能在期限內脫戰。
- **物品守恆要計入射擊**：已消耗彈藥 = SHOT 事件數。
- **收兵的前提**：已經脫戰，沒有飛行中的箭，`_pending_deaths` 和 §4.4 的俘虜寫回佇列都是空的。

---

## 3. C2-A：命令

### 3.1 規則（先照遊戲原本的程式碼定義清楚）

**兩層權限要分開：**

- **底層**：`ArmyCrowd.order()` 對 AI 擁有的隊伍回傳 `NOT_OWNER`。這一層只是保護，不讓 AI 和宿主同時下令。
- **UI 層**：照遊戲原本的規則。`TerrainArmy._issue_combat_order` 成功提交後，會呼叫 `_stop_tactical_ai()`（terrain_army.gd 約第 3747 行）。也就是說，**人工命令一旦成功，AI 就改成停用**。群眾模式的 UI 流程是一筆交易：
  0. **宿主預檢**：照遊戲原本的流程先檢查，例如 MOVE 先經過 `_formation_move_candidate`（site_controller.gd 約第 1019 行）。預檢失敗就直接顯示結果並結束，**不碰 AI 旗標，也不呼叫原生**。
  1. 讀取並保存**原本的**旗標：`was_ai = crowd.order_owner(f)`（需要時補這個查詢綁定）。
  2. 如果 `was_ai` 為真，暫時 `set_order_owner(f, false)`；原本就是手動的隊伍，這一步不做任何事。
  3. 執行 `order(...)`，取得結果碼。
  4. 成功：保持手動，更新 UI 的 AI 狀態為「停用」。
  5. 失敗：**恢復成原值** `set_order_owner(f, was_ai)`。**不可以一律設回 AI**，否則原本手動的隊伍會在命令失敗後被改成 AI。失敗時，隊伍狀態不得有任何改變：前後 `state_hash` 相同，旗標也和原值相同。

**原生命令要能回報失敗（必修，自查發現）：**

- **結果碼統一如下**。原生、C API（`crowd_c_api.h`）、Godot 綁定、GDScript、測試，一律使用這張表：`0` 表示成功，**任何非零值都表示失敗**。任何一層都不能再用 bool 表示命令結果；測試要比較**確切的碼**，不能只看「是否為真」。

  | 碼 | 名稱 | 意義 | 對應的遊戲訊息碼 |
  |---|---|---|---|
  | 0 | `OK` | 成功 | |
  | 1 | `NOT_OWNER` | 隊伍由 AI 擁有，宿主不能直接下令 | （只出現在底層；UI 流程會先接管） |
  | 2 | `BAD_FORMATION` | 隊伍索引越界 | `NO_TARGET` |
  | 3 | `BAD_ARGS` | 種類不存在、座標不是有限值 | `NO_TARGET` |
  | 4 | `NO_TARGET` | 目標越界、不能行動、PURSUE 超過 20 格 | `NO_TARGET` |
  | 5 | `BLOCKED` | 目的地在地圖外或走不到 | `BLOCKED` |
  | 6 | `NOT_ROUTED` | 沒有潰退卻下 RETREAT | `NOT_ROUTED` |
  | 7 | `ROUTED` | 潰退中下 MOVE、ATTACK、PURSUE | `ROUTED` |
  | 8 | `NO_ORDERS` | 一人隊伍（§4.1 第 7 項）不接受隊伍命令 | （UI 清單不列出一人隊伍，正常不會出現） |
  | （無） | `NO_AUTHORITY` | 下令者不是當前隊長或沒有指揮資格。**只在 GDScript 端使用**，不是原生碼 | `NO_AUTHORITY` |

- **檢查順序要固定**，因為同一個輸入可能同時違反好幾條，例如已潰退又目的地不可走。測試比較確切的碼，所以順序必須明訂：
  - **原生 `host_order()`**：`BAD_FORMATION` → `NOT_OWNER` → `BAD_ARGS` → `NOT_ROUTED` → `ROUTED` → `NO_TARGET`／`BLOCKED`。
    - `NO_ORDERS` 排在 `BAD_FORMATION` 之後、`NOT_OWNER` 之前。
    - 目前的 `host_may_order` 對越界的 f 也回傳 false（crowd_core.hpp 約第 321 行），改版後越界的 f 必須回傳 `BAD_FORMATION`，不能回傳 `NOT_OWNER`。
  - **GDScript UI 流程**：照遊戲 `_issue_combat_order` 的順序（terrain_army.gd 約第 3570–3587 行），也就是 `NOT_ROUTED` → `NO_AUTHORITY` → `ROUTED` → `BLOCKED`／`NO_TARGET`。

- **對外 API 與內部呼叫要分開**（依第三次審閱第 5 項）：
  - **對外**：新增 `host_order(f, kind, gx, gy, x) -> int`。它先檢查全部條件，通過後才呼叫內部函式。綁定的 `order()` 和 C API 都只能走這一條路。
  - **內部**：`order_move`、`order_retreat` 等函式保持原本的行為，照舊用 `set_goal` 把座標**裁切**到地圖內。內部呼叫者繼續直接使用它們，**不經過**對外檢查。內部呼叫者包括：`begin_rout`、AI、追擊結束的返回。
  - **原因**：`begin_rout`（command.cpp 約第 146 行）先設定潰退、送出 ROUT 事件，然後才算出「後方 25 格」的座標。這個座標在地圖邊緣可能落在地圖外，目前靠 `set_goal` 裁切。如果它改走對外檢查，就可能出現「已經標記潰退，卻沒有送出撤退命令」。
  - 實作時要列出所有內部呼叫點，確認沒有任何一處改用對外檢查。
- **對外檢查**在**改動任何狀態之前**，檢查以下項目：
  - `f` 在範圍內；
  - 目標索引在 `0..n-1`，而且目標可行動；
  - 座標是有限值，並且在地圖內；
  - 目的地可以走到；
  - 潰退規則：未潰退的隊伍不能 RETREAT；潰退中的隊伍不能 MOVE、ATTACK、PURSUE。
- 檢查失敗時直接回傳對應的碼，**不改動任何狀態**。
- 宿主端 UI 流程把非零碼換成遊戲的訊息碼（上表最右欄）後顯示；`NOT_OWNER` 不應該出現在 UI 流程中，出現就算錯誤。
- 宿主端（GDScript）先把索引、距離、目標是否存在查清楚，對應到遊戲的訊息碼。原生層的檢查是最後一道防線。
- 不能只靠宿主端檢查，因為越界索引會讓原生讀到陣列外的記憶體。
- **下令者資格**：遊戲要求 `requester == current_commander` 而且 `command_eligible`（`_issue_combat_order`）；AI 開關也一樣（`set_tactical_ai_enabled`）。群眾隊伍要用自己的指揮者資料做同樣的檢查，不符合時回傳 `NO_AUTHORITY`。

**各命令的對照：**

| 遊戲命令 | 遊戲的規則（程式碼位置） | 群眾的做法 |
|---|---|---|
| HOLD | 一般 | `order(f, 0, …)` |
| MOVE | 目的格加朝向；`_formation_move_candidate` 會先驗證 | `order(f, 1, gx + 0.5, gy + 0.5, 朝向角)`。目的地非法時回傳 `BLOCKED`。 |
| ATTACK | **UI 傳入的 `target_id` 是 `-1`**（`_trial_team_order` 約第 1024 行），由隊伍自己挑目標 | 下令當下以隊長為基準，用 `nearest_enemy` 挑最近的可行動敵人，再 `order(f, 2, …, 目標索引)`。沒有敵人時回傳 `NO_TARGET`。 |
| PURSUE | 只有 PURSUE 取得目標 ID（`_selected_enemy_identity`）；必須在指揮參考點 20 格內（約第 3585 行） | person_id 先換成士兵索引，再檢查 20 格；不符合時回傳 `NO_TARGET` |
| RETREAT | **只有士氣崩潰時才可以**：`NOT_ROUTED`「士氣尚未崩潰，隊長不能下令撤退」，崩潰時走 `begin_morale_retreat()`（約第 3570 行） | 隊伍沒有潰退時回傳 `NOT_ROUTED`；已潰退時走群眾的潰退流程。**「任意退到後方 15 格」不是撤退，要用 MOVE。** |
| 潰退中的 ATTACK／PURSUE／MOVE | 回傳 `ROUTED`「隊伍尚未完成安全整補…」 | 同樣拒絕 |
| RETURN | 追擊結束後的返回 | 不是對外命令。原生在追擊結束時自動切換（見 §0.4），宿主不下這道命令 |
| AI 開關 | `_trial_team_ai` → `set_tactical_ai_enabled(requester, enabled)` | `set_order_owner(f, enabled)`，加上下令者資格檢查 |

**UI 清單**：群眾模式下，`trial_command_team` 的隊伍清單要列出群眾的隊伍。來源是 `crowd_site` 的「UI 槽位 → 群眾編隊」對照表，不是空的 TerrainArmy 槽位。

### 3.2 L0 原生測試（新增）

- `order` 對 AI 擁有的隊伍回傳 `NOT_OWNER`（1），而且 `state_hash` 不變。
- **RETREAT 的合法條件是 `routed` 旗標，不是士氣數值**：
  - 沒有潰退的隊伍被拒絕，回傳 `NOT_ROUTED`，狀態不變。
  - 只把士氣調低**不會**讓 RETREAT 變成合法：`routed` 仍然是 false。下一步 `sustain_stage` 會自己開始潰退（command.cpp 約第 207 行），宿主的 RETREAT 就看不出效果。
  - 正確做法：用 `set_formation_state` 同時設定 `routed = 1`、士氣低於 `MORALE_ROUT`，然後下 RETREAT。
- **已潰退時的 RETREAT**：回傳 `OK`。原生用和 `begin_rout` 相同的內部計算（包括裁切），重新產生後撤目的地；隊伍的移動方向遠離最近的敵人。
- **潰退隊伍**：MOVE、ATTACK、PURSUE 都被拒絕。
- **PURSUE**：目標超過 20 格時被拒絕；原有的追擊限制測試（20 秒、20 格）照舊通過。
- **RETURN（自動）**：下 PURSUE 後讓追擊超過 20 秒，或超過 20 格。隊伍自動切換成 `order == RETURN`，並在期限內回到出發點 1.5 格內。
- **錯誤參數**：目標索引為 −1、n、`INT_MAX`，NaN 與無限大座標，地圖外座標，不可走的目的地。每一種都回傳**表中對應的碼**（逐一寫出期望值），`state_hash` 不變。這一項要在 ASan、UBSan 下各跑一次。
- **C API 與綁定的傳遞**：同一組錯誤參數分別經過 C API 和 Godot 綁定呼叫，得到的碼要和直接呼叫原生完全相同。
- **地圖邊緣的自動潰退**（第三次審閱第 5 項）：把隊伍放在地圖角落，最近的敵人在內側，讓它士氣崩潰。
  - 通過條件：隊伍 `routed` 為真，`order == RETREAT`，目的地在地圖內，並且隊伍中心確實往遠離敵人的方向移動。
  - 地圖的四個角落和四條邊各做一次。

### 3.3 L1 替身場景測試（`scripts/tests/crowd_c2_orders_check.gd`）

部署 4 隊，2 對 2，**全部非 AI**。每一步都要有數值門檻：

| 步驟 | 動作 | 通過條件 |
|---|---|---|
| 1 | 第 1 隊 MOVE 到 20 格外 | 25 秒內隊伍中心到目標 ≤ 1.5 格，命令轉回 HOLD；非法格、非法邊都是 0 |
| 2 | 第 2 隊 HOLD，敵人在 6 格外 | 20 秒內隊伍中心位移 ≤ 1.5 格 |
| 3 | 第 1 隊 ATTACK（不指定目標） | 選到的目標是當下最近的可行動敵人；20 秒內交手次數增加 > 0 |
| 4 | 第 3 隊 PURSUE 一名 25 格外的敵人 | 回傳 `NO_TARGET`，狀態不變 |
| 5 | 第 1 隊 RETREAT，士氣正常 | 回傳 `NOT_ROUTED`，狀態不變 |
| 6 | 用 `set_formation_state` 把第 2 隊設為 `routed = 1`、士氣低於 `MORALE_ROUT`，再下 RETREAT | 回傳 `OK`；10 秒內與最近敵人的距離增加 ≥ 5 格。再對它下 MOVE，回傳 `ROUTED` |
| 7 | 第 4 隊改成 AI，再透過 UI 流程下 MOVE | 成功；之後第 4 隊的 AI 為停用（接管） |
| 8 | 第 4 隊重新開 AI，再用**底層** `order()` 直接下令 | 回傳 `NOT_OWNER`（1），狀態不變 |
| 9a | UI 流程對 **AI 隊**下 MOVE，目的地非法 | 宿主預檢回傳 `BLOCKED`；原生 `order` **沒有被呼叫**（用呼叫計數確認）；AI **維持開啟**；`state_hash` 不變 |
| 9b | 同上，但對**手動隊**（第 1 隊） | 同上；AI **維持關閉** |
| 9c | 用測試專用掛鉤讓**原生**回傳 `BLOCKED`，對 AI 隊走完整的 UI 流程。這是只有原生才能發現的失敗，用來測交易的還原路徑 | 回傳 `BLOCKED`；AI 旗標**還原成開啟**；`state_hash` 不變 |
| 9d | 同 9c，但對手動隊 | AI 旗標**維持關閉** |
| 10 | 錯誤參數：隊伍 −1、目標不存在、NaN 座標 | 不崩潰；分別回傳 `BAD_FORMATION`、`NO_TARGET`、`BAD_ARGS`；狀態不變，AI 旗標不變 |

輸出 `orders.json`：每一步的時間序列，包含隊伍中心、命令、AI 旗標、交手數、回傳碼。

### 3.4 L2 正式場景自動測試（`run_c2.bat` 第一段）

- 以 `--crowd --crowd-test` 啟動，透過 `site_controller._deploy_trial_armies()` 部署 25＋25 隊，**全部 AI**。
- 下令的方式：用 UI 的 `trial_command_team` 選隊，呼叫 SiteController 的 UI 函式，也就是 `_trial_team_order`、`_trial_team_ai`、朝向拖曳的完成函式，不直接呼叫 crowd。
- 使用 §2.1 的場景 B。
- 因為是全 AI 部署，第一道人工命令就是「接管」，接管成功之後 AI 必須為停用。
- 步驟 9b 使用已經被接管的隊伍，確認失敗的命令不會把它改回 AI。
- **L2 只跑 3.3 裡能透過 UI 函式表達的步驟**：1、2、3、4、5、7、9a、9b。
  - 以下步驟**只在 L0、L1 跑**：
    - 6：需要 `set_formation_state`
    - 8：需要直接呼叫底層 `order()`
    - 9c、9d：需要測試掛鉤
    - 10：需要錯誤參數
  - L2 **不直接呼叫 crowd**。
- **判斷訊息的規則**：每一步都預先寫好**預期的回傳碼**。成功的步驟，`show_result` 不能是錯誤；預期會被拒絕的步驟，訊息碼必須**完全等於**預期值，例如 `NOT_ROUTED`。出現其他錯誤就是失敗。
- **另外兩項檢查**：
  - UI 隊伍清單的項目數等於部署隊數，**不算一人隊伍**（§4.1 第 7 項）。
  - 每道命令之後，UI 顯示的 AI 狀態和 `set_order_owner` 的實際值一致。
- **截圖三張**：下令前、MOVE 途中、交戰中。

### 3.5 L3 手動清單

- 從清單選一支隊伍，按「進攻」「移動」「守位」，有反應，動作合理；按「撤退」時，士氣沒崩潰會顯示「士氣尚未崩潰…」。
- 拖曳指定方向的移動：隊伍抵達後面向拖曳的方向。
- 開關 AI 時，按鈕與提示正確；對 AI 隊人工下令成功後，AI 顯示為停用。

---

## 4. C2-B：人物與實物交接、事件寫回

### 4.1 人物紀錄與引用（決策項目，先定案再施工）

目標：**傷亡與物品守恆**。每一名人物在 Site 裡只有**一筆紀錄**；其他地方只放 person_id 的**引用**。每一件實物在任何時刻都只有一個位置。

**名詞：**

- **紀錄**：人物冷資料的唯一權威位置，例如身分、裝備實物、長期狀態。
- **目前引用**：只存 person_id，指向一位**目前存在**的人物，**必須**解析到恰好一筆紀錄。
- **歷史來源 ID**：只記錄「這樣東西曾經屬於誰」，例如實物或地上遺物的原持有者、遺物的死者編號、贖金與供養的歷史。這類 ID **不要求**仍有紀錄，只要求 `0 < id < next_person_id`。
  - 原因：遊戲本身就會留下沒有紀錄的歷史 ID。例如退休工人流程（site_store.gd 約第 339 行起）會把工人的物資留在地上，然後刪掉 `actors.npc`；這是合法的舊存檔。
  - 死者也一樣：死者的紀錄是否保留，照遊戲原本的規則，群眾不另外規定。
- **受控人物**：`controlled_person_id()` 所指的人，也就是群眾裡由輸入控制的那名士兵。**它不一定是 `actors.player`**：家族接續（site_controller.gd `_control_family_person` 約第 3611 行）可以改為控制 NPC 或隊伍名冊裡的人。見決策 D5、D6。

**遊戲原有的慣例（群眾照用）**：

- 原玩家角色的紀錄在 `actors.player`，由 `lab.character.capture_state()` 產生。
- 原玩家角色所在的隊伍，快照裡只用 `player_member: {id, present, goal}` 引用他，**不另存一份**（terrain_army.gd `capture_combat_state` 約第 6979 行）。

**各位置的性質：**

| 位置 | 性質 | 內容 |
|---|---|---|
| `actors.player` | 紀錄 | 原玩家角色（群眾模式也一樣） |
| `actors.npc` | 紀錄 | 工人 |
| 群眾人物紀錄：`site.armies` 裡標記 `"crowd": true` 的 roster（D1） | 紀錄 | 玩家以外的群眾士兵 |
| `site.armies` 裡的一般 roster | 紀錄 | 非群眾的 TerrainArmy 成員 |
| `site.crowd.teams[].person_ids` | 目前引用 | 每隊成員，**包含受控人物** |
| `site.crowd.player` | 目前引用 | `{person_id, soldier_index}`，指受控人物 |
| 原生 blob 裡的 `person_id` 陣列 | 目前引用 | 每個原生索引對應的人物 |
| `site.captivity` 的鍵、`captor_id`、`guard_id` | 目前引用 | 看守者已死亡時，照遊戲原本的規則處理 |
| 實物與地上遺物的原持有者、遺物的死者編號、贖金與供養的歷史 | **歷史來源 ID** | 不要求有紀錄 |

**唯一性規則（§6.3 的驗證照這個寫）：**

1. 每個 person_id 在所有「紀錄」中**恰好出現一次**。
2. 每個「**目前引用**」都必須解析到恰好一筆紀錄。「**歷史來源 ID**」只檢查 `0 < id < next_person_id`。
   - 驗證程式裡，這兩類要用**兩張明確的欄位清單**分開列出。
   - 遇到不在任何一張清單裡的 ID 欄位，就讓測試失敗，不要猜它屬於哪一類。
3. 原生 blob 的 person_id 陣列：
   - 每個 id 最多出現一次。
   - 每個 id 都恰好屬於 `crowd.teams` 的一隊；反過來，`crowd.teams` 的每個 id 也都在原生陣列裡。
4. **受控人物**：
   - `site.crowd.player.person_id == controlled_person_id()`，而且原生索引 `soldier_index` 的 person_id 等於它。
   - 它的紀錄位置照決策 D5 解析，**不假定**在 `actors.player`。
   - 群眾隊伍裡只有引用。
5. **標記 `crowd` 的 roster 絕不能被建立成 TerrainArmy**。一般模式讀到含群眾的存檔時，照 D9 先自動切換成群眾模式；任何路徑都不能把這些 roster 交給 TerrainArmy 的載入流程。

**熱狀態的權威：**

- **戰鬥中**，原生是權威：位置、HP、暈眩、KO、被俘，以及 §4.2 表格裡的其他欄位。
- **紀錄**只在固定的**同步點**寫回：事件結算、收兵、存檔前。

**需要使用者決定**（下面的 1～7 對應 §9.1 的 D1～D6 與 D10；D7～D9 見 §4.4、§6.4、§6.6。已決定的項目有標示）：

1. **群眾人物紀錄放哪裡**（**已決定：D1 = (a) 放進 `site.armies`**）：
   - (a) 放在 `site.armies`，用 roster schema 2，並加上 `crowd` 標記。現有的人物、裝備、拘押驗證可以直接使用。
   - (b) 另外新增 `site.crowd_people`，同時擴充 `SiteStore` 收集人物的地方（`_validate_captivity` 目前只從 actors 和 armies 收集，site_store.gd 約第 1660 行）。
2. **實物**（**已決定：D2 = 每人都建立**）：部署時，照遊戲原本的 `SiteController.initialize_team_items` 為每名士兵建立 `item_state` 和 `cargo`（`Runtime.seed_person_equipment`、`reconcile_cape_roles`、`equipment_changed`）。持有者是那位人物的 person_id。
3. **彈藥**（**已決定：D3 = 戰鬥中以原生為準**）：同步規則見 §4.4。
4. **群眾作戰期間，`person_actions` 的其他工作**，也就是搜刮、拘束、解綁、換裝、贖回、逃脫，以群眾人物為對象時怎麼辦：
   - **已決定：D4 = 戰鬥中一律拒絕**，回傳 `CROWD_ACTIVE`，訊息為「群眾戰鬥中由戰場規則處理」。
   - 收兵後照一般流程處理。
5. **受控人物不是原玩家角色時**（**已決定：D5 = 這版就支援**），例如家族接續後控制了 NPC 或名冊裡的人：
   - 部署前用 `lab._combat_target(controlled_person_id())` 解析紀錄位置；裝備與 cargo 用 `_person()` 的同一套規則取得。分成三種：

     | 受控人物 | 紀錄位置 | cargo | 在群眾裡的位置 |
     |---|---|---|---|
     | `lab.character` | `actors.player` | `site.manual.cargo` | 和 C1 一樣：自己一個小隊伍，隊形以他為中心 |
     | `lab.npc` | `actors.npc` | `site.worker.cargo` | 同上 |
     | 名冊裡的人 | 照 D1 放在群眾人物紀錄 | 他自己的 `cargo` | 留在原本的隊伍裡，**只有他自己**改由輸入控制，隊伍照常行動（見下） |

   - **只有一人隊伍以受控人物為中心**（第五次審閱第 3 項）：
     - 目前原生的隊形流程（crowd_core.cpp 約第 497 行）只要在隊伍裡找到受控成員，就把**整隊**的中心和目的地改成他的座標，並跳過正常的命令流程。名冊裡的人受控時，原隊如果正在 MOVE，下一步就會失去原本的目的地。
     - **修法**：原生新增每隊的「以受控人物為中心」旗標，只有一人隊伍（`solo`）設定。其他隊伍裡的受控成員，只是**他個人**的移動和出手改由輸入決定；隊伍的中心、目的地、命令、AI 都照常。
     - 受控成員在一般隊伍裡保留自己的 slot，其他隊員照常補位。
     - **驗收**：一支隊伍正在 MOVE 往 20 格外，接續（或部署）時讓隊伍側邊的一名隊員受控。之後 10 秒內：
       - 隊伍的目的地和命令不變；
       - 其他隊員繼續朝原目的地移動，隊伍中心到目的地的距離持續縮短；
       - 受控隊員照輸入移動。

   - **以紀錄的種類來決定冷資料放哪裡，不是以「是否受控」來決定**：只要紀錄是 actor（`lab.character` 或 `lab.npc`），不管現在有沒有受控，他在群眾裡的冷資料一律讀寫 actor 物件本身。原因是控制權可能在戰鬥中換人（D6）。
   - 寫回時寫到同一個位置。
   - **三種情況都要有往返測試與存讀測試。**

6. **戰鬥中受控人物戰死，換繼承人**（**已決定：D6 = 戰死就立刻換繼承人**）：
   - 受控人物一戰死，就照遊戲原本的方式**暫停並跳出家族視窗，由使用者選繼承人**（已確認：照原本的流程）。群眾戰鬥不等收兵，也不強制收兵；選好後戰鬥繼續。
   - **遊戲原本的兩個等待要調整**：
     - `check_family_death` 在 `_pending_deaths` 不是空的時候會直接返回（site_controller.gd 約第 3639 行）。大戰中別人的死亡結算幾乎一直存在，照原樣視窗會一直不出現。
     - 群眾模式下改成：**只等受控人物自己的倒地與死亡結算完成**，不等其他人。
     - `_open_family` 會暫停遊戲並開啟視窗（約第 3656–3664 行），這部分照舊。視窗裡「繼續原場景，等待脫戰安全歸檔後再選」的選項也照舊保留。
   - **這個版本的繼承人一定在同一個 Site**。群眾運行中如果遇到不在同一 Site 的接續（`source.local` 為 false），回傳 `UNSUPPORTED`，訊息寫明「群眾戰鬥中不支援跨 Site 接續」，而且不能歸檔、不能清除群眾。之後的版本再處理跨 Site。
   - **同一 Site 的接續**（site_family_continuity.gd 約第 184 行）不經過歸檔，也不清除群眾。群眾端要掛在「受控人物改變」這個時間點上，例如 `_control_family_person` 設定 `controlled_person_id` 之後，呼叫 `crowd_site.on_control_changed(舊, 新)`，處理方式如下：
     - **舊的受控士兵**：`set_host_control(舊, false)`。如果他在一人隊伍裡，這支隊伍的「以受控人物為中心」旗標也清掉。
     - **繼承人就在群眾裡**：`set_host_control(繼承人, true)`，輸入從下一步起送給他。他所屬隊伍的 AI 旗標和命令擁有權**不變**。
     - **繼承人在同一 Site，但不在這場群眾戰鬥裡**，例如留在營地的 NPC：見決策 D10。
   - **任何時刻，原生裡受控的士兵最多只有一名。**

7. **場外繼承人**（**已決定：D10 = 身分不變，可以自由操作，敵對的人照樣會攻擊他**）：
   - 他的身分、陣營、所屬隊伍、紀錄位置**全部不變**。他**不會**被編進任何群眾隊伍，名冊也不改。
   - 但是敵對的人要能攻擊他，他也要能反擊，所以他必須出現在戰鬥模擬裡：
     - 群眾在他所在的位置，把他加成一名**受控士兵**，放在只有他一人的隊伍裡。
     - 這個隊伍沒有 AI，也不接受隊伍命令：原生新增每隊的「不接受命令」旗標，`host_order()` 對它回傳新的結果碼 `NO_ORDERS`（8）。它也**不出現在** UI 的隊伍清單裡，隊伍數量的檢查不算它。
     - 他的狀態照 §4.2 的欄位表匯入；冷資料照第 5 項的規則，讀寫他原本的 actor 物件。
     - 這個一人隊伍是模擬用的，**不寫進任何名冊**。
   - **「一人隊伍」（`"solo": true`）的定義**：成員全部是 actor 紀錄的人的隊伍。包括兩種：
     - 第 5 項裡 `lab.character`、`lab.npc` 受控時的自己一人小隊；
     - 這裡的場外繼承人。

     `site.crowd.teams` 裡這些隊伍都標記 `"solo": true`。`_validate_crowd` **只要求**有名冊成員的隊伍在 `site.armies` 裡有對應的 roster。
   - **原生要支援戰鬥中加人**。`add_formation`、`add_soldiers` 在 `finalize` 之後也能呼叫，而且以下項目都要處理：
     - 每人陣列：包括 `add_soldier` 目前**沒有**擴充的 `rescued_by_`、`capturing_by_`（crowd_core.cpp 約第 222 行）。
     - `lag_acc_`、`lag_cnt_` 等每隊陣列。
     - `touch_` 是「隊伍數 × 隊伍數」攤平的表（約第 224 行），加隊伍時要**重新排列索引**，不能只在後面補。
     - 繼承人的陣營如果是新的，要重跑 `build_faction_slots`；否則 `enemy_blocks()` 會用到 −1。
     - 新隊伍要跑一次 `settle_command`。
     - 衍生緩衝：`ex_acc_`、`chunks_` 等。
     - 新士兵的 `cell` 在下一次 `build_hash` 之前是 −1（約第 148 行），會違反 §6.1 的規則。所以**加人之後立刻跑一次 `build_hash`**，之後才允許存檔。
     - **新隊伍的計數要初始化**（第五次審閱第 5 項）：目前只有 `finalize`（約第 185–200 行）會設定 `slot_count`、每人的 `slot`、`roster`、`fatigue_count`，以及隊伍中心與目的地。新隊伍要照 `finalize` 對單一隊伍的做法初始化這些值，**只處理新增的隊伍和新增的人**，不能重跑整場初始化。
     - **驗收**：加人完成後、第一步之前，立刻呼叫 `validate()` 並做一次存讀，兩者都要通過；讀回後的 `state_hash` 和加人後相同。
     - 加入後雜湊、確定性照常成立。
   - 收兵時，他照一般流程寫回，一人隊伍移除。

   **第 5～7 項的測試：**

   - **部署**：受控人物分別是 `lab.character`、`lab.npc`、名冊裡的人，三種都部署成功，通過 §4.2 的往返測試和 §6 的存讀測試。
   - **戰鬥中接續，繼承人在群眾裡**：
     - 群眾模式下，受控人物自己的死亡結算一完成，家族視窗就開啟，**即使其他人的死亡結算還沒完成**。
     - 測試腳本直接呼叫 `family_continuity.choose(繼承人)`（site_family_continuity.gd 約第 154 行），代替人工點選。
     - `choose` 返回後的同一步或下一步，`controlled_person_id()` 變成繼承人。
     - 原生的 `host_ctl` 從舊索引移到繼承人的索引，而且全場只有一名。
     - 輸入移動的是繼承人；舊受控士兵不再收到輸入。
     - 群眾沒有收兵，也沒有重建（`state_hash` 連續，步數不中斷）。
   - **戰鬥中接續，繼承人在場外**：
     - 繼承人加成一人隊伍的受控士兵。
     - 敵方士兵會攻擊他：在一定時間內，他身上出現有效命中，或進入交手。
     - 他的紀錄仍在 `actors.npc`，沒有被編進任何名冊。
     - 收兵後，一人隊伍消失，他的 HP 等狀態寫回 actor。
   - **戰鬥中加人的確定性**：同樣的加人時間點和輸入，1 執行緒和 4 執行緒的雜湊相同；存讀之後也相同。
   - **跨 Site 接續**：回傳 `UNSUPPORTED`，群眾和存檔都不變。

**施工要求：**

- **移除 C1 的暫時行為 2**：
  - 玩家不再使用固定裝備。
  - 部署時，照 §4.2 的欄位表，匯入玩家和每名士兵的完整狀態。
- **移除 C1 的暫時行為 3**：
  - 收兵、清除時，照同一張表**寫回**。
  - 不再恢復部署前的狀態。

### 4.2 交接欄位表與往返測試

**收兵 B 已定案的例外**：以下交接表仍為依據；收兵瞬間 `px/py` 改驗合法整體落位與逐人位移，必要的位置派生資料依新幾何重建，重新部署採當下真實位置。其他傷勢、實物、人物引用、命令意圖與 AI 所有權保留。精確欄位分類、原子提交、MOVE 接續、完整 DR／D9 驗收見 [後續計畫 §4／§6](SITE_CROWD_10K_C2_C3_FOLLOWUP_PLAN.md)。active crowd 的保存／載入精確重播要求不變。

**開戰匯入、收兵寫回，都使用同一組欄位**（上層計畫 §2.1）。左欄是原生欄位；右欄的 Site 欄位名，實作時照 `TerrainArmy.capture_combat_state()` 和 `TerrainTestCharacter.capture_state()` 填入，**填好的完整表格放進決策文件**。

**每人：**

| 項目 | 原生欄位 | Site 端 |
|---|---|---|
| HP | `hp` | 人物 hp |
| 暈眩 | `stun` | |
| 擊暈剩餘 | `ko` | `knockout_left` 等 |
| 起身 | `getup` | |
| 被俘 | `captive` | `site.captivity` |
| 看守者 | `captor`（索引，要換成 person_id） | **`captivity.guard_id`**，見下方說明 |
| 包紮 | `bandaged` | |
| 逃脫計時 | `escape_t` | |
| 指揮能力 | `ability.tactics/leadership/coach` | `command_abilities` |
| 角色 | `role` | 隊長、幹部 |
| 裝備 | `equip`（family、material、armor、shield） | 由 `item_state.equipped` 推導。**只從實物推導到原生，不反向寫** |
| 彈藥 | `ammo` | `cargo["arrow"/"bolt"]` |
| 位置、朝向 | `px, py, face` | cell |

**每隊：**

| 項目 | 原生欄位 | Site 端 |
|---|---|---|
| 士氣、集結、潰退 | `morale`、`rally_rest`、`routed` | |
| 共享疲勞與分母 | `fatigue`、`fatigue_rest`、`fatigue_count` | `team_fatigue` |
| 正式、代理、當前隊長 | `formal_cmd`、`acting_cmd`、`current_cmd` | `formal_commander`、`acting_commander`、`current_commander` |
| 幹部順位 | `officer_order` | `officers` |
| 命令、目標、目的地、朝向 | `order`、`target_person`、`goal_x/y`、`goal_facing` | `combat_order`、`pursuit_target`、`goal` |
| 追擊 | `pursuit_left`、`origin_x/y` | `pursuit_left`、`origin` |
| AI | `ai_enabled` | `tactical_ai` |
| 訓練 | `training` | `training` |

- Site 端有、但原生沒有對應的欄位，要在決策文件裡列為「群眾不經手、保留原值」，並用測試證明收兵後這些值沒有改變。

**拘押者和看守者是兩個不同的欄位**（第四次審閱第 4 項）：

- Site 的 captivity 紀錄分別保存 `captor_id` 和 `guard_id`（site_person_actions.gd 約第 532 行），兩者可以是不同的人。
  - `captor_id`：拘押者。**供養歸屬跟著拘押者**。
  - `guard_id`：實際在旁邊看守的人。
- 原生只有一個欄位 `captor[i]`，它的意義是**看守者**：逃脫判定看的是這個人在不在附近、能不能行動。
- **對應方式：**
  - **匯入既有的拘押關係**：原生 `captor[i]` ← Site 的 `guard_id`。Site 的 `captor_id` 原樣保留，群眾不經手。
  - **原生產生的新捕獲**（CAPTURED 事件）：原生的捕獲者同時是拘押者和看守者，所以 `captor_id = guard_id = 事件的 other`。
  - **收兵寫回**：只在原生看守者 ≥ 0 時寫回 `guard_id`；原生看守者是 −1 時，**保留原本的 `guard_id`**（`_validate_captivity` 要求 `guard_id` ≥ 1，site_store.gd 約第 1678–1680 行）。`captor_id` 一律不動。
  - **比對**：原生看守者對應 Site 的 `guard_id`，不是 `captor_id`。
- **看守者不在群眾裡**（**已決定：D11 = 照戰場規則，沒人看守就會逃**）：
  - 匯入時 `soldier_index(guard_id)` 找不到人，原生 `captor[i]` 就是 −1。這名俘虜在戰場上**算是沒人看守**，照 §4.5 的逃脫條件，清醒、起身完成、附近沒有威脅，滿 30 遊戲秒就逃脫。
  - 逃脫時照 §4.4 的 ESCAPED 流程處理，供養照原規則從拘押者那邊移回原供養者。
  - 還沒逃脫就收兵時，Site 保留原本的 `guard_id`（見上）。
  - 比對時，原生看守者是 −1 的俘虜，只檢查 Site 的 `guard_id` 仍是原值。
  - **之後的版本**：使用者規劃了戰俘建築。關進建築的俘虜是囚犯，只有被解放才能逃。現在的程式還沒有這個建築，C2／C3 不做；但原生的逃脫判定要保留一個每人旗標的位置，之後可以標記「囚犯，不跑逃脫倒數」。
- **往返測試另加一個情況**：一名被俘者的 `captor_id` 和 `guard_id` 屬於**不同隊伍**。匯入、戰鬥、收兵之後：
  - `captor_id` 不變；
  - `guard_id` 等於原生看守者；
  - 供養歸屬仍然在拘押者那一方。
- **再加一個情況（D11）**：一名俘虜被編進群眾，看守者不在群眾裡。
  - 他清醒、起身完成、附近沒有威脅，滿 30 遊戲秒後逃脫，Site 的 captivity 刪除，供養移回。
  - 如果改成讓他一直處於擊暈狀態，收兵時 `guard_id` 仍是原值，`_validate_captivity` 回傳 ok。
- 匯入隊長時不能發出 SUCCESSION 事件；`state.cpp` 已經有這個處理，要保留。

**往返測試（L1 與 L2 都做，使用 §2.1 的場景 DR）：**

1. **部署前**，把 Site 紀錄設成**非預設值**：
   - 玩家：hp 63、暈眩 20。
   - 一名士兵：擊暈剩 1,234 遊戲秒。
   - 一名士兵：正在起身。
   - 一名士兵：被俘，看守者是敵方某人。
   - 一名士兵：指揮能力不是預設值。
   - 一名弓兵：彈藥 7。這名弓兵在場景 DR 的弓兵隊裡。
   - 某一隊：
     - 士氣 0.4、共享疲勞不是 0；
     - 代理隊長不是預設人選、幹部順位打亂；
     - 命令是 MOVE，並且有目的地。
2. **匯入後**：原生值逐欄等於 Site 值。浮點數容差 1e-6，其他欄位完全相等。
3. **戰鬥到脫戰，然後收兵**：Site 值逐欄等於收兵前一刻的原生值。
4. **重新部署**：原生值逐欄等於 Site 值。
5. 這個測試**不經過存檔**。存讀 blob 只能證明原生能續行，**不能代替**收兵交接。

### 4.3 死亡結算與人物介接（必修）

**問題一：結算尾段被跳過。**

`_advance_combat` 的群眾分支用 `continue`，跳過了結算尾段（terrain_lab.gd 約第 1097 行，跳過約第 1153 行起的呼叫）。

- **修法**：群眾步進只取代中間的 TerrainArmy、角色、交手部分，**尾段照常執行**：
  - `settle_person_deaths(elapsed)`
  - `settle_after_contacts()`
  - `settle_supply_deliveries()`
  - `check_family_death()`
- `team.settle_combat_command()` 只對仍在場的 TerrainArmy 執行；群眾隊伍的指揮由原生處理。

**問題三：供養時鐘沒有推進**（第四次審閱第 2 項）。

- 供養時間是由 `_advance_fatigue(seconds)`（terrain_lab.gd 約第 1219 行起）推進的，群眾分支也跳過了它。
- 供養資料裡已經有成員時，時鐘落後就會被 `_align_supply_clock`（site_controller.gd 約第 4535 行）拒絕。之後的俘虜交易會一直回傳 `BUSY`。
- **修法**：群眾模式下，`_advance_fatigue` 拆成三部分，**使用和 `step_clock` 相同的遊戲秒數**：

| 部分 | 群眾模式的做法 |
|---|---|
| **個人供養時鐘**：`advance_person_supply(seconds)` | **照常執行** |
| **隊伍供養**：`advance_team_sustain(team, seconds)`（site_controller.gd 約第 4419–4495 行） | 群眾隊伍**只推進吃飯時鐘、餐份與飢餓**，供養鍵照決策 D7。士氣的處理見下面的「士氣只有一個負責端」；飢餓傷害見下面的「飢餓傷害」 |
| **不在群眾裡的人**：actors 的疲勞、`person_actions.advance`、`advance_guard_work` | 照原流程執行 |
| **群眾裡的人**：個人疲勞、隊伍共享疲勞、`captive_escort.advance` 的逃脫處理 | **跳過**。這些由原生處理，Site 端再算一次會重複計算，逃脫也會被處理兩次 |

- `captive_escort.advance` 要能分辨群眾俘虜，只跳過他們；非群眾俘虜照舊。

**士氣只有一個負責端：原生**（第五次審閱第 2 項）

- **問題**：原生的 `sustain_stage`（command.cpp 約第 197 行）是原型的寫法，**假設糧食永遠充足**：只要安全而且停下，就每遊戲小時 +5 士氣，並累積集結時間。遊戲原本的規則（site_sustain.gd 約第 235–285 行）不是這樣：
  - **缺糧扣士氣**：`2 × 小時數 × 缺糧人數 ÷ 存活人數`。
  - **吃飽才恢復**：`safe` 要求 `fully_fed`，也就是全隊都吃飽；不然士氣不回升，集結時間歸零。
  - **餐份獎勵**：一個餐次完整吃完時，士氣 +`2 × 該批人數 ÷ 存活人數`。
- **做法**：士氣、潰退、集結**只由原生結算**；Site 端算出每支群眾隊伍的「供養結果」，在兩步之間交給原生。
  - 新增綁定 `set_sustain_input(f, fully_fed, morale_delta)`：
    - `fully_fed`：這段時間全隊是否吃飽。
    - `morale_delta`：缺糧扣分加上餐份獎勵的淨值，照 site_sustain.gd 原本的公式計算。
  - 原生在 `sustain_stage` 裡：
    - 先套用 `morale_delta`；
    - **只有 `fully_fed` 為真**，才做「安全且停下 +5／遊戲小時」和集結計時；否則集結時間歸零；
    - 潰退門檻（≤ 20）和集結條件（連續 30 遊戲分鐘、士氣 ≥ 50）不變。
  - Site 端群眾隊伍的 `entry.sustain.morale`、`routed` **不參與計算**。收兵時由原生的值寫回。
  - 還沒有收到供養結果的隊伍，原生當作「吃飽」，行為和目前的原型相同。這只用在沒有 Site 的原生單元測試。
- **對照測試（L1）**：兩支完全相同的隊伍，起始士氣 60，脫戰、安全、停下，都跑 2 遊戲小時：
  - **足糧**：士氣 +10，加上期間的餐份獎勵；集結時間持續累積。
  - **零口糧**：士氣照「缺糧扣士氣」的公式下降，不回升；集結時間一直是 0；已潰退的隊伍不會重新集結。
  - 兩者與「一般模式同一場景」的 Site 規則結果相比，誤差 ≤ 0.01。

**飢餓傷害**（第五次審閱第 1 項）

- **不能用 `set_soldier_state` 寫入**：它是靜默匯入（state.cpp 約第 169 行），HP 歸零時**不會**發出 DEATH 事件、不增加死亡計數、不取消相關動作，遺物結算和拘押清理都不會啟動。
- **新增原生入口 `apply_environment_damage(i, amount)`**：
  - 只扣 HP，不加暈眩，**不延長戰鬥時鐘**（和失血一樣，參考 combat.cpp `bleed_stage` 的 `quiet_contact_` 用法）。
  - **沒有致死時**：不取消救援、俘虜等動作，也不重新打開包紮的傷口。這和一般傷害不同，因為飢餓不是傷口。
  - **致死時**：走和一般死亡**相同**的流程：取消相關動作、發出 DEATH 事件（被俘時 other 是看守者）、死亡計數 +1、解除被俘、更新疲勞分母、倒地動作。
  - **唯一的差別：不算戰損士氣**（第六次審閱第 2 項）。
    - 一般死亡不會更新這個人的生命檢查點 `life_ck`，下一次 `observe_life`（command.cpp 約第 125 行）比對檢查點時，就會把他算成戰鬥死亡，扣 `MORALE_DEATH`。
    - 遊戲原本刻意把飢餓排除在戰損之外：飢餓傷害之後更新生命檢查點（site_controller.gd 約第 4461 行，「Hunger isn't a combat casualty event」）。
    - **做法**：`apply_environment_damage` 致死時，**只把這一個人**的 `life_ck` 設成「已死亡」。這樣下一次 `observe_life` 既不把他算成死亡，也不把他算進分母。
    - **不能**把整隊的檢查點都更新，否則同一步裡真正的戰鬥死傷也會被一起略過。
  - 只能在兩步之間呼叫。
- **測試（L0 與 L1）**：
  - **一般人物飢餓致死**：飢餓超過 48 小時後持續缺糧，直到 HP 歸零。應出現 DEATH 事件，進入 `_pending_deaths`，然後完成遺物結算，`remains_id` 存在；`combat_left` 沒有因此增加。
  - **俘虜飢餓致死**：同上，而且原生解除被俘；Site 的 captivity 在死亡結算時刪除。
  - **沒有致死的飢餓傷害**：正在救人的士兵受到飢餓傷害，救援不會被取消。
  - **士氣對照（L0）**：一支 N 人的隊伍，隊長與領導能力固定。三組各自從相同狀態開始，斷言都放在**各組操作完成後的下一次** `observe_life`；有 B 戰死的組，要在 B 死亡之後。設領導減免為 r（`command_effect(f, 1, 0.25)`，三組的隊長與領導條件相同，所以 r 相同）：
    - **混合組**：兩步之間讓 A 餓死，同一步讓 B 戰死。士氣只扣 B 這一筆戰鬥死亡：`40 / (N−1) × (1 − r)`。A 已經先標成已檢查，所以不算進分母。
    - **只有 A 餓死**：士氣不因死亡改變，扣分為 0。
    - **只有 B 戰死**：A 仍然活著，分母是 N，扣分是 `40 / N × (1 − r)`。**這和混合組不相等，是正確的**，因為分母不同（command.cpp 約第 125 行的公式）。
    - 如果想直接比較兩組的數值，就另做一組：起始只有其餘 N−1 人、隊長與領導條件相同，只有 B 戰死。這一組的扣分要和混合組**完全相同**。
    - 死亡事件：混合組 A 和 B 都有 DEATH 事件，死亡計數 +2。

**供養時鐘的測試（L1 與 L2）：**
  1. 第一次捕獲完成後，再經過至少一個供養時段，例如 2 遊戲小時。
  2. 再發生一次捕獲，以及一次逃脫，兩者都要在 3 步內完成提交，不能一直 `BUSY`。
  3. 每一步之後，所有有成員的供養資料，`state.at` 都等於目前的 Site 時間。

**問題二：整條呼叫鏈都假設 owner 是 TerrainArmy 或 TerrainTestCharacter。** 只讓 `_person()` 回傳同樣格式的 Dictionary 並不夠。

- **新增群眾 owner 物件**（`CrowdPersonOwner`，放在 `crowd_person_owner.gd`），讓它提供呼叫鏈需要的同名成員。
- **每個呼叫點都要處理**：

| 呼叫點 | 原本的用法 | 群眾的做法 |
|---|---|---|
| `terrain_lab._combat_target(id)` | 先找 `combat_actors`，再找 `combat_armies` | **群眾分支放在最前面**。群眾裡的人，**包括玩家**，都回傳 `{owner: 群眾 owner, unit: 原生索引, cell, position, hp}`。玩家戰鬥中的熱狀態以原生為準，所以不能先找到 `lab.character`。 |
| `person_actions._person()` | 讀 `owner.combat_units[unit]`、`combat_hot_get(unit, hp/ko/captive/surrender_pending)`、`owner.moving_to[unit]`、`owner.faction_id` | 由群眾 owner 提供這些成員 |
| `_body_get`／`_body_set`（site_person_actions.gd 約第 829、841 行） | `owner.combat_hot_get/set(unit, 欄位)` | 由群眾 owner 實作，欄位對應見下表 |
| `settle_person_deaths` | `_body_set(loot_settled, remains_id)`、`person.moving`、`holder`、`cargo`、`cell` | 同上 |
| `SiteController.equipment_changed` | `var team: TerrainArmy = person.owner`，再呼叫 presenter、`refresh_captain_presentation` | **函式開頭加群眾分支**：交給 `crowd_site.equipment_changed(id)` 處理後直接 return。群眾端依實物重建外觀，並更新原生 `equip`。 |
| `SiteController._captivity_changed` | 強制轉型成 TerrainArmy 或 TerrainTestCharacter | **函式開頭加群眾分支**，交給 `crowd_site` 處理 |
| `cape_policy_guard`、`reconcile_cape_roles` | 走訪 `combat_actors`、`combat_armies` | 人物清單要加入群眾 |
| `lab.has_ranged_projectiles()` | 查各 owner 的 `projectiles` | 群眾模式下，改查原生是否有飛行中的箭 |

- **呼叫點清單必須完整**。實作前，在以下檔案搜尋 `person.owner`、`combat_hot_get`、`combat_hot_set`、`: TerrainArmy =`、`: TerrainTestCharacter =`：
  - `site_controller.gd`
  - `site_person_actions.gd`
  - `site_captivity_supply.gd`
  - 以及它們呼叫到的其他 site_*.gd

  把每一個可能遇到群眾人物的呼叫點列進決策文件，並寫明處理方式。**不能有未列出的路徑。**

**群眾 owner 的欄位對應：**

| 欄位 | 來源 |
|---|---|
| `hp`、`ko`、`captive` | 讀取：原生。寫入：`set_soldier_state`，只能在兩步之間 |
| `exchange_stagger` | 原生 `stagger` |
| `attack` | 唯讀：原生狀態為交手中。寫入時忽略，並計數 |
| `pose` | 唯讀：活著而且不在交手中時為 `"idle"` |
| `surrender_pending` | 固定為 false，群眾沒有投降 |
| `loot_settled`、`remains_id`、`status`、`work_task`、`appearance`、`item_state`、`cargo`、`hit_revision` | 冷資料。紀錄在名冊裡的群眾士兵：存在群眾 owner 的每人字典 `combat_units[unit]`。**紀錄是 actor 的人**（`lab.character`、`lab.npc`）：一律讀寫 actor 物件的同名屬性，見下方「actor 紀錄的冷資料」 |
| `moving_to[unit]` | 死者、倒地、被俘：`(-1, -1)`；其他人依原生速度判斷 |
| 表中沒有列出的欄位 | 回傳預設值，並計數。**測試要求這個計數為 0**，證明沒有漏列 |

**actor 紀錄的冷資料**（適用於 `lab.character`、`lab.npc`，不論現在是否受控）：

- 群眾 owner 對這些人回傳的 `item_state`、`cargo`，必須**直接引用**原本的物件，**不能是複本**。否則封存、搜刮會改到複本，實物就不守恆了。照 `_person()` 原本的做法：`lab.character` 用它的 `item_state` 和 `site.manual.cargo`；`lab.npc` 用它的 `item_state` 和 `site.worker.cargo`。
- **`loot_settled`、`remains_id` 的權威位置也是 actor 物件**（第四次審閱第 5 項）。
  - `TerrainTestCharacter.capture_state()`（terrain_test_character.gd 約第 1681 行）存檔時從 actor 物件讀這兩個欄位。
  - 所以群眾 owner 對這些人的 `_body_set("loot_settled")`、`_body_set("remains_id")`，必須**直接寫到 actor 物件**，不能寫進群眾字典。
  - 否則這個人死亡、遺物結算完成後，存檔會變成「未結算、沒有遺物 ID」，讀回後遺物可能重複產生。D6 讓原玩家角色戰死後控制權轉走，這種情況一定會發生。

**其他要求：**

- **倒數時間**：照遊戲的 `CombatTimings.POSE_SECONDS["down"]`，每步用 `elapsed` 遞減，不另外發明計時。
- **遺物**：結算時照原流程呼叫 `Runtime.leave_ground_loot`，並設定 `loot_settled`、`remains_id`。

### 4.4 事件寫回，以及俘虜的實物封存

**彈藥同步規則（防止封存後又把箭補回來）：**

- **方向**：只有「原生 → cargo」一個方向。
- **同步點**：
  - SHOT 事件結算
  - CAPTURED 處理順序的第 0 步
  - 收兵
  - 存檔前
- **把 cargo 寫進原生**，只在兩個地方發生：
  - 部署匯入
  - CAPTURED 處理順序的第 3 步（清空）

**俘虜交易。** 遊戲原本的捕獲流程（site_person_actions.gd `_commit` 約第 525 行起）依序做這些事：

1. 封存選擇：武器、盾、箭、弩箭（`_sealed_selection`）
2. `leave_ground_loot(..., "sealed")`
3. 寫入 captivity 紀錄，包含 `sealed_container`
4. 設定被俘旗標
5. `holder.version + 1`
6. `captivity_supply_commit`
7. `equipment_changed`
8. `captivity_changed`

`_captivity_changed` 本身**不做**封存，所以群眾的 CAPTURED 寫回要自己做完整的交易。

**供養預檢的限制**（第三次審閱第 1 項）：

- `captivity_supply.commit_change()`（site_captivity_supply.gd 約第 253 行）要求**同一步**已經有成功的 `change_guard()` 預檢，否則會觸發 assert。
- 現有的 `change_guard()` 不能直接拿來處理群眾事件：
  - **CAPTURED**：原生已經設好被俘旗標，`change_guard(capturing = true)` 看到目標已被俘，會拒絕。
  - **ESCAPED**：如果先刪掉 captivity 紀錄，`change_guard(capturing = false)` 就找不到原拘押關係，也會拒絕。
- 另外，`_original_team`、`_home`、`_all_members` 等函式都假定隊伍是 TerrainArmy，群眾隊伍需要對應的分支。這些函式要列進 §4.3 的呼叫點清單。

**做法：**

- 在 `site_captivity_supply.gd` 新增只給群眾事件用的 `event_change_guard(target_id, captor_id, capturing)`。
  - **不重新判斷存活或被俘旗標**，因為原生已經判定過；只檢查供養資料能不能移轉。
  - 供養去處照原規則決定：被俘時由**拘押者**（`captor_id`，不是看守者）那一方供養，逃脫時回到原供養者。群眾隊伍的供養鍵照決策 D7：沿用原隊伍的 `team_id`。
  - 檢查通過後，照 `change_guard` 的方式留下 `_prepared`，讓 `commit_change` 可以使用。
- 另外新增 `discard(target_id)`，用來清掉還沒提交的 `_prepared`。

**俘虜寫回佇列：**

- CAPTURED、ESCAPED 事件不直接寫進 Site，先放進「俘虜寫回佇列」，由每一步的結算尾段依序處理。
- **同一人的事件嚴格照順序處理**。前一筆還沒完成，這個人後面的事件都要等。他的死亡結算也要等：`settle_person_deaths` 會跳過佇列裡還有事件的人。
- 佇列不是空的，就擋存檔和收兵，回傳 `BUSY`，訊息為「俘虜交接尚未完成」。
- 每一筆都在**同一步內**做完「預檢 → 提交」，中間不能 yield。

**CAPTURED 的處理順序**（原生已經設好被俘旗標）：

0. **同步彈藥**：把這個人的原生彈藥同步到 cargo。這是同步點，重複執行也沒有影響，不算交易的一部分。此後不再從原生同步他的彈藥。
1. **供養預檢**：`event_change_guard(target, captor, true)`。失敗就停在這裡，事件留在佇列，下一步重試。
2. **封存**：先呼叫 `_sealed_selection(target)`。
   - **選擇是空的**（沒有武器、盾、箭、弩箭）：**不建立容器**，`sealed_container = ""`，直接進行下一步。這和原本的捕獲流程一樣（site_person_actions.gd 約第 525 行起），原流程只有選擇不是空的時候才呼叫 `leave_ground_loot`。常見情況是「被俘 → 逃脫 → 再次被俘」，第一次封存後身上已經沒有東西。
   - **選擇不是空的**：呼叫 `leave_ground_loot(sealed)`。失敗時呼叫 `discard(target)`，事件留在佇列，下一步重試。
   - 不能把 `EMPTY` 當成失敗而重試，否則這個人的佇列會永遠卡住。
   - 到這一步為止，除了第 0 步的同步以外，**任何 Site 資料都沒有改變**。
3. **清空原生的裝備與彈藥**：武器、盾清空，`ammo = 0`。需要時補 `set_soldier_equip`、`set_soldier_ammo` 綁定，或併進 `set_soldier_state`。
4. **寫入紀錄**，這一步不會失敗：
   - captivity 紀錄
   - `holder.version + 1`
   - `captivity_supply_commit(target, captor, true)`
   - `equipment_changed`（群眾分支）
   - `_captivity_changed`（群眾分支）

**ESCAPED 的處理順序：**

1. **供養預檢**：**在刪除 captivity 紀錄之前**呼叫 `event_change_guard(target, captor, false)`。
   - ESCAPED 事件的 other 是 −1，所以 captor 要從現有的 captivity 紀錄取得。
   - 失敗時事件留在佇列，captivity 紀錄保留，下一步重試。
2. **寫入紀錄**：
   - 刪除 captivity
   - `holder.version + 1`
   - `captivity_supply_commit(target, captor, false)`
   - `equipment_changed`
   - `_captivity_changed`

   **封存物留在原地**，原生的裝備維持封存後的樣子，不恢復。

**失敗的分類：**

- **暫時失敗**：例如 `BUSY`，表示供養時段或交糧還沒收束。事件留在佇列，下一步重試。
- **永久失敗**：例如 `NO_SUPPLY_OWNER`、`INVALID_SUSTAIN`。
  - 原生事件無法撤銷，所以**不能部分提交**。佇列停在這一筆，持續擋住存檔，UI 顯示錯誤碼。
  - 測試裡出現就判定 **GATE FAIL**。這代表 `event_change_guard` 或供養鍵的設計有缺漏，要修正設計，不能略過這一筆。

**測試：供養拒絕時不會部分提交（L1 與 L2）**

1. **製造暫時失敗**：讓看守者那一方有未完成的交糧，也就是 `team_supply[...].delivery` 不是空的，或用其他方式讓供養時段未收束。然後觸發一次 CAPTURED。
2. **比對事件處理前後**，以下全部相同：
   - `site.captivity`
   - `ground_loot`
   - 所有實物的位置
   - 目標的 `holder.version`
   - `team_supply`、`person_supply`
   - 原生裡目標的裝備
   - `captivity_supply._prepared` 是空的

   只有第 0 步同步的彈藥數可以不同。
3. 佇列長度為 1，`save_to` 回傳 `BUSY`。
4. **解除阻擋**：完成交糧後的下一步，交易完整提交，§4.4 的守恆測試成立。
5. **ESCAPED 也照這個流程測一次**：預檢失敗時 captivity 紀錄必須保留。
6. **封存失敗**：用測試專用的掛鉤讓 `leave_ground_loot` 失敗，確認 `_prepared` 已經清空，而且第 2 點列出的資料都沒有改變。
7. **順序**：同一人 CAPTURED 還在佇列裡時，又發生 DEATH。確認死亡結算等 CAPTURED 提交後才進行，最後 captivity 紀錄照原流程刪除。
8. **再次被俘**：同一人「被俘 → 封存 → 逃脫 → 再次被俘」。
   - 第二次捕獲在 3 步內提交。
   - 第二筆 captivity 的 `sealed_container == ""`。
   - 沒有新增任何地上容器。
   - 供養歸屬正確移轉。

**事件對照：**

| 事件 | 寫到哪裡 | 注意 |
|---|---|---|
| DEATH | `SiteController._person_died(id)`，由 §4.3 的尾段結算 | 同一人只能一次。被俘時死亡，照原流程由結算刪除 captivity |
| KO／WAKE | 同步點寫回人物紀錄；戰鬥時間已經由 `combat_mark` 延長 | 不要重複延長戰鬥時鐘 |
| CAPTURED | 俘虜寫回佇列，照上面的處理順序 | 格式照 `SiteStore._validate_captivity` |
| ESCAPED | 俘虜寫回佇列，照上面的處理順序 | **封存物留在原地**。原生的裝備維持封存後的樣子，不恢復 |
| RESCUED | 人物紀錄（包紮、KO 縮短） | 沒有對應欄位的，只在 log 計數，不要編造欄位 |
| SUCCESSION／COMMAND_LOST／ROUT／RALLY | UI 提示；隊伍欄位在同步點寫回 | ROUT 會影響 §3.1 的 RETREAT 規則 |
| SHOT | 彈藥同步 | |
| actor 紀錄的人 | 同步點寫回 actor 物件的 `hp`、`knockout_left`、`captive` 等欄位。戰鬥中 UI 讀原生 | 存檔保護和 UI 看到的狀態要一致 |

**守恆測試：被俘 → 封存 → 逃脫**

- **流程**：弓兵 A 帶 12 支箭，射出 3 支，被擊暈，被俘，逃脫。
- **L0（只有原生）**：cargo 和封存箱只存在 Site 端，L0 看不到，所以只驗原生：
  - 被俘之前，A 的原生 `ammo` + A 的 SHOT 次數 = 12。
  - 事件依序為 SHOT ×3、KO、CAPTURED、ESCAPED，欄位照 §4.5 的表。
- **L1（用自己的小場景，不用場景 DR）**：場景 DR 的弱方不會俘虜人，做不出這個流程。L1 另外布置：A 所在的隊伍打輸，對方是 AI 隊並開啟自動俘虜；A 被俘後，再讓看守者失能。
- **L1 每一個階段都要成立**：A 的 cargo 箭數 + 封存箱的箭數 + 已射出的 3 支 = 12。
- **逃脫後**：
  - A 的原生 `ammo = 0`，cargo 的箭數 = 0，封存箱仍有 9 支。
  - 再經過一次同步點（收兵），數值不變。
- **武器和盾**：
  - 封存後在封存箱裡。
  - A 的 `equipped` 沒有武器和盾。
  - 原生 `equip` 的武器為無。

### 4.5 事件測試（用狀態比對，並逐種驗證欄位）

**宿主端只追蹤離散狀態。** 依事件維護每個人：自由、倒地、死亡、被俘，以及看守者的 person_id。

- HP、KO 剩餘、暈眩**不靠事件推算**：一般傷害和倒數都沒有逐次事件。
- 比對時，精確值一律向原生查詢（`soldier_view`）。
- 在同步點之後，比對 Site 紀錄和原生值。

**逐人比對**：每 5 秒一次，以及結束時。離散狀態和看守者要和原生一致，**包括受控人物**。

**被俘與看守：**

- **被俘比對要排除還在處理中的人**。以下兩種人，Site 端本來就會落後原生，比對時排除：
  - 在 `_pending_deaths` 裡的人。原生在被俘者死亡時立刻清掉被俘旗標（combat.cpp 約第 117–118 行），Site 要等倒地動作結束、死亡結算時才刪除 captivity（site_controller.gd 約第 3818 行）。
  - 在俘虜寫回佇列裡還有事件的人，例如因為 `BUSY` 正在重試。

  對其他人：`site.captivity` 的筆數等於原生被俘人數，而且每一筆的 **`guard_id`** 等於原生看守者的 person_id（見 §4.2 的拘押者與看守者說明）。`captor_id` 不和原生比對。
- **兩個佇列都清空時**，例如脫戰後，做一次**不排除任何人**的完整比對。
- **不要求看守者可以行動**。看守者倒地或死亡後，要等逃脫條件**全部成立並持續 30 遊戲秒**，被俘者才會逃脫（`combat.cpp` 約第 650–675 行）。在這之前，captivity 仍然有效。條件如下，**任何一項不成立，倒數就歸零重來**：
  1. 被俘者存活（hp > 0）；
  2. 被俘者清醒（`ko == 0`）；
  3. 起身已經完成（`getup == 0`）；
  4. 沒有有效的看守：看守者不能行動、不再敵對，或距離超過看守範圍（`GUARD_CELLS`）；
  5. 附近沒有威脅：鄰近區塊沒有敵人。
- **驗證方式**：
  - 五項條件同時成立後，連續滿 30 遊戲秒，在下一步內出現 ESCAPED。
  - 被俘者仍在擊暈或起身時，即使看守者已經死亡，也不能逃脫。等他醒來、起身完成，才從 0 開始計算 30 秒。
  - 倒數途中有任何一項條件中斷，例如敵人走近，就要從 0 重新計算。

**逐種驗證事件欄位**（照 `combat.cpp`、`command.cpp` 的 `push_event`）：

| 事件 | person | other | formation |
|---|---|---|---|
| DEATH | ≥ 0 | 被俘時為看守者，否則 −1 | ≥ 0 |
| KO、WAKE、SHOT、ESCAPED | ≥ 0 | −1 | ≥ 0 |
| RESCUED | 被救者 | 救援者 | ≥ 0 |
| CAPTURED | 被俘者 | 看守者 | ≥ 0 |
| SUCCESSION | 新的當前隊長 | 舊隊長，或 −1 | ≥ 0 |
| COMMAND_LOST | **−1** | 失去的隊長 | ≥ 0 |
| ROUT、RALLY | **−1** | **−1** | ≥ 0 |

- 表中 ≥ 0 的 person_id 都必須在部署時配發的編號集合內，**加上受控人物**。
- 同一人的 DEATH 只能一次；DEATH 之後，不能再出現這個人的 KO、WAKE、CAPTURED。

**強制事件真的發生，避免空跑通過：**

- **L0**：擴充 `test_events`，**11 種事件逐一斷言次數 > 0**，並照上表驗證欄位。可以分成這些場景：
  - 追擊致死
  - 擊暈再醒來
  - 救援
  - 俘虜後逃脫：看守者失能，被俘者清醒並起身完成後，再等滿 30 遊戲秒
  - 被俘者仍在擊暈中，看守者已死亡：在醒來並起身完成之前，都不能逃脫
  - **被俘後受擊致死**
    - 被俘期間**不會失血**（`combat.cpp` 的 `bleed_stage` 跳過被俘者），所以不能用失血致死。
    - 規則上被俘者若不會成為攻擊目標，就在 L0 用測試專用的內部呼叫施加一次有效傷害，並在測試名稱註明。
  - **被俘且倒地的人，1 遊戲小時內 HP 不變**
  - 指揮者陣亡後繼承：產生 SUCCESSION
  - **整隊沒有可接任的人**：讓一支隊伍的所有成員都倒地或被俘，`current_cmd` 變成 −1，產生 COMMAND_LOST（command.cpp 約第 103–116 行）。只有「隊長陣亡、其他人接任」的場景，只會產生 SUCCESSION
  - 士氣崩潰再重新集結
  - 射擊
- **L1、L2 的場景 B**：戰鬥結束時，DEATH、KO、CAPTURED、SHOT 的次數都要 > 0，否則判定 **GATE FAIL（事件未發生）**。

**L2 正式場景（`run_c2.bat` 第二段），分兩部分：**

1. **場景 B，戰鬥 120 秒，不要求脫戰**
   - 事件欄位逐種驗證全部通過。
   - 逐人比對全部一致。
   - 每一筆 DEATH 之後，這個人在 `POSE_SECONDS["down"] + 1` 秒內離開 `_pending_deaths`。死者不會移動，所以不需要脫戰。
   - 事件處理的成本：每步平均 ≤ 0.1 ms、最大 ≤ 2 ms；大量死亡的那一步也要量到。
   - 每 5 秒輸出一行 CSV：時間、存活、倒地、死亡、被俘、`_pending_deaths` 數、`combat_left`、實物總數。
2. **場景 D，打到脫戰**
   - `supply_save_guard()` 回傳 ok。
   - 每一位死者都有 `remains_id`。
   - 物品守恆：`部署時總件數 = 持有 + 地上遺物 + 封存箱 + 已消耗彈藥`。已消耗彈藥 = SHOT 事件數；場景 D 沒有弓兵，所以是 0。
   - 直接呼叫 `SiteStore._validate_captivity(data, state)`，回傳 ok。
   - 實物唯一位置檢查（`locations.size() == item_records.size()` 那一段）在部署後、脫戰時都是 ok。
   - 逐人比對全部一致。

---

## 5. C3 前置：可以回傳結果的存檔 API

`SiteController.save_current()` 回傳 `void`，測試無法判斷成功或失敗。先重構：

- 新增 `func save_to(path: String) -> Dictionary`，依序執行：
  1. `supply_save_guard()`。群眾模式下，守門還要包含：原生有飛行中的箭（經由 `has_ranged_projectiles` 的群眾分支）、俘虜寫回佇列不是空的（§4.4）。
  2. **組成存檔內容**，改用新的 `_capture_for_save()`。**不能**用「先同步原生、再呼叫 `_capture_positions()`」的順序，理由見下。
  3. `Store.save(lab.terrain, path)`。
  4. **成功時設定 `_auto_save_blocked = false`**。這是原 `save_current()` 成功後的行為（site_controller.gd 約第 2125 行），不能漏掉；否則讀壞檔之後，即使手動保存成功，自動保存也會一直停用。
  5. 回傳結果。
- `save_current()` 改成 `show_result(save_to(save_path))`，一般模式的行為不變。

**為什麼不能先同步、再 `_capture_positions()`**（第三次審閱第 2 項）：

`_capture_positions()`（site_controller.gd 約第 2091 行）會**整個重建**以下兩項：

- `site.actors`：用 `lab.character.capture_state()` 和 `lab.npc.capture_state()` 重建。
- `site.armies`：只用現場的 TerrainArmy 重建。

所以：

- 如果只把受控人物的最新狀態寫進 Site 字典，會被 `character.capture_state()` 的舊值蓋掉。
- 群眾隊伍的 roster（D1）不是 TerrainArmy，重建 `site.armies` 時會整批消失。

**`_capture_for_save()` 的順序：**

1. **寫回現場物件**：把原生熱狀態寫回**所有 actor 紀錄的人**的現場物件（`lab.character`、`lab.npc`，只要他們在群眾裡），包括 hp、`knockout_left`、captive、`terrain_cell` 等欄位。這樣 `capture_state()` 讀到的就是最新值。名冊裡的群眾士兵，熱狀態寫回群眾 owner 的每人字典。
2. **取得基礎快照**：呼叫原本的 `_capture_positions()`，函式本身不修改。一般模式只做到這一步，行為和原本完全相同。
3. **合併群眾資料**：
   - 把群眾 roster 附加到 `site.armies` 後面，並加上 `crowd` 標記（D1）。
   - 最後寫入 `site.crowd` 區段。
4. **斷言**：合併後，§4.1 的唯一性規則成立。不成立就回傳 `INVALID_CROWD`，而且**不寫檔**。

**其他直接呼叫 `_capture_positions()` 的地方**，群眾模式下都要改用 `_capture_for_save()`：

- `archive_before_replace()`
- `_request_exit()`
- `_archive_family_site()`（約第 3604 行）

實作時搜尋全部呼叫點並列進決策文件。

**測試（L1 與 L2）：**

- **受控人物受傷**：受控人物在戰鬥中 hp 降到 41，脫戰後存檔。讀出檔案的 JSON，**在他實際的紀錄位置**檢查 hp 是 41。三種受控情況各做一次（D5）：
  - `lab.character`：`actors.player`
  - `lab.npc`：`actors.npc`
  - 名冊裡的人：`site.armies` 裡標記 `crowd` 的 roster 中，他那一筆
- **受控人物死亡**：等死亡結算完成，然後存檔。讀出檔案的 JSON，在他實際的紀錄位置檢查：
  - hp 是 0，`loot_settled` 是 true；
  - `remains_id` 不是空字串，而且這個 id 在 `ground_loot` 裡存在；
  - 讀回後再跑一次死亡結算，不會產生第二份遺物。
  - 三種受控情況各做一次。
- **原玩家角色戰死、控制權已經轉給繼承人**（D6）：這時原玩家角色已經不是受控人物，但紀錄仍在 `actors.player`。存檔後同樣檢查 `actors.player` 的 hp 是 0、`loot_settled` 是 true、`remains_id` 存在。
- 檔案裡標記 `crowd` 的 roster 人數，等於群眾人數減去紀錄在 actors 的人（包括一人隊伍的場外繼承人）。
- 對 `archive_before_replace`、`_request_exit`、`_archive_family_site` 這三條路徑，各做一次同樣的檢查。
- **所有會寫檔的路徑都要改成經過 `save_to`，或者保持同樣的旗標行為**：
  - `archive_before_replace()`：成功時同樣清除 `_auto_save_blocked`（約第 2140 行）。
  - `_request_exit()`：目的地依 `_auto_save_blocked` 在 `save_path` 和 `<site.id>.json` 之間二選一（約第 2206 行）。**兩個分支都要經過 §1 的測試路徑改寫。**
- 讀檔也一樣：新增 `func load_from(path) -> Dictionary`，`_load_path` 改成呼叫它。失敗時照原本的做法設定 `_auto_save_blocked = true`，成功時設為 false（約第 2169–2171 行）。

**回歸測試（L2，一般模式和群眾模式各跑一次，都帶 `--crowd-test`）：**

1. `load_from(壞檔複本)` → 失敗，而且 `_auto_save_blocked == true`。
2. `save_to(測試路徑)` → ok，而且 `_auto_save_blocked == false`。
3. 保持脫戰超過 30 秒 → 自動保存確實寫入測試路徑，檔案的修改時間有更新；§1 的前後快照仍然一致。

---

## 6. C3：存檔讀檔

### 6.1 原生 `load` 必須先改成安全（必修）

**現況的問題：**

- `World::load` 直接反序列化到現有的 World，**失敗時現有狀態已經被改壞了**。
- `nested()`、formations 的數量都直接用檔案裡的長度配置記憶體，沒有上限。
- 地形寬高也沒有和陣列長度核對。

**修法：**

1. 反序列化到**暫時的 World**（或暫時的緩衝區）。
2. **所有長度都要有上限**：
   - 巢狀容器的元素數 ≤ 剩下的位元組數 ÷ 最小元素大小。
   - 隊伍數 ≤ 士兵數 + 1。
   - `w × h` ≤ 1024 × 1024，而且等於地形陣列長度。
   - 每個士兵陣列的長度都等於 n。
3. **所有索引都要在範圍內，並且互相一致**：
   - `form[i]`：在 `0..隊伍數−1` 之間，**不能是 −1**。原生直接用 `formations[form[i]]`，沒有另外檢查（例如 combat.cpp 約第 133 行的 `push_event`）。
   - `target`、`captor`、`rescue_of`、`capture_of`、`enc_target`、`rescued_by_`、`capturing_by_`：在 −1 到 n−1 之間。
   - `cell[i]`：在 `0..w×h−1` 之間。流場查詢會用它當索引（crowd_core.cpp 約第 754、783 行）。也可以在讀檔時由位置重算，然後要求和存檔一致。
   - `slot[i]`：**不是士兵索引**，規則見下面「各隊的成員」。
   - `rescuers_`、`capturers_`、`captives_` 的元素在 0 到 n−1 之間。
   - **各隊的成員**（第三次審閱第 4 項）：
     - `compact_slots`（crowd_core.cpp 約第 944 行）會把**死者**從 `members` 移除，但死者仍然留在士兵陣列裡，`form[i]` 也不變。所以規則是：
       - `members` 的每個元素都在 0 到 n−1 之間，不重複，而且 `form[m] == 這一隊`。
       - **存活的士兵**（`hp > 0`）必須恰好出現在 `form[i]` 那一隊的 `members` 裡。
       - **死者可以不在** `members` 裡；還沒重整時，也可能還在。兩種都合法。
     - `slot` 的規則**只套用在 `members` 裡的士兵**：值為 −1，或小於本隊的 `slot_count`。
     - **只有非負的 slot 必須在同一隊裡不重複；−1 可以重複**。`compact_slots` 會把「不能行動、也不在起身中」的成員設成 −1（crowd_core.cpp 約第 951–953 行，條件是 `can_act(i) || getup[i] > 0` 才保留 slot），所以同隊有多名倒地或被俘的人時，會有好幾個 −1。
     - **死者的 `slot` 不檢查**。`compact_slots` 只會把活著但不能行動的成員設成 −1（crowd_core.cpp 約第 953 行），被移出 `members` 的死者保留舊的 slot。舊值可能 ≥ 新的 `slot_count`，也可能和活人重複，這是合法的。
     - `slot_count` ≤ `members` 的長度。
   - 隊伍的 `formal_cmd`、`acting_cmd`、`current_cmd`、`officer_order`、`target_person`、`ai_target`：為 −1，或是 `0..n−1` 的合法索引。
     - 隊長和幹部必須屬於本隊，也就是 `form[i] == 這一隊`。
     - **不要求**他們在 `members` 裡，也不要求存活：陣亡的正式隊長可能在指揮結算前仍留在欄位裡。
   - 隊伍的 `field`：為 −1，或小於流場數量。
   - **流場**（第三次審閱第 3 項）。流場重建（crowd_core.cpp 約第 271 行的 `build_field`）會直接使用 `cost[goal]`，也會依照 `edge_ok` 的方向位元存取鄰格，所以：
     - 流場數量不超過原生的流場上限。
     - 每個流場的 `goal`：
       - **會被使用的流場**，`goal` 必須在 `0..w×h−1` 之間。「會被使用」包括三種：已建置的、**出現在 `field_queue_` 裡的**、被任何隊伍的 `field` 引用的。
       - 原因：下一步會直接建置佇列裡的流場（crowd_core.cpp 約第 996 行），`goal = −1` 會造成 `cost[-1]` 越界。
       - 只有不屬於這三種的閒置流場，`goal` 才可以是 −1。
     - `last_used` ≤ `tick`。
     - `field_queue_` 的每個元素都在 `0..流場數量−1` 之間。
   - **地圖邊界 `edge_ok`**：不能只檢查長度。偽造的方向位元可能指向地圖外，重建流場時就會越界。
     - **做法**：讀檔時用存檔裡的地形資料（高度、flags、ramp_edges、static_blocked）**重新算一次** `edge_ok`，要求和存檔裡的完全相同，不同就拒絕。
     - 重算要用和 `set_terrain` 相同的函式，不能另外寫一份。
   - **其他跨步驟保存的私有陣列**：`slot_tx_`、`slot_ty_`、`slot_clip_`、`lag_acc_`、`lag_cnt_`、`attackers_`、`touch_`。長度符合對應的士兵數或隊伍數；浮點數都是有限值；裡面的索引都在範圍內。
   - 箭矢的 `shooter`：為合法索引。
   - `hostile_` 是固定大小的 256×256 表，以陣營 id 當索引（crowd_core.cpp 約第 434–438 行、crowd_core.hpp 約第 388 行），所以長度必須剛好是 65,536。陣營 id 不要求連續。
   - 士兵的 `team` 和隊伍的 `team` 都在 0..255 之間；士兵的 `team` 等於他所屬隊伍的 `team`。
4. **數值必須合法**，這一項防止重建時出錯，例如 `cfg.chunk = 0` 會在 `state.cpp` 約第 142 行的 `(n + cfg.chunk - 1) / cfg.chunk` 除以零：
   - **cfg 的整數**：`chunk`、`los_period`、`contact_period`、`los_max_cells`、`max_fields_per_step` 都 ≥ 1，並有合理上限，例如 `chunk` ≤ 65,536；`encircle_budget` ≥ 0。
   - **cfg 的浮點數**：全部都是有限值；`radius`、`march_speed`、`run_speed`、`reach`、`speed` > 0；其他距離 ≥ 0；`ko_seconds`、`rescued_ko_seconds` > 0；`bleed_per_game_hour` ≥ 0。
   - **每名士兵的浮點數**：全部都是有限值；位置在地圖內，也就是 `0 ≤ px < w`、`0 ≤ py < h`；`hp` ≥ 0；`ko`、`getup`、`stun`、`escape_t` 等計時值 ≥ 0。
   - **每支隊伍的浮點數**（第五次審閱第 4 項）：下一步的座標解析（crowd_core.cpp 約第 410 行）會把隊伍中心直接換成格子索引，所以：
     - **全部都是有限值**。實作時對照 `io_formation`，把其中所有浮點欄位逐一列出，不能漏。至少包括：`cx`、`cy`、`facing`、`goal_x`、`goal_y`、`goal_facing`、`lag`、`compact_t`、`origin_x`、`origin_y`、`pursuit_left`、`order_delay`、`ref_x`、`ref_y`、`training`、`morale`、`rally_rest`、`fatigue`、`fatigue_rest`、`contact_age`、`threat`、`ai_order_cd`、`ai_chase_cd`、`encircle_t` 等。
     - **座標在地圖內**：中心 `cx, cy`、目的地 `goal_x, goal_y`、追擊出發點 `origin_x, origin_y`；`ref_valid` 為真時，參考點 `ref_x, ref_y` 也要在地圖內。
     - **數值範圍要逐欄定義**（第六次審閱第 1 項）。**不能**一律要求計時值 ≥ 0，因為有些欄位在正常執行中會扣過零，並且原樣存檔：
       | 欄位 | 合法範圍 | 原因 |
       |---|---|---|
       | `morale` | 0..100 | |
       | `training` | ≥ 0 | |
       | `order_delay` | > −1 | 只在 > 0 時扣 `dt`（crowd_core.cpp 約第 504、541 行），扣完可能是負數；每步的 `dt` < 1 |
       | `pursuit_left` | > −1 | 追擊中每步扣 `dt`（約第 520 行），到期那一步會留下負值 |
       | `compact_t`、`encircle_t` | > −1 | 扣 `dt` 後，≤ 0 就在同一步重設（約第 1012、1058 行） |
       | `ai_order_cd`、`ai_chase_cd`、`rally_rest`、`fatigue`、`fatigue_rest` | ≥ 0 | 產生端已經限制 |
       | `contact_age` | ≥ 0 | 只會增加或歸零 |
       - 上表的「> −1」是依據「每步 `dt` < 1」。**這個前提目前只有 Godot 綁定的 `step`／`step_clock` 有檢查**。原生的 `World::step` 和 C API 都沒有檢查，所以要把它明列為**所有呼叫者共同遵守的前提**：
         - 原生 `step`、`step_clock` 開頭加上檢查：`dt` 不是有限值，或不在 (0, 1) 之內，就不步進並回報錯誤（除錯建置用 assert）。
         - C API 的步進函式也回傳同樣的錯誤。
         - 原生測試與 `crowd_flicker` 等工具，也都只能用 0 < `dt` < 1。
         - 這個前提寫進 R1 的範圍表說明。
       - 實作時要對 `io_formation` 和士兵陣列的**每一個**浮點欄位，查出所有寫入的地方，再定範圍，列成完整的表放進 §9.2 的清單 R1。
       - **不能在讀檔時把負值截成 0**，否則讀回後的續行雜湊會和原世界不同。
     - **防止規則太嚴的總檢查（L0）**：在所有既有的場景測試裡，**每一步結束後都呼叫一次 `validate()`**，任何一步失敗都算測試失敗。這樣可以確定正常執行產生的狀態一定能通過驗證。
     - **合法存讀對照**：以下兩種狀態各存讀一次，都要通過，而且讀回後的續行雜湊和原世界相同：
       - 一支隊伍剛下完 MOVE，`order_delay` 扣到負值的那一步；
       - 一支隊伍追擊到期，`pursuit_left` 是負值的那一步。
   - **列舉**：`state` < `S_` 的數量；`order` ≤ `RETURN`；`troop` ≤ `T_CROSSBOW`；`role` ≤ `R_OFFICER`；`ai_status` 在範圍內；`equip` 的 family、material、armor、shield 在各自的列舉範圍內；事件的 kind ≤ 10。
   - **布林值**只能是 0 或 1。這裡有兩種情況：
     - 以 `uint8_t` 存的旗標：讀進來之後檢查。
     - **C++ `bool` 欄位**，例如 `Formation` 的 `arrived`、`routed`、`ai_enabled`，以及 `Config` 的 `auto_capture`、`ai`：
       - 目前的 `Reader::pod` 用 `memcpy` 直接寫進 `bool`。位元組是 2 的時候，已經是未定義行為，**事後再檢查來不及**。
       - 必須改成先讀成 `uint8_t`，確認是 0 或 1，再轉成 `bool`：為 `bool` 寫專用的讀取函式。
       - 含有 `bool` 的結構，例如 `Config`，不能整塊 `pod()` 讀寫，要改成逐欄讀寫。
       - 實作時搜尋全部以 `pod()` 整塊讀寫的結構，列出其中的 `bool` 欄位，逐一處理。
   - **時鐘**：`time`、`combat_left`、`game_dt` 都是有限值，而且 ≥ 0。
5. **寫成一個共用的 `World::validate()`**：安全載入和 fuzz 測試都呼叫它。衍生狀態的重建，例如 `chunks_`、`build_field`，只能在 `validate()` 通過之後執行。
6. 全部檢查通過之後，才整個替換現有的 World。

**L0 測試：**

- **必拒絕的壞結構**：逐項人工製作，**每一項都必須回傳 false**，而且現有 World 的 `state_hash` 不變。
  - 截斷
  - 長度欄位放大
  - 士兵陣列的長度不等於 n
  - `w × h` 和陣列長度不符
  - 越界的索引：每一種索引欄位各一個
  - 隊員和 `form` 互相矛盾
  - `cfg.chunk = 0`，以及其他 cfg 整數設為 0
  - 位置、hp、cfg 浮點數設為 NaN 或無限大
  - 超出範圍的列舉值
  - 布林欄位設為 2：`uint8_t` 旗標和 C++ `bool` 欄位各做一個，包括 `Config` 裡的 `bool`
  - 流場 `goal` 越界：已建置的流場 `goal = w×h`
  - `field_queue_` 有越界的元素
  - 未建置的流場 `goal = −1`，但它在 `field_queue_` 裡，例如 `fields[0] = {built: false, goal: −1}`、`field_queue_ = [0]`
  - 未建置的流場 `goal = −1`，但被某一隊的 `field` 引用
  - **只變造一支隊伍的中心**：有效存檔裡，把某一隊的 `cx` 改成 NaN，其他資料都合法
  - 某一隊的 `goal_x` 在地圖外；某一隊的 `morale` 是 150
  - 偽造的 `edge_ok`：地圖邊緣的格子，設定一個指向地圖外的方向位元，其他資料都合法
  - 存活士兵不在自己隊伍的 `members` 裡
- **必須通過的合法狀態**（不能被誤判成壞檔）：
  - 同一隊有多名倒地、被俘的成員，`slot` 有好幾個 −1。
  - 已經有死者、而且已經完成 `compact_slots` 的戰後存檔。死者不在 `members` 裡，但仍在士兵陣列中。
  - 已經有死者、但還沒重整的存檔。
- **隨機變異 fuzz**：拿一份有效的存檔，做 2,000 次隨機變異：改位元組、截斷、插入。
  - 全程在 ASan 與 UBSan 下執行，**任何一次都不能崩潰，也不能有 sanitizer 報錯**。
  - **不要求一律回傳 false**：變異可能只是合法地改了某個值，例如 HP。判定方式如下：
    - 回傳 false：現有 World 的 `state_hash` 不變。
    - 回傳 true：新的 World 必須通過 `validate()`，接著再步進 300 步。步進期間不能崩潰，也不能有 sanitizer 報錯，而且每一步結束時，位置都是有限值。
  - 回報兩種結果各自的次數。
  - 如果回傳 true 的次數是 0，就表示變異太粗糙，要調整變異方式，至少讓一部分變異只改動數值欄位。
- `KW01`、未來版本代號、空資料，都回傳 false。
- 有主控玩家的戰鬥存檔，讀回後玩家仍然受主控；輸入同樣的操作，雜湊相同（C1 已有這一項）。

### 6.2 Build 識別

- **識別值**是 **DLL 檔案本身的 SHA-256**：GDScript 用 `FileAccess.get_sha256("res://native/crowd10k/bin/crowd10k.windows.x86_64.dll")` 取得，和群眾區段一起存。
- **輔助值**：建置時產生 `build_id.h`，內容是全部原生原始碼、編譯器版本、編譯旗標的雜湊，由 `crowd.build_id()` 回傳。用途是在 log 裡辨識是哪一次建置。
- **讀檔時兩者都要相同**；不同時照 §6.4 處理。

### 6.3 群眾區段的格式（跟著 D1）

```
site.crowd = {
  "version": 1,
  "dll_sha256": "...", "build_id": "...",
  "blob": "<base64 of save_state()>", "blob_sha256": "...",
  "teams": [{slot, team_id, formation, faction, troop, person_ids: [...], solo: false}],  # solo = D10 場外繼承人的一人隊伍
  "player": {person_id, soldier_index},
  # 群眾人物的紀錄在 site.armies（標記 crowd 的 roster，D1），這裡不另外存
  "deploy": ...   # 重建外觀所需的部署參數
}
```

**SiteStore 的驗證**：新增 `_validate_crowd`，並把群眾人物加入 `_validate_captivity` 等處的人物集合，讓拘押、裝備、`controlled_person_id` 的驗證都看得到群眾人物。檢查項目：

- `version`
- base64 能解開，`blob_sha256` 相符，大小 ≤ 16 MB
- **照 §4.1 的唯一性規則驗證**：
  - 每個 person_id 在所有**紀錄**中恰好出現一次，並且小於 `next_person_id`。
  - 每個**目前引用**都必須解析到恰好一筆紀錄。目前引用包括 `crowd.teams[].person_ids`、`crowd.player`、原生 blob 的 person_id 陣列、`captivity` 的鍵與看守者。
  - **受控人物的合法形態**：紀錄在一個地方（actors 或群眾名冊），同時被 `crowd.teams` 的某一隊引用，也被 `crowd.player` 引用。這是**合法的**，不能被當成重複而拒絕。
  - **場外繼承人的一人隊伍**（D10）：`crowd.teams` 裡標記 `"solo": true` 的隊伍只是引用，紀錄仍在 actors。這也是合法的。
  - **歷史來源 ID** 只檢查 `0 < id < next_person_id`，不要求有紀錄。例如退休工人留下的地上物資，原持有者已經沒有紀錄，這是合法的。
  - `site.armies` 裡標記 `crowd` 的 roster 是群眾人物的紀錄，`crowd.teams` 對它們是引用，也是**合法的**。
  - **不合法的例子**：同一個 person_id 同時有兩筆紀錄，例如同時在一般 roster 和群眾紀錄裡；或同時在 `actors` 和群眾紀錄裡。
  - blob 的 person_id 陣列和 `crowd.teams` 的集合必須完全相等。這一項在 GDScript 端比對，需要時補一個綁定，從 blob 讀出 person_id 陣列，但不載入整個 World。
- 每一件實物有唯一的位置

### 6.4 載入失敗的處理，以及一般模式讀到群眾存檔（已決定：D8、D9）

- **已決定：D8 = 整份拒絕**。群眾區段無效、DLL 不相容、驗證失敗時，**整份載入都拒絕**。
  - **目前的場景不動。**
  - **原存檔檔案不動**，不改寫、不刪除。
  - 顯示明確訊息，例如：「群眾存檔來自不同版本（DLL 不同），無法載入；目前場景與原檔都未修改」。
- **理由**：群眾人物可能被俘虜，也可能被裝備或玩家資料引用。只略過群眾區段、載入其他部分，會造成引用斷裂，或人物消失。
- **已決定：D9 = 一般模式讀到群眾存檔時，自動切換成群眾模式再讀。**
  - 讀檔流程先看存檔有沒有 `site.crowd` 區段；有的話，在 `bind_terrain` **之前**建立並啟用 `crowd_site`，然後照群眾模式的流程載入。
  - 所以 `crowd_site` 在一般模式下也要能**隨時建立**，不能只在啟動參數 `--crowd` 時才建立。
  - D8 仍然適用：自動切換後，群眾區段驗證失敗就整份拒絕，並**恢復原本的模式**，場景與檔案都不動。
  - 自動切換只持續到這場群眾戰鬥收兵為止；收兵後，新的部署照啟動時的模式進行。
  - 一般模式下沒有群眾區段的存檔，行為完全不變。
- **清除目前的群眾、替換 World，都只能在完整驗證成功之後才做。** `bind_terrain` 目前一開始就呼叫 `crowd_site.clear()`，要改成「驗證通過 → 建立新的群眾 → 成功後才換掉舊的」。

### 6.5 L1 替身場景測試（`crowd_c3_saveload_check.gd`）

這一節分成兩部分：戰鬥中的續行一致性，只測原生 blob；完整的 `save_to`／`load_from`，只在脫戰後測。

**第一部分：戰鬥中續行（原生 blob）**

- 用場景 B 部署 5,000 人，跑 30 秒，**仍在戰鬥中**，這時呼叫原生 `save_state()`。
- **不在這裡呼叫 `save_to()`**。戰鬥中可能有飛行中的箭、待結算的死亡，守門擋下是正常的。

**第二部分：完整存讀**

- 用場景 D 打到脫戰（§2.1）。存檔前再確認一次：`combat_left <= 0`，而且 `supply_save_guard()` 回傳 ok。
- 呼叫 `save_to(測試路徑)`，要回傳 ok。
- **讀回要在一個新的、沒有交戰的場景裡做**。原世界存檔後會繼續跑 20 秒，這段期間可能又交戰，醒來的人可能重新接敵。這時在原世界呼叫 `load_from`，會被「脫戰後才能載入」擋下；路徑和 `save_path` 不同時，還會先跑 `archive_before_replace`。所以：
  - L1：建立**新的** SiteController 和替身 lab，在新場景呼叫 `load_from`。
  - L2：像 §6.6 第 8 步一樣重新啟動 Godot，再呼叫 `load_from`。
  - 讀回前斷言新場景沒有交戰，也就是 `combat_left <= 0`。

**兩部分都要做的比對：**

1. **記錄**：存檔之後，原世界繼續跑 20 秒，記下每一步的 `state_hash`、stats，以及玩家的輸入。
2. **重跑**：讀回存檔，給同樣的輸入，重跑 20 秒。
   - 第一部分用原生 `load_state()` 讀回，可以讀進另一個 `ArmyCrowd` 實例。
   - 第二部分在新的場景裡用 `load_from()` 讀回，做法見上。
3. **通過條件**：
   - 每一步的 `state_hash` 都相同。
   - `stats` 的 A 組（0–17）和 C 組（33–39）完全相同，分兩行回報；B 組是耗時，不比較（§0.4）。
   - **模擬座標**完全相同：逐人比對 `soldier_view` 的索引 9、10（從 0 起算），也就是模擬 x、y。
   - **畫面重建**：讀回後的第一幀，畫出的位置 = 模擬座標 × 64，因為呈現濾波會從讀回的位置重新開始。**不要**和存檔前畫面上的位置比較。
4. **只在第二部分做**：
   - 讀回後，Site 端的人物紀錄、`captivity`、實物，都和存檔前相同。
   - 5,000 人時，存檔大小 ≤ 4 MB，存檔時間 ≤ 300 ms，讀檔時間 ≤ 500 ms。

**壞檔和不相容**（都用測試複本）：

- **必須被拒絕的**：
  - blob 改 1 個位元組
  - 截掉一半
  - 空字串
  - 把 `dll_sha256` 換掉
  - 同一個 person_id 有兩筆紀錄（違反 §4.1）

  每一種都要做到：**不崩潰**、回傳失敗、目前場景不變（載入前後的 `state_hash` 和 Site 字典都相同）、檔案內容不變。
- **必須通過的對照組**，每一個都要能正常載入：
  - 受控人物同時出現在 `actors.player` 和 `crowd.teams` 的存檔。
  - 含有退休工人留下的地上物資、原持有者已經沒有紀錄的存檔。做法：用 C3 之前的舊存檔複本讀入，部署群眾，打到脫戰，存檔，再讀回。
  - 已經有死者、而且原生已經完成隊形重整（`compact_slots`）的存檔，見 §6.1。

### 6.6 L2 正式場景自動測試（`run_c3.bat`）

整份流程都在 `--crowd --crowd-test <run_id>` 下執行：

1. 部署 §2.1 的**場景 D**，開始交戰。
2. **戰鬥中嘗試讀檔**：`load_from` 必須回傳「脫戰後才能載入」，場景不變。
3. 照 §2.1 的判定等到脫戰。**不要用 MOVE 後退來脫戰。**
4. **記錄存檔前的狀態**：
   - `stats` 的 A 組、C 組，以及 `state_hash`
   - 玩家的模擬座標、各隊存活數
   - `site.captivity`、實物總數
5. **存一份固定的基準檔**（第六次審閱第 3 項）：
   - `save_to("user://sites/crowd_test/<run_id>/baseline.json")`，要回傳 ok。
   - 基準檔**不是** `save_path`。自動保存寫的是 `crowd_test/<run_id>/current.json`，碰不到基準檔。
   - 存完立刻算基準檔的 SHA-256，寫進 `saveload.json`。
   - 之後第 6、8、9 步**每次讀基準檔之前**，都先重算 SHA-256，必須和記錄的相同；不同就 GATE FAIL（基準檔被改寫），並印出新舊兩個值。
   - 原因：第 7 步會移動玩家並再跑 30 秒，期間脫戰超過 30 秒就會觸發自動保存。如果基準檔就是 `current.json`，第 8 步重啟後讀到的會是自動保存的新狀態，正確的實作也會被判失敗。
6. `load_from(基準檔)`，要回傳 ok。基準檔的路徑和 `save_path` 不同，所以讀檔前會先跑 `archive_before_replace`；它寫的是 `crowd_test/<run_id>/<site.id>.json`（§1），也碰不到基準檔。
7. **讀回後的比對**：
   - 第 4 步記錄的每一項都要相同。
   - 玩家仍受主控：送 2 秒向右的輸入，模擬位移 > 3 格。
   - UI 隊伍清單的數量相同。
   - 讀回後再跑 30 秒，共通關卡全部通過；逐人比對時，沒有人物重複，也沒有人物消失。
8. **重啟**：批次檔結束 Godot，以相同參數重新啟動。確認基準檔的 SHA-256 沒變，然後 `load_from(基準檔)`，重做第 7 步的比對。這一步驗證真的是從硬碟讀回。
9. **一般模式讀群眾存檔**（D9 = 自動切換）：不帶 `--crowd`、帶 `--crowd-test`。確認基準檔的 SHA-256 沒變，然後讀基準檔。
   - 讀檔成功，群眾模式自動啟用，第 7 步的比對全部通過。
   - 收兵後，再部署一次：這次用的是一般的 TerrainArmy，行為和一般模式相同。
   - **壞檔版本**：不帶 `--crowd`，讀一份群眾區段損壞的存檔。整份拒絕，模式恢復成一般模式，場景和檔案都不變。
   - 不能崩潰，也不能讓群眾人物消失後又把存檔寫回去。
10. **舊存檔**：拿 C3 之前的存檔**複本**（沒有 `crowd` 區段），用 `--crowd` 讀取，要照常載入，戰場上沒有群眾。
11. **自動保存**：在測試模式下讓遊戲脫戰超過 30 秒，確認自動保存只寫進測試路徑的 `current.json`（§1 的快照關卡會抓到任何越界寫入），而且基準檔的 SHA-256 仍然沒變。

輸出 `saveload.json`：每一步的結果、時間、檔案大小、雜湊。

### 6.7 L3 手動清單（用使用者自己開的一個新 Site）

- 打到一半、脫戰後存檔，關遊戲，重開讀檔：戰場、人數、被俘的人、地上的遺物都在，自己仍可以走動和交手。
- 戰鬥中按讀檔，顯示「脫戰後才能載入」。
- 換地圖或產生新地形時，群眾正確清除，畫面上沒有殘留的士兵。

---

## 7. 允許修改的檔案範圍

**2026-10-01 已同意的範圍補充**：收兵 B 所需原 handoff／TerrainArmy MOVE 準備／原預約接點，以及 Atlas 入場去重與實際受影響版本發布，依 [後續計畫 §3–§5](SITE_CROWD_10K_C2_C3_FOLLOWUP_PLAN.md) 的狹窄白名單執行。這是下列原限制的明示例外，不允許無關改規則；一般模式回歸與資料保全要求維持。

**可以修改。所有 GDScript 的改動都必須以群眾模式或測試模式為前提；不帶參數時，遊戲行為不變。唯一的例外是 D9：不帶參數時讀到含群眾的存檔，會自動切換成群眾模式（§6.4）。**

- `native/crowd10k/src/*`：
  - `state.cpp` 安全載入與 `World::validate()`
  - 對外的 `host_order()` 與結果碼表；內部的 `order_*` 保持裁切行為（§3.1）
  - `Reader` 的 `bool` 安全讀取、含 `bool` 結構的逐欄讀寫
  - `crowd_core`／`combat` 的事件與狀態
  - build 識別

  改完要保持確定性。
- `native/crowd10k/src/*` 另外需要（D6、D10）：
  - `finalize` 之後仍能 `add_formation`、`add_soldiers`，並同步擴充所有衍生緩衝
  - `set_host_control(i, false)` 時，解除以他為中心的隊形
- `native/crowd10k/godot/crowd10k_gdext.cpp`：補綁定。需要的有：
  - `order` 回傳結果碼（int）、`order_owner` 查詢；C API 同步改成回傳結果碼
  - `set/get_soldier_state`、`set/get_formation_state`，要涵蓋 §4.2 的全部欄位
  - 裝備與彈藥的寫入
  - 飛行中箭矢的查詢
  - 從 blob 讀出 person_id 陣列
- `native/crowd10k/tests/*`、`native/crowd10k/tools/*`、`native/crowd10k/run_*.bat`
- `scripts/terrain_lab/crowd_site.gd`（一般模式下也要能隨時建立，D9），以及新增的 `scripts/terrain_lab/crowd_person_owner.gd`（§4.3）
- `scripts/terrain_lab/terrain_lab.gd`：只改以下幾處：
  - 群眾分支
  - 結算尾段的結構（§4.3）
  - `_combat_target` 的群眾分支，放在最前面
  - `has_ranged_projectiles` 的群眾分支
  - `_advance_fatigue` 在群眾模式下的三段拆分（§4.3 問題三）
  - `crowd_site` 改成可以隨時建立，不只在 `--crowd` 時建立（目前在約第 188–193 行，D9）
  - `bind_terrain` 改成「先驗證，再建立新群眾，成功後才換掉舊的」（目前約第 426–427 行一開始就清除群眾，§6.4）
- `scripts/terrain_lab/site_controller.gd`：
  - `check_family_death` 在群眾模式下只等受控人物自己的死亡結算（D6）
  - `advance_team_sustain` 對群眾隊伍只推進吃飯時鐘與飢餓（§4.3 問題三）
  - UI 清單、命令、AI 開關的群眾分支
  - `save_to`／`load_from` 重構
  - 存檔根目錄與測試模式
  - `equipment_changed`、`_captivity_changed` 開頭的群眾分支
  - 人物清單的群眾分支：`cape_policy_guard`、`reconcile_cape_roles`
  - CAPTURED、ESCAPED 的俘虜寫回佇列（§4.4）
  - `_capture_for_save()`，以及 `archive_before_replace`、`_request_exit`、`_archive_family_site` 改用它（§5）
  - 受控人物三種來源的部署（D5）
  - `_control_family_person` 之後通知群眾控制權改變；群眾戰鬥中，`_archive_family_site` 對跨 Site 接續回傳 `UNSUPPORTED`（D6、D10）
  - 讀檔時偵測 `site.crowd`，自動切換成群眾模式；失敗時恢復原模式（D9）
- `scripts/terrain_lab/site_person_actions.gd`：
  - `_person()`、`_body_get`、`_body_set` 的群眾人物介接
  - 群眾作戰期間拒絕其他工作（決策 D4）
- `scripts/terrain_lab/site_captivity_supply.gd`：
  - 新增 `event_change_guard`、`discard`（§4.4）
  - `_body`、`_original_team`、`_home`、`_all_members` 等處的群眾隊伍分支
  - 原有函式的一般模式行為不變
- **§4.3 呼叫點清單裡出現、確實需要群眾分支的其他 `site_*.gd`**：
  - 只能加群眾分支。
  - 必須先列進決策文件，經使用者確認後才能改。
- `scripts/terrain_lab/site_store.gd`：`_validate_crowd`，以及人物集合的擴充。
- `scripts/tests/crowd_c2_*`、`scripts/tests/crowd_c3_*`：新增的測試腳本。

**不可修改：**

- `scripts/terrain_lab/terrain_army.gd`
- 其他原有的遊戲規則檔案

真的需要改動清單以外的檔案時，先停下來，說明理由，取得使用者同意後才能動。

---

## 8. 已知的坑（C1 實際踩過的）

1. **GUI 焦點會吃掉按鍵**：群眾模式在 `TerrainLab._input` 裡，對非文字框的焦點呼叫 `gui_release_focus()`；新增 UI 時也要留意。
2. **地圖邊界**：部署格可能超出地圖。`finalize` 已經會把位置拉回地圖內；任何「設定位置」的 API 都要做同樣的處理。
3. **玩家動作不會自己播**：正式場景的角色是交手呈現器。呈現端要設定 `visual_state.animation_time` 和 `_exchange_pose_dirty`，**不要**關掉 `exchange_enabled`。
4. **換行混用**：`terrain_lab.gd` 裡 CRLF 和 LF 混在一起。修改時要保留原本的換行，用 `newline=''` 讀寫，不要整份轉換。
5. **輸出資料夾**要放 `.gdignore`。
6. **呈現不能影響模擬**：呈現只讀模擬狀態，不存檔、不算進雜湊。事件寫回也只在兩步之間透過 API 進行。
7. **確定性**：每一輪的 L1 都要做一次「1 執行緒對 4 執行緒」的雜湊比對。
8. **寫入後要驗證**：寫出的檔案讀回來，和來源逐位元組比對。
9. **比較存檔前後時，只比規則值**：
   - `stats` 比 A 組（0–17）和 C 組（33–39），不比 B 組耗時（18–32），詳見 §0.4。
   - `state_hash` 不含統計計數，所以雜湊相同不能代替統計比較。
   - 位置只比模擬座標；畫面只驗證「重建後等於模擬座標」。
10. **只讓 `_person()` 回傳同樣格式的字典不夠**：後續的 `_body_get`、`_body_set`、`equipment_changed`、`_captivity_changed` 都會直接使用 owner 的型別。見 §4.3。
11. **不要假設「全軍 MOVE 後退就會脫戰」**：接敵時 MOVE 會停步，潰退的隊伍又會拒絕 MOVE。需要脫戰時，用 §2.1 的場景 D 或 DR。
12. **`commit_change` 需要同一步的預檢**：沒有成功的預檢就呼叫，會觸發 assert。群眾事件要用 `event_change_guard`（§4.4）。
13. **`_capture_positions()` 會整個重建 actors 和 armies**：存檔前寫進 Site 字典的群眾資料會被蓋掉。要用 `_capture_for_save()` 的順序（§5）。
14. **內部命令不能套對外檢查**：`begin_rout` 等內部呼叫者依賴 `set_goal` 裁切座標（§3.1）。
15. **死者不在 `members` 裡是合法的**：`compact_slots` 會移除死者（§6.1）。
16. **受控人物不一定是 `actors.player`**：家族接續可以改控別人，群眾運行中也可能發生（決策 D5、D6）。
17. **C++ `bool` 不能用 `memcpy` 讀入不可信的位元組**：要先讀成 `uint8_t` 再檢查（§6.1）。

---

## 9. 施工順序與回報

**施工順序：**

1. **決策與清單**：§9.1 的決策 D1～D11 已由使用者定案。§9.2 的四份清單由實作者整理、使用者核可，核可後才開始寫程式。
2. **§1 資料安全**，以及 **§5 的 `save_to`／`load_from`／`_capture_for_save`** 重構。先交付，並跑一般模式回歸。
3. **C2-A 命令**：L0 → L1 → L2 → L3。
4. **C2-B**：依序做：
   1. §4.3 的結算尾段與人物介接
   2. §4.1、§4.2 的交接與往返測試
   3. §4.4 的俘虜寫回佇列、供養預檢與封存
   4. §4.5 的事件測試
5. **C3**：先修 §6.1 的安全載入，必拒絕的壞結構與隨機變異 fuzz 都要通過；再做 §6.2～§6.7。
6. **每完成一段**，就在 `SITE_CROWD_10K_PLAN_SOL.md` 新增「C2 結果」或「C3 結果」小節。

### 9.1 使用者的決定（2026-09-30 定案）

| 編號 | 問題 | 決定 | 相關章節 |
|---|---|---|---|
| **D1** | 群眾人物的紀錄放在哪裡 | **放進 `site.armies`**，roster schema 2，加 `crowd` 標記 | §4.1、§5、§6.3 |
| **D2** | 部署時是否為每名群眾士兵建立實物 | **每人都建立**，照 `initialize_team_items` | §4.1、§4.4 |
| **D3** | 戰鬥中彈藥以哪邊為準 | **原生為準**，固定同步點單向寫回 cargo | §4.4 |
| **D4** | 群眾戰鬥中對群眾人物做搜刮、拘束、解綁、換裝、贖回、逃脫 | **一律拒絕**，回傳 `CROWD_ACTIVE`，收兵後再做 | §4.1 |
| **D5** | 受控人物不是原玩家角色 | **這版就支援**：可以是 `lab.character`、`lab.npc` 或名冊裡的人 | §4.1 第 5 項 |
| **D6** | 群眾戰鬥中受控人物戰死 | **戰死就換繼承人**，戰鬥照常繼續。照原本的流程暫停並跳出家族視窗，由使用者選繼承人；只等他自己的死亡結算，不等其他人。這個版本的繼承人一定在同一個 Site；跨 Site 接續在群眾戰鬥中回傳 `UNSUPPORTED` | §4.1 第 6 項 |
| **D7** | 群眾隊伍的供養鍵 | **沿用原隊伍的 `team_id`** | §4.3、§4.4 |
| **D8** | 讀檔時群眾區段無效或不相容 | **整份拒絕**，場景與檔案都不動 | §6.4 |
| **D9** | 一般模式讀到群眾存檔 | **自動切換成群眾模式再讀**；只持續到收兵 | §0.1、§6.4、§6.6 第 9 項 |
| **D10** | 繼承人在同一 Site 但不在群眾戰鬥裡 | **身分不變，可以自由操作；敵對的人照樣會攻擊他**。技術上在他的位置加成一人隊伍的受控士兵，不編入任何名冊 | §4.1 第 7 項 |
| **D11** | 被編進群眾的俘虜，看守者不在群眾裡 | **照戰場規則，沒人看守就會逃**（30 遊戲秒）。之後的版本會有戰俘建築：關進去的是囚犯，只有被解放才能逃；C2／C3 不做，但原生要保留標記的位置 | §4.2 |

- §6.3 的群眾區段格式跟著 D1：群眾名冊放在 `site.armies`，`site.crowd` 只放 blob、識別值、隊伍引用與受控人物引用。
- 之後如果要改任何一項決定，先改這張表，再改相關章節和測試。

### 9.2 由實作者整理、使用者核可的清單

這些不是設計選擇，而是「把程式碼裡的現況完整列出來」。實作者整理好之後給使用者看，核可後才開始寫程式。

| 編號 | 清單 | 章節 |
|---|---|---|
| **R1** | 完整交接表：每人、每隊的原生欄位，對應到 Site 欄位名稱；以及「群眾不經手、保留原值」的欄位。另附每一個浮點欄位的合法範圍與依據（寫入它的程式位置），並註明範圍所依賴的前提「每步 0 < `dt` < 1」由原生、C API、Godot 綁定三層共同保證 | §4.2、§6.1 |
| **R2** | 呼叫點清單：所有可能遇到群眾人物的 `person.owner`、`combat_hot_get/set`、型別轉換，以及每一處的處理方式 | §4.3 |
| **R3** | 兩張 ID 欄位清單：「目前引用」和「歷史來源 ID」 | §4.1 |
| **R4** | 直接呼叫 `_capture_positions()` 的全部位置 | §5 |

**回報格式：**

```
【C2-A 命令｜第 N 輪｜輸出資料夾 out_c2/<時間戳>】
結論：通過／未通過（未通過項目：…）
L0：原生測試 X 項，失敗 0（ASan：通過）
L1：步驟 1～10（每步一行：實測值／門檻／回傳碼）
L2：同上，另附截圖路徑
共通關卡：非法格 0、非法邊 0、冷卻違規 0、無 SCRIPT ERROR、無崩潰、一般模式回歸 OK、資料安全快照一致
效能：每幀平均 / p95 / p99（ms），新增的每步成本（ms）
改了哪些檔案（路徑清單），DLL 是否重編（新的 dll_sha256）
下一步
```

數字一律附單位。使用者沒有要求時，不貼整份 log。

---

## 附錄 A：第 2 版修正對照（第一次審閱）

| # | 問題 | 修正位置 |
|---|---|---|
| 1 | 測試可能覆寫正式存檔 | §1 資料安全（測試路徑、唯一 site.id、自動保存與封存改寫、前後快照、備份、複本） |
| 2 | 人物狀態與實物交接缺漏；C1 恢復部署前 HP | §0.3 暫時行為清單、§4.1、§4.2 |
| 3 | 群眾分支的 `continue` 跳過死亡結算 | §4.3 |
| 4 | 軍令規則不一致（AI 接管、RETREAT、ATTACK 目標） | §3.1、§3.3、§3.4 |
| 5 | 壞檔、不相容時部分載入的資料保全 | §6.4（全有或全無，驗證成功後才清除） |
| 6 | 檔案範圍太窄；原生 load 不安全 | §7、§6.1 |
| 7 | stats 含耗時；畫面位置比較會誤判 | §0.4、§6.5、§8.9 |
| 8 | 事件等式錯誤；可能空跑通過 | §4.5 |
| 小 | 預期拒絕與「不能有錯誤」矛盾 | §3.4 |
| 小 | `save_current()` 回傳 void | §5 |
| 小 | build 識別 | §6.2（DLL SHA-256） |
| 小 | canonical verifier、逾時、保留結果 | §2 |

## 附錄 B：第 3 版修正對照（第二次審閱）

| # | 問題 | 修正位置 |
|---|---|---|
| 1 | 人物唯一性規則會拒絕合法存檔（名冊放在 armies；玩家同時在原生與 `actors.player`） | §4.1 定義「紀錄」與「引用」，照遊戲 `player_member` 的慣例處理玩家；§6.3 改成依這個規則驗證；§6.5 加上必須通過的對照組 |
| 2 | 只補 `_person()` 不夠：`_body_get/_body_set`、`equipment_changed`、`_captivity_changed` 會直接使用 owner 的型別 | §4.3 新增群眾 owner 物件、呼叫點對照表、欄位對應，並要求列出完整的呼叫點清單；§7 |
| 3 | 俘虜漏了實物封存，可能複製彈藥 | §4.4 的彈藥單向同步規則、完整的俘虜交易（同步 → 封存 → 清空原生 → 寫紀錄）、逃脫時不恢復裝備，以及「被俘 → 封存 → 逃脫」守恆測試 |
| 4 | 人工命令失敗時一律恢復成 AI | §3.1 改成保存原旗標、失敗時恢復原值；§3.3 的步驟 9a、9b 分別測 AI 隊與手動隊 |
| 5 | 安全載入缺數值驗證（例如 `chunk = 0` 除以零）；fuzz 要求「一律 false」不成立 | §6.1 補索引一致性、數值範圍、有限浮點數、列舉、布林，並要求共用的 `World::validate()`；fuzz 分成「必拒絕的壞結構」和「隨機變異」兩類，各自的判定方式 |
| 6 | 交接欄位不完整；保存 blob 不能代替收兵交接 | §4.2 的每人、每隊欄位表，以及非預設值的「匯入 → 戰鬥 → 收兵 → 重部署」往返測試 |
| 7 | 被俘期間不失血；看守失能後有逃脫等待期；部分事件的 person_id 為 −1；HP、KO 沒有逐次事件 | §4.5：改成「被俘後受擊致死」並測「被俘期間不失血」；逃脫等待期的驗證方式；逐種驗證事件欄位；精確值向原生查詢 |
| 8 | 「MOVE 後退就會脫戰」不成立；§6.5 跑 30 秒就存檔 | §2.1 新增場景 B（大戰，不要求脫戰）與場景 D（一定會脫戰）；§4.5、§6.5、§6.6 改用場景 D；戰鬥中的續行一致性只用原生 blob 測 |
| 9 | stats 不是「18 以後全是耗時」 | §0.4 分成 A 組（0–17）、B 組（18–32，耗時）、C 組（33–39，時鐘與計數），並註明 `state_hash` 不含統計計數；§6.5、§8.9 |
| 10 | `save_to()` 漏了恢復自動保存 | §5：成功時清除 `_auto_save_blocked`，封存與離開也照同樣的旗標處理，並加回歸測試 |
| 自查 | 原生 `order_*` 不驗證參數，越界索引會讀到陣列外的記憶體 | §0.4、§3.1 改成回傳結果碼，並在改動任何狀態前先檢查；§3.2 的錯誤參數測試要在 ASan、UBSan 下跑 |

## 附錄 C：第 4 版修正對照（第三次審閱）

| # | 問題 | 修正位置 |
|---|---|---|
| 1 | 俘虜交易缺少供養預檢；原生已設被俘、ESCAPED 先刪關係，都會讓現有預檢失敗 | §4.4：新增 `event_change_guard`、`discard`，建立俘虜寫回佇列；CAPTURED、ESCAPED 各自的「預檢 → 提交」順序；暫時與永久失敗的處理；「供養拒絕時不會部分提交」測試；§7 |
| 2 | 存檔順序會被 `_capture_positions()` 蓋掉 | §5：`_capture_for_save()` 依序為「寫回現場物件 → 取基礎快照 → 合併群眾資料 → 斷言」，四條寫檔路徑都改用它，並加測試 |
| 3 | 安全載入漏了流場、`field_queue_`、`edge_ok`；C++ `bool` 的讀取 | §6.1：流場與佇列的範圍、重算 `edge_ok` 並比對、私有陣列、`bool` 安全讀取與逐欄讀寫；對應的人工壞檔 |
| 4 | 隊員規則會拒絕重整後的合法戰後存檔 | §6.1：只要求「存活者」在自己隊伍的 `members` 裡；加入重整前與重整後的合法對照；§6.5 |
| 5 | 拒絕地圖外座標會破壞地圖邊緣的自動潰退 | §3.1：對外的 `host_order()` 和內部的 `order_*` 分開，內部照舊裁切；§3.2 加上四角、四邊的自動潰退測試 |
| 6 | 命令結果碼自相矛盾（int 與 false 混用） | §0.4、§3.1 的結果碼表；§3.2、§3.3 一律比較確切的碼；C API 與綁定要能正確傳遞結果碼 |
| 7 | 歷史原持有者不一定仍有人物紀錄 | §4.1 區分「目前引用」與「歷史來源 ID」，用兩張明確的欄位清單；§6.3；§6.5 加上退休工人的合法對照 |
| 8 | `actors.player` 不一定是受控人物 | §4.1 定義受控人物，新增決策 5（建議本版限制，也列出一般化的做法），兩種做法都有測試；§4.3、§4.4、§5 改用「受控人物」 |
| 9 | 逃脫倒數缺少清醒與起身條件 | §4.5：五項條件全部成立才開始計算，任何一項中斷就歸零；L0 加上「擊暈中看守者死亡不能逃脫」 |
| 設定 | 場景 D 禁止弓弩，往返測試卻需要弓兵 | §2.1 新增場景 DR（含弓兵的可脫戰場景）；§4.2 的往返測試改用 DR |

**第 4 版自查另修（對照程式碼的一致性檢查）：**

| 問題 | 修正位置 |
|---|---|
| RETURN 不是對外命令（C API 與綁定都沒有），原本的測試無從呼叫 | §0.4、§3.1 改成「追擊結束時由原生自動切換」；§3.2 改測自動 RETURN |
| L2 只能透過 UI 函式下令，但部分步驟需要直接呼叫 crowd | §3.4 明列 L2 跑哪些步驟，其餘只在 L0、L1 跑 |
| MOVE 的非法目的地會先被宿主預檢擋下，根本到不了原生 | §3.1 新增第 0 步「宿主預檢」；§3.3 的 9a、9b 改驗「原生沒有被呼叫」，另加 9c、9d 用測試掛鉤驗還原路徑 |
| 列出的場景產生不了 COMMAND_LOST | §4.5 新增「整隊沒有可接任的人」場景 |
| 被俘人數比對會被正常的處理延遲誤判 | §4.5 排除 `_pending_deaths` 和俘虜寫回佇列裡的人；兩者清空時再做完整比對 |
| 死者保留舊的 slot，照原本的規則會被當成壞檔 | §6.1：slot 規則只套用在 `members` 裡的士兵 |
| `form` 不能是 −1；`hostile_` 是固定 256×256 表 | §6.1 更正；補上 `cell` 的範圍 |
| L0 看不到 cargo 和封存箱；場景 DR 做不出俘虜流程 | §4.4 守恆測試分成 L0（只驗原生）和 L1（自己的小場景）；§2.1 修正場景 DR 的用途 |
| 只調低士氣不會讓 RETREAT 合法 | §3.2、§3.3 改用 `routed = 1`；定義已潰退時 RETREAT 的行為 |
| 檢查順序未定；`NO_AUTHORITY` 不在結果碼表裡 | §3.1 明訂原生與 GDScript 兩層的檢查順序，把 `NO_AUTHORITY` 列為 GDScript 專用 |
| `soldier_view` 的索引寫法會讓人讀錯 | §6.5 改成「索引 9、10（從 0 起算）」 |
| 原世界跑完 20 秒後可能又交戰，這時 `load_from` 會被拒絕 | §6.5 改成在新的、沒有交戰的場景讀回 |
| 場景 D 裡玩家所在的隊伍是 AI 還是手動沒寫清楚；同一個佇列有三種名稱 | §2.1 設為手動；統一稱為「俘虜寫回佇列」 |

## 附錄 D：第 5 版修正對照（第四次審閱）

| # | 問題 | 修正位置 |
|---|---|---|
| 1 | 未建置的流場 `goal = −1` 仍能通過驗證，下一步越界 | §6.1：在佇列裡或被隊伍引用的流場，`goal` 都必須合法；加兩個人工壞檔 |
| 2 | 供養時鐘沒有推進，俘虜交易會一直 `BUSY` | §4.3 問題三：`_advance_fatigue` 拆成三部分，供養時鐘用同一段遊戲秒推進；加「隔一段時間再捕獲、逃脫」測試 |
| 3 | 沒有物品可封存時，佇列會永久卡住 | §4.4：空選擇不建立容器，`sealed_container = ""`；加「再次被俘」測試 |
| 4 | 拘押者和看守者被混成同一個人 | §4.2：原生 `captor` 對應 `guard_id`，`captor_id` 保留作供養歸屬；§4.5 改比 `guard_id`；加「拘押者、看守者分屬不同隊伍」的往返測試 |
| 5 | 受控人物的 `loot_settled`、`remains_id` 會存錯 | §4.3：受控人物的這兩個欄位直接讀寫 `lab.character`；§5 加受控人物死亡後的存檔測試 |
| 6 | 部署限制擋不住戰鬥中的家族接續 | §4.1 新增決策 D6，並加上戰鬥中接續的測試 |
| 7 | `slot` 唯一性會拒絕同隊多人倒地的合法存檔 | §6.1：只有非負 slot 必須唯一；加合法對照案例。另外放寬隊長欄位：不要求在 `members` 裡，也不要求存活 |
| 另 | 待決事項分散各節 | §9.1 集中為 D1～D11 並記錄使用者的決定；§9.2 列出四份由實作者整理的清單 |
| 自查 | 家族視窗要等全場死亡結算清空；群眾隊伍的士氣會被 Site 再算一次；看守者不在群眾裡；D9 與檔案範圍規則矛盾；使用者操控的一人隊伍沒有標記 solo；戰鬥中加人的項目不完整；一人隊伍會接受命令；`compact_slots` 的說明有誤 | §4.1 第 6、7 項（只等自己的死亡結算、`solo` 定義、加人清單、`NO_ORDERS`）；§4.3 問題三（隊伍供養只推進吃飯與飢餓）；§4.2（D11）；§7；§6.1 |
| 另 | 使用者決定 D5 = 支援、D6 = 立刻換繼承人、D9 = 自動切換、D10 = 場外繼承人照樣會被攻擊 | §0.1、§4.1 第 5～7 項、§4.3、§4.4、§5、§6.3、§6.4、§6.6、§7 |

## 附錄 E：第 6 版修正對照（第五次審閱）

| # | 問題 | 修正位置 |
|---|---|---|
| 1 | 飢餓傷害用 `set_soldier_state` 寫入，死亡不會觸發結算 | §4.3 問題三「飢餓傷害」：新增 `apply_environment_damage`，致死時走完整死亡流程、不延長戰鬥時鐘；加一般人物、俘虜飢餓致死與非致死測試 |
| 2 | 原生士氣假設糧食充足，缺糧會被當成足糧 | §4.3 問題三「士氣只有一個負責端」：原生是唯一負責端，Site 經 `set_sustain_input` 提供吃飽與否和士氣增減；加零口糧與足糧的對照測試 |
| 3 | 控制名冊成員會讓整隊跟著他走 | §4.1 第 5 項：只有一人隊伍以受控人物為中心；一般隊伍只改他個人的輸入；加「接續後其餘隊員仍執行原命令」的驗收 |
| 4 | 安全載入漏查隊伍本身的浮點資料 | §6.1：隊伍浮點欄位全部有限、座標在地圖內、數值範圍；加「只變造隊伍中心」等壞檔案例 |
| 5 | 戰鬥中加人沒有初始化新隊伍的計數 | §4.1 第 7 項：只初始化新增的隊伍與人；加人後、第一步之前就要通過驗證與存讀 |
| 文字 | 受控人物的存檔測試固定檢查 `actors.player` | §5 測試：改在實際的紀錄位置檢查，三種受控情況各一次；另保留「原玩家角色戰死、控制權已轉走」的案例 |

## 附錄 F：第 7 版修正對照（第六次審閱）

| # | 問題 | 修正位置 |
|---|---|---|
| 1 | 計時值一律要求 ≥ 0，會拒絕正常存檔（`order_delay`、`pursuit_left` 會扣過零） | §6.1：逐欄定義範圍表，過期負值合法；禁止讀檔時截成 0；所有場景測試每步呼叫 `validate()`；加兩種負值狀態的合法存讀測試 |
| 2 | 飢餓死亡會再被算一次戰損士氣 | §4.3「飢餓傷害」：致死時只更新這一個人的生命檢查點；加「同一步一人餓死、一人戰死」與兩個對照組的測試 |
| 3 | 重啟驗收讀的檔可能已被自動保存改寫 | §6.6：固定的 `baseline.json` 與自動保存的 `current.json` 分開；每次讀基準檔前比對 SHA-256 |

## 附錄 G：第 8 版修正對照（第七次審閱）

| # | 問題 | 修正位置 |
|---|---|---|
| 1 | 「混合死亡」與「只有戰死」兩組的分母不同，不能要求扣分相同 | §4.3「飢餓傷害」的士氣對照：每組各自寫出正確公式；要直接比較時，另做起始只有 N−1 人的對照組 |
| 2 | `dt` < 1 目前只有 Godot 綁定保證 | §6.1：原生 `step`／`step_clock` 與 C API 也要檢查，並寫進 R1 |
