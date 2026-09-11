extends SceneTree

const FEMALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_female_character_pack.glb"
const MALE_MODEL_PATH: String = "res://assets/characters/human/q35/standard_anime_male_character_pack.glb"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Female Helmet Leather 01 Band Front Rim ---")
	_inspect_band(FEMALE_MODEL_PATH)
	print("--- Male Helmet Leather 01 Band Front Rim ---")
	_inspect_band(MALE_MODEL_PATH)
	quit(0)

func _inspect_band(path: String) -> void:
	var scene := load(path) as PackedScene
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
	
	# Check vertices in front (Z > 0.05) and not nasal guard (|X| > 0.03):
	for v in verts:
		var hp := inv_head * (node.global_transform * v)
		if hp.z > 0.05 and absf(hp.x) > 0.02 and absf(hp.x) < 0.07:
			print("   hp = ", hp)
	inst.queue_free()
