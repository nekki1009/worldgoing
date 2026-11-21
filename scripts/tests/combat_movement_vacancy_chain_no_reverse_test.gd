extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
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
	var terrain := Helper.build_flat_map(18, 7)
	var plan := CombatDeploymentPlan.new()
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	plan.ingress_cell = Vector2i(0, 3)
	var actors: Array[int] = []
	var forward: Array[Vector2i] = []
	var backward: Array[Vector2i] = []
	var cells: Dictionary = {}
	for i in range(10):
		var mid := 100 + i
		var slot := Vector2i(i, 3)
		actors.append(mid)
		forward.append(Vector2i(i + 1, 3))
		backward.append(slot)
		plan.platform_slots.append(slot)
		plan.platform_footprint.append(slot)
		plan.member_slot_map[mid] = slot
		plan.slot_owner_map[slot] = mid
		plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
		plan.slot_tactical_roles[slot] = Types.TacticalSlotRole.FLEX
		plan.admitted_platform_member_ids.append(mid)
		plan.settled_platform_member_ids.append(mid)
		plan.member_slot_locked[mid] = true
		cells[mid] = slot
	var waiting := 999
	var vacancy := Vector2i(10, 3)
	plan.platform_slots.append(vacancy)
	plan.platform_footprint.append(vacancy)
	plan.member_slot_map[waiting] = vacancy
	plan.slot_owner_map[vacancy] = waiting
	plan.member_role_map[waiting] = Types.CombatDestinationRole.PLATFORM
	plan.slot_tactical_roles[vacancy] = Types.TacticalSlotRole.FLEX
	plan.pending_platform_member_ids.append(waiting)
	cells[waiting] = Vector2i(15, 3)
	var independent := 200
	var independent_final := Vector2i(12, 3)
	plan.platform_slots.append(independent_final)
	plan.platform_footprint.append(Vector2i(11, 3))
	plan.platform_footprint.append(independent_final)
	plan.member_slot_map[independent] = independent_final
	plan.slot_owner_map[independent_final] = independent
	plan.member_role_map[independent] = Types.CombatDestinationRole.PLATFORM
	plan.slot_tactical_roles[independent_final] = Types.TacticalSlotRole.FLEX
	plan.admitted_platform_member_ids.append(independent)
	cells[independent] = Vector2i(11, 3)
	move.platform_settled_highwater = 10
	var before: Dictionary = cells.duplicate()
	if not _require(Destination._rotate_platform_vacancy_chain(move, plan, actors, forward).size() == 11 and cells == before,
		"A ten-person chain may rotate only final ownership, with no physical movement"): return
	for i in range(actors.size() - 1, -1, -1):
		var actor: int = actors[i]
		var step: Vector2i = forward[i]
		if not _require(terrain.can_step(cells[actor], step), "Each simulated chain completion must be one legal Grid edge"): return
		cells[actor] = step
	Destination.update_movement_phase(move, plan, cells, null, 0.05)
	var after_forward: Dictionary = cells.duplicate()
	if not _require(plan.settled_platform_member_ids.size() == 10 and move.platform_settled_highwater == 10,
		"Completion of the same ten actors must not count as new platform capacity progress"): return
	if not _require(Destination._rotate_platform_vacancy_chain(move, plan, actors, backward).is_empty() and cells == after_forward and plan.get_slot_for_member(actors[0]) == forward[0],
		"The same vacancy must not immediately travel backwards through the ten actors"): return
	if not _require(terrain.can_step(cells[independent], independent_final), "Independent progress must still use one legal physical edge"): return
	cells[independent] = independent_final
	Destination.update_movement_phase(move, plan, cells, null, 0.05)
	var after_progress: Dictionary = cells.duplicate()
	if not _require(move.platform_settled_highwater == 11 and move.member_recovery_vacated_cell.is_empty(),
		"A newly settled independent soldier must reopen future recovery choices"): return
	if not _require(Destination._rotate_platform_vacancy_chain(move, plan, actors, backward).size() == 11 and cells == after_progress,
		"After independent physical progress, the target planner may reconsider the old chain without teleporting"): return
	var owners: Dictionary = {}
	for mid in plan.member_slot_map.keys():
		var slot: Vector2i = plan.get_slot_for_member(mid)
		if not _require(not owners.has(slot) and int(plan.slot_owner_map.get(slot, -1)) == mid,
			"Both rotations must preserve one-to-one authoritative final ownership"): return
		owners[slot] = true
	print("COMBAT MOVEMENT VACANCY CHAIN NO REVERSE PASS")
	quit(0)
