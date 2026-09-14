extends "res://scripts/tests/site_fatigue_threat_fast_test.gd"
## Same original Lab/TerrainData/people and forward eight-step BFS oracle.
## Inherits the existing 17s synchronous / 18s timer / 20s helper bounds.
## Both candidate settings run every old case and these two-hop boundaries.

var two_hop_checks := 0
var two_hop_fallbacks := 0

func _check(cell: Vector2i, expected: bool, label: String, path: int = -1) -> Dictionary:
	assert(Time.get_ticks_usec() < deadline_usec, "Original bounded threat test deadline")
	var original := _reference(cell, lab.character.faction_id)
	assert(original == expected, label + ": fixture must match the real forward graph")
	var result := {}
	for enabled: bool in [false, true]:
		lab.fatigue_two_hop_witness_enabled = enabled
		var candidates := {}
		var actual := lab._fatigue_threat(cell, lab.character.faction_id, lab.character, -1, candidates)
		assert(actual == original, "%s: two-hop=%s original=%s actual=%s" % [label, enabled, original, actual])
		if path >= 0:
			assert(candidates.has(lab.character.faction_id))
			var searched: bool = candidates[lab.character.faction_id].has("reachable")
			# path=2 requires the old BFS and a NEW exact positive witness.
			assert(searched == (path == 1 or (path == 2 and not enabled)), label + ": wrong early-return/fallback path")
			if searched:
				fallback_checks += 1
			else:
				assert(actual)
				positive_fast_checks += 1
		if enabled:
			result = candidates
	if path == 2:
		two_hop_checks += 1
	elif path == 1:
		two_hop_fallbacks += 1
	checks += 1
	return result

func _actor_cases() -> void:
	super._actor_cases()
	_flat()
	assert(lab.npc.place(QUERY + Vector2i.RIGHT * 2, true))
	_check(QUERY, true, "two-cell enemy after a front-line gap", 2)
	for field: String in ["hp", "knockout_left", "captive", "_getting_up", "faction_id"]:
		var prior: Variant = lab.npc.get(field)
		lab.npc.set(field, {"hp": 0.0, "knockout_left": 1.0, "captive": true, "_getting_up": true, "faction_id": lab.character.faction_id}[field])
		_check(QUERY, false, "two-hop source excluded by " + field)
		lab.npc.set(field, prior)
	assert(lab.npc.step(Vector2i.RIGHT))
	var candidates := _check(QUERY, true, "moving Actor old cell is two, destination three", 2)
	assert(candidates[lab.character.faction_id].cells.has(QUERY + Vector2i.RIGHT * 2))
	assert(candidates[lab.character.faction_id].cells.has(QUERY + Vector2i.RIGHT * 3))
	lab.npc._advance_movement(lab.npc._movement_duration)
	_check(QUERY, true, "next query cannot reuse completed two-cell source", 1)
	assert(lab.npc.step(Vector2i.LEFT))
	_check(QUERY, true, "moving Actor new destination is two, source three", 2)
	lab.npc._advance_movement(lab.npc._movement_duration)

func _terrain_cases() -> void:
	super._terrain_cases()
	_flat()
	assert(lab.npc.place(QUERY + Vector2i.RIGHT * 2, true))
	data.static_blocked[data.index(QUERY + Vector2i.RIGHT)] = 1
	_check(QUERY, true, "blocked straight middle requires a four-edge detour", 1)
	for y: int in data.size.y:
		data.static_blocked[data.index(Vector2i(QUERY.x + 1, y))] = 1
	_check(QUERY, false, "two-cell enemy across a complete wall", 1)
	data.static_blocked[data.index(QUERY + Vector2i(1, 1))] = 0
	_check(QUERY, true, "wall opening beyond the two-hop witness still uses BFS", 1)
	_flat()
	assert(lab.npc.place(QUERY + Vector2i(1, 1), true))
	_check(QUERY, true, "diagonal enemy has two real cardinal routes", 2)
	data.static_blocked[data.index(QUERY + Vector2i.RIGHT)] = 1
	_check(QUERY, true, "one diagonal middle blocked retains the other route", 2)
	data.static_blocked[data.index(QUERY + Vector2i.DOWN)] = 1
	_check(QUERY, true, "both diagonal middles blocked require six real edges", 1)
	data.static_blocked[data.index(QUERY + Vector2i.UP)] = 1
	data.static_blocked[data.index(QUERY + Vector2i.LEFT)] = 1
	_check(QUERY, false, "diagonal proximity cannot cross a sealed corner", 1)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		_flat()
		var middle := QUERY + direction
		var enemy := QUERY + direction * 2
		assert(lab.npc.place(enemy, true))
		data.height_levels[data.index(middle)] = 1
		data.height_levels[data.index(enemy)] = 2
		var toward_enemy := TerrainData.DIRECTIONS.find(direction)
		var toward_query := TerrainData.DIRECTIONS.find(-direction)
		data.ramp_edges[data.index(enemy)] = 1 << toward_query
		_check(QUERY, false, "one-ended source ramp is not permission %s" % direction, 1)
		data.ramp_edges[data.index(middle)] = (1 << toward_enemy) | (1 << toward_query)
		assert(data.can_step(enemy, middle) and not data.can_step(middle, QUERY))
		_check(QUERY, false, "second edge still needs its reciprocal ramp %s" % direction, 1)
		data.ramp_edges[data.index(QUERY)] = 1 << toward_enemy
		assert(data.can_step(enemy, middle) and data.can_step(middle, QUERY))
		_check(QUERY, true, "actual two-level reciprocal stair descent %s" % direction, 2)
		# TerrainData has no legal one-way ramp: exercise reversed elevations
		# on the real reciprocal rule, not an invented asymmetric mock graph.
		data.height_levels.fill(2)
		data.height_levels[data.index(middle)] = 1
		data.height_levels[data.index(enemy)] = 0
		assert(data.can_step(enemy, middle) and data.can_step(middle, QUERY))
		_check(QUERY, true, "actual reciprocal stair ascent %s" % direction, 2)
		data.static_blocked[data.index(middle)] = 1
		_check(QUERY, false, "blocked ramp middle rejects the witness %s" % direction, 1)
	_flat()

func _army_cases() -> void:
	super._army_cases()
	_flat()
	var team := lab.army
	team.combat_enabled = true
	team.faction_id = 1
	var member: Dictionary = team.combat_units[0]
	var source := team.cells[0]
	var destination := team.moving_to[0]
	assert(destination == source + Vector2i.LEFT)
	_check(source + Vector2i.RIGHT * 2, true, "Army moving source two, destination three", 2)
	_check(destination + Vector2i.LEFT * 2, true, "Army moving destination two, source three", 2)
	for field: String in ["hp", "ko", "captive", "departed", "pose"]:
		var prior: Variant = member[field]
		member[field] = {"hp": 0.0, "ko": 1.0, "captive": true, "departed": true, "pose": "get_up"}[field]
		_check(source + Vector2i.RIGHT * 2, false, "two-hop Army excludes " + field)
		member[field] = prior
	# One original front row actually enters the existing death path. It is
	# retained at the middle cell; the threat rule remains TerrainData walking,
	# not a new corpse-obstacle rule or a claim of full death/loot acceptance.
	assert(team.cells[1] == source + Vector2i.RIGHT)
	team.apply_unit_contact(1, {"environmental": true, "shield": false,
		"result": {"hp": float(team.combat_units[1].hp), "stun": 0.0, "guard_break": false}})
	assert(float(team.combat_units[1].hp) == 0.0 and str(team.combat_units[1].pose) == "down")
	assert(not team.combat_can_act(1) and data.can_step(source, team.cells[1]))
	_check(source + Vector2i.RIGHT * 2, true, "actual dead front row leaves a two-cell enemy gap", 2)
	member.member = false
	_check(source + Vector2i.RIGHT * 2, true, "independent actual row remains a two-hop threat", 2)
	member.member = true
	team.combat_enabled = false

func _projectile_cases() -> void:
	super._projectile_cases() # Both A/B flags also run unchanged live/expired/blocked arrows.
	assert(two_hop_checks >= 16 and two_hop_fallbacks > 0)
	print("TWO HOP EXACT MATRIX: new witnesses=", two_hop_checks,
		" retained BFS cases=", two_hop_fallbacks,
		"; both settings compared to original forward eight-step BFS; original reciprocal ramps, no fabricated one-way graph")
