extends SceneTree

const FEMALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_female_character_pack.glb"
const MALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_male_character_pack.glb"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Female Hair Vertices in Head Bone Space ---")
	_inspect_model(FEMALE_MODEL_PATH)
	print("--- Male Hair Vertices in Head Bone Space ---")
	_inspect_model(MALE_MODEL_PATH)
	quit(0)

func _inspect_model(path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		print("Failed to load: ", path)
		return
	var inst := scene.instantiate() as Node3D
	root.add_child(inst)
	
	var skeleton := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var head_bone_idx := skeleton.find_bone("J_Bip_C_Head")
	var head_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head_bone_idx)
	var inv_head := head_world.affine_inverse()
	
	for child in inst.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		var mname := mesh_node.name
		if not (mname.begins_with("Hair_") or mname.begins_with("Helmet_")):
			continue
		var m := mesh_node.mesh
		if m == null:
			continue
		var min_pos := Vector3(INF, INF, INF)
		var max_pos := Vector3(-INF, -INF, -INF)
		var vert_count := 0
		for s in range(m.get_surface_count()):
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var node_transform := mesh_node.global_transform
			for v in verts:
				var w_pos := node_transform * v
				var h_pos := inv_head * w_pos
				min_pos.x = minf(min_pos.x, h_pos.x)
				min_pos.y = minf(min_pos.y, h_pos.y)
				min_pos.z = minf(min_pos.z, h_pos.z)
				max_pos.x = maxf(max_pos.x, h_pos.x)
				max_pos.y = maxf(max_pos.y, h_pos.y)
				max_pos.z = maxf(max_pos.z, h_pos.z)
				vert_count += 1
		print(mname, " (", vert_count, " verts): min=", min_pos, " max=", max_pos)
	inst.queue_free()
