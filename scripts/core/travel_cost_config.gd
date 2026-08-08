class_name TravelCostConfig
extends RefCounted

const DEFAULT_WALK_SPEED_KMH: float = 5.0
const ROAD_SPEED_KMH: float = 6.0
const FOREST_SPEED_MULTIPLIER: float = 0.70
const MOUNTAIN_SPEED_MULTIPLIER: float = 0.40
const RIVER_CROSSING_PENALTY_SECONDS: int = 180
const SLOPE_PENALTY_SECONDS_PER_ELEVATION: float = 60.0

static func get_speed_kmh(terrain_type: int, has_road: bool, base_speed_kmh: float) -> float:
	if has_road:
		return ROAD_SPEED_KMH
	var base_speed: float = maxf(base_speed_kmh, 0.01)
	match terrain_type:
		TerrainType.FOREST:
			return base_speed * FOREST_SPEED_MULTIPLIER
		TerrainType.MOUNTAIN:
			return base_speed * MOUNTAIN_SPEED_MULTIPLIER
		_:
			return base_speed

static func is_passable(terrain_type: int, river: bool, river_crossing: bool) -> bool:
	if terrain_type == TerrainType.WATER:
		return false
	if river and not river_crossing:
		return false
	return terrain_type == TerrainType.PLAINS \
		or terrain_type == TerrainType.FOREST \
		or terrain_type == TerrainType.MOUNTAIN

static func step_distance_meters(direction: Vector2i) -> float:
	return float(WorldCoordinates.REGION_CELL_SIZE_METERS) * (
		sqrt(2.0) if direction.x != 0 and direction.y != 0 else 1.0
	)

static func travel_seconds(distance_meters: float, speed_kmh: float) -> float:
	return distance_meters / 1000.0 / maxf(speed_kmh, 0.01) * 3600.0

static func slope_penalty_seconds(elevation_delta: float) -> float:
	return absf(elevation_delta) * SLOPE_PENALTY_SECONDS_PER_ELEVATION

static func step_travel_seconds(
		current_info: Dictionary,
		next_info: Dictionary,
		direction: Vector2i,
		base_speed_kmh: float
	) -> float:
	if not bool(next_info.get("passable", false)):
		return INF
	var speed: float = get_speed_kmh(
			int(next_info.get("terrain_type", TerrainType.PLAINS)),
			bool(next_info.get("road", false)),
			base_speed_kmh
		)
	var seconds: float = travel_seconds(step_distance_meters(direction), speed)
	seconds += slope_penalty_seconds(
			float(next_info.get("elevation", 0.0)) - float(current_info.get("elevation", 0.0))
		)
	if bool(next_info.get("river_crossing", false)) \
		and not bool(current_info.get("river", false)):
		seconds += float(RIVER_CROSSING_PENALTY_SECONDS)
	return seconds

static func minimum_step_seconds(base_speed_kmh: float) -> float:
	return travel_seconds(
			float(WorldCoordinates.REGION_CELL_SIZE_METERS),
			maxf(ROAD_SPEED_KMH, base_speed_kmh)
		)

static func format_duration(total_seconds: int) -> String:
	var seconds: int = maxi(total_seconds, 0)
	if seconds == 0:
		return "0m"
	var hours: int = floori(float(seconds) / 3600.0)
	var minutes: int = floori(float(seconds % 3600) / 60.0)
	if hours > 0:
		return "%dh %02dm" % [hours, minutes]
	return "%dm" % maxi(minutes, 1)
