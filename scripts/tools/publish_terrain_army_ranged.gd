extends SceneTree
## Publish exactly two complete, lossless ranged recipes; never replace a bundle.
const Reader = preload("res://scripts/terrain_lab/terrain_army_ranged_atlas.gd")
const WORK := "res://output/site_ranged_20260914/atlas"
const DESTINATION := Reader.ROOT

func _initialize() -> void:
	if OS.get_cmdline_user_args() == PackedStringArray(["--validate-published-ranged"]):
		if _validate_published():
			print("TERRAIN ARMY RANGED PUBLISHED VALIDATION PASS: read-only; 2 exact canonical recipes / 1168 samples; current sources, decoded PNG/RES bytes, SHA-256 and runtime admission -> ", DESTINATION)
			quit(0)
		return
	if OS.get_cmdline_user_args() != PackedStringArray(["--publish-complete-ranged"]):
		_fail("Explicit --publish-complete-ranged or read-only --validate-published-ranged is required")
		return
	var destination := ProjectSettings.globalize_path(DESTINATION)
	if DirAccess.dir_exists_absolute(destination) or FileAccess.file_exists(destination):
		_fail("Formal ranged v1 already exists; nothing was overwritten")
		return
	var sources := Reader.fingerprints()
	var base_md5 := FileAccess.get_md5(Reader.BASE_MANIFEST)
	if sources.is_empty() or base_md5.length() != 32:
		_fail("Original and ranged sources are unavailable")
		return
	var manifests := {}
	var source_hashes := {}
	for weapon: String in Reader.WEAPONS:
		var directory := WORK + "/" + weapon + "/"
		var path := directory + "manifest.json"
		if not FileAccess.file_exists(path):
			_fail("Missing completed source manifest: " + path)
			return
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary or Reader.validate_batches(weapon, [parsed], directory).is_empty():
			_fail("Source recipe is incomplete or does not match its exact appearance/timings: " + weapon)
			return
		if parsed.source_fingerprints != sources or parsed.source_manifest_md5 != base_md5 or parsed.batch.first != 0 or parsed.batch.count != Reader.FRAME_COUNT or parsed.batch.recipe_complete != true:
			_fail("Source recipe is partial or has mixed source fingerprints: " + weapon)
			return
		if parsed.pages[0].path != directory + "page_000.png" or parsed.pages[0].resource_path != directory + "page_000.res" or not _lossless(parsed):
			_fail("Source PNG/RES bytes, dimensions or recorded pixel hashes do not agree: " + weapon)
			return
		manifests[weapon] = parsed
		for filename: String in ["manifest.json", "page_000.png", "page_000.res"]:
			source_hashes[directory + filename] = FileAccess.get_md5(directory + filename)
	# All source admission and actual decoded-pixel checks precede any copy.
	var staging := "res://output/site_ranged_20260914/publish_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var staging_absolute := ProjectSettings.globalize_path(staging)
	if DirAccess.dir_exists_absolute(staging_absolute) or DirAccess.make_dir_recursive_absolute(staging_absolute) != OK:
		_fail("Cannot create a fresh publication staging directory")
		return
	for weapon: String in Reader.WEAPONS:
		var directory := staging + "/" + weapon + "/"
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
			_fail("Cannot create publication recipe staging; partial output retained")
			return
		for filename: String in ["page_000.png", "page_000.res"]:
			var source := WORK + "/" + weapon + "/" + filename
			var target := directory + filename
			if FileAccess.get_md5(source) != source_hashes[source] or DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(target)) != OK or FileAccess.get_md5(target) != source_hashes[source]:
				_fail("Ranged asset copy is not byte-identical; no formal directory published")
				return
		var staged: Dictionary = manifests[weapon].duplicate(true)
		staged.pages[0].path = directory + "page_000.png"
		staged.pages[0].resource_path = directory + "page_000.res"
		if Reader.validate_batches(weapon, [staged], directory).is_empty():
			_fail("Copied recipe failed complete frame/source validation")
			return
		staged.pages[0].path = DESTINATION + "/" + weapon + "/page_000.png"
		staged.pages[0].resource_path = DESTINATION + "/" + weapon + "/page_000.res"
		if not _write_json(directory + "manifest.json", staged):
			return
	# Source manifests are read-only: retain original staging paths and evidence.
	for path: String in source_hashes:
		if FileAccess.get_md5(path) != source_hashes[path]:
			_fail("Source output changed during publication; no formal directory published")
			return
	if sources != Reader.fingerprints() or base_md5 != FileAccess.get_md5(Reader.BASE_MANIFEST):
		_fail("Original sources changed during publication; no formal directory published")
		return
	var expected_parent := ProjectSettings.globalize_path("res://assets/characters/terrain_lab_army/standard_soldier/ranged").replace("\\", "/").trim_suffix("/")
	var allowed_staging := ProjectSettings.globalize_path("res://output/site_ranged_20260914").replace("\\", "/").trim_suffix("/") + "/publish_"
	if destination.replace("\\", "/") != expected_parent + "/v1" or not staging_absolute.replace("\\", "/").begins_with(allowed_staging):
		_fail("Resolved publication move paths escaped their exact task directories")
		return
	if DirAccess.dir_exists_absolute(destination) or FileAccess.file_exists(destination):
		_fail("Formal destination appeared during publication; staging retained without replacement")
		return
	var mkdir_error := DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	if mkdir_error != OK:
		_fail("Formal parent creation failed: Godot Error %d (%s); staging retained: %s" % [mkdir_error, error_string(mkdir_error), staging_absolute])
		return
	var rename_error := DirAccess.rename_absolute(staging_absolute, destination)
	if rename_error != OK:
		_fail("Atomic publication rename failed: Godot Error %d (%s); staging retained without replacement: %s -> %s" % [rename_error, error_string(rename_error), staging_absolute, destination])
		return
	if not _validate_published():
		return
	print("TERRAIN ARMY RANGED PUBLISH PASS: 2 exact recipes / 1168 samples; decoded PNG/RES bytes and SHA-256 verified; source manifests unchanged -> ", DESTINATION)
	quit(0)

func _validate_published() -> bool:
	# No directory creation, copy, move or metadata write in this validation path.
	var sources := Reader.fingerprints()
	var base_md5 := FileAccess.get_md5(Reader.BASE_MANIFEST)
	if sources.is_empty() or base_md5.length() != 32:
		_fail("Published validation cannot read current original and ranged sources")
		return false
	Reader.set_root_path(DESTINATION)
	var hashes := {}
	for weapon: String in Reader.WEAPONS:
		var directory := DESTINATION + "/" + weapon + "/"
		for filename: String in ["manifest.json", "page_000.png", "page_000.res"]:
			var path := directory + filename
			if not FileAccess.file_exists(path):
				_fail("Missing canonical published file: " + path)
				return false
			hashes[path] = FileAccess.get_md5(path)
		var published: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory + "manifest.json"))
		if not published is Dictionary or Reader.validate_batches(weapon, [published], directory).is_empty():
			_fail("Published recipe failed exact appearance, all frames or source validation: " + weapon)
			return false
		if published.get("source_manifest") != Reader.BASE_MANIFEST or published.source_fingerprints != sources or published.source_manifest_md5 != base_md5 or published.batch.first != 0 or published.batch.count != Reader.FRAME_COUNT or published.batch.get("recipe_complete") != true:
			_fail("Published recipe is incomplete or does not match current canonical sources: " + weapon)
			return false
		if published.pages[0].path != directory + "page_000.png" or published.pages[0].resource_path != directory + "page_000.res" or not _lossless(published):
			_fail("Published canonical paths, PNG/RES bytes, dimensions or pixel hashes disagree: " + weapon)
			return false
		var admitted := Reader.recipe(published.appearance)
		if admitted.is_empty() or admitted.sequences.size() != 76:
			_fail("Published recipe failed the actual runtime admission route: " + weapon)
			return false
	for path: String in hashes:
		if FileAccess.get_md5(path) != hashes[path]:
			_fail("A published file changed during read-only validation: " + path)
			return false
	if sources != Reader.fingerprints() or base_md5 != FileAccess.get_md5(Reader.BASE_MANIFEST):
		_fail("An original source changed during read-only validation")
		return false
	return true

func _lossless(manifest: Dictionary) -> bool:
	if not manifest.get("metrics") is Dictionary or not manifest.metrics.has_all(["decoded_rgba_bytes", "png_bytes", "resource_bytes", "pixel_sha256", "png_decoded_sha256", "resource_decoded_sha256"]):
		return false
	for key: String in ["decoded_rgba_bytes", "png_bytes", "resource_bytes"]:
		if not Reader._integer(manifest.metrics[key], 1, 2147483647):
			return false
	var page: Dictionary = manifest.pages[0]
	var png := Image.load_from_file(str(page.path))
	var texture := ResourceLoader.load(str(page.resource_path), "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	if png == null or texture == null:
		return false
	var restored := texture.get_image()
	var expected := Vector2i(int(page.width), int(page.height))
	if restored == null or png.get_size() != expected or restored.get_size() != expected or png.get_format() != Image.FORMAT_RGBA8 or restored.get_format() != Image.FORMAT_RGBA8:
		return false
	var png_bytes := png.get_data()
	if png_bytes != restored.get_data() or png_bytes.size() != int(manifest.metrics.decoded_rgba_bytes):
		return false
	var digest := _pixel_digest(png_bytes)
	if digest != str(manifest.metrics.pixel_sha256) or digest != str(manifest.metrics.png_decoded_sha256) or digest != str(manifest.metrics.resource_decoded_sha256):
		return false
	for pair: Array in [[str(page.path), "png_bytes"], [str(page.resource_path), "resource_bytes"]]:
		var file := FileAccess.open(pair[0], FileAccess.READ)
		if file == null:
			return false
		var length := file.get_length()
		file.close()
		if length != int(manifest.metrics[pair[1]]):
			return false
	return true

func _pixel_digest(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	assert(hashing.start(HashingContext.HASH_SHA256) == OK)
	assert(hashing.update(bytes) == OK)
	return hashing.finish().hex_encode()

func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Cannot write publication manifest: " + path)
		return false
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
	return true

func _fail(message: String) -> void:
	push_error(message)
	quit(2)
