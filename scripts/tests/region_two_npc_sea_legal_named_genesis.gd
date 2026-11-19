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
			var east := -400 + x * 2 + 1
			# Finite initial shore cells: actual south/north contacts for two true crews.
			var pier := north == 165 and east in [61, -59]
			var ocean := north >= 160 and not pier
			elevation.encode_s16(index * 2, -32767 if ocean else 0)
			water[index] = 2 if ocean else 0
	var height_record: Dictionary = test._asset("coast.height.zlib", elevation.compress(FileAccess.COMPRESSION_DEFLATE))
	var level_record: Dictionary = test._asset("coast.levels.zlib", levels.compress(FileAccess.COMPRESSION_DEFLATE))
	var water_record: Dictionary = test._asset("coast.water.zlib", water.compress(FileAccess.COMPRESSION_DEFLATE))
	height_record.merge({"id": "c06_straight_coast", "origin": [-400, -400], "size": [500, 500], "spacing_m": 2,
		"encoding": "int16_le_zlib", "row_order": "north_to_south", "nodata": -32767,
		"derived": {"encoding": "u8_zlib", "levels_path": level_record.path, "levels_sha256": level_record.sha256, "water_path": water_record.path, "water_sha256": water_record.sha256}})
	var manifest := {"format": 1, "synthetic_fixture": true, "atlas_id": CoastGrid.ATLAS_ID, "grid_contract_version": 1,
		"base_revision": "region-c06-two-npc-sea-initial-coast-v1", "land_condition_rule": "terrain_mapped_potential_v1", "crs": "EPSG:3826",
		"grid": {"origin": [0, 0], "cell_m": 2, "site_cells": 100, "region_sites": 100},
		"summary": summary_record, "elevation_tiles": [height_record], "sources": [{"title": "Synthetic initial two-NPC coast with two finite legal north boarding cells"}]}
	test.manifest_path = test.out.path_join("manifest.json")
	var file := FileAccess.open(test.manifest_path, FileAccess.WRITE)
	if not test._check(file != null, "NEW named coast source is writable before World birth"): return false
	file.store_string(JSON.stringify(manifest, "", true, true))
	file.close()
	var source := RegionData.new()
	var loaded: Dictionary = source.load_manifest(test.manifest_path)
	if not test._check(loaded.ok, "original checksummed Source loads the named coast", loaded): return false
	for spec: Dictionary in [{"site": Vector2i.ZERO, "anchor": Vector2i(30, 19), "facing": Vector2i.LEFT}, {"site": Vector2i(-1, 0), "anchor": Vector2i(70, 18), "facing": Vector2i.RIGHT}]:
		var built: Dictionary = CoastAdapter.build(source, spec.site)
		if not test._check(built.ok and built.data.parameters.get("fixed_land_condition_rule") == "terrain_mapped_potential_v1", "original fixed Adapter recognizes both prebirth coasts", built.get("code")): return false
		var data: TerrainData = built.data
		CoastEnvironment.initialize(data, "c06-two-npc-prebirth:" + str(spec.site))
		var hull: Array[Vector2i] = CoastShips.footprint("ferry", spec.anchor, spec.facing)
		var shores: Array[Vector2i] = CoastShips.boarding_cells("ferry", spec.anchor, spec.facing)
		if not test._check(data.can_place_water_vehicle(hull) and shores.size() == 2, "original complete hull lies on real Source water", spec): return false
		for cell: Vector2i in shores:
			if not test._check(data.is_walkable(cell) and absi(data.effective_height(spec.anchor) - data.effective_height(cell)) <= 1, "both real distinct boarding cells satisfy original shore/height guards", cell): return false
	return true
