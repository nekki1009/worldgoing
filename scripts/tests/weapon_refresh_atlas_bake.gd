extends "res://scripts/tools/bake_terrain_army_soldier.gd"

## Reuse the native 1080-frame baker, but publish only after the staged bundle
## has finished and passed verification. Do not overwrite old recipe batches.
func _initialize() -> void:
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/weapon_refresh_20260913/atlas"))
	assert(error == OK, "Cannot create staged atlas directory")
	super._initialize()

func _destination(source_path: String) -> String:
	return "res://output/weapon_refresh_20260913/atlas/" + source_path.get_file()
