extends SceneTree

const Data = preload("res://scripts/terrain_lab/terrain_data.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
const HULL_COUNTS := {"ferry": 10, "river": 5, "coastal": 4, "troop": 2, "patrol": 4, "tower": 1}

var deadline := 0
var lab: TerrainLab
var team: TerrainArmy
var people: Array[int] = []
var original_rows: Array[Dictionary] = []
var original_holders: Array[Dictionary] = []
var original_goods: Array[Dictionary] = []
var original_items: Array[Array] = []

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 60000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Hundred-person ship fleet contract deadline")
		quit(1)
	return false

func _fixture() -> Array[Vector2i]:
	# This is explicit navigable test water, not a generated-map JSON roundtrip.
	var data := lab.terrain
	assert(data.contains(Vector2i(95, 90)))
	for y in range(10, 91):
		for x in range(2, 96):
			var i := data.index(Vector2i(x, y))
			assert(int(data.feature_at[i]) == 0, "Fleet fixture cannot replace a real building")
			var water := x >= 20
			data.height_levels[i] = 0
			data.ramp_edges[i] = 0
			data.static_blocked[i] = 0
			data.flags[i] = Data.Flag.BLOCKED | Data.Flag.WET if water else Data.Flag.WALKABLE
			data.surface_types[i] = Data.Surface.WATER if water else Data.Surface.GRASS
			data.water_kind[i] = 1 if water else 0
			data.water_body[i] = 98765 if water else -1
			for key: String in data.resources_at.get(i, []):
				Env.change(data, key, {"cleared": true, "remaining": 0})
	data.parameters.navigable_water_version = 1
	data.parameters.navigable_water_bodies = [98765]
	data.parameters.erase("navigable_water_cells")
	Env.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	var cells: Array[Vector2i] = []
	for y in range(14, 80):
		for x in range(3, 19):
			var cell := Vector2i(x, y)
			if lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell): continue
			cells.append(cell)
			if cells.size() == 100: return cells
	assert(false, "Fixture requires a hundred distinct original shore positions")
	return cells

func _reset_fleet() -> void:
	# Test-only fixture reset. No live job, committed movement, cargo or death is discarded.
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	assert(lab.site_controller.person_actions._jobs.is_empty())
	for vehicle: Dictionary in vehicles.records().values():
		assert(str(vehicle.kind) == "ship" and vehicle.move.is_empty() and vehicle.command.is_empty())
		assert(vehicle.cargo.is_empty() and vehicle.holder.item_ids.is_empty() and vehicle.holder.equipped.is_empty())
	for row: Dictionary in team.combat_units:
		row.erase("embarked_vehicle_id")
		row.erase("berth_id")
	vehicles.records().clear()
	for identity: int in people: team.ship_embarkation_changed(identity)
	assert(not vehicles.team_has_embarked(team.team_id))
	assert(team._cell_owners.size() == 100)

func _assert_original_people() -> void:
	assert(team.combat_units.size() == 100 and team.roster_size == 100 and team.living_member_count() == 100)
	for index in range(100):
		var row: Dictionary = team.combat_units[index]
		assert(team.combat_identity(index) == people[index] and is_same(row, original_rows[index]))
		assert(is_same(row.item_state, original_holders[index]) and row.cargo == original_goods[index])
		assert(row.item_state.item_ids == original_items[index] and float(team.combat_hot_get(index, &"hp", 0.0)) == 100.0)
		assert(team.is_member(index), "Fleet allocation never creates a separate passenger roster")

func _minimum_crew_navigation(kind: String, vehicle_id: String) -> void:
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var spec: Dictionary = Ship.definition(kind)
	var boat: Dictionary = vehicles.records()[vehicle_id]
	var minimum := int(spec.min_crew)
	var standard := int(spec.standard_crew)
	var original_ko: Array[float] = []
	# Temporary KO inputs stay in the original hot store, using the existing rows.
	# No synthetic crew list or person is introduced, and every input is restored.
	for index in range(standard):
		original_ko.append(float(team.combat_hot_get(index, &"ko", 0.0)))
		team.combat_hot_set(index, &"ko", SiteCombatRules.KNOCKOUT_GAME_SECONDS if index >= minimum - 1 else 0.0)
	var before: Dictionary = boat.duplicate(true)
	var load: float = vehicles.ship_load(vehicle_id)
	assert(vehicles.ship_crew_count(boat) == minimum - 1)
	var rejected: Dictionary = vehicles.ship_order(vehicle_id, "forward", TerrainArmy.INVALID_CELL, people[0], true)
	assert(rejected.code == ("BUSY" if minimum == 1 else "NO_CREW"), "%s below-minimum original crew must reject: %s" % [kind, str(rejected)])
	assert(boat == before and vehicles.ship_people(boat).size() == int(spec.max_people) and is_equal_approx(vehicles.ship_load(vehicle_id), load))
	team.combat_hot_set(minimum - 1, &"ko", 0.0)
	assert(vehicles.ship_driver_ready(boat) and vehicles.ship_crew_count(boat) == minimum)
	assert(vehicles.ship_contacts(boat).is_empty(), "Fleet speed fixture is away from the shoreline cap")
	var committed: Dictionary = vehicles.ship_order(vehicle_id, "forward", TerrainArmy.INVALID_CELL, people[0], true)
	assert(committed.ok and not boat.move.is_empty(), "%s minimum crew must commit: %s" % [kind, str(committed)])
	var target := int(boat.move.cell)
	var duration := float(boat.move.duration)
	assert(is_equal_approx(duration, 1.0 / Ship.speed(kind, int(spec.max_people), load, minimum)), "Actual minimum-crew sailing uses the canonical speed formula")
	assert(vehicles.ship_order(vehicle_id, "stop", TerrainArmy.INVALID_CELL, people[0], true).ok)
	vehicles.update_ships(duration + 0.01)
	assert(int(boat.cell) == target and boat.move.is_empty() and boat.command.is_empty() and not bool(boat.stop_pending))
	assert(is_equal_approx(vehicles.ship_load(vehicle_id), load))
	for index in range(standard): team.combat_hot_set(index, &"ko", original_ko[index])
	assert(vehicles.ship_crew_count(boat) == standard and vehicles.ship_driver_ready(boat))
	print("SITE_SHIP_FLEET_MIN_CREW_PASS:%s:minimum=%d" % [kind, minimum])

func _fleet(kind: String) -> void:
	_reset_fleet()
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var spec: Dictionary = Ship.definition(kind)
	var hulls := int(HULL_COUNTS[kind])
	var seats := int(spec.max_people)
	var boat_ids: Array[String] = []
	for hull in range(hulls):
		var anchor := Vector2i(32 + (hull % 5) * 12, 32 + floori(float(hull) / 5.0) * 24)
		var deployed: Dictionary = vehicles.deploy_ship(team, kind, anchor, Vector2i.UP, true)
		assert(deployed.ok, str(deployed))
		boat_ids.append(str(deployed.vehicle_id))
	# Boarding transactions are covered by site_ship_transport_test. Here a legal
	# attachment fixture isolates all six real fleets without copying any body/items.
	for index in range(100):
		var hull := floori(float(index) / seats)
		var row: Dictionary = team.combat_units[index]
		row.embarked_vehicle_id = boat_ids[hull]
		row.berth_id = index % seats
	for index in range(100): team.ship_boarded(index)
	var seen_people := {}
	var total_load := 0.0
	for hull in range(hulls):
		var id := boat_ids[hull]
		var boat: Dictionary = vehicles.records()[id]
		boat.operator_id = people[hull * seats]
		var aboard: Array[Dictionary] = vehicles.ship_people(boat)
		assert(aboard.size() == seats and int(boat.team_id) == team.team_id)
		var berths := {}
		var expected_load := 0.0
		for person: Dictionary in aboard:
			assert(not seen_people.has(int(person.id)))
			seen_people[int(person.id)] = true
			var berth := int(person.row.berth_id)
			assert(berth >= 0 and berth < seats and not berths.has(berth))
			berths[berth] = true
			expected_load += Runtime.carried_load(lab.terrain.site, person.cargo, person.holder) + float(person.holder.equipped.size())
			assert(team.moving_to[int(person.unit)] == TerrainArmy.INVALID_CELL and not team._cell_owners.values().has(int(person.unit)))
		assert(vehicles.ship_driver_ready(boat) and vehicles.ship_crew_count(boat) == int(spec.standard_crew))
		assert(is_equal_approx(vehicles.ship_load(id), expected_load) and expected_load <= float(spec.capacity))
		total_load += expected_load
	assert(seen_people.size() == 100 and vehicles.records().size() == hulls)
	assert(vehicles.team_vehicle_count(team) == 0, "Hull count is not a deduction from the hundred original persons")
	_assert_original_people()
	var expected_total := 0.0
	for index in range(100):
		expected_total += Runtime.carried_load(lab.terrain.site, original_goods[index], original_holders[index]) + float(original_holders[index].equipped.size())
	assert(is_equal_approx(total_load, expected_total), "Across every hull, every real item contributes to Q exactly once")
	lab.site_controller._capture_positions()
	var checked: Dictionary = Store._validate_vehicles(lab.terrain, lab.terrain.site, true)
	assert(checked.ok, "%s hundred-person candidate: %s" % [kind, str(checked)])
	var corrupted: Dictionary = lab.terrain.site.duplicate(true)
	corrupted.armies[0].units[1].berth_id = 0
	assert(not Store._validate_vehicles(lab.terrain, corrupted, true).ok, "Saved fleet cannot alias a living berth")
	corrupted = lab.terrain.site.duplicate(true)
	var first_id := boat_ids[0]
	var first_boat: Dictionary = vehicles.records()[first_id]
	var excess: int = floori(float(spec.capacity) - vehicles.ship_load(first_id)) + 1
	corrupted.vehicles[first_id].cargo.grain = excess
	assert(not Store._validate_vehicles(lab.terrain, corrupted, true).ok, "Saved full-fleet Q includes passenger equipment")
	corrupted = lab.terrain.site.duplicate(true)
	corrupted.vehicles[first_id].operator_id = people[1]
	assert(not Store._validate_vehicles(lab.terrain, corrupted, true).ok, "Duty must remain with the real helm berth occupant")
	var before: Dictionary = vehicles.records().duplicate(true)
	var depot_before: Dictionary = lab.terrain.site.inventory.duplicate(true)
	assert(vehicles.ship_transfer_guard(lab.terrain.site.depot_items, first_boat.holder, {"grain": excess}, []).code == "CAPACITY")
	assert(vehicles.records() == before and lab.terrain.site.inventory == depot_before)
	_minimum_crew_navigation(kind, first_id)
	_assert_original_people()
	print("SITE_SHIP_FLEET_KIND_PASS:%s:people=100:boats=%d:Q=%.2f" % [kind, hulls, total_load])

func _run() -> void:
	assert(DisplayServer.get_name() == "headless")
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)
	var cells := _fixture()
	team = lab.army
	team.role = "logistics"
	team.team_id = lab._next_army_identity()
	team.roster_size = 100
	assert(team.deploy_at(lab.terrain, lab.character, lab.npc, cells) and team.enable_combat(false, 0))
	lab.terrain.site.army_next_team = team.team_id + 1
	lab.terrain.site.army_trial_active = true
	assert(lab.site_controller.vehicles.records().is_empty() and lab.terrain.site.ground_loot.is_empty())
	var seen := {}
	for index in range(100):
		var row: Dictionary = team.combat_units[index]
		var identity := team.combat_identity(index)
		assert(identity > 0 and not seen.has(identity))
		seen[identity] = true
		people.append(identity)
		row.logistics = true
		original_rows.append(row)
		original_holders.append(row.item_state)
		original_goods.append(row.cargo.duplicate(true))
		original_items.append(row.item_state.item_ids.duplicate())
	for kind: String in Ship.KINDS: _fleet(kind)
	print("SITE_SHIP_FLEET_PASS")
	quit(0)
