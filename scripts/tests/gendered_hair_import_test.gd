extends SceneTree

func _init() -> void:
	for sex in ["male","female"]:
		var path := "res://assets/characters/human/q35/standard_anime_%s_character_pack.glb" % sex
		var scene := load(path) as PackedScene
		assert(scene != null)
		var instance := scene.instantiate()
		assert(instance.find_children("*","Skeleton3D",true,false).size() == 1)
		for i in range(1,9):
			var prefix := ("Hair_Long_" if sex == "female" else "Hair_Short_") if i <= 4 else ("Hair_Female_" if sex == "female" else "Hair_Male_")
			assert(instance.find_child(prefix+"%02d" % i,true,false) is MeshInstance3D,"Imported cache missing hair")
		instance.free()
		print("GENDERED_HAIR_IMPORTED_SCENE_PASS ",sex," styles=8")
	quit(0)
