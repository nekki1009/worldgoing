extends "res://scripts/tests/site_boarding_b6_exit_test.gd"

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	if not _setup_b6() or not _public_link_b6(): return
	if not _region_cases_b6(): return
	print("SITE_BOARDING_B6_REGION_PREFLIGHT_PASS")
	await _cleanup(0)

func _region_cases_b6() -> bool:
	var controller: SiteController = lab.site_controller
	var captured: Dictionary = controller._capture_for_save()
	if not _must(captured.ok, "B6_REGION_STEADY_CAPTURE " + str(captured)): return false
	var state: Dictionary = lab.terrain.site
	var before: PackedByteArray = var_to_bytes(state)
	var teams: Array[int] = [int(team.team_id), int(enemy.team_id)]
	for identity: int in teams:
		var spec: Dictionary = {"team_id": identity, "controller": "npc", "mode": "sea"}
		var extracted: Dictionary = RegionTravel.extract(state, spec, "b6_rejected_" + str(identity))
		if not _must(not extracted.ok and extracted.code == "BOARDING_TRAVEL_UNSUPPORTED" and var_to_bytes(state) == before, "B6_REGION_EITHER_LINK_ENDPOINT_REFUSES_ATOMICALLY " + str(extracted)): return false
	var slot_b6: RegionSaveSlot = RegionSaveSlot.new()
	var control_before: PackedByteArray = var_to_bytes(slot_b6.control)
	var slot_before: PackedByteArray = var_to_bytes(slot_b6._marker)
	var begin: Dictionary = slot_b6.begin_region_travel(lab.terrain, {"team_id": int(team.team_id), "mode": "sea"}, 0)
	if not _must(not begin.ok and begin.code == "BOARDING_TRAVEL_UNSUPPORTED" and var_to_bytes(state) == before and var_to_bytes(slot_b6.control) == control_before and var_to_bytes(slot_b6._marker) == slot_before, "B6_PUBLIC_SLOT_PREFLIGHT_PRECEDES_RECOVERY_ID_TIME_FILES " + str(begin)): return false
	for identity: String in [boat_id, enemy_boat]:
		var selected: Array[String] = [identity]
		var transfer: Dictionary = slot_b6.prepare_ship_transfer(lab.terrain, Vector2i(1, 0), selected, Vector2i(1, 1), Vector2i.DOWN)
		if not _must(not transfer.ok and transfer.code == "BOARDING_TRAVEL_UNSUPPORTED" and var_to_bytes(state) == before and var_to_bytes(slot_b6.control) == control_before and var_to_bytes(slot_b6._marker) == slot_before, "B6_PUBLIC_SHIP_TRANSFER_REFUSES_EITHER_ENDPOINT_BEFORE_RECOVERY " + str(transfer)): return false
	# Real independent onshore original row; the unrelated linked boats remain behind.
	var solo: Dictionary = {"solo_row": people[2], "person_id": people[2], "team_id": int(team.team_id), "controller": "npc", "mode": "land"}
	var walking: Dictionary = RegionTravel.extract(state, solo, "b6_independent_walker")
	if not _must(walking.ok and var_to_bytes(state) == before, "B6_UNRELATED_WALKER_DEPARTS_WITH_LINK_LEFT_BEHIND " + str(walking)): return false
	if not _must(walking.origin.vehicles.has(boat_id) and walking.origin.vehicles.has(enemy_boat) and walking.party.content.vehicles.is_empty(), "B6_INDEPENDENT_PARTY_TRUE_VEHICLE_CLOSURE"): return false
	var destination_before: PackedByteArray = var_to_bytes(walking.origin)
	# Unsupported legacy arrival payload wraps the genuinely produced linked Site closure.
	var linked_incoming: Dictionary = {"content": state}
	var rejected_arrival: Dictionary = RegionTravel.prepare_arrival(walking.origin, linked_incoming)
	var rejected_insert: Dictionary = RegionTravel.insert(walking.origin, linked_incoming, lab.terrain, native_dock.shore, "b6_unused.json", 0.0, 0.0)
	var rejected_join: Dictionary = RegionTravel.join_party(walking.party, linked_incoming)
	if not _must(not rejected_arrival.ok and rejected_arrival.code == "BOARDING_TRAVEL_UNSUPPORTED" and not rejected_insert.ok and rejected_insert.code == "BOARDING_TRAVEL_UNSUPPORTED" and not rejected_join.ok and rejected_join.code == "BOARDING_TRAVEL_UNSUPPORTED" and var_to_bytes(state) == before and var_to_bytes(walking.origin) == destination_before, "B6_LINKED_INCOMING_ARRIVAL_INSERT_JOIN_REFUSE_BEFORE_MUTATION"): return false
	var arrival: Dictionary = RegionTravel.prepare_arrival(walking.origin, walking.party)
	if not _must(arrival.ok and var_to_bytes(walking.origin) == destination_before, "B6_UNRELATED_LINK_AT_DESTINATION_DOES_NOT_BLOCK_ARRIVAL " + str(arrival)): return false
	# Malformed selected naval data refuses explicitly, without a Variant.get crash or acceptance.
	var corrupt: Dictionary = state.duplicate(true)
	corrupt.vehicles[boat_id].naval = 7
	var malformed: Dictionary = RegionTravel.boarding_travel_guard(corrupt, [boat_id])
	return _must(not malformed.ok and malformed.code == "INVALID", "B6_MALFORMED_NAVAL_REJECTS " + str(malformed))
