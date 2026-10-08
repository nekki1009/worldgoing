extends SceneTree
## Formal MOVE through a four-wide approach, a one-cell choke, and open ground.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Transit = preload("res://scripts/terrain_lab/formation_transit_planner.gd")
const MovePlan = preload("res://scripts/terrain_lab/combat_move_plan.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

var _army: TerrainArmy = null
var _coordinator: SiteCombatMovementCoordinator = null

func _initialize() -> void:
	call_deferred("_run")

func _finish(ok: bool, message: String) -> void:
	if is_instance_valid(_army):
		if _coordinator != null:
			_coordinator.unregister_formation(_army)
		_army.free()
	if ok:
		print(message)
		quit(0)
	else:
		push_error(message)
		quit(1)

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_finish(false, message)
	return false

func _run() -> void:
	var mountain := Helper.build_exact_60_platform_map()
	var mountain_path: Array[Vector2i] = Transit.build_macro_path(mountain.data, mountain.start, mountain.anchor)
	var mountain_members: Array[int] = [101, 102]
	var mountain_plan: CombatDeploymentPlan = Destination.plan_deployment(9, 1, mountain.data, mountain.anchor, mountain_path, mountain_members)
	if not _require(mountain_plan != null, "Mountain entry plan must be legal"): return
	var mountain_move: CombatMovePlan = MovePlan.new()
	mountain_move.macro_path = mountain_path
	mountain_move.member_observed_path_s[101] = float(mountain_path.size() - 1)
	mountain_move.member_transit_slots[101] = Vector2i(43, 29)
	mountain_move.member_path_s[101] = float(mountain_path.size() - 3)
	var cliff_side_target: Dictionary = Destination.resolve_member_target(mountain_move, mountain_plan, 101, Vector2i(44, 29))
	if not _require(cliff_side_target.kind == "transit" and cliff_side_target.target == Vector2i(43, 29), "A soldier beside the cliff must rejoin transit, not chase a deep final slot"): return
	var ramp_target: Dictionary = Destination.resolve_member_target(mountain_move, mountain_plan, 101, mountain.ramp)
	if not _require(ramp_target.kind == "platform", "A soldier on the real ramp may enter final deployment"): return
	Destination.update_ingress_gate(mountain_plan, {101: mountain_plan.get_slot_for_member(101)})
	var return_target: Dictionary = Destination.resolve_member_target(mountain_move, mountain_plan, 101, Vector2i(44, 29))
	if not _require(return_target.kind == "platform_return" and return_target.target == mountain_plan.get_slot_for_member(101), "A former entrant outside the footprint must return to its fixed final slot"): return
	var full_members: Array[int] = []
	for mid in range(200, 260):
		full_members.append(mid)
	var full_plan: CombatDeploymentPlan = Destination.plan_deployment(10, 2, mountain.data, mountain.anchor, mountain_path, full_members)
	if not _require(full_plan != null and full_plan.platform_slots.size() == 60, "Topology fixture must have sixty final slots"): return
	var hundred_members: Array[int] = []
	var hundred_cells: Dictionary = {}
	for i in range(100):
		var mid := 1100 + i
		hundred_members.append(mid)
		hundred_cells[mid] = Vector2i(30 + i % 10, 25 + floori(float(i) / 10.0))
	var officer_plan: CombatDeploymentPlan = Destination.plan_deployment(11, 3, mountain.data, mountain.anchor, mountain_path, hundred_members, null, [1100], hundred_cells)
	if not _require(officer_plan != null and officer_plan.is_platform_member(1100), "Rear commander keeps a platform role"): return
	if not _require(officer_plan.get_slot_for_member(1100) == Vector2i(45, 30), "The commander must own the accessible rear center slot fixed at command time"): return
	if not _require(officer_plan.settled_platform_member_ids.is_empty(), "Fixture must have unsettled ordinary platform members"): return
	var commander_move: CombatMovePlan = MovePlan.new()
	commander_move.destination_plan = officer_plan
	commander_move.macro_path = mountain_path
	commander_move.member_observed_path_s[1100] = 0.0
	commander_move.member_path_s[1100] = 1.0
	commander_move.member_transit_slots[1100] = mountain_path[1]
	var marching_target: Dictionary = Destination.resolve_member_target(commander_move, officer_plan, 1100, mountain_path[0])
	if not _require(marching_target.kind == "transit" and marching_target.target == mountain_path[1], "Commander follows the same transit target contract as other members"): return
	var hold_k: int = clampi(floori(officer_plan.queue_hold_path_s), 0, mountain_path.size() - 1)
	commander_move.member_observed_path_s[1100] = float(hold_k - 1)
	commander_move.member_path_s[1100] = float(hold_k)
	commander_move.member_transit_slots[1100] = mountain_path[hold_k]
	var waiting_target: Dictionary = Destination.resolve_member_target(commander_move, officer_plan, 1100, mountain_path[hold_k - 1])
	if not _require(waiting_target.kind == "transit" and waiting_target.target == mountain_path[hold_k], "Unsettled soldiers must not impose a commander-only entrance hold"): return
	for ordinary_id in officer_plan.pending_platform_member_ids:
		if ordinary_id != 1100:
			officer_plan.settled_platform_member_ids.append(ordinary_id)
	if not _require(officer_plan.settled_platform_member_ids.size() == officer_plan.platform_slots.size() - 1, "Fixture must observe all other platform slots settled"): return
	officer_plan.ever_admitted_platform_member_ids[1100] = true
	var released_target: Dictionary = Destination.resolve_member_target(commander_move, officer_plan, 1100, officer_plan.get_slot_for_member(1100) + Vector2i.LEFT)
	if not _require(released_target.target == Vector2i(45, 30) and released_target.kind in ["platform", "platform_return"], "An entered commander aims at its own final through the ordinary target contract"): return
	officer_plan.settled_platform_member_ids.clear()
	var queue_front: int = officer_plan.queue_member_ids[0]
	var queue_old_slot: Vector2i = officer_plan.get_slot_for_member(queue_front)
	var role_cells: Dictionary = hundred_cells.duplicate()
	role_cells[queue_front] = mountain.ramp + Vector2i.LEFT
	var role_move: CombatMovePlan = MovePlan.new()
	role_move.macro_path = mountain_path
	if not _require(Destination.exchange_front_queue_role(role_move, officer_plan, role_cells), "An unlocked queue soldier blocking the one-cell ramp must exchange with a rear ordinary platform soldier"): return
	var rear_partner: int = officer_plan.slot_owner_map[queue_old_slot]
	if not _require(officer_plan.is_platform_member(queue_front) and officer_plan.is_queue_member(rear_partner) and officer_plan.pending_platform_member_ids.size() == 60 and officer_plan.queue_member_ids.size() == 40 and role_cells[queue_front] == mountain.ramp + Vector2i.LEFT, "Choke role exchange must preserve sixty platform roles, forty queue roles, and all physical cells"): return
	var approach_plan: CombatDeploymentPlan = Destination.plan_deployment(14, 6, mountain.data, mountain.anchor, mountain_path, hundred_members, null, [1100], hundred_cells)
	if not _require(approach_plan != null, "Approach clearance fixture must plan"): return
	var approach_queue: int = approach_plan.queue_member_ids[0]
	var approach_rear := -1
	for candidate_id in approach_plan.pending_platform_member_ids:
		if approach_plan.slot_tactical_roles.get(approach_plan.get_slot_for_member(candidate_id), Types.TacticalSlotRole.FLEX) == Types.TacticalSlotRole.FLEX:
			approach_rear = candidate_id
			break
	if not _require(approach_rear >= 0, "Approach fixture needs a rear ordinary platform member"): return
	var approach_cells: Dictionary = {approach_queue: Vector2i(39, 30), approach_rear: Vector2i(38, 30)}
	var approach_move: CombatMovePlan = MovePlan.new()
	approach_move.macro_path = mountain_path
	if not _require(Destination.exchange_front_queue_role(approach_move, approach_plan, approach_cells) and approach_plan.is_platform_member(approach_queue) and approach_plan.is_queue_member(approach_rear) and approach_cells[approach_queue] == Vector2i(39, 30), "An ordinary queue soldier ahead of the last platform soldier on the approach must trade roles without changing physical cells"): return
	var early_member := 259
	var shallow_slot: Vector2i = full_plan.get_slot_for_member(early_member)
	var rebind_move: CombatMovePlan = MovePlan.new()
	rebind_move.macro_path = mountain_path
	rebind_move.planning_time_sec = 1.0
	full_plan.admitted_platform_member_ids = [early_member]
	full_plan.pending_platform_member_ids.erase(early_member)
	var early_cell: Vector2i = mountain.ingress
	var current_cells: Dictionary = {early_member: early_cell}
	if not _require(Destination.rebalance_provisional_slots(rebind_move, full_plan, current_cells, mountain.data, true), "An early entrant with a shallow provisional slot must be rebound deeper"): return
	var deeper_slot: Vector2i = full_plan.get_slot_for_member(early_member)
	if not _require(deeper_slot.x > shallow_slot.x and full_plan.slot_owner_map[deeper_slot] == early_member and current_cells[early_member] == early_cell, "Rebinding must preserve deep-to-shallow entry and leave physical cells unchanged"): return
	var entry_plan: CombatDeploymentPlan = Destination.plan_deployment(12, 4, mountain.data, mountain.anchor, mountain_path, full_members)
	if not _require(entry_plan != null, "Entry binding fixture must plan"): return
	var entry_move: CombatMovePlan = MovePlan.new()
	entry_move.macro_path = mountain_path
	entry_move.planning_time_sec = 1.0
	var entry_cells: Dictionary = {early_member: mountain.ramp}
	if not _require(Destination.late_bind_ingress_target(entry_move, entry_plan, entry_cells, mountain.data), "The first ramp arrival must take a reachable deep side slot"): return
	if not _require(entry_plan.get_slot_for_member(early_member).x == 50 and not mountain_path.has(entry_plan.get_slot_for_member(early_member)) and entry_cells[early_member] == mountain.ramp, "Pre-ingress binding must preserve the corridor and physical cells"): return
	var last_plan: CombatDeploymentPlan = Destination.plan_deployment(13, 5, mountain.data, mountain.anchor, mountain_path, full_members)
	if not _require(last_plan != null, "Last entry-lane fixture must plan"): return
	var last_move: CombatMovePlan = MovePlan.new()
	last_move.macro_path = mountain_path
	last_move.planning_time_sec = 1.0
	var slope_foot: Vector2i = mountain.ramp + Vector2i.LEFT
	var last_cells: Dictionary = {early_member: slope_foot}
	var fake_mid := 5000
	for slot in last_plan.platform_slots:
		if not mountain_path.has(slot):
			last_cells[fake_mid] = slot
			fake_mid += 1
	if not _require(Destination.late_bind_ingress_target(last_move, last_plan, last_cells, mountain.data), "The front soldier at the slope foot may take a reachable entry-lane slot after side slots fill"): return
	if not _require(mountain_path.has(last_plan.get_slot_for_member(early_member)) and last_cells[early_member] == slope_foot and mountain.data.can_step(slope_foot, mountain.ramp), "Last-slot binding must clear the single ramp without moving anyone directly"): return
	var small_data := Helper.build_flat_map(8, 8)
	var lane_plan := CombatDeploymentPlan.new()
	lane_plan.ingress_cell = Vector2i(2, 2)
	lane_plan.ingress_buffer_cells = [Vector2i(1, 2)]
	lane_plan.final_facing = Vector2i.RIGHT
	for cell in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3), Vector2i(4, 3)]:
		lane_plan.platform_footprint.append(cell)
		lane_plan.platform_slots.append(cell)
	for i in range(4):
		var mid := 20 + i
		var slot: Vector2i = lane_plan.platform_slots[i]
		lane_plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
		lane_plan.member_slot_map[mid] = slot
		lane_plan.slot_owner_map[slot] = mid
	var lane_move: CombatMovePlan = MovePlan.new()
	lane_move.macro_path = [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)]
	var lane_cells: Dictionary = {20: Vector2i(2, 2), 22: Vector2i(3, 3)}
	Destination.update_movement_phase(lane_move, lane_plan, lane_cells, small_data, 0.05)
	var lane_target: Dictionary = Destination.resolve_member_target(lane_move, lane_plan, 20, Vector2i(2, 2))
	if not _require(not lane_plan.is_slot_locked(20) and not lane_plan.settled_platform_member_ids.has(20) and lane_target.kind == "entry_waypoint" and lane_target.target == Vector2i(3, 2) and lane_cells[20] == Vector2i(2, 2), "An unreachable but vacant side final must keep the centerline provisional and offer only a physical one-step waypoint"): return
	var crossed_plan := CombatDeploymentPlan.new()
	for mid in [30, 31]:
		var slot := Vector2i(mid - 28, 2)
		crossed_plan.platform_slots.append(slot)
		crossed_plan.platform_footprint.append(slot)
		crossed_plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
		crossed_plan.member_slot_map[mid] = slot
		crossed_plan.slot_owner_map[slot] = mid
		crossed_plan.admitted_platform_member_ids.append(mid)
	var crossed_cells: Dictionary = {30: Vector2i(3, 2), 31: Vector2i(2, 2)}
	var crossed_move: CombatMovePlan = MovePlan.new()
	crossed_move.active_vacancy_chain_actors = [30]
	crossed_move.member_vacancy_chain_target[30] = Vector2i(2, 2)
	crossed_move.member_pending_proposal_id[30] = 7
	if not _require(not Destination.resolve_crossed_provisional_targets(crossed_move, crossed_plan, crossed_cells) and crossed_plan.get_slot_for_member(30) == Vector2i(2, 2) and crossed_move.member_crossed_swap_hold.has(30) and crossed_move.member_crossed_swap_hold.has(31),
		"An active vacancy chain must not exchange crossed ownership during an in-flight proposal"): return
	crossed_move.member_pending_proposal_id.erase(30)
	if not _require(Destination.resolve_crossed_provisional_targets(crossed_move, crossed_plan, crossed_cells) and crossed_plan.get_slot_for_member(30) == crossed_cells[30] and crossed_plan.get_slot_for_member(31) == crossed_cells[31] and crossed_plan.slot_owner_map[Vector2i(2, 2)] == 31 and crossed_plan.slot_owner_map[Vector2i(3, 2)] == 30 and crossed_cells[30] == Vector2i(3, 2), "Crossed FLEX targets must exchange ownership atomically without swapping physical cells"): return
	if not _require(crossed_move.member_vacancy_chain_target[30] == crossed_cells[30], "A crossed ownership repair must update active vacancy-chain intent so it can complete next tick"): return
	var queue_plan := CombatDeploymentPlan.new()
	queue_plan.approach_queue_slots = [Vector2i(1, 1), Vector2i(2, 1)]
	for mid in [50, 51]:
		var slot := Vector2i(mid - 49, 1)
		queue_plan.member_role_map[mid] = Types.CombatDestinationRole.APPROACH_QUEUE
		queue_plan.member_slot_map[mid] = slot
		queue_plan.slot_owner_map[slot] = mid
		queue_plan.queue_member_ids.append(mid)
	var queue_cells: Dictionary = {50: Vector2i(2, 1), 51: Vector2i(3, 1)}
	var queue_move: CombatMovePlan = MovePlan.new()
	Destination.update_movement_phase(queue_move, queue_plan, queue_cells)
	if not _require(queue_plan.get_slot_for_member(50) == Vector2i(2, 1) and queue_plan.get_slot_for_member(51) == Vector2i(1, 1) and queue_plan.is_slot_locked(50) and queue_cells[50] == Vector2i(2, 1), "Released queue member occupying another provisional final must gain that target without moving cells"): return
	var queue_vacancy_plan := CombatDeploymentPlan.new()
	queue_vacancy_plan.queue_released = true
	queue_vacancy_plan.approach_queue_slots = [Vector2i(2, 2), Vector2i(3, 2)]
	queue_vacancy_plan.queue_member_ids = [60, 61]
	queue_vacancy_plan.member_role_map = {60: Types.CombatDestinationRole.APPROACH_QUEUE, 61: Types.CombatDestinationRole.APPROACH_QUEUE}
	queue_vacancy_plan.member_slot_map = {60: Vector2i(2, 2), 61: Vector2i(3, 2)}
	queue_vacancy_plan.slot_owner_map = {Vector2i(2, 2): 60, Vector2i(3, 2): 61}
	queue_vacancy_plan.member_slot_locked[61] = true
	queue_vacancy_plan.settled_queue_member_ids = [61]
	var queue_vacancy_cells: Dictionary = {60: Vector2i(5, 2), 61: Vector2i(3, 2)}
	var queue_vacancy_move: CombatMovePlan = MovePlan.new()
	queue_vacancy_move.planning_time_sec = 2.0
	if not _require(Destination.recover_stalled_queue_slots(queue_vacancy_move, queue_vacancy_plan, queue_vacancy_cells, small_data) and queue_vacancy_plan.get_slot_for_member(61) == Vector2i(2, 2) and queue_vacancy_plan.get_slot_for_member(60) == Vector2i(3, 2) and queue_vacancy_cells[61] == Vector2i(3, 2), "Queue vacancy recovery must change only final targets, leaving the legal physical steps to Grid"): return
	var casualty_plan := CombatDeploymentPlan.new()
	casualty_plan.platform_slots = [Vector2i(2, 2), Vector2i(3, 2)]
	casualty_plan.approach_queue_slots = [Vector2i(1, 2)]
	casualty_plan.slot_tactical_roles[Vector2i(2, 2)] = Types.TacticalSlotRole.COMMANDER
	for mid in [40, 41, 42]:
		var slot := Vector2i(mid - 38, 2) if mid < 42 else Vector2i(1, 2)
		casualty_plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM if mid < 42 else Types.CombatDestinationRole.APPROACH_QUEUE
		casualty_plan.member_slot_map[mid] = slot
		casualty_plan.slot_owner_map[slot] = mid
	casualty_plan.queue_member_ids = [42]
	casualty_plan.remove_member(40)
	if not _require(not casualty_plan.slot_owner_map.has(Vector2i(2, 2)) and casualty_plan.is_queue_member(42), "Ordinary queue soldier must not inherit a dead commander's reserved tactical slot"): return
	if not _require(casualty_plan.rebind_commander_slot(41, Vector2i(2, 2)) and casualty_plan.slot_tactical_roles[Vector2i(3, 2)] == Types.TacticalSlotRole.COMMANDER and casualty_plan.is_platform_member(42) and casualty_plan.get_slot_for_member(42) == Vector2i(2, 2), "New commander keeps its physical final; old rear slot becomes ordinary before promotion"): return
	var small_plan := CombatDeploymentPlan.new()
	small_plan.ingress_cell = Vector2i(2, 2)
	small_plan.final_facing = Vector2i.RIGHT
	for cell in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)]:
		small_plan.platform_footprint.append(cell)
		small_plan.platform_slots.append(cell)
	for mid in [1, 2, 3]:
		var cell: Vector2i = small_plan.platform_slots[mid - 1]
		small_plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
		small_plan.member_slot_map[mid] = cell
		small_plan.slot_owner_map[cell] = mid
	small_plan.admitted_platform_member_ids = [2]
	small_plan.settled_platform_member_ids = [2]
	small_plan.pending_platform_member_ids = [1, 3]
	small_plan.member_slot_locked[2] = true
	var small_move: CombatMovePlan = MovePlan.new()
	small_move.macro_path = [Vector2i(2, 2), Vector2i(3, 2)]
	small_move.planning_time_sec = 2.0
	var small_cells: Dictionary = {2: Vector2i(3, 2)}
	if not _require(Destination.recover_stalled_platform_slots(small_move, small_plan, small_cells, small_data), "A locked FLEX blocker must yield one legal step into a vacant final cell after platform stall"): return
	if not _require(small_plan.get_slot_for_member(2) == Vector2i(4, 2) and small_plan.get_slot_for_member(3) == Vector2i(3, 2) and small_cells[2] == Vector2i(3, 2) and small_data.can_step(Vector2i(3, 2), Vector2i(4, 2)), "Vacancy recovery changes only target ownership; the later physical step belongs to Grid"): return
	var after_grid_cells: Dictionary = {2: Vector2i(4, 2)}
	small_plan.member_slot_locked[2] = true
	small_plan.settled_platform_member_ids = [2]
	small_move.planning_time_sec = 4.0
	if not _require(not Destination.recover_stalled_platform_slots(small_move, small_plan, after_grid_cells, small_data) and small_plan.get_slot_for_member(2) == Vector2i(4, 2), "A completed vacancy step must not be reversed into the cell it just freed"): return
	var chain_plan := CombatDeploymentPlan.new()
	chain_plan.ingress_cell = Vector2i(2, 3)
	chain_plan.final_facing = Vector2i.RIGHT
	for mid in range(1, 5):
		var cell := Vector2i(mid + 1, 3)
		chain_plan.platform_footprint.append(cell)
		chain_plan.platform_slots.append(cell)
		chain_plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
		chain_plan.member_slot_map[mid] = cell
		chain_plan.slot_owner_map[cell] = mid
	chain_plan.admitted_platform_member_ids = [2, 3]
	chain_plan.settled_platform_member_ids = [2, 3]
	chain_plan.pending_platform_member_ids = [1, 4]
	chain_plan.member_slot_locked[2] = true
	chain_plan.member_slot_locked[3] = true
	var chain_move: CombatMovePlan = MovePlan.new()
	chain_move.macro_path = [Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)]
	chain_move.planning_time_sec = 2.0
	var chain_cells: Dictionary = {2: Vector2i(3, 3), 3: Vector2i(4, 3)}
	var chain_epoch: int = chain_plan.assignment_epoch
	if not _require(not Destination.recover_stalled_platform_slots(chain_move, chain_plan, chain_cells, small_data, {Vector2i(2, 3): true, Vector2i(5, 3): true}) and chain_plan.assignment_epoch == chain_epoch and chain_move.active_vacancy_chain_actors.is_empty(),
		"A vacancy chain must wait when every physically empty tail has an in-flight Grid claim"): return
	chain_move.next_platform_recovery_time_sec = 0.0
	if not _require(Destination.recover_stalled_platform_slots(chain_move, chain_plan, chain_cells, small_data), "Vacancy recovery must traverse two locked FLEX slots toward the entrance"): return
	if not _require(chain_plan.get_slot_for_member(2) == Vector2i(4, 3) and chain_plan.get_slot_for_member(3) == Vector2i(5, 3) and chain_plan.get_slot_for_member(4) == Vector2i(3, 3) and chain_move.active_vacancy_chain_actors == [2, 3] and chain_cells[2] == Vector2i(3, 3) and chain_cells[3] == Vector2i(4, 3), "Vacancy chain reserves both legal physical steps and leaves cells untouched until Grid executes them"): return

	var fixture := Helper.build_bottleneck_map(Vector2i(36, 20), 10, 12, 17, 1)
	var data: TerrainData = fixture["data"]
	var corridor_start: Vector2i = fixture["corridor_start"]
	var corridor_end: Vector2i = fixture["corridor_end"]
	if not _require(Transit.detect_corridor_width(data, Vector2i(7, 10), Vector2i.RIGHT) == 4, "Approach must admit four lanes"): return
	if not _require(Transit.detect_corridor_width(data, corridor_start + Vector2i(2, 0), Vector2i.RIGHT) == 1, "Choke must have exactly one lane"): return
	if not _require(Transit.detect_corridor_width(data, Vector2i(26, 10), Vector2i.RIGHT) == 4, "Destination must reopen to four lanes"): return
	var span_path: Array[Vector2i] = []
	for x in range(4, 35):
		span_path.append(Vector2i(x, 10))
	var span_mids: Array[int] = []
	for mid in range(300, 312):
		span_mids.append(mid)
	var narrow_span_move: CombatMovePlan = MovePlan.new()
	narrow_span_move.macro_path = span_path
	narrow_span_move.macro_cursor = 18
	narrow_span_move.current_width = 4
	var narrow_cells: Dictionary = {}
	for i in range(span_mids.size()):
		var observed_k := 21 - i
		narrow_span_move.member_observed_path_s[span_mids[i]] = float(observed_k)
		narrow_cells[span_mids[i]] = span_path[observed_k]
	var narrow_soft := Transit.calculate_transit_slots(narrow_span_move, data, null, span_mids, narrow_cells)
	var gate_exit_k: int = corridor_end.x - span_path[0].x
	var narrow_rows: Array = Transit._get_static_row_sections(narrow_span_move, data, null)
	var narrow_unique := {}
	if not _require(narrow_soft.size() == 12 and narrow_span_move.member_row_map[span_mids[3]] == 0
		and narrow_span_move.member_lane_map[span_mids[3]] == 3 and float(narrow_span_move.member_path_s[span_mids[11]]) <= 14.0,
		"Nine physically crossed members may spread into the wide exit while the tail stays near the gate"): return
	for i in range(span_mids.size()):
		var mid: int = span_mids[i]
		var slot: Vector2i = narrow_soft[mid]
		var slot_k: int = floori(float(narrow_span_move.member_path_s[mid]))
		if not _require(not narrow_unique.has(slot) and slot_k >= 0 and slot_k < narrow_rows.size() and narrow_rows[slot_k].has(slot),
			"Every narrow-span soft slot must be unique and in its legal static row"): return
		narrow_unique[slot] = true
		if narrow_cells[mid].x < corridor_end.x and not _require(slot_k <= gate_exit_k,
			"A member physically short of the one-cell gate exit cannot receive a beyond-gate soft target"): return
	var wide_span_move: CombatMovePlan = MovePlan.new()
	wide_span_move.macro_path = span_path
	wide_span_move.macro_cursor = 26
	wide_span_move.current_width = 4
	var wide_cells: Dictionary = {}
	for i in range(span_mids.size()):
		var observed_k := 29 - i
		wide_span_move.member_observed_path_s[span_mids[i]] = float(observed_k)
		wide_cells[span_mids[i]] = span_path[observed_k]
	var wide_soft := Transit.calculate_transit_slots(wide_span_move, data, null, span_mids, wide_cells)
	if not _require(wide_soft.size() == 12 and wide_span_move.member_row_map[span_mids[3]] == 0 and wide_span_move.member_lane_map[span_mids[3]] == 3, "Soft slots may widen to four lanes after the tail clears the choke"): return

	_army = Helper.create_test_army(data, 1, 0, 4, Vector2i(4, 9))
	_coordinator = Coordinator.new()
	_coordinator.register_formation(_army)
	var order: Dictionary = _army.issue_combat_order(_army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(27, 10), -1, Vector2i.UP)
	if not _require(bool(order.get("ok", false)), "Formal choke MOVE must be accepted: " + str(order)): return
	var plan: CombatDeploymentPlan = _army.get_active_deployment_plan()
	if not _require(plan != null and plan.final_facing == Vector2i.UP, "Explicit final facing must survive planning"): return
	var near_final_mid: int = _army.combat_identity(3)
	var near_final_slot: Vector2i = plan.get_slot_for_member(near_final_mid)
	var near_final_cell: Vector2i = near_final_slot + Vector2i.DOWN
	if not _require(plan.platform_footprint.has(near_final_cell) and Destination.resolve_member_target(_army.get_active_move_plan(), plan, near_final_mid, near_final_cell).target == near_final_slot, "An admitted soldier beside its final must not return to a broad-footprint stage waypoint"): return

	var previous: Array[Vector2i] = _army.cells.duplicate()
	var entered_exit: Dictionary = {}
	var completed_tick := -1
	for tick in range(1600):
		_coordinator.combat_logic_tick(0.05)
		_army.prepare_combat(0.05)
		_coordinator.complete_committed_moves()
		if tick % 200 == 0 or tick == 1599:
			var active_move: CombatMovePlan = _army.get_active_move_plan()
			var members: Array[String] = []
			for i in range(4):
				var mid: int = _army.combat_identity(i)
				var resolved: Dictionary = Destination.resolve_member_target(active_move, plan, mid, _army.cells[i]) if active_move != null else {}
				members.append("%d:%s>%s target=%s/%s soft=%s obs=%.1f row=%d route=%d claim=%s direct=%s" % [mid, str(_army.cells[i]), str(plan.get_slot_for_member(mid)), str(resolved.get("target", Vector2i(-1, -1))), str(resolved.get("kind", "none")), str(active_move.member_transit_slots.get(mid, Vector2i(-1, -1))) if active_move != null else "none", float(active_move.member_observed_path_s.get(mid, -1.0)) if active_move != null else -1.0, int(active_move.member_row_map.get(mid, -1)) if active_move != null else -1, int(active_move.member_route_status.get(mid, -1)) if active_move != null else -1, str(_army.moving_to[i]), str(data.can_step(_army.cells[i], plan.get_slot_for_member(mid)))])
			print("CHOKE_FOUR_PROGRESS tick=", tick, " cursor=", active_move.macro_cursor if active_move != null else -1, " width=", active_move.current_width if active_move != null else -1, " phase=", active_move.phase if active_move != null else -1, " pending=", plan.pending_platform_member_ids.size(), " settled=", plan.settled_platform_member_ids.size(), " members=", members)
		var sources: Dictionary = {}
		var destinations: Dictionary = {}
		for i in range(4):
			var cell: Vector2i = _army.cells[i]
			if not _require(data.contains(cell) and data.is_walkable(cell), "Member left legal terrain at tick %d" % tick): return
			if not _require(not sources.has(cell), "Duplicate physical occupancy at tick %d" % tick): return
			sources[cell] = true
			if cell != previous[i]:
				if not _require(data.can_step(previous[i], cell), "Member skipped a legal edge at tick %d" % tick): return
				previous[i] = cell
			if cell.x > corridor_end.x:
				entered_exit[i] = true
			var claim: Vector2i = _army.moving_to[i]
			if claim != TerrainArmy.INVALID_CELL:
				if not _require(data.can_step(cell, claim), "In-flight claim must be an adjacent legal step at tick %d" % tick): return
				if not _require(not destinations.has(claim), "Duplicate in-flight destination at tick %d" % tick): return
				destinations[claim] = true
		if _army.combat_order == TerrainArmy.CombatOrder.HOLD:
			completed_tick = tick
			break
	if not _require(completed_tick >= 0, "All four members must finish the choke MOVE; status=" + _army.command_status): return
	if not _require(_army.command_status.begins_with("已抵達"), "HOLD must mean complete arrival, not route failure"): return
	if not _require(entered_exit.size() == 4, "Every member must physically traverse the choke and enter the open destination"): return
	if not _require(Destination.is_settled(plan, _army.get_active_members_occupancy()), "All members must occupy assigned final slots"): return
	var final_cells: Array[Vector2i] = _army.cells.duplicate()
	var reserved_before: Array[Vector2i] = _coordinator.deployment_registry.get_formation_reserved_slots(_army.team_id)
	if not _require(not reserved_before.is_empty(), "Completed deployment must retain its registered final-slot leases"): return
	for i in range(4):
		if not _require(_army.moving_to[i] == TerrainArmy.INVALID_CELL and _army.facing[i] == Vector2i.UP, "Final steps must finish and facing must be UP"): return
	for quiet_tick in range(100):
		_coordinator.combat_logic_tick(0.05)
		_army.prepare_combat(0.05)
		_coordinator.complete_committed_moves()
		if not _require(_army.combat_order == TerrainArmy.CombatOrder.HOLD and _army.cells == final_cells, "Arrival must stay physically stable for five simulation seconds at tick %d" % quiet_tick): return
		if not _require(_army.get_active_movement_claims().is_empty() and _army._combat_batch_members.is_empty() and _coordinator._inflight_batches.is_empty(), "Completed arrival must leave no motion claim or in-flight batch at tick %d" % quiet_tick): return
		for i in range(4):
			if not _require(_army.moving_to[i] == TerrainArmy.INVALID_CELL and _army.facing[i] == Vector2i.UP, "Completed member must remain idle and correctly oriented at tick %d" % quiet_tick): return
	var reserved_after: Array[Vector2i] = _coordinator.deployment_registry.get_formation_reserved_slots(_army.team_id)
	if not _require(reserved_after.size() == reserved_before.size(), "Completed deployment must retain final-slot lease count"): return
	for slot in reserved_before:
		if not _require(reserved_after.has(slot), "Completed deployment must retain every final-slot lease"): return
	_finish(true, "COMBAT MOVEMENT CHOKE ARRIVAL PASS: tick=" + str(completed_tick))
