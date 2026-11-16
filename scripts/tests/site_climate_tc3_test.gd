extends SceneTree
## 時間與氣候 TC3 (氣候 S0; reports/day-weather-season-plan.md §4.1–§4.5, D1–D4 A). SiteClimate is a pure query. Checks:
## - the same world, region and minute give the same answer; another world gives another year;
## - bands (dawn 05–07, day 07–17, dusk 17–19, night 19–05) and seasons by calendar month;
## - a year of one region: 2–8 typhoon days, all in Jul–Sep; storms only from typhoons or Jun–Sep afternoon
##   thunder; fog only 04:00–08:00 of Nov–Apr; the plum rains (mid May–mid Jun) wetter than July; the January
##   monsoon blows to the south-west;
## - rain, wind and drying stay in range; a year of slot queries is cheap;
## - climate is off unless the Site sets climate_enabled: off reads {} and no clock suffix.
## Output: SITE_CLIMATE_TC3_PASS on success; quit(1) on failure.
const Climate = preload("res://scripts/terrain_lab/site_climate.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_CLIMATE_TC3 OK ", checks, ": ", message)
		return true
	printerr("SITE_CLIMATE_TC3_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _minute(year: int, month: int, day: int, hour: int) -> float:
	return float(Calendar.day_start_minute(Calendar.day_of(year, month, day)) + hour * 60)

func _run() -> void:
	var a := Climate.at("w1", "r1", 0.0, _minute(1, 3, 10, 9))
	var b := Climate.at("w1", "r1", 0.0, _minute(1, 3, 10, 9))
	if not _ok(a == b, "the same query gives the same answer"): return
	var differs := false
	for day: int in range(365):
		if Climate.day_type("w1", "r1", 0.0, day) != Climate.day_type("w2", "r1", 0.0, day):
			differs = true
			break
	if not _ok(differs, "another world has another year"): return
	var bands := [Climate.at("w1", "r1", 0.0, _minute(1, 3, 10, 5)).band, Climate.at("w1", "r1", 0.0, _minute(1, 3, 10, 12)).band,
		Climate.at("w1", "r1", 0.0, _minute(1, 3, 10, 17)).band, Climate.at("w1", "r1", 0.0, _minute(1, 3, 10, 23)).band, Climate.at("w1", "r1", 0.0, _minute(1, 3, 10, 2)).band]
	if not _ok(bands == ["dawn", "day", "dusk", "night", "night"], "bands", bands): return
	var seasons := [Climate.at("w1", "r1", 0.0, _minute(1, 1, 5, 9)).season, Climate.at("w1", "r1", 0.0, _minute(1, 4, 5, 9)).season,
		Climate.at("w1", "r1", 0.0, _minute(1, 7, 5, 9)).season, Climate.at("w1", "r1", 0.0, _minute(1, 10, 5, 9)).season, Climate.at("w1", "r1", 0.0, _minute(1, 12, 5, 9)).season]
	if not _ok(seasons == ["winter", "spring", "summer", "autumn", "winter"], "seasons follow the calendar months", seasons): return
	# A year of one region.
	var began := Time.get_ticks_usec()
	var typhoon := Climate.typhoon_days("w1", "r1", 2)
	var typhoon_ok := typhoon.size() >= 2 and typhoon.size() <= 8
	for day: Variant in typhoon:
		var month := int(Calendar.date(float(Calendar.day_start_minute(int(day)))).month)
		typhoon_ok = typhoon_ok and month >= 7 and month <= 9
	var bad_storm := 0
	var bad_fog := 0
	var ranges_ok := true
	var plum_wet := 0
	var plum_slots := 0
	var july_wet := 0
	var july_slots := 0
	var monsoon_ok := true
	var first := Calendar.day_of(2, 1, 1)
	for day: int in range(first, first + 365):
		var date := Calendar.date(float(Calendar.day_start_minute(day)))
		var month := int(date.month)
		var at_day := month * 100 + int(date.day)
		for slot: int in range(Climate.SLOTS):
			var now := Climate.at("w1", "r1", 0.0, float(Calendar.day_start_minute(day) + slot * Climate.SLOT_MINUTES + 30))
			var weather := str(now.weather)
			if weather == "storm" and not typhoon.has(day) and not (slot == 7 and month >= 6 and month <= 9): bad_storm += 1
			if weather == "fog" and (slot not in [2, 3] or (month > 4 and month < 11)): bad_fog += 1
			ranges_ok = ranges_ok and float(now.rain) >= 0.0 and float(now.rain) <= 1.0 and (now.wind as Vector2).length() <= 1.0001 and float(now.drying) >= 0.0 and float(now.drying) <= 0.02
			var wet := weather in ["drizzle", "rain", "storm"]
			if at_day >= 515 and at_day <= 615:
				plum_slots += 1
				if wet: plum_wet += 1
			if month == 7 and not typhoon.has(day):
				july_slots += 1
				if wet: july_wet += 1
			if month == 1 and weather != "fog":
				var wind: Vector2 = now.wind
				monsoon_ok = monsoon_ok and wind.x < 0.0 and wind.y > 0.0
	var wall := float(Time.get_ticks_usec() - began) / 1000000.0
	if not _ok(typhoon_ok, "2–8 typhoon days, all in Jul–Sep", typhoon): return
	if not _ok(bad_storm == 0, "storms only from typhoons or summer afternoon thunder", bad_storm): return
	if not _ok(bad_fog == 0, "fog only in the early morning of Nov–Apr", bad_fog): return
	if not _ok(ranges_ok, "rain, wind and drying in range"): return
	if not _ok(float(plum_wet) / float(plum_slots) > float(july_wet) / float(july_slots), "the plum rains are wetter than July", [plum_wet, plum_slots, july_wet, july_slots]): return
	if not _ok(monsoon_ok, "the January monsoon blows to the south-west"): return
	if not _ok(wall < 5.0, "a year of slot queries is cheap", wall): return
	print("SITE_CLIMATE_TC3 year_seconds=", wall)
	# The Site switch.
	var data := TerrainData.new()
	data.site = {"id": "s1", "minute": int(_minute(1, 3, 10, 9))}
	if not _ok(Climate.for_site(data).is_empty() and Climate.clock_suffix(data) == "", "off by default: no climate and no clock suffix"): return
	data.site["climate_enabled"] = true
	var suffix := Climate.clock_suffix(data)
	if not _ok(not Climate.for_site(data).is_empty() and suffix.begins_with("　白天　"), "on: the clock line shows the band and the weather", suffix): return
	print("SITE_CLIMATE_TC3_PASS checks=", checks)
	quit(0)
