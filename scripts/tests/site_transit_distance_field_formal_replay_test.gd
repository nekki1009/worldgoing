extends "res://scripts/tests/site_movement_r3_replay_test.gd"
## Same formal r3 trace in both worlds; only the cold distance-field path differs.

const FIELD_REPLAY_OUT := "res://output/site_movement_cold_impl_20260929/replay"

func _sources() -> Dictionary:
	var sources: Dictionary = super._sources()
	var path := "res://scripts/tests/site_transit_distance_field_formal_replay_test.gd"
	sources[path] = FileAccess.get_sha256(path)
	return sources

func _fixture(field_native: bool) -> Dictionary:
	var world: Dictionary = super._fixture(true)
	world.native = field_native # The inherited _advance sets the planner switch from this field.
	world["distance_field_calls"] = 0
	return world

func _advance(world: Dictionary) -> int:
	var before: int = FormationTransitPlanner.native_distance_field_calls
	var elapsed: int = super._advance(world)
	world.distance_field_calls += FormationTransitPlanner.native_distance_field_calls - before
	return elapsed

func _coverage(world: Dictionary) -> Dictionary:
	var result: Dictionary = super._coverage(world)
	result["native_distance_field_calls"] = world.distance_field_calls
	return result

func _oracle(reference_only: bool) -> Dictionary:
	var result: Dictionary = super._oracle(reference_only)
	if not reference_only and (int(result.reference_coverage.native_distance_field_calls) != 0 \
			or int(result.candidate_coverage.native_distance_field_calls) <= 0):
		_faults.append("Field oracle did not compare GD against an exercised native distance field")
	return result

func _timing(field_native: bool) -> Dictionary:
	var result: Dictionary = super._timing(field_native)
	if field_native and int(result.coverage.native_distance_field_calls) <= 0 \
			or not field_native and int(result.coverage.native_distance_field_calls) != 0:
		_faults.append("Field timing used the wrong distance-field path")
	return result

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var oracle: bool = args == PackedStringArray(["--oracle"])
	var timing: bool = args == PackedStringArray(["--timing", "--reference"]) \
		or args == PackedStringArray(["--timing", "--candidate"])
	if not oracle and not timing:
		push_error("Use --oracle or --timing --reference/--candidate")
		quit(1)
		return
	if ProjectSettings.get_setting("application/run/main_scene") != "res://scenes/terrain_lab/TerrainLab.tscn":
		push_error("Formal TerrainLab entry changed")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIELD_REPLAY_OUT)) != OK:
		push_error("Cannot create distance-field replay directory")
		quit(1)
		return
	_output_path = "%s/%s_%d_%d.json" % [FIELD_REPLAY_OUT, "_".join(args).replace("--", ""), int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	_mark("run.begin")
	var sources_before := _sources()
	var result: Dictionary = _oracle(false) if oracle else _timing(args.has("--candidate"))
	var sources_after := _sources()
	if sources_before != sources_after:
		_faults.append("Source changed during distance-field replay")
	result.merge({"scope": "Formal TerrainLab UI PLAINS 581, 100 x 3, 450 fixed action steps; r3 on in both worlds; only transit distance-field GD/native differs; not FPS",
		"steps_requested": STEPS, "step_seconds": STEP, "warmup_steps": WARMUP_STEPS,
		"sources_before": sources_before, "sources_after": sources_after,
		"engine": Engine.get_version_info(), "cpu": OS.get_processor_name(), "arguments": args,
		"faults": _faults, "passed": _faults.is_empty() and (not oracle or result.steps.size() == STEPS + 1)}, true)
	var file := FileAccess.open(_output_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write distance-field replay evidence")
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	TerrainArmy.release_contact_source()
	print("TRANSIT_FIELD_REPLAY ", "PASS" if result.passed else "FAIL", " ", _output_path)
	if not result.passed:
		push_error(str(_faults))
	quit(0 if result.passed else 1)
