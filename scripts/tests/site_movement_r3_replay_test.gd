extends "res://scripts/tests/site_movement_formal_replay_test.gd"
## Compare r3 with the already-native r2 path on the same formal UI trace.

const R3_REPLAY_OUT := "res://output/site_movement_plan_revision3_20260928/implementation/replay"

func _sources() -> Dictionary:
	var sources: Dictionary = super._sources()
	for path: String in ["res://scripts/tests/site_movement_r3_replay_test.gd",
		"res://scripts/terrain_lab/formation_destination_planner.gd",
		"res://scripts/terrain_lab/combat_move_plan.gd",
		"res://scripts/terrain_lab/combat_deployment_plan.gd"]:
		sources[path] = FileAccess.get_sha256(path)
		if str(sources[path]).length() != 64:
			_faults.append("Missing r3 source hash: " + path)
	return sources

func _fixture(r3_enabled: bool) -> Dictionary:
	# Keep every r2 native switch on in both worlds. These r3 switches are
	# applied after normal UI deployment and before the first action step.
	var world: Dictionary = super._fixture(true)
	for army: TerrainArmy in world.armies:
		for property: String in ["r3_fused_propose_enabled", "r3_prepare_enabled"]:
			if not property in army:
				_faults.append("Missing r3 switch: " + property)
			else:
				army.set(property, r3_enabled)
	world["r3_enabled"] = r3_enabled
	return world

func _coverage(world: Dictionary) -> Dictionary:
	var result: Dictionary = super._coverage(world)
	for army: TerrainArmy in world.armies:
		var team: Dictionary = result[str(army.team_id)]
		team["r3_enabled"] = bool(world.r3_enabled)
		for field: String in ["r3_fused_propose_hits", "r3_fused_propose_fallbacks"]:
			if field in army:
				team[field] = army.get(field)
	return result

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var is_oracle: bool = args == PackedStringArray(["--oracle"])
	var is_timing: bool = args == PackedStringArray(["--timing", "--baseline"]) \
		or args == PackedStringArray(["--timing", "--candidate"])
	if not is_oracle and not is_timing:
		push_error("Use --oracle or --timing --baseline/--candidate")
		quit(1)
		return
	if ProjectSettings.get_setting("application/run/main_scene") != "res://scenes/terrain_lab/TerrainLab.tscn":
		push_error("Formal TerrainLab entry changed")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(R3_REPLAY_OUT)) != OK:
		push_error("Cannot create r3 replay directory")
		quit(1)
		return
	_output_path = "%s/%s_%d_%d.json" % [R3_REPLAY_OUT,
		"_".join(args).replace("--", ""), int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	_mark("run.begin")
	var sources_before := _sources()
	var result: Dictionary = _oracle(false) if is_oracle else _timing(args.has("--candidate"))
	var sources_after := _sources()
	if sources_before != sources_after:
		_faults.append("Source changed during r3 replay")
	if is_timing and bool(result.get("coverage", {}).get("1", {}).get("r3_enabled", false)) != args.has("--candidate"):
		_faults.append("Incorrect r3 timing mode")
	result.merge({"revision": 3, "baseline": "r2 native + common in-flight route fix",
		"steps_requested": STEPS, "step_seconds": STEP,
		"stage_samples": "steps_31_450" if is_timing else "not_applicable",
		"scope": "Formal TerrainLab UI PLAINS 581, 100 x 3, fixed original action CPU replay; not FPS",
		"sources_before": sources_before, "sources_after": sources_after,
		"engine": Engine.get_version_info(), "cpu": OS.get_processor_name(),
		"arguments": args, "faults": _faults, "passed": _faults.is_empty()}, true)
	var file := FileAccess.open(_output_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write r3 replay evidence")
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	TerrainArmy.release_contact_source()
	print("R3_MOVEMENT_REPLAY ", "PASS" if _faults.is_empty() else "FAIL", " ", _output_path)
	if not _faults.is_empty():
		push_error(str(_faults))
	quit(0 if _faults.is_empty() else 1)
