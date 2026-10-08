extends SceneTree
## Read-only diagnostic for an already preserved crowd baseline.
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Controller = preload("res://scripts/terrain_lab/site_controller.gd")
const SCENE = preload("res://scenes/terrain_lab/TerrainLab.tscn")
var probe_lab: TerrainLab
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--crowd-source")
	if at < 0 or at + 1 >= args.size() or not args[at + 1].begins_with("res://output/"):
		printerr("GATE FAIL: --crowd-source must name preserved project output")
		quit(2)
		return
	if args.has("--crowd-profile-scene"):
		create_timer(180.0).timeout.connect(func() -> void:
			printerr("GATE FAIL: load profile exceeded explicit 180 second deadline")
			quit(3))
		var staged_profile := _profile_scene(args, args[at + 1])
		_write_scene_profile(args, staged_profile)
		if is_instance_valid(probe_lab): probe_lab.queue_free()
		await process_frame
		print("GATE OK: full staged load profile" if staged_profile.ok else "GATE FAIL: full staged load profile " + str(staged_profile.get("failure", "")))
		quit(0 if staged_profile.ok else 2)
		return
	var started := Time.get_ticks_usec()
	var result: Dictionary = Store.load_site(args[at + 1])
	var initial_load_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var profile := {"source": args[at + 1], "source_sha256": FileAccess.get_sha256(args[at + 1]),
		"initial_store_load_ms": initial_load_ms,
		"scope": "Store-only timings; excludes live CrowdSite capture and TerrainLab bind/render work"}
	var details: Dictionary = result.duplicate()
	details.erase("data")
	print("CROWD_LOAD_PROBE ", JSON.stringify(details))
	started = Time.get_ticks_usec()
	var decoded: Dictionary = Store._read(args[at + 1])
	profile.read_decode_ms = float(Time.get_ticks_usec() - started) / 1000.0
	if decoded.ok and decoded.payload.state.has("crowd"):
		var state: Dictionary = decoded.payload.state
		var native: RefCounted = ClassDB.instantiate("ArmyCrowd")
		native.setup(1, int(decoded.payload.seed))
		var bytes := Marshalls.base64_to_raw(state.crowd.blob)
		print("CROWD_LOAD_PROBE_NATIVE ", native.load_state(bytes))
		var records := {}
		var actor_ids := {}
		for row: Dictionary in state.actors.values():
			records[int(row.person_id)] = row
			actor_ids[int(row.person_id)] = true
		for roster: Dictionary in state.armies:
			for row: Dictionary in roster.units: records[int(row.person_id)] = row
		var ids: PackedInt64Array = native.person_ids()
		for index in range(ids.size()):
			var row: Dictionary = records[ids[index]]
			var hot: PackedFloat64Array = native.get_soldier_state(index)
			var ko_key := "knockout_left" if actor_ids.has(ids[index]) else "ko"
			if float(row.get("hp", -1.0)) != hot[0] or float(row.get(ko_key, -1.0)) != hot[3] or bool(row.get("captive", false)) != bool(hot[6]):
				print("CROWD_LOAD_PROBE_FIRST_LIFE_DIFF ", JSON.stringify({"person_id": ids[index], "native_index": index,
					"hp": {"json": row.get("hp"), "native": hot[0], "difference": float(row.get("hp", -1.0)) - hot[0]},
					"ko": {"key": ko_key, "json": row.get(ko_key), "native": hot[3], "difference": float(row.get(ko_key, -1.0)) - hot[3]},
					"captive": {"json": row.get("captive"), "native": bool(hot[6])}, "cold_row": row, "native_state": Array(hot)}, "", true, true))
				break
	if result.ok:
		var data: TerrainData = result.data
		profile.validation_stages = []
		for stage: Dictionary in [
			{"name": "crowd", "run": func() -> Dictionary: return Store._validate_crowd(data, data.site)},
			{"name": "armies", "run": func() -> Dictionary: return Store._validate_armies(data, data.site, true)},
			{"name": "vehicles", "run": func() -> Dictionary: return Store._validate_vehicles(data, data.site, true)},
			{"name": "army_assets", "run": func() -> Dictionary: return Store._validate_army_assets(data, data.site, true)},
			{"name": "actors", "run": func() -> Dictionary: return Store._validate_actors(data, data.site)},
			{"name": "items", "run": func() -> Dictionary: return Store._validate_items(data, data.site)},
			{"name": "person_allocator", "run": func() -> Dictionary: return Store._validate_person_allocator(data.site)},
			{"name": "supply", "run": func() -> Dictionary: return Store._validate_supply(data.site)},
			{"name": "cape_roles", "run": func() -> Dictionary: return Store._validate_cape_roles(data.site)},
			{"name": "all_state", "run": func() -> Dictionary: return Store._validate_state(data, data.site)}]:
			started = Time.get_ticks_usec()
			var outcome: Dictionary = stage.run.call()
			profile.validation_stages.append({"name": stage.name, "ms": float(Time.get_ticks_usec() - started) / 1000.0, "ok": outcome.ok, "code": outcome.get("code", "")})
		if decoded.ok:
			started = Time.get_ticks_usec()
			var body := JSON.stringify(decoded.payload, "", true, true)
			profile.json_encode_ms = float(Time.get_ticks_usec() - started) / 1000.0
			var raw := body.to_utf8_buffer()
			started = Time.get_ticks_usec()
			var compressed := raw.compress(FileAccess.COMPRESSION_ZSTD)
			profile.zstd_ms = float(Time.get_ticks_usec() - started) / 1000.0
			profile.raw_payload_bytes = raw.size()
			profile.zstd_bytes = compressed.size()
			profile.zstd_base64_bytes = Marshalls.raw_to_base64(compressed).length()
		if args.has("--crowd-rewrite"):
			var controller: Node = load("res://scripts/terrain_lab/site_controller.gd").new()
			var configured: Dictionary = controller.configure_test_paths(args)
			if not configured.ok or controller.crowd_test_run_id.is_empty() or not controller._save_path_guard(controller.save_path).ok:
				printerr("GATE FAIL: rewrite requires an isolated --crowd-test root")
				controller.free()
				quit(2)
				return
			started = Time.get_ticks_usec()
			var saved: Dictionary = Store.save(data, controller.save_path)
			profile.rewrite_save_ms = float(Time.get_ticks_usec() - started) / 1000.0
			profile.rewrite_result = saved
			if saved.ok:
				var file := FileAccess.open(controller.save_path, FileAccess.READ)
				profile.rewrite_file_bytes = file.get_length()
				file.close()
				started = Time.get_ticks_usec()
				var loaded: Dictionary = Store.load_site(controller.save_path)
				profile.rewrite_load_ms = float(Time.get_ticks_usec() - started) / 1000.0
				profile.rewrite_load_ok = loaded.ok
				if not loaded.ok: result = loaded
			else: result = saved
			controller.free()
	profile.source_sha256_after = FileAccess.get_sha256(args[at + 1])
	if profile.source_sha256_after != profile.source_sha256:
		printerr("GATE FAIL: source baseline changed")
		quit(2)
		return
	print("CROWD_STORE_PROFILE ", JSON.stringify(profile))
	var report_at := args.find("--crowd-profile-output")
	if report_at >= 0 and report_at + 1 < args.size():
		var report: String = args[report_at + 1].simplify_path()
		if report.begins_with("res://output/"):
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report).get_base_dir())
			var file := FileAccess.open(report, FileAccess.WRITE)
			file.store_string(JSON.stringify(profile, "\t", true, true))
			file.close()
	print("GATE OK: Store loaded preserved baseline" if result.ok else "GATE FAIL: Store rejected preserved baseline")
	quit(0 if result.ok else 2)


func _profile_scene(args: PackedStringArray, source: String) -> Dictionary:
	var profile := {"ok": false, "mode": "fresh-staged-scene", "source": source,
		"source_sha256": FileAccess.get_sha256(source), "stages": [],
		"scope": "Fresh candidate means no earlier Store load in this process; this is not an OS cold-cache benchmark because SHA and copy already read the source. One fresh Lab, one private Store candidate, original Controller.load_from checks in their current order. Store.load_site, Lab.prepare_crowd_load and Lab.bind_terrain are each timed exactly once. This diagnostic transcribes the current synchronous Controller orchestration; it does not invoke Controller.load_from itself. Scene startup, isolated fixture copy, report writing and final proof reads are outside load_total_ms. The input equals controller.save_path, so the normal alternate-path archive branch is inapplicable. UI show_result is not part of Controller.load_from either. No validation or bind initialization is skipped.",
		"script_sha256": FileAccess.get_sha256("res://scripts/tests/crowd_c3_load_probe.gd"),
		"controller_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/site_controller.gd"),
		"store_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/site_store.gd"),
		"lab_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_lab.gd"),
		"crowd_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/crowd_site.gd")}
	var safe_source := source.replace("\\", "/").simplify_path()
	if not safe_source.begins_with("res://output/") or not FileAccess.file_exists(safe_source):
		return _scene_profile_result(profile, false, "source must be an existing preserved output fixture")
	var path_owner := Controller.new()
	var configured: Dictionary = path_owner.configure_test_paths(args)
	var isolated: bool = configured.ok and not path_owner.crowd_test_run_id.is_empty() and not path_owner._save_path_guard(Store.DEFAULT_PATH).ok and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path_owner.save_root))
	profile["save_root"] = path_owner.save_root
	profile["copy_path"] = path_owner.save_path
	path_owner.free()
	if not isolated:
		return _scene_profile_result(profile, false, "requires a new isolated --crowd-test namespace")
	var started := Time.get_ticks_usec()
	probe_lab = SCENE.instantiate()
	probe_lab.pause_when_unfocused = false
	root.add_child(probe_lab)
	current_scene = probe_lab
	probe_lab.set_process(false)
	for actor in probe_lab.combat_actors: actor.set_process(false)
	profile["scene_startup_ms_excluded"] = float(Time.get_ticks_usec() - started) / 1000.0
	var controller: Node = probe_lab.site_controller
	if controller.save_path != profile.copy_path or FileAccess.file_exists(controller.save_path):
		return _scene_profile_result(profile, false, "fresh scene has unexpected save path or existing current file")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(controller.save_root))
	started = Time.get_ticks_usec()
	var copied := DirAccess.copy_absolute(ProjectSettings.globalize_path(safe_source), ProjectSettings.globalize_path(controller.save_path))
	profile["fixture_copy_ms_excluded"] = float(Time.get_ticks_usec() - started) / 1000.0
	profile["copy_sha256"] = FileAccess.get_sha256(controller.save_path)
	if copied != OK or profile.copy_sha256 != profile.source_sha256:
		return _scene_profile_result(profile, false, "isolated current copy differs from the preserved source")
	# Keep this order identical to Controller.load_from. Each stage uses this one
	# Store result and one Crowd candidate. No earlier warm-up load occurs here.
	var total_started := Time.get_ticks_usec()
	started = Time.get_ticks_usec()
	var result: Dictionary = controller._save_path_guard(controller.save_path)
	if result.ok and probe_lab.terrain != null and float(probe_lab.terrain.site.combat_left) > 0.0:
		result = SiteRuntime.fail("BUSY", "fresh scene unexpectedly starts in combat")
	_profile_stage(profile, "controller_path_and_current_combat_guard", started, result)
	if not result.ok:
		controller._load_failure(result)
		return _scene_profile_result(profile, false, str(result))
	started = Time.get_ticks_usec()
	result = Store.load_site(controller.save_path, Callable(), clampi(OS.get_processor_count(), 1, 8))
	_profile_stage(profile, "Store.load_site", started, result)
	if not result.ok:
		controller._load_failure(result)
		return _scene_profile_result(profile, false, str(result))
	var candidate: TerrainData = result.data
	started = Time.get_ticks_usec()
	var compatible: Dictionary = probe_lab.exchange_snapshot_guard(candidate)
	if compatible.ok and not is_instance_valid(probe_lab.npc):
		compatible = Store.retire_default_worker(candidate)
	_profile_stage(profile, "controller_exchange_guard_and_optional_worker_retirement", started, compatible)
	profile["default_worker_present"] = is_instance_valid(probe_lab.npc)
	if not compatible.ok:
		controller._load_failure(compatible)
		return _scene_profile_result(profile, false, str(compatible))
	started = Time.get_ticks_usec()
	var native_candidate: Variant = result.get("crowd_native")
	var prepared: Dictionary = _prepare_profile_candidate(candidate, native_candidate)
	result.erase("crowd_native")
	_profile_stage(profile, "Lab.prepare_crowd_load_including_native_validation_and_kits", started, prepared)
	if not prepared.ok:
		controller._load_failure(prepared)
		return _scene_profile_result(profile, false, str(prepared))
	# Exactly the current path means Controller's archive branch does not run.
	# Keep the original cancellation and candidate-commit guards as well.
	started = Time.get_ticks_usec()
	controller._cancel_facing_move()
	controller._clear_formation_candidate()
	_profile_stage(profile, "controller_cancel_transient_orders", started, SiteRuntime.ok())
	started = Time.get_ticks_usec()
	probe_lab.bind_terrain(candidate, prepared)
	_profile_stage(profile, "Lab.bind_terrain_including_controller_bind_and_item_initialization", started, {"ok": probe_lab.terrain == candidate})
	if probe_lab.terrain != candidate:
		if is_instance_valid(prepared.get("crowd_site")): prepared.crowd_site.free()
		controller._load_failure(SiteRuntime.fail("INVALID_CROWD", "load candidate was not committed"))
		return _scene_profile_result(profile, false, "original bind candidate identity guard failed")
	controller._auto_save_blocked = false
	profile["load_total_ms"] = float(Time.get_ticks_usec() - total_started) / 1000.0
	var sum_ms := 0.0
	for stage: Dictionary in profile.stages: sum_ms += float(stage.ms)
	profile["stage_sum_ms"] = sum_ms
	profile["orchestration_and_probe_overhead_ms"] = float(profile.load_total_ms) - sum_ms
	profile["same_data_candidate_committed"] = probe_lab.terrain == candidate
	profile["same_crowd_candidate_committed"] = probe_lab.crowd_site == prepared.get("crowd_site")
	profile["same_native_candidate_committed"] = is_instance_valid(probe_lab.crowd_site) and is_same(probe_lab.crowd_site.crowd, native_candidate)
	profile["archive_branch_executed"] = false
	profile["autosave_blocked_after_success"] = controller._auto_save_blocked
	if not is_instance_valid(probe_lab.crowd_site) or not probe_lab.crowd_site.active:
		return _scene_profile_result(profile, false, "loaded crowd candidate is not active")
	profile["native_people"] = int(probe_lab.crowd_site.crowd.soldier_count())
	profile["native_hash"] = str(probe_lab.crowd_site.crowd.state_hash())
	profile["site_id"] = str(candidate.site.get("id", ""))
	return _scene_profile_result(profile, int(profile.native_people) >= 5000 and bool(profile.same_crowd_candidate_committed) and bool(profile.same_native_candidate_committed), "" if int(profile.native_people) >= 5000 else "profile requires at least 5000 native people")

func _prepare_profile_candidate(data: TerrainData, native_candidate: Variant = null) -> Dictionary:
	return probe_lab.prepare_crowd_load(data, native_candidate)

func _profile_stage(profile: Dictionary, name: String, started: int, outcome: Dictionary) -> void:
	profile.stages.append({"name": name, "ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"ok": bool(outcome.get("ok", false)), "code": str(outcome.get("code", ""))})

func _scene_profile_result(profile: Dictionary, ok: bool, failure: String) -> Dictionary:
	profile["source_sha256_after"] = FileAccess.get_sha256(str(profile.source))
	profile["source_unchanged"] = profile.source_sha256_after == profile.source_sha256
	if profile.has("copy_sha256"):
		profile["copy_sha256_after"] = FileAccess.get_sha256(str(profile.copy_path))
		profile["copy_unchanged"] = profile.copy_sha256_after == profile.copy_sha256
	profile.ok = ok and bool(profile.source_unchanged) and bool(profile.get("copy_unchanged", true))
	profile["failure"] = failure if not failure.is_empty() else ("source or isolated copy changed" if not profile.ok else "")
	return profile

func _write_scene_profile(args: PackedStringArray, profile: Dictionary) -> void:
	var at := args.find("--crowd-profile-output")
	var report := ""
	if at >= 0 and at + 1 < args.size():
		report = args[at + 1].replace("\\", "/").simplify_path()
		var absolute := ProjectSettings.globalize_path(report).simplify_path().replace("\\", "/").to_lower()
		var source_path := ProjectSettings.globalize_path(str(profile.source)).simplify_path().replace("\\", "/").to_lower()
		var copy_path := ProjectSettings.globalize_path(str(profile.get("copy_path", ""))).simplify_path().replace("\\", "/").to_lower()
		if not report.begins_with("res://output/") or absolute in [source_path, copy_path] or FileAccess.file_exists(report):
			profile.ok = false
			profile.failure = "report must name a new output file distinct from source and isolated current"
			report = ""
	if not report.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report).get_base_dir())
		var file := FileAccess.open(report, FileAccess.WRITE)
		if file == null:
			profile.ok = false
			profile.failure = "could not create new diagnostic report"
		else:
			file.store_string(JSON.stringify(profile, "\t", true, true))
			file.close()
			# The report writer is outside the timed load, but still part of the
			# source-preservation proof. Invalid report paths never open a file.
			_scene_profile_result(profile, bool(profile.ok), str(profile.get("failure", "")))
	print("CROWD_SCENE_LOAD_PROFILE ", JSON.stringify(profile, "", true, true))
