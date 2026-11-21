extends SceneTree
## 時間與氣候 TC8 (氣候 S3; reports/day-weather-season-plan.md §4.3, §4.7, §4.8, §7 risk 4). Checks:
## - every multiplier is 1.0 while the Site's climate is off;
## - with climate on: farm 0.6 in January and 1.2 in July, pasture, wild food / fish recovery and farm water demand by
##   season; recovery minutes stretch in winter;
## - rain waters a farm (wet_ratio) and a drought after 10 dry days cuts wells and intakes to ×0.7;
## - the forecast: today only, three more days with the 虞衡;
## - autumn stores: an NPC registry in autumn with less than 90 rations per resident puts every household on food,
##   not in spring and not with a full camp; the long-absence catch-up applies the farm factor.
## Output: SITE_SEASON_TC8_PASS on success; quit(1) on failure.
const Season = preload("res://scripts/terrain_lab/site_season.gd")
const Climate = preload("res://scripts/terrain_lab/site_climate.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const ResidentWork = preload("res://scripts/terrain_lab/site_resident_work.gd")
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SEASON_TC8 OK ", checks, ": ", message)
		return true
	printerr("SITE_SEASON_TC8_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _data(month: int, enabled: bool, world: String = "w1") -> TerrainData:
	var data := TerrainData.new()
	data.site = {"id": "s1", "minute": Calendar.day_start_minute(Calendar.day_of(2, month, 10)) + 9 * 60, "world_pin": {"world_instance_id": world}}
	if enabled: data.site["climate_enabled"] = true
	return data

func _run() -> void:
	var off := _data(1, false)
	if not _ok(Season.farm_factor(off) == 1.0 and Season.water_factor(off) == 1.0 and Season.supply_factor(off) == 1.0 and Season.rain(off) == 0.0 \
		and Season.recover_minutes(off, Env.Kind.FOOD, 720) == 720 and Season.forecast(off, true).is_empty() and Season.water_key(off) == "", "climate off: every factor is 1.0"): return
	var january := _data(1, true)
	var july := _data(7, true)
	var april := _data(4, true)
	if not _ok(Season.farm_factor(january) == 0.6 and Season.farm_factor(july) == 1.2 and Season.farm_factor(april) == 1.0 and Season.pasture_factor(january) == 0.7 and Season.water_factor(july) == 1.3, "season multipliers"): return
	if not _ok(Season.recover_minutes(january, Env.Kind.FOOD, 720) == 1440 and Season.recover_minutes(january, Env.Kind.FISH, 120) == 150 and Season.recover_minutes(april, Env.Kind.HERB, 1440) == 1200 and Season.recover_minutes(january, Env.Kind.TIMBER, 10080) == 10080, "wild food, herb and fish recovery follow the season"): return
	# Rain.
	var keys := Climate.site_keys(july)
	var wet := -1
	for minute: int in range(int(july.site.minute), int(july.site.minute) + 60 * 1440, 120):
		if str(Climate.at(str(keys.world), str(keys.region), 0.0, float(minute)).weather) == "rain":
			wet = minute
			break
	if not _ok(wet >= 0, "a rain slot exists within 60 days"): return
	july.site.minute = wet
	if not _ok(is_equal_approx(Season.wet_ratio(july, 0.0, 10.0), 0.7) and Season.wet_ratio(july, 5.0, 10.0) == 1.0 and Season.wet_ratio(january, 0.0, 10.0) < 1.0, "rain waters an open farm"): return
	# Drought: search worlds for ten dry days.
	var dry: TerrainData = null
	for index: int in range(1, 200):
		for month: int in [7, 8, 9, 10]:
			for day: int in [5, 15, 25]:
				var probe := _data(month, true, "dry%d" % index)
				probe.site.minute = Calendar.day_start_minute(Calendar.day_of(2, month, day)) + 600
				if Season.drought(probe):
					dry = probe
					break
			if dry != null: break
		if dry != null: break
	if not _ok(dry != null and Season.supply_factor(dry) == 0.7 and Season.dry_days(dry) >= 10 and Season.water_key(dry).ends_with("true"), "ten dry days make a drought: wells and intakes ×0.7"): return
	var wet_day := _data(7, true)
	wet_day.site.minute = Calendar.day_start_minute(Calendar.day_index(float(wet)) + 1) + 600
	if not _ok(Season.dry_days(wet_day) == 0 and Season.supply_factor(wet_day) == 1.0, "the day after rain is no drought"): return
	# Forecast.
	if not _ok(Season.forecast(july, false).size() == 1 and Season.forecast(july, true).size() == 4 and (Season.forecast(july, true)[0].weathers as Array).size() == 12, "the forecast: today, or four days with the 虞衡"): return
	# Autumn stores.
	var state := {"climate_enabled": true, "minute": Calendar.day_start_minute(Calendar.day_of(2, 10, 1)) + 600, "inventory": {"grain": 10},
		"housing": {"5": {}, "6": {}},
		"features": {"10": {"kind": "farm", "owner_faction": 1}, "11": {"kind": "lumber_camp", "owner_faction": 1}, "20": {"kind": "house", "owner_faction": 1}, "21": {"kind": "house", "owner_faction": 1}},
		"zones": [{"active": true, "action": "operate", "feature": "10"}, {"active": true, "action": "operate", "feature": "11"}],
		"households": {"20": {"job": {"feature": "11"}}, "21": {"job": {}}}}
	if not _ok(ResidentWork.autumn_store(state), "autumn with 10 grain for two residents stores food"): return
	var stored := ResidentWork.plan(state, 1, true)
	var plain := ResidentWork.plan(state, 1, false)
	if not _ok(stored == {"20": "10", "21": "10"} and plain == {"21": "10"}, "autumn puts every household on the farm; a normal plan keeps the existing job", [stored, plain]): return
	state.inventory.grain = 1000
	var full := ResidentWork.autumn_store(state)
	state.inventory.grain = 10
	state.minute = Calendar.day_start_minute(Calendar.day_of(2, 4, 1)) + 600
	var spring := ResidentWork.autumn_store(state)
	state.erase("climate_enabled")
	state.minute = Calendar.day_start_minute(Calendar.day_of(2, 10, 1)) + 600
	if not _ok(not full and not spring and not ResidentWork.autumn_store(state), "no autumn store with a full camp, in spring, or with climate off"): return
	if not _ok(Season.farm_factor_of_state({"climate_enabled": true, "minute": Calendar.day_start_minute(Calendar.day_of(2, 1, 5))}) == 0.6 and Season.farm_factor_of_state({"minute": 0}) == 1.0, "the catch-up reads the farm factor from the state"): return
	print("SITE_SEASON_TC8_PASS checks=", checks)
	quit(0)
