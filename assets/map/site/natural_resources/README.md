# Site natural resource art v1

## 目前狀態：2026-10-03 五種野生動物與馬羊捕捉正式接入

有角鹿、野豬、無角鹿、野馬、羊已接入原 `SiteResourceView`；物種由 `SiteEnvironment.wildlife_species(variant, source_cell)` 統一判定。variant 0 的來源 anchor cell 偶／奇分別是有角鹿／野馬，variant 1 均為野豬，variant 2 的來源 anchor cell 偶／奇分別是無角鹿／羊。同一來源的各隻動物共用分類，不隨活動位置、剩餘量或動畫改變；保留原 variant 0～2、來源 ID、生成與存檔欄位，沒有新增 species 或其他保存欄位。

- `natural_resources_v1.png` 仍為 RGBA 1086×1448，三種樹、石料、黏土、鐵礦、鹽源、野生食物、藥草與魚沿用既有裁區。
- `stag_walk_v1.png`、`boar_walk_v1.png`、`doe_walk_v1.png`、`sheep_walk_v1.png` 沿用原透明圖集，均為 1774×887、4×2 格；羊沿既有試放素材正式接入。
- `horse_walk_v1.png` 為新離線烘焙透明圖集，512×256、4×2 格；alpha ≥16 的可見本體每格至少留邊 6 px。本輪羊圖的可見本體也至少留邊 6 px；鹿與野豬的既有量測見下方歷史紀錄。
- `manifest.json` 共用每種動物的貼圖、尺寸、左右方向錨點與各四幀資料。自然地圖和牧場均使用同一馬／羊貼圖；牧場沿既有靜態 feature 繪製路徑使用 phase 0，不新增動畫更新或排序 owner。

捕捉沿原 `SiteRuntime`／`SiteWorkTeam` 作業、工具、六遊戲分鐘批次與原人物 cargo，每批從同一來源扣一隻並取得一匹馬或一隻羊；鹿與野豬不能活捉。本人可將攜帶牲畜送到已完成、畜種相符的牧場入口旁，由 `stock_pasture` 在草地承載及原保存上限 36 頭內轉入 residents，剩餘牲畜仍留在原 cargo。自動捕捉區沿原工人搬運流程送到 depot，營地牲畜可供原牧場建造成本使用；狩獵的肉／皮產出規則保留。

原匯出 glob 涵蓋本目錄六張 PNG 與 manifest，未另造打包路徑。本輪五種素材、捕捉／入欄／存讀、正式按鈕與 GPU 畫面，以及原資源／隊員工作／建設流程回歸已通過。額外舊共同時鐘測試與目前全隊共享疲勞契約不相容，保留失敗紀錄，未列通過；不代表完整發行包、RegionLab 或大量動物效能驗收。做法、來源與最新證據統一見 [SITE_RESOURCE_IMPLEMENTATION.md 的「2026-10-03 五種野生動物與馬羊捕捉正式接入」](../../../../SITE_RESOURCE_IMPLEMENTATION.md#2026-10-03-五種野生動物與馬羊捕捉正式接入)。

## 歷史紀錄：2026-10-02 三種動物與天然資源素材接入

以下保留當時的素材與驗收邊界；目前五種映射、馬圖與捕捉接線以本頁上方 2026-10-03 狀態為準。

正式接入：2026-10-02，`SiteResourceView`。資料仍由 `SiteEnvironment` / `SiteRuntime` / `SiteStore` 管理。

- `natural_resources_v1.png`：image_gen 依使用者確認的天然資源樣板重畫，RGBA 1086×1448。三種樹、石料、黏土、鐵礦、鹽源、野生食物、藥草與魚；不含文字或地圖背景。
- `stag_walk_v1.png` / `boar_walk_v1.png` / `doe_walk_v1.png`：沿用 2026-10-01 走路試放原始透明 PNG，均 1774×887、4×2 格。正式 variant 0/1/2 固定對應有角鹿／野豬／無角鹿；未加入野馬資源。
- `manifest.json`：靜態圖實際裁區、遊戲尺寸、接地錨點；動物每方向固定錨點、左右各四幀。圖集實際尺寸及排列與生成提示要求不同，故靜態圖使用實測矩形，不假設等分格。

所有 PNG 都按來源原始 bytes 複製，沒有另行修改像素。來源與 SHA-256 在 `output/natural_resources_formal_20261002/asset_sources.json`。alpha ≥16 的可見本體留邊經測量：靜態至少 2 px、動物至少 4 px；alpha 1–15 的少量透明散點仍保留。動物採完整固定格，沒有逐幀重新置中或縮放。

素材由原顯示 owner 一次載入並共用；原列排序、TriangleBatcher flush、0.12 秒動態列刷新、活動相位與剩餘量檢查保留。圖集不存入遊戲存檔。匯出設定明確包含四張 PNG 與 manifest；本次未執行完整發行包測試。

## 靜態圖集生成提示

Tool: built-in image_gen; transparent_background=true. Reference: approved `exec-a7cb2c8d-f4bc-4ce6-9259-f0b253f892c7.png`.

Create ONE production-ready transparent PNG SPRITE ATLAS for the Worldgoing game from the supplied approved natural-resource art board. The reference is an art/shape reference, not a layout to preserve. Repaint its non-animal resources as separated reusable sprites with real alpha transparency. NOT another presentation board. No text, labels, cell lines, UI, checkerboard, solid backdrop, vignette or baked landscape.

EXACT ATLAS LAYOUT: portrait canvas 1536 pixels wide by 2048 pixels high, THREE columns and FOUR rows of equal 512x512 cells. Each object fully contained within its cell with at least 48px transparent margin on all four sides. Do not draw cell borders. There are EXACTLY TEN sprites and two empty cells. Row-major arrangement:
row 1 cells 1/2/3 = tall evergreen conifer / deep-green broadleaf oak / olive yellow-green broadleaf tree;
row 2 cells 1/2/3 = grey stone outcrop / shallow exposed terracotta clay patch / dark iron-bearing rock with restrained rusty ochre mineral seams;
row 3 cells 1/2/3 = flat white salt crust patch with modest tiny squat salt nodules / wild red-berry bush / broadleaf medicinal herbs with a few small very muted pale grey-lilac flowers;
row 4 cell 1 = ONE small freshwater fish viewed obliquely from above, its head points LEFT and tail RIGHT; row 4 cells 2 and 3 COMPLETELY EMPTY transparent.

STYLE must match the reference: elevated orthographic approximately 45-degree top-down game camera, clearly modeled natural forms with fine slightly painterly materials, clear small-scale silhouettes, upper-left daylight, warm bark, subdued natural colors. No perspective convergence. Crisp clean antialiased alpha edges. Trees show full trunks and exposed roots; no clipped treetops or thin cut off roots. Within their cells tree silhouettes roughly 350px wide by 400px tall. Rock forms roughly 360px wide by 280px tall, with fractured geometry but not low-poly. Clay and salt are FLAT deposits about 350px wide by 170px high, not dramatic cliffs or a deep mine, no pond or surrounding terrain. Bush/herbs about 350px wide by 300px high. The single fish around 300px long and 110px tall, silver-grey subdued coloring, fins/tail intact. Fish has NO water, ripples, rocks or other fish. Plants can have a tiny root contact clump, but NO rectangular soil tile or grassy platform. All other empty portions of each cell are truly alpha transparent. Do not include shadows: the game supplies contact shadows separately. No hazy outer glows, no white fringe, no loose particles near cell boundaries. No cast shadow on invisible floor. No people, no animals, no buildings, no extra resource types. Avoid saturated magenta or saturated purple; medicinal flowers very pale muted grey-lilac, green leaves dominate.
