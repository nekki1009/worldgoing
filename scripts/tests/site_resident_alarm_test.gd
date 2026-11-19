extends "res://scripts/tests/site_building_ui_test.gd"
## 平民行為 C3a (reports/civilian-site-behavior-plan.md §4.5): residents go home from danger. A standard house of faction 1
## and a commanderless civilian of faction 1 registered to it, standing away from the door. Checks:
## - at a work-phase check with nobody hostile, nothing starts and there is no alarm;
## - an armed person of faction 2 on the Site is danger: the civilian starts home at once (the alarm), at the next check;
## - in a fight an ordinary housing return is refused ("須先脫戰") but the fleeing one starts and keeps walking;
## - a fight starting sends the residents home without waiting for the ten-minute check;
## - the alarm holds 30 minutes after the danger is gone; then the work phase is back (nothing is started).
## Output: SITE_RESIDENT_ALARM_PASS on success; quit(1) on failure.

const Schedule = preload("res://scripts/terrain_lab/site_resident_schedule.gd")
const Housing = preload("res://scripts/terrain_lab/site_housing.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_RESIDENT_ALARM OK ", checks, ": ", message)
		return true
	push_error("SITE_RESIDENT_ALARM_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var house := _formal_feature(data, "house", Vector2i(28, 20), Vector2i.ONE, {"variant": "long"})
	var layout: Dictionary = Runtime.house_layout(data, house)
	if not _ok(layout.ok and layout.slots.size() >= 1, "the house has a door rest cell", layout): return
	var team: TerrainArmy = lab.army
	team.roster_size = 1
	team.faction_id = 1
	if not _ok(team.deploy_at(data, null, null, [Vector2i(34, 26)]) and team.enable_combat(false), "a one-person team deploys away from the door"): return
	team.set_process(false)
	team.settle_combat_command()
	team.formal_commander = -1
	team.acting_commander = -1
	team.current_commander = -1
	team.officer_order.clear()
	team.officer_service.clear()
	team.combat_order = TerrainArmy.CombatOrder.HOLD
	var civilian := team.combat_identity(0)
	team.combat_units[0]["military_role"] = "civilian"
	if not data.site.has("housing"): data.site["housing"] = {}
	data.site.housing[str(civilian)] = {"version": 1, "house_id": house, "cell": int(layout.slots[0])}
	if not _ok(Housing.schedule_authority(lab, actions._person(civilian)), "the schedule has authority over the civilian"): return

	# A quiet work phase: nothing starts.
	data.site.minute = 3 * 1440 + 8 * 60
	controller.resident_schedule_tick()
	if not _ok(int(controller.last_resident_schedule.get("started", -1)) == 0 and not bool(controller.last_resident_schedule.get("alarm", true)) and not actions.is_busy(civilian), "a quiet work phase starts nothing", controller.last_resident_schedule): return

	# An armed enemy appears.
	lab._ensure_army_slots(2)
	var enemy: TerrainArmy = null
	for candidate: TerrainArmy in lab.combat_armies:
		if candidate != team and not candidate.has_army() and not candidate.combat_enabled and candidate.combat_units.is_empty(): enemy = candidate
	if not _ok(enemy != null, "a free slot holds the enemy"): return
	enemy.team_id = lab._next_army_identity()
	enemy.faction_id = 2
	enemy.roster_size = 1
	if not _ok(enemy.deploy_at(data, null, null, [Vector2i(70, 70)]) and enemy.enable_combat(false), "an armed person of faction 2 stands on the Site"): return
	enemy.set_process(false)
	if not _ok(Schedule.danger(lab), "that is danger for the settlement"): return
	data.site.minute = 3 * 1440 + 8 * 60 + 10
	controller.resident_schedule_tick()
	if not _ok(bool(controller.last_resident_schedule.alarm) and int(controller.last_resident_schedule.started) == 1 and str(actions.job_for(civilian).get("kind", "")) == "housing_return" and bool(actions.job_for(civilian).get("flee", false)), "the alarm sends the civilian home in the work phase", controller.last_resident_schedule): return
	actions.advance_housing_jobs(0.6)
	if not _ok(not bool(actions.job_for(civilian).get("cancelled", true)), "the fleeing walk passes its own step check near the enemy", actions.job_for(civilian)): return

	# In a fight only the flight is allowed; a fight starting acts at once.
	actions._cancel_housing_job(actions._jobs.get(str(civilian), {}), "test reset")
	actions.advance_housing_jobs(0.6)
	data.site.combat_left = 5.0
	# Both judged as a walk in progress (allow_moving), so only the fight rule differs.
	var ordinary: Dictionary = Housing.context(lab, civilian, house, Housing.SCHEDULE_REQUESTER, true)
	var fleeing: Dictionary = Housing.context(lab, civilian, house, Housing.SCHEDULE_REQUESTER, true, true)
	if not _ok(not ordinary.ok and str(ordinary.message).ends_with("須先脫戰") and fleeing.ok, "in a fight an ordinary return is refused, a flight is not", [ordinary, fleeing.get("code")]): return
	var before: Dictionary = controller.last_resident_schedule
	controller.resident_schedule_tick() # same ten-minute check, but the fight has just started
	if not _ok(not is_same(before, controller.last_resident_schedule) and bool(controller.last_resident_schedule.alarm), "a fight starting runs the schedule at once", controller.last_resident_schedule): return
	data.site.combat_left = 0.0

	# The danger goes; the alarm holds 30 minutes, then work is back.
	actions._cancel_housing_job(actions._jobs.get(str(civilian), {}), "test reset")
	actions.advance_housing_jobs(0.6)
	enemy.combat_enabled = false # the enemy leaves the field
	if not _ok(not Schedule.danger(lab), "with the enemy gone there is no danger"): return
	data.site.minute = 3 * 1440 + 8 * 60 + 30
	controller.resident_schedule_tick()
	if not _ok(bool(controller.last_resident_schedule.alarm), "20 minutes after the danger the alarm still holds", controller.last_resident_schedule): return
	if actions.is_busy(civilian): actions._cancel_housing_job(actions._jobs.get(str(civilian), {}), "test reset"); actions.advance_housing_jobs(0.6)
	data.site.minute = 3 * 1440 + 8 * 60 + 50
	controller.resident_schedule_tick()
	if not _ok(not bool(controller.last_resident_schedule.alarm) and int(controller.last_resident_schedule.started) == 0, "after 30 minutes the work phase is back", controller.last_resident_schedule): return
	print("SITE_RESIDENT_ALARM_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
