extends SceneTree
## Exact GPU publications for C2 captivity and D's explicit unarmored fixture.
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Batch = preload("res://scripts/terrain_lab/terrain_army_batch_view.gd")
const CrowdSite = preload("res://scripts/terrain_lab/crowd_site.gd")
const Site = preload("res://scripts/terrain_lab/site_controller.gd")
var output_root := "res://output/crowd_c2_c3_20261001/atlas"
var report_root := ""
var results: Array[Dictionary] = []
var current_case := "startup"
var started := 0
var finished := false
var filter := ""

func _initialize() -> void:
	_run.call_deferred()

func _write(complete: bool) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_root))
	var file := FileAccess.open(report_root.path_join("fixture" + ("_" + filter if not filter.is_empty() else "") + ".json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"complete": complete, "atlas_root": output_root, "current": current_case, "seconds": float(Time.get_ticks_msec() - started) / 1000.0, "results": results}, "\t"))
		file.close()

func _deadline() -> void:
	if finished: return
	_write(false)
	printerr("CROWD_CAPTIVITY_ATLAS_FAIL deadline current=", current_case)
	quit(2)

func _progress() -> void:
	while not finished:
		await create_timer(10.0).timeout
		if finished: return
		var capture := Atlas._preparation
		print("CROWD_CAPTIVITY_ATLAS_PROGRESS ", current_case, " seconds=", float(Time.get_ticks_msec() - started) / 1000.0,
			" phase=", str(capture.get("phase")) if is_instance_valid(capture) else "idle",
			" frames=", str(capture.get("captured_frames")) if is_instance_valid(capture) else "0")

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
	started = Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	var paths := Site.new()
	var path_args := args.duplicate()
	if not path_args.has("--crowd-atlas-root"):
		path_args.append_array(PackedStringArray(["--crowd-atlas-root", output_root]))
	var configured: Dictionary = paths.configure_test_paths(path_args)
	paths.free()
	if not configured.ok:
		printerr("CROWD_CAPTIVITY_ATLAS_FAIL ", configured)
		quit(1)
		return
	output_root = Atlas._mixed_root
	report_root = output_root
	var report_at := args.find("--crowd-output")
	if report_at >= 0:
		if report_at + 1 >= args.size():
			printerr("CROWD_CAPTIVITY_ATLAS_FAIL missing report root")
			quit(1)
			return
		report_root = args[report_at + 1].replace("\\", "/").simplify_path().trim_suffix("/")
		if not (report_root.begins_with("res://output/") or report_root.begins_with("res://native/crowd10k/out_c2/") or report_root.begins_with("res://native/crowd10k/out_c3/")):
			printerr("CROWD_CAPTIVITY_ATLAS_FAIL report root must be a project evidence subdirectory")
			quit(1)
			return
	var at := args.find("--crowd-atlas-filter")
	if at >= 0 and at + 1 < args.size(): filter = args[at + 1]
	if not filter.is_empty() and filter not in ["male_", "female_", "plain_", "cape_", "unarmored", "armor_captured"]:
		printerr("CROWD_CAPTIVITY_ATLAS_FAIL unsupported filter")
		quit(1)
		return
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists("ArmyCrowd"):
		printerr("CROWD_CAPTIVITY_ATLAS_FAIL GPU and native class required")
		quit(1)
		return
	create_timer(900.0).timeout.connect(_deadline)
	_progress()
	Atlas._mixed_root = output_root
	Atlas.refresh_female_sources()
	var army := TerrainArmy.new()
	root.add_child(army)
	army.set_process(false)
	if not TerrainArmy.load_combat_bake() or not army._load_baked_soldier():
		printerr("CROWD_CAPTIVITY_ATLAS_FAIL baseline missing")
		quit(1)
		return
	var view := Batch.new()
	root.add_child(view)
	view.setup(army, 32)
	var host := CrowdSite.new()
	root.add_child(host)
	host.view = view
	host.crowd = ClassDB.instantiate("ArmyCrowd")
	host.crowd.setup(1, 71)
	var cases := _cases(TerrainArmy._combat_bake.manifest.appearance)
	for row: Dictionary in cases:
		current_case = str(row.name)
		var appearance: Dictionary = row.appearance
		var before := appearance.duplicate(true)
		var description: Dictionary = view._describe(appearance)
		var generated := false
		print("CROWD_CAPTIVITY_ATLAS_BEGIN ", current_case, " cached=", not description.is_empty())
		if description.is_empty():
			generated = await CrowdSite.prepare_captivity_recipe(root, appearance)
			description = view._describe(appearance)
		var kit := -1
		if not description.is_empty():
			var windows := PackedFloat32Array()
			windows.resize(CrowdSite.SLOTS.size())
			kit = host._make_kit(int(description.page), int(description.palette), appearance, windows)
		var record := Atlas.dye_entry(appearance)
		var recipe := Atlas.mixed_recipe(appearance)
		var ok := not description.is_empty() and kit >= 0 and host.missing.is_empty() and before == appearance and not record.is_empty()
		results.append({"name": current_case, "ok": ok, "generated": generated, "key": Atlas._mixed_key(appearance), "appearance": appearance,
			"manifest": recipe.get("source_manifest", record.get("source_manifest", "")), "missing": host.missing.duplicate()})
		_write(false)
		print("CROWD_CAPTIVITY_ATLAS_RESULT ", current_case, " ok=", ok, " generated=", generated, " missing=", host.missing)
		if not ok:
			finished = true
			printerr("CROWD_CAPTIVITY_ATLAS_FAIL ", current_case)
			quit(1)
			return
	finished = true
	_write(true)
	print("CROWD_CAPTIVITY_ATLAS_PASS cases=", results.size(), " root=", output_root)
	quit(0)
