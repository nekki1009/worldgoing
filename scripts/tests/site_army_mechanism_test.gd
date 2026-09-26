extends SceneTree
## Generated admission evidence. Missing or stale behavioral results remain FAIL.

const Gate = preload("res://scripts/tests/fixtures/site_army_mechanism_gate.gd")
const Stream = preload("res://scripts/tests/site_army_oracle_stream_test.gd")
const ROOT := Gate.EVIDENCE_ROOT
const OUTPUT := ROOT + "mechanism_result.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if "--manifest-only" in OS.get_cmdline_user_args():
		var manifest: Dictionary = Gate.capture_source_manifest()
		var manifest_result := {"status": "PASS" if manifest.errors.is_empty() else "FAIL",
			"generated_by": Gate.GENERATOR, "engine": Engine.get_version_info(),
			"source_sha256": manifest.hashes, "errors": manifest.errors}
		_write_json(ROOT + "source_manifest.json", manifest_result)
		quit(0 if manifest.errors.is_empty() else 1)
		return
	if "--scope-only" in OS.get_cmdline_user_args():
		var scope_only := _hot_scope()
		var scope_path := ROOT + "hot_scope_selfcheck.json"
		_write_json(scope_path, scope_only)
		if scope_only.get("status") != "PASS":
			push_error("SITE_ARMY_HOT_SCOPE_FAIL " + str(scope_only.get("failure")) + " output=" + scope_path)
			quit(1)
			return
		print("SITE_ARMY_HOT_SCOPE_PASS output=", scope_path)
		quit(0)
		return
	var source_capture: Dictionary = Gate.capture_source_manifest()
	var assertions := {}
	for name: String in Gate.ASSERTIONS: assertions[name] = false
	var observations := {}
	var failures: Array[String] = []
	for problem: String in source_capture.errors: failures.append(problem)
	var store: Variant = _json(ROOT + "hot_store_smoke.json")
	var store_valid := _store_smoke_valid(store)
	observations["hot_store_smoke_valid"] = store_valid
	if not store_valid: failures.append("hot_store_smoke_missing_or_stale")
	var prepare: Variant = _json(ROOT + "hot_prepare_smoke.json")
	var prepare_valid := _prepare_smoke_valid(prepare)
	observations["hot_prepare_smoke_valid"] = prepare_valid
	if not prepare_valid: failures.append("hot_prepare_smoke_missing_or_stale")
	assertions.pure_visual_no_owner_barrier = store_valid and prepare_valid \
		and bool(store.checks.get("pure_visual_no_owner_barrier", false)) \
		and bool(prepare.checks.get("pure_visual_no_owner_barrier", false))
	if prepare_valid:
		observations["pure_visual_stats"] = prepare.pure_visual_stats
		observations["visual_expiry_stats"] = prepare.visual_expiry_stats
	var lifecycle: Variant = _json(ROOT + "hot_lifecycle_smoke.json")
	var lifecycle_valid := _lifecycle_smoke_valid(lifecycle)
	observations["hot_lifecycle_smoke_valid"] = lifecycle_valid
	if not lifecycle_valid: failures.append("hot_lifecycle_smoke_missing_or_stale")
	var projection: Variant = _json(ROOT + "hot_projection_smoke.json")
	var projection_valid := _projection_smoke_valid(projection)
	observations["hot_projection_smoke_valid"] = projection_valid
	if not projection_valid: failures.append("hot_projection_smoke_missing_or_stale")
	var presenter: Variant = _json(ROOT + "retained_batch_smoke.json")
	var presenter_valid := _presenter_smoke_valid(presenter)
	observations["retained_batch_smoke_valid"] = presenter_valid
	if not presenter_valid: failures.append("retained_batch_smoke_missing_or_stale")
	var army_retained: Variant = _json(ROOT + "hot_retained_integration_smoke.json")
	var army_retained_valid := _army_retained_valid(army_retained)
	observations["hot_retained_integration_valid"] = army_retained_valid
	if not army_retained_valid: failures.append("hot_retained_integration_missing_or_stale")
	var pixels: Variant = _json(ROOT + "pixel_occlusion_smoke.json")
	var pixels_valid := _pixel_occlusion_valid(pixels)
	observations["pixel_occlusion_valid"] = pixels_valid
	if not pixels_valid: failures.append("pixel_occlusion_missing_or_stale")
	assertions.pixel_occlusion_full_rgba_exact = pixels_valid
	var native_exact: Variant = _json(ROOT + "native_exact_oracle_smoke.json")
	var native_exact_valid := _native_exact_smoke_valid(native_exact)
	var stream_selfcheck: Variant = _json(ROOT + "oracle_stream_selfcheck.json")
	var stream_selfcheck_valid := _stream_selfcheck_valid(stream_selfcheck)
	observations["native_exact_oracle_valid"] = native_exact_valid
	observations["oracle_stream_selfcheck_valid"] = stream_selfcheck_valid
	if not native_exact_valid: failures.append("native_exact_oracle_missing_or_stale")
	if not stream_selfcheck_valid: failures.append("oracle_stream_selfcheck_missing_or_stale")
	assertions.native_exact_oracle_boundary = native_exact_valid and stream_selfcheck_valid
	var render_5k: Variant = _json(ROOT + "render_5k_mechanism.json")
	var render_5k_valid := _render_5k_valid(render_5k, source_capture)
	observations["render_5k_mechanism_valid"] = render_5k_valid
	if render_5k is Dictionary:
		observations["render_5k_late_hot_stats"] = render_5k.get("late_hot_stats", [])
	if not render_5k_valid: failures.append("render_5k_mechanism_missing_or_stale")
	if presenter_valid:
		var checks: Dictionary = presenter.assertions
		var counters: Dictionary = presenter.counters
		assertions.static_unchanged_zero_projection = render_5k_valid and army_retained_valid and bool(checks.get("unchanged_no_static_0", false)) and bool(checks.get("unchanged_no_static_1", false)) and bool(checks.get("unchanged_no_regroup_0", false)) and bool(checks.get("unchanged_no_regroup_1", false))
		assertions.animation_unchanged_zero_upload = army_retained_valid and bool(checks.get("unchanged_no_upload_0", false)) and bool(checks.get("unchanged_no_upload_1", false))
		for label: String in ["unchanged_0", "unchanged_1"]:
			var unchanged: Variant = counters.get(label)
			if not unchanged is Dictionary:
				assertions.static_unchanged_zero_projection = false
				assertions.animation_unchanged_zero_upload = false
				continue
			for field: String in ["static_observations", "ground_projections", "row_rebuilds", "run_rebuilds"]:
				if int(unchanged.get(field, -1)) != 0: assertions.static_unchanged_zero_projection = false
			for field: String in ["packed_instances", "packed_bytes", "multimesh_setters", "multimesh_bytes", "gpu_dispatches"]:
				if int(unchanged.get(field, -1)) != 0: assertions.animation_unchanged_zero_upload = false
			if int(unchanged.get("animation_samples", 0)) <= 0: assertions.animation_unchanged_zero_upload = false
		assertions.frame_anchor_and_full_change_exact = projection_valid and army_retained_valid and bool(checks.get("exact_frame", false)) and bool(checks.get("exact_native_frame", false)) and bool(checks.get("exact_filtered_frame", false)) and bool(checks.get("frame_no_static_or_regroup", false)) and bool(checks.get("native_frame_no_static", false)) \
			and int(counters.get("frame", {}).get("changed_outputs", 0)) > 0 and int(counters.get("native_frame", {}).get("changed_outputs", 0)) > 0
		assertions.rejected_full_projection_detected = bool(checks.get("full_reference_observed", false)) and int(counters.get("full_reference", {}).get("static_observations", 0)) > 0 and int(counters.get("full_reference", {}).get("ground_projections", 0)) > 0
		# The direct fixture proves changed person/row/page/Sprite; roster,
		# restore and vehicle transitions need a separate integrated check.
		observations["presenter_comparisons"] = presenter.comparisons
		observations["presenter_counters"] = counters
	var reference: Variant = _json(Stream.REFERENCE_REPORT)
	var candidate: Variant = _json(Stream.CANDIDATE_REPORT)
	var oracle_valid := _oracle_valid(reference, candidate, source_capture)
	observations["oracle_valid"] = oracle_valid
	if not oracle_valid: failures.append("full_oracle_missing_or_stale")
	assertions.logical_1800_exact = oracle_valid and native_exact_valid and stream_selfcheck_valid
	if oracle_valid:
		var samples: Array = candidate.hot_stats
		observations["hot_stats"] = samples
		assertions.canonical_hot_dictionary_zero = _hot_dictionary_zero(samples)
		assertions.no_full_roster_sync = _no_roster_sync(samples)
		assertions.late_5k_active_and_costed = render_5k_valid and _late_path_measured(samples, reference, candidate)
		assertions.native_no_barrier_single_call = store_valid and bool(store.checks.get("native_no_barrier_single_call", false))
		assertions.native_barrier_order = store_valid and bool(store.checks.get("native_barrier_order", false))
	var scope: Dictionary = _hot_scope() if lifecycle_valid and source_capture.errors.is_empty() else {"status": "FAIL", "failure": "lifecycle_smoke_or_source_manifest_stale"}
	observations["hot_scope"] = scope
	assertions.local_mutation_and_roster_scope = army_retained_valid and scope.get("status") == "PASS" \
		and scope.get("checks", {}).get("save_restore_hot") == true \
		and scope.get("checks", {}).get("restore_resumes_with_control_and_cargo") == true \
		and scope.get("generator_sha256") == FileAccess.get_sha256(Gate.GENERATOR) \
		and scope.get("army_sha256") == FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd") \
		and scope.get("dll_sha256") == FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll")
	for name: String in Gate.ASSERTIONS:
		if not bool(assertions[name]): failures.append("assertion:" + name)
	var dependencies := {}
	for filename: String in Gate.EVIDENCE_FILES:
		var digest := FileAccess.get_sha256(ROOT + filename)
		dependencies[filename] = digest
		if digest.length() != 64: failures.append("evidence_dependency_missing:" + filename)
	var result := {"schema": 1, "status": "PASS" if failures.is_empty() else "FAIL",
		"generated_by": Gate.GENERATOR,
		"fixture": {"scene": "res://scenes/terrain_lab/TerrainLab.tscn", "preset": "PLAINS",
			"seed": 581, "per_team": 2500, "teams": 2},
		"engine": Engine.get_version_info(), "source_sha256": source_capture.hashes,
		"evidence_sha256": dependencies,
		"assertions": assertions, "observations": observations, "failures": failures}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		push_error("Could not write generated mechanism result")
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	if not failures.is_empty():
		push_error("SITE_ARMY_MECHANISM_FAIL " + str(failures) + " output=" + OUTPUT)
		quit(1)
		return
	print("SITE_ARMY_MECHANISM_PASS output=", OUTPUT)
	quit(0)


func _native_exact_smoke_valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("status") != "PASS" or not value.get("checks") is Dictionary \
			or not value.get("source_sha256") is Dictionary:
		return false
	for name: String in ["dictionary_order", "mixed_key_order", "mixed_key_string_vs_int",
			"mixed_key_name_vs_string", "optional_key", "int_float_type", "array_order",
			"typed_array_equal", "typed_array_metadata", "float_signed_zero",
			"packed_float_signed_zero", "vector2i_value", "string_name_equal",
			"packed_float_equal", "unsupported_color", "unsupported_object",
			"unsupported_callable", "unsupported_signal", "input_bytes_unchanged",
			"fixture_negative_zero_distinct", "native_methods_present"]:
		if value.checks.get(name) != true: return false
	return value.source_sha256.get("cpp") == FileAccess.get_sha256("res://native/army_idle/army_idle.cpp") \
		and value.source_sha256.get("dll") == FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll") \
		and value.source_sha256.get("test") == FileAccess.get_sha256("res://scripts/tests/site_army_native_exact_oracle_test.gd")


func _stream_selfcheck_valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("status") != "PASS" \
			or value.get("fixture_sha256") != FileAccess.get_sha256("res://scripts/tests/site_army_oracle_stream_test.gd"):
		return false
	var boundary: Variant = value.get("unsupported_serialization")
	if not boundary is Dictionary: return false
	for kind: String in ["object", "callable", "signal"]:
		if boundary.get(kind) != true: return false
	var stream: Variant = value.get("segment_stream")
	return stream is Dictionary and stream.get("skip_decode_and_end") == true \
		and stream.get("reject_corrupt_length") == true


func _store_smoke_valid(value: Variant) -> bool:
	if not value is Dictionary or not value.get("checks") is Dictionary:
		return false
	for name: String in ["atomic_rejection", "capture", "get_set_erase", "load_and_isolation",
			"numeric_and_flag_columns", "single_row_borrow", "pure_visual_no_owner_barrier",
			"visual_expiry_ordered_barrier", "owner_reason_abi", "attack_reason",
			"hold_think_reason", "pose_expiry_reason", "rescue_reason", "think_reason",
			"visual_expiry_reason"]:
		if value.checks.get(name) != true: return false
	return value.get("cpp_sha256") == FileAccess.get_sha256("res://native/army_idle/army_idle.cpp") \
		and value.get("dll_sha256") == FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll") \
		and value.get("test_sha256") == FileAccess.get_sha256("res://scripts/tests/site_army_hot_store_native_test.gd")


func _prepare_smoke_valid(value: Variant) -> bool:
	if not value is Dictionary or not value.get("checks") is Dictionary:
		return false
	for name: String in ["four_step_exact_rows", "hold_safe_prefix_and_barrier_exact",
			"native_no_barrier_whole_roster", "pure_visual_no_owner_barrier",
			"visual_expiry_ordered_barrier_exact", "owner_reason_totals_exact",
			"attack_think_two_step_exact_native", "attack_pose_expiry_exact"]:
		if value.checks.get(name) != true: return false
	var visual: Variant = value.get("pure_visual_stats")
	var expiry: Variant = value.get("visual_expiry_stats")
	var attack: Variant = value.get("attack_think_stats")
	var attack_expiry: Variant = value.get("attack_expiry_stats")
	if not visual is Dictionary or not expiry is Dictionary \
			or not attack is Dictionary or not attack_expiry is Dictionary \
			or visual.get("active") != true or expiry.get("active") != true \
			or visual.get("coverage_complete") != true or expiry.get("coverage_complete") != true \
			or int(visual.get("native_calls", -1)) != 1 or int(visual.get("native_rows", -1)) != 8 \
			or int(visual.get("fallback_rows", -1)) != 0 or not visual.get("barriers") is Dictionary \
			or not visual.barriers.is_empty() or not _owner_reasons_complete(visual) \
			or int(visual.get("materialized_rows", -1)) != 0 \
			or int(expiry.get("fallback_rows", -1)) != 1 or not expiry.get("barriers") is Dictionary \
			or int(expiry.barriers.get("3", -1)) != 1 or not _owner_reasons_complete(expiry) \
			or int(expiry.owner_reasons.get("visual_expiry", -1)) != 1 \
			or int(attack.get("native_calls", -1)) != 2 or int(attack.get("native_rows", -1)) != 16 \
			or int(attack.get("fallback_rows", -1)) != 0 or not _owner_reasons_complete(attack) \
			or not attack.barriers.is_empty() or not _owner_reasons_complete(attack_expiry) \
			or int(attack_expiry.owner_reasons.get("pose_expiry", -1)) != 1 \
			or int(expiry.get("hot_dictionary_unscoped_reads", -1)) != 0 \
			or int(expiry.get("hot_dictionary_unscoped_writes", -1)) != 0:
		return false
	return value.get("army_sha256") == FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd") \
		and value.get("cpp_sha256") == FileAccess.get_sha256("res://native/army_idle/army_idle.cpp") \
		and value.get("dll_sha256") == FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll") \
		and value.get("test_sha256") == FileAccess.get_sha256("res://scripts/tests/site_army_hot_prepare_test.gd")


func _lifecycle_smoke_valid(value: Variant) -> bool:
	if not value is Dictionary or not value.get("checks") is Dictionary:
		return false
	for name: String in ["admission", "cold_reference", "member_query", "optional_key",
			"owner_reads_and_writes", "release_rebind", "single_and_full_materialization", "single_row_borrow"]:
		if value.checks.get(name) != true: return false
	return value.get("army_sha256") == FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd") \
		and value.get("cpp_sha256") == FileAccess.get_sha256("res://native/army_idle/army_idle.cpp") \
		and value.get("dll_sha256") == FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll") \
		and value.get("test_sha256") == FileAccess.get_sha256("res://scripts/tests/site_army_hot_lifecycle_test.gd")


func _projection_smoke_valid(value: Variant) -> bool:
	if not value is Dictionary or not value.get("checks") is Dictionary:
		return false
	for name: String in ["alias_rejection", "can_act", "capture_columns", "capture_people",
			"command_presence", "command_presence_delta", "empty_visual_rejection",
			"hold_empty_visual_barrier", "hold_guard", "hold_idle_exact", "hold_ko_death",
			"hold_think_barrier", "moving_walk_exact", "render_idle", "retained_idle_mask"]:
		if value.checks.get(name) != true: return false
	return value.get("cpp_sha256") == FileAccess.get_sha256("res://native/army_idle/army_idle.cpp") \
		and value.get("dll_sha256") == FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll") \
		and value.get("test_sha256") == FileAccess.get_sha256("res://scripts/tests/site_army_hot_projection_native_test.gd") \
		and value.get("batch_sha256") == FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_batch_view.gd")


func _presenter_smoke_valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("status") != "PASS" or int(value.get("comparisons", 0)) < 8 or int(value.get("mismatches", 1)) != 0 or not value.get("assertions") is Dictionary or not value.get("sources") is Dictionary:
		return false
	for passed: Variant in value.assertions.values():
		if passed != true: return false
	var sources: Dictionary = value.sources
	return sources.get("army") == FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd") \
		and sources.get("presenter") == FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_batch_view.gd") \
		and sources.get("native_source") == FileAccess.get_sha256("res://native/army_idle/army_idle.cpp") \
		and sources.get("native_dll") == FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll") \
		and sources.get("fixture") == FileAccess.get_sha256("res://scripts/tests/site_army_retained_batch_test.gd")


func _army_retained_valid(value: Variant) -> bool:
	if not value is Dictionary or not value.get("checks") is Dictionary:
		return false
	for name: String in ["formal_admission", "stable_no_rebuild", "stable_exact_full",
			"local_ko_bounded_exact", "moving_bounded_exact", "native_no_barrier",
			"two_step_single_frame_exact", "visual_pure_retained_exact",
			"attack_visual_two_step_retained_exact", "nonidle_visual_zero_static",
			"nonidle_attack_two_step_zero_static", "ended_visual_pose_timer_exact",
			"local_facing_bounded_exact", "authored_duration_distinct_page_exact",
			"unchanged_live_sprite_zero_ground_exact"]:
		if value.checks.get(name) != true: return false
	for label: String in ["stable", "catchup"]:
		var stats: Variant = value.get(label)
		if not stats is Dictionary or int(stats.get("animation_samples", 0)) <= 0: return false
		for field: String in ["static_observations", "ground_projections", "row_rebuilds",
				"run_rebuilds", "changed_outputs", "packed_instances", "packed_bytes",
				"multimesh_setters", "multimesh_bytes", "gpu_dispatches"]:
			if int(stats.get(field, -1)) != 0: return false
	for label: String in ["local", "moving"]:
		var stats: Variant = value.get(label)
		if not stats is Dictionary or int(stats.get("static_observations", -1)) not in [0, 1] \
				or int(stats.get("ground_projections", -1)) not in [0, 1] \
				or int(stats.get("changed_outputs", 0)) != 1:
			return false
	for label: String in ["visual_render", "attack_render", "ended_visual", "distinct_clock"]:
		var nonidle: Variant = value.get(label)
		if not nonidle is Dictionary or int(nonidle.get("animation_samples", 0)) <= 0 \
				or int(nonidle.get("changed_outputs", -1)) != 1:
			return false
		for field: String in ["static_observations", "ground_projections", "row_rebuilds", "run_rebuilds"]:
			if int(nonidle.get(field, -1)) != 0: return false
	var facing: Variant = value.get("facing")
	if not facing is Dictionary or int(facing.get("static_observations", -1)) != 1 \
			or int(facing.get("ground_projections", -1)) != 1 \
			or int(facing.get("changed_outputs", -1)) != 1:
		return false
	var live_sprite: Variant = value.get("live_sprite")
	if not live_sprite is Dictionary or int(live_sprite.get("static_observations", -1)) != 0 \
			or int(live_sprite.get("ground_projections", -1)) != 0:
		return false
	var native: Variant = value.get("native")
	if not native is Dictionary or native.get("active") != true or int(native.get("native_calls", -1)) != 3 \
			or int(native.get("native_rows", -1)) != 192 or int(native.get("fallback_rows", -1)) != 0:
		return false
	var attack_two_step: Variant = value.get("attack_two_step")
	if not attack_two_step is Dictionary or attack_two_step.get("active") != true \
			or int(attack_two_step.get("native_calls", -1)) != 2 \
			or int(attack_two_step.get("native_rows", -1)) != 128 \
			or int(attack_two_step.get("fallback_rows", -1)) != 0 \
			or not _owner_reasons_complete(attack_two_step) \
			or not attack_two_step.barriers.is_empty():
		return false
	return value.get("army_sha256") == FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd") \
		and value.get("batch_sha256") == FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_batch_view.gd") \
		and value.get("dll_sha256") == FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll") \
		and value.get("test_sha256") == FileAccess.get_sha256("res://scripts/tests/site_army_hot_retained_integration_test.gd")


func _pixel_occlusion_valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("schema") != 1 or value.get("status") != "PASS" \
			or value.get("generated_by") != "res://scripts/tests/verify_site_army_hot_pixels.ps1" \
			or value.get("source_unchanged") != true or value.get("stdout_marker") != true \
			or int(value.get("asset_file_count", 0)) < 20 \
			or not value.get("source_sha256") is Dictionary:
		return false
	var required_paths := ["res://scripts/tests/verify_site_army_hot_pixels.ps1",
		"res://scripts/tests/site_army_batch_pixels_test.gd",
		"res://scripts/tests/fixtures/terrain_army_batch_view_phase3.gd.txt",
		"res://scripts/terrain_lab/terrain_army.gd",
		"res://scripts/terrain_lab/terrain_army_batch_view.gd",
		"res://native/army_idle/army_idle.cpp",
		"res://native/army_idle/bin/army_idle.windows.x86_64.dll"]
	for path: String in required_paths:
		if value.source_sha256.get(path) != FileAccess.get_sha256(path): return false
	for path: String in value.source_sha256:
		if not path.begins_with("res://") or path.contains("..") or value.source_sha256[path] != FileAccess.get_sha256(path):
			return false
	var run_dir: Variant = value.get("run_dir")
	if not run_dir is String or not run_dir.begins_with(ROOT + "pixel_occlusion_runs/") or run_dir.contains(".."):
		return false
	var verifier_path := str(value.get("verifier_result", ""))
	var pixel_path := str(value.get("pixel_result", ""))
	if verifier_path != run_dir + "/verifier_result.json" or pixel_path != run_dir + "/pixel_result.json":
		return false
	if value.get("verifier_result_sha256") != FileAccess.get_sha256(verifier_path) \
			or value.get("pixel_result_sha256") != FileAccess.get_sha256(pixel_path):
		return false
	var verifier: Variant = _json(verifier_path)
	var pixels: Variant = _json(pixel_path)
	if not verifier is Dictionary or verifier.get("status") != "PASS" or verifier.get("mode") != "visual" \
			or verifier.get("exit_code") != 0 or verifier.get("timed_out") != false \
			or not verifier.get("arguments") is Array \
			or not "res://scripts/tests/site_army_batch_pixels_test.gd" in verifier.arguments:
		return false
	if not pixels is Dictionary or int(pixels.get("checked", 0)) < 100 \
			or not pixels.get("differences") is Array or not pixels.differences.is_empty() \
			or int(pixels.get("sample_parity_checks", 0)) <= 0 \
			or pixels.get("native_groups_exercised") != true:
		return false
	var stdout_path: String = str(run_dir) + "/stdout.log"
	var verifier_script: String = str(value.get("verifier_script_path", "")).replace("\\", "/")
	var user_home := OS.get_environment("USERPROFILE").replace("\\", "/")
	if user_home.is_empty() or verifier_script != user_home + "/.codex/skills/godot-runtime-verify/scripts/verify_godot.ps1":
		return false
	return FileAccess.file_exists(stdout_path) \
		and FileAccess.get_file_as_string(stdout_path).contains("ARMY_BATCH_PIXELS_PASS") \
		and value.get("verifier_script_sha256") == FileAccess.get_sha256(verifier_script)


func _render_5k_valid(value: Variant, source_capture: Dictionary) -> bool:
	if not value is Dictionary or value.get("status") != "PASS" or value.get("generated_by") != "res://scripts/tests/site_army_scale_realtime_test.gd" \
			or value.get("scene") != "res://scenes/terrain_lab/TerrainLab.tscn" or value.get("preset") != "PLAINS" \
			or value.get("seed") != 581 or value.get("per_team") != 2500 or value.get("teams") != 2 \
			or value.get("renderer") != "forward_plus" or value.get("driver") != "d3d12" \
			or value.get("window_pixels") != str(Vector2i(1600, 900)) or value.get("logical_viewport") != str(Vector2(2560, 1440)) \
			or value.get("source_sha256") != source_capture.hashes or not bool(value.get("source_unchanged", false)) \
			or not bool(value.get("diagnostic_probe_only", false)) or value.get("ordinary_expected") != 4998 \
			or float(value.get("late_clock_advance", 0.0)) < 40.0 or int(value.get("late_exchange_count", 0)) <= 0:
		return false
	if not value.get("engine") is Dictionary or not value.get("source_errors") is Array or not value.source_errors.is_empty(): return false
	for field: String in ["major", "minor", "patch", "status", "build"]:
		if value.engine.get(field) != Engine.get_version_info().get(field): return false
	if not value.get("initial_visibility") is Dictionary or not value.get("final_visibility") is Dictionary:
		return false
	var product_defaults: Variant = value.get("product_hot_preconfigured")
	if not product_defaults is Array or product_defaults.size() != 2: return false
	for side in range(2):
		var original: Variant = product_defaults[side]
		if not original is Dictionary or original.get("side") != side or original.get("enabled") != true \
				or original.get("scene_file_path") != "res://scenes/terrain_lab/TerrainLab.tscn":
			return false
	var late_hot_stats: Variant = value.get("late_hot_stats")
	if not late_hot_stats is Array or late_hot_stats.size() != 2: return false
	for side in range(2):
		var entry: Variant = late_hot_stats[side]
		if not entry is Dictionary or entry.get("side") != side or not entry.get("stats") is Dictionary:
			return false
		var hot: Dictionary = entry.stats
		if hot.get("active") != true or hot.get("coverage_complete") != true or hot.get("diagnostics_enabled") != true \
				or int(hot.get("hot_dictionary_unscoped_reads", -1)) != 0 \
				or int(hot.get("hot_dictionary_unscoped_writes", -1)) != 0 \
				or int(hot.get("hot_dictionary_reads", -1)) < 0 \
				or int(hot.get("hot_dictionary_writes", -1)) < 0 \
				or int(hot.get("native_calls", 0)) <= 0 or int(hot.get("native_rows", 0)) <= 0 \
				or int(hot.get("inclusive_usec", 0)) <= 0 or not _owner_reasons_complete(hot):
			return false
		var barrier_count := 0
		for count: Variant in hot.barriers.values():
			if int(count) < 0: return false
			barrier_count += int(count)
		if int(hot.get("fallback_rows", -1)) < 0 or int(hot.fallback_rows) > barrier_count:
			return false
	if not value.get("viewport_size") is Array or value.viewport_size.size() != 2 \
			or value.get("final_viewport_size") != value.viewport_size \
			or int(value.viewport_size[0]) < 1000 or int(value.viewport_size[1]) < 563:
		return false
	if int(value.initial_visibility.get("visible_textured_sprites", 0)) != 5000 \
			or int(value.final_visibility.get("visible_textured_sprites", 0)) != 5000:
		return false
	for phase: String in ["stationary", "late"]:
		var frames: Variant = value.get(phase + "_frames")
		var assessment: Variant = value.get(phase + "_assessment")
		if not frames is Array or frames.size() != (4 if phase == "stationary" else 12) or not assessment is Dictionary or not bool(assessment.get("passed", false)):
			return false
		var zero_static := [0, 0]
		var zero_upload := [0, 0]
		var unchanged_output := [0, 0]
		var upload_without_change := [0, 0]
		var sampled := [0, 0]
		var stable_cells := ["", ""]
		var previous_frame := -1
		for frame: Variant in frames:
			if not frame is Dictionary or not frame.get("sides") is Array or frame.sides.size() != 2: return false
			if int(frame.get("drawn_frame", -1)) <= previous_frame: return false
			previous_frame = int(frame.drawn_frame)
			for side in range(2):
				var observed: Variant = frame.sides[side]
				if not observed is Dictionary or not observed.get("stats") is Dictionary or observed.get("side") != side \
						or not bool(observed.get("hot_active", false)) or observed.get("rendered_count") != 2499 \
						or int(observed.get("moving_count", -1)) < 0 \
						or str(observed.get("cells_sha256", "")).length() != 64:
					return false
				var stats: Dictionary = observed.stats
				for field: String in ["static_observations", "ground_projections", "animation_samples", "changed_outputs",
						"row_rebuilds", "run_rebuilds", "packed_instances", "packed_bytes", "multimesh_setters", "multimesh_bytes", "gpu_dispatches"]:
					if int(stats.get(field, -1)) < 0: return false
				if int(stats.static_observations) >= 2499 or int(stats.ground_projections) >= 2499 \
						or int(stats.changed_outputs) > 2499:
					return false
				if int(stats.animation_samples) > 0: sampled[side] += 1
				if phase == "stationary":
					if int(observed.moving_count) != 0: return false
					if stable_cells[side].is_empty(): stable_cells[side] = str(observed.cells_sha256)
					elif stable_cells[side] != str(observed.cells_sha256): return false
				if int(stats.static_observations) == 0 and int(stats.ground_projections) == 0 \
						and int(stats.row_rebuilds) == 0 and int(stats.run_rebuilds) == 0 and int(stats.animation_samples) > 0:
					zero_static[side] += 1
				if int(stats.changed_outputs) == 0:
					unchanged_output[side] += 1
					if int(stats.packed_instances) == 0 and int(stats.packed_bytes) == 0 \
							and int(stats.multimesh_setters) == 0 and int(stats.multimesh_bytes) == 0 \
							and int(stats.gpu_dispatches) == 0:
						zero_upload[side] += 1
					else:
						upload_without_change[side] += 1
		if assessment.get("zero_static_frames") != zero_static \
				or assessment.get("zero_upload_frames") != zero_upload \
				or assessment.get("unchanged_output_frames") != unchanged_output \
				or assessment.get("upload_without_change_frames") != upload_without_change \
				or mini(upload_without_change[0], upload_without_change[1]) != 0 \
				or maxi(upload_without_change[0], upload_without_change[1]) != 0:
			return false
		if mini(sampled[0], sampled[1]) < 2 \
				or float(frames.back().clock) <= float(frames[0].clock):
			return false
		if phase == "stationary" and mini(zero_static[0], zero_static[1]) < 2 \
				or phase == "late" and int(frames.back().exchange_count) <= int(frames[0].exchange_count):
			return false
	return true


func _oracle_valid(reference: Variant, candidate: Variant, source_capture: Dictionary) -> bool:
	if not reference is Dictionary or not candidate is Dictionary:
		return false
	if reference.get("status") != "PASS" or candidate.get("status") != "PASS" or reference.get("role") != "A" or candidate.get("role") != "B" or reference.get("snapshots_checked") != Stream.SNAPSHOTS or candidate.get("snapshots_checked") != Stream.SNAPSHOTS:
		return false
	if reference.get("materialized_ticks") != Stream.SNAPSHOTS or reference.get("process_steps") != Stream.SNAPSHOTS - 1 \
			or candidate.get("first_unfinished_tick") != Stream.SNAPSHOTS:
		return false
	if reference.get("snapshot_encoding") != "original_dictionary_order" or candidate.get("snapshot_encoding") != "original_dictionary_order" \
			or reference.get("A_unsupported_validation_deferred_to_B") != true \
			or candidate.get("native_exact_checks_both_values") != true \
			or candidate.get("first_mismatch_tick") != null \
			or candidate.get("native_exact_result") != null:
		return false
	if not reference.get("source_sha256") is Dictionary or not candidate.get("source_sha256") is Dictionary or not candidate.get("hot_stats") is Array or candidate.hot_stats.size() != 4:
		return false
	if candidate.get("source_manifest") != source_capture.hashes or not reference.get("source_manifest") is Dictionary:
		return false
	var original_manifest: Dictionary = reference.source_manifest
	if original_manifest.size() != source_capture.hashes.size(): return false
	var allowed_differences := {}
	for label: String in Stream.PRODUCT_PATHS:
		allowed_differences[Stream.PRODUCT_PATHS[label]] = true
	for path: String in source_capture.hashes:
		if not allowed_differences.has(path) and original_manifest.get(path, "") != source_capture.hashes[path]:
			return false
	for label: String in Stream.PRODUCT_PATHS:
		var path: String = Stream.PRODUCT_PATHS[label]
		if candidate.source_sha256.get(label) != FileAccess.get_sha256(path) or candidate.source_manifest.get(path) != candidate.source_sha256.get(label): return false
	for label: String in Stream.FROZEN_FILES:
		var path: String = Stream.PRODUCT_PATHS[label]
		if reference.get("source_sha256", {}).get(label) != FileAccess.get_sha256(ROOT + "frozen_A/" + str(Stream.FROZEN_FILES[label])) or original_manifest.get(path) != reference.source_sha256.get(label): return false
	if reference.get("binary_sha256") != FileAccess.get_sha256(Stream.REFERENCE) or candidate.get("reference_binary_sha256") != reference.binary_sha256:
		return false
	if not candidate.get("segment_sha256") is Dictionary or candidate.segment_sha256.size() != Stream.SEGMENT_BOUNDS.size() \
			or not candidate.get("segments") is Array or candidate.segments.size() != Stream.SEGMENT_BOUNDS.size():
		return false
	var covered := 0
	for index in Stream.SEGMENT_BOUNDS.size():
		var bounds: Array = Stream.SEGMENT_BOUNDS[index]
		var path: String = Stream.ROOT + "candidate_B_segment_%d.json" % index
		var segment: Variant = _json(path)
		if not segment is Dictionary or segment.get("status") != "PASS" \
				or segment.get("role") != "B%d" % index \
				or segment.get("segment_first") != bounds[0] or segment.get("segment_last") != bounds[1] \
				or segment.get("source_manifest") != source_capture.hashes \
				or segment.get("source_sha256") != candidate.source_sha256 \
				or segment.get("reference_binary_sha256") != reference.binary_sha256 \
				or segment.get("snapshots_checked") != int(bounds[1]) - int(bounds[0]) + 1 \
				or segment.get("materialized_ticks") != Stream.SNAPSHOTS \
				or segment.get("hot_active_checked_ticks") != Stream.SNAPSHOTS \
				or segment.get("reference_frames_traversed") != Stream.SNAPSHOTS \
				or segment.get("process_steps") != Stream.SNAPSHOTS - 1 \
				or segment.get("checkpoint_checked") != Stream.CHECKPOINT_TICKS.size() \
				or segment.get("checkpoint_ticks") != Stream.CHECKPOINT_TICKS \
				or segment.has("first_mismatch_tick") or segment.has("first_inactive_tick") \
				or candidate.segment_sha256.get(path.get_file()) != FileAccess.get_sha256(path):
			return false
		covered += int(segment.snapshots_checked)
	if covered != Stream.SNAPSHOTS: return false
	return candidate.source_sha256.get("fixture") == FileAccess.get_sha256("res://scripts/tests/site_army_oracle_stream_test.gd") \
		and candidate.source_sha256.get("oracle") == FileAccess.get_sha256("res://scripts/tests/fixtures/site_army_logical_state_oracle.gd") \
		and reference.get("source_sha256", {}).get("fixture") == candidate.source_sha256.fixture \
		and reference.get("source_sha256", {}).get("oracle") == candidate.source_sha256.oracle


func _hot_dictionary_zero(samples: Array) -> bool:
	for sample: Variant in samples:
		if not sample is Dictionary or not sample.get("teams") is Array or sample.teams.size() != 2: return false
		for team: Variant in sample.teams:
			if not team is Dictionary or not bool(team.get("active", false)) or not bool(team.get("coverage_complete", false)) \
					or int(team.get("hot_dictionary_unscoped_reads", -1)) != 0 \
					or int(team.get("hot_dictionary_unscoped_writes", -1)) != 0 \
					or int(team.get("hot_dictionary_reads", -1)) < 0 \
					or int(team.get("hot_dictionary_writes", -1)) < 0:
				return false
	return true


func _no_roster_sync(samples: Array) -> bool:
	var previous_tick := 0
	var previous_counts := [0, 0]
	for sample: Variant in samples:
		if not sample is Dictionary or not sample.get("teams") is Array or sample.teams.size() != 2: return false
		var tick := int(sample.get("tick", -1))
		if tick < previous_tick: return false
		for side in range(2):
			var count := int(sample.teams[side].get("materialized_rows", -1))
			if tick > 0 and count - previous_counts[side] != (tick - previous_tick) * 2500:
				return false
			previous_counts[side] = count
		previous_tick = tick
	return previous_tick == 1800


func _late_path_measured(samples: Array, reference: Dictionary, candidate: Dictionary) -> bool:
	if int(reference.get("process_usec", 0)) <= 0 or int(candidate.get("process_usec", 0)) <= 0 or int(candidate.process_usec) >= int(reference.process_usec): return false
	for tick: int in [1200, 1800]:
		var sample_at_tick: Dictionary = {}
		for sample: Variant in samples:
			if sample is Dictionary and sample.get("tick") == tick: sample_at_tick = sample
		if sample_at_tick.is_empty(): return false
		for team: Variant in sample_at_tick.teams:
			if not team is Dictionary or not bool(team.get("active", false)) or int(team.get("native_calls", 0)) <= 0 or int(team.get("native_rows", 0)) <= 0 or int(team.get("inclusive_usec", 0)) <= 0 or not _owner_reasons_complete(team):
				return false
			var barrier_count := 0
			for count: Variant in team.barriers.values():
				if int(count) < 0: return false
				barrier_count += int(count)
			# Borrowing an owner row is justified only by a recorded ordered barrier.
			if int(team.get("fallback_rows", -1)) < 0 or int(team.fallback_rows) > barrier_count \
					or barrier_count > int(team.native_calls):
				return false
	return true


func _owner_reasons_complete(stats: Dictionary) -> bool:
	if not stats.get("barriers") is Dictionary or not stats.get("owner_reasons") is Dictionary:
		return false
	var allowed := ["input_invalid", "state_invalid", "movement_invalid", "rescue",
		"visual_clear", "visual_expiry", "visual_invalid", "numeric_invalid", "attack_active",
		"pose_owner", "pose_expiry", "think_nonhold", "think_hold"]
	var total := 0
	for reason: String in stats.owner_reasons:
		if reason not in allowed or int(stats.owner_reasons[reason]) < 0: return false
		total += int(stats.owner_reasons[reason])
	return total == int(stats.barriers.get("3", 0))


func _hot_scope() -> Dictionary:
	# Real Army and vehicle owners; no direct writes to a stripped hot field.
	var result := {"status": "FAIL", "failure": "setup", "checks": {}, "observed": {},
		"generator_sha256": FileAccess.get_sha256(Gate.GENERATOR),
		"army_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"),
		"dll_sha256": FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll")}
	var lab := (load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene).instantiate() as TerrainLab
	if lab == null: return result
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	if lab.scene_file_path != "res://scenes/terrain_lab/TerrainLab.tscn": return _scope_finish(result, "formal_scene", lab)
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	SiteEnvironment.initialize(data, "hot-scope-581")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	lab.bind_terrain(data)
	lab.site_controller.release_worker()
	data.site.paused = false
	paused = false
	var first: TerrainArmy = lab.army
	var split: TerrainArmy = lab.third_army
	split.faction_id = first.faction_id
	result.checks["product_entry_hot_default"] = first.native_hot_enabled and split.native_hot_enabled
	if not result.checks.product_entry_hot_default: return _scope_finish(result, "product_entry_hot_default", lab)
	first.roster_size = 4
	var cells: Array[Vector2i] = [Vector2i(20, 20), Vector2i(20, 21), Vector2i(20, 22), Vector2i(20, 23)]
	if not first.deploy_at(data, lab.character, lab.npc, cells) or not first.enable_combat(false, 0):
		return _scope_finish(result, "deploy_enable", lab)
	result.checks["active_and_stripped_after_enable"] = first.combat_hot_active() and first.combat_units.size() == 4 and not first.combat_units[1].has("hp")
	if not result.checks.active_and_stripped_after_enable: return _scope_finish(result, "active_and_stripped_after_enable", lab)
	var person_id := first.combat_identity(1)
	var person: Dictionary = first.combat_units[1]
	var cargo := {"grain": 3}
	person.cargo = cargo
	first.apply_unit_contact(1, {"result": {"hp": 12.5, "stun": 0.0, "guard_break": false}, "shield": false})
	result.checks["owner_local_hit"] = first.combat_hot_active() and first.combat_hot_get(1, &"hp") == 87.5 \
		and not person.has("hp") and int(person.get("hit_revision", 0)) == 1
	if not result.checks.owner_local_hit: return _scope_finish(result, "owner_local_hit", lab)
	var own_members := {person_id: person}
	var changed_ids := {person_id: true}
	var own_hot_read: Callable = lab.site_controller._supply_hot_reader(first, own_members, changed_ids)
	var captured_hot_read: Callable = lab.site_controller._supply_hot_reader(first, own_members, {})
	var own_read_before: bool = own_hot_read.is_valid() and own_hot_read.call(person_id, &"hp") == 87.5 \
		and own_hot_read.call(person_id, &"ko") == first.combat_hot_get(1, &"ko")
	var own_captive_before: Variant = first.combat_hot_get(1, &"captive")
	first.combat_hot_set(1, &"captive", true)
	var own_captive_read: bool = own_hot_read.is_valid() and own_hot_read.call(person_id, &"captive") == true
	first.combat_hot_set(1, &"captive", own_captive_before)
	first.combat_hot_set(1, &"hp", 86.0)
	var own_changed_read: bool = own_hot_read.is_valid() and own_hot_read.call(person_id, &"hp") == 86.0
	var captured_prior_hp: bool = captured_hot_read.is_valid() and captured_hot_read.call(person_id, &"hp") == 87.5
	first.combat_hot_set(1, &"hp", 87.5)
	result.checks["supply_owner_changed_ids"] = own_read_before and own_captive_read and own_changed_read and captured_prior_hp \
		and own_hot_read.call(person_id, &"hp") == 87.5
	if not result.checks.supply_owner_changed_ids: return _scope_finish(result, "supply_owner_changed_ids", lab)
	# The hit opens the normal ten-second combat lock. The roster transition is
	# intentionally tested after that lock expires, while its HP remains changed.
	data.site.combat_left = 0.0
	result.observed["pre_split"] = {"ready": first.roster_change_ready(),
		"combat_left": data.site.get("combat_left", null), "combat_order": first.combat_order,
		"command": first.command, "moving_count": first.moving_count(),
		"paused": paused, "player_present": first.player_member != null,
		"rescue_count": first._unit_rescues.size(), "external_rescue_count": first._external_rescuers.size(),
		"poses": [first.combat_hot_get(0, &"pose"), first.combat_hot_get(1, &"pose"),
			first.combat_hot_get(2, &"pose"), first.combat_hot_get(3, &"pose")]}
	var source_cell := first.cells[1]
	var selected: Array[int] = [person_id]
	var split_result: Dictionary = first.split_members_to(split, selected, first.current_commander)
	result.checks["split_original_person"] = split_result.ok and first.combat_hot_active() and split.combat_hot_active() \
		and first.index_for_identity(person_id) == -1 and split.index_for_identity(person_id) == 0 \
		and is_same(split.combat_units[0], person) and is_same(split.combat_units[0].cargo, cargo) \
		and split.combat_hot_get(0, &"hp") == 87.5 and split.cells[0] == source_cell
	if not result.checks.split_original_person: return _scope_finish(result, "split_original_person:" + str(split_result), lab)
	var original_captive: Variant = split.combat_hot_get(0, &"captive")
	var original_present: Variant = split.combat_hot_get(0, &"present")
	split.combat_hot_set(0, &"captive", true)
	split.combat_hot_set(0, &"present", true)
	var foreign_hot_read: Callable = lab.site_controller._supply_hot_reader(first, {person_id: split.combat_units[0]}, {})
	result.checks["supply_foreign_captive_present"] = foreign_hot_read.is_valid() \
		and foreign_hot_read.call(person_id, &"hp") == 87.5 \
		and foreign_hot_read.call(person_id, &"captive") == true \
		and foreign_hot_read.call(person_id, &"present") == true
	split.combat_hot_set(0, &"captive", original_captive)
	split.combat_hot_set(0, &"present", original_present)
	if not result.checks.supply_foreign_captive_present: return _scope_finish(result, "supply_foreign_captive_present", lab)
	var merge_result: Dictionary = split.merge_into(first, split.current_commander, first.current_commander)
	var rejoined := first.index_for_identity(person_id)
	result.checks["merge_rebind"] = merge_result.ok and first.combat_hot_active() and not split.has_army() \
		and rejoined >= 0 and is_same(first.combat_units[rejoined], person) \
		and first.combat_hot_get(rejoined, &"hp") == 87.5 and first.cells[rejoined] == source_cell
	if not result.checks.merge_rebind: return _scope_finish(result, "merge_rebind:" + str(merge_result), lab)
	var captured: Dictionary = first.capture_combat_state()
	var saved: Variant = JSON.parse_string(JSON.stringify(captured))
	if not saved is Dictionary or not TerrainArmy.valid_combat_state(saved, data):
		return _scope_finish(result, "save_schema", lab)
	var restored := TerrainArmy.new()
	restored.native_hot_enabled = true
	lab.add_child(restored)
	restored.set_process(false)
	restored.restore_combat_state(saved, data, null, null)
	var restored_index := restored.index_for_identity(person_id)
	result.observed["restore"] = {"active": restored.combat_hot_active(), "index": restored_index,
		"hp": restored.combat_hot_get(restored_index, &"hp", null) if restored_index >= 0 else null,
		"cell": str(restored.cells[restored_index]) if restored_index >= 0 else "",
		"cargo": restored.combat_units[restored_index].get("cargo", {}) if restored_index >= 0 else {},
		"raw_has_hp": restored.combat_units[restored_index].has("hp") if restored_index >= 0 else null,
		"saved_ids": TerrainArmy.snapshot_person_ids(saved),
		"restored_ids": TerrainArmy.snapshot_person_ids(restored.capture_combat_state())}
	result.checks["save_restore_hot"] = restored.combat_hot_active() and restored_index >= 0 \
		and restored.combat_hot_get(restored_index, &"hp") == 87.5 \
		and restored.cells[restored_index] == source_cell \
		and int(restored.combat_units[restored_index].get("cargo", {}).get("grain", -1)) == 3 \
		and not restored.combat_units[restored_index].has("hp") \
		and TerrainArmy.snapshot_person_ids(restored.capture_combat_state()) == TerrainArmy.snapshot_person_ids(saved)
	if not result.checks.save_restore_hot: return _scope_finish(result, "save_restore_hot", lab)
	var expected_command := [first.combat_identity(first.formal_commander),
		first.combat_identity(first.acting_commander), first.combat_identity(first.current_commander)]
	var restored_cargo: Dictionary = restored.combat_units[restored_index].cargo
	restored.prepare_combat(1.0 / 30.0, 1.0 / 30.0)
	var resumed_index := restored.index_for_identity(person_id)
	var resumed_command := [restored.combat_identity(restored.formal_commander),
		restored.combat_identity(restored.acting_commander), restored.combat_identity(restored.current_commander)]
	result.observed["restore_resume"] = {"expected_command": expected_command,
		"resumed_command": resumed_command, "resumed_index": resumed_index,
		"cargo_same_reference": resumed_index >= 0 and is_same(restored.combat_units[resumed_index].cargo, restored_cargo)}
	result.checks["restore_resumes_with_control_and_cargo"] = restored.combat_hot_active() \
		and resumed_index >= 0 and resumed_command == expected_command \
		and is_same(restored.combat_units[resumed_index].cargo, restored_cargo) \
		and int(restored_cargo.get("grain", -1)) == 3 \
		and TerrainArmy.valid_combat_state(restored.capture_combat_state(), data)
	if not result.checks.restore_resumes_with_control_and_cargo:
		return _scope_finish(result, "restore_resumes_with_control_and_cargo", lab)
	restored.free()
	first.role = "logistics"
	var transport: SiteVehicleTransport = lab.site_controller.vehicles
	var operator_id := first.combat_identity(0)
	var plan := [{"kind": "cart", "team_id": first.team_id,
		"cell": data.index(first.cells[0] + Vector2i.RIGHT), "facing": [1, 0], "operator_index": 0}]
	var vehicle_result: Dictionary = transport.deploy_plan(first, plan)
	if not vehicle_result.ok or transport.records().size() != 1:
		return _scope_finish(result, "vehicle_deploy:" + str(vehicle_result), lab)
	var vehicle: Dictionary = transport.records().values()[0]
	var holder: Dictionary = vehicle.holder
	var vehicle_cargo: Dictionary = vehicle.cargo
	result.checks["vehicle_native_operator"] = first.combat_hot_active() and first.combat_can_act(0) \
		and int(vehicle.operator_id) == operator_id and transport.is_operator(operator_id) \
		and transport._available(transport._operator(operator_id))
	if not result.checks.vehicle_native_operator: return _scope_finish(result, "vehicle_native_operator", lab)
	var before_transfer: Dictionary = first.capture_combat_state()
	var refused: Dictionary = first.transfer_members_to(split, selected, first.current_commander)
	result.checks["vehicle_blocks_roster_atomically"] = refused.get("code") == "VEHICLES_ATTACHED" \
		and first.capture_combat_state() == before_transfer and int(vehicle.operator_id) == operator_id
	if not result.checks.vehicle_blocks_roster_atomically: return _scope_finish(result, "vehicle_blocks_roster_atomically:" + str(refused), lab)
	var parked: Dictionary = transport.park_team(first)
	result.checks["vehicle_park_preserves_cargo"] = parked.ok and int(vehicle.operator_id) == 0 \
		and int(vehicle.team_id) == 0 and is_same(vehicle.holder, holder) and is_same(vehicle.cargo, vehicle_cargo)
	if not result.checks.vehicle_park_preserves_cargo: return _scope_finish(result, "vehicle_park_preserves_cargo:" + str(parked), lab)
	result.observed["final"] = {"person_id": person_id, "hp_after_hit": first.combat_hot_get(rejoined, &"hp"),
		"source_cell": str(source_cell), "captured_units": saved.units.size(),
		"vehicle_id": vehicle.id, "operator_id": operator_id}
	return _scope_finish(result, "", lab)


func _scope_finish(result: Dictionary, failure: String, lab: TerrainLab) -> Dictionary:
	result.failure = failure
	result.status = "PASS" if failure.is_empty() else "FAIL"
	if lab != null: lab.free()
	TerrainArmy.release_contact_source()
	if result.generator_sha256 != FileAccess.get_sha256(Gate.GENERATOR) \
			or result.army_sha256 != FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd") \
			or result.dll_sha256 != FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll"):
		result.status = "FAIL"
		result.failure = "source_changed_during_scope"
	return result


func _write_json(path: String, value: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(value, "\t"))
	file.close()


func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
