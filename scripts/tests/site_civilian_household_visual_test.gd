extends SceneTree
## CIV-A4 / CA-05 (output/civilian_atlas_plan_20261119/PLAN.md) with the real resident owner, GPU (visual): the work path
## the game itself runs. A house of the settlement's faction is built and completed; two unarmed civilians are born at
## its doors and form a captainless residents' team the way the game makes one (SiteFallenResidents._submit: their own
## team of the faction, captain cleared, registered at their doors); a real farm is built and opened, and the 戶籍
## decider gives it to the household.
## Checks:
## - the residents are under the daily schedule (no captain), dressed with the straw hat on civilian kits, no live body;
## - a work phase: the schedule itself (resident_schedule_tick) hands both to the household's work; walking to the farm
##   they carry, standing at the work they lift; the native presentation takes it (screenshots carry.png, lift.png);
## - the evening: the schedule takes them off the work and walks them home, inside the house (native absent): nothing
##   plays, and the crowd and the Site clock keep running with them inside;
## - save and reopen (the stand-in settlement taken out first): each keeps his civilian look on a
##   civilian kit, hp and fatigue unchanged by the presentation, still home and under the schedule.
## Output: SITE_CIVILIAN_HOUSEHOLD_VISUAL_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Dress = preload("res://scripts/terrain_lab/civilian_dress.gd")
const Schedule = preload("res://scripts/terrain_lab/site_resident_schedule.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Households = preload("res://scripts/terrain_lab/site_households.gd")
const Housing = preload("res://scripts/terrain_lab/site_housing.gd")
const SiteFallenResidents = preload("res://scripts/terrain_lab/site_fallen_residents.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false
var _build_refusals := {}

func _initialize() -> void:
	create_timer(600.0).timeout.connect(func() -> void: _fail("600-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	printerr("SITE_CIVILIAN_HOUSEHOLD_VISUAL_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_CIVILIAN_HOUSEHOLD_VISUAL OK ", checks, ": ", message)
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
				for item: String in ["wood", "stone"]: data.site.inventory[item] = maxi(int(data.site.inventory.get(item, 0)), 20) # a taken-back plan may not refund all
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
				# A plot the Site worker cannot finish (it needs clearing first): take the plan back and try the next plot.
				_build_refusals["stage:" + str(feature.stage)] = int(_build_refusals.get("stage:" + str(feature.stage), 0)) + 1
				var taken_back: Dictionary = SiteRuntime.cancel_feature(data, key, Callable(), faction)
				if not taken_back.ok: _build_refusals["cancel:" + str(taken_back.get("code", ""))] = 1
				for cell: int in firmed: data.foundation[cell] = int(firmed[cell])
				continue
	return ""

## Builds, completes and opens a farm of `faction` near `near` through the formal path (as _house does), seeded.
func _farm(data: TerrainData, near: Vector2i, faction: int) -> String:
	var settings := {"owner_faction": faction}
	data.site.inventory["seeds"] = int(data.site.inventory.get("seeds", 0)) + 10
	data.site.inventory["tools"] = maxi(int(data.site.inventory.get("tools", 0)), 2)
	for radius: int in range(0, 40, 2):
		for dy: int in range(-radius, radius + 1, 2):
			for dx: int in range(-radius, radius + 1, 2):
				if maxi(absi(dx), absi(dy)) != radius: continue
				var anchor := near + Vector2i(dx, dy)
				if not data.contains(anchor): continue
				var placement := SiteRuntime.building_cells(data, "farm", anchor, Vector2i(2, 2), settings)
				if not placement.ok:
					_build_refusals["farm cells:" + str(placement.get("code", ""))] = 1
					continue
				# Test-only ground preparation, as for the house: the start Site's ground near the house is too poor to till
				# (fertility and drainage under 30); improve the chosen plot, then build through the formal path.
				var improved := {}
				for cell: Variant in placement.cells:
					improved[int(cell)] = [int(data.fertility[int(cell)]), int(data.drainage[int(cell)])]
					data.fertility[int(cell)] = maxi(int(data.fertility[int(cell)]), 50)
					data.drainage[int(cell)] = maxi(int(data.drainage[int(cell)]), 50)
				var built := SiteRuntime.request_build(data, "farm", placement.cells, Callable(), settings)
				if not built.ok:
					for cell: int in improved:
						data.fertility[cell] = int(improved[cell][0])
						data.drainage[cell] = int(improved[cell][1])
					_build_refusals["farm build:" + str(built.get("code", ""))] = int(_build_refusals.get("farm build:" + str(built.get("code", "")), 0)) + 1
					continue
				var key := str(built.feature)
				var feature: Dictionary = data.site.features[key]
				var entrance: int = int(feature.get("pending_build", feature).get("entrance", feature.entrance))
				SiteRuntime.assign_task(data, SiteRuntime.ok("", {"target": "feature:" + key, "action": "construct", "cell": entrance}))
				data.site.worker.cell = entrance
				data.site.worker.mode = "work"
				SiteRuntime.advance(data, float(feature.get("pending_build", feature).work) + 1.0, true, false, Callable(), Callable(), Callable(), SiteRuntime.CARRY_CAPACITY, SiteRuntime.CARRY_CAPACITY, 1.0, faction)
				data.site.worker.mode = "idle"
				if str(feature.stage) != "complete":
					_build_refusals["farm stage:" + str(feature.stage) + ":" + str(data.site.worker.get("status", ""))] = 1
					return ""
				var opened: Dictionary = SiteRuntime.operate_feature(data, key)
				if not opened.ok: _build_refusals["farm operate:" + str(opened.get("message", ""))] = 1
				return key if opened.ok else ""
	return ""

## A minute of the day at which every resident (each with his own diligence) is in `phase`.
func _common_minute(controller: Variant, residents: Array[int], phase: String) -> int:
	for minute: int in range(1440):
		if residents.all(func(person: int) -> bool: return Schedule.phase_at(minute, Schedule.diligence_of(controller.person_actions._person(person, false))) == phase): return minute
	return -1

func _choice_of(activity: Variant, person: int) -> String:
	return str(activity._choice.get(person, {}).get("clip", ""))

func _run() -> void:
	if not _check(DisplayServer.get_name() != "headless", "GPU required"): return
	if not _check(RegionEntry.request_new_world(START, {}, "平民戶籍世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
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
	# Away from the camp: the player's team stands around its camp, and a person standing on a door blocks the way home.
	var house := ""
	for offset: Vector2i in [Vector2i(0, 10), Vector2i(10, 0), Vector2i(-10, 0), Vector2i(0, -10)]:
		house = _house(data, crowd.combat_target(player).cell + offset, own)
		if not house.is_empty(): break
	if not _check(not house.is_empty(), "a house of the faction is built and completed", _build_refusals): return
	if not _check(not _build_refusals.keys().any(func(key: String) -> bool: return key.begins_with("cancel:")) and data.site.features.values().all(func(feature: Dictionary) -> bool: return str(feature.get("stage", "")) != "planned"),
		"no unfinished house plan is left on the ground", _build_refusals): return
	var layout: Dictionary = SiteRuntime.house_layout(data, house)
	if not _check(layout.ok and layout.slots.size() >= 2, "the house has two door rest cells", layout): return
	data.site["settlement"] = {"version": 1, "settlement_id": "household_village", "center_id": "c", "level": 2, "name": "測試村", "owner_faction": own,
		"offices": SiteOffices.default_offices("settlement", player, false), "fall_record": SiteSettlement.empty_fall_record()}
	# Two unarmed civilians are born at the doors (as migrants join: a row of the player's team) ...
	var ids: Array[int] = lab._allocate_army_person_ids(2)
	var residents: Array[int] = []
	var homes := {}
	for index: int in ids.size():
		var row: Dictionary = template.duplicate(true)
		for field: String in ["social", "social_state", "vital", "reputation", "combat_record", "work_task", "family", "skills"]: row.erase(field)
		row["person_id"] = ids[index]
		row["name"] = "居民%d" % ids[index]
		row["hp"] = 100.0
		row["cargo"] = {}
		row["item_state"] = SiteRuntime.new_item_state("person:%d" % ids[index])
		row["military_role"] = "civilian"
		var slot := int(layout.slots[layout.slots.size() - 1 - index])
		var made: Dictionary = crowd.add_new_person(int(team.team_id), row, Vector2(data.cell_from_index(slot)) + Vector2(0.5, 0.5))
		if not _check(made.ok, "resident %d is born at a door" % ids[index], made): return
		residents.append(ids[index])
		homes[str(ids[index])] = [house, slot]
	# ... and become the settlement's residents the way the game makes a residents' team (SiteFallenResidents._submit):
	# out into their own team of the faction, then captainless, registered at their doors.
	var formed: Dictionary = SiteFallenResidents._submit(controller, residents, own, homes)
	if not _check(formed.ok, "the residents form a captainless residents' team, registered at their doors", formed): return
	var residents_team := int(formed.team_id)
	if not _check(residents.all(func(person: int) -> bool: return Housing.schedule_authority(lab, controller.person_actions._person(person, false))),
		"the daily schedule commands them (no captain)", residents.map(func(person: int) -> Dictionary: return Housing._formation(lab, controller.person_actions._person(person, false)))): return
	# A real farm of the faction some cells away, built and opened through the formal path, with seed in the stock.
	var door0 := data.cell_from_index(int(layout.slots[0]))
	var farm := _farm(data, door0 + Vector2i(7, 0), own)
	if not _check(not farm.is_empty(), "a farm of the faction is built, completed and opened", _build_refusals): return
	var job: Dictionary = controller.assign_household_job(house, farm, player)
	if not _check(job.ok, "the head gives the household the farm", job): return
	var dressed: Dictionary = controller.dress_residents()
	for _frame: int in range(5): await process_frame
	var activity: Variant = crowd._civilian_activity
	for person: int in residents:
		var index := int(crowd._index_by_id[person])
		var kit := int(crowd._kit_ids[index])
		if not _check(Dress.is_hatted(crowd._records[person].appearance) and kit >= 0 and activity._tracks.has(kit), "resident %d wears the civilian look with the straw hat on a civilian kit (atlas batch, no body)" % person, [dressed, kit, crowd._bodies.has(person)]): return
		if not _check(not crowd._bodies.has(person), "resident %d has no live body (a captainless residents' team)" % person): return
	# Work: the schedule itself sends them to the household's farm; walking they carry, at the farm they lift.
	var day := int(Calendar.day_index(float(data.site.minute))) + 1
	var work_minute := _common_minute(controller, residents, "work")
	if not _check(work_minute >= 0, "a minute when both are in their work phase"): return
	data.site.minute = Calendar.day_start_minute(day) + work_minute
	controller._resident_check = -1
	controller.resident_schedule_tick()
	# The game's own ten-minute check may already have sent them (the world opens at 06:00, a work phase): either way the
	# schedule did it, never the test.
	var schedule: Dictionary = controller.last_resident_schedule
	if not _check(int(schedule.get("sent", 0)) + int(schedule.get("working", 0)) == residents.size() and residents.all(func(person: int) -> bool: return controller.work_team.is_assigned(person)),
		"in a work phase the schedule hands both to the household's work", schedule): return
	var seen := {}
	for person: int in residents: seen[person] = {}
	var shot_taken := false
	for _frame: int in range(900):
		await process_frame
		if _finished: return
		activity._since_decide = INF # decide every frame here, so a short walk is not missed
		for person: int in residents:
			var clip := _choice_of(activity, person)
			if not clip.is_empty(): seen[person][clip] = true
		if not shot_taken and residents.any(func(person: int) -> bool: return _choice_of(activity, person) == "civilian_carry"):
			shot_taken = true
			var image := lab.get_viewport().get_texture().get_image()
			DirAccess.make_dir_recursive_absolute("user://civilian_household_visual")
			image.save_png("user://civilian_household_visual/carry.png")
		if residents.all(func(person: int) -> bool: return seen[person].has("civilian_carry") and seen[person].has("civilian_lift")): break
	if not _check(residents.all(func(person: int) -> bool: return seen[person].has("civilian_carry")), "walking to the farm they carry", seen): return
	# The farm's work walks them between the stock and the field (seed in, grain out): standing at the work they lift.
	if not _check(residents.all(func(person: int) -> bool: return seen[person].has("civilian_lift")), "standing at the work they lift", [seen, activity._choice]): return
	if not _check(not bool(activity._rejected), "the native presentation takes the work set"): return
	var image := lab.get_viewport().get_texture().get_image()
	image.save_png("user://civilian_household_visual/lift.png")
	print("SITE_CIVILIAN_HOUSEHOLD_VISUAL SHOT ", ProjectSettings.globalize_path("user://civilian_household_visual"))
	# Evening: the schedule takes them off the work and walks them home; at their doors they go in (native absent).
	var evening_minute := _common_minute(controller, residents, "evening")
	if not _check(evening_minute >= 0, "a minute when both are in their evening"): return
	data.site.minute = Calendar.day_start_minute(day) + evening_minute
	# The walk home is a real walk, step by step; the player's own speed control (4×) shortens the wait.
	for _press: int in range(3): lab.change_simulation_speed(1)
	var evening_until := Time.get_ticks_msec() + 150000
	while Time.get_ticks_msec() < evening_until:
		controller._resident_check = -1
		controller.resident_schedule_tick()
		for _frame: int in range(30): await process_frame
		if _finished: return
		if residents.all(func(person: int) -> bool: return crowd.is_at_home(person)): break
	if not _check(residents.all(func(person: int) -> bool: return not controller.work_team.is_assigned(person) and crowd.is_at_home(person)),
		"in the evening the schedule takes them off the work and home, inside the house", [controller.last_resident_schedule, residents.map(func(person: int) -> Dictionary:
			var body: Dictionary = controller.person_actions._person(person, false)
			var registered: Dictionary = Housing.relation(lab, person)
			return {"id": person, "home": crowd.is_at_home(person), "assigned": controller.work_team.is_assigned(person), "attends": Housing._attends(lab, person),
				"busy": controller.person_actions.is_busy(person), "job": {"paused": controller.person_actions._jobs.get(str(person), {}).get("paused", ""), "route_elapsed": controller.person_actions._jobs.get(str(person), {}).get("route_elapsed", -1), "from": controller.person_actions._jobs.get(str(person), {}).get("executor_cell", -1)},
				"native": crowd.soldier_state(int(crowd._index_by_id[person])),
				"others": crowd._index_by_id.keys().map(func(other: int) -> Array:
					var other_state: Dictionary = crowd.soldier_state(int(crowd._index_by_id[other]))
					return [other, snappedf(float(other_state.get("px", -1.0)), 0.01), snappedf(float(other_state.get("py", -1.0)), 0.01)]),
				"worker": data.site.get("worker", {}).get("cell", -1),
				"near": [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN].map(func(step: Vector2i) -> Array:
					return [Vector2i(body.cell) + step, data.is_walkable(Vector2i(body.cell) + step)]),
				"route": data.path_between(body.cell, data.cell_from_index(int(registered.get("cell", -1))), func(cell: Vector2i) -> bool: return controller.person_actions.prison_blocked(cell, [person])),
				"moving": bool(body.get("moving", false)), "cell": data.index(body.cell), "door": int(registered.get("cell", -1)),
				"order": Housing._formation(lab, body).get("order"), "return": controller.person_actions.begin_housing_return(person, Housing.SCHEDULE_REQUESTER, false)})]): return
	for _press: int in range(3): lab.change_simulation_speed(-1)
	activity._decide(crowd)
	if not _check(residents.all(func(person: int) -> bool: return _choice_of(activity, person).is_empty()), "inside the house nothing plays", activity._choice): return
	# With them inside, the Site keeps running: the housing attendance input skips people inside their houses (the native
	# refused an attendance row for them, and that refusal stopped every crowd step and the Site clock; found 2026-11-21).
	var tick_before := int(crowd.crowd.stats()[36])
	var minute_before := float(data.site.minute)
	for _frame: int in range(90): await process_frame
	if not _check(int(crowd.crowd.stats()[36]) > tick_before and float(data.site.minute) > minute_before and str(crowd.last_event_error.get("code", "")) != "INVALID_HOUSING",
		"with both inside, the crowd and the Site clock keep running", [tick_before, int(crowd.crowd.stats()[36]), minute_before, data.site.minute, crowd.last_event_error]): return
	# The save and reopen: the stand-in settlement out first; the house, the farm and the team are real.
	var before := {}
	for person: int in residents:
		var body: Dictionary = controller.person_actions._person(person, false)
		before[person] = {"hp": float(body.hp), "fatigue": float(crowd.soldier_state(int(crowd._index_by_id[person])).get("fatigue", 0.0)), "parts": crowd._records[person].appearance.parts.duplicate(true)}
	data.site.erase("settlement")
	var synced: Dictionary = crowd.sync_to_site()
	var saved: Dictionary = controller.save_to(controller.save_path)
	if not _check(synced.get("ok", true) and saved.ok, "the residents' team in the real house passes the Site save rules", [synced, saved]): return
	var reopened: Dictionary = await controller.load_from(controller.save_path)
	for _frame: int in range(10): await process_frame
	crowd = lab.crowd_site
	if not _check(reopened.get("ok", false) and crowd != null and crowd.active, "the Site reopens from the save", reopened): return
	activity = crowd._civilian_activity
	for person: int in residents:
		var index := int(crowd._index_by_id.get(person, -1))
		var kit := int(crowd._kit_ids[index]) if index >= 0 else -1
		var body: Dictionary = controller.person_actions._person(person, false)
		if not _check(index >= 0 and kit >= 0 and activity._tracks.has(kit) and crowd._records[person].appearance.parts == before[person].parts and not crowd._bodies.has(person),
			"after reopening resident %d keeps his civilian look on a civilian kit" % person, [index, kit, crowd._records.get(person, {}).get("appearance", {})]): return
		if not _check(is_equal_approx(float(body.hp), float(before[person].hp)) and is_equal_approx(float(crowd.soldier_state(index).get("fatigue", 0.0)), float(before[person].fatigue)),
			"the presentation changed nothing of resident %d (hp, fatigue)" % person, [body.hp, before[person]]): return
		if not _check(crowd.is_at_home(person) and Housing.schedule_authority(lab, body), "resident %d is still home and under the schedule" % person, Housing._formation(lab, body)): return
	print("SITE_CIVILIAN_HOUSEHOLD_VISUAL_PASS: ", checks, " checks (team %d)" % residents_team)
	_finished = true
	quit(0)
