extends "res://scripts/tools/bake_terrain_army_soldier.gd"
## One female standard-infantry recipe, using the original baker/projection.

func _initialize() -> void:
	_started_usec = Time.get_ticks_usec()
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1 or not arguments[0].begins_with("--output=res://output/"):
		push_error("Female bake requires one fresh --output=res://output/... directory")
		quit(2)
		return
	var output := arguments[0].trim_prefix("--output=").simplify_path().trim_suffix("/")
	if output == "res://output" or DirAccess.dir_exists_absolute(output):
		push_error("Female bake output must be a new named staging directory")
		quit(2)
		return
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	var appearance: Dictionary = base.appearance.duplicate(true)
	appearance.body = 1.0 # Manifest dictionaries use JSON numeric types.
	appearance.parts.hair = HumanCharacter3DEditor.default_appearance(1).parts.hair
	_recipe = RecipePlan.build(PackedStringArray([
		"--recipe-mask=31", "--recipe-output=" + output, "--recipe-clips=all",
		"--recipe-directions=all", "--recipe-first=0", "--recipe-count=128"
	]), CLIPS, DIRECTIONS, appearance)
	assert(_recipe.ok and HumanCharacter3DEditor.valid_appearance(appearance))
	# One complete shared page also enters the original MultiMesh batch path.
	_recipe.count = _recipe.recipe_total
	_recipe.selection_complete = true
	_recipe.recipe_complete = true
	_recipe.source_fingerprints = RecipePlan.fingerprints()
	_source_fingerprints = _recipe.source_fingerprints.duplicate()
	_source_fingerprints[get_script().resource_path] = FileAccess.get_md5(get_script().resource_path)
	_base_manifest = {} # Restore through _recipe; never overwrite the male base.
	call_deferred("_run")

func _write_recipe_manifest(atlas: Image, frames: Array[Dictionary]) -> void:
	super._write_recipe_manifest(atlas, frames)
	var path := _destination(MANIFEST_PATH)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(_source_fingerprints[get_script().resource_path] == FileAccess.get_md5(get_script().resource_path))
	manifest.kind = "terrain_army_female_recipe"
	manifest.recipe_key = "standard_female_v1"
	manifest.source_fingerprints = _source_fingerprints
	manifest.pages[0].png_md5 = FileAccess.get_md5(_destination(ATLAS_PATH))
	manifest.pages[0].resource_md5 = FileAccess.get_md5(_destination(ATLAS_RESOURCE_PATH))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("TERRAIN FEMALE RECIPE PASS: body=1 frames=", frames.size(), " clips=", manifest.clips.size())
