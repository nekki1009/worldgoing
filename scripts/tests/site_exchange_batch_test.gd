extends "res://scripts/tests/site_army_scale_rules_test.gd"
## Exact query/owner parity, not a substitute gameplay scene or FPS measurement.
const Snapshot = preload("res://scripts/terrain_lab/site_exchange_snapshot.gd")

func _require(condition: bool, message: String) -> bool:
	if not condition: push_error(message)
	return condition

func _run() -> void:
	var kernel_script: Script = load("res://scripts/terrain_lab/compiled_exchange_candidates.cs")
	if not _require(kernel_script.can_instantiate(), "Build the real C# candidate kernel before verification"):
		quit(1); return
	var kernel: RefCounted = kernel_script.new()
	if not _check_kernel(kernel): quit(1); return
	var army_script := load("res://scripts/terrain_lab/terrain_army.gd") as GDScript
	var guard := "selected.size() > MAX_ROSTER_SIZE"
	if not _require(army_script.source_code.count(guard) == 1, "Unique in-memory deployment guard"):
		quit(1); return
	army_script.source_code = army_script.source_code.replace(guard, "selected.size() > 2500")
	if not _require(army_script.reload(true) == OK, "Load scale fixture"):
		quit(1); return
	for per_team in [100, 2500]:
		if not _check_owners(per_team): quit(1); return
	if not _check_owners(100, false): quit(1); return
	print("EXCHANGE_BATCH_PASS native/fallback/brute query order; original full owner state and events")
	quit(0)

func _check_kernel(kernel: RefCounted) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 419581
	for trial in range(100):
		var columns := Snapshot.new()
		var count := rng.randi_range(0, 140)
		for i in range(count):
			columns.xs.append(rng.randi_range(-6, 6))
			columns.ys.append(rng.randi_range(-6, 6))
			columns.factions.append(rng.randi_range(-2, 3) * (4294967296 if trial % 3 == 0 else 1))
			columns.units.append(i)
		var round_id := 2147483647 + trial if trial % 2 == 0 else trial
		var expected := PackedInt32Array()
		for offset in range(count):
			var i := (offset + round_id) % count
			for j in range(count):
				if columns.factions[i] != columns.factions[j] and absi(columns.xs[i] - columns.xs[j]) + absi(columns.ys[i] - columns.ys[j]) == 1:
					expected.append(i)
					break
		if not _require(columns.front_order(round_id, kernel) == expected and columns.front_order(round_id, null) == expected,
			"Native/fallback broad-phase order differs from independent brute force: trial %d" % trial): return false
	print("EXCHANGE_COLUMNS_PASS 100 seeded layouts, mixed factions in one cell, empty sets, negative cells, large round")
	return true

func _actor_state(actor: TerrainTestCharacter) -> Array:
	return [actor.capture_state(), actor.person_id, actor.terrain_cell, actor.movement_from_cell, actor.position,
		actor.hp, actor.stun, actor.knockout_left, actor.exchange_cooldown, actor.exchange_stagger,
		actor.exchange_skill_cooldown, actor.ranged_cooldown, actor.fatigue, actor.fatigue_rest,
		actor.ammo_inventory.duplicate(true), actor.projectiles.duplicate(true)]

func _mixed_actors(lab: TerrainLab, events: Array) -> void:
	var cells: Array[Vector2i] = [Vector2i(40, 10), Vector2i(46, 10), Vector2i(43, 10), Vector2i(49, 10)]
	for i in range(cells.size()):
		var actor := TerrainTestCharacter.new()
		actor.data = lab.terrain
		actor.exchange_enabled = true
		actor.person_id = 900001 + i
		actor.faction_id = 1 if i == 1 else 0
		actor.ammo_inventory = {"arrow": 20, "bolt": 20} if i == 0 else {}
		actor._saved_appearance = {"parts": {"weapon": "bow_01" if i == 0 else "longsword_01"}}
		assert(actor.place(cells[i], true))
		lab.combat_actors.append(actor)
	lab.character = lab.combat_actors[0]
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.attack_target_id = 900002 if actor.faction_id == 0 else 900001
	# A melee signal can equip/replenish an initially empty distant original actor.
	# The new ranged gate must read AFTER that signal, not before pairing.
	lab.exchange_resolved.connect(func(a: int, b: int, result: Dictionary) -> void:
		events.append(["melee", a, b, result.duplicate(true)])
		var rear := lab.combat_actors[1]
		rear._saved_appearance = {"parts": {"weapon": "crossbow_01"}}
		rear.ammo_inventory["bolt"] = 20)
	lab.ranged_resolved.connect(func(a: int, b: int, result: Dictionary) -> void:
		events.append(["ranged", a, b, result.duplicate(true)]))

func _check_owners(per_team: int, native: bool = true) -> bool:
	var baseline := _fixture(false, per_team, true)
	var candidate := _fixture(false, per_team, true)
	baseline.exchange_batch_enabled = false
	for team: TerrainArmy in baseline.combat_armies: team.native_queries_enabled = false
	candidate._exchange_kernel_checked = not native
	var before_events: Array = []
	var after_events: Array = []
	_mixed_actors(baseline, before_events)
	_mixed_actors(candidate, after_events)
	var steps := 120 if per_team == 100 else 36
	for step in range(steps):
		for lab: TerrainLab in [baseline, candidate]:
			# Cover fresh dynamic terrain/faction/KO/gear state, never cross-tick caching.
			if step == 12:
				lab.terrain.static_blocked[lab.terrain.index(Vector2i(50, 12))] = 1
				lab.combat_armies[0].combat_units[20].ko = 0.05
			if step == 24:
				lab.terrain.static_blocked[lab.terrain.index(Vector2i(50, 12))] = 0
				lab.combat_actors[2].faction_id = 1
			lab._advance_combat(1.0 / 30.0)
		var same := var_to_bytes(_state(baseline)) == var_to_bytes(_state(candidate)) and var_to_bytes(before_events) == var_to_bytes(after_events)
		for i in range(4): same = same and var_to_bytes(_actor_state(baseline.combat_actors[i])) == var_to_bytes(_actor_state(candidate.combat_actors[i]))
		for side in range(2):
			var a: TerrainArmy = baseline.combat_armies[side]
			var b: TerrainArmy = candidate.combat_armies[side]
			same = same and a.combat_slots == b.combat_slots and a._reserved_cells == b._reserved_cells and a._cell_owners == b._cell_owners and a.command_rng.state == b.command_rng.state
		if not _require(same, "Batch query changed full original state/events: %d people step %d" % [per_team * 2, step]):
			_cleanup_mixed(baseline); _cleanup_mixed(candidate); return false
	var okay := _require((candidate._exchange_kernel != null) == native and candidate.exchange_count > 0 and candidate.ranged_shots > 0 and candidate.ranged_resolutions > 0,
		"Must exercise compiled kernel, real melee and resolved ranged events")
	var native_rows := 0
	for team: TerrainArmy in candidate.combat_armies: native_rows += team.native_query_rows
	for team: TerrainArmy in baseline.combat_armies:
		okay = _require(team.native_query_rows == 0, "Reference must use the original GD capture") and okay
	okay = _require(native_rows > 0, "Candidate must exercise the new native captures") and okay
	print("EXCHANGE_OWNER_PARITY native=", native, " people=", per_team * 2, "+4 actors steps=", steps,
		" melee=", candidate.exchange_count, " shots=", candidate.ranged_shots, " arrivals=", candidate.ranged_resolutions, " native_query_rows=", native_rows)
	_cleanup_mixed(baseline)
	_cleanup_mixed(candidate)
	return okay

func _cleanup_mixed(lab: TerrainLab) -> void:
	for actor: TerrainTestCharacter in lab.combat_actors: actor.free()
	_dispose(lab)
