extends SceneTree

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const OUTPUT := "res://.visual_captures/site_resources/"
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 17000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("SITE SCENE did not complete")
		quit(1)
	return false

func _run() -> void:
	var lab := TerrainLab.new()
	root.add_child(lab)
	current_scene = lab
	var controller: Node = lab.site_controller
	controller.save_path = "res://.godot-temp/site_resources_contract/scene.json"
	assert(lab.renderer.get_child_count() == 4, "Resource art replaced terrain layers")
	assert(lab.find_child("ManualHarvest", true, false) != null and lab.find_child("BuildFeature", true, false) != null)
	var data: TerrainData = lab.terrain
	var keys: Array = data.resource_base.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return data.cell_from_index(int(data.resource_base[a].cell)).distance_squared_to(lab.npc.terrain_cell) < data.cell_from_index(int(data.resource_base[b].cell)).distance_squared_to(lab.npc.terrain_cell))
	var source := ""
	for key: String in keys:
		if int(data.resource_base[key].kind) != Env.Kind.FOOD:
			continue
		for cell: Vector2i in Env.work_cells(data, key):
			var path := data.path_between(lab.npc.terrain_cell, cell, controller._worker_blocked)
			if not path.is_empty() and path.size() <= 18:
				source = key
				break
		if not source.is_empty():
			break
	assert(not source.is_empty(), "No accessible nearby forage")
	var source_cell := data.cell_from_index(int(data.resource_base[source].cell))
	controller.select_cell(source_cell)
	# Exercise the same map-drag command the panel exposes.
	controller.modes.select(2)
	controller.kinds.select(Env.Kind.FOOD + 1)
	lab.camera.force_update_scroll()
	var screen := lab.get_viewport().get_canvas_transform() * ((Vector2(source_cell) + Vector2.ONE * 0.5) * 64)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = screen
	press.pressed = true
	assert(controller.handle_input(press))
	press.pressed = false
	assert(controller.handle_input(press))
	assert(data.site.zones.size() == 1 and bool(data.site.worker_enabled))
	var original := int(Env.resource(data, source).remaining)
	var initial_cell := lab.npc.terrain_cell
	var observed_travel := false
	var observed_cargo := false
	var delivered := false
	var store_before := int(data.site.inventory.get("wild_food", 0))
	while Time.get_ticks_msec() < deadline - 1500:
		await process_frame
		observed_travel = observed_travel or lab.npc.terrain_cell != initial_cell
		if lab.npc.is_moving():
			assert(controller.reserves_cell(lab.npc.movement_from_cell) and controller.reserves_cell(lab.npc.terrain_cell), "Moving worker lost its source or destination reservation")
		observed_cargo = observed_cargo or int(data.site.worker.cargo.get("wild_food", 0)) > 0
		if int(data.site.inventory.get("wild_food", 0)) > store_before:
			delivered = true
			break
	assert(observed_travel and observed_cargo and delivered, "Worker did not walk, harvest and deliver: " + str(data.site.worker))
	controller.release_worker()
	assert(int(Env.resource(data, source).remaining) == original - 3)
	assert(int(data.site.inventory.wild_food) == store_before + 3)
	var time_before := Runtime.now(data)
	lab._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert(bool(data.site.paused), "Leaving the application did not pause the Site")
	controller.tick(10.0)
	assert(Runtime.now(data) == time_before)
	assert(not lab.character.step(Vector2i.UP))
	controller.toggle_pause()
	# A remote swing is not combat; nearby legal contact activates the clock.
	lab.character.reset_combat()
	lab.npc.reset_combat()
	var actor_from := lab.character.terrain_cell
	var actor_to := lab.npc.terrain_cell
	assert(lab.character.can_hit(lab.npc, 1), "Delivery should end adjacent to camp")
	assert(lab.character.start_attack(lab.npc))
	assert(float(data.site.combat_left) > 10)
	assert(not Store.save(data, controller.save_path).ok)
	lab.character.reset_combat()
	lab.npc.reset_combat()
	data.site.combat_left = 0.0
	controller.save_current()
	var checksum := FileAccess.get_sha256(controller.save_path)
	controller.load_current()
	assert(int(lab.terrain.site.inventory.wild_food) == store_before + 3)
	assert(lab.character.terrain_cell == actor_from and lab.npc.terrain_cell == actor_to)
	assert(FileAccess.get_sha256(controller.save_path) == checksum)
	var bad_file := FileAccess.open(controller.save_path + ".corrupt", FileAccess.WRITE)
	bad_file.store_string("broken save")
	bad_file.close()
	var previous_data: TerrainData = lab.terrain
	controller._load_path(controller.save_path + ".corrupt")
	assert(lab.terrain == previous_data and controller._auto_save_blocked)
	controller._save_elapsed = 40.0
	controller.tick(0.01)
	assert(FileAccess.get_sha256(controller.save_path) == checksum, "Failed load allowed automatic overwrite")
	print("SITE SCENE PASS: panel drag, real worker travel/carry/delivery, pause, actual combat hook, save/load positions")
	lab.queue_free()
	await process_frame
	quit(0)
