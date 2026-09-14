extends SceneTree
## Explicit offline publication only: prepare a new folder, then one rename.
const Reader = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Plan = preload("res://scripts/tools/terrain_army_recipe_bake_plan.gd")
const WORK := "res://output/terrain_army_missing_gear_20260913/"
const DESTINATION := "res://assets/characters/terrain_lab_army/standard_soldier/recipes/v1"
const REFRESH_WORK := "res://output/western_iron_atlas_20260913/"
const REFRESH_DESTINATION := "res://assets/characters/terrain_lab_army/standard_soldier/recipes/v2"
var work := WORK
var destination := DESTINATION
var include_iron := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args in [PackedStringArray(["--prepare-western-iron-refresh"]), PackedStringArray(["--publish-western-iron-refresh"])]:
		work = REFRESH_WORK
		destination = REFRESH_DESTINATION
		include_iron = true
		if args[0] == "--prepare-western-iron-refresh":
			_prepare()
			return
	elif args != PackedStringArray(["--publish-complete-recipes"]):
		_fail("Explicit --publish-complete-recipes is required; this tool never publishes partial recipes")
		return
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(destination)):
		_fail("Published recipe destination already exists; refusing to overwrite it")
		return
	var expected := _jobs()
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(work + "batch_plan.json"))
	if not plan is Dictionary or plan.get("status") != "READY" or plan.get("source_fingerprints") != Plan.fingerprints() or plan.get("source_manifest_md5") != FileAccess.get_md5(Reader.BASE_MANIFEST) or not plan.get("batches") is Array or plan.batches != expected:
		_fail("The full recipe plan is incomplete or its locked original sources changed")
		return
	var grouped := {}
	var records: Array[Dictionary] = []
	for index: int in expected.size():
		var entry: Dictionary = plan.batches[index]
		var mask := int(entry.mask)
		var iron := int(entry.get("iron", 0))
		var source := str(entry.output)
		var verification: Variant = JSON.parse_string(FileAccess.get_file_as_string(source + "/verification/result.json"))
		if not verification is Dictionary or verification.get("status") != "PASS" or verification.get("exit_code") != 0 or verification.get("mode") != "visual" or verification.get("timed_out") != false or verification.get("failure") != null or verification.get("missing_outputs", ["missing"]) != []:
			_fail("Batch %d has no preserved successful bounded GPU verification" % index)
			return
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(source + "/manifest.json"))
		if not manifest is Dictionary or not manifest.get("metrics") is Dictionary or not manifest.get("pages") is Array or manifest.pages.size() != 1:
			_fail("Batch %d has no completed page manifest" % index)
			return
		var metrics: Dictionary = manifest.metrics
		var digest := str(metrics.get("pixel_sha256", ""))
		if digest.length() != 64 or metrics.get("png_decoded_sha256") != digest or metrics.get("resource_decoded_sha256") != digest:
			_fail("Batch %d has no lossless PNG/resource pixel proof" % index)
			return
		var key := Plan.recipe_key(mask, iron)
		if not grouped.has(key):
			grouped[key] = []
		grouped[key].append(manifest)
		records.append({"entry": entry, "manifest": manifest})
	for index: int in range(0, expected.size(), 5):
		var entry: Dictionary = expected[index]
		var batches: Array[Dictionary] = []
		batches.assign(grouped[Plan.recipe_key(entry.mask, entry.get("iron", 0))])
		if Reader.validate_batches(entry.mask, batches, work + "full/", entry.get("iron", 0)).is_empty():
			_fail("Recipe %s lacks its exact 536 original samples or has mixed sources" % entry.output)
			return
	var staging := work + "publish_%d" % int(Time.get_unix_time_from_system())
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(staging)):
		_fail("Publication staging path already exists; nothing was overwritten")
		return
	var catalog := {"schema_version": 1, "source_manifest_md5": plan.source_manifest_md5,
		"source_fingerprints": plan.source_fingerprints, "recipes": {}}
	for record: Dictionary in records:
		var entry: Dictionary = record.entry
		var manifest: Dictionary = record.manifest.duplicate(true)
		var relative := str(entry.output).trim_prefix(work + "full/")
		var staged := staging + "/" + relative
		var published := destination + "/" + relative
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(staged)) != OK:
			_fail("Cannot create recipe publication staging; partial staging is retained")
			return
		for filename: String in ["page_000.png", "page_000.res"]:
			var original := str(entry.output) + "/" + filename
			var target := staged + "/" + filename
			if DirAccess.copy_absolute(ProjectSettings.globalize_path(original), ProjectSettings.globalize_path(target)) != OK or FileAccess.get_md5(original) != FileAccess.get_md5(target):
				_fail("Recipe page copy failed byte verification; no catalog was published")
				return
		manifest.pages[0].path = published + "/page_000.png"
		manifest.pages[0].resource_path = published + "/page_000.res"
		if not _json(staged + "/manifest.json", manifest):
			return
		var key := str(manifest.recipe_key)
		if not catalog.recipes.has(key):
			catalog.recipes[key] = []
		catalog.recipes[key].append(published + "/manifest.json")
	if not _json(staging + "/catalog.json", catalog):
		return
	if Plan.fingerprints() != plan.source_fingerprints or FileAccess.get_md5(Reader.BASE_MANIFEST) != plan.source_manifest_md5:
		_fail("Recipe sources changed while preparing publication; no catalog was enabled")
		return
	var destination_absolute := ProjectSettings.globalize_path(destination)
	var staging_absolute := ProjectSettings.globalize_path(staging)
	var workspace := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/") + "/"
	if not staging_absolute.replace("\\", "/").begins_with(ProjectSettings.globalize_path(work).replace("\\", "/") + "publish_") or not destination_absolute.replace("\\", "/").begins_with(workspace + "assets/characters/terrain_lab_army/standard_soldier/recipes/"):
		_fail("Resolved publication move paths escaped their exact task directories")
		return
	if DirAccess.dir_exists_absolute(destination_absolute) or DirAccess.make_dir_recursive_absolute(destination_absolute.get_base_dir()) != OK or DirAccess.rename_absolute(staging_absolute, destination_absolute) != OK:
		_fail("Final recipe folder could not be atomically published; staging is retained")
		return
	print("TERRAIN ARMY RECIPES PUBLISH PASS: ", grouped.size(), " complete recipes / ", grouped.size() * 536, " samples / ", expected.size(), " checked pages -> ", destination)
	quit(0)

func _jobs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for variant: int in range(39 if include_iron else 32):
		var mask := variant if variant < 32 else 31
		var iron := 0 if variant < 32 else variant - 31
		for first: int in range(0, 536, 128):
			var count := mini(128, 536 - first)
			var folder := ("iron%d/" % iron if iron != 0 else "") + "m%02d/%03d_%03d" % [mask, first, count]
			var entry := {"index": result.size(), "mask": mask, "first": first, "count": count, "output": work + "full/" + folder}
			if include_iron:
				entry.iron = iron
			result.append(entry)
	return result

func _prepare() -> void:
	var path := work + "batch_plan.json"
	if FileAccess.file_exists(path):
		_fail("Locked refresh plan already exists; refusing to replace it")
		return
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(Reader.BASE_MANIFEST))
	if not source is Dictionary or source.get("source_fingerprints") != Plan.fingerprints():
		_fail("Publish and verify the newly baked baseline before locking recipes")
		return
	if not _json(path, {"status": "READY", "source_manifest_md5": FileAccess.get_md5(Reader.BASE_MANIFEST), "source_fingerprints": Plan.fingerprints(), "batches": _jobs()}):
		return
	print("TERRAIN ARMY REFRESH PLAN PASS: 32 original masks + 7 iron helmet/armor/boots combinations; 195 bounded batches")
	quit(0)

func _json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Cannot write recipe publication metadata: " + path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true

func _fail(message: String) -> void:
	push_error(message)
	quit(2)
