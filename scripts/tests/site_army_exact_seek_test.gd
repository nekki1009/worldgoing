extends "res://scripts/tests/site_army_equipment_query_test.gd"
## GPU groups 0..5 retain the original equipment/HumanEditor matrix.
## GPU group 6 independently exercises reverse seeks and one-shot boundaries.
## Each group keeps the original 23-second internal deadline; no FPS claim.

var old_pose_usec := 0
var seek_pose_usec := 0
var exact_pairs := 0

func _snapshot(source: Variant, appearance: Dictionary, request: Array, query: Dictionary) -> Dictionary:
	var result := {"sample": query.duplicate(true), "bones": [], "morphs": {}, "armor": {}, "protection": []}
	for index: int in source.skeleton.get_bone_count():
		result.bones.append([source.skeleton.get_bone_pose(index), source.skeleton.get_bone_global_pose(index)])
	# Compare every authored scalar morph, including unworn original meshes.
	for node: Node in source.editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.get_blend_shape_count() == 0:
			continue
		var values: Array[float] = []
		for shape in range(mesh.get_blend_shape_count()):
			values.append(mesh.get_blend_shape_value(shape))
		result.morphs[source.editor.model_root.get_path_to(mesh)] = values
	var proxy := {"editor": source.editor, "player_sprite": source.sprite}
	for slot: StringName in [&"helmet", &"armor", &"outfit", &"boots"]:
		var item := StringName(str(appearance.parts[str(slot)]))
		if item == &"none":
			continue
		var component: Dictionary = source.editor._component_definition(slot, item)
		for node: Node in source.editor._find_component_nodes(component.get("prefixes", [])):
			var mesh := node as MeshInstance3D
			if mesh != null and mesh.is_visible_in_tree() and mesh.mesh != null:
				result.armor[source.editor.model_root.get_path_to(mesh)] = source.geometry.posed_points(proxy, mesh, source.skeleton)
	for limb: int in [0, 3, 7, 9]:
		result.protection.append(source.armor_at(request[0], request[1], request[2], centre(query.body[limb]), "slash", request[3], request[4], appearance))
	return result

func compare_pose(source: Variant, actor: TerrainTestCharacter, appearance: Dictionary, clip: StringName, time: float, direction: Vector2i) -> Dictionary:
	assert(source.get("exact_seek_only_enabled") != null)
	var baseline: Dictionary = TerrainArmy._combat_bake.manifest.appearance
	var interlude := missing_recipe(baseline, 31) if appearance.parts != missing_recipe(baseline, 31).parts else baseline
	var request: Array = [clip, time, direction, Vector2.ZERO, 0.0]
	source.terminal_cache_enabled = false
	source.exact_seek_only_enabled = false
	source.clear_samples()
	assert(not source.sample(&"idle", 0.017, Vector2i.DOWN, Vector2.ZERO, 0.0, interlude).is_empty())
	var before: int = source.profile_usec.pose
	# Original HumanEditor remains independent; its original seek+advance and
	# original geometry/protection checks are not modified by this source flag.
	var original := super.compare_pose(source, actor, appearance, clip, time, direction)
	old_pose_usec += int(source.profile_usec.pose) - before
	var expected := _snapshot(source, appearance, request, original)
	source.exact_seek_only_enabled = true
	source.clear_samples()
	assert(not source.sample(&"idle", 0.017, Vector2i.DOWN, Vector2.ZERO, 0.0, interlude).is_empty())
	before = int(source.profile_usec.pose)
	var query: Dictionary = source.sample(clip, time, direction, Vector2.ZERO, 0.0, appearance)
	seek_pose_usec += int(source.profile_usec.pose) - before
	assert(_snapshot(source, appearance, request, query) == expected,
		"One original seek(update=true) preserves every exact bone, scalar morph, worn armor vertex, sample field and protection result")
	assert(source.editor.animation_player.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL)
	exact_pairs += 1
	return query

func run() -> void:
	if group == 6:
		await _boundary_run()
	else:
		await super.run()
	assert(exact_pairs > 0)
	var report := {"group": group, "exact_pairs": exact_pairs, "seek_advance_pose_usec": old_pose_usec,
		"seek_only_pose_usec": seek_pose_usec, "exact": true,
		"source_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd"),
		"scope": "Same-source original seek+advance versus seek-only exact geometry; original HumanEditor reference; not FPS"}
	var path := "res://output/site_combat_performance_20260913/exact_seek/group_%d.json" % group
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SITE_ARMY_EXACT_SEEK_PASS ", JSON.stringify(report))
	quit(0)

func _boundary_run() -> void:
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
	assert(source.get("exact_seek_only_enabled") != null)
	source.terminal_cache_enabled = false
	var end: float = source.editor.animation_player.get_animation(&"down").length
	var get_up_end: float = source.editor.animation_player.get_animation(&"get_up").length
	var requests: Array = [[&"walk_slash", 0.631], [&"walk_slash", 0.213],
		[&"down", end], [&"walk_slash", 0.517], [&"down", end], [&"down", end - 0.001],
		[&"down", 0.0], [&"down", end], [&"unconscious", 0.173], [&"get_up", 0.0],
		[&"get_up", get_up_end], [&"guard", 0.073]]
	var expected: Array[Dictionary] = []
	for pass_index in range(2):
		source.exact_seek_only_enabled = pass_index == 1
		source.clear_samples()
		assert(not source.sample(&"idle", 0.019, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline).is_empty())
		for index in range(requests.size()):
			var request: Array = requests[index]
			# Clear only result caches. Preserve the real preceding animation/pose
			# so reverse time and endpoint->B->endpoint cannot become cold fixtures.
			source.clear_samples()
			var before: int = source.profile_usec.pose
			var query := super.compare_pose(source, actor, baseline, request[0], request[1], Vector2i.RIGHT)
			var spent: int = int(source.profile_usec.pose) - before
			var snapshot := _snapshot(source, baseline, [request[0], request[1], Vector2i.RIGHT, Vector2.ZERO, 0.0], query)
			if pass_index == 0:
				expected.append(snapshot)
				old_pose_usec += spent
			else:
				assert(snapshot == expected[index], "Exact sequential seek boundary differs at request %d" % index)
				seek_pose_usec += spent
				exact_pairs += 1
	assert(source._terminal_poses.is_empty(), "Terminal reuse must not conceal animation evaluation in this test")
	source.dispose()
	actor.queue_free()
	await process_frame
