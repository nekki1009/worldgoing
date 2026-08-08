# Worldgoing Architecture Contract

`PROJECT_ARCHITECTURE.md` is the source of truth. This file records the current implementation boundary and does not replace or extend that document's design.

## Module contracts

| Module | Responsibility | Owns what data | Can depend on | Must not depend on | Status |
| --- | --- | --- | --- | --- | --- |
| Coordinates / deterministic core | Coordinate conversion, deterministic hashing, shared travel cost, bounded path algorithms | No session or player state | Data value types and shared constants | Scenes, TileMap, UI | Implemented |
| World data | Region index, generated terrain/POI/road access, deterministic caches | `RegionData`, generated `RegionTerrainData`, POI and road cache entries | Generators, data types, core utilities | Party, World Time, Scene nodes, UI | Implemented; cache is non-authoritative and rebuildable |
| Region data | Regenerable 100×100 strategic data and region seed | `RegionData.seed`, terrain data, generated road overlay | Coordinates and generator output | TileMap, presentation state, session mutation | Implemented |
| Region runtime | Mutable Region state that must survive view replacement | `RegionRuntimeState` and its future delta/discovery fields | Session-owned state types | Generators, TileMap, UI | Minimal boundary added; gameplay mutation is not implemented |
| Site entry / Site data | Region-to-Site entry context and future Site-local definitions | `WorldPOIData` entry data; `SiteData` remains static Site-local data | World/Region data types | Camera, Sprite, UI as state owners | Entry context implemented; Site gameplay is not implemented |
| Session runtime | Run-lifetime Party, World Time, selected layer context, travel plan, Region runtime states | `GameSession`, `PartyData`, travel state, `RegionRuntimeState` map | Data and core services | View nodes, TileMap, Sprite | Implemented |
| Runtime navigation | Composes World/Region/Site views and runs the existing travel loop | Active view reference only; authoritative state stays in Session/WorldData | Session, WorldData, map scene contracts | Generator-owned player state; direct visual constants | Implemented; map animation is now an optional view contract |
| Presentation | Draw maps, camera, hover/preview/visual interpolation, Debug UI | View-only hover, preview and visual positions | Session/data snapshots and runtime signals | Authoritative Party position, World Time, generated data mutation | Implemented |
| Persistence | Future Seed + Delta save/load boundary | Not implemented | Session/runtime snapshots and generated data versions | Scene nodes and presentation state | NOT IMPLEMENTED |

## World → Region → Site

- `WorldData.regions` is the World-owned index of Region definitions. The current `RegionData.world_cell` is the implementation name for the document's Region coordinate.
- A Region is generated from the world seed plus its coordinate; `RegionData.seed` records the seed used by its generated cache.
- `PartyData.current_global_region_cell` is the single authoritative Party position. World/Region cells are derived with `WorldCoordinates`.
- `GameSession` owns World Time, travel plan/progress, and Region runtime state, so replacing `WorldMap`, `RegionMap`, or `SiteMap` does not erase them.
- `WorldPOIData` is the generated Region-level Site entry. `SiteMap` receives that entry and the parent Region context; it does not become a second world or region state owner.

## Generator / runtime / presentation boundary

- `RegionTerrainGenerator`, `WorldPOIGenerator`, and `WorldRoadGenerator` are deterministic generators. They contain no Party, discovery, construction, combat, quest, or view state and never read TileMap nodes.
- `WorldData` may cache generated results for performance. Clearing those caches must not change results.
- `GameSession` and `RegionRuntimeState` hold mutable run state. No map Scene is required to keep Party position, World Time, travel progress, or Region runtime fields alive.
- Map Scenes and `DebugUI` consume data and session state. Their hover, preview, camera, and interpolation fields are presentation state only.

## Audit status

- A — Skeleton complete: three map Scenes, coordinate contract, deterministic terrain/POI/road generation, and existing Party/Travel/World Time test coverage are present; runtime pass is environment-blocked in this checkout.
- B — Corrected: Region mutable ownership was separated from `RegionData`; `RegionData.seed` is now the generated-cache seed contract.
- C — Corrected minimally: added `RegionRuntimeState`, Session accessor, and this contract file. No speculative feature modules were added.
- D — No duplicate Manager/Singleton system. `SiteData` is a static data type; the live Region Site entry is `WorldPOIData`.
- E — Corrected: Runtime navigation no longer reads `RegionMap`'s visual duration constant; the view owns animation timing through an optional method contract.
- F — Remaining boundary: map input still owns preview UI state and calls the existing `PartyPathfinder` helper. It does not own Party/Time/travel state; a larger command/query split is deferred until a gameplay requirement needs it.
- G — Complete: generators hold only deterministic generator/cache state, never player mutable state.
- H — Complete for current state: Party/World Time/Travel are Session-owned; Region mutable fields are `RegionRuntimeState`-owned.
- I — Smoke coverage added for World/Region view replacement. Site gameplay persistence is not implemented because Site gameplay is a future phase.
- J — Future module boundaries are documented above; no future gameplay feature was implemented.

## Not implemented by design

Exploration rules, construction, settlement gameplay, economy, characters, paper doll, combat, NPC, AI, events, weather, quests, and Save/Load are future work. Their absence is not treated as a missing architecture skeleton when the current contract has a clear owner boundary.
