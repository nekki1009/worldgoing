extends "res://scripts/tests/site_building_ui_test.gd"
## 平民行為 C1a (reports/civilian-site-behavior-plan.md §4.2; Nekki 11/15 Q3 A). Pure timetable rules plus the driver on
## a real Site: a standard house of faction 1 and a commanderless three-person team of faction 1, all registered to the
## house ; two stand away and one at his door. Checks:
## - phases, the diligent shift, ten-minute checks and the meal list;
## - in a work phase the driver starts nothing; in the night phase it starts the normal housing return for a civilian,
##   once per ten-minute check, and never for a soldier or the controlled person;
## - a civilian already at his door counts as home; the started job survives the normal housing job's step (the walk itself
##   is the crowd path, covered with C1c).
## Output: SITE_RESIDENT_SCHEDULE_PASS on success; quit(1) on failure.

const Schedule = preload("res://scripts/terrain_lab/site_resident_schedule.gd")
const Housing = preload("res://scripts/terrain_lab/site_housing.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_RESIDENT_SCHEDULE OK ", checks, ": ", message)
		return true
	push_error("SITE_RESIDENT_SCHEDULE_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _run() -> void:
	if not _ok(Schedule.phase_at(23 * 60) == "sleep" and Schedule.phase_at(4 * 60) == "sleep" and Schedule.phase_at(5 * 60 + 30) == "wake" and Schedule.phase_at(7 * 60) == "work" and Schedule.phase_at(12 * 60) == "meal" and Schedule.phase_at(15 * 60) == "work" and Schedule.phase_at(19 * 60) == "evening", "the day's phases"): return
	if not _ok(Schedule.phase_at(5 * 60 + 40, 80) == "work" and Schedule.phase_at(5 * 60 + 40, 50) == "wake" and Schedule.phase_at(18 * 60 + 10, 80) == "work" and Schedule.phase_at(18 * 60 + 10, 50) == "evening", "a diligent person works 30 minutes longer at both ends"): return
	if not _ok(Schedule.check_index(1449.0) == 144 and Schedule.meals_between(600.0, 1440.0 + 700.0).size() == 3 and Schedule.meals_between(660.0, 660.0).is_empty(), "ten-minute checks and the meal list"): return
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var house := _formal_feature(data, "house", Vector2i(28, 20), Vector2i.ONE, {"variant": "long"})
	var layout: Dictionary = Runtime.house_layout(data, house)
	if not _ok(layout.ok and layout.slots.size() >= 3, "the house has three door rest cells", layout): return
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	team.faction_id = 1
	var door: Vector2i = data.cell_from_index(int(layout.slots[2]))
	var deployed := team.deploy_at(data, null, null, [Vector2i(34, 26), Vector2i(35, 26), door]) and team.enable_combat(false)
	if not _ok(deployed, "a three-person team deploys, two away and one at the door"): return
	team.set_process(false)
	team.settle_combat_command()
	team.formal_commander = -1
	team.acting_commander = -1
	team.current_commander = -1
	team.officer_order.clear()
	team.officer_service.clear()
	team.combat_order = TerrainArmy.CombatOrder.HOLD
	var civilian := team.combat_identity(0)
	var soldier := team.combat_identity(1)
	team.combat_units[0]["military_role"] = "civilian"
	team.combat_units[1]["military_role"] = "soldier"
	var settled := team.combat_identity(2)
	team.combat_units[2]["military_role"] = "civilian"
	if not data.site.has("housing"): data.site["housing"] = {}
	data.site.housing[str(civilian)] = {"version": 1, "house_id": house, "cell": int(layout.slots[0])}
	data.site.housing[str(soldier)] = {"version": 1, "house_id": house, "cell": int(layout.slots[1])}
	data.site.housing[str(settled)] = {"version": 1, "house_id": house, "cell": int(layout.slots[2])}
	if not _ok(Housing.schedule_authority(lab, actions._person(civilian)) and not Housing.schedule_authority(lab, actions._person(soldier)) and not Housing.schedule_authority(lab, actions._person(int(lab.controlled_person_id()))), "the schedule has authority over the civilian only"): return
	data.site.minute = 3 * 1440 + 8 * 60
	controller.resident_schedule_tick()
	if not _ok(int(controller.last_resident_schedule.get("started", -1)) == 0 and not actions.is_busy(civilian), "a work phase starts nothing", controller.last_resident_schedule): return
	data.site.minute = 3 * 1440 + 22 * 60 + 3
	controller.resident_schedule_tick()
	if not _ok(int(controller.last_resident_schedule.started) == 1 and str(actions.job_for(civilian).get("kind", "")) == "housing_return" and not actions.is_busy(soldier), "at night the civilian starts home and the soldier does not", controller.last_resident_schedule): return
	var first: Dictionary = controller.last_resident_schedule
	data.site.minute = 3 * 1440 + 22 * 60 + 8
	controller.resident_schedule_tick()
	if not _ok(is_same(first, controller.last_resident_schedule), "the same ten-minute check runs once"): return
	if not _ok(int(first.home) == 1 and not actions.is_busy(settled), "the civilian at his door counts as home", first): return
	actions.advance_housing_jobs(0.6)
	var job: Dictionary = actions.job_for(civilian)
	if not _ok(str(job.get("kind", "")) == "housing_return" and not bool(job.get("cancelled", true)), "the scheduled job passes the housing job's own authority check", job): return
	print("SITE_RESIDENT_SCHEDULE_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
