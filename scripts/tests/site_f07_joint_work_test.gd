extends SceneTree
## Pure F07 math contract. No scene, owner, inventory, clock or fatigue mutation.
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _near(actual: float, expected: float, label: String, tolerance: float = 0.000001) -> void:
	_check(is_finite(actual) and absf(actual - expected) <= tolerance, "%s: %.12f != %.12f" % [label, actual, expected])

func _split_joint(a: float, b: float, seconds: float, rate_a: float, rate_b: float, pieces: int) -> float:
	var result := 0.0
	var elapsed := 0.0
	for index: int in pieces:
		var end := seconds * float(index + 1) / float(pieces)
		result += Fatigue.joint_work_seconds(minf(100.0, a + elapsed * rate_a), minf(100.0, b + elapsed * rate_b), end - elapsed, rate_a, rate_b)
		elapsed = end
	return result

func _run() -> void:
	var w := 10.0 / 3600.0
	# R29: whole-frame min of individual integrals gives the wrong answer.
	var shared := Fatigue.joint_work_seconds(40.0, 40.3, 300.0, w, w / 10.0)
	_near(shared, 287.108957165, "cross-pool pointwise minimum")
	_near(Fatigue.joint_work_seconds(40.3, 40.0, 300.0, w / 10.0, w), shared, "teacher/student swap")
	_near(_split_joint(40.0, 40.3, 300.0, w, w / 10.0, 137), shared, "crossing long/split interval")
	_check(minf(Fatigue.work_seconds(40.0, 300.0, w), Fatigue.work_seconds(40.3, 300.0, w / 10.0)) > shared + 0.07, "whole-frame minimum must remain detectably wrong")
	_near(Fatigue.joint_work_seconds(40.0, 40.3, 120.0, w, w / 10.0) + Fatigue.joint_work_seconds(40.0 + 120.0 * w, 40.3 + 12.0 * w, 180.0, w, w / 10.0), shared, "exact equality event")
	# Both people share one total pool slope, not twice that slope or half the output.
	_near(Fatigue.joint_work_seconds(79.9, 79.9, 36.0, w, w), 29.652291888786, "same pool at 80")
	_near(Fatigue.joint_work_seconds(40.0, 40.0, 300.0, w, w), Fatigue.work_seconds(40.0, 300.0, w), "same pool counts productive work once")
	_near((80.0 - 79.9) / (2.0 * w / 2.0), 36.0, "two-person total slope")
	_near((80.0 - 79.9) / (3.0 * w / 3.0), 36.0, "third worker contributes to same pool")
	# Golden values retain the original positive-rate formula across all boundaries.
	_near(Fatigue.work_seconds(29.95, 300.0, w), 299.527699615189, "cross 30")
	_near(Fatigue.work_seconds(79.9, 120.0, w), 98.800293676814, "cross 80 is math; caller owns rest")
	_near(Fatigue.work_seconds(99.0, 100.0, 0.1), 76.935784487540, "cross 100")
	_near(Fatigue.work_seconds(29.0, 1000.0, 0.1), 845.260206834402, "cross 30 and 100")
	for values: Array in [[29.0, 35.0, 1000.0, 0.1, 0.02], [79.9, 75.0, 120.0, w, 0.05], [99.0, 98.0, 100.0, 0.1, 0.2], [29.0, 80.0, 1000.0, 0.1, 0.0]]:
		var whole := Fatigue.joint_work_seconds(values[0], values[1], values[2], values[3], values[4])
		_near(_split_joint(values[0], values[1], values[2], values[3], values[4], 113), whole, "30/80/100 partition independence")
		_near(Fatigue.joint_work_seconds(values[1], values[0], values[2], values[4], values[3]), whole, "30/80/100 swap")
	# Zero slope is a valid constant path, including one moving and one constant path.
	_near(Fatigue.work_seconds(20.0, 60.0, 0.0), 60.0, "fresh zero slope")
	_near(Fatigue.work_seconds(100.0, 60.0, 0.0), 60.0 / 1.3, "capped zero slope")
	_near(Fatigue.work_seconds(40.0, 60.0, 1.0e-300), 60.0 / (1.0 + 0.3 / 7.0), "finite numerically constant slope")
	_near(Fatigue.joint_work_seconds(20.0, 100.0, 60.0, 0.0, 0.0), 60.0 / 1.3, "two constant paths")
	_near(Fatigue.joint_work_seconds(0.0, 100.0, 100.0, 0.1, 0.0), 100.0 / 1.3, "constant slower path")
	_near(Fatigue.joint_work_seconds(0.0, 100.0, 0.0, w, 0.0), 0.0, "empty interval")
	# Inverses return real elapsed time, cap when insufficient, and never impose REST.
	_near(Fatigue.seconds_for_joint_work(40.0, 40.3, shared, 400.0, w, w / 10.0), 300.0, "joint inverse through crossing")
	_near(Fatigue.seconds_for_joint_work(40.3, 40.0, shared, 400.0, w / 10.0, w), 300.0, "inverse swap")
	_near(Fatigue.seconds_for_joint_work(40.0, 40.3, 300.0, 120.0, w, w / 10.0), 120.0, "joint inverse available time cap")
	_near(Fatigue.seconds_for_work(79.9, 29.652291888786, 120.0, w), 36.0, "inverse exact 80 event")
	_near(Fatigue.seconds_for_work(29.0, 845.260206834402, 1200.0, 0.1), 1000.0, "inverse cross 30 and 100")
	_near(Fatigue.seconds_for_work(100.0, 60.0, 100.0, 0.0), 78.0, "zero slope inverse")
	_near(Fatigue.seconds_for_joint_work(20.0, 100.0, 60.0, 100.0, 0.0, 0.0), 78.0, "constant joint inverse")
	_near(Fatigue.seconds_for_work(100.0, 60.0, 1.0e200, 0.0), 78.0, "finite large limit keeps small inverse precise")
	_near(Fatigue.seconds_for_joint_work(20.0, 100.0, 60.0, 1.0e200, 0.0, 0.0), 78.0, "finite large joint limit keeps inverse precise")
	_near(Fatigue.seconds_for_work(40.0, 300.0, 120.0, w), 120.0, "single inverse available time cap")
	_near(Fatigue.seconds_for_work(40.0, 0.0, 120.0, w), 0.0, "zero goal")
	_near(Fatigue.seconds_for_joint_work(40.0, 40.3, 0.0, 120.0, w, w / 10.0), 0.0, "zero joint goal")
	_near(Fatigue.seconds_for_work(40.0, 1.0, 0.0, w), 0.0, "zero available time")
	_near(Fatigue.seconds_for_joint_work(40.0, 40.3, 1.0, 0.0, w, w / 10.0), 0.0, "zero joint available time")
	_test_work_plan()
	# Illegal data fails closed as NAN; a caller must reject it, not grant work.
	for invalid: float in [NAN, INF, -INF, -0.1, 100.1]:
		_check(is_nan(Fatigue.work_seconds(invalid, 60.0, w)), "invalid fatigue in work_seconds")
		_check(is_nan(Fatigue.joint_work_seconds(invalid, 40.0, 60.0, w, w)), "invalid first joint fatigue")
		_check(is_nan(Fatigue.joint_work_seconds(40.0, invalid, 60.0, w, w)), "invalid second joint fatigue")
		_check(is_nan(Fatigue.seconds_for_work(invalid, 1.0, 60.0, w)), "invalid fatigue in inverse")
		_check(is_nan(Fatigue.seconds_for_joint_work(40.0, invalid, 1.0, 60.0, w, w)), "invalid fatigue in joint inverse")
	for invalid: float in [NAN, INF, -INF, -0.1]:
		_check(is_nan(Fatigue.work_seconds(40.0, invalid, w)), "invalid work time")
		_check(is_nan(Fatigue.work_seconds(40.0, 60.0, invalid)), "invalid work slope")
		_check(is_nan(Fatigue.joint_work_seconds(40.0, 40.3, invalid, w, w)), "invalid joint time")
		_check(is_nan(Fatigue.joint_work_seconds(40.0, 40.3, 60.0, invalid, w)), "invalid first joint slope")
		_check(is_nan(Fatigue.joint_work_seconds(40.0, 40.3, 60.0, w, invalid)), "invalid second joint slope")
		_check(is_nan(Fatigue.seconds_for_work(40.0, invalid, 60.0, w)), "invalid single goal")
		_check(is_nan(Fatigue.seconds_for_work(40.0, 1.0, invalid, w)), "invalid single time limit")
		_check(is_nan(Fatigue.seconds_for_work(40.0, 1.0, 60.0, invalid)), "invalid single inverse slope")
		_check(is_nan(Fatigue.seconds_for_joint_work(40.0, 40.3, invalid, 60.0, w, w)), "invalid joint goal")
		_check(is_nan(Fatigue.seconds_for_joint_work(40.0, 40.3, 1.0, invalid, w, w)), "invalid joint time limit")
		_check(is_nan(Fatigue.seconds_for_joint_work(40.0, 40.3, 1.0, 60.0, invalid, w)), "invalid first joint inverse slope")
		_check(is_nan(Fatigue.seconds_for_joint_work(40.0, 40.3, 1.0, 60.0, w, invalid)), "invalid second joint inverse slope")
	_check(is_nan(Fatigue.seconds_for_work(40.0, -1.0, 0.0, w)), "invalid goal not hidden by zero interval")
	_check(is_nan(Fatigue.seconds_for_joint_work(40.0, 40.3, 0.0, 0.0, -1.0, w)), "invalid slope not hidden by zero goal")
	print("F07_JOINT_WORK_MATH %s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func _test_body(fatigue: float, rested: float = 0.0, resting: bool = false) -> Dictionary:
	return {"fatigue": fatigue, "fatigue_rest": rested, "work_resting": resting}

func _participant(identity: int, body: Dictionary, rate: float, limited: bool = true) -> Dictionary:
	return {"person_id": identity, "body": body, "effort_rate": rate, "rest_limited": limited}

func _request(key: String, people: Array, remaining: float, kind: String = "single", multiplier: float = 1.0, maximum: float = 3600.0, provider: String = "actions") -> Dictionary:
	return {"provider": provider, "key": key, "participants": people, "remaining": remaining, "productive_kind": kind, "progress_multiplier": multiplier, "max_game_seconds": maximum}

func _test_work_plan() -> void:
	var w := 10.0 / 3600.0
	var original := {"fatigue": 79.9, "fatigue_rest": 12.0, "count": 2}
	var a := _test_body(0.0)
	var b := _test_body(0.0)
	Fatigue.bind(a, original)
	Fatigue.bind(b, original)
	var requests := [_request("lesson", [_participant(1, a, w / 2.0), _participant(2, b, w / 2.0)], 300.0, "joint")]
	var before := JSON.stringify(requests)
	var plan := Fatigue.plan_work_interval(requests, 100.0)
	_check(bool(plan.ok), "shared lesson plan is valid")
	if not plan.ok: return
	var lesson: Dictionary = plan.jobs.actions.lesson
	_near(float(lesson.actual_seconds), 36.0, "full pool reaches 80 after 36 actual seconds")
	_near(float(lesson.effective_seconds), 29.652291888786, "shared lesson productive seconds")
	_near(float(lesson.participant_seconds[1]), 36.0, "teacher handled actual seconds")
	_near(float(lesson.participant_seconds[2]), 36.0, "student handled actual seconds")
	_check(str(lesson.paused) == "REST", "unfinished lesson pauses both people")
	_check(plan.pools.size() == 1 and is_same(plan.pools[0].original_pool, original) and is_same(plan.pools[0].body, a), "plan borrows one original pool and representative body")
	_near(float(plan.pools[0].fatigue), 80.0, "one planned pool charge")
	_near(float(plan.pools[0].fatigue_rest), 0.0, "actual work resets planned rest")
	_near(float(plan.pools[0].effort_seconds), 72.0, "both original people contributed effort")
	_near(float(plan.pools[0].segments[1].seconds), 64.0, "idle tail is exposed without granting recovery")
	_check(before == JSON.stringify(requests) and float(original.fatigue) == 79.9 and float(original.fatigue_rest) == 12.0, "planner never writes requests or original pool")
	# A third legal worker changes the same total slope before its own completion.
	original = {"fatigue": 79.9, "fatigue_rest": 0.0, "count": 3}
	a = _test_body(0.0)
	b = _test_body(0.0)
	var c := _test_body(0.0)
	for body: Dictionary in [a, b, c]: Fatigue.bind(body, original)
	requests = [_request("lesson", [_participant(1, a, w / 3.0), _participant(2, b, w / 3.0)], 300.0, "joint"), _request("third", [_participant(3, c, w / 3.0)], 1000.0)]
	plan = Fatigue.plan_work_interval(requests, 100.0)
	_check(bool(plan.ok), "third worker plan is valid")
	if not plan.ok: return
	_near(float(plan.jobs.actions.lesson.actual_seconds), 36.0, "third worker is included in full slope")
	_near(float(plan.jobs.actions.third.actual_seconds), 36.0, "third worker shares same 80 endpoint")
	requests[1].remaining = Fatigue.work_seconds(79.9, 10.0, w)
	plan = Fatigue.plan_work_interval(requests, 100.0)
	_check(bool(plan.ok), "early third completion plan is valid")
	if not plan.ok: return
	_near(float(plan.jobs.actions.third.actual_seconds), 10.0, "third work completes at its exact actual time")
	_near(float(plan.jobs.actions.lesson.actual_seconds), 49.0, "remaining slope is recomputed after third completion")
	var reverse := Fatigue.plan_work_interval([requests[1], requests[0]], 100.0)
	_check(bool(reverse.ok), "reordered plan is valid")
	if not reverse.ok: return
	_near(float(reverse.jobs.actions.lesson.actual_seconds), float(plan.jobs.actions.lesson.actual_seconds), "request order does not change time")
	_near(float(reverse.jobs.actions.lesson.effective_seconds), float(plan.jobs.actions.lesson.effective_seconds), "request order does not change productivity")
	var split_source := {"fatigue": 79.9, "fatigue_rest": 0.0, "count": 3}
	var split_a := _test_body(0.0)
	var split_b := _test_body(0.0)
	var split_c := _test_body(0.0)
	for body: Dictionary in [split_a, split_b, split_c]: Fatigue.bind(body, split_source)
	var partitioned := _consume_partitioned_plans([_request("lesson", [_participant(1, split_a, w / 3.0), _participant(2, split_b, w / 3.0)], 300.0, "joint"), _request("third", [_participant(3, split_c, w / 3.0)], Fatigue.work_seconds(79.9, 10.0, w))], 100.0, 137)
	_check(bool(partitioned.ok), "partitioned full-pool plan is valid")
	if not partitioned.ok: return
	_near(float(partitioned.jobs.actions.lesson.actual_seconds), float(plan.jobs.actions.lesson.actual_seconds), "full-pool long/split actual time")
	_near(float(partitioned.jobs.actions.lesson.effective_seconds), float(plan.jobs.actions.lesson.effective_seconds), "full-pool long/split productive time")
	_near(float(split_source.fatigue), 80.0, "partitioned plans reach same original pool endpoint")
	requests[1].remaining = 1000.0
	requests[1].max_game_seconds = 10.0
	plan = Fatigue.plan_work_interval(requests, 100.0)
	_check(bool(plan.ok), "finite third work window is valid")
	if not plan.ok: return
	_near(float(plan.jobs.actions.lesson.actual_seconds), 49.0, "max work window ends the third slope")
	# A running third person is not stopped by another person's work REST limit.
	requests[1] = _request("run", [_participant(3, c, 0.1 / 3.0, false)], 100.0, "raw", 1.0, 100.0, "movement")
	plan = Fatigue.plan_work_interval(requests, 100.0)
	_check(bool(plan.ok), "concurrent run plan is valid")
	if not plan.ok: return
	var until_rest := (80.0 - 79.9) / (2.0 * w / 3.0 + 0.1 / 3.0)
	_near(float(plan.jobs.actions.lesson.actual_seconds), until_rest, "RUN contributes to lesson's 80 boundary")
	_near(float(plan.jobs.movement.run.actual_seconds), 100.0, "RUN continues after lesson stops")
	_near(float(plan.pools[0].fatigue), 80.0 + (100.0 - until_rest) * 0.1 / 3.0, "unrestricted effort still raises the original pool")
	# Independent teacher/student pools use total slopes and pointwise minimum.
	a = _test_body(40.0)
	b = _test_body(40.3)
	requests = [_request("crossing", [_participant(1, a, w), _participant(2, b, w / 10.0)], 300.0, "joint")]
	plan = Fatigue.plan_work_interval(requests, 300.0)
	_check(bool(plan.ok), "cross-pool plan is valid")
	if not plan.ok: return
	_near(float(plan.jobs.actions.crossing.effective_seconds), 287.108957165, "planner uses pointwise minimum through crossing")
	_near(float(plan.pools[0].fatigue), 40.0 + 300.0 * w, "teacher pool keeps actual effort")
	_near(float(plan.pools[1].fatigue), 40.3 + 30.0 * w, "student pool keeps actual effort")
	var whole_productive := float(plan.jobs.actions.crossing.effective_seconds)
	a = _test_body(40.0)
	b = _test_body(40.3)
	var split_request := _request("crossing", [_participant(1, a, w), _participant(2, b, w / 10.0)], 300.0, "joint")
	var split_productive := 0.0
	var split_actual := 0.0
	var elapsed := 0.0
	for index: int in 137:
		var end := 300.0 * float(index + 1) / 137.0
		var part := Fatigue.plan_work_interval([split_request], end - elapsed)
		_check(bool(part.ok), "split planner interval is valid")
		if not part.ok: return
		var record: Dictionary = part.jobs.actions.crossing
		split_productive += float(record.effective_seconds)
		split_actual += float(record.actual_seconds)
		split_request.remaining = maxf(0.0, float(split_request.remaining) - float(record.effective_seconds))
		for group: Dictionary in part.pools:
			group.body.fatigue = float(group.fatigue) # Test simulates original owner consuming a plan.
			group.body.fatigue_rest = float(group.fatigue_rest)
		elapsed = end
	_near(split_productive, whole_productive, "planner long/split crossing agreement")
	_near(split_actual, 300.0, "planner partitions real effort once")
	# Cold 0.5 output changes the real work's completion time, never its effort.
	a = _test_body(0.0)
	plan = Fatigue.plan_work_interval([_request("cold", [_participant(1, a, w)], 120.0, "single", 0.5)], 300.0)
	_check(bool(plan.ok), "cold multiplier plan is valid")
	if not plan.ok: return
	_near(float(plan.jobs.actions.cold.actual_seconds), 240.0, "cold work requires 240 actual seconds")
	_near(float(plan.jobs.actions.cold.effective_seconds), 120.0, "cold work reaches original effective requirement")
	_near(float(plan.pools[0].fatigue), 240.0 * w, "cold effort is not halved")
	# Different courses may share a pool; sum/raw retain their original clocks.
	original = {"fatigue": 40.0, "fatigue_rest": 0.0, "count": 4}
	a = _test_body(0.0)
	b = _test_body(0.0)
	c = _test_body(0.0)
	var d := _test_body(0.0)
	for body: Dictionary in [a, b, c, d]: Fatigue.bind(body, original)
	requests = [_request("one", [_participant(1, a, w / 4.0), _participant(2, b, w / 4.0)], 300.0, "joint"), _request("two", [_participant(3, c, w / 4.0), _participant(4, d, w / 4.0)], 300.0, "joint")]
	plan = Fatigue.plan_work_interval(requests, 100.0)
	_check(bool(plan.ok), "two-course shared pool plan is valid")
	if not plan.ok: return
	_near(float(plan.jobs.actions.one.effective_seconds), Fatigue.work_seconds(40.0, 100.0, w), "first course gets one common interval")
	_near(float(plan.jobs.actions.two.effective_seconds), float(plan.jobs.actions.one.effective_seconds), "second course sees same full slope")
	_near(float(plan.pools[0].fatigue), 40.0 + 100.0 * w, "four people charge the pool once")
	requests = [_request("training", [_participant(1, a, w / 4.0), _participant(2, b, w / 4.0)], 1000.0, "sum"), _request("equipment", [_participant(3, c, w / 4.0), _participant(4, d, w / 4.0)], 20.0, "raw")]
	plan = Fatigue.plan_work_interval(requests, 20.0)
	_check(bool(plan.ok), "sum/raw shared pool plan is valid")
	if not plan.ok: return
	_near(float(plan.jobs.actions.training.effective_seconds), 2.0 * Fatigue.work_seconds(40.0, 20.0, w), "sum is productive seconds across participants")
	_near(float(plan.jobs.actions.equipment.effective_seconds), 20.0, "raw multi-person work does not double progress")
	plan = Fatigue.plan_work_interval([_request("sum_end", [_participant(1, _test_body(0.0), w), _participant(2, _test_body(0.0), w)], 60.0, "sum")], 100.0)
	_check(bool(plan.ok), "sum completion plan is valid")
	if not plan.ok: return
	_near(float(plan.jobs.actions.sum_end.actual_seconds), 30.0, "sum completes using both participants' productive time")
	_near(float(plan.jobs.actions.sum_end.effective_seconds), 60.0, "sum completion is not one person's output")
	_near(float(plan.jobs.actions.sum_end.participant_effective_seconds[1]), 30.0, "shared work exposes each person's unweighted contribution")
	_near(float(plan.jobs.actions.sum_end.participant_effective_seconds[2]), 30.0, "shared work does not hand the full sum to each worker")
	# Water/slot productivity changes production, never actual pool effort.
	var weighted_a := _participant(1, _test_body(40.0), 0.0)
	var weighted_b := _participant(2, _test_body(60.0), 0.0)
	weighted_a["progress_multiplier"] = 1.5
	weighted_b["progress_multiplier"] = 0.25
	var weighted := _request("weighted", [weighted_a, weighted_b], 60.0, "sum")
	plan = Fatigue.plan_work_interval([weighted], 100.0)
	_check(bool(plan.ok), "weighted shared-batch completion is valid")
	if not plan.ok: return
	var finish := 60.0 / (1.5 / (1.0 + Fatigue.slowdown(40.0)) + 0.25 / (1.0 + Fatigue.slowdown(60.0)))
	var weighted_job: Dictionary = plan.jobs.actions.weighted
	_near(float(weighted_job.actual_seconds), finish, "weighted batch stops at the exact shared completion boundary")
	_near(float(weighted_job.effective_seconds), 60.0, "weighted production completes once")
	_near(float(weighted_job.participant_seconds[1]), finish, "first slot effort is not multiplied by productivity")
	_near(float(weighted_job.participant_seconds[2]), finish, "second slot effort is not divided by productivity")
	_near(float(weighted_job.participant_effective_seconds[1]), finish / (1.0 + Fatigue.slowdown(40.0)), "first slot exposes its unweighted productive seconds")
	_near(float(weighted_job.participant_effective_seconds[2]), finish / (1.0 + Fatigue.slowdown(60.0)), "second slot exposes its unweighted productive seconds")
	var weighted_swapped := weighted.duplicate(true)
	weighted_swapped.participants.reverse()
	var swapped_plan := Fatigue.plan_work_interval([weighted_swapped], 100.0)
	_near(float(swapped_plan.jobs.actions.weighted.actual_seconds), finish, "weighted participant order cannot change completion")
	var weighted_split := _consume_partitioned_plans([weighted.duplicate(true)], 100.0, 137)
	_near(float(weighted_split.jobs.actions.weighted.actual_seconds), finish, "weighted shared work remains invariant under partition")
	_near(float(weighted_split.jobs.actions.weighted.effective_seconds), 60.0, "partitioned weighted production is not duplicated")
	# Unlike a lesson, each original vehicle worker can rest independently.
	weighted_a = _participant(1, _test_body(79.9), w)
	weighted_b = _participant(2, _test_body(0.0), w)
	weighted_a["progress_multiplier"] = 2.0
	weighted_b["progress_multiplier"] = 0.5
	weighted = _request("partial_rest", [weighted_a, weighted_b], 100.0, "sum")
	plan = Fatigue.plan_work_interval([weighted], 100.0)
	_check(bool(plan.ok), "shared work continues after only one worker reaches REST")
	if not plan.ok: return
	var rested_work := Fatigue.work_seconds(79.9, 36.0, w)
	finish = (100.0 - 2.0 * rested_work) / 0.5
	var partial: Dictionary = plan.jobs.actions.partial_rest
	_near(float(partial.actual_seconds), finish, "remaining worker completes the original shared batch")
	_near(float(partial.participant_seconds[1]), 36.0, "rested worker contributes no later effort")
	_near(float(partial.participant_seconds[2]), finish, "other worker continues after the REST event")
	_near(float(partial.participant_effective_seconds[1]), rested_work, "rested worker's unweighted work is preserved")
	_near(float(partial.participant_effective_seconds[2]), finish, "fresh worker's complete unweighted work is preserved")
	_check(str(partial.participant_paused[1]) == "REST" and str(partial.participant_paused[2]).is_empty() and str(partial.paused).is_empty(), "only the resting person receives REST; completed shared work remains ready")
	_near(float(plan.pools[0].fatigue), 80.0, "rested pool stops at original 80")
	_near(float(plan.pools[1].fatigue), finish * w, "remaining worker is charged exactly its own actual seconds")
	var partial_split := _consume_partitioned_plans([weighted.duplicate(true)], 100.0, 137)
	_near(float(partial_split.jobs.actions.partial_rest.actual_seconds), finish, "partial REST completion is invariant under partition")
	_near(float(partial_split.jobs.actions.partial_rest.effective_seconds), 100.0, "partitioned partial REST preserves one shared completion")
	original = {"fatigue": 60.0, "fatigue_rest": 12.0, "count": 2}
	a = _test_body(0.0, 0.0, true)
	b = _test_body(0.0)
	Fatigue.bind(a, original)
	Fatigue.bind(b, original)
	plan = Fatigue.plan_work_interval([_request("initial_partial_rest", [_participant(1, a, w / 2.0), _participant(2, b, w / 2.0)], 1000.0, "sum")], 100.0)
	_near(float(plan.jobs.actions.initial_partial_rest.participant_seconds[1]), 0.0, "an initial resting latch does not borrow another worker's effort")
	_near(float(plan.jobs.actions.initial_partial_rest.participant_seconds[2]), 100.0, "a different worker in the same pool may still work")
	_near(float(plan.pools[0].fatigue), 60.0 + 100.0 * w / 2.0, "only the active worker contributes to the shared pool")
	_check(bool(a.work_resting) and float(original.fatigue) == 60.0, "weighted and partial REST plans retain original body/pool state")
	for invalid_weight: Variant in [0.0, -1.0, INF, NAN, "2"]:
		var bad_weight := weighted.duplicate(true)
		bad_weight.participants[0].progress_multiplier = invalid_weight
		_check(not bool(Fatigue.plan_work_interval([bad_weight], 100.0).ok), "zero, negative, nonfinite and nonnumeric sum weights are refused")
	# D12: helpers require at least one genuine master continuously working.
	var master_request := _request("masters", [_participant(1, _test_body(79.9), w), _participant(2, _test_body(79.8), w), _participant(3, _test_body(0.0), w)], 1000.0, "sum")
	master_request["required_any_ids"] = [1, 2]
	plan = Fatigue.plan_work_interval([master_request], 100.0)
	_check(bool(plan.ok), "two-original-master shared job is valid")
	if not plan.ok: return
	var masters: Dictionary = plan.jobs.actions.masters
	_near(float(masters.actual_seconds), 72.0, "one resting master does not stop the other; the last master's REST stops the job")
	_near(float(masters.participant_seconds[1]), 36.0, "first master stops at its original 80 boundary")
	_near(float(masters.participant_seconds[2]), 72.0, "second master continues after the first rests")
	_near(float(masters.participant_seconds[3]), 72.0, "helper stops exactly when the last actual master stops")
	_near(float(masters.effective_seconds), Fatigue.work_seconds(79.9, 36.0, w) + Fatigue.work_seconds(79.8, 72.0, w) + 72.0, "only genuinely supervised contributions count")
	_check(str(masters.paused) == "REST" and str(masters.participant_paused[1]) == "REST" and str(masters.participant_paused[2]) == "REST" and str(masters.participant_paused[3]).is_empty(), "master gate pauses the shared job without inventing the helper's fatigue latch")
	_near(float(plan.pools[2].fatigue), 72.0 * w, "unsupervised helper effort is never charged")
	var masters_split := _consume_partitioned_plans([master_request.duplicate(true)], 100.0, 137)
	_near(float(masters_split.jobs.actions.masters.actual_seconds), 72.0, "last-master REST keeps exact timing across partitions")
	_near(float(masters_split.jobs.actions.masters.effective_seconds), float(masters.effective_seconds), "partitioned supervised work has the same productive budget")
	var ungated := master_request.duplicate(true)
	ungated.erase("required_any_ids")
	var ungated_plan := Fatigue.plan_work_interval([ungated], 100.0)
	_near(float(ungated_plan.jobs.actions.masters.participant_seconds[3]), 100.0, "ordinary ungated crew retains independent workers after another rests")
	var master_with_run := master_request.duplicate(true)
	var continuing_pool := {"fatigue": 0.0, "fatigue_rest": 0.0, "count": 2}
	var runner := _test_body(0.0)
	Fatigue.bind(master_with_run.participants[2].body, continuing_pool)
	Fatigue.bind(runner, continuing_pool)
	master_with_run.participants[2].effort_rate = w / 2.0
	var continuing := _request("independent_run", [_participant(4, runner, Fatigue.RUN_RATE / 2.0, false)], 1000.0, "raw")
	plan = Fatigue.plan_work_interval([master_with_run, continuing], 100.0)
	_near(float(plan.jobs.actions.masters.participant_seconds[3]), 72.0, "supervision still stops the helper inside a concurrently active original pool")
	_near(float(plan.jobs.actions.independent_run.actual_seconds), 100.0, "master REST does not stop another original activity")
	_near(float(plan.pools[2].fatigue), 100.0 * Fatigue.RUN_RATE / 2.0 + 72.0 * w / 2.0, "the remaining RUN keeps its exact original pool slope after the helper stops")
	master_request = _request("one_master", [_participant(1, _test_body(79.9), w), _participant(2, _test_body(0.0), w)], rested_work + 36.0, "sum")
	master_request["required_any_ids"] = [1]
	plan = Fatigue.plan_work_interval([master_request], 100.0)
	_near(float(plan.jobs.actions.one_master.actual_seconds), 36.0, "single master completion may coincide with its REST endpoint")
	_check(str(plan.jobs.actions.one_master.paused).is_empty(), "genuine completion at the last-master boundary remains available for original point commit")
	master_request = _request("initial_master_rest", [_participant(1, _test_body(60.0, 12.0, true), w), _participant(2, _test_body(0.0), w), _participant(3, _test_body(0.0), w)], 1000.0, "sum")
	master_request["required_any_ids"] = [1, 2]
	plan = Fatigue.plan_work_interval([master_request], 100.0)
	_near(float(plan.jobs.actions.initial_master_rest.participant_seconds[1]), 0.0, "a resting master lends no fictional work")
	_near(float(plan.jobs.actions.initial_master_rest.participant_seconds[2]), 100.0, "the other actual master keeps the crew legal")
	_near(float(plan.jobs.actions.initial_master_rest.participant_seconds[3]), 100.0, "helper work requires the second actual master")
	for invalid_masters: Variant in [[1, 1], [4], [1.0], "1"]:
		var invalid_master_request := master_request.duplicate(true)
		invalid_master_request.required_any_ids = invalid_masters
		var rejected := Fatigue.plan_work_interval([invalid_master_request], 100.0)
		_check(not bool(rejected.ok) and rejected.jobs.is_empty() and rejected.pools.is_empty(), "nonparticipant, duplicate and noninteger master gates are refused atomically")
	var non_sum_master := _request("wrong_master_kind", [_participant(1, _test_body(0.0), w)], 100.0)
	non_sum_master["required_any_ids"] = [1]
	_check(not bool(Fatigue.plan_work_interval([non_sum_master], 100.0).ok), "a master gate is only legal on an original shared sum job")
	plan = Fatigue.plan_work_interval([_request("constant", [_participant(1, _test_body(40.0, 10.0), 0.0)], 30.0)], 100.0)
	_check(bool(plan.ok), "zero-slope planner work is valid")
	if not plan.ok: return
	_near(float(plan.jobs.actions.constant.actual_seconds), 30.0 * (1.0 + 0.3 / 7.0), "zero-slope planner completion")
	_near(float(plan.pools[0].fatigue), 40.0, "zero slope leaves fatigue value")
	_near(float(plan.pools[0].fatigue_rest), 0.0, "actual zero-slope activity is not idle recovery")
	# Initial REST preserves progress/occupancy and never performs recovery here.
	a = _test_body(60.0, 12.0, true)
	b = _test_body(20.0, 8.0)
	plan = Fatigue.plan_work_interval([_request("rest", [_participant(1, a, w), _participant(2, b, w)], 300.0, "joint")], 300.0)
	_check(bool(plan.ok), "initial REST plan is valid")
	if not plan.ok: return
	_near(float(plan.jobs.actions.rest.actual_seconds), 0.0, "one resting participant stops both efforts")
	_near(float(plan.pools[0].fatigue), 60.0, "planner grants no recovery")
	_near(float(plan.pools[0].fatigue_rest), 12.0, "planner leaves idle rest clock to original owner")
	_near(float(plan.pools[1].effort_seconds), 0.0, "other participant is not charged alone")
	# Recovery to 50 clears only the planner's local work latch. A concurrent
	# completion must not reinterpret resumed work as still resting above 50.
	original = {"fatigue": 50.0, "fatigue_rest": 30.0, "count": 2}
	a = _test_body(0.0, 0.0, true)
	b = _test_body(0.0)
	Fatigue.bind(a, original)
	Fatigue.bind(b, original)
	requests = [_request("resumed", [_participant(1, a, w / 2.0)], 120.0, "single", 0.5), _request("early", [_participant(2, b, w / 2.0)], 1.0, "raw")]
	plan = Fatigue.plan_work_interval(requests, 100.0)
	_check(bool(plan.ok), "recovered work with an internal completion event is valid")
	if not plan.ok: return
	_near(float(plan.jobs.actions.resumed.actual_seconds), 100.0, "recovered work does not rest again above 50")
	_check(str(plan.jobs.actions.resumed.paused).is_empty(), "resumed work waits for the next original 80 boundary")
	_near(float(plan.pools[0].fatigue), 50.0 + 101.0 * w / 2.0, "resumed work keeps all original effort after other completion")
	_check(bool(a.work_resting) and float(original.fatigue) == 50.0, "planner never clears the original body's latch or writes its pool")
	var request := _request("threat", [_participant(1, _test_body(20.0), w)], 120.0)
	request.paused = "THREAT"
	plan = Fatigue.plan_work_interval([request], 100.0)
	_check(bool(plan.ok) and str(plan.jobs.actions.threat.paused) == "THREAT" and float(plan.jobs.actions.threat.actual_seconds) == 0.0, "provider pause is retained without deciding threat")
	request = _request("at80", [_participant(1, _test_body(79.9), w)], 29.652291888785584)
	plan = Fatigue.plan_work_interval([request], 100.0)
	_check(bool(plan.ok), "completion at 80 plan is valid")
	if not plan.ok: return
	_near(float(plan.jobs.actions.at80.actual_seconds), 36.0, "completion reaches exact rest endpoint")
	_check(str(plan.jobs.actions.at80.paused).is_empty(), "completed pending work is not turned into REST")
	# Reject duplicate activity and malformed inputs without returning partial work.
	request = _request("first", [_participant(1, _test_body(20.0), w)], 120.0)
	var duplicate := request.duplicate(true)
	duplicate.key = "other"
	plan = Fatigue.plan_work_interval([request, duplicate], 100.0)
	_check(not bool(plan.ok) and plan.jobs.is_empty() and plan.pools.is_empty(), "same original person across requests is rejected")
	a = _test_body(20.0)
	_check(not bool(Fatigue.plan_work_interval([_request("alias", [_participant(1, a, w), _participant(2, a, w)], 300.0, "joint")], 100.0).ok), "same original body under two IDs is rejected")
	for invalid: float in [-1.0, INF, NAN]:
		_check(not bool(Fatigue.plan_work_interval([request], invalid).ok), "invalid planner interval")
		var broken := request.duplicate(true)
		broken.remaining = invalid
		_check(not bool(Fatigue.plan_work_interval([broken], 100.0).ok), "invalid remaining work")
		broken = request.duplicate(true)
		broken.max_game_seconds = invalid
		_check(not bool(Fatigue.plan_work_interval([broken], 100.0).ok), "invalid work window")
		broken = request.duplicate(true)
		broken.participants[0].effort_rate = invalid
		_check(not bool(Fatigue.plan_work_interval([broken], 100.0).ok), "invalid participant slope")
	for field: String in ["productive_kind", "provider", "key", "paused", "progress_multiplier"]:
		var broken := request.duplicate(true)
		broken[field] = 0.25
		_check(not bool(Fatigue.plan_work_interval([broken], 100.0).ok), "invalid planner field " + field)
	var broken := request.duplicate(true)
	broken.participants[0].body.fatigue = 101.0
	_check(not bool(Fatigue.plan_work_interval([broken], 100.0).ok), "invalid original body fatigue")
	broken = request.duplicate(true)
	broken.productive_kind = "joint"
	_check(not bool(Fatigue.plan_work_interval([broken], 100.0).ok), "joint work requires two original people")
	_near(float(Fatigue.plan_work_interval([request], 0.0).jobs.actions.first.actual_seconds), 0.0, "zero interval creates no effort")
	_check(bool(Fatigue.plan_work_interval([], 100.0).ok), "empty activity interval is valid")

func _consume_partitioned_plans(requests: Array, seconds: float, pieces: int) -> Dictionary:
	# Only this fixture acts as a consumer; production remains on original owners.
	var jobs := {}
	var elapsed := 0.0
	for index: int in pieces:
		var end := seconds * float(index + 1) / float(pieces)
		var part := Fatigue.plan_work_interval(requests, end - elapsed)
		if not part.ok: return part
		for request: Dictionary in requests:
			var record: Dictionary = part.jobs[request.provider][request.key]
			if not jobs.has(request.provider): jobs[request.provider] = {}
			if not jobs[request.provider].has(request.key): jobs[request.provider][request.key] = {"actual_seconds": 0.0, "effective_seconds": 0.0}
			var combined: Dictionary = jobs[request.provider][request.key]
			combined.actual_seconds = float(combined.actual_seconds) + float(record.actual_seconds)
			combined.effective_seconds = float(combined.effective_seconds) + float(record.effective_seconds)
			request.remaining = maxf(0.0, float(request.remaining) - float(record.effective_seconds))
			request.max_game_seconds = maxf(0.0, float(request.max_game_seconds) - (end - elapsed))
			request.paused = str(record.paused)
		for group: Dictionary in part.pools:
			if group.original_pool.is_empty():
				group.body.fatigue = float(group.fatigue)
				group.body.fatigue_rest = float(group.fatigue_rest)
			else:
				group.original_pool.fatigue = float(group.fatigue)
				group.original_pool.fatigue_rest = float(group.fatigue_rest)
		elapsed = end
	return {"ok": true, "jobs": jobs}
