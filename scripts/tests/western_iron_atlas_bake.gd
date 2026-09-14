extends "res://scripts/tools/bake_terrain_army_soldier.gd"

func _initialize() -> void:
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/western_iron_atlas_20260913/base2")) == OK)
	super._initialize()

func _destination(source_path: String) -> String:
	return "res://output/western_iron_atlas_20260913/base2/" + source_path.get_file()
