extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")

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
	var army := Helper.create_test_army(terrain, 1, 0, 2, Vector2i(5, 5))
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	if not _require(bool(army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(15, 5)).get("ok", false)), "MOVE must start"): return
	var source: Array[Vector2i] = army.cells.duplicate()
	var old_slots: Array[Vector2i] = coordinator.deployment_registry.get_formation_reserved_slots(1)
	if not _require(not old_slots.is_empty(), "MOVE must own final-slot leases"): return
	coordinator._rebuild_occupancy()
	var grid = coordinator.movement_reservation_grid
	grid.begin_tick(coordinator._current_occupancy, terrain)
	for i in range(1, -1, -1):
		grid.propose_move(army.formation_runtime_id, army.combat_identity(i), army.get_order_serial(), source[i], source[i] + Vector2i.RIGHT)
	grid.resolve_all()
	grid.commit_all(coordinator._member_lookup, 1)
	coordinator._register_started_batches()
	if not _require(coordinator._inflight_batches.size() == 1, "The committed chain must exist before terminal recovery"): return
	army.cancel_combat_deployment_for_forced_order()
	army.combat_order = TerrainArmy.CombatOrder.HOLD
	if not _require(army.get_active_move_plan() == null and army.get_active_deployment_plan() == null and coordinator.deployment_registry.get_formation_reserved_slots(1).is_empty(), "Terminal recovery must release the unfinished destination contract"): return
	for i in range(2):
		if not _require(army.cells[i] == source[i] and army.moving_to[i] == source[i] + Vector2i.RIGHT and army.combat_slots[i] == army.moving_to[i], "Terminal recovery must retain the in-flight physical step and its safe endpoint"): return
	army.prepare_combat(0.5)
	coordinator.complete_committed_moves()
	if not _require(coordinator._inflight_batches.is_empty() and army._combat_batch_members.is_empty(), "The old physical batch must close after terminal recovery"): return
	for i in range(2):
		if not _require(army.cells[i] == source[i] + Vector2i.RIGHT and army.moving_to[i] == TerrainArmy.INVALID_CELL, "The committed step must finish without teleporting"): return
	var replacement: Dictionary = coordinator.deployment_registry.try_replace_reservations(2, 0, 1, old_slots)
	if not _require(bool(replacement.get("ok", false)), "Another team may claim released failed-order slots"): return
	print("COMBAT MOVEMENT TERMINAL RECOVERY PASS")
	coordinator.deployment_registry.release_order(2)
	coordinator.unregister_formation(army)
	army.free()
	quit(0)
