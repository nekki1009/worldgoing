extends SceneTree
## A reciprocal same-formation pair must keep both sources until one physical
## completion barrier, including after restoring its in-flight batch.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if not condition:
		push_error("PHYSICAL PAIR SWAP FAIL: " + message)
		TerrainArmy.release_contact_source() # Headless teardown: release the shared contact rig before the post-quit frame (as 8ab42b0/54cd151).
		quit(1)
	return condition

func _run() -> void:
	var terrain: TerrainData = Helper.build_flat_map(24, 16)
	var army: TerrainArmy = Helper.create_test_army(terrain, 1, 0, 2, Vector2i(5, 5))
	var coordinator: SiteCombatMovementCoordinator = Coordinator.new()
	coordinator.register_formation(army)
	var order: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(15, 5), -1, Vector2i.RIGHT)
	if not _require(bool(order.get("ok", false)), "the original MOVE order must be accepted"): return
	var first: Vector2i = army.cells[0]
	var second: Vector2i = army.cells[1]
	if not _require(first + Vector2i.RIGHT == second, "fixture members must be orthogonally adjacent"): return
	coordinator._rebuild_occupancy()
	var grid: SiteMovementReservationGrid = coordinator.movement_reservation_grid
	grid.begin_tick(coordinator._current_occupancy, terrain)
	var second_id: int = army.combat_identity(1)
	var first_id: int = army.combat_identity(0)
	var second_pid: int = grid.propose_move(army.formation_runtime_id, second_id, army.get_order_serial(), second, first)
	var first_pid: int = grid.propose_move(army.formation_runtime_id, first_id, army.get_order_serial(), first, second)
	grid.resolve_all()
	if not _require(grid.proposal_lookup[first_pid].status == Types.MoveProposalStatus.ACCEPTED and grid.proposal_lookup[second_pid].status == Types.MoveProposalStatus.ACCEPTED,
		"both sides of the same-formation pair must resolve together"): return
	grid.commit_all(coordinator._member_lookup, 1)
	coordinator._register_started_batches()
	var batches: Array = coordinator.get_inflight_batches_for_formation(army)
	if not _require(batches.size() == 1 and batches[0].size() == 2 and batches[0].has(first_id) and batches[0].has(second_id),
		"the pair must have one common in-flight completion batch"): return
	if not _require(army.cells[0] == first and army.cells[1] == second and army.moving_to[0] == second and army.moving_to[1] == first,
		"starting the pair must preserve both authoritative source cells"): return
	army.prepare_combat(0.11)
	coordinator.complete_committed_moves()
	if not _require(army.combat_ground(0).distance_to(army.combat_ground(1)) < TerrainRenderer.CELL_PIXELS * 0.05,
		"straight logical trajectories must meet near the crossing midpoint"): return
	if not _require(army.combat_visual_ground(0).distance_to(army.combat_visual_ground(1)) > TerrainRenderer.CELL_PIXELS * 0.5,
		"the visual sidestep must keep both bodies separated at the crossing midpoint"): return
	army.prepare_combat(0.08)
	coordinator.complete_committed_moves()
	if not _require(army.cells[0] == first and army.cells[1] == second and army.move_progress[0] > 0.0 and army.move_progress[1] > 0.0,
		"partial interpolation must not commit either source cell"): return
	var moving_snapshot: Dictionary = army.capture_combat_state()
	if not _require(moving_snapshot.combat_batches.size() == 1 and moving_snapshot.combat_batches[0].size() == 2
		and moving_snapshot.get("combat_batch_retreat_members", []).is_empty()
		and moving_snapshot.get("combat_batch_move_members", []).size() == 2
		and Store._valid_combat_movement_snapshot(terrain, moving_snapshot, {}),
		"SiteStore must accept a real in-flight MOVE pair without RETREAT markers"): return
	var unmarked_move: Dictionary = moving_snapshot.duplicate(true)
	unmarked_move.erase("combat_batch_move_members")
	if not _require(not Store._valid_combat_movement_snapshot(terrain, unmarked_move, {}),
		"SiteStore must reject a forged MOVE pair without its in-flight MOVE markers"): return
	var hold_result: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.HOLD)
	if not _require(bool(hold_result.get("ok", false)) and army.moving_to[0] == second and army.moving_to[1] == first,
		"HOLD must preserve a pair that already began its physical step"): return
	var held_snapshot: Dictionary = army.capture_combat_state()
	if not _require(int(held_snapshot.combat_order) == TerrainArmy.CombatOrder.HOLD
		and held_snapshot.combat_batches.size() == 1 and held_snapshot.combat_batches[0].size() == 2
		and held_snapshot.get("combat_batch_retreat_members", []).is_empty()
		and held_snapshot.get("combat_batch_move_members", []).size() == 2
		and Store._valid_combat_movement_snapshot(terrain, held_snapshot, {}),
		"SiteStore must accept the in-flight MOVE pair after a new HOLD order"): return
	coordinator.restore_inflight_batches_for_formation(army, batches)
	if not _require(coordinator.get_inflight_batches_for_formation(army) == batches, "restored pair must remain one batch"): return
	army.prepare_combat(0.20)
	coordinator.complete_committed_moves()
	if not _require(army.cells[0] == second and army.cells[1] == first and army.moving_to[0] == TerrainArmy.INVALID_CELL and army.moving_to[1] == TerrainArmy.INVALID_CELL,
		"both members must exchange cells at the same completion barrier"): return
	if not _require(army.combat_visual_ground(0) == army.combat_ground(0) and army.combat_visual_ground(1) == army.combat_ground(1),
		"the sidestep must return both visuals to their exact final cell centers"): return
	if not _require(army._cell_owners.size() == 2 and army._cell_owners.get(first, -1) == 1 and army._cell_owners.get(second, -1) == 0 and army._reserved_cells.is_empty(),
		"completion must preserve unique cell ownership and clear both claims"): return
	if not _require(coordinator.get_inflight_batches_for_formation(army).is_empty() and coordinator._current_occupancy.get(first, -1) == second_id and coordinator._current_occupancy.get(second, -1) == first_id,
		"the coordinator occupancy must match the finished physical pair"): return
	print("COMBAT MOVEMENT PHYSICAL PAIR SWAP PASS")
	coordinator.unregister_formation(army)
	army.free()
	TerrainArmy.release_contact_source() # Headless teardown: release the shared contact rig before the post-quit frame (as 8ab42b0/54cd151).
	quit(0)
