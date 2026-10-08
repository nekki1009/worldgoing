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
	var army := Helper.create_test_army(terrain, 1, 0, 2, Vector2i(5, 5))
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	var order: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(15, 5))
	if not _require(bool(order.get("ok", false)), "The MOVE must reserve two final slots"): return
	var plan = army.get_active_deployment_plan()
	var removed_id := army.combat_identity(1)
	var retained_id := army.combat_identity(0)
	var vacated: Vector2i = plan.get_slot_for_member(removed_id)
	var retained: Vector2i = plan.get_slot_for_member(retained_id)
	army.remove_member_from_combat_plans(removed_id)
	if not _require(not coordinator.deployment_registry.is_slot_reserved(vacated) and coordinator.deployment_registry.is_slot_reserved(retained), "Permanent removal must release only an unowned final slot"): return
	var takeover: Dictionary = coordinator.deployment_registry.try_replace_reservations(2, 0, 1, [vacated])
	if not _require(bool(takeover.get("ok", false)), "Another team may lease the permanently vacated slot"): return
	coordinator.deployment_registry.release_order(2)
	var temporary_id := retained_id
	plan.remove_member(temporary_id, Types.SlotVacancyReason.TEMPORARY_ABSENCE)
	army._sync_combat_deployment_leases()
	if not _require(coordinator.deployment_registry.is_slot_reserved(retained), "Temporary absence must preserve its lease during grace"): return
	plan.update_leases(4.1)
	army._sync_combat_deployment_leases()
	if not _require(not coordinator.deployment_registry.is_slot_reserved(retained), "An expired and unowned absence lease must release"): return
	print("COMBAT MOVEMENT VACATED LEASE PASS")
	coordinator.unregister_formation(army)
	army.free()
	quit(0)
