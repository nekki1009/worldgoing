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

func _run_case(action: String) -> bool:
	var terrain := Helper.build_flat_map(30, 25)
	var army := Helper.create_test_army(terrain, 1, 0, 1, Vector2i(5, 5))
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	var move: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(20, 15))
	if not _require(bool(move.get("ok", false)), action + ": initial MOVE must reserve final slots"):
		army.free()
		return false
	var slots: Array[Vector2i] = coordinator.deployment_registry.get_formation_reserved_slots(1)
	if not _require(not slots.is_empty(), action + ": initial lease missing"):
		army.free()
		return false
	var order: Dictionary = {}
	match action:
		"hold":
			order = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.HOLD)
			if not _require(bool(order.get("ok", false)), "HOLD must succeed"): return false
		"attack":
			order = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.ATTACK)
			if not _require(bool(order.get("ok", false)), "ATTACK must succeed"): return false
		"retreat":
			order = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.RETREAT, Vector2i(10, 10))
			if not _require(bool(order.get("ok", false)), "RETREAT must succeed"): return false
		"local_move":
			order = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(6, 5))
			if not _require(bool(order.get("ok", false)) and army.get_active_move_plan() != null and army.get_active_deployment_plan() != null, "Short MOVE must replace the old deployment through the formal path"): return false
		"clear":
			army.clear()
		"unregister":
			coordinator.unregister_formation(army)
	if action == "local_move":
		for slot: Vector2i in slots:
			if not _require(coordinator.deployment_registry.owner_of(slot) == null, "Short MOVE must release each old final slot"): return false
	else:
		if not _require(coordinator.deployment_registry.get_formation_reserved_slots(1).is_empty(), action + ": old lease must be released"): return false
	var takeover: Dictionary = coordinator.deployment_registry.try_replace_reservations(2, 0, 1, slots)
	if not _require(bool(takeover.get("ok", false)), action + ": another formation must be able to reserve released slots"): return false
	coordinator.deployment_registry.release_order(2)
	if action != "unregister":
		coordinator.unregister_formation(army)
	army.free()
	return true

func _run() -> void:
	for action in ["hold", "attack", "retreat", "local_move", "clear", "unregister"]:
		if not _run_case(action):
			return
	print("COMBAT MOVEMENT LEASE LIFECYCLE PASS")
	quit(0)
