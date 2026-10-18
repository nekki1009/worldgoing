extends "res://scripts/tests/site_boarding_begin_test.gd"
## B2S4: the held boarding action commits both ends atomically, or refuses with no write.
## Reuses the B0 fixture (inherited) and the B2S3 begin gate.

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	if not _must(DisplayServer.get_name() == "headless", "B2S4_CANONICAL_HEADLESS"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for owner: TerrainArmy in lab.combat_armies: owner.set_process(false)
	if not _fixture() or not _cases_b2s4(): return
	print("SITE_BOARDING_B2S4_PASS: " + get_script().resource_path)
	await _cleanup(0)

func _records_b2s4() -> Dictionary:
	return lab.site_controller.vehicles.records()

## Hull records with the naval key removed: the non-link state that must not move.
func _non_naval_b2s4(records: Dictionary) -> PackedByteArray:
	var copy: Dictionary = records.duplicate(true)
	for identity: String in copy:
		copy[identity].erase("naval")
	return var_to_bytes(copy)

func _begin_hold_b2s4(person: int) -> bool:
	var actions: Variant = lab.site_controller.person_actions
	var began: Dictionary = actions.begin_boarding_link(person, boat_id, enemy_boat, person)
	if not _must(began.ok, "B2S4_BEGIN: " + str(began)): return false
	actions.advance_ship_jobs(B2Contract.LINK_ACTION_SECONDS)
	var job: Dictionary = actions._jobs.get(str(person), {})
	return _must(not job.is_empty() and str(job.paused) == "AWAIT_COMMIT", "B2S4_HELD_AWAIT_COMMIT")

func _cases_b2s4() -> bool:
	var vehicles: Variant = lab.site_controller.vehicles
	var actions: Variant = lab.site_controller.person_actions
	var aboard: int = people[0]
	var live: Dictionary = _records_b2s4()
	if not _must(str(vehicles.ship_person(aboard).row.get("embarked_vehicle_id", "")) == boat_id, "B2S4_PREMISE_EMBARKED"): return false

	# Case 1: target moved on after the hold. Commit re-proves, refuses, writes nothing.
	if not _begin_hold_b2s4(aboard): return false
	var before_stale: PackedByteArray = var_to_bytes(_records_b2s4())
	live[enemy_boat].revision += 1
	var moved_snapshot: PackedByteArray = var_to_bytes(_records_b2s4())
	actions.advance_ship_jobs(0.1)
	if not _must(actions._jobs.is_empty() and str(actions._results.back().code) == "STALE", "B2S4_STALE_DROPS_JOB: " + str(actions._results.back())): return false
	if not _must(var_to_bytes(_records_b2s4()) == moved_snapshot and _no_link_b2s3(), "B2S4_STALE_WRITES_NOTHING"): return false
	_must(moved_snapshot != before_stale, "B2S4_PREMISE_REVISION_MOVED")

	# Case 2: the peer hull sinks during the hold. Commit refuses; the wreck is untouched.
	if not _begin_hold_b2s4(aboard): return false
	var saved_naval: Dictionary = live[enemy_boat].naval.duplicate(true)
	live[enemy_boat].naval.state = "wrecked"
	live[enemy_boat].naval.hp = 0.0
	var sunk_snapshot: PackedByteArray = var_to_bytes(_records_b2s4())
	actions.advance_ship_jobs(0.1)
	if not _must(actions._jobs.is_empty() and not actions._results.is_empty() and not bool(actions._results.back().get("ok", true)), "B2S4_SINK_DROPS_JOB"): return false
	if not _must(var_to_bytes(_records_b2s4()) == sunk_snapshot and _no_link_b2s3(), "B2S4_SINK_WRITES_NOTHING"): return false
	live[enemy_boat].naval = saved_naval
	if not _must(_no_link_b2s3(), "B2S4_RESTORE_NO_LINK"): return false

	# Case 3: cancel during the hold. Cancel never writes a link.
	if not _begin_hold_b2s4(aboard): return false
	var cancelled: Dictionary = actions.cancel(aboard)
	if not _must(cancelled.ok and actions._jobs.is_empty() and _no_link_b2s3(), "B2S4_CANCEL_NO_LINK"): return false

	# Case 4: the real commit. Both ends v2 linked, nothing else in either hull moves.
	if not _begin_hold_b2s4(aboard): return false
	var before_commit: Dictionary = _records_b2s4().duplicate(true)
	var before_bytes: PackedByteArray = _non_naval_b2s4(_records_b2s4())
	actions.advance_ship_jobs(0.1)
	if not _must(actions._jobs.is_empty() and not actions._results.is_empty() and bool(actions._results.back().get("ok", false)), "B2S4_COMMIT_RESULT: " + str(actions._results.back())): return false
	var records: Dictionary = _records_b2s4()
	for identity: String in [boat_id, enemy_boat]:
		var link: Dictionary = records[identity].naval.get("boarding_link", {})
		if not _must(int(records[identity].naval.version) == 2 and str(link.state) == "linked" and int(link.crosser_id) == 0 and int(link.epoch) == 1, "B2S4_BOTH_ENDS_V2_LINKED: " + identity): return false
	if not _must(_non_naval_b2s4(records) == before_bytes, "B2S4_COMMIT_TOUCHES_ONLY_NAVAL"): return false
	var checked: Dictionary = LinkContract.query(lab.terrain.site, boat_id, lab.terrain)
	if not _must(checked.ok and checked.linked and checked.entrants_open and not checked.can_execute, "B2S4_QUERY_ACCEPTS_COMMIT: " + str(checked)): return false
	# Q1 applies to manual commands and the routed original step producer.
	var b2_fixed_before: PackedByteArray = var_to_bytes(records)
	var b2_forward: Dictionary = vehicles.ship_order(boat_id, "forward", Vector2i.ZERO, aboard)
	var b2_sail: Dictionary = vehicles.ship_order(boat_id, "sail", native_dock.anchor, aboard)
	var b2_routed: Dictionary = vehicles._commit_ship_step(records[boat_id], native_dock.anchor + native_dock.facing, native_dock.facing, "forward")
	if not _must(not b2_forward.ok and b2_forward.code == "BUSY" and not b2_sail.ok and b2_sail.code == "BUSY" and not b2_routed.ok and b2_routed.code == "BUSY", "B2_LINK_BLOCKS_BOTH_ORIGINAL_MOTION_PRODUCERS"): return false
	if not _must(var_to_bytes(records) == b2_fixed_before, "B2_LINK_MOTION_REFUSALS_PRESERVE_BOTH_HULLS"): return false
	# The B0 save gate is kept: an active link is not admitted before B5.
	if not _must(vehicles.boarding_save_guard().code == "BUSY", "B2S4_SAVE_STILL_REFUSES_ACTIVE_LINK"): return false
	if not _must(not before_commit.is_empty(), "B2S4_PREMISE_SNAPSHOT"): return false
	return true
