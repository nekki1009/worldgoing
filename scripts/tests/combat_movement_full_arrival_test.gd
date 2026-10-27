extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")

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
	var data := Helper.build_flat_map(14, 14)
	var army := Helper.create_test_army(data, 1, 0, 4, Vector2i(2, 5))
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	var order: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(10, 5), -1, Vector2i.RIGHT)
	if not _require(bool(order.get("ok", false)), "The four-person formal MOVE order must be accepted"): return
	var plan = army.get_active_deployment_plan()
	if not _require(plan != null and plan.final_facing == Vector2i.RIGHT, "Explicit final facing must survive planning"): return
	var previous: Array[Vector2i] = army.cells.duplicate()
	var completed_tick := -1
	for tick in range(1200):
		coordinator.combat_logic_tick(0.05)
		army.prepare_combat(0.05)
		coordinator.complete_committed_moves()
		var source_owners: Dictionary = {}
		var destination_claims: Dictionary = {}
		for i in range(4):
			var cell: Vector2i = army.cells[i]
			if not _require(data.contains(cell) and data.is_walkable(cell), "A member must remain on legal terrain at tick %d" % tick): return
			if not _require(not source_owners.has(cell), "Physical source cells must remain unique at tick %d" % tick): return
			source_owners[cell] = true
			if cell != previous[i] and not _require(data.can_step(previous[i], cell), "A member must commit only one legal edge at tick %d" % tick): return
			previous[i] = cell
			var destination: Vector2i = army.moving_to[i]
			if destination != TerrainArmy.INVALID_CELL:
				if not _require(not destination_claims.has(destination), "In-flight destination claims must remain unique at tick %d" % tick): return
				destination_claims[destination] = true
		if army.combat_order == TerrainArmy.CombatOrder.HOLD:
			completed_tick = tick
			break
	if not _require(completed_tick >= 0, "All four members must finish, not merely make early progress; status=" + army.command_status): return
	if not _require(army.command_status.begins_with("已抵達"), "HOLD must mean actual arrival, not congestion or route failure"): return
	if not _require(Destination.is_settled(plan, army.get_active_members_occupancy()), "Every member must occupy its assigned final slot"): return
	for i in range(4):
		if not _require(army.moving_to[i] == TerrainArmy.INVALID_CELL and army.facing[i] == Vector2i.RIGHT, "Arrival must finish physical steps and apply final facing"): return
	var final_cells: Array[Vector2i] = army.cells.duplicate()
	var final_slots: Dictionary = plan.member_slot_map.duplicate()
	for tick in range(100):
		coordinator.combat_logic_tick(0.05)
		army.prepare_combat(0.05)
		coordinator.complete_committed_moves()
		if not _require(army.combat_order == TerrainArmy.CombatOrder.HOLD and army.cells == final_cells and plan.member_slot_map == final_slots, "Arrival must remain stable for five simulated seconds at tick %d" % tick): return
		if not _require(army._reserved_cells.is_empty() and coordinator.get_inflight_batches_for_formation(army).is_empty(), "Arrival must leave no in-flight movement claims"): return
	for slot: Vector2i in final_slots.values():
		var lease = coordinator.deployment_registry.owner_of(slot)
		if not _require(lease != null and lease.formation_id == army.team_id and lease.order_serial == plan.order_serial, "The completed formation must retain its final-slot lease"): return
	print("COMBAT MOVEMENT FULL ARRIVAL PASS: tick=", completed_tick)
	coordinator.unregister_formation(army)
	army.free()
	TerrainArmy.release_contact_source() # Headless teardown: release the shared contact rig before the post-quit frame (as 8ab42b0/54cd151).
	quit(0)
