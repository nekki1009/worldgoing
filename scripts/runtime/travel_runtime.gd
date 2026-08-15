class_name TravelRuntime
extends RefCounted

const GlobalTravelPathType = preload("res://scripts/data/global_travel_path.gd")
const PartyPathfinderType = preload("res://scripts/core/party_pathfinder.gd")
const WeightedGridPathfinderType = preload("res://scripts/core/weighted_grid_pathfinder.gd")
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
var site_pathfinder: WeightedGridPathfinder = WeightedGridPathfinderType.new()
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
	result.site_landform = int(info.get("site_landform", SiteLayoutDataType.Landform.NONE))
	result.travel_exit_mask = int(info.get("travel_exit_mask", 0))
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
	var prepared: SiteRuntimeCommandResult = ensure_site_runtime_state(site_id)
	if not prepared.success:
		return prepared
	var party_at_site: bool = session.party.initialized \
		and session.party.current_global_region_cell == definition.global_region_cell
	result.success = true
	result.changed = prepared.changed \
		or session.current_site_id != site_id \
		or (party_at_site and session.party.current_site_local_cell != SiteLayoutDataType.ENTRANCE_CELL)
	result.revision = prepared.revision
	session.current_site_id = site_id
	if party_at_site:
		session.party.current_site_local_cell = SiteLayoutDataType.ENTRANCE_CELL
	else:
		session.party.current_site_local_cell = SiteLayoutDataType.INVALID_CELL
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
	var layout: SiteLayoutDataType = _resolved_site_layout(definition)
	if layout == null or not layout.has_navigation_base():
		result.failure_reason = SiteRuntimeFailureReasonType.Code.SITE_NOT_FOUND
		return result
	if not layout.can_traverse(session.party.current_site_local_cell, destination):
		result.failure_reason = SiteRuntimeFailureReasonType.Code.BLOCKED
		return result
	session.party.current_site_local_cell = destination
	var state: SiteRuntimeState = session.find_site_runtime_state(site_id)
	result.success = true
	result.changed = true
	result.revision = state.revision if state != null else 0
	return result

func query_site_path(
		site_id: String,
		start: Vector2i,
		destination: Vector2i
	) -> PartyPathResult:
	var result: PartyPathResult = PartyPathResult.new()
	if world_data == null or site_id.is_empty():
		return result
	var definition: SiteData = _find_site_definition(site_id)
	if definition == null:
		return result
	var layout: SiteLayoutDataType = _resolved_site_layout(definition)
	if layout == null or not layout.is_valid() \
		or not SiteLayoutDataType.is_valid_cell(start) \
		or not SiteLayoutDataType.is_valid_cell(destination):
		return result
	var astar: Dictionary = site_pathfinder.find_path(
		start,
		destination,
		Vector2i.ZERO,
		SiteLayoutDataType.GRID_SIZE - Vector2i.ONE,
		Callable(self, "_site_cell_info").bind(layout),
		Callable(self, "_site_step_cost").bind(layout),
		1.0,
		SiteLayoutDataType.NAVIGATION_CELL_COUNT * 4
	)
	var raw_path: Variant = astar.get("path", [])
	if not raw_path is Array:
		return result
	for cell: Variant in raw_path:
		if cell is Vector2i:
			result.cells.append(cell as Vector2i)
	if result.cells.is_empty():
		return result
	result.total_cost = float(astar.get("cost", 0.0))
	result.total_distance_meters = float(result.cells.size() - 1) * SiteLayoutDataType.CELL_SIZE_METERS
	result.step_travel_seconds.clear()
	for _step: int in range(1, result.cells.size()):
		result.step_travel_seconds.append(1)
		result.estimated_travel_seconds += 1
	return result

func _site_cell_info(cell: Vector2i, layout: SiteLayoutDataType) -> Dictionary:
	if layout == null or not SiteLayoutDataType.is_valid_cell(cell):
		return {"passable": false}
	var flags: int = layout.navigation_flags_at(cell)
	var surface: int = layout.surface_flags_at(cell)
	var passable: bool = (flags & SiteLayoutDataType.NAV_BLOCKED) == 0 \
		and (not SiteContentTypes.is_water_surface(layout.native_surface_at(cell)) \
		or (surface & (SiteLayoutDataType.SURFACE_BRIDGE | SiteLayoutDataType.SURFACE_DOCK)) != 0)
	return {
		"passable": passable,
		"elevation": layout.elevation_level_at(cell),
		"surface_flags": surface,
	}

func _site_step_cost(
		current: Vector2i,
		next: Vector2i,
		_direction: Vector2i,
		_current_info: Dictionary,
		_next_info: Dictionary,
		layout: SiteLayoutDataType
	) -> float:
	if layout == null or not layout.can_traverse(current, next):
		return INF
	return 1.0 + float(abs(layout.elevation_level_at(next) - layout.elevation_level_at(current)))

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

func remove_generated_site_feature(site_id: String, feature_id: String) -> SiteRuntimeCommandResult:
	var result: SiteRuntimeCommandResult = _prepare_site_runtime_command(site_id)
	if not result.success:
		return result
	if feature_id.is_empty() or not feature_id.begins_with("generated:%s:" % site_id):
		result.success = false
		result.failure_reason = SiteRuntimeFailureReasonType.Code.INVALID_FEATURE_ID
		return result
	var definition: SiteData = _find_site_definition(site_id)
	var layout: SiteLayoutDataType = world_data.get_site_layout(definition) if world_data != null else null
	if layout == null \
		or (layout.generated_resource(feature_id).is_empty() \
		and layout.generated_facility(feature_id).is_empty() \
		and not _layout_has_wall(layout, feature_id)):
		result.success = false
		result.failure_reason = SiteRuntimeFailureReasonType.Code.FEATURE_NOT_FOUND
		return result
	var state: SiteRuntimeState = session.find_site_runtime_state(site_id)
	var code: int = state.mark_generated_feature_removed(feature_id)
	result.failure_reason = code
	result.success = code == SiteRuntimeFailureReasonType.Code.NONE
	result.changed = result.success
	result.revision = state.revision
	return result

func harvest_site_resource(site_id: String, resource_id: String) -> SiteRuntimeCommandResult:
	var result: SiteRuntimeCommandResult = SiteRuntimeCommandResultType.new()
	result.site_id = site_id
	if session == null or site_id.is_empty():
		result.failure_reason = SiteRuntimeFailureReasonType.Code.INVALID_SITE_ID
		return result
	var definition: SiteData = _find_site_definition(site_id)
	if definition == null:
		result.failure_reason = SiteRuntimeFailureReasonType.Code.SITE_NOT_FOUND
		return result
	var layout: SiteLayoutDataType = world_data.get_site_layout(definition) if world_data != null else null
	if layout == null or layout.generated_resource(resource_id).is_empty():
		result.failure_reason = SiteRuntimeFailureReasonType.Code.FEATURE_NOT_FOUND
		return result
	return remove_generated_site_feature(site_id, resource_id)

func add_site_facility(
		site_id: String,
		feature_id: String,
		facility_type: int,
		origin: Vector2i,
		size: Vector2i = Vector2i.ONE,
		orientation: int = SiteContentTypes.Orientation.HORIZONTAL,
		target: Vector2i = SiteLayoutDataType.INVALID_CELL,
		definition_id: String = ""
	) -> SiteRuntimeCommandResult:
	var result: SiteRuntimeCommandResult = SiteRuntimeCommandResultType.new()
	result.site_id = site_id
	if session == null or site_id.is_empty():
		result.failure_reason = SiteRuntimeFailureReasonType.Code.INVALID_SITE_ID
		return result
	if feature_id.is_empty() or feature_id.begins_with("generated:"):
		result.failure_reason = SiteRuntimeFailureReasonType.Code.INVALID_FEATURE_ID
		return result
	if not SiteContentTypes.is_facility(facility_type):
		result.failure_reason = SiteRuntimeFailureReasonType.Code.INVALID_FACILITY_TYPE
		return result
	var definition: SiteData = _find_site_definition(site_id)
	if definition == null:
		result.failure_reason = SiteRuntimeFailureReasonType.Code.SITE_NOT_FOUND
		return result
	var layout: SiteLayoutDataType = _resolved_site_layout(definition)
	var placement: Dictionary = SiteContentTypes.make_facility(
		feature_id,
		facility_type,
		origin,
		size,
		orientation,
		target,
		definition_id
	)
	if layout == null or not _facility_placement_valid(layout, placement):
		result.failure_reason = SiteRuntimeFailureReasonType.Code.INVALID_FOOTPRINT
		return result
	var prepared: SiteRuntimeCommandResult = _prepare_site_runtime_command(site_id)
	if not prepared.success:
		return prepared
	var state: SiteRuntimeState = session.find_site_runtime_state(site_id)
	var code: int = state.add_feature(SiteFeatureStateType.new(
		feature_id,
		"FACILITY",
		true,
		placement
	))
	prepared.failure_reason = code
	prepared.success = code == SiteRuntimeFailureReasonType.Code.NONE
	prepared.changed = prepared.success
	prepared.revision = state.revision
	return prepared

func remove_site_facility(site_id: String, feature_id: String) -> SiteRuntimeCommandResult:
	if session == null or site_id.is_empty():
		var invalid: SiteRuntimeCommandResult = SiteRuntimeCommandResultType.new()
		invalid.site_id = site_id
		invalid.failure_reason = SiteRuntimeFailureReasonType.Code.INVALID_SITE_ID
		return invalid
	var state: SiteRuntimeState = session.find_site_runtime_state(site_id)
	if state == null:
		var missing: SiteRuntimeCommandResult = SiteRuntimeCommandResultType.new()
		missing.site_id = site_id
		missing.failure_reason = SiteRuntimeFailureReasonType.Code.FEATURE_NOT_FOUND
		return missing
	for feature: SiteFeatureState in state.added_features:
		if feature.feature_id == feature_id and feature.feature_type == "FACILITY":
			return remove_site_test_feature(site_id, feature_id)
	var not_found: SiteRuntimeCommandResult = SiteRuntimeCommandResultType.new()
	not_found.site_id = site_id
	not_found.failure_reason = SiteRuntimeFailureReasonType.Code.FEATURE_NOT_FOUND
	return not_found

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
	var definition: SiteData = world_data.get_site_definition_at(
		world_cell,
		region_cell,
		session.world_seed
	)
	if definition == null:
		result.failure_reason = TravelFailureReasonType.Code.SITE_NOT_FOUND
		return result
	result.can_enter = true
	result.site_id = definition.site_id
	result.site_definition = definition
	var poi: WorldPOIData = world_data.find_poi_at(world_cell, region_cell, session.world_seed)
	if poi != null:
		result.poi = poi
		result.poi_id = poi.poi_id
	return result

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
	var road_connection_offsets: Array[Vector2i] = []
	if road:
		road_connection_offsets = resolver.get_road_connection_offsets(region_cell)
	var river: bool = resolver.has_river(region_cell)
	var river_crossing: bool = resolver.has_river_crossing(region_cell)
	var passable: bool = TravelCostConfig.is_passable(terrain_type, river, river_crossing)
	var site_landform: int = SiteLayoutDataType.landform_for_travel_cell(
		terrain_type,
		road_connection_offsets
	)
	var speed: float = TravelCostConfig.get_speed_kmh(
			terrain_type,
			road,
			session.party.base_walk_speed_kmh if session != null and session.party != null else TravelCostConfig.DEFAULT_WALK_SPEED_KMH
		)
	return {
		"valid": true,
		"passable": passable,
		"terrain_type": terrain_type,
		"site_landform": site_landform,
		"travel_exit_mask": SiteLayoutDataType.exit_mask_for_travel_cell(
			passable,
			site_landform,
			road_connection_offsets
		),
		"road": road,
		"road_connection_offsets": road_connection_offsets,
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
	return world_data.get_site_definition_by_id(site_id, session.world_seed if session != null else 0)

func _resolved_site_layout(definition: SiteData) -> SiteLayoutDataType:
	if world_data == null or definition == null:
		return null
	var layout: SiteLayoutDataType = world_data.get_site_layout(definition)
	var state: SiteRuntimeState = session.find_site_runtime_state(definition.site_id) \
		if session != null else null
	return layout.resolved_with_delta(state.added_features, state.removed_feature_ids) \
		if layout != null and state != null else layout

func _facility_placement_valid(layout: SiteLayoutDataType, placement: Dictionary) -> bool:
	if layout == null:
		return false
	var facility_type: int = int(placement.get("type", -1))
	var origin_value: Variant = placement.get("origin", SiteLayoutDataType.INVALID_CELL)
	var size_value: Variant = placement.get("size", Vector2i.ZERO)
	if not origin_value is Vector2i or not size_value is Vector2i:
		return false
	var origin: Vector2i = origin_value as Vector2i
	var size: Vector2i = size_value as Vector2i
	if size.x <= 0 or size.y <= 0 \
		or not SiteLayoutDataType.is_valid_cell(origin) \
		or not SiteLayoutDataType.is_valid_cell(origin + size - Vector2i.ONE):
		return false
	if facility_type in [SiteContentTypes.Facility.WOOD_WALL, SiteContentTypes.Facility.STONE_WALL,
		SiteContentTypes.Facility.WOOD_STAIR, SiteContentTypes.Facility.STONE_STAIR]:
		var target_value: Variant = placement.get("target", SiteLayoutDataType.INVALID_CELL)
		if not target_value is Vector2i:
			return false
		var target: Vector2i = target_value as Vector2i
		if not SiteLayoutDataType.is_valid_cell(target) \
			or absi(target.x - origin.x) + absi(target.y - origin.y) != 1:
			return false
		if facility_type in [SiteContentTypes.Facility.WOOD_STAIR, SiteContentTypes.Facility.STONE_STAIR] \
			and layout.elevation_level_at(origin) == layout.elevation_level_at(target):
			return false
	if facility_type == SiteContentTypes.Facility.BRIDGE:
		if size.x > 1 and size.y > 1:
			return false
		for y: int in range(size.y):
			for x: int in range(size.x):
				if not SiteContentTypes.is_water_surface(layout.native_surface_at(origin + Vector2i(x, y))):
					return false
	else:
		for y: int in range(size.y):
			for x: int in range(size.x):
				if SiteContentTypes.is_water_surface(layout.native_surface_at(origin + Vector2i(x, y))):
					return false
	for facility: Dictionary in layout.facility_placements:
		if _rects_overlap(origin, size, facility):
			return false
	return true

func _rects_overlap(origin: Vector2i, size: Vector2i, placement: Dictionary) -> bool:
	var other_origin_value: Variant = placement.get("origin", SiteLayoutDataType.INVALID_CELL)
	var other_size_value: Variant = placement.get("size", Vector2i.ZERO)
	if not other_origin_value is Vector2i or not other_size_value is Vector2i:
		return false
	var other_origin: Vector2i = other_origin_value as Vector2i
	var other_size: Vector2i = other_size_value as Vector2i
	return Rect2i(origin, size).intersects(Rect2i(other_origin, other_size))

func _layout_has_wall(layout: SiteLayoutDataType, feature_id: String) -> bool:
	for wall: Dictionary in layout.wall_edges:
		if str(wall.get("id", "")) == feature_id:
			return true
	return false

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
	snapshot.site_landform = definition.site_landform
	snapshot.travel_exit_mask = definition.travel_exit_mask
	snapshot.source_elevation = definition.source_elevation
	snapshot.source_moisture = definition.source_moisture
	snapshot.source_river_nearby = definition.source_river_nearby
	snapshot.source_candidate_cell = definition.source_candidate_cell
	snapshot.source_priority = definition.source_priority
	snapshot.layout = _resolved_site_layout(definition)
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
