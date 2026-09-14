extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "save-size-fixture")
	var path := "res://.godot-temp/site_resources_contract/save_size.json"
	assert(SiteStore.save(data, path).ok)
	var original := FileAccess.get_sha256(path)
	# Unknown sparse test payload isolates encoded byte size, not item quantity.
	data.site["size_fixture"] = "物".repeat(floori(float(SiteStore.MAX_BYTES) / 3.0))
	var result := SiteStore.save(data, path)
	assert(not result.ok and result.code == "SAVE_TOO_LARGE")
	assert(FileAccess.get_sha256(path) == original, "Oversize must fail before touching the existing file")
	assert(not FileAccess.file_exists(path + ".tmp"))
	assert(SiteStore.load_site(path).ok)
	data.site.erase("size_fixture")
	assert(SiteStore.save(data, path).ok and SiteStore.load_site(path).ok)
	print("SITE SAVE SIZE PASS: final UTF-8 envelope checked before writes, oversize refusal preserves readable old save, no loot deletion; not a loot performance benchmark")
	quit(0)
