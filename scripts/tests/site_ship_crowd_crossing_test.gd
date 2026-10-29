extends SceneTree
## G1 S4: a crowd soldier of team A crosses a linked ferry pair to the ferry of hostile team B.
## Natural coastal map as site_ship_json_test uses. The link and the crossing run through the original
## boarding-link flow (begin_boarding_link, then begin_boarding_cross), the same as the grid cross-link test.
## Run: --crowd --crowd-test <run_id>. Fails fast: every check quits non-zero at the first failure.
const DT := 1.0 / 30.0
const WALK_TICKS := 2400
const JOB_TICKS := 4000
const SEEDS := [17, 12345, 98761, 76404]
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
var lab: TerrainLab
var checks := 0
var owner_a: Variant = null
var owner_b: Variant = null
var members: Array[int] = []
var pair: Dictionary = {}
var settled: Array[Dictionary] = [] # Every result the per-tick settlement drained, in order.

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	checks += 1
	print("G1 S4 CROSSING ", "OK " if ok else "FAIL ", checks, ": ", label, " ", details)
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(1)
	return ok

# One tick: native crowd step, then the GD ship step and job clock, then the deck sync, then the settlement that
# commits held ship jobs (TerrainLab.gd:2133 calls settle_after_contacts each tick; ship_cross commits only there).
func _tick(count: int) -> void:
	for step in range(count):
		lab.crowd_site.step(DT, DT, 0.0)
		lab.site_controller.vehicles.update_ships(DT)
		lab.site_controller.person_actions.advance_ship_jobs(DT)
		lab.site_controller.vehicles.sync_ship_decks()
		for result: Dictionary in lab.site_controller.person_actions.settle_after_contacts():
			settled.append(result)

func _aboard(person_owner: Variant, identity: int) -> Array:
	return person_owner.native_aboard(int(person_owner.index_for_identity(identity)))

# Crowd soldier walks to goal with the native siege step until it stands there and stops.
func _walk_to(person_owner: Variant, identity: int, goal: Vector2i) -> bool:
	for tick in range(WALK_TICKS):
		var person: Dictionary = person_owner.person(int(person_owner.index_for_identity(identity)), false)
		if person.is_empty(): return false
		if person.cell == goal and not bool(person.moving): return true
		if not bool(person.moving): lab.crowd_site.siege_approach_step(identity, goal)
		_tick(1)
	return false

# Runs the committed GD action for this person until the job leaves the table, or the limit passes.
# True only when the job settled AND its final result is ok: a refusal (INTERRUPTED, STALE, ...) is a failure.
func _run_job(identity: int, limit: int) -> bool:
	var actions: SitePersonActions = lab.site_controller.person_actions
	var first := settled.size()
	for tick in range(limit):
		if not actions.is_busy(identity): break
		_tick(1)
	# A refusal settled for this executor (INTERRUPTED, STALE, ...) is a failure, not a commit.
	for index in range(first, settled.size()):
		if int(settled[index].get("executor_id", -1)) == identity and not bool(settled[index].get("ok", false)): return false
	return not actions.is_busy(identity)

# Boarding has a fixed clock (the same as the grid ship contract): advance it to the commit, then settle.
func _finish_job(identity: int) -> bool:
	var actions: SitePersonActions = lab.site_controller.person_actions
	if not actions.is_busy(identity): return true
	var job: Dictionary = actions._jobs[str(identity)]
	actions.advance_ship_jobs(maxf(0.01, float(job.duration) - float(job.elapsed) + 0.01))
	var drained: Array[Dictionary] = actions.settle_after_contacts()
	settled.append_array(drained)
	# settle_after_contacts returns (and drains) the settled results; a refusal for this executor is a failure.
	for result: Dictionary in drained:
		if int(result.get("executor_id", -1)) == identity and not bool(result.get("ok", false)): return false
	return not actions.is_busy(identity)

func _last_result() -> Dictionary:
	return settled.back() if not settled.is_empty() else {}

# Non-Actor roster members of a crowd owner. Actors (player/NPC) cannot board in the first ship version.
func _non_actor_members(candidate: Variant) -> Array[int]:
	var result: Array[int] = []
	var all: Array = candidate.command_members()
	for member: int in all:
		if lab.crowd_site._actor(candidate.combat_identity(member)) == null: result.append(member)
	return result

# Shore cells: walkable, not an Actor and not a living crowd soldier (a boarding contact must be free).
func _shore_cluster(data: TerrainData, shore: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var pending: Array[Vector2i] = [shore]
	var seen := {shore: true}
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_front()
		if lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell) or lab.crowd_site.reserves_cell(cell): continue
		result.append(cell)
		if result.size() == 4: return result
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if not seen.has(next) and data.can_step(cell, next) and next.distance_to(shore) <= 5.0:
				seen[next] = true
				pending.append(next)
	return []

# Two hulls side by side in navigable water, as the grid naval layout places them (second = anchor + 2 sideways).
func _find_linked_dock(data: TerrainData, near: Vector2i) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for y in range(4, data.size.y - 4):
		for x in range(4, data.size.x - 4):
			var anchor := Vector2i(x, y)
			var distance := float(anchor.distance_to(near))
			if distance >= best_distance or not data.can_navigate_water(anchor): continue
			for facing: Vector2i in TerrainData.DIRECTIONS:
				if not data.can_place_water_vehicle(Ship.footprint("ferry", anchor, facing)): continue
				if not data.can_place_water_vehicle(Ship.swept_footprint("ferry", anchor, facing, anchor + facing, facing)): continue
				var second := anchor + Vector2i(-facing.y, facing.x) * 2
				if not data.can_place_water_vehicle(Ship.footprint("ferry", second, facing)): continue
				for shore: Vector2i in Ship.boarding_cells("ferry", anchor, facing):
					if not data.is_walkable(shore) or absi(data.effective_height(shore) - data.effective_height(anchor)) > 1: continue
					var cells: Array[Vector2i] = _shore_cluster(data, shore)
					if cells.size() == 4:
						best = {"anchor": anchor, "facing": facing, "second": second, "shore": shore, "cells": cells}
						best_distance = distance
						break
	return best

# Generates a coastal Site per seed, binds it and deploys two hostile crowd teams. Team A owns a soldier
# with a free dock beside it; team B is the other side of the same deployment.
func _prepare() -> Dictionary:
	var last: Dictionary = {"ok": false, "message": "no seed produced two hostile crowd teams with a linked dock"}
	for seed_value: int in SEEDS:
		owner_a = null
		owner_b = null
		members = []
		pair = {}
		var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.COASTAL_CLIFF, seed_value, {"max_height": 1})
		Env.initialize(data, "crowd_crossing_%d" % seed_value)
		var bodies := {}
		for identity: int in data.water_body:
			if identity >= 0: bodies[identity] = true
		data.parameters.navigable_water_version = 1
		data.parameters.navigable_water_bodies = bodies.keys()
		lab.bind_terrain(data)
		lab.site_controller.set_process(false)
		lab.site_controller._auto_save_blocked = true
		var deployed: Dictionary = lab.deploy_trial_armies([
			{"faction": 0, "count": 8, "role": "logistics", "attack": false, "ai_enabled": false, "entry": "west"},
			{"faction": 1, "count": 8, "role": "logistics", "attack": false, "ai_enabled": false, "entry": "east"}])
		last = deployed
		if not deployed.ok or lab.crowd_site == null or not lab.crowd_site.active: continue
		for candidate: Variant in lab.crowd_site.person_owners():
			if not (candidate is CrowdPersonOwner) or not candidate.has_army(): continue
			var found: Array[int] = _non_actor_members(candidate)
			if found.size() < 1: continue
			owner_a = candidate
			members = found
			break
		if owner_a == null: continue
		for candidate: Variant in lab.crowd_site.person_owners():
			if not (candidate is CrowdPersonOwner) or not candidate.has_army(): continue
			if int(candidate.team_id) == int(owner_a.team_id): continue
			owner_b = candidate
			break
		if owner_b == null: continue
		var near: Vector2i = owner_a.person(members[0], false).cell
		var found_pair: Dictionary = _find_linked_dock(data, near)
		if found_pair.is_empty(): continue
		pair = found_pair
		return {"ok": true, "seed": seed_value}
	return last

func _run() -> void:
	create_timer(300.0).timeout.connect(func() -> void: quit(3))
	var args := OS.get_cmdline_user_args()
	if not check(args.has("--crowd") and args.has("--crowd-test"), "isolated crowd startup required"): return
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	var prepared: Dictionary = _prepare()
	if not check(bool(prepared.get("ok", false)), "generated coastal Site deploys two hostile crowd teams with a linked dock", prepared): return
	var site: Node = lab.crowd_site
	if not check(site != null and site.active, "crowd site active on the generated map"): return
	if not check(int(owner_a.team_id) != int(owner_b.team_id), "the two ferries belong to hostile teams", {"a": owner_a.team_id, "b": owner_b.team_id}): return
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var actions: SitePersonActions = lab.site_controller.person_actions
	var aboard: int = owner_a.combat_identity(members[0])

	# Two ferries: team A's hull at the anchor, hostile team B's hull on the second berth beside it.
	var made: Dictionary = vehicles.deploy_ship(owner_a, "ferry", pair.anchor, pair.facing, true)
	if not check(made.ok, "team A ferry deploys at the linked dock (test path)", made): return
	var hostile: Dictionary = vehicles.deploy_ship(owner_b, "ferry", pair.second, pair.facing, true)
	if not check(hostile.ok, "hostile team B ferry deploys beside it (test path)", hostile): return
	var a_id := str(made.vehicle_id)
	var b_id := str(hostile.vehicle_id)
	# Launched ships (Ships.make_record) carry a v1 afloat naval record; the test-only deploy path leaves it
	# for later lazy creation. The link contract needs it on both hulls, so give both the launch record.
	for identity: String in [a_id, b_id]:
		vehicles.records()[identity]["naval"] = {"version": 1, "hp": Ship.hull_hp("ferry"), "state": "afloat", "repair": {}}
	var boat_a: Dictionary = vehicles.records()[a_id]
	var contacts: Array[Vector2i] = vehicles.ship_contacts(boat_a)
	if not check(contacts.size() >= 1, "team A ferry has a land contact cell", contacts): return
	var shore: Vector2i = contacts[0]

	# Team A's soldier boards ferry A from the shore contact.
	if not check(_walk_to(owner_a, aboard, shore), "team A soldier walks to the contact cell"): return
	var boarded: Dictionary = actions.begin_ship_board(aboard, a_id, aboard, 0, true)
	if not check(boarded.ok, "team A soldier boards ferry A", boarded): return
	if not check(_finish_job(aboard), "boarding job on ferry A commits"): return
	if not check(_aboard(owner_a, aboard) == [true, int(a_id)], "soldier is native aboard ferry A before the link", _aboard(owner_a, aboard)): return

	# The link: an original boarding-link action, then the commit writes both hull records.
	var linking: Dictionary = actions.begin_boarding_link(aboard, a_id, b_id, aboard, true)
	if not check(linking.ok, "the boarding link action starts between the two hulls", linking): return
	if not check(_run_job(aboard, JOB_TICKS), "the boarding link action commits", _last_result()): return
	var records: Dictionary = vehicles.records()
	# Guarded reads: a hull record without a naval block is a failed check, not a crash.
	var naval_a: Dictionary = records.get(a_id, {}).get("naval", {})
	var naval_b: Dictionary = records.get(b_id, {}).get("naval", {})
	if not check(naval_a.has("boarding_link") and naval_b.has("boarding_link"), "both hull records carry the link after the commit", {"a": naval_a.keys(), "b": naval_b.keys()}): return

	# The crossing: the same soldier leaves ferry A for ferry B through the link-gated path.
	var crossing: Dictionary = actions.begin_boarding_cross(aboard, b_id, aboard, true)
	if not check(crossing.ok, "the link-gated crossing starts for the soldier", crossing): return
	var crossed_done: bool = _run_job(aboard, JOB_TICKS)
	if not check(crossed_done, "the crossing finishes", _last_result()): return

	# Afterwards: the native state and the GD row both name ferry B, the crosser stays one soldier of team A.
	var row_vehicle := str(vehicles.ship_person(aboard).row.get("embarked_vehicle_id", ""))
	if not check(row_vehicle == b_id, "the GD row names the new ferry after the crossing", {"row": row_vehicle, "expected": b_id}): return
	if not check(_aboard(owner_a, aboard) == [true, int(b_id)], "native aboard state reports the new ferry after the crossing", _aboard(owner_a, aboard)): return
	if not check(owner_a.is_member(int(owner_a.index_for_identity(aboard))), "the crosser is still a member of team A"): return
	if not check(vehicles.ship_person(aboard).row.get("ship_guest", false) == true, "the crosser is a guest on the hostile ferry", vehicles.ship_person(aboard).row.get("ship_guest", null)): return
	if not check(SiteVehicleTransport.ship_record_check(lab.terrain, lab.crowd_site.crowd).ok, "native aboard state matches the GD rows after the crossing"): return
	print("G1 S4 CROSSING DONE checks=", checks)
	quit(0)
