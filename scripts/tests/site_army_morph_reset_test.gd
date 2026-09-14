extends "res://scripts/tests/site_army_paused_assigned_test.gd"
## Independent original-lookup/unconditional-reset versus opt-in exact reset.
## GPU --group=0 (male) or 1 (female), internal 23 seconds / helper 25 seconds.
## Reuse only the existing full-pose snapshot helpers; never their run method.

var reset_snapshots: Array[Dictionary] = []
var reset_passes: Array[Dictionary] = []
var reset_pairs := 0
var reset_seed_snapshots: Array[Dictionary] = []
var reset_lookup_checks := 0
var reset_history_checks := 0
var reset_same_clip_checks := 0

func run() -> void:
	var deadline_us := Time.get_ticks_usec() + 23000000
	create_timer(23.0).timeout.connect(func() -> void:
		push_error("SITE_ARMY_MORPH_RESET deadline")
		quit(1))
	assert(group in [0, 1] and DisplayServer.get_name() != "headless")
	assert(TerrainArmy.load_combat_bake())
	var baseline: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	baseline.body = group
	# The soldier recipe is male: body alone cannot admit its hair_male_01 on
	# a female model. Keep all equipment, use this body's canonical default hair.
	baseline.parts.hair = HumanCharacter3DEditor.default_appearance(group).parts.hair
	assert(HumanCharacter3DEditor.valid_appearance(baseline), "Morph-reset fixture must be a legal body-specific appearance")
	var actor := TerrainTestCharacter.new()
	actor.visual_state.body_index = group
	root.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	assert(actor.editor != null and actor.editor.restore_appearance(baseline))
	actor.editor.set_process(false)
	actor.editor.combat_ready = true
	actor.editor.visual_state.combat_ready = true
	actor.editor.set_playing(false)
	var actor_morphs := _all_morphs(actor.editor)
	var down_end: float = actor.editor.animation_player.get_animation(&"down").length
	var bare := missing_recipe(baseline, 31)
	bare.parts.cape = "none"
	var armor := baseline.duplicate(true)
	armor.parts.armor = "armor_mingguang_01"
	armor.parts.helmet = "helmet_mingguang_01"
	armor.parts.outfit = "outfit_chinese_lining_01"
	armor.parts.boots = "boots_mingguang_01"
	armor.parts.cape = "cape_chinese_01"
	var no_shield := missing_recipe(baseline, 2)
	var requests: Array = [
		[&"walk_slash", 0.537, bare],
		[&"down", 1.137, armor],
		[&"down", down_end, armor],
		[&"get_up", 0.337, armor],
		[&"idle", 0.019, armor],
		[&"guard", 0.073, baseline],
		[&"walk_slash", 0.631, baseline],
		[&"walk_slash", 0.213, baseline],
		[&"down", down_end, bare],
		[&"get_up", 0.337, bare],
		[&"idle", 0.023, bare],
		[&"guard", 0.083, no_shield],
		[&"down", 0.417, armor],
		[&"idle", 0.031, armor],
	]
	for pass_index in range(2):
		# Recreate only the private source. Restore the same original raw Actor
		# before copying its animation resources, including all unworn morphs.
		_restore_morphs(actor.editor, actor_morphs)
		assert(actor.editor.restore_appearance(baseline))
		assert(actor.editor.select_animation_by_id(&"idle"))
		actor.editor.animation_player.seek(0.0, true)
		actor.editor.animation_player.advance(0.0)
		var source := Source.new()
		assert(source.initialize(root, baseline, actor.editor))
		var editor: Variant = source.editor
		editor.morph_reset_reuse_enabled = pass_index == 1
		editor.select_profile_enabled = true
		source.terminal_cache_enabled = false
		var source_id: int = editor.get_instance_id()
		var skeleton_id: int = source.skeleton.get_instance_id()
		assert(not source.sample(&"idle", 0.017, Vector2i.RIGHT, Vector2.ZERO, 0.0, bare).is_empty())
		var seeded := _seed_original_reset_morphs(editor)
		assert(int(seeded.hidden_armor) > 0 and int(seeded.hidden_cloth) > 0 and int(seeded.tiny_nonzero) > 0)
		assert(editor.select_animation_by_id(&"walk_slash"))
		# Inspect immediately BEFORE any seek can overwrite a failed reset.
		_assert_original_reset_zero(editor)
		var reset_state := {"morphs": _all_morphs(editor), "bones": []}
		for bone in range(source.skeleton.get_bone_count()):
			reset_state.bones.append(source.skeleton.get_bone_pose(bone))
		if pass_index == 0:
			reset_seed_snapshots.append(reset_state)
		else:
			assert(reset_state == reset_seed_snapshots[0], "Seeded hidden/tiny nonzero morphs and complete bone reset must match before seek")
		var began := Time.get_ticks_usec()
		for index in range(requests.size()):
			assert(Time.get_ticks_usec() < deadline_us, "Original 23 second deadline exceeded")
			var request: Array = requests[index]
			var full_request := [request[0], request[1], Vector2i.RIGHT, Vector2.ZERO, 0.0]
			source.clear_samples()
			if index == 5:
				editor.clear_component_lookup_cache()
				assert(not editor._component_nodes.has(&"clip_reset_armor"))
			var query: Dictionary = source.sample(request[0], request[1], Vector2i.RIGHT, Vector2.ZERO, 0.0, request[2])
			assert(not query.is_empty())
			var snapshot := _snapshot(source, request[2], full_request, query)
			snapshot.parts = editor.capture_appearance().parts
			snapshot.visibility = _held_visibility(editor)
			if pass_index == 0:
				reset_snapshots.append(snapshot)
			else:
				for field: String in snapshot:
					assert(snapshot[field] == reset_snapshots[index][field], "Strict reset A/B difference request %d / %s" % [index, field])
				reset_pairs += 1
			if index == 2:
				_cached_reset_history(source, request, query, snapshot, baseline)
			if index == 7:
				assert(source.sample(request[0], request[1], Vector2i.RIGHT, Vector2.ZERO, 0.0, request[2]) == query)
				_seed_original_reset_morphs(editor)
				var before_same_clip := _all_morphs(editor)
				editor._play_selected_animation()
				assert(_all_morphs(editor) == before_same_clip, "Same assigned clip must not introduce a reset")
				reset_same_clip_checks += 1
			assert(editor.get_instance_id() == source_id and source.skeleton.get_instance_id() == skeleton_id)
		if pass_index == 1:
			_lookup_invalidation(editor)
		else:
			assert(not editor._component_nodes.has(&"clip_reset_armor"), "Disabled path must execute the original query")
		reset_passes.append({"enabled": pass_index == 1, "elapsed_usec": Time.get_ticks_usec() - began,
			"select_profile_usec": editor.select_profile_usec.duplicate(), "seeded_original_morphs": seeded})
		source.dispose()
		await process_frame
	assert(Time.get_ticks_usec() < deadline_us and reset_pairs == 14 and reset_history_checks == 2 and reset_same_clip_checks == 2 and reset_lookup_checks >= 7)
	var report := {"group": group, "body": "male" if group == 0 else "female",
		"exact_pairs": reset_pairs, "maximum_error": 0.0, "passes": reset_passes,
		"lookup_checks": reset_lookup_checks, "history_checks": reset_history_checks,
		"same_clip_checks": reset_same_clip_checks, "pre_seek_seed_checks": 2,
		"source_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd"),
		"scope": "Original ordered searches/unconditional morph setters versus opt-in fixed-private lookup and exact current-value guards. Full bones, every original morph including unworn, worn armor vertices, shapes and protection; no FPS claim."}
	var path := "res://output/site_combat_performance_20260913/morph_reset/group_%d.json" % group
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	actor.queue_free()
	await process_frame
	print("SITE_ARMY_MORPH_RESET_PASS ", JSON.stringify(report))
	quit(0)

func _seed_original_reset_morphs(editor: Variant) -> Dictionary:
	var nodes: Array = editor.model_root.find_children("Armor_Mingguang_01_*", "MeshInstance3D", true, false)
	for record: Dictionary in editor._combat_cloth:
		if is_instance_valid(record.node):
			nodes.append(record.node)
	var result := {"shapes": 0, "hidden_armor": 0, "hidden_cloth": 0, "tiny_nonzero": 0}
	var values: Array[float] = [0.375, -0.125, 0.0, 1.0e-20]
	for node: MeshInstance3D in nodes:
		for shape in range(node.get_blend_shape_count()):
			var value: float = values[int(result.shapes) % values.size()]
			node.set_blend_shape_value(shape, value)
			if value != 0.0:
				assert(node.get_blend_shape_value(shape) != 0.0)
				if not node.visible:
					var field := "hidden_armor" if str(node.name).begins_with("Armor_Mingguang_") else "hidden_cloth"
					result[field] += 1
				result.tiny_nonzero += int(value == 1.0e-20)
			result.shapes += 1
	return result

func _assert_original_reset_zero(editor: Variant) -> void:
	for node: MeshInstance3D in editor.model_root.find_children("Armor_Mingguang_01_*", "MeshInstance3D", true, false):
		for shape in range(node.get_blend_shape_count()):
			assert(node.get_blend_shape_value(shape) == 0.0)
	for record: Dictionary in editor._combat_cloth:
		var node := record.node as MeshInstance3D
		if is_instance_valid(node):
			for shape in range(node.get_blend_shape_count()):
				assert(node.get_blend_shape_value(shape) == 0.0)

func _cached_reset_history(source: Variant, request: Array, query: Dictionary, expected: Dictionary, baseline: Dictionary) -> void:
	var key_a: Array = source._key.duplicate(true)
	assert(not source.sample(&"idle", 0.419, Vector2i.UP, Vector2.ZERO, 0.0, baseline).is_empty())
	var key_b: Array = source._key.duplicate(true)
	assert(key_a != key_b)
	assert(source.sample(request[0], request[1], Vector2i.RIGHT, Vector2.ZERO, 0.0, request[2]) == query)
	assert(source._key == key_b, "Cached sample must not pretend to restore the private rig")
	source.armor_at(request[0], request[1], Vector2i.RIGHT, centre(query.body[0]), "slash", Vector2.ZERO, 0.0, request[2])
	assert(source._key == key_a)
	var snapshot := _snapshot(source, request[2], [request[0], request[1], Vector2i.RIGHT, Vector2.ZERO, 0.0], query)
	snapshot.parts = source.editor.capture_appearance().parts
	snapshot.visibility = _held_visibility(source.editor)
	assert(snapshot == expected, "Armor lookup after cached A must restore its original reset/seek history exactly")
	reset_history_checks += 1

func _lookup_invalidation(editor: Variant) -> void:
	var original_model: Node3D = editor.model_root
	var expected: Array = original_model.find_children("Armor_Mingguang_01_*", "MeshInstance3D", true, false)
	assert(editor._armor_nodes_for_reset() == expected)
	assert(is_same(editor._armor_nodes_for_reset(), editor._component_nodes[&"clip_reset_armor"]))
	reset_lookup_checks += 2
	editor.clear_component_lookup_cache()
	assert(not editor._component_nodes.has(&"clip_reset_armor"))
	assert(editor._armor_nodes_for_reset() == expected)
	reset_lookup_checks += 1
	# Explicit same-root hierarchy invalidation, with a non-rendering probe only.
	var probe := MeshInstance3D.new()
	probe.name = "Armor_Mingguang_01_ResetProbe"
	original_model.add_child(probe)
	editor.clear_component_lookup_cache()
	assert(editor._armor_nodes_for_reset() == original_model.find_children("Armor_Mingguang_01_*", "MeshInstance3D", true, false))
	assert(editor._armor_nodes_for_reset().has(probe))
	original_model.remove_child(probe)
	probe.free()
	editor.clear_component_lookup_cache()
	assert(editor._armor_nodes_for_reset() == expected)
	reset_lookup_checks += 1
	# A temporary empty root checks actual identity invalidation; no pose query
	# runs with it, no character/body/animation is copied or created.
	var temporary_root := Node3D.new()
	root.add_child(temporary_root)
	editor.model_root = temporary_root
	assert(editor._armor_nodes_for_reset().is_empty())
	assert(editor._component_model_id == temporary_root.get_instance_id())
	editor.model_root = original_model
	assert(editor._armor_nodes_for_reset() == expected)
	assert(editor._component_model_id == original_model.get_instance_id())
	temporary_root.free()
	reset_lookup_checks += 1
	editor.morph_reset_reuse_enabled = false
	assert(not editor._component_nodes.has(&"clip_reset_armor"))
	assert(editor._armor_nodes_for_reset() == expected and not editor._component_nodes.has(&"clip_reset_armor"))
	editor.morph_reset_reuse_enabled = true
	assert(editor._armor_nodes_for_reset() == expected)
	reset_lookup_checks += 1
	editor.clear_component_lookup_cache()
	editor.component_lookup_enabled = false
	assert(editor._armor_nodes_for_reset() == expected and not editor._component_nodes.has(&"clip_reset_armor"))
	editor.enable_component_lookup_cache()
	assert(editor._armor_nodes_for_reset() == expected)
	reset_lookup_checks += 1
