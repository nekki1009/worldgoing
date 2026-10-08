extends SceneTree

# Original TerrainLab, generated terrain, public trial/order, and rendered owner frames.
const LAB_SCENE = preload("res://scenes/terrain_lab/TerrainLab.tscn")
const Transit = preload("res://scripts/terrain_lab/formation_transit_planner.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const MEMBERS := 100
const PEAK := Vector2i(49, 37)
const BLOCK_ROUTE_INDEX := 10
const BLOCK_CELL := Vector2i(77, 16)
const MEASURE_SECONDS := 60.0
const CONTACT_DEADLINE_SECONDS := 10.0
const RELEASE_AFTER_CONTACT_SECONDS := 2.0
const WARMUP_FRAMES := 60
const OUTPUT_ROOT := "res://output/site_move_formal_visual"
const SOURCE_PATHS := [
	"res://scripts/terrain_lab/terrain_lab.gd",
	"res://scripts/terrain_lab/terrain_army.gd",
	"res://scripts/terrain_lab/terrain_test_character.gd",
	"res://scripts/terrain_lab/site_combat_movement_coordinator.gd",
	"res://scripts/terrain_lab/site_movement_reservation_grid.gd",
]

var _lab: TerrainLab
var _army: TerrainArmy
var _move_plan: CombatMovePlan
var _deployment_plan: CombatDeploymentPlan
var _serial := 0
var _stage := TerrainArmy.INVALID_CELL
var _release_exit := TerrainArmy.INVALID_CELL
var _block_cell := TerrainArmy.INVALID_CELL
var _out := ""
var _report: Dictionary = {}
var _frame_ms: Array[float] = []
var _frame_at: Array[float] = []
var _previous_cells: Array[Vector2i] = []
var _blocked_frames := 0
var _blocked_near_member_frames := 0
var _invalid_member_proposals := 0
var _physical_steps_after_release := 0
var _release_complete := false

func _initialize() -> void:
	_out = "%s/run_%d_%d" % [OUTPUT_ROOT, int(Time.get_unix_time_from_system()), OS.get_process_id()]
	_report = {"status": "SETUP", "scene": "res://scenes/terrain_lab/TerrainLab.tscn",
		"preset": "TERRACED_HIGHLAND", "seed": 12345, "friendly_count": MEMBERS,
		"enemy_count": MEMBERS, "goal": str(PEAK), "block_cell": "unselected",
		"block_route_index": -1, "block_selection_rule": "accepted production macro_path[10] must equal (77,16), be free and within six cells of original friendly front, with a legal two-way Player staging edge",
		"measurement_seconds_declared": MEASURE_SECONDS,
		"contact_deadline_seconds_declared": CONTACT_DEADLINE_SECONDS,
		"release_after_contact_seconds_declared": RELEASE_AFTER_CONTACT_SECONDS,
		"release_exit_order_declared": ["right", "down", "left", "up"],
		"warmup_frames_declared": WARMUP_FRAMES, "terrain_edits": false,
		"manual_combat_advance": false, "measurement_player_teleport": false,
		"frame_ms": _frame_ms, "frame_at": _frame_at,
		"fps_targets": {"average_min": 30.0, "p95_ms_max": 33.334,
			"p99_ms_max": 50.0, "each_10s_window_min": 30.0,
			"action_clock_ratio_min": 0.99, "action_clock_ratio_max": 1.01}}
	call_deferred("_run")

func _fail(reason: String) -> bool:
	_report["status"] = "FAIL"
	_report["failure"] = reason
	_report["blocked_frames"] = _blocked_frames
	_report["blocked_near_member_frames"] = _blocked_near_member_frames
	_report["invalid_member_proposals"] = _invalid_member_proposals
	_report["physical_steps_after_release"] = _physical_steps_after_release
	_write()
	push_error("SITE_MOVE_FORMAL_VISUAL_FAIL " + reason + " output=" + _out)
	if is_instance_valid(_lab):
		_lab.queue_free()
	quit(1)
	return false

func _write() -> void:
	_report["frame_ms"] = _frame_ms
	_report["frame_at"] = _frame_at
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("Cannot create formal MOVE evidence directory: " + str(error))
		return
	var file := FileAccess.open(_out + "/measurements.json", FileAccess.WRITE)
	if file == null:
		push_error("Cannot write formal MOVE evidence: " + str(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()

func _clock() -> float:
	return _lab._exchange_round * TerrainLab.EXCHANGE_QUERY_STEP + _lab._exchange_phase + _lab._action_time_remainder

func _source_hashes() -> Dictionary:
	var hashes := {}
	for path: String in SOURCE_PATHS:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _visible_soldiers() -> int:
	var visible := 0
	for team: TerrainArmy in [_lab.army, _lab.opposing_army]:
		for sprite: Sprite2D in team._sprites:
			if sprite != null and sprite.is_visible_in_tree() and sprite.texture != null:
				visible += 1
		if team._batch_view != null:
			visible += team._batch_view.rendered_count
	return visible

func _find_distant_enemy_spawn(friendly: Array[Vector2i], route: Array[Vector2i]) -> Vector2i:
	var protected := {}
	var anchors: Array[Vector2i] = friendly.duplicate()
	anchors.append_array(route)
	for anchor: Vector2i in anchors:
		for dx in range(-16, 17):
			for dy in range(-16 + absi(dx), 17 - absi(dx)):
				protected[anchor + Vector2i(dx, dy)] = true
	for y in range(_lab.terrain.size.y - 10, 0, -1):
		for x in range(_lab.terrain.size.x - 10, 0, -1):
			var anchor := Vector2i(x, y)
			var cells: Array[Vector2i] = _lab._melee_trial_formation(anchor, MEMBERS, false)
			if _lab._melee_trial_formation_legal(cells, protected):
				return anchor
	return TerrainArmy.INVALID_CELL

func _find_stage(block_cell: Vector2i) -> Vector2i:
	# Fixed search order; the chosen route cell stays frozen after command setup.
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		var cell := block_cell + direction
		if _lab.terrain.can_step(cell, block_cell) and _lab.terrain.can_step(block_cell, cell) \
			and _lab.character.can_enter_cell(cell) \
			and not _lab.army.blocks_cell(cell) and not _lab.opposing_army.blocks_cell(cell):
			return cell
	return TerrainArmy.INVALID_CELL

func _select_blocker() -> bool:
	var path: Array[Vector2i] = _move_plan.macro_path
	var exact_path_cell := path.size() > BLOCK_ROUTE_INDEX and path[BLOCK_ROUTE_INDEX] == BLOCK_CELL
	var free := _lab.terrain.is_walkable(BLOCK_CELL) and not _army.blocks_cell(BLOCK_CELL) \
		and not _lab.opposing_army.blocks_cell(BLOCK_CELL) and _lab.character.can_enter_cell(BLOCK_CELL)
	var nearest_member_distance := 999999
	var front_neighbor := TerrainArmy.INVALID_CELL
	for source: Vector2i in _army.cells:
		var distance := absi(source.x - BLOCK_CELL.x) + absi(source.y - BLOCK_CELL.y)
		if distance < nearest_member_distance:
			nearest_member_distance = distance
			front_neighbor = source
	var staging := _find_stage(BLOCK_CELL)
	_report["blocker_preflight"] = {"accepted_path_index_matches": exact_path_cell,
		"route_cell_free": free, "nearest_original_member_distance": nearest_member_distance,
		"nearest_original_member_cell": str(front_neighbor), "two_way_player_stage": str(staging)}
	if not exact_path_cell or not free or nearest_member_distance < 1 or nearest_member_distance > 6 \
		or staging == TerrainArmy.INVALID_CELL:
		return false
	_block_cell = BLOCK_CELL
	_stage = staging
	_report["block_cell"] = str(BLOCK_CELL)
	_report["block_route_index"] = BLOCK_ROUTE_INDEX
	_report["player_stage"] = str(staging)
	_report["predeclared_release_candidate"] = str(staging)
	_report["predeclared_release_direction"] = str(staging - BLOCK_CELL)
	return true

func _first_cells(path: Array[Vector2i]) -> Array[String]:
	var result: Array[String] = []
	for index in range(mini(20, path.size())):
		result.append(str(path[index]))
	return result

func _release_player() -> bool:
	var attempts: Array[Dictionary] = []
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		var exit_cell := _block_cell + direction
		var reason := ""
		if not _lab.terrain.can_step(_block_cell, exit_cell):
			reason = "terrain_edge_illegal"
		elif _army.blocks_cell(exit_cell):
			reason = "friendly_occupied_or_claimed"
		elif _lab.opposing_army.blocks_cell(exit_cell):
			reason = "enemy_occupied_or_claimed"
		elif not _lab.character.can_enter_cell(exit_cell):
			reason = "actor_entry_refused"
		elif not _lab.character.step(direction):
			reason = "owner_step_refused"
		attempts.append({"direction": str(direction), "cell": str(exit_cell),
			"result": "accepted" if reason.is_empty() else reason})
		if reason.is_empty():
			_release_exit = exit_cell
			_report["release_exit_cell"] = str(exit_cell)
			_report["release_exit_attempts"] = attempts
			return true
	_report["release_exit_attempts"] = attempts
	_report["release_failure_reason"] = "No legal adjacent Player.step exit in declared right/down/left/up order"
	return false

func _observe(phase: String) -> bool:
	if _army.get_active_move_plan() != _move_plan or _army.get_active_deployment_plan() != _deployment_plan \
		or _army.get_order_serial() != _serial or _army.combat_order != TerrainArmy.CombatOrder.MOVE:
		return _fail("Accepted MOVE plan/serial changed during " + phase)
	var player := _lab.character
	var grid := _lab.combat_movement_coordinator.movement_reservation_grid
	if player.occupies_cell(_block_cell) and grid.blocked_destinations.has(_block_cell):
		_blocked_frames += 1
		for cell: Vector2i in _army.cells:
			if absi(cell.x - _block_cell.x) + absi(cell.y - _block_cell.y) == 1:
				_blocked_near_member_frames += 1
				break
	for proposal in grid.proposals:
		if proposal.status == Types.MoveProposalStatus.REJECTED_INVALID_MEMBER:
			_invalid_member_proposals += 1
			return _fail("Reservation grid produced REJECTED_INVALID_MEMBER during " + phase)
	for team: TerrainArmy in [_army, _lab.opposing_army]:
		for index in range(team.cells.size()):
			if player.occupies_cell(team.cells[index]) or (team.moving_to[index] != TerrainArmy.INVALID_CELL and player.occupies_cell(team.moving_to[index])):
				return _fail("Player and army occupied or claimed the same cell during " + phase)
	if _release_complete:
		for index in range(_army.cells.size()):
			if _army.cells[index] != _previous_cells[index]:
				_physical_steps_after_release += 1
	_previous_cells = _army.cells.duplicate()
	return true

func _p(sorted: Array[float], fraction: float) -> float:
	return sorted[ceili(sorted.size() * fraction) - 1] if not sorted.is_empty() else -1.0

func _run() -> void:
	var output_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	if output_error != OK and output_error != ERR_ALREADY_EXISTS:
		_fail("Cannot create output directory: " + str(output_error))
		return
	if DisplayServer.get_name() == "headless":
		_fail("Real GPU window required")
		return
	if ProjectSettings.get_setting("application/run/main_scene") != "res://scenes/terrain_lab/TerrainLab.tscn":
		_fail("Project main scene differs from formal TerrainLab")
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	_report["source_hashes_start"] = _source_hashes()
	_report["gpu"] = RenderingServer.get_video_adapter_name()
	_report["renderer"] = RenderingServer.get_current_rendering_method()
	_report["driver"] = RenderingServer.get_current_rendering_driver_name()
	_report["cpu"] = OS.get_processor_name()
	_lab = LAB_SCENE.instantiate() as TerrainLab
	_lab.pause_when_unfocused = false
	root.add_child(_lab)
	current_scene = _lab
	_lab.set_process(false)
	var data := TerrainGenerator.generate(TerrainPreset.Kind.TERRACED_HIGHLAND, 12345)
	SiteEnvironment.initialize(data, "formal-move-visual-fixture")
	_lab.bind_terrain(data)
	if _lab.terrain != data or data.preset != TerrainPreset.Kind.TERRACED_HIGHLAND or data.seed_value != 12345 or not data.is_walkable(PEAK):
		_fail("Fresh formal mountain terrain is unavailable")
		return
	_report["terrain_fingerprint_start"] = data.fingerprint()
	var original_static: PackedByteArray = data.static_blocked.duplicate()
	_report["navigation_revision_start"] = data.navigation_revision
	var default_layout: Dictionary = _lab.find_melee_trial_layout(MEMBERS, MEMBERS)
	if default_layout.is_empty():
		_fail("No legal original 100-person friendly formation")
		return
	var friendly: Array[Vector2i] = default_layout.friendly
	var route: Array[Vector2i] = Transit.build_macro_path(data, friendly[0], PEAK)
	_report["friendly_first_cell"] = str(friendly[0])
	_report["predeployment_route_size"] = route.size()
	_report["predeployment_route_first20"] = _first_cells(route)
	if route.is_empty():
		_fail("No static route from original friendly first cell to peak on unchanged generated mountain")
		return
	var enemy_spawn := _find_distant_enemy_spawn(friendly, route)
	if enemy_spawn == TerrainArmy.INVALID_CELL:
		_fail("No legal distant 100-person enemy formation clear of the fixed route")
		return
	var trial := _lab.start_melee_trial({"friendly_count": MEMBERS, "enemy_count": MEMBERS,
		"friendly_attack": false, "enemy_attack": false, "enemy_role": "logistics",
		"friendly_spawn": friendly[0], "enemy_spawn": enemy_spawn})
	if not bool(trial.get("ok", false)):
		_fail("Original start_melee_trial rejected 100+100: " + str(trial))
		return
	_army = _lab.army
	if _army.combat_units.size() != MEMBERS or _lab.opposing_army.combat_units.size() != MEMBERS \
		or _army.visual_mode() != "baked_atlas" or _lab.opposing_army.visual_mode() != "baked_atlas":
		_fail("100+100 original bodies and baked presentation are unavailable")
		return
	_report["enemy_spawn"] = str(enemy_spawn)
	_report["friendly_spawn"] = str(friendly[0])
	_report["window_pixels"] = str(DisplayServer.window_get_size())
	_report["viewport_pixels"] = str(root.get_texture().get_size())
	_lab.set_process(true)
	for frame in range(WARMUP_FRAMES):
		await process_frame
		await RenderingServer.frame_post_draw
	if _visible_soldiers() != MEMBERS * 2:
		_fail("Warm original scene did not render all 200 soldiers")
		return
	if _lab.terrain != data or bool(data.site.get("paused", false)) or _lab.get_tree().paused \
		or not _lab.is_processing() or not _lab.character.is_processing() or not _army.is_processing() or not _lab.opposing_army.is_processing():
		_fail("Original Lab, Player, or both Army process callbacks are inactive")
		return
	_army.reset_movement_metrics()
	var order: Dictionary = _army.issue_combat_order(_army.current_commander, TerrainArmy.CombatOrder.MOVE, PEAK, -1, Vector2i.UP)
	if not bool(order.get("ok", false)):
		_fail("Commander MOVE was rejected: " + str(order))
		return
	_move_plan = _army.get_active_move_plan()
	_deployment_plan = _army.get_active_deployment_plan()
	_serial = _army.get_order_serial()
	if _move_plan == null or _deployment_plan == null:
		_fail("Accepted MOVE did not retain its original move and deployment plans")
		return
	_report["accepted_route_size"] = _move_plan.macro_path.size()
	_report["accepted_route_first20"] = _first_cells(_move_plan.macro_path)
	if _deployment_plan.member_slot_map.size() != MEMBERS:
		_fail("Accepted MOVE did not retain 100 final assignments")
		return
	if not _select_blocker():
		_fail("Accepted path index 10=(77,16) lacks a free blocker within six original member cells or two-way Player stage: " + str(_report.blocker_preflight))
		return
	if not _lab.character.place(_stage, true):
		_fail("No legal adjacent Player staging cell before measurement")
		return
	_report["accepted_order_serial"] = _serial
	_report["accepted_path_size"] = _move_plan.macro_path.size()
	_report["accepted_goal"] = str(_move_plan.requested_goal)
	_previous_cells = _army.cells.duplicate()
	if not _lab.character.step(_block_cell - _stage):
		_fail("Real Player.step could not enter fixed route cell")
		return
	var enter_deadline := Time.get_ticks_usec() + 3000000
	while _lab.character.is_moving() and Time.get_ticks_usec() < enter_deadline:
		await process_frame
		await RenderingServer.frame_post_draw
		if not _observe("Player entry"):
			return
	if _lab.character.is_moving() or _lab.character.terrain_cell != _block_cell or _blocked_frames == 0:
		_fail("Player did not physically enter the accepted route cell through the original blocker grid")
		return
	_report["blocker_entry_before_measurement"] = true
	_report["blocker_frame_count_before_measurement"] = _blocked_frames
	if root.get_texture().get_image().save_png(_out + "/blocker.png") != OK:
		_fail("Could not capture rendered Player blocker")
		return
	_report["status"] = "MEASURING"
	var drawn_start := Engine.get_frames_drawn()
	var clock_start := _clock()
	var accepted_start := _army.accepted_count
	var blocked_start := _blocked_frames
	var near_start := _blocked_near_member_frames
	var measure_start := Time.get_ticks_usec()
	var previous := measure_start
	var release_started := false
	var first_near_contact := -1.0
	while Time.get_ticks_usec() - measure_start < int(MEASURE_SECONDS * 1000000.0):
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var elapsed := (now - measure_start) / 1000000.0
		_frame_ms.append((now - previous) / 1000.0)
		_frame_at.append(elapsed)
		previous = now
		if not _observe("60-second rendered measurement"):
			return
		if first_near_contact < 0.0 and _blocked_near_member_frames > near_start:
			first_near_contact = elapsed
			_report["first_blocked_near_member_at_seconds"] = elapsed
			_report["release_trigger_at_seconds"] = elapsed + RELEASE_AFTER_CONTACT_SECONDS
		if first_near_contact < 0.0 and elapsed >= CONTACT_DEADLINE_SECONDS:
			_fail("No physical friendly member reached the blocked route cell by the declared 10-second contact deadline")
			return
		if not release_started and first_near_contact >= 0.0 and elapsed >= first_near_contact + RELEASE_AFTER_CONTACT_SECONDS:
			if not _release_player():
				_fail(str(_report.release_failure_reason))
				return
			release_started = true
			_report["release_step_at_seconds"] = elapsed
		if release_started and not _release_complete and not _lab.character.occupies_cell(_block_cell):
			_release_complete = true
			_report["release_complete_at_seconds"] = elapsed
	if not release_started or not _release_complete:
		_fail("Player blocker was not released during the declared 60 seconds")
		return
	var wall := (previous - measure_start) / 1000000.0
	var clock_delta := _clock() - clock_start
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var windows: Array[float] = []
	for window in range(6):
		var frames := 0
		for at: float in _frame_at:
			if at > window * 10.0 and at <= (window + 1) * 10.0:
				frames += 1
		windows.append(frames / 10.0)
	_report["wall_seconds"] = wall
	_report["action_clock_seconds"] = clock_delta
	_report["action_clock_ratio"] = clock_delta / wall
	_report["frames"] = _frame_ms.size()
	_report["fps"] = _frame_ms.size() / wall
	_report["p95_ms"] = _p(sorted, 0.95)
	_report["p99_ms"] = _p(sorted, 0.99)
	_report["max_ms"] = sorted.back() if not sorted.is_empty() else -1.0
	_report["fps_by_10s"] = windows
	_report["drawn_frames_delta"] = Engine.get_frames_drawn() - drawn_start
	_report["blocked_frames"] = _blocked_frames - blocked_start
	_report["blocked_near_member_frames"] = _blocked_near_member_frames - near_start
	_report["invalid_member_proposals"] = _invalid_member_proposals
	_report["physical_steps_after_release"] = _physical_steps_after_release
	_report["accepted_proposals_delta"] = _army.accepted_count - accepted_start
	_report["player_cell_end"] = str(_lab.character.terrain_cell)
	_report["terrain_fingerprint_end"] = data.fingerprint()
	_report["navigation_revision_end"] = data.navigation_revision
	_report["source_hashes_end"] = _source_hashes()
	_report["visible_soldiers_end"] = _visible_soldiers()
	_report["movement_metrics_end"] = _army.get_movement_metrics()
	var failures: Array[String] = []
	if wall < MEASURE_SECONDS or _frame_ms.size() < 60:
		failures.append("duration_or_samples")
	if int(_report.blocked_frames) < 30 or int(_report.blocked_near_member_frames) == 0 \
		or first_near_contact < 0.0 or float(_report.release_step_at_seconds) - first_near_contact < RELEASE_AFTER_CONTACT_SECONDS:
		failures.append("blocker_effect")
	if _physical_steps_after_release == 0 or _army.accepted_count <= accepted_start:
		failures.append("post_release_progress")
	if _invalid_member_proposals != 0 or _release_exit == TerrainArmy.INVALID_CELL or _lab.character.terrain_cell != _release_exit:
		failures.append("player_or_grid")
	if _report.terrain_fingerprint_end != _report.terrain_fingerprint_start or data.static_blocked != original_static \
		or _report.navigation_revision_end != _report.navigation_revision_start or _report.source_hashes_end != _report.source_hashes_start:
		failures.append("terrain_or_source_changed")
	if _report.visible_soldiers_end != MEMBERS * 2 or int(_report.drawn_frames_delta) < _frame_ms.size() - 1:
		failures.append("visual_frames")
	if float(_report.fps) < 30.0 or float(_report.p95_ms) > 33.334 or float(_report.p99_ms) > 50.0:
		failures.append("frame_targets")
	for index in range(windows.size()):
		if windows[index] < 30.0:
			failures.append("fps_window_%d" % index)
	if float(_report.action_clock_ratio) < 0.99 or float(_report.action_clock_ratio) > 1.01:
		failures.append("action_clock")
	_report["status"] = "PASS" if failures.is_empty() else "FAIL"
	_report["failures"] = failures
	if root.get_texture().get_image().save_png(_out + "/after.png") != OK:
		_fail("Could not capture final rendered scene")
		return
	_write()
	print("SITE_MOVE_FORMAL_VISUAL_", _report.status, " output=", _out, " fps=", _report.fps,
		" p95_ms=", _report.p95_ms, " p99_ms=", _report.p99_ms, " windows=", windows,
		" clock_ratio=", _report.action_clock_ratio, " failures=", failures)
	_lab.queue_free()
	quit(0 if failures.is_empty() else 1)
