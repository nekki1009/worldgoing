extends SceneTree

const RigType = preload("res://scripts/benchmark/3d_crowd/human_rig_v1.gd")
const DefinitionType = preload("res://scripts/benchmark/3d_special/special_visual_definition.gd")
const AppearanceType = preload("res://scripts/benchmark/3d_special/special_character_appearance.gd")
const AnimationStateType = preload("res://scripts/benchmark/3d_special/special_character_animation_state.gd")
const RegistryType = preload("res://scripts/benchmark/3d_special/special_character_visual_registry.gd")
const AnimationLibraryType = preload("res://scripts/benchmark/3d_special/special_human_animation_library.gd")
const ControllerType = preload("res://scripts/benchmark/3d_special/special_character_benchmark_controller.gd")
const VisualType = preload("res://scripts/benchmark/3d_special/special_character_visual_3d.gd")
const ScenePath: String = "res://scenes/benchmark/3d_special/SpecialCharacter3DTest.tscn"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_validate_rig_contract()
	var registry: SpecialCharacterVisualRegistry = RegistryType.new()
	_validate_registry(registry)
	var shared_library: AnimationLibrary = AnimationLibraryType.build_library()
	for clip_name: StringName in AnimationLibraryType.CLIP_NAMES:
		assert(shared_library.has_animation(clip_name), "Shared animation clip missing: %s" % clip_name)

	var scene: PackedScene = load(ScenePath) as PackedScene
	assert(scene != null, "SPECIAL test scene missing")
	var instance: Node = scene.instantiate()
	get_root().add_child(instance)
	await process_frame
	await process_frame
	var controller: SpecialCharacterBenchmarkController = instance as SpecialCharacterBenchmarkController
	assert(controller != null, "SPECIAL controller script missing")
	assert(controller.characters.size() == 4, "Expected four default SPECIAL characters")
	for character: SpecialCharacterVisual3D in controller.characters:
		assert(character.skeleton != null and RigType.validate(character.skeleton), "HumanRig_v1 runtime mismatch")
		assert(character.animation_player != null, "Shared AnimationPlayer missing")
		assert(character.animator != null, "SpecialCharacterAnimator missing")
		assert(character.get_skinned_mesh_count() >= 7, "Skinned body/armor modules missing")
		assert(character.get_character_node_count() > 15, "SPECIAL modular character node tree is incomplete")
		assert(character.get_socket_bone_name(&"weapon_socket_r") == &"weapon_socket_r", "Weapon socket contract missing")
		assert(character.get_socket_bone_name(&"shield_socket_l") == &"shield_socket_l", "Shield socket contract missing")
		assert(character.get_socket_bone_name(&"head_socket") == &"head_socket", "Head socket contract missing")
		assert(character.get_socket_bone_name(&"back_socket") == &"back_socket", "Back socket contract missing")

	var character: SpecialCharacterVisual3D = controller.characters[0]
	var combinations: Array[SpecialCharacterAppearance] = [
		_appearance(&"", &"", &"", &"", &""),
		_appearance(&"hair_short_01", &"", &"", &"", &""),
		_appearance(&"", &"cloth_01", &"", &"", &""),
		_appearance(&"", &"leather_01", &"", &"", &""),
		_appearance(&"", &"plate_01", &"", &"", &""),
		_appearance(&"hair_short_01", &"plate_01", &"helmet_01", &"", &""),
		_appearance(&"", &"plate_01", &"", &"sword_01", &""),
		_appearance(&"", &"plate_01", &"", &"sword_01", &"shield_01")
	]
	for combination_index: int in range(combinations.size()):
		assert(character.set_appearance(combinations[combination_index]), "Appearance combination rejected: %d" % combination_index)
		for state: int in range(AnimationStateType.State.BLOCK + 1):
			character.apply_animation_state(state, 0.35, 0.17)
			await process_frame
			assert(character.skeleton.get_bone_count() == RigType.BONE_NAMES.size(), "Skeleton changed after appearance/animation")
		assert(character.get_socket_bone_name(&"weapon_socket_r") == &"weapon_socket_r", "Weapon socket changed after animation")
		assert(character.get_socket_bone_name(&"shield_socket_l") == &"shield_socket_l", "Shield socket changed after animation")
		assert(character.get_socket_bone_name(&"head_socket") == &"head_socket", "Head socket changed after animation")

	assert(character.set_appearance(combinations[5]), "Plate appearance rejected")
	assert(not character.body_region_visible(DefinitionType.BodyRegion.TORSO), "Plate did not hide torso body region")
	assert(not character.body_region_visible(DefinitionType.BodyRegion.ARMS), "Plate did not hide arm body region")
	assert(not character.body_region_visible(DefinitionType.BodyRegion.LEGS), "Plate did not hide leg body region")
	assert(character.body_region_visible(DefinitionType.BodyRegion.HANDS), "Plate hid hand region unexpectedly")
	assert(character.armor_mesh_instance.visible, "Plate armor is not visible")
	assert(not character.hair_mesh_instance.visible, "Helmet compatibility did not hide hair")

	var idle_weapon: Transform3D
	var idle_shield: Transform3D
	character.set_appearance(combinations[7])
	assert(character.apply_view_state(
		4242, Transform3D(Basis.IDENTITY, Vector3(2.0, 0.0, -2.0)), combinations[7],
		AnimationStateType.State.IDLE, 0.2, 0.37
	), "Promotion view-state API rejected a valid SPECIAL appearance")
	assert(character.soldier_id == 4242, "Promotion soldier_id did not reach view representation")
	character.apply_animation_state(AnimationStateType.State.IDLE, 0.0, 0.0)
	await process_frame
	idle_weapon = character.get_socket_transform(&"weapon_socket_r")
	idle_shield = character.get_socket_transform(&"shield_socket_l")
	character.apply_animation_state(AnimationStateType.State.ATTACK_SWORD, 0.35, 0.0)
	await process_frame
	assert(character.get_socket_transform(&"weapon_socket_r") != idle_weapon, "Sword socket did not follow right-hand attack")
	character.apply_animation_state(AnimationStateType.State.BLOCK, 0.35, 0.0)
	await process_frame
	assert(character.get_socket_transform(&"shield_socket_l") != idle_shield, "Shield socket did not follow left-hand block")

	print(
		"SPECIAL_CHARACTER_CONTRACT_PASS: rig_bones=%d combinations=%d states=%d nodes=%d skinned_meshes=%d materials=%d" % [
			RigType.BONE_NAMES.size(), combinations.size(), AnimationStateType.State.BLOCK + 1,
			character.get_character_node_count(), character.get_skinned_mesh_count(), registry.material_count()
		]
	)
	instance.queue_free()
	await process_frame
	quit(0)

func _validate_rig_contract() -> void:
	assert(RigType.BONE_NAMES.size() == 22, "HumanRig_v1 bone count changed")
	var skeleton: Skeleton3D = RigType.build_skeleton()
	assert(RigType.validate(skeleton), "HumanRig_v1 names do not match")
	for bone_index: int in range(RigType.BONE_NAMES.size()):
		assert(skeleton.get_bone_parent(bone_index) == RigType.PARENT_INDICES[bone_index], "HumanRig parent mismatch")
	assert(skeleton.find_bone(&"weapon_socket_r") == RigType.Bone.WEAPON_SOCKET_R, "Weapon socket index mismatch")
	assert(skeleton.find_bone(&"shield_socket_l") == RigType.Bone.SHIELD_SOCKET_L, "Shield socket index mismatch")
	assert(skeleton.find_bone(&"head_socket") == RigType.Bone.HEAD_SOCKET, "Head socket index mismatch")
	assert(skeleton.find_bone(&"back_socket") == RigType.Bone.BACK_SOCKET, "Back socket index mismatch")
	skeleton.free()

func _validate_registry(registry: SpecialCharacterVisualRegistry) -> void:
	for slot_and_id: Array in [
		[DefinitionType.Slot.BODY, &"human_body_01"], [DefinitionType.Slot.HEAD, &"head_01"],
		[DefinitionType.Slot.HAIR, &"hair_short_01"], [DefinitionType.Slot.HAIR, &"hair_long_01"],
		[DefinitionType.Slot.ARMOR, &"cloth_01"], [DefinitionType.Slot.ARMOR, &"leather_01"],
		[DefinitionType.Slot.ARMOR, &"plate_01"], [DefinitionType.Slot.HELMET, &"helmet_01"],
		[DefinitionType.Slot.WEAPON, &"sword_01"], [DefinitionType.Slot.SHIELD, &"shield_01"]
	]:
		var definition: SpecialVisualDefinition = registry.resolve(slot_and_id[0], slot_and_id[1])
		assert(definition != null, "Registry entry missing: %s" % slot_and_id[1])
		assert(definition.is_compatible(), "Registry entry is not HumanRig_v1 compatible")
	var plate := registry.resolve(DefinitionType.Slot.ARMOR, &"plate_01")
	assert(plate.hide_body_regions.has(DefinitionType.BodyRegion.TORSO), "Plate coverage contract missing")
	assert(plate.hide_body_regions.has(DefinitionType.BodyRegion.ARMS), "Plate arm coverage contract missing")
	assert(plate.hide_body_regions.has(DefinitionType.BodyRegion.LEGS), "Plate leg coverage contract missing")
	assert(registry.material_count() >= 7, "Expected distinct prototype materials")

func _appearance(
	hair_id: StringName = &"",
	armor_id: StringName = &"",
	helmet_id: StringName = &"",
	weapon_id: StringName = &"",
	shield_id: StringName = &""
) -> SpecialCharacterAppearance:
	var appearance := AppearanceType.new()
	appearance.hair_id = hair_id
	appearance.armor_id = armor_id
	appearance.helmet_id = helmet_id
	appearance.weapon_id = weapon_id
	appearance.shield_id = shield_id
	return appearance
