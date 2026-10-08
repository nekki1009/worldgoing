extends "res://scripts/tests/site_movement_r3_replay_test.gd"
## Component cost only. The original 120-step world must remain unchanged.

func _run() -> void:
	_output_path = "res://output/site_movement_event_audit_20260928/cold_search_%d.json" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_path.get_base_dir()))
	var sources := _sources()
	var world := _fixture(true)
	for step in range(120):
		_advance(world)
	var army: TerrainArmy = world.armies[0]
	var plan := army.get_active_move_plan()
	var before := _hash(_state(world))
	var copy := CombatMovePlan.new()
	copy.macro_path = plan.macro_path
	copy.path_epoch = plan.path_epoch
	copy.terrain_revision = plan.terrain_revision
	var started := Time.get_ticks_usec()
	var cold_field := FormationTransitPlanner.get_transit_distance_field(copy, army.data, army._formation_movement_profile)
	var cold_usec := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var warm_field := FormationTransitPlanner.get_transit_distance_field(copy, army.data, army._formation_movement_profile)
	var warm_usec := Time.get_ticks_usec() - started
	var coordinator := army._coordinator
	var egress_state: Object = coordinator.get_egress_search_state(army.get_formation_id())
	# This synchronous original function only saves/retries through coordinator;
	# temporarily omit that sink to measure a fresh search without publishing it.
	army._coordinator = null
	started = Time.get_ticks_usec()
	var cold_egress := army._build_egress_distance_field(plan.macro_path, plan.macro_cursor, army._formation_movement_profile)
	var egress_usec := Time.get_ticks_usec() - started
	army._coordinator = coordinator
	var after := _hash(_state(world))
	if before != after:
		_faults.append("Component audit changed original world state")
	if _sources() != sources:
		_faults.append("Source changed during component audit")
	if cold_field != warm_field:
		_faults.append("Cold and warm distance fields differ")
	var data := {"scope": "Diagnostic cold component calls at original formal replay step 120; not optimization or FPS",
		"sources_before": sources, "sources_after": _sources(), "before": before, "after": after,
		"cold_transit_usec": cold_usec, "warm_transit_usec": warm_usec, "transit_cells": cold_field.size(),
		"cold_egress_usec": egress_usec, "egress_cells": cold_egress.size(),
		"egress_matches_original": egress_state != null and cold_egress == egress_state.distances,
		"passed": _faults.is_empty(), "faults": _faults}
	var file := FileAccess.open(_output_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write cold search audit")
		quit(1)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	world.root.free()
	TerrainArmy.release_contact_source()
	print("COLD_SEARCH_AUDIT ", "PASS" if data.passed else "FAIL", " ", _output_path)
	quit(0 if data.passed else 1)
