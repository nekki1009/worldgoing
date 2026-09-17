extends SceneTree
## Exact current captain playback replay; establish old-vs-old control first.
const ARMY := "res://scripts/terrain_lab/terrain_army.gd"
const EDITOR := "res://scripts/ui/human_character_3d_editor.gd"
const OUT := "res://output/site_army_pose_replay_20260916/timeline"
var army: TerrainArmy
var editor: HumanCharacter3DEditor
var out := ""
var control := false

func _initialize() -> void:
	control = OS.get_cmdline_user_args().has("--control")
	_run.call_deferred()

func _difference(a: Variant, b: Variant, path: String = "state") -> String:
	if a == b: return ""
	if a is Array and b is Array and a.size() == b.size():
		for index in a.size():
			var child := _difference(a[index], b[index], path + "[%d]" % index)
			if not child.is_empty(): return child
	return "%s expected=%s actual=%s" % [path, var_to_str(a), var_to_str(b)]

func _state() -> Array:
	var state := []
	for node: Node in editor.preview_pivot.find_children("*", "Node3D", true, false):
		var spatial := node as Node3D
		var record: Array = [str(editor.preview_pivot.get_path_to(node)), spatial.transform, spatial.global_transform, spatial.visible]
		if node is Skeleton3D:
			for bone in node.get_bone_count(): record.append([node.get_bone_name(bone), node.get_bone_pose(bone), node.get_bone_global_pose(bone)])
		if node is MeshInstance3D:
			for shape in node.get_blend_shape_count(): record.append(node.get_blend_shape_value(shape))
			if node.mesh != null:
				for surface in node.mesh.get_surface_count():
					var material := node.get_active_material(surface) as ShaderMaterial
					if material != null:
						for uniform: Dictionary in material.shader.get_shader_uniform_list(): record.append([uniform.name, material.get_shader_parameter(uniform.name)])
		state.append(record)
	state.append([editor.selected_animation, editor.animation_player.current_animation_position, editor.visual_state.animation_time,
		editor.animation_player.assigned_animation, editor.animation_player.is_playing(), editor.animation_player.get_queue(),
		editor.timeline_slider.value, editor.timeline_slider.max_value, editor.timeline_slider.is_blocking_signals(),
		editor.animation_state_label.text, editor.status_label.text, army._sprites[0].transform])
	return state

func _run() -> void:
	create_timer(65.0).timeout.connect(func() -> void: push_error("Live timeline deadline"); quit(1))
	assert(DisplayServer.get_name() != "headless")
	var script := load(ARMY) as GDScript
	var old := FileAccess.get_file_as_string("res://scripts/tests/fixtures/terrain_army_captain_timeline_original.gd.txt")
	var signature := "func _sync_captain_combat(frame: Dictionary, index: int = 0) -> void:\n"
	assert(script.source_code.count(signature) == 1)
	script.source_code = script.source_code.replace(signature, "var timeline_reference := false\n" + signature + "\tif timeline_reference:\n\t\t_reference_sync(frame, index)\n\t\treturn\n") + "\n" + old.replace("func _sync_captain_combat(", "func _reference_sync(")
	assert(script.reload(true) == OK)
	var editor_script := load(EDITOR) as GDScript
	var callback := "func _on_timeline_changed(value: float) -> void:\n"
	assert(editor_script.source_code.count(callback) == 1)
	editor_script.source_code = editor_script.source_code.replace(callback, callback + "\tset_meta(&\"timeline_calls\", int(get_meta(&\"timeline_calls\", 0)) + 1)\n")
	assert(editor_script.reload(true) == OK)
	var data := TerrainData.new()
	data.allocate(Vector2i(24, 24))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "live-timeline")
	data.static_blocked.fill(0)
	army = TerrainArmy.new()
	army.roster_size = 1
	root.add_child(army)
	army.set_process(false)
	assert(army.deploy_at(data, null, null, [Vector2i(10, 10)]) and army.enable_combat(false))
	editor = army._unit_editor(0)
	assert(editor != null and editor.get_script() == HumanCharacter3DEditor)
	editor.set_process(false)
	editor.set_playing(false)
	# A frozen replay must not run a variable number of independent physics
	# modifier ticks while waiting for rendering. Direct owner calls still run.
	paused = true
	await process_frame
	await RenderingServer.frame_post_draw
	print("REPLAY_PLAYER blend=", editor.animation_player.playback_default_blend_time, " capture=", editor.animation_player.playback_auto_capture, " deterministic=", editor.animation_player.deterministic)
	for child: Node in editor.model_root.find_children("*", "SkeletonModifier3D", true, false): print("REPLAY_MODIFIER ", child.get_path())
	out = OUT + "/%d" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var transforms := {}
	var morphs := {}
	for node: Node in editor.preview_pivot.find_children("*", "Node3D", true, false):
		transforms[node] = (node as Node3D).transform
		if node is MeshInstance3D:
			var values := []
			for shape in node.get_blend_shape_count(): values.append(node.get_blend_shape_value(shape))
			morphs[node] = values
	var results := []
	for mode in ["hidden", "playing", "visible", "blocked", "legacy"]:
		for pose: String in army._combat_bake.clips:
			assert(army._combat_bake.clips.has(pose), "Replay uses the actual Army clip IDs")
			var expected := []
			var image_bytes := PackedByteArray()
			var calls := []
			for reference in [true, false]:
				army.set("timeline_reference", true)
				editor.timeline_slider.set_block_signals(false)
				editor.editor_root.visible = mode == "visible"
				army.exchange_enabled = mode != "legacy"
				editor.animation_player.stop()
				editor.animation_player.clear_caches()
				editor.set_playing(mode != "hidden")
				for child: Node in editor.model_root.find_children("*", "Skeleton3D", true, false): child.reset_bone_poses()
				for node: Node3D in transforms: node.transform = transforms[node]
				for mesh: MeshInstance3D in morphs:
					for shape in morphs[mesh].size(): mesh.set_blend_shape_value(shape, morphs[mesh][shape])
				army.combat_units[0].pose = "rescue"
				army.combat_units[0].age = 3.5
				army._sync_captain_combat(army.combat_frame(0), 0)
				editor.timeline_slider.set_value_no_signal(3.5)
				editor.timeline_slider.set_block_signals(mode == "blocked")
				editor.set_meta(&"timeline_calls", 0)
				army.set("timeline_reference", reference or control)
				army.combat_units[0].pose = pose
				army.combat_units[0].age = .173
				var owner := var_to_bytes([army.combat_units, army.cells, army.command_rng.state, army.combat_slots, army._reserved_cells])
				army._sync_captain_combat(army.combat_frame(0), 0)
				assert(owner == var_to_bytes([army.combat_units, army.cells, army.command_rng.state, army.combat_slots, army._reserved_cells]))
				var immediate := _state()
				await process_frame
				await RenderingServer.frame_post_draw
				var deferred_difference := _difference(immediate, _state())
				if not deferred_difference.is_empty(): print("REPLAY_DEFERRED ", mode, "/", pose, " ", deferred_difference)
				var picture := editor.preview_viewport.get_texture().get_image()
				assert(picture.get_used_rect().has_area())
				calls.append(int(editor.get_meta(&"timeline_calls", 0)))
				if reference:
					expected = _state()
					image_bytes = picture.get_data()
				else:
					var difference := _difference(expected, _state())
					if not difference.is_empty():
						push_error("Pose/UI/morph/visibility difference: " + mode + "/" + pose + " " + difference)
						army.free()
						quit(1)
						return
					assert(image_bytes == picture.get_data(), "Full RGBA difference: " + mode + "/" + pose)
				if mode == "hidden" and pose in ["walk_slash", "hit"]:
					assert(picture.save_png(out + "/" + pose + ("_reference.png" if reference else "_candidate.png")) == OK)
			if not control and mode in ["hidden", "playing"]:
				assert(calls[1] == 0, "Private timeline must not seek an intermediate clamped pose")
			else:
				assert(calls[0] == calls[1], "Public, blocked and legacy timeline callbacks must be preserved")
			results.append({"mode": mode, "pose": pose, "exact": true, "timeline_calls": calls})
	assert(results.any(func(row: Dictionary) -> bool: return row.mode == "hidden" and row.timeline_calls[0] > 0))
	var file := FileAccess.open(out + "/measurements.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"pairs": results, "exact": true, "control": control}, "\t"))
	file.close()
	print("LIVE_TIMELINE_PASS exact_pose_ui_morph_rgba_pairs=", results.size(), " control=", control, "; output=", out)
	army.free()
	quit(0)
