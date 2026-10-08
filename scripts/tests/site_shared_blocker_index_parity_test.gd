extends "res://scripts/tests/site_movement_r3_replay_test.gd"
## Exact original-owner replay with only the disposable cross-team blocker view toggled.

const OUT := "res://output/site_crowd_d1_20260929/shared_blocker_parity"
const PARITY_STEPS := 30

func _fixture(shared_enabled: bool) -> Dictionary:
	var world: Dictionary = super._fixture(true)
	var coordinator: SiteCombatMovementCoordinator = world.coordinator
	coordinator.shared_blocker_index_enabled = shared_enabled
	world["shared_enabled"] = shared_enabled
	return world

func _verify_index(world: Dictionary) -> void:
	var coordinator: SiteCombatMovementCoordinator = world.coordinator
	var saved_plans: Array = []
	for team: TerrainArmy in world.armies:
		saved_plans.append([team.get_active_move_plan(), team.get_active_deployment_plan()])
		team._combat_move_plan = null
		team._combat_deployment_plan = null
		team.begin_combat_movement_read_scope()
		team.current_logic_tick = coordinator.current_logic_tick
	coordinator._publish_shared_blocker_index()
	if coordinator.shared_blocker_index_builds != 1 or coordinator.shared_blocker_index_copied_maps != 0:
		_faults.append("Canonical three-team shared blocker index was not admitted")
	var first: TerrainArmy = world.armies[0]
	var second: TerrainArmy = world.armies[1]
	var held: TerrainArmy = world.armies[2]
	var foreign_cell: Vector2i = first.cells[0]
	if held._shared_movement_blockers_valid() or not bool(held.external_blocker.call(foreign_cell)) \
		or held._is_external_cell(foreign_cell) != bool(held.external_blocker.call(foreign_cell)):
		_faults.append("Planless HOLD did not use the original blocker fallback")
	# A plan created after the first publication must still read the original
	# callback until the next publication in this same read scope.
	first._combat_move_plan = CombatMovePlan.new()
	second._combat_deployment_plan = CombatDeploymentPlan.new()
	if first._shared_movement_blockers_valid() or first._is_external_cell(held.cells[0]) != bool(first.external_blocker.call(held.cells[0])):
		_faults.append("Late plan used a stale shared blocker map")
	coordinator._publish_shared_blocker_index()
	if coordinator.shared_blocker_index_copied_maps != 2:
		_faults.append("Late move and deployment plans did not each receive a map")
	var claimed: Dictionary = {}
	for team: TerrainArmy in world.armies:
		for cell: Vector2i in team._cell_owners:
			claimed[cell] = true
		for cell: Vector2i in team._reserved_cells:
			claimed[cell] = true
	for team: TerrainArmy in world.armies:
		if team == held:
			if team._shared_movement_blockers_valid() or team._is_external_cell(foreign_cell) != bool(team.external_blocker.call(foreign_cell)):
				_faults.append("Planless HOLD acquired a copied map")
			continue
		if not team._shared_movement_blockers_valid():
			_faults.append("Active plan did not acquire a shared map: team %d" % team.team_id)
		for cell: Vector2i in claimed:
			if team._shared_movement_blockers.has(cell) != bool(team.external_blocker.call(cell)):
				_faults.append("Shared claim differs from original callback: team %d cell %s" % [team.team_id, cell])
				break
	# A cell reserved by two teams remains external to each after excluding self.
	var overlap := Vector2i(-1, -1)
	first._reserved_cells[overlap] = -101
	second._reserved_cells[overlap] = -102
	coordinator._publish_shared_blocker_index()
	if coordinator.shared_blocker_index_copied_maps != 4:
		_faults.append("Overlapping-claim publication copied an unexpected number of maps")
	for team: TerrainArmy in world.armies:
		var actual: bool = team._is_external_cell(overlap) if team == held else team._shared_movement_blockers.has(overlap)
		if actual != bool(team.external_blocker.call(overlap)):
			_faults.append("Overlapping claim lost for team %d" % team.team_id)
	first._reserved_cells.erase(overlap)
	second._reserved_cells.erase(overlap)
	for index in range(world.armies.size()):
		var team: TerrainArmy = world.armies[index]
		team._combat_move_plan = saved_plans[index][0]
		team._combat_deployment_plan = saved_plans[index][1]
	for team: TerrainArmy in world.armies:
		team.end_combat_movement_read_scope()

func _run() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		push_error("This bounded parity test takes no arguments")
		quit(1)
		return
	if ProjectSettings.get_setting("application/run/main_scene") != "res://scenes/terrain_lab/TerrainLab.tscn":
		push_error("Formal TerrainLab entry changed")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT)) != OK:
		push_error("Cannot create shared blocker parity output")
		quit(1)
		return
	_output_path = "%s/parity_%d_%d.json" % [OUT, int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var sources_before := _sources()
	var reference := _fixture(false)
	var candidate := _fixture(true)
	_verify_index(candidate)
	var oracle := TerrainArmy._get_idle_kernel()
	if oracle == null or not oracle.has_method("exact_value_equal"):
		_faults.append("Existing exact native oracle unavailable")
	var result := {"steps": [], "first_difference": "", "reference_builds": 0,
		"candidate_builds": 0, "reference_attempts": 0, "candidate_attempts": 0,
		"reference_copied_maps": 0, "candidate_copied_maps": 0,
		"requested_steps": PARITY_STEPS,
		"scope": "Formal TerrainLab UI PLAINS 581, three teams of 100; exact owner state, not FPS"}
	if reference.terrain_hash != candidate.terrain_hash:
		_faults.append("Fixture terrain differs")
	for step in range(PARITY_STEPS + 1):
		if not _faults.is_empty() or Time.get_ticks_usec() >= _deadline_usec:
			if _faults.is_empty():
				_faults.append("Parity exceeded bounded deadline at step %d" % step)
			break
		if step > 0:
			_advance(reference)
			_advance(candidate)
		var left: Dictionary = _state(reference)
		var right: Dictionary = _state(candidate)
		var exact: int = int(oracle.exact_value_equal(left, right))
		var difference := ""
		if exact == 0:
			difference = _first_difference(left, right)
			if difference.is_empty():
				difference = "exact scalar bits or typed-container metadata"
		elif exact != 1:
			difference = "unsupported oracle value"
		result.steps.append({"step": step, "reference_hash": _hash(left), "candidate_hash": _hash(right)})
		if not difference.is_empty():
			result.first_difference = difference
			result["first_difference_step"] = step
			_faults.append("Shared blocker A/B owner state differs at step %d: %s" % [step, difference])
			break
	result.reference_builds = reference.coordinator.shared_blocker_index_builds
	result.candidate_builds = candidate.coordinator.shared_blocker_index_builds
	result.reference_attempts = reference.coordinator.shared_blocker_index_attempts
	result.candidate_attempts = candidate.coordinator.shared_blocker_index_attempts
	result.reference_copied_maps = reference.coordinator.shared_blocker_index_copied_maps
	result.candidate_copied_maps = candidate.coordinator.shared_blocker_index_copied_maps
	if result.reference_builds != 0 or result.candidate_attempts < 2 \
		or result.candidate_builds != result.candidate_attempts \
		or result.reference_copied_maps != 0 or result.candidate_copied_maps < 4:
		_faults.append("A/B toggle did not cover every full Coordinator tick")
	var sources_after := _sources()
	if sources_before != sources_after:
		_faults.append("Source changed during parity test")
	result.merge({"sources_before": sources_before, "sources_after": sources_after,
		"engine": Engine.get_version_info(), "faults": _faults, "passed": _faults.is_empty()}, true)
	var file := FileAccess.open(_output_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	else:
		_faults.append("Cannot write parity evidence")
	_dispose(reference)
	_dispose(candidate)
	TerrainArmy.release_contact_source()
	print("SHARED_BLOCKER_PARITY ", "PASS" if _faults.is_empty() else "FAIL", " ", _output_path)
	if not _faults.is_empty():
		push_error(str(_faults))
	quit(0 if _faults.is_empty() else 1)
