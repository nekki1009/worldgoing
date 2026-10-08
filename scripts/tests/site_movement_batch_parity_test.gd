extends SceneTree
## S1 oracle: two independent original owner worlds, one GD and one native intent.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const STEP := 1.0 / 30.0
const STEPS := 450
const OUTPUT_DIR := "res://output/site_movement_batch_implementation_20260928/"

func _initialize() -> void:
	_run.call_deferred()
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("MOVEMENT BATCH PARITY timed out")
		quit(1))

func _fixture(native_enabled: bool) -> Dictionary:
	var terrain := Helper.build_flat_map(72, 36)
	var owner_root := Node2D.new()
	root.add_child(owner_root)
	var coordinator := Coordinator.new()
	var armies: Array[TerrainArmy] = []
	for side in range(2):
		var origin := Vector2i(4, 8 if side == 0 else 19)
		var army := Helper.create_test_army(terrain, side + 1, side, 8, origin)
		owner_root.add_child(army)
		coordinator.register_formation(army)
		army.set("native_move_intent_enabled", native_enabled)
		armies.append(army)
	armies[0].external_blocker = armies[1].blocks_cell
	armies[1].external_blocker = armies[0].blocks_cell
	for side in range(2):
		var goal := Vector2i(52, 8 if side == 0 else 19)
		assert(armies[side].issue_combat_order(armies[side].current_commander,
			TerrainArmy.CombatOrder.MOVE, goal).ok)
	return {"root": owner_root, "coordinator": coordinator, "armies": armies}

func _dispose(world: Dictionary) -> void:
	for army: TerrainArmy in world.armies:
		army.external_blocker = Callable()
		world.coordinator.unregister_formation(army)
	world.root.free()

func _script_state(owner: Object) -> Dictionary:
	if owner == null:
		return {}
	var state := {}
	for property: Dictionary in owner.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name := str(property.name)
		var value: Variant = owner.get(name)
		if not value is Object:
			state[name] = value
	for name: StringName in owner.get_meta_list():
		state["@" + str(name)] = owner.get_meta(name)
	return state

func _proposal_state(grid: SiteMovementReservationGrid) -> Array:
	var result := []
	for p in grid.get_proposals():
		result.append([p.proposal_id, p.formation_id, p.member_id, p.order_serial,
			p.from_cell, p.to_cell, p.emergency_priority, p.wait_age_ticks,
			p.formation_rr_rank, p.front_rank, p.formation_persistent_serial,
			p.status, p.dependency_proposal_id])
	return result

func _state(world: Dictionary) -> Dictionary:
	var coordinator: SiteCombatMovementCoordinator = world.coordinator
	var grid := coordinator.movement_reservation_grid
	var teams := []
	var route_allocations := []
	for army: TerrainArmy in world.armies:
		var people := []
		for index in range(army.combat_units.size()):
			people.append([army.combat_identity(index), army.combat_hot_get(index, &"hp"),
				army.combat_hot_get(index, &"ko")])
		teams.append({
			"people": people,
			"cells": army.cells.duplicate(), "moving_to": army.moving_to.duplicate(),
			"progress": army.move_progress.duplicate(), "duration": army.move_duration.duplicate(),
			"slots": army.combat_slots.duplicate(), "facing": army.facing.duplicate(),
			"order": army.combat_order, "order_serial": army.get_order_serial(),
			"order_delay": army._order_delay, "rng": army.command_rng.state,
			"proposal_count": army.proposal_count, "accepted_count": army.accepted_count,
			"rejected_count": army.rejected_dependency_count,
			"reserved": army._reserved_cells.duplicate(),
			"batch_members": army._combat_batch_members.duplicate(),
			"absent_slots": army._combat_absent_slots.duplicate(),
			"move_plan": _script_state(army.get_active_move_plan()),
			"deployment_plan": _script_state(army.get_active_deployment_plan()),
			"inflight": coordinator.get_inflight_batches_for_formation(army),
		})
		route_allocations.append(coordinator.route_budget.get_allocation(army.try_get_formation_id()))
	return {
		"logic_tick": coordinator.current_logic_tick,
		"teams": teams,
		"route_allocations": route_allocations,
		"route_site_calls": coordinator.route_budget.site_calls_used,
		"route_site_expansions": coordinator.route_budget.site_expansions_used,
		"occupancy": coordinator._current_occupancy.duplicate(),
		"retained": coordinator.get_retained_occupancy().duplicate(),
		"grid_initial": grid.initial_occupancy.duplicate(),
		"grid_committed": grid.committed_occupancy.duplicate(),
		"grid_blocked": grid.blocked_destinations.duplicate(),
		"proposals": _proposal_state(grid),
	}

func _first_difference(reference: Variant, candidate: Variant, path: String = "") -> String:
	if typeof(reference) != typeof(candidate):
		return path + " (type)"
	if reference is Dictionary:
		for key: Variant in reference:
			var child := path + "." + str(key) if not path.is_empty() else str(key)
			if not candidate.has(key):
				return child + " (missing)"
			var mismatch := _first_difference(reference[key], candidate[key], child)
			if not mismatch.is_empty():
				return mismatch
		for key: Variant in candidate:
			if not reference.has(key):
				return path + "." + str(key) + " (extra)"
		return ""
	if reference is Array:
		if reference.size() != candidate.size():
			return path + ".size"
		for index in range(reference.size()):
			var mismatch := _first_difference(reference[index], candidate[index], path + "[" + str(index) + "]")
			if not mismatch.is_empty():
				return mismatch
		return ""
	return "" if reference == candidate else path

func _record(result: Dictionary) -> void:
	var absolute_dir := ProjectSettings.globalize_path(OUTPUT_DIR)
	if DirAccess.make_dir_recursive_absolute(absolute_dir) != OK:
		push_error("Cannot create parity evidence directory")
		return
	var name := "s1_parity_%d_%d.json" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var path := OUTPUT_DIR + name
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write parity evidence: " + path)
		return
	result["source_hashes"] = {
		"terrain_army": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"),
		"coordinator": FileAccess.get_sha256("res://scripts/terrain_lab/site_combat_movement_coordinator.gd"),
		"test": FileAccess.get_sha256("res://scripts/tests/site_movement_batch_parity_test.gd"),
	}
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("MOVEMENT_BATCH_PARITY_EVIDENCE ", path)

func _run() -> void:
	assert(_first_difference({"a": [1]}, {"a": [2]}) == "a[0]")
	var reference := _fixture(false)
	var candidate := _fixture(true)
	var mismatch := ""
	var failed_step := -1
	var failed_stage := ""
	var proposals := 0
	var accepted := 0
	var blocked_steps := 0
	var start_cells: Array = candidate.armies[0].cells.duplicate()
	for step in range(STEPS):
		var blocked := {}
		if step >= 45 and step < 65:
			blocked[reference.armies[0].cells[0] + Vector2i.RIGHT] = true
			blocked_steps += 1
		for world: Dictionary in [reference, candidate]:
			world.coordinator.combat_logic_tick_if_needed(STEP, blocked)
		var reference_state := _state(reference)
		var candidate_state := _state(candidate)
		mismatch = _first_difference(reference_state, candidate_state)
		if not mismatch.is_empty():
			failed_step = step
			failed_stage = "coordinator"
			break
		for p in candidate.coordinator.movement_reservation_grid.get_proposals():
			proposals += 1
			if p.status == CombatMovementTypes.MoveProposalStatus.ACCEPTED:
				accepted += 1
		for world: Dictionary in [reference, candidate]:
			for army: TerrainArmy in world.armies:
				army.prepare_combat(STEP, STEP)
			world.coordinator.complete_committed_moves()
			for army: TerrainArmy in world.armies:
				army.settle_combat_command()
		reference_state = _state(reference)
		candidate_state = _state(candidate)
		mismatch = _first_difference(reference_state, candidate_state)
		if not mismatch.is_empty():
			failed_step = step
			failed_stage = "physical_completion"
			break
	var reference_hits := 0
	var candidate_hits := 0
	for index in range(2):
		reference_hits += int(reference.armies[index].get("native_move_intent_hits"))
		candidate_hits += int(candidate.armies[index].get("native_move_intent_hits"))
	var moved: bool = candidate.armies[0].cells != start_cells
	var passed := failed_step < 0 and reference_hits == 0 and candidate_hits > 0 and proposals > 0 and accepted > 0 and moved
	_record({
		"status": "PASS" if passed else "FAIL", "steps_requested": STEPS,
		"steps_equal": STEPS if failed_step < 0 else failed_step,
		"first_mismatch_step": failed_step, "first_mismatch_stage": failed_stage,
		"first_mismatch_field": mismatch, "reference_native_hits": reference_hits,
		"candidate_native_hits": candidate_hits, "proposals": proposals,
		"accepted": accepted, "blocked_steps": blocked_steps, "physical_movement": moved,
	})
	_dispose(reference)
	_dispose(candidate)
	TerrainArmy.release_contact_source()
	if not passed:
		push_error("MOVEMENT BATCH PARITY FAIL step=%d stage=%s field=%s hits=%d/%d proposals=%d accepted=%d moved=%s" % [
			failed_step, failed_stage, mismatch, reference_hits, candidate_hits, proposals, accepted, str(moved)])
		quit(1)
		return
	print("MOVEMENT BATCH PARITY PASS: 450 exact owner steps, GD/native proposals and physical commits, native hits=", candidate_hits)
	quit(0)
