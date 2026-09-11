class_name SpecialHumanAnimationLibrary
extends RefCounted

const HumanRigType = preload("res://scripts/benchmark/3d_crowd/human_rig_v1.gd")
const AnimationStateType = preload("res://scripts/benchmark/3d_special/special_character_animation_state.gd")

const CLIP_NAMES: Array[StringName] = [
	&"idle", &"walk", &"run", &"attack_sword_1h", &"block"
]

static func build_library() -> AnimationLibrary:
	var library := AnimationLibrary.new()
	for clip_name: StringName in CLIP_NAMES:
		var animation := Animation.new()
		animation.length = 1.0
		animation.loop_mode = Animation.LOOP_LINEAR
		library.add_animation(clip_name, animation)
	return library

static func clip_for(animation_state: int) -> StringName:
	match animation_state:
		AnimationStateType.State.WALK:
			return &"walk"
		AnimationStateType.State.RUN:
			return &"run"
		AnimationStateType.State.ATTACK_SWORD:
			return &"attack_sword_1h"
		AnimationStateType.State.BLOCK:
			return &"block"
		_:
			return &"idle"

static func sample(
	skeleton: Skeleton3D,
	bones: PackedInt32Array,
	animation_state: int,
	animation_time: float,
	animation_phase: float
) -> void:
	if skeleton == null or bones.size() < HumanRigType.BONE_NAMES.size():
		return
	for bone_index: int in range(HumanRigType.Bone.PELVIS, HumanRigType.Bone.FOOT_R + 1):
		skeleton.set_bone_pose_rotation(bones[bone_index], Quaternion.IDENTITY)
	skeleton.set_bone_pose_position(
		bones[HumanRigType.Bone.PELVIS], HumanRigType.REST_POSITIONS[HumanRigType.Bone.PELVIS]
	)

	var phase: float = animation_time * 7.5 + animation_phase * TAU
	match animation_state:
		AnimationStateType.State.WALK:
			_apply_walk(skeleton, bones, phase, 0.58, 0.65)
		AnimationStateType.State.RUN:
			_apply_walk(skeleton, bones, phase * 1.25, 0.92, 0.86)
		AnimationStateType.State.ATTACK_SWORD:
			_apply_attack(skeleton, bones, animation_time, animation_phase)
		AnimationStateType.State.BLOCK:
			_apply_block(skeleton, bones, animation_time)
		_:
			skeleton.set_bone_pose_position(
				bones[HumanRigType.Bone.PELVIS],
				HumanRigType.REST_POSITIONS[HumanRigType.Bone.PELVIS] + Vector3(0.0, sin(phase * 0.5) * 0.008, 0.0)
			)

static func _apply_walk(
	skeleton: Skeleton3D,
	bones: PackedInt32Array,
	phase: float,
	leg_swing: float,
	arm_scale: float
) -> void:
	var swing: float = sin(phase) * leg_swing
	_set_rotation(skeleton, bones, HumanRigType.Bone.UPPER_LEG_L, Vector3(swing, 0.0, 0.0))
	_set_rotation(skeleton, bones, HumanRigType.Bone.UPPER_LEG_R, Vector3(-swing, 0.0, 0.0))
	_set_rotation(skeleton, bones, HumanRigType.Bone.LOWER_LEG_L, Vector3(maxf(0.0, -swing) * 0.35, 0.0, 0.0))
	_set_rotation(skeleton, bones, HumanRigType.Bone.LOWER_LEG_R, Vector3(maxf(0.0, swing) * 0.35, 0.0, 0.0))
	_set_rotation(skeleton, bones, HumanRigType.Bone.UPPER_ARM_L, Vector3(-swing * arm_scale, 0.0, 0.0))
	_set_rotation(skeleton, bones, HumanRigType.Bone.UPPER_ARM_R, Vector3(swing * arm_scale, 0.0, 0.0))
	skeleton.set_bone_pose_position(
		bones[HumanRigType.Bone.PELVIS],
		HumanRigType.REST_POSITIONS[HumanRigType.Bone.PELVIS] + Vector3(0.0, sin(phase * 2.0) * 0.025, 0.0)
	)

static func _apply_attack(
	skeleton: Skeleton3D,
	bones: PackedInt32Array,
	animation_time: float,
	animation_phase: float
) -> void:
	var attack_phase: float = fmod(animation_time * 3.2 + animation_phase, 1.0)
	var attack: float = sin(attack_phase * PI)
	_set_rotation(skeleton, bones, HumanRigType.Bone.UPPER_ARM_R, Vector3(-0.72 - attack * 1.18, 0.0, 0.0))
	_set_rotation(skeleton, bones, HumanRigType.Bone.LOWER_ARM_R, Vector3(-0.20 - attack * 0.42, 0.0, 0.0))
	_set_rotation(skeleton, bones, HumanRigType.Bone.UPPER_ARM_L, Vector3(-0.24 - attack * 0.18, 0.0, 0.0))
	_set_rotation(skeleton, bones, HumanRigType.Bone.CHEST, Vector3(-attack * 0.12, 0.0, 0.0))
	_set_rotation(skeleton, bones, HumanRigType.Bone.PELVIS, Vector3(0.0, 0.0, -attack * 0.08))

static func _apply_block(
	skeleton: Skeleton3D,
	bones: PackedInt32Array,
	animation_time: float
) -> void:
	var settle: float = 0.5 + sin(animation_time * TAU) * 0.04
	_set_rotation(skeleton, bones, HumanRigType.Bone.UPPER_ARM_L, Vector3(-1.05 * settle, 0.0, -0.20))
	_set_rotation(skeleton, bones, HumanRigType.Bone.LOWER_ARM_L, Vector3(-0.78 * settle, 0.0, 0.0))
	_set_rotation(skeleton, bones, HumanRigType.Bone.UPPER_ARM_R, Vector3(-0.42 * settle, 0.0, 0.12))
	_set_rotation(skeleton, bones, HumanRigType.Bone.LOWER_ARM_R, Vector3(-0.55 * settle, 0.0, 0.0))
	_set_rotation(skeleton, bones, HumanRigType.Bone.CHEST, Vector3(-0.10, 0.0, 0.0))

static func _set_rotation(
	skeleton: Skeleton3D,
	bones: PackedInt32Array,
	bone_index: int,
	euler: Vector3
) -> void:
	skeleton.set_bone_pose_rotation(bones[bone_index], Quaternion.from_euler(euler))
