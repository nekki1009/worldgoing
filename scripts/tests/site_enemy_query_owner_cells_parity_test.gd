extends "res://scripts/tests/site_movement_r3_replay_test.gd"
## The original TerrainLab owner and exact replay, with only enemy lookup toggled.

const OUT := "res://output/site_crowd_d1_20260929/enemy_query_parity"
const PARITY_STEPS := 30

func _fixture(indexed: bool) -> Dictionary:
	var world: Dictionary = super._fixture(true)
	var lab: TerrainLab = world.lab
	lab.enemy_query_owner_cells_enabled = indexed
	var holding: TerrainArmy = world.armies[2]
	holding.tactical_ai_enabled = false
	var issued: Dictionary = holding.issue_combat_order(holding.current_commander, TerrainArmy.CombatOrder.HOLD)
	if not bool(issued.get("ok", false)):
		_faults.append("Original HOLD order rejected in enemy-query replay")
	for index in range(holding.combat_units.size()):
		holding.combat_hot_set(index, &"think", 0.0)
	return world

func _clear_patch(lab: TerrainLab) -> Vector2i:
	var claimed: Dictionary = {}
	for team: TerrainArmy in lab.combat_armies:
		claimed.merge(team._cell_owners)
	for actor: TerrainTestCharacter in lab.combat_actors:
		claimed[actor.terrain_cell] = true
	for y in range(8, lab.terrain.size.y - 8):
		for x in range(8, lab.terrain.size.x - 8):
			var origin := Vector2i(x, y)
			var valid := true
			for cell: Vector2i in [origin, origin + Vector2i.LEFT, origin + Vector2i.RIGHT,
				origin + Vector2i.UP, origin + Vector2i.DOWN]:
				if claimed.has(cell) or not lab.terrain.is_walkable(cell) \
					or not SiteCombatRules.terrain_line_clear(lab.terrain, origin, cell):
					valid = false
					break
			if valid:
				return origin
	return TerrainArmy.INVALID_CELL

func _place(team: TerrainArmy, index: int, cell: Vector2i) -> void:
	team._cell_owners.erase(team.cells[index])
	team.cells[index] = cell
	team._cell_owners[cell] = index

func _query_case(lab: TerrainLab, source: TerrainArmy, label: String, expected_fast: bool, expected_id: int = -1) -> Dictionary:
	lab._enemy_query_owner_cell_window = false
	lab.enemy_query_owner_cells_enabled = false
	var original: Dictionary = lab._nearest_unit_enemy(source, 1)
	lab.enemy_query_owner_cells_enabled = true
	var admitted: bool = lab._enemy_query_owner_cells_admitted()
	lab._enemy_query_owner_cell_window = admitted
	var hits_before := lab.enemy_query_owner_cell_hits
	var candidate: Dictionary = lab._nearest_unit_enemy(source, 1)
	lab._enemy_query_owner_cell_window = false
	if admitted != expected_fast or (lab.enemy_query_owner_cell_hits > hits_before) != expected_fast:
		_faults.append("Wrong owner-cell admission for " + label)
	if original != candidate:
		_faults.append("Enemy query differs for " + label + ": " + str(original) + " vs " + str(candidate))
	if expected_id >= 0 and int(candidate.get("identity", -1)) != expected_id:
		_faults.append("Wrong original target for " + label)
	return {"case": label, "admitted": admitted, "reference": original, "candidate": candidate}

func _direct_cases() -> Array:
	var world := _fixture(true)
	var lab: TerrainLab = world.lab
	var source: TerrainArmy = world.armies[0]
	var first: TerrainArmy = world.armies[1]
	var second: TerrainArmy = world.armies[2]
	var origin := _clear_patch(lab)
	var rows: Array = []
	if origin == TerrainArmy.INVALID_CELL or lab.combat_actors.is_empty():
		_faults.append("No clear formal patch or Actor for direct enemy-query cases")
	else:
		_place(source, 1, origin)
		_place(first, 1, origin + Vector2i.RIGHT)
		_place(second, 1, origin + Vector2i.UP)
		source.combat_units[1].target = -1
		rows.append(_query_case(lab, source, "equal-distance roster tie", true,
			mini(first.combat_identity(1), second.combat_identity(1))))
		source.combat_units[1].target = second.combat_identity(1)
		rows.append(_query_case(lab, source, "retained target", true, second.combat_identity(1)))
		source.combat_units[1].target = -1
		second.combat_hot_set(1, &"attack", true)
		second.combat_units[1].target = source.combat_identity(1)
		rows.append(_query_case(lab, source, "threat priority", true, second.combat_identity(1)))
		second.combat_hot_set(1, &"attack", false)
		first.combat_hot_set(1, &"ko", 1.0)
		second.combat_hot_set(1, &"ko", 1.0)
		var actor: TerrainTestCharacter = lab.combat_actors[0]
		actor.terrain_cell = origin + Vector2i.LEFT
		actor.faction_id = 1
		actor.hp = 100.0
		actor.knockout_left = 0.0
		rows.append(_query_case(lab, source, "Actor after soldiers", true, actor.combat_identity()))
		first.combat_hot_set(1, &"ko", 0.0)
		second.combat_hot_set(1, &"ko", 0.0)
		_place(second, 1, first.cells[1]) # Different enemy teams claim the same cell.
		rows.append(_query_case(lab, source, "cross-team same-cell fallback", false))
		_place(second, 1, origin + Vector2i.UP)
		var vehicles: Dictionary = lab.terrain.site.get("vehicles", {})
		vehicles["query_parity_vehicle"] = {"kind": "cart", "cell": 0, "facing": [1, 0],
			"team_id": first.team_id, "operator_id": -1}
		lab.terrain.site["vehicles"] = vehicles
		rows.append(_query_case(lab, source, "vehicle fallback", false))
		vehicles.erase("query_parity_vehicle")
		lab.terrain.site["vehicles"] = vehicles
		first.combat_hot_set(1, &"hp", 0.0)
		second.combat_hot_set(1, &"ko", 1.0)
		first._cell_owners.erase(first.cells[1])
		second._cell_owners.erase(second.cells[1])
		rows.append(_query_case(lab, source, "dead and KO unowned fallback", false, actor.combat_identity()))
	_dispose(world)
	return rows

func _run() -> void:
	if not OS.get_cmdline_user_args().is_empty() or ProjectSettings.get_setting("application/run/main_scene") != "res://scenes/terrain_lab/TerrainLab.tscn":
		push_error("Use the formal TerrainLab project with no arguments")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT)) != OK:
		push_error("Cannot create enemy-query parity output")
		quit(1)
		return
	_output_path = "%s/parity_%d_%d.json" % [OUT, int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var sources_before := _sources()
	var reference := _fixture(false)
	var candidate := _fixture(true)
	var oracle := TerrainArmy._get_idle_kernel()
	if oracle == null or not oracle.has_method("exact_value_equal"):
		_faults.append("Existing exact native oracle unavailable")
	var result := {"steps": [], "first_difference": "", "requested_steps": PARITY_STEPS,
		"scope": "Formal three-team TerrainLab exact owner replay plus direct query edge cases; not FPS"}
	for step in range(PARITY_STEPS + 1):
		if not _faults.is_empty() or Time.get_ticks_usec() >= _deadline_usec:
			if _faults.is_empty():
				_faults.append("Enemy-query parity exceeded bounded deadline at step %d" % step)
			break
		if step > 0:
			_advance(reference)
			_advance(candidate)
		var left: Dictionary = _state(reference)
		var right: Dictionary = _state(candidate)
		var exact: int = int(oracle.exact_value_equal(left, right))
		var difference := _first_difference(left, right) if exact == 0 else "unsupported oracle value" if exact != 1 else ""
		result.steps.append({"step": step, "reference_hash": _hash(left), "candidate_hash": _hash(right)})
		if not difference.is_empty():
			result.first_difference = difference
			result["first_difference_step"] = step
			_faults.append("Enemy-query owner state differs at step %d: %s" % [step, difference])
			break
	result["reference_hits"] = reference.lab.enemy_query_owner_cell_hits
	result["candidate_hits"] = candidate.lab.enemy_query_owner_cell_hits
	if result.reference_hits != 0 or result.candidate_hits <= 0:
		_faults.append("Enemy-query A/B did not exercise the original and indexed branches")
	_dispose(reference)
	_dispose(candidate)
	if _faults.is_empty():
		result["direct_cases"] = _direct_cases()
	var sources_after := _sources()
	if sources_before != sources_after:
		_faults.append("Source changed during enemy-query parity")
	result.merge({"sources_before": sources_before, "sources_after": sources_after,
		"faults": _faults, "passed": _faults.is_empty(), "engine": Engine.get_version_info()}, true)
	var file := FileAccess.open(_output_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	else:
		_faults.append("Cannot write enemy-query parity evidence")
	TerrainArmy.release_contact_source()
	print("ENEMY_QUERY_OWNER_CELLS_PARITY ", "PASS" if _faults.is_empty() else "FAIL", " ", _output_path)
	if not _faults.is_empty():
		push_error(str(_faults))
	quit(0 if _faults.is_empty() else 1)
