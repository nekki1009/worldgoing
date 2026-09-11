extends SceneTree

const EDITOR_SCENE: String = "res://scenes/ui/HumanCharacter3DEditor.tscn"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load(EDITOR_SCENE) as PackedScene
	var editor := scene.instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	
	editor._load_body_model(1)
	editor.select_part_by_id(&"hair", &"hair_short_01")
	editor.select_part_by_id(&"helmet", &"helmet_leather_01")
	
	for node in editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var mn := node as MeshInstance3D
		print("Node: ", mn.name, " visible=", mn.visible, " override_mat=", mn.get_surface_override_material(0))
	editor.queue_free()
	quit(0)
