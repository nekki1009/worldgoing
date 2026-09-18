extends SceneTree
## Test-only admission of five newly baked pages; never changes formal assets.
const Reader = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Plan = preload("res://scripts/tools/terrain_army_recipe_bake_plan.gd")
const WORK := "res://output/terrain_army_m25_weapon_refresh_20260913/"

func _initialize() -> void:
	var work := work_for(OS.get_cmdline_user_args())
	if work.is_empty():
		_fail("Explicit --publish-test-only-m25 required; optional --work must name one directory under res://output/")
		return
	var catalog_path := work + "test_catalog.json"
	var pending_path := catalog_path + ".pending"
	if FileAccess.file_exists(catalog_path) or FileAccess.file_exists(pending_path):
		_fail("Test catalog or unfinished publication already exists; nothing overwritten")
		return
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(work + "batch_plan.json"))
	var recipe_total := int(plan.get("recipe_total", 0)) if plan is Dictionary else 0
	var batch_count := ceili(float(recipe_total) / float(Plan.MAX_BATCH_FRAMES)) if recipe_total > 0 else 0
	if not plan is Dictionary or plan.get("status") != "READY" or plan.get("test_only") != true or plan.get("source_fingerprints") != Plan.fingerprints() or plan.get("source_manifest_md5") != FileAccess.get_md5(Reader.BASE_MANIFEST) or not plan.get("batches") is Array or plan.batches.size() != batch_count:
		_fail("The bounded-batch test plan is incomplete or its locked original sources changed")
		return
	var batches: Array[Dictionary] = []
	var paths: Array[String] = []
	for index: int in range(batch_count):
		var entry: Variant = plan.batches[index]
		var first := index * Plan.MAX_BATCH_FRAMES
		var count := mini(Plan.MAX_BATCH_FRAMES, recipe_total - first)
		var source := work + "full/m25/%03d_%03d" % [first, count]
		if not entry is Dictionary or entry.get("index") != index or entry.get("mask") != 25 or entry.get("first") != first or entry.get("count") != count or entry.get("output") != source:
			_fail("The explicit m25 partition changed at batch %d" % index)
			return
		var verification: Variant = JSON.parse_string(FileAccess.get_file_as_string(source + "/verification/result.json"))
		if not verification is Dictionary or verification.get("status") != "PASS" or verification.get("exit_code") != 0 or verification.get("mode") != "visual" or verification.get("timed_out") != false or verification.get("failure") != null or verification.get("missing_outputs", ["missing"]) != [] or not verification.get("arguments") is Array:
			_fail("Batch %d has no preserved successful bounded GPU verification" % index)
			return
		for argument: String in ["res://scripts/tools/bake_terrain_army_soldier.gd", "--recipe-mask=25", "--recipe-output=" + source, "--recipe-clips=all", "--recipe-directions=all", "--recipe-first=%d" % first, "--recipe-count=%d" % count]:
			if argument not in verification.arguments:
				_fail("Batch %d verification belongs to a different command" % index)
				return
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(source + "/manifest.json"))
		if not manifest is Dictionary or not manifest.get("metrics") is Dictionary or not manifest.get("batch") is Dictionary or manifest.batch.get("first") != first or manifest.batch.get("count") != count or not manifest.get("pages") is Array or manifest.pages.size() != 1 or not manifest.pages[0] is Dictionary:
			_fail("Batch %d has no matching completed page manifest" % index)
			return
		var page: Dictionary = manifest.pages[0]
		var metrics: Dictionary = manifest.metrics
		var digest := str(metrics.get("pixel_sha256", ""))
		if page.get("path") != source + "/page_000.png" or page.get("resource_path") != source + "/page_000.res" or digest.length() != 64 or metrics.get("png_decoded_sha256") != digest or metrics.get("resource_decoded_sha256") != digest:
			_fail("Batch %d has no matching lossless PNG/resource proof" % index)
			return
		batches.append(manifest)
		paths.append(source + "/manifest.json")
	if Reader.validate_batches(25, batches, work).is_empty():
		_fail("m25 lacks its exact %d original samples or has mixed sources" % recipe_total)
		return
	var catalog := {"schema_version": 1, "test_only": true,
		"source_manifest_md5": plan.source_manifest_md5, "source_fingerprints": plan.source_fingerprints,
		"recipes": {Plan.recipe_key(25): paths}}
	var file := FileAccess.open(pending_path, FileAccess.WRITE)
	if file == null:
		_fail("Cannot stage the test catalog; no catalog enabled")
		return
	file.store_string(JSON.stringify(catalog, "\t"))
	file.close()
	# Exercise the existing real reader before the final rename. No alternate
	# loader: all unbaked masks must remain unavailable, including m31 here.
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Reader.BASE_MANIFEST)).appearance
	if not Reader.set_catalog_path(pending_path):
		_fail("Original reader rejected the test catalog path")
		return
	for mask: int in range(32):
		if Reader.supports(Plan.appearance_for(mask, baseline)) != (mask == 25):
			_fail("Test catalog did not admit exactly m25; pending evidence retained")
			return
	Reader.set_catalog_path(Reader.CATALOG)
	if Plan.fingerprints() != plan.source_fingerprints or FileAccess.get_md5(Reader.BASE_MANIFEST) != plan.source_manifest_md5:
		_fail("Original sources changed during test admission; pending evidence retained")
		return
	if FileAccess.file_exists(catalog_path) or DirAccess.rename_absolute(ProjectSettings.globalize_path(pending_path), ProjectSettings.globalize_path(catalog_path)) != OK:
		_fail("Cannot atomically enable the new test catalog; pending evidence retained")
		return
	print("TERRAIN ARMY M25 TEST CATALOG PASS: ", batch_count, " real GPU batches / ", recipe_total, " keys; other 31 masks rejected; formal catalog unchanged -> ", catalog_path)
	quit(0)

static func work_for(arguments: PackedStringArray) -> String:
	var explicit := false
	var selected := ""
	for argument: String in arguments:
		if argument == "--publish-test-only-m25" and not explicit:
			explicit = true
		elif argument.begins_with("--work=") and selected.is_empty():
			selected = argument.trim_prefix("--work=")
			if not selected.begins_with("res://output/"):
				return ""
			var name := selected.trim_prefix("res://output/").trim_suffix("/")
			# A single named child, not a normalized traversal, nested path, or a
			# formal asset directory. Preserve the original no-argument work path.
			if not name.replace("-", "_").is_valid_identifier():
				return ""
			selected = "res://output/" + name + "/"
		else:
			return ""
	return (WORK if selected.is_empty() else selected) if explicit else ""

func _fail(message: String) -> void:
	push_error(message)
	quit(2)
