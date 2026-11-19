extends SceneTree
## Pure planner oracle only. No body trajectory, synthetic melee packet or
## TerrainLab acceptance is claimed by this component test.
const F = preload("res://scripts/terrain_lab/person_fatigue.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _person(identity: int, body: Dictionary, rate: float, until: float = 4.0) -> Dictionary:
	return {"person_id": identity, "body": body, "effort_rate": rate,
		"rest_limited": true, "active_until_game_seconds": until}

func _request(key: String, participants: Array, productive: String, multiplier: float = 1.0) -> Dictionary:
	return {"provider": "person_actions", "key": key, "participants": participants,
		"remaining": 100.0, "productive_kind": productive, "progress_multiplier": multiplier,
		"max_game_seconds": 4.0, "paused": ""}

func _run() -> void:
	var pool_a := {"fatigue": 40.0, "fatigue_rest": 0.0, "count": 2}
	var pool_b := {"fatigue": 40.3, "fatigue_rest": 0.0, "count": 1}
	var teacher := {"fatigue": 0.0, "fatigue_rest": 0.0, "_fatigue_pool": pool_a}
	var student := {"fatigue": 0.0, "fatigue_rest": 0.0, "_fatigue_pool": pool_b}
	var third := {"fatigue": 0.0, "fatigue_rest": 0.0, "_fatigue_pool": pool_a}
	var course: Dictionary = _request("course", [_person(1, teacher, 0.1, 2.0), _person(2, student, 0.2)], "joint")
	var other: Dictionary = _request("third", [_person(3, third, 0.4)], "raw")
	var before: PackedByteArray = var_to_bytes([pool_a, pool_b, teacher, student, third, course, other])
	var planned: Dictionary = F.plan_work_interval([course, other], 4.0)
	_check(planned.ok, "Two original pool projections and an independent third activity are legal")
	if planned.ok:
		var lesson: Dictionary = planned.jobs.person_actions.course
		var expected: float = F.joint_work_seconds(40.0, 40.3, 2.0, 0.5, 0.2)
		_check(absf(float(lesson.effective_seconds) - expected) < 0.000000001,
			"Lesson uses pointwise minimum with TOTAL pool effort before its real activity boundary")
		_check(float(lesson.participant_seconds[1]) == 2.0 and float(lesson.participant_seconds[2]) == 2.0
			and lesson.paused == "CONTACT", "One course participant ending stops both course efforts exactly")
		_check(float(planned.jobs.person_actions.third.participant_seconds[3]) == 4.0,
			"Unrelated legitimate work survives the course contact boundary")
		for pool: Dictionary in planned.pools:
			if is_same(pool.original_pool, pool_a):
				_check(absf(float(pool.fatigue) - 41.8) < 0.000000001,
					"Shared pool counts teacher2*0.1 plus third4*0.4 once")
			elif is_same(pool.original_pool, pool_b):
				_check(absf(float(pool.fatigue) - 40.7) < 0.000000001,
					"Other course pool stops at the same joint boundary")
	var swapped: Dictionary = course.duplicate(false)
	swapped.participants = [course.participants[1], course.participants[0]]
	var swap_plan: Dictionary = F.plan_work_interval([other, swapped], 4.0)
	_check(swap_plan.ok and planned.ok and absf(float(swap_plan.jobs.person_actions.course.effective_seconds)
		- float(planned.jobs.person_actions.course.effective_seconds)) < 0.000000001,
		"Provider ordering and teacher/student ordering cannot change productive work")
	var cold: Dictionary = _request("cold", [_person(1, teacher, 0.1)], "single", 0.5)
	var cold_plan: Dictionary = F.plan_work_interval([cold, other], 4.0)
	_check(cold_plan.ok and absf(float(cold_plan.jobs.person_actions.cold.effective_seconds)
		- 0.5 * F.work_seconds(40.0, 4.0, 0.5)) < 0.000000001,
		"Cold NPC research halves productive work once; actual effort remains full")
	_check(cold_plan.ok and float(cold_plan.jobs.person_actions.cold.participant_seconds[1]) == 4.0,
		"Cold multiplier never halves fatigue effort or elapsed original interval")
	_check(var_to_bytes([pool_a, pool_b, teacher, student, third, course, other]) == before,
		"Every positive and negative pure planner call preserves original input bytes")
	var short_course: Dictionary = course.duplicate(false)
	short_course.remaining = 0.25
	var completed: Dictionary = F.plan_work_interval([short_course, other], 4.0)
	_check(completed.ok and absf(float(completed.jobs.person_actions.course.effective_seconds) - 0.25) < 0.000000001
		and float(completed.jobs.person_actions.course.actual_seconds) < 2.0,
		"True completion inverse stops both course participants before a later contact bound")
	print("TECH_GD_CONTACT_LESSON_COLD_MATH: " + JSON.stringify({"checks": checks, "failures": failures,
		"scope": "pure_math_only_not_maincaller_or_receipt_acceptance"}))
	quit(0 if failures.is_empty() else 1)
