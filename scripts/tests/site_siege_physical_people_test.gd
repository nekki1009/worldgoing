extends "res://scripts/tests/site_siege_ballista_contract_test.gd"

func _require(condition: bool, message: String) -> bool:
	if condition: return true
	push_error(message)
	quit(1)
	return false

func _run() -> void:
	create_timer(40.0).timeout.connect(func() -> void: quit(90))
	var context := _ballista_fixture()
	var team: TerrainArmy = context.fixture.army
	var transport: SiteVehicleTransport = context.controller.vehicles
	var dead_cell: Vector2i = team.cells[1]
	var dead_id := team.combat_identity(1)
	team.combat_hot_set(1, &"hp", 0.0)
	team._cell_owners.erase(dead_cell)
	team._reserved_cells.erase(dead_cell)
	if not _require(not team.combat_can_act(1) and transport._siege_people_except(dead_cell, {}), "Original dead Army body vanished from siege physical claims after live maps cleared"): return
	if not _require(not transport._siege_people_except(dead_cell, {dead_id: true}), "Ignored original participant identity lost its narrow exemption"): return
	completed += 1
	var ko_cell: Vector2i = team.cells[2]
	team.combat_hot_set(2, &"ko", 2.0)
	team._cell_owners.erase(ko_cell)
	team._reserved_cells.erase(ko_cell)
	if not _require(not team.combat_can_act(2) and transport._siege_people_except(ko_cell, {}), "Settled KO Army body vanished from siege physical claims"): return
	if not _require(context.controller.work_team._occupied(dead_cell, team, 0) and context.controller.work_team._occupied(ko_cell, team, 0), "Original WorkTeam still crosses dead/KO Army bodies"): return
	completed += 1
	var actor := TerrainTestCharacter.new()
	actor.person_id = 90001
	actor.terrain_cell = Vector2i(30, 30)
	actor.movement_from_cell = Vector2i(29, 30)
	actor._movement_duration = 1.0
	actor._movement_elapsed = 0.5
	actor.hp = 0.0
	context.lab.combat_actors.append(actor)
	if not _require(not actor.occupies_cell(actor.terrain_cell) and transport._siege_people_except(actor.terrain_cell, {}) and transport._siege_people_except(actor.movement_from_cell, {}), "Dead original Actor lost either committed endpoint under the live-only occupies_cell query"): return
	if not _require(context.controller.work_team._occupied(actor.terrain_cell, team, 0) and context.controller.work_team._occupied(actor.movement_from_cell, team, 0), "WorkTeam crosses a dead original Actor endpoint"): return
	actor.site_exited = true
	if not _require(not transport._siege_people_except(actor.terrain_cell, {}), "Departed Actor projection still blocks the Site"): return
	completed += 1
	_close_ballista(context)
	if not _require(completed == 3, "All physical original-body groups must finish before PASS"): return
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_PHYSICAL_PEOPLE_PASS: original Army dead/KO bodies without live maps, narrow ignored identity, original dead Actor committed endpoints and departure, WorkTeam physical body guard; isolated headless owner queries only")
	quit(0)
