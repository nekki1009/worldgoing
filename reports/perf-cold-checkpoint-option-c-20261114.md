# 效能待辦 C：冷補算結尾的完整冷存檔點

狀態：只寫報告，不改程式（Nekki 11/13 09:20Z 照建議：C 列效能待辦）。

## 量到的成本（P4 群眾冷研究測試，2026-11-13～14）

- 冷補算本身很便宜：一段 30～300 秒的 `replay_site_to` 只要 2～130 ms。
- 每次補算收尾（`_region_finish_cold_replay`）都會建立一個完整並驗證過的冷存檔點，成本固定，跟補算長度無關：
  - `capture_region_owner_state`（擁有者圖）：約 245 ms。
  - `SiteStore.capture_region_snapshot`（序列化加驗證）：約 545 ms。
  - 群眾版還要先做一次 `crowd_site.capture_save(true)` 原生擷取。
- 整體效果：P4 每呼叫一次 `_p4_advance` 約 2.5 秒（含收尾，以及驗證重放不重複的那一次 repeat）。整支測試約 650 次呼叫，總共 1936～2076 秒，其中九成以上花在收尾的存檔點。
- 遊戲內的影響：區域畫面上，每個離屏 Site 每次冷補算推進都要付一次約 0.8 秒的固定成本。Site 越多、補算越細，累積得越快。

## 選項 C 的內容

冷補算推進到中途時，不在每次結尾都做完整的存檔驗證，只在以下時機做：

1. 真正要存檔或交接時：玩家存檔、Region 轉場、Site 重新綁定。
2. 補算批次的最後一段。

中間的各段只更新記憶體中的擁有者狀態和結算水印，不做序列化。

## 風險

- 現在每段都驗證，壞狀態會在出錯的那一段立刻被抓到。改成 C 之後，錯誤要到下一個存檔點才會被發現，定位會變困難。
- `region_snapshot` 的 context／receipt 比對、時鐘容差檢查（11/14 修的 STALE_REGION_CONTEXT），目前都依賴每段的存檔點；改動時要保留等價的檢查。
- 要動存檔核心（`site_store.gd`、`terrain_lab.gd` 的 `_region_finish_cold_replay`），回歸範圍是全清單。

## 建議做法（排程時）

1. 先加一個開關，只在冷補算的中間段跳過序列化，收尾段照舊驗證。
2. 用 P4（約 650 次推進）和 region_siege 系列做前後計時，預期 P4 可以從約 2000 秒降到 300 秒以內。
3. 全清單回歸，外加 ship_journey／journey_edge 時鐘組（記憶：clock-changes-need-ship-journey-tests）。

## 相關提交

ca824ff、9ec5fb7（時鐘容差）、cac1668（P4 測試，時限 2700/2760）。
