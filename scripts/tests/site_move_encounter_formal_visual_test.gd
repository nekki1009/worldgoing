extends SceneTree
## Bounded GPU acceptance of the real TerrainLab 100 versus 100 MOVE/HOLD encounter.
## The entire 60-second window uses the scene's own _process and rendered frames.

const LAB_SCENE = preload("res://scenes/terrain_lab/TerrainLab.tscn")
const SiteEnv = preload("res://scripts/terrain_lab/site_environment.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const SECONDS := 60.0
const DEADLINE_SECONDS := 140.0
const OUTPUT_ROOT := "res://output/site_move_encounter_formal_visual"
const SOURCES := [
	"res://scenes/terrain_lab/TerrainLab.tscn",
	"res://scripts/terrain_lab/terrain_lab.gd",
	"res://scripts/terrain_lab/terrain_army.gd",
	"res://scripts/tests/site_move_encounter_formal_visual_test.gd",
]

var _lab: TerrainLab
var _data: TerrainData
var _mover: TerrainArmy
var _holder: TerrainArmy
var _move_plan: CombatMovePlan
var _serial := -1
var _started_us := 0
var _deadline_us := 0
var _output := ""
var _report := {}
var _faults: Array[String] = []
var _frame_ms: Array[float] = []
var _frame_at: Array[float] = []
var _initial_ids: Array = []
var _terrain_columns := {}
var _source_hashes := {}
var _engage_begin_at := -1.0
var _max_engage_seconds := 0.0
var _engaging_frames := 0
var _cooldown_engaging_frames := 0
var _contact_ids := {}
var _released_at := -1.0
var _released_cells: Array[Vector2i] = []
var _continued_at := -1.0
var _natural_ko_at_release := 0

func _initialize() -> void:
	_started_us = Time.get_ticks_usec()
	_deadline_us = _started_us + int(DEADLINE_SECONDS * 1000000.0)
	_output = "%s/%d_%d" % [OUTPUT_ROOT, int(Time.get_unix_time_from_system()), _started_us]
	_run.call_deferred()

func _write() -> bool:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output)) != OK:
		return false
	var file := FileAccess.open(_output + "/measurements.json", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	return true

func _fail(reason: String) -> void:
	_report["targets_met"] = false
	_report["reason"] = reason
	_report["faults"] = _faults
	_report["frame_ms"] = _frame_ms
	_report["frame_at_seconds"] = _frame_at
	_report["elapsed_wall_seconds"] = (Time.get_ticks_usec() - _started_us) / 1000000.0
	if not _write(): push_error("MOVE_ENCOUNTER_FORMAL could not write " + _output)
	push_error("MOVE_ENCOUNTER_FORMAL FAILED: " + reason)
	if is_instance_valid(_lab):
		_lab.set_process(false)
		_lab.queue_free()
	quit(1)

func _note_fault(reason: String) -> void:
	if not _faults.has(reason):
		_faults.append(reason)

func _action_seconds() -> float:
	return float(_lab._exchange_round) * TerrainLab.EXCHANGE_QUERY_STEP + _lab._exchange_phase + _lab._action_time_remainder

func _terrain_unchanged() -> bool:
	return _data.height_levels == _terrain_columns.height_levels \
		and _data.static_blocked == _terrain_columns.static_blocked \
		and _data.ramp_edges == _terrain_columns.ramp_edges \
		and _data.flags == _terrain_columns.flags \
		and _data.surface_types == _terrain_columns.surface_types

func _occupied_without_overlap() -> bool:
	var occupied := {}
	var destinations := {}
	for actor: TerrainTestCharacter in _lab.combat_actors:
		if is_instance_valid(actor) and actor.occupies_cell(actor.terrain_cell):
			if occupied.has(actor.terrain_cell): return false
			occupied[actor.terrain_cell] = actor.person_id
	for team: TerrainArmy in [_mover, _holder]:
		for index in range(team.combat_units.size()):
			var cell: Vector2i = team.cells[index]
			if int(team._cell_owners.get(cell, -1)) == index:
				if occupied.has(cell): return false
				occupied[cell] = team.combat_identity(index)
			var destination: Vector2i = team.moving_to[index]
			if destination != TerrainArmy.INVALID_CELL:
				if destinations.has(destination): return false
				destinations[destination] = team.combat_identity(index)
	return true

func _contact_state() -> Dictionary:
	var plan: CombatMovePlan = _mover.get_active_move_plan()
	var engaging := plan == _move_plan and plan != null and plan.tactical_overlay == Types.TacticalOverlay.ENGAGING
	var adjacent := false
	var cooling := false
	if engaging:
		for source_index: Variant in _mover._move_encounters:
			var index := int(source_index)
			var enemies: Dictionary = _mover._move_encounters[source_index]
			for enemy_id: Variant in enemies:
				var other_index := _holder.index_for_identity(int(enemy_id))
				if other_index < 0 or not _holder.combat_can_act(other_index): continue
				var source: Vector2i = _mover.cells[index]
				var target: Vector2i = _holder.cells[other_index]
				if absi(source.x - target.x) + absi(source.y - target.y) == 1 and _data.can_attack_across(source, target):
					adjacent = true
					cooling = cooling or float(_mover.combat_hot_get(index, &"exchange_cooldown", 0.0)) > 0.0
					_contact_ids[int(enemy_id)] = true
	return {"engaging": engaging, "adjacent": adjacent, "cooling": cooling}

func _observe(at: float) -> void:
	if _mover.combat_units.size() != 100 or _holder.combat_units.size() != 100:
		_note_fault("Original 100 + 100 roster size changed")
		return
	for side in range(2):
		var team: TerrainArmy = _mover if side == 0 else _holder
		for index in range(100):
			if team.combat_identity(index) != int(_initial_ids[side][index]):
				_note_fault("Original person identities changed")
				break
	if not _occupied_without_overlap(): _note_fault("Physical occupancy or in-flight destination overlapped")
	if _mover.get_order_serial() != _serial:
		_note_fault("Original MOVE order serial changed")
	if _mover.combat_order == TerrainArmy.CombatOrder.MOVE and _mover.get_active_move_plan() != _move_plan:
		_note_fault("Original MOVE plan was replaced")
	var contact := _contact_state()
	if bool(contact.engaging) and bool(contact.adjacent):
		_engaging_frames += 1
		_cooldown_engaging_frames += int(bool(contact.cooling))
		if _engage_begin_at < 0.0: _engage_begin_at = at
		_max_engage_seconds = maxf(_max_engage_seconds, at - _engage_begin_at)
	else:
		if _engage_begin_at >= 0.0 and _released_at < 0.0 and _mover.combat_order == TerrainArmy.CombatOrder.MOVE:
			_released_at = at
			_released_cells = _mover.cells.duplicate()
			for enemy_id: int in _contact_ids:
				var enemy_index := _holder.index_for_identity(enemy_id)
				_natural_ko_at_release += int(enemy_index >= 0 and not _holder.combat_can_act(enemy_index))
		_engage_begin_at = -1.0
	if _released_at >= 0.0 and _continued_at < 0.0 and _mover.cells != _released_cells:
		_continued_at = at

func _percentile(samples: Array[float], fraction: float) -> float:
	if samples.is_empty(): return -1.0
	var ordered := samples.duplicate()
	ordered.sort()
	return ordered[clampi(ceili(ordered.size() * fraction) - 1, 0, ordered.size() - 1)]

func _window_report() -> Array[Dictionary]:
	var samples: Array = [[], [], [], [], [], []]
	for index in range(_frame_ms.size()):
		var bin := clampi(floori(_frame_at[index] / 10.0), 0, 5)
		samples[bin].append(_frame_ms[index])
	var windows: Array[Dictionary] = []
	for index in range(6):
		var times: Array[float] = []
		times.assign(samples[index])
		windows.append({"from_seconds": index * 10, "to_seconds": (index + 1) * 10,
			"frames": times.size(), "fps": times.size() / 10.0,
			"p95_ms": _percentile(times, 0.95), "p99_ms": _percentile(times, 0.99)})
	return windows

func _capture(name: String) -> bool:
	var image := root.get_texture().get_image()
	return image != null and not image.is_empty() and image.save_png(_output + "/" + name) == OK

func _run() -> void:
	_report = {"scope": "Exact TerrainLab.tscn; production generated highland seed 12345; public 100 + 100 trial; accepted commander MOVE versus HOLD; 60 wall seconds of normal _process and frame_post_draw",
		"targets_met": false, "output": _output, "terrain_edits": false, "manual_combat_advance": false,
		"mid_measurement_teleports": false, "continuation_scope": "Natural contact clearance only; no scripted KO or removal"}
	if DisplayServer.get_name() == "headless":
		_fail("GPU window required")
		return
	if not is_equal_approx(Engine.time_scale, 1.0):
		_fail("Engine time scale must be 1.0")
		return
	root.size = Vector2i(1600, 1000)
	root.content_scale_size = root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if not _write():
		push_error("MOVE_ENCOUNTER_FORMAL cannot create output " + _output)
		quit(1)
		return
	for path: String in SOURCES:
		_source_hashes[path] = FileAccess.get_sha256(path)
	_lab = LAB_SCENE.instantiate() as TerrainLab
	_lab.pause_when_unfocused = false
	root.add_child(_lab)
	current_scene = _lab
	_lab.set_process(false)
	_lab.set_process_unhandled_input(false)
	_lab.site_controller._auto_save_blocked = true
	if _lab.scene_file_path != "res://scenes/terrain_lab/TerrainLab.tscn" or not _lab.exchange_enabled:
		_fail("The formal scene or exchange policy is unavailable")
		return
	_data = TerrainGenerator.generate(TerrainPreset.Kind.TERRACED_HIGHLAND, 12345)
	SiteEnv.initialize(_data, "formal-move-encounter-visual-fixture")
	_lab.bind_terrain(_data)
	if _lab.terrain != _data or _data.preset != TerrainPreset.Kind.TERRACED_HIGHLAND or _data.seed_value != 12345:
		_fail("Fresh production terrain setup failed")
		return
	_terrain_columns = {"height_levels": _data.height_levels.duplicate(), "static_blocked": _data.static_blocked.duplicate(),
		"ramp_edges": _data.ramp_edges.duplicate(), "flags": _data.flags.duplicate(), "surface_types": _data.surface_types.duplicate()}
	var trial: Dictionary = _lab.start_melee_trial({"friendly_count": 100, "enemy_count": 100,
		"friendly_attack": false, "enemy_attack": false})
	if not bool(trial.get("ok", false)):
		_fail("Public 100 + 100 trial setup refused unchanged terrain: " + str(trial))
		return
	_mover = _lab.army
	_holder = _lab.opposing_army
	if _mover.combat_units.size() != 100 or _holder.combat_units.size() != 100 or _holder.combat_order != TerrainArmy.CombatOrder.HOLD:
		_fail("Public trial did not deploy two complete teams with enemy HOLD")
		return
	_initial_ids = [[], []]
	for index in range(100):
		_initial_ids[0].append(_mover.combat_identity(index))
		_initial_ids[1].append(_holder.combat_identity(index))
	var fronts := 0
	for row in range(10):
		var a: Vector2i = _mover.cells[row]
		var b: Vector2i = _holder.cells[row]
		fronts += int(absi(a.x - b.x) + absi(a.y - b.y) == 1 and _data.can_attack_across(a, b))
	if fronts != 10 or not _occupied_without_overlap():
		_fail("Public initial fronts are not ten legal adjacent, non-overlapping pairs")
		return
	var origin: Vector2i = _mover.cells[_mover.current_commander]
	var attempts: Array[Dictionary] = []
	var selected := TerrainArmy.INVALID_CELL
	for offset: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1),
		Vector2i(-1, -1), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(0, -2)]:
		var goal := origin + offset
		var preview: Dictionary = _mover.preview_combat_move(goal)
		attempts.append({"goal": [goal.x, goal.y], "preview": str(preview.get("code", "OK"))})
		if not bool(preview.get("ok", false)): continue
		var resolved: Vector2i = preview.get("resolved_anchor", TerrainArmy.INVALID_CELL)
		if absi(resolved.x - origin.x) + absi(resolved.y - origin.y) > 5: continue
		var ordered: Dictionary = _mover.issue_combat_order(_mover.current_commander, TerrainArmy.CombatOrder.MOVE, goal)
		attempts[-1]["order"] = str(ordered.get("code", "OK"))
		if bool(ordered.get("ok", false)):
			selected = goal
			break
	_report["setup_attempts"] = attempts
	if selected == TerrainArmy.INVALID_CELL:
		_fail("No nearby legal commander MOVE was accepted")
		return
	_move_plan = _mover.get_active_move_plan()
	_serial = _mover.get_order_serial()
	if _move_plan == null or _mover.combat_order != TerrainArmy.CombatOrder.MOVE or _move_plan.macro_path.size() > 12:
		_fail("Accepted MOVE did not retain a short original movement plan")
		return
	_report["fixture"] = {"scene": _lab.scene_file_path, "preset": _data.preset, "seed": _data.seed_value,
		"mover_team": _mover.team_id, "holder_team": _holder.team_id,
		"origin": [origin.x, origin.y], "goal": [selected.x, selected.y],
		"macro_path_cells": _move_plan.macro_path.size(), "front_pairs": fronts, "order_serial": _serial,
		"roster_ids": _initial_ids, "gpu": RenderingServer.get_video_adapter_name(), "cpu": OS.get_processor_name()}
	var warmup_start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - warmup_start < 2000000:
		await process_frame
		await RenderingServer.frame_post_draw
		if Time.get_ticks_usec() >= _deadline_us:
			_fail("Setup/warmup reached the internal 140-second deadline")
			return
	if not _capture("before.png"):
		_fail("Rendered before-frame capture failed")
		return
	var initial_exchange := _lab.exchange_count
	var initial_action := _action_seconds()
	var begin_us := Time.get_ticks_usec()
	var previous_us := begin_us
	var input_seconds := 0.0
	var checkpoints: Array[Dictionary] = []
	var next_checkpoint := 10.0
	_lab.set_process(true)
	while Time.get_ticks_usec() - begin_us < int(SECONDS * 1000000.0):
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		_frame_ms.append((now - previous_us) / 1000.0)
		_frame_at.append((now - begin_us) / 1000000.0)
		previous_us = now
		input_seconds += _lab.get_process_delta_time()
		_observe(_frame_at[-1])
		if _frame_at[-1] >= next_checkpoint:
			checkpoints.append({"wall_seconds": _frame_at[-1], "frames": _frame_ms.size(),
				"exchanges": _lab.exchange_count - initial_exchange, "engaging_frames": _engaging_frames,
				"cooldown_engaging_frames": _cooldown_engaging_frames,
				"move_order": _mover.combat_order, "faults": _faults.duplicate()})
			print("MOVE_ENCOUNTER_FORMAL_PROGRESS ", JSON.stringify(checkpoints[-1]))
			next_checkpoint += 10.0
		if now >= _deadline_us:
			_report["checkpoints"] = checkpoints
			_fail("Measurement reached the internal 140-second deadline")
			return
	_lab.set_process(false)
	var wall_seconds := (previous_us - begin_us) / 1000000.0
	var action_seconds := _action_seconds() - initial_action
	await process_frame
	await RenderingServer.frame_post_draw
	var after_capture := _capture("after.png")
	var source_stable := true
	for path: String in SOURCES:
		source_stable = source_stable and FileAccess.get_sha256(path) == _source_hashes[path]
	var windows := _window_report()
	var p95_ms := _percentile(_frame_ms, 0.95)
	var p99_ms := _percentile(_frame_ms, 0.99)
	var all_windows_30fps := true
	for window: Dictionary in windows:
		all_windows_30fps = all_windows_30fps and float(window.fps) >= 30.0
	var action_ratio := action_seconds / wall_seconds
	var gate := {"full_60_wall_seconds": wall_seconds >= SECONDS, "two_original_100_person_rosters": _mover.combat_units.size() == 100 and _holder.combat_units.size() == 100,
		"actual_exchanges": _lab.exchange_count > initial_exchange, "sustained_adjacent_engaging": _max_engage_seconds >= 1.0,
		"engaging_during_cooldown": _cooldown_engaging_frames > 0, "no_physical_overlap": not _faults.has("Physical occupancy or in-flight destination overlapped"),
		"original_order_serial_and_plan": not _faults.has("Original MOVE order serial changed") and not _faults.has("Original MOVE plan was replaced"),
		"original_person_ids": not _faults.has("Original person identities changed") and not _faults.has("Original 100 + 100 roster size changed"),
		"terrain_unchanged": _terrain_unchanged(), "action_clock": absf(input_seconds - action_seconds) <= TerrainLab.EXCHANGE_ACTION_STEP + 0.00001,
		"p95_33_33ms": p95_ms <= 33.33, "p99_50ms": p99_ms <= 50.0, "all_10s_windows_30fps": all_windows_30fps,
		"action_clock_wall_ratio": action_ratio >= 0.99 and action_ratio <= 1.01,
		"source_stable": source_stable, "before_and_after_rendered": after_capture}
	var passed := _faults.is_empty()
	for value: bool in gate.values(): passed = passed and value
	_report.merge({"targets_met": passed, "gate": gate, "faults": _faults, "checkpoints": checkpoints,
		"wall_seconds": wall_seconds, "frames": _frame_ms.size(), "fps": _frame_ms.size() / wall_seconds,
		"p95_ms": p95_ms, "p99_ms": p99_ms,
		"ten_second_windows": windows, "frame_ms": _frame_ms, "frame_at_seconds": _frame_at,
		"action_clock": {"input_seconds": input_seconds, "scene_seconds": action_seconds, "wall_ratio": action_ratio,
			"query_rounds": _lab._exchange_round, "phase_seconds": _lab._exchange_phase,
			"remainder_seconds": _lab._action_time_remainder},
		"exchanges": _lab.exchange_count - initial_exchange, "exchange_results": _lab.exchange_results,
		"engaging_frames": _engaging_frames, "cooldown_engaging_frames": _cooldown_engaging_frames,
		"longest_adjacent_engaging_wall_seconds": _max_engage_seconds,
		"natural_release_at_wall_seconds": _released_at, "natural_ko_at_release": _natural_ko_at_release,
		"natural_continuation_at_wall_seconds": _continued_at,
		"continuation_observed": _continued_at >= 0.0, "source_sha256": _source_hashes}, true)
	if not _write():
		push_error("MOVE_ENCOUNTER_FORMAL could not write final measurements")
		quit(1)
		return
	print("MOVE_ENCOUNTER_FORMAL_RESULT ", JSON.stringify({"output": _output, "targets_met": passed,
		"exchanges": _report.exchanges, "fps": _report.fps, "p95_ms": _report.p95_ms,
		"p99_ms": _report.p99_ms, "continuation_observed": _report.continuation_observed,
		"gate": gate}))
	_lab.queue_free()
	await process_frame
	quit(0 if passed else 1)
