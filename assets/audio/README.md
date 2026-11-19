# Site P0／P1 音效素材

2026-10-08。這是已授權製作的首批播放素材，**Godot 匯入與原生播放器元件合約已通過；主觀試聽、原遊戲事件播放與混音仍未驗收**。所有 WAV 都是 44.1 kHz、mono、PCM16，峰值不超過 0.451；音量仍由原 SFX bus／presenter 控制。

`catalog.json` 是目前播放清單：`sounds[kind] = {variants: [{path, duration, provisional, loop, ...}], volume_db, group, priority}`。`duration` 是讀回 WAV 得到的真實秒數；腳步額外記錄 surface、locomotion、tempo、variant、footsteps。火 loop 的 `loop: true` 由 presenter 複製原生 AudioStreamWAV 後設定 LOOP_FORWARD；不要修改共享 resource。

## 首批數量

首批 **36 檔＝24 個步伐段＋12 個其他短聲**。步伐為四種表面 × walk／run × fast／slow＝16 檔位：草土與硬地各 8 檔，木板與淺水各 4 檔。每段安排兩次接觸，walk fast／slow 為 0.38／0.50 秒，run fast／slow 為 0.18／0.26 秒；只供原格步進完成後的擬聲，不宣稱是真實自然步頻或動畫精確著地。尤其 0.18 秒兩步很密集，須實際試聽後調整素材；不得把它當作聽感通過。

其餘 12 檔：馬蹄 3、contact 3、shield 2、hurt 2、bow 1、crossbow 1。`hoof_walk`／`hoof_run` 共用那 3 檔，不重複計數。

P1 另加 6 檔：地面／木／金屬投射接觸各 1、小火／大火 loop 各 1、熄滅 1。因此目錄共 **42 個 WAV**；追加檔不包含在首批 36 檔內。

## 來源、授權與限制

原始檔與完整來源記錄仍在 `output/audio_preview_20261008`，沒有覆寫預覽。catalog 的 sources 列出來源頁、作者、原標題、CC0 授權、取得品質、原檔 SHA-256 與選用秒數；製作修改、每檔 SHA-256、實測格式與峰值另見 `output/audio_implementation_20261008/material_receipt.json`。`licenses/` 保存 Kenney 原 License.txt，以及本批使用的 Freesound 授權紀錄：純文字 `freesound_<編號>.txt`，記音效名稱、作者、來源網址與 CC0。原本存的 Freesound 網頁 HTML 快照內嵌 Freesound 的公開 Mapbox 金鑰，觸發 GitHub 金鑰警告，2026-11-14 改存文字。全部選用來源均按保存的 **CC0 1.0** 記錄製作。

- Kenney：[Impact Sounds](https://kenney.nl/assets/impact-sounds)、[RPG Audio](https://kenney.nl/assets/rpg-audio)，使用官方原 Ogg。步伐剪取攻擊段並排列兩次；contact 是通用金屬撞擊，沒有驗證特定武器材質。
- 淺水步伐與熄滅聲來自 el_boss 的 [Fishing Lure Plop Water](https://freesound.org/people/el_boss/sounds/853279/)；它是釣具水花，**並非真實淺水腳步或滅火錄音**。
- 馬蹄來自 Max_Headroom 的 [Horse Galloping](https://freesound.org/people/Max_Headroom/sounds/175356/)，將短接觸排列成完成步段；**並非真實走馬節奏或正式母檔**。
- fire_small／fire_large 來自 ceich93 的 [fire_crackling](https://freesound.org/people/ceich93/sounds/263864/) 前 0–6／4–10 秒，做 250 ms 循環交叉淡化，實際每圈 5.75 秒。技術上已處理切口，**可聽接縫、噪音與大小火適配尚未驗收**。
- crossbow 來自 DUDE_X-SoundLab 的 [Crossbow Fire III](https://freesound.org/people/DUDE_X-SoundLab/sounds/752203/)，頁面另署 XTREME_STUDIOS，原為彈簧裝置擬音。**所有上述 Freesound 檔都只使用公開低品質 MP3 預聽，轉成 WAV 不會變成母檔品質**；正式品質關閉前須換原始母檔或經使用者接受的素材。
- shield 是 Kenney 金屬＋木板撞擊的修改擬音，不是假稱真盾錄音；hurt 是肉身撞擊回饋，**不是人類受傷叫聲，也没有新增角色語音**。bow 是刀刃揮動＋皮帶操作的暫用釋放擬音，不是真弓弦；投射接觸也只是材質撞擊替代。

所有合成與公開預聽衍生檔在 catalog 標 `provisional: true`。`false` 只表示兩個通用 metal contact 沿官方素材原聲轉換，不代表聲音適配／遊戲／聽覺驗收完成。

## 已做與仍待完成

已核對 CC0 原檔 hash、16 檔位／24 步伐／36 首批／6 追加數量，讀回全部 mono PCM16 WAV，檢查有限值、真實長度與峰值，並記錄火 loop 首末樣本差。C 隔離專案已經 canonical Godot 匯入與原生播放器元件 335 checks PASS，2 個專用腳本及 42 個 PCM 匯入 sidecar 已按相同 hash 發布 D；歷史兩次 FAIL 保留於 output/audio_implementation_20261008/runtime_evidence。仍待試聽選擇、真弓弦／人類受傷叫聲／母檔補齊、火 loop 可聽接縫、原事件接入、實機音訊、密集播放混音與效能驗收；元件 PASS 不代表原遊戲流程或聽感通過。

先前 shore MP3 的解碼警告仍保留在預覽證據；本批沒有使用 shore。源取樣率不同時沿既有 numpy 作線性轉換，這是 provisional 擬音的簡單製作方式，正式品質驗收若不足則换母檔或適當重採樣版本，不新增 runtime codec。

## P3 追加與替換（2026-10-10 搬入 D）

Nekki 2026-10-10 選定全部搬入。`catalog.json` 換成 P0–P3 版：51 種聲音、68 個變體檔。新增 `p3/` 25 檔（採集與工具、門、船、動物、水邊環境）與 7 個替換版（`bow_longbow_release`、`crossbow_recorded_release`、`down_body_foley`、`fire_large_original`、`fire_small_original`、`hurt_voice_1`、`hurt_voice_2`）；舊版 6 檔留在目錄但不再被 catalog 引用。每檔的來源、作者、授權與修改記錄在 catalog `sources`，授權頁快照在 `licenses/`，野豬與魚另見 `P3_ADDITIONAL_CREDITS.md`。仍全部是 provisional，試聽、混音與實際事件聽感都未驗收。

### 需要署名的素材

散佈遊戲時，下列素材必須在遊戲的版權／致謝頁列出：

- `p3/animal_boar_01.wav`、`p3/animal_boar_02.wav`、`p3/animal_boar_03.wav`：Günter Tembrock，**TSA:Sus_scrofa_V_2124_17_2**，Museum für Naturkunde Berlin / Tierstimmenarchiv（[來源](https://suche.tierstimmenarchiv.de/search/showdetails.html?from_search=true&language=deutsch&unique_identifier=TSA%3ASus_scrofa_V_2124_17_2)），[CC BY-SA 3.0 Germany](https://creativecommons.org/licenses/by-sa/3.0/de/legalcode)。已剪輯、重採樣到 44.1 kHz、加 20 ms 淡入淡出、必要時衰減、轉 PCM16。**這三個衍生音檔本身也以 CC BY-SA 3.0 Germany 授權**；此授權只適用於這三檔，不擴及遊戲其他內容。不代表原作者背書。
- `p3/animal_deer_fallow_rut_01.wav`：Elodie Briefer、Elisabetta Vannoni、Alan G. McElligott，*Quality prevails over identity in the sexually selected vocalisations of an ageing mammal*，Additional file 1（[doi:10.1186/1741-7007-8-35](https://doi.org/10.1186/1741-7007-8-35)），[CC BY 2.0](https://creativecommons.org/licenses/by/2.0/)。已剪輯與轉檔。
- `p3/cart_roll_loop_01.wav`：Monika Widzicka / Work With Sounds / Museum of Municipal Engineering，*WWS Woodenwagon*（[Wikimedia Commons](https://commons.wikimedia.org/wiki/File:WWS_Woodenwagon.ogg)），[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。已剪輯成循環並轉檔。

其餘素材依 catalog 記錄為 CC0 1.0，不強制署名；仍建議在致謝頁列出 Kenney 與各 Freesound／OpenGameArt 作者。
