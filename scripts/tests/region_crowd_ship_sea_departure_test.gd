extends SceneTree
## SHIPSEA v4: a crowd team aboard its ferry leaves the Site by sea through the player entry
## (RegionTravelSite.request_departure). The vessel and every passenger travel in the party and leave the origin crowd;
## the party takes at least one sea map step; the origin crowd keeps advancing natively (watermark equals the world).
## Fixture sources (copied, not reinvented):
## - Region binding, crowd deploy, control switch, checkpoint, production travel panel and map steps:
##   region_crowd_journey_test.gd (open_fixed_world on the formal TerrainLab scene, then CrowdSite.deploy).
## - The map: the named straight coast of region_ship_coast_legal_named_genesis.gd (a manifest coast, so the origin
##   Site reloads in the travel panel; a hand-painted water fixture does not survive a reload). It pins the ferry
##   anchor (30,19) facing LEFT with its genuine shore contact (30,20).
## - Ticking, walking, boarding and the helm job: site_ship_crowd_test.gd helpers verbatim (_tick, _aboard, _cell_of,
##   _walk_to, _finish_job), in its order: a soldier walks to the contact, boards berth 0, takes the wheel; then each
##   further soldier walks to the same contact and boards a passenger berth. The team stands well inland (as the
##   passing tests' teams stand far from the dock), and the controlled captain boards last.
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_SEA_PASS on success; quit(1) on the first failure. Every phase has its own deadline.

const Grid = preload("res://scripts/region_lab/region_grid.gd")
const TravelPanelScript = preload("res://scripts/region_lab/region_travel_panel.gd")
const ShipCoastGenesis = preload("res://scripts/tests/region_ship_coast_legal_named_genesis.gd")
const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")

const DT := 1.0 / 30.0
const MAX_TICKS := 2400 # site_ship_crowd_test uses 1200 for a short walk; the inland team walks about 20 cells.
const SHIP_ANCHOR := Vector2i(30, 19)
const SHIP_FACING := Vector2i.LEFT
const SHIP_SHORE := Vector2i(30, 20)
const TEAM_SIZE := 3
const DECK_TICKS := 10
const SETTLE_TICKS := 2400
const TO := Vector2i(-1, 0)
const MAP_STEPS := 1
## Per-phase deadlines, each a fast fail with its own label (the 540 s in-file timer is the outer bound only).
const BOARD_DEADLINE_MS := 180000
const DEPART_DEADLINE_MS := 60000
const MAP_DEADLINE_MS := 60000

var out := ""
var manifest_path := ""
var checks := 0
var lab: TerrainLab
var controller: SiteController
var slot: RegionSaveSlot
var site_id := ""
var journey_slot: RegionSaveSlot
var journey_host: TerrainLab
var crowd_owner: Variant = null
var members: Array[int] = []
var captain := -1
var ship_id := ""

func _initialize() -> void:
	out = "res://.godot-temp/region_crowd_ship_sea/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	create_timer(540.0).timeout.connect(func() -> void: _fail("540-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_SEA_FAIL: ", message, " ", str(detail))
	push_error("REGION_CROWD_SEA_FAIL: " + message + " " + str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_SEA OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _phase(label: String, budget_ms: int) -> int:
	print("SHIPSEA PHASE: ", label)
	return Time.get_ticks_msec() + budget_ms

# region_crowd_journey_test.gd verbatim.
func _freeze(scene: TerrainLab) -> void:
	scene.set_process(false)
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	scene.site_controller.set_process(false)
	scene.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in scene.combat_actors: actor.set_process(false)
	for team: TerrainArmy in scene.combat_armies: team.set_process(false)

# region_crowd_journey_test.gd verbatim (ShipCoastGenesis.write calls it).
func _asset(name: String, bytes: PackedByteArray) -> Dictionary:
	var path := out.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return {"path": name, "sha256": FileAccess.get_sha256(path)}

# region_crowd_journey_test.gd verbatim.
func _side(count: int, faction: int) -> Dictionary:
	var parsed: Dictionary = lab._trial_side_settings({"friendly_count": count, "friendly_training": 0,
		"friendly_female_percent": 0, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
	if not _check(parsed.ok, "original side settings accepted", parsed): return {}
	var side: Dictionary = parsed.side
	side["faction"] = faction
	return side

func _mode() -> Dictionary:
	return slot.region_registry().modes.get(site_id, {})

# ---- site_ship_crowd_test.gd helpers, verbatim ----

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

# ---- diagnostics (read-only) ----

func _person_diag(identity: int, goal: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	var index: int = int(crowd_owner.index_for_identity(identity))
	var report := {"id": identity, "index": index}
	if index < 0: return report
	var person: Dictionary = crowd_owner.person(index, false)
	report["cell"] = person.get("cell")
	report["moving"] = person.get("moving")
	report["walking"] = crowd_owner.is_walking(index)
	report["can_act"] = crowd_owner.combat_can_act(index)
	report["aboard"] = _aboard(crowd_owner, identity)
	report["siege_state"] = str(crowd_owner.native_siege_state(index))
	report["busy"] = lab.site_controller.person_actions.is_busy(identity)
	if goal != Vector2i(-1, -1) and person.has("cell"):
		var ignored: Array = [identity]
		report["goal"] = goal
		report["goal_walkable"] = lab.terrain.is_walkable(goal)
		report["goal_occupied_native"] = lab.crowd_site.siege_people_block(goal, ignored)
		report["goal_occupied_gd"] = lab.site_controller.vehicles._siege_people_except(goal, {identity: true})
		report["free_path_cells"] = lab.terrain.path_between(person.cell, goal).size()
		var occupied := func(cell: Vector2i) -> bool: return lab.site_controller.vehicles._siege_people_except(cell, {identity: true})
		var edge_blocked := func(from: Vector2i, to: Vector2i) -> bool:
			return lab.site_controller.vehicles.blocks_person_step(identity, person.cell, from, to, goal)
		report["occupied_path_cells"] = lab.terrain.path_between(person.cell, goal, occupied, edge_blocked).size()
	return report

func _team_diag() -> Array:
	var rows: Array = []
	for identity: int in members: rows.append(_person_diag(identity))
	return rows

## Steps the crowd until no land member of the team is walking (site_controller's first-boarding rule needs the whole
## team stopped). Bounded by SETTLE_TICKS. Returns false if the team never settles.
func _settle_team() -> bool:
	for tick in range(SETTLE_TICKS):
		var walking := false
		for identity: int in members:
			var index: int = int(crowd_owner.index_for_identity(identity))
			if index >= 0 and not lab.site_controller.vehicles.is_embarked(identity) and bool(crowd_owner.is_walking(index)): walking = true
		if not walking: return true
		_tick(1)
	return false

## TEAM_SIZE land cells two apart on one inland row, each free of the original Actors and connected to the shore contact.
func _inland_cells(start: Vector2i) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	for row: int in range(0, 30):
		for column: int in range(0, 30):
			var cells: Array[Vector2i] = []
			var legal := true
			for k: int in range(TEAM_SIZE):
				var cell := start + Vector2i(column + k * 2, row)
				if not lab.terrain.contains(cell) or not lab.terrain.is_walkable(cell) or lab.character.occupies_cell(cell) \
						or lab.npc != null and lab.npc.occupies_cell(cell) or lab.terrain.path_between(cell, SHIP_SHORE).is_empty():
					legal = false
					break
				cells.append(cell)
			if legal: return cells
	return none

func _far_cells(start: Vector2i, count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row: int in range(0, 20):
		for column: int in range(0, 20):
			var cell := start - Vector2i(column, row)
			if not lab.terrain.contains(cell) or not lab.terrain.is_walkable(cell) or lab.character.occupies_cell(cell) or lab.npc != null and lab.npc.occupies_cell(cell): continue
			cells.append(cell)
			if cells.size() == count: return cells
	return cells

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "native startup and a fresh --crowd-test run id required"): return
	if not ShipCoastGenesis.write(self): return
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(packed != null, "formal TerrainLab scene exists"): return
	lab = packed.instantiate() as TerrainLab
	if not _check(lab != null, "formal TerrainLab instance exists"): return
	lab.pause_when_unfocused = false
	lab.movement_input_enabled = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	if not _check(lab.character != null, "formal scene has its player body"): return
	lab.character.set_process(false)
	controller = lab.site_controller
	if not _check(controller != null and lab.crowd_site != null and not lab.crowd_site.active and not controller.crowd_test_run_id.is_empty(),
		"formal scene has its inactive CrowdSite and isolated Controller"): return
	_freeze(lab)

	# Step 1 (region_crowd_journey_test): bind the Site to a Region save slot on the named coast, then deploy the crowd.
	var world_id := "r0_crowd_sea_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "Controller publishes and live-binds the pinned coast World", opened): return
	_freeze(lab)
	slot = controller.region_slot
	if not _check(slot != null and controller.region_slot == slot, "a Region save slot is bound to the Site"): return
	site_id = str(lab.terrain.site.id)
	var mode_gd := _mode()
	if not _check(str(mode_gd.get("mode", "")) == "live" and str(mode_gd.get("backend", "")) == "gd", "live GD mode before any crowd", mode_gd): return
	var hull: Array[Vector2i] = Ship.footprint("ferry", SHIP_ANCHOR, SHIP_FACING)
	if not _check(lab.terrain.can_place_water_vehicle(hull) and lab.terrain.is_walkable(SHIP_SHORE), "the bound coast has the pinned ferry water and its shore contact", {"anchor": SHIP_ANCHOR, "shore": SHIP_SHORE}): return
	var friendly_cells: Array[Vector2i] = _inland_cells(Vector2i(24, 40))
	if not _check(friendly_cells.size() == TEAM_SIZE, "an inland team row, free and connected to the shore contact, exists", friendly_cells): return
	var enemy_cells: Array[Vector2i] = _far_cells(Vector2i(96, 96), 2)
	if not _check(enemy_cells.size() == 2, "two far enemy cells exist", enemy_cells): return
	var sides: Array[Dictionary] = [_side(friendly_cells.size(), 0), _side(enemy_cells.size(), 1)]
	if not _check(sides[0].size() > 0 and sides[1].size() > 0, "both original sides exist"): return
	var formations: Array = [friendly_cells, enemy_cells]
	var entered: Dictionary = lab.crowd_site.deploy(sides, formations)
	if not _check(entered.get("ok", false) and lab.crowd_site.active, "the native crowd deploys on the bound Site", entered): return
	var native_mode := _mode()
	if not _check(str(native_mode.get("backend", "")) == "native", "the bound slot's live mode follows the crowd to native", native_mode): return

	var crowd: Variant = lab.crowd_site
	var roster: Dictionary = {}
	for candidate: Dictionary in crowd.rosters:
		if int(candidate.faction_id) == 0 and candidate.units.size() == TEAM_SIZE:
			roster = candidate
			break
	if not _check(not roster.is_empty(), "the friendly crowd team has its roster"): return
	var team_id: int = int(roster.team_id)
	for unit: Dictionary in roster.units: members.append(int(unit.person_id))
	crowd_owner = crowd.person_owner(members[0])
	if not _check(crowd_owner != null and crowd_owner is CrowdPersonOwner, "the crowd team has its person owner"): return
	for identity: int in members:
		if not _check(crowd.person_owner(identity) == crowd_owner and crowd._actor(identity) == null, "every team member is a non-Actor soldier of the same owner", identity): return
	# As region_crowd_journey_test: control moves to the friendly team's formal captain (departure_plan refuses actors).
	captain = int(roster.units[int(roster.formal_commander)].person_id)
	var switched: Dictionary = crowd.on_control_changed(lab.controlled_person_id(), captain)
	if not _check(switched.ok, "control moves to the friendly team's captain", switched): return
	lab.terrain.site["controlled_person_id"] = captain
	var controlled: int = lab.controlled_person_id()
	if not _check(controlled == captain and members.has(controlled), "the controlled captain is a member of the friendly crowd team", [controlled, captain]): return

	# Step 2 (site_ship_crowd_test order): the ferry, then one soldier at a time walks to the contact and boards.
	# The first boarder takes berth 0 and the wheel; the controlled captain boards last.
	var vehicles: SiteVehicleTransport = controller.vehicles
	var actions: SitePersonActions = controller.person_actions
	var deployed_ship: Dictionary = vehicles.deploy_ship(crowd_owner, "ferry", SHIP_ANCHOR, SHIP_FACING, true)
	if not _check(deployed_ship.ok, "a ferry deploys at the pinned coast anchor (test path)", deployed_ship): return
	ship_id = str(deployed_ship.vehicle_id)
	var boat: Dictionary = vehicles.records()[ship_id]
	var contacts: Array[Vector2i] = vehicles.ship_contacts(boat)
	if not _check(contacts.has(SHIP_SHORE), "the ferry has the pinned land contact cell", contacts): return
	var shore: Vector2i = SHIP_SHORE
	var order: Array[int] = []
	for identity: int in members:
		if identity != captain: order.append(identity)
	order.append(captain)
	var helm_id: int = order[0]
	var board_deadline := _phase("board the whole crowd team", BOARD_DEADLINE_MS)
	for berth: int in range(order.size()):
		var identity: int = order[berth]
		if not _check(Time.get_ticks_msec() <= board_deadline, "boarding finishes within the %d s phase deadline" % (BOARD_DEADLINE_MS / 1000), _team_diag()): return
		# The first boarding needs the whole team stopped (site_controller prepare_ship_supply); every later walk starts settled too.
		if not _check(_settle_team(), "the team settles before soldier %d walks" % identity, _team_diag()): return
		if not _check(_walk_to(crowd_owner, identity, shore), "crowd soldier %d walks to the contact cell" % identity, {"walker": _person_diag(identity, shore), "team": _team_diag()}): return
		var boarded: Dictionary = actions.begin_ship_board(identity, ship_id, identity, berth, true)
		if not _check(boarded.ok, "crowd soldier %d boards berth %d" % [identity, berth], {"refusal": boarded, "walker": _person_diag(identity, shore), "team": _team_diag()}): return
		if not _check(_finish_job(identity), "boarding job of soldier %d commits" % identity, _person_diag(identity)): return
		if not _check(_aboard(crowd_owner, identity) == [true, int(ship_id)], "boarded soldier %d is native aboard on the ferry" % identity, _aboard(crowd_owner, identity)): return
		if berth == 0:
			# site_ship_crowd_test: the first boarder takes the wheel; the record names them as operator.
			var helm: Dictionary = actions.begin_ship_helm(helm_id, ship_id, helm_id, true)
			if not _check(helm.ok, "helm operator takes the wheel", helm): return
			if not _check(_finish_job(helm_id) and int(boat.operator_id) == helm_id, "helm operator is the ferry operator after the helm job", boat.operator_id): return
		# Deck sync moves the aboard body onto the deck before the next soldier walks to the same contact.
		_tick(DECK_TICKS)
	for identity: int in members:
		if not _check(vehicles.is_embarked(identity) and not actions.is_busy(identity), "crowd soldier %d is aboard and idle before departure" % identity, _person_diag(identity)): return
	if not _check(vehicles.team_has_embarked(team_id), "the crowd team reports embarked", team_id): return
	# The controlled captain boards like any member and keeps host control aboard (crowd_person_owner.ship_ensure_aboard).
	if not _check(int(crowd.player_index) == int(crowd_owner.index_for_identity(captain)) and lab.controlled_person_id() == captain,
		"the controlled captain keeps host control aboard", {"player_index": crowd.player_index, "captain": _person_diag(captain)}): return
	if not _check(boat.move.is_empty() and boat.command.is_empty(), "the ferry is stopped at the anchor", {"move": boat.move, "command": boat.command}): return

	# Step 3: combat refuses the sea departure before anything is released.
	var depart_deadline := _phase("sea departure", DEPART_DEADLINE_MS)
	lab.terrain.site["combat_left"] = 5.0
	var refused: Dictionary = RegionTravelSite.request_departure(controller)
	lab.terrain.site["combat_left"] = 0.0
	if not _check(not refused.get("ok", false) and str(refused.get("code", "")) == "IN_COMBAT", "a sea departure in combat refuses with IN_COMBAT", refused): return
	for identity: int in members:
		if not _check(crowd.person_owner(identity) != null and vehicles.is_embarked(identity), "a refused departure releases nobody", identity): return

	# Step 4: the whole aboard team leaves by sea through the player entry.
	var departed: Dictionary = RegionTravelSite.request_departure(controller)
	if not _check(departed.get("ok", false) == true, "the aboard team departs by sea through RegionTravelSite.request_departure", {"refusal": departed, "team": _team_diag()}): return
	if not _check(Time.get_ticks_msec() <= depart_deadline, "the departure finishes within the %d s phase deadline" % (DEPART_DEADLINE_MS / 1000)): return
	var status: Dictionary = slot.region_travel_status()
	if not _check(status.ok and status.pending and not str(status.get("token", "")).is_empty(), "the sea departure opens one pending travel journey", status): return
	var travelling: Dictionary = slot.region_travel_party()
	if not _check(travelling.ok, "the travelling party is readable from the slot", travelling): return
	if not _check(str(travelling.party.get("mode", "")) == "sea", "the travelling party is a sea party", travelling.party.get("mode")): return
	var census: Dictionary = RegionTravel.census(travelling.party)
	var expected_people: Array = []
	for identity: int in members: expected_people.append(identity)
	expected_people.sort()
	if not _check(census.people == expected_people, "the sea party carries every member of the team", {"party": census.people, "team": expected_people}): return
	if not _check(census.vehicles.size() == 1 and census.vehicles.has(ship_id), "the sea party carries the vessel", {"party": census.vehicles, "ship": ship_id}): return
	for army: Dictionary in travelling.party.content.get("armies", []):
		for row: Dictionary in army.get("units", []):
			if not members.has(int(row.person_id)): continue
			if not _check(str(row.get("embarked_vehicle_id", "")) == ship_id, "passenger %d travels aboard the vessel" % int(row.person_id), row.get("embarked_vehicle_id", null)): return
	for identity: int in members:
		if not _check(not crowd.contains_person(identity) and crowd.person_owner(identity) == null, "a departed passenger leaves the origin crowd", identity): return
	if not _check(lab.crowd_site.active, "the remaining crowd keeps the origin Site active after the departure"): return

	# Step 5 (region_crowd_journey_test): durable checkpoint, then the production travel panel reopens the journey.
	var checkpoint: Dictionary = slot.checkpoint_region_travel()
	if not _check(checkpoint.ok, "the sea journey is durably checkpointed before the map reopens", checkpoint): return
	var panel = TravelPanelScript.new()
	root.add_child(panel)
	panel.setup(panel)
	panel.set_process(false)
	var started: Dictionary = panel.start({"world_id": world_id, "slot_id": "main", "manifest": manifest_path})
	if not _check(started.get("ok", false) == true, "the production travel panel reopens the sea journey", started): return
	journey_slot = panel.slot
	journey_host = panel._original_adapter_host
	if not _check(journey_slot != null and journey_host != null, "the reopened journey has its slot and origin host"): return
	_freeze(journey_host)
	var origin_watermark_before: float = float(journey_host.fire_action_cursor)
	var world_action_before: float = float(journey_slot.control.fire_clock.action_seconds)

	# Step 6 (region_crowd_journey_test): at least one sea map step along an original route.
	var before: Dictionary = journey_slot.region_travel_status()
	var party: Dictionary = journey_slot.region_travel_party()
	var context: Dictionary = journey_slot.prepare_region_route_context(null, party.get("party", {}))
	if not _check(before.ok and party.ok and context.ok, "the sea journey has its party and navigation context", [before.get("code"), party.get("code"), context.get("code")]): return
	var search := RegionRoute.Search.new()
	search.source = journey_slot.source
	search.start_site = before.site
	search.start_component = int(before.component)
	search.goal_site = TO
	search.context = context.context
	var route: Dictionary = search.run()
	if not _check(route.ok, "the original route producer finds a sea leg to the neighbouring Site", {"route": route, "start": before.site, "component": before.get("component")}): return
	var planned: Dictionary = journey_slot.set_region_travel_plan(route.steps)
	if not _check(planned.ok, "the original slot admits the sea route", planned): return
	var moved := 0
	var attempts := 0
	var map_deadline := _phase("sea map steps", MAP_DEADLINE_MS)
	while moved < MAP_STEPS and attempts < 5000:
		if not _check(Time.get_ticks_msec() <= map_deadline, "sea map steps finish within the %d s phase deadline" % (MAP_DEADLINE_MS / 1000), {"moved": moved, "attempts": attempts}): return
		attempts += 1
		var advanced: Dictionary = journey_slot.advance_region_travel(1)
		if not _check(advanced.get("ok", false) == true, "a sea map step advances without refusal", advanced): return
		if bool(advanced.get("arrived", false)): break
		if float(advanced.get("advanced", 0.0)) > 0.0: moved += 1
	var after: Dictionary = journey_slot.region_travel_status()
	if not _check(moved >= MAP_STEPS, "at least one sea map step is taken by the travelling party", {"moved": moved, "attempts": attempts}): return
	var position_moved: bool = float(after.get("elapsed_game_seconds", 0.0)) > float(before.get("elapsed_game_seconds", 0.0)) \
		and (float(after.get("fraction", 0.0)) != float(before.get("fraction", 0.0)) or int(after.get("step_index", 0)) != int(before.get("step_index", 0)) \
		or after.get("site") != before.get("site") or int(after.get("component", -1)) != int(before.get("component", -1)) 		or int(after.get("sea_action_index", 0)) != int(before.get("sea_action_index", 0)) 		or float(after.get("sea_action_elapsed", 0.0)) != float(before.get("sea_action_elapsed", 0.0)))
	# A sea status reports its progress as the ship ACTION cursor (region_sea_travel_status), not a land fraction.
	if not _check(position_moved, "the sea position advances across the map steps", {"plan_mode": after.get("plan", {}).get("mode", "land"),
		"step": [before.get("step_index"), after.get("step_index")], "fraction": [before.get("fraction"), after.get("fraction")],
		"sea_action": [before.get("sea_action_index"), after.get("sea_action_index"), before.get("sea_action_elapsed"), after.get("sea_action_elapsed")],
		"elapsed": [before.get("elapsed_game_seconds"), after.get("elapsed_game_seconds")]}): return
	var still: Dictionary = journey_slot.region_travel_party()
	if not _check(still.ok and str(still.party.get("mode", "")) == "sea" and RegionTravel.census(still.party).vehicles.size() == 1 \
		and RegionTravel.census(still.party).people.size() == members.size(), "the vessel and every passenger are still in the travelling party after the map steps",
		RegionTravel.census(still.party) if still.ok else still): return
	# The origin Site's crowd advances natively while the party travels (region_crowd_offscreen_step_test (a)).
	var origin_watermark_after: float = float(journey_host.fire_action_cursor)
	var world_action_after: float = float(journey_slot.control.fire_clock.action_seconds)
	var origin_advanced: bool = journey_host.crowd_site != null and journey_host.crowd_site.active \
		and origin_watermark_after > origin_watermark_before and world_action_after > world_action_before \
		and absf(origin_watermark_after - world_action_after) <= 0.000001
	if not _check(origin_advanced, "the origin crowd advances natively across the sea map steps (watermark equals the world clock)",
		[origin_watermark_before, origin_watermark_after, world_action_before, world_action_after]): return
	for identity: int in members:
		if not _check(journey_host.crowd_site.person_owner(identity) == null, "a departed passenger is not in the reopened origin crowd", identity): return
	print("REGION_CROWD_SEA_PASS: ", checks, " checks; ", moved, " sea map step(s); the vessel and ", members.size(),
		" passengers left the origin crowd by sea through request_departure; origin crowd advanced natively (watermark = world)")
	quit(0)
