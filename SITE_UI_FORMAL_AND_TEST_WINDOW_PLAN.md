# Site 正式介面與獨立測試視窗詳細實作計畫

日期：2026-10-01。狀態：**正式／測試視窗與輸入分離已實作，驗收依證據分項確認**。本文保留施工前查核與原驗收矩陣；程式已落地不代表全部桌面互動驗收通過。

本計畫承接使用者指定方向：Site 右側功能欄改為分類的可移動視窗，用來模擬正式版 UI；所有測試選項集中於唯一測試視窗，再於窗內分類。正式介面使用遊戲內嵌入式 Window，測試工具使用唯一原生桌面 Window，並以未來可整個移除為設計條件。

本文是施工與驗收依據，不代表測試已通過。正式玩法尚未提供的授權、外交同意、親屬建立或生產取得途徑，不在本輪借用測試權限補成正式功能。

## 已落地範圍與待驗證界線

- `SiteController` 已建立可移動「功能」選單及第 4 節十類正式嵌入式、非獨占 Window；後續依使用者要求另加可捲動的唯讀「隊伍資訊」窗，部署完整報告不再撐大左下結果區。FPS 恢復常駐頂欄右側，左下訊息最多三行並保留完整提示；關閉隱藏原實例，原相機可用區按常駐 HUD 計算。
- `-- --site-test-ui` 才動態安裝唯一 `SiteTestWindow`，F12 切換原生桌面窗，第 5 節七分頁共用此宿主。無旗標不建立測試窗或 `TerrainLabUI`，缺少模組時回報並繼續正式啟動。
- Movement 測試 checkbox 只設定 `movement_input_enabled` 並清除待執行輸入，不變更人物可見性或 NPC processing，也不取消原 owner 已承諾的步進。測試放置另行明示啟用；視窗隱藏時復位。
- 原人物、隊伍、實物、車輛、工作、時鐘及 SiteStore owner 不變；角色編輯控制借還原 `editor_root`，保留原模型／SubViewport／Sprite 引用。本次不變更存檔 schema，UI geometry、分頁與草稿不進玩法快照。
- **待驗證：**OS 手動拖曳／縮放、完整跨窗真實鼠鍵及多螢幕／Windows DPI 矩陣。headless 結構／事件斷言及 viewport 圖片只能支持各自檢查範圍；第 17 節仍是驗收要求，不能整表視為已通過。

施工證據見 [交接紀錄](D:/worldgoing/output/site_ui_windows_20261001/README.md) 與 [驗證索引](D:/worldgoing/output/site_ui_windows_20261001/verification_index.json)。最後 editor/import、正式／測試開關兩案契約及三種解析度 GPU 畫面已通過；實際缺少測試模組的隔離副本也通過冷啟動、載入、權限契約與正式 GPU 畫面。`site_vehicle_transport_test` 與 `site_support_main_test` 兩項補充回歸仍失敗，原因與原始結果均保留；本次沒有修改其玩法 owner 或放寬到達／危險路線斷言。

## 1 工作範圍與完成定義

必須完成：

1. 右欄改成可移動的正式功能選單，各正式分類能獨立開啟、移動、縮放及關閉。
2. 正式畫面不含生成、清場、補物、改能力、模擬 NPC 指揮、代替對方確認等測試操作。
3. 唯一 Site 測試視窗包含所有 Site 測試入口、分類與測試專用表單。測試入口新建的共用交易子視窗嵌入該測試窗，不另開第二個桌面工具窗；若同類交易已存在，優先遵守第 11 節唯一實例規則。
4. 不建立測試視窗、也不建立舊 TerrainLabUI 時，正式啟動、控制、渲染、存讀及已具備的玩家操作仍正常。
5. 關閉、停用或未攜帶測試 UI 模組，不影響原人物、隊伍、實物、車輛、已提交工作或玩法存檔。
6. 原測試指揮入口仍能在明示的測試上下文使用；原權限、版本、容量、位置、作業及保存守衛繼續生效。

本輪不實作：新遊戲主選單、完整招募／任免／外交同意／親屬制度、額外生產經濟、World/Region 整合、Crowd 新能力、存檔格式升級、另一套人物或渲染器。跨重啟布局記憶、停靠吸附、多套工作區及視窗管理插件也不加入。

## 2 查核基準與並行工作

查核目錄 D:/worldgoing，當次 HEAD 為 24eaf20。相關 TerrainLab、SiteController、車輛 owner、project.godot 與架構文件已有未提交變更；它們不屬本文件新增的變更。

行號會因其他 session 改動而移動，施工時以「檔案＋函式名＋實際呼叫者」重新定位。本次讀取完整，未遇到鎖檔。後續若因另一 session 鎖定、半寫入或修改衝突而無法可靠讀取，先用可用的原生狀態／等待機制等其完成，再重讀；不刪鎖、不覆寫、不回退其他工作，也不以舊副本冒充最新版本。

PROJECT_ARCHITECTURE.md 是責任依據。SITE_BUILDING_REQUIREMENTS_AND_IMPLEMENTATION_PLAN.md 是並行的建設規劃；本計畫只重新安置建設介面，種類、成本、尺寸、選址與預览均讀原 Runtime，不能在 UI 另複製一套建物定義或提前實作該規劃。

正式入口維持 project.godot → scenes/terrain_lab/TerrainLab.tscn，不重命名 TerrainLab，不另造正式主場景。

## 3 現況與必須解開的依賴

| 現況位置 | 已確認的依賴 | 本輪必要處理 |
| --- | --- | --- |
| TerrainLab._ready、generate_from_ui、bind_terrain | 啟動透過隱藏 seed_input／preset_dropdown 生成；載入後又回寫控制項 | 生成入口改收明確 preset／seed；UI 只整理參數；保留 archive_before_replace |
| TerrainLab._advance_movement_input、_unhandled_input | movement_toggle 不存在會停用正式移動，其他分支還會直接解參考 | 操作可用性歸回原 TerrainLab；不以隱藏 checkbox 保存正式狀態 |
| TerrainLab.select_army_target、_update_info | 選人寫 selected_army_label；定時更新隱藏診斷 Label | 保留原人物 ID，正式 HUD 讀取；診斷字串僅測試頁可見時更新 |
| TerrainLab.fit_map、SiteController.setup／_layout | 硬查 TerrainLabUI 節點與左右固定預留 | 移除舊欄位節點依賴，改由常駐正式 HUD 決定可用區 |
| SiteController._build_combat_window | 正式本隊、名冊、後勤、訓練及軍令也建在混合測試窗 | 先抽回正式 builders，再移走測試內容 |
| SiteController.setup、_build_vehicle_controls | 必須找到 TrialVehicleControls，且有非空 assert | 正式與測試車輛表單分入口，不依賴測試容器存在 |
| SiteController._formation_source | selector 不存在時預設 trial | 正式明確使用玩家來源；禁止 fallback 成 NPC 測試權限 |
| SiteController._player_corps_reposition | 正式軍團指令讀 _selected_trial_team | 改讀正式選取的真實 team_id，交原命令驗權 |
| SiteController._sync_trial_captain_selection | 測試選隊同步隊長呈現 | 正式選隊接原呈現入口；測試選取不得暗改正式命令目標 |
| SiteController._chosen_supply_team | 玩家本隊與我方測試隊共用 selector | 正式供養讀原本隊／合法後勤目標，測試來源獨立 |
| SiteController._vehicle_requester／_assign_trial_vehicle／_transfer_trial_vehicle | 代選 NPC 隊長，操作帶 test_dispatch=true | 正式 requester 使用 controlled_person_id，test_dispatch=false |
| SiteController._open_roster | 勾選 ReceiverCommanderConfirmation 可模擬接收方同意 | 移入測試分頁；正式沒有真正確認時不能提交該轉籍／合併 |
| SiteController._open_family_registry | 手填 Site、快照路徑、人物 ID、年齡與 complete | 歸測試情境資料；正式只讀名單與原合法接續 |
| SiteController.tick／update_ui／_update_combat_window | 正式刷新依賴 combat_window 存在或可見 | 正式與測試顯示刷新分開，原模擬時鐘與步進不變 |
| SiteController._begin_facing_move | 無條件隱藏 combat_window | 收起實際發起介面；暫時讓出地圖不等於取消候選 |
| SiteController.load_from／bind | 更換原資料，但未集中失效所有普通表單 | 成功換場／換人後使舊草稿及交易上下文失效 |
| TerrainTestCharacter.initialize_visual | 隱藏 editor／SubViewport 同時供正式 player_sprite | 保留原呈現來源，只整理可見測試操作，不刪 editor 或複製骨架 |

建議施工前再次搜尋所有上述函式與欄位呼叫者；不能以新增 null 檢查取代正式狀態遷移，也不能以假隱藏控制項讓測試勉強通過。

## 4 正式畫面與分類

常駐頂欄保留日期／時間、速度、暫停、目前控制人物摘要及「功能」按鈕。左下保留結果、目前地圖工具與選格摘要。後續使用者指定 FPS 常駐右上；格線、碰撞框仍由測試診斷控制。隊伍完整資訊另開唯讀窗，不放入左下結果區。

原右欄改成可移動「功能」選單，只放正式分類入口。初始放在頂欄下方靠右處；它不形成固定 590px 保留區。所有正式工具窗預設關閉，按需開啟；首次進場顯示功能選單。頂欄入口可找回關閉的選單。

| 穩定視窗 ID | 顯示名稱 | 正式內容及邊界 |
| --- | --- | --- |
| map | 地圖與土地 | 地圖／資源／農耕／放牧／淡水／建設檢視、圖例、資源篩選、營地近景、全圖；不含 seed 重生或瞬移 |
| work | 採集與工作區 | 手動採集、採集／清理／勘探區、原隊員指派／停止、原工作區清單與啟用狀態；保留現有優先規則 |
| construction | 建設與製作 | 原建築種類、選址／材料／工時預覽、施工、運作、拆除／取消、已有弓弩與彈藥製作；不新增配方 |
| equipment | 倉儲與配裝 | 營地容量／庫存／供水、交貨、領取、本人與合法指定人物實物配裝、原軍事首長領裝標準 |
| people | 人物與俘虜 | 所選人物／遺留物、搜刮與回收執行者、原攻擊／救助、拘束／解綁／贖回、逃脫及押送；仍依原行動與權限 |
| family | 家族與接續 | 檢視已登錄家人、原死亡接續／等待安全歸檔；缺資料維持 UNREGISTERED／DATA_MISSING |
| team | 隊伍與軍令 | 本隊狀態、名冊、接任順位、正式退隊／派工／合法拆分、實物領裝、軍令／陣型／終點面向與原軍團權限 |
| supply | 後勤與訓練 | 原本隊口糧、合法來源與目標、交糧／取消、供養／士氣摘要、訓練命令 |
| transport | 車輛與運輸 | 檢視／定位現有車輛；正式指派／停止／裝卸只用實際玩家身份、原 owner 的非測試入口 |
| system | 存讀與介面 | 保存、載入、已有存檔、原保存限制、收起一般工具窗及重設位置；〔審核二〕音效設定：SFX 音量滑桿與靜音開關，以 Godot ConfigFile 存本機設定、與玩法存檔分開（來源：`GAME_AUDIO_IMPLEMENTATION_PLAN.md` R2-3=A，Nekki 2026-10-08） |

同一功能可有跨分類捷徑，但只打開同一個表單。例如本隊領裝可由隊伍頁進入，不複製另一組領裝 callback 或庫存。

「加入我方測試軍隊」目前會對獨立 Actor 直接使用 lab.army，沒有正式選隊／招募互動。本輪將這個測試入隊入口留在測試窗；正式已有隊籍的玩家照常查看與下合法命令。不得把加入第一支測試隊包裝成完整招募。真實玩家加入指定隊伍的正式流程留作玩法缺口，不在這次另建制度。

## 5 唯一測試視窗與分頁

測試視窗標題「Site 測試工具」。使用 Godot Window.force_native=true、非獨占、可拖移／縮放；不製作正式版皮膚、不預設強制置頂。其內採原生 TabContainer，每頁有自己的捲動區與結果區。

| 分頁 ID | 分頁名稱 | 遷入內容 |
| --- | --- | --- |
| scenario | 場景與人物 | 舊 seed／preset／Previous／Next／Random／Generate、原測試放置、movement 測試、NPC 命令／陣營／反擊／復活及角色部件／動畫入口 |
| deployment | 隊伍部署 | 三方陣營、角色／兵種、人數、車輛名額、男女比例、訓練與幹部能力、初令／AI／進場方向、批次部署／追加／清場、測試入隊 |
| command | 軍令與 AI | 測試隊伍選擇、模擬隊長命令、測試陣型／面向／撤退／追擊、AI 開關、測試軍團任命 |
| stock | 裝備與物資 | 測試國別／文化／首長登錄、測試實物補入、測試標準及 NPC 整隊領裝；沿原容量／唯一 ID／圖集准入 |
| logistics | 後勤與車輛 | 指定測試隊伍、模擬隊長供養／調度、原測試車輛指派／停止／實物裝卸 |
| relationships | 人物關係與接續 | 接收隊 NPC 同意模擬、原家族 ID／快照／年齡／完整度登錄與原接續情境設定 |
| diagnostics | 診斷與顯示 | 既有 FPS／生成耗時／戰鬥傷亡摘要、格線／高度、武器／身體碰撞及原診斷資訊 |

不新增原本不存在的任意造物、秒殺、萬能改參數或自動情境產生器。原先只在 NPC 存在時才有效的測試繼續維持該前提，不能為了填滿分頁恢復預設工人。

測試場景設定成功後，原資料仍由既有 owner 保存與模擬。關閉測試視窗不清人、不撤銷國別、不恢復物資、不回滾已接受的命令。

## 6 啟用與移除方式

已採用唯一明示啟動旗標 --site-test-ui（放在 '--' 後）；無旗標時採正式 UI，連測試視窗與舊 TerrainLabUI 都不建立。現有 --crowd 或測試保存路徑參數不隱含啟用 UI。

新增一個腳本 scripts/terrain_lab/site_test_window.gd，沿現有程式建 UI 的風格，不另加通用插件、控制匯流排或常駐管理器。正式初始化只有一處可選載入／安裝接點；避開對該腳本的 preload、scene ext_resource 或全域 class_name 強型別依賴。

安裝順序：正式 owner 與 HUD → 現有生成／載入流程 → 如明確啟用，再建立測試視窗，讀取目前原資料初始化表單。開啟測試窗本身不得生成隊伍、補物、授職或切換人物。

啟用後由 F12 找回／切換同一視窗，僅在測試模組存在時處理。此入口不放入正式分類清單。無旗標時不註冊該開發操作。

關閉按鈕只隱藏；再次開啟保留本次程序的位置、尺寸、分頁及未失效草稿。正式發行不攜帶測試 UI 腳本／入口。若測試模式明示啟用但檔案缺失，回報測試工具不可用，正式 UI 繼續初始化；不得無聲建立另一套工具。

移除驗收的含義是「正式 UI 不需要這個腳本」，不是刪除名稱帶 Test／Trial 的正式人物類別、模擬功能、fixtures、歷史證據或共享資產。

## 7 原責任與允許的介面資料

| 所有者 | 保留責任 | UI 可持有的資料 |
| --- | --- | --- |
| TerrainLab | 原場景、人物／隊伍引用、正式輸入、Camera2D、生成／綁定與原軍令入口 | 正式輸入可用狀態、原 selected_army_target、必要的狀態文字轉接 |
| SiteController | 正式 UI、單一選格／操作模式／執行者、原命令轉接、共用交易表單、上下文失效、存讀守衛 | 視窗引用、位置、選項、原 ID、未提交候選與顯示快取 |
| SiteTestWindow | 測試分頁、測試表單草稿、測試選取與模擬指揮轉接、可見時診斷刷新 | stable ID、表單數值及短期原 owner 引用；不得持有替身人物／庫存 |
| TerrainData／Runtime／PersonActions／EquipmentOrders／Army／Vehicles 等 | 原資料、授權、預檢、步進、原子結算與原角色呈現 | 不移入視窗 |
| SiteStore | 原格式、校驗及原子保存／載入 | 不加入任何 UI schema |

正式 API 呼叫方向仍為正式 UI → 原 Controller／Lab → 原 owner。測試入口也呼叫原 owners，原先明示測試能力只在測試轉接內傳入。視窗 host、焦點、頁籤或「某測試窗已開」不能決定授權。

供正式選隊使用的 ID 選取是 UI 狀態；不得從 _selected_trial_team 偷讀。隊伍／人物已消失時停用操作並顯示原因，不能改選另一隊繼續提交。

## 8 舊 TerrainLabUI 的必要移轉

1. 把現行生成實作抽為原 TerrainLab 的參數入口，保留 archive_before_replace、失敗不換圖與原 bind_terrain。啟動仍用現行梯田高地與 seed 12345，再沿既有程序載入 current；不新增生成設定存檔。測試表單負責整數字串檢查與 Random 等便利操作。
2. 正式移動／跑步／攻擊／防禦／技能／合法騎乘不再讀 movement_toggle；改讀原 TerrainLab 的正式輸入判斷。測試 checkbox 僅是明確輸入覆寫入口，沒有該 checkbox 時必須預設正常控制。
   原地圖點選放置／瞬移分支只在明示的測試放置模式可達；不能因正式輸入預設可用而讓普通左鍵點選搬動人物。
3. 把 status.text 的正式結果改送既有 SiteController.message／show_result，必要時只新增 TerrainLab 一個薄文字轉接；不建立事件日誌系統。測試操作結果歸測試頁並按需要同步主狀態。
4. 選人只寫原 selected_army_target；正式人物摘要從其讀取。正常攻擊／救助遷入正式人物操作，不因原來按鈕放在開發欄就一起刪掉。
5. 把參數、FPS、接觸統計、舊 army_info 等字串組裝收進測試診斷刷新。既有 _update_info 呼叫者（包含 crowd_clear_handoff）改為安全的選配刷新或移除純 UI 呼叫，不影響原 handoff。
6. 移除 get_node("TerrainLabUI") 的生成、hide、布局與鏡頭依賴。NPC 存在時也不可再回寫不存在的 npc_allied_toggle。
7. 不刪 TerrainTestCharacter／TerrainTestNPC／TerrainArmy 等真正 owner，不更動原小步、Reservation Grid、碰撞、時鐘或資料保存。

## 9 角色編輯器的特殊呈現邊界

TerrainTestCharacter.initialize_visual 建立的 HumanCharacter3DEditor 不只是測試工具：preview_host 指向原 Actor，preview_viewport 是正式地圖 Sprite2D 的材質來源。正式模式仍需保留這份原 editor、模型、SubViewport 與必要隱藏載體，不能因「測試窗不建立」將其刪除。

Site 內既有「Player parts / animation」不能只搬按鈕卻再開第二個桌面工具窗。規劃如下：

- 唯一測試窗在「場景與人物」頁提供原編輯控制區的顯示位置，重用原 editor_root 及原 callbacks，不建立第二個 editor／骨架／渲染視口。
- 原 preview_viewport 由 preview_host 持有，保留其父節點、World3D、texture 與 Sprite2D 引用；只借用控制區。施工前完整檢查該區父節點、輸入 viewport、關閉回呼與大小依賴。
- 原 Actor 保持唯一的「正在編輯」判斷。窄修 open_editor／_close_editor 與散落的 editor_window.visible 判斷，使嵌入控制區也遵守原 can_act、受擊／恢復、動畫 callback 與退出恢復規則。
- 借出期間的編輯器輸入必須由實際承載視口消費，不能仍對舊隱藏 Window 呼叫 set_input_as_handled。需要時只改 human_character_3d_editor.gd 的承載／輸入接點。
- 切離角色編輯頁、切 Actor、以 X 隱藏／收起整個測試窗、成功換場或移除測試模組之前，先經原 Actor 結束編輯、恢復地圖 viewport／動畫 callback／更新模式，再歸還控制區。此規則優先於一般表單保留草稿；不能只 hide host 而留下編輯狀態。測試 UI 釋放不能連帶 free 原 editor_root／原模型，失效 Actor 的草稿不得接到新人物。
- 獨立資產編輯場景維持原工作方式。本輪不改骨架、GLB、動畫、材質、圖集、裝備交易或碰撞結果。

此項是獨立的施工與 GPU 驗收步驟，不能用 headless UI PASS 代替。若目前原控制區無法按上述邊界借用，必須先查明具體依賴並修正計畫，不得複製 renderer 或偷偷留第二個可見 Site 測試工具窗。

## 10 正式與測試權限的分界

- 陣型／軍令：正式來源固定為玩家及其真實隊伍／職位。測試才選 trial／test 來源與原合格 NPC 隊長。缺少控制項、無隊伍或無指揮者時回傳無目標／無權限，不尋找能成功的替代者。
- 軍團轉進：正式窗顯示原可查詢隊伍，以 stable team_id 提交原 issue_player_corps_reposition；原任職判定保持。
- 車輛：正式 assign_operator／unassign_operator／transfer 的 requester 必須是實際 controlled_person_id，test_dispatch=false。既有 _vehicle_requester 的 NPC 代選僅供測試；正式列表只展示可選對象，提交時仍重查。
- 配裝：本人用 controlled_person_id；指定搜刮執行者另列。保留整隊 trial=false／true 分界；不得根據父視窗的類型自動授予 npc_mode。
- 名冊：正式保留合法派工／取消與空槽拆分。對已有接收隊的補入／合併，沒有真實同意即不可提交；模擬確認只在測試頁，不能把開發 checkbox 藏起來卻預設勾選。
- 家族：測試資料登錄仍查證原人物／原 Site，並補舊草稿的 terrain／control scope。正式未知名單不推斷全部死亡，保持原 DATA_MISSING／UNREGISTERED 與死亡強制決策。
- Crowd：保留既有命令能力與 CROWD_ACTIVE／UNSUPPORTED 等限制；UI 分類不是新群眾派工／配裝／拘押或跨 Site 接續功能。

## 11 視窗與交易生命週期

一般正式窗每類一個實例，初始化一次，關閉用 hide；首開置於可用畫面並錯開，重開保留 geometry／頁籤／捲動，顯示前讀取最新原資料。原生機制負責拖移、縮放與置前，不寫第二套拖曳框架。

正式窗放在主遊戲嵌入視口。測試窗強制 native，其 gui_embed_subwindows 啟用，讓下拉、確認及必要共用交易子窗嵌在測試窗內。主遊戲與測試窗使用不同座標邊界，禁止互套 global Control rect。

個人配裝、整隊領裝等現有每類單一 _dialog／_sync／_result 保持唯一。共用表單可增加一個明確 host 接點，但不複製業務與 callback：

新建實例依請求 host 承載；已有實例時以全域唯一交易規則優先，不另建或搬動。喚回前先顯示其真正 host，必要時切到承載頁，再聚焦原表單；不得把正式入口的使用者留在不可見測試窗中的表單上。

| 開啟情況 | 行為 |
| --- | --- |
| 同類、同 Site／控制者／目標／權限上下文／host | 顯示並聚焦既有實例 |
| 同類但上下文或 host 不同 | 聚焦既有表單並明示原目標，先關閉再切換；不靜默換人、換權限或搬動執行中的表單 |
| 普通分類窗 X | 隱藏，不取消原作業 |
| 交易表單 X | 釋放 UI 草稿／callbacks，已提交 job 留在原 owner；重開從 job_for 等既有入口恢復 |
| 明確取消作業 | 才呼叫原取消命令，維持已扣／未扣及原子結算規則 |
| 讓出地圖指定終點 | 暫時收起來源窗，保留本次已建立的候選；不能被 visibility_changed 當成取消 |
| 成功載入新 Site／更換控制者 | 關閉或失效舊操作表單與未提交候選，重讀原資料 |
| 載入失敗 | 保留現場資料；不得先毀掉原場景再宣稱失敗 |
| 死亡接續／未保存退出 | 保留原強制決策與 modal 語義，全部收起不影響它們 |

一個地圖目前工具、一份 selected／source_key／feature_key／build_cells／selected_army_target，沿原 Controller／Lab 持有。工作、建設與測試放置的按鈕切換同一工具狀態，不能各窗建立一套互斥模式。資源篩選只有一份來源；其他窗可顯示當前篩選並提供切換入口，不保留不同步的第二組值。

結果仍有全域狀態與表單局部結果。原 owner 回報的成功、失敗、進度只送對應作業上下文；不得另造通用事件匯流排。

## 12 輸入與焦點規則

一般工具窗可同時開啟，遊戲繼續按原時鐘推進；打開／關閉不自動暫停或改倍率。原死亡／退出流程的暫停規則不變。

1. 標題列、邊框、內文、捲軸、下拉、子確認與原生測試窗的事件，不得穿透為地圖點選、採集、建設或軍令。
2. 地圖按下、在任何 UI 或另一原生窗放開，須清理原 drag_start／面向候選／相機拖曳；不能晚一拍發送舊 MOVE。
3. LineEdit、SpinBox 的文字編輯、TextEdit、選單與按鈕聚焦遵守正常鍵盤操作。輸入 WASD／Space／G／Q／E／F 不得同時操作人物；不要沿用「每個按鍵都釋放非文字焦點」而破壞 Tab／箭頭／Enter。
4. 切入 UI 或失焦時釋放原人物移動意圖、跑步／防禦／Crowd engage 及鏡頭按鍵；只清輸入願望，不撤銷已承諾的原步進。
5. Esc 先交目前 modal／下拉處理；無 modal 時先取消未提交的地圖工具操作，再收起目前一般工具窗。測試窗聚焦時的 Esc 只處理其子流程，不觸發背後正式軍令。
6. 主遊戲與自家原生測試窗切換視為同一應用內操作；切去其他應用才套用原失焦暫停。按原引擎 focus 訊號核對，不能只停用所有失焦保護。
7. 要求點地圖的測試命令捕捉原 Site／team_id／requester／序號與版本，交回遊戲焦點；切換目標、場景或測試模組卸載時取消未提交候選。
8. 複查原 TerrainLab._input 的 Crowd 焦點處理及 editor_window.visible 擋輸入邏輯，改成實際視口／編輯狀態，不新建獨立輸入系統。

## 13 布局與鏡頭

正式 UI 以目前 1600×900 顯示設定為主要排版目標，並驗 1280×720、2560×1440 與 Windows 100%／150% 縮放。尺寸按實際可用視口限制，不把原 PANEL_SCALE=1.35 再套一次造成雙重放大。內容字級使用同一主題，長內容靠內部捲動。

一般窗主視口變小時只修正越界位置／尺寸，不重新置中所有已拖移的窗。至少標題與關閉鈕可達；頂欄的「重設位置」能找回全部普通窗。原生測試窗依桌面可用顯示區限制並可重設到遊戲所在螢幕。

在原 SiteController 提供一個小型「基本可用地圖矩形」查詢，供以下三處共同使用：

- TerrainLab.fit_map；
- SiteController.focus_camp；
- TerrainLab 部署後依隊伍 bounds 自動取景。

只計常駐 HUD，不以可移動功能選單或浮窗的 x 座標縮地圖。移動、開關任意浮窗不改鏡頭；使用者按全圖／營地近景或原部署動作時才套用原取景。

## 14 刷新與保存

沿用原 tick／update_ui 時序，把純顯示更新分為常駐 HUD、實際可見正式窗、可見測試頁。大表只在資料變更或頁面開啟時重建，不能每個 UI 更新都重建全部 Node。測試關閉時不生成測試統計字串，也不逐窗啟動獨立 Timer。

選配測試模組可由同一 UI 更新節點呼叫一次可見刷新，方法只讀原資料；正式模擬、AI、供養與工作不能因測試窗關閉而停止。

保存維持 SiteController.save_to → 原保存守衛／原快照 → SiteStore；成功載入仍走 load_from／bind。視窗位置、分頁、測試旗標、表單草稿及授權上下文不寫進 TerrainData.site，不改 SiteStore 格式。

第一版視窗 geometry／分頁只記本次啟動，不為它們新增設定檔；未來確需跨重啟記憶，再用獨立 UI ConfigFile。這條不包含已決音效設定：GAME_AUDIO_IMPLEMENTATION_PLAN.md 的 R2-3=A 使用獨立 user://audio_settings.cfg 保存 SFX 音量／靜音，與 geometry／分頁及玩法保存分開；活動 Site 初始化讀取，cold／hidden builder 不改 bus 或寫檔，僅使用者操作保存。

## 15 檔案修改範圍

| 檔案 | 計畫修改 |
| --- | --- |
| scripts/terrain_lab/site_controller.gd | 正式分類 builders、共用小型建窗 helper、正式狀態／刷新、命令來源分離、表單 host／失效、可用地圖矩形 |
| scripts/terrain_lab/terrain_lab.gd | 解除舊隱藏控件依賴、參數生成入口、正式訊息／輸入、選配測試接點、焦點與三處取景配合 |
| scripts/terrain_lab/site_test_window.gd | 新增唯一可移除測試 UI；七個分頁、測試草稿及原命令轉接 |
| scripts/terrain_lab/terrain_test_character.gd | 僅角色編輯控制的開關／承載狀態與還原；不改正式人物／武器／動畫數值 |
| scripts/ui/human_character_3d_editor.gd | 僅確有必要的 editor_root 掛接／還原／實際輸入視口；原 preview_host／SubViewport／模型所有權不動 |
| scripts/terrain_lab/crowd_clear_handoff.gd | 如仍呼叫已移走的診斷 UI，僅改該接點；原資料移交不動 |
| scripts/tests 中直接依賴 UI 的既有檢查 | 改分類入口／穩定 node name 或明確參數；保留行為斷言 |
| scripts/tests/site_ui_window_contract_test.gd | 新增一個集中契約入口；名稱先在施工前確認未被並行工作使用 |
| PROJECT_ARCHITECTURE.md、TERRAIN_GENERATOR_LAB.md | 實作完成後才補 UI 邊界與操作說明，不提前標示已實作 |

預設不修改 SiteRuntime、SitePersonActions、SiteEquipmentOrders、TerrainArmy、車輛 owner、SiteStore 或原生模組。若讀取最新程式後發現必要的窄接點，先記錄具體原因及呼叫鏈；不能順便重寫玩法。project.godot 原入口與渲染設定保留；視窗嵌入模式優先在相關 viewport 明確設定並驗證，不擴大修改其他專案設定。

## 16 施工階段與完成條件

| 階段 | 施工內容 | 必須先成立的完成條件 |
| --- | --- | --- |
| P0 固定基線 | 重讀 dirty files／架構／並行建設規劃；建立逐控制項正式／測試／共用清單；保存主場景原畫面與既有相關結果 | 可定位原路徑；記錄既有失敗，無他人變更遭覆寫 |
| P1 解除舊開發欄依賴 | 參數生成、輸入可用狀態、正式訊息、選人與安全診斷刷新；移除 TerrainLabUI 硬查找 | 不建立舊開發欄也能啟動／載入／移動／選人／回報，Actor 原呈現仍存在 |
| P2 正式功能獨立 | 抽回本隊／名冊／供養／軍令；正式選隊、陣型、車輛授權與刷新；測試混入處分離 | 不建立混合 combat_window 也不缺正式功能；正式操作從不代選 NPC 授權 |
| P3 正式浮窗與鏡頭 | 功能選單、十類窗、共用開關與邊界、原交易入口、三處鏡頭 | 一類一份、功能可達、無固定右欄空白、普通關窗不取消作業 |
| P4 唯一原生測試窗 | 明示 flag、可選載入、七分頁、測試表單與內嵌子對話框、舊測試遷移 | 唯一可見原生測試頂層窗；所有測試項歸位，開窗不產生遊戲資料 |
| P5 角色編輯控制與多窗生命週期 | 原控制區借用／還原、scope、唯一交易實例、成功換場失效、焦點／輸入 | 無第二份 renderer；不復活忙碌角色；不把舊表單提交給新人物／Site |
| P6 定向回歸與可移除驗收 | 按第 17 節完成無測試、有測試、缺模組、GPU 與輸入矩陣 | 證據完整，失敗未被刪除，靜態／headless／實機結果分開 |
| P7 文件與交接 | 更新操作／架構說明、實際改檔表及證據索引 | 所有原控件皆有去向，已實作／已驗證／剩餘缺口明列 |

不能把「加 if test_ui != null」當作 P1/P2 完成；必須實際走正式啟動、讀檔、控制與操作。不能以空場按鈕全 disabled 的單一畫面代替有原隊伍／庫存的功能驗收。

## 17 驗收矩陣

下列為施工驗收矩陣，逐項完成狀態須引用當次結果；本文件不將程式已實作等同整表通過。資料測試使用既有隔離保存路徑與合法 fixtures，不覆寫使用者 current.json 或開局資料。

| ID | 情境 | 必須成立 |
| --- | --- | --- |
| U01 | 無 --site-test-ui 冷啟動與合法既有存檔 | 測試模組未載入／未安裝，TerrainLabUI／CombatTestWindow／SiteTestWindow 工具節點不存在、F12 未接線；正式時鐘／輸入／渲染／存讀可用 |
| U02 | 明示測試模式開關與重開 | 唯一原生測試頂層窗，分頁／位置保留，關窗不清隊／清貨／停模擬 |
| U03 | 獨立驗證副本或匯出配置不包含測試腳本 | 正式解析／啟動／讀檔／操作正常；不得刪共用工作樹中的檔案做此測試 |
| U04 | 明示啟用但模組缺失 | 清楚回報工具不可用，正式啟動不依賴該模組；不是宣稱開發工具成功 |
| U05 | 十個正式分類逐一打開及多窗並開 | 每類唯一、原功能可達、可置前／移動／縮放／關閉／找回 |
| U06 | 三種尺寸及兩種 Windows 縮放 | 字級可讀、長內容可捲、標題／關閉可達，縮主窗不丟失工具窗 |
| U07 | 地圖按下後於窗內容／標題／邊框／原生窗放開 | 無遲發 MOVE、殘留框選／建設提交／相機拖曳 |
| U08 | 文字／數字／下拉／按鈕焦點與鍵盤導航 | 不觸發 WASD／攻擊／防禦／騎乘；Tab／Enter／方向鍵仍可操作 UI |
| U09 | 遊戲↔測試窗↔外部應用、按住鍵後切窗 | 自家切窗不誤暫停，外部失焦沿原規則，沒有黏鍵；已承諾移動步不回滾 |
| U10 | 無測試窗的本隊選陣／軍令／軍團目標 | 正式目標與隊長呈現正常，無 trial fallback，撤退／權限按原當前值更新 |
| U11 | 車輛正式／測試路徑各測 | 正式 requester 為受控人且 test_dispatch=false；無權人拒絕；測試明示才可模擬隊長 |
| U12 | 正式名冊與測試接收方同意 | 正式無模擬勾選／自動同意；合法空槽拆分可用；測試同意不滲入正式上下文 |
| U13 | 個人／整隊配裝＋庫存＋後勤同開 | 唯一交易實例，成功後更新或明示 STALE；不重複扣物、不半批換裝 |
| U14 | 同類交易跨正式／測試入口、不同人或不同host | 不靜默替換目標／權限，原 callback 不被第二窗搶走 |
| U15 | 關表單後原作業完成，再重開 | 原 jobs／軍令持續，進度由原 owner 恢復；明確取消才取消 |
| U16 | 成功／失敗載入、換控制人、清隊、轉籍、死亡 | 舊 scope 不向新資料提交；失敗載入保全現場，家族草稿不越場 |
| U17 | 死亡接續／退出未保存決策 | 原強制流程不被全部收起或測試窗關閉繞過；未知家族不誤判 Game Over |
| U18 | 全圖／營地／部署後取景與移動浮窗 | 無 590px 舊留白，鏡頭只在原應有時機更新，浮窗不成地圖邊界 |
| U19 | Actor 編輯控制在唯一測試窗打開／還原／換場 | 原模型／viewport／sprite 引用保留；外觀／動作／騎乘正常，無第二個工具窗或模型 |
| U20 | 通常 TerrainArmy 與已有 Crowd 路徑 | 支援能力仍可達；未支援操作保持原拒絕，不把新 UI 當新群眾玩法 |
| U21 | 測試工具未開／已關時的定時更新 | 正式摘要持續、無測試字串與重建 Node 的常駐額外工作、無每窗新模擬時鐘 |
| U22 | 保存內容比較與退出 | UI geometry／分頁／測試草稿不進玩法快照，原交戰／作業保存限制未放寬 |

「測試 UI 不建立」特指可移除的工具與舊 TerrainLabUI，不要求刪除 Actor 現有正式呈現所需的隱藏 editor 載體。該例外不可用來藏回 seed、movement_toggle 等正式依賴。

## 18 測試沿用與證據要求

優先更新以下已存在的測試，而不是新增一套框架：

- site_battle_window_test.gd、site_resource_visual_test.gd：替換舊固定右欄與父子路徑斷言；保留時間、人物／性別、部署拒絕及存讀斷言。
- combat_movement_facing_gui_cancel_test.gd：擴充新窗與原生窗跨界釋放；保留合法地圖命令仍能提交。
- site_movement_input_clock_test.gd、site_player_army_test.gd、site_battle_movement_exit_test.gd：保留正式鍵盤時鐘、本隊授權、交戰退出與取消流程；不得以直接呼叫輸入函式冒充跨視窗實際按鍵驗證。
- site_equipment_player_ui_test.gd、site_equipment_depot_ui_test.gd、site_equipment_trial_ui_test.gd、site_team_equipment_orders_test.gd：保留實物、scope、圖集與原子交易；正式／測試入口分別驗。
- site_roster_ui_test.gd、site_logistics_ui_test.gd、site_ransom_ui_scope_test.gd、site_family_continuity_test.gd：保留雙方權限／版本／資料缺漏／退出流程。
- site_vehicle_transport_test.gd、site_vehicle_main_visual_test.gd、site_support_main_test.gd：保留 owner 的非測試權限拒絕，再驗正式 UI 參數。
- site_tactical_ai_ui_test.gd、site_trial_team_choice_test.gd、site_trial_roles_test.gd：明確啟用測試 UI 後測新的單窗分頁入口。
- site_mount_fatigue_visual_test.gd 與其他依右欄取景的測試：只改布局假設；不為 UI 重排重跑完整 5,000 人／萬人效能工程。
- 既有直接讀 lab.seed_input／movement_toggle／status 或 combat_window 子孫的測試，改用新的正式參數／結果入口或明示測試 module；不設假隱藏 controls 相容。
- terrain_lab_test.gd 的 Next／Previous／Random 等測試明確啟用測試 UI。另追查 SiteUI.hide()／panel.hide() 的截圖與效能腳本，改用新介面的實際可見性控制；不因此啟動其完整長測。

新增 site_ui_window_contract_test.gd 集中覆蓋 U01、U02/U05 的結構與生命週期部分及必要上下文契約。headless 只證明實例數、要求的模式、重開與資料生命週期；實際 is_embedded=false、有效原生視窗 ID、鼠鍵、焦點、DPI 及拖移須由 GPU／桌面操作留下證據。事件注入與 root viewport 截圖不能冒充桌面驗收。

執行順序：限定檔案靜態檢查 → canonical editor/import → 與改動對應的 headless 契約／回歸 → 正式主場景 GPU／輸入 → 原生測試窗與可移除煙霧驗證。單次失敗保存結果、定位原因、做範圍內修正再重跑；不盲目重複、不改 verifier 或放寬斷言。

所有 Godot 執行使用 C:/Users/Nekki/.codex/skills/godot-runtime-verify/scripts/verify_godot.ps1 原檔、明確 -TimeoutSeconds 及隔離結果路徑，保留 canonical 最新 100 份已完成紀錄的 retention。既有模式是 editor、headless、visual，測試入口經 -GodotArguments 傳入，產物由 -ExpectedOutput 核對。施工時先確認實際 GodotExecutable 路徑與 helper 介面；不能把「有計畫命令」當成執行檔已驗證。原規劃階段未執行 Godot，施工後的驗證以各次保存結果為準。

無旗標與有旗標分別冷啟動一次，不能只在同程序改欄位代替。啟用測試模式的參數形狀為 -GodotArguments @('--script', 'res://scripts/tests/site_ui_window_contract_test.gd', '--', '--site-test-ui')，使用者旗標必須放在 '--' 後。

U03 的可移除副本必須由當下工作樹與明確 runtime include manifest 建立，包含尚未提交的本次實作與所需資產；不能只 clone HEAD。建立時排除測試模組及其專用 .uid／scene，不在來源樹暫時刪檔或改名，也不以 symlink 把 Godot import 回寫來源。靜態依賴檢查聚焦正式可執行 .gd／.tscn／.tres／autoload／project.godot，排除本計畫與測試斷言中的引用字串。證據保存 manifest、隔離保存路徑、副本位置與結果；不得以 git reset／clean 清除其他 session 的變更。

實作證據建議集中 output/site_ui_formal_test_window_20261001/，保存每階段結果索引、失敗／修復說明與畫面。原生測試窗須有實際桌面可見證據與 is_embedded=false 檢查；正式窗須有主遊戲內嵌證據。若當時工具不能擷取原生窗或執行實際鼠鍵，該項明列未驗證，不以主 viewport 截圖替代。

visual 通過須同時確認程序正常退出、無錯誤、本輪指定畫面確實新產生，且已實際檢視。現有 site_resource_visual_test、site_support_main_test、site_vehicle_main_visual_test 的強制嵌入／root texture 截圖只保留適用於正式主視口的部分；測試工具證據改拍實際 native host，不能沿用舊圖片或原截圖檔名就當作已遷移。

背景程序與子代理用實際可用 status／wait 主動監控；沒有 schedule 時沿使用者規則使用原生等待，不為此建立 recurring automation。

## 19 完工交接清單

- 逐項控制遷移清單已核完：正式、測試、共用及移除原因皆可追查。
- 測試開關 OFF 的主場景與既有存檔可實際操作，不只是沒有报錯。
- 測試入口均集中唯一原生窗，正式介面沒有隱含模擬 NPC 或測試物資來源。
- 測試模組可不攜帶，原人物呈現、命令、供養、車輛與存讀不受影響。
- 已提交作業、物品守恆、版本、權限、家庭接續及退出限制均保留。
- UI 證據分為靜態、headless、GPU、真實輸入、原生視窗與可移除測試，不以其中一項代表全部。
- 文檔列出實際改檔、完成項與未解缺口；未授權的 gameplay 補完不混入本次工作。

## 20 原始碼與平台參考

核心檔案：scripts/terrain_lab/terrain_lab.gd、site_controller.gd、site_vehicle_transport.gd、site_family_continuity.gd、terrain_test_character.gd，以及 scripts/ui/human_character_3d_editor.gd。責任依 PROJECT_ARCHITECTURE.md 的「現行責任」。

平台依據：Godot [Window 文件](https://docs.godotengine.org/en/stable/classes/class_window.html) 說明同一 Window 可嵌入或使用原生模式；[force_native](https://docs.godotengine.org/en/stable/classes/class_window.html#class-window-property-force-native) 可只對測試窗強制 native；[Viewport.gui_embed_subwindows](https://docs.godotengine.org/en/stable/classes/class_viewport.html#class-viewport-property-gui-embed-subwindows) 決定子視窗嵌入。這些文件支持平台選型，不代表本專案已完成原生焦點／縮放驗收。
