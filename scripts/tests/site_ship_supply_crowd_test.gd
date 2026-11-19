extends SceneTree
## G3: crowd split-shore and ship supply (team_supply version 3) on a generated coastal map.
## A crowd soldier on the shore contact prepares ship supply and the team converts to version 3 at shore:<index>;
## stock moves to the ferry and back with the meal credit conserved; the people aboard eat from the ship stock;
## a mid-voyage save and load keeps every location and amount.
## Run: --crowd --crowd-test <run_id>. Fails fast: every check quits non-zero at the first failure.
const DT := 1.0 / 30.0
const WALK_TICKS := 2400
const SAIL_TICKS := 2400
const SAIL_RUN := 4
const SEEDS := [17, 12345, 98761, 76404]
const DAY_SECONDS := 86400.0
const SHORE_GRAIN := 12
const SHIP_GRAIN := 8
const BACK_GRAIN := 2
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
var lab: TerrainLab
var checks := 0
var owner: Variant = null
var members: Array[int] = []
var dock: Dictionary = {}
var walk_reason := ""
const INVALID := Vector2i(-1, -1)

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	checks += 1
	print("G3 SUPPLY ", "OK " if ok else "FAIL ", checks, ": ", label, " ", details)
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(1)
	return ok

# One tick: the same crowd and ship step as site_ship_crowd_reload_test (the verified walk and boarding path).
# The site clock and supply are advanced explicitly by the supply steps, so the sustain clock stays exact.
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
# On failure walk_reason says why: no person, the last refused approach step, and the timeout state.
func _walk_to(person_owner: Variant, identity: int, goal: Vector2i) -> bool:
	walk_reason = ""
	var index: int = int(person_owner.index_for_identity(identity))
	for tick in range(WALK_TICKS):
		var person: Dictionary = person_owner.person(index, false)
		if person.is_empty():
			walk_reason = "no crowd person for identity %d" % identity
			return false
		if person.cell == goal and not bool(person.moving): return true
		if not bool(person.moving) and not lab.crowd_site.siege_approach_step(identity, goal):
			walk_reason = "siege_approach_step refused from %s to %s; terrain route %d cells; can_act %s" % [person.cell, goal, lab.terrain.path_between(person.cell, goal).size(), person_owner.combat_can_act(index)]
		_tick(1)
	var final: Dictionary = person_owner.person(index, false)
	walk_reason = "timed out from %s to %s (moving %s); last refusal: %s" % [final.get("cell"), goal, final.get("moving"), walk_reason]
	return false

# The first contact cell this person can reach on land (the same cell counts as reached); INVALID when none.
func _reachable_contact(identity: int, contacts: Array[Vector2i]) -> Vector2i:
	var from: Vector2i = _cell_of(owner, identity)
	for contact: Vector2i in contacts:
		if from == contact or not lab.terrain.path_between(from, contact).is_empty(): return contact
	return INVALID

# Runs the committed GD ship job for this person to completion (same clock as the grid ship contract).
func _finish_job(identity: int) -> bool:
	var actions: SitePersonActions = lab.site_controller.person_actions
	if not actions.is_busy(identity): return true
	var job: Dictionary = actions._jobs[str(identity)]
	actions.advance_ship_jobs(maxf(0.01, float(job.duration) - float(job.elapsed) + 0.01))
	var settled: Array[Dictionary] = actions.settle_after_contacts()
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

# Longest straight run along direction from anchor (up to 6 cells) whose every swept step fits the ferry hull.
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
# Three non-Actor soldiers are needed: a helm, a passenger and a supplier who stays on the shore.
func _prepare() -> Dictionary:
	var last: Dictionary = {"ok": false, "message": "no seed produced a crowd deployment with a natural dock"}
	for seed_value: int in SEEDS:
		owner = null
		members = []
		dock = {}
		var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.COASTAL_CLIFF, seed_value, {"max_height": 1})
		Env.initialize(data, "crowd_supply_%d" % seed_value)
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
			if found.size() < 3: continue
			owner = candidate
			# Transfers require the team's eligible current commander as requester (grid _authorized), and an
			# operator cannot handle supply (_delivery_person_ready). So the commander is the passenger (index 1).
			var commander: int = int(candidate.current_commander)
			if found.has(commander):
				found.erase(commander)
				found.insert(1, commander)
			members = found
			break
		if owner == null: continue
		var near: Vector2i = owner.person(members[0], false).cell
		var found_dock: Dictionary = _find_dock(data, near)
		if found_dock.is_empty(): continue
		dock = found_dock
		return {"ok": true, "seed": seed_value}
	return last

# Food on a location: physical units plus opened meal credit.
func _location_food(entry: Dictionary, key: String) -> float:
	if not entry.locations.has(key): return 0.0
	var location: Dictionary = entry.locations[key]
	return float(Runtime.inventory_size(location.inventory)) + float(location.open_rations)

# Every location as sorted text rows; equal rows mean the same keys and the same amounts.
func _summary(entry: Dictionary) -> Array:
	var rows: Array = []
	for key: String in entry.locations:
		var location: Dictionary = entry.locations[key]
		rows.append("%s=%.6f/%.6f" % [key, float(Runtime.inventory_size(location.inventory)), float(location.open_rations)])
	rows.sort()
	return rows

# Sets the Site clock to the sustain clock exactly (a cohort may not lag or lead the Site clock).
func _sync_site_clock(at_seconds: float) -> void:
	var minutes := at_seconds / 60.0
	lab.terrain.site.minute = int(floor(minutes))
	lab.terrain.site.phase = minutes - floor(minutes)

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
	var controller: SiteController = lab.site_controller
	var vehicles: SiteVehicleTransport = controller.vehicles
	var actions: SitePersonActions = controller.person_actions
	var helm_id: int = owner.combat_identity(members[0])
	var passenger_id: int = owner.combat_identity(members[1])
	var supplier_id: int = owner.combat_identity(members[2])

	# Deploy a ferry at the natural dock (test path, no grid people).
	var deployed_ship: Dictionary = vehicles.deploy_ship(owner, "ferry", dock.anchor, dock.facing, true)
	if not check(deployed_ship.ok, "a ferry deploys at the natural dock (test path)", deployed_ship): return
	var ship_id := str(deployed_ship.vehicle_id)
	var boat: Dictionary = vehicles.records()[ship_id]
	var contacts: Array[Vector2i] = vehicles.ship_contacts(boat)
	if not check(contacts.size() >= 1, "the ferry has a land contact cell", contacts): return
	var shore: Vector2i = contacts[0]
	var shore_key := "shore:%d" % lab.terrain.index(shore)
	var ship_key := "vehicle:" + ship_id

	# Before the first boarding the team is on version 2 with the old shared stock. The helm's boarding commit then
	# converts that stock to version 3 at the boarding contact (commit_ship_person calls prepare_ship_supply).
	_sync_site_clock(60.0 * floorf(Runtime.now(lab.terrain)))
	var opted: Dictionary = controller.captivity_supply.enable_team(owner)
	if not check(opted.ok, "the crowd team opts into supply before its first boarding", opted): return
	var entry: Dictionary = controller._supply_entry(owner)
	if not check(int(entry.version) == 2 and not entry.has("locations"), "before the first boarding the team is on version 2 (no positional stock)", entry.get("version")): return
	entry["inventory"] = {"grain": SHORE_GRAIN}

	# The commander (the passenger) is the eligible commander before boarding; the helm is not the commander.
	var commander_before: int = owner.combat_identity(int(owner.current_commander))
	if not check(commander_before == passenger_id and owner.command_eligible(int(owner.current_commander)) and helm_id != passenger_id, "the passenger is the eligible commander before boarding", {"commander": commander_before, "passenger": passenger_id}): return

	# The helm boards and takes the wheel; a passenger boards from the same contact cell.
	if not check(_walk_to(owner, helm_id, shore), "helm operator walks to the contact cell", _cell_of(owner, helm_id)): return
	var boarded: Dictionary = actions.begin_ship_board(helm_id, ship_id, helm_id, 0, true)
	if not check(boarded.ok, "helm operator boards the ferry", boarded): return
	if not check(_finish_job(helm_id), "helm boarding job commits"): return
	var helm: Dictionary = actions.begin_ship_helm(helm_id, ship_id, helm_id, true)
	if not check(helm.ok, "helm operator takes the wheel", helm): return
	if not check(_finish_job(helm_id) and int(boat.operator_id) == helm_id, "helm operator is the ferry operator after the helm job", boat.operator_id): return
	entry = controller._supply_entry(owner)
	if not check(int(entry.version) == 3 and not entry.has("inventory") and not entry.sustain.has("open_rations"), "the first boarding converts the team to supply version 3", entry.get("version")): return
	if not check(entry.locations.has(shore_key) and entry.locations.keys().size() == 1, "the converted stock sits at the boarding contact shore location", entry.locations.keys()): return
	if not check(absf(Sustain.rations(entry.sustain, entry.locations) - float(SHORE_GRAIN)) < 0.000001, "the converted amount equals the pre-boarding stock", Sustain.rations(entry.sustain, entry.locations)): return
	var passenger_contacts: Array[Vector2i] = vehicles.ship_contacts(boat)
	var passenger_shore: Vector2i = _reachable_contact(passenger_id, passenger_contacts)
	if not check(passenger_shore != INVALID, "a contact cell is reachable for the passenger after the helm boards", {"from": _cell_of(owner, passenger_id), "contacts": passenger_contacts}): return
	if not check(_walk_to(owner, passenger_id, passenger_shore), "passenger walks to the contact cell", {"to": passenger_shore, "reason": walk_reason}): return
	var passenger: Dictionary = actions.begin_ship_board(passenger_id, ship_id, passenger_id, 1, true)
	if not check(passenger.ok, "passenger boards a passenger berth", passenger): return
	if not check(_finish_job(passenger_id) and _aboard(owner, passenger_id) == [true, int(ship_id)], "passenger is native aboard", _aboard(owner, passenger_id)): return
	# The commander left the formation to walk to the shore, so an acting commander took over (as on the grid).
	# Aboard counts as present: the formal commander resumes at the next native command settle (every 15 ticks).
	_tick(30)
	var commander_id: int = owner.combat_identity(int(owner.current_commander))
	if not check(commander_id == passenger_id and owner.command_eligible(int(owner.current_commander)), "the commander is aboard and eligible again (transfers are the commander's)", {"commander": commander_id, "passenger": passenger_id}): return

	# The supplier stands on the shore contact cell that holds the stock (not aboard); the team is stopped and the ferry is docked.
	if not check(_walk_to(owner, supplier_id, shore), "supplier walks to the stock's shore contact cell", {"to": shore, "reason": walk_reason}): return
	var prepared_supply: Dictionary = controller.prepare_ship_supply(owner, shore)
	if not check(prepared_supply.ok, "a crowd soldier on the shore contact keeps the converted supply (prepare on v3 is accepted)", prepared_supply): return
	entry = controller._supply_entry(owner)
	if not check(int(entry.version) == 3 and entry.locations.has(shore_key), "supply is still version 3 at the shore location after the supplier prepares", entry.get("version")): return
	if not check(absf(Sustain.rations(entry.sustain, entry.locations) - float(SHORE_GRAIN)) < 0.000001, "the shore location holds all the old stock", Sustain.rations(entry.sustain, entry.locations)): return

	# Transfer to the ferry and back: physical food and meal credit are conserved (only consumed rations leave).
	var before_total: float = Sustain.rations(entry.sustain, entry.locations)
	var to_ship: Dictionary = controller.transfer_ship_supply(owner, shore_key, ship_key, {"grain": SHIP_GRAIN}, 0.0, commander_id, true)
	if not check(to_ship.ok, "shore to ferry transfer succeeds for the soldier on the contact cell", to_ship): return
	entry = controller._supply_entry(owner)
	var after_to_ship: float = Sustain.rations(entry.sustain, entry.locations)
	if not check(absf(before_total - float(to_ship.get("consumed_rations", 0.0)) - after_to_ship) < 0.000001, "shore to ferry transfer conserves the food", {"before": before_total, "after": after_to_ship}): return
	if not check(entry.locations.has(ship_key) and Sustain.rations(entry.sustain, entry.locations) > 0.0, "the ferry location exists and holds the transferred food", entry.locations.keys()): return
	var back: Dictionary = controller.transfer_ship_supply(owner, ship_key, shore_key, {"grain": BACK_GRAIN}, 0.0, commander_id, true)
	if not check(back.ok, "ferry to shore transfer succeeds back on the contact cell", back): return
	entry = controller._supply_entry(owner)
	var after_back: float = Sustain.rations(entry.sustain, entry.locations)
	if not check(absf(after_to_ship - float(back.get("consumed_rations", 0.0)) - after_back) < 0.000001, "ferry to shore transfer conserves the food", {"before": after_to_ship, "after": after_back}): return

	# People aboard eat from the ship stock: a day of meals draws the ferry location down.
	var ship_before: float = _location_food(entry, ship_key)
	var at_before: float = float(entry.sustain.at)
	controller.advance_crowd_sustain(DAY_SECONDS)
	entry = controller._supply_entry(owner)
	_sync_site_clock(float(entry.sustain.at))
	var ship_after: float = _location_food(entry, ship_key)
	if not check(float(entry.sustain.at) > at_before and ship_after < ship_before - 0.000001, "people aboard eat from the ferry stock", {"before": ship_before, "after": ship_after}): return
	if not check(_aboard(owner, helm_id) == [true, int(ship_id)] and _aboard(owner, passenger_id) == [true, int(ship_id)], "the people who ate are still aboard the ferry", _aboard(owner, passenger_id)): return

	# Sail a straight run of water with the food aboard; save and reload mid-voyage.
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
		if not saved_mid_sail and sail_ticks == 20:
			saved_mid_sail = true
			if not check(not boat.move.is_empty() or not boat.command.is_empty(), "ferry is mid-sail at the save point", boat.command): return
			entry = controller._supply_entry(owner)
			var summary_before: Array = _summary(entry)
			var rations_before: float = Sustain.rations(entry.sustain, entry.locations)
			var ship_at_save: float = _location_food(entry, ship_key)
			if not check(ship_at_save > 0.0, "the ferry still holds food at the mid-voyage save", ship_at_save): return
			# The shore supplier still holds its arrived siege step, and a crowd Site is unsaveable while any
			# soldier holds one (gap G10). Release the held steps of every crowd soldier first.
			for step_owner: Variant in lab.crowd_site.person_owners():
				if not step_owner is CrowdPersonOwner: continue
				for member: int in step_owner.command_members(): step_owner.siege_cancel_step(member)
			_tick(5)
			var held_steps := 0
			for index in range(int(lab.crowd_site.crowd.soldier_count())):
				var held: PackedInt64Array = lab.crowd_site.crowd.controlled_step_state(index)
				if held.size() == 2 and int(held[0]) >= 3: held_steps += 1
			if not check(held_steps == 0, "no soldier holds a controlled step at the save point", held_steps): return
			if not check(controller._capture_for_save().ok, "capture for save with food and people aboard at sea"): return
			var native: Variant = lab.crowd_site.crowd
			var written: Dictionary = Store.save(lab.terrain, controller.save_path, native)
			if not check(written.get("ok", false) == true, "Store.save writes the mid-voyage Site with v3 food aboard", written): return
			var loaded: Dictionary = controller.load_from(controller.save_path)
			if not check(loaded.get("ok", false) == true, "load_from restores the mid-voyage Site with v3 food aboard", loaded): return
			# Every reference below is re-fetched: the load binds a new terrain, crowd and records.
			owner = lab.crowd_site.person_owner(helm_id)
			if not check(owner != null, "the helm soldier keeps its crowd owner after the reload"): return
			controller = lab.site_controller
			vehicles = controller.vehicles
			boat = vehicles.records()[ship_id]
			entry = controller._supply_entry(owner)
			if not check(int(entry.version) == 3, "the team is still on supply version 3 after the reload", entry.get("version")): return
			if not check(_summary(entry) == summary_before, "every supply location and amount survives the reload", {"before": summary_before, "after": _summary(entry)}): return
			if not check(absf(Sustain.rations(entry.sustain, entry.locations) - rations_before) < 0.000001, "meal credit survives the reload", Sustain.rations(entry.sustain, entry.locations)): return
			if not check(_aboard(owner, helm_id) == [true, int(ship_id)] and _aboard(owner, passenger_id) == [true, int(ship_id)], "both soldiers are native aboard the same ferry after the reload"): return
			if not check(int(boat.operator_id) == helm_id, "the helm operator survives the reload", boat.operator_id): return
			if not check(not boat.move.is_empty() or not boat.command.is_empty(), "the ferry still has its sail order after the reload", boat.command): return
			if not check(_deck_follows(owner, riders), "the deck still follows the riders after the reload"): return
		if boat.move.is_empty() and boat.command.is_empty(): break
	if not check(saved_mid_sail and boat.move.is_empty() and boat.command.is_empty(), "the ferry settles after the mid-voyage reload", {"sail_ticks": sail_ticks}): return
	entry = controller._supply_entry(owner)
	if not check(_location_food(entry, ship_key) > 0.0, "the ferry still holds food at its destination", _location_food(entry, ship_key)): return
	print("G3 SUPPLY DONE checks=", checks, " sail_ticks=", sail_ticks)
	quit(0)
