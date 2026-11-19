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
	var plan: CombatDeploymentPlan = Destination.plan_deployment(1, 1, terrain, Vector2i(30, 17), path, roster, null, [1001], {}, Vector2i.RIGHT)
	if not _require(plan != null and plan.approach_bottlenecked == 0 and plan.platform_slots.size() == 100,
		"The fixture needs the actual hundred-person open compact deployment"): return
	var a := -1
	var b := -1
	for deep in plan.platform_slots:
		if deep.x > 29 or deep.y == 17 or int(plan.slot_tactical_roles.get(deep, -1)) != Types.TacticalSlotRole.FLEX:
			continue
		for near in plan.platform_slots:
			if near.x < 34 or near.y != deep.y or int(plan.slot_tactical_roles.get(near, -1)) != Types.TacticalSlotRole.FLEX:
				continue
			a = int(plan.slot_owner_map[deep])
			b = int(plan.slot_owner_map[near])
			break
		if a >= 0:
			break
	if not _require(a >= 0 and b >= 0, "Compatible deep and near-edge FLEX targets must exist"): return
	var old_a: Vector2i = plan.get_slot_for_member(a)
	var old_b: Vector2i = plan.get_slot_for_member(b)
	var cells: Dictionary = {a: Vector2i(43, old_b.y), b: old_a + Vector2i.RIGHT}
	plan.pending_platform_member_ids.clear()
	plan.admitted_platform_member_ids.clear()
	plan.settled_platform_member_ids.clear()
	for mid in roster:
		if int(plan.slot_tactical_roles.get(plan.get_slot_for_member(mid), -1)) == Types.TacticalSlotRole.COMMANDER:
			plan.pending_platform_member_ids.append(mid)
		else:
			plan.admitted_platform_member_ids.append(mid)
			if mid != a and mid != b and plan.get_slot_for_member(mid).y != old_a.y and plan.settled_platform_member_ids.size() < 60:
				cells[mid] = plan.get_slot_for_member(mid)
				plan.settled_platform_member_ids.append(mid)
				plan.member_slot_locked[mid] = true
	if not _require(plan.settled_platform_member_ids.size() == 60 and not cells.values().has(old_a) and not cells.values().has(old_b),
		"The deep and near-side final targets must both be vacant while 60 others are settled"): return
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	move.macro_path = path
	move.planning_time_sec = 2.0
	move.member_route_retry_count[a] = 5
	var occupied: Dictionary = {}
	for cell in cells.values():
		occupied[cell] = true
	var before: Dictionary = cells.duplicate()
	if not _require(Destination._recover_compact_exterior_slot(move, plan, cells, terrain, occupied),
		"A stalled, previously admitted outside soldier must take a reachable near-side vacant target when the compatible owner can reach its deep target; a=%s old=%s b=%s old=%s pending=%s admitted=%d" % [cells[a], old_a, cells[b], old_b, str(plan.pending_platform_member_ids), plan.admitted_platform_member_ids.size()]): return
	if not _require(plan.get_slot_for_member(a) == old_b and plan.get_slot_for_member(b) == old_a and cells == before,
		"The two target owners must exchange atomically without moving either physical cell"): return
	if not _require(int(plan.slot_owner_map[old_a]) == b and int(plan.slot_owner_map[old_b]) == a and move.assignment_epoch > 0,
		"The authoritative owner map and assignment epoch must agree"): return
	if not _require(plan.swap_member_slots(a, b), "The fixture must restore its provisional assignment"): return
	move.member_swap_cooldown_until_sec.clear()
	plan.admitted_platform_member_ids.erase(a)
	plan.pending_platform_member_ids.append(a)
	plan.ever_admitted_platform_member_ids[a] = true
	if not _require(Destination._recover_compact_exterior_slot(move, plan, cells, terrain, occupied) and plan.get_slot_for_member(a) == old_b and cells == before and plan.pending_platform_member_ids.has(a),
		"A former entrant beyond handoff must be eligible for target rebind without changing its physical admission state"): return
	if not _require(plan.swap_member_slots(a, b), "The fixture must restore targets after the returning entrant case"): return
	move.member_swap_cooldown_until_sec.clear()
	# A returning entrant can skirt the platform on the ingress side of its
	# routing handoff. Admission history, not that waypoint, distinguishes it
	# from the one soldier that has never entered.
	plan.centered_platform_handoff = Vector2i(44, 17)
	if not _require(cells[a].x < plan.get_platform_handoff_cell().x
		and Destination._never_crossed_platform_count(plan, cells) == 1
		and Destination._recover_compact_exterior_slot(move, plan, cells, terrain, occupied)
		and plan.get_slot_for_member(a) == old_b and cells == before,
		"A previously admitted exterior soldier remains eligible behind the handoff while the genuinely new entrant still counts pending"): return
	if not _require(plan.swap_member_slots(a, b), "The fixture must restore targets after ingress-side return"): return
	move.member_swap_cooldown_until_sec.clear()
	plan.set_approach_bottlenecked(true, Vector2i(24, 17))
	if not _require(cells[a].x > plan.approach_last_bottleneck_cell.x,
		"The returning entrant must already be physically beyond the approach choke"): return
	var other_pending: int = plan.pending_platform_member_ids[0]
	plan.pending_platform_member_ids.erase(other_pending)
	plan.ever_admitted_platform_member_ids.erase(a)
	if not _require(Destination._never_crossed_platform_count(plan, cells) == 1
		and not Destination._recover_compact_exterior_slot(move, plan, cells, terrain, occupied) and plan.get_slot_for_member(a) == old_a,
		"A never-admitted pending soldier must not borrow the former-entrant exception, even beyond a choke"): return
	plan.pending_platform_member_ids.erase(a)
	plan.pending_platform_member_ids.append(other_pending)
	plan.admitted_platform_member_ids.append(a)
	plan.ever_admitted_platform_member_ids[a] = true
	move.member_pending_proposal_id[b] = 7
	if not _require(not Destination._recover_compact_exterior_slot(move, plan, cells, terrain, occupied) and plan.get_slot_for_member(a) == old_a,
		"An in-flight owner must retain its authoritative target"): return
	move.member_pending_proposal_id.clear()
	var beyond_choke_before: Dictionary = cells.duplicate()
	if not _require(Destination._recover_compact_exterior_slot(move, plan, cells, terrain, occupied)
		and plan.get_slot_for_member(a) == old_b and plan.get_slot_for_member(b) == old_a and cells == beyond_choke_before
		and int(plan.slot_owner_map[old_a]) == b and int(plan.slot_owner_map[old_b]) == a,
		"A previously admitted soldier beyond the choke must exchange only reachable target ownership, without moving either physical cell"): return
	print("COMBAT MOVEMENT COMPACT EXTERIOR REBIND PASS")
	quit(0)
