extends SceneTree
## D1 diagnostic: the formal TerrainLab deployment and action owner, without GPU presentation.
## Run separately with -- --teams=3, --teams=10, and --teams=50.

const SCENE := "res://scenes/terrain_lab/TerrainLab.tscn"
const TacticalAI = preload("res://scripts/terrain_lab/site_army_ai.gd")
const OUTPUT_ROOT := "res://output/site_crowd_d1_20260929"
const WARMUP_STEPS := 10
const MEASURE_STEPS := 60
const DEADLINE_SECONDS := 300.0

var _started_usec := 0
var _deadline_usec := 0
var _folder := ""
var _lab: TerrainLab
var _result := {}
var _finished := false

func _initialize() -> void:
	_started_usec = Time.get_ticks_usec()
	_deadline_usec = _started_usec + int(DEADLINE_SECONDS * 1000000.0)
	_folder = "%s/run_%d_%d" % [OUTPUT_ROOT, int(Time.get_unix_time_from_system()), _started_usec]
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not _finished and Time.get_ticks_usec() >= _deadline_usec:
		_finish("D1 step profile exceeded its 300-second deadline")
	return false

func _sources() -> Dictionary:
	var result := {}
	for path: String in [SCENE, "res://scripts/terrain_lab/terrain_lab.gd",
			"res://scripts/terrain_lab/terrain_army.gd",
			"res://scripts/terrain_lab/site_army_ai.gd",
			"res://scripts/terrain_lab/combat_move_plan.gd",
			"res://scripts/terrain_lab/formation_destination_planner.gd",
			"res://scripts/terrain_lab/site_combat_movement_coordinator.gd",
			"res://scripts/tests/site_crowd_d1_step_profile_test.gd"]:
		result[path] = FileAccess.get_sha256(path)
	return result

func _finish(failure: String = "") -> void:
	if _finished:
		return
	_finished = true
	_result["passed"] = failure.is_empty()
	_result["failure"] = failure
	_result["elapsed_wall_seconds"] = float(Time.get_ticks_usec() - _started_usec) / 1000000.0
	_result["source_hashes_after"] = _sources()
	if not _folder.is_empty() and DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_folder)) == OK:
		var file := FileAccess.open(_folder + "/measurements.json", FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(_result, "\t"))
			file.close()
		else:
			push_error("D1 could not write measurements.json")
	else:
		push_error("D1 could not create evidence folder")
	print("SITE_CROWD_D1_", "PASS" if failure.is_empty() else "FAIL", " ",
		JSON.stringify({"folder": _folder, "failure": failure}))
	if _lab != null:
		_lab.queue_free()
	quit(0 if failure.is_empty() else 1)

func _issue_move(team: TerrainArmy) -> Dictionary:
	var direction := 1 if team.faction_id == 0 else -1
	var origin: Vector2i = team.command_reference
	for offset: Vector2i in [Vector2i(8, 0), Vector2i(16, 0), Vector2i(8, 10),
			Vector2i(8, -10), Vector2i(16, 10), Vector2i(16, -10)]:
		var goal := origin + Vector2i(direction * offset.x, offset.y)
		if not _lab.terrain.is_walkable(goal):
			continue
		var issued: Dictionary = team.issue_combat_order(team.current_commander,
			TerrainArmy.CombatOrder.MOVE, goal)
		if bool(issued.get("ok", false)):
			return issued
	return {"ok": false, "message": "No accepted deterministic MOVE goal"}

func _clock_seconds() -> float:
	return _lab._exchange_round * TerrainLab.EXCHANGE_QUERY_STEP + _lab._exchange_phase

func _distribution(samples: Array[int]) -> Dictionary:
	if samples.is_empty():
		return {}
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0
	for sample: int in samples:
		total += sample
	return {"count": samples.size(), "sum_usec": total,
		"mean_usec": float(total) / samples.size(),
		"p50_usec": sorted[floori(float(sorted.size() - 1) * 0.50)],
		"p95_usec": sorted[ceili(float(sorted.size()) * 0.95) - 1],
		"max_usec": sorted.back()}

func _sum_team_counters(field: String) -> Dictionary:
	var sums := {}
	for team: TerrainArmy in _lab.combat_armies:
		if not team.has_army():
			continue
		var counters: Dictionary = team.get(field)
		for key: Variant in counters:
			if counters[key] is int or counters[key] is float:
				sums[str(key)] = int(sums.get(str(key), 0)) + int(counters[key])
	return sums

func _run() -> void:
	var team_count := -1
	var profile_enabled := true
	var hot_diagnostics := false
	var activity_mode := "mixed"
	var enemy_index_enabled := true
	var platform_bfs_cache_enabled := true
	var hold_empty_rescue_skip_enabled := true
	var hold_rescue_column_enabled := true
	var bbox_contact_guard_enabled := true
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--teams="):
			team_count = int(argument.trim_prefix("--teams="))
		elif argument == "--profile=off":
			profile_enabled = false
		elif argument == "--hot-diagnostics=on":
			hot_diagnostics = true
		elif argument == "--activity=hold":
			activity_mode = "hold"
		elif argument == "--enemy-index=off":
			enemy_index_enabled = false
		elif argument == "--platform-bfs-cache=off":
			platform_bfs_cache_enabled = false
		elif argument == "--hold-rescue-guard=off":
			hold_empty_rescue_skip_enabled = false
		elif argument == "--hold-rescue-column=off":
			hold_rescue_column_enabled = false
		elif argument == "--bbox-contact-guard=off":
			bbox_contact_guard_enabled = false
	FormationDestinationPlanner.platform_bfs_cache_enabled = platform_bfs_cache_enabled
	TacticalAI.bbox_contact_guard_enabled = bbox_contact_guard_enabled
	_result = {"scope": "Headless formal TerrainLab fixed-step D1 diagnosis; no GPU, visual FPS, or live 3D captain claim",
		"scene": SCENE, "team_count": team_count, "members_per_team": 100,
		"activity_mode": activity_mode,
		"profile_enabled": profile_enabled,
		"enemy_index_enabled": enemy_index_enabled,
		"platform_bfs_cache_enabled": platform_bfs_cache_enabled,
		"hold_empty_rescue_skip_enabled": hold_empty_rescue_skip_enabled,
		"hold_rescue_column_enabled": hold_rescue_column_enabled,
		"bbox_contact_guard_enabled": bbox_contact_guard_enabled,
		"hot_diagnostics": hot_diagnostics,
		"preset": "PLAINS", "seed": 581, "warmup_steps": WARMUP_STEPS,
		"measured_steps": MEASURE_STEPS, "step_seconds": TerrainLab.EXCHANGE_ACTION_STEP,
		"clock": "Manual TerrainLab._process(fixed 30 Hz delta); inclusive wall timer brackets original Site/UI/action owner",
		"profile_hierarchy": "frame_inclusive contains lab.process_total; action_outer contains coordinator and team prepare. Child timers overlap parents and must not be added.",
		"source_hashes_before": _sources()}
	if team_count not in [3, 10, 50]:
		_finish("Expected --teams=3, 10, or 50")
		return
	if DisplayServer.get_name() != "headless":
		_finish("D1 step profile requires headless; the 50-team visual test is separate")
		return
	if not is_equal_approx(Engine.time_scale, 1.0):
		_finish("Engine.time_scale must be 1.0")
		return
	var scene: PackedScene = load(SCENE)
	if scene == null:
		_finish("Formal TerrainLab scene did not load")
		return
	_lab = scene.instantiate()
	_lab.enemy_query_owner_cells_enabled = enemy_index_enabled
	_lab.pause_when_unfocused = false
	root.add_child(_lab)
	current_scene = _lab
	_lab.set_process(false)
	_lab.set_process_unhandled_input(false)
	var ui: SiteController = _lab.site_controller
	ui._auto_save_blocked = true
	ui.save_path = _folder + "/isolated_ui_save.json"
	_lab.generate_terrain(TerrainPreset.Kind.PLAINS, 581)
	ui._auto_save_blocked = true
	if _lab.terrain == null or _lab.terrain.size != Vector2i(100, 100):
		_finish("Formal PLAINS 581 100x100 generation failed")
		return
	if Time.get_ticks_usec() >= _deadline_usec:
		_finish("D1 setup deadline after terrain generation")
		return
	var setups: Array[Dictionary] = []
	var friendly := ceili(float(team_count) / 2.0)
	for index in range(team_count):
		setups.append({"count": 100, "role": "combat", "troop_type": "melee_infantry",
			"faction": 0 if index < friendly else 1,
			"entry": "west" if index < friendly else "east",
			"attack": activity_mode == "mixed" and index % 4 == 2,
			"ai_enabled": activity_mode == "mixed" and index % 4 == 0})
	var setup_started := Time.get_ticks_usec()
	var deployed: Dictionary = _lab.deploy_trial_armies(setups)
	_result["deployment_usec"] = Time.get_ticks_usec() - setup_started
	if not bool(deployed.get("ok", false)):
		_finish("Formal deploy_trial_armies failed: " + str(deployed))
		return
	var team_ids := {}
	var person_ids := {}
	var occupied := {}
	for team: TerrainArmy in _lab.combat_armies:
		if not team.has_army():
			continue
		if team.combat_units.size() != 100 or team_ids.has(team.team_id):
			_finish("Invalid team roster or duplicate team ID")
			return
		team_ids[team.team_id] = true
		for index in range(team.combat_units.size()):
			var person_id := team.combat_identity(index)
			var cell: Vector2i = team.cells[index]
			if person_ids.has(person_id) or occupied.has(cell):
				_finish("Duplicate person ID or standing cell")
				return
			person_ids[person_id] = true
			occupied[cell] = true
	if team_ids.size() != team_count or person_ids.size() != team_count * 100:
		_finish("Formal deployed count was not %d x 100" % team_count)
		return
	_result["fixture"] = {"teams": team_ids.size(), "people": person_ids.size(),
		"occupied_cells": occupied.size(), "factions": [friendly, team_count - friendly],
		"terrain_navigation_revision": _lab.terrain.navigation_revision}
	var commands := {"AI": 0, "MOVE": 0, "ATTACK": 0, "HOLD": 0}
	for index in range(team_count):
		var team: TerrainArmy = _lab.combat_armies[index]
		var mode: String = "HOLD" if activity_mode == "hold" else ["AI", "MOVE", "ATTACK", "HOLD"][index % 4]
		var issued: Dictionary = {"ok": true}
		if mode == "MOVE":
			issued = _issue_move(team)
		elif mode == "ATTACK":
			issued = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.ATTACK)
		elif mode == "HOLD":
			issued = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.HOLD)
		if not bool(issued.get("ok", false)):
			_finish("Team %d %s command rejected: %s" % [team.team_id, mode, str(issued)])
			return
		commands[mode] = int(commands[mode]) + 1
	_result["command_counts"] = commands
	if Time.get_ticks_usec() >= _deadline_usec:
		_finish("D1 setup deadline after deployment and commands")
		return
	var warmup_started := Time.get_ticks_usec()
	for step in range(WARMUP_STEPS):
		if Time.get_ticks_usec() >= _deadline_usec:
			_finish("D1 warmup deadline at step %d" % step)
			return
		_lab._process(TerrainLab.EXCHANGE_ACTION_STEP)
	_result["warmup_usec"] = Time.get_ticks_usec() - warmup_started
	var action_before := _clock_seconds()
	var pending_before := _lab._action_time_remainder
	var exchanges_before := _lab.exchange_count
	_lab.combat_profile_enabled = profile_enabled
	_lab.combat_profile_usec.clear()
	_lab.combat_movement_coordinator.profile_enabled = profile_enabled
	_lab.combat_movement_coordinator.profile_usec.clear()
	FormationDestinationPlanner.profile_enabled = profile_enabled
	FormationDestinationPlanner.profile_usec.clear()
	FormationDestinationPlanner.profile_calls.clear()
	for team: TerrainArmy in _lab.combat_armies:
		if team.has_army():
			team.hold_empty_rescue_skip_enabled = hold_empty_rescue_skip_enabled
			team.hold_rescue_column_enabled = hold_rescue_column_enabled
			team.combat_profile_enabled = profile_enabled
			team.combat_profile_usec.clear()
			team.combat_hot_diagnostics_enabled = hot_diagnostics
			team.combat_hot_reset_stats()
	var frames: Array[Dictionary] = []
	var frame_samples: Array[int] = []
	var maximum_pending := pending_before
	for step in range(MEASURE_STEPS):
		if Time.get_ticks_usec() >= _deadline_usec:
			_finish("D1 measurement deadline at step %d" % step)
			return
		var before := Time.get_ticks_usec()
		_lab._process(TerrainLab.EXCHANGE_ACTION_STEP)
		var elapsed := Time.get_ticks_usec() - before
		frame_samples.append(elapsed)
		var pending: float = _lab._action_time_remainder
		maximum_pending = maxf(maximum_pending, pending)
		frames.append({"step": step + 1, "frame_inclusive_usec": elapsed,
			"settled_action_seconds": _clock_seconds(), "pending_action_seconds": pending,
			"exchange_count": _lab.exchange_count})
	var action_after := _clock_seconds()
	var lab_profile: Dictionary = _lab.combat_profile_usec.duplicate()
	var coordinator_profile: Dictionary = _lab.combat_movement_coordinator.profile_usec.duplicate()
	var army_profile := _sum_team_counters("combat_profile_usec")
	var geometry_profile := _sum_team_counters("combat_geometry_profile")
	var moving := 0
	var ai_decisions := 0
	var ai_orders := 0
	for team: TerrainArmy in _lab.combat_armies:
		if not team.has_army():
			continue
		moving += team.moving_count()
		ai_decisions += team.tactical_ai_decisions
		ai_orders += team.tactical_ai_orders
	_result["steps"] = frames
	_result["frame_inclusive"] = _distribution(frame_samples)
	_result["action"] = {"settled_before_seconds": action_before,
		"settled_after_seconds": action_after, "settled_during_seconds": action_after - action_before,
		"requested_during_seconds": MEASURE_STEPS * TerrainLab.EXCHANGE_ACTION_STEP,
		"pending_before_seconds": pending_before, "pending_after_seconds": _lab._action_time_remainder,
		"maximum_pending_seconds": maximum_pending,
		"exchanges_during": _lab.exchange_count - exchanges_before,
		"moving_at_end": moving, "ai_decisions_at_end": ai_decisions, "ai_orders_at_end": ai_orders}
	_result["inclusive_parent_usec"] = {"frame": _result.frame_inclusive.sum_usec,
		"lab_process": int(lab_profile.get("process_total", 0)),
		"lab_action_advance": int(lab_profile.get("action_outer", 0)),
		"navigation_and_team_prepare": int(lab_profile.get("navigation_and_team_prepare", 0)),
		"movement_coordinator": int(lab_profile.get("movement_coordinator", 0)),
		"exchange_people_index": int(lab_profile.get("exchange_people_index", 0)),
		"exchange_pair_context": int(lab_profile.get("exchange_pair_context", 0)),
		"exchange_apply": int(lab_profile.get("exchange_apply", 0))}
	_result["lab_profile_usec"] = lab_profile
	_result["coordinator_profile_usec"] = coordinator_profile
	_result["army_profile_usec_sum"] = army_profile
	_result["movement_phase_profile_usec"] = FormationDestinationPlanner.profile_usec.duplicate()
	_result["movement_phase_profile_calls"] = FormationDestinationPlanner.profile_calls.duplicate()
	FormationDestinationPlanner.profile_enabled = false
	var replay_state: Array[Dictionary] = []
	for team: TerrainArmy in _lab.combat_armies:
		if team.has_army():
			replay_state.append(team.capture_combat_state())
	_result["replay_state_sha256"] = JSON.stringify(replay_state).sha256_text()
	_result["army_geometry_profile_sum"] = geometry_profile
	_result["enemy_index_hits"] = _lab.enemy_query_owner_cell_hits
	if hot_diagnostics:
		var hot_stats: Array[Dictionary] = []
		for team: TerrainArmy in _lab.combat_armies:
			if team.has_army():
				hot_stats.append({"team_id": team.team_id, "faction_id": team.faction_id,
					"combat_order": team.combat_order, "stats": team.combat_hot_stats()})
		_result["combat_hot_stats_by_team"] = hot_stats
	_result["pose_scope"] = "Formal exchange mode uses numeric pair context in headless; live 3D pose, viewport, GPU, and presentation cost are unmeasured"
	if _result.source_hashes_before != _sources():
		_finish("Source changed during D1 measurement")
		return
	if action_after <= action_before or (profile_enabled and int(lab_profile.get("process_total", 0)) <= 0):
		_finish("Original action clock or inclusive process profiler did not advance")
		return
	_finish()
