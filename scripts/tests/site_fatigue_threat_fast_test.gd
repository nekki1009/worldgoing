extends SceneTree
## Original Lab query versus the original forward multi-source eight-step BFS.
## Headless: no substitute collider, enemy body, movement owner or clock.

var lab: TerrainLab
var data: TerrainData
var checks := 0
var positive_fast_checks := 0
var fallback_checks := 0
var deadline_usec := 0
const QUERY := Vector2i(20, 20)

func _initialize() -> void:
	run.call_deferred()

func _flat() -> void:
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)

func _seeds(faction: int) -> Dictionary:
	var seeds := {}
	for actor: TerrainTestCharacter in lab.combat_actors:
		if actor.faction_id != faction and actor.can_act():
			seeds[actor.terrain_cell] = true
			if actor.is_moving():
				seeds[actor.movement_from_cell] = true
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled or team.faction_id == faction:
			continue
		for index in range(team.combat_units.size()):
			if team.combat_can_act(index):
				seeds[team.cells[index]] = true
				if team.moving_to[index] != TerrainArmy.INVALID_CELL:
					seeds[team.moving_to[index]] = true
	return seeds

func _reference(cell: Vector2i, faction: int) -> bool:
	if not data.is_walkable(cell):
		return true
	var distances := {}
	var pending: Array[Vector2i] = []
	for enemy: Vector2i in _seeds(faction):
		distances[enemy] = 0
		pending.append(enemy)
	var cursor := 0
	while cursor < pending.size():
		var current := pending[cursor]
		cursor += 1
		if int(distances[current]) == 8:
			continue
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := current + direction
			if not distances.has(next) and data.can_step(current, next):
				distances[next] = int(distances[current]) + 1
				pending.append(next)
	if distances.has(cell):
		return true
	# The unchanged original headless branch conservatively disallows rest for
	# a live projectile with an unobstructed terrain line. No fake body polygon.
	assert(lab.character.editor == null)
	for actor: TerrainTestCharacter in lab.combat_actors:
		for arrow: Dictionary in actor.projectiles:
			if float(arrow.remaining) > 0.0 and SiteCombatRules.terrain_line_clear(data, Vector2i((arrow.ground as Vector2) / TerrainRenderer.CELL_PIXELS), cell):
				return true
	return false

func _check(cell: Vector2i, expected: bool, label: String, path: int = -1) -> Dictionary:
	assert(Time.get_ticks_usec() < deadline_usec, "Bounded synchronous threat test exceeded 17 seconds")
	var candidates := {}
	var original := _reference(cell, lab.character.faction_id)
	var actual := lab._fatigue_threat(cell, lab.character.faction_id, lab.character, -1, candidates)
	assert(original == expected and actual == original, "%s: expected=%s original=%s actual=%s" % [label, expected, original, actual])
	if path >= 0:
		assert(candidates.has(lab.character.faction_id))
		var searched: bool = candidates[lab.character.faction_id].has("reachable")
		assert(searched == (path == 1), "%s must %s the original BFS" % [label, "reach" if path == 1 else "bypass"])
		if path == 1:
			fallback_checks += 1
		else:
			assert(actual)
			positive_fast_checks += 1
	checks += 1
	return candidates

func _actor_cases() -> void:
	assert(lab.character.place(QUERY, true))
	lab.npc.faction_id = 1
	for distance: int in [1, 8, 9]:
		assert(lab.npc.place(QUERY + Vector2i.RIGHT * distance, true))
		_check(QUERY, distance <= 8, "actor distance %d" % distance, 0 if distance == 1 else 1 if distance == 8 else -1)
	# Exercise the primitive's distance-zero query without spawning two people
	# in the same occupied cell. With no projectile, owner geometry is irrelevant.
	_check(lab.npc.terrain_cell, true, "same-cell positive witness", 0)
	assert(lab.npc.place(QUERY + Vector2i.RIGHT, true))
	for field: String in ["hp", "knockout_left", "captive", "_getting_up", "faction_id"]:
		var original: Variant = lab.npc.get(field)
		lab.npc.set(field, {"hp": 0.0, "knockout_left": 1.0, "captive": true, "_getting_up": true, "faction_id": lab.character.faction_id}[field])
		_check(QUERY, false, "actor excluded by " + field)
		lab.npc.set(field, original)
	_check(QUERY, true, "same original actor restored", 0)
	# Real committed Actor movement records terrain_cell=destination and keeps
	# movement_from_cell as an equally valid enemy seed until the step completes.
	assert(lab.npc.place(QUERY + Vector2i.RIGHT * 8, true) and lab.npc.step(Vector2i.RIGHT))
	assert(lab.npc.is_moving())
	var candidates := _check(QUERY, true, "moving actor old cell remains distance eight", 1)
	assert(candidates[lab.character.faction_id].cells.has(QUERY + Vector2i.RIGHT * 8))
	assert(candidates[lab.character.faction_id].cells.has(QUERY + Vector2i.RIGHT * 9))
	lab.npc._advance_movement(lab.npc._movement_duration)
	_check(QUERY, false, "completed actor step removes old seed")
	assert(lab.npc.step(Vector2i.LEFT))
	_check(QUERY, true, "moving actor destination becomes distance eight", 1)
	lab.npc._advance_movement(lab.npc._movement_duration)

func _terrain_cases() -> void:
	_flat()
	assert(lab.npc.place(QUERY + Vector2i.RIGHT * 2, true))
	for y in range(data.size.y):
		data.static_blocked[data.index(Vector2i(QUERY.x + 1, y))] = 1
	_check(QUERY, false, "full wall denies a nearby enemy", 1)
	data.static_blocked[data.index(QUERY + Vector2i(1, 1))] = 0
	_check(QUERY, true, "detour uses original BFS after fast proof fails", 1)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		_flat()
		var enemy := QUERY + direction
		assert(lab.npc.place(enemy, true))
		data.height_levels[data.index(enemy)] = 1
		var toward_query := TerrainData.DIRECTIONS.find(-direction)
		var toward_enemy := TerrainData.DIRECTIONS.find(direction)
		assert(not data.can_step(enemy, QUERY))
		_check(QUERY, false, "one-level isolated cliff %s" % direction, 1)
		data.ramp_edges[data.index(enemy)] = 1 << toward_query
		assert(not data.can_step(enemy, QUERY) and not data.can_step(QUERY, enemy))
		_check(QUERY, false, "one-ended ramp is not a directed permission %s" % direction, 1)
		data.ramp_edges[data.index(QUERY)] = 1 << ((toward_enemy + 1) % 4)
		_check(QUERY, false, "wrong-facing reciprocal ramp %s" % direction, 1)
		data.ramp_edges[data.index(QUERY)] = 1 << toward_enemy
		assert(data.can_step(enemy, QUERY) and data.can_step(QUERY, enemy))
		_check(QUERY, true, "actual reciprocal descent %s" % direction, 0)
		# TerrainData's real ramp rule is reciprocal, not a fabricated one-way
		# graph: reverse the heights and test its legal ascent as well.
		data.height_levels.fill(1)
		data.height_levels[data.index(enemy)] = 0
		assert(data.can_step(enemy, QUERY))
		_check(QUERY, true, "actual reciprocal ascent %s" % direction, 0)
		data.height_levels.fill(0)
		data.height_levels[data.index(enemy)] = 2
		_check(QUERY, false, "two-level cliff rejects even reciprocal bits %s" % direction, 1)
		data.height_levels.fill(0)
		data.static_blocked[data.index(enemy)] = 1
		_check(QUERY, false, "blocked source cannot prove adjacency %s" % direction, 1)
	_flat()
	data.static_blocked[data.index(QUERY)] = 1
	_check(QUERY, true, "nonwalkable resting cell retains original refusal")
	_flat()

func _army_cases() -> void:
	lab.npc.faction_id = lab.character.faction_id
	assert(lab.npc.place(Vector2i(40, 40), true))
	var team := lab.army
	assert(not team.has_army())
	var cells: Array[Vector2i] = []
	for index in range(100):
		cells.append(Vector2i(60 + index % 10, 60 + floori(float(index) / 10.0)))
	assert(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false))
	team.set_process(false)
	team.faction_id = 1
	# All 100 original rows remain. A controlled KO fixture isolates one actual
	# moving row's seeds without erasing bodies or creating surrogate enemies.
	for member: Dictionary in team.combat_units:
		member.ko = 10.0
	var selected_row: Dictionary = team.combat_units[0]
	selected_row.ko = 0.0
	var source := team.cells[0]
	var destination := source + Vector2i.LEFT
	assert(team._reserve_combat_step(0, destination))
	_check(source, true, "moving Army source has distance-zero witness", 0)
	_check(destination, true, "moving Army destination has distance-zero witness", 0)
	var candidates := _check(Vector2i(67, 59), true, "Army source is eight while destination is nine", 1)
	assert(candidates[lab.character.faction_id].cells.has(source) and candidates[lab.character.faction_id].cells.has(destination))
	_check(Vector2i(51, 60), true, "Army destination is eight while source is nine", 1)
	for field: String in ["hp", "ko", "captive", "departed", "pose"]:
		var original: Variant = selected_row[field]
		selected_row[field] = {"hp": 0.0, "ko": 1.0, "captive": true, "departed": true, "pose": "get_up"}[field]
		_check(destination, false, "Army excluded by " + field)
		selected_row[field] = original
	selected_row.member = false
	_check(destination, true, "independent original row is still an actual threat", 0)
	selected_row.member = true
	team.faction_id = lab.character.faction_id
	_check(destination, false, "same-faction Army is not an enemy")
	team.faction_id = 1
	team.combat_enabled = false
	_check(destination, false, "disabled Army excluded")
	team.combat_enabled = true
	# Multiple original source owners, including a distant seed, retain the
	# same forward graph result. No synthetic candidate dictionary is injected.
	lab.npc.faction_id = 1
	assert(lab.npc.place(Vector2i(80, 59), true))
	_check(Vector2i(67, 59), true, "multiple original enemy owners", 1)
	team.combat_enabled = false
	lab.npc.faction_id = lab.character.faction_id

func _projectile_cases() -> void:
	# Same conservative headless fixture as site_fatigue_test.gd; this is not
	# projected arrow collision acceptance (the existing GPU suite owns that).
	assert(lab.character.place(QUERY, true))
	var ground := (Vector2(QUERY + Vector2i.LEFT * 2) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	lab.npc.projectiles.append({"position": ground, "velocity": Vector2.RIGHT * 420.0, "ground": ground, "remaining": 100.0})
	_check(QUERY, true, "no enemy witness still reaches original projectile refusal")
	lab.npc.projectiles[0].remaining = 0.0
	_check(QUERY, false, "expired projectile is not a threat")
	lab.npc.projectiles[0].remaining = 100.0
	data.static_blocked[data.index(QUERY + Vector2i.LEFT)] = 1
	_check(QUERY, false, "terrain-blocked projectile is not a threat")
	data.static_blocked.fill(0)
	lab.npc.projectiles.clear()

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	deadline_usec = Time.get_ticks_usec() + 17000000
	assert(DisplayServer.get_name() == "headless")
	lab = TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	for team: TerrainArmy in lab.combat_armies:
		team.set_process(false)
	lab.site_controller._auto_save_blocked = true
	data = lab.terrain
	lab.site_controller.release_worker()
	_flat()
	var clock := [data.site.minute, data.site.phase, data.site.combat_left]
	_actor_cases()
	_terrain_cases()
	_army_cases()
	_projectile_cases()
	assert(checks >= 50 and positive_fast_checks > 0 and fallback_checks > 0)
	assert([data.site.minute, data.site.phase, data.site.combat_left] == clock, "Read-only threat queries never advance the original Site clock")
	lab.queue_free()
	await process_frame
	print("SITE FATIGUE THREAT FAST PASS: checks=", checks, " positive_fast=", positive_fast_checks,
		" original_BFS_fallback=", fallback_checks,
		"; actual TerrainData reciprocal ramps/obstacles, original Actor+100 Army rows, original movement seeds and headless projectile fallback; not FPS")
	quit(0)
