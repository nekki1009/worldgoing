extends SceneTree
## Probe (2026-11-27, 優化): what a player's ×16 sleep costs in the shipped demo A world. Births the package through the
## real boot path (as scenario_demo_trial_test), puts the controlled person to sleep (SiteController.start_sleep "hours"
## -- --hours=N, ×16; if refused, runs the Site at ×16), steps frames as the 30-day test does, and prints the game
## minutes per wall second, the frame time spread and the Region slot's stage counters (profile_usec).
## Output: SLEEP_COST lines and SLEEP_COST_DONE.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const PACKAGE := "res://assets/scenarios/demo_a/demo_a.json"
const WALL_CAP_MS := 900000

var _done := false

func _initialize() -> void:
	create_timer(1700.0).timeout.connect(func() -> void: _end("deadline"))
	_run.call_deferred()

func _end(reason: String) -> void:
	if _done: return
	_done = true
	print("SLEEP_COST end: %s" % reason)
	print("SLEEP_COST_DONE")
	quit(0)

func _hours() -> int:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--hours="): return int(argument.get_slice("=", 1))
	return 6

func _run() -> void:
	var package := RegionData.new()
	if not package.load_manifest(PACKAGE).get("ok", false):
		_end("package refused")
		return
	var start: Array = package.author_initial_context().starting_site
	if not RegionEntry.request_new_world(Vector2i(int(start[0]), int(start[1])), {}, "睡眠量測", "", PACKAGE):
		_end("request refused: " + str(RegionEntry.menu_message))
		return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	for _frame: int in range(36000):
		await process_frame
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if lab == null:
		_end("not born")
		return
	var controller: SiteController = lab.site_controller
	var slot: RegionSaveSlot = controller.region_slot
	for _frame: int in range(10): await process_frame
	var hours := _hours()
	var slept: Dictionary = controller.start_sleep("hours", hours, 16.0)
	print("SLEEP_COST sleep %s %s" % [str(slept.get("ok", false)), str(slept.get("message", ""))])
	if not slept.get("ok", false): lab.simulation_speed = 16.0
	slot.profile_enabled = true
	slot.profile_usec = {}
	var game_before := float(slot.control.logical_game_seconds)
	var minute_before := int(lab.terrain.site.get("minute", 0))
	var target_minute := minute_before + hours * 60
	var started := Time.get_ticks_msec()
	var frames: Array[float] = []
	while int(lab.terrain.site.get("minute", 0)) < target_minute and Time.get_ticks_msec() - started < WALL_CAP_MS:
		var t := Time.get_ticks_usec()
		await process_frame
		if _done: return
		lab._process(1.0 / 30.0)
		controller.person_actions.settle_after_contacts()
		frames.append(float(Time.get_ticks_usec() - t) / 1000.0)
		if not controller._original_step_fault.is_empty():
			print("SLEEP_COST fault %s" % str(controller._original_step_fault))
			break
		if not slept.get("ok", false) and lab.simulation_speed != 16.0: lab.simulation_speed = 16.0
	var wall := float(Time.get_ticks_msec() - started) / 1000.0
	var game_minutes := (float(slot.control.logical_game_seconds) - game_before) / 60.0
	frames.sort()
	var p50: float = frames[frames.size() / 2] if not frames.is_empty() else 0.0
	var p95: float = frames[int(frames.size() * 0.95)] if not frames.is_empty() else 0.0
	print("SLEEP_COST %.1f game minutes in %.1f s wall: %.2f game minutes a wall second (×16 is 16 when a frame keeps up); %d frames, p50 %.1f ms, p95 %.1f ms, max %.1f ms; still asleep %s" % [game_minutes, wall, game_minutes / maxf(wall, 0.001), frames.size(), p50, p95, frames.back() if not frames.is_empty() else 0.0, str(controller.sleeping())])
	var stages: Array = slot.profile_usec.keys()
	stages.sort_custom(func(a: String, b: String) -> bool: return int(slot.profile_usec[a]) > int(slot.profile_usec[b]))
	for stage: String in stages.slice(0, 15): print("SLEEP_COST slot stage %s %.1f s" % [stage, float(slot.profile_usec[stage]) / 1000000.0])
	_end("measured")
