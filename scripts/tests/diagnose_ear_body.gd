extends SceneTree

const FEMALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_female_character_pack.glb"
const MALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_male_character_pack.glb"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_inspect_head(MALE_MODEL_PATH, "Male")
	_inspect_head(FEMALE_MODEL_PATH, "Female")
	quit(0)

func _inspect_head(path: String, label: String) -> void:
	var scene := load(path) as PackedScene
	var inst := scene.instantiate() as Node3D
	root.add_child(inst)
	
	var skeleton := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var head_bone_idx := skeleton.find_bone("J_Bip_C_Head")
	var head_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head_bone_idx)
	var inv_head := head_world.affine_inverse()
	
	print("--- Head Body Vertices for ", label, " around Ear (X > 0.06, |Z| < 0.04) ---")
	for child in inst.find_children("Body*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		var m := mesh_node.mesh
		var min_y := 999.0
		var max_y := -999.0
		var max_x := -999.0
		for s in range(m.get_surface_count()):
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var h_pos := inv_head * (mesh_node.global_transform * v)
				if h_pos.x > 0.06 and abs(h_pos.z) < 0.04:
					min_y = minf(min_y, h_pos.y)
					max_y = maxf(max_y, h_pos.y)
					max_x = maxf(max_x, h_pos.x)
		print("Ear Y range: ", min_y, " to ", max_y, ", max X: ", max_x)
	inst.queue_free()
