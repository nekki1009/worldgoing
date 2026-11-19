extends SceneTree
## P4 S5 (author data part): the static resident roster rows (site_resident_roster.gd).
## Pure: no Site, no Lab, no person is created. Refused input changes nothing.
## Positive add/remove through the family panel is NOT covered here (see S5_DESIGN.md).

const ResidentRoster = preload("res://scripts/terrain_lab/site_resident_roster.gd")

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("MAP_EDITOR_P4_RESIDENT_ROSTER_FAIL: " + message)
	quit(1)
	return false

func _row(display_name: Variant = "甲", faction: Variant = 1, house: Variant = "house_1") -> Dictionary:
	return {"name": display_name, "faction_id": faction, "house": house}

func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: push_error("MAP_EDITOR_P4_RESIDENT_ROSTER_TIMEOUT"); quit(1))

	# Lists: empty, one row, and the full cap are valid; one past the cap is refused.
	var none: Array = []
	if not _check(ResidentRoster.valid_rows(none), "empty roster valid"): return
	var one: Array = [_row()]
	if not _check(ResidentRoster.valid_rows(one), "one row valid"): return
	var full: Array = []
	for index: int in ResidentRoster.ROSTER_MAX: full.append(_row("甲%d" % index))
	if not _check(ResidentRoster.valid_rows(full), "cap-size roster valid"): return
	full.append(_row("多出"))
	if not _check(not ResidentRoster.valid_rows(full), "roster one past the cap refused"): return
	if not _check(not ResidentRoster.valid_rows({"name": "甲"}), "a dictionary is not a roster"): return

	# Row shape: exactly three fields with the documented types and bounds.
	if not _check(ResidentRoster.valid_row(_row("甲", 0, "house_0")), "faction 0 and house key valid"): return
	if not _check(not ResidentRoster.valid_row("甲"), "non-dictionary row refused"): return
	if not _check(not ResidentRoster.valid_row({"name": "甲", "faction_id": 1}), "row missing house refused"): return
	var extra: Dictionary = _row()
	extra.person_id = 4
	if not _check(not ResidentRoster.valid_row(extra), "row with a person id refused"): return
	if not _check(not ResidentRoster.valid_row(_row("")), "empty name refused"): return
	if not _check(not ResidentRoster.valid_row(_row("   ")), "blank name refused"): return
	if not _check(ResidentRoster.valid_row(_row("甲".repeat(ResidentRoster.NAME_MAX))), "32-character name valid"): return
	if not _check(not ResidentRoster.valid_row(_row("甲".repeat(ResidentRoster.NAME_MAX + 1))), "33-character name refused"): return
	if not _check(not ResidentRoster.valid_row(_row(3)), "integer name refused"): return
	if not _check(not ResidentRoster.valid_row(_row("甲", -1)), "negative faction refused"): return
	if not _check(not ResidentRoster.valid_row(_row("甲", 1.5)), "fractional faction refused"): return
	if not _check(not ResidentRoster.valid_row(_row("甲", "1")), "string faction refused"): return
	if not _check(not ResidentRoster.valid_row(_row("甲", 1, "")), "empty house refused"): return
	if not _check(not ResidentRoster.valid_row(_row("甲", 1, "h".repeat(65))), "65-character house refused"): return
	if not _check(not ResidentRoster.valid_row(_row("甲", 1, 7)), "integer house refused"): return

	# JSON round trip: numbers come back as floats and still validate.
	var text: String = JSON.stringify([_row("乙", 2, "house_9")])
	var parsed: Variant = JSON.parse_string(text)
	if not _check(ResidentRoster.valid_rows(parsed), "round-tripped roster validates"): return
	if not _check(float(parsed[0].get("faction_id")) == 2.0, "round-tripped faction numeric"): return

	# State: no key is valid; a present key must hold valid rows.
	if not _check(ResidentRoster.valid_state({}), "state without roster valid"): return
	if not _check(ResidentRoster.valid_state({"residents": []}), "state with empty roster valid"): return
	if not _check(not ResidentRoster.valid_state({"residents": "甲"}), "non-array roster refused"): return
	if not _check(not ResidentRoster.valid_state({"residents": [{"name": "甲"}]}), "state with a bad row refused"): return
	if not _check(not ResidentRoster.valid_state(null), "non-dictionary state refused"): return

	# Candidate: a valid list gives a new state; refusals and the input stay unchanged.
	var state: Dictionary = {"id": "p5_site", "features": {}}
	var state_before: Dictionary = state.duplicate(true)
	var rows: Array = [_row("甲", 1, "house_1"), _row("乙", 1, "house_2")]
	var rows_before: Array = rows.duplicate(true)
	var made: Dictionary = ResidentRoster.roster_candidate(state, rows)
	if not _check(made.ok and made.state.get("residents", []).size() == 2, "valid candidate has two rows"): return
	if not _check(ResidentRoster.valid_state(made.state), "candidate state validates"): return
	if not _check(not state.has("residents") and state == state_before, "input state unchanged by candidate"): return
	if not _check(rows == rows_before, "input rows unchanged by candidate"): return
	var bad: Dictionary = ResidentRoster.roster_candidate(state, [_row("甲", -1)])
	if not _check(not bad.ok and bad.code == "INVALID_RESIDENT_ROSTER", "invalid rows refused with code"): return
	if not _check(state == state_before, "refused candidate leaves state unchanged"): return
	var overfull: Array = full.duplicate(true)
	if not _check(not ResidentRoster.roster_candidate(state, overfull).ok, "overfull candidate refused"): return

	print("MAP_EDITOR_P4_RESIDENT_ROSTER_PASS: row shape and bounds, cap, JSON round trip, state key, candidate purity")
	quit(0)
