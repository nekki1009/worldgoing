extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Transit = preload("res://scripts/terrain_lab/formation_transit_planner.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false

func _run() -> void:
	var terrain := Helper.build_flat_map(70, 70)
	var path: Array[Vector2i] = Transit.build_macro_path(terrain, Vector2i(5, 17), Vector2i(30, 17))
	var roster: Array[int] = []
	for i in range(100):
		roster.append(1001 + i)
	var officers: Array[int] = [1001]
	var plan: CombatDeploymentPlan = Destination.plan_deployment(1, 1, terrain, Vector2i(30, 17), path, roster, null, officers, {}, Vector2i.RIGHT)
	if not _require(plan != null and plan.approach_bottlenecked == 0 and plan.platform_slots.size() == 100,
		"The regression needs the real centered open-ground hundred-slot plan"): return
	var a := -1
	var b := -1
	for slot in plan.platform_slots:
		if slot.x < 30 or slot.y == 17 or int(plan.slot_tactical_roles.get(slot, -1)) != Types.TacticalSlotRole.FLEX:
			continue
		if a < 0:
			a = int(plan.slot_owner_map[slot])
		elif b < 0:
			b = int(plan.slot_owner_map[slot])
			break
	if not _require(a >= 0 and b >= 0, "Two compatible off-lane ordinary slots must exist"): return
	var a_final: Vector2i = plan.get_slot_for_member(a)
	var b_final: Vector2i = plan.get_slot_for_member(b)
	var cells: Dictionary = {a: b_final, b: Vector2i(42, 25)}
	plan.pending_platform_member_ids.clear()
	for mid in roster:
		if int(plan.slot_tactical_roles.get(plan.get_slot_for_member(mid), -1)) == Types.TacticalSlotRole.COMMANDER:
			plan.pending_platform_member_ids.append(mid)
			break
	plan.admitted_platform_member_ids.assign([a, b])
	plan.settled_platform_member_ids.clear()
	for mid in roster:
		if mid == a or mid == b or plan.pending_platform_member_ids.has(mid) or plan.get_slot_for_member(mid).y == 17 or plan.settled_platform_member_ids.size() >= 60:
			continue
		var slot: Vector2i = plan.get_slot_for_member(mid)
		cells[mid] = slot
		plan.settled_platform_member_ids.append(mid)
		plan.member_slot_locked[mid] = true
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	move.macro_path = path
	move.planning_time_sec = 2.0
	var before_cells: Dictionary = cells.duplicate()
	if not _require(plan.settled_platform_member_ids.size() == 60 and plan.pending_platform_member_ids.size() == 1 and b_final != a_final,
		"The exchange must start below the ordinary 88-of-100 late gate; settled=%d pending=%d a=%s b=%s" % [plan.settled_platform_member_ids.size(), plan.pending_platform_member_ids.size(), a_final, b_final]): return
	if not _require(Destination.late_bind_ingress_target(move, plan, cells, terrain),
		"After a real compact-platform stall, the occupant of another unlocked FLEX final must exchange ownership"): return
	if not _require(plan.get_slot_for_member(a) == b_final and plan.get_slot_for_member(b) == a_final and cells == before_cells,
		"The exchange must settle the occupant by changing only target ownership, never physical cells"): return
	if not _require(int(plan.slot_owner_map[b_final]) == a and int(plan.slot_owner_map[a_final]) == b,
		"Both authoritative slot-owner entries must change atomically"): return
	if not _require(plan.swap_member_slots(a, b), "The focused test must restore its two provisional owners"): return
	plan.member_slot_locked[b] = true
	if not _require(not Destination.late_bind_ingress_target(move, plan, cells, terrain) and plan.get_slot_for_member(a) == a_final,
		"A locked slot owner must never be taken by compact early exchange"): return
	plan.member_slot_locked.erase(b)
	plan.set_approach_bottlenecked(true, Vector2i(24, 17))
	move.planning_time_sec = 3.0 # Allow the prior target-exchange cooldown to expire.
	if not _require(Destination.late_bind_ingress_target(move, plan, cells, terrain) and plan.get_slot_for_member(a) == b_final and cells == before_cells,
		"An off-lane occupied final may exchange target ownership even when the approach has a bottleneck"): return
	var commander: int = officers[0]
	var commander_final: Vector2i = plan.get_slot_for_member(commander)
	var ordinary_final: Vector2i = plan.get_slot_for_member(b)
	if not _require(plan.swap_member_slots(commander, b), "A commander and ordinary platform member must be eligible for the same target exchange"): return
	if not _require(plan.get_slot_for_member(commander) == ordinary_final and plan.get_slot_for_member(b) == commander_final and int(plan.slot_tactical_roles[ordinary_final]) == Types.TacticalSlotRole.COMMANDER and int(plan.slot_tactical_roles[commander_final]) == Types.TacticalSlotRole.FLEX and cells == before_cells,
		"Target exchange must carry commander identity without changing either physical cell"): return
	# An admitted soldier may stand on a pending ally's final. Preserve that
	# assignment until the ally physically enters the platform, then exchange.
	var pending_plan: CombatDeploymentPlan = Destination.plan_deployment(3, 3, terrain, Vector2i(30, 17), path, roster, null, officers, {}, Vector2i.RIGHT)
	if not _require(pending_plan != null, "The pending-owner exchange needs a real deployment plan"): return
	var pending_owner: int = officers[0]
	var pending_final: Vector2i = pending_plan.get_slot_for_member(pending_owner)
	var admitted_ally := -1
	for slot in pending_plan.platform_slots:
		if not path.has(slot) and int(pending_plan.slot_tactical_roles.get(slot, -1)) == Types.TacticalSlotRole.FLEX:
			admitted_ally = int(pending_plan.slot_owner_map[slot])
			break
	if not _require(admitted_ally >= 0 and admitted_ally != pending_owner, "The pending-owner fixture needs an ordinary compatible ally"): return
	var ally_final: Vector2i = pending_plan.get_slot_for_member(admitted_ally)
	var entry_inside := Vector2i(-1, -1)
	var entry_outside := Vector2i(-1, -1)
	for candidate in pending_plan.platform_footprint:
		if pending_plan.slot_owner_map.has(candidate):
			continue
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var outside: Vector2i = candidate + direction
			if not pending_plan.platform_footprint.has(outside) and terrain.can_step(outside, candidate):
				entry_inside = candidate
				entry_outside = outside
				break
		if entry_inside != Vector2i(-1, -1):
			break
	if not _require(entry_inside != Vector2i(-1, -1), "A pending owner needs one legal physical edge into a free footprint cell"): return
	var pending_cells: Dictionary = {admitted_ally: pending_final, pending_owner: entry_outside}
	var admitted_members: Array[int] = [admitted_ally]
	for mid in roster:
		if mid == admitted_ally or mid == pending_owner:
			continue
		pending_cells[mid] = pending_plan.get_slot_for_member(mid)
		admitted_members.append(mid)
		pending_plan.member_slot_locked[mid] = true
		pending_plan.settled_platform_member_ids.append(mid)
	var physical_before: Dictionary = pending_cells.duplicate()
	pending_plan.admitted_platform_member_ids.assign(admitted_members)
	pending_plan.pending_platform_member_ids.assign([pending_owner])
	var admitted_before: Array[int] = pending_plan.admitted_platform_member_ids.duplicate()
	var pending_before: Array[int] = pending_plan.pending_platform_member_ids.duplicate()
	var roles_before: Dictionary = pending_plan.member_role_map.duplicate()
	var assignment_before: int = pending_plan.assignment_epoch
	var pending_move := CombatMovePlan.new()
	pending_move.destination_plan = pending_plan
	pending_move.macro_path = path
	pending_move.planning_time_sec = 2.0
	if not _require(pending_final in pending_plan.platform_footprint and not pending_plan.is_slot_locked(admitted_ally) and not pending_plan.is_slot_locked(pending_owner) and int(pending_plan.slot_tactical_roles[pending_final]) == Types.TacticalSlotRole.COMMANDER and int(pending_plan.slot_tactical_roles[ally_final]) == Types.TacticalSlotRole.FLEX,
		"The admitted ally must stand on an unlocked, not-yet-admitted commander-owned final"): return
	if not _require(not Destination.late_bind_ingress_target(pending_move, pending_plan, pending_cells, terrain)
		and pending_cells == physical_before and pending_plan.assignment_epoch == assignment_before
		and pending_plan.get_slot_for_member(admitted_ally) == ally_final and pending_plan.get_slot_for_member(pending_owner) == pending_final,
		"Standing on a pending owner's target must not exchange its ownership before physical admission"): return
	if not _require(pending_plan.admitted_platform_member_ids == admitted_before and pending_plan.pending_platform_member_ids == pending_before and pending_plan.member_role_map == roles_before and int(pending_plan.slot_owner_map[pending_final]) == pending_owner and int(pending_plan.slot_owner_map[ally_final]) == admitted_ally and int(pending_plan.slot_tactical_roles[pending_final]) == Types.TacticalSlotRole.COMMANDER and int(pending_plan.slot_tactical_roles[ally_final]) == Types.TacticalSlotRole.FLEX,
		"The pending phase must preserve admission, both original owners and their tactical identity markers"): return
	# B walks one legal cell into the footprint; the canonical admission gate,
	# rather than the target exchange, records this change of status.
	pending_cells[pending_owner] = entry_inside
	Destination.update_ingress_gate(pending_plan, pending_cells)
	if not _require(pending_plan.admitted_platform_member_ids.has(pending_owner) and not pending_plan.pending_platform_member_ids.has(pending_owner) and pending_plan.assignment_epoch == assignment_before,
		"Only the real footprint entry may admit the former pending owner"): return
	var admitted_physical_before: Dictionary = pending_cells.duplicate()
	var admitted_after_entry: Array[int] = pending_plan.admitted_platform_member_ids.duplicate()
	var pending_after_entry: Array[int] = pending_plan.pending_platform_member_ids.duplicate()
	if not _require(Destination.late_bind_ingress_target(pending_move, pending_plan, pending_cells, terrain),
		"Two admitted platform members must exchange occupied target ownership immediately"): return
	if not _require(pending_cells == admitted_physical_before and pending_plan.assignment_epoch == assignment_before + 1 and pending_plan.get_slot_for_member(admitted_ally) == pending_final and pending_plan.get_slot_for_member(pending_owner) == ally_final,
		"Admission enables one target exchange without moving either member during the exchange"): return
	if not _require(int(pending_plan.slot_owner_map[pending_final]) == admitted_ally and int(pending_plan.slot_owner_map[ally_final]) == pending_owner and int(pending_plan.slot_tactical_roles[pending_final]) == Types.TacticalSlotRole.FLEX and int(pending_plan.slot_tactical_roles[ally_final]) == Types.TacticalSlotRole.COMMANDER,
		"The owner map and tactical identity markers must follow their members"): return
	if not _require(pending_plan.admitted_platform_member_ids == admitted_after_entry and pending_plan.pending_platform_member_ids == pending_after_entry and pending_plan.member_role_map == roles_before,
		"The target exchange must preserve the admission recorded by the physical entry"): return
	var pending_owners_seen: Dictionary = {}
	for mid in pending_plan.member_slot_map.keys():
		var slot: Vector2i = pending_plan.get_slot_for_member(mid)
		if not _require(not pending_owners_seen.has(slot) and int(pending_plan.slot_owner_map.get(slot, -1)) == mid, "Every final slot must still have exactly one authoritative owner"): return
		pending_owners_seen[slot] = true
	if not _require(Destination.resolve_member_target(pending_move, pending_plan, admitted_ally, pending_final).get("kind") == "settled",
		"The admitted ally must resolve directly to the final under its feet"): return
	var lane_plan: CombatDeploymentPlan = Destination.plan_deployment(2, 2, terrain, Vector2i(30, 17), path, roster, null, officers, {}, Vector2i.RIGHT)
	var lane := Vector2i(-1, -1)
	for slot in lane_plan.platform_slots:
		if path.has(slot):
			lane = slot
			break
	if not _require(lane != Vector2i(-1, -1), "The platform must have an occupied-route final to exercise entrance ownership"): return
	var lane_owner: int = int(lane_plan.slot_owner_map[lane])
	var lane_occupant: int = a if a != lane_owner else b
	var lane_cells: Dictionary = {lane_occupant: lane, lane_owner: Vector2i(42, 25)}
	lane_plan.admitted_platform_member_ids.assign([lane_occupant, lane_owner])
	lane_plan.pending_platform_member_ids.assign(roster)
	var lane_move := CombatMovePlan.new()
	lane_move.destination_plan = lane_plan
	lane_move.macro_path = path
	lane_move.planning_time_sec = 2.0
	if not _require(Destination.late_bind_ingress_target(lane_move, lane_plan, lane_cells, terrain)
		and lane_plan.get_slot_for_member(lane_occupant) == lane and lane_cells[lane_occupant] == lane,
		"An admitted friendly already on an unlocked entrance final must claim its target cell even with many pending members"): return
	var admitted_target: Dictionary = Destination.resolve_member_target(lane_move, lane_plan, lane_occupant, lane)
	if not _require(admitted_target.get("kind") == "settled" and not lane_move.member_entry_hold.has(lane_occupant),
		"Entrance ownership must produce a real settled target, not a permanent self-target ingress wait"): return
	if not _check_pending_depth_guard(terrain): return
	print("COMBAT MOVEMENT COMPACT TARGET EXCHANGE PASS")
	quit(0)

func _check_pending_depth_guard(terrain: Object) -> bool:
	var plan := CombatDeploymentPlan.new()
	plan.ingress_cell = Vector2i(5, 5)
	plan.ingress_buffer_cells.assign([Vector2i(5, 7), Vector2i(5, 6)])
	plan.set_approach_bottlenecked(true, Vector2i(5, 6))
	plan.final_facing = Vector2i.UP
	plan.platform_footprint.assign([Vector2i(5, 5), Vector2i(4, 5), Vector2i(3, 5),
		Vector2i(3, 4), Vector2i(3, 3), Vector2i(3, 2), Vector2i(4, 4)])
	var deep := Vector2i(3, 2)
	var shallow := Vector2i(4, 4)
	var blocker_final := Vector2i(3, 3)
	plan.platform_slots.assign([deep, shallow, blocker_final])
	for mid in [1, 2, 3]:
		plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
	plan.member_slot_map = {1: deep, 2: shallow, 3: blocker_final}
	plan.slot_owner_map = {deep: 1, shallow: 2, blocker_final: 3}
	plan.admitted_platform_member_ids.assign([1, 3])
	plan.pending_platform_member_ids.assign([2])
	plan.member_slot_locked[3] = true
	var path: Array[Vector2i] = [Vector2i(5, 7), Vector2i(5, 6), Vector2i(5, 5),
		Vector2i(4, 5), Vector2i(3, 5), Vector2i(3, 4), blocker_final, deep]
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	move.macro_path = path
	move.planning_time_sec = 2.0
	var cells: Dictionary = {1: plan.ingress_cell, 2: Vector2i(5, 7), 3: deep}
	var before: Dictionary = cells.duplicate()
	if not _require(not Destination.late_bind_ingress_target(move, plan, cells, terrain)
		and plan.get_slot_for_member(1) == deep and plan.get_slot_for_member(2) == shallow and cells == before,
		"A pending member must not inherit a deeper final from an admitted entrant"): return false
	if not _require(plan.swap_member_slots(1, 2), "The fixture must reverse the provisional targets"): return false
	cells[3] = shallow # Block the entrant's own target; the deeper target remains free.
	before = cells.duplicate()
	if not _require(Destination.late_bind_ingress_target(move, plan, cells, terrain)
		and plan.get_slot_for_member(1) == deep and plan.get_slot_for_member(2) == shallow and cells == before,
		"The same entrant may exchange targets when the pending owner gains a shallower final"): return false
	plan.set_approach_bottlenecked(false)
	move.member_swap_cooldown_until_sec.clear()
	cells[3] = deep
	before = cells.duplicate()
	if not _require(Destination.late_bind_ingress_target(move, plan, cells, terrain)
		and plan.get_slot_for_member(1) == shallow and plan.get_slot_for_member(2) == deep and cells == before,
		"An open approach may exchange reachable targets without the narrow-route depth guard"): return false
	return true
