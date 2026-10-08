extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE := "res://.godot-temp/site_combat/anytime-formation-intent.json"
const STEP := 0.05

var _army: TerrainArmy
var _enemy: TerrainArmy
var _coordinator: RefCounted
var _data: TerrainData
var _failures: Array[String] = []
var _target_available := true
var _block_all := false

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> bool:
	if not ok:
		_failures.append(label)
		print("ANYTIME FAILURE: ", label)
	return ok

func _dispose() -> void:
	paused = false
	if is_instance_valid(_army):
		_coordinator.unregister_formation(_army)
		_army.free()
	if is_instance_valid(_enemy):
		_coordinator.unregister_formation(_enemy)
		_enemy.free()
	_army = null
	_enemy = null

func _fixture(data: TerrainData = null, origin: Vector2i = Vector2i(8, 12)) -> bool:
	_dispose()
	_data = data if data != null else Helper.build_flat_map(48, 32)
	_coordinator = Coordinator.new()
	_army = Helper.create_test_army(_data, 1, 0, 9, origin)
	if not _check(is_instance_valid(_army), "Fixture: original Army could not be created"): return false
	root.add_child(_army)
	_army.set_process(false)
	_coordinator.register_formation(_army)
	_target_available = true
	_block_all = false
	return true

func _target(_owner: TerrainArmy, identity: int) -> Dictionary:
	if not _target_available or not is_instance_valid(_enemy) or identity != _enemy.combat_identity(0) or not _enemy.combat_can_act(0):
		return {}
	return {"id": identity, "cell": _enemy.cells[0], "owner": _enemy, "unit": 0}

func _blocked(_cell: Vector2i) -> bool:
	return _block_all

func _advance() -> void:
	_coordinator.combat_logic_tick(STEP)
	_army.prepare_combat(STEP)
	_coordinator.complete_committed_moves()

func _physical() -> Dictionary:
	return {"cells": _army.cells.duplicate(), "moving_to": _army.moving_to.duplicate(),
		"progress": _army.move_progress.duplicate(), "duration": _army.move_duration.duplicate(),
		"claims": _army._reserved_cells.duplicate(), "batches": _coordinator.get_inflight_batches_for_formation(_army).duplicate(true)}

func _tactical() -> Dictionary:
	var targets: Array = []
	for unit: Dictionary in _army.combat_units: targets.append(unit.get("target", -1))
	return {"order": _army.combat_order, "goal": _army.combat_goal, "attacking": _army.combat_attacking,
		"pursuit_target": _army.pursuit_target, "pursuit_left": _army.pursuit_left, "origin": _army.pursuit_origin,
		"order_delay": _army._order_delay, "command_elapsed": _army._command_elapsed,
		"targets": targets, "retreat": _army._retreat_resolution.duplicate(true)}

func _change(preset: String, label: String, preserve_tactical: bool = true) -> bool:
	var physical_before := _physical()
	var tactical_before := _tactical()
	var result: Dictionary = _army.issue_formation_change(_army.current_commander, preset)
	var ok := _check(bool(result.get("ok", false)) and _army.formation_preset_id == preset and _army.formation_intent_version == 1, label + ": latest requested preset was not accepted: " + str(result))
	ok = _check(_physical() == physical_before, label + ": changed original cells, committed edge, progress, duration, claim, or Grid batch") and ok
	if preserve_tactical:
		var after := _tactical()
		for key: String in tactical_before:
			ok = _check(after[key] == tactical_before[key], "%s: tactical %s changed from %s to %s" % [label, key, tactical_before[key], after[key]]) and ok
	return ok

func _committed_step() -> bool:
	if not _check(_army._reserve_combat_step(0, _army.cells[0] + Vector2i.UP), "Fixture: failed to commit a real common-order edge"): return false
	_army.prepare_combat(STEP)
	return _check(_army.moving_to[0] != TerrainArmy.INVALID_CELL and _army.move_progress[0] > 0.0 and _army.move_progress[0] < 1.0, "Fixture: committed edge did not physically begin")

func _hold() -> void:
	if not _fixture(): return
	if not _committed_step(): return
	_change("square", "HOLD", false) # Existing physical reformation may temporarily use MOVE.
	for tick in range(1200):
		_advance()
		if _army.combat_order == TerrainArmy.CombatOrder.HOLD: break
	var plan: CombatDeploymentPlan = _army.get_active_deployment_plan()
	_check(_army.combat_order == TerrainArmy.CombatOrder.HOLD and plan != null and plan.formation_preset_id == "square" and Destination.is_settled(plan, _army.get_active_members_occupancy()), "HOLD: accepted reformation failed to return to exact settled HOLD")

func _move() -> void:
	if not _fixture(): return
	if not _check(bool(_army.issue_combat_order(_army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(35, 16), -1, Vector2i.RIGHT, "square").ok), "MOVE fixture rejected"): return
	var inflight := false
	for tick in range(400):
		_advance()
		for index in range(_army.cells.size()):
			if _army.moving_to[index] != TerrainArmy.INVALID_CELL and _army.move_progress[index] > 0.0 and _army.move_progress[index] < 1.0:
				inflight = true
				break
		if inflight: break
	if not _check(inflight, "MOVE fixture did not create a real in-flight Grid edge"): return
	_change("wedge", "MOVE square-to-wedge")
	_change("circle", "MOVE wedge-to-circle")
	_check(_army.get_active_deployment_plan() != null and _army.get_active_deployment_plan().formation_preset_id == "circle", "MOVE: A-to-B-to-C retained an older physical preset")

func _tactical_order(order: int, label: String) -> void:
	if not _fixture(): return
	if order == TerrainArmy.CombatOrder.ATTACK:
		if not _check(bool(_army.issue_combat_order(_army.current_commander, order).ok), label + " fixture rejected"): return
	else:
		_enemy = Helper.create_test_army(_data, 2, 1, 1, Vector2i(26, 12))
		_coordinator.register_formation(_enemy)
		_army.target_query = _target
		if not _check(bool(_army.issue_combat_order(_army.current_commander, TerrainArmy.CombatOrder.PURSUE, TerrainArmy.INVALID_CELL, _enemy.combat_identity(0)).ok), label + " pursuit fixture rejected"): return
	if not _committed_step(): return
	if order == TerrainArmy.CombatOrder.RETURN:
		_target_available = false
		_army._update_combat_orders(0.01)
		if not _check(_army.combat_order == TerrainArmy.CombatOrder.RETURN, "RETURN fixture failed to use the real pursuit-end transition"): return
	_change("square", label + " to-square")
	_change("circle", label + " to-circle")

func _retreat() -> void:
	if not _fixture(): return
	if not _committed_step(): return
	_army.sustain_routed_query = func(_team: TerrainArmy) -> bool: return true
	if not _check(bool(_army.begin_morale_retreat().ok), "RETREAT fixture failed real morale-collapse entry"): return
	_change("square", "morale RETREAT to-square")
	_change("circle", "morale RETREAT to-circle")
	_check(_army._formation_change_pending and _army.combat_order == TerrainArmy.CombatOrder.RETREAT and _army.is_sustain_routed(), "RETREAT: intent canceled the original rout or was lost instead of pending")

func _blocked_latest() -> void:
	if not _fixture(): return
	if not _check(bool(_army.issue_combat_order(_army.current_commander, TerrainArmy.CombatOrder.ATTACK).ok), "Pending ATTACK fixture rejected"): return
	if not _committed_step(): return
	_army.external_blocker = _blocked
	_block_all = true
	for preset: String in ["square", "wedge", "circle"]:
		_change(preset, "no-room ATTACK " + preset)
		_check(_army._formation_change_pending, "No-room request was not retained as pending: " + preset)
	_block_all = false
	for tick in range(60):
		_advance()
		if not _army._formation_change_pending: break
	var plan: CombatDeploymentPlan = _army.get_active_deployment_plan()
	_check(not _army._formation_change_pending and _army.formation_preset_id == "circle" and plan != null and plan.formation_preset_id == "circle" and _army.combat_order == TerrainArmy.CombatOrder.ATTACK, "No-room A-to-B-to-C did not automatically apply only latest C after space reopened")

func _site_pause() -> void:
	if not _fixture(): return
	if not _check(bool(_army.issue_combat_order(_army.current_commander, TerrainArmy.CombatOrder.ATTACK).ok), "Site-pause ATTACK fixture rejected"): return
	if not _committed_step(): return
	_data.site.paused = true
	var plan: CombatDeploymentPlan = _army.get_active_deployment_plan()
	var slots := _army.combat_slots.duplicate()
	var preview: Dictionary = _army.preview_formation_change("wedge")
	_check(bool(preview.get("ok", false)) and bool(preview.get("pending", false)), "Site pause: preview did not expose accepted pending intent")
	_change("wedge", "Site paused ATTACK")
	_check(_army._formation_change_pending and _army.get_active_deployment_plan() == plan and _army.combat_slots == slots, "Site pause: accepted intent immediately rewrote the physical plan/slots")
	_data.site.paused = false

func _room(data: TerrainData) -> Vector2i:
	for y in range(2, data.size.y - 8):
		for x in range(2, data.size.x - 28):
			var legal := true
			for dy in range(7):
				for dx in range(27):
					if not data.is_walkable(Vector2i(x + dx, y + dy)):
						legal = false
						break
				if not legal: break
			if legal: return Vector2i(x, y)
	return TerrainArmy.INVALID_CELL

func _paused_store() -> void:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581, {"size": Vector2i(80, 65)})
	SiteEnvironment.initialize(data, "anytime-intent-fixture")
	for index in range(data.height_levels.size()):
		data.height_levels[index] = 0
		data.site.terrain_changes[str(index)] = 0
	SiteRuntime.rebuild_terrain_edges(data)
	var room := _room(data)
	if not _check(room != TerrainArmy.INVALID_CELL, "Store fixture has no persistent legal room"): return
	if not _fixture(data, room + Vector2i(1, 3)): return
	if not _check(bool(_army.issue_combat_order(_army.current_commander, TerrainArmy.CombatOrder.MOVE, room + Vector2i(21, 3), -1, Vector2i.RIGHT, "auto").ok), "Paused MOVE fixture rejected"): return
	for tick in range(25): _advance()
	var old_plan: CombatDeploymentPlan = _army.get_active_deployment_plan()
	var old_serial := _army.get_order_serial()
	var tactical_before := _tactical()
	var physical_before := _physical()
	paused = true
	var preview: Dictionary = _army.preview_formation_change("circle")
	_check(bool(preview.get("ok", false)) and bool(preview.get("pending", false)), "Tree pause: preview did not expose accepted pending intent")
	for preset: String in ["square", "wedge", "circle"]:
		_change(preset, "Tree paused MOVE " + preset)
	_check(_army._formation_change_pending and _army.get_active_deployment_plan() == old_plan and _army.get_order_serial() == old_serial, "Tree pause rebuilt the physical deployment instead of saving latest intent")
	_army.prepare_combat(2.0)
	_check(_tactical() == tactical_before and _physical() == physical_before, "Paused intent advanced an original clock or committed movement")
	var snapshot := _army.capture_combat_state()
	_check(int(snapshot.get("formation_intent_version", 0)) == 1 and snapshot.get("formation_change_pending", false) and snapshot.formation_preset_id == "circle" and snapshot.combat_deployment_plan.formation_preset_id == "auto", "Snapshot lost requested C / applied auto / explicit pending marker")
	data.site.armies = [snapshot]
	var saved := Store.save(data, SAVE)
	if not _check(bool(saved.get("ok", false)), "Pending intent Store.save failed: " + str(saved)): return
	var loaded := Store.load_site(SAVE)
	if not _check(bool(loaded.get("ok", false)), "Pending intent Store.load failed: " + str(loaded)): return
	var restored := TerrainArmy.new()
	root.add_child(restored)
	restored.set_process(false)
	restored.roster_size = 9
	restored.exchange_enabled = true
	var restored_coordinator := Coordinator.new()
	restored_coordinator.register_formation(restored)
	restored.restore_combat_state(loaded.data.site.armies[0], loaded.data, null, null)
	_check(restored.formation_intent_version == 1 and restored._formation_change_pending and restored.formation_preset_id == "circle" and restored.get_active_deployment_plan() != null and restored.get_active_deployment_plan().formation_preset_id == "auto" and restored.combat_order == TerrainArmy.CombatOrder.MOVE and restored.combat_goal == _army.combat_goal and restored.cells == _army.cells and restored.moving_to == _army.moving_to, "Pending intent restore changed requested/applied distinction, original order, goal, or physical step")
	var corrupt: Dictionary = snapshot.duplicate(true)
	corrupt.erase("formation_intent_version")
	_check(not TerrainArmy.valid_combat_state(corrupt, data), "Pending intent without its version marker was accepted")
	corrupt = snapshot.duplicate(true)
	corrupt.formation_intent_version = 2
	_check(not TerrainArmy.valid_combat_state(corrupt, data), "Unknown intent marker version was accepted")
	paused = false
	for tick in range(60):
		restored_coordinator.combat_logic_tick(STEP)
		restored.prepare_combat(STEP)
		restored_coordinator.complete_committed_moves()
		if not restored._formation_change_pending: break
	_check(not restored._formation_change_pending and restored.formation_preset_id == "circle" and restored.get_active_deployment_plan() != null and restored.get_active_deployment_plan().formation_preset_id == "circle" and restored.combat_goal == _army.combat_goal, "Restored pending latest intent did not automatically apply after unpause")
	restored_coordinator.unregister_formation(restored)
	restored.free()

func _run() -> void:
	_hold()
	_move()
	_tactical_order(TerrainArmy.CombatOrder.ATTACK, "ATTACK")
	_tactical_order(TerrainArmy.CombatOrder.PURSUE, "PURSUE")
	_tactical_order(TerrainArmy.CombatOrder.RETURN, "RETURN")
	_retreat()
	_blocked_latest()
	_site_pause()
	_paused_store()
	_dispose()
	if _failures.is_empty():
		print("COMBAT FORMATION ANYTIME INTENT PASS: HOLD/MOVE/ATTACK/PURSUE/RETURN/morale-RETREAT/tree+Site-pause; committed edges and tactical clocks; latest pending A-B-C; real Store marker roundtrip")
	else:
		push_error("COMBAT FORMATION ANYTIME INTENT FAIL: " + str(_failures.size()) + " invariant failures; see ANYTIME FAILURE details")
	quit(0 if _failures.is_empty() else 1)
