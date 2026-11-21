extends SceneTree
## 技能系統 (reports/skill-system-plan.md V0.7 §5.2, §2): handcraft (ranged_craft, its technology trials included) runs
## at the craft line's speed, 0.5 + 工藝/100. Checks, on the ranged-crafting fixture:
## - a master (工藝 100) works an arrow batch 1.5 times as fast as a plain hand (no stored line) on the direct path, and
##   a novice (工藝 0) half as fast;
## - on the shared work plan the master's request is a one-person "sum" request carrying 1.5, the plain hand's request
##   is unchanged, and the planner gives the master 1.5 times the effective work;
## - the master finishes in duration / 1.5 and is credited the time actually worked.
## Output: SITE_SKILLS_HANDCRAFT_PASS on success; quit(1) on failure.

const Base = preload("res://scripts/tests/site_ranged_crafting_test.gd")
const Skills = preload("res://scripts/terrain_lab/person_skills.gd")
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")

var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SKILLS_HANDCRAFT OK ", checks, ": ", message)
		return true
	push_error("SITE_SKILLS_HANDCRAFT_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _fixture(craft: int) -> Variant:
	var fixture: Variant = Base.Fixture.new()
	if craft >= 0: fixture.character.skills = {"version": 1, "lines": {"craft": craft}}
	return fixture

func _elapsed(fixture: Variant, seconds: float) -> float:
	var started: Dictionary = fixture.actions.begin_ranged_craft(1, "arrow")
	if not started.ok: return -1.0
	fixture.actions.advance(seconds)
	return float(fixture.actions._jobs.values()[0].elapsed)

func _run() -> void:
	var duration := float(SiteRuntime.RANGED_RECIPES.arrow.duration)
	var plain: Variant = _fixture(-1)
	var master: Variant = _fixture(100000)
	var novice: Variant = _fixture(0)
	var step := duration * 0.4
	var plain_elapsed := _elapsed(plain, step)
	var master_elapsed := _elapsed(master, step)
	var novice_elapsed := _elapsed(novice, step)
	if not _ok(plain_elapsed > 0.0 and absf(master_elapsed / plain_elapsed - 1.5) < 0.001 and absf(novice_elapsed / plain_elapsed - 0.5) < 0.001,
		"direct path: 工藝 100 works 1.5x, 工藝 0 half, no stored line unchanged", [plain_elapsed, master_elapsed, novice_elapsed]): return
	# The shared work plan (crowd and native steps): the same factor on the planner's one-person request.
	var plain_requests: Array[Dictionary] = plain.actions.work_requests(10.0)
	var master_requests: Array[Dictionary] = master.actions.work_requests(10.0)
	if not _ok(plain_requests.size() == 1 and master_requests.size() == 1 and str(plain_requests[0].productive_kind) == "single" and str(master_requests[0].productive_kind) == "sum"
		and is_equal_approx(float(master_requests[0].participants[0].progress_multiplier), 1.5) and float(master_requests[0].progress_multiplier) == 1.0,
		"shared plan: the master's request carries 1.5 on its participant, the plain hand's stays single", [plain_requests, master_requests]): return
	var plain_plan: Dictionary = Fatigue.plan_work_interval(plain_requests, 10.0)
	var master_plan: Dictionary = Fatigue.plan_work_interval(master_requests, 10.0)
	var plain_work := float(plain_plan.get("jobs", {}).get("person_actions", {}).get(str(plain_requests[0].key), {}).get("effective_seconds", -1.0))
	var master_work := float(master_plan.get("jobs", {}).get("person_actions", {}).get(str(master_requests[0].key), {}).get("effective_seconds", -1.0))
	if not _ok(plain_plan.get("ok") == true and master_plan.get("ok") == true and plain_work > 0.0 and absf(master_work / plain_work - 1.5) < 0.001,
		"shared plan: the planner admits the request and gives the master 1.5x the effective work", [plain_plan, master_plan]): return
	# The master finishes in duration / 1.5 and is credited the time he worked.
	master.actions.advance(duration / 1.5 - step + 0.01)
	var results: Array = master.actions.settle_after_contacts()
	var pending := int(Skills.of(master.character).get("pending", {}).get("craft", 0))
	if not _ok(results.size() == 1 and results[0].ok and absi(pending - roundi(duration / 1.5 * 1000000.0)) <= 1,
		"the master finishes in duration / 1.5 and is credited the time actually worked", [results, Skills.of(master.character)]): return
	for fixture: Variant in [plain, master, novice]: fixture.close()
	print("SITE_SKILLS_HANDCRAFT_PASS checks=", checks)
	quit(0)
