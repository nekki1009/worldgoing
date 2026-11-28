extends SceneTree
## Probe (2026-11-27, 開局速度 B): the stages of one Site build after its 10,404 samples (RegionTerrainAdapter.build).
## Loads the shipped demo A package; for a few authored and plain Sites: the whole build, the natural build (no author
## layers) and each later stage run again on a built copy. Output: BUILD_STAGE lines and BUILD_STAGE_DONE.
const PACKAGE := "res://assets/scenarios/demo_a/demo_a.json"
const Adapter = preload("res://scripts/region_lab/region_terrain_adapter.gd")

func _initialize() -> void:
	_run.call_deferred()

func _ms(from: int) -> float:
	return float(Time.get_ticks_usec() - from) / 1000.0

func _run() -> void:
	var source := RegionData.new()
	var loaded: Dictionary = source.load_manifest(PACKAGE)
	if not loaded.get("ok", false):
		print("BUILD_STAGE load failed %s" % str(loaded))
		print("BUILD_STAGE_DONE")
		quit(1)
		return
	var sites: Array = []
	for pair: Variant in source.author_initial_context().get("expected_initial_sites", []).slice(0, 3): sites.append(Vector2i(int(pair[0]), int(pair[1])))
	sites.append(sites[0] + Vector2i(0, 5)) # a plain neighbourhood Site
	sites.append(sites[0] + Vector2i(7, 0))
	for site: Vector2i in sites:
		var authored: bool = not source.author_static_for(site).is_empty()
		var t := Time.get_ticks_usec()
		var built: Dictionary = Adapter.build(source, site)
		var whole := _ms(t)
		if not built.get("ok", false):
			print("BUILD_STAGE site %s refused %s" % [str(site), str(built.get("code", ""))])
			continue
		t = Time.get_ticks_usec()
		var natural: Dictionary = Adapter.build(source, site, false)
		var natural_ms := _ms(t)
		var data: TerrainData = natural.data
		var rows := {}
		t = Time.get_ticks_usec()
		var rng := RandomNumberGenerator.new()
		rng.seed = data.seed_value
		TerrainGenerator._connect_platforms(data, rng)
		rows["connect_platforms"] = _ms(t)
		t = Time.get_ticks_usec()
		var cover: Dictionary = source.site_resource_cover(site)
		rows["resource_cover"] = _ms(t)
		t = Time.get_ticks_usec()
		if bool(cover.get("enabled", false)): SiteEnvironment.populate_fixed_resources(data, cover.cover, site, natural.metadata.absolute_elevation_m)
		rows["populate_resources"] = _ms(t)
		t = Time.get_ticks_usec()
		data.fingerprint()
		rows["fingerprint"] = _ms(t)
		t = Time.get_ticks_usec()
		JSON.stringify(data.resource_base, "", true, true).sha256_text()
		rows["resource_fingerprint"] = _ms(t)
		var full: TerrainData = built.data
		if authored:
			t = Time.get_ticks_usec()
			source.apply_author_layers(full, site)
			rows["author_layers"] = _ms(t)
			t = Time.get_ticks_usec()
			SiteEnvironment.rebuild_indexes(full)
			rows["rebuild_indexes"] = _ms(t)
		t = Time.get_ticks_usec()
		SiteEnvironment._populate_soil_conditions(full, false)
		rows["soil"] = _ms(t)
		t = Time.get_ticks_usec()
		SiteEnvironment.restore_author_land(full)
		rows["restore_land"] = _ms(t)
		t = Time.get_ticks_usec()
		Adapter.author_environment_fingerprint(full)
		rows["environment_fingerprint"] = _ms(t)
		t = Time.get_ticks_usec()
		RegionRoute._fixed_base_copy(built)
		rows["memo_copy"] = _ms(t)
		var text := ""
		for key: String in rows: text += " %s %.0f," % [key, rows[key]]
		print("BUILD_STAGE site %s authored %s: whole %.0f ms, natural build %.0f ms |%s" % [str(site), str(authored), whole, natural_ms, text])
	print("BUILD_STAGE_DONE")
	quit(0)
