class_name WorldPOIType
extends RefCounted

enum {
	VILLAGE,
	TOWN,
	CASTLE,
	RUINS,
	CAVE,
}

static func to_display_name(poi_type: int) -> String:
	match poi_type:
		VILLAGE:
			return "VILLAGE"
		TOWN:
			return "TOWN"
		CASTLE:
			return "CASTLE"
		RUINS:
			return "RUINS"
		CAVE:
			return "CAVE"
		_:
			return "UNKNOWN"

static func to_id_prefix(poi_type: int) -> String:
	match poi_type:
		VILLAGE:
			return "village"
		TOWN:
			return "town"
		CASTLE:
			return "castle"
		RUINS:
			return "ruins"
		CAVE:
			return "cave"
		_:
			return "poi"

static func to_color(poi_type: int) -> Color:
	match poi_type:
		VILLAGE:
			return Color("f2d15c")
		TOWN:
			return Color("e99842")
		CASTLE:
			return Color("d95757")
		RUINS:
			return Color("a979c9")
		CAVE:
			return Color("e6e6e6")
		_:
			return Color("ffffff")

static func is_settlement(poi_type: int) -> bool:
	return poi_type == VILLAGE or poi_type == TOWN or poi_type == CASTLE

static func is_adventure(poi_type: int) -> bool:
	return poi_type == RUINS or poi_type == CAVE
