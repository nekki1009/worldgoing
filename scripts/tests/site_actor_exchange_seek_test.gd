extends "res://scripts/tests/site_actor_cloth_batch_test.gd"
## The real actor/editor, fixed-clock A/B against this round's frozen play_pose.

func _initialize() -> void:
	output_root = "res://output/site_army_stable30_native_20260915/actor_seek"
	super._initialize()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_usec() - started_us > 55000000:
		_fail("Actor exchange seek exceeded 55 seconds")
	return false

func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	var script := load("res://scripts/terrain_lab/terrain_test_character.gd") as GDScript
	var matcher := RegEx.new()
	assert(matcher.compile("(?ms)^func play_pose\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
	var old := matcher.search(FileAccess.get_file_as_string("res://output/site_army_stable30_native_20260915/baseline/terrain_test_character.gd.baseline")).get_string()
	script.source_code = script.source_code.replace("func play_pose(clip: StringName) -> void:\n", "var seek_reference := false\nfunc play_pose(clip: StringName) -> void:\n\tif seek_reference:\n\t\t_reference_play_pose(clip)\n\t\treturn\n") + "\n" + old.replace("func play_pose(", "func _reference_play_pose(")
	assert(script.reload(true) == OK)
	actor = TerrainTestCharacter.new()
	actor.visual_state.body_index = body_index
	actor.exchange_enabled = true
	actor.combat_driven_by_lab = true
	root.add_child(actor)
	actor.initialize_visual()
	actor.position = Vector2(400, 650)
	actor.set_process(false)
	actor.editor.set_process(false)
	actor.editor.set_playing(false)
	actor.editor.combat_ready = true
	actor.editor.visual_state.combat_ready = true
	actor.combat_ready = true
	skeleton = actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	for node: Node in actor.editor.model_root.find_children("*", "MeshInstance3D", true, false): model_meshes.append(node)
	var initial := _cosmetic_snapshot()
	for clip: StringName in [&"attack_sword", &"hit", &"hit_back", &"knockback", &"guard", &"down", &"get_up", &"rescue", &"idle", &"walk", &"attack_bow", &"reload_bow", &"attack_crossbow", &"ride_slash"]:
		assert(actor.editor.select_part_by_id(&"weapon", &"bow_01" if clip in [&"attack_bow", &"reload_bow"] else (&"crossbow_01" if clip == &"attack_crossbow" else &"longsword_01")))
		actor.editor.set_mount_enabled(clip == &"ride_slash")
		# Both replays must start from identical cloth/mount local transforms.
		# Restoring just the clip leaves the previous global-to-local roundoff.
		var transforms := {}
		for node: Node in actor.editor.preview_pivot.find_children("*", "Node3D", true, false):
			transforms[node] = (node as Node3D).transform
		var expected: Array = []
		for reference in [true, false]:
			actor.set("seek_reference", reference)
			actor.set_process(false)
			for node: Node3D in transforms: node.transform = transforms[node]
			actor._exchange_visual_active = false
			actor.play_pose(&"idle")
			actor.visual_state.animation_time = .17
			actor._process(0.0)
			for mesh: MeshInstance3D in model_meshes:
				var values: Array = initial.morphs.get(str(actor.editor.model_root.get_path_to(mesh)), [])
				for i in range(values.size()): mesh.set_blend_shape_value(i, float(values[i]))
			actor.set_process(true) # Exercise production deferral, not manual fallback.
			actor._start_exchange_visual(clip)
			var step := 0
			for delta: float in [0.0, 1.0 / 30.0, .09, .34]:
				actor._exchange_visual_left = maxf(0.0, actor._exchange_visual_left - delta)
				actor._advance_combat_pose(delta)
				actor._process(0.0)
				await process_frame
				await RenderingServer.frame_post_draw
				var picture := actor.editor.preview_viewport.get_texture().get_image()
				assert(picture.get_used_rect().has_area())
				var state := [_collision_snapshot(), _cosmetic_snapshot(), _pixel_hash(picture)]
				if reference: expected.append(state)
				else:
					if state != expected[step]:
						report.mismatch = _first_difference(expected[step], state)
						_fail("Exchange pose difference: " + str(clip) + " step " + str(step))
						return
					frame_pairs += 1
				if step == 1 and clip in [&"attack_sword", &"hit", &"ride_slash"]:
					DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path))
					picture.save_png(output_path + "/" + str(clip) + ("_reference.png" if reference else "_candidate.png"))
				step += 1
			actor.set_process(false)
	assert(frame_pairs == 56)
	actor.editor.set_mount_enabled(false)
	for mode in range(4):
		var expected: Dictionary = {}
		for reference in [true, false]:
			paused = false
			actor.editor_window.hide()
			actor.set_process(false)
			actor.set("seek_reference", reference)
			actor._exchange_visual_active = false
			actor.play_pose(&"idle")
			actor.set_process(mode != 0)
			actor.combat_driven_by_lab = mode != 2
			paused = mode == 1
			actor.editor_window.visible = mode == 3
			actor.play_pose(&"hit")
			var state := _collision_snapshot()
			if reference: expected = state
			else: assert(state == expected, "Manual/paused/standalone/editor must seek immediately")
	paused = false
	actor.editor_window.hide()
	report.immediate_fallback_cases = 4
	finished = true
	report.exact = true
	report.body = body_index
	_write()
	print("ACTOR_EXCHANGE_SEEK_PASS body=", body_index, " exact_bone_cosmetic_rgba_pairs=", frame_pairs, " output=", output_path)
	actor.free()
	quit(0)
