extends "res://scripts/tests/site_building_ui_test.gd"
## 技能系統 K1b (reports/skill-k1-implementation.md; spec reports/skill-system-plan.md V0.7 §5.2). Checks:
## - the speed factor is 0.5 + proficiency / 100: x0.5 at 0, x1.0 at 50 (and with no packet, no line or a task that
##   trains no line), x1.5 at 100;
## - SiteRuntime._skill_work_factor (used by prepare_checked_work_prefix and manual harvest) reads the worker from a work
##   prefix's start body, else from the Site's person lookup, on the task's line (a real smithy on a real Site).
## The SiteWorkTeam paths multiply their returned work minutes by the same PersonSkills.work_factor of the worker's row;
## at proficiency 50 every existing work test keeps its exact numbers.
## Output: SITE_SKILLS_K1B_PASS on success; quit(1) on failure.

const Skills = preload("res://scripts/terrain_lab/person_skills.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SKILLS_K1B OK ", checks, ": ", message)
		return true
	push_error("SITE_SKILLS_K1B_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _run() -> void:
	var rows := [{"skills": {"version": 1, "lines": {"craft": 0}}}, {"skills": {"version": 1, "lines": {"craft": 100000}}}, {"skills": {"version": 1, "lines": {"craft": 75000}}}, {}, {"skills": {"version": 1}}]
	var factors := [Skills.work_factor(rows[0], "craft"), Skills.work_factor(rows[1], "craft"), Skills.work_factor(rows[2], "craft"),
		Skills.work_factor(rows[3], "craft"), Skills.work_factor(rows[4], "craft"), Skills.work_factor(rows[1], "farming"), Skills.work_factor(rows[1], ""), Skills.work_factor(null, "craft")]
	if not _ok(factors == [0.5, 1.5, 1.25, 1.0, 1.0, 1.0, 1.0, 1.0], "factor 0.5 + proficiency / 100; 1.0 without a packet, line or task line", factors): return
	var data := _building_fixture()
	var lab := _building_lab(data)
	var smithy := _formal_feature(data, "smithy", Vector2i(30, 24))
	var master := {"person_id": 41, "skills": {"version": 1, "lines": {"craft": 100000}}}
	var task := {"action": "operate", "target": "feature:" + smithy}
	var well_task := {"action": "harvest", "target": "nothing"}
	if not _ok(is_equal_approx(SiteRuntime._skill_work_factor(data, task, 41, {"start": {"body": master}}), 1.5) and is_equal_approx(SiteRuntime._skill_work_factor(data, well_task, 41, {"start": {"body": master}}), 1.0), "a prefix's start body sets the factor on the task's line"): return
	var actor := lab.character
	actor.skills = {"version": 1, "lines": {"craft": 0}}
	if not _ok(is_equal_approx(SiteRuntime._skill_work_factor(data, task, int(actor.person_id)), 0.5) and is_equal_approx(SiteRuntime._skill_work_factor(data, task, 0), 1.0), "without a start body the Site's person lookup finds the worker", SiteRuntime._skill_work_factor(data, task, int(actor.person_id))): return
	actor.skills = {}
	if not _finish_workflow_body(): return
	print("SITE_SKILLS_K1B_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
