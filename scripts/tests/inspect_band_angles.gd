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
	
	var node := inst.find_child("Helmet_Leather_01_Band", true, false) as MeshInstance3D
	var m := node.mesh
	var arrays := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	
	# Print all lower rim vertices sorted by angle around head:
	var rim_pts := []
	for v in verts:
		var hp := inv_head * (node.global_transform * v)
		# Only bottom rim vertices (y < 0.11)
		if hp.y < 0.115:
			rim_pts.append(hp)
	print("Found ", rim_pts.size(), " lower rim vertices on Band:")
	# Sort by angle in XZ plane
	rim_pts.sort_custom(func(a: Vector3, b: Vector3): return atan2(a.x, a.z) < atan2(b.x, b.z))
	for p: Vector3 in rim_pts:
		var ang_deg := rad_to_deg(atan2(p.x, p.z))
		print("  angle=%6.1f deg: hp=(%6.3f, %6.3f, %6.3f)" % [ang_deg, p.x, p.y, p.z])
	quit(0)
