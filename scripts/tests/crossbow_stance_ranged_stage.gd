extends "res://scripts/tools/publish_terrain_army_ranged.gd"
## Reuse production source/frame/pixel validation; prepare only staged files.
const SOURCE := "res://output/crossbow_stance_20260914/ranged"
const PREPARED := "res://output/crossbow_stance_20260914/ranged_publish"

func _initialize() -> void:
	var sources := Reader.fingerprints()
	var base_md5 := FileAccess.get_md5(Reader.BASE_MANIFEST)
	var manifests := {}
	for weapon: String in Reader.WEAPONS:
		var directory := SOURCE + "/" + weapon + "/"
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory + "manifest.json"))
		assert(not Reader.validate_batches(weapon, [manifest], directory).is_empty())
		assert(manifest.batch.first == 0 and manifest.batch.count == Reader.FRAME_COUNT and manifest.batch.recipe_complete)
		assert(manifest.source_fingerprints == sources and manifest.source_manifest_md5 == base_md5)
		assert(_lossless(manifest), "Decode and compare actual PNG/RES bytes before preparing publication")
		manifests[weapon] = manifest
	for weapon: String in Reader.WEAPONS:
		var directory := PREPARED + "/" + weapon + "/"
		assert(not DirAccess.dir_exists_absolute(directory), "Fresh staging only")
		assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK)
		for filename: String in ["page_000.png", "page_000.res"]:
			var source := SOURCE + "/" + weapon + "/" + filename
			assert(DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(directory + filename)) == OK)
			assert(FileAccess.get_md5(source) == FileAccess.get_md5(directory + filename))
		var manifest: Dictionary = manifests[weapon].duplicate(true)
		manifest.pages[0].path = directory + "page_000.png"
		manifest.pages[0].resource_path = directory + "page_000.res"
		assert(not Reader.validate_batches(weapon, [manifest], directory).is_empty() and _lossless(manifest))
		manifest.pages[0].path = Reader.ROOT + "/" + weapon + "/page_000.png"
		manifest.pages[0].resource_path = Reader.ROOT + "/" + weapon + "/page_000.res"
		assert(_write_json(directory + "manifest.json", manifest))
	assert(sources == Reader.fingerprints() and base_md5 == FileAccess.get_md5(Reader.BASE_MANIFEST))
	print("CROSSBOW STANCE RANGED STAGING PASS: 1168 frames; source, appearance, timings and lossless pixels; formal files not modified")
	quit(0)
