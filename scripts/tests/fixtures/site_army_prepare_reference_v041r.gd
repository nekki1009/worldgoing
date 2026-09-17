extends "res://scripts/terrain_lab/terrain_army.gd"
## Frozen V0.41R reference, test only.

func prepare_combat(delta: float) -> void:
	if not combat_enabled or delta <= 0.0 or (is_inside_tree() and get_tree().paused):
		return
	if is_instance_valid(player_member):
		_command_dirty = true # Observe independent player movement/KO on this same step.
	if combat_order in [CombatOrder.MOVE, CombatOrder.RETREAT, CombatOrder.RETURN]:
		for index in range(combat_units.size()):
			if is_member(index) and str(combat_units[index].pose) == "guard":
				set_unit_guard(index, false)
	_update_combat_orders(delta)
	for index in range(combat_units.size()):
		var unit: Dictionary = combat_units[index]
		unit.age = float(unit.age) + delta
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
