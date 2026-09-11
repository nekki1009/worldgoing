# Terrain Generator Lab

## 單圖資源與土地操作（2026-09-11）

右側「聚落地圖 · 資源與土地」是新操作面板。用天然資源／農耕／牧地／淡水／建設
檢視查看土地；WASD 移動、滾輪縮放、右／中鍵拖圖保持原樣。
選「工人採集區」「清理區」「勘探區」後在地圖拖曳，原 NPC 會走到合法工作格，
採集後攜帶產物回營地箱才入庫。工作區由上而下優先，可關閉暫不需要的工作。
玩家手動作業須站在來源旁；移動、攻擊或受擊會中斷，攜帶物需回營地交貨。

建設先選設施，再以「建設區」框選 1–36 格，核對材料、清理需求、入口及工時後
按「安排施工」。完成農牧場／作坊後，選中並按「派工運作」；原料按批扣除，缺水會停工。
整地把框選範圍降至其中最低層，範圍內高差最多一級；採礦本身不改山體。
土地檢視的「查看」模式也可框選，顯示可耕格、牧養承載、已服務及地基適建格數。

和平 1 秒＝1 遊戲分鐘；實際交戰 1 秒＝1 遊戲秒，動作不變慢。暫停及離開應用程式
會停止時間，回來按「繼續」。離線不增加產量。
每 30 現實秒在和平時自動保存地圖，也可手動保存／載入。開新 seed 前會按地圖 ID
另存舊地圖，面板底部可重新開啟。損壞載入不覆蓋原檔，也會停用自動保存。
此保存涵蓋資源、用地、存貨、工作及角色格位；不包含人物換裝、軍隊和戰鬥快照。

原本的地形、換裝、騎乘、戰鬥與軍隊測試控制位於「展開原地形／人物／戰鬥測試」。
這些測試控制的裝備與騎乘尚未消耗生產庫存。詳細規則及驗證見 `SITE_RESOURCE_IMPLEMENTATION.md`。

## LAB combat test (2026-09-08)

The command NPC now inherits the player's grid movement and transparent 3D
viewport presentation and loads the existing female character model. Both have
separate parts/animation windows. Move commands arm a destination click on the map.

Space attacks the female NPC using the player's equipped weapon; hold G to guard.
The panel can order an NPC attack, enable adjacent counterattacks, or restore both
actors to 100 HP. Existing WASD/Shift/F controls remain available. Movement reserves
the destination cell; actors cannot step onto each other's cell.

Within three cells actors draw weapons and enter a ready pose; beyond four cells
they return to travel mode (hysteresis prevents flicker). Ready pose alone is not
damage-blocking: G explicitly guards. Weapons remain drawn while moving nearby.

Attacks lock movement for the clip duration. During 20–80% of the clip, CPU-skinned
weapon blade/head convex silhouettes sweep against bone-driven body capsules in
shared map coordinates. Animation is sampled at 120 Hz; one attack can hurt once.
This is 2D collision matching the projected 3D artwork, not 3D triangle physics.
Bow/crossbow release a visible straight projectile at 45%; the swept projectile
must physically reach a body, with a six-cell maximum travel distance. Every
intervening terrain edge must pass TerrainData.can_attack_across (including current tall resource/building blockers). Heavy
attacks deal 30, others 20; front guard reduces damage to 20%. Hits interrupt pending
strikes, zero HP disables movement/attacks and plays down. The retired World battle
formation rules were removed in V0.3R; this Site uses its existing LAB owners.

Deliberate limits: one selected opponent, cardinal facing, convex weapon parts and
bone capsules rather than per-pixel alpha collision, no pursuit combat AI, and
no per-clip authored hit events. Timing windows and damage are initial test tuning.
Short-weapon clips have an explicit in-cell attack step (stance + step <32 pixels);
both the displayed actor and collision geometry move together and recover to the
ready stance. Logical terrain_cell and actor/camera positions never change during
this step. Spears use a withdrawn leading foot to retain thrusting space.
Mounted and screen-down weapon attacks blend a fixed-target arm aim correction;
mounted riders can lean from the upper torso while hips/legs stay on the saddle.
Bone lengths, weapon size and colliders are not stretched to force a hit. Head
hurtboxes fit the selected face mesh, excluding hair/helmets. There is no invisible
tile-range damage fallback. Editor animation tests
remain presentation-only; combat is triggered by Space or the combat buttons.

Focused verification: scripts/tests/terrain_lab_combat_test.gd checks strike timing,
single-hit damage, guard, cliff blocking, death/reset, both models' weapon clips and
mounted thrust. GPU captures are 21_female_npc_combat.png and 22_combat_strike.png.

The newer `terrain_lab_weapon_contact_test.gd` verifies fixed idle/attack framing,
left/right ground and mounted spear bounds, jump attack scale, mesh contact,
swept tunnelling protection, misses, guard, cliffs and projectile travel. Captures:
`contact_attack_spear_1.png`, `contact_attack_jump_heavy_1.png`,
`contact_ride_thrust_1.png` (and opposite-direction variants).
Lab viewports are 1280×1536 with matching orthographic overscan; sprite scale and
centre are unchanged. Ground and mounted projection both use 37.128 map pixels
per metre. No mount/attack-dependent camera shift or character shrink in the LAB.
`terrain_lab_weapon_reach_test.gd` covers male/female attacks in all four cardinal
directions with all eight ground loadouts and mounted sword/spear, plus in-cell
step/return and identical mounted/ground scale assertions. Its `--mounted-down`
argument isolates the downward mounted reach cases for diagnostics.

2026-09-08 verification: the 80-case male/female, four-direction weapon matrix
passed (exit 0, 21.616s; godot_verify/20260908_131655_578). After adding vertical
overscan for the full-scale mounted spear, weapon-frame bounds, fixed anchors,
guard/cliff rejection, misses and projectile single-hit checks passed (exit 0,
11.922s; godot_verify/20260908_131829_496). These are functional GPU runs, not a
steady-state FPS benchmark. The normal standing/riding scale is identical.

## Scope and entry

Run the project (F6 on `scenes/terrain_lab/TerrainLab.tscn`, or F5 using the new
project main scene). Baseline viewport: 2560×1440; default OS window: 1600×900.
The map is 100×100 cells (10,000 cells). At camera zoom 1, each cell is 64×64 logical pixels;
the window's content scale still applies. **Fit map** shows the complete map;
**64px / cell** restores the inspection scale.

The 100×100 expansion keeps the 64px logical cell contract; only the generated
terrain extent and packed arrays grow from 4,096 to 10,000 cells. `Fit map`
computes its camera framing from the generated `TerrainData.size`, so the whole
map remains visible without a preset-specific camera constant.

This is the current Site entry in V0.35R. It has no legacy World/Region streaming,
resource/building gameplay, save system, or AStar dependency.
The previous world-system runtime and 2D paper doll system have been removed;
the existing NPC/combat tests and hundred-person army remain here.

## Owners

- `TerrainPreset`: eight strategy identifiers and default parameters.
- `TerrainGenerator.generate(preset, seed, overrides)`: standalone data generation;
  does not access scenes, rendering or input. Defaults are 100×100, maximum level
  1–5 according to preset, and micro strength 0.025. Optional overrides are
  `size: Vector2i` (16–128 per axis), `max_height: int` (1–5), and
  `micro_strength: float` (0–0.04).
- `TerrainData`: one map object with packed byte arrays for height, surface,
  flags, directional drops, ramp edges and appearance variation. No per-cell
  Node/Resource/Dictionary/object. Default cell payload: 90 KiB (nine bytes/cell),
  excluding the small map-level metadata and temporary generation buffers.
- `TerrainRenderer`: four retained CanvasItem draw batches: GroundTop,
  CliffFaces, Water, TerrainDetail. Camera/movement do not regenerate terrain.
- `TerrainTestCharacter`: authoritative `terrain_cell` plus a transparent 3D
  character viewport presented as Sprite2D. Headless data tests use no 3D visual.
  `TerrainLab` owns UI and camera.

## Player editing (2026-09-08)

Use **Player parts / animation** to open the existing 3D character editor in
an additional Window. Body, equipment, animation, speed, loop and timeline
controls operate on the same live model shown on the terrain. Closing the
window preserves the selected clip and equipment for this session. Movement
temporarily selects walk and returns to idle; grid traversal updates immediately
while the rendered character eases to the next cell over 0.38s.
Holding WASD/arrows repeats at a fixed walk cadence; Shift selects the faster
run cadence without OS key-repeat acceleration. F toggles a real horse mount
and the rider is reparented to the horse's `Socket_Rider` attachment.
Edits are not saved across application restarts. The window captures movement
input while open. The renderer viewport is created under the player before
loading the GLB, avoiding invalidated skin bindings from moving a loaded rig
between 3D worlds. Existing standalone editor behavior remains the default.

Verification: actual Lab visual/input test exit 0, 24.907s; part selection,
shared viewport identity, changing arm pose during walk, left/right facing,
fixed walk/run repeat, F mount/dismount, mounted framing, mounted slash/thrust
shield visibility, one-shot jump attack,
smooth movement completion, 1920x1080 editor readability, window close
retaining the clip, plus existing movement/picking checks. Evidence:
`.godot-temp/godot_verify/20260908_014415_781/result.json`.
Captures `12_player_editor.jpg`, `13_player_in_lab.jpg`,
`14_player_mounted.jpg`, `15_player_jump_attack.jpg`, `16_mounted_slash.jpg`,
`17_mounted_thrust.jpg`, and the late-frame `19_ground_spear_late.jpg` were
inspected. Spear attacks keep the exact idle character framing; only the
hand-mounted lance is reoriented so the full shaft and tip read without moving
or scaling the rider.
Terrain art is loaded through Godot's imported `Texture2D` resources via
`ResourceLoader`, removing the previous `Image.load` export warnings. A first visual
attempt timed out at 50s; the data-only test actor now does not initialize the
full editor before the actual Lab.

## Macro composition

| Preset | Composition |
| --- | --- |
| PLAINS | Broad low rollers, one damp hollow, correlated dirt patches |
| TERRACED_HIGHLAND | Asymmetric radial platforms with nested height contours |
| COASTAL_CLIFF | Oriented continuous shoreline, beach, lowland and rising inland plateau |
| FOREST | Forest ground mass, winding clearing and two glades; no trees |
| WETLAND | Two broad basin shapes, water cores, joined wet banks and grass margins |
| ROCKY_HIGHLAND | Elongated bending ridge with raised rocky shoulders |
| RIVER_VALLEY | Continuous meandering river, floodplain and elevated valley sides |
| ISLAND | Closed irregular landmass, sandy perimeter, grassy interior and highland |

Seed chooses macro position/orientation/phase/stretch. These fields determine
elevation and surfaces, then heights are quantized. Neighbor analysis produces
cliff drops and shores. Same-height connected platforms are joined by a seeded
spanning set of adjacent one-level ramps. Noise only adds small field variation;
the final per-cell random byte affects brush shading, not terrain classification.

## Cliff and movement contract

`cliff_drops[cell * 4 + direction]` retains the positive height difference in
N/E/S/W order. A CLIFF flag means the platform has a cliff edge, **not** that its
whole top is blocked. Rock faces are separate edge geometry and never walkable
floor cells. The current visual face expands 64px toward the lower
platform so it remains readable at fit-to-map zoom; it does not change the
64px logical standing cell or the stored height difference.

`ramp_edges` contains reciprocal direction bits. The displayed arrow points
uphill, but the passage works both ways. Movement is cardinal and one cell per
key event: same-height walkable tops pass; a height difference of one needs a
reciprocal ramp; larger changes, water and outside bounds are blocked.

Click walkable ground to place the tester. WASD/arrows move it. Holding the
right or middle mouse button pans the camera; wheel zoom keeps the mouse target
fixed and supports up to 10× close-up. Grid/height labels and movement can be
toggled independently. The Lab intentionally permits teleporting the tester to
either bank of the river; it does not invent a bridge or a pathfinding system.

The Lab also includes one lightweight command-test NPC. Its purple marker is
presentation-only and stores a `terrain_cell`, a command, and a temporary grid
path. The command dropdown can stop it, move it to the currently hovered
walkable cell, or make it follow the player. It uses the same `TerrainData`
`can_step` rule and does not introduce the formal NPC or combat systems.

The optional 100-person army test keeps one captain at index 0 and 99 ordinary
soldiers on the same packed grid. When the captain's next legal step is occupied
by an adjacent friendly soldier, `TerrainArmy` performs an atomic two-cell
exchange: both units interpolate with the same progress, both source cells stay
reserved during the exchange, and both owners are committed in one tick. Water,
one-way or missing ramps, external PLAYER/NPC cells, moving units, and active
reservations reject the exchange. The HUD reports `Swaps` and `completed steps`.
Detour search uses one reusable Packed frontier and resumes for 256 expansions
per navigation slice; exhausting a slice is pending, not an unreachable result.

## Verification

Run `scripts/tests/terrain_lab_test.gd` with Godot 4.6.2. Headless mode checks
eight presets × three seeds, duplicate data hashes, distinct macro compositions,
346,152 movement-edge commands, valid ramps, island water boundaries, river
connectivity, and reachable highland summits. Visual mode loads the actual Lab,
tests UI seed controls, invalid input, camera picking through the 10× range, right-drag
camera panning, mouse zoom anchoring, movement toggle, and uphill/downhill input; it captures each preset
NPC move/follow/stop commands, and the character before/after a slope crossing.

Captures: `.visual_captures/terrain_lab/01_plains.png` through `08_island.png`,
plus `09_ramp_before.png`, `10_ramp_after.png`, and `20_npc_commands.png`
(2560×1440).
The visual runner measures 60 settled frames per preset at a 60 FPS cap;
that is a short stationary test, not a long-duration performance guarantee.
Generation timing excludes first draw/submission. PNG export is outside the
measured frame window. The Lab now uses four project-bound, high-resolution
terrain textures:

- `assets/map/terrain_lab/terrain_lab_grass_v2.png` — seamless grass base.
- `assets/map/site/cliffs/cliff_face_inland_highres_v2.png` — existing painted
  cliff, sampled from its straight interior (source y=120..400). Ramp ends use
  proportional crops; no full-image squeezing or artificial joint lines.
  The previous Lab cliff texture remains on disk but is no longer consumed.
- `assets/map/terrain_lab/terrain_lab_water_v2.png` — seamless water surface.
- `assets/map/terrain_lab/terrain_lab_sand_v2.png` — seamless sand/dry-soil
  surface used by SAND and DIRT cells.

They contain no trees, resource nodes, roads, buildings or characters. The
remaining surface variation and ramps are still drawn by the four retained
CanvasItem batches so the generator stays cheap and deterministic. Which
presets to retain remains a human visual/gameplay decision.

Material revision preview: `11_cliff_material_close.png` and its smaller JPG
in `.visual_captures/terrain_lab/`; captured from the running Lab at zoom 1
with debug labels disabled. Visual/input verification passed on 2026-09-07
in 20.301s (exit 0), evidence:
`.godot-temp/godot_verify/20260907_230350_174/result.json`.
This verifies loading and movement, not final art acceptance. The cliff-face
presentation now occupies the full low-side 64px tile while ramp spans remain
open. No new raster generation was needed for this revision.

### 2026-09-11 cliff readability revision

`TerrainRenderer` now draws a warm height tint, a narrow irregular high-side lip,
directional face lighting, a top-to-bottom shade gradient and a fading 10px foot
shadow. Multi-level drops have an internal rock-stratum mark while retaining the
same 64px visual face. Passage openings remain 36px wide. Ramps use the existing
soil texture and an outlined uphill arrow; both directions remain traversable.
Water is drawn before cliff faces so it no longer hides the shore edge.

These are presentation changes within the same four terrain batches. TerrainData,
TerrainGenerator and TerrainTestCharacter SHA-256 hashes were unchanged; no model,
collision, saved height or ramp-bit changes were made.

`terrain_cliff_readability_test.gd` captures the actual Lab, including the default
highland seed, natural coast and a controlled 16×16 plateau with four ramp directions
and a two-level drop. It walks every fixture ramp uphill and downhill, rejects the
two-level crossing, and checks that rendering preserves the terrain fingerprint.
Images are in `.visual_captures/terrain_lab/cliff_readability/`, with `before_` and
`after_` prefixes for the same map/camera pair. All seven final PNGs were inspected.

Godot 4.6.2 Mono, isolated writable environment, bounded foreground verification:

- Before GPU: `20260911_234050_100/result.json`, exit 0, 17.997s.
- Final GPU: `20260911_234515_948/result.json`, exit 0, 18.310s.
- Original eight-presets × three-seeds data/movement regression:
  `20260911_234558_904/result.json`, exit 0, 13.818s.

Records are under `.godot-temp/godot_verify/`. Run the visual test with
`-Mode visual -TimeoutSeconds 27 -GodotArguments @('--script',
'res://scripts/tests/terrain_cliff_readability_test.gd')`; the baseline capture used
the old renderer and additionally passed `'--','--before'`.
Root-certificate output is recorded as environment noise. An initial test assumption
that the default natural seed contained all four uphill directions was false;
that failed run is not counted as success. The fixed fixture makes coverage explicit.
No battle-performance matrix was measured for this art revision.

The 100-person army path is measured separately by
`scripts/tests/terrain_lab_army_performance_test.gd`. Ordinary soldiers use
the shared baked atlas at `assets/characters/terrain_lab_army/standard_soldier/`
and the captain is the only live 3D source. On 2026-09-09 at 2560×1440,
PLAINS seed 24680 measured BASE P95 16.793ms, idle army P95 16.792ms, moving
P95 16.775ms / P99 16.804ms / max 17.145ms at Engine FPS 60, with 105
completed steps during the sample. This is a GPU-backed smoke benchmark, not
a multi-minute performance guarantee.

Measured on 2026-09-07, Godot 4.6.2 Mono / D3D12 Forward+ / RTX 5060:

- Editor scan: PASS, exit 0, 23.649s.
- Headless data/movement run: PASS, exit 0, 3.971s.
- Final data + actual-Lab visual/input run: PASS, exit 0, 17.249s.
- Normal project entry without a test script (`--quit-after 90`): PASS, exit 0;
  evidence `.godot-temp/godot_verify/20260907_154854_252/result.json`.
- Final 24-map generation sample: median 35.177ms, maximum 66.859ms.
- Eight UI generation samples: 31.638–38.770ms. Settled render windows: 60.00 FPS
  at the configured 60 FPS cap; maximum sampled frame 16.82ms. Total scene count
  stayed at 42 nodes including UI, with four terrain drawing layers.
- Known environment-only message: `Failed to read the root certificate store`.
  No script/parse/assertion failure or leaked-resource warning in the final log.

Final evidence: `.godot-temp/godot_verify/20260907_154622_139/result.json` and
`combined.log`. The runner used
`C:/Users/Nekki/.codex/skills/godot-runtime-verify/scripts/verify_godot.ps1`,
`-Mode visual -GodotArguments @('--script','res://scripts/tests/terrain_lab_test.gd')`
with a 50-second timeout and
`C:/Users/Nekki/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64.exe`.
