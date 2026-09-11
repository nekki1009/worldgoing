extends SceneTree

const OUTPUT := "res://.visual_captures/terrain_lab/default_edge_v5/"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("GPU rendering required; not a visual PASS")
		quit(1)
		return
	DisplayServer.window_set_size(Vector2i(2560, 1440))
	var lab := (load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene).instantiate() as TerrainLab
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.army.set_process(false)
	assert(lab.terrain.preset == TerrainPreset.Kind.TERRACED_HIGHLAND and lab.terrain.seed_value == 12345)
	lab.deploy_army()
	assert(lab.army.issue_command(TerrainArmy.Command.MOVE_TO_EDGE))
	var army := lab.army
	var previous := army.cells.duplicate()
	var crossed := {}
	var captures := {}
	var gates: Array = preload("res://scripts/tests/terrain_army_default_edge_test.gd").EXPECTED_GATES
	for frame: int in range(10800):
		army.advance_frame(1.0 / 60.0)
		for index: int in range(1, 100):
			if previous[index] == gates[4][0] and army.cells[index] == gates[4][1]:
				crossed[index] = true
		previous = army.cells.duplicate()
		var label := ""
		if frame == 59:
			label = "01_approach"
		elif frame == 2399:
			label = "02_captain_far_tail_upstream"
		elif crossed.size() == 99 and army.passage_summary().completed == 99 and not captures.has("03_last_exit_clear"):
			label = "03_last_exit_clear"
		elif not army.passage_active() and army.is_formation_complete() and not captures.has("04_assembled"):
			label = "04_assembled"
		if not label.is_empty():
			captures[label] = true
			lab._update_info()
			if label == "01_approach":
				lab.camera.zoom = Vector2.ONE * 1.1
				lab.camera.position = Vector2(62, 51) * 64 - Vector2(220, 0)
			elif label == "02_captain_far_tail_upstream":
				lab.fit_map()
			else:
				lab.camera.zoom = Vector2.ONE * 0.8
				lab.camera.position = Vector2(87, 74) * 64 - Vector2(220, 0)
			lab.camera.force_update_scroll()
			await process_frame
			var scroll := lab.army_info.get_parent().get_parent().get_parent() as ScrollContainer
			scroll.ensure_control_visible(lab.army_info)
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
			assert(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + label + ".png")) == OK)
			print("CAPTURE %s input=%.3f goal=%s summary=%s assembled=%d" % [label, float(frame + 1) / 60.0, army.desired_cells[0], army.passage_summary(), army.formation_count()])
		elif frame % 60 == 0:
			await process_frame
	assert(captures.size() == 4, "missing visual stages")
	print("DEFAULT EDGE GPU CAPTURES READY: inspect all four images; accelerated replay, not a performance benchmark")
	lab.queue_free()
	await process_frame
	quit(0)
