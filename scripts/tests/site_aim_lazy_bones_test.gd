extends SceneTree
## Independent frozen original versus current helper on the SAME reset original rig.
## GPU initialized original actor; one body/mount/weapon group, internal 23/helper 25 s.
const Frozen = preload("res://output/site_combat_performance_20260913/before/terrain_weapon_collision.gd")
const Current = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
const FROZEN_PATH := "res://output/site_combat_performance_20260913/before/terrain_weapon_collision.gd"
const CURRENT_PATH := "res://scripts/terrain_lab/terrain_weapon_collision.gd"
const FROZEN_SHA256 := "151E950DAF13B63F536404146F42828B2D279C9FD6E7833EF462023A8089B782"
const OUTPUT := "res://output/site_combat_performance_20260913/aim_lazy_bones/"
const GROUPS := {
	"male-ground-longsword": [0, false, "longsword_01"],
	"female-ground-longsword": [1, false, "longsword_01"],
	"male-mounted-longsword": [0, true, "longsword_01"],
	"female-mounted-longsword": [1, true, "longsword_01"],
	"male-ground-spear": [0, false, "spear_01"],
	"female-ground-spear": [1, false, "spear_01"],
}
var group := "male-ground-longsword"
var began_us := 0
var deadline_us := 0
var rows: Array[Dictionary] = []
var failures: Array[String] = []
var maxima := {"bone": 0.0, "polygon_vertex": 0.0, "mesh_vertex": 0.0, "mesh_transform": 0.0, "armor": 0.0, "reset": 0.0}
var original_us := 0
var current_us := 0
var frozen := Frozen.new()
var current := Current.new()
var actor: TerrainTestCharacter
var skeleton: Skeleton3D
var visible_parts: Array[MeshInstance3D] = []
var original_actor_id := 0
var original_editor_id := 0
var original_skeleton_id := 0

func _initialize() -> void:
	began_us = Time.get_ticks_usec()
	deadline_us = began_us + 23000000
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--group="):
			group = argument.trim_prefix("--group=")
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_usec() >= deadline_us:
		push_error("SITE_AIM_LAZY_BONES deadline: " + group)
		quit(1)
	return false

func _run() -> void:
	assert(GROUPS.has(group), "Choose one documented --group; never extend this group's deadline")
	assert(DisplayServer.get_name() != "headless", "Original actor initialization requires the GPU-backed viewport")
	assert(FileAccess.get_sha256(FROZEN_PATH).to_upper() == FROZEN_SHA256, "Frozen pre-optimization source must remain untouched")
	var old_text := FileAccess.get_file_as_string(FROZEN_PATH).replace("\r", "")
	var new_text := FileAccess.get_file_as_string(CURRENT_PATH).replace("\r", "")
	var original_inner := "skeleton.set_bone_pose_rotation(joint, pose.basis.get_rotation_quaternion())\n\t\t\tskeleton.force_update_all_bone_transforms()"
	assert(old_text.contains(original_inner) and not new_text.contains(original_inner), "Exercise the actual per-joint force removal, not two unchanged helpers")
	var body_index := int(GROUPS[group][0])
	var mounted := bool(GROUPS[group][1])
	var weapon := StringName(str(GROUPS[group][2]))
	actor = TerrainTestCharacter.new()
	actor.visual_state.body_index = body_index
	actor.person_id = 1
	actor.auto_face = false
	actor.combat_driven_by_lab = true
	root.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	assert(actor.editor != null and actor.editor._body_index == body_index and not actor.editor.use_imported_model)
	actor.editor.set_process(false)
	actor.editor.set_playing(false)
	# Explicit existing-asset geometry fixture, not equipment ownership or legal issue UI.
	for selection: Array in [[&"weapon", weapon], [&"helmet", &"helmet_mingguang_01"], [&"armor", &"armor_mingguang_01"],
		[&"outfit", &"outfit_chinese_lining_01"], [&"boots", &"boots_mingguang_01"]]:
		assert(actor.editor.select_part_by_id(selection[0], selection[1]), "Original asset unavailable: " + str(selection))
	actor.editor.combat_ready = true
	actor.editor.visual_state.combat_ready = true
	actor.editor.set_mount_enabled(mounted)
	assert(actor.editor.is_mounted == mounted)
	actor.facing = Vector2i.DOWN
	actor.position = Vector2(4800, 3600)
	actor.editor.set_preview_yaw_degrees(0.0)
	var clip: StringName = &"ride_slash" if mounted else HumanCharacter3DEditor.WEAPON_ATTACK_MAP[weapon]
	actor.play_pose(clip)
	assert(actor.editor.selected_animation == clip)
	actor.editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	actor.editor._on_timeline_changed(0.413)
	actor.editor.animation_player.advance(0.0)
	if mounted:
		assert(actor.editor.mount_horse != null)
		actor.editor.mount_horse.set_process(false)
		actor.editor.mount_horse.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	actor.editor._update_combat_props()
	actor.editor._update_scabbard_pose()
	actor.editor._update_combat_cloth()
	actor._sync_render_projection()
	skeleton = actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	assert(skeleton != null)
	skeleton.force_update_all_bone_transforms()
	original_actor_id = actor.get_instance_id()
	original_editor_id = actor.editor.get_instance_id()
	original_skeleton_id = skeleton.get_instance_id()
	for node: Node in actor.editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		var label := str(part.name)
		if part.is_visible_in_tree() and part.mesh != null and (label.begins_with("Weapon_") or label.begins_with("Shield_")) and not ("Scabbard" in label or "Holstered" in label or "Sheathed" in label):
			visible_parts.append(part)
	assert(not visible_parts.is_empty())
	var base_bones := _bones()
	var original_model_transform: Transform3D = actor.editor.model_root.global_transform
	var original_sprite_transform: Transform2D = actor.player_sprite.global_transform
	var original_camera_transform: Transform3D = actor.editor.camera.global_transform
	var chain := _chain(mounted, weapon)
	assert(chain.size() > 3 if mounted else chain.size() == (1 if weapon == &"spear_01" else 3))
	for aim_kind: String in ["normal", "unreachable"]:
		var aim := actor.position + (Vector2(0, 39) if aim_kind == "normal" else Vector2(4096, -2048))
		for weight: float in [0.0, 0.5, 1.0]:
			if Time.get_ticks_usec() >= deadline_us:
				failures.append("Bounded group deadline before case")
				_finish(false)
				return
			_check_case(clip, aim_kind, aim, weight, base_bones, chain)
			if actor.editor.model_root.global_transform != original_model_transform or actor.player_sprite.global_transform != original_sprite_transform or actor.editor.camera.global_transform != original_camera_transform:
				failures.append("Original ground/camera/model transform changed")
			if not failures.is_empty():
				_finish(false)
				return
			await process_frame # Yield only between complete original/new comparisons.
	assert(rows.size() == 6)
	_finish(true)

func _chain(mounted: bool, weapon: StringName) -> Array[String]:
	if not mounted and weapon == &"spear_01":
		return ["J_Bip_R_Hand"]
	var result: Array[String] = ["J_Bip_R_Hand", "J_Bip_R_LowerArm", "J_Bip_R_UpperArm"]
	if mounted:
		var ancestor := skeleton.get_bone_parent(skeleton.find_bone("J_Bip_R_UpperArm"))
		while ancestor >= 0 and skeleton.get_bone_name(ancestor) != "J_Bip_C_Hips":
			result.append(skeleton.get_bone_name(ancestor))
			ancestor = skeleton.get_bone_parent(ancestor)
	return result

func _bones() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(skeleton.get_bone_count()):
		result.append({"name": skeleton.get_bone_name(index), "position": skeleton.get_bone_pose_position(index),
			"rotation": skeleton.get_bone_pose_rotation(index), "scale": skeleton.get_bone_pose_scale(index),
			"local": skeleton.get_bone_pose(index), "global": skeleton.get_bone_global_pose(index)})
	return result

func _restore(base: Array[Dictionary]) -> void:
	# Animation seek alone can leave untracked ancestor joints carrying old IK.
	# Restore EVERY original local pose component, then flush original attachments.
	for index in range(base.size()):
		skeleton.set_bone_pose_position(index, base[index].position)
		skeleton.set_bone_pose_rotation(index, base[index].rotation)
		skeleton.set_bone_pose_scale(index, base[index].scale)
	skeleton.force_update_all_bone_transforms()
	var reset_error := _bone_difference(base, _bones())
	maxima.reset = maxf(float(maxima.reset), reset_error)
	if reset_error != 0.0:
		failures.append("Original full pose reset differs by " + str(reset_error))

func _check_case(clip: StringName, aim_kind: String, aim: Vector2, weight: float, base: Array[Dictionary], chain: Array[String]) -> void:
	_restore(base)
	if not failures.is_empty():
		return
	var started := Time.get_ticks_usec()
	frozen.aim_weapon_attack(actor, aim, weight)
	var old_us := Time.get_ticks_usec() - started
	var expected_bones := _bones()
	var expected := _geometry_snapshot(frozen, clip)
	var armor_points: Array[Vector2] = []
	for index: int in [0, 1, 3, 7]:
		var center := Vector2.ZERO
		for vertex: Vector2 in expected.body[index]:
			center += vertex
		armor_points.append(center / expected.body[index].size())
	armor_points.append(actor.position + Vector2(5000, 5000)) # Actual exposed miss, not all-positive protection.
	var expected_armor: Array[Vector2] = []
	for point: Vector2 in armor_points:
		expected_armor.append(frozen.armor_at(actor, point, "slash"))
	_restore(base)
	if not failures.is_empty():
		return
	started = Time.get_ticks_usec()
	current.aim_weapon_attack(actor, aim, weight)
	var new_us := Time.get_ticks_usec() - started
	var actual_bones := _bones()
	var actual := _geometry_snapshot(current, clip)
	var errors := {"bone": _bone_difference(expected_bones, actual_bones), "polygon_vertex": 0.0,
		"mesh_vertex": 0.0, "mesh_transform": 0.0, "armor": 0.0}
	var polygon_vertices := 0
	for kind: String in ["body", "weapon", "shield", "parry"]:
		if expected[kind].size() != actual[kind].size():
			failures.append("Polygon count differs: " + kind)
			continue
		for index in range(expected[kind].size()):
			var old_points: PackedVector2Array = expected[kind][index]
			var new_points: PackedVector2Array = actual[kind][index]
			if old_points.size() != new_points.size():
				failures.append("Polygon vertex count differs: " + kind)
				continue
			polygon_vertices += old_points.size()
			for vertex in range(old_points.size()):
				errors.polygon_vertex = maxf(float(errors.polygon_vertex), old_points[vertex].distance_to(new_points[vertex]))
	var mesh_vertices := 0
	for key: String in expected.mesh_vertices:
		var old_vertices: PackedVector3Array = expected.mesh_vertices[key]
		var new_vertices: PackedVector3Array = actual.mesh_vertices[key]
		if old_vertices.size() != new_vertices.size():
			failures.append("Actual weapon/shield mesh vertex count differs: " + key)
			continue
		mesh_vertices += old_vertices.size()
		for index in range(old_vertices.size()):
			errors.mesh_vertex = maxf(float(errors.mesh_vertex), old_vertices[index].distance_to(new_vertices[index]))
		errors.mesh_transform = maxf(float(errors.mesh_transform), _transform_difference(expected.mesh_transforms[key], actual.mesh_transforms[key]))
	var armor_nonzero := 0
	for index in range(armor_points.size()):
		var actual_armor: Vector2 = current.armor_at(actor, armor_points[index], "slash")
		errors.armor = maxf(float(errors.armor), expected_armor[index].distance_to(actual_armor))
		armor_nonzero += int(expected_armor[index] != Vector2.ZERO)
	if armor_nonzero == 0:
		failures.append("Armor fixture has no positive original protection sample")
	var changed: Array[String] = []
	for index in range(base.size()):
		if base[index].rotation != expected_bones[index].rotation:
			changed.append(str(base[index].name))
			if str(base[index].name) not in chain:
				failures.append("Aim changed a local rotation outside its original chain")
	if (weight == 0.0 and not changed.is_empty()) or (weight > 0.0 and changed.is_empty()):
		failures.append("Expected original weight/chain branch was not exercised")
	for key: String in errors:
		maxima[key] = maxf(float(maxima[key]), float(errors[key]))
		if float(errors[key]) != 0.0:
			failures.append("Strict mismatch " + key + " = " + str(errors[key]))
	original_us += old_us
	current_us += new_us
	var row := {"aim": aim_kind, "aim_point": [aim.x, aim.y], "weight": weight, "clip": str(clip), "sample_time": 0.413,
		"bones": base.size(), "chain": chain, "changed_local_bones": changed, "polygon_vertices": polygon_vertices,
		"actual_weapon_shield_mesh_vertices": mesh_vertices, "armor_points": armor_points.size(), "armor_positive_points": armor_nonzero,
		"original_aim_usec": old_us, "current_aim_usec": new_us, "maximum_errors": errors}
	rows.append(row)
	print("AIM_LAZY_BONES_CASE ", group, " ", JSON.stringify(row))

func _geometry_snapshot(geometry: Variant, clip: StringName) -> Dictionary:
	var result := {"body": geometry.body_shapes(actor), "weapon": geometry.weapon_shapes(actor, clip),
		"shield": geometry.shield_shapes(actor), "parry": geometry.weapon_shapes(actor, clip, true), "mesh_vertices": {}, "mesh_transforms": {}}
	for part: MeshInstance3D in visible_parts:
		var key := str(part.get_path())
		result.mesh_vertices[key] = geometry.posed_vertices(part, skeleton)
		result.mesh_transforms[key] = part.global_transform
	return result

func _transform_difference(a: Transform3D, b: Transform3D) -> float:
	return maxf(a.origin.distance_to(b.origin), maxf(a.basis.x.distance_to(b.basis.x), maxf(a.basis.y.distance_to(b.basis.y), a.basis.z.distance_to(b.basis.z))))

func _bone_difference(a: Array[Dictionary], b: Array[Dictionary]) -> float:
	if a.size() != b.size():
		failures.append("Original bone count changed")
		return 1.0e30
	var maximum := 0.0
	for index in range(a.size()):
		if a[index].name != b[index].name:
			failures.append("Original bone order changed")
		maximum = maxf(maximum, _transform_difference(a[index].local, b[index].local))
		maximum = maxf(maximum, _transform_difference(a[index].global, b[index].global))
		maximum = maxf(maximum, (a[index].position as Vector3).distance_to(b[index].position))
		maximum = maxf(maximum, (a[index].scale as Vector3).distance_to(b[index].scale))
		var ar: Quaternion = a[index].rotation
		var br: Quaternion = b[index].rotation
		maximum = maxf(maximum, maxf(absf(ar.x - br.x), maxf(absf(ar.y - br.y), maxf(absf(ar.z - br.z), absf(ar.w - br.w)))))
	return maximum

func _finish(passed: bool) -> void:
	if actor != null and (actor.get_instance_id() != original_actor_id or actor.editor.get_instance_id() != original_editor_id or skeleton.get_instance_id() != original_skeleton_id or actor.hp != 100.0):
		failures.append("Original actor/rig or HP changed")
	passed = passed and failures.is_empty() and rows.size() == 6
	var report := {"pass": passed, "group": group, "cases": rows.size(), "rows": rows, "maximum_errors": maxima,
		"failures": failures, "original_aim_usec": original_us, "current_aim_usec": current_us,
		"wall_ms": (Time.get_ticks_usec() - began_us) / 1000.0, "internal_deadline_seconds": 23,
		"frozen_source_sha256": FROZEN_SHA256, "current_source_sha256": FileAccess.get_sha256(CURRENT_PATH).to_upper(),
		"scope": "Same original raw male/female actor restored to every identical local bone pose; frozen pre-change helper versus current aim. Exact zero-error bone/global/local, collider and actual weapon/shield mesh vertices, armor coverage. Timings cover aim calls only, not 200-person FPS."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var file := FileAccess.open(OUTPUT + group + ".json", FileAccess.WRITE)
	if file == null:
		push_error("AIM_LAZY_BONES could not preserve report")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	if passed:
		print("SITE_AIM_LAZY_BONES_PASS ", JSON.stringify(report))
	else:
		push_error("SITE_AIM_LAZY_BONES_FAIL " + JSON.stringify(report))
	if is_instance_valid(actor):
		actor.free()
	quit(0 if passed else 1)
