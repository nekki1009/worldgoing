extends SceneTree

const AssetPath: String = "res://assets/characters/human/q35/base_body_series_male_q35_box_model.glb"
const RequiredBones: Array[StringName] = [
	&"root", &"pelvis", &"spine", &"chest", &"neck", &"head",
	&"upper_arm_l", &"lower_arm_l", &"hand_l",
	&"upper_arm_r", &"lower_arm_r", &"hand_r",
	&"upper_leg_l", &"lower_leg_l", &"foot_l",
	&"upper_leg_r", &"lower_leg_r", &"foot_r",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if not FileAccess.file_exists(ProjectSettings.globalize_path(AssetPath)):
		_fail("Missing box-model GLB: %s" % AssetPath)
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var parse_error := document.append_from_file(ProjectSettings.globalize_path(AssetPath), state)
	if parse_error != OK:
		_fail("GLTFDocument could not parse box-model GLB error=%d" % parse_error)
		return
	var instance: Node = document.generate_scene(state)
	if instance == null:
		_fail("GLTFDocument generated no scene")
		return
	root.add_child(instance)
	await process_frame
	await process_frame
	var skeletons := instance.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() != 1:
		_fail("Skeleton3D count=%d expected=1" % skeletons.size())
		return
	var skeleton := skeletons[0] as Skeleton3D
	if skeleton.get_bone_count() != 22:
		_fail("bone_count=%d expected=22" % skeleton.get_bone_count())
		return
	for bone_name: StringName in RequiredBones:
		if skeleton.find_bone(bone_name) < 0:
			_fail("required bone missing: %s" % bone_name)
			return
	var mesh_count := instance.find_children("*", "MeshInstance3D", true, false).size()
	if mesh_count < 1:
		_fail("MeshInstance3D count=%d expected_at_least=1" % mesh_count)
		return
	print("BASE_BODY_SERIES_MALE_Q35_BOX_MODEL_IMPORT_PASS: bones=%d meshes=%d" % [skeleton.get_bone_count(), mesh_count])
	instance.queue_free()
	quit(0)

func _fail(message: String) -> void:
	push_error("BASE_BODY_SERIES_MALE_Q35_BOX_MODEL_IMPORT_FAIL: " + message)
	quit(2)
