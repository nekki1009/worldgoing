extends SceneTree
## G1 S4: crowd ferry passengers survive a mid-sail save and reload on a generated coastal map.
## Uses the natural water and shore of TerrainGenerator (as site_ship_json_test does), not a painted fixture.
## Run: --crowd --crowd-test <run_id>. Fails fast: every check quits non-zero at the first failure.
const DT := 1.0 / 30.0
const WALK_TICKS := 2400
const SAIL_TICKS := 2400
const SAIL_RUN := 4
const SEEDS := [17, 12345, 98761, 76404]
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
var lab: TerrainLab
var checks := 0
var owner: Variant = null
var members: Array[int] = []
var dock: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	checks += 1
	print("G1 S4 RELOAD ", "OK " if ok else "FAIL ", checks, ": ", label, " ", details)
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(1)
	return ok

# One tick: native crowd step, then the GD ship step and job clock, then the deck sync (the same order as TerrainLab).
func _tick(count: int) -> void:
	for step in range(count):
		lab.crowd_site.step(DT, DT, 0.0)
		lab.site_controller.vehicles.update_ships(DT)
		lab.site_controller.person_actions.advance_ship_jobs(DT)
		lab.site_controller.vehicles.sync_ship_decks()

func _aboard(person_owner: Variant, identity: int) -> Array:
	return person_owner.native_aboard(int(person_owner.index_for_identity(identity)))

func _cell_of(person_owner: Variant, identity: int) -> Vector2i:
	return person_owner.person(int(person_owner.index_for_identity(identity)), false).cell

# Crowd soldier walks to goal with the native siege step, one cell at a time, until it stands there and stops.
func _walk_to(person_owner: Variant, identity: int, goal: Vector2i) -> bool:
	for tick in range(WALK_TICKS):
		var person: Dictionary = person_owner.person(int(person_owner.index_for_identity(identity)), false)
		if person.is_empty(): return false
		if person.cell == goal and not bool(person.moving): return true
		if not bool(person.moving): lab.crowd_site.siege_approach_step(identity, goal)
		_tick(1)
	return false

# Runs the committed GD ship job for this person to completion (same clock as the grid ship contract).
func _finish_job(identity: int) -> bool:
	var actions: SitePersonActions = lab.site_controller.person_actions
	if not actions.is_busy(identity): return true
	var job: Dictionary = actions._jobs[str(identity)]
	actions.advance_ship_jobs(maxf(0.01, float(job.duration) - float(job.elapsed) + 0.01))
	var settled: Array[Dictionary] = actions.settle_after_contacts()
	# settle_after_contacts returns (and drains) the settled results; a refusal (INTERRUPTED, STALE, ...)
	# for this executor is a failure, not a commit.
	for result: Dictionary in settled:
		if int(result.get("executor_id", -1)) == identity and not bool(result.get("ok", false)): return false
	return not actions.is_busy(identity)

# Deck contract: every aboard person's native position stays within one cell of its GD deck point.
func _deck_follows(person_owner: Variant, identities: Array) -> bool:
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	for identity: int in identities:
		var index := int(person_owner.index_for_identity(identity))
		var native: Array = _aboard(person_owner, identity)
		if not check(native.size() == 2 and bool(native[0]), "passenger %d stays native aboard while sailing" % identity, native): return false
		var deck: Vector2 = person_owner.person(index, false).position / float(TerrainRenderer.CELL_PIXELS)
		var ground: Vector2 = vehicles.ship_person_ground(identity) / float(TerrainRenderer.CELL_PIXELS)
		if not check(deck.distance_to(ground) <= 1.0, "aboard passenger %d follows the deck within one cell" % identity, {"native": deck, "deck": ground}): return false
	return true

# A land soldier never shares a cell with an aboard person: deck people do not block or sit inside the crowd.
func _no_land_on_deck(person_owner: Variant, identities: Array) -> bool:
	var deck_cells := {}
	for identity: int in identities:
		deck_cells[_cell_of(person_owner, identity)] = identity
	for index: int in person_owner.combat_units.keys():
		var state: Array = person_owner.native_aboard(index)
		if state.size() == 2 and bool(state[0]): continue
		var other: Dictionary = person_owner.person(index, false)
		if other.is_empty() or float(other.hp) <= 0.0: continue
		if not check(not deck_cells.has(other.cell), "land soldier %d never stands inside an aboard person" % index, {"cell": other.cell}): return false
	return true

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

# The natural dock nearest to near: a water anchor that fits, with a free four-cell shore cluster.
func _find_dock(data: TerrainData, near: Vector2i) -> Dictionary:
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
				# The sail run is checked before anyone walks: at least SAIL_RUN straight cells ahead or reversed.
				var ahead := _run_length(data, anchor, facing, facing)
				var reverse := _run_length(data, anchor, facing, -facing)
				var direction := facing if ahead >= reverse else -facing
				var run := maxi(ahead, reverse)
				if run < SAIL_RUN: continue
				for shore: Vector2i in Ship.boarding_cells("ferry", anchor, facing):
					if not data.is_walkable(shore) or absi(data.effective_height(shore) - data.effective_height(anchor)) > 1: continue
					var cells: Array[Vector2i] = _shore_cluster(data, shore)
					if cells.size() == 4:
						var target: Vector2i = anchor + direction * run
						best = {"anchor": anchor, "facing": facing, "shore": shore, "cells": cells, "sail_target": target}
						best_distance = distance
						break
	return best

# Longest straight run along direction from anchor (up to 6 cells) whose every swept step fits the ferry hull
# (the same swept-footprint test as site_ship_json_test _dock). The hull keeps facing; only the travel direction changes.
func _run_length(data: TerrainData, anchor: Vector2i, facing: Vector2i, direction: Vector2i) -> int:
	var length := 0
	for step in range(1, 7):
		var from := anchor + direction * (step - 1)
		var to := anchor + direction * step
		if not data.can_navigate_water(to): break
		if not data.can_place_water_vehicle(Ship.swept_footprint("ferry", from, facing, to, facing)): break
		length = step
	return length

# Generates a coastal Site per seed, binds it, deploys two crowd teams and picks the dock nearest the first owner.
func _prepare() -> Dictionary:
	var last: Dictionary = {"ok": false, "message": "no seed produced a crowd deployment with a natural dock"}
	for seed_value: int in SEEDS:
		owner = null
		members = []
		dock = {}
		var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.COASTAL_CLIFF, seed_value, {"max_height": 1})
		Env.initialize(data, "crowd_reload_%d" % seed_value)
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
			{"faction": 1, "count": 8, "attack": false, "ai_enabled": false, "entry": "east"}])
		last = deployed
		if not deployed.ok or lab.crowd_site == null or not lab.crowd_site.active: continue
		for candidate: Variant in lab.crowd_site.person_owners():
			if not (candidate is CrowdPersonOwner) or not candidate.has_army(): continue
			var found: Array[int] = _non_actor_members(candidate)
			if found.size() < 2: continue
			owner = candidate
			members = found
			break
		if owner == null: continue
		var near: Vector2i = owner.person(members[0], false).cell
		var found_dock: Dictionary = _find_dock(data, near)
		if found_dock.is_empty(): continue
		dock = found_dock
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
	if not check(bool(prepared.get("ok", false)), "generated coastal Site deploys crowd teams with a natural dock", prepared): return
	for person: TerrainTestCharacter in lab.combat_actors: person.set_process(false)
	var site: Node = lab.crowd_site
	if not check(site != null and site.active, "crowd site active on the generated map"): return
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var actions: SitePersonActions = lab.site_controller.person_actions
	var helm_id: int = owner.combat_identity(members[0])
	var passenger_id: int = owner.combat_identity(members[1])

	# Deploy a ferry at the natural dock (test path, no grid people).
	var deployed_ship: Dictionary = vehicles.deploy_ship(owner, "ferry", dock.anchor, dock.facing, true)
	if not check(deployed_ship.ok, "a ferry deploys at the natural dock (test path)", deployed_ship): return
	var ship_id := str(deployed_ship.vehicle_id)
	var boat: Dictionary = vehicles.records()[ship_id]
	var contacts: Array[Vector2i] = vehicles.ship_contacts(boat)
	if not check(contacts.size() >= 1, "the ferry has a land contact cell", contacts): return
	var shore: Vector2i = contacts[0]

	# The helm walks to the contact cell and boards on the helm berth; then takes the wheel.
	if not check(_walk_to(owner, helm_id, shore), "helm operator walks to the contact cell", _cell_of(owner, helm_id)): return
	var boarded: Dictionary = actions.begin_ship_board(helm_id, ship_id, helm_id, 0, true)
	if not check(boarded.ok, "helm operator boards the ferry", boarded): return
	if not check(_finish_job(helm_id), "helm boarding job commits"): return
	if not check(_aboard(owner, helm_id) == [true, int(ship_id)], "boarded soldier is native aboard on the ferry", _aboard(owner, helm_id)): return
	var helm: Dictionary = actions.begin_ship_helm(helm_id, ship_id, helm_id, true)
	if not check(helm.ok, "helm operator takes the wheel", helm): return
	if not check(_finish_job(helm_id) and int(boat.operator_id) == helm_id, "helm operator is the ferry operator after the helm job", boat.operator_id): return

	# A second soldier boards a passenger berth from the same contact cell.
	if not check(_walk_to(owner, passenger_id, shore), "passenger walks to the contact cell", _cell_of(owner, passenger_id)): return
	var passenger: Dictionary = actions.begin_ship_board(passenger_id, ship_id, passenger_id, 1, true)
	if not check(passenger.ok, "passenger boards a passenger berth", passenger): return
	if not check(_finish_job(passenger_id) and _aboard(owner, passenger_id) == [true, int(ship_id)], "passenger is native aboard", _aboard(owner, passenger_id)): return

	# Sail a straight run of water. Aboard people follow the deck every tick; nobody on land shares their cell.
	var target: Vector2i = dock.sail_target
	if not check(lab.terrain.can_navigate_water(target), "the dock has a sailable run of water (checked before walking)", dock): return
	var sail: Dictionary = vehicles.ship_order(ship_id, "sail", target, helm_id, true)
	if not check(sail.ok, "ferry sails along the water to the target cell", sail): return
	var riders: Array[int] = [helm_id, passenger_id]
	var sail_ticks := 0
	var saved_mid_sail := false
	while sail_ticks < SAIL_TICKS:
		_tick(1)
		sail_ticks += 1
		if not _deck_follows(owner, riders): return
		if not _no_land_on_deck(owner, riders): return
		# Save and reload with people aboard, once, while the ferry is under way.
		if not saved_mid_sail and sail_ticks == 20:
			saved_mid_sail = true
			if not check(not boat.move.is_empty() or not boat.command.is_empty(), "ferry is mid-sail at the save point", boat.command): return
			if not check(lab.site_controller._capture_for_save().ok, "capture for save with people aboard at sea"): return
			var native: Variant = lab.crowd_site.crowd
			var exposes_hash: bool = native.has_method("state_hash")
			var hash_before: int = int(native.state_hash()) if exposes_hash else 0
			var written: Dictionary = Store.save(lab.terrain, lab.site_controller.save_path, native)
			if not check(written.get("ok", false) == true, "Store.save writes the mid-sail Site with people aboard", written): return
			var loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
			if not check(loaded.get("ok", false) == true, "load_from restores the mid-sail Site with people aboard", loaded): return
			native = lab.crowd_site.crowd
			var hash_after: int = int(native.state_hash()) if exposes_hash else 0
			if exposes_hash and not check(hash_after == hash_before, "native state hash is unchanged by the save and load", {"before": hash_before, "after": hash_after}): return
			# Every reference below is re-fetched: the load binds a new terrain, crowd and records.
			owner = lab.crowd_site.person_owner(helm_id)
			if not check(owner != null, "the helm soldier keeps its crowd owner after the reload"): return
			vehicles = lab.site_controller.vehicles
			if not check(vehicles.records().has(ship_id), "the ferry record survives the reload"): return
			boat = vehicles.records()[ship_id]
			if not check(_aboard(owner, helm_id) == [true, int(ship_id)] and _aboard(owner, passenger_id) == [true, int(ship_id)], "both soldiers are native aboard the same ferry after the reload", {"helm": _aboard(owner, helm_id), "passenger": _aboard(owner, passenger_id)}): return
			if not check(int(boat.operator_id) == helm_id, "the helm operator survives the reload", boat.operator_id): return
			if not check(not boat.move.is_empty() or not boat.command.is_empty(), "the ferry still has its sail order after the reload", boat.command): return
			if not check(SiteVehicleTransport.ship_record_check(lab.terrain, lab.crowd_site.crowd).ok, "native aboard state matches the GD rows after the reload"): return
			if not _deck_follows(owner, riders): return
		if boat.move.is_empty() and boat.command.is_empty(): break
	if not check(saved_mid_sail and boat.move.is_empty() and boat.command.is_empty(), "the ferry settles after the mid-sail reload", {"sail_ticks": sail_ticks}): return
	if not check(int(boat.cell) == lab.terrain.index(target), "ferry arrives at the target after the mid-sail reload", {"cell": boat.cell, "target": lab.terrain.index(target)}): return

	# Dock back at the original anchor, then the passenger disembarks onto the shore contact cell.
	var docked: Dictionary = vehicles.ship_order(ship_id, "dock", dock.anchor, helm_id, true)
	if not check(docked.ok, "ferry docks back at the original anchor after the reload", docked): return
	_tick(1)
	var dock_ticks := 0
	while not (boat.move.is_empty() and boat.command.is_empty()) and dock_ticks < SAIL_TICKS:
		_tick(1)
		dock_ticks += 1
		if not _deck_follows(owner, riders): return
	if not check(boat.move.is_empty() and boat.command.is_empty(), "the docking step settles", {"dock_ticks": dock_ticks}): return
	var landing_contacts: Array[Vector2i] = vehicles.ship_contacts(boat)
	if not check(landing_contacts.size() >= 1, "the docked ferry has a shore contact after the reload", landing_contacts): return
	var landing: Vector2i = landing_contacts[0]
	var left: Dictionary = actions.begin_ship_disembark(passenger_id, ship_id, passenger_id, landing, true)
	if not check(left.ok, "passenger disembarks onto the shore contact after the reload", left): return
	if not check(_finish_job(passenger_id), "disembark job commits after the reload"): return
	if not check(_aboard(owner, passenger_id) == [false, -1] and _cell_of(owner, passenger_id) == landing, "disembarked passenger is native land at the shore cell", {"aboard": _aboard(owner, passenger_id), "cell": _cell_of(owner, passenger_id), "landing": landing}): return
	if not check(owner.is_member(int(owner.index_for_identity(passenger_id))), "disembarked passenger rejoins the formation"): return
	_tick(60)
	if not check(owner.combat_can_act(int(owner.index_for_identity(passenger_id))), "disembarked passenger settles and can act on land"): return
	print("G1 S4 RELOAD DONE checks=", checks, " sail_ticks=", sail_ticks, " dock_ticks=", dock_ticks)
	quit(0)
