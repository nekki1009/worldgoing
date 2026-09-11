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

	var mask_center_offset := Vector3(0.0, 0.082, -0.005)
	var mask_radii := Vector3(0.120, 0.132, 0.136)
	var brow_cut_y := 0.102
	var front_bangs_mode := 1
	var cull_twintails := false
	var cull_ponytail := false

	var discarded_count := 0
	var total_count := 0
	var rule_counts := {"NOSE": 0, "DOME": 0, "SPIKE": 0, "TWINTAIL": 0, "PONYTAIL": 0}

	for child in inst.find_children("Hair_Long_02*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		var m := mesh_node.mesh
		for s in range(m.get_surface_count()):
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				total_count += 1
				var h_pos := inv_head * (mesh_node.global_transform * v)
				
				var disc := false
				if front_bangs_mode == 1 and h_pos.z > 0.080 and h_pos.y < 0.055 and abs(h_pos.x) < 0.030:
					rule_counts["NOSE"] += 1
					disc = true
				
				var is_front_bangs: bool = (h_pos.z > 0.015 and h_pos.y <= (brow_cut_y + 0.008) and abs(h_pos.x) <= 0.068)
				
				if not disc and not is_front_bangs:
					if h_pos.y > brow_cut_y:
						var d := (h_pos - mask_center_offset) / mask_radii
						if d.dot(d) <= 1.06:
							rule_counts["DOME"] += 1
							disc = true
						elif h_pos.y > (mask_center_offset.y + mask_radii.y * 0.28):
							rule_counts["SPIKE"] += 1
							disc = true
					
					if not disc and cull_twintails and abs(h_pos.x) > 0.106 and h_pos.z < 0.035:
						rule_counts["TWINTAIL"] += 1
						disc = true
					
					if not disc and cull_ponytail and (h_pos.z < -0.128 or (h_pos.y < -0.05 and h_pos.z < -0.105 and abs(h_pos.x) < 0.060)):
						rule_counts["PONYTAIL"] += 1
						disc = true
				
				if disc:
					discarded_count += 1
				else:
					# Surviving vert!
					if h_pos.z < -0.05 and h_pos.y < 0.0:
						print("Surviving rear hair vert: X=%.3f, Y=%.3f, Z=%.3f" % [h_pos.x, h_pos.y, h_pos.z])

	print("Total verts: ", total_count, ", Discarded: ", discarded_count)
	print("Rule counts: ", rule_counts)

	inst.queue_free()
	quit(0)
