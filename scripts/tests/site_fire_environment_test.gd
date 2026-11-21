extends "res://scripts/tests/site_fire_runtime_test.gd"
## Original Runtime weather/smoke functional candidate. Genesis is explicit.

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	print("SITE_FIRE_ENVIRONMENT_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	quit(0 if ok else 1)

func _smoke_total(data: TerrainData) -> float:
	var total := 0.0
	for entry: Dictionary in data.site.fire.get("smoke", {}).values(): total += float(entry.density)
	return total

func _weather_history() -> bool:
	var data := _data()
	if not _check(Runtime.fire_set_weather(data, 0.0, Vector2.RIGHT, 1.0).ok, "Original weather input starts at exact completed action boundary"): return false
	if not _advance(data, 2.0): return false
	if not _check(Runtime.fire_set_weather(data, 2.0, Vector2.ZERO, 0.0).ok, "Original weather switches after two rain action seconds"): return false
	if not _advance(data, 6.0): return false
	var unit := {"moisture": 0.0, "moisture_action": 0.0}
	var exposed := {"moisture": 0.0, "rain_exposure": 1.0}
	var sheltered := {"moisture": 0.0, "rain_exposure": 0.0}
	var before := var_to_bytes(data.site.fire)
	if not _check(absf(Runtime.fire_unit_moisture(data, unit, exposed, 6.0) - 0.04) < 0.000000001
		and Runtime.fire_unit_moisture(data, unit, sheltered, 6.0) == 0.0
		and absf(Runtime.fire_rain_integral(data, 0.0, 6.0) - 2.0) < 0.000000001
		and var_to_bytes(data.site.fire) == before, "FI-08 dormant exposed and sheltered units integrate actual old rain then dry, with pure reads"): return false
	if not _check(not Runtime.fire_set_weather(data, 5.0, Vector2.ZERO, 1.0).ok
		and var_to_bytes(data.site.fire) == before, "Past weather insertion rejects without replacing live history"): return false
	data.site.paused = true
	if not _check(not Runtime.fire_set_weather(data, 6.0, Vector2.ZERO, 1.0).ok
		and not Runtime.fire_advance(data, 6.2, 0).ok and var_to_bytes(data.site.fire) == before,
		"Paused original Site advances neither weather input nor smoke/fire"): return false
	return true

func _wind_legal_edges() -> bool:
	var data := _data()
	# Complete the original paid wall while its original entrance is clear.
	if _stone_wall(data, Vector2i(20, 19)).is_empty(): return false
	var source := _timber(data, Vector2i(20, 20))
	var east := _timber(data, Vector2i(21, 20))
	var west := _timber(data, Vector2i(19, 20))
	var blocked := _timber(data, Vector2i(20, 18))
	if not _check(Runtime.fire_set_weather(data, 0.0, Vector2.RIGHT, 0.0).ok, "Original wind input recorded without topology edits"): return false
	var state := Runtime._fire_state(data, 0.0)
	var unit := Runtime._fire_unit(data, state, Runtime._fire_resource_descriptor(data, source))
	unit.merge({"heat": 100.0, "state": "BURNING", "intensity": 1.0, "moisture": 0.0}, true)
	state.active["resource:" + source] = true
	var descriptor := Runtime._fire_resource_descriptor(data, source)
	var before_edges := var_to_bytes(Runtime._fire_resource_edges(data, descriptor))
	var nav := data.navigation_revision
	if not _advance(data, 0.2): return false
	if not _check(float(_unit(data, east).get("heat", 0.0)) > float(_unit(data, west).get("heat", 0.0))
		and not data.site.fire.units.has("resource:" + blocked) and data.navigation_revision == nav
		and var_to_bytes(Runtime._fire_resource_edges(data, descriptor)) == before_edges,
		"FI-09 wind redistributes bounded existing legal edges; stone wall gains no edge and no navigation mutation"): return false
	return true

func _smoke_conservation_and_middle() -> bool:
	var data := _data()
	if _stone_wall(data, Vector2i(21, 20)).is_empty(): return false
	var state := Runtime._fire_state(data, 0.0)
	var source := data.index(Vector2i(20, 20))
	state.smoke = {Runtime._fire_smoke_key(source, 0): {"cell": source, "layer": 0, "density": 10.0}} # Explicit cold cloud genesis.
	if not _advance(data, 0.2): return false
	var expected := 10.0 * exp(-0.35 * 0.2)
	if not _check(absf(_smoke_total(data) - expected) < 0.000000001
		and not state.smoke.has(Runtime._fire_smoke_key(data.index(Vector2i(21, 20)), 0))
		and state.active.is_empty() and Runtime.fire_active(data),
		"FI-10 outdoor smoke survives absent heat, conserves transport before decay, and cannot enter original wall prism"): return false
	var from := Vector3(20.5, 16.5, 1.0)
	var to := Vector3(20.5, 24.5, 1.0)
	var columns := Runtime._fire_smoke_columns(data)
	var before := var_to_bytes(state)
	if not _check(not columns.has(data.index(Vector2i(20, 16))) and not columns.has(data.index(Vector2i(20, 24)))
		and Runtime.fire_smoke_optical_depth(data, from, to) > 8.0
		and Runtime.fire_smoke_scatter_scale(data, from, to) > 1.0
		and Runtime.fire_smoke_optical_depth(data, from + Vector3(0, 0, 4), to + Vector3(0, 0, 4)) == 0.0
		and var_to_bytes(state) == before,
		"FI-11 clear endpoints still integrate mid-segment smoke by actual ray height without mutating authority"): return false
	if not _advance(data, 1.2): return false
	if not _check(_smoke_total(data) < expected and _smoke_total(data) > 0.0 and state.active.is_empty()
		and Runtime.fire_active(data), "Cold smoke continues its original5Hz decay independently of any VFX"): return false
	return true

func _actual_fire_emits_then_cools() -> bool:
	var data := _data()
	var resource := _timber(data, Vector2i(20, 20))
	var key := "resource:" + resource
	var state := Runtime._fire_state(data, 0.0)
	var unit := Runtime._fire_unit(data, state, Runtime._fire_resource_descriptor(data, resource))
	unit.merge({"profile": "TEST_HEAT_100", "heat": 100.0, "state": "BURNING", "intensity": 1.0, "moisture": 0.0}, true)
	state.active[key] = true
	if not _advance(data, 0.2): return false
	if not _check(_smoke_total(data) > 0.0, "Actual old burning original fuel emits logical smoke at fire boundary"): return false
	var holder := Runtime.new_item_state("person:789")
	holder.fire_lab_suppression_q = 4096
	var fraction := 0.0
	for tick in range(60):
		var begin := 0.2 + tick / 30.0
		var end := 0.2 + (tick + 1) / 30.0
		fraction += 1024.0 / 30.0
		var q := floori(fraction + Runtime.FIRE_EPS)
		fraction -= q
		var prepared := Runtime.fire_prepare_suppression(data, key, int(data.site.fire.units[key].generation), begin, end, q, holder, int(holder.version))
		if not _check(prepared.ok, "Original finite suppression prepare during burning smoke case"): return false
		if int(prepared.get("paid_q", 0)) > 0 and not _check(Runtime.fire_commit_suppression(data, prepared).ok, "Original holder commits finite cooling once"): return false
		if not _advance(data, end): return false
	if not _check(float(state.units[key].heat) == 0.0 and not state.active.has(key) and _smoke_total(data) > 0.0
		and Runtime.fire_active(data) and holder.fire_lab_suppression_q == 2496,
		"FI-10 original fuel extinguishes with1600 paid quanta while independent finite smoke remains"): return false
	return true

func _run() -> void:
	if not _weather_history(): _finish(false, "weather history and exposure"); return
	if not _wind_legal_edges(): _finish(false, "wind legal edges"); return
	if not _smoke_conservation_and_middle(): _finish(false, "smoke conservation/ray"); return
	if not _actual_fire_emits_then_cools(): _finish(false, "burning to cold smoke"); return
	_finish(not failed)
