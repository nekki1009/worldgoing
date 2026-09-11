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
	
	var node := inst.find_child("Hair_Long_04", true, false) as MeshInstance3D
	var m := node.mesh
	var arrays := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	
	# Compare Hair_Long_04 with Hair_Long_03 (bob, which has only skull cap):
	var node3 := inst.find_child("Hair_Long_03", true, false) as MeshInstance3D
	var m3 := node3.mesh
	var verts3: PackedVector3Array = m3.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	
	# Any vertex in Hair_Long_04 that is NOT in Hair_Long_03 is part of the ponytail!
	print("Hair_Long_04 total verts: ", verts.size(), ", Hair_Long_03 verts: ", verts3.size())
	# Let's inspect the ponytail vertices in Hair_Long_04:
	# Hair_Long_04 has 7431 verts, Hair_Long_03 has 7395 verts.
	# Wait! Hair_Long_04 only has 36 more verts? Or were they added via strands?
	# Let's check how many verts Hair_Long_04 has vs Hair_Long_03:
	# In diagnose_hair_coords.gd:
	# Hair_Long_03 (7395 verts): min=(-0.1087, -0.1018, -0.1218) max=(0.1086, 0.2269, 0.1253)
	# Hair_Long_04 (7431 verts): min=(-0.1087, -0.2818, -0.1752) max=(0.1086, 0.2323, 0.1253)
	
	# Notice Hair_Long_04 min Y is -0.2818! (While Hair_Long_03 min Y is -0.1018)
	# And Hair_Long_04 min Z is -0.1752! (While Hair_Long_03 min Z is -0.1218)
	
	# Let's find vertices in Hair_Long_04 that have Z < -0.1218 or Y < -0.1018:
	var ponytail_verts := 0
	for v in verts:
		var hp := inv_head * (node.global_transform * v)
		if hp.z < -0.1218 or (hp.z < -0.05 and hp.y < -0.10):
			ponytail_verts += 1
	print("Ponytail verts by depth/length: ", ponytail_verts)
	quit(0)
