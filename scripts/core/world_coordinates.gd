class_name WorldCoordinates
extends RefCounted

const REGION_GRID_SIZE: int = 100
const REGION_CELL_SIZE_METERS: int = 100
const REGION_SIZE_METERS: int = REGION_GRID_SIZE * REGION_CELL_SIZE_METERS
const REGION_CELLS_PER_AXIS: int = REGION_GRID_SIZE

static func is_valid_region_cell(region_cell: Vector2i) -> bool:
	return region_cell.x >= 0 and region_cell.y >= 0 \
		and region_cell.x < REGION_GRID_SIZE and region_cell.y < REGION_GRID_SIZE

static func world_region_to_global_region_cell(world_cell: Vector2i, region_cell: Vector2i) -> Vector2i:
	# Region generation samples this shared global grid so neighboring Regions meet at x=99/x=100.
	return Vector2i(
		world_cell.x * REGION_GRID_SIZE + region_cell.x,
		world_cell.y * REGION_GRID_SIZE + region_cell.y
	)

static func floor_divide(value: int, divisor: int) -> int:
	# Candidate grids and reverse conversion need mathematical floor for negative cells.
	return floori(float(value) / float(divisor))

static func global_region_cell_to_world_region(global_region_cell: Vector2i) -> Dictionary:
	var world_cell: Vector2i = Vector2i(
		floor_divide(global_region_cell.x, REGION_GRID_SIZE),
		floor_divide(global_region_cell.y, REGION_GRID_SIZE)
	)
	var region_cell: Vector2i = Vector2i(
		posmod(global_region_cell.x, REGION_GRID_SIZE),
		posmod(global_region_cell.y, REGION_GRID_SIZE)
	)
	return {
		"world_cell": world_cell,
		"region_cell": region_cell
	}

static func global_region_cell_to_global_meters(global_region_cell: Vector2i) -> Vector2i:
	return global_region_cell * REGION_CELL_SIZE_METERS

static func world_region_to_global_meters(world_cell: Vector2i, region_cell: Vector2i) -> Vector2i:
	return global_region_cell_to_global_meters(
		world_region_to_global_region_cell(world_cell, region_cell)
	)

static func global_meters_to_world_region(global_meters: Vector2i) -> Dictionary:
	var world_cell: Vector2i = Vector2i(
		floor_divide(global_meters.x, REGION_SIZE_METERS),
		floor_divide(global_meters.y, REGION_SIZE_METERS)
	)
	var region_cell: Vector2i = Vector2i(
		floori(float(posmod(global_meters.x, REGION_SIZE_METERS)) / REGION_CELL_SIZE_METERS),
		floori(float(posmod(global_meters.y, REGION_SIZE_METERS)) / REGION_CELL_SIZE_METERS)
	)
	return {
		"world_cell": world_cell,
		"region_cell": region_cell
	}
