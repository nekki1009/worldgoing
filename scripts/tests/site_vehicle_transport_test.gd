extends SceneTree
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Vehicles = preload("res://scripts/terrain_lab/site_vehicle_transport.gd")
const OUT := "res://output/site_siege_p0_p1_20261003/legacy_vehicle_fixture"
var deadline := 0
var _run_completed := false
var _run_failed := false

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 60000
	_run.call_deferred()
	_check_run_completion.call_deferred()

func _check_run_completion() -> void:
	# The fixture runs synchronously through its final acceptance assertions.
	# An assertion abort must fail immediately instead of waiting for the deadline.
	if not _run_completed or _run_failed:
		push_error("Vehicle transport contract did not complete its acceptance assertions")
		quit(1)

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Vehicle transport contract deadline")
		quit(1)
	return false

func _patch(lab: TerrainLab) -> Vector2i:
	for y in range(1, lab.terrain.size.y - 10):
		for x in range(1, lab.terrain.size.x - 10):
			var legal := true
			for row in range(10):
				for column in range(10):
					var cell := Vector2i(x + column, y + row)
					if not lab.terrain.is_walkable(cell) or lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell): legal = false
					if column > 0 and not lab.terrain.can_step(cell - Vector2i.RIGHT, cell) or row > 0 and not lab.terrain.can_step(cell - Vector2i.DOWN, cell): legal = false
			if legal: return Vector2i(x, y)
	return TerrainArmy.INVALID_CELL

func _run() -> void:
	assert(DisplayServer.get_name() == "headless")
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	var lab := TerrainLab.new()
	lab.npc = TerrainTestNPC.new() # Explicit occupancy fixture; formal startup has no default worker.
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	var origin := _patch(lab)
	assert(origin != TerrainArmy.INVALID_CELL, "Vehicle test uses an actual connected original terrain patch")
	var team := lab.army
	team.role = "logistics"
	team.team_id = lab._next_army_identity()
	team.roster_size = 1
	var cells: Array[Vector2i] = [origin + Vector2i(3, 3)]
	assert(team.deploy_at(lab.terrain, lab.character, lab.npc, cells) and team.enable_combat(false, 0))
	lab.terrain.site.army_next_team = team.team_id + 1
	lab.terrain.site.army_trial_active = true
	var transport: Vehicles = lab.site_controller.vehicles
	var commander := team.combat_identity(0)
	var plan := [{"kind": "cart", "team_id": team.team_id, "cell": lab.terrain.index(cells[0] + Vector2i.RIGHT), "facing": [1, 0], "operator_index": 0},
		{"kind": "wagon", "team_id": team.team_id, "cell": lab.terrain.index(origin + Vector2i(1, 7)), "facing": [1, 0], "operator_index": -1}]
	assert(transport.deploy_plan(team, plan).ok)
	var ids := transport.records().keys()
	var cart: Dictionary = transport.records()[ids[0]]
	var wagon: Dictionary = transport.records()[ids[1]]
	assert(transport.is_operator(commander) and int(wagon.operator_id) == 0)
	assert(Vehicles.footprint(lab.terrain, wagon).size() == 3)
	assert(transport.assign_operator(str(wagon.id), commander, commander, true).code == "BUSY")
	var parked_wagon := wagon.duplicate(true)
	assert(team._reserve_combat_step(0, team.cells[0] + Vector2i.RIGHT), "Own old cart cell must not block its genuine operator's forward step")
	team.prepare_combat(0.1)
	assert(not cart.move.is_empty() and transport.render_state(cart).moving and transport.render_state(cart).progress > 0.0)
	lab.site_controller._capture_positions()
	var saved := Store.save(lab.terrain, OUT + "/moving.json")
	assert(saved.ok, str(saved))
	var loaded := Store.load_site(OUT + "/moving.json")
	assert(loaded.ok, str(loaded))
	assert(not loaded.data.site.vehicles[cart.id].move.is_empty())
	var corrupted: Dictionary = lab.terrain.site.duplicate(true)
	corrupted.vehicles[cart.id].move.sweep.pop_back()
	assert(not Store._validate_vehicles(lab.terrain, corrupted, true).ok)
	corrupted = lab.terrain.site.duplicate(true)
	corrupted.vehicles[wagon.id].operator_id = commander
	assert(not Store._validate_vehicles(lab.terrain, corrupted, true).ok, "Saved operator cannot own two vehicles")
	corrupted = lab.terrain.site.duplicate(true)
	corrupted.vehicles[wagon.id].holder = corrupted.vehicles[cart.id].holder.duplicate(true)
	assert(not Store._validate_items(lab.terrain, corrupted).ok, "Saved vehicle holders cannot alias or duplicate original equipment")
	lab.bind_terrain(loaded.data)
	team = lab.army
	transport = lab.site_controller.vehicles
	cart = transport.records()[ids[0]]
	wagon = transport.records()[ids[1]]
	assert(team.moving_count() == 1 and int(cart.operator_id) == commander and not cart.move.is_empty(), "Loading must restore the same original moving person/car pair")
	# Nekki 2026-11-13 (依建議): the grid team steps that drove these vehicles are retired (Option C); the crowd convoy
	# tests own vehicle motion now. This contract keeps its deployment, operator, moving save/load and Store rules only.
	if _run_failed: return
	_run_completed = true
	print("VEHICLE TRANSPORT PASS (rules only): deployment plan, footprint, operator BUSY, moving cart save/load/bind of the same person/car pair, corrupt sweep/double operator/aliased holder rejected by Store")
	lab.queue_free()
	await process_frame
	quit(0)
