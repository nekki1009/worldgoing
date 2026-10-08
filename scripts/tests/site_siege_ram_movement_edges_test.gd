extends "res://scripts/tests/site_siege_ram_compound_test.gd"
## Narrow extra P2 boundaries; reuse the original headless owner fixture.
var edge_groups := 0
var edge_checks := 0
var edge_failed := false

func _edge(value: bool, label: String, detail: Variant = null) -> bool:
	edge_checks += 1
	if value: return true
	edge_failed = true
	printerr("RAM MOVEMENT EDGE FAIL: ", label, " / ", detail)
	quit(2)
	return false

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void: _edge(false, "bounded P2 edge deadline"); quit(3))
	if not _opposing_compounds(): return
	if not _occupied_mouth(): return
	if not _halfstep_casualty(): return
	if not _four_turns_and_new_station_guard(): return
	if not _edge(edge_groups == 4 and not edge_failed, "all four additional edge groups completed"): return
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_RAM_MOVEMENT_EDGES_PASS: ", edge_checks, " checks; two original facing vehicles contend for one physical destination, original live/dead Actor blocks a two-cell mouth, frozen half-step death/captive plus stop preserves whole endpoints and original cargo/remains, four real90-degree rig/return cycles restore anchor/footprint and reject premature attack/push transactions; headless only, no native/GPU/full capture or save claim")
	quit(0)

func _ram_ticks(context: Dictionary, seconds: float) -> void:
	# Same original fixture clock/call sequence, extended only to prepare both
	# registered original Armies in the opposing-vehicle case.
	var remaining := seconds
	while remaining > 0.000000001:
		var step := minf(0.05, remaining)
		context.controller.vehicles.update_siege(step)
		context.coordinator.combat_logic_tick_if_needed(step)
		for team: TerrainArmy in context.lab.combat_armies: team.prepare_combat(step)
		context.coordinator.complete_committed_moves()
		context.lab._advance_siege(step)
		remaining -= step

func _second_ram(context: Dictionary) -> Dictionary:
	var created := SiteRuntime.begin_siege_build(context.data, "ram", Vector2i(26, 20), Vector2i.LEFT, 2, 2)
	if not _edge(created.ok, "second facing ram pays original cost", created): return {}
	var vehicle: Dictionary = context.data.site.vehicles[str(created.vehicle)]
	var work: Dictionary = SiteRuntime.siege_work_slots(context.data, vehicle)[0]
	var built := SiteRuntime.advance_siege_work(context.data, str(vehicle.id), "construct", float(vehicle.build.total_work), context.data.cell_from_index(int(work.cell)), int(work.slot), 2)
	if not _edge(built.ok, "second original ram paid build completes", built): return {}
	var army := TerrainArmy.new()
	root.add_child(army)
	army.set_process(false)
	army.team_id = 2 # Genesis owner metadata before original IDs are allocated.
	army.faction_id = 1
	army.roster_size = 5
	var positions: Array[Vector2i] = [Vector2i(30, 18)]
	for slot in range(4): positions.append(SiteRuntime.siege_crew_cell(context.data, vehicle, str(slot)))
	if not _edge(army.deploy_at(context.data, null, null, positions) and army.enable_combat(false), "second original Army owns five new genesis people"): return {}
	for row: Dictionary in army.combat_units:
		row.cargo = {}
		row.item_state = SiteRuntime.new_item_state("person:" + str(row.person_id))
	context.lab.combat_armies.append(army)
	army.vehicle_transport = context.controller.vehicles
	army.exchange_enabled = true
	context.coordinator.register_formation(army)
	for slot in range(4):
		var assigned: Dictionary = context.controller.vehicles.assign_crew(str(vehicle.id), army.combat_identity(slot + 1), str(slot), army.combat_identity(army.current_commander), true)
		if not _edge(assigned.ok, "second original crew admits distinct real slots", assigned): return {}
	context.controller.vehicles.update_siege(0.001)
	return {"army": army, "vehicle": vehicle}

func _opposing_compounds() -> bool:
	var context := _ram_fixture()
	var other := _second_ram(context)
	if other.is_empty(): return false
	var first: TerrainArmy = context.fixture.army
	var second: TerrainArmy = other.army
	var first_cells: Array[Vector2i] = first.cells.duplicate()
	var second_cells: Array[Vector2i] = second.cells.duplicate()
	var ids := first._get_active_member_ids() # Ordinary commander only; original full roster retained separately.
	for index in range(first.combat_units.size()):
		if not _edge(second.index_for_identity(first.combat_identity(index)) < 0, "two original Army identities never alias"): return false
	var transport: SiteVehicleTransport = context.controller.vehicles
	var one := transport.order_siege(context.key, "move", {"type": "ground", "cell": [21, 20]}, int(context.commander), true)
	var two := transport.order_siege(str(other.vehicle.id), "move", {"type": "ground", "cell": [25, 20]}, second.combat_identity(second.current_commander), true)
	if not _edge(one.ok and two.ok, "both independent original commanders may request the opposing step", [one, two]): return false
	context.coordinator.combat_logic_tick(0.0)
	var admitted := int(not context.vehicle.move.is_empty()) + int(not other.vehicle.move.is_empty())
	if not _edge(admitted == 1, "original Grid admits exactly one whole group at shared destination23,20", {"first": context.vehicle.move, "second": other.vehicle.move}): return false
	var first_won: bool = not context.vehicle.move.is_empty()
	if not _edge(transport.order_siege(context.key, "stop", {}, int(context.commander), true).ok and transport.order_siege(str(other.vehicle.id), "stop", {}, second.combat_identity(second.current_commander), true).ok, "stop retains only already admitted original group"): return false
	_ram_ticks(context, 1.0)
	if not _edge(first.cells == first_cells and second.cells == second_cells, "opposing stop keeps both source sets until the one original barrier"): return false
	_ram_ticks(context, 1.0)
	for index in range(1, 5):
		if not _edge(first.cells[index] == first_cells[index] + (Vector2i.RIGHT if first_won else Vector2i.ZERO) and second.cells[index] == second_cells[index] + (Vector2i.ZERO if first_won else Vector2i.LEFT), "one complete original group reaches endpoint; loser stays source", index): return false
	if not _edge(context.vehicle.move.is_empty() and other.vehicle.move.is_empty() and first._get_active_member_ids() == ids, "opposing conflict does not alter roster roles or leave half a group"): return false
	context.coordinator.unregister_formation(second)
	context.lab.combat_armies.erase(second)
	second.free()
	_close_ram(context)
	edge_groups += 1
	return true

func _occupied_mouth() -> bool:
	var context := _ram_fixture(2)
	var army: TerrainArmy = context.fixture.army
	var source: Array[Vector2i] = army.cells.duplicate()
	# Genesis natural choke: the original two-cell body fits, no route exists
	# around the wall; no feature/nav owner or post-admission surface is changed.
	for y in range(context.data.size.y):
		if y not in [20, 21]: context.data.static_blocked[context.data.index(Vector2i(23, y))] = 1
	context.data.navigation_revision += 1
	var blocker := _add_projected_actor(context, Vector2i(23, 20), 900101)
	blocker.faction_id = 1
	var ordered: Dictionary = context.controller.vehicles.order_siege(context.key, "move", {"type": "ground", "cell": [25, 20]}, int(context.commander), true)
	if not _edge(ordered.ok, "original commander requests route through natural two-cell mouth", ordered): return false
	context.coordinator.combat_logic_tick(0.0)
	if not _edge(context.vehicle.move.is_empty() and army.cells == source and army._reserved_cells.is_empty(), "real live Actor in mouth rejects whole body/crew route"): return false
	blocker.apply_contact({"environmental": true, "shield": false, "result": {"hp": 100.0, "stun": 0.0, "guard_break": false}})
	if not _edge(blocker.hp == 0.0 and blocker.terrain_cell == Vector2i(23, 20), "original lethal hit retains real corpse source"): return false
	context.coordinator.combat_logic_tick(0.0)
	if not _edge(context.vehicle.move.is_empty() and army.cells == source and army._reserved_cells.is_empty(), "actual dead body still occupies the same mouth; no awake/delete workaround"): return false
	_close_ram(context)
	edge_groups += 1
	return true

func _halfstep_casualty() -> bool:
	for status: String in ["dead", "captive"]:
		var context := _ram_fixture()
		var army: TerrainArmy = context.fixture.army
		var source: Array[Vector2i] = army.cells.duplicate()
		var original_row: Dictionary = army.combat_units[1]
		var identity := army.combat_identity(1)
		original_row.cargo.grain = 3 # Explicit genesis cargo in this original holder.
		var original_cargo: Dictionary = original_row.cargo.duplicate(true)
		if not army.died.is_connected(context.controller._person_died): army.died.connect(context.controller._person_died)
		if not _begin_ram_step(context, Vector2i.RIGHT): return false
		_ram_ticks(context, 1.0)
		if not _edge(is_equal_approx(float(army.move_progress[1]), 0.5), "casualty boundary begins on true committed half-step"): return false
		if status == "dead":
			army.apply_unit_contact(1, {"environmental": true, "shield": false, "result": {"hp": 100.0, "stun": 0.0, "guard_break": false}})
		else:
			# Explicit adversarial boundary injection through the original hot
			# person writer, not proof that ordinary binding can capture a moving
			# target. No fake relation/person, new clock or revival is introduced.
			context.controller.person_actions._body_set(context.controller.person_actions._person(identity), "captive", true)
		context.controller.vehicles.update_siege(0.001)
		var stopped: Dictionary = context.controller.vehicles.order_siege(context.key, "stop", {}, int(context.commander), true)
		if not _edge(stopped.ok and not context.vehicle.move.is_empty() and army.cells == source and not context.controller.vehicles.siege_save_guard().ok, "death/captive stop preserves original committed sources and blocks premature save", status): return false
		context.controller.settle_person_deaths(3.0)
		if not _edge(original_row.cargo == original_cargo and context.data.site.ground_loot.is_empty(), "death publisher cannot move belongings before original endpoint", status): return false
		_ram_ticks(context, 1.0)
		context.controller.vehicles.update_siege(0.001)
		for index in range(1, 5):
			if not _edge(army.cells[index] == source[index] + Vector2i.RIGHT and army.moving_to[index] == TerrainArmy.INVALID_CELL, "historical original compound participant finishes endpoint even after status loss", {"status": status, "index": index}): return false
		if not _edge(army.combat_identity(1) == identity and is_same(army.combat_units[1], original_row) and army.combat_units.size() == 5 and not context.controller.vehicles.is_siege_crew(identity), "invalid role releases after barrier; original person row/ID remains", status): return false
		context.controller.settle_person_deaths(0.0)
		if status == "dead":
			var remains_id := str(context.controller.person_actions._body_get(context.controller.person_actions._person(identity), "remains_id"))
			var remains: Dictionary = context.data.site.ground_loot.get(remains_id, {})
			if not _edge(not remains.is_empty() and int(remains.original_owner) == identity and int(remains.cell) == context.data.index(source[1] + Vector2i.RIGHT) and remains.cargo == original_cargo and original_row.cargo.is_empty() and float(army.combat_hot_get(1, &"hp")) == 0.0, "real remains preserve all original cargo once at actual committed endpoint", remains): return false
			var preserved := JSON.stringify(context.data.site.ground_loot)
			context.controller.settle_person_deaths(5.0)
			if not _edge(context.data.site.ground_loot.size() == 1 and JSON.stringify(context.data.site.ground_loot) == preserved, "repeated death settlement cannot duplicate original remains"): return false
		elif not _edge(bool(army.combat_hot_get(1, &"captive")) and float(army.combat_hot_get(1, &"hp")) == 100.0 and original_row.cargo == original_cargo and context.data.site.ground_loot.is_empty(), "explicit captive boundary preserves true captive status/cargo without reviving or minting remains"): return false
		_close_ram(context)
	edge_groups += 1
	return true

func _four_turns_and_new_station_guard() -> bool:
	var context := _ram_fixture()
	var army: TerrainArmy = context.fixture.army
	var original_anchor := int(context.vehicle.cell)
	var original_footprint: Array[int] = []
	for cell: Vector2i in SiteRuntime.siege_cells(context.data, context.vehicle): original_footprint.append(context.data.index(cell))
	original_footprint.sort()
	var original_ids: Array[int] = []
	for index in range(army.combat_units.size()): original_ids.append(army.combat_identity(index))
	for direction: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT]:
		var ordered: Dictionary = context.controller.vehicles.order_siege(context.key, "turn", {"facing": [direction.x, direction.y]}, int(context.commander), true)
		if not _edge(ordered.ok, "original ninety-degree turn requested", ordered): return false
		var saw_rotate := false
		var saw_return := false
		for _tick in range(500):
			_ram_ticks(context, 0.05)
			var stage := str(context.vehicle.action.get("stage", ""))
			saw_rotate = saw_rotate or stage == "rotate"
			if stage == "return" and not saw_return:
				saw_return = true
				var move: Dictionary = context.controller.vehicles.order_siege(context.key, "move", {"type": "ground", "cell": [21, 20]}, int(context.commander), true)
				var attack: Dictionary = context.controller.vehicles.order_siege(context.key, "attack", {"type": "structure", "feature_id": "fixture-not-used", "part_id": "fixture-not-used"}, int(context.commander), true)
				if not _edge(not context.controller.vehicles.crew_ready(context.vehicle) and not move.ok and str(move.code) == "BUSY" and not attack.ok and str(attack.code) == "BUSY" and context.vehicle.move.is_empty(), "new facing cannot push/attack before real crew return stations finish"): return false
			if context.vehicle.action.is_empty() and context.controller.vehicles.crew_ready(context.vehicle): break
		if not _edge(saw_rotate and saw_return and context.vehicle.action.is_empty() and context.controller.vehicles.crew_ready(context.vehicle) and context.vehicle.facing == [direction.x, direction.y] and int(context.vehicle.cell) == original_anchor, "actual rig rotation and original return walks complete without changing anchor", direction): return false
		for index in range(army.combat_units.size()):
			if not _edge(army.combat_identity(index) == original_ids[index], "four-turn cycle retains original identities", index): return false
	var final_footprint: Array[int] = []
	for cell: Vector2i in SiteRuntime.siege_cells(context.data, context.vehicle): final_footprint.append(context.data.index(cell))
	final_footprint.sort()
	if not _edge(context.vehicle.facing == [1, 0] and final_footprint == original_footprint and context.controller.vehicles.siege_save_guard().ok, "four real90-degree cycles restore exact footprint/facing/anchor and stable guard"): return false
	_close_ram(context)
	edge_groups += 1
	return true
