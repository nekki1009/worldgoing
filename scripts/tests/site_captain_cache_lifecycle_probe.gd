extends "res://scripts/tests/site_captain_clip_sequence_probe.gd"
## Same original Army presenter, original/control/candidate/reverse histories.
## Resource identities change on real body reload; compare normalized resources,
## exact numeric pose/UI values and full RGBA. This is not an FPS test.
var lifecycle_rows: Array = []
var lifecycle_expected: Array = []
var lifecycle_variant := 0
var lifecycle_case := 0
var lifecycle_owner := PackedByteArray()
var cache_clear_count := 0
var source_hashes := {}

func _run() -> void:
	create_timer(160.0).timeout.connect(func() -> void: push_error("Cache lifecycle deadline"); quit(1))
	assert(DisplayServer.get_name() != "headless")
	assert(ClassDB.class_has_method("AnimationPlayer", "set_clear_cache_on_stop_enabled"))
	for path: String in [ARMY, EDITOR, HumanCharacter3DEditor.MALE_MODEL_PATH, HumanCharacter3DEditor.FEMALE_MODEL_PATH]:
		source_hashes[path] = FileAccess.get_sha256(path)
	out = "res://output/site_animation_cache_retention_20260917/lifecycle/run_%d" % int(Time.get_unix_time_from_system())
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out)) == OK)
	var data := TerrainData.new()
	data.allocate(Vector2i(24, 24))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "cache-lifecycle")
	data.static_blocked.fill(0)
	army = TerrainArmy.new()
	army.roster_size = 1
	root.add_child(army)
	army.set_process(false)
	assert(army.deploy_at(data, null, null, [Vector2i(10, 10)]) and army.enable_combat(false))
	editor = army._unit_editor(0)
	editor.set_process(false)
	var female_appearance := editor.capture_appearance()
	paused = true
	lifecycle_owner = _owner_bytes()
	for variant in range(4):
		lifecycle_variant = variant
		lifecycle_case = 0
		await _replace_body(1, female_appearance)
		if not await _observe("female_idle", &"idle", .271): return
		if not await _observe("attack_end", &"walk_slash", 100.0): return
		editor.animation_player.stop(true)
		if not await _observe("stop_restart", &"walk_slash", .219): return
		assert(editor.select_part_by_id(&"shield", &"none"))
		if not await _observe("shield_removed", &"guard", .217): return
		assert(editor.restore_appearance(female_appearance))
		assert(editor.select_part_by_id(&"helmet", &"none"))
		assert(editor.select_part_by_id(&"armor", &"none"))
		if not await _observe("armor_removed", &"get_up", .317): return
		assert(editor.restore_appearance(female_appearance))
		assert(editor.set_equipment_dyes({"armor": "376b9cff"}))
		if not await _observe("armor_dyed", &"walk_slash", .219): return
		assert(editor.restore_appearance(female_appearance))
		var animation := editor.animation_player.get_animation(&"walk_slash")
		var track := -1
		for index in animation.get_track_count():
			if animation.track_get_type(index) == Animation.TYPE_POSITION_3D and animation.track_get_key_count(index) > 0:
				track = index
				break
		assert(track >= 0)
		var original: Vector3 = animation.track_get_key_value(track, 0)
		animation.track_set_key_value(track, 0, original + Vector3(.01, 0, 0))
		if not await _observe("private_key_edited", &"walk_slash", .219): return
		animation.track_set_key_value(track, 0, original)
		if not await _observe("private_key_restored", &"walk_slash", .219): return
		var library := editor.animation_player.get_animation_library(&"")
		var clears_before := cache_clear_count
		library.remove_animation(&"walk_slash")
		assert(library.add_animation(&"walk_slash", animation) == OK)
		assert(cache_clear_count > clears_before, "Replacing a library entry must invalidate retained target bindings")
		if not await _observe("library_entry_replaced", &"walk_slash", .219): return
		editor.animation_player.clear_caches()
		if not await _observe("explicit_clear", &"down", .517): return
		# Replace an actual bound mesh while the SAME player remains alive.
		# No animation rewrite, missing-target playback or numeric tolerance.
		var root_node := editor.animation_player.get_node(editor.animation_player.root_node)
		var target: Node
		var current_clip := editor.animation_player.get_animation(&"down")
		for index in current_clip.get_track_count():
			if current_clip.track_get_type(index) == Animation.TYPE_BLEND_SHAPE:
				target = root_node.get_node(NodePath(current_clip.track_get_path(index).get_concatenated_names()))
				break
		assert(target is MeshInstance3D)
		var parent := target.get_parent()
		var sibling := target.get_index(true)
		var replacement := target.duplicate()
		for shape in (replacement as MeshInstance3D).get_blend_shape_count():
			(replacement as MeshInstance3D).set_blend_shape_value(shape, .123)
		var old_target: WeakRef = weakref(target)
		# This fixture owns the partial replacement. Rebind the editor's existing
		# cloth records too; leaving them dangling is not an animation-cache test.
		for record: Dictionary in editor._combat_cloth:
			if is_same(record.node, target): record.node = replacement
		clears_before = cache_clear_count
		parent.remove_child(target)
		target.free()
		parent.add_child(replacement)
		parent.move_child(replacement, sibling)
		# Node removal is NOT an automatic invalidation guarantee in AnimationMixer,
		# even with its default policy. The caller replacing a target must clear it.
		editor.animation_player.clear_caches()
		assert(old_target.get_ref() == null and cache_clear_count > clears_before)
		if not await _observe("bound_mesh_replaced_explicit_clear", &"down", .517): return
		await _replace_body(0, HumanCharacter3DEditor.default_appearance(0))
		if not await _observe("male_replacement", &"walk_slash", .319): return
		await _replace_body(1, female_appearance)
		if not await _observe("female_return", &"idle", .271): return
	var recipient := TerrainArmy.new()
	root.add_child(recipient)
	recipient.set_process(false)
	var old_army: WeakRef = weakref(army)
	army._transfer_presenters(recipient, [army.combat_identity(0)])
	assert(editor.get_parent() == recipient and editor.preview_viewport.get_parent() == recipient)
	army.free()
	assert(old_army.get_ref() == null)
	army = recipient
	lifecycle_owner = _owner_bytes()
	await _replace_body(0, HumanCharacter3DEditor.default_appearance(0))
	await _replace_body(1, female_appearance)
	print("CACHE_TRANSFER_PASS old_owner_released=true body_reload_policy=true")
	for path: String in source_hashes:
		assert(source_hashes[path] == FileAccess.get_sha256(path), "Formal source changed during lifecycle replay")
	_write_lifecycle(true)
	print("CACHE_LIFECYCLE_PASS observations=", lifecycle_rows.size(), " output=", out)
	army.free()
	quit(0)

func _replace_body(body: int, appearance: Dictionary) -> void:
	var old_model: WeakRef = weakref(editor.model_root)
	var old_player: WeakRef = weakref(editor.animation_player)
	editor.set_playing(false)
	editor._load_body_model(body)
	assert(editor.restore_appearance(appearance))
	assert(not editor.animation_player.call("is_clear_cache_on_stop_enabled"), "New private presenter body must inherit the production Army policy")
	editor.animation_player.call("set_clear_cache_on_stop_enabled", lifecycle_variant != 2)
	editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	editor.animation_player.caches_cleared.connect(func() -> void: cache_clear_count += 1)
	editor.combat_ready = true
	editor.visual_state.combat_ready = true
	editor.set_playing(true)
	await process_frame
	await process_frame
	assert(old_model.get_ref() == null and old_player.get_ref() == null, "Old model and animation target owner must be released")
	assert(_owner_bytes() == lifecycle_owner)

func _owner_bytes() -> PackedByteArray:
	return var_to_bytes([army.combat_units, army.cells, army.command_rng.state, army.combat_slots, army._reserved_cells])

func _lifecycle_state() -> Array:
	var result: Array = _cache_comparable(_state())
	var nodes := editor.preview_pivot.find_children("*", "Node3D", true, false)
	for index in nodes.size():
		var node: Node = nodes[index]
		if node is PhysicalBoneSimulator3D and str(node.name).begins_with("@"):
			# The raw loader creates an anonymous simulator with a process-wide
			# serial name. Original-vs-original body reload changes that serial.
			# Preserve parent identity, class, sibling index and EVERY state value.
			result[index][0] = str(editor.preview_pivot.get_path_to(node.get_parent())) + "/<PhysicalBoneSimulator3D:%d>" % node.get_index(true)
	return result

func _observe(label: String, clip: StringName, at: float) -> bool:
	assert(editor.select_animation_by_id(clip))
	editor.set_playing(true)
	editor.animation_player.seek(minf(at, editor.animation_player.get_animation(clip).length), true)
	editor._process(0.0)
	var immediate := _lifecycle_state()
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := editor.preview_viewport.get_texture().get_image()
	assert(picture.get_used_rect().has_area() and _owner_bytes() == lifecycle_owner)
	var actual := [immediate, _lifecycle_state()]
	var row := {"variant": lifecycle_variant, "label": label, "state_equal": true, "rgba_equal": true}
	if lifecycle_variant == 0:
		lifecycle_expected.append([actual, picture.get_data()])
	else:
		var reference: Array = lifecycle_expected[lifecycle_case]
		row.state_equal = reference[0] == actual
		row.rgba_equal = reference[1] == picture.get_data()
		row.difference = _difference(reference[0], actual)
	lifecycle_rows.append(row)
	lifecycle_case += 1
	if label in ["female_idle", "shield_removed", "male_replacement"]:
		assert(picture.save_png(out + "/%s_%d.png" % [label, lifecycle_variant]) == OK)
	if not row.state_equal or not row.rgba_equal:
		_write_lifecycle(false)
		push_error("Cache lifecycle mismatch: " + label + " " + str(row.get("difference", "")))
		quit(1)
		return false
	return true

func _write_lifecycle(exact: bool) -> void:
	var file := FileAccess.open(out + "/measurements.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"exact": exact, "rows": lifecycle_rows, "source_hashes": source_hashes,
		"scope": "Actual private Army presenter equipment, raw private key edits, library replacement, stop/restart, old-model deletion and female/male/female reconstruction; same-engine full RGBA and exact numeric state. Not FPS or full save integration."}, "\t"))
	file.close()
