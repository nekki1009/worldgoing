extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

class ThreatLab extends TerrainLab:
	var all_threatened := false
	func _fatigue_threat(_cell: Vector2i, _faction: int, _owner: Variant, _unit: int, _candidates: Dictionary) -> bool:
		return all_threatened

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false

func _run_case(all_threatened: bool) -> bool:
	var label := "THREATENED" if all_threatened else "UNTHREATENED"
	var data := Helper.build_flat_map(30, 25)
	var army := Helper.create_test_army(data, 1, 0, 1, Vector2i(5, 5))
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	var lab := ThreatLab.new()
	lab.terrain = data
	lab.all_threatened = all_threatened
	var controller := SiteController.new()
	controller.lab = lab
	var sustain := SiteSustain.create()
	data.site["team_supply"] = {str(army.team_id): {"sustain": sustain}}
	army.sustain_routed_query = controller.team_is_routed
	var retreat_button := Button.new()

	var order: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(20, 15), -1, Vector2i.RIGHT)
	if not _require(bool(order.get("ok", false)), label + ": initial MOVE must succeed"): return false
	var old_slots: Array[Vector2i] = coordinator.deployment_registry.get_formation_reserved_slots(army.team_id)
	if not _require(not old_slots.is_empty() and army.get_active_move_plan() != null and army.get_active_deployment_plan() != null, label + ": MOVE must own a plan and leases"): return false

	# Start a real committed step before sustain changes the order.
	var source: Vector2i = army.cells[0]
	var destination := source + Vector2i.RIGHT
	var member_id := army.combat_identity(0)
	coordinator._rebuild_occupancy()
	var grid = coordinator.movement_reservation_grid
	grid.begin_tick(coordinator._current_occupancy, data)
	var proposal_id: int = grid.propose_move(army.formation_runtime_id, member_id, army.get_order_serial(), source, destination)
	grid.resolve_all()
	if not _require(grid.proposal_lookup[proposal_id].status == Types.MoveProposalStatus.ACCEPTED, label + ": physical step must be accepted"): return false
	grid.commit_all(coordinator._member_lookup, 1)
	coordinator._register_started_batches()
	army.prepare_combat(0.08)
	if not _require(army.cells[0] == source and army.moving_to[0] == destination and army.move_progress[0] > 0.0 and army.move_progress[0] < 1.0, label + ": physical step must be partially complete"): return false
	var progress := army.move_progress[0]
	if not _require(coordinator.get_inflight_batches_for_formation(army).size() == 1, label + ": committed step must have a completion barrier"): return false

	var before := army.capture_combat_state()
	controller._update_retreat_button(retreat_button, army, army.current_commander)
	if not _require(retreat_button.disabled and retreat_button.tooltip_text.contains("士氣尚未崩潰"), label + ": UI must explain why a captain cannot retreat before collapse"): return false
	controller._start_supply_rout(army)
	if not _require(army.capture_combat_state() == before, label + ": controller cannot manufacture a rout before Sustain collapses"): return false
	sustain.routed = true
	controller._update_retreat_button(retreat_button, army, army.current_commander)
	if not _require(not retreat_button.disabled, label + ": original routed commander may continue withdrawal"): return false
	controller._start_supply_rout(army)
	if not _require(army.combat_order == TerrainArmy.CombatOrder.RETREAT, label + ": sustain must delegate a boundary retreat to the original Army"): return false
	var routed_serial := army.get_order_serial()
	controller._start_supply_rout(army)
	if not _require(army.get_order_serial() == routed_serial, label + ": repeated routed review must keep the accepted order"): return false
	if not _require(army.get_active_move_plan() == null and army.get_active_deployment_plan() == null, label + ": old MOVE plans must be cleared"): return false
	if not _require(coordinator.deployment_registry.get_formation_reserved_slots(army.team_id).is_empty(), label + ": old final-slot leases must be cleared"): return false
	for slot in old_slots:
		if not _require(not coordinator.deployment_registry.is_slot_reserved(slot), label + ": old lease remains at " + str(slot)): return false
	if not _require(army.cells[0] == source and army.moving_to[0] == destination and army.move_progress[0] == progress, label + ": forced order must preserve the committed physical step"): return false
	if not _require(coordinator.get_inflight_batches_for_formation(army).size() == 1, label + ": forced order must preserve its completion barrier"): return false

	army.prepare_combat(0.31)
	coordinator.complete_committed_moves()
	if not _require(army.cells[0] == destination and army.moving_to[0] == TerrainArmy.INVALID_CELL, label + ": committed step must finish at its original destination"): return false
	if not _require(coordinator.get_inflight_batches_for_formation(army).is_empty() and army._reserved_cells.is_empty(), label + ": completion must clear physical claims"): return false
	coordinator.unregister_formation(army)
	army.sustain_routed_query = Callable()
	retreat_button.free()
	controller.lab = null
	controller.free()
	lab.free()
	army.free()
	return true

func _run() -> void:
	if not _run_case(false): return
	if not _run_case(true): return
	print("COMBAT MOVEMENT SUPPLY ROUT TRANSITION PASS: original Sustain authority, disabled UI reason, Army delegation/idempotence, released deployment leases and preserved in-flight step")
	quit(0)
