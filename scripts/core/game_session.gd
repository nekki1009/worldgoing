class_name GameSession
extends RefCounted

const GlobalTravelPathType = preload("res://scripts/data/global_travel_path.gd")
const RegionRuntimeStateType = preload("res://scripts/runtime/region_runtime_state.gd")
const SiteRuntimeStateType = preload("res://scripts/runtime/site_runtime_state.gd")
const TravelFailureReasonType = preload("res://scripts/runtime/travel_failure_reason.gd")
const TravelStatusType = preload("res://scripts/runtime/travel_status.gd")

const DEFAULT_WORLD_SEED: int = 123456789
const INITIAL_WORLD_TIME_SECONDS: int = 1 * 86400 + 8 * 3600

var world_seed: int = DEFAULT_WORLD_SEED
var selected_world_cell: Vector2i = Vector2i(3, 4)
var selected_region_cell: Vector2i = Vector2i(50, 50)
var current_region_id: String = ""
var current_site_id: String = ""
var party: PartyData = PartyData.new()
var region_runtime_states: Dictionary = {}
var site_runtime_states: Dictionary = {}
var world_time_seconds: int = INITIAL_WORLD_TIME_SECONDS
var active_global_travel_path: GlobalTravelPathType
var global_travel_path_index: int = -1
var global_travel_confirmed: bool = false
var travel_speed_multiplier: float = 1.0
var travel_cancel_requested: bool = false
var travel_failure_reason: int = TravelFailureReasonType.Code.NONE
var last_travel_status: int = TravelStatusType.Code.NONE

func has_travel_plan() -> bool:
	return active_global_travel_path != null

func is_traveling() -> bool:
	return active_global_travel_path != null and global_travel_confirmed

func set_travel_plan(path: GlobalTravelPathType, poi_id: String = "") -> void:
	active_global_travel_path = path
	global_travel_path_index = 0
	global_travel_confirmed = false
	travel_cancel_requested = false
	travel_failure_reason = TravelFailureReasonType.Code.NONE \
		if path != null and path.has_path() else TravelFailureReasonType.Code.NO_PATH
	if path != null:
		path.destination_poi_id = poi_id

func confirm_travel() -> bool:
	if active_global_travel_path == null or not active_global_travel_path.has_path():
		return false
	global_travel_confirmed = true
	travel_cancel_requested = false
	return true

func clear_travel() -> void:
	active_global_travel_path = null
	global_travel_path_index = -1
	global_travel_confirmed = false
	travel_cancel_requested = false

func current_global_region_cell() -> Vector2i:
	return party.current_global_region_cell

func get_region_runtime_state(region_coord: Vector2i) -> RegionRuntimeState:
	var stored: Variant = region_runtime_states.get(region_coord, null)
	if stored is RegionRuntimeState:
		return stored as RegionRuntimeState
	var created: RegionRuntimeState = RegionRuntimeStateType.new(region_coord)
	region_runtime_states[region_coord] = created
	return created

func find_region_runtime_state(region_coord: Vector2i) -> RegionRuntimeState:
	var stored: Variant = region_runtime_states.get(region_coord, null)
	return stored as RegionRuntimeState if stored is RegionRuntimeState else null

func find_site_runtime_state(site_id: String) -> SiteRuntimeState:
	var stored: Variant = site_runtime_states.get(site_id, null)
	if stored is SiteRuntimeState:
		return stored as SiteRuntimeState
	return null

func ensure_site_runtime_state(definition: SiteData) -> SiteRuntimeState:
	if definition == null or definition.site_id.is_empty():
		return null
	var existing: SiteRuntimeState = find_site_runtime_state(definition.site_id)
	if existing != null:
		return existing if existing.matches_definition(definition) else null
	var created: SiteRuntimeState = SiteRuntimeStateType.new(definition)
	site_runtime_states[definition.site_id] = created
	return created

func advance_world_time(seconds: int) -> void:
	world_time_seconds += maxi(seconds, 0)

func world_day() -> int:
	return floori(float(world_time_seconds) / 86400.0)

func world_hour() -> int:
	return floori(float(world_time_seconds % 86400) / 3600.0)

func world_minute() -> int:
	return floori(float(world_time_seconds % 3600) / 60.0)

func format_world_time() -> String:
	return "Day %d  %02d:%02d" % [world_day(), world_hour(), world_minute()]
