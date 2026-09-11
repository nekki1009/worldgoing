extends SceneTree

const EDITOR_SCENE: String = "res://scenes/ui/HumanCharacter3DEditor.tscn"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load(EDITOR_SCENE) as PackedScene
	var editor := scene.instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await _settle(10)

	editor._load_body_model(0)
	editor.select_part_by_id(&"helmet", &"helmet_leather_01")
	editor.select_part_by_id(&"hair", &"hair_short_01")
	editor.set_preview_yaw_degrees(85.0) # Side view

	var head_y := 1.58
	editor.camera.size = 0.96
	editor.camera.position = Vector3(0.0, head_y, -2.40)
	editor.camera.look_at_from_position(editor.camera.position, Vector3(0.0, head_y - 0.02, 0.0), Vector3.UP)

	var skeleton := editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var head_bone_idx := skeleton.find_bone("J_Bip_C_Head")
	var head_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head_bone_idx)
	var inv_head := head_world.affine_inverse()

	for node in editor.model_root.find_children("Hair_Short_01*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var m := mesh_node.mesh
		for s in range(m.get_surface_count()):
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var world_v := mesh_node.global_transform * v
				var screen_pos := editor.camera.unproject_position(world_v)
				# Check if screen_pos is near X=852, Y=467 on 1600x900
				# Preview viewport is centered in the editor window
				var h_pos := inv_head * world_v
				if abs(screen_pos.x - 852) < 40 and abs(screen_pos.y - 467) < 40:
					print("Hair vert near (852, 467): screen=(%.1f, %.1f), head_local=(%.3f, %.3f, %.3f)" % [
						screen_pos.x, screen_pos.y, h_pos.x, h_pos.y, h_pos.z
					])

	editor.queue_free()
	quit(0)

func _settle(frames: int) -> void:
	for i in range(frames):
		await process_frame
