extends "res://scripts/tests/site_army_combat_longrun_test.gd"
## Actual GPU/render-frame acceptance, not the inherited manual-step pilot.
## Canonical helper: GPU, TimeoutSeconds 160; internal watchdog: 140 seconds.
## Default: two seconds of render-only warmup, then at least 60 wall seconds.
## --short=10 is diagnostic ONLY and can never set targets_met=true.
## --baseline-equipment keeps all original gear: diagnostic ONLY, not mixed acceptance.
## --m25-test-catalog uses the explicitly admitted current-source test recipe;
## it does not repair or claim publication of the other 31 formal recipes.
## Exit 0 means a complete measurement, NOT that its performance targets passed.
## --fixed120 diagnoses a fixed common 120 Hz grid with a retained <1/120 s
## remainder. It changes render partitioning, not frequency, damage or time scale.
## --strict-cull diagnoses strict contact ordering and original melee hit-set
## exclusion. Legacy approximate-sort recordings are retained as separate results.
## --cheap-bounds diagnoses a static native bound only after the original face
## has been fitted. No query pose; positives still use complete original shapes.
## --centered-bounds also uses the optional native per-clip Hips envelope.
## --fatigue-zero diagnoses the exact already-zero idle fatigue fast path.
## --no-stage-profile uses production Lab profiling settings; wall/FPS/contact
## observers remain active, but nested per-candidate timing is disabled.
## --weapon-mesh-filter / --pose-result-reuse isolate the two redundant-work candidates.
## --compiled-source enables the opt-in Source geometry candidate, without shadow
## comparisons or another simulation loop. Original unsupported requests fall back.

const LongrunFixture = preload("res://scripts/tests/site_army_combat_longrun_test.gd")
const EquipmentAtlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const CoarseProxy = preload("res://scripts/tests/helpers/site_combat_proxy.gd")
const M25_TEST_CATALOG := "res://output/terrain_army_m25_weapon_refresh_20260913/test_catalog.json"
const M25_PERFORMANCE_CATALOG := "res://output/terrain_army_m25_performance_20260913/test_catalog.json"
const M25_SCALAR_CATALOG := "res://output/terrain_army_m25_scalar_20260913/test_catalog.json"
const REALTIME_OUTPUT := "res://output/site_army_combat_realtime"
const REALTIME_INTERNAL_SECONDS := 140.0
const WARMUP_WALL_SECONDS := 2.0
const MEASURE_WALL_SECONDS := 60.0
const MIN_COMBAT_SECONDS := 55.0
const TARGET_FPS := 30.0
const TARGET_P95_MS := 33.334
const MAX_STALL_MS := 1000.0
const DEBT_EPSILON_SECONDS := 0.00001
const SOURCE_PATHS := [
	"res://scripts/tests/site_army_combat_realtime_test.gd",
	"res://scripts/tests/helpers/site_combat_proxy.gd",
	"res://scripts/tests/site_army_combat_longrun_test.gd",
	"res://scripts/terrain_lab/terrain_lab.gd",
	"res://scripts/terrain_lab/terrain_data.gd",
	"res://scripts/terrain_lab/terrain_army.gd",
	"res://scripts/terrain_lab/terrain_army_contact_source.gd",
	"res://scripts/terrain_lab/terrain_army_shapes_descriptor.gd",
	"res://scripts/terrain_lab/compiled_contact_shapes.cs",
	"res://scripts/terrain_lab/terrain_army_source_bounds.gd",
	"res://scripts/terrain_lab/terrain_army_equipment_atlas.gd",
	"res://scripts/terrain_lab/terrain_weapon_collision.gd",
	"res://scripts/terrain_lab/terrain_gpu_skinner.gd",
	"res://scripts/terrain_lab/terrain_test_character.gd",
	"res://scripts/terrain_lab/terrain_test_npc.gd",
	"res://scripts/terrain_lab/site_controller.gd",
	"res://scripts/terrain_lab/site_runtime.gd",
	"res://scripts/terrain_lab/person_fatigue.gd",
	"res://scripts/terrain_lab/site_sustain.gd",
	"res://scripts/terrain_lab/site_store.gd",
	"res://scripts/ui/human_character_3d_editor.gd",
	"res://scripts/terrain_lab/character_combat_timings.gd",
	"res://scripts/tools/bake_terrain_army_soldier.gd",
	"res://scripts/tools/terrain_army_recipe_bake_plan.gd",
	"res://assets/characters/human/q35/standard_anime_male_character_pack.glb",
	"res://assets/characters/human/q35/standard_anime_female_character_pack.glb",
	EquipmentAtlas.BASE_MANIFEST,
	"res://project.godot",
]

class RealtimeLab extends LongrunFixture.ObservedLab:
	var recording := false
	var input_seconds := 0.0
	var consumed_action_seconds := 0.0
	var process_cpu_us := 0
	var maximum_abs_debt := 0.0
	var maximum_frame_debt := 0.0
	var unexpected_paused_frames := 0
	var raw_input_deltas := PackedFloat64Array()
	var raw_action_deltas := PackedFloat64Array()
	var raw_process_cpu_ms := PackedFloat64Array()
	var stage_usec := {"fatigue_supply": 0, "action_step_inclusive": 0, "army_contacts_inclusive": 0,
		"resolve_contacts": 0, "sort_contacts": 0}
	var gpu_batch_profile_enabled := false
	var pose_demand_steps := 0
	var pose_demand_total := 0
	var pose_demand_histogram: Dictionary = {}
	var cached_pose_histogram: Dictionary = {}
	var bucket_trace_enabled := false
	var bucket_trace_start := 0
	var bucket_trace_steps: Dictionary = {}
	var bucket_trace: Dictionary = {}

	func _advance_fatigue(seconds: float) -> void:
		var started := Time.get_ticks_usec()
		super._advance_fatigue(seconds)
		stage_usec.fatigue_supply += Time.get_ticks_usec() - started

	func _advance_combat(delta: float, combat_clock: float = -1.0) -> void:
		var observe_demand := recording and gpu_batch_profile_enabled
		var poses_before := int(TerrainArmy._contact_source.query_profile.true_pose_evaluations) if observe_demand else 0
		var started := Time.get_ticks_usec()
		super._advance_combat(delta, combat_clock)
		stage_usec.action_step_inclusive += Time.get_ticks_usec() - started
		if observe_demand:
			# Read counters only after the unchanged synchronous owner has finished.
			# Restores and dependency-ordered queries are NOT proven batchable jobs.
			assert(delta <= TerrainLab.ACTION_STEP and delta > 0.0)
			var demand := int(TerrainArmy._contact_source.query_profile.true_pose_evaluations) - poses_before
			var cached: int = TerrainArmy._contact_source._poses.size()
			assert(demand >= 0)
			pose_demand_steps += 1
			pose_demand_total += demand
			pose_demand_histogram[demand] = int(pose_demand_histogram.get(demand, 0)) + 1
			cached_pose_histogram[cached] = int(cached_pose_histogram.get(cached, 0)) + 1

	func _collect_army_contacts(previous: Array[PackedVector2Array], current: Array[PackedVector2Array], source_cell: Vector2i, source_position: Vector2, source: Variant, source_unit: int, ranged: bool = false, prepared: Array = []) -> Array[Dictionary]:
		var started := Time.get_ticks_usec()
		var result := super._collect_army_contacts(previous, current, source_cell, source_position, source, source_unit, ranged, prepared)
		stage_usec.army_contacts_inclusive += Time.get_ticks_usec() - started
		# Capture only 16 original tail steps, without poses or extra contact
		# calls. Both A/B runs pay the same observer policy; FPS includes it.
		if bucket_trace_enabled and recording and _sampling_army_contacts and not current.is_empty() and Time.get_ticks_usec() - bucket_trace_start >= 50000000 and (bucket_trace_steps.has(shared_steps) or bucket_trace_steps.size() < 16):
			bucket_trace_steps[shared_steps] = true
			var bounds := Rect2(current[0][0], Vector2.ZERO)
			for shapes: Array in [previous, current]:
				for shape: PackedVector2Array in shapes:
					for vertex: Vector2 in shape:
						bounds = bounds.expand(vertex)
			for team: TerrainArmy in combat_armies:
				var ground_key := ["grounds", team.get_instance_id()]
				if not team.combat_enabled or not _army_contact_geometry.has(ground_key):
					continue
				var trace_key := [shared_steps, team.get_instance_id()]
				if not bucket_trace.has(trace_key):
					bucket_trace[trace_key] = {"grounds": _army_contact_geometry[ground_key].duplicate(), "queries": []}
				bucket_trace[trace_key].queries.append({"bounds": bounds.grow(256.0), "source_unit": source_unit if source == team else -1})
		return result

	func _resolve_combat_contacts() -> void:
		var started := Time.get_ticks_usec()
		super._resolve_combat_contacts()
		stage_usec.resolve_contacts += Time.get_ticks_usec() - started

	func _sort_contacts(hits: Array[Dictionary]) -> void:
		var started := Time.get_ticks_usec()
		super._sort_contacts(hits)
		stage_usec.sort_contacts += Time.get_ticks_usec() - started

	func _process(delta: float) -> void:
		# Called only by Godot. The inherited observer delegates every original
		# common step unchanged; no accumulator, clamp, batch or replacement AI.
		var before_action := action_seconds
		var before_cpu := Time.get_ticks_usec()
		var paused_before: bool = get_tree().paused or bool(terrain.site.get("paused", false))
		super._process(delta)
		var elapsed_cpu := Time.get_ticks_usec() - before_cpu
		if not recording:
			return
		var advanced := action_seconds - before_action
		input_seconds += delta
		consumed_action_seconds += advanced
		process_cpu_us += elapsed_cpu
		maximum_abs_debt = maxf(maximum_abs_debt, absf(input_seconds - consumed_action_seconds))
		maximum_frame_debt = maxf(maximum_frame_debt, absf(delta - advanced))
		unexpected_paused_frames += int(paused_before or get_tree().paused or bool(terrain.site.get("paused", false)))
		raw_input_deltas.append(delta)
		raw_action_deltas.append(advanced)
		raw_process_cpu_ms.append(elapsed_cpu / 1000.0)

var _realtime_lab: RealtimeLab
var _short_diagnostic := false
var _baseline_equipment := false
var _fixed120 := false
var _strict_cull := false
var _cheap_bounds := false
var _centered_bounds := false
var _fatigue_zero := false
var _stage_profile := true
var _contact_inputs := false
var _weapon_mesh_filter := false
var _skinning_profile := false
var _script_profile := false # Requires --debug; report before ScriptInstances are freed.
var _gpu_batch_profile := false # Test-only original same-step demand, not a GPU scheduler.
var _pose_result_reuse := false
var _recipe_refresh := false
var _compiled_source := false
var _coarse_proxy := false
var _contact_buckets := false
var _bucket_profile := false
var _proxy: RefCounted
var _proxy_source_start := 0
var _measurement_target := MEASURE_WALL_SECONDS
var _finished := false
var _measurement_started_us := 0
var _previous_draw_us := 0
var _last_draw_cpu_us := 0
var _draw_intervals_ms: Array[float] = []
var _draw_elapsed_seconds: Array[float] = []
var _draw_lab_cpu_ms: Array[float] = []
var _engine_process_ms: Array[float] = []
var _original_rows := {}
var _original_inventory := {}
var _initial_site_seconds := 0.0
var _baseline_path := ""
var _baseline_hash := ""
var _measurement_camera_position := Vector2.ZERO
var _measurement_camera_zoom := Vector2.ONE
var _measurement_window_size := Vector2i.ZERO
var _measurement_view_changed := false

func _initialize() -> void:
	# Do not call the inherited initializer/run or reuse any old output path.
	started_us = Time.get_ticks_usec()
	deadline_us = started_us + int(REALTIME_INTERNAL_SECONDS * 1000000.0)
	_short_diagnostic = "--short=10" in OS.get_cmdline_user_args()
	_baseline_equipment = "--baseline-equipment" in OS.get_cmdline_user_args()
	_fixed120 = "--fixed120" in OS.get_cmdline_user_args()
	_strict_cull = "--strict-cull" in OS.get_cmdline_user_args()
	_centered_bounds = "--centered-bounds" in OS.get_cmdline_user_args()
	_cheap_bounds = "--cheap-bounds" in OS.get_cmdline_user_args() or _centered_bounds
	_fatigue_zero = "--fatigue-zero" in OS.get_cmdline_user_args()
	_stage_profile = "--no-stage-profile" not in OS.get_cmdline_user_args()
	_contact_inputs = "--contact-inputs" in OS.get_cmdline_user_args()
	_weapon_mesh_filter = "--weapon-mesh-filter" in OS.get_cmdline_user_args()
	_skinning_profile = "--skinning-profile" in OS.get_cmdline_user_args()
	_script_profile = "--script-profile" in OS.get_cmdline_user_args()
	_gpu_batch_profile = "--gpu-batch-profile" in OS.get_cmdline_user_args()
	if _script_profile:
		assert(EngineDebugger.is_active() and EngineDebugger.has_profiler(&"scripts"))
	_pose_result_reuse = "--pose-result-reuse" in OS.get_cmdline_user_args()
	_recipe_refresh = "--recipe-refresh" in OS.get_cmdline_user_args()
	_compiled_source = "--compiled-source" in OS.get_cmdline_user_args()
	_coarse_proxy = "--coarse-proxy" in OS.get_cmdline_user_args()
	_contact_buckets = "--contact-buckets" in OS.get_cmdline_user_args()
	_bucket_profile = "--bucket-profile" in OS.get_cmdline_user_args()
	assert(not _coarse_proxy or not (_compiled_source or _cheap_bounds or _strict_cull), "Isolate changed collision policy")
	TerrainLab.FatigueGeometry.strict_contact_order_enabled = _strict_cull
	TerrainLab.FatigueGeometry.melee_hit_cull_enabled = _strict_cull
	assert(int("--m25-test-catalog" in OS.get_cmdline_user_args()) + int("--m25-performance-catalog" in OS.get_cmdline_user_args()) + int("--m25-scalar-catalog" in OS.get_cmdline_user_args()) <= 1)
	if "--m25-scalar-catalog" in OS.get_cmdline_user_args():
		assert(EquipmentAtlas.set_catalog_path(M25_SCALAR_CATALOG))
	elif "--m25-performance-catalog" in OS.get_cmdline_user_args():
		assert(EquipmentAtlas.set_catalog_path(M25_PERFORMANCE_CATALOG))
	elif "--m25-test-catalog" in OS.get_cmdline_user_args():
		assert(EquipmentAtlas.set_catalog_path(M25_TEST_CATALOG))
	_measurement_target = 10.0 if _short_diagnostic else MEASURE_WALL_SECONDS
	var fingerprints := _source_fingerprints()
	var source_key := JSON.stringify(fingerprints).sha256_text().substr(0, 16)
	var run_key := "%s_%s" % [int(Time.get_unix_time_from_system()), started_us]
	var run_mode := ("baseline_equipment_diagnostic_" if _baseline_equipment else "mixed_equipment_") + ("short10" if _short_diagnostic else "full60")
	if _fixed120:
		run_mode += "_fixed120"
	if _strict_cull:
		run_mode += "_strict_cull"
	if _cheap_bounds:
		run_mode += "_static_bounds"
	if _centered_bounds:
		run_mode += "_centered"
	if _fatigue_zero:
		run_mode += "_fatigue_zero"
	if not _stage_profile:
		run_mode += "_no_stage_profile"
	if _contact_inputs:
		run_mode += "_contact_inputs"
	if _weapon_mesh_filter:
		run_mode += "_weapon_filter"
	if _skinning_profile:
		run_mode += "_skinning_profile"
	if _script_profile:
		run_mode += "_script_profile_diagnostic"
	if _gpu_batch_profile:
		run_mode += "_gpu_batch_profile"
	if _pose_result_reuse:
		run_mode += "_pose_result_reuse"
	if _recipe_refresh:
		run_mode += "_recipe_refresh"
	if _compiled_source:
		run_mode += "_compiled_source"
	if _coarse_proxy:
		run_mode += "_coarse_proxy"
	if _contact_buckets:
		run_mode += "_contact_buckets"
	if _bucket_profile:
		run_mode += "_bucket_profile"
	output_path = "%s/%s/%s/%s" % [REALTIME_OUTPUT, source_key, run_mode, run_key]
	measurements = {
		"targets_met": false, "measurement_complete": false, "full_acceptance_window": false,
		"status": "setup", "scope": "Original 200-row TerrainLab, automatic native _process, normal HUD, exact common 120 Hz maximum substeps; real GPU frame intervals",
		"source_fingerprints": fingerprints, "output_path": ProjectSettings.globalize_path(output_path),
		"mode": run_mode, "fixture_mode": "baseline-equipment DIAGNOSTIC ONLY" if _baseline_equipment else "mixed-equipment",
		"baseline_equipment_diagnostic_only": _baseline_equipment,
		"actual_equipment_catalog": EquipmentAtlas._catalog_path,
		"test_catalog_only": EquipmentAtlas._catalog_path != EquipmentAtlas.CATALOG,
		"source_fingerprint_policy": "SHA256 at setup/end only, including original HumanEditor, both raw GLBs, actual selected catalog, baseline manifest and every referenced recipe manifest; OFF and ON both include the compiled shapes and native descriptor; never rehash GLBs at checkpoints",
		"internal_deadline_seconds": REALTIME_INTERNAL_SECONDS, "helper_timeout_seconds": 160,
		"required_wall_seconds": _measurement_target, "required_full_wall_seconds": MEASURE_WALL_SECONDS,
		"required_continuous_combat_seconds": MIN_COMBAT_SECONDS,
		"thresholds": {"fps": TARGET_FPS, "p95_ms": TARGET_P95_MS, "maximum_stall_ms": MAX_STALL_MS,
			"delta_wall_ratio_min_exclusive": 0.95, "delta_wall_ratio_max": 1.05, "debt_epsilon_seconds": DEBT_EPSILON_SECONDS},
		"percentile_definition": "Nearest rank; FPS is presented frame count divided by monotonic wall time, not mean instantaneous FPS",
		"display": DisplayServer.get_name(), "checkpoints": [],
		"native_physics_ticks_per_second": Engine.physics_ticks_per_second,
		"native_max_physics_steps_per_frame": Engine.max_physics_steps_per_frame,
		"manual_simulation_calls": 0, "production_hud_enabled": true,
		"observer_scope": "Inherited exact-contact counters plus one stopwatch per native Lab frame; Lab CPU is inclusive of its clock/AI/contacts/HUD, not separate Army/Actor rendering or GPU time",
		"engine_process_monitor_note": "Godot 4.6.2 TIME_PROCESS is a periodically published process maximum, not independent per-frame CPU samples; its statistics are diagnostic monitor readings only",
		"automatic_test_save_suppressed": true,
	}
	measurements.action_clock = {"fixed120": _fixed120, "step_seconds": TerrainLab.ACTION_STEP,
		"maximum_retained_fraction_seconds": TerrainLab.ACTION_STEP if _fixed120 else 0.0,
		"policy": "Retain every accepted delta; fixed mode carries less than one 120 Hz step across native render frames, never a catch-up cap or discarded elapsed time."}
	measurements.geometry_rigid_hull_dedup_enabled = TerrainLab.FatigueGeometry.new().rigid_hull_dedup_enabled
	measurements.strict_contact_order_and_melee_hit_cull = _strict_cull
	measurements.cheap_query_bounds_enabled = _cheap_bounds
	measurements.centered_query_bounds_enabled = _centered_bounds
	measurements.cheap_query_bounds_policy = "Warm original target-face cache; native all-curve static local enclosure, cold/unsupported original full fallback. No dynamic pose-bound cache."
	measurements.fatigue_zero_fast_path_enabled = _fatigue_zero
	measurements.lab_stage_profiling_enabled = _stage_profile
	measurements.contact_input_reuse_enabled = _contact_inputs
	measurements.weapon_mesh_filter_enabled = _weapon_mesh_filter
	measurements.skinning_profile_enabled = _skinning_profile
	measurements.native_script_profile_diagnostic = _script_profile
	measurements.gpu_batch_profile_enabled = _gpu_batch_profile
	measurements.same_batch_result_reuse_enabled = _pose_result_reuse
	measurements.recipe_refresh_batch_enabled = _recipe_refresh
	measurements.compiled_geometry_enabled = _compiled_source
	measurements.coarse_proxy_enabled = _coarse_proxy
	measurements.contact_buckets_enabled = _contact_buckets
	measurements.contact_bucket_observer_enabled = _bucket_profile
	measurements.collision_policy = "Coarse offline boxes, continuous interpolation, shared all-person region armor; NOT original exact collision" if _coarse_proxy else "Original native exact collision"
	measurements.compiled_geometry_shadow_enabled = false
	measurements.compiled_geometry_profile_scope = "Original Source geometry attempts only, excluding Source result-cache hits. Start snapshot excludes setup; final delta includes actual view builds, successes and per-reason fallbacks. No shadow comparison, extra combat loop or pose replacement."
	if _fixed120:
		measurements.scope = "Original 200-row TerrainLab, automatic native _process, normal HUD, fixed common 120 Hz with retained sub-step fraction; real GPU frame intervals"
	_write()
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not _finished and Time.get_ticks_usec() >= deadline_us:
		_finish_realtime("internal_deadline", false)
	return false

func _source_fingerprints() -> Dictionary:
	var result := {}
	if FileAccess.file_exists(CoarseProxy.PROFILE_PATH):
		result[CoarseProxy.PROFILE_PATH] = FileAccess.get_sha256(CoarseProxy.PROFILE_PATH)
	for path: String in SOURCE_PATHS:
		result[path] = FileAccess.get_sha256(path)
	var catalog_path: String = EquipmentAtlas._catalog_path
	result[catalog_path] = FileAccess.get_sha256(catalog_path)
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
	if catalog is Dictionary and catalog.get("recipes") is Dictionary:
		var catalog_directory: String = catalog_path.get_base_dir() + "/"
		for paths: Variant in catalog.recipes.values():
			if not paths is Array:
				continue
			for value: Variant in paths:
				if not value is String:
					continue
				var path: String = value.simplify_path()
				if path.begins_with(catalog_directory) and path.get_file() == "manifest.json":
					result[path] = FileAccess.get_sha256(path)
	return result

func _redundant_work_instances(lab: TerrainLab) -> Array:
	var result: Array = [TerrainArmy._contact_source.geometry]
	for team: TerrainArmy in lab.combat_armies:
		result.append(team._combat_geometry)
	for actor: TerrainTestCharacter in lab.combat_actors:
		result.append(actor._geometry)
	return result

func _redundant_work_flags_match(lab: TerrainLab) -> bool:
	for team: TerrainArmy in lab.combat_armies:
		if (team.combat_proxy != null) != _coarse_proxy:
			return false
	for actor: TerrainTestCharacter in lab.combat_actors:
		if (actor.combat_proxy != null) != _coarse_proxy:
			return false
	if TerrainArmy._contact_source.same_batch_result_reuse_enabled != _pose_result_reuse:
		return false
	if TerrainArmy._contact_source.compiled_geometry_enabled != _compiled_source or TerrainArmy._contact_source.compiled_geometry_shadow_enabled:
		return false
	for geometry: RefCounted in _redundant_work_instances(lab):
		if geometry.weapon_mesh_filter_enabled != _weapon_mesh_filter or geometry.skinning_profile_enabled != _skinning_profile:
			return false
	return true

func _setup_unavailable(code: String, message: String, details: Dictionary = {}) -> void:
	measurements.unavailable = {"code": code, "message": message, "details": details}
	_finish_realtime("fixture_unavailable", false)

func _preflight_mixed_equipment(lab: TerrainLab) -> Dictionary:
	# Read-only validation of EVERY actual prospective transfer before the
	# inherited helper can move even the first original shield/armor item.
	var checked: Array[Dictionary] = []
	for team: TerrainArmy in lab.combat_armies:
		var front_count := 0
		for index: int in team.combat_units.size():
			var adjacent := false
			for other: TerrainArmy in lab.combat_armies:
				if other.faction_id == team.faction_id:
					continue
				for cell: Vector2i in other.cells:
					var offset := cell - team.cells[index]
					if absi(offset.x) + absi(offset.y) == 1:
						adjacent = true
						break
			if not adjacent:
				continue
			front_count += 1
			var identity: int = team.combat_identity(index)
			var body: Dictionary = team.combat_units[index]
			var appearance: Dictionary = team.equipment_appearance(index).duplicate(true)
			for slot: String in ["shield", "armor"]:
				if not body.item_state.equipped.has(slot):
					return {"ok": false, "code": "FIXTURE_MISSING_GEAR", "message": "Original front-rank loadout lacks a required held item", "person_id": identity, "slot": slot}
				appearance.parts[slot] = "none"
			var person: Dictionary = lab.site_controller.person_actions._person(identity)
			var admitted: Dictionary = lab.site_controller._equipment_recipe_guard(person, appearance)
			if not admitted.ok:
				return {"ok": false, "code": str(admitted.code), "message": str(admitted.message),
					"person_id": identity, "team_id": team.team_id, "appearance": appearance,
					"checked_before_failure": checked, "source_items_moved": 0}
			checked.append({"person_id": identity, "team_id": team.team_id, "appearance": appearance})
		if front_count != 10:
			return {"ok": false, "code": "FIXTURE_FRONT_RANK", "message": "Original trial did not produce ten adjacent people per team", "team_id": team.team_id, "count": front_count}
	return {"ok": checked.size() == 20, "code": "OK", "checked": checked, "source_items_moved": 0}

func _source_profile() -> Dictionary:
	if TerrainArmy._contact_source == null:
		return {}
	var profile: Dictionary = TerrainArmy._contact_source.profile_usec
	return profile.duplicate()

func _source_profile_delta() -> Dictionary:
	var result := _source_profile()
	var baseline: Dictionary = measurements.get("source_profile_at_measurement_start", {})
	for key: String in result:
		result[key] = int(result[key]) - int(baseline.get(key, 0))
	return result

func _compiled_source_profile() -> Dictionary:
	if TerrainArmy._contact_source == null:
		return {}
	var profile: Dictionary = TerrainArmy._contact_source.compiled_geometry_profile
	return profile.duplicate(true)

func _compiled_source_profile_delta() -> Dictionary:
	if not measurements.has("compiled_geometry_profile_at_measurement_start"):
		return {} # Setup failure is not a measured candidate workload.
	var result := _compiled_source_profile()
	var baseline: Dictionary = measurements.compiled_geometry_profile_at_measurement_start
	for field: String in result:
		if field == "fallbacks":
			var reasons: Dictionary = result[field]
			var before: Dictionary = baseline.get(field, {})
			for reason: String in reasons:
				reasons[reason] = int(reasons[reason]) - int(before.get(reason, 0))
		else:
			result[field] = int(result[field]) - int(baseline.get(field, 0))
	return result

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_finish_realtime("GPU required: headless cannot exercise both original female live geometry owners or presentation pacing", false)
		return
	root.size = Vector2i(1400, 900)
	root.content_scale_size = root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	assert(is_equal_approx(Engine.time_scale, 1.0), "Do not accelerate or slow the original simulation clock")
	_realtime_lab = RealtimeLab.new()
	var lab: RealtimeLab = _realtime_lab
	lab.pause_when_unfocused = false
	lab.fixed_action_steps_enabled = _fixed120
	lab.fatigue_zero_fast_path_enabled = _fatigue_zero
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false) # Setup/render-only warmup; enabled once below.
	lab.site_controller._auto_save_blocked = true # Isolated fixture must not write a real player save.
	var data: TerrainData = TerrainGenerator.generate(0, 581)
	Env.initialize(data, "army-combat-realtime-fixture")
	# Identical flat fixture semantics to longrun, including sparse resource
	# clearing so the real clock cannot restore obstacles at a minute boundary.
	for key: String in data.resource_base:
		Env.change(data, key, {"cleared": true, "remaining": 0})
	Env.rebuild_indexes(data)
	for index: int in data.surface_types.size():
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
		data.surface_types[index] = TerrainData.Surface.GRASS
	data.ramp_edges.fill(0)
	lab.bind_terrain(data)
	lab.site_controller.release_worker()
	assert(lab.character.place(Vector2i(50, 50), true) and lab.npc.place(Vector2i(52, 50), true))
	var deployed: Dictionary = lab.start_melee_trial()
	if not deployed.ok:
		_setup_unavailable(str(deployed.code), str(deployed.message), deployed)
		return
	assert(TerrainArmy._contact_source != null)
	TerrainArmy._contact_source.same_batch_result_reuse_enabled = _pose_result_reuse
	TerrainArmy._contact_source.compiled_geometry_enabled = _compiled_source
	TerrainArmy._contact_source.compiled_geometry_shadow_enabled = false
	TerrainArmy._contact_source.editor.set("recipe_refresh_batch_enabled", _recipe_refresh)
	for geometry: RefCounted in _redundant_work_instances(lab):
		geometry.weapon_mesh_filter_enabled = _weapon_mesh_filter
		geometry.skinning_profile_enabled = _skinning_profile
	for team: TerrainArmy in lab.combat_armies:
		assert(team.visual_mode() == "baked_atlas" and team.active_3d_source_count() == 1)
		for body: Dictionary in team.combat_units:
			assert(float(body.hp) == 100.0 and float(body.stun) == 0.0 and float(body.ko) == 0.0)
			assert(not _original_rows.has(int(body.person_id)))
			_original_rows[int(body.person_id)] = body
		assert(team._unit_editor(0) != null and team._unit_editor(0)._body_index == 1)
		assert(not team.combat_shapes(0, "body").is_empty() and not team.combat_shapes(1, "body").is_empty())
		team.set_process(true) # Original Army._process renders; Lab alone advances combat.
	assert(_original_rows.size() == 200)
	assert(TerrainArmy._contact_source.editor.preview_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	TerrainArmy._contact_source.cheap_query_bounds_enabled = _cheap_bounds
	TerrainArmy._contact_source.centered_query_bounds_enabled = _centered_bounds
	_original_inventory = _inventory(lab)
	assert((_original_inventory.items as Dictionary).size() == 1018)
	measurements.initial_loadout_transfers = []
	if not _baseline_equipment:
		var preflight: Dictionary = _preflight_mixed_equipment(lab)
		measurements.mixed_equipment_preflight = preflight
		if not preflight.ok:
			_setup_unavailable(str(preflight.code), str(preflight.message), preflight)
			return
		measurements.initial_loadout_transfers = _prepare_mixed_equipment(lab)
		if measurements.initial_loadout_transfers.size() != 20 or _inventory(lab) != _original_inventory:
			_setup_unavailable("MIXED_SETUP_FAILED", "Mixed fixture did not complete its 20 original-person/40 original-item transfers with conservation")
			return
	if _coarse_proxy:
		_proxy = CoarseProxy.new()
		assert(_proxy.load_profile(), "Coarse profile must exist and match original offline sources")
		for team: TerrainArmy in lab.combat_armies:
			team.combat_proxy = _proxy
		for actor: TerrainTestCharacter in lab.combat_actors:
			actor.combat_proxy = _proxy
			actor._geometry = _proxy
		_proxy.weapon_mesh_filter_enabled = _weapon_mesh_filter
		_proxy.skinning_profile_enabled = _skinning_profile
		measurements.coarse_proxy_sources = _proxy.profile_sources.duplicate()
	_initial_site_seconds = Runtime.now(data) * 60.0
	lab.site_controller._capture_positions()
	_baseline_path = output_path + "/before_battle.json"
	var initial_save: Dictionary = Store.save(data, _baseline_path)
	if not initial_save.ok:
		_setup_unavailable(str(initial_save.code), str(initial_save.message), initial_save)
		return
	_baseline_hash = FileAccess.get_sha256(_baseline_path)
	lab.character.set_process(true)
	lab.npc.set_process(true)
	assert(lab.character.combat_driven_by_lab and lab.npc.combat_driven_by_lab)
	# SiteController intentionally hides the optional TerrainLab debug panel
	# when constructing the normal Site HUD. Do not require or force debug UI.
	measurements.initial_ui_visibility = {"site_hud": lab.get_node("SiteUI").visible,
		"optional_debug_panel": lab.get_node("TerrainLabUI").visible}
	if not lab.get_node("SiteUI").visible:
		_setup_unavailable("HUD_HIDDEN", "The original normal Site HUD must remain visible")
		return
	lab.camera.zoom = Vector2.ONE * 0.85
	# Automated A/B owns its camera; normal game input remains untouched.
	# Keep the original visible HUD, but do not let wheel/drag/key input alter
	# this benchmark's camera or issue manual combat orders during measurement.
	lab.set_process_unhandled_input(false)
	_measurement_camera_position = lab.camera.position
	_measurement_camera_zoom = lab.camera.zoom
	_measurement_window_size = root.size
	measurements.camera_at_setup = {"position": [_measurement_camera_position.x, _measurement_camera_position.y],
		"zoom": [_measurement_camera_zoom.x, _measurement_camera_zoom.y], "manual_lab_input_enabled": false}
	lab._update_info()
	measurements.setup_ms = (Time.get_ticks_usec() - started_us) / 1000.0
	measurements.status = "render_only_warmup"
	measurements.display_configuration = {"window_pixels": [root.size.x, root.size.y],
		"content_scale_pixels": [root.content_scale_size.x, root.content_scale_size.y],
		"vsync": "disabled", "actual_vsync_mode": DisplayServer.window_get_vsync_mode(),
		"engine_max_fps": Engine.max_fps, "engine_time_scale": Engine.time_scale,
		"gpu": RenderingServer.get_video_adapter_name(), "cpu": OS.get_processor_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "driver": ProjectSettings.get_setting("rendering/rendering_device/driver.windows")}
	_write()
	var warmup_started := Time.get_ticks_usec()
	var warmup_frames := 0
	while Time.get_ticks_usec() - warmup_started < int(WARMUP_WALL_SECONDS * 1000000.0):
		await process_frame
		await RenderingServer.frame_post_draw
		if _finished:
			return
		warmup_frames += 1
	measurements.warmup = {"wall_seconds": (Time.get_ticks_usec() - warmup_started) / 1000000.0,
		"rendered_frames": warmup_frames, "action_seconds": lab.action_seconds,
		"simulation_suspended": true, "note": "Atlas/live presenters warm up naturally; no combat or manual fast-forward is hidden in warmup"}
	assert(lab.action_seconds == 0.0 and _inventory(lab) == _original_inventory)
	assert(root.get_texture().get_image().save_png(output_path + "/01_before.png") == OK)
	measurements.nodes_before = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	measurements.memory_before_bytes = OS.get_static_memory_usage()
	measurements.status = "measuring"
	_write()
	# Consume the screenshot/report frame while simulation is still stopped;
	# its setup-only disk cost must not enter the first accepted combat delta.
	await process_frame
	await RenderingServer.frame_post_draw
	if _finished:
		return
	measurements.source_profile_at_measurement_start = _source_profile()
	_proxy_source_start = int(TerrainArmy._contact_source.query_profile.sample_calls)
	measurements.compiled_geometry_profile_at_measurement_start = _compiled_source_profile()
	assert(_redundant_work_flags_match(lab))
	measurements.redundant_work_instances_verified_before = _redundant_work_instances(lab).size()
	for geometry: RefCounted in _redundant_work_instances(lab):
		for field: String in geometry.skinning_profile:
			geometry.skinning_profile[field] = 0
	if TerrainArmy._contact_source != null:
		TerrainArmy._contact_source.editor.set("select_profile_enabled", true)
	for team: TerrainArmy in lab.combat_armies:
		for field: String in team.combat_geometry_profile:
			team.combat_geometry_profile[field] = 0
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.combat_pose_profile_enabled = true
		for field: String in actor.combat_pose_profile_usec:
			actor.combat_pose_profile_usec[field] = 0
	if _script_profile:
		EngineDebugger.profiler_enable(&"scripts", true)
	_measurement_started_us = Time.get_ticks_usec()
	lab.camera.position = _measurement_camera_position
	lab.camera.zoom = _measurement_camera_zoom
	lab.camera.force_update_scroll()
	_previous_draw_us = _measurement_started_us
	lab.recording = true
	lab.gpu_batch_profile_enabled = _gpu_batch_profile
	lab.combat_profile_enabled = _stage_profile
	lab.contact_input_reuse_enabled = _contact_inputs
	lab.contact_buckets_enabled = _contact_buckets
	lab.contact_candidate_profile_enabled = _bucket_profile
	lab.bucket_trace_enabled = _bucket_profile
	lab.bucket_trace_start = _measurement_started_us
	lab.set_process(true)
	var next_checkpoint := 10.0
	while not _finished:
		await process_frame
		await RenderingServer.frame_post_draw
		if _finished:
			return
		var now := Time.get_ticks_usec()
		_record_draw(now)
		var wall_seconds := (now - _measurement_started_us) / 1000000.0
		if wall_seconds >= next_checkpoint:
			var checkpoint := _checkpoint(wall_seconds)
			measurements.checkpoints.append(checkpoint)
			print("SITE_ARMY_COMBAT_REALTIME_PROGRESS ", JSON.stringify(checkpoint))
			# Retain compact progress, not the growing per-frame arrays, during
			# measurement. Its real cost is included in the next draw interval.
			_write()
			next_checkpoint = (floorf(wall_seconds / 10.0) + 1.0) * 10.0
		if wall_seconds >= _measurement_target:
			_finish_realtime("measurement_window_complete", true)
			return

func _record_draw(now: int) -> void:
	_measurement_view_changed = _measurement_view_changed or _realtime_lab.camera.position != _measurement_camera_position or _realtime_lab.camera.zoom != _measurement_camera_zoom or root.size != _measurement_window_size
	_draw_intervals_ms.append((now - _previous_draw_us) / 1000.0)
	_draw_elapsed_seconds.append((now - _measurement_started_us) / 1000000.0)
	_draw_lab_cpu_ms.append((_realtime_lab.process_cpu_us - _last_draw_cpu_us) / 1000.0)
	_engine_process_ms.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
	_previous_draw_us = now
	_last_draw_cpu_us = _realtime_lab.process_cpu_us

func _checkpoint(wall_seconds: float) -> Dictionary:
	var lab: RealtimeLab = _realtime_lab
	var result := _life(lab)
	var moving := 0
	var formations := []
	for team: TerrainArmy in lab.combat_armies:
		moving += team.moving_count()
		formations.append({"team_id": team.team_id, "mode": team.formation_mode_name(),
			"formed": team.formation_count(), "completed_original_steps": team.completed_steps()})
	result.merge({"wall_seconds": wall_seconds, "presented_frames": _draw_intervals_ms.size(),
		"fps_so_far": _draw_intervals_ms.size() / wall_seconds, "action_seconds": lab.action_seconds,
		"input_seconds": lab.input_seconds, "input_minus_action_seconds": lab.input_seconds - lab.consumed_action_seconds,
		"delta_wall_ratio": lab.input_seconds / wall_seconds, "longest_combat_streak_seconds": lab.longest_combat_streak,
		"effective_hit_events": lab.effective_hit_events, "moving": moving, "formations": formations,
		"shared_source_profile_usec": _source_profile(), "measurement_source_profile_usec": _source_profile_delta(),
		"phase": "initial_contact" if wall_seconds <= 10.5 else "later_original_battle_and_natural_reposition"})
	# Read existing counters at the original ten-second checkpoints only. This
	# separates natural late-battle pose work without adding per-person logging.
	result["original_lab_combat_stage_usec"] = lab.combat_profile_usec.duplicate()
	if _bucket_profile:
		result["contact_candidate_profile"] = lab.contact_candidate_profile.duplicate()
	result["shared_steps"] = lab.shared_steps
	result["source_query_profile"] = TerrainArmy._contact_source.query_profile.duplicate()
	result["recipe_refresh_profile"] = TerrainArmy._contact_source.editor.get("recipe_refresh_profile").duplicate()
	result["source_pose_clip_profile"] = TerrainArmy._contact_source.pose_clip_profile.duplicate()
	result["source_constant_morph_keys_enabled"] = TerrainArmy._contact_source.constant_morph_keys_enabled
	result["source_cape_track_omission_enabled"] = TerrainArmy._contact_source.cape_track_omission_enabled
	result["source_nonattack_bounds_enabled"] = TerrainArmy._contact_source.conservative_nonattack_bounds_enabled
	result["source_cheap_query_bounds_enabled"] = TerrainArmy._contact_source.cheap_query_bounds_enabled
	result["source_centered_query_bounds_enabled"] = TerrainArmy._contact_source.centered_query_bounds_enabled
	result["fatigue_zero_counts"] = {"eligible_rows": lab.fatigue_zero_eligible_rows, "skipped_advances": lab.fatigue_zero_skipped_advances}
	result["source_nonattack_bound"] = TerrainArmy._contact_source._nonattack_bound.duplicate(true)
	result["army_geometry_profiles"] = []
	for team: TerrainArmy in lab.combat_armies:
		result.army_geometry_profiles.append(team.combat_geometry_profile.duplicate())
	return result

func _percentile(samples: Array[float], quantile: float) -> float:
	if samples.is_empty():
		return 0.0
	var ordered: Array[float] = samples.duplicate()
	ordered.sort()
	return ordered[clampi(ceili(ordered.size() * quantile) - 1, 0, ordered.size() - 1)]

func _sample_summary(samples: Array[float]) -> Dictionary:
	var total := 0.0
	var largest := 0.0
	for value: float in samples:
		total += value
		largest = maxf(largest, value)
	return {"count": samples.size(), "mean_ms": total / maxi(1, samples.size()),
		"p50_ms": _percentile(samples, 0.5), "p95_ms": _percentile(samples, 0.95),
		"p99_ms": _percentile(samples, 0.99), "max_ms": largest}

func _ten_second_bins(wall_seconds: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in ceili(wall_seconds / 10.0):
		var exposure := minf(10.0, wall_seconds - index * 10.0)
		result.append({"start_wall_seconds": index * 10.0, "end_wall_seconds": minf(wall_seconds, (index + 1) * 10.0),
			"wall_seconds": exposure, "complete_ten_seconds": exposure >= 10.0 - 0.000001,
			"presented_frames": 0, "fps": 0.0, "frame_intervals_ms": []})
	for index: int in _draw_elapsed_seconds.size():
		# A frame is counted where it really finishes. A stall crossing one or
		# more bins leaves those bins empty; it is not divided into fake frames.
		var bucket := clampi(floori((_draw_elapsed_seconds[index] - 0.000000001) / 10.0), 0, result.size() - 1)
		result[bucket].presented_frames += 1
		result[bucket].frame_intervals_ms.append(_draw_intervals_ms[index])
	for bucket: Dictionary in result:
		bucket.fps = int(bucket.presented_frames) / maxf(0.000001, float(bucket.wall_seconds))
		var intervals: Array[float] = []
		intervals.assign(bucket.frame_intervals_ms)
		bucket.frame_statistics = _sample_summary(intervals)
		bucket.erase("frame_intervals_ms")
	return result

func _finish_realtime(reason: String, completed: bool) -> void:
	if _finished:
		return
	_finished = true
	measurements.status = reason
	measurements.measurement_complete = completed
	measurements.targets_met = false # Assigned explicitly; never Dictionary.merge a pre-existing false flag.
	measurements.total_wall_seconds = (Time.get_ticks_usec() - started_us) / 1000000.0
	measurements.shared_source_profile_usec = _source_profile()
	if TerrainArmy._contact_source != null:
		measurements.compiled_geometry_profile = _compiled_source_profile()
		measurements.measurement_compiled_geometry_profile = _compiled_source_profile_delta()
		measurements.source_query_profile = TerrainArmy._contact_source.query_profile.duplicate()
		measurements.recipe_refresh_profile = TerrainArmy._contact_source.editor.get("recipe_refresh_profile").duplicate()
		measurements.source_pose_clip_profile = TerrainArmy._contact_source.pose_clip_profile.duplicate()
		measurements.source_held_state_profile = TerrainArmy._contact_source.editor.get("held_state_profile").duplicate()
		measurements.source_assigned_playback_enabled = TerrainArmy._contact_source.editor.get("paused_assigned_playback_enabled")
		measurements.source_assigned_playback_profile = TerrainArmy._contact_source.editor.get("assigned_playback_profile").duplicate()
		measurements.source_select_profile_usec = TerrainArmy._contact_source.editor.get("select_profile_usec").duplicate()
	if is_instance_valid(_realtime_lab):
		measurements.army_geometry_profiles = []
		for team: TerrainArmy in _realtime_lab.combat_armies:
			measurements.army_geometry_profiles.append({"team_id": team.team_id,
				"measurement_counters": team.combat_geometry_profile.duplicate()})
	if not is_instance_valid(_realtime_lab) or _measurement_started_us == 0:
		var unavailable: Dictionary = measurements.get("unavailable", {})
		measurements.reason = str(unavailable.get("message", "No complete measured GPU window; setup/warmup/deadline is not performance evidence"))
		_write()
		print("SITE_ARMY_COMBAT_REALTIME_UNAVAILABLE ", JSON.stringify(measurements))
		if is_instance_valid(_realtime_lab):
			_realtime_lab.free()
			TerrainArmy.release_contact_source()
		quit(1)
		return
	var lab: RealtimeLab = _realtime_lab
	var native_processing: bool = lab.is_processing() and lab.character.is_processing() and lab.npc.is_processing()
	for team: TerrainArmy in lab.combat_armies:
		native_processing = native_processing and team.is_processing()
	lab.recording = false
	lab.set_process(false) # Measurement ended; no manual remainder settlement.
	measurements.redundant_work_flags_verified_after = _redundant_work_flags_match(lab)
	assert(measurements.redundant_work_flags_verified_after)
	var wall_seconds := (_previous_draw_us - _measurement_started_us) / 1000000.0
	var frame_stats := _sample_summary(_draw_intervals_ms)
	var bins := _ten_second_bins(wall_seconds)
	var all_full_bins_fast := true
	var full_bin_count := 0
	for bucket: Dictionary in bins:
		if bool(bucket.complete_ten_seconds):
			full_bin_count += 1
			all_full_bins_fast = all_full_bins_fast and float(bucket.fps) >= TARGET_FPS
	var final_life := _life(lab)
	var identity_preserved: bool = int(final_life.actual_rows) == 200
	for team: TerrainArmy in lab.combat_armies:
		for body: Dictionary in team.combat_units:
			identity_preserved = identity_preserved and _original_rows.has(int(body.person_id)) and is_same(body, _original_rows.get(int(body.person_id)))
	var inventory_conserved: bool = _inventory(lab) == _original_inventory
	lab.site_controller._capture_positions()
	var item_validation: Dictionary = Store._validate_items(lab.terrain, lab.terrain.site)
	var save_guard: Dictionary = lab.site_controller.supply_save_guard()
	var save_result := {"ok": false, "code": "NOT_BUSY", "message": "Battle no longer active; safe initial snapshot left untouched"}
	if float(lab.terrain.site.get("combat_left", 0.0)) > 0.0:
		save_result = Store.save(lab.terrain, _baseline_path) if save_guard.ok else save_guard
	var safe_busy: bool = not bool(save_result.ok) and str(save_result.code) == "BUSY" and FileAccess.get_sha256(_baseline_path) == _baseline_hash
	var fps := _draw_intervals_ms.size() / maxf(wall_seconds, 0.000001)
	var ratio := lab.input_seconds / maxf(wall_seconds, 0.000001)
	var nodes_after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var debt_limit := TerrainLab.ACTION_STEP + DEBT_EPSILON_SECONDS if _fixed120 else DEBT_EPSILON_SECONDS
	var accounted_debt := absf(lab.input_seconds - lab.consumed_action_seconds - lab._action_time_remainder)
	var flags := {
		"completed_60_wall_seconds": completed and not _short_diagnostic and wall_seconds >= MEASURE_WALL_SECONDS,
		"required_mixed_equipment_fixture": not _baseline_equipment and measurements.initial_loadout_transfers.size() == 20,
		"fps_at_least_30": fps >= TARGET_FPS,
		"p95_at_most_33_334_ms": not _draw_intervals_ms.is_empty() and float(frame_stats.p95_ms) <= TARGET_P95_MS,
		"all_six_complete_ten_second_bins_at_least_30_fps": full_bin_count >= 6 and all_full_bins_fast,
		"no_stall_over_one_second": not _draw_intervals_ms.is_empty() and float(frame_stats.max_ms) <= MAX_STALL_MS,
		"input_tracks_wall_time": ratio > 0.95 and ratio <= 1.05,
		"no_simulation_time_debt": lab.maximum_abs_debt <= debt_limit and lab.maximum_frame_debt <= debt_limit and accounted_debt <= DEBT_EPSILON_SECONDS,
		"no_unexpected_pause": lab.unexpected_paused_frames == 0,
		"camera_and_window_unchanged": not _measurement_view_changed,
		"native_lab_actor_army_processing_enabled": native_processing,
		"continuous_combat_at_least_55_seconds": lab.longest_combat_streak >= MIN_COMBAT_SECONDS,
		"effective_original_hit_observed": lab.effective_hit_events > 0,
		"original_200_row_identity_preserved": identity_preserved,
		"original_1018_items_and_cargo_conserved": inventory_conserved and lab.terrain.site.item_records.size() == 1018 and bool(item_validation.ok),
		"no_node_growth": nodes_after == int(measurements.nodes_before),
		"active_battle_preserves_safe_save_BUSY": safe_busy,
		"production_hud_still_visible": lab.get_node("SiteUI").visible and lab.get_node("TerrainLabUI").visible == bool(measurements.initial_ui_visibility.optional_debug_panel),
		"source_fingerprints_unchanged": _source_fingerprints() == measurements.source_fingerprints,
	}
	var passed := true
	for value: bool in flags.values():
		passed = passed and value
	measurements.targets_met = passed
	if _coarse_proxy:
		measurements.coarse_proxy_performance_targets_met = passed
		measurements.targets_met = false # Changed collision policy is not original-contract acceptance.
	measurements.full_acceptance_window = bool(flags.completed_60_wall_seconds) and bool(flags.required_mixed_equipment_fixture)
	measurements.flags = flags
	measurements.reason = "All actual realtime 200-person thresholds met" if passed else "Measurement retained without a weakened PASS; inspect each failed flag. Short mode and baseline-equipment mode are never full mixed-equipment acceptance."
	measurements.wall_seconds = wall_seconds
	measurements.fps = fps
	measurements.frame_statistics = frame_stats
	measurements.lab_process_cpu_statistics = _sample_summary(_draw_lab_cpu_ms)
	measurements.engine_reported_process_statistics = _sample_summary(_engine_process_ms)
	measurements.ten_second_bins = bins
	measurements.preferred_60_fps = passed and fps >= 60.0 and float(frame_stats.p95_ms) <= 16.667
	measurements.native_process_calls = lab.raw_input_deltas.size()
	measurements.presented_frames = _draw_intervals_ms.size()
	measurements.input_seconds = lab.input_seconds
	measurements.action_seconds = lab.action_seconds
	measurements.input_minus_action_seconds = lab.input_seconds - lab.consumed_action_seconds
	measurements.maximum_abs_debt_seconds = lab.maximum_abs_debt
	measurements.maximum_per_frame_debt_seconds = lab.maximum_frame_debt
	measurements.retained_action_fraction_seconds = lab._action_time_remainder
	measurements.unaccounted_action_seconds = accounted_debt
	measurements.allowed_action_fraction_seconds = debt_limit
	measurements.input_wall_ratio = ratio
	measurements.action_wall_ratio = lab.consumed_action_seconds / maxf(wall_seconds, 0.000001)
	measurements.game_seconds = Runtime.now(lab.terrain) * 60.0 - _initial_site_seconds
	measurements.combat_seconds = lab.combat_seconds
	measurements.longest_combat_streak_seconds = lab.longest_combat_streak
	measurements.shared_steps = lab.shared_steps
	measurements.full_clock_cpu_ms = lab.process_cpu_us / 1000.0
	measurements.lab_stage_usec = lab.stage_usec.duplicate()
	measurements.original_step_pose_demand = {"steps": lab.pose_demand_steps, "native_pose_evaluations": lab.pose_demand_total,
		"native_pose_count_histogram": lab.pose_demand_histogram.duplicate(), "end_step_cached_pose_histogram": lab.cached_pose_histogram.duplicate(),
		"scope": "Read-only counts per original common step. Counts include original pose restores; cached poses exclude terminal-only returns and may have been cleared at capacity. Neither proves queries can be reordered/batched or all use the same GPU surface. No GPU dispatch or scheduling changes."}
	if _gpu_batch_profile:
		var counted_steps := 0
		var counted_poses := 0
		for demand: int in lab.pose_demand_histogram:
			counted_steps += int(lab.pose_demand_histogram[demand])
			counted_poses += demand * int(lab.pose_demand_histogram[demand])
		assert(counted_steps == lab.pose_demand_steps and counted_steps == lab.shared_steps and counted_poses == lab.pose_demand_total)
	measurements.skinning_profiles = []
	for geometry: RefCounted in _redundant_work_instances(lab):
		measurements.skinning_profiles.append(geometry.skinning_profile.duplicate())
	measurements.original_lab_combat_stage_usec = lab.combat_profile_usec.duplicate()
	measurements.contact_candidate_profile = lab.contact_candidate_profile.duplicate()
	assert(lab.contact_buckets_enabled == _contact_buckets)
	if _bucket_profile and _contact_buckets:
		assert(int(lab.contact_candidate_profile.bucket_builds) > 0 and int(lab.contact_candidate_profile.rows_visited) < int(lab.contact_candidate_profile.rows_before))
	measurements.fatigue_zero_counts = {"eligible_rows": lab.fatigue_zero_eligible_rows, "skipped_advances": lab.fatigue_zero_skipped_advances}
	measurements.actor_pose_profiles = []
	for actor: TerrainTestCharacter in lab.combat_actors:
		measurements.actor_pose_profiles.append({"person_id": actor.person_id, "profile_usec": actor.combat_pose_profile_usec.duplicate()})
	measurements.lab_stage_note = "Nested observer timings, not additive. action_step includes fatigue, army contacts, resolution and sorting; full clock minus action_step includes original SiteController.tick and end-of-frame UI."
	measurements.contact_cpu_ms = lab.contact_cpu_us / 1000.0
	measurements.measurement_source_profile_usec = _source_profile_delta()
	if _coarse_proxy:
		measurements.coarse_proxy_profile = {"samples": _proxy.samples, "cache_hits": _proxy.cache_hits,
			"unsupported": _proxy.unsupported, "native_source_samples_during_measurement": int(TerrainArmy._contact_source.query_profile.sample_calls) - _proxy_source_start,
			"production_accepted": false}
		assert(int(_proxy.unsupported) == 0 and int(TerrainArmy._contact_source.query_profile.sample_calls) == _proxy_source_start,
			"No unsupported shape or hidden native Source sampling in the coarse trial")
	# Ended measurement only: actual keys from the final completed contact step,
	# not a per-query trace or a claim that this sample represents the whole run.
	measurements.final_step_source_sample_inputs = TerrainArmy._contact_source._poses.keys().duplicate(true)
	measurements.contact_queries = lab.contact_queries
	measurements.resolved_packets = lab.resolved_packets
	measurements.effective_hit_events = lab.effective_hit_events
	measurements.returned_contact_kinds = lab.returned_contact_kinds
	measurements.queued_result_kinds = lab.queued_result_kinds
	measurements.unique_injured = lab.injured.size()
	measurements.unique_ko = lab.knocked_out.size()
	measurements.unique_deaths_from_contact = lab.died_from_contact.size()
	measurements.final_life = final_life
	measurements.natural_terminal = _natural_terminal(lab)
	measurements.items = lab.terrain.site.item_records.size()
	measurements.containers = lab.terrain.site.ground_loot.size()
	measurements.pending_original_deaths = lab.site_controller._pending_deaths.size()
	measurements.item_conservation = inventory_conserved
	measurements.save_result = save_result
	measurements.safe_snapshot_sha256 = _baseline_hash
	measurements.nodes_after = nodes_after
	measurements.camera_at_end = {"position": [lab.camera.position.x, lab.camera.position.y],
		"zoom": [lab.camera.zoom.x, lab.camera.zoom.y], "changed_during_measurement": _measurement_view_changed}
	measurements.memory_after_bytes = OS.get_static_memory_usage()
	measurements.raw_samples = {"draw_elapsed_seconds": _draw_elapsed_seconds, "draw_intervals_ms": _draw_intervals_ms,
		"lab_cpu_between_draws_ms": _draw_lab_cpu_ms, "engine_reported_process_ms": _engine_process_ms,
		"native_input_deltas": Array(lab.raw_input_deltas), "native_action_deltas": Array(lab.raw_action_deltas),
		"native_lab_process_cpu_ms": Array(lab.raw_process_cpu_ms)}
	measurements.replay_note = "Recorded native input deltas permit a separate identical-delta A/B correctness replay. This test does not substitute a manual replay's throughput for FPS or claim different native jitter sequences have identical packets."
	measurements.final_capture_error = root.get_texture().get_image().save_png(output_path + "/02_final.png")
	if _bucket_profile and not _short_diagnostic:
		measurements.bucket_tail_replay = _verify_bucket_tail(lab)
	if _script_profile and EngineDebugger.is_profiling(&"scripts"):
		# Snapshot before lab.free releases function profiling records. Native
		# super-call wrappers can double-count self time; don't add them as CPU.
		print("SITE_SCRIPT_PROFILE_ACCUMULATED_BEGIN")
		EngineDebugger.profiler_enable(&"scripts", false)
		print("SITE_SCRIPT_PROFILE_ACCUMULATED_END")
	_write()
	print("SITE_ARMY_COMBAT_REALTIME_TARGETS_MET " if passed else "SITE_ARMY_COMBAT_REALTIME_TARGETS_NOT_MET ",
		JSON.stringify({"output": output_path, "measurement_complete": completed, "targets_met": passed,
			"wall_seconds": wall_seconds, "fps": fps, "p95_ms": frame_stats.p95_ms, "flags": flags}))
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0 if completed else 1)

func _bucket_replay_pass(entries: Array, indexed: bool, verify: bool) -> Dictionary:
	var visited := 0
	var passed := 0
	var queries := 0
	var started := Time.get_ticks_usec()
	for entry: Dictionary in entries:
		var grounds: Array[Vector2] = entry.grounds
		var buckets := TerrainLab._build_contact_buckets(grounds) if indexed else {}
		for query: Dictionary in entry.queries:
			queries += 1
			var candidates: Array = TerrainLab._contact_bucket_candidates(query.bounds, grounds, buckets) if indexed else range(grounds.size())
			visited += candidates.size()
			var selected: Array[int] = []
			for index: int in candidates:
				if index != int(query.source_unit) and (index == 0 or (query.bounds as Rect2).has_point(grounds[index])):
					selected.append(index)
			passed += selected.size()
			if verify:
				var expected: Array[int] = []
				for index in grounds.size():
					if index != int(query.source_unit) and (index == 0 or (query.bounds as Rect2).has_point(grounds[index])):
						expected.append(index)
				assert(selected == expected, "Tail replay candidate completeness/order changed")
	return {"usec": Time.get_ticks_usec() - started, "queries": queries, "rows_visited": visited, "anchor_passed": passed}

func _verify_bucket_tail(lab: RealtimeLab) -> Dictionary:
	assert(lab.bucket_trace_steps.size() == 16, "Expected 16 actual original tail steps")
	var entries := lab.bucket_trace.values()
	var artifact := FileAccess.open_compressed(output_path + "/bucket_tail_inputs.bin", FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	assert(artifact != null)
	artifact.store_var({"sources": measurements.source_fingerprints, "steps": lab.bucket_trace_steps.keys(), "batches": entries}, false)
	artifact.close()
	var verified := _bucket_replay_pass(entries, true, true)
	# Same captured inputs; three alternating pairs include per-step index build
	# and result sorting. Not a full contact/HP replay and not an FPS estimate.
	var original: Array = []
	var indexed: Array = []
	for iteration in 3:
		if iteration % 2 == 0:
			original.append(_bucket_replay_pass(entries, false, false))
			indexed.append(_bucket_replay_pass(entries, true, false))
		else:
			indexed.append(_bucket_replay_pass(entries, true, false))
			original.append(_bucket_replay_pass(entries, false, false))
	return {"steps": lab.bucket_trace_steps.size(), "batches": entries.size(), "verified_queries": verified.queries,
		"original": original, "indexed": indexed, "artifact": "bucket_tail_inputs.bin",
		"scope": "Same real tail anchors/sweeps, exact candidate/order comparison; timing includes index builds/sort, not geometry or full combat. Capture cost included in FPS; replay runs after measurement."}
