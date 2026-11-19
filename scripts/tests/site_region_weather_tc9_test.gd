extends SceneTree
## 時間與氣候 TC9 (氣候 S4; reports/day-weather-season-plan.md §4.7). Checks:
## - travel speed: drizzle ×0.9, rain ×0.75, storm ×0.5, night ×0.85, on a road half the penalty;
## - open-air rest ×0.7 in rain or at night, nothing for a party with a camp tent;
## - scouting distance at night ×0.6 and in fog ×0.5;
## - weather slots end on even hours; a Region position is keyed like its Sites (map and Site agree);
## - the faction registry's climate switch validates, and a broken one is refused;
## - fatigue recovers less with the rest factor.
## Output: SITE_REGION_WEATHER_TC9_PASS on success; quit(1) on failure.
const RegionWeather = preload("res://scripts/region_lab/region_weather.gd")
const Climate = preload("res://scripts/terrain_lab/site_climate.gd")
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_REGION_WEATHER_TC9 OK ", checks, ": ", message)
		return true
	printerr("SITE_REGION_WEATHER_TC9_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _run() -> void:
	var day_clear := {"weather": "clear", "band": "day"}
	var night_clear := {"weather": "clear", "band": "night"}
	var day_rain := {"weather": "rain", "band": "day"}
	var night_storm := {"weather": "storm", "band": "night"}
	var night_fog := {"weather": "fog", "band": "night"}
	var speeds := [RegionWeather.speed_factor(day_clear), RegionWeather.speed_factor(night_clear), RegionWeather.speed_factor(day_rain), RegionWeather.speed_factor(night_storm), RegionWeather.speed_factor(day_rain, true), RegionWeather.speed_factor({})]
	if not _ok(is_equal_approx(speeds[0], 1.0) and is_equal_approx(speeds[1], 0.85) and is_equal_approx(speeds[2], 0.75) and is_equal_approx(speeds[3], 0.425) and is_equal_approx(speeds[4], 0.875) and speeds[5] == 1.0, "travel speed by weather and night; half on a road", speeds): return
	if not _ok(is_equal_approx(RegionWeather.rest_factor(night_clear, false), 0.7) and RegionWeather.rest_factor(day_clear, false) == 1.0 and RegionWeather.rest_factor(day_rain, true) == 1.0 and is_equal_approx(RegionWeather.rest_factor({"weather": "drizzle", "band": "day"}, false), 0.7), "open-air rest ×0.7 in rain or at night; a tent shelters"): return
	if not _ok(is_equal_approx(RegionWeather.scout_factor(night_clear), 0.6) and is_equal_approx(RegionWeather.scout_factor({"weather": "fog", "band": "dawn"}), 0.5) and is_equal_approx(RegionWeather.scout_factor(night_fog), 0.3) and RegionWeather.scout_factor(day_clear) == 1.0, "scouting shrinks at night and in fog"): return
	if not _ok(RegionWeather.slot_end(0.0) == 7200.0 and RegionWeather.slot_end(7199.0) == 7200.0 and RegionWeather.slot_end(7200.0) == 14400.0, "weather slots end every two game hours"): return
	if not _ok(RegionWeather.sheltered({"content": {"carriers": [{"cargo": {"camp_tent": 1}}]}}) and not RegionWeather.sheltered({"content": {"carriers": [{"cargo": {"grain": 5}}]}}), "a camp tent anywhere in the party shelters it"): return
	var data := TerrainData.new()
	data.site = {"id": "taiwan_v1:1170:13252", "minute": 0}
	var keys := Climate.site_keys(data)
	if not _ok(str(keys.region) == RegionWeather.region_key("taiwan_v1", Vector2i(1170, 13252)), "a Region position is keyed like its Sites", [keys.region, RegionWeather.region_key("taiwan_v1", Vector2i(1170, 13252))]): return
	var registry := {"version": RegionFactionQuery.VERSION, "revision": 1, "next_faction_id": 1, "migration_complete": true, "entries": {},
		"coverage": {"complete": false, "sources": [], "counts": null}, "climate": {"version": 1, "enabled": true}}
	if not _ok(RegionFactionQuery.validate(registry, 1.0e9).ok and RegionWeather.enabled(registry), "the registry's climate switch validates", RegionFactionQuery.validate(registry, 1.0e9)): return
	registry.climate = {"version": 1, "enabled": "yes"}
	if not _ok(not RegionFactionQuery.validate(registry, 1.0e9).ok, "a broken switch is refused"): return
	var full: Array[float] = Fatigue.advance(80.0, Fatigue.REST_DELAY, 600.0, 0.0, true, 1.0)
	var open: Array[float] = Fatigue.advance(80.0, Fatigue.REST_DELAY, 600.0, 0.0, true, 0.7)
	if not _ok(open[0] > full[0], "fatigue recovers less with the rest factor", [full, open]): return
	print("SITE_REGION_WEATHER_TC9_PASS checks=", checks)
	quit(0)
