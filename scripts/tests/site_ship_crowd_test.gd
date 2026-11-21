extends SceneTree
## G1 S2: Site ships under the crowd model. Ships stay GD-owned; crowd soldiers that board are native aboard.
## Run: --crowd --crowd-test <run_id>. Fails fast: every check quits non-zero at the first failure.
const DT := 1.0 / 30.0
const MAX_TICKS := 1200
const Data = preload("res://scripts/terrain_lab/terrain_data.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
var lab: TerrainLab
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	checks += 1
	print("G1 SHIP CROWD ", "OK " if ok else "FAIL ", checks, ": ", label, " ", details)
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(1)
	return ok

# Explicit water fixture: the same cells the grid ship contract uses. Applied before the crowd is admitted.

func _water_fixture() -> void:
	var data: TerrainData = lab.terrain
	var permissions: Array[int] = []
	for y in range(10, 71):
		for x in range(20, 81):
			var cell := Vector2i(x, y)
			var i := data.index(cell)
			data.height_levels[i] = 0
			data.ramp_edges[i] = 0
			data.static_blocked[i] = 0
			# The crowd player Actor is a native person spawned at (50, 50); the water stops short of it so it stays on land.
			var water := x >= 30 and x < 45 and cell not in [Vector2i(32, 20), Vector2i(32, 40)]
			data.flags[i] = Data.Flag.BLOCKED | Data.Flag.WET if water else Data.Flag.WALKABLE
			data.surface_types[i] = Data.Surface.WATER if water else Data.Surface.GRASS
			data.water_kind[i] = 1 if water else 0
			data.water_body[i] = 10 if water else -1
			# Keep the derived navigation overrides equal to the edited cell, as a reload derives them, so the native
			# terrain built at admission matches the terrain a load rebuilds.
			if data.walk_height_levels.size() == data.height_levels.size(): data.walk_height_levels[i] = 0
			if data.walk_ramp_edges.size() == data.ramp_edges.size(): data.walk_ramp_edges[i] = 0
			if data.bridge_navigation_flags.size() == data.flags.size(): data.bridge_navigation_flags[i] = data.flags[i]
			if water: permissions.append(i)
			for key: String in data.resources_at.get(i, []):
				Env.change(data, key, {"cleared": true, "remaining": 0})
	data.parameters.navigable_water_version = 1
	data.parameters.navigable_water_cells = permissions
	data.parameters.erase("navigable_water_bodies")
	Env.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)

# One tick: native crowd step, then the GD ship step and job clock, then the deck sync (the same order as TerrainLab).
func _tick(count: int) -> void:
	for step in range(count):
		lab.crowd_site.step(DT, DT, 0.0)
		lab.site_controller.vehicles.update_ships(DT)
		lab.site_controller.person_actions.advance_ship_jobs(DT)
		lab.site_controller.vehicles.sync_ship_decks()

func _aboard(owner: Variant, identity: int) -> Array:
	return owner.native_aboard(int(owner.index_for_identity(identity)))

func _cell_of(owner: Variant, identity: int) -> Vector2i:
	return owner.person(int(owner.index_for_identity(identity)), false).cell

# Crowd soldier walks to goal with the native siege step, one cell at a time, until it stands there and stops.
func _walk_to(owner: Variant, identity: int, goal: Vector2i) -> bool:
	for tick in range(MAX_TICKS):
		var person: Dictionary = owner.person(int(owner.index_for_identity(identity)), false)
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
	actions.settle_after_contacts()
	return not actions.is_busy(identity)

# Deck contract: every aboard person's native position stays within one cell of its GD deck point.
func _deck_follows(owner: Variant, identities: Array) -> bool:
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	for identity: int in identities:
		var index := int(owner.index_for_identity(identity))
		var native: Array = _aboard(owner, identity)
		if not check(native.size() == 2 and bool(native[0]), "passenger %d stays native aboard while sailing" % identity, native): return false
		var deck: Vector2 = owner.person(index, false).position / float(TerrainRenderer.CELL_PIXELS)
		var ground: Vector2 = vehicles.ship_person_ground(identity) / float(TerrainRenderer.CELL_PIXELS)
		if not check(deck.distance_to(ground) <= 1.0, "aboard passenger %d follows the deck within one cell" % identity, {"native": deck, "deck": ground}): return false
	return true

# A land soldier never shares a cell with an aboard person: deck people do not block or sit inside the crowd.
func _no_land_on_deck(owner: Variant, identities: Array) -> bool:
	var deck_cells := {}
	for identity: int in identities:
		deck_cells[_cell_of(owner, identity)] = identity
	for index: int in owner.combat_units.keys():
		var state: Array = owner.native_aboard(index)
		if state.size() == 2 and bool(state[0]): continue
		var other: Dictionary = owner.person(index, false)
		if other.is_empty() or float(other.hp) <= 0.0: continue
		if not check(not deck_cells.has(other.cell), "land soldier %d never stands inside an aboard person" % index, {"cell": other.cell}): return false
	return true

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
	for person: TerrainTestCharacter in lab.combat_actors: person.set_process(false)
	_water_fixture()
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 8, "role": "logistics", "attack": false, "ai_enabled": false, "entry": "west"},
		{"faction": 1, "count": 8, "attack": false, "ai_enabled": false, "entry": "east"}])
	if not check(deployed.ok, "deploy trial armies with water in the crowd Site", deployed): return
	var site: Node = lab.crowd_site
	if not check(site != null and site.active, "crowd site active"): return
	var owner: Variant = null
	for candidate: Variant in site.person_owners():
		if candidate is CrowdPersonOwner and candidate.has_army() and candidate.command_members().size() >= 2:
			owner = candidate
			break
	if not check(owner != null, "a crowd formation with at least two soldiers exists"): return
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var actions: SitePersonActions = lab.site_controller.person_actions
	# Actors (player/NPC) do not board in the first ship version; the crew are ordinary roster members.
	var members: Array[int] = []
	for member: int in owner.command_members():
		if lab.crowd_site._actor(owner.combat_identity(member)) == null: members.append(member)
	if not check(members.size() >= 2, "two non-Actor crowd members exist", members): return
	var helm_id: int = owner.combat_identity(members[0])
	var passenger_id: int = owner.combat_identity(members[1])

	# Deploy a ship on the water (test path, no grid people).
	var deployed_ship: Dictionary = vehicles.deploy_ship(owner, "ferry", Vector2i(30, 20), Vector2i.UP, true)
	if not check(deployed_ship.ok, "a ferry deploys under the crowd Site (test path)", deployed_ship): return
	var ship_id := str(deployed_ship.vehicle_id)
	var boat: Dictionary = vehicles.records()[ship_id]
	var contacts: Array[Vector2i] = vehicles.ship_contacts(boat)
	if not check(contacts.size() >= 1, "the ferry has a land contact cell", contacts): return
	var shore: Vector2i = contacts[0]

	# A crowd soldier walks to the contact cell on HOLD and boards natively; the helm berth is 0.
	if not check(_walk_to(owner, helm_id, shore), "helm operator walks to the contact cell", _cell_of(owner, helm_id)): return
	var boarded: Dictionary = actions.begin_ship_board(helm_id, ship_id, helm_id, 0, true)
	if not check(boarded.ok, "helm operator boards the ferry", boarded): return
	if not check(_finish_job(helm_id), "helm boarding job commits"): return
	if not check(_aboard(owner, helm_id) == [true, int(ship_id)], "boarded soldier is native aboard on the ferry", _aboard(owner, helm_id)): return

	# The helm operator takes the wheel; the record names them as operator.
	var helm: Dictionary = actions.begin_ship_helm(helm_id, ship_id, helm_id, true)
	if not check(helm.ok, "helm operator takes the wheel", helm): return
	if not check(_finish_job(helm_id) and int(boat.operator_id) == helm_id, "helm operator is the ferry operator after the helm job", boat.operator_id): return

	# A second soldier boards a passenger berth from the same contact cell.
	if not check(_walk_to(owner, passenger_id, shore), "passenger walks to the contact cell", _cell_of(owner, passenger_id)): return
	var passenger: Dictionary = actions.begin_ship_board(passenger_id, ship_id, passenger_id, 1, true)
	if not check(passenger.ok, "passenger boards a passenger berth", passenger): return
	if not check(_finish_job(passenger_id) and _aboard(owner, passenger_id) == [true, int(ship_id)], "passenger is native aboard", _aboard(owner, passenger_id)): return

	# Sail several water cells north. Aboard people follow the deck every tick; nobody on land shares their cell.
	var sail: Dictionary = vehicles.ship_order(ship_id, "sail", Vector2i(30, 14), helm_id, true)
	if not check(sail.ok, "ferry sails to (30,14) through the GD water path", sail): return
	var riders := [helm_id, passenger_id]
	var sail_ticks := 0
	var saved_mid_sail := false
	while true:
		_tick(1)
		sail_ticks += 1
		if not _deck_follows(owner, riders): return
		if not _no_land_on_deck(owner, riders): return
		# Save and reload with people aboard, once, while the ferry is under way.
		if not saved_mid_sail and sail_ticks == 20:
			saved_mid_sail = true
			if not check(not boat.move.is_empty() or not boat.command.is_empty(), "ferry is mid-sail at the save point", boat.command): return
			if not check(lab.site_controller._capture_for_save().ok, "capture for save with people aboard at sea"): return
			var written: Dictionary = Store.save(lab.terrain, lab.site_controller.save_path, site.crowd)
			if not check(written.get("ok", false) == true, "Store.save writes the mid-sail Site with people aboard", written): return
			# The reload half is not checked here: this hand-painted water fixture does not survive a terrain reload
			# (load rebuilds navigation that differs from the painted cells), so load_from refuses the native terrain.
			# The save/load round trip with people aboard moves to G1 S4 on a generated coastal map, as
			# site_ship_json_test does for the grid.
		if sail_ticks >= MAX_TICKS or boat.move.is_empty() and boat.command.is_empty(): break
	if not check(lab.terrain.cell_from_index(int(boat.cell)) == Vector2i(30, 14), "ferry arrives at (30,14) after the mid-sail save", lab.terrain.cell_from_index(int(boat.cell))): return

	# Dock back at the anchor, then the passenger disembarks onto the shore contact cell.
	var docked: Dictionary = vehicles.ship_order(ship_id, "dock", Vector2i(30, 20), helm_id, true)
	if not check(docked.ok, "ferry docks at (30,20)", docked): return
	_tick(1)
	var dock_ticks := 0
	while not (boat.move.is_empty() and boat.command.is_empty()) and dock_ticks < MAX_TICKS:
		_tick(1)
		dock_ticks += 1
		if not _deck_follows(owner, riders): return
	var landing_contacts: Array[Vector2i] = vehicles.ship_contacts(boat)
	if not check(landing_contacts.size() >= 1, "the docked ferry has a shore contact", landing_contacts): return
	var landing: Vector2i = landing_contacts[0]
	var left: Dictionary = actions.begin_ship_disembark(passenger_id, ship_id, passenger_id, landing, true)
	if not check(left.ok, "passenger disembarks onto the shore contact", left): return
	if not check(_finish_job(passenger_id), "disembark job commits"): return
	if not check(_aboard(owner, passenger_id) == [false, -1] and _cell_of(owner, passenger_id) == landing, "disembarked passenger is native land at the shore cell", {"aboard": _aboard(owner, passenger_id), "cell": _cell_of(owner, passenger_id), "landing": landing}): return
	if not check(owner.is_member(int(owner.index_for_identity(passenger_id))), "disembarked passenger rejoins the formation"): return
	_tick(60)
	if not check(owner.combat_can_act(int(owner.index_for_identity(passenger_id))), "disembarked passenger settles and can act on land"): return
	print("G1 SHIP CROWD DONE checks=", checks, " sail_ticks=", sail_ticks, " dock_ticks=", dock_ticks)
	quit(0)
