extends "res://scripts/tests/site_boarding_commit_test.gd"
## B2b: a linked hull is fixed (Q1 A refusals), unlink clears both ends (Q2 A, no crosser),
## and the link epoch advances on every connect and survives unlink (plan lines 33, 60, 99).

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	if not _must(DisplayServer.get_name() == "headless", "B2B_CANONICAL_HEADLESS"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for owner: TerrainArmy in lab.combat_armies: owner.set_process(false)
	if not _fixture() or not _cases_b2b(): return
	print("SITE_BOARDING_B2B_PASS: " + get_script().resource_path)
	await _cleanup(0)

## Connects through the real B2 path: begin, hold, then the commit tick.
func _connect_b2b(person: int) -> bool:
	if not _begin_hold_b2s4(person): return false
	lab.site_controller.person_actions.advance_ship_jobs(0.1)
	return _must(lab.site_controller.person_actions._jobs.is_empty(), "B2B_CONNECT_COMMITTED")

func _epochs_b2b() -> Array:
	var records: Dictionary = lab.site_controller.vehicles.records()
	return [int(records[boat_id].naval.get("link_epoch", -1)), int(records[enemy_boat].naval.get("link_epoch", -1))]

func _cases_b2b() -> bool:
	var vehicles: Variant = lab.site_controller.vehicles
	var aboard: int = people[0]
	if not _must(str(vehicles.ship_person(aboard).row.get("embarked_vehicle_id", "")) == boat_id, "B2B_PREMISE_EMBARKED"): return false

	# Connect #1 through the real path: both ends v2, epoch 1 on each hull.
	if not _connect_b2b(aboard): return false
	if not _must(_epochs_b2b() == [1, 1], "B2B_EPOCH_FIRST_CONNECT: " + str(_epochs_b2b())): return false

	# Q1 A: every independent step on the linked hull is refused, and nothing is written.
	var before: PackedByteArray = var_to_bytes(vehicles.records())
	var walk: Dictionary = vehicles.ship_walk_query(aboard, Vector2(1.0, 1.0), aboard)
	if not _must(not walk.ok and walk.code == "BUSY", "B2B_WALK_REFUSED: " + str(walk)): return false
	var helm: Dictionary = vehicles.ship_action_query("ship_helm", aboard, boat_id, 0, Vector2i(0, 0), aboard)
	if not _must(not helm.ok and helm.code == "BUSY", "B2B_HELM_REFUSED: " + str(helm)): return false
	var disembark: Dictionary = vehicles.ship_action_query("ship_disembark", aboard, boat_id, -1, Vector2i(0, 0), aboard)
	if not _must(not disembark.ok and disembark.code == "BUSY", "B2B_DISEMBARK_REFUSED: " + str(disembark)): return false
	var board: Dictionary = vehicles.ship_action_query("ship_board", people[1], enemy_boat, -1, Vector2i(0, 0), people[1], true)
	if not _must(not board.ok and board.code == "BUSY", "B2B_BOARD_REFUSED: " + str(board)): return false
	var fleet: Array[String] = [boat_id]
	var journey: Dictionary = lab.site_controller.begin_ship_journey(fleet, Vector2i(0, 0), Vector2i(0, 0), Vector2i(1, 0), aboard)
	if not _must(not journey.ok and journey.code == "BUSY", "B2B_JOURNEY_REFUSED: " + str(journey)): return false
	if not _must(var_to_bytes(vehicles.records()) == before, "B2B_REFUSALS_LEAVE_RECORDS"): return false

	# Unlink without authority is refused; with authority and no crosser it clears both ends at once.
	var stranger: Dictionary = vehicles.request_boarding_unlink(people[1], people[1])
	if not _must(not stranger.ok and var_to_bytes(vehicles.records()) == before, "B2B_UNLINK_NO_AUTHORITY: " + str(stranger)): return false
	var cleared: Dictionary = vehicles.request_boarding_unlink(aboard, aboard)
	if not _must(cleared.ok, "B2B_UNLINK: " + str(cleared)): return false
	var live: Dictionary = vehicles.records()
	for identity: String in [boat_id, enemy_boat]:
		if not _must(not live[identity].naval.has("boarding_link") and int(live[identity].naval.version) == 1, "B2B_UNLINK_CLEARS_BOTH: " + identity): return false
	if not _must(_epochs_b2b() == [1, 1], "B2B_UNLINK_KEEPS_EPOCH"): return false
	if not _must(vehicles.boarding_save_guard().ok, "B2B_SAVE_GATE_RELEASED_AFTER_UNLINK"): return false

	# Connect #2: the epoch advances, and the walk is allowed again on the cleared hull.
	if not _connect_b2b(aboard): return false
	if not _must(_epochs_b2b() == [2, 2], "B2B_EPOCH_ADVANCES_ON_RECONNECT: " + str(_epochs_b2b())): return false
	var again: Dictionary = vehicles.ship_walk_query(aboard, Vector2(1.0, 1.0), aboard)
	return _must(not again.ok and again.code == "BUSY", "B2B_RECONNECT_FIXES_HULL_AGAIN: " + str(again))
