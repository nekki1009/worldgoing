extends SceneTree
## Probe (2026-11-27, 開局速度 B): where the first projection of each authored Site goes. Loads the shipped demo A package
## and, for every expected initial Site: make_terrain_data (the tile build), _initial_body (build + state check + navigation),
## project_terrain the first time and again. Output: AUTHOR_PROJECTION lines and AUTHOR_PROJECTION_DONE.
const PACKAGE := "res://assets/scenarios/demo_a/demo_a.json"

func _initialize() -> void:
	_run.call_deferred()

func _ms(from: int) -> float:
	return float(Time.get_ticks_usec() - from) / 1000.0

func _run() -> void:
	var source := RegionData.new()
	var started := Time.get_ticks_usec()
	var loaded: Dictionary = source.load_manifest(PACKAGE)
	print("AUTHOR_PROJECTION manifest %s in %.0f ms" % [str(loaded.get("ok", false)), _ms(started)])
	if not loaded.get("ok", false):
		print("AUTHOR_PROJECTION_DONE")
		quit(1)
		return
	var sites: Array = source.author_initial_context().get("expected_initial_sites", [])
	var totals := {"build": 0.0, "body": 0.0, "first": 0.0, "again": 0.0}
	var slowest := []
	for pair: Variant in sites:
		var site := Vector2i(int(pair[0]), int(pair[1]))
		var t := Time.get_ticks_usec()
		var built: Dictionary = source.make_terrain_data(site.x, site.y)
		var build_ms := _ms(t)
		t = Time.get_ticks_usec()
		var body: Dictionary = source._initial_body(site)
		var body_ms := _ms(t)
		t = Time.get_ticks_usec()
		var first: Dictionary = source.project_terrain(site, "author_initial")
		var first_ms := _ms(t)
		t = Time.get_ticks_usec()
		var again: Dictionary = source.project_terrain(site, "author_initial")
		var again_ms := _ms(t)
		totals.build += build_ms
		totals.body += body_ms
		totals.first += first_ms
		totals.again += again_ms
		slowest.append([first_ms, str(site), build_ms, body_ms, again_ms, bool(built.get("ok", false)) and bool(body.get("ok", false)) and bool(first.get("ok", false)) and bool(again.get("ok", false))])
	slowest.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	for row: Array in slowest.slice(0, 6): print("AUTHOR_PROJECTION site %s first %.0f ms (build %.0f, body %.0f) again %.0f ok %s" % [row[1], row[0], row[2], row[3], row[4], str(row[5])])
	print("AUTHOR_PROJECTION %d sites: build %.0f ms, body %.0f ms, project first %.0f ms, again %.0f ms" % [sites.size(), totals.build, totals.body, totals.first, totals.again])
	# The second pass, everything warm: what a repeated build costs.
	var t2 := Time.get_ticks_usec()
	for pair: Variant in sites: source.make_terrain_data(int(pair[0]), int(pair[1]))
	print("AUTHOR_PROJECTION build again (warm) %.0f ms" % _ms(t2))
	print("AUTHOR_PROJECTION_DONE")
	quit(0)
