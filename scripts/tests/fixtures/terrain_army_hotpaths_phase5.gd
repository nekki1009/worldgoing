extends "res://scripts/terrain_lab/terrain_army.gd"
## Frozen phase-five methods for same-owner performance/state comparisons.

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
			and float(unit.stun) == 0.0 and float(unit.grace) == 0.0 and (not unit.has("exchange_visual") or unit.exchange_visual.is_empty()) and float(unit.get("exchange_pose_duration", 0.0)) == 0.0 \
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
func _set_soldier_frame(index: int, force: bool = false) -> void:
	if not _soldier_baked_ready or index < 0 or index >= _sprites.size() or _uses_live_presenter(index):
		return
	if _batch_view != null and _batch_render_active():
		var unit: Dictionary = combat_units[index]
		var idle := str(unit.pose) == "idle" and not unit.has("exchange_visual")
		var pose := "idle" if idle else _exchange_visual_pose(index)
		var clip := _combat_clip(index, pose)
		var direction := _soldier_direction_id(facing[index] if idle else _exchange_visual_facing(index, pose))
		var clock: Array = _combat_bake.contact_clocks[clip][direction]
		var sample := float(unit.age) if idle else _exchange_animation_time(index, float(clock[1]), pose)
		if _batch_view.submit(index, combat_ground(index), equipment_appearance(index), clip, direction, sample):
			if _sprites[index] != null:
				_sprites[index].queue_free()
				_sprites[index] = null
			return
	if _sprites[index] == null:
		_sprites[index] = _new_person_sprite(index)
		_sprites[index].scale = Vector2.ONE * _soldier_map_scale
	if combat_enabled:
		var appearance := equipment_appearance(index)
		if not appearance.is_empty() and not EquipmentAtlas.DyeAtlas.apply(_sprites[index], appearance):
			_sprites[index].texture = null # No recolouring without an exact complete companion.
			return
		if not appearance.is_empty() and HumanCharacter3DEditor.EquipmentDye.geometry_appearance(appearance) != _combat_bake.manifest.appearance:
			var raw := contact_sample(index)
			var frame := EquipmentAtlas.frame(appearance, _combat_clip(index), _soldier_direction_id(Vector2i(raw[2])), float(raw[1]))
			if frame.is_empty():
				_sprites[index].texture = null # Missing assets must not show phantom full gear.
				return
			var equipment_key := "equipment|%s|%s|%s|%d" % [str(appearance.parts), str(frame.clip), str(frame.direction), int(frame.frame)]
			if force or _soldier_current_keys[index] != equipment_key:
				_soldier_current_keys[index] = equipment_key
				_sprites[index].texture = frame.texture
				_soldier_sprite_anchors[index] = Vector2(float(frame.anchor_offset.x), float(frame.anchor_offset.y)) * float(frame.map_scale)
			return
	var clip_id := _locomotion_clip(index)
	if not _soldier_clip_counts.has(clip_id):
		clip_id = "walk" if _soldier_clip_counts.has("walk") else "idle"
	var direction_id := _soldier_direction_id(facing[index])
	var frame_count := maxi(1, int(_soldier_clip_counts.get(clip_id, 1)))
	var duration := maxf(0.001, float(_soldier_clip_durations.get(clip_id, 1.0)))
	var phase := fmod(maxf(0.0, _soldier_animation_time[index]), duration) / duration
	var frame_id := mini(frame_count - 1, floori(phase * frame_count))
	var key := _soldier_frame_key(clip_id, direction_id, frame_id)
	if combat_enabled:
		var frame := combat_frame(index)
		key = _soldier_frame_key(str(frame.clip), str(frame.direction), int(frame.frame))
	if not force and _soldier_current_keys[index] == key:
		return
	var texture_variant = _soldier_frame_textures.get(key)
	if texture_variant == null:
		key = _soldier_frame_key("idle", direction_id, 0)
		texture_variant = _soldier_frame_textures.get(key)
	if texture_variant == null:
		return
	_soldier_current_keys[index] = key
	_sprites[index].texture = texture_variant as Texture2D
	_soldier_sprite_anchors[index] = _soldier_frame_anchors.get(key, Vector2.ZERO)
