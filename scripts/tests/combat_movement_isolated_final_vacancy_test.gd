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
	var terrain := Helper.build_flat_map(12, 8)
	var plan := CombatDeploymentPlan.new()
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	var waiting := 999
	var commander := 1000
	var vacancy := Vector2i(5, 2)
	var commander_slot := Vector2i(3, 1)
	var cells: Dictionary = {waiting: Vector2i(2, 4), commander: Vector2i(1, 1)}
	var next_id := 1
	for x in range(2, 9):
		for y in range(1, 7):
			plan.platform_footprint.append(Vector2i(x, y))
	for x in range(3, 8):
		for y in range(1, 6):
			var slot := Vector2i(x, y)
			plan.platform_slots.append(slot)
			var mid: int = waiting if slot == vacancy else (commander if slot == commander_slot else next_id)
			if mid == next_id and slot != vacancy and slot != commander_slot:
				next_id += 1
			plan.member_slot_map[mid] = slot
			plan.slot_owner_map[slot] = mid
			plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
			plan.slot_tactical_roles[slot] = Types.TacticalSlotRole.COMMANDER if slot == commander_slot else Types.TacticalSlotRole.FLEX
			if mid != waiting and mid != commander:
				cells[mid] = slot
				plan.admitted_platform_member_ids.append(mid)
				plan.settled_platform_member_ids.append(mid)
				plan.member_slot_locked[mid] = true
	plan.admitted_platform_member_ids.append(waiting)
	plan.pending_platform_member_ids.append(commander)
	var original_cells: Dictionary = cells.duplicate()
	var occupied: Dictionary = {}
	for cell in cells.values():
		occupied[cell] = true
	var allowed: Dictionary = {}
	for cell in plan.platform_footprint:
		allowed[cell] = true
	var original_epoch: int = plan.assignment_epoch
	if not _require(not Destination._recover_isolated_final_vacancy(move, plan, cells, terrain, occupied, allowed, {vacancy: true}) and move.active_vacancy_chain_actors.is_empty() and plan.assignment_epoch == original_epoch and cells == original_cells,
		"A physically empty final claimed by an in-flight step cannot become a vacancy-chain tail yet"): return
	move.member_pending_proposal_id[waiting] = 42
	if not _require(Destination._recover_isolated_final_vacancy(move, plan, cells, terrain, occupied, allowed) and move.member_recovery_hold.has(waiting) and cells == original_cells and plan.get_slot_for_member(waiting) == vacancy,
		"An in-flight soldier must wait for batch completion without moving any cell or target"): return
	move.member_pending_proposal_id.erase(waiting)
	move.active_vacancy_chain_actors = [waiting]
	Destination.update_movement_phase(move, plan, cells, terrain, 0.05)
	if not _require(not move.member_recovery_hold.has(waiting) and cells == original_cells and plan.get_slot_for_member(waiting) == vacancy,
		"A completed physical step must not remain parked behind another active vacancy chain"): return
	move.active_vacancy_chain_actors.clear()
	if not _require(Destination._recover_isolated_final_vacancy(move, plan, cells, terrain, occupied, allowed),
		"The completed soldier must receive a vacancy chain through compatible locked FLEX slots"): return
	var new_waiting_slot: Vector2i = plan.get_slot_for_member(waiting)
	if not _require(cells == original_cells and new_waiting_slot != vacancy and move.member_recovery_hold.has(waiting) and move.vacancy_waiting_id == waiting and move.active_vacancy_chain_actors.size() == 1 and plan.get_slot_for_member(commander) == commander_slot,
		"Only one adjacent actor may take the vacancy while the waiting soldier holds position"): return
	var unique_slots: Dictionary = {}
	for mid in plan.member_slot_map.keys():
		var slot: Vector2i = plan.get_slot_for_member(mid)
		if not _require(not unique_slots.has(slot) and int(plan.slot_owner_map.get(slot, -1)) == mid,
			"Rotated final ownership must remain bijective"): return
		unique_slots[slot] = true
	for mid in move.active_vacancy_chain_actors:
		if not _require(terrain.can_step(cells[mid], plan.get_slot_for_member(mid)),
			"Every vacancy-chain actor must have one legal physical step for Grid to execute later"): return
	print("COMBAT MOVEMENT ISOLATED FINAL VACANCY PASS actors=", move.active_vacancy_chain_actors.size())
	quit(0)
