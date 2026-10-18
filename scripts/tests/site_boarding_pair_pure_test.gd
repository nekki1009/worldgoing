extends SceneTree
## B2S1: pure pair constructor. No Site lab, no person job, no NPC authority.
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
	return {"id": "b2s1-site", "vehicles": {"boat_a": first, "boat_b": second},
		"actors": {}, "armies": [], "ground_loot": {}}

func _pair(state: Dictionary, self_id: String = "boat_a", peer_id: String = "boat_b", epoch: int = 3) -> Dictionary:
	return LinkContract.make_pair(state, self_id, peer_id, "b2s1-link", epoch,
		Vector2i(10, 10), Vector2i(12, 10), [1.0, 0.5], [0.5, 0.5])

func _initialize() -> void:
	var state: Dictionary = _state()
	_must(not state.vehicles.boat_a.is_empty() and not state.vehicles.boat_b.is_empty(), "B2S1_FIXTURE_SHIPS")
	var before: PackedByteArray = var_to_bytes(state)
	var made: Dictionary = _pair(state)
	if not _must(made.ok, "B2S1_PAIR_BUILDS: " + str(made)): _finish(); return
	if not _must(var_to_bytes(state) == before, "B2S1_INPUT_UNCHANGED"): _finish(); return
	var linked: Dictionary = made.state
	var checked: Dictionary = LinkContract.query(linked, "boat_a")
	_must(checked.ok and checked.linked and checked.entrants_open and not checked.can_execute, "B2S1_QUERY_LINKED_OPEN: " + str(checked))
	var other: Dictionary = LinkContract.query(linked, "boat_b")
	_must(other.ok and other.linked and other.link.self.vehicle_id == "boat_b" and other.link.peer.vehicle_id == "boat_a", "B2S1_BOTH_ENDS_CLOSED")
	_must(linked.vehicles.boat_a.naval.version == 2 and linked.vehicles.boat_b.naval.version == 2, "B2S1_NAVAL_V2_BOTH")
	_must(LinkContract.save_guard(linked).code == "BUSY", "B2S1_SAVE_GUARD_STILL_BUSY_BEFORE_B5")
	# Stable JSON round trip keeps the same closure (numbers become floats).
	var parsed: Variant = JSON.parse_string(JSON.stringify(linked, "", true, true))
	if not _must(parsed is Dictionary, "B2S1_JSON_PARSE"): _finish(); return
	var parsed_query: Dictionary = LinkContract.query(parsed, "boat_b")
	_must(parsed_query.ok and parsed_query.linked, "B2S1_JSON_ROUNDTRIP")
	# Refusals leave the caller's state byte-equal.
	var refusals: Array = [
		["NO_TARGET", _pair(state, "boat_a", "boat_a")],
		["NO_TARGET", _pair(state, "boat_a", "ghost")],
		["NO_TARGET", _pair(state, "boat_a", "boat_b", 0)],
		["CORRUPT_SAVE", LinkContract.make_pair(state, "boat_a", "boat_b", "b2s1-link", 3, Vector2i(10, 10), Vector2i(12, 10), [5.0, 0.5], [0.5, 0.5])],
		["BUSY", _pair(linked)],
	]
	var moving: Dictionary = _state()
	moving.vehicles.boat_b.move = {"path": [1]}
	refusals.append(["BUSY", _pair(moving)])
	var sinking: Dictionary = _state()
	sinking.vehicles.boat_a.naval.state = "sinking"
	refusals.append(["BUSY", _pair(sinking)])
	for refusal: Array in refusals:
		var code: String = refusal[0]
		var result: Dictionary = refusal[1]
		_must(not result.ok and result.code == code, "B2S1_REFUSAL_" + code + ": " + str(result))
	_must(var_to_bytes(state) == before, "B2S1_REFUSAL_PURITY")
	_finish()

func _finish() -> void:
	if failed:
		quit(1)
		return
	print("SITE_BOARDING_B2S1_PASS: " + get_script().resource_path)
	quit(0)
