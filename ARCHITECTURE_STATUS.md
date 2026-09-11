# V0.3R 架構狀態

唯一遊玩入口是 `scenes/terrain_lab/TerrainLab.tscn`。
正式責任與資源邊界以 `PROJECT_ARCHITECTURE.md` 為準。

V0.3R 移除已停用的 2D 紙娃娃及舊 World／Region／Site、Travel、Persistence、
Battle／Formation 相依流程。舊三層世界與舊存檔測試不再是現行 Site 的驗收基線。
新 Site 的地形、角色、戰鬥、百人隊伍與 3D 換裝功能保留。

清理、驗證結果及剩餘限制統一記錄於 `V0.3R_RELEASE.md`。
本機舊工作備份不納入 Git，也不作為 Godot 資源載入。
