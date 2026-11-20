extends SceneTree
## 技能系統 K4c (reports/skill-system-plan.md V0.7 §5.7): school learning on the §5.3 curve (talent 悟性). Checks:
## - a full-time year of study from 0 reaches about 21 (literate, 20, in about 11 months) at 悟性 50;
## - lessons shorter than a thousandth of progress add up (twelve 300-second lessons = one hour);
## - the school's cap stops it; an edited learning value restarts the thousandths; 文曲 at 100.
## Output: SITE_SKILLS_K4C_PASS on success; quit(1) on failure.

const Skills = preload("res://scripts/terrain_lab/person_skills.gd")

var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SKILLS_K4C OK ", checks, ": ", message)
		return true
	push_error("SITE_SKILLS_K4C_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _run() -> void:
	var talent := {"version": 1, "aptitude": {"body": 50, "mind": 50}}
	var year: Dictionary = Skills.study(talent, Skills.YEAR_SECONDS, 0, 100, 1, 7)
	if not _ok(int(year.value) == 21 and int(year.packet.study) >= 21000, "a full-time year of study from 0 reaches about 21", year): return
	var months := Skills.seconds_between(0, 20000, 50.0) / Skills.YEAR_SECONDS * 12.0
	if not _ok(months > 10.0 and months < 12.0, "literate (20) in about 11 months of full-time study", months): return
	var lessons: Dictionary = talent.duplicate(true)
	var value := 0
	for _lesson: int in range(12):
		var step: Dictionary = Skills.study(lessons, 300.0, value, 100, 1, 7)
		lessons = step.packet
		value = int(step.value)
	var hour: Dictionary = Skills.study(talent, 3600.0, 0, 100, 1, 7)
	var lesson_total := int(lessons.get("study", 0)) * 1000000 + int(lessons.get("pending", {}).get("learning", 0))
	var hour_total := int(hour.packet.get("study", 0)) * 1000000 + int(hour.packet.get("pending", {}).get("learning", 0))
	if not _ok(int(lessons.get("study", 0)) == int(hour.packet.get("study", 0)) and absi(int(lessons.get("pending", {}).get("learning", 0)) - int(hour.packet.get("pending", {}).get("learning", 0))) < 1000, "twelve 300-second lessons equal one hour", [lessons, hour.packet, lesson_total, hour_total]): return
	var capped: Dictionary = Skills.study({"version": 1, "study": 39500}, Skills.YEAR_SECONDS * 5.0, 39, 40, 1, 7)
	if not _ok(int(capped.value) == 40 and int(capped.packet.study) == 40000, "the school's cap stops it", capped): return
	var at_cap: Dictionary = Skills.study({"version": 1, "study": 40000}, 300.0, 40, 40, 1, 7)
	if not _ok(int(at_cap.value) == 40 and not at_cap.packet.has("pending"), "a student at the cap learns nothing more", at_cap): return
	var edited: Dictionary = Skills.study({"version": 1, "study": 55877}, 1.0, 70, 100, 1, 7)
	if not _ok(int(edited.value) == 70 and int(edited.packet.study) == 70000, "an edited learning value restarts the thousandths", edited): return
	var top: Dictionary = Skills.study({"version": 1, "aptitude": {"body": 100, "mind": 100}, "study": 99000}, Skills.YEAR_SECONDS, 99, 100, 1, 7)
	if not _ok(int(top.value) == 100 and Skills.titles_of(top.packet) == ["learning"], "100 earns 文曲", top): return
	if not _ok(not Skills.valid({"version": 1, "study": 100001}), "a malformed study value is refused"): return
	print("SITE_SKILLS_K4C_PASS checks=", checks)
	quit(0)
