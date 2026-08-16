# Worldgoing Architecture Contract

`PROJECT_ARCHITECTURE.md` is the source of truth. This file records the current implementation boundary and does not replace or extend that document's design.

## Module contracts

| Module | Responsibility | Owns what data | Can depend on | Must not depend on | Status |
| --- | --- | --- | --- | --- | --- |
| Coordinates / deterministic core | Coordinate conversion, deterministic hashing, shared travel cost, bounded path algorithms | No session or player state | Data value types and shared constants | Scenes, TileMap, UI | Implemented |
| World data | Packed 256×256 Overview, lazy Region index, generated terrain/POI/road/Manifest access and deterministic caches | `WorldOverviewData`, `RegionData`, generated base/cache entries | Generators, data types, core utilities | Party, World Time, Scene nodes, UI, Region Delta | Implemented; startup allocates Overview and zero Regions; cache is rebuildable |
| Region data | Regenerable 100×100 strategic data, derived Region seed, generated feature references and packed Site content profiles | `RegionData.seed`, frozen base terrain, generated POI/route IDs, `RegionSiteContentData` | Coordinates, Manifest and generator output | TileMap, presentation state, session mutation, full Site Layout | Implemented; seven resource budgets conserve Manifest totals |
| Region runtime | Mutable Region state that must survive view replacement | `RegionRuntimeState`, `RegionDelta`, discovery placeholder | Session-owned state types, Region Runtime/Resolver | Generators, TileMap, UI as state owners | Implemented; minimal Outpost mutation uses this boundary |
| Region construction | Typed read-only Outpost preview and revalidated place/remove commands | No second state; writes stable `outpost` records into Session-owned sparse Region Delta | RegionRuntime, RegionStateResolver, RegionFeatureDelta | Scene nodes, UI, economy, Site state | Implemented as the first Construction Mode slice |
| Site definition | Rebuildable deterministic Site base for every Strategic Cell, Site Travel Profile and explicit Region/Site entrance anchor | `SiteData`: stable tile/POI ID, base version 3, Site Seed, four-way exit mask, local/global entrance meters and optional POI context | `WorldPOIData`, coordinates, deterministic hash | Runtime mutation, Scene nodes, UI | Implemented |
| Site generated layout | Fixed 50×50／2m Site base with native surfaces, local elevation/cliffs, resources, facilities, walls and transitions | Rebuildable `SiteLayoutData` version 8; four packed native surfaces plus generated placements, no mutable authority | SiteData/Profile, deterministic hash | Session, runtime state, Scene nodes, UI | Implemented; MOUNTAIN_PASS, bridge/stair traversal, minimum buildings and orthogonal tile roads share the resolved navigation data |
| Session runtime | Run-lifetime Party, World Time, selected layer context, travel plan, Region/Site runtime states, and active Battle state | `GameSession`, `PartyData`, global position, active Site-local Party cell, travel state, `RegionRuntimeState` map, lazy `SiteRuntimeState` map, `BattleRuntimeState` | Data and core services | View nodes, TileMap, Sprite | Implemented |
| Site runtime | Sparse mutable Site state, revision and detached Base + Runtime query snapshots | `SiteRuntimeState`: base identity stamp, test flag, removed generated IDs and added facility placements; Party position remains in `PartyData` | SiteData, Session, typed Site query/command results | SiteMap, RegionMap, generators, UI, localization | Implemented for harvest and facility add/remove without copying 2,500-cell Base |
| Runtime travel API | Typed travel query/command results, Site-profile path/cost decisions, Site Entry Query, bounded/blocked Site movement, Site runtime query/commands, authoritative travel step mutation | Operates `GameSession` through its API; no duplicate manager state | Session, WorldData, core travel services, typed result data | Map scenes, Camera, TileMap, UI | Implemented as `TravelRuntime` |
| Battle runtime | Read-only preview query plus the minimal mutable Battle command loop | `BattleRuntimeState` in `GameSession`; nine detached `SiteLayoutData` bases, formations, paths, revision and elapsed battle time | Session, `RegionRuntime`, deterministic Battle Site generator, shared `WeightedGridPathfinder` | Scene nodes, UI, damage/AI/combat resolution | Implemented as formation movement slice; combat resolution is NOT IMPLEMENTED |
| Runtime navigation | Composes World/Region/Site/Battle Preview views and runs the existing travel loop | Active view reference only; authoritative state stays in Session/WorldData/Runtime services | Session, WorldData, TravelRuntime, BattlePreviewRuntime, map scene contracts | Pathfinder, Travel Cost, gameplay eligibility decisions | Implemented; map animation is an optional view contract |
| Presentation | Draw maps, camera, hover/preview/visual interpolation, Site direction requests, Party marker, Debug UI | View-only hover, preview and visual positions | Session/data snapshots, Runtime query/command results and signals | Pathfinder, Travel Cost, authoritative Party/World Time mutation | Implemented |
| Paper doll asset lab | Validate visual catalogs, resolve detached split-part recipes, preview action clips, apply transient dyes, and export deterministic contact sheets | V1 `PaperDollPreviewDraft` plus V2 `PaperDollV2Recipe`; V1 fixed 11-Sprite pool and V2 fixed 12-Sprite pool remain separate until migration | Presentation visual Resources, Texture2D, Image, UI | GameSession mutation, Persistence, gameplay Item/Mount, Unit/Battle state | V1 split-part/action/dye lab remains implemented. V2 male+female calibrated reference baseline is PASS: 256/256 GPU checks, minimum silhouette IoU 1.0, maximum BBox delta 0 px across 4 directions × 8 frames × 8 cases. V2 split-part自由換裝、PC appearance persistence、gameplay equipment/mount ownership、V1→V2 CharacterCreator migration and Battle variants are NOT IMPLEMENTED |

Acceptance note (2026-08-13): the default generator capture is white hair with
silver armor. Hair+eyebrows, Armor, Cape and Mount are independent transient
dye groups; Helmet is opt-in and hides Hair to prevent double-head stacking. The
ImageGen attack candidate is composite-only and is not attached to a split layer
until deterministic layer extraction is available. The current action fallback is
the verified `PaperDollActionSheet` procedural split transform, not a claim of
dedicated per-layer attack art. Alternate visuals use geometry-locked palette
variants of approved reference sheets; the female complete boards are now
calibrated into the V2 reference-match path, while raw split-part crops remain
staged until deterministic layer extraction is accepted.
| Persistence | Seed + Delta save/load boundary for Session and Region runtime | Serialized `SessionSaveData` snapshots only; authoritative state remains in `GameSession` | Session/runtime snapshots, generated data versions, JSON/FileAccess | Scene nodes, UI, caches, Site Runtime, active Travel Path, active Battle | Implemented for Session + Region; active Site/Battle state is rejected with typed codes |

Current Battle slice: the active battle state is Session-owned, composed from nine deterministic `SiteLayoutData` CELL_BASE layouts, and moved by typed Formation commands. Each Formation contains 100 personnel, uses a 20m x 10m footprint with 20 x 5 visual slots, and the Battle context caps both sides together at 9,000 personnel. `BattleSiteMap` renders one circular GPU instance per person (100 instances per full Formation) for active and reserve personnel; selected Formation bounds are an interaction outline only, not a team sprite. Reserves are presentation-only staging and are not selectable or movable until activated by a future runtime command. Active Battle saves are rejected with `BATTLE_ACTIVE` until combat persistence exists.

## World → Region → Site

- `NavigationController.start()` requests one packed 256×256 `WorldOverviewData`; `WorldMap` consumes it without generating Region thumbnails or POIs. Actual startup verification requires `WorldData.regions` to remain empty.
- `WorldData` lazily produces a detached `RegionGenerationManifest` and, on Region demand, packed `RegionSiteContentData`. Shared edge contracts are derived from stable coordinates; seven resource budgets are distributed across 10,000 Strategic Cells without allocating full Site Layouts.
- `WorldData.regions` is the World-owned index of Region definitions. The current `RegionData.world_cell` is the implementation name for the document's Region coordinate.
- A Region seed is derived only from `world_seed`, `world_cell`, and the terrain generation version through `RegionData.derive_seed()`; runtime RNG order and scene instances are not inputs.
- `RegionData` records deterministic identity and generated base/cache references. `RegionData.terrain_data` is frozen after generation; clearing the cache removes only the rebuildable object.
- `PartyData.current_global_region_cell` is the single authoritative global Party position. World/Region cells are derived with `WorldCoordinates`; while a Site is active, `PartyData.current_site_local_cell` is the authoritative local sub-position and is cleared on return to Region.
- `GameSession` owns World Time, travel plan/progress, and Region runtime state, so replacing `WorldMap`, `RegionMap`, or `SiteMap` does not erase them.
- Region Outposts are stable `RegionFeatureDelta` records owned by `GameSession.region_runtime_states`; `RegionMap` only keeps the current preview and renders resolved copies.
- `WorldPOIData` is optional Region-level Site content. `SiteData.from_poi()` enriches a POI tile; `SiteData.from_region_cell()` supplies the deterministic base for any non-POI Strategic Cell. `SiteMap` does not retain the POI, Region, Session, or Runtime owner.
- POI Site IDs remain stable and POI-derived; generic tile Site IDs use `site_cell_<global_x>_<global_y>` and derive a versioned deterministic Site Seed from World Seed plus Global Cell. Both paths copy the lightweight strategic landform/exit profile and define Site-local meters through a reversible local/global entrance anchor at the center of the parent Strategic Cell. They contain no mutable gameplay state.
- `SiteLayoutData` owns the fixed `50×50` grid and `2m` cell constants. `SiteLayoutGenerator` version 8 deterministically rebuilds the corresponding `100m×100m` bounds, four native surfaces, elevation/cliff edges, resource/facility placements and four-way tile-edge navigation from `SiteData`; those bounds align exactly with the parent Strategic Cell.
- Every Strategic Cell can be queried lazily as one lightweight Site Travel Profile without allocating Site Runtime. The Profile includes native surface／rock／river／coast hints and seven resource amounts. `MOUNTAIN_PASS` is derived only for Mountain Road cells with at least two actual Route connections; its exit mask is shared by strategic travel, the local corridor and the two raised cliff sides.
- `GameSession.site_runtime_states` lazily owns `SiteRuntimeState` by `site_id`. A Site query can return an unallocated detached snapshot; entering or mutating a Site allocates its runtime state.
- `SiteRuntimeState` stores only the current architecture contract: base identity/version stamp, revision, test flag, added facility placement records and removed stable generated IDs. It contains no Node, Scene or presentation reference and never copies the 2,500-cell Base.
- `SiteMap` receives one detached `SiteRuntimeSnapshot` from `TravelRuntime`, emits cardinal movement requests, and draws a Party marker only when the snapshot says the Party is at that tile. It has no `GameSession`, `TravelRuntime`, `WorldPOIData`, or `RegionData` dependency and never mutates Party state.

## Generator / runtime / presentation boundary

- `RegionTerrainGenerator`, `WorldPOIGenerator`, and `WorldRoadGenerator` are deterministic generators. They contain no Party, discovery, construction, combat, quest, or view state and never read TileMap nodes.
- `SiteData.from_poi()` and `SiteData.from_region_cell()` derive the Site base. `SiteLayoutGenerator` consumes only that base and emits detached `SiteLayoutData`; it has no Session, Runtime, Scene, UI, or mutable gameplay dependency.
- `WorldData` may cache generated results for performance. Clearing those caches must not change results.
- Road generation version 5 limits each deterministic terrain-aware Route to a 48-Cell corridor and only connects POIs inside the current finite `WorldData` bounds. World／Region roads use cardinal tile edges only; POI candidate, road sample, graph, path and overlay caches remain rebuildable generated data, never Runtime authority.
- `GameSession` owns `RegionRuntimeState` instances; each state owns a sparse `RegionDelta`. `RegionStateResolver` is the only Base + Delta read path.
- `GameSession` and `RegionRuntimeState` hold mutable run state. No map Scene is required to keep Party position, World Time, travel progress, or Region runtime fields alive.
- `TravelRuntime.query_site_snapshot()` is read-only and resolves copied Site Base + Runtime + Session read context. Site state commands validate identity and update Site revision only on real Site-state mutations; `move_party_in_site()` validates Party/Site identity, cardinal direction, bounds and generated `NAV_BLOCKED`, then mutates only `PartyData.current_site_local_cell`.
- `RegionRuntime.query_outpost_preview()` is read-only and does not allocate or repair Region runtime state. Place/remove commands revalidate and are the only Outpost mutation path used by Presentation.
- Map Scenes and `DebugUI` consume data or detached snapshots. Their hover, preview, camera, and interpolation fields are presentation state only.
- Site art scale is presentation-only and derives from the fixed 50×50／2m contract. The 256px base surface remains the low-cost composite; the 800px near-camera layer renders native surfaces, elevation faces, resources and facilities at 16px per local cell. `SiteMap` supports wheel zoom from 2x to 32x and preserves zoom across snapshot refresh. Site roads render as one continuous opaque cleared band; decorative road sprites are not tiled into the route, so roadside resources remain outside the visual clearance. MOUNTAIN_PASS no longer copies the debris-bearing base tile into raised tops, then draws the narrow exit road separately, preventing rock bleed-through and platform/road double bands. `MapArtCatalog` owns visual metre sizes and generated sprite paths, never occupancy or navigation. Large POI images remain deferred multi-tile composites.

## Audit status

### Site runtime completion

The Site layer now has deterministic tile- and POI-backed definitions, explicit local/global entrance anchors, four native surfaces, local height/cliff edges, seven generated resource types, bridge／wood-stair／stone-stair／wood-wall／stone-wall placements, minimum 7×5 and 9×7 building definitions, bounded Site A*, lazy Session-owned sparse runtime state, detached snapshots and typed query/command results. Any valid Region tile can enter Site without Party locality or POI gating. Full harvesting rewards, regeneration, building cost/time, NPC content, movement time/animation and persistence remain outside this slice.

### Completed Site native-surface slice

The approved boundary keeps the 50×50／2m contract, uses rebuildable per-cell elevation plus explicit transitions in `SiteLayoutData`, and lets `TravelRuntime` validate the same resolved layout used by the renderer. `SITE_NATIVE_SURFACE_LAZY_GENERATION_REFACTOR_PLAN.md` P0–P6 is complete. This adds no second coordinate system, TileMap authority, 3D physics, per-cell Node or Party/Formation ownership.

- A — Skeleton complete: three map Scenes, coordinate contract, deterministic terrain/POI/road generation, and existing Party/Travel/World Time test coverage are present; Main and Runtime smoke now pass with the normal Godot CLI user/cache environment.
- B — Corrected: Region mutable ownership was separated from `RegionData`; `RegionData.seed` is now the generated-cache seed contract.
- C — Corrected minimally: added `RegionRuntimeState`, Session accessor, and this contract file. No speculative feature modules were added.
- D — No duplicate Manager/Singleton system. `SiteData` is a static data type; a Region Site entry resolves from the selected Strategic Cell, with `WorldPOIData` as optional enrichment.
- E — Corrected: Runtime navigation no longer reads `RegionMap`'s visual duration constant; the view owns animation timing through an optional method contract.
- F — Corrected: `TravelRuntime` now owns `PartyPathfinder` and Travel Cost calls. `RegionMap` and `WorldMap` use the shared typed Travel Preview Query and Start Travel Command; `SiteMap` and NavigationController use the typed Site Entry Query. The old RegionMap `PartyPathResult` bridge and view-injected Travel context were removed.
- G — Complete: generators hold only deterministic generator/cache state, never player mutable state.
- H — Complete for current state: Party/World Time/Travel are Session-owned; Region mutable fields are `RegionRuntimeState`-owned.
- I — Smoke coverage added for World/Region view replacement. Persistence for Site-local Party position and broader Site gameplay is not implemented.
- J — Future module boundaries are documented above; only the minimal Region Outpost and bounded Site movement slices have entered gameplay implementation.
- K — Added `scripts/tests/runtime_command_query_test.gd` with 18 focused boundary checks. Editor parse, static dependency scans, headless Main startup, and the Runtime command/query tests pass with writable Godot user/cache directories. The managed sandbox's prior signal 11 is an environment limitation, not a project dependency.
- L — Added `RegionDelta`, `RegionStateResolver`, and `RegionRuntime` for the in-session Seed + Delta contract. `scripts/tests/region_seed_delta_test.gd` contains 22 reconstruction/boundary checks.
- M — Construction Mode now has one minimal Region Outpost slice. It reuses Region Runtime/Delta/Persistence and adds no Manager, Autoload, economy, worker, timer, road, wall, farm, or Site-construction system.

## Runtime command/query boundary

- `TravelRuntime.query_site_snapshot()` is the Site read boundary. It rebuilds `SiteData` plus deterministic `SiteLayoutData`, validates any Session-owned runtime state, and returns one detached Base + Runtime + Session read snapshot without allocating gameplay state. `begin_site_visit()`, `leave_site()`, `move_party_in_site()`, `ensure_site_runtime_state()`, `set_site_test_flag()`, `add_site_test_feature()`, and `remove_site_test_feature()` are typed Site commands.
- Site runtime commands re-resolve the deterministic POI or Strategic Cell definition by `site_id`, reject identity mismatch, reject duplicate features, and do not trust or mutate a Presentation-held snapshot. `move_party_in_site()` additionally requires the active Party at that Site, accepts only one-cell cardinal directions, rejects the `0..49` boundary and `NAV_BLOCKED` destination, and does not advance World Time.
- Site runtime failure codes are typed in `SiteRuntimeFailureReason`, including invalid Party, inactive Site, invalid direction, out-of-bounds and blocked movement; no localization or UI string is returned by the Runtime boundary.
- `TravelRuntime.query_travel_preview()` is read-only with respect to Party position, World Time, active Travel State and Region runtime state. Its pathfinder/cache internals may change.
- Travel Preview keeps one query-scoped `RegionStateResolver` per visited World Cell; the cache is discarded after the query and cannot survive as gameplay state.
- `TravelRuntime.start_travel()` re-runs the query from `party_id` and destination, then creates the authoritative Session travel path. Presentation never submits a preview path as authority.
- `TravelRuntime.cancel_travel()` owns cancellation state; `commit_travel_step()` owns Party position, path index and World Time updates; `finish_travel()` owns completion/cleanup.
- `GameSession` stores typed `travel_failure_reason` and `last_travel_status`; map Presentation converts those codes into display labels. Runtime no longer writes travel UI messages into Session.
- `TravelRuntime.query_site_entry_at()` owns generic Strategic Cell Site entry; it resolves every valid tile and does not require Party locality or POI presence. `query_site_entry()` follows the same no-locality-gate rule for callers that explicitly address a POI. NavigationController loads the approved Site view and routes `SiteMap.move_requested` to the Runtime movement command without deciding movement validity.
- `TravelPreviewResult`, `TravelCommandResult`, `TravelCellResult`, `SiteEntryQueryResult`, `TravelStepResult`, and `TravelFailureReason` contain typed runtime data/reasons, not localized UI strings.
- `TravelRuntime` obtains resolved deterministic Terrain/Road data through `RegionRuntime` and `WorldData`; `RegionMap` no longer supplies mutable Travel calculation context or accepts a `PartyPathResult`.
- `RegionMap`, `WorldMap`, and `SiteMap` contain no direct `PartyPathfinder` or `TravelCostConfig` calls; RegionMap forwards tile entry to the typed `TravelRuntime.query_site_entry_at()` boundary. NavigationController contains no direct Pathfinder/Travel Cost calls.
- `RegionRuntime.query_region()` returns resolved Base + Delta queries. Generic terrain/feature mutation helpers remain test-only; production Outpost changes use typed Construction commands, and map scenes do not write `RegionDelta`.

## Region construction boundary

- `RegionRuntime.query_outpost_preview(world_cell, region_cell)` owns Party/Travel eligibility, Region/Cell validation, passability and occupancy rules. It returns a typed `RegionConstructionResult` and does not allocate mutable Region state.
- `RegionRuntime.place_outpost()` reruns the preview query before adding one stable `outpost:x:y:cell_x:cell_y` feature to sparse `RegionDelta`; a Presentation-held preview is never authoritative.
- `RegionRuntime.remove_outpost()` only removes a matching player-added Outpost. Missing and wrong-type records return typed failures and do not change revision.
- `RegionStateResolver.get_runtime_features_by_type()` returns detached copies for Presentation. `RegionMap` never reads or writes `RegionDelta` directly.
- `RegionMap` owns only Construction Mode, hover preview and marker drawing. Clearing the preview or replacing the Scene cannot change or erase an Outpost.
- The existing Region persistence wire format already serializes `RegionFeatureDelta`, so Outposts round-trip without a second save schema.

## Battle command/query boundary

- `BattlePreviewRuntime.query_preview()` is a read-only query. It validates typed participant/context inputs, rejects active Travel, resolves the complete 3x3 footprint through `RegionRuntime`, and returns a detached typed `BattleSiteSnapshot`.
- `BattleSiteGenerator` receives resolved cell input and produces deterministic nine-Site base data plus preview geometry only. It does not read `WorldData`, `GameSession`, Region Delta, Scene nodes, TileMap, UI, or mutable combat state.
- `RegionMap` converts the selected cell to a global coordinate, sends the preview query, renders typed failure status, and emits only a successful snapshot. It does not calculate Battle eligibility, terrain, roads, rivers, frontage, or deployment.
- `NavigationController` begins the revalidated Battle Runtime, advances it, routes `BattleSiteMap.formation_move_requested` to the Runtime, and clears the active state on return to Region.
- `BattleSiteMap` consumes `BattleSiteSnapshot`, draws the nine-Site composite and Formation footprints, and emits camera/select/move input only. It has no `WorldData`, `GameSession`, `RegionRuntime`, or generator dependency.
- Active Battle state is intentionally excluded from Persistence; `PersistenceService` returns typed `BATTLE_ACTIVE` instead of writing an incomplete combat save. Damage, AI and combat resolution remain out of scope.

The current implementation extends this boundary with a minimal movement and command slice: `BattlePreviewRuntime.begin_battle()` re-runs the query and creates Session-owned `BattleRuntimeState`; `issue_move()` uses the shared bounded `WeightedGridPathfinder`; `advance_battle()` moves Formation positions continuously in meters with terrain/road/river-crossing step costs. `BattleParticipantData` identifies the PC/NPC commander and its commander Formation; subordinate simple intents are delayed, while fine intents travel as data-only `BattleDispatchData` messengers with deterministic segment interception and typed `query_order()` status. Formations enter captain autonomy on direct contact and defer incoming orders until contact clears. The composite is nine canonical 50×50/2m `SiteLayoutData` CELL_BASE layouts (150×150 derived navigation cells, 300m×300m). `BattleSiteMap` remains presentation-only and emits move intents/status updates. Damage, AI, combat resolution, and Battle persistence remain out of scope.

## Corrective logic closure

- `TravelRuntime.finish_travel()` now verifies the active path, committed path index, and authoritative Party destination before marking `ARRIVED`; incomplete or stale steps cannot clear travel as an arrival.
- `TravelRuntime.fail_travel()` records typed failure and clears a broken active plan as `FAILED`; `NavigationController` uses it when a travel step cannot be committed.
- Active cancellation is finalized by `TravelRuntime` and emits the typed `travel_cancelled` signal after Session cleanup.
- Travel pathfinding and `query_travel_cell()` now consume a Runtime-owned resolved Base + Region Delta cell provider. Direct generator sampling remains available for deterministic data tests, while active Runtime travel rejects cells outside the finite WorldData bounds.
- `RegionRuntime.query_region()` is read-only with respect to Session allocation; mutable Region state is created only by mutation commands.
- Region queries no longer repair a zero/invalid Delta generation version as a side effect; invalid state remains unchanged and resolves as an explicit version mismatch.
- `WorldRoadGenerator` enforces connection limits against both source and candidate total degree, including deterministic fallback edges.
- `RegionMap` redraws its custom Party presentation while the visual tween changes its view-only position; authoritative Party position remains Session-owned.
- Added focused regression coverage for terminal Travel guards, cancellation signaling, non-allocating Region queries, and Delta-aware Travel cell queries; the separate Outpost section records the later Construction slice.

## Region Seed + Delta Contract

- `RegionData.derive_seed(world_seed, world_cell, generation_version)` is the single Region seed derivation. The existing shared world-field generators remain unchanged, so neighboring Region slices still meet at global cell boundaries.
- `RegionData` owns deterministic identity and generated base/cache references only: source world seed, derived seed, generation version, frozen terrain, generated POI IDs, and generated route IDs. It does not own owner, development, construction, removal, camera, hover, preview, or animation state.
- `RegionRuntimeState` is session-owned. Its `RegionDelta` stores only sparse terrain overrides, added feature records, removed/disabled stable feature IDs, owner/development values, base generation version, and revision. Discovery remains the existing placeholder and is not expanded here.
- Region Outposts use coordinate-derived stable IDs and `feature_type == &"outpost"`; removing an added Outpost erases it without creating a tombstone.
- `RegionStateResolver` validates Region identity and base generation version before exposing `get_terrain()`, feature queries, owner, and development. A mismatch reports `DELTA_REGION_MISMATCH` or `DELTA_BASE_VERSION_MISMATCH` and is not silently applied.
- Generated POIs use their existing stable `poi_id`; generated roads use their existing stable `route_id`. Delta never stores Node IDs, array indexes, or scene paths.
- `WorldData.clear_generated_cache()` clears only generated base/cache objects. The same Seed plus a copied Delta reconstructs the same resolved query. Persistence now serializes Session Seed + Region Delta without serializing generated caches.

## Persistence boundary

- `PersistenceService` is a small `RefCounted` service. It captures typed `SessionSaveData` and returns typed `PersistenceResult` values; it does not own a second runtime Session.
- Session Save stores World Seed, current generation versions, World Time, Party data, and sparse Session-owned `RegionRuntimeState` / `RegionDelta` records. Generated terrain, POI, road caches, Scenes, UI, TileMaps, camera state, and path preview data are excluded.
- Save validates the complete snapshot before writing, rejects active Travel with `TRAVEL_IN_PROGRESS`, rejects an active Site with `SITE_ACTIVE`, and rejects active Battle with `BATTLE_ACTIVE`; active Travel Path, Site-local Party position, and Battle state persistence are intentionally deferred.
- Load parses and validates the complete wire payload, including format and generation versions, before constructing a new `GameSession`. A failed load returns no replacement Session and does not mutate the existing one.
- `NavigationController.replace_session()` is the Presentation orchestration hook for a validated replacement. It rebinds `RegionRuntime` and `TravelRuntime` and may refresh the current view; `PersistenceService` never loads Scenes or controls a Camera.
- The JSON wire format is an implementation detail of Persistence. Runtime callers use typed snapshot/result objects and typed failure codes; no localization string crosses the boundary.
- Outposts reuse the existing added-feature serialization and require no Persistence format or migration change.

## Verification status

- Static command/query and Runtime dependency scans: PASS; Runtime has no Map/UI symbols and Presentation has no Pathfinder/Travel Cost symbols.
- Site runtime dependency and ownership scans: PASS; `SiteRuntimeState` has no Presentation dependency, map scenes do not own the Site state dictionary, and NavigationController delegates Site state to `TravelRuntime`.
- `Godot --headless --editor --recovery-mode --quit`: project script/class scan PASS. Godot Mono emits a known editor-only `HotReloadAssemblyWatcher` timer message during headless editor shutdown; no project script parse error was reported.
- Main headless startup with `--rendering-method gl_compatibility`: PASS, exit 0.
- `character_creator_test.gd`: PASS for the reference-derived Catalog/ID/texture contract, 22 runtime PNG export, gender/default resolution, mount bundle resolution, detached drafts, on-foot/mounted Recipe visibility, all seven non-idle distinct action sheets, fixed 11-Sprite reuse, unified four-direction frame/flip/z-order control, hair+brow/armor/cape/mount dye groups, pure Image contact sheets, mounted head/body/horse alignment, reusable UI lifecycle, lazy DebugUI entry, modal input restoration, and one-way Presentation dependencies.
- `build_paper_doll_reference_pack.gd`: PASS; the three source boards are deterministically keyed, trimmed, nearest-packed into 22 `reference_parts` sheets at `512×192` RGBA8.
- CharacterCreator visible runtime capture: generated under OpenGL compatibility on NVIDIA GeForce RTX 5060 and manually inspected for split controls, white-hair/silver-armor default, six additional action states, four dye groups, Anchor guide and mounted output without layout clipping. Focused action QA also writes on-foot/mounted 8-action montages to `.visual_captures/paper_doll/qa/`; Art Gate 1 contact sheets remain 42 PNGs in `.visual_captures/paper_doll/art_gate1/`.
- `runtime_command_query_test.gd`: 18/18 PASS.
- `site_runtime_test.gd`: 36/36 PASS, including deterministic Site Seed/base/layout reconstruction, fixed 50×50/2m bounds aligned to one Region Strategic Cell, directional MOUNTAIN_PASS profiles, generated `NAV_BLOCKED` cliffs, typed cardinal/bounds/blocked movement, WASD input-to-Runtime routing, detached read-only snapshots, Scene re-entry stability, and one-way generator/runtime/presentation dependencies.
- `architecture_smoke_test.gd`: PASS.
- `cross_region_runtime_test.gd`: Global travel and cancel runtime PASS.
- Existing tests: Coordinate 4/4, Terrain 9/9, POI 10/10, Road 14/14, Party movement 16/16, Cross-Region Travel 18/18, Region Seed + Delta 22/22 PASS. Runtime command/query also covers a shared cross-Region Preview Query. The Road suite includes an actual generated Mountain Road Site at Global Cell `(1832,38)` resolving to a directional pass and validates cardinal tile edges.
- Party movement still reports a Godot ObjectDB/resource cleanup warning at process shutdown; POI teardown is clean after releasing its temporary SiteMap. Party gameplay assertions and exit code are successful. This remaining warning is a test-harness cleanup gap, not a persistent runtime gameplay error.
- `persistence_test.gd`: 10/10 PASS for Session round-trip, Region Delta reconstruction, active Travel/Site rejection, corrupt/version/data validation, view-state exclusion, Presentation dependency scan, and Navigation Session replacement.
- `battle_site_test.gd`: 20/20 PASS for nine-Site composition, typed/read-only preview queries, PC/NPC commander authority, delayed simple orders, fine-order delivery, messenger interception, captain-autonomy data, 100-person Formation geometry, active Formation path/movement commands, 9,000-person GPU-instance rendering, input validation, Region boundary resolution, Region Delta projection, typed failures, detached snapshots, Presentation dependency separation, deterministic regeneration, and Region/Battle Scene replacement.
- `region_construction_test.gd`: 13/13 PASS for read-only preview, typed validation, command revalidation, sparse place/remove, stable IDs, detached resolved data, Scene replacement, Persistence round-trip, and one-way Runtime/Presentation dependencies.
- `site_native_surface_refactor_test.gd`: 9/9 PASS for packed Overview budget and zero-Region startup, detached shared Manifest edges, exact seven-resource Region conservation, all four generated native surfaces, stable resource placements, bridge and stair sparse removal, the 7×5 minimum building door/wall contract, harvest and player facility Delta.
- `site_detailed_scene_test.gd`: 6/6 PASS; `site_visual_scale_test.gd`: 8/8 PASS; `visual_composition_test.gd`: 8/8 PASS with all generated Site art loading.
- Non-headless GPU P6 capture on NVIDIA GeForce RTX 5060: 10/10 full/close PNGs for grassland village, forest/fruit trees, mining, double-cliff pass and river/bridge/stairs. After the clean-road and mountain-pass layer revision, at 1280×720 with VSync disabled, the uncapped gate minimum was 3488.07 FPS; this is only a threshold check, not a product FPS claim. Images are in `.visual_captures/site_native_surface_p6/`.
- Isolated `APPDATA`／`LOCALAPPDATA` editor scan: exit 0 with no project `SCRIPT ERROR`, Parse Error or `res://` resource load error. Windows root-certificate access remains an environment warning.

## Not implemented by design

Site native surfaces, height/cliffs, bridge/stairs/walls, seven resource placements, minimum building definitions, bounded Site pathfinding and sparse harvest/facility Delta are implemented. The following remain deliberately unimplemented: resource rewards/regeneration, ecological AI, construction costs/time/durability, building interiors, large POI multi-tile composition, formal sand/snow/swamp overlay and shoreline polish, Site movement time/animation, Site-local Party persistence, Site Runtime persistence, active Travel persistence, Save UI, world-scale impassable ridge topology, broader Region construction, settlement/economy gameplay, NPC, events, weather, quests, migrations, Character gameplay beyond the presentation pack, Battle paper-doll variants/shader, combat runtime/resolution and multi-slot saves. Their absence does not imply a missing parallel owner.
