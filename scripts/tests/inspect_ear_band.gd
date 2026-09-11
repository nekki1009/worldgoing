extends SceneTree

const FEMALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_female_character_pack.glb"
const MALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_male_character_pack.glb"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_inspect_band(MALE_MODEL_PATH, "Male")
	quit(0)

func _inspect_band(path: String, label: String) -> void:
	var scene := load(path) as PackedScene
	var inst := scene.instantiate() as Node3D
	root.add_child(inst)
	
	var skeleton := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var head_bone_idx := skeleton.find_bone("J_Bip_C_Head")
	var head_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head_bone_idx)
	var inv_head := head_world.affine_inverse()
	
	for child in inst.find_children("Helmet_Leather_01_Band", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		var m := mesh_node.mesh
		for s in range(m.get_surface_count()):
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			print("Helmet_Leather_01_Band vertices:")
			for v in verts:
				var h_pos := inv_head * (mesh_node.global_transform * v)
				if h_pos.x > 0.08 and abs(h_pos.z) < 0.04:
					print("  X=%6.3f, Y=%6.3f, Z=%6.3f" % [h_pos.x, h_pos.y, h_pos.z])
	inst.queue_free()
