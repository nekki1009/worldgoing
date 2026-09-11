extends "res://scripts/tests/capture_all_model_audit.gd"

func _run() -> void:
	sex = "female"
	audit_dir = "res://.visual_captures/all_model_repaired/layer_probe"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(audit_dir))
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await settle(4)
	editor._load_body_model(1,"res://assets/characters/human/q35/audit_repair/candidate_female.glb")
	await settle(4)
	editor.preview_viewport.size = Vector2i(1024,1280)
	for pair in [[&"outfit",&"outfit_underlayer_01"],[&"armor",&"armor_light_leather_01"],[&"helmet",&"none"],[&"cape",&"none"],[&"weapon",&"none"],[&"shield",&"none"]]:
		editor.select_part_by_id(pair[0],pair[1])
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.animation_player.seek(0.0,true)
	editor.camera.size = 0.90
	editor.camera.position = Vector3(0,1.18,-5)
	editor.camera.look_at(Vector3(0,1.18,0))
	await capture("with_body")
	for node in editor.model_root.find_children("*","MeshInstance3D",true,false):
		if str(node.name).begins_with("Body_") or str(node.name).begins_with("Outfit_"):node.visible = false
	await capture("without_body_or_underwear")
	for node in editor.model_root.find_children("*","MeshInstance3D",true,false):
		if not str(node.name).begins_with("Armor_Light_Leather_01"):continue
		var flat := StandardMaterial3D.new()
		flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flat.cull_mode = BaseMaterial3D.CULL_DISABLED
		flat.albedo_color = Color.CORNFLOWER_BLUE
		if str(node.name).ends_with("Collar"):flat.albedo_color = Color.CYAN
		if str(node.name).ends_with("CrossStrap"):flat.albedo_color = Color.RED
		if str(node.name).ends_with("FrontSeam"):flat.albedo_color = Color.GREEN
		node.material_override = flat
	await capture("flat_part_ids")
	editor.queue_free()
	await settle(3)
	quit(0)
