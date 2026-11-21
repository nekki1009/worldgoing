extends "res://scripts/tests/site_building_ui_test.gd"
## 時間與氣候 TC5b (§4.6, §7 risk 1). Checks:
## - climate off: a fire boundary writes no weather;
## - climate on: the boundary writes the slot's wind, rain and drying once, and a second boundary in the same slot
##   writes nothing; the next slot with other weather writes a new row;
## - a full history (4096 rows) is compacted (the older half merged pairwise), stays valid, and keeps accepting rows;
##   the merged rows keep their time-weighted rain.
## Output: SITE_FIRE_WEATHER_TC5B_PASS on success; quit(1) on failure.
const Climate = preload("res://scripts/terrain_lab/site_climate.gd")
var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_FIRE_WEATHER_TC5B OK ", checks, ": ", message)
		return true
	push_error("SITE_FIRE_WEATHER_TC5B_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _history(data: TerrainData) -> Array:
	return data.site.get("fire", {}).get("weather", {}).get("history", [])

func _boundary(lab: TerrainLab, data: TerrainData, at: float) -> void:
	if data.site.has("fire"): data.site.fire.observed_action_end = at
	data.set_meta(&"fire_completed_action_end", at)
	lab._climate_fire_weather(at)

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	data.site.minute = 600
	_boundary(lab, data, 10.0)
	if not _ok(_history(data).is_empty(), "climate off: no fire weather"): return
	data.site["climate_enabled"] = true
	_boundary(lab, data, 20.0)
	var now := Climate.for_site(data)
	var rows := _history(data)
	if not _ok(rows.size() == 2 and is_equal_approx(float(rows[1].rain), float(now.rain)) and is_equal_approx(float(rows[1].wind_x), (now.wind as Vector2).x), "climate on: the slot's weather is written", rows): return
	_boundary(lab, data, 30.0)
	if not _ok(_history(data).size() == 2, "the same slot writes nothing more"): return
	var keys := Climate.site_keys(data)
	var other := -1
	for minute: int in range(600 + 120, 600 + 120 * 400, 120):
		var later := Climate.at(str(keys.world), str(keys.region), 0.0, float(minute))
		if float(later.rain) != float(now.rain) or (later.wind as Vector2) != (now.wind as Vector2):
			other = minute
			break
	data.site.minute = other
	_boundary(lab, data, 40.0)
	if not _ok(other > 0 and _history(data).size() == 3, "another slot's weather writes a row"): return
	# Fill to the cap.
	var cap := int(SiteCombatRules.fire_environment_profile().weather_history_cap)
	var at := 50.0
	while _history(data).size() < cap:
		data.site.fire.observed_action_end = at
		SiteRuntime.fire_set_weather(data, at, Vector2(0.1 * (int(at / 10.0) % 3), 0.0), float(int(at / 10.0) % 2), 0.01)
		at += 10.0
	var before_rows := _history(data).size()
	data.site.fire.observed_action_end = at
	var refused := SiteRuntime.fire_set_weather(data, at, Vector2.ZERO, 0.5, 0.0)
	if not _ok(before_rows == cap and str(refused.code) == "WEATHER_HISTORY_CAPACITY", "a full history refuses a row", refused): return
	data.site.minute = 600
	_boundary(lab, data, at)
	var after := _history(data)
	var checked := SiteRuntime._validate_fire_weather_snapshot(data.site.fire.weather, at)
	if not _ok(after.size() < cap and after.size() > cap / 2 and checked.ok and float(after.back().action_time) == at, "the boundary compacts and writes; the history stays valid", [after.size(), checked]): return
	var merged: Dictionary = after[4]
	if not _ok(float(merged.rain) > 0.0 and float(merged.rain) < 1.0, "a merged row keeps the time-weighted rain", merged): return
	print("SITE_FIRE_WEATHER_TC5B_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
