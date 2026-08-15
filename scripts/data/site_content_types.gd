class_name SiteContentTypes
extends RefCounted

enum NativeSurface {
	DIRT,
	ROCK,
	RIVER_WATER,
	SEA_WATER,
	COUNT,
}

const RESOURCE_GRASS: int = 0
const RESOURCE_FRUIT_TREE: int = 1
const RESOURCE_FOREST: int = 2
const RESOURCE_STONE_ORE: int = 3
const RESOURCE_IRON_ORE: int = 4
const RESOURCE_SILVER_ORE: int = 5
const RESOURCE_GOLD_ORE: int = 6
const RESOURCE_COUNT: int = 7

enum Facility {
	BRIDGE,
	WOOD_STAIR,
	STONE_STAIR,
	WOOD_WALL,
	STONE_WALL,
	BUILDING,
	COUNT,
}

enum Orientation {
	HORIZONTAL,
	VERTICAL,
}

static func is_water_surface(surface: int) -> bool:
	return surface == NativeSurface.RIVER_WATER or surface == NativeSurface.SEA_WATER

static func is_resource(resource_type: int) -> bool:
	return resource_type >= RESOURCE_GRASS and resource_type < RESOURCE_COUNT

static func is_facility(facility_type: int) -> bool:
	return facility_type >= Facility.BRIDGE and facility_type < Facility.COUNT

static func resource_name(resource_type: int) -> String:
	match resource_type:
		RESOURCE_GRASS:
			return "grass"
		RESOURCE_FRUIT_TREE:
			return "fruit_tree"
		RESOURCE_FOREST:
			return "forest"
		RESOURCE_STONE_ORE:
			return "stone_ore"
		RESOURCE_IRON_ORE:
			return "iron_ore"
		RESOURCE_SILVER_ORE:
			return "silver_ore"
		RESOURCE_GOLD_ORE:
			return "gold_ore"
		_:
			return "unknown"

static func facility_name(facility_type: int) -> String:
	match facility_type:
		Facility.BRIDGE:
			return "bridge"
		Facility.WOOD_STAIR:
			return "wood_stair"
		Facility.STONE_STAIR:
			return "stone_stair"
		Facility.WOOD_WALL:
			return "wood_wall"
		Facility.STONE_WALL:
			return "stone_wall"
		Facility.BUILDING:
			return "building"
		_:
			return "unknown"

static func make_resource(
		resource_id: String,
		resource_type: int,
		origin_cell: Vector2i,
		size_cells: Vector2i,
		quantity: int
	) -> Dictionary:
	return {
		"id": resource_id,
		"type": resource_type,
		"origin": origin_cell,
		"size": size_cells,
		"quantity": maxi(quantity, 0),
	}

static func make_facility(
		facility_id: String,
		facility_type: int,
		origin_cell: Vector2i,
		size_cells: Vector2i,
		orientation: int,
		target_cell: Vector2i = Vector2i(-1, -1),
		definition_id: String = ""
	) -> Dictionary:
	return {
		"id": facility_id,
		"type": facility_type,
		"origin": origin_cell,
		"size": size_cells,
		"orientation": orientation,
		"target": target_cell,
		"definition_id": definition_id,
	}
