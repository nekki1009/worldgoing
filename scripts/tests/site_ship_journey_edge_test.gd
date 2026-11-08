extends "res://scripts/tests/site_ship_journey_test.gd"
## OUTPUT candidate only: formal original Controller/Slot, real river boarding,
## helm and deck walks, true fine edge, private original geometry candidates,
## then the original retained cold-Lab replay with a fixed target. No new owner.

const EDGE_OUT := "res://output/site_ship_close_20261004/journey_edge"

func _edge_snapshot() -> Dictionary:
	return {"state": var_to_bytes(lab.terrain.site), "fingerprint": lab.terrain.fingerprint(),
		"clock": controller.region_slot.control.duplicate(true),
		"marker": controller.region_slot._marker.duplicate(true),
		"prepared": controller.region_slot._prepared.keys().duplicate(),
		"path": controller.region_slot.site_path(FROM),
		"file": FileAccess.get_file_as_bytes(controller.region_slot.site_path(FROM))}

func _unchanged_edge(before: Dictionary, label: String) -> bool:
	return _must(var_to_bytes(lab.terrain.site) == before.state and lab.terrain.fingerprint() == before.fingerprint
		and _same_json(controller.region_slot.control, before.clock) and _same_json(controller.region_slot._marker, before.marker)
		and controller.region_slot._prepared.keys() == before.prepared
		and controller.region_slot.site_path(FROM) == before.path and FileAccess.get_file_as_bytes(before.path) == before.file
		and not controller.ship_journey_active(), label + ": original source/clock/generation/token mutated")

func _reject_edge(destination: Vector2i, anchor: Vector2i, facing: Vector2i, code: String, label: String) -> bool:
	if not _capture_journey(): return false
	var before: Dictionary = _edge_snapshot()
	var boats: Array[String] = [boat_id]
	var result: Dictionary = controller.begin_ship_journey(boats, destination, anchor, facing, people[0])
	return _must(not result.ok and str(result.code) == code, label + ": wrong rejection " + str(result)) and _unchanged_edge(before, label)

func _original_deck_walk(index: int, target: Vector2) -> bool:
	var walked: Dictionary = controller.person_actions.begin_ship_walk(people[index], target, people[index], true)
	return _must(walked.ok, "Original duty deck walk rejected: " + str(walked)) and _finish_job(people[index])

func _edge_fixture() -> bool:
	if not _must(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EDGE_OUT)) == OK, "Edge evidence directory unavailable"): return false
	var coast: TerrainData = _fixed_coast()
	if coast == null: return false
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.bind_terrain(coast)
	_freeze_processes()
	controller = lab.site_controller
	controller.save_root = EDGE_OUT
	controller.save_path = EDGE_OUT.path_join("before_fixed_world.json")
	world_id = "ship_edge_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(OUT.path_join("manifest.json"), world_id, "slot", FROM, true)
	if not _must(opened.ok and controller.get_script() == SiteController, "Original fixed-world initialization rejected: " + str(opened)): return false
	_freeze_processes()
	# Crowd port (2026-11-08), as site_ship_journey: the start crowd returns to GD, the four people deploy on the same cells
	# through the trial path, and control moves to their pilot.
	if not _release_start_crowd(): return false
	var setup: Dictionary = lab._trial_side_settings({"friendly_count": 4, "friendly_role": "logistics", "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
	if not _must(setup.ok, "Original four-person edge side rejected: %s" % str(setup)): return false
	var sides: Array[Dictionary] = [setup.side]
	var cells: Array[Vector2i] = [Vector2i(11, 21), Vector2i(12, 21), Vector2i(13, 21), Vector2i(14, 21)]
	var deployed_team: Dictionary = lab._deploy_trial_teams(sides, [cells.duplicate()], 0)
	if not _must(deployed_team.ok, "Original four-person edge roster rejected: %s" % str(deployed_team)): return false
	team = null
	for candidate: Variant in lab.crowd_site.person_owners():
		if candidate is CrowdPersonOwner and candidate.has_army() and candidate.command_members().size() == 4: team = candidate
	if not _must(team != null, "Crowd formation did not hold the four original people"): return false
	team_id = team.team_id
	lab.terrain.site.army_next_team = team.team_id + 1
	lab.terrain.site.army_trial_active = true
	for index in range(4):
		var row: Dictionary = team.person(index, true)
		if not _must(not row.is_empty(), "Crowd edge person %d has no item holder" % index): return false
		people.append(int(row.person_id))
	var switched: Dictionary = lab.crowd_site.on_control_changed(lab.controlled_person_id(), people[0])
	if not _must(switched.ok, "Control could not move to the original crowd pilot: " + str(switched)): return false
	lab.terrain.site["controlled_person_id"] = people[0]
	var pool: Dictionary = controller._enable_team_supply(team)
	if not _must(not pool.is_empty(), "Original common supply unavailable"): return false
	pool.inventory.grain = 8 # Explicit initial fixture stock; physically load it below.
	var deployed: Dictionary = controller.vehicles.deploy_ship(team, "river", Vector2i(10, 19), Vector2i.LEFT, true)
	if not _must(deployed.ok, "Original river deployment rejected: " + str(deployed)): return false
	boat_id = str(deployed.vehicle_id)
	var berths: Array[int] = [0, 1, 5, 6] # Exactly MIN2 actual crew, two actual passengers.
	for index in range(4):
		if not _walk(index, Vector2i(10, 20)): return false
		if not (_stop_team() if index == 0 else _hold_team()): return false
		var boarding: Dictionary = controller.person_actions.begin_ship_board(people[index], boat_id, people[index], berths[index], true)
		if not _must(boarding.ok, "Original edge boarding rejected: " + str(boarding)) or not _finish_job(people[index]): return false
	var food: Dictionary = controller.transfer_ship_supply(team, "shore:%d" % lab.terrain.index(Vector2i(10, 20)), "vehicle:" + boat_id, {"grain": 8}, 0.0, people[0], true)
	if not _must(food.ok, "Original physical food loading rejected: " + str(food)): return false
	var helm: Dictionary = controller.person_actions.begin_ship_helm(people[0], boat_id, people[0], true)
	if not _must(helm.ok, "Original helm rejected") or not _finish_job(people[0]): return false
	lab.terrain.site.controlled_person_id = people[0]
	if not _capture_journey(): return false
	return _must(controller.save_to(controller.region_slot.site_path(FROM)).ok, "Original edge fixture snapshot rejected")

func _duty_rejections() -> bool:
	if not _original_deck_walk(1, Vector2(0.25, 1.25)): return false
	var boat: Dictionary = controller.vehicles.records()[boat_id]
	if not _must(_berth_of(people[1], boat) == 1 and not controller.vehicles.ship_local_position(people[1]).is_equal_approx(Ship.local_position("river", 1))
		and controller.vehicles.ship_crew_count(boat) == 1, "Real crew walk did not leave its unchanged original berth duty"): return false
	if not _reject_edge(TO, Vector2i(99, 19), Vector2i.LEFT, "NO_CREW", "Live nonpilot off duty"): return false
	var before: Dictionary = _edge_snapshot()
	var boats: Array[String] = [boat_id]
	var raw: Dictionary = controller.region_slot.prepare_ship_transfer(lab.terrain, TO, boats, Vector2i(99, 19), Vector2i.LEFT, true)
	if not _must(not raw.ok and raw.code == "CREW", "Original saved deck override counted as seated crew: " + str(raw)) or not _unchanged_edge(before, "Saved crew duty"): return false
	if not _original_deck_walk(1, Ship.local_position("river", 1)): return false
	if not _original_deck_walk(0, Vector2(1.25, 1.25)): return false
	if not _must(int(boat.operator_id) == 0, "Real pilot departure retained helm duty"): return false
	if not _reject_edge(TO, Vector2i(99, 19), Vector2i.LEFT, "NO_CREW", "Live pilot off helm"): return false
	before = _edge_snapshot()
	raw = controller.region_slot.prepare_ship_transfer(lab.terrain, TO, boats, Vector2i(99, 19), Vector2i.LEFT, true)
	if not _must(not raw.ok and raw.code == "CREW", "Saved off-helm pilot admitted: " + str(raw)) or not _unchanged_edge(before, "Saved helm duty"): return false
	var helm: Dictionary = controller.person_actions.begin_ship_helm(people[0], boat_id, people[0], true)
	if not _must(helm.ok, "Original pilot could not walk back to original helm") or not _finish_job(people[0]): return false
	return _must(controller.vehicles.ship_driver_ready(boat) and controller.vehicles.ship_crew_count(boat) == 2, "Original crew/helm restoration lost actual duty")

func _full_hull_unknown_route() -> bool:
	if not _capture_journey(): return false
	if not _must(controller.save_to(controller.region_slot.site_path(FROM)).ok, "Original stopped edge source save rejected"): return false
	var before: Dictionary = _edge_snapshot()
	var built: Dictionary = atlas.make_terrain_data(TO.x, TO.y)
	if not _must(built.ok, "Original opposite entry source unavailable"): return false
	var initialized: Dictionary = controller._initialize_ship_destination(built.data)
	if not _must(initialized.ok, "Original private destination initialization rejected"): return false
	var boats: Array[String] = [boat_id]
	var pair: Dictionary = controller.region_slot._transfer_pair(lab.terrain, built.data, boats, Vector2i(99, 19), Vector2i.LEFT, EDGE_OUT.path_join("private_geometry_candidate.json"), "edge_private_geometry")
	if not _must(pair.ok, "Original ownership geometry candidate rejected: " + str(pair)): return false
	var legal: Dictionary = controller.region_slot._adjacent_ship_route(lab.terrain, pair.destination_data, FROM, TO, boats)
	if not _must(legal.ok and float(legal.distance) == 7.0, "Actual river seam was not seven original2m cells: " + str(legal)): return false
	# Reload the real saved source through the original validated fixed loader.
	# Only its PRIVATE original navigation override is changed, following the
	# same explicit high-bit fixture contract as site_ship_water_test.
	var restored: Dictionary = controller.region_slot.load_compatible_site(controller.region_slot.site_path(FROM))
	if not _must(restored.ok and Store._validate_state(restored.data, restored.data.site).ok, "Original stored source edge fixture was not valid"): return false
	var origin: TerrainData = restored.data
	origin.walk_ramp_edges = origin.navigation_ramps().duplicate()
	origin.has_navigation_overrides = true
	var outer := Vector2i(0, 17)
	origin.walk_ramp_edges[origin.index(outer)] |= 1 << 7 # Local LEFT exit, north-positive global seam.
	if not _must(origin.can_navigate_water(outer) and pair.destination_data.can_navigate_water(Vector2i(99, 17))
		and origin.height_levels[origin.index(outer)] == pair.destination_data.height_levels[pair.destination_data.index(Vector2i(99, 17))], "Original outer seam fixture changed its permitted vertices or heights"): return false
	var edge_blocked: Dictionary = controller.region_slot._adjacent_ship_route(origin, pair.destination_data, FROM, TO, boats)
	if not _must(not edge_blocked.ok and edge_blocked.code == "NO_ROUTE", "Original route crossed an external beam edge forbidden by its saved-source high bit") or not _unchanged_edge(before, "Original private outer beam edge"): return false
	# Explicit UNKNOWN permission fixture in the original PRIVATE candidate only.
	# Keep its anchor cell permitted and remove one outer beam cell. No source
	# asset/Site/runtime owner is changed, and this candidate is never published.
	var destination: TerrainData = pair.destination_data
	destination.parameters = destination.parameters.duplicate(true)
	var beam := Vector2i(99, 17)
	destination.parameters.navigable_water_cells.erase(destination.index(beam))
	destination.parameters["navigable_water_bodies"] = []
	if not _must(destination.can_navigate_water(Vector2i(99, 19)) and not destination.can_navigate_water(beam), "Unknown full-beam fixture accidentally removed the anchor permission"): return false
	var blocked: Dictionary = controller.region_slot._adjacent_ship_route(lab.terrain, destination, FROM, TO, boats)
	return _must(not blocked.ok and blocked.code == "NO_ROUTE", "Route tested only its center and crossed an UNKNOWN outer hull cell") and _unchanged_edge(before, "Original private whole hull geometry")

## Diagnostic only: which part of the pending-replay invariant changed.
func _pending_diff(state_before: PackedByteArray, clock_before: float, remainder_before: float, visited_path: String, visited_bytes: PackedByteArray) -> Dictionary:
	var before: Dictionary = bytes_to_var(state_before)
	var changed: Array = []
	for key: Variant in before.keys() + lab.terrain.site.keys():
		if not before.has(key) or not lab.terrain.site.has(key) or var_to_bytes(before[key]) != var_to_bytes(lab.terrain.site[key]):
			if not changed.has(str(key)): changed.append(str(key))
	var army_fields: Array = []
	if changed.has("armies") and before.armies.size() == lab.terrain.site.armies.size():
		for at: int in range(before.armies.size()):
			var a: Dictionary = before.armies[at]
			var b: Dictionary = lab.terrain.site.armies[at]
			for key: Variant in a.keys() + b.keys():
				if not a.has(key) or not b.has(key) or var_to_bytes(a[key]) != var_to_bytes(b[key]):
					army_fields.append("%d.%s: %s -> %s" % [at, str(key), str(a.get(key)).substr(0, 160), str(b.get(key)).substr(0, 160)])
	return {"army_fields": army_fields.slice(0, 12), "clock": float(controller.region_slot.control.logical_game_seconds) == clock_before, "remainder": lab._action_time_remainder == remainder_before,
		"visited_file": FileAccess.get_file_as_bytes(visited_path) == visited_bytes, "changed_site_keys": changed}

func _complete_original_pending(prepared: Dictionary, require_pending: bool = false) -> bool:
	if prepared.ok:
		return _must(not require_pending and controller.ship_journey_status().pending, "Original visited destination completed without the required bounded PENDING")
	var visited_path := controller.region_slot.site_path(TO)
	var visited_bytes := FileAccess.get_file_as_bytes(visited_path)
	var state_before := var_to_bytes(lab.terrain.site)
	var clock_before := float(controller.region_slot.control.logical_game_seconds)
	var remainder_before := lab._action_time_remainder
	var boats: Array[String] = [boat_id]
	if not _must(not prepared.ok and prepared.code == "PENDING" and controller.region_operation_pending(), "Original visited destination did not expose bounded PENDING: " + str(prepared)): return false
	var target := float(controller._region_pending.pending.target)
	if not _must(target == clock_before, "Original cold replay selected another GAME target"): return false
	var order: Dictionary = team.issue_combat_order(people[0], TerrainArmy.CombatOrder.MOVE, Vector2i(15, 21)) if team is TerrainArmy \
		else lab.crowd_site.issue_order(team_id, TerrainArmy.CombatOrder.MOVE, Vector2i(15, 21), -1, "player")
	var walked: Dictionary = controller.person_actions.begin_ship_walk(people[2], Vector2(1, 2.25), people[2], true)
	var sail: Dictionary = controller.vehicles.ship_order(boat_id, "forward", TerrainArmy.INVALID_CELL, people[0], true)
	var departed: Dictionary = controller.begin_ship_journey(boats, TO, Vector2i(99, 19), Vector2i.LEFT, people[0])
	# Keep the real existing land NPC; do not synthesize another worker/team.
	if not _must(is_instance_valid(lab.npc), "Original fixed land world lost its worker presenter"): return false
	var worker_elapsed: float = controller._work_elapsed
	var worker_body: Dictionary = lab.npc.capture_state()
	controller.enable_worker()
	controller.release_worker()
	var zone: Dictionary = Runtime.add_zone(lab.terrain, Rect2i(11, 21, 4, 2), -1)
	if not _must(not order.ok and order.code == "BUSY" and not walked.ok and walked.code == "BUSY"
		and not sail.ok and sail.code == "BUSY" and not departed.ok and departed.code == "BUSY"
		and not zone.ok and zone.code == "BUSY" and controller._work_elapsed == worker_elapsed
		and _same_json(lab.npc.capture_state(), worker_body)
		and controller.person_actions._jobs.is_empty() and var_to_bytes(lab.terrain.site) == state_before,
		"Original pending input admitted a shore order, deck job, ship command, worker/zone input or another transfer"): return false
	var retries := 0
	while controller.region_operation_pending() and retries < 2000:
		if not _must(float(controller._region_pending.pending.target) == target, "Original pending retry changed its fixed cold target"): return false
		# The real process obtains zero elapsed input while this request waits.
		# Lab freezes; only the original finish_tick retries the retained cold Lab.
		var elapsed: float = lab._action_elapsed_input(0.05)
		if not _must(elapsed == 0.0, "Original pending process accumulated live elapsed input"): return false
		lab._advance_action_time(elapsed)
		if not _must(controller.region_operation_pending(), "Lab retried a pending cold request before the sole finish_tick publisher"): return false
		controller.finish_tick()
		retries += 1
		if not _must(float(controller.region_slot.control.logical_game_seconds) == clock_before
			and lab._action_time_remainder == remainder_before and var_to_bytes(lab.terrain.site) == state_before
			and FileAccess.get_file_as_bytes(visited_path) == visited_bytes, "Pending replay consumed source body/food/GAME/remainder or published destination prematurely: " + str(_pending_diff(state_before, clock_before, remainder_before, visited_path, visited_bytes))): return false
	var journey_status: Dictionary = controller.ship_journey_status()
	var continued := not controller.region_operation_pending() and bool(journey_status.get("pending", false)) \
		and float(journey_status.get("elapsed_action_seconds", -1.0)) == 0.0 and retries > 0
	if not continued:
		var cold_valid := is_instance_valid(lab._cold_replay_lab)
		var cold_receipt: Dictionary = RegionSaveSlot.validate_settlement(lab._cold_replay_lab.terrain.site, target) if cold_valid else {}
		print("SITE_SHIP_EDGE_PENDING_FAILURE: " + str({"retries": retries, "journey": journey_status,
			"region_pending": controller.region_operation_pending(), "message": controller.message.text,
			"pending_kind": str(controller._region_pending.get("kind", "")),
			"pending_code": str(controller._region_pending.get("pending", {}).get("code", "")),
			"cold_valid": cold_valid, "cold_last": cold_receipt.get("last", -1.0),
			"cold_debt": cold_receipt.get("pending", -1.0), "tree_paused": paused,
			"site_paused": bool(lab.terrain.site.get("paused", false))}))
	if not _must(continued, "Original cold continuation failed or replayed journey ACTION"): return false
	print("SITE_SHIP_EDGE_PENDING:original_cold_retries=%d:fixed_GAME_target=%.8f" % [retries, target])
	return true

func _visited_pending() -> bool:
	var built: Dictionary = atlas.make_terrain_data(TO.x, TO.y)
	if not _must(built.ok and controller._initialize_ship_destination(built.data).ok, "Original visited destination setup unavailable"): return false
	# This is a saved EMPTY Site with the original initialization receipt,
	# not a claim that a resident ever lived here. The existing public Slot
	# owner attaches the real current watermark without changing world time.
	var initial_game: float = float(controller.region_slot.control.logical_game_seconds)
	var attached: Dictionary = RegionSaveSlot.attach_settlement(built.data.site, initial_game)
	if not _must(attached.ok, "Original empty Site receipt initialization rejected: " + str(attached)): return false
	var receipt: Dictionary = RegionSaveSlot.validate_settlement(built.data.site, initial_game)
	if not _must(receipt.ok and not receipt.legacy and float(receipt.last) == initial_game and float(receipt.pending) == 0.0
		and float(controller.region_slot.control.logical_game_seconds) == initial_game, "Original empty Site receipt changed GAME or lacked the actual current watermark"): return false
	var saved: Dictionary = controller.region_slot.save_site(built.data)
	if not _must(saved.ok, "Original empty visited destination with initialized receipt save rejected: " + str(saved)): return false
	# Real original source phases create the destination's GAME debt. Every
	# retained cold phase uses the original Lab's bounded replay callback.
	# Keep enough real original steps to cross the frame budget and force PENDING,
	# without turning this functional continuation check into a 3600-step soak.
	var source_action: float = 10.0
	if not _step(source_action) or not _capture_journey(): return false
	var target: float = float(controller.region_slot.control.logical_game_seconds)
	var debt: Dictionary = RegionSaveSlot.validate_settlement(built.data.site, target)
	if not _must(debt.ok and not debt.legacy and float(debt.last) == initial_game and float(debt.pending) > 0.0, "Original shared source phases failed to create real destination GAME debt"): return false
	print("SITE_SHIP_EDGE_PENDING_SETUP: " + str({"empty_site_with_original_receipt":true,"source_ACTION":source_action,"initial_GAME":initial_game,"fixed_target_GAME":target,"original_debt_GAME":debt.pending,"original_frame_budget_usec":TerrainLab.ACTION_FRAME_BUDGET_USEC}))
	if not _must(controller.save_to(controller.region_slot.site_path(FROM)).ok, "Original source clock baseline save rejected"): return false
	var boats: Array[String] = [boat_id]
	var prepared: Dictionary = controller.begin_ship_journey(boats, TO, Vector2i(99, 19), Vector2i.LEFT, people[0])
	var cold_diagnostic: Dictionary = {}
	if is_instance_valid(lab._cold_replay_lab):
		var cold: TerrainLab = lab._cold_replay_lab
		var cold_receipt: Dictionary = RegionSaveSlot.validate_settlement(cold.terrain.site, target)
		if not _must(cold_receipt.ok and not cold_receipt.legacy, "Original retained cold Lab lost its real initialization receipt"): return false
		var action_step: float = TerrainLab.EXCHANGE_ACTION_STEP if cold.exchange_enabled else TerrainLab.ACTION_STEP
		var game_per_step: float = Runtime.game_seconds(action_step,0.0)*cold.simulation_speed
		cold_diagnostic = {"original_cold_last_GAME":cold_receipt.last,"remaining_GAME":cold_receipt.pending,"completed_original_GAME":float(cold_receipt.last)-initial_game,"peaceful_GAME_per_original_step":game_per_step,"completed_fixed_steps_from_receipt":roundi((float(cold_receipt.last)-initial_game)/game_per_step),"required_steps_from_original_debt":ceili(float(debt.pending)/game_per_step)}
	print("SITE_SHIP_EDGE_PENDING_FIRST: " + str({"ok":prepared.ok,"code":prepared.get("code",""),"target":target,"pending_result_GAME":prepared.get("pending",0.0),"cold":cold_diagnostic}))
	if not _complete_original_pending(prepared, true): return false
	var token := str(controller.ship_journey_status().token)
	if not _must(controller.cancel_ship_journey().ok, "Original zero-distance return preparation rejected"): return false
	if not _step(0.05): return false
	return _must(not controller.ship_journey_active() and controller.region_slot.commit_ship_transfer(token, lab.terrain).code == "CANCELLED", "Zero-distance original cancellation remained replayable")

func _bad_live_generation_recovery() -> bool:
	# Same real live owner and original token: no alternate Slot/cold owner.
	if not _must(controller._checkpoint_ship_journey().ok, "Original live recovery baseline checkpoint rejected"): return false
	var slot: RegionSaveSlot = controller.region_slot
	var status: Dictionary = controller.ship_journey_status()
	var token: String = str(status.token)
	var path: String = slot.site_path(FROM)
	var original_file: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var original_control: Dictionary = slot.control
	var original_marker: Dictionary = slot._marker
	var control_bytes: PackedByteArray = var_to_bytes(original_control)
	var marker_bytes: PackedByteArray = var_to_bytes(original_marker)
	var original_scope: String = slot._control_scope
	var source_bytes: PackedByteArray = var_to_bytes(lab.terrain.site)
	var journey_bytes: PackedByteArray = var_to_bytes(controller._ship_journey)
	var prepared_bytes: PackedByteArray = var_to_bytes(slot._prepared)
	var fingerprint: String = lab.terrain.fingerprint()
	if not _must(float(slot.control.logical_game_seconds) > 0.0 and not original_file.is_empty()
		and path.begins_with(slot.folder.path_join("generations")), "Recovery fixture lacked a real selected generation and positive original GAME"): return false
	var corrupted: PackedByteArray = original_file.duplicate()
	corrupted.append(32) # Valid JSON whitespace, but the selected commit SHA is wrong.
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not _must(file != null, "Test-only selected generation could not be opened"): return false
	file.store_buffer(corrupted)
	file.close()
	var query: Dictionary = slot.ship_transfer_status(token)
	var checkpoint: Dictionary = slot.checkpoint_ship_transfer(token, lab.terrain, float(status.elapsed_action_seconds), str(status.phase), float(status.return_elapsed_action_seconds))
	var preserved: bool = (is_same(slot.control, original_control) and is_same(slot._marker, original_marker)
		and var_to_bytes(slot.control) == control_bytes and var_to_bytes(slot._marker) == marker_bytes
		and slot._control_scope == original_scope and var_to_bytes(slot._prepared) == prepared_bytes
		and var_to_bytes(lab.terrain.site) == source_bytes and var_to_bytes(controller._ship_journey) == journey_bytes
		and lab.terrain.fingerprint() == fingerprint)
	# Restore exact bytes before asserting the intentional rejection, including
	# FAIL paths; this test cannot leave the live test-world generation corrupted.
	file = FileAccess.open(path, FileAccess.WRITE)
	if not _must(file != null, "Test-only generation restoration could not be opened"): return false
	file.store_buffer(original_file)
	file.close()
	if not _must(FileAccess.get_file_as_bytes(path) == original_file, "Test-only generation bytes were not restored exactly"): return false
	if not _must(not query.ok and query.code == "CORRUPT_SAVE" and not checkpoint.ok and checkpoint.code == "CORRUPT_SAVE"
		and preserved, "Bad selected generation reset live control/job/source or fell back to an older generation"): return false
	var resumed: Dictionary = slot.ship_transfer_status(token)
	var recovery_checks: Dictionary = {
		"resumed_ok": bool(resumed.get("ok", false)),
		"token_exact": str(resumed.get("token", "")) == token,
		"phase_exact": str(resumed.get("phase", "")) == str(status.phase),
		"elapsed_exact": float(resumed.get("elapsed_action_seconds", -1.0)) == float(status.elapsed_action_seconds),
		"elapsed_same_json": _same_json(resumed.get("elapsed_action_seconds"), status.elapsed_action_seconds),
		"return_required_same_json": _same_json(resumed.get("return_required_action_seconds"), status.return_required_action_seconds),
		"return_elapsed_same_json": _same_json(resumed.get("return_elapsed_action_seconds"), status.return_elapsed_action_seconds),
		"control_bytes_exact": var_to_bytes(slot.control) == control_bytes,
		"control_same_json": _same_json(slot.control, original_control),
		"clock_exact": float(slot.control.logical_game_seconds) == float(original_control.logical_game_seconds),
		"clock_same_json": _same_json(slot.control.logical_game_seconds, original_control.logical_game_seconds),
		"source_bytes_exact": var_to_bytes(lab.terrain.site) == source_bytes,
		"journey_bytes_exact": var_to_bytes(controller._ship_journey) == journey_bytes,
		"prepared_bytes_exact": var_to_bytes(slot._prepared) == prepared_bytes,
		"generation_file_exact": FileAccess.get_file_as_bytes(path) == original_file,
		"source_fingerprint_exact": lab.terrain.fingerprint() == fingerprint,
		"corrupt_rejection_original_refs_bytes": preserved,
	}
	var original_key_shapes: Array[Dictionary] = []
	var restored_key_shapes: Array[Dictionary] = []
	for key: Variant in original_control:
		original_key_shapes.append({"key":str(key), "key_type":typeof(key), "value_type":typeof(original_control[key])})
	for key: Variant in slot.control:
		restored_key_shapes.append({"key":str(key), "key_type":typeof(key), "value_type":typeof(slot.control[key])})
	var elapsed_before: float = float(status.elapsed_action_seconds)
	var elapsed_after: float = float(resumed.get("elapsed_action_seconds", -1.0))
	var elapsed_before_once: Variant = JSON.parse_string(JSON.stringify(elapsed_before, "", true, true))
	var elapsed_after_once: Variant = JSON.parse_string(JSON.stringify(elapsed_after, "", true, true))
	var numeric_diagnostic: Dictionary = {
		"control_before": JSON.stringify(original_control, "", true, true),
		"control_after": JSON.stringify(slot.control, "", true, true),
		"control_before_raw_hex": control_bytes.hex_encode(),
		"control_after_raw_hex": var_to_bytes(slot.control).hex_encode(),
		"control_before_keys": original_key_shapes,
		"control_after_keys": restored_key_shapes,
		"elapsed_before": JSON.stringify(elapsed_before, "", true, true),
		"elapsed_after": JSON.stringify(elapsed_after, "", true, true),
		"elapsed_delta": JSON.stringify(elapsed_after - elapsed_before, "", true, true),
		"elapsed_before_binary64_le": PackedFloat64Array([elapsed_before]).to_byte_array().hex_encode(),
		"elapsed_after_binary64_le": PackedFloat64Array([elapsed_after]).to_byte_array().hex_encode(),
		"elapsed_before_second_parse_stable": elapsed_before_once == JSON.parse_string(JSON.stringify(elapsed_before_once, "", true, true)),
		"elapsed_after_second_parse_stable": elapsed_after_once == JSON.parse_string(JSON.stringify(elapsed_after_once, "", true, true)),
		"clock_delta": JSON.stringify(float(slot.control.logical_game_seconds) - float(original_control.logical_game_seconds), "", true, true),
		"before_marker_generation": original_marker.get("generation"),
		"after_marker_generation": slot._marker.get("generation"),
	}
	print("SITE_SHIP_EDGE_RECOVERY_CHECKS: " + str(recovery_checks))
	print("SITE_SHIP_EDGE_RECOVERY_NUMERIC: " + str(numeric_diagnostic))
	if not _must(resumed.ok and str(resumed.token) == token and float(resumed.elapsed_action_seconds) == float(status.elapsed_action_seconds)
		and str(resumed.phase) == str(status.phase) and _same_json(slot.control, original_control)
		and float(slot.control.logical_game_seconds) == float(original_control.logical_game_seconds) and var_to_bytes(lab.terrain.site) == source_bytes,
		"Exact-file restoration could not resume the same token without replaying GAME/food"): return false
	var continued: Dictionary = slot.checkpoint_ship_transfer(token, lab.terrain, float(status.elapsed_action_seconds), str(status.phase), float(status.return_elapsed_action_seconds))
	# Region R1: a checkpoint publishes a new generation, and the active mode and
	# its activation receipt record that generation. Everything else in control
	# (clock, fire journal, journey, registry) must stay exactly the same.
	return _must(continued.ok and _same_json(_without_activation_generation(slot.control), _without_activation_generation(original_control))
		and float(slot.control.logical_game_seconds) == float(original_control.logical_game_seconds) and var_to_bytes(lab.terrain.site) == source_bytes
		and var_to_bytes(controller._ship_journey) == journey_bytes,
		"Recovered original token could not checkpoint without replaying original food/history/ACTION")

func _without_activation_generation(control: Dictionary) -> Dictionary:
	var copy: Dictionary = control.duplicate(true)
	for mode: Variant in copy.get("region_gameplay", {}).get("modes", {}).values():
		if not mode is Dictionary: continue
		mode.erase("generation")
		if mode.get("activation") is Dictionary: mode.activation.erase("generation")
	return copy

func _sweep_and_return() -> bool:
	if not _capture_journey(): return false
	var boats: Array[String] = [boat_id]
	var began: Dictionary = controller.begin_ship_journey(boats, TO, Vector2i(99, 19), Vector2i.LEFT, people[0])
	# A cancelled private candidate did not publish the visited cold Site.
	# The next request must settle it through the same original callback again.
	if not _complete_original_pending(began): return false
	if not _step(0.35): return false
	var status: Dictionary = controller.ship_journey_status()
	var boat: Dictionary = controller.vehicles.records()[boat_id]
	var claims: Dictionary = controller.ship_journey_claims(boat)
	var fraction := float(status.elapsed_action_seconds) / float(status.seconds)
	var position := Vector2(6, 19) + Vector2(-7, 0) * fraction
	if not _must(fraction > 0.0 and fraction < 1.0 and not claims.is_empty(), "Original fractional hull motion did not retain partial source claims"): return false
	for local: Vector2 in [Vector2(0, 0), Vector2(2, 0), Vector2(0, 6), Vector2(2, 6)]:
		var point := position + Vector2(0, -1) * local.x + Vector2(-1, 0) * local.y
		for cell: Vector2i in [Vector2i(floori(point.x), floori(point.y)), Vector2i(ceili(point.x), ceili(point.y))]:
			if lab.terrain.contains(cell) and not _must(claims.has(cell), "Original partial sweep omitted a continuous outer hull corner"): return false
	if not _bad_live_generation_recovery(): return false
	var token := str(status.token)
	if not _must(controller.cancel_ship_journey().ok, "Original equal-distance test return rejected"): return false
	for step in range(300):
		if not controller.ship_journey_active(): break
		if not _step(0.05): return false
	return _must(not controller.ship_journey_active() and controller._current_region_site() == FROM
		and controller.region_slot.commit_ship_transfer(token, lab.terrain).code == "CANCELLED"
		and controller.vehicles._claims(boat).has(Vector2i(6, 19)), "Actual partial hull return did not restore source claims or kept a replayable token")

func _run() -> void:
	deadline = Time.get_ticks_msec() + 240000
	if not _edge_fixture(): return
	if not _reject_edge(TO, Vector2i(99, 19), Vector2i.LEFT, "NO_ROUTE", "Interior departure"): return
	var boat: Dictionary = controller.vehicles.records()[boat_id]
	var sailing: Dictionary = controller.vehicles.ship_order(boat_id, "sail", Vector2i(6, 19), people[0], true)
	if not _must(sailing.ok, "Original fine sail to actual edge rejected: " + str(sailing)): return
	for step in range(40):
		if boat.move.is_empty() and boat.command.is_empty(): break
		controller.vehicles.update_ships(5.0)
	if not _must(boat.move.is_empty() and boat.command.is_empty() and lab.terrain.cell_from_index(int(boat.cell)) == Vector2i(6, 19), "Original river did not really reach the edge"): return
	if not _reject_edge(TO, Vector2i(90, 19), Vector2i.LEFT, "NO_ROUTE", "Interior arrival"): return
	if not _reject_edge(TO, Vector2i(97, 19), Vector2i.UP, "NO_ROUTE", "Wrong facing"): return
	if not _reject_edge(Vector2i(-1, 1), Vector2i(99, 19), Vector2i.LEFT, "NO_ROUTE", "Nonadjacent cardinal seam"): return
	if not _duty_rejections() or not _full_hull_unknown_route() or not _visited_pending() or not _sweep_and_return(): return
	print("SITE_SHIP_JOURNEY_EDGE_PASS:real_river_min2:real_off_duty_walk:live_and_saved_crew_guard:actual_exit_opposite_entry:wrong_facing:nonadjacent:unknown_outer_beam:original_high_bit_outer_edge:continuous_partial_sweep:original_visited_cold_PENDING:fixed_target:no_source_clock_replay:no_token_replay")
	quit(0)
