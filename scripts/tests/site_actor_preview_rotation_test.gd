extends "res://scripts/tests/site_actor_cloth_batch_test.gd"
## GPU --body=0|1, 33s / helper 35s bound for additional hair/mounted probes.
## Only actual-equal pivot.rotation assignment may be omitted. Hair mask remains live.
var rotation_case: Dictionary = {}
var rotation_step := 0
var rotation_checks := 0
var equal_rotation_checks := 0
var unexpected_pivot_checks := 0
var hair_uniform_checks := 0

func _process(_delta: float) -> bool:
	# The extended matrix reached 54 exact steps / 17 frames at the old 23s
	# bound. Preserve every check and the original parent's 23s for other tests.
	if not finished and Time.get_ticks_usec() - started_us > 33000000:
		_fail("Internal 33-second bound; no incomplete equality PASS")
	return false

func _initialize() -> void:
	output_root = "res://output/site_combat_performance_20260913/actor_preview_rotation"
	result_prefix = "SITE_ACTOR_PREVIEW_ROTATION"
	capture_modes = ["original_setter", "actual_equal_guard"]
	candidate_scope = "Original repeated pivot.rotation setter versus exact actual-state guard only; original yaw/visual-state/hair-mask calls retained. Same actor, four facing directions, reverse, pitch, unexpected actual pivot edits, original hair/equipment changes, mounted and ground poses. All 54 substep bones/body/weapon/shield/armor/props/selected-hair uniforms and 18 native-frame morph/material/parts/camera/pixels exact; not FPS, new collision or formal atlas admission."
	super._initialize()

func _configure_candidate(enabled: bool) -> void:
	assert(actor.editor.get("exact_preview_rotation_guard_enabled") != null)
	actor.editor.exact_preview_rotation_guard_enabled = enabled
	actor.editor.lazy_combat_visual_bones_enabled = true
	actor.batch_cloth_updates_enabled = true

func _cases() -> Array[Dictionary]:
	var cases := super._cases()
	for index: int in cases.size():
		cases[index].yaw = [0.0, 90.0, 180.0, -90.0][index % 4]
		cases[index].pitch = [0.0, 0.11, -0.07, 0.0][index % 4]
	# Keep the original matrix size/bow-first acceptance, adding a real mount
	# followed by the original final ground rescue without replacing any owner.
	cases[16] = {"label": "mounted_idle", "clip": &"ride_idle", "time": .317,
		"weapon": &"longsword_01", "yaw": 90.0, "pitch": .06}
	cases[0].hair = &"hair_male_01" if body_index == 0 else &"hair_female_01"
	cases[3].hair = &"hair_male_02" if body_index == 0 else &"hair_female_02"
	cases[16].hair = &"hair_male_01" if body_index == 0 else &"hair_female_01"
	return cases

func _prime_case(item: Dictionary) -> bool:
	if not super._prime_case(item):
		return false
	if item.has("hair") and not actor.editor.select_part_by_id(&"hair", item.hair):
		return false
	rotation_case = item
	rotation_step = 0
	actor.editor._preview_pitch = float(item.pitch)
	actor.editor.set_preview_yaw_degrees(float(item.yaw))
	assert(actor.editor.is_mounted == (item.clip == &"ride_idle"))
	return true

func _collision_snapshot() -> Dictionary:
	# Exercise the real setter after each original seek, before any global bone
	# snapshot. An equal rotation must STILL update the newly posed hair mask.
	var degrees: float = float(rotation_case.yaw) + (180.0 if rotation_step > 0 else 0.0)
	var requested := Vector3(float(rotation_case.pitch), PI + deg_to_rad(degrees), 0.0)
	if rotation_step == 2:
		actor.editor.preview_pivot.rotation = requested + Vector3(.037, -.021, .014)
		unexpected_pivot_checks += 1
	if actor.editor.preview_pivot.rotation == requested:
		equal_rotation_checks += 1
	actor.editor.set_preview_yaw_degrees(degrees)
	assert(actor.editor.preview_pivot.rotation == requested, "Actual pivot edits must not be hidden by a remembered facing")
	assert(actor.editor._preview_yaw == deg_to_rad(degrees) and actor.editor.visual_state.yaw_degrees == degrees)
	var hair := _selected_hair_uniforms(true)
	var result := super._collision_snapshot()
	result.preview_rotation = [actor.editor.preview_pivot.rotation, actor.editor.preview_pivot.transform,
		actor.editor.model_root.global_transform, skeleton.global_transform, actor.editor.camera.global_transform]
	result.appearance = actor.editor.capture_appearance()
	result.hair = hair
	rotation_step += 1
	rotation_checks += 1
	report.rotation_checks = rotation_checks
	report.equal_rotation_checks = equal_rotation_checks
	report.unexpected_pivot_checks = unexpected_pivot_checks
	report.hair_uniform_checks = hair_uniform_checks
	return result

func _selected_hair_uniforms(check_current_head: bool = false) -> Dictionary:
	var head := skeleton.find_bone("J_Bip_C_Head")
	assert(head >= 0 and actor.editor._hair_mask_mode == &"auto")
	var inverse_head := (skeleton.global_transform * skeleton.get_bone_global_pose(head)).affine_inverse()
	var option := actor.editor.part_options[&"hair"] as OptionButton
	var definition: Dictionary = actor.editor._component_definition(&"hair", StringName(option.get_item_metadata(option.selected)))
	var result := {}
	for node: Node in actor.editor._find_component_nodes(definition.prefixes):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var surfaces: Array[Dictionary] = []
		for surface: int in mesh.mesh.get_surface_count():
			var material := mesh.get_surface_override_material(surface) as ShaderMaterial
			assert(material != null)
			var values := {}
			for parameter: String in ["mask_enabled", "inv_head_transform", "dye_enabled", "dye_color", "brow_cut_y", "tuck_hair_piece"]:
				values[parameter] = material.get_shader_parameter(parameter)
			if check_current_head:
				assert(values.inv_head_transform == inverse_head, "Repeated equal yaw must not skip original hair-mask refresh after seek")
				hair_uniform_checks += 1
			surfaces.append(values)
		result[str(actor.editor.model_root.get_path_to(mesh))] = {"visible": mesh.visible, "surfaces": surfaces}
	assert(not result.is_empty())
	return result

func _cosmetic_snapshot() -> Dictionary:
	var result := super._cosmetic_snapshot()
	result.appearance = actor.editor.capture_appearance()
	result.selected_hair = _selected_hair_uniforms()
	result.part_visibility = {}
	for mesh: MeshInstance3D in model_meshes:
		result.part_visibility[str(actor.editor.model_root.get_path_to(mesh))] = [mesh.visible, mesh.is_visible_in_tree()]
	return result

func _fallback_checks(item: Dictionary) -> bool:
	if not super._fallback_checks(item):
		return false
	assert(rotation_checks == 111 and unexpected_pivot_checks == 36)
	assert(equal_rotation_checks > 0 and hair_uniform_checks > 0, "Must exercise actual-equal assignments and original hair refresh")
	return true

func _source_hashes() -> Dictionary:
	var hashes := super._source_hashes()
	for path: String in ["res://scripts/mount/mount_horse_3d.gd", MountHorse3D.HORSE_MODEL_PATH]:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes
