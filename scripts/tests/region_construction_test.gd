extends SceneTree

const TEST_SEED: int = 123456789
const REGION_CELL: Vector2i = Vector2i(3, 4)
const SAVE_PATH: String = "user://v016_region_construction_test.json"
const GlobalTravelPathType = preload("res://scripts/data/global_travel_path.gd")
const RegionConstructionResultType = preload("res://scripts/runtime/region_construction_result.gd")

var world_data: WorldData
var session: GameSession
var runtime: RegionRuntime
var terrain: RegionTerrainData
var pois: Array[WorldPOIData]
var roads: RegionRoadOverlay

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_preview_is_read_only()
	_test_typed_input_failures()
	_test_party_and_travel_eligibility()
	_test_terrain_and_occupancy_rules()
	_test_place_outpost_uses_sparse_delta()
	_test_command_revalidates_preview()
	_test_duplicate_does_not_change_revision()
	_test_remove_is_sparse()
	_test_remove_rejects_wrong_feature_type()
	_test_query_does_not_repair_invalid_state()
	_test_runtime_has_no_presentation_dependency()
	_test_save_load_round_trip()
	await _test_presentation_lifecycle()
	_remove_save_file()
	print("Region construction tests passed: 13 cases")
	quit()

func _test_preview_is_read_only() -> void:
	_reset()
	var party_before: Vector2i = session.party.current_global_region_cell
	var time_before: int = session.world_time_seconds
	var state_count_before: int = session.region_runtime_states.size()
	var cell: Vector2i = _find_buildable_cell()
	var result: RegionConstructionResultType = runtime.query_outpost_preview(REGION_CELL, cell)
	assert(result.success and not result.feature_id.is_empty(), "Valid Outpost preview failed")
	assert(session.party.current_global_region_cell == party_before, "Outpost preview moved Party")
	assert(session.world_time_seconds == time_before, "Outpost preview advanced World Time")
	assert(session.region_runtime_states.size() == state_count_before, "Outpost preview allocated Region runtime state")
	print("CONSTRUCTION TEST 1 PASS: preview query is read-only")

func _test_typed_input_failures() -> void:
	_reset()
	var unavailable: RegionConstructionResultType = RegionRuntime.new().query_outpost_preview(REGION_CELL, Vector2i.ZERO)
	var bad_region: RegionConstructionResultType = runtime.query_outpost_preview(WorldData.WORLD_CELLS, Vector2i.ZERO)
	var bad_cell: RegionConstructionResultType = runtime.query_outpost_preview(REGION_CELL, Vector2i(100, 0))
	assert(unavailable.failure_reason == RegionConstructionResultType.FailureReason.RUNTIME_UNAVAILABLE, "Unavailable Runtime failure is not typed")
	assert(bad_region.failure_reason == RegionConstructionResultType.FailureReason.INVALID_REGION, "Invalid Region failure is not typed")
	assert(bad_cell.failure_reason == RegionConstructionResultType.FailureReason.INVALID_CELL, "Invalid Cell failure is not typed")
	print("CONSTRUCTION TEST 2 PASS: invalid inputs return typed failures")

func _test_party_and_travel_eligibility() -> void:
	_reset()
	var cell: Vector2i = _find_buildable_cell()
	session.party.initialized = false
	assert(runtime.query_outpost_preview(REGION_CELL, cell).failure_reason == RegionConstructionResultType.FailureReason.PARTY_NOT_READY, "Uninitialized Party could build")
	_reset()
	cell = _find_buildable_cell()
	session.party.set_global_region_cell(WorldCoordinates.world_region_to_global_region_cell(Vector2i(2, 4), Vector2i(50, 50)))
	assert(runtime.query_outpost_preview(REGION_CELL, cell).failure_reason == RegionConstructionResultType.FailureReason.PARTY_NOT_IN_REGION, "Remote Party could build")
	_reset()
	cell = _find_buildable_cell()
	var path: GlobalTravelPathType = GlobalTravelPathType.new()
	path.cells = [session.party.current_global_region_cell, session.party.current_global_region_cell + Vector2i.RIGHT]
	session.set_travel_plan(path)
	assert(runtime.query_outpost_preview(REGION_CELL, cell).failure_reason == RegionConstructionResultType.FailureReason.TRAVEL_IN_PROGRESS, "Travelling Party could build")
	print("CONSTRUCTION TEST 3 PASS: Party and Travel eligibility belongs to Runtime")

func _test_terrain_and_occupancy_rules() -> void:
	_reset()
	var impassable: Vector2i = _find_cell_with_failure(RegionConstructionResultType.FailureReason.IMPASSABLE)
	var occupied: Vector2i = _find_cell_with_failure(RegionConstructionResultType.FailureReason.OCCUPIED)
	assert(impassable != Vector2i(-1, -1), "No impassable construction cell found")
	assert(occupied != Vector2i(-1, -1), "No occupied construction cell found")
	print("CONSTRUCTION TEST 4 PASS: terrain and occupancy rules are Runtime decisions")

func _test_place_outpost_uses_sparse_delta() -> void:
	_reset()
	var cell: Vector2i = _find_buildable_cell()
	var preview: RegionConstructionResultType = runtime.query_outpost_preview(REGION_CELL, cell)
	var command: RegionConstructionResultType = runtime.place_outpost(REGION_CELL, cell)
	var state: RegionRuntimeState = session.find_region_runtime_state(REGION_CELL)
	var stored: Variant = state.delta.added_features.get(command.feature_id, null)
	assert(command.success and command.changed, "Outpost command did not mutate Runtime")
	assert(command.feature_id == preview.feature_id, "Outpost ID is not stable")
	assert(state != null and state.delta.added_feature_count() == 1, "Outpost did not use sparse Region Delta")
	assert(stored is RegionFeatureDelta and (stored as RegionFeatureDelta).feature_type == RegionRuntime.OUTPOST_FEATURE_TYPE, "Outpost feature type is wrong")
	var queried: Array[RegionFeatureDelta] = runtime.query_region(REGION_CELL).get_runtime_features_by_type(RegionRuntime.OUTPOST_FEATURE_TYPE)
	queried[0].region_cell = Vector2i.ZERO
	assert((state.delta.added_features[command.feature_id] as RegionFeatureDelta).region_cell == cell, "Resolved construction query exposed mutable authority")
	print("CONSTRUCTION TEST 5 PASS: place writes one stable sparse Outpost feature")

func _test_command_revalidates_preview() -> void:
	_reset()
	var cell: Vector2i = _find_buildable_cell()
	assert(runtime.query_outpost_preview(REGION_CELL, cell).success, "Revalidation preview setup failed")
	assert(runtime.apply_test_feature_add(REGION_CELL, "blocking_feature", &"test", cell), "Revalidation blocker setup failed")
	var command: RegionConstructionResultType = runtime.place_outpost(REGION_CELL, cell)
	assert(not command.success and command.failure_reason == RegionConstructionResultType.FailureReason.OCCUPIED, "Place command trusted stale preview")
	assert(not runtime.query_region(REGION_CELL).has_feature(command.feature_id), "Stale preview created an Outpost")
	print("CONSTRUCTION TEST 6 PASS: place command revalidates preview")

func _test_duplicate_does_not_change_revision() -> void:
	_reset()
	var cell: Vector2i = _find_buildable_cell()
	assert(runtime.place_outpost(REGION_CELL, cell).success, "Duplicate test setup failed")
	var delta: RegionDelta = session.find_region_runtime_state(REGION_CELL).delta
	var revision_before: int = delta.revision
	var duplicate: RegionConstructionResultType = runtime.place_outpost(REGION_CELL, cell)
	assert(not duplicate.success and duplicate.failure_reason == RegionConstructionResultType.FailureReason.ALREADY_EXISTS, "Duplicate Outpost was accepted")
	assert(delta.revision == revision_before, "Duplicate Outpost changed revision")
	print("CONSTRUCTION TEST 7 PASS: duplicate placement is an explicit no-op")

func _test_remove_is_sparse() -> void:
	_reset()
	var cell: Vector2i = _find_buildable_cell()
	var placed: RegionConstructionResultType = runtime.place_outpost(REGION_CELL, cell)
	var delta: RegionDelta = session.find_region_runtime_state(REGION_CELL).delta
	var removed: RegionConstructionResultType = runtime.remove_outpost(REGION_CELL, cell)
	var revision_after: int = delta.revision
	assert(placed.success and removed.success and removed.changed, "Outpost remove command failed")
	assert(delta.added_features.is_empty() and delta.removed_feature_ids.is_empty(), "Removing an added Outpost left non-sparse state")
	var repeated: RegionConstructionResultType = runtime.remove_outpost(REGION_CELL, cell)
	assert(repeated.failure_reason == RegionConstructionResultType.FailureReason.NOT_FOUND, "Missing Outpost removal was accepted")
	assert(delta.revision == revision_after, "Missing Outpost removal changed revision")
	print("CONSTRUCTION TEST 8 PASS: remove erases added Outpost without tombstone")

func _test_remove_rejects_wrong_feature_type() -> void:
	_reset()
	var cell: Vector2i = _find_buildable_cell()
	var preview: RegionConstructionResultType = runtime.query_outpost_preview(REGION_CELL, cell)
	assert(runtime.apply_test_feature_add(REGION_CELL, preview.feature_id, &"test", cell), "Wrong-type setup failed")
	var result: RegionConstructionResultType = runtime.remove_outpost(REGION_CELL, cell)
	assert(not result.success and result.failure_reason == RegionConstructionResultType.FailureReason.WRONG_FEATURE_TYPE, "Remove command deleted a non-Outpost feature")
	assert(runtime.query_region(REGION_CELL).has_feature(preview.feature_id), "Wrong-type feature was removed")
	print("CONSTRUCTION TEST 9 PASS: remove command validates feature type")

func _test_query_does_not_repair_invalid_state() -> void:
	_reset()
	var state: RegionRuntimeState = session.get_region_runtime_state(REGION_CELL)
	state.delta.base_generation_version = 0
	var result: RegionConstructionResultType = runtime.query_outpost_preview(REGION_CELL, Vector2i.ZERO)
	assert(not result.success and result.failure_reason == RegionConstructionResultType.FailureReason.INVALID_REGION, "Invalid Delta version was silently accepted")
	assert(state.delta.base_generation_version == 0, "Read-only query repaired mutable Runtime state")
	print("CONSTRUCTION TEST 10 PASS: query never repairs or mutates invalid state")

func _test_runtime_has_no_presentation_dependency() -> void:
	var runtime_source: String = FileAccess.get_file_as_string("res://scripts/runtime/region_runtime.gd")
	for forbidden: String in ["RegionMap", "Node2D", "Camera2D", "TileMap", "Control", "Sprite2D"]:
		assert(not runtime_source.contains(forbidden), "Construction Runtime depends on Presentation symbol %s" % forbidden)
	var map_source: String = FileAccess.get_file_as_string("res://scripts/region/region_map.gd")
	assert(not map_source.contains("RegionDelta") and not map_source.contains("delta."), "RegionMap writes Region Delta directly")
	assert(map_source.contains("query_outpost_preview") and map_source.contains("place_outpost") and map_source.contains("remove_outpost"), "RegionMap bypasses Construction Runtime API")
	print("CONSTRUCTION TEST 11 PASS: Runtime and Presentation dependencies stay one-way")

func _test_save_load_round_trip() -> void:
	_reset()
	_remove_save_file()
	var cell: Vector2i = _find_buildable_cell()
	var placed: RegionConstructionResultType = runtime.place_outpost(REGION_CELL, cell)
	var persistence: PersistenceService = PersistenceService.new(world_data)
	assert(placed.success and persistence.save_session(session, SAVE_PATH).success, "Outpost save setup failed")
	var loaded: PersistenceResult = persistence.load_session(SAVE_PATH, world_data)
	assert(loaded.success and loaded.session != null, "Outpost save did not load")
	var restored_runtime: RegionRuntime = RegionRuntime.new(loaded.session, world_data)
	var restored: Array[RegionFeatureDelta] = restored_runtime.query_region(REGION_CELL).get_runtime_features_by_type(RegionRuntime.OUTPOST_FEATURE_TYPE)
	assert(restored.size() == 1 and restored[0].feature_id == placed.feature_id and restored[0].region_cell == cell, "Outpost did not survive Save/Load")
	print("CONSTRUCTION TEST 12 PASS: existing Region persistence restores Outpost")

func _test_presentation_lifecycle() -> void:
	_reset()
	var cell: Vector2i = _find_buildable_cell()
	var scene: PackedScene = load("res://scenes/region/RegionMap.tscn") as PackedScene
	var first: RegionMap = scene.instantiate() as RegionMap
	get_root().add_child(first)
	await process_frame
	first.setup(world_data.get_region(REGION_CELL), terrain, pois, session, roads, TravelRuntime.new(session, world_data), runtime)
	assert(first.set_construction_mode(true), "RegionMap could not enter Construction mode")
	assert(first.place_outpost_at(cell).success, "RegionMap did not send Place command")
	var revision_after_place: int = session.find_region_runtime_state(REGION_CELL).delta.revision
	first.set_construction_mode(false)
	assert(session.find_region_runtime_state(REGION_CELL).delta.revision == revision_after_place, "Clearing construction preview mutated Runtime")
	first.queue_free()
	await process_frame
	var second: RegionMap = scene.instantiate() as RegionMap
	get_root().add_child(second)
	await process_frame
	second.setup(world_data.get_region(REGION_CELL), terrain, pois, session, roads, TravelRuntime.new(session, world_data), runtime)
	assert(second.resolved_region.get_runtime_features_by_type(RegionRuntime.OUTPOST_FEATURE_TYPE).size() == 1, "Region view replacement lost Outpost")
	second.queue_free()
	await process_frame
	print("CONSTRUCTION TEST 13 PASS: preview is visual and Region replacement keeps Outpost")

func _reset() -> void:
	world_data = WorldData.new()
	session = GameSession.new()
	session.world_seed = TEST_SEED
	session.selected_world_cell = REGION_CELL
	session.selected_region_cell = Vector2i(50, 50)
	session.party.set_global_region_cell(WorldCoordinates.world_region_to_global_region_cell(
		REGION_CELL,
		Vector2i(50, 50)
	))
	session.party.initialized = true
	terrain = world_data.get_or_generate_region_terrain(REGION_CELL, TEST_SEED)
	pois = world_data.get_pois_for_region(REGION_CELL, TEST_SEED)
	roads = world_data.get_roads_for_region(REGION_CELL, TEST_SEED)
	runtime = RegionRuntime.new(session, world_data)
	runtime.set_region_context(world_data.get_region(REGION_CELL), terrain, pois, roads)

func _find_buildable_cell() -> Vector2i:
	for y: int in range(WorldCoordinates.REGION_GRID_SIZE):
		for x: int in range(WorldCoordinates.REGION_GRID_SIZE):
			var cell: Vector2i = Vector2i(x, y)
			if runtime.query_outpost_preview(REGION_CELL, cell).success:
				return cell
	assert(false, "No deterministic buildable Cell found")
	return Vector2i(-1, -1)

func _find_cell_with_failure(reason: int) -> Vector2i:
	for y: int in range(WorldCoordinates.REGION_GRID_SIZE):
		for x: int in range(WorldCoordinates.REGION_GRID_SIZE):
			var cell: Vector2i = Vector2i(x, y)
			if runtime.query_outpost_preview(REGION_CELL, cell).failure_reason == reason:
				return cell
	return Vector2i(-1, -1)

func _remove_save_file() -> void:
	var absolute: String = ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(absolute)
