extends "res://scripts/tests/site_building_ui_test.gd"
## 時間與氣候 TC10 (§4.7, D6 A): ranged aim under weather. Checks:
## - a weather penalty widens the scatter (lower aim quality) for the same shot;
## - climate off: the shooter is untouched;
## - climate on: rain −15 (drizzle −5, storm −30), strong wind −5, night −10 unless the target is near a fire light.
## Output: SITE_RANGED_WEATHER_TC10_PASS on success; quit(1) on failure.
const Climate = preload("res://scripts/terrain_lab/site_climate.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_RANGED_WEATHER_TC10 OK ", checks, ": ", message)
		return true
	push_error("SITE_RANGED_WEATHER_TC10_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _run() -> void:
	var shooter := {"ability": 50.0, "training": 0.0, "fatigue": 0.0}
	var calm := 0.0
	var wet := 0.0
	for shot: int in range(1, 200):
		calm += SiteCombatRules.fire_aim_offset(shooter, 8.0, false, 7, 3, 1, shot).length()
		wet += SiteCombatRules.fire_aim_offset(shooter.merged({"weather_penalty": 25.0}), 8.0, false, 7, 3, 1, shot).length()
	if not _ok(wet > calm * 1.1, "a weather penalty widens the scatter", [calm, wet]): return
	var data := _building_fixture()
	var lab := _building_lab(data)
	if not _ok(lab._weather_aim(shooter, Vector2i(20, 20)) == shooter, "climate off: untouched"): return
	data.site["climate_enabled"] = true
	var keys := Climate.site_keys(data)
	var found := -1
	for minute: int in range(0, 400 * 1440, 120):
		var now := Climate.at(str(keys.world), str(keys.region), 0.0, float(minute + 30))
		if str(now.weather) == "rain" and str(now.band) == "night" and (now.wind as Vector2).length() < 0.6:
			found = minute + 30
			break
	if not _ok(found >= 0, "a calm rainy night exists"): return
	data.site.minute = found
	var far := lab._weather_aim(shooter, Vector2i(40, 40))
	var depot := data.cell_from_index(int(data.site.depot_cell))
	var near := lab._weather_aim(shooter, depot)
	if not _ok(float(far.get("weather_penalty", 0.0)) == 25.0 and float(near.get("weather_penalty", 0.0)) == 15.0 and not shooter.has("weather_penalty"), "a rainy night −25; beside the camp fire −15", [far, near]): return
	print("SITE_RANGED_WEATHER_TC10_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
