extends "res://scripts/tests/site_army_constant_morph_test.gd"
## GPU --group=0 synthetic guards, --group=1 original male, --group=2 original female.
## Internal 23 seconds / unchanged canonical helper 25 seconds per group.
## Full ordered hull bits and original indexed arrays; not an FPS benchmark.
const OriginalGeometry = preload("res://output/site_combat_performance_20260913/before/terrain_weapon_collision.gd")
const ORIGINAL_SHA := "151E950DAF13B63F536404146F42828B2D279C9FD6E7833EF462023A8089B782"
const GEOMETRY_PATH := "res://scripts/terrain_lab/terrain_weapon_collision.gd"

class DispatchGeometry extends Geometry:
	var calls := 0
	func posed_points(actor: Variant, part: MeshInstance3D, skeleton: Skeleton3D) -> PackedVector2Array:
		calls += 1
		return super.posed_points(actor, part, skeleton)

class ProjectionEditor extends RefCounted:
	var model_root: Node3D
	var camera: Camera3D
	var preview_viewport: SubViewport

var dedup_report := {"pairs": 0, "guards": 0, "original_usec": 0, "candidate_usec": 0, "removed_local_vertices": 0, "actual_shorter_projections": 0,
	"silhouette_passes": [], "silhouette_scope": "Warmed same-pose weapon_shapes + shield_shapes only; false/true/true/false, eight pairs per phase; no armor, pose resets, loading, cache warming or reduction counting inside timing"}
var dedup_completed := false

func run() -> void:
	var began := Time.get_ticks_usec()
	morph_deadline_usec = began + 23000000
	create_timer(23.0).timeout.connect(func() -> void: push_error("Rigid hull dedup deadline"); quit(1))
	assert(group in [0, 1, 2] and DisplayServer.get_name() != "headless")
	assert(FileAccess.get_sha256("res://output/site_combat_performance_20260913/before/terrain_weapon_collision.gd").to_upper() == ORIGINAL_SHA)
	var geometry_hash := FileAccess.get_sha256(GEOMETRY_PATH)
	if group == 0:
		await _synthetic_dedup()
	else:
		await _actual_dedup()
	if not dedup_completed:
		quit(1) # A nested assertion is never allowed to fall through to PASS.
		return
	_deadline()
	assert(FileAccess.get_sha256(GEOMETRY_PATH) == geometry_hash)
	dedup_report.merge({"group": group, "elapsed_usec": Time.get_ticks_usec() - began, "geometry_sha256": geometry_hash,
		"internal_deadline_seconds": 23, "helper_timeout_seconds": 25, "maximum_error": 0.0,
		"scope": "Exact ordered closed hull bits, same original Actor, unchanged armor triangle indices/Head/IK vertex order; no FPS claim"})
	var directory := "res://output/site_combat_performance_20260913/rigid_hull_dedup/group%d_%d_%d" % [group, int(Time.get_unix_time_from_system()), began]
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK)
	var file := FileAccess.open(directory + "/measurements.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(dedup_report, "\t"))
	file.close()
	print("SITE_RIGID_HULL_DEDUP_PASS ", JSON.stringify(dedup_report))
	quit(0)

func _same_bits(expected: Variant, actual: Variant) -> bool:
	var differences: Array[Dictionary] = []
	_snapshot_byte_diff(expected, actual, "$", differences)
	if not differences.is_empty():
		push_error("Rigid hull exact mismatch: " + str(differences))
	return differences.is_empty()

func _synthetic_dedup() -> void:
	var geometry := Geometry.new()
	geometry.rigid_hull_dedup_enabled = true
	var a := Vector3(0.25, 0.25, 0.0)
	var b := Vector3(0.75, 0.25, 0.0)
	var c := Vector3(0.25, 0.75, 0.0)
	var vertices := PackedVector3Array([a, b, c, a, b, c])
	assert(_same_bits(Geometry._unique_rigid_vertices(vertices), PackedVector3Array([a, b, c])))
	for degenerate: PackedVector3Array in [PackedVector3Array([a, a, a]), PackedVector3Array([a, b, a, b, a, b]),
		PackedVector3Array([Vector3.INF, b, c, Vector3.INF, b, c])]:
		assert(_same_bits(Geometry._unique_rigid_vertices(degenerate), degenerate))
		dedup_report.guards += 1
	var negative_zero := PackedByteArray([0, 0, 0, 128]).decode_float(0)
	assert(PackedFloat32Array([negative_zero]).to_byte_array() == PackedByteArray([0, 0, 0, 128]))
	var zeros := PackedVector3Array([Vector3(0.0, 1, 0), Vector3(negative_zero, 1, 0), b, c, b, c])
	assert(var_to_bytes(zeros[0]) != var_to_bytes(zeros[1]))
	assert(Geometry._unique_rigid_vertices(zeros).size() == 4, "Do not hash Vector3 numeric equality: signed zeros differ")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	world.add_child(camera)
	camera.position = Vector3(0, 0, 5)
	camera.current = true
	var rig := Skeleton3D.new()
	rig.name = "Skeleton3D"
	world.add_child(rig)
	for bone in range(2):
		rig.add_bone("Bone%d" % bone)
		rig.set_bone_rest(bone, Transform3D.IDENTITY)
		rig.set_bone_pose_position(bone, Vector3(0.17 * bone, 0.21 * bone, 0))
	var part := MeshInstance3D.new()
	part.name = "Weapon_Test_Blade"
	var skin := Skin.new()
	skin.add_bind(0, Transform3D.IDENTITY)
	skin.add_bind(1, Transform3D.IDENTITY)
	part.skin = skin
	part.skeleton = NodePath("../Skeleton3D")
	world.add_child(part)
	var sprite := Sprite2D.new()
	root.add_child(sprite)
	sprite.position = Vector2(17, 23)
	var editor := ProjectionEditor.new()
	editor.model_root = world
	editor.camera = camera
	editor.preview_viewport = viewport
	var proxy := {"editor": editor, "player_sprite": sprite}
	await process_frame
	for spec: Array in [[false, false, -1], [true, false, -1], [false, true, -1], [false, false, 1]]:
		part.mesh = _dedup_mesh(vertices, spec[0], spec[1], spec[2])
		for phase in range(2):
			if spec[1]:
				part.set_blend_shape_value(0, 0.0 if phase == 0 else 0.5)
			rig.set_bone_pose_rotation(0, Quaternion.from_euler(Vector3(0.11 * phase, 0.21 * phase, -0.13 * phase)))
			geometry.rigid_hull_dedup_enabled = false
			var original := geometry.posed_vertices(part, rig)
			var original_points := geometry.posed_points(proxy, part, rig)
			geometry.rigid_hull_dedup_enabled = true
			assert(_same_bits(geometry.posed_vertices(part, rig), original))
			assert(_same_bits(geometry.posed_points(proxy, part, rig), original_points))
			var compact := geometry.posed_vertices(part, rig, true, true)
			assert(compact.size() == original.size() if spec[0] or spec[1] else compact.size() * 2 == original.size())
			assert(_same_bits(Geometry2D.convex_hull(original_points), Geometry2D.convex_hull(geometry._posed_points(proxy, part, rig, true))))
			dedup_report.pairs += 1
	# Identical positions on different weight-one bones are not duplicates.
	part.mesh = _dedup_mesh(vertices)
	var split_arrays := part.mesh.surface_get_arrays(0)
	var split_bones: PackedInt32Array = split_arrays[Mesh.ARRAY_BONES]
	split_bones[12] = 1
	split_arrays[Mesh.ARRAY_BONES] = split_bones
	var split_mesh := ArrayMesh.new()
	split_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, split_arrays)
	part.mesh = split_mesh
	assert(geometry.posed_vertices(part, rig, true, true).size() == vertices.size())
	# Replacing skin retains the same local cache but must use the actual new bind.
	part.mesh = _dedup_mesh(vertices)
	geometry.posed_vertices(part, rig, true, true)
	var replacement := Skin.new()
	replacement.add_bind(1, Transform3D(Basis.IDENTITY, Vector3(0.2, -0.1, 0)))
	part.skin = replacement
	assert(_same_bits(Geometry2D.convex_hull(geometry.posed_points(proxy, part, rig)), Geometry2D.convex_hull(geometry._posed_points(proxy, part, rig, true))))
	# Existing clear hooks reset both original-array and rigid metadata generation.
	geometry._surfaces.clear()
	geometry._rigid_surfaces.clear()
	part.mesh = _dedup_mesh(PackedVector3Array([a, b, c, a + Vector3(0.01, 0, 0), b, c]))
	assert(geometry.posed_vertices(part, rig, true, true).size() == 4)
	part.skin = skin
	rig.reset_bone_poses()
	sprite.position = Vector2.ZERO
	var axial := PackedVector3Array([Vector3(0, 0.25, 0), b, c, Vector3(0, 0.25, 0), b, c])
	part.mesh = _dedup_mesh(axial)
	assert(geometry.posed_points(proxy, part, rig)[0].x == 0.0)
	assert(_same_bits(geometry._posed_points(proxy, part, rig, true), geometry.posed_points(proxy, part, rig)), "Zero-sign sort risk returns the full original ordered points")
	sprite.position = Vector2(1000000000.0, 1000000000.0)
	assert(_same_bits(geometry._posed_points(proxy, part, rig, true), geometry.posed_points(proxy, part, rig)), "Large cross-product input retains legacy path")
	sprite.position = Vector2(17, 23)
	part.mesh = _dedup_mesh(PackedVector3Array([a, b, Vector3(1.25, 0.25, 0), a, b, Vector3(1.25, 0.25, 0)]))
	assert(_same_bits(Geometry2D.convex_hull(geometry.posed_points(proxy, part, rig)), Geometry2D.convex_hull(geometry._posed_points(proxy, part, rig, true))), "Collinear closed hull retains original bits/order")
	var dispatch := DispatchGeometry.new()
	dispatch.rigid_hull_dedup_enabled = false
	dispatch.weapon_shapes(proxy, &"walk_slash")
	assert(dispatch.calls == 1)
	part.name = "Shield_Test"
	dispatch.shield_shapes(proxy)
	assert(dispatch.calls == 2, "Flag false preserves public override dispatch")
	dedup_report.guards += 8
	viewport.free()
	sprite.free()
	dedup_completed = true

func _dedup_mesh(vertices: PackedVector3Array, mixed: bool = false, morph: bool = false, second_binding: int = -1) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if morph:
		mesh.add_blend_shape(&"TestDelta")
		mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE
	for binding: int in ([0] if second_binding < 0 else [0, second_binding]):
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		for _index in range(vertices.size()):
			bones.append_array(PackedInt32Array([binding, 1, 0, 0]))
			weights.append_array(PackedFloat32Array([0.25, 0.75, 0, 0]) if mixed else PackedFloat32Array([1, 0, 0, 0]))
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		var morphs: Array[Array] = []
		if morph:
			var target: Array = []
			target.resize(Mesh.ARRAY_MAX)
			var deltas := PackedVector3Array()
			for index in range(vertices.size()):
				deltas.append(Vector3(0.05 * index, 0, 0))
			target[Mesh.ARRAY_VERTEX] = deltas
			morphs.append(target)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, morphs)
	return mesh

func _actual_dedup() -> void:
	var actor := TerrainTestCharacter.new()
	actor.visual_state.body_index = group - 1
	actor.combat_driven_by_lab = true
	root.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	assert(actor.editor != null and actor.editor._body_index == group - 1 and not actor.editor.use_imported_model)
	actor.editor.set_process(false)
	actor.editor.set_playing(false)
	actor.editor.combat_ready = true
	actor.editor.visual_state.combat_ready = true
	actor.position = Vector2(961.25, 539.75)
	for selection: Array in [[&"helmet", &"helmet_mingguang_01"], [&"armor", &"armor_mingguang_01"],
		[&"outfit", &"outfit_chinese_lining_01"], [&"boots", &"boots_mingguang_01"]]:
		assert(actor.editor.select_part_by_id(selection[0], selection[1]))
	var rig := actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var ids := [actor.get_instance_id(), actor.editor.get_instance_id(), rig.get_instance_id()]
	var raw_path: String = HumanCharacter3DEditor.BODY_MODELS[group - 1].path
	var raw_hash := FileAccess.get_sha256(raw_path)
	var geometry := Geometry.new()
	var frozen := OriginalGeometry.new()
	var cases: Array = [[&"longsword_01", &"walk_slash", 0.317, true, 0.0], [&"longsword_01", &"guard", 0.073, false, 0.0],
		[&"axe_01", &"attack_axe", 0.417, true, 0.0], [&"dagger_01", &"attack_dagger", 0.533, false, 0.0],
		[&"hammer_01", &"attack_hammer", 0.427, true, 0.0], [&"spear_01", &"attack_spear", 0.617, false, 1.0],
		[&"longsword_01", &"down", 1.137, true, 0.0], [&"longsword_01", &"get_up", 0.337, true, 0.0],
		[&"none", &"attack_unarmed", 0.233, false, 0.0], [&"longsword_01", &"walk_slash", 0.417, true, 0.5]]
	for index in range(cases.size()):
		_deadline()
		var request: Array = cases[index]
		assert(actor.editor.select_part_by_id(&"weapon", request[0]))
		assert(actor.editor.select_part_by_id(&"shield", &"shield_heater_01" if request[3] else &"none"))
		actor.editor.set_preview_yaw_degrees([0.0, 180.0, -90.0, 90.0][index % 4])
		assert(actor.editor.select_animation_by_id(request[1]))
		actor.editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		actor.editor._on_timeline_changed(float(request[2]))
		actor.editor.animation_player.advance(0.0)
		actor.editor._update_combat_props()
		actor.editor._update_scabbard_pose()
		actor.editor._update_combat_cloth()
		actor._sync_render_projection()
		var local: Array = []
		for bone in range(rig.get_bone_count()):
			local.append([rig.get_bone_pose_position(bone), rig.get_bone_pose_rotation(bone), rig.get_bone_pose_scale(bone)])
		var original: Dictionary = {}
		for enabled: bool in [false, true]:
			geometry.rigid_hull_dedup_enabled = enabled
			for bone in range(local.size()):
				rig.set_bone_pose_position(bone, local[bone][0])
				rig.set_bone_pose_rotation(bone, local[bone][1])
				rig.set_bone_pose_scale(bone, local[bone][2])
			geometry.aim_weapon_attack(actor, actor.position + Vector2(18, 39), float(request[4]))
			var began := Time.get_ticks_usec()
			var snapshot := _actual_snapshot(geometry, actor, rig, request[1])
			dedup_report["candidate_usec" if enabled else "original_usec"] += Time.get_ticks_usec() - began
			if not enabled:
				original = snapshot
				assert(_same_bits(frozen.pose_snapshot(actor, request[1]), snapshot.pose), "Independent frozen full geometry oracle")
			else:
				assert(_same_bits(original, snapshot), "All ordered polygon bits, indexed armor vertices and post-IK bones must remain exact")
				dedup_report.pairs += 1
				_count_reduction(geometry, actor, rig)
		# Both paths and their full ordered hulls were checked above. Do not
		# reset bones, advance the pose, warm caches or count reductions here.
		for phase in range(4):
			_deadline()
			var enabled: bool = phase == 1 or phase == 2
			geometry.rigid_hull_dedup_enabled = enabled
			var silhouette_began := Time.get_ticks_usec()
			for _repeat in range(8):
				geometry.weapon_shapes(actor, request[1])
				geometry.shield_shapes(actor)
			var silhouette_elapsed := Time.get_ticks_usec() - silhouette_began
			dedup_report.silhouette_passes.append({"pose_index": index, "clip": str(request[1]), "time": float(request[2]),
				"phase": phase, "enabled": enabled, "elapsed_usec": silhouette_elapsed, "calls": 16, "weapon_calls": 8, "shield_calls": 8})
			_deadline()
		await process_frame
	assert(dedup_report.pairs == 10 and dedup_report.removed_local_vertices > 0 and dedup_report.actual_shorter_projections > 0)
	assert(dedup_report.silhouette_passes.size() == 40)
	assert(ids == [actor.get_instance_id(), actor.editor.get_instance_id(), rig.get_instance_id()] and FileAccess.get_sha256(raw_path) == raw_hash)
	dedup_report.raw_sha256 = raw_hash
	actor.free()
	dedup_completed = true

func _actual_snapshot(geometry: Variant, actor: TerrainTestCharacter, rig: Skeleton3D, clip: StringName) -> Dictionary:
	var result := {"pose": geometry.pose_snapshot(actor, clip), "bones": [], "protection": [], "indexed_vertices": {}}
	for bone in range(rig.get_bone_count()):
		result.bones.append([rig.get_bone_pose(bone), rig.get_bone_global_pose(bone)])
	for limb: int in [0, 3, 7, 9]:
		result.protection.append(geometry.armor_at(actor, centre(result.pose.body[limb]), "slash"))
	for node: Node in actor.editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.is_visible_in_tree() and part.mesh != null and (str(part.name).begins_with("Weapon_") or str(part.name).begins_with("Shield_") or str(part.name).begins_with("Face_Standard")):
			result.indexed_vertices[actor.editor.model_root.get_path_to(part)] = geometry.posed_vertices(part, rig)
	return result

func _count_reduction(geometry: Variant, actor: TerrainTestCharacter, rig: Skeleton3D) -> void:
	for node: Node in actor.editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if not part.is_visible_in_tree() or part.mesh == null or not (str(part.name).begins_with("Weapon_") or str(part.name).begins_with("Shield_")):
			continue
		var full: PackedVector3Array = geometry.posed_vertices(part, rig)
		var compact: PackedVector3Array = geometry.posed_vertices(part, rig, true, true)
		dedup_report.removed_local_vertices += full.size() - compact.size()
		var projected: PackedVector2Array = geometry._posed_points(actor, part, rig, true)
		dedup_report.actual_shorter_projections += int(projected.size() < full.size())
