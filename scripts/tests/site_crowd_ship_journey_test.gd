extends SceneTree
## SHIPJ v1: crowd ship journey guards. A crowd team boards a ferry in peace; its passengers are read through the crowd
## records by team_has_embarked; the journey peace guard passes at peace and refuses CROWD_ACTIVE in combat; the crowd
## remains helper reads and clears the crowd record. Journey start itself (begin_ship_journey) needs a Region slot,
## which this fixture does not open, so the journey cases (depart, passenger in journey, save/load mid-journey) are
## NOT covered here.
## Run: --crowd --crowd-test <run_id>. Fails fast: every check quits non-zero at the first failure.
const DT := 1.0 / 30.0
const MAX_TICKS := 1200
const Data = preload("res://scripts/terrain_lab/terrain_data.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
var lab: TerrainLab
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	checks += 1
	print("SHIPJ CROWD ", "OK " if ok else "FAIL ", checks, ": ", label, " ", details)
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(1)
	return ok

# Same explicit water fixture as site_ship_crowd_test.gd (the crowd player Actor stays on land at (50, 50)).
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
			var water := x >= 30 and x < 45 and cell not in [Vector2i(32, 20), Vector2i(32, 40)]
			data.flags[i] = Data.Flag.BLOCKED | Data.Flag.WET if water else Data.Flag.WALKABLE
			data.surface_types[i] = Data.Surface.WATER if water else Data.Surface.GRASS
			data.water_kind[i] = 1 if water else 0
			data.water_body[i] = 10 if water else -1
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

func _walk_to(owner: Variant, identity: int, goal: Vector2i) -> bool:
	for tick in range(MAX_TICKS):
		var person: Dictionary = owner.person(int(owner.index_for_identity(identity)), false)
		if person.is_empty(): return false
		if person.cell == goal and not bool(person.moving): return true
		if not bool(person.moving): lab.crowd_site.siege_approach_step(identity, goal)
		_tick(1)
	return false

func _finish_job(identity: int) -> bool:
	var actions: SitePersonActions = lab.site_controller.person_actions
	if not actions.is_busy(identity): return true
	var job: Dictionary = actions._jobs[str(identity)]
	actions.advance_ship_jobs(maxf(0.01, float(job.duration) - float(job.elapsed) + 0.01))
	actions.settle_after_contacts()
	return not actions.is_busy(identity)

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
	var other: Variant = null
	for candidate: Variant in site.person_owners():
		if candidate is CrowdPersonOwner and int(candidate.team_id) != int(owner.team_id):
			other = candidate
			break
	if not check(other != null, "a second crowd team exists for the negative embarked check"): return
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var actions: SitePersonActions = lab.site_controller.person_actions
	var members: Array[int] = []
	for member: int in owner.command_members():
		if lab.crowd_site._actor(owner.combat_identity(member)) == null: members.append(member)
	if not check(members.size() >= 2, "two non-Actor crowd members exist", members): return
	var helm_id: int = owner.combat_identity(members[0])
	var passenger_id: int = owner.combat_identity(members[1])

	var deployed_ship: Dictionary = vehicles.deploy_ship(owner, "ferry", Vector2i(30, 20), Vector2i.UP, true)
	if not check(deployed_ship.ok, "a ferry deploys under the crowd Site (test path)", deployed_ship): return
	var ship_id := str(deployed_ship.vehicle_id)
	var boat: Dictionary = vehicles.records()[ship_id]
	var shore: Vector2i = vehicles.ship_contacts(boat)[0]

	# Helm and one passenger board the crowd ferry from the contact cell (whole-team rules are not exercised here).
	if not check(_walk_to(owner, helm_id, shore), "helm operator walks to the contact cell", _cell_of(owner, helm_id)): return
	if not check(actions.begin_ship_board(helm_id, ship_id, helm_id, 0, true).ok and _finish_job(helm_id), "helm operator boards the ferry"): return
	if not check(actions.begin_ship_helm(helm_id, ship_id, helm_id, true).ok and _finish_job(helm_id), "helm operator takes the wheel"): return
	if not check(_walk_to(owner, passenger_id, shore), "passenger walks to the contact cell", _cell_of(owner, passenger_id)): return
	if not check(actions.begin_ship_board(passenger_id, ship_id, passenger_id, 1, true).ok and _finish_job(passenger_id), "passenger boards a passenger berth"): return
	if not check(_aboard(owner, passenger_id) == [true, int(ship_id)], "passenger is native aboard", _aboard(owner, passenger_id)): return

	# Embarked passengers live in the crowd records: the crowd team reports embarked, another crowd team does not.
	if not check(vehicles.team_has_embarked(int(owner.team_id)), "crowd team with aboard passengers reports embarked", owner.team_id): return
	if not check(not vehicles.team_has_embarked(int(other.team_id)), "a crowd team without passengers reports not embarked", other.team_id): return

	# No journey has begun, so nobody is in a journey: the early refusal in ship_person_in_journey is unchanged.
	if not check(not lab.site_controller.ship_person_in_journey(passenger_id), "aboard crowd passenger is not in a journey before departure"): return

	# Save guard: the crowd boarding rows pass the position guard and the person-action guard at rest.
	var saved_guard: Dictionary = vehicles.boarding_save_guard()
	if not check(saved_guard.ok, "boarding save guard allows a settled crowd ferry", saved_guard): return

	# Journey peace guard: passes at peace with crowd passengers aboard, refuses CROWD_ACTIVE once the Site is in combat.
	var ship_ids: Array[String] = [ship_id]
	var peace: Dictionary = lab.site_controller._ship_journey_peace_guard(ship_ids, helm_id)
	if not check(peace.ok, "journey peace guard passes at peace with a crowd ferry", peace): return
	lab.terrain.site["combat_left"] = 5.0
	var fighting: Dictionary = lab.site_controller._ship_journey_peace_guard(ship_ids, helm_id)
	lab.terrain.site["combat_left"] = 0.0
	if not check(not fighting.ok and str(fighting.code) == "CROWD_ACTIVE", "journey peace guard refuses with CROWD_ACTIVE in combat", fighting): return

	# Crowd remains reference: the crowd record is read and cleared by clear_ship_remains_reference.
	var passenger_index := int(owner.index_for_identity(passenger_id))
	owner._cold_set(passenger_index, "remains_id", "shipj-remains")
	vehicles.clear_ship_remains_reference("shipj-remains")
	if not check(str(owner._cold_get(passenger_index, "remains_id", "")) == "", "crowd remains reference is cleared"): return

	# TODO (not covered): begin_ship_journey depart in peace, passenger in journey, and save/load mid-journey need an open
	# Region slot. begin_ship_journey returns NO_TARGET before its peace check when no slot is open.
	print("SHIPJ CROWD DONE checks=", checks)
	quit(0)
