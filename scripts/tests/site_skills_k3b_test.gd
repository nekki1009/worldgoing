extends "res://scripts/tests/site_building_ui_test.gd"
## 技能系統 K3b (reports/skill-system-plan.md V0.7 §5.3, §6). Checks:
## - a battle counts 70 hours; 武力 grows on the §5.3 curve at a third of the pace: three years' worth of battles take
##   武力 from 50 as far as one year takes a martial line (about 55.9 at aptitude 50);
## - from 80 武力 rolls once per three years' worth; at 100 it earns 武神 once; the remainder below one thousandth stays;
## - martial_line: a bow or crossbow trains 弓弩, mounted trains 騎乘, anything else 近戰;
## - on a real Site the day's settlement writes the grown 武力 into the person's combat_ability, other people untouched.
## Output: SITE_SKILLS_K3B_PASS on success; quit(1) on failure.

const Skills = preload("res://scripts/terrain_lab/person_skills.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const YEAR_MICROS := 12960000000000

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SKILLS_K3B OK ", checks, ": ", message)
		return true
	push_error("SITE_SKILLS_K3B_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _pure() -> bool:
	var talent := {"version": 1, "aptitude": {"body": 50, "mind": 50}}
	var line := talent.duplicate(true)
	line["pending"] = {"melee": YEAR_MICROS}
	var melee := Skills.level(Skills.settle(line, 1, 7), "melee")
	var three := talent.duplicate(true)
	three["pending"] = {"ability": YEAR_MICROS * 3}
	var grown: Dictionary = Skills.settle_ability(Skills.settle(three, 1, 7), 50.0, 1, 7)
	if not _ok(absf(float(grown.ability) - melee) < 0.002 and absf(melee - 55.9) < 0.2, "three years of battles take 武力 as far as one year takes a line", [grown, melee]): return false
	var one := talent.duplicate(true)
	one["pending"] = {"ability": YEAR_MICROS}
	var slow: Dictionary = Skills.settle_ability(one, 50.0, 1, 7)
	if not _ok(float(slow.ability) > 50.0 and float(slow.ability) < float(grown.ability), "one year of battles grows 武力 less", slow): return false
	var top := {"version": 1, "aptitude": {"body": 100, "mind": 100}, "pending": {"ability": YEAR_MICROS * 3}}
	var rolled: Dictionary = Skills.settle_ability(top, 96.0, 1, 7)
	if not _ok(float(rolled.ability) == 100.0 and Skills.titles_of(rolled.packet) == ["ability"] and int(rolled.packet.get("rolls", {}).get("ability", 0)) == 1, "from 80 three years' worth roll once; 100 earns 武神", rolled): return false
	var tiny: Dictionary = Skills.settle_ability({"version": 1, "pending": {"ability": 1000000}}, 63.4, 1, 7)
	if not _ok(float(tiny.ability) == 63.4 and int(tiny.packet.get("pending", {}).get("ability", 0)) == 1000000, "less than one thousandth keeps 武力 exact and the work pending", tiny): return false
	var bow := {"appearance": {"parts": {"weapon": "bow_01"}, "mounted": false}}
	var horse := {"appearance": {"parts": {"weapon": "spear_01"}, "mounted": true}}
	var foot := {"appearance": {"parts": {"weapon": "spear_01"}, "mounted": false}}
	if not _ok([Skills.martial_line(bow), Skills.martial_line(horse), Skills.martial_line(foot), Skills.martial_line({})] == ["archery", "riding", "melee", "melee"], "martial lines by weapon and mount"): return false
	if not _ok(Skills.valid({"version": 1, "pending": {"ability": 5}, "titles": ["ability"]}) and not Skills.valid({"version": 1, "lines": {"ability": 50000}}), "武力 grows through pending, never as a stored line"): return false
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
	var row: Dictionary = team.combat_units[0]
	row["combat_ability"] = 50.0
	row["skills"] = {"version": 1, "aptitude": {"body": 50, "mind": 50}, "pending": {"ability": YEAR_MICROS * 3, "melee": YEAR_MICROS}}
	var other: Dictionary = team.combat_units[1]
	var other_ability: Variant = other.get("combat_ability")
	data.site.minute = Calendar.day_start_minute(2) + 60
	controller.skills_day()
	if not _ok(absf(float(row.combat_ability) - 55.9) < 0.2 and absf(Skills.level(Skills.of(row), "melee") - 55.9) < 0.2 and int(Skills.of(row).get("pending", {}).get("ability", 0)) < 10800000000, "the settlement writes the grown 武力 into combat_ability (a remainder under one thousandth stays pending)", [row.combat_ability, Skills.of(row)]): return
	if not _ok(other.get("combat_ability") == other_ability, "nobody else's 武力 changes"): return
	if not _finish_workflow_body(): return
	print("SITE_SKILLS_K3B_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
