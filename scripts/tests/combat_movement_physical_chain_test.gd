extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	TerrainArmy.release_contact_source() # Headless teardown: release the shared contact rig before the post-quit frame (as 8ab42b0/54cd151).
	quit(1)
	return false

func _run() -> void:
	var data := Helper.build_flat_map(30, 20)
	var army := Helper.create_test_army(data, 1, 0, 3, Vector2i(5, 5))
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	var order: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(15, 5), -1, Vector2i.RIGHT)
	if not _require(bool(order.get("ok", false)), "A full MOVE order must be accepted for the chain test"): return
	var original: Array[Vector2i] = [army.cells[0], army.cells[1], army.cells[2]]
	var member_ids: Array[int] = [army.combat_identity(0), army.combat_identity(1), army.combat_identity(2)]
	coordinator._rebuild_occupancy()
	var grid = coordinator.movement_reservation_grid
	grid.begin_tick(coordinator._current_occupancy, data)
	var proposal_ids: Array[int] = []
	for i in range(2, -1, -1):
		proposal_ids.append(grid.propose_move(army.formation_runtime_id, member_ids[i], army.get_order_serial(), original[i], original[i] + Vector2i.RIGHT))
	grid.resolve_all()
	for pid in proposal_ids:
		if not _require(grid.proposal_lookup[pid].status == Types.MoveProposalStatus.ACCEPTED, "The empty-tail chain must resolve atomically"): return
	grid.commit_all(coordinator._member_lookup, 1)
	coordinator._register_started_batches()
	for i in range(3):
		if not _require(army.cells[i] == original[i], "Starting a move must keep its source cell authoritative"): return
		if not _require(army.moving_to[i] == original[i] + Vector2i.RIGHT, "Every chain member must start the original movement step"): return
	army.prepare_combat(0.19)
	coordinator.complete_committed_moves()
	for i in range(3):
		if not _require(army.cells[i] == original[i], "A partial step must not commit any chain member"): return
		if not _require(army.move_progress[i] > 0.0 and army.move_progress[i] < 1.0, "A partial step must interpolate over time"): return
	army.prepare_combat(0.20)
	coordinator.complete_committed_moves()
	var occupied: Dictionary = {}
	for i in range(3):
		if not _require(army.cells[i] == original[i] + Vector2i.RIGHT, "The whole chain must reach its destination together"): return
		if not _require(army.moving_to[i] == TerrainArmy.INVALID_CELL, "The original movement state must finish"): return
		if not _require(not occupied.has(army.cells[i]), "Completed members must own unique cells"): return
		occupied[army.cells[i]] = true
	if not _require(army._cell_owners.size() == 3 and army._reserved_cells.is_empty(), "Ownership and destination claims must close at the completion barrier"): return
	print("COMBAT MOVEMENT PHYSICAL CHAIN PASS")
	coordinator.unregister_formation(army)
	army.free()
	TerrainArmy.release_contact_source() # Headless teardown: release the shared contact rig before the post-quit frame (as 8ab42b0/54cd151).
	quit(0)
