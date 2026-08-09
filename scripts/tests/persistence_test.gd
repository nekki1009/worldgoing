extends SceneTree

const TEST_SEED: int = 246813579
const REGION_CELL: Vector2i = Vector2i(3, 4)
const SAVE_PATH: String = "user://v012_persistence_test.json"

var world_data: WorldData
var persistence: PersistenceService

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	world_data = WorldData.new()
	persistence = PersistenceService.new(world_data)
	_remove_save_file()
	_test_round_trip()
	_test_delta_reconstruction()
	_test_save_rejects_active_travel()
	_test_corrupt_load_is_atomic()
	_test_generation_version_validation()
	_test_invalid_region_data()
	_test_wire_excludes_view_state()
	_test_no_presentation_dependency()
	await _test_navigation_session_replacement()
	_remove_save_file()
	print("Persistence tests passed: 9 cases")
	quit()

func _test_round_trip() -> void:
	var source: GameSession = _new_session()
	_populate_region_state(source)
	var save_result: PersistenceResult = persistence.save_session(source, SAVE_PATH)
	assert(save_result.success, "Session save failed")
	var load_result: PersistenceResult = persistence.load_session(SAVE_PATH, world_data)
	assert(load_result.success and load_result.session != null, "Session load failed: %s" % PersistenceResult.to_code(load_result.failure_reason))
	var restored: GameSession = load_result.session
	assert(restored != source, "Load reused the source Session")
	assert(restored.world_seed == source.world_seed, "World Seed did not round-trip")
	assert(restored.world_time_seconds == source.world_time_seconds, "World Time did not round-trip")
	assert(restored.party.party_id == source.party.party_id, "Party ID did not round-trip")
	assert(restored.party.display_name == source.party.display_name, "Party name did not round-trip")
	assert(restored.party.current_global_region_cell == source.party.current_global_region_cell, "Party position did not round-trip")
	assert(restored.party.base_walk_speed_kmh == source.party.base_walk_speed_kmh, "Party speed did not round-trip")
	assert(restored.party.initialized == source.party.initialized, "Party initialized state did not round-trip")
	assert(restored.active_global_travel_path == null, "Save restored an active travel path")
	assert(restored.site_runtime_states.is_empty(), "Save restored Site Runtime that is outside this contract")
	var state: RegionRuntimeState = restored.find_region_runtime_state(REGION_CELL)
	assert(state != null and not state.discovered, "Region discovery state did not round-trip")
	assert(state.discovered_site_ids.has("poi_persisted"), "Discovered Site ID did not round-trip")
	assert(state.owner_id == "player" and state.development_level == 3, "Region values did not round-trip")
	print("TEST 1 PASS: Session Seed + Party + World Time + Region state round-trip")

func _test_delta_reconstruction() -> void:
	var source: GameSession = _new_session()
	_populate_region_state(source)
	var save_result: PersistenceResult = persistence.save_session(source, SAVE_PATH)
	assert(save_result.success, "Delta save setup failed")
	world_data.clear_generated_cache()
	var load_result: PersistenceResult = persistence.load_session(SAVE_PATH, world_data)
	assert(load_result.success, "Delta load setup failed: %s" % PersistenceResult.to_code(load_result.failure_reason))
	var restored_runtime: RegionRuntime = RegionRuntime.new(load_result.session, world_data)
	var resolved: RegionStateResolver = restored_runtime.query_region(REGION_CELL)
	assert(resolved.is_valid(), "Restored Region could not resolve")
	assert(resolved.get_terrain(Vector2i(20, 30)) == TerrainType.PLAINS, "Terrain Delta was not reconstructed")
	assert(resolved.get_owner() == "player" and resolved.get_development_level() == 3, "Region Delta values were not reconstructed")
	var features: Array[RegionFeatureDelta] = resolved.get_features_at(Vector2i(20, 30))
	assert(_has_feature(features, "feature_persisted"), "Added Feature Delta was not reconstructed")
	var feature: RegionFeatureDelta = _find_feature(features, "feature_persisted")
	assert(feature.payload.get("cell", Vector2i(-1, -1)) == Vector2i(20, 30), "Feature payload was not reconstructed")
	print("TEST 2 PASS: Seed + sparse Region Delta reconstructs Resolved Region")

func _test_save_rejects_active_travel() -> void:
	var source: GameSession = _new_session()
	var path: GlobalTravelPath = GlobalTravelPath.new()
	path.cells = [source.party.current_global_region_cell, source.party.current_global_region_cell + Vector2i(1, 0)]
	source.set_travel_plan(path)
	var result: PersistenceResult = persistence.save_session(source, SAVE_PATH)
	assert(not result.success, "Save accepted active Travel")
	assert(result.failure_reason == PersistenceResult.Code.TRAVEL_IN_PROGRESS, "Active Travel failure was not typed")
	print("TEST 3 PASS: Active Travel save is rejected with typed reason")

func _test_corrupt_load_is_atomic() -> void:
	var source: GameSession = _new_session()
	var before_position: Vector2i = source.party.current_global_region_cell
	var before_time: int = source.world_time_seconds
	_write_save_text("{not valid json")
	var result: PersistenceResult = persistence.load_session(SAVE_PATH, world_data)
	assert(not result.success and result.session == null, "Corrupt Save produced a Session")
	assert(result.failure_reason == PersistenceResult.Code.CORRUPT_DATA, "Corrupt Save failure was not typed")
	assert(source.party.current_global_region_cell == before_position and source.world_time_seconds == before_time, "Failed load mutated the source Session")
	print("TEST 4 PASS: Corrupt load fails atomically without mutating Runtime state")

func _test_generation_version_validation() -> void:
	var source: GameSession = _new_session()
	var save_result: PersistenceResult = persistence.save_session(source, SAVE_PATH)
	assert(save_result.success, "Version validation setup failed")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	assert(parsed is Dictionary, "Saved JSON could not be parsed for version test")
	var wire: Dictionary = parsed as Dictionary
	var versions: Dictionary = wire["generation_versions"] as Dictionary
	versions["terrain"] = RegionTerrainGenerator.GENERATION_VERSION + 1
	_write_save_text(JSON.stringify(wire))
	var result: PersistenceResult = persistence.load_session(SAVE_PATH, world_data)
	assert(not result.success, "Unsupported generation version was accepted")
	assert(result.failure_reason == PersistenceResult.Code.UNSUPPORTED_VERSION, "Generation version failure was not typed: %s" % PersistenceResult.to_code(result.failure_reason))
	print("TEST 5 PASS: Generation version mismatch is rejected before reconstruction")

func _test_invalid_region_data() -> void:
	var source: GameSession = _new_session()
	_populate_region_state(source)
	var save_result: PersistenceResult = persistence.save_session(source, SAVE_PATH)
	assert(save_result.success, "Invalid Region data setup failed")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	assert(parsed is Dictionary, "Saved JSON could not be parsed for invalid data test")
	var wire: Dictionary = parsed as Dictionary
	var region: Dictionary = wire["regions"][0] as Dictionary
	var delta: Dictionary = region["delta"] as Dictionary
	delta["development_level"] = -1
	_write_save_text(JSON.stringify(wire))
	var result: PersistenceResult = persistence.load_session(SAVE_PATH, world_data)
	assert(not result.success, "Invalid Region data was accepted")
	assert(result.failure_reason == PersistenceResult.Code.INVALID_REGION_DELTA, "Invalid Region data failure was not typed: %s" % PersistenceResult.to_code(result.failure_reason))
	print("TEST 6 PASS: Invalid Region Delta is rejected before reconstruction")

func _test_wire_excludes_view_state() -> void:
	var source: GameSession = _new_session()
	var save_result: PersistenceResult = persistence.save_session(source, SAVE_PATH)
	assert(save_result.success, "Wire exclusion setup failed")
	var serialized: String = FileAccess.get_file_as_string(SAVE_PATH)
	assert(not serialized.contains("active_global_travel_path"), "Wire contains active Travel Path")
	assert(not serialized.contains("site_runtime_states"), "Wire contains Site Runtime state")
	assert(not serialized.contains("TileMap") and not serialized.contains("Camera"), "Wire contains Presentation state")
	print("TEST 7 PASS: Save wire contains no Scene, UI, cache, or active Travel view state")

func _test_no_presentation_dependency() -> void:
	for path: String in [
		"scripts/persistence/persistence_result.gd",
		"scripts/persistence/session_save_data.gd",
		"scripts/persistence/persistence_service.gd",
	]:
		var source: String = FileAccess.get_file_as_string("res://" + path)
		for forbidden: String in [
			"RegionMap",
			"WorldMap",
			"SiteMap",
			"NavigationController",
			"Camera2D",
			"TileMapLayer",
			"Control",
			"DebugUI",
		]:
			assert(not source.contains(forbidden), "%s depends on %s" % [path, forbidden])
	print("TEST 8 PASS: Persistence boundary has no Presentation dependency")

func _test_navigation_session_replacement() -> void:
	var source: GameSession = _new_session()
	_populate_region_state(source)
	var save_result: PersistenceResult = persistence.save_session(source, SAVE_PATH)
	assert(save_result.success, "Navigation replacement setup failed")
	var loaded_result: PersistenceResult = persistence.load_session(SAVE_PATH, world_data)
	assert(loaded_result.success, "Navigation replacement load failed: %s" % PersistenceResult.to_code(loaded_result.failure_reason))
	var main_scene: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	assert(main_scene != null, "Main scene could not be loaded")
	var main: Node2D = main_scene.instantiate() as Node2D
	get_root().add_child(main)
	await process_frame
	var navigation: NavigationController = main.get_node("NavigationController") as NavigationController
	assert(navigation != null, "NavigationController missing from Main scene")
	var original: GameSession = navigation.get_session()
	assert(navigation.replace_session(loaded_result.session), "Navigation rejected valid loaded Session")
	assert(navigation.get_session() == loaded_result.session, "Navigation did not replace Session")
	assert(navigation.region_runtime.session == loaded_result.session, "Region Runtime was not rebound")
	assert(navigation.travel_runtime.session == loaded_result.session, "Travel Runtime was not rebound")
	assert(navigation.get_session() != original, "Navigation kept the old Session")
	await process_frame
	navigation.show_world()
	await process_frame
	navigation.show_region()
	await process_frame
	assert(navigation.get_session().find_region_runtime_state(REGION_CELL) != null, "View replacement lost loaded Region state")
	main.queue_free()
	await process_frame
	print("TEST 9 PASS: Loaded Session replacement survives World -> Region view replacement")

func _new_session() -> GameSession:
	var result: GameSession = GameSession.new()
	result.world_seed = TEST_SEED
	result.world_time_seconds = 987654
	result.party.party_id = "party_persistence"
	result.party.display_name = "Persistence Test Party"
	result.party.base_walk_speed_kmh = 6.5
	result.party.set_global_region_cell(WorldCoordinates.world_region_to_global_region_cell(REGION_CELL, Vector2i(50, 50)))
	result.party.initialized = true
	result.selected_world_cell = REGION_CELL
	result.selected_region_cell = Vector2i(50, 50)
	return result

func _populate_region_state(source: GameSession) -> void:
	var state: RegionRuntimeState = source.get_region_runtime_state(REGION_CELL)
	state.discovered = false
	state.discovered_site_ids["poi_persisted"] = true
	assert(state.delta.set_terrain_override(Vector2i(20, 30), TerrainType.PLAINS), "Could not create Terrain Delta")
	assert(state.delta.add_feature_record(
		"feature_persisted",
		&"test",
		Vector2i(20, 30),
		{"cell": Vector2i(20, 30), "kind": &"persisted"}
	), "Could not create Feature Delta")
	assert(state.delta.remove_feature("feature_removed"), "Could not create removed Feature Delta")
	state.owner_id = "player"
	state.development_level = 3

func _has_feature(features: Array[RegionFeatureDelta], feature_id: String) -> bool:
	return _find_feature(features, feature_id) != null

func _find_feature(features: Array[RegionFeatureDelta], feature_id: String) -> RegionFeatureDelta:
	for feature: RegionFeatureDelta in features:
		if feature.feature_id == feature_id:
			return feature
	return null

func _write_save_text(text: String) -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	assert(file != null, "Could not open test Save file")
	file.store_string(text)
	file.close()

func _remove_save_file() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
