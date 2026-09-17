extends SceneTree

const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE := "res://.godot-temp/site_combat/army-state.json"

func _initialize() -> void:
	if "--retain-animation-cache" in OS.get_cmdline_user_args():
		preload("res://scripts/tests/fixtures/animation_cache_lifecycle_install.gd").install()
	call_deferred("run")

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "army-command-fixture")
	# Make the fixture changes persistent, so Store reconstructs the same terrain.
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.site.terrain_changes[str(index)] = 0
	SiteRuntime.rebuild_terrain_edges(data)
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	var selected: Array[Vector2i] = []
	# Existing legal connected ground only; no actor nodes or visual substitutes.
	for cell: Vector2i in team_placement(data):
		selected.append(cell)
	assert(selected.size() == 100)
	assert(team.deploy_at(data, null, null, selected))
	assert(team.enable_combat(false))
	if "--retain-animation-cache" in OS.get_cmdline_user_args():
		preload("res://scripts/tests/fixtures/animation_cache_lifecycle_install.gd").assert_captain(team)
	assert(team.formal_commander == 0 and team.command_abilities.size() == 1)
	var original_cells := team.cells.duplicate()
	var original_abilities: Dictionary = team.command_abilities[0].duplicate()
	team.officer_order.assign([1, 2])
	knockout(team, 0)
	team.settle_combat_command()
	assert(team.formal_commander == 0 and team.acting_commander == 1 and team.current_commander == 1)
	assert(team.cells == original_cells and team.command_abilities.size() == 2, "Role handover cannot move a person or generate all soldiers' abilities")
	knockout(team, 1)
	team.settle_combat_command()
	assert(team.current_commander == 2)
	team.combat_units[1].ko = 0.0
	team.combat_units[1].pose = "idle"
	team._cell_owners[team.cells[1]] = 1
	team._command_dirty = true
	team.settle_combat_command()
	assert(team.current_commander == 2, "Recovered higher-priority officer must not replace an eligible acting commander")
	team.apply_unit_contact(0, {"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
	team.settle_combat_command()
	assert(team.formal_commander == 2 and team.acting_commander == -1 and team.current_commander == 2, "Eligible acting commander directly succeeds the deceased formal commander")
	assert(team.command_abilities[0] == original_abilities and not team.officer_order.has(2))
	var rng_before := team.command_rng.state
	team._command_dirty = true
	team.settle_combat_command()
	assert(team.command_rng.state == rng_before, "Duplicate state notification must not re-elect")
	assert(not team.issue_combat_order(1, TerrainArmy.CombatOrder.ATTACK).ok)
	assert(team.issue_combat_order(2, TerrainArmy.CombatOrder.ATTACK).ok)
	for index in range(1, 100):
		knockout(team, index)
	team.settle_combat_command()
	assert(team.current_commander == -1 and team.needs_attack_order and not team.combat_attacking and team.combat_order == TerrainArmy.CombatOrder.HOLD)
	# Only one eligible ordinary member: random selection cannot nominate an
	# incapacitated person, and must keep the original living formal relationship.
	team.combat_units[99].ko = 0.0
	team.combat_units[99].pose = "idle"
	team._cell_owners[team.cells[99]] = 99
	team._command_dirty = true
	team.settle_combat_command()
	assert(team.current_commander == 99 and team.formal_commander == 2 and team.acting_commander == 99)
	assert(team.needs_attack_order and not team.combat_attacking, "Restoring command cannot resume an old attack order")
	assert(team.command_abilities.size() == 4)
	assert(team.issue_combat_order(99, TerrainArmy.CombatOrder.ATTACK).ok and not team.needs_attack_order)
	assert(team.issue_combat_order(99, TerrainArmy.CombatOrder.HOLD).ok)
	assert(not team.reorder_officers(99, [1]).ok, "Acting commander cannot edit officer priority")
	# Committed movement remains an original TerrainArmy claim, including save.
	var step := Vector2i(-1, -1)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var next := team.cells[99] + direction
		if data.can_step(team.cells[99], next) and not team.blocks_cell(next):
			step = next
			break
	assert(step.x >= 0 and team._reserve_combat_step(99, step))
	team.prepare_combat(0.1)
	team.settle_combat_command()
	team.combat_units[99].fatigue = 78.5
	team.combat_units[99].fatigue_rest = 14.25
	team.combat_units[99].attack_reduction = 0.1
	team.combat_units[99].attack_fatigue = 0.25
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(team.capture_combat_state()))
	assert(TerrainArmy.valid_combat_state(snapshot, data), "Valid JSON army snapshot must pass")
	for field: String in ["fatigue", "fatigue_rest", "attack_reduction", "attack_fatigue"]:
		for bad: Variant in [-1, 101, "0", null, INF, NAN]:
			var invalid_fatigue: Dictionary = snapshot.duplicate(true)
			invalid_fatigue.units[99][field] = bad
			assert(not TerrainArmy.valid_combat_state(invalid_fatigue, data))
		var legacy: Dictionary = snapshot.duplicate(true)
		legacy.units[99].erase(field)
		assert(TerrainArmy.valid_combat_state(legacy, data))
	assert(typeof(snapshot.abilities[0]["values"].tactics) == TYPE_FLOAT, "Exercise the actual JSON numeric boundary")
	var broken: Dictionary = snapshot.duplicate(true)
	broken.current_commander = 98
	assert(not TerrainArmy.valid_combat_state(broken, data), "Incapacitated commander must be rejected, not repaired by re-election")
	broken = snapshot.duplicate(true)
	broken.units[0].hp = -1.0
	assert(not TerrainArmy.valid_combat_state(broken, data))
	broken = snapshot.duplicate(true)
	broken.officers = [1, 1]
	assert(not TerrainArmy.valid_combat_state(broken, data))
	for invalid: Variant in [-1, 101, 1.5, "9", null, NAN, INF]:
		broken = snapshot.duplicate(true)
		broken.abilities[0]["values"].tactics = invalid
		assert(not TerrainArmy.valid_combat_state(broken, data), "Reject invalid ability before integer normalization: %s" % str(invalid))
	data.site["army_trial_active"] = true
	data.site["army_next_team"] = 2
	data.site["actors"] = {}
	data.site["armies"] = [snapshot]
	data.site.combat_left = 10.0
	assert(not Store.save(data, SAVE).ok, "Army persistence cannot bypass combat save policy")
	data.site.combat_left = 0.0
	var saved := Store.save(data, SAVE)
	assert(saved.ok, str(saved))
	var loaded := Store.load_site(SAVE)
	assert(loaded.ok, str(loaded))
	var copy := TerrainArmy.new()
	root.add_child(copy)
	copy.set_process(false)
	copy.restore_combat_state(loaded.data.site.armies[0], loaded.data, null, null)
	if "--retain-animation-cache" in OS.get_cmdline_user_args():
		preload("res://scripts/tests/fixtures/animation_cache_lifecycle_install.gd").assert_captain(copy)
	assert(float(copy.combat_units[99].fatigue) == 78.5 and float(copy.combat_units[99].fatigue_rest) == 14.25)
	assert(float(copy.combat_units[99].attack_reduction) == 0.1 and float(copy.combat_units[99].attack_fatigue) == 0.25)
	assert(copy.cells == team.cells and copy.moving_to == team.moving_to)
	assert(copy.move_progress.size() == team.move_progress.size())
	for index: int in team.move_progress.size():
		# Progress now uses the original actor's float64 precision. Decimal JSON
		# may round one ULP; exact cell/claim/identity checks remain unchanged.
		assert(absf(copy.move_progress[index] - team.move_progress[index]) < 0.000000000000001, "Movement progress changed at %d: %.17f != %.17f" % [index, copy.move_progress[index], team.move_progress[index]])
	assert(copy.current_commander == 99 and copy.formal_commander == 2 and copy.command_rng.state == team.command_rng.state)
	for index: int in team.command_abilities:
		for kind: String in ["tactics", "leadership", "coach"]:
			assert(typeof(copy.command_abilities[index][kind]) == TYPE_INT, "Restored %d/%s must remain an integer" % [index, kind])
	assert(copy.command_abilities == team.command_abilities, "Restored abilities changed: %s != %s" % [str(copy.command_abilities), str(team.command_abilities)])
	assert(float(copy.combat_units[0].hp) == 0.0, "Loading revived a dead member")
	assert(float(copy.combat_units[1].ko) == float(team.combat_units[1].ko), "KO timer changed: %.17f != %.17f" % [float(copy.combat_units[1].ko), float(team.combat_units[1].ko)])
	assert(copy.blocks_cell(step) and copy.blocks_cell(copy.cells[99]), "Restore must retain source and destination claims")
	copy.prepare_combat(0.3)
	assert(copy.cells[99] == step and copy.moving_to[99] == TerrainArmy.INVALID_CELL)
	assert(float(copy.combat_units[99].hp) == float(team.combat_units[99].hp), "Load and move cannot heal")
	var duplicate: Dictionary = data.site.duplicate(true)
	duplicate.armies.append(snapshot.duplicate(true))
	assert(not Store._validate_armies(data, duplicate).ok)
	# Restore is idempotent, including command RNG and abilities.
	copy.restore_combat_state(snapshot, data, null, null)
	if "--retain-animation-cache" in OS.get_cmdline_user_args():
		preload("res://scripts/tests/fixtures/animation_cache_lifecycle_install.gd").assert_captain(copy)
	assert(copy.command_rng.state == team.command_rng.state and copy.command_abilities.size() == 4)
	assert(copy.command_abilities == team.command_abilities, "Repeated restore changed ability values or types")
	copy.clear()
	team.clear()
	copy.queue_free()
	team.queue_free()
	await process_frame
	print("SITE ARMY COMMAND SAVE PASS: priority/acting/permanent succession, no role teleport, sparse ability RNG, vacancy latch, authority, movement claims, format3 no-heal roundtrip, corrupt/duplicate rejection")
	quit(0)

func knockout(team: TerrainArmy, index: int) -> void:
	team.apply_unit_contact(index, {"result": {"hp": 1.25, "stun": 110.0, "guard_break": false}, "shield": false})

func team_placement(data: TerrainData) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(20, 40):
		for x in range(20, 40):
			var cell := Vector2i(x, y)
			if data.is_walkable(cell):
				result.append(cell)
				if result.size() == 100:
					return result
	return result
