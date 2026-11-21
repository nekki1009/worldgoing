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
	var terrain := Helper.build_flat_map(14, 8)
	var plan := CombatDeploymentPlan.new()
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	var waiting := 99
	var vacancy := Vector2i(5, 3)
	var cells: Dictionary = {waiting: Vector2i(10, 3)}
	var occupied: Dictionary = {Vector2i(10, 3): true}
	var allowed: Dictionary = {}
	for x in range(3, 8):
		for y in range(1, 6):
			var cell := Vector2i(x, y)
			plan.platform_footprint.append(cell)
			allowed[cell] = true
	var other_vacancies: Dictionary = {}
	for y in range(1, 6):
		other_vacancies[Vector2i(3, y)] = true
	other_vacancies[Vector2i(4, 1)] = true
	other_vacancies[Vector2i(4, 5)] = true
	other_vacancies[Vector2i(7, 1)] = true
	var next_id := 1
	for x in range(3, 8):
		for y in range(1, 6):
			var slot := Vector2i(x, y)
			var mid: int = waiting if slot == vacancy else next_id
			if mid == next_id:
				next_id += 1
			plan.platform_slots.append(slot)
			plan.member_slot_map[mid] = slot
			plan.slot_owner_map[slot] = mid
			plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
			plan.slot_tactical_roles[slot] = Types.TacticalSlotRole.FLEX
			if mid == waiting:
				plan.admitted_platform_member_ids.append(mid)
			elif not other_vacancies.has(slot):
				cells[mid] = slot
				occupied[slot] = true
				plan.admitted_platform_member_ids.append(mid)
				plan.settled_platform_member_ids.append(mid)
				plan.member_slot_locked[mid] = true
	var original_cells: Dictionary = cells.duplicate()
	var original_epoch: int = plan.assignment_epoch
	if not _require(plan.platform_slots.size() == 25 and plan.settled_platform_member_ids.size() == 16 and plan.pending_platform_member_ids.is_empty(),
		"The mid-density fixture must have sixteen locked soldiers and nine vacancies"): return
	if not _require(Destination._recover_isolated_final_vacancy(move, plan, cells, terrain, occupied, allowed),
		"A soldier three cells outside the final footprint must connect to the interior vacancy chain before 97 percent settlement"): return
	var new_waiting_slot: Vector2i = plan.get_slot_for_member(waiting)
	if not _require(cells == original_cells and plan.assignment_epoch == original_epoch + 1 and new_waiting_slot != vacancy and original_cells.values().has(new_waiting_slot) and not move.active_vacancy_chain_actors.is_empty(),
		"The stranded soldier must receive the boundary slot vacated by a legal chain, without moving any cell immediately"): return
	var owners: Dictionary = {}
	for mid in plan.member_slot_map.keys():
		var slot: Vector2i = plan.get_slot_for_member(mid)
		if not _require(not owners.has(slot) and int(plan.slot_owner_map.get(slot, -1)) == mid,
			"Mid-density final owners must remain unique after the rotation"): return
		owners[slot] = true
	for mid in move.active_vacancy_chain_actors:
		if not _require(terrain.can_step(cells[mid], plan.get_slot_for_member(mid)),
			"Each chain actor must still make a legal physical Grid step"): return
	print("COMBAT MOVEMENT MID-DENSITY VACANCY PASS actors=", move.active_vacancy_chain_actors.size())
	quit(0)
