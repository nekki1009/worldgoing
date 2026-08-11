class_name TravelRuntime
extends RefCounted

const GlobalTravelPathType = preload("res://scripts/data/global_travel_path.gd")
const PartyPathfinderType = preload("res://scripts/core/party_pathfinder.gd")
const RegionRuntimeType = preload("res://scripts/runtime/region_runtime.gd")
const TravelFailureReasonType = preload("res://scripts/runtime/travel_failure_reason.gd")
const TravelStatusType = preload("res://scripts/runtime/travel_status.gd")
const TravelPreviewResultType = preload("res://scripts/runtime/travel_preview_result.gd")
const TravelCommandResultType = preload("res://scripts/runtime/travel_command_result.gd")
const TravelCellResultType = preload("res://scripts/runtime/travel_cell_result.gd")
const SiteEntryQueryResultType = preload("res://scripts/runtime/site_entry_query_result.gd")
const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")
const SiteFeatureStateType = preload("res://scripts/runtime/site_feature_state.gd")
const SiteRuntimeCommandResultType = preload("res://scripts/runtime/site_runtime_command_result.gd")
const SiteRuntimeFailureReasonType = preload("res://scripts/runtime/site_runtime_failure_reason.gd")
const SiteRuntimeQueryResultType = preload("res://scripts/runtime/site_runtime_query_result.gd")
const SiteRuntimeSnapshotType = preload("res://scripts/runtime/site_runtime_snapshot.gd")
const TravelStepResultType = preload("res://scripts/runtime/travel_step_result.gd")

signal travel_started(result: TravelCommandResult)
signal travel_cancelled(result: TravelCommandResult)

var session: GameSession
var world_data: WorldData
var party_pathfinder: PartyPathfinder = PartyPathfinderType.new()
var region_runtime: RegionRuntime
var local_path_world_cell: Vector2i = Vector2i(-1, -1)
var path_query_resolver_cache: Dictionary = {}
var path_query_active: bool = false

func _init(p_session: GameSession = null, p_world_data: WorldData = null) -> void:
	bind(p_session, p_world_data)

func bind(p_session: GameSession, p_world_data: WorldData) -> void:
	session = p_session
	world_data = p_world_data
	path_query_resolver_cache.clear()
	path_query_active = false
	if region_runtime == null:
		region_runtime = RegionRuntimeType.new()
	region_runtime.bind(session, world_data)

func query_travel_preview(
		party_id: String,
		destination_global_cell: Vector2i,
		destination_poi_id: String = ""
	) -> TravelPreviewResult:
	var result: TravelPreviewResult = TravelPreviewResultType.new()
	result.party_id = party_id
	result.destination_global_cell = destination_global_cell
	result.destination_poi_id = destination_poi_id
	if session == null or session.party == null or session.party.party_id != party_id:
		result.failure_reason = TravelFailureReasonType.Code.INVALID_PARTY
		return result
	if session.has_travel_plan():
		result.failure_reason = TravelFailureReasonType.Code.ALREADY_TRAVELLING
		return result
	if not session.party.initialized:
		result.failure_reason = TravelFailureReasonType.Code.PARTY_NOT_READY
		return result
	if world_data == null:
		result.failure_reason = TravelFailureReasonType.Code.INVALID_DESTINATION
		return result
	result.start_global_cell = session.party.current_global_region_cell
	var start_region: Dictionary = WorldCoordinates.global_region_cell_to_world_region(result.start_global_cell)
	var start_world_cell: Vector2i = start_region["world_cell"] as Vector2i
	if not world_data.is_valid_world_cell(start_world_cell):
		result.failure_reason = TravelFailureReasonType.Code.INVALID_PARTY_POSITION
		return result
	var destination_region: Dictionary = WorldCoordinates.global_region_cell_to_world_region(destination_global_cell)
	var destination_world_cell: Vector2i = destination_region["world_cell"] as Vector2i
	if not world_data.is_valid_world_cell(destination_world_cell):
		result.failure_reason = TravelFailureReasonType.Code.INVALID_DESTINATION
		return result
	path_query_resolver_cache.clear()
	path_query_active = true
	var path: GlobalTravelPath
	if start_region["world_cell"] as Vector2i == destination_world_cell:
		path = _find_local_path(
			start_region["world_cell"] as Vector2i,
			start_region["region_cell"] as Vector2i,
			destination_region["region_cell"] as Vector2i
		)
	else:
		path = party_pathfinder.find_global_path(
			world_data,
			result.start_global_cell,
			destination_global_cell,
			session.world_seed,
			session.party.base_walk_speed_kmh,
			Callable(self, "_travel_cell_info")
		)
	path_query_active = false
	path_query_resolver_cache.clear()
	if path == null or not path.has_path():
		result.failure_reason = _failure_for_path(path, result.start_global_cell, destination_global_cell)
		return result
	result.success = true
	result.set_path(path)
	return result

func resolve_world_destination(world_cell: Vector2i) -> Vector2i:
	if world_data == null or not world_data.is_valid_world_cell(world_cell):
		return Vector2i(-1, -1)
	var center: Vector2i = Vector2i(50, 50)
	for radius: int in range(WorldCoordinates.REGION_GRID_SIZE):
		var min_x: int = maxi(0, center.x - radius)
		var max_x: int = mini(WorldCoordinates.REGION_GRID_SIZE - 1, center.x + radius)
		var min_y: int = maxi(0, center.y - radius)
		var max_y: int = mini(WorldCoordinates.REGION_GRID_SIZE - 1, center.y + radius)
		for y: int in range(min_y, max_y + 1):
			for x: int in range(min_x, max_x + 1):
				if maxi(absi(x - center.x), absi(y - center.y)) != radius:
					continue
				var candidate: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
					world_cell,
					Vector2i(x, y)
				)
				var info: Dictionary = _travel_cell_info(candidate)
				if bool(info.get("valid", false)) and bool(info.get("passable", false)):
					return candidate
	return Vector2i(-1, -1)

func query_travel_cell(global_cell: Vector2i) -> TravelCellResult:
	var result: TravelCellResult = TravelCellResultType.new()
	result.global_cell = global_cell
	if world_data == null:
		result.failure_reason = TravelFailureReasonType.Code.INVALID_DESTINATION
		return result
	var info: Dictionary = _travel_cell_info(global_cell)
	if not bool(info.get("valid", false)):
		result.failure_reason = TravelFailureReasonType.Code.INVALID_DESTINATION
		return result
	result.success = true
	result.passable = bool(info.get("passable", false))
	result.terrain_type = int(info.get("terrain_type", -1))
	result.road = bool(info.get("road", false))
	result.river = bool(info.get("river", false))
	result.river_crossing = bool(info.get("river_crossing", false))
	result.elevation = float(info.get("elevation", 0.0))
	result.speed = float(info.get("travel_speed_kmh", info.get("speed", 0.0)))
	if result.passable and result.speed > 0.0:
		result.travel_seconds = roundi(TravelCostConfig.travel_seconds(
				float(WorldCoordinates.REGION_CELL_SIZE_METERS),
				result.speed
			))
	return result

func start_travel(
		party_id: String,
		destination_global_cell: Vector2i,
		destination_poi_id: String = ""
	) -> TravelCommandResult:
	var result: TravelCommandResult = TravelCommandResultType.new()
	result.party_id = party_id
	result.destination_global_cell = destination_global_cell
	if session != null and session.has_travel_plan():
		result.failure_reason = TravelFailureReasonType.Code.ALREADY_TRAVELLING
		session.travel_failure_reason = result.failure_reason
		return result
	var preview: TravelPreviewResult = query_travel_preview(
			party_id,
			destination_global_cell,
			destination_poi_id
		)
	if not preview.has_path():
		result.failure_reason = preview.failure_reason
		if session != null:
			session.travel_failure_reason = result.failure_reason
		return result
	var authoritative_path: GlobalTravelPath = preview.path
	authoritative_path.destination_poi_id = destination_poi_id
	session.set_travel_plan(authoritative_path, destination_poi_id)
	if not session.confirm_travel():
		session.clear_travel()
		result.failure_reason = TravelFailureReasonType.Code.NO_PATH
		session.travel_failure_reason = result.failure_reason
		return result
	result.success = true
	result.path = authoritative_path
	session.travel_failure_reason = TravelFailureReasonType.Code.NONE
	session.last_travel_status = TravelStatusType.Code.STARTED
	travel_started.emit(result)
	return result

func cancel_travel(party_id: String) -> TravelCommandResult:
	var result: TravelCommandResult = TravelCommandResultType.new()
	result.party_id = party_id
	if session == null or session.party == null or session.party.party_id != party_id:
		result.failure_reason = TravelFailureReasonType.Code.INVALID_PARTY
		return result
	if not session.has_travel_plan():
		result.failure_reason = TravelFailureReasonType.Code.NO_ACTIVE_TRAVEL
		session.travel_failure_reason = result.failure_reason
		return result
	result.success = true
	result.destination_global_cell = session.active_global_travel_path.destination_global_cell
	if session.is_traveling():
		session.travel_cancel_requested = true
		session.last_travel_status = TravelStatusType.Code.CANCEL_REQUESTED
		result.cancel_requested = true
		return result
	session.clear_travel()
	session.last_travel_status = TravelStatusType.Code.CANCELLED
	travel_cancelled.emit(result)
	return result

func set_travel_speed_multiplier(party_id: String, multiplier: float) -> TravelCommandResult:
	var result: TravelCommandResult = TravelCommandResultType.new()
	result.party_id = party_id
	if session == null or session.party == null or session.party.party_id != party_id:
		result.failure_reason = TravelFailureReasonType.Code.INVALID_PARTY
		return result
	if not session.is_traveling():
		result.failure_reason = TravelFailureReasonType.Code.NO_ACTIVE_TRAVEL
		return result
	session.travel_speed_multiplier = clampf(multiplier, 1.0, 16.0)
	result.success = true
	return result

func get_active_travel_path() -> GlobalTravelPath:
	if session == null:
		return null
	return session.active_global_travel_path

func get_active_travel_state() -> GlobalTravelPath:
	return get_active_travel_path()

func get_next_travel_step() -> TravelStepResult:
	var result: TravelStepResult = TravelStepResultType.new()
	if session == null or not session.is_traveling() or session.active_global_travel_path == null:
		result.failure_reason = TravelFailureReasonType.Code.NO_ACTIVE_TRAVEL
		return result
	var path: GlobalTravelPath = session.active_global_travel_path
	return _make_step_result(path, session.global_travel_path_index)

func commit_travel_step(path_index: int) -> TravelStepResult:
	var result: TravelStepResult = get_next_travel_step()
	if not result.success:
		return result
	if result.path_index != path_index:
		result.success = false
		result.failure_reason = TravelFailureReasonType.Code.STALE_TRAVEL_STEP
		return result
	session.party.set_global_region_cell(result.next_global_cell)
	session.global_travel_path_index = path_index + 1
	session.advance_world_time(result.step_travel_seconds)
	session.selected_world_cell = result.next_world_cell
	session.selected_region_cell = result.next_region_cell
	return result

func finish_travel() -> bool:
	if session == null or not session.has_travel_plan():
		return false
	var path: GlobalTravelPath = session.active_global_travel_path
	if session.travel_cancel_requested:
		var result: TravelCommandResult = TravelCommandResultType.new()
		result.success = true
		result.cancel_requested = true
		result.party_id = session.party.party_id if session.party != null else ""
		result.destination_global_cell = path.destination_global_cell
		session.last_travel_status = TravelStatusType.Code.CANCELLED
		session.travel_failure_reason = TravelFailureReasonType.Code.NONE
		session.clear_travel()
		travel_cancelled.emit(result)
		return true
	if not session.is_traveling() or path == null or path.cells.is_empty():
		return false
	var reached_end: bool = session.global_travel_path_index >= path.cells.size() - 1
	var at_destination: bool = session.party != null \
		and session.party.current_global_region_cell == path.destination_global_cell
	if not reached_end or not at_destination:
		return false
	session.last_travel_status = TravelStatusType.Code.ARRIVED
	session.travel_failure_reason = TravelFailureReasonType.Code.NONE
	session.clear_travel()
	return true

func fail_travel(
		failure_reason: int = TravelFailureReasonType.Code.TRAVEL_STEP_FAILED
	) -> TravelCommandResult:
	var result: TravelCommandResult = TravelCommandResultType.new()
	if session == null or not session.has_travel_plan():
		result.failure_reason = TravelFailureReasonType.Code.NO_ACTIVE_TRAVEL
		return result
	var path: GlobalTravelPath = session.active_global_travel_path
	result.party_id = session.party.party_id if session.party != null else ""
	result.destination_global_cell = path.destination_global_cell
	result.failure_reason = failure_reason
	session.travel_failure_reason = failure_reason
	session.last_travel_status = TravelStatusType.Code.FAILED
	session.clear_travel()
	return result

func query_site_entry(party_id: String, poi_id: String) -> SiteEntryQueryResult:
	var result: SiteEntryQueryResult = SiteEntryQueryResultType.new()
	result.party_id = party_id
	result.site_id = poi_id
	result.poi_id = poi_id
	var poi: WorldPOIData = _find_poi_by_id(poi_id)
	if poi == null:
		result.failure_reason = TravelFailureReasonType.Code.SITE_NOT_FOUND
		return result
	result.poi = poi
	result.site_id = poi.poi_id
	result.site_definition = world_data.get_site_definition(poi)
	result.world_cell = poi.world_cell
	result.region_cell = poi.region_cell
	if session == null or session.party == null or session.party.party_id != party_id:
		result.failure_reason = TravelFailureReasonType.Code.INVALID_PARTY
		return result
	if not session.party.initialized:
		result.failure_reason = TravelFailureReasonType.Code.PARTY_NOT_READY
		return result
	if session.is_traveling() or not session.party.is_at(poi.world_cell, poi.region_cell):
		result.failure_reason = TravelFailureReasonType.Code.NOT_AT_SITE
		return result
	result.can_enter = true
	return result

func ensure_site_runtime_state(site_id: String) -> SiteRuntimeCommandResult:
	var result: SiteRuntimeCommandResult = SiteRuntimeCommandResultType.new()
	result.site_id = site_id
	if session == null or site_id.is_empty():
		result.failure_reason = SiteRuntimeFailureReasonType.Code.INVALID_SITE_ID
		return result
	var definition: SiteData = _find_site_definition(site_id)
	if definition == null:
		result.failure_reason = SiteRuntimeFailureReasonType.Code.SITE_NOT_FOUND
		return result
	var existing: SiteRuntimeState = session.find_site_runtime_state(site_id)
	var state: SiteRuntimeState = session.ensure_site_runtime_state(definition)
	if state == null:
		result.failure_reason = SiteRuntimeFailureReasonType.Code.SITE_IDENTITY_MISMATCH
		return result
	result.success = true
	result.changed = existing == null
	result.revision = state.revision
	return result

func query_site_snapshot(site_id: String) -> SiteRuntimeQueryResult:
	var result: SiteRuntimeQueryResult = SiteRuntimeQueryResultType.new()
	result.site_id = site_id
	if session == null or site_id.is_empty():
		result.failure_reason = SiteRuntimeFailureReasonType.Code.INVALID_SITE_ID
		return result
	var definition: SiteData = _find_site_definition(site_id)
	if definition == null:
		result.failure_reason = SiteRuntimeFailureReasonType.Code.SITE_NOT_FOUND
		return result
	var state: SiteRuntimeState = session.find_site_runtime_state(site_id)
	if state == null:
		result.snapshot = _snapshot_for_definition(definition)
	else:
		if not state.matches_definition(definition):
			result.failure_reason = SiteRuntimeFailureReasonType.Code.SITE_IDENTITY_MISMATCH
			return result
		result.snapshot = _snapshot_for_definition(definition, state.to_snapshot(true))
	result.revision = result.snapshot.revision
	result.success = true
	return result

func get_site_snapshot(site_id: String) -> SiteRuntimeSnapshot:
	var result: SiteRuntimeQueryResult = query_site_snapshot(site_id)
	return result.snapshot if result.success else null

func begin_site_visit(party_id: String, site_id: String) -> SiteRuntimeCommandResult:
	var result: SiteRuntimeCommandResult = SiteRuntimeCommandResultType.new()
	result.site_id = site_id
	if session == null or session.party == null or session.party.party_id != party_id:
		result.failure_reason = SiteRuntimeFailureReasonType.Code.INVALID_PARTY
		return result
	if site_id.is_empty():
		result.failure_reason = SiteRuntimeFailureReasonType.Code.INVALID_SITE_ID
		return result
	var definition: SiteData = _find_site_definition(site_id)
	if definition == null:
		result.failure_reason = SiteRuntimeFailureReasonType.Code.SITE_NOT_FOUND
		return result
	if not session.party.initialized \
		or session.is_traveling() \
		or not session.party.is_at(definition.parent_world_cell, definition.parent_region_cell):
		result.failure_reason = SiteRuntimeFailureReasonType.Code.PARTY_NOT_AT_SITE
		return result
	var prepared: SiteRuntimeCommandResult = ensure_site_runtime_state(site_id)
	if not prepared.success:
		return prepared
	result.success = true
	result.changed = prepared.changed \
		or session.current_site_id != site_id \
		or session.party.current_site_local_cell != SiteLayoutDataType.ENTRANCE_CELL
	result.revision = prepared.revision
	session.current_site_id = site_id
	session.party.current_site_local_cell = SiteLayoutDataType.ENTRANCE_CELL
	return result

func leave_site(party_id: String) -> SiteRuntimeCommandResult:
	var result: SiteRuntimeCommandResult = SiteRuntimeCommandResultType.new()
	if session == null or session.party == null or session.party.party_id != party_id:
		result.failure_reason = SiteRuntimeFailureReasonType.Code.INVALID_PARTY
		return result
	result.site_id = session.current_site_id
	result.success = true
	result.changed = not session.current_site_id.is_empty() \
		or SiteLayoutDataType.is_valid_cell(session.party.current_site_local_cell)
	session.current_site_id = ""
	session.party.current_site_local_cell = SiteLayoutDataType.INVALID_CELL
	return result

func move_party_in_site(
		party_id: String,
		site_id: String,
		direction: Vector2i
	) -> SiteRuntimeCommandResult:
	var result: SiteRuntimeCommandResult = SiteRuntimeCommandResultType.new()
	result.site_id = site_id
	if session == null or session.party == null or session.party.party_id != party_id:
		result.failure_reason = SiteRuntimeFailureReasonType.Code.INVALID_PARTY
		return result
	if site_id.is_empty():
		result.failure_reason = SiteRuntimeFailureReasonType.Code.INVALID_SITE_ID
		return result
	var definition: SiteData = _find_site_definition(site_id)
	if definition == null:
		result.failure_reason = SiteRuntimeFailureReasonType.Code.SITE_NOT_FOUND
		return result
	if session.current_site_id != site_id \
		or not session.party.initialized \
		or session.is_traveling() \
		or not session.party.is_at(definition.parent_world_cell, definition.parent_region_cell) \
		or not SiteLayoutDataType.is_valid_cell(session.party.current_site_local_cell):
		result.failure_reason = SiteRuntimeFailureReasonType.Code.PARTY_NOT_AT_SITE
		return result
	if absi(direction.x) + absi(direction.y) != 1:
		result.failure_reason = SiteRuntimeFailureReasonType.Code.INVALID_DIRECTION
		return result
	var destination: Vector2i = session.party.current_site_local_cell + direction
	if not SiteLayoutDataType.is_valid_cell(destination):
		result.failure_reason = SiteRuntimeFailureReasonType.Code.OUT_OF_BOUNDS
		return result
	session.party.current_site_local_cell = destination
	var state: SiteRuntimeState = session.find_site_runtime_state(site_id)
	result.success = true
	result.changed = true
	result.revision = state.revision if state != null else 0
	return result

func set_site_test_flag(site_id: String, enabled: bool) -> SiteRuntimeCommandResult:
	var result: SiteRuntimeCommandResult = _prepare_site_runtime_command(site_id)
	if not result.success:
		return result
	var state: SiteRuntimeState = session.find_site_runtime_state(site_id)
	var before_revision: int = state.revision
	state.set_test_flag(enabled)
	result.changed = state.revision != before_revision
	result.revision = state.revision
	return result

func add_site_test_feature(
		site_id: String,
		feature_id: String,
		feature_type: String = "TEST"
	) -> SiteRuntimeCommandResult:
	var result: SiteRuntimeCommandResult = SiteRuntimeCommandResultType.new()
	result.site_id = site_id
	if feature_id.is_empty():
		result.failure_reason = SiteRuntimeFailureReasonType.Code.INVALID_FEATURE_ID
		return result
	var prepared: SiteRuntimeCommandResult = _prepare_site_runtime_command(site_id)
	if not prepared.success:
		return prepared
	result = prepared
	var state: SiteRuntimeState = session.find_site_runtime_state(site_id)
	var code: int = state.add_feature(SiteFeatureStateType.new(feature_id, feature_type))
	result.failure_reason = code
	result.success = code == SiteRuntimeFailureReasonType.Code.NONE
	result.changed = result.success
	result.revision = state.revision
	return result

func remove_site_test_feature(site_id: String, feature_id: String) -> SiteRuntimeCommandResult:
	var result: SiteRuntimeCommandResult = SiteRuntimeCommandResultType.new()
	result.site_id = site_id
	if feature_id.is_empty():
		result.failure_reason = SiteRuntimeFailureReasonType.Code.INVALID_FEATURE_ID
		return result
	if session == null or site_id.is_empty():
		result.failure_reason = SiteRuntimeFailureReasonType.Code.INVALID_SITE_ID
		return result
	var definition: SiteData = _find_site_definition(site_id)
	if definition == null:
		result.failure_reason = SiteRuntimeFailureReasonType.Code.SITE_NOT_FOUND
		return result
	var state: SiteRuntimeState = session.find_site_runtime_state(site_id)
	if state == null:
		result.failure_reason = SiteRuntimeFailureReasonType.Code.FEATURE_NOT_FOUND
		return result
	if not state.matches_definition(definition):
		result.failure_reason = SiteRuntimeFailureReasonType.Code.SITE_IDENTITY_MISMATCH
		return result
	var code: int = state.remove_feature(feature_id)
	result.failure_reason = code
	result.success = code == SiteRuntimeFailureReasonType.Code.NONE
	result.changed = result.success
	result.revision = state.revision
	return result

func query_site_entry_at(
		party_id: String,
		world_cell: Vector2i,
		region_cell: Vector2i
	) -> SiteEntryQueryResult:
	var result: SiteEntryQueryResult = SiteEntryQueryResultType.new()
	result.party_id = party_id
	result.world_cell = world_cell
	result.region_cell = region_cell
	if world_data == null or session == null:
		result.failure_reason = TravelFailureReasonType.Code.SITE_NOT_FOUND
		return result
	var poi: WorldPOIData = world_data.find_poi_at(world_cell, region_cell, session.world_seed)
	if poi == null:
		result.failure_reason = TravelFailureReasonType.Code.SITE_NOT_FOUND
		return result
	return query_site_entry(party_id, poi.poi_id)

func ensure_party_ready() -> void:
	if session == null or session.party == null or session.party.initialized or world_data == null:
		return
	var selected_before_spawn: Vector2i = session.selected_world_cell
	var spawn_world_cell: Vector2i = session.party.get_world_cell()
	var terrain_data: RegionTerrainData = world_data.get_or_generate_region_terrain(
			spawn_world_cell,
			session.world_seed
		)
	var road_overlay: RegionRoadOverlay = world_data.get_roads_for_region(
			spawn_world_cell,
			session.world_seed
		)
	var spawn_cell: Vector2i = _find_passable_spawn(terrain_data, road_overlay, session.party.get_region_cell())
	if spawn_cell == Vector2i(-1, -1):
		spawn_cell = Vector2i(50, 50)
	session.party.set_global_region_cell(WorldCoordinates.world_region_to_global_region_cell(
			spawn_world_cell,
			spawn_cell
		))
	session.party.initialized = true
	session.selected_world_cell = selected_before_spawn
	session.selected_region_cell = spawn_cell

func ensure_party_spawn(world_cell: Vector2i, preferred_region_cell: Vector2i) -> void:
	if session == null or session.party == null or session.party.initialized or world_data == null:
		return
	var terrain_data: RegionTerrainData = world_data.get_or_generate_region_terrain(world_cell, session.world_seed)
	var road_overlay: RegionRoadOverlay = world_data.get_roads_for_region(world_cell, session.world_seed)
	var spawn_cell: Vector2i = _find_passable_spawn(terrain_data, road_overlay, preferred_region_cell)
	if spawn_cell == Vector2i(-1, -1):
		spawn_cell = Vector2i(50, 50)
	session.party.set_global_region_cell(WorldCoordinates.world_region_to_global_region_cell(world_cell, spawn_cell))
	session.party.initialized = true
	session.selected_region_cell = spawn_cell

func _travel_cell_info(global_cell: Vector2i) -> Dictionary:
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(global_cell)
	var world_cell: Vector2i = converted["world_cell"] as Vector2i
	var region_cell: Vector2i = converted["region_cell"] as Vector2i
	if world_data == null or not world_data.is_valid_world_cell(world_cell):
		return {
			"valid": false,
			"passable": false,
			"global_region_cell": global_cell,
			"world_cell": world_cell,
			"region_cell": region_cell,
		}
	var resolver: RegionStateResolver = path_query_resolver_cache.get(world_cell) as RegionStateResolver
	if resolver == null and region_runtime != null:
		resolver = region_runtime.query_region(world_cell)
		if path_query_active and resolver != null:
			path_query_resolver_cache[world_cell] = resolver
	if resolver == null or not resolver.is_valid():
		return {
			"valid": false,
			"passable": false,
			"global_region_cell": global_cell,
			"world_cell": world_cell,
			"region_cell": region_cell,
		}
	var terrain_type: int = resolver.get_terrain(region_cell)
	var road: bool = resolver.has_road(region_cell)
	var river: bool = resolver.has_river(region_cell)
	var river_crossing: bool = resolver.has_river_crossing(region_cell)
	var speed: float = TravelCostConfig.get_speed_kmh(
			terrain_type,
			road,
			session.party.base_walk_speed_kmh if session != null and session.party != null else TravelCostConfig.DEFAULT_WALK_SPEED_KMH
		)
	return {
		"valid": true,
		"passable": TravelCostConfig.is_passable(terrain_type, river, river_crossing),
		"terrain_type": terrain_type,
		"road": road,
		"river": river,
		"river_crossing": river_crossing,
		"elevation": resolver.get_elevation(region_cell),
		"moisture": resolver.get_moisture(region_cell),
		"river_strength": resolver.get_river_strength(region_cell),
		"speed": speed,
		"travel_speed_kmh": speed,
		"global_region_cell": global_cell,
		"world_cell": world_cell,
		"region_cell": region_cell,
	}

func _travel_local_cell_info(region_cell: Vector2i) -> Dictionary:
	if local_path_world_cell == Vector2i(-1, -1):
		return {"valid": false, "passable": false}
	return _travel_cell_info(WorldCoordinates.world_region_to_global_region_cell(
		local_path_world_cell,
		region_cell
	))

func _find_local_path(
		world_cell: Vector2i,
		start_region_cell: Vector2i,
		destination_region_cell: Vector2i
	) -> GlobalTravelPath:
	if world_data == null or session == null:
		return null
	local_path_world_cell = world_cell
	var local_result: PartyPathResult = party_pathfinder.find_path_with_cell_info(
			start_region_cell,
			destination_region_cell,
			session.party.base_walk_speed_kmh,
			Callable(self, "_travel_local_cell_info")
		)
	local_path_world_cell = Vector2i(-1, -1)
	if not local_result.has_path():
		return null
	var result: GlobalTravelPath = GlobalTravelPathType.new()
	result.start_global_cell = WorldCoordinates.world_region_to_global_region_cell(world_cell, start_region_cell)
	result.destination_global_cell = WorldCoordinates.world_region_to_global_region_cell(world_cell, destination_region_cell)
	for local_cell: Vector2i in local_result.cells:
		result.cells.append(WorldCoordinates.world_region_to_global_region_cell(world_cell, local_cell))
	result.step_travel_seconds = local_result.step_travel_seconds.duplicate()
	result.total_distance_meters = local_result.total_distance_meters
	result.estimated_travel_seconds = local_result.estimated_travel_seconds
	result.regions_crossed = 1
	return result

func _failure_for_path(path: GlobalTravelPath, start_cell: Vector2i, destination_cell: Vector2i) -> int:
	if path != null and path.error_message == "Path search limit exceeded":
		return TravelFailureReasonType.Code.DESTINATION_TOO_FAR
	var destination_info: TravelCellResult = query_travel_cell(destination_cell)
	if not destination_info.success:
		return TravelFailureReasonType.Code.INVALID_DESTINATION
	if not destination_info.passable:
		return TravelFailureReasonType.Code.IMPASSABLE
	var start_info: TravelCellResult = query_travel_cell(start_cell)
	if not start_info.success:
		return TravelFailureReasonType.Code.INVALID_PARTY_POSITION
	if not start_info.passable:
		return TravelFailureReasonType.Code.IMPASSABLE
	return TravelFailureReasonType.Code.NO_PATH

func _make_step_result(path: GlobalTravelPath, path_index: int) -> TravelStepResult:
	var result: TravelStepResult = TravelStepResultType.new()
	result.path_index = path_index
	if path == null or path_index < 0 or path_index >= path.cells.size() - 1:
		result.failure_reason = TravelFailureReasonType.Code.NO_ACTIVE_TRAVEL
		return result
	result.from_global_cell = path.cells[path_index]
	result.next_global_cell = path.cells[path_index + 1]
	var previous_region: Dictionary = WorldCoordinates.global_region_cell_to_world_region(result.from_global_cell)
	var next_region: Dictionary = WorldCoordinates.global_region_cell_to_world_region(result.next_global_cell)
	result.previous_world_cell = previous_region["world_cell"] as Vector2i
	result.next_world_cell = next_region["world_cell"] as Vector2i
	result.next_region_cell = next_region["region_cell"] as Vector2i
	result.step_travel_seconds = path.step_travel_seconds[path_index] if path_index < path.step_travel_seconds.size() else 0
	result.success = true
	return result

func _find_passable_spawn(
		terrain_data: RegionTerrainData,
		road_overlay: RegionRoadOverlay,
		center: Vector2i
	) -> Vector2i:
	if terrain_data == null:
		return Vector2i(-1, -1)
	var clamped_center: Vector2i = Vector2i(
			clampi(center.x, 0, WorldCoordinates.REGION_GRID_SIZE - 1),
			clampi(center.y, 0, WorldCoordinates.REGION_GRID_SIZE - 1)
		)
	for radius: int in range(WorldCoordinates.REGION_GRID_SIZE * 2):
		var min_x: int = maxi(0, clamped_center.x - radius)
		var max_x: int = mini(WorldCoordinates.REGION_GRID_SIZE - 1, clamped_center.x + radius)
		var min_y: int = maxi(0, clamped_center.y - radius)
		var max_y: int = mini(WorldCoordinates.REGION_GRID_SIZE - 1, clamped_center.y + radius)
		for y: int in range(min_y, max_y + 1):
			for x: int in range(min_x, max_x + 1):
				var candidate: Vector2i = Vector2i(x, y)
				if maxi(absi(candidate.x - clamped_center.x), absi(candidate.y - clamped_center.y)) != radius:
					continue
				var terrain_type: int = terrain_data.get_terrain(candidate)
				if TravelCostConfig.is_passable(
						terrain_type,
						terrain_data.has_river(candidate),
						road_overlay != null and road_overlay.has_river_crossing(candidate)
					):
					return candidate
	return Vector2i(-1, -1)

func _find_poi_by_id(poi_id: String) -> WorldPOIData:
	if world_data == null or session == null or poi_id.is_empty():
		return null
	return world_data.find_poi_by_id(poi_id, session.world_seed)

func _find_site_definition(site_id: String) -> SiteData:
	if world_data == null or site_id.is_empty():
		return null
	var poi: WorldPOIData = _find_poi_by_id(site_id)
	return world_data.get_site_definition(poi) if poi != null else null

func _snapshot_for_definition(
		definition: SiteData,
		snapshot: SiteRuntimeSnapshot = null
	) -> SiteRuntimeSnapshot:
	if snapshot == null:
		snapshot = SiteRuntimeSnapshotType.new()
	snapshot.site_id = definition.site_id
	snapshot.source_poi_id = definition.source_poi_id
	snapshot.site_name = definition.site_name
	snapshot.site_type = definition.site_type
	snapshot.parent_world_cell = definition.parent_world_cell
	snapshot.parent_region_cell = definition.parent_region_cell
	snapshot.global_region_cell = definition.global_region_cell
	snapshot.base_generation_version = definition.base_generation_version
	snapshot.site_seed = definition.site_seed
	snapshot.entrance_local_meters = definition.entrance_local_meters
	snapshot.entrance_global_meters = definition.entrance_global_meters
	snapshot.source_terrain_type = definition.source_terrain_type
	snapshot.source_elevation = definition.source_elevation
	snapshot.source_moisture = definition.source_moisture
	snapshot.source_river_nearby = definition.source_river_nearby
	snapshot.source_candidate_cell = definition.source_candidate_cell
	snapshot.source_priority = definition.source_priority
	snapshot.layout = world_data.get_site_layout(definition) if world_data != null else null
	var parent_region: RegionData = world_data.get_region(definition.parent_world_cell) \
		if world_data != null else null
	if parent_region != null:
		snapshot.parent_region_id = parent_region.region_id
		snapshot.parent_region_name = parent_region.region_name
	if session != null:
		snapshot.world_seed = session.world_seed
		snapshot.world_time_seconds = session.world_time_seconds
		if session.party != null:
			snapshot.party_id = session.party.party_id
			snapshot.party_global_region_cell = session.party.current_global_region_cell
			snapshot.party_at_site = session.party.initialized \
				and not session.is_traveling() \
				and session.party.current_global_region_cell == definition.global_region_cell
			if snapshot.party_at_site and session.current_site_id == definition.site_id:
				snapshot.party_site_local_cell = session.party.current_site_local_cell
	return snapshot

func _prepare_site_runtime_command(site_id: String) -> SiteRuntimeCommandResult:
	var result: SiteRuntimeCommandResult = SiteRuntimeCommandResultType.new()
	result.site_id = site_id
	if session == null or site_id.is_empty():
		result.failure_reason = SiteRuntimeFailureReasonType.Code.INVALID_SITE_ID
		return result
	var definition: SiteData = _find_site_definition(site_id)
	if definition == null:
		result.failure_reason = SiteRuntimeFailureReasonType.Code.SITE_NOT_FOUND
		return result
	var state: SiteRuntimeState = session.ensure_site_runtime_state(definition)
	if state == null:
		result.failure_reason = SiteRuntimeFailureReasonType.Code.SITE_IDENTITY_MISMATCH
		return result
	result.success = true
	result.revision = state.revision
	return result
