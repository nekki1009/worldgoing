extends "res://scripts/tests/site_ship_formal_art_visual_test.gd"
## OUTPUT candidate. Original main scene / shared step / Army Sprite reference path.
## No frame-rate threshold or hardware release claim; root canonical GPU verifier owns errors.
const PERF_OUT := "res://output/site_ship_close_20261004/fleet_performance"
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
var person_count: int = 10
var stock_shore: Vector2i = TerrainArmy.INVALID_CELL
var setup_action: float = 0.0
var source_hashes: Dictionary = {}
var phase_reports: Array[Dictionary] = []
var initial_anchors: Dictionary = {}
var output_dir: String = ""

func _initialize() -> void:
	case_kind = "ferry"
	deadline = Time.get_ticks_msec() + 600000
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--ship-passengers="): person_count = int(argument.trim_prefix("--ship-passengers="))
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not run_completed and Time.get_ticks_msec() > deadline:
		_must(false, "Bounded setup or live-phase internal deadline")
	return false

func _must(condition: bool, reason: String) -> bool:
	if condition: return true
	if not run_completed:
		run_completed = true
		push_error("SITE_SHIP_FLEET_PERFORMANCE_FAIL: " + reason)
		quit(1)
	return false

func _fixture() -> TerrainData:
	# B's same original generated fixture, with shorter real shore contacts.
	# Every water cell remains explicitly licensed. These are initial fixtures,
	# not teleported people or geometry changes during boarding/measurement.
	var data: TerrainData = super._fixture()
	var navigable: Array[int] = []
	for y: int in data.size.y:
		for x: int in range(32, data.size.x):
			var index: int = data.index(Vector2i(x, y))
			data.flags[index] = TerrainData.Flag.BLOCKED | TerrainData.Flag.WET
			data.surface_types[index] = TerrainData.Surface.WATER
			data.water_kind[index] = 1
			data.water_body[index] = 10
			navigable.append(index)
	data.parameters.navigable_water_cells = navigable
	Env.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	return data

func _step_original(index: int, next: Vector2i) -> bool:
	if not _must(team._reserve_combat_step(index, next), "Original land reservation person=%d from=%s to=%s" % [ids[index], team.cells[index], next]): return false
	var elapsed: float = float(team.move_duration[index]) + 0.04
	lab._advance_action_time(elapsed)
	setup_action += elapsed
	return _must(team.cells[index] == next and team.moving_to[index] == TerrainArmy.INVALID_CELL, "Original shared step committed land walk")

func _walk(index: int, destination: Vector2i) -> bool:
	var identity: int = ids[index]
	var path: Array[Vector2i] = lab.terrain.path_between(team.cells[index], destination, func(cell: Vector2i) -> bool:
		return team.blocks_cell(cell) or team._is_external_cell(cell, identity))
	if not _must(not path.is_empty() or team.cells[index] == destination, "Finite original shore route person=%d from=%s to=%s" % [identity, team.cells[index], destination]): return false
	if not _must(path.size() <= 256, "Original route bounded at 256 cells"): return false
	for next: Vector2i in path:
		if next != team.cells[index] and not _step_original(index, next): return false
		if not _must(Time.get_ticks_msec() < deadline, "Real shared walking setup deadline"): return false
	return true

func _finish_job(identity: int) -> bool:
	var actions: SitePersonActions = lab.site_controller.person_actions
	if not _must(actions.is_busy(identity), "Original timed job exists"): return false
	for iteration: int in range(400):
		if not actions.is_busy(identity): return true
		lab._advance_action_time(0.10)
		setup_action += 0.10
		if not _must(Time.get_ticks_msec() < deadline, "Timed boarding/helm original shared clock deadline"): return false
	return _must(false, "Original timed job failed to complete within 40 ACTION seconds: " + str(identity))

func _shore_key(cell: Vector2i) -> String:
	return "shore:%d" % lab.terrain.index(cell)

func _move_stock(index: int, destination: Vector2i) -> bool:
	# Each relocation uses original one-cell contact, after an original reserved
	# land step. No remote stock movement, copy, spawn or meal reset.
	if not _walk(index, stock_shore): return false
	var identity: int = ids[index]
	var path: Array[Vector2i] = lab.terrain.path_between(stock_shore, destination, func(cell: Vector2i) -> bool:
		return team.blocks_cell(cell) or team._is_external_cell(cell, identity))
	if not _must(not path.is_empty() or stock_shore == destination, "Connected physical shore food route"): return false
	for next: Vector2i in path:
		if next == team.cells[index]: continue
		var prior: Vector2i = stock_shore
		if not _step_original(index, next): return false
		var ui: SiteController = lab.site_controller
		var entry: Dictionary = ui._supply_entry(team)
		var source: Dictionary = entry.locations[_shore_key(prior)]
		var resources: Dictionary = source.inventory.duplicate(true)
		var opened: float = float(source.open_rations)
		if not _must(not resources.is_empty() or opened > 0.0, "Original remaining stock, not fixture replenishment"): return false
		var transferred: Dictionary = ui.transfer_ship_supply(team, _shore_key(prior), _shore_key(next), resources, opened, identity, true)
		if not _must(transferred.ok, "Real original food contact relocation: " + str(transferred)): return false
		stock_shore = next
	return true

func _check_people() -> bool:
	if not _must(team.combat_units.size() == person_count and team.roster_size == person_count and team._sprites.size() == person_count, "Actual original roster count"): return false
	for index: int in range(person_count):
		var row: Dictionary = team.combat_units[index]
		var sprite: Sprite2D = team._sprites[index]
		if not _must(team.combat_identity(index) == ids[index] and is_same(row, rows[index]) and is_same(row.item_state, holders[index]) and row.item_state.item_ids == items[index] and row.cargo == cargos[index] and float(team.combat_hot_get(index, &"hp", 0.0)) == 100.0 and float(team.combat_hot_get(index, &"ko", 0.0)) == 0.0, "Original IDs/body/holder/item IDs/cargo/living HP preserved"): return false
		if not _must(sprite != null and sprite.texture != null, "Original Sprite renderer texture"): return false
	return _must(not team.is_sustain_routed(), "Food/fatigue history must not become routed and hide workload")

func _prepare_fleet() -> bool:
	var ui: SiteController = lab.site_controller
	var spec: Dictionary = Ships.definition("ferry")
	var hull_count: int = floori(float(person_count) / 10.0)
	for hull: int in range(hull_count):
		var created: Dictionary = ui.vehicles.deploy_ship(team, "ferry", Vector2i(32, port_rows[hull]), Vector2i.UP, true)
		if not _must(created.ok, "Real initial shore-contact ferry: " + str(created)): return false
		var vessel: String = str(created.vehicle_id)
		boat_ids.append(vessel)
		initial_anchors[vessel] = Vector2i(32, port_rows[hull])
	var entry: Dictionary = ui._enable_team_supply(team)
	if not _must(not entry.is_empty() and int(entry.version) < 3, "Original shared supply enabled"): return false
	entry.inventory.grain = 200 # Sole explicit initial fixture material seed.
	stock_shore = Vector2i(31, port_rows[0])
	var prepared: Dictionary = ui.prepare_ship_supply(team, stock_shore)
	if not _must(prepared.ok and int(ui._supply_entry(team).version) == 3, "Actual first conversion to shore food locations: " + str(prepared)): return false
	# Original current commander is both authorized requester and physical mover.
	# Load the stopped fleet before boarding that commander; no remote executor.
	if not _must(team.current_commander == 0 and team.command_eligible(0), "Original first-boat commander remains the physical shore supply requester"): return false
	for hull: int in range(hull_count):
		var driver: int = hull * 10
		var port: Vector2i = Vector2i(31, port_rows[hull])
		if hull > 0:
			if not _walk(driver, Vector2i(30, port.y + 2)): return false
			if not _move_stock(0, port): return false
		var loaded: Dictionary = ui.transfer_ship_supply(team, _shore_key(port), "vehicle:" + boat_ids[hull], {"grain":10}, 0.0, ids[0], true)
		if not _must(loaded.ok, "Ten original physical grain for each ten-person ferry: " + str(loaded)): return false
	if not _walk(0, Vector2i(31, port_rows[0])): return false
	# One original timed job per distinct hull. Complete all shore walks before
	# opening any job, then let the original shared clock advance every job.
	for berth: int in [0, 3, 6, 9, 2, 5, 8, 1, 4, 7]:
		for hull: int in range(hull_count):
			var index: int = hull * 10 + berth
			var port: Vector2i = Vector2i(31, port_rows[hull])
			if not _walk(index, port): return false
		var wave_jobs: Array[Dictionary] = []
		for hull: int in range(hull_count):
			var index: int = hull * 10 + berth
			var port: Vector2i = Vector2i(31, port_rows[hull])
			var board: Dictionary = ui.person_actions.begin_ship_board(ids[index], boat_ids[hull], ids[index], berth, true)
			if not _must(board.ok and not rows[index].has("embarked_vehicle_id") and team._cell_owners.get(port, -1) == index, "Original timed board retains original shore side before commit: " + str(board)): return false
			# job_for() is a duplicate; retain the original job only for observation.
			var job: Dictionary = ui.person_actions._jobs.get(str(ids[index]), {})
			if not _must(ui.person_actions.is_busy(ids[index]) and str(job.get("kind", "")) == "ship_board" and int(job.get("executor_id", 0)) == ids[index] and str(job.get("vehicle_id", "")) == boat_ids[hull] and float(job.get("duration", -1.0)) == 2.0 and float(job.get("elapsed", -1.0)) == 0.0, "Every wave member owns a real unadvanced two-second original board job"): return false
			wave_jobs.append(job)
		if not _finish_job(ids[berth]): return false
		for hull: int in range(hull_count):
			var index: int = hull * 10 + berth
			var job: Dictionary = wave_jobs[hull]
			if not _must(not ui.person_actions.is_busy(ids[index]) and not ui.person_actions._jobs.has(str(ids[index])) and float(job.duration) == 2.0 and float(job.elapsed) <= float(job.duration) and float(job.elapsed) + 0.00000001 >= float(job.duration), "Every original wave job reaches its unchanged owner completion threshold and clears"): return false
			if not _must(str(rows[index].get("embarked_vehicle_id", "")) == boat_ids[hull] and int(rows[index].berth_id) == berth and not team._cell_owners.values().has(index), "Real original board committed/released shore claim"): return false
		print("SITE_SHIP_FLEET_PERFORMANCE_SETUP: board_wave berth=%d hulls=%d remaining_ms=%d action=%.3f" % [berth, hull_count, deadline - Time.get_ticks_msec(), setup_action])
	var helm_jobs: Array[Dictionary] = []
	for hull: int in range(hull_count):
		var driver: int = hull * 10
		var helm: Dictionary = ui.person_actions.begin_ship_helm(ids[driver], boat_ids[hull], ids[driver], true)
		if not _must(helm.ok, "Actual helm job"): return false
		var job: Dictionary = ui.person_actions._jobs.get(str(ids[driver]), {})
		if not _must(ui.person_actions.is_busy(ids[driver]) and str(job.get("kind", "")) == "ship_helm" and int(job.get("executor_id", 0)) == ids[driver] and str(job.get("vehicle_id", "")) == boat_ids[hull] and float(job.get("duration", -1.0)) == 0.0 and float(job.get("elapsed", -1.0)) == 0.0, "Every berth-zero driver owns its actual zero-distance original helm job"): return false
		helm_jobs.append(job)
	if not _finish_job(ids[0]): return false
	for hull: int in range(hull_count):
		var driver: int = hull * 10
		var job: Dictionary = helm_jobs[hull]
		var boat: Dictionary = ui.vehicles.records()[boat_ids[hull]]
		if not _must(not ui.person_actions.is_busy(ids[driver]) and not ui.person_actions._jobs.has(str(ids[driver])) and float(job.duration) == 0.0 and float(job.elapsed) == 0.0 and int(boat.operator_id) == ids[driver] and ui.vehicles.ship_driver_ready(boat), "Every actual original helm job settles through the shared clock to its own ready driver"): return false
	print("SITE_SHIP_FLEET_PERFORMANCE_SETUP: helm_wave hulls=%d remaining_ms=%d action=%.3f" % [hull_count, deadline - Time.get_ticks_msec(), setup_action])
	boat_id = boat_ids[0]
	if not _must(ui._control_family_person(null, ids[0]).ok and lab.controlled_person_id() == ids[0], "Original control caller"): return false
	return _fleet_invariants()

func _fleet_invariants() -> bool:
	if not _check_people(): return false
	var ui: SiteController = lab.site_controller
	var count: int = 0
	for vessel: String in boat_ids:
		var boat: Dictionary = ui.vehicles.records()[vessel]
		count += ui.vehicles.ship_people(boat).size()
		if not _must(ui.vehicles.ship_people(boat).size() == 10 and ui.vehicles.ship_driver_ready(boat) and ui.vehicles.ship_load(vessel) <= 80.0 and ui.vehicles.ship_crew_count(boat) == 1, "Original ten-passenger ferry full N/legal Q/actual helm crew"): return false
	return _must(count == person_count and team._cell_owners.is_empty(), "All original people aboard, no source ground passenger copies")

func _hashes() -> Dictionary:
	var result: Dictionary = {}
	var paths: Array[String] = ["res://project.godot", "res://scenes/terrain_lab/TerrainLab.tscn", "res://scripts/terrain_lab/terrain_lab.gd", "res://scripts/terrain_lab/terrain_army.gd", "res://scripts/terrain_lab/site_controller.gd", "res://scripts/terrain_lab/site_person_actions.gd", "res://scripts/terrain_lab/site_vehicle_transport.gd", "res://scripts/terrain_lab/site_vehicle_ship_definitions.gd", "res://scripts/terrain_lab/site_vehicle_view.gd", "res://scripts/terrain_lab/site_runtime.gd", "res://scripts/terrain_lab/site_store.gd", "res://scripts/tests/site_ship_formal_art_visual_test.gd", "res://scripts/tests/site_ship_fleet_performance_test.gd", "res://native/army_idle/bin/army_idle.windows.x86_64.dll", "res://native/crowd10k/bin/crowd10k.windows.x86_64.dll", MANIFEST]
	for path: String in paths:
		if not _must(FileAccess.file_exists(path), "Hash source/DLL exists: " + path): return {}
		result[path] = FileAccess.get_sha256(path)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for entry: Dictionary in manifest.entries.values():
		var path: String = "res://assets/vehicles/ships/v1/" + str(entry.source)
		result[path] = FileAccess.get_sha256(path)
	return result

func _percentile(values: Array[float], fraction: float) -> float:
	var ordered: Array[float] = values.duplicate()
	ordered.sort()
	return ordered[clampi(ceili(fraction * ordered.size()) - 1, 0, ordered.size() - 1)]

func _count_moving() -> int:
	var count: int = 0
	for vessel: String in boat_ids:
		if not (lab.site_controller.vehicles.records()[vessel] as Dictionary).move.is_empty(): count += 1
	return count

func _keep_sailing() -> bool:
	var ui: SiteController = lab.site_controller
	for vessel: String in boat_ids:
		var boat: Dictionary = ui.vehicles.records()[vessel]
		if not boat.move.is_empty() or not boat.command.is_empty(): continue
		var origin: Vector2i = initial_anchors[vessel]
		var current: Vector2i = lab.terrain.cell_from_index(int(boat.cell))
		var target: Vector2i = origin + Vector2i(0, -4) if current == origin else origin
		var ordered: Dictionary = ui.vehicles.ship_order(vessel, "sail", target, int(boat.operator_id), true)
		if not _must(ordered.ok, "Original per-hull shared-process sailing command: " + str(ordered)): return false
	return true

func _check_live_feet() -> bool:
	# After frame_post_draw, inspect the actual original Sprite feet. This
	# invariant is outside the timed sample; do not manually redraw the Army.
	for index: int in range(person_count):
		var sprite: Sprite2D = team._sprites[index]
		var ground: Vector2 = lab.site_controller.vehicles.ship_person_ground(ids[index])
		var displayed: Vector2 = sprite.position + team._unit_anchor(index) - lab.terrain.surface_visual_offset_at(ground)
		if not _must(sprite.visible and displayed.distance_to(ground) < 0.01,"Actual live original foot follows current full-hull pose within 0.01px: " + str(ids[index])): return false
	return true

func _source_counts() -> Dictionary:
	var actors: Array[int] = []
	var count: int = 0
	for original: TerrainArmy in lab.combat_armies: count += original.combat_units.size()
	for actor: TerrainTestCharacter in lab.combat_actors:
		if lab.actor_present(actor): actors.append(actor.person_id)
	return {"original_army_rows":count,"original_present_actor_ids":actors,"total_original_source_people":count+actors.size(),"real_passengers":person_count,"hulls":boat_ids.size()}

func _sample(label: String, sailing: bool) -> bool:
	for frame: int in range(60):
		if sailing and not _keep_sailing(): return false
		await process_frame
		await RenderingServer.frame_post_draw
	var start: int = Time.get_ticks_usec()
	var previous: int = start
	var start_game: float = Runtime.now(lab.terrain) * 60.0
	var before_boats: PackedByteArray = var_to_bytes(lab.terrain.site.vehicles)
	var frame_ms: Array[float] = []
	var cpu_ms: Array[float] = []
	var army_cpu_ms: Array[float] = []
	var moving_frames: int = 0
	var moving_hull_sum: int = 0
	var poses_before: Dictionary = {}
	var hulls_progressed: Dictionary = {}
	for vessel: String in boat_ids: poses_before[vessel] = Vector2(lab.site_controller.vehicles.ship_render_pose(lab.site_controller.vehicles.records()[vessel]).anchor)
	while frame_ms.size() < 120 or Time.get_ticks_usec() - start < 3000000:
		if not _must(Time.get_ticks_msec() < deadline, "Bounded live GPU sample"): return false
		if sailing and not _keep_sailing(): return false
		await process_frame
		await RenderingServer.frame_post_draw
		var instant: int = Time.get_ticks_usec()
		frame_ms.append(float(instant - previous) / 1000.0)
		previous = instant
		cpu_ms.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
		army_cpu_ms.append(float(team.last_frame_cpu_usec) / 1000.0)
		var moving: int = _count_moving()
		moving_hull_sum += moving
		if moving > 0: moving_frames += 1
		for vessel: String in boat_ids:
			var pose: Dictionary = lab.site_controller.vehicles.ship_render_pose(lab.site_controller.vehicles.records()[vessel])
			if Vector2(pose.anchor).distance_to(poses_before[vessel]) > 0.0001: hulls_progressed[vessel] = true
		if not sailing and not _must(moving == 0, "Docked measurement remains stopped"): return false
	var wall: float = float(previous - start) / 1000000.0
	var game_delta: float = Runtime.now(lab.terrain) * 60.0 - start_game
	if not _must(game_delta > 0.0 and (not sailing or moving_frames > 0 and hulls_progressed.size() == boat_ids.size() and before_boats != var_to_bytes(lab.terrain.site.vehicles)), "Actual original shared clock and hull progress during live sample"): return false
	if not _fleet_invariants() or not _check_live_feet(): return false
	phase_reports.append({"phase":label, "sample_frames":frame_ms.size(), "warmup_frames":60, "wall_seconds":wall, "game_seconds":game_delta, "realized_fps":float(frame_ms.size()) / wall, "frame_ms_median":_percentile(frame_ms, 0.5), "frame_ms_p95":_percentile(frame_ms, 0.95), "fps_from_median_frame":1000.0 / _percentile(frame_ms, 0.5), "fps_from_p95_frame":1000.0 / _percentile(frame_ms, 0.95), "process_cpu_ms_median":_percentile(cpu_ms, 0.5), "process_cpu_ms_p95":_percentile(cpu_ms, 0.95), "army_frame_cpu_ms_median":_percentile(army_cpu_ms, 0.5), "army_frame_cpu_ms_p95":_percentile(army_cpu_ms, 0.95), "moving_frames":moving_frames, "actual_hulls_progressed":hulls_progressed.keys(), "original_source_counts":_source_counts(), "mean_moving_hulls":float(moving_hull_sum) / frame_ms.size(), "original_source_people":team.combat_units.size(), "original_hulls":boat_ids.size(), "food_locations":lab.site_controller._supply_entry(team).locations.size()})
	print("SITE_SHIP_FLEET_PERFORMANCE_PHASE:" + JSON.stringify(phase_reports.back()))
	return true

func _dock_all() -> bool:
	var ui: SiteController = lab.site_controller
	for vessel: String in boat_ids:
		var boat: Dictionary = ui.vehicles.records()[vessel]
		var stopped: Dictionary = ui.vehicles.ship_order(vessel, "stop", TerrainArmy.INVALID_CELL, int(boat.operator_id), true)
		if not _must(stopped.ok, "Original committed-step stop"): return false
	for frame: int in range(600):
		if _count_moving() == 0: break
		await process_frame
		await RenderingServer.frame_post_draw
	if not _must(_count_moving() == 0, "Original committed moves bounded stop"): return false
	for vessel: String in boat_ids:
		var boat: Dictionary = ui.vehicles.records()[vessel]
		var ordered: Dictionary = ui.vehicles.ship_order(vessel, "dock", initial_anchors[vessel], int(boat.operator_id), true)
		if not _must(ordered.ok, "Original real shoreline docking command: " + str(ordered)): return false
	for frame: int in range(1800):
		var done: bool = true
		for vessel: String in boat_ids:
			var boat: Dictionary = ui.vehicles.records()[vessel]
			if not boat.move.is_empty() or not boat.command.is_empty(): done = false
		if done: break
		if not _must(Time.get_ticks_msec() < deadline, "Bounded original dock movement"): return false
		await process_frame
		await RenderingServer.frame_post_draw
	for vessel: String in boat_ids:
		var boat: Dictionary = ui.vehicles.records()[vessel]
		if not _must(boat.move.is_empty() and boat.command.is_empty() and lab.terrain.cell_from_index(int(boat.cell)) == initial_anchors[vessel] and not ui.vehicles.ship_contacts(boat).is_empty(), "Original dock completed at genuine shore contact"): return false
	return true

func _run() -> void:
	if not _must(DisplayServer.get_name() != "headless" and person_count in [10, 100], "GPU only; --ship-passengers=10 or100"): return
	output_dir = PERF_OUT + "/" + str(person_count)
	if not _must(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)) == OK, "Output directory"): return
	root.size = Vector2i(1800, 1100)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	source_hashes = _hashes()
	if source_hashes.is_empty(): return
	var main: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn")
	if not _must(main != null, "Original MainScene"): return
	lab = main.instantiate()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	if lab.npc.editor == null: lab.npc.initialize_visual()
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	lab.bind_terrain(_fixture())
	lab.site_controller.release_worker()
	lab.site_controller.hide_tool_windows()
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)
	team = lab.army
	team.role = "logistics"
	team.team_id = lab._next_army_identity()
	team.roster_size = person_count
	team.batch_render_enabled = false # Same original Sprite reference branch as B, explicit report scope.
	var shore: Array[Vector2i] = []
	for hull: int in range(floori(float(person_count) / 10.0)):
		shore.append(Vector2i(31, port_rows[hull]))
		for slot: int in range(9): shore.append(Vector2i(28 + slot % 3, port_rows[hull] - 1 + floori(float(slot) / 3.0)))
	if not _must(team.deploy_at(lab.terrain, lab.character, lab.npc, shore), "Original legal deployment, not subsequent relocation"): return
	if not _must(TerrainArmy.load_combat_bake() and team.enable_combat(false, 0), "Original human atlas and bodies"): return
	lab.terrain.site.army_next_team = team.team_id + 1
	lab.terrain.site.army_trial_active = true
	for index: int in range(person_count):
		var row: Dictionary = team.combat_units[index]
		row.logistics = true
		ids.append(team.combat_identity(index)); rows.append(row); holders.append(row.item_state)
		items.append(row.item_state.item_ids.duplicate()); cargos.append(row.cargo.duplicate(true))
	var start_game: float = Runtime.now(lab.terrain) * 60.0
	if not _prepare_fleet(): return
	var setup_game: float = Runtime.now(lab.terrain) * 60.0 - start_game
	team.advance_frame(0.0)
	var bounds: Rect2 = Rect2()
	for vessel: String in boat_ids:
		var rendered: Dictionary = _check_render("ferry", Vector2i.UP, vessel)
		if rendered.is_empty(): return
		bounds = rendered.art if not bounds.has_area() else bounds.merge(rendered.art)
	_focus(bounds.grow(60))
	# Live original processes. Actors remain actual originals and Lab owns combat time.
	deadline = Time.get_ticks_msec() + 180000 # Original live-phase budget after real setup.
	lab.set_process(true)
	lab.site_controller.set_process(true)
	lab.site_controller.vehicle_view.set_process(true)
	for actor: TerrainTestCharacter in lab.combat_actors:
		if lab.actor_present(actor): actor.set_process(true)
	for army: TerrainArmy in lab.combat_armies: army.set_process(true)
	if not _must(lab.is_processing() and team.is_processing() and lab.site_controller.vehicle_view.is_processing() and setup_game > 0.0,"Original live processes and real setup GAME clock"): return
	if not await _sample("sailing", true): return
	if not await _dock_all() or not await _sample("docked", false): return
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	if not _must(not picture.is_empty() and picture.save_png(output_dir + "/actual_live_fleet.png") == OK, "Actual live GPU preview"): return
	var end_hashes: Dictionary = _hashes()
	if not _must(end_hashes == source_hashes and _fleet_invariants(), "Formal source/DLL/art hashes stable, original owners preserved"): return
	var report: FileAccess = FileAccess.open(output_dir + "/performance_report.json", FileAccess.WRITE)
	if not _must(report != null, "Performance report write"): return
	report.store_string(JSON.stringify({"status":"SITE_SHIP_FLEET_PERFORMANCE_PASS", "person_count":person_count, "hull_count":boat_ids.size(), "original_ids":ids, "original_source_counts":_source_counts(), "setup_action_seconds":setup_action, "setup_game_seconds":setup_game, "initial_fixture_grain":200, "grain_loaded_each":10, "food_and_fatigue_history":lab.site_controller._supply_entry(team).duplicate(true), "phases":phase_reports, "source_sha256_before":source_hashes, "source_sha256_after":end_hashes, "gpu":RenderingServer.get_video_adapter_name(), "cpu":OS.get_processor_name(), "renderer":RenderingServer.get_current_rendering_method(), "viewport":[root.size.x,root.size.y], "vsync":DisplayServer.window_get_vsync_mode(), "max_fps":Engine.max_fps, "scope":"Original MainScene/shared ACTION-GAME steps, original ten or hundred people truly walk/timed board/helm, actual 1 or10 full ferries, original live Lab/Army Sprite renderer and VehicleView. Sailing/docking use original hull reservation/command progression. No CPU/GPU FPS threshold; empirical measurements on this machine only. No native/batch A-B, hardware release, export, 5k/10k or World geography claim."}, "\t"))
	report.close()
	run_completed = true
	lab.queue_free()
	await process_frame
	print("SITE_SHIP_FLEET_PERFORMANCE_PASS:" + str(person_count))
	quit(0)

func _check_render(kind: String, facing: Vector2i, vehicle_id: String = "") -> Dictionary:
	if vehicle_id.is_empty(): vehicle_id = boat_id
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var view: SiteVehicleView = lab.site_controller.vehicle_view
	view.refresh()
	var node: Node2D = view._ship_nodes.get(vehicle_id)
	if not _must(node != null and node.is_visible_in_tree() and node.get_meta("ship_formal_art", false) and not node.get_meta("ship_debug_geometry", true), "Actual VehicleView must render formal PNG, with no gray fallback"): return {}
	var body: Sprite2D = node.get_node_or_null("Body")
	var front: Sprite2D = node.get_node_or_null("Foreground")
	var frame: Dictionary = view.ship_art_frame(kind, facing)
	if not _must(body != null and front != null and not frame.is_empty() and body.material is ShaderMaterial and front.material is ShaderMaterial and body.texture == frame.texture and front.texture == frame.texture and body.texture_filter == Contract.TEXTURE_FILTER and front.texture_filter == Contract.TEXTURE_FILTER and not (node.get_node("Hull") as Polygon2D).visible, "Real source frame/material/filter and hidden debug shape"): return {}
	var boat: Dictionary = vehicles.records()[vehicle_id]
	var pose: Dictionary = vehicles.ship_render_pose(boat)
	var primary: Dictionary = _check_ship_frame_geometry(kind, pose, frame, facing, body, front)
	if primary.is_empty(): return {}
	var expected: Rect2 = view._ship_pose_rectangle(kind, pose)
	expected.position += Vector2(primary.surface)
	var mapped: Rect2 = primary.physical
	if not _must(mapped.position.distance_to(expected.position) < 0.01 and mapped.size.distance_to(expected.size) < 0.01, "Presenter footprint metadata matches independently checked rotated physical corners"): return {}
	var layers: Array[Dictionary] = [{"body":body, "front":front, "frame":frame, "geometry":primary}]
	var art: Rect2 = primary.art
	var move: Dictionary = boat.get("move", {})
	if not move.is_empty():
		var next_facing: Vector2i = Vector2i(int(move.facing[0]), int(move.facing[1]))
		if next_facing != facing:
			var next_frame: Dictionary = view.ship_art_frame(kind, next_facing)
			var next_body: Sprite2D = node.get_node_or_null("TurnBody")
			var next_front: Sprite2D = node.get_node_or_null("TurnForeground")
			if not _must(next_body != null and next_front != null and not next_frame.is_empty() and next_body.visible and next_front.visible and next_body.texture == next_frame.texture and next_front.texture == next_frame.texture and next_body.material is ShaderMaterial and next_front.material is ShaderMaterial and next_body.texture_filter == Contract.TEXTURE_FILTER and next_front.texture_filter == Contract.TEXTURE_FILTER, "Both actual cardinal source pairs exist during the real committed turn"): return {}
			if not _must(is_equal_approx(body.modulate.a, 1.0 - float(pose.progress)) and is_equal_approx(front.modulate.a, body.modulate.a) and is_equal_approx(next_body.modulate.a, float(pose.progress)) and is_equal_approx(next_front.modulate.a, next_body.modulate.a), "Original crossblend follows the actual committed turn progress"): return {}
			var target: Dictionary = _check_ship_frame_geometry(kind, pose, next_frame, next_facing, next_body, next_front)
			if target.is_empty(): return {}
			layers.append({"body":next_body, "front":next_front, "frame":next_frame, "geometry":target})
			art = art.merge(target.art)
	else:
		if not _must(absf(body.rotation) < 0.000001 and absf(front.rotation) < 0.000001, "Stopped cardinal source must not receive a second rotation"): return {}
	var rotations: Array[float] = []
	for layer: Dictionary in layers:
		var body_material: ShaderMaterial = layer.body.material
		var front_material: ShaderMaterial = layer.front.material
		if not _must(body_material.get_shader_parameter("foreground") == false and front_material.get_shader_parameter("foreground") == true and body_material.get_shader_parameter("polygon_counts") == front_material.get_shader_parameter("polygon_counts") and body_material.get_shader_parameter("polygon_points") == front_material.get_shader_parameter("polygon_points"), "Both actual layers use the same source-pixel mask after rotation"): return {}
		rotations.append(float(layer.geometry.rotation))
	var spec: Dictionary = Ships.definition(kind)
	var counted: int = 0
	for index: int in range(person_count):
		if str(rows[index].get("embarked_vehicle_id", "")) != vehicle_id: continue
		counted += 1
		var sprite: Sprite2D = team._sprites[index]
		if not _must(sprite != null and sprite.texture != null, "Every living original embarked human has its actual Sprite"): return {}
		var ground: Vector2 = vehicles.ship_person_ground(ids[index])
		var displayed: Vector2 = sprite.position + team._unit_anchor(index) - lab.terrain.surface_visual_offset_at(ground)
		if not _must(displayed.distance_to(ground) < 0.01, "Original human foot follows its actual unchanged berth and continuous boat basis"): return {}
		for layer: Dictionary in layers:
			if not _check_ship_source_foot(layer.body, layer.frame, ground, layer.geometry.surface): return {}
	if not _must(counted == int(spec.max_people), "Every real hull retains its full original physical-berth people"): return {}
	frames_checked[kind + "/" + str(frame.direction)] = true
	return {"physical":mapped, "art":art, "frame":frame, "source_layers":layers.size(), "source_rotations":rotations, "actual_original_feet":counted, "inverse_source_alpha_checked":true}

