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
	var terrain := Helper.build_flat_map(20, 15)
	var plan := CombatDeploymentPlan.new()
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	plan.ingress_cell = Vector2i(2, 6)
	plan.resolved_anchor = Vector2i(8, 6)
	plan.centered_platform_handoff = Vector2i(14, 6)
	var waiting := 999
	var vacancy := Vector2i(8, 6)
	var cells: Dictionary = {waiting: Vector2i(18, 6)}
	var occupied: Dictionary = {Vector2i(18, 6): true}
	var allowed: Dictionary = {}
	var next_id := 1
	var side_entrant := -1
	var rear_soldier := -1
	for x in range(3, 14):
		for y in range(1, 12):
			var slot := Vector2i(x, y)
			var mid: int = waiting if slot == vacancy else next_id
			if mid == next_id:
				next_id += 1
			plan.platform_slots.append(slot)
			plan.platform_footprint.append(slot)
			allowed[slot] = true
			plan.member_slot_map[mid] = slot
			plan.slot_owner_map[slot] = mid
			plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
			plan.slot_tactical_roles[slot] = Types.TacticalSlotRole.FLEX
			var free_corridor: bool = y == 1 and x >= 8 or x == 8 and y <= 6
			if mid == waiting:
				plan.pending_platform_member_ids.append(mid)
			elif slot == Vector2i(12, 10):
				side_entrant = mid
				cells[mid] = Vector2i(18, 10)
				occupied[cells[mid]] = true
				plan.pending_platform_member_ids.append(mid)
			elif slot == Vector2i(4, 10):
				rear_soldier = mid
				cells[mid] = Vector2i(2, 12)
				occupied[cells[mid]] = true
				plan.pending_platform_member_ids.append(mid)
			elif not free_corridor:
				cells[mid] = slot
				occupied[slot] = true
				plan.admitted_platform_member_ids.append(mid)
				plan.settled_platform_member_ids.append(mid)
				plan.member_slot_locked[mid] = true
	move.member_route_retry_count[waiting] = 20
	terrain.static_blocked[terrain.index(Vector2i(8, 1))] = 1
	var before: Dictionary = cells.duplicate()
	if not _require(side_entrant >= 0 and rear_soldier >= 0 and plan.pending_platform_member_ids.size() == 3,
		"The fixture needs two returned entrants and one soldier who never crossed the handoff"): return
	if not _require(not Destination._recover_isolated_final_vacancy(move, plan, cells, terrain, occupied, allowed),
		"Three never-crossed soldiers must keep late vacancy recovery closed"): return
	plan.ever_admitted_platform_member_ids[waiting] = true
	plan.ever_admitted_platform_member_ids[side_entrant] = true
	if not _require(Destination._prior_entrant_final_isolated(plan, waiting, cells, terrain, occupied) and Destination._recover_isolated_final_vacancy(move, plan, cells, terrain, occupied, allowed),
		"Returned entrants beyond the physical handoff must not count as new ingress traffic"): return
	if not _require(cells == before and plan.get_slot_for_member(waiting) != vacancy and not move.active_vacancy_chain_actors.is_empty(),
		"Recovery may change target ownership but must leave every physical cell untouched"): return
	var unique: Dictionary = {}
	for mid in plan.member_slot_map.keys():
		var slot: Vector2i = plan.get_slot_for_member(mid)
		if not _require(not unique.has(slot) and int(plan.slot_owner_map.get(slot, -1)) == mid,
			"Returned-entrant recovery must retain unique authoritative final ownership"): return
		unique[slot] = true
	for actor in move.active_vacancy_chain_actors:
		if not _require(terrain.can_step(cells[actor], plan.get_slot_for_member(actor)),
			"Every vacancy-chain actor must have one legal future Grid step"): return
	print("COMBAT MOVEMENT RETURNED ENTRANT VACANCY PASS")
	quit(0)
