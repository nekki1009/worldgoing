extends SceneTree
## Check the real imported PackedScenes, not the editor's raw GLB fallback.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for sex in ["male", "female"]:
		var path := "res://assets/characters/human/q35/standard_anime_%s_character_pack.glb" % sex
		var packed := load(path) as PackedScene
		assert(packed != null)
		var model := packed.instantiate()
		root.add_child(model)
		var skeletons := model.find_children("*", "Skeleton3D", true, false)
		assert(skeletons.size() == 1)
		var skeleton := skeletons[0] as Skeleton3D
		assert(skeleton.find_bone("J_Bip_C_Head") >= 0)
		var hats := model.find_children("Helmet_Cloth_*", "MeshInstance3D", true, false)
		assert(hats.size() == 37, "Imported cache must include all new authored meshes")
		for style in ["Chinese", "Japanese", "Western"]:
			var crown := model.find_child("Helmet_Cloth_%s_01_Crown" % style, true, false) as MeshInstance3D
			assert(crown != null and crown.skin != null and crown.get_node(crown.skeleton) == skeleton)
			var material := crown.get_active_material(0) as BaseMaterial3D
			assert(material != null and material.metallic == 0.0 and material.roughness > .85 and material.albedo_texture != null)
		print("CLOTH_HATS_IMPORTED_PACK_PASS ", sex, " 37 meshes, native skeleton, matte woven cloth")
		model.queue_free()
		await process_frame
	quit(0)
