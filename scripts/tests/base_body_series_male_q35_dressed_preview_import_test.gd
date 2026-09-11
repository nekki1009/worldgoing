extends SceneTree

const AssetPath: String = "res://assets/characters/human/q35/base_body_series_male_q35_dressed_preview.glb"
const ExpectedVisualLayers: Array[StringName] = [
	&"HairCap_Male_Q35",
	&"EyeWhite_L_Male_Q35",
	&"JacketBody_Male_Q35",
	&"CapeOuter_Male_Q35",
	&"TrousersL_Male_Q35",
	&"BootL_Male_Q35",
	&"ShoeL_Male_Q35",
	&"HighCollar_Male_Q35",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var absolute_path := ProjectSettings.globalize_path(AssetPath)
	if not FileAccess.file_exists(absolute_path):
		_fail("Missing dressed preview GLB: %s" % AssetPath)
		return
	var packed := ResourceLoader.load(AssetPath) as PackedScene
	if packed == null:
		_fail("Dressed preview GLB did not import as PackedScene: %s" % AssetPath)
		return
	var instance: Node = packed.instantiate()
	root.add_child(instance)
	await process_frame
	var skeletons := instance.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() != 1:
		_fail("Dressed preview imported Skeleton3D count=%d expected=1" % skeletons.size())
		return
	var mesh_count := instance.find_children("*", "MeshInstance3D", true, false).size()
	if mesh_count < 20:
		_fail("Dressed preview MeshInstance3D count=%d expected_at_least=20" % mesh_count)
		return
	for expected_name: StringName in ExpectedVisualLayers:
		var visual := instance.find_child(expected_name, true, false)
		if visual == null or not (visual is MeshInstance3D) or (visual as MeshInstance3D).mesh == null:
			_fail("Dressed visual layer missing or has no mesh: %s" % expected_name)
			return

	print("BASE_BODY_SERIES_MALE_Q35_DRESSED_PREVIEW_IMPORT_PASS: meshes=%d visual_layers=%d" % [mesh_count, ExpectedVisualLayers.size()])
	instance.queue_free()
	quit(0)

func _fail(message: String) -> void:
	push_error("BASE_BODY_SERIES_MALE_Q35_DRESSED_PREVIEW_IMPORT_FAIL: " + message)
	quit(2)
