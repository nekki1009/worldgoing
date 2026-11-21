extends "res://scripts/tests/combat_movement_formal_mountain_arrival_test.gd"
## Diagnostic-only early stop; the formal acceptance script remains unchanged.

func _advance() -> bool:
	if not super._advance():
		return false
	if _tick < 8700:
		return true
	var move: CombatMovePlan = _army.get_active_move_plan()
	var current: Dictionary = _army.get_active_members_occupancy()
	var occupied: Dictionary = {}
	for mid in current.keys():
		occupied[current[mid]] = mid
	var correct := 0
	var wrong_slot := 0
	var wrong_swappable := 0
	var off_slot := 0
	var goal_occupied := 0
	var footprint := 0
	var target_kinds: Dictionary = {}
	var examples: Array[String] = []
	for mid in _members:
		var cell: Vector2i = current[mid]
		var goal: Vector2i = _plan.get_slot_for_member(mid)
		var owner: int = int(_plan.slot_owner_map.get(cell, -1))
		var blocker: int = int(occupied.get(goal, -1))
		var target: Dictionary = Destination.resolve_member_target(move, _plan, mid, cell)
		var kind: String = str(target.get("kind", "?"))
		target_kinds[kind] = int(target_kinds.get(kind, 0)) + 1
		if _plan.platform_footprint.has(cell):
			footprint += 1
		if cell == goal:
			correct += 1
		else:
			if owner >= 0:
				wrong_slot += 1
				if _plan.admitted_platform_member_ids.has(mid) and _plan.admitted_platform_member_ids.has(owner) \
					and _plan.get_role_for_member(mid) == _plan.get_role_for_member(owner) \
					and _plan.slot_tactical_roles.get(goal) == _plan.slot_tactical_roles.get(cell) \
					and not _plan.is_slot_locked(mid) and not _plan.is_slot_locked(owner):
					wrong_swappable += 1
			else:
				off_slot += 1
			if blocker >= 0:
				goal_occupied += 1
			if examples.size() < 20:
				examples.append("%d cell=%s goal=%s owner=%d blocker=%d kind=%s admitted=%s locked=%s moving=%s" % [
					mid, cell, goal, owner, blocker, kind,
					_plan.admitted_platform_member_ids.has(mid), _plan.is_slot_locked(mid),
					_army.moving_to[_army.index_for_identity(mid)]
				])
	print("MOUNTAIN_PLATFORM_OWNERSHIP_PROBE simulated=", _tick * STEP,
		" correct=", correct, " wrong_slot=", wrong_slot, " wrong_swappable=", wrong_swappable,
		" off_slot=", off_slot, " unresolved_goal_occupied=", goal_occupied,
		" footprint=", footprint, " admitted=", _plan.admitted_platform_member_ids.size(),
		" target_kinds=", target_kinds, " examples=", examples)
	var vacant_slots: Array[Vector2i] = []
	for slot in _plan.platform_slots:
		if not occupied.has(slot):
			vacant_slots.append(slot)
	print("MOUNTAIN_PLATFORM_VACANCIES count=", vacant_slots.size(), " cells=", vacant_slots)
	print("MOUNTAIN_PLATFORM_RECOVERY active_chain=", move.active_vacancy_chain_actors,
		" highwater=", move.platform_settled_highwater,
		" last_progress=", move.last_platform_progress_time_sec,
		" next_recovery=", move.next_platform_recovery_time_sec)
	for mid in _members:
		var cell: Vector2i = current[mid]
		var goal: Vector2i = _plan.get_slot_for_member(mid)
		if cell == goal:
			continue
		var near_free := 0
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var neighbor: Vector2i = cell + direction
			if not occupied.has(neighbor) and _army.data.can_step(cell, neighbor):
				near_free += 1
		print("MOUNTAIN_PLATFORM_UNRESOLVED mid=", mid, " cell=", cell, " goal=", goal,
			" current_owner=", _plan.slot_owner_map.get(cell, -1), " goal_occupant=", occupied.get(goal, -1),
			" near_free=", near_free, " retry=", move.member_route_retry_count.get(mid, 0),
			" kind=", Destination.resolve_member_target(move, _plan, mid, cell).get("kind", "?"),
			" admitted=", _plan.admitted_platform_member_ids.has(mid), " locked=", _plan.is_slot_locked(mid))
	if is_instance_valid(_lab):
		_lab.queue_free()
	quit(0)
	return false
