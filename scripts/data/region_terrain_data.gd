class_name RegionTerrainData
extends RefCounted

const GRID_SIZE: int = WorldCoordinates.REGION_GRID_SIZE
const CELL_COUNT: int = GRID_SIZE * GRID_SIZE

var terrain_array: PackedByteArray = PackedByteArray()
var elevation_data: PackedByteArray = PackedByteArray()
var moisture_data: PackedByteArray = PackedByteArray()
var river_strength_data: PackedByteArray = PackedByteArray()
var is_frozen: bool = false

func _init() -> void:
	terrain_array.resize(CELL_COUNT)
	terrain_array.fill(TerrainType.PLAINS)
	elevation_data.resize(CELL_COUNT)
	elevation_data.fill(0)
	moisture_data.resize(CELL_COUNT)
	moisture_data.fill(0)
	river_strength_data.resize(CELL_COUNT)
	river_strength_data.fill(0)

func get_terrain(region_cell: Vector2i) -> int:
	if not is_valid_region_cell(region_cell):
		return -1
	return terrain_array[_index_for(region_cell)]

func set_terrain(region_cell: Vector2i, terrain_type: int) -> bool:
	if is_frozen or not is_valid_region_cell(region_cell) or not TerrainType.is_valid(terrain_type):
		return false
	terrain_array[_index_for(region_cell)] = terrain_type
	return true

func get_elevation(region_cell: Vector2i) -> float:
	if not is_valid_region_cell(region_cell):
		return 0.0
	return _decode_normalized(elevation_data[_index_for(region_cell)])

func set_elevation(region_cell: Vector2i, elevation: float) -> bool:
	if is_frozen or not is_valid_region_cell(region_cell):
		return false
	elevation_data[_index_for(region_cell)] = _encode_normalized(elevation)
	return true

func get_moisture(region_cell: Vector2i) -> float:
	if not is_valid_region_cell(region_cell):
		return 0.0
	return _decode_normalized(moisture_data[_index_for(region_cell)])

func set_moisture(region_cell: Vector2i, moisture: float) -> bool:
	if is_frozen or not is_valid_region_cell(region_cell):
		return false
	moisture_data[_index_for(region_cell)] = _encode_normalized(moisture)
	return true

func get_river_strength(region_cell: Vector2i) -> float:
	if not is_valid_region_cell(region_cell):
		return 0.0
	return _decode_normalized(river_strength_data[_index_for(region_cell)])

func set_river_strength(region_cell: Vector2i, river_strength: float) -> bool:
	if is_frozen or not is_valid_region_cell(region_cell):
		return false
	var encoded_strength: int = _encode_normalized(river_strength)
	if river_strength > 0.0 and encoded_strength == 0:
		encoded_strength = 1
	river_strength_data[_index_for(region_cell)] = encoded_strength
	return true

func has_river(region_cell: Vector2i) -> bool:
	return get_river_strength(region_cell) > 0.0

func is_valid_region_cell(region_cell: Vector2i) -> bool:
	return WorldCoordinates.is_valid_region_cell(region_cell)

func freeze() -> void:
	is_frozen = true

func _index_for(region_cell: Vector2i) -> int:
	return region_cell.y * GRID_SIZE + region_cell.x

func _encode_normalized(value: float) -> int:
	return clampi(roundi(clampf(value, 0.0, 1.0) * 255.0), 0, 255)

func _decode_normalized(value: int) -> float:
	return float(value) / 255.0
