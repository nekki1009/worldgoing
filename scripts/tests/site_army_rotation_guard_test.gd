extends "res://scripts/tests/site_army_exact_seek_test.gd"
## GPU only: original raw model, same-source unconditional setter versus exact
## current-value guard. Reuses the complete bone/morph/armor/sample snapshot.
## Internal 23 seconds / canonical helper 25 seconds; no FPS or visual claim.

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	assert(DisplayServer.get_name() != "headless", "Original mesh morph queries require the GPU verifier")
	assert(TerrainArmy.load_combat_bake())
	var baseline: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	var actor := TerrainTestCharacter.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	assert(actor.editor != null and actor.editor.restore_appearance(baseline))
	actor.editor.set_process(false)
	actor.editor.combat_ready = true
	actor.editor.visual_state.combat_ready = true
	actor.editor.set_playing(false)
	var source := Source.new()
	assert(source.initialize(root, baseline, actor.editor))
	source.terminal_cache_enabled = false
	var editor_id := source.editor.get_instance_id()
	var skeleton_id := source.skeleton.get_instance_id()
	var armor := baseline.duplicate(true)
	armor.parts.armor = "armor_mingguang_01"
	armor.parts.helmet = "helmet_mingguang_01"
	armor.parts.outfit = "outfit_chinese_lining_01"
	armor.parts.boots = "boots_mingguang_01"
	var stripped := missing_recipe(baseline, 31)
	var no_shield := missing_recipe(baseline, 2)
	var requests: Array = [
		[&"walk_slash", 0.213, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline],
		[&"walk_slash", 0.217, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline],
		[&"walk_slash", 0.221, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline],
		[&"walk_slash", 0.537, Vector2i.DOWN, Vector2(21.0, -54.0), 0.5, baseline],
		[&"walk_slash", 0.541, Vector2i.DOWN, Vector2(21.0, -54.0), 1.0, baseline],
		[&"guard", 0.073, Vector2i.UP, Vector2.ZERO, 0.0, baseline],
		[&"down", 1.137, Vector2i.LEFT, Vector2.ZERO, 0.0, armor],
		[&"get_up", 0.337, Vector2i.LEFT, Vector2.ZERO, 0.0, armor],
		[&"idle", 0.219, Vector2i.RIGHT, Vector2.ZERO, 0.0, stripped],
		[&"walk_slash", 0.517, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline],
		[&"guard", 0.083, Vector2i.DOWN, Vector2.ZERO, 0.0, no_shield],
		[&"walk_slash", 0.521, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline]]
	var expected: Array[Dictionary] = []
	var passes: Array[Dictionary] = []
	for pass_index in range(2):
		source.equal_rotation_guard_enabled = pass_index == 1
		source.clear_samples()
		# A real interlude keeps A/B from accidentally taking the existing _key
		# shortcut. Both passes retain all preceding original animation history.
		assert(not source.sample(&"idle", 0.019, Vector2i.LEFT, Vector2.ZERO, 0.0, stripped).is_empty())
		var before: Dictionary = source.query_profile.duplicate()
		var started := Time.get_ticks_usec()
		for index in range(requests.size()):
			var request: Array = requests[index]
			if index == 2:
				# The requested direction has not changed, but the real transform has.
				# A last-direction flag would incorrectly leave this disturbed pose.
				source.editor.preview_pivot.rotation = Vector3(0.125, 0.375, -0.25)
			var evaluated: int = source.query_profile.true_pose_evaluations
			var query := _request_sample(source, request)
			assert(not query.is_empty() and int(source.query_profile.true_pose_evaluations) == evaluated + 1,
				"Every distinct request must execute the original exact seek, not reuse the prior time")
			var snapshot := _snapshot(source, request[5], request, query)
			snapshot["rotation"] = source.editor.preview_pivot.rotation
			if pass_index == 0:
				expected.append(snapshot)
			else:
				_assert_exact(snapshot, expected[index], "sequential request %d" % index)
		var request_a: Array = requests[0]
		var live_key: Array = source._key.duplicate(true)
		var evaluated: int = source.query_profile.true_pose_evaluations
		var cached_a := _request_sample(source, request_a)
		assert(cached_a == expected[0].sample and source._key == live_key)
		assert(int(source.query_profile.true_pose_evaluations) == evaluated,
			"A cached sample must not claim the single live model has left B")
		var protection: Vector2 = source.armor_at(request_a[0], request_a[1], request_a[2],
			centre(cached_a.body[0]), "slash", request_a[3], request_a[4], request_a[5])
		assert(protection == expected[0].protection[0])
		assert(int(source.query_profile.true_pose_evaluations) == evaluated + 1,
			"Armor restore is a real seek and must be included in true_pose_evaluations")
		var restored := _snapshot(source, request_a[5], request_a, cached_a)
		restored["rotation"] = source.editor.preview_pivot.rotation
		_assert_exact(restored, expected[0], "cached A / live B / armor A")
		# Clearing result data does not change the current live pose. The old
		# sample-miss count rises, but the new true evaluation count must not.
		source.begin_contact_step()
		evaluated = int(source.query_profile.true_pose_evaluations)
		var sample_misses: int = source.query_profile.pose_evaluations
		assert(_request_sample(source, request_a) == cached_a)
		assert(int(source.query_profile.pose_evaluations) == sample_misses + 1)
		assert(int(source.query_profile.true_pose_evaluations) == evaluated)
		var measured := {"guard_enabled": source.equal_rotation_guard_enabled,
			"elapsed_usec": Time.get_ticks_usec() - started, "query_profile": {}}
		for field: String in source.query_profile:
			measured.query_profile[field] = int(source.query_profile[field]) - int(before[field])
		assert(int(measured.query_profile.true_pose_evaluations) == requests.size() + 1)
		passes.append(measured)
	assert(source.editor.get_instance_id() == editor_id and source.skeleton.get_instance_id() == skeleton_id)
	assert(source.editor.preview_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	var report := {"exact_pairs": requests.size() + 1, "max_error": 0.0, "passes": passes,
		"source_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd"),
		"test_sha256": FileAccess.get_sha256("res://scripts/tests/site_army_rotation_guard_test.gd"),
		"scope": "Original source setter versus exact current rotation guard; full samples, bones, morphs, worn armor vertices and protection; not FPS"}
	var path := "res://output/site_combat_performance_20260913/rotation_guard.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	source.dispose()
	actor.queue_free()
	await process_frame
	print("SITE_ARMY_ROTATION_GUARD_PASS ", JSON.stringify(report))
	quit(0)

func _request_sample(source: Variant, request: Array) -> Dictionary:
	return source.sample(request[0], request[1], request[2], request[3], request[4], request[5])

func _assert_exact(actual: Dictionary, expected: Dictionary, label: String) -> void:
	assert(actual.keys() == expected.keys(), "%s: complete snapshot fields differ" % label)
	for field: String in expected:
		assert(actual[field] == expected[field], "%s: %s is not exactly equal (no tolerance)" % [label, field])
