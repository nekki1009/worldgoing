extends SceneTree

const Atlas = preload("res://scripts/region_lab/region_data.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const OUTPUT := "res://.godot-temp/region_lab_fine_contract"
const COAST_SITES: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(0, 0)]
const ISLAND := Vector2i(1, 1)

var _finished := false

func _init() -> void:
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if not _finished:
		printerr("REGION_LAB_FINE_MASK_INTERRUPTED")
		quit(1)
	return false

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var manifest := _fixture()
	var manifest_path := OUTPUT.path_join("manifest.json")
	_write(manifest_path, JSON.stringify(manifest).to_utf8_buffer())
	var source := Atlas.new()
	var loaded := source.load_manifest(manifest_path)
	assert(loaded.ok, str(loaded))
	var fine_land := source.sample_meters(-11.0, 9.0)
	var fine_sea := source.sample_meters(-9.0, 11.0)
	assert(fine_land.ok and fine_sea.ok)
	assert(fine_land.water_kind == 0 and fine_land.elevation_valid and fine_land.elevation_m == 100.0,
		"Fine land did not use retained coarse-sea elevation support")
	assert(fine_land.source_quality_code == 4, "Sea-supported fine land was not marked estimated")
	assert(fine_sea.water_kind == 2 and fine_sea.water_body == 1 and not fine_sea.elevation_valid,
		"Fine ocean exposed a measured seabed")
	var pure_sea := source.sample_meters(1001.0, 1001.0)
	assert(pure_sea.ok and pure_sea.water_kind == 2 and not pure_sea.elevation_valid,
		"Coarse ocean without a fine mask exposed measured elevation")
	# Both positions fall inside one 200 m coarse post. The observed transition
	# is at two-metre resolution, not a coarse square Site or source-post edge.
	assert(Grid.site_from_meters(-11.0, 9.0) == Grid.site_from_meters(-9.0, 11.0))
	assert(floori(-11.0 / 200.0) == floori(-9.0 / 200.0))
	assert(floori(9.0 / 200.0) == floori(11.0 / 200.0))
	var island_land := source.sample_meters(301.0, 301.0)
	var island_lake := source.sample_meters(271.0, 301.0)
	assert(island_land.ok and island_lake.ok)
	assert(island_land.water_kind == 0 and island_land.elevation_valid and island_land.elevation_m == 100.0
		and island_land.source_quality_code == 4, "Fine island lost inland-water height support or estimate label")
	assert(island_lake.water_kind == 1 and island_lake.water_body == 2 and island_lake.elevation_valid
		and island_lake.elevation_m == 100.0, "Named lake lost nonzero height or identity")
	var corner_checks := 0
	var sites: Dictionary = {}
	for site: Vector2i in COAST_SITES + [ISLAND]:
		var result := source.make_terrain_data(site.x, site.y)
		assert(result.ok, str({"site": site, "code": result.get("code", "OK")}))
		sites[site] = result.data
		for y: int in [0, 99]:
			for x: int in [0, 99]:
				var easting := site.x * 200.0 + x * 2.0 + 1.0
				var northing := site.y * 200.0 + (99 - y) * 2.0 + 1.0
				var expected := source.sample_meters(easting, northing)
				var index: int = result.data.index(Vector2i(x, y))
				assert(expected.ok and result.data.water_kind[index] == expected.water_kind
					and result.data.water_body[index] == (expected.water_body if expected.water_kind > 0 else -1),
					str({"message": "Four-corner or negative-coordinate fine mask disagreed with Site expansion",
						"site": site, "cell": [x, y], "meters": [easting, northing],
						"expected": expected, "water_kind": result.data.water_kind[index],
						"water_body": result.data.water_body[index]}))
				corner_checks += 1
	assert(sites[ISLAND].water_kind.has(0) and sites[ISLAND].water_body.has(2),
		"Lake island Site did not retain both land and named water")
	var reverse := source.make_terrain_data(-1, -1)
	assert(reverse.ok and reverse.data.fingerprint() == sites[Vector2i(-1, -1)].fingerprint(),
		"Fine-mask loading order changed a Site")
	assert(int(source.cache_stats().fine_masks) <= Atlas.MAX_FINE_MASKS and
		int(source.cache_stats().bytes) <= Atlas.MAX_CACHE_BYTES)
	_check_corruptions(manifest)
	_finished = true
	print("REGION_LAB_FINE_MASK_PASS ", JSON.stringify({"coarse_spacing_m": 200,
		"two_metre_coast_same_coarse_post": true, "four_corner_checks": corner_checks,
		"negative_sites": [[-1, -1], [0, -1], [-1, 0]], "lake_island_quality": island_land.source_quality_code,
		"sea_elevation_valid": fine_sea.elevation_valid, "cache": source.cache_stats(),
		"scope": "Synthetic four-Region fine-water contract; not real Taiwan coverage"}))
	quit(0)

func _check_corruptions(manifest: Dictionary) -> void:
	var tile_index := 0 # Southwest tile contains Site (-1,-1).
	var detail: Dictionary = manifest.elevation_tiles[tile_index].derived.water_detail
	var bad := manifest.duplicate(true)
	bad.elevation_tiles[tile_index].derived.water_detail.index_sha256 = "0".repeat(64)
	_write(OUTPUT.path_join("bad_index_hash.json"), JSON.stringify(bad).to_utf8_buffer())
	var broken := Atlas.new()
	assert(broken.load_manifest(OUTPUT.path_join("bad_index_hash.json")).ok)
	assert(broken.sample_meters(-1.0, -1.0).code == "HASH_MISMATCH")
	bad = manifest.duplicate(true)
	bad.elevation_tiles[tile_index].derived.water_detail.data_sha256 = "0".repeat(64)
	_write(OUTPUT.path_join("bad_bank_hash.json"), JSON.stringify(bad).to_utf8_buffer())
	broken = Atlas.new()
	assert(broken.load_manifest(OUTPUT.path_join("bad_bank_hash.json")).ok)
	assert(broken.sample_meters(-1.0, -1.0).code == "HASH_MISMATCH")
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join(str(detail.index_path))))
	var segment_key: String = str(index.keys()[0])
	var old_segment: Dictionary = index[segment_key]
	index[segment_key].sha256 = "0".repeat(64)
	var index_record := _asset("bad_segment_index.json", JSON.stringify(index).to_utf8_buffer())
	bad = manifest.duplicate(true)
	bad.elevation_tiles[tile_index].derived.water_detail.index_path = index_record.path
	bad.elevation_tiles[tile_index].derived.water_detail.index_sha256 = index_record.sha256
	bad.elevation_tiles[tile_index].derived.water_detail.index_bytes = FileAccess.get_file_as_bytes(OUTPUT.path_join(index_record.path)).size()
	_write(OUTPUT.path_join("bad_segment_hash.json"), JSON.stringify(bad).to_utf8_buffer())
	broken = Atlas.new()
	assert(broken.load_manifest(OUTPUT.path_join("bad_segment_hash.json")).ok)
	assert(broken.sample_meters(-1.0, -1.0).code == "HASH_MISMATCH")
	index[segment_key] = old_segment
	index[segment_key].offset = 1
	index_record = _asset("bad_segment_offset.json", JSON.stringify(index).to_utf8_buffer())
	bad = manifest.duplicate(true)
	bad.elevation_tiles[tile_index].derived.water_detail.index_path = index_record.path
	bad.elevation_tiles[tile_index].derived.water_detail.index_sha256 = index_record.sha256
	bad.elevation_tiles[tile_index].derived.water_detail.index_bytes = FileAccess.get_file_as_bytes(OUTPUT.path_join(index_record.path)).size()
	_write(OUTPUT.path_join("bad_segment_range.json"), JSON.stringify(bad).to_utf8_buffer())
	broken = Atlas.new()
	assert(broken.load_manifest(OUTPUT.path_join("bad_segment_range.json")).ok)
	assert(broken.sample_meters(-1.0, -1.0).code == "INVALID_WATER_DETAIL")
	var unknown := _coast_mask(Vector2i(-1, -1))
	unknown.encode_u32(0, 999)
	var compressed := unknown.compress(FileAccess.COMPRESSION_DEFLATE)
	var bank_record := _asset("unknown_body_bank.zlib", compressed)
	index[segment_key] = {"offset": 0, "compressed_bytes": compressed.size(), "sha256": _digest(compressed)}
	index_record = _asset("unknown_body_index.json", JSON.stringify(index).to_utf8_buffer())
	bad = manifest.duplicate(true)
	bad.elevation_tiles[tile_index].derived.water_detail.index_path = index_record.path
	bad.elevation_tiles[tile_index].derived.water_detail.index_sha256 = index_record.sha256
	bad.elevation_tiles[tile_index].derived.water_detail.index_bytes = FileAccess.get_file_as_bytes(OUTPUT.path_join(index_record.path)).size()
	bad.elevation_tiles[tile_index].derived.water_detail.data_path = bank_record.path
	bad.elevation_tiles[tile_index].derived.water_detail.data_sha256 = bank_record.sha256
	bad.elevation_tiles[tile_index].derived.water_detail.data_bytes = compressed.size()
	_write(OUTPUT.path_join("unknown_body.json"), JSON.stringify(bad).to_utf8_buffer())
	broken = Atlas.new()
	assert(broken.load_manifest(OUTPUT.path_join("unknown_body.json")).ok)
	assert(broken.sample_meters(-1.0, -1.0).code == "MISSING_WATER_ID")

func _fixture() -> Dictionary:
	var summary := PackedByteArray()
	var scope := PackedByteArray()
	var quality := PackedByteArray()
	summary.resize(200 * 200)
	scope.resize(200 * 200)
	quality.resize(200 * 200)
	summary.fill(1)
	scope.fill(5)
	for site: Vector2i in COAST_SITES + [ISLAND]:
		var index := _site_index(site)
		summary[index] = 1 if site == Vector2i(0, 0) else (2 if site == Vector2i(-1, -1) else 4)
		scope[index] = 1
		quality[index] = 0 if site == Vector2i(0, 0) else 4
	var summary_record := _asset("summary.u8", summary)
	summary_record.merge({"size": [200, 200], "site_origin": [-100, -100], "encoding": "u8",
		"row_order": "north_to_south", "nodata": 0})
	var scope_record := _asset("content_scope.u8", scope)
	scope_record.merge({"size": [200, 200], "site_origin": [-100, -100], "encoding": "u8",
		"row_order": "north_to_south"})
	var quality_record := _asset("source_quality.u8", quality)
	quality_record.merge({"size": [200, 200], "site_origin": [-100, -100], "encoding": "u8",
		"row_order": "north_to_south"})
	var tiles: Array[Dictionary] = []
	for origin: Vector2i in [Vector2i(-20000, -20000), Vector2i(0, -20000),
			Vector2i(-20000, 0), Vector2i.ZERO]:
		var heights := PackedByteArray()
		var levels := PackedByteArray()
		var water := PackedByteArray()
		var post_quality := PackedByteArray()
		var bodies := PackedByteArray()
		heights.resize(100 * 100 * 2)
		levels.resize(100 * 100)
		water.resize(100 * 100)
		post_quality.resize(100 * 100)
		bodies.resize(100 * 100 * 4)
		levels.fill(2)
		water.fill(2)
		for i: int in range(10000):
			heights.encode_s16(i * 2, 100)
			bodies.encode_u32(i * 4, 1)
			if origin == Vector2i.ZERO:
				var column := i % 100
				var row := i / 100
				var north_index := 99 - row
				if column <= 3 and north_index <= 3:
					water[i] = 1
					post_quality[i] = 1
					bodies.encode_u32(i * 4, 2)
		var prefix := "tile_%d_%d" % [origin.x, origin.y]
		var height_record := _asset(prefix + ".height.zlib", heights.compress(FileAccess.COMPRESSION_DEFLATE))
		var level_record := _asset(prefix + ".levels.zlib", levels.compress(FileAccess.COMPRESSION_DEFLATE))
		var water_record := _asset(prefix + ".water.zlib", water.compress(FileAccess.COMPRESSION_DEFLATE))
		var quality_tile_record := _asset(prefix + ".quality.zlib", post_quality.compress(FileAccess.COMPRESSION_DEFLATE))
		var body_record := _asset(prefix + ".water_body.zlib", bodies.compress(FileAccess.COMPRESSION_DEFLATE))
		var bank := PackedByteArray()
		var index := {}
		for site: Vector2i in COAST_SITES + [ISLAND]:
			if Grid.region_of(site) != Vector2i(Grid.floor_div(origin.x, 20000), Grid.floor_div(origin.y, 20000)):
				continue
			var mask := _island_mask() if site == ISLAND else _coast_mask(site)
			var segment := mask.compress(FileAccess.COMPRESSION_DEFLATE)
			var local_site := Grid.site_in_region(site)
			var key := str((99 - local_site.y) * 100 + local_site.x)
			index[key] = {"offset": bank.size(), "compressed_bytes": segment.size(), "sha256": _digest(segment)}
			bank.append_array(segment)
		var index_bytes := JSON.stringify(index).to_utf8_buffer()
		var index_record := _asset(prefix + ".index.json", index_bytes)
		var bank_record := _asset(prefix + ".bank.zlib", bank)
		var detail := {"index_path": index_record.path, "index_sha256": index_record.sha256,
			"index_bytes": index_bytes.size(), "data_path": bank_record.path,
			"data_sha256": bank_record.sha256, "data_bytes": bank.size(),
			"encoding": "u32_le_zlib_segments", "site_size": [100, 100],
			"site_order": "north_to_south"}
		var tile: Dictionary = {"id": prefix, "origin": [origin.x, origin.y], "size": [100, 100],
			"spacing_m": 200, "encoding": "int16_le_zlib", "row_order": "north_to_south",
			"nodata": -32767, "path": height_record.path, "sha256": height_record.sha256,
			"derived": {"encoding": "u8_zlib", "levels_path": level_record.path,
				"levels_sha256": level_record.sha256, "water_path": water_record.path,
				"water_sha256": water_record.sha256, "quality_path": quality_tile_record.path,
				"quality_sha256": quality_tile_record.sha256, "water_body_path": body_record.path,
				"water_body_sha256": body_record.sha256, "water_body_encoding": "u32_le_zlib",
				"water_detail": detail}}
		tiles.append(tile)
	return {"format": 1, "synthetic_fixture": true, "atlas_id": Grid.ATLAS_ID,
		"grid_contract_version": 1, "base_revision": "fine-mask-contract-v1", "crs": "EPSG:3826",
		"grid": {"origin": [0, 0], "cell_m": 2, "site_cells": 100, "region_sites": 100},
		"summary": summary_record, "content_scope": scope_record, "source_quality": quality_record,
		"source_quality_codes": {"0": "sea_or_missing", "1": "measured_moi", "4": "other_estimate"},
		"elevation_tiles": tiles, "water_bodies": [{"id": 2, "source_id": "fixture_lake",
			"kind": 1, "name": "Fixture lake"}], "sources": [{"id": "fine_synthetic", "title": "Synthetic"}],
		"sea_surface_rule": {"source": "synthetic", "summary_class": 1, "gameplay_level": 0,
			"whole_site_verified": true},
		"summary_counts": {"missing_data": 0, "sea": 39996, "land": 1, "inland_water": 0, "mixed": 3}}

func _site_index(site: Vector2i) -> int:
	return (199 - (site.y + 100)) * 200 + site.x + 100

func _coast_mask(site: Vector2i) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(100 * 100 * 4)
	for row: int in range(100):
		for column: int in range(100):
			var east := site.x * 200 + column * 2 + 1
			var north := site.y * 200 + (99 - row) * 2 + 1
			mask.encode_u32((row * 100 + column) * 4, 0 if east + north < 0 else 1)
	return mask

func _island_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(100 * 100 * 4)
	for row: int in range(100):
		for column: int in range(100):
			var east := 200 + column * 2 + 1
			var north := 200 + (99 - row) * 2 + 1
			mask.encode_u32((row * 100 + column) * 4,
				0 if absi(east - 300) <= 10 and absi(north - 300) <= 10 else 2)
	return mask

func _asset(name: String, bytes: PackedByteArray) -> Dictionary:
	_write(OUTPUT.path_join(name), bytes)
	return {"path": name, "sha256": _digest(bytes)}

func _digest(bytes: PackedByteArray) -> String:
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(bytes)
	return hasher.finish().hex_encode()

func _write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "Cannot write isolated fine-mask fixture")
	file.store_buffer(bytes)
