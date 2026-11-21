extends SceneTree
## Original SiteSustain consumes a shared lesson/training interval without a
## second fatigue clock. TerrainLab/Controller scene validation remains separate.
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _near(actual: float, expected: float, label: String) -> void:
	_check(is_finite(actual) and absf(actual - expected) < 0.000001, label)

func _run() -> void:
	var pool := {"fatigue": 79.9, "fatigue_rest": 0.0, "count": 3, "active": false}
	var members := {}
	var people: Array[Dictionary] = []
	for identity: int in [1, 2, 3]:
		var body := {"person_id": identity, "hp": 100.0, "ko": 0.0, "captive": false, "present": true, "fatigue": 79.9, "fatigue_rest": 0.0, "work_resting": false}
		Fatigue.bind(body, pool)
		members[identity] = body
		people.append({"person_id": identity, "body": body, "effort_rate": Fatigue.effort_rate(body), "rest_limited": true})
	var requests: Array = [
		{"provider": "person_actions", "key": "lesson", "participants": [people[0], people[1]], "remaining": 300.0, "productive_kind": "joint", "progress_multiplier": 1.0, "max_game_seconds": 54.0},
		{"provider": "training", "key": "3", "participants": [people[2]], "remaining": 10000.0, "productive_kind": "single", "progress_multiplier": 1.0, "max_game_seconds": 54.0}]
	var plan := Fatigue.plan_work_interval(requests, 54.0)
	_check(bool(plan.ok), "same original pool complete demands")
	if not plan.ok:
		quit(1)
		return
	var context := {"ordered": true, "commander": true, "safe": true, "stopped": true, "fed": true, "paused": false, "routed": false,
		"coach": 0.0, "controlled_person_id": 0, "training_multiplier": 1.0, "work_plan": plan}
	var before := members.duplicate(true)
	var result := Sustain.train(0.0, members, [3], 54.0, context)
	_check(bool(result.ok), "original training consumes legal complete-pool plan")
	if result.ok:
		_near(float(result.effort_seconds[3]), 36.0, "third real trainee stops with original pool at 80")
		_near(float(result.training), Fatigue.work_seconds(79.9, 36.0, Fatigue.WORK_RATE) / 3600.0 / 3.0, "original team living denominator is preserved")
		_check(result.handled_ids == [3], "only actual eligible trainee is handled")
	_check(members == before and float(pool.fatigue) == 79.9 and not pool.active, "Sustain has no second fatigue write")
	var capped := Sustain.train(1000.0, members, [3], 54.0, context)
	_check(bool(capped.ok) and float(capped.training) == 1000.0 and float(capped.effort_seconds[3]) > 0.0, "training cap preserves original ordered effort")
	for condition: String in ["ordered", "commander", "safe", "stopped", "fed"]:
		var blocked := context.duplicate()
		blocked[condition] = false
		var denied := Sustain.train(0.0, members, [3], 54.0, blocked)
		_check(bool(denied.ok) and float(denied.training) == 0.0 and denied.effort_seconds.is_empty(), "original training condition still owns legality: " + condition)
	var malformed := context.duplicate(true)
	malformed.work_plan.jobs.training["3"].participant_seconds[3] = 55.0
	_check(not Sustain.train(0.0, members, [3], 54.0, malformed).ok, "planned effort cannot exceed original interval")
	malformed = context.duplicate(true)
	malformed.work_plan.jobs.training["3"].participant_effective_seconds = []
	_check(not Sustain.train(0.0, members, [3], 54.0, malformed).ok, "malformed participant productivity refuses")
	_check(members == before, "negative plans cannot mutate original training bodies")
	print("TRAINING_WORK_PLAN %s %d checks" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
