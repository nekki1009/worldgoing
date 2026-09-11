extends SceneTree

const FEMALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_female_character_pack.glb"
const MALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_male_character_pack.glb"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== Male Hair & Leather Helmet around Ear ===")
	_inspect_model(MALE_MODEL_PATH, "Hair_Short_01", false)
	print("=== Female Hair & Leather Helmet around Ear ===")
	_inspect_model(FEMALE_MODEL_PATH, "Hair_Long_01", true)
	quit(0)

func _inspect_model(path: String, hair_name: String, is_female: bool) -> void:
	var scene := load(path) as PackedScene
	var inst := scene.instantiate() as Node3D
	root.add_child(inst)
	
	var skeleton := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var head_bone_idx := skeleton.find_bone("J_Bip_C_Head")
	var head_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head_bone_idx)
	var inv_head := head_world.affine_inverse()
	
	var dome_center := Vector3(0.0, 0.088 if not is_female else 0.082, -0.005)
	var dome_radii := Vector3(0.126, 0.138, 0.142) if not is_female else Vector3(0.120, 0.132, 0.136)
	var brow_cut_y := 0.105
	
	# Check Helmet_Leather_01 ear cutout rim vertices
	for child in inst.find_children("Helmet_Leather_01*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		var m := mesh_node.mesh
		var ear_rim_verts: Array[Vector3] = []
		for s in range(m.get_surface_count()):
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var h_pos := inv_head * (mesh_node.global_transform * v)
				# Ear notch is around x ~ 0.075-0.12, z ~ -0.06 to +0.03
				if abs(h_pos.x) > 0.075 and h_pos.z > -0.06 and h_pos.z < 0.03 and h_pos.y < 0.16:
					ear_rim_verts.append(h_pos)
		print(mesh_node.name, " ear region verts count: ", ear_rim_verts.size())
		var min_y := 999.0
		var max_y := -999.0
		for ev in ear_rim_verts:
			min_y = minf(min_y, ev.y)
			max_y = maxf(max_y, ev.y)
		print("  Helmet ear notch Y range: ", min_y, " to ", max_y)
		ear_rim_verts.sort_custom(func(a, b): return a.y < b.y)
		for i in range(mini(10, ear_rim_verts.size())):
			print("  ear notch bottom vert: ", ear_rim_verts[i])

	# Check Hair around ear
	for child in inst.find_children(hair_name + "*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		var m := mesh_node.mesh
		var culled_by_dome := 0
		var culled_by_spikes := 0
		var culled_by_twintail := 0
		var culled_by_ponytail := 0
		var ear_hair_verts: Array[Vector3] = []
		for s in range(m.get_surface_count()):
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var h_pos := inv_head * (mesh_node.global_transform * v)
				if abs(h_pos.x) > 0.06 and h_pos.z > -0.06 and h_pos.z < 0.03:
					ear_hair_verts.append(h_pos)
					var is_front_bangs: bool = (h_pos.z > 0.015 and h_pos.y <= (brow_cut_y + 0.008) and abs(h_pos.x) <= 0.068)
					if not is_front_bangs:
						if h_pos.y > brow_cut_y:
							var d := (h_pos - dome_center) / dome_radii
							if d.dot(d) <= 1.06:
								culled_by_dome += 1
							elif h_pos.y > (dome_center.y + dome_radii.y * 0.28):
								culled_by_spikes += 1
						if abs(h_pos.x) > 0.106 and h_pos.z < 0.035:
							culled_by_twintail += 1
						if h_pos.z < -0.128 or (h_pos.y < -0.05 and h_pos.z < -0.105 and abs(h_pos.x) < 0.060):
							culled_by_ponytail += 1
		print(mesh_node.name, " ear region hair verts: ", ear_hair_verts.size())
		print("  culled by dome: ", culled_by_dome, ", spikes: ", culled_by_spikes, ", twintail: ", culled_by_twintail, ", ponytail: ", culled_by_ponytail)
		var y_culled_min := 999.0
		for ev in ear_hair_verts:
			var d := (ev - dome_center) / dome_radii
			if ev.y > brow_cut_y and (d.dot(d) <= 1.06 or ev.y > (dome_center.y + dome_radii.y * 0.28)):
				y_culled_min = minf(y_culled_min, ev.y)
		print("  lowest Y culled around ear: ", y_culled_min)
	
	inst.queue_free()
