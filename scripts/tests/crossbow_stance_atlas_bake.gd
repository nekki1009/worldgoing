extends "res://scripts/tools/bake_terrain_army_soldier.gd"

func _initialize() -> void:
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/crossbow_stance_20260914/atlas")) == OK)
	super._initialize()

func _destination(source_path: String) -> String:
	return "res://output/crossbow_stance_20260914/atlas/" + source_path.get_file()
