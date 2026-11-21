extends "res://scripts/tests/site_gd_shiprepair_point_test.gd"
## Original admitted shore worker, actual remote melee source in the SAME point.
## The work station stays outside the original eight-hop THREAT exclusion.

func _run() -> void:
	var f: Dictionary = _point_fixture()
	var lab: TerrainLab = f.lab
	var data: TerrainData = f.data
	var team: TerrainArmy = f.team
	var target_cell := TerrainArmy.INVALID_CELL
	var enemy_cell := TerrainArmy.INVALID_CELL
	var used: Array[Vector2i] = []
	used.assign(team.cells)
	if is_instance_valid(lab.npc): used.append(lab.npc.terrain_cell)
	for cell_id: int in data.size.x * data.size.y:
		var cell: Vector2i = data.cell_from_index(cell_id)
		if not data.is_walkable(cell) or used.has(cell) or absi(cell.x - f.work_cell.x) + absi(cell.y - f.work_cell.y) < 14: continue
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var adjacent: Vector2i = cell + direction
			if used.has(adjacent) or not data.can_step(cell, adjacent) or not SiteCombatRules.terrain_line_clear(data, cell, adjacent): continue
			target_cell = cell; enemy_cell = adjacent; break
		if target_cell != TerrainArmy.INVALID_CELL: break
	assert(target_cell != TerrainArmy.INVALID_CELL and lab.character.place(target_cell, true), "True generated ground provides an unchanged real melee contact pair")
	var enemy: TerrainArmy = lab.opposing_army
	enemy.roster_size = 4
	used.append(target_cell)
	used.append(enemy_cell)
	var extras: Array[Vector2i] = []
	for cell_id: int in data.size.x * data.size.y:
		var cell: Vector2i = data.cell_from_index(cell_id)
		if not data.is_walkable(cell) or used.has(cell) or absi(cell.x - f.work_cell.x) + absi(cell.y - f.work_cell.y) < 14 or absi(cell.x - target_cell.x) + absi(cell.y - target_cell.y) < 25: continue
		extras.append(cell)
		if extras.size() == 4: break
	assert(extras.size() == 4, "Other initial original bodies remain outside true threat/ranged contact geometry")
	if is_instance_valid(lab.npc): assert(lab.npc.place(extras[3], true))
	var cells: Array[Vector2i] = [enemy_cell, extras[0], extras[1], extras[2]]
	assert(enemy.deploy_at(data, lab.character, lab.npc, cells) and enemy.enable_combat(false))
	enemy.faction_id = team.faction_id + 1
	enemy.settle_combat_command()
	assert(not lab._fatigue_threat(f.work_cell, team.faction_id, team, 1, {}), "No fixture bypass of the actual shore worker THREAT admission")
	var attacker := -1
	for index: int in enemy.combat_units.size():
		if enemy.cells[index] == enemy_cell and enemy.combat_can_act(index) and enemy.ranged_profile(index).is_empty(): attacker = index; break
	assert(attacker >= 0 and enemy.contact_sink.is_valid())
	var packets: Array[Dictionary] = []
	var original_sink: Callable = enemy.contact_sink
	enemy.contact_sink = func(packet: Dictionary) -> void:
		packets.append({"fraction": float(packet.fraction), "target": packet.get("target"), "hp": float(packet.result.hp), "stun": float(packet.result.stun)})
		original_sink.call(packet) # EXACT original mesh/material packet, no test-generated impact.
	var observed := {}
	var before_hit: int = int(lab.character._received_effective_hit)
	for tick: int in 1800:
		assert(Time.get_ticks_msec() <= deadline)
		if not bool(enemy.combat_hot_get(attacker, &"attack")) and enemy.combat_can_act(attacker): assert(enemy.start_unit_attack(attacker, target_cell, lab.character.person_id))
		var count: int = packets.size()
		var progress: float = float(f.job.progress)
		var version: int = int(f.vehicle.holder.version)
		var fatigue: float = Fatigue.read(f.row)
		var rate: float = Fatigue.effort_rate(f.row)
		var step: Dictionary = lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		assert(step.ok and step.get("completed", false) and lab._region_point_pending.is_empty(), str(step))
		if int(lab.character._received_effective_hit) > before_hit and packets.size() > count:
			observed = {"packets": packets.slice(count), "game_seconds": float(step.game_seconds), "progress": progress, "version": version, "fatigue": fatigue, "rate": rate}
			break
		assert(not f.vehicle.naval.repair.is_empty(), "Actual real contact must precede the finite paid repair endpoint")
	enemy.contact_sink = original_sink
	assert(not observed.is_empty() and not f.vehicle.naval.repair.is_empty())
	var interior := false
	for packet: Dictionary in observed.packets:
		interior = interior or is_same(packet.target, lab.character) and float(packet.fraction) > 0.0 and float(packet.fraction) < 1.0 and (float(packet.hp) > 0.0 or float(packet.stun) > 0.0)
	assert(interior, "Strict actual mesh fraction is inside the admitted original action interval")
	var worked: float = float(f.job.progress) - float(observed.progress)
	var effective: float = Fatigue.work_seconds(float(observed.fatigue), float(observed.game_seconds), float(observed.rate))
	assert(worked > 0.0 and absf(worked - effective) < 0.00000001, "Unaffected genuine shore worker receives its exact full point across true disjoint contact segments, no whole-window duplicate")
	assert(int(f.vehicle.holder.version) >= int(observed.version) + 2 and int(f.vehicle.holder.version) <= int(observed.version) + observed.packets.size() + 1)
	for resource: String in f.cost:
		assert(int(f.vehicle.cargo[resource]) == int(f.cost[resource]) - floori(float(f.cost[resource]) * float(f.job.progress) / float(f.job.total_work)), "Cross-contact floor deltas telescope, neither double-spend nor restore paid material")
	assert(is_equal_approx(float(f.vehicle.naval.hp), Ships.hull_hp("ferry") * 0.5 + float(f.job.applied)))
	assert(Runtime.validate_ship_repair(data, f.vehicle).ok and lab.site_controller.original_step_fault_guard().ok and lab._shared_work_plan.is_empty())
	assert(var_to_bytes([data.height_levels, data.flags, data.surface_types, data.ramp_edges, data.foundation, data.water_kind, data.water_body]) == f.ground)
	_close_point(f)
	TerrainArmy.release_contact_source()
	run_completed = true
	print("GD_CONTACT_SHIP_REPAIR_MESH_PASS scope=original_natural_shore_admitted_worker_actual_remote_mesh_segments_floor_HP_version_only native_world_manufacture_workerTHREAT_not_claimed")
	quit(0)
