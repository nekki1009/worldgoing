extends "res://scripts/tests/site_building_ui_test.gd"
## 技能系統 K1a (reports/skill-k1-implementation.md; spec reports/skill-system-plan.md V0.7 §5.3, §5.6). Checks:
## - the §5.3 pace: full-time (3600 effective hours a year) from 0 at aptitude 50 reaches 40 in 2.5 years and 80 in 15;
##   aptitude 100 reaches 80 in 10 years and aptitude 0 in 30;
## - daily settlement composes: a hundred 10-hour days give the same proficiency as one 1000-hour settlement, and the
##   work not yet worth one thousandth stays pending;
## - from 80 every full year of work rolls five times at aptitude %: aptitude 0 never grows, aptitude 100 gains 5; the
##   rolls are fixed by the world seed, the person, the line and the count, and survive a JSON round trip;
## - pending and toward are whole microseconds (JSON-stable); a malformed growth field is refused;
## - task lines: construct/repair -> building, harvest/clear -> gathering, capture -> farming, operate by feature kind;
## - credit() writes in place on a row and on an Actor; a published work prefix credits its worker (SiteRuntime);
## - on a real Site the daily settlement runs once per calendar day and turns a roster row's pending work into proficiency.
## Output: SITE_SKILLS_K1A_PASS on success; quit(1) on failure.

const Skills = preload("res://scripts/terrain_lab/person_skills.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const YEAR_HOURS := 3600.0

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SKILLS_K1A OK ", checks, ": ", message)
		return true
	push_error("SITE_SKILLS_K1A_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _years(from_milli: int, to_milli: int, talent: float) -> float:
	return Skills.seconds_between(from_milli, to_milli, talent) / 3600.0 / YEAR_HOURS

func _work(packet: Dictionary, line: String, hours: float) -> Dictionary:
	var row := {"person_id": 7, "skills": packet.duplicate(true)}
	Skills.credit(row, line, hours * 3600.0)
	return row.skills

func _pure() -> bool:
	var pace := [_years(0, 40000, 50.0), _years(0, 80000, 50.0), _years(0, 80000, 100.0), _years(0, 80000, 0.0), _years(0, 20000, 50.0)]
	if not _ok(absf(pace[0] - 2.5) < 0.01 and absf(pace[1] - 15.0) < 0.05 and absf(pace[2] - 10.0) < 0.05 and absf(pace[3] - 30.0) < 0.1 and absf(pace[4] - 0.9) < 0.05, "the §5.3 pace table", pace): return false
	var seed_value := Skills.world_seed("k1a")
	var born := {"version": 1, "aptitude": {"body": 50, "mind": 50}}
	var daily := born.duplicate(true)
	for _day: int in range(100): daily = Skills.settle(_work(daily, "farming", 10.0), seed_value, 7)
	var once := Skills.settle(_work(born, "farming", 1000.0), seed_value, 7)
	var daily_level := Skills.level_milli(daily, "farming")
	if not _ok(absf(daily_level - Skills.level_milli(once, "farming")) <= 1 and daily_level > 50000, "a hundred 10-hour days equal one 1000-hour settlement", [daily, once]): return false
	var tiny := Skills.settle(_work(born, "craft", 0.01), seed_value, 7)
	if not _ok(Skills.level_milli(tiny, "craft") == 50000 and int(tiny.get("pending", {}).get("craft", 0)) == 36000000, "work worth less than one thousandth stays pending", tiny): return false
	# From 80: one full year of work, one roll of five draws at aptitude %.
	for talent: int in [0, 100]:
		var master := {"version": 1, "lines": {"craft": 80000}, "aptitude": {"body": talent, "mind": talent}}
		var rolled := Skills.settle(_work(master, "craft", YEAR_HOURS), seed_value, 7)
		var expected := 80000 + (5000 if talent == 100 else 0)
		if not _ok(Skills.level_milli(rolled, "craft") == expected and int(rolled.get("rolls", {}).get("craft", 0)) == 1 and not rolled.has("toward"), "a full year from 80 rolls once at aptitude %d" % talent, rolled): return false
	var middle := {"version": 1, "lines": {"craft": 80000}, "aptitude": {"body": 50, "mind": 50}}
	var half := Skills.settle(_work(middle, "craft", YEAR_HOURS * 0.5), seed_value, 7)
	if not _ok(Skills.level_milli(half, "craft") == 80000 and int(half.toward.craft) == int(YEAR_HOURS * 0.5 * 3600.0 * 1000000.0), "half a year from 80 gathers toward the next roll", half): return false
	var parsed: Variant = JSON.parse_string(JSON.stringify(half))
	if not _ok(Skills.valid(parsed) and Skills.normalized(parsed) == Skills.normalized(half), "toward survives a JSON round trip exactly", parsed): return false
	var resumed := Skills.settle(_work(Skills.normalized(parsed), "craft", YEAR_HOURS * 0.5), seed_value, 7)
	var straight := Skills.settle(_work(middle, "craft", YEAR_HOURS), seed_value, 7)
	if not _ok(resumed == straight and int(straight.rolls.craft) == 1, "a reload between two half years gives the same roll as one full year", [resumed, straight]): return false
	var gains := {}
	for count: int in range(400): gains[Skills.yearly_gain(seed_value, 7, "craft", count, 50.0)] = int(gains.get(Skills.yearly_gain(seed_value, 7, "craft", count, 50.0), 0)) + 1
	var mean := 0.0
	for gain: int in gains: mean += float(gain) * float(gains[gain])
	mean /= 400.0
	if not _ok(absf(mean - 2.5) < 0.25 and Skills.yearly_gain(seed_value, 7, "craft", 3, 50.0) == Skills.yearly_gain(seed_value, 7, "craft", 3, 50.0), "aptitude 50 averages +2.5 a year from fixed rolls", [mean, gains]): return false
	var top := Skills.settle(_work({"version": 1, "lines": {"craft": 99000}, "aptitude": {"body": 100, "mind": 100}}, "craft", YEAR_HOURS * 3.0), seed_value, 7)
	if not _ok(Skills.level_milli(top, "craft") == 100000 and not top.has("toward") and not top.has("pending"), "100 is the cap and nothing gathers past it", top): return false
	for bad: Dictionary in [{"version": 1, "pending": {"craft": 1.5}}, {"version": 1, "pending": {"cooking": 5}}, {"version": 1, "toward": {"craft": -1}}, {"version": 1, "rolls": {"craft": 0.5}}]:
		if not _ok(not Skills.valid(bad), "a malformed growth field is refused", bad): return false
	# Task lines.
	var state := {"features": {"1": {"kind": "farm"}, "2": {"kind": "smithy"}, "3": {"kind": "shipyard"}, "4": {"kind": "well"}, "5": {"kind": "pasture"}}}
	var lines := [Skills.line_for_task(state, {"action": "construct", "target": "feature:4"}), Skills.line_for_task(state, {"action": "repair", "target": "vehicle:9"}),
		Skills.line_for_task(state, {"action": "harvest", "target": "12"}), Skills.line_for_task(state, {"action": "clear", "target": "13"}),
		Skills.line_for_task(state, {"action": "capture", "target": "14"}), Skills.line_for_task(state, {"action": "operate", "target": "feature:1"}),
		Skills.line_for_task(state, {"action": "operate", "target": "feature:2"}), Skills.line_for_task(state, {"action": "operate", "target": "feature:3"}),
		Skills.line_for_task(state, {"action": "operate", "target": "feature:4"}), Skills.line_for_task(state, {"action": "operate", "target": "feature:5"}),
		Skills.line_for_task(state, {"action": "survey", "target": "12"})]
	if not _ok(lines == ["building", "building", "gathering", "gathering", "farming", "farming", "craft", "building", "", "farming", ""], "task lines", lines): return false
	# credit() in place, microseconds; a published prefix credits its worker.
	var row := {"person_id": 3}
	Skills.credit(row, "gathering", 1.5)
	Skills.credit(row, "gathering", 0.25)
	Skills.credit(row, "medicine", -1.0)
	if not _ok(row.get("skills") == {"version": 1, "pending": {"gathering": 1750000}} and Skills.valid(row.skills), "credit adds whole microseconds in place", row): return false
	var worker := {"person_id": 4}
	SiteRuntime._credit_skill_work({"site": state, "task": {"action": "operate", "target": "feature:2"}, "prefix_ref": {"productive_seconds": 3600.0, "start": {"body": worker}}, "data": null, "identity": 4})
	SiteRuntime._credit_skill_work({"site": state, "task": {"action": "operate", "target": "feature:4"}, "prefix_ref": {"productive_seconds": 3600.0, "start": {"body": worker}}, "data": null, "identity": 4})
	if not _ok(int(worker.get("skills", {}).get("pending", {}).get("craft", 0)) == 3600000000 and worker.skills.pending.size() == 1, "a published smithy prefix credits craft; a well credits nothing", worker): return false
	return true

func _run() -> void:
	if not _pure(): return
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var actor := lab.character
	Skills.credit(actor, "building", 3600.0)
	if not _ok(int(actor.skills.get("pending", {}).get("building", 0)) == 3600000000 and actor.capture_state(true).get("skills") == actor.skills, "credit writes the Actor's own packet, which the Actor saves"): return
	var team: TerrainArmy = lab.army
	team.roster_size = 1
	var deployed := team.deploy_at(data, null, null, [Vector2i(30, 22)]) and team.enable_combat(false)
	if not _ok(deployed, "a one-person team deploys"): return
	team.set_process(false)
	var identity := team.combat_identity(0)
	var member: Dictionary = team.combat_units[0]
	Skills.credit(member, "farming", 10.0 * 3600.0)
	data.site.minute = Calendar.day_start_minute(3) + 60
	var first: Dictionary = controller.skills_day()
	var settled := Skills.of(member)
	# Only the remainder not yet worth one thousandth (well under an hour of work at 50) stays pending.
	if not _ok(int(first.get("settled", 0)) >= 2 and Skills.level_milli(settled, "farming") > 50000 and int(settled.get("pending", {}).get("farming", 0)) < 3600000000, "the day's settlement turns the row's pending work into farming", [first, settled]): return
	if not _ok(Skills.level_milli(Skills.of(actor), "building") > 50000, "the Actor is settled too", actor.skills): return
	Skills.credit(member, "farming", 10.0 * 3600.0)
	if not _ok(controller.skills_day().is_empty() and Skills.of(member).get("pending", {}).has("farming"), "the same day does not settle twice"): return
	data.site.minute = Calendar.day_start_minute(4) + 60
	controller.skills_day()
	var expected := Skills.settle(_work(Skills.settle(_work({"version": 1}, "farming", 10.0), controller._skills_world_seed(), identity), "farming", 10.0), controller._skills_world_seed(), identity)
	if not _ok(Skills.of(member) == expected, "the next day settles again, as the pure rule does", [Skills.of(member), expected]): return
	if not _finish_workflow_body(): return
	print("SITE_SKILLS_K1A_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
