extends "res://scripts/tests/site_siege_ballista_contract_test.gd"

const RamCoordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const RamTypes = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _require(condition: bool, message: String) -> bool:
	if condition: return true
	push_error(message)
	quit(1)
	return false

func _run() -> void:
	create_timer(65.0).timeout.connect(func() -> void: quit(1))
	if not _check_ram_durations_and_barrier(): return
	if not _check_ram_whole_group_preflight(): return
	if not _check_ram_stop_ko_and_retreat(): return
	if not _check_ram_invalid_support(): return
	if not _check_ram_turn_grid_and_recovery(): return
	if not _require(completed == 5, "Every ram compound group must finish before PASS"): return
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_RAM_COMPOUND_PASS: original Army cells/steps, same-duration four-way/reverse compound barrier, all-or-none missing-owner/sweep/crew-destination preflight, stop/KO/retreat endpoint preservation, source/target support cancellation with original one-time fall, Grid rotation admission and mandatory recovery; headless owner fixture only, no native/GPU claim")
	quit(0)

func _ram_fixture(count: int = 4, facing: Vector2i = Vector2i.RIGHT, level: int = 0) -> Dictionary:
	var data := _fixture()
	data.height_levels.fill(level)
	var created := SiteRuntime.begin_siege_build(data, "ram", Vector2i(20, 20), facing, 1, 1)
	assert(created.ok, str(created))
	var key := str(created.vehicle)
	var vehicle: Dictionary = data.site.vehicles[key]
	var work: Dictionary = SiteRuntime.siege_work_slots(data, vehicle)[0]
	assert(SiteRuntime.advance_siege_work(data, key, "construct", 7200.0, data.cell_from_index(int(work.cell)), 0, 1).ok)
	var lab := QueryLab.new()
	lab.terrain = data
	var controller := Controller.new()
	controller.lab = lab
	lab.site_controller = controller
	controller.person_actions.init(lab)
	controller.vehicles.init(controller)
	var positions: Array[Vector2i] = [Vector2i(16, 18)] # Original commander outside all four turn stations and their sweep.
	for slot in range(count): positions.append(SiteRuntime.siege_crew_cell(data, vehicle, str(slot)))
	var fixture := CrewFixture.new()
	fixture.setup(root, data, positions)
	lab.army = fixture.army
	lab.combat_armies.append(fixture.army)
	fixture.army.vehicle_transport = controller.vehicles
	fixture.army.exchange_enabled = true
	controller.work_team.init(lab)
	var coordinator := RamCoordinator.new()
	coordinator.register_formation(fixture.army)
	lab.combat_movement_coordinator = coordinator
	var commander := fixture.army.combat_identity(0)
	for slot in range(count): assert(controller.vehicles.assign_crew(key, fixture.army.combat_identity(slot + 1), str(slot), commander, true).ok)
	controller.vehicles.update_siege(0.001)
	assert(controller.vehicles.crew_ready(vehicle))
	return {"data": data, "key": key, "vehicle": vehicle, "lab": lab, "controller": controller, "fixture": fixture, "commander": commander, "coordinator": coordinator}

func _ram_ticks(context: Dictionary, seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000000001:
		var step := minf(0.05, remaining)
		context.controller.vehicles.update_siege(step)
		context.coordinator.combat_logic_tick_if_needed(step)
		context.fixture.army.prepare_combat(step)
		context.coordinator.complete_committed_moves()
		# The real Lab gathers ram and flight contacts after original people move.
		context.lab._advance_siege(step)
		remaining -= step

func _begin_ram_step(context: Dictionary, delta: Vector2i) -> bool:
	var source: Vector2i = context.data.cell_from_index(int(context.vehicle.cell))
	var goal := source + delta
	var order: Dictionary = context.controller.vehicles.order_siege(context.key, "move", {"type": "ground", "cell": [goal.x, goal.y]}, int(context.commander), true)
	if not _require(order.ok, "Authorized original ram MOVE failed: " + str(order)): return false
	context.coordinator.combat_logic_tick(0.0)
	return _require(not context.vehicle.move.is_empty(), "A legal whole ram group did not commit admission")

func _close_ram(context: Dictionary) -> void:
	context.coordinator.unregister_formation(context.fixture.army)
	context.lab.combat_movement_coordinator = null
	_close_ballista(context)

func _check_ram_durations_and_barrier() -> bool:
	for count in [2, 3, 4]:
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var context := _ram_fixture(count)
			var army: TerrainArmy = context.fixture.army
			var source: Array[Vector2i] = army.cells.duplicate()
			var anchor: int = int(context.vehicle.cell)
			if not _begin_ram_step(context, direction): return false
			var duration := 1.0 / (0.5 * SiteCombatRules.siege_crew_multiplier(count, 2, 4) * (0.5 if direction == Vector2i.LEFT else 1.0))
			if not _require(context.coordinator._inflight_batches.size() == 1 and context.coordinator._inflight_batches[0].size() == count, "Separate open-tail pushers must still share one compound batch"): return false
			for index in range(1, count + 1):
				if not _require(army.cells[index] == source[index] and army.moving_to[index] == source[index] + direction and is_equal_approx(army.move_duration[index], duration), "Admission changed a source or split controlled duration"): return false
			_ram_ticks(context, duration * 0.5)
			if not _require(int(context.vehicle.cell) == anchor and army.cells == source, "The whole group must retain sources before its finish barrier"): return false
			var pose: Dictionary = context.controller.vehicles.render_state(context.vehicle)
			var vehicle_source := (Vector2(context.data.cell_from_index(anchor)) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
			var person_source := (Vector2(source[1]) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
			if not _require((Vector2(pose.position) - vehicle_source).is_equal_approx(army.combat_ground(1) - person_source), "Vehicle presentation must borrow the same original movement weight as its pushers"): return false
			for index in range(1, count + 1):
				if not _require(is_equal_approx(army.move_progress[index], 0.5), "All original participant progress must advance on one duration"): return false
			_ram_ticks(context, duration * 0.5)
			if not _require(int(context.vehicle.cell) == context.data.index(context.data.cell_from_index(anchor) + direction) and context.vehicle.move.is_empty(), "Vehicle pose did not finish with its original person batch"): return false
			for index in range(1, count + 1):
				if not _require(army.cells[index] == source[index] + direction and army.moving_to[index] == TerrainArmy.INVALID_CELL and is_equal_approx(army.move_duration[index], TerrainArmy.MOVE_DURATION), "Person completion left a split endpoint or slow ordinary duration"): return false
			_ram_ticks(context, 0.05)
			if not _require(context.controller.vehicles.siege_save_guard().ok, "A stable arrived ram must pass the original save guard"): return false
			_close_ram(context)
	completed += 1
	return true

func _check_ram_whole_group_preflight() -> bool:
	var context := _ram_fixture()
	var army: TerrainArmy = context.fixture.army
	var source: Array[Vector2i] = army.cells.duplicate()
	var goal := Vector2i(21, 20)
	assert(context.controller.vehicles.order_siege(context.key, "move", {"type": "ground", "cell": [goal.x, goal.y]}, int(context.commander), true).ok)
	context.coordinator._rebuild_occupancy()
	var grid: Object = context.coordinator.movement_reservation_grid
	grid.begin_tick(context.coordinator._current_occupancy, context.data)
	context.controller.vehicles.propose_siege_compounds(grid)
	grid.resolve_all()
	var lookup: Dictionary = context.coordinator._member_lookup.duplicate()
	lookup.erase(army.combat_identity(4))
	grid.commit_all(lookup, 1)
	if not _require(context.vehicle.move.is_empty() and army.cells == source and army._reserved_cells.is_empty(), "Missing last owner must reject the entire compound before any first owner starts"): return false
	for index in range(1, 5):
		if not _require(army.moving_to[index] == TerrainArmy.INVALID_CELL, "Preflight failure admitted part of a ram group"): return false
	_close_ram(context)
	for blocker: Vector2i in [Vector2i(23, 21), Vector2i(22, 22)]:
		context = _ram_fixture()
		army = context.fixture.army
		source = army.cells.duplicate()
		var actor := _add_projected_actor(context, blocker, 900001)
		actor.faction_id = 2
		assert(context.controller.vehicles.order_siege(context.key, "move", {"type": "ground", "cell": [21, 20]}, int(context.commander), true).ok)
		context.coordinator.combat_logic_tick(0.0)
		if not _require(context.vehicle.move.is_empty() and army.cells == source and army._reserved_cells.is_empty(), "Body sweep or one required crew destination must reject every pusher"): return false
		_close_ram(context)
	completed += 1
	return true

func _check_ram_stop_ko_and_retreat() -> bool:
	for retreat in [false, true]:
		var context := _ram_fixture()
		var army: TerrainArmy = context.fixture.army
		var source: Array[Vector2i] = army.cells.duplicate()
		if not _begin_ram_step(context, Vector2i.RIGHT): return false
		_ram_ticks(context, 0.4)
		army.apply_unit_contact(1, {"shield": false, "result": {"hp": 0.0, "stun": 100.0, "guard_break": false}})
		context.controller.vehicles.update_siege(0.01)
		if retreat:
			var refused := army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.RETREAT)
			if not _require(not refused.ok and str(refused.get("code", "")) == "NOT_ROUTED" and not context.vehicle.move.is_empty(), "An uncollapsed original team must reject RETREAT without dissolving its committed vehicle step: " + str(refused)): return false
			# Original retreat contract fixtures supply the existing morale-owner
			# query; a single KO does not itself prove the whole team has routed.
			army.sustain_routed_query = func(_original: TerrainArmy) -> bool: return true
			var ordered := army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.RETREAT)
			if not _require(ordered.ok, "Collapsed original team RETREAT failed: " + str(ordered)): return false
		else:
			var stopped: Dictionary = context.controller.vehicles.order_siege(context.key, "stop", {}, int(context.commander), true)
			if not _require(stopped.ok, "Authorized stop failed: " + str(stopped)): return false
		if not _require(not context.controller.vehicles.siege_save_guard().ok and not context.vehicle.move.is_empty(), "Stop/KO cannot save, rewind, or dissolve the committed group"): return false
		_ram_ticks(context, 1.6)
		if not _require(context.vehicle.move.is_empty() and int(context.vehicle.cell) == context.data.index(Vector2i(21, 20)), "Stop/KO/retreat failed to finish the frozen original group"): return false
		for index in range(1, 5):
			if not _require(army.cells[index] == source[index] + Vector2i.RIGHT and army.moving_to[index] == TerrainArmy.INVALID_CELL and is_equal_approx(army.move_duration[index], TerrainArmy.MOVE_DURATION), "A casualty or retreat split a historical participant endpoint"): return false
		if not _require(army.cells.size() == source.size() and not context.controller.vehicles.is_siege_crew(army.combat_identity(1)), "Crew release must retain original people and remove the invalid role only after completion"): return false
		if retreat and not _require(context.vehicle.crew_slots.is_empty(), "Retreat must abandon the engine and release the whole original crew"): return false
		_close_ram(context)
	completed += 1
	return true

func _check_ram_invalid_support() -> bool:
	for source_lost in [false, true]:
		var context := _ram_fixture(4, Vector2i.RIGHT, 1 if source_lost else 0)
		var army: TerrainArmy = context.fixture.army
		var source: Array[Vector2i] = army.cells.duplicate()
		if not _begin_ram_step(context, Vector2i.RIGHT): return false
		_ram_ticks(context, 0.4)
		if source_lost:
			var lost := {}
			for cell: Vector2i in source: lost[context.data.index(cell)] = 1
			context.data.height_levels.fill(0)
			context.data.navigation_revision += 1
			context.lab.resolve_structure_change(SiteRuntime.ok("fixture original support lost", {"lost_surfaces": lost}))
			if not _require(is_equal_approx(float(context.vehicle.hp), 225.0), "One actual lost navigation layer must damage the original vehicle once by 25% maxHP"): return false
			for index in range(1, 5):
				if not _require(is_equal_approx(float(army.combat_hot_get(index, &"hp")), 85.0), "Original Lab fall must settle each original person once at the source"): return false
		else:
			context.data.static_blocked[context.data.index(Vector2i(23, 21))] = 1
			context.data.navigation_revision += 1
			context.coordinator.complete_committed_moves()
		if not _require(army.cells == source and int(context.vehicle.cell) == context.data.index(Vector2i(20, 20)) and context.vehicle.move.is_empty() and army._reserved_cells.is_empty() and context.coordinator._inflight_batches.is_empty(), "Invalid support must cancel the entire uncompleted group without partial or remote relocation"): return false
		context.coordinator.complete_committed_moves()
		if source_lost and not _require(is_equal_approx(float(context.vehicle.hp), 225.0), "A repeated completion poll duplicated fall damage"): return false
		_close_ram(context)
	completed += 1
	return true

func _check_ram_turn_grid_and_recovery() -> bool:
	var context := _ram_fixture()
	assert(context.controller.vehicles.order_siege(context.key, "turn", {"facing": [0, 1]}, int(context.commander), true).ok)
	_ram_ticks(context, 4.0)
	if not _require(str(context.vehicle.action.get("stage", "")) == "rotate", "All real crew must reach four distinct rope stations before Grid rotation admission"): return false
	var cells: Array[Vector2i] = context.fixture.army.cells.duplicate()
	var remaining_turn := 4.0 - float(context.vehicle.action.elapsed)
	assert(context.controller.vehicles.order_siege(context.key, "stop", {}, int(context.commander), true).ok)
	_ram_ticks(context, remaining_turn - 0.05)
	if not _require(context.vehicle.facing == [1, 0] and not context.vehicle.action.is_empty(), "A ram cannot finish before all four committed rotation seconds elapse"): return false
	_ram_ticks(context, 0.05)
	if not _require(context.vehicle.facing == [0, 1] and context.vehicle.action.is_empty() and context.fixture.army.cells == cells and context.controller.vehicles.siege_save_guard().ok, "Committed four-second turn must finish after stop without snapping crew to new slots"): return false
	context.vehicle.action = {"stage": "recovering", "elapsed": 0.0, "multiplier": 1.0, "attack_id": "fixture:committed"}
	context.vehicle.phase = "recovering"
	assert(context.controller.vehicles.order_siege(context.key, "stop", {}, int(context.commander), true).ok)
	context.controller.vehicles.advance_ram_actions(0.70)
	if not _require(not context.vehicle.action.is_empty() and not context.controller.vehicles.siege_save_guard().ok, "Stopping a completed impact cannot discard its remaining recovery"): return false
	context.controller.vehicles.advance_ram_actions(0.05)
	if not _require(context.vehicle.action.is_empty() and str(context.vehicle.phase) == "idle", "Committed recovery must finish on the original action-time caller"): return false
	_close_ram(context)
	context = _ram_fixture(4, Vector2i.RIGHT, 1)
	assert(context.controller.vehicles.order_siege(context.key, "turn", {"facing": [0, 1]}, int(context.commander), true).ok)
	_ram_ticks(context, 4.0)
	if not _require(str(context.vehicle.action.get("stage", "")) == "rotate", "Source-drop fixture must first admit the real rotation"): return false
	var lost := {}
	for cell: Vector2i in context.fixture.army.cells: lost[context.data.index(cell)] = 1
	context.data.height_levels.fill(0)
	context.data.navigation_revision += 1
	context.lab.resolve_structure_change(SiteRuntime.ok("rotation support lost", {"lost_surfaces": lost}))
	context.controller.vehicles.update_siege(0.01)
	if not _require(is_equal_approx(float(context.vehicle.hp), 225.0) and context.vehicle.facing == [1, 0] and context.vehicle.action.is_empty() and str(context.vehicle.phase) == "disabled", "A still-flat lowered support must cancel rotation and damage the vehicle once without committing a new facing"): return false
	context.controller.vehicles.update_siege(0.01)
	if not _require(is_equal_approx(float(context.vehicle.hp), 225.0), "Rotation support polling duplicated the vehicle fall"): return false
	_close_ram(context)
	completed += 1
	return true
