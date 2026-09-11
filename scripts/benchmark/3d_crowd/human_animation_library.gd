class_name HumanAnimationLibrary
extends RefCounted

const AnimationStateType = preload("res://scripts/benchmark/3d_crowd/battle_crowd_simulation.gd")
const SpearmanArchetype: int = 2

static func build_library() -> AnimationLibrary:
	var library := AnimationLibrary.new()
	for clip_name: StringName in [&"idle", &"walk", &"attack_1h", &"attack_spear", &"dead"]:
		var animation := Animation.new()
		animation.length = 1.0
		library.add_animation(clip_name, animation)
	return library

static func clip_for(animation_state: int, archetype_id: int) -> StringName:
	match animation_state:
		AnimationStateType.AnimationState.ATTACK:
			return &"attack_spear" if archetype_id == SpearmanArchetype else &"attack_1h"
		AnimationStateType.AnimationState.WALK:
			return &"walk"
		AnimationStateType.AnimationState.DEAD:
			return &"dead"
		_:
			return &"idle"

static func sample(
	skeleton: Skeleton3D,
	bones: PackedInt32Array,
	animation_state: int,
	animation_time: float,
	animation_phase: float,
	archetype_id: int
) -> void:
	for bone_index: int in [
		HumanRigV1.Bone.PELVIS, HumanRigV1.Bone.SPINE, HumanRigV1.Bone.CHEST,
		HumanRigV1.Bone.HEAD, HumanRigV1.Bone.UPPER_ARM_L, HumanRigV1.Bone.LOWER_ARM_L,
		HumanRigV1.Bone.HAND_L, HumanRigV1.Bone.UPPER_ARM_R, HumanRigV1.Bone.LOWER_ARM_R,
		HumanRigV1.Bone.HAND_R, HumanRigV1.Bone.UPPER_LEG_L, HumanRigV1.Bone.LOWER_LEG_L,
		HumanRigV1.Bone.FOOT_L, HumanRigV1.Bone.UPPER_LEG_R, HumanRigV1.Bone.LOWER_LEG_R,
		HumanRigV1.Bone.FOOT_R
	]:
		skeleton.set_bone_pose_rotation(bones[bone_index], Quaternion.IDENTITY)
	skeleton.set_bone_pose_position(bones[HumanRigV1.Bone.PELVIS], Vector3.ZERO)

	var phase: float = animation_time * 7.5 + animation_phase * TAU
	match animation_state:
		AnimationStateType.AnimationState.WALK:
			var swing: float = sin(phase) * 0.58
			_set_rotation(skeleton, bones, HumanRigV1.Bone.UPPER_LEG_L, Vector3(swing, 0.0, 0.0))
			_set_rotation(skeleton, bones, HumanRigV1.Bone.UPPER_LEG_R, Vector3(-swing, 0.0, 0.0))
			_set_rotation(skeleton, bones, HumanRigV1.Bone.LOWER_LEG_L, Vector3(maxf(0.0, -swing) * 0.35, 0.0, 0.0))
			_set_rotation(skeleton, bones, HumanRigV1.Bone.LOWER_LEG_R, Vector3(maxf(0.0, swing) * 0.35, 0.0, 0.0))
			_set_rotation(skeleton, bones, HumanRigV1.Bone.UPPER_ARM_L, Vector3(-swing * 0.65, 0.0, 0.0))
			_set_rotation(skeleton, bones, HumanRigV1.Bone.UPPER_ARM_R, Vector3(swing * 0.65, 0.0, 0.0))
			skeleton.set_bone_pose_position(
				bones[HumanRigV1.Bone.PELVIS], Vector3(0.0, sin(phase * 2.0) * 0.025, 0.0)
			)
		AnimationStateType.AnimationState.ATTACK:
			var attack: float = sin(fmod(animation_time * 4.0 + animation_phase, 1.0) * PI)
			if archetype_id == SpearmanArchetype:
				_set_rotation(skeleton, bones, HumanRigV1.Bone.UPPER_ARM_L, Vector3(-0.65 - attack * 0.35, 0.0, 0.0))
				_set_rotation(skeleton, bones, HumanRigV1.Bone.UPPER_ARM_R, Vector3(-0.80 - attack * 0.45, 0.0, 0.0))
			else:
				_set_rotation(skeleton, bones, HumanRigV1.Bone.UPPER_ARM_R, Vector3(-0.75 - attack * 1.1, 0.0, 0.0))
				_set_rotation(skeleton, bones, HumanRigV1.Bone.LOWER_ARM_R, Vector3(-0.25 - attack * 0.35, 0.0, 0.0))
			_set_rotation(skeleton, bones, HumanRigV1.Bone.CHEST, Vector3(-attack * 0.08, 0.0, 0.0))
		AnimationStateType.AnimationState.DEAD:
			_set_rotation(skeleton, bones, HumanRigV1.Bone.CHEST, Vector3(0.0, 0.0, deg_to_rad(78.0)))

static func _set_rotation(
	skeleton: Skeleton3D,
	bones: PackedInt32Array,
	bone_index: int,
	euler: Vector3
) -> void:
	skeleton.set_bone_pose_rotation(bones[bone_index], Quaternion.from_euler(euler))
