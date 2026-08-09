# Worldgoing Architecture Contract

`PROJECT_ARCHITECTURE.md` is the source of truth. This file records the current implementation boundary and does not replace or extend that document's design.

## Module contracts

| Module | Responsibility | Owns what data | Can depend on | Must not depend on | Status |
| --- | --- | --- | --- | --- | --- |
| Coordinates / deterministic core | Coordinate conversion, deterministic hashing, shared travel cost, bounded path algorithms | No session or player state | Data value types and shared constants | Scenes, TileMap, UI | Implemented |
| World data | Region index, generated terrain/POI/road access, deterministic caches | `RegionData`, generated `RegionTerrainData`, POI and road cache entries | Generators, data types, core utilities | Party, World Time, Scene nodes, UI, Region Delta | Implemented; cache is non-authoritative and rebuildable |
| Region data | Regenerable 100×100 strategic data, derived Region seed, generated feature references | `RegionData.seed`, frozen base terrain, generated POI/route IDs | Coordinates and generator output | TileMap, presentation state, session mutation | Implemented |
| Region runtime | Mutable Region state that must survive view replacement | `RegionRuntimeState`, `RegionDelta`, discovery placeholder | Session-owned state types, Region Runtime/Resolver | Generators, TileMap, UI as state owners | Implemented; gameplay mutation is test-only |
| Site definition | Stable Site identity and deterministic Site context derived from a Region POI | `SiteData`, with `site_id == WorldPOIData.poi_id` | `WorldPOIData`, WorldData, coordinate/data types | Runtime mutation, Scene nodes, UI | Implemented; no Site gameplay data |
| Session runtime | Run-lifetime Party, World Time, selected layer context, travel plan, Region and Site runtime states | `GameSession`, `PartyData`, travel state, `RegionRuntimeState` map, lazy `SiteRuntimeState` map | Data and core services | View nodes, TileMap, Sprite | Implemented |
| Site runtime | Sparse mutable Site state, revision and detached snapshots | `SiteRuntimeState`: test flag, added/removed stable feature records | SiteData, Session, typed Site query/command results | SiteMap, RegionMap, generators, UI, localization | Implemented as a minimal test-only contract |
| Runtime travel API | Typed travel query/command results, path/cost decisions, Site Entry Query, Site runtime query/commands, authoritative travel step mutation | Operates `GameSession` through its API; no duplicate manager state | Session, WorldData, core travel services, typed result data | Map scenes, Camera, TileMap, UI | Implemented as `TravelRuntime` |
| Runtime navigation | Composes World/Region/Site views and runs the existing travel loop | Active view reference only; authoritative state stays in Session/WorldData/TravelRuntime | Session, WorldData, TravelRuntime, map scene contracts | Pathfinder, Travel Cost, gameplay eligibility decisions | Implemented; map animation is an optional view contract |
| Presentation | Draw maps, camera, hover/preview/visual interpolation, Debug UI | View-only hover, preview and visual positions | Session/data snapshots, Runtime query/command results and signals | Pathfinder, Travel Cost, authoritative Party/World Time mutation | Implemented |
| Persistence | Future Seed + Delta save/load boundary | Not implemented | Session/runtime snapshots and generated data versions | Scene nodes and presentation state | NOT IMPLEMENTED |

## World → Region → Site

- `WorldData.regions` is the World-owned index of Region definitions. The current `RegionData.world_cell` is the implementation name for the document's Region coordinate.
- A Region seed is derived only from `world_seed`, `world_cell`, and the terrain generation version through `RegionData.derive_seed()`; runtime RNG order and scene instances are not inputs.
- `RegionData` records deterministic identity and generated base/cache references. `RegionData.terrain_data` is frozen after generation; clearing the cache removes only the rebuildable object.
- `PartyData.current_global_region_cell` is the single authoritative Party position. World/Region cells are derived with `WorldCoordinates`.
- `GameSession` owns World Time, travel plan/progress, and Region runtime state, so replacing `WorldMap`, `RegionMap`, or `SiteMap` does not erase them.
- `WorldPOIData` is the generated Region-level Site entry. `SiteMap` receives that entry and the parent Region context; it does not become a second world or region state owner.
- `SiteData` is derived from the stable `WorldPOIData.poi_id`; it carries Site definition/context only and does not contain mutable gameplay state.
- `GameSession.site_runtime_states` lazily owns `SiteRuntimeState` by `site_id`. A Site query can return an unallocated detached snapshot; entering or mutating a Site allocates its runtime state.
- `SiteRuntimeState` stores only the current architecture contract: revision, test flag, added test feature records and removed stable feature IDs. It contains no Node, Scene or presentation reference.
- `SiteMap` receives a `SiteRuntimeSnapshot` from `TravelRuntime` and is a view. Different SiteMap instances for the same `site_id` consume the same Session-owned state.

## Generator / runtime / presentation boundary

- `RegionTerrainGenerator`, `WorldPOIGenerator`, and `WorldRoadGenerator` are deterministic generators. They contain no Party, discovery, construction, combat, quest, or view state and never read TileMap nodes.
- `WorldData` may cache generated results for performance. Clearing those caches must not change results.
- `GameSession` owns `RegionRuntimeState` instances; each state owns a sparse `RegionDelta`. `RegionStateResolver` is the only Base + Delta read path.
- `GameSession` and `RegionRuntimeState` hold mutable run state. No map Scene is required to keep Party position, World Time, travel progress, or Region runtime fields alive.
- `TravelRuntime.query_site_snapshot()` is read-only and returns copied Site collections; Site commands validate Site identity and update revision only on real mutations.
- Map Scenes and `DebugUI` consume data and session state. Their hover, preview, camera, and interpolation fields are presentation state only.

## Audit status

### Site runtime completion

The Site layer now has stable POI-backed definitions, lazy Session-owned runtime state, detached snapshots, typed query/command results, and 24 focused architecture tests. Site generation, grid/cell simulation, gameplay mutation, and persistence remain intentionally outside this stage.

- A — Skeleton complete: three map Scenes, coordinate contract, deterministic terrain/POI/road generation, and existing Party/Travel/World Time test coverage are present; Main and Runtime smoke now pass with the normal Godot CLI user/cache environment.
- B — Corrected: Region mutable ownership was separated from `RegionData`; `RegionData.seed` is now the generated-cache seed contract.
- C — Corrected minimally: added `RegionRuntimeState`, Session accessor, and this contract file. No speculative feature modules were added.
- D — No duplicate Manager/Singleton system. `SiteData` is a static data type; the live Region Site entry is `WorldPOIData`.
- E — Corrected: Runtime navigation no longer reads `RegionMap`'s visual duration constant; the view owns animation timing through an optional method contract.
- F — Corrected: `TravelRuntime` now owns `PartyPathfinder` and Travel Cost calls. `RegionMap` and `WorldMap` use the shared typed Travel Preview Query and Start Travel Command; `SiteMap` and NavigationController use the typed Site Entry Query. The old RegionMap `PartyPathResult` bridge and view-injected Travel context were removed.
- G — Complete: generators hold only deterministic generator/cache state, never player mutable state.
- H — Complete for current state: Party/World Time/Travel are Session-owned; Region mutable fields are `RegionRuntimeState`-owned.
- I — Smoke coverage added for World/Region view replacement. Site gameplay persistence is not implemented because Site gameplay is a future phase.
- J — Future module boundaries are documented above; no future gameplay feature was implemented.
- K — Added `scripts/tests/runtime_command_query_test.gd` with the 16 requested boundary checks. Editor parse, static dependency scans, headless Main startup, and the Runtime command/query tests pass with writable Godot user/cache directories. The managed sandbox's prior signal 11 is an environment limitation, not a project dependency.
- L — Added `RegionDelta`, `RegionStateResolver`, and `RegionRuntime` for the in-session Seed + Delta contract. `scripts/tests/region_seed_delta_test.gd` contains the 20 requested reconstruction/boundary checks.

## Runtime command/query boundary

- `TravelRuntime.query_site_snapshot()` is the Site read boundary. `ensure_site_runtime_state()`, `set_site_test_flag()`, `add_site_test_feature()`, and `remove_site_test_feature()` are typed Site commands; `SiteMap` only consumes the returned `SiteRuntimeSnapshot`.
- Site runtime commands re-resolve the deterministic POI definition by `site_id`, reject identity mismatch, reject duplicate features, and do not trust or mutate a Presentation-held snapshot.
- Site runtime failure codes are typed in `SiteRuntimeFailureReason`; no localization or UI string is returned by the Runtime boundary.
- `TravelRuntime.query_travel_preview()` is read-only with respect to Party position, World Time, active Travel State and Region runtime state. Its pathfinder/cache internals may change.
- `TravelRuntime.start_travel()` re-runs the query from `party_id` and destination, then creates the authoritative Session travel path. Presentation never submits a preview path as authority.
- `TravelRuntime.cancel_travel()` owns cancellation state; `commit_travel_step()` owns Party position, path index and World Time updates; `finish_travel()` owns completion/cleanup.
- `GameSession` stores typed `travel_failure_reason` and `last_travel_status`; map Presentation converts those codes into display labels. Runtime no longer writes travel UI messages into Session.
- `TravelRuntime.query_site_entry()` owns exact POI eligibility. NavigationController only loads the approved Site view.
- `TravelPreviewResult`, `TravelCommandResult`, `TravelCellResult`, `SiteEntryQueryResult`, `TravelStepResult`, and `TravelFailureReason` contain typed runtime data/reasons, not localized UI strings.
- `TravelRuntime` obtains resolved deterministic Terrain/Road data through `RegionRuntime` and `WorldData`; `RegionMap` no longer supplies mutable Travel calculation context or accepts a `PartyPathResult`.
- `RegionMap`, `WorldMap`, and `SiteMap` contain no direct `PartyPathfinder`, `TravelCostConfig`, or Site eligibility calls. NavigationController contains no direct Pathfinder/Travel Cost calls.
- `RegionRuntime.query_region()` returns resolved Base + Delta queries. Its test-only mutation commands own terrain override, feature add/remove, and Region value changes; map scenes do not write `RegionDelta`.

## Corrective logic closure

- `TravelRuntime.finish_travel()` now verifies the active path, committed path index, and authoritative Party destination before marking `ARRIVED`; incomplete or stale steps cannot clear travel as an arrival.
- `TravelRuntime.fail_travel()` records typed failure and clears a broken active plan as `FAILED`; `NavigationController` uses it when a travel step cannot be committed.
- Active cancellation is finalized by `TravelRuntime` and emits the typed `travel_cancelled` signal after Session cleanup.
- Travel pathfinding and `query_travel_cell()` now consume a Runtime-owned resolved Base + Region Delta cell provider. Direct generator sampling remains available for deterministic data tests, while active Runtime travel rejects cells outside the finite WorldData bounds.
- `RegionRuntime.query_region()` is read-only with respect to Session allocation; mutable Region state is created only by mutation commands.
- `WorldRoadGenerator` enforces connection limits against both source and candidate total degree, including deterministic fallback edges.
- `RegionMap` redraws its custom Party presentation while the visual tween changes its view-only position; authoritative Party position remains Session-owned.
- Added focused regression coverage for terminal Travel guards, cancellation signaling, non-allocating Region queries, and Delta-aware Travel cell queries. No gameplay feature was added.

## Region Seed + Delta Contract

- `RegionData.derive_seed(world_seed, world_cell, generation_version)` is the single Region seed derivation. The existing shared world-field generators remain unchanged, so neighboring Region slices still meet at global cell boundaries.
- `RegionData` owns deterministic identity and generated base/cache references only: source world seed, derived seed, generation version, frozen terrain, generated POI IDs, and generated route IDs. It does not own owner, development, construction, removal, camera, hover, preview, or animation state.
- `RegionRuntimeState` is session-owned. Its `RegionDelta` stores only sparse terrain overrides, added feature records, removed/disabled stable feature IDs, owner/development values, base generation version, and revision. Discovery remains the existing placeholder and is not expanded here.
- `RegionStateResolver` validates Region identity and base generation version before exposing `get_terrain()`, feature queries, owner, and development. A mismatch reports `DELTA_REGION_MISMATCH` or `DELTA_BASE_VERSION_MISMATCH` and is not silently applied.
- Generated POIs use their existing stable `poi_id`; generated roads use their existing stable `route_id`. Delta never stores Node IDs, array indexes, or scene paths.
- `WorldData.clear_generated_cache()` clears only generated base/cache objects. The same Seed plus a copied Delta reconstructs the same resolved query. No Disk Save/Load or serializer was added.

## Verification status

- Static command/query and Runtime dependency scans: PASS; Runtime has no Map/UI symbols and Presentation has no Pathfinder/Travel Cost symbols.
- Site runtime dependency and ownership scans: PASS; `SiteRuntimeState` has no Presentation dependency, map scenes do not own the Site state dictionary, and NavigationController delegates Site state to `TravelRuntime`.
- `Godot --headless --editor --recovery-mode --quit`: project script/class scan PASS. Godot Mono emits a known editor-only `HotReloadAssemblyWatcher` timer message during headless editor shutdown; no project script parse error was reported.
- Main headless startup with `--rendering-method gl_compatibility`: PASS, exit 0.
- `runtime_command_query_test.gd`: 18/18 PASS.
- `site_runtime_test.gd`: 24/24 PASS.
- `architecture_smoke_test.gd`: PASS.
- `cross_region_runtime_test.gd`: Global travel and cancel runtime PASS.
- Existing tests: Coordinate 4/4, Terrain 9/9, POI 10/10, Road 12/12, Party movement 16/16, Cross-Region Travel 18/18, Region Seed + Delta 22/22 PASS. Runtime command/query also covers a shared cross-Region Preview Query.
- Party movement still reports a Godot ObjectDB/resource cleanup warning at process shutdown; POI teardown is clean after releasing its temporary SiteMap. Party gameplay assertions and exit code are successful. This remaining warning is a test-harness cleanup gap, not a persistent runtime gameplay error.

## Not implemented by design

Site generation/grid/cell simulation, Site gameplay, discovery gameplay, Site delta serialization and Save/Load are NOT IMPLEMENTED. Exploration rules, construction, settlement gameplay, economy, characters, paper doll, combat, NPC, AI, events, weather, and quests remain future work. Their absence is not treated as a missing architecture skeleton when the current contract has a clear owner boundary.
