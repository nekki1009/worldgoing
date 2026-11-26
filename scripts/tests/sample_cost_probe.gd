extends SceneTree
## Probe (2026-11-27, 開局速度 B): where one Site build's 10,404 source samples spend their time (Adapter.build calls
## RegionData._sample_site_meters once per two-metre cell of the Site and its halo). Loads the shipped demo A package and
## times each layer of the sampler alone over the same positions, for a few authored Sites.
## Output: SAMPLE_COST lines and SAMPLE_COST_DONE.
const PACKAGE := "res://assets/scenarios/demo_a/demo_a.json"
const SIDE := 100

func _initialize() -> void:
	_run.call_deferred()

func _ms(from: int) -> float:
	return float(Time.get_ticks_usec() - from) / 1000.0

func _positions(site: Vector2i) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for y: int in range(-1, SIDE + 1):
		for x: int in range(-1, SIDE + 1):
			out.append(Vector2(site.x * 200.0 + x * 2.0 + 1.0, site.y * 200.0 + (SIDE - 1 - y) * 2.0 + 1.0))
	return out

func _run() -> void:
	var source := RegionData.new()
	var loaded: Dictionary = source.load_manifest(PACKAGE)
	if not loaded.get("ok", false):
		print("SAMPLE_COST load failed %s" % str(loaded))
		print("SAMPLE_COST_DONE")
		quit(1)
		return
	var sites: Array = source.author_initial_context().get("expected_initial_sites", [])
	for pair: Variant in sites.slice(0, 4):
		var site := Vector2i(int(pair[0]), int(pair[1]))
		var points := _positions(site)
		var t := Time.get_ticks_usec()
		var built: Dictionary = source.make_terrain_data(site.x, site.y)
		var build_ms := _ms(t)
		t = Time.get_ticks_usec()
		var cache := {}
		for p: Vector2 in points: source._sample_site_meters(p.x, p.y, cache)
		var site_ms := _ms(t)
		t = Time.get_ticks_usec()
		cache = {}
		for p: Vector2 in points: source._sample_meters(p.x, p.y, cache)
		var meters_ms := _ms(t)
		t = Time.get_ticks_usec()
		for p: Vector2 in points: source._tile_at(p.x, p.y)
		var tile_ms := _ms(t)
		var tile: Dictionary = source._tile_at(points[0].x, points[0].y)
		t = Time.get_ticks_usec()
		for p: Vector2 in points: source._fine_water_at(p.x, p.y, tile)
		var fine_ms := _ms(t)
		t = Time.get_ticks_usec()
		cache = {}
		for p: Vector2 in points: source._sample_point(p.x, p.y, cache)
		var point_ms := _ms(t)
		var plain := {"ok": true, "elevation_m": 1.0, "elevation_valid": true, "level": 1, "water_kind": 0, "water_id": "", "water_body": 0, "source_quality_code": 1}
		t = Time.get_ticks_usec()
		for p: Vector2 in points: source._author_sample(plain, p.x, p.y)
		var author_ms := _ms(t)
		t = Time.get_ticks_usec()
		for p: Vector2 in points: plain.duplicate()
		var dup_ms := _ms(t)
		print("SAMPLE_COST site %s ok %s build %.0f ms | %d samples: site_meters %.0f, meters %.0f, tile_at %.0f, fine_water %.0f, point %.0f, author %.0f, dict dup %.0f ms" % [str(site), str(built.get("ok", false)), build_ms, points.size(), site_ms, meters_ms, tile_ms, fine_ms, point_ms, author_ms, dup_ms])
	print("SAMPLE_COST_DONE")
	quit(0)
