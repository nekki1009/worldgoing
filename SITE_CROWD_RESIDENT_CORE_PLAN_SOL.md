# Worldgoing GPU Resident Crowd — 歷史獨立 3D 支線

歷史日期：2026-09-25。本文件保存當時附件學習後的獨立 3D P1a–P1d 設計，並非現行施工指令。**正式 5,000 人的唯一執行入口是 [close 修訂計畫 R0–R4](SITE_CROWD_GPU_OPTIMIZATION_PLAN_SOL.md)，不得依下方歷史「下一包／等待實作」措辭轉去跑獨立 benchmark。** 本次僅補上文件狀態，不改其歷史技術內容。

完整 A–H 學習報告、呼叫鏈、證據等級、API 核對見 [SITE_CROWD_GPU_LEARNING_REVIEW.md](SITE_CROWD_GPU_LEARNING_REVIEW.md)。此前完整 native 核心方案保留為 [歷史／後續正式整合候選](output/site_crowd_learning_20260925/resident_core_plan_before_learning.md)，不再是本次 Phase 1 前置。

## 1. 本次修訂的決策

**先在現有 3D Crowd 路徑，證明「CPU Formation Command → GPU 直接產生 MultiMesh instance data」能取消一般兵每幀 CPU Transform preparation。保留 Formation／Terrain／Special 的責任，第一包不重寫戰鬥、尋路、動畫、裝備及 promotion。**

撤回上一版將完整 ordinary native 狀態機、查詢、交鋒和結算同時列入首包的安排。那個方向仍可解決正式 TerrainLab 的已量測模擬問題，但不能拿來取代這次更小的 GPU 呈現驗證。

本計畫分清三個範圍：

- **已存在的 3D 實驗路徑：**`BattleCrowdSimulation`、`CrowdRenderer3D`、FormationSpace／Promotion scene。以此作本次 Phase 1 落點，沿用原檔案及角色資源。
- **已存在的正式遊戲：**`project.godot` 仍進入 Node2D `TerrainLab.tscn`，普通兵是 2D atlas／MultiMesh。正式萬人模擬74.46%、8.695 FPS的舊量測只適用這條路徑。
- **附件的目標架構：**3D GPU Crowd、每Formation最多100含隊長／幹部、Near預算64、GPU局部移動。不是目前全數已實作；本輪不擅改正式main scene，也不把舊2D實作當成禁止研究3D的理由。

不引入「封閉式物資循環、所有資源追溯、不可生成單位、所有物件保存完整歷史」等舊專案前提。既有正式功能暫不改；prototype不需要先移植物資／家庭／社會系統。

## 2. 已學到的現況與必須修正的假設

### 2.1 已經有更強的CPU基線

`CURRENT_PER_INSTANCE` 會逐兵更新／打包Transform；但 `FORMATION_PARENT_TRANSFORM` 已用每Formation父節點變換，slot Transform只在初始化或spacing變更時建立。選此路徑時controller會關閉全軍world-position cache。

因此比較必須是：

1. A：原 per-instance CPU。
2. B：既有 Formation parent CPU。
3. C：新 GPU Formation Command。

只打敗A不構成新增GPU backend的性能理由。C若慢於B，保留B為預設，記錄原因；GPU的後續價值要由獨立局部移動／動態slots和resident資料流證明，不預先承諾FPS。

### 2.2 人數、Near與能力邊界

- 現有總人數10,000，Near64是其中promotion：9,936 proxies＋64 Near＝10,000。若要10,000普通兵外加64獨立角色，另做10,064 fixture。
- 初期Near預算固定64；舊pool容量128／256不代表需求變成256。分開記錄allocated、active、visible。
- simulation固定100×100，active setter至少100且按100取整，上限10k。0／1用renderer-level probe；25k需擴測試容量後才算實測。
- 目前3D Formation只有center／facing／destination等，沒有正式隊長／幹部、動態columns、平台／corridor。10×10↔3×34先作command輸入契約probe，不冒稱既有山地玩法已接上。
- 既有shader是程序頂點動畫，custom為`phase,state,active,variant`。Phase1保持ABI、原shader和Near骨架；BAT／VAT另期。
- 附件25–30ms原始報告本輪未定位；不能與較早另一套`.benchmarks/site_formation`來源混用，也不能視為本輪成績。

## 3. Phase 1 單一目標與資料權威

### 3.1 目標資料流

```text
原 CPU Formation／roster／命令
    ├─ 100份左右的 FormationCommand（10k／100）
    ├─ 初始化的 AgentDescriptor／穩定ID映射
    └─ 有變更時的 animation custom／Near mask事件
                         ↓
render thread：先提交commands／dirty events
                         ↓
Compute：閉式計算slot位置＋朝向
         直接寫3D MultiMesh instance output
         寫indirect command count
                         ↓
原3D mesh／material／Special pool呈現
```

GPU Phase1的position是CPU Formation及slot的**呈現投影**，不是新的戰鬥權威；沒有獨立velocity積分或碰撞修正。因此CPU可只為最多64個Near及policy候選做少量相同公式查詢，不需要讀回GPU。

一般兵renderer不能再經過legacy全軍world cache、LOD/chunk重建及per-person Transform pack後才dispatch。這階段仍保留原simulation逐人動畫與promotion政策工作，清楚量其成本；不宣稱所有O(N)腳本均已移除。

### 3.2 建議ABI：分開資料用途

先凍結一份CPU／shader共享layout及版本；這是資料契約，不是要求照抄附件struct。

- **FormationCommand，建議64B：**三個vec4描述center+spacing、right axis、local-Z axis；一個uvec4描述columns、rows、valid slot span、flags。整數不要透過float存StableAgentID。simulation/render epoch與command generation放批次header，不每人重複傳。
- **AgentDescriptor，建議32B起：**一個uvec4保留穩定ID的低／高32bits、formation index、slot index；一個vec4保留現有custom ABI。GPU內部dense slot另有generation／映射表，不能把output index當永久ID。是否需額外欄位以真正reader為準，不先加入HP／社會資料。
- **3D MultiMesh output：**無color、有custom時固定16 floats／64B，其中12為row-major Transform3D，後4沿現有custom ABI。AgentDescriptor與output是不同buffer，不因大小巧合共用結構。
- **Indirect command：**本機4.7.2官方來源為每surface 5 uint／20B；只寫count欄位，保留引擎初始化的geometry參數。Phase1要求mesh只有一個surface。
- commands、descriptors、output、engine draw arguments的capacity、stride、count單獨記錄；加入schema/layout斷言与非對稱basis＋translation probe。

10k／100個Formation時，純command量約6.4KB／更新；這只是建議ABI的理論payload，尚不含事件、對齊／driver成本，不是量測帶寬。初始化AgentDescriptor與output為O(N)合理，常態不傳N個完整Transform。

### 3.3 座標、槽位與數量

沿用現有**Formation中心pivot**，不要直接套附件的前排中心；local X／Z軸跟現有Basis一致。command及compute output採benchmark/renderer局部座標，RS visual instance只套renderer的global transform，不再額外套一次Formation父變換；用非identity父變換驗證沒有重複平移。3×34的最後一行只用100個有效slot，不能畫出102人。改寬測試先驗公式與ID穩定，平滑收斂留Phase2。

第一版沿既有Formation batches的分組配置，但GPU backend用純RS MultiMesh＋visual instance持有低階呈現，固定capacity與保守bounds，不先重寫整套chunk／LOD。AABB與output同採renderer-local且涵蓋該批預定移動範圍；output已含Formation中心，不能複製舊formation-local小框。commands以同一frame packet提交；在render thread批次處理，記錄實際dispatch／draw數，不替每人排callback。若每Formation一個output RID導致100次dispatch，照實量測，不假裝單次dispatch；批次整併需由證據支持。

必須分列：

- `capacity`：配置可容纳slot。
- `valid_slot_span`：尚未compaction時需要提交的有效索引範圍。
- `alive_count`、`proxy_active_count`、`near_active_count`。
- `visible_count`：實際相機可見，不能拿active充當同屏。
- 後續地形的`platform_capacity`及`queue_count`，不參與錯誤裁人。

promotion holes先沿用原active mask。**不能把indirect count直接寫成未compact的proxy人數**，否则中間被遮住的slot會使末端活人被裁掉。此階段count控制span、mask控制proxy；仍會處理孔洞vertices，後期compaction才消除。indirect count能力用無洞0／1／65等probe獨立證明。

### 3.4 GPU寫者與Near邊界

CPU初始化後，該backend的output只由GPU寫；CPU的`set_buffer`、per-instance setter、visible-count setter不可在每幀覆寫。少量custom／mask事件寫入descriptor，再由GPU更新output，不逐兵重傳transform。

Phase1保留既有pool／policy。CPU知道的ID遮罩在同一committed render版本生效；只有對應Near成功ready時才隱藏proxy，失敗保留proxy。避免重載／切backend有一幀雙身或空洞；不能把render callback已enqueue當GPU已完成。

Phase2一旦GPU有獨立局部位移，CPU Formation公式就不再是準確位置。**bounded selected-agent query／promotion交接與fallback checkpoint必須在Phase2啟用該能力以前完成，不能拖到Phase7。**

## 4. Phase 1 最小檔案範圍

預計新增三個benchmark範圍檔案：

- `scripts/benchmark/3d_crowd/crowd_gpu_formation_writer.gd`：自有RS MultiMesh／visual instance、main RD資源、immutable command packet、render-thread排程、失敗／teardown；沿用原World3D與camera。
- `scripts/benchmark/3d_crowd/crowd_gpu_formation.glsl`：單一direct Transform producer及count写入，不含戰鬥／grid／BAT。
- `scripts/benchmark/3d_crowd/crowd_gpu_formation_contract_test.gd`：layout、indirect實際draw、邊界數量、bounds／重載測試。

預計修改：

- `crowd_renderer_3d.gd`：新增GPU mode與metrics，沿用mesh／shader／mask；不走legacy全軍prepare。
- `formation_render_batch.gd`：保留原B路徑，首包預設不改。4.7.2的MultiMesh Resource沒有use_indirect setter且有自己的count快取；不要直接對其RID重配再假定Resource同步。GPU候選使用自有純RS呈現資源，不用`set_base`混搭陳舊Resource。
- `crowd_promotion_benchmark_controller.gd`：mode選擇、world-cache policy、mask橋接；不改選人算法。
- `formation_space_crowd_benchmark_runner.gd`：三路比較、raw JSON、wall FPS、指紋、實際可見人數、nested timing scope。
- 既有`formation_space_crowd_contract_test.gd`只有新接點需要時增測；不重寫已通過的parent契約。

不修改正式入口、TerrainArmy/native combat、正式Formation planner、地形、save schema、裝備資產及Special骨架。場景沿用FormationSpace，不新增一個「看似正式」的替代戰場。

## 5. Phase 1 內部施工順序

### P1a：本機3D API與生命期探針

沿現有main RD Canvas writer／probe重用排程與清理經驗，但換成**真正3D／16-float／indirect**測例。現有Canvas成功不代表此步成功。

1. 先確認實際Godot executable／hash、renderer／driver、六個API綁定。專案SDK與保存的API dump是4.7.2，但本輪未啟動引擎核實當次binary。
2. backend建立fresh RS MultiMesh RID→固定capacity的3D＋custom＋indirect allocation→單surface mesh→conservative custom AABB→取得borrowed output/command RID→compute bindings與有效資料/count→RS visual instance掛入既有World3D scenario。首次可見前完成有效初始化。backend保留Mesh／Material Resource強引用，並用`instance_geometry_set_material_override`真正將原材質綁至RS instance，LOD换材質也同步；只保留引用不會自動帶入Node原有override。不要經MultiMesh Resource的count setter，也不借allocate early-return漏洞同步快取。
3. 固定capacity測0/1/65/100；GPU改count後從畫面／離線diagnostic證明draw改變，不能用CPU getter代替GPU證據。
4. count=0只清count，不每幀重建allocation、不dispatch 0 groups。一般shader寫入有index/capacity守衛。
5. 明列TAA、motion vectors、physics interpolation設定與buffer offset；先在受控fixture驗清楚，不能為成功修改全專案畫質。
6. disable/re-enable、resize、mesh替換、reload、exit含pending callback；檢查RID與uniform失效／重取generation、無重複free。第一版容量／mesh變更建立新的RS MultiMesh及bindings再切換，不假設原地resize保留borrowed RID。同步scenario、global transform、visibility/layer與shadow，World3D切換解除舊scenario。

若API只在官方source成立而本機失敗，保留精確錯誤；不偷退CPU count仍宣稱GPU indirect通過。

### P1b：Formation commands直接output

初始化descriptor後只更新commands與真dirty事件；保持rigid-slot等價公式。先1個Formation，後100個；同CPU reference核對translation、朝向、mask／custom與count。

給GPU backend加明確 mode；fallback依失敗原因回既有parent路徑，必要時舊per-instance，不能無聲回退卻仍貼GPU標籤。Phase1 CPU仍權威，可一致重建，不需全軍readback。

### P1c：Near64、動態shape輸入與同屏

接原Near mask與相同policy／pool，固定64預算。試0/64、promotion失敗、同ID多次切換、reload／mode toggle；避免把原影子、骨架或socket成本偷偷關閉製造收益。

10×10↔3×34用probe command加CPU oracle驗證，按中心pivot、slot ID及valid100；它不是修改正式mountain planner。場景畫面測max-visible與一般視野兩種，報10k實際可見及9,936＋64守恆。

### P1d：三路量測與採用決策

先同seed、同command trace、Near64設定和camera確保可比，再量A/B/C。**核心比較固定同一mesh／material／LOD且三路每幀更新Transform輸出**：legacy按逐兵LOD且FAR每3幀提交，parent按Formation中心LOD且每幀更新父變換，原runner預設不自動公平。另列保留各路原LOD政策的端到端case，兩種結果分開報。採用候選／最佳現有路徑做交錯ABBA，每輪暖機後至少60秒、獨立reset；probe／截圖／readback不混入無探針數據。

C能力通過但慢於B：保持B預設，標為GPU能力原型完成／性能採用未過，不稱優化成功。查明剩餘成本再決定Phase2，不為GPU名稱反覆加無關cache。

## 6. 同步、資源與錯誤契約

- main RD操作走render thread；主線先形成不可变command packet，包含scene generation／frame version。callback檢查generation，不能持有已queue_free節點再取其狀態。
- uploads在compute/draw list外；有依賴的compute pass用barrier。主RD不调用submit/sync；`full_barrier`在此版本不是有效補救。compute→Canvas／3D draw的同frame依賴由實際probe驗。
- 自有descriptor／command buffers、uniforms、shader／pipeline由backend釋放；借用MultiMesh output／command RID不自行RD free。GPU backend的RS MultiMesh／visual instance依RS ownership釋放一次，Mesh／Material強引用留到資源停用完成；fallback的MultiMesh Resource仍由原Node/Resource管理。
- instance count／格式／mesh／motion-vector重配置可能替換底層buffer，需重取borrowed handles並重建uniform；RID非空不等於資源仍有效。
- 先停止新提交、使舊generation失效，再於安全render-thread順序釋放自有資源。teardown不全量GPU readback。
- capability／compile／allocation／RID invalid／bounds錯誤有機讀原因，fallback數與人數可見；資料越界／資源失效不能當可忽略warning。

## 7. Phase 1 驗收

### 功能與架構

- 單surface crowd mesh、64B output ABI、GPU直接寫instance buffer、GPU count有實際畫面證據。
- 暖機後一般兵每幀CPU world-position cache updates、Basis/Transform constructions、instance-transform setters與完整Transform uploads＝0；一般兵正常frame readback＝0。
- 允許初始化／改配置的O(N)工作，必須單列；custom/animation事件E可能同時很多人改變，不預設永遠E≪N。Near64有界Transform與socket成本另列，不混入ordinary gate。
- 不新增每普通兵Node／Skeleton／Animator／NavAgent／Collider／script。穩定ID不隨render index、Near slot或後期LOD compaction改變。
- active_count 0、1、65、100、10000；非workgroup整倍數；靜止、直線、90度、10×10↔3×34；相機進出、視窗切換、pause/resume、mode toggle、reload、exit均驗。
- 完整10k可見case，以及原有一般视野case都留存截圖與counts；不可只把active=10000當萬人同屏證據。

### 正確性／畫面

Phase1 CPU Formation／人物資料不變，核對ID與state snapshot；相同command版本的GPU輸出對CPU公式oracle。先凍結非對稱矩陣、0/90度、正負translation、100有效slots等確定案例，離線讀回不得計入性能。

新3D producer可能有float32/FMA差異，先明訂數值驗收：受控±192m測試空間的位置誤差≤0.0001m、朝向誤差≤0.0001rad，另檢查矩陣軸向、custom資料與count精確相同。這是新3D原型的預定容差，不是放寬正式TerrainLab已有RGBA oracle；超出不得以「看起來差不多」放行。固定動畫採樣與共同畫質作畫面比較，人物少畫、錯衣裝、分身、影子缺失為零容忍。

### 性能與統計

先量1k／5k／10k×Near0/64。25k列後續容量擴展，不先把`set_active_soldiers(25000)`被clamp的10k當25k結果。新runner輸出actual/requested counts與來源指紋。

報告至少有wall FPS＝frames／實測wall、frame p50/p95/p99/max、CPU simulation、ordinary transform prep、upload／submit、Near／socket／structural、draw/dispatch counts、active／visible／mask／Near人數、資源容量與記憶體高水位。既有逐幀FPS平均不得當wall FPS；CPU nested scopes不得相加。Render-thread/GPU timestamps與VRAM若無可靠來源就標unavailable，不從wall餘額推算。

第一成功訊號是普通兵CPU Transform準備近乎消失；但B已達部分相同gate，故仍須展示C相對B的整場／尾幀變化。預設啟用需同條件反覆收益且畫面／時鐘／Near不回歸。GPU能力通過、實測收益、正式整合三種狀態分別報告。

**正式TerrainLab萬人≥30 FPS、p95≤33.33ms、p99≤50ms、action/wall 0.99–1.01的舊整場門檻保留為後續正式任務，不能由這次3D原型成績替代。** 不為達標偷偷降人數、解析度、模擬速度或Near預算。

## 8. 後續分期（不納入第一包一起做）

### Phase 2：GPU短期位置／速度與交接邊界

AgentState A/B、每個simulation substep讀A寫B並交換，render消費最後committed版本；加入turn／加減速／slot convergence。先定固定模擬步與render插值，不把frame delta任意改成戰鬥時鐘。獨立位移一啟用，同步完成Near選人位置查詢、少量GPU state回傳、PROMOTING／ACTIVE／DEMOTING版本交易與失敗checkpoint。

只讀回需要的IDs／小型事件，不掃全軍state。用同一個StableAgentID移交，ready前保留proxy，demotion等GPU提交可見後才撤actor；表示切換是原子可見，不以多畫一個人物掩蓋延遲。異步回傳帶epoch／generation，舊回包不得復活已轉隊／刪除ID。

本期採明確單寫者：GPU_ACTIVE由GPU積分；CPU_NEAR_ACTIVE由原Near側state控制，GPU停止該ID的一般積分。PROMOTING在約定handoff tick取得可移交的確定狀態，暫停該ID的普通GPU積分且proxy仍可見，Near ready後再移交；若取消則GPU從同一已提交狀態恢復。不得用舊異步快照覆蓋仍在前進的Agent。DEMOTING在約定tick提交最後Near狀態並停止Near寫入，GPU確認後才恢復該ID積分。這是Phase2必驗的新交接契約，正式玩法若不允許交接等待，需同tick追補／事件協議後才能接入，不能暗藏時間差。

### Phase 3：地形、corridor與合法slots

CPU保留主路徑、形狀、戰術容量；GPU追蹤合法slots與走廊。center/basis/columns只能表示矩形；引入有版本的SlotTargetBuffer及CorridorBuffer，部署、地形revision、改寬、slot-swap時更新changed slots，常態不傳全軍Transform。

正式destination planner已有100人平台60＋合法queue40、深到淺與入口保留；只有平台加合法queue仍不足才拒令。**平台容量60≠render count60**，存活／排隊100人仍全部存在。正式transit最大寬4，附件10/5/3/1是新目標示例；不直接改formal常數。不同座標單位、坡度、cliff與corridor資料要明確adapter，不在shader自行猜合法性。

### Phase 4：GPU grid與局部移動

uniform grid、有限鄰居、soft separation／alignment／corridor constraint；A/B避免同buffer鄰居race。cell size由角色半徑、作用距離和最大單步位移決定，3×3只有在覆蓋範圍足夠時成立。

32人/cell僅初始容量，不是密集戰場永遠成立的假設。counter飽和／overflow不OOB，也不能漏兵／丟碰撞而自稱通過；定義可重建的overflow隊列／count-scan-scatter或容量擴充策略，以實測選最小正確方案。不要直接把GPU軟排斥等同正式reservation／atomic occupancy。

slot-swap只變派位與assignment revision，不交換人物ID／隊長幹部身分。正式已有target ownership交換與0.5秒rebalance，應做adapter，不另建第二份Formation權威。

### Phase 5：GPU動畫

先沿既有archetype及共用資產選BAT／VAT或baked palette，測Idle/Walk/Run/Attack/Hit/Death、clip邊界與pose同步。完整模組骨架保留Special；目前程序擺動不冒稱完成此期。1個surface是第一probe限制，不是未來全部裝備必須重做的授權。

### Phase 6：分區、culling、LOD與compaction

依archetype／空間chunk／LOD配置，正確custom AABB，考慮formation-relative／chunk-relative和origin rebasing。GPU cull及compact後才以實際compact count驅動draw；維持StableAgentID映射、counter reset、buffer bounds及每surface arguments。camera-only的LOD變化不應改玩法資格。

### Phase 7：戰鬥事件與正式遊戲整合

CPU繼續高階Formation／軍令／重要角色與保存責任；普通兵GPU傷害／死亡若加入，先設事件容量、無丟失提交與權威reconciliation，再談擴量。不得將全部AgentState每tick下載。

正式接入需選清楚：
- CPU cells／reservation仍權威、GPU只按合法movement description插值：這是GPU呈現。
- GPU ordinary位置成玩法權威：則移動、占格、選敵、命中、Near及save所有同tick讀者都要有一致接口，不能保留stale CPU mirror。

既有正式救援ordinal、pair／side／callback順序、ranged pre-melee位置＋post-melee資格的契約，保留在歷史核心計畫及現有tests；只在接入這些玩法時驗，不強迫Phase1先重寫全部。正式Army上限200與目標Formation≤100的層級映射／保存遷移需單獨交付；不縮名冊、不憑renderer index造新人物。

## 9. Sol 交付與停止邊界

下一個實作指令後，先按P1a–P1d完成最小GPU Transform垂直切片。每步分開「已實作／已驗證／仍缺口」，保留失敗與不利結果。新增能力probe與性能試驗使用原樣有界Godot verifier，超時／錯誤按AGENTS定位修正；不改verifier、不中途丟棄dirty工作或自動commit/push。

專屬output需包含：來源／DLL／引擎／素材指紋、requested/actual/visible counts、command/output ABI、RID生命期結果、GPU真正執行證據、A/B/C原始frame資料與wall統計、畫面／ID oracle、fallback原因、選用backend決策。無來源的25–30ms不充當已核實基線。

本輪文件學習到此完成；**不因這份計畫自動開始實作，也不一次啟動Phase2–7。**
