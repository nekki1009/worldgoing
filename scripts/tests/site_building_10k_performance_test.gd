extends SceneTree
## Instrumented TerrainLab.tscn + original CrowdSite/atlas, with 10,000 original people.
## One bounded ABBA per --building-count 1|25|100. No empty-person FPS extrapolation.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const ControllerSource = preload("res://scripts/terrain_lab/site_controller.gd")
const ViewSource = preload("res://scripts/terrain_lab/site_resource_view.gd")
const Probe = preload("res://scripts/tests/helpers/site_building_phase_probe.gd")
const ProfileController = preload("res://scripts/tests/helpers/site_building_profile_controller.gd")
const ProfileView = preload("res://scripts/tests/helpers/site_building_profile_view.gd")
const MAIN := "res://scenes/terrain_lab/TerrainLab.tscn"
const OUT := "res://output/site_building_close_20261004/performance/"
const BUILDING_PHASES := ["building.selection_ui", "building.rebuild", "building.art_submit", "building.prop_submit"]
const ALL_PHASES := BUILDING_PHASES + ["host.site_tick_inclusive", "view.refresh_inclusive"]
const SEED := 12345
var lab: TerrainLab
var probe: RefCounted
var installed: Dictionary = {}
var requested_count: int = 100
var seconds: float = 15.0
var warmup_seconds: float = 3.0
var deadline_us: int = 0
var folder: String = ""
var report: Dictionary = {"status": "UNRUN", "runs": []}
var finished: bool = false
var native_guard_path: String = ""
var native_guard: Dictionary = {}

func _initialize() -> void:
	deadline_us = Time.get_ticks_usec() + 600000000
	for option: String in ["--building-count", "--building-seconds", "--building-warmup"]:
		var at: int = OS.get_cmdline_user_args().find(option)
		if at < 0: continue
		assert(at + 1 < OS.get_cmdline_user_args().size())
		var value: String = OS.get_cmdline_user_args()[at + 1]
		if option == "--building-count": requested_count = int(value)
		elif option == "--building-seconds": seconds = float(value)
		else: warmup_seconds = float(value)
	assert(requested_count in [1, 25, 100] and seconds >= 10.0 and seconds <= 30.0 and warmup_seconds >= 2.0 and warmup_seconds <= 10.0)
	var guard_at: int = OS.get_cmdline_user_args().find("--building-native-guard")
	if guard_at >= 0 and guard_at + 1 < OS.get_cmdline_user_args().size(): native_guard_path = OS.get_cmdline_user_args()[guard_at + 1]
	folder = OUT + "%d_%d_%d" % [requested_count, int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	assert(DirAccess.make_dir_recursive_absolute(folder) == OK)
	node_added.connect(_install_probe)
	_launch.call_deferred()

func _launch() -> void:
	await _run()
	if not finished: _finish("FAILED", "Original assertion aborted a benchmark phase; inspect the retained canonical error")

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_usec() >= deadline_us: _finish("TIMEOUT", "600-second internal deadline")
	return false

func _sources() -> Dictionary:
	var hashes: Dictionary = {}
	for path: String in [MAIN, "res://project.godot", "res://scripts/terrain_lab/terrain_lab.gd", "res://scripts/terrain_lab/terrain_generator.gd",
		"res://scripts/terrain_lab/terrain_renderer.gd", "res://scripts/terrain_lab/site_controller.gd", "res://scripts/terrain_lab/site_resource_view.gd",
		"res://scripts/terrain_lab/site_runtime.gd", "res://scripts/terrain_lab/site_stockpiles.gd", "res://scripts/terrain_lab/crowd_site.gd",
		"res://scripts/terrain_lab/crowd_person_owner.gd", "res://native/crowd10k/bin/crowd10k.windows.x86_64.dll",
		"res://native/army_idle/vendor/gdextension_interface.h", "res://scripts/tests/site_building_10k_performance_test.gd",
		"res://scripts/tests/helpers/site_building_phase_probe.gd", "res://scripts/tests/helpers/site_building_profile_controller.gd",
		"res://scripts/tests/helpers/site_building_profile_view.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	for path: String in native_guard.get("source_sha256", {}): hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _check_native_build() -> Dictionary:
	if native_guard_path.is_empty() or not FileAccess.file_exists(native_guard_path): return Runtime.fail("NATIVE_BUILD_GUARD", "Provide --building-native-guard from the final successful canonical formal_native run after formal DLL publication")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(native_guard_path))
	if not parsed is Dictionary or int(parsed.get("version", 0)) != 1 or not parsed.get("source_sha256") is Dictionary or parsed.source_sha256.is_empty(): return Runtime.fail("NATIVE_BUILD_GUARD", "Invalid test-only canonical build guard")
	native_guard = parsed
	if FileAccess.get_sha256("res://native/crowd10k/bin/crowd10k.windows.x86_64.dll") != str(native_guard.get("dll_sha256", "")): return Runtime.fail("NATIVE_BUILD_GUARD", "Published formal DLL differs from the completed canonical build")
	var actual_sources: Dictionary = {}
	for folder: String in ["src", "godot", "tests", "tools"]:
		var path: String = "res://native/crowd10k/" + folder
		var directory: DirAccess = DirAccess.open(path)
		if directory == null: return Runtime.fail("NATIVE_BUILD_GUARD", "Native source directory missing: " + path)
		for file: String in directory.get_files():
			if file.get_extension().to_lower() not in ["h", "hpp", "c", "cpp"]: continue
			var source: String = path.path_join(file)
			actual_sources[source] = FileAccess.get_sha256(source)
	if actual_sources != native_guard.source_sha256: return Runtime.fail("NATIVE_BUILD_GUARD", "Formal Native source list/content differs from the completed canonical identity")
	if not ClassDB.class_exists("ArmyCrowd"): return Runtime.fail("NATIVE_BUILD_GUARD", "Original ArmyCrowd extension is unavailable")
	var native: RefCounted = ClassDB.instantiate("ArmyCrowd")
	if str(native.build_id()) != str(native_guard.get("build_id", "")): return Runtime.fail("NATIVE_BUILD_GUARD", "Actually loaded ArmyCrowd build_id differs from the canonical source/DLL")
	return Runtime.ok()

func _install_probe(node: Node) -> void:
	if lab == null or node.get_parent() != lab: return
	var source: Script = node.get_script()
	if source != ControllerSource and source != ViewSource: return
	var identity: int = node.get_instance_id()
	if source == ControllerSource:
		assert(node.get("lab") == null, "Only the fresh original controller before setup may receive telemetry")
		node.set_script(ProfileController)
		installed["controller"] = identity == node.get_instance_id()
	else:
		assert(node.get("data") == null, "Only the fresh original view before display may receive telemetry")
		node.set_script(ProfileView)
		installed["view"] = identity == node.get_instance_id()
	node.set("building_probe", probe)

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or not args.has("--crowd") or not args.has("--crowd-test") or not args.has("--crowd-atlas-root"):
		_finish("INVALID_SURFACE", "GPU, --crowd, named --crowd-test and isolated --crowd-atlas-root are required")
		return
	var guard: Dictionary = _check_native_build()
	if not guard.ok:
		_finish("NATIVE_BUILD_GUARD", str(guard.message))
		return
	report = {"status": "MEASURING", "requested_features": requested_count, "runs": [], "sources_before": _sources(),
		"native_build_guard": native_guard.duplicate(true), "native_build_guard_path": native_guard_path,
		"godot": Engine.get_version_info(), "renderer": RenderingServer.get_video_adapter_name(), "cpu": OS.get_processor_name(),
		"debug_build": OS.is_debug_build(), "seconds_per_run": seconds, "warmup_seconds": warmup_seconds,
		"scope": "Generated 128x128 Site from the formal generator, original navigation/collision and original TerrainLab/CrowdSite/atlas. Fixture-only 50 native formations with 9999 roster people plus the original player. Not fixed geography 100x100 admission, formal 100-row UI deployment, 10k save admission, battle performance or production throughput.",
		"phase_scope": "Instrumented main-thread building selection UI, building cache rebuild and art/prop draw submission, including unmeasured probe overhead; inclusive view refresh and original host Site tick are separate and excluded from the sum. Engine/render-thread/GPU time is separately measured. Static cached art need not submit fresh commands on every frame.",
		"target": "Instrumented building CPU phase p95 increment on actual building-work frames versus the same-instrumentation 10k baseline <= 2ms; this includes unmeasured probe overhead and is not an uninstrumented CPU/FPS acceptance. Zero-cost cached frames and full-scene frame times are reported separately and never assigned a total-FPS pass."}
	report["instrumentation"] = {
		"mode": "Same fresh Controller/View Nodes receive Profile subclasses before setup; each override calls super once",
		"scope": "Only same-instrumentation ABBA building-work-frame p95 increment; no uninstrumented full-scene CPU/FPS claim",
		"controller_exact_identity_guards": ["original_checkpoint", "native_sample", "non-Crowd team-info batch"],
		"transitive_gd_army_fallbacks": ["all-melee publication shortcut", "canonical geometry prefilter", "empty-rescue skip"],
		"timed_native_branch": "Original active Crowd path; GD Army prepare optimizations are outside this branch",
		"native_owner_and_store_identity": "Original CrowdSite, ArmyCrowd class/script-null and Store admission remain unchanged",
		"overhead": "Unmeasured and not subtracted: wrapper/super dispatch, timer and per-call frame/Dictionary operations; extra calls may grow with building count",
		"sustain_scope": "No supply enabled by this fixture; empty original entries skip the sustain inner loop. Actual counts are recorded per run; no active-feeding 10k claim"}
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	for count: int in [0, requested_count, requested_count, 0]:
		if finished: return
		var run: Dictionary = await _one_run(count, report.runs.size())
		if run.is_empty(): return
		report.runs.append(run)
		report["sources_after"] = _sources()
		if report.sources_after != report.sources_before:
			_finish("SOURCE_DRIFT", "Original sources changed during an ABBA measurement")
			return
	var baseline: float = (float(report.runs[0].active_building_cpu_ms.p95) + float(report.runs[3].active_building_cpu_ms.p95)) * 0.5
	var candidate: float = (float(report.runs[1].active_building_cpu_ms.p95) + float(report.runs[2].active_building_cpu_ms.p95)) * 0.5
	report["building_p95_increment_ms"] = candidate - baseline
	report["building_target_met"] = candidate - baseline <= 2.0
	var attribution: Array = []
	for phase: String in ALL_PHASES:
		var base: float = (float(report.runs[0].active_phases[phase].p95) + float(report.runs[3].active_phases[phase].p95)) * 0.5
		var changed: float = (float(report.runs[1].active_phases[phase].p95) + float(report.runs[2].active_phases[phase].p95)) * 0.5
		attribution.append({"phase": phase, "baseline_p95_ms": base, "candidate_p95_ms": changed, "increment_ms": changed - base})
	attribution.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.increment_ms) > float(b.increment_ms))
	report["profile_attribution"] = attribution
	_finish("MEASURED" if bool(report.building_target_met) else "TARGET_EXCEEDED", "" if bool(report.building_target_met) else "See actual per-phase p95 increments and raw slow-frame rows; full-scene frame budget remains separately reported")

func _instrumentation_snapshot() -> Dictionary:
	var native_supply_entries: int = 0
	for owner: RefCounted in lab.crowd_site.person_owners():
		if not lab.site_controller._supply_entry(owner).is_empty(): native_supply_entries += 1
	var active_gd_armies: int = 0
	for army: TerrainArmy in lab.combat_armies:
		if army.combat_enabled: active_gd_armies += 1
	return {"controller_script": lab.site_controller.get_script().resource_path,
		"view_script": lab.site_controller.view.get_script().resource_path,
		"crowd_script": lab.crowd_site.get_script().resource_path,
		"controller_instance_id": lab.site_controller.get_instance_id(), "view_instance_id": lab.site_controller.view.get_instance_id(),
		"controller_exact_original": lab.site_controller.get_script() == ControllerSource,
		"view_exact_original": lab.site_controller.view.get_script() == ViewSource,
		"native_class": lab.crowd_site.crowd.get_class(), "native_script_null": lab.crowd_site.crowd.get_script() == null,
		"native_sustain_entries": native_supply_entries, "active_gd_armies": active_gd_armies,
		"events_observers": lab.crowd_site.get_signal_connection_list("events_received").size()}

func _make_features(count: int) -> bool:
	var data: TerrainData = lab.terrain
	var kinds: Array[String] = ["house", "warehouse", "kiln", "weaver", "smelter"]
	for ordinal: int in range(count):
		var kind: String = kinds[ordinal % kinds.size()]
		var options: Dictionary = {"owner_faction": 0, "quarter": ordinal % 4, "variant": "small" if ordinal % 2 == 0 else "standard"}
		var accepted: bool = false
		for y: int in range(8, data.size.y - 8, 5):
			if accepted: break
			for x: int in range(8, data.size.x - 8, 5):
				var layout: Dictionary = Runtime.building_cells(data, kind, Vector2i(x, y), Vector2i.ONE, options)
				if not layout.ok: continue
				var cells: Array[int] = []
				cells.assign(layout.cells)
				var planned: Dictionary = Runtime.preview_build(data, kind, cells, lab.site_controller.reserves_cell, options)
				if not planned.ok: continue
				var built: Dictionary = Runtime.request_build(data, kind, cells, lab.site_controller.reserves_cell, options)
				assert(built.ok, str(built))
				var key: String = str(built.feature)
				var feature: Dictionary = data.site.features[key]
				# Untimed fixture preparation, through original construction completion.
				# The longplay test separately proves real workers and construction time.
				var task: Dictionary = {"target": "feature:" + key, "action": "construct", "cell": feature.entrance, "mode": "work", "status": "", "progress": 0.0, "work_slot": -1}
				Runtime._feature_work(data, key, float(feature.work), lab.site_controller.reserves_cell, Callable(), task, {}, 20, 0)
				assert(feature.stage == "complete" and Runtime.validate_feature_layout(data, feature).ok)
				accepted = true
				break
		if not accepted:
			_finish("NO_SPACE", "Original placement rejected feature %d/%d (%s), without replacing terrain or relaxing placement" % [ordinal + 1, count, kind])
			return false
	return true

func _ten_thousand() -> Dictionary:
	var data: TerrainData = lab.terrain
	var available: int = 0
	for index: int in range(data.size.x * data.size.y):
		var cell: Vector2i = data.cell_from_index(index)
		if data.is_walkable(cell) and not lab.character.occupies_cell(cell): available += 1
	if available < 9999:
		_finish("NO_SPACE", "Only %d original legal unoccupied cells remain for 9999 original roster people" % available)
		return {}
	var sides: Array[Dictionary] = []
	for index: int in range(50):
		var parsed: Dictionary = lab._trial_side_settings({"third_count": 100, "third_faction": 0, "third_attack": false, "third_ai_enabled": false, "third_female_percent": 0}, "third")
		assert(parsed.ok, str(parsed))
		var side: Dictionary = parsed.side
		# Fixture-only expansion at the original native deploy boundary. No
		# production UI/save cap or native owner/render path is replaced.
		side.count = 199 if index == 49 else 200
		side.slot_count = side.count
		sides.append(side)
	var formations: Array = lab._independent_trial_formations(sides)
	if formations.size() != sides.size():
		_finish("NO_SPACE", "Original connected formation allocator rejected 10k: " + str(lab._trial_formation_failure))
		return {}
	var claimed: Dictionary = {}
	for cells: Array in formations:
		for cell: Vector2i in cells:
			assert(not claimed.has(cell) and data.is_walkable(cell) and data.static_blocked[data.index(cell)] == 0 and not lab.character.occupies_cell(cell))
			claimed[cell] = true
	assert(claimed.size() == 9999)
	var deployed: Dictionary = lab.crowd_site.deploy(sides, formations)
	if not deployed.ok:
		_finish("DEPLOY_REJECTED", str(deployed))
		return {}
	var ids: PackedInt64Array = lab.crowd_site.crowd.person_ids()
	var identities: Dictionary = {}
	for identity: int in ids:
		assert(not identities.has(identity))
		identities[identity] = true
	assert(lab.crowd_site.active and ids.size() == 10000 and identities.size() == 10000 and lab.crowd_site._records.size() + lab.crowd_site._actors.size() == 10000)
	assert(str(lab.crowd_site.crowd.build_id()) == str(native_guard.build_id), "The actual deployed original Native owner must retain the proven canonical build")
	assert(lab.crowd_site.crowd.validate())
	var orders: int = 0
	for team: Dictionary in lab.crowd_site.command_teams():
		var state: Dictionary = lab.crowd_site.formation_state(int(team.formation))
		var origin: Vector2i = Vector2i(floori(float(state.cx)), floori(float(state.cy)))
		for offset: Vector2i in [Vector2i(4, 0), Vector2i(0, 4), Vector2i(-4, 0), Vector2i(0, -4)]:
			if not data.is_walkable(origin + offset): continue
			if lab.crowd_site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.MOVE, origin + offset, -1, "test").ok:
				orders += 1
				break
	assert(orders > 0, "The original 10k owner must receive a real legal MOVE order")
	return {"count": 10000, "unique_initial_roster_cells": claimed.size(), "available_cells_before_deploy": available, "native_formations": lab.crowd_site.crowd.formation_count(), "accepted_move_orders": orders}

func _wait_captivity_preparation() -> bool:
	var original: Node = lab.crowd_site
	# Establish the same original deferred jobs before inspecting their states.
	original._prewarm_captivity_atlases()
	while not finished:
		var preparing: bool = is_instance_valid(TerrainArmy.EquipmentAtlas._preparation)
		for key: String in original._captivity_atlas_jobs:
			var job: Dictionary = original._captivity_atlas_jobs[key]
			if not original._captivity_atlas_context(key, job) or job.state not in ["preparing", "ready"]:
				_finish("CAPTIVITY_PREPARATION_FAILED", "Original captivity queue failed or changed context: " + key)
				return false
			preparing = preparing or job.state == "preparing"
		if not preparing: break
		await process_frame
		await RenderingServer.frame_post_draw
	if finished: return false
	# An empty queue can mean a cache hit; prove exact publication/kit admission.
	var seen: Dictionary = {}
	for value: Variant in original._kit_appearances:
		if not value is Dictionary or value.is_empty(): continue
		var appearance: Dictionary = value.duplicate(true)
		for slot: String in ["weapon", "shield"]:
			appearance.parts[slot] = "none"
			if appearance.has("equipment_dyes"): appearance.equipment_dyes.erase(slot)
		if appearance.has("equipment_dyes") and appearance.equipment_dyes.is_empty(): appearance.erase("equipment_dyes")
		var key: String = JSON.stringify(appearance)
		if seen.has(key): continue
		seen[key] = true
		if original._ensure_kit(appearance) < 0:
			_finish("CAPTIVITY_PREPARATION_FAILED", "Original unarmed publication did not pass exact kit admission")
			return false
	return true

func _one_run(count: int, index: int) -> Dictionary:
	probe = Probe.new()
	installed.clear()
	var prepared_at: int = Time.get_ticks_usec()
	lab = (load(MAIN) as PackedScene).instantiate() as TerrainLab
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.character.set_process(false)
	assert(installed.get("controller", false) and installed.get("view", false))
	lab.site_controller._auto_save_blocked = true
	var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, SEED, {"size": Vector2i(128, 128)})
	assert(data.size == Vector2i(128, 128) and not data.parameters.has("fixed_base"))
	Env.initialize(data, "crowd_test_" + lab.site_controller.crowd_test_run_id + "_buildings")
	# Identical cleared natural-resource state in every A and B. Original base
	# heights, water, flags, ramps and collision are never replaced or flattened.
	for key: String in data.resource_base: Env.change(data, key, {"cleared": true, "remaining": 0})
	Env.rebuild_indexes(data)
	for item: String in Env.ITEM_NAMES: data.site.inventory[item] = 10000
	data.site.capacity = 1000000
	lab.bind_terrain(data)
	assert(lab.terrain == data and not lab.site_controller.crowd_test_run_id.is_empty())
	if not _make_features(count): return {}
	assert(data.site.features.size() == count)
	var rebuild_at: int = Time.get_ticks_usec()
	lab.site_controller.view.refresh()
	var initial_refresh_ms: float = float(Time.get_ticks_usec() - rebuild_at) / 1000.0
	var deployment: Dictionary = _ten_thousand()
	if deployment.is_empty(): return {}
	if not await _wait_captivity_preparation(): return {}
	var preparation_ms: float = float(Time.get_ticks_usec() - prepared_at) / 1000.0
	lab.site_controller.feature_key = str(data.site.features.keys()[0]) if count > 0 else ""
	lab.site_controller.update_ui()
	lab.fit_map()
	lab.camera.force_update_scroll()
	lab.set_process(true)
	var warmup_at: int = Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - warmup_at) / 1000000.0 < warmup_seconds:
		await process_frame
		await RenderingServer.frame_post_draw
		if finished: return {}
	assert(lab.crowd_site.crowd.soldier_count() == 10000 and lab.terrain.site.features.size() == count)
	assert(_issue_measurement_moves() > 0)
	var before_positions: PackedFloat32Array = _position_signature()
	var instrumentation_before: Dictionary = _instrumentation_snapshot() # Untimed read-only metadata.
	var samples: Array[Dictionary] = []
	probe.frames.clear()
	probe.enabled = true
	var started: int = Time.get_ticks_usec()
	var previous: int = started
	while float(Time.get_ticks_usec() - started) / 1000000.0 < seconds:
		await process_frame
		await RenderingServer.frame_post_draw
		if finished: return {}
		var now: int = Time.get_ticks_usec()
		var phases: Dictionary = probe.take(Engine.get_process_frames())
		var building: float = 0.0
		for phase: String in BUILDING_PHASES: building += float(phases.get(phase, 0.0))
		var sample: Dictionary = {"frame_ms": float(now - previous) / 1000.0, "building_cpu_ms": building,
			"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
			"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"memory_static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
			"video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED), "phases": phases,
			"site_minute": Runtime.now(lab.terrain), "native_people": lab.crowd_site.crowd.soldier_count(), "features": lab.terrain.site.features.size()}
		assert(int(sample.native_people) == 10000 and int(sample.features) == count)
		samples.append(sample)
		previous = now
	probe.enabled = false
	var instrumentation_after: Dictionary = _instrumentation_snapshot() # Collection is already stopped.
	assert(samples.size() >= 100, "Insufficient full-frame observations for p95/p99")
	var active_samples: Array[Dictionary] = []
	for sample: Dictionary in samples:
		if float(sample.building_cpu_ms) > 0.0: active_samples.append(sample)
	assert(active_samples.size() >= 25, "Insufficient actual building-work frames; cached zero-cost frames cannot establish the building target")
	var stats: PackedFloat64Array = lab.crowd_site.crowd.stats()
	assert(stats.size() == 40 and stats[14] == 0.0 and stats[15] == 0.0 and stats[16] == 0.0)
	assert(_position_signature() != before_positions, "Actual native positions never changed during the full-frame run")
	var visible_instances: int = 0
	var submitted_spans: PackedInt32Array = lab.crowd_site.crowd.row_spans()
	assert(submitted_spans.size() % 6 == 0)
	for offset: int in range(0, submitted_spans.size(), 6):
		if submitted_spans[offset + 1] < 0: continue
		var node: MultiMeshInstance2D = lab.crowd_site.nodes.get(submitted_spans[offset + 5])
		if is_instance_valid(node) and node.visible: visible_instances += submitted_spans[offset + 3]
	assert(visible_instances >= 9999, "The actual original atlas was not submitted for the 9999 roster people")
	var result: Dictionary = {"sequence": index, "features": count, "people": 10000, "deployment": deployment, "preparation_ms": preparation_ms,
		"instrumentation_before": instrumentation_before, "instrumentation_after": instrumentation_after,
		"initial_refresh_ms": initial_refresh_ms, "warmup_seconds": warmup_seconds, "atlas_submitted_roster_instances": visible_instances,
		"camera_position": [lab.camera.position.x, lab.camera.position.y], "camera_zoom": [lab.camera.zoom.x, lab.camera.zoom.y],
		"viewport_pixels": [root.get_texture().get_size().x, root.get_texture().get_size().y], "phases": {}, "active_phases": {}, "final_stats": Array(stats)}
	for key: String in ["frame_ms", "building_cpu_ms", "gpu_ms", "render_cpu_ms", "draw_calls", "memory_static_bytes", "video_memory_bytes"]:
		result[key] = _distribution(samples, key)
	result["active_building_cpu_ms"] = _distribution(active_samples, "building_cpu_ms")
	result["building_work_frame_fraction"] = float(active_samples.size()) / samples.size()
	for phase: String in ALL_PHASES: result.phases[phase] = _distribution(samples, phase, true)
	for phase: String in ALL_PHASES: result.active_phases[phase] = _distribution(active_samples, phase, true)
	var raw: FileAccess = FileAccess.open(folder + "/run_%d_features_%d.json" % [index, count], FileAccess.WRITE)
	assert(raw != null)
	raw.store_string(JSON.stringify({"summary": result, "frames": samples}, "\t", true, true))
	raw.close()
	var image: Image = root.get_texture().get_image()
	assert(not image.is_empty() and image.save_png(folder + "/run_%d_features_%d.png" % [index, count]) == OK)
	lab.queue_free()
	await process_frame
	await process_frame
	lab = null
	return result

func _position_signature() -> PackedFloat32Array:
	var positions: PackedFloat32Array = PackedFloat32Array()
	for index: int in range(int(lab.crowd_site.crowd.soldier_count())):
		var person: Dictionary = lab.crowd_site.soldier_state(index)
		positions.append(float(person.px))
		positions.append(float(person.py))
	return positions

func _issue_measurement_moves() -> int:
	var accepted: int = 0
	for team: Dictionary in lab.crowd_site.command_teams():
		var state: Dictionary = lab.crowd_site.formation_state(int(team.formation))
		var origin: Vector2i = Vector2i(floori(float(state.cx)), floori(float(state.cy)))
		for offset: Vector2i in [Vector2i(16, 0), Vector2i(0, 16), Vector2i(-16, 0), Vector2i(0, -16)]:
			if not lab.terrain.is_walkable(origin + offset): continue
			if lab.crowd_site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.MOVE, origin + offset, -1, "test").ok:
				accepted += 1
				break
	return accepted

func _distribution(samples: Array[Dictionary], key: String, phase: bool = false) -> Dictionary:
	var values: Array[float] = []
	var total: float = 0.0
	for sample: Dictionary in samples:
		var value: float = float(sample.phases.get(key, 0.0)) if phase else float(sample[key])
		values.append(value)
		total += value
	values.sort()
	return {"n": values.size(), "mean": total / values.size(), "p50": values[ceili(values.size() * 0.50) - 1],
		"p95": values[ceili(values.size() * 0.95) - 1], "p99": values[ceili(values.size() * 0.99) - 1], "max": values.back()}

func _finish(status: String, failure: String) -> void:
	if finished: return
	finished = true
	report.status = status
	report["failure"] = failure
	report["sources_after"] = _sources()
	var file: FileAccess = FileAccess.open(folder + "/result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t", true, true))
		file.close()
	print("SITE_BUILDING_10K_PERFORMANCE_", status, " ", JSON.stringify({"folder": folder, "features": requested_count, "building_p95_increment_ms": report.get("building_p95_increment_ms"), "failure": failure}))
	if lab != null: lab.queue_free()
	quit(0 if status == "MEASURED" else 2)
