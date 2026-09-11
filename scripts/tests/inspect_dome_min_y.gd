extends SceneTree

const MALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_male_character_pack.glb"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load(MALE_MODEL_PATH) as PackedScene
	var inst := scene.instantiate() as Node3D
	root.add_child(inst)
	
	var skeleton := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var head_bone_idx := skeleton.find_bone("J_Bip_C_Head")
	var head_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head_bone_idx)
	var inv_head := head_world.affine_inverse()

	for child in inst.find_children("Helmet_Leather_01_Dome", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		var m := mesh_node.mesh
		var min_y := 999.0
		var max_y := -999.0
		for s in range(m.get_surface_count()):
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var h_pos := inv_head * (mesh_node.global_transform * v)
				min_y = minf(min_y, h_pos.y)
				max_y = maxf(max_y, h_pos.y)
		print("Helmet_Leather_01_Dome min_Y = ", min_y, ", max_Y = ", max_y)

	inst.queue_free()
	quit(0)
