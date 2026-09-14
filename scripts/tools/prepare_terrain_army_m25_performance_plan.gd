extends SceneTree
## Preparation only. The original baker/reader/formal catalog remain unchanged.
## --validate-only checks real source/536-key planning and path guards, no writes.
## --prepare-test-only-m25 locks current sources once into the NEW fixed staging.
const Plan = preload("res://scripts/tools/terrain_army_recipe_bake_plan.gd")
const Baker = preload("res://scripts/tools/bake_terrain_army_soldier.gd")
const Publisher = preload("res://scripts/tests/publish_terrain_army_m25_test_catalog.gd")
const WORK := "res://output/terrain_army_m25_performance_20260913/"
const SCALAR_WORK := "res://output/terrain_army_m25_scalar_20260913/"

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var work := WORK
	if "--scalar-stage" in arguments:
		work = SCALAR_WORK
		arguments.remove_at(arguments.find("--scalar-stage"))
	if arguments not in [PackedStringArray(["--validate-only"]), PackedStringArray(["--prepare-test-only-m25"])]:
		_fail("Choose explicit --validate-only or --prepare-test-only-m25; no implicit output")
		return
	_check_paths()
	var plan := _build_plan(work)
	if plan.is_empty():
		return
	if arguments == PackedStringArray(["--validate-only"]):
		print("TERRAIN ARMY M25 PREPARATION VALIDATION PASS: original source plan, 536 unique keys / five batches; no files written")
		quit(0)
		return
	# Even a partial former attempt is evidence: never overwrite or refresh its
	# fingerprints in place, and never reuse the older weapon-refresh output.
	var path := work + "batch_plan.json"
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(work)) or FileAccess.file_exists(path) or FileAccess.file_exists(path + ".pending"):
		_fail("New performance staging already exists; nothing overwritten")
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(work)) != OK:
		_fail("Cannot create the new named performance staging")
		return
	var file := FileAccess.open(path + ".pending", FileAccess.WRITE)
	if file == null:
		_fail("Cannot stage the immutable five-batch plan")
		return
	file.store_string(JSON.stringify(plan, "\t"))
	file.close()
	if Plan.fingerprints() != plan.source_fingerprints or FileAccess.get_md5(Baker.MANIFEST_PATH) != plan.source_manifest_md5:
		_fail("Original sources changed while preparing; pending evidence retained")
		return
	if FileAccess.file_exists(path) or DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".pending"), ProjectSettings.globalize_path(path)) != OK:
		_fail("Cannot enable the new plan; pending evidence retained")
		return
	print("TERRAIN ARMY M25 PREPARATION PASS: locked six current sources + baseline; 536 keys / five UNBAKED batches -> ", path)
	quit(0)

func _build_plan(work: String) -> Dictionary:
	var fingerprints := Plan.fingerprints()
	var baseline_hash := FileAccess.get_md5(Baker.MANIFEST_PATH)
	var baseline: Variant = JSON.parse_string(FileAccess.get_file_as_string(Baker.MANIFEST_PATH))
	if fingerprints.size() != 6 or baseline_hash.length() != 32 or not baseline is Dictionary or not baseline.get("appearance") is Dictionary or not baseline.get("clips") is Array or not baseline.get("directions") is Array:
		_fail("Cannot lock the complete original sources and baseline")
		return {}
	var original_clips: Array[Dictionary] = []
	var original_directions: Array[Dictionary] = []
	for value: Variant in baseline.clips:
		if not value is Dictionary or not (value.get("samples") is int or value.get("samples") is float):
			_fail("Baseline clip samples must be a numeric integer")
			return {}
		var samples := float(value.samples)
		if not is_finite(samples) or samples < 1.0 or samples > 536.0 or samples != floor(samples):
			_fail("Baseline clip samples are not a positive integral count within the 536-key plan")
			return {}
		# JSON numbers are floats; the original Baker.CLIPS counts are ints.
		# Dictionary equality is type-strict: normalize this validated count only,
		# retaining every original clip field, ordering and the full comparison.
		var clip: Dictionary = value.duplicate(true)
		clip.samples = int(samples)
		original_clips.append(clip)
	original_directions.assign(baseline.directions)
	var batches: Array[Dictionary] = []
	var keys := {}
	for index in range(5):
		var first := index * 128
		var count := mini(128, 536 - first)
		var output := work + "full/m25/%03d_%03d" % [first, count]
		var arguments := PackedStringArray(["--recipe-mask=25", "--recipe-output=" + output,
			"--recipe-clips=all", "--recipe-directions=all", "--recipe-first=%d" % first, "--recipe-count=%d" % count])
		var actual := Plan.build(arguments, Baker.CLIPS, Baker.DIRECTIONS, baseline.appearance)
		var reader_plan := Plan.build(arguments, original_clips, original_directions, baseline.appearance)
		if not actual.ok or not reader_plan.ok or actual != reader_plan or actual.recipe_total != 536 or actual.selected_total != 536:
			_fail("Current original baker and baseline do not describe the same 536-key m25 recipe")
			return {}
		var sequence: Array[String] = []
		for clip: Dictionary in actual.clips:
			for direction: Dictionary in actual.directions:
				for frame: int in int(clip.samples):
					sequence.append("%s|%s|%d" % [clip.id, direction.id, frame])
		for offset in range(first, first + count):
			if sequence.size() != 536 or keys.has(sequence[offset]):
				_fail("The bounded m25 partition has a duplicate or missing original key")
				return {}
			keys[sequence[offset]] = true
		batches.append({"index": index, "mask": 25, "first": first, "count": count, "output": output})
	if keys.size() != 536 or Plan.fingerprints() != fingerprints or FileAccess.get_md5(Baker.MANIFEST_PATH) != baseline_hash:
		_fail("The original sources changed or the five-batch coverage is incomplete")
		return {}
	return {"status": "READY", "test_only": true,
		"scope": "Current-source m25 performance fixture only; five unbaked GPU batches / 536 original samples; not formal 32-recipe publication.",
		"source_manifest_md5": baseline_hash, "source_fingerprints": fingerprints, "batches": batches}

func _check_paths() -> void:
	assert(Publisher.work_for(PackedStringArray(["--publish-test-only-m25"])) == Publisher.WORK)
	for work: String in [WORK, SCALAR_WORK]:
		for spelling: String in [work, work.trim_suffix("/")]:
			assert(Publisher.work_for(PackedStringArray(["--publish-test-only-m25", "--work=" + spelling])) == work)
			assert(Publisher.work_for(PackedStringArray(["--work=" + spelling, "--publish-test-only-m25"])) == work)
	for work: String in ["", "res://output/", "res://output/../assets", "res://output/a/../../assets", "res://output/a/b/",
		"res://output/a//", "res://output/a\\b", "res://assets/recipes", "user://output/a", "C:/output/a"]:
		assert(Publisher.work_for(PackedStringArray(["--publish-test-only-m25", "--work=" + work])).is_empty())
	for arguments: PackedStringArray in [PackedStringArray(), PackedStringArray(["--work=" + WORK]),
		PackedStringArray(["--publish-test-only-m25", "--unknown"]),
		PackedStringArray(["--publish-test-only-m25", "--publish-test-only-m25"]),
		PackedStringArray(["--publish-test-only-m25", "--work=" + WORK, "--work=" + WORK])]:
		assert(Publisher.work_for(arguments).is_empty())

func _fail(message: String) -> void:
	push_error(message)
	quit(2)
