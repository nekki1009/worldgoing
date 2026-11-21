extends SceneTree
## Checks the regenerated imported resource; visual CA-02 uses the editor separately.
var checks: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		push_error("CIV_STRAW_IMPORT_FAIL " + label)
		quit(1)
		assert(ok, label)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var sex: String = args[0]
	var output: String = args[1]
	check(sex in ["male", "female"] and output.begins_with("res://output/"), "scoped arguments")
	var path: String = "res://assets/characters/human/q35/standard_anime_" + sex + "_character_pack.glb"
	var config := ConfigFile.new()
	check(config.load(path + ".import") == OK, "formal GLB import remap")
	var imported: String = config.get_value("remap", "path", "")
	check(not imported.is_empty() and FileAccess.file_exists(imported), "generated imported scene exists")
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	check(packed != null, "load actual imported formal-path pack")
	var model := packed.instantiate() as Node3D
	check(model != null, "instantiate imported pack")
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path.get_basename() + ".json"))
	var names: Array[String] = []
	for slot: String in ["boots", "helmet"]:
		for name: String in metadata["parts"][slot]:
			if not name.begins_with("Boots_Civilian_Straw_01_") and not name.begins_with("Helmet_Civilian_Straw_01_"): continue
			var node := model.find_child(name, true, false) as MeshInstance3D
			check(node != null and node.mesh != null and node.skin != null, "imported skinned mesh " + name)
			names.append(name)
	check(names.size() > 50, "complete detailed straw geometry")
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	check(player != null and player.get_animation_list().size() > 0, "original imported animations exist")
	check(not FileAccess.file_exists(output), "fresh result output")
	check(DirAccess.make_dir_recursive_absolute(output.get_base_dir()) == OK, "create result directory")
	var file := FileAccess.open(output, FileAccess.WRITE)
	check(file != null, "open result")
	file.store_string(JSON.stringify({"status": "PASS", "sex": sex, "checks": checks,
		"formal_glb_sha256": FileAccess.get_sha256(path), "imported_scene": imported,
		"new_skinned_meshes": names, "animation_names": player.get_animation_list(),
		"scope": "fresh imported resource has the detailed new meshes; no raw/imported pixel equivalence claim"}, "\t"))
	file.close()
	model.free()
	print("CIV_STRAW_IMPORT_PASS ", sex, " checks=", checks)
	quit(0)
