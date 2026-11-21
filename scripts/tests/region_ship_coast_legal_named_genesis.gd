extends RefCounted
## Named test source only. All water, heights and soil are fixed before World birth.
const CoastGrid = preload("res://scripts/region_lab/region_grid.gd")
const CoastAdapter = preload("res://scripts/region_lab/region_terrain_adapter.gd")
const CoastEnvironment = preload("res://scripts/terrain_lab/site_environment.gd")
const CoastShips = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")

static func write(test: Variant) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(test.out))
	var summary := PackedByteArray()
	summary.resize(5 * 5)
	summary.fill(2)
	var summary_record: Dictionary = test._asset("summary.u8", summary)
	summary_record.merge({"size": [5, 5], "site_origin": [-2, -2], "encoding": "u8", "row_order": "north_to_south", "nodata": 0})
	var elevation := PackedByteArray()
	var levels := PackedByteArray()
	var water := PackedByteArray()
	elevation.resize(500 * 500 * 2)
	levels.resize(500 * 500)
	water.resize(500 * 500)
	for y: int in range(500):
		var north := -400 + (499 - y) * 2 + 1
		for x: int in range(500):
			var index := y * 500 + x
			var ocean := north >= 160
			elevation.encode_s16(index * 2, -32767 if ocean else 0)
			water[index] = 2 if ocean else 0
	var height_record: Dictionary = test._asset("coast.height.zlib", elevation.compress(FileAccess.COMPRESSION_DEFLATE))
	var level_record: Dictionary = test._asset("coast.levels.zlib", levels.compress(FileAccess.COMPRESSION_DEFLATE))
	var water_record: Dictionary = test._asset("coast.water.zlib", water.compress(FileAccess.COMPRESSION_DEFLATE))
	height_record.merge({"id": "c06_straight_coast", "origin": [-400, -400], "size": [500, 500], "spacing_m": 2,
		"encoding": "int16_le_zlib", "row_order": "north_to_south", "nodata": -32767,
		"derived": {"encoding": "u8_zlib", "levels_path": level_record.path, "levels_sha256": level_record.sha256, "water_path": water_record.path, "water_sha256": water_record.sha256}})
	var manifest := {"format": 1, "synthetic_fixture": true, "atlas_id": CoastGrid.ATLAS_ID, "grid_contract_version": 1,
		"base_revision": "region-c06-ship-physical-legal-coast-v1", "land_condition_rule": "terrain_mapped_potential_v1", "crs": "EPSG:3826",
		"grid": {"origin": [0, 0], "cell_m": 2, "site_cells": 100, "region_sites": 100},
		"summary": summary_record, "elevation_tiles": [height_record], "sources": [{"title": "Synthetic original ship physical fixture only"}]}
	test.manifest_path = test.out.path_join("manifest.json")
	var file := FileAccess.open(test.manifest_path, FileAccess.WRITE)
	if not test._check(file != null, "NEW named coast source is writable before World birth"): return false
	file.store_string(JSON.stringify(manifest, "", true, true))
	file.close()
	var source := RegionData.new()
	var loaded: Dictionary = source.load_manifest(test.manifest_path)
	if not test._check(loaded.ok, "original checksummed Source loads the named coast", loaded): return false
	var built: Dictionary = CoastAdapter.build(source, Vector2i.ZERO)
	if not test._check(built.ok and built.data.parameters.get("fixed_land_condition_rule") == "terrain_mapped_potential_v1", "original fixed Adapter recognizes coast and land potential", built.get("code")): return false
	var data: TerrainData = built.data
	CoastEnvironment.initialize(data, "c06-ship-prebirth-coast-probe")
	for anchor: Vector2i in [Vector2i(30, 19), Vector2i(35, 19)]:
		var hull: Array[Vector2i] = CoastShips.footprint("ferry", anchor, Vector2i.LEFT)
		if not test._check(data.can_place_water_vehicle(hull) and data.is_walkable(anchor + Vector2i.DOWN), "original source supplies each full genuine ferry hull and its actual shore", anchor): return false
		if not test._check(absi(data.effective_height(anchor) - data.effective_height(anchor + Vector2i.DOWN)) <= 1, "original source shoreline meets existing ship contact height guard", anchor): return false
	return test._check(int(data.foundation[data.index(Vector2i(25, 40))]) >= 35, "original named soil potential permits the original finite land barrier before World birth")
