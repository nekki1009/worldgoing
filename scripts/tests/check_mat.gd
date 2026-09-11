extends SceneTree

func _init() -> void:
	var glb := load("res://assets/characters/human/q35/standard_anime_female_character_pack.glb") as PackedScene
	if glb:
		var inst := glb.instantiate()
		_check(inst)
	quit()

func _check(node: Node) -> void:
	if "Helmet" in node.name:
		print("FOUND: ", node.name, " type=", node.get_class())
		if node is MeshInstance3D and node.mesh:
			print("  surfaces=", node.mesh.get_surface_count())
			for s in range(node.mesh.get_surface_count()):
				var mat = node.get_active_material(s)
				if mat is BaseMaterial3D:
					print("    mat name=", mat.resource_name, " albedo=", mat.albedo_color)
				else:
					print("    mat=", mat)
	for child in node.get_children():
		_check(child)
