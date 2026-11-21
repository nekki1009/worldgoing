# 平民 C1c 屋內「在家」實作計畫

日期：2026-11-20　負責：指揮中心（Claude）。依據：reports/civilian-site-behavior-plan.md §4.8 與 Q9（Nekki 選 A）：屋內居民不畫，用原生 `absent` 新增一種「在家」，不參與碰撞與目標選擇。

## 已查明的現況
- 原生 `site_person_absent(i, kind)` 只收 kind 1–4。對應：1 離隊（present=false）、2 離開 Site（site_exited）、3（另一用途）、4 駐營（site_garrison）。存檔驗證 `state.cpp` 要求 absent 時 kind 介於 1–4。
- 不在場的人不會被當成活人（`alive()`），所以不被瞄準、不參與碰撞、不畫。原生活動覆寫也會略過他們。
- 宿主端 `CrowdPersonOwner.presence_state` 只看 kind，kind 1 算「不是隊員」，kind 0 才算「在場」。
- **交接限制**：`crowd_site.gd` 約 4622 行，名冊裡有離隊、離圖或待俘的人時，拒絕群眾交接（例如冷 Site 轉換、出發抽離）。如果「在家」直接沿用 kind 1／2，所有出發和冷存流程都會被擋。

## 設計
1. **原生**：新增 kind 5「在家」。`site_person_absent` 和存檔驗證接受 5；行為與其他 absent 相同（不算活人、清掉以他為目標的命令）。`site_person_absent_state` 回傳 [1, 5]。需要重建並發佈 DLL（流程見 crowd-test-invocation 記憶）。
2. **宿主對應**：`presence_state` 對 kind 5 回報 member=true、present=true、at_home=true。名冊、餉、人數、供養都照常把他算在隊上。只有畫面、碰撞和目標選擇把他排除。
3. **進屋**：居民在家時段（睡、用餐、晚間），回到家門口（`Housing._attends`）後設 kind 5。群眾 Site 才做，網格模式不做。
4. **出屋**：作息輪到工作或出門、警報解除超過 30 分鐘、住宅毀損或被占、Site 要轉冷或要出發抽離、玩家指派這個人時，先在家門格 `site_person_return`；門格被占就退到最近的可走格。
5. **交接**：kind 5 的人在任何交接、存檔、轉冷之前一律先出屋。存檔本身仍保存 kind 5，讀回後維持在家，不必再出屋。這樣 4622 行的交接限制不必放寬。
6. **戰鬥**：遇敵時屋內的人留在屋內，不會被選為目標（規格 §4.5）。住宅被燒或被攻破時，屋內的人出屋改到聚落中心，這一項目前是「未做：沒有走到中心的動作」，留待後續。

## 驗收
- 原生：新增 kind 5 的接受與拒絕、存讀一致、目標清除（原生測試）。
- 宿主：一位居民走完一天，晚上進屋（畫面上消失、敵人選不到），早上出屋上工。存讀後狀態不變。轉冷、出發前都會先出屋。
- 效能：量 100 位居民時每步的耗時，夜間應明顯下降。
- 回歸：群眾家族、平民相關測試、冒煙測試。

## 風險
- 交接、存檔和名冊有很多處讀 absent kind。上線前要把所有讀 `site_person_absent_state` 和 `absent_kind_of` 的地方逐一列出，確認每處都處理了 5。
