extends "res://scripts/tests/site_building_ui_test.gd"
## 技能系統 K1e 365-day balance run (spec reports/skill-system-plan.md V0.7 §5.2: K1 must pass a TC8 long run). The
## TC8 settlements (site_season_longrun_tc8_test) are run twice by the long-absence daily formula
## (SiteResidentWork.daily_production): the old way (everyone at 50, no growth) and with skills, every resident seeded
## as a new world seeds him (PersonSkills.initial: age from the TC7 seed, his household job's line, other lines 30),
## working at his speed and growing by the daily settlement. Checks:
## - with skills the settlements that lived through the year still do (no hungry day), and the farm's food over the
##   year stays within 35% of the old formula's;
## - every farmer's farming and every kiln worker's craft grows over the year, and nobody's other lines change;
## - prints both runs' season stocks, food made and the average farming before and after, for the balance report.
## Output: SITE_SKILLS_LONGRUN_K1E_PASS on success; quit(1) on failure.

const ResidentWork = preload("res://scripts/terrain_lab/site_resident_work.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Skills = preload("res://scripts/terrain_lab/person_skills.gd")
const Vital = preload("res://scripts/terrain_lab/site_vital.gd")
const FOODS := ["grain", "wild_food", "fish", "meat"]
const DAYS := 365 + 59
const SEED := 20261120

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SKILLS_LONGRUN_K1E OK ", checks, ": ", message)
		return true
	push_error("SITE_SKILLS_LONGRUN_K1E_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _food(state: Dictionary) -> int:
	var total := 0
	for food: String in FOODS: total += int(state.inventory.get(food, 0))
	return total

func _average(rows: Dictionary, ids: Array, line: String) -> float:
	if ids.is_empty(): return 0.0
	var total := 0.0
	for identity: int in ids: total += Skills.level(Skills.of(rows[identity]), line)
	return total / float(ids.size())

## A year and the next winter's first 59 days, as TC8; `skilled` seeds and trains every resident.
func _year(data: TerrainData, farm: String, kiln: String, houses: Array, farm_houses: int, opening: int, autumn: bool, skilled: bool) -> Dictionary:
	var state: Dictionary = data.site
	state["climate_enabled"] = true
	state["housing"] = {}
	state["households"] = {}
	var rows := {}
	var farmers: Array = []
	var smiths: Array = []
	var next_id := 9000
	for index: int in houses.size():
		var job: String = farm if index < farm_houses else kiln
		state.households[houses[index]] = {"job": {"feature": job}}
		for _member: int in range(2):
			state.housing[str(next_id)] = {"version": 1, "house_id": houses[index], "cell": 0}
			var age := 2026 - int(Vital.fresh(SEED, next_id, 2026).birth_year)
			var trade := "farming" if job == farm else "craft"
			rows[next_id] = {"person_id": next_id, "skills": Skills.initial({}, age, [trade], Skills.TRADE_RATE, SEED, next_id)}
			if job == farm: farmers.append(next_id)
			else: smiths.append(next_id)
			next_id += 1
	for food: String in FOODS: state.inventory[food] = 0
	state.inventory["grain"] = opening
	for item: String in ["clay", "wood", "seeds", "tools"]: state.inventory[item] = 1000000
	var skill := func(identity: int, line: String, seconds: float) -> float:
		if not rows.has(identity): return 1.0
		Skills.credit(rows[identity], line, seconds)
		return Skills.work_factor(rows[identity], line)
	var start := {"farming": _average(rows, farmers, "farming"), "craft": _average(rows, smiths, "craft"), "farmer_building": _average(rows, farmers, "building")}
	var residents: int = state.housing.size()
	var minutes := {}
	var hungry := 0
	var first_hungry := -1
	var stock := {}
	var made := 0
	for day: int in range(DAYS):
		state.minute = Calendar.day_start_minute(day) + 600
		var at := Calendar.date(float(state.minute))
		if int(at.day) == 1 and int(at.month) in [1, 3, 6, 9, 12]: stock["y%d-%d-1" % [int(at.year), int(at.month)]] = _food(state)
		if autumn and ResidentWork.autumn_store(state): ResidentWork.apply(state, ResidentWork.plan(state, 1, true))
		var before := _food(state)
		ResidentWork.daily_production(state, minutes, null, Callable(), skill if skilled else Callable())
		made += maxi(0, _food(state) - before)
		if skilled:
			for identity: int in rows: rows[identity]["skills"] = Skills.settle(Skills.of(rows[identity]), SEED, identity)
		var need := residents
		for food: String in FOODS:
			var eaten := mini(need, int(state.inventory.get(food, 0)))
			state.inventory[food] = int(state.inventory.get(food, 0)) - eaten
			need -= eaten
		if need > 0:
			hungry += 1
			if first_hungry < 0: first_hungry = day
	stock["end"] = _food(state)
	var finish := {"farming": _average(rows, farmers, "farming"), "craft": _average(rows, smiths, "craft"), "farmer_building": _average(rows, farmers, "building")}
	return {"hungry_days": hungry, "first_hungry": first_hungry, "stock": stock, "food_made": made, "start": start, "finish": finish}

func _run() -> void:
	var data := _building_fixture()
	var farm := _formal_feature(data, "farm", Vector2i(26, 14), Vector2i(6, 6))
	var kiln := _formal_feature(data, "kiln", Vector2i(14, 40))
	var houses: Array = []
	for index: int in range(10): houses.append(_formal_feature(data, "house", Vector2i(12 + index * 4, 26), Vector2i.ONE, {"variant": "small"}))
	data.site.capacity = 100000000
	data.site["zones"] = [{"active": true, "action": "operate", "feature": farm}, {"active": true, "action": "operate", "feature": kiln}]
	var seven := houses.slice(0, 7)
	var old_enough := _year(data, farm, kiln, seven, 1, 150, true, false)
	var enough := _year(data, farm, kiln, seven, 1, 150, true, true)
	print("SITE_SKILLS_LONGRUN_K1E enough old ", JSON.stringify(old_enough))
	print("SITE_SKILLS_LONGRUN_K1E enough skilled ", JSON.stringify(enough))
	if not _ok(int(old_enough.hungry_days) == 0 and int(enough.hungry_days) == 0, "1 farm house of 7 and 150 grain: no hungry day with skills either", [old_enough.hungry_days, enough.hungry_days]): return
	var ratio := float(enough.food_made) / maxf(1.0, float(old_enough.food_made))
	if not _ok(ratio > 0.65 and ratio < 1.35, "the farm's food over the year stays within 35% of the old formula's", [enough.food_made, old_enough.food_made, ratio]): return
	if not _ok(float(enough.finish.farming) > float(enough.start.farming) and float(enough.finish.craft) > float(enough.start.craft) and float(enough.finish.farmer_building) == float(enough.start.farmer_building), "farmers' farming and kiln workers' craft grow; other lines stay", [enough.start, enough.finish]): return
	var old_stored := _year(data, farm, kiln, houses, 1, 520, true, false)
	var stored := _year(data, farm, kiln, houses, 1, 520, true, true)
	var short := _year(data, farm, kiln, houses, 1, 520, false, true)
	print("SITE_SKILLS_LONGRUN_K1E stored old ", JSON.stringify(old_stored))
	print("SITE_SKILLS_LONGRUN_K1E stored skilled ", JSON.stringify(stored), " short skilled ", JSON.stringify(short))
	if not _ok(int(old_stored.hungry_days) == 0 and int(stored.hungry_days) == 0, "1 farm house of 10 with the autumn store: no hungry day with skills either", [old_stored.hungry_days, stored.hungry_days]): return
	data.site.erase("housing")
	data.site.erase("households")
	data.site.erase("climate_enabled")
	print("SITE_SKILLS_LONGRUN_K1E_PASS checks=", checks)
	quit(0)
