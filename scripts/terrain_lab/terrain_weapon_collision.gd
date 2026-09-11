extends RefCounted
## Collision lives in the same 2D space as the rendered characters. Weapon
## convex parts follow CPU-skinned mesh vertices; body capsules follow bones.
## No viewport rectangle, tile radius, cape or holstered weapon is a hitbox.

var _surfaces: Dictionary = {}
var _head_bounds: Dictionary = {}
const LIMBS := [
	["J_Bip_C_Hips", "J_Bip_C_Chest", 0.16],
	["J_Bip_C_Neck", "J_Bip_C_Head", 0.13],
	["J_Bip_L_UpperArm", "J_Bip_L_LowerArm", 0.065],
	["J_Bip_L_LowerArm", "J_Bip_L_Hand", 0.055],
	["J_Bip_R_UpperArm", "J_Bip_R_LowerArm", 0.065],
	["J_Bip_R_LowerArm", "J_Bip_R_Hand", 0.055],
	["J_Bip_L_UpperLeg", "J_Bip_L_LowerLeg", 0.09],
	["J_Bip_L_LowerLeg", "J_Bip_L_Foot", 0.065],
	["J_Bip_R_UpperLeg", "J_Bip_R_LowerLeg", 0.09],
	["J_Bip_R_LowerLeg", "J_Bip_R_Foot", 0.065],
]

func project(actor: TerrainTestCharacter, point: Vector3) -> Vector2:
	var viewport_point := actor.editor.camera.unproject_position(point)
	return actor.player_sprite.to_global(viewport_point - Vector2(actor.editor.preview_viewport.size) * 0.5)

func body_shapes(actor: TerrainTestCharacter) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var skeleton := actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return result
	skeleton.force_update_all_bone_transforms()
	for limb: Array in LIMBS:
		var a := skeleton.find_bone(limb[0])
		var b := skeleton.find_bone(limb[1])
		if a < 0 or b < 0:
			continue
		var start := skeleton.global_transform * skeleton.get_bone_global_pose(a).origin
		var end := skeleton.global_transform * skeleton.get_bone_global_pose(b).origin
		var centre := project(actor, start)
		var radius := centre.distance_to(project(actor, start + actor.editor.camera.global_basis.x * float(limb[2])))
		result.append(capsule(centre, project(actor, end), radius))
	var head_shape := head_shape_from_mesh(actor, skeleton)
	if not head_shape.is_empty() and result.size() > 1:
		result[1] = head_shape
	return result

func head_shape_from_mesh(actor: TerrainTestCharacter, skeleton: Skeleton3D) -> PackedVector2Array:
	var head := skeleton.find_bone("J_Bip_C_Head")
	if head < 0:
		return PackedVector2Array()
	var head_world := skeleton.global_transform * skeleton.get_bone_global_pose(head)
	for node: Node in actor.editor.model_root.find_children("Face_Standard*", "MeshInstance3D", true, false):
		var face := node as MeshInstance3D
		if not face.is_visible_in_tree() or face.mesh == null:
			continue
		var key := face.get_instance_id()
		if not _head_bounds.has(key):
			if _head_bounds.size() > 16:
				_head_bounds.clear()
			var vertices := posed_vertices(face, skeleton)
			if vertices.is_empty():
				continue
			var inverse := head_world.affine_inverse()
			var local_bounds := AABB(inverse * vertices[0], Vector3.ZERO)
			for vertex: Vector3 in vertices:
				local_bounds = local_bounds.expand(inverse * vertex)
			_head_bounds[key] = local_bounds
		# The head bone sits at the neck, not at the skull centre. Fit the
		# actual face mesh once; hair/helmets never enlarge this hurtbox.
		var head_bounds: AABB = _head_bounds[key]
		var points := PackedVector2Array()
		for corner in range(8):
			points.append(project(actor, head_world * head_bounds.get_endpoint(corner)))
		return Geometry2D.convex_hull(points)
	return PackedVector2Array()

static func capsule(start: Vector2, end: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(12):
		var offset := Vector2.from_angle(TAU * i / 12.0) * radius
		points.append(start + offset)
		points.append(end + offset)
	return Geometry2D.convex_hull(points)

func weapon_shapes(actor: TerrainTestCharacter, clip: StringName) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var skeleton := actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return result
	skeleton.force_update_all_bone_transforms()
	if clip == &"attack_unarmed":
		var knee := skeleton.find_bone("J_Bip_R_LowerLeg")
		var foot := skeleton.find_bone("J_Bip_R_Foot")
		if knee >= 0 and foot >= 0:
			result.append(capsule(project(actor, skeleton.global_transform * skeleton.get_bone_global_pose(knee).origin), project(actor, skeleton.global_transform * skeleton.get_bone_global_pose(foot).origin), 3.0))
		return result
	if clip in [&"attack_bow", &"attack_crossbow"]:
		return result # Projectiles, never the bow mesh, deal ranged damage.
	for node: Node in actor.editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		var label := str(part.name)
		if not part.is_visible_in_tree() or not label.begins_with("Weapon_") or part.mesh == null:
			continue
		if "Holstered" in label or "Sheathed" in label or "Scabbard" in label or "Grip" in label or "Handle" in label or "Guard" in label or "Shaft" in label:
			continue
		var points := posed_points(actor, part, skeleton)
		if points.size() >= 3:
			result.append(Geometry2D.convex_hull(points))
	return result

func posed_points(actor: TerrainTestCharacter, part: MeshInstance3D, skeleton: Skeleton3D) -> PackedVector2Array:
	var points := PackedVector2Array()
	for vertex: Vector3 in posed_vertices(part, skeleton):
		points.append(project(actor, vertex))
	return points

func posed_vertices(part: MeshInstance3D, skeleton: Skeleton3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	var palette: Array[Transform3D] = []
	if part.skin != null:
		for i in range(part.skin.get_bind_count()):
			var bone := part.skin.get_bind_bone(i)
			if bone < 0:
				bone = skeleton.find_bone(part.skin.get_bind_name(i))
			palette.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * part.skin.get_bind_pose(i) if bone >= 0 else part.global_transform)
	for surface in range(part.mesh.get_surface_count()):
		var key := "%d:%d" % [part.mesh.get_instance_id(), surface]
		if not _surfaces.has(key):
			# Cache arrays only while the selected model exists; resources can be
			# swapped in the editor. Bounded two-character LAB, not crowd rendering.
			if _surfaces.size() > 128:
				_surfaces.clear()
			_surfaces[key] = part.mesh.surface_get_arrays(surface)
		var arrays: Array = _surfaces[key]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var influences := int(float(bones.size()) / maxf(1.0, vertices.size()))
		for v in range(vertices.size()):
			var point := part.global_transform * vertices[v]
			if not palette.is_empty() and influences > 0:
				point = Vector3.ZERO
				for slot in range(influences):
					var index := v * influences + slot
					point += (palette[bones[index]] * vertices[v]) * weights[index]
			points.append(point)
	return points

func aim_weapon_attack(actor: TerrainTestCharacter, aim_point: Vector2, weight: float) -> void:
	if weight <= 0.0:
		return
	var skeleton := actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var arm := skeleton.find_bone("J_Bip_R_UpperArm")
	var hand := skeleton.find_bone("J_Bip_R_Hand")
	if arm < 0 or hand < 0:
		return
	skeleton.force_update_all_bone_transforms()
	var arm_world := skeleton.global_transform * skeleton.get_bone_global_pose(arm)
	var hand_world := skeleton.global_transform * skeleton.get_bone_global_pose(hand).origin
	var tip := hand_world
	var furthest := 0.0
	for node: Node in actor.editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		var label := str(part.name)
		if not part.is_visible_in_tree() or not label.begins_with("Weapon_") or part.mesh == null:
			continue
		if not ("Blade" in label or "Head" in label or "Tip" in label) or "Holstered" in label or "Sheathed" in label:
			continue
		for vertex: Vector3 in posed_vertices(part, skeleton):
			var distance := vertex.distance_squared_to(hand_world)
			if distance > furthest:
				furthest = distance
				tip = vertex
	if furthest <= 0.0:
		return
	# Solve the hand/elbow/shoulder chain toward a fixed attack aim point.
	# Root, saddle, limb lengths and weapon geometry are never translated/scaled.
	var camera := actor.editor.camera
	var pixel := actor.player_sprite.to_local(aim_point) + Vector2(actor.editor.preview_viewport.size) * 0.5
	var ray_start := camera.project_ray_origin(pixel)
	var ray := camera.project_ray_normal(pixel)
	var destination := ray_start + ray * (arm_world.origin - ray_start).dot(ray)
	var hand_transform := skeleton.global_transform * skeleton.get_bone_global_pose(hand)
	var tip_in_hand := hand_transform.affine_inverse() * tip
	var elbow := skeleton.find_bone("J_Bip_R_LowerArm")
	if elbow < 0:
		return
	var chain: Array[int] = [hand, elbow, arm]
	if actor.editor.is_mounted:
		# A rider must lean from the waist to strike a standing target below.
		# Keep hips/legs attached to the saddle and preserve all bone lengths.
		var ancestor := skeleton.get_bone_parent(arm)
		while ancestor >= 0 and skeleton.get_bone_name(ancestor) != "J_Bip_C_Hips":
			chain.append(ancestor)
			ancestor = skeleton.get_bone_parent(ancestor)
	var original: Array[Quaternion] = []
	for joint: int in chain:
		original.append(skeleton.get_bone_pose_rotation(joint))
	for iteration in range(64):
		for joint: int in chain:
			var joint_world := skeleton.global_transform * skeleton.get_bone_global_pose(joint)
			var current_endpoint := skeleton.global_transform * skeleton.get_bone_global_pose(hand) * tip_in_hand
			var from := current_endpoint - joint_world.origin
			var to := destination - joint_world.origin
			if from.length_squared() < 0.00001 or to.length_squared() < 0.00001:
				continue
			var turn := Quaternion(from.normalized(), to.normalized())
			var desired := Transform3D(Basis(turn) * joint_world.basis, joint_world.origin)
			var parent_world := skeleton.global_transform
			var parent := skeleton.get_bone_parent(joint)
			if parent >= 0:
				parent_world *= skeleton.get_bone_global_pose(parent)
			# Godot 4 bone pose is already parent-local (including rest).
			# Removing rest again twists imported joints and breaks convergence.
			var pose := parent_world.affine_inverse() * desired
			skeleton.set_bone_pose_rotation(joint, pose.basis.get_rotation_quaternion())
			skeleton.force_update_all_bone_transforms()
		var final_endpoint := skeleton.global_transform * skeleton.get_bone_global_pose(hand) * tip_in_hand
		if final_endpoint.distance_squared_to(destination) < 0.0001:
			break
	for i in range(chain.size()):
		var solved := skeleton.get_bone_pose_rotation(chain[i])
		skeleton.set_bone_pose_rotation(chain[i], original[i].slerp(solved, weight))
	skeleton.force_update_all_bone_transforms()

static func swept_contact(previous: Array[PackedVector2Array], current: Array[PackedVector2Array], bodies: Array[PackedVector2Array]) -> bool:
	for i in range(current.size()):
		var sweep := current[i].duplicate()
		if i < previous.size():
			sweep.append_array(previous[i])
		sweep = Geometry2D.convex_hull(sweep)
		for body: PackedVector2Array in bodies:
			if not Geometry2D.intersect_polygons(sweep, body).is_empty():
				return true
	return false
