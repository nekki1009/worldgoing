class_name TravelCostConfig
extends RefCounted

const DEFAULT_WALK_SPEED_KMH: float = 5.0
const ROAD_SPEED_KMH: float = 6.0
const FOREST_SPEED_MULTIPLIER: float = 0.70
const MOUNTAIN_SPEED_MULTIPLIER: float = 0.40
const SAND_SPEED_MULTIPLIER: float = 0.80
const SNOW_SPEED_MULTIPLIER: float = 0.60
const SWAMP_SPEED_MULTIPLIER: float = 0.50
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
		TerrainType.SAND:
			return base_speed * SAND_SPEED_MULTIPLIER
		TerrainType.SNOW:
			return base_speed * SNOW_SPEED_MULTIPLIER
		TerrainType.SWAMP:
			return base_speed * SWAMP_SPEED_MULTIPLIER
		_:
			return base_speed

static func is_passable(terrain_type: int, river: bool, river_crossing: bool) -> bool:
	if not TerrainType.is_valid(terrain_type) or TerrainType.is_water_like(terrain_type):
		return false
	if river and not river_crossing:
		return false
	return true

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
	if not can_traverse_site_edge(current_info, next_info, direction):
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

static func can_traverse_site_edge(
		current_info: Dictionary,
		next_info: Dictionary,
		direction: Vector2i
	) -> bool:
	if not bool(current_info.get("passable", false)) \
		or not bool(next_info.get("passable", false)):
		return false
	var exit_bit: int = SiteLayoutData.exit_bit(direction)
	var entry_bit: int = SiteLayoutData.exit_bit(-direction)
	if exit_bit == 0 or entry_bit == 0:
		return false
	var current_mask: int = int(current_info.get("travel_exit_mask", SiteLayoutData.EXIT_ALL))
	var next_mask: int = int(next_info.get("travel_exit_mask", SiteLayoutData.EXIT_ALL))
	return (current_mask & exit_bit) != 0 and (next_mask & entry_bit) != 0

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
