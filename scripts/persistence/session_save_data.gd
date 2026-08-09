class_name SessionSaveData
extends RefCounted

const FORMAT_VERSION: int = 1

var format_version: int = FORMAT_VERSION
var terrain_generation_version: int = RegionTerrainGenerator.GENERATION_VERSION
var poi_generation_version: int = WorldPOIGenerator.GENERATION_VERSION
var road_generation_version: int = WorldRoadGenerator.GENERATION_VERSION
var world_seed: int = GameSession.DEFAULT_WORLD_SEED
var world_time_seconds: int = GameSession.INITIAL_WORLD_TIME_SECONDS
var party_id: String = ""
var party_display_name: String = ""
var party_global_cell: Vector2i = Vector2i.ZERO
var party_base_walk_speed_kmh: float = TravelCostConfig.DEFAULT_WALK_SPEED_KMH
var party_initialized: bool = false
var regions: Array[Dictionary] = []

static func capture(session: GameSession) -> SessionSaveData:
	var result: SessionSaveData = SessionSaveData.new()
	if session == null or session.party == null:
		return result
	result.world_seed = session.world_seed
	result.world_time_seconds = session.world_time_seconds
	result.party_id = session.party.party_id
	result.party_display_name = session.party.display_name
	result.party_global_cell = session.party.current_global_region_cell
	result.party_base_walk_speed_kmh = session.party.base_walk_speed_kmh
	result.party_initialized = session.party.initialized
	for key: Variant in session.region_runtime_states.keys():
		if not key is Vector2i:
			continue
		var state: RegionRuntimeState = session.region_runtime_states[key] as RegionRuntimeState
		if state == null or state.delta == null:
			continue
		var discovered_site_ids: Array[String] = []
		for site_id: Variant in state.discovered_site_ids.keys():
			discovered_site_ids.append(str(site_id))
		discovered_site_ids.sort()
		result.regions.append({
			"world_cell": key as Vector2i,
			"discovered": state.discovered,
			"discovered_site_ids": discovered_site_ids,
			"delta": state.delta.copy(),
		})
	result.regions.sort_custom(Callable(result, "_region_less"))
	return result

func _region_less(left: Dictionary, right: Dictionary) -> bool:
	var left_cell: Vector2i = left["world_cell"] as Vector2i
	var right_cell: Vector2i = right["world_cell"] as Vector2i
	if left_cell.x != right_cell.x:
		return left_cell.x < right_cell.x
	return left_cell.y < right_cell.y
