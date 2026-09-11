extends SceneTree

const AssetPath: String = "res://assets/characters/human/q35/base_body_series_female_standard_anime.glb"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var absolute_path := ProjectSettings.globalize_path(AssetPath)
	if not FileAccess.file_exists(absolute_path):
		_fail("Missing standard anime female GLB: %s" % AssetPath)
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var parse_error := document.append_from_file(absolute_path, state)
	if parse_error != OK:
		_fail("GLTFDocument could not parse standard anime female GLB error=%d" % parse_error)
		return
	var instance: Node = document.generate_scene(state)
	if instance == null:
		_fail("GLTFDocument generated no female scene")
		return
	root.add_child(instance)
	await process_frame
	await process_frame
	var skeletons := instance.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() != 1:
		_fail("Skeleton3D count=%d expected=1" % skeletons.size())
		return
	var skeleton := skeletons[0] as Skeleton3D
	var mesh_count := instance.find_children("*", "MeshInstance3D", true, false).size()
	if mesh_count < 2:
		_fail("MeshInstance3D count=%d expected_at_least=2" % mesh_count)
		return
	if skeleton.get_bone_count() < 20:
		_fail("bone_count=%d expected_at_least=20" % skeleton.get_bone_count())
		return
	print("BASE_BODY_SERIES_FEMALE_STANDARD_ANIME_IMPORT_PASS: bones=%d meshes=%d" % [skeleton.get_bone_count(), mesh_count])
	instance.queue_free()
	quit(0)

func _fail(message: String) -> void:
	push_error("BASE_BODY_SERIES_FEMALE_STANDARD_ANIME_IMPORT_FAIL: " + message)
	quit(2)
