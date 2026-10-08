extends SceneTree
## Real generated map, original UI deployment and normal GPU/main-scene processing.
## Diagnostic, strict 120-second performance, and explicit 30-second smoke modes.
const SECONDS := 120.0
const SMOKE_SECONDS := 30.0
const DEADLINE_SECONDS := 230.0
const SMOKE_DEADLINE_SECONDS := 120.0
const OUT := "res://output/three_faction_ai_20260928/formal_visual"
const PERFORMANCE_OUT := "res://output/site_movement_optimization_20260928/formal_performance"
const SMOKE_OUT := "res://output/site_movement_batch_implementation_20260928/formal_smoke"
const RELEASE_OUT := "user://site_release_evidence/tactical_ai"
const RELEASE_MANIFEST := "site_release_manifest.json"
const SOURCES := ["res://project.godot", "res://scenes/terrain_lab/TerrainLab.tscn",
	"res://scripts/terrain_lab/terrain_lab.gd", "res://scripts/terrain_lab/terrain_army.gd",
	"res://scripts/terrain_lab/terrain_army_batch_view.gd",
	"res://scripts/terrain_lab/terrain_army_shared_visual_source.gd",
	"res://scripts/terrain_lab/site_army_ai.gd", "res://scripts/terrain_lab/site_controller.gd",
	"res://scripts/terrain_lab/formation_destination_planner.gd",
	"res://scripts/terrain_lab/formation_transit_planner.gd",
	"res://scripts/terrain_lab/site_combat_movement_coordinator.gd",
	"res://scripts/terrain_lab/combat_move_plan.gd",
	"res://scripts/terrain_lab/combat_deployment_plan.gd",
	"res://scripts/terrain_lab/combat_movement_types.gd",
	"res://scripts/terrain_lab/formation_movement_profile.gd",
	"res://scripts/terrain_lab/site_movement_reservation_grid.gd",
	"res://scripts/terrain_lab/site_deployment_reservation_registry.gd",
	"res://native/army_idle/army_idle.cpp",
	"res://native/army_idle/movement_core.inc",
	"res://native/army_idle/movement_transit.inc",
	"res://native/army_idle/movement_projection.inc",
	"res://native/army_idle/army_idle.gdextension",
	"res://native/army_idle/bin/army_idle.windows.x86_64.dll",
	"res://scripts/tests/site_tactical_ai_formal_visual_test.gd"]

var lab: TerrainLab
var output := ""
var performance_mode := false
var smoke_mode := false
var release_mode := false
var release_manifest: Dictionary = {}
var deadline_us := 0
var measured_us := 0
var finished := false
var report := {}
var faults: Array[String] = []
var frame_ms: Array[float] = []
var frame_at: Array[float] = []
var frame_action_seconds: Array[float] = []
var frame_pending_seconds: Array[float] = []
var frame_input_seconds: Array[float] = []
var frame_steps: Array[int] = []
var frame_phase: Array[String] = []
var process_delta_seconds: Array[float] = []
var process_delta_at: Array[float] = []
var process_delta_sum := 0.0
var maximum_pending_seconds := 0.0
var snapshots: Array[Dictionary] = []
var initial_ids: Array = []
var previous_cells: Array = []
var observed_steps := [0, 0, 0]
var natural_steps := [0, 0, 0]
var retreat_steps := [0, 0, 0]
var previous_orders := [-1, -1, -1]
var seen_orders: Array[Dictionary] = [{}, {}, {}]
var identities := {}
var actor_identities := {}
var actor_exchanges := 0
var natural_pairs := {}
var natural_participants := {}
var all_pairs := {}
var last_round := -1
var round_pairs := {}
var phase := "setup"
var takeover := {}

func _initialize() -> void:
	assert(OS.get_cmdline_user_args().has("--site-test-ui"), "Tactical AI setup controls require --site-test-ui")
	smoke_mode = "--performance-smoke" in OS.get_cmdline_user_args()
	performance_mode = smoke_mode or ("--performance-mode" in OS.get_cmdline_user_args())
	release_mode = (OS.has_feature("release") and not Engine.is_editor_hint()) \
		or FileAccess.file_exists(OS.get_executable_path().get_base_dir().path_join(RELEASE_MANIFEST))
	if release_mode:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
			OS.get_executable_path().get_base_dir().path_join(RELEASE_MANIFEST)))
		if parsed is Dictionary: release_manifest = parsed
	deadline_us = Time.get_ticks_usec() + int((SMOKE_DEADLINE_SECONDS if smoke_mode else DEADLINE_SECONDS) * 1000000.0)
	var output_root := RELEASE_OUT if release_mode else (SMOKE_OUT if smoke_mode else (PERFORMANCE_OUT if performance_mode else OUT))
	output = "%s/run_%d_%d" % [output_root,
		int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	_run.call_deferred()

func _process(delta: float) -> bool:
	if measured_us > 0 and not finished and is_instance_valid(lab) and lab.is_processing():
		process_delta_seconds.append(delta)
		process_delta_at.append(float(Time.get_ticks_usec() - measured_us) / 1000000.0)
		process_delta_sum += delta
	if not finished and Time.get_ticks_usec() >= deadline_us:
		faults.append("Internal wall-clock deadline exceeded")
		_finish()
	return false

func _source_hashes() -> Dictionary:
	if release_mode: return release_manifest.get("source_hashes", {})
	var hashes := {}
	for path: String in SOURCES: hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _package_hashes() -> Dictionary:
	var hashes := {}
	var files: Dictionary = release_manifest.get("package_files", {})
	var base := OS.get_executable_path().get_base_dir()
	for path: String in files:
		if path.is_absolute_path() or ".." in path.split("/"):
			hashes[path] = ""
		else:
			hashes[path] = FileAccess.get_sha256(base.path_join(path))
	return hashes

func _terrain_hash() -> String:
	var data := lab.terrain
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes([data.height_levels, data.static_blocked, data.ramp_edges, data.flags, data.surface_types]))
	return context.finish().hex_encode()

func _press(button_name: String) -> bool:
	var button := lab.find_child(button_name, true, false) as Button
	if button == null:
		faults.append("Missing original UI button: " + button_name)
		return false
	button.pressed.emit()
	return true

func _capture(filename: String) -> bool:
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(output + "/" + filename) != OK:
		faults.append("Capture failed: " + filename)
		return false
	return true

func _capture_ui(filename: String, options: bool) -> void:
	var ui: SiteController = lab.site_controller
	lab.site_test_window.get("tabs").current_tab = 1
	ui._open_combat_window()
	var available := DisplayServer.screen_get_usable_rect(root.current_screen)
	ui.combat_window.size = Vector2i(mini(available.size.x, root.size.x - 80), mini(available.size.y, root.size.y - 120))
	# Containers settle after the Window resizes; only then position and scroll.
	await process_frame
	await process_frame
	ui.combat_window.position = available.position + (available.size - ui.combat_window.size) / 2
	var ancestor: Node = ui.combat_summary_label.get_parent()
	while ancestor != null and not ancestor is ScrollContainer:
		ancestor = ancestor.get_parent()
	var scroll := ancestor as ScrollContainer
	if scroll == null:
		faults.append("Original combat menu scroll container is unavailable")
	else:
		if options: scroll.scroll_vertical = 0
		else: scroll.ensure_control_visible(ui.combat_summary_label)
	await process_frame
	await RenderingServer.frame_post_draw
	var origin := ui.combat_window.position
	var extent := origin + ui.combat_window.size
	if origin.x < available.position.x or origin.y < available.position.y or extent.x > available.end.x or extent.y > available.end.y:
		faults.append("Native combat menu does not fit within the usable screen")
	report.ui_capture_layouts[filename] = {"position": [origin.x, origin.y],
		"size": [ui.combat_window.size.x, ui.combat_window.size.y],
		"viewport": [ui.combat_window.size.x, ui.combat_window.size.y], "native_window": true, "scroll_vertical": scroll.scroll_vertical if scroll != null else -1,
		"ai_options": options, "team_summary": not options}
	var image := ui.combat_window.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(output + "/" + filename) != OK:
		faults.append("Capture failed: " + filename)
	ui.combat_window.hide()

func _observe() -> void:
	maximum_pending_seconds = maxf(maximum_pending_seconds, lab._action_time_remainder)
	var occupied := {}
	var destinations := {}
	for actor: TerrainTestCharacter in lab.combat_actors:
		if actor.occupies_cell(actor.terrain_cell):
			if occupied.has(actor.terrain_cell): faults.append("Standing actor overlap")
			occupied[actor.terrain_cell] = actor.person_id
	for side in range(3):
		var team: TerrainArmy = lab.combat_armies[side]
		if team.combat_units.size() != 100:
			faults.append("Original 100-person roster changed")
			return
		seen_orders[side][TerrainArmy.CombatOrder.keys()[team.combat_order]] = true
		for index in range(100):
			var identity := team.combat_identity(index)
			if identity != int(initial_ids[side][index]): faults.append("Original person identity changed")
			var cell: Vector2i = team.cells[index]
			var previous: Vector2i = previous_cells[side][index]
			var steps := absi(cell.x - previous.x) + absi(cell.y - previous.y)
			observed_steps[side] += steps
			if phase == "natural": natural_steps[side] += steps
			if team.combat_order == TerrainArmy.CombatOrder.RETREAT and previous_orders[side] == team.combat_order:
				retreat_steps[side] += steps
			previous_cells[side][index] = cell
			# KO/dead rows retain their coordinates but do not own a standing cell.
			if int(team._cell_owners.get(cell, -1)) == index:
				if occupied.has(cell): faults.append("Standing person overlap at " + str(cell))
				occupied[cell] = identity
			var destination: Vector2i = team.moving_to[index]
			if destination != TerrainArmy.INVALID_CELL:
				if destinations.has(destination): faults.append("Duplicate in-flight destination at " + str(destination))
				destinations[destination] = identity
		previous_orders[side] = team.combat_order

func _snapshot(at: float) -> Dictionary:
	var teams: Array[Dictionary] = []
	for side in range(3):
		var team: TerrainArmy = lab.combat_armies[side]
		var hp := 0.0
		var active := 0
		var knocked := 0
		for index in range(team.combat_units.size()):
			hp += float(team.combat_hot_get(index, &"hp", 0.0))
			active += int(team.combat_can_act(index))
			knocked += int(float(team.combat_hot_get(index, &"ko", 0.0)) > 0.0)
		teams.append({"team_id": team.team_id, "faction": team.faction_id,
			"enabled": team.tactical_ai_enabled, "recovering": team.tactical_ai_recovering,
			"status": team.tactical_ai_status, "reason": team.tactical_ai_reason,
			"target_id": team.tactical_ai_target_id, "decisions": team.tactical_ai_decisions,
			"orders": team.tactical_ai_orders, "order": TerrainArmy.CombatOrder.keys()[team.combat_order],
			"order_serial": team.get_order_serial(), "observed_cell_steps": observed_steps[side],
			"natural_cell_steps": natural_steps[side], "moving": team.moving_count(),
			"active": active, "ko": knocked, "hp": hp,
			"reference": [team.command_reference.x, team.command_reference.y],
			"goal": [team.combat_goal.x, team.combat_goal.y]})
	return {"at": at, "phase": phase, "exchange_count": lab.exchange_count, "teams": teams,
		"settled_action_seconds": lab._exchange_round * TerrainLab.EXCHANGE_QUERY_STEP + lab._exchange_phase,
		"pending_action_seconds": lab._action_time_remainder}

func _exchange(a: int, b: int, _outcome: Dictionary) -> void:
	if not identities.has(a) and not actor_identities.has(a) or not identities.has(b) and not actor_identities.has(b):
		faults.append("Exchange contains an unknown person")
		return
	var faction_a := int(identities.get(a, actor_identities.get(a, -1)))
	var faction_b := int(identities.get(b, actor_identities.get(b, -1)))
	if faction_a == faction_b: faults.append("Same-faction exchange")
	if last_round != lab._exchange_round:
		last_round = lab._exchange_round
		round_pairs.clear()
	var person_pair := "%d:%d" % [mini(a, b), maxi(a, b)]
	if round_pairs.has(person_pair): faults.append("Duplicate person pair in one round")
	round_pairs[person_pair] = true
	var key := "%d:%d" % [mini(faction_a, faction_b), maxi(faction_a, faction_b)]
	all_pairs[key] = int(all_pairs.get(key, 0)) + 1
	if actor_identities.has(a) or actor_identities.has(b):
		actor_exchanges += 1
	elif phase == "natural":
		natural_pairs[key] = int(natural_pairs.get(key, 0)) + 1
		natural_participants[faction_a] = true
		natural_participants[faction_b] = true

func _run() -> void:
	report = {"passed": false, "output": output, "scope": "Original TerrainLab.tscn and UI; PLAINS seed 581; 100 + 100 + 100; %d seconds normal GPU process" % [int(SMOKE_SECONDS if smoke_mode else SECONDS)],
		"terrain_edits": false, "person_teleports": false, "health_stimuli": false,
		"manual_ai_result_orders": false, "fps_is_observation_not_existing_performance_closure": not performance_mode,
		"mode": "performance_smoke" if smoke_mode else ("performance" if performance_mode else "diagnostic"),
		"package_mode": "release" if release_mode else "editor_source",
		"full_120s_gate_applies": performance_mode and not smoke_mode,
		"engine_args": OS.get_cmdline_args(), "user_args": OS.get_cmdline_user_args(),
		"engine": Engine.get_version_info(), "cpu": OS.get_processor_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"viewport_pixels": [root.size.x, root.size.y],
		"action_elapsed_source": "TerrainLab consecutive active monotonic frame intervals feed the original retained 30 Hz clock; process_delta_seconds records Godot's original capped delta separately",
		"ui_capture_layouts": {}, "scene_stage_counters_inclusive_not_additive": true}
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) != OK:
		push_error("Cannot create tactical AI evidence folder")
		quit(1)
		return
	if DisplayServer.get_name() == "headless" or ProjectSettings.get_setting("application/run/main_scene") != "res://scenes/terrain_lab/TerrainLab.tscn":
		faults.append("Original GPU main scene required")
		_finish()
		return
	root.size = Vector2i(1800, 1100)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	report.viewport_pixels = [root.size.x, root.size.y]
	if not is_equal_approx(Engine.time_scale, 1.0):
		faults.append("Engine time scale must remain 1.0")
		_finish()
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	report.source_hashes_before = _source_hashes()
	if release_mode:
		report["release_manifest_sha256_before"] = FileAccess.get_sha256(
			OS.get_executable_path().get_base_dir().path_join(RELEASE_MANIFEST))
		report["package_hashes_before"] = _package_hashes()
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	lab = scene.instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.combat_profile_enabled = not performance_mode
	var ui: SiteController = lab.site_controller
	ui._auto_save_blocked = true
	ui.save_path = output + "/isolated_ui_save.json"
	lab.generate_terrain(TerrainPreset.Kind.PLAINS, 581)
	ui._auto_save_blocked = true # Normal Generate archived only the isolated fresh startup.
	if lab.terrain.preset != TerrainPreset.Kind.PLAINS or lab.terrain.seed_value != 581:
		faults.append("Normal Generate button refused PLAINS seed 581: " + ui.message.text)
		_finish()
		return
	report.terrain_hash_before = _terrain_hash()
	report.navigation_revision_before = lab.terrain.navigation_revision
	ui.trial_third_enabled.button_pressed = true
	ui.trial_third_faction.select(2)
	for prefix: String in ["friendly", "enemy", "third"]:
		ui.trial_roles[prefix].select(0)
		ui._trial_role_changed(prefix)
		ui.trial_ai_enabled[prefix].button_pressed = true
	for count: SpinBox in [ui.trial_friendly_count, ui.trial_enemy_count, ui.trial_third_count]: count.value = 100
	# Keep normal west/east/north entry edges. Three adjacent equal armies would
	# rationally assess two hostile forces at once and all choose withdrawal.
	report.ui_setup = ui._trial_setup()
	_press("StartMeleeTrial")
	for side in range(3):
		var team: TerrainArmy = lab.combat_armies[side]
		if not team.has_army() or team.combat_units.size() != 100 or not team.tactical_ai_enabled or team.faction_id != side:
			faults.append("Normal UI did not deploy three independent AI armies: " + ui.message.text)
			_finish()
			return
		team.combat_profile_enabled = not performance_mode
		team.combat_profile_usec.clear()
		var ids: Array[int] = []
		for index in range(100):
			var identity := team.combat_identity(index)
			if identities.has(identity): faults.append("Duplicate deployed person identity")
			identities[identity] = team.faction_id
			ids.append(identity)
		initial_ids.append(ids)
		previous_cells.append(team.cells.duplicate())
	report.initial_person_ids = initial_ids
	report.initial_cells = previous_cells.duplicate(true)
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor_identities[actor.person_id] = actor.faction_id
	report["separate_actors"] = actor_identities
	lab.exchange_resolved.connect(_exchange)
	assert(not lab.has_node("TerrainLabUI"), "Legacy debug panel must not be constructed")
	if is_instance_valid(lab.site_test_window): lab.site_test_window.hide()
	ui.panel.hide()
	await _capture_ui("ui_options_before.png", true)
	await _capture_ui("ui_summary_before.png", false)
	ui.status_panel.hide()
	lab.camera.zoom = Vector2.ONE * 0.15
	lab.camera.position = Vector2(lab.terrain.size) * TerrainRenderer.CELL_PIXELS * 0.5 + Vector2(260.0 / lab.camera.zoom.x, 0.0)
	lab.camera.force_update_scroll()
	for _frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	_capture("before.png")
	phase = "natural"
	snapshots.append(_snapshot(0.0))
	measured_us = Time.get_ticks_usec()
	report["action_seconds_before"] = lab._exchange_round * TerrainLab.EXCHANGE_QUERY_STEP + lab._exchange_phase
	report["pending_seconds_before"] = lab._action_time_remainder
	report["engine_before"] = {"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"max_physics_steps_per_frame": Engine.max_physics_steps_per_frame, "time_scale": Engine.time_scale}
	lab.combat_profile_usec.clear()
	lab.combat_movement_coordinator.profile_enabled = not performance_mode
	lab.combat_movement_coordinator.profile_usec.clear()
	lab.action_elapsed_input_sum = 0.0
	lab.action_elapsed_input_count = 0
	lab.action_elapsed_measure_enabled = performance_mode
	report["measurement_mode_before"] = _mode_state()
	var previous_us := measured_us
	var previous_action := float(report.action_seconds_before)
	var next_snapshot := 0.5
	var next_progress := 10.0
	var middle_captured := false
	lab.set_process(true)
	while not finished and Time.get_ticks_usec() - measured_us < int((SMOKE_SECONDS if smoke_mode else SECONDS) * 1000000.0):
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var at := float(now - measured_us) / 1000000.0
		frame_ms.append(float(now - previous_us) / 1000.0)
		frame_at.append(at)
		previous_us = now
		if performance_mode:
			var action_now := lab._exchange_round * TerrainLab.EXCHANGE_QUERY_STEP + lab._exchange_phase
			frame_action_seconds.append(action_now)
			frame_pending_seconds.append(lab._action_time_remainder)
			frame_input_seconds.append(lab.action_elapsed_input_sum)
			frame_steps.append(maxi(0, roundi((action_now - previous_action) / TerrainLab.EXCHANGE_ACTION_STEP)))
			frame_phase.append(phase)
			previous_action = action_now
		_observe()
		if not faults.is_empty():
			_finish()
			return
		if at >= next_snapshot:
			snapshots.append(_snapshot(at))
			next_snapshot += 0.5
		if at >= next_progress:
			print("TACTICAL_AI_FORMAL_PROGRESS ", JSON.stringify(snapshots.back()))
			next_progress += 10.0
		if at >= 60.0 and not middle_captured and not performance_mode:
			_capture("natural_60s.png")
			middle_captured = true
		if phase == "natural" and at >= 90.0:
			takeover["at"] = at
			takeover["before"] = _snapshot(at)
			phase = "manual_hold"
			for side in range(3):
				ui.trial_command_team.select(side)
				_press("TrialTeamHold")
				var team: TerrainArmy = lab.combat_armies[side]
				if team.tactical_ai_enabled or team.combat_order != TerrainArmy.CombatOrder.HOLD:
					faults.append("Manual HOLD did not take over faction " + str(side))
			takeover["held"] = _snapshot(at)
			if not performance_mode: _capture("manual_hold.png")
		elif phase == "manual_hold" and at >= float(takeover.at) + 1.0:
			for side in range(3):
				var team: TerrainArmy = lab.combat_armies[side]
				if team.tactical_ai_enabled or team.tactical_ai_decisions != int(takeover.held.teams[side].decisions):
					faults.append("Manual HOLD was overridden by AI faction " + str(side))
				ui.trial_command_team.select(side)
				_press("TrialTeamAIEnable")
				if not team.tactical_ai_enabled: faults.append("AI resume rejected faction " + str(side))
			phase = "resumed_ai"
			takeover["resumed_at"] = at
			takeover["resumed"] = _snapshot(at)
	if finished: return
	lab.set_process(false)
	ui._update_combat_window()
	await process_frame
	await RenderingServer.frame_post_draw
	_capture("after.png")
	await _capture_ui("ui_options_after.png", true)
	await _capture_ui("ui_summary_after.png", false)
	_finish()

func _mode_state() -> Dictionary:
	var army_profiles: Array[bool] = []
	for team: TerrainArmy in lab.combat_armies:
		army_profiles.append(team.combat_profile_enabled)
	return {"lab_profile_enabled": lab.combat_profile_enabled,
		"coordinator_profile_enabled": lab.combat_movement_coordinator.profile_enabled,
		"army_profile_enabled": army_profiles,
		"accepted_input_measure_enabled": lab.action_elapsed_measure_enabled,
		"vsync": DisplayServer.window_get_vsync_mode(), "fps_cap": Engine.max_fps,
		"window_pixels": [root.size.x, root.size.y]}

func _performance_windows() -> Array[Dictionary]:
	var windows: Array[Dictionary] = []
	var previous_index := -1
	var previous_at := 0.0
	var previous_action := float(report.action_seconds_before)
	var previous_pending := float(report.pending_seconds_before)
	var previous_input := 0.0
	for window in range(3 if smoke_mode else 12):
		var end_index := -1
		for index in range(previous_index + 1, frame_at.size()):
			if frame_at[index] >= float(window + 1) * 10.0:
				end_index = index
				break
		if end_index < 0:
			windows.append({"window": window, "complete": false})
			continue
		var elapsed := frame_at[end_index] - previous_at
		var values: Array[float] = []
		var pending_peak := previous_pending
		var steps := 0
		for index in range(previous_index + 1, end_index + 1):
			values.append(frame_ms[index])
			pending_peak = maxf(pending_peak, frame_pending_seconds[index])
			steps += frame_steps[index]
		values.sort()
		var action_delta := frame_action_seconds[end_index] - previous_action
		var pending_delta := frame_pending_seconds[end_index] - previous_pending
		var input_delta := frame_input_seconds[end_index] - previous_input
		var hold_exempt := takeover.has("resumed_at") and previous_at < float(takeover.resumed_at) and frame_at[end_index] > float(takeover.at)
		windows.append({"window": window, "complete": true, "start_at": previous_at,
			"end_at": frame_at[end_index], "frame_count": values.size(),
			"fps": values.size() / elapsed if elapsed > 0.0 else 0.0,
			"p95_ms": values[clampi(ceili(values.size() * 0.95) - 1, 0, values.size() - 1)],
			"p99_ms": values[clampi(ceili(values.size() * 0.99) - 1, 0, values.size() - 1)],
			"action_ratio": action_delta / elapsed if elapsed > 0.0 else 0.0,
			"action_seconds": action_delta, "pending_change_seconds": pending_delta,
			"accepted_input_seconds": input_delta,
			"input_conservation_error": input_delta - action_delta - pending_delta,
			"pending_peak_seconds": pending_peak, "steps": steps,
			"manual_hold_clock_exempt": hold_exempt})
		previous_index = end_index
		previous_at = frame_at[end_index]
		previous_action = frame_action_seconds[end_index]
		previous_pending = frame_pending_seconds[end_index]
		previous_input = frame_input_seconds[end_index]
	return windows

func _percentile(fraction: float) -> float:
	if frame_ms.is_empty(): return -1.0
	var ordered := frame_ms.duplicate()
	ordered.sort()
	return ordered[clampi(ceili(ordered.size() * fraction) - 1, 0, ordered.size() - 1)]

func _valid_hash(value: Variant) -> bool:
	var digest := str(value)
	return digest.length() == 64 and digest.is_valid_hex_number()

func _finish() -> void:
	if finished: return
	finished = true
	if is_instance_valid(lab): lab.set_process(false)
	var wall: float = frame_at.back() if not frame_at.is_empty() else 0.0
	report["wall_seconds"] = wall
	report["frame_ms"] = frame_ms
	report["frame_at"] = frame_at
	if performance_mode:
		report["frame_action_seconds"] = frame_action_seconds
		report["frame_pending_seconds"] = frame_pending_seconds
		report["frame_accepted_input_seconds"] = frame_input_seconds
		report["frame_steps"] = frame_steps
		report["frame_phase"] = frame_phase
	report["process_delta_seconds"] = process_delta_seconds
	report["process_delta_at"] = process_delta_at
	report["process_delta_sum"] = process_delta_sum
	report["snapshots"] = snapshots
	report["natural_pairs"] = natural_pairs
	report["natural_participants"] = natural_participants.keys()
	report["all_pairs"] = all_pairs
	report["separate_actor_exchanges"] = actor_exchanges
	report["seen_orders"] = seen_orders
	report["observed_cell_steps"] = observed_steps
	report["natural_cell_steps"] = natural_steps
	report["retreat_cell_steps"] = retreat_steps
	report["step_measurement"] = "Per rendered frame net Manhattan cell changes; a lower bound if a frame spans several completed edges"
	report["manual_takeover"] = takeover
	report["fps"] = frame_ms.size() / wall if wall > 0.0 else 0.0
	report["p95_ms"] = _percentile(0.95)
	report["p99_ms"] = _percentile(0.99)
	report["max_ms"] = frame_ms.max() if not frame_ms.is_empty() else 0.0
	report["source_hashes_after"] = _source_hashes()
	var gates := {"source_stable": report.get("source_hashes_before", {}) == report.source_hashes_after,
		"each_faction_physically_moved": natural_steps[0] > 0 and natural_steps[1] > 0 and natural_steps[2] > 0}
	if release_mode:
		var expected: Dictionary = release_manifest.get("package_files", {})
		var actual: Dictionary = report.get("package_hashes_before", {})
		report["package_hashes_after"] = _package_hashes()
		report["release_manifest_sha256_after"] = FileAccess.get_sha256(
			OS.get_executable_path().get_base_dir().path_join(RELEASE_MANIFEST))
		gates["release_build_flags"] = OS.has_feature("release") and not OS.has_feature("debug") \
			and not OS.has_feature("editor")
		gates["release_package_complete"] = not expected.is_empty() and expected == actual \
			and actual == report.package_hashes_after and not str(report.release_manifest_sha256_before).is_empty() \
			and report.release_manifest_sha256_before == report.release_manifest_sha256_after
	if smoke_mode:
		gates["smoke_window_30s"] = wall >= SMOKE_SECONDS and wall < SECONDS
		report["smoke_coverage"] = {"natural_exchanges_observed": not natural_pairs.is_empty(),
			"natural_participants": natural_participants.keys(), "retreat_steps": retreat_steps,
			"manual_takeover_reached": takeover.has("resumed")}
	else:
		gates["full_window"] = wall >= SECONDS
		gates["three_natural_participants"] = natural_participants.size() == 3
		gates["natural_exchanges"] = not natural_pairs.is_empty()
		gates["each_faction_physically_retreated"] = retreat_steps[0] > 0 and retreat_steps[1] > 0 and retreat_steps[2] > 0
		gates["manual_takeover_and_resume"] = takeover.has("resumed")
	if is_instance_valid(lab):
		report["engine_after"] = {"physics_ticks_per_second": Engine.physics_ticks_per_second,
			"max_physics_steps_per_frame": Engine.max_physics_steps_per_frame, "time_scale": Engine.time_scale}
		report["scene_stage_usec"] = lab.combat_profile_usec.duplicate()
		report["coordinator_stage_usec"] = lab.combat_movement_coordinator.profile_usec.duplicate()
		report["action_seconds_after"] = lab._exchange_round * TerrainLab.EXCHANGE_QUERY_STEP + lab._exchange_phase
		report["pending_seconds_after"] = lab._action_time_remainder
		report["maximum_pending_seconds"] = maximum_pending_seconds
		report["measurement_mode_after"] = _mode_state()
		report["accepted_input_seconds"] = lab.action_elapsed_input_sum
		report["accepted_input_callbacks"] = lab.action_elapsed_input_count
		lab.action_elapsed_measure_enabled = false
		report["action_clock_ratio"] = (float(report.action_seconds_after) - float(report.get("action_seconds_before", 0.0))) / wall if wall > 0.0 else 0.0
		gates["normal_action_clock"] = absf(float(report.action_clock_ratio) - 1.0) <= 0.05
		gates["no_second_long_frame"] = float(report.max_ms) < 1000.0
		report["terrain_hash_after"] = _terrain_hash()
		report["navigation_revision_after"] = lab.terrain.navigation_revision
		gates["terrain_unchanged"] = report.get("terrain_hash_before", "") == report.terrain_hash_after \
			and report.get("navigation_revision_before", -1) == report.navigation_revision_after
		report["final"] = _snapshot(wall)
		report["final_people"] = []
		report["army_profiles"] = []
		gates["each_faction_issued_ai_order"] = true
		if not smoke_mode: gates["each_faction_resumed_decisions"] = takeover.has("resumed")
		for side in range(lab.combat_armies.size()):
			var team: TerrainArmy = lab.combat_armies[side]
			report.army_profiles.append({"faction": team.faction_id, "stage_usec": team.combat_profile_usec.duplicate(),
				"route_calls": team.route_calls, "expanded_nodes": team.expanded_nodes, "direct_route_hits": team.direct_route_hits})
			var rows: Array[Dictionary] = []
			for index in range(team.combat_units.size()):
				var cell := team.cells[index]
				var slot := team.combat_slots[index]
				var destination := team.moving_to[index]
				rows.append({"id": team.combat_identity(index), "member": team.is_member(index),
					"can_act": team.combat_can_act(index), "hp": float(team.combat_hot_get(index, &"hp", 0.0)),
					"ko": float(team.combat_hot_get(index, &"ko", 0.0)), "cell": [cell.x, cell.y],
					"combat_slot": [slot.x, slot.y], "moving_to": [destination.x, destination.y],
					"owns_standing_cell": int(team._cell_owners.get(cell, -1)) == index})
			report.final_people.append({"team_id": team.team_id, "faction": team.faction_id, "rows": rows})
			gates.each_faction_issued_ai_order = bool(gates.each_faction_issued_ai_order) and team.tactical_ai_orders > 0
			if not smoke_mode and takeover.has("resumed"):
				gates.each_faction_resumed_decisions = bool(gates.each_faction_resumed_decisions) and team.tactical_ai_decisions > int(takeover.resumed.teams[side].decisions)
	if performance_mode and is_instance_valid(lab) and report.has("measurement_mode_before") and not frame_at.is_empty():
		var hashes_before: Dictionary = report.get("source_hashes_before", {})
		var hashes_after: Dictionary = report.source_hashes_after
		var hashes_complete := (hashes_before.size() >= SOURCES.size() and hashes_after.size() >= SOURCES.size()) \
			if release_mode else (hashes_before.size() == SOURCES.size() and hashes_after.size() == SOURCES.size())
		for path: String in SOURCES:
			hashes_complete = hashes_complete and _valid_hash(hashes_before.get(path, "")) and _valid_hash(hashes_after.get(path, ""))
		var mode_before: Dictionary = report.measurement_mode_before
		var mode_after: Dictionary = report.measurement_mode_after
		var profiles_disabled := not bool(mode_before.lab_profile_enabled) and not bool(mode_before.coordinator_profile_enabled) \
			and not bool(mode_after.lab_profile_enabled) and not bool(mode_after.coordinator_profile_enabled)
		for flags: Array in [mode_before.army_profile_enabled, mode_after.army_profile_enabled]:
			profiles_disabled = profiles_disabled and flags.size() == 3
			for enabled: bool in flags:
				profiles_disabled = profiles_disabled and not enabled
		var expected_arg := "--performance-smoke" if smoke_mode else "--performance-mode"
		var args_clean: bool = OS.get_cmdline_user_args().size() == 1 and OS.get_cmdline_user_args()[0] == expected_arg
		for forbidden: String in ["--debug", "--profiling", "--gpu-profile", "--gpu-validation", "--editor", "--fixed-fps"]:
			args_clean = args_clean and forbidden not in OS.get_cmdline_args()
		var settled := float(report.action_seconds_after) - float(report.action_seconds_before)
		var pending_change := float(report.pending_seconds_after) - float(report.pending_seconds_before)
		var input_error := float(report.accepted_input_seconds) - settled - pending_change
		report["input_conservation_error"] = input_error
		report["performance_windows"] = _performance_windows()
		var spikes: Array[Dictionary] = []
		var over_33 := 0
		var over_50 := 0
		var over_100 := 0
		var over_1000 := 0
		for index in range(frame_ms.size()):
			var ms := frame_ms[index]
			over_33 += int(ms > 33.33)
			over_50 += int(ms > 50.0)
			over_100 += int(ms > 100.0)
			over_1000 += int(ms >= 1000.0)
			if ms > 100.0:
				spikes.append({"at": frame_at[index], "frame_ms": ms, "action_steps": frame_steps[index],
					"pending_seconds": frame_pending_seconds[index], "phase": frame_phase[index]})
		report["frame_counts_over_threshold"] = {"33_33_ms": over_33, "50_ms": over_50,
			"100_ms": over_100, "1000_ms_or_more": over_1000}
		report["frames_over_100ms"] = spikes
		gates["performance_mode_flags"] = profiles_disabled and args_clean and bool(mode_before.accepted_input_measure_enabled) \
			and bool(mode_after.accepted_input_measure_enabled) and mode_before.vsync == DisplayServer.VSYNC_DISABLED \
			and int(mode_before.fps_cap) == 0 and mode_after.window_pixels == mode_before.window_pixels \
			and report.viewport_pixels == mode_before.window_pixels
		report["render_identity_after"] = {"gpu": RenderingServer.get_video_adapter_name(),
			"renderer": RenderingServer.get_current_rendering_method(),
			"driver": RenderingServer.get_current_rendering_driver_name()}
		gates["render_identity_stable"] = report.gpu == report.render_identity_after.gpu \
			and report.renderer == report.render_identity_after.renderer \
			and report.driver == report.render_identity_after.driver
		gates["complete_evidence_hashes"] = hashes_complete and _valid_hash(report.get("terrain_hash_before", "")) \
			and _valid_hash(report.get("terrain_hash_after", ""))
		gates["accepted_input_conserved"] = absf(input_error) <= 0.0001 and int(report.accepted_input_callbacks) >= frame_at.size() - 1
		gates["performance_smoke_window_clock" if smoke_mode else "performance_full_window_clock"] = \
			float(report.action_clock_ratio) >= 0.99 and float(report.action_clock_ratio) <= 1.01
		gates["performance_p95"] = float(report.p95_ms) <= 33.33
		gates["performance_p99"] = float(report.p99_ms) <= 50.0
		gates["performance_pending_peak"] = maximum_pending_seconds <= 0.25
		gates["performance_pending_end"] = float(report.pending_seconds_after) >= -TerrainLab.ACTION_TIME_EPSILON \
			and float(report.pending_seconds_after) < TerrainLab.EXCHANGE_ACTION_STEP + TerrainLab.ACTION_TIME_EPSILON
		gates["performance_no_second_long_frame"] = over_1000 == 0
		for window: Dictionary in report.performance_windows:
			var name := str(window.window)
			gates["performance_fps_10s_" + name] = bool(window.complete) and float(window.get("fps", 0.0)) >= 30.0
			gates["performance_input_10s_" + name] = bool(window.complete) and absf(float(window.get("input_conservation_error", 1.0))) <= 0.0001
			gates["performance_clock_10s_" + name] = bool(window.complete) and (bool(window.get("manual_hold_clock_exempt", false)) \
				or (float(window.get("action_ratio", 0.0)) >= 0.99 and float(window.get("action_ratio", 0.0)) <= 1.01))
	for gate: String in gates:
		if not bool(gates[gate]) and not faults.has("Gate failed: " + gate): faults.append("Gate failed: " + gate)
	report["gates"] = gates
	report["faults"] = faults
	report["passed"] = faults.is_empty()
	var file := FileAccess.open(output + "/measurements.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	else:
		faults.append("Could not write measurements")
	print("SITE_TACTICAL_AI_SMOKE_" if smoke_mode else "SITE_TACTICAL_AI_FORMAL_",
		"PASS" if faults.is_empty() else "FAIL", " ",
		JSON.stringify({"output": output, "gates": gates, "faults": faults, "wall_seconds": wall, "fps": report.fps}))
	if is_instance_valid(lab): lab.queue_free()
	quit(0 if faults.is_empty() else 1)
