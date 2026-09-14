extends "res://scripts/tests/site_army_morph_reset_test.gd"
## Same live private source, original per-slot lining owner versus one final
## original call. GPU groups 0/1: male/female lining; 2: footer only, no batching.
## Original 23-second internal / 25-second helper bound. Not an FPS benchmark.

var lining_expected: Array[Dictionary] = []
var lining_passes: Array[Dictionary] = []
var lining_exact_pairs := 0
var lining_failure_expected := {}
var lining_range_events: Array[float] = []

func run() -> void:
	var refresh_mode := "--refresh-mode" in OS.get_cmdline_user_args()
	var deadline_us := Time.get_ticks_usec() + 23000000
	create_timer(23.0).timeout.connect(func() -> void:
		push_error("SITE_ARMY_LINING_BATCH deadline")
		quit(1))
	assert(group in [0, 1, 2] and DisplayServer.get_name() != "headless")
	assert(TerrainArmy.load_combat_bake())
	var body_index := 1 if group == 1 else 0
	var baseline: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	baseline.body = body_index
	baseline.parts.hair = HumanCharacter3DEditor.default_appearance(body_index).parts.hair
	assert(HumanCharacter3DEditor.valid_appearance(baseline))
	var actor := TerrainTestCharacter.new()
	actor.visual_state.body_index = body_index
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
	var editor: Variant = source.editor
	assert(not editor.parts_footer.text.is_empty())
	source.terminal_cache_enabled = false
	var source_id: int = editor.get_instance_id()
	var skeleton_id: int = source.skeleton.get_instance_id()
	var armor := baseline.duplicate(true)
	armor.parts.outfit = "outfit_chinese_lining_01"
	armor.parts.armor = "armor_mingguang_01"
	armor.parts.helmet = "helmet_mingguang_01"
	armor.parts.boots = "boots_mingguang_01"
	armor.parts.cape = "cape_chinese_01"
	var western := armor.duplicate(true)
	western.parts.armor = "armor_western_iron_01"
	western.parts.helmet = "helmet_western_iron_01"
	western.parts.boots = "boots_western_iron_01"
	western.parts.shield = "none"
	var bare := missing_recipe(baseline, 31)
	bare.parts.cape = "none"
	var m25 := missing_recipe(baseline, 6)
	var alternate := western.duplicate(true)
	alternate.parts.hair = "hair_female_02" if body_index == 1 else "hair_male_02"
	alternate.parts.face = "face_standard_02"
	var polearm := baseline.duplicate(true)
	polearm.parts.weapon = "spear_01"
	var requests: Array = [
		[&"guard", 0.073, baseline],
		[&"get_up", 0.337, armor],
		[&"idle", 0.019, bare],
		[&"rescue", 1.137, armor],
		[&"guard", 0.083, western],
		[&"down", 0.417, baseline],
		[&"guard", 0.093, m25],
		[&"walk_slash", 0.517, baseline],
		[&"get_up", 0.637, armor],
		[&"idle", 0.219, bare],
	]
	if refresh_mode:
		requests.append_array([[&"guard", 0.117, western], [&"guard", 0.127, polearm],
			[&"idle", 0.327, alternate], [&"walk_slash", 0.527, baseline]])
	# Prime only the original covered-mesh cache. Both A/B passes then retain
	# these exact original/covered resource identities, not newly authored meshes.
	assert(not source.sample(&"get_up", 0.111, Vector2i.LEFT, Vector2.ZERO, 0.0, armor).is_empty())
	if refresh_mode:
		assert(not source.sample(&"idle", 0.011, Vector2i.LEFT, Vector2.ZERO, 0.0, alternate).is_empty())
	assert(not source.sample(&"idle", 0.011, Vector2i.LEFT, Vector2.ZERO, 0.0, baseline).is_empty())
	var initial_morphs := _all_morphs(editor)
	var body := editor.model_root.find_child("Body_Standard_Female" if body_index == 1 else "Body_Standard_Male", true, false) as MeshInstance3D
	assert(body != null and body.has_meta("lining_original_mesh") and body.has_meta("lining_covered_mesh"))
	var original_mesh: ArrayMesh = body.get_meta("lining_original_mesh")
	var covered_mesh: ArrayMesh = body.get_meta("lining_covered_mesh")
	assert(original_mesh != covered_mesh and body.mesh == original_mesh)
	var initial_hair: Dictionary = _lining_state(source, body).hair_shader if refresh_mode else {}
	editor.timeline_slider.value_changed.connect(func(value: float) -> void: lining_range_events.append(value))
	for pass_index in range(2):
		editor.batch_lining_updates_enabled = refresh_mode or (group != 2 and pass_index == 1)
		if refresh_mode:
			editor.recipe_refresh_batch_enabled = pass_index == 1
		# Lining runs keep the original labels in BOTH paths. Group 2 tests the
		# footer suppression independently while both lining paths stay original.
		editor.query_labels_enabled = group != 2 or pass_index == 0
		_restore_morphs(editor, initial_morphs)
		if refresh_mode:
			for address: String in initial_hair:
				var pieces := address.split("|")
				var hair := editor.model_root.get_node(NodePath(pieces[0])) as MeshInstance3D
				var material := hair.get_surface_override_material(int(pieces[1])) as ShaderMaterial
				for parameter: String in initial_hair[address]:
					material.set_shader_parameter(parameter, initial_hair[address][parameter])
		source.clear_samples()
		source._key.clear()
		assert(not source.sample(&"get_up", 0.111, Vector2i.LEFT, Vector2.ZERO, 0.0, armor).is_empty())
		assert(not source.sample(&"idle", 0.011, Vector2i.LEFT, Vector2.ZERO, 0.0, baseline).is_empty())
		editor.timeline_slider.set_value_no_signal(3.5)
		lining_range_events.clear()
		editor.parts_footer.text = "private footer fixture marker"
		var before: Dictionary = editor.lining_update_profile.duplicate()
		var refresh_before: Dictionary = editor.recipe_refresh_profile.duplicate() if refresh_mode else {}
		var started := Time.get_ticks_usec()
		for index in range(requests.size()):
			assert(Time.get_ticks_usec() < deadline_us, "Original 23 second deadline exceeded")
			var request: Array = requests[index]
			source.clear_samples()
			var query: Dictionary = source.sample(request[0], request[1], Vector2i.RIGHT, Vector2.ZERO, 0.0, request[2])
			assert(not query.is_empty() and not editor._recipe_lining_active and not editor._recipe_lining_pending)
			if refresh_mode:
				assert(not editor._recipe_refresh_active and not editor._recipe_full_body_pending and not editor._recipe_hair_pending)
			var snapshot := _snapshot(source, request[2], [request[0], request[1], Vector2i.RIGHT, Vector2.ZERO, 0.0], query)
			snapshot.lining = _lining_state(source, body)
			snapshot.timeline = [editor.timeline_slider.max_value, editor.timeline_slider.value, lining_range_events.duplicate()]
			assert(body.mesh == (covered_mesh if request[2].parts.outfit == "outfit_chinese_lining_01" else original_mesh))
			assert(body.get_meta("lining_original_mesh") == original_mesh and body.get_meta("lining_covered_mesh") == covered_mesh)
			if pass_index == 0:
				lining_expected.append(snapshot)
			else:
				for field: String in snapshot:
					assert(snapshot[field] == lining_expected[index][field], "Strict lining/footer A/B difference request %d / %s" % [index, field])
					if refresh_mode:
						assert(_refresh_exact(snapshot[field], lining_expected[index][field]), "Recipe refresh numeric bits changed %d / %s" % [index, field])
				lining_exact_pairs += 1
			assert(editor.get_instance_id() == source_id and source.skeleton.get_instance_id() == skeleton_id)
		var failed_state := _failed_recipe(source, baseline, western, body)
		if pass_index == 0:
			lining_failure_expected = failed_state
		else:
			assert(failed_state == lining_failure_expected, "Partial selection failure must flush original lining before capture/return")
			if refresh_mode:
				assert(_refresh_exact(failed_state, lining_failure_expected), "Failed recipe refresh numeric bits changed")
		# A direct original-editor selection outside Source's batch never defers.
		assert(not source.sample(&"idle", 0.029, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline).is_empty())
		var actual_before: int = editor.lining_update_profile.actual
		var deferred_before: int = editor.lining_update_profile.deferred
		var refresh_outside_before: Dictionary = editor.recipe_refresh_profile.duplicate() if refresh_mode else {}
		assert(editor.select_part_by_id(&"armor", StringName(str(baseline.parts.armor))))
		assert(int(editor.lining_update_profile.actual) == actual_before + 1 and int(editor.lining_update_profile.deferred) == deferred_before)
		if refresh_mode:
			assert(int(editor.recipe_refresh_profile.full_body_actual) == int(refresh_outside_before.full_body_actual) + 1)
			assert(int(editor.recipe_refresh_profile.hair_actual) == int(refresh_outside_before.hair_actual) + 1)
			assert(editor.recipe_refresh_profile.full_body_deferred == refresh_outside_before.full_body_deferred and editor.recipe_refresh_profile.hair_deferred == refresh_outside_before.hair_deferred)
			assert(not editor._recipe_refresh_active and not editor._recipe_full_body_pending and not editor._recipe_hair_pending)
		var measured := {"batch_enabled": editor.batch_lining_updates_enabled,
			"labels_enabled": editor.query_labels_enabled, "elapsed_usec": Time.get_ticks_usec() - started, "lining_updates": {}}
		for field: String in before:
			measured.lining_updates[field] = int(editor.lining_update_profile[field]) - int(before[field])
		if refresh_mode:
			measured["refresh"] = {}
			for field: String in refresh_before:
				measured.refresh[field] = int(editor.recipe_refresh_profile[field]) - int(refresh_before[field])
			if pass_index == 1:
				assert(int(measured.refresh.full_body_deferred) > 0 and int(measured.refresh.hair_deferred) > 0)
		elif group != 2 and pass_index == 1:
			assert(int(measured.lining_updates.deferred) > 0 and int(measured.lining_updates.flushes) > 0)
			assert(int(measured.lining_updates.actual) < int(lining_passes[0].lining_updates.actual), "Candidate must exercise fewer actual original lining calls")
		else:
			assert(int(measured.lining_updates.deferred) == 0 and int(measured.lining_updates.flushes) == 0)
		if group == 2:
			assert((editor.parts_footer.text == "private footer fixture marker") == (pass_index == 1))
		lining_passes.append(measured)
	assert(Time.get_ticks_usec() < deadline_us and lining_exact_pairs == requests.size())
	var report := {"group": group, "body": body_index, "exact_pairs": lining_exact_pairs,
		"maximum_error": 0.0, "failure_pairs": 1, "outside_batch_checks": 2,
		"passes": lining_passes, "source_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd"),
		"scope": "Same original private source/rig. All bones/morphs/armor/geometry/protection plus actual body mesh identities/surface arrays, all mesh visibility and original hair shader uniforms. Group 2 isolates hidden footer suppression. Not FPS."}
	report["refresh_mode"] = refresh_mode
	if refresh_mode:
		report["timing"] = _refresh_timing(source, baseline, requests)
	var path := "res://output/site_combat_performance_20260913/recipe_refresh/%d_%d_group%d.json" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec(), group] if refresh_mode else "res://output/site_combat_performance_20260913/lining_batch/group_%d.json" % group
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	source.dispose()
	actor.queue_free()
	await process_frame
	print("SITE_ARMY_LINING_BATCH_PASS ", JSON.stringify(report))
	quit(0)

func _refresh_exact(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		if a.keys() != b.keys():
			return false
		for key: Variant in a:
			if not _refresh_exact(a[key], b[key]):
				return false
		return true
	if a is Array:
		if a.size() != b.size():
			return false
		for index in a.size():
			if not _refresh_exact(a[index], b[index]):
				return false
		return true
	if a is NodePath or a is Object:
		return a == b # Semantic paths and original resources; not encoder padding.
	return var_to_bytes(a) == var_to_bytes(b)

func _refresh_timing(source: Variant, baseline: Dictionary, requests: Array) -> Array:
	var runs: Array = []
	for enabled: bool in [false, true, true, false]:
		source.editor.recipe_refresh_batch_enabled = enabled
		source.begin_contact_step()
		assert(not source.sample(&"idle", 0.011, Vector2i.LEFT, Vector2.ZERO, 0.0, baseline).is_empty())
		var before: Dictionary = source.query_profile.duplicate()
		var began := Time.get_ticks_usec()
		for repeat in 4:
			for request: Array in requests:
				source.begin_contact_step()
				assert(not source.sample(request[0], request[1], Vector2i.RIGHT, Vector2.ZERO, 0.0, request[2]).is_empty())
		runs.append({"enabled": enabled, "queries": 4 * requests.size(), "elapsed_usec": Time.get_ticks_usec() - began,
			"appearance_usec": int(source.query_profile.apply_appearance_usec) - int(before.apply_appearance_usec)})
	return runs

func _lining_state(source: Variant, body: MeshInstance3D) -> Dictionary:
	var editor: Variant = source.editor
	var result := {"body_mesh": body.mesh, "body_original": body.get_meta("lining_original_mesh"),
		"body_covered": body.get_meta("lining_covered_mesh"), "body_surfaces": [],
		"appearance": editor.capture_appearance(), "visibility": {}, "hair_shader": {}}
	for surface in range(body.mesh.get_surface_count()):
		result.body_surfaces.append(body.mesh.surface_get_arrays(surface).duplicate(true))
	for node: MeshInstance3D in editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var path: NodePath = editor.model_root.get_path_to(node)
		result.visibility[path] = [node.visible, node.is_visible_in_tree()]
		if not str(node.name).begins_with("Hair_") or node.mesh == null:
			continue
		for surface in range(node.mesh.get_surface_count()):
			var material := node.get_surface_override_material(surface) as ShaderMaterial
			if material == null or material.shader != editor._hair_mask_shader:
				continue
			var values := {}
			for field: String in ["mask_enabled", "dye_enabled", "dye_color", "inv_head_transform", "brow_cut_y", "tuck_hair_piece"]:
				values[field] = material.get_shader_parameter(field)
			result.hair_shader["%s|%d" % [path, surface]] = values
	assert(not result.hair_shader.is_empty(), "The real original selected hair must exercise its shader state")
	return result

func _failed_recipe(source: Variant, baseline: Dictionary, target: Dictionary, body: MeshInstance3D) -> Dictionary:
	source.clear_samples()
	assert(not source.sample(&"guard", 0.097, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline).is_empty())
	var invalid := target.duplicate(true)
	invalid.parts.boots = "missing_fixture_boots"
	# Deliberately inject a late original selector failure after earlier valid
	# slots, bypassing only supports_appearance in this bounded failure fixture.
	assert(not source._apply_appearance(invalid, source._appearance_key(invalid)))
	var editor: Variant = source.editor
	assert(not editor._recipe_lining_active and not editor._recipe_lining_pending)
	assert(source._appearance == editor.capture_appearance() and source._recipe_key.is_empty() and source._key.is_empty())
	assert(source._appearance.parts.boots == baseline.parts.boots and source._appearance.parts.outfit == target.parts.outfit)
	var result := _lining_state(source, body)
	result.morphs = _all_morphs(editor)
	result.bones = []
	for bone in range(source.skeleton.get_bone_count()):
		result.bones.append([source.skeleton.get_bone_pose(bone), source.skeleton.get_bone_global_pose(bone)])
	var proxy := {"editor": editor, "player_sprite": source.sprite}
	result.geometry = {"body": source.geometry.body_shapes(proxy),
		"weapon": source.geometry.weapon_shapes(proxy, editor._resolve_weapon_attack_animation()), "shield": source.geometry.shield_shapes(proxy)}
	return result
