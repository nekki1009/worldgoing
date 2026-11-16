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
const FOOD_KINDS := ["farm"]
const DUTY := "settlement.registry"

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
static func plan(state: Dictionary, faction: int) -> Dictionary:
	var candidates := job_features(state, faction)
	var result := {}
	if candidates.is_empty(): return result
	var taken := {}
	for key: String in candidates: taken[key] = 0
	var houses := households_of(state, faction)
	for house_id: String in houses:
		var current := str(state.households[house_id].get("job", {}).get("feature", ""))
		if taken.has(current): taken[current] = int(taken[current]) + 1
	for house_id: String in houses:
		var current := str(state.households[house_id].get("job", {}).get("feature", ""))
		if taken.has(current): continue
		var best := str(candidates[0])
		for key: String in candidates:
			if int(taken[key]) < int(taken[best]): best = key
		taken[best] = int(taken[best]) + 1
		result[house_id] = best
	return result

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
static func daily_production(state: Dictionary, minutes: Dictionary) -> int:
	var made := 0
	var stock: Dictionary = state.get("inventory", {})
	var houses: Array = state.get("households", {}).keys()
	houses.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for house_id: String in houses:
		var feature_key := str(state.households[house_id].get("job", {}).get("feature", ""))
		var feature: Dictionary = state.get("features", {}).get(feature_key, {})
		if feature.is_empty() or str(feature.get("stage", "")) != "complete" or not Runtime.feature_usable(feature): continue
		var recipe := Runtime.feature_recipe(feature)
		if not recipe.has("cycle") or float(recipe.cycle) <= 0.0 or not recipe.get("output") is Dictionary: continue
		var workers := Households.members(state, house_id).size()
		if workers <= 0: continue
		minutes[house_id] = float(minutes.get(house_id, 0.0)) + float(workers) * WORK_HOURS * 60.0
		while float(minutes[house_id]) >= float(recipe.cycle):
			if not Runtime.can_pay(stock, {"tools": 1}) or not Runtime.can_pay(stock, recipe.get("input", {})): break
			var room := int(state.get("capacity", 0)) - Runtime.inventory_size(stock)
			var size := 0
			for item: String in recipe.output: size += int(recipe.output[item])
			if room < size: break
			for item: String in recipe.get("input", {}): stock[item] = int(stock.get(item, 0)) - int(recipe.input[item])
			for item: String in recipe.output: stock[item] = int(stock.get(item, 0)) + int(recipe.output[item])
			minutes[house_id] = float(minutes[house_id]) - float(recipe.cycle)
			made += 1
	return made
