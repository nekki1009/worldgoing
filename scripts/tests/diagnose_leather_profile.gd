extends SceneTree

const FEMALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_female_character_pack.glb"
const MALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_male_character_pack.glb"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_inspect_helmet_rim(MALE_MODEL_PATH, "Male")
	_inspect_helmet_rim(FEMALE_MODEL_PATH, "Female")
	quit(0)

func _inspect_helmet_rim(path: String, label: String) -> void:
	var scene := load(path) as PackedScene
	var inst := scene.instantiate() as Node3D
	root.add_child(inst)
	
	var skeleton := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var head_bone_idx := skeleton.find_bone("J_Bip_C_Head")
	var head_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head_bone_idx)
	var inv_head := head_world.affine_inverse()
	
	print("================ ", label, " Leather Helmet Profile ================")
	
	# We want to know for different angular sectors around the head (yaw angle 0 to 360):
	# What is the minimum Y (lowest point) of Helmet_Leather_01?
	# And what is the maximum radius R = sqrt(X^2 + Z^2)?
	var sector_min_y: Dictionary = {}
	var sector_max_y: Dictionary = {}
	var sector_samples: Dictionary = {}
	
	for s in range(16):
		sector_min_y[s] = 999.0
		sector_max_y[s] = -999.0
		sector_samples[s] = []
	
	for child in inst.find_children("Helmet_Leather_01*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		# Ignore rivets/emblems, focus on Band, Dome, CheekGuards
		if "Rivets" in mesh_node.name or "Rosettes" in mesh_node.name or "Emblem" in mesh_node.name:
			continue
		var m := mesh_node.mesh
		if m == null:
			continue
		for s in range(m.get_surface_count()):
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var h_pos := inv_head * (mesh_node.global_transform * v)
				var angle := atan2(h_pos.x, h_pos.z) # 0 = front (+Z), PI/2 = left (+X), -PI/2 = right (-X), PI = back (-Z)
				var deg := rad_to_deg(angle)
				if deg < 0:
					deg += 360.0
				var sector := int(floor(deg / 22.5)) % 16
				sector_min_y[sector] = minf(sector_min_y[sector], h_pos.y)
				sector_max_y[sector] = maxf(sector_max_y[sector], h_pos.y)
				sector_samples[sector].append(h_pos)
	
	var sector_names := [
		"Front (+Z, nasal/brow)",
		"Front-Left 1",
		"Front-Left 2 (cheek top)",
		"Left-Cheek (+X, Z>0)",
		"Left-Ear (+X, Z~0)",
		"Left-Behind-Ear",
		"Rear-Left (nape guard)",
		"Rear-Left 2",
		"Back (-Z, nape center)",
		"Rear-Right 2",
		"Rear-Right (nape guard)",
		"Right-Behind-Ear",
		"Right-Ear (-X, Z~0)",
		"Right-Cheek (-X, Z>0)",
		"Front-Right 2 (cheek top)",
		"Front-Right 1"
	]
	
	for s in range(16):
		var deg_start := s * 22.5
		var deg_end := (s + 1) * 22.5
		print("[%2d] %-28s (deg %5.1f-%5.1f): min_Y = %6.3f, max_Y = %6.3f (pts: %d)" % [
			s, sector_names[s], deg_start, deg_end, sector_min_y[s], sector_max_y[s], sector_samples[s].size()
		])
	
	inst.queue_free()
