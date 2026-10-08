extends SceneTree
## SiteStore must preserve an accepted reciprocal RETREAT batch across save/load.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE := "res://.godot-temp/site_combat/movement-retreat-pair-store-resume.json"
const INTERRUPTED_SAVE := "res://.godot-temp/site_combat/movement-retreat-pair-interrupted-save.json"
const STEP := 0.05

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

func _advance(army: TerrainArmy, coordinator: SiteCombatMovementCoordinator, delta: float = STEP) -> void:
	coordinator.combat_logic_tick_if_needed(delta)
	army.prepare_combat(delta)
	coordinator.complete_committed_moves()

func _clear_room(data: TerrainData) -> Vector2i:
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

func _run() -> void:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	SiteEnvironment.initialize(data, "movement-retreat-pair-store-fixture")
	# The loaded Site reconstructs precisely the same flattened terrain.
	for index in range(data.height_levels.size()):
		data.height_levels[index] = 0
		data.site.terrain_changes[str(index)] = 0
	SiteRuntime.rebuild_terrain_edges(data)
	var room := _clear_room(data)
	if not _require(room != TerrainArmy.INVALID_CELL, "Generated seed 581 has no legal 14 x 7 fixture room"): return
	_source = Helper.create_test_army(data, 1, 0, 2, room + Vector2i(1, 3))
	_source_coordinator.register_formation(_source)
	var rear: Vector2i = _source.cells[0]
	var front: Vector2i = _source.cells[1]
	if not _require(front == rear + Vector2i.RIGHT, "Fixture members must be adjacent"): return
	var retreat_goal := Vector2i(_source.command_reference.floor()) + Vector2i.LEFT
	var order: Dictionary = _source.issue_combat_order(_source.current_commander, TerrainArmy.CombatOrder.RETREAT, retreat_goal)
	if not _require(bool(order.get("ok", false)), "The real RETREAT command must be accepted: " + str(order)): return
	if not _require(_source.combat_slots[0] == rear + Vector2i.LEFT and _source.combat_slots[1] == rear,
		"The command must assign original retreat slots"): return
	# Close the rear exit only after the order. This forces the real Grid to
	# accept a two-person reciprocal step while the RETREAT command remains live.
	var rear_exit := rear + Vector2i.LEFT
	data.static_blocked[data.index(rear_exit)] = 1
	var started := false
	for tick in range(30):
		_advance(_source, _source_coordinator)
		if _source.moving_to[0] == front and _source.moving_to[1] == rear:
			started = true
			break
	if not _require(started and _source_coordinator.get_inflight_batches_for_formation(_source).size() == 1,
		"RETREAT must have one Grid-accepted reciprocal batch"): return
	_source.prepare_combat(0.14)
	_source_coordinator.complete_committed_moves()
	if not _require(_source.cells[0] == rear and _source.cells[1] == front and _source.move_progress[0] > 0.0 \
		and _source.move_progress[0] < 1.0 and _source.move_progress[1] > 0.0 and _source.move_progress[1] < 1.0,
		"Save must occur while both physical edges are in flight"): return
	data.static_blocked[data.index(rear_exit)] = 0
	var snapshot: Dictionary = _source.capture_combat_state()
	var groups: Dictionary = {}
	if not _require(snapshot.get("combat_batches", []).size() == 1 and snapshot.combat_batches[0].size() == 2 \
		and snapshot.get("combat_batch_retreat_members", []).size() == 2 \
		and Store._valid_combat_movement_snapshot(data, snapshot, groups) and groups.size() == 2,
		"SiteStore must recognize both accepted reciprocal RETREAT members"): return
	var half_marked: Dictionary = snapshot.duplicate(true)
	half_marked.combat_batch_retreat_members = [snapshot.combat_batch_retreat_members[0]]
	if not _require(not Store._valid_combat_movement_snapshot(data, half_marked, {}),
		"One RETREAT marker must not authorize a pair"): return
	var ordinary_retreat: Dictionary = snapshot.duplicate(true)
	ordinary_retreat.units[1].destination = [front.x + 1, front.y]
	if not _require(Store._valid_combat_movement_snapshot(data, ordinary_retreat, {}),
		"The ordinary one-tail RETREAT batch rule must remain valid"): return
	var nonreciprocal: Dictionary = snapshot.duplicate(true)
	nonreciprocal.units[0].destination = [rear.x, rear.y - 1]
	if not _require(not Store._valid_combat_movement_snapshot(data, nonreciprocal, {}),
		"Both markers must not authorize a nonreciprocal batch"): return

	data.site["army_trial_active"] = true
	data.site["army_next_team"] = 2
	data.site["actors"] = {}
	data.site["armies"] = [snapshot]
	data.site.combat_left = 0.0
	var saved: Dictionary = Store.save(data, SAVE)
	if not _require(bool(saved.get("ok", false)), "SiteStore.save rejected the in-flight RETREAT pair: " + str(saved)): return
	var saved_text := FileAccess.get_file_as_string(SAVE)
	var unmarked: Dictionary = snapshot.duplicate(true)
	unmarked.erase("combat_batch_retreat_members")
	data.site.armies = [unmarked]
	var rejected: Dictionary = Store.save(data, SAVE)
	if not _require(not bool(rejected.get("ok", false)) and str(rejected.get("code", "")) == "CORRUPT_SAVE" \
		and FileAccess.get_file_as_string(SAVE) == saved_text,
		"SiteStore.save must reject an unmarked swap without replacing the valid save: " + str(rejected)): return
	data.site.armies = [snapshot]
	var loaded: Dictionary = Store.load_site(SAVE)
	if not _require(bool(loaded.get("ok", false)), "SiteStore.load_site rejected the in-flight RETREAT pair: " + str(loaded)): return
	var active_data: TerrainData = loaded.data
	if not _require(active_data != data and active_data.height_levels == data.height_levels \
		and active_data.static_blocked == data.static_blocked,
		"Load must reconstruct the same legal terrain"): return
	_restored = TerrainArmy.new()
	_restored.roster_size = 2
	_restored.exchange_enabled = true
	_restored_coordinator.register_formation(_restored)
	_restored.restore_combat_state(active_data.site.armies[0], active_data, null, null)
	if not _require(_restored.combat_order == TerrainArmy.CombatOrder.RETREAT and _restored.cells == _source.cells \
		and _restored.moving_to == _source.moving_to and _restored.capture_combat_state().get("combat_batch_retreat_members", []).size() == 2 \
		and _restored_coordinator.get_inflight_batches_for_formation(_restored).size() == 1,
		"Load changed the order, physical edge, RETREAT markers, or completion barrier"): return
	for i in range(2):
		if not _require(absf(_restored.move_progress[i] - _source.move_progress[i]) < 0.000000000000001,
			"Load changed physical interpolation at member " + str(i)): return
	var swapped := false
	for tick in range(12):
		_advance(_restored, _restored_coordinator)
		if _restored.cells[0] == front and _restored.cells[1] == rear:
			swapped = true
			break
	if not _require(swapped and _restored.moving_to[0] == TerrainArmy.INVALID_CELL \
		and _restored.moving_to[1] == TerrainArmy.INVALID_CELL and _restored._cell_owners.size() == 2 \
		and _restored._cell_owners.get(front, -1) == 0 and _restored._cell_owners.get(rear, -1) == 1 \
		and _restored._reserved_cells.is_empty() \
		and _restored_coordinator.get_inflight_batches_for_formation(_restored).is_empty(),
		"Loaded reciprocal pair must commit atomically with unique occupancy and no stale claims"): return
	var attack_result: Dictionary = _source.issue_combat_order(_source.current_commander, TerrainArmy.CombatOrder.ATTACK)
	if not _require(bool(attack_result.get("ok", false)) and _source.moving_to[0] == front and _source.moving_to[1] == rear,
		"ATTACK must preserve a RETREAT pair that already began its physical step"): return
	var interrupted: Dictionary = _source.capture_combat_state()
	if not _require(int(interrupted.combat_order) == TerrainArmy.CombatOrder.ATTACK
		and interrupted.get("combat_batch_retreat_members", []).size() == 2
		and interrupted.combat_batches.size() == 1 and interrupted.combat_batches[0].size() == 2
		and Store._valid_combat_movement_snapshot(data, interrupted, {}),
		"SiteStore must validate the original RETREAT batch after a new ATTACK order"): return
	data.site.armies = [interrupted]
	var interrupted_saved: Dictionary = Store.save(data, INTERRUPTED_SAVE)
	if not _require(bool(interrupted_saved.get("ok", false)),
		"SiteStore must save the original RETREAT batch after a new ATTACK order: " + str(interrupted_saved)): return
	var interrupted_loaded: Dictionary = Store.load_site(INTERRUPTED_SAVE)
	if not _require(bool(interrupted_loaded.get("ok", false))
		and int(interrupted_loaded.data.site.armies[0].combat_order) == TerrainArmy.CombatOrder.ATTACK
		and interrupted_loaded.data.site.armies[0].get("combat_batch_retreat_members", []).size() == 2,
		"SiteStore must load the ATTACK order and original in-flight RETREAT pair"): return
	_restored_coordinator.unregister_formation(_restored)
	_restored.free()
	_restored = TerrainArmy.new()
	_restored.roster_size = 2
	_restored.exchange_enabled = true
	_restored_coordinator.register_formation(_restored)
	_restored.restore_combat_state(interrupted_loaded.data.site.armies[0], interrupted_loaded.data, null, null)
	if not _require(_restored.combat_order == TerrainArmy.CombatOrder.ATTACK
		and _restored.moving_to[0] == front and _restored.moving_to[1] == rear
		and _restored_coordinator.get_inflight_batches_for_formation(_restored).size() == 1,
		"Runtime restore must retain the new ATTACK order and old RETREAT batch"): return
	var interrupted_swapped := false
	for tick in range(12):
		_advance(_restored, _restored_coordinator)
		if _restored.cells[0] == front and _restored.cells[1] == rear:
			interrupted_swapped = true
			break
	if not _require(interrupted_swapped and _restored._cell_owners.get(front, -1) == 0
		and _restored._cell_owners.get(rear, -1) == 1 and _restored._reserved_cells.is_empty()
		and _restored_coordinator.get_inflight_batches_for_formation(_restored).is_empty(),
		"Interrupted RETREAT batch must still finish atomically after loading ATTACK"): return
	_finish(true, "COMBAT MOVEMENT RETREAT PAIR STORE RESUME PASS: in_flight=2 saved=true loaded=true unmarked_rejected=true atomic_commit=true")
