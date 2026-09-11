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
		print("=== Helmet_Leather_01_Dome Profile ===")
		var min_y := 999.0
		var max_y := -999.0
		var y_bins: Dictionary = {}
		for s in range(m.get_surface_count()):
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var h_pos := inv_head * (mesh_node.global_transform * v)
				min_y = minf(min_y, h_pos.y)
				max_y = maxf(max_y, h_pos.y)
				var y_step := snappedf(h_pos.y, 0.02)
				if not y_bins.has(y_step):
					y_bins[y_step] = {"max_r": 0.0, "min_r": 999.0, "count": 0}
				var r := Vector2(h_pos.x, h_pos.z).length()
				y_bins[y_step]["max_r"] = maxf(y_bins[y_step]["max_r"], r)
				y_bins[y_step]["min_r"] = minf(y_bins[y_step]["min_r"], r)
				y_bins[y_step]["count"] += 1
		
		var sorted_keys := y_bins.keys()
		sorted_keys.sort()
		for k in sorted_keys:
			print("  Y ~ %5.2f: count=%3d, R=[%5.3f, %5.3f]" % [k, y_bins[k]["count"], y_bins[k]["min_r"], y_bins[k]["max_r"]])

	inst.queue_free()
	quit(0)
