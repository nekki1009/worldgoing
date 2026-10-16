extends "res://scripts/tests/site_workflow_test.gd"
## Reuse the existing controlled work/build fixture and real production owner.

func near(actual: float, expected: float, label: String = "") -> void:
	assert(absf(actual - expected) < 0.000001, "%s: %.12f != %.12f" % [label, actual, expected])

func _run() -> void:
	var lab := TerrainLab.new()
	lab.npc = TerrainTestNPC.new() # The lab no longer creates a default worker presenter.
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var data := _fixture()
	lab.bind_terrain(data)
	lab.npc.faction_id = lab.character.faction_id
	var actor := lab.character
	var npc := lab.npc
	var cells: Array[int] = _footprint(data, "house", Vector2i(22, 20))
	var building := Runtime.request_build(data, "house", cells)
	assert(building.ok)
	var feature: Dictionary = data.site.features[str(building.feature)]
	Runtime.assign_task(data, {"ok": true, "target": "feature:" + str(building.feature), "action": "construct", "cell": feature.entrance, "message": ""})
	data.site.worker.mode = "work"
	data.site.worker.cell = feature.entrance
	npc.place(data.cell_from_index(feature.entrance), true)
	actor.place(Vector2i(18, 20), true)
	lab.site_controller.enable_worker()
	npc.fatigue = 70
	# Actual controller -> Runtime -> person, then shared body/fatigue boundary.
	lab._process(1.0)
	near(float(feature.progress), PersonFatigue.work_seconds(70, 60) / 60.0, "tired construction below work-rest threshold")
	near(npc.fatigue, 70.0 + 1.0 / 6.0)
	near(npc.fatigue_rest, 0, "cannot work and recover in same frame")
	data.site.inventory.tools = 0
	var before := float(feature.progress)
	var tired := npc.fatigue
	lab._process(1.0)
	near(float(feature.progress), before, "no tools, no productive work")
	near(npc.fatigue, tired, "waiting for tools is duty, not a rest break")
	near(npc.fatigue_rest, 0)
	data.site.inventory.tools = 100
	npc.fatigue = 50
	Runtime.advance(data, 1, true, false, func(_cell: Vector2i) -> bool: return true, lab.fatigue_work_minutes)
	near(npc.fatigue, 50, "occupied work plot has no effort")
	near(float(feature.progress), before)
	# Production pays the original inputs once, scales progress, keeps outputs.
	var kiln := _build(data, "kiln", Vector2i(25, 22))
	var workshop: Dictionary = data.site.features[kiln]
	Runtime.assign_task(data, {"ok": true, "target": "feature:" + kiln, "action": "operate", "cell": workshop.entrance, "message": ""})
	data.site.worker.cell = workshop.entrance
	data.site.worker.mode = "work"
	var clay := int(data.site.inventory.clay)
	npc.fatigue = 70
	Runtime.advance(data, 1, true, false, Callable(), lab.fatigue_work_minutes)
	near(float(workshop.production), PersonFatigue.work_seconds(70, 60) / 60.0)
	assert(int(data.site.inventory.clay) == clay - 3)
	Runtime.advance(data, 1, true, false, Callable(), lab.fatigue_work_minutes)
	assert(int(data.site.inventory.clay) == clay - 3, "Fatigue must not repay batch inputs")
	workshop.production = Runtime.FEATURES.kiln.cycle
	data.site.worker.cargo = {"stone": Runtime.CARRY_CAPACITY}
	npc.fatigue = 50
	Runtime.advance(data, 1, true, false, Callable(), lab.fatigue_work_minutes)
	near(npc.fatigue, 50, "finished batch awaiting cargo space is not effort")
	data.site.worker.cargo.clear()
	Runtime.advance(data, 1, true, false, Callable(), lab.fatigue_work_minutes)
	assert(data.site.worker.cargo == Runtime.FEATURES.kiln.output)
	near(npc.fatigue, 50)
	Runtime.assign_task(data, {"ok": true, "target": "feature:" + kiln, "action": "operate", "cell": workshop.entrance, "message": ""})
	data.site.worker.mode = "work"
	data.site.inventory.clay = 0
	Runtime.advance(data, 1, true, false, Callable(), lab.fatigue_work_minutes)
	near(npc.fatigue, 50, "missing production input")
	var farm: String = _build(data, "farm", Vector2i(22, 27))
	var field: Dictionary = data.site.features[farm]
	Runtime.assign_task(data, _operate_task(data, farm))
	data.site.worker.cell = data.site.worker.work_cell
	data.site.worker.mode = "work"
	data.site.water_status[farm] = {"supplied": 0.0}
	Runtime.advance(data, 0.1, true, false, Callable(), lab.fatigue_work_minutes)
	near(npc.fatigue, 50, "missing irrigation water")
	near(float(field.production), 0)
	# Resource harvest previews use the very same legality checks as committing.
	data.site.worker.target = ""
	data.site.worker.cargo.clear()
	data.site.manual.cargo.clear()
	var source := ""
	var work_cell := Vector2i.ZERO
	for key: String in data.resource_base:
		var candidate := Env.resource(data, key)
		if candidate.kind != Env.Kind.TIMBER or candidate.cleared or candidate.remaining <= 0:
			continue
		var available := Env.work_cells(data, key)
		if not available.is_empty():
			source = key
			work_cell = available[0]
			break
	assert(not source.is_empty())
	Env.change(data, source, {"discovered": true})
	var manual_started: Dictionary = Runtime.begin_manual(data, source, work_cell)
	assert(manual_started.ok)
	actor.fatigue = 100
	Runtime.advance(data, 1, false, true, Callable(), lab.fatigue_work_minutes)
	near(float(data.site.manual.progress), 1.0 / 1.3, "manual resource work")
	near(actor.fatigue, 100)
	Runtime.mark_combat(data, 0.0) # Existing interruption clears work, not fatigue.
	near(actor.fatigue, 100)
	Runtime.assign_task(data, {"ok": true, "target": source, "action": "harvest", "cell": data.index(work_cell), "message": ""})
	data.site.worker.cell = data.index(work_cell)
	data.site.worker.mode = "work"
	npc.fatigue = 70
	Runtime.advance(data, 1, true, false, Callable(), lab.fatigue_work_minutes)
	near(float(data.site.worker.progress), PersonFatigue.work_seconds(70, 60) / 60.0, "same worker resource work below rest threshold")
	data.site.inventory.tools = 0
	npc.fatigue = 50
	Runtime.advance(data, 1, true, false, Callable(), lab.fatigue_work_minutes)
	near(npc.fatigue, 50, "missing gathering tools")
	data.site.inventory.tools = 100
	data.site.worker.target = ""
	var manual_started_2: Dictionary = Runtime.begin_manual(data, source, work_cell)
	assert(manual_started_2.ok)
	actor.fatigue = 50
	data.site.manual.cargo = {"stone": Runtime.CARRY_CAPACITY}
	Runtime.advance(data, 1, false, true, Callable(), lab.fatigue_work_minutes)
	near(actor.fatigue, 50, "full manual cargo")
	# Root pause blocks both work output and person fatigue.
	var frozen := npc.fatigue
	data.site.paused = true
	lab._process(1)
	near(npc.fatigue, frozen)
	data.site.paused = false
	paused = true
	var minute_before := Runtime.now(data)
	lab._process(1)
	near(npc.fatigue, frozen)
	near(Runtime.now(data), minute_before, "tree pause also freezes Site clock/work")
	paused = false
	lab.site_controller.update_ui()
	assert("疲勞" in lab.site_controller.worker_label.text and "疲勞" in lab.site_controller.player_status_label.text)
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1440, 900)
		var output := "res://.visual_captures/site_work_fatigue"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
		lab.site_controller.open_window("work")
		var scroll: ScrollContainer = lab.site_controller.formal_windows.work.get_child(0).get_child(0) as ScrollContainer
		assert(scroll != null)
		await process_frame
		scroll.ensure_control_visible(lab.site_controller.worker_label)
		await process_frame
		await RenderingServer.frame_post_draw
		var worker_image_saved: Error = root.get_texture().get_image().save_png(output + "/worker.png")
		assert(worker_image_saved == OK)
		scroll.scroll_vertical = 0
		await process_frame
		await RenderingServer.frame_post_draw
		var player_image_saved: Error = root.get_texture().get_image().save_png(output + "/player.png")
		assert(player_image_saved == OK)
	lab.queue_free()
	await process_frame
	print("SITE WORK FATIGUE PASS: real controller construction/rest, manual/NPC gathering, productive workshop time/input/output, tools/occupancy/cargo/input waits, pause and visible Site labels")
	quit(0)
