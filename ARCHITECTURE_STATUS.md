# Worldgoing Architecture Contract

`PROJECT_ARCHITECTURE.md` is the source of truth. This file records the current implementation boundary and does not replace or extend that document's design.

## Module contracts

| Module | Responsibility | Owns what data | Can depend on | Must not depend on | Status |
| --- | --- | --- | --- | --- | --- |
| Coordinates / deterministic core | Coordinate conversion, deterministic hashing, shared travel cost, bounded path algorithms | No session or player state | Data value types and shared constants | Scenes, TileMap, UI | Implemented |
| World data | Region index, generated terrain/POI/road access, deterministic caches | `RegionData`, generated `RegionTerrainData`, POI and road cache entries | Generators, data types, core utilities | Party, World Time, Scene nodes, UI, Region Delta | Implemented; cache is non-authoritative and rebuildable |
| Region data | Regenerable 100×100 strategic data, derived Region seed, generated feature references | `RegionData.seed`, frozen base terrain, generated POI/route IDs | Coordinates and generator output | TileMap, presentation state, session mutation | Implemented |
| Region runtime | Mutable Region state that must survive view replacement | `RegionRuntimeState`, `RegionDelta`, discovery placeholder | Session-owned state types, Region Runtime/Resolver | Generators, TileMap, UI as state owners | Implemented; minimal Outpost mutation uses this boundary |
| Region construction | Typed read-only Outpost preview and revalidated place/remove commands | No second state; writes stable `outpost` records into Session-owned sparse Region Delta | RegionRuntime, RegionStateResolver, RegionFeatureDelta | Scene nodes, UI, economy, Site state | Implemented as the first Construction Mode slice |
| Site definition | Rebuildable deterministic Site base and explicit Region/Site entrance anchor | `SiteData`: stable ID, base version, Site Seed, local/global entrance meters and copied POI context | `WorldPOIData`, coordinates, deterministic hash | Runtime mutation, Scene nodes, UI | Implemented |
| Site generated layout | Fixed 50×50 Site grid at 2m per cell, deterministic bounds and presentation anchors | Rebuildable `SiteLayoutData`; no 2,500-cell mutable array or cached authority | SiteData, deterministic hash | Session, runtime state, Scene nodes, UI | Implemented as minimal layout data; semantic Site content/collision is NOT IMPLEMENTED |
| Session runtime | Run-lifetime Party, World Time, selected layer context, travel plan, Region/Site runtime states, and active Battle state | `GameSession`, `PartyData`, global position, active Site-local Party cell, travel state, `RegionRuntimeState` map, lazy `SiteRuntimeState` map, `BattleRuntimeState` | Data and core services | View nodes, TileMap, Sprite | Implemented |
| Site runtime | Sparse mutable Site state, revision and detached Base + Runtime query snapshots | `SiteRuntimeState`: base identity stamp, test flag, added/removed stable feature records; Party position remains in `PartyData` | SiteData, Session, typed Site query/command results | SiteMap, RegionMap, generators, UI, localization | Implemented as a minimal sparse contract |
| Runtime travel API | Typed travel query/command results, path/cost decisions, Site Entry Query, bounded Site movement, Site runtime query/commands, authoritative travel step mutation | Operates `GameSession` through its API; no duplicate manager state | Session, WorldData, core travel services, typed result data | Map scenes, Camera, TileMap, UI | Implemented as `TravelRuntime` |
| Battle runtime | Read-only preview query plus the minimal mutable Battle command loop | `BattleRuntimeState` in `GameSession`; nine detached `SiteLayoutData` bases, formations, paths, revision and elapsed battle time | Session, `RegionRuntime`, deterministic Battle Site generator, shared `WeightedGridPathfinder` | Scene nodes, UI, damage/AI/combat resolution | Implemented as formation movement slice; combat resolution is NOT IMPLEMENTED |
| Runtime navigation | Composes World/Region/Site/Battle Preview views and runs the existing travel loop | Active view reference only; authoritative state stays in Session/WorldData/Runtime services | Session, WorldData, TravelRuntime, BattlePreviewRuntime, map scene contracts | Pathfinder, Travel Cost, gameplay eligibility decisions | Implemented; map animation is an optional view contract |
| Presentation | Draw maps, camera, hover/preview/visual interpolation, Site direction requests, Party marker, Debug UI | View-only hover, preview and visual positions | Session/data snapshots, Runtime query/command results and signals | Pathfinder, Travel Cost, authoritative Party/World Time mutation | Implemented |
| Persistence | Seed + Delta save/load boundary for Session and Region runtime | Serialized `SessionSaveData` snapshots only; authoritative state remains in `GameSession` | Session/runtime snapshots, generated data versions, JSON/FileAccess | Scene nodes, UI, caches, Site Runtime, active Travel Path, active Battle | Implemented for Session + Region; active Site/Battle state is rejected with typed codes |

Current Battle slice: the active battle state is Session-owned, composed from nine deterministic `SiteLayoutData` CELL_BASE layouts, and moved by typed Formation commands. Each Formation contains 100 personnel, uses a 20m x 10m footprint with 20 x 5 visual slots, and the Battle context caps both sides together at 9,000 personnel. `BattleSiteMap` renders one circular GPU instance per person (100 instances per full Formation) for active and reserve personnel; selected Formation bounds are an interaction outline only, not a team sprite. Reserves are presentation-only staging and are not selectable or movable until activated by a future runtime command. Active Battle saves are rejected with `BATTLE_ACTIVE` until combat persistence exists.

## World → Region → Site

- `WorldData.regions` is the World-owned index of Region definitions. The current `RegionData.world_cell` is the implementation name for the document's Region coordinate.
- A Region seed is derived only from `world_seed`, `world_cell`, and the terrain generation version through `RegionData.derive_seed()`; runtime RNG order and scene instances are not inputs.
- `RegionData` records deterministic identity and generated base/cache references. `RegionData.terrain_data` is frozen after generation; clearing the cache removes only the rebuildable object.
- `PartyData.current_global_region_cell` is the single authoritative global Party position. World/Region cells are derived with `WorldCoordinates`; while a Site is active, `PartyData.current_site_local_cell` is the authoritative local sub-position and is cleared on return to Region.
- `GameSession` owns World Time, travel plan/progress, and Region runtime state, so replacing `WorldMap`, `RegionMap`, or `SiteMap` does not erase them.
- Region Outposts are stable `RegionFeatureDelta` records owned by `GameSession.region_runtime_states`; `RegionMap` only keeps the current preview and renders resolved copies.
- `WorldPOIData` is the generated Region-level Site entry. `SiteData.from_poi()` copies its stable context into a rebuildable Site base; `SiteMap` does not retain the POI, Region, Session, or Runtime owner.
- `SiteData` reuses `WorldPOIData.poi_id`, derives a versioned deterministic Site Seed, and defines Site-local meters through a reversible local/global entrance anchor at the center of the parent Strategic Cell. It does not contain mutable gameplay state.
- `SiteLayoutData` owns the fixed `50×50` grid and `2m` cell constants. `SiteLayoutGenerator` deterministically rebuilds the corresponding `100m×100m` bounds and layout anchors from `SiteData`; those bounds align exactly with the parent Strategic Cell, and `WorldData` exposes them without storing a second authoritative Site state.
- `GameSession.site_runtime_states` lazily owns `SiteRuntimeState` by `site_id`. A Site query can return an unallocated detached snapshot; entering or mutating a Site allocates its runtime state.
- `SiteRuntimeState` stores only the current architecture contract: base identity/version stamp, revision, test flag, added test feature records and removed stable feature IDs. It contains no Node, Scene or presentation reference.
- `SiteMap` receives one detached `SiteRuntimeSnapshot` from `TravelRuntime`, emits cardinal movement requests, and draws the Party marker. It has no `GameSession`, `TravelRuntime`, `WorldPOIData`, or `RegionData` dependency and never mutates Party state.

## Generator / runtime / presentation boundary

- `RegionTerrainGenerator`, `WorldPOIGenerator`, and `WorldRoadGenerator` are deterministic generators. They contain no Party, discovery, construction, combat, quest, or view state and never read TileMap nodes.
- `SiteData.from_poi()` derives the Site base. `SiteLayoutGenerator` consumes only that base and emits detached `SiteLayoutData`; it has no Session, Runtime, Scene, UI, or mutable gameplay dependency.
- `WorldData` may cache generated results for performance. Clearing those caches must not change results.
- Road generation version 3 limits each deterministic terrain-aware Route to a 48-Cell corridor and only connects POIs inside the current finite `WorldData` bounds. POI candidate, road sample, graph, path and overlay caches remain rebuildable generated data, never Runtime authority.
- `GameSession` owns `RegionRuntimeState` instances; each state owns a sparse `RegionDelta`. `RegionStateResolver` is the only Base + Delta read path.
- `GameSession` and `RegionRuntimeState` hold mutable run state. No map Scene is required to keep Party position, World Time, travel progress, or Region runtime fields alive.
- `TravelRuntime.query_site_snapshot()` is read-only and resolves copied Site Base + Runtime + Session read context. Site state commands validate identity and update Site revision only on real Site-state mutations; `move_party_in_site()` validates Party/Site identity, cardinal direction and bounds, then mutates only `PartyData.current_site_local_cell`.
- `RegionRuntime.query_outpost_preview()` is read-only and does not allocate or repair Region runtime state. Place/remove commands revalidate and are the only Outpost mutation path used by Presentation.
- Map Scenes and `DebugUI` consume data or detached snapshots. Their hover, preview, camera, and interpolation fields are presentation state only.

## Audit status

### Site runtime completion

The Site layer now has deterministic POI-backed base definitions, explicit local/global entrance anchors, a fixed 50×50 grid coordinate contract at 2m per cell, bounded WASD/arrow Party movement from `(25,25)`, generated local layout data, lazy Session-owned runtime state, detached snapshots, typed query/command results, and 34 focused architecture tests. Per-cell terrain/collision data, semantic gameplay content, movement time/animation and persistence remain intentionally outside this stage.

- A — Skeleton complete: three map Scenes, coordinate contract, deterministic terrain/POI/road generation, and existing Party/Travel/World Time test coverage are present; Main and Runtime smoke now pass with the normal Godot CLI user/cache environment.
- B — Corrected: Region mutable ownership was separated from `RegionData`; `RegionData.seed` is now the generated-cache seed contract.
- C — Corrected minimally: added `RegionRuntimeState`, Session accessor, and this contract file. No speculative feature modules were added.
- D — No duplicate Manager/Singleton system. `SiteData` is a static data type; the live Region Site entry is `WorldPOIData`.
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
- Site runtime commands re-resolve the deterministic POI definition by `site_id`, reject identity mismatch, reject duplicate features, and do not trust or mutate a Presentation-held snapshot. `move_party_in_site()` additionally requires the active Party at that Site, accepts only one-cell cardinal directions, rejects the `0..49` boundary, and does not advance World Time.
- Site runtime failure codes are typed in `SiteRuntimeFailureReason`, including invalid Party, inactive Site, invalid direction and out-of-bounds movement; no localization or UI string is returned by the Runtime boundary.
- `TravelRuntime.query_travel_preview()` is read-only with respect to Party position, World Time, active Travel State and Region runtime state. Its pathfinder/cache internals may change.
- Travel Preview keeps one query-scoped `RegionStateResolver` per visited World Cell; the cache is discarded after the query and cannot survive as gameplay state.
- `TravelRuntime.start_travel()` re-runs the query from `party_id` and destination, then creates the authoritative Session travel path. Presentation never submits a preview path as authority.
- `TravelRuntime.cancel_travel()` owns cancellation state; `commit_travel_step()` owns Party position, path index and World Time updates; `finish_travel()` owns completion/cleanup.
- `GameSession` stores typed `travel_failure_reason` and `last_travel_status`; map Presentation converts those codes into display labels. Runtime no longer writes travel UI messages into Session.
- `TravelRuntime.query_site_entry()` owns exact POI eligibility. NavigationController loads the approved Site view and routes `SiteMap.move_requested` to the Runtime movement command without deciding movement validity.
- `TravelPreviewResult`, `TravelCommandResult`, `TravelCellResult`, `SiteEntryQueryResult`, `TravelStepResult`, and `TravelFailureReason` contain typed runtime data/reasons, not localized UI strings.
- `TravelRuntime` obtains resolved deterministic Terrain/Road data through `RegionRuntime` and `WorldData`; `RegionMap` no longer supplies mutable Travel calculation context or accepts a `PartyPathResult`.
- `RegionMap`, `WorldMap`, and `SiteMap` contain no direct `PartyPathfinder`, `TravelCostConfig`, or Site eligibility calls. NavigationController contains no direct Pathfinder/Travel Cost calls.
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
- `runtime_command_query_test.gd`: 18/18 PASS.
- `site_runtime_test.gd`: 34/34 PASS, including deterministic Site Seed/base/layout reconstruction, fixed 50×50/2m bounds aligned to one Region Strategic Cell, typed cardinal/bounds movement, WASD input-to-Runtime routing, detached read-only snapshots, Scene re-entry stability, and one-way generator/runtime/presentation dependencies.
- `architecture_smoke_test.gd`: PASS.
- `cross_region_runtime_test.gd`: Global travel and cancel runtime PASS.
- Existing tests: Coordinate 4/4, Terrain 9/9, POI 10/10, Road 12/12, Party movement 16/16, Cross-Region Travel 18/18, Region Seed + Delta 22/22 PASS. Runtime command/query also covers a shared cross-Region Preview Query.
- Party movement still reports a Godot ObjectDB/resource cleanup warning at process shutdown; POI teardown is clean after releasing its temporary SiteMap. Party gameplay assertions and exit code are successful. This remaining warning is a test-harness cleanup gap, not a persistent runtime gameplay error.
- `persistence_test.gd`: 10/10 PASS for Session round-trip, Region Delta reconstruction, active Travel/Site rejection, corrupt/version/data validation, view-state exclusion, Presentation dependency scan, and Navigation Session replacement.
- `battle_site_test.gd`: 20/20 PASS for nine-Site composition, typed/read-only preview queries, PC/NPC commander authority, delayed simple orders, fine-order delivery, messenger interception, captain-autonomy data, 100-person Formation geometry, active Formation path/movement commands, 9,000-person GPU-instance rendering, input validation, Region boundary resolution, Region Delta projection, typed failures, detached snapshots, Presentation dependency separation, deterministic regeneration, and Region/Battle Scene replacement.
- `region_construction_test.gd`: 13/13 PASS for read-only preview, typed validation, command revalidation, sparse place/remove, stable IDs, detached resolved data, Scene replacement, Persistence round-trip, and one-way Runtime/Presentation dependencies.

## Not implemented by design

Semantic Site content, per-cell terrain/collision data, pathfinding, movement time/animation, Site-local Party position persistence, Site Runtime persistence, active Travel persistence, and Save UI are NOT IMPLEMENTED. The generated Site layout contains only the fixed grid scale, bounds and visual anchor points; it does not define buildings, resources, NPCs, collision, or gameplay rules. Region Construction currently supports only immediate Outpost place/remove with no cost or gameplay effect; roads, walls, farms, build time, workers and Site construction are NOT IMPLEMENTED. The current Battle Site is a deterministic read-only debug preview, not Combat. Exploration rules, settlement gameplay, economy, characters, paper doll, combat runtime/resolution, NPC, AI, events, weather, quests, migrations, and multi-slot saves remain future work. Their absence is not treated as a missing architecture skeleton when the current contract has a clear owner boundary.
