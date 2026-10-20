extends "res://scripts/tests/site_boarding_cross_link_test.gd"
## B3R: a link-gated crossing completes atomically (body and ledger in one commit).
## Q2 A: cancel closes entries and lets the crossing finish, then clears the link.
## Sink: the link clears on both ends (no invalid, no ghost). Refusal releases the crosser only.

## Last result returned by settle_after_contacts(); the list is drained by that call, so _results is empty after it.
var last_b3: Dictionary = {}

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	if not _must(DisplayServer.get_name() == "headless", "B3R_CANONICAL_HEADLESS"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for owner: TerrainArmy in lab.combat_armies: owner.set_process(false)
	if not _fixture() or not _cases_b3r(): return
	print("SITE_BOARDING_B3R_PASS: " + get_script().resource_path)
	await _cleanup(0)

## Advances the existing ship clock in small steps until the crossing settles (bounded).
## Ship-path jobs complete in settle_after_contacts() (the tick that commits or releases), not in
## advance_ship_jobs(); the naval lifecycle test drives them the same way.
func _settle_b3(actions: Variant) -> bool:
	for step in range(800):
		if actions._jobs.is_empty(): return true
		actions.advance_ship_jobs(0.5)
		for result: Dictionary in actions.settle_after_contacts(): last_b3 = result
	return actions._jobs.is_empty()

## Actual state of the open crossing, for failure messages.
func _state_b3(actions: Variant) -> String:
	var job: Dictionary = actions._jobs.get(str(people[0]), {})
	if job.is_empty():
		return "no open job; last settled result " + str(last_b3)
	return "kind=" + str(job.kind) + " elapsed=" + str(job.elapsed) + " duration=" + str(job.duration) + " paused=" + str(job.paused) + " cancelled=" + str(job.cancelled) + " path=" + str(job.path.size())

## Both ends are linked with the crosser clear, in the given link state.
func _linked_clear_b3(live: Dictionary, state: String) -> bool:
	for identity: String in [boat_id, enemy_boat]:
		var link: Dictionary = live[identity].naval.get("boarding_link", {})
		if int(link.get("crosser_id", -1)) != 0 or str(link.get("state", "")) != state: return false
	return true

## Actual naval records of both hulls, for failure messages.
func _naval_b3(live: Dictionary) -> String:
	return "boat=" + str(live[boat_id].naval) + " enemy=" + str(live[enemy_boat].naval)

## Neither hull carries an original link record.
func _cleared_b3(live: Dictionary) -> bool:
	for identity: String in [boat_id, enemy_boat]:
		if live[identity].naval.has("boarding_link") or int(live[identity].naval.version) != 1: return false
	return true

func _cases_b3r() -> bool:
	var vehicles: Variant = lab.site_controller.vehicles
	var actions: Variant = lab.site_controller.person_actions
	var aboard: int = people[0]
	var live: Dictionary = _live_b3()
	if not _must(str(vehicles.ship_person(aboard).row.get("embarked_vehicle_id", "")) == boat_id, "B3R_PREMISE_EMBARKED"): return false

	# (a) cancel: no abort. The job stays, entries close, the cross finishes, the link clears.
	if not _must(_link_live_b3(), "B3R_PREMISE_LINK"): return false
	var began: Dictionary = actions.begin_boarding_cross(aboard, enemy_boat, aboard)
	if not _must(began.ok, "B3R_CANCEL_BEGIN: " + str(began)): return false
	actions.advance_ship_jobs(0.5)
	var cancelled: Dictionary = actions.cancel(aboard)
	if not _must(cancelled.ok and not actions._jobs.is_empty(), "B3R_CANCEL_KEEPS_CROSS: " + str(cancelled)): return false
	if not _must(str(live[boat_id].naval.boarding_link.state) == "closing" and int(live[boat_id].naval.boarding_link.crosser_id) == aboard, "B3R_CANCEL_CLOSES_ENTRIES"): return false
	if not _must(_settle_b3(actions), "B3R_CANCEL_SETTLES: " + _state_b3(actions)): return false
	var finished: Dictionary = last_b3
	if not _must(bool(finished.get("ok", false)) and bool(finished.get("link_released", false)), "B3R_CANCEL_RESULT: " + str(finished)): return false
	if not _must(str(vehicles.ship_for_person(aboard).id) == enemy_boat, "B3R_CANCEL_CROSS_COMPLETES: " + str(last_b3) + " on=" + str(vehicles.ship_for_person(aboard).id)): return false
	if not _must(_cleared_b3(live), "B3R_CANCEL_CLEARS_LINK_ON_EXIT: " + _naval_b3(live)): return false
	if not _must(vehicles.boarding_save_guard().ok, "B3R_SAVE_RELEASED_AFTER_CLEAR"): return false

	# Target changed during the crossing: the channel is no longer valid (B6, plan
	# output/project_command_center/evidence/CC-20261014-052/BOARDING_QUESTIONS_FOR_NEKKI.md line 24, Q3 A, and
	# BOARDING_LINK_PLAN.md line 86). The live, non-KO person is still on the supported source deck, so it
	# walks to a reachable berth there as a real paid leg, commits, and the link clears on both ends.
	# The body never teleports and is never returned to the target hull.
	if not _must(_link_live_b3(), "B3R_REFUSAL_LINK"): return false
	var back: Dictionary = actions.begin_boarding_cross(aboard, boat_id, aboard)
	if not _must(back.ok, "B3R_REFUSAL_BEGIN: " + str(back)): return false
	live[boat_id].revision += 1
	if not _must(_settle_b3(actions), "B3R_REFUSAL_SETTLES: " + _state_b3(actions)): return false
	var walked: Dictionary = last_b3
	if not _must(bool(walked.get("ok", false)) and bool(walked.get("link_released", false)), "B6_WALKOUT_RESULT: " + str(walked)): return false
	if not _must(str(vehicles.ship_for_person(aboard).id) == enemy_boat and _cleared_b3(live), "B6_WALKOUT_KEEPS_PERSON_AND_CLEARS_LINK: " + _naval_b3(live)): return false
	# The commit section below needs a live link again; re-linked through the same contract builder as above.
	if not _must(_link_live_b3(), "B6_RELINK_AFTER_WALKOUT"): return false

	# Commit: body moves, the ledger exit is written together, and the link stays connected.
	began = actions.begin_boarding_cross(aboard, boat_id, aboard)
	if not _must(began.ok, "B3R_COMMIT_BEGIN: " + str(began)): return false
	if not _must(_settle_b3(actions), "B3R_COMMIT_SETTLES: " + _state_b3(actions)): return false
	var committed: Dictionary = last_b3
	if not _must(bool(committed.get("ok", false)) and bool(committed.get("link_released", false)), "B3R_COMMIT_RESULT: " + str(committed) + " " + _naval_b3(live)): return false
	if not _must(str(vehicles.ship_for_person(aboard).id) == boat_id and _linked_clear_b3(live, "linked"), "B3R_COMMIT_MOVES_BODY_KEEPS_LINK"): return false

	# Sink: the peer sinks during the crossing. The link clears on both ends; the person stays on the source hull.
	# B6 (same plan lines as the refusal above): the surviving source deck still supports the person, so the
	# person walks to a reachable berth there as a real paid leg instead of stopping at the paid point.
	began = actions.begin_boarding_cross(aboard, enemy_boat, aboard)
	if not _must(began.ok, "B3R_SINK_BEGIN: " + str(began)): return false
	live[enemy_boat].naval.state = "wrecked"
	live[enemy_boat].naval.hp = 0.0
	if not _must(_settle_b3(actions), "B3R_SINK_SETTLES: " + _state_b3(actions)): return false
	var sunk: Dictionary = last_b3
	if not _must(bool(sunk.get("ok", false)) and bool(sunk.get("link_released", false)), "B6_SINK_WALKOUT_RESULT: " + str(sunk)): return false
	if not _must(_cleared_b3(live), "B3R_SINK_CLEARS_BOTH_ENDS"): return false
	return _must(str(vehicles.ship_for_person(aboard).id) == boat_id, "B3R_SINK_PERSON_STAYS")
