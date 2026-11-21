extends SceneTree
## B3S1: pure crossing ledger. No Site lab, no body move, no person job.
const LinkContract = preload("res://scripts/terrain_lab/site_boarding_link_contract.gd")
const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
var failed: bool = false

func _must(condition: bool, message: String) -> bool:
	if condition: return true
	if not failed:
		failed = true
		push_error(message + " [hex " + message.to_utf8_buffer().hex_encode() + "]")
	return false

func _linked() -> Dictionary:
	var first: Dictionary = Ship.make_record("boat_a", 1, "ferry", 0, Vector2i.RIGHT)
	var second: Dictionary = Ship.make_record("boat_b", 2, "ferry", 5, Vector2i.RIGHT)
	# Original person rows 7 and 8 exist, so both are legal crossers when unlinked from the channel.
	var state: Dictionary = {"id": "b3s1-site", "vehicles": {"boat_a": first, "boat_b": second},
		"actors": {"row_7": {"person_id": 7}, "row_8": {"person_id": 8}}, "armies": [], "ground_loot": {}}
	var made: Dictionary = LinkContract.make_pair(state, "boat_a", "boat_b", "b3s1-link", 3,
		Vector2i(10, 10), Vector2i(12, 10), [1.0, 0.5], [0.5, 0.5])
	return made.state if made.ok else {}

func _initialize() -> void:
	var linked: Dictionary = _linked()
	if not _must(not linked.is_empty(), "B3S1_FIXTURE_LINKED"): _finish(); return
	var before: PackedByteArray = var_to_bytes(linked)

	# Begin from either side; both ends record the same crosser and keep the epoch.
	var entered: Dictionary = LinkContract.crossing_begin(linked, "boat_a", "boat_b", 7)
	if not _must(entered.ok and entered.crosser_id == 7 and not entered.entrants_open, "B3S1_BEGIN_FROM_A: " + str(entered)): _finish(); return
	_must(entered.state.vehicles.boat_b.naval.boarding_link.crosser_id == 7 and entered.state.vehicles.boat_a.naval.boarding_link.epoch == 3, "B3S1_BOTH_ENDS_SAME_CROSSER_EPOCH")
	var from_b: Dictionary = LinkContract.crossing_begin(linked, "boat_b", "boat_a", 8)
	_must(from_b.ok and from_b.crosser_id == 8, "B3S1_BEGIN_FROM_B")
	_must(var_to_bytes(linked) == before, "B3S1_INPUT_UNCHANGED")

	# One crosser at a time: a second person and the same person are both refused.
	var occupied: Dictionary = entered.state
	var occupied_before: PackedByteArray = var_to_bytes(occupied)
	var second_person: Dictionary = LinkContract.crossing_begin(occupied, "boat_a", "boat_b", 8)
	_must(not second_person.ok and second_person.code == "BUSY", "B3S1_SECOND_CROSSER_BUSY: " + str(second_person))
	_must(var_to_bytes(occupied) == occupied_before, "B3S1_SECOND_CROSSER_BYTES")

	# Only the recorded crosser may leave; the peer side may close it.
	var wrong_leaver: Dictionary = LinkContract.crossing_end(occupied, "boat_a", 8)
	_must(not wrong_leaver.ok and wrong_leaver.code == "BUSY", "B3S1_WRONG_LEAVER_BUSY: " + str(wrong_leaver))
	_must(var_to_bytes(occupied) == occupied_before, "B3S1_WRONG_LEAVER_BYTES")
	var left: Dictionary = LinkContract.crossing_end(occupied, "boat_b", 7)
	_must(left.ok and left.crosser_id == 0 and left.entrants_open, "B3S1_END_FROM_PEER: " + str(left))
	_must(var_to_bytes(occupied) == occupied_before, "B3S1_END_INPUT_UNCHANGED")

	# Wrong peer, no link, and no crosser are refused without writes.
	var wrong_peer: Dictionary = LinkContract.crossing_begin(linked, "boat_a", "ghost", 7)
	_must(not wrong_peer.ok and wrong_peer.code == "NO_TARGET", "B3S1_WRONG_PEER: " + str(wrong_peer))
	var no_crosser: Dictionary = LinkContract.crossing_end(linked, "boat_a", 7)
	_must(not no_crosser.ok and no_crosser.code == "NO_TARGET", "B3S1_NO_CROSSER: " + str(no_crosser))
	_must(var_to_bytes(linked) == before, "B3S1_REFUSALS_LINKED_BYTES")
	var unlinked: Dictionary = _linked()
	for identity: String in ["boat_a", "boat_b"]:
		unlinked.vehicles[identity].naval.erase("boarding_link")
		unlinked.vehicles[identity].naval.version = 1
	var unlinked_before: PackedByteArray = var_to_bytes(unlinked)
	var no_link: Dictionary = LinkContract.crossing_begin(unlinked, "boat_a", "boat_b", 7)
	_must(not no_link.ok and no_link.code == "NO_TARGET", "B3S1_NO_LINK: " + str(no_link))
	_must(var_to_bytes(unlinked) == unlinked_before, "B3S1_NO_LINK_BYTES")

	# Closing blocks a new crosser but keeps the one already in the channel.
	var closing: Dictionary = LinkContract.set_state(occupied, "boat_a", "closing")
	_must(closing.ok and closing.crosser_id == 7, "B3S1_PREMISE_CLOSING_KEEPS_CROSSER")
	var closing_before: PackedByteArray = var_to_bytes(closing.state)
	var closed_entry: Dictionary = LinkContract.crossing_begin(closing.state, "boat_a", "boat_b", 7)
	_must(false if closed_entry.ok else closed_entry.code == "BUSY", "B3S1_CLOSING_NO_NEW_ENTRY: " + str(closed_entry))
	_must(var_to_bytes(closing.state) == closing_before, "B3S1_CLOSING_ENTRY_BYTES")
	var crosser_leaves: Dictionary = LinkContract.crossing_end(closing.state, "boat_b", 7)
	_must(crosser_leaves.ok and crosser_leaves.crosser_id == 0, "B3S1_CLOSING_LETS_CROSSER_OUT")
	_finish()

func _finish() -> void:
	if failed:
		quit(1)
		return
	print("SITE_BOARDING_B3S1_PASS: " + get_script().resource_path)
	quit(0)
