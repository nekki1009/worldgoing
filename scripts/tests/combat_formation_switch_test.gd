extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		TerrainArmy.release_contact_source() # Headless teardown: release the shared contact rig before the post-quit frame (as 8ab42b0/54cd151).
		quit(1)
	return ok

func _drive_to_hold(army: TerrainArmy, coordinator: Object, terrain: TerrainData, limit: int) -> bool:
	var previous: Array[Vector2i] = army.cells.duplicate()
	for tick in range(limit):
		coordinator.combat_logic_tick(0.05)
		army.prepare_combat(0.05)
		coordinator.complete_committed_moves()
		var occupied: Dictionary = {}
		var claims: Dictionary = {}
		for i in range(army.cells.size()):
			if not army.is_member(i):
				continue
			var cell: Vector2i = army.cells[i]
			if not _require(terrain.is_walkable(cell) and not occupied.has(cell), "Member left legal unique ground at tick %d" % tick): return false
			occupied[cell] = true
			if cell != previous[i] and not _require(terrain.can_step(previous[i], cell), "Member skipped a physical edge at tick %d" % tick): return false
			previous[i] = cell
			var claim: Vector2i = army.moving_to[i]
			if claim != TerrainArmy.INVALID_CELL:
				if not _require(not claims.has(claim), "Two members claimed one step at tick %d" % tick): return false
				claims[claim] = true
		if army.combat_order == TerrainArmy.CombatOrder.HOLD:
			if army.command_status.begins_with("已抵達"):
				return true
			return _require(false, "Reform aborted at tick %d: %s cells=%s slots=%s" % [tick, army.command_status,
				str(army.cells), str(army.get_active_deployment_plan().member_slot_map) if army.get_active_deployment_plan() != null else "released"])
	return _require(false, "Formation did not finish every assigned slot: " + army.command_status)

func _check_settled(army: TerrainArmy, coordinator: Object, preset: String, count: int) -> bool:
	var plan: CombatDeploymentPlan = army.get_active_deployment_plan()
	if not _require(plan != null and plan.formation_preset_id == preset and plan.member_slot_map.size() == count,
		"HOLD retained the wrong formation contract for %s: actual=%s count=%d status=%s" % [preset,
			plan.formation_preset_id if plan != null else "null", plan.member_slot_map.size() if plan != null else -1, army.command_status]): return false
	if not _require(Destination.is_settled(plan, army.get_active_members_occupancy()), "A member missed its assigned final slot"): return false
	var expected: Dictionary = {}
	for slot in Destination.shape_slots(preset, count, plan.resolved_anchor, plan.final_facing):
		expected[slot] = true
	for slot: Vector2i in plan.member_slot_map.values():
		if not _require(expected.erase(slot), "Final slot does not match the selected shape"): return false
		var lease = coordinator.deployment_registry.owner_of(slot)
		if not _require(lease != null and lease.formation_id == army.team_id and lease.order_serial == plan.order_serial, "Final slot lost its lease"): return false
	if not _require(expected.is_empty(), "Final shape has unassigned cells"): return false
	for i in range(army.cells.size()):
		if army.is_member(i) and not _require(army.moving_to[i] == TerrainArmy.INVALID_CELL and army.facing[i] == plan.get_facing_for_slot(army.cells[i]), "Settled member has an unfinished step or wrong facing"): return false
	var final_cells: Array[Vector2i] = army.cells.duplicate()
	for tick in range(100):
		coordinator.combat_logic_tick(0.05)
		army.prepare_combat(0.05)
		coordinator.complete_committed_moves()
		if not _require(army.combat_order == TerrainArmy.CombatOrder.HOLD and army.cells == final_cells and coordinator.get_inflight_batches_for_formation(army).is_empty(), "HOLD drifted during five stable seconds"): return false
	return true

func _run() -> void:
	var terrain := Helper.build_flat_map(48, 36)
	var army := Helper.create_test_army(terrain, 1, 0, 9, Vector2i(3, 14))
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	var goal := Vector2i(28, 17)
	var original_cells: Array[Vector2i] = army.cells.duplicate()
	var original_serial := army.get_order_serial()
	var preview: Dictionary = army.preview_combat_move(goal, Vector2i.RIGHT, "square")
	if not _require(bool(preview.get("ok", false)) and preview.formation_preset_id == "square" and preview.platform_slots.size() == 9, "Square preview failed"): return
	if not _require(army.cells == original_cells and army.get_order_serial() == original_serial and coordinator.deployment_registry.get_formation_reserved_slots(1).is_empty(), "Preview changed Army state or leases"): return
	if not _require(bool(army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, goal, -1, Vector2i.RIGHT, "square").get("ok", false)), "Square MOVE was rejected"): return
	var submitted: CombatDeploymentPlan = army.get_active_deployment_plan()
	if not _require(submitted.platform_slots == preview.platform_slots and army.formation_preset_id == "square", "Preview and submitted slots differ"): return
	for tick in range(25):
		coordinator.combat_logic_tick(0.05)
		army.prepare_combat(0.05)
		coordinator.complete_committed_moves()
	var before_switch: Array[Vector2i] = army.cells.duplicate()
	var in_flight: Array[Vector2i] = army.moving_to.duplicate()
	var serial_before_switch := army.get_order_serial()
	var square_plan: CombatDeploymentPlan = army.get_active_deployment_plan()
	var square_move_plan: CombatMovePlan = army.get_active_move_plan()
	var square_leases: Array[Vector2i] = coordinator.deployment_registry.get_formation_reserved_slots(1)
	if not _require(bool(army.issue_formation_change(army.current_commander, "square").get("ok", false)) \
		and army.get_order_serial() == serial_before_switch and army.get_active_deployment_plan() == square_plan \
		and army.get_active_move_plan() == square_move_plan and army.cells == before_switch and army.moving_to == in_flight \
		and coordinator.deployment_registry.get_formation_reserved_slots(1) == square_leases,
		"Same in-transit shape should not reset the contract or physical step"): return
	if not _require(bool(army.issue_formation_change(army.current_commander, "wedge").get("ok", false)), "Mid-MOVE wedge switch was rejected"): return
	if not _require(army.cells == before_switch and army.moving_to == in_flight and army.get_order_serial() == serial_before_switch + 1 and army.formation_preset_id == "wedge", "Switch teleported a member, cancelled a committed step, or lost its command serial"): return
	var active_plan: CombatDeploymentPlan = army.get_active_deployment_plan()
	var active_slots: Dictionary = active_plan.member_slot_map.duplicate()
	var active_leases: Array[Vector2i] = coordinator.deployment_registry.get_formation_reserved_slots(1)
	var rejected: Dictionary = army.issue_formation_change(army.current_commander, "unknown")
	if not _require(not bool(rejected.get("ok", false)) and army.get_order_serial() == serial_before_switch + 1 and army.formation_preset_id == "wedge" and army.get_active_deployment_plan() == active_plan and active_plan.member_slot_map == active_slots and coordinator.deployment_registry.get_formation_reserved_slots(1) == active_leases, "Rejected switch changed the active contract"): return
	if not _drive_to_hold(army, coordinator, terrain, 1800): return
	if not _check_settled(army, coordinator, "wedge", 9): return
	var settled_serial := army.get_order_serial()
	if not _require(bool(army.issue_formation_change(army.current_commander, "wedge").get("ok", false)) and army.get_order_serial() == settled_serial and army.combat_order == TerrainArmy.CombatOrder.HOLD, "Same settled shape should be a no-op"): return
	if not _require(bool(army.issue_formation_change(army.current_commander, "circle").get("ok", false)), "HOLD-to-circle switch was rejected"): return
	if not _drive_to_hold(army, coordinator, terrain, 1800): return
	if not _check_settled(army, coordinator, "circle", 9): return
	for preset in ["goose", "hook", "loose", "square"]:
		if not _require(bool(army.issue_formation_change(army.current_commander, preset).get("ok", false)), "HOLD switch to %s was rejected" % preset): return
		if not _drive_to_hold(army, coordinator, terrain, 1800): return
		if not _check_settled(army, coordinator, preset, 9): return
	var fallen := army.cells.size() - 1
	var fallen_id := army.combat_identity(fallen)
	var last_serial := army.get_order_serial()
	army.combat_units[fallen].hp = 0.0
	army.combat_units[fallen].dead = true
	army._cell_owners.erase(army.cells[fallen])
	army.remove_member_from_combat_plans(fallen_id)
	if not _require(bool(army.issue_formation_change(army.current_commander, "square").get("ok", false))
		and army.get_order_serial() == last_serial + 1 and army.get_active_deployment_plan().requested_count == 8,
		"A casualty must replan the same selected shape for the new active count"): return
	print("COMBAT FORMATION SWITCH PASS")
	coordinator.unregister_formation(army)
	army.free()
	TerrainArmy.release_contact_source() # Headless teardown: release the shared contact rig before the post-quit frame (as 8ab42b0/54cd151).
	quit(0)
