extends "res://scripts/tests/site_building_ui_test.gd"
## 時間與氣候 TC8 long run (reports/day-weather-season-plan.md §7 risk 4; reports/time-and-climate-plan.md §1 rule 5).
## A year of a settlement by the long-absence daily formula (SiteResidentWork.daily_production with the season's farm
## factor) and one ration per resident a day, starting 1 January (winter). Real farm and kiln recipes. Checks:
## - a settlement with enough farmers (1 farm house of 7, 14 residents) and 150 grain at the start lives through the
##   first 59 winter days and the whole year without a hungry day; its stock falls in winter and rises in summer;
## - with only 50 grain at the start the same settlement goes hungry before 1 March (the plan's opening-stock warning);
## - a settlement whose farms just feed it in spring (1 farm house of 10, 20 residents, 520 grain) starves in the next
##   winter unless its 戶曹 stores food in autumn (SiteResidentWork.autumn_store → every household on the farm).
## The run covers a year and the next winter's first 59 days.
## Prints the stock at each season start. Output: SITE_SEASON_LONGRUN_TC8_PASS on success; quit(1) on failure.

const ResidentWork = preload("res://scripts/terrain_lab/site_resident_work.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const FOODS := ["grain", "wild_food", "fish", "meat"]
## A year and the next winter's first 59 days (to 1 March of year 2).
const DAYS := 365 + 59
var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SEASON_LONGRUN_TC8 OK ", checks, ": ", message)
		return true
	push_error("SITE_SEASON_LONGRUN_TC8_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

## A year: {hungry_days, first_hungry, stock: {"m-d": food}}.
func _year(data: TerrainData, farm: String, kiln: String, houses: Array, farm_houses: int, opening: int, autumn: bool) -> Dictionary:
	var state: Dictionary = data.site
	state["climate_enabled"] = true
	state["housing"] = {}
	state["households"] = {}
	var next_id := 9000
	for index: int in houses.size():
		state.households[houses[index]] = {"job": {"feature": farm if index < farm_houses else kiln}}
		for _member: int in range(2):
			state.housing[str(next_id)] = {"version": 1, "house_id": houses[index], "cell": 0}
			next_id += 1
	for food: String in FOODS: state.inventory[food] = 0
	state.inventory["grain"] = opening
	for item: String in ["clay", "wood", "seeds", "tools"]: state.inventory[item] = 1000000
	var residents: int = state.housing.size()
	var minutes := {}
	var hungry := 0
	var first_hungry := -1
	var stock := {}
	for day: int in range(DAYS):
		state.minute = Calendar.day_start_minute(day) + 600
		var at := Calendar.date(float(state.minute))
		if int(at.day) == 1 and int(at.month) in [1, 3, 6, 9, 12]: stock["y%d-%d-1" % [int(at.year), int(at.month)]] = _food(state)
		if autumn and ResidentWork.autumn_store(state): ResidentWork.apply(state, ResidentWork.plan(state, 1, true))
		ResidentWork.daily_production(state, minutes)
		var need := residents
		for food: String in FOODS:
			var eaten := mini(need, int(state.inventory.get(food, 0)))
			state.inventory[food] = int(state.inventory.get(food, 0)) - eaten
			need -= eaten
		if need > 0:
			hungry += 1
			if first_hungry < 0: first_hungry = day
	stock["end"] = _food(state)
	return {"hungry_days": hungry, "first_hungry": first_hungry, "stock": stock}

func _food(state: Dictionary) -> int:
	var total := 0
	for food: String in FOODS: total += int(state.inventory.get(food, 0))
	return total

func _run() -> void:
	var data := _building_fixture()
	var farm := _formal_feature(data, "farm", Vector2i(26, 14), Vector2i(6, 6))
	var kiln := _formal_feature(data, "kiln", Vector2i(14, 40))
	var houses: Array = []
	for index: int in range(10): houses.append(_formal_feature(data, "house", Vector2i(12 + index * 4, 26), Vector2i.ONE, {"variant": "small"}))
	data.site.capacity = 100000000
	# The 戶曹 plans among operate jobs (SiteResidentWork.job_features reads the active operate zones).
	data.site["zones"] = [{"active": true, "action": "operate", "feature": farm}, {"active": true, "action": "operate", "feature": kiln}]
	var seven := houses.slice(0, 7)
	var enough := _year(data, farm, kiln, seven, 1, 150, true)
	print("SITE_SEASON_LONGRUN_TC8 enough ", JSON.stringify(enough))
	if not _ok(int(enough.hungry_days) == 0, "1 farm house of 7 and 150 grain: no hungry day all year", enough): return
	if not _ok(int(enough.stock["y1-3-1"]) < 150 and int(enough.stock["y1-9-1"]) > int(enough.stock["y1-3-1"]), "the stock falls in winter and rises through spring and summer", enough.stock): return
	var thin := _year(data, farm, kiln, seven, 1, 50, true)
	print("SITE_SEASON_LONGRUN_TC8 thin ", JSON.stringify(thin))
	if not _ok(int(thin.first_hungry) >= 0 and int(thin.first_hungry) < Calendar.day_of(1, 3, 1), "50 grain at the start goes hungry before 1 March", thin): return
	var short := _year(data, farm, kiln, houses, 1, 520, false)
	var stored := _year(data, farm, kiln, houses, 1, 520, true)
	print("SITE_SEASON_LONGRUN_TC8 short ", JSON.stringify(short), " stored ", JSON.stringify(stored))
	if not _ok(int(short.hungry_days) > 0 and int(short.first_hungry) >= 365 and int(stored.hungry_days) == 0, "1 farm house of 10 (farms just feed it in spring) starves in the next winter without the autumn store, not with it", [short.first_hungry, short.hungry_days, stored.hungry_days]): return
	data.site.erase("housing")
	data.site.erase("households")
	data.site.erase("climate_enabled")
	print("SITE_SEASON_LONGRUN_TC8_PASS checks=", checks)
	quit(0)
