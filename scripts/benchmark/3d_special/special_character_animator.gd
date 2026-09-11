class_name SpecialCharacterAnimator
extends Node

const HumanRigType = preload("res://scripts/benchmark/3d_crowd/human_rig_v1.gd")
const AnimationStateType = preload("res://scripts/benchmark/3d_special/special_character_animation_state.gd")
const AnimationLibraryType = preload("res://scripts/benchmark/3d_special/special_human_animation_library.gd")

var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var bones: PackedInt32Array = PackedInt32Array()
var animation_state: int = AnimationStateType.State.IDLE
var animation_time: float = 0.0
var animation_phase: float = 0.0

func setup(
	target_skeleton: Skeleton3D,
	target_animation_player: AnimationPlayer,
	shared_library: AnimationLibrary
) -> void:
	skeleton = target_skeleton
	animation_player = target_animation_player
	bones = HumanRigType.bone_indices()
	if animation_player != null and shared_library != null:
		if not animation_player.has_animation_library(&""):
			animation_player.add_animation_library(&"", shared_library)
		# ponytail: bone poses are sampled explicitly below; avoid a second
		# per-frame AnimationPlayer process for the same shared animation state.
		animation_player.active = false

func apply_state(next_state: int, next_time: float, next_phase: float) -> void:
	animation_state = next_state
	animation_time = next_time
	animation_phase = next_phase
	if animation_player != null:
		var clip_name := AnimationLibraryType.clip_for(animation_state)
		if animation_player.current_animation != clip_name:
			animation_player.play(clip_name)
		# AnimationPlayer.play() may reactivate playback; the explicit sampler
		# below remains the sole per-frame animation owner.
		animation_player.active = false
	AnimationLibraryType.sample(skeleton, bones, animation_state, animation_time, animation_phase)
	if skeleton != null:
		skeleton.force_update_all_bone_transforms()
