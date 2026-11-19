extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok

func _routed(team: TerrainArmy) -> void:
	team.sustain_routed_query = func(_original: TerrainArmy) -> bool: return true
	assert(team.begin_morale_retreat().ok)

func _run() -> void:
	var data := Helper.build_flat_map(15, 15)
	var row := Helper.create_test_army(data, 1, 0, 1, Vector2i(0, 7))
	var identity := row.combat_identity(0)
	row.controlled_person_query = func() -> int: return identity
	if not _check(row.issue_combat_order(row.current_commander, TerrainArmy.CombatOrder.RETREAT).code == "NOT_ROUTED", "Intact morale cannot exit by captain order"): return
	_routed(row)
	row.prepare_combat(0.6)
	if not _check(not bool(row.combat_hot_get(0, &"site_exited", false)) and row._cell_owners.has(row.cells[0]) and not row.morale_retreat_terminal(), "Controlled original row exited without outward player input"): return
	if not _check(not row.exit_controlled_site_retreat(0, Vector2i.UP).ok, "A direction still inside the map cannot exit"): return
	if not _check(row.exit_controlled_site_retreat(0, Vector2i.LEFT).ok and bool(row.combat_hot_get(0, &"site_exited", false)) and row._cell_owners.is_empty() and row.morale_retreat_terminal(), "Outward input did not release original row at edge"): return
	if not _check(TerrainArmy.valid_combat_state(row.capture_combat_state(), data), "Controlled original row exit snapshot invalid"): return
	row.free()

	var actor_team := Helper.create_test_army(data, 2, 0, 1, Vector2i(5, 7))
	var actor := TerrainTestCharacter.new()
	actor.data = data
	actor.person_id = 9999
	actor.faction_id = 0
	actor.terrain_cell = Vector2i(0, 8)
	actor_team.player_member = actor
	actor_team.controlled_person_query = func() -> int: return actor.person_id
	_routed(actor_team)
	actor_team.prepare_combat(0.6)
	if not _check(not actor.site_exited and actor_team.player_goal == actor.terrain_cell and not actor_team.morale_retreat_terminal(), "Controlled Actor must remain present on the boundary awaiting explicit exit"): return
	if not _check(actor_team.exit_controlled_site_retreat(TerrainArmy.PLAYER_MEMBER, Vector2i.LEFT).ok and actor.site_exited and not actor.visible and actor_team.player_goal == TerrainArmy.INVALID_CELL, "Controlled Actor did not leave after outward boundary input"): return
	if not _check(not actor.occupies_cell(Vector2i(0, 8)), "Exited Actor still blocks the physical cell"): return
	actor_team.player_member = null
	actor.free()
	actor_team.free()

	var sealed := Helper.build_flat_map(15, 15)
	for x in range(sealed.size.x):
		sealed.flags[sealed.index(Vector2i(x, 0))] = 0
		sealed.flags[sealed.index(Vector2i(x, sealed.size.y - 1))] = 0
	for y in range(sealed.size.y):
		sealed.flags[sealed.index(Vector2i(0, y))] = 0
		sealed.flags[sealed.index(Vector2i(sealed.size.x - 1, y))] = 0
	sealed.navigation_revision += 1
	var blocked := Helper.create_test_army(sealed, 3, 0, 1, Vector2i(7, 7))
	blocked.controlled_person_query = func() -> int: return blocked.combat_identity(0)
	_routed(blocked)
	blocked.prepare_combat(0.6)
	if not _check(bool(blocked.combat_hot_get(0, &"surrender_pending", false)) and not bool(blocked.combat_hot_get(0, &"site_exited", false)) and blocked.cells[0] == Vector2i(7, 7), "Controlled original row without a legal exit/refuge must await capture in place"): return
	blocked.free()
	print("SITE CONTROLLED RETREAT EXIT PASS: row and Actor leave only after explicit outward input; sealed route surrenders in place")
	quit(0)
