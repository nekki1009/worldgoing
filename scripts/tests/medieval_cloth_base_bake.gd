extends "res://scripts/tools/bake_terrain_army_soldier.gd"
var STAGE := "res://output/medieval_cloth_20260916/atlases/base"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		assert(args.size() == 1 and args[0].begins_with("--stage="))
		STAGE = args[0].trim_prefix("--stage=").simplify_path()
		assert(STAGE.begins_with("res://output/") and STAGE.ends_with("/base"))
	assert(not FileAccess.file_exists(STAGE + "/standard_soldier_atlas.json"), "Use a fresh complete stage")
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STAGE)) == OK)
	super._initialize()

func _destination(source_path: String) -> String:
	return STAGE + "/" + source_path.get_file()
