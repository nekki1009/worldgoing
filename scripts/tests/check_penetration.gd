extends SceneTree

const FEMALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_female_character_pack.glb"
const MALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_male_character_pack.glb"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Checking Hair vs Helmet Penetration ---")
	_check_penetration(MALE_MODEL_PATH, "Male", [
		"Hair_Short_01", "Hair_Short_02", "Hair_Short_03", "Hair_Short_04"
	])
	_check_penetration(FEMALE_MODEL_PATH, "Female", [
		"Hair_Long_02", "Hair_Long_03", "Hair_Long_04"
	])
	quit(0)

func _check_penetration(path: String, label: String, hair_names: Array) -> void:
	var scene := load(path) as PackedScene
	var inst := scene.instantiate() as Node3D
	root.add_child(inst)
	
	var skeleton := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var head_bone_idx := skeleton.find_bone("J_Bip_C_Head")
	var head_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head_bone_idx)
	var inv_head := head_world.affine_inverse()
	
	# For leather helmet, what is the maximum extent:
	# Dome top: Y = 0.240. At Y = 0.18, R ~ 0.12.
	# Let's check hair vertices above Y = 0.12 (top crown) vs below Y = 0.12:
	for hname in hair_names:
		for child in inst.find_children(hname + "*", "MeshInstance3D", true, false):
			var mesh_node := child as MeshInstance3D
			var m := mesh_node.mesh
			var above_12 := 0
			var below_12 := 0
			var max_y := -999.0
			var max_x_below_12 := -999.0
			var max_z_below_12 := -999.0
			var min_z_below_12 := 999.0
			for s in range(m.get_surface_count()):
				var arrays := m.surface_get_arrays(s)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for v in verts:
					var h_pos := inv_head * (mesh_node.global_transform * v)
					max_y = maxf(max_y, h_pos.y)
					if h_pos.y >= 0.120:
						above_12 += 1
					else:
						below_12 += 1
						max_x_below_12 = maxf(max_x_below_12, abs(h_pos.x))
						max_z_below_12 = maxf(max_z_below_12, h_pos.z)
						min_z_below_12 = minf(min_z_below_12, h_pos.z)
			print("%-6s %-15s: max_Y=%.3f, above_0.12=%d, below_0.12=%d | below_0.12: max|X|=%.3f, Z=[%.3f, %.3f]" % [
				label, hname, max_y, above_12, below_12, max_x_below_12, min_z_below_12, max_z_below_12
			])
	
	inst.queue_free()
