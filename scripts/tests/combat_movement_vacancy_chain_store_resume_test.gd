extends SceneTree
## A saved, half-finished turning vacancy chain must resume its queued step.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const SAVE := "res://.godot-temp/site_combat/vacancy-chain-resume.json"

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

func _require(ok: bool, message: String) -> bool:
	if not ok:
		_finish(false, message)
	return ok

func _run() -> void:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	SiteEnvironment.initialize(data, "vacancy-chain-resume-fixture")
	for i in range(data.height_levels.size()):
		data.height_levels[i] = 0
		data.site.terrain_changes[str(i)] = 0
	SiteRuntime.rebuild_terrain_edges(data)
	var room := TerrainArmy.INVALID_CELL
	for y in range(2, data.size.y - 8):
		for x in range(2, data.size.x - 35):
			var clear := true
			for dy in range(7):
				for dx in range(35):
					if not data.is_walkable(Vector2i(x + dx, y + dy)):
						clear = false
						break
				if not clear: break
			if clear:
				room = Vector2i(x, y)
				break
		if room != TerrainArmy.INVALID_CELL: break
	if not _require(room != TerrainArmy.INVALID_CELL, "No legal vacancy-chain room"): return
	_source = Helper.create_test_army(data, 1, 0, 9, room + Vector2i(1, 3))
	_source_coordinator.register_formation(_source)
	if not _require(bool(_source.issue_combat_order(_source.current_commander, TerrainArmy.CombatOrder.MOVE, room + Vector2i(29, 3), -1, Vector2i.RIGHT).get("ok", false)), "MOVE order rejected"): return
	var plan: CombatDeploymentPlan = _source.get_active_deployment_plan()
	var move: CombatMovePlan = _source.get_active_move_plan()
	var slots: Dictionary = {}
	for cell: Vector2i in plan.platform_slots:
		slots[cell] = true
	var vacancy := TerrainArmy.INVALID_CELL
	var active_from := TerrainArmy.INVALID_CELL
	var queued_from := TerrainArmy.INVALID_CELL
	var waiting_start := TerrainArmy.INVALID_CELL
	for candidate: Vector2i in plan.platform_slots:
		for first: Vector2i in TerrainData.DIRECTIONS:
			for second: Vector2i in TerrainData.DIRECTIONS:
				var neighbor: Vector2i = candidate - first
				var edge: Vector2i = neighbor - second
				if first != second and first != -second and slots.has(neighbor) and slots.has(edge) and data.can_step(edge, neighbor) and data.can_step(neighbor, candidate):
					var outside := TerrainArmy.INVALID_CELL
					for direction: Vector2i in TerrainData.DIRECTIONS:
						var adjacent: Vector2i = edge + direction
						if not slots.has(adjacent) and data.can_step(adjacent, edge):
							outside = adjacent
							break
					if outside == TerrainArmy.INVALID_CELL:
						continue
					vacancy = candidate
					active_from = neighbor
					queued_from = edge
					waiting_start = outside
					break
			if vacancy != TerrainArmy.INVALID_CELL: break
		if vacancy != TerrainArmy.INVALID_CELL: break
	if not _require(vacancy != TerrainArmy.INVALID_CELL and waiting_start != TerrainArmy.INVALID_CELL, "Need a turning platform chain with a legal exterior edge"): return
	var waiting: int = int(plan.slot_owner_map[vacancy])
	var active: int = int(plan.slot_owner_map[active_from])
	var queued: int = int(plan.slot_owner_map[queued_from])
	var waiting_index := _source.index_for_identity(waiting)
	_source._cell_owners.clear()
	for index in range(_source.roster_size):
		var mid := _source.combat_identity(index)
		if mid == waiting:
			_source.cells[index] = waiting_start
		else:
			_source.cells[index] = plan.get_slot_for_member(mid)
		_source.combat_slots[index] = plan.get_slot_for_member(mid)
		_source._cell_owners[_source.cells[index]] = index
		plan.ever_admitted_platform_member_ids[mid] = true
		if mid != waiting:
			plan.admitted_platform_member_ids.append(mid)
			if mid != active:
				plan.settled_platform_member_ids.append(mid)
				plan.member_slot_locked[mid] = true
	plan.pending_platform_member_ids = [waiting]
	plan.queue_released = false
	plan.member_slot_locked.erase(waiting)
	plan.member_slot_locked.erase(active)
	plan.member_slot_locked.erase(queued)
	move.platform_settled_highwater = plan.settled_platform_member_ids.size()
	move.phase = Types.CombatMovePhase.PLATFORM_INGRESS
	move.planning_time_sec = 10.0
	move.last_platform_progress_time_sec = 10.0
	if not _require(_source.cells[waiting_index] == waiting_start and _source._cell_owners.size() == 9, "Fixture must leave the waiting owner physically outside"): return
	if not _require(Destination._start_platform_vacancy_chain(move, plan, [queued, active], [active_from, vacancy], _source.get_active_members_occupancy()), "Real planner must create a one-step turning queue"): return
	if not _require(move.queued_vacancy_steps.size() == 1 and move.active_vacancy_chain_actors == [active] and move.vacancy_waiting_id == waiting, "Turning chain setup changed"): return
	_source_coordinator._rebuild_occupancy()
	var grid = _source_coordinator.movement_reservation_grid
	grid.begin_tick(_source_coordinator._current_occupancy, data)
	var proposal: int = grid.propose_move(_source.formation_runtime_id, active, _source.get_order_serial(), active_from, vacancy)
	grid.resolve_all()
	if not _require(proposal >= 0 and grid.proposal_lookup[proposal].status == Types.MoveProposalStatus.ACCEPTED, "First physical edge rejected"): return
	grid.commit_all(_source_coordinator._member_lookup, 1)
	_source_coordinator._register_started_batches()
	_source.prepare_combat(0.14)
	_source_coordinator.complete_committed_moves()
	if not _require(_source.cells[_source.index_for_identity(active)] == active_from and _source.moving_to[_source.index_for_identity(active)] == vacancy, "Save must occur mid-animation"): return
	var snapshot: Dictionary = _source.capture_combat_state()
	var chain: Dictionary = snapshot.combat_move_plan.vacancy_chain_state
	if not _require(chain.active == [active] and chain.queued.size() == 1 and chain.waiting == waiting and chain.hold.has(waiting) and chain.start_cells.has(str(active)), "Active and pending chain state must be serialized together"): return
	if not _require(Store._valid_combat_movement_snapshot(data, snapshot, {}), "SiteStore rejected the valid in-flight chain"): return
	var bad_id: Dictionary = snapshot.duplicate(true)
	bad_id.combat_move_plan.vacancy_chain_state.queued[0].actor = 2147483647
	if not _require(not Store._valid_combat_movement_snapshot(data, bad_id, {}), "Unknown queued actor must be rejected"): return
	var bad_edge: Dictionary = snapshot.duplicate(true)
	bad_edge.combat_move_plan.vacancy_chain_state.queued[0].to = [0, 0]
	if not _require(not Store._valid_combat_movement_snapshot(data, bad_edge, {}), "Forged queued destination must be rejected"): return
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy.combat_move_plan.erase("vacancy_chain_state")
	if not _require(Store._valid_combat_movement_snapshot(data, legacy, {}), "Earlier v1 movement snapshots must remain loadable"): return
	data.site.armies = [snapshot]
	data.site.army_trial_active = true
	data.site.army_next_team = 2
	data.site.actors = {}
	data.site.combat_left = 0.0
	if not _require(bool(Store.save(data, SAVE).get("ok", false)), "SiteStore rejected the real chain snapshot"): return
	var loaded: Dictionary = Store.load_site(SAVE)
	if not _require(bool(loaded.get("ok", false)), "SiteStore could not load the chain snapshot"): return
	var restored_data: TerrainData = loaded.data
	_restored = TerrainArmy.new()
	# Production armies live in the scene tree; fixtures step them explicitly.
	root.add_child(_restored)
	_restored.set_process(false)
	_restored.roster_size = 9
	_restored.exchange_enabled = true
	_restored_coordinator.register_formation(_restored)
	_restored.restore_combat_state(restored_data.site.armies[0], restored_data, null, null)
	var restored_move: CombatMovePlan = _restored.get_active_move_plan()
	var restored_plan: CombatDeploymentPlan = _restored.get_active_deployment_plan()
	if not _require(restored_move != null and restored_move.active_vacancy_chain_actors == [active] and restored_move.queued_vacancy_steps.size() == 1 and restored_move.vacancy_waiting_id == waiting and restored_move.member_recovery_hold.has(waiting) and _restored_coordinator.get_inflight_batches_for_formation(_restored).size() == 1, "Load lost the active edge, queued step, wait hold, or Grid batch"): return
	_restored.prepare_combat(0.25)
	_restored_coordinator.complete_committed_moves()
	if not _require(_restored.cells[_restored.index_for_identity(active)] == vacancy and _restored.cells[_restored.index_for_identity(waiting)] == waiting_start, "First physical arrival after load failed"): return
	Destination.update_movement_phase(restored_move, restored_plan, _restored.get_active_members_occupancy(), restored_data, 0.25)
	if not _require(restored_move.active_vacancy_chain_actors == [queued] and restored_move.queued_vacancy_steps.is_empty() and restored_move.member_recovery_hold.has(waiting) and restored_plan.get_slot_for_member(queued) == active_from, "Loaded queue must dispatch only after first physical arrival"): return
	_restored_coordinator._rebuild_occupancy()
	var next_grid = _restored_coordinator.movement_reservation_grid
	next_grid.begin_tick(_restored_coordinator._current_occupancy, restored_data)
	var next_proposal: int = next_grid.propose_move(_restored.formation_runtime_id, queued, _restored.get_order_serial(), queued_from, active_from)
	next_grid.resolve_all()
	if not _require(next_proposal >= 0 and next_grid.proposal_lookup[next_proposal].status == Types.MoveProposalStatus.ACCEPTED, "Resumed queued physical edge rejected"): return
	next_grid.commit_all(_restored_coordinator._member_lookup, 2)
	_restored_coordinator._register_started_batches()
	_restored.prepare_combat(0.39)
	_restored_coordinator.complete_committed_moves()
	Destination.update_movement_phase(restored_move, restored_plan, _restored.get_active_members_occupancy(), restored_data, 0.39)
	if not _require(_restored.cells[_restored.index_for_identity(queued)] == active_from and restored_move.active_vacancy_chain_actors.is_empty() and not restored_move.member_recovery_hold.has(waiting) and restored_plan.get_slot_for_member(waiting) == queued_from, "Resumed chain must release its final edge to the waiting owner"): return
	_finish(true, "COMBAT MOVEMENT VACANCY CHAIN STORE RESUME PASS")
