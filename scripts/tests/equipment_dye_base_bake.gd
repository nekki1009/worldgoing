extends "res://scripts/tools/bake_terrain_army_soldier.gd"
const STAGE := "res://output/equipment_palette_policy_20260914/base"

func _initialize() -> void:
	assert(not FileAccess.file_exists(STAGE + "/standard_soldier_atlas.json"), "Use a fresh complete stage")
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STAGE)) == OK)
	super._initialize()

func _destination(source_path: String) -> String:
	return STAGE + "/" + source_path.get_file()
