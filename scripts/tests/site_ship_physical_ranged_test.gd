extends "res://scripts/tests/site_ship_combat_test.gd"
## Physical ranged fire from an afloat ship (default physical_ranged_enabled = true).
## Same original boarding fixture as site_ship_combat_test; only the fire mode differs.
## One original reservation, one debit from the shooter's own cargo, one real flight from the
## deck point, and one original contact resolution (person, ground, or boundary).

const Renderer = preload("res://scripts/terrain_lab/terrain_renderer.gd")
const STEP := 1.0 / 30.0

func _run() -> void:
	if not _must(DisplayServer.get_name() == "headless", "Canonical headless fixture required"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army_owner: TerrainArmy in lab.combat_armies: army_owner.set_process(false)
	_water_fixture()
	team = lab.army
	other = lab.opposing_army
	team.team_id = lab._next_army_identity()
	other.team_id = team.team_id + 1
	lab.terrain.site.army_next_team = other.team_id + 1
	for owner: TerrainArmy in [team, other]:
		owner.roster_size = 2
		owner.role = "logistics"
		owner.exchange_enabled = true
	lab.exchange_enabled = true
	lab.physical_ranged_enabled = true # Default mode under test; no legacy override.
	var first_cells: Array[Vector2i] = [Vector2i(29, 20), Vector2i(28, 20)]
	var second_cells: Array[Vector2i] = [Vector2i(29, 25), Vector2i(28, 25)]
	if not _must(team.deploy_at(lab.terrain, lab.character, lab.npc, first_cells) and team.enable_combat(false, 0), "First original roster admission"): return
	if not _must(other.deploy_at(lab.terrain, lab.character, lab.npc, second_cells) and other.enable_combat(false, 0), "Second original roster admission"): return
	for index in range(2):
		people.append(team.combat_identity(index))
		enemy_ids.append(other.combat_identity(index))
		team.combat_units[index].logistics = true
		other.combat_units[index].logistics = true
	if not _must(people[0] != enemy_ids[0] and team.faction_id != other.faction_id, "Distinct original opponents"): return
	lab.terrain.site.controlled_person_id = people[0]
	var source: Dictionary = team.combat_units[0]
	var made: Dictionary = Runtime.create_equipment(lab.terrain, source.item_state, "ship_physical_bow",
		{"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, people[0])
	if not _must(made.ok, "Original bow allocation: " + str(made)): return
	var equipped: Dictionary = lab.site_controller.equipment_orders.begin_personal(people[0], "weapon", str(made.item_id))
	if not _must(equipped.ok, "Original bow wearing: " + str(equipped)) or not _job(people[0]): return
	source.cargo.arrow = 4 # Explicit fixture ammunition belongs to the shooter's own row.
	var cargo: Dictionary = source.cargo
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var a: Dictionary = vehicles.deploy_ship(team, "ferry", Vector2i(30, 20), Vector2i.UP, true)
	var b: Dictionary = vehicles.deploy_ship(other, "ferry", Vector2i(30, 25), Vector2i.UP, true)
	if not _must(a.ok and b.ok, "Two original test hulls: " + str([a, b])): return
	var first_id := str(a.vehicle_id)
	var second_id := str(b.vehicle_id)
	if not _board_pair(team, people, first_id) or not _board_pair(other, enemy_ids, second_id): return
	if not _must(lab.physical_ranged_enabled, "Physical ranged is the active default for this ship case"): return
	if not _must(vehicles.ship_can_attack(people[0]) and team.exchange_ready(0), "Afloat original archer readiness"): return
	var source_cell := vehicles.ship_person_cell(people[0])
	var deck_ground := vehicles.ship_person_ground(people[0])
	if not _must(source_cell != team.cells[0] and not lab.terrain.is_walkable(source_cell), "Physical source is the deck water cell, not the historical shore"): return
	if not _must(team.combat_ground(0).is_equal_approx(deck_ground), "Army ground for an embarked archer is the real deck world point"): return

	# Preparation reserves only; the shooter's own cargo is debited at the original commit.
	# Explicit controlled attack sets the original unit target, so exchange_initiates admits the fire path.
	if not _must(lab.controlled_attack(enemy_ids[0]), "Controlled original aboard attack order"): return
	var shooter := {"owner": team, "unit": 0, "id": people[0], "cell": team.cells[0], "faction": team.faction_id}
	var reserved: Dictionary = lab.request_fire_release(shooter, {"type": "person", "person_id": enemy_ids[0]})
	if not _must(reserved.ok, "Physical preparation accepted from the deck: " + str(reserved)): return
	if not _must(lab.fire_reservations.size() == 1 and int(cargo.arrow) == 4 and lab.ranged_shots == 0, "Preparation reserves without debiting cargo"): return
	var ticks := 0
	while lab.ranged_shots == 0 and ticks < ceili(5.0 / STEP):
		lab._advance_combat(STEP, 0.0)
		ticks += 1
	if not _must(lab.ranged_shots == 1 and int(cargo.arrow) == 3 and lab.fire_projectiles.size() == 1, "Exactly one arrow leaves the shooter's cargo and one flight exists"): return
	var flight: Dictionary = lab.fire_projectiles[0]
	if not _must(int(flight.source_member_id) == people[0] and int(flight.projectile_id) > 0 and float(flight.life) > 0.0, "Flight belongs to the original shooter with positive life"): return
	var launch := Vector2(flight.position.x, flight.position.y) * Renderer.CELL_PIXELS
	if not _must(launch.distance_to(deck_ground) < 48.0, "Flight launches from the deck point, not the shore cell: " + str([launch, deck_ground])): return
	# The original flight resolves through contact on water, ground, or the boundary.
	ticks = 0
	var limit := ceili((float(flight.life) + 2.0) / STEP)
	while not lab.fire_projectiles.is_empty() and ticks < limit:
		lab._advance_combat(STEP, 0.0)
		ticks += 1
	if not _must(lab.fire_projectiles.is_empty() and lab.ranged_resolutions == 1 and lab.fire_impact_recorder.size() == 1, "Physical flight resolves exactly once"): return
	var impact: Dictionary = lab.fire_impact_recorder[0]
	if not _must(int(impact.projectile_id) == int(flight.projectile_id) and str(impact.type) in ["person", "ground", "boundary"], "Resolution is an original contact event: " + str(impact)): return
	if not _must(int(cargo.arrow) == 3 and is_same(cargo, source.cargo) and lab.fire_reservations.is_empty(), "Resolution never duplicates or refunds ammunition"): return
	print("SHIP_PHYSICAL_RANGED_PASS default physical deck launch, one debit, real flight, original resolution")
	lab.queue_free()
	await process_frame
	quit(0)
