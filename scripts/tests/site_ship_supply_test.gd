extends SceneTree
## Original Sustain history with two ship stocks and a separate shore stock.
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const HOUR := 3600.0

func _initialize() -> void:
	call_deferred("_run")

func _near(actual: float, expected: float, label: String = "") -> void:
	assert(absf(actual - expected) < 0.000001, "%s: %.12f != %.12f" % [label, actual, expected])

func _people() -> Dictionary:
	return {1: {"hp": 100.0}, 2: {"hp": 100.0}, 3: {"hp": 100.0}}

func _state(people: Dictionary, ids: Array = [1, 2, 3], at: float = 0.0, version: int = 2) -> Dictionary:
	var state := Sustain.create(at, version)
	assert(Sustain.add_members(state, people, ids).ok)
	return state

func _stocks() -> Dictionary:
	return {"vehicle:1": {"inventory": {"grain": 1, "seeds": 7}, "open_rations": 0.0},
		"vehicle:2": {"inventory": {}, "open_rations": 0.0},
		"shore:10": {"inventory": {}, "open_rations": 0.125}}

func _context() -> Dictionary:
	return {"food_locations": {1: "vehicle:1", 2: "vehicle:2", 3: "shore:10"}}

func _history(state: Dictionary, id: int) -> Dictionary:
	for cohort: Dictionary in state.cohorts:
		if id in cohort.ids:
			return cohort
	assert(false, "Original feeding ID missing: %d" % id)
	return {}

func _compare(first: Dictionary, second: Dictionary) -> void:
	for field: String in ["at", "morale", "regroup_seconds"]:
		_near(float(first[field]), float(second[field]), field)
	assert(first.routed == second.routed)
	for id: int in [1, 2, 3]:
		var a := _history(first, id)
		var b := _history(second, id)
		for field: String in ["hunger", "coverage", "meal_until"]:
			_near(float(a[field]), float(b[field]), field)
		assert(a.bonus_paid == b.bonus_paid and a.bonus_pending == b.bonus_pending)

func _separate_meals() -> void:
	var people := _people()
	var state := _state(people)
	var stocks := _stocks()
	var before := Sustain.rations(state, stocks)
	var outcome := Sustain.advance_to(state, people, stocks, 6.0 * HOUR, _context())
	assert(outcome.ok and not outcome.fully_fed)
	_near(float(outcome.consumed_rations), 0.375)
	_near(Sustain.rations(state, stocks), before - 0.375, "single physical debit")
	_near(float(_history(state, 1).hunger), 0.0)
	_near(float(_history(state, 2).hunger), 6.0, "other ship cannot consume remote stock")
	_near(float(_history(state, 3).hunger), 3.0, "shore retains its own partial meal")
	_near(float(state.at), 6.0 * HOUR, "one team clock")
	_near(float(state.morale), 94.0, "one living-weighted team loss")
	assert(stocks["vehicle:1"].inventory.seeds == 7 and not state.has("open_rations"))
	# Paid coverage follows the person. Only missing future coverage is paid again.
	state = _state(people, [1, 2])
	stocks = _stocks()
	var context := {"food_locations": {1: "vehicle:1", 2: "vehicle:2"}}
	assert(Sustain.advance_to(state, people, stocks, 3.0 * HOUR, context).ok)
	context.food_locations[2] = "vehicle:1"
	var supplied := Sustain.resupply(state, people, stocks, false, Callable(), {}, context)
	assert(supplied.ok)
	_near(float(supplied.consumed_rations), 0.125)
	assert(Sustain.advance_to(state, people, stocks, 6.0 * HOUR, context).ok)
	_near(float(_history(state, 2).hunger), 1.5)
	_near(float(stocks["vehicle:1"].open_rations), 0.625)

func _membership_history() -> void:
	var people := _people()
	var team := _state(people)
	var stocks := _stocks()
	assert(Sustain.advance_to(team, people, stocks, 3.0 * HOUR, _context()).ok)
	var personal := Sustain.create(float(team.at))
	personal.open_rations = 0.2
	var history := _history(team, 2).duplicate(true)
	var stock_before := var_to_bytes(stocks)
	assert(Sustain.move_members(team, personal, people, [2]).ok)
	assert(_history(personal, 2) == history and Sustain.validate_owners([team, personal], people))
	assert(var_to_bytes(stocks) == stock_before)
	_near(float(personal.open_rations), 0.2, "membership does not move stock")
	assert(Sustain.move_members(personal, team, people, [2]).ok)
	assert(_history(team, 2) == history and Sustain.validate_owners([team, personal], people))
	assert(not Sustain.validate_owners([team, team.duplicate(true)], people))
	assert(var_to_bytes(stocks) == stock_before and personal.open_rations == 0.2)

func _atomic_rejection() -> void:
	for kind: String in ["missing_map", "missing_id", "unknown_stock", "unknown_id", "bad_key", "bad_later_stock", "fractional_stock", "aliased_stock", "aggregate_open", "backward", "bad_later_hp"]:
		var people := _people()
		var state := _state(people)
		var stocks := _stocks()
		var context := _context()
		var at := HOUR
		match kind:
			"missing_map": context.erase("food_locations")
			"missing_id": context.food_locations.erase(3)
			"unknown_stock": context.food_locations[3] = "shore:99"
			"unknown_id": context.food_locations[99] = "shore:10"
			"bad_key": stocks["shore:010"] = {"inventory": {}, "open_rations": 0.0}
			"bad_later_stock": stocks["shore:10"].open_rations = -0.1
			"fractional_stock": stocks["shore:10"].inventory.grain = 0.5
			"aliased_stock": stocks["vehicle:2"].inventory = stocks["vehicle:1"].inventory
			"aggregate_open": state.open_rations = 1.0
			"backward": at = -1.0
			"bad_later_hp": people[3].hp = -1.0
		var before := var_to_bytes([state, stocks, people, context])
		assert(not Sustain.advance_to(state, people, stocks, at, context).ok, kind)
		assert(var_to_bytes([state, stocks, people, context]) == before, kind + " advance changes nothing")
		if kind != "backward":
			assert(not Sustain.resupply(state, people, stocks, false, Callable(), {}, context).ok, kind)
			assert(var_to_bytes([state, stocks, people, context]) == before, kind + " resupply changes nothing")
	# Explicitly having no reachable stock is starvation, not an invalid packet.
	var people := _people()
	var state := _state(people)
	var stocks := _stocks()
	var context := {"food_locations": {1: "", 2: "", 3: ""}}
	var before := var_to_bytes(stocks)
	assert(Sustain.advance_to(state, people, stocks, HOUR, context).ok)
	_near(float(_history(state, 1).hunger), 1.0)
	assert(var_to_bytes(stocks) == before)
	before = var_to_bytes([state, stocks, people])
	context.paused = true
	assert(Sustain.advance_to(state, people, stocks, 8.0 * HOUR, context).ok)
	assert(var_to_bytes([state, stocks, people]) == before)

func _shared_regroup_and_partition() -> void:
	var people := _people()
	var state := _state(people)
	var stocks := _stocks()
	for location: Dictionary in stocks.values():
		location.inventory.grain = 1
	state.morale = 50.0
	state.routed = true
	var context := _context()
	context.safe = true
	context.stopped = true
	var outcome := Sustain.advance_to(state, people, stocks, 1800.0, context)
	assert(outcome.ok and outcome.regrouped and not state.routed)
	_near(float(state.regroup_seconds), 1800.0)
	_near(float(state.morale), 52.5, "regroup does not advance once per location")
	# Compaction may join identical histories. The next meal splits them again.
	assert(state.cohorts.size() == 1)
	stocks["vehicle:2"].inventory.grain = 0
	stocks["vehicle:2"].open_rations = 0.0
	assert(Sustain.advance_to(state, people, stocks, 12.0 * HOUR, _context()).ok)
	_near(float(_history(state, 2).hunger), 6.0)
	_near(float(_history(state, 1).hunger), 0.0)
	# Equal meals retain v1's numerical behavior for a single reachable stock.
	var legacy := _state(people, [1, 2, 3], 0.0, 1)
	var legacy_stock := {"grain": 1}
	var modern := _state(people)
	var modern_stock := {"shore:10": {"inventory": {"grain": 1}, "open_rations": 0.0}}
	var same_place := {"food_locations": {1: "shore:10", 2: "shore:10", 3: "shore:10"}}
	assert(Sustain.advance_to(legacy, people, legacy_stock, 36.0 * HOUR).ok)
	assert(Sustain.advance_to(modern, people, modern_stock, 36.0 * HOUR, same_place).ok)
	_compare(legacy, modern)
	_near(Sustain.rations(legacy, legacy_stock), Sustain.rations(modern, modern_stock))
	var a_people := _people()
	a_people[2].hp = 0.25
	var b_people := a_people.duplicate(true)
	var a := _state(a_people)
	var b := a.duplicate(true)
	var a_stock := _stocks()
	var b_stock := a_stock.duplicate(true)
	assert(Sustain.advance_to(a, a_people, a_stock, 72.0 * HOUR, _context()).ok)
	for step: int in range(1, 601):
		assert(Sustain.advance_to(b, b_people, b_stock, step * 0.12 * HOUR, _context()).ok)
	_compare(a, b)
	for id: int in [1, 2, 3]:
		_near(float(a_people[id].hp), float(b_people[id].hp), "original famine damage")
	_near(float(a_people[2].hp), 0.0)
	for key: String in a_stock:
		assert(a_stock[key].inventory == b_stock[key].inventory)
		_near(float(a_stock[key].open_rations), float(b_stock[key].open_rations))

func _run() -> void:
	_separate_meals()
	_membership_history()
	_atomic_rejection()
	_shared_regroup_and_partition()
	print("SITE SHIP SUPPLY PASS: two ships/shore ration conservation, location history splits, v1/v2 membership, atomic invalid rejection, one morale/regroup clock, v1 parity and famine partition")
	quit(0)
