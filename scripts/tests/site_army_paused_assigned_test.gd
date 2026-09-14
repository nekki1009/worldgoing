extends "res://scripts/tests/site_army_exact_seek_test.gd"
## GPU --group=0; one original raw actor and one serially recreated query owner.
## Internal 23 seconds / unchanged canonical helper 25 seconds. No FPS claim.
var assigned_snapshots: Array[Dictionary] = []
var assigned_passes: Array[Dictionary] = []
var assigned_pairs := 0
var applied_count := 0
var original_actor_checks := 0
var fallback_checks := 0
var classification_checks := 0
var classification_timing := {}

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void:
		push_error("SITE_ARMY_PAUSED_ASSIGNED deadline")
		quit(1))
	assert(group == 0 and DisplayServer.get_name() != "headless")
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
	var actor_morphs := _all_morphs(actor.editor)
	var down_end: float = actor.editor.animation_player.get_animation(&"down").length
	var get_up_end: float = actor.editor.animation_player.get_animation(&"get_up").length
	var stripped := missing_recipe(baseline, 31)
	var no_shield := missing_recipe(baseline, 2)
	var bow := baseline.duplicate(true)
	bow.parts.weapon = "bow_01"
	var requests: Array = [
		[&"idle", 0.019, baseline],
		[&"walk_slash", 0.631, baseline],
		[&"walk_slash", 0.213, baseline], # Same-clip backwards exact seek.
		[&"down", down_end, baseline],
		[&"guard", 0.073, baseline],
		[&"down", down_end, baseline], # Cold caches after a terminal->other->terminal sequence.
		[&"down", down_end - 0.001, baseline],
		[&"get_up", 0.337, stripped],
		[&"get_up", get_up_end, baseline],
		[&"guard", 0.083, no_shield],
		[&"attack_unarmed", 0.233, stripped],
		[&"attack_bow", 0.437, bow],
		[&"reload_bow", 0.219, bow],
		[&"guard", 0.093, baseline],
	]
	for pass_index in range(2):
		# Identical original actor history, including unselected original morphs.
		_restore_morphs(actor.editor, actor_morphs)
		assert(actor.editor.restore_appearance(baseline))
		assert(actor.editor.select_animation_by_id(&"idle"))
		actor.editor.animation_player.seek(0.0, true)
		actor.editor.animation_player.advance(0.0)
		var source := Source.new()
		assert(source.initialize(root, baseline, actor.editor))
		var editor: Variant = source.editor
		assert(not editor.animation_player.is_playing())
		editor.paused_assigned_playback_enabled = pass_index == 1
		source.terminal_cache_enabled = false
		source.exact_seek_only_enabled = true
		# No synthetic advance/pause prepares candidate startup. Its original
		# initialization and first native seek own any residual started flag.
		editor.animation_player.mixer_applied.connect(func() -> void: applied_count += 1)
		var source_id: int = editor.get_instance_id()
		var skeleton_id: int = source.skeleton.get_instance_id()
		var applied_before := applied_count
		var measured_queries: Array[Dictionary] = []
		var began := Time.get_ticks_usec()
		for index in range(requests.size()):
			var request: Array = requests[index]
			var full_request := [request[0], request[1], Vector2i.RIGHT, Vector2.ZERO, 0.0]
			source.clear_samples() # Retain actual previous pose, clear result/memo only.
			if index in [0, 5]:
				editor.animation_player.clear_caches() # Deliberate cold native track cache on BOTH paths.
			var before_query := applied_count
			var query: Dictionary = source.sample(request[0], request[1], Vector2i.RIGHT, Vector2.ZERO, 0.0, request[2])
			assert(not query.is_empty())
			var snapshot := _snapshot(source, request[2], full_request, query)
			snapshot.parts = editor.capture_appearance().parts
			snapshot.selected_animation = str(editor.selected_animation)
			snapshot.visibility = _held_visibility(editor)
			# Playing state is intentionally different, never compared as geometry.
			if pass_index == 0:
				assigned_snapshots.append(snapshot)
			else:
				for field: String in assigned_snapshots[index]:
					assert(snapshot[field] == assigned_snapshots[index][field], "Strict assigned A/B difference request %d / %s" % [index, field])
				assigned_pairs += 1
				assert(not editor.animation_player.is_playing(), "The candidate must never re-enter native playback")
			measured_queries.append({"clip": str(request[0]), "time": request[1], "mixer_applications": applied_count - before_query})
			if index in [1, 3, 8, 10]:
				_original_actor_reference(actor, source, request, query)
			assert(editor.get_instance_id() == source_id and source.skeleton.get_instance_id() == skeleton_id)
		if pass_index == 1:
			assert(int(editor.assigned_playback_profile.assignments) > 0 and int(editor.assigned_playback_profile.fallbacks) == 0,
				"Candidate must exercise actual guarded setter, not silently fall back")
			assert(applied_count - applied_before < int(assigned_passes[0].mixer_applications), "Avoid at least one real extra zero-time evaluation")
			_classification_invalidation(editor, source, actor)
			_guard_fallbacks(editor)
		assigned_passes.append({"enabled": pass_index == 1, "mixer_applications": applied_count - applied_before,
			"elapsed_usec": Time.get_ticks_usec() - began, "queries": measured_queries,
			"profile": editor.assigned_playback_profile.duplicate()})
		source.dispose()
		await process_frame
	var report := {"group": group, "exact_pairs": assigned_pairs, "maximum_error": 0.0,
		"passes": assigned_passes, "original_actor_checks": original_actor_checks, "original_actor_shape_bound": maximum_error,
		"fallback_checks": fallback_checks, "classification_checks": classification_checks, "classification_timing": classification_timing,
		"source_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd"),
		"scope": "Original manual play/seek source versus opt-in paused assigned/seek; exact all bones, all morphs, armor vertices/protection, shapes and visibility. Original raw Actor separately checks existing projected shape bound and exact protection. Not FPS."}
	var path := "res://output/site_combat_performance_20260913/paused_assigned/group_0_cached_v2.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	actor.queue_free()
	await process_frame
	assert(assigned_pairs == 14 and original_actor_checks == 8 and fallback_checks >= 8 and classification_checks >= 8)
	print("SITE_ARMY_PAUSED_ASSIGNED_PASS ", JSON.stringify(report))
	quit(0)

func _original_actor_reference(actor: TerrainTestCharacter, source: Variant, request: Array, query: Dictionary) -> void:
	assert(actor.editor.restore_appearance(request[2]))
	actor.facing = Vector2i.RIGHT
	actor.editor.set_preview_yaw_degrees(90.0)
	actor.play_pose(request[0])
	actor.editor.animation_player.seek(float(request[1]), true)
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
		assert(maximum_error < 0.01, "Preserve the existing original-Actor projected boundary contract")
	for limb: int in [0, 3, 7]:
		var point := centre(original.body[limb])
		assert(actor._geometry.armor_at(actor, point, "slash") == source.armor_at(request[0], request[1], Vector2i.RIGHT, point, "slash", Vector2.ZERO, 0.0, request[2]))
	original_actor_checks += 1

func _all_morphs(editor: Variant) -> Dictionary:
	var result := {}
	for node: Node in editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var values: Array[float] = []
		for shape in mesh.get_blend_shape_count():
			values.append(mesh.get_blend_shape_value(shape))
		if not values.is_empty():
			result[editor.model_root.get_path_to(mesh)] = values
	return result

func _restore_morphs(editor: Variant, values: Dictionary) -> void:
	for path: NodePath in values:
		var mesh := editor.model_root.get_node(path) as MeshInstance3D
		for shape in range(values[path].size()):
			mesh.set_blend_shape_value(shape, values[path][shape])

func _held_visibility(editor: Variant) -> Dictionary:
	var result := {}
	for node: Node in editor.model_root.find_children("*", "MeshInstance3D", true, false):
		if str(node.name).begins_with("Weapon_") or str(node.name).begins_with("Shield_"):
			var mesh := node as MeshInstance3D
			result[editor.model_root.get_path_to(mesh)] = [mesh.visible, mesh.is_visible_in_tree()]
	return result

func _classification_invalidation(editor: Variant, source: Variant, actor: TerrainTestCharacter) -> void:
	# Mutate the actual PRIVATE resource, never a person's original animation.
	var animation: Animation = editor.animation_player.get_animation(editor.selected_animation)
	assert(animation != actor.editor.animation_player.get_animation(editor.selected_animation))
	assert(editor._can_assign_paused_clip(animation))
	var misses: int = editor.assigned_playback_profile.classification_misses
	var hits: int = editor.assigned_playback_profile.classification_hits
	assert(editor._can_assign_paused_clip(animation))
	assert(int(editor.assigned_playback_profile.classification_misses) == misses and int(editor.assigned_playback_profile.classification_hits) == hits + 1)
	classification_checks += 1
	var original_tracks := animation.get_track_count()
	var method_track := animation.add_track(Animation.TYPE_METHOD)
	assert(editor._assigned_track_contracts.is_empty(), "Animation.changed must synchronously invalidate even an allowed cached result")
	assert(not editor._can_assign_paused_clip(animation))
	assert(not editor._can_assign_paused_clip(animation), "Rejected classification may be reused too")
	animation.remove_track(method_track)
	assert(editor._assigned_track_contracts.is_empty() and animation.get_track_count() == original_tracks)
	assert(editor._can_assign_paused_clip(animation), "Removal must invalidate rejected classification and admit the restored resource")
	classification_checks += 2
	var original_path := animation.track_get_path(0)
	animation.track_set_path(0, NodePath("missing_skeleton:J_Bip_C_Hips"))
	assert(editor._assigned_track_contracts.is_empty() and not editor._can_assign_paused_clip(animation))
	animation.track_set_path(0, original_path)
	assert(editor._assigned_track_contracts.is_empty() and editor._can_assign_paused_clip(animation))
	classification_checks += 2
	editor.clear_component_lookup_cache()
	assert(editor._assigned_track_contracts.is_empty())
	assert(editor._can_assign_paused_clip(animation))
	classification_checks += 1
	# Isolate equal call counts, not initialization, query geometry or 200-person FPS.
	var cold_us := 0
	var warm_us := 0
	for iteration in range(8):
		editor.clear_assigned_track_contracts()
		var began := Time.get_ticks_usec()
		assert(editor._can_assign_paused_clip(animation))
		cold_us += Time.get_ticks_usec() - began
		began = Time.get_ticks_usec()
		assert(editor._can_assign_paused_clip(animation))
		warm_us += Time.get_ticks_usec() - began
	classification_timing = {"calls_each": 8, "cold_guard_usec": cold_us, "warm_guard_usec": warm_us}
	assert(warm_us < cold_us, "Static classification reuse must save measured guard work")
	classification_checks += 1
	# Real raw-library replacement invalidates retained resources, not just names.
	var old_animation: Animation = animation
	source._copy_private_animations(actor.editor.animation_player)
	assert(editor._assigned_track_contracts.is_empty())
	animation = editor.animation_player.get_animation(editor.selected_animation)
	assert(animation != old_animation and editor._can_assign_paused_clip(animation))
	classification_checks += 1

func _guard_fallbacks(editor: Variant) -> void:
	var animation: Animation = editor.animation_player.get_animation(editor.selected_animation)
	assert(editor._can_assign_paused_clip(animation))
	editor.animation_player.set_default_blend_time(0.1)
	assert(not editor._can_assign_paused_clip(animation))
	editor.animation_player.set_default_blend_time(0.0)
	fallback_checks += 1
	editor.animation_player.set_blend_time(&"idle", &"guard", 0.1)
	assert(not editor._can_assign_paused_clip(animation))
	editor.animation_player.set_blend_time(&"idle", &"guard", 0.0)
	fallback_checks += 1
	editor.animation_player.root_motion_track = NodePath("Skeleton3D:J_Bip_C_Hips")
	assert(not editor._can_assign_paused_clip(animation))
	editor.animation_player.root_motion_track = NodePath()
	fallback_checks += 1
	# These temporary resource clones are only inspected; never run event tracks.
	for type: int in [Animation.TYPE_METHOD, Animation.TYPE_AUDIO, Animation.TYPE_VALUE]:
		var unsupported := animation.duplicate(true) as Animation
		var track := unsupported.add_track(type)
		unsupported.track_set_path(track, NodePath("Skeleton3D:J_Bip_C_Hips"))
		if type == Animation.TYPE_VALUE:
			unsupported.value_track_set_update_mode(track, Animation.UPDATE_CAPTURE)
		assert(not editor._can_assign_paused_clip(unsupported))
		fallback_checks += 1
	var invalid_path := animation.duplicate(true) as Animation
	invalid_path.track_set_path(0, NodePath("missing_skeleton:J_Bip_C_Hips"))
	assert(not editor._can_assign_paused_clip(invalid_path))
	fallback_checks += 1
	# A real playing owner must fall back without silently pausing it. This is
	# last, so an intentionally changed playback state cannot pollute A/B history.
	editor.animation_player.play(editor.selected_animation)
	var before: int = editor.assigned_playback_profile.fallbacks
	editor._play_selected_animation()
	assert(editor.animation_player.is_playing() and int(editor.assigned_playback_profile.fallbacks) == before + 1)
	fallback_checks += 1
