# 讓另一個專案的 Claude 派工給 Codex（2026-11-26）

## 為什麼那邊「過不去」
我沒看到那邊的錯誤訊息，所以不能斷定。依這台電腦上踩過的坑，照機率排：

1. **那個 Claude 不在你的電腦上跑。** 雲端的工作階段在別的機器，看不到 `codex.exe`，怎麼設都過不去。要從電腦上的 Claude 桌面版（或在這台電腦開著的遠端控制）開啟那個專案資料夾。
2. **它找錯路徑。** `codex` 不在 PATH，執行檔在 `%LOCALAPPDATA%\OpenAI\Codex\bin\<一串碼>\codex.exe`，那串碼每次 Codex 更新都會變（現在是 `f71a721e0e6193a9`，版本 0.167.0-alpha.3.2）。寫死路徑就會壞。
3. **指令被權限擋下。** 送件要寫 `%USERPROFILE%\.codex` 裡的資料庫；在沙盒裡跑會失敗（我們第一次自測就是這樣）。它要執行時會跳出許可，按允許即可；想免按，由你自己在那個專案加允許規則，我不代改。
4. **用了舊方法。** `codex mcp-server` 這個版本已移除，要用 `codex queue`。

## 實際怎麼派
沒有特別的連線，就是「一個資料夾＋一行指令」：

1. Claude 把工作單寫成檔案：`output\project_command_center\inbox\<單號>.md`。
2. Claude 執行 `codex.exe queue --thread <Codex 聊天的 ID> --message "…"`。看到 `Queued message` 才算送入佇列；**只寫檔案不會叫醒 Codex**。
3. Codex 做完，把結果寫到 `output\project_command_center\receipts\<單號>.json`（先寫 `RUNNING`，再寫 `DONE`／`NEEDS_INPUT`／`FAILED`）。
4. Claude 在背景等這個檔變成最終狀態，再檢查、驗收。**以回報檔為準**，送入佇列不等於做完。

要先開著的東西：Codex 桌面版開著且已登入；那個專案在 Codex 裡有一個專門接單的聊天。

## 你要做的（一次）
1. 在 Codex 用那個專案的資料夾開一個新聊天，跟它說：「你負責接 Claude 的工作單，檔案在 `output\project_command_center\inbox`，結果寫到 `receipts`，一次只做一張。」
2. 找聊天 ID：到 `%USERPROFILE%\.codex\sessions\<年>\<月>\<日>`，最新檔名 `rollout-日期-` 後面那一長串就是。也可以請 Codex 說出它的 session id。
3. 把下面整段貼進那個專案的說明（專案設定的指示，或資料夾裡的 `CLAUDE.md`），換掉兩個〈〉。

## 可直接貼上的說明

```
## 派工給 Codex
- 你必須在 Nekki 的 Windows 電腦上執行（不是雲端）。先檢查：
  ls $env:LOCALAPPDATA\OpenAI\Codex\bin\*\codex.exe
  找不到就停下來告訴 Nekki「我不在這台電腦上」，不要試別的方法。
- Codex 接單聊天 ID：〈Codex 聊天 ID〉
- 專案根目錄：〈例如 D:\wuxia〉
- 派工步驟：
  1. 工作單寫到 <根目錄>\output\project_command_center\inbox\<單號>.md，單號只用英文、數字、連字號。
     內容要有：目標、可以改哪些檔案、不准做什麼、交付位置、驗收方式、回報檔路徑。
  2. 用 PowerShell 送件（每次都重新找 codex.exe，路徑會變；逾時 30 秒）：
     $id   = 'CC-20261126-001'
     $root = '〈專案根目錄〉'
     $file = "$root\output\project_command_center\inbox\$id.md"
     $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
     $exe  = (Get-ChildItem "$env:LOCALAPPDATA\OpenAI\Codex\bin\*\codex.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
     & $exe queue --thread '〈Codex 聊天 ID〉' --message "[CLAUDE_TASK] id=$id file=$file sha256=$hash 請照工作單執行，並把結果寫到 $root\output\project_command_center\receipts\$id.json"
     出現 Queued message 且退出碼 0 才算送入佇列；失敗先看錯誤，不要直接重送。
  3. 立刻在背景等 receipts\<單號>.json 變成 DONE／NEEDS_INPUT／FAILED，不要結束後沒人看。
  4. 讀回報檔、自己檢查成品，再告訴 Nekki。
- 一次只派一張；上一張沒有最終回報前不派下一張。
- 回報是 QUOTA_STOP（額度用完）就停派，告訴 Nekki，等恢復。恢復後的第一張，要在 --message 裡寫明「Nekki 已同意恢復」。
- 不要用 codex mcp-server（這版已移除）。
```

## 還不行時
請那邊的 Claude 把這三行的輸出原樣貼給你，再轉給我看：

```powershell
hostname
```

```powershell
Get-ChildItem "$env:LOCALAPPDATA\OpenAI\Codex\bin\*\codex.exe"
```

```powershell
& (Get-ChildItem "$env:LOCALAPPDATA\OpenAI\Codex\bin\*\codex.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName queue --help
```
