extends SceneTree

const TEST_SEED: int = 123456789
const REGION_CELL: Vector2i = Vector2i(3, 4)

var world_data: WorldData
var session: GameSession
var region_runtime: RegionRuntime

func _init() -> void:
	_test_empty_delta()
	_test_terrain_override()
	_test_clear_override()
	_test_base_immutable()
	_test_feature_add()
	_test_added_feature_remove()
	_test_generated_poi_disable()
	_test_runtime_values()
	_test_revision()
	_test_wrong_region()
	_test_generation_version()
	_test_reconstruction()
	_test_scene_replacement()
	_test_no_tilemap_authority()
	_test_no_presentation_dependency()
	_test_sparse_storage()
	_test_coordinate_validation()
	_test_deterministic_base()
	_test_command_boundary()
	_test_query_does_not_allocate_runtime_state()
	_test_delta_affects_travel_query()
	_test_existing_runtime_regression()
	print("Region Seed + Delta tests passed: 22 cases")
	quit()

func _test_empty_delta() -> void:
	_reset()
	var base: RegionTerrainData = _base_terrain()
	var resolved: RegionStateResolver = region_runtime.query_region(REGION_CELL)
	assert(resolved.is_valid(), "Empty Delta did not resolve")
	for cell: Vector2i in _sample_cells():
		assert(resolved.get_terrain(cell) == base.get_terrain(cell), "Empty Delta changed base terrain")
	print("TEST 1 PASS: Empty Delta equals generated Base")

func _test_terrain_override() -> void:
	_reset()
	var base: RegionTerrainData = _base_terrain()
	var cell: Vector2i = _find_terrain(base, TerrainType.FOREST)
	assert(cell != Vector2i(-1, -1), "No Forest cell found")
	assert(region_runtime.apply_test_terrain_override(REGION_CELL, cell, TerrainType.PLAINS), "Terrain override was rejected")
	var resolved: RegionStateResolver = region_runtime.query_region(REGION_CELL)
	assert(resolved.get_terrain(cell) == TerrainType.PLAINS, "Terrain override was not resolved")
	var snapshot: PackedByteArray = resolved.get_terrain_snapshot()
	var cell_index: int = cell.y * WorldCoordinates.REGION_GRID_SIZE + cell.x
	assert(snapshot[cell_index] == TerrainType.PLAINS, "Terrain snapshot omitted the sparse override")
	snapshot[cell_index] = TerrainType.MOUNTAIN
	assert(resolved.get_terrain(cell) == TerrainType.PLAINS, "Terrain snapshot exposed authoritative state")
	assert(base.get_terrain(cell) == TerrainType.FOREST, "Terrain override modified Base")
	print("TEST 2 PASS: Sparse Terrain Override resolves without changing Base")

func _test_clear_override() -> void:
	_reset()
	var base: RegionTerrainData = _base_terrain()
	var cell: Vector2i = _sample_cells()[0]
	var original: int = base.get_terrain(cell)
	assert(region_runtime.apply_test_terrain_override(REGION_CELL, cell, (original + 1) % 4), "Terrain override setup failed")
	assert(region_runtime.clear_test_terrain_override(REGION_CELL, cell), "Terrain override clear was rejected")
	assert(region_runtime.query_region(REGION_CELL).get_terrain(cell) == original, "Cleared override did not reveal Base")
	print("TEST 3 PASS: Clearing an override restores Base")

func _test_base_immutable() -> void:
	_reset()
	var base: RegionTerrainData = _base_terrain()
	var before: int = _hash_bytes(base.terrain_array)
	for index: int in range(10):
		var cell: Vector2i = Vector2i(index, index + 1)
		region_runtime.apply_test_terrain_override(REGION_CELL, cell, (base.get_terrain(cell) + 1) % 4)
	assert(_hash_bytes(base.terrain_array) == before, "Applying Delta changed Base hash")
	assert(base.is_frozen, "Generated Base terrain was not frozen")
	print("TEST 4 PASS: Ten overrides leave Base immutable")

func _test_feature_add() -> void:
	_reset()
	assert(region_runtime.apply_test_feature_add(
		REGION_CELL,
		"test_feature_001",
		&"test",
		Vector2i(20, 30),
		{"source": "test"}
	), "Feature add was rejected")
	assert(_has_feature(region_runtime.query_region(REGION_CELL).get_features_at(Vector2i(20, 30)), "test_feature_001"), "Added feature was not resolved")
	print("TEST 5 PASS: Feature Add is visible in Resolved Query")

func _test_added_feature_remove() -> void:
	_reset()
	var cell: Vector2i = Vector2i(20, 30)
	assert(region_runtime.apply_test_feature_add(REGION_CELL, "test_feature_001", &"test", cell), "Feature add setup failed")
	assert(region_runtime.apply_test_feature_remove(REGION_CELL, "test_feature_001"), "Added feature remove was rejected")
	assert(not region_runtime.query_region(REGION_CELL).has_feature("test_feature_001"), "Removed added feature remained resolved")
	assert(session.get_region_runtime_state(REGION_CELL).delta.removed_feature_ids.is_empty(), "Added feature created an unnecessary tombstone")
	print("TEST 6 PASS: Delta-added Feature Remove is reversible and sparse")

func _test_generated_poi_disable() -> void:
	_reset()
	var pois: Array[WorldPOIData] = world_data.get_pois_for_region(REGION_CELL, TEST_SEED)
	assert(not pois.is_empty(), "No deterministic POI found")
	var poi: WorldPOIData = pois[0]
	assert(region_runtime.apply_test_feature_remove(REGION_CELL, poi.poi_id), "Generated POI disable was rejected")
	var resolved: RegionStateResolver = region_runtime.query_region(REGION_CELL)
	assert(not resolved.has_feature(poi.poi_id), "Disabled POI remained in Resolved Query")
	assert(_has_poi(world_data.get_pois_for_region(REGION_CELL, TEST_SEED), poi.poi_id), "Generated POI disappeared from Base generator")
	print("TEST 7 PASS: Stable generated POI ID disables only the Resolved feature")

func _test_runtime_values() -> void:
	_reset()
	var state: RegionRuntimeState = session.get_region_runtime_state(REGION_CELL)
	state.owner_id = "player"
	state.development_level = 3
	var resolved: RegionStateResolver = region_runtime.query_region(REGION_CELL)
	assert(resolved.get_owner() == "player" and resolved.get_development_level() == 3, "Mutable Region values did not resolve")
	assert(not _source_contains("scripts/data/region_data.gd", "owner_id"), "RegionData owns mutable owner state")
	print("TEST 8 PASS: Owner and Development live in Region Delta")

func _test_revision() -> void:
	_reset()
	var delta: RegionDelta = session.get_region_runtime_state(REGION_CELL).delta
	var initial: int = delta.revision
	assert(not delta.set_terrain_override(Vector2i(-1, 20), TerrainType.PLAINS), "Invalid mutation was accepted")
	assert(delta.revision == initial, "Invalid mutation changed revision")
	var cell: Vector2i = Vector2i(0, 0)
	var target: int = (_base_terrain().get_terrain(cell) + 1) % 4
	assert(delta.set_terrain_override(cell, target), "Valid mutation was rejected")
	assert(delta.revision == initial + 1, "Valid mutation did not increment revision")
	assert(not delta.set_terrain_override(cell, target), "Same-value mutation was not ignored")
	assert(delta.revision == initial + 1, "Same-value mutation incremented revision")
	print("TEST 9 PASS: Revision changes only on real mutation")

func _test_wrong_region() -> void:
	_reset()
	var base_region: RegionData = world_data.get_region(REGION_CELL)
	var delta: RegionDelta = RegionDelta.new(Vector2i(4, 4), RegionTerrainGenerator.GENERATION_VERSION)
	var resolver: RegionStateResolver = RegionStateResolver.new(
		base_region,
		_base_terrain(),
		world_data.get_pois_for_region(REGION_CELL, TEST_SEED),
		world_data.get_roads_for_region(REGION_CELL, TEST_SEED),
		delta,
		RegionTerrainGenerator.GENERATION_VERSION
	)
	assert(not resolver.is_valid() and resolver.failure_code == &"DELTA_REGION_MISMATCH", "Wrong Region Delta was silently applied")
	print("TEST 10 PASS: Region identity mismatch is reported")

func _test_generation_version() -> void:
	_reset()
	var bad_delta: RegionDelta = RegionDelta.new(REGION_CELL, RegionTerrainGenerator.GENERATION_VERSION + 1)
	var resolver: RegionStateResolver = RegionStateResolver.new(
		world_data.get_region(REGION_CELL),
		_base_terrain(),
		world_data.get_pois_for_region(REGION_CELL, TEST_SEED),
		world_data.get_roads_for_region(REGION_CELL, TEST_SEED),
		bad_delta,
		RegionTerrainGenerator.GENERATION_VERSION
	)
	assert(not resolver.is_valid() and resolver.failure_code == &"DELTA_BASE_VERSION_MISMATCH", "Generation version mismatch was not detected")
	print("TEST 11 PASS: Delta generation version mismatch is explicit")

func _test_reconstruction() -> void:
	_reset()
	var cell: Vector2i = Vector2i(20, 30)
	region_runtime.apply_test_terrain_override(REGION_CELL, cell, TerrainType.PLAINS)
	region_runtime.apply_test_feature_add(REGION_CELL, "rebuild_feature", &"test", cell)
	session.get_region_runtime_state(REGION_CELL).owner_id = "player"
	var snapshot: RegionDelta = session.get_region_runtime_state(REGION_CELL).delta.copy()
	var first_hash: int = _resolved_hash(region_runtime.query_region(REGION_CELL))
	world_data.clear_generated_cache()
	var rebuilt_session: GameSession = GameSession.new()
	rebuilt_session.world_seed = TEST_SEED
	rebuilt_session.get_region_runtime_state(REGION_CELL).delta = snapshot.copy()
	var rebuilt_runtime: RegionRuntime = RegionRuntime.new(rebuilt_session, world_data)
	assert(_resolved_hash(rebuilt_runtime.query_region(REGION_CELL)) == first_hash, "Seed + Delta reconstruction changed Resolved result")
	print("TEST 12 PASS: Clearing generated cache and rebuilding from Seed + Delta is identical")

func _test_scene_replacement() -> void:
	_reset()
	var cell: Vector2i = Vector2i(20, 30)
	region_runtime.apply_test_terrain_override(REGION_CELL, cell, TerrainType.PLAINS)
	var state_before: RegionRuntimeState = session.get_region_runtime_state(REGION_CELL)
	region_runtime.query_region(Vector2i(2, 2))
	region_runtime.clear_region_context()
	var state_after: RegionRuntimeState = session.get_region_runtime_state(REGION_CELL)
	assert(state_before == state_after and region_runtime.query_region(REGION_CELL).get_terrain(cell) == TerrainType.PLAINS, "Region replacement lost Delta")
	print("TEST 13 PASS: Region Delta survives view/context replacement")

func _test_no_tilemap_authority() -> void:
	_reset()
	var base: RegionTerrainData = _base_terrain()
	var cell: Vector2i = Vector2i(20, 30)
	region_runtime.apply_test_terrain_override(REGION_CELL, cell, TerrainType.PLAINS)
	assert(not base.set_terrain(cell, TerrainType.MOUNTAIN), "Generated Base accepted a visual-style mutation")
	assert(region_runtime.query_region(REGION_CELL).get_terrain(cell) == TerrainType.PLAINS, "Visual/Base mutation changed Resolved Delta")
	print("TEST 14 PASS: Tile/visual data is not Delta authority")

func _test_no_presentation_dependency() -> void:
	_reset()
	var resolver: RegionStateResolver = region_runtime.query_region(REGION_CELL)
	assert(resolver.is_valid(), "Resolver required RegionMap presentation")
	assert(not _source_contains("scripts/runtime/region_runtime.gd", "RegionMap"), "Region Runtime depends on RegionMap")
	assert(not _source_contains("scripts/runtime/region_state_resolver.gd", "Node2D"), "Resolver depends on a Scene Node")
	print("TEST 15 PASS: Base + Delta + Resolver run without Presentation")

func _test_sparse_storage() -> void:
	_reset()
	var delta: RegionDelta = session.get_region_runtime_state(REGION_CELL).delta
	for cell: Vector2i in [Vector2i(1, 1), Vector2i(50, 50), Vector2i(99, 99)]:
		delta.set_terrain_override(cell, TerrainType.PLAINS)
	assert(delta.terrain_override_count() == 3, "Sparse Delta stored more than changed Cells")
	print("TEST 16 PASS: Three Cell changes use three sparse overrides")

func _test_coordinate_validation() -> void:
	_reset()
	var delta: RegionDelta = session.get_region_runtime_state(REGION_CELL).delta
	assert(not delta.set_terrain_override(Vector2i(-1, 20), TerrainType.PLAINS), "Negative Cell was accepted")
	assert(not delta.set_terrain_override(Vector2i(100, 20), TerrainType.PLAINS), "Out-of-range Cell was accepted")
	assert(delta.set_terrain_override(Vector2i(0, 0), TerrainType.PLAINS), "Cell (0,0) was rejected")
	assert(delta.set_terrain_override(Vector2i(99, 99), TerrainType.FOREST), "Cell (99,99) was rejected")
	print("TEST 17 PASS: Region Cell bounds are enforced")

func _test_deterministic_base() -> void:
	_reset()
	var expected_seed: int = RegionData.derive_seed(TEST_SEED, REGION_CELL, RegionTerrainGenerator.GENERATION_VERSION)
	assert(expected_seed == RegionData.derive_seed(TEST_SEED, REGION_CELL, RegionTerrainGenerator.GENERATION_VERSION), "Region seed derivation is not deterministic")
	_base_terrain()
	assert(world_data.get_region(REGION_CELL).seed == expected_seed, "RegionData did not record the derived Region seed")
	var terrain_before: int = _hash_bytes(_base_terrain().terrain_array)
	var pois_before: String = _poi_signature(world_data.get_pois_for_region(REGION_CELL, TEST_SEED))
	var roads_before: String = _route_signature(world_data.get_route_edges_for_region(REGION_CELL, TEST_SEED))
	region_runtime.apply_test_terrain_override(REGION_CELL, Vector2i(20, 30), TerrainType.PLAINS)
	region_runtime.apply_test_feature_remove(REGION_CELL, "nonexistent_generated_feature")
	world_data.clear_generated_cache()
	assert(_hash_bytes(_base_terrain().terrain_array) == terrain_before, "Delta changed deterministic Terrain output")
	assert(_poi_signature(world_data.get_pois_for_region(REGION_CELL, TEST_SEED)) == pois_before, "Delta changed deterministic POI output")
	assert(_route_signature(world_data.get_route_edges_for_region(REGION_CELL, TEST_SEED)) == roads_before, "Delta changed deterministic Road output")
	print("TEST 18 PASS: Delta does not alter deterministic generators")

func _test_command_boundary() -> void:
	_reset()
	var region_source: String = FileAccess.get_file_as_string("res://scripts/region/region_map.gd")
	assert(not region_source.contains("RegionDelta") and not region_source.contains("delta."), "RegionMap bypasses Region Runtime mutation boundary")
	print("TEST 19 PASS: RegionMap uses Runtime/Resolved Query boundary")

func _test_query_does_not_allocate_runtime_state() -> void:
	_reset()
	assert(session.find_region_runtime_state(REGION_CELL) == null, "Region test started with an allocated runtime state")
	var resolver: RegionStateResolver = region_runtime.query_region(REGION_CELL)
	assert(resolver.is_valid(), "Region query without runtime state failed")
	assert(session.find_region_runtime_state(REGION_CELL) == null, "Read-only Region query allocated runtime state")
	print("TEST 20 PASS: Region query does not allocate mutable runtime state")

func _test_delta_affects_travel_query() -> void:
	_reset()
	var overridden_cell: Vector2i = Vector2i(20, 30)
	assert(region_runtime.apply_test_terrain_override(REGION_CELL, overridden_cell, TerrainType.WATER), "Travel Delta setup failed")
	var session_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(REGION_CELL, overridden_cell)
	session.party.initialized = true
	session.party.set_global_region_cell(session_cell)
	var travel_runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	var queried: TravelCellResult = travel_runtime.query_travel_cell(session_cell)
	assert(queried.success and queried.terrain_type == TerrainType.WATER, "Travel query ignored Region Delta terrain")
	assert(not queried.passable, "Water Delta terrain remained passable")
	var site_definition: SiteData = world_data.get_site_definition_at(
		REGION_CELL,
		overridden_cell,
		TEST_SEED
	)
	var site_snapshot: SiteRuntimeQueryResult = travel_runtime.query_site_snapshot(site_definition.site_id)
	assert(site_snapshot.success and site_snapshot.snapshot.source_terrain_type == TerrainType.WATER,
		"Site query ignored the resolved Region Delta terrain")
	var center_cell: Vector2i = Vector2i(50, 50)
	assert(region_runtime.apply_test_terrain_override(REGION_CELL, center_cell, TerrainType.WATER), "Runtime destination Delta setup failed")
	var resolved_destination: Vector2i = travel_runtime.resolve_world_destination(REGION_CELL)
	assert(resolved_destination != WorldCoordinates.world_region_to_global_region_cell(REGION_CELL, center_cell), "World destination resolver ignored Region Delta")
	assert(travel_runtime.query_travel_cell(resolved_destination).passable, "Resolved Runtime destination is not passable")
	print("TEST 21 PASS: Travel queries consume resolved Region Delta")

func _test_existing_runtime_regression() -> void:
	_reset()
	var terrain: RegionTerrainData = _base_terrain()
	var pois: Array[WorldPOIData] = world_data.get_pois_for_region(REGION_CELL, TEST_SEED)
	var roads: RegionRoadOverlay = world_data.get_roads_for_region(REGION_CELL, TEST_SEED)
	assert(terrain != null and roads != null and not pois.is_empty(), "Existing Base terrain/POI/road runtime regressed")
	session.party.initialized = true
	session.party.set_global_region_cell(WorldCoordinates.world_region_to_global_region_cell(REGION_CELL, Vector2i(50, 50)))
	var travel_runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	var cell_query: TravelCellResult = travel_runtime.query_travel_cell(session.party.current_global_region_cell)
	assert(cell_query.success, "Existing Travel Query regressed")
	assert(session.world_time_seconds == GameSession.INITIAL_WORLD_TIME_SECONDS, "Existing World Time regressed")
	print("TEST 22 PASS: Existing Base, Party, Travel and World Time contracts remain available")

func _reset() -> void:
	world_data = WorldData.new()
	session = GameSession.new()
	session.world_seed = TEST_SEED
	region_runtime = RegionRuntime.new(session, world_data)

func _base_terrain() -> RegionTerrainData:
	return world_data.get_or_generate_region_terrain(REGION_CELL, TEST_SEED)

func _sample_cells() -> Array[Vector2i]:
	return [Vector2i(0, 0), Vector2i(20, 30), Vector2i(50, 50), Vector2i(99, 99)]

func _find_terrain(terrain: RegionTerrainData, terrain_type: int) -> Vector2i:
	for y: int in range(WorldCoordinates.REGION_GRID_SIZE):
		for x: int in range(WorldCoordinates.REGION_GRID_SIZE):
			var cell: Vector2i = Vector2i(x, y)
			if terrain.get_terrain(cell) == terrain_type:
				return cell
	return Vector2i(-1, -1)

func _has_feature(features: Array[RegionFeatureDelta], feature_id: String) -> bool:
	for feature: RegionFeatureDelta in features:
		if feature.feature_id == feature_id:
			return true
	return false

func _has_poi(pois: Array[WorldPOIData], poi_id: String) -> bool:
	for poi: WorldPOIData in pois:
		if poi.poi_id == poi_id:
			return true
	return false

func _resolved_hash(resolver: RegionStateResolver) -> int:
	var result: int = 17
	for y: int in range(WorldCoordinates.REGION_GRID_SIZE):
		for x: int in range(WorldCoordinates.REGION_GRID_SIZE):
			result = posmod(result * 31 + resolver.get_terrain(Vector2i(x, y)), 2_147_483_647)
	result = posmod(result * 31 + resolver.get_owner().hash(), 2_147_483_647)
	result = posmod(result * 31 + resolver.get_development_level(), 2_147_483_647)
	for feature: RegionFeatureDelta in resolver.get_features_at(Vector2i(20, 30)):
		result = posmod(result * 31 + feature.feature_id.hash(), 2_147_483_647)
	return result

func _hash_bytes(values: PackedByteArray) -> int:
	var result: int = 17
	for value: int in values:
		result = posmod(result * 31 + value, 2_147_483_647)
	return result

func _poi_signature(pois: Array[WorldPOIData]) -> String:
	var ids: Array[String] = []
	for poi: WorldPOIData in pois:
		ids.append(poi.poi_id)
	ids.sort()
	return "|".join(ids)

func _route_signature(routes: Array[WorldRoadRoute]) -> String:
	var ids: Array[String] = []
	for route: WorldRoadRoute in routes:
		ids.append(route.route_id)
	ids.sort()
	return "|".join(ids)

func _source_contains(path: String, text: String) -> bool:
	return FileAccess.get_file_as_string("res://" + path).contains(text)
