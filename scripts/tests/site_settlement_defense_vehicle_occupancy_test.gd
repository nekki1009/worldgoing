extends "res://scripts/tests/site_building_ui_test.gd"
## CC039 row52: real vehicles retain full footprints and movement reservations.
## Direct original owner queries only; no travel, renderer or Native acceptance.

class OccupancyErrors extends Logger:
	var _mutex := Mutex.new()
	var _first := ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING: return
		_mutex.lock()
		if _first.is_empty(): _first = "%s:%d %s: %s %s" % [file, line, function, code, rationale]
		_mutex.unlock()

	func first_error() -> String:
		_mutex.lock()
		var result := _first
		_mutex.unlock()
		return result

var _occupancy_errors := OccupancyErrors.new()
var _occupancy_failed := false
var _occupancy_checks := 0

func _initialize() -> void:
	OS.add_logger(_occupancy_errors)
	super._initialize()

func _finalize() -> void:
	OS.remove_logger(_occupancy_errors)

func _occupancy_check(condition: bool, label: String) -> bool:
	if _occupancy_failed: return false
	var engine_error := _occupancy_errors.first_error()
	if condition and engine_error.is_empty():
		_occupancy_checks += 1
		return true
	_occupancy_failed = true
	push_error("SETTLEMENT_DEFENSE_OCCUPANCY_FAIL: %s %s" % [label, engine_error])
	quit(1)
	return false

func _process(delta: float) -> bool:
	if not _occupancy_check(true, "first engine error"): return false
	return super._process(delta)

func _occupancy_probe(lab: TerrainLab, identity: int, cell: Vector2i, expected: bool, label: String) -> bool:
	var before := var_to_bytes([lab.terrain.site, lab.site_controller.person_actions._jobs, lab.army.cells, lab.army.moving_to])
	var actual := Runtime._settlement_defense_occupied(lab.terrain, identity, cell)
	if not _occupancy_check(actual == expected, label): return false
	return _occupancy_check(var_to_bytes([lab.terrain.site, lab.site_controller.person_actions._jobs, lab.army.cells, lab.army.moving_to]) == before, label + " is read-only")

func _occupancy_preview(lab: TerrainLab, identity: int, cell: Vector2i, expected: bool) -> bool:
	var cells: Array[int] = [lab.terrain.index(cell)]
	var occupied := func(candidate: Vector2i) -> bool: return Runtime._settlement_defense_occupied(lab.terrain, identity, candidate)
	var before := var_to_bytes([lab.terrain.site, lab.site_controller.person_actions._jobs])
	var preview := Runtime.preview_build(lab.terrain, "stone_wall", cells, occupied, {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	if not _occupancy_check(preview.ok == expected and (expected or preview.get("code") == "OCCUPIED"), "Original build preview retains exact vehicle OCCUPIED refusal"): return false
	return _occupancy_check(var_to_bytes([lab.terrain.site, lab.site_controller.person_actions._jobs]) == before, "Original build preview changes no stock, vehicle or job")

func _run() -> void:
	var data := _building_fixture()
	if not _occupancy_check(data != null, "Original building terrain"): return
	var lab := _building_lab(data)
	if not _occupancy_check(is_instance_valid(lab), "Original bound Lab and vehicle owner"): return
	var team: TerrainArmy = lab.army
	team.team_id = 301
	team.faction_id = 1
	team.roster_size = 2
	var formation: Array[Vector2i] = [Vector2i(24, 24), Vector2i(28, 24)]
	if not _occupancy_check(team.deploy_at(data, lab.character, lab.npc, formation) and team.enable_combat(false), "Original Army deploys its actual two members"): return
	team.set_process(false)
	if not lab.combat_armies.has(team): lab.combat_armies.append(team)
	team.controlled_person_query = lab.controlled_person_id
	team.person_busy_query = lab.site_controller.person_actions.is_busy
	var control := lab.controlled_person_id()
	var worker := team.combat_identity(1)
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var wagon_id := str(int(data.site.next_vehicle))
	var cart_id := str(int(data.site.next_vehicle) + 1)
	var plan := [
		{"kind": "wagon", "team_id": team.team_id, "cell": data.index(Vector2i(36, 36)), "facing": [1, 0], "operator_index": -1},
		{"kind": "cart", "team_id": team.team_id, "cell": data.index(formation[1] + Vector2i.RIGHT), "facing": [1, 0], "operator_index": 1}]
	var deployed := vehicles.deploy_plan(team, plan)
	if not _occupancy_check(deployed.ok, "Original owner admits a parked wagon and the same member's cart"): return
	if not _occupancy_probe(lab, control, Vector2i(40, 40), false, "Empty original ground remains buildable"): return
	if not _occupancy_probe(lab, 0, Vector2i(40, 40), true, "Missing original named person fails closed"): return
	if not _occupancy_probe(lab, control, lab.character.terrain_cell, false, "Only the named independent Actor is excluded"): return
	if not _occupancy_probe(lab, control, lab.npc.terrain_cell, true, "A second actual Actor still blocks"): return
	if not _occupancy_probe(lab, worker, formation[1], false, "Original WorkTeam excludes only the named NPC"): return
	if not _occupancy_probe(lab, worker, formation[0], true, "Another original Army member still blocks"): return
	var wagon: Dictionary = vehicles.records()[wagon_id]
	var footprint := SiteVehicleTransport.footprint(data, wagon)
	if not _occupancy_check(footprint.size() == 3, "Original wagon has its full three-cell footprint"): return
	for cell: Vector2i in footprint:
		if not _occupancy_probe(lab, control, cell, true, "Every wagon body cell blocks the Actor path"): return
		if not _occupancy_probe(lab, worker, cell, true, "Every wagon body cell blocks the WorkTeam path"): return
	if not _occupancy_preview(lab, worker, footprint.back(), false): return
	var cart: Dictionary = vehicles.records()[cart_id]
	var reserved_only := formation[1] + Vector2i.RIGHT * 2
	if not _occupancy_check(not SiteVehicleTransport.footprint(data, cart).has(reserved_only), "Probe cell is outside the current cart body"): return
	if not _occupancy_probe(lab, worker, reserved_only, false, "Future cart cell starts clear"): return
	if not _occupancy_preview(lab, worker, reserved_only, true): return
	if not _occupancy_check(vehicles.before_step(team, 1, formation[1] + Vector2i.RIGHT), "Original vehicle planner accepts the next real operator step"): return
	vehicles.commit_step_reservation(team, 1, formation[1] + Vector2i.RIGHT)
	if not _occupancy_check(not cart.move.is_empty() and cart.move.sweep.has(data.index(reserved_only)), "Original owner publishes its real movement sweep"): return
	if not _occupancy_probe(lab, control, reserved_only, true, "Actor cannot build into a vehicle movement reservation"): return
	if not _occupancy_probe(lab, worker, reserved_only, true, "The same original operator cannot ignore their vehicle reservation"): return
	if not _occupancy_preview(lab, worker, reserved_only, false): return
	vehicles.cancel_step(team, 1)
	if not _occupancy_check(cart.move.is_empty(), "Original cancel releases only the pending vehicle step"): return
	if not _occupancy_probe(lab, worker, reserved_only, false, "Cancelled reservation releases the original free cell"): return
	if not _occupancy_preview(lab, worker, reserved_only, true): return
	if not _occupancy_probe(lab, worker, data.cell_from_index(int(cart.cell)), true, "Cancellation retains the physical original cart body"): return
	lab.queue_free()
	TerrainArmy.release_contact_source()
	if not _occupancy_check(true, "No engine errors before PASS"): return
	print("SITE_SETTLEMENT_DEFENSE_VEHICLE_OCCUPANCY_PASS: checks=", _occupancy_checks, "; original vehicle footprint/reservation and person exclusions; no full S10/Native/render acceptance")
	quit(0)
