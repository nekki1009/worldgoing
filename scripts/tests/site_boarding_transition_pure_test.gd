extends SceneTree
## B2S2: pure link transitions. No Site lab, no person job, no NPC authority.
const LinkContract = preload("res://scripts/terrain_lab/site_boarding_link_contract.gd")
const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
var failed: bool = false

func _must(condition: bool, message: String) -> bool:
	if condition: return true
	if not failed:
		failed = true
		push_error(message)
	return false

func _state() -> Dictionary:
	var first: Dictionary = Ship.make_record("boat_a", 1, "ferry", 0, Vector2i.RIGHT)
	var second: Dictionary = Ship.make_record("boat_b", 2, "ferry", 5, Vector2i.RIGHT)
	# One real original person (id 7) is the only possible crosser in these fixtures.
	return {"id": "b2s2-site", "vehicles": {"boat_a": first, "boat_b": second},
		"actors": {"row_7": {"person_id": 7}}, "armies": [], "ground_loot": {}}

func _linked() -> Dictionary:
	var made: Dictionary = LinkContract.make_pair(_state(), "boat_a", "boat_b", "b2s2-link", 3,
		Vector2i(10, 10), Vector2i(12, 10), [1.0, 0.5], [0.5, 0.5])
	return made.state if made.ok else {}

func _initialize() -> void:
	var linked: Dictionary = _linked()
	if not _must(not linked.is_empty(), "B2S2_FIXTURE_LINKED"): _finish(); return
	var before: PackedByteArray = var_to_bytes(linked)

	# Accepted transitions keep the same epoch and never alter the input.
	var closed: Dictionary = LinkContract.set_state(linked, "boat_a", "closing")
	if not _must(closed.ok and closed.link_state == "closing" and not closed.entrants_open, "B2S2_CLOSING_BLOCKS_ENTRY: " + str(closed)): _finish(); return
	_must(var_to_bytes(linked) == before, "B2S2_INPUT_UNCHANGED")
	_must(closed.state.vehicles.boat_a.naval.boarding_link.epoch == 3 and closed.state.vehicles.boat_b.naval.boarding_link.epoch == 3, "B2S2_EPOCH_KEPT_ON_CLOSE")
	var reopened: Dictionary = LinkContract.set_state(closed.state, "boat_b", "linked")
	_must(reopened.ok and reopened.link_state == "linked" and reopened.entrants_open, "B2S2_CLOSING_TO_LINKED_REOPENS")

	# One crosser at a time; the crosser does not change the epoch.
	var crossing: Dictionary = LinkContract.enter_crosser(linked, "boat_a", 7)
	if not _must(crossing.ok and crossing.crosser_id == 7 and not crossing.entrants_open, "B2S2_ENTER_CROSSER: " + str(crossing)): _finish(); return
	_must(crossing.state.vehicles.boat_b.naval.boarding_link.crosser_id == 7, "B2S2_CROSSER_BOTH_ENDS")
	_must(crossing.state.vehicles.boat_a.naval.boarding_link.epoch == 3, "B2S2_EPOCH_KEPT_ON_CROSSER")
	var crossing_before: PackedByteArray = var_to_bytes(crossing.state)
	var quiet: Dictionary = LinkContract.set_state(crossing.state, "boat_a", "closing")
	_must(quiet.ok and quiet.crosser_id == 7 and not quiet.entrants_open, "B2S2_CLOSING_KEEPS_CROSSER")
	var left: Dictionary = LinkContract.leave_crosser(quiet.state, "boat_b")
	_must(left.ok and left.crosser_id == 0 and left.link_state == "closing", "B2S2_LEAVE_WHILE_CLOSING")
	_must(var_to_bytes(crossing.state) == crossing_before, "B2S2_CROSSING_INPUT_UNCHANGED")

	# Refusals: each leaves the caller's state byte-equal.
	var refusals: Array = [
		["BUSY", LinkContract.set_state(linked, "boat_a", "establishing")],
		["BUSY", LinkContract.enter_crosser(closed.state, "boat_a", 7)],
		["BUSY", LinkContract.enter_crosser(crossing.state, "boat_b", 8)],
		["NO_TARGET", LinkContract.enter_crosser(linked, "boat_a", 0)],
		["CORRUPT_SAVE", LinkContract.enter_crosser(linked, "boat_a", 9)],
		["NO_TARGET", LinkContract.leave_crosser(linked, "boat_a")],
	]
	for refusal: Array in refusals:
		var code: String = refusal[0]
		var result: Dictionary = refusal[1]
		_must(not result.ok and result.code == code, "B2S2_REFUSAL_" + code + ": " + str(result))
	_must(var_to_bytes(linked) == before, "B2S2_REFUSAL_PURITY_LINKED")

	# Invalid is terminal: no entry, no leave, no reopen.
	var invalid: Dictionary = LinkContract.set_state(linked, "boat_a", "invalid")
	if not _must(invalid.ok and invalid.link_state == "invalid" and not invalid.entrants_open, "B2S2_INVALID_REACHABLE"): _finish(); return
	var invalid_before: PackedByteArray = var_to_bytes(invalid.state)
	var no_return: Dictionary = LinkContract.set_state(invalid.state, "boat_a", "linked")
	_must(not no_return.ok and no_return.code == "BUSY", "B2S2_INVALID_TERMINAL")
	var no_entry: Dictionary = LinkContract.enter_crosser(invalid.state, "boat_a", 7)
	_must(not no_entry.ok and no_entry.code == "BUSY", "B2S2_INVALID_NO_ENTRY")
	var no_leave: Dictionary = LinkContract.leave_crosser(invalid.state, "boat_a")
	_must(not no_leave.ok and no_leave.code == "BUSY", "B2S2_INVALID_NO_LEAVE")
	_must(var_to_bytes(invalid.state) == invalid_before, "B2S2_INVALID_PURITY")

	# Establishing completes only when both hulls are afloat.
	var establishing: Dictionary = _linked()
	for identity: String in ["boat_a", "boat_b"]:
		establishing.vehicles[identity].naval.boarding_link.state = "establishing"
	var completed: Dictionary = LinkContract.set_state(establishing, "boat_a", "linked")
	_must(completed.ok and completed.link_state == "linked", "B2S2_ESTABLISH_COMPLETES: " + str(completed))
	var wrecked: Dictionary = establishing.duplicate(true)
	wrecked.vehicles.boat_b.naval.state = "wrecked"
	wrecked.vehicles.boat_b.naval.hp = 0.0
	var wrecked_before: PackedByteArray = var_to_bytes(wrecked)
	var refused: Dictionary = LinkContract.set_state(wrecked, "boat_a", "linked")
	_must(not refused.ok and refused.code == "BUSY", "B2S2_ESTABLISH_NEEDS_BOTH_AFLOAT: " + str(refused))
	_must(var_to_bytes(wrecked) == wrecked_before, "B2S2_ESTABLISH_REFUSAL_PURITY")
	_finish()

func _finish() -> void:
	if failed:
		quit(1)
		return
	print("SITE_BOARDING_B2S2_PASS: " + get_script().resource_path)
	quit(0)
