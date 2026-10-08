extends SceneTree

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
	var plan := CombatDeploymentPlan.new()
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	var a := 1146
	var b := 1153
	var a_slot := Vector2i(47, 24)
	var b_slot := Vector2i(47, 25)
	var cells: Dictionary = {a: b_slot, b: a_slot}
	for mid in [a, b]:
		plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
		plan.admitted_platform_member_ids.append(mid)
	plan.member_slot_map[a] = a_slot
	plan.member_slot_map[b] = b_slot
	plan.slot_owner_map[a_slot] = a
	plan.slot_owner_map[b_slot] = b
	plan.platform_slots = [a_slot, b_slot]
	plan.platform_footprint = [a_slot, b_slot]
	plan.slot_tactical_roles[a_slot] = Types.TacticalSlotRole.FLEX
	plan.slot_tactical_roles[b_slot] = Types.TacticalSlotRole.FLEX
	var original_cells: Dictionary = cells.duplicate()
	move.member_pending_proposal_id[a] = 1
	move.member_pending_proposal_id[b] = 2
	if not _require(not Destination.resolve_crossed_provisional_targets(move, plan, cells) and move.member_crossed_swap_hold.has(a) and move.member_crossed_swap_hold.has(b) and plan.get_slot_for_member(a) == a_slot,
		"A crossed pair with in-flight proposals must stop re-proposing without mutating authoritative slots"): return
	var held_a: Dictionary = Destination.resolve_member_target(move, plan, a, cells[a])
	var held_b: Dictionary = Destination.resolve_member_target(move, plan, b, cells[b])
	if not _require(held_a.get("target") == cells[a] and held_b.get("target") == cells[b] and cells == original_cells,
		"In-flight crossed soldiers must wait at their physical cells without teleporting"): return
	move.member_pending_proposal_id.clear()
	if not _require(Destination.resolve_crossed_provisional_targets(move, plan, cells) and plan.get_slot_for_member(a) == cells[a] and plan.get_slot_for_member(b) == cells[b] and cells == original_cells,
		"Once proposals finish, compatible final ownership must exchange atomically"): return
	if not _require(int(plan.slot_owner_map[cells[a]]) == a and int(plan.slot_owner_map[cells[b]]) == b and not move.member_crossed_swap_hold.has(a) and not move.member_crossed_swap_hold.has(b),
		"Slot owner map and transient crossed hold must remain consistent"): return
	# A soldier that was settled earlier can be displaced by an ordinary Grid
	# step. Only the exact crossed pair may release stale locks; an unrelated
	# displaced soldier must retain its committed slot.
	if not _require(plan.swap_member_slots(a, b), "The fixture must restore crossed provisional targets"): return
	var unrelated := 1154
	var unrelated_slot := Vector2i(49, 24)
	cells[unrelated] = Vector2i(50, 24)
	plan.member_role_map[unrelated] = Types.CombatDestinationRole.PLATFORM
	plan.admitted_platform_member_ids.append(unrelated)
	plan.member_slot_map[unrelated] = unrelated_slot
	plan.slot_owner_map[unrelated_slot] = unrelated
	plan.slot_tactical_roles[unrelated_slot] = Types.TacticalSlotRole.FLEX
	plan.platform_slots.append(unrelated_slot)
	plan.platform_footprint.append(cells[unrelated])
	plan.member_slot_locked[unrelated] = true
	plan.settled_platform_member_ids.append(unrelated)
	plan.member_slot_locked[b] = true
	plan.settled_platform_member_ids.append(b)
	var displaced_cells: Dictionary = cells.duplicate()
	if not _require(Destination.resolve_crossed_provisional_targets(move, plan, cells) and plan.get_slot_for_member(a) == cells[a] and plan.get_slot_for_member(b) == cells[b] and cells == displaced_cells,
		"A stale lock in an exact FLEX two-cycle must resolve by target ownership alone"): return
	if not _require(plan.is_slot_locked(unrelated) and plan.get_slot_for_member(unrelated) == unrelated_slot and not plan.is_slot_locked(b),
		"A displaced soldier outside the exact two-cycle must keep its committed lock"): return
	print("COMBAT MOVEMENT CROSSED TARGET HOLD PASS")
	quit(0)
