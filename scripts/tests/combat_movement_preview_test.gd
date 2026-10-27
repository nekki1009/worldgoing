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
	var terrain := Helper.build_flat_map(24, 20)
	var army := Helper.create_test_army(terrain, 1, 0, 4, Vector2i(3, 5))
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	var serial_before := army.get_order_serial()
	var cells_before: Array[Vector2i] = army.cells.duplicate()
	var preview: Dictionary = army.preview_combat_move(Vector2i(14, 5), Vector2i.UP)
	if not _require(bool(preview.get("ok", false)) and preview.resolved_anchor == Vector2i(14, 5) and preview.final_facing == Vector2i.UP, "Preview must resolve the same final anchor and facing as MOVE"): return
	if not _require(preview.platform_slots.size() + preview.approach_queue_slots.size() == 4, "Preview must return only four assigned final slots"): return
	if not _require(army.get_order_serial() == serial_before and army.get_active_move_plan() == null and army.get_active_deployment_plan() == null and army.cells == cells_before and coordinator.deployment_registry.get_formation_reserved_slots(1).is_empty(), "Preview must not mutate order, movement, cells, or leases"): return
	var invalid: Dictionary = army.preview_combat_move(Vector2i(14, 5), Vector2i(1, 1))
	if not _require(not bool(invalid.get("ok", false)) and invalid.has("code") and invalid.has("message") and army.get_order_serial() == serial_before, "Invalid facing preview must report failure without changing serial"): return
	if not _require(bool(army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(14, 5), -1, Vector2i.UP).get("ok", false)), "The previewed MOVE must be accepted"): return
	var plan = army.get_active_deployment_plan()
	var actual_platform: Array[Vector2i] = []
	var actual_queue: Array[Vector2i] = []
	for mid in plan.member_slot_map.keys():
		var slot: Vector2i = plan.member_slot_map[mid]
		if int(plan.member_role_map.get(mid, Types.CombatDestinationRole.PLATFORM)) == Types.CombatDestinationRole.PLATFORM:
			actual_platform.append(slot)
		else:
			actual_queue.append(slot)
	if not _require(plan.resolved_anchor == preview.resolved_anchor and plan.final_facing == preview.final_facing and actual_platform == preview.platform_slots and actual_queue == preview.approach_queue_slots, "Preview geometry must exactly match the issued deployment"): return
	var active_plan = army.get_active_move_plan()
	var serial_active := army.get_order_serial()
	var leased: Array[Vector2i] = coordinator.deployment_registry.get_formation_reserved_slots(1)
	army.preview_combat_move(Vector2i(16, 8), Vector2i.LEFT)
	if not _require(army.get_active_move_plan() == active_plan and army.get_order_serial() == serial_active and coordinator.deployment_registry.get_formation_reserved_slots(1) == leased, "Previewing another destination must leave the active MOVE and its leases untouched"): return
	print("COMBAT MOVEMENT PREVIEW PASS")
	coordinator.unregister_formation(army)
	army.free()
	TerrainArmy.release_contact_source() # Headless teardown: release the shared contact rig before the post-quit frame (as 8ab42b0/54cd151).
	quit(0)
