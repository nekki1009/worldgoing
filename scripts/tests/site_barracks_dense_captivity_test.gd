extends "res://scripts/tests/site_garrison_captivity_test.gd"
## Reuse every original GD capture/return assertion with a dense fixture.

func _formal_feature(data: TerrainData, kind: String, anchor: Vector2i, extent: Vector2i = Vector2i.ONE, options: Dictionary = {}) -> String:
	var settings := options.duplicate()
	if kind == "barracks": settings["barracks_layout_version"] = 2
	var key := super._formal_feature(data, kind, anchor, extent, settings)
	if kind == "barracks":
		var feature: Dictionary = data.site.features[key]
		assert(int(feature.barracks_layout_version) == 2 and Runtime.military_modules(data, feature).size() == 7 and Runtime.military_capacity(data, feature) == 60)
		print("DENSE_BARRACKS_FIXTURE_V2: GD captivity/return; 10x10; 7 modules; 60 standing cells")
	return key
