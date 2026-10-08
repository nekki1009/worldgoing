# 單一 Site：天然資源與土地實作紀錄

實作日期：2026-09-11。基線為 V0.3R `81ff890`；本次內容納入 V0.35R，見 `V0.35R_RELEASE.md`。
入口仍是 `scenes/terrain_lab/TerrainLab.tscn`。本紀錄是實作結果，設計依據見
`SITE_NATURAL_RESOURCES_AND_LAND_CONDITIONS_PLAN.md`。

## 已加入的功能

### 2026-09-12 共用工作疲勞

玩家手工作業與原 NPC 工人共用其人物疲勞，軍隊也用同一套規則。有效採集／清理／勘探、施工與生產才收取作業疲勞；缺工具、非法工作格、貨滿、缺投入、缺水、占地受阻及已完成批次等待領貨不累積。採集預檢直接重用 harvest 的完整守衛，沒有另一套資源交易規則。保留原批次投入、產量、進度與搬運，疲勞只縮減有效工作時間。

疲勞超過 30 才有影響，最高增加 30% 耗時（工作速度最低約 76.9%）。初始作業每遊戲小時 +10、安全停工 30 遊戲秒後每小時 −20；與交戰共用 Site 時鐘，暫停不算、離線不補算。右側原存貨／工人面板顯示疲勞與耗時增幅，人物快照同步保存；不新增自動輪休或多人工作名冊。完整規則見 `SITE_COMBAT_DESIGN.md` 第 5.6 節。

實際 controller → Runtime → 人物工作流程、材料／完成貨物守恆、失敗等待與暫停測試通過；原 `site_workflow_test.gd` 回歸通過。GPU 工作流程正常退出 13.159 秒，兩張面板圖已檢視。紀錄見 `output/site_fatigue_20260912_2330/README.md`，初值不代表長時間平衡已驗收。

### V0.35R 原功能

- 九類天然來源：林木、石料、黏土、鐵礦、鹽源、野生食物、藥用植物、魚群、野生動物。
  資源使用獨立 seed 分流；同格可有多個來源，礦藏／棲地的多格範圍共用一份存量。
  地貌不等於可採庫存，也不保證每張圖有鐵礦、鹽源或明水。
- 四類土地檢視：農耕、牧地、淡水服務、建設；提供限制原因、基底潛力與框選統計。
  水域分淡水、海水及內陸鹵水；鹵水點不作淡水井址。
- 第一名工人沿用原 NPC：工作區 → 合法路線 → 到場作業 → 攜帶產物 → 回營地入庫。
  採集、清理、勘探及建設共用這條流程；按工作區由上而下取工作，介面可停用各區。
  工人與玩家不能同時占用同一來源作業。手動採集須站在來源旁，移動或交戰會中斷。
- 建設先預覽占地、清理、材料、入口與工時，確認後才扣施工投入。
  完工前會清除地上來源；地下礦藏保持原存量。拆屋、取消施工不倒帶採集與整地。
  樹木、巨石及實體建物阻擋移動和武器；施工／再生會避開角色的移動來源、目的地及軍隊通道預約。
- 保存 seed、生成版本、稀疏差異、分鐘餘量、存貨、工作進度與攜帶物，重開不重發產物。
  施工中、採集途中與已扣原料的生產批次都能保存。

## 操作

1. 右側選「天然資源」及資源種類，再選「工人採集區」於地圖拖曳。
   工人到場後才工作；「攜帶」與「營地」分開顯示，交貨後才入庫。
2. 改選「清理區」會採完地上資源再清除；鐵礦先選「勘探區」，未勘探前不顯示儲量。
3. 玩家以 WASD 移動，到來源旁按「手動作業」，回營地箱旁按「玩家向營地交貨」。
4. 建設選設施種類及「建設區」，框選 1–36 格。淺色輪廓代表預覽通過，紅色代表拒絕，
   綠圈標出入口；按「安排施工」提交。選中完成的農牧場／作坊，再按「派工運作」。
   長期採集區優先時，可暫時關閉該區讓工人施工或生產。
5. 土地檢視下的「查看」模式也可拖曳框選；供水圖藍色表示服務可達，實際供需另在選中設施中顯示。
6. 原地形生成、人物換裝、騎乘、戰鬥與百人隊伍控制保留在「展開原地形／人物／戰鬥測試」。
   原 NPC 指令會解除工人控制；按「工人開始」可交回工作系統。

## 時間、恢復與供水

| 狀態／來源 | 現行規則 |
| --- | --- |
| 和平 | 1 現實秒＝1 遊戲分鐘 |
| 有效攻擊／受擊 | 1 現實秒＝1 遊戲秒；攻擊時長加 10 現實秒緩衝，新事件續期 |
| 暫停／離開應用程式 | 模擬停止；回來按「繼續」。離線不補產量 |
| 林木 | 10080 遊戲分鐘恢復；清除或人工占地後不再恢復 |
| 野生食物／草藥 | 720／1440 遊戲分鐘恢復 |
| 石料／黏土／鐵礦 | 有限儲量，無自然回補；開採不直接削去地形 |
| 魚群／野生動物 | 120／1440 遊戲分鐘恢復 1 單位，受棲地可用容量限制 |
| 鹽源 | 每來源每遊戲分鐘最多取 3 單位鹵水，未用額度不累積；食鹽需加工 |
| 水井／取水站 | 同一地下水區／水體共用 2／6 單位每分鐘上限；沿合法通行路線服務最多 14 格 |

全 Site 的工作、恢復、生產與供水使用同一時鐘，沒有修改 `Engine.time_scale`。
單純備戰姿勢、遠距離無效攻擊不啟動交戰倍率。時間跨越分鐘或脫戰邊界時保留小數餘量。
供水先分營地與住宅，再分其他設施；重疊取水設施不複製同一來源的容量。
表內數值都是第一版遊戲設定，沒有物理面積、真實產量或生態模型的主張。

## 最小生產串接

目前有住宅、井、取水站、三類農田、養羊牧區、育馬場、鹽場、磚瓦窯、炭窯、
冶煉作坊、鐵匠鋪、製革作坊、織布作坊、土路、整地，共 17 種用途。

| 生產 | 持續投入 | 每批產出 |
| --- | --- | --- |
| 糧食／纖維／飼料農田 | 種子、工具、工時、供水 | 糧食 8／植物纖維 5／飼料 10 |
| 養羊牧區 | 羊、草地承載、飼料、飲水、工時 | 羊毛 2 |
| 育馬場 | 2 頭種馬、草地承載、飼料、飲水、工時 | 馬 1；沒有生皮副產品 |
| 鹽場 | 鹵水 2、木材 1、工時 | 食鹽 2 |
| 磚瓦窯 | 黏土 3、木材 1、工時 | 磚瓦 3 |
| 炭窯 | 木材 4、工時 | 木炭 2 |
| 冶煉 | 鐵礦石 3、木炭 2、工時 | 鐵料 2 |
| 鐵匠 | 鐵料 2、木炭 1、木材 1、工時 | 工具 1 |
| 製革 | 生皮 2、供水、工時 | 皮革 2 |
| 織布 | 植物纖維 3、工時 | 布料 2 |

農田面積增加整地工時、供水需求與生產速度；每批維持可搬運量，原料仍逐批扣除。
牧區保存畜種與種畜數量，草地決定承載；取消或拆除時把種畜退回存貨。
首次建設使用初始木石、黏土、工具、種子、羊及馬，不要求先持有尚未能製造的磚。
井與取水站按不同地基要求選址，河岸濕地可做簡易取水，海岸沙地可做簡易鹽場。

施工／作坊投入由單一營地統一供應；採集物與生產成品需要實際帶回營地。
這是介面明示的單營地簡化，沒有宣稱完成多倉庫投入運輸與完整物流排程。

## 保存與責任邊界

正常執行保存到 `user://sites/current.json`，每 30 現實秒在和平時自動保存，另有手動保存。
開新 seed 之前先按 Site ID 封存舊地圖；右側面板底部可重新開啟已保存地圖。
這些封存地圖不在背景運作，不構成 World／Region 旅行系統。

保存採暫存寫入、校驗、備份與替換；保留上一份 `.bak`。校驗、版本、數量、占地、
工作目標或檔案格式不合法時拒絕載入，保留現況並停用自動覆蓋。
若此時關閉，當前有效地圖按 ID 另存，避免覆蓋損壞的來源檔；保存失敗仍留在現況。
交戰中拒絕地圖保存／載入；正常關閉會停止續發反擊、等待已有動作與緩衝結束後保存。

`TerrainData` 是唯一資料入口；`SiteEnvironment` 生成／查詢，`SiteRuntime` 提交變更，
`SiteStore` 編碼及重建，`SiteController` 轉接介面與原 NPC，`SiteResourceView` 只繪圖。
資源／建物按地面列分批繪製，原 TerrainRenderer 四個地形子層不變。

保存不含角色換裝、戰鬥快照或軍隊狀態。原測試控制的騎乘／裝備仍未消耗生產庫存。
此版沒有完整居民日常、多工人排程、貿易／稅收、作物季節與病害、地下採坑或完整生態。
土路目前保存占地與外觀，不提供額外速度加成；整地只壓低框選範圍至最低層，高差限一級。
鋼、陶器、繩等後續加工品尚未擴充；本期串接止於表列最小配方。

## 驗證證據

Windows / Godot 4.6.2 Mono，使用 `godot-runtime-verify` 的前景限時程序，隔離可寫的
APPDATA／LOCALAPPDATA／TEMP／TMP，檢查真實 exit code 與完整輸出。
下列成功程序均為 exit 0，沒有腳本、斷言或逾時錯誤；根憑證訊息單獨記為環境雜訊。

| 範圍 | 測試／參數 | 結果紀錄（`.godot-temp/godot_verify/` 下） |
| --- | --- | --- |
| 九類生成與採集、雙採集者守恆、鹽源上限、勘探、時間分段、保存 | `site_resource_contract_test.gd` | `20260911_223616_099/result.json`，6.187 秒 |
| 清林→建屋→整地→重建→拆屋、施工途中保存、所有表列配方、面積供水、種畜、損壞檔 | `site_workflow_test.gd` | `20260911_223028_620/result.json`，3.271 秒 |
| 實際面板拖曳、工人步行／攜帶／交貨、暫停通知、有效交戰、角色格位、損壞載入保護 | `site_scene_test.gd` | `20260911_221939_169/result.json`，11.299 秒 |
| 新障礙加入時，百人仍唯一佔格、合法移動、舊命令排空後重算及通道保護 | `site_army_navigation_test.gd` | `20260911_221015_147/result.json`，1.306 秒 |
| 原八地貌×三 seeds 地形／坡口／移動 | `terrain_lab_test.gd` | `20260911_215702_864/result.json`，13.415 秒 |
| 原軍隊通道轉彎 | `terrain_army_passage_test.gd -- --case=E05_TURN` | `20260911_220200_288/result.json`，7.769 秒 |
| 原軍隊環境變更交易保護 | `terrain_army_width_transaction_test.gd -- --contract=Q02_ENV` | `20260911_220113_145/result.json`，1.115 秒 |
| 原正式入口、模型依賴、角色及百人部署 | `v03r_cleanup_test.gd` | `20260911_222230_854/result.json`，1.753 秒 |
| GPU 武器命中、防禦、死亡、騎乘與武器切換 | `terrain_lab_combat_test.gd`（visual） | `20260911_215627_171/result.json`，18.193 秒 |
| GPU 資源／土地、野生動物姿態、住宅／井／農田、有效及拒絕預覽 | `site_resource_visual_test.gd`（visual） | `20260911_223144_316/result.json`，17.979 秒 |
| GPU 自然海鹽、魚群活動、實際可建河岸取水站與服務範圍 | `site_resource_visual_test.gd -- --water`（visual） | `20260911_221132_913/result.json`，15.586 秒 |
| 編輯器載入／匯入 | editor scan | `20260911_223457_721/result.json`，4.668 秒 |

圖片位於 `.visual_captures/site_resources/`，已人工檢視實際 PNG；成功產生圖片不單獨作為遊戲流程通過依據。
圖中房屋、井及農田為驗證配置，工人實際行走另由場景測試證明。
2026-09-11 當次靜止 GPU 預覽的 20 幀樣本：314 個來源、100 個資源列批次、整場景 1772 Nodes、
2976 draw calls，幀間隔中位數 16.522 ms、最大值 18.336 ms。
原始記錄為 `preview_metrics.json`；這個短樣本不是戰鬥效能基準，也不證明完整軍隊測量矩陣通過。

開發時曾攔下解析／測試場地錯誤，修正後才重新驗證。舊戰鬥測試在無圖形模式不會載入碰撞模型，
所以該模式的命中斷言失敗不算成功；最後改以 GPU 模式驗證。原測試的平地 fixture 另清空新增靜態障礙，
真實資源／建物阻擋仍由新測試獨立保留。未執行全部軍隊、全武器接觸視角及長期平衡矩陣。

重現方式：以技能的 `verify_godot.ps1 -ProjectPath (Get-Location)` 執行，資料／場景測試使用
`-Mode headless -TimeoutSeconds 20 -GodotArguments @('--script','res://scripts/tests/<上述檔名>')`；
需要模型與圖片的測試使用 `-Mode visual -TimeoutSeconds 27`。完整路徑、stdout／stderr 與時長都在各 result.json 同目錄。

## 2026-09-11：環境圖試接

已把使用者確認的住宅、水井、農田與營地箱圖接入 `SiteResourceView`。內建 image_gen 將概念稿的
棋盤格改為單色底；遊戲用一張共用圖集與去背材質繪製，並未把 RGB 圖謊稱為透明 PNG。
來源、生成提示及貼圖規格見 `assets/map/site/settlement/README.md`。

住宅依實際框選占地縮放，截圖示例是 3×3 格住宅；農田逐格鋪在人物腳下，
同列建物排序放在原人物後面，較北側人物仍會被屋頂遮住。原地形四層、100 個資源列批次保持不變。
營地箱立即使用新圖；住宅、井與農田完工後使用新圖，既有存檔不需遷移。
人物模型、角色／NPC 腳本、角色編輯器及 SiteRuntime 在本次美術接入前後的 SHA-256 相同。

本次檢查使用 Godot 4.6.2 Mono，同前述隔離環境及前景限時程序：

- 完整資源匯入：`-Mode headless -GodotArguments @('--editor','--import') -TimeoutSeconds 27`，
  `20260911_231657_001/result.json`，exit 0，8.337 秒。
- GPU：`site_resource_visual_test.gd -- --props`，`20260911_232047_650/result.json`，exit 0，15.352 秒。
  實際建設命令、房屋阻擋、農田可站立、原人物 SubViewport 與騎乘通過；縮小截圖未檢出洋紅底。
  已檢視 `props_overview`、房屋前後、人物在農田、水井近景及原騎乘的 PNG，檔案均在前述截圖目錄。
- 工人／面板／存檔回歸：`site_scene_test.gd`，`20260911_231931_713/result.json`，exit 0，11.325 秒。
- `git diff --check` 通過。根憑證訊息仍只列為環境雜訊。

第一輪 GPU 因兩幀編輯器掃描尚未完成新 PNG 匯入而失敗；補做完整 `--import` 後才得到上述成功結果。
此輪是四種環境圖的試接，未更換自然資源、草地或其餘作坊；未重跑完整戰鬥效能矩陣。

## 2026-10-01 野生動物視覺與走路動畫試放

狀態：已完成 `D:\worldgoing_crowd10k` 的主畫面試放，使用者要求將成果納入本正式文件。`D:\worldgoing` 的遊戲顯示程式與正式素材尚未接入；本節不屬於上方 V0.35R 的發布內容。實際入口仍是 `res://scenes/terrain_lab/TerrainLab.tscn`，素材、畫面與結果保存於 [走路試放目錄的說明](D:/worldgoing_crowd10k/output/wildlife_walk_trial_20261001/TRIAL_README.txt)。

### 已實作的呈現

有角鹿、野豬、無角鹿、野馬各有左右兩向、每向四幀，共 32 格。鹿與野豬使用生成的透明圖集；野馬從原 `assets/mounts/horse/standard_horse_pack.glb`，透過 `MountHorse3D` 關閉馬具、移除騎士後，取原 `horse_walk` 離線烘焙。遊戲執行時讀取共用貼圖，不為每匹野馬載入 3D 馬模型。

呈現沿原 `SiteController → SiteResourceView.animate` 呼叫、`animation_time` 與 0.12 秒動態列重繪。原漫步位置保持水平 ±9、垂直 ±5 像素；水平移動方向決定左右向，同一活動相位決定四幀索引，慢步循環約 2.5 秒。每個方向共用接地錨點，不按每幀外框重新置中或縮放。

繪製仍在原 `SiteResourceView` 的 WILDLIFE 分支、同一資源列內完成：先畫接觸陰影，再 flush 原三角形批次，畫圖集區域；保留數量、可通行／建物檢查與列排序。沒有新增逐動物 Node、AnimationPlayer、AI、時鐘或保存欄位。原 `_draw_animal` 仍供未套用試放貼圖的來源與育馬場使用。

試放只指定四個來源套圖：原 variant 0、1、2 分別呈現有角鹿、野豬、無角鹿；野馬另指定一個 variant 2 來源。沒有新增 variant 3、修改產肉／生皮規則，或完成野馬的獨立物種、捕捉、馴化與坐騎交易。一般啟動不會自動載入試放目錄；正式來源與外觀的穩定映射仍待接入。

### 已驗證的範圍

本輪使用 Windows / Godot 4.7.2 Mono，以及未修改的 `godot-runtime-verify/scripts/verify_godot.ps1`。以下四次均 PASS、exit 0，沒有腳本、斷言或逾時錯誤；結果與完整日誌已另存到具名試放目錄，不依賴臨時驗證資料的保留期限。

- [野馬烘焙結果](D:/worldgoing_crowd10k/output/wildlife_walk_trial_20261001/evidence/horse_bake/result.json)：3.989 秒，兩向各四幀，原模型及步行動畫來源保留。
- [無視窗素材與入口檢查](D:/worldgoing_crowd10k/output/wildlife_walk_trial_20261001/evidence/headless/result.json)：3.259 秒，32 格透明素材、相鄰幀差異、可見輪廓留邊及實際主場景載入。
- [實際主畫面與比較結果](D:/worldgoing_crowd10k/output/wildlife_walk_trial_20261001/evidence/main_walk_gpu/result.json)：53.977 秒，原主回呼推進動畫相位、暫停凍結、資源篩選；有角鹿右／左指定幀的實際畫面區域與預期圖集幀一致。試放建立後，`resource_base`、`site.changes`、四個來源的剩餘量及 view 後代節點數不變。
- [動畫錄製結果](D:/worldgoing_crowd10k/output/wildlife_walk_trial_20261001/evidence/record_preview/result.json)：39.829 秒，32 張實際主畫面截圖，已檢視腳步與轉向。截圖讀回／寫檔在效能比較之外；錄製畫面不以受寫檔影響的 FPS 作為效能證據。

[實際主畫面走路預覽](D:/worldgoing_crowd10k/output/wildlife_walk_trial_20261001/wildlife_walk_preview.webp)由這 32 張截圖封裝成無損全彩動畫。[重播腳本](D:/worldgoing_crowd10k/output/wildlife_walk_trial_20261001/run_wildlife_walk_preview.ps1)沿 canonical verifier 執行 `wildlife_walk_capture.gd -- --crowd`，外部時限 120 秒；變更與來源檢查讀回原 owner，沒有另造動物資料帳。

首次素材檢查曾因生成圖的 alpha 1～15 散點碰到圖格邊緣而 FAIL；exit 0 仍分類為失敗。[原失敗結果](D:/worldgoing_crowd10k/output/wildlife_walk_trial_20261001/evidence/first_headless_failed/result.json)、日誌、原腳本及當次輸出均保留。修正後同時記錄非零 alpha 邊界與 alpha ≥16 的可見輪廓邊界，確認動物本體未裁切，並修正斷言失敗後繼續輸出的流程；沒有修改圖集像素。這項預覽檢查不取代正式圖集的透明留邊與零雜點驗收。

### 本次效能比較

比較只含四隻動物、相同主場景／相機／完整圖集，原漫步在兩種模式都保留：A 固定一幀，B 切換走路幀。關閉垂直同步與幀率上限，按 A/B/B/A 順序，每輪暖機 0.5 秒、量測 2 秒。Crowd bridge 存在但未啟用，沒有部署軍隊。

- A1：2668 個樣本，幀間隔中位數 0.641 ms、P95 0.968 ms。
- B1：2629 個樣本，幀間隔中位數 0.654 ms、P95 0.963 ms。
- B2：2691 個樣本，幀間隔中位數 0.635 ms、P95 0.958 ms。
- A2：2662 個樣本，幀間隔中位數 0.6435 ms、P95 0.990 ms。

四輪 draw calls 中位數與 P95 都是 185，最高都是 276，逐動物節點增量為零。本次沒有呈現一致變慢；短樣本不證明零成本、大量動物效能或正式萬人 FPS，也不能與上方不同場景的 2026-09-11 指標直接相減比較。

四份新 RGBA8 圖集解碼總量 18.51 MiB，前一版單姿勢圖片為 12.00 MiB，差約 6.50 MiB；這是圖片解碼位元組數，不是實測 GPU 配置。圖集可共用，不按每隻動物複製；A/B 使用同一完整圖集，因此容量差異不是 A/B 的量測結果。完整原始樣本及修正解讀見 [performance_interpretation.json](D:/worldgoing_crowd10k/output/wildlife_walk_trial_20261001/performance_interpretation.json)。原始 `process_ms` 保留作診斷，但 Godot 4.7.2 的該監測值是前一個約一秒窗口的峰值且包含渲染同步／繪製，不能作為每幀或動物專屬 CPU 成本。

### 正式遊戲接入仍需完成

後續接入沿本文件及原資源 owner，不另建動物、棲地、時鐘、renderer 或保存 authority。詳細來源與素材接入規格見 [原視覺接入計畫](D:/worldgoing/output/wildlife_visual_preview_20261001/PLAN.md)；其中第一輪「尚未執行」為生成候選時的歷史狀態，本節記錄後續已完成的 Crowd10k 試放。尚未完成的驗收包括：

1. 將生成圖規格化為正式圖集，清除透明雜點並保留完整角腳與至少 4 像素留邊；檢查左右受光、體型、斑點、接地與腳滑。四幀預覽不等於完整八方向或高幀數動畫。
2. 在原 WILDLIFE 呈現入口建立可重建的穩定來源映射與共用素材載入；保留 variant 0～2、舊來源 ID、產出、存檔及育馬場用途，不以刷新時隨機選圖。
3. 驗證剩餘量 0／1／容量、採集／恢復、清除／建物占地、revision 與存讀後一致；重跑原資源契約，維持歷史 retained rows 比較的資料、排序與全 RGBA 等價要求。
4. 檢查 RegionLab 固定姿態、人物／樹／建物遮擋、魚與聚落材質相容，以及 0.25～3 倍縮放；再做大量動物的相同場景比較。萬人軍隊須獨立沿正式效能驗收流程測試。

## 2026-10-02 追加羊的走路動畫

使用者要求把羊加入同一批野生動物視覺。已在 `D:\worldgoing_crowd10k` 完成五種動物主畫面試放：有角鹿、野豬、無角鹿、野馬、羊，各左右兩向、每向四幀，合計 40 格。上節四種動物的原始素材、畫面與量測證據仍保留；新增結果獨立保存於 [追加羊試放說明](D:/worldgoing_crowd10k/output/wildlife_sheep_walk_trial_20261002/TRIAL_README.txt)。

羊採奶白色羊毛、短角、灰褐頭腿與深色蹄，沿鹿與野豬的俯視畫風製作[透明慢步圖集](D:/worldgoing_crowd10k/output/wildlife_sheep_walk_trial_20261002/sheep_walk_raw_v1.png)。使用內建 imagegen；[完整提示與參考來源](D:/worldgoing_crowd10k/output/wildlife_sheep_walk_trial_20261002/generation_prompt.json)一併保存。素材仍為預覽圖集；透明雜點、步態連續性與正式圖格規格沿上節待驗收項目處理。

羊只增加一個原 WILDLIFE 來源的貼圖映射，使用 variant 2、容量 1，試放格為 `(50, 47)`；沒有修改原 renderer、加入逐動物節點或另設時鐘。原 `wildlife_walk_capture.gd` 以 `--sheep` 選配追加，未帶該參數仍走四種動物預覽。沒有新增野羊資料／產出規則，也不從養羊牧區扣種羊、改羊毛產量或建立捕捉／馴化交易。本輪羊圖集仍只在 Crowd10k 試放，尚未接入 `D:\worldgoing` 的正常遊戲入口。

已驗證：

- [無視窗五種素材與主場景載入](D:/worldgoing_crowd10k/output/wildlife_sheep_walk_trial_20261002/evidence/headless/result.json)：Godot 4.7.2 Mono，PASS、exit 0、3.481 秒，五種各八格，共 40 格。
- [五種動物實際主畫面](D:/worldgoing_crowd10k/output/wildlife_sheep_walk_trial_20261002/evidence/main_walk_gpu/result.json)：PASS、exit 0、47.278 秒。已檢視全景、近景與動畫截圖，五種動物都完整可見；原主回呼推進動畫相位，暫停會凍結相位與換幀，試放建立後的資源存量／變更與 view 節點數不變。
- [有角鹿與羊左右取幀比對](D:/worldgoing_crowd10k/output/wildlife_sheep_walk_trial_20261002/captures/frame_selection_checks.json)：實際畫面區域等於指定圖集幀，且不同於同方向的相鄰幀。檢查裁切範圍有效並加入錯幀負對照，避免兩張相同背景被誤判為動畫通過。

本輪五隻 A/B/B/A 的幀間隔中位數分別為 0.733／0.681／0.699／0.718 ms，P95 為 2.953／3.012／3.051／3.012 ms；四輪 draw calls 中位數及 P95 都是 188、最高 279。比較只切換相同圖集的固定幀／走路幀，未部署軍隊，沒有測到一致變慢。完整原始樣本見 [五隻效能比較](D:/worldgoing_crowd10k/output/wildlife_sheep_walk_trial_20261002/captures/performance_comparison.json)。不同日期的場景與呈現原始碼已不同，不能直接與上節四隻數字相減推算羊的 CPU／GPU 成本。

羊圖集新增解碼容量 6,294,152 bytes，約 6.00 MiB；五份圖集合計約 24.51 MiB，均可按圖集共用。這是 RGBA8 圖片位元組數，不是 GPU 配置量測，也不是每隻羊各占一份圖集。上節 12.00 MiB 的舊單姿勢基線只包含四種，不能改稱五種單姿勢基線。`TIME_PROCESS` 的峰值解讀與大量動物／正式萬人未驗收界線仍沿上節。

[五種動物走路動畫預覽](D:/worldgoing_crowd10k/output/wildlife_sheep_walk_trial_20261002/wildlife_with_sheep_preview.webp)由 32 張實際主畫面截圖封裝。[重播入口](D:/worldgoing_crowd10k/output/wildlife_sheep_walk_trial_20261002/run_wildlife_sheep_preview.ps1)沿未修改的 canonical verifier 執行 `wildlife_walk_capture.gd -- --crowd --sheep`，外部時限 120 秒；不覆寫四種動物的原始證據。

## 2026-10-02 天然資源正式素材替換

前節「尚未正式接入」為 2026-10-01 試放時的狀態。本輪依使用者確認的素材預覽，在原 `SiteResourceView` 正式接入九類天然資源外觀：三種樹、石料、黏土、鐵礦、鹽源、野生食物、藥草、魚，以及有角鹿／野豬／無角鹿。靜態資源使用新生成透明圖集；三種動物沿用前節試放的左右各四幀圖集，variant 0／1／2 穩定對應，育馬場仍走原呈現。正式素材、實際裁區／尺寸／接地錨點與生成提示在 [natural_resources/README.md](assets/map/site/natural_resources/README.md)。

貼圖在原顯示 owner 一次載入共用，仍沿原列排序、批次 flush、動畫相位與刷新頻率。未新增資源種類、物種欄位、來源 ID、Node、AI、時鐘或保存欄位。兩個現有 export preset 已加入 PNG 與 manifest。RegionLab 沿用同一顯示類別，其既有固定姿態行為保留；本輪未將 RegionLab 實際 GPU 畫面列為已驗證。

本輪實拍載入 `project.godot` 的正式 TerrainLab 主場景，使用預設自然地形及正式「海岸斷崖／seed 71」生成流程，保留原 UI。截圖沒有人工補放來源或合成背景，拍攝時只凍結模擬、調整相機與呈現動畫。採用隔離的驗證存檔目錄，不寫入使用者既有 Site。0.5／1／2 倍及個別近景的原始 PNG 存於 [captures](output/natural_resources_formal_20261002/captures)。截圖中的 FPS 包含素材檢查、同步讀回與寫檔，不能作為遊戲效能結論。

透明本體以 alpha ≥16 檢查，靜態裁區至少 2 px 留邊、動物格至少 4 px；原圖 alpha 1～15 的少量散點仍保留，未宣稱完成零雜點或全部動畫腳滑驗收。原有採集、清除、耗盡、恢復及保存行為由資源契約與本輪存讀測試確認；兩組新圖的 retained／nonretained 全 RGBA 比較均要求完全相同，沒有拿刻意更換前的舊畫風當像素基準。未重跑大量動物、完整戰鬥效能、全平台或完整發行封包測試。

首次新測試在 JSON 數字陣列的型別比較上失敗，canonical verifier 正確判為 FAIL，即使當時子函式斷言中止後上層誤寫 PASS。已改為逐值驗證與逐層傳遞失敗；原失敗日誌、當次測試與無效報告保留於 `output/natural_resources_formal_20261002/verification/20261002_232115_546/`，不納入成功證據。第一輪實拍後另將動物接觸陰影由舊幾何圖的偏移位置移回圖集的地面錨點。
本次成功驗證皆使用未修改的 canonical `verify_godot.ps1`、Godot 4.7.2 Mono，exit 0，無腳本／斷言／逾時錯誤；下列每個 result 旁均保留 stdout、stderr、combined 日誌：

- editor `--import`：`verification/20261002_231853_289/result.json`，114.678 秒。
- headless `site_resource_contract_test.gd`：`verification/20261002_232237_716/result.json`，7.770 秒，原九類採集、地形分離、交易、時鐘、稀疏保存。
- headless `site_natural_resource_art_test.gd`：`verification/20261002_232822_968/result.json`，7.362 秒，四圖集／24 動物幀、九類與三 variant、清除／耗盡存讀、全部 view mode 不改 owner。
- 最終 visual `site_natural_resource_art_test.gd -- --visual`：`verification/20261002_233405_632/result.json`，26.141 秒，14 張實拍，含 3 倍的三種動物近景。兩組 retained／nonretained 完整 RGBA 相同，所有拍攝前後 owner 比對通過。

以上相對路徑以 `output/natural_resources_formal_20261002/` 為根。最終來源、相機、縮放、可見來源 anchor 與截圖 SHA-256 在 `result_visual.json`；素材規格結果在 `result_headless.json`；目視檢查及交付雜湊在 `visual_review.json`。本次未提交或推送 Git。

## 2026-10-03 五種野生動物與馬羊捕捉正式接入

依使用者「把五種動物都正式接入」及「馬跟羊可以抓回牧場」的要求，正式 `D:\worldgoing` 已接入有角鹿、野豬、無角鹿、野馬、羊，以及活捉與入欄操作。前節 Crowd10k 試放和三種正式素材的敘述保留為歷史紀錄；以下為本輪狀態。

`SiteEnvironment.wildlife_species(variant, source_cell)` 是唯一物種判定入口：variant 0 的來源 anchor cell 偶數為有角鹿、奇數為野馬；variant 1 為野豬；variant 2 的偶數為無角鹿、奇數為羊。使用整個來源的固定 `cell`，不按群內個別顯示格、剩餘量、刷新或動畫相位改種。原 variant 0～2、來源 ID、天然基底與保存格式保留；舊存檔中奇數 anchor 的 variant 0／2 來源會依新規則顯示野馬／羊，存量不重置。

五份圖集由原 `SiteResourceView` 一次載入共用，每種左右各四幀；自然來源仍沿原資源列、遮擋排序、接地陰影、漫步相位與 0.12 秒刷新。已完成的養羊牧區與育馬場也使用相同羊／馬素材，保留原固定姿態和居民數顯示。沒有新增逐動物 Node、AI、時鐘、物種保存欄位或家畜帳本。野馬從原 `MountHorse3D`／`horse_walk` 關閉馬具後重烘焙，擴大共用裁區以保留完整馬身；羊沿用已確認的原圖 bytes。來源及 SHA-256 見 [asset_sources.json](output/wildlife_formal_20261002/asset_sources.json)，正式規格見 [素材 README](assets/map/site/natural_resources/README.md)。

### 遊戲操作與原 owner

1. 在工作視窗選取野馬或羊來源，讓控制人物走到來源旁，按「活捉馬／羊」。沿原工具、可到達工作格、攜帶容量與六遊戲分鐘工作規則，每批從同一來源扣一隻，放入本人既有 `horse` 或 `sheep` cargo；這筆捕捉不產肉皮。原「手動作業」與狩獵產肉／生皮數值不變，鹿與野豬不能活捉。
2. 將本人攜帶的馬／羊帶到已完成且種類相符的育馬場／養羊牧區入口，選取牧場，在建設視窗按「把攜帶馬／羊送入所選牧場」。`SiteRuntime.stock_pasture` 同次扣 cargo 並增加原 `feature.residents`；人物須站在入口或可合法跨步到入口的相鄰格。超過原土地放牧承載或保存上限 36 隻的部分留在本人身上，錯種、未完工、不可達與滿欄均拒絕。
3. 框選「馬羊捕捉區」沿原工人／隊伍工作分配、自動尋路、攜帶與營地交貨。捕獲家畜進入原營地存貨，可供原建場投入，亦可用原物品流程取回後入欄。自動工人沒有新增直接選牧場的配送規則。

玩家、NPC 與隊伍人物沿 `SitePersonActions._person` 取得既有身份、cargo、holder 與位置；正式操作沿原暫停、清醒／自由、其他作業、來源預約及 Crowd 控制限制。入欄成功更新原 holder version，避免持物視窗沿用舊狀態。`SiteRuntime` 保留來源減量／產物增加的單次提交；`SiteWorkTeam` 與 `SiteStore` 在原工作命令驗證中接受合法 `capture`，拒絕錯種目標。捕捉中進度、本人攜帶、營地存貨與牧場居民都沿原保存流程；不另造跟隨動物實體。牧場原建造投入、羊毛／馬匹生產與拆除返還規則沿用既有 owner。

### 本輪驗證紀錄

本輪使用 Godot 4.7.2 Mono 與未修改的 canonical `verify_godot.ps1`。結果、完整日誌、失敗證據及圖片統一保留於 [wildlife_formal_20261002](output/wildlife_formal_20261002/)。下列路徑均相對於該目錄；無視窗測試的根憑證訊息另記為環境雜訊，不隱藏在日誌之外。

- 野馬離線重烘焙：`verification/20261002_235622_157/result.json`，visual PASS、exit 0、1.651 秒。
- 修正歷史副本掃描後的 editor `--import`：`verification/20261003_001306_177/result.json`，PASS、exit 0、31.160 秒。
- 五種素材與資料契約：`verification/20261003_002111_494/result.json`，headless PASS、exit 0、9.258 秒。六張圖集／40 個動物幀、六組已知映射、九類資源、三個原 variant、剩餘量／清除／恢復／存讀映射、原 view mode 與固定 RegionLab presenter 切片。
- 正式主畫面實拍：`verification/20261003_003817_047/result.json`，visual PASS、exit 0、27.728 秒。16 張圖片包含原自然高地與海岸、0.5／1／2 倍與五種動物 3 倍近景；沒有補放天然來源。兩組 retained／nonretained 完整 RGBA 相同，動畫暫停、230 個 presenter 節點帳與 owner 不變檢查通過。原始圖與來源 anchor 在 `captures/` 及 `result_visual.json`。
- 正式 UI 捕捉／入欄：`verification/20261003_003648_241/result.json`，visual PASS、exit 0、16.846 秒。從正式 main 載入原控制人物，發出兩個實際 Button 的 `pressed` 訊號；馬羊各經原六遊戲分鐘取得一隻、本人 cargo／來源減量守恆，再送入原 Runtime 建造完成的相符牧場。錯種按鈕及強制訊號、兩種暫停、原 holder version 都有檢查。四張 UI 圖與結果在 `capture_ui/`；人物位置、施工與時間推進是明示測試配置，不是自然遊玩全程錄影。
- 捕捉／保存／牧場契約：`verification/20261003_005207_107/result.json`，headless PASS、exit 0、12.883 秒。馬羊活捉與原狩獵共享來源守恆、預檢無副作用、最後一隻競爭、錯種／工具／攜帶／清除／占地拒絕、工作中途及貨物／營地／居民保存、入欄不可達／錯種／未完工／滿欄／部分轉入／36 上限，以及拆除原居民返還。Army 使用原隊員工作 fixture，驗原手動與自動 capture、工作命令及 JSON roster 驗證；不把合成 Army 場地稱為完整軍隊存檔重建。
- 原資源回歸 `site_resource_contract_test.gd`：`verification/20261003_004755_018/result.json`，headless PASS、exit 0、8.272 秒。
- 原隊員工作回歸 `site_work_team_test.gd`：`verification/20261003_004843_578/result.json`，headless PASS、exit 0、11.590 秒。
- 原建設／搬運／恢復回歸 `site_workflow_test.gd`：`verification/20261003_005049_792/result.json`，headless PASS、exit 0、4.960 秒。

已使用圖片檢視器逐張檢查五種近景與四張捕捉／入欄畫面，目視結果及圖片雜湊在 `visual_review.json`。相鄰棲地仍可能在原格位上重疊，牧場居民沿原位置排列；未把既有布局改為新動物導航。畫面 FPS 受凍結、同步讀回與寫檔影響，不作效能結論。

首次 editor 匯入因另一項工作在 `output/idle_fps_fix_20261002/{before,candidate}` 保存了同名 `TerrainArmy` 原始碼而失敗。核對無正式 runtime 引用後，僅在這兩個歷史副本目錄加 `.gdignore`；保留父目錄的可執行 probe 與測試。全域 class cache 已恢復正式 `scripts/terrain_lab/terrain_army.gd`，重跑匯入通過。首次捕捉測試另發現選用的天然 Plains／12345 沒有全部測試物種，以及 Army JSON 數值型別比較問題；改用經短 probe 確認的正式高地／12345，保留原生成參數供存檔重建。第二次捕捉測試在原工作格被建物占用後仍期待來源占用錯誤，實際先被原不可達守衛拒絕；需分別驗證兩種拒絕。失敗日誌與當次腳本均保存，不能算通過。

捕捉測試第三輪亦保留失敗 `verification/20261003_004816_553`：原 Store 會將未完成工人恢復為 travel，直接 Runtime 測試漏掉已到站後轉 work 的既有條件。測試現先驗存讀後原 cell／work_cell 與合法工作格，再恢復到站狀態推進；正式程式未為測試放寬限制。成功結果以 `20261003_005207_107` 為準。

附加的舊 `site_work_team_clock_test.gd` 未列通過：首次因預設 NPC 已改為按需建立而在配置階段失敗（`verification/20261003_004948_038`）；暫以原入樹前 NPC 入口與正式工作視窗適配後，通過原兩隊員工作及初段共同時鐘檢查，但在第 117 行舊疲勞斷言失敗（`verification/20261003_005614_214`）。測試要求受控隊長脫離共享池、count=2；現行 `PersonFatigue` 與 `TerrainArmy.sync_shared_fatigue` 明定包括受控隊長的全隊共池，控制切換也已同步。本輪沒有修改疲勞實作或放寬此斷言；兩份失敗日誌／當次測試均保留，該舊測試已還原本輪前 bytes。完整共同時鐘舊測試的契約更新仍是獨立缺口，不能把本輪 Runtime 存讀與 UI 捕捉結果擴大為它已通過。

RegionLab 僅驗證共用 presenter 的固定姿態資料契約；本輪不宣稱 RegionLab 全地理 GPU、動物跟隨／馴服 AI、大量動物效能、完整軍隊戰鬥或發行封包完成。圖集 alpha 1～15 的微量散點沿原素材保留，未宣稱零散點或高幀數動畫。牧場大量居民的原位置排列也未改為新的群聚系統。
