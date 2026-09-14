extends "res://scripts/tests/site_army_held_state_reuse_test.gd"
## The private source has no UI consumer. Keep original Range/clamp signals,
## animation and all geometry; omit only its hidden status/available-clip text.

var range_events: Array[float] = []

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	assert(DisplayServer.get_name() != "headless" and TerrainArmy.load_combat_bake())
	var baseline: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	var actor := TerrainTestCharacter.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	assert(actor.editor.restore_appearance(baseline))
	actor.editor.set_process(false)
	actor.editor.combat_ready = true
	actor.editor.visual_state.combat_ready = true
	actor.editor.set_playing(false)
	var source := Source.new()
	assert(source.initialize(root, baseline, actor.editor))
	var editor: Variant = source.editor
	assert(not editor.status_label.text.is_empty() and not editor.animation_state_label.text.is_empty(),
		"Initialization retains the original complete editor setup")
	editor.timeline_slider.value_changed.connect(func(value: float) -> void: range_events.append(value))
	var armor := baseline.duplicate(true)
	armor.parts.armor = "armor_mingguang_01"
	armor.parts.helmet = "helmet_mingguang_01"
	armor.parts.outfit = "outfit_chinese_lining_01"
	armor.parts.boots = "boots_mingguang_01"
	var requests: Array = [
		[&"idle", 0.019, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline],
		[&"walk_slash", 0.537, Vector2i.DOWN, Vector2(21, -54), 0.5, baseline],
		[&"guard", 0.073, Vector2i.UP, Vector2.ZERO, 0.0, baseline],
		[&"rescue", 1.137, Vector2i.LEFT, Vector2.ZERO, 0.0, baseline],
		[&"walk_slash", 0.517, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline],
		[&"down", 1.137, Vector2i.LEFT, Vector2.ZERO, 0.0, armor],
		[&"get_up", 0.337, Vector2i.LEFT, Vector2.ZERO, 0.0, armor],
		[&"guard", 0.083, Vector2i.DOWN, Vector2.ZERO, 0.0, missing_recipe(baseline, 2)],
		[&"idle", 0.219, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline]]
	var initial_morphs := _morphs(editor)
	var expected: Array[Dictionary] = []
	var passes: Array[Dictionary] = []
	for pass_index in range(2):
		editor.query_labels_enabled = pass_index == 0
		for path: NodePath in initial_morphs:
			var mesh := editor.model_root.get_node(path) as MeshInstance3D
			for shape in range(initial_morphs[path].size()):
				mesh.set_blend_shape_value(shape, initial_morphs[path][shape])
		source.clear_samples()
		source._key.clear()
		assert(not source.sample(&"rescue", 0.011, Vector2i.LEFT, Vector2.ZERO, 0.0, baseline).is_empty())
		# Deliberately exercise the original timeline maximum clamp and signal.
		editor.timeline_slider.set_value_no_signal(3.5)
		range_events.clear()
		var status_before: String = editor.status_label.text
		var animation_before: String = editor.animation_state_label.text
		var pose_before: int = source.profile_usec.pose
		var started := Time.get_ticks_usec()
		for index in range(requests.size()):
			var request: Array = requests[index]
			var query: Dictionary = source.sample(request[0], request[1], request[2], request[3], request[4], request[5])
			var snapshot := _snapshot(source, request[5], request, query)
			snapshot["timeline"] = [editor.timeline_slider.max_value, editor.timeline_slider.value, range_events.duplicate()]
			snapshot["camera"] = [editor.camera.transform, editor.camera.size, editor.preview_viewport.size]
			snapshot["playback"] = [editor.selected_animation, editor.animation_player.current_animation_position,
				editor.animation_player.speed_scale, editor.loop_toggle.button_pressed, editor.capture_appearance()]
			if pass_index == 0:
				expected.append(snapshot)
			else:
				assert(snapshot == expected[index], "Hidden-label suppression changed original pose/geometry/Range at %d" % index)
		if pass_index == 1:
			assert(editor.status_label.text == status_before and editor.animation_state_label.text == animation_before)
		assert(not range_events.is_empty(), "The original timeline clamp still emits its value signal")
		passes.append({"labels_enabled": editor.query_labels_enabled, "elapsed_usec": Time.get_ticks_usec() - started,
			"pose_usec": int(source.profile_usec.pose) - pose_before, "range_events": range_events.duplicate()})
	assert(not editor.editor_root.visible and editor.preview_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	var report := {"exact_pairs": requests.size(), "max_error": 0.0, "passes": passes,
		"source_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd"),
		"test_sha256": FileAccess.get_sha256("res://scripts/tests/site_army_query_labels_test.gd"),
		"scope": "Private hidden text only; original timeline signals/camera/animation/bones/morphs/geometry/armor exact; not FPS"}
	var path := "res://output/site_combat_performance_20260913/query_labels.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	source.dispose()
	actor.queue_free()
	await process_frame
	print("SITE_ARMY_QUERY_LABELS_PASS ", JSON.stringify(report))
	quit(0)
