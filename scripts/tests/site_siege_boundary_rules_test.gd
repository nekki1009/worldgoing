extends "res://scripts/tests/site_siege_crew_movement_test.gd"
## Small deterministic rule and original-person admission boundaries only.
var boundary_checks := 0
var boundary_groups := 0
var boundary_failed := false

func _edge(ok: bool, label: String, detail: Variant = null) -> bool:
	if boundary_failed: return false
	boundary_checks += 1
	if ok: return true
	boundary_failed = true
	printerr("SIEGE BOUNDARY FAIL: ", label, " / ", detail)
	quit(2)
	return false

func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void: quit(1))
	# An aborted helper must fail now rather than leave only the deadline timer.
	if not _edge(_cost_edges() == true and boundary_groups == 1, "cost boundary returns successfully after its original assertions"): return
	if not _edge(_crew_edges() == true and boundary_groups == 2, "crew boundary returns successfully after its original assertions"): return
	if not _edge(_stock_edges() == true and boundary_groups == 3, "stock boundary returns successfully after its original assertions"): return
	if not _edge(_original_transaction_edges() == true and boundary_groups == 4, "original transaction boundary returns successfully after its original assertions"): return
	if not _edge(boundary_groups == 4 and not boundary_failed, "all four boundary groups completed"): return
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_BOUNDARY_RULES_PASS: ", boundary_checks, " checks; zero/139 damage and three fully paid rebuild cycles, proportional/no-double/full/loaded cancellation conservation, original crew slot/engine/KO/captive/guard/work exclusions, no/wrong ammo and two real engines competing for the original last Depot bolt; headless rules/admission only, no real-person wreck loot or GPU claim")
	quit(0)

func _cost_edges() -> bool:
	var data := _fixture()
	var start: Dictionary = data.site.inventory.duplicate(true)
	var previous_id := 0
	var cost: Dictionary = SiteRuntime.SIEGE_DEFINITIONS.ballista.cost
	for cycle in range(3):
		var key := _new_ballista(data)
		if not _edge(int(key) > previous_id, "rebuild gets a fresh original vehicle ID"): return false
		previous_id = int(key)
		var vehicle: Dictionary = data.site.vehicles[key]
		var unchanged := JSON.stringify(data.site)
		var zero := SiteRuntime.damage_siege_vehicle(data, key, 0.0)
		if not _edge(not zero.ok and not bool(vehicle.ever_hp_damaged) and JSON.stringify(data.site) == unchanged, "zero damage never marks or mutates the original vehicle"): return false
		if not _edge(SiteRuntime.damage_siege_vehicle(data, key, 139.0).ok and float(vehicle.hp) == 1.0 and bool(vehicle.ever_hp_damaged), "139 damage leaves actual HP one with irreversible damage flag"): return false
		var paid: Dictionary = data.site.inventory.duplicate(true)
		var cancelled := SiteRuntime.cancel_siege_job(data, key, 1)
		if not _edge(cancelled.ok and data.site.inventory == paid and not data.site.vehicles.has(key), "damaged construction cancellation refunds zero", cancelled): return false
		for material: String in cost:
			if not _edge(int(data.site.inventory.get(material, 0)) == int(start.get(material, 0)) - (cycle + 1) * int(cost[material]), "each rebuild consumes the complete original material cost", {"cycle": cycle, "material": material}): return false
		unchanged = JSON.stringify(data.site)
		if not _edge(not SiteRuntime.cancel_siege_job(data, key, 1).ok and JSON.stringify(data.site) == unchanged, "repeated cancellation does not refund or allocate"): return false
	data = _fixture()
	var key := _new_ballista(data)
	var vehicle: Dictionary = data.site.vehicles[key]
	var slot: Dictionary = SiteRuntime.siege_work_slots(data, vehicle)[0]
	if not _edge(SiteRuntime.advance_siege_work(data, key, "construct", float(vehicle.build.total_work) * 0.25, data.cell_from_index(int(slot.cell)), 0, 1).ok, "original construction reaches one quarter"): return false
	var paid: Dictionary = data.site.inventory.duplicate(true)
	data.site.capacity = int(SiteRuntime.carried_load(data.site, data.site.inventory, data.site.depot_items))
	var unchanged := JSON.stringify(data.site)
	var full := SiteRuntime.cancel_siege_job(data, key, 1)
	if not _edge(not full.ok and full.code == "STORAGE_FULL" and JSON.stringify(data.site) == unchanged, "full Depot cancellation is wholly atomic", full): return false
	data.site.capacity = 100000
	var loaded := SiteRuntime.transfer_items(data, data.site.depot_items, data.site.inventory, vehicle.holder, vehicle.cargo, {"siege_bolt": 1}, [], int(data.site.depot_items.version), int(vehicle.holder.version), 20)
	if not _edge(loaded.ok, "negative loaded-build fixture uses original holder transfer", loaded): return false
	unchanged = JSON.stringify(data.site)
	var blocked := SiteRuntime.cancel_siege_job(data, key, 1)
	if not _edge(not blocked.ok and blocked.code == "BUSY" and JSON.stringify(data.site) == unchanged, "loaded cancellation cannot erase existing cargo", blocked): return false
	var unloaded := SiteRuntime.transfer_items(data, vehicle.holder, vehicle.cargo, data.site.depot_items, data.site.inventory, {"siege_bolt": 1}, [], int(vehicle.holder.version), int(data.site.depot_items.version), 100000)
	if not _edge(unloaded.ok and data.site.inventory == paid, "unloading conserves every original resource", unloaded): return false
	var refunded := SiteRuntime.cancel_siege_job(data, key, 1)
	if not _edge(refunded.ok and data.site.vehicles.is_empty(), "undamaged partial construction cancels once", refunded): return false
	for material: String in cost:
		var expected := floori(float(cost[material]) * 0.75)
		if not _edge(int(refunded.refund[material]) == expected and int(data.site.inventory[material]) == int(paid[material]) + expected, "undamaged refund is the floored unworked fraction", material): return false
	unchanged = JSON.stringify(data.site)
	if not _edge(not SiteRuntime.cancel_siege_job(data, key, 1).ok and JSON.stringify(data.site) == unchanged, "partial cancellation cannot repeat its refund"): return false
	boundary_groups += 1
	return true

func _crew_edges() -> bool:
	var context := _ballista_fixture(2)
	var team: TerrainArmy = context.fixture.army
	var transport: SiteVehicleTransport = context.controller.vehicles
	var second := SiteRuntime.begin_siege_build(context.data, "ballista", Vector2i(30, 20), Vector2i.RIGHT, 1, int(context.commander))
	if not _edge(second.ok, "second real original engine constructed", second): return false
	_finish_siege(context.data, str(second.vehicle))
	var state := JSON.stringify(context.data.site)
	var first := team.combat_identity(1)
	if not _edge(not transport.assign_crew(context.key, first, "1", int(context.commander), true).ok and JSON.stringify(context.data.site) == state, "one original person cannot occupy two slots"): return false
	if not _edge(not transport.assign_crew(str(second.vehicle), first, "0", int(context.commander), true).ok and JSON.stringify(context.data.site) == state, "one original person cannot operate two engines"): return false
	_close_ballista(context)
	for kind: String in ["ko", "captive", "guard", "work"]:
		context = _ballista_fixture(0)
		team = context.fixture.army
		transport = context.controller.vehicles
		first = team.combat_identity(1)
		match kind:
			"ko": team.combat_hot_set(1, &"ko", 60.0)
			"captive": team.combat_hot_set(1, &"captive", true)
			"guard":
				# Original guard relationship, queried by the ordinary person owner.
				context.data.site.captivity[str(team.combat_identity(2))] = {"guard_id": first, "prison_id": ""}
			"work":
				var work_ids: Array[int] = [first]
				var assigned: Dictionary = context.controller.work_team.assign(team, work_ids, int(context.commander))
				if not _edge(assigned.ok, "original commander creates the work exclusion fixture", assigned): return false
		state = JSON.stringify(context.data.site)
		var rejected := transport.assign_crew(context.key, first, "0", int(context.commander), true)
		if not _edge(not rejected.ok and JSON.stringify(context.data.site) == state and context.vehicle.crew_slots.is_empty(), kind + " original role cannot also become siege crew", rejected): return false
		_close_ballista(context)
	boundary_groups += 1
	return true

func _stock_edges() -> bool:
	var context := _ballista_fixture(2)
	var vehicle: Dictionary = context.vehicle
	vehicle.cargo.clear() # Explicit empty initial magazine for the no-ammo case.
	var version := int(vehicle.holder.version)
	_attack(context)
	_tick(context, 20.0)
	if not _edge(context.lab.siege_shots == 0 and int(vehicle.next_attack_seq) == 1 and int(vehicle.holder.version) == version and vehicle.cargo.is_empty(), "empty original magazine cannot fire or increment its release identity"): return false
	_close_ballista(context)
	context = _ballista_fixture(0)
	var team: TerrainArmy = context.fixture.army
	var transport: SiteVehicleTransport = context.controller.vehicles
	var data: TerrainData = context.data
	vehicle = context.vehicle
	vehicle.cargo.clear() # Original fixture begins this resource race with empty magazines.
	if not _edge(team._reserve_combat_step(0, Vector2i(16, 19)), "commander starts first original edge"): return false
	_crew_ticks(context, 0.5)
	if not _edge(team.cells[0] == Vector2i(16, 19) and team._reserve_combat_step(0, Vector2i(16, 18)), "commander starts second original edge"): return false
	_crew_ticks(context, 0.5)
	if not _edge(team._reserve_combat_step(1, Vector2i(18, 20)), "second engine loader takes its real adjacent step"): return false
	_crew_ticks(context, 0.5)
	if not _edge(team.cells[0] == Vector2i(16, 18) and team.cells[1] == Vector2i(18, 20), "both original people reached their actual fixture cells"): return false
	var second := SiteRuntime.begin_siege_build(data, "ballista", Vector2i(17, 20), Vector2i.LEFT, 1, int(context.commander))
	if not _edge(second.ok, "second competing engine has its own paid source", second): return false
	var second_key := str(second.vehicle)
	_finish_siege(data, second_key)
	var other: Dictionary = data.site.vehicles[second_key]
	var left_person := team.combat_identity(1)
	var right_person := team.combat_identity(2)
	if not _edge(transport.assign_crew(context.key, right_person, "1", int(context.commander), true).ok and transport.assign_crew(second_key, left_person, "0", int(context.commander), true).ok, "two original crew load their distinct actual engine stations"): return false
	data.site.depot_cell = data.index(Vector2i(19, 20))
	data.site.inventory.siege_bolt = 1 # The agreed single remaining original Depot unit.
	var state := JSON.stringify(data.site)
	var wrong := transport.transfer("depot", context.key, {"siege_stone": 1}, [], int(data.site.depot_items.version), int(vehicle.holder.version), right_person, true)
	if not _edge(not wrong.ok and wrong.code == "INVALID" and JSON.stringify(data.site) == state, "wrong physical ammunition is rejected atomically", wrong): return false
	var depot_version := int(data.site.depot_items.version)
	var old_magazine := int(other.holder.version)
	var won := transport.transfer("depot", context.key, {"siege_bolt": 1}, [], depot_version, int(vehicle.holder.version), right_person, true)
	if not _edge(won.ok and int(vehicle.cargo.get("siege_bolt", 0)) == 1, "first real engine takes the last original Depot bolt", won): return false
	state = JSON.stringify(data.site)
	var lost := transport.transfer("depot", second_key, {"siege_bolt": 1}, [], depot_version, old_magazine, left_person, true)
	if not _edge(not lost.ok and lost.code == "STALE_SOURCE" and JSON.stringify(data.site) == state, "second real engine loses the stale same-source race atomically", lost): return false
	lost = transport.transfer("depot", second_key, {"siege_bolt": 1}, [], int(data.site.depot_items.version), old_magazine, left_person, true)
	if not _edge(not lost.ok and lost.code == "EMPTY" and JSON.stringify(data.site) == state and int(data.site.inventory.get("siege_bolt", 0)) + int(vehicle.cargo.get("siege_bolt", 0)) + int(other.cargo.get("siege_bolt", 0)) == 1, "fresh retry cannot duplicate the consumed original resource", lost): return false
	var release := SiteRuntime.release_siege_ammo(data, context.key, int(vehicle.holder.version) - 1)
	if not _edge(not release.ok and release.code == "STALE_SOURCE" and JSON.stringify(data.site) == state, "stale holder cannot release a newly loaded original bolt", release): return false
	_close_ballista(context)
	boundary_groups += 1
	return true

func _original_transaction_edges() -> bool:
	var context := _ballista_fixture(2)
	var team: TerrainArmy = context.fixture.army
	var first := team.combat_identity(1)
	var row: Dictionary = team.combat_units[1]
	var holder: Dictionary = row.item_state
	var cargo: Dictionary = row.cargo
	var roster: int = team.combat_units.size()
	if not _edge(context.controller.vehicles.unassign_crew(context.key, first, int(context.commander), true).ok
		and not context.controller.vehicles.is_operator(first), "original crew release actually removes the original occupation"): return false
	var work_ids: Array[int] = [first]
	var assigned: Dictionary = context.controller.work_team.assign(team, work_ids, int(context.commander))
	if not _edge(assigned.ok and context.controller.work_team.is_assigned(first) and not row.work_task.is_empty()
		and team.combat_units.size() == roster and team.combat_identity(1) == first
		and is_same(team.combat_units[1], row) and is_same(row.item_state, holder) and is_same(row.cargo, cargo),
		"released original person enters original WorkTeam with the same row, holder, cargo and ID", assigned): return false
	_close_ballista(context)
	context = _ballista_fixture(0)
	team = context.fixture.army
	first = team.combat_identity(1)
	if not _edge(team._reserve_combat_step(1, Vector2i(19, 19)), "ordinary original person commits a true adjacent movement edge before crew admission"): return false
	var state := JSON.stringify(context.data.site)
	var movement := JSON.stringify(team.capture_combat_state())
	var rejected: Dictionary = context.controller.vehicles.assign_crew(context.key, first, "0", int(context.commander), true)
	if not _edge(not rejected.ok and rejected.code == "BUSY" and context.vehicle.crew_slots.is_empty()
		and JSON.stringify(context.data.site) == state and JSON.stringify(team.capture_combat_state()) == movement,
		"crew admission cannot steal an original committed ordinary step or its reservations", rejected): return false
	_close_ballista(context)
	for mode: String in ["occupied", "reserved"]:
		context = _ballista_fixture(0)
		team = context.fixture.army
		var witness := Vector2i(19, 19)
		if not _edge(team._reserve_combat_step(1, witness), "cancel witness starts a real original reservation " + mode): return false
		if mode == "occupied":
			_crew_ticks(context, 0.5)
			if not _edge(team.cells[1] == witness and team.moving_to[1] == TerrainArmy.INVALID_CELL, "occupied cancel witness arrived by a real original adjacent step"): return false
		else:
			if not _edge(team.cells[1] != witness and team.moving_to[1] == witness and team._reserved_cells.has(witness), "reservation-only witness remains outside the new footprint"): return false
		# Explicit negative candidate: the low-level fixture omits the placement
		# occupancy callback. The original cancellation callback must still refuse
		# this layout. This does not claim normal UI placement accepts occupants.
		var created := SiteRuntime.begin_siege_build(context.data, "ballista", Vector2i(17, 18), Vector2i.RIGHT, 1, int(context.commander))
		if not _edge(created.ok and not context.data.site.vehicles[str(created.vehicle)].build.is_empty()
			and context.controller._siege_people_occupied(witness), "negative construction candidate references the true original person or reservation " + mode, created): return false
		state = JSON.stringify(context.data.site)
		movement = JSON.stringify(team.capture_combat_state())
		var denied := SiteRuntime.cancel_siege_job(context.data, str(created.vehicle), 1, context.controller._siege_people_occupied)
		if not _edge(not denied.ok and denied.code == "OCCUPIED" and JSON.stringify(context.data.site) == state
			and JSON.stringify(team.capture_combat_state()) == movement,
			"cancel preserves the complete original construction/person/reservation transaction " + mode, denied): return false
		_close_ballista(context)
	context = _ballista_fixture(2)
	_attack(context)
	for _slice in range(500):
		_tick(context, 0.02)
		if context.lab.siege_shots == 1: break
	if not _edge(context.lab.siege_shots == 1 and str(context.vehicle.action.get("stage", "")) == "recovering", "real release reaches its original committed recovery transaction"): return false
	if not _edge(context.controller.vehicles.unassign_crew(context.key, 0, int(context.commander), true).ok
		and context.vehicle.crew_slots.is_empty() and not context.vehicle.action.is_empty(), "real crew release retains committed recovery without crew as another refusal reason"): return false
	state = JSON.stringify(context.data.site)
	movement = JSON.stringify(context.fixture.army.capture_combat_state())
	var cancelled := SiteRuntime.cancel_siege_job(context.data, context.key, 1, context.controller._siege_people_occupied)
	if not _edge(not cancelled.ok and cancelled.code == "BUSY" and JSON.stringify(context.data.site) == state
		and JSON.stringify(context.fixture.army.capture_combat_state()) == movement and context.lab.siege_shots == 1,
		"cancel cannot erase a genuine committed original action or consume/restore its released round", cancelled): return false
	_close_ballista(context)
	boundary_groups += 1
	return true
