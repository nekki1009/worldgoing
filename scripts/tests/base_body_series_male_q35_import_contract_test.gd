extends SceneTree

const AssetPath: String = "res://assets/characters/human/q35/base_body_series_male_q35.glb"
const ExpectedBones: Array[StringName] = [
	&"root", &"pelvis", &"spine", &"chest", &"neck", &"head",
	&"upper_arm_l", &"lower_arm_l", &"hand_l",
	&"upper_arm_r", &"lower_arm_r", &"hand_r",
	&"upper_leg_l", &"lower_leg_l", &"foot_l",
	&"upper_leg_r", &"lower_leg_r", &"foot_r",
	&"weapon_socket_r", &"shield_socket_l", &"head_socket", &"back_socket"
]
const ExpectedParentNames: Array[StringName] = [
	&"", &"root", &"pelvis", &"spine", &"chest", &"neck",
	&"chest", &"upper_arm_l", &"lower_arm_l",
	&"chest", &"upper_arm_r", &"lower_arm_r",
	&"pelvis", &"upper_leg_l", &"lower_leg_l",
	&"pelvis", &"upper_leg_r", &"lower_leg_r",
	&"hand_r", &"hand_l", &"head", &"chest"
]
const ExpectedSockets: Array[StringName] = [
	&"HEAD_SOCKET", &"HAND_R_SOCKET", &"HAND_L_SOCKET", &"CHEST_SOCKET",
	&"PELVIS_SOCKET", &"FOOT_SOCKET_L", &"FOOT_SOCKET_R"
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var absolute_path := ProjectSettings.globalize_path(AssetPath)
	if not FileAccess.file_exists(absolute_path):
		_fail("Missing Blender export: %s" % absolute_path)
		return
	var packed := ResourceLoader.load(AssetPath) as PackedScene
	if packed == null:
		_fail("GLB did not import as PackedScene: %s" % AssetPath)
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	await process_frame

	var skeleton := instance as Skeleton3D
	if skeleton == null:
		skeleton = instance.find_child("HumanRig_v1_Q35", true, false) as Skeleton3D
	if skeleton == null:
		var imported_skeletons := instance.find_children("*", "Skeleton3D", true, false)
		if imported_skeletons.size() == 1:
			skeleton = imported_skeletons[0] as Skeleton3D
	if skeleton == null:
		var skeleton_names: Array[String] = []
		for candidate: Node in instance.find_children("*", "Skeleton3D", true, false):
			skeleton_names.append(str(candidate.name))
		_fail("HumanRig_v1_Q35 Skeleton3D not found; imported Skeleton3D nodes=%s" % skeleton_names)
		return
	if skeleton.get_bone_count() != ExpectedBones.size():
		_fail("Bone count mismatch: got %d expected %d" % [skeleton.get_bone_count(), ExpectedBones.size()])
		return
	var bone_indices: Dictionary = {}
	for bone_index: int in range(skeleton.get_bone_count()):
		var imported_name := skeleton.get_bone_name(bone_index)
		if bone_indices.has(imported_name):
			_fail("Duplicate imported bone name: %s" % imported_name)
			return
		bone_indices[imported_name] = bone_index
	for expected_index: int in range(ExpectedBones.size()):
		var expected_name: StringName = ExpectedBones[expected_index]
		if not bone_indices.has(expected_name):
			_fail("Missing imported bone: %s" % expected_name)
			return
		var actual_index: int = bone_indices[expected_name]
		var actual_parent_index := skeleton.get_bone_parent(actual_index)
		var actual_parent_name: StringName = &""
		if actual_parent_index >= 0:
			actual_parent_name = skeleton.get_bone_name(actual_parent_index)
		if actual_parent_name != ExpectedParentNames[expected_index]:
			_fail("Parent mismatch for %s: got %s expected %s" % [expected_name, actual_parent_name, ExpectedParentNames[expected_index]])
			return
			return

	var body := instance.find_child("BaseBody_Male_Q35", true, false) as MeshInstance3D
	if body == null or body.mesh == null:
		_fail("BaseBody_Male_Q35 mesh missing")
		return
	if body.skin == null:
		_fail("BaseBody_Male_Q35 has no imported Skin resource")
		return
	if body.mesh.get_surface_count() < 1:
		_fail("BaseBody_Male_Q35 has no mesh surface")
		return

	var shorts := instance.find_child("BaseShorts_Male_Q35", true, false) as MeshInstance3D
	if shorts == null or shorts.mesh == null:
		_fail("BaseShorts_Male_Q35 mesh missing")
		return
	for socket_name: StringName in ExpectedSockets:
		if instance.find_child(socket_name, true, false) == null:
			_fail("Socket marker missing: %s" % socket_name)
			return

	print("BASE_BODY_SERIES_MALE_Q35_IMPORT_CONTRACT_PASS: bones=%d body_surfaces=%d skinned=true sockets=%d" % [
		skeleton.get_bone_count(), body.mesh.get_surface_count(), ExpectedSockets.size()
	])
	instance.queue_free()
	quit(0)

func _fail(message: String) -> void:
	push_error("BASE_BODY_SERIES_MALE_Q35_IMPORT_CONTRACT_FAIL: " + message)
	quit(2)
