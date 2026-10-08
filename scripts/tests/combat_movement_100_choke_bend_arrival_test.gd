extends SceneTree
## One hundred real members cross a walkability-wall 4-to-1-to-4 choke and an L bend.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Transit = preload("res://scripts/terrain_lab/formation_transit_planner.gd")

var _army: TerrainArmy = null
var _coordinator: SiteCombatMovementCoordinator = null

func _initialize() -> void:
	call_deferred("_run")

func _finish(ok: bool, message: String) -> void:
	_cleanup()
	if ok:
		print(message)
		quit(0)
	else:
		push_error(message)
		quit(1)

func _cleanup() -> void:
	if is_instance_valid(_army):
		if _coordinator != null:
			_coordinator.unregister_formation(_army)
		_army.free()
	_army = null
	_coordinator = null

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_finish(false, message)
	return false

func _build_bend() -> TerrainData:
	var data: TerrainData = Helper.build_bottleneck_map(Vector2i(70, 45), 20, 25, 33, 1)["data"]
	# The wall spans the map height. Only an east-south-east one-cell L route is open.
	for x in range(29, 34):
		var old_cell := Vector2i(x, 20)
		data.flags[data.index(old_cell)] = 0
		data.static_blocked[data.index(old_cell)] = 1
	for y in range(20, 25):
		var vertical := Vector2i(28, y)
		data.flags[data.index(vertical)] = TerrainData.Flag.WALKABLE
		data.static_blocked[data.index(vertical)] = 0
	for x in range(28, 34):
		var exit_cell := Vector2i(x, 24)
		data.flags[data.index(exit_cell)] = TerrainData.Flag.WALKABLE
		data.static_blocked[data.index(exit_cell)] = 0
	return data

func _run() -> void:
	var bend_only: bool = OS.get_cmdline_user_args().has("--bend-only")
	if not bend_only:
		var straight: TerrainData = Helper.build_bottleneck_map(Vector2i(70, 45), 20, 25, 31, 1)["data"]
		if not _require(Transit.detect_corridor_width(straight, Vector2i(21, 20), Vector2i.RIGHT) >= 4 and Transit.detect_corridor_width(straight, Vector2i(27, 20), Vector2i.RIGHT) == 1 and Transit.detect_corridor_width(straight, Vector2i(35, 20), Vector2i.RIGHT) >= 4, "Straight fixture must physically narrow 4-to-1-to-4"): return
		if not _run_case("straight", straight, Vector2i(45, 20), false): return
	var bend: TerrainData = _build_bend()
	if not _require(Transit.detect_corridor_width(bend, Vector2i(21, 20), Vector2i.RIGHT) >= 4 and Transit.detect_corridor_width(bend, Vector2i(27, 20), Vector2i.RIGHT) == 1 and Transit.detect_corridor_width(bend, Vector2i(28, 22), Vector2i.DOWN) == 1 and Transit.detect_corridor_width(bend, Vector2i(37, 24), Vector2i.RIGHT) >= 4, "Bend fixture must force one-cell east-south-east travel through a real wall"): return
	if not _run_case("bend", bend, Vector2i(46, 24), true): return
	_finish(true, "COMBAT MOVEMENT 100 BEND ARRIVAL PASS" if bend_only else "COMBAT MOVEMENT 100 CHOKE AND BEND ARRIVAL PASS")

func _run_case(label: String, data: TerrainData, anchor: Vector2i, expect_bend: bool) -> bool:
	_army = Helper.create_test_army(data, 1, 0, 100, Vector2i(5, 15))
	_coordinator = Coordinator.new()
	_coordinator.register_formation(_army)
	var order: Dictionary = _army.issue_combat_order(_army.current_commander, TerrainArmy.CombatOrder.MOVE, anchor, -1, Vector2i.RIGHT)
	if not _require(bool(order.get("ok", false)), "%s: MOVE must be accepted: %s" % [label, str(order)]): return false
	var plan: CombatDeploymentPlan = _army.get_active_deployment_plan()
	if not _require(plan != null and plan.final_facing == Vector2i.RIGHT, "%s: final facing must be fixed at command time" % label): return false
	var previous: Array[Vector2i] = _army.cells.duplicate()
	var crossed: Dictionary = {}
	var bent: Dictionary = {}
	var completed_tick := -1
	for tick in range(8000):
		_coordinator.combat_logic_tick(0.05)
		_army.prepare_combat(0.05)
		_coordinator.complete_committed_moves()
		var occupied: Dictionary = {}
		var claims: Dictionary = {}
		for i in range(100):
			var cell: Vector2i = _army.cells[i]
			if not _require(data.contains(cell) and data.is_walkable(cell) and not occupied.has(cell), "%s: invalid/duplicate cell at tick %d" % [label, tick]): return false
			occupied[cell] = true
			if cell != previous[i]:
				if not _require(data.can_step(previous[i], cell), "%s: member skipped a legal physical edge at tick %d" % [label, tick]): return false
				previous[i] = cell
			if cell.x > 33:
				crossed[i] = true
			if cell == Vector2i(28, 22):
				bent[i] = true
			var claim: Vector2i = _army.moving_to[i]
			if claim != TerrainArmy.INVALID_CELL:
				if not _require(data.can_step(cell, claim) and not claims.has(claim), "%s: invalid/duplicate in-flight claim at tick %d" % [label, tick]): return false
				claims[claim] = true
		if _army.combat_order == TerrainArmy.CombatOrder.HOLD:
			completed_tick = tick
			break
		if tick % 200 == 0:
			_print_progress(label, tick, plan, crossed)
	if completed_tick >= 0 and not _army.command_status.begins_with("已抵達"):
		_print_progress(label, completed_tick, plan, crossed)
	elif completed_tick < 0:
		_print_progress(label, 8000, plan, crossed)
	if not _require(completed_tick >= 0 and _army.command_status.begins_with("已抵達"), "%s: all 100 must complete arrival; status=%s" % [label, _army.command_status]): return false
	if not _require(crossed.size() == 100 and (not expect_bend or bent.size() == 100), "%s: all 100 must physically cross the real wall%s" % [label, " and 90-degree bend" if expect_bend else ""]): return false
	if not _require(Destination.is_settled(plan, _army.get_active_members_occupancy()), "%s: every member must occupy its exact final slot" % label): return false
	var final_cells: Array[Vector2i] = _army.cells.duplicate()
	var leases: Array[Vector2i] = _coordinator.deployment_registry.get_formation_reserved_slots(_army.team_id)
	if not _require(leases.size() == 100, "%s: all 100 final slots must retain their reservation" % label): return false
	for quiet_tick in range(100):
		_coordinator.combat_logic_tick(0.05)
		_army.prepare_combat(0.05)
		_coordinator.complete_committed_moves()
		if not _require(_army.combat_order == TerrainArmy.CombatOrder.HOLD and _army.cells == final_cells and _army.get_active_movement_claims().is_empty() and _army._combat_batch_members.is_empty() and _coordinator._inflight_batches.is_empty(), "%s: arrival must stay stable and claim-free for five seconds at tick %d" % [label, quiet_tick]): return false
		for i in range(100):
			if not _require(_army.moving_to[i] == TerrainArmy.INVALID_CELL and _army.facing[i] == Vector2i.RIGHT, "%s: final facing/idle state changed during stable window" % label): return false
	var leases_after: Array[Vector2i] = _coordinator.deployment_registry.get_formation_reserved_slots(_army.team_id)
	if not _require(leases_after.size() == leases.size(), "%s: final reservation count changed after arrival" % label): return false
	for slot in leases:
		if not _require(leases_after.has(slot), "%s: a final reservation disappeared after arrival" % label): return false
	print("COMBAT MOVEMENT 100 %s ARRIVAL PASS: tick=%d" % [label, completed_tick])
	_cleanup()
	return true

func _print_progress(label: String, tick: int, plan: CombatDeploymentPlan, crossed: Dictionary) -> void:
	var move_plan: CombatMovePlan = _army.get_active_move_plan()
	print("CHOKE_BEND_PROGRESS ", label, " tick=", tick, " crossed=", crossed.size(), " pending=", plan.pending_platform_member_ids.size(), " admitted=", plan.admitted_platform_member_ids.size(), " platform=", plan.settled_platform_member_ids.size(), " queue=", plan.settled_queue_member_ids.size(), " phase=", move_plan.phase if move_plan != null else -1, " cursor=", move_plan.macro_cursor if move_plan != null else -1)
	if move_plan != null and label == "bend":
		var commander: int = _army.combat_identity(0)
		var commander_cell: Vector2i = _army.cells[0]
		var commander_target: Dictionary = Destination.resolve_member_target(move_plan, plan, commander, commander_cell)
		print("CHOKE_BEND_COMMANDER tick=", tick, " cell=", commander_cell, " soft=", move_plan.member_transit_slots.get(commander, Vector2i(-1, -1)), " observed=", move_plan.member_observed_path_s.get(commander, -INF), " assigned_s=", move_plan.member_path_s.get(commander, -INF), " target=", commander_target, " path_epoch=", move_plan.path_epoch, " replans=", move_plan.macro_replan_count, " last_progress=", move_plan.last_platform_progress_time_sec, " stall=", move_plan.active_stall_total_sec, " recovery_stage=", move_plan.recovery_stage)
		if tick >= 1800:
			for mid in [1146, 1153]:
				var cell: Vector2i = _army.cells[_army.index_for_identity(mid)]
				var slot: Vector2i = plan.get_slot_for_member(mid)
				print("CHOKE_BEND_CROSSED tick=", tick, " mid=", mid, " cell=", cell, " slot=", slot, " owner_here=", plan.slot_owner_map.get(cell, -1), " role=", plan.get_role_for_member(mid), " tactical=", plan.slot_tactical_roles.get(slot, -1), " locked=", plan.is_slot_locked(mid), " admitted=", plan.admitted_platform_member_ids.has(mid), " proposal=", move_plan.member_pending_proposal_id.get(mid, -1), " hold=", move_plan.member_crossed_swap_hold.has(mid), " chain=", move_plan.active_vacancy_chain_actors, " chain_target=", move_plan.member_vacancy_chain_target.get(mid, Vector2i(-1, -1)), " epoch=", move_plan.member_assignment_epoch.get(mid, 0))
	var owners: Dictionary = {}
	for mid in _army.get_active_members_occupancy().keys():
		owners[_army.get_active_members_occupancy()[mid]] = mid
	var rows: Array[String] = []
	for y in range(19, 22):
		var row: Array[String] = []
		for x in range(22, 36):
			var mid: int = int(owners.get(Vector2i(x, y), -1))
			row.append(".." if mid < 0 else "%02d" % (mid % 100))
		rows.append("y%d:%s" % [y, " ".join(row)])
	print("CHOKE_BEND_CORRIDOR ", " | ".join(rows))
	if label == "bend" and move_plan != null:
		var gate: Array[String] = []
		for mid in _army.get_active_members_occupancy().keys():
			var cell: Vector2i = _army.get_active_members_occupancy()[mid]
			if cell.x < 24 or cell.x > 34 or cell.y < 19 or cell.y > 25:
				continue
			var idx: int = _army.index_for_identity(mid)
			gate.append("%d@%s soft=%s target=%s observed=%.1f" % [mid, str(cell), str(move_plan.member_transit_slots.get(mid, Vector2i(-1, -1))), str(_army.combat_slots[idx]), float(move_plan.member_observed_path_s.get(mid, -INF))])
		print("CHOKE_BEND_GATE tick=", tick, " ", gate)
	var unresolved: Array[String] = []
	for mid in plan.member_slot_map.keys():
		var idx: int = _army.index_for_identity(mid)
		if idx < 0 or _army.cells[idx] == plan.get_slot_for_member(mid):
			continue
		var status: int = int(move_plan.member_route_status.get(mid, -1)) if move_plan != null else -1
		var retry: int = int(move_plan.member_route_retry_count.get(mid, -1)) if move_plan != null else -1
		unresolved.append("%d:%s>%s target=%s status=%d retry=%d" % [mid, str(_army.cells[idx]), str(plan.get_slot_for_member(mid)), str(_army.combat_slots[idx]), status, retry])
		if unresolved.size() >= 12:
			break
	print("CHOKE_BEND_UNRESOLVED ", unresolved)
	if tick >= 2800 and move_plan != null:
		var empty_final: Array[String] = []
		for slot in plan.platform_slots:
			if not owners.has(slot):
				var owner: int = int(plan.slot_owner_map.get(slot, -1))
				empty_final.append("%s:%d:%s" % [str(slot), owner, str(plan.is_slot_locked(owner))])
		print("CHOKE_BEND_TAIL chain=", move_plan.active_vacancy_chain_actors, " chain_targets=", move_plan.member_vacancy_chain_target.size(), " last_platform_progress=", move_plan.last_platform_progress_time_sec, " next_recovery=", move_plan.next_platform_recovery_time_sec, " empty_final=", empty_final)
		if label == "straight":
			for slot in plan.platform_slots:
				if owners.has(slot) or int(plan.slot_tactical_roles.get(slot, -1)) != 0:
					continue
				var waiting_owner: int = int(plan.slot_owner_map.get(slot, -1))
				if waiting_owner < 0 or not plan.admitted_platform_member_ids.has(waiting_owner):
					continue
				var waiting_cell: Vector2i = _army.cells[_army.index_for_identity(waiting_owner)]
				var free_area: Dictionary = {}
				for platform_cell in plan.platform_footprint:
					if not owners.has(platform_cell) or platform_cell == waiting_cell:
						free_area[platform_cell] = true
				var free_distance: int = Destination._platform_distance(waiting_cell, slot, _army.data, free_area)
				var neighbors: Array[String] = []
				for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
					var neighbor: Vector2i = slot + direction
					var occupant: int = int(owners.get(neighbor, -1))
					neighbors.append("%s:%d locked=%s settled=%s step=%s" % [str(neighbor), occupant, str(plan.is_slot_locked(occupant)), str(plan.settled_platform_member_ids.has(occupant)), str(_army.data.can_step(neighbor, slot))])
				print("CHOKE_BEND_ISOLATED_FINAL owner=", waiting_owner, " cell=", waiting_cell, " slot=", slot, " locked=", plan.is_slot_locked(waiting_owner), " admitted=", plan.admitted_platform_member_ids.has(waiting_owner), " pending=", plan.pending_platform_member_ids.size(), " proposal=", move_plan.member_pending_proposal_id.has(waiting_owner), " footprint=", plan.platform_footprint.has(waiting_cell), " free_distance=", free_distance, " neighbors=", neighbors)
				break
		if label == "straight" and plan.member_slot_map.has(1150):
			var waiting := 1150
			var start: Vector2i = _army.cells[_army.index_for_identity(waiting)]
			var vacancy: Vector2i = plan.get_slot_for_member(waiting)
			var free_cells: Dictionary = {}
			for cell in plan.platform_footprint:
				if not owners.has(cell) or cell == start:
					free_cells[cell] = true
			var candidates: Array[String] = []
			for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var edge: Vector2i = vacancy + direction
				var blocker: int = int(owners.get(edge, -1))
				free_cells[edge] = true
				var distance: int = Destination._platform_distance(start, edge, _army.data, free_cells)
				free_cells.erase(edge)
				candidates.append("%s occupant=%d owner=%d locked=%s settled=%s role=%d step=%s reach=%d" % [str(edge), blocker, int(plan.slot_owner_map.get(edge, -1)), str(plan.is_slot_locked(blocker)), str(plan.settled_platform_member_ids.has(blocker)), int(plan.slot_tactical_roles.get(edge, -1)), str(_army.data.can_step(edge, vacancy)), distance])
			print("CHOKE_BEND_VACANCY_1150 start=", start, " vacancy=", vacancy, " admitted=", plan.admitted_platform_member_ids.has(waiting), " pending=", plan.pending_platform_member_ids.has(waiting), " locked=", plan.is_slot_locked(waiting), " proposal=", move_plan.member_pending_proposal_id.has(waiting), " footprint=", plan.platform_footprint.has(start), " guard_count=", plan.settled_platform_member_ids.size(), "/", plan.platform_slots.size(), " current_reach=", Destination._platform_distance(start, vacancy, _army.data, free_cells), " neighbors=", candidates)
