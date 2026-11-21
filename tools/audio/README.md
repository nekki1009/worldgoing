# 製作已授權 Site 音效

`build_site_audio.py` 只讀已保存的 CC0 預覽來源，使用現有 soundfile decoder 與配置的 bundled Python／numpy，離線製作 `assets/audio` 與素材 receipt。沒有網路、Godot、玩法修改或新依賴安裝。

本次命令：

```powershell
& 'C:\Users\Nekki\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' 'D:\worldgoing\tools\audio\build_site_audio.py'
```

腳本有 90 秒明確 watchdog，非零退出時保留已產出的檔案。既有 `assets/audio` 或完成 receipt 會拒絕覆寫；重新製作需另開明確檢查的輸出版本，不能刪除正式素材後盲重跑。

每次生成都讀回 WAV，assert 原檔 hash、CC0、格式、有限值、峰值及數量。這是製作技術檢查，沒有主觀聽覺或 Godot runtime PASS。素材來源與限制見 `assets/audio/README.md`。
