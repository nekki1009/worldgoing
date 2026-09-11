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
	
	for hname in ["Hair_Short_01", "Hair_Short_02", "Hair_Short_03", "Hair_Short_04"]:
		var node := inst.find_child(hname, true, false) as MeshInstance3D
		print("\n=== ", hname, " ===")
		var m := node.mesh
		var arrays := m.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var y_ranges := [[0.10, 0.30], [0.00, 0.10], [-0.10, 0.00], [-0.30, -0.10]]
		for r in y_ranges:
			var min_z := 999.0
			var max_z := -999.0
			var min_x := 999.0
			var max_x := -999.0
			var count := 0
			for v in verts:
				var h_pos := inv_head * (node.global_transform * v)
				if h_pos.y >= r[0] and h_pos.y < r[1]:
					min_z = minf(min_z, h_pos.z)
					max_z = maxf(max_z, h_pos.z)
					min_x = minf(min_x, h_pos.x)
					max_x = maxf(max_x, h_pos.x)
					count += 1
			print("  Y in [", r[0], ", ", r[1], "]: count=", count, " X in [", min_x, ", ", max_x, "] Z in [", min_z, ", ", max_z, "]")
	quit(0)
