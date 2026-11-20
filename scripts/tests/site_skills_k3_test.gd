extends SceneTree
## 技能系統 K3/K2b native inputs (Nekki 2026-11-20 A; reports/skill-system-plan.md V0.7 §4, §5.2). Checks:
## - PersonSkills.combat_inputs: 武力 + (近戰/騎乘/弓弩 - 50) x 0.5 clamped 0..100 and the medicine speed; an ordinary
##   soldier fights at 50 whatever his row says; no body is all defaults;
## - on a live crowd Site the next step writes every person's inputs into the native crowd (set_person_skill /
##   person_skill): a cadre with 武力 80, melee 100 and medicine 100 gets [100, 80, 80, 1.5], a soldier [50, 50, 50, x];
## - the inputs are not saved: a loaded copy of the saved crowd starts at the defaults;
## - a rescuer with medicine 100 advances the rescue's action seconds 1.5 times as fast (EV_RESCUED still follows; both
##   possible rescuers are at medicine 100).
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: SITE_SKILLS_K3_PASS on success; quit(1) on any failure.

const Skills = preload("res://scripts/terrain_lab/person_skills.gd")
const DT := 1.0 / 30.0
const S_RESCUE := 5

var checks := 0
var _finished := false
var lab: TerrainLab

func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void: _fail("240-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_SKILLS_K3_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SKILLS_K3 OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _near(values: Variant, wanted: Array) -> bool:
	if not (values is PackedFloat64Array or values is Array) or values.size() != wanted.size(): return false
	for at: int in range(wanted.size()):
		if absf(float(values[at]) - float(wanted[at])) > 0.001: return false
	return true

func _new_lab() -> TerrainLab:
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	var instance := packed.instantiate() as TerrainLab
	instance.pause_when_unfocused = false
	instance.movement_input_enabled = false
	root.add_child(instance)
	instance.set_process(false)
	instance.character.set_process(false)
	var worker := TerrainTestNPC.new()
	instance.add_child(worker)
	worker.set_process(false)
	instance.npc = worker
	for person: TerrainTestCharacter in instance.combat_actors: person.set_process(false)
	return instance

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "native startup and a fresh --crowd-test run id required"): return
	var cadre_row := {"military_role": "officer", "combat_ability": 80.0, "skills": {"version": 1, "lines": {"melee": 100000, "archery": 50000, "medicine": 100000}}}
	if not _check(_near(Skills.combat_inputs(cadre_row), [100.0, 80.0, 80.0, 1.5]), "a cadre: 武力 80 + (melee 100 - 50) x 0.5 = 100 on foot, 80 mounted and ranged, rescue x1.5", Skills.combat_inputs(cadre_row)): return
	if not _check(_near(Skills.combat_inputs({"military_role": "soldier", "combat_ability": 90.0, "skills": {"version": 1, "lines": {"melee": 100000}}}), [50.0, 50.0, 50.0, 1.0]) and _near(Skills.combat_inputs(null), [50.0, 50.0, 50.0, 1.0]), "an ordinary soldier fights at 50; no body is all defaults"): return
	if not _check(_near(Skills.combat_inputs({"military_role": "officer", "combat_ability": 10.0, "skills": {"version": 1, "lines": {"riding": 0}}}), [10.0, 0.0, 10.0, 1.0]), "the result never goes below 0"): return
	lab = _new_lab()
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 3, "attack": false, "ai_enabled": false, "entry": "west"},
		{"faction": 1, "count": 2, "attack": false, "ai_enabled": false, "entry": "east"}])
	if not _check(deployed.ok and lab.crowd_site.active, "a live crowd Site deploys", deployed): return
	var crowd: Variant = lab.crowd_site
	if not _check(crowd.crowd.has_method("set_person_skill") and crowd.crowd.has_method("person_skill"), "the native module has the skill inputs"): return
	var roster: Dictionary = {}
	for candidate: Dictionary in crowd.rosters:
		if int(candidate.faction_id) == 0: roster = candidate
	# Roles stay as deployed (the native crowd checks them; this small trial team is all officers). The soldier rule is
	# checked on combat_inputs above; here the patient keeps the defaults.
	var ids: Array = []
	for row: Dictionary in roster.units: ids.append(int(row.person_id))
	var cadre := int(ids[0])
	var soldier := int(ids[2]) # the patient
	var third := int(ids[1])
	var cadre_body: Dictionary = crowd._records[cadre]
	cadre_body["combat_ability"] = 80.0
	cadre_body["skills"] = {"version": 1, "lines": {"melee": 100000, "medicine": 100000}}
	crowd._records[third]["skills"] = {"version": 1, "lines": {"medicine": 100000}} # either team-mate may rescue: both at medicine 100
	crowd.mark_person_skills_dirty()
	crowd.step(DT, DT, 0.0)
	var cadre_index := int(crowd._index_by_id[cadre])
	var soldier_index := int(crowd._index_by_id[soldier])
	if not _check(_near(crowd.crowd.person_skill(cadre_index), [100.0, 80.0, 80.0, 1.5]) and _near(crowd.crowd.person_skill(soldier_index), [50.0, 50.0, 50.0, 1.0]), "the step writes the cadre's inputs into the native crowd; the patient keeps the defaults", [crowd.crowd.person_skill(cadre_index), crowd.crowd.person_skill(soldier_index)]): return
	if not _check(not bool(crowd.crowd.set_person_skill(cadre_index, 101.0, 50.0, 50.0, 1.0)) and not bool(crowd.crowd.set_person_skill(cadre_index, 50.0, 50.0, 50.0, 2.0)), "the native crowd refuses out-of-range inputs"): return
	# The native crowd does not save the inputs: a loaded copy of the saved crowd starts at the defaults (the Site sets
	# them again on its next step after every bind, CrowdSite._bind_people).
	var captured: Dictionary = lab.site_controller._capture_for_save()
	if not _check(captured.get("ok", false) == true, "the Site captures", captured): return
	var path: String = lab.site_controller.save_root.path_join("skills_k3.json")
	var saved: Dictionary = SiteStore.save(lab.terrain, path, crowd.crowd)
	if not _check(saved.get("ok", false) == true, "the Site saves", saved): return
	var loaded: Dictionary = SiteStore.load_site(path, Callable(), 1, false)
	var native: Variant = loaded.get("crowd_native")
	if not _check(loaded.get("ok", false) == true and native is Object and _near(native.person_skill(cadre_index), [50.0, 50.0, 50.0, 1.0]), "a loaded copy of the saved crowd starts the cadre at the defaults", native.person_skill(cadre_index) if native is Object else loaded): return
	crowd.mark_person_skills_dirty()
	crowd.step(DT, DT, 0.0)
	if not _check(_near(crowd.crowd.person_skill(cadre_index), [100.0, 80.0, 80.0, 1.5]), "the live crowd keeps the cadre's inputs", crowd.crowd.person_skill(cadre_index)): return
	# Rescue speed: the cadre (medicine 100) rescues the soldier knocked out beside him.
	var near: Dictionary = crowd.soldier_state(cadre_index)
	soldier_index = int(crowd._index_by_id[soldier])
	if not _check(crowd.set_soldier_fields(soldier_index, {"ko": 7200.0, "px": float(near.px) + 1.0, "py": float(near.py)}), "the soldier is knocked out beside the cadre"): return
	var before := int(crowd.event_counts.get(3, 0))
	var rescuing := -1
	var act_start := 0.0
	var frames := 0
	var rates: Array = []
	for _frame in range(900):
		crowd.step(DT, DT, 0.0)
		if int(crowd.event_counts.get(3, 0)) > before: break
		for identity: Variant in ids:
			var values: PackedFloat64Array = crowd.crowd.get_soldier_state(int(crowd._index_by_id[identity]))
			if values.size() > 24 and int(values[24]) == S_RESCUE and float(values[21]) > 0.0:
				if rescuing != int(identity):
					rescuing = int(identity)
					act_start = float(values[21])
					frames = 0
				else:
					frames += 1
					rates.append((float(values[21]) - act_start) / (float(frames) * DT))
	if not _check(int(crowd.event_counts.get(3, 0)) > before, "the rescue finishes (EV_RESCUED)", crowd.event_counts): return
	var rate: float = float(rates.back()) if not rates.is_empty() else 0.0
	if not _check(rescuing in [cadre, third] and absf(rate - 1.5) < 0.05, "a medicine-100 rescuer's action seconds advance 1.5 times as fast", [rescuing, rate, rates.size()]): return
	_finished = true
	print("SITE_SKILLS_K3_PASS: ", checks, " checks; personal ability and rescue speed reach the native crowd")
	lab.queue_free()
	for _frame: int in range(3): await process_frame
	TerrainArmy.release_contact_source()
	quit(0)
