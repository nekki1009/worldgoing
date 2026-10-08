extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")
	create_timer(20.0).timeout.connect(func() -> void:
		push_error("COMBAT MOVEMENT PLAYER BLOCK timed out")
		quit(1))

func _run() -> void:
	var terrain := Helper.build_flat_map(16, 16)
	var army := Helper.create_test_army(terrain, 1, 0, 1, Vector2i(5, 5))
	var player := TerrainTestCharacter.new()
	player.data = terrain
	player.person_id = 9001
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	var source: Vector2i = army.cells[0]
	var goal := source + Vector2i.RIGHT
	assert(army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, goal).get("ok", false))
	assert(player.place(goal, true) and player.occupies_cell(goal))
	var member_id := army.combat_identity(0)
	for tick in range(20):
		coordinator.combat_logic_tick_if_needed(0.05, {player.terrain_cell: true})
		army.prepare_combat(0.05)
		coordinator.complete_committed_moves()
		assert(coordinator.movement_reservation_grid.blocked_destinations.has(goal))
		assert(army.cells[0] == source and army.moving_to[0] == TerrainArmy.INVALID_CELL,
			"Player occupancy must hold the Army at its physical source")
		for proposal in coordinator.movement_reservation_grid.proposals:
			assert(proposal.status != Types.MoveProposalStatus.REJECTED_INVALID_MEMBER,
				"Player blocking must not create INVALID_MEMBER proposals")
			if proposal.to_cell == goal:
				assert(proposal.status == Types.MoveProposalStatus.REJECTED_DEPENDENCY)

	assert(player.place(Vector2i(10, 10), true) and not player.occupies_cell(goal))
	var completed := false
	for tick in range(100):
		coordinator.combat_logic_tick_if_needed(0.05)
		army.prepare_combat(0.05)
		coordinator.complete_committed_moves()
		if tick == 0:
			assert(not coordinator.movement_reservation_grid.blocked_destinations.has(goal),
				"The departed Player cannot block the next tick")
		if army.combat_order == TerrainArmy.CombatOrder.HOLD:
			completed = army.command_status.begins_with("已抵達") and army.cells[0] == goal
			break
	assert(completed, "MOVE must complete after the player leaves")

	var grid := coordinator.movement_reservation_grid
	coordinator._rebuild_occupancy()
	grid.begin_tick(coordinator._current_occupancy, terrain)
	var bad_id: int = grid.propose_move(army.formation_runtime_id, member_id + 1, 0, goal, source)
	grid.resolve_all()
	assert(grid.proposal_lookup[bad_id].status == Types.MoveProposalStatus.REJECTED_INVALID_MEMBER,
		"A genuinely invalid member must still be rejected")

	coordinator.unregister_formation(army)
	army.free()
	player.free()
	print("COMBAT MOVEMENT PLAYER BLOCK PASS")
	quit(0)
