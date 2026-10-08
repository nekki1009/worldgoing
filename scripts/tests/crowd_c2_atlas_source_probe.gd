extends SceneTree
## Test-only reader copies: exact production code except explicit dependency
## paths and transparent FileAccess counters. No production asset is modified.
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Site = preload("res://scripts/terrain_lab/site_controller.gd")
const EDITOR_SOURCE := "res://scripts/ui/human_character_3d_editor.gd"
const SOURCE_SCRIPTS := ["res://scripts/terrain_lab/terrain_army_equipment_atlas.gd",
	"res://scripts/terrain_lab/terrain_army_dye_atlas.gd", "res://scripts/terrain_lab/terrain_army_ranged_atlas.gd",
	"res://scripts/tools/terrain_army_recipe_bake_plan.gd"]
var checks := 0
var output := ""

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	if not value:
		printerr("CROWD_ATLAS_SOURCE_PROBE_FAIL ", checks + 1, " ", label)
		quit(1)
		assert(value, label)
	checks += 1

func _text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "write isolated evidence")
	file.store_string(value)
	file.close()

func _json(path: String, value: Dictionary) -> void:
	_text(path, JSON.stringify(value, "\t", true, true))

func _reader_copy(source_copy: String) -> Dictionary:
	var scripts := output.path_join("scripts")
	_check(DirAccess.make_dir_recursive_absolute(scripts) == OK, "create test-only reader directory")
	var trace_path := scripts.path_join("source_trace.gd")
	_text(trace_path, "extends RefCounted\nstatic var hashes := {}\nstatic var calls := {}\nstatic func reset() -> void:\n\thashes.clear()\n\tcalls.clear()\nstatic func invoked(name: String) -> void:\n\tcalls[name] = int(calls.get(name, 0)) + 1\nstatic func md5(path: String) -> String:\n\thashes[path] = int(hashes.get(path, 0)) + 1\n\treturn FileAccess.get_md5(path)\n")
	var paths := {}
	var proofs := {}
	for path: String in SOURCE_SCRIPTS: paths[path] = scripts.path_join(path.get_file())
	for path: String in SOURCE_SCRIPTS:
		var original := FileAccess.get_file_as_string(path)
		var changed := original
		for dependency: String in paths:
			changed = changed.replace('preload("' + dependency + '")', 'preload("' + str(paths[dependency]) + '")')
		if path.ends_with("terrain_army_recipe_bake_plan.gd"):
			_check(changed.count('"' + EDITOR_SOURCE + '"') == 1, "only one explicitly remapped source declaration")
			changed = changed.replace('"' + EDITOR_SOURCE + '"', '"' + source_copy + '"')
		var trace_declaration := '\nconst Trace = preload("' + trace_path + '")'
		changed = changed.replace("extends RefCounted", "extends RefCounted" + trace_declaration)
		changed = changed.replace("FileAccess.get_md5(", "Trace.md5(")
		var marker := 'static func fingerprints() -> Dictionary:\n'
		var instrumentation := '\tTrace.invoked("' + path.get_file() + '.fingerprints")\n'
		changed = changed.replace(marker, marker + instrumentation)
		# Invert every permitted transform and prove the measured algorithm is
		# byte-for-byte the production source before loading the isolated copy.
		var restored := changed.replace(trace_declaration, "").replace("Trace.md5(", "FileAccess.get_md5(").replace(marker + instrumentation, marker)
		if path.ends_with("terrain_army_recipe_bake_plan.gd"): restored = restored.replace('"' + source_copy + '"', '"' + EDITOR_SOURCE + '"')
		for dependency: String in paths:
			restored = restored.replace('preload("' + str(paths[dependency]) + '")', 'preload("' + dependency + '")')
		_check(restored == original, "instrumentation inverse equals original " + path)
		_text(paths[path], changed)
		proofs[path] = {"original_sha256": FileAccess.get_sha256(path), "measured_copy": paths[path],
			"measured_sha256": FileAccess.get_sha256(paths[path]), "inverse_equal": true}
	return {"reader": load(paths[SOURCE_SCRIPTS[0]]), "trace": load(trace_path), "proofs": proofs}

func _copy_recipe(reader: Variant, appearance: Dictionary, source_copy: String) -> void:
	var published := Atlas.mixed_recipe(appearance)
	_check(not published.is_empty(), "current production mixed publication required")
	var source_path: String = published.source_manifest
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	var dye: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path.get_base_dir().path_join("dye.json")))
	var target: String = reader._mixed_directory(reader._mixed_key(appearance))
	_check(DirAccess.make_dir_recursive_absolute(target) == OK, "create copy under actual isolated source namespace")
	for fingerprints: Dictionary in [original.source_fingerprints, dye.source_fingerprints]:
		_check(fingerprints.get(EDITOR_SOURCE) == FileAccess.get_md5(source_copy), "copied source bytes match original provenance")
		fingerprints[source_copy] = FileAccess.get_md5(source_copy)
		fingerprints.erase(EDITOR_SOURCE)
	for field: String in ["path", "resource_path"]:
		var old_path: String = original.pages[0][field]
		var new_path := target.path_join(old_path.get_file())
		_check(DirAccess.copy_absolute(old_path, new_path) == OK and FileAccess.get_sha256(old_path) == FileAccess.get_sha256(new_path), "copy exact page bytes")
		original.pages[0][field] = new_path
	var mask_path := target.path_join(str(dye.mask_path).get_file())
	_check(DirAccess.copy_absolute(dye.mask_path, mask_path) == OK and FileAccess.get_sha256(dye.mask_path) == FileAccess.get_sha256(mask_path), "copy exact mask bytes")
	_json(target.path_join("manifest.json"), original)
	dye.source_manifest = target.path_join("manifest.json")
	dye.source_manifest_md5 = FileAccess.get_md5(dye.source_manifest)
	dye.mask_path = mask_path
	_json(target.path_join("dye.json"), dye)

func _counts(trace: Variant) -> Dictionary:
	return {"fingerprints": trace.calls.duplicate(true), "file_md5_reads": trace.hashes.duplicate(true)}

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var paths := Site.new()
	var configured: Dictionary = paths.configure_test_paths(args)
	paths.free()
	_check(configured.ok and args.has("--crowd-test"), "explicit isolated run namespace")
	output = "res://output/crowd_c2_c3_b_atlas_20261001/source_probe_" + args[args.find("--crowd-test") + 1]
	_check(not DirAccess.dir_exists_absolute(output), "never replace prior probe")
	_check(DirAccess.make_dir_recursive_absolute(output) == OK, "create probe root")
	var source_copy := output.path_join("human_character_source.gd.txt")
	var source_bytes := FileAccess.get_file_as_bytes(EDITOR_SOURCE)
	var source_sha := FileAccess.get_sha256(EDITOR_SOURCE)
	_check(DirAccess.copy_absolute(EDITOR_SOURCE, source_copy) == OK and FileAccess.get_sha256(source_copy) == source_sha, "byte-identical isolated source")
	var copied := _reader_copy(source_copy)
	var reader: Variant = copied.reader
	var trace: Variant = copied.trace
	_check(reader != null and trace != null, "load exact instrumented reader copies")
	reader._mixed_root = output.path_join("atlas")
	reader.refresh_female_sources()
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Atlas.BASE_MANIFEST)).appearance
	var appearances: Array = []
	var published_before := {}
	for body in range(2):
		var appearance: Dictionary = (base if body == 0 else Atlas.female_appearance()).duplicate(true)
		for slot: String in ["weapon", "shield", "helmet"]: appearance.parts[slot] = "none"
		appearance.equipment_dyes = {"armor": "123456ff", "boots": "876543ff"}
		var published := Atlas.mixed_recipe(appearance)
		_check(not published.is_empty(), "frozen-source mixed publication available")
		for name: String in ["manifest.json", "dye.json"]:
			var path: String = str(published.source_manifest).get_base_dir().path_join(name)
			published_before[path] = FileAccess.get_sha256(path)
		_copy_recipe(reader, appearance, source_copy)
		appearances.append(appearance)
	var palette: Dictionary = appearances[0].duplicate(true)
	palette.equipment_dyes.armor = "987654ff"
	appearances.append_array([palette, appearances[0].duplicate(true)])
	reader._clear_crowd_admission()
	trace.reset()
	var legacy: Array[Dictionary] = []
	for appearance: Dictionary in appearances:
		var record: Dictionary = reader.dye_entry(appearance)
		_check(not record.is_empty(), "original entry admits each copied recipe")
		legacy.append(record.duplicate(true))
	var legacy_counts := _counts(trace)
	trace.reset()
	var batch: Dictionary = reader.admit_crowd_appearances(appearances)
	_check(batch.ok and batch.unique_count == 3, "instrumented production public batch admits all appearances")
	var batch_counts := _counts(trace)
	_check(int(batch_counts.fingerprints.get("terrain_army_dye_atlas.gd.fingerprints", 0)) == 1, "actual common DyeAtlas.fingerprints call count is one")
	for path: String in Atlas.Plan.SOURCE_PATHS:
		var measured_path := source_copy if path == EDITOR_SOURCE else path
		_check(int(batch_counts.file_md5_reads.get(measured_path, 0)) == 1, "every common source really hashed once: " + measured_path)
		_check(int(legacy_counts.file_md5_reads.get(measured_path, 0)) > 1, "original multi-recipe path really repeated source reads")
	for index in range(appearances.size()):
		_check(reader.dye_entry(appearances[index]) == legacy[index], "measured optimization preserves complete admitted dye record")
	_check(_counts(trace) == batch_counts, "subsequent original entry consumes fully validated metadata without another source hash")
	_text(source_copy, source_bytes.get_string_from_utf8() + "\n# Isolated A4 source mutation.\n")
	trace.reset()
	var changed: Dictionary = reader.admit_crowd_appearances(appearances)
	_check(not changed.ok and changed.required_failed.size() == appearances.size(), "next public batch rejects actual changed source despite earlier success")
	var changed_counts := _counts(trace)
	_check(int(changed_counts.file_md5_reads.get(source_copy, 0)) >= 1, "changed isolated source was truly read")
	var restored := FileAccess.open(source_copy, FileAccess.WRITE)
	_check(restored != null, "restore isolated source only")
	restored.store_buffer(source_bytes)
	restored.close()
	trace.reset()
	_check(reader.admit_crowd_appearances(appearances).ok, "restored source revalidates through public admission")
	_check(FileAccess.get_sha256(EDITOR_SOURCE) == source_sha and FileAccess.get_sha256(source_copy) == source_sha, "formal source bytes never changed")
	for path: String in published_before: _check(FileAccess.get_sha256(path) == published_before[path], "formal publication unchanged")
	for path: String in copied.proofs: _check(FileAccess.get_sha256(path) == copied.proofs[path].original_sha256, "production reader source remained frozen")
	_json(output.path_join("result.json"), {"ok": true, "checks": checks, "legacy": legacy_counts, "batch": batch_counts,
		"changed_source_batch": changed_counts, "public_batch": batch, "script_copy_proof": copied.proofs,
		"source_copy": source_copy, "formal_source_sha256": source_sha,
		"scope": "test-only exact reader copies; only preload/source paths and transparent FileAccess counters differ; no runtime bypass or caller-provided trusted hash"})
	print("CROWD_ATLAS_SOURCE_PROBE_PASS checks=", checks, " report=", output.path_join("result.json"))
	quit(0)
