class_name TerrainPreset
extends RefCounted

enum Kind { PLAINS, TERRACED_HIGHLAND, COASTAL_CLIFF, FOREST, WETLAND, ROCKY_HIGHLAND, RIVER_VALLEY, ISLAND }
const NAMES: Array[String] = ["PLAINS", "TERRACED_HIGHLAND", "COASTAL_CLIFF", "FOREST", "WETLAND", "ROCKY_HIGHLAND", "RIVER_VALLEY", "ISLAND"]

static func defaults(kind: int) -> Dictionary:
	var settings: Dictionary = {"size": Vector2i(100, 100), "max_height": 5, "micro_strength": 0.025}
	match kind:
		Kind.PLAINS:
			settings.merge({"max_height": 1, "composition": "Broad low rollers; damp hollow and dirt patches"}, true)
		Kind.TERRACED_HIGHLAND:
			settings["composition"] = "Nested asymmetric plateau contours; linked natural passes"
		Kind.COASTAL_CLIFF:
			settings["composition"] = "One continuous coast: sea / beach / lowland / rising plateau"
		Kind.FOREST:
			settings.merge({"max_height": 1, "composition": "Forest floor mass; winding clearing and two glades"}, true)
		Kind.WETLAND:
			settings.merge({"max_height": 1, "composition": "Joined elongated basins; shallow water and wet banks"}, true)
		Kind.ROCKY_HIGHLAND:
			settings["composition"] = "Long broken ridge with two shoulders; broad rocky platforms"
		Kind.RIVER_VALLEY:
			settings.merge({"max_height": 4, "composition": "Continuous meandering river; floodplain and raised valley sides"}, true)
		Kind.ISLAND:
			settings["composition"] = "Enclosed asymmetric island; beach ring and inland highland"
	return settings
