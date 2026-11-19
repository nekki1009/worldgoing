extends SceneTree
## Main-scene UI wiring; generated sources, fixture placement/construction/readiness.
## Run with the unchanged canonical verifier; optional user argument --visual.
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const OUT: String = "res://output/wildlife_formal_20261002/capture_ui"
var lab: TerrainLab
var controller: SiteController
var visual: bool = false
var started: bool = false
var finished: bool = false
var waiting: bool = false
var deadline: int = 0
var stage: String = "startup"
var report: Dictionary = {"status": "INCOMPLETE", "checks": [], "captures": [], "fixture": "Formal main scene and its default generated sources; original player placed at work cells; pastures built with original Runtime; work readiness/time advanced explicitly. Not natural gameplay or performance proof."}

func _initialize() -> void:
	visual = OS.get_cmdline_user_args().has("--visual")
	deadline = Time.get_ticks_msec() + 60000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and (Time.get_ticks_msec() > deadline or (started and not waiting)):
		report.status = "FAIL"
		report["failure_stage"] = stage
		_write_report()
		push_error("SITE_WILDLIFE_CAPTURE_UI_FAIL: stopped or timed out at " + stage)
		finished = true
		quit(1)
	return false

func _write_report() -> void:
	var file: FileAccess = FileAccess.open(OUT + "/result_" + ("visual" if visual else "headless") + ".json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()

func _run() -> void:
	started = true
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT)) == OK)
	assert(OS.get_environment("APPDATA").replace("\\", "/").contains("/godot_verify/"), "Use the isolated canonical verifier profile")
	assert(not FileAccess.file_exists(Store.DEFAULT_PATH), "Verification profile already has a current Site")
	assert(not visual or DisplayServer.get_name() != "headless", "--visual needs a GPU window")
	root.gui_embed_subwindows = true
	if visual: DisplayServer.window_set_size(Vector2i(1600, 1000))
	var main_path: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	var scene: PackedScene = load(main_path) as PackedScene
	assert(scene != null)
	lab = scene.instantiate() as TerrainLab
	assert(lab != null)
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	controller = lab.site_controller
	controller._auto_save_blocked = true
	_freeze(lab)
	paused = false
	lab.terrain.site.paused = false
	lab.terrain.site.worker_enabled = false
	assert(lab.controlled_person_id() == lab.character.person_id)
	var person: Dictionary = controller.person_actions._person(lab.character.person_id)
	assert(not person.is_empty() and person.owner == lab.character and controller.person_actions._ready(person))
	var cargo: Dictionary = person.cargo
	assert(is_same(cargo, lab.terrain.site.manual.cargo) and is_same(cargo, lab.character.ammo_inventory) and cargo.is_empty())
	assert(controller.manual_capture_button.name == "ManualCapture" and controller.manual_capture_button.get_signal_connection_list("pressed").size() == 1)
	assert(controller.stock_pasture_button.name == "StockPasture" and controller.stock_pasture_button.get_signal_connection_list("pressed").size() == 1)
	assert(controller.modes.item_count == 7 and controller.modes.get_item_text(6) == "馬羊捕捉區")
	controller.modes.select(6)
	controller.modes.item_selected.emit(6)
	assert(controller.modes.selected == 6 and not lab.test_placement_enabled)
	var immutable_base: PackedByteArray = var_to_bytes(lab.terrain.resource_base)
	report["main_scene"] = main_path
	report["preset"] = lab.terrain.preset
	report["seed"] = lab.terrain.seed_value
	report["site_id"] = str(lab.terrain.site.id)
	report["mode"] = "visual" if visual else "headless"
	report["user_data_dir"] = OS.get_user_data_dir()
	_write_report()
	stage = "wrong species button guards"
	for species: String in ["stag", "boar", "doe"]:
		_select_source(_source(species))
		assert(controller.manual_capture_button.disabled, "Wrong species capture button remained enabled: " + species)
		var before: PackedByteArray = _signature()
		controller.manual_capture_button.pressed.emit() # Forced signal also tests the command guard.
		assert(_signature() == before and str(lab.terrain.site.manual.target).is_empty())
	report.checks.append({"phase": "wrong_species", "disabled_and_forced_signal_rejected": ["stag", "boar", "doe"]})
	for species: String in ["horse", "sheep"]:
		stage = "capture " + species
		var key: String = _source(species)
		_select_source(key)
		assert(not controller.manual_capture_button.disabled)
		var work_cell: Vector2i = Env.work_cells(lab.terrain, key)[0]
		assert(lab.character.place(work_cell, true), "Player fixture could not enter generated work cell")
		_check_paused_signal(controller.manual_capture_button)
		var held_before: Dictionary = cargo.duplicate()
		var stock_before: int = int(Env.resource(lab.terrain, key).remaining)
		var clock_before: float = Runtime.now(lab.terrain)
		controller.manual_capture_button.pressed.emit()
		assert(lab.terrain.site.manual.target == key and lab.terrain.site.manual.action == "capture" and lab.terrain.site.manual.progress == 0.0)
		assert(float(Env.WORK_MINUTES[Env.Kind.WILDLIFE]) == 6.0)
		Runtime.advance(lab.terrain, 5.999, false, true)
		assert(lab.terrain.site.manual.target == key and cargo == held_before and int(Env.resource(lab.terrain, key).remaining) == stock_before, "Capture completed before six original game minutes")
		Runtime.advance(lab.terrain, 0.001, false, true)
		var expected: Dictionary = held_before.duplicate()
		expected[species] = int(expected.get(species, 0)) + 1
		assert(str(lab.terrain.site.manual.target).is_empty() and cargo == expected and not cargo.has("meat") and not cargo.has("hide"))
		assert(int(Env.resource(lab.terrain, key).remaining) == stock_before - 1 and is_equal_approx(Runtime.now(lab.terrain) - clock_before, 6.0))
		assert(is_same(cargo, controller.person_actions._person(lab.character.person_id).cargo))
		report.checks.append({"phase": "capture", "species": species, "source_key": key, "work_cell": [work_cell.x, work_cell.y], "source_remaining_before": stock_before, "source_remaining_after": stock_before - 1, "original_game_minutes": 6, "original_cargo": cargo.duplicate(), "both_pause_guards": true})
		await _capture(species + "_captured", "work")
	stage = "pasture construction fixture"
	var pastures: Dictionary = {"horse": _build("horse_ranch"), "sheep": _build("pasture")}
	for species: String in ["horse", "sheep"]:
		stage = "stock " + species
		var feature_key: String = str(pastures[species])
		var feature: Dictionary = lab.terrain.site.features[feature_key]
		assert(lab.character.place(lab.terrain.cell_from_index(int(feature.entrance)), true))
		controller.select_cell(lab.terrain.cell_from_index(int(feature.cells[0])))
		assert(controller.feature_key == feature_key and not controller.stock_pasture_button.disabled)
		_check_paused_signal(controller.stock_pasture_button)
		var stock_before: Dictionary = lab.terrain.site.inventory.duplicate()
		var expected_cargo: Dictionary = cargo.duplicate()
		expected_cargo.erase(species)
		var expected_feature: Dictionary = feature.duplicate(true)
		expected_feature.residents = int(feature.residents) + 1
		var holder: Dictionary = lab.character.item_state
		var version_before: int = int(holder.version)
		controller.stock_pasture_button.pressed.emit()
		assert(cargo == expected_cargo and feature == expected_feature and lab.terrain.site.inventory == stock_before)
		assert(is_same(holder, lab.character.item_state) and is_same(cargo, controller.person_actions._person(lab.character.person_id).cargo) and int(holder.version) == version_before + 1)
		report.checks.append({"phase": "stock", "species": species, "feature_key": feature_key, "original_residents": feature.residents, "original_cargo": cargo.duplicate(), "holder_version_before": version_before, "holder_version_after": holder.version, "same_original_holder_and_cargo": true, "both_pause_guards": true})
		await _capture(species + "_stocked", "construction")
	assert(cargo.is_empty() and var_to_bytes(lab.terrain.resource_base) == immutable_base)
	finished = true
	report.status = "PASS"
	_write_report()
	print("SITE_WILDLIFE_CAPTURE_UI_PASS original main buttons; horse/sheep six-minute capture; paused/wrong-species guards; original cargo/residents/holder versions")
	lab.queue_free()
	await process_frame
	quit(0)

func _source(species: String) -> String:
	for key: String in lab.terrain.resource_base:
		var resource: Dictionary = Env.resource(lab.terrain, key)
		if int(resource.kind) == Env.Kind.WILDLIFE and Env.wildlife_species(int(resource.variant), int(resource.cell)) == species and int(resource.remaining) > 0 and not bool(resource.cleared) and lab.terrain.feature_at[int(resource.cell)] == 0 and not Env.work_cells(lab.terrain, key).is_empty():
			controller.kinds.select(Env.Kind.WILDLIFE + 1)
			controller.select_cell(lab.terrain.cell_from_index(int(resource.cell)))
			if controller.source_key == key: return key # Overlapping herds follow the real selector's first source.
	assert(false, "Missing generated UI fixture species: " + species)
	return ""

func _select_source(key: String) -> void:
	controller.kinds.select(Env.Kind.WILDLIFE + 1)
	controller.select_cell(lab.terrain.cell_from_index(int(lab.terrain.resource_base[key].cell)))
	assert(controller.source_key == key, "Formal source selection did not select the generated wildlife")

func _signature() -> PackedByteArray:
	return var_to_bytes([lab.terrain.resource_base, lab.terrain.site, lab.character.item_state])

func _check_paused_signal(button: Button) -> void:
	for tree_pause: bool in [true, false]:
		paused = tree_pause
		lab.terrain.site.paused = not tree_pause
		var before: PackedByteArray = _signature()
		button.pressed.emit()
		assert(_signature() == before, "Paused command changed stock, work, cargo, residents or holder")
	paused = false
	lab.terrain.site.paused = false

func _build(kind: String) -> String:
	for y: int in range(2, lab.terrain.size.y - 2):
		for x: int in range(2, lab.terrain.size.x - 3):
			var cells: Array[int] = [lab.terrain.index(Vector2i(x, y)), lab.terrain.index(Vector2i(x + 1, y))]
			var preview: Dictionary = Runtime.preview_build(lab.terrain, kind, cells)
			if not preview.ok or not preview.clearing.is_empty() or Runtime.grazing_capacity(lab.terrain, cells) < 3:
				continue
			var built: Dictionary = Runtime.request_build(lab.terrain, kind, cells)
			assert(built.ok, str(built))
			var feature: Dictionary = lab.terrain.site.features[str(built.feature)]
			Runtime.assign_task(lab.terrain, Runtime.ok("UI fixture construction", {"target": "feature:" + str(built.feature), "action": "construct", "cell": feature.entrance}))
			lab.terrain.site.worker.cell = feature.entrance
			lab.terrain.site.worker.mode = "work"
			Runtime.advance(lab.terrain, float(feature.work), true)
			assert(feature.stage == "complete")
			return str(built.feature)
	assert(false, "No lawful construction fixture for " + kind)
	return ""

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children(): _freeze(child)

func _capture(label: String, window: String) -> void:
	if not visual: return
	var before: PackedByteArray = _signature()
	paused = true
	controller.hide_tool_windows()
	controller.open_window(window)
	controller.view.refresh()
	lab.camera.zoom = Vector2.ONE * 1.5
	lab.camera.position = lab.character.position
	lab.camera.force_update_scroll()
	lab.renderer.set_process(true)
	waiting = true
	while lab.renderer.display_pending:
		await process_frame
		await RenderingServer.frame_post_draw
	for _frame: int in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	waiting = false
	lab.renderer.set_process(false)
	var picture: Image = root.get_texture().get_image()
	assert(picture != null and not picture.is_empty())
	var path: String = OUT + "/" + label + ".png"
	assert(picture.save_png(path) == OK and _signature() == before)
	report.captures.append({"label": label, "path": path, "sha256": FileAccess.get_sha256(path), "fixture_placement": true})
	_write_report()
	paused = false
