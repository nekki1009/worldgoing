extends "res://scripts/terrain_lab/terrain_lab.gd"
## Frozen original-owner fatigue loop before native stationary-zero batching.

func _advance_fatigue(seconds: float) -> void:
	if terrain == null or seconds <= 0.0:
		return
	var fatigue_started := Time.get_ticks_usec() if combat_profile_enabled else 0
	var training_seconds := {}
	if site_controller != null:
		training_seconds = site_controller.consume_crew_work()
		site_controller.advance_person_supply(seconds)
		for team: TerrainArmy in combat_armies:
			if team.combat_enabled:
				var handled: Dictionary = site_controller.advance_team_sustain(team, seconds).handled_seconds
				for identity: int in handled:
					training_seconds[identity] = float(training_seconds.get(identity, 0.0)) + float(handled[identity])
		var action_seconds: Dictionary = site_controller.person_actions.advance(seconds).handled_seconds
		site_controller.captive_escort.advance(seconds)
		for identity: int in action_seconds:
			training_seconds[identity] = float(training_seconds.get(identity, 0.0)) + float(action_seconds[identity])
		var guard_seconds: Dictionary = site_controller.advance_guard_work(seconds)
		for identity: int in guard_seconds:
			training_seconds[identity] = float(training_seconds.get(identity, 0.0)) + float(guard_seconds[identity])
	fatigue_started = _combat_profile_stage("fatigue_providers", fatigue_started)
	# Only this synchronous step shares the read-only threat candidates.
	var enemies := {}
	for actor: TerrainTestCharacter in combat_actors:
		if not is_instance_valid(actor):
			continue
		var worked := minf(seconds, float(_fatigue_work_seconds.get(actor, 0.0)))
		_fatigue_work_seconds[actor] = maxf(0.0, float(_fatigue_work_seconds.get(actor, 0.0)) - worked)
		var available := maxf(0.0, seconds - worked - float(training_seconds.get(actor.person_id, 0.0)))
		if available <= 0.0:
			continue
		var moving := actor.is_moving()
		var can_act := actor.can_act()
		var rate := 0.0
		if can_act:
			if not exchange_enabled and actor.action_time > 0.0 and actor._strike_at >= 0.0:
				rate = PersonFatigue.ATTACK_RATE
			elif not exchange_enabled and (actor.guarding or actor.guard_transition_left > 0.0):
				rate = PersonFatigue.GUARD_RATE
			elif moving and actor.combat_ready and actor._movement_duration <= TerrainTestCharacter.RUN_DURATION + 0.000001:
				rate = PersonFatigue.RUN_RATE
		var idle := can_act and not moving and actor.action_time <= 0.0 and not actor.guarding and actor.guard_transition_left <= 0.0 and actor.guard_break_left <= 0.0 and actor._rescue_left <= 0.0
		if actor == npc and (bool(terrain.site.get("worker_enabled", false)) or bool(terrain.site.worker.get("manual_control", false))) and not actor.work_resting and not str(terrain.site.get("worker", {}).get("target", "")).is_empty():
			idle = false # Assigned travel/work/input waits do not double as a rest break.
		var safe := false
		if idle and actor.fatigue > 0.0:
			var threat_started := Time.get_ticks_usec() if combat_profile_enabled else 0
			safe = not _fatigue_threat(actor.terrain_cell, actor.faction_id, actor, -1, enemies)
			_combat_profile_stage("fatigue_threat", threat_started)
		var state := PersonFatigue.advance(actor.fatigue, actor.fatigue_rest, available, rate, safe)
		actor.fatigue = state[0]
		actor.fatigue_rest = state[1]
	for team: TerrainArmy in combat_armies:
		if not team.combat_enabled:
			continue
		for index in range(team.combat_units.size()):
			var unit: Dictionary = team.combat_units[index]
			var available := seconds if training_seconds.is_empty() else maxf(0.0, seconds - float(training_seconds.get(team.combat_identity(index), 0.0)))
			if available <= 0.0:
				continue
			var moving := team.moving_to[index] != TerrainArmy.INVALID_CELL
			# In exchange mode only running accrues continuous effort. An exact
			# zero walking/stationary row needs no eligibility/rest/formula query.
			if fatigue_zero_fast_path_enabled and exchange_enabled and float(unit.fatigue) == 0.0 and (not moving or team.move_duration[index] > TerrainArmy.RUN_DURATION + 0.000001):
				unit.fatigue = float(unit.fatigue)
				unit.fatigue_rest = 0.0
				if combat_profile_enabled:
					fatigue_zero_eligible_rows += 1
					fatigue_zero_skipped_advances += 1
				continue
			var can_act := team.combat_can_act(index)
			var rate := 0.0
			if can_act:
				if not exchange_enabled and bool(unit.attack):
					rate = PersonFatigue.ATTACK_RATE
				elif not exchange_enabled and str(unit.pose) in ["guard", "guard_raise", "guard_lower"]:
					rate = PersonFatigue.GUARD_RATE
				elif moving and team.move_duration[index] <= TerrainArmy.RUN_DURATION + 0.000001:
					rate = PersonFatigue.RUN_RATE
			if (fatigue_zero_fast_path_enabled or combat_profile_enabled) and rate == 0.0 and float(unit.fatigue) == 0.0:
				if combat_profile_enabled:
					fatigue_zero_eligible_rows += 1
				if fatigue_zero_fast_path_enabled:
					# Original safe=false path returns [float(value), +0.0]. Keep
					# the incoming fatigue's signed zero/type conversion, not a new zero.
					unit.fatigue = float(unit.fatigue)
					unit.fatigue_rest = 0.0
					if combat_profile_enabled:
						fatigue_zero_skipped_advances += 1
					continue
			var idle := can_act and not moving and str(unit.pose) == "idle"
			if not unit.get("work_task", {}).is_empty() and str(unit.work_task.get("mode", "")) != "rest":
				idle = false # Pending work/input/path waits are not a rest break.
			var safe := false
			if idle and float(unit.fatigue) > 0.0:
				var threat_started := Time.get_ticks_usec() if combat_profile_enabled else 0
				safe = not _fatigue_threat(team.cells[index], team.faction_id, team, index, enemies)
				_combat_profile_stage("fatigue_threat", threat_started)
			var state := PersonFatigue.advance(float(unit.fatigue), float(unit.fatigue_rest), available, rate, safe)
			unit.fatigue = state[0]
			unit.fatigue_rest = state[1]
	# Inclusive of fatigue_threat; do not add that nested counter a second time.
	_combat_profile_stage("fatigue_people_inclusive", fatigue_started)
