extends SceneTree
## Run twice in separate processes, without and with: -- --site-test-ui.
## Headless proves structure and command arguments, not desktop focus or native dragging.

const TEST_SCRIPT := "res://scripts/terrain_lab/site_test_window.gd"
const CATEGORIES := ["map", "work", "construction", "equipment", "people", "family", "team_info", "team", "supply", "transport", "system"]
const TEST_PAGES := ["scenario", "deployment", "command", "stock", "logistics", "relationships", "diagnostics"]
const Vehicles = preload("res://scripts/terrain_lab/site_vehicle_transport.gd")

class VehicleProbe extends Vehicles:
	var calls: Array[Dictionary] = []

	func assign_operator(vehicle_id: String, person_id: int, requester_id: int, test_dispatch: bool = false) -> Dictionary:
		calls.append({"action": "assign", "requester": requester_id, "test_dispatch": test_dispatch})
		return super.assign_operator(vehicle_id, person_id, requester_id, test_dispatch)

	func unassign_operator(vehicle_id: String, requester_id: int, test_dispatch: bool = false) -> Dictionary:
		calls.append({"action": "park", "requester": requester_id, "test_dispatch": test_dispatch})
		return super.unassign_operator(vehicle_id, requester_id, test_dispatch)

	func transfer(source_id: String, destination_id: String, resources: Dictionary, item_ids: Array, source_version: int, destination_version: int, requester_id: int, test_dispatch: bool = false) -> Dictionary:
		calls.append({"action": "transfer", "requester": requester_id, "test_dispatch": test_dispatch})
		return super.transfer(source_id, destination_id, resources, item_ids, source_version, destination_version, requester_id, test_dispatch)

var _lab: TerrainLab
var _ui: SiteController
var _deadline := 0
var _checks := 0
var _failed := false
var _test_enabled := false
var _expect_missing := false
var _save_path := ""

func _initialize() -> void:
	_deadline = Time.get_ticks_msec() + 90000
	_expect_missing = OS.get_cmdline_user_args().has("--expect-test-ui-missing")
	_test_enabled = OS.get_cmdline_user_args().has("--site-test-ui") and not _expect_missing
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not _failed and Time.get_ticks_msec() > _deadline:
		_require(false, "90-second window contract deadline")
	return false

func _require(condition: bool, description: String) -> bool:
	_checks += 1
	if not condition:
		_failed = true
		push_error("SITE UI WINDOW CONTRACT: " + description)
		quit(1)
	return condition

func _run() -> void:
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	var main := load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene
	if not _require(main != null, "Formal main scene is available"): return
	_lab = main.instantiate() as TerrainLab
	_lab.pause_when_unfocused = false
	root.add_child(_lab)
	_lab.set_process(false)
	_ui = _lab.site_controller
	_ui.set_process(false)
	_ui._auto_save_blocked = true
	for actor: TerrainTestCharacter in _lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in _lab.combat_armies: team.set_process(false)
	_save_path = "res://.godot-temp/site_ui_window_contract/state_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	_ui.save_path = _save_path
	if not _cold_start(): return
	if not _formal_windows(): return
	if not await _status_layout_contract(): return
	if not _test_window(): return
	if not await _save_and_scope(): return
	if not await _input_focus_contract(): return
	if not _focus_cleanup_contract(): return
	if not _team_information_contract(): return
	if not _formal_authority(): return
	if not await _remove_test_host(): return
	print("SITE UI WINDOW CONTRACT PASS checks=%d test_ui=%s; headless native/desktop focus/editor rendering are not verified" % [_checks, _test_enabled])
	_lab.queue_free()
	await process_frame
	quit(0)

func _cold_start() -> bool:
	if _expect_missing:
		if not _require(not FileAccess.file_exists(TEST_SCRIPT) and _lab.site_test_window == null, "The isolated runtime physically omits the optional test script"): return false
		if OS.get_cmdline_user_args().has("--site-test-ui"):
			if not _require(_ui.message.text.contains("測試工具不可用"), "An explicitly requested missing module reports its unavailability in the formal status"): return false
	if not _require(_lab.get_node_or_null("TerrainLabUI") == null, "The old hidden TerrainLabUI is not built"): return false
	if not _require(_lab.movement_input_enabled and not _lab.test_placement_enabled, "Formal movement works without a debug checkbox; test teleport is off"): return false
	if not _require(_lab.character != null and _lab.terrain != null and not _lab.terrain.site.is_empty(), "Original person and Site initialize without test controls"): return false
	_lab.show_status("formal status without debug labels")
	if not _require(_ui.message.text == "formal status without debug labels", "Formal results reach the original Site status"): return false
	if not _test_enabled:
		if not _require(not ResourceLoader.has_cached(TEST_SCRIPT) and _lab.site_test_window == null, "Flag OFF neither loads nor installs the optional test module"): return false
		if not _require(_lab.find_child("SiteTestWindow", true, false) == null and _lab.find_child("CombatTestWindow", true, false) == null, "Flag OFF has no hidden test Window"): return false
		var key := InputEventKey.new()
		key.keycode = KEY_F12
		key.physical_keycode = KEY_F12
		key.pressed = true
		root.push_input(key)
		key.pressed = false
		root.push_input(key)
		if not _require(not ResourceLoader.has_cached(TEST_SCRIPT) and _lab.site_test_window == null, "F12 cannot install test tools when their flag is absent"): return false
	return true

func _formal_windows() -> bool:
	if not _require(root.gui_embed_subwindows, "Formal windows use the main embedded viewport"): return false
	if not _require(_ui.formal_windows.size() == CATEGORIES.size(), "All eleven formal categories are installed exactly once"): return false
	var launcher: Window = _ui.launcher_window
	if not _require(is_instance_valid(launcher) and not launcher.force_native and not launcher.exclusive, "The launcher is a nonmodal embedded Window"): return false
	var map_rect: Rect2 = _ui.camera_usable_rect()
	if not _require(map_rect.size.x > 0.0 and map_rect.size.y > 0.0 and _lab.camera_usable_rect() == map_rect, "Lab camera framing uses the shared positive map rectangle"): return false
	var camera_before := _lab.camera.position
	var zoom_before := _lab.camera.zoom
	var ids: Array[int] = []
	for category: String in CATEGORIES:
		if not _require(_ui.formal_windows.has(category), "Missing formal category: " + category): return false
		var window := _ui.formal_windows[category] as Window
		if not _require(is_instance_valid(window) and not window.force_native and not window.exclusive, "Formal category must remain embedded and nonmodal: " + category): return false
		if not _require(not ids.has(window.get_instance_id()), "Categories cannot alias one Window: " + category): return false
		ids.append(window.get_instance_id())
		_ui.open_window(category)
		if not _require(window.visible, "The category can be opened: " + category): return false
		window.position = Vector2i(80 + ids.size() * 9, 130 + ids.size() * 5)
		var moved := window.position
		window.close_requested.emit()
		if not _require(is_instance_valid(window) and not window.visible, "Close hides the existing category: " + category): return false
		_ui.open_window(category)
		if not _require(_ui.formal_windows[category] == window and window.visible and window.position == moved, "Reopen preserves the same category and position: " + category): return false
		if DisplayServer.get_name() != "headless" and not _require(window.is_embedded(), "Actual formal category remains embedded: " + category): return false
		if not _require(_ui.camera_usable_rect() == map_rect and _lab.camera.position == camera_before and _lab.camera.zoom == zoom_before, "Moving/opening a tool cannot change the camera or its base area: " + category): return false
	_ui.update_ui()
	for category: String in CATEGORIES:
		if not _require((_ui.formal_windows[category] as Window).visible, "Formal categories can stay open together: " + category): return false
	_ui.hide_tool_windows()
	for category: String in CATEGORIES:
		if not _require(not (_ui.formal_windows[category] as Window).visible, "Hide tools closes each ordinary category: " + category): return false
	_ui.reset_window_positions()
	return _require(_ui.camera_usable_rect() == map_rect, "Resetting tools does not restore the old fixed sidebar map exclusion")

func _status_layout_contract() -> bool:
	if not _require(_ui.fps_label.is_visible_in_tree() and _ui.top_banner.is_ancestor_of(_ui.fps_label), "FPS stays visible inside the formal top banner"): return false
	if not _require(_ui.message.max_lines_visible == 3 and _ui.message.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "Formal status limits long results to three lines with ellipsis"): return false
	var previous_message := _ui.message.text
	_ui.show_result({"ok": true, "message": "第一行\n第二行\n第三行"})
	await process_frame
	await process_frame
	var panel_height := _ui.status_panel.size.y
	var message_height := _ui.message.size.y
	var long_message := "長狀態仍需保留完整說明，左下只能顯示有限行數。\n".repeat(40)
	_ui.show_result({"ok": true, "message": long_message})
	await process_frame
	await process_frame
	if not _require(_ui.status_panel.size.y <= panel_height + 1.0 and _ui.message.size.y <= message_height + 1.0, "A long result cannot enlarge the three-line status or its lower-left panel"): return false
	if not _require(_ui.message.tooltip_text == long_message, "The full long result remains available in the status tooltip"): return false
	if not _require(_ui.top_banner.get_global_rect().encloses(_ui.fps_label.get_global_rect()), "FPS fits completely inside the top banner"): return false
	_ui.show_result({"ok": true, "message": previous_message})
	return true

func _team_information_contract() -> bool:
	var result := _lab.start_melee_trial({"third_enabled": true, "third_faction": 2,
		"friendly_count": 3, "enemy_count": 3, "third_count": 3,
		"friendly_attack": false, "enemy_attack": false, "third_attack": false,
		"friendly_ai_enabled": false, "enemy_ai_enabled": false, "third_ai_enabled": false})
	if not _require(bool(result.get("ok", false)), "Three original HOLD teams deploy for the information window: " + str(result)): return false
	var terrain := _lab.terrain
	var actor := _lab.character
	var teams := _lab.combat_armies.duplicate()
	var team_states: Array[String] = []
	for team: TerrainArmy in teams:
		team.set_process(false)
		if not _require(team.has_army() and team.combat_order == TerrainArmy.CombatOrder.HOLD and not team.tactical_ai_enabled, "Information fixture retains each original HOLD team without autonomous combat"): return false
		team_states.append(JSON.stringify(team.capture_combat_state()))
	var site_before := JSON.stringify(terrain.site)
	var full_report := str(result.message)
	_ui._show_team_deployment_result(result)
	var window := _ui.formal_windows.team_info as Window
	if not _require(window.visible and window.is_ancestor_of(_ui.team_info_label), "Successful deployment opens the formal team-information window"): return false
	if not _require(_ui.team_info_label.text.contains(full_report) and not _ui.message.text.contains(full_report) and _ui.message.text.length() < full_report.length(), "Full deployment details move into team information while the status stays brief"): return false
	if not _require(not _ui.team_info_label.visible and _ui._team_info_report_button.visible, "Complete text starts folded behind its explicit report button"): return false
	_ui._team_info_report_button.pressed.emit()
	if not _require(_ui.team_info_label.visible and _ui.team_info_label.text.contains(full_report), "The report button reveals the original complete deployment text"): return false
	_ui._team_info_report_button.pressed.emit()
	if not _require(not _ui.team_info_label.visible and _ui._team_info_cards.size() == teams.size(), "Folding the report preserves one separate card per real team"): return false
	if not _require(_ui._team_info_overview.visible and _ui._team_info_overview.text.contains("共 %d 隊" % teams.size()), "The visible overview reports the current number of separate teams"): return false
	var panels: Dictionary = {}
	var buttons: Dictionary = {}
	for team: TerrainArmy in teams:
		if not _require(_ui.team_info_label.text.contains(_ui._trial_team_choice_text(team)) and _ui.team_info_label.text.contains(team.combat_summary()), "Team information reads the original identity and current summary for every deployed team"): return false
		if not _require(_ui._team_info_cards.has(team.team_id), "Each team card is keyed by its original team identity"): return false
		var card: Dictionary = _ui._team_info_cards[team.team_id]
		if not _require(window.is_ancestor_of(card.panel) and card.panel.is_ancestor_of(card.button) and card.summary.text.contains(team.combat_summary()), "Each team owns a separate clickable card with its complete original summary"): return false
		panels[team.team_id] = card.panel
		buttons[team.team_id] = card.button
		if not _team_info_click_contract(team, team.formal_commander, "Click each original faction's formal captain"): return false
	_ui.update_ui()
	for team: TerrainArmy in teams:
		var card: Dictionary = _ui._team_info_cards[team.team_id]
		if not _require(card.panel == panels[team.team_id] and card.button == buttons[team.team_id], "Refreshing team information preserves existing cards and their click targets"): return false
	var original_raised := terrain.has_raised_surfaces
	var original_walk_heights := terrain.walk_height_levels
	var original_walk_ramps := terrain.walk_ramp_edges
	var raised_team: TerrainArmy = teams[0]
	terrain.has_raised_surfaces = true
	terrain.walk_height_levels = terrain.height_levels.duplicate()
	terrain.walk_ramp_edges = terrain.ramp_edges.duplicate()
	terrain.walk_height_levels[terrain.index(raised_team.cells[raised_team.formal_commander])] += 2
	var raised_centered := _require(terrain.surface_visual_offset_at(raised_team.combat_ground(raised_team.formal_commander)) == Vector2(0, -96), "The raised-surface fixture uses the original two-level visual offset") and _team_info_click_contract(raised_team, raised_team.formal_commander, "A captain on a raised surface is centered at the rendered height")
	terrain.has_raised_surfaces = original_raised
	terrain.walk_height_levels = original_walk_heights
	terrain.walk_ramp_edges = original_walk_ramps
	if not raised_centered: return false
	var regular_size := window.size
	var regular_position := window.position
	var zoom_before_maximized := _lab.camera.zoom
	var controlled_before_maximized := _lab.controlled_person_id()
	window.size = root.size - Vector2i(16, 120)
	window.position = Vector2i(8, 104)
	var maximized_team: TerrainArmy = teams[2]
	(buttons[maximized_team.team_id] as Button).pressed.emit()
	var maximized_target := maximized_team.combat_ground(maximized_team.formal_commander)
	maximized_target += terrain.surface_visual_offset_at(maximized_target)
	var expected_uncovered := maximized_target + (_lab.get_viewport_rect().size * 0.5 - _ui.camera_usable_rect().get_center()) / zoom_before_maximized.x
	if not _require(not window.visible and _lab.camera.position.is_equal_approx(expected_uncovered) and _lab.camera.zoom == zoom_before_maximized and _lab.controlled_person_id() == controlled_before_maximized, "A window covering the whole map hides before locating its captain in the normal usable area"): return false
	window.size = regular_size
	window.position = regular_position
	_ui.open_window("team_info")
	var focus_team: TerrainArmy = teams[0]
	var formal := focus_team.formal_commander
	var original_current := focus_team.current_commander
	var original_acting := focus_team.acting_commander
	var original_ko := float(focus_team.combat_hot_get(formal, &"ko"))
	var original_formal_exit := bool(focus_team.combat_hot_get(formal, &"site_exited", false))
	var original_proxy_exit := bool(focus_team.combat_hot_get(1, &"site_exited", false))
	focus_team.current_commander = 1
	focus_team.acting_commander = 1
	focus_team.combat_hot_set(formal, &"ko", 7.0)
	_ui.update_ui()
	if not _team_info_click_contract(focus_team, formal, "An unconscious formal captain remains viewable ahead of the acting commander"): return false
	focus_team.combat_hot_set(formal, &"site_exited", true)
	if not _team_info_click_contract(focus_team, 1, "A click resolves the current eligible proxy when the formal captain has left"): return false
	var stale_button: Button = buttons[focus_team.team_id]
	var camera_before_rejected := _lab.camera.position
	var controlled_before_rejected := _lab.controlled_person_id()
	focus_team.combat_hot_set(1, &"site_exited", true)
	stale_button.pressed.emit()
	if not _require(_lab.camera.position == camera_before_rejected and _lab.controlled_person_id() == controlled_before_rejected and window.visible, "A stale card rejects a now-unavailable captain without moving the camera or switching control"): return false
	_ui.update_ui()
	if not _require(stale_button.disabled, "A team without an available formal or acting captain disables its locate button"): return false
	focus_team.combat_hot_set(formal, &"ko", original_ko)
	focus_team.combat_hot_set(formal, &"site_exited", original_formal_exit)
	focus_team.combat_hot_set(1, &"site_exited", original_proxy_exit)
	focus_team.current_commander = original_current
	focus_team.acting_commander = original_acting
	_ui.update_ui()
	window.position += Vector2i(7, 9)
	var moved := window.position
	window.close_requested.emit()
	if not _require(is_instance_valid(window) and not window.visible, "Closing team information hides its existing window"): return false
	_ui.open_window("team_info")
	if not _require(_ui.formal_windows.team_info == window and window.visible and window.position == moved and _ui.team_info_label.text.contains(full_report), "Reopening team information preserves its instance, position and complete report"): return false
	if not _require(_lab.terrain == terrain and _lab.character == actor and JSON.stringify(terrain.site) == site_before, "Displaying team information cannot replace the Site/person or mutate Site data"): return false
	for index in range(teams.size()):
		if not _require(_lab.combat_armies[index] == teams[index] and JSON.stringify(teams[index].capture_combat_state()) == team_states[index], "Opening and closing team information cannot replace or mutate an original team"): return false
	_lab.clear_army()
	for team: TerrainArmy in _lab.combat_armies:
		if not _require(not team.has_army(), "The original clear entry removes each deployed trial team"): return false
	if not _require(_ui._team_info_report.is_empty() and _ui.team_info_label.text == "尚未部署隊伍。" and _ui._team_info_cards.is_empty(), "Clearing teams removes the previous deployment report and cards and displays the empty state"): return false
	_lab.deploy_army()
	var legacy := _lab.army
	legacy.set_process(false)
	if not _require(legacy.has_army() and not legacy.combat_enabled and legacy.roster_size == 100 and legacy.cells.size() == 100 and legacy.combat_units.is_empty(), "The original Deploy100 entry creates a real non-combat 100-person formation"): return false
	_ui.open_window("team_info")
	if not _require(_ui.team_info_label.text.contains("· 100 人") and not _ui.team_info_label.text.contains("· 0 人"), "Legacy deployment information uses its real roster instead of the empty combat rows"): return false
	if not _require(_ui._team_info_report.is_empty() and not _ui.team_info_label.text.contains(full_report), "A new legacy deployment cannot reuse the previous trial report"): return false
	if not _require(_ui._team_info_cards.size() == 1 and _ui._team_info_cards.has(legacy.team_id), "Legacy deployment receives its own single current card"): return false
	var legacy_cells := legacy.cells.duplicate()
	if not _team_info_click_contract(legacy, 0, "Legacy Deploy100 locates its original row-zero captain"): return false
	if not _require(legacy.cells == legacy_cells and legacy.roster_size == 100 and not legacy.combat_enabled, "Locating the legacy captain leaves its original formation unchanged"): return false
	_lab.clear_army()
	if not _require(not legacy.has_army() and _ui._team_info_report.is_empty() and _ui.team_info_label.text == "尚未部署隊伍。" and _ui._team_info_cards.is_empty(), "Clearing the legacy formation leaves neither a team, old card nor old report"): return false
	window.hide()
	return true

func _team_info_click_contract(team: TerrainArmy, captain_index: int, description: String) -> bool:
	var card: Dictionary = _ui._team_info_cards[team.team_id]
	var button := card.button as Button
	if not _require(button != null and not button.disabled, description + ": the real card button is available"): return false
	var zoom_before := _lab.camera.zoom
	var base_area := _ui.camera_usable_rect()
	var controlled_before := _lab.controlled_person_id()
	var executor_before := _ui.person_executor_id
	var target := team.combat_ground(captain_index)
	target += _lab.terrain.surface_visual_offset_at(target)
	_lab.camera.position += Vector2(314, -271)
	button.pressed.emit()
	var area := _ui._team_leader_focus_rect()
	var expected := target + (_lab.get_viewport_rect().size * 0.5 - area.get_center()) / zoom_before
	var window := _ui.formal_windows.team_info as Window
	if not _require(_lab.camera.position.is_equal_approx(expected) and _lab.camera.zoom == zoom_before, description + ": the original position is centered without changing zoom"): return false
	return _require(window.visible and _ui.camera_usable_rect() == base_area and not Rect2(Vector2(window.position), Vector2(window.size)).has_point(area.get_center()) and _lab.controlled_person_id() == controlled_before and _ui.person_executor_id == executor_before, description + ": the captain remains visible beside the open window without changing the shared map area, control or work authority")

func _test_window() -> bool:
	if not _test_enabled: return true
	var window: Window = _lab.site_test_window
	if not _require(is_instance_valid(window) and window.name == "SiteTestWindow", "The explicit flag installs one optional test Window"): return false
	if not _require(window.force_native and window.gui_embed_subwindows and not window.exclusive, "Only the test host requests native mode, with embedded children"): return false
	var tabs := window.get_node_or_null("TestTabs") as TabContainer
	if tabs == null: tabs = window.find_child("TestTabs", true, false) as TabContainer
	if not _require(tabs != null and tabs.get_tab_count() == TEST_PAGES.size(), "The single test host has seven tabs"): return false
	var pages: Dictionary = window.get("pages")
	for page: String in TEST_PAGES:
		if not _require(pages.has(page) and is_instance_valid(pages[page]) and window.is_ancestor_of(pages[page]), "Test page belongs to its one host: " + page): return false
	var before := JSON.stringify(_lab.terrain.site)
	window.call("open")
	window.position = Vector2i(85, 95)
	var moved := window.position
	tabs.current_tab = 2
	window.close_requested.emit()
	if not _require(is_instance_valid(window) and not window.visible, "Test close hides instead of freeing its original host"): return false
	window.call("open")
	window.call("open")
	if not _require(_lab.site_test_window == window and window.visible and window.position == moved and tabs.current_tab == 2, "Repeated test open preserves the same host, position and page"): return false
	if not _require(_lab.find_children("SiteTestWindow", "Window", true, false).size() == 1, "Repeated test open cannot create a second native tool host"): return false
	if not _require(JSON.stringify(_lab.terrain.site) == before, "Opening and closing test tools does not mutate original game data"): return false
	window.call("hide_window")
	return true

func _focus_cleanup_contract() -> bool:
	if not _test_enabled: return true
	_lab._held_directions[KEY_W] = Vector2i.UP
	_lab._last_direction_key = KEY_W
	_lab._run_held = true
	_lab._dragging = true
	_ui.drag_start = Vector2i(8, 8)
	_lab.controlled_guard(true)
	if not _require(_lab.character.guarding, "The original actor begins a held guard before changing input host"): return false
	_lab.site_test_window.call("_focus_entered")
	if not _require(_lab._held_directions.is_empty() and not _lab._run_held and not _lab._dragging, "Test-host focus callback clears held movement and camera input"): return false
	return _require(not _lab.character.guarding and _ui.drag_start == Vector2i(-1, -1), "Test-host focus callback releases original guard and unfinished map selection")

func _input_focus_contract() -> bool:
	# Direct event callbacks verify cleanup logic only, not real desktop delivery.
	_ui.hide_tool_windows()
	for entry: Dictionary in _ui._ui_dialogs.values(): entry.dialog.hide()
	var field := LineEdit.new()
	_lab.add_child(field)
	field.grab_focus()
	await process_frame
	if not _require(_lab.get_viewport().gui_get_focus_owner() == field, "The formal viewport accepts text-field focus"): return false
	_lab._held_directions[KEY_W] = Vector2i.UP
	_lab._run_held = true
	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.pressed = true
	_lab._input(key)
	_lab._unhandled_input(key)
	if not _require(_lab._held_directions.is_empty() and not _lab._run_held, "Focused GUI input cannot leave a movement wish active"): return false
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = _ui.camera_usable_rect().get_center()
	_lab._unhandled_input(click)
	if not _require(_lab.get_viewport().gui_get_focus_owner() == null, "Unhandled map click releases GUI focus before the Controller handles it"): return false
	for button: int in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		_lab._dragging = true
		click.button_index = button as MouseButton
		click.pressed = false
		_lab._input(click)
		if not _require(not _lab._dragging, "Mouse release clears camera dragging even before GUI consumes it"): return false
	field.queue_free()
	await process_frame
	return true

func _remove_test_host() -> bool:
	if not _test_enabled: return true
	var before := JSON.stringify(_lab.terrain.site)
	var actor := _lab.character
	_lab.movement_input_enabled = false
	_lab.test_placement_enabled = true
	_lab.site_test_window.queue_free()
	await process_frame
	_ui.update_ui()
	_lab._update_info()
	_lab.show_status("formal UI after removing the optional host")
	_ui.open_window("transport")
	return _require(_lab.movement_input_enabled and not _lab.test_placement_enabled and _lab.character == actor and JSON.stringify(_lab.terrain.site) == before, "Removing test tools restores input without replacing the actor or changing game data")

func _formal_authority() -> bool:
	if not _require(_ui._formation_source() == "player", "Formal formation source must never fall back to trial/test"): return false
	if not _require(_ui._formation_team("player") == _lab.player_army(), "Formal formation target comes from the original player's membership"): return false
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "site-ui-window-contract")
	data.resource_base.clear()
	data.resources_at.clear()
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	_lab.bind_terrain(data)
	if not _require(_lab.terrain == data and _lab.character.place(Vector2i(50, 50), true), "The original Site accepts a flat authority fixture"): return false
	var team: TerrainArmy = _lab.army
	team.role = "logistics"
	team.team_id = _lab._next_army_identity()
	team.roster_size = 1
	var cells: Array[Vector2i] = [Vector2i(20, 20)]
	if not _require(team.deploy_at(data, _lab.character, _lab.npc, cells) and team.enable_combat(false, 0), "One original NPC supplies the unauthorized transport fixture"): return false
	data.site.army_next_team = team.team_id + 1
	data.site.army_trial_active = true
	if not _require(_ui._formation_source() == "player" and _ui._formation_team("player") == null and _ui._formation_requester(team, "player") == -1, "An available NPC captain cannot become the unjoined player's formation authority"): return false
	var probe := VehicleProbe.new()
	probe.init(_ui)
	_ui.vehicles = probe
	var plan := [{"kind": "cart", "team_id": team.team_id, "cell": data.index(cells[0] + Vector2i.RIGHT), "facing": [1, 0], "operator_index": 0}]
	if not _require(probe.deploy_plan(team, plan).ok, "Original vehicle owner creates the single cart fixture"): return false
	var before := JSON.stringify(probe.records())
	var vehicle_id := str(probe.records().keys()[0])
	var commander := team.combat_identity(0)
	var unauthorized: Dictionary = probe.unassign_operator(vehicle_id, commander)
	if not _require(str(unauthorized.get("code", "")) == "NO_AUTHORITY" and JSON.stringify(probe.records()) == before, "Non-controlled NPC dispatch is rejected without changing its original cart"): return false
	data.site.controlled_person_id = commander
	_ui.update_ui()
	_ui.open_window("transport")
	_ui._refresh_vehicle_controls()
	for button_name: String in ["ParkVehicle", "AssignVehicleOperator", "LoadVehicleResources"]:
		var button := (_ui.formal_windows["transport"] as Window).find_child(button_name, true, false) as Button
		if not _require(button != null, "Formal transport button exists: " + button_name): return false
		var calls_before := probe.calls.size()
		button.pressed.emit()
		if not _require(probe.calls.size() == calls_before + 1, "Formal button reaches the original owner once: " + button_name): return false
		var invocation: Dictionary = probe.calls.back()
		if not _require(int(invocation.requester) == _lab.controlled_person_id() and not bool(invocation.test_dispatch), "Formal transport uses the actual controlled person and false test_dispatch: " + button_name): return false
	return true

func _save_and_scope() -> bool:
	var previous_data := _lab.terrain
	_lab.generate_terrain(0, 54321)
	if not _require(_lab.terrain != previous_data and _lab.terrain.preset == 0 and _lab.terrain.seed_value == 54321, "Formal parameter generation succeeds without hidden seed controls"): return false
	_ui._auto_save_blocked = true
	_ui.save_path = _save_path
	var saved: Dictionary = _ui.save_to(_save_path)
	if not _require(bool(saved.get("ok", false)), "Original save succeeds: " + str(saved)): return false
	var saved_text := FileAccess.get_file_as_string(_save_path)
	_ui.open_window("map")
	(_ui.formal_windows["map"] as Window).position += Vector2i(11, 13)
	_ui.open_window("system")
	saved = _ui.save_to(_save_path)
	if not _require(bool(saved.get("ok", false)) and FileAccess.get_file_as_string(_save_path) == saved_text, "Opening and moving tools cannot change the original gameplay save"): return false
	_ui._open_equipment_inventory()
	var dialog := _lab.get_node("SiteUI").find_child("EquipmentInventoryDialog", true, false) as AcceptDialog
	if not _require(dialog != null and dialog.visible, "Original equipment form is available through formal UI"): return false
	_ui._open_logistics()
	var logistics := _lab.get_node("SiteUI").find_child("LogisticsDialog", true, false) as AcceptDialog
	if not _require(logistics != null and logistics.visible and dialog.visible and not logistics.exclusive and not dialog.exclusive, "Ordinary equipment and logistics forms remain open together without modal ownership"): return false
	_ui._open_equipment_inventory()
	if not _require(_ui._ui_dialogs.equipment.dialog == dialog, "Repeated equipment entry preserves the existing form and callbacks"): return false
	if _test_enabled:
		_ui._open_equipment_inventory(-1, _lab.site_test_window)
		if not _require(_ui._ui_dialogs.equipment.dialog == dialog and dialog.get_parent() == _lab.get_node("SiteUI"), "A test-host shortcut cannot reparent or replace an existing formal transaction"): return false
	var original_data := _lab.terrain
	var failed: Dictionary = _ui.load_from(_save_path + ".missing")
	if not _require(not bool(failed.get("ok", true)) and _lab.terrain == original_data and is_instance_valid(dialog), "Rejected load preserves the current Site and form"): return false
	var loaded: Dictionary = _ui.load_from(_save_path)
	if not _require(bool(loaded.get("ok", false)) and _lab.terrain != original_data, "Original load commits a fresh Site: " + str(loaded)): return false
	await process_frame
	if not _require(not is_instance_valid(dialog) or not dialog.visible, "Successful load invalidates the old form and its captured scope"): return false
	_ui.open_window("equipment")
	_ui._open_equipment_inventory()
	var reopened := _lab.get_node("SiteUI").find_child("EquipmentInventoryDialog", true, false) as AcceptDialog
	return _require(reopened != null and reopened.visible and reopened != dialog, "Reopening creates a current-scope form after load")
