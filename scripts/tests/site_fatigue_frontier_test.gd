extends "res://scripts/tests/site_fatigue_threat_fast_test.gd"
## Original forward eager oracle versus the same frontier paused/resumed.
## Reuses the real people, movement, ramps and 17/18/20-second headless fixture.

class ObservedTerrain extends TerrainData:
	var step_calls := 0
	var counting := true
	func can_step(from: Vector2i, to: Vector2i) -> bool:
		step_calls += int(counting)
		return super.can_step(from, to)

var observed: ObservedTerrain
var frontier_costs: Array[Dictionary] = []

func _observe_original_terrain() -> void:
	# Instrument the existing fixture's complete data, not a surrogate graph.
	# Site and its actual people remain the same; all queried owners use this
	# TerrainData subclass, whose only changed operation is counting super calls.
	observed = ObservedTerrain.new()
	for property: Dictionary in data.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			observed.set(property.name, data.get(property.name))
	assert(is_same(observed.site, data.site) and observed.height_levels == data.height_levels)
	data = observed
	lab.terrain = observed
	lab.renderer.data = observed
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.data = observed
	for team: TerrainArmy in lab.combat_armies:
		team.data = observed

func _complete_expanded_nodes(threat: Dictionary) -> void:
	assert(threat.has("reachable") and threat.has("pending") and threat.has("cursor"))
	var distances: Dictionary = threat.reachable
	var pending: Array[Vector2i] = threat.pending
	var cursor: int = threat.cursor
	assert(cursor >= 0 and cursor <= pending.size() and distances.size() == pending.size())
	# Verification calls are excluded from the production algorithm counter.
	observed.counting = false
	for position: int in cursor:
		var current := pending[position]
		if int(distances[current]) >= 8:
			continue
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := current + direction
			if data.can_step(current, next):
				assert(distances.has(next) and int(distances[next]) <= int(distances[current]) + 1,
					"A paused node must finish every original neighbor, not abandon directions after finding the target")
	observed.counting = true

func _sequence(cells: Array[Vector2i], expected: Array[bool], label: String, expect_early_saving: bool) -> void:
	assert(Time.get_ticks_usec() < deadline_usec and cells.size() == expected.size())
	var faction := lab.character.faction_id
	var seeds := _seeds(faction)
	assert(not seeds.is_empty())
	# No enemy is within the unchanged 0/1/2 witnesses in these cost cases.
	# Thus all counted can_step work is the frontier, not added witness overhead.
	for cell: Vector2i in cells:
		for enemy: Vector2i in seeds:
			var offset := enemy - cell
			assert(absi(offset.x) + absi(offset.y) > 2)
	var eager_calls := 0
	for index: int in cells.size():
		observed.step_calls = 0
		assert(_reference(cells[index], faction) == expected[index], label + ": original eager result")
		if index == 0:
			eager_calls = observed.step_calls
		else:
			assert(observed.step_calls == eager_calls, "Original eager BFS has one complete per-faction traversal independent of target order")
	assert(eager_calls > 0)
	observed.step_calls = 0
	var candidates := {}
	var first_calls := 0
	var previous_cursor := 0
	for index: int in cells.size():
		assert(lab._fatigue_threat(cells[index], faction, lab.character, -1, candidates) == expected[index], label + ": lazy result differs")
		var threat: Dictionary = candidates[faction]
		_complete_expanded_nodes(threat)
		assert(int(threat.cursor) >= previous_cursor, "Shared frontier must resume without rewinding")
		previous_cursor = int(threat.cursor)
		assert(observed.step_calls <= eager_calls, "All requests together must not exceed one original eager traversal")
		if index == 0:
			first_calls = observed.step_calls
			if expect_early_saving:
				assert(first_calls * 2 < eager_calls and int(threat.cursor) < threat.pending.size(),
					"Nearby positive must genuinely pause early and use less than half the original edge checks")
		if not expected[index]:
			assert(int(threat.cursor) == threat.pending.size(), "A ground-negative result must exhaust the original frontier")
	assert(observed.step_calls == eager_calls, "After a negative query, the shared traversal must have exactly the original eager edge count")
	frontier_costs.append({"case": label, "queries": cells.size(), "seeds": seeds.size(),
		"eager_can_step": eager_calls, "first_query_can_step": first_calls,
		"shared_lazy_can_step": observed.step_calls, "expanded": previous_cursor})

func _isolate(cell: Vector2i) -> void:
	for direction: Vector2i in TerrainData.DIRECTIONS:
		data.static_blocked[data.index(cell + direction)] = 1
	assert(data.is_walkable(cell))

func _actor_cases() -> void:
	_observe_original_terrain()
	super._actor_cases()
	_flat()
	var enemy := QUERY + Vector2i.RIGHT * 12
	assert(lab.npc.place(enemy, true))
	var near_cell := enemy + Vector2i.UP * 3
	var far_cell := enemy + Vector2i.RIGHT * 6
	var negative := enemy + Vector2i.LEFT * 4
	_isolate(negative)
	_sequence([near_cell, far_cell, negative, near_cell], [true, true, false, true], "single seed near/far/negative/retained", true)
	_sequence([negative, far_cell, near_cell, near_cell], [false, true, true, true], "single seed reversed order", false)
	# Each _check owns fresh candidates: original terrain/enemy mutations must
	# be visible on the next synchronous batch, never a cross-step result cache.
	_flat()
	_check(near_cell, true, "next batch original open terrain")
	for x: int in data.size.x:
		data.static_blocked[data.index(Vector2i(x, enemy.y - 1))] = 1
	_check(near_cell, false, "next batch actual barrier invalidates prior positive")
	_flat()
	data.height_levels[data.index(enemy)] = 1
	_check(near_cell, false, "next batch original cliff isolates seed")
	data.ramp_edges[data.index(enemy)] = 1 << TerrainData.DIRECTIONS.find(Vector2i.UP)
	data.ramp_edges[data.index(enemy + Vector2i.UP)] = 1 << TerrainData.DIRECTIONS.find(Vector2i.DOWN)
	_check(near_cell, true, "next batch actual reciprocal ramp restores reachability")
	data.ramp_edges[data.index(enemy + Vector2i.UP)] = 0
	_check(near_cell, false, "next batch broken reciprocal ramp is not permission")
	_flat()
	lab.npc.knockout_left = 1.0
	_check(near_cell, false, "next batch KO removes original seed")
	lab.npc.knockout_left = 0.0
	_check(near_cell, true, "next batch waking restores original seed")
	# The inherited matrix already checks live/dead/captive/faction and actual
	# Actor/Army movement source/destination removal on subsequent fresh batches.

func _army_cases() -> void:
	super._army_cases()
	_flat()
	var team := lab.army
	team.combat_enabled = true
	var knockout_values: Array[float] = []
	for row: Dictionary in team.combat_units:
		knockout_values.append(float(row.ko))
		row.ko = 0.0
	assert(team.combat_units.size() == 100 and team.moving_to[0] != TerrainArmy.INVALID_CELL)
	var near_cell := Vector2i(64, 57)
	var far_cell := Vector2i(74, 64)
	var negative := Vector2i(55, 64)
	_isolate(negative)
	_sequence([near_cell, far_cell, negative, near_cell], [true, true, false, true], "original 100 rows plus committed destination", true)
	_sequence([negative, far_cell, near_cell, far_cell], [false, true, true, true], "original 100 rows reversed order", false)
	for index: int in team.combat_units.size():
		team.combat_units[index].ko = knockout_values[index]
	team.combat_enabled = false
	_flat()

func _projectile_cases() -> void:
	super._projectile_cases()
	assert(lab.npc.place(QUERY + Vector2i.RIGHT * 4, true))
	lab.npc.faction_id = 1
	for y: int in data.size.y:
		data.static_blocked[data.index(Vector2i(QUERY.x + 1, y))] = 1
	var team := lab.army
	var original_faction := team.faction_id
	team.faction_id = lab.character.faction_id
	team.combat_enabled = true # Fix all enemy eligibility before this shared batch.
	var candidates := {}
	assert(not lab._fatigue_threat(QUERY, lab.character.faction_id, lab.character, -1, candidates))
	assert(candidates[lab.character.faction_id].cursor == candidates[lab.character.faction_id].pending.size())
	var ground := (Vector2(QUERY + Vector2i.LEFT * 2) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	lab.npc.projectiles.append({"position": ground, "velocity": Vector2.RIGHT * 420.0, "ground": ground, "remaining": 100.0})
	assert(lab._fatigue_threat(QUERY, lab.character.faction_id, lab.character, -1, candidates), "Exhausted ground-negative frontier must still inspect the current original projectile")
	# This is the real headless owner distinction, not a fake body polygon:
	# Actor without projection conservatively refuses rest; original Army row0
	# without its live presenter returns no projected shapes. GPU hit coverage
	# remains in the existing visual projectile tests, not this headless claim.
	assert(team.combat_shapes(0, "body").is_empty())
	assert(not lab._fatigue_threat(QUERY, lab.character.faction_id, team, 0, candidates), "Do not cache another owner's projectile result in the per-faction ground frontier")
	lab.npc.projectiles[0].remaining = 0.0
	assert(not lab._fatigue_threat(QUERY, lab.character.faction_id, lab.character, -1, candidates), "Expired original projectile must not remain cached as a threat")
	lab.npc.projectiles.clear()
	team.combat_enabled = false
	team.faction_id = original_faction
	_flat()
	assert(frontier_costs.size() == 4)
	print("SITE FATIGUE FRONTIER EXACT: ", JSON.stringify(frontier_costs),
		"; original complete-node forward queue, shared/resumed eager-equivalent costs, next-batch terrain/seeds and live owner-specific headless projectile fallback; not GPU collision/FPS")
