extends "res://scripts/tests/site_army_baseline_key_test.gd"
## Same original private model, original native traversal versus ordered references.
## GPU --body=male|female, internal 23 seconds / canonical helper 25 seconds.

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	assert(DisplayServer.get_name() != "headless" and TerrainArmy.load_combat_bake())
	var body := 1 if "--body=female" in OS.get_cmdline_user_args() else 0
	var baseline: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	baseline.body = body
	baseline.parts.hair = HumanCharacter3DEditor.default_appearance(body).parts.hair
	var actor := TerrainTestCharacter.new()
	actor.visual_state.body_index = body
	root.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	assert(actor.editor != null and actor.editor.restore_appearance(baseline))
	actor.editor.set_process(false)
	actor.editor.set_playing(false)
	var source := Source.new()
	assert(source.initialize(root, baseline, actor.editor))
	var editor: Variant = source.editor
	var proxy := {"editor": editor, "player_sprite": source.sprite}
	var patterns: Array[String] = ["*", "Face_Standard*", "Shield_*", "Weapon_*", "NoSuchMesh*", "Armor_Mingguang_01_*"]
	# Normal actors keep the native mutable hierarchy path, not this private hook.
	assert(not actor.editor.has_method("_combat_mesh_nodes"))
	for pattern: String in patterns:
		assert(source.geometry._mesh_nodes(actor, pattern) == actor.editor.model_root.find_children(pattern, "MeshInstance3D", true, false))
	var lookup_timing: Array[Dictionary] = []
	for enabled: bool in [false, true]:
		editor.collision_mesh_lookup_enabled = enabled
		editor.clear_component_lookup_cache()
		for pattern: String in patterns:
			var nodes: Array = source.geometry._mesh_nodes(proxy, pattern)
			assert(nodes == editor.model_root.find_children(pattern, "MeshInstance3D", true, false))
			assert(nodes.is_read_only() == enabled)
		var count := 0
		var began := Time.get_ticks_usec()
		for iteration in range(1000):
			for pattern: String in patterns:
				count += source.geometry._mesh_nodes(proxy, pattern).size()
		lookup_timing.append({"enabled": enabled, "calls": 6000, "nodes": count, "usec": Time.get_ticks_usec() - began})
	assert(lookup_timing[0].nodes == lookup_timing[1].nodes)
	var initial_morphs := _morphs(editor)
	var no_shield := missing_recipe(baseline, 2)
	var spear := no_shield.duplicate(true)
	spear.parts.weapon = "spear_01"
	var bow := baseline.duplicate(true)
	bow.parts.weapon = "bow_01"
	var requests: Array = [
		[&"idle", 0.019, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline],
		[&"walk_slash", 0.537, Vector2i.DOWN, Vector2(21, -54), 0.5, baseline],
		[&"guard", 0.091, Vector2i.DOWN, Vector2.ZERO, 0.0, no_shield],
		[&"guard", 0.073, Vector2i.UP, Vector2.ZERO, 0.0, spear],
		[&"down", 0.613, Vector2i.LEFT, Vector2.ZERO, 0.0, baseline],
		[&"get_up", 0.337, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline],
		[&"rescue", 1.137, Vector2i.LEFT, Vector2.ZERO, 0.0, baseline],
		[&"attack_bow", 0.537, Vector2i.RIGHT, Vector2.ZERO, 0.0, bow],
		[&"reload_bow", 0.219, Vector2i.RIGHT, Vector2.ZERO, 0.0, bow],
		[&"guard", 0.091, Vector2i.DOWN, Vector2.ZERO, 0.0, missing_recipe(baseline, 31)],
		[&"walk_slash", 0.517, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline]]
	var expected: Array[Dictionary] = []
	var passes: Array[Dictionary] = []
	for enabled: bool in [false, true]:
		editor.collision_mesh_lookup_enabled = enabled
		editor.clear_component_lookup_cache()
		for path: NodePath in initial_morphs:
			var mesh := editor.model_root.get_node(path) as MeshInstance3D
			for shape in range(initial_morphs[path].size()):
				mesh.set_blend_shape_value(shape, initial_morphs[path][shape])
		source.clear_samples()
		source._key.clear()
		assert(not source.sample(&"walk", 0.011, Vector2i.LEFT, Vector2.ZERO, 0.0, baseline).is_empty())
		var began := Time.get_ticks_usec()
		for index in range(requests.size()):
			var snapshot := _key_snapshot(source, requests[index])
			snapshot.visibility = _visibility(editor)
			if not enabled:
				expected.append(snapshot)
			else:
				assert(snapshot == expected[index], "Original full geometry/bones/morphs/armor/visibility differs at %d" % index)
		passes.append({"enabled": enabled, "snapshots": requests.size(), "usec": Time.get_ticks_usec() - began})
	# The existing owner clears same-root structural changes; root identity also
	# invalidates automatically. Test only lookup, never fabricate query geometry.
	var original_root: Node3D = editor.model_root
	var replacement := Node3D.new()
	var first := MeshInstance3D.new()
	first.name = "Shield_Test_B"
	replacement.add_child(first)
	var second := MeshInstance3D.new()
	second.name = "Shield_Test_A"
	replacement.add_child(second)
	var retained: Array = source.geometry._mesh_nodes(proxy, "Shield_*")
	var retained_copy := retained.duplicate()
	editor.model_root = replacement
	assert(source.geometry._mesh_nodes(proxy, "Shield_*") == [first, second])
	replacement.move_child(second, 0)
	editor.clear_component_lookup_cache()
	assert(source.geometry._mesh_nodes(proxy, "Shield_*") == [second, first])
	editor.model_root = original_root
	assert(source.geometry._mesh_nodes(proxy, "Shield_*") == retained_copy)
	assert(retained == retained_copy and retained.is_read_only())
	replacement.free()
	var report := {"body": body, "exact_pairs": requests.size(), "maximum_error": 0.0,
		"lookup_timing": lookup_timing, "full_snapshot_timing": passes,
		"source_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd"),
		"geometry_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_weapon_collision.gd"),
		"scope": "Only original ordered native mesh node references, private fixed hierarchy; normal actor fallback, recipe/visibility/morph changes, read-only arrays and existing root/explicit invalidation. Not FPS or visual acceptance."}
	var path := "res://output/site_combat_performance_20260913/collision_mesh_lookup/body%d/%d_%d/measurements.json" % [body, int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	source.dispose()
	actor.queue_free()
	await process_frame
	print("SITE_ARMY_COLLISION_MESH_LOOKUP_PASS ", JSON.stringify(report))
	quit(0)
