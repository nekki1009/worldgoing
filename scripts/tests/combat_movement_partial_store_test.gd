extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const BASE := "res://.godot-temp/site_combat/partial-store-"

var _source: TerrainArmy
var _restored: TerrainArmy
var _coordinator := Coordinator.new()
var _restored_coordinator := Coordinator.new()

func _initialize() -> void:
	call_deferred("_run")

func _finish(ok: bool, message: String) -> void:
	if is_instance_valid(_restored):
		_restored_coordinator.unregister_formation(_restored)
		_restored.free()
	if is_instance_valid(_source):
		_coordinator.unregister_formation(_source)
		_source.free()
	if ok:
		print(message)
	else:
		push_error(message)
	quit(0 if ok else 1)

func _require(ok: bool, message: String) -> bool:
	if not ok:
		_finish(false, message)
	return ok

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

func _write_payload(path: String, payload: Dictionary) -> void:
	var body := JSON.stringify(payload, "", true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}, "\t"))
	file.close()

func _run() -> void:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581, {"size": Vector2i(80, 65)})
	SiteEnvironment.initialize(data, "partial-store-fixture")
	for index in range(data.height_levels.size()):
		data.height_levels[index] = 0
		data.site.terrain_changes[str(index)] = 0
	SiteRuntime.rebuild_terrain_edges(data)
	var room := _room(data)
	if not _require(room != TerrainArmy.INVALID_CELL, "No persistent legal room for partial store fixture"): return
	_source = Helper.create_test_army(data, 1, 0, 9, room + Vector2i(1, 3))
	_coordinator.register_formation(_source)
	var goal := room + Vector2i(21, 3)
	var blocked_slot: Vector2i = Destination.shape_slots("square", 9, goal, Vector2i.RIGHT)[0]
	_source.external_blocker = func(cell: Vector2i) -> bool: return cell == blocked_slot
	var order := _source.issue_combat_order(_source.current_commander, TerrainArmy.CombatOrder.MOVE, goal, -1, Vector2i.RIGHT, "square")
	if not _require(bool(order.get("ok", false)), "Partial square order failed: " + str(order)): return
	var plan: CombatDeploymentPlan = _source.get_active_deployment_plan()
	if not _require(plan != null and plan.following_member_ids.size() == 1 and plan.platform_slots.size() == 8, "Actual order did not create the intended 8+1 contract"): return
	var snapshot := _source.capture_combat_state()
	var follower: int = plan.following_member_ids[0]
	if not _require(snapshot.combat_deployment_plan.get("following_member_ids", []) == [follower], "Actual serializer lost the explicit follower"): return
	if not _require(Store._valid_combat_movement_snapshot(data, snapshot, {}), "Actual partial movement snapshot failed validation"): return
	data.site.armies = [snapshot]
	var path := BASE + "valid.json"
	var saved := Store.save(data, path)
	if not _require(bool(saved.get("ok", false)), "Real partial save failed: " + str(saved)): return
	var original := FileAccess.get_file_as_string(path)
	var loaded := Store.load_site(path)
	if not _require(bool(loaded.get("ok", false)), "Real partial load failed: " + str(loaded)): return
	_restored = TerrainArmy.new()
	# Production armies live in the scene tree; fixtures step them explicitly.
	root.add_child(_restored)
	_restored.set_process(false)
	_restored.roster_size = 9
	_restored.exchange_enabled = true
	_restored_coordinator.register_formation(_restored)
	_restored.restore_combat_state(loaded.data.site.armies[0], loaded.data, null, null)
	var restored_plan: CombatDeploymentPlan = _restored.get_active_deployment_plan()
	if not _require(restored_plan != null and restored_plan.following_member_ids == plan.following_member_ids and restored_plan.member_slot_map == plan.member_slot_map and _restored.cells == _source.cells and _restored.moving_to == _source.moving_to and _restored.combat_order == TerrainArmy.CombatOrder.MOVE, "Actual restore changed original people, followers, slots, or physical steps"): return
	var ko_snapshot: Dictionary = snapshot.duplicate(true)
	for unit: Dictionary in ko_snapshot.units:
		if int(unit.person_id) == follower:
			unit.ko = 4.0
			unit.pose = "unconscious"
	if not _require(Store._valid_combat_movement_snapshot(data, ko_snapshot, {}), "A KO follower must retain its identity without a fake absent slot"): return
	var envelope: Dictionary = JSON.parse_string(original)
	for case in range(15):
		var payload: Dictionary = JSON.parse_string(envelope.payload)
		var team: Dictionary = payload.state.armies[0]
		var deployment: Dictionary = team.combat_deployment_plan
		match case:
			0: deployment.following_member_ids.append(follower)
			1: deployment.following_member_ids = [int(deployment.member_slot_map.keys()[0])]
			2: deployment.following_member_ids = [2147483646]
			3: deployment.following_member_ids = [-1]
			4: deployment.following_member_ids = [float(follower) + 0.5]
			5: deployment.following_member_ids = [str(follower)]
			6: deployment.erase("following_member_ids")
			7: deployment.shape_version = 2
			8: deployment.following_member_ids = []
			9: deployment.final_width += 1
			10: team.combat_order = TerrainArmy.CombatOrder.HOLD
			11: team.combat_move_plan.phase = CombatMovementTypes.CombatMovePhase.COMPLETE
			12: team.formation_intent_version = 2
			13: team["combat_absent_slots"] = {str(follower): deployment.platform_slots[0]}
			14:
				var old_slot: Array = deployment.platform_slots[0]
				var false_slot := [goal.x + 4, goal.y]
				deployment.platform_slots[0] = false_slot
				for key in deployment.member_slot_map.keys():
					if deployment.member_slot_map[key] == old_slot:
						deployment.member_slot_map[key] = false_slot
		var corrupt_path := BASE + "corrupt.json"
		_write_payload(corrupt_path, payload)
		var rejected := Store.load_site(corrupt_path)
		if not _require(not bool(rejected.get("ok", false)) and str(rejected.get("code", "")) == "CORRUPT_SAVE" and not rejected.has("data"), "Corrupt partial case %d was accepted: %s" % [case, rejected]): return
		if not _require(FileAccess.get_file_as_string(path) == original and _source.capture_combat_state() == snapshot, "Corrupt load changed the good save or live original army"): return
	var intent: Dictionary = snapshot.duplicate(true)
	intent.formation_preset_id = "circle"
	intent.formation_intent_version = 1
	if not _require(Store._valid_combat_movement_snapshot(data, intent, {}), "Versioned requested intent must not rewrite applied square geometry"): return
	intent.erase("formation_intent_version")
	if not _require(not Store._valid_combat_movement_snapshot(data, intent, {}), "Unversioned requested/applied mismatch must still be rejected"): return
	_source.external_blocker = Callable()
	if not _require(bool(_source.issue_combat_order(_source.current_commander, TerrainArmy.CombatOrder.MOVE, goal, -1, Vector2i.RIGHT, "auto").get("ok", false)), "Legacy full auto fixture failed"): return
	var legacy: Dictionary = _source.capture_combat_state()
	legacy.erase("formation_intent_version")
	if not _require(int(legacy.combat_deployment_plan.shape_version) == 2 and Store._valid_combat_movement_snapshot(data, legacy, {}), "Full v2 auto compatibility failed"): return
	legacy.combat_deployment_plan.erase("shape_version")
	legacy.combat_deployment_plan.erase("formation_preset_id")
	legacy.combat_deployment_plan.erase("final_facing")
	legacy.combat_deployment_plan.resolved_anchor = [-1, -1]
	data.site.armies = [legacy]
	if not _require(bool(Store.save(data, BASE + "legacy.json").get("ok", false)) and bool(Store.load_site(BASE + "legacy.json").get("ok", false)), "Real v1 compatibility save/load failed"): return
	_finish(true, "COMBAT MOVEMENT PARTIAL STORE PASS: real 8+1 round-trip, 15 corruptions, KO follower, requested intent, v1/v2 compatibility")
