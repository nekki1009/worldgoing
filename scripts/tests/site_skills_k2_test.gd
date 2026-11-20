extends SceneTree
## 技能系統 K2 (reports/skill-system-plan.md V0.7 §4, §8; K2a): on a live crowd Site a team-mate rescues a knocked-out
## member (the native rescue that bandages and lifts, EV_RESCUED) and the rescuer's medicine gains the rescue's action
## seconds as pending work; the patient gains nothing; the daily settlement turns it into medicine (aptitude: 悟性).
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: SITE_SKILLS_K2_PASS on success; quit(1) on any failure.

const Skills = preload("res://scripts/terrain_lab/person_skills.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const DT := 1.0 / 30.0

var checks := 0
var _finished := false
var lab: TerrainLab

func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void: _fail("240-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_SKILLS_K2_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SKILLS_K2 OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

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

func _medicine_pending(identity: int) -> int:
	var body: Variant = lab.crowd_site._records.get(identity)
	return int(Skills.of(body).get("pending", {}).get("medicine", 0)) if body != null else 0

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "native startup and a fresh --crowd-test run id required"): return
	lab = _new_lab()
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 3, "attack": false, "ai_enabled": false, "entry": "west"},
		{"faction": 1, "count": 2, "attack": false, "ai_enabled": false, "entry": "east"}])
	if not _check(deployed.ok and lab.crowd_site.active, "a live crowd Site deploys", deployed): return
	var crowd: Variant = lab.crowd_site
	for _step in range(2): crowd.step(DT, DT, 0.0)
	var roster: Dictionary = {}
	for candidate: Dictionary in crowd.rosters:
		if int(candidate.faction_id) == 0: roster = candidate
	var ids: Array = []
	for row: Dictionary in roster.units: ids.append(int(row.person_id))
	if not _check(ids.size() == 3, "the friendly team has three people", ids): return
	var patient := int(ids[1])
	var patient_index := int(crowd._index_by_id[patient])
	var near: Dictionary = crowd.soldier_state(int(crowd._index_by_id[int(ids[0])]))
	if not _check(crowd.set_soldier_fields(patient_index, {"ko": 7200.0, "px": float(near.px) + 1.0, "py": float(near.py)}), "a team-mate is knocked out next to the others"): return
	var before_events := int(crowd.event_counts.get(3, 0))
	var rescued := false
	for _frame in range(900):
		crowd.step(DT, DT, 0.0)
		if int(crowd.event_counts.get(3, 0)) > before_events:
			rescued = true
			break
	var others := ids.filter(func(identity: int) -> bool: return identity != patient)
	var credited := others.filter(func(identity: int) -> bool: return _medicine_pending(identity) > 0)
	if not _check(rescued, "a team-mate rescues him (EV_RESCUED)", [crowd.event_counts, crowd.soldier_state(patient_index)]): return
	if not _check(credited.size() == 1 and _medicine_pending(int(credited[0])) == roundi(4.0 * 1000000.0) and _medicine_pending(patient) == 0, "the rescuer's medicine gains the rescue's 4 action seconds; the patient gains nothing", [credited, others.map(func(identity: int) -> int: return _medicine_pending(identity)), _medicine_pending(patient)]): return
	var rescuer := int(credited[0])
	lab.terrain.site.minute = Calendar.day_start_minute(5) + 60
	lab.site_controller.skills_day()
	var settled := Skills.of(crowd._records[rescuer])
	if not _check(Skills.level_milli(settled, "medicine") == 50000 and int(settled.get("pending", {}).get("medicine", 0)) == roundi(4.0 * 1000000.0), "4 seconds are worth less than one thousandth: the daily settlement keeps them pending", settled): return
	_finished = true
	print("SITE_SKILLS_K2_PASS: ", checks, " checks; a native rescue trains the rescuer's medicine")
	lab.queue_free()
	for _frame: int in range(3): await process_frame
	TerrainArmy.release_contact_source()
	quit(0)
