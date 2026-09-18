extends SceneTree
## Additive publication only; never modifies the existing male catalog.
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const SOURCE := "res://output/terrain_army_gender_20260918/female_standard_retry"
const DYE := "res://output/terrain_army_gender_20260918/female_dye"

func _initialize() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE + "/manifest.json"))
	var mask: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DYE + ".json"))
	var sources := Atlas.Plan.fingerprints()
	sources[Atlas.FEMALE_BAKER] = FileAccess.get_md5(Atlas.FEMALE_BAKER)
	assert(manifest.source_fingerprints == sources and manifest.source_manifest_md5 == FileAccess.get_md5(Atlas.BASE_MANIFEST))
	assert(mask.complete and mask.frame_count == 584 and manifest.frames.size() == 584)
	assert(mask.source_fingerprints == Atlas.DyeAtlas.fingerprints() and mask.source_manifest_md5 == FileAccess.get_md5(SOURCE + "/manifest.json"))
	var page: Dictionary = manifest.pages[0]
	assert(FileAccess.get_md5(page.path) == page.png_md5 and FileAccess.get_md5(page.resource_path) == page.resource_md5 and FileAccess.get_md5(mask.mask_path) == mask.mask_md5)
	var png := Image.load_from_file(page.path)
	var texture := load(page.resource_path) as Texture2D
	var dye := Image.load_from_file(mask.mask_path)
	assert(png != null and texture != null and dye != null and png.get_data() == texture.get_image().get_data() and png.get_size() == dye.get_size())
	assert(not DirAccess.dir_exists_absolute(Atlas.FEMALE_ROOT), "New additive destination required")
	assert(DirAccess.make_dir_recursive_absolute(Atlas.FEMALE_ROOT) == OK)
	for pair: Array in [[page.path, "page_000.png"], [page.resource_path, "page_000.res"], [mask.mask_path, "dye.png"]]:
		var destination := Atlas.FEMALE_ROOT + "/" + str(pair[1])
		assert(DirAccess.copy_absolute(pair[0], destination) == OK)
		assert(FileAccess.get_md5(pair[0]) == FileAccess.get_md5(destination))
	page.path = Atlas.FEMALE_ROOT + "/page_000.png"
	page.resource_path = Atlas.FEMALE_ROOT + "/page_000.res"
	_write(Atlas.FEMALE_ROOT + "/manifest.json", manifest)
	mask.source_manifest = Atlas.FEMALE_ROOT + "/manifest.json"
	mask.source_manifest_md5 = FileAccess.get_md5(mask.source_manifest)
	mask.mask_path = Atlas.FEMALE_ROOT + "/dye.png"
	_write(Atlas.FEMALE_ROOT + "/dye.json", mask)
	assert(Atlas.supports(Atlas.female_appearance()), "Published female recipe must be admitted")
	assert(not Atlas.dye_entry(Atlas.female_appearance()).is_empty(), "Published female dye must be admitted")
	print("FEMALE PUBLICATION PASS: 584 frames / 19 clips / 4 directions, lossless page and complete companion")
	quit()

func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
