extends SceneTree
## Real publication metadata + isolated corruption. The root runs bounded Godot.
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Site = preload("res://scripts/terrain_lab/site_controller.gd")
var checks := 0
var reports: Array[Dictionary] = []
var fixture := ""
var filter := "" # The original fixture's _cases is copied below, without filtering.

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	if not value:
		printerr("CROWD_ATLAS_ADMISSION_FAIL ", checks + 1, " ", label)
		quit(1)
		assert(value, label)
	checks += 1

func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "isolated fixture is writable")
	file.store_string(JSON.stringify(value, "\t", true, true))
	file.close()

func _evidence(appearance: Dictionary) -> Dictionary:
	var geometry := Atlas.DyeAtlas.Dye.geometry_appearance(appearance)
	var dye := Atlas.dye_entry(geometry)
	var recipe := Atlas.mixed_recipe(geometry)
	if recipe.is_empty() and int(geometry.body) == 1: recipe = Atlas.female_recipe(geometry)
	if recipe.is_empty(): recipe = Atlas.RangedAtlas.recipe(geometry)
	if recipe.is_empty():
		var mask := Atlas._appearance_mask(geometry)
		if mask >= 0: recipe = Atlas._recipe(mask, Atlas._appearance_iron(geometry))
	return {"dye": dye.duplicate(true), "recipe": recipe.duplicate(true)}

func _cases(base: Dictionary) -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	# The formal default culture's officer cape. No extra culture assets are invented.
	var cape := str(HumanCharacter3DEditor.PART_SLOTS.filter(func(slot: Dictionary) -> bool: return str(slot.id) == "cape")[0].options[0].id)
	for body in range(2):
		for caped in [false, true]:
			for armored in [true, false]:
				for captured in ([true] if armored else [false, true]):
					var appearance: Dictionary = (base if body == 0 else Atlas.female_appearance()).duplicate(true)
					appearance.parts.cape = cape if caped else "none"
					if not armored:
						appearance.parts.armor = "none"
						appearance.parts.helmet = "none"
					if captured:
						appearance.parts.weapon = "none"
						appearance.parts.shield = "none"
					appearance = Site._initial_uniform(appearance, 1)
					var label := "%s_%s_%s_%s" % ["male" if body == 0 else "female", "cape" if caped else "plain", "armor" if armored else "unarmored", "captured" if captured else "equipped"]
					if filter.is_empty() or (label.begins_with(filter) if filter in ["male_", "female_"] else label.contains(filter)): cases.append({"name": label, "appearance": appearance})
	return cases

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var paths := Site.new()
	var configured: Dictionary = paths.configure_test_paths(args)
	paths.free()
	_check(configured.ok and args.has("--crowd-test"), "explicit isolated run namespace")
	var run_id := args[args.find("--crowd-test") + 1]
	fixture = "res://output/crowd_c2_c3_b_atlas_20261001/admission_" + run_id
	var output_at := args.find("--crowd-output")
	if output_at >= 0:
		_check(output_at + 1 < args.size(), "--crowd-output requires a new report directory")
		fixture = args[output_at + 1].replace("\\", "/").simplify_path().trim_suffix("/")
		_check(fixture.begins_with("res://output/"), "optional report root stays inside project output")
	_check(not DirAccess.dir_exists_absolute(fixture), "never overwrite earlier evidence")
	_check(DirAccess.make_dir_recursive_absolute(fixture) == OK, "create isolated fixture")
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Atlas.BASE_MANIFEST)).appearance
	var cases: Array = [base.duplicate(true), Atlas.female_appearance()]
	var minimal := args.has("--atlas-minimal")
	var current_captivity := args.has("--atlas-current-captivity")
	_check(not (minimal and current_captivity), "current captivity mode retains all twelve cases and the corruption guards")
	var case_mode := "current_captivity_12_plus_base_female" if current_captivity else ("legacy_minimal" if minimal else "legacy_full")
	var case_names: Array[String] = ["male_base", "female_base"]
	if current_captivity:
		var current_cases := _cases(base)
		_check(current_cases.size() == 12 and str(current_cases.back().name) == "female_cape_unarmored_captured", "use every original captivity fixture case and its final mixed female corruption target")
		for row: Dictionary in current_cases:
			cases.append(row.appearance)
			case_names.append(str(row.name))
	elif not minimal:
		for body in range(2):
			for weapon: String in ["bow_01", "crossbow_01"]:
				var appearance: Dictionary = (base if body == 0 else Atlas.female_appearance()).duplicate(true)
				appearance.parts.weapon = weapon
				appearance.parts.shield = "none"
				cases.append(appearance)
		var removed := base.duplicate(true)
		for slot: String in ["weapon", "shield", "helmet"]: removed.parts[slot] = "none"
		removed.equipment_dyes = {"armor": "b6433aff", "boots": "49332fff", "outfit": "e3d5baff"}
		cases.append(removed)
	var expected: Array[Dictionary] = []
	for appearance: Dictionary in cases:
		var record := _evidence(appearance)
		_check(not record.dye.is_empty() and not record.recipe.is_empty(), "original current-source admission")
		expected.append(record)
	var palette: Dictionary = cases[0].duplicate(true)
	palette.equipment_dyes = {"armor": "123456ff"}
	var required: Array = cases.duplicate(true)
	required.append_array([null, cases[0].duplicate(true), palette])
	var before := var_to_bytes(required)
	var missing: Dictionary = Atlas.female_appearance().duplicate(true)
	missing.parts.hair = "hair_female_02"
	_check(HumanCharacter3DEditor.valid_appearance(missing), "optional missing recipe is a valid appearance")
	for iteration in range(2):
		var started := Time.get_ticks_usec()
		var admitted := Atlas.admit_crowd_appearances(required, [missing])
		admitted["elapsed_us"] = Time.get_ticks_usec() - started
		reports.append(admitted)
		_check(admitted.ok and admitted.required_failed.is_empty(), "all required appearances admitted")
		_check(admitted.optional_missing == [0], "missing optional recipe never rejects required admission")
		_check(admitted.unique_count == cases.size() + 2 and admitted.admitted_count == cases.size() + 1, "duplicates and null skipped; palette remains distinct")
		_check(admitted.source_hash_calls.bundle_fingerprints == 1, "one actual common Dye fingerprint bundle in public admission")
		var admitted_sources: Dictionary = Atlas.DyeAtlas._sources
		_check(not admitted_sources.is_empty() and admitted_sources == Atlas.DyeAtlas.fingerprints(), "original Dye source cache equals this batch's actual current source fingerprints")
		_check(not Atlas.DyeAtlas.entry(base).is_empty(), "base entry still validates the admitted current-source mask")
		_check(is_same(Atlas.DyeAtlas._sources, admitted_sources), "subsequent base entry reuses the same admitted source cache")
		_check(var_to_bytes(required) == before, "caller appearances remain unchanged")
		for index in range(cases.size()):
			_check(_evidence(cases[index]) == expected[index], "original and batch admission preserve exact recipe/frame/page/mask metadata")
	var expected_sources: Dictionary = Atlas.DyeAtlas._sources.duplicate()
	var poisoned_sources: Dictionary = expected_sources.duplicate()
	poisoned_sources[poisoned_sources.keys()[0]] = "00000000000000000000000000000000"
	Atlas.DyeAtlas._entries.clear()
	Atlas.DyeAtlas._sources = poisoned_sources
	_check(Atlas.DyeAtlas.entry(base).is_empty(), "base entry rejects poisoned cached fingerprints without weakening its source guard")
	_check(Atlas.admit_crowd_appearances([base]).ok, "next public admission clears poisoned state and reloads genuine current fingerprints")
	_check(Atlas.DyeAtlas._sources == expected_sources and not is_same(Atlas.DyeAtlas._sources, poisoned_sources), "next batch replaces the poisoned cache with the fresh validated source bundle")
	_check(not Atlas.DyeAtlas.entry(base).is_empty(), "base mask admission recovers after original cache reset and fresh validation")
	var invalid: Dictionary = base.duplicate(true)
	invalid.parts.weapon = "missing_recipe_weapon"
	var rejected := Atlas.admit_crowd_appearances([base, invalid], [])
	_check(not rejected.ok and rejected.required_failed == [1], "required failure identifies its original index")
	_check(Atlas.DyeAtlas._sources.is_empty(), "failed required batch clears the shared Dye source cache")
	_check(Atlas.admit_crowd_appearances([base]).ok, "failed batch leaves no incomplete success marker")
	if not minimal: _corrupt_copy(cases.back())
	_write(fixture.path_join("result.json"), {"ok": true, "checks": checks, "minimal": minimal,
		"case_mode": case_mode, "case_count": cases.size(), "current_captivity_case_names": case_names if current_captivity else [],
		"captivity_fixture_source_sha256": FileAccess.get_sha256("res://scripts/tests/crowd_c2_captivity_atlas_fixture.gd") if current_captivity else "",
		"batches": reports, "source_scope": "Public admission computes one actual common Dye fingerprint bundle and seeds the original Dye source cache for male-base fallback. Extra-source counters and other original reader/hash scopes remain separate; this is not a whole-process fingerprint call count. Cache equality, same-cache base entry, poisoned-cache rejection, fresh-batch recovery and failure clearing are checked outside batch timings.",
		"not_covered": ["actual production source mutation requires an isolated project copy", "GPU first-frame/texture/tracks verified by original recipe gate"]})
	print("CROWD_ATLAS_ADMISSION_PASS checks=", checks, " minimal=", minimal, " report=", fixture.path_join("result.json"))
	quit(0)

func _corrupt_copy(appearance: Dictionary) -> void:
	var original_root: String = Atlas._mixed_root
	var key := Atlas._mixed_key(appearance)
	var original := Atlas._mixed_directory(key)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(original.path_join("manifest.json")))
	var dye: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(original.path_join("dye.json")))
	var original_manifest_sha := FileAccess.get_sha256(original.path_join("manifest.json"))
	var original_dye_sha := FileAccess.get_sha256(original.path_join("dye.json"))
	Atlas._mixed_root = fixture.path_join("copied_atlas")
	Atlas.refresh_female_sources()
	var target := Atlas._mixed_directory(key)
	_check(DirAccess.make_dir_recursive_absolute(target) == OK, "copy has its own namespace")
	for field: String in ["path", "resource_path"]:
		var before_path: String = source.pages[0][field]
		var after_path := target.path_join(before_path.get_file())
		_check(DirAccess.copy_absolute(before_path, after_path) == OK and FileAccess.get_sha256(before_path) == FileAccess.get_sha256(after_path), "copy exact page bytes")
		source.pages[0][field] = after_path
	var mask_target := target.path_join(str(dye.mask_path).get_file())
	_check(DirAccess.copy_absolute(dye.mask_path, mask_target) == OK and FileAccess.get_sha256(dye.mask_path) == FileAccess.get_sha256(mask_target), "copy exact mask bytes")
	dye.mask_path = mask_target
	dye.source_manifest = target.path_join("manifest.json")
	_write(target.path_join("manifest.json"), source)
	dye.source_manifest_md5 = FileAccess.get_md5(target.path_join("manifest.json"))
	_write(target.path_join("dye.json"), dye)
	_check(Atlas.admit_crowd_appearances([appearance]).ok, "valid relocated copy admitted through current source hashes")
	for defect: String in ["source", "frame", "page", "mask", "size", "appearance", "path"]:
		var broken := source.duplicate(true)
		var broken_dye := dye.duplicate(true)
		match defect:
			"source": broken.source_fingerprints["res://scripts/terrain_lab/terrain_army_equipment_atlas.gd"] = "00000000000000000000000000000000"
			"frame": broken.frames[0].clip = "missing_frame"
			"page": broken.pages[0].resource_md5 = "00000000000000000000000000000000"
			"mask": broken_dye.mask_md5 = "00000000000000000000000000000000"
			"size": broken_dye.width = int(broken_dye.width) + 1
			"appearance": broken.appearance.parts.weapon = "longsword_01"
			"path": broken.pages[0].path = target.path_join("../page_000.png")
		_write(target.path_join("manifest.json"), broken)
		broken_dye.source_manifest_md5 = FileAccess.get_md5(target.path_join("manifest.json"))
		_write(target.path_join("dye.json"), broken_dye)
		_check(not Atlas.admit_crowd_appearances([appearance]).ok, "new batch rejects changed " + defect + " despite old cached success")
		_write(target.path_join("manifest.json"), source)
		_write(target.path_join("dye.json"), dye)
		_check(Atlas.admit_crowd_appearances([appearance]).ok, "recovered copy revalidates after " + defect)
	_check(FileAccess.get_sha256(original.path_join("manifest.json")) == original_manifest_sha and FileAccess.get_sha256(original.path_join("dye.json")) == original_dye_sha, "source publication metadata untouched")
	Atlas._mixed_root = original_root
	Atlas.refresh_female_sources()
