class_name TerrainType
extends RefCounted

enum {
	PLAINS,
	FOREST,
	MOUNTAIN,
	WATER,
	SAND,
	SNOW,
	SWAMP,
	OCEAN,
	COUNT,
}

static func to_display_name(terrain_type: int) -> String:
	match terrain_type:
		PLAINS:
			return "Plains"
		FOREST:
			return "Forest"
		MOUNTAIN:
			return "Mountain"
		WATER:
			return "Water"
		SAND:
			return "Sand"
		SNOW:
			return "Snow"
		SWAMP:
			return "Swamp"
		OCEAN:
			return "Ocean"
		_:
			return "Unknown"

static func to_color(terrain_type: int) -> Color:
	match terrain_type:
		FOREST:
			return Color("3f7857")
		MOUNTAIN:
			return Color("777b83")
		WATER:
			return Color("4d87a1")
		SAND:
			return Color("c9ad6a")
		SNOW:
			return Color("dce8ed")
		SWAMP:
			return Color("66734a")
		OCEAN:
			return Color("294f68")
		_:
			return Color("6f9b5b")

static func is_valid(terrain_type: int) -> bool:
	return terrain_type >= PLAINS and terrain_type < COUNT

static func is_water_like(terrain_type: int) -> bool:
	return terrain_type == WATER or terrain_type == OCEAN
