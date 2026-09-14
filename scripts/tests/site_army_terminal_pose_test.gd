extends "res://scripts/tests/site_army_equipment_query_test.gd"
## GPU --group=0: exact terminal A/B, original owner, interleaving and invalidation.
## GPU --group=1: 65 real exact-key samples exercise the independent 64-entry cap.
## No atlas, clock/HP change, extra production rig or gameplay/FPS claim.

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	assert(DisplayServer.get_name() != "headless", "Original morph projection requires the GPU verifier")
	assert(group in [0, 1] and TerrainArmy.load_combat_bake())
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
	var editor_id := source.editor.get_instance_id()
	var skeleton_id := source.skeleton.get_instance_id()
	var end: float = source.editor.animation_player.get_animation(&"down").length
	assert(end > 0.0 and source.TERMINAL_POSE_LIMIT == 64)
	if group == 0:
		for index in range(4):
			var appearance := missing_recipe(baseline, [0, 2, 12, 31][index])
			_exact_terminal(source, actor, baseline, appearance, end, TerrainData.DIRECTIONS[index])
		_boundaries(source, baseline, end)
	else:
		_limit(source, baseline, end)
	assert(source.editor.get_instance_id() == editor_id and source.skeleton.get_instance_id() == skeleton_id)
	assert(source._poses.size() <= 128 and source._terminal_poses.size() <= 64)
	source.dispose()
	assert(source._poses.is_empty() and source._terminal_poses.is_empty())
	actor.queue_free()
	await process_frame
	print("SITE ARMY TERMINAL POSE PASS: group=", group,
		"; exact original local geometry, bounded completed-down reuse, original armor restoration; not full combat/FPS")
	quit(0)

func _bones(source: Variant) -> Array:
	var result: Array = []
	for bone in range(source.skeleton.get_bone_count()):
		result.append([source.skeleton.get_bone_pose_position(bone), source.skeleton.get_bone_pose_rotation(bone),
			source.skeleton.get_bone_pose_scale(bone), source.skeleton.get_bone_global_pose(bone)])
	return result

func _armor_vertices(source: Variant, appearance: Dictionary) -> Dictionary:
	var result := {}
	var proxy := {"editor": source.editor, "player_sprite": source.sprite}
	for slot: StringName in [&"helmet", &"armor", &"outfit", &"boots"]:
		var item := StringName(str(appearance.parts[str(slot)]))
		if item == &"none":
			continue
		var component: Dictionary = source.editor._component_definition(slot, item)
		for node: Node in source.editor._find_component_nodes(component.get("prefixes", [])):
			var mesh := node as MeshInstance3D
			if mesh == null or not mesh.is_visible_in_tree() or mesh.mesh == null:
				continue
			var morphs: Array[float] = []
			for shape in range(mesh.get_blend_shape_count()):
				morphs.append(mesh.get_blend_shape_value(shape))
			result[source.editor.model_root.get_path_to(mesh)] = [morphs, source.geometry.posed_points(proxy, mesh, source.skeleton)]
	return result

func _exact_terminal(source: Variant, actor: TerrainTestCharacter, baseline: Dictionary, appearance: Dictionary, end: float, direction: Vector2i) -> void:
	var interlude := missing_recipe(baseline, 31) if appearance.parts != missing_recipe(baseline, 31).parts else baseline
	source.terminal_cache_enabled = false
	source.clear_samples()
	assert(not source.sample(&"idle", 0.017, Vector2i.DOWN, Vector2.ZERO, 0.0, interlude).is_empty())
	# The unmodified original HumanEditor remains the independent owner reference;
	# its existing exact protection checks and boundary checks are still applied.
	var expected := compare_pose(source, actor, appearance, &"down", end, direction).duplicate(true)
	var expected_bones := _bones(source)
	var expected_armor := _armor_vertices(source, appearance)
	var point := centre(expected.body[0])
	var protection: Vector2 = source.armor_at(&"down", end, direction, point, "slash", Vector2.ZERO, 0.0, appearance)
	assert(source._terminal_poses.is_empty())
	source.terminal_cache_enabled = true
	source.clear_samples()
	assert(not source.sample(&"idle", 0.017, Vector2i.DOWN, Vector2.ZERO, 0.0, interlude).is_empty())
	assert(source.sample(&"down", end, direction, Vector2.ZERO, 0.0, appearance) == expected)
	assert(_bones(source) == expected_bones and _armor_vertices(source, appearance) == expected_armor)
	assert(source._terminal_poses.size() == 1)
	for step in range(3):
		source.begin_contact_step()
		assert(source._poses.is_empty() and source._terminal_poses.size() == 1)
		assert(not source.sample(&"walk_slash", 0.417 + float(step) / 120.0, Vector2i.RIGHT, Vector2.ZERO, 0.0, interlude).is_empty())
		var live_key: Array = source._key.duplicate(true)
		var live_bones := _bones(source)
		var before: Dictionary = source.profile_usec.duplicate(true)
		var cached: Dictionary = source.sample(&"down", end, direction, Vector2.ZERO, 0.0, appearance)
		assert(cached == expected, "Every scalar, polygon vertex and bound must be exactly equal")
		assert(source.profile_usec == before, "A terminal result hit must not evaluate the editor or any collider")
		assert(source._key == live_key and _bones(source) == live_bones, "A cached A must not pretend the live editor left B")
		var origin := Vector2(137.25 + float(step) * 0.75, -53.125)
		var world := Geometry.shifted(cached.body, origin)
		for index in range(cached.body.size()):
			assert(world[index] == Transform2D(0.0, origin) * expected.body[index])
		assert(cached.body == expected.body, "World movement shifts newly allocated shapes, never retained local vertices")
		# A caller mutating its result must not poison the next contact step.
		cached.body.clear()
		cached.shoulder = Vector2(INF, INF)
		source.begin_contact_step()
		assert(source.sample(&"down", end, direction, Vector2.ZERO, 0.0, appearance) == expected)
		assert(source.armor_at(&"down", end, direction, point, "slash", Vector2.ZERO, 0.0, appearance) == protection)
		assert(_bones(source) == expected_bones and _armor_vertices(source, appearance) == expected_armor,
			"The original armor lookup restores A's exact scalar morphs, bones and every worn projected vertex")
	# Equipment full-clear remains the existing shared entry point. Force a real
	# intermediate pose so this checks recomputation, not the live _key fast path.
	assert(not source.sample(&"idle", 0.219, Vector2i.LEFT, Vector2.ZERO, 0.0, interlude).is_empty())
	source.clear_samples()
	assert(source._poses.is_empty() and source._terminal_poses.is_empty())
	var before: int = source.profile_usec.pose
	assert(source.sample(&"down", end, direction, Vector2.ZERO, 0.0, appearance) == expected)
	assert(int(source.profile_usec.pose) > before and source._terminal_poses.size() == 1)

func _boundaries(source: Variant, baseline: Dictionary, end: float) -> void:
	source.clear_samples()
	for request: Array in [[&"down", end - 0.000001], [&"down", end + 0.000001], [&"unconscious", 0.173], [&"get_up", 0.337]]:
		assert(not source.sample(request[0], request[1], Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline).is_empty())
		assert(source._terminal_poses.is_empty(), "No rounding, clamping or non-down cross-step reuse")
	assert(not source.sample(&"down", end, Vector2i.RIGHT, Vector2(9.0, 4.0), 0.01, baseline).is_empty())
	assert(source._terminal_poses.is_empty(), "Aimed poses retain the original per-step path")
	var mutable := baseline.duplicate(true)
	assert(not source.sample(&"down", end, Vector2i.RIGHT, Vector2.ZERO, 0.0, mutable).is_empty())
	mutable.parts.shield = "none"
	assert(source.sample(&"down", end, Vector2i.RIGHT, Vector2.ZERO, 0.0, mutable).shield.is_empty())
	assert(source._terminal_poses.size() == 2, "Actual equipment is part of the retained immutable value key")
	source.begin_contact_step()
	assert(not source.sample(&"down", end, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline).shield.is_empty())
	# The source's only supported animation-generation replacement must clear all
	# result caches and preserve the existing owned current-pose reset contract.
	source._copy_private_animations()
	assert(source._poses.is_empty() and source._terminal_poses.is_empty() and source._key.is_empty())

func _limit(source: Variant, baseline: Dictionary, end: float) -> void:
	source.clear_samples()
	var expected: Dictionary = source.sample(&"down", end, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline).duplicate(true)
	for index in range(1, 65):
		source.begin_contact_step()
		# Aim is ineffective at weight zero but remains part of the exact full key.
		# These are real sample evaluations, not synthetic dictionary insertions.
		assert(source.sample(&"down", end, Vector2i.RIGHT, Vector2(float(index), 0.0), 0.0, baseline) == expected)
		assert(source._poses.size() <= 128 and source._terminal_poses.size() <= 64)
		assert(source._terminal_poses.size() == (index + 1 if index < 64 else 1))
	assert(source._terminal_poses.size() == 1, "The 65th exact terminal key clears only the bounded terminal store")
	assert(source._poses.size() == 1, "Terminal capacity never changes the original 128-entry per-step cache")
