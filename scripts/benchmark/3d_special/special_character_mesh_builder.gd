class_name SpecialCharacterMeshBuilder
extends RefCounted

const HumanRigType = preload("res://scripts/benchmark/3d_crowd/human_rig_v1.gd")
const DefinitionType = preload("res://scripts/benchmark/3d_special/special_visual_definition.gd")

## ponytail: these small box lists are compile-time prototype asset recipes, not runtime state.

static func build_body_region_meshes() -> Array:
	var result: Array = []
	result.append(_build_mesh([
		_box(Vector3(0.0, 1.94, 0.0), Vector3(0.34, 0.34, 0.34), HumanRigType.Bone.HEAD)
	], true))
	result.append(_build_mesh([
		_box(Vector3(0.0, 1.29, 0.0), Vector3(0.52, 0.72, 0.30), HumanRigType.Bone.CHEST)
	], true))
	result.append(_build_mesh([
		_box(Vector3(-0.34, 1.24, 0.0), Vector3(0.14, 0.34, 0.16), HumanRigType.Bone.UPPER_ARM_L),
		_box(Vector3(-0.34, 0.88, 0.0), Vector3(0.13, 0.30, 0.14), HumanRigType.Bone.LOWER_ARM_L),
		_box(Vector3(0.34, 1.24, 0.0), Vector3(0.14, 0.34, 0.16), HumanRigType.Bone.UPPER_ARM_R),
		_box(Vector3(0.34, 0.88, 0.0), Vector3(0.13, 0.30, 0.14), HumanRigType.Bone.LOWER_ARM_R)
	], true))
	result.append(_build_mesh([
		_box(Vector3(-0.34, 0.57, 0.0), Vector3(0.14, 0.14, 0.14), HumanRigType.Bone.HAND_L),
		_box(Vector3(0.34, 0.57, 0.0), Vector3(0.14, 0.14, 0.14), HumanRigType.Bone.HAND_R)
	], true))
	result.append(_build_mesh([
		_box(Vector3(-0.14, 0.67, 0.0), Vector3(0.17, 0.38, 0.17), HumanRigType.Bone.UPPER_LEG_L),
		_box(Vector3(-0.14, 0.29, 0.0), Vector3(0.16, 0.36, 0.16), HumanRigType.Bone.LOWER_LEG_L),
		_box(Vector3(0.14, 0.67, 0.0), Vector3(0.17, 0.38, 0.17), HumanRigType.Bone.UPPER_LEG_R),
		_box(Vector3(0.14, 0.29, 0.0), Vector3(0.16, 0.36, 0.16), HumanRigType.Bone.LOWER_LEG_R)
	], true))
	result.append(_build_mesh([
		_box(Vector3(-0.14, 0.08, 0.08), Vector3(0.18, 0.12, 0.28), HumanRigType.Bone.FOOT_L),
		_box(Vector3(0.14, 0.08, 0.08), Vector3(0.18, 0.12, 0.28), HumanRigType.Bone.FOOT_R)
	], true))
	return result

static func build_head_mesh() -> ArrayMesh:
	return _build_mesh([
		_box(Vector3(0.0, 0.0, 0.0), Vector3(0.34, 0.34, 0.34), HumanRigType.Bone.HEAD)
	], true)

static func build_armor_mesh(armor_id: StringName) -> ArrayMesh:
	var boxes: Array = []
	match armor_id:
		&"cloth_01":
			boxes = [
				_box(Vector3(0.0, 1.30, 0.0), Vector3(0.58, 0.78, 0.34), HumanRigType.Bone.CHEST)
			]
		&"leather_01":
			boxes = [
				_box(Vector3(0.0, 1.30, 0.0), Vector3(0.62, 0.80, 0.38), HumanRigType.Bone.CHEST),
				_box(Vector3(-0.34, 1.25, 0.0), Vector3(0.18, 0.36, 0.20), HumanRigType.Bone.UPPER_ARM_L),
				_box(Vector3(0.34, 1.25, 0.0), Vector3(0.18, 0.36, 0.20), HumanRigType.Bone.UPPER_ARM_R)
			]
		&"plate_01":
			boxes = [
				_box(Vector3(0.0, 1.30, 0.0), Vector3(0.68, 0.84, 0.44), HumanRigType.Bone.CHEST),
				_box(Vector3(-0.35, 1.26, 0.0), Vector3(0.22, 0.40, 0.24), HumanRigType.Bone.UPPER_ARM_L),
				_box(Vector3(-0.35, 0.87, 0.0), Vector3(0.18, 0.32, 0.20), HumanRigType.Bone.LOWER_ARM_L),
				_box(Vector3(0.35, 1.26, 0.0), Vector3(0.22, 0.40, 0.24), HumanRigType.Bone.UPPER_ARM_R),
				_box(Vector3(0.35, 0.87, 0.0), Vector3(0.18, 0.32, 0.20), HumanRigType.Bone.LOWER_ARM_R),
				_box(Vector3(-0.14, 0.67, 0.0), Vector3(0.22, 0.40, 0.22), HumanRigType.Bone.UPPER_LEG_L),
				_box(Vector3(-0.14, 0.29, 0.0), Vector3(0.20, 0.36, 0.20), HumanRigType.Bone.LOWER_LEG_L),
				_box(Vector3(0.14, 0.67, 0.0), Vector3(0.22, 0.40, 0.22), HumanRigType.Bone.UPPER_LEG_R),
				_box(Vector3(0.14, 0.29, 0.0), Vector3(0.20, 0.36, 0.20), HumanRigType.Bone.LOWER_LEG_R)
			]
	return _build_mesh(boxes, true)

static func build_hair_mesh(hair_id: StringName) -> ArrayMesh:
	var size := Vector3(0.40, 0.18, 0.40)
	var center := Vector3(0.0, 0.15, -0.02)
	if hair_id == &"hair_long_01":
		size = Vector3(0.44, 0.42, 0.40)
		center = Vector3(0.0, 0.02, -0.04)
	return _build_mesh([_box(center, size, 0)], false)

static func build_helmet_mesh() -> ArrayMesh:
	return _build_mesh([
		_box(Vector3(0.0, 0.08, 0.0), Vector3(0.44, 0.18, 0.44), 0),
		_box(Vector3(0.0, 0.20, 0.0), Vector3(0.12, 0.12, 0.30), 0)
	], false)

static func build_sword_mesh() -> ArrayMesh:
	return _build_mesh([
		_box(Vector3(0.0, -0.42, 0.0), Vector3(0.075, 0.72, 0.045), 0),
		_box(Vector3(0.0, -0.02, 0.0), Vector3(0.13, 0.16, 0.10), 0)
	], false)

static func build_shield_mesh() -> ArrayMesh:
	return _build_mesh([
		_box(Vector3(0.0, -0.25, -0.04), Vector3(0.50, 0.62, 0.10), 0),
		_box(Vector3(0.0, -0.25, -0.10), Vector3(0.16, 0.18, 0.08), 0)
	], false)

static func _box(center: Vector3, size: Vector3, bone_index: int) -> Dictionary:
	return {"center": center, "size": size, "bone": bone_index}

static func _build_mesh(boxes: Array, skinned: bool) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	for spec: Dictionary in boxes:
		_append_box(vertices, normals, uvs, bones, weights, indices, spec, skinned)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if skinned:
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func _append_box(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	bones: PackedInt32Array,
	weights: PackedFloat32Array,
	indices: PackedInt32Array,
	spec: Dictionary,
	skinned: bool
) -> void:
	var center: Vector3 = spec.center
	var half: Vector3 = spec.size * 0.5
	var bone_index: int = spec.bone
	var faces: Array = [
		{"corners": [Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)], "normal": Vector3.FORWARD},
		{"corners": [Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)], "normal": Vector3.BACK},
		{"corners": [Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)], "normal": Vector3.UP},
		{"corners": [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1)], "normal": Vector3.DOWN},
		{"corners": [Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1)], "normal": Vector3.RIGHT},
		{"corners": [Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)], "normal": Vector3.LEFT}
	]
	for face: Dictionary in faces:
		var base_index: int = vertices.size()
		var corners: Array = face.corners
		var normal: Vector3 = face.normal
		for corner_index: int in range(4):
			vertices.append(center + Vector3(corners[corner_index]) * half)
			normals.append(normal)
			uvs.append(Vector2(0.0 if corner_index == 0 or corner_index == 3 else 1.0, 0.0 if corner_index < 2 else 1.0))
			if skinned:
				bones.append(bone_index)
				bones.append(0)
				bones.append(0)
				bones.append(0)
				weights.append(1.0)
				weights.append(0.0)
				weights.append(0.0)
				weights.append(0.0)
		indices.append(base_index)
		indices.append(base_index + 1)
		indices.append(base_index + 2)
		indices.append(base_index)
		indices.append(base_index + 2)
		indices.append(base_index + 3)
