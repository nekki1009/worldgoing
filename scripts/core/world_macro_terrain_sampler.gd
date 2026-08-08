class_name WorldMacroTerrainSampler
extends RefCounted

# One sampler owns every world-scale field. Regions only slice this field.
const CONTINENTAL_FREQUENCY: float = 0.0016
const REGIONAL_ELEVATION_FREQUENCY: float = 0.005
const ELEVATION_DETAIL_FREQUENCY: float = 0.018
const MOISTURE_FREQUENCY: float = 0.0038
const RIVER_FREQUENCY: float = 0.007

const CONTINENTAL_SEED_OFFSET: int = 1_001
const REGIONAL_ELEVATION_SEED_OFFSET: int = 2_003
const ELEVATION_DETAIL_SEED_OFFSET: int = 3_007
const MOISTURE_SEED_OFFSET: int = 5_009
const RIVER_SEED_OFFSET: int = 7_013

const SEA_LEVEL: float = 0.44
const RIVER_MAX_ELEVATION: float = 0.80
const RIVER_LINE_THRESHOLD: float = 0.032

var continental_noise: FastNoiseLite = FastNoiseLite.new()
var regional_elevation_noise: FastNoiseLite = FastNoiseLite.new()
var elevation_detail_noise: FastNoiseLite = FastNoiseLite.new()
var moisture_noise: FastNoiseLite = FastNoiseLite.new()
var river_noise: FastNoiseLite = FastNoiseLite.new()

var _configured_seed: int = 0
var _has_configured_seed: bool = false

func _init() -> void:
	_configure_noise(continental_noise, CONTINENTAL_FREQUENCY, 2)
	_configure_noise(regional_elevation_noise, REGIONAL_ELEVATION_FREQUENCY, 3)
	_configure_noise(elevation_detail_noise, ELEVATION_DETAIL_FREQUENCY, 2)
	_configure_noise(moisture_noise, MOISTURE_FREQUENCY, 3)
	_configure_noise(river_noise, RIVER_FREQUENCY, 2)

func sample(world_seed: int, global_region_cell: Vector2i) -> Vector3:
	# Vector3 is a value return: x=elevation, y=moisture, z=river strength.
	_ensure_world_seed(world_seed)
	var elevation: float = _sample_elevation(global_region_cell)
	var moisture: float = _normalize_noise(
		moisture_noise.get_noise_2d(global_region_cell.x, global_region_cell.y)
	)
	var river_strength: float = _sample_river_strength(global_region_cell, elevation)
	return Vector3(elevation, moisture, river_strength)

func is_river(world_seed: int, global_region_cell: Vector2i) -> bool:
	return sample(world_seed, global_region_cell).z > 0.0

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
	return clampf(continental * 0.62 + regional * 0.28 + detail * 0.10, 0.0, 1.0)

func _sample_river_strength(global_region_cell: Vector2i, elevation: float) -> float:
	if elevation < SEA_LEVEL or elevation > RIVER_MAX_ELEVATION:
		return 0.0
	var river_signal: float = absf(
		river_noise.get_noise_2d(global_region_cell.x, global_region_cell.y)
	)
	return clampf((RIVER_LINE_THRESHOLD - river_signal) / RIVER_LINE_THRESHOLD, 0.0, 1.0)

func _ensure_world_seed(world_seed: int) -> void:
	if _has_configured_seed and _configured_seed == world_seed:
		return
	_configured_seed = world_seed
	_has_configured_seed = true
	continental_noise.seed = world_seed + CONTINENTAL_SEED_OFFSET
	regional_elevation_noise.seed = world_seed + REGIONAL_ELEVATION_SEED_OFFSET
	elevation_detail_noise.seed = world_seed + ELEVATION_DETAIL_SEED_OFFSET
	moisture_noise.seed = world_seed + MOISTURE_SEED_OFFSET
	river_noise.seed = world_seed + RIVER_SEED_OFFSET

func _configure_noise(noise: FastNoiseLite, frequency: float, octaves: int) -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = octaves

func _normalize_noise(value: float) -> float:
	return clampf(value * 0.5 + 0.5, 0.0, 1.0)
