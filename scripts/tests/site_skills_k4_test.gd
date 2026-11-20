extends "res://scripts/tests/site_building_ui_test.gd"
## 技能系統 K4a (reports/skill-system-plan.md V0.7 §6). Checks:
## - a round is 10 battles commanded (戰術) or 360 days as captain (統御); one round grows a command ability like one
##   full-time year grows a line, talent 悟性 (about 50 -> 55.9 at 悟性 50);
## - the whole number goes to command_abilities, the thousandths stay in the packet's `command`; an edited whole number
##   restarts the thousandths from it; from 80 one roll per round; 謀神 at 100; no command ability, no growth;
## - on a real Site the day's settlement writes the grown 戰術 into the person's command_abilities.
## Output: SITE_SKILLS_K4_PASS on success; quit(1) on failure.

const Skills = preload("res://scripts/terrain_lab/person_skills.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const YEAR_MICROS := 12960000000000

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SKILLS_K4 OK ", checks, ": ", message)
		return true
	push_error("SITE_SKILLS_K4_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _pure() -> bool:
	if not _ok(is_equal_approx(Skills.TACTICS_PER_BATTLE * 10.0, Skills.YEAR_SECONDS) and is_equal_approx(Skills.LEADERSHIP_PER_DAY * 360.0, Skills.YEAR_SECONDS), "10 battles or 360 days make one round"): return false
	var packet := {"version": 1, "aptitude": {"body": 50, "mind": 50}, "pending": {"tactics": YEAR_MICROS}}
	var ruled: Dictionary = Skills.settle_command(Skills.settle(packet, 1, 7), "tactics", 50, 1, 7)
	var milli := int(ruled.packet.get("command", {}).get("tactics", 0))
	if not _ok(int(ruled.value) == 55 and absi(milli - 55877) <= 30 and not ruled.packet.get("pending", {}).has("tactics") or int(ruled.packet.get("pending", {}).get("tactics", 0)) < 3600000000, "one round takes 戰術 50 to about 55.9; 55 is written, the thousandths kept", ruled): return false
	var again: Dictionary = ruled.packet.duplicate(true)
	var pending: Dictionary = again.get("pending", {})
	pending["tactics"] = int(pending.get("tactics", 0)) + YEAR_MICROS
	again["pending"] = pending
	var second: Dictionary = Skills.settle_command(again, "tactics", 55, 1, 7)
	if not _ok(int(second.value) > 55 and int(second.packet.command.tactics) > milli, "a second round keeps growing from the kept thousandths", second): return false
	var edited: Dictionary = Skills.settle_command({"version": 1, "command": {"tactics": 55877}, "pending": {"tactics": 1000000}}, "tactics", 70, 1, 7)
	if not _ok(int(edited.value) == 70 and int(edited.packet.command.tactics) == 70000, "an edited whole number restarts the thousandths from it", edited): return false
	var top: Dictionary = Skills.settle_command({"version": 1, "aptitude": {"body": 100, "mind": 100}, "command": {"leadership": 99000}, "pending": {"leadership": YEAR_MICROS}}, "leadership", 99, 1, 7)
	if not _ok(int(top.value) == 100 and Skills.titles_of(top.packet) == ["leadership"], "from 80 one roll per round; 軍神 at 100", top): return false
	var page := Skills.page(top.packet, {"body": 100, "mind": 100}, 50.0, 0, {"leadership": 100}, [])
	if not _ok(str(page[0].title) == "名號" and str(page[0].rows[0][0]) == "軍神", "the page lists 軍神", page[0]): return false
	if not _ok(not Skills.valid({"version": 1, "command": {"tactics": 100001}}) and not Skills.valid({"version": 1, "command": {}}) and not Skills.valid({"version": 1, "command": {"melee": 50000}}), "a malformed command map is refused"): return false
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
	var cadre: Dictionary = team.combat_units[0]
	cadre["command_abilities"] = {"tactics": 50, "leadership": 50, "coach": 50}
	cadre["skills"] = {"version": 1, "aptitude": {"body": 50, "mind": 50}, "pending": {"tactics": YEAR_MICROS}}
	var plain: Dictionary = team.combat_units[1]
	plain["command_abilities"] = {}
	plain["skills"] = {"version": 1, "pending": {"tactics": YEAR_MICROS}}
	data.site.minute = Calendar.day_start_minute(2) + 60
	controller.skills_day()
	if not _ok(int(cadre.command_abilities.tactics) == 55 and int(cadre.command_abilities.leadership) == 50 and int(Skills.of(cadre).get("command", {}).get("tactics", 0)) > 55000, "the settlement writes the grown 戰術 into command_abilities", [cadre.command_abilities, Skills.of(cadre)]): return
	if not _ok(plain.command_abilities.is_empty(), "no command ability held, no growth", plain.command_abilities): return
	if not _finish_workflow_body(): return
	print("SITE_SKILLS_K4_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
