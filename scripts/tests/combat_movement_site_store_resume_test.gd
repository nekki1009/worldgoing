extends SceneTree
## Real SiteStore I/O without adding an Army to the scene or creating a renderer.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE := "res://.godot-temp/site_combat/movement-store-resume.json"
const CORRUPT_SAVE := SAVE + ".corrupt"
const STEP := 0.05
const MEMBERS := 4
const START_LIMIT := 20.0
const ARRIVAL_LIMIT := 60.0
const STABLE_SECONDS := 5.0

var _source: TerrainArmy
var _restored: TerrainArmy
var _source_coordinator := Coordinator.new()
var _restored_coordinator := Coordinator.new()

func _initialize() -> void:
	call_deferred("_run")

func _finish(ok: bool, message: String) -> void:
	if ok:
		print(message)
	else:
		push_error(message)
	if is_instance_valid(_source):
		_source_coordinator.unregister_formation(_source)
		_source.free()
	if is_instance_valid(_restored):
		_restored_coordinator.unregister_formation(_restored)
		_restored.free()
	quit(0 if ok else 1)

func _require(condition: bool, message: String) -> bool:
	if not condition:
		_finish(false, message)
	return condition

func _advance(army: TerrainArmy, coordinator: SiteCombatMovementCoordinator) -> void:
	coordinator.combat_logic_tick(STEP)
	army.prepare_combat(STEP)
	coordinator.complete_committed_moves()

func _clear_room(data: TerrainData) -> Vector2i:
	# Select existing legal ground; only the persistent height fixture is changed.
	for y in range(2, data.size.y - 8):
		for x in range(2, data.size.x - 15):
			var legal := true
			for dy in range(7):
				for dx in range(14):
					if not data.is_walkable(Vector2i(x + dx, y + dy)):
						legal = false
						break
				if not legal: break
			if legal: return Vector2i(x, y)
	return TerrainArmy.INVALID_CELL

func _check_step(army: TerrainArmy, data: TerrainData, previous: Array[Vector2i]) -> bool:
	var sources: Dictionary = {}
	var claims: Dictionary = {}
	for i in range(MEMBERS):
		var cell: Vector2i = army.cells[i]
		if not _require(data.is_walkable(cell) and not sources.has(cell), "Resume produced an illegal or duplicate source: " + str(cell)): return false
		if cell != previous[i] and not _require(data.can_step(previous[i], cell), "Resume skipped a legal edge: %s -> %s" % [previous[i], cell]): return false
		sources[cell] = true
		var target: Vector2i = army.moving_to[i]
		if target != TerrainArmy.INVALID_CELL:
			if not _require(data.can_step(cell, target) and not claims.has(target), "Resume produced an illegal or duplicate destination claim: " + str(target)): return false
			claims[target] = true
	return true

func _run() -> void:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	SiteEnvironment.initialize(data, "movement-store-resume-fixture")
	# Same persistent flattening as site_army_command_save_test: load_site must
	# reconstruct these heights from terrain_changes, not an unsaved test override.
	for index in range(data.height_levels.size()):
		data.height_levels[index] = 0
		data.site.terrain_changes[str(index)] = 0
	SiteRuntime.rebuild_terrain_edges(data)
	var room := _clear_room(data)
	if not _require(room != TerrainArmy.INVALID_CELL, "Generated seed 581 has no legal 14 x 7 fixture room"): return
	var origin := room + Vector2i(1, 3)
	var goal := room + Vector2i(11, 3)
	_source = Helper.create_test_army(data, 1, 0, MEMBERS, origin)
	_source_coordinator.register_formation(_source)
	var order: Dictionary = _source.issue_combat_order(_source.current_commander, TerrainArmy.CombatOrder.MOVE, goal, -1, Vector2i.RIGHT)
	if not _require(bool(order.get("ok", false)), "Formal MOVE rejected: " + str(order)): return
	var started_at := -1.0
	for tick in range(roundi(START_LIMIT / STEP)):
		var previous: Array[Vector2i] = _source.cells.duplicate()
		_advance(_source, _source_coordinator)
		if not _check_step(_source, data, previous): return
		for i in range(MEMBERS):
			if _source.moving_to[i] != TerrainArmy.INVALID_CELL and _source.move_progress[i] > 0.0 and _source.move_progress[i] < 1.0:
				started_at = (tick + 1) * STEP
				break
		if started_at >= 0.0: break
	if not _require(started_at >= 0.0 and not _source_coordinator.get_inflight_batches_for_formation(_source).is_empty(), "No formal in-flight MOVE within 20 simulated seconds; status=" + _source.command_status): return
	var snapshot: Dictionary = _source.capture_combat_state()
	data.site["army_trial_active"] = true
	data.site["army_next_team"] = 2
	data.site["actors"] = {}
	data.site["armies"] = [snapshot]
	data.site.combat_left = 0.0
	var saved: Dictionary = Store.save(data, SAVE)
	if not _require(bool(saved.get("ok", false)), "SiteStore.save rejected the in-flight MOVE: " + str(saved)): return
	var saved_text := FileAccess.get_file_as_string(SAVE)
	var loaded: Dictionary = Store.load_site(SAVE)
	if not _require(bool(loaded.get("ok", false)), "SiteStore.load_site rejected the in-flight MOVE: " + str(loaded)): return
	var active_data: TerrainData = loaded.data
	if not _require(active_data != data and active_data.height_levels == data.height_levels and active_data.static_blocked == data.static_blocked, "Load must reconstruct a separate terrain with the same legal geometry"): return
	_restored = TerrainArmy.new()
	# Production armies live in the scene tree; fixtures step them explicitly.
	root.add_child(_restored)
	_restored.set_process(false)
	_restored.roster_size = MEMBERS
	_restored.exchange_enabled = true
	_restored_coordinator.register_formation(_restored)
	_restored.restore_combat_state(active_data.site.armies[0], active_data, null, null)
	if not _require(_restored.combat_order == TerrainArmy.CombatOrder.MOVE and _restored.cells == _source.cells and _restored.moving_to == _source.moving_to, "Load changed the order or physical source/destination cells"): return
	if not _require(_restored_coordinator.get_inflight_batches_for_formation(_restored).size() == _source_coordinator.get_inflight_batches_for_formation(_source).size(), "Load lost an in-flight completion barrier"): return
	for i in range(MEMBERS):
		if not _require(absf(_restored.move_progress[i] - _source.move_progress[i]) < 0.000000000000001, "Load changed interpolation progress at member " + str(i)): return
	var plan: CombatDeploymentPlan = _restored.get_active_deployment_plan()
	if not _require(plan != null and plan.member_slot_map == _source.get_active_deployment_plan().member_slot_map, "Load changed the final slot contract"): return

	# Keep a valid checksum so this reaches the movement validator, not just the
	# envelope checksum guard. Only the dedicated corrupt copy is changed.
	var envelope: Dictionary = JSON.parse_string(saved_text)
	var payload: Dictionary = JSON.parse_string(envelope.payload)
	payload.state.armies[0].combat_deployment_plan.final_facing = [1, 1]
	var corrupt_body := JSON.stringify(payload, "", true, true)
	var corrupt_text := JSON.stringify({"checksum": corrupt_body.sha256_text(), "payload": corrupt_body}, "\t")
	var corrupt_file := FileAccess.open(CORRUPT_SAVE, FileAccess.WRITE)
	if not _require(corrupt_file != null, "Cannot write the corrupt-load fixture"): return
	corrupt_file.store_string(corrupt_text)
	corrupt_file.close()
	var active_id := active_data.get_instance_id()
	var active_site: Dictionary = active_data.site.duplicate(true)
	var active_army: Dictionary = _restored.capture_combat_state()
	var rejected: Dictionary = Store.load_site(CORRUPT_SAVE)
	if not _require(not bool(rejected.get("ok", false)) and str(rejected.get("code", "")) == "CORRUPT_SAVE" and not rejected.has("data"), "Malformed movement data must fail without publishing replacement data: " + str(rejected)): return
	if not _require(active_data.get_instance_id() == active_id and active_data.site == active_site and _restored.capture_combat_state() == active_army, "Failed load changed the active terrain or moving army"): return
	if not _require(FileAccess.get_file_as_string(SAVE) == saved_text and FileAccess.get_file_as_string(CORRUPT_SAVE) == corrupt_text, "Load must preserve both the original save and the rejected file"): return

	var completed_at := -1.0
	for tick in range(roundi(ARRIVAL_LIMIT / STEP)):
		var previous: Array[Vector2i] = _restored.cells.duplicate()
		_advance(_restored, _restored_coordinator)
		if not _check_step(_restored, active_data, previous): return
		if _restored.combat_order == TerrainArmy.CombatOrder.HOLD:
			completed_at = (tick + 1) * STEP
			break
	if not _require(completed_at >= 0.0 and _restored.command_status.begins_with("已抵達"), "Restored MOVE did not finish within 60 simulated seconds; status=" + _restored.command_status): return
	if not _require(Destination.is_settled(plan, _restored.get_active_members_occupancy()), "Restored members must occupy their exact final slots"): return
	var settled: Array[Vector2i] = _restored.cells.duplicate()
	var settled_slots: Dictionary = plan.member_slot_map.duplicate()
	for tick in range(roundi(STABLE_SECONDS / STEP)):
		_advance(_restored, _restored_coordinator)
		if not _require(_restored.combat_order == TerrainArmy.CombatOrder.HOLD and _restored.cells == settled and plan.member_slot_map == settled_slots, "Final HOLD must remain stable for five simulated seconds"): return
		if not _require(_restored._reserved_cells.is_empty() and _restored_coordinator.get_inflight_batches_for_formation(_restored).is_empty(), "Completed MOVE left physical claims or batches"): return
		for i in range(MEMBERS):
			if not _require(_restored.moving_to[i] == TerrainArmy.INVALID_CELL and _restored.facing[i] == Vector2i.RIGHT, "Completed MOVE must finish its original step and final facing"): return
	_finish(true, "COMBAT MOVEMENT SITE STORE RESUME PASS: members=4 saved_at=%.2fs resumed_arrival=%.2fs stable=5s invalid_load_preserved=true save=%s" % [started_at, completed_at, SAVE])
