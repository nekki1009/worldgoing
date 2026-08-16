# Worldgoing Paper Doll V2 — Component Pack 02 規格表

狀態：`STAGING_SPEC_ONLY`（未通過素材 Gate 前不得加入 V2 Catalog）
版本：`pack_02 / v2_1`
適用：角色生成器、素材實驗室、離線接觸表與未來 SubViewport 烘焙

本包的目的，是在既有 `artgate1_*` 基線與目前 `alt_*` 測試素材之外，為每個可替換部件槽位增加一個可驗證的設計。所有新圖先放在 `assets/paper_doll/v2/staging/pack_02/`，只有 Validator、GPU 接觸表與人工輪廓審核全部通過後，才可複製到正式 `assets/paper_doll/v2/parts/` 並登錄 `manifest.json`。

## 1. 固定工程契約

| 狀態 | 每幀尺寸 | Sheet 尺寸 | Anchor | Sprite offset | 來源列 |
| --- | ---: | ---: | --- | --- | --- |
| `ON_FOOT` | `64×64` | `512×192` | `(32,56)` | `(-32,-56)` | `DOWN=0 / UP=1 / RIGHT=2` |
| `MOUNTED` | `64×96` | `512×288` | `(32,88)` | `(-32,-88)` | `DOWN=0 / UP=1 / RIGHT=2` |

- 每張 sheet 固定 8 欄、3 個美術來源方向；`LEFT` 只能由 `RIGHT` 以 `flip_h` 鏡像產生，除非 manifest 明確標示其他策略。
- `Sprite2D.centered = false`、Nearest filter、每個部件的 offset 不得自行改值。
- 每一幀的接觸點必須落在 Anchor ±1 px；不得用 Composer 的臨時位移掩蓋素材錯位。
- `BODY` 不在本包新增外觀。男女 Body 是幾何模板權威；改 Body 必須升級 `template_version`，不能當成普通裝備變體。

## 2. Pack 02 新增部件總表

設計主題是「旅行者皮甲套組」：短辮髮、皮革／青銅輕甲、騎行靴、開面盔、深綠披風、短槍、木圓盾，以及栗色馬與深綠馬鎧。這些是美術方向，不改變工程尺寸或遮罩契約。

| 新增槽位 | `visual_id` | 新增數量 | 性別策略 | 狀態 | 對稱策略 | 內容框（每幀 local px） | 染色遮罩 |
| --- | --- | ---: | --- | --- | --- | --- | --- |
| Hair | `pack02_hair_short_braid_01` | 1 款 × 男女 | `GENDERED` | Foot + Mounted | `MIRROR_RIGHT` | Foot `(4,0)-(60,36)`；Mounted `(4,32)-(60,68)` | `HAIR_BROWS` |
| Armor | `pack02_leather_scale_armor_01` | 1 | `UNISEX` | Foot + Mounted | `MIRROR_RIGHT` | Foot `(4,18)-(60,56)`；Mounted `(4,50)-(60,88)` | `ARMOR` |
| Boots | `pack02_riding_boots_01` | 1 | `UNISEX` | Foot + Mounted | `MIRROR_RIGHT` | Foot `(4,38)-(60,56)`；Mounted `(4,70)-(60,88)` | `BOOTS` |
| Helmet | `pack02_open_sallet_01` | 1 | `UNISEX` | Foot + Mounted | `MIRROR_RIGHT` | Foot `(6,0)-(58,32)`；Mounted `(6,32)-(58,64)` | `ARMOR` |
| Cape | `pack02_forest_cape_01` | 1 | `UNISEX` | Foot + Mounted | `MIRROR_RIGHT` | Foot `(0,18)-(64,56)`；Mounted `(0,50)-(64,88)` | `CAPE` |
| Weapon | `pack02_short_spear_01` | 1 | `UNISEX` | Foot + Mounted | `ASYMMETRIC_ALLOWED` | Foot `(0,8)-(64,56)`；Mounted `(0,40)-(64,88)` | 不染色 |
| Shield | `pack02_round_shield_01` | 1 | `UNISEX` | Foot + Mounted | `ASYMMETRIC_ALLOWED` | Foot `(0,14)-(64,56)`；Mounted `(0,46)-(64,88)` | `ARMOR` |
| MountTail | `pack02_chestnut_horse_tail_01` | 1 | `UNISEX` | Mounted only | `MIRROR_RIGHT` | Mounted `(0,50)-(64,88)` | `MOUNT` |
| MountBody | `pack02_chestnut_horse_body_01` | 1 | `UNISEX` | Mounted only | `MIRROR_RIGHT` | Mounted `(0,52)-(64,88)` | `MOUNT` |
| MountHead | `pack02_chestnut_horse_head_01` | 1 | `UNISEX` | Mounted only | `MIRROR_RIGHT` | Mounted `(0,32)-(64,80)` | `MOUNT` |
| MountBarding | `pack02_forest_barding_01` | 1 | `UNISEX` | Mounted only | `MIRROR_RIGHT` | Mounted `(0,46)-(64,88)` | `MOUNT_BARDING` |

合計：**11 個新增視覺槽位**；Hair 需要男女各一套，因此是 4 張 Hair sheet，其餘 Foot／Mounted 部件依表輸出。Body 不計入裝備新增數量。

## 3. 檔案命名與來源

### 3.1 最終標準化檔案

```text
assets/paper_doll/v2/staging/pack_02/
  pack02_hair_short_braid_01_on_foot_male.png
  pack02_hair_short_braid_01_on_foot_female.png
  pack02_hair_short_braid_01_mounted_male.png
  pack02_hair_short_braid_01_mounted_female.png
  pack02_leather_scale_armor_01_on_foot_unisex.png
  pack02_leather_scale_armor_01_mounted_unisex.png
  pack02_riding_boots_01_on_foot_unisex.png
  pack02_riding_boots_01_mounted_unisex.png
  pack02_open_sallet_01_on_foot_unisex.png
  pack02_open_sallet_01_mounted_unisex.png
  pack02_forest_cape_01_on_foot_unisex.png
  pack02_forest_cape_01_mounted_unisex.png
  pack02_short_spear_01_on_foot_unisex.png
  pack02_short_spear_01_mounted_unisex.png
  pack02_round_shield_01_on_foot_unisex.png
  pack02_round_shield_01_mounted_unisex.png
  pack02_chestnut_horse_tail_01_mounted_unisex.png
  pack02_chestnut_horse_body_01_mounted_unisex.png
  pack02_chestnut_horse_head_01_mounted_unisex.png
  pack02_forest_barding_01_mounted_unisex.png
```

### 3.2 美術來源板

每個部件先交付一張來源板，放在：

```text
art_source/paper_doll_v2/pack_02/<visual_id>_source.png
```

來源板只包含 `DOWN / UP / RIGHT` 三個完整視圖，不把多個不同部件拼在同一張圖。背景必須透明或純白且可由邊界 flood-fill 清理；不得使用帶有上一套角色頭、手、腳或馬身的完整角色板當部件來源。

## 4. 各槽位位置與禁止區

| 槽位 | 必須覆蓋 | 禁止覆蓋 | 驗收重點 |
| --- | --- | --- | --- |
| Hair | 頭皮、髮絲、眉毛 | 眼睛、鼻子、臉、耳朵、披風 | 四方向髮際線一致；染色只影響 Hair/Brows mask |
| Armor | 胸、肩、手臂、軀幹護甲 | 頭、髮、臉、鞋、披風外緣 | 不得露出錯位身體，也不得把護甲畫到頭上 |
| Boots | 鞋與靴筒至膝線 | 臉、軀幹、膝線以上 | 腳底貼 Anchor；不得漂浮或穿地 |
| Helmet | 頭盔與護面 | 眼睛可讀區、鼻子、披風 | 戴上後臉仍可讀；不得把頭盔當完整頭部重畫 |
| Cape | 披風布料與邊緣 | 頭髮、身體核心、武器握把 | DOWN 在身後、UP 可完整覆蓋背部；不以 z-index 掩蓋錯位 |
| Weapon | 武器本體 | 手、手臂、盾牌、身體 | 方向與握持點一致；LEFT/RIGHT 不瞬移 |
| Shield | 盾牌本體 | 手臂、臉、身體核心 | 盾牌位置符合朝向；不長在身體正中央 |
| MountTail | 馬尾與尾毛 | 騎士、馬頭 | 尾巴只在馬匹後側；不得穿過騎士身體 |
| MountBody | 馬軀幹、腿、蹄 | 騎士核心與臉 | 馬蹄落在 `(32,88)`；不得倒置或與騎士比例跳變 |
| MountHead | 馬頭、耳、韁繩 | 騎士臉、胸口 | DOWN／SIDE 朝向正確；不得蓋住騎士臉 |
| MountBarding | 馬身護甲 | 騎士、馬頭、馬尾 | 只覆蓋馬身；前後方向和馬體一致 |

## 5. Z-Order（直接採用 V2 候選契約）

| Layer | DOWN | UP | RIGHT | LEFT |
| --- | ---: | ---: | ---: | ---: |
| MountTail | -10 | -10 | -10 | -10 |
| Cape | -5 | 15 | 5 | 5 |
| MountBody | 0 | 0 | 0 | 0 |
| Body | 10 | 10 | 10 | 10 |
| Boots | 11 | 11 | 11 | 11 |
| Armor | 12 | 12 | 12 | 12 |
| Hair | 13 | 13 | 13 | 13 |
| Helmet | 14 | 14 | 14 | 14 |
| Weapon | 15 | -1 | 15 | -1 |
| Shield | 16 | -2 | -2 | 16 |
| MountHead | 20 | -5 | 20 | 20 |
| MountBarding | 21 | 1 | 21 | 21 |

## 6. 進件 Gate

每一張標準化 sheet 必須產生以下 QA 輸出：

1. 原始來源板與固定轉換參數。
2. 標準化 PNG：尺寸、RGBA8、8×3、Nearest。
3. 4 方向 × 8 frame contact sheet。
4. Anchor crosshair 與 frame 邊界圖。
5. template protected-mask overlay。
6. dye-mask overlay 與非目標像素差異報告。
7. JSON manifest 與 `PASS`／`FAIL` 原因。

任何一項失敗就停在 `staging/pack_02`，不得進入 `assets/paper_doll/v2/parts/`，不得修改目前 V2 參考板或替換現有 Catalog 預設。

## 7. 目前交付邊界

- 本文件與配套 JSON 是 Pack 02 的工程規格與位置鎖定結果。
- 新 PNG 尚未宣稱通過美術驗收，也不會在本階段直接加入 Catalog。
- 下一步是依本表逐槽位產生來源板，再用 V2 Normalizer／Validator 產出 20 張標準化 sheet（Hair 4 張、其餘 16 張），最後才做人工預覽驗收。
