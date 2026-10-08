extends "res://scripts/tests/site_resource_visual_test.gd"
## Candidate E14 evidence: original PackedScene, immutable generated base and real UI.
## Saving readable PNGs proves capture only. A person must inspect the four images.

const ORIGINAL_SCENE = preload("res://scenes/terrain_lab/TerrainLab.tscn")
const ECO_OUTPUT := "res://.visual_captures/site_ecology_gpu/"
const WINDOW_SIZE := Vector2i(1600, 1000)
const SHOTS := ["01_exhausted_countdown", "02_sustainable_rest", "03_protected_restore_7", "04_blocked_restore_59"]
var _proof := {"scope": "ORIGINAL_SITE_GPU_CAPTURE_ONLY", "visual_review": "REQUIRED", "screenshots": [], "ui_query_checks": [], "actions": []}
var _immutable_base := ""

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 120000
	_run.call_deferred()

func _check_deadline() -> void:
	assert(Time.get_ticks_msec() <= deadline, "SITE_ECOLOGY_GPU_INTERNAL_DEADLINE")

func _base_hash(data: TerrainData) -> String:
	return _digest(var_to_bytes([data.resource_base, data.parameters, data.surface_types, data.height_levels,
		data.ramp_edges, data.flags, data.water_kind, data.water_body, data.fertility, data.moisture,
		data.drainage, data.foundation, data.groundwater]))

func _digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	assert(context.start(HashingContext.HASH_SHA256) == OK)
	assert(context.update(bytes) == OK)
	return context.finish().hex_encode()

func _freeze(lab: TerrainLab) -> PackedByteArray:
	var data: TerrainData = lab.terrain
	return var_to_bytes([data.site, data.resource_base, data.parameters, data.surface_types, data.height_levels,
		data.ramp_edges, data.flags, data.water_kind, data.water_body, data.fertility, data.moisture,
		data.drainage, data.foundation, data.groundwater, data.static_blocked, data.feature_at,
		data.resources_at, data.walk_height_levels, data.walk_ramp_edges, data.facility_cells,
		data.bridge_walkable, data.environment_revision, data.navigation_revision,
		lab.character.capture_state(), lab.npc.capture_state()])

func _quiet_actors(lab: TerrainLab) -> void:
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.set_process(false)
		if actor.editor != null:
			actor.editor.set_process(false)
			actor.editor.animation_player.pause()
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)

func _fixture() -> Dictionary:
	# Never rewrite capacity, soil, water or generation to make a screenshot pass.
	for preset: int in [TerrainPreset.Kind.PLAINS, TerrainPreset.Kind.ISLAND]:
		for seed_value: int in [12345, 71, 581, 91, 7, 23]:
			_check_deadline()
			var data := TerrainGenerator.generate(preset, seed_value, {"size": Vector2i(64, 64)})
			Env.initialize(data, "ecology-gpu-original-generated")
			assert(Runtime.initialize_item_storage(data.site).ok)
			var fish_key := ""
			var timber_keys: Array[String] = []
			var plant_keys: Array[String] = []
			var keys := data.resource_base.keys()
			keys.sort()
			for key: String in keys:
				var resource := Env.resource(data, key)
				if Env.work_cells(data, key).is_empty(): continue
				if int(resource.kind) == Env.Kind.FISH and int(Env.ecology_info(data, key).capacity) == 20: fish_key = key
				elif int(resource.kind) == Env.Kind.TIMBER: timber_keys.append(key)
				elif int(resource.kind) in [Env.Kind.FOOD, Env.Kind.HERB]: plant_keys.append(key)
			if fish_key.is_empty(): continue
			for timber_key: String in timber_keys:
				var timber_cell := data.cell_from_index(int(data.resource_base[timber_key].cell))
				if timber_cell.x < 6 or timber_cell.y < 6 or timber_cell.x > 57 or timber_cell.y > 57: continue
				for plant_key: String in plant_keys:
					var plant_cell := data.cell_from_index(int(data.resource_base[plant_key].cell))
					if plant_cell == timber_cell or plant_cell.distance_squared_to(timber_cell) > 16: continue
					var plant_work: Array[Vector2i] = Env.work_cells(data, plant_key)
					plant_work = plant_work.filter(func(cell: Vector2i) -> bool: return cell != timber_cell)
					if not plant_work.is_empty():
						return {"data": data, "fish": fish_key, "timber": timber_key, "plant": plant_key, "plant_work": plant_work[0]}
	assert(false, "Original generated seeds lack Fish K20 and adjacent legal Timber/plant sources")
	return {}

func _deposit(lab: TerrainLab) -> void:
	if lab.terrain.site.manual.cargo.is_empty(): return
	var depot := lab.terrain.cell_from_index(int(lab.terrain.site.depot_cell))
	assert(lab.character.place(depot, true), "Original player must reach the original depot cell")
	assert(Runtime.deposit(lab.terrain, lab.terrain.site.manual.cargo, lab.character.terrain_cell).ok)
	assert(lab.terrain.site.manual.cargo.is_empty())

func _work_cell(lab: TerrainLab, key: String, avoid: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	for cell: Vector2i in Env.work_cells(lab.terrain, key):
		if cell != avoid and not lab.npc.occupies_cell(cell) and lab.character.can_enter_cell(cell): return cell
	assert(false, "Original actor lacks a legal original resource work cell")
	return Vector2i(-1, -1)

func _deplete(lab: TerrainLab, key: String, clear_after: bool) -> void:
	var data: TerrainData = lab.terrain
	for _batch in range(64):
		_check_deadline()
		var resource := Env.resource(data, key)
		if int(resource.remaining) <= 0: break
		if Runtime.inventory_size(data.site.manual.cargo) + mini(int(resource.remaining), int(Env.BATCH[int(resource.kind)])) > Runtime.CARRY_CAPACITY: _deposit(lab)
		assert(lab.character.place(_work_cell(lab, key), true))
		assert(Runtime.harvest(data, key, lab.character.terrain_cell, data.site.manual.cargo).ok)
	assert(int(Env.resource(data, key).remaining) == 0, "Bounded real harvest did not exhaust original source")
	if clear_after:
		assert(lab.character.place(_work_cell(lab, key), true))
		assert(Runtime.harvest(data, key, lab.character.terrain_cell, data.site.manual.cargo, "clear").ok)
		assert(bool(Env.resource(data, key).cleared) and int(Env.resource(data, key).next_recovery) == -1)
	_deposit(lab)
	assert(_base_hash(data) == _immutable_base, "Real resource actions altered immutable generation")
	_proof.actions.append({"action": "real_harvest_then_clear" if clear_after else "real_harvest_to_zero", "key": key,
		"capacity": int(data.resource_base[key].capacity), "remaining": int(Env.resource(data, key).remaining), "minute": Runtime.now(data)})

func _present(lab: TerrainLab, key: String) -> Dictionary:
	_quiet_actors(lab)
	var before := _freeze(lab)
	var controller: SiteController = lab.site_controller
	var resource := Env.resource(lab.terrain, key)
	controller.view.selection = Rect2i()
	controller.view.view_mode = 1
	controller.view.resource_filter = -1
	controller.kinds.select(int(resource.kind) + 1)
	controller.select_cell(lab.terrain.cell_from_index(int(resource.cell)))
	assert(controller.source_key == key and controller.view.selected_resource == key)
	lab.camera.zoom = Vector2.ONE * 1.4
	lab.camera.position = (Vector2(controller.selected) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS + Vector2(250.0 / 1.4, -35.0)
	lab.camera.force_update_scroll()
	controller.view.animate(1.0)
	controller.update_ui()
	controller.view.refresh()
	var description := controller._ecology_description(key)
	assert(controller.details.text.contains(description))
	assert(_freeze(lab) == before, "Original selection, view refresh or ecology UI query changed gameplay state")
	var summary := {"source": key, "description": description, "details": controller.details.text,
		"work_status": controller.ecology_status.text, "source_label": controller.view._resource_label(key, Env.resource(lab.terrain, key)),
		"environment_revision": lab.terrain.environment_revision, "navigation_revision": lab.terrain.navigation_revision, "state_sha256": _digest(before)}
	_proof.ui_query_checks.append(summary)
	return summary

func _capture_ecology(lab: TerrainLab, name: String, presented: Dictionary) -> void:
	_check_deadline()
	var before := _freeze(lab)
	await process_frame
	var work_window: Window = lab.site_controller.formal_windows.work
	var scroll: ScrollContainer = null
	for node: Node in work_window.find_children("*", "ScrollContainer", true, false):
		scroll = node as ScrollContainer
		break
	assert(scroll != null)
	scroll.ensure_control_visible(lab.site_controller.manual_restore_button)
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	assert(picture.get_size() == WINDOW_SIZE, "Original viewport capture size does not match the named fixture")
	var path := ECO_OUTPUT + name + ".png"
	assert(picture.save_png(path) == OK)
	var reloaded := Image.new()
	assert(reloaded.load(path) == OK and reloaded.get_size() == WINDOW_SIZE, "Saved PNG did not reload at the original viewport size")
	var hash := FileAccess.get_sha256(path)
	assert(hash.length() == 64 and _freeze(lab) == before, "UI rendering, animation or PNG capture mutated original gameplay state")
	assert(_base_hash(lab.terrain) == _immutable_base)
	var row := presented.duplicate(true)
	row.merge({"name": name, "path": ProjectSettings.globalize_path(path), "sha256": hash,
		"width": reloaded.get_width(), "height": reloaded.get_height(), "visual_review": "REQUIRED"}, true)
	_proof.screenshots.append(row)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("SITE_ECOLOGY_GPU requires the original GPU display")
		quit(1)
		return
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ECO_OUTPUT)) == OK)
	DisplayServer.window_set_size(WINDOW_SIZE)
	root.gui_embed_subwindows = true
	var fixture := _fixture()
	var data: TerrainData = fixture.data
	_immutable_base = _base_hash(data)
	var lab := ORIGINAL_SCENE.instantiate() as TerrainLab
	assert(lab != null)
	lab.restore_only = true # Original initializer skips default load/save/generation.
	lab.npc = TerrainTestNPC.new() # Existing command-test person, actual cell owner for screenshot 4.
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.bind_terrain(data)
	assert(lab.terrain == data)
	lab.restore_only = false
	lab.visible = true
	lab.get_node("SiteUI").visible = true
	lab.movement_input_enabled = false
	lab.set_process_input(false)
	lab.set_process_unhandled_input(false)
	_quiet_actors(lab)
	var controller: SiteController = lab.site_controller
	controller._auto_save_blocked = true
	controller.release_worker()
	controller.hide_tool_windows()
	var work_window: Window = controller.formal_windows.work
	work_window.position = Vector2i(1048, 112)
	work_window.size = Vector2i(536, 780)
	controller.open_window("work")
	await process_frame
	var timber_key: String = fixture.timber
	var fish_key: String = fixture.fish
	var plant_key: String = fixture.plant
	_proof.merge({"scene": "res://scenes/terrain_lab/TerrainLab.tscn", "preset": data.preset, "seed": data.seed_value,
		"source_keys": {"timber": timber_key, "fish": fish_key, "plant": plant_key}, "immutable_base_sha256": _immutable_base,
		"sources_sha256": {}, "freeze_scope": "Site, immutable base, original terrain/projection arrays, environment/navigation revisions and original actor saved states; preview AnimationPlayer paused",
		"excluded_acceptance": "Pixel appearance without human inspection; FPS, Native/Crowd, Region replay, persistence, release and all16ECO"}, true)
	for path: String in ["res://scripts/tests/site_ecology_gpu_test.gd", "res://scenes/terrain_lab/TerrainLab.tscn",
		"res://scripts/terrain_lab/site_runtime.gd", "res://scripts/terrain_lab/site_environment.gd", "res://scripts/terrain_lab/site_controller.gd",
		"res://scripts/terrain_lab/site_resource_view.gd", "res://scripts/terrain_lab/site_settlement.gd"]:
		_proof.sources_sha256[path] = FileAccess.get_sha256(path)

	_deplete(lab, timber_key, false)
	var shown := _present(lab, timber_key)
	assert(shown.description.contains("現量 0") and shown.description.contains("下次成熟") and shown.source_label.contains("待恢復"))
	await _capture_ecology(lab, SHOTS[0], shown)

	for _batch in range(8):
		assert(lab.character.place(_work_cell(lab, fish_key), true))
		assert(Runtime.harvest(data, fish_key, lab.character.terrain_cell, data.site.manual.cargo).ok)
	var fish := Env.ecology_info(data, fish_key)
	assert(int(fish.capacity) == 20 and int(fish.remaining) == 4 and int(fish.reserve) == 4 and int(fish.resume) == 10 and bool(fish.resting) and int(fish.takeable) == 0)
	shown = _present(lab, fish_key)
	assert(shown.description.contains("留底 4 · 復採 10 · 保育休採") and shown.source_label.contains("休採"))
	await _capture_ecology(lab, SHOTS[1], shown)
	_deposit(lab)
	Runtime.advance(data, 720.0, false, false, controller.reserves_cell)
	fish = Env.ecology_info(data, fish_key)
	assert(int(fish.remaining) == 10 and not bool(fish.resting) and int(fish.takeable) == 6, "Six original Fish recovery events must reach the actual resume threshold")
	var resumed := _present(lab, fish_key)
	assert(resumed.description.contains("留底 4 · 復採 10 · 可採") and not resumed.source_label.contains("休採"))
	_proof.actions.append({"action": "original_runtime_recovery", "elapsed_game_minutes": 720, "source": fish_key,
		"remaining": fish.remaining, "resting": fish.resting, "takeable": fish.takeable, "ui": resumed})

	_deplete(lab, plant_key, true)
	_present(lab, plant_key)
	assert(not controller.ecology_apply_button.disabled)
	controller.ecology_modes.select(1)
	controller.ecology_apply_button.pressed.emit() # Actual formal button + Settlement authority and revision map.
	assert(str(Env.ecology_info(data, plant_key).mode) == "protected")
	var timber_cell := data.cell_from_index(int(data.resource_base[timber_key].cell))
	assert(lab.character.place(_work_cell(lab, plant_key, timber_cell), true))
	_present(lab, plant_key)
	assert(not controller.manual_restore_button.disabled)
	controller.manual_restore_button.pressed.emit() # Actual formal action and original player work owner.
	assert(str(data.site.manual.target) == plant_key and str(data.site.manual.action) == "restore")
	Runtime.advance(data, 7.0, false, true, controller.reserves_cell)
	assert(is_equal_approx(float(data.site.manual.progress), 7.0) and bool(Env.resource(data, plant_key).cleared))
	assert(int(Env.resource(data, plant_key).remaining) == 0 and int(Env.resource(data, plant_key).next_recovery) == -1)
	shown = _present(lab, plant_key)
	assert(shown.description.contains("休養保護") and shown.description.contains("已清地") and shown.description.contains("普通等待不會恢復"))
	assert(shown.source_label.contains("待復育") and shown.source_label.contains("休養保護") and shown.work_status.contains("7.0 / 60"))
	await _capture_ecology(lab, SHOTS[2], shown)

	Runtime.advance(data, 52.0, false, true, controller.reserves_cell)
	assert(is_equal_approx(float(data.site.manual.progress), 59.0) and str(data.site.manual.target) == plant_key)
	assert(bool(Env.resource(data, plant_key).cleared) and int(Env.resource(data, plant_key).next_recovery) == -1)
	assert(data.is_walkable(timber_cell) and lab.character.terrain_cell != timber_cell)
	assert(lab.npc.place(timber_cell, true), "Blocking reason must come from the actual original NPC cell owner")
	assert(controller.reserves_cell(timber_cell))
	shown = _present(lab, timber_key)
	assert(shown.description.contains("恢復受阻：人物、車輛或移動預約正在使用此格"))
	assert(shown.work_status.contains("59.0 / 60"))
	assert(controller.view._resource_label(plant_key, Env.resource(data, plant_key)).contains("待復育"))
	await _capture_ecology(lab, SHOTS[3], shown)
	assert(_proof.screenshots.size() == SHOTS.size() and _base_hash(data) == _immutable_base)
	_proof["elapsed_milliseconds"] = 120000 - maxi(0, deadline - Time.get_ticks_msec())
	_proof["final_state_sha256"] = _digest(_freeze(lab))
	_proof["capture_status"] = "FOUR_READABLE_PNG_FILES_WRITTEN"
	var receipt := FileAccess.open(ECO_OUTPUT + "capture_receipt.json", FileAccess.WRITE)
	assert(receipt != null)
	receipt.store_string(JSON.stringify(_proof, "\t", true, true))
	receipt.close()
	print("SITE_ECOLOGY_GPU_CAPTURE_READY screenshots=4 original_scene=true immutable_base=true ui_queries_read_only=true visual_review=REQUIRED; no pixel, FPS, Native/Crowd or release acceptance")
	lab.queue_free()
	await process_frame
	quit(0)
