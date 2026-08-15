extends SceneTree

const TEST_SEED: int = 123456789
const TravelRuntimeType = preload("res://scripts/runtime/travel_runtime.gd")
const TravelFailureReasonType = preload("res://scripts/runtime/travel_failure_reason.gd")

var world_data: WorldData = WorldData.new()
var cancellation_signal_seen: bool = false
var site_entry_signal_cell: Vector2i = Vector2i(-1, -1)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_query_is_read_only()
	_test_region_map_has_no_pathfinder_dependency()
	_test_world_map_uses_runtime_api()
	_test_preview_result()
	_test_invalid_destination_reason()
	_test_start_travel_command()
	_test_preview_is_not_authority()
	_test_cancel_travel_command()
	_test_travel_terminal_guards()
	_test_site_entry_query()
	await _test_region_tile_selection_and_site_entry()
	_test_navigation_has_no_gameplay_pathfinding()
	await _test_scene_replacement_contract()
	_test_existing_local_travel_contract()
	_test_cross_region_runtime_query()
	await _test_presentation_preview_state()
	_test_runtime_without_region_map()
	_test_runtime_without_ui()
	_test_runtime_dependency_scan()
	print("Runtime command/query tests passed: 19 cases")
	quit()

func _test_query_is_read_only() -> void:
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = _new_runtime(session)
	var destination: Vector2i = _find_destination(runtime, session)
	var before: Dictionary = _state_snapshot(session)
	var result: TravelPreviewResult = runtime.query_travel_preview(
			session.party.party_id,
			destination
		)
	assert(result.success, "Read-only query could not build a valid preview")
	assert(_state_snapshot(session) == before, "Travel Preview Query mutated gameplay state")
	print("TEST 1 PASS: query is read-only")

func _test_region_map_has_no_pathfinder_dependency() -> void:
	var source: String = _source("res://scripts/region/region_map.gd")
	assert(not source.contains("PartyPathfinder"), "RegionMap still owns PartyPathfinder")
	assert(not source.contains("PartyPathResult"), "RegionMap still exposes legacy PartyPathResult")
	assert(not source.contains("local_travel_confirm_requested"), "RegionMap still exposes legacy travel signal")
	assert(not source.contains("TravelCostConfig"), "RegionMap still owns Travel Cost")
	print("TEST 2 PASS: RegionMap has no Pathfinder dependency")

func _test_world_map_uses_runtime_api() -> void:
	var source: String = _source("res://scripts/world/world_map.gd")
	assert(source.contains("query_travel_preview"), "WorldMap does not use the Runtime travel query")
	assert(source.contains("start_travel"), "WorldMap does not use the Runtime travel command")
	assert(not source.contains("find_nearest_passable_global_cell"), "WorldMap still resolves gameplay destinations")
	print("TEST 3 PASS: WorldMap uses the shared Runtime API")

func _test_preview_result() -> void:
	var session: GameSession = _new_session()
	var destination: Vector2i = _find_destination(_new_runtime(session), session)
	var result: TravelPreviewResult = _new_runtime(session).query_travel_preview(
			session.party.party_id,
			destination
		)
	assert(result.success and result.path != null, "Preview result has no path")
	assert(result.start_global_cell == session.party.current_global_region_cell, "Preview start cell is wrong")
	assert(result.destination_global_cell == destination, "Preview destination is wrong")
	assert(result.total_distance_meters > 0.0, "Preview distance is missing")
	assert(result.estimated_travel_seconds > 0, "Preview travel time is missing")
	assert(result.regions_crossed == 1, "Local preview Region count is wrong")
	print("TEST 4 PASS: Preview Result contains typed travel data")

func _test_invalid_destination_reason() -> void:
	var session: GameSession = _new_session()
	var invalid_destination: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
		WorldData.WORLD_CELLS,
		Vector2i.ZERO
	)
	var result: TravelPreviewResult = _new_runtime(session).query_travel_preview(
			session.party.party_id,
			invalid_destination
		)
	assert(not result.success, "Invalid destination unexpectedly succeeded")
	assert(
			result.failure_reason == TravelFailureReasonType.Code.INVALID_DESTINATION,
			"Invalid destination did not return typed reason"
		)
	print("TEST 5 PASS: invalid destination returns typed failure reason")

func _test_start_travel_command() -> void:
	var session: GameSession = _new_session()
	var destination: Vector2i = _find_destination(_new_runtime(session), session)
	var start_cell: Vector2i = session.party.current_global_region_cell
	var command: TravelCommandResult = _new_runtime(session).start_travel(
			session.party.party_id,
			destination
		)
	assert(command.success and session.is_traveling(), "Start Travel Command did not activate travel")
	assert(session.party.current_global_region_cell == start_cell, "Start command teleported Party")
	assert(session.active_global_travel_path == command.path, "Command did not expose authoritative path")
	print("TEST 6 PASS: Start Travel is a Runtime Command")

func _test_preview_is_not_authority() -> void:
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = _new_runtime(session)
	var destination: Vector2i = _find_destination(runtime, session)
	var expected: TravelPreviewResult = runtime.query_travel_preview(session.party.party_id, destination)
	var expected_hash: String = expected.path.path_hash()
	expected.path.cells[1] = Vector2i(99, 99)
	var command: TravelCommandResult = runtime.start_travel(session.party.party_id, destination)
	assert(command.success, "Start command failed after preview data was changed")
	assert(command.path.path_hash() == expected_hash, "Start command trusted Presentation preview path")
	print("TEST 7 PASS: Preview data is not authoritative")

func _test_cancel_travel_command() -> void:
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = _new_runtime(session)
	var destination: Vector2i = _find_destination(runtime, session)
	runtime.travel_cancelled.connect(_on_travel_cancelled)
	cancellation_signal_seen = false
	assert(runtime.start_travel(session.party.party_id, destination).success, "Could not start cancel test travel")
	var result: TravelCommandResult = runtime.cancel_travel(session.party.party_id)
	assert(result.success and result.cancel_requested, "Cancel Travel Command did not request cancellation")
	assert(session.has_travel_plan(), "Cancel request cleared active travel before step completion")
	assert(runtime.finish_travel(), "Cancel command did not finish cleanly")
	assert(not session.has_travel_plan(), "Cancel command did not finish cleanly")
	assert(cancellation_signal_seen, "Active travel cancellation did not emit travel_cancelled")
	print("TEST 8 PASS: Cancel Travel is a Runtime Command")

func _test_travel_terminal_guards() -> void:
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = _new_runtime(session)
	var destination: Vector2i = _find_destination(runtime, session)
	assert(runtime.start_travel(session.party.party_id, destination).success, "Could not start terminal guard test travel")
	var next_step: TravelStepResult = runtime.get_next_travel_step()
	var stale: TravelStepResult = runtime.commit_travel_step(next_step.path_index + 1)
	assert(not stale.success, "Stale travel step was accepted")
	assert(stale.failure_reason == TravelFailureReasonType.Code.STALE_TRAVEL_STEP, "Stale travel step reason is not typed")
	assert(not runtime.finish_travel(), "Incomplete travel was marked finished")
	assert(session.has_travel_plan(), "Incomplete finish cleared active travel")
	runtime.cancel_travel(session.party.party_id)
	assert(runtime.finish_travel(), "Terminal guard cleanup could not cancel travel")
	print("TEST 8B PASS: travel terminal state guards reject stale/incomplete completion")

func _test_site_entry_query() -> void:
	var session: GameSession = _new_session()
	var poi: WorldPOIData = _first_poi()
	assert(poi != null, "No deterministic POI available for Site Entry Query")
	session.party.set_global_region_cell(poi.global_region_cell)
	var runtime: TravelRuntime = TravelRuntimeType.new(session, world_data)
	var allowed: SiteEntryQueryResult = runtime.query_site_entry(session.party.party_id, poi.poi_id)
	assert(allowed.can_enter, "Party at POI was rejected by Site Entry Query")
	session.party.set_global_region_cell(poi.global_region_cell + Vector2i.RIGHT)
	var remote: SiteEntryQueryResult = runtime.query_site_entry(session.party.party_id, poi.poi_id)
	assert(remote.can_enter, "POI Site entry still depends on Party locality")
	var generic_region_cell: Vector2i = _find_non_poi_cell(poi.world_cell, session.world_seed)
	var generic: SiteEntryQueryResult = runtime.query_site_entry_at(
		session.party.party_id,
		poi.world_cell,
		generic_region_cell
	)
	assert(generic.can_enter, "A non-POI Region tile was rejected as a Site")
	assert(generic.poi == null and generic.site_definition.source_poi_id.is_empty(), "Generic tile Site incorrectly requires POI data")
	assert(generic.site_definition.layout_kind == SiteLayoutData.LayoutKind.CELL_BASE, "Generic tile Site did not use the cell layout")
	print("TEST 9 PASS: Site Entry belongs to Runtime Query")

func _test_region_tile_selection_and_site_entry() -> void:
	var map_scene: PackedScene = load("res://scenes/region/RegionMap.tscn") as PackedScene
	var map: RegionMap = map_scene.instantiate() as RegionMap
	get_root().add_child(map)
	await process_frame
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = _new_runtime(session)
	var remote_world_cell: Vector2i = session.party.get_world_cell() + Vector2i.RIGHT
	var remote_region: RegionData = world_data.get_region(remote_world_cell)
	var remote_terrain: RegionTerrainData = world_data.get_or_generate_region_terrain(
		remote_world_cell,
		session.world_seed
	)
	var remote_roads: RegionRoadOverlay = world_data.get_roads_for_region(
		remote_world_cell,
		session.world_seed
	)
	session.selected_world_cell = remote_world_cell
	session.selected_region_cell = Vector2i(12, 13)
	map.setup(
		remote_region,
		remote_terrain,
		world_data.get_pois_for_region(remote_world_cell, session.world_seed),
		session,
		remote_roads,
		runtime
	)
	assert(not map.party_in_region, "Remote Region unexpectedly claimed the Party")
	assert(map.select_region_cell(Vector2i(14, 15)), "Remote Region tile could not be selected")
	assert(session.selected_region_cell == Vector2i(14, 15), "Remote Region tile selection was discarded")

	var generic_region_cell: Vector2i = _find_non_poi_cell(remote_world_cell, session.world_seed)
	session.selected_region_cell = generic_region_cell
	site_entry_signal_cell = Vector2i(-1, -1)
	if not map.site_enter_requested.is_connected(_on_test_site_enter_requested):
		map.site_enter_requested.connect(_on_test_site_enter_requested)
	map.setup(
		remote_region,
		remote_terrain,
		world_data.get_pois_for_region(remote_world_cell, session.world_seed),
		session,
		remote_roads,
		runtime
	)
	assert(map._try_enter_site_at(generic_region_cell), "Non-POI Region tile did not resolve as a Site entry")
	assert(site_entry_signal_cell == generic_region_cell, "Region did not emit the generic Site entry request")
	site_entry_signal_cell = Vector2i(-1, -1)
	map.setup(
		remote_region,
		remote_terrain,
		world_data.get_pois_for_region(remote_world_cell, session.world_seed),
		session,
		remote_roads,
		runtime
	)
	var enter_event: InputEventKey = InputEventKey.new()
	enter_event.keycode = KEY_ENTER
	enter_event.pressed = true
	map._unhandled_input(enter_event)
	assert(site_entry_signal_cell == generic_region_cell, "Enter on a selected non-POI tile did not emit the Site entry request")
	map.queue_free()
	await process_frame
	print("TEST 9B PASS: Any Region tile opens Site independently from Party locality and POI presence")

func _on_test_site_enter_requested(region_cell: Vector2i) -> void:
	site_entry_signal_cell = region_cell

func _test_navigation_has_no_gameplay_pathfinding() -> void:
	var source: String = _source("res://scripts/core/navigation_controller.gd")
	assert(not source.contains("PartyPathfinder"), "NavigationController still owns Pathfinder")
	assert(not source.contains("PartyPathResult"), "NavigationController still accepts Presentation path data")
	assert(not source.contains("begin_local_travel"), "NavigationController still exposes legacy local travel bridge")
	assert(not source.contains("TravelCostConfig"), "NavigationController still owns Travel Cost")
	assert(not source.contains("find_path("), "NavigationController still calls a pathfinder")
	print("TEST 10 PASS: NavigationController has no gameplay pathfinding")

func _test_scene_replacement_contract() -> void:
	var main_scene: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	assert(main_scene != null, "Main scene contract is missing")
	assert(load("res://scenes/world/WorldMap.tscn") is PackedScene, "World scene contract is missing")
	assert(load("res://scenes/region/RegionMap.tscn") is PackedScene, "Region scene contract is missing")
	assert(load("res://scenes/site/SiteMap.tscn") is PackedScene, "Site scene contract is missing")
	var main: Node2D = main_scene.instantiate() as Node2D
	get_root().add_child(main)
	await process_frame
	var navigation: NavigationController = main.get_node("NavigationController") as NavigationController
	assert(navigation != null, "NavigationController missing from Main scene")
	var poi: WorldPOIData = _first_poi()
	assert(poi != null, "No deterministic POI available for scene replacement")
	navigation.session.party.set_global_region_cell(poi.global_region_cell)
	navigation.session.party.initialized = true
	navigation.session.selected_world_cell = poi.world_cell
	navigation.session.selected_region_cell = poi.region_cell
	navigation.show_region()
	await process_frame
	var before: Dictionary = _state_snapshot(navigation.session)
	navigation.enter_site_at(poi.region_cell)
	await process_frame
	assert(navigation.current_layer == NavigationController.MapLayer.SITE, "Region did not enter Site view")
	navigation.show_region()
	await process_frame
	assert(navigation.current_layer == NavigationController.MapLayer.REGION, "Site did not return to Region view")
	assert(_state_snapshot(navigation.session) == before, "View replacement changed Session state")
	main.queue_free()
	await process_frame
	print("TEST 11 PASS: World/Region/Site/Region replacement keeps Session state")

func _test_existing_local_travel_contract() -> void:
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = _new_runtime(session)
	var result: TravelPreviewResult = runtime.query_travel_preview(
			session.party.party_id,
			_find_destination(runtime, session)
		)
	assert(result.success and result.path.cells.size() > 1, "Existing local travel path disappeared")
	assert(result.estimated_travel_seconds > 0, "Existing local travel time disappeared")
	print("TEST 12 PASS: existing local travel behavior is preserved")

func _test_cross_region_runtime_query() -> void:
	var session: GameSession = GameSession.new()
	session.world_seed = TEST_SEED
	var start: Vector2i = _find_clear_global_cell_near(
		WorldCoordinates.world_region_to_global_region_cell(Vector2i(3, 4), Vector2i(50, 50))
	)
	var destination: Vector2i = _find_clear_global_cell_near(
		WorldCoordinates.world_region_to_global_region_cell(Vector2i(4, 4), Vector2i(50, 50))
	)
	assert(start != Vector2i(-1, -1) and destination != Vector2i(-1, -1), "Could not find cross-Region Runtime endpoints")
	session.party.set_global_region_cell(start)
	session.party.initialized = true
	var runtime: TravelRuntime = _new_runtime(session)
	var result: TravelPreviewResult = runtime.query_travel_preview(session.party.party_id, destination)
	assert(result.success and result.regions_crossed >= 2, "Runtime cross-Region Query could not build a shared path")
	assert(_state_snapshot(session)["active_path"] == "", "Cross-Region Preview mutated active travel")
	print("TEST 13 PASS: shared Runtime Query supports cross-Region travel")

func _test_presentation_preview_state() -> void:
	var map_scene: PackedScene = load("res://scenes/region/RegionMap.tscn") as PackedScene
	var map: RegionMap = map_scene.instantiate() as RegionMap
	get_root().add_child(map)
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = _new_runtime(session)
	var world_cell: Vector2i = session.party.get_world_cell()
	var terrain: RegionTerrainData = world_data.get_or_generate_region_terrain(world_cell, session.world_seed)
	var roads: RegionRoadOverlay = world_data.get_roads_for_region(world_cell, session.world_seed)
	var region: RegionData = world_data.get_region(world_cell)
	var pois: Array[WorldPOIData] = world_data.get_pois_for_region(world_cell, session.world_seed)
	map.setup(region, terrain, pois, session, roads, runtime)
	var before: Dictionary = _state_snapshot(session)
	var destination: Vector2i = _find_destination(runtime, session)
	var destination_region: Dictionary = WorldCoordinates.global_region_cell_to_world_region(destination)
	assert(map.select_destination(destination_region["region_cell"] as Vector2i), "Presentation preview could not be created")
	map.cancel_path_preview()
	assert(_state_snapshot(session) == before, "Clearing Preview Visual changed Runtime state")
	map.queue_free()
	await process_frame
	print("TEST 14 PASS: path preview is Presentation-only state")

func _test_runtime_without_region_map() -> void:
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = _new_runtime(session)
	var result: TravelPreviewResult = runtime.query_travel_preview(
			session.party.party_id,
			_find_destination(runtime, session)
		)
	assert(result.success, "Runtime query required RegionMap Scene")
	print("TEST 15 PASS: Runtime query works without RegionMap")

func _test_runtime_without_ui() -> void:
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = _new_runtime(session)
	var command: TravelCommandResult = runtime.start_travel(
			session.party.party_id,
			_find_destination(runtime, session)
		)
	assert(command.success and session.is_traveling(), "Runtime command required DebugUI")
	assert(not runtime.finish_travel(), "Runtime finished travel without reaching its destination")
	assert(session.has_travel_plan(), "Runtime incomplete finish cleared travel without UI")
	assert(runtime.cancel_travel(session.party.party_id).success, "Runtime cancel command failed without UI")
	assert(runtime.finish_travel(), "Runtime cancel could not finish without UI")
	assert(not session.has_travel_plan(), "Runtime command could not finish without UI")
	print("TEST 16 PASS: Runtime commands work without UI")

func _test_runtime_dependency_scan() -> void:
	for path: String in [
			"res://scripts/runtime/travel_runtime.gd",
			"res://scripts/runtime/travel_preview_result.gd",
			"res://scripts/runtime/travel_command_result.gd",
			"res://scripts/runtime/site_entry_query_result.gd",
		]:
		var source: String = _source(path)
		for forbidden: String in ["RegionMap", "WorldMap", "SiteMap", "Camera2D", "TileMapLayer", "Control", "DebugUI"]:
			assert(not source.contains(forbidden), "%s depends on Presentation symbol %s" % [path, forbidden])
	print("TEST 17 PASS: Runtime dependency direction is clean")

func _new_session() -> GameSession:
	var session: GameSession = GameSession.new()
	session.world_seed = TEST_SEED
	var start_global_cell: Vector2i = _find_clear_global_cell_near(
		WorldCoordinates.world_region_to_global_region_cell(Vector2i(3, 4), Vector2i(10, 10))
	)
	assert(start_global_cell != Vector2i(-1, -1), "Could not find a passable Runtime test start")
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(start_global_cell)
	session.selected_world_cell = converted["world_cell"] as Vector2i
	session.selected_region_cell = converted["region_cell"] as Vector2i
	session.party.set_global_region_cell(start_global_cell)
	session.party.initialized = true
	return session

func _find_destination(runtime: TravelRuntime, session: GameSession) -> Vector2i:
	var world_cell: Vector2i = session.party.get_world_cell()
	var start_region_cell: Vector2i = session.party.get_region_cell()
	for radius: int in range(1, 20):
		for y: int in range(maxi(0, start_region_cell.y - radius), mini(WorldCoordinates.REGION_GRID_SIZE - 1, start_region_cell.y + radius) + 1):
			for x: int in range(maxi(0, start_region_cell.x - radius), mini(WorldCoordinates.REGION_GRID_SIZE - 1, start_region_cell.x + radius) + 1):
				if maxi(abs(x - start_region_cell.x), abs(y - start_region_cell.y)) != radius:
					continue
				var candidate: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
					world_cell,
					Vector2i(x, y)
				)
				var preview: TravelPreviewResult = runtime.query_travel_preview(session.party.party_id, candidate)
				if preview.success and preview.path != null and preview.path.cells.size() > 1:
					return candidate
	assert(false, "Could not find a nearby Runtime test destination")
	return session.party.current_global_region_cell

func _find_clear_global_cell_near(center: Vector2i) -> Vector2i:
	for radius: int in range(50):
		for y: int in range(center.y - radius, center.y + radius + 1):
			for x: int in range(center.x - radius, center.x + radius + 1):
				if maxi(abs(x - center.x), abs(y - center.y)) != radius:
					continue
				var global_cell: Vector2i = Vector2i(x, y)
				var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(global_cell)
				if not world_data.is_valid_world_cell(converted["world_cell"] as Vector2i):
					continue
				var sample: Vector4 = world_data.terrain_generator.macro_sampler.sample(TEST_SEED, global_cell)
				var terrain_type: int = world_data.terrain_generator.classify_sample(sample)
				if not TerrainType.is_water_like(terrain_type) and sample.z <= 0.0:
					return global_cell
	return Vector2i(-1, -1)

func _new_runtime(session: GameSession) -> TravelRuntime:
	return TravelRuntimeType.new(session, world_data)

func _on_travel_cancelled(_result: TravelCommandResult) -> void:
	cancellation_signal_seen = true

func _first_poi() -> WorldPOIData:
	for y: int in range(1, 5):
		for x: int in range(1, 5):
			var pois: Array[WorldPOIData] = world_data.get_pois_for_region(Vector2i(x, y), TEST_SEED)
			if not pois.is_empty():
				return pois[0]
	return null

func _find_non_poi_cell(world_cell: Vector2i, world_seed: int) -> Vector2i:
	for y: int in range(WorldCoordinates.REGION_GRID_SIZE):
		for x: int in range(WorldCoordinates.REGION_GRID_SIZE):
			var candidate: Vector2i = Vector2i(x, y)
			if world_data.find_poi_at(world_cell, candidate, world_seed) == null:
				return candidate
	return Vector2i.ZERO

func _state_snapshot(session: GameSession) -> Dictionary:
	var region_state: RegionRuntimeState = session.region_runtime_states.get(
			session.party.get_world_cell(),
			null
		) as RegionRuntimeState
	return {
		"position": session.party.current_global_region_cell,
		"world_time": session.world_time_seconds,
		"active_path": session.active_global_travel_path.path_hash() if session.active_global_travel_path != null else "",
		"path_index": session.global_travel_path_index,
		"traveling": session.is_traveling(),
		"region_state_count": session.region_runtime_states.size(),
		"region_revision": region_state.delta.revision if region_state != null else -1,
		"region_owner": region_state.owner_id if region_state != null else "",
		"region_discovered": region_state.discovered if region_state != null else false,
	}

func _source(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert(file != null, "Could not read %s" % path)
	return file.get_as_text()
