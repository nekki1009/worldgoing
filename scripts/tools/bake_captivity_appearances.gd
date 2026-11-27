extends SceneTree
## Publishes captive (stripped) looks into the runtime equipment atlas cache (Atlas default root, user://equipment_atlas/v1)
## so a later headless run finds them (CrowdSite._captivity_atlas_guard requires a published recipe headless).
## Input: a JSON array of appearances, default user://captivity_appearances_needed.json (written by
## region_siege_center_original_test), or --appearances <path>. Must run with a GPU (visual), never headless.
## Same capture path as scripts/tests/crowd_c2_captivity_atlas_fixture.gd, without the test-path redirect.
## `--seed-out` (2026-11-28) also stores every look this run baked under CaptiveAtlasSeed.SEED_ROOT with an index, so the
## game copies them into the user cache instead of baking them while it is played (scripts/terrain_lab/captive_atlas_seed.gd).
## Run it after any change to the atlas sources (the cache directory names them), with the looks of the shipped scenarios
## (scripts/tests/scenario_captive_looks_probe.gd writes res://output/captive_looks/demo_a.json). The seed stays on this
## machine (its folder's .gitignore keeps it out of git); a packed build ships it.
## Output: BAKE_CAPTIVITY_PASS / BAKE_CAPTIVITY_FAIL.
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Seed = preload("res://scripts/terrain_lab/captive_atlas_seed.gd")
const Batch = preload("res://scripts/terrain_lab/terrain_army_batch_view.gd")
const CrowdSite = preload("res://scripts/terrain_lab/crowd_site.gd")

func _initialize() -> void:
	create_timer(900.0).timeout.connect(func() -> void:
		printerr("BAKE_CAPTIVITY_FAIL deadline")
		quit(2))
	_run.call_deferred()

func _fail(message: String) -> void:
	printerr("BAKE_CAPTIVITY_FAIL ", message)
	quit(1)

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists("ArmyCrowd"): return _fail("GPU and native class required")
	var args := OS.get_cmdline_user_args()
	var path := "user://captivity_appearances_needed.json"
	var at := args.find("--appearances")
	if at >= 0 and at + 1 < args.size(): path = args[at + 1]
	var listing: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not listing is Array or listing.is_empty(): return _fail("no appearances in " + path)
	Atlas.refresh_female_sources()
	var army := TerrainArmy.new()
	root.add_child(army)
	army.set_process(false)
	if not TerrainArmy.load_combat_bake() or not army._load_baked_soldier(): return _fail("baseline missing")
	var view := Batch.new()
	root.add_child(view)
	view.setup(army, 32)
	var host := CrowdSite.new()
	root.add_child(host)
	host.view = view
	host.crowd = ClassDB.instantiate("ArmyCrowd")
	host.crowd.setup(1, 71)
	var baked := 0
	var seeds: Array = []
	for entry: Variant in listing:
		if not entry is Dictionary: return _fail("appearance is not a dictionary")
		var appearance: Dictionary = entry
		var description: Dictionary = view._describe(appearance)
		var generated := false
		if description.is_empty():
			generated = await CrowdSite.prepare_captivity_recipe(root, appearance)
			description = view._describe(appearance)
		var kit := -1
		if not description.is_empty():
			var windows := PackedFloat32Array()
			windows.resize(CrowdSite.SLOTS.size())
			kit = host._make_kit(int(description.page), int(description.palette), appearance, windows)
		print("BAKE_CAPTIVITY_RESULT key=", Atlas._mixed_key(appearance), " generated=", generated, " kit=", kit, " missing=", host.missing, " root=", Atlas._mixed_root)
		if description.is_empty() or kit < 0 or not host.missing.is_empty(): return _fail("appearance not published: " + JSON.stringify(appearance))
		baked += 1
		var key := Atlas._mixed_key(appearance)
		var directory := Atlas._mixed_directory(key)
		if "--seed-out" in args and generated and not key.is_empty() and FileAccess.file_exists(directory + "/manifest.json"):
			var files: Array = []
			if not _store_tree(directory, "", key, files): return _fail("seed copy failed for " + key)
			seeds.append({"key": key, "directory": directory, "appearance": appearance, "files": files})
			print("BAKE_CAPTIVITY_SEED key=", key, " files=", files.size())
	if "--seed-out" in args:
		# Earlier stored looks of other keys stay; a key baked again replaces its entry.
		var index: Dictionary = {"schema": Seed.SCHEMA, "looks": []}
		if FileAccess.file_exists(Seed.INDEX):
			var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(Seed.INDEX))
			if old is Dictionary and old.get("schema") == Seed.SCHEMA and old.get("looks") is Array: index = old
		var fresh := {}
		for look: Dictionary in seeds: fresh[str(look.key)] = true
		var kept: Array = index.looks.filter(func(look: Variant) -> bool: return look is Dictionary and not fresh.has(str(look.get("key", ""))))
		kept.append_array(seeds)
		index.looks = kept
		var file := FileAccess.open(Seed.INDEX, FileAccess.WRITE)
		if file == null: return _fail("cannot write " + Seed.INDEX)
		file.store_string(JSON.stringify(index, "	", true))
		file.close()
		print("BAKE_CAPTIVITY_SEED_INDEX looks=", kept.size(), " new=", seeds.size(), " path=", Seed.INDEX)
	print("BAKE_CAPTIVITY_PASS appearances=", baked, " root=", Atlas._mixed_root)
	quit(0)

## Copies every file under `directory` (dot folders included) to Seed.SEED_ROOT under its stored name and lists it.
func _store_tree(directory: String, relative: String, key: String, files: Array) -> bool:
	var here := directory if relative.is_empty() else directory + "/" + relative
	var dir := DirAccess.open(here)
	if dir == null: return false
	dir.include_hidden = true
	for name: String in dir.get_files():
		var inner := name if relative.is_empty() else relative + "/" + name
		var bytes := FileAccess.get_file_as_bytes(here + "/" + name)
		if bytes.is_empty(): return false
		var stored := Seed.stored_name(key, inner)
		var target := Seed.SEED_ROOT + "/" + stored
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null: return false
		file.store_buffer(bytes)
		file.close()
		files.append({"path": inner, "stored": stored, "size": bytes.size(), "md5": FileAccess.get_md5(here + "/" + name)})
	for name: String in dir.get_directories():
		if not _store_tree(directory, name if relative.is_empty() else relative + "/" + name, key, files): return false
	return true
