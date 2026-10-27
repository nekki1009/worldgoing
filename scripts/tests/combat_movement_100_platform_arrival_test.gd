extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Transit = preload("res://scripts/terrain_lab/formation_transit_planner.gd")

var _army: TerrainArmy = null
var _coordinator: SiteCombatMovementCoordinator = null
var _slot_change_total: int = 0
var _recent_slot_changes: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	if is_instance_valid(_army):
		if _coordinator != null:
			_coordinator.unregister_formation(_army)
		_army.free()
	TerrainArmy.release_contact_source() # Headless teardown: release the shared contact rig before the post-quit frame (as f219902).
	quit(1)
	return false

func _print_frontier(plan: CombatDeploymentPlan) -> void:
	var move_plan = _army.get_active_move_plan()
	var cell_owners: Dictionary = {}
	for mid: int in _army.get_active_members_occupancy().keys():
		cell_owners[_army.get_active_members_occupancy()[mid]] = mid
	for y in range(27, 34):
		var row: Array[String] = []
		for x in range(38, 51):
			var cell := Vector2i(x, y)
			var owner: int = int(cell_owners.get(cell, -1))
			if owner < 0:
				row.append("...")
			else:
				var role := "P" if plan.is_platform_member(owner) else "Q"
				row.append("%s%02d" % [role, owner % 100])
		print("FRONTIER y=", y, " ", " ".join(row))
	if move_plan == null:
		return
	var samples: Array[String] = []
	for mid: int in plan.pending_platform_member_ids:
		var index: int = _army.index_for_identity(mid)
		if index < 0: continue
		var cell: Vector2i = _army.cells[index]
		var goal: Vector2i = _army.combat_slots[index]
		var route: Array = move_plan.member_paths.get(mid, [])
		var next: Vector2i = route[1] if route.size() > 1 else Vector2i(-1, -1)
		samples.append("%d@%s goal=%s next=%s next_owner=%d rank=%d s=%.1f" % [mid, str(cell), str(goal), str(next), int(cell_owners.get(next, -1)), int(move_plan.member_sequence_rank.get(mid, -1)), float(move_plan.member_observed_path_s.get(mid, -1.0))])
		if samples.size() >= 12: break
	print("PENDING_SAMPLES ", samples)
	var front: Array[int] = plan.pending_platform_member_ids.duplicate()
	front.sort_custom(func(a: int, b: int) -> bool:
		var ax: int = _army.cells[_army.index_for_identity(a)].x
		var bx: int = _army.cells[_army.index_for_identity(b)].x
		return ax > bx if ax != bx else a < b
	)
	var front_samples: Array[String] = []
	for i in range(mini(8, front.size())):
		var mid: int = front[i]
		var index: int = _army.index_for_identity(mid)
		var goal: Vector2i = _army.combat_slots[index]
		var route: Array = move_plan.member_paths.get(mid, [])
		var probe: Array[Vector2i] = _army._find_local_route(_army.cells[index], goal, 512, true, -1, 0, false, _army.get_formation_movement_profile())
		front_samples.append("%d@%s goal=%s route=%d probe=%d first=%s retry=%d defer=%d" % [mid, str(_army.cells[index]), str(goal), route.size(), probe.size(), str(probe[1] if probe.size() > 1 else Vector2i(-1, -1)), int(move_plan.member_route_retry_count.get(mid, -1)), int(move_plan.member_defer_count.get(mid, -1))])
	print("FRONT_SAMPLES ", front_samples)
	var commander_id: int = _army.combat_identity(_army.current_commander)
	var commander_index: int = _army.index_for_identity(commander_id)
	if commander_index >= 0:
		var commander_cell: Vector2i = _army.cells[commander_index]
		var commander_goal: Vector2i = plan.get_slot_for_member(commander_id)
		print("COMMANDER ", commander_id, " cell=", commander_cell, " final=", commander_goal, " soft=", _army.combat_slots[commander_index], " rank=", move_plan.member_sequence_rank.get(commander_id, -1), " target=", move_plan.member_transit_slots.get(commander_id, Vector2i(-1, -1)), " route_status=", move_plan.member_route_status.get(commander_id, -1))
		for y in range(commander_cell.y - 2, commander_cell.y + 4):
			var local_row: Array[String] = []
			for x in range(commander_cell.x - 2, commander_cell.x + 7):
				var local_cell := Vector2i(x, y)
				var local_owner: int = int(cell_owners.get(local_cell, -1))
				if local_owner < 0:
					local_row.append("..." if _army.data.is_walkable(local_cell) else "###")
				else:
					local_row.append("%s%02d" % ["P" if plan.is_platform_member(local_owner) else "Q", local_owner % 100])
			print("COMMANDER_LOCAL y=", y, " ", " ".join(local_row))
		var neighbors: Array[String] = []
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var adjacent: Vector2i = commander_cell + direction
			var adjacent_owner: int = int(cell_owners.get(adjacent, -1))
			neighbors.append("%s owner=%d role=%d target=%s step=%s" % [str(adjacent), adjacent_owner, int(plan.member_role_map.get(adjacent_owner, -1)), str(plan.get_slot_for_member(adjacent_owner)), str(Transit._can_profile_step(_army.data, commander_cell, adjacent, _army.get_formation_movement_profile()))])
		print("COMMANDER_NEIGHBORS ", neighbors)
	var ramp: Array[String] = []
	var profile = _army.get_formation_movement_profile()
	for x in range(41, 48):
		var cell := Vector2i(x, 30)
		var next := cell + Vector2i.RIGHT
		ramp.append("%s owner=%d claimed=%d slot=%s next_step=%s" % [str(cell), int(cell_owners.get(cell, -1)), int(_army._reserved_cells.get(cell, -1)), str(_army.combat_slots[_army.index_for_identity(int(cell_owners[cell]))] if cell_owners.has(cell) else Vector2i(-1, -1)), str(profile != null and Transit._can_profile_step(_army.data, cell, next, profile))])
	print("RAMP_CELLS ", ramp)
	var entry_slots: Array[String] = []
	for x in range(45, 49):
		var cell := Vector2i(x, 30)
		var slot_owner: int = int(plan.slot_owner_map.get(cell, -1))
		var owner_index: int = _army.index_for_identity(slot_owner) if slot_owner >= 0 else -1
		entry_slots.append("%s occupant=%d claim=%d slot_owner=%d role=%d locked=%s owner_cell=%s cooldown=%.2f" % [str(cell), int(cell_owners.get(cell, -1)), int(_army._reserved_cells.get(cell, -1)), slot_owner, int(plan.slot_tactical_roles.get(cell, -1)), str(plan.is_slot_locked(slot_owner)), str(_army.cells[owner_index] if owner_index >= 0 else Vector2i(-1, -1)), float(move_plan.member_swap_cooldown_until_sec.get(slot_owner, -1.0))])
	print("ENTRY_SLOTS ", entry_slots, " recovery_clock=", move_plan.last_platform_progress_time_sec, "/", move_plan.next_platform_recovery_time_sec, "/", move_plan.planning_time_sec)
	var vacant_finals: Array[String] = []
	for slot in plan.platform_slots:
		if cell_owners.has(slot): continue
		var slot_owner: int = int(plan.slot_owner_map.get(slot, -1))
		var owner_index: int = _army.index_for_identity(slot_owner) if slot_owner >= 0 else -1
		vacant_finals.append("%s role=%d owner=%d owner_cell=%s locked=%s" % [str(slot), int(plan.slot_tactical_roles.get(slot, -1)), slot_owner, str(_army.cells[owner_index] if owner_index >= 0 else Vector2i(-1, -1)), str(plan.is_slot_locked(slot_owner))])
	print("VACANT_FINALS ", vacant_finals)
	print("SLOT_CHANGES total=", _slot_change_total, " recent=", _recent_slot_changes)
	var chain_state: Array[String] = []
	for mid in move_plan.active_vacancy_chain_actors:
		var index: int = _army.index_for_identity(mid)
		chain_state.append("%d@%s>%s moving=%s pending=%s locked=%s" % [mid, str(_army.cells[index] if index >= 0 else Vector2i(-1, -1)), str(plan.get_slot_for_member(mid)), str(_army.moving_to[index] if index >= 0 else Vector2i(-1, -1)), str(move_plan.member_pending_proposal_id.has(mid)), str(plan.is_slot_locked(mid))])
	print("VACANCY_CHAIN ", chain_state, " targets=", move_plan.member_vacancy_chain_target.size())
	var admitted_samples: Array[String] = []
	for mid: int in plan.admitted_platform_member_ids:
		var index: int = _army.index_for_identity(mid)
		if index < 0 or _army.cells[index] == plan.get_slot_for_member(mid): continue
		var admitted_route: Array = move_plan.member_paths.get(mid, [])
		var admitted_next: Vector2i = admitted_route[1] if admitted_route.size() > 1 else Vector2i(-1, -1)
		admitted_samples.append("%d@%s goal=%s next=%s next_owner=%d moving=%s status=%d defer=%d retry=%d current=%s" % [mid, str(_army.cells[index]), str(_army.combat_slots[index]), str(admitted_next), int(cell_owners.get(admitted_next, -1)), str(_army.moving_to[index]), int(move_plan.member_route_status.get(mid, -1)), int(move_plan.member_defer_count.get(mid, -1)), int(move_plan.member_route_retry_count.get(mid, -1)), str(move_plan.is_member_route_current(mid, _army.combat_slots[index]))])
		if admitted_samples.size() >= 10: break
	print("ADMITTED_SAMPLES ", admitted_samples)
	var unsettled_queue: Array[String] = []
	for mid: int in plan.queue_member_ids:
		var index: int = _army.index_for_identity(mid)
		if index < 0: continue
		var final_slot: Vector2i = plan.get_slot_for_member(mid)
		if _army.cells[index] == final_slot: continue
		var route: Array = move_plan.member_paths.get(mid, [])
		var probe: Array[Vector2i] = _army._find_local_route(_army.cells[index], final_slot, 512, true, -1, 0, false, _army.get_formation_movement_profile())
		var adjacent: Array[String] = []
		for direction in TerrainData.DIRECTIONS:
			var neighbor: Vector2i = _army.cells[index] + direction
			adjacent.append("%s:%d" % [str(neighbor), int(cell_owners.get(neighbor, -1))])
		unsettled_queue.append("%d@%s>%s target_owner=%d locked=%s route=%d probe=%d next=%s neighbors=%s" % [mid, str(_army.cells[index]), str(final_slot), int(cell_owners.get(final_slot, -1)), str(plan.is_slot_locked(mid)), route.size(), probe.size(), str(route[1] if route.size() > 1 else Vector2i(-1, -1)), str(adjacent)])
		if unsettled_queue.size() >= 16: break
	print("UNSETTLED_QUEUE ", unsettled_queue)
	var vacant_queue: Array[String] = []
	for slot: Vector2i in plan.approach_queue_slots:
		if cell_owners.has(slot): continue
		var slot_owner: int = int(plan.slot_owner_map.get(slot, -1))
		if slot_owner < 0: continue
		var owner_index: int = _army.index_for_identity(slot_owner)
		vacant_queue.append("%s owner=%d at=%s locked=%s" % [str(slot), slot_owner, str(_army.cells[owner_index] if owner_index >= 0 else Vector2i(-1, -1)), str(plan.is_slot_locked(slot_owner))])
	print("VACANT_QUEUE ", vacant_queue)
	for y in range(24, 35):
		var queue_row: Array[String] = []
		for x in range(35, 44):
			var cell := Vector2i(x, y)
			var owner: int = int(cell_owners.get(cell, -1))
			queue_row.append("..." if owner < 0 else "%s%02d" % ["L" if plan.is_slot_locked(owner) else ("P" if plan.is_platform_member(owner) else "Q"), owner % 100])
		print("QUEUE_ZONE y=", y, " ", " ".join(queue_row))
	var status_counts: Dictionary = {}
	for proposal in _coordinator.movement_reservation_grid.get_proposals():
		status_counts[proposal.status] = int(status_counts.get(proposal.status, 0)) + 1
	print("GRID_LAST_STATUS ", status_counts)

func _run() -> void:
	var fixture: Dictionary = Helper.build_exact_60_platform_map()
	var data: TerrainData = fixture.data
	var army := Helper.create_test_army(data, 1, 0, 100, Vector2i(30, 25))
	_army = army
	var coordinator := Coordinator.new()
	_coordinator = coordinator
	coordinator.register_formation(army)
	var order: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, fixture.anchor, -1, Vector2i.RIGHT)
	if not _require(bool(order.get("ok", false)), "The 100-person single-ramp MOVE order must be accepted: " + str(order)): return
	var plan = army.get_active_deployment_plan()
	if not _require(plan != null and plan.platform_slots.size() == 60 and plan.queue_member_ids.size() == 40, "The command must reserve exactly 60 platform and 40 queue slots"): return
	var previous: Array[Vector2i] = army.cells.duplicate()
	var previous_slots: Dictionary = plan.member_slot_map.duplicate()
	var completed_tick := -1
	for tick in range(5000):
		coordinator.combat_logic_tick(0.05)
		army.prepare_combat(0.05)
		coordinator.complete_committed_moves()
		for mid in plan.member_slot_map.keys():
			var assigned: Vector2i = plan.get_slot_for_member(mid)
			if previous_slots.get(mid, assigned) != assigned:
				_slot_change_total += 1
				_recent_slot_changes.append("t%d %d:%s>%s" % [tick, mid, str(previous_slots[mid]), str(assigned)])
				if _recent_slot_changes.size() > 20: _recent_slot_changes.pop_front()
				previous_slots[mid] = assigned
		var occupied: Dictionary = {}
		var claimed: Dictionary = {}
		for i in range(100):
			var cell: Vector2i = army.cells[i]
			if not _require(data.contains(cell) and data.is_walkable(cell) and not occupied.has(cell), "All 100 source cells must remain distinct and legal at tick %d" % tick): return
			occupied[cell] = true
			if cell != previous[i] and not _require(data.can_step(previous[i], cell), "No member may teleport or cross a cliff at tick %d" % tick): return
			previous[i] = cell
			var destination: Vector2i = army.moving_to[i]
			if destination != TerrainArmy.INVALID_CELL:
				if not _require(data.can_step(cell, destination) and not claimed.has(destination), "In-flight claims must be unique and legal at tick %d" % tick): return
				claimed[destination] = true
		if tick % 50 == 0:
			var platform_roles := 0
			for mid in plan.member_role_map.keys():
				if plan.is_platform_member(mid): platform_roles += 1
			if not _require(platform_roles == 60 and plan.queue_member_ids.size() == 40 and plan.member_slot_map.size() == 100 and plan.slot_owner_map.size() == 100, "Every role exchange must preserve 60 platform / 40 queue and one final slot per member at tick %d" % tick): return
			var mp = army.get_active_move_plan()
			print("100_PLATFORM_PROGRESS tick=", tick, " phase=", mp.phase if mp != null else -1, " cursor=", mp.macro_cursor if mp != null else -1, " width=", mp.current_width if mp != null else -1, " stall=", mp.active_stall_total_sec if mp != null else -1, " accepted=", army.accepted_count, " pending=", plan.pending_platform_member_ids.size(), " admitted=", plan.admitted_platform_member_ids.size(), " platform=", plan.settled_platform_member_ids.size(), " queue=", plan.settled_queue_member_ids.size(), " released=", plan.queue_released)
			if tick in [650, 800, 900, 1400, 1600, 1800, 2000, 2100, 2200, 2350]: _print_frontier(plan)
		if army.combat_order == TerrainArmy.CombatOrder.HOLD:
			if not army.command_status.begins_with("已抵達"):
				var unresolved: Array[String] = []
				for mid: int in plan.member_slot_map.keys():
					var index: int = army.index_for_identity(mid)
					if index >= 0 and army.cells[index] != plan.get_slot_for_member(mid):
						unresolved.append("%d:%s>%s" % [mid, str(army.cells[index]), str(plan.get_slot_for_member(mid))])
						if unresolved.size() >= 12: break
				print("100_PLATFORM_FAILURE tick=", tick, " unresolved=", unresolved)
				_print_frontier(plan)
			completed_tick = tick
			break
	if not _require(completed_tick >= 0 and army.command_status.begins_with("已抵達"), "The last member must reach its final slot; status=" + army.command_status): return
	if not _require(Destination.is_settled(plan, army.get_active_members_occupancy()), "All 60 platform and 40 queue members must occupy their exact final slots"): return
	if not _require(plan.settled_platform_member_ids.size() == 60 and plan.settled_queue_member_ids.size() == 40, "Arrival counts must be 60 + 40"): return
	for i in range(100):
		if not _require(army.moving_to[i] == TerrainArmy.INVALID_CELL and army.facing[i] == Vector2i.RIGHT, "Every arrival must have completed its step and faced east"): return
	var final_cells: Array[Vector2i] = army.cells.duplicate()
	var final_slots: Dictionary = plan.member_slot_map.duplicate()
	for stable_tick in range(100):
		coordinator.combat_logic_tick(0.05)
		army.prepare_combat(0.05)
		coordinator.complete_committed_moves()
		if not _require(army.combat_order == TerrainArmy.CombatOrder.HOLD and army.cells == final_cells and plan.member_slot_map == final_slots, "The 60+40 deployment must remain stable for five simulated seconds at tick %d" % stable_tick): return
		if not _require(army._reserved_cells.is_empty() and coordinator.get_inflight_batches_for_formation(army).is_empty(), "The complete deployment must retain no movement claims"): return
	for slot: Vector2i in final_slots.values():
		var lease = coordinator.deployment_registry.owner_of(slot)
		if not _require(lease != null and lease.formation_id == army.team_id and lease.order_serial == plan.order_serial, "Every 60+40 final slot must retain its deployment lease"): return
	print("COMBAT MOVEMENT 100 PLATFORM ARRIVAL PASS: tick=", completed_tick)
	coordinator.unregister_formation(army)
	army.free()
	_army = null
	TerrainArmy.release_contact_source() # Headless teardown: release the shared contact rig before the post-quit frame (as f219902).
	quit(0)
