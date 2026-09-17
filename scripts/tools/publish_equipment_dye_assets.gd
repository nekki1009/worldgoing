extends "res://scripts/tools/publish_terrain_army_ranged.gd"
## Reuses original ranged admission/lossless checks. Every replacement is backed
## up first; partial generations and changed sources are never admitted.
const DyeAtlas = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const Plan = preload("res://scripts/tools/terrain_army_recipe_bake_plan.gd")
var stage_root := "res://output/equipment_palette_policy_20260914"
var prepare_only := false
const BASE := "res://assets/characters/terrain_lab_army/standard_soldier"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() in [1, 2, 3] and args[0] in ["--base", "--ranged", "--masks", "--weapons", "--weapon-masks"])
	if args.size() == 3:
		assert(args[2].begins_with("--stage="))
		stage_root = args[2].trim_prefix("--stage=").simplify_path().trim_suffix("/")
		assert(stage_root.begins_with("res://output/") and stage_root != "res://output")
	var phase := args[0].trim_prefix("--")
	if args.size() >= 2:
		if args[1] == "--prepare": prepare_only = true
		else:
			assert(args[1].begins_with("--attempt=") and args[1].trim_prefix("--attempt=").is_valid_identifier())
			phase += "_" + args[1].trim_prefix("--attempt=")
	var sources := Plan.fingerprints()
	var pairs := {}
	if args[0] == "--base":
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(stage_root + "/base/standard_soldier_atlas.json"))
		var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "/standard_soldier_atlas.json"))
		assert(manifest.source_fingerprints == sources and manifest.clips == original.clips and manifest.appearance == original.appearance)
		assert(manifest.frames.size() == original.frames.size() and manifest.frames.size() == 1080)
		for index in range(original.frames.size()):
			for field in ["clip", "direction", "frame", "duration", "sample_time", "collision_index"]:
				assert(manifest.frames[index][field] == original.frames[index][field], "Base timing/index drift: " + field)
		var png := Image.load_from_file(stage_root + "/base/standard_soldier_atlas.png")
		var resource := load(stage_root + "/base/standard_soldier_atlas.res") as Texture2D
		assert(png.get_data() == resource.get_image().get_data())
		var collision := FileAccess.open_compressed(stage_root + "/base/standard_soldier_collision.bin", FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		assert(collision != null and collision.get_var(false).size() == manifest.frames.size())
		collision.close()
		for filename: String in ["standard_soldier_atlas.png", "standard_soldier_atlas.res", "standard_soldier_atlas.json", "standard_soldier_collision.bin"]:
			pairs[stage_root + "/base/" + filename] = BASE + "/" + filename
	elif args[0] in ["--ranged", "--weapons"]:
		var weapons: Array = Reader.WEAPONS.duplicate()
		if args[0] == "--weapons":
			weapons.clear()
			for row: Dictionary in Reader.Materials.OPTIONS:
				if row.id != "none": weapons.append(row.id)
		for weapon: String in weapons:
			var directory := stage_root + "/ranged/" + weapon + "/"
			var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory + "manifest.json"))
			assert(not Reader.validate_batches(weapon, [manifest], directory).is_empty() and _lossless(manifest))
			assert(manifest.batch.recipe_complete and manifest.batch.count == Reader.FRAME_COUNT and manifest.batch.first == 0)
			for filename: String in ["page_000.png", "page_000.res"]:
				pairs[directory + filename] = Reader.ROOT + "/" + weapon + "/" + filename
			manifest.pages[0].path = Reader.ROOT + "/" + weapon + "/page_000.png"
			manifest.pages[0].resource_path = Reader.ROOT + "/" + weapon + "/page_000.res"
			assert(_write_json(directory + "publish.json", manifest))
			pairs[directory + "publish.json"] = Reader.ROOT + "/" + weapon + "/manifest.json"
	else:
		var mask_keys: Array = ["base", "bow_01", "crossbow_01"]
		if args[0] == "--weapon-masks":
			mask_keys = ["base"]
			for row: Dictionary in Reader.Materials.OPTIONS:
				if row.id != "none": mask_keys.append(row.id)
		for key: String in mask_keys:
			var path := stage_root + "/masks/" + key
			var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path + ".json"))
			assert(manifest.complete and manifest.source_fingerprints == DyeAtlas.fingerprints())
			assert(manifest.slots == DyeAtlas.Dye.SLOTS and manifest.source_manifest_md5 == FileAccess.get_md5(manifest.source_manifest))
			var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest.source_manifest))
			assert(manifest.frame_count == base.frames.size() and manifest.appearance == base.appearance)
			assert(manifest.mask_md5 == FileAccess.get_md5(path + ".png"))
			var pixels := Image.load_from_file(path + ".png")
			assert(pixels.get_width() == int(manifest.width) and pixels.get_height() == int(manifest.height))
			pixels.convert(Image.FORMAT_RGB8)
			var bytes := pixels.get_data()
			for index in range(0, bytes.size(), 3): assert(bytes[index] <= 5, "Invalid categorical dye slot")
			manifest.mask_path = DyeAtlas.ROOT + "/" + key + ".png"
			assert(_write_json(path + "_publish.json", manifest))
			pairs[path + ".png"] = manifest.mask_path
			pairs[path + "_publish.json"] = DyeAtlas.ROOT + "/" + key + ".json"
	assert(sources == Plan.fingerprints(), "Source changed during publication preflight")
	if not _publish(pairs, phase): return
	print("EQUIPMENT DYE ", "PREPARATION PASS (NO PUBLICATION)" if prepare_only else "PUBLICATION PASS", ": ", args[0], " files=", pairs.size(), " old assets backed up; original guards retained")
	quit()

func _publish(pairs: Dictionary, phase: String) -> bool:
	var backup := stage_root + "/baseline/" + phase + "/"
	assert(not DirAccess.dir_exists_absolute(backup), "Refuse to replace an existing recoverable baseline")
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(backup)) == OK)
	var originals := {}
	var digests := {}
	for source: String in pairs:
		var destination: String = pairs[source]
		assert(destination.begins_with(BASE + "/") and source.begins_with(stage_root + "/"))
		digests[source] = FileAccess.get_md5(source)
		assert(str(digests[source]).length() == 32)
		if FileAccess.file_exists(destination):
			var copy := backup + destination.trim_prefix(BASE + "/")
			assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(copy.get_base_dir())) == OK)
			assert(DirAccess.copy_absolute(ProjectSettings.globalize_path(destination), ProjectSettings.globalize_path(copy)) == OK)
			assert(FileAccess.get_md5(copy) == FileAccess.get_md5(destination))
			originals[destination] = copy
	assert(_write_json(backup + "recovery.json", {"originals": originals, "new_sources": pairs, "source_md5": digests}))
	for source: String in pairs:
		assert(FileAccess.get_md5(source) == digests[source])
		var destination: String = pairs[source]
		if originals.has(destination): assert(FileAccess.get_md5(destination) == FileAccess.get_md5(originals[destination]))
	# Some Dropbox files reject Godot's truncate/copy while native Copy-Item
	# succeeds after this process exits. Keep full preflight and original backups.
	if prepare_only: return true
	for source: String in pairs:
		var destination: String = pairs[source]
		assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir())) == OK)
		if FileAccess.get_md5(destination) == digests[source]: continue
		var copied := DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(destination))
		if copied != OK or FileAccess.get_md5(destination) != digests[source]:
			var recovered := true
			for original: String in originals:
				if FileAccess.get_md5(original) == FileAccess.get_md5(originals[original]): continue
				var restored := DirAccess.copy_absolute(ProjectSettings.globalize_path(originals[original]), ProjectSettings.globalize_path(original))
				if restored != OK or FileAccess.get_md5(original) != FileAccess.get_md5(originals[original]): recovered = false
			push_error("Publication copy failed; restored=" + str(recovered) + "; retained recovery manifest: " + backup)
			quit(1)
			return false
	return true
