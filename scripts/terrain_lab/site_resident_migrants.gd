extends RefCounted
## 平民 C4c (reports/civilian-site-behavior-plan.md §4.7): migrants. Every 30th game day on the active crowd Site, a
## settlement with free beds, food for 30 days and calm residents (mean discontent below 40) draws one migrant household
## from the Region: up to MAX_HOUSEHOLD new people (ids from the world allocator) are born into the residents' team
## (CrowdSite.add_new_person) as civilians at the free door cells of one house and registered there. This is the only
## population growth (no births yet). Food for 30 days: the camp's grain, fish, meat and wild food reach
## (residents + newcomers) x 30. The new rows copy a current resident's row (look, troop), with their own id, name,
## items and no history.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Households = preload("res://scripts/terrain_lab/site_households.gd")
const Mood = preload("res://scripts/terrain_lab/site_resident_mood.gd")
const ProduceTax = preload("res://scripts/terrain_lab/site_produce_tax.gd")

const EVERY_DAYS := 30
const CALM_BELOW := 40
const FOOD_DAYS := 30
const MAX_HOUSEHOLD := 4
const FOODS := ["grain", "fish", "meat", "wild_food"]

## The residents' team: the team of the lowest registered resident present here ({} when none).
static func residents_team(lab: Variant) -> Dictionary:
	var ids: Array = lab.terrain.site.get("housing", {}).keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for raw: String in ids:
		for team: Dictionary in lab.crowd_site.teams:
			if not bool(team.get("departed", false)) and team.get("person_ids", []).has(int(raw)): return team
	return {}

## Free door cells per house of the settlement's faction: {house_id: [cell index]}.
static func free_beds(data: TerrainData) -> Dictionary:
	var owner := int(data.site.get("settlement", {}).get("owner_faction", -1)) if data.site.get("settlement") is Dictionary else -1
	var taken := {}
	for registered: Variant in data.site.get("housing", {}).values():
		if registered is Dictionary: taken[int(registered.get("cell", -1))] = true
	var result := {}
	var keys: Array = data.site.get("features", {}).keys()
	keys.sort()
	for key: String in keys:
		var feature: Dictionary = data.site.features[key]
		if int(feature.get("owner_faction", -2)) != owner or not Runtime.feature_usable(feature, "lodging"): continue
		var layout: Dictionary = Runtime.house_layout(data, key)
		if not layout.get("ok", false) or not bool(layout.get("complete", false)): continue
		var free: Array = []
		for slot: Variant in layout.slots:
			if not taken.has(int(slot)): free.append(int(slot))
		if not free.is_empty(): result[key] = free
	return result

static func food(data: TerrainData) -> int:
	var total := 0
	for item: String in FOODS: total += int(data.site.get("inventory", {}).get(item, 0))
	return total

## The household that arrives today: {house_id, cells} or {} (with `reason`).
static func judge(controller: Variant, day: int) -> Dictionary:
	var lab: Variant = controller.lab
	if day % EVERY_DAYS != 0: return {"reason": "not_today"}
	if ProduceTax.settlement_ref(lab.terrain).is_empty(): return {"reason": "no_settlement"}
	var residents: Array = lab.terrain.site.get("housing", {}).keys()
	var total := 0
	var counted := 0
	for raw: Variant in residents:
		var person: Dictionary = controller.person_actions._person(int(raw), false)
		if person.is_empty() or person.get("body") == null: continue
		total += Mood.g_of(lab.terrain, person.body)
		counted += 1
	if counted > 0 and float(total) / float(counted) >= CALM_BELOW: return {"reason": "unrest"}
	var beds := free_beds(lab.terrain)
	if beds.is_empty(): return {"reason": "no_beds"}
	var best := ""
	for house: String in beds:
		if best.is_empty() or beds[house].size() > beds[best].size(): best = house
	var cells: Array = beds[best].slice(0, MAX_HOUSEHOLD)
	if food(lab.terrain) < (counted + cells.size()) * FOOD_DAYS: return {"reason": "no_food"}
	return {"house_id": best, "cells": cells}

## Runs today's judgement on the active crowd Site. Returns {arrived: [ids], reason}.
static func day(controller: Variant, today: int) -> Dictionary:
	var lab: Variant = controller.lab
	if lab.crowd_site == null or not lab.crowd_site.active: return {"arrived": [], "reason": "no_crowd"}
	var verdict := judge(controller, today)
	if not verdict.has("house_id"): return {"arrived": [], "reason": str(verdict.get("reason", ""))}
	return arrive(controller, str(verdict.house_id), verdict.cells)

## A household of len(`cells`) new people is born into the residents' team and registered at `cells` of `house_id`.
static func arrive(controller: Variant, house_id: String, cells: Array) -> Dictionary:
	var lab: Variant = controller.lab
	var team := residents_team(lab)
	if team.is_empty(): return {"arrived": [], "reason": "no_residents_team"}
	var roster: Dictionary = lab.crowd_site.native_roster(int(team.team_id))
	var template: Dictionary = {}
	for row: Dictionary in roster.get("units", []):
		if lab.terrain.site.get("housing", {}).has(str(int(row.person_id))): template = row
	if template.is_empty(): return {"arrived": [], "reason": "no_template"}
	var ids: Array[int] = lab._allocate_army_person_ids(cells.size())
	if ids.size() != cells.size(): return {"arrived": [], "reason": "no_ids"}
	var arrived: Array = []
	for index: int in cells.size():
		var identity := ids[index]
		var row: Dictionary = template.duplicate(true)
		for field: String in ["social", "social_state", "vital", "reputation", "combat_record", "work_task", "family"]: row.erase(field)
		row["person_id"] = identity
		row["name"] = "流民%d" % identity
		row["hp"] = 100.0
		row["cargo"] = {}
		row["item_state"] = Runtime.new_item_state("person:%d" % identity)
		row["military_role"] = "civilian"
		var cell: Vector2i = lab.terrain.cell_from_index(int(cells[index]))
		var born: Dictionary = lab.crowd_site.add_new_person(int(team.team_id), row, Vector2(cell) + Vector2(0.5, 0.5))
		if not born.ok: break
		if not lab.terrain.site.has("housing"): lab.terrain.site["housing"] = {}
		lab.terrain.site.housing[str(identity)] = {"version": 1, "house_id": house_id, "cell": int(cells[index])}
		arrived.append(identity)
	Households.reconcile(lab.terrain.site)
	if not arrived.is_empty() and lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("流民一戶 %d 人遷入" % arrived.size())
	return {"arrived": arrived, "reason": "" if arrived.size() == cells.size() else "partial"}
