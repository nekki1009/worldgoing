extends SceneTree

const FEMALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_female_character_pack.glb"
const MALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_male_character_pack.glb"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Female Front Bangs (Z > 0.015, |X| < 0.070) ---")
	_check_bangs(FEMALE_MODEL_PATH, "Hair_Long_01")
	print("--- Male Front Bangs (Z > 0.015, |X| < 0.070) ---")
	_check_bangs(MALE_MODEL_PATH, "Hair_Short_01")
	quit(0)

func _check_bangs(path: String, hname: String) -> void:
	var scene := load(path) as PackedScene
	var inst := scene.instantiate() as Node3D
	root.add_child(inst)
	var skeleton := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var head_bone_idx := skeleton.find_bone("J_Bip_C_Head")
	var head_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head_bone_idx)
	var inv_head := head_world.affine_inverse()
	var node := inst.find_child(hname, true, false) as MeshInstance3D
	var m := node.mesh
	var arrays := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var y_counts := {}
	for y_step in range(4, 16):
		y_counts[y_step] = 0
	for v in verts:
		var h_pos := inv_head * (node.global_transform * v)
		if h_pos.z > 0.015 and absf(h_pos.x) <= 0.070:
			var y_i := int(floor(h_pos.y * 100.0))
			if y_counts.has(y_i):
				y_counts[y_i] += 1
	for k in y_counts.keys():
		print("  Y [", float(k)/100.0, ", ", float(k+1)/100.0, "]: ", y_counts[k], " verts")
	inst.queue_free()
