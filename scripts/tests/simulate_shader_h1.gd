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
	
	# Simulate the TEST_SHADER on every vertex of Hair_Long_01:
	var mask_center_offset := Vector3(0.0, 0.082, -0.005)
	var mask_radii := Vector3(0.120, 0.132, 0.136)
	var brow_cut_y := 0.088
	var front_bangs_mode := 1
	
	var remaining_verts := []
	for v in verts:
		var hp := inv_head * (node.global_transform * v)
		var discarded := false
		
		if front_bangs_mode == 1 and hp.z > 0.080 and hp.y < 0.055 and absf(hp.x) < 0.030:
			discarded = true
		
		var is_front_bangs := (hp.z > 0.015 and hp.y <= (brow_cut_y + 0.006) and absf(hp.x) <= 0.065)
		if not is_front_bangs and not discarded:
			if hp.y > brow_cut_y:
				var d := (hp - mask_center_offset) / mask_radii
				if d.length_squared() <= 1.06:
					discarded = true
				elif hp.y > (mask_center_offset.y + mask_radii.y * 0.28):
					discarded = true
			if not discarded:
				if absf(hp.x) > 0.106 and hp.z < 0.035:
					discarded = true
				elif hp.z < -0.128 or (hp.y < -0.05 and hp.z < -0.105 and absf(hp.x) < 0.060):
					discarded = true
		if not discarded:
			remaining_verts.append(hp)
	
	print("Original verts: ", verts.size(), ", Remaining verts: ", remaining_verts.size())
	# Check remaining verts at low Y (below -0.04):
	var low_verts := []
	for p: Vector3 in remaining_verts:
		if p.y < -0.04:
			low_verts.append(p)
	print("Remaining verts with Y < -0.04: ", low_verts.size())
	for p: Vector3 in low_verts:
		print("   hp = ", p)
	quit(0)
