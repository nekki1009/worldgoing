extends "res://scripts/tests/site_siege_ram_compound_test.gd"
## Output-only: actual original person approach, original navigation edge bits,
## and the original Coordinator external reservation input. No fake grid/clock.
var turn_edge_groups := 0

func _run() -> void:
	create_timer(90.0).timeout.connect(func() -> void: quit(3))
	for mode: String in ["station_person", "route_edge", "reservation_only", "sweep_person"]:
		if not _turn_edge(mode): return
	if not _committed_rotation_crew_loss(): return
	if not _require(turn_edge_groups == 5, "All five turn-admission and committed-loss groups must finish before PASS"): return
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_TURN_ADMISSION_EDGES_PASS: occupied original rig station, inaccessible original navigation edges, reservation-only original Grid rejection, real sweep-only Actor, already-arrived crew stay in place, blocker leaves by original single step then real rotation; original committed rotation survives below-minimum crew KO without rollback/new attack; headless GD owner/admission only, no native/GPU claim")
	quit(0)

func _turn_tick(context: Dictionary, seconds: float, reservations: Dictionary) -> void:
	var remaining := seconds
	while remaining > 0.000000001:
		var dt := minf(0.05, remaining)
		context.controller.vehicles.update_siege(dt)
		var external_reservations: Dictionary = reservations.duplicate()
		external_reservations.merge(context.lab._combat_actor_blocked_cells())
		context.coordinator.combat_logic_tick(dt, external_reservations)
		context.fixture.army.prepare_combat(dt)
		context.coordinator.complete_committed_moves()
		context.lab._advance_siege(dt)
		remaining -= dt

func _turn_edge(mode: String) -> bool:
	var context: Dictionary = _ram_fixture()
	var data: TerrainData = context.data
	var army: TerrainArmy = context.fixture.army
	var vehicle: Dictionary = context.vehicle
	var transport: SiteVehicleTransport = context.controller.vehicles
	var blocked_slot := "2"
	var station: Vector2i = transport.crew_cell(vehicle, blocked_slot, true)
	var stationary_actor: TerrainTestCharacter
	var reservations := {}
	var edge_index := data.index(station)
	var saved_ramp := int(data.ramp_edges[edge_index])
	var saved_walk_ramp := int(data.walk_ramp_edges[edge_index])
	var actor_source: Vector2i = station if mode == "station_person" else data.cell_from_index(int(vehicle.cell)) + Vector2i(3, 3)
	if mode in ["station_person", "sweep_person"]:
		stationary_actor = TerrainTestCharacter.new()
		stationary_actor.data = data
		stationary_actor.person_id = 99102 if mode == "sweep_person" else 99101 # Initial original Actor identity, before turn command/admission.
		stationary_actor.faction_id = army.faction_id
		if not _require(stationary_actor.place(actor_source, true), "Initial original Actor occupies only this requested gate"): return false
		context.lab.combat_actors.append(stationary_actor)
		# Original deploy_at binds this same Actor reference for direct original foot-step occupancy checks.
		army.player = stationary_actor
	elif mode == "route_edge":
		# The station and sweep stay natural/walkable/unoccupied. Only all four
		# existing terrain navigation edge prohibitions deny entry to this goal.
		data.ramp_edges[edge_index] = saved_ramp | 0xf0
		data.walk_ramp_edges[edge_index] = saved_walk_ramp | 0xf0
		data.navigation_revision += 1
		for direction: Vector2i in TerrainData.DIRECTIONS:
			if not _require(not data.can_step(station + direction, station), "Original route edge rejects entry but does not replace the cell surface"): return false
	elif mode == "reservation_only":
		# This is the same external actor/in-flight reservation input consumed
		# by production Coordinator; no terrain or live-body occupant is added.
		reservations[Vector2i(22, 22)] = true
	var anchor_before := int(vehicle.cell)
	var hp_before := float(vehicle.hp)
	var identities: Array[int] = []
	for index in range(army.combat_units.size()): identities.append(army.combat_identity(index))
	if not _require(transport.order_siege(context.key, "turn", {"facing": [0, 1]}, int(context.commander), true).ok, "Original turn command begins real approach"): return false
	_turn_tick(context, 8.0, reservations)
	if not _require(str(vehicle.action.get("stage", "")) == "approach" and float(vehicle.action.elapsed) == 0.0
		and vehicle.facing == [1, 0] and int(vehicle.cell) == anchor_before and float(vehicle.hp) == hp_before
		and vehicle.move.is_empty() and vehicle.action.sweep.is_empty(), "Blocked turn must not commit any body rotation/translation/HP/claim: " + mode): return false
	if mode == "sweep_person":
		var sweep: Array[int] = transport._turn_sweep(vehicle)
		if not _require(sweep.has(data.index(actor_source)) and not SiteRuntime.siege_cells(data, vehicle).has(actor_source)
			and transport._turn_crew_ready(vehicle) and transport._turn_contacts_valid(vehicle)
			and not transport._turn_fits(vehicle, sweep) and reservations.is_empty()
			and data.is_walkable(actor_source) and int(data.feature_at[data.index(actor_source)]) == 0,
			"Only a real Actor inside rotation sweep blocks; every original station/path/rope is already ready"): return false
	elif mode == "reservation_only":
		if not _require(transport._turn_crew_ready(vehicle) and transport._turn_fits(vehicle, transport._turn_sweep(vehicle))
			and context.coordinator.movement_reservation_grid.blocked_destinations.has(Vector2i(22, 22)), "Reservation-only gate has all real stations ready and otherwise valid physical sweep"): return false
	else:
		if not _require(army.cells[army.index_for_identity(int(vehicle.crew_slots[blocked_slot]))] != station and not transport._turn_crew_ready(vehicle), "Real blocked station remains unarrived"): return false
	var arrived := {}
	for slot: String in vehicle.crew_slots:
		var index := army.index_for_identity(int(vehicle.crew_slots[slot]))
		if army.cells[index] == transport.crew_cell(vehicle, slot, true): arrived[index] = army.cells[index]
	if not _require(arrived.size() == 4 if mode == "sweep_person" else arrived.size() >= 3, "Required original crew genuinely reached rig stations despite this gate: " + mode): return false
	_turn_tick(context, 1.0, reservations)
	for index: int in arrived:
		if not _require(army.cells[index] == arrived[index] and army.moving_to[index] == TerrainArmy.INVALID_CELL,
			"Already-arrived original crew cannot roll back while waiting: " + mode): return false
	for index in range(identities.size()):
		if not _require(army.combat_identity(index) == identities[index], "Turn rejection retains each original person identity"): return false
	if mode in ["station_person", "sweep_person"]:
		var away: Vector2i = Vector2i.RIGHT if mode == "sweep_person" else Vector2i.LEFT
		if not _require(stationary_actor.step(away) and stationary_actor.is_moving() and stationary_actor.movement_from_cell == actor_source, "Real blocking Actor commits one original adjacent departure, without a position write"): return false
		var departure_reservations: Dictionary = context.lab._combat_actor_blocked_cells()
		if not _require(departure_reservations.has(actor_source) and departure_reservations.has(stationary_actor.terrain_cell), "Original Lab occupancy gather retains both real Actor endpoints while departure is in flight"): return false
		# Same original Actor movement owner used by the existing station fixture.
		stationary_actor.advance_combat(1.0)
		if not _require(not stationary_actor.is_moving() and stationary_actor.terrain_cell == actor_source + away, "Original body genuinely leaves before rotation admission"): return false
		var settled_reservations: Dictionary = context.lab._combat_actor_blocked_cells()
		if not _require(not settled_reservations.has(actor_source) and settled_reservations.has(stationary_actor.terrain_cell), "Original Lab occupancy gather releases the source only after the real adjacent Actor step settles"): return false
		if mode == "sweep_person" and not _require(not transport._turn_sweep(vehicle).has(data.index(stationary_actor.terrain_cell))
			and transport._turn_crew_ready(vehicle) and transport._turn_contacts_valid(vehicle)
			and transport._turn_fits(vehicle, transport._turn_sweep(vehicle)), "Only the original sweep body departure makes the unchanged physical plan eligible"): return false
	elif mode == "route_edge":
		data.ramp_edges[edge_index] = saved_ramp
		data.walk_ramp_edges[edge_index] = saved_walk_ramp
		data.navigation_revision += 1
	reservations.clear()
	var saw_rotate := false
	for tick in range(320):
		_turn_tick(context, 0.05, reservations)
		saw_rotate = saw_rotate or str(vehicle.action.get("stage", "")) == "rotate"
		if vehicle.action.is_empty() and transport.crew_ready(vehicle): break
	if not _require(saw_rotate and vehicle.action.is_empty() and transport.crew_ready(vehicle)
		and vehicle.facing == [0, 1] and int(vehicle.cell) == anchor_before and float(vehicle.hp) == hp_before,
		"After original blocker release the same original approach/rotation/return genuinely completes: " + mode): return false
	_close_ram(context)
	turn_edge_groups += 1
	return true

func _committed_rotation_crew_loss() -> bool:
	# Two genuine original crew are exactly the RAM minimum. One original KO
	# after real Grid admission drops below it; no status/position reset is used.
	var context: Dictionary = _ram_fixture(2)
	var army: TerrainArmy = context.fixture.army
	var vehicle: Dictionary = context.vehicle
	var transport: SiteVehicleTransport = context.controller.vehicles
	var anchor: int = int(vehicle.cell)
	var original_ids: Array[int] = []
	var original_rows: Array[Dictionary] = []
	var holders: Array[Dictionary] = []
	var cargo: Array[Dictionary] = []
	for index in range(army.combat_units.size()):
		original_ids.append(army.combat_identity(index))
		original_rows.append(army.combat_units[index])
		holders.append(army.combat_units[index].item_state)
		cargo.append(army.combat_units[index].cargo)
	var vehicle_holder: Dictionary = vehicle.holder
	var vehicle_cargo: Dictionary = vehicle.cargo
	var hp_before: float = float(vehicle.hp)
	var sequence: int = int(vehicle.next_attack_seq)
	if not _require(transport.order_siege(context.key, "turn", {"facing": [0, 1]}, int(context.commander), true).ok, "Minimum original RAM crew requests real turn"): return false
	for tick in range(200):
		_turn_tick(context, 0.05, {})
		if str(vehicle.action.get("stage", "")) == "rotate": break
	if not _require(str(vehicle.action.get("stage", "")) == "rotate" and transport._turn_crew_ready(vehicle)
		and not vehicle.action.sweep.is_empty() and float(vehicle.action.elapsed) < float(SiteRuntime.SIEGE_DEFINITIONS.ram.turn_seconds),
		"Original Grid must actually commit rotation before any casualty"): return false
	var endpoints: Array[Vector2i] = army.cells.duplicate()
	var frozen_sweep: Array[int] = []
	frozen_sweep.assign(vehicle.action.sweep)
	var elapsed_before: float = float(vehicle.action.elapsed)
	var casualty_id: int = army.combat_identity(1)
	var casualty_hp: float = float(army.combat_hot_get(1, &"hp"))
	var hit_before: int = int(army.combat_units[1].get("hit_revision", 0))
	army.ranged_apply_hit(1, army.cells[1] + Vector2i.LEFT, {"siege": true, "shield": false,
		"result": {"hp": 1.0, "stun": SiteCombatRules.STUN_LIMIT, "guard_break": false}})
	if not _require(float(army.combat_hot_get(1, &"ko")) > 0.0 and float(army.combat_hot_get(1, &"hp")) == casualty_hp - 1.0
		and int(army.combat_units[1].get("hit_revision", 0)) == hit_before + 1,
		"Original contact owner caused real KO and one HP/revision hit"): return false
	transport.update_siege(0.01)
	if not _require(transport.crew_count(vehicle, false) == 1 and not transport._turn_crew_ready(vehicle)
		and str(vehicle.action.get("stage", "")) == "rotate" and vehicle.action.sweep == frozen_sweep
		and float(vehicle.action.elapsed) > elapsed_before and vehicle.facing == [1, 0]
		and str(vehicle.command.get("type", "")) == "release" and vehicle.command.people.has(casualty_id)
		and transport.is_siege_crew(casualty_id) and not transport.siege_save_guard().ok,
		"Below-minimum KO queues role release but retains the original committed rotation and claims"): return false
	var before_rejections := JSON.stringify(vehicle)
	var attack: Dictionary = transport.order_siege(context.key, "attack", {"type": "structure", "feature_id": "not-used-before-BUSY", "part_id": "not-used-before-BUSY"}, int(context.commander), true)
	var move: Dictionary = transport.order_siege(context.key, "move", {"type": "ground", "cell": [21, 20]}, int(context.commander), true)
	if not _require(not attack.ok and str(attack.code) == "BUSY" and not move.ok and str(move.code) == "BUSY"
		and JSON.stringify(vehicle) == before_rejections and army.cells == endpoints,
		"No new attack/push may replace the committed low-crew rotation or mutate its endpoints"): return false
	var remaining: float = float(SiteRuntime.SIEGE_DEFINITIONS.ram.turn_seconds) - float(vehicle.action.elapsed)
	if not _require(remaining > 0.05, "Casualty occurs before original rotation's last slice"): return false
	_turn_tick(context, remaining - 0.05, {})
	if not _require(str(vehicle.action.get("stage", "")) == "rotate" and vehicle.facing == [1, 0]
		and army.cells == endpoints and transport.is_siege_crew(casualty_id),
		"Crew loss cannot accelerate completion, rollback people or release a historical participant early"): return false
	_turn_tick(context, 0.05, {})
	if not _require(vehicle.action.is_empty() and vehicle.facing == [0, 1] and int(vehicle.cell) == anchor
		and vehicle.move.is_empty() and str(vehicle.command.get("type", "")) == "stop"
		and not transport.is_siege_crew(casualty_id) and float(vehicle.hp) == hp_before
		and int(vehicle.next_attack_seq) == sequence and context.lab.siege_shots == 0
		and transport.siege_save_guard().ok,
		"Committed rotation safely finishes the new facing, clears transaction and releases KO role without new attack"): return false
	var sweep_only: Vector2i = context.data.cell_from_index(anchor) + Vector2i(3, 3)
	if not _require(frozen_sweep.has(context.data.index(sweep_only)) and not transport.blocks_cell(sweep_only),
		"Actual historical sweep claim disappears after the new footprint commits"): return false
	for index in range(original_ids.size()):
		if not _require(army.combat_identity(index) == original_ids[index] and is_same(army.combat_units[index], original_rows[index])
			and is_same(army.combat_units[index].item_state, holders[index]) and is_same(army.combat_units[index].cargo, cargo[index])
			and army.cells[index] == endpoints[index] and army.moving_to[index] == TerrainArmy.INVALID_CELL,
			"Original person, holder/cargo and real station endpoint survive the committed crew-loss rotation"): return false
	if not _require(float(army.combat_hot_get(1, &"ko")) > 0.0 and float(army.combat_hot_get(1, &"hp")) <= casualty_hp - 1.0
		and is_same(vehicle.holder, vehicle_holder) and is_same(vehicle.cargo, vehicle_cargo),
		"No revival, new holder or substituted vehicle cargo is used to pass the boundary"): return false
	var settled_snapshot := JSON.stringify(vehicle)
	attack = transport.order_siege(context.key, "attack", {"type": "structure", "feature_id": "not-used-below-minimum", "part_id": "not-used-below-minimum"}, int(context.commander), true)
	move = transport.order_siege(context.key, "move", {"type": "ground", "cell": [21, 20]}, int(context.commander), true)
	if not _require(not attack.ok and not move.ok and JSON.stringify(vehicle) == settled_snapshot,
		"Below-minimum original crew also refuses new operations after the safe rotation commit"): return false
	_close_ram(context)
	turn_edge_groups += 1
	return true
