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

func _free_distance(terrain: TerrainData, start: Vector2i, goal: Vector2i, occupied: Dictionary) -> int:
	var distances: Dictionary = {start: 0}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty() and distances.size() <= 512:
		var cell: Vector2i = frontier.pop_front()
		if cell == goal:
			return int(distances[cell])
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next: Vector2i = cell + direction
			if not distances.has(next) and not occupied.has(next) and terrain.contains(next) and terrain.can_step(cell, next):
				distances[next] = int(distances[cell]) + 1
				frontier.append(next)
	return -1

func _run() -> void:
	var terrain := Helper.build_flat_map(20, 15)
	var plan := CombatDeploymentPlan.new()
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	var waiting := 999
	var start := Vector2i(18, 6)
	var vacancy := Vector2i(8, 6)
	var cells: Dictionary = {waiting: start}
	var occupied: Dictionary = {start: true}
	var allowed: Dictionary = {}
	var next_id := 1
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
				plan.admitted_platform_member_ids.append(mid)
			elif not free_corridor:
				cells[mid] = slot
				occupied[slot] = true
				plan.admitted_platform_member_ids.append(mid)
				plan.settled_platform_member_ids.append(mid)
				plan.member_slot_locked[mid] = true
	var before: Dictionary = cells.duplicate()
	if not _require(plan.platform_slots.size() == 121 and plan.settled_platform_member_ids.size() >= 100,
		"The long-detour fixture must have a dense locked final wall and an exterior gap"): return
	if not _require(not Destination._recover_isolated_final_vacancy(move, plan, cells, terrain, occupied, allowed) and cells == before,
		"A reachable final with no prior route failures must keep its original ownership"): return
	move.member_route_retry_count[waiting] = 20
	print("LONG_DETOUR_PROBE free_distance=", _free_distance(terrain, start, vacancy, occupied), " direct=", absi(start.x - vacancy.x) + absi(start.y - vacancy.y), " settled=", plan.settled_platform_member_ids.size())
	if not _require(Destination._recover_isolated_final_vacancy(move, plan, cells, terrain, occupied, allowed),
		"After repeated route failures, a long free-only detour must permit a vacancy chain to the nearby exterior edge"): return
	var new_waiting_slot: Vector2i = plan.get_slot_for_member(waiting)
	if not _require(cells == before and new_waiting_slot != vacancy and new_waiting_slot.x >= 12 and move.active_vacancy_chain_actors.size() > 0,
		"Long-detour recovery must change target ownership near the waiting soldier without moving any cell"): return
	var owners: Dictionary = {}
	for mid in plan.member_slot_map.keys():
		var slot: Vector2i = plan.get_slot_for_member(mid)
		if not _require(not owners.has(slot) and int(plan.slot_owner_map.get(slot, -1)) == mid,
			"Long-detour vacancy rotation must preserve unique final ownership"): return
		owners[slot] = true
	for mid in move.active_vacancy_chain_actors:
		if not _require(terrain.can_step(cells[mid], plan.get_slot_for_member(mid)),
			"Each actor must retain one legal future physical Grid step"): return
	print("COMBAT MOVEMENT LONG DETOUR VACANCY PASS actors=", move.active_vacancy_chain_actors.size())
	quit(0)
