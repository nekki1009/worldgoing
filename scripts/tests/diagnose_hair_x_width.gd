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
	
	# Compare Hair_Long_03 (pure skull hair) vs Hair_Long_01 (twintails)
	for hname in ["Hair_Long_03", "Hair_Long_01"]:
		var node := inst.find_child(hname, true, false) as MeshInstance3D
		if node == null:
			continue
		print("\n=== ", hname, " ===")
		var m := node.mesh
		var max_x_at_y := {}
		for y_step in range(-12, 14, 2):
			max_x_at_y[y_step] = 0.0
		var arrays := m.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in verts:
			var h_pos := inv_head * (node.global_transform * v)
			var y_idx := int(floor(h_pos.y * 100.0 / 2.0)) * 2
			if max_x_at_y.has(y_idx):
				max_x_at_y[y_idx] = maxf(max_x_at_y[y_idx], absf(h_pos.x))
		for k in max_x_at_y.keys():
			print("  Y [", float(k)/100.0, ", ", float(k+2)/100.0, "]: max |X| = ", max_x_at_y[k])
	quit(0)
