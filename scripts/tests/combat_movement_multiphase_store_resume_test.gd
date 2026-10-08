extends SceneTree
## Real SiteStore save/load at observed MOVE phases; never relabels a snapshot.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const BASE := "res://.godot-temp/site_combat/movement-multiphase-"
const STEP := 0.05
const MEMBERS := 4

var _data: TerrainData
var _source: TerrainArmy
var _source_coordinator := Coordinator.new()

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false

func _advance(army: TerrainArmy, coordinator: SiteCombatMovementCoordinator) -> void:
	coordinator.combat_logic_tick(STEP)
	army.prepare_combat(STEP)
	coordinator.complete_committed_moves()

func _legal_step(army: TerrainArmy, terrain: TerrainData, previous: Array[Vector2i]) -> bool:
	var seen: Dictionary = {}
	for i in range(MEMBERS):
		var cell: Vector2i = army.cells[i]
		if not _require(terrain.is_walkable(cell) and not seen.has(cell), "Save/resume must preserve one legal source per person"): return false
		if cell != previous[i] and not _require(terrain.can_step(previous[i], cell), "Save/resume must commit one legal edge"): return false
		seen[cell] = true
	return true

func _room(data: TerrainData) -> Vector2i:
	for y in range(2, data.size.y - 8):
		for x in range(2, data.size.x - 35):
			var valid := true
			for dy in range(7):
				for dx in range(35):
					if not data.is_walkable(Vector2i(x + dx, y + dy)):
						valid = false
						break
				if not valid: break
			if valid: return Vector2i(x, y)
	return TerrainArmy.INVALID_CELL

func _resume(snapshot: Dictionary, label: String, expected_phase: int, expect_hold: bool = false) -> bool:
	_data.site.armies = [snapshot]
	var path := BASE + label + ".json"
	var saved: Dictionary = Store.save(_data, path)
	if not _require(bool(saved.get("ok", false)), "Real SiteStore.save rejected %s: %s" % [label, saved]): return false
	var original_text := FileAccess.get_file_as_string(path)
	var loaded: Dictionary = Store.load_site(path)
	if not _require(bool(loaded.get("ok", false)), "Real SiteStore.load_site rejected %s: %s" % [label, loaded]): return false
	var live_data: TerrainData = loaded.data
	var army := TerrainArmy.new()
	army.roster_size = MEMBERS
	army.exchange_enabled = true
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	army.restore_combat_state(live_data.site.armies[0], live_data, null, null)
	if not _require(army.cells == _snapshot_cells(snapshot) and army.moving_to == _snapshot_destinations(snapshot), "Restored %s physical cells or in-flight destinations changed" % label): return false
	var plan: CombatDeploymentPlan = army.get_active_deployment_plan()
	if not _require(plan != null, "Restored %s lost its final deployment contract" % label): return false
	if not _require(plan.shape_version == 2 and army.formation_preset_id == snapshot.formation_preset_id and plan.formation_preset_id == army.formation_preset_id, "Restored %s lost its selected formation" % label): return false
	if expect_hold:
		if not _require(army.combat_order == TerrainArmy.CombatOrder.HOLD and army.get_active_move_plan() == null, "Deployed HOLD must remain completed after load"): return false
		if not _require(Destination.is_settled(plan, army.get_active_members_occupancy()), "Deployed HOLD must retain exact final slots"): return false
	else:
		if not _require(army.combat_order == TerrainArmy.CombatOrder.MOVE and army.get_active_move_plan() != null and army.get_active_move_plan().phase == expected_phase, "Restored %s must retain its observed MOVE phase" % label): return false
		var completed := false
		for tick in range(1400):
			var before: Array[Vector2i] = army.cells.duplicate()
			_advance(army, coordinator)
			if not _legal_step(army, live_data, before): return false
			if army.combat_order == TerrainArmy.CombatOrder.HOLD:
				completed = army.command_status.begins_with("已抵達")
				break
		if not _require(completed and Destination.is_settled(plan, army.get_active_members_occupancy()), "Restored %s must finish exact final deployment; status=%s" % [label, army.command_status]): return false
	for slot: Vector2i in plan.member_slot_map.values():
		if not _require(coordinator.deployment_registry.is_slot_reserved(slot), "Final %s slot lease must survive load and completion" % label): return false
	if label == "transit":
		var envelope: Dictionary = JSON.parse_string(original_text)
		var corrupt := BASE + "corrupt.json"
		var active_site: Dictionary = live_data.site.duplicate(true)
		var active_army: Dictionary = army.capture_combat_state()
		for case in range(9):
			var payload: Dictionary = JSON.parse_string(envelope.payload)
			var team: Dictionary = payload.state.armies[0]
			var saved_plan: Dictionary = team.combat_deployment_plan
			match case:
				0:
					var first_mid: String = str(saved_plan.member_role_map.keys()[0])
					saved_plan.member_role_map[first_mid] = 1
				1: team.formation_preset_id = "unknown"
				2: saved_plan.formation_preset_id = "square"
				3: saved_plan.shape_version = 4
				4: saved_plan.final_width = 999
				5: saved_plan.erase("formation_preset_id")
				6: saved_plan.formation_preset_id = 42
				7: saved_plan.requested_count = 0
				8: team.combat_order_serial = int(saved_plan.order_serial) + 1
			var body := JSON.stringify(payload, "", true, true)
			var file := FileAccess.open(corrupt, FileAccess.WRITE)
			if not _require(file != null, "Cannot write checksummed corrupt fixture"): return false
			file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}, "\t"))
			file.close()
			var rejected: Dictionary = Store.load_site(corrupt)
			if not _require(not bool(rejected.get("ok", false)) and str(rejected.get("code", "")) == "CORRUPT_SAVE" and not rejected.has("data"), "Malformed deployment case %d must fail real load" % case): return false
			if not _require(live_data.site == active_site and army.capture_combat_state() == active_army and FileAccess.get_file_as_string(path) == original_text, "Failed load must not replace the live Site, army, or valid save"): return false
		var legacy_payload: Dictionary = JSON.parse_string(envelope.payload)
		legacy_payload.state.armies[0].combat_deployment_plan.erase("shape_version")
		legacy_payload.state.armies[0].combat_deployment_plan.erase("formation_preset_id")
		legacy_payload.state.armies[0].combat_deployment_plan.erase("final_facing")
		legacy_payload.state.armies[0].combat_deployment_plan.resolved_anchor = [-1, -1]
		var legacy_body := JSON.stringify(legacy_payload, "", true, true)
		var legacy_path := BASE + "legacy.json"
		var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
		if not _require(legacy_file != null, "Cannot write legacy movement fixture"): return false
		legacy_file.store_string(JSON.stringify({"checksum": legacy_body.sha256_text(), "payload": legacy_body}, "\t"))
		legacy_file.close()
		var legacy_loaded: Dictionary = Store.load_site(legacy_path)
		if not _require(bool(legacy_loaded.get("ok", false)), "Legacy movement fields must migrate through real load: " + str(legacy_loaded)): return false
		var legacy_data: TerrainData = legacy_loaded.data
		var legacy_army := TerrainArmy.new()
		legacy_army.roster_size = MEMBERS
		legacy_army.exchange_enabled = true
		var legacy_coordinator := Coordinator.new()
		legacy_coordinator.register_formation(legacy_army)
		legacy_army.restore_combat_state(legacy_data.site.armies[0], legacy_data, null, null)
		if not _require(legacy_army.get_active_deployment_plan().resolved_anchor == army.get_active_deployment_plan().resolved_anchor and legacy_army.get_active_deployment_plan().final_facing == Vector2i.RIGHT, "Legacy anchor and final facing must be rebuilt"): return false
		var legacy_finished := false
		for tick in range(1400):
			var previous: Array[Vector2i] = legacy_army.cells.duplicate()
			_advance(legacy_army, legacy_coordinator)
			if not _legal_step(legacy_army, legacy_data, previous): return false
			if legacy_army.combat_order == TerrainArmy.CombatOrder.HOLD:
				legacy_finished = legacy_army.command_status.begins_with("已抵達")
				break
		if not _require(legacy_finished and Destination.is_settled(legacy_army.get_active_deployment_plan(), legacy_army.get_active_members_occupancy()), "Legacy movement must continue to exact final HOLD"): return false
		legacy_coordinator.unregister_formation(legacy_army)
		legacy_army.free()
	if label == "square-deployed":
		var square_envelope: Dictionary = JSON.parse_string(original_text)
		var square_payload: Dictionary = JSON.parse_string(square_envelope.payload)
		var square_plan: Dictionary = square_payload.state.armies[0].combat_deployment_plan
		var old_slot: Array = square_plan.platform_slots[0]
		var false_slot := [int(old_slot[0]) + 3, int(old_slot[1])]
		if not _require(live_data.is_walkable(Vector2i(false_slot[0], false_slot[1])) and not square_plan.platform_slots.has(false_slot) and not square_plan.approach_queue_slots.has(false_slot), "Square corruption fixture needs an otherwise legal spare cell"): return false
		square_plan.platform_slots[0] = false_slot
		for mid: String in square_plan.member_slot_map.keys():
			if square_plan.member_slot_map[mid] == old_slot:
				square_plan.member_slot_map[mid] = false_slot
		var square_body := JSON.stringify(square_payload, "", true, true)
		var square_corrupt := BASE + "square-corrupt.json"
		var square_file := FileAccess.open(square_corrupt, FileAccess.WRITE)
		if not _require(square_file != null, "Cannot write checksummed square corruption fixture"): return false
		square_file.store_string(JSON.stringify({"checksum": square_body.sha256_text(), "payload": square_body}, "\t"))
		square_file.close()
		var square_rejected: Dictionary = Store.load_site(square_corrupt)
		if not _require(not bool(square_rejected.get("ok", false)) and str(square_rejected.get("code", "")) == "CORRUPT_SAVE" and not square_rejected.has("data"), "Wrong square geometry must fail real load"): return false
		if not _require(FileAccess.get_file_as_string(path) == original_text, "Wrong square geometry must preserve the valid save"): return false
	coordinator.unregister_formation(army)
	army.free()
	return true

func _snapshot_cells(snapshot: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for unit: Dictionary in snapshot.units:
		cells.append(Vector2i(int(unit.cell[0]), int(unit.cell[1])))
	return cells

func _snapshot_destinations(snapshot: Dictionary) -> Array[Vector2i]:
	var destinations: Array[Vector2i] = []
	for unit: Dictionary in snapshot.units:
		destinations.append(Vector2i(int(unit.destination[0]), int(unit.destination[1])))
	return destinations

func _run() -> void:
	_data = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	SiteEnvironment.initialize(_data, "movement-multiphase-fixture")
	for index in range(_data.height_levels.size()):
		_data.height_levels[index] = 0
		_data.site.terrain_changes[str(index)] = 0
	SiteRuntime.rebuild_terrain_edges(_data)
	var room := _room(_data)
	if not _require(room != TerrainArmy.INVALID_CELL, "No persistent 35 x 7 phase fixture room"): return
	_source = Helper.create_test_army(_data, 1, 0, MEMBERS, room + Vector2i(1, 3))
	_source_coordinator.register_formation(_source)
	if not _require(bool(_source.issue_combat_order(_source.current_commander, TerrainArmy.CombatOrder.MOVE, room + Vector2i(29, 3), -1, Vector2i.RIGHT).get("ok", false)), "Formal phase fixture MOVE must start"): return
	var phase_snapshots: Dictionary = {}
	var desired: Array[int] = [Types.CombatMovePhase.TRANSIT, Types.CombatMovePhase.INGRESS_STAGING, Types.CombatMovePhase.PLATFORM_INGRESS, Types.CombatMovePhase.QUEUE_SETTLING]
	var hold_snapshot: Dictionary = {}
	for tick in range(1400):
		var before: Array[Vector2i] = _source.cells.duplicate()
		_advance(_source, _source_coordinator)
		if not _legal_step(_source, _data, before): return
		var active = _source.get_active_move_plan()
		if active != null and not phase_snapshots.has(active.phase) and (tick > 0 or active.phase != Types.CombatMovePhase.TRANSIT):
			phase_snapshots[active.phase] = JSON.parse_string(JSON.stringify(_source.capture_combat_state()))
		if _source.combat_order == TerrainArmy.CombatOrder.HOLD:
			hold_snapshot = JSON.parse_string(JSON.stringify(_source.capture_combat_state()))
			break
	if not _require(not hold_snapshot.is_empty() and _source.command_status.begins_with("已抵達"), "Source must actually finish before phase checkpoints are assessed"): return
	if not _require(phase_snapshots.has(Types.CombatMovePhase.TRANSIT) and phase_snapshots.size() >= 2, "Must observe at least two genuine MOVE phases including TRANSIT; observed=" + str(phase_snapshots.keys())): return
	_data.site["army_trial_active"] = true
	_data.site["army_next_team"] = 2
	_data.site["actors"] = {}
	_data.site.combat_left = 0.0
	for phase in desired:
		if phase_snapshots.has(phase):
			var label: String = str(["transit", "staging", "platform", "queue"][phase])
			if not _resume(phase_snapshots[phase], label, phase): return
	if not _resume(hold_snapshot, "deployed", Types.CombatMovePhase.COMPLETE, true): return
	if not _require(bool(_source.issue_formation_change(_source.current_commander, "square").get("ok", false)), "Square switch must be accepted from completed HOLD"): return
	var square_hold: Dictionary = {}
	for tick in range(1400):
		var before: Array[Vector2i] = _source.cells.duplicate()
		_advance(_source, _source_coordinator)
		if not _legal_step(_source, _data, before): return
		if _source.combat_order == TerrainArmy.CombatOrder.HOLD:
			square_hold = JSON.parse_string(JSON.stringify(_source.capture_combat_state()))
			break
	if not _require(not square_hold.is_empty() and square_hold.formation_preset_id == "square", "Square switch must finish before save/resume"): return
	if not _resume(square_hold, "square-deployed", Types.CombatMovePhase.COMPLETE, true): return
	print("COMBAT MOVEMENT MULTIPHASE STORE RESUME PASS observed_phases=", phase_snapshots.keys(), " deployed=true square_hold=true corrupt_load_preserved=true")
	_source_coordinator.unregister_formation(_source)
	_source.free()
	quit(0)
