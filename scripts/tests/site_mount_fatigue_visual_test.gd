extends SceneTree
## Formal main scene, real F/held keys, then a distinct single-pool UI fixture.
const OUT := "res://output/site_shared_mount_fatigue_20260918/visual"
var lab: TerrainLab
var deadline := 0
var run_dir := ""
var failed := false
var report := {"complete": false, "failure": "", "captures": []}

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 55000
	run_dir = OUT + "/run_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec()]
	DirAccess.make_dir_recursive_absolute(run_dir)
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not failed and Time.get_ticks_msec() > deadline:
		_check(false, "Mount fatigue visual test exceeded its 55-second deadline")
	return false

func _write() -> void:
	var file := FileAccess.open(run_dir + "/result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	var latest := FileAccess.open(OUT + "/latest.json", FileAccess.WRITE)
	if latest != null:
		latest.store_string(JSON.stringify({"directory": run_dir, "complete": report.complete, "failure": report.failure}, "\t"))

func _check(value: bool, message: String) -> bool:
	if failed: return false
	if not value:
		failed = true
		report.failure = message
		_write()
		push_error(message)
		quit(1)
	return value

func _key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	lab._unhandled_input(event)

func _route() -> Array[Vector2i]:
	var origin := lab.character.terrain_cell
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var path := lab.terrain.path_between(origin, origin + direction * 6,
			func(cell: Vector2i) -> bool: return not lab.character.can_enter_cell(cell))
		if path.size() >= 6 and path.size() <= 32:
			path.push_front(origin)
			return path
	return []

func _held_run(route: Array[Vector2i]) -> bool:
	var fatigue_before := PersonFatigue.read(lab.character)
	var time_before := SiteRuntime.now(lab.terrain)
	var cursor := 0
	var held := 0
	var tick := 0
	_key(KEY_SHIFT, true)
	while cursor < route.size() - 1 or lab.character.is_moving():
		if not _check(tick < 1800, "Real held-key riding did not finish the bounded generated route"): return false
		var desired := Vector2i.ZERO if cursor == route.size() - 1 else route[cursor + 1] - route[cursor]
		var next_key: int = {Vector2i.UP: KEY_W, Vector2i.RIGHT: KEY_D, Vector2i.DOWN: KEY_S, Vector2i.LEFT: KEY_A}.get(desired, 0)
		if held != next_key:
			if next_key != 0: _key(next_key, true)
			if held != 0: _key(held, false)
			held = next_key
		lab._process(1.0 / 60.0)
		if cursor + 1 < route.size() and lab.character.terrain_cell == route[cursor + 1]:
			cursor += 1
		if not _check(lab.character.terrain_cell == route[cursor], "Rider left its original generated route"): return false
		tick += 1
		if tick % 60 == 0: await process_frame
	_key(KEY_SHIFT, false)
	report.measured_run = {"steps": cursor, "route": route, "fatigue_before": fatigue_before,
		"fatigue_after": PersonFatigue.read(lab.character), "game_minutes": SiteRuntime.now(lab.terrain) - time_before,
		"input_hz": 60, "boundary": "Actual original F mount and held Shift/direction keys; no fatigue injection, terrain edits or placement during travel."}
	return _check(cursor >= 6 and PersonFatigue.read(lab.character) > fatigue_before and lab.character.ride_speed == 0.0,
		"Real riding must cross at least six cells, accumulate the original single fatigue and fully stop")

func _capture(name: String) -> bool:
	lab.site_controller.update_ui()
	lab.site_controller._layout()
	lab.character._process(0.0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var label: Label = lab.site_controller.player_status_label
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var widths: Array[float] = []
	for line: String in label.text.split("\n"):
		var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		widths.append(width)
		if not _check(width <= label.size.x + 0.5, "Player banner line is clipped: " + line): return false
	var text_height := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).y
	var banner: PanelContainer = lab.site_controller.top_banner
	if not _check(text_height <= label.size.y + 0.5 and banner.get_global_rect().encloses(label.get_global_rect()), "Player banner text height must fit its original panel"): return false
	if not _check(banner.get_global_rect().end.x <= lab.site_controller.panel.get_global_rect().position.x - 15.0,
		"Player banner must not overlap the right-hand panel"): return false
	if not _check(not label.get_global_rect().intersects(lab.site_controller.clock_label.get_global_rect()), "Player status must not cover the original clock"): return false
	var image := root.get_texture().get_image()
	if not _check(image.save_png(run_dir + "/" + name + ".png") == OK, "Could not save original main-scene capture"): return false
	report.captures.append({"file": name + ".png", "text": label.text, "line_widths": widths,
		"label_size": label.size, "text_height": text_height, "image_size": image.get_size()})
	return true

func _run() -> void:
	if not _check(DisplayServer.get_name() != "headless", "Real F-mounted visual test requires a GPU display"): return
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	if not _check(main_scene == "res://scenes/terrain_lab/TerrainLab.tscn", "Must load the formal main scene"): return
	# Keep the project's normal window/content scaling; do not resize to hide clipping.
	lab = (load(main_scene) as PackedScene).instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	lab.site_controller.release_worker()
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	report.surface = {"main_scene": main_scene, "window_size": root.size, "content_scale_size": root.content_scale_size,
		"viewport": lab.get_viewport_rect().size, "seed": lab.terrain.seed_value, "preset": lab.terrain.preset}
	var fingerprint := lab.terrain.fingerprint()
	var route := _route()
	if not _check(not route.is_empty() and not lab.character.is_mounted(), "Original spawn must have a legal short route and begin on foot"): return
	lab.site_controller.update_ui()
	if not _check("坐騎疲勞" not in lab.site_controller.player_status_label.text, "Foot actor must not display horse fatigue"): return
	_key(KEY_F, true)
	_key(KEY_F, false)
	if not _check(lab.character.is_mounted() and lab.character.editor.is_mounted, "Original F must mount the actual Actor presenter"): return
	if not await _held_run(route): return
	if not _check(lab.terrain.fingerprint() == fingerprint, "Generated terrain changed during actual riding"): return
	# This sole value is a display fixture AFTER the measured run, not its outcome.
	PersonFatigue.write(lab.character, "fatigue", 65.0)
	lab.site_controller.update_ui()
	var mounted_text: String = lab.site_controller.player_status_label.text
	if not _check(mounted_text.count("疲勞") == 1 and "疲勞 65.0／100（騎乘耗時 +15.0%）" in mounted_text and "隊伍疲勞" not in mounted_text,
		"Unaffiliated mounted Actor must display only its original single fatigue and riding slowdown"): return
	report.display_fixture = {"sole_fatigue": 65.0, "riding_slowdown_percent": 15.0,
		"boundary": "Explicit display-only value after recording real movement fatigue, reapplied once after real team admission; not claimed as a measured run result."}
	if not await _capture("mounted_banner_fixture"): return
	_key(KEY_F, true)
	_key(KEY_F, false)
	lab.site_controller.update_ui()
	if not _check(not lab.character.is_mounted() and "騎乘耗時" not in lab.site_controller.player_status_label.text and PersonFatigue.read(lab.character) == 65.0
		and lab.site_controller.player_status_label.text.count("疲勞") == 1, "Dismount must retain the sole fatigue, without a separate horse value"): return
	if not await _capture("foot_banner"): return
	_key(KEY_F, true)
	_key(KEY_F, false)
	var deployed := lab.start_melee_trial({"friendly_count": 2, "enemy_count": 1, "friendly_attack": false, "enemy_attack": false})
	if not _check(bool(deployed.ok), "Original trial deployment required for shared Army-row UI"): return
	var joined := lab.army.join_player(lab.character)
	if not _check(bool(joined.ok) and is_same(PersonFatigue.pool(lab.character), lab.army.team_fatigue),
		"Actual original rider must join the real Army fatigue pool"): return
	PersonFatigue.write(lab.character, "fatigue", 65.0) # Explicit common display fixture after admission averaging.
	lab.site_controller.update_ui()
	if not _check("隊伍疲勞 65.0／100（騎乘耗時 +15.0%）" in lab.site_controller.player_status_label.text
		and lab.site_controller.player_status_label.text.count("疲勞") == 1, "Mounted member must show only the common team fatigue"): return
	if not await _capture("team_rider_banner"): return
	lab.terrain.site.controlled_person_id = lab.army.combat_identity(1) # Explicit controlled-person display fixture.
	lab.army.sync_shared_fatigue(true)
	lab.site_controller.update_ui()
	if not _check(int(lab.controlled_target().unit) >= 0 and lab.character.is_mounted()
		and "隊伍疲勞 65.0／100（耗時 +15.0%）" in lab.site_controller.player_status_label.text
		and lab.site_controller.player_status_label.text.count("疲勞") == 1 and "騎乘耗時" not in lab.site_controller.player_status_label.text,
		"Changing controlled member must show the same single team fatigue, not the other Actor's riding mode"): return
	for member: Dictionary in lab.army.combat_units:
		if not _check(PersonFatigue.read(member) == 65.0 and is_same(PersonFatigue.pool(member), PersonFatigue.pool(lab.character)),
			"Original rider and all real team rows must share the exact same fatigue dictionary"): return
	if not await _capture("team_member_banner"): return
	report.display_gates = {"unaffiliated_single_value": true, "dismount_retains_value": true, "controlled_members_share_same_pool": true}
	report.complete = true
	_write()
	print("SITE SHARED MOUNT FATIGUE VISUAL PASS ", run_dir, " — real riding and team admission; inspect four single-value banner PNGs")
	lab.queue_free()
	await process_frame
	quit(0)
