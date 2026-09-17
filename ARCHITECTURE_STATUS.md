# V0.45R 架構狀態

唯一遊玩入口是 `scenes/terrain_lab/TerrainLab.tscn`。
正式責任與資源邊界以 `PROJECT_ARCHITECTURE.md` 為準。

V0.3R 移除已停用的 2D 紙娃娃及舊 World／Region／Site、Travel、Persistence、
Battle／Formation 相依流程。舊三層世界與舊存檔測試不再是現行 Site 的驗收基線。
新 Site 的地形、角色、戰鬥、百人隊伍與 3D 換裝功能保留。

2026-09-11：現行 TerrainLab 加入九類天然資源、四類土地條件、首名工人的
工作區／運貨流程、角色手動採集、最小建設及農牧加工批次、共享供水與單圖存讀檔。
狀態仍由 TerrainData 擁有；舊 World／Region／Persistence 流程沒有恢復。
和平／交戰倍率作用於同一 Site 時鐘，動作速度維持現狀。
新功能與驗證邊界見 `SITE_RESOURCE_IMPLEMENTATION.md`；完整軍隊效能矩陣不在此次結論內。

V0.35R 同時接入住宅、水井、農田與營地箱圖集，並加強崖頂、崖腳及坡口辨識。
2026-09-18 V0.45R 收錄原擁有者的批次呈現與同步運算、隊伍共享疲勞、後排跟進／離開守衛，
以及男女布甲、鞋履、44 種武器工具材質選項及對應標準男兵圖集。
本版內容、驗證結果及限制見 `V0.45R_RELEASE.md`；既有各版紀錄保留。
本機舊工作備份不納入 Git，也不作為 Godot 資源載入。
