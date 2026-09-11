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
		# Check vertex distribution along Y bands:
		var y_bins := {}
		for y_step in range(-30, 30, 2):
			y_bins[y_step] = 0
		var arrays := m.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in verts:
			var h_pos := inv_head * (node.global_transform * v)
			var y_idx := int(floor(h_pos.y * 100.0 / 2.0)) * 2
			if y_bins.has(y_idx):
				y_bins[y_idx] += 1
		for k in y_bins.keys():
			if y_bins[k] > 0:
				print("  Y [", float(k)/100.0, ", ", float(k+2)/100.0, "]: ", y_bins[k], " verts")
	quit(0)
