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
	var brow_cut_y := 0.120
	var front_bangs_mode := 1

	for child in inst.find_children("Hair_Short_01*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		var m := mesh_node.mesh
		for s in range(m.get_surface_count()):
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var h_pos := inv_head * (mesh_node.global_transform * v)
				# Target vertices in the ear notch and temple region:
				# X: 0.06 to 0.13, Y: 0.04 to 0.14, Z: -0.04 to 0.05
				if h_pos.x > 0.06 and h_pos.y > 0.04 and h_pos.y < 0.14 and h_pos.z > -0.04 and h_pos.z < 0.05:
					# Check which rule discards this vertex
					var discarded_by := "NONE (SURVIVES!)"
					
					if front_bangs_mode == 1 and h_pos.z > 0.080 and h_pos.y < 0.055 and abs(h_pos.x) < 0.030:
						discarded_by = "NOSE_BRIDGE_BANG_TIP"
					
					var is_front_bangs: bool = (h_pos.z > 0.015 and h_pos.y <= (brow_cut_y + 0.008) and abs(h_pos.x) <= 0.068)
					
					if not is_front_bangs and discarded_by == "NONE (SURVIVES!)":
						if h_pos.y > brow_cut_y:
							var d := (h_pos - mask_center_offset) / mask_radii
							if d.dot(d) <= 1.06:
								discarded_by = "RULE_A_DOME_ELLIPSOID (dot=%.3f)" % d.dot(d)
							elif h_pos.y > (mask_center_offset.y + mask_radii.y * 0.28):
								discarded_by = "RULE_A_CROWN_SPIKES"
						
						var twintail_x := 0.106 if (mask_radii.x < 0.123) else 0.128
						if discarded_by == "NONE (SURVIVES!)" and abs(h_pos.x) > twintail_x and h_pos.z < 0.035:
							discarded_by = "RULE_B_TWINTAIL"
						
						if discarded_by == "NONE (SURVIVES!)" and (h_pos.z < -0.128 or (h_pos.y < -0.05 and h_pos.z < -0.105 and abs(h_pos.x) < 0.060)):
							discarded_by = "RULE_C_PONITAIL"

					print("Ear/Temple Vert: X=%6.3f, Y=%6.3f, Z=%6.3f -> %s" % [
						h_pos.x, h_pos.y, h_pos.z, discarded_by
					])

	inst.queue_free()
	quit(0)
