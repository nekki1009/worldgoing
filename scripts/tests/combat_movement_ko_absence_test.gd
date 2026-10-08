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
	var terrain := Helper.build_flat_map(30, 20)
	var army := Helper.create_test_army(terrain, 1, 0, 2, Vector2i(5, 5))
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	if not _require(bool(army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(15, 5)).get("ok", false)), "MOVE must start"): return
	var mid := army.combat_identity(1)
	var source: Vector2i = army.cells[1]
	var plan = army.get_active_deployment_plan()
	var final_slot: Vector2i = plan.get_slot_for_member(mid)
	army.apply_unit_contact(1, {"result": {"hp": 0.0, "stun": 110.0, "guard_break": false}, "shield": false})
	army.update_combat_deployment(0.05)
	if not _require(not plan.member_slot_map.has(mid) and army._combat_absent_slots.get(mid) == final_slot, "KO member must leave active deployment but retain return intent"): return
	if not _require(plan.slot_lease_timers.has(final_slot) and coordinator.deployment_registry.is_slot_reserved(final_slot), "KO final slot must keep its four-second lease"): return
	if not _require(not army._get_active_member_ids().has(mid) and not army.get_active_members_occupancy().has(mid)
		and not army.blocks_cell(source), "Stationary KO cannot march and releases physical occupancy"): return
	var saved: Dictionary = JSON.parse_string(JSON.stringify(army.capture_combat_state()))
	if not _require(Store._valid_combat_movement_snapshot(terrain, saved, {}), "SiteStore must accept a valid KO movement snapshot"): return
	var bad: Dictionary = saved.duplicate(true)
	bad["combat_absent_slots"][str(mid)] = [29, 19]
	if not _require(not Store._valid_combat_movement_snapshot(terrain, bad, {}), "SiteStore must reject an absent intent outside final-slot candidates"): return
	var restored := ArmyScript.new()
	restored.roster_size = 2
	restored.exchange_enabled = true
	var restored_coordinator := Coordinator.new()
	restored_coordinator.register_formation(restored)
	restored.restore_combat_state(saved, terrain, null, null)
	if not _require(restored._combat_absent_slots.get(mid) == final_slot and restored.get_active_deployment_plan().slot_lease_timers.has(final_slot), "KO intent and lease must survive restore"): return
	if not _require(restored_coordinator.deployment_registry.is_slot_reserved(final_slot), "Restore must re-register the absent slot against other teams"): return
	restored._wake_unit(1)
	restored.combat_units[1].pose = "idle"
	restored.update_combat_deployment(0.05)
	if not _require(restored._combat_absent_slots.is_empty() and restored.get_active_deployment_plan().get_slot_for_member(mid) == final_slot, "Awake member must reclaim the valid original slot"): return
	if not _require(restored.cells[1] == source, "Returning member must remain at its physical source until it walks"): return
	restored.apply_unit_contact(1, {"result": {"hp": 0.0, "stun": 110.0, "guard_break": false}, "shield": false})
	restored.update_combat_deployment(0.05)
	restored.update_combat_deployment(4.1)
	if not _require(not restored_coordinator.deployment_registry.is_slot_reserved(final_slot), "Expired KO lease must become available if no one owns it"): return
	var takeover: Dictionary = restored_coordinator.deployment_registry.try_replace_reservations(2, 0, 1, [final_slot])
	if not _require(bool(takeover.get("ok", false)), "Another team must be able to reserve the expired slot"): return
	restored._wake_unit(1)
	restored.combat_units[1].pose = "idle"
	restored.update_combat_deployment(0.05)
	if not _require(restored_coordinator.deployment_registry.is_slot_reserved(final_slot, 1), "Wake must not steal another team's final slot"): return
	if not _require(not restored.get_active_deployment_plan().member_slot_map.has(mid) or restored.get_active_deployment_plan().get_slot_for_member(mid) != final_slot, "Wake must take a different legal slot or wait"): return
	var before_hold: Vector2i = restored.cells[1]
	restored.issue_combat_order(restored.current_commander, TerrainArmy.CombatOrder.HOLD, before_hold)
	if not _require(restored._combat_absent_slots.is_empty() and restored.cells[1] == before_hold, "HOLD must clear return intent without moving the recovering member"): return
	print("COMBAT MOVEMENT KO ABSENCE PASS")
	restored_coordinator.deployment_registry.release_order(2)
	coordinator.unregister_formation(army)
	restored_coordinator.unregister_formation(restored)
	army.free()
	restored.free()
	quit(0)
