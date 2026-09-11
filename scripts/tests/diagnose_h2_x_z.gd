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
	
	var node := inst.find_child("Hair_Long_02", true, false) as MeshInstance3D
	var m := node.mesh
	var arrays := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	
	for v in verts:
		var h_pos := inv_head * (node.global_transform * v)
		if absf(h_pos.x) > 0.082 and h_pos.z < 0.035:
			# Check height and position
			pass
	var count_back := 0
	var count_mid := 0
	var count_front := 0
	for v in verts:
		var h_pos := inv_head * (node.global_transform * v)
		if absf(h_pos.x) > 0.082:
			if h_pos.z < -0.02:
				count_back += 1
			elif h_pos.z <= 0.035:
				count_mid += 1
			else:
				count_front += 1
	print("Hair_Long_02 |X| > 0.082: back (Z<-0.02)=", count_back, " mid (Z in [-0.02, 0.035])=", count_mid, " front (Z>0.035)=", count_front)
	quit(0)
