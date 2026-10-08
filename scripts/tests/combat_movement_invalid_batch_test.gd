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
	quit(1)
	return false

func _run() -> void:
	var terrain := Helper.build_flat_map(30, 20)
	var army := Helper.create_test_army(terrain, 1, 0, 3, Vector2i(5, 5))
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	var order: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(15, 5))
	if not _require(bool(order.get("ok", false)), "The initial MOVE must reserve the chain"): return
	var source: Array[Vector2i] = army.cells.duplicate()
	coordinator._rebuild_occupancy()
	var grid = coordinator.movement_reservation_grid
	grid.begin_tick(coordinator._current_occupancy, terrain)
	for i in range(2, -1, -1):
		grid.propose_move(army.formation_runtime_id, army.combat_identity(i), army.get_order_serial(), source[i], source[i] + Vector2i.RIGHT)
	grid.resolve_all()
	grid.commit_all(coordinator._member_lookup, 1)
	coordinator._register_started_batches()
	if not _require(coordinator._inflight_batches.size() == 1, "The three steps must form one physical batch"): return
	army.prepare_combat(0.072)
	if not _require(army.move_progress[0] > 0.1 and army.move_progress[0] < 0.3, "Terrain must change during an in-flight step, before its commit boundary"): return
	terrain.static_blocked[terrain.index(source[2] + Vector2i.RIGHT)] = 1
	terrain.navigation_revision += 1
	army.prepare_combat(0.5)
	if not _require(army.cells == source, "A changed edge must not commit any chain member before the batch barrier"): return
	coordinator.complete_committed_moves()
	if not _require(coordinator._inflight_batches.is_empty() and army._combat_batch_members.is_empty(), "An invalid edge must cancel the whole batch"): return
	var occupied: Dictionary = {}
	for i in range(3):
		if not _require(army.cells[i] == source[i] and army.moving_to[i] == TerrainArmy.INVALID_CELL, "Canceled members must retain their authoritative source cells"): return
		if not _require(not occupied.has(army.cells[i]), "Canceling a batch must not overlap members"): return
		occupied[army.cells[i]] = true
	if not _require(army._reserved_cells.is_empty() and army.combat_order == TerrainArmy.CombatOrder.HOLD, "Canceled claims must close and MOVE must stop"): return
	if not _require(coordinator.deployment_registry.get_formation_reserved_slots(1).is_empty(), "Invalidated MOVE must release its final-slot leases"): return
	print("COMBAT MOVEMENT INVALID BATCH PASS")
	coordinator.unregister_formation(army)
	army.free()
	quit(0)
