extends SceneTree
## SHIPUI v1: the player's real ship journey entry for a crowd team. The fixture is region_crowd_ship_sea_departure_test's
## (named coast bound through open_fixed_world, native crowd deploy, control to the team's captain, and the whole team boarded
## one by one with site_ship_crowd_test's helpers). Then, as site_ship_journey_test drives the grid journey: the helm sails
## the ferry to the outward edge, the formal vehicle UI selects the ferry and DepartShipJourney is pressed
## (SiteController.begin_ship_journey -> RegionSaveSlot.prepare_ship_transfer), and the shared step advances the journey
## until the arrival commit binds the destination. The passengers stay native aboard while sailing; at arrival they are
## released from the origin crowd with their vessel (site_person_release_aboard) and arrive with it.
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_SHIP_UI_PASS on success; quit(1) on the first failure. Every phase has its own deadline.

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
const SAIL_EDGE := Vector2i(3, 19)
const SAIL_TICKS := 3000
const SAIL_DEADLINE_MS := 120000
const ARRIVAL_ANCHOR := Vector2i(99, 19)
const ARRIVAL_DEADLINE_MS := 180000
const JOURNEY_STEPS := 4000

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
	out = "res://.godot-temp/region_crowd_ship_ui/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	create_timer(540.0).timeout.connect(func() -> void: _fail("540-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_SHIP_UI_FAIL: ", message, " ", str(detail))
	push_error("REGION_CROWD_SHIP_UI_FAIL: " + message + " " + str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_SHIP_UI OK ", checks, ": ", message)
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

## The journey projection and every _journey_can_advance input (site_controller.gd), read-only.
func _journey_diag() -> Dictionary:
	var report := {"status": controller.ship_journey_status(), "message": str(controller.message.text), "paused": bool(lab.terrain.site.get("paused", false)),
		"can_advance": controller._journey_can_advance(), "pending_operation": controller.region_operation_pending()}
	var boat: Dictionary = controller.vehicles.records().get(ship_id, {})
	if not boat.is_empty():
		report["afloat"] = SiteVehicleTransport.ship_afloat(boat)
		report["ship_job"] = controller.vehicles.ship_job(ship_id)
		report["driver_ready"] = controller.vehicles.ship_driver_ready(boat)
		report["crew"] = controller.vehicles.ship_crew_count(boat)
		report["operator"] = int(boat.get("operator_id", 0))
		var helm: Dictionary = controller.vehicles.ship_person(int(boat.get("operator_id", 0)))
		if not helm.is_empty():
			report["helm"] = {"moving": helm.get("moving"), "pose": str(helm.owner.combat_hot_get(int(helm.unit), &"pose")),
				"capable": controller.vehicles._ship_capable(helm), "berth": helm.row.get("berth_id"), "local": controller.vehicles.ship_local_position(int(helm.id))}
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
	var world_id := "r0_crowd_ship_ui_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "Controller publishes and live-binds the pinned coast World", opened): return
	_freeze(lab)
	slot = controller.region_slot
	if not _check(slot != null and controller.region_slot == slot, "a Region save slot is bound to the Site"): return
	site_id = str(lab.terrain.site.id)
	var mode_gd := _mode()
	# Neutral part 2: the bind opens the Site as a live native crowd (the player's start team), so the mode is native.
	var bind_live: Dictionary = lab.region_bind_receipt(lab.terrain)
	if not _check(bind_live.get("complete") == true and str(bind_live.get("backend", "")) == "native" and lab.crowd_site.active, "a new world binds straight into a live native crowd", bind_live): return
	if not _check(str(mode_gd.get("mode", "")) == "live" and str(mode_gd.get("backend", "")) == "native", "live native mode from the bind", mode_gd): return
	var hull: Array[Vector2i] = Ship.footprint("ferry", SHIP_ANCHOR, SHIP_FACING)
	if not _check(lab.terrain.can_place_water_vehicle(hull) and lab.terrain.is_walkable(SHIP_SHORE), "the bound coast has the pinned ferry water and its shore contact", {"anchor": SHIP_ANCHOR, "shore": SHIP_SHORE}): return
	var friendly_cells: Array[Vector2i] = _inland_cells(Vector2i(24, 40))
	if not _check(friendly_cells.size() == TEAM_SIZE, "an inland team row, free and connected to the shore contact, exists", friendly_cells): return
	var enemy_cells: Array[Vector2i] = _far_cells(Vector2i(96, 96), 2)
	if not _check(enemy_cells.size() == 2, "two far enemy cells exist", enemy_cells): return
	var sides: Array[Dictionary] = [_side(friendly_cells.size(), 0), _side(enemy_cells.size(), 1)]
	if not _check(sides[0].size() > 0 and sides[1].size() > 0, "both original sides exist"): return
	var formations: Array = [friendly_cells, enemy_cells]
	# Neutral part 2: clear the player's live native crowd back to GD before the test sides deploy.
	var cleared: Dictionary = lab.crowd_site.clear()
	if not _check(cleared.get("ok", false) == true and not lab.crowd_site.active, "the player's crowd team returns to GD before the test sides deploy", cleared): return
	# Stand-in for the pending join relabel: the player's start team joins the friendly faction 0, as the old actor
	# player was. Neutral is hostile to everyone, so a neutral player beside the test team would block its departure.
	for team: TerrainArmy in lab.combat_armies:
		if team.has_army() and team.combat_identity(0) == lab.controlled_person_id(): team.faction_id = 0
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

	# Step 3 (site_ship_journey_test): the helm sails the ferry to the outward edge, so the seam route starts at the boat.
	var sail_deadline := _phase("sail to the outward edge", SAIL_DEADLINE_MS)
	var sail: Dictionary = vehicles.ship_order(ship_id, "sail", SAIL_EDGE, helm_id, true)
	if not _check(sail.ok, "the ferry sails to the outward edge through the GD water path", sail): return
	for step in range(SAIL_TICKS):
		if boat.move.is_empty() and boat.command.is_empty(): break
		if not _check(Time.get_ticks_msec() <= sail_deadline, "the sail finishes within the %d s phase deadline" % (SAIL_DEADLINE_MS / 1000), {"cell": lab.terrain.cell_from_index(int(boat.cell))}): return
		_tick(1)
	if not _check(lab.terrain.cell_from_index(int(boat.cell)) == SAIL_EDGE and boat.move.is_empty() and boat.command.is_empty(),
		"the ferry stops at the outward edge", {"cell": lab.terrain.cell_from_index(int(boat.cell)), "move": boat.move, "command": boat.command}): return
	_tick(DECK_TICKS)
	for identity: int in members:
		if not _check(vehicles.is_embarked(identity) and crowd.contains_person(identity), "crowd soldier %d is still aboard at the edge" % identity, _person_diag(identity)): return

	# Step 4 (site_ship_journey_test._depart_ui): select the ship in the formal vehicle UI and press DepartShipJourney.
	var depart_deadline := _phase("press DepartShipJourney", DEPART_DEADLINE_MS)
	controller._refresh_vehicle_controls()
	var form: Dictionary = controller._vehicle_forms.get("formal", {})
	if not _check(not form.is_empty() and form.choice != null, "the formal vehicle UI exists"): return
	var chosen := false
	for at in range(form.choice.item_count):
		if str(form.choice.get_item_metadata(at)) == ship_id:
			form.choice.select(at)
			chosen = true
	if not _check(chosen, "the formal vehicle UI lists the crowd ferry", ship_id): return
	controller._region_form.site_x.value = TO.x
	controller._region_form.site_y.value = TO.y
	controller._region_form.anchor_x.value = ARRIVAL_ANCHOR.x
	controller._region_form.anchor_y.value = ARRIVAL_ANCHOR.y
	controller._region_form.facing.select(2)
	var button: Button = lab.find_child("DepartShipJourney", true, false)
	if not _check(button != null, "the formal DepartShipJourney button exists"): return
	button.pressed.emit()
	if not _check(controller.ship_journey_active() and bool(controller.ship_journey_status().get("pending", false)),
		"the formal departure UI begins the original ship journey", {"message": str(controller.message.text), "status": controller.ship_journey_status(), "team": _team_diag()}): return
	if not _check(Time.get_ticks_msec() <= depart_deadline, "the departure finishes within its phase deadline"): return
	var required := float(controller.ship_journey_status().seconds)
	if not _check(required > 0.0, "the ship journey has a positive sailing time", required): return
	# During the journey the passengers sail aboard: they stay native aboard until the arrival commit.
	for identity: int in members:
		if not _check(vehicles.is_embarked(identity) and crowd.contains_person(identity), "crowd soldier %d sails aboard during the journey" % identity, _person_diag(identity)): return

	# Step 5: the shared step advances the journey until the arrival binds the destination. A live crowd Site steps through
	# lab._advance_original_shared_step(EXCHANGE_ACTION_STEP), as the crowd step tests do; _advance_action_time hides a
	# refused step behind show_result, so every step result is checked here.
	var origin_path: String = slot.effective_site_path(Vector2i.ZERO).get("path", "")
	var arrive_deadline := _phase("sail the journey to arrival", ARRIVAL_DEADLINE_MS)
	if not _check(controller._journey_can_advance(), "the begun crowd journey can advance (helm and crew ready)", _journey_diag()): return
	var progressed := false
	var completed_steps := 0
	for step in range(JOURNEY_STEPS):
		if not controller.ship_journey_active(): break
		if not _check(Time.get_ticks_msec() <= arrive_deadline, "the ship journey arrives within the %d s phase deadline" % (ARRIVAL_DEADLINE_MS / 1000), _journey_diag()): return
		var stepped: Dictionary = lab._advance_original_shared_step(lab.EXCHANGE_ACTION_STEP)
		if not _check(bool(stepped.get("ok", false)) or str(stepped.get("status", "")) in ["FIRE_SYNC_PENDING", "REGION_EVENT_PENDING"],
			"shared step %d of the crowd ship journey is accepted" % step, {"step": stepped, "journey": _journey_diag()}): return
		if not controller._ship_journey.is_empty() and float(controller._ship_journey.get("elapsed_action_seconds", 0.0)) > 0.0: progressed = true
		if bool(stepped.get("completed", false)): completed_steps += 1
		if completed_steps == 1 and bool(stepped.get("completed", false)) and controller.ship_journey_active():
			if not _check(progressed, "the first completed shared step advances the journey's ACTION progress", {"step": stepped, "journey": _journey_diag()}): return
	if not _check(progressed or not controller.ship_journey_active(), "the ship journey's ACTION progress advanced", _journey_diag()): return
	if not _check(not controller.ship_journey_active() and controller._current_region_site() == TO
		and str(controller.region_slot.control.active_site_id) == str(controller.lab.terrain.site.id),
		"the formal journey binds the destination Site", {"site": controller._current_region_site(), "status": controller.ship_journey_status(), "message": str(controller.message.text)}): return

	# Step 6: the passengers left the origin crowd (the origin Site file the arrival published) and arrived with the vessel.
	var origin_entry: Dictionary = controller.region_slot.effective_site_path(Vector2i.ZERO)
	if not _check(origin_entry.ok, "the origin Site has its published slot file", origin_entry): return
	var origin_loaded: Dictionary = controller.region_slot._load_checked(str(origin_entry.path), Vector2i.ZERO)
	if not _check(origin_loaded.ok, "the published origin Site reloads", origin_loaded): return
	var origin_state: Dictionary = origin_loaded.data.site
	if not _check(str(origin_entry.path) != origin_path, "the arrival published a new origin Site file", [origin_path, origin_entry.path]): return
	for army: Variant in origin_state.get("armies", []):
		if not army is Dictionary: continue
		for row: Dictionary in army.get("units", []):
			if not _check(not members.has(int(row.person_id)), "a departed passenger has no origin roster row", int(row.person_id)): return
	var tombstoned := false
	for team: Variant in origin_state.get("crowd", {}).get("teams", []):
		if team is Dictionary and int(team.get("team_id", -1)) == team_id: tombstoned = bool(team.get("departed", false))
	if not _check(not origin_state.has("crowd") or tombstoned, "the origin crowd section marks the travelling team departed", team_id): return
	if not _check(not origin_state.get("vehicles", {}).has(ship_id), "the vessel left the origin Site", origin_state.get("vehicles", {}).keys()): return
	if not _check(int(origin_state.get("controlled_person_id", -1)) != captain, "the origin Site no longer names the departed captain as controlled", origin_state.get("controlled_person_id", null)): return
	var destination_state: Dictionary = controller.lab.terrain.site
	var arrived_ids := {}
	for army: Variant in destination_state.get("armies", []):
		if not army is Dictionary: continue
		for row: Dictionary in army.get("units", []):
			if members.has(int(row.person_id)): arrived_ids[int(row.person_id)] = true
	if not _check(arrived_ids.size() == members.size(), "every passenger arrived in the destination armies", {"arrived": arrived_ids.keys(), "team": members}): return
	if not _check(destination_state.get("vehicles", {}).size() == 1, "the vessel arrived at the destination", destination_state.get("vehicles", {}).keys()): return
	print("REGION_CROWD_SHIP_UI destination crowd: ", destination_state.has("crowd"), " convert_pending=", destination_state.get("crowd_convert_pending", false),
		" live_crowd=", controller.lab.crowd_site != null and controller.lab.crowd_site.active)
	print("REGION_CROWD_SHIP_UI_PASS: ", checks, " checks; the crowd team boarded, sailed through DepartShipJourney/begin_ship_journey, left the origin crowd and arrived with its vessel")
	quit(0)
