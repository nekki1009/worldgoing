extends "res://scripts/tests/site_siege_tower_movement_test.gd"

func _run() -> void:
	create_timer(70.0).timeout.connect(func() -> void: quit(1))
	if not _check_actor_roof_and_keyboard(): return
	if not _check_npc_original_bfs(): return
	if not _check_actor_and_npc_wreck_exit(): return
	if not _require(completed == 3, "All actual Actor/NPC caller groups must finish"): return
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_ACTOR_NAVIGATION_PASS: original Actor keyboard/place/terrain edge, original NPC BFS source/final-goal context and FOLLOW endpoint checks, deployed rear stair/roof/bridge/wall, disabled/wreck original-source wake and multi-edge exit, outsiders/reentry rejected, physical construction claims retained; headless caller fixtures, no native/GPU claim")
	quit(0)

func _prepare_actor_tower() -> Dictionary:
	var context := _tower_context()
	if not _deploy_tower(context): return {}
	if not _walk_tower_member(context, 9, Vector2i(16, 25)): return {}
	return context

func _navigation_actor(context: Dictionary, cell: Vector2i, identity: int, npc: bool = false) -> TerrainTestCharacter:
	var actor: TerrainTestCharacter = TerrainTestNPC.new() if npc else ProjectedActor.new()
	actor.data = context.data
	actor.person_id = identity
	actor.faction_id = 0
	actor.terrain_cell = cell
	actor.movement_from_cell = cell
	actor.position = (Vector2(cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	actor.cell_blocker = context.controller._actor_blocked
	actor.step_blocker = context.controller._actor_step_blocked
	actor.exchange_enabled = true
	context.lab.combat_actors.append(actor)
	return actor

func _actor_edge(actor: TerrainTestCharacter, direction: Vector2i) -> bool:
	var source := actor.terrain_cell
	if not _require(actor.step(direction), "Actual Actor step refused original edge " + str({"from": source, "direction": direction})): return false
	if not _require(actor.terrain_cell == source + direction and actor.movement_from_cell == source and actor.is_moving(), "Actor did not reserve the original source/destination"): return false
	actor._advance_movement(actor._movement_duration)
	return _require(not actor.is_moving() and actor.terrain_cell == source + direction, "Actual Actor edge did not settle at its reserved destination")

func _check_actor_roof_and_keyboard() -> bool:
	var context := _prepare_actor_tower()
	if context.is_empty(): return false
	var actor := _navigation_actor(context, Vector2i(17, 21), 990001)
	for x in range(18, 26):
		if not _actor_edge(actor, Vector2i.RIGHT): return false
		if not _require(context.controller.vehicles.blocks_cell(actor.terrain_cell) == (x < 25), "Physical tower claims disappeared under Actor traversal"): return false
	if not _require(actor.terrain_cell == Vector2i(25, 21) and context.data.effective_height(actor.terrain_cell) == 2, "Actual Actor failed to climb onto original wall"): return false
	var outsider := _navigation_actor(context, Vector2i(20, 23), 990002)
	if not _require(not outsider.step(Vector2i.UP), "An Actor climbed the un-ramped side of the tower"): return false
	# Explicit original-state fixtures prove body occupancy without relying on
	# the ordinary live-person index, which deliberately omits settled KO/dead.
	var blocker := _navigation_actor(context, Vector2i(17, 24), 990040)
	var walker := _navigation_actor(context, Vector2i(16, 24), 990041)
	blocker.knockout_left = 1.0
	if not _require(not walker.step(Vector2i.RIGHT) and context.controller._siege_people_occupied(blocker.terrain_cell), "Original KO Actor vanished from movement/lifecycle occupancy"): return false
	blocker.knockout_left = 0.0
	blocker.hp = 0.0
	if not _require(not walker.step(Vector2i.RIGHT) and context.controller._siege_people_occupied(blocker.terrain_cell), "Original dead Actor vanished before its owner was retired"): return false
	context.fixture.army.combat_hot_set(9, &"ko", 1.0)
	context.fixture.army._rebuild_ground_cell_owners()
	if not _require(not walker.step(Vector2i.DOWN) and context.controller._siege_people_occupied(Vector2i(16, 25)), "Original KO Army row vanished from physical occupancy"): return false
	context.fixture.army.combat_hot_set(9, &"ko", 0.0)
	context.fixture.army.combat_hot_set(9, &"hp", 0.0)
	context.fixture.army._rebuild_ground_cell_owners()
	if not _require(not walker.step(Vector2i.DOWN) and context.controller._siege_people_occupied(Vector2i(16, 25)), "Original dead Army row vanished before death settlement"): return false
	_close_ram(context)
	completed += 1
	return true

func _npc_walk(npc: TerrainTestNPC, limit: int = 40) -> bool:
	for edge in range(limit):
		if npc.terrain_cell == npc.target_cell and not npc.is_moving(): return true
		npc.advance_navigation()
		if npc.is_moving(): npc._advance_movement(npc._movement_duration)
	return _require(false, "Original NPC BFS/step failed to finish without another pathfinder: " + str({"source": npc.terrain_cell, "goal": npc.target_cell, "status": npc.command_status}))

func _check_npc_original_bfs() -> bool:
	var context := _prepare_actor_tower()
	if context.is_empty(): return false
	var npc: TerrainTestNPC = _navigation_actor(context, Vector2i(17, 21), 990003, true)
	if not _require(npc.issue_command(TerrainTestNPC.Command.MOVE_TO_CELL, Vector2i(25, 21)), "Actual NPC MOVE could not plan original tower edges"): return false
	if not _npc_walk(npc): return false
	var player := _navigation_actor(context, Vector2i(25, 20), 990004)
	if not _require(npc.issue_command(TerrainTestNPC.Command.FOLLOW_PLAYER, Vector2i(-1, -1), player) and not npc._path.is_empty(), "FOLLOW lost its existing real-player endpoint planning exception"): return false
	npc.advance_navigation()
	if not _require(npc.terrain_cell == Vector2i(25, 21) and not npc.is_moving(), "FOLLOW committed overlap with the real endpoint Actor"): return false
	_close_ram(context)
	completed += 1
	return true

func _check_actor_and_npc_wreck_exit() -> bool:
	for npc_mode in [false, true]:
		var context := _prepare_actor_tower()
		if context.is_empty(): return false
		var actor := _navigation_actor(context, Vector2i(17, 21), 990010 + int(npc_mode), npc_mode)
		for x in range(18, 22):
			if not _actor_edge(actor, Vector2i.RIGHT): return false
		var source := actor.terrain_cell
		var old_level: int = context.data.effective_height(source)
		if npc_mode:
			context.data.height_levels[context.data.index(Vector2i(25, 21))] = 0
			SiteRuntime.invalidate_siege_tower_supports(context.data)
		else: SiteRuntime.damage_siege_vehicle(context.data, context.key, 450.0)
		SiteEnvironment.rebuild_indexes(context.data)
		context.lab.resolve_structure_change(SiteRuntime.ok("lost original tower surface", {"lost_surfaces": {context.data.index(source): old_level}}))
		if not _require(actor.terrain_cell == source and is_equal_approx(actor.hp, 70.0) and actor.knockout_left > 0.0, "Actor lost its source or settled more than one two-level fall"): return false
		actor.advance_combat(0.05, false, SiteCombatRules.KNOCKOUT_GAME_SECONDS)
		actor.advance_combat(2.3, false, 2.3)
		if not _require(actor.can_act() and actor.terrain_cell == source and actor.can_enter_cell(source), "Actual Actor could not wake at its retained original wreck source"): return false
		if npc_mode:
			var npc: TerrainTestNPC = actor
			if not _require(npc.issue_command(TerrainTestNPC.Command.MOVE_TO_CELL, Vector2i(16, 21)), "Wreck NPC lost true original source in its BFS"): return false
			if not _npc_walk(npc): return false
		else:
			for x in range(20, 15, -1):
				if not _actor_edge(actor, Vector2i.LEFT): return false
		if not _require(actor.terrain_cell == Vector2i(16, 21) and is_equal_approx(actor.hp, 70.0), "Exit teleported the original Actor or repeated fall damage"): return false
		var outsider := _navigation_actor(context, Vector2i(17, 21), 990030 + int(npc_mode))
		if not _require(not outsider.step(Vector2i.RIGHT) and not outsider.place(Vector2i(20, 21), true), "An outsider entered/was placed into the retained wreck"): return false
		# Retire the separate outsider fixture before testing the original's reentry.
		context.lab.combat_actors.erase(outsider)
		outsider.free()
		if not _actor_edge(actor, Vector2i.RIGHT): return false
		if not _require(not actor.step(Vector2i.RIGHT), "An exited original Actor reentered its former wreck"): return false
		_close_ram(context)
	completed += 1
	return true
