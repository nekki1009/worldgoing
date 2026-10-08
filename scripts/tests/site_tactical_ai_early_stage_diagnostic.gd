extends "res://scripts/tests/site_tactical_ai_formal_visual_test.gd"
## One bounded formal-entry probe: early MOVE stage deltas and fixture observer cost.

const DIAG_OUT := "res://output/site_movement_root_cause_20260928/early_stage"
const R3_OUT := "res://output/site_movement_plan_revision3_20260928/implementation/r0"
const LIMIT_SECONDS := 30.0
const R3_SOURCES := ["res://scripts/terrain_lab/terrain_lab.gd", "res://scripts/terrain_lab/terrain_army.gd",
	"res://scripts/terrain_lab/terrain_test_character.gd", "res://scripts/terrain_lab/terrain_renderer.gd",
	"res://scripts/ui/human_character_3d_editor.gd",
	"res://scripts/tests/site_tactical_ai_early_stage_diagnostic.gd",
	"res://native/army_idle/bin/army_idle.windows.x86_64.dll"]

var _observer_usec := 0
var _snapshot_usec := 0
var _next_mark := 10.0
var _records: Array[Dictionary] = []
var _limit_seconds := 10.0 if "--batch-coverage10" in OS.get_cmdline_user_args() else LIMIT_SECONDS
var _r3 := "--r3-diagnostic" in OS.get_cmdline_user_args()
var _r3_frames: Array[Dictionary] = []
var _r3_viewports: Array[Dictionary] = []
var _r3_prior: Dictionary = {}
var _r3_previous_usec := 0
var _r3_source_before: Dictionary = {}
var _r3_pre_draw_modes: Dictionary = {}
var _r3_started := false
var _r3_previous_action := 0.0
var _r3_probe_usec := 0

func _initialize() -> void:
	super._initialize()
	output = "%s/run_%d_%d" % [R3_OUT if _r3 else DIAG_OUT,
		int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	if _r3:
		_r3_source_before = _r3_source_hashes()

func _r3_source_hashes() -> Dictionary:
	var hashes := {}
	for path: String in R3_SOURCES:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _r3_add_viewport(viewport: Viewport, role: String) -> void:
	if viewport == null:
		return
	for item: Dictionary in _r3_viewports:
		if item.viewport == viewport:
			item.roles.append(role)
			return
	var rid := viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var extent := viewport.get_visible_rect().size
	_r3_viewports.append({"viewport": viewport, "rid": rid, "path": str(viewport.get_path()),
		"roles": [role], "size": [extent.x, extent.y]})

func _r3_start() -> void:
	_r3_add_viewport(root, "main")
	for side in range(lab.combat_armies.size()):
		var team: TerrainArmy = lab.combat_armies[side]
		for index in range(team.combat_units.size()):
			if not team._uses_live_presenter(index):
				continue
			var presenter: HumanCharacter3DEditor = team._unit_editor(index)
			if presenter != null:
				_r3_add_viewport(presenter.preview_viewport, "army_%d_live_%d" % [side, index])
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.combat_pose_profile_enabled = true
		actor.combat_pose_profile_usec.clear()
		if actor.editor != null:
			_r3_add_viewport(actor.editor.preview_viewport, "actor_%d" % actor.person_id)
	lab.renderer.r3_render_profile_enabled = true
	lab.renderer.r3_render_process_usec = 0
	lab.renderer.r3_render_process_calls = 0
	_r3_prior = _r3_counters()
	_r3_previous_usec = Time.get_ticks_usec()
	_r3_previous_action = lab._exchange_round * TerrainLab.EXCHANGE_QUERY_STEP + lab._exchange_phase
	RenderingServer.frame_pre_draw.connect(_r3_before_draw)
	RenderingServer.frame_post_draw.connect(_r3_after_draw)

func _r3_counters() -> Dictionary:
	var result := {}
	for key: String in ["process_total", "process_input", "action_outer", "finish_tick_outer",
		"retaliation_outer", "update_info_outer", "site_tick", "movement_input",
		"navigation_and_team_prepare", "actors_advance", "actors_sample", "teams_sample",
		"resolve", "settle_life_orders_family", "movement_coordinator"]:
		result["lab_" + key] = int(lab.combat_profile_usec.get(key, 0))
	result["army_render_total"] = 0
	result["army_live_presenter"] = 0
	result["army_live_editor"] = 0
	result["army_live_calls"] = 0
	result["army_native_frames"] = 0
	for team: TerrainArmy in lab.combat_armies:
		result.army_render_total += team.combat_render_usec
		result.army_live_presenter += int(team.combat_profile_usec.get("render_live_presenter", 0))
		result.army_live_editor += int(team.combat_profile_usec.get("render_live_editor", 0))
		result.army_live_calls += int(team.combat_profile_usec.get("render_live_calls", 0))
		result.army_native_frames += team._batch_view.native_crowd_frames if team._batch_view != null else 0
	result["actor_render_total"] = 0
	for actor: TerrainTestCharacter in lab.combat_actors:
		result.actor_render_total += int(actor.combat_pose_profile_usec.get("render_process", 0))
	result["terrain_renderer"] = lab.renderer.r3_render_process_usec
	result["fixture_observer"] = _observer_usec
	result["fixture_snapshot"] = _snapshot_usec
	result["outer_probe"] = _r3_probe_usec
	return result

func _r3_before_draw() -> void:
	var started := Time.get_ticks_usec()
	_r3_pre_draw_modes.clear()
	for item: Dictionary in _r3_viewports:
		var viewport: Viewport = item.viewport
		_r3_pre_draw_modes[item.path] = viewport.render_target_update_mode if viewport is SubViewport else -1
	_r3_probe_usec += Time.get_ticks_usec() - started

func _r3_after_draw() -> void:
	if finished or not is_instance_valid(lab):
		return
	var now := Time.get_ticks_usec()
	var current := _r3_counters()
	var deltas := {}
	for key: String in current:
		deltas[key] = int(current[key]) - int(_r3_prior.get(key, 0))
	_r3_prior = current
	var wall_usec := now - _r3_previous_usec
	_r3_previous_usec = now
	var viewport_samples: Array[Dictionary] = []
	for item: Dictionary in _r3_viewports:
		var rid: RID = item.rid
		var cpu_ms := RenderingServer.viewport_get_measured_render_time_cpu(rid)
		var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		var draw_calls := RenderingServer.viewport_get_render_info(rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		viewport_samples.append({"path": item.path, "roles": item.roles,
			"mode_pre_draw": int(_r3_pre_draw_modes.get(item.path, -2)),
			"visible_draw_calls": draw_calls,
			"cpu_ms_last_reported": cpu_ms if is_finite(cpu_ms) and cpu_ms >= 0.0 else null,
			"gpu_ms_last_reported": gpu_ms if is_finite(gpu_ms) and gpu_ms >= 0.0 else null,
			"updated_evidence": item.roles.has("main") or (int(_r3_pre_draw_modes.get(item.path, 0)) != SubViewport.UPDATE_DISABLED and draw_calls > 0)})
	var lab_action := int(deltas.lab_action_outer)
	var lab_top_children := int(deltas.lab_site_tick) + int(deltas.lab_movement_input) \
		+ int(deltas.lab_navigation_and_team_prepare) + int(deltas.lab_actors_advance) \
		+ int(deltas.lab_actors_sample) + int(deltas.lab_teams_sample) \
		+ int(deltas.lab_resolve) + int(deltas.lab_settle_life_orders_family)
	var lab_total := int(deltas.lab_process_total)
	var lab_outer_children := int(deltas.lab_process_input) + lab_action + int(deltas.lab_finish_tick_outer) \
		+ int(deltas.lab_retaliation_outer) + int(deltas.lab_update_info_outer)
	var army_total := int(deltas.army_render_total)
	var actor_total := int(deltas.actor_render_total)
	var terrain_total := int(deltas.terrain_renderer)
	var fixture_total := int(deltas.fixture_observer) + int(deltas.fixture_snapshot) + int(deltas.outer_probe)
	var action_now := lab._exchange_round * TerrainLab.EXCHANGE_QUERY_STEP + lab._exchange_phase
	var steps := maxi(0, roundi((action_now - _r3_previous_action) / TerrainLab.EXCHANGE_ACTION_STEP))
	_r3_previous_action = action_now
	_r3_frames.append({"at": float(now - measured_us) / 1000000.0,
		"engine_frame_id": Engine.get_process_frames(), "action_seconds": action_now,
		"action_steps": steps, "pending_seconds": lab._action_time_remainder,
		"phase": phase, "wall_usec": wall_usec,
		"deltas_usec": deltas, "lab_process_other_usec": lab_total - lab_outer_children,
		"lab_action_other_usec": lab_action - lab_top_children,
		"army_non_live_usec": army_total - int(deltas.army_live_presenter),
		"unassigned_wall_usec": wall_usec - lab_total - army_total - actor_total - terrain_total - fixture_total,
		"frame_setup_cpu_ms_last_reported": RenderingServer.get_frame_setup_time_cpu(),
		"viewports": viewport_samples})
	# This callback is after the wall boundary; its cost belongs to the next
	# interval. The cumulative counter is sampled at that interval's boundary.
	_r3_probe_usec += Time.get_ticks_usec() - now

func _observe() -> void:
	var started := Time.get_ticks_usec()
	super._observe()
	_observer_usec += Time.get_ticks_usec() - started

func _snapshot(at: float) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result := super._snapshot(at)
	_snapshot_usec += Time.get_ticks_usec() - started
	return result

func _stage_record(at: float) -> Dictionary:
	var army_stages: Array[Dictionary] = []
	var army_native: Array[Dictionary] = []
	for team: TerrainArmy in lab.combat_armies:
		army_stages.append(team.combat_profile_usec.duplicate())
		army_native.append({"move_intent_hits": team.native_move_intent_hits,
			"scheduler": team.profiled_scheduler_metrics.duplicate()})
	return {"wall_at": at, "frames": frame_ms.size(),
		"action_seconds": lab._exchange_round * TerrainLab.EXCHANGE_QUERY_STEP + lab._exchange_phase,
		"pending_seconds": lab._action_time_remainder, "exchanges": lab.exchange_count,
		"orders": lab.combat_armies.map(func(team: TerrainArmy) -> int: return team.combat_order),
		"lab_stage_usec": lab.combat_profile_usec.duplicate(),
		"coordinator_stage_usec": lab.combat_movement_coordinator.profile_usec.duplicate(),
		"army_stage_usec": army_stages, "army_native": army_native,
		"fixture_observer_usec": _observer_usec, "fixture_snapshot_usec": _snapshot_usec}

func _process(delta: float) -> bool:
	var result := super._process(delta)
	if measured_us <= 0 or finished or not is_instance_valid(lab):
		return result
	if _r3 and not _r3_started:
		_r3_started = true
		_r3_start()
	var at := float(Time.get_ticks_usec() - measured_us) / 1000000.0
	if _records.is_empty():
		var initial_record_started := Time.get_ticks_usec()
		_records.append(_stage_record(at))
		_r3_probe_usec += Time.get_ticks_usec() - initial_record_started
	if at >= _next_mark:
		var periodic_record_started := Time.get_ticks_usec()
		_records.append(_stage_record(at))
		_next_mark += 10.0
		_r3_probe_usec += Time.get_ticks_usec() - periodic_record_started
	if at >= _limit_seconds:
		var data := {"scope": "formal TerrainLab 300-person early MOVE diagnostic",
			"diagnostic_only": true, "limit_seconds": _limit_seconds,
			"source_hashes": _source_hashes(),
			"probe_source_hash": FileAccess.get_sha256("res://scripts/tests/site_tactical_ai_early_stage_diagnostic.gd"),
			"records": _records}
		if _r3:
			data["measurement_revision"] = 2
			data["scope"] = "formal TerrainLab 300-person R3 outer CPU and viewport diagnostic"
			data["formal_context"] = {"gpu": RenderingServer.get_video_adapter_name(),
				"renderer": RenderingServer.get_current_rendering_method(),
				"driver": RenderingServer.get_current_rendering_driver_name(),
				"viewport_pixels": [root.size.x, root.size.y],
				"terrain_hash_before": report.get("terrain_hash_before", ""),
				"terrain_hash_after": _terrain_hash(), "natural_steps": natural_steps,
				"natural_pairs": natural_pairs, "ai_enabled": lab.combat_armies.map(func(team: TerrainArmy) -> bool: return team.tactical_ai_enabled)}
			data["source_hashes_before_formal"] = report.get("source_hashes_before", {})
			data["source_hashes_after_formal"] = _source_hashes()
			data["source_stable_formal"] = data.source_hashes_before_formal == data.source_hashes_after_formal
			data["source_hashes_before_r3"] = _r3_source_before
			data["source_hashes_after_r3"] = _r3_source_hashes()
			data["source_stable_r3"] = _r3_source_before == data.source_hashes_after_r3
			data["frames"] = _r3_frames
			data["viewport_catalog"] = _r3_viewports.map(func(item: Dictionary) -> Dictionary:
				return {"path": item.path, "roles": item.roles, "size": item.size})
			data["army_visual_roles"] = []
			data["army_render_profiles"] = []
			data["actor_render_profiles"] = []
			for side in range(lab.combat_armies.size()):
				var team: TerrainArmy = lab.combat_armies[side]
				var roles := {}
				for unit: Dictionary in team.combat_units:
					var role := str(unit.get("visual_role", "male_atlas"))
					roles[role] = int(roles.get(role, 0)) + 1
				data.army_visual_roles.append({"side": side, "roles": roles,
					"native_crowd_frames": team._batch_view.native_crowd_frames if team._batch_view != null else 0})
				data.army_render_profiles.append({"side": side, "render_total_usec": team.combat_render_usec,
					"stages": team.combat_profile_usec.duplicate()})
			for actor: TerrainTestCharacter in lab.combat_actors:
				data.actor_render_profiles.append({"role": "actor_%d" % actor.person_id,
					"stages": actor.combat_pose_profile_usec.duplicate()})
			data["terrain_renderer"] = {"calls": lab.renderer.r3_render_process_calls,
				"usec": lab.renderer.r3_render_process_usec, "pending": lab.renderer.display_pending,
				"processing": lab.renderer.is_processing()}
			data["limitations"] = "Outer probe pre/post draw and stage-record cost is included in deltas_usec.outer_probe; post-draw cost is charged to the following wall interval. Product stage-profiler overhead remains inside owner timings. GPU and CPU can overlap; inactive viewport readings are stale and must not be summed into wall time. Lab/Army/Actor counters nest their children; unassigned_wall_usec is an accounting residual, not a GPU cost. The final post-draw probe has no following measured interval."
			RenderingServer.frame_pre_draw.disconnect(_r3_before_draw)
			RenderingServer.frame_post_draw.disconnect(_r3_after_draw)
			for item: Dictionary in _r3_viewports:
				RenderingServer.viewport_set_measure_render_time(item.rid, false)
			if not data.source_stable_formal or not data.source_stable_r3:
				faults.append("Source changed during R3 diagnostic")
			if _r3_frames.is_empty():
				faults.append("R3 diagnostic captured no frames")
		data["passed"] = faults.is_empty()
		data["faults"] = faults.duplicate()
		var file := FileAccess.open(output + ("/r3_outer_viewport.json" if _r3 else "/early_stage.json"), FileAccess.WRITE)
		if file == null:
			push_error("EARLY_STAGE_DIAGNOSTIC cannot write output: " + str(FileAccess.get_open_error()))
			quit(1)
			return result
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print(("R3_DIAGNOSTIC_" if _r3 else "EARLY_STAGE_DIAGNOSTIC_") + ("PASS " if data.passed else "FAIL "), JSON.stringify({"output": output,
			"last": _records.back(), "observer_usec": _observer_usec,
			"snapshot_usec": _snapshot_usec, "frames": _r3_frames.size() if _r3 else 0,
			"source_stable": bool(data.get("source_stable_r3", true))}))
		finished = true
		lab.set_process(false)
		quit(0 if data.passed else 1)
	return result
