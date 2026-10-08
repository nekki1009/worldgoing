extends SceneTree
## Real contact KO releases a stationary cell, but a committed batch keeps its
## source and destination claims until its original physical step finishes.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false

func _run() -> void:
	var data: TerrainData = Helper.build_flat_map(30, 20)
	var army: TerrainArmy = Helper.create_test_army(data, 1, 0, 3, Vector2i(5, 5))
	var coordinator: SiteCombatMovementCoordinator = Coordinator.new()
	coordinator.register_formation(army)
	var order: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(15, 5))
	if not _require(bool(order.get("ok", false)), "MOVE must establish a real deployment before KO"): return
	var sources: Array[Vector2i] = army.cells.duplicate()
	coordinator._rebuild_occupancy()
	var grid: SiteMovementReservationGrid = coordinator.movement_reservation_grid
	grid.begin_tick(coordinator._current_occupancy, data)
	for index in range(2, -1, -1):
		grid.propose_move(army.formation_runtime_id, army.combat_identity(index), army.get_order_serial(), sources[index], sources[index] + Vector2i.RIGHT)
	grid.resolve_all()
	grid.commit_all(coordinator._member_lookup, 1)
	coordinator._register_started_batches()
	if not _require(coordinator._inflight_batches.size() == 1 and army.moving_to[1] == sources[1] + Vector2i.RIGHT,
		"Three members must begin one original physical chain"): return
	army.prepare_combat(0.072)
	var middle_id: int = army.combat_identity(1)
	army.apply_unit_contact(1, {"result": {"hp": 0.0, "stun": 110.0, "guard_break": false}, "shield": false})
	if not _require(float(army.combat_units[1].ko) > 0.0 and army._cell_owners.get(sources[1], -1) == 1
		and army.get_active_members_occupancy().get(middle_id) == sources[1],
		"Contact KO during a committed step must retain its physical source"): return
	# TerrainLab settles command presence after all contacts, before a save can run.
	army.settle_combat_command()
	if not _require(not bool(army.combat_units[1].present) and army._cell_owners.get(sources[1], -1) == 1,
		"Settling KO presence must not discard the committed physical source"): return
	coordinator._rebuild_occupancy()
	grid.begin_tick(coordinator._current_occupancy, data, army.get_active_movement_claims())
	if not _require(grid.initial_occupancy.get(sources[1]) == middle_id and grid.blocked_destinations.has(army.moving_to[1]),
		"Grid must protect both ends of the in-flight KO step"): return
	var mid_step: Dictionary = JSON.parse_string(JSON.stringify(army.capture_combat_state()))
	var roster_valid: bool = TerrainArmy.valid_combat_state(mid_step, data)
	var movement_valid: bool = Store._valid_combat_movement_snapshot(data, mid_step, {})
	var site_valid: Dictionary = Store._validate_armies(data, {"actors": {}, "armies": [mid_step]}, true)
	if not _require(roster_valid and movement_valid and bool(site_valid.get("ok", false)),
		"A real mid-chain KO must remain a valid save snapshot: roster=%s movement=%s site=%s" % [roster_valid, movement_valid, site_valid]): return
	army.prepare_combat(0.5)
	coordinator.complete_committed_moves()
	var released_cell: Vector2i = sources[1] + Vector2i.RIGHT
	if not _require(coordinator._inflight_batches.is_empty() and army.cells[1] == released_cell
		and army.moving_to[1] == TerrainArmy.INVALID_CELL and not army.blocks_cell(released_cell)
		and not army.get_active_members_occupancy().has(middle_id),
		"Finished KO step must release its safe endpoint without dropping the chain"): return
	var probe: TerrainArmy = Helper.create_test_army(data, 2, 1, 1, released_cell + Vector2i.DOWN)
	coordinator.register_formation(probe)
	coordinator._rebuild_occupancy()
	grid.begin_tick(coordinator._current_occupancy, data)
	var proposal_id: int = grid.propose_move(probe.formation_runtime_id, probe.combat_identity(0), 0, probe.cells[0], released_cell)
	grid.resolve_all()
	if not _require(proposal_id >= 0 and grid.proposal_lookup[proposal_id].status == Types.MoveProposalStatus.ACCEPTED,
		"Grid must allow another team to enter the stationary KO cell"): return
	coordinator.unregister_formation(probe)
	probe.free()
	var standing: TerrainArmy = Helper.create_test_army(data, 2, 1, 1, released_cell)
	coordinator.register_formation(standing)
	coordinator._rebuild_occupancy()
	if not _require(coordinator._current_occupancy.get(released_cell) == standing.combat_identity(0),
		"Coordinator must register only the standing owner of the KO cell"): return
	var saved_ko: Dictionary = JSON.parse_string(JSON.stringify(army.capture_combat_state()))
	var saved_standing: Dictionary = JSON.parse_string(JSON.stringify(standing.capture_combat_state()))
	if not _require(bool(Store._validate_armies(data, {"actors": {}, "armies": [saved_ko, saved_standing]}, true).get("ok", false)),
		"SiteStore must accept a standing member sharing a released KO cell"): return
	coordinator.unregister_formation(army)
	coordinator.unregister_formation(standing)
	army.free()
	standing.free()
	print("COMBAT MOVEMENT CONTACT KO OCCUPANCY PASS")
	quit(0)
