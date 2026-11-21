extends SceneTree
## P4 S5b (precheck part): ResidentRoster.plan refuses the whole roster or plans it. Pure:
## no Site, no Lab, no person is created, and the input state is never changed.

const ResidentRoster = preload("res://scripts/terrain_lab/site_resident_roster.gd")

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("MAP_EDITOR_P4_RESIDENT_PLAN_FAIL: " + message)
	quit(1)
	return false

func _row(house: String = "h1", faction: Variant = 1) -> Dictionary:
	return {"name": "甲", "faction_id": faction, "house": house}

func _state() -> Dictionary:
	return {
		"id": "p5_site",
		"settlement": {"level": 1, "owner_faction": 1},
		"features": {
			"h1": {"kind": "house", "stage": "complete", "owner_faction": 1},
			"h2": {"kind": "house", "stage": "building", "owner_faction": 1},
			"w": {"kind": "well", "stage": "complete", "owner_faction": 1},
		},
	}

func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: push_error("MAP_EDITOR_P4_RESIDENT_PLAN_TIMEOUT"); quit(1))
	var state: Dictionary = _state()
	var before: Dictionary = state.duplicate(true)
	var capacity: Dictionary = {"h1": 2, "h2": 4, "w": 4}

	# Empty roster is planned with no rows; the whole plan is pure.
	var none: Array = []
	var empty_plan: Dictionary = ResidentRoster.plan(state, none, capacity)
	if not _check(empty_plan.ok and int(empty_plan.total) == 0, "empty roster plans with zero rows"): return

	# Two rows fit the two beds of h1; counts are per house.
	var fits: Array = [_row("h1"), _row("h1")]
	var fit_plan: Dictionary = ResidentRoster.plan(state, fits, capacity)
	if not _check(fit_plan.ok and int(fit_plan.counts.h1) == 2 and int(fit_plan.total) == 2, "two rows fit two beds"): return

	# A third row for h1 exceeds its capacity: whole roster refused.
	var over: Array = [_row("h1"), _row("h1"), _row("h1")]
	var over_plan: Dictionary = ResidentRoster.plan(state, over, capacity)
	if not _check(not over_plan.ok and over_plan.code == "NO_BEDS", "third row over capacity refused NO_BEDS"): return

	# A house still under construction, a non-house feature, a missing key, and a foreign faction are refused.
	var building: Dictionary = ResidentRoster.plan(state, [_row("h2")], capacity)
	if not _check(not building.ok and building.code == "RESIDENT_HOUSE", "incomplete house refused"): return
	var well: Dictionary = ResidentRoster.plan(state, [_row("w")], capacity)
	if not _check(not well.ok and well.code == "RESIDENT_HOUSE", "non-house feature refused"): return
	var missing: Dictionary = ResidentRoster.plan(state, [_row("nope")], capacity)
	if not _check(not missing.ok and missing.code == "RESIDENT_HOUSE", "missing house key refused"): return
	var foreign: Dictionary = ResidentRoster.plan(state, [_row("h1", 2)], capacity)
	if not _check(not foreign.ok and foreign.code == "RESIDENT_FACTION", "foreign faction row refused"): return

	# One bad row in an otherwise valid roster refuses the whole roster (no partial plan).
	var mixed: Array = [_row("h1"), _row("h1", 2)]
	var mixed_plan: Dictionary = ResidentRoster.plan(state, mixed, capacity)
	if not _check(not mixed_plan.ok and not mixed_plan.has("counts"), "mixed roster refused whole"): return

	# Settlement that cannot hold residents, or has no owner, is refused.
	var no_level: Dictionary = _state()
	no_level.settlement.level = 0
	if not _check(not ResidentRoster.plan(no_level, fits, capacity).ok, "level 0 settlement refused"): return
	var no_settlement: Dictionary = _state()
	no_settlement.erase("settlement")
	if not _check(ResidentRoster.plan(no_settlement, none, capacity).code == "NO_SETTLEMENT", "no settlement refused"): return

	# Invalid roster shape is refused before any settlement check.
	var bad: Dictionary = ResidentRoster.plan(state, [{"name": "甲", "faction_id": -1, "house": "h1"}], capacity)
	if not _check(not bad.ok and bad.code == "INVALID_RESIDENT_ROSTER", "invalid row refused INVALID_RESIDENT_ROSTER"): return

	# JSON round trip: float owner faction and float capacity still plan.
	var parsed_state: Variant = JSON.parse_string(JSON.stringify(state))
	var parsed_capacity: Variant = JSON.parse_string(JSON.stringify(capacity))
	var parsed_rows: Variant = JSON.parse_string(JSON.stringify(fits))
	var round: Dictionary = ResidentRoster.plan(parsed_state, parsed_rows, parsed_capacity)
	if not _check(round.ok and int(round.counts.h1) == 2, "round-tripped state and rows plan"): return

	if not _check(state == before, "input state unchanged by planning"): return
	print("MAP_EDITOR_P4_RESIDENT_PLAN_PASS: empty, fit, bed shortage, house and faction refusals, whole-roster refusal, JSON round trip")
	quit(0)
