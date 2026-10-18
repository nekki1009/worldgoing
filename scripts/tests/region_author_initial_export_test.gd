extends SceneTree
## P4 S5d (B): the author-package export writer. A package written by RegionData.export_author_initial_package
## loads through load_author_package, its initial state reads back identically, world admission validates separately
## (source loading creates no world), and every refusal writes nothing. Synthetic fixtures in a
## test-owned user:// folder, removed at the end. Pure: no Site, no world is born.

const Data = preload("res://scripts/region_lab/region_data.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")

var folder := ""
var _failed: bool = false

func _initialize() -> void:
	call_deferred("run")

func _check(value: bool, message: String) -> bool:
	if value: return true
	if not _failed:
		_failed = true
		push_error("REGION_AUTHOR_INITIAL_EXPORT_FAIL: " + message)
		quit(1)
	return false

func _bytes(path: String, bytes: PackedByteArray) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not _check(file != null, "fixture file open"): return {}
	file.store_buffer(bytes)
	file.close()
	return {"path": path.get_file(), "bytes": bytes.size(), "sha256": FileAccess.get_sha256(path)}

## The synthetic natural source the loader's load_manifest reads (same shape as map_editor_source_contract_test).
func _natural_source() -> String:
	var summary := _bytes(folder.path_join("summary.bin"), PackedByteArray([2]))
	if _failed: return ""
	summary.erase("bytes")
	summary.merge({"size": [1, 1], "site_origin": [0, 0], "encoding": "u8", "row_order": "north_to_south", "nodata": 0})
	var heights := PackedFloat32Array()
	heights.resize(25); heights.fill(20.0)
	var elevation := _bytes(folder.path_join("elevation.bin"), heights.to_byte_array())
	if _failed: return ""
	elevation.erase("bytes")
	elevation.merge({"id": "fixture", "size": [5, 5], "origin": [-200, -200], "spacing_m": 200, "encoding": "float32_le", "row_order": "north_to_south", "nodata": -9999})
	var levels := PackedByteArray(); levels.resize(25); levels.fill(1)
	var waters := PackedByteArray(); waters.resize(25); waters.fill(0)
	var level_record := _bytes(folder.path_join("levels.bin"), levels)
	var water_record := _bytes(folder.path_join("water.bin"), waters)
	if _failed: return ""
	elevation["derived"] = {"levels_path": level_record.path, "levels_sha256": level_record.sha256, "water_path": water_record.path, "water_sha256": water_record.sha256, "encoding": "u8"}
	var natural := {"format": 1, "atlas_id": Grid.ATLAS_ID, "grid_contract_version": Grid.CONTRACT_VERSION,
		"crs": "EPSG:3826", "base_revision": "p4s5d_fixture", "sources": [], "synthetic_fixture": true,
		"grid": {"origin": [0, 0], "cell_m": 2, "site_cells": 100, "region_sites": 100},
		"summary": summary, "elevation_tiles": [elevation]}
	var path := folder.path_join("natural.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not _check(file != null, "natural fixture open"): return ""
	file.store_string(JSON.stringify(natural, "", true, true))
	file.close()
	return path

func _same(left: Variant, right: Variant) -> bool:
	return JSON.stringify(left, "", true, true) == JSON.stringify(right, "", true, true)

## Diagnostic: the first key path (or array index) where two normalized values differ; empty when equal.
func _first_difference(left: Variant, right: Variant, path: String) -> String:
	if left is Dictionary and right is Dictionary:
		var keys := {}
		for key: Variant in left: keys[str(key)] = true
		for key: Variant in right: keys[str(key)] = true
		for key: String in keys.keys():
			if not left.has(key) or not right.has(key): return path + "/" + key + " (present on one side only)"
			var found_key := _first_difference(left[key], right[key], path + "/" + key)
			if not found_key.is_empty(): return found_key
		return ""
	if left is Array and right is Array:
		if left.size() != right.size(): return path + " (length %d vs %d)" % [left.size(), right.size()]
		for index: int in left.size():
			var found_index := _first_difference(left[index], right[index], path + "[%d]" % index)
			if not found_index.is_empty(): return found_index
		return ""
	if JSON.stringify(left, "", true, true) != JSON.stringify(right, "", true, true):
		return path + " (" + JSON.stringify(left, "", true, true) + " vs " + JSON.stringify(right, "", true, true) + ")"
	return ""

func run() -> void:
	folder = "user://p4s5d_export_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _check(DirAccess.make_dir_recursive_absolute(folder) == OK, "fixture folder"): return
	var natural_path := _natural_source()
	if _failed: return
	var dependencies: Array = [{"path": natural_path, "id": "natural"}]
	var start := {"mode": "created_player", "site": [0, 0], "cell": [49, 49]}
	var state := {"id": "p4s5d_site", "residents": [{"name": "甲", "faction_id": 1, "house": "12"}],
		"features": {"12": {"kind": "house", "stage": "complete"}}, "next_feature": 13}

	# 1. Export, then load through the loader: the state reads back identically, world admission validates separately.
	var exported: Dictionary = Data.export_author_initial_package(folder, "package.json", dependencies, "natural", "p4s5d_export", 1, "P4S5D 匯出", "P4S5D 寫出後讀回", start, {"0:0": state})
	if not _check(exported.ok, "export writes the package: " + str(exported)): return
	var source := Data.new()
	var loaded: Dictionary = source.load_author_package(str(exported.path))
	if not _check(loaded.ok and loaded.get("initial_admitted") == true, "loader accepts export capability; full template validation remains at world creation: " + str(loaded)): return
	# The loader stores JSON.parse_string output as it is (region_data.gd ~196-201), so every whole number is a float.
	# Compare like with like: the written state through the same JSON round trip, both sides normalized the same way.
	var expected: Variant = JSON.parse_string(JSON.stringify(state, "", true, true))
	var read_back: Variant = source._author_initial.get("0:0", {})
	if OS.get_cmdline_user_args().has("--s5d-diag") and not _same(read_back, expected):
		print("S5D_DIAG first difference: " + _first_difference(read_back, expected, "$"))
	if not _check(source._author_initial.has("0:0") and _same(read_back, expected), "the initial state reads back identically (JSON-normalized, as the loader stores it)"): return

	# 2. The same content exports to the same digest (deterministic).
	var again: Dictionary = Data.export_author_initial_package(folder, "package_again.json", dependencies, "natural", "p4s5d_export", 1, "P4S5D 匯出", "P4S5D 寫出後讀回", start, {"0:0": state})
	if not _check(again.ok and again.package_digest == exported.package_digest, "the same export gives the same package digest"): return

	# 3. Refusals write nothing: a world_pin in the state, a non-dictionary state, and a bad start.
	var with_pin: Dictionary = state.duplicate(true)
	with_pin["world_pin"] = {"format": 2}
	var refused_pin: Dictionary = Data.export_author_initial_package(folder, "refused_pin.json", dependencies, "natural", "p4s5d_export", 1, "x", "y", start, {"0:0": with_pin})
	if not _check(not refused_pin.ok and refused_pin.code == "INVALID_AUTHOR_INITIAL" and not FileAccess.file_exists(folder.path_join("refused_pin.json")), "a state with world_pin is refused and nothing is written: " + str(refused_pin)): return
	var refused_text: Dictionary = Data.export_author_initial_package(folder, "refused_text.json", dependencies, "natural", "p4s5d_export", 1, "x", "y", start, {"0:0": "not a state"})
	if not _check(not refused_text.ok and refused_text.code == "INVALID_AUTHOR_INITIAL" and not FileAccess.file_exists(folder.path_join("refused_text.json")), "a non-dictionary state is refused and nothing is written"): return
	var refused_start: Dictionary = Data.export_author_initial_package(folder, "refused_start.json", dependencies, "natural", "p4s5d_export", 1, "x", "y", {"mode": "unknown"}, {"0:0": state})
	if not _check(not refused_start.ok and refused_start.code == "INVALID_AUTHOR_PACKAGE" and not FileAccess.file_exists(folder.path_join("refused_start.json")), "a manifest the loader would refuse is refused before any write: " + str(refused_start)): return

	# 4. Cleanup of every fixture file this test wrote.
	for name: String in ["summary.bin", "elevation.bin", "levels.bin", "water.bin", "natural.json", "package.json", "package_again.json", "initial_0_0.json"]:
		if FileAccess.file_exists(folder.path_join(name)): DirAccess.remove_absolute(folder.path_join(name))
	DirAccess.remove_absolute(folder)
	print("REGION_AUTHOR_INITIAL_EXPORT_PASS: digest=%s" % str(exported.package_digest).left(12))
	quit(0)
