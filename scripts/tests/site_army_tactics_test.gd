extends SceneTree

var data: TerrainData
var lab: TerrainLab
var team: TerrainArmy
var enemy: TerrainArmy

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(14.0).timeout.connect(func() -> void: quit(1))
	data = TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "army-tactics-fixture")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	lab = TerrainLab.new() # No full scene or GPU in this navigation contract.
	lab.terrain = data
	team = TerrainArmy.new()
	enemy = TerrainArmy.new()
	# Navigation regression uses the formal mode, without an unused exact 3D
	# contact source that cannot validate shader materials in a headless renderer.
	team.exchange_enabled = true
	enemy.exchange_enabled = true
	root.add_child(team)
	root.add_child(enemy)
	team.set_process(false)
	enemy.set_process(false)
	enemy.team_id = 2
	enemy.faction_id = 1
	lab.combat_armies.assign([team, enemy])
	team.external_blocker = enemy.blocks_cell
	enemy.external_blocker = team.blocks_cell
	team.target_query = lab._army_target
	reset_team()
	var original := team.cells.duplicate()
	var goal := Vector2i(team.command_reference.floor()) + Vector2i.RIGHT
	assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, goal).ok)
	advance(8.0)
	assert(team.combat_order == TerrainArmy.CombatOrder.HOLD, team.command_status)
	for index in range(100):
		assert(team.cells[index] == original[index] + Vector2i.RIGHT, "Dense formation failed to move without passing through allies: %d" % index)
	assert(team.occupied_count() == 100 and team.moving_count() == 0)
	print("TACTICS: 100-person legal formation move")

	reset_team()
	var vacant := team.cells[1]
	knockout(1)
	assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.ATTACK).ok)
	advance(0.6)
	assert(int(team._vacancy_assignments.get(1, -1)) == 0, "Equal-cost filler must use stable person ID")
	advance(1.0)
	assert(team.cells[0] == vacant and team.cells[2] == Vector2i(22, 20))
	assert(team._vacancy_assignments.size() == 1, "An eligible filler must retain its destination")
	knockout(0)
	advance(1.5)
	assert(team.cells[2] == vacant, "A second casualty must permit a new legal filler")
	assert(team._vacancy_assignments.size() == 1, "Two fallen rows referencing one slot cannot reserve two replacements")
	print("TACTICS: cost/ID refill, persistent destination, replacement casualty")

	reset_team()
	team.combat_units[0].pose = "guard_break"
	team.combat_units[0].age = 0.0
	assert(not team._reserve_combat_step(0, team.cells[0] + Vector2i.LEFT), "Movement cannot cancel guard break")
	advance(0.5)
	assert(team._reserve_combat_step(0, team.cells[0] + Vector2i.LEFT))
	var committed := team.moving_to[0]
	goal = Vector2i(team.command_reference.floor()) + Vector2i.LEFT * 2
	assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.RETREAT, goal).ok)
	assert(team.moving_to[0] == committed, "A new order must preserve a committed edge")
	advance(0.3)
	assert(team.cells[0] != committed and team.moving_to[0] == committed,
		"The shared 0.38-second walk is still in flight after 0.3 seconds")
	# Attack supersedes retreat, but all already committed original edges must
	# still finish. The former 0.24-second fixture incorrectly assumed arrival.
	assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.ATTACK).ok)
	var line := team.cells.duplicate()
	for index: int in range(team.cells.size()):
		if team.moving_to[index] != TerrainArmy.INVALID_CELL:
			line[index] = team.moving_to[index]
	advance(1.0)
	assert(team.cells[0] == committed and team.cells == line and team.moving_count() == 0,
		"New attack order must finish original committed edges, not resume distant retreat goals")
	print("TACTICS: guard-break movement lock, committed edge, command supersession")

	reset_team()
	for y in range(data.size.y):
		data.static_blocked[data.index(Vector2i(32, y))] = 1
	original = team.cells.duplicate()
	assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.RETREAT, Vector2i(40, 24)).ok)
	advance(1.0)
	assert(team.combat_order == TerrainArmy.CombatOrder.HOLD and not team.combat_attacking)
	assert(team.cells == original and team.moving_count() == 0, "No route must mean self-defense, not teleportation")
	for y in range(data.size.y):
		data.static_blocked[data.index(Vector2i(32, y))] = 0
	print("TACTICS: unreachable retreat stops at legal cells")

	reset_team()
	# The 99 fallen members remain real rows; only soldier 1 can act. This
	# isolates pursuit timing from weapon geometry, which has a separate test.
	for index in range(100):
		if index != 1:
			team.apply_unit_contact(index, {"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
	team.settle_combat_command()
	var enemy_cells := placement(Vector2i(60, 20))
	enemy_cells[1] = Vector2i(22, 20)
	assert(enemy.deploy_at(data, null, null, enemy_cells) and enemy.enable_combat(false))
	var identity := enemy.combat_identity(1)
	assert(team.issue_combat_order(1, TerrainArmy.CombatOrder.PURSUE, TerrainArmy.INVALID_CELL, identity).ok)
	var start := team.cells[1]
	advance(19.5)
	assert(team.combat_order == TerrainArmy.CombatOrder.PURSUE and team.pursuit_left > 0.0, "Melee-range recovery is not a failed pursuit path")
	assert(team.cells[1] == start, "Pursuer must not try to occupy the enemy's cell")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(team.capture_combat_state()))
	assert(TerrainArmy.valid_combat_state(saved, data))
	team.restore_combat_state(saved, data, null, null)
	assert(is_equal_approx(team.pursuit_left, 0.5) and team.pursuit_target == identity)
	advance(0.6)
	assert(team.combat_order != TerrainArmy.CombatOrder.PURSUE and team.pursuit_left == 0.0 and not team.combat_attacking)
	advance(1.0)
	assert(team.combat_order == TerrainArmy.CombatOrder.HOLD and team.cells[1] == start, "Completed chase cannot automatically restart")
	print("TACTICS: actual 20-second chase limit, save/restore countdown, return/self-defense")

	assert(team.issue_combat_order(1, TerrainArmy.CombatOrder.PURSUE, TerrainArmy.INVALID_CELL, identity).ok)
	var paused_state := JSON.stringify(team.capture_combat_state())
	paused = true
	advance(2.0)
	assert(JSON.stringify(team.capture_combat_state()) == paused_state, "Pause must freeze movement, action and chase clocks")
	assert(not team.issue_combat_order(1, TerrainArmy.CombatOrder.RETREAT, start + Vector2i.LEFT).ok)
	paused = false
	# Relocate only the test target, explicitly in the fixture, outside the leash.
	enemy._cell_owners.erase(enemy.cells[1])
	enemy.cells[1] = start + Vector2i.RIGHT * 21
	enemy._cell_owners[enemy.cells[1]] = 1
	advance(0.1)
	assert(team.combat_order != TerrainArmy.CombatOrder.PURSUE and team.cells[1] == start)
	enemy._cell_owners.erase(enemy.cells[1])
	enemy.cells[1] = start + Vector2i.RIGHT
	enemy._cell_owners[enemy.cells[1]] = 1
	assert(team.issue_combat_order(1, TerrainArmy.CombatOrder.PURSUE, TerrainArmy.INVALID_CELL, identity).ok)
	goal = start + Vector2i.LEFT * 3
	assert(team.issue_combat_order(1, TerrainArmy.CombatOrder.RETREAT, goal).ok)
	advance(3.0)
	assert(team.cells[1] == goal and team.combat_order == TerrainArmy.CombatOrder.HOLD)
	assert(team.pursuit_target == -1 and team.pursuit_left == 0.0, "Old pursuit cannot overwrite a new retreat")
	assert(team.issue_combat_order(1, TerrainArmy.CombatOrder.PURSUE, TerrainArmy.INVALID_CELL, identity).ok)
	enemy.apply_unit_contact(1, {"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
	advance(0.1)
	assert(team.combat_order != TerrainArmy.CombatOrder.PURSUE)
	print("TACTICS: pause, distance leash, retreat priority, invalid target")
	team.clear()
	enemy.clear()
	team.queue_free()
	enemy.queue_free()
	lab.free()
	await process_frame
	print("SITE ARMY TACTICS PASS: legal 100-person movement, refill and double-casualty claims, action lock, supersession, unreachable self-defense, 20-second/distance pursuit limits, pause and chase persistence")
	quit(0)

func reset_team() -> void:
	team.clear()
	assert(team.deploy_at(data, null, null, placement(Vector2i(20, 20))))
	assert(team.enable_combat(false))
	assert(team.get_child_count() == 0)

func placement(origin: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for index in range(100):
		result.append(origin + Vector2i(index % 10, floori(float(index) / 10.0)))
	return result

func knockout(index: int) -> void:
	team.apply_unit_contact(index, {"result": {"hp": 1.0, "stun": 110.0, "guard_break": false}, "shield": false})
	team.settle_combat_command()

func advance(seconds: float) -> void:
	for tick in range(ceili(seconds * 120.0)):
		team.prepare_combat(1.0 / 120.0)
		team.settle_combat_command()
		var occupied := {}
		for index in range(100):
			if team.combat_can_act(index) or team.moving_to[index] != TerrainArmy.INVALID_CELL:
				assert(not occupied.has(team.cells[index]), "Two standing/moving people share a source")
				occupied[team.cells[index]] = index
		for cell: Vector2i in team._reserved_cells:
			var owner := int(team._reserved_cells[cell])
			assert(not occupied.has(cell) and team.moving_to[owner] == cell)
			assert(data.can_step(team.cells[owner], cell) and not enemy.blocks_cell(cell))
