extends "res://scripts/tests/region_siege_cold_action_epoch_test.gd"
## NEW Source-only fixture: original birth, public work, Nation dispatch, actual frame.
## Hull TEST_ONLY genesis is explicit; no manufacture-time or six-case acceptance.
const FleetGenesis = preload("res://scripts/tests/region_two_npc_sea_legal_named_genesis.gd")
const FleetGarrison = preload("res://scripts/terrain_lab/site_garrison.gd")
const FleetSustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const FleetFatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
var fleet_case := "hostile"
var fleets: Array[Dictionary] = []
var fleet_food: Array[Dictionary] = []
var fleet_meals := 0.0
var fleet_live_meals := 0.0
var fleet_cold: Array[Dictionary] = []
var fleet_exchanges: Array[Dictionary] = []
var fleet_observation := "birth"
var fleet_main_actor := 0 # The person the active Site controls now.
var fleet_founder := 0 # The world's start person; it stands up both fleets, then stays at the remote Site as an NPC.
var fleet_primary := ""
var fleet_live_lab: TerrainLab
var fleet_max_attempts := 48000
## The shared step each _fleet_step requests. ACTION_STEP everywhere except the
## friendly case's coarse approach to its meal boundary (_fleet_coarse_to_meal).
var fleet_step_request: float = TerrainLab.ACTION_STEP
## Fine-cadence game seconds kept before the next meal boundary. It is larger than
## one coarse step (EXCHANGE_ACTION_STEP x 60 x 4 = 8 game s), so no coarse step crosses it.
const FLEET_FINE_MEAL_MARGIN := 16.0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 600000
	out = "res://.godot-temp/region_c06_two_npc_sea/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with("--sea-case="): fleet_case = argument.trim_prefix("--sea-case=")
	# Nekki 2026-10-27: the friendly case waits for a real meal and runs 592-610 s; in-file 720 s, outer 780 s.
	if fleet_case == "friendly": deadline = Time.get_ticks_msec() + 720000
	action_speed = 1.0
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline: _finish(false, "%d-second genuine two-NPC sea deadline" % (720 if fleet_case == "friendly" else 600))
	return false

func _write_manifest() -> bool:
	return FleetGenesis.write(self)

## The active Site's owner is the live main Lab; the other fleet Site is its
## cached cold original. Decision A makes the remote Site briefly the active one.
func _fleet_owner(index: int) -> TerrainLab:
	if str(fleets[index].site) == str(slot.control.active_site_id): return lab
	var read: Dictionary = lab._region_gameplay_owner_lab(str(fleets[index].site), "cold_exact")
	return read.lab if read.ok else null

## The fleet team's live holder: its crowd owner on a crowd Site, else its GD army.
func _fleet_team(index: int) -> Variant:
	var original := _fleet_owner(index)
	if original == null: return null
	return _team_owner(original, int(fleets[index].team))

## Moves control between two crowd persons on the active Site (region_ship_finite_food_physical_test._ship_control).
## The test's expected controlled person follows the move.
func _fleet_control(from_id: int, to_id: int) -> bool:
	var switched: Dictionary = lab.crowd_site.on_control_changed(from_id, to_id)
	if not _check(switched.ok, "crowd control moves to the named person", {"from": from_id, "to": to_id, "result": switched}): return false
	lab.terrain.site["controlled_person_id"] = to_id
	fleet_main_actor = to_id
	return _check(lab.controlled_person_id() == to_id and not lab.controlled_target().is_empty(), "the Site controls the named person", to_id)

func _fleet_boat(index: int) -> Dictionary:
	var original := _fleet_owner(index)
	return {} if original == null else original.terrain.site.vehicles.get(str(fleets[index].boat), {})

func _setup_action_world() -> bool:
	lab = _shell()
	if not _check(lab != null, "original complete restore shell exists"): return false
	# The shell enters the tree as a restore owner (no crowd startup). The live main Lab of the game starts as an
	# ordinary scene, whose _ready requests the crowd unless --grid; this live owner does the same before its bind.
	lab.crowd_startup_requested = not OS.get_cmdline_user_args().has("--grid")
	controller = lab.site_controller
	var archive := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(32, 32)})
	Env.initialize(archive, "c06-two-npc-sea:archive")
	lab.bind_terrain(archive)
	lab.restore_only = false
	controller.save_root = out.path_join("archive")
	world_id = "r0_siege_action_%d_two_npc_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "original Controller opens the complete checksummed named World", opened): return false
	_freeze(lab)
	slot = controller.region_slot
	action_owner = lab
	lab.simulation_speed = 1.0
	if not _check(lab._wire_region_gameplay_adapters(slot).ok, "original common Slot owns both true Site flows"): return false
	# Neutral part 2 (11/03): the bind opens the Site as the player's live native one-person start team with its cadres.
	var bound: Dictionary = lab.region_bind_receipt(lab.terrain)
	if not _check(bound.get("complete") == true and lab.crowd_site != null and lab.crowd_site.active, "a new world binds straight into the player's live native crowd team", bound): return false
	fleet_main_actor = lab.controlled_person_id()
	fleet_founder = fleet_main_actor
	# Decision A (Nekki 2026-10-26): since P6 S1 a cold Site opened after world
	# genesis has no people, so the remote fleet's Site is no longer born cold
	# here. The same Actor stands it up hot later (_fleet_remote_decision_a).
	if not _fleet_genesis(0, lab): return false
	return _check(action_paid == 0.0 and lab.controlled_person_id() == fleet_main_actor and controller.checkpoint_region_internal("region_checkpoint", true).ok, "the main legal genesis graph publishes before paid work while main control stays with its original Actor")

## One fleet's legal genesis on the hot Site the founder stands on.
## Crowd port (2026-11-10): since 11/03 the founder is a row of its own neutral start team (with its cadres), so the
## fleet is built from crowd teams as region_ship_finite_food_physical_test builds its ship team:
## - a two-person fleet team (helm row 0, bow row 1) and a one-person headquarters team (the Nation head) are born
##   through the GD roster constructor between a crowd release and re-admission (region_siege_center_original_test);
## - control moves to the fleet captain for the public ship, food and bow work, as the old Actor Captain held it, and
##   returns to the founder afterwards; the fleet team keeps its own captain, now an NPC.
## The grid join_player / transfer_members_to / office-plan succession / leave_player_army checks have no crowd form (a
## crowd person changes teams only through a cadre split); crowd cadre rules are covered by region_crowd_cadre_split_test.
func _fleet_genesis(index: int, original: TerrainLab) -> bool:
	var x := 30 if index == 0 else 70
	var faction := 2 if index == 1 and fleet_case == "hostile" else 1
	for key: String in original.terrain.resource_base: Env.change(original.terrain, key, {"cleared": true, "remaining": 0})
	original.terrain.site.capacity = 100000
	for resource: String in Env.ITEM_NAMES: original.terrain.site.inventory[resource] = 1000
	# The finite Depot proof pays grain only: no other original food is stocked.
	for food: String in ["fish", "meat", "wild_food"]: original.terrain.site.inventory[food] = 0
	original.terrain.site.inventory.grain = 8
	original.terrain.site.depot_cell = original.terrain.index(Vector2i(x, 20))
	if not _check(SiteRuntime.initialize_item_storage(original.terrain.site).ok, "finite initial Depot stock uses the original allocator", index): return false
	var founder: Dictionary = original.site_controller.person_actions._person(fleet_founder, false)
	if not _check(original.controlled_person_id() == fleet_founder and not founder.is_empty() and founder.owner is CrowdPersonOwner,
		"the founder is the controlled live crowd row on the hot fleet Site", index): return false
	# The main founder starts on dry land east of the hull and its contacts, on the main side. On the remote Site the founder (main side) stays where it
	# arrived: the remote fleet may be hostile to it, so it must not stand within melee reach of that fleet.
	if index == 0 and not _check(_place_controlled(original, Vector2i(x + 6, 24), faction, true), "the founder and its cadres stand on the dry shore", index): return false
	var founder_cell := Vector2i(original.site_controller.person_actions._person(fleet_founder, false).cell)
	var free := _genesis_cells(Vector2i(x, 24), 3, original)
	if not _check(free.size() == 3, "actual free dry cells hold the fleet and headquarters rows", free): return false
	if index == 1 and not _check(Vector2(founder_cell).distance_to(Vector2(free[0])) >= 8.0, "the founder stands away from the remote fleet's rows", {"founder": founder_cell, "rows": free}): return false
	var teams_before := {}
	for owner: Variant in original.crowd_site.person_owners():
		if owner is CrowdPersonOwner: teams_before[int(owner.team_id)] = true
	var side := {"prefix": "friendly", "count": 2, "slot_count": 2, "female_count": 0, "faction": faction, "training": 0.0, "role": "combat", "troop_type": "melee_infantry", "attack": false, "cart_count": 0, "wagon_count": 0, "abilities": {}, "ai_enabled": false}
	var other: Dictionary = side.duplicate(true)
	other.prefix = "enemy"; other.count = 1; other.slot_count = 1
	var source_cells: Array[Vector2i] = [free[0], free[1]]
	var headquarters_cells: Array[Vector2i] = [free[2]]
	var sides: Array[Dictionary] = [side, other]
	var formations: Array = [source_cells, headquarters_cells]
	# Decision A: the remote Site's heir (main side) is born with the remote fleet, before its rows board: a crowd release
	# cannot hand a boarded row back to GD (NO_LEGAL_LAYOUT on its water cell), and nothing is paid in between.
	var heir_cells: Array[Vector2i] = []
	if index == 1:
		for cell: Vector2i in _genesis_cells(founder_cell + Vector2i(0, 3), 6, original):
			if not free.has(cell) and heir_cells.size() < 2: heir_cells.append(cell)
		if not _check(heir_cells.size() == 2, "actual free cells beside the founder hold the heir's original team", heir_cells): return false
		sides.append({"prefix": "friendly", "count": 2, "slot_count": 2, "female_count": 0, "faction": 1, "training": 0.0,
			"role": "combat", "troop_type": "melee_infantry", "attack": false, "cart_count": 0, "wagon_count": 0, "abilities": {}, "ai_enabled": false})
		formations.append(heir_cells)
	if not _crowd_release(original): return false
	var born: Dictionary = original._deploy_trial_teams(sides, formations, 4)
	if not _check(born.ok, "original typed genesis creates the finite real bodies and holders", born): return false
	# The named genesis itself re-admits a released crowd (TerrainLab._deploy_trial_teams crowd branch).
	if not original.crowd_site.active and not _crowd_admit(original): return false
	var source: Variant = null
	var headquarters: Variant = null
	for owner: Variant in original.crowd_site.person_owners():
		if not owner is CrowdPersonOwner or teams_before.has(int(owner.team_id)): continue
		for row: int in owner.records:
			var cell := Vector2i(owner.person(row, false).cell)
			if cell == source_cells[0]: source = owner
			if cell == headquarters_cells[0]: headquarters = owner
			if not heir_cells.is_empty() and cell == heir_cells[0]: center_heir = owner.combat_identity(int(owner.current_commander))
	if not _check(source != null and headquarters != null and source != headquarters, "the fleet and headquarters teams have their own crowd owners", index): return false
	var captain: int = source.combat_identity(int(source.current_commander))
	var people: Array[int] = [captain]
	for row: int in source.records:
		var identity: int = source.combat_identity(row)
		if identity != captain: people.append(identity)
	if not _check(people.size() == 2 and source.command_eligible(int(source.current_commander)) and not people.has(fleet_founder), "the fleet team is two real rows under its own eligible captain", people): return false
	# The founder commands the public ship work only through the fleet captain, as the old Actor Captain did.
	if not _fleet_control(fleet_founder, captain): return false
	var anchor := Vector2i(x, 19 if index == 0 else 18)
	var facing := Vector2i.LEFT if index == 0 else Vector2i.RIGHT
	var deployed: Dictionary = original.site_controller.vehicles.deploy_ship(source, "ferry", anchor, facing, true)
	if not deployed.ok:
		# Failure evidence only: every living body's cell beside the hull footprint.
		var hull: Array[Vector2i] = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd").footprint("ferry", anchor, facing)
		var bodies := []
		for owner: Variant in original.crowd_site.person_owners():
			if not owner is CrowdPersonOwner: continue
			for row: int in owner.records:
				var person: Dictionary = owner.person(row, false)
				if not person.is_empty(): bodies.append([owner.combat_identity(row), int(owner.team_id), person.cell, hull.has(Vector2i(person.cell))])
		var transport: SiteVehicleTransport = original.site_controller.vehicles
		deployed["evidence"] = {"hull": hull, "bodies": bodies, "water": original.terrain.can_place_water_vehicle(hull), "gd_block": hull.map(func(c: Vector2i) -> bool: return transport._people_block(c)), "crowd_block": hull.map(func(c: Vector2i) -> bool: return transport._crowd_people_block(c))}
	if not _check(deployed.ok, "explicit TEST_ONLY hull genesis retains original complete fit and owner guards", deployed): return false
	var boat := str(deployed.vehicle_id)
	var contacts: Array[Vector2i] = original.site_controller.vehicles.ship_contacts(original.terrain.site.vehicles[boat])
	if not _check(contacts.size() == 2 and contacts[0] != contacts[1], "the hull has two genuine distinct shore boarding contacts", contacts): return false
	# The north contact is a pier cut off from the land by the hull's water, so the rows stand on their contacts at
	# genesis (as the old fixture bore them there), placed natively before any paid interval.
	for row: int in 2:
		if not _check(_place_controlled_person(original, people[row], contacts[row]), "a fleet row stands on its own genuine boarding contact at genesis", {"person": people[row], "contact": contacts[row]}): return false
	# A crowd formation regroups placed rows on its captain; the original siege step holds an arrived worker on its cell
	# (region_ship_finite_food_physical_test walks its rows there through the same order).
	for row: int in 2:
		if not _check(original.crowd_site.siege_approach_step(people[row], contacts[row]), "the original siege step holds each fleet row on its contact", {"person": people[row], "contact": contacts[row]}): return false
	var members: Array[int] = []
	for owner: Variant in [source, headquarters]:
		for row: int in owner.records: members.append(owner.combat_identity(row))
	var head: int = headquarters.combat_identity(int(headquarters.current_commander))
	var nation := "c06_sea_nation_%d_%d" % [OS.get_process_id(), index]
	if not original.terrain.site.has("equipment_nations"): original.terrain.site.equipment_nations = {}
	original.terrain.site.equipment_nations[nation] = {"members": members, "standards": {}, "offices": SiteOffices.default_offices("nation", head, true)}
	var nation_offices: Dictionary = original.terrain.site.equipment_nations[nation].offices
	var authorized: Dictionary = original.site_controller.equipment_orders.apply_nation_office_plan(head, nation, int(nation_offices.revision), [{"op": "assign", "duty_id": "nation.dispatch", "position_id": str(SiteOffices.head_position(nation_offices).id)}])
	if not _check(authorized.ok and head != fleet_founder and not people.has(head), "original Nation office transaction retains its resident actual NPC dispatch head", authorized): return false
	fleets.append({"coordinate": Vector2i.ZERO if index == 0 else Vector2i(-1, 0), "site": str(original.terrain.site.id), "actor": captain, "team": int(source.team_id), "people": people, "boat": boat, "contacts": contacts, "nation": nation, "head": head, "token": "c06_two_npc_%d_%d" % [OS.get_process_id(), index], "refs": {}, "delivered": 6.0})
	return true

## Decision A for the remote fleet Site (Nekki 2026-10-26, same pattern as the
## phase/center tests). Only the controlled person may issue the public ship
## actions (site_vehicle_transport.gd requester == controlled_person_id), and
## the world has one controlled person. So the founder, free of the main fleet,
## travels with its start team to the remote Site, stands its fleet up there while
## that Site is hot, and hands living control to a newly born family member, who
## departs for the main Site so the remote Site goes cold. The founder stays there as an NPC.
func _fleet_remote_decision_a() -> bool:
	var remote_site := Grid.site_id(str(slot.pin.atlas_id), Vector2i(-1, 0))
	if not await _fleet_travel_controlled(Vector2i(-1, 0)): return false
	_fleet_phase("a_travel_to_remote")
	action_owner = lab
	lab.simulation_speed = 1.0
	if not _check(lab.controlled_person_id() == fleet_founder and str(slot.control.active_site_id) == remote_site and str(lab.terrain.site.id) == remote_site,
		"the same founder arrives at and controls the hot remote fleet Site"): return false
	fleet_main_actor = fleet_founder
	if not _fleet_genesis(1, lab): return false
	if not _check(controller.checkpoint_region_internal("region_checkpoint", true).ok,
		"the remote legal genesis graph publishes before its own paid work"): return false
	_fleet_phase("a_remote_genesis")
	if not await _public_fit(1): return false
	# The heir belongs to the main side's faction: it becomes main human control.
	_fleet_phase("a_remote_fit")
	if not _fleet_birth_heir(1): return false
	if not await _hand_over_and_leave(Vector2i.ZERO): return false
	action_owner = lab
	lab.simulation_speed = 1.0
	fleet_main_actor = lab.controlled_person_id()
	return _check(fleet_main_actor == center_heir and str(slot.control.active_site_id) == str(fleets[0].site) and str(slot.control.active_site_id) != remote_site and not lab.controlled_target().is_empty(),
		"the living heir controls the main Site and the remote fleet Site is cold", {"heir": center_heir, "controlled": fleet_main_actor, "active": slot.control.active_site_id})

## The heir is a newly born family member with a world-unique id, born beside the founder with the remote fleet.
func _fleet_birth_heir(_faction: int) -> bool:
	return _check(center_heir > 0 and center_heir != fleet_founder and lab.controlled_person_id() == fleet_founder and lab.crowd_site.person_owner(center_heir) != null,
		"the heir is a newly born world-unique person beside the founder", center_heir)

## The controlled Actor's own original Region travel (the travel half of
## _hand_over_and_leave, without a handover): depart, route, paid map
## intervals, then the production world-open binds the arrived Site.
func _fleet_travel_controlled(destination: Vector2i) -> bool:
	var traveller := lab.controlled_person_id()
	var due: Dictionary = slot.consume_due_region_events()
	if not _check(due.ok and bool(due.get("complete", false)), "original due endpoints finish before the Actor's own departure", due): return false
	var settled: Dictionary = controller.checkpoint_region_internal("region_checkpoint")
	if not _check(settled.ok, "original complete checkpoint captures the source Site before the Actor departs", settled): return false
	var departed_lab := lab
	var departed: Dictionary = RegionTravelSite.depart(controller)
	if not _check(departed.ok, "the controlled Actor departs through the original Region travel", departed): return false
	if is_instance_valid(genesis_panel): genesis_panel.free()
	genesis_panel = GenesisPanel.new()
	root.add_child(genesis_panel)
	genesis_panel.setup(genesis_panel)
	genesis_panel.set_process(false)
	var opened: Dictionary = genesis_panel.start({"world_id": world_id, "slot_id": "main", "manifest": manifest_path})
	if not _check(opened.ok and is_instance_valid(genesis_panel._original_adapter_host), "production travel panel restores the original map host", opened): return false
	lab = genesis_panel._original_adapter_host
	controller = lab.site_controller
	slot = genesis_panel.slot
	var selected: Dictionary = slot.region_travel_party()
	if not _check(selected.ok, "original map selects the Actor's party", selected): return false
	var current: Dictionary = slot.region_travel_status()
	var route_context: Dictionary = slot.prepare_region_route_context(null, selected.party)
	if not _check(route_context.ok, "original party route context", route_context): return false
	var search := RegionRoute.Search.new()
	search.source = slot.source
	search.start_site = current.site
	search.start_component = int(current.component)
	search.goal_site = destination
	search.context = route_context.context
	var route: Dictionary = search.run()
	if not _check(route.ok, "original route producer reaches the remote fleet Site", route): return false
	var planned: Dictionary = slot.set_region_travel_plan(route.steps)
	if not _check(planned.ok, "original Slot admits the Actor's route", planned): return false
	for iteration: int in range(18000):
		current = slot.region_travel_status()
		if not _check(current.ok, "the Actor's route has one original status", current): return false
		if bool(current.get("arrived", false)): break
		var advanced: Dictionary = slot.advance_region_travel(37)
		if not _check(advanced.ok, "original map caller advances one common interval", advanced): return false
		if bool(advanced.get("arrived", false)): break
		if iteration % 60 == 0: await process_frame
	_fleet_phase("t_route")
	if not _check(bool(slot.region_travel_status().get("arrived", false)), "the Actor genuinely arrives at the remote fleet Site"): return false
	var stored: Dictionary = slot.checkpoint_region_travel()
	if not _check(stored.ok, "the original travel publisher stores the arrived party", stored): return false
	# The departed scene's own Controller opens the arrival, as the real world-open path does.
	var visible := departed_lab
	var visible_open: Dictionary = visible.site_controller.open_fixed_world(manifest_path, world_id, "main", Vector2i(-1, -1), false)
	for retry: int in range(200000):
		if str(visible_open.get("code", "")) != "PENDING" and not visible.site_controller.region_operation_pending(): break
		visible_open = visible.site_controller.resume_region_operation()
		if retry % 60 == 0: await process_frame
	if not _check(visible_open.ok and bool(visible_open.get("arrived", false)), "production world-open binds the arrived remote fleet Site", visible_open): return false
	_fleet_phase("t_world_open")
	_freeze(visible)
	lab = visible
	controller = visible.site_controller
	slot = controller.region_slot
	var wired := lab._wire_region_gameplay_adapters(slot)
	if not _check(wired.ok, "arrived Site wires the same original Slot owners", wired): return false
	return _check(lab.controlled_person_id() == traveller and str(slot.control.active_site_id) == str(lab.terrain.site.id), "the same Actor controls the arrived Site")

func _food_results() -> bool:
	for outcome: Dictionary in slot.take_original_food_results():
		var owned := false
		for fleet: Dictionary in fleets:
			owned = owned or outcome.owner_kind == "party" and outcome.owner_id == fleet.token or outcome.owner_kind == "team" and outcome.owner_id == str(fleet.team) and outcome.site_id == fleet.site
		var actual_child := false
		if is_instance_valid(fleet_live_lab) and outcome.owner_kind == "team" and outcome.site_id == str(fleet_live_lab.terrain.site.id):
			for team: Variant in fleet_live_lab.team_owners():
				actual_child = actual_child or outcome.owner_id == str(team.team_id)
		owned = owned or actual_child
		if not owned: continue
		var consumed := float(outcome.consumed_rations)
		if not _check(is_finite(consumed) and consumed > 0.0, "accepted original per-call food result is positive and finite", outcome): return false
		fleet_meals += consumed
		if actual_child: fleet_live_meals += consumed
		fleet_food.append(outcome.duplicate(true))
	return _check(slot.take_original_food_results().is_empty(), "per-call accepted food observations drain once and do not replay")

func _fleet_step() -> bool:
	if not _food_results(): return false
	# Observe before the accepted caller, including exchanges during contact readiness.
	var body_before: Dictionary = _melee_bodies()
	var exchange_begin: int = fleet_exchanges.size()
	var paid_begin: float = action_paid
	var sequence_begin: int = int(slot.control.fire_clock.sequence)
	var stepped: Dictionary = lab._advance_original_shared_step(fleet_step_request)
	if not _check(stepped.ok, "original main caller accepts the actual common interval or due-zero endpoint", stepped): return false
	if stepped.get("completed", false):
		if not _check(float(stepped.action_seconds) > 0.0 and float(stepped.action_seconds) <= fleet_step_request + EPS and float(stepped.game_seconds) > 0.0, "genuine original accepted interval pays both clocks once", stepped): return false
		action_paid += float(stepped.action_seconds); action_game_paid += float(stepped.game_seconds)
	else:
		if not _check(float(stepped.get("action_seconds", 0.0)) == 0.0 and float(stepped.get("game_seconds", 0.0)) == 0.0, "same-point completion consumes no elapsed duration", stepped): return false
	if fleet_exchanges.size() > exchange_begin:
		var body_after: Dictionary = _melee_bodies()
		for ordinal: int in range(exchange_begin, fleet_exchanges.size()):
			fleet_exchanges[ordinal]["body_interval"] = {"before": body_before.duplicate(true), "after": body_after.duplicate(true),
				"paid_begin": paid_begin, "paid_end": action_paid, "completed": bool(stepped.get("completed", false)),
				"sequence_begin": sequence_begin, "sequence_end": int(slot.control.fire_clock.sequence),
				"endpoint_consumed": is_instance_valid(fleet_live_lab) and fleet_live_lab._region_point_pending.is_empty()}
	if not _fleet_reservation_observation(bool(stepped.get("completed", false))): return false
	return _check(lab.controlled_person_id() == fleet_main_actor and not lab.controlled_target().is_empty(), "actual main human control remains at its original Site Actor") and _food_results()

func _fleet_until(predicate: Callable, label: String) -> bool:
	for attempt: int in range(fleet_max_attempts):
		if predicate.call(): return _check(true, label)
		if Time.get_ticks_msec() > deadline: return _check(false, label + " deadline")
		if not _fleet_step(): return false
		if attempt % 60 == 0: await process_frame
	return _check(false, label + " caller-attempt bound")

func _public_board(index: int, row: int, berth: int) -> bool:
	var original := _fleet_owner(index)
	var fleet: Dictionary = fleets[index]
	var person := int(fleet.people[row])
	var begun: Dictionary = original.site_controller.person_actions.begin_ship_board(person, str(fleet.boat), int(fleet.actor), berth, false)
	if not _check(begun.ok and not original.site_controller.vehicles.is_embarked(person), "false-dispatch public boarding creates only the original pending job", begun): return false
	# The job ends either committed (embarked) or refused; a refusal is reported at once, not at the attempt bound.
	if not await _fleet_until(func() -> bool: return not _fleet_owner(index).site_controller.person_actions.is_busy(person), "original paid boarding job ends for the same actual row"): return false
	var owner_lab := _fleet_owner(index)
	var body: Dictionary = owner_lab.site_controller.person_actions._person(person, false)
	if not _check(owner_lab.site_controller.vehicles.is_embarked(person), "original paid board commits the same actual row",
		{"refusal": owner_lab.get_meta(&"last_refused_result", {}), "cell": body.get("cell"), "moving": body.get("moving"), "contacts": fleet.contacts, "row": row}): return false
	return _check(int(_fleet_owner(index).site_controller.vehicles.ship_person(person).row.berth_id) == berth, "actual body owns only its original requested berth")

func _contact_bow_local(vehicle: Dictionary) -> Vector2:
	var spec: Dictionary = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd").definition(str(vehicle.ship_type))
	return Vector2(float(int(spec.width) - 1) * 0.5, float(spec.length) - 0.75)

func _public_contact_bow(index: int) -> bool:
	# Move under the real Actor Captain before leave/dispatch; never command the NPC host.
	var original: TerrainLab = _fleet_owner(index)
	var fleet: Dictionary = fleets[index]
	var vehicles: SiteVehicleTransport = original.site_controller.vehicles
	var actions: SitePersonActions = original.site_controller.person_actions
	var identity: int = int(fleet.people[1])
	var boat: Dictionary = _fleet_boat(index)
	var target: Vector2 = _contact_bow_local(boat)
	var before: Vector2 = vehicles.ship_local_position(identity)
	var before_action: float = action_paid
	var begun: Dictionary = actions.begin_ship_walk(identity, target, int(fleet.actor), false)
	if not _check(begun.ok and actions.is_busy(identity) and float(begun.get("seconds", 0.0)) > 0.0
		and vehicles.ship_local_position(identity).distance_to(before) <= EPS,
		"false-dispatch public bow walk reserves the same real crew without teleporting", {"fleet": index, "result": begun, "from": before, "target": target}): return false
	if not await _fleet_until(func() -> bool: return _fleet_owner(index).site_controller.person_actions.is_busy(identity) and _fleet_owner(index).site_controller.vehicles.ship_local_position(identity).distance_to(before) > EPS, "original shared paid interval advances the genuine bow path"): return false
	original = _fleet_owner(index)
	vehicles = original.site_controller.vehicles; actions = original.site_controller.person_actions; boat = _fleet_boat(index)
	var partial: Vector2 = vehicles.ship_local_position(identity)
	var job: Dictionary = actions.job_for(identity)
	var projected: Vector2 = vehicles.ship_local_ground(boat, partial)
	if not _check(action_paid > before_action and float(job.get("elapsed", 0.0)) > 0.0
		and float(job.get("elapsed", 0.0)) < float(job.get("duration", 0.0))
		and not bool(job.get("test_dispatch", true)) and not vehicles.ship_can_attack(identity)
		and partial.distance_to(target) > EPS and vehicles.ship_person_ground(identity).distance_to(projected) <= EPS,
		"actual partial bow motion pays ACTION and projects the original busy noncombat body", {"fleet": index, "local": partial, "ground": projected, "elapsed": job.get("elapsed"), "duration": job.get("duration")}): return false
	if not await _fleet_until(func() -> bool: return not _fleet_owner(index).site_controller.person_actions.is_busy(identity), "original paid bow walk reaches its actual committed endpoint"): return false
	original = _fleet_owner(index)
	vehicles = original.site_controller.vehicles; boat = _fleet_boat(index)
	var arrived: Dictionary = vehicles.ship_person(identity)
	return _check(action_paid > before_action and not arrived.is_empty()
		and int(arrived.id) == identity and str(arrived.row.get("embarked_vehicle_id", "")) == str(fleet.boat)
		and int(arrived.row.get("berth_id", -1)) == 1 and vehicles.ship_local_position(identity).distance_to(target) <= EPS
		and vehicles.ship_driver_ready(boat) and vehicles.ship_crew_count(boat) == 1,
		"real paid crew reaches the legal bow while the same ferry retains its original helm and full standard crew", {"fleet": index, "target": target, "paid_action": action_paid - before_action})

## Every public step below names the Actor as requester, and the Depot fill
## needs the controlled Actor to command the receiving crew
## (site_vehicle_transport.gd, site_food_delivery.gd _command_receiver), so a
## fleet's whole fit runs while its own Site is hot under that Actor.
func _public_fit(index: int) -> bool:
	var fleet: Dictionary = fleets[index]
	# Two NPCs: row 0 boards berth 1 and takes the helm; row 1 then boards the
	# freed crew berth 1 and stays seated (helm + one seated crew = standard crew).
	if not await _public_board(index, 0, 1): return false
	var original := _fleet_owner(index)
	var helm: Dictionary = original.site_controller.person_actions.begin_ship_helm(int(fleet.people[0]), str(fleet.boat), int(fleet.actor), false)
	if not _check(helm.ok and int(_fleet_boat(index).operator_id) == 0, "false-dispatch public helm reserves an actual uncommitted duty", helm): return false
	if not await _fleet_until(func() -> bool: return int(_fleet_boat(index).operator_id) == int(fleet.people[0]) and not _fleet_owner(index).site_controller.person_actions.is_busy(int(fleet.people[0])), "original paid helm seats the same actual operator"): return false
	if not await _public_board(index, 1, 1): return false
	# Boarding leaves row 1 at the hull edge; the original deck path seats it on
	# its own crew berth position (crew is counted only there).
	var seat: Vector2 = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd").local_position(str(_fleet_boat(index).ship_type), 1)
	var seated: Dictionary = _fleet_owner(index).site_controller.person_actions.begin_ship_walk(int(fleet.people[1]), seat, int(fleet.actor), false)
	if not _check(seated.ok, "false-dispatch original deck path seats the crew row on its berth", seated): return false
	if not await _fleet_until(func() -> bool: return not _fleet_owner(index).site_controller.person_actions.is_busy(int(fleet.people[1])), "original paid deck path seats the same actual crew row"): return false
	if not _check(_fleet_owner(index).site_controller.vehicles.ship_local_position(int(fleet.people[1])).distance_to(seat) <= EPS, "actual crew row sits exactly on its crew berth"): return false
	original = _fleet_owner(index)
	var team: Variant = _fleet_team(index)
	# A ferry's standard crew is its helm alone (standard_crew 1); the second
	# real NPC rides aboard the same boat, able, on a legal seated position.
	var second: Dictionary = original.site_controller.vehicles.ship_person(int(fleet.people[1]))
	var second_seat: Vector2 = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd").local_position(str(_fleet_boat(index).ship_type), int(second.get("row", {}).get("berth_id", -1)))
	if not _check(original.site_controller.vehicles.ship_driver_ready(_fleet_boat(index)) and original.site_controller.vehicles.ship_crew_count(_fleet_boat(index)) == 1
		and not second.is_empty() and str(second.row.get("embarked_vehicle_id", "")) == str(fleet.boat) and original.site_controller.vehicles._ship_capable(second)
		and original.site_controller.vehicles.ship_local_position(int(fleet.people[1])).distance_to(second_seat) <= EPS,
		"one real helm is the full standard crew and one separate real NPC rides seated aboard each ferry"): return false
	var delivery: Dictionary = original.site_controller.begin_team_food(team, float(fleet.delivered), int(fleet.people[1]), {"kind": "depot"})
	if not _check(delivery.ok, "public actual shore Depot fill starts finite original productive work", delivery): return false
	for attempt: int in range(6000):
		if _fleet_owner(index).site_controller._supply_entry(_fleet_team(index)).delivery.is_empty(): break
		if Time.get_ticks_msec() > deadline: break
		if not _fleet_step(): return false
		if attempt % 60 == 0: await process_frame
	var fed: SiteController = _fleet_owner(index).site_controller
	var job: Dictionary = fed._supply_entry(_fleet_team(index)).get("delivery", {})
	if not _check(job.is_empty(), "original accepted delivery publishes its actual boat food pool",
		{"left": job.get("left"), "quantity": job.get("quantity"), "pending": job.get("pending"), "representative": job.get("representative_id"), "target": job.get("target_location"),
		"crowd_delivery_steps": fed.crowd_delivery_steps, "crowd_delivery_last": fed.crowd_delivery_last, "settle": fed.supply_settle_last,
		"valid": fed.food_delivery.valid_breakdown(_fleet_team(index), fed._supply_entry(_fleet_team(index))) if not job.is_empty() else "done", "paid": action_paid}): return false
	if not _check(int(_fleet_owner(index).terrain.site.inventory.grain) == 8 - int(fleet.delivered), "finite original Depot pays each delivered grain exactly once"): return false
	team = _fleet_team(index)
	if not _check(team != null and team.combat_identity(int(team.current_commander)) == int(fleet.actor) and team.command_eligible(int(team.current_commander)) and lab.controlled_person_id() == int(fleet.actor), "the controlled fleet captain commands its real crew before control returns to the founder"): return false
	if not await _public_contact_bow(index): return false
	# Control returns to the founder; the fleet team keeps its own captain, now an NPC (finite_food closure).
	if not _fleet_control(int(fleet.actor), fleet_founder): return false
	team = _fleet_team(index)
	return _check(team != null and team.combat_identity(int(team.current_commander)) == int(fleet.actor) and team.command_eligible(int(team.current_commander)) and not fleet.people.has(lab.controlled_person_id()),
		"the fleet team keeps the same eligible captain, now an NPC, after control returns to the founder")

## Stable person/team/nation refs come from the original travel identity
## allocator, which a departure would run; nothing has travelled yet in this
## fixture, and the resident head's observation needs them first. The first
## reopen checkpoint publishes them with the same whole graphs.
func _fleet_identities() -> bool:
	for index: int in 2:
		var original := _fleet_owner(index)
		if not _check(original != null, "each fleet Site has its actual original owner before identity indexing"): return false
		var identified := RegionTravel.prepare_identity(original.terrain.site)
		if not _check(identified.ok, "original identity allocator indexes each fleet Site's nation, teams and people", identified): return false
		original.terrain.site.travel_identity = identified.state.travel_identity
	return true

func _sorted_ids(ids: Array) -> Array:
	var sorted: Array = []
	for identity: Variant in ids: sorted.append(int(identity))
	sorted.sort()
	return sorted

func _fleet_dispatch(index: int) -> bool:
	var original := _fleet_owner(index)
	var fleet: Dictionary = fleets[index]
	var destination := Vector2i(-1, 0) if index == 0 else Vector2i.ZERO
	var observed: Dictionary = slot.record_region_officer_geography_observation(original, int(fleet.head), destination)
	if not _check(observed.ok, "actual resident Nation head observes only original public target geography", observed): return false
	var prepared: Dictionary = slot.prepare_npc_region_dispatch(original, str(fleet.nation), int(fleet.team), destination, 0, [], str(fleet.token))
	if not _check(prepared.ok and prepared.party.mode == "sea" and _sorted_ids(prepared.party.person_ids) == _sorted_ids(fleet.people) and prepared.party.vehicle_ids == [fleet.boat] and prepared.party.content.actors.is_empty() and prepared.plan.action_steps.size() > 0 and prepared.request.decider == int(fleet.head), "original Nation authority prepares a genuine full one-hull two-row sea route", prepared.get("code")): return false
	fleet.refs = prepared.party.content.travel_identity.refs.duplicate(true)
	var before := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds]
	var committed: Dictionary = slot.commit_npc_region_dispatch(prepared)
	return _check(committed.ok and not original.terrain.site.vehicles.has(str(fleet.boat)) and before == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds] and lab.controlled_person_id() == fleet_main_actor, "true original dispatch relinquishes each source hull once without control or clock drift", committed)

func _fleet_graphs() -> Dictionary:
	var graphs := {}
	for index: int in 2:
		var original := _fleet_owner(index)
		if original == null: return {}
		var context: Dictionary = slot.region_checkpoint_context(original.terrain, "region_checkpoint", "c06_two_npc_source_observer", true, {})
		if not context.ok: return {}
		var captured: Dictionary = original.capture_region_owner_state(context.context)
		if not captured.ok: return {}
		graphs[str(fleets[index].site)] = {"root": captured.owner_states.scene.root.duplicate(true), "nodes": captured.owner_states.scene.nodes.duplicate(true)}
	for fleet: Dictionary in fleets:
		var reference: Dictionary = slot.region_registry().parties.get(str(fleet.token), {})
		if reference.is_empty() or reference.phase != "travelling": continue
		var selected: Dictionary = slot._region_npc_party(str(fleet.token))
		if not selected.ok: return {}
		var graph: Dictionary = slot._region_capture_party_graph(str(fleet.token), selected.party)
		if not graph.ok: return {}
		var proof: Dictionary = slot.region_live_party_proof(str(fleet.token))
		var mode: Dictionary = slot.region_registry().modes.get("travel:" + str(fleet.token), {})
		var diagnostic := {"token": str(fleet.token), "phase": str(reference.phase), "stage": fleet_observation,
			"generation": int(slot._marker.generation), "revision": int(slot.region_registry().revision),
			"party_path": reference.party_path, "party_sha256": reference.party_sha256, "code": proof.get("code", "OK"),
			"party_game": selected.party.upkeep.at, "party_action": selected.party.upkeep.get("owner_action_seconds"),
			"world_game": slot.control.logical_game_seconds, "world_action": slot.control.fire_clock.action_seconds,
			"mode_game": mode.get("game_seconds"), "mode_action": mode.get("action_seconds"), "sequence": slot.control.fire_clock.sequence}
		if not _check(proof.ok, "joint checkpoint selects each complete original party proof", diagnostic): return {}
		if not _check(var_to_bytes(proof.party) == var_to_bytes(selected.party)
			and absf(float(proof.proof.game_seconds) - float(slot.control.logical_game_seconds)) <= 0.00000001
			and absf(float(proof.proof.action_seconds) - float(slot.control.fire_clock.action_seconds)) <= 0.00000001,
			"selected checkpoint body and both clocks match the completed original runtime party", diagnostic): return {}
		if not _check(graph.original_live_graph.has("owners") and graph.original_live_graph.owners is Dictionary
			and graph.original_live_graph.owners.get("scene") is Dictionary and graph.original_live_graph.owners.get("transport") is Dictionary,
			"original party graph contains the actual complete scene and transport owners", {"token": str(fleet.token), "stage": fleet_observation}): return {}
		var owners: Dictionary = graph.original_live_graph.owners
		graphs[str(fleet.token)] = {"party": selected.party.duplicate(true), "graph": {"root": owners.scene.root.duplicate(true), "nodes": owners.scene.nodes.duplicate(true), "transport": owners.transport.duplicate(true)}, "proof": proof.proof}
	return graphs

## Saved JSON domain: the same stringify(sort_keys, full_precision) -> parse ->
## stringify path the store saves with; no custom rounding. Only the three
## re-activation fields of each mode row are set aside (checked separately);
## tactical_until_action compares as its remaining demand.
func _reopen_canonical(control: Dictionary, marker: Dictionary, graphs: Dictionary) -> String:
	var control_copy: Dictionary = control.duplicate(true)
	var action := float(control.fire_clock.action_seconds)
	for owner: Variant in control_copy.get("region_gameplay", {}).get("modes", {}):
		var mode: Dictionary = control_copy.region_gameplay.modes[owner]
		mode.erase("revision")
		mode.tactical_until_action = maxf(0.0, float(mode.get("tactical_until_action", 0.0)) - action)
		if mode.get("activation") is Dictionary:
			mode.activation.erase("session")
			mode.activation.erase("mode_revision")
			mode.activation.erase(&"mode_revision")
	var saved := JSON.stringify([control_copy, marker, graphs], "", true, true)
	return JSON.stringify(JSON.parse_string(saved), "", true, true)

## Every travelling party's selected document as the Slot reads it from disk:
## body, saved original owner graph and proof. Needs no adapter or owner Lab.
## Before any dispatch there are none; null means a document failed to read.
func _fleet_selected_documents(source_slot: RegionSaveSlot) -> Variant:
	var documents := {}
	for fleet: Dictionary in fleets:
		var reference: Dictionary = source_slot.region_registry().parties.get(str(fleet.token), {})
		if reference.is_empty() or reference.phase != "travelling": continue
		var selected: Dictionary = source_slot.region_live_party_proof(str(fleet.token))
		if not _check(selected.ok, "each selected party document reads back complete", {"token": str(fleet.token), "code": selected.get("code", "OK")}): return null
		documents[str(fleet.token)] = {"party": selected.party, "graph": selected.original_live_graph, "proof": selected.proof}
	return documents

## As _reopen_canonical, but a fresh open has not yet re-admitted any mode: each
## runtime activation is set aside here and checked after rewire instead.
func _restore_canonical(control: Dictionary, marker: Dictionary, documents: Dictionary) -> String:
	var control_copy: Dictionary = control.duplicate(true)
	var action := float(control.fire_clock.action_seconds)
	for owner: Variant in control_copy.get("region_gameplay", {}).get("modes", {}):
		var mode: Dictionary = control_copy.region_gameplay.modes[owner]
		mode.erase("revision")
		mode.erase("activation")
		mode.tactical_until_action = maxf(0.0, float(mode.get("tactical_until_action", 0.0)) - action)
	var saved := JSON.stringify([control_copy, marker, documents], "", true, true)
	return JSON.stringify(JSON.parse_string(saved), "", true, true)

## Each re-activated mode advances revision and mode_revision by exactly one and
## carries the session of the original Lab now bound to that owner.
func _reopen_modes_reactivated(before: Dictionary) -> bool:
	var after: Dictionary = slot.region_registry().modes
	if before.size() != after.size(): return false
	for owner: Variant in before:
		if not after.has(owner): return false
		var old: Dictionary = before[owner]
		var now: Dictionary = after[owner]
		var old_activation: Dictionary = old.get("activation", {})
		var new_activation: Dictionary = now.get("activation", {})
		if int(now.revision) == int(old.revision) and str(new_activation.get("session", "")) == str(old_activation.get("session", "")) \
				and int(new_activation.get("mode_revision", -1)) == int(old_activation.get("mode_revision", -1)): continue
		if int(now.revision) != int(old.revision) + 1 or int(new_activation.get("mode_revision", -1)) != int(old_activation.get("mode_revision", -1)) + 1: return false
		var owner_lab: TerrainLab = lab if str(owner) == str(slot.control.active_site_id) else slot._region_original_labs.get(str(owner))
		# A travelling party's original Lab is not a Site owner: the Slot keeps it
		# under region_party_owner_labs, keyed by token, after the positive bind.
		if str(owner).begins_with("travel:"):
			owner_lab = slot.get_meta(&"region_party_owner_labs", {}).get(str(owner).trim_prefix("travel:"))
		if not is_instance_valid(owner_lab) or owner_lab.terrain == null: return false
		if str(new_activation.get("session", "")) != str(owner_lab.region_bind_receipt(owner_lab.terrain).get("session", "-")): return false
	return true

## Failure detail for _reopen_modes_reactivated: every owner's mode before and
## after the fresh cold bind, the bound original Lab's session, and the first
## rule that owner breaks ("" when it passes). Read-only.
func _reopen_mode_facts(before: Dictionary) -> Dictionary:
	var after: Dictionary = slot.region_registry().modes
	var owners: Array = before.keys()
	for owner: Variant in after:
		if not owners.has(owner): owners.append(owner)
	var rows := {}
	for owner: Variant in owners:
		var old: Dictionary = before.get(owner, {})
		var now: Dictionary = after.get(owner, {})
		var old_activation: Dictionary = old.get("activation", {})
		var new_activation: Dictionary = now.get("activation", {})
		var owner_lab: Variant = lab if str(owner) == str(slot.control.active_site_id) else slot._region_original_labs.get(str(owner))
		if str(owner).begins_with("travel:"): owner_lab = slot.get_meta(&"region_party_owner_labs", {}).get(str(owner).trim_prefix("travel:"))
		var lab_session := "-"
		if owner_lab is TerrainLab and is_instance_valid(owner_lab) and owner_lab.terrain != null: lab_session = str(owner_lab.region_bind_receipt(owner_lab.terrain).get("session", "-"))
		var reason := ""
		if old.is_empty(): reason = "NEW_AFTER_REOPEN"
		elif now.is_empty(): reason = "MISSING_AFTER_REOPEN"
		elif int(now.revision) == int(old.revision) and str(new_activation.get("session", "")) == str(old_activation.get("session", "")) and int(new_activation.get("mode_revision", -1)) == int(old_activation.get("mode_revision", -1)): reason = ""
		elif int(now.revision) != int(old.revision) + 1 or int(new_activation.get("mode_revision", -1)) != int(old_activation.get("mode_revision", -1)) + 1: reason = "NOT_EXACTLY_ONE_REACTIVATION"
		elif lab_session == "-": reason = "NO_BOUND_OWNER_LAB"
		elif str(new_activation.get("session", "")) != lab_session: reason = "SESSION_MISMATCH"
		rows[str(owner)] = {"reason": reason,
			"before": {"mode": old.get("mode"), "revision": old.get("revision"), "generation": old.get("generation"), "consumer": old.get("consumer"), "mode_revision": old_activation.get("mode_revision"), "session": old_activation.get("session")},
			"after": {"mode": now.get("mode"), "revision": now.get("revision"), "generation": now.get("generation"), "consumer": now.get("consumer"), "mode_revision": new_activation.get("mode_revision"), "session": new_activation.get("session")},
			"bound_lab_session": lab_session}
	return {"active": str(slot.control.active_site_id), "before_count": before.size(), "after_count": after.size(), "owners": rows}

func _fleet_reopen() -> bool:
	if not _food_results(): return false
	var saved: Dictionary = controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(saved.ok, "original joint publisher captures both complete Sites and all true current party owners", saved): return false
	var graphs := _fleet_graphs()
	if not _check(not graphs.is_empty(), "complete actual Sites/party graphs are observed after original publication"): return false
	var truth_modes: Dictionary = slot.region_registry().modes.duplicate(true)
	var truth := _reopen_canonical(slot.control, slot._marker, graphs)
	var truth_documents: Variant = _fleet_selected_documents(slot)
	if truth_documents == null: return false
	var truth_publication := _restore_canonical(slot.control, slot._marker, truth_documents)
	var reopened := RegionSaveSlot.new()
	var opened: Dictionary = reopened.open_map(slot.source, world_id, "main")
	if not _check(opened.ok, "fresh original Slot opens the same immutable publication", opened): return false
	var read: Dictionary = reopened.open_site(Vector2i.ZERO)
	if not _check(read.ok and read.data.site.has("region_snapshot"), "fresh source retains its entire genuine owner graph", read.get("code")): return false
	# Restore itself is compared first, before any adapter rewire or party owner
	# bind can touch it: the read-back marker, clocks and every selected party
	# document equal the saved publication in the saved JSON domain.
	var restored_documents: Variant = _fleet_selected_documents(reopened)
	if restored_documents == null: return false
	if not _check(truth_publication == _restore_canonical(reopened.control, reopened._marker, restored_documents),
		"fresh restore reads back the same selected marker, clocks and party documents before any rewire"): return false
	var restored := _restore_selected(read.data, reopened, false)
	if restored == null: return false
	lab = restored; controller = lab.site_controller; slot = reopened; action_owner = lab
	lab.simulation_speed = 1.0
	# The manual fresh Slot gets the restored main original as its common adapter
	# host, as the original controller did for the first Slot.
	var rewired := lab._wire_region_gameplay_adapters(slot)
	if not _check(rewired.ok, "fresh Slot adapters wire to the positively restored main original", rewired): return false
	# Sites restore separately; positively restore every travelling party before observing its graph.
	for token: String in slot.region_registry().parties:
		if str(slot.region_registry().parties[token].get("phase", "")) not in ["travelling", "pending_life"]: continue
		var travelling := slot._region_npc_party(token)
		var owner: Dictionary = lab.prepare_region_party_original_owner(token, travelling.party, slot) if travelling.ok else travelling
		if not _check(owner.ok and owner.lab is TerrainLab and owner.receipt.get("complete", false)
			and owner.receipt.get("owners_restored", false), "fresh original bind restores the selected party's complete owner", {"token": token, "code": owner.get("code", "OK"), "message": str(owner.get("message", "")).left(800)}): return false
		var actual := slot.region_original_party_runtime_proof(token, travelling.party)
		if not _check(actual.ok and actual.lab == owner.lab, "restored travelling party has its actual current runtime proof", {"token": token, "code": actual.get("code", "OK")}): return false
	if not fleet_primary.is_empty() and not _bind_live_observer(): return false
	# This replaces a byte check that cannot hold across a JSON reopen with a fresh
	# original Lab: the store's JSON round trip changes number types, key order and
	# last-ulp floats, and the new Lab re-activates each mode under its own session.
	var reopened_graphs := _fleet_graphs()
	if not _check(_reopen_modes_reactivated(truth_modes), "fresh cold bind re-activates each mode exactly once under its new original Lab session", _reopen_mode_facts(truth_modes)): return false
	if not _check(truth == _reopen_canonical(slot.control, slot._marker, reopened_graphs), "true full cold bind preserves every Site and current party graph, clock and selected marker in the saved JSON domain"): return false
	if not _food_results(): return false
	var before := var_to_bytes([slot.control, _fleet_graphs()])
	var retry: Dictionary = slot.consume_due_region_events()
	if not _check(retry.ok and retry.get("complete", false) and before == var_to_bytes([slot.control, _fleet_graphs()]), "original selected endpoint retry owns zero time and no duplicate frame or body", retry): return false
	if not _food_results(): return false
	fleet_cold.append({"observation": fleet_observation, "world": slot.control.logical_game_seconds, "action": slot.control.fire_clock.action_seconds, "generation": slot._marker.generation, "graphs": graphs})
	return true

func _has_partial() -> bool:
	for fleet: Dictionary in fleets:
		var selected: Dictionary = slot._region_npc_party(str(fleet.token))
		if selected.ok:
			var cursor: Dictionary = selected.party.upkeep.sea_cursor
			if float(cursor.elapsed) > EPS and float(cursor.elapsed) < float(cursor.duration) - EPS: return true
	return false

func _has_actual_frame() -> bool:
	for fleet: Dictionary in fleets:
		var reference: Dictionary = slot.region_registry().parties[str(fleet.token)]
		if reference.phase != "travelling": continue
		var selected: Dictionary = slot._region_npc_party(str(fleet.token))
		if selected.ok and str(selected.party.upkeep.get("live", {}).get("upkeep", "")) == "liveBody":
			fleet_primary = str(fleet.token)
			return true
	return false

func _original_partial_refusals() -> bool:
	for fleet: Dictionary in fleets:
		var selected: Dictionary = slot._region_npc_party(str(fleet.token))
		if not _check(selected.ok, "real travelling party is selected for its original refusal", selected.get("code")): return false
		var proved: Dictionary = slot.region_original_party_runtime_proof(str(fleet.token), selected.party)
		if not _check(proved.ok and proved.lab is TerrainLab, "real coarse travelling party retains its actual original host", proved.get("code")): return false
		var found := false
		for team: TerrainArmy in proved.lab.combat_armies:
			for unit: int in team.combat_units.size():
				var identity := team.combat_identity(unit)
				if proved.lab.terrain.site.travel_identity.refs.person.get(str(identity), {}) != fleet.refs.person[str(fleet.people[1])]: continue
				found = true
				if not _check(not proved.lab.site_controller.vehicles.ship_can_attack(identity) and not team.exchange_initiates(unit, int(fleet.people[0]), true), "original real journey/partial pose keeps nonhelm combat refusal before actual frame completion"): return false
		if not _check(found, "partial refusal names the same real original bow crew reference"): return false
	return true

func _bind_live_observer() -> bool:
	var selected: Dictionary = slot._region_npc_party(fleet_primary)
	if not _check(selected.ok and str(selected.party.upkeep.get("live", {}).get("upkeep", "")) == "liveBody" and selected.party.content.actors.is_empty(), "selected actual NPC LIVE_BODY contains the real complete merged boat/crew closure", selected.get("code")): return false
	var proof: Dictionary = slot.region_original_party_runtime_proof(fleet_primary, selected.party)
	if not _check(proof.ok and proof.lab is TerrainLab and proof.lab != lab, "original proof resolves the actual separate complete NPC frame host", proof.get("code")): return false
	fleet_live_lab = proof.lab
	var callback := Callable(self, "_actual_exchange")
	if not fleet_live_lab.exchange_resolved.is_connected(callback): fleet_live_lab.exchange_resolved.connect(callback)
	return _check(fleet_live_lab.terrain.site.controlled_person_id == -1 and lab.controlled_person_id() == fleet_main_actor and slot.control.active_site_id == str(lab.terrain.site.id), "NPC frame publication keeps the active human Site and original Actor untouched")

func _crew(index: int, row: int) -> Dictionary:
	var fleet: Dictionary = fleets[index]
	var reference: Dictionary = fleet.refs.person[str(fleet.people[row])]
	# The frame's team holders: native crowd owners once the frame steps as a crowd (Nekki 2026-11-10 A), else GD armies.
	for team: Variant in fleet_live_lab.team_owners():
		for unit: int in _unit_indices(team):
			var identity: int = team.combat_identity(unit)
			if fleet_live_lab.terrain.site.travel_identity.refs.person.get(str(identity), {}) == reference:
				return fleet_live_lab.site_controller.vehicles.ship_person(identity)
	return {}

## Failure evidence only: what the frame holds when a bow crew cannot be read.
func _crew_facts(index: int) -> Dictionary:
	var fleet: Dictionary = fleets[index]
	var facts := {"want": fleet.refs.person.get(str(fleet.people[1]), {}), "native": _native_frame(), "teams": []}
	if not is_instance_valid(fleet_live_lab): return facts
	for team: Variant in fleet_live_lab.team_owners():
		var rows: Array = []
		for unit: int in _unit_indices(team):
			var identity: int = team.combat_identity(unit)
			rows.append([identity, fleet_live_lab.terrain.site.travel_identity.refs.person.get(str(identity), {}), not fleet_live_lab.site_controller.vehicles.ship_person(identity).is_empty()])
		facts.teams.append({"team": team.team_id, "rows": rows})
	return facts

## Whether `person` (a ship_person record) would start an exchange with `other_id`: the native order form on a crowd
## frame (CrowdPersonOwner.native_exchange_initiates), the GD form on a grid frame.
func _initiates(person: Dictionary, other_id: int, melee: bool) -> bool:
	if person.owner is CrowdPersonOwner: return person.owner.native_exchange_initiates(int(person.unit), other_id, melee)
	return person.owner.exchange_initiates(int(person.unit), other_id, melee)

## A team holder's row indices: a GD army's rows are 0..n-1; a crowd owner's combat_units is keyed by native index.
static func _unit_indices(team: Variant) -> Array:
	return team.combat_units.keys() if team.combat_units is Dictionary else range(team.combat_units.size())

func _native_frame() -> bool:
	return is_instance_valid(fleet_live_lab) and fleet_live_lab.crowd_site != null and fleet_live_lab.crowd_site.active

func _actual_exchange(first: int, second: int, result: Dictionary) -> void:
	var a := _crew(0, 1)
	var b := _crew(1, 1)
	if a.is_empty() or b.is_empty() or [mini(first, second), maxi(first, second)] != [mini(int(a.id), int(b.id)), maxi(int(a.id), int(b.id))]: return
	fleet_exchanges.append({"first": first, "second": second, "result": result.duplicate(true), "world": slot.control.logical_game_seconds, "action": slot.control.fire_clock.action_seconds, "sequence": slot.control.fire_clock.sequence})

func _actual_contact_ready() -> bool:
	var a := _crew(0, 1)
	var b := _crew(1, 1)
	return not a.is_empty() and not b.is_empty() and fleet_live_lab.site_controller.vehicles.ship_can_attack(int(a.id)) and fleet_live_lab.site_controller.vehicles.ship_can_attack(int(b.id)) and fleet_live_lab.site_controller.vehicles.ship_combat_contact(int(a.id), int(b.id))

func _live_food_held() -> float:
	var held := 0.0
	var seen: Array[Dictionary] = []
	for index: int in 2:
		var person := _crew(index, 1)
		if person.is_empty(): return -1.0
		var supply: Dictionary = fleet_live_lab.site_controller._supply_entry(person.owner)
		if supply.is_empty(): return -1.0
		var key := "vehicle:" + str(person.row.embarked_vehicle_id)
		if not _check(supply.locations.has(key), "actual remapped team retains only its true boat food pool", key): return -1.0
		if not seen.any(func(prior: Dictionary) -> bool: return is_same(prior, supply)):
			seen.append(supply)
			held += FleetSustain.rations(supply.sustain, supply.locations)
	return held

func _melee_bodies() -> Dictionary:
	var bodies: Dictionary = {}
	if not is_instance_valid(fleet_live_lab): return bodies
	for fleet_index: int in 2:
		var person: Dictionary = _crew(fleet_index, 1)
		if person.is_empty(): return {}
		var owner: Variant = person.owner
		var unit: int = int(person.unit)
		var body: Dictionary = person.row
		bodies[str(int(person.id))] = {"owner": owner.get_instance_id(), "unit": unit,
			"ref": fleet_live_lab.terrain.site.travel_identity.refs.person[str(int(person.id))].duplicate(true),
			"hp": float(owner.combat_hot_get(unit, &"hp", 0.0)), "fatigue": FleetFatigue.read(body),
			"cooldown": float(owner.combat_hot_get(unit, &"exchange_cooldown", 0.0)),
			"stun": float(owner.combat_hot_get(unit, &"stun", 0.0)),
			"hold": float(owner.combat_hot_get(unit, &"exchange_stagger", 0.0)),
			"hit_revision": int(body.get("hit_revision", 0))}
	return bodies

func _melee_effect_applied(exchange: Dictionary) -> bool:
	var interval: Dictionary = exchange.get("body_interval", {})
	if interval.is_empty() or not bool(interval.get("completed", false)) or not bool(interval.get("endpoint_consumed", false)): return false
	var paid_begin: float = float(interval.get("paid_begin", -1.0))
	var paid_end: float = float(interval.get("paid_end", -1.0))
	if not is_finite(paid_begin) or not is_finite(paid_end) or paid_begin < 0.0 or paid_end <= paid_begin: return false
	if int(exchange.sequence) < int(interval.sequence_begin) or int(exchange.sequence) > int(interval.sequence_end): return false
	var result: Dictionary = exchange.result
	for field: String in ["hp_a", "hp_b", "stun_a", "stun_b", "hold", "stagger"]:
		if not is_finite(float(result.get(field, 0.0))) or float(result.get(field, 0.0)) < 0.0: return false
	var changed: bool = false
	for side: int in [1, -1]:
		var identity: String = str(int(exchange.first if side == 1 else exchange.second))
		var before: Dictionary = interval.before.get(identity, {})
		var after: Dictionary = interval.after.get(identity, {})
		if before.is_empty() or after.is_empty() or int(before.owner) != int(after.owner) or int(before.unit) != int(after.unit) or before.ref != after.ref: return false
		for field: String in ["hp", "fatigue", "cooldown", "stun", "hold"]:
			if not is_finite(float(before[field])) or not is_finite(float(after[field])): return false
		var hp: float = float(result.get("hp_a" if side == 1 else "hp_b", 0.0))
		var stun: float = float(result.get("stun_a" if side == 1 else "stun_b", 0.0))
		var hold: float = float(result.hold) if int(result.winner) == 0 else float(result.stagger) if int(result.winner) != side else 0.0
		if hp > 0.0 and float(after.hp) >= float(before.hp): return false
		if stun > 0.0 and (float(after.stun) <= float(before.stun) or float(after.stun) + EPS < stun): return false
		if (hp > 0.0 or stun > 0.0) and int(after.hit_revision) <= int(before.hit_revision): return false
		if hold > 0.0 and float(after.hold) + EPS < hold: return false
		changed = changed or float(before.hp) != float(after.hp) or float(before.fatigue) != float(after.fatigue) \
			or float(before.cooldown) != float(after.cooldown) or float(before.stun) != float(after.stun) or float(before.hold) != float(after.hold)
	return changed

## Nekki 2026-10-26 decision B (NEKKI_DECISION_20261026T0919Z_two_npc_sea_friendly_B.md).
## Meals fall only on 6 h world boundaries (site_sustain.gd _next_meal), so at the
## 0.5 game s fine cadence the friendly case idled about 34k steps. The same main
## caller now pays genuine accepted intervals at the coarsest legal cadence
## (EXCHANGE_ACTION_STEP, the shared-step cap for this exchange-enabled Lab, at
## the original player speed control's 4x) until FLEET_FINE_MEAL_MARGIN game
## seconds before the boundary. It then restores 1x and ACTION_STEP, and the
## unchanged wait below observes the child Controller's own meal result.
## Nothing here creates a meal or moves a clock outside an accepted interval.
func _fleet_coarse_to_meal() -> bool:
	var boundary: float = FleetSustain._next_meal(float(slot.control.logical_game_seconds))
	var stop_at: float = boundary - FLEET_FINE_MEAL_MARGIN
	if float(slot.control.logical_game_seconds) >= stop_at or fleet_live_meals > 0.0: return true
	lab.change_simulation_speed(1)
	lab.change_simulation_speed(1)
	if not _check(lab.simulation_speed == 4.0, "original player speed control selects its 4x cadence for the coarse meal approach", lab.simulation_speed): return false
	fleet_step_request = TerrainLab.EXCHANGE_ACTION_STEP
	var advanced := true
	for attempt: int in range(fleet_max_attempts):
		if fleet_live_meals > 0.0 or float(slot.control.logical_game_seconds) >= stop_at: break
		if Time.get_ticks_msec() > deadline:
			advanced = _check(false, "coarse accepted intervals reach the fine margin before the next meal boundary deadline", {"world": slot.control.logical_game_seconds, "stop_at": stop_at})
			break
		if not _fleet_step():
			advanced = false
			break
		if attempt % 60 == 0: await process_frame
	fleet_step_request = TerrainLab.ACTION_STEP
	lab.change_simulation_speed(-1)
	lab.change_simulation_speed(-1)
	if not advanced: return false
	return _check(lab.simulation_speed == 1.0 and (fleet_live_meals > 0.0 or float(slot.control.logical_game_seconds) >= stop_at and float(slot.control.logical_game_seconds) < boundary),
		"coarse accepted intervals stop inside the fine margin before the meal boundary and restore the 1x cadence",
		{"world": slot.control.logical_game_seconds, "stop_at": stop_at, "boundary": boundary, "meals": fleet_live_meals})

## Failure evidence only: both bow crews, their boats' moves and the contact guards in the NPC frame host.
func _contact_facts(started: int, steps: int) -> Dictionary:
	var facts := {"wall_ms_in_wait": Time.get_ticks_msec() - started, "steps": steps, "world": slot.control.logical_game_seconds, "paid": action_paid}
	if not is_instance_valid(fleet_live_lab): return facts
	var vehicles: SiteVehicleTransport = fleet_live_lab.site_controller.vehicles
	for index: int in 2:
		var person := _crew(index, 1)
		if person.is_empty(): facts["crew_%d" % index] = "missing"; continue
		var boat: Dictionary = vehicles.ship_for_person(int(person.id))
		facts["crew_%d" % index] = {"id": person.id, "can_attack": vehicles.ship_can_attack(int(person.id)), "ground": vehicles.ship_person_ground(int(person.id)),
			"boat": boat.get("id"), "cell": fleet_live_lab.terrain.cell_from_index(int(boat.get("cell", 0))) if not boat.is_empty() else null,
			"move": boat.get("move", {}).keys(), "elapsed": boat.get("move", {}).get("elapsed"), "duration": boat.get("move", {}).get("duration"), "command": boat.get("command", {}).keys(), "job": vehicles.ship_job(str(boat.get("id", ""))).get("kind", "")}
	var a := _crew(0, 1)
	var b := _crew(1, 1)
	if not a.is_empty() and not b.is_empty(): facts["contact"] = vehicles.ship_combat_contact(int(a.id), int(b.id))
	return facts

func _real_melee() -> bool:
	var contact_a: Dictionary = _crew(0, 1)
	var contact_b: Dictionary = _crew(1, 1)
	var contact_transport: SiteVehicleTransport = fleet_live_lab.site_controller.vehicles
	if not _check(not contact_a.is_empty() and not contact_b.is_empty()
		and contact_transport.ship_local_position(int(contact_a.id)).distance_to(_contact_bow_local(contact_transport.ship_for_person(int(contact_a.id)))) <= EPS
		and contact_transport.ship_local_position(int(contact_b.id)).distance_to(_contact_bow_local(contact_transport.ship_for_person(int(contact_b.id)))) <= EPS,
		"original full cold restore and NPC frame retain both publicly paid bow positions"): return false
	var contact_started := Time.get_ticks_msec()
	var contact_steps := 0
	while not _actual_contact_ready():
		if Time.get_ticks_msec() > deadline or contact_steps >= fleet_max_attempts:
			return _check(false, "original completed boat moves release journey/moving guards and expose true crew contact", _contact_facts(contact_started, contact_steps))
		if not _fleet_step(): return false
		contact_steps += 1
		if contact_steps % 60 == 0: await process_frame
	_check(true, "original completed boat moves release journey/moving guards and expose true crew contact")
	var a := _crew(0, 1)
	var b := _crew(1, 1)
	var helm := _crew(0, 0)
	var vehicles: SiteVehicleTransport = fleet_live_lab.site_controller.vehicles
	if not _check(not vehicles.ship_can_attack(int(helm.id)) and not _initiates(helm, int(b.id), true), "real seated helm cannot initiate original melee"): return false
	if not _check(not _initiates(a, int(helm.id), true) and not _initiates(a, -999999, true) and not _initiates(a, int(b.id), false), "friendly same-boat, absent identity and nonmelee queries do not gain a naval defense order"): return false
	if fleet_case == "friendly":
		if not _check(not _initiates(a, int(b.id), true) and not _initiates(b, int(a.id), true), "real friendly frame contacts do not authorize combat"): return false
		if not await _fleet_coarse_to_meal(): return false
		if not await _fleet_until(func() -> bool: return fleet_live_meals > 0.0, "actual original NPC child Controller publishes a genuine accepted meal result"): return false
		return _check(fleet_exchanges.is_empty(), "friendly actual paid frame produces no hostile exchange")
	if not _check(_initiates(a, int(b.id), true) and _initiates(b, int(a.id), true), "actual lawful nonhelm HOLD crews receive only original current defensive contact authorization"): return false
	if _native_frame(): return await _native_melee(a, b)
	if not await _fleet_until(func() -> bool: return not fleet_exchanges.is_empty(), "actual main paid caller resolves the genuine original reciprocal melee pair"): return false
	a = _crew(0, 1); b = _crew(1, 1)
	var sequences := {}
	var physical_effects: bool = true
	for exchange: Dictionary in fleet_exchanges:
		var key := "%s:%d:%d" % [str(exchange.sequence), mini(int(exchange.first), int(exchange.second)), maxi(int(exchange.first), int(exchange.second))]
		if not _check(not sequences.has(key), "original reciprocal pair is observed once per accepted ACTION sequence", key): return false
		sequences[key] = true
		physical_effects = physical_effects and _melee_effect_applied(exchange)
	return _check(not fleet_exchanges.is_empty() and physical_effects and fleet_live_lab._region_point_pending.is_empty(), "genuine accepted original exchange changes real life/fatigue/cooldown effects after its endpoint is consumed", {"exchanges": fleet_exchanges})

## Native contact frame (Nekki 2026-11-10 A): the crowd resolves melee natively, with no GD exchange_resolved pair. The
## accepted evidence is the bow crews' own bodies: a hit lands (life or hit revision changes) on a paid step, the frame's
## endpoint is consumed, and every other body of both fleets stays in the frame.
func _native_melee(a: Dictionary, b: Dictionary) -> bool:
	var before := _melee_bodies()
	if not _check(before.size() == 2, "both bow crews are readable native bodies before melee", before): return false
	var landed := func() -> bool:
		var now := _melee_bodies()
		if now.size() != 2: return true # A fallen crew leaves the frame's readable bodies: that is a landed blow too.
		for key: String in before:
			if not now.has(key): return true
			if float(now[key].hp) < float(before[key].hp) - EPS or int(now[key].hit_revision) != int(before[key].hit_revision): return true
		return false
	if not await _fleet_until(landed, "actual main paid caller lets the native crowd resolve the bow crews' melee"): return false
	var after := _melee_bodies()
	print("FLEET_NATIVE_MELEE ", JSON.stringify({"before": before, "after": after, "world": slot.control.logical_game_seconds}))
	return _check(fleet_live_lab._region_point_pending.is_empty() and fleet_live_lab.crowd_site.active, "native melee lands on a consumed paid endpoint and the frame stays a live native crowd", {"before": before, "after": after})

## Wall-clock phase marks (evidence only): each phase's elapsed milliseconds since the previous mark.
var fleet_phase_marks: Array = []
var fleet_phase_last := 0
func _fleet_phase(label: String) -> void:
	var now := Time.get_ticks_msec()
	fleet_phase_marks.append([label, now - fleet_phase_last, action_paid, slot.control.logical_game_seconds if slot != null else -1.0])
	fleet_phase_last = now
	print("FLEET_PHASE ", label, " ms=", fleet_phase_marks[-1][1], " paid=", action_paid)

func _run() -> void:
	fleet_phase_last = Time.get_ticks_msec()
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _check(fleet_case in ["hostile", "friendly"], "one original hostile or friendly actual two-fleet case", fleet_case): _finish(); return
	if not _write_manifest() or not _setup_action_world(): _finish(); return
	_fleet_phase("genesis")
	fleet_observation = "public_work"
	if not await _public_fit(0): _finish(); return
	_fleet_phase("public_fit_0")
	if not await _fleet_remote_decision_a(): _finish(); return
	if not _fleet_identities(): _finish(); return
	_fleet_phase("remote_decision_a")
	if not await _fleet_reopen(): _finish(); return
	_fleet_phase("first_reopen")
	for index: int in 2:
		if not _fleet_dispatch(index): _finish(); return
	var far: Dictionary = slot._region_npc_sea_pair_boundary(str(fleets[0].token), str(fleets[1].token))
	if not _check(far.ok and not far.get("contact", false), "same original ocean component with distant true hulls is not contact", far): _finish(); return
	_fleet_phase("paid_partial_sea")
	fleet_observation = "paid_partial_sea"
	if not await _fleet_until(_has_partial, "actual original NPC cursors retain a real paid partial ship step") or not _original_partial_refusals() or not await _fleet_reopen() or not _original_partial_refusals(): _finish(); return
	_fleet_phase("actual_npc_frame")
	fleet_observation = "actual_npc_frame"
	if not await _fleet_until(_has_actual_frame, "same original earliest-boundary consumer publishes the true two-NPC frame") or not _bind_live_observer(): _finish(); return
	var incoming := str(fleets[0].token) if fleet_primary == str(fleets[1].token) else str(fleets[1].token)
	if not _check(slot.region_registry().parties[incoming].phase == "joined" and slot.region_registry().parties[incoming].entered_party == fleet_primary and slot.region_registry().parties[fleet_primary].phase == "travelling", "one actual incoming closure joins the same primary NPC owner exactly once"): _finish(); return
	_fleet_phase("frame_bound")
	if not await _fleet_reopen(): _finish(); return
	_fleet_phase("frame_reopen")
	if not await _real_melee() or not _food_results(): _finish(); return
	_fleet_phase("melee_or_meal")
	# Native frame (Nekki 2026-11-10 A): a checkpoint and fresh reopen after the frame stepped as a crowd restores the same
	# party, which converts again on its next interval and keeps stepping.
	if _native_frame():
		if not await _fleet_reopen(): _finish(); return
		_fleet_phase("native_frame_reopen")
		for extra: int in 240:
			if not _fleet_step(): _finish(); return
			if extra % 60 == 0: await process_frame
		if not _check(_native_frame() and not _crew(0, 1).is_empty() and not _crew(1, 1).is_empty(), "the reopened frame converts again and keeps both bow crews as native bodies"): _finish(); return
		_fleet_phase("native_frame_continue")
	var held := _live_food_held()
	if not _check(held >= 0.0 and absf(held + fleet_meals - 12.0) <= EPS, "real mapped two-boat held plus actual accepted original consumption conserves all twelve delivered rations", {"held": held, "accepted_consumed": fleet_meals, "live_controller_consumed": fleet_live_meals}): _finish(); return
	report["two_npc_sea"] = {"case": fleet_case, "fleets": fleets, "primary": fleet_primary, "paid_action": action_paid, "paid_game": action_game_paid, "cold": fleet_cold, "exchanges": fleet_exchanges, "actual_food_results": fleet_food, "all_six_cases": "OPEN_NOT_RUN"}
	_finish()

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	finished = true; failed = failed or not ok; paused = false
	if not message.is_empty(): printerr(message)
	if is_instance_valid(genesis_panel): genesis_panel.free()
	for scene: TerrainLab in capture_scenes:
		if is_instance_valid(scene): scene.free()
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(Entry.LAST_WORLD)) if FileAccess.file_exists(Entry.LAST_WORLD) else null
	if current is Dictionary and str(current.get("world_id", "")) == world_id:
		if last_world_exists:
			var restored := FileAccess.open(Entry.LAST_WORLD, FileAccess.WRITE); restored.store_buffer(last_world_bytes); restored.close()
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(Entry.LAST_WORLD))
	TerrainArmy.release_contact_source()
	print("FLEET_PHASES ", fleet_phase_marks, " tail_ms=", Time.get_ticks_msec() - fleet_phase_last)
	var receipt := {"failed": failed, "checks": checks, "case": fleet_case, "report": report, "checks_evidence": action_evidence, "scope": "Source-authored actual original public work, two NPC Nation sea dispatches, full cold owners, first conservative frame, paid original contact and real melee/food outcomes; GD/parser/runtime/all-six/native/performance OPEN until sole Root runner"}
	var file := FileAccess.open(out.path_join("two_npc_sea_public_contact_receipt.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(receipt, "\t", true, true)); file.close()
	print("REGION_TWO_NPC_SEA_PUBLIC_CONTACT_", "FAILED" if failed else "PASS", " ", fleet_case, " checks=", checks)
	quit(1 if failed else 0)

func _fleet_reservation_observation(paid: bool) -> bool:
	if not is_instance_valid(fleet_live_lab): return true
	var vehicles: SiteVehicleTransport = fleet_live_lab.site_controller.vehicles
	var boats: Array[Dictionary] = []
	for index: int in 2:
		var person := _crew(index, 1)
		if person.is_empty(): return _check(false, "reservation observer keeps actual stable bow crew", _crew_facts(index))
		boats.append(vehicles.records()[str(person.row.embarked_vehicle_id)])
	var first: Dictionary = vehicles._claims(boats[0])
	var second: Dictionary = vehicles._claims(boats[1])
	# One check per observed step names every shared cell (none expected), rather
	# than one evidence row per claimed cell; the per-step proof is unchanged.
	var shared: Array[Vector2i] = []
	for cell: Vector2i in first:
		if second.has(cell): shared.append(cell)
	if not _check(shared.is_empty(), "actual current hulls and accepted original sweeps never share a reserved cell", shared): return false
	for boat: Dictionary in boats:
		if boat.move.is_empty(): continue
		if not _check(float(boat.move.elapsed) >= 0.0 and (not paid or float(boat.move.elapsed) > 0.0) and float(boat.move.elapsed) <= float(boat.move.duration) and not boat.move.sweep.is_empty(), "actual original Vehicle reservation is advanced only by a genuine accepted positive interval"): return false
	return true
