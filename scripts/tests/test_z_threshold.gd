extends SceneTree

const FEMALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_female_character_pack.glb"
const MALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_male_character_pack.glb"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Female: vertices with Z < -0.125 ---")
	_test(FEMALE_MODEL_PATH, -0.125)
	print("--- Female: vertices with Z < -0.128 ---")
	_test(FEMALE_MODEL_PATH, -0.128)
	print("--- Male: vertices with Z < -0.125 ---")
	_test(MALE_MODEL_PATH, -0.125)
	quit(0)

func _test(path: String, z_th: float) -> void:
	var scene := load(path) as PackedScene
	var inst := scene.instantiate() as Node3D
	root.add_child(inst)
	var skeleton := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var head_bone_idx := skeleton.find_bone("J_Bip_C_Head")
	var head_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head_bone_idx)
	var inv_head := head_world.affine_inverse()
	
	for child in inst.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		var mname := mesh_node.name
		if not mname.begins_with("Hair_"):
			continue
		var m := mesh_node.mesh
		if m == null:
			continue
		var count := 0
		for s in range(m.get_surface_count()):
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var hp := inv_head * (mesh_node.global_transform * v)
				if hp.z < z_th:
					count += 1
		print("  ", mname, ": ", count, " verts")
	inst.queue_free()
