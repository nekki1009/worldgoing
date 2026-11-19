extends "res://scripts/tests/site_siege_native_integration_test.gd"
## Formal GPU acceptance only. The original TerrainLab automatically advances
## its common clock and renderer once. This script never manually ticks a World.

const PerformanceCrowdSite = preload("res://scripts/terrain_lab/crowd_site.gd")
const SAMPLE_SECONDS := 60.0
const WARMUP_SECONDS := 10.0
const MEDIAN_LIMIT_MS := 33.33
const P95_LIMIT_MS := 50.0
const WINDOW_PIXELS := Vector2i(1600, 1000)
var performance_native := true
var population := 100
var contexts: Array[Dictionary] = []
var original_ids: Array[int] = []
var hit_events: Array[Dictionary] = []
var previous_parts := {}
var performance_report := {}
var frame_sampler: FrameSampler
var sample_clock_premise_error := {}
var sample_minimum_combat_left := -1.0

func _feature_hp(key: String) -> Dictionary:
	var result := {}
	for part: String in lab.terrain.site.features[key].parts:
		result[part] = float(lab.terrain.site.features[key].parts[part].hp)
	return result

class FrameSampler extends Node:
	signal completed
	var sample_seconds := 60.0
	var active := false
	var started_usec := 0
	var ended_usec := 0
	var previous_usec := 0
	var last_guard_usec := 0
	var progress_seconds := 0
	var frames: Array[Array] = []
	var guard_error := {}
	var workload_probe: Callable
	var guard_probe: Callable
	func start(seconds: float, workload: Callable, guard: Callable) -> void:
		sample_seconds = seconds
		workload_probe = workload
		guard_probe = guard
		process_mode = Node.PROCESS_MODE_ALWAYS # Observe a paused original owner; never drive it.
		process_priority = 100 # Observe after the original Lab's process phase.
		active = true
	func _process(_delta: float) -> void:
		if not active: return
		var now := Time.get_ticks_usec()
		if previous_usec == 0:
			started_usec = now; previous_usec = now; last_guard_usec = now
			workload_probe.call(0.0) # The first observed frame must retain a brief pause premise failure too.
			return
		var wall_elapsed := float(now - started_usec) / 1000000.0
		var probe_begun := Time.get_ticks_usec()
		workload_probe.call(wall_elapsed)
		var probe_ms := float(Time.get_ticks_usec() - probe_begun) / 1000.0
		var viewport_rid := get_viewport().get_viewport_rid()
		frames.append([wall_elapsed, float(now - previous_usec) / 1000.0,
			RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid),
			RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid), probe_ms])
		previous_usec = now
		if now - last_guard_usec >= 1000000:
			guard_error = guard_probe.call()
			last_guard_usec = now
		var reached := int(wall_elapsed / 10.0)
		if reached > progress_seconds:
			progress_seconds = reached
			print("SIEGE FORMAL GPU sample: ", mini(reached * 10, 60), " / 60 real seconds; ", frames.size(), " actual frames")
		if wall_elapsed >= sample_seconds or not guard_error.is_empty():
			ended_usec = now; active = false; completed.emit()

func _initialize() -> void:
	suite = "formal_gpu_performance"
	case_name = "100"
	output_root = "res://output/site_siege_close_20261004/formal_gpu_performance"
	super._initialize()
	performance_native = not OS.get_cmdline_user_args().has("--siege-performance-gd")

func _write_result() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_root))
	var file := FileAccess.open(output_root.path_join(suite + "_" + case_name + ("_native" if performance_native else "_gd") + ".json"), FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(_json_value({"ok": not failed, "suite": suite, "case": case_name,
		"checks": checks, "results": results, "measurement": performance_report,
		"scope": "selected formal 100/300 original-person GPU workload, actual original siege contacts and 60 real seconds; no 5k/10k/export claim"}), "\t"))
	file.close()

func _run() -> void:
	create_timer(600.0).timeout.connect(func() -> void:
		failed = true; _write_result(); printerr("SIEGE FORMAL GPU FAIL: 600-second wall deadline including explicit original work-asset preparation"); quit(3))
	if not _check(case_name in ["100", "300"], "one formal GPU population case", case_name): return
	population = int(case_name)
	if not _preflight(): return
	if not _check(DisplayServer.get_name() != "headless" and not OS.get_cmdline_args().has("--fixed-fps"), "real GPU and real unfixed frame clock required", DisplayServer.get_name()): return
	Engine.time_scale = 1.0
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = WINDOW_PIXELS
	root.content_scale_size = WINDOW_PIXELS
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	performance_report.hardware = {"os": OS.get_name(), "os_version": OS.get_version(),
		"cpu": OS.get_processor_name(), "logical_processors": OS.get_processor_count(),
		"gpu_adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(), "godot": Engine.get_version_info(),
		"debug_build": OS.is_debug_build(), "window_pixels": WINDOW_PIXELS, "actual_vsync_mode": DisplayServer.window_get_vsync_mode(),
		"engine_max_fps": Engine.max_fps, "engine_time_scale": Engine.time_scale,
		"native_dll_sha256": FileAccess.get_sha256("res://native/crowd10k/bin/crowd10k.windows.x86_64.dll") if performance_native else "unused"}
	performance_report.population_includes_original_actor = true
	performance_report.owner_mode = "native" if performance_native else "GD"
	if not await _setup_workload(): return
	lab.action_elapsed_measure_enabled = true
	lab.set_process(true)
	if not await _wait_live(func() -> bool: return _all_crew_ready(), 30.0, "every real original crew walks to its original engine station"): return
	for context: Dictionary in contexts:
		var owner_error := _performance_owner_guard(context)
		if not _check(owner_error.is_empty(), "each actual original configured commander and full crew remains present before real orders", owner_error): return
		if str(context.kind) != "ram": continue
		var moved: Dictionary = lab.site_controller.vehicles.order_siege(context.key, "move", {"type": "ground", "cell": [context.goal.x, context.goal.y]}, int(context.commander), true)
		if not _check(moved.ok, "formal RAM receives actual original compound push command", moved): return
	if not await _wait_live(func() -> bool: return _all_ram_arrived(), 30.0, "every formal RAM completes its actual original compound push"): return
	var warmup_begun := Time.get_ticks_usec()
	while Time.get_ticks_usec() - warmup_begun < int(WARMUP_SECONDS * 1000000.0):
		await process_frame
		var error := _live_error()
		if not error.is_empty(): _check(false, "formal owners remain valid during real GPU warmup", error); return
	performance_report.actual_warmup_wall_seconds = float(Time.get_ticks_usec() - warmup_begun) / 1000000.0
	performance_report.render_before = _render_evidence()
	if not _check(int(performance_report.render_before.visible_engine_presenters) == contexts.size()
		and (not performance_native or int(performance_report.render_before.visible_native_instances) > 0),
		"all actual engine textures and original people reach the real formal renderer", performance_report.render_before): return
	for context: Dictionary in contexts:
		context.initial_part_hp = _feature_hp(str(context.target.feature_id))
		previous_parts[str(context.key)] = context.initial_part_hp.duplicate()
		context.initial_sequence = int(_vehicle(context).next_attack_seq)
		context.initial_ammunition = _vehicle(context).cargo.duplicate()
		var attack: Dictionary = lab.site_controller.vehicles.order_siege(context.key, "attack", context.target, int(context.commander), true)
		if not _check(attack.ok, "actual formal engine begins real attack on its original stone parts", {"kind": context.kind, "result": attack}): return
	# One unchanged original fixed clock: an active siege refreshes combat grace
	# before every step, so game seconds equal action seconds at speed one.
	# These bookmarks precede the sampler's first callback; all three terms below
	# use these same bookends, independently of the wall-frame sampling interval.
	var original_speed_begun := float(lab.simulation_speed)
	if not _check(is_equal_approx(original_speed_begun, 1.0) and lab.exchange_enabled and lab._siege_active(),
		"clock accounting begins with original fixed shared steps and active siege at speed one", {"simulation_speed": original_speed_begun, "exchange_enabled": lab.exchange_enabled, "siege_active": lab._siege_active()}): return
	var accepted_action_begun := float(lab.action_elapsed_input_sum)
	var game_clock_begun := SiteRuntime.now(lab.terrain) * 60.0
	var pending_action_begun := float(lab._action_time_remainder)
	performance_report.original_simulation_speed = original_speed_begun
	performance_report.pending_original_action_seconds_at_sample_start = pending_action_begun
	performance_report.sample_scope = "60 real wall seconds of the original formal renderer; original committed game progress and retained action debt are reported separately. Clock conservation does not assert that simulation kept up with wall time."
	var shots_begun := int(lab.siege_shots)
	frame_sampler = FrameSampler.new()
	root.add_child(frame_sampler)
	frame_sampler.start(SAMPLE_SECONDS, _observe_actual_contacts, _live_error)
	await frame_sampler.completed
	lab.set_process(false)
	performance_report.actual_sample_wall_seconds = float(frame_sampler.ended_usec - frame_sampler.started_usec) / 1000000.0
	performance_report.accepted_original_action_input_seconds = float(lab.action_elapsed_input_sum) - accepted_action_begun
	performance_report.original_committed_game_seconds = SiteRuntime.now(lab.terrain) * 60.0 - game_clock_begun
	performance_report.pending_original_action_seconds = float(lab._action_time_remainder)
	performance_report.original_simulation_speed_at_sample_end = float(lab.simulation_speed)
	performance_report.original_action_debt_growth_seconds = float(performance_report.pending_original_action_seconds) - pending_action_begun
	performance_report.original_clock_conservation_residual_seconds = float(performance_report.accepted_original_action_input_seconds) - float(performance_report.original_committed_game_seconds) - float(performance_report.original_action_debt_growth_seconds)
	performance_report.original_clock_accounting = {"formula": "accepted_input - committed_game_seconds = pending_end - pending_start",
		"premise": "unpaused original SceneTree/Site and fixed shared clock; active siege and simulation_speed=1 throughout observed frames; original Runtime combat conversion is 1:1",
		"minimum_observed_combat_left_seconds": sample_minimum_combat_left, "premise_error": sample_clock_premise_error,
		"numerical_tolerance_seconds": EPS, "catchup_threshold_seconds": null,
		"bookends": "after all actual attack orders, before first FrameSampler callback; to completed callback after original Lab process",
		"scope": "conservation only; positive retained debt growth is reported and is not hidden by frame percentile PASS"}
	performance_report.actual_released_projectiles = int(lab.siege_shots) - shots_begun
	performance_report.actual_contact_hp_events = hit_events
	performance_report.sample_count = frame_sampler.frames.size()
	performance_report.frame_ms = _column_summary(1)
	performance_report.gpu_ms = _column_summary(2)
	performance_report.render_cpu_ms = _column_summary(3)
	performance_report.workload_probe_ms = _column_summary(4)
	performance_report.render_after = _render_evidence()
	performance_report.original_person_ids_before = original_ids
	performance_report.original_person_ids_after = _original_person_ids()
	performance_report.engines = _engine_evidence()
	performance_report.pending_real_projectiles_at_sample_end = lab.siege_projectiles.size()
	performance_report.frame_thresholds_ms = {"p50_max": MEDIAN_LIMIT_MS, "p95_max": P95_LIMIT_MS}
	performance_report.frame_threshold_difference_ms = {"p50": float(performance_report.frame_ms.p50) - MEDIAN_LIMIT_MS,
		"p95": float(performance_report.frame_ms.p95) - P95_LIMIT_MS}
	_write_raw_frames()
	await _capture_actual_frame()
	if failed: return
	if not _check(frame_sampler.guard_error.is_empty(), "original owners have no native/shared-step fault during sampling", frame_sampler.guard_error): return
	if not _check(sample_clock_premise_error.is_empty() and is_equal_approx(float(lab.simulation_speed), original_speed_begun),
		"the original unpaused wartime speed-one premise remains valid; never apply its formula across a pause/peace/speed boundary", performance_report.original_clock_accounting): return
	if not _check(is_finite(float(performance_report.original_clock_conservation_residual_seconds)) and absf(float(performance_report.original_clock_conservation_residual_seconds)) <= EPS,
		"accepted original seconds are committed once or retained as debt; no catch-up threshold is imposed", {"accepted_input": performance_report.accepted_original_action_input_seconds, "committed_game_seconds": performance_report.original_committed_game_seconds, "pending_start": pending_action_begun, "pending_end": performance_report.pending_original_action_seconds, "debt_growth": performance_report.original_action_debt_growth_seconds, "residual": performance_report.original_clock_conservation_residual_seconds, "tolerance": EPS}): return
	if not _check(float(performance_report.actual_sample_wall_seconds) >= SAMPLE_SECONDS and frame_sampler.frames.size() > 0,
		"warmup-excluded sample spans at least sixty real seconds", {"seconds": performance_report.actual_sample_wall_seconds, "frames": frame_sampler.frames.size()}): return
	if not _check(original_ids.size() == population and _same_gameplay(original_ids, performance_report.original_person_ids_after), "exact original person identity collection survives the whole real workload", population): return
	for engine: Dictionary in performance_report.engines:
		if not _check(int(engine.actual_attack_sequences) > 0 and float(engine.actual_feature_hp_damage) > EPS,
			"every measured original engine has actual committed attacks and actual material HP hits", engine): return
	if not _check(float(performance_report.frame_ms.p50) <= MEDIAN_LIMIT_MS and float(performance_report.frame_ms.p95) <= P95_LIMIT_MS,
		"formal frame p50 <=33.33ms and p95 <=50ms without lowering acceptance", performance_report.frame_ms): return
	_write_result()
	await _close_lab()
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_FORMAL_GPU_PERFORMANCE_PASS: ", population, " actual original people + ", contexts.size(), " real engines; 60 real wall seconds; p50=", performance_report.frame_ms.p50, " p95=", performance_report.frame_ms.p95, " p99=", performance_report.frame_ms.p99, " committed_game_seconds=", performance_report.original_committed_game_seconds, " retained_debt_growth_seconds=", performance_report.original_action_debt_growth_seconds, "; frame and conservation scope, no catch-up-speed claim")
	quit(0)

func _setup_workload() -> bool:
	if not _new_formal_lab(): return false
	lab.character.terrain_cell = Vector2i(8, 7) # Genesis fixture, before original deployment.
	lab.character.position = (Vector2(lab.character.terrain_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	lab.terrain.site.inventory.siege_bolt = 100
	lab.terrain.site.inventory.siege_stone = 100
	var kinds: Array[String] = []
	kinds.assign(["ballista", "ram"] if population == 100 else ["ballista", "ballista", "ram", "ram", "traction_trebuchet", "traction_trebuchet", "counterweight_trebuchet", "counterweight_trebuchet"])
	var used := {lab.character.terrain_cell: true}
	var first_team := int(lab._next_army_identity())
	# One actual existing-owner formation per engine keeps every original crew
	# inside Native D56. Total original people remains exactly100/300.
	for index in range(kinds.size()):
		var kind := kinds[index]
		var row := 14 + index * 7
		var feature := _paid_feature("stone_wall", Vector2i(48, row - 2 if kind != "ram" else row), Vector2i(1, 5) if kind != "ram" else Vector2i.ONE, {"owner_faction": 1, "material": "stone"})
		if failed: return false
		var target := {"type": "structure", "feature_id": feature, "part_id": "c:%d" % lab.terrain.index(Vector2i(48, row))}
		var pose := _ram_pose(target) if kind == "ram" else {"start": Vector2i(20, row), "goal": Vector2i(20, row), "facing": Vector2i.RIGHT}
		if failed: return false
		var built := SiteRuntime.begin_siege_build(lab.terrain, kind, pose.start, pose.facing, first_team + index, 1)
		if not _check(built.ok, "formal paid original engine fixture", {"kind": kind, "result": built}): return false
		var key := str(built.vehicle)
		var vehicle: Dictionary = lab.terrain.site.vehicles[key]
		var work_slot: Dictionary = SiteRuntime.siege_work_slots(lab.terrain, vehicle)[0]
		var completed := SiteRuntime.advance_siege_work(lab.terrain, key, "construct", float(SiteRuntime.SIEGE_DEFINITIONS[kind].work_seconds), lab.terrain.cell_from_index(int(work_slot.cell)), 0, first_team + index)
		if not _check(completed.ok and vehicle.build.is_empty(), "original paid engine construction completes as initial fixture", completed): return false
		var ammo := str(SiteRuntime.SIEGE_DEFINITIONS[kind].ammo)
		if not ammo.is_empty():
			# Conserved initial fixture allocation; no claim of live resupply.
			var depot: Dictionary = lab.terrain.site.depot_items
			var allocated := SiteRuntime.transfer_items(lab.terrain, depot, lab.terrain.site.inventory, vehicle.holder, vehicle.cargo,
				{ammo: int(SiteRuntime.SIEGE_DEFINITIONS[kind].capacity)}, [], int(depot.version), int(vehicle.holder.version), int(SiteRuntime.SIEGE_DEFINITIONS[kind].capacity))
			if not _check(allocated.ok, "initial ammunition conserved in original bounded magazine", allocated): return false
		var crew_sources: Array[Vector2i] = []
		var crew_stations: Array[Vector2i] = []
		var arrived_pose: Dictionary = vehicle.duplicate(true)
		arrived_pose.cell = lab.terrain.index(pose.goal)
		for slot in range(int(SiteRuntime.SIEGE_DEFINITIONS[kind].standard_crew)):
			var cell := SiteRuntime.siege_crew_cell(lab.terrain, vehicle, slot) - Vector2i(pose.facing)
			if not _check(not used.has(cell) and lab.terrain.is_walkable(cell), "distinct actual initial original crew approach cell", cell): return false
			crew_sources.append(cell); used[cell] = true
			crew_stations.append(SiteRuntime.siege_crew_cell(lab.terrain, arrived_pose, slot))
		contexts.append({"kind": kind, "key": key, "target": target, "goal": pose.goal, "initial_anchor": pose.start,
			"facing": pose.facing, "owner_slot": index, "crew_sources": crew_sources, "crew_stations": crew_stations, "crew": [], "native": performance_native})
	# Initial ordinary people never occupy a real engine, its push corridor or
	# either original crew station endpoint. This is placement, not live claims.
	for context: Dictionary in contexts:
		var vehicle := _vehicle(context)
		var path_length := absi(int(context.goal.x) - int(context.initial_anchor.x)) + absi(int(context.goal.y) - int(context.initial_anchor.y))
		for ahead in range(path_length + 1):
			var along: Dictionary = vehicle.duplicate(true)
			along.cell = lab.terrain.index(Vector2i(context.initial_anchor) + Vector2i(context.facing) * ahead)
			for cell: Vector2i in SiteRuntime.siege_cells(lab.terrain, along): used[cell] = true
			for slot in range(context.crew_sources.size()): used[SiteRuntime.siege_crew_cell(lab.terrain, along, slot)] = true
	var soldier_total := population - (2 if performance_native else 1)
	var sides: Array[Dictionary] = []
	var formations: Array = []
	performance_report.initial_presence_geometry = []
	for index in range(contexts.size()):
		var context: Dictionary = contexts[index]
		var count := int(soldier_total / contexts.size()) + int(index < soldier_total % contexts.size())
		var station_center := Vector2.ZERO
		for cell: Vector2i in context.crew_stations: station_center += Vector2(cell)
		station_center /= context.crew_stations.size()
		# Initial ordinary cells remain behind the true crew approach; RAM retains its proven layout.
		var ordinary_center := station_center - Vector2(context.facing) * float({"ballista": 4.0, "traction_trebuchet": 5.0, "counterweight_trebuchet": 6.0}.get(str(context.kind), 0.0))
		var choices: Array[Vector2i] = []
		var midpoint := Vector2i(station_center.round())
		for y in range(midpoint.y - 12, midpoint.y + 13):
			for x in range(midpoint.x - 12, midpoint.x + 13):
				var cell := Vector2i(x, y)
				if used.has(cell) or not lab.terrain.contains(cell) or not lab.terrain.is_walkable(cell) or int(lab.terrain.feature_at[lab.terrain.index(cell)]) != 0: continue
				# Real ordinary soldiers start behind the actual engine anchor;
				# they cannot be an unrequested friendly obstruction at its muzzle.
				if Vector2(cell - Vector2i(context.goal)).dot(Vector2(context.facing)) >= 0.0: continue
				choices.append(cell)
		choices.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var left := Vector2(a).distance_squared_to(ordinary_center)
			var right := Vector2(b).distance_squared_to(ordinary_center)
			return left < right if not is_equal_approx(left, right) else lab.terrain.index(a) < lab.terrain.index(b))
		var ordinary_count: int = count - context.crew_sources.size()
		if not _check(ordinary_count >= 1 and choices.size() >= ordinary_count, "original compact owner has real commander/ordinary natural cells", index): return false
		var cells: Array[Vector2i] = [choices[0]] # Actual original commander is genesis row0.
		used[choices[0]] = true
		for cell: Vector2i in context.crew_sources: cells.append(cell)
		for ordinary in range(1, ordinary_count): cells.append(choices[ordinary]); used[choices[ordinary]] = true
		var arrived_cells: Array[Vector2i] = cells.duplicate()
		for slot in range(context.crew_stations.size()): arrived_cells[slot + 1] = context.crew_stations[slot]
		var geometry := _performance_presence_geometry(cells, arrived_cells, context.crew_stations.size())
		if not _check(float(geometry.maximum_initial_person_distance) <= float(geometry.native_radius) and float(geometry.maximum_arrived_crew_distance) <= float(geometry.native_radius) and float(geometry.arrived_commander_distance) <= float(geometry.native_radius), "original compact owner geometry fits the unchanged native command radius before/after push", geometry): return false
		geometry["engine_id"] = context.key
		geometry["original_team_id"] = first_team + index
		performance_report.initial_presence_geometry.append(geometry)
		sides.append(_side(count, 0)); formations.append(cells)
	var inactive: Node = lab.crowd_site
	lab.crowd_site = null
	var deployed: Dictionary = lab._deploy_trial_teams(sides, formations, 0)
	lab.crowd_site = inactive
	if not _check(deployed.ok, "actual formal original GD entry creates every seed person and actual equipment", deployed): return false
	for context: Dictionary in contexts:
		var original_team: TerrainArmy = lab.combat_armies[int(context.owner_slot)]
		context.commander = original_team.combat_identity(0)
		if not _check(original_team.team_id == int(_vehicle(context).team_id), "engine refers to its actual original deployed owner"): return false
		for index in range(1, context.crew_sources.size() + 1): context.crew.append(original_team.combat_identity(index))
	if performance_native:
		# Native deploy already prewarms these exact unequipped kit pictures.
		# Admit them explicitly while the original Lab is not processing, so its
		# deferred asset job cannot consume the live admission/sample window.
		var prewarm_begun := Time.get_ticks_usec()
		var prepared_appearances := {}
		var prepared_geometry_keys: Array[String] = []
		for original_team: TerrainArmy in lab.combat_armies:
			for index in range(original_team.combat_units.size()):
				var appearance: Dictionary = lab.site_controller.person_appearance(original_team.combat_identity(index)).duplicate(true)
				for slot: String in ["weapon", "shield"]:
					appearance.parts[slot] = "none"
					if appearance.has("equipment_dyes"): appearance.equipment_dyes.erase(slot)
				if appearance.has("equipment_dyes") and appearance.equipment_dyes.is_empty(): appearance.erase("equipment_dyes")
				var full_appearance_key := JSON.stringify(appearance, "", true)
				if prepared_appearances.has(full_appearance_key): continue
				prepared_appearances[full_appearance_key] = true
				var geometry_key := TerrainArmy.EquipmentAtlas._mixed_key(appearance)
				if not _check(HumanCharacter3DEditor.valid_appearance(appearance) and not geometry_key.is_empty()
					and await PerformanceCrowdSite.prepare_captivity_recipe(lab, appearance),
					"original native deferred captivity kit is explicitly ready before any live workload",
					{"original_person_id": original_team.combat_identity(index), "geometry_key": geometry_key}): return false
				if not prepared_geometry_keys.has(geometry_key): prepared_geometry_keys.append(geometry_key)
		performance_report.original_captivity_asset_preparation_wall_seconds = float(Time.get_ticks_usec() - prewarm_begun) / 1000000.0
		performance_report.original_captivity_asset_geometry_keys = prepared_geometry_keys
		performance_report.captivity_asset_preparation_in_sample = false
		var activated: Dictionary = inactive.deploy([_side(1, 0)], [[Vector2i(58, 66)]])
		if not _check(activated.ok and inactive.active and inactive.siege_native_supported(), "actual D5 native activation imports all original GD people and appends exactly one original native person", activated): return false
	var work_people: Array[int] = []
	var unique_work_people := {}
	for context: Dictionary in contexts:
		for identity: int in context.crew: work_people.append(identity); unique_work_people[identity] = true
	if not _check(work_people.size() == (44 if population == 300 else 6) and unique_work_people.size() == work_people.size(), "exact original six/forty-four crew IDs are unique within the full population", work_people): return false
	var preparing_begun := Time.get_ticks_usec()
	if not _check(await lab.site_controller._prepare_siege_work_people(work_people), "original Controller explicitly prepares every real crew work appearance before GPU admission"): return false
	performance_report.original_work_asset_preparation_wall_seconds = float(Time.get_ticks_usec() - preparing_begun) / 1000000.0
	performance_report.work_asset_preparation_in_sample = false
	for context: Dictionary in contexts:
		for slot in range(context.crew.size()):
			var assigned: Dictionary = lab.site_controller.vehicles.assign_crew(context.key, int(context.crew[slot]), str(slot), int(context.commander), true)
			if not _check(assigned.ok, "original actual person assigned to one original siege duty", assigned): return false
	original_ids = _original_person_ids()
	if not _check(original_ids.size() == population, "formal workload contains exactly requested original people including actor1", {"count": original_ids.size(), "person_ids": original_ids}): return false
	lab.camera.position = Vector2(28, 38) * TerrainRenderer.CELL_PIXELS
	lab.camera.zoom = Vector2.ONE * 0.22
	lab.camera.reset_smoothing(); lab.camera.force_update_scroll()
	lab.renderer.display(lab.terrain)
	lab.site_controller.view.refresh(); lab.site_controller.vehicle_view.refresh()
	performance_report.initial_original_gd_soldiers = soldier_total
	performance_report.initial_original_native_added_soldiers = 1 if performance_native else 0
	performance_report.original_engine_owner_count = contexts.size()
	performance_report.camera = {"world_cell": [28, 38], "zoom": 0.22}
	performance_report.engine_count = contexts.size()
	return true

func _performance_presence_geometry(source: Array[Vector2i], arrived: Array[Vector2i], crew_size: int) -> Dictionary:
	# Native D56 average/actual-member medoid and unchanged10-column envelope.
	var references: Array[Vector2] = []
	for cells: Array in [source, arrived]:
		var mean := Vector2.ZERO
		for cell: Vector2i in cells: mean += Vector2(cell)
		mean /= cells.size()
		var reference := Vector2(cells[0])
		for cell: Vector2i in cells:
			if Vector2(cell).distance_squared_to(mean) < reference.distance_squared_to(mean): reference = Vector2(cell)
		references.append(reference)
	var columns := mini(10, source.size())
	var rows := ceili(float(source.size()) / float(columns))
	var radius := maxf(8.0, Vector2(float(columns - 1) * 0.5, float(rows - 1) * 0.5).length() + 2.0)
	var maximum := 0.0
	var crew_maximum := 0.0
	for cell: Vector2i in source: maximum = maxf(maximum, Vector2(cell).distance_to(references[0]))
	for index in range(1, crew_size + 1): crew_maximum = maxf(crew_maximum, Vector2(arrived[index]).distance_to(references[1]))
	return {"member_count": source.size(), "crew_count": crew_size, "native_columns": columns, "native_radius": radius,
		"source_cells": source, "expected_arrived_cells": arrived, "initial_reference": references[0], "expected_arrived_reference": references[1],
		"maximum_initial_person_distance": maximum, "maximum_arrived_crew_distance": crew_maximum, "arrived_commander_distance": Vector2(arrived[0]).distance_to(references[1])}

func _performance_owner_guard(context: Dictionary) -> Dictionary:
	var original_team: Variant = lab.site_controller.vehicles._siege_team(_vehicle(context))
	if original_team == null or not original_team.command_eligible(original_team.current_commander) or original_team.combat_identity(original_team.current_commander) != int(context.commander):
		return {"engine": context.key, "error": "original configured commander no longer physically present", "commander": context.commander}
	if performance_native:
		var members := PackedInt32Array()
		for identity: int in context.crew: members.append(int(lab.crowd_site._index_by_id[identity]))
		# Original zero-debit admission proves true per-crew present; no second
		# round, fatigue charge, position, role, order or clock is committed.
		if not lab.crowd_site.crowd.charge_siege_round(members, 0.0): return {"engine": context.key, "error": "original native crew presence/charge admission rejected", "crew_ids": context.crew}
	return {}

func _original_person_ids() -> Array[int]:
	var ids: Array[int] = []
	if lab.crowd_site != null and lab.crowd_site.active:
		ids.assign(lab.crowd_site.crowd.person_ids())
	else:
		for actor: TerrainTestCharacter in lab.combat_actors:
			if lab.actor_present(actor): ids.append(actor.person_id)
		for team: TerrainArmy in lab.combat_armies:
			for index in range(team.combat_units.size()):
				if team.is_member(index): ids.append(team.combat_identity(index))
	ids.sort()
	return ids

func _all_crew_ready() -> bool:
	for context: Dictionary in contexts:
		if not lab.site_controller.vehicles.crew_ready(_vehicle(context)): return false
	return true

func _all_ram_arrived() -> bool:
	for context: Dictionary in contexts:
		if str(context.kind) != "ram": continue
		var vehicle := _vehicle(context)
		if not vehicle.move.is_empty() or int(vehicle.cell) != lab.terrain.index(context.goal) or not lab.site_controller.vehicles.crew_ready(vehicle): return false
	return true

func _live_error() -> Dictionary:
	# Resource publication is preparation, not steady-state workload. Keep a
	# newly deferred original capture visible as a real failure, never an FPS pass.
	if is_instance_valid(TerrainArmy.EquipmentAtlas._preparation):
		return {"error": "original optional Atlas capture is active inside live workload", "sample_excludes_asset_preparation": false}
	if lab == null or not is_instance_valid(lab) or paused or bool(lab.terrain.site.paused): return {"error": "formal scene paused or missing"}
	var original_fault: Dictionary = lab.site_controller.original_step_fault_guard()
	if not original_fault.ok: return original_fault
	if lab.crowd_site != null and lab.crowd_site.active and not lab.crowd_site.last_event_error.is_empty(): return lab.crowd_site.last_event_error
	for context: Dictionary in contexts:
		var owner_error := _performance_owner_guard(context)
		if not owner_error.is_empty(): return owner_error
	return {}

func _wait_live(predicate: Callable, maximum_seconds: float, label: String) -> bool:
	var begun := Time.get_ticks_usec()
	while not bool(predicate.call()) and Time.get_ticks_usec() - begun < int(maximum_seconds * 1000000.0):
		await process_frame
		var error := _live_error()
		if not error.is_empty(): return _check(false, label, error)
	return _check(bool(predicate.call()), label, {"maximum_wall_seconds": maximum_seconds})

func _observe_actual_contacts(wall_elapsed: float) -> void:
	# Read only. Never mark combat, change speed, drain debt or tick a second clock.
	# Original _advance_original_shared_step refreshes active-siege grace before
	# each step; a peace/speed boundary invalidates this test's 1:1 premise.
	var combat_left := float(lab.terrain.site.get("combat_left", 0.0))
	sample_minimum_combat_left = combat_left if sample_minimum_combat_left < 0.0 else minf(sample_minimum_combat_left, combat_left)
	if sample_clock_premise_error.is_empty() and (paused or bool(lab.terrain.site.get("paused", false)) or not lab.exchange_enabled or not is_equal_approx(float(lab.simulation_speed), 1.0) or not lab._siege_active()):
		sample_clock_premise_error = {"wall_elapsed_seconds": wall_elapsed, "simulation_speed": lab.simulation_speed,
			"tree_paused": paused, "site_paused": bool(lab.terrain.site.get("paused", false)),
			"exchange_enabled": lab.exchange_enabled, "siege_active": lab._siege_active(), "combat_left": combat_left}
	for context: Dictionary in contexts:
		var key := str(context.key)
		var before: Dictionary = previous_parts[key]
		var after := _feature_hp(str(context.target.feature_id))
		for part: String in before:
			var damage := float(before[part]) - float(after.get(part, 0.0))
			if damage > EPS:
				hit_events.append({"wall_elapsed_seconds": wall_elapsed, "engine_id": key, "kind": context.kind,
					"feature_id": context.target.feature_id, "part_id": part, "actual_hp_damage": damage,
					"actual_hp_after": after.get(part, 0.0), "observed_original_next_attack_seq": _vehicle(context).next_attack_seq})
		previous_parts[key] = after

func _engine_evidence() -> Array[Dictionary]:
	var engines: Array[Dictionary] = []
	for context: Dictionary in contexts:
		var vehicle := _vehicle(context)
		var final_hp := _feature_hp(str(context.target.feature_id))
		var damage := 0.0
		for part: String in context.initial_part_hp: damage += float(context.initial_part_hp[part]) - float(final_hp.get(part, 0.0))
		engines.append({"vehicle_id": context.key, "kind": context.kind, "original_crew_person_ids": context.crew,
			"original_commander_person_id": context.commander, "initial_anchor": context.initial_anchor,
			"actual_final_anchor": lab.terrain.cell_from_index(int(vehicle.cell)), "original_target": context.target,
			"actual_attack_sequences": int(vehicle.next_attack_seq) - int(context.initial_sequence), "actual_feature_hp_damage": damage,
			"initial_all_part_hp": context.initial_part_hp, "actual_final_all_part_hp": final_hp,
			"initial_ammunition": context.initial_ammunition, "actual_final_ammunition": vehicle.cargo,
			"original_magazine_capacity": SiteRuntime.SIEGE_DEFINITIONS[str(context.kind)].capacity,
			"actual_end_action": vehicle.action, "actual_end_phase": vehicle.phase})
	return engines

func _render_evidence() -> Dictionary:
	var visible_engines := 0
	var visible_native_instances := 0
	var view: SiteVehicleView = lab.site_controller.vehicle_view
	for context: Dictionary in contexts:
		var node: Node2D = view._siege_nodes.get(str(context.key), view._sprites.get(str(context.key)))
		if node == null or not node.is_visible_in_tree(): continue
		var textured := node is Sprite2D and (node as Sprite2D).texture != null
		for sprite: Sprite2D in node.find_children("*", "Sprite2D", true, false):
			if sprite.is_visible_in_tree() and sprite.texture != null: textured = true
		if textured: visible_engines += 1
	if lab.crowd_site != null and lab.crowd_site.active:
		for node: MultiMeshInstance2D in lab.crowd_site.nodes.values():
			if node.is_visible_in_tree(): visible_native_instances += node.multimesh.instance_count
	return {"visible_engine_presenters": visible_engines, "visible_native_instances": visible_native_instances,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"original_person_count": _original_person_ids().size(), "viewport_pixels": root.size}

func _column_summary(column: int) -> Dictionary:
	var values: Array[float] = []
	var total := 0.0
	for frame: Array in frame_sampler.frames:
		values.append(float(frame[column])); total += float(frame[column])
	values.sort()
	if values.is_empty(): return {"p50": 0.0, "p95": 0.0, "p99": 0.0, "mean": 0.0, "max": 0.0, "n": 0}
	return {"p50": values[maxi(0, ceili(float(values.size()) * 0.50) - 1)],
		"p95": values[maxi(0, ceili(float(values.size()) * 0.95) - 1)],
		"p99": values[maxi(0, ceili(float(values.size()) * 0.99) - 1)],
		"mean": total / float(values.size()), "max": values.back(), "n": values.size()}

func _write_raw_frames() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_root))
	var file := FileAccess.open(output_root.path_join("frames_" + case_name + ("_native" if performance_native else "_gd") + ".csv"), FileAccess.WRITE)
	if file == null: _check(false, "raw observed frame CSV opens"); return
	file.store_line("frame_index,wall_elapsed_seconds,frame_ms,gpu_ms,render_cpu_ms,workload_probe_ms")
	for index in range(frame_sampler.frames.size()):
		var row: Array = frame_sampler.frames[index]
		file.store_line("%d,%.6f,%.6f,%.6f,%.6f,%.6f" % [index + 1, row[0], row[1], row[2], row[3], row[4]])
	file.close()

func _capture_actual_frame() -> void:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var path := output_root.path_join("formal_" + case_name + ("_native" if performance_native else "_gd") + ".png")
	if not _check(not picture.is_empty() and picture.save_png(path) == OK, "actual formal GPU framebuffer saved as visual workload proof", path): return
	performance_report.actual_gpu_capture = path
