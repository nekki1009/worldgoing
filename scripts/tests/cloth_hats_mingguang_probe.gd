extends "res://scripts/tests/capture_chinese_leather_mingguang.gd"
const OUT := "res://output/cloth_hats_20260918/mingguang_probe"
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var rows := {}
	for source in ["old_a","old_b","new_a","new_b"]:
		editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
		root.add_child(editor)
		editor.open()
		await settle(3)
		editor._load_body_model(0,"res://output/cloth_hats_20260918/baseline/standard_anime_male_character_pack.glb" if source.begins_with("old") else "")
		await settle(4)
		editor.preview_viewport.size = Vector2i(256,320)
		editor.preview_viewport.msaa_3d = Viewport.MSAA_DISABLED
		editor.preview_viewport.use_debanding = false
		assert(editor.restore_appearance(HumanCharacter3DEditor.default_appearance(0)))
		for choice in ["none","helmet_leather_01","helmet_iron_01","helmet_steel_01","helmet_mingguang_01"]:
			assert(editor.select_part_by_id(&"helmet",StringName(choice)))
			for angle in [0.0,90.0,180.0]:
				neutral()
				editor.set_preview_yaw_degrees(angle)
				frame_camera("head")
				await settle(3)
				await RenderingServer.frame_post_draw
				if choice == "helmet_mingguang_01":
					assert(editor.preview_viewport.get_texture().get_image().save_png(OUT+"/%s_%d.png" % [source,int(angle)]) == OK)
		var nodes := {}
		for node in editor.model_root.find_children("Helmet_Mingguang_*","MeshInstance3D",true,false):
			var info := {"visible":node.visible,"transform":str(node.global_transform),"blend":[],"materials":[]}
			for i in node.get_blend_shape_count(): info.blend.append(node.get_blend_shape_value(i))
			for i in node.mesh.get_surface_count():
				var mat: Material = node.get_active_material(i)
				info.materials.append({"name":mat.resource_name,"priority":mat.render_priority,"class":mat.get_class()})
			nodes[str(node.name)] = info
		rows[source] = nodes
		editor.queue_free()
		await settle(3)
	var file := FileAccess.open(OUT+"/result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"  "))
	file.close()
	print("CLOTH_HATS_MINGGUANG_PROBE_READY")
	quit(0)
