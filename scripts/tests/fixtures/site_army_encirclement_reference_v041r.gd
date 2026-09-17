extends "res://scripts/tests/fixtures/site_army_prepare_reference_v041r.gd"
## Frozen original encirclement implementation, before phase-two spatial lookup.

func _try_exchange_encirclement() -> bool:
	if data == null or bool(data.site.get("paused", false)) or (is_inside_tree() and get_tree().paused) \
		or not exchange_enabled or not combat_attacking or combat_order not in [CombatOrder.ATTACK, CombatOrder.PURSUE] \
		or needs_attack_order or is_sustain_routed() or not exchange_people_query.is_valid():
		return false
	var people: Array = exchange_people_query.call()
	var enemies := {}
	for person: Dictionary in people:
		if int(person.faction) != faction_id:
			enemies[Vector2i(person.cell)] = true
	var contact_cells: Array[Vector2i] = []
	var pinned := {}
	for person: Dictionary in people:
		var index := int(person.unit)
		if not (person.owner == self and index >= 0 and is_member(index)) \
			and not (is_instance_valid(player_member) and person.owner == player_member):
			continue
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next: Vector2i = person.cell + direction
			if enemies.has(next) and data.can_attack_across(person.cell, next):
				contact_cells.append(person.cell)
				if person.owner == self:
					pinned[index] = true
				break
	if contact_cells.is_empty():
		return false # No automatic long-distance pursuit just because ATTACK is selected.
	encirclement_reviews += 1
	# A single bounded reverse field serves this review, not a BFS per person/goal.
	# ponytail: local eight-step encirclement only; do not add global siege/path AI here.
	var distance := {}
	var destinations := {}
	var pending: Array[Vector2i] = []
	for enemy_cell: Vector2i in enemies:
		var near_front := false
		for contact: Vector2i in contact_cells:
			if absi(enemy_cell.x - contact.x) + absi(enemy_cell.y - contact.y) <= ENCIRCLEMENT_DISTANCE:
				near_front = true
				break
		if not near_front:
			continue
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var goal := enemy_cell + direction
			if distance.has(goal) or pending.size() >= ENCIRCLEMENT_CELLS or not data.is_walkable(goal) \
				or not data.can_attack_across(goal, enemy_cell) or blocks_cell(goal) or _is_external_cell(goal):
				continue
			distance[goal] = 0
			destinations[goal] = goal
			pending.append(goal)
	var head := 0
	while head < pending.size():
		var cell := pending[head]
		head += 1
		if int(distance[cell]) >= ENCIRCLEMENT_DISTANCE - 1:
			continue
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if distance.has(next) or pending.size() >= ENCIRCLEMENT_CELLS \
				or not data.can_step(next, cell) or blocks_cell(next) or _is_external_cell(next):
				continue
			distance[next] = int(distance[cell]) + 1
			destinations[next] = destinations[cell]
			pending.append(next)
	var candidates: Array[Dictionary] = []
	for index in range(combat_units.size()):
		if pinned.has(index) or not is_member(index) or is_controlled_person(index) or not combat_can_act(index) \
			or moving_to[index] != INVALID_CELL or _combat_action_blocks_step(index) or _unit_rescues.has(index) \
			or _exchange_maneuver_blocked(index):
			continue
		var best := INVALID_CELL
		var cost := ENCIRCLEMENT_DISTANCE
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cells[index] + direction
			if distance.has(next) and int(distance[next]) < cost and data.can_step(cells[index], next):
				best = next
				cost = int(distance[next])
		if best != INVALID_CELL:
			candidates.append({"unit": index, "id": combat_identity(index), "step": best,
				"goal": destinations[best], "cost": cost})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.cost) < int(b.cost) if int(a.cost) != int(b.cost) else int(a.id) < int(b.id))
	var claimed_goals := {}
	var issued := 0
	for candidate: Dictionary in candidates:
		if issued >= ENCIRCLEMENT_STEPS:
			break
		if claimed_goals.has(candidate.goal):
			continue
		var index := int(candidate.unit)
		if _reserve_combat_step(index, candidate.step):
			# Keep the accepted endpoint in the original order state: losing contact
			# must not send this person back to an obsolete pre-engagement slot.
			for slot_index: int in _vacancy_assignments.keys():
				if int(_vacancy_assignments[slot_index]) == index:
					_vacancy_assignments.erase(slot_index)
			combat_slots[index] = candidate.step
			claimed_goals[candidate.goal] = true
			issued += 1
			encirclement_steps += 1
	return true # A blocked flank waits; it never teleports, swaps bodies or forces allies aside.
