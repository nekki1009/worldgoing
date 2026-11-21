extends SceneTree
## CIV-A4 / CA-05 (output/civilian_atlas_plan_20261119/PLAN.md; Nekki 2026-11-20 A) with a real house and the household
## work path, on a real crowd Site, GPU (visual). A house of the settlement's faction is built and completed; two
## unarmed civilians are born at its doors and registered there; the 戶籍 decider (the head) gives the household a farm.
## Checks:
## - the daily dressing gives both the civilian look with the straw hat (a farming household) on a civilian kit;
## - a work phase: handed to the work by their team's commander, they carry or lift; the native presentation takes it;
## - the evening: off the work, standing at their own doors they sit;
## - the night: inside the house (native absent, kind 5): no activity, not on the field;
## - the morning: out at their doors, they fetch water;
## The residents stand in the player's team: the schedule's own hand-over (leaderless residents) is site_resident_work_test's,
## and a civilian alone captains his team and is drawn as a live body, outside the atlas batch.
## - the dressed residents and the real house pass the Site save rules (the data-only farm and the stand-in settlement
##   taken out first).
## Output: SITE_CIVILIAN_LIFE_VISUAL_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Dress = preload("res://scripts/terrain_lab/civilian_dress.gd")
const Schedule = preload("res://scripts/terrain_lab/site_resident_schedule.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Households = preload("res://scripts/terrain_lab/site_households.gd")
const SiteHousingProbe = preload("res://scripts/terrain_lab/site_housing.gd") # diagnostics of the at-home rule
const START := Vector2i(1170, 13252)
const FARM := "9101"

var checks := 0
var _finished := false
var _build_refusals := {}

func _initialize() -> void:
	create_timer(420.0).timeout.connect(func() -> void: _fail("420-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	printerr("SITE_CIVILIAN_LIFE_VISUAL_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_CIVILIAN_LIFE_VISUAL OK ", checks, ": ", message)
		return true
	return _fail(message, detail)

func _minute_of(phase: String, after: int = 0) -> int:
	for minute: int in range(after, 1440):
		if Schedule.phase_at(minute, 50) == phase: return minute
	return -1

## Builds and completes a house of `faction` near `near` (the formal build path, completed by the Site worker).
func _house(data: TerrainData, near: Vector2i, faction: int) -> String:
	var settings := {"layout_version": 1, "quarter": 0, "owner_faction": faction, "variant": "long"}
	# The camp's own stock pays the house (wood 8, stone 4) and the work needs tools.
	for item: String in ["wood", "stone"]: data.site.inventory[item] = int(data.site.inventory.get(item, 0)) + 20
	data.site.inventory["tools"] = maxi(int(data.site.inventory.get("tools", 0)), 2)
	# The start Site is real terrain: search outward for level ground (a house needs its foundation), ring by ring.
	for radius: int in range(4, 96, 3):
		for dy: int in range(-radius, radius + 1, 3):
			for dx: int in range(-radius, radius + 1, 3):
				if maxi(absi(dx), absi(dy)) != radius - posmod(radius - 4, 3) and maxi(absi(dx), absi(dy)) < radius - 2: continue # this ring only
				var anchor := near + Vector2i(dx, dy)
				if not data.contains(anchor): continue
				var placement := SiteRuntime.building_cells(data, "house", anchor, Vector2i.ONE, settings)
				if not placement.ok:
					_build_refusals["cells:" + str(placement.get("code", ""))] = int(_build_refusals.get("cells:" + str(placement.get("code", "")), 0)) + 1
					continue
				# Test-only ground preparation: the start Site's ground is below a house's foundation (35); firm the
				# chosen plot, then build through the formal path.
				var firmed := {}
				for cell: Variant in placement.cells:
					firmed[int(cell)] = int(data.foundation[int(cell)])
					data.foundation[int(cell)] = maxi(int(data.foundation[int(cell)]), 50)
				var built := SiteRuntime.request_build(data, "house", placement.cells, Callable(), settings)
				if not built.ok:
					for cell: int in firmed: data.foundation[cell] = int(firmed[cell])
				if not built.ok:
					_build_refusals["build:" + str(built.get("code", "")) + ":" + str(built.get("message", ""))] = 1
					continue
				var key := str(built.feature)
				var feature: Dictionary = data.site.features[key]
				var entrance: int = int(feature.get("pending_build", feature).get("entrance", feature.entrance))
				SiteRuntime.assign_task(data, SiteRuntime.ok("", {"target": "feature:" + key, "action": "construct", "cell": entrance}))
				data.site.worker.cell = entrance
				data.site.worker.mode = "work"
				SiteRuntime.advance(data, float(feature.get("pending_build", feature).work) + 1.0, true, false, Callable(), Callable(), Callable(), SiteRuntime.CARRY_CAPACITY, SiteRuntime.CARRY_CAPACITY, 1.0, faction) # the worker of the managing faction
				data.site.worker.mode = "idle"
				if str(feature.stage) == "complete" and SiteRuntime.house_layout(data, key).ok: return key
				_build_refusals["stage:" + str(feature.stage) + ":" + str(SiteRuntime.house_layout(data, key).get("code", "")) + ":" + str(data.site.worker.get("status", ""))] = 1
				return ""
	return ""

func _clip(activity: Variant, person: int) -> String:
	return str(activity._choice.get(person, {}).get("clip", ""))

func _run() -> void:
	if not _check(DisplayServer.get_name() != "headless", "GPU required"): return
	if not _check(RegionEntry.request_new_world(START, {}, "平民生活世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	for _frame: int in range(1200):
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _check(lab != null, "the new world opens", RegionEntry.menu_message): return
	for _frame: int in range(5): await process_frame
	var controller: SiteController = lab.site_controller
	var crowd: Variant = lab.crowd_site
	var data: TerrainData = lab.terrain
	var player := int(lab.controlled_person_id())
	var team: Dictionary = {}
	for row_team: Dictionary in crowd.teams:
		if not bool(row_team.get("departed", false)) and row_team.get("person_ids", []).has(player): team = row_team
	var own := int(team.faction)
	var template: Dictionary = {}
	for row: Dictionary in crowd.native_roster(int(team.team_id)).get("units", []):
		if int(row.person_id) != player: template = row
	var house := _house(data, crowd.combat_target(player).cell, own)
	if not _check(not house.is_empty(), "a house of the faction is built and completed", _build_refusals): return
	var layout: Dictionary = SiteRuntime.house_layout(data, house)
	if not _check(layout.ok and layout.slots.size() >= 2, "the house has two door rest cells", layout): return
	data.site["settlement"] = {"version": 1, "settlement_id": "life_village", "center_id": "c", "level": 2, "name": "測試村", "owner_faction": own,
		"offices": SiteOffices.default_offices("settlement", player, false), "fall_record": SiteSettlement.empty_fall_record()}
	var ids: Array[int] = lab._allocate_army_person_ids(2)
	var residents: Array[int] = []
	if not data.site.has("housing"): data.site["housing"] = {}
	for index: int in ids.size():
		var row: Dictionary = template.duplicate(true)
		for field: String in ["social", "social_state", "vital", "reputation", "combat_record", "work_task", "family", "skills"]: row.erase(field)
		row["person_id"] = ids[index]
		row["name"] = "居民%d" % ids[index]
		row["hp"] = 100.0
		row["cargo"] = {}
		row["item_state"] = SiteRuntime.new_item_state("person:%d" % ids[index])
		row["military_role"] = "civilian"
		var door: Vector2i = data.cell_from_index(int(layout.slots[layout.slots.size() - 1 - index]))
		var made: Dictionary = crowd.add_new_person(int(team.team_id), row, Vector2(door) + Vector2(0.5, 0.5))
		if not _check(made.ok, "resident %d is born at a door" % ids[index], made): return
		residents.append(ids[index])
		data.site.housing[str(ids[index])] = {"version": 1, "house_id": house, "cell": int(layout.slots[layout.slots.size() - 1 - index])}
	Households.reconcile(data.site)
	# A data-only farm of the faction near the house (the household job stand-in, as site_resident_work_test).
	var job_cell := data.index(data.cell_from_index(int(layout.slots[0])) + Vector2i(3, 0))
	data.site.features[FARM] = {"kind": "farm", "owner_faction": own, "cells": [job_cell], "stage": "complete", "entrance": job_cell, "solid": false}
	data.site.zones.append({"cells": [job_cell], "kind": -1, "action": "operate", "feature": FARM, "active": true})
	var job: Dictionary = controller.assign_household_job(house, FARM, player)
	if not _check(job.ok, "the head gives the household the farm", job): return
	for _frame: int in range(3): await process_frame
	var dressed: Dictionary = controller.dress_residents()
	for _frame: int in range(5): await process_frame
	var activity: Variant = crowd._civilian_activity
	for person: int in residents:
		var index := int(crowd._index_by_id[person])
		var kit := int(crowd._kit_ids[index])
		if not _check(Dress.is_hatted(crowd._records[person].appearance) and kit >= 0 and activity._tracks.has(kit), "resident %d wears the civilian look with the straw hat (a farming household) on a civilian kit" % person, [dressed, crowd._records[person].appearance.parts]): return
	var day := int(Calendar.day_index(float(data.site.minute))) + 1
	var day_start := Calendar.day_start_minute(day)
	# Evening: standing at their own doors they sit. Their team's formation pulls them to its slots, so each steps in and
	# out of his house (C1c: he comes out at his own door cell) and the check runs before the formation moves him.
	data.site.minute = day_start + _minute_of("evening") + 1
	for person: int in residents: # all inside first, so no one stands on another's door when they come out
		if not _check(crowd.home_enter(person), "resident %d steps into his house" % person): return
	for person: int in residents:
		# home_leave returns him where he went in; the fixture brings him out exactly at his registered door (the same
		# native return op, aimed at the door).
		var door: Vector2i = data.cell_from_index(int(data.site.housing[str(person)].cell))
		var out := bool(crowd.crowd.site_person_return(int(crowd._index_by_id[person]), int(crowd._owner_by_id[person].formation_index), float(door.x) + 0.5, float(door.y) + 0.5))
		if not _check(out and not crowd.is_at_home(person) and data.index(controller.person_actions._person(person, false).cell) == int(data.site.housing[str(person)].cell), "resident %d steps out at his own door" % person): return
	activity._decide(crowd)
	var home := residents.all(func(person: int) -> bool: return _clip(activity, person) == "civilian_sit")
	if not _check(home, "standing at their own doors in the evening they sit", residents.map(func(person: int) -> Dictionary:
		var registered: Dictionary = SiteHousingProbe.relation(lab, person)
		var layout_now: Dictionary = SiteRuntime.house_layout(data, str(registered.get("house_id", "")))
		var feature: Dictionary = data.site.features.get(str(registered.get("house_id", "")), {})
		var formation: Dictionary = SiteHousingProbe._formation(lab, controller.person_actions._person(person, false))
		return {"id": person, "attends": SiteHousingProbe._attends(lab, person), "layout": layout_now.get("ok"), "complete": layout_now.get("complete"),
			"lodging": SiteRuntime.feature_usable(feature, "lodging"), "slot": layout_now.get("slots", []).has(int(registered.get("cell", -1))),
			"order": formation.get("order"), "busy": controller.person_actions._jobs.has(str(person)), "ready": controller.person_actions._ready(controller.person_actions._person(person, false)),
			"choice": activity._choice.get(person, {}), "cell": data.index(controller.person_actions._person(person, false).cell), "door": int(registered.get("cell", -1)),
			"faction": int(controller.person_actions._person(person, false).faction), "owner_faction": int(feature.get("owner_faction", -1))})): return
	# Night: inside the house.
	data.site.minute = day_start + _minute_of("sleep", _minute_of("evening")) + 1
	for person: int in residents: crowd.home_enter(person)
	activity._decide(crowd)
	if not _check(residents.all(func(person: int) -> bool: return crowd.is_at_home(person) and Array(crowd.crowd.site_person_absent_state(int(crowd._index_by_id[person]))) == [1.0, 5.0]) and activity._choice.is_empty(),
		"the night takes them inside: natively absent (kind 5), nothing plays", [residents.map(func(person: int) -> bool: return crowd.is_at_home(person)), activity._choice]): return
	# Morning: out again, fetching water.
	var next_start := Calendar.day_start_minute(day + 1)
	data.site.minute = next_start + _minute_of("wake") + 1
	for person: int in residents: crowd.home_leave(person)
	for _frame: int in range(3): await process_frame
	activity._decide(crowd)
	if not _check(residents.all(func(person: int) -> bool: return not crowd.is_at_home(person) and _clip(activity, person) == "civilian_fetch_water"), "the morning brings them out to fetch water", activity._choice): return
	# Work (last: it takes them away from their doors).
	# The residents stand in the player's team, so its commander hands them to the work (the schedule keeps only
	# leaderless residents; a civilian alone captains his team and is drawn as a live body, outside the atlas batch).
	data.site.minute = next_start + _minute_of("work") + 1
	var owner: Variant = crowd.person_owner(residents[0])
	var assigned: Dictionary = {}
	for _frame: int in range(600):
		assigned = controller.work_team.assign(owner, residents, player)
		if assigned.ok or str(assigned.get("code", "")) != "BUSY": break
		await process_frame
	if not _check(assigned.ok and residents.all(func(person: int) -> bool: return controller.work_team.is_assigned(person)), "in a work phase both are handed to the work", assigned): return
	activity._decide(crowd)
	if not _check(residents.all(func(person: int) -> bool: return _clip(activity, person) in ["civilian_carry", "civilian_lift"]), "at work they carry or lift", activity._choice): return
	activity._since_update = INF
	activity.update(crowd, 0.0)
	if not _check(not bool(activity._rejected), "the native presentation takes the work set", residents.map(func(person: int) -> Dictionary:
		var index := int(crowd._index_by_id[person])
		return {"id": person, "index": index, "kit": int(crowd._kit_ids[index]), "role": int(crowd.crowd.get_military_role(index)),
			"absent": Array(crowd.crowd.site_person_absent_state(index)), "player_index": int(crowd.player_index), "choice": activity._choice.get(person, {}),
			"tracks": activity._tracks.has(int(crowd._kit_ids[index])),
			"alone": ["civilian_sit", "civilian_fetch_water", "civilian_carry", "civilian_lift"].map(func(clip: String) -> bool:
				var ok := bool(crowd.crowd.render_set_activity(PackedInt32Array([index]), activity._tracks[int(crowd._kit_ids[index])][clip], PackedFloat32Array([0.0]), PackedByteArray([1])))
				crowd.crowd.render_set_activity(PackedInt32Array(), PackedInt32Array(), PackedFloat32Array(), PackedByteArray())
				return ok),
			"state": crowd.soldier_state(index)})): return
	# The save: the data-only farm out first; the house is real.
	data.site.features.erase(FARM)
	data.site.zones = data.site.zones.filter(func(zone: Dictionary) -> bool: return str(zone.get("feature", "")) != FARM)
	Households.set_job(data.site, house, "")
	data.site.erase("settlement") # the stand-in settlement has no centre feature, which the save rules require
	var synced: Dictionary = crowd.sync_to_site()
	var saved: Dictionary = controller.save_to(controller.save_path)
	if not _check(synced.get("ok", true) and saved.ok, "the dressed residents in a real house pass the Site save rules", [synced, saved]): return
	_finished = true
	print("SITE_CIVILIAN_LIFE_VISUAL_PASS: ", checks, " checks")
	quit(0)
