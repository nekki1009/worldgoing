extends "res://scripts/tools/publish_terrain_army_ranged.gd"
const DyeAtlas = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() >= 1)
	var published := args[0] == "--published"
	var directory := Reader.ROOT if published else args[0].trim_prefix("--stage=")
	assert(Reader.set_root_path(directory))
	var count := 0
	for row: Dictionary in Reader.Materials.OPTIONS:
		if row.id == "none" or (args.size() > 1 and row.id not in args.slice(1)): continue
		var folder: String = directory + "/" + row.id + "/"
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "manifest.json"))
		assert(not Reader.validate_batches(row.id, [manifest], folder).is_empty(), row.id)
		assert(manifest.batch.recipe_complete and manifest.batch.count == 584 and manifest.batch.first == 0)
		assert(_lossless(manifest), row.id + " lossless PNG/RES")
		assert(not Reader.recipe(manifest.appearance).is_empty(), row.id)
		if published:
			assert(not DyeAtlas.entry(manifest.appearance).is_empty(), row.id + " mask")
			var masked: Dictionary = manifest.appearance.duplicate(true)
			masked.equipment_dyes = {"armor": "396fbbff", "boots": "26384eff"}
			assert(not Reader.recipe(masked).is_empty())
		count += 1
		print("WEAPON_MATERIAL_NPC_VALIDATED ", row.id)
	assert(count == (44 if args.size() == 1 else args.size() - 1))
	print("WEAPON_MATERIAL_NPC_PUBLICATION_PASS recipes=",count," actual decoded PNG/RES equality, complete frame/timing/source/appearance admission; published=",published)
	quit(0)
