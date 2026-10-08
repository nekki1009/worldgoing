extends SceneTree

var lab: TerrainLab
var ui: SiteController
var out := "res://output/site_ui_windows_20261001/visual"
var deadline := 0
var checks := 0
var report: Dictionary = {}
var interactive := false
var last_state_write := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	var args := OS.get_cmdline_user_args()
	var index := args.find("--ui-output")
	if index >= 0 and index + 1 < args.size(): out = args[index + 1]
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Site UI visual deadline")
		quit(1)
	if interactive and Time.get_ticks_msec() - last_state_write > 200:
		last_state_write = Time.get_ticks_msec()
		var windows := {}
		for category: String in ui.formal_windows:
			var window: Window = ui.formal_windows[category]
			windows[category] = {"visible": window.visible, "position": [window.position.x, window.position.y], "size": [window.size.x, window.size.y]}
		var state := {"paused": lab.terrain.site.paused, "cell": [lab.character.terrain_cell.x, lab.character.terrain_cell.y],
			"held": lab._held_directions.size(), "run": lab._run_held, "guard": lab.character.guarding,
			"drag": lab._dragging, "selected": [ui.selected.x, ui.selected.y], "message": ui.message.text,
			"test_visible": lab.site_test_window.visible, "test_position": [lab.site_test_window.position.x, lab.site_test_window.position.y],
			"test_size": [lab.site_test_window.size.x, lab.site_test_window.size.y], "editor": lab.character.is_editor_open(), "windows": windows}
		var file := FileAccess.open(out.path_join("live_state.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(state))
		file.close()
		if FileAccess.file_exists(out.path_join("interactive_done")):
			print("SITE UI DESKTOP INTERACTION FINISHED ", JSON.stringify(state))
			quit(0)
	return false

func check(condition: bool, message: String) -> void:
	checks += 1
	assert(condition, message)

func capture(viewport: Viewport, name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(out.path_join(name + ".png")) == OK, "Fresh capture " + name)

func _run() -> void:
	check(DisplayServer.get_name() != "headless", "GPU window required")
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	var scene := load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene
	lab = scene.instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	ui = lab.site_controller
	ui._auto_save_blocked = true
	await process_frame
	lab.set_process(false)
	ui.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	ui.focus_camp()
	check(lab.get_node_or_null("TerrainLabUI") == null, "No legacy panel")
	check(lab.character.player_sprite.texture == lab.character.editor.preview_viewport.get_texture(), "Original viewport still feeds the formal character")
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(2560, 1440)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await process_frame
		ui.hide_tool_windows()
		ui.reset_window_positions()
		ui.launcher_window.show()
		await capture(root, "formal_%dx%d" % [dimensions.x, dimensions.y])
		var before := ui.camera_usable_rect()
		for category: String in ["map", "equipment", "team"]: ui.open_window(category)
		check(ui.camera_usable_rect() == before, "Floating tools leave camera room unchanged")
		for category: String in ["map", "equipment", "team"]:
			check((ui.formal_windows[category] as Window).is_embedded(), "Embedded formal " + category)
		await capture(root, "tools_%dx%d" % [dimensions.x, dimensions.y])
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	ui.hide_tool_windows()
	var test: Window = lab.site_test_window
	if test != null:
		var site_before := JSON.stringify(lab.terrain.site)
		test.call("open")
		await process_frame
		check(not test.is_embedded() and test.get_window_id() != DisplayServer.INVALID_WINDOW_ID, "Actual desktop test host")
		var native_id := test.get_window_id()
		var tabs: TabContainer = test.get("tabs")
		tabs.current_tab = 1
		await capture(test, "native_deployment")
		check(JSON.stringify(lab.terrain.site) == site_before, "Opening test tools does not change original game data")
		tabs.current_tab = 0
		var editor := lab.character.editor
		var viewport := editor.preview_viewport
		var world := editor.preview_world
		var parent := viewport.get_parent()
		var state := lab.character.capture_state()
		test.call("_open_character_editor")
		check(lab.character.is_editor_open() and not lab.character.editor_window.visible, "Editor controls use the sole native test window")
		check(editor.editor_root.get_parent() == test.get("editor_slot"), "Original controls borrowed")
		check(viewport.get_parent() == parent and editor.preview_world == world, "Original render world and viewport stay with their owner")
		await capture(test, "native_character_editor")
		tabs.current_tab = 6
		check(not lab.character.is_editor_open() and editor.editor_root.get_parent() == editor, "Changing tab restores original controls")
		check(viewport.size == CharacterRenderContract.MAP_VIEWPORT_SIZE and not editor.is_processing(), "Changing tab restores original map presenter mode")
		check(lab.character.hp == float(state.hp) and lab.character.person_id == int(state.person_id), "Editor lifecycle does not heal or replace the original person")
		tabs.current_tab = 0
		test.call("_open_character_editor")
		test.close_requested.emit()
		check(not lab.character.is_editor_open() and editor.editor_root.get_parent() == editor, "Closing native host restores controls")
		await capture(root, "formal_after_test_close")
		report["native_window"] = {"visible_id": native_id, "embedded": test.is_embedded(), "tabs": tabs.get_tab_count()}
	await _capture_team_information()
	report["checks"] = checks
	report["scope"] = "GPU captures of formal windows, FPS and bounded status at three sizes, actual native host, and original editor borrow/restore; OS dragging, external focus and DPI require desktop interaction"
	var file := FileAccess.open(out.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SITE UI WINDOW VISUAL PASS ", JSON.stringify(report))
	if OS.get_cmdline_user_args().has("--ui-interactive"):
		root.title = "Worldgoing — Site UI desktop verification"
		deadline = Time.get_ticks_msec() + 480000
		lab.pause_when_unfocused = true
		ui.open_window("map")
		lab.set_process(true)
		for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(true)
		interactive = true
		print("SITE UI DESKTOP READY ", out)
		return
	lab.queue_free()
	await process_frame
	quit(0)

func _capture_team_information() -> void:
	var deployed := lab.start_melee_trial({"third_enabled": true, "third_faction": 2,
		"friendly_count": 3, "enemy_count": 3, "third_count": 3,
		"friendly_attack": false, "enemy_attack": false, "third_attack": false,
		"friendly_ai_enabled": false, "enemy_ai_enabled": false, "third_ai_enabled": false})
	check(bool(deployed.get("ok", false)), "Three original HOLD teams deploy: " + str(deployed))
	for team: TerrainArmy in lab.combat_armies:
		team.set_process(false)
		check(team.has_army() and team.combat_order == TerrainArmy.CombatOrder.HOLD and not team.tactical_ai_enabled, "Team information uses original HOLD teams")
	var layouts: Array[Dictionary] = []
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(2560, 1440)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await process_frame
		ui.hide_tool_windows()
		ui.reset_window_positions()
		ui._show_team_deployment_result(deployed)
		var window := ui.formal_windows.team_info as Window
		window.position = Vector2i(dimensions.x - window.size.x - 24, 126)
		await process_frame
		await process_frame
		check(window.is_embedded() and window.visible and ui.team_info_label.text.contains(str(deployed.message)), "Complete deployment report appears in its formal window")
		_check_team_card_layout(window, 3)
		check(not ui.message.text.contains(str(deployed.message)), "The lower-left status contains only the brief deployment result")
		check(ui.fps_label.is_visible_in_tree() and ui.top_banner.is_ancestor_of(ui.fps_label) and ui.top_banner.get_global_rect().encloses(ui.fps_label.get_global_rect()), "Visible FPS fits inside the top banner at " + str(dimensions))
		check(ui.status_panel.size.y < dimensions.y * 0.5, "Deployment status occupies less than half the screen height")
		await capture(root, "team_info_%dx%d" % [dimensions.x, dimensions.y])
		ui.show_result({"ok": true, "message": "第一行\n第二行\n第三行"})
		await process_frame
		await process_frame
		var baseline_height := ui.status_panel.size.y
		var long_message := "長狀態仍可閱讀完整提示，左下訊息最多三行；隊伍詳情保留於獨立視窗。\n".repeat(40)
		ui.show_result({"ok": true, "message": long_message})
		await process_frame
		await process_frame
		check(ui.message.max_lines_visible == 3 and ui.message.tooltip_text == long_message, "Long status keeps its full tooltip and three-line limit")
		check(ui.status_panel.size.y <= baseline_height + 1.0 and ui.status_panel.size.y < dimensions.y * 0.5, "Long status cannot grow the lower-left panel at " + str(dimensions))
		await capture(root, "status_long_%dx%d" % [dimensions.x, dimensions.y])
		var team: TerrainArmy = lab.combat_armies[1]
		var target := team.combat_ground(team.formal_commander)
		target += lab.terrain.surface_visual_offset_at(target)
		var zoom_before := lab.camera.zoom
		var controlled_before := lab.controlled_person_id()
		(ui._team_info_cards[team.team_id].button as Button).pressed.emit()
		await process_frame
		var focus_area := ui._team_leader_focus_rect()
		var on_screen := lab.get_viewport().get_canvas_transform() * target
		check(on_screen.distance_to(focus_area.get_center()) < 1.0 and not Rect2(Vector2(window.position), Vector2(window.size)).has_point(on_screen), "Clicking an enemy-team card shows its original captain beside the information window")
		check(window.visible and lab.camera.zoom == zoom_before and lab.controlled_person_id() == controlled_before, "Locating a captain preserves the open window, zoom and controlled person")
		await capture(root, "team_focus_%dx%d" % [dimensions.x, dimensions.y])
		layouts.append({"size": [dimensions.x, dimensions.y], "status_height": ui.status_panel.size.y, "fps_visible": ui.fps_label.is_visible_in_tree()})
	report["team_information_layouts"] = layouts
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	ui._show_team_deployment_result(deployed)
	var narrow: Window = ui.formal_windows.team_info
	var regular_size := narrow.size
	var regular_position := narrow.position
	narrow.size.x = 360
	narrow.position = Vector2i(1216, 126)
	await process_frame
	await process_frame
	check(narrow.size.x == 360, "The information window can retain a 360-pixel width")
	_check_team_card_layout(narrow, 3)
	await capture(root, "team_info_narrow360")
	ui._team_info_report_button.pressed.emit()
	check(ui.team_info_label.visible and ui.team_info_label.text.contains(str(deployed.message)), "The collapsed report still reveals every original deployment detail")
	ui._team_info_report_button.pressed.emit()
	narrow.size = root.size - Vector2i(16, 120)
	narrow.position = Vector2i(8, 104)
	var maximized_team: TerrainArmy = lab.combat_armies[2]
	var maximized_target := maximized_team.combat_ground(maximized_team.formal_commander)
	maximized_target += lab.terrain.surface_visual_offset_at(maximized_target)
	var zoom_before_maximized := lab.camera.zoom
	(ui._team_info_cards[maximized_team.team_id].button as Button).pressed.emit()
	await process_frame
	check(not narrow.visible and lab.camera.zoom == zoom_before_maximized and (lab.get_viewport().get_canvas_transform() * maximized_target).distance_to(ui.camera_usable_rect().get_center()) < 1.0, "A fully obstructing information window hides so the selected captain remains visible")
	await capture(root, "team_focus_maximized_fallback")
	narrow.size = regular_size
	narrow.position = regular_position
	ui.open_window("team_info")
	lab.clear_army()
	check(ui._team_info_report.is_empty(), "Clearing teams removes the previous deployment report")
	lab.deploy_army()
	lab.army.set_process(false)
	check(lab.army.has_army() and lab.army.roster_size == 100 and not lab.army.combat_enabled, "Original legacy formation deploys its actual 100 people")
	ui.open_window("team_info")
	check(ui.team_info_label.text.contains("100 人") and not ui.team_info_label.text.contains(str(deployed.message)), "Legacy formation information uses its actual roster without a cleared report")
	await process_frame
	await process_frame
	_check_team_card_layout(narrow, 1)
	await capture(root, "team_info_legacy100")

func _check_team_card_layout(window: Window, expected_count: int) -> void:
	check(ui._team_info_cards.size() == expected_count and not ui.team_info_label.visible, "Separate current-team cards appear ahead of the folded full report")
	check(ui._team_info_overview.visible and ui._team_info_overview.text.contains("共 %d 隊" % expected_count), "The overview counts the visible team cards")
	var panels: Array[Control] = []
	for card: Dictionary in ui._team_info_cards.values(): panels.append(card.panel)
	panels.sort_custom(func(left: Control, right: Control) -> bool: return left.get_global_rect().position.y < right.get_global_rect().position.y)
	var previous_end := -INF
	for panel: Control in panels:
		var rect := panel.get_global_rect()
		check(rect.size.x > 0.0 and rect.position.x >= 0.0 and rect.end.x <= float(window.size.x) + 1.0, "Each team card fits the current window width")
		check(rect.position.y >= previous_end + 8.0, "Adjacent team cards retain a visible gap instead of merging into one text block")
		previous_end = rect.end.y
	for card: Dictionary in ui._team_info_cards.values():
		var panel_rect: Rect2 = card.panel.get_global_rect()
		for control: Control in [card.button, card.meta, card.leader, card.summary]:
			var rect := control.get_global_rect()
			check(rect.position.x >= panel_rect.position.x and rect.end.x <= panel_rect.end.x + 1.0, "Team heading and wrapped information stay within their own card")
