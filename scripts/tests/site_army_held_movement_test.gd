extends SceneTree
## Real reserved steps and row save/restore, not a new movement or run policy.

const OUTPUT := "res://.visual_captures/site_army_held_movement"
var scene: Node2D
var army: TerrainArmy
var camera: Camera2D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "held-movement-fixture")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	scene = Node2D.new()
	root.add_child(scene)
	current_scene = scene
	army = TerrainArmy.new()
	scene.add_child(army)
	army.set_process(false)
	army.initialize_visual()
	var selected: Array[Vector2i] = []
	for index in range(100):
		selected.append(Vector2i(10 + index % 10, 10 + floori(float(index) / 10)))
	assert(army.deploy_at(data, null, null, selected) and army.enable_combat(false))
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280, 800)
		RenderingServer.set_default_clear_color(Color("293039"))
		camera = Camera2D.new()
		scene.add_child(camera)
		camera.zoom = Vector2.ONE * 4.0
		assert(army.visual_mode() == "baked_atlas" and army.active_3d_source_count() == 1)
		assert(army._captain_editor._body_index == 1, "Keep the original live female captain")
	for pose: String in ["walk", "run"]:
		for index in [0, 1]:
			assert(army._reserve_combat_step(index, army.cells[index] + Vector2i.UP))
			army.combat_units[index].fatigue = 80.0
			if pose == "run":
				# Exercise the already-valid saved run duration; do not add an AI order.
				army.move_duration[index] = TerrainArmy.RUN_DURATION
		var duration := float(army.move_duration[0])
		army.prepare_combat(duration * 0.5)
		army.settle_combat_command()
		var frames: Array[Dictionary] = []
		var grounds: Array[Vector2] = []
		for index in [0, 1]:
			assert(army.moving_to[index] != TerrainArmy.INVALID_CELL and is_equal_approx(army.move_progress[index], 0.5))
			assert(army.combat_units[index].pose == "walk" and army.combat_frame(index).clip == "combat_" + pose)
			assert(army.combat_offset(index) == Vector2.ZERO)
			frames.append(army.combat_frame(index))
			grounds.append(army.combat_ground(index))
		var before_pause := army.capture_combat_state()
		var saved := JSON.parse_string(JSON.stringify(before_pause)) as Dictionary
		assert(TerrainArmy.valid_combat_state(saved, data))
		paused = true
		army.prepare_combat(5.0)
		assert(army.capture_combat_state() == before_pause, "Pause must not consume the remaining step")
		paused = false
		army.restore_combat_state(saved, data, null, null)
		for index in [0, 1]:
			assert(army.combat_frame(index) == frames[index] and army.combat_ground(index).distance_to(grounds[index]) < 0.0001)
			assert(is_equal_approx(army.move_duration[index], duration) and army.combat_units[index].fatigue == 80.0)
		await capture(pose + "_restored_mid", pose)
		army.prepare_combat(duration * 0.5 + 0.000001)
		for index in [0, 1]:
			assert(army.cells[index] == selected[index] + Vector2i.UP * (1 if pose == "walk" else 2))
			assert(army.moving_to[index] == TerrainArmy.INVALID_CELL and army.combat_frame(index).clip == "combat_idle")
	await capture("held_idle_after_move", "idle")
	# Leaving combat still uses the untouched original sheathed locomotion clips.
	army.clear()
	assert(army.deploy_at(data, null, null, selected))
	army.advance_frame(0.0)
	if DisplayServer.get_name() != "headless":
		assert(not army._captain_editor.combat_ready and army.captain_animation_id() == &"idle")
	army.clear()
	scene.queue_free()
	await process_frame
	print("SITE ARMY HELD MOVEMENT PASS: actual reserved walk, existing saved run duration, 2 moving rows, pause/JSON restore/arrival, held captain and baked soldier; no new run order or continuous-time parity claim")
	quit(0)

func capture(label: String, pose: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	army.advance_frame(0.0)
	assert(army.captain_animation_id() == StringName(pose) and army._captain_editor.combat_ready)
	for index in [0, 1]:
		var anchor: Vector2 = army._captain_anchor if index == 0 else army._soldier_sprite_anchors[index]
		assert((army._sprites[index].position + anchor).distance_to(army.combat_ground(index) + army.combat_offset(index)) < 0.0001)
		assert(army.combat_shapes(index, "body").size() == 10 and not army.combat_shapes(index, "weapon").is_empty() and not army.combat_shapes(index, "shield").is_empty())
	for index in range(2, army._sprites.size()):
		army._sprites[index].hide() # Close-up only; all 100 simulation rows remain.
	camera.position = army.combat_ground(0).lerp(army.combat_ground(1), 0.5) + Vector2(0, -35)
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	assert(root.get_texture().get_image().save_png(OUTPUT + "/" + label + ".png") == OK)
