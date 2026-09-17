extends "res://scripts/tests/site_captain_timeline_replay_test.gd"
## Diagnostic only. Fixed-sequence working set; unused full animations remain
## in memory. This is not yet an on-demand playback implementation or FPS test.

func _run() -> void:
	create_timer(200.0).timeout.connect(func() -> void: push_error("Clip-set probe deadline"); quit(1))
	assert(DisplayServer.get_name() != "headless")
	var data := TerrainData.new()
	data.allocate(Vector2i(24, 24))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "clip-set-probe")
	data.static_blocked.fill(0)
	army = TerrainArmy.new()
	army.roster_size = 1
	root.add_child(army)
	army.set_process(false)
	assert(army.deploy_at(data, null, null, [Vector2i(10, 10)]) and army.enable_combat(false))
	editor = army._unit_editor(0)
	assert(editor != null and editor.get_script() == HumanCharacter3DEditor)
	editor.set_process(false)
	var player := editor.animation_player
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	assert(player.get_animation_library_list().size() == 1 and player.has_animation_library(&""))
	var full := player.get_animation_library(&"")
	var catalog := player.get_animation_list()
	var full_tracks := 0
	for name: StringName in catalog: full_tracks += full.get_animation(name).get_track_count()
	paused = true
	await process_frame
	await RenderingServer.frame_post_draw
	out = "res://output/site_captain_clip_set_20260916/run_%d" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var transforms := {}
	var morphs := {}
	for node: Node in editor.preview_pivot.find_children("*", "Node3D", true, false):
		transforms[node] = (node as Node3D).transform
		if node is MeshInstance3D:
			var values := []
			for shape in node.get_blend_shape_count(): values.append(node.get_blend_shape_value(shape))
			morphs[node] = values
	var notices: Array = []
	player.animation_started.connect(func(clip: StringName) -> void: notices.append(["started", clip]))
	player.animation_finished.connect(func(clip: StringName) -> void: notices.append(["finished", clip]))
	player.current_animation_changed.connect(func(clip: StringName) -> void: notices.append(["current", clip]))
	player.animation_changed.connect(func(previous: StringName, clip: StringName) -> void: notices.append(["changed", previous, clip]))
	var rows := []
	for pose: StringName in [&"walk_slash", &"down", &"get_up", &"attack_bow", &"reload_crossbow"]:
		print("CLIP_SET_CASE ", pose)
		var subset := AnimationLibrary.new()
		var subset_tracks := 0
		for name: StringName in catalog:
			var source := full.get_animation(name)
			var animation := source
			if name not in [pose, &"idle", &"RESET"]:
				animation = Animation.new()
				animation.length = source.length
				animation.step = source.step
				animation.loop_mode = source.loop_mode
			subset_tracks += animation.get_track_count()
			assert(subset.add_animation(name, animation) == OK)
		var expected := []
		for variant in range(4): # Full reference, full control, working set, full reverse control.
			editor.set_playing(false)
			player.stop()
			player.remove_animation_library(&"")
			assert(player.add_animation_library(&"", subset if variant == 2 else full) == OK)
			assert(player.get_animation_list() == catalog)
			for child: Node in editor.model_root.find_children("*", "Skeleton3D", true, false): child.reset_bone_poses()
			for node: Node3D in transforms: node.transform = transforms[node]
			for mesh: MeshInstance3D in morphs:
				for shape in morphs[mesh].size(): mesh.set_blend_shape_value(shape, morphs[mesh][shape])
			assert(editor.select_animation_by_id(pose) and editor.selected_animation == pose)
			editor.set_playing(true)
			var length := player.get_animation(pose).length
			for step in range(4):
				if step == 3: assert(editor.select_animation_by_id(&"idle"))
				var sample := length * .5 if step == 0 else (.173 if step == 3 else length)
				notices.clear()
				var owner := var_to_bytes([army.combat_units, army.cells, army.command_rng.state, army.combat_slots, army._reserved_cells])
				var started := Time.get_ticks_usec()
				player.seek(sample, true)
				var seek_usec := Time.get_ticks_usec() - started
				editor._process(0.0)
				await process_frame
				await RenderingServer.frame_post_draw
				assert(owner == var_to_bytes([army.combat_units, army.cells, army.command_rng.state, army.combat_slots, army._reserved_cells]))
				var picture := editor.preview_viewport.get_texture().get_image()
				assert(picture.get_used_rect().has_area())
				var state := _state()
				var record := {"pose": str(pose), "variant": variant, "step": step, "seek_usec": seek_usec, "tracks": subset_tracks if variant == 2 else full_tracks}
				if variant == 0:
					expected.append([state, picture.get_data(), notices.duplicate(true)])
				else:
					record.full_state_equal = state == expected[step][0]
					record.full_rgba_equal = picture.get_data() == expected[step][1]
					record.events_equal = notices == expected[step][2]
					record.difference = _difference(expected[step][0], state)
					if variant != 2: assert(record.full_state_equal and record.full_rgba_equal and record.events_equal, "Full/full control mismatch: " + record.difference)
				if step == 2 and pose in [&"walk_slash", &"down"]: assert(picture.save_png(out + "/%s_%d.png" % [pose, variant]) == OK)
				rows.append(record)
	var equivalent := rows.all(func(row: Dictionary) -> bool: return int(row.variant) != 2 or (row.full_state_equal and row.full_rgba_equal and row.events_equal))
	var report := {"rows": rows, "full_tracks": full_tracks, "fixed_sequence_equivalent": equivalent, "catalog_equal": true, "candidate_adopted": false,
		"limitations": "Unused animation tracks are stubs in this diagnostic only; arbitrary clip switches, equipment, blending, queue, body swap and complete gameplay are NOT validated", "engine": Engine.get_version_info()}
	var file := FileAccess.open(out + "/measurements.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CLIP_SET_PROBE_DONE fixed_sequence_equivalent=", equivalent, " output=", out)
	army.free()
	quit(0)
