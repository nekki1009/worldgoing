extends "res://scripts/tests/site_army_constant_morph_test.gd"
## GPU --group=0 metadata/guards, --group=1 exact query history.
## Each group internal 53s/helper 55s, including full original-library digests.
## Cape values are NOT asserted equivalent.
## Reuses the original numeric/path oracle; no new rig or animation evaluator.

var cape_report := {"exact_pairs": 0, "actor_checks": 0, "guards": 0, "passes": []}

func run() -> void:
	var started := Time.get_ticks_usec()
	morph_deadline_usec = started + 53000000
	create_timer(53.0).timeout.connect(func() -> void: push_error("Cape query deadline"); quit(1))
	assert(group in [0, 1] and DisplayServer.get_name() != "headless")
	var source_hash := FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd")
	var raw_hash := FileAccess.get_sha256(HumanCharacter3DEditor.MALE_MODEL_PATH)
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
	source.constant_morph_keys_enabled = false # Isolate this change: every raw key remains.
	source.cape_track_omission_enabled = false # Explicit original path after production admission.
	assert(source.initialize(root, baseline, actor.editor))
	source.terminal_cache_enabled = false
	var editor_id := source.editor.get_instance_id()
	var skeleton_id := source.skeleton.get_instance_id()
	if group == 0:
		_metadata_cases(source, actor)
	else:
		_history_cases(source, actor, baseline)
	assert(bool(cape_report.get("complete", false)), "Nested failure cannot fall through to PASS")
	assert(source.editor.get_instance_id() == editor_id and source.skeleton.get_instance_id() == skeleton_id)
	assert(FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd") == source_hash)
	assert(FileAccess.get_sha256(HumanCharacter3DEditor.MALE_MODEL_PATH) == raw_hash)
	cape_report.merge({"group": group, "elapsed_usec": Time.get_ticks_usec() - started,
		"internal_deadline_seconds": 53, "helper_timeout_seconds": 55,
		"source_sha256": source_hash, "raw_sha256": raw_hash, "maximum_query_error": 0.0,
		"original_actor_boundary_error": maximum_error,
		"scope": "Same private Source, actual original Actor reference, all collider fields/non-Cape morphs/bones/worn armor/protection exact A/B. Cape scalar values intentionally excluded: private query owner is not rendered. Actor geometry retains its existing <0.01 projection boundary contract; no FPS or all-morph/render equivalence claim."})
	var directory := "res://output/site_combat_performance_20260913/cape_query/group%d_%d_%d" % [group, int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK)
	var file := FileAccess.open(directory + "/measurements.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(cape_report, "\t"))
	file.close()
	source.dispose()
	actor.queue_free()
	await process_frame
	_deadline()
	print("SITE_ARMY_CAPE_QUERY_PASS ", JSON.stringify(cape_report))
	quit(0)

func _metadata_cases(source: Variant, actor: TerrainTestCharacter) -> void:
	var reference := actor.editor.animation_player
	var reference_clips := reference.get_animation_list()
	var original := _player_digest(reference)
	assert(_player_digest(source.editor.animation_player) == original)
	source.cape_track_omission_enabled = true
	source._copy_private_animations(reference)
	assert(source.editor.animation_player.get_animation_list() == reference_clips)
	var counts := {"clips": 0, "tracks": 0, "keys": 0, "disabled": 0, "expected_disabled": 0,
		"reference_clips": reference_clips.size()}
	var animation_root: Node = source.editor.animation_player.get_node(source.editor.animation_player.root_node)
	for clip: StringName in reference_clips:
		_deadline()
		var before := reference.get_animation(clip)
		var after: Animation = source.editor.animation_player.get_animation(clip)
		assert(before != after and before.get_track_count() == after.get_track_count())
		assert(before.length == after.length and before.loop_mode == after.loop_mode and before.step == after.step)
		for property: Dictionary in before.get_property_list():
			var name := str(property.name)
			if name in ["markers", "_compression"]:
				assert(var_to_bytes(before.get(name)) == var_to_bytes(after.get(name)))
		for track in range(before.get_track_count()):
			var path := before.track_get_path(track)
			var target := animation_root.get_node_or_null(NodePath(path.get_concatenated_names())) as MeshInstance3D
			# Derive the expected transition from the original metadata and actual
			# private-model target, independently of the helper's return count.
			var omitted: bool = before.track_get_type(track) == Animation.TYPE_BLEND_SHAPE \
				and before.track_is_enabled(track) and not path.is_absolute() and path.get_subname_count() == 1 \
				and target != null and target.get_script() == null and source.editor.model_root.is_ancestor_of(target) \
				and str(target.name).begins_with("Cape_") and target.mesh != null \
				and target.find_blend_shape_by_name(path.get_subname(0)) >= 0
			var expected_metadata := _metadata(before, track)
			expected_metadata[2] = false if omitted else before.track_is_enabled(track)
			assert(_metadata(after, track) == expected_metadata)
			assert(before.track_get_key_count(track) == after.track_get_key_count(track))
			assert(var_to_bytes(before.get("tracks/%d/keys" % track)) == var_to_bytes(after.get("tracks/%d/keys" % track)))
			if before.track_is_compressed(track):
				assert(before.get("tracks/%d/compressed_track" % track) == after.get("tracks/%d/compressed_track" % track))
			counts.tracks += 1
			counts.keys += before.track_get_key_count(track)
			counts.expected_disabled += int(omitted)
			counts.disabled += int(before.track_is_enabled(track) and not after.track_is_enabled(track))
		counts.clips += 1
	assert(counts.clips == reference_clips.size() and counts.clips > 0 and counts.keys > 0)
	assert(counts.disabled == counts.expected_disabled and counts.disabled > 0)
	assert(_player_digest(reference) == original, "Private enable edits never mutate the original Actor animations")
	_guard_cases(source, actor)
	source.cape_track_omission_enabled = false
	source._copy_private_animations(reference)
	assert(_player_digest(source.editor.animation_player) == original, "Explicit recopy with flag false restores all original tracks/keys")
	cape_report.metadata = counts
	cape_report.complete = true

func _guard_cases(source: Variant, actor: TerrainTestCharacter) -> void:
	var animation_root: Node = source.editor.animation_player.get_node(source.editor.animation_player.root_node)
	var cape := source.editor.model_root.find_child("Cape_Travel_01_Main", true, false) as MeshInstance3D
	assert(cape != null and cape.get_blend_shape_count() > 0)
	var original_path := NodePath(str(animation_root.get_path_to(cape)) + ":" + str(cape.mesh.get_blend_shape_name(0)))
	var fixture := Animation.new()
	fixture.length = 1.0
	var track := fixture.add_track(Animation.TYPE_BLEND_SHAPE)
	fixture.track_set_path(track, original_path)
	fixture.blend_shape_track_insert_key(track, 0.0, 0.375)
	fixture.blend_shape_track_insert_key(track, 1.0, -0.125)
	var keys := var_to_bytes(fixture.get("tracks/0/keys"))
	assert(source._disable_private_cape_tracks(fixture) == 1 and not fixture.track_is_enabled(track))
	assert(var_to_bytes(fixture.get("tracks/0/keys")) == keys)
	assert(source._disable_private_cape_tracks(fixture) == 0)
	cape_report.guards += 2
	var external := actor.editor.model_root.find_child(str(cape.name), true, false) as MeshInstance3D
	assert(external != null)
	for path: NodePath in [NodePath(str(cape.get_path()) + ":" + str(cape.mesh.get_blend_shape_name(0))),
		NodePath(str(animation_root.get_path_to(external)) + ":" + str(external.mesh.get_blend_shape_name(0))),
		NodePath(str(animation_root.get_path_to(cape)) + ":MissingMorph"),
		NodePath(str(original_path) + ":extra"), NodePath("MissingCape:Shape")]:
		fixture.track_set_enabled(track, true)
		fixture.track_set_path(track, path)
		assert(source._disable_private_cape_tracks(fixture) == 0 and fixture.track_is_enabled(track))
		cape_report.guards += 1
	fixture.track_set_path(track, original_path)
	var script := GDScript.new()
	script.source_code = "extends MeshInstance3D\n"
	assert(script.reload() == OK)
	cape.set_script(script)
	assert(source._disable_private_cape_tracks(fixture) == 0 and fixture.track_is_enabled(track))
	cape.set_script(null)
	var position := fixture.add_track(Animation.TYPE_POSITION_3D)
	fixture.track_set_path(position, NodePath(str(animation_root.get_path_to(cape))))
	fixture.position_track_insert_key(position, 0.0, Vector3.ZERO)
	assert(source._disable_private_cape_tracks(fixture) == 1 and fixture.track_is_enabled(position))
	cape_report.guards += 2
	_deadline()

func _history_cases(source: Variant, actor: TerrainTestCharacter, baseline: Dictionary) -> void:
	var metal := baseline.duplicate(true)
	metal.parts.merge({"armor": "armor_mingguang_01", "helmet": "helmet_mingguang_01", "outfit": "outfit_chinese_lining_01", "boots": "boots_mingguang_01", "cape": "cape_chinese_01"}, true)
	var no_shield := missing_recipe(metal, 2)
	var no_cape := metal.duplicate(true)
	no_cape.parts.cape = "none"
	var bare := missing_recipe(baseline, 31)
	bare.parts.cape = "none"
	var travel := baseline.duplicate(true)
	travel.parts.cape = "cape_travel_01"
	var down_end: float = actor.editor.animation_player.get_animation(&"down").length
	var requests: Array = [[&"down", 1.137, Vector2i.RIGHT, metal], [&"get_up", 0.337, Vector2i.DOWN, metal],
		[&"idle", 0.019, Vector2i.UP, metal], [&"guard", 0.073, Vector2i.LEFT, no_shield],
		[&"walk_slash", 0.631, Vector2i.DOWN, bare], [&"walk_slash", 0.213, Vector2i.UP, travel],
		[&"down", 0.417, Vector2i.LEFT, no_cape], [&"get_up", 0.437, Vector2i.RIGHT, no_cape],
		[&"idle", 0.023, Vector2i.DOWN, baseline], [&"guard", 0.093, Vector2i.UP, travel],
		[&"down", down_end, Vector2i.LEFT, metal], [&"idle", 0.031, Vector2i.RIGHT, metal]]
	var expected: Array[Dictionary] = []
	var actor_loops := {}
	for clip: StringName in actor.editor.animation_player.get_animation_list():
		actor_loops[clip] = actor.editor.animation_player.get_animation(clip).loop_mode
	var original_library := _player_digest(actor.editor.animation_player)
	for pass_index in range(2):
		source.cape_track_omission_enabled = pass_index == 1
		source._copy_private_animations(actor.editor.animation_player)
		source.editor._selected_animation = &""
		assert(source.editor.select_animation_by_id(&"idle"))
		source.skeleton.reset_bone_poses()
		source.clear_samples()
		assert(not source.sample(&"idle", 0.011, Vector2i.DOWN, Vector2.ZERO, 0.0, baseline).is_empty())
		var hidden_nonzero := _seed_capes(source.editor)
		assert(hidden_nonzero > 0, "Real hidden Cape shapes have nonzero history before any following query")
		var began := Time.get_ticks_usec()
		var before_profile: Dictionary = source.query_profile.duplicate()
		for index in range(requests.size()):
			_deadline()
			var request: Array = requests[index]
			source.begin_contact_step()
			var query: Dictionary = source.sample(request[0], request[1], request[2], Vector2.ZERO, 0.0, request[3])
			assert(not query.is_empty())
			var snapshot := _query_snapshot(source, request, query)
			if pass_index == 0:
				expected.append(snapshot)
			else:
				var differences: Array[Dictionary] = []
				_snapshot_byte_diff(expected[index], snapshot, "$", differences)
				assert(differences.is_empty(), "Exact non-Cape query difference: " + str(differences))
				cape_report.exact_pairs += 1
			if index < 4:
				_actor_reference(actor, source, request, query)
				for clip: StringName in actor_loops:
					actor.editor.animation_player.get_animation(clip).loop_mode = actor_loops[clip]
			if index == 0:
				var key_a: Array = source._key.duplicate(true)
				assert(not source.sample(&"idle", 0.719, Vector2i.UP, Vector2.ZERO, 0.0, bare).is_empty())
				var key_b: Array = source._key.duplicate(true)
				assert(key_a != key_b and source.sample(request[0], request[1], request[2], Vector2.ZERO, 0.0, request[3]) == query)
				assert(source._key == key_b)
				source.armor_at(request[0], request[1], request[2], centre(query.body[0]), "slash", Vector2.ZERO, 0.0, request[3])
				assert(source._key == key_a and _query_snapshot(source, request, query) == snapshot)
		cape_report.passes.append({"enabled": pass_index == 1, "elapsed_usec": Time.get_ticks_usec() - began,
			"seek_usec": int(source.query_profile.seek_usec) - int(before_profile.seek_usec), "hidden_nonzero_cape_shapes": hidden_nonzero})
		assert(_player_digest(actor.editor.animation_player) == original_library, "Source changes do not alter original Actor resources")
	assert(cape_report.exact_pairs == 12 and cape_report.actor_checks == 8)
	cape_report.complete = true

func _seed_capes(editor: Variant) -> int:
	var hidden := 0
	for node: Node in editor.model_root.find_children("Cape_*", "MeshInstance3D", true, false):
		var cape := node as MeshInstance3D
		for shape in range(cape.get_blend_shape_count()):
			cape.set_blend_shape_value(shape, 0.375 if shape % 2 == 0 else -0.125)
			hidden += int(not cape.is_visible_in_tree())
	return hidden

func _query_snapshot(source: Variant, request: Array, query: Dictionary) -> Dictionary:
	var result := _snapshot(source, request[3], [request[0], request[1], request[2], Vector2.ZERO, 0.0], query)
	# Exact output contract is explicit: all original non-Cape morph values
	# remain checked, including unworn Mingguang, helmet plume and bow string.
	for path: NodePath in result.morphs.keys():
		var node: Node = source.editor.model_root.get_node(path)
		if str(node.name).begins_with("Cape_"):
			result.morphs.erase(path)
	result.parts = source.editor.capture_appearance().parts
	return result

func _actor_reference(actor: TerrainTestCharacter, source: Variant, request: Array, query: Dictionary) -> void:
	assert(actor.editor.restore_appearance(request[3]))
	actor.facing = request[2]
	actor.editor.set_preview_yaw_degrees({Vector2i.DOWN: 0.0, Vector2i.UP: 180.0, Vector2i.LEFT: -90.0, Vector2i.RIGHT: 90.0}[request[2]])
	actor.play_pose(request[0])
	actor.editor.animation_player.seek(request[1], true)
	actor.editor.animation_player.advance(0.0)
	actor.editor._update_combat_props()
	actor.editor._update_scabbard_pose()
	actor.editor._update_combat_cloth()
	actor._sync_render_projection()
	actor.guarding = actor.editor.selected_animation in [&"guard", &"guard_weapon", &"guard_polearm"]
	actor.guard_transition_left = 0.0
	actor.guard_break_left = 0.0
	var original := actor.incoming_geometry()
	original.weapon = actor._geometry.weapon_shapes(actor, actor.editor._resolve_weapon_attack_animation())
	for kind: String in original:
		maximum_error = maxf(maximum_error, shape_error(original[kind], query[kind]))
		assert(maximum_error < 0.01, "Existing original Actor projection boundary, not a relaxed A/B tolerance")
	for limb: int in [0, 3, 7, 9]:
		var point := centre(original.body[limb])
		assert(actor._geometry.armor_at(actor, point, "slash") == source.armor_at(request[0], request[1], request[2], point, "slash", Vector2.ZERO, 0.0, request[3]))
	cape_report.actor_checks += 1
