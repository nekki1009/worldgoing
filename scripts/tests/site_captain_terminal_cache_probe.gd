extends "res://scripts/tests/site_captain_timeline_replay_test.gd"
## Diagnostic only: original private captain and every exact state field remain
## the reference. A faster but observably different player is NOT accepted.

func _run() -> void:
	create_timer(55.0).timeout.connect(func() -> void: push_error("Terminal cache probe deadline"); quit(1))
	assert(DisplayServer.get_name() != "headless")
	var data := TerrainData.new()
	data.allocate(Vector2i(24, 24))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "terminal-cache-probe")
	data.static_blocked.fill(0)
	army = TerrainArmy.new()
	army.roster_size = 1
	root.add_child(army)
	army.set_process(false)
	assert(army.deploy_at(data, null, null, [Vector2i(10, 10)]) and army.enable_combat(false))
	editor = army._unit_editor(0)
	assert(editor != null and editor.get_script() == HumanCharacter3DEditor)
	editor.set_process(false)
	editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	paused = true
	await process_frame
	await RenderingServer.frame_post_draw
	out = "res://output/site_army_terminal_cache_20260916/run_%d" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var transforms := {}
	var morphs := {}
	for node: Node in editor.preview_pivot.find_children("*", "Node3D", true, false):
		transforms[node] = (node as Node3D).transform
		if node is MeshInstance3D:
			var values := []
			for shape in node.get_blend_shape_count(): values.append(node.get_blend_shape_value(shape))
			morphs[node] = values
	var player := editor.animation_player
	var supports_policy := false
	for property: Dictionary in player.get_property_list():
		if property.name == "clear_cache_on_stop": supports_policy = true
	var events: Array[String] = []
	var clears: Array[int] = [0]
	player.caches_cleared.connect(func() -> void: clears[0] += 1)
	player.animation_finished.connect(func(clip: StringName) -> void: events.append("finished:" + str(clip)))
	player.animation_started.connect(func(clip: StringName) -> void: events.append("started:" + str(clip)))
	player.current_animation_changed.connect(func(clip: StringName) -> void: events.append("current:" + str(clip)))
	var results := []
	for pose: StringName in [&"walk_slash", &"down"]:
		assert(player.has_animation(pose) and player.get_animation(pose).loop_mode == Animation.LOOP_NONE)
		var expected := []
		for variant: int in range(3): # Original, original control, reverse-zero terminal trial.
			editor.set_playing(false)
			player.stop()
			player.clear_caches()
			for child: Node in editor.model_root.find_children("*", "Skeleton3D", true, false): child.reset_bone_poses()
			for node: Node3D in transforms: node.transform = transforms[node]
			for mesh: MeshInstance3D in morphs:
				for shape in morphs[mesh].size(): mesh.set_blend_shape_value(shape, morphs[mesh][shape])
			assert(editor.select_animation_by_id(pose))
			editor.set_playing(true)
			player.speed_scale = 1.0
			var length := player.get_animation(pose).length
			for step in range(4):
				if step == 3: assert(editor.select_animation_by_id(&"idle"))
				var sample := length * 0.5 if step == 0 else (0.173 if step == 3 else length)
				events.clear()
				clears[0] = 0
				var owner := var_to_bytes([army.combat_units, army.cells, army.command_rng.state, army.combat_slots, army._reserved_cells])
				var started := Time.get_ticks_usec()
				# A source-backed experiment, not a gameplay fix: reversing zero
				# delta avoids the forward-end branch but may change player state.
				if variant == 2 and step in [1, 2]: player.speed_scale = -0.0
				player.seek(sample, true)
				player.speed_scale = 1.0
				var seek_usec := Time.get_ticks_usec() - started
				editor._process(0.0)
				await process_frame
				await RenderingServer.frame_post_draw
				assert(owner == var_to_bytes([army.combat_units, army.cells, army.command_rng.state, army.combat_slots, army._reserved_cells]))
				var picture := editor.preview_viewport.get_texture().get_image()
				assert(picture.get_used_rect().has_area())
				var state := _state()
				var observed_events := events.duplicate()
				var record := {"pose": str(pose), "variant": variant, "step": step, "seek_usec": seek_usec,
					"cache_clears": clears[0], "playing": player.is_playing(), "assigned": str(player.assigned_animation),
					"position": player.current_animation_position, "events": observed_events}
				if variant == 0:
					expected.append([state, picture.get_data(), observed_events])
				else:
					record["full_state_equal"] = state == expected[step][0]
					record["full_rgba_equal"] = picture.get_data() == expected[step][1]
					record["events_equal"] = observed_events == expected[step][2]
					record["difference"] = _difference(expected[step][0], state)
					if variant == 1:
						assert(record.full_state_equal and record.full_rgba_equal and record.events_equal, "Original/original control failed: " + record.difference)
				if step == 2: assert(picture.save_png(out + "/%s_%d.png" % [pose, variant]) == OK)
				results.append(record)
	var equivalent := results.all(func(row: Dictionary) -> bool: return int(row.variant) != 2 or (row.full_state_equal and row.full_rgba_equal and row.events_equal))
	var report := {"engine": Engine.get_version_info(), "clear_cache_on_stop_available": supports_policy,
		"candidate_equivalent": equivalent, "candidate_adopted": false, "rows": results,
		"scope": "Frozen original-captain endpoint diagnostic; no production mutation and no FPS claim"}
	var file := FileAccess.open(out + "/measurements.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("TERMINAL_CACHE_PROBE_DONE equivalent=", equivalent, " clear_cache_on_stop=", supports_policy, " output=", out)
	army.free()
	quit(0)
