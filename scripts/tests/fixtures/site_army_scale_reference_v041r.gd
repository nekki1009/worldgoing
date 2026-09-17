extends "res://scripts/tests/fixtures/site_army_fatigue_reference_v041r.gd"
## Frozen V0.41R (51adc2f) reference, for equivalence tests only.

func _fatigue_threat(cell: Vector2i, faction: int, rest_owner: Variant, unit_index: int, candidates: Dictionary) -> bool:
	if not terrain.is_walkable(cell):
		return true
	if not candidates.has(faction):
		var cells := {}
		for actor: TerrainTestCharacter in combat_actors:
			if actor.faction_id != faction and actor.can_act():
				cells[actor.terrain_cell] = true
				if actor.is_moving():
					cells[actor.movement_from_cell] = true
		for team: TerrainArmy in combat_armies:
			if not team.combat_enabled or team.faction_id == faction:
				continue
			for index in range(team.combat_units.size()):
				if team.combat_can_act(index):
					cells[team.cells[index]] = true
					if team.moving_to[index] != TerrainArmy.INVALID_CELL:
						cells[team.moving_to[index]] = true
		candidates[faction] = {"cells": cells}
	var threat: Dictionary = candidates[faction]
	if exchange_enabled:
		if not candidates.has("flight_cells"):
			var flight_cells := {}
			for source: Node2D in _ranged_owners():
				for flight: Dictionary in source.projectiles:
					if str(flight.get("mode", "")) == "cell":
						for crossed: Vector2i in SiteCombatRules.ranged_cells(flight.source_cell, flight.target_cell):
							flight_cells[crossed] = true
			candidates["flight_cells"] = flight_cells
		if candidates.flight_cells.has(cell):
			return true # Incoming arrows, including friendly ones, prevent safe rest.
		# New rest rule: an awake enemy within eight cardinal cells prevents
		# rest even behind cover. No geometry or repeated reachability search.
		for enemy: Vector2i in threat.cells:
			var distance := enemy - cell
			if absi(distance.x) + absi(distance.y) <= 8:
				return true
		return false
	# Exact distance-zero/one witnesses from the same directed walk graph.
	# Only a positive proof bypasses the original eight-step search; obstacles,
	# distant enemies and projectiles keep their existing path below.
	if threat.cells.has(cell):
		return true
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var enemy := cell + direction
		if threat.cells.has(enemy) and terrain.can_step(enemy, cell):
			return true
	if fatigue_two_hop_witness_enabled:
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var middle := cell + direction
			for source_direction: Vector2i in TerrainData.DIRECTIONS:
				var enemy := middle + source_direction
				if threat.cells.has(enemy) and terrain.can_step(enemy, middle) and terrain.can_step(middle, cell):
					return true # Reverse enumeration, but both edges prove the original forward path.
	var nearby := false
	for enemy: Vector2i in threat.cells:
		var offset := enemy - cell
		if absi(offset.x) + absi(offset.y) <= 8:
			nearby = true
			break
	if nearby:
		if not threat.has("reachable"):
			# One original multi-source frontier per faction in this synchronous
			# step. Pause once this target is found; later targets resume it.
			var distances := {}
			var pending: Array[Vector2i] = []
			for enemy: Vector2i in threat.cells:
				distances[enemy] = 0
				pending.append(enemy)
			threat["reachable"] = distances
			threat["pending"] = pending
			threat["cursor"] = 0
		var frontier_distances: Dictionary = threat.reachable
		var frontier_pending: Array[Vector2i] = threat.pending
		var cursor: int = threat.cursor
		while not frontier_distances.has(cell) and cursor < frontier_pending.size():
			var current := frontier_pending[cursor]
			cursor += 1
			if int(frontier_distances[current]) >= 8:
				continue
			# Complete all four edges before pausing, so resuming never skips
			# the rest of the original node. Negative queries exhaust the frontier.
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var next := current + direction
				if not frontier_distances.has(next) and terrain.can_step(current, next):
					frontier_distances[next] = int(frontier_distances[current]) + 1
					frontier_pending.append(next)
		threat.cursor = cursor
		if threat.reachable.has(cell):
			return true
	for actor: TerrainTestCharacter in combat_actors:
		for arrow: Dictionary in actor.projectiles:
			if float(arrow.remaining) <= 0.0:
				continue
			if not SiteCombatRules.terrain_line_clear(terrain, Vector2i((arrow.ground as Vector2) / TerrainRenderer.CELL_PIXELS), cell):
				continue
			if rest_owner is TerrainTestCharacter and rest_owner.editor == null:
				return true # No projection in a headless fixture: conservatively forbid rest, never fabricate a hit.
			var bodies: Array[PackedVector2Array] = rest_owner.combat_shapes(unit_index, "body") if rest_owner is TerrainArmy else rest_owner._geometry.body_shapes(rest_owner)
			var end: Vector2 = arrow.position + (arrow.velocity as Vector2).normalized() * float(arrow.remaining)
			var sweep := FatigueGeometry.capsule(arrow.position, end, 1.0)
			for body: PackedVector2Array in bodies:
				if not Geometry2D.intersect_polygons(sweep, body).is_empty():
					return true
	return false

func _exchange_context(person: Dictionary, occupied: Dictionary) -> Dictionary:
	var sectors := 0
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var next: Vector2i = person.cell + direction
		if not terrain.can_attack_across(person.cell, next):
			continue
		for other: Dictionary in occupied.get(next, []):
			if int(other.faction) != int(person.faction):
				sectors += 1
				break
	var person_owner: Variant = person.owner
	var index := int(person.unit)
	# Only named command-capable people use automatic skills. The controlled
	# person chooses Q/E, so AI never consumes their pending choice or cooldown.
	if int(person.id) != controlled_person_id():
		if index >= 0:
			if person_owner.command_abilities.has(index):
				person_owner.activate_exchange_skill(index, "brace" if sectors >= 2 else "power")
		elif not person_owner.command_abilities.is_empty():
			person_owner.activate_exchange_skill("brace" if sectors >= 2 else "power")
	var stats: Dictionary = person_owner.exchange_stats(index) if index >= 0 else person_owner.exchange_stats()
	stats.encirclement = sectors
	stats.facility = SiteRuntime.exchange_facility_bonus(terrain, person.cell)
	if site_controller != null:
		# Read the real feeding owner, including independent people and captives;
		# an empty former personal/team pool must not supply stale morale.
		stats.morale = _exchange_morale(int(person.id))
	return stats

func _resolve_exchanges() -> void:
	if terrain == null:
		return
	_exchange_round += 1
	var people := _exchange_people()
	if people.is_empty():
		return
	var occupied := {}
	for person: Dictionary in people:
		if not occupied.has(person.cell):
			occupied[person.cell] = []
		occupied[person.cell].append(person)
	var used := {}
	var pending: Array[Dictionary] = []
	# Rotate priority to avoid a permanent low-ID advantage in a crowded line.
	for offset in range(people.size()):
		var a: Dictionary = people[(offset + _exchange_round) % people.size()]
		if not bool(a.receive) or used.has(a.id):
			continue
		var matched := false
		for direction_offset in range(4):
			var next: Vector2i = a.cell + TerrainData.DIRECTIONS[(direction_offset + _exchange_round) % 4]
			if not terrain.can_attack_across(a.cell, next):
				continue
			for b: Dictionary in occupied.get(next, []):
				if not bool(b.receive) or used.has(b.id) or int(a.faction) == int(b.faction):
					continue
				if not (bool(a.ready) and _exchange_initiates(a, int(b.id))) and not (bool(b.ready) and _exchange_initiates(b, int(a.id))):
					continue # Peaceful worker/player neighbours do not spontaneously duel.
				var stats_a := _exchange_context(a, occupied)
				var stats_b := _exchange_context(b, occupied)
				var low := mini(int(a.id), int(b.id))
				var high := maxi(int(a.id), int(b.id))
				var noise := (low * 73856093) ^ (high * 19349663) ^ (_exchange_round * 83492791) ^ terrain.seed_value
				var roll := float(posmod(noise, 21) - 10) * (1.0 if int(a.id) == low else -1.0)
				pending.append({"a": a, "b": b, "stats_a": stats_a, "stats_b": stats_b,
					"result": SiteCombatRules.exchange_result(stats_a, stats_b, roll)})
				used[a.id] = true
				used[b.id] = true
				matched = true
				break
			if matched:
				break
	# Every pairing sees pre-resolution abilities/positions; each original
	# person participates once. Knockback still commits through original owners.
	for pair: Dictionary in pending:
		_apply_exchange_side(pair.a, pair.b, pair.result, pair.stats_a, 1)
		_apply_exchange_side(pair.b, pair.a, pair.result, pair.stats_b, -1)
		exchange_count += 1
		exchange_results[str(pair.result.kind)] += 1
		exchange_resolved.emit(int(pair.a.id), int(pair.b.id), pair.result)
	_resolve_ranged_fire(people)

func _resolve_ranged_fire(people: Array[Dictionary]) -> void:
	for person: Dictionary in people:
		var shooter_owner: Variant = person.owner
		var index := int(person.unit)
		# Pair resolution may have consumed readiness since this disposable list was built.
		if not (shooter_owner.exchange_ready(index) if index >= 0 else shooter_owner.exchange_ready()):
			continue
		if (float(shooter_owner.combat_units[index].get("ranged_cooldown", 0.0)) if index >= 0 else shooter_owner.ranged_cooldown) > 0.0:
			continue
		if index >= 0 and shooter_owner.is_member(index) and not shooter_owner.is_controlled_person(index) and shooter_owner.is_sustain_routed():
			continue # A rout does not become a new automatic ranged attack order.
		var profile: Dictionary = shooter_owner.ranged_profile(index) if index >= 0 else shooter_owner.ranged_profile()
		if profile.is_empty():
			continue
		var ammunition: Dictionary = shooter_owner.combat_units[index].get("cargo", {}) if index >= 0 else shooter_owner.ammo_inventory
		if int(ammunition.get(str(profile.ammo), 0)) < 1:
			continue # Empty quivers neither scan all targets nor reserve an automatic skill.
		var selected := {}
		var nearest := INF
		var close_threat := false
		for other: Dictionary in people:
			if int(person.faction) == int(other.faction):
				continue
			if not (other.owner.combat_can_act(int(other.unit)) if int(other.unit) >= 0 else other.owner.can_act()):
				continue # A melee result in this same decision tick may have incapacitated them.
			var separation: Vector2i = other.cell - person.cell
			if absi(separation.x) + absi(separation.y) <= 1 and terrain.can_attack_across(person.cell, other.cell):
				close_threat = true
				break # A nearby opponent forces close combat even while that opponent cools down.
			if not _exchange_initiates(person, int(other.id)):
				continue
			var distance := Vector2(separation).length_squared()
			if distance <= 1.0 or distance > float(profile.range) * float(profile.range) or distance >= nearest:
				continue
			if SiteCombatRules.ranged_line_clear(terrain, person.cell, other.cell):
				selected = other
				nearest = distance
		if close_threat or selected.is_empty():
			continue
		if int(person.id) != controlled_person_id():
			if index >= 0 and shooter_owner.command_abilities.has(index):
				shooter_owner.activate_exchange_skill(index, "power")
			elif index < 0 and not shooter_owner.command_abilities.is_empty():
				shooter_owner.activate_exchange_skill("power")
		var fired: bool = shooter_owner.ranged_fire(index, selected.cell, ranged_shots + 1) if index >= 0 else shooter_owner.ranged_fire(selected.cell, ranged_shots + 1)
		if fired:
			ranged_shots += 1
