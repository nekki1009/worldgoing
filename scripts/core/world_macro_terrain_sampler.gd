class_name WorldMacroTerrainSampler
extends RefCounted

# One sampler owns every world-scale field. Regions only slice this field.
const CONTINENTAL_FREQUENCY: float = 0.00009
const REGIONAL_ELEVATION_FREQUENCY: float = 0.0007
const ELEVATION_DETAIL_FREQUENCY: float = 0.0045
const MOISTURE_FREQUENCY: float = 0.0008
const TEMPERATURE_FREQUENCY: float = 0.00018
const RIVER_FREQUENCY: float = 0.0018
const MAJOR_RIVER_FREQUENCY: float = 0.00008

const CONTINENTAL_SEED_OFFSET: int = 1_001
const REGIONAL_ELEVATION_SEED_OFFSET: int = 2_003
const ELEVATION_DETAIL_SEED_OFFSET: int = 3_007
const MOISTURE_SEED_OFFSET: int = 5_009
const TEMPERATURE_SEED_OFFSET: int = 6_011
const RIVER_SEED_OFFSET: int = 7_013
const MAJOR_RIVER_SEED_OFFSET: int = 8_021

const DEEP_WATER_LEVEL: float = 0.405
const SEA_LEVEL: float = 0.44
const RIVER_MAX_ELEVATION: float = 0.80
const RIVER_LINE_THRESHOLD: float = 0.008
const MAJOR_RIVER_SOURCE_THRESHOLD: float = 0.0015
const MAJOR_RIVER_MOUTH_THRESHOLD: float = 0.005

var continental_noise: FastNoiseLite = FastNoiseLite.new()
var regional_elevation_noise: FastNoiseLite = FastNoiseLite.new()
var elevation_detail_noise: FastNoiseLite = FastNoiseLite.new()
var moisture_noise: FastNoiseLite = FastNoiseLite.new()
var temperature_noise: FastNoiseLite = FastNoiseLite.new()
var river_noise: FastNoiseLite = FastNoiseLite.new()
var major_river_noise: FastNoiseLite = FastNoiseLite.new()

var _configured_seed: int = 0
var _has_configured_seed: bool = false

func _init() -> void:
	_configure_noise(continental_noise, CONTINENTAL_FREQUENCY, 2)
	_configure_noise(regional_elevation_noise, REGIONAL_ELEVATION_FREQUENCY, 3)
	_configure_noise(elevation_detail_noise, ELEVATION_DETAIL_FREQUENCY, 2)
	_configure_noise(moisture_noise, MOISTURE_FREQUENCY, 3)
	_configure_noise(temperature_noise, TEMPERATURE_FREQUENCY, 3)
	_configure_noise(river_noise, RIVER_FREQUENCY, 2)
	_configure_noise(major_river_noise, MAJOR_RIVER_FREQUENCY, 3)

func sample(world_seed: int, global_region_cell: Vector2i) -> Vector4:
	# Vector4 is a compact value return: x=elevation, y=moisture,
	# z=river strength, w=temperature.
	_ensure_world_seed(world_seed)
	var elevation: float = _sample_elevation(global_region_cell)
	var moisture: float = _normalize_noise(
		moisture_noise.get_noise_2d(global_region_cell.x, global_region_cell.y)
	)
	var river_strength: float = _sample_river_strength(global_region_cell, elevation)
	var temperature: float = _sample_temperature(global_region_cell, elevation)
	return Vector4(elevation, moisture, river_strength, temperature)

func is_river(world_seed: int, global_region_cell: Vector2i) -> bool:
	return sample(world_seed, global_region_cell).z > 0.0

func sample_major_river_strength(
		world_seed: int,
		global_region_cell: Vector2i,
		elevation: float = -1.0
	) -> float:
	_ensure_world_seed(world_seed)
	var resolved_elevation: float = elevation
	if resolved_elevation < 0.0:
		resolved_elevation = _sample_elevation(global_region_cell)
	return _sample_major_river_strength(global_region_cell, resolved_elevation)

func _sample_elevation(global_region_cell: Vector2i) -> float:
	var continental: float = _normalize_noise(
		continental_noise.get_noise_2d(global_region_cell.x, global_region_cell.y)
	)
	var regional: float = _normalize_noise(
		regional_elevation_noise.get_noise_2d(global_region_cell.x, global_region_cell.y)
	)
	var detail: float = _normalize_noise(
		elevation_detail_noise.get_noise_2d(global_region_cell.x, global_region_cell.y)
	)
	return clampf(continental * 0.72 + regional * 0.22 + detail * 0.06, 0.0, 1.0)

func _sample_temperature(global_region_cell: Vector2i, elevation: float) -> float:
	var climate: float = _normalize_noise(
		temperature_noise.get_noise_2d(global_region_cell.x, global_region_cell.y)
	)
	var altitude_cooling: float = maxf(elevation - SEA_LEVEL, 0.0) * 0.65
	return clampf(climate - altitude_cooling, 0.0, 1.0)

func _sample_river_strength(global_region_cell: Vector2i, elevation: float) -> float:
	var local_strength: float = 0.0
	if elevation >= SEA_LEVEL and elevation <= RIVER_MAX_ELEVATION:
		var river_signal: float = absf(
			river_noise.get_noise_2d(global_region_cell.x, global_region_cell.y)
		)
		local_strength = clampf(
			(RIVER_LINE_THRESHOLD - river_signal) / RIVER_LINE_THRESHOLD,
			0.0,
			1.0
		)
	return maxf(
		local_strength,
		_sample_major_river_strength(global_region_cell, elevation)
	)

func _sample_major_river_strength(global_region_cell: Vector2i, elevation: float) -> float:
	if elevation < DEEP_WATER_LEVEL or elevation > RIVER_MAX_ELEVATION:
		return 0.0
	var downstream: float = clampf(
		(RIVER_MAX_ELEVATION - elevation) / (RIVER_MAX_ELEVATION - DEEP_WATER_LEVEL),
		0.0,
		1.0
	)
	var threshold: float = lerpf(
		MAJOR_RIVER_SOURCE_THRESHOLD,
		MAJOR_RIVER_MOUTH_THRESHOLD,
		downstream
	)
	var river_signal: float = absf(
		major_river_noise.get_noise_2d(global_region_cell.x, global_region_cell.y)
	)
	return clampf((threshold - river_signal) / threshold, 0.0, 1.0)

func _ensure_world_seed(world_seed: int) -> void:
	if _has_configured_seed and _configured_seed == world_seed:
		return
	_configured_seed = world_seed
	_has_configured_seed = true
	continental_noise.seed = world_seed + CONTINENTAL_SEED_OFFSET
	regional_elevation_noise.seed = world_seed + REGIONAL_ELEVATION_SEED_OFFSET
	elevation_detail_noise.seed = world_seed + ELEVATION_DETAIL_SEED_OFFSET
	moisture_noise.seed = world_seed + MOISTURE_SEED_OFFSET
	temperature_noise.seed = world_seed + TEMPERATURE_SEED_OFFSET
	river_noise.seed = world_seed + RIVER_SEED_OFFSET
	major_river_noise.seed = world_seed + MAJOR_RIVER_SEED_OFFSET

func _configure_noise(noise: FastNoiseLite, frequency: float, octaves: int) -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = octaves

func _normalize_noise(value: float) -> float:
	return clampf(value * 0.5 + 0.5, 0.0, 1.0)
