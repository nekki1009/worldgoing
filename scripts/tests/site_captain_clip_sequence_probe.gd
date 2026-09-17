extends "res://scripts/tests/site_captain_timeline_replay_test.gd"
## Diagnostic: continuous original history, not isolated poses or FPS acceptance.

func _cache_comparable(value: Variant) -> Variant:
	# Resource IDs differ between engine processes; keep their authored identity.
	# Full within-process state equality and full RGBA equality remain mandatory.
	if value is Resource: return [value.get_class(), value.resource_path]
	if value is Array:
		var result := []
		for item: Variant in value: result.append(_cache_comparable(item))
		return result
	return value

func _cache_digest(bytes: PackedByteArray) -> String:
	var digest := HashingContext.new()
	assert(digest.start(HashingContext.HASH_SHA256) == OK)
	assert(digest.update(bytes) == OK)
	return digest.finish().hex_encode()

func _run() -> void:
	create_timer(110.0).timeout.connect(func() -> void: push_error("Clip sequence deadline"); quit(1))
	assert(DisplayServer.get_name() != "headless")
	var safe := "--clip-safe" in OS.get_cmdline_user_args()
	var retain_cache := "--retain-animation-cache" in OS.get_cmdline_user_args()
	var cache_control := "--animation-cache-control" in OS.get_cmdline_user_args()
	var cache_trial := retain_cache or cache_control
	assert(not (retain_cache and cache_control))
	var boundary := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--clip-boundary="): boundary = argument.get_slice("=", 1)
	assert(boundary in ["", "queue", "blend", "chain", "public"])
	var compact_keys := "--compact-zero-keys" in OS.get_cmdline_user_args()
	var compact_in_place := compact_keys and "--compact-in-place" in OS.get_cmdline_user_args()
	var morph_zero_guard := "--morph-zero-guard" in OS.get_cmdline_user_args()
	assert(not cache_trial or (not safe and not compact_keys and not morph_zero_guard))
	assert(not morph_zero_guard or (not safe and not compact_keys and boundary.is_empty()))
	if morph_zero_guard:
		preload("res://scripts/tests/fixtures/animation_morph_zero_guard.gd").install(true)
	elif safe:
		preload("res://scripts/tests/fixtures/captain_clip_safe_install.gd").install()
	elif not compact_keys and not cache_trial:
		var script := load(EDITOR) as GDScript
		var anchor := "\tvar animation := animation_player.get_animation(play_anim)\n\t# Rewriting the same Resource value"
		assert(script.source_code.count(anchor) == 1)
		script.source_code = script.source_code.replace(anchor, "\t_clip_set_probe_prepare(play_anim)\n" + anchor) + "\n" + FileAccess.get_file_as_string("res://scripts/tests/fixtures/captain_clip_working_set.gd.txt")
		assert(script.reload(true) == OK)
	var data := TerrainData.new()
	data.allocate(Vector2i(24, 24))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "clip-sequence-probe")
	data.static_blocked.fill(0)
	army = TerrainArmy.new()
	army.roster_size = 1
	root.add_child(army)
	army.set_process(false)
	assert(army.deploy_at(data, null, null, [Vector2i(10, 10)]) and army.enable_combat(false))
	editor = army._unit_editor(0)
	editor.set_process(false)
	if "--male-body" in OS.get_cmdline_user_args(): editor._on_body_selected(0)
	var player := editor.animation_player
	if retain_cache:
		assert(player.has_method("set_clear_cache_on_stop_enabled"), "Cache trial requires the isolated patched engine")
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var library := player.get_animation_library(&"")
	var originals := {}
	for clip: StringName in player.get_animation_list(): originals[clip] = library.get_animation(clip)
	var compacted := {}
	var key_counts := {"before": 0, "after": 0, "tracks": 0}
	if compact_keys:
		# Reuse the existing conservative key compactor. Keep EVERY track,
		# alias and clip; this does not change AnimationMixer.deterministic.
		var compactor := preload("res://scripts/terrain_lab/terrain_army_contact_source.gd").new()
		var copies := {}
		for clip: StringName in originals:
			var original: Animation = originals[clip]
			if not copies.has(original):
				var copy := original.duplicate(true) as Animation
				if not compact_in_place: compactor._compact_constant_morph_keys(copy)
				copies[original] = copy
				for track in original.get_track_count():
					key_counts.before += original.track_get_key_count(track)
					key_counts.after += copy.track_get_key_count(track)
					key_counts.tracks += 1
			compacted[clip] = copies[original]
		print("ZERO_KEY_COMPACTION ", key_counts, " deterministic=", player.deterministic)
	paused = true
	await process_frame
	await RenderingServer.frame_post_draw
	out = "res://output/site_captain_clip_sequence_20260917/run_%d" % int(Time.get_unix_time_from_system())
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
	var cache_clears: Array[int] = [0]
	if cache_trial: player.caches_cleared.connect(func() -> void: cache_clears[0] += 1)
	player.animation_started.connect(func(clip: StringName) -> void: notices.append(["started", clip]))
	player.animation_finished.connect(func(clip: StringName) -> void: notices.append(["finished", clip]))
	player.current_animation_changed.connect(func(clip: StringName) -> void: notices.append(["current", clip]))
	player.animation_changed.connect(func(previous: StringName, clip: StringName) -> void: notices.append(["changed", previous, clip]))
	var poses: Array[StringName] = [&"idle", &"walk_slash", &"walk_slash", &"idle", &"down", &"get_up", &"idle", &"attack_bow", &"idle", &"reload_crossbow", &"idle", &"walk_slash", &"hit", &"guard", &"down", &"idle"]
	if safe and ("--clip-reactions" in OS.get_cmdline_user_args() or "--clip-lifecycle" in OS.get_cmdline_user_args() or "--clip-mobile" in OS.get_cmdline_user_args() or "--clip-mobile-lifecycle" in OS.get_cmdline_user_args()):
		poses.assign([&"idle", &"walk_slash", &"hit", &"hit_back", &"knockback", &"guard", &"walk_slash", &"hit", &"idle"] + poses)
		if "--clip-mobile" in OS.get_cmdline_user_args() or "--clip-mobile-lifecycle" in OS.get_cmdline_user_args():
			poses[1] = &"walk"
			poses[2] = &"run"
		if "--clip-mobile-lifecycle" in OS.get_cmdline_user_args():
			poses.insert(9, &"unconscious")
			poses.insert(10, &"rescue")
	var fallback_index := poses.size()
	if safe:
		for pose_index in poses.size():
			if poses[pose_index] not in editor.call("_clip_safe_resident"):
				fallback_index = pose_index
				break
	if not boundary.is_empty():
		assert((safe and poses.size() in [25, 27]) or cache_trial)
		fallback_index = mini(fallback_index, 9)
	var expected := []
	var rows := []
	for variant in range(4): # original, original control, candidate, reverse original.
		if retain_cache: player.call("set_clear_cache_on_stop_enabled", true)
		if morph_zero_guard: editor.set("morph_zero_guard_enabled", false)
		if safe: editor.call("_clip_safe_restore", "test_replay_reset")
		if editor.has_meta(&"clip_set_probe_enabled"): editor.remove_meta(&"clip_set_probe_enabled")
		editor.set_playing(false)
		player.stop()
		if cache_trial: player.clear_caches()
		if not boundary.is_empty():
			player.clear_queue()
			player.playback_default_blend_time = 0.0
			for clip: StringName in originals: player.animation_set_next(clip, &"")
			editor.editor_root.hide()
		if compact_in_place and variant in [2, 3]:
			var visited := {}
			var compactor := preload("res://scripts/terrain_lab/terrain_army_contact_source.gd").new()
			for clip: StringName in originals:
				var original: Animation = originals[clip]
				if visited.has(original): continue
				visited[original] = true
				if variant == 2:
					compactor._compact_constant_morph_keys(original)
					for track in original.get_track_count():
						key_counts.after -= compacted[clip].track_get_key_count(track) - original.track_get_key_count(track)
				else:
					# Restore only removed positive-zero morph keys. Duplicating a
					# raw Animation also re-normalizes rotation keys; never replace
					# its untouched raw transforms during this in-place experiment.
					var backup: Animation = compacted[clip]
					for track in original.get_track_count():
						if original.track_get_key_count(track) == backup.track_get_key_count(track): continue
						assert(original.track_get_type(track) == Animation.TYPE_BLEND_SHAPE and original.track_get_key_count(track) == 1)
						for key in range(1, backup.track_get_key_count(track)):
							assert(backup.track_get_key_value(track, key) == 0.0)
							original.track_insert_key(track, backup.track_get_key_time(track, key), backup.track_get_key_value(track, key), backup.track_get_key_transition(track, key))
		for clip: StringName in originals:
			var chosen: Animation = compacted[clip] if compact_keys and not compact_in_place and variant == 2 else originals[clip]
			if library.get_animation(clip) != chosen: assert(library.add_animation(clip, chosen) == OK)
		for child: Node in editor.model_root.find_children("*", "Skeleton3D", true, false): child.reset_bone_poses()
		for node: Node3D in transforms: node.transform = transforms[node]
		for mesh: MeshInstance3D in morphs:
			for shape in morphs[mesh].size(): mesh.set_blend_shape_value(shape, morphs[mesh][shape])
		assert(editor.select_animation_by_id(&"idle"))
		editor.set_playing(true)
		player.seek(0.0, true)
		editor._process(0.0)
		if morph_zero_guard:
			editor.set("morph_zero_guard_enabled", variant == 2)
			editor.set("morph_zero_writes", 0)
		elif cache_trial:
			if retain_cache: player.call("set_clear_cache_on_stop_enabled", variant != 2)
		elif variant == 2 and not compact_keys: editor.set_meta(&"clip_safe_enabled" if safe else &"clip_set_probe_enabled", true)
		for pose_index in poses.size():
			var pose := poses[pose_index]
			for step in range(3):
				if pose_index == 9 and step == 0:
					match boundary:
						"queue": player.queue(&"down")
						"blend": player.playback_default_blend_time = .1
						"chain": player.animation_set_next(&"idle", &"down")
						"public": editor.editor_root.show()
				notices.clear()
				cache_clears[0] = 0
				var owner := var_to_bytes([army.combat_units, army.cells, army.command_rng.state, army.combat_slots, army._reserved_cells])
				var started := Time.get_ticks_usec()
				if step == 0: assert(editor.select_animation_by_id(pose))
				if safe and variant == 2:
					assert(bool(editor.get_meta(&"clip_safe_enabled", false)) == (pose_index < fallback_index))
					if pose_index >= fallback_index:
						for clip: StringName in originals: assert(library.get_animation(clip) == originals[clip])
				var length: float = originals[pose].length
				player.seek(length * .5 if step == 0 else length, true)
				editor._process(0.0)
				var elapsed := Time.get_ticks_usec() - started
				var immediate := _state()
				await process_frame
				await RenderingServer.frame_post_draw
				var picture := editor.preview_viewport.get_texture().get_image()
				assert(picture.get_used_rect().has_area())
				assert(owner == var_to_bytes([army.combat_units, army.cells, army.command_rng.state, army.combat_slots, army._reserved_cells]))
				var observation: Array = [immediate, _state(), notices.duplicate(true)]
				var row := {"variant": variant, "pose_index": pose_index, "pose": str(pose), "step": step, "select_seek_process_usec": elapsed}
				if cache_trial:
					row["cache_clears"] = cache_clears[0]
					row["state_sha256"] = _cache_digest(var_to_bytes(_cache_comparable(observation)))
					row["rgba_sha256"] = _cache_digest(picture.get_data())
					if variant == 0 and pose_index == 0 and step == 0:
						# Keep the actual values for diagnosing cross-process digest
						# differences; never relax the exact in-process comparison.
						var state_file := FileAccess.open(out + "/first_state.bin", FileAccess.WRITE)
						assert(state_file != null)
						state_file.store_buffer(var_to_bytes(_cache_comparable(observation)))
						state_file.close()
						for argument: String in OS.get_cmdline_user_args():
							if argument.begins_with("--cache-state-reference="):
								var reference: Variant = bytes_to_var(FileAccess.get_file_as_bytes(argument.trim_prefix("--cache-state-reference=")))
								print("CACHE_CROSS_PROCESS_FIRST_DIFFERENCE ", _difference(reference, _cache_comparable(observation)))
				if morph_zero_guard: row["morph_zero_writes"] = int(editor.get("morph_zero_writes"))
				if variant == 0:
					expected.append([observation, picture.get_data()])
				else:
					var previous: Array = expected[pose_index * 3 + step]
					row.state_equal = observation == previous[0]
					row.rgba_equal = picture.get_data() == previous[1]
					row.difference = _difference(previous[0], observation)
					if variant != 2: assert(row.state_equal and row.rgba_equal, "Original history control mismatch: " + row.difference)
				rows.append(row)
				if pose_index in [1, 4, 7] and step == 2: assert(picture.save_png(out + "/%s_%d.png" % [pose, variant]) == OK)
	var equivalent := rows.all(func(row: Dictionary) -> bool: return int(row.variant) != 2 or (row.state_equal and row.rgba_equal))
	var file := FileAccess.open(out + "/measurements.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows": rows, "continuous_sequence_equivalent": equivalent, "retain_animation_cache": retain_cache, "animation_cache_control": cache_control, "safe_full_fallback": safe, "playback_boundary": boundary, "compact_zero_keys": compact_keys, "compact_in_place": compact_in_place, "morph_zero_guard": morph_zero_guard, "key_counts": key_counts, "candidate_adopted": false, "engine": Engine.get_version_info()}, "\t"))
	file.close()
	print("CLIP_SEQUENCE_DONE equivalent=", equivalent, " output=", out)
	army.free()
	quit(0 if equivalent else 1)
