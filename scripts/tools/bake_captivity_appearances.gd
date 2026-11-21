extends SceneTree
## Publishes captive (stripped) looks into the runtime equipment atlas cache (Atlas default root, user://equipment_atlas/v1)
## so a later headless run finds them (CrowdSite._captivity_atlas_guard requires a published recipe headless).
## Input: a JSON array of appearances, default user://captivity_appearances_needed.json (written by
## region_siege_center_original_test), or --appearances <path>. Must run with a GPU (visual), never headless.
## Same capture path as scripts/tests/crowd_c2_captivity_atlas_fixture.gd, without the test-path redirect.
## Output: BAKE_CAPTIVITY_PASS / BAKE_CAPTIVITY_FAIL.
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
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
	print("BAKE_CAPTIVITY_PASS appearances=", baked, " root=", Atlas._mixed_root)
	quit(0)
