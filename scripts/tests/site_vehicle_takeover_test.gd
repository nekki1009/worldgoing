extends SceneTree
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Vehicles = preload("res://scripts/terrain_lab/site_vehicle_transport.gd")
const OUT := "res://output/logistics_vehicles_20260918/takeover"
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 60000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Vehicle takeover contract deadline")
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

func _walk(team: TerrainArmy, goal: Vector2i) -> void:
	assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, goal).ok)
	for step in range(180): team.prepare_combat(1.0 / 30.0)
	assert(team.cells[0] == goal and team.moving_count() == 0, "A real original person must walk to the actual rear of the vehicle")

func _finish(team: TerrainArmy) -> void:
	for step in range(25): team.prepare_combat(1.0 / 30.0)
	assert(team.moving_count() == 0)

func _probe(kind: String) -> void:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	var origin := _patch(lab)
	assert(origin != TerrainArmy.INVALID_CELL)
	var rear := origin + Vector2i(3, 3)
	var first := lab.army
	var second := lab.opposing_army
	for index in range(2):
		var team: TerrainArmy = [first, second][index]
		team.team_id = index + 1
		team.role = "logistics"
		team.roster_size = 1
		var formation: Array[Vector2i] = [rear if index == 0 else rear + Vector2i.DOWN * 3]
		assert(team.deploy_at(lab.terrain, lab.character, lab.npc, formation) and team.enable_combat(false, 0))
	lab.terrain.site.army_next_team = 3
	lab.terrain.site.army_trial_active = true
	var transport: Vehicles = lab.site_controller.vehicles
	var first_id := first.combat_identity(0)
	var second_id := second.combat_identity(0)
	assert(first_id != second_id)
	var anchor := Vehicles.anchor_from_operator(kind, rear, Vector2i.RIGHT)
	assert(transport.deploy_plan(first, [{"kind": kind, "team_id": first.team_id, "cell": lab.terrain.index(anchor), "facing": [1, 0], "operator_index": 0}]).ok)
	var vehicle: Dictionary = transport.records().values()[0]
	assert(transport.assign_operator(vehicle.id, second_id, second_id, true).code == "BUSY", "A second team must not take an occupied vehicle")
	var depot_cell: int = lab.terrain.site.depot_cell
	lab.terrain.site.depot_cell = lab.terrain.index(rear + Vector2i.UP)
	lab.terrain.site.inventory.grain = 40
	assert(transport.transfer("depot", vehicle.id, {"grain": 40}, [], int(lab.terrain.site.depot_items.version), int(vehicle.holder.version), first_id, true).ok)
	lab.terrain.site.depot_cell = depot_cell
	var holder_alias: Dictionary = vehicle.holder
	var cargo_alias: Dictionary = vehicle.cargo
	var original := vehicle.duplicate(true)
	var next_vehicle: int = lab.terrain.site.next_vehicle
	assert(transport.unassign_operator(vehicle.id, first_id, true).ok)
	_finish(first)
	assert(int(vehicle.team_id) == first.team_id and transport.team_vehicle_count(first) == 1)
	_walk(first, rear + Vector2i.UP * 2)
	_walk(second, rear + Vector2i.DOWN if kind == "wagon" else rear)
	second.faction_id = 1
	assert(not transport.can_offer_operator_team(vehicle, second))
	assert(transport.assign_operator(vehicle.id, second_id, second_id, true).code == "NO_AUTHORITY")
	second.faction_id = 0
	assert(transport.can_offer_operator_team(vehicle, second))
	assert(transport.assign_operator(vehicle.id, second_id, first_id, true).code == "NO_AUTHORITY", "The previous commander cannot authorize a different team's person")
	assert(transport.assign_operator(vehicle.id, second_id, second_id, true).ok)
	_finish(second)
	assert(transport.team_vehicle_count(first) == 0 and transport.team_vehicle_count(second) == 1)
	assert(int(vehicle.team_id) == second.team_id and int(vehicle.operator_id) == second_id)
	assert(vehicle.id == original.id and vehicle.holder == original.holder and vehicle.cargo == original.cargo and int(lab.terrain.site.next_vehicle) == next_vehicle)
	assert(is_same(holder_alias, vehicle.holder) and is_same(cargo_alias, vehicle.cargo), "Taking a vehicle changes no stock owner object or cargo alias")
	lab.site_controller._capture_positions()
	assert(Store.save(lab.terrain, OUT + "/" + kind + "_second_team.json").ok)
	var loaded := Store.load_site(OUT + "/" + kind + "_second_team.json")
	assert(loaded.ok)
	lab.bind_terrain(loaded.data)
	first = lab.army
	second = lab.opposing_army
	transport = lab.site_controller.vehicles
	vehicle = transport.records()[original.id]
	assert(int(vehicle.team_id) == second.team_id and int(vehicle.operator_id) == second_id and int(vehicle.cargo.grain) == 40)
	# An unconscious original driver releases operation, not the vehicle or cargo.
	second.apply_unit_contact(0, {"result": {"hp": 0.0, "stun": 1000.0, "guard_break": false}, "shield": false})
	transport.settle_operators()
	lab._advance_action_time(1.0 / 30.0) # Original common step settles the KO command roster before capture.
	if kind == "wagon":
		assert(int(vehicle.operator_id) == second_id and bool(vehicle.stop_pending) and not transport.can_offer_operator_team(vehicle, first), "An unconscious person still occupies the horse")
		second.apply_unit_contact(0, {"result": {"hp": 10000.0, "stun": 0.0, "guard_break": false}, "shield": false})
		lab._advance_action_time(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + 0.5)
	assert(int(vehicle.operator_id) == 0 and int(vehicle.team_id) == second.team_id)
	_walk(first, rear + Vector2i.UP if kind == "wagon" else rear)
	assert(transport.assign_operator(vehicle.id, first_id, first_id, true).ok)
	_finish(first)
	assert(transport.team_vehicle_count(first) == 1 and transport.team_vehicle_count(second) == 0 and int(vehicle.cargo.grain) == 40)
	assert(vehicle.holder == original.holder and vehicle.id == original.id and int(lab.terrain.site.next_vehicle) == next_vehicle)
	lab.terrain.site.combat_left = 0.0
	lab.site_controller._capture_positions()
	var saved := Store.save(lab.terrain, OUT + "/" + kind + "_recovered.json")
	assert(saved.ok, str(saved))
	loaded = Store.load_site(OUT + "/" + kind + "_recovered.json")
	assert(loaded.ok and loaded.data.site.armies.size() == 2 and int(loaded.data.site.vehicles[original.id].operator_id) == first_id)
	print("VEHICLE TAKEOVER ", kind, " PASS: two genuine logistics people walk to actual operator position; occupied/enemy/old-commander rejected; original mount/dismount for wagon; same-faction stopped vehicle recovered after cart KO/wagon death; person/car slots transfer 2+1 unchanged; IDs/holder/cargo/versions/aliases preserved; Store/load/bind verified")
	lab.queue_free()
	await process_frame

func _run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	await _probe("cart")
	await _probe("wagon")
	quit(0)
