# Region 旅行 R1 結果報告（2026-10-07）

## 完成內容
- **整隊出發**（功能選單「整隊出發」，`scripts/region_lab/region_travel_site.gd`）：脫戰（`combat_left`=0、24 格內無可行動敵人）、無倒地隊員才可出發。受控人物是隊長 → 帶全隊（人、車／馬車、隨身與車上物品、隊伍／個人餐份帳、火攻命令列）；不是隊長 → 先走既有 `leave_player()` 退隊再單獨出發。家人、住民留下；出發者自動離住。
- **旅隊資料**（`region_travel.gd`）：旅途中人物記錄只存在一份有校驗的 party 文件（Godot Variant 精確編碼），存檔槽 commit 的 `journey`（kind=`region_travel`）記位置／路線；出發地當代存檔已移除這些記錄，不重複不遺失。格式含 `controller` 欄位，可供 R3 NPC 旅隊沿用。
- **路線**（`region_route.gd`）：每個 Site 的四邊連通表由**與實際進入 Site 相同的建置**（`make_terrain_data`，含台階、水域、稀疏坡口、生成樹石阻擋）推得；邊界只在兩側皆可站且同高或經共同坡口處可通。採**惰性計算＋快取**（記憶體＋`user://region_lab/route_tables`），未做全島預算表（約 0.25 秒／Site，全島估 6–8 小時，留待離線工具）。加權 A*（≤1.4 倍最短）在背景執行緒。
- **時鐘**：旅行中無活動 Site，`advance_region_travel` 是唯一時鐘發布者，以火攻 journal 的和平步（8 遊戲秒／步，scale 4）推進，冷 Site 之後可沿原步補算。地圖速率 1 實秒＝10 遊戲分 × 0.5/1/2/4。
- **地圖 UI**（`region_travel_panel.gd`，RegionLab 新 `travel` 模式）：旅隊圖示、路線與預覽、遊戲時間、出發／暫停／速度、每 5 實秒及暫停時存檔、抵達後自動進入目的 Site；「保存並回主選單」。主選單續玩若在途會自動轉到地圖。一般「台灣地圖」檢視仍暫停時間（未改）。
- **抵達**：只展開目的 Site（未造訪者走既有初始化，已造訪者走原精確冷補算）；在來向入口坡口旁安置隊伍，車輛停放於附近並解除駕駛綁定；一次 commit 同時寫入目的地並設為活動 Site。
- 對既有檔案的最小改動：`site_controller.gd`（加按鈕＋世界開啟掛勾 5 行）、`region_save_slot.gd`（journey 正規化、船旅狀態忽略陸路旅隊、旅行方法附加於檔尾）、`region_lab.gd`（travel 模式掛勾）。

## 與指示的差異／限制
1. **旅途中隊伍需求凍結**：不吃飯、不累；抵達時餐份時鐘平移（剩餘餐期保留，上限下一餐界）。旅途補給消耗留給 R2。
2. 非隊長但受控人物是**隊伍列（row）**時（例如家族接續後）暫不支援單獨出發；隊內有陣亡者、已退隊者、船／攻城器、駐營、拘押、與留下者共用的國別職務／軍團時拒絕出發（訊息說明原因）。
3. 已造訪 Site 內玩家自建牆／整地未納入路線表；以實際目的地決定落點，入口被封則抵達失敗、隊伍留在地圖。
4. 仍有火場燃燒時禁止出發。海路未納入。

## 驗證結果（canonical helper）
- `scripts/tests/region_travel_test.gd`（headless）**PASS**：隊長全隊（4 人＋板車＋馬車＋物品）、非隊長單獨、人／物／車守恆、戰鬥／倒地／附近敵人拒絕且不寫 commit、合成地圖海峽繞行、玉山兩條路線每個跨界以原 `boundary_surfaces_can_step` 與 `path_between` 重新證明、旅途中保存重開位置／時間一致、未保存的時間不會復活、世界時鐘單調且＝出發＋旅行時間、抵達不可重放。
- 數據：玉山 900 m 路線首次約 2 秒（5–6 個 Site 建置），快取後 0.5 ms；**回到已造訪 Site：落後 3432 遊戲秒（約 57 分）補算約 6.2 秒**，長途（10 小時）預估約 1 分鐘以上 → 需 R2 混合補算。
- GPU 截圖 PASS：`.visual_captures/region_travel/r1_20261007c/travel_map.png`（玉山附近、旅隊在途、路線與面板）。
- **尚未重跑**（額度用盡）：region_lab_contract_test、region_lab_preview_contract_test、site_ship_journey_test、main_menu_flow_test。

## 待辦
重跑上述四項回歸；遊戲內手動走一次完整流程；離線全島連通表工具；R2 旅途補給與混合補算。
