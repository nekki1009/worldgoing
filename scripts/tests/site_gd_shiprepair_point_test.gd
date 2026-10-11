extends "res://scripts/tests/site_ship_repair_test.gd"
## Explicit existing half-damaged ferry at the original generated shoreline.
## This earns repair progress/material use, not manufacture or navigation.
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()

func _free_cells(data: TerrainData, count: int, excluded: Array[Vector2i], origin: Vector2i, minimum: int = 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell_id: int in data.size.x * data.size.y:
		var cell: Vector2i = data.cell_from_index(cell_id)
		if not data.is_walkable(cell) or excluded.has(cell) or result.has(cell) or absi(cell.x - origin.x) + absi(cell.y - origin.y) < minimum: continue
		result.append(cell)
		if result.size() == count: return result
	assert(false, "Original untouched ground must provide the explicit stationary input cells")
	return []

func _near_cells(data: TerrainData, count: int, excluded: Array[Vector2i], origin: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell_id: int in data.size.x * data.size.y:
		var cell: Vector2i = data.cell_from_index(cell_id)
		if not data.is_walkable(cell) or excluded.has(cell) or result.has(cell) or absi(cell.x - origin.x) + absi(cell.y - origin.y) > 4: continue
		result.append(cell)
		if result.size() == count: return result
	assert(false, "Original natural shore provides two additional true initial team body cells")
	return []

func _point_fixture() -> Dictionary:
	var f: Dictionary = _natural_repair_fixture()
	var data: TerrainData = f.data
	var lab := TerrainLab.new()
	lab.exchange_enabled = false
	lab.pause_when_unfocused = false
	root.add_child(lab)
	for owner: Node in [lab, lab.character, lab.site_controller, lab.army, lab.opposing_army]: owner.set_process(false)
	if is_instance_valid(lab.npc): lab.npc.set_process(false)
	lab.site_controller._auto_save_blocked = true
	lab.bind_terrain(data)
	lab.site_controller.release_worker()
	if is_instance_valid(lab.npc):
		lab.npc.faction_id = lab.character.faction_id
		lab.npc.issue_command(TerrainTestNPC.Command.STOP)
	# Ask original geometry for the station without constructing a fake receipt.
	var geometry_vehicle: Dictionary = f.vehicle.duplicate(true)
	geometry_vehicle.naval.repair = {"feature_id": f.feature_id}
	var stations: Array[Dictionary] = Runtime.ship_repair_work_slots(data, geometry_vehicle)
	assert(not stations.is_empty())
	var station: Dictionary = stations[0]
	var work_cell: Vector2i = data.cell_from_index(int(station.cell))
	var captain_cell := TerrainArmy.INVALID_CELL
	for direction: Vector2i in TerrainData.DIRECTIONS:
		if data.can_step(work_cell, work_cell + direction): captain_cell = work_cell + direction; break
	assert(captain_cell != TerrainArmy.INVALID_CELL)
	var excluded: Array[Vector2i] = [work_cell, captain_cell]
	var extra: Array[Vector2i] = _free_cells(data, 2, excluded, work_cell, 12)
	assert(lab.character.place(extra[0], true))
	if is_instance_valid(lab.npc): assert(lab.npc.place(extra[1], true))
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	var near: Array[Vector2i] = _near_cells(data, 2, excluded, work_cell)
	var positions: Array[Vector2i] = [captain_cell, work_cell, near[0], near[1]]
	assert(team.deploy_at(data, lab.character, lab.npc, positions) and team.enable_combat(false))
	team.faction_id = int(data.site.features[f.feature_id].owner_faction)
	team.settle_combat_command()
	lab.site_controller.initialize_team_items(team)
	assert(int(f.vehicle.team_id) == int(team.team_id), "Original initial boat/team identity is retained; no late authority rewrite")
	var captain: int = team.combat_identity(team.current_commander)
	var worker: int = team.combat_identity(1)
	assert(lab.site_controller._control_family_person(null, captain).ok)
	var before: PackedByteArray = var_to_bytes([data.site.inventory, f.vehicle, Fatigue.read(team.combat_units[1])])
	assert(lab.site_controller.begin_ship_repair("1", f.feature_id, captain, true).ok)
	assert(var_to_bytes([data.site.inventory, f.vehicle, Fatigue.read(team.combat_units[1])]) == before, "True original repair preview has zero material/time/fatigue cost")
	assert(lab.site_controller.begin_ship_repair("1", f.feature_id, captain).ok)
	var job: Dictionary = f.vehicle.naval.repair
	assert(job.size() == 7 and Runtime.validate_ship_repair(data, f.vehicle).ok and float(job.progress) == 0.0)
	assert(lab.site_controller._control_family_person(null, lab.character.person_id).ok)
	var assigned_ids: Array[int] = [worker]
	var assigned: Dictionary = lab.site_controller.work_team.assign(team, assigned_ids, captain)
	assert(assigned.ok, "Original captain/team.work authority assigns the original NPC; not a controlled worker bypass")
	f.merge({"lab": lab, "team": team, "worker": worker, "row": team.combat_units[1], "station": station,
		"work_cell": work_cell, "job": job, "cost": job.paid_cost.duplicate(true), "holder_begin": int(f.vehicle.holder.version), "captain": captain})
	return f

func _close_point(f: Dictionary) -> void:
	f.lab.site_controller.work_team.discard_prepared_interval()
	f.lab._clear_shared_work_step()
	f.lab.free()

func _main_paid_completion() -> void:
	var f: Dictionary = _point_fixture()
	var positive_points := 0
	var depot: Dictionary = f.data.site.inventory.duplicate(true)
	var holder: Dictionary = f.vehicle.holder
	var cargo: Dictionary = f.vehicle.cargo
	for tick: int in 10000:
		assert(Time.get_ticks_msec() <= deadline)
		if f.vehicle.naval.repair.is_empty(): break
		var prior: float = float(f.job.progress)
		var step: Dictionary = f.lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		assert(step.ok and step.get("completed", false) and f.lab._region_point_pending.is_empty(), str(step))
		if float(f.job.progress) > prior: positive_points += 1
		if not f.vehicle.naval.repair.is_empty():
			assert(Runtime.validate_ship_repair(f.data, f.vehicle).ok)
			for resource: String in f.cost:
				assert(int(cargo[resource]) == int(f.cost[resource]) - floori(float(f.cost[resource]) * float(f.job.progress) / float(f.job.total_work)))
	assert(positive_points > 0 and f.vehicle.naval.repair.is_empty() and is_equal_approx(float(f.job.progress), float(f.job.total_work)), "True ACTION_STEP planner work reaches the real original repair endpoint")
	assert(is_equal_approx(float(f.vehicle.naval.hp), Ships.hull_hp("ferry")) and Runtime.inventory_size(cargo) == 0)
	assert(int(holder.version) == int(f.holder_begin) + positive_points, "Each positive original prefix increments once; completed zero endpoint does not consume another holder version")
	assert(is_same(holder, f.vehicle.holder) and is_same(cargo, f.vehicle.cargo) and f.data.site.inventory == depot)
	assert(str(f.row.work_task.target).is_empty() and f.lab.site_controller.original_step_fault_guard().ok and f.lab._shared_work_plan.is_empty())
	var before: PackedByteArray = var_to_bytes([f.vehicle, depot, Fatigue.read(f.row)])
	assert(not Runtime.advance_ship_repair_work(f.data, "1", 0.0, f.work_cell, int(f.station.slot), int(f.team.team_id)).ok)
	assert(var_to_bytes([f.vehicle, depot, Fatigue.read(f.row)]) == before, "Repeated original cleared endpoint never charges material, fatigue or HP")
	assert(var_to_bytes([f.data.height_levels, f.data.flags, f.data.surface_types, f.data.ramp_edges, f.data.foundation, f.data.water_kind, f.data.water_body]) == f.ground)
	_close_point(f)

func _earned_zero_component() -> void:
	var f: Dictionary = _point_fixture()
	var work: SiteWorkTeam = f.lab.site_controller.work_team
	var requests: Array = work.prepare_work_requests(90.0)
	f.lab._shared_work_requests = requests
	assert(f.lab._refresh_shared_work_preflight().ok and requests.size() == 1)
	var captured: Dictionary = work.prepare_shared_work_prefix(90.0)
	var planned: Dictionary = Fatigue.plan_work_interval(f.lab._shared_work_requests, 90.0)
	var priors: Array = []
	var admitted: Dictionary = work.validate_shared_work_prefix(captured, planned, priors)
	assert(captured.ok and planned.ok and admitted.ok and priors.size() == 1)
	assert(float(priors[0].progress) == float(f.job.total_work) and float(f.job.progress) == 0.0, "Completion is derived from actual original worker allocation, not written fixture elapsed/progress")
	f.lab._shared_work_plan = planned
	f.lab.site_controller._shared_work_plan = planned
	f.lab._shared_work_pools_committed = false
	f.lab._commit_shared_work_pools()
	work.publish_shared_work_prefix(admitted)
	assert(float(f.job.progress) == float(f.job.total_work) and not f.vehicle.naval.repair.is_empty())
	assert(not Runtime.validate_ship_repair(f.data, f.vehicle).ok, "Store default receipt validator still rejects an uncleared completed repair")
	var before: PackedByteArray = var_to_bytes([f.vehicle, f.data.site.inventory, Fatigue.read(f.row)])
	assert(Runtime.advance_ship_repair_work(f.data, "1", 0.0, f.work_cell, int(f.station.slot), int(f.team.team_id), true).ok)
	assert(var_to_bytes([f.vehicle, f.data.site.inventory, Fatigue.read(f.row)]) == before, "Original zero endpoint preview is pure")
	assert(not Runtime.advance_ship_repair_work(f.data, "1", 0.0, Vector2i(-1, -1), int(f.station.slot), int(f.team.team_id)).ok)
	assert(var_to_bytes([f.vehicle, f.data.site.inventory, Fatigue.read(f.row)]) == before, "Completed work does not bypass current physical station guard")
	var version: int = int(f.vehicle.holder.version)
	var fatigue: float = Fatigue.read(f.row)
	# Only the finite header is an explicit negative test input; the work
	# above was earned by original provider/planner publication.
	var original_revision: int = int(f.vehicle.revision)
	f.vehicle.revision = 2147483647
	var counter_before: PackedByteArray = var_to_bytes([f.vehicle, f.data.site.inventory, Fatigue.read(f.row)])
	assert(not Runtime.advance_ship_repair_work(f.data, "1", 0.0, f.work_cell, int(f.station.slot), int(f.team.team_id)).ok)
	assert(var_to_bytes([f.vehicle, f.data.site.inventory, Fatigue.read(f.row)]) == counter_before, "Completed zero endpoint cannot overflow the true vehicle revision")
	f.vehicle.revision = original_revision # Restore only the finite input, never work/body/time.
	assert(Runtime.advance_ship_repair_work(f.data, "1", 0.0, f.work_cell, int(f.station.slot), int(f.team.team_id)).ok)
	assert(f.vehicle.naval.repair.is_empty() and int(f.vehicle.holder.version) == version and Fatigue.read(f.row) == fatigue)
	work.finish_shared_work_prefix(admitted)
	_close_point(f)

func _revision_source_limit() -> void:
	var f: Dictionary = _point_fixture()
	f.vehicle.revision = 2147483647 # Explicit legal Store header limit.
	assert(Runtime.validate_ship_repair(f.data, f.vehicle).ok)
	var before: PackedByteArray = var_to_bytes([f.vehicle, f.data.site.inventory, Fatigue.read(f.row)])
	assert(not Runtime.advance_ship_repair_work(f.data, "1", 1.0, f.work_cell, int(f.station.slot), int(f.team.team_id), true).ok)
	assert(not Runtime.advance_ship_repair_work(f.data, "1", 1.0, f.work_cell, int(f.station.slot), int(f.team.team_id)).ok)
	assert(var_to_bytes([f.vehicle, f.data.site.inventory, Fatigue.read(f.row)]) == before, "Positive repair cannot spend reserved material before revision rejection")
	_close_point(f)

func _run() -> void:
	_main_paid_completion()
	_earned_zero_component()
	_revision_source_limit()
	TerrainArmy.release_contact_source()
	run_completed = true
	print("GD_CONTACT_SHIP_REPAIR_POINT_PASS scope=original_natural_shore_paid_ACTION_STEP_completion_and_earned_zero_component_only native_world_manufacture_navigation_not_claimed")
	quit(0)
