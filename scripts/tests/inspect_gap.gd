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

	print("=== Cheek Guard and Hair in Gap Region (X: 0.06 to 0.11, Y: 0.06 to 0.14, Z: 0.0 to 0.08) ===")
	for child in inst.find_children("Helmet_Leather_01*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		var m := mesh_node.mesh
		for s in range(m.get_surface_count()):
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var h_pos := inv_head * (mesh_node.global_transform * v)
				if h_pos.x > 0.05 and h_pos.y > 0.06 and h_pos.y < 0.14 and h_pos.z > 0.0 and h_pos.z < 0.08:
					print("Helmet %-30s: X=%6.3f, Y=%6.3f, Z=%6.3f" % [mesh_node.name, h_pos.x, h_pos.y, h_pos.z])

	for child in inst.find_children("Hair_Short_01*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		var m := mesh_node.mesh
		for s in range(m.get_surface_count()):
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var h_pos := inv_head * (mesh_node.global_transform * v)
				if h_pos.x > 0.05 and h_pos.y > 0.06 and h_pos.y < 0.14 and h_pos.z > 0.0 and h_pos.z < 0.08:
					print("Hair   %-30s: X=%6.3f, Y=%6.3f, Z=%6.3f" % [mesh_node.name, h_pos.x, h_pos.y, h_pos.z])

	inst.queue_free()
	quit(0)
