extends SceneTree
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Vehicles = preload("res://scripts/terrain_lab/site_vehicle_transport.gd")
const OUT := "res://output/site_ship_implementation_20261003/regressions/vehicle_takeover"
var deadline := 0
var _movement_probe_index := 0

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

func _movement_probe(team: TerrainArmy) -> Dictionary:
	var coordinator: Object = team.get_coordinator()
	var plan: CombatMovePlan = team.get_active_move_plan()
	var deployment: CombatDeploymentPlan = team.get_active_deployment_plan()
	return {"team_id": team.team_id, "faction": team.faction_id, "cells": str(team.cells),
		"moving_to": str(team.moving_to), "progress": team.move_progress.duplicate(),
		"duration": team.move_duration.duplicate(), "slots": str(team.combat_slots),
		"claims": str(team.get_active_movement_claims()), "order": team.combat_order,
		"status": team.command_status, "commander": team.current_commander,
		"plan": TerrainArmy._serialize_move_plan(plan) if plan != null else {},
		"deployment": TerrainArmy._serialize_deployment_plan(deployment) if deployment != null else {},
		"coordinator": {"tick": coordinator.current_logic_tick,
			"occupancy": str(coordinator._current_occupancy),
			"rebuild_pending": coordinator.is_occupancy_rebuild_pending(),
			"batches": coordinator.get_inflight_batches_for_formation(team),
			"committed_occupancy": str(coordinator.movement_reservation_grid.committed_occupancy)} if coordinator != null else {}}

func _movement_failure(team: TerrainArmy, label: String, before: Dictionary) -> void:
	_movement_probe_index += 1
	var report := {"label": label, "before": before, "after": _movement_probe(team)}
	var path := OUT + "/movement_failure_%d_%02d.json" % [int(Time.get_unix_time_from_system() * 1000.0), _movement_probe_index]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("VEHICLE TAKEOVER MOVEMENT FAILURE ", path, " ", JSON.stringify(report))

func _walk(lab: TerrainLab, team: TerrainArmy, goal: Vector2i) -> bool:
	var before := _movement_probe(team)
	assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, goal).ok)
	# The original Lab step owns coordinator proposals and committed completion.
	# Retain exactly the original 180 steps / six seconds and physical-cell check.
	for step in range(180): lab._advance_action_time(1.0 / 30.0)
	if team.cells[0] != goal or team.moving_count() != 0:
		_movement_failure(team, "walk to " + str(goal), before)
	assert(team.cells[0] == goal and team.moving_count() == 0, "A real original person must walk to the actual rear of the vehicle")
	return true

func _finish(lab: TerrainLab, team: TerrainArmy) -> bool:
	var before := _movement_probe(team)
	for step in range(25): lab._advance_action_time(1.0 / 30.0)
	if team.moving_count() != 0: _movement_failure(team, "finish original vehicle step", before)
	assert(team.moving_count() == 0)
	return true

func _probe(kind: String) -> bool:
	var lab := TerrainLab.new()
	lab.npc = TerrainTestNPC.new() # Explicit original occupancy fixture; formal startup has no default worker.
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
		team.faction_id = 0 # Both original teams are allies; enemy rejection below remains explicit.
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
	if not _finish(lab, first): return false
	assert(int(vehicle.team_id) == first.team_id and transport.team_vehicle_count(first) == 1)
	if not _walk(lab, first, rear + Vector2i.UP * 2): return false
	if not _walk(lab, second, rear + Vector2i.DOWN if kind == "wagon" else rear): return false
	second.faction_id = 1
	assert(not transport.can_offer_operator_team(vehicle, second))
	assert(transport.assign_operator(vehicle.id, second_id, second_id, true).code == "NO_AUTHORITY")
	second.faction_id = 0
	assert(transport.can_offer_operator_team(vehicle, second))
	assert(transport.assign_operator(vehicle.id, second_id, first_id, true).code == "NO_AUTHORITY", "The previous commander cannot authorize a different team's person")
	assert(transport.assign_operator(vehicle.id, second_id, second_id, true).ok)
	if not _finish(lab, second): return false
	assert(transport.team_vehicle_count(first) == 0 and transport.team_vehicle_count(second) == 1)
	assert(int(vehicle.team_id) == second.team_id and int(vehicle.operator_id) == second_id)
	assert(vehicle.id == original.id and vehicle.holder == original.holder and vehicle.cargo == original.cargo and int(lab.terrain.site.next_vehicle) == next_vehicle)
	assert(is_same(holder_alias, vehicle.holder) and is_same(cargo_alias, vehicle.cargo), "Taking a vehicle changes no stock owner object or cargo alias")
	lab.site_controller._capture_positions()
	var second_save := Store.save(lab.terrain, OUT + "/" + kind + "_second_team.json")
	if not bool(second_save.get("ok", false)):
		# Preserve the exact rejected owner state before the original save assertion.
		var report := {"save_result": second_save, "site": lab.terrain.site.duplicate(true),
			"first": _movement_probe(first), "second": _movement_probe(second),
			"army_validation": Store._validate_armies(lab.terrain, lab.terrain.site, true),
			"vehicle_validation": Store._validate_vehicles(lab.terrain, lab.terrain.site, true)}
		var report_path := OUT + "/save_failure_%s_%d.json" % [kind, int(Time.get_unix_time_from_system() * 1000.0)]
		var report_file := FileAccess.open(report_path, FileAccess.WRITE)
		if report_file != null:
			report_file.store_string(JSON.stringify(report, "\t", true, true))
			report_file.close()
		print("VEHICLE TAKEOVER SAVE FAILURE ", report_path, " result=", second_save,
			" armies=", report.army_validation, " vehicles=", report.vehicle_validation)
	assert(second_save.ok, str(second_save))
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
	if not _walk(lab, first, rear + Vector2i.UP if kind == "wagon" else rear): return false
	assert(transport.assign_operator(vehicle.id, first_id, first_id, true).ok)
	if not _finish(lab, first): return false
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
	return true

func _run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	if not await _probe("cart"):
		push_error("Vehicle cart takeover did not complete its original acceptance assertions")
		quit(1)
		return
	if not await _probe("wagon"):
		push_error("Vehicle wagon takeover did not complete its original acceptance assertions")
		quit(1)
		return
	quit(0)
