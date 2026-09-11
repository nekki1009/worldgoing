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
	
	var node := inst.find_child("Hair_Long_01", true, false) as MeshInstance3D
	var m := node.mesh
	var arrays := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	
	var min_z := 999.0
	var max_z := -999.0
	var min_y := 999.0
	var max_y := -999.0
	var count := 0
	for v in verts:
		var h_pos := inv_head * (node.global_transform * v)
		if absf(h_pos.x) > 0.085:
			min_z = minf(min_z, h_pos.z)
			max_z = maxf(max_z, h_pos.z)
			min_y = minf(min_y, h_pos.y)
			max_y = maxf(max_y, h_pos.y)
			count += 1
	print("Hair_Long_01 |X| > 0.085: count=", count, " Y in [", min_y, ", ", max_y, "] Z in [", min_z, ", ", max_z, "]")
	quit(0)
