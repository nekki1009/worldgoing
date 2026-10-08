extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const ArmyScript = preload("res://scripts/terrain_lab/terrain_army.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false

func _run() -> void:
	var data := Helper.build_flat_map(30, 20)
	var army := Helper.create_test_army(data, 1, 0, 3, Vector2i(5, 5))
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	var order: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(15, 5), -1, Vector2i.RIGHT)
	if not _require(bool(order.get("ok", false)), "The three-person save order must be accepted"): return
	var initial: Array[Vector2i] = army.cells.duplicate()
	var mids: Array[int] = [army.combat_identity(0), army.combat_identity(1), army.combat_identity(2)]
	coordinator._rebuild_occupancy()
	var grid = coordinator.movement_reservation_grid
	grid.begin_tick(coordinator._current_occupancy, data)
	for i in range(2, -1, -1):
		grid.propose_move(army.formation_runtime_id, mids[i], army.get_order_serial(), initial[i], initial[i] + Vector2i.RIGHT)
	grid.resolve_all()
	grid.commit_all(coordinator._member_lookup, 1)
	coordinator._register_started_batches()
	army.prepare_combat(0.19)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(army.capture_combat_state()))
	if not _require(saved.get("combat_batches", []).size() == 1 and saved.combat_batches[0].size() == 3, "The save must retain the entire in-flight dependency component"): return
	var groups: Dictionary = {}
	if not _require(Store._valid_combat_movement_snapshot(data, saved, groups) and groups.size() == 3, "SiteStore must validate the legal in-flight chain"): return
	var broken_chain: Dictionary = saved.duplicate(true)
	broken_chain["combat_batches"] = [[mids[0], mids[2]]]
	if not _require(not Store._valid_combat_movement_snapshot(data, broken_chain, {}), "SiteStore must reject a disconnected in-flight batch"): return
	var broken_facing: Dictionary = saved.duplicate(true)
	broken_facing["combat_deployment_plan"]["final_facing"] = [1, 1]
	if not _require(not Store._valid_combat_movement_snapshot(data, broken_facing, {}), "SiteStore must reject a diagonal final facing"): return
	var unknown_queue: Dictionary = saved.duplicate(true)
	unknown_queue["combat_deployment_plan"]["queue_member_ids"].append(999999)
	if not _require(not Store._valid_combat_movement_snapshot(data, unknown_queue, {}), "SiteStore must reject an unknown queue member"): return
	var duplicate_pending: Dictionary = saved.duplicate(true)
	duplicate_pending["combat_deployment_plan"]["pending_platform_member_ids"].append(mids[0])
	if not _require(not Store._valid_combat_movement_snapshot(data, duplicate_pending, {}), "SiteStore must reject a duplicate platform member"): return
	var wrong_role: Dictionary = saved.duplicate(true)
	wrong_role["combat_deployment_plan"]["settled_queue_member_ids"].append(mids[0])
	if not _require(not Store._valid_combat_movement_snapshot(data, wrong_role, {}), "SiteStore must reject a platform member in the settled queue"): return
	var bad_release: Dictionary = saved.duplicate(true)
	bad_release["combat_deployment_plan"]["queue_released"] = "true"
	if not _require(not Store._valid_combat_movement_snapshot(data, bad_release, {}), "SiteStore must reject a malformed queue gate"): return
	var bad_absence: Dictionary = saved.duplicate(true)
	bad_absence["combat_absent_slots"] = {str(mids[0]): [15, 5]}
	if not _require(not Store._valid_combat_movement_snapshot(data, bad_absence, {}), "A temporarily absent member cannot also own an active final slot"): return
	var legacy: Dictionary = saved.duplicate(true)
	legacy["combat_deployment_plan"].erase("shape_version")
	legacy["combat_deployment_plan"].erase("formation_preset_id")
	legacy["combat_deployment_plan"].erase("final_facing")
	legacy["combat_deployment_plan"]["resolved_anchor"] = [-1, -1]
	if not _require(Store._valid_combat_movement_snapshot(data, legacy, {}), "Legacy movement anchor must be accepted for normalization"): return
	var legacy_restored := ArmyScript.new()
	legacy_restored.roster_size = 3
	legacy_restored.exchange_enabled = true
	legacy_restored.restore_combat_state(legacy, data, null, null)
	if not _require(legacy_restored.get_active_deployment_plan().resolved_anchor == Vector2i(15, 5) and legacy_restored.get_active_deployment_plan().final_facing == Vector2i.RIGHT, "Legacy movement contract must restore the anchor and path-facing"): return
	legacy_restored.free()
	var other := Helper.create_test_army(data, 2, 0, 3, Vector2i(5, 10))
	var other_order: Dictionary = other.issue_combat_order(other.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(15, 5), -1, Vector2i.RIGHT)
	if not _require(bool(other_order.get("ok", false)), "The independent second deployment must be accepted before cross-team save validation"): return
	var other_saved: Dictionary = JSON.parse_string(JSON.stringify(other.capture_combat_state()))
	var base_state: Dictionary = {"actors": {}, "armies": [saved]}
	var first_valid: Dictionary = Store._validate_armies(data, base_state)
	if not _require(bool(first_valid.get("ok", false)), "A single valid deployment must pass whole-Site validation: " + str(first_valid)): return
	base_state.armies = [other_saved]
	var second_valid: Dictionary = Store._validate_armies(data, base_state)
	if not _require(bool(second_valid.get("ok", false)), "The independent second deployment must pass whole-Site validation: " + str(second_valid)): return
	base_state.armies = [saved, other_saved]
	if not _require(not bool(Store._validate_armies(data, base_state).get("ok", false)), "Cross-team final-slot overlap must be rejected before restore"): return
	other.free()
	var restored := ArmyScript.new()
	restored.roster_size = 3
	restored.exchange_enabled = true
	var restored_coordinator := Coordinator.new()
	restored_coordinator.register_formation(restored)
	restored.restore_combat_state(saved, data, null, null)
	if not _require(restored_coordinator.get_inflight_batches_for_formation(restored).size() == 1, "Restoration must rebuild the shared completion barrier"): return
	for i in range(3):
		if not _require(restored.cells[i] == initial[i] and restored.moving_to[i] == initial[i] + Vector2i.RIGHT, "Restoration must preserve the original physical step"): return
		if not _require(restored.move_progress[i] > 0.0 and restored.move_progress[i] < 1.0, "Restoration must preserve interpolation progress"): return
	restored.prepare_combat(0.20)
	restored_coordinator.complete_committed_moves()
	for i in range(3):
		if not _require(restored.cells[i] == initial[i] + Vector2i.RIGHT and restored.moving_to[i] == TerrainArmy.INVALID_CELL, "The restored chain must finish atomically"): return
	print("COMBAT MOVEMENT SAVE MID CHAIN PASS")
	coordinator.unregister_formation(army)
	restored_coordinator.unregister_formation(restored)
	army.free()
	restored.free()
	quit(0)
