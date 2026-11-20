extends "res://scripts/tests/site_building_ui_test.gd"
## 技能系統 K1d part 1 (reports/skill-k1-implementation.md; spec reports/skill-system-plan.md V0.7 §5.4, §5.8). Checks:
## - a line that reaches 100 earns its title once, kept in the order earned; the skills page lists 名號 first;
## - malformed titles are refused (unknown key, duplicate, empty list);
## - the New Year decline lowers every stored line by the age-base drop, never below 0, and leaves a packet without
##   lines alone;
## - on a real Site: the day's settlement that takes a worker to 100 gives him the title and +5 prestige once; a New Year
##   at 60 takes 2 off each of his lines (TC7's age base), and a person with no stored line keeps 50.
## Output: SITE_SKILLS_K1D_PASS on success; quit(1) on failure.

const Skills = preload("res://scripts/terrain_lab/person_skills.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")
const YEAR_MICROS := 12960000000000

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SKILLS_K1D OK ", checks, ": ", message)
		return true
	push_error("SITE_SKILLS_K1D_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _pure() -> bool:
	var near := {"version": 1, "lines": {"craft": 99000}, "aptitude": {"body": 100, "mind": 100}, "pending": {"craft": YEAR_MICROS}}
	var top := Skills.settle(near, 3, 9)
	if not _ok(Skills.level_milli(top, "craft") == 100000 and Skills.titles_of(top) == ["craft"], "reaching 100 earns the title", top): return false
	var again := top.duplicate(true)
	again["pending"] = {"craft": YEAR_MICROS, "farming": 1000000}
	again.lines["farming"] = 100000
	var later := Skills.settle(again, 3, 9)
	if not _ok(Skills.titles_of(later) == ["craft", "farming"], "a title is earned once, in order", later): return false
	var page := Skills.page(later, {"body": 100, "mind": 100}, 50.0, 0, {}, [])
	if not _ok(str(page[0].title) == "名號" and str(page[0].rows[0][0]) == "匠神" and str(page[0].rows[1][0]) == "農神", "the page lists 名號 first", page[0]): return false
	for bad: Dictionary in [{"version": 1, "titles": []}, {"version": 1, "titles": ["craft", "craft"]}, {"version": 1, "titles": ["cooking"]}]:
		if not _ok(not Skills.valid(bad), "malformed titles are refused", bad): return false
	var aged := Skills.age_decline({"version": 1, "lines": {"craft": 80000, "farming": 30000, "riding": 1500}}, 2.0)
	if not _ok(aged == {"version": 1, "lines": {"craft": 78000, "farming": 28000}} or aged == {"version": 1, "lines": {"craft": 78000, "farming": 28000, "riding": 0}}, "the decline takes 2 off every line, never below 0", aged): return false
	if not _ok(Skills.age_decline({"version": 1, "pending": {"craft": 5}}, 4.0) == {"version": 1, "pending": {"craft": 5}} and Skills.age_decline({}, 4.0).is_empty(), "no stored line, no decline"): return false
	return true

func _run() -> void:
	if not _pure(): return
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var team: TerrainArmy = lab.army
	team.roster_size = 2
	var deployed := team.deploy_at(data, null, null, [Vector2i(30, 22), Vector2i(32, 22)]) and team.enable_combat(false)
	if not _ok(deployed, "a two-person team deploys"): return
	team.set_process(false)
	var master := team.combat_identity(0)
	var plain := team.combat_identity(1)
	var row: Dictionary = team.combat_units[0]
	row["skills"] = {"version": 1, "lines": {"craft": 99000, "farming": 70000}, "aptitude": {"body": 100, "mind": 100}, "pending": {"craft": YEAR_MICROS}}
	var prestige_before := int(controller.reputation_of(master).prestige)
	data.site.minute = Calendar.day_start_minute(2) + 60
	controller.skills_day()
	var prestige_after := int(controller.reputation_of(master).prestige)
	if not _ok(Skills.titles_of(Skills.of(row)) == ["craft"] and prestige_after - prestige_before == 500, "the settlement that reaches 100 gives the title and +5 prestige", [Skills.of(row), prestige_before, prestige_after]): return
	data.site.minute = Calendar.day_start_minute(3) + 60
	controller.skills_day()
	if not _ok(int(controller.reputation_of(master).prestige) == prestige_after, "the prestige is given once"): return
	# A New Year at 60: the age base drops 2, and so does each stored line.
	var year := int(Calendar.date(float(data.site.minute)).year)
	PersonSocial.set_vital(row, {"birth_year": year - 59, "base": 100.0, "max_hp": 100.0, "year": year, "ko": 0, "starved": false})
	PersonSocial.set_vital(team.combat_units[1], {"birth_year": year - 59, "base": 100.0, "max_hp": 100.0, "year": year, "ko": 0, "starved": false})
	data.site.minute = Calendar.day_start_minute(364) + 60
	controller.vital_year_tick()
	data.site.minute = Calendar.day_start_minute(365) + 1
	controller.vital_year_tick()
	var after := Skills.of(row)
	if not _ok(int(PersonSocial.vital(row).year) == year + 1 and Skills.level_milli(after, "craft") == 98000 and Skills.level_milli(after, "farming") == 68000 and Skills.titles_of(after) == ["craft"], "a New Year at 60 takes 2 off each line; the title stays", [PersonSocial.vital(row), after]): return
	if not _ok(Skills.of(team.combat_units[1]).is_empty(), "a person with no stored line keeps 50", Skills.of(team.combat_units[1])): return
	if not _finish_workflow_body(): return
	print("SITE_SKILLS_K1D_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
