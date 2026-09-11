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

	var mask_center_offset := Vector3(0.0, 0.088, -0.005)
	var mask_radii := Vector3(0.126, 0.138, 0.142)
	var brow_cut_y := 0.105
	var dome_cut_y := 0.136
	var front_bangs_mode := 1

	var discarded_count := 0
	var total_count := 0
	var rule_counts := {"NOSE": 0, "DOME": 0, "SPIKE": 0, "TWINTAIL": 0, "PONYTAIL": 0}

	for child in inst.find_children("Hair_Short_01*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		var m := mesh_node.mesh
		for s in range(m.get_surface_count()):
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				total_count += 1
				var h_pos := inv_head * (mesh_node.global_transform * v)
				
				# Check V5 rules
				var disc := false
				if front_bangs_mode == 1 and h_pos.z > 0.080 and h_pos.y < 0.055 and abs(h_pos.x) < 0.030:
					rule_counts["NOSE"] += 1
					disc = true
				
				var is_front_bangs: bool = (h_pos.z > 0.015 and h_pos.y <= (brow_cut_y + 0.008) and abs(h_pos.x) <= 0.096)
				
				if not disc and not is_front_bangs:
					if h_pos.y > dome_cut_y:
						var d := (h_pos - mask_center_offset) / mask_radii
						if d.dot(d) <= 1.06:
							rule_counts["DOME"] += 1
							disc = true
						elif h_pos.y > (mask_center_offset.y + mask_radii.y * 0.28):
							rule_counts["SPIKE"] += 1
							disc = true
					
					var twintail_x := 0.106 if (mask_radii.x < 0.123) else 0.128
					if not disc and abs(h_pos.x) > twintail_x and h_pos.z < 0.035:
						rule_counts["TWINTAIL"] += 1
						disc = true
					
					if not disc and (h_pos.z < -0.128 or (h_pos.y < -0.05 and h_pos.z < -0.105 and abs(h_pos.x) < 0.060)):
						rule_counts["PONYTAIL"] += 1
						disc = true
				
				if disc:
					discarded_count += 1
					# If this discarded vert has Y < 0.14 and |X| > 0.05, print it!
					if h_pos.y < 0.14 and abs(h_pos.x) > 0.05:
						print("Discarded low vert: X=%.3f, Y=%.3f, Z=%.3f (bangs=%s)" % [
							h_pos.x, h_pos.y, h_pos.z, str(is_front_bangs)
						])

	print("Total verts: ", total_count, ", Discarded: ", discarded_count)
	print("Rule counts: ", rule_counts)

	inst.queue_free()
	quit(0)
