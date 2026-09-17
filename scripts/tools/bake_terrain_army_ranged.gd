extends "res://scripts/tools/bake_terrain_army_soldier.gd"
## Original renderer, packer and lossless checks for exact unshielded weapons.
const RangedAtlas = preload("res://scripts/terrain_lab/terrain_army_ranged_atlas.gd")
var _ranged_sources := {}
var _ranged_base_md5 := ""

func _initialize() -> void:
	_started_usec = Time.get_ticks_usec()
	var flags := {}
	for argument: String in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() != 2 or pair[0] not in ["--weapon", "--output", "--first", "--count"] or flags.has(pair[0]) or pair[1].is_empty():
			_fail_ranged("Expected unique --weapon=<catalogue ID>, optional --output, --first and --count")
			return
		flags[pair[0]] = pair[1]
	var weapon := str(flags.get("--weapon", ""))
	var baseline: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not baseline is Dictionary:
		_fail_ranged("Ranged bake requires the original complete soldier manifest")
		return
	_recipe = RangedAtlas.plan(weapon, baseline)
	if _recipe.is_empty():
		_fail_ranged("Requires the original male/leather baseline and an exact catalogue weapon ID")
		return
	var output := str(flags.get("--output", "res://output/site_ranged_20260914/atlas/" + weapon)).simplify_path().trim_suffix("/")
	if not output.begins_with("res://output/") or not str(flags.get("--first", "0")).is_valid_int() or not str(flags.get("--count", str(RangedAtlas.FRAME_COUNT))).is_valid_int():
		_fail_ranged("Ranged bake output must be a named staging directory and bounds must be integers")
		return
	var first := int(flags.get("--first", 0))
	var count := int(flags.get("--count", RangedAtlas.FRAME_COUNT))
	if first < 0 or count < 1 or first + count > RangedAtlas.FRAME_COUNT:
		_fail_ranged("Ranged batch must remain inside all 584 required samples")
		return
	_recipe.merge({"ok": true, "mask": 29, "iron": 0, "output": output,
		"first": first, "count": count, "selected_total": RangedAtlas.FRAME_COUNT,
		"selection_complete": first == 0 and count == RangedAtlas.FRAME_COUNT,
		"recipe_complete": first == 0 and count == RangedAtlas.FRAME_COUNT})
	_recipe.source_fingerprints = RecipePlan.fingerprints()
	_ranged_sources = RangedAtlas.fingerprints()
	_ranged_base_md5 = FileAccess.get_md5(MANIFEST_PATH)
	if _recipe.source_fingerprints.is_empty() or _ranged_sources.is_empty() or _ranged_base_md5.length() != 32:
		_fail_ranged("Every original and ranged source must have a stable fingerprint")
		return
	for source_path: String in [ATLAS_PATH, ATLAS_RESOURCE_PATH, MANIFEST_PATH]:
		if FileAccess.file_exists(_destination(source_path)):
			_fail_ranged("Ranged batch already exists; choose a fresh staging directory: " + output)
			return
	call_deferred("_run")

func _write_recipe_manifest(atlas: Image, frames: Array[Dictionary]) -> void:
	assert(_ranged_sources == RangedAtlas.fingerprints() and _ranged_base_md5 == FileAccess.get_md5(MANIFEST_PATH), "Ranged sources changed during bake; partial output must not be published")
	super._write_recipe_manifest(atlas, frames)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_destination(MANIFEST_PATH)))
	manifest.kind = "terrain_army_ranged_batch"
	manifest.source_fingerprints = _ranged_sources
	assert(_ranged_sources == RangedAtlas.fingerprints() and _ranged_base_md5 == FileAccess.get_md5(MANIFEST_PATH), "Ranged sources changed before manifest completion")
	var file := FileAccess.open(_destination(MANIFEST_PATH), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("TERRAIN RANGED BATCH PASS: ", _recipe.key, " samples=", frames.size(), " -> ", _destination(MANIFEST_PATH))

func _fail_ranged(message: String) -> void:
	push_error(message)
	quit(2)
