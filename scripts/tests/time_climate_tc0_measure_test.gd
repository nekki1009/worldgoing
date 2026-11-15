extends SceneTree
## 時間與氣候 TC0 (reports/time-and-climate-plan.md §4): measurements only, no game behaviour changes.
## 1. Cold Site catch-up: a saved small Site (one NPC, a farm; res://output/time_climate_tc0/source_small.json, a copy of
##    the real-NPC cold replay fixture) is advanced cold by 1, 10 and 30 game days through TerrainLab.advance_cold_site,
##    the production adapter. Each case runs for at most CASE_BUDGET_MS of wall time; the game seconds reached in that
##    budget give the catch-up rate (game seconds per wall second) and the projected wall time of the whole case.
## 2. Clock precision over 3 years: the float world-second clock stepped by one game minute for three 365-day years
##    against the exact integer count, the double ulp at that range, and the calendar date at the end.
## 3. Climate query cost estimate: a stand-in pure function of (seed, region, 2-hour cell) with the shape SiteClimate.at
##    will have (two hashes, a few sines), per call and per cached cell.
## Writes res://output/time_climate_tc0/tc0_result.json. Output: TIME_CLIMATE_TC0_PASS; quit(1) on failure.

const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const SOURCE := "res://output/time_climate_tc0/source_small.json"
const RESULT := "res://output/time_climate_tc0/tc0_result.json"
const CASE_BUDGET_MS := 120000
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 900000
	_run.call_deferred()

func _fail(message: String) -> void:
	printerr("TIME_CLIMATE_TC0_FAIL: ", message)
	quit(1)

func _scene() -> TerrainLab:
	var lab: TerrainLab = (load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene).instantiate() as TerrainLab
	lab.restore_only = true
	lab.pause_when_unfocused = false
	lab.exchange_enabled = true
	root.add_child(lab)
	return lab

func _cold_case(days: int) -> Dictionary:
	var loaded: Dictionary = SiteStore.load_site(SOURCE, Callable(), 1, true)
	if not loaded.ok: return {"ok": false, "error": str(loaded)}
	var source: TerrainData = loaded.data
	var start_seconds := float(source.site.get("minute", 0)) * 60.0 + float(source.site.get("phase", 0.0)) * 60.0
	var target := start_seconds + float(days) * 86400.0
	var host := _scene()
	var started := Time.get_ticks_usec()
	var budget_end := Time.get_ticks_msec() + CASE_BUDGET_MS
	var calls := 1
	var adapted: Dictionary = host.advance_cold_site(source, target)
	while not adapted.ok and str(adapted.get("code", "")) == "PENDING":
		if Time.get_ticks_msec() > budget_end or Time.get_ticks_msec() > deadline:
			var replay_lab: Variant = host._cold_replay_lab
			var at := -1.0
			if is_instance_valid(replay_lab) and replay_lab.terrain != null:
				at = float(replay_lab.terrain.site.get("minute", 0)) * 60.0 + float(replay_lab.terrain.site.get("phase", 0.0)) * 60.0
			var wall := float(Time.get_ticks_usec() - started) / 1000000.0
			var rate := (at - start_seconds) / wall if at >= 0.0 else -1.0
			host.queue_free()
			return {"ok": true, "complete": false, "days": days, "calls": calls, "wall_seconds": wall, "game_seconds_reached": at - start_seconds,
				"game_seconds_per_wall_second": rate, "projected_wall_seconds": (float(days) * 86400.0 / rate) if rate > 0.0 else -1.0}
		adapted = host.advance_cold_site(source, target)
		calls += 1
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var reached := -1.0
	if adapted.ok: reached = float(adapted.data.site.get("minute", 0)) * 60.0 + float(adapted.data.site.get("phase", 0.0)) * 60.0
	host.queue_free()
	return {"ok": bool(adapted.ok), "complete": bool(adapted.ok), "days": days, "wall_seconds": elapsed_ms / 1000.0, "calls": calls, "target": target, "reached": reached, "code": str(adapted.get("code", ""))}

func _precision() -> Dictionary:
	var seconds := 0.0
	var steps := 3 * Calendar.YEAR_DAYS * Calendar.DAY_MINUTES
	var started := Time.get_ticks_usec()
	for _step: int in range(steps): seconds += 60.0
	var exact := float(steps) * 60.0
	var fractional := 0.0
	for _step: int in range(steps): fractional += 60.0 / 7.0 * 7.0 # a non-representable-looking step that is exact again
	var frame_seconds := 0.0
	for _step: int in range(200000): frame_seconds += 1.0 / 60.0 * 60.0 * 0.37 # a 0.37 speed frame of the peace rate
	var end_date := Calendar.date(exact / 60.0)
	return {"steps": steps, "drift_seconds": seconds - exact, "drift_fractional": fractional - exact, "ulp_at_3_years": _ulp(exact),
		"frame_sum_drift": frame_seconds - 200000.0 * 0.37, "end_date": end_date, "ms": float(Time.get_ticks_usec() - started) / 1000.0}

func _ulp(value: float) -> float:
	var exponent := floorf(log(absf(value)) / log(2.0))
	return pow(2.0, exponent - 52.0)

static func _climate_stand_in(seed_value: int, region: int, cell: int) -> Dictionary:
	var h1 := hash([seed_value, region, cell])
	var h2 := hash([h1, 7919])
	var season_wave := sin(float(cell % 4380) / 4380.0 * TAU)
	var rain := clampf(float(h1 % 1000) / 1000.0 + 0.3 * season_wave, 0.0, 1.0)
	var wind := float(h2 % 360)
	var gust := absf(sin(float(h2 % 997)))
	return {"rain": rain, "wind": wind, "gust": gust, "dry": 1.0 - rain}

func _climate_cost() -> Dictionary:
	var calls := 100000
	var started := Time.get_ticks_usec()
	var sink := 0.0
	for index: int in range(calls): sink += float(_climate_stand_in(12345, index % 37, index).rain)
	var per_call_us := float(Time.get_ticks_usec() - started) / float(calls)
	var cache := {}
	started = Time.get_ticks_usec()
	for index: int in range(calls):
		var key := Vector2i(index % 37, index / 5000)
		if not cache.has(key): cache[key] = _climate_stand_in(12345, key.x, key.y)
		sink += float(cache[key].rain)
	var cached_us := float(Time.get_ticks_usec() - started) / float(calls)
	return {"per_call_us": per_call_us, "cached_lookup_us": cached_us, "sink": sink}

func _run() -> void:
	if not FileAccess.file_exists(SOURCE):
		_fail("missing " + SOURCE)
		return
	var result := {"cold": [], "precision": {}, "climate": {}}
	for days: int in [1, 10, 30]:
		var measured := _cold_case(days)
		print("TIME_CLIMATE_TC0 cold ", JSON.stringify(measured))
		result.cold.append(measured)
		for _frame: int in range(3): await process_frame
		if not bool(measured.ok):
			_fail("cold catch-up of %d days did not complete: %s" % [days, str(measured)])
			return
	result.precision = _precision()
	print("TIME_CLIMATE_TC0 precision ", JSON.stringify(result.precision))
	result.climate = _climate_cost()
	print("TIME_CLIMATE_TC0 climate ", JSON.stringify(result.climate))
	var file := FileAccess.open(RESULT, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "  "))
		file.close()
	if absf(float(result.precision.drift_seconds)) > 0.0:
		_fail("whole-minute steps drifted: " + str(result.precision))
		return
	print("TIME_CLIMATE_TC0_PASS")
	TerrainArmy.release_contact_source()
	quit(0)
