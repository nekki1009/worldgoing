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

func _unrelated_vacancy_must_not_rotate() -> bool:
	var terrain := Helper.build_flat_map(14, 6)
	var plan := CombatDeploymentPlan.new()
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	plan.ingress_cell = Vector2i(0, 2)
	var cells: Dictionary = {99: Vector2i(7, 2), 98: Vector2i(13, 3)}
	var occupied: Dictionary = {Vector2i(7, 2): true, Vector2i(13, 3): true}
	var next_id := 1
	for x in range(8, 11):
		for y in range(1, 4):
			var slot := Vector2i(x, y)
			var mid: int = 99 if slot == Vector2i(10, 2) else 98 if slot == Vector2i(8, 3) else next_id
			if mid == next_id:
				next_id += 1
			plan.platform_slots.append(slot)
			plan.member_slot_map[mid] = slot
			plan.slot_owner_map[slot] = mid
			plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
			plan.slot_tactical_roles[slot] = Types.TacticalSlotRole.FRONT if x == 9 else Types.TacticalSlotRole.FLEX
			plan.admitted_platform_member_ids.append(mid)
			if mid != 99 and mid != 98:
				cells[mid] = slot
				occupied[slot] = true
				plan.settled_platform_member_ids.append(mid)
				plan.member_slot_locked[mid] = true
	var original_slots: Dictionary = plan.member_slot_map.duplicate()
	var original_cells: Dictionary = cells.duplicate()
	return _require(not Destination._recover_broad_final_vacancy(move, plan, cells, terrain, occupied)
		and plan.member_slot_map == original_slots and cells == original_cells and move.active_vacancy_chain_actors.is_empty(),
		"A reachable but unrelated vacancy must not rotate a settled chain when the waiting owner's desired final is isolated by a tactical divider")

func _run() -> void:
	if not _unrelated_vacancy_must_not_rotate(): return
	var terrain := Helper.build_flat_map(14, 6)
	var plan := CombatDeploymentPlan.new()
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	plan.ingress_cell = Vector2i(0, 2)
	var waiting := 99
	var vacancy := Vector2i(10, 2)
	var cells: Dictionary = {waiting: Vector2i(7, 2)}
	var occupied: Dictionary = {Vector2i(7, 2): true}
	var next_id := 1
	for x in range(8, 11):
		for y in range(1, 4):
			var slot := Vector2i(x, y)
			var mid: int = waiting if slot == vacancy else next_id
			if mid == next_id:
				next_id += 1
			plan.platform_slots.append(slot)
			plan.member_slot_map[mid] = slot
			plan.slot_owner_map[slot] = mid
			plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
			plan.slot_tactical_roles[slot] = Types.TacticalSlotRole.FLEX
			plan.admitted_platform_member_ids.append(mid)
			if mid != waiting:
				cells[mid] = slot
				occupied[slot] = true
				plan.settled_platform_member_ids.append(mid)
				plan.member_slot_locked[mid] = true
	var original_cells: Dictionary = cells.duplicate()
	var original_epoch: int = plan.assignment_epoch
	if not _require(not Destination._recover_broad_final_vacancy(move, plan, cells, terrain, occupied, {vacancy: true}) and plan.assignment_epoch == original_epoch and cells == original_cells and move.active_vacancy_chain_actors.is_empty(),
		"An in-flight claim on the vacant final must defer broad vacancy rotation until Grid releases the tail"): return
	if not _require(Destination._recover_broad_final_vacancy(move, plan, cells, terrain, occupied),
		"A compact final block eight cells beyond ingress must open a locked FLEX wall toward its vacant slot"): return
	if not _require(cells == original_cells and plan.assignment_epoch == original_epoch + 1 and plan.get_slot_for_member(waiting) == Vector2i(8, 2),
		"Vacancy rotation must atomically change targets without moving any soldier"): return
	var owners: Dictionary = {}
	for mid in plan.member_slot_map.keys():
		var slot: Vector2i = plan.get_slot_for_member(mid)
		if not _require(not owners.has(slot) and int(plan.slot_owner_map.get(slot, -1)) == mid,
			"Compact vacancy final ownership must remain bijective"): return
		owners[slot] = true
	for mid in move.active_vacancy_chain_actors:
		if not _require(terrain.can_step(cells[mid], plan.get_slot_for_member(mid)),
			"Each wall actor still needs one legal Grid step after target rotation"): return
	print("COMBAT MOVEMENT COMPACT VACANCY PASS actors=", move.active_vacancy_chain_actors.size())
	quit(0)
