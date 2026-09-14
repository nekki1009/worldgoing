extends "res://scripts/tests/site_workflow_test.gd"

func _run() -> void:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var data := _fixture()
	lab.bind_terrain(data)
	var npc := lab.npc
	npc.faction_id = lab.character.faction_id
	var built := Runtime.request_build(data, "house", [data.index(Vector2i(22, 20))])
	assert(built.ok)
	var feature: Dictionary = data.site.features[str(built.feature)]
	var task := "feature:" + str(built.feature)
	Runtime.assign_task(data, {"ok": true, "target": task, "action": "construct", "cell": feature.entrance, "message": ""})
	data.site.worker.mode = "work"
	data.site.worker.cell = feature.entrance
	data.site.worker.cargo.wood = 2
	assert(npc.place(data.cell_from_index(feature.entrance), true))
	assert(lab.character.place(Vector2i(18, 20), true))
	npc.fatigue = 79.99
	lab._process(1.0)
	var checkpoint := float(feature.progress)
	assert(checkpoint > 0.0 and checkpoint < 0.1 and npc.work_resting, "Only effort up to 80 may be committed")
	assert(npc.fatigue <= 80.0 and npc.fatigue > 50.0)
	assert(data.site.worker.target == task and data.site.worker.cargo == {"wood": 2}, "Rest retains original work and cargo")
	# The rest latch survives below 80 and cannot be bypassed by pressing Start.
	npc.fatigue = 70.0
	lab.site_controller.enable_worker()
	lab._process(0.1)
	assert(npc.work_resting and feature.progress == checkpoint and data.site.worker.target == task)
	lab.site_controller._capture_positions()
	var path := "res://.godot-temp/site_resources_contract/work_rest.json"
	assert(Store.save(data, path).ok)
	var loaded := Store.load_site(path)
	assert(loaded.ok)
	lab.bind_terrain(loaded.data)
	data = lab.terrain
	feature = data.site.features[str(built.feature)]
	# JSON's decimal round-trip can differ by one float64 ULP (~7e-18 here).
	# Preserve exact post-load no-progress checks against the restored baseline.
	assert(npc.work_resting and absf(float(feature.progress) - checkpoint) < 0.000000000000001 and data.site.worker.cargo == {"wood": 2})
	checkpoint = float(feature.progress)
	var snapshot := npc.capture_state()
	var malformed := snapshot.duplicate(true)
	malformed.work_resting = "true"
	assert(not TerrainTestCharacter.valid_state(malformed, data))
	var legacy := snapshot.duplicate(true)
	legacy.erase("work_resting")
	assert(TerrainTestCharacter.valid_state(legacy, data))
	npc.restore_state(legacy)
	assert(not npc.work_resting)
	npc.restore_state(snapshot)
	# Enemy presence interrupts rest; no working while waiting for safety.
	lab.character.faction_id = npc.faction_id + 1
	var fatigue := npc.fatigue
	lab._process(1.0)
	assert(npc.fatigue == fatigue and npc.fatigue_rest == 0.0 and feature.progress == checkpoint)
	lab.character.faction_id = npc.faction_id
	npc.fatigue = 50.1
	npc.fatigue_rest = PersonFatigue.REST_DELAY
	lab._process(0.1)
	assert(npc.work_resting and npc.fatigue > 50.0 and feature.progress == checkpoint)
	lab._advance_fatigue(60.0)
	assert(npc.fatigue < 50.0)
	lab._process(0.1)
	assert(not npc.work_resting and float(feature.progress) > checkpoint and data.site.worker.target == task)
	# Player autonomy: the same efficiency formula still permits work at 100.
	lab.character.fatigue = 100.0
	assert(is_equal_approx(lab.fatigue_work_minutes(true, 1.0), 1.0 / 1.3))
	assert(not lab.character.work_resting)
	lab._fatigue_work_seconds.clear()
	npc.fatigue = 85.0
	npc.work_resting = true
	var state_before := npc.capture_state()
	paused = true
	lab._process(1.0)
	paused = false
	assert(npc.capture_state() == state_before)
	lab.site_controller.release_worker()
	lab._process(0.1)
	assert(not data.site.worker_enabled and data.site.worker.target == "" and data.site.worker.cargo == {"wood": 2})
	lab.site_controller.update_ui()
	assert("輪休" in lab.site_controller.worker_label.text and "50" in lab.site_controller.worker_label.text)
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1440, 900)
		var scroll := lab.site_controller.panel.get_child(0) as ScrollContainer
		await process_frame
		scroll.ensure_control_visible(lab.site_controller.worker_label)
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.visual_captures/site_work_rest"))
		assert(root.get_texture().get_image().save_png("res://.visual_captures/site_work_rest/worker.png") == OK)
	lab.queue_free()
	await process_frame
	print("SITE WORK REST PASS: real controller/production, 80 checkpoint and 50 resume, source task/cargo/save retained, invalid/legacy flag, threat and pause, player autonomy; existing one-worker slice")
	quit(0)
