# crowd10k：萬人戰場核心原型（v2，P1 完成）

2026-09-29。這是獨立的 C++17 程式，不依賴 Godot，也還沒接進正式入口。

- **v1**（同日稍早）只證明了一件事：「連續位置＋推擠」的移動方式，在萬人規模下夠快。
- **v2** 移植了正式戰鬥的**主要規則**：
  - 相鄰交鋒制、遠程
  - 暈眩／擊暈／救助、倒地失血
  - 士氣與潰退、指揮接任
  - 戰術 AI、追擊、包圍
  - 俘虜、共享疲勞
- **P1**（同日）完成施工計畫 P1 的各項，全部在原型內，不碰 Godot：
  - 對照正式流程的提交順序，修正 13 處差異
  - 統一時鐘
  - 人物狀態匯入／匯出
  - 事件佇列
  - 完整存讀檔
  - 每隊唯一決策者

**狀態說明**：主要規則已經移植，提交順序也逐段對照過。但仍有兩部分沒辦法對照：

- `site_sustain.gd` 和 SitePersonActions 不在這次對照的檔案裡，跟它們有關的細節標為「未驗證」。
- 連續移動下，「移動中不能發起交鋒」這條規則無法照原樣移植。

規則逐條對照見 [RULES_COVERAGE.md](RULES_COVERAGE.md)；施工計畫見專案根目錄的 `SITE_CROWD_10K_PLAN_SOL.md`。

## 檔案

| 檔案 | 內容 |
|---|---|
| `src/rules.hpp` | 數值公式：逐行移植 `SiteCombatRules`／`PersonFatigue`／`WeaponMaterials`，包括原本的擲骰 hash |
| `src/crowd_core.hpp/.cpp` | 地形邊、流場、隊形、士兵移動、空間雜湊、陣營關係、Site 時鐘、每步流程、渲染資料打包、完整狀態雜湊 |
| `src/combat.cpp` | 交鋒輪（準備→擊退→傷害三段）、暈眩／KO 計時、遠程射擊／飛行／攔截、救助、俘虜、押送、逃脫、失血、事件 |
| `src/command.cpp` | 在場判定、接任、士氣觀測（每步比對存活檢查點）、整補、潰退／集結、共享疲勞 |
| `src/state.cpp` | 人物／隊伍狀態匯入匯出（SiteStore 邊界）、完整存讀檔 |
| `src/ai.cpp` | 戰術 AI（`site_army_ai.gd` 的移植）、接敵後包圍 |
| `src/crowd_c_api.h/.cpp` | 給 GDExtension 包裝用的純 C ABI |
| `src/bench.cpp` | AI 自主作戰量測：兩軍 battle／melee，或三陣營 three；可以接一段戰後時間 |
| `tests/scenario_tests.cpp` | 規則情境測試：23 個測試函式、152 項斷言 |
| `tests/rules_vectors.cpp`＋`tools/gd_reference.py` | 公式交叉比對：把 GDScript 公式手譯成 Python，跟 C++ 輸出比較 |

## P1：這一輪做了什麼

### 1. 對照正式提交順序（`terrain_lab._advance_combat`）

每步的順序改成跟正式一致：

1. 整補與疲勞（遊戲時間）
2. 俘虜與押送（遊戲時間）
3. 戰術 AI
4. 隊形
5. 準備：冷卻、KO／醒來、救助
6. 移動
7. 箭抵達
8. 交鋒輪，結束時射擊
9. 結算指揮

修正的差異（逐項都有斷言）：

| # | 正式行為 | 原型原本 |
|---|---|---|
| 1 | 箭先抵達，再交鋒；新射出的箭下一步才開始飛 | 交鋒後才處理箭，新箭當步就少飛一步 |
| 2 | 最後一名合格指揮者失能時，隊伍改守位（撤退除外），清掉目標與追擊 | 保留原命令繼續走或追 |
| 3 | 疲勞恢復、整補、集結、俘虜 4 秒、逃脫 30 秒，都用**遊戲時間** | 用動作時間 |
| 4 | 整補 +5／遊戲小時：只要安全、停止就適用，不限潰退中 | 只在潰退時回復 |
| 5 | 士氣在下一步開頭，跟上次檢查點比對：同一段時間內先暈後死，只算一次死亡；分母含昏迷者與俘虜；指揮中斷的 −10 在同一次事件裡扣 | 逐次受擊扣分；先暈後死扣兩次；分母不含俘虜 |
| 6 | 疲勞恢復要：守位、Site 已脫戰、全員閒置、8 步內沒有敵人、沒有箭飛過 | 條件較寬 |
| 7 | 被擊退時同時倒地，身體仍滑一格 | 倒地後停在原地 |
| 8 | 擊退不清除原有硬直，取兩者較大值 | 擊退時歸零 |
| 9 | 多個對手時，擊退方向與朝向由唯一「反應」決定：擊退優先，再來依序是敗 > 平 > 勝、HP 損失較大、差距較大、對手編號較小 | 取第一個擊退、最後一個對手 |
| 10 | 醒來、起身結束時標記指揮需要重新結算 | 只有受擊時標記 |
| 11 | 計時與救助在移動前處理 | 在移動後 |
| 12 | 救助中的人，暈眩不會消退 | 會消退 |
| 13 | 火控只算還活著的友軍（包括昏迷的） | 當輪剛死的友軍也擋線 |

**沒有照原樣移植的兩點**：

- 正式規則要求「移動中不能發起交鋒或射擊」。連續移動沒有「移動中」這個離散狀態，所以沒有照搬。
- 死亡時俘虜狀態解除的時點，正式要等倒地動畫結束。原始碼不在對照範圍，未驗證。

### 2. Site 時鐘（唯一時間來源）

- `step(dt)`：照 `SiteRuntime.game_seconds` 自己計時。
  - 戰鬥時鐘 `combat_left` 大於 0 時，1 秒 = 1 遊戲秒；歸零後 1 秒 = 60 遊戲秒。
  - 交鋒與有效受擊會把戰鬥時鐘拉到至少 10 秒，射擊拉到至少 12 秒。
  - Site 倍速只乘在遊戲時間上。
- `step_clock(dt, game_seconds, combat_left)`：由 Godot 端傳入時間，原型只回報 `combat_mark`，由 Godot 交給 `SiteRuntime.mark_combat`。

### 3. 人物狀態匯入／匯出

- 每人：HP、暈眩、寬限、KO 剩餘、起身、硬直、是否被俘與看守（依 person_id）、是否已包紮、彈藥、指揮能力。
- 每隊：士氣、集結計時、共享疲勞與休息、訓練、潰退、需要重新下令、正式／代理隊長、幹部順位（依 person_id）。
- 匯入不算士氣事件，也不會產生 KO 或死亡事件。

### 4. 事件佇列

事件種類：死亡、KO、醒來、被救、被俘、逃脫、接任、指揮中斷、潰退、集結、射擊。

每筆事件帶 person_id、相關人物（救助者、看守、前任隊長）、隊伍與動作時間。

### 5. 完整存讀檔

- 存入所有會影響下一步的狀態，包括飛行中的箭，以及正在進行的救助與俘虜。
- 流場只存「目標與是否已建」，讀檔時重建（建置是確定的）。
- 測試方法：戰鬥中在「有箭在空中、有交鋒、救助與俘虜都在進行」的時點存檔，分別直接續跑 20 秒、讀檔後用另一個執行緒數續跑 20 秒，兩者的完整雜湊相同。截斷的存檔會被拒絕。
- 萬人存檔約 3 MB。只保證同一個 build 內有效。

### 6. 每隊唯一決策者

- `ai_enabled = true` 的隊伍由原生 AI 決定，Godot 端的命令會被拒絕，C API 回傳 0。
- `ai_enabled = false`（玩家或 GDScript AI）的隊伍，原生 AI 不會下令。

## 驗證

| 項目 | 結果 | 能證明的範圍 |
|---|---|---|
| 公式交叉比對（16,500 組） | 差異 0 | C++ 公式等於**手譯的 Python 公式**，不等於跟正式 Godot 流程等價 |
| 規則情境測試 | 23 個函式、152 項斷言，全部通過；AddressSanitizer＋UBSan 下無錯誤 | 各條規則在小場景的行為 |
| 決定性 | 1／2／4 執行緒的完整狀態雜湊相同；存讀後續行相同 | 同一個 build |
| C 介面冒煙測試 | 決策者檢查、狀態往返、經 C 介面存讀後續行，雜湊相同 | |
| 不變量 | 非法格 0、非法跨邊 0、交鋒冷卻違規 0 | 量測遇到違規會以錯誤碼 2 結束 |

## 量測（雲端 2 vCPU，比使用者電腦慢約 1.5 倍）

**P1 的成本**：同一台機器交替跑兩次，10k battle 單執行緒從 5.65 ms 變成 6.03 ms，多了約 0.4 ms（+7%）。

- 移動後要多建一次空間雜湊，約 0.11 ms。
- 救助改在移動前做，加上整補檢查威脅、疲勞恢復條件，合計約 0.15 ms。
- 其他差異是戰況不同造成的：新流程下 KO 5,108 人，原本 4,767 人。

**戰後條件改變**：交戰 120 秒後，雙方各自往遠離敵軍的方向退 15 格並守位，再跑 7 分鐘。

- 原本的量測直接把時鐘設成 60 倍。現在由 Site 時鐘自己判斷。
- 最後一次交鋒或受擊後 10 秒才脫戰。之後醒來的人又會跟附近敵人打起來，戰鬥時鐘會再被拉起來，所以 7 分鐘內仍有 1–2 分鐘是戰鬥時間，合計約 5.1–5.8 遊戲小時。

| 規則 | 交戰結束時倒地 | 救起（戰中＋戰後） | 俘虜（戰中＋戰後） | 失血死亡 | 醒來 | 逃脫 | 潰退 |
|---|---|---|---|---|---|---|---|
| 原規則（只救相鄰、不自動俘虜） | 5,083 | 129＋188 | 0 | 4,121 | 1,076 | 0 | 20 |
| 新預設（救 8 格、自動俘虜 8 格） | 5,108 | 194＋460 | 1,308＋1,925 | 1,143 | 4,005 | 23 | 0 |

- 失血死亡約 1,100 人，比上一版的約 470 人多。原因是雙方退開 15 格後，只剩 8 格內的傷兵能被救或被俘，留在中間的傷兵沒人處理。
- 三陣營（0／2／5 各 3,300 人，320² 平地）：三方互相交戰。交戰結束時倒地 6,392 人，俘虜 4,308 人，失血死亡 1,035 人，潰退 3 隊，不變量違規 0。
- **存讀檔**（交戰 120 秒後）：存檔 2.9–3.3 MB，存 3–8 ms，讀 0.3–0.7 秒（大部分時間在重建流場）。讀回的副本跟原本各自再跑 1 秒，完整雜湊相同。量測程式把這一項列為關卡，不同就以錯誤碼結束。

**正式數字要在使用者電腦上跑**：雙擊 `run_prebuilt.bat`。

## 還沒有包含的東西

- 玩家操控
- 隊長 live 3D
- 正式圖集渲染與遮擋（P2）
- 口糧、交付、搜刮、贖回
- 攻城

## 重現

```
cmake -S . -B build && cmake --build build -j
build/crowd_scenario_tests && build/crowd_api_test
build/crowd_bench --n 10000 --threads 8 --seconds 120 --scenario battle --aftermath 420 --out out
build/crowd_bench --n 10000 --map 320 --threads 8 --seconds 120 --scenario three --aftermath 420 --out out
build/crowd_bench ... --rescue-seek 0 --no-auto-capture      (原規則對照)
```

Windows 有兩種跑法：

- **不需要 Visual Studio**：雙擊 `run_prebuilt.bat`，用 `bin\` 裡預先編好的程式（MinGW-w64，已用 wine 實際跑過）。
- **用 Visual Studio 自己編**：在「x64 Native Tools Command Prompt for VS」執行 `build_msvc.bat`（`/W3 /WX`）。

兩種跑法都會先跑規則測試，再跑 9 組量測，大約 15–20 分鐘。任何測試失敗或量測錯誤碼都會中止。

- 結果放在 `out\base`、`out\three`、`out\original`、`out\default`，每組都有 `result_*.json`、`series_*.csv`（每 5 秒一列）和 `run_*.log`。
- 編譯中間檔放在 `%LOCALAPPDATA%\worldgoing_crowd10k`，避免 Dropbox 鎖檔。

## P2 / C1 — Godot (2026-09-29 … 30)

The core also runs inside Godot as the GDExtension class `ArmyCrowd`
(`godot/crowd10k_gdext.cpp`, `crowd10k.gdextension`, `bin/crowd10k.windows.x86_64.dll`; MinGW build:
`x86_64-w64-mingw32-g++-posix -O2 -std=c++17 -shared -static -static-libgcc -static-libstdc++ src/*.cpp (not bench / api_test) godot/crowd10k_gdext.cpp -Wl,--no-undefined`).

| Batch | What it runs |
|---|---|
| `run_p2a.bat` | `scripts/tests/crowd10k_site_bench.gd`: 50 teams / 5,000 / three factions on real TerrainGenerator ground (simulation, determinism, save / load) |
| `run_p2b.bat` | `scripts/tests/crowd10k_atlas_bench.gd`: the game's soldier atlas, shader and dyes (`render.cpp`, `pack_rows`) |
| `run_p2c.bat` | `scripts/tests/crowd10k_occlusion_bench.gd`: draw order with the real player, depth bands, anti-twitch filter, the player as one crowd soldier |
| `run_crowd_lab.bat` | the formal TerrainLab with `--crowd`: `scripts/terrain_lab/crowd_site.gd` replaces TerrainArmy battles (C1) |

Without `--crowd` TerrainLab is unchanged. Rendering (`render.cpp`): draw order by 64-px row, depth bands where
atlas pages meet, host actors split rows; a presentation filter smooths drawn positions and adds pose /
direction hysteresis (`tools/flicker.cpp` measures it). Host-controlled soldiers (`set_host_control`,
`host_input`): the player is one crowd soldier under every soldier rule (user decision 2026-09-30).

## Read-only host queries (2026-10-02)

`get_life_states()` returns a `PackedFloat64Array` in native soldier-index order,
three doubles per person: HP, KO game seconds, captive (0/1). It directly reads
the original SoA and retains no host state. The original per-person API remains
available. `SiteController.advance_crowd_sustain` uses this projection only for
one synchronous call; damage invalidates the affected person's sample. A
connected `CrowdSite.events_received` observer keeps the original lazy sampling,
because its callback may change another person before their first read.

`hud_stats()` returns eight current panel values: soldier count, alive, down,
deaths, captive, exchange pairs, illegal cells and illegal steps. Their semantics
match `stats()` indices `[0,1,2,7,3,10,14,15]`. It does not build a spatial hash,
scan overlaps or change diagnostics. The original 40-field `stats()` retains
its complete diagnostic behavior.

The Site save/load boundary may reuse its synchronous native candidate after
checking native invariants and exact blob bytes, in addition to all original
schema, build, identity, roster and item guards. A candidate is neither a saved
field nor a persistent cache. New DLL/build identity still requires fresh Crowd
fixtures; no previous-build save identity is rewritten to admit it.

## Post holders and command eligibility (2026-10-07)

Each person has `post_holder` (0/1): they hold a non-head post (civil or military) in their original
team. `command_eligible` is now officer rank and (`post_holder` or the formal captaincy), the same rule
TerrainArmy uses (v2 plan R1b, amended "文官也可以帶兵"). Acting, succession candidates,
`command_effect` sums and the AI's "has a commander" check all follow from it. The host sets the flag
from the team's `offices` at Crowd entry (`set_post_holder` / `get_post_holder`). Standalone callers
default to 1, so benches and scenario tests keep the old behavior. The save magic is now KW09 (`released`, the G6.4 site exit; KW08 added `post_holder`); as with
every native change, saves from an older DLL are rejected by the existing build guard.
