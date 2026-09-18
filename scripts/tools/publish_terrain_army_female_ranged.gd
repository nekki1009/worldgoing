extends SceneTree
## Additive, complete female bow/crossbow publication with lossless preflight.
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const WORK := "res://output/ranged_behavior_fix_20260918/female"

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	assert(arguments == PackedStringArray(["--publish"]) or arguments == PackedStringArray(["--validate"]))
	var publishing := arguments[0] == "--publish"
	var checked := {}
	for weapon: String in Atlas.RangedAtlas.WEAPONS:
		var directory := WORK + "/atlases/" + weapon if publishing else Atlas.FEMALE_RANGED_ROOT + "/" + weapon
		var dye_path := WORK + "/masks/" + weapon + ".json" if publishing else directory + "/dye.json"
		checked[weapon] = _check(weapon, directory, dye_path)
	if publishing:
		assert(not DirAccess.dir_exists_absolute(Atlas.FEMALE_RANGED_ROOT), "Additive destination must not exist")
		var staged := WORK + "/publish"
		assert(not DirAccess.dir_exists_absolute(staged), "Use a fresh publication staging directory")
		for weapon: String in Atlas.RangedAtlas.WEAPONS:
			var record: Dictionary = checked[weapon]
			var target := staged + "/" + weapon
			var destination := Atlas.FEMALE_RANGED_ROOT + "/" + weapon
			assert(DirAccess.make_dir_recursive_absolute(target) == OK)
			for pair: Array in [[record.manifest.pages[0].path, "page_000.png"], [record.manifest.pages[0].resource_path, "page_000.res"], [record.dye.mask_path, "dye.png"]]:
				assert(DirAccess.copy_absolute(pair[0], target + "/" + pair[1]) == OK)
				assert(FileAccess.get_md5(pair[0]) == FileAccess.get_md5(target + "/" + pair[1]))
			var manifest: Dictionary = record.manifest.duplicate(true)
			manifest.pages[0].path = destination + "/page_000.png"
			manifest.pages[0].resource_path = destination + "/page_000.res"
			_write(target + "/manifest.json", manifest)
			var dye: Dictionary = record.dye.duplicate(true)
			dye.source_manifest = destination + "/manifest.json"
			dye.source_manifest_md5 = FileAccess.get_md5(target + "/manifest.json")
			dye.mask_path = destination + "/dye.png"
			_write(target + "/dye.json", dye)
		# No source changes or overwritten formal output can enter this rename.
		for weapon: String in Atlas.RangedAtlas.WEAPONS:
			assert(_check(weapon, WORK + "/atlases/" + weapon, WORK + "/masks/" + weapon + ".json") == checked[weapon])
		assert(DirAccess.make_dir_recursive_absolute(Atlas.FEMALE_RANGED_ROOT.get_base_dir()) == OK)
		assert(not DirAccess.dir_exists_absolute(Atlas.FEMALE_RANGED_ROOT))
		assert(DirAccess.rename_absolute(staged, Atlas.FEMALE_RANGED_ROOT) == OK)
	Atlas.refresh_female_sources()
	for weapon: String in Atlas.RangedAtlas.WEAPONS:
		var directory := Atlas.FEMALE_RANGED_ROOT + "/" + weapon
		_check(weapon, directory, directory + "/dye.json")
		var appearance: Dictionary = Atlas.female_ranged_plan(weapon).appearance
		appearance.equipment_dyes = {"armor": "76a92dff", "outfit": "f4ca78ff", "boots": "8453b1ff"}
		assert(Atlas.supports(appearance) and not Atlas.dye_entry(appearance).is_empty())
		var recipe := Atlas.female_recipe(appearance)
		assert(recipe.sequences.size() == 80)
		for key: String in recipe.sequences:
			for frame: Dictionary in recipe.sequences[key]:
				assert(not Atlas.frame(appearance, str(frame.clip), str(frame.direction), float(frame.sample_time)).is_empty())
		for field: String in ["hair", "armor", "weapon", "shield"]:
			var rejected := appearance.duplicate(true)
			rejected.parts[field] = {"hair": "hair_female_02", "armor": "none", "weapon": "bow_01_wood", "shield": "shield_heater_01"}[field]
			assert(not Atlas.supports(rejected), "Unbaked female variant must remain rejected: " + field)
	print("FEMALE RANGED ASSETS PASS: 2 exact recipes / 1264 frames / 40 clips / 4 directions; lossless pages, complete dyes, runtime admission and rejection")
	quit()

func _check(weapon: String, directory: String, dye_path: String) -> Dictionary:
	var plan := Atlas.female_ranged_plan(weapon)
	assert(not plan.is_empty() and int(plan.recipe_total) == 632)
	assert(not Atlas._single_page_recipe(plan.appearance, directory, "terrain_army_female_ranged_recipe", Atlas.female_ranged_sources(), 29, plan).is_empty(), "All source fingerprints and frame metadata must match")
	var path := directory + "/manifest.json"
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var dye: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dye_path))
	assert(manifest.batch.recipe_complete and manifest.batch.count == 632 and manifest.batch.first == 0)
	assert(dye.schema_version == 1 and dye.slots == Atlas.DyeAtlas.Dye.SLOTS and dye.complete and dye.frame_count == 632 and dye.appearance == plan.appearance)
	assert(dye.source_fingerprints == Atlas.DyeAtlas.fingerprints() and dye.source_manifest == path and dye.source_manifest_md5 == FileAccess.get_md5(path))
	assert(dye.mask_md5 == FileAccess.get_md5(dye.mask_path))
	var page: Dictionary = manifest.pages[0]
	var png := Image.load_from_file(page.path)
	var texture := ResourceLoader.load(page.resource_path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	var mask := Image.load_from_file(dye.mask_path)
	assert(png != null and texture != null and mask != null)
	assert(png.get_size() == Vector2i(texture.get_size()) and png.get_size() == mask.get_size() and png.get_size() == Vector2i(int(page.width), int(page.height)))
	assert(png.get_format() == Image.FORMAT_RGBA8 and png.get_data() == texture.get_image().get_data())
	var hash := HashingContext.new()
	assert(hash.start(HashingContext.HASH_SHA256) == OK and hash.update(png.get_data()) == OK)
	assert(hash.finish().hex_encode() == manifest.metrics.pixel_sha256)
	var mask_bytes := mask.get_data()
	assert(mask.get_format() == Image.FORMAT_RGB8)
	var occupied := 0
	for index in range(0, mask_bytes.size(), 3):
		assert(mask_bytes[index] <= 5)
		if mask_bytes[index] > 0: occupied += 1
	assert(occupied > 0 and dye.width == page.width and dye.height == page.height)
	return {"manifest": manifest, "dye": dye}

func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
