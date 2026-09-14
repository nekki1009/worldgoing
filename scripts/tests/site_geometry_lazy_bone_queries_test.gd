extends "res://scripts/tests/site_aim_lazy_bones_test.gd"
## Reuses only the original actor bone/error helpers, not that test's run/reset.
## GPU --body=male|female; internal 23 seconds / canonical helper 25 seconds.
## Same original three query functions: flag false is their prior full-force path.
const QUERY_OUTPUT := "res://output/site_combat_performance_20260913/lazy_bone_queries/"
const QUERY_ORDERS := [["body", "weapon", "shield"], ["weapon", "shield", "body"], ["shield", "body", "weapon"]]
var body_name := "male"
var sync_signals := 0
var render_pairs := 0
var captured_paths: Array[String] = []
var query_finished := false
var nonzero_morph_cases := 0
var render_byte_differences := 0

func _initialize() -> void:
	began_us = Time.get_ticks_usec()
	deadline_us = began_us + 23000000
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--body="):
			body_name = argument.trim_prefix("--body=")
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not query_finished and Time.get_ticks_usec() >= deadline_us:
		failures.append("Original 23 second deadline exceeded")
		_finish(false)
	return false

func _run() -> void:
	assert(body_name in ["male", "female"])
	assert(DisplayServer.get_name() != "headless", "Original raw actor requires GPU initialization")
	assert(current.lazy_bone_queries_enabled, "Production candidate must default to lazy native queries")
	actor = TerrainTestCharacter.new()
	actor.visual_state.body_index = 0 if body_name == "male" else 1
	actor.person_id = 1
	actor.auto_face = false
	actor.combat_driven_by_lab = true
	root.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	assert(actor.editor != null and actor.editor._body_index == actor.visual_state.body_index and not actor.editor.use_imported_model)
	actor.editor.set_process(false)
	actor.editor.set_playing(false)
	actor.editor.combat_ready = true
	actor.editor.visual_state.combat_ready = true
	actor.position = Vector2(960, 540)
	for selection: Array in [[&"helmet", &"helmet_mingguang_01"], [&"armor", &"armor_mingguang_01"],
		[&"outfit", &"outfit_chinese_lining_01"], [&"boots", &"boots_mingguang_01"]]:
		assert(actor.editor.select_part_by_id(selection[0], selection[1]), "Original component unavailable: " + str(selection))
	skeleton = actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	assert(skeleton != null)
	original_actor_id = actor.get_instance_id()
	original_editor_id = actor.editor.get_instance_id()
	original_skeleton_id = skeleton.get_instance_id()
	skeleton.pose_updated.connect(func() -> void: sync_signals += 1)
	actor.editor.preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(QUERY_OUTPUT))
	# Real asset selection is solely a rendering fixture, not lawful issue/mint UI.
	# Low-pose clips exercise authored armor morphs; spear and sword retain real IK.
	var cases: Array[Array] = [
		[&"walk_slash", 0.317, &"longsword_01", &"shield_heater_01", 0.0],
		[&"guard", 0.173, &"longsword_01", &"none", 0.0],
		[&"down", 0.613, &"longsword_01", &"shield_heater_01", 0.0],
		[&"get_up", 0.337, &"longsword_01", &"shield_heater_01", 0.0],
		[&"attack_unarmed", 0.233, &"none", &"none", 0.0],
		[&"walk_slash", 0.417, &"longsword_01", &"shield_heater_01", 0.5],
		[&"attack_spear", 0.337, &"spear_01", &"shield_heater_01", 1.0],
	]
	for case_index in range(cases.size()):
		var request: Array = cases[case_index]
		assert(actor.editor.select_part_by_id(&"weapon", request[2]))
		assert(actor.editor.select_part_by_id(&"shield", request[3]))
		actor.editor.set_preview_yaw_degrees([0.0, 180.0, -90.0, 90.0][case_index % 4])
		assert(actor.editor.select_animation_by_id(request[0]))
		actor.editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		actor.editor._on_timeline_changed(float(request[1]))
		actor.editor.animation_player.advance(0.0)
		actor.editor._update_combat_props()
		actor.editor._update_scabbard_pose()
		actor.editor._update_combat_cloth()
		actor._sync_render_projection()
		current.aim_weapon_attack(actor, actor.position + Vector2(18, 39), float(request[4]))
		# Only LOCAL components are read here. No global snapshot may pre-clean
		# the candidate's dirty chains before its first actual geometry query.
		var local_poses := _query_local_poses()
		for order_index in range(QUERY_ORDERS.size()):
			if Time.get_ticks_usec() >= deadline_us:
				failures.append("Bounded deadline before query pair")
				_finish(false)
				return
			await _query_pair(request, local_poses, QUERY_ORDERS[order_index], case_index == 2 and order_index == 1)
			if not failures.is_empty():
				_finish(false)
				return
		await process_frame
	assert(rows.size() == 21 and render_pairs == 1 and nonzero_morph_cases > 0)
	_finish(true)

func _query_local_poses() -> Array[Array]:
	var result: Array[Array] = []
	for index in range(skeleton.get_bone_count()):
		result.append([skeleton.get_bone_pose_position(index), skeleton.get_bone_pose_rotation(index), skeleton.get_bone_pose_scale(index)])
	return result

func _query_dirty_restore(poses: Array[Array]) -> void:
	# Native setters mark every original local bone/descendant dirty even when
	# assigned the same value. Deliberately NO force, getter-global, await or draw.
	for index in range(poses.size()):
		skeleton.set_bone_pose_position(index, poses[index][0])
		skeleton.set_bone_pose_rotation(index, poses[index][1])
		skeleton.set_bone_pose_scale(index, poses[index][2])

func _query_three(geometry: Variant, clip: StringName, order: Array) -> Dictionary:
	var result := {}
	for kind: String in order:
		match kind:
			"body": result.body = geometry.body_shapes(actor)
			"weapon": result.weapon = geometry.weapon_shapes(actor, clip)
			"shield": result.shield = geometry.shield_shapes(actor)
	result.parry = geometry.weapon_shapes(actor, clip, true)
	return result

func _query_details(geometry: Variant, shapes: Dictionary) -> Dictionary:
	# Full diagnostic snapshots happen AFTER all requested query functions.
	var result := {"shapes": shapes, "bones": _bones(), "morphs": {}, "vertices": {}, "transforms": {}, "protection": []}
	for node: Node in actor.editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var key := str(actor.editor.model_root.get_path_to(mesh))
		var values: Array[float] = []
		for shape in range(mesh.get_blend_shape_count()):
			values.append(mesh.get_blend_shape_value(shape))
		if not values.is_empty():
			result.morphs[key] = values
		var label := str(mesh.name)
		if mesh.is_visible_in_tree() and mesh.mesh != null and (label.begins_with("Weapon_") or label.begins_with("Shield_") or label.begins_with("Armor_") or label.begins_with("Helmet_") or label.begins_with("Outfit_") or label.begins_with("Boots_")):
			result.vertices[key] = geometry.posed_vertices(mesh, skeleton)
			result.transforms[key] = mesh.global_transform
	for index: int in [0, 3, 7]:
		var centre := Vector2.ZERO
		var polygon: PackedVector2Array = shapes.body[index]
		for point: Vector2 in polygon:
			centre += point
		result.protection.append(geometry.armor_at(actor, centre / polygon.size(), "slash"))
	return result

func _query_pair(request: Array, poses: Array[Array], order: Array, capture: bool) -> void:
	var snapshots: Array[Dictionary] = []
	var pictures: Array[Image] = []
	var timings: Array[int] = []
	var forces: Array[int] = []
	for pass_index in range(2):
		# Separate cold head/surface caches: first face fitting cannot hide a
		# candidate difference behind the reference's already-computed AABB.
		var geometry := Current.new()
		geometry.lazy_bone_queries_enabled = pass_index == 1
		_query_dirty_restore(poses)
		var before_signals := sync_signals
		var started := Time.get_ticks_usec()
		var shapes := _query_three(geometry, request[0], order)
		timings.append(Time.get_ticks_usec() - started)
		forces.append(sync_signals - before_signals)
		assert(shapes.body.size() == 10)
		assert(not shapes.weapon.is_empty(), "Fixture must exercise real weapon or unarmed mesh/bone branch")
		assert(shapes.shield.is_empty() == (request[3] == &"none"))
		if capture:
			# Draw BEFORE the full-bone diagnostic snapshot. The engine's original
			# deferred skeleton/skin update, not the test, finishes rendering.
			await process_frame
			await RenderingServer.frame_post_draw
			var picture: Image = actor.editor.preview_viewport.get_texture().get_image()
			assert(not picture.is_empty() and picture.get_used_rect().has_area())
			var path := QUERY_OUTPUT + body_name + ("_original.png" if pass_index == 0 else "_lazy.png")
			assert(picture.save_png(path) == OK)
			pictures.append(picture)
			captured_paths.append(path)
		snapshots.append(_query_details(geometry, shapes))
	assert(forces[0] >= 4 and forces[1] == 0, "Both actual full-force and no-force query paths must execute")
	var a: Dictionary = snapshots[0]
	var b: Dictionary = snapshots[1]
	var bone_error := _bone_difference(a.bones, b.bones)
	maxima.bone = maxf(float(maxima.bone), bone_error)
	var vertex_error := 0.0
	var polygon_error := 0.0
	var transform_error := 0.0
	var armor_error := 0.0
	for kind: String in ["body", "weapon", "shield", "parry"]:
		if a.shapes[kind].size() != b.shapes[kind].size():
			failures.append("Shape count differs: " + kind)
			continue
		for index in range(a.shapes[kind].size()):
			var old_polygon: PackedVector2Array = a.shapes[kind][index]
			var new_polygon: PackedVector2Array = b.shapes[kind][index]
			if old_polygon.size() != new_polygon.size():
				failures.append("Polygon vertex count differs: " + kind)
				continue
			for vertex in range(old_polygon.size()):
				polygon_error = maxf(polygon_error, old_polygon[vertex].distance_to(new_polygon[vertex]))
	for key: String in a.vertices:
		if not b.vertices.has(key) or a.vertices[key].size() != b.vertices[key].size():
			failures.append("Actual mesh vertex count differs: " + key)
			continue
		var old_vertices: PackedVector3Array = a.vertices[key]
		var new_vertices: PackedVector3Array = b.vertices[key]
		for index in range(old_vertices.size()):
			vertex_error = maxf(vertex_error, old_vertices[index].distance_to(new_vertices[index]))
		transform_error = maxf(transform_error, _transform_difference(a.transforms[key], b.transforms[key]))
	for index in range(a.protection.size()):
		armor_error = maxf(armor_error, (a.protection[index] as Vector2).distance_to(b.protection[index]))
	maxima.mesh_vertex = maxf(float(maxima.mesh_vertex), vertex_error)
	maxima.polygon_vertex = maxf(float(maxima.polygon_vertex), polygon_error)
	maxima.mesh_transform = maxf(float(maxima.mesh_transform), transform_error)
	maxima.armor = maxf(float(maxima.armor), armor_error)
	if a != b:
		var different_fields: Array[String] = []
		for key: String in a:
			if a[key] != b[key]:
				different_fields.append(key)
		failures.append("Exact dirty-pose result differs: %s first=%s fields=%s" % [request[0], order[0], different_fields])
	var active_morphs := 0
	for values: Array in a.morphs.values():
		for value: float in values:
			active_morphs += int(value != 0.0)
	nonzero_morph_cases += int(active_morphs > 0)
	if capture:
		if pictures[0].get_size() != pictures[1].get_size() or pictures[0].get_format() != pictures[1].get_format() or pictures[0].get_data() != pictures[1].get_data():
			failures.append("Full original deferred render frame bytes differ; keep both PNGs for inspection")
			var old_bytes := pictures[0].get_data()
			var new_bytes := pictures[1].get_data()
			render_byte_differences += absi(old_bytes.size() - new_bytes.size())
			for index in range(mini(old_bytes.size(), new_bytes.size())):
				render_byte_differences += int(old_bytes[index] != new_bytes[index])
		render_pairs += 1
	original_us += timings[0]
	current_us += timings[1]
	var row := {"clip": str(request[0]), "time": request[1], "weight": request[4], "first_query": order[0],
		"full_force_signals": forces[0], "lazy_force_signals": forces[1], "active_morphs": active_morphs,
		"bone_error": bone_error, "vertex_error": vertex_error, "polygon_error": polygon_error,
		"transform_error": transform_error, "armor_error": armor_error, "exact_dictionary": a == b,
		"original_query_usec": timings[0], "lazy_query_usec": timings[1], "render_pair": capture}
	rows.append(row)
	print("GEOMETRY_LAZY_BONE_CASE ", body_name, " ", JSON.stringify(row))

func _finish(passed: bool) -> void:
	if query_finished:
		return
	query_finished = true
	if actor != null and (actor.get_instance_id() != original_actor_id or actor.editor.get_instance_id() != original_editor_id or skeleton.get_instance_id() != original_skeleton_id or actor.hp != 100.0):
		failures.append("Original actor/editor/skeleton identity or HP changed")
	passed = passed and failures.is_empty() and rows.size() == 21 and render_pairs == 1
	var report := {"pass": passed, "body": body_name, "cases": rows.size(), "rows": rows, "failures": failures,
		"maximum_errors": maxima, "render_pairs": render_pairs, "render_byte_differences": render_byte_differences, "pngs": captured_paths,
		"original_query_usec": original_us, "lazy_query_usec": current_us,
		"wall_ms": (Time.get_ticks_usec() - began_us) / 1000.0, "internal_deadline_seconds": 23,
		"geometry_sha256": FileAccess.get_sha256(CURRENT_PATH),
		"scope": "Same original raw actor; identical local pose rewritten dirty before first body/weapon/shield query. Original full-force flag false versus native-lazy true; complete dictionary and rendered preview bytes exact. No 200-person FPS claim."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(QUERY_OUTPUT))
	var file := FileAccess.open(QUERY_OUTPUT + body_name + ".json", FileAccess.WRITE)
	if file == null:
		push_error("Could not preserve lazy-bone query report")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	if passed:
		print("SITE_GEOMETRY_LAZY_BONE_QUERIES_PASS ", JSON.stringify(report))
	else:
		push_error("SITE_GEOMETRY_LAZY_BONE_QUERIES_FAIL " + JSON.stringify(report))
	if is_instance_valid(actor):
		actor.free()
	quit(0 if passed else 1)
