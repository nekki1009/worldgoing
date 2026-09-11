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
	
	var node4 := inst.find_child("Hair_Long_04", true, false) as MeshInstance3D
	var m4 := node4.mesh
	var verts4: PackedVector3Array = m4.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	
	var node3 := inst.find_child("Hair_Long_03", true, false) as MeshInstance3D
	var m3 := node3.mesh
	var verts3: PackedVector3Array = m3.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	
	# Hair_Long_04 has all the verts of Hair_Long_03 plus the ponytail strands:
	print("Hair_Long_04 total: ", verts4.size(), " Hair_Long_03 total: ", verts3.size())
	var extra_verts := []
	for i in range(verts3.size(), verts4.size()):
		var hp := inv_head * (node4.global_transform * verts4[i])
		extra_verts.append(hp)
	print("Found ", extra_verts.size(), " ponytail strand verts in Hair_Long_04:")
	var min_p := Vector3(INF, INF, INF)
	var max_p := Vector3(-INF, -INF, -INF)
	for p: Vector3 in extra_verts:
		min_p.x = minf(min_p.x, p.x)
		min_p.y = minf(min_p.y, p.y)
		min_p.z = minf(min_p.z, p.z)
		max_p.x = maxf(max_p.x, p.x)
		max_p.y = maxf(max_p.y, p.y)
		max_p.z = maxf(max_p.z, p.z)
	print("Ponytail bounds: min=", min_p, " max=", max_p)
	
	# Check where ponytail verts have Z >= -0.128:
	var z_greater := []
	for p: Vector3 in extra_verts:
		if p.z >= -0.128:
			z_greater.append(p)
	print("Ponytail verts with Z >= -0.128: ", z_greater.size())
	for p: Vector3 in z_greater:
		print("  p = ", p)
	quit(0)
