extends RefCounted
## Household work (平民行為 C2, reports/civilian-site-behavior-plan.md §4.3; Q2 A: the settlement's 戶籍 duty assigns
## work, the AI fills it while the duty AI is on). Pure rules over a Site state:
## - a household's main job is a completed feature of its faction with an active "operate" work zone;
## - plan() keeps every valid job and gives each household without one the candidate with the fewest households, food
##   producers (FOOD_KINDS) first, then the lowest feature id; one job per household, all members share it;
## - excluded_for() names every other operate feature, so the existing SiteWorkTeam choice (SiteRuntime.choose_task)
##   sends a resident only to his own household's job (wild harvest and hauling rules are unchanged).
## The controller checks the duty's authority and runs the plan; SiteResidentSchedule hands residents to SiteWorkTeam in
## the work phases and back home in the home phases.
const Households = preload("res://scripts/terrain_lab/site_households.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Season = preload("res://scripts/terrain_lab/site_season.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
## 時間與氣候 TC8 (§7 risk 4): an NPC settlement stores food for the winter. In autumn, while the camp holds less food
## than WINTER_DAYS of one ration per registered resident, its 戶曹 puts every household on a food job.
const WINTER_DAYS := 90
const FOOD_ITEMS := ["grain", "wild_food", "fish", "meat"]
const FOOD_KINDS := ["farm"]
const DUTY := "settlement.registry"
const ResidentLife = preload("res://scripts/terrain_lab/site_resident_life.gd") # 產出三成歸戶
const PersonSkills = preload("res://scripts/terrain_lab/person_skills.gd") # 技能 K1d: the most skilled households first.

## Features of `faction` with an active operate zone, food producers first, then by id.
static func job_features(state: Dictionary, faction: int) -> Array:
	var keys := {}
	for zone: Variant in state.get("zones", []):
		if not zone is Dictionary or not bool(zone.get("active", false)) or str(zone.get("action", "")) != "operate": continue
		var key := str(zone.get("feature", ""))
		var feature: Variant = state.get("features", {}).get(key)
		if feature is Dictionary and int(feature.get("owner_faction", -1)) == faction: keys[key] = true
	var result: Array = keys.keys()
	result.sort_custom(func(a: String, b: String) -> bool:
		var food_a := str(state.features[a].get("kind", "")) in FOOD_KINDS
		var food_b := str(state.features[b].get("kind", "")) in FOOD_KINDS
		if food_a != food_b: return food_a
		return int(a) < int(b))
	return result

## Households whose house belongs to `faction`, sorted by house id.
static func households_of(state: Dictionary, faction: int) -> Array:
	var result: Array = []
	for house_id: String in state.get("households", {}):
		var house: Variant = state.get("features", {}).get(house_id)
		if house is Dictionary and int(house.get("owner_faction", -1)) == faction: result.append(house_id)
	result.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	return result

## {house_id: feature} for the households of `faction` that need a new job. Existing valid jobs are kept and counted.
## 技能 K1d (§7): with `skill` (identity, line -> proficiency), each open place goes to the jobless household with the
## highest average proficiency in that job's line (ties: lowest house id); without it, house id order as before.
static func plan(state: Dictionary, faction: int, food_first: bool = false, skill: Callable = Callable()) -> Dictionary:
	var candidates := job_features(state, faction)
	var result := {}
	if candidates.is_empty(): return result
	if food_first:
		var food: Array = candidates.filter(func(key: String) -> bool: return str(state.features[key].get("kind", "")) in FOOD_KINDS)
		if not food.is_empty(): candidates = food
	var taken := {}
	for key: String in candidates: taken[key] = 0
	var houses := households_of(state, faction)
	for house_id: String in houses:
		var current := str(state.households[house_id].get("job", {}).get("feature", ""))
		if taken.has(current): taken[current] = int(taken[current]) + 1
	var open: Array = []
	for house_id: String in houses:
		if not taken.has(str(state.households[house_id].get("job", {}).get("feature", ""))): open.append(house_id)
	while not open.is_empty():
		var best := str(candidates[0])
		for key: String in candidates:
			if int(taken[key]) < int(taken[best]): best = key
		var pick := 0
		if skill.is_valid():
			var line := PersonSkills.line_for_task(state, {"action": "operate", "target": "feature:" + best})
			var top := -1.0
			for index: int in open.size():
				var score := _household_skill(state, str(open[index]), line, skill)
				if score > top:
					top = score
					pick = index
		var house_id: String = open[pick]
		open.remove_at(pick)
		taken[best] = int(taken[best]) + 1
		result[house_id] = best
	return result

## The average proficiency of a household's members in `line` (0 with no line or no member).
static func _household_skill(state: Dictionary, house_id: String, line: String, skill: Callable) -> float:
	var members: Array = Households.members(state, house_id)
	if line.is_empty() or members.is_empty(): return 0.0
	var total := 0.0
	for identity: Variant in members: total += float(skill.call(int(identity), line))
	return total / float(members.size())

## TC8: autumn, climate on, and the camp holds less than WINTER_DAYS rations per registered resident.
static func autumn_store(state: Dictionary) -> bool:
	if state.get("climate_enabled") != true or str(Calendar.date(float(state.get("minute", 0))).season) != "autumn": return false
	var food := 0
	for item: String in FOOD_ITEMS: food += int(state.get("inventory", {}).get(item, 0))
	return food < state.get("housing", {}).size() * WINTER_DAYS

## Applies a plan through Households.set_job; returns the number of households changed.
static func apply(state: Dictionary, planned: Dictionary) -> int:
	var changed := 0
	var keys: Array = planned.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for house_id: String in keys:
		if bool(Households.set_job(state, house_id, str(planned[house_id])).get("changed", false)): changed += 1
	return changed

## The job feature of a person's household, "" when he has none (or it is no longer an active operate feature).
static func job_of(state: Dictionary, identity: int) -> String:
	var house_id := Households.house_of(state, identity)
	if house_id.is_empty(): return ""
	var feature := str(state.get("households", {}).get(house_id, {}).get("job", {}).get("feature", ""))
	var house: Variant = state.get("features", {}).get(house_id)
	if feature.is_empty() or not house is Dictionary or not job_features(state, int(house.get("owner_faction", -1))).has(feature): return ""
	return feature

## SiteRuntime.choose_task exclusions for a resident with a job: every other operate feature.
static func excluded_for(state: Dictionary, identity: int) -> Dictionary:
	var job := job_of(state, identity)
	var result := {}
	if job.is_empty(): return result
	for zone: Variant in state.get("zones", []):
		if zone is Dictionary and str(zone.get("action", "")) == "operate" and str(zone.get("feature", "")) != job: result["feature:" + str(zone.get("feature", ""))] = true
	return result


## Long-absence catch-up (Nekki 11/16 A): one game day of household work, by daily averages. Each living registered
## member puts WORK_HOURS into his household's job; `minutes` (house id → minutes, the caller's runtime carry) collects
## them and each full recipe cycle becomes one batch: the inputs are paid from the camp stock, the outputs added while
## the camp has room, as long as the camp has a tool. Returns the batches made.
const WORK_HOURS := 10.0
## `factor` (平民 C6): identity → work speed of a member (SiteResidentMood.work_factor); none = everyone at full speed.
## `skill` (技能 K1e): (identity, line, seconds) → speed; it credits the member's day on his job's line and returns his
## speed on it (PersonSkills.work_factor). None = no growth and full speed, the old formula.
static func daily_production(state: Dictionary, minutes: Dictionary, data: TerrainData = null, factor: Callable = Callable(), skill: Callable = Callable()) -> int:
	var made := 0
	var stock: Dictionary = state.get("inventory", {})
	# 居民吃飯 L1: where a settlement feeds its people a field gives work to as many as it has places (as on the live step).
	# Without its map (the projection of a Site nobody opened, RegionBanditFormula) a place is a FARM_WORK_SIDE square.
	var meals: bool = state.get("settlement") is Dictionary and int(state.settlement.get("meals", 0)) == 1
	var places := {}
	var houses: Array = state.get("households", {}).keys()
	houses.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for house_id: String in houses:
		var feature_key := str(state.households[house_id].get("job", {}).get("feature", ""))
		var feature: Dictionary = state.get("features", {}).get(feature_key, {})
		if feature.is_empty() or str(feature.get("stage", "")) != "complete" or not Runtime.feature_usable(feature): continue
		var recipe := Runtime.feature_recipe(feature)
		if not recipe.has("cycle") or float(recipe.cycle) <= 0.0 or not recipe.get("output") is Dictionary: continue
		var members: Array = Households.members(state, house_id)
		if members.is_empty(): continue
		var workers := 0.0
		var line := PersonSkills.line_for_task(state, {"action": "operate", "target": "feature:" + feature_key}) if skill.is_valid() else ""
		for identity: Variant in members:
			var speed := float(factor.call(int(identity))) if factor.is_valid() else 1.0
			if not line.is_empty(): speed *= float(skill.call(int(identity), line, WORK_HOURS * 3600.0))
			workers += speed
		if meals:
			if not places.has(feature_key): places[feature_key] = float(Runtime.feature_work_slots(data, feature).size()) if data != null else maxf(1.0, ceilf(float(feature.get("cells", []).size()) / float(Runtime.FARM_WORK_SIDE * Runtime.FARM_WORK_SIDE)))
			workers = minf(workers, float(places[feature_key]))
			places[feature_key] = float(places[feature_key]) - workers
		var season := Season.farm_factor_of_state(state) if str(feature.get("kind", "")) in Runtime.FARM_KINDS else 1.0 # TC8
		minutes[house_id] = float(minutes.get(house_id, 0.0)) + workers * WORK_HOURS * 60.0 * season
		while float(minutes[house_id]) >= float(recipe.cycle):
			if not Runtime.can_pay(stock, {"tools": 1}) or not Runtime.can_pay(stock, recipe.get("input", {})): break
			var room := int(state.get("capacity", 0)) - Runtime.inventory_size(stock)
			var size := 0
			for item: String in recipe.output: size += int(recipe.output[item])
			if room < size: break
			for item: String in recipe.get("input", {}): stock[item] = int(stock.get(item, 0)) - int(recipe.input[item])
			# 軍餉與稅收 P5: the batch pays the settlement's production tax as a published batch would.
			# 產出三成歸戶: the household keeps its share of the food first (SiteResidentLife.share_house); the rest is taxed.
			var kept: Dictionary = ResidentLife.share_house(state, house_id, recipe.output) if meals else recipe.output
			if data != null and state.has("finance"): kept = (load("res://scripts/terrain_lab/site_produce_tax.gd") as Script).call("levy", data, feature_key, feature, kept)
			for item: String in kept: stock[item] = int(stock.get(item, 0)) + int(kept[item])
			minutes[house_id] = float(minutes[house_id]) - float(recipe.cycle)
			made += 1
	return made
