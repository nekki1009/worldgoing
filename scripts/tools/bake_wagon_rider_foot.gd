extends "res://scripts/tools/bake_terrain_army_soldier.gd"
## Fixed cloth male/female foot poses, using the unchanged original GPU baker.
const RiderRecipe = preload("res://scripts/terrain_lab/site_wagon_rider_recipe.gd")
const FootAtlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
var _body := 0

func _initialize() -> void:
	_started_usec = Time.get_ticks_usec()
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 2 or arguments[0] not in ["--body=0", "--body=1"] or not (arguments[1].begins_with("--output=res://output/") or arguments[1].begins_with("--publish=res://output/")):
		push_error("Foot bake requires --body=0|1 and --output=res://output/<fresh-directory> or --publish=res://output/<staging>")
		quit(2)
		return
	_body = int(arguments[0].trim_prefix("--body="))
	if arguments[1].begins_with("--publish="):
		_publish(arguments[1].trim_prefix("--publish=").simplify_path().trim_suffix("/"))
		return
	var output := arguments[1].trim_prefix("--output=").simplify_path().trim_suffix("/")
	if not output.begins_with("res://output/") or DirAccess.dir_exists_absolute(output):
		push_error("Foot bake must use a new named staging directory")
		quit(2)
		return
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_recipe = RecipePlan.build(PackedStringArray(["--recipe-mask=28", "--recipe-output=" + output,
		"--recipe-clips=all", "--recipe-directions=all", "--recipe-first=0", "--recipe-count=128"]), CLIPS, DIRECTIONS, base.appearance)
	assert(_recipe.ok and HumanCharacter3DEditor.valid_appearance(RiderRecipe.appearance(_body)))
	_recipe.appearance = HumanCharacter3DEditor.EquipmentDye.geometry_appearance(RiderRecipe.appearance(_body))
	_recipe.count = _recipe.recipe_total
	_recipe.selection_complete = true
	_recipe.recipe_complete = true
	_recipe.source_fingerprints = RecipePlan.fingerprints()
	_source_fingerprints = _recipe.source_fingerprints.duplicate()
	for path: String in [get_script().resource_path, "res://scripts/terrain_lab/site_wagon_rider_recipe.gd"]:
		_source_fingerprints[path] = FileAccess.get_md5(path)
	_base_manifest = {} # Only the new staging recipe is written, never the baseline.
	_run.call_deferred()

func _publish(staging: String) -> void:
	var destination := FootAtlas.WAGON_FOOT_ROOT + ("/male" if _body == 0 else "/female")
	if not staging.begins_with("res://output/") or not DirAccess.dir_exists_absolute(staging) or DirAccess.dir_exists_absolute(destination):
		push_error("Foot publication needs existing named staging and an absent fixed destination; no overwrite")
		quit(2)
		return
	var sources := RecipePlan.fingerprints()
	for path: String in [get_script().resource_path, "res://scripts/terrain_lab/site_wagon_rider_recipe.gd"]:
		sources[path] = FileAccess.get_md5(path)
	var appearance := HumanCharacter3DEditor.EquipmentDye.geometry_appearance(RiderRecipe.appearance(_body))
	if FootAtlas._single_page_recipe(appearance, staging, "terrain_army_wagon_rider_foot", sources, 28).is_empty():
		push_error("Staged fixed foot atlas failed complete runtime/source validation; nothing published")
		quit(3)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(staging + "/manifest.json"))
	var page: Dictionary = manifest.pages[0]
	var pixels := Image.load_from_file(page.path)
	var texture := ResourceLoader.load(page.resource_path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	assert(pixels != null and texture != null and pixels.get_data() == texture.get_image().get_data())
	assert(_pixel_digest(pixels) == str(manifest.metrics.pixel_sha256))
	assert(DirAccess.make_dir_recursive_absolute(destination) == OK)
	for field: String in ["path", "resource_path"]:
		var original := str(page[field])
		var target := destination + ("/page_000.png" if field == "path" else "/page_000.res")
		assert(DirAccess.copy_absolute(original, target) == OK and FileAccess.get_md5(original) == FileAccess.get_md5(target))
		page[field] = target
	var file := FileAccess.open(destination + "/manifest.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	FootAtlas.refresh_female_sources()
	assert(FootAtlas.supports(RiderRecipe.appearance(_body)) and not FootAtlas.wagon_foot_recipe(appearance).is_empty())
	print("WAGON RIDER FOOT PUBLICATION PASS body=", _body, " clips=", manifest.clips.size(), " frames=", manifest.frames.size(), " destination=", destination)
	quit(0)

func _process(_delta: float) -> bool:
	if Time.get_ticks_usec() - _started_usec > 160000000:
		push_error("Fixed wagon foot bake exceeded its 160-second deadline")
		quit(90)
	return false

func _write_recipe_manifest(atlas: Image, frames: Array[Dictionary]) -> void:
	super._write_recipe_manifest(atlas, frames)
	for path: String in _source_fingerprints:
		assert(_source_fingerprints[path] == FileAccess.get_md5(path), "Foot recipe source changed while baking")
	var manifest_path := _destination(MANIFEST_PATH)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	manifest.kind = "terrain_army_wagon_rider_foot"
	manifest.recipe_key = "wagon_rider_foot_v1/" + ("male" if _body == 0 else "female")
	manifest.source_fingerprints = _source_fingerprints
	manifest.pages[0].png_md5 = FileAccess.get_md5(_destination(ATLAS_PATH))
	manifest.pages[0].resource_md5 = FileAccess.get_md5(_destination(ATLAS_RESOURCE_PATH))
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	assert(not FootAtlas._single_page_recipe(_recipe.appearance, str(_recipe.output), "terrain_army_wagon_rider_foot", _source_fingerprints, 28).is_empty(), "Complete fixed foot publication must pass the runtime reader")
	print("WAGON RIDER FOOT PASS body=", _body, " clips=", manifest.clips.size(), " frames=", frames.size(), " output=", _recipe.output)
