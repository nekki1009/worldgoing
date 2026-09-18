extends "res://scripts/tools/bake_terrain_army_soldier.gd"
## Female bow/crossbow variants of the original exact ranged plan and renderer.
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
var _female_sources := {}
var _female_base_md5 := ""

func _initialize() -> void:
	_started_usec = Time.get_ticks_usec()
	var arguments := OS.get_cmdline_user_args()
	assert(arguments.size() == 2 and arguments[0].begins_with("--weapon=") and arguments[1].begins_with("--output=res://output/"))
	var weapon := arguments[0].trim_prefix("--weapon=")
	var output := arguments[1].trim_prefix("--output=").simplify_path().trim_suffix("/")
	assert(output.begins_with("res://output/") and not DirAccess.dir_exists_absolute(output), "Use a fresh named staging directory")
	_recipe = Atlas.female_ranged_plan(weapon)
	assert(not _recipe.is_empty() and HumanCharacter3DEditor.valid_appearance(_recipe.appearance))
	_recipe.merge({"ok": true, "mask": 29, "iron": 0, "output": output, "first": 0,
		"count": _recipe.recipe_total, "selected_total": _recipe.recipe_total,
		"selection_complete": true, "recipe_complete": true, "source_fingerprints": RecipePlan.fingerprints()})
	_female_sources = Atlas.female_ranged_sources()
	_female_base_md5 = FileAccess.get_md5(MANIFEST_PATH)
	assert(not _female_sources.is_empty() and _female_base_md5.length() == 32)
	call_deferred("_run")

func _write_recipe_manifest(atlas: Image, frames: Array[Dictionary]) -> void:
	assert(_female_sources == Atlas.female_ranged_sources() and _female_base_md5 == FileAccess.get_md5(MANIFEST_PATH), "Female ranged sources changed during bake")
	super._write_recipe_manifest(atlas, frames)
	var path := _destination(MANIFEST_PATH)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	manifest.kind = "terrain_army_female_ranged_recipe"
	manifest.source_fingerprints = _female_sources
	manifest.pages[0].png_md5 = FileAccess.get_md5(_destination(ATLAS_PATH))
	manifest.pages[0].resource_md5 = FileAccess.get_md5(_destination(ATLAS_RESOURCE_PATH))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("TERRAIN FEMALE RANGED PASS: ", _recipe.key, " frames=", frames.size(), " clips=", manifest.clips.size())
