# Site 200 人 GPU 批次戰鬥計畫

2026-09-14 遠程後續已接入原相鄰交鋒模式：弓弩落點到期單次結算，仍無身體／武器幾何查詢。200 人含 40 射手／60 秒、800 發實際扣彈通過，完整條件與限制見 [遠程證據](output/site_ranged_20260914/README.md)。這不是舊精確 GPU 批次計畫完成，也不把不同相機的 FPS 作等價加速比較。

2026-09-14 最新授權已更換近戰玩法，不再要求武器／身體精確碰撞。後續正式工作改見 [相鄰交鋒 v1](SITE_COMBAT_EXCHANGE_V1.md) 與 [新模式實測](output/site_exchange_20260914/README.md)。本文件以下為原精確／GPU 試驗歷史，不將新規則成果計為精確 GPU 方案完成，也不繼續無收益候選索引。

**2026-09-14 03:08：附近候選索引已完成驗證與固定相機對照，仍無穩定收益，維持關閉。** 5,091 案與原六人各 141 步真命中重播通過；同來源固定視角 200 人／60 秒 OFF→ON 平均 **16.61→18.02 FPS**、P95 **218.93→208.71 ms**，末十秒卻 **6.6→5.9 FPS**。平均差不能當作等工作量／多輪穩定加速；兩組各自相同尾段輸入的候選搜尋皆較慢，建索引與排序吃掉少遍歷的收益。`contact_buckets_enabled=false`，不再追加此輪索引變體，流暢門檻未通過。兩個修前失敗、初次相機不同的對照及後續補驗全部保留；使用者要求已寫入 AGENTS，取消每次失敗就停問、改為明確定位後自主修正重驗。[完整證據](output/site_contact_buckets_20260914/README.md)

**2026-09-14 02:29 歷史：依新授權完成簡化碰撞資料試版，有改善但仍未流暢，僅保留為預設關閉測試。** 原 200 人／120 Hz 最大子步／各 60 現實秒，同來源原版 **15.86 FPS／P95 322.80 ms**、簡化初版 **19.50 FPS／196.67 ms**；尾段仍 **6.5 FPS**。修正 Actor／Army 簡化瞄準肩點一致性並加既有輸入重用後，當時最新為 **18.36 FPS／196.08 ms／尾段 6.2 FPS**，未有額外加速證據；後一場來源不同，不作單變因比較。

本試版改為十部位矩形＋武器／盾／招架簡化輪廓、按原關鍵時間連續插值、部位／實裝護甲規則，保留空間掃掠、原人物／物品／時鐘與結算；是 **CPU 純資料候選，不是 GPU，也不是原精確規則等價優化**。正式 owner 的 `combat_proxy=null`，只在 `--coarse-proxy` 測試注入；下方原精確計畫約束不因試驗而改成已達標。共享 Source 在候選量測窗口新增取樣 0，但 Actor 視覺骨架／IK 仍運作，其他逐步接觸收集／疲勞威脅／導航成本仍在。最新獨立性能門檻亦 false，不能只因放寬碰撞便稱解決。[實際規則、全部資料、驗證與限制](output/site_combat_proxy_20260914/README.md)。

**接續 2026-09-14：附近候選索引已做成預設關閉試版，首測 FAIL 已修型別、尚未重驗。** 只在原接觸批次用原接點分區，不移除倒地者、不改命中或疲勞。新增候選計數／原命中重播／尾段同輸入重播入口；但 `20260914_025047_200` 發生 Array→Array[int] 錯誤，依驗證技能停止後續啟動。已修正明確整數陣列並補完整案數守衛，沒有新 FPS 或索引效能結論。[本輪完整紀錄](output/site_contact_buckets_20260914/README.md)

以下保留歷史結果。

**2026-09-14 01:58：延後 body/head/shield/parry 凸包試版已量測並撤回，流暢目標仍未完成。** 同來源、同 200 人、各 60 秒為原版 **14.54 FPS / P95 338.29 ms**、候選 **14.68 FPS / P95 346.73 ms**，最後十秒皆 **3.7 FPS**。雖約 58.9% 延後輪廓未需生成，query＋exact 幾何收集仍 **17.74→18.02 秒**，沒有淨收益；不能只看轉移了成本的單項計時。另有 128-key 淘汰後可能新增 pose restore 的未覆蓋風險，不啟用也不留停用開關；全部本輪 runtime 改動已還原原 hash。64 組查詢及 141 步實際命中重播通過的範圍、原始 A/B／失敗／試版快照見 [試驗紀錄](output/site_deferred_hulls_20260914/README.md)。原 200 人／120 Hz／30 FPS 門檻不降。

以下保留前次結果。

**2026-09-14 01:28：Source 幾何接入已實作並完成三場 full60，沒有整場加速，流暢計畫仍未完成。** 同來源 `cd11a8a0fe4dc256` 的原版／C# 幾何／C#＋既有輸入重用為 **14.47／14.33／14.71 FPS**，P95 **330.28／353.88／348.53 ms**，最後完整十秒 **3.8／3.1／3.3 FPS**；三場 `targets_met=false`。所以 `compiled_geometry_enabled` 與 `contact_input_reuse_enabled` 都維持 false，不將此接法交付為預設加速。

這一步只在原 `_pose` 之後接 C# Shapes，**沒有接入先前完整 Pose／Query／Batch 試驗**，仍非 GPU／多核心。原快取不 seek、partial 只補武器、護甲先 restore、原換裝／held／morph／first-head-fit 保留。三組原歷史 4＋65＋8 cases、實際141步扣血回放與新增35項生命期檢查通過；本輪也修正完整Dictionary key型別與C# view釋放問題。原明光甲的非零變形與瞄準仍明確走原生，不放寬命中精度。

整場接入有18,442次新幾何成功＋286次原生partial，74次護甲成功，並非未使用C#；但準備資料5.002秒、C#幾何3.976秒，足以吃掉局部收益。ordinary bounds整條路16.935秒包含在collect_geometry19.968秒內，narrow碰撞僅0.592秒；不得相加或把後者搬到C#就當作能省前者。下一個切片須沿原owner減少重複request/view/bounds整理，保留每個Army回呼同步返回、hits/blocked/護甲的依賴，再量含資料搬運的整段成本。人數200、120Hz、60現實秒與原30FPS等門檻不變。[完整資料、失敗與修正紀錄](output/site_compiled_contact/README.md)

以下保留前一階段歷史，不把其36–47%的離線收益套用到本次Source幾何接法。

**2026-09-14 00:42：C# 受限完整取樣試驗已實作，整場流暢仍未完成。** 使用者已同意試作新增建置流程；新增獨立 C# pose／geometry／query／batch helper，正式 TerrainLab 路徑尚未切換。最終同工作量三輪中位數：持盾 56 筆取樣 **76.848→49.146 ms（省 36.05%）**；未配盾 330 筆取樣 **281.603→147.891 ms（省 47.48%）**。兩組原幾何、接觸次序、護甲與原傷害封包完全一致，但不包含 HP 結算、完整 AI、200 人或呈現，因此不是新 FPS，也不推算整場已達標。[各版失敗／修正／原始 JSON／准入缺口](output/site_compiled_contact/README.md)

這次是**同步 C#＋Godot 原生計算**，不是 GPU 或已驗證多核心。第一版直搬較慢，之後依分段計時移除剛性部件多算的骨骼矩陣、資料複製與無需執行的排序才取得收益。原 Source 的快取不 seek、partial weapon／armor restore、換裝／held／morph／first-head-fit 歷史仍須接回並完整對照；aim、非零碰撞 morph 與其他未准入組合不得偷偷採近似或半批切回。以下原 200 人／120 Hz／60 秒與流暢門檻不變。

**2026-09-13 23:25 歷史結果：仍未流暢。** 已實作並驗證 private 換裝刷新合併，但同來源 full60 為 OFF 14.3713 FPS／ON 14.6699 FPS，末十秒都 3.8 FPS、P95 都約 333 ms；候選維持關閉。另已建立 test-only 原動畫速度界候選，各 252 個 idle／walk_slash 姿態範圍檢查沒有觀測違反，但 `admitted=false`、沒有正式剔除或 GPU 接入；數學及原歷史重播尚未完成。[實作、完整數據與未完成事項](output/site_combat_performance_20260913/recipe_refresh/README.md)

最新狀態摘要：GPU skinner 快照修後，男女各原 107 案＋5 個 mutation 案通過；正式路徑 `gpu_skinner` 仍為 null，尚未上線。
最新 full60 批量需求診斷 `215848` 為 13.3502 FPS／P95 350.165 ms／末十秒 2.6 FPS；它在快照修正前執行、且未注入 GPU，不能作為修後 GPU 場景 benchmark。
流暢門檻與整段隊伍取樣批次化仍未完成；以下各階段的精確性、同步成本與效能驗收條件維持原樣。

2026-09-13：依使用者「開始 GPU 批次規劃實作直到流暢」的新授權建立。本文件是接續實作與驗收計畫，不是 GPU 已上線或流暢已完成的證明。既有結果、失敗與各候選開關保留在 [SITE_COMBAT_PERFORMANCE.md](SITE_COMBAT_PERFORMANCE.md)。

## 目標與不變條件

保留原 200 人、同一 Site、原至多 1/120 秒共同動作步、完整連續命中、實際裝備／護甲／盾／徒手、疲勞、傷亡及物資守恆。不得靠減人、跳過屍體碰撞、降低頻率、捨棄時間、改傷害或放寬命中幾何達標。

- `TerrainLab` 仍是原共同時鐘與場景組裝入口；地圖仍由 `Node2D + Camera2D` 控制，3D 僅原隔離呈現／查詢用途。
- 人物身分、HP、格位、攻擊歷史、彈體與裝備仍屬原 Actor／TerrainArmy／SiteRuntime；GPU 不保存第二份權威人物或物品狀態。
- `TerrainWeaponCollision` 仍擁有精確幾何；新增 RenderingDevice 私有計算 helper 只接收原資料並返回計算結果，不是第二套碰撞或渲染框架。
- 原 raw GLB、原生動畫時間、骨架／morph、skin bind、部件順序與正式來源指紋不可偷換。男女 live owner、共享普通兵 Source、無法證明支援的狀態保留原 CPU 路徑。
- GPU 候選先關閉；正確性與包含傳輸／同步的淨效益分開驗收。局部快不等於整場流暢；失敗不回改原紀錄。

## 決策起點：已量到什麼

硬體診斷 `20260913_204950_738` 為 Godot 4.6.2 Mono、Forward+ D3D12、RTX 5060／i5-14400F、1400×900、VSync off；原戰鬥 891 幀／60.056419 現實秒，**14.836049 FPS、P95 330.861 ms、最後十秒 3.9 FPS**，`targets_met=false`。[原診斷與完整資料](output/site_combat_performance_20260913/gpu_cpu_diagnosis_204950/README.md)

戰鬥內部 19 筆外部取樣的整張 GPU 平均使用率為 **4.789%**，遊戲最忙執行緒平均約 **0.994 個邏輯核心**。這是約每 2.6 秒取樣、只涵蓋所列內部窗口的觀察，不是逐幀 GPU timestamp，也不是整台 CPU 99%；GPU 數值包含其他程序，不能推算「還能快幾倍」。

原 Lab 呼叫經過時間合計 **47.427748 秒／60.056419 秒窗口**，包含函式內等待，不是 OS 純 CPU busy time。證據支持先減少主要串行／同步工作；不支持「只提高 GPU 使用率便會流暢」。同場 `teams_sample=32.669281 s`、其內 `collect_geometry=17.492888 s`、Source sample／pose 等是巢狀計時，不能相加。

現有 Sprite2D 正常由 GPU 畫圖。瓶頸調查針對取得精確碰撞頂點、姿態与同步計算，不是把原 2D 場景換成另一個 3D 遊戲入口。

## 階段 1：原 Geometry 內的最小 GPU 蒙皮／投影切片

主控首先實作 Geometry 私有 RenderingDevice helper：網格靜態資料常駐 GPU，輸入仍是原 CPU 骨矩陣，候選只計算原頂點的蒙皮／投影。保持原呼叫順序；此階段**尚未**把 AnimationPlayer、骨架取樣或整段 `teams_sample` 搬到 GPU。

1. 常駐資料只包含原頂點、索引、權重、綁定與必要布局；沿實際 mesh／skin 生命周期建立、失效與釋放，不逐幀重讀 GLB 或雜湊大檔。開關關閉、RenderingDevice 不可用、資料不支援或失敗時明確回原路徑。
2. 每次使用原姿態、原 palette、相同原始頂點順序與投影輸入；有 morph 時不能忽略原修正或拿未變形頂點冒充。第一片未處理的 morph／非剛性／其他狀態須如實列出 CPU fallback 範圍。
3. 不先改凸包、膠囊、三角形覆蓋、接觸 fraction、排序與傷害。不得以 GPU hull／近似形狀取代尚未驗證的原演算法。
4. 明確測 shader 浮點運算順序、FMA／精度、矩陣布局、正負零、索引與結果順序；與原完整 CPU 路徑逐值／位元比較。不以 epsilon 放寬來隱藏不同碰撞結果；不一致則定位或保留 CPU。

### 第一片的收益門檻

逐 call 版本只用來量出 break-even，不預設適合上線。分開保存首次建立與暖機後結果，總成本必須包括：

`準備輸入 + 上傳 + dispatch + GPU執行 + 同步等待 + 回讀 + 原結果轉換`

GPU kernel 時間不能單獨和整段 CPU 時間相比。用相同原始資料、原順序交錯 A/B，記錄實際頂點／矩陣／bytes／call 數，以及中位數與尾延遲；測少量與較大工作包的淨成本，找出最小有利批量。若逐次同步反而更慢，保留結果與關閉候選，不宣稱已完成優化，也不在正式路徑強行啟用。

最小正確性矩陣沿既有男女／普通兵幾何 oracle：原實裝、缺裝再裝、四向、連續非圖集時間、aim、guard／parry、down／get-up、移動、剛性與非剛性、索引／多 surface／空結果、原 head 首次擬合。只有真正經過 GPU 的案例才列 GPU 覆蓋，fallback 不冒充 GPU 通過。

## 階段 2：按實測瓶頸擴至骨架／頂點批次

若階段 1 已證明精確且批量存在淨收益，再沿同一 helper 擴大工作包，而非建立每兵 rig：

- 先批次提交原多個 palette／mesh 工作；仍使用原 CPU 姿態來源，量出減少 dispatch／同步的收益。
- 若 CPU 原生骨架／morph 取樣仍占主要成本，再以原 raw tracks、插值／loop／長度、FK、skin bind 及原裝備資料，做 GPU 骨架／頂點批次候選。這是後續獨立正確性關卡，不由第一片 GPU 蒙皮 PASS 推定完成。
- 原 CPU 仍提供人物本步的精確時間／配裝／方向／aim；GPU 批次只產生可重建結果。不得將快照改為 GPU 權威狀態，或因批量不足偷偷量化時間／共用不相等姿態。
- 原 IK／瞄準、非零 morph、未被 clip 寫入的骨／morph 歷史若尚未證明等價，保留原路徑。只支援部分姿態時，測試須同時報支援率、fallback 次數及整體成本。

進入更大批次前，先用實際 200 人工作序列量出批量分布；合成大陣列吞吐量不能代替原遊戲可形成的批量。

## 階段 3：同一步收集、批次查詢、按原順序消費

原共同步已先前進人物，再收集接觸，最後處理 HP。可以沿此邊界保存有限的本步不可變工作紀錄，但不得把同步回呼改成「先回空命中、以後補傷害」。GPU 結果必須在**同一步完成結算前**可用，不允許跨到下一步套用舊結果。

最小紀錄包含原查詢序號、原 owner／人物索引、previous／current 頂點、位置／來源格、實際 attack profile 與所需 target 幾何；只存當步工作，不入存檔、不另持有 HP。

必須解決的原順序限制：

- Army `sample_combat` 收到 hits 立即更新 `unit.hits`、友軍／盾造成的 `blocked`、狀態及 `previous`。Actor 近戰還有 `_did_hit`、刺擊阻擋；同一人的下一筆 pending melee 是否查詢取決於上一筆。批次可預算純幾何，但結果消費仍依原 Actor→Army→人物索引與原 hits 順序，重查原 blocked／hit 去重，不能額外提交原本不會生效的封包。
- Actor 原流程是舊彈體移動→當步新發射→近戰。彈體接觸立即停止／移除，新發射扣原彈藥且下一步才開始飛行。第一個跨人批次可先保留彈體同步路徑；後續准入須另驗倒序彈體迴圈、首命中與地形阻擋。
- Source 目前交錯處理武器、目標身體與實際命中点護甲。任意按 clip／配裝重排可能改變首次 head fitting、原生 clip reset、未被動畫寫入的 morph／骨姿及 armor restore 歷史。須保存原首次幾何需求次序，或有完整原歷史對照證明的新取樣流程；不能因人物 HP 尚未變就推定所有查詢沒有副作用。
- Lab 仍用原 fraction 排序、近似同時群組與每群組攻擊者資格，保留互擊；不能用 GPU 完成順序取代原接觸順序。當步解除借用資料後，才走原生命、物資、供養、命令與家族結算。

跨人批次的最小验收為原小場景逐步 CPU/GPU 重播：完整人物列、每筆 ordered contacts／packets、previous、hits、blocked、HP／KO、彈體、裝備／物資、Source 骨／morph／head 首次擬合與結算邊界一致。通過後才進原 200 人；不能只用 collector probe 代替真命中流程。

## 階段 4：原 200 人、60 秒實戰驗收

沿既有 `site_army_combat_realtime_test.gd`，不降低原門檻：

| 必要項目 | 原門檻 |
| --- | --- |
| 原生現實量測窗口 | 完整 60 秒；不是手動快速推進或短測 |
| 平均 FPS | ≥30 |
| P95 畫面間隔 | ≤33.334 ms |
| 六個完整十秒窗口 | 每段皆 ≥30 FPS，包含最後十秒 |
| 最大停頓 | ≤1,000 ms |
| 原 input／wall | >0.95 且 ≤1.05；另報 actual action／wall，不靠減少接收時間達標 |
| 時間對帳 | 不丟已接收時間；保留原 `1e-5` 秒誤差守衛與現行時鐘策略 |
| 自然連續交戰 | ≥55 動作秒，且觀察到原有效命中 |
| 人物／資產 | 原 200 身分、混合實装 fixture、1,018 件原物品／cargo 守恆 |
| 其他 | 無意外暫停／Node 增長；原處理、HUD、交戰 BUSY 安全保存及來源指紋不變 |

死亡、失能、補位、倒地遺物與可搜刮物資照原流程保留，不復活或改 HP 製造工作量。60 FPS 仍是更佳目標，但 30 FPS 與所有必需項同時通過之前不得稱流暢完成。

先保留候選全關的同來源對照，再分別量 GPU 切片與批次配置；記錄來源 SHA、實際開關、renderer／解析度、輸入與動作秒、每階段工作量和六段尾延遲。原生 delta 不同會改變實際進度及工作量，CPU／動作秒正規化也不能冒充完全等量重播。除了數值驗收，須檢視原場景近景／交戰／倒地／缺裝畫面；靜態截圖不能代替動態流暢證據。

## 執行、回退與目前狀態

- 每次驗證使用未修改的 canonical bounded helper；測試有明確內部 deadline，單一 Godot runner，長測保持原生 session 監看。重要原四份紀錄另存 named output、核 SHA，保留全部 FAIL／timeout；不更改 100 筆保留政策。
- 不同 GPU／driver 的可用性與數值差異明確 guard；不支援者保留原 CPU。GPU buffer／RID 釋放與來源替換必驗，不以常駐資源洩漏換取短測收益。
- 任一階段未達正確性或淨效益，保留關閉與實測原因，調整同 owner 內的最小切片；不得靠弱化驗收直接上線。
- 建立計畫時，階段 1 尚未取得 PASS；後續實測按下節追加。跨人批次與原 200 人流暢驗收仍未完成，不由局部 kernel PASS 推定通過。

## 2026-09-13 21:28 更新：蒙皮切片正確，但不是主要熱點

原正式 CPU 路徑診斷 `20260913_212240_618`：helper PASS／exit 0／92.373 秒，僅代表量測完成。原 901 幀／60.189816 現實秒為 **14.969310 FPS、P95 323.472 ms、最後十秒 3.8 FPS**，`targets_met=false`；原 input／wall 為 0.604200，實際動作 36.366667 秒。1,018 件物品守恆、Node 維持 4,781；本次沒有把 GPU 注入正式戰鬥。[完整原始量測](output/site_army_combat_realtime/62f16ae78dee72ee/mixed_equipment_full60_weapon_filter_skinning_profile/1789305765_3845095/measurements.json)

五個原 Geometry 的 `scalar_usec` 合計 **414,135 us**，已包含在 `posed_usec=1,572,828 us`，不可再相加。其後獨立計時的 `projection_usec=1,446,454 us`，因此蒙皮完整函式加投影共 **3.019282 秒／Lab 47.366810 秒＝6.3743%**；`morph_calls=0`，全部 `gpu_surfaces=0`。這不是整場骨架／姿態取樣的成本，也不能把 Source／collector 的巢狀時間算進蒙皮。就本次原工作量而言，即使這兩小段免費也無法獨自補足流暢差距；GPU 蒙皮開關不預設啟用。

強化定向 GPU 驗證均在 RTX 5060／D3D12 通過，沒有放寬浮點位元對照：

| 原紀錄 | helper | 真正覆蓋與界線 |
| --- | --- | --- |
| `20260913_212742_381` 男 | PASS／7.187 秒 | 107 案、0 頂點差異；52 案強制蒙皮逐案驗 dispatch 與頂點數，52 案原 `native_rigid=true` 路徑對照，另 3 個批量；原生路徑其中 48 案為 CPU-only，不列 GPU 覆蓋。 |
| `20260913_212811_188` 女 | PASS／7.257 秒 | 同樣 107 案、0 頂點差異及 48 案 CPU-only；保留女體自己的原 palette／頂點，未套男體結果。 |

[男體完整資料](output/site_combat_gpu/skinning/body0_1789306069_1478107/measurements.json)、[女體完整資料](output/site_combat_gpu/skinning/body1_1789306098_1408570/measurements.json) 含逐案路徑、GPU 計數、合法長度但越界的 binding／零權重、257 jobs、異長 palette、NaN／±Inf、矩陣與輸出上限拒絕，以及釋放後空 surface、原 uniform set 失效、owner RID 無效、device 已釋放、重複 dispose 檢查。兩組均 `gpu_fallbacks=0`；男／女總 GPU batch 數為 107／111，但不可與 107 個比較案例混稱一對一。PASS 在清理驗證後才寫出。

最新合成批量 32 jobs，每個計時 pass 連做兩次：男 CPU 18,680／18,919 us、GPU 3,768／3,505 us（各兩筆中位數之比 **5.170×**）；女 CPU 18,232／18,320 us、GPU 4,576／4,547 us（**4.007×**）。這是已備妥 palette 的重複工作包、843／834 頂點每 job，含該 helper 的上傳／同步／回讀，但不是正式 native-rigid 路徑、不是 200 人可形成批量的證明，更不是 FPS 倍率；不能用概略「4.7×」替代這次男女原值。目前 kernel 僅做 3D 蒙皮，2D 投影與 CPU 姿態／morph 未搬移。

首試 `20260913_211636_451` 仍是 **FAIL**：雖 exit 0，PREDELETE 的 `_notification` 呼叫已失效 `dispose` 產生 SCRIPT ERROR，不能由後續 PASS 抹除。上述四批各自的原 `result.json/stdout.log/stderr.log/combined.log` 已複製至 [永久驗證封存](output/site_combat_gpu/verification/README.md)，16 檔逐一核 SHA-256 與位元組數相等；原檔及舊報告未覆寫。

下一步改查原完整函式的 **self time** 與實際批次邊界，區分 Source pose、選裝／動畫同步、各種查詢包裝及 collector 自身成本，再決定可涵蓋主要工作量的最小批次切片；不可因 kernel 算術通過就繼續搬移小熱點。主控進行中的 `--debug --profiling` full60 尚未在本更新取得結果。其後仍須先通過原順序／歷史精確對照、包含傳輸同步的淨收益，最後達到原 30 FPS／P95／尾段／動作時間門檻。本次僅更新文件與封存，沒有執行 Godot 或改程式／測試。

## 2026-09-13 21:52 更新：原生 profiler 與兩個未採用切片

### 原生 script profiler：量測完成，不是流暢或加速驗收

`20260913_213503_588` helper PASS／exit 0／90.705 秒；開啟原生 script profiler 的診斷為 753 幀／60.365951 秒，**12.473919 FPS、P95 389.718 ms、最後十秒 3.1 FPS**。實際動作 32.703474 秒，action／wall 0.541754，Lab 計時 48.379741 秒，`targets_met=false`；原 200 個 ID／1,018 件物品、來源指紋與無 Node 成長守衛通過，20 人死亡並完成原遺物處理。這是帶 profiler 負擔的診斷，不能直接與未開 profiler 的 FPS 作優化 A/B。[本次完整量測](output/site_army_combat_realtime/e2e9f221ec6ea6f3/mixed_equipment_full60_weapon_filter_skinning_profile_script_profile_diagnostic/1789306507_3064865/measurements.json)

原生 accumulated 表可定位 caller，但 **不能把所有 self 或 total 列加總**：例如 `RealtimeLab._advance_combat` 與 `ObservedLab._advance_combat` 的 self 分別是 47.830600／47.821590 秒，兩者包住同一次 `super` 呼叫，並非兩份 CPU 工作；表頭 `ACCUMULATED total=268.962677` 也不是本場額外耗時。以下只列原 production 函式的原表值供追查，各列仍可能互相包含：

| 原函式 | Calls | total 秒 | self 秒 |
| --- | ---: | ---: | ---: |
| `TerrainArmy.sample_combat` | 8,580 | 32.837658 | 0.478891 |
| `TerrainLab._collect_army_contacts` | 50,167 | 23.370171 | 3.540025 |
| `Source._sample` | 178,125 | 11.817891 | 0.446745 |
| `Source._pose` | 15,549 | 5.805709 | 1.168761 |
| `TerrainTestCharacter._advance_combat_pose` | 8,580 | 3.437956 | 3.307632 |

完整函式表保留於 [原生 profiler stdout](output/site_combat_gpu/verification/20260913_213503_588/stdout.log)。原 debug 警告亦保留，未把本次 helper PASS 稱為零警告掃描。下一步仍需分離原生動畫／渲染同步等真實成本，不能把 wrapper 的重複 self 變成移植收益估算。

### 地面索引：正確性通過，常見批量更慢，已退回 test-only

`20260913_214245_883` headless PASS／exit 0／2.154 秒，5,000 個候選索引與原順序完全相同。每組 100 批、ABBA 兩次原路徑與兩次候選計時如下；這是局部微秒數，不是 FPS：

| 每步 queries | 原全掃 us（兩次） | 索引 us（兩次） |
| ---: | ---: | ---: |
| 1 | 1,374／1,290 | 1,964／1,446 |
| 4 | 5,178／5,159 | 8,172／8,077 |
| 16 | 21,971／21,634 | 24,332／23,303 |
| 64 | 85,976／86,929 | 80,324／80,952 |

1／4／16 次均更慢，64 次才約省 6.7%；本次實戰 50,167 queries／4,290 steps 約 11.69 次／步，沒有支持採用的收益證據。完整候選方法已移入測試自己的 `Probe extends TerrainLab`；Lab 與 realtime 的 ground-index flag、CLI、報告與 collector 接入均已移除，沒有留下未採用的 production 分支。[原始微測結果](output/site_combat_gpu/verification/20260913_214245_883/stdout.log) 保留 PASS 的正確性證據與負收益，不另捏造 JSON 報告；原 stderr 憑證訊息也保留。

### 原 Actor 原地常值 morph 壓縮：男女位元對照通過，mixed 收益不穩定

check-only `20260913_214316_022` PASS／2.972 秒。隨後原男體 `20260913_214415_551` PASS／35.669 秒、原女體 `20260913_214905_951` PASS／35.414 秒；各為同一 Actor 的 AABB 歷史，45 組完整骨骼／可見與隱藏 morph 位元對照、9 組原幾何子集，最大差異 0。原 Actor／AnimationPlayer／Skeleton／Animation／Library instance 均保留；只改該測試程序內原生 runtime-generated Animation 的合法正零重複 keys，不複製／重掛資源、不新增 rig、不寫 GLB 或正式資產。所有 tracks 與非壓縮 keys 保留；記憶體內原資源刻意已改，不能稱為 `original_resources_unchanged`。

| 身體 | Clips／tracks | Keys 原→候選 | 壓縮 tracks | 同 idle seek 中位 us | mixed 全段中位 us |
| --- | --- | --- | ---: | --- | --- |
| 男 | 59／44,221 | 2,720,390→465,506 | 37,672 | 55,780→44,159（−20.83%） | 1,855,651.5→1,918,015.5（+3.36%，更慢） |
| 女 | 57／43,847 | 2,685,009→435,293 | 37,672 | 53,580→41,699.5（−22.17%） | 1,899,899.5→1,856,362（−2.29%） |

每個數值取四次、每次 200 seeks 的中位數；mixed 含 99 次 clip 切換與原 select／seek 整段成本，不能把同 idle 的兩成改善套到 mixed 或 FPS。男／女原地壓縮加 audit 分別 2,370,072／2,684,989 us，不是純 compactor 計時。[男體原始 JSON](output/site_combat_performance_20260913/actor_constant_morph/1789307090_35228407_body0_in_place_test/measurements.json)、[女體原始 JSON](output/site_combat_performance_20260913/actor_constant_morph/1789307381_35012547_body1_in_place_test/measurements.json)

本次只证明特定原生 Actor 歷史的精確性，尚未驗 production 初始化邊界、Source 借用已改 Actor 資源時的原始 oracle 隔離，亦未驗整場淨收益。舊 copy-only／clone 浮點 FAIL 不被此新 in-place PASS 覆蓋。**Actor in-place 與 GPU 蒙皮均未啟用 production，ground-index 已拒絕；整案仍未流暢，原 30 FPS／P95／尾段／動作時間門檻不降。**

上述四個重要 run 各四檔已追加 [永久封存清單](output/site_combat_gpu/verification/README.md)，新增 16 檔／3,780,772 bytes 逐一核對來源與副本 SHA-256、大小相等，沒有覆寫不同內容或執行 Godot。本節僅追加文件與證據，舊結果完整保留。

後續短註：索引搬到 test-only Probe 後，`20260913_215649_245` headless PASS／2.146 秒；這只確認移除 production 接入後測試仍成立，不改變拒絕採用的收益結論。新 `--gpu-batch-profile` 診斷首個 check-only `20260913_215812_470` 因 `cached` 型別無法推斷而 FAIL／exit 1／0.759 秒；主控補明確 int 後，`20260913_215830_491` check-only PASS／1.694 秒，原 FAIL 保留。該新診斷只觀察每個原 step 的 `true_pose_evaluations` 差與末尾 `_poses.size` 分布，計數含姿態 restore，**不等於可批次 jobs 數**。其 full60 此時仍在執行，沒有在本次追加中預先登錄結果。

## 2026-09-13 後續：同一步原生姿態需求已量測，尚非 GPU 批次證明

上節待完成的 `20260913_215848_694` 現已取得 helper PASS／exit 0／88.616 秒，僅表示完整診斷結束。802 幀／60.073988 現實秒為 **13.350204 FPS、P95 350.165 ms、最後十秒 2.6 FPS**；原動作時間 32.567483 秒，action／wall 0.542123，Lab 48.968473 秒，`targets_met=false`。六個完整十秒區間為 15.3／21.9／13.2／21.0／6.1／2.6 FPS。本次未開上節的原生 script profiler，也未開 skinning-profile，不能和上節宣稱單變因回歸或加速。[原始完整量測](output/site_army_combat_realtime/7c0b361dfa7fb285/mixed_equipment_full60_weapon_filter_gpu_batch_profile/1789307931_1888112/measurements.json)

`original_step_pose_demand` 沿原 common step 只讀統計，沒有 GPU dispatch、重新排序或跨步合併：

| 原生姿態求值需求 | 實測 |
| --- | ---: |
| 原 steps | 4,404 |
| 原生 pose evaluations（含 restore） | 17,106 |
| 零求值 steps | 2,376（53.950954%） |
| 非零 steps | 2,028；每步平均 8.434911 次 |
| 恰好 6 次的 steps | 1,201 |
| 單步最大次數 | 22 |
| 所有 steps 平均 | 3.884196 次 |

原末步 cache 數是另一個量：零項 2,378 步、6 項 1,208 步、最大 21 項，不等同上表。求值計數包含原姿態 restore；cache 數不包含 terminal-only 返回，且可能經容量清除。因此 **原生 pose 需求不等於使用相同 surface、相同 palette 格式而可批次的 GPU 工作包**，也不能證明這些查詢可改變順序。約 54% 步沒有新求值，其餘平均約 8.435 次；不能直接套用先前 32 個相同 surface 合成 jobs 的 GPU timing，更不能由 22 次最大值推論 22 個合法同批工作包。下一步若做批次，必須在原 caller 邊界量出實際可合併工作、傳輸／同步淨成本與原歷史等價，原 120 Hz／人數／命中規則不變。

另主控獨立審查發現 GPU helper 的 PackedArray 快照別名問題，目前仍在修正與驗證，**未上線，也未在此登錄修復 PASS**；先前男女 GPU 局部 PASS 不能充當該新增 mutation 邊界的證據。GPU 計畫仍未完成流暢驗收，所有原門檻不降。

本 run 的四份原紀錄已加入 [永久封存](output/site_combat_gpu/verification/README.md)：4 檔／89,509 bytes，SHA-256 與大小逐一相等，包含空 stderr；未覆寫原 measurement／舊紀錄，未在本文件任務執行 Godot。

## 2026-09-13 22:06 後續：GPU resident 快照別名已修驗，仍未上線

新增 mutation 回歸先在原 helper 上重現真問題：`20260913_220514_240` **FAIL／exit 1／7.265 秒**。雖原 107 個幾何比較仍零差異，第一個 `vertex` mutation 就得到 `resident_snapshot_unchanged=false`：呼叫者修改 PackedArray，連 resident metadata 也被別名改動，已上傳 buffer 卻仍是舊內容。測試在不安全的 mutation dispatch 前停止，該 mutation 的 dispatches／vertices 都是 0；不是「整個 run 從未 dispatch」。清理仍完整通過，原 FAIL 永久保留。[修前失敗 JSON](output/site_combat_gpu/skinning/body0_1789308321_1424804/measurements.json)

主控在原 `terrain_gpu_skinner.gd` resident 紀錄將 vertices／bones／weights 三個 PackedArray 改成各自 `duplicate()` 快照，保持原 buffer 與 dispatch 流程，不改正式動畫或權威 HP。修後 helper SHA-256 為 `de31bb8cee7e91a097d955e4a7143e2148c6706d6ff04a68c3dc5d899805f4c0`。本文件工作只讀此修改與報告，沒有另行改程式或執行 Godot。

| 修後原紀錄 | helper | 精確比較與新增邊界 |
| --- | --- | --- |
| `20260913_220559_118` 男 | PASS／exit 0／7.574 秒 | 原 107 cases／0 頂點差异；新增 vertex、bone_index、weight、grow、shrink 五案全部 PASS。 |
| `20260913_220622_600` 女 | PASS／exit 0／7.212 秒 | 同樣原 107 cases／0 頂點差异，五個 mutation cases 全部 PASS，保留女體自己的原輸入。 |

五案各自先證原 resident 快照不被呼叫者改動，再重新註冊真輸入、各 dispatch 一次，以原 CPU 計算比較所有輸出頂點位元；每組五次 dispatch／六個頂點，皆 `exact_vertex_bits=true`。原 typed input guards、逐案 dispatch 與 native CPU-only 分界仍保留。清理驗證在 PASS 前完成：空 surface、舊 uniform sets 失效、owner RIDs 無效、device null／freed、dispose 兩次；男／女舊 uniform sets 分別 11／10 個。[男體修後 JSON](output/site_combat_gpu/skinning/body0_1789308366_1486523/measurements.json)、[女體修後 JSON](output/site_combat_gpu/skinning/body1_1789308389_1397793/measurements.json)

修後合成 32 jobs 的本批原值是男 CPU 18,937／20,130 us、GPU 4,060／3,630 us；女 CPU 17,907／18,208 us、GPU 4,743／4,583 us。這些才是修後報告，不能沿用上節歷史 32-job 倍率；同樣只是已備 palette、重複 surface 的局部微測，不是原同一步 32 個可批次工作，更不是正式 FPS 或上線驗收。

主控另已人工檢視 `215848` 的 [02_final.png](output/site_army_combat_realtime/7c0b361dfa7fb285/mixed_equipment_full60_weapon_filter_gpu_batch_profile/1789307931_1888112/02_final.png)：原隊伍、倒地遺物與 HUD 可見。這是一張靜態畫面，不能證明動態順暢；該場 `targets_met=false` 不變。

**階段 2 仍未完成。** 原 CPU 工作量已證 GPU skinning alone 只涵蓋小熱點；下一個有意義的切片需沿整段隊伍取樣把實際資料整理成可批次工作，而非只增加合成 jobs。須保留原 120 Hz、全部 200 人、Source 歷史／first-fit 與同步返回的 hit／blocked 順序，先證實可批次性，再量傳輸、同步與回讀後的整段淨成本。GPU helper 的局部正確性修復不等於正式戰鬥已使用 GPU；目前未上線，也未達原 30 FPS／P95／尾段／action-wall 門檻。

本次三個 run 各四份原始紀錄已追加 [永久封存清單](output/site_combat_gpu/verification/README.md)，12 檔／4,554 bytes 逐一核對來源與副本 SHA-256、大小相同，空 stderr 亦保留。原失敗、舊 PASS 與所有 measurement 不覆寫。
