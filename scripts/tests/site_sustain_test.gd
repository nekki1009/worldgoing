extends SceneTree

const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const HOUR := 3600.0

func _initialize() -> void:
	call_deferred("_run")

func _near(actual: float, expected: float, label: String = "") -> void:
	assert(absf(actual - expected) < 0.000001, "%s: %.12f != %.12f" % [label, actual, expected])

func _people(count: int) -> Dictionary:
	var result := {}
	for id: int in range(1, count + 1):
		result[id] = {"hp": 100.0, "fatigue": 0.0, "fatigue_rest": 0.0,
			"work_resting": false, "present": true, "captive": false, "ko": 0.0}
	return result

func _state(people: Dictionary, ids: Array, at_seconds: float = 0.0) -> Dictionary:
	var state := Sustain.create(at_seconds)
	assert(Sustain.add_members(state, people, ids).ok)
	return state

func _compare(first: Dictionary, second: Dictionary) -> void:
	for field: String in ["at", "open_rations", "morale", "regroup_seconds"]:
		_near(float(first[field]), float(second[field]), field)
	assert(first.routed == second.routed and first.cohorts.size() == second.cohorts.size())
	for i: int in first.cohorts.size():
		var a: Dictionary = first.cohorts[i]
		var b: Dictionary = second.cohorts[i]
		assert(a.ids == b.ids and a.bonus_paid == b.bonus_paid and a.bonus_pending == b.bonus_pending)
		for field: String in ["hunger", "coverage", "meal_until"]:
			_near(float(a[field]), float(b[field]), field)

func _run() -> void:
	# Combining real opened meals cannot mint grain or reject a valid 1.5 pool.
	var opened := Sustain.create()
	opened.open_rations = 0.75 + 0.75
	assert(Sustain.validate(opened, {}))
	var no_grain := {}
	_near(Sustain._eat(opened, no_grain, 1.25), 1.25)
	_near(float(opened.open_rations), 0.25)
	assert(no_grain.is_empty())
	for invalid: float in [-0.001, INF, NAN, 1000000.001]:
		opened.open_rations = invalid
		assert(not Sustain.validate(opened, {}))
	opened.open_rations = 1000000.0
	assert(Sustain.validate(opened, {}))
	# One opened integer unit funds four quarter-meals, in explicit stock only.
	var people := _people(4)
	people[2].ko = 30.0
	people[3].captive = true
	var state := _state(people, [1, 2, 3, 4])
	var stock := {"fish": 1, "meat": 2, "wild_food": 2, "grain": 2, "seeds": 90, "fodder": 20}
	var served := Sustain.resupply(state, people, stock)
	_near(float(served.consumed_rations), 1.0)
	assert(stock.fish == 0 and stock.meat == 2 and stock.seeds == 90 and stock.fodder == 20)
	assert(Sustain.resupply(state, people, stock).consumed_rations == 0.0)
	_near(float(state.cohorts[0].coverage), 1.0)
	assert(Sustain.advance_to(state, people, stock, 6.0 * HOUR).ok)
	_near(float(state.cohorts[0].hunger), 0)
	# Partial inventory is shared by every original person, including the KO/captive.
	state = _state(people, [1, 2, 3, 4])
	state.open_rations = 0.5
	stock = {"seeds": 90}
	_near(float(Sustain.resupply(state, people, stock).consumed_rations), 0.5)
	_near(float(state.cohorts[0].coverage), 0.5)
	Sustain.advance_to(state, people, stock, 6.0 * HOUR)
	_near(float(state.cohorts[0].hunger), 3.0)
	_near(float(state.morale), 94.0)
	assert(stock.seeds == 90)
	# Partial first-day join and split preserve credit/history, not shared cargo.
	people = _people(3)
	state = _state(people, [1, 2])
	stock = {"grain": 1}
	Sustain.advance_to(state, people, stock, 3.0 * HOUR)
	_near(float(state.open_rations), 0.5)
	assert(Sustain.add_members(state, people, [3]).ok)
	_near(float(Sustain.resupply(state, people, stock).consumed_rations), 0.125)
	var split := Sustain.create(3.0 * HOUR)
	assert(Sustain.move_members(state, split, people, [1]).ok)
	_near(float(split.cohorts[0].coverage), 1.0)
	_near(float(split.open_rations), 0.0)
	_near(float(state.open_rations), 0.375)
	assert(Sustain.resupply(split, people, {}).consumed_rations == 0.0)
	assert(not Sustain.move_members(state, split, people, [3, 3]).ok)
	assert(Sustain.move_members(split, state, people, [1]).ok)
	_near(float(Sustain.rations(state, stock)), 0.375)
	assert(Sustain.validate_owners([state, split], people))
	assert(not Sustain.validate_owners([state, state.duplicate(true)], people))
	# Hungry veterans and fresh people never average their hunger history.
	state = _state(people, [1])
	Sustain.advance_to(state, people, {}, 48.0 * HOUR)
	_near(float(people[1].hp), 100.0, "48 h grace")
	assert(Sustain.add_members(state, people, [2, 3]).ok)
	assert(state.cohorts.size() == 2)
	Sustain.advance_to(state, people, {}, 49.0 * HOUR)
	_near(float(people[1].hp), 99.0)
	_near(float(people[2].hp), 100.0)
	_near(float(state.cohorts[0].hunger), 49.0)
	_near(float(state.cohorts[1].hunger), 1.0)
	stock = {"grain": 2}
	Sustain.resupply(state, people, stock)
	var before := float(people[1].hp)
	Sustain.advance_to(state, people, stock, 50.0 * HOUR)
	_near(float(people[1].hp), before, "full resupply stops damage now, without healing")
	_near(float(state.cohorts[0].hunger), 48.5)
	# 72 hours in one call vs 600 intervals includes the actual death boundary.
	var a_people := _people(2)
	a_people[1].hp = 0.25
	var a := _state(a_people, [1, 2])
	var b_people := a_people.duplicate(true)
	var b := a.duplicate(true)
	var a_stock := {"grain": 1}
	var b_stock := a_stock.duplicate()
	Sustain.advance_to(a, a_people, a_stock, 72.0 * HOUR)
	for step: int in range(1, 601):
		assert(Sustain.advance_to(b, b_people, b_stock, step * 0.12 * HOUR).ok)
	_compare(a, b)
	_near(float(a_people[1].hp), 0)
	_near(float(a_people[2].hp), float(b_people[2].hp))
	assert(a_stock == b_stock)
	var frozen := b.duplicate(true)
	Sustain.advance_to(b, b_people, b_stock, 100.0 * HOUR, {"paused": true})
	assert(b == frozen)
	assert(not Sustain.advance_to(b, b_people, b_stock, 1.0).ok)
	var malformed := b.duplicate(true)
	malformed.cohorts[0].ids.append(malformed.cohorts[0].ids[0])
	assert(not Sustain.validate(malformed, b_people))
	assert(not Sustain.resupply(b, b_people, {"grain": -1}).ok)
	assert(not Sustain.resupply(b, b_people, {"grain": 0.5}).ok)
	var restored: Dictionary = JSON.parse_string(JSON.stringify(b))
	assert(Sustain.validate(restored, b_people), "Saved JSON integer IDs normalize through the validation boundary")
	assert(Sustain.advance_to(restored, b_people, b_stock, float(b.at)).ok)
	# Combat event sequence and commander latch prevent repeated losses.
	people = _people(2)
	state = _state(people, [1, 2])
	var event := Sustain.combat_event(state, 1, 2, 0, 1, false, 100.0)
	_near(float(event.loss), 17.5)
	assert(not Sustain.combat_event(state, 1, 2, 0, 1, false, 100.0).applied)
	_near(float(Sustain.combat_event(state, 2, 2, 0, 0, false, 100.0).loss), 0.0)
	Sustain.combat_event(state, 3, 2, 2, 0, true, 0.0)
	Sustain.combat_event(state, 4, 2, 0, 2, false, 0.0)
	assert(state.routed)
	state.morale = 50.0
	stock = {"grain": 10}
	Sustain.advance_to(state, people, stock, 1799.0, {"safe": true, "stopped": true})
	assert(state.routed)
	Sustain.advance_to(state, people, stock, 1800.0, {"safe": false, "stopped": true})
	_near(float(state.regroup_seconds), 0)
	var regroup := Sustain.advance_to(state, people, stock, 3600.0, {"safe": true, "stopped": true})
	assert(regroup.regrouped and not state.routed)
	# One actual first fully fed period reward, no repeat on a supply button.
	state = _state(people, [1, 2])
	Sustain.advance_to(state, people, {}, 6.0 * HOUR)
	stock = {"grain": 10}
	var morale := float(state.morale)
	Sustain.resupply(state, people, stock)
	Sustain.resupply(state, people, stock)
	_near(float(state.morale), morale)
	Sustain.advance_to(state, people, stock, 12.0 * HOUR)
	_near(float(state.morale), morale + 2.0)
	Sustain.advance_to(state, people, stock, 18.0 * HOUR)
	_near(float(state.morale), morale + 2.0)
	# Exact original fatigue integration and 80/50 cycles, no per-person T state.
	var conditions := {"ordered": true, "commander": true, "safe": true, "stopped": true, "fed": true, "coach": 100.0}
	a_people = _people(3)
	a_people[1].fatigue = 79.9
	a_people[2].ko = 30.0
	a_people[3].captive = true
	b_people = a_people.duplicate(true)
	var trained := Sustain.train(0, a_people, [1, 2, 3], 8.0 * HOUR, conditions)
	assert(trained.ok and trained.handled_ids == [1])
	var training := 0.0
	var effort := 0.0
	for step: int in 800:
		var part := Sustain.train(training, b_people, [1, 2, 3], 0.01 * HOUR, conditions)
		assert(part.ok)
		training = float(part.training)
		effort += float(part.effort_seconds[1])
	_near(float(trained.training), training, "training interval partition")
	_near(float(trained.effort_seconds[1]), effort)
	_near(float(a_people[1].fatigue), float(b_people[1].fatigue))
	assert(a_people[1].work_resting == b_people[1].work_resting)
	assert(not Sustain.train(0, a_people, [1, 1], 1, conditions).ok)
	assert(not Sustain.train(0, {1: 99}, [1], 1, conditions).ok)
	var untouched := a_people.duplicate(true)
	conditions.paused = true
	_near(float(Sustain.train(0, a_people, [1], HOUR, conditions).training), 0)
	assert(a_people == untouched)
	conditions.paused = false
	_near(float(Sustain.train(1001, a_people, [1], HOUR, conditions).training), 1001)
	assert(a_people != untouched, "Existing order still does work; only T growth is capped")
	a_people = _people(1)
	b_people = a_people.duplicate(true)
	trained = Sustain.train(999.9, a_people, [1], HOUR, conditions)
	training = 999.9
	for step: int in 100:
		training = float(Sustain.train(training, b_people, [1], HOUR / 100.0, conditions).training)
	_near(float(trained.training), 1000.0)
	_near(training, 1000.0)
	_near(float(a_people[1].fatigue), float(b_people[1].fatigue), "T cap does not change actual training effort by frame size")
	people = _people(1)
	conditions.controlled_person_id = 1
	people[1].fatigue = 100.0
	trained = Sustain.train(0, people, [1], HOUR, conditions)
	_near(float(trained.training), 1.25 / 1.3)
	assert(not people[1].work_resting)
	people = _people(2)
	people[1].fatigue = 79.999
	people[2].fatigue = 79.999
	trained = Sustain.train(0, people, [1, 2], 20.0, conditions)
	_near(float(trained.effort_seconds[1]), 20.0)
	assert(float(people[1].fatigue) > 80.0 and not people[1].work_resting)
	assert(float(trained.effort_seconds[2]) < 1.0 and people[2].work_resting)
	assert(not people[1].has("is_player") and not people[2].has("is_player"), "Control identity is context, never a persisted body flag")
	conditions.controlled_person_id = 2
	people[1].is_player = true # Stale data cannot retain player exemptions after succession.
	trained = Sustain.train(0, people, [1, 2], 20.0, conditions)
	_near(float(trained.effort_seconds[2]), 20.0)
	_near(float(trained.effort_seconds[1]), 0.0)
	assert(people[1].work_resting and not people[2].work_resting)
	assert(not Sustain.train(0, people, [1], 1, {"controlled_person_id": -1}).ok)
	_near(Sustain.weighted(100, 10, 0, 10), 50)
	print("SITE SUSTAIN PASS: ration conservation, equal meals, time-credit transfer, hunger history/grace/death/resupply, partition/pause, morale/rout/reward, original fatigue training 80/50 and validation")
	quit(0)
