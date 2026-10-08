extends "res://scripts/tests/site_tactical_ai_formal_visual_test.gd"
## Thin F5K diagnostic: the original TerrainLab, deployment, action clock and
## formal visual harness's frame/window calculations remain the test owners.

const TEAM_COUNT := 50
const MEMBERS_PER_TEAM := 100
const MEASURE_SECONDS := 30.0
const SETUP_DEADLINE_SECONDS := 180.0
const OWN_SOURCE := "res://scripts/tests/site_multi_army_realtime_test.gd"
const OUTPUT_ROOT := "res://output/site_multi_army_realtime_20260929"
const RELEASE_OUTPUT_ROOT := "user://site_release_evidence/multi_army"

var team_steps := {}
var previous_team_cells := {}
var command_results: Array[Dictionary] = []
var initial_people := {}

func _initialize() -> void:
	smoke_mode = true
	performance_mode = true
	release_mode = (OS.has_feature("release") and not Engine.is_editor_hint()) \
		or FileAccess.file_exists(OS.get_executable_path().get_base_dir().path_join(RELEASE_MANIFEST))
	if release_mode:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
			OS.get_executable_path().get_base_dir().path_join(RELEASE_MANIFEST)))
		if parsed is Dictionary: release_manifest = parsed
	deadline_us = Time.get_ticks_usec() + int(SETUP_DEADLINE_SECONDS * 1000000.0)
	output = "%s/run_%d_%d" % [RELEASE_OUTPUT_ROOT if release_mode else OUTPUT_ROOT,
		int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	_run.call_deferred()

func _source_hashes() -> Dictionary:
	var hashes: Dictionary = super._source_hashes()
	hashes[OWN_SOURCE] = FileAccess.get_sha256(OWN_SOURCE)
	return hashes

func _fixture_snapshot(at: float) -> Dictionary:
	var teams: Array[Dictionary] = []
	for team: TerrainArmy in lab.combat_armies:
		if not team.has_army(): continue
		var previous: Array = previous_team_cells.get(team.team_id, [])
		if previous.size() == team.cells.size():
			for row in range(previous.size()):
				team_steps[team.team_id] = int(team_steps.get(team.team_id, 0)) + \
					absi(team.cells[row].x - previous[row].x) + absi(team.cells[row].y - previous[row].y)
		previous_team_cells[team.team_id] = team.cells.duplicate()
		teams.append({"team_id": team.team_id, "faction": team.faction_id,
			"order": TerrainArmy.CombatOrder.keys()[team.combat_order],
			"order_serial": team.get_order_serial(), "ai_enabled": team.tactical_ai_enabled,
			"ai_decisions": team.tactical_ai_decisions, "ai_orders": team.tactical_ai_orders,
			"moving": team.moving_count(), "cell_steps": int(team_steps.get(team.team_id, 0)),
			"native_idle_calls": team.native_idle_calls,
			"native_movement_projection_calls": team.native_movement_projection_calls,
			"native_presence_rows": team.native_presence_rows})
	return {"at": at, "teams": teams, "exchange_count": lab.exchange_count,
		"settled_action_seconds": lab._exchange_round * TerrainLab.EXCHANGE_QUERY_STEP + lab._exchange_phase,
		"pending_action_seconds": lab._action_time_remainder}

func _validate_fixture() -> void:
	var factions := {0: 0, 1: 0}
	var occupied := {}
	var team_ids := {}
	for team: TerrainArmy in lab.combat_armies:
		if not team.has_army(): continue
		if team_ids.has(team.team_id): faults.append("Duplicate team ID: " + str(team.team_id))
		team_ids[team.team_id] = true
		if team.combat_units.size() != MEMBERS_PER_TEAM:
			faults.append("Roster is not 100: " + str(team.team_id))
		factions[team.faction_id] = int(factions.get(team.faction_id, 0)) + team.combat_units.size()
		for row in range(team.combat_units.size()):
			var person_id := team.combat_identity(row)
			if initial_people.has(person_id): faults.append("Duplicate person ID: " + str(person_id))
			initial_people[person_id] = team.team_id
			var cell: Vector2i = team.cells[row]
			if int(team._cell_owners.get(cell, -1)) == row:
				if occupied.has(cell): faults.append("Standing overlap: " + str(cell))
				occupied[cell] = person_id
	if team_ids.size() != TEAM_COUNT: faults.append("Expected 50 independent deployed teams")
	if initial_people.size() != TEAM_COUNT * MEMBERS_PER_TEAM:
		faults.append("Expected 5000 unique people")
	if int(factions.get(0, 0)) != 2500 or int(factions.get(1, 0)) != 2500:
		faults.append("Expected two factions of 2500 people")
	report["fixture"] = {"team_ids": team_ids.keys(), "team_count": team_ids.size(),
		"people_count": initial_people.size(), "faction_people": factions,
		"standing_cells": occupied.size(), "terrain_seed": lab.terrain.seed_value,
		"terrain_preset": lab.terrain.preset}

func _issue_move(team: TerrainArmy) -> Dictionary:
	var direction := 1 if team.faction_id == 0 else -1
	var origin: Vector2i = team.command_reference
	for offset: Vector2i in [Vector2i(8, 0), Vector2i(16, 0), Vector2i(8, 10),
			Vector2i(8, -10), Vector2i(16, 10), Vector2i(16, -10)]:
		var goal := origin + Vector2i(direction * offset.x, offset.y)
		if not lab.terrain.is_walkable(goal): continue
		var result: Dictionary = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, goal)
		if bool(result.get("ok", false)):
			return {"ok": true, "goal": [goal.x, goal.y], "result": result}
	return {"ok": false, "reason": "No accepted legal MOVE goal among six deterministic candidates"}

func _run() -> void:
	report = {"passed": false, "scope": "Formal TerrainLab 50 x 100; PLAINS seed 581; 25+25 factions; 30s visual mixed action",
		"mode": "f5k_diagnostic_smoke", "output": output, "package_mode": "release" if release_mode else "editor_source",
		"engine_args": OS.get_cmdline_args(), "user_args": OS.get_cmdline_user_args(),
		"engine": Engine.get_version_info(), "cpu": OS.get_processor_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"frame_source": "consecutive process_frame to RenderingServer.frame_post_draw monotonic wall intervals",
		"action_elapsed_source": "TerrainLab original 30 Hz settled action clock and accepted wall input",
		"fixture_source": "TerrainLab.deploy_trial_armies with normal 100-person preflight; no terrain edits or teleports"}
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) != OK:
		faults.append("Cannot create evidence folder")
		_finish()
		return
	if DisplayServer.get_name() == "headless" or ProjectSettings.get_setting("application/run/main_scene") != "res://scenes/terrain_lab/TerrainLab.tscn":
		faults.append("GPU-backed formal TerrainLab main scene required")
		_finish()
		return
	root.size = Vector2i(1800, 1100)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	report["viewport_pixels"] = [root.size.x, root.size.y]
	if not is_equal_approx(Engine.time_scale, 1.0):
		faults.append("Engine time scale must remain 1.0")
		_finish()
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	report["source_hashes_before"] = _source_hashes()
	if release_mode:
		report["release_manifest_sha256_before"] = FileAccess.get_sha256(
			OS.get_executable_path().get_base_dir().path_join(RELEASE_MANIFEST))
		report["package_hashes_before"] = _package_hashes()
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	if scene == null:
		faults.append("Formal TerrainLab scene could not load")
		_finish()
		return
	lab = scene.instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.combat_profile_enabled = false
	var ui: SiteController = lab.site_controller
	ui._auto_save_blocked = true
	ui.save_path = output + "/isolated_ui_save.json"
	lab.generate_terrain(TerrainPreset.Kind.PLAINS, 581)
	ui._auto_save_blocked = true
	if lab.terrain.preset != TerrainPreset.Kind.PLAINS or lab.terrain.seed_value != 581:
		faults.append("Original Generate rejected PLAINS seed 581")
		_finish()
		return
	report["terrain_hash_before"] = _terrain_hash()
	report["navigation_revision_before"] = lab.terrain.navigation_revision
	var setups: Array[Dictionary] = []
	for index in range(TEAM_COUNT):
		setups.append({"count": MEMBERS_PER_TEAM, "role": "combat", "troop_type": "melee_infantry",
			"faction": 0 if index < 25 else 1, "entry": "west" if index < 25 else "east",
			"attack": index % 4 == 2, "ai_enabled": index % 4 == 0})
	var deployed: Dictionary = lab.deploy_trial_armies(setups)
	if not bool(deployed.get("ok", false)):
		faults.append("Formal 50-team deployment failed: " + JSON.stringify(deployed))
		_finish()
		return
	_validate_fixture()
	if not faults.is_empty():
		_finish()
		return
	var commands := {"AI": 0, "MOVE": 0, "ATTACK": 0, "HOLD": 0}
	for index in range(TEAM_COUNT):
		var team: TerrainArmy = lab.combat_armies[index]
		team.combat_profile_enabled = false
		var mode: String = ["AI", "MOVE", "ATTACK", "HOLD"][index % 4]
		var result: Dictionary = {"ok": true}
		if mode == "MOVE": result = _issue_move(team)
		elif mode == "ATTACK": result = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.ATTACK)
		elif mode == "HOLD": result = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.HOLD)
		if not bool(result.get("ok", false)):
			faults.append("Team %d %s command rejected: %s" % [team.team_id, mode, JSON.stringify(result)])
		else:
			commands[mode] = int(commands[mode]) + 1
		command_results.append({"team_id": team.team_id, "faction": team.faction_id,
			"mode": mode, "result": result, "order_serial": team.get_order_serial()})
	report["command_results"] = command_results
	report["command_counts"] = commands
	if not faults.is_empty():
		_finish()
		return
	assert(not lab.has_node("TerrainLabUI"), "Legacy debug panel must not be constructed")
	if is_instance_valid(lab.site_test_window): lab.site_test_window.hide()
	ui.panel.hide()
	ui.status_panel.hide()
	lab.camera.zoom = Vector2.ONE * 0.15
	lab.camera.position = Vector2(lab.terrain.size) * TerrainRenderer.CELL_PIXELS * 0.5
	lab.camera.force_update_scroll()
	for _frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	_capture("before.png")
	for team: TerrainArmy in lab.combat_armies:
		team.native_idle_calls = 0
		team.native_movement_projection_calls = 0
		team.native_presence_rows = 0
	snapshots.append(_fixture_snapshot(0.0))
	measured_us = Time.get_ticks_usec()
	deadline_us = measured_us + int((MEASURE_SECONDS + 15.0) * 1000000.0)
	report["action_seconds_before"] = lab._exchange_round * TerrainLab.EXCHANGE_QUERY_STEP + lab._exchange_phase
	report["pending_seconds_before"] = lab._action_time_remainder
	lab.combat_profile_usec.clear()
	lab.combat_movement_coordinator.profile_enabled = false
	lab.combat_movement_coordinator.profile_usec.clear()
	lab.action_elapsed_input_sum = 0.0
	lab.action_elapsed_input_count = 0
	lab.action_elapsed_measure_enabled = true
	report["measurement_mode_before"] = _mode_state()
	var previous_us := measured_us
	var previous_action := float(report.action_seconds_before)
	var next_snapshot := 10.0
	lab.set_process(true)
	while not finished and Time.get_ticks_usec() - measured_us < int(MEASURE_SECONDS * 1000000.0):
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var at := float(now - measured_us) / 1000000.0
		frame_ms.append(float(now - previous_us) / 1000.0)
		frame_at.append(at)
		previous_us = now
		var action_now := lab._exchange_round * TerrainLab.EXCHANGE_QUERY_STEP + lab._exchange_phase
		frame_action_seconds.append(action_now)
		frame_pending_seconds.append(lab._action_time_remainder)
		frame_input_seconds.append(lab.action_elapsed_input_sum)
		frame_steps.append(maxi(0, roundi((action_now - previous_action) / TerrainLab.EXCHANGE_ACTION_STEP)))
		frame_phase.append("mixed_action")
		previous_action = action_now
		maximum_pending_seconds = maxf(maximum_pending_seconds, lab._action_time_remainder)
		if at >= next_snapshot:
			snapshots.append(_fixture_snapshot(at))
			print("SITE_MULTI_ARMY_PROGRESS ", JSON.stringify({"at": at, "frames": frame_ms.size(),
				"action_seconds": action_now - float(report.action_seconds_before), "pending_seconds": lab._action_time_remainder,
				"exchanges": lab.exchange_count}))
			next_snapshot += 10.0
	if finished: return
	lab.set_process(false)
	snapshots.append(_fixture_snapshot(float(Time.get_ticks_usec() - measured_us) / 1000000.0))
	await RenderingServer.frame_post_draw
	_capture("after.png")
	_finish()

func _finish() -> void:
	if finished: return
	finished = true
	if is_instance_valid(lab): lab.set_process(false)
	var wall: float = frame_at.back() if not frame_at.is_empty() else 0.0
	report["wall_seconds"] = wall
	report["frame_ms"] = frame_ms
	report["frame_at"] = frame_at
	report["frame_action_seconds"] = frame_action_seconds
	report["frame_pending_seconds"] = frame_pending_seconds
	report["frame_accepted_input_seconds"] = frame_input_seconds
	report["frame_steps"] = frame_steps
	report["process_delta_seconds"] = process_delta_seconds
	report["process_delta_at"] = process_delta_at
	report["snapshots"] = snapshots
	report["fps"] = frame_ms.size() / wall if wall > 0.0 else 0.0
	report["p95_ms"] = _percentile(0.95)
	report["p99_ms"] = _percentile(0.99)
	report["max_ms"] = frame_ms.max() if not frame_ms.is_empty() else 0.0
	report["source_hashes_after"] = _source_hashes()
	var gates := {"source_stable": report.get("source_hashes_before", {}) == report.source_hashes_after,
		"f5k_fixture": int(report.get("fixture", {}).get("team_count", 0)) == TEAM_COUNT
			and int(report.get("fixture", {}).get("people_count", 0)) == TEAM_COUNT * MEMBERS_PER_TEAM,
		"all_four_command_modes": int(report.get("command_counts", {}).get("AI", 0)) > 0
			and int(report.get("command_counts", {}).get("MOVE", 0)) > 0
			and int(report.get("command_counts", {}).get("ATTACK", 0)) > 0
			and int(report.get("command_counts", {}).get("HOLD", 0)) > 0,
		"complete_30s": wall >= MEASURE_SECONDS and wall < MEASURE_SECONDS + 5.0}
	if is_instance_valid(lab):
		report["action_seconds_after"] = lab._exchange_round * TerrainLab.EXCHANGE_QUERY_STEP + lab._exchange_phase
		report["pending_seconds_after"] = lab._action_time_remainder
		report["accepted_input_seconds"] = lab.action_elapsed_input_sum
		report["accepted_input_callbacks"] = lab.action_elapsed_input_count
		report["maximum_pending_seconds"] = maximum_pending_seconds
		report["measurement_mode_after"] = _mode_state()
		report["action_clock_ratio"] = (float(report.action_seconds_after) - float(report.get("action_seconds_before", 0.0))) / wall if wall > 0.0 else 0.0
		report["terrain_hash_after"] = _terrain_hash()
		report["navigation_revision_after"] = lab.terrain.navigation_revision
		report["native_counts"] = {"idle_calls": 0, "movement_projection_calls": 0, "presence_rows": 0}
		for team: TerrainArmy in lab.combat_armies:
			report.native_counts.idle_calls += team.native_idle_calls
			report.native_counts.movement_projection_calls += team.native_movement_projection_calls
			report.native_counts.presence_rows += team.native_presence_rows
		gates["native_used"] = ClassDB.class_exists("ArmyIdleKernel") and \
			(int(report.native_counts.idle_calls) + int(report.native_counts.movement_projection_calls) + int(report.native_counts.presence_rows) > 0)
		gates["terrain_unchanged"] = report.get("terrain_hash_before", "") == report.terrain_hash_after \
			and report.get("navigation_revision_before", -1) == report.navigation_revision_after
		gates["action_clock"] = float(report.action_clock_ratio) >= 0.99 and float(report.action_clock_ratio) <= 1.01
		gates["pending_peak"] = maximum_pending_seconds <= 0.25
		gates["input_conserved"] = absf(float(report.accepted_input_seconds) - \
			(float(report.action_seconds_after) - float(report.get("action_seconds_before", 0.0))) - \
			(float(report.pending_seconds_after) - float(report.get("pending_seconds_before", 0.0)))) <= 0.0001
	if not frame_at.is_empty():
		report["performance_windows"] = _performance_windows()
		gates["p95"] = float(report.p95_ms) <= 33.333
		gates["p99"] = float(report.p99_ms) <= 50.0
		gates["no_second_long_frame"] = float(report.max_ms) < 1000.0
		for window: Dictionary in report.performance_windows:
			gates["fps_window_" + str(window.window)] = bool(window.complete) and float(window.get("fps", 0.0)) >= 30.0
			gates["action_window_" + str(window.window)] = bool(window.complete) and \
				float(window.get("action_ratio", 0.0)) >= 0.99 and float(window.get("action_ratio", 0.0)) <= 1.01
	for gate: String in gates:
		if not bool(gates[gate]): faults.append("Gate failed: " + gate)
	report["gates"] = gates
	report["faults"] = faults
	report["passed"] = faults.is_empty()
	var file := FileAccess.open(output + "/measurements.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	else:
		faults.append("Could not write measurements")
	print("SITE_MULTI_ARMY_F5K_", "PASS" if faults.is_empty() else "FAIL", " ",
		JSON.stringify({"output": output, "faults": faults, "fps": report.fps,
			"p95_ms": report.p95_ms, "p99_ms": report.p99_ms, "action_clock_ratio": report.get("action_clock_ratio", 0.0)}))
	if is_instance_valid(lab): lab.queue_free()
	quit(0 if faults.is_empty() else 1)
