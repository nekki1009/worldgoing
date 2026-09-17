extends "res://scripts/terrain_lab/terrain_army.gd"
## Frozen phase-four methods. Do not update these to match optimized code.

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
	# Disposable contact buckets, not another movement/target owner. Exact
	# Manhattan checks still decide membership; enemy iteration/claim order stays.
	var contact_buckets := {}
	for contact: Vector2i in contact_cells:
		var bucket := Vector2i(contact.x >> 3, contact.y >> 3)
		if not contact_buckets.has(bucket): contact_buckets[bucket] = []
		contact_buckets[bucket].append(contact)
	for enemy_cell: Vector2i in enemies:
		var near_front := false
		for bucket_y in range((enemy_cell.y - ENCIRCLEMENT_DISTANCE) >> 3, ((enemy_cell.y + ENCIRCLEMENT_DISTANCE) >> 3) + 1):
			for bucket_x in range((enemy_cell.x - ENCIRCLEMENT_DISTANCE) >> 3, ((enemy_cell.x + ENCIRCLEMENT_DISTANCE) >> 3) + 1):
				for contact: Vector2i in contact_buckets.get(Vector2i(bucket_x, bucket_y), []):
					if absi(enemy_cell.x - contact.x) + absi(enemy_cell.y - contact.y) <= ENCIRCLEMENT_DISTANCE:
						near_front = true
						break
				if near_front: break
			if near_front: break
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


func prepare_combat(delta: float) -> void:
	if not combat_enabled or delta <= 0.0 or (is_inside_tree() and get_tree().paused):
		return
	var profile_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	if is_instance_valid(player_member):
		_command_dirty = true # Observe independent player movement/KO on this same step.
	if combat_order in [CombatOrder.MOVE, CombatOrder.RETREAT, CombatOrder.RETURN]:
		for index in range(combat_units.size()):
			if is_member(index) and str(combat_units[index].pose) == "guard":
				set_unit_guard(index, false)
	_update_combat_orders(delta)
	profile_started = _profile_combat_stage("orders", profile_started)
	for index in range(combat_units.size()):
		var unit: Dictionary = combat_units[index]
		unit.age = float(unit.age) + delta
		# Original idle ATTACK rear ranks have no active recovery/movement work.
		# Normalize the same optional timers once, retain age/think exactly, and
		# leave all rescue/guard/hit/KO/moving rows on the complete owner path.
		if exchange_enabled and combat_order != CombatOrder.HOLD and str(unit.pose) == "idle" and float(unit.hp) > 0.0 and float(unit.ko) <= 0.0 and moving_to[index] == INVALID_CELL and not _unit_rescues.has(index) \
			and float(unit.stun) == 0.0 and float(unit.grace) == 0.0 and unit.get("exchange_visual", {}).is_empty() and float(unit.get("exchange_pose_duration", 0.0)) == 0.0 \
			and float(unit.get("exchange_cooldown", 0.0)) == 0.0 and float(unit.get("exchange_stagger", 0.0)) == 0.0 and float(unit.get("exchange_skill_cooldown", 0.0)) == 0.0 and float(unit.get("ranged_cooldown", 0.0)) == 0.0:
			unit["exchange_cooldown"] = 0.0
			unit["exchange_stagger"] = 0.0
			unit["exchange_skill_cooldown"] = 0.0
			unit["ranged_cooldown"] = 0.0
			unit.grace = 0.0
			unit.stun = 0.0
			unit.think = maxf(0.0, float(unit.think) - delta)
			continue
		if exchange_enabled:
			_advance_exchange_visual(index, delta)
			for field: String in ["exchange_cooldown", "exchange_stagger", "exchange_skill_cooldown", "ranged_cooldown"]:
				var remaining := maxf(0.0, float(unit.get(field, 0.0)) - delta)
				unit[field] = 0.0 if remaining <= 0.000000001 else remaining
		if moving_to[index] != INVALID_CELL:
			move_progress[index] = CombatTimings.advance_movement_progress(move_progress[index], delta, move_duration[index])
			if move_progress[index] >= 1.0:
				_complete_move(index)
		if float(unit.hp) <= 0.0:
			continue
		if float(unit.ko) > 0.0:
			unit.ko = maxf(0.0, float(unit.ko) - delta)
			if str(unit.pose) == "down" and float(unit.age) >= float(CombatTimings.POSE_SECONDS[&"down"]):
				unit.pose = "unconscious"
				unit.age = 0.0
			if float(unit.ko) <= 0.0:
				_wake_unit(index)
			continue
		if _unit_rescues.has(index):
			var entry: Dictionary = _unit_rescues[index]
			var patient := int(entry.patient)
			if not combat_can_act(index) or not _rescue_reachable(index, patient) or patient == PLAYER_MEMBER and int(entry.revision) != player_member._received_effective_hit:
				_cancel_unit_rescue(index)
			elif float(unit.age) >= float(CombatTimings.POSE_SECONDS[&"rescue"]):
				if patient == PLAYER_MEMBER:
					player_member._wake_up()
				else:
					_wake_unit(patient)
				_cancel_unit_rescue(index)
			continue
		var decay := maxf(0.0, delta - float(unit.grace))
		unit.grace = maxf(0.0, float(unit.grace) - delta)
		unit.stun = maxf(0.0, float(unit.stun) - decay * SiteCombatRules.STUN_RECOVERY)
		if exchange_enabled:
			_advance_exchange_pose(index)
			unit.think = maxf(0.0, float(unit.think) - delta)
			# Keep existing automatic safe rescue in HOLD without any pose/body
			# sampling. Advancing combat units never run the old enemy scan.
			if float(unit.think) <= 0.0 and is_member(index) and combat_order == CombatOrder.HOLD and str(unit.pose) == "idle" and combat_can_act(index) and not is_controlled_person(index):
				unit.think = 0.5
				if not is_sustain_routed() and not (person_busy_query.is_valid() and bool(person_busy_query.call(combat_identity(index)))) and enemy_query.is_valid() and (enemy_query.call(self, index) as Dictionary).is_empty():
					for patient: int in command_members():
						if start_unit_rescue(index, patient):
							break
			continue # Adjacency/ability decisions happen once in the Lab; no old targeting/aim queries.
		var finished := bool(unit.attack) and float(unit.age) >= CombatTimings.action_duration(attack_clip(index), float(unit.attack_reduction), float(unit.attack_fatigue))
		if str(unit.pose) in ["get_up", "guard_break"]:
			finished = float(unit.age) >= float(CombatTimings.POSE_SECONDS[StringName(str(unit.pose))])
		if str(unit.pose) in ["guard_raise", "guard_lower"] and float(unit.age) >= SiteCombatRules.GUARD_TRANSITION:
			unit.pose = "guard" if str(unit.pose) == "guard_raise" else "idle"
			unit.age = 0.0
		if finished:
			unit.pose = "idle"
			unit.age = 0.0
			unit.attack = false
			unit.previous = []
			unit.think = 0.5
			_command_dirty = true
		unit.think = maxf(0.0, float(unit.think) - delta)
		if not bool(unit.attack) and float(unit.think) <= 0.0 and combat_can_act(index) and not is_controlled_person(index) and (not is_member(index) or _order_delay <= 0.0) and enemy_query.is_valid():
			unit.think = 0.5 * (1.0 - command_effect("tactics", 0.20)) if is_member(index) else 0.5
			var target: Dictionary = enemy_query.call(self, index)
			if is_member(index) and target.is_empty() and combat_order == CombatOrder.HOLD and str(unit.pose) == "idle" and not is_sustain_routed() and not (person_busy_query.is_valid() and bool(person_busy_query.call(combat_identity(index)))):
				for patient: int in command_members():
					if start_unit_rescue(index, patient):
						break
			if (not is_member(index) or not combat_attacking) and not target.is_empty() and bool(target.get("threat", false)):
				set_unit_guard(index, true)
				continue
			if str(unit.pose) == "guard":
				set_unit_guard(index, false)
				continue
			if not target.is_empty() and (is_member(index) and combat_attacking or bool(target.get("threat", false))):
				if start_unit_attack(index, target.cell, int(target.identity), bool(target.get("threat", false))):
					unit.target = int(target.identity)
	_visual_dirty = true
	_profile_combat_stage("prepare_rows", profile_started)
