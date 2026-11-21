extends SceneTree
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const Reference = preload("res://scripts/tests/helpers/site_sustain_batch_reference.gd")
var checks := 0
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String, details: Variant = null) -> bool:
	checks += 1
	print("SUSTAIN_BATCH ", "OK " if ok else "FAIL ", checks, ": ", label, " ", details if details != null else "")
	if not ok: failed = true
	return ok

func _difference(a: Variant, b: Variant, path: String = "state") -> String:
	if (a is int or a is float) and (b is int or b is float):
		return "" if absf(float(a) - float(b)) <= 0.000000001 else "%s %s != %s" % [path, a, b]
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return path + " dictionary size"
		for key: Variant in a:
			if not b.has(key): return path + " missing " + str(key)
			var mismatch := _difference(a[key], b[key], path + "." + str(key))
			if not mismatch.is_empty(): return mismatch
		return ""
	if a is Array and b is Array:
		if a.size() != b.size(): return path + " array size"
		for index in range(a.size()):
			var mismatch := _difference(a[index], b[index], path + "[" + str(index) + "]")
			if not mismatch.is_empty(): return mismatch
		return ""
	return "" if a == b else "%s %s != %s" % [path, a, b]

func _members(hps: Array) -> Dictionary:
	var result := {}
	for index in range(hps.size()):
		result[index + 1] = {"person_id": index + 1, "hp": float(hps[index]), "ko": 0.0, "captive": false, "present": true}
	return result

func _state(members: Dictionary, at: float = 0.0, hunger: float = 0.0) -> Dictionary:
	var state: Dictionary = Sustain.create(at)
	if not members.is_empty():
		assert(Sustain.add_members(state, members, members.keys()).ok)
		state.cohorts[0].hunger = hunger
	return state

func _legacy_result(result: Dictionary) -> Dictionary:
	# The retained slow oracle predates only this added observation field.
	var prior_fields := result.duplicate(true)
	prior_fields.erase("fully_fed")
	return prior_fields

func _pair(label: String, state: Dictionary, members: Dictionary, stock: Dictionary, times: Array, context: Dictionary = {}, hot: bool = false) -> void:
	var actual := {"state": state.duplicate(true), "members": members.duplicate(true), "stock": stock.duplicate(true), "pending": {}}
	var expected := actual.duplicate(true)
	var current_context: Dictionary = context.duplicate(true)
	var old_context: Dictionary = context.duplicate(true)
	var current_reads := [0]
	var old_reads := [0]
	if hot:
		current_context.hot_read = func(id: int, field: StringName) -> Variant:
			current_reads[0] += 1
			return actual.members[id][field]
		old_context.hot_read = func(id: int, field: StringName) -> Variant:
			old_reads[0] += 1
			return expected.members[id][field]
		current_context.pending_hp = actual.pending
		old_context.pending_hp = expected.pending
	for time: float in times:
		var result: Dictionary = Sustain.advance_to(actual.state, actual.members, actual.stock, time, current_context)
		var prior: Dictionary = Reference.advance_to(expected.state, expected.members, expected.stock, time, old_context)
		var mismatch := _difference({"values": actual, "result": _legacy_result(result)}, {"values": expected, "result": prior})
		_check(mismatch.is_empty(), label + " through " + str(time) + " seconds", mismatch)
	if hot: _check(current_reads[0] < old_reads[0], label + " reduces native HP reads without a persistent cache", {"before": old_reads[0], "after": current_reads[0]})

func _resupply_cases() -> void:
	var members := _members([10.0, 2.0, 0.0])
	for due_only in [false, true]:
		for hot in [false, true]:
			var state := _state(members, 1800.0, 7.0)
			state.cohorts[0].coverage = 0.25
			state.cohorts[0].meal_until = 21600.0
			state.open_rations = 0.1
			var prior: Dictionary = state.duplicate(true)
			var stock := {"fish": 1, "grain": 2}
			var old_stock: Dictionary = stock.duplicate(true)
			var pending := {2: 0.0} if hot else {}
			var read := func(id: int, field: StringName) -> Variant: return members[id][field]
			var result: Dictionary = Sustain.resupply(state, members, stock, due_only, read if hot else Callable(), pending)
			var old_result: Dictionary = Reference.resupply(prior, members, old_stock, due_only, read if hot else Callable(), pending)
			var mismatch := _difference([state, stock, result], [prior, old_stock, old_result])
			_check(mismatch.is_empty(), "explicit resupply due_only=%s hot=%s" % [due_only, hot], mismatch)

func _membership_cases() -> void:
	var members := _members([25.0, 10.0, 1.0, 0.125])
	var actual := {"a": Sustain.create(), "b": Sustain.create(), "members": members.duplicate(true), "stock_a": {}, "stock_b": {"grain": 1}}
	Sustain.add_members(actual.a, actual.members, [1, 2])
	Sustain.add_members(actual.b, actual.members, [3])
	actual.a.cohorts[0].hunger = 47.0
	var prior: Dictionary = actual.duplicate(true)
	for time: float in [3600.0, 7200.0, 21600.0, 43200.0]:
		for key: String in ["a", "b"]:
			var outcome: Dictionary = Sustain.advance_to(actual[key], actual.members, actual["stock_" + key], time)
			var old_outcome: Dictionary = Reference.advance_to(prior[key], prior.members, prior["stock_" + key], time)
			var mismatch := _difference([actual, _legacy_result(outcome)], [prior, old_outcome])
			_check(mismatch.is_empty(), "membership history " + key + " at " + str(time), mismatch)
		if time == 3600.0:
			var moved: Dictionary = Sustain.move_members(actual.a, actual.b, actual.members, [2])
			var old_moved: Dictionary = Sustain.move_members(prior.a, prior.b, prior.members, [2])
			_check(moved.ok and old_moved.ok and _difference(actual, prior).is_empty(), "membership transfer retains separate meal histories")
		if time == 7200.0:
			Sustain.add_members(actual.a, actual.members, [4])
			Sustain.add_members(prior.a, prior.members, [4])
			actual.members[1].hp = 0.0
			prior.members[1].hp = 0.0
			_check(_difference(actual, prior).is_empty(), "new member and external death are sampled afresh next call")

func _invalid_cases() -> void:
	for kind: String in ["duplicate", "missing", "negative_hp", "bad_stock", "backwards"]:
		var members := _members([10.0, 20.0])
		var state := _state(members, 60.0)
		var stock := {"grain": 1}
		if kind == "duplicate": state.cohorts[0].ids.append(1)
		if kind == "missing": members.erase(2)
		if kind == "negative_hp": members[1].hp = -1.0
		if kind == "bad_stock": stock.grain = -1
		var before := [state.duplicate(true), members.duplicate(true), stock.duplicate(true)]
		if kind != "backwards":
			var supplied: Dictionary = Sustain.resupply(state, members, stock)
			_check(not supplied.ok, "public resupply rejects " + kind)
		var result: Dictionary = Sustain.advance_to(state, members, stock, 0.0 if kind == "backwards" else 120.0)
		_check(not result.ok and _difference(before, [state, members, stock]).is_empty(), "public advance rejects " + kind + " without mutation")

func _fed_case(label: String, state: Dictionary, members: Dictionary, stock: Dictionary, at: float, expected_fed: bool, context: Dictionary = {}) -> void:
	var prior_state := state.duplicate(true)
	var prior_members := members.duplicate(true)
	var prior_stock := stock.duplicate(true)
	var result := Sustain.advance_to(state, members, stock, at, context)
	var prior := Reference.advance_to(prior_state, prior_members, prior_stock, at, context)
	var mismatch := _difference([state, members, stock, _legacy_result(result)], [prior_state, prior_members, prior_stock, prior])
	_check(result.ok and bool(result.fully_fed) == expected_fed and mismatch.is_empty(), label,
		{"fully_fed": result.get("fully_fed"), "expected": expected_fed, "difference": mismatch})

func _fully_fed_cases() -> void:
	var members := _members([10.0, 0.0])
	_fed_case("due meal feeds the living cohort inside advance_to", _state(members), members.duplicate(true), {"grain": 1}, 600.0, true)
	_fed_case("zero food remains unfed after internal resupply", _state(members), members.duplicate(true), {}, 600.0, false)
	_fed_case("an advanced empty owner is not fully fed", Sustain.create(), {}, {}, 600.0, false)
	var dead := _members([0.0])
	_fed_case("an advanced all-dead owner is not fully fed", _state(dead), dead, {"grain": 1}, 600.0, false)
	var boundary := _state(members, 21000.0)
	boundary.cohorts[0].coverage = 1.0
	boundary.cohorts[0].meal_until = 21600.0
	_fed_case("AND includes shortage after crossing a meal boundary", boundary.duplicate(true), members.duplicate(true), {}, 22200.0, false)
	_fed_case("meal-boundary renewal stays fully fed when stock suffices", boundary, members.duplicate(true), {"grain": 1}, 22200.0, true)
	var mixed := _members([0.125, 10.0])
	var cohorts := Sustain.create()
	Sustain.add_members(cohorts, mixed, [1])
	Sustain.add_members(cohorts, mixed, [2])
	cohorts.cohorts[0].hunger = 48.0
	cohorts.cohorts[1].coverage = 1.0
	for cohort: Dictionary in cohorts.cohorts: cohort.meal_until = 21600.0
	_fed_case("an unfed cohort dying mid-call cannot erase an earlier shortage", cohorts.duplicate(true), mixed.duplicate(true), {}, 900.0, false)
	mixed[1].hp = 0.0
	_fed_case("dead unfed cohort does not block living fed cohort", cohorts, mixed, {}, 900.0, true)
	_fed_case("paused call advances no segment and returns neutral AND", _state(members), members.duplicate(true), {}, 600.0, true, {"paused": true})
	_fed_case("zero interval advances no segment and returns neutral AND", _state(members), members.duplicate(true), {}, 0.0, true)

func _run() -> void:
	_pair("empty", Sustain.create(), {}, {}, [120.0, 43200.0])
	var members := _members([30.0, 20.0, 1.0, 0.0])
	_pair("zero food", _state(members), members, {}, [3600.0, 28800.0, 172800.0])
	var fed := _state(members, 0.0, 12.0)
	fed.morale = 40.0
	fed.routed = true
	_pair("full food, bonus and regroup", fed, members, {"fish": 2, "grain": 10}, [1800.0, 21600.0, 43200.0], {"safe": true, "stopped": true})
	var cross := _state(members, 20700.0, 47.75)
	cross.cohorts[0].coverage = 0.25
	cross.cohorts[0].meal_until = 21600.0
	cross.open_rations = 0.125
	_pair("partial coverage across meals", cross, members, {"grain": 1}, [21600.0, 100000.0, 172800.0])
	var starving := _members([0.125, 0.25, 1.0, 0.0])
	for hot in [false, true]:
		_pair("48-hour starvation deaths hot=" + str(hot), _state(starving, 0.0, 47.9), starving, {}, [1800.0, 7200.0, 21600.0], {}, hot)
	var simultaneous := _members([6.0, 10.0, 5.0])
	var coupled: Dictionary = Sustain.create()
	Sustain.add_members(coupled, simultaneous, [1])
	Sustain.add_members(coupled, simultaneous, [2, 3])
	coupled.morale = 50.0
	coupled.cohorts[0].hunger = 48.0
	coupled.cohorts[1].hunger = 10.0
	coupled.cohorts[1].coverage = 1.0
	coupled.cohorts[1].bonus_pending = true
	for cohort: Dictionary in coupled.cohorts: cohort.meal_until = 21600.0
	_pair("one cohort dies as another receives meal bonus", coupled, simultaneous, {}, [21600.0, 25200.0])
	_pair("paused", _state(members), members, {"grain": 1}, [100.0], {"paused": true})
	var many := {}
	for index in range(1000): many[index + 1] = {"person_id": index + 1, "hp": 100.0}
	_pair("1000 original hot bodies", _state(many), many, {"grain": 1000}, [2.0, 4.0, 6.0], {}, true)
	_fully_fed_cases()
	_resupply_cases()
	_membership_cases()
	_invalid_cases()
	print("GATE FAIL: Sustain equivalence " if failed else "GATE OK: Sustain equivalence ", checks, " checks")
	quit(2 if failed else 0)
