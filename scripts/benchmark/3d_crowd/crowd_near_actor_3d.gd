class_name CrowdNearActor3D
extends Node3D

const AnimationLibraryType = preload("res://scripts/benchmark/3d_crowd/human_animation_library.gd")

var current_soldier_id: int = -1
var current_archetype_id: int = -1
var current_animation_state: int = -1
var skeleton: Skeleton3D
var animation_player: AnimationPlayer

var _bones: PackedInt32Array
var _box_mesh: Mesh
var _body_material: Material
var _equipment_material: Material
var _pelvis_mesh: MeshInstance3D
var _chest_mesh: MeshInstance3D
var _head_mesh: MeshInstance3D
var _helmet_mesh: MeshInstance3D
var _upper_arm_l_mesh: MeshInstance3D
var _lower_arm_l_mesh: MeshInstance3D
var _hand_l_mesh: MeshInstance3D
var _upper_arm_r_mesh: MeshInstance3D
var _lower_arm_r_mesh: MeshInstance3D
var _hand_r_mesh: MeshInstance3D
var _upper_leg_l_mesh: MeshInstance3D
var _lower_leg_l_mesh: MeshInstance3D
var _foot_l_mesh: MeshInstance3D
var _upper_leg_r_mesh: MeshInstance3D
var _lower_leg_r_mesh: MeshInstance3D
var _foot_r_mesh: MeshInstance3D
var _sword_mesh: MeshInstance3D
var _spear_mesh: MeshInstance3D
var _shield_mesh: MeshInstance3D
var _back_mesh: MeshInstance3D

func setup(box_mesh: Mesh, shared_animation_library: AnimationLibrary) -> void:
	_box_mesh = box_mesh
	skeleton = HumanRigV1.build_skeleton()
	add_child(skeleton)
	_bones = HumanRigV1.bone_indices()
	animation_player = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	animation_player.add_animation_library("", shared_animation_library)
	add_child(animation_player)
	_create_body_parts()
	visible = false

func activate(
	soldier_id: int,
	simulation: BattleCrowdSimulation,
	spec: SoldierVisualArchetype,
	body_material: Material,
	equipment_material: Material
) -> void:
	if current_soldier_id != soldier_id or current_archetype_id != spec.id:
		current_soldier_id = soldier_id
		current_archetype_id = spec.id
		configure_archetype(spec, body_material, equipment_material)
	visible = true
	sync_from_simulation(simulation)

func sync_from_simulation(simulation: BattleCrowdSimulation) -> void:
	if current_soldier_id < 0:
		return
	var soldier_index: int = current_soldier_id
	position = simulation.get_soldier_world_position(soldier_index)
	rotation.y = simulation.get_soldier_facing(soldier_index)
	var next_state: int = simulation.soldier_animation_state[soldier_index]
	if next_state != current_animation_state:
		current_animation_state = next_state
		animation_player.play(
			AnimationLibraryType.clip_for(next_state, current_archetype_id)
		)
	AnimationLibraryType.sample(
		skeleton,
		_bones,
		next_state,
		simulation.soldier_animation_time[soldier_index],
		simulation.soldier_animation_phase[soldier_index],
		current_archetype_id
	)

func deactivate() -> void:
	current_soldier_id = -1
	current_archetype_id = -1
	current_animation_state = -1
	animation_player.stop()
	visible = false

func configure_archetype(
	spec: SoldierVisualArchetype,
	body_material: Material,
	equipment_material: Material
) -> void:
	_body_material = body_material
	_equipment_material = equipment_material
	for body_part: MeshInstance3D in [
		_pelvis_mesh, _chest_mesh, _head_mesh,
		_upper_arm_l_mesh, _lower_arm_l_mesh, _hand_l_mesh,
		_upper_arm_r_mesh, _lower_arm_r_mesh, _hand_r_mesh,
		_upper_leg_l_mesh, _lower_leg_l_mesh, _foot_l_mesh,
		_upper_leg_r_mesh, _lower_leg_r_mesh, _foot_r_mesh
	]:
		body_part.material_override = _body_material
	for equipment_part: MeshInstance3D in [_helmet_mesh, _sword_mesh, _spear_mesh, _shield_mesh, _back_mesh]:
		equipment_part.material_override = _equipment_material

	_pelvis_mesh.scale = Vector3(0.50, 0.28, 0.30)
	_chest_mesh.scale = Vector3(spec.body_width, spec.body_height, spec.body_depth)
	_head_mesh.scale = Vector3.ONE * spec.head_size
	_helmet_mesh.scale = Vector3.ONE * spec.head_size * 1.18
	_helmet_mesh.visible = spec.id != 0
	_upper_arm_l_mesh.scale = Vector3(0.15, 0.34, 0.15)
	_lower_arm_l_mesh.scale = Vector3(0.14, 0.30, 0.14)
	_hand_l_mesh.scale = Vector3(0.13, 0.13, 0.13)
	_upper_arm_r_mesh.scale = Vector3(0.15, 0.34, 0.15)
	_lower_arm_r_mesh.scale = Vector3(0.14, 0.30, 0.14)
	_hand_r_mesh.scale = Vector3(0.13, 0.13, 0.13)
	_upper_leg_l_mesh.scale = Vector3(0.17, 0.38, 0.17)
	_lower_leg_l_mesh.scale = Vector3(0.16, 0.38, 0.16)
	_foot_l_mesh.scale = Vector3(0.18, 0.12, 0.28)
	_upper_leg_r_mesh.scale = Vector3(0.17, 0.38, 0.17)
	_lower_leg_r_mesh.scale = Vector3(0.16, 0.38, 0.16)
	_foot_r_mesh.scale = Vector3(0.18, 0.12, 0.28)

	_sword_mesh.scale = Vector3(0.07, spec.weapon_length * 0.5, 0.07)
	_spear_mesh.scale = Vector3(0.045, spec.weapon_length * 0.5, 0.045)
	_sword_mesh.visible = spec.weapon_kind == &"sword"
	_spear_mesh.visible = spec.weapon_kind == &"spear"
	_shield_mesh.scale = Vector3(spec.shield_width, spec.shield_height, 0.09)
	_shield_mesh.visible = spec.has_shield
	_back_mesh.visible = spec.id == 1

func _create_body_parts() -> void:
	_pelvis_mesh = _add_part(HumanRigV1.Bone.PELVIS, "Pelvis")
	_chest_mesh = _add_part(HumanRigV1.Bone.CHEST, "Chest", Vector3(0.0, -0.18, 0.0))
	_head_mesh = _add_part(HumanRigV1.Bone.HEAD, "Head")
	_helmet_mesh = _add_part(HumanRigV1.Bone.HEAD_SOCKET, "Helmet", Vector3(0.0, 0.0, 0.0))
	_upper_arm_l_mesh = _add_part(HumanRigV1.Bone.UPPER_ARM_L, "UpperArmL", Vector3(0.0, -0.16, 0.0))
	_lower_arm_l_mesh = _add_part(HumanRigV1.Bone.LOWER_ARM_L, "LowerArmL", Vector3(0.0, -0.15, 0.0))
	_hand_l_mesh = _add_part(HumanRigV1.Bone.HAND_L, "HandL")
	_upper_arm_r_mesh = _add_part(HumanRigV1.Bone.UPPER_ARM_R, "UpperArmR", Vector3(0.0, -0.16, 0.0))
	_lower_arm_r_mesh = _add_part(HumanRigV1.Bone.LOWER_ARM_R, "LowerArmR", Vector3(0.0, -0.15, 0.0))
	_hand_r_mesh = _add_part(HumanRigV1.Bone.HAND_R, "HandR")
	_upper_leg_l_mesh = _add_part(HumanRigV1.Bone.UPPER_LEG_L, "UpperLegL", Vector3(0.0, -0.18, 0.0))
	_lower_leg_l_mesh = _add_part(HumanRigV1.Bone.LOWER_LEG_L, "LowerLegL", Vector3(0.0, -0.18, 0.0))
	_foot_l_mesh = _add_part(HumanRigV1.Bone.FOOT_L, "FootL", Vector3(0.0, -0.02, 0.08))
	_upper_leg_r_mesh = _add_part(HumanRigV1.Bone.UPPER_LEG_R, "UpperLegR", Vector3(0.0, -0.18, 0.0))
	_lower_leg_r_mesh = _add_part(HumanRigV1.Bone.LOWER_LEG_R, "LowerLegR", Vector3(0.0, -0.18, 0.0))
	_foot_r_mesh = _add_part(HumanRigV1.Bone.FOOT_R, "FootR", Vector3(0.0, -0.02, 0.08))
	_sword_mesh = _add_part(HumanRigV1.Bone.WEAPON_SOCKET_R, "Sword", Vector3(0.0, -0.28, 0.0))
	_spear_mesh = _add_part(HumanRigV1.Bone.WEAPON_SOCKET_R, "Spear", Vector3(0.0, -0.72, 0.0))
	_shield_mesh = _add_part(HumanRigV1.Bone.SHIELD_SOCKET_L, "Shield", Vector3(0.0, -0.24, -0.08))
	_back_mesh = _add_part(HumanRigV1.Bone.BACK_SOCKET, "Back", Vector3(0.0, -0.04, 0.0))

func _add_part(bone_index: int, part_name: String, local_position: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var attachment := BoneAttachment3D.new()
	attachment.name = "%sAttachment" % part_name
	attachment.bone_name = HumanRigV1.BONE_NAMES[bone_index]
	skeleton.add_child(attachment)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	mesh_instance.mesh = _box_mesh
	mesh_instance.position = local_position
	attachment.add_child(mesh_instance)
	return mesh_instance
