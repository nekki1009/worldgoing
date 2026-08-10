class_name PartyData
extends RefCounted

var party_id: String = "party_1"
var display_name: String = "Exploration Party"
var current_global_region_cell: Vector2i = Vector2i(350, 450)
var current_site_local_cell: Vector2i = SiteLayoutData.INVALID_CELL
var current_world_cell: Vector2i:
	get:
		return get_world_cell()
	set(value):
		current_global_region_cell = WorldCoordinates.world_region_to_global_region_cell(
			value,
			get_region_cell()
		)
var current_region_cell: Vector2i:
	get:
		return get_region_cell()
	set(value):
		current_global_region_cell = WorldCoordinates.world_region_to_global_region_cell(
			get_world_cell(),
			value
		)
var base_walk_speed_kmh: float = TravelCostConfig.DEFAULT_WALK_SPEED_KMH
var initialized: bool = false

func is_at(world_cell: Vector2i, region_cell: Vector2i) -> bool:
	return initialized and get_world_cell() == world_cell and get_region_cell() == region_cell

func global_region_cell() -> Vector2i:
	return current_global_region_cell

func get_world_cell() -> Vector2i:
	return WorldCoordinates.global_region_cell_to_world_region(current_global_region_cell)["world_cell"] as Vector2i

func get_region_cell() -> Vector2i:
	return WorldCoordinates.global_region_cell_to_world_region(current_global_region_cell)["region_cell"] as Vector2i

func set_global_region_cell(global_cell: Vector2i) -> void:
	current_global_region_cell = global_cell
