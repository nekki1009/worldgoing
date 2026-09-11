extends SceneTree

const FEMALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_female_character_pack.glb"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load(FEMALE_MODEL_PATH) as PackedScene
	var inst := scene.instantiate() as Node3D
	root.add_child(inst)
	var skeleton := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var head_bone_idx := skeleton.find_bone("J_Bip_C_Head")
	var head_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head_bone_idx)
	var inv_head := head_world.affine_inverse()
	
	for hname in ["Hair_Long_01", "Hair_Long_02", "Hair_Long_04"]:
		var node := inst.find_child(hname, true, false) as MeshInstance3D
		if node == null:
			continue
		print("\n=== ", hname, " ===")
		var m := node.mesh
		var arrays := m.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var max_x := 0.0
		var min_z := 0.0
		var max_z := 0.0
		for v in verts:
			var h_pos := inv_head * (node.global_transform * v)
			if h_pos.y < 0.0:
				max_x = maxf(max_x, absf(h_pos.x))
				min_z = minf(min_z, h_pos.z)
				max_z = maxf(max_z, h_pos.z)
		print("Below Y=0: max |X| = ", max_x, ", Z in [", min_z, ", ", max_z, "]")
	quit(0)
