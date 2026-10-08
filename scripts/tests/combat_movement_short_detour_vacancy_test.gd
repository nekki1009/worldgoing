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
	var terrain := Helper.build_flat_map(70, 45)
	var plan := CombatDeploymentPlan.new()
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	var waiting := 1141
	var commander := 1100
	var vacancy := Vector2i(42, 15)
	var commander_slot := Vector2i(41, 20)
	var cells: Dictionary = {waiting: Vector2i(56, 15), commander: Vector2i(29, 20)}
	var next_id := 2000
	for x in range(33, 58):
		for y in range(8, 33):
			plan.platform_footprint.append(Vector2i(x, y))
	for x in range(41, 51):
		for y in range(15, 25):
			var slot := Vector2i(x, y)
			var mid: int = waiting if slot == vacancy else (commander if slot == commander_slot else next_id)
			if mid == next_id:
				next_id += 1
			plan.platform_slots.append(slot)
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
	move.member_route_retry_count[waiting] = 3
	if not _require(not Destination._recover_isolated_final_vacancy(move, plan, cells, terrain, occupied, allowed) and plan.get_slot_for_member(waiting) == vacancy,
		"A short nominal exterior detour must not rotate a final after only a few route failures"): return
	move.member_route_retry_count[waiting] = 12
	if not _require(Destination._recover_isolated_final_vacancy(move, plan, cells, terrain, occupied, allowed),
		"A genuinely stalled owner must get a vacancy chain even when the free-only detour is short"): return
	if not _require(cells == original_cells and plan.get_slot_for_member(waiting) != vacancy and plan.get_slot_for_member(commander) == commander_slot and move.active_vacancy_chain_actors.size() > 0,
		"Recovery must only change compatible final ownership, never physical cells or Commander slot"): return
	var seen: Dictionary = {}
	for mid in plan.member_slot_map.keys():
		var slot: Vector2i = plan.get_slot_for_member(mid)
		if not _require(not seen.has(slot) and int(plan.slot_owner_map.get(slot, -1)) == mid, "Final ownership must remain unique and reversible"): return
		seen[slot] = true
	for mid in move.active_vacancy_chain_actors:
		if not _require(terrain.can_step(cells[mid], plan.get_slot_for_member(mid)), "Grid must be able to execute each chain step legally"): return
	print("COMBAT MOVEMENT SHORT DETOUR VACANCY PASS")
	quit(0)
