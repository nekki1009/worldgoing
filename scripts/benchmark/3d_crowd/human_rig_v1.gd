class_name HumanRigV1
extends RefCounted

enum Bone {
	ROOT,
	PELVIS,
	SPINE,
	CHEST,
	NECK,
	HEAD,
	UPPER_ARM_L,
	LOWER_ARM_L,
	HAND_L,
	UPPER_ARM_R,
	LOWER_ARM_R,
	HAND_R,
	UPPER_LEG_L,
	LOWER_LEG_L,
	FOOT_L,
	UPPER_LEG_R,
	LOWER_LEG_R,
	FOOT_R,
	WEAPON_SOCKET_R,
	SHIELD_SOCKET_L,
	HEAD_SOCKET,
	BACK_SOCKET
}

const BONE_NAMES: Array[StringName] = [
	&"root", &"pelvis", &"spine", &"chest", &"neck", &"head",
	&"upper_arm_l", &"lower_arm_l", &"hand_l",
	&"upper_arm_r", &"lower_arm_r", &"hand_r",
	&"upper_leg_l", &"lower_leg_l", &"foot_l",
	&"upper_leg_r", &"lower_leg_r", &"foot_r",
	&"weapon_socket_r", &"shield_socket_l", &"head_socket", &"back_socket"
]

const PARENT_INDICES: Array[int] = [
	-1, Bone.ROOT, Bone.PELVIS, Bone.SPINE, Bone.CHEST, Bone.NECK,
	Bone.CHEST, Bone.UPPER_ARM_L, Bone.LOWER_ARM_L,
	Bone.CHEST, Bone.UPPER_ARM_R, Bone.LOWER_ARM_R,
	Bone.PELVIS, Bone.UPPER_LEG_L, Bone.LOWER_LEG_L,
	Bone.PELVIS, Bone.UPPER_LEG_R, Bone.LOWER_LEG_R,
	Bone.HAND_R, Bone.HAND_L, Bone.HEAD, Bone.CHEST
]

# HumanBase_v1 metric rest layout. Root is the ground contact origin; the hip
# is raised and the torso compressed so the Q silhouette keeps longer legs at
# the same 1.78m fitting height.
const REST_POSITIONS: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.94, 0.0), Vector3(0.0, 0.20, 0.0),
	Vector3(0.0, 0.19, 0.0), Vector3(0.0, 0.17, 0.0), Vector3(0.0, 0.12, 0.0),
	Vector3(-0.24, 0.01, 0.0), Vector3(-0.19, -0.27, 0.0), Vector3(-0.09, -0.24, 0.0),
	Vector3(0.24, 0.01, 0.0), Vector3(0.19, -0.27, 0.0), Vector3(0.09, -0.24, 0.0),
	Vector3(-0.115, -0.27, 0.0), Vector3(0.0, -0.33, 0.0), Vector3(0.0, -0.34, 0.0),
	Vector3(0.115, -0.27, 0.0), Vector3(0.0, -0.33, 0.0), Vector3(0.0, -0.34, 0.0),
	Vector3(0.07, -0.03, 0.12), Vector3(-0.07, -0.03, 0.12), Vector3(0.0, 0.0, 0.0),
	Vector3(0.0, -0.06, 0.16)
]

static func build_skeleton() -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = "HumanRig_v1"
	for bone_name: StringName in BONE_NAMES:
		skeleton.add_bone(bone_name)
	for index: int in range(BONE_NAMES.size()):
		skeleton.set_bone_parent(index, PARENT_INDICES[index])
		skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, REST_POSITIONS[index]))
	return skeleton

static func bone_indices() -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(BONE_NAMES.size())
	for index: int in range(BONE_NAMES.size()):
		result[index] = index
	return result

static func validate(skeleton: Skeleton3D) -> bool:
	if skeleton == null or skeleton.get_bone_count() != BONE_NAMES.size():
		return false
	for index: int in range(BONE_NAMES.size()):
		if skeleton.get_bone_name(index) != BONE_NAMES[index]:
			return false
	return true
