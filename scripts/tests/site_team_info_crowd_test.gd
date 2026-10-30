extends SceneTree
## Real Crowd owner/native contract; run with -- --crowd --crowd-test <unique_run_id>.
## Headless validates camera transforms and state preservation, not desktop clicks.

var _lab: TerrainLab
var _ui: SiteController
var _site: Node
var _window: Window
var _deadline := 0
var _checks := 0
var _failed := false

func _initialize() -> void:
	_deadline = Time.get_ticks_msec() + 60000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not _failed and Time.get_ticks_msec() > _deadline:
		_require(false, "60-second Crowd team information deadline")
	return false

func _require(condition: bool, description: String) -> bool:
	_checks += 1
	if not condition:
		_failed = true
		push_error("SITE TEAM INFO CROWD: " + description)
		quit(1)
	return condition

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not _require(args.has("--crowd") and args.has("--crowd-test"), "The real Crowd path requires an isolated test run"): return
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	_lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate() as TerrainLab
	_lab.pause_when_unfocused = false
	root.add_child(_lab)
	_lab.set_process(false)
	_ui = _lab.site_controller
	_ui.set_process(false)
	_ui._auto_save_blocked = true
	for actor: TerrainTestCharacter in _lab.combat_actors: actor.set_process(false)
	if not _require(not _ui.crowd_test_run_id.is_empty(), "Crowd test paths are isolated from the player's saved Site"): return
	var deployed: Dictionary = _lab.deploy_trial_armies([
		{"faction": 0, "count": 3, "female_percent": 0, "attack": false, "ai_enabled": false, "entry": "west"},
		{"faction": 1, "count": 3, "female_percent": 0, "attack": false, "ai_enabled": false, "entry": "east"}])
	if not _require(bool(deployed.get("ok", false)), "Two real HOLD teams deploy: " + str(deployed)): return
	_site = _lab.crowd_site
	if not _require(_site != null and _site.active and _site.crowd != null and _site.crowd.get_class() == "ArmyCrowd", "Original CrowdSite and native ArmyCrowd own the deployed people"): return
	for team: TerrainArmy in _lab.combat_armies: team.set_process(false)
	var teams: Array[Dictionary] = _site.command_teams()
	if not _require(teams.size() == 2, "Exactly the two real command teams appear, excluding the solo controlled person"): return
	_lab.selected_army_target = int(_site.formation_state(int(teams[1].formation)).formal_person)
	_ui._show_team_deployment_result(deployed)
	_window = _ui.formal_windows.team_info as Window
	_window.position = Vector2i(970, 140)
	_window.size = Vector2i(560, 580)
	await process_frame
	await process_frame
	if not _require(_window.visible and _ui._team_info_cards.size() == 2, "The existing information window contains one card per Crowd team"): return
	var original_buttons := {}
	for team: Dictionary in teams:
		var card_team_id := int(team.team_id)
		var card_state: Dictionary = _site.formation_state(int(team.formation))
		if not _require(int(card_state.order) == 0 and not bool(card_state.ai_enabled), "Each fixture retains its original HOLD order with autonomous combat disabled"): return
		if not _require(_ui._team_info_cards.has(card_team_id), "The Crowd card uses its original team identity"): return
		var card: Dictionary = _ui._team_info_cards[card_team_id]
		if not _require(_window.is_ancestor_of(card.panel) and card.panel.is_ancestor_of(card.button) and not str(card.summary.text).is_empty(), "The real team has its own populated clickable card"): return
		original_buttons[card_team_id] = card.button
		if not _focus(card_team_id, int(card_state.formal_person), false, "Each faction's formal captain"): return
	_ui._update_team_info()
	for card_team_id: int in original_buttons:
		if not _require(_ui._team_info_cards[card_team_id].button == original_buttons[card_team_id], "Refreshing reuses the original Crowd card button"): return
	var first: Dictionary = teams[0]
	var row: Dictionary = _site._team_by_id(int(first.team_id))
	var formation := int(first.formation)
	var team_id := int(first.team_id)
	var state: Dictionary = _site.formation_state(formation)
	var formal := int(state.formal_person)
	var deputy := -1
	for identity: int in row.person_ids:
		if identity != formal:
			deputy = identity
			break
	var owner: RefCounted = _site.person_owner(formal)
	var formal_index: int = _site.crowd.soldier_index(formal)
	var deputy_index: int = _site.crowd.soldier_index(deputy)
	if not _require(owner != null and formal_index >= 0 and deputy_index >= 0 and owner.records.has(formal_index) and owner.records.has(deputy_index), "Captain scenarios use distinct original cold records and native bodies"): return
	if not _require(_site.set_formation_fields(formation, {"current_person": deputy, "acting_person": deputy, "commander_present": true}), "The original native setter authors the acting-captain fixture"): return
	if not _require(_site.set_soldier_fields(formal_index, {"ko": 7.0}), "The original native setter authors an unconscious formal captain"): return
	if not _focus(team_id, formal, false, "A living unconscious formal captain precedes the acting captain"): return
	# G5 S2: off-map exit is a native kind-2 absence, which only an acting soldier may take (grid _finish_site_exit).
	# The KO is cleared first. Native cannot un-exit, so the old cold reset to false is not restored here.
	if not _require(_site.set_soldier_fields(formal_index, {"ko": 0.0}), "The native setter restores the formal captain to act before exit"): return
	owner.combat_hot_set(formal_index, &"site_exited", true)
	if not _focus(team_id, deputy, true, "An exited formal captain falls back to the current eligible captain"): return
	if not _require(_site.set_soldier_fields(formal_index, {"hp": 0.0, "ko": 0.0}), "The native setter authors the deceased formal captain"): return
	if not _focus(team_id, deputy, true, "A deceased formal captain falls back to the current eligible captain"): return
	if not _require(_site.set_soldier_fields(formal_index, {"hp": 100.0}), "The native setter restores the formal body before a departure fixture"): return
	owner.combat_hot_set(formal_index, &"departed", true)
	if not _focus(team_id, deputy, true, "A departed formal captain falls back to the current eligible captain"): return
	owner.combat_hot_set(formal_index, &"departed", false)
	if not _require(_site.set_formation_fields(formation, {"formal_person": -1}), "The native setter authors an absent formal captain"): return
	_window.position = Vector2i(45, 150)
	if not _focus(team_id, deputy, true, "An absent formal captain remains locatable beside the moved information window"): return
	# Do not refresh the card: its button still represents the previous live captain.
	if not _require(_site.set_soldier_fields(deputy_index, {"hp": 0.0}), "The native setter removes the last living captain after the card was drawn"): return
	if not _reject(team_id, "A stale enabled card rejects a captain who died before the click"): return
	if not _require(_site.set_soldier_fields(deputy_index, {"hp": 100.0, "ko": 5.0}), "The native setter authors an unavailable unconscious acting captain"): return
	if not _reject(team_id, "An unconscious acting captain cannot substitute for an absent formal captain"): return
	if not _require(_site.set_soldier_fields(deputy_index, {"ko": 0.0}) and _site.set_formation_fields(formation, {"commander_present": false}), "The native setter authors a live current identity without command presence"): return
	if not _reject(team_id, "A current identity without commander presence is unavailable"): return
	print("SITE TEAM INFO CROWD PASS checks=%d; real native state and camera geometry verified; desktop clicks and rendered appearance not verified" % _checks)
	_lab.queue_free()
	await process_frame
	quit(0)

func _snapshot() -> Dictionary:
	var formations: Array[Dictionary] = []
	for team: Dictionary in _site.teams: formations.append(_site.formation_state(int(team.formation)))
	return {"native": _site.crowd.save_state(), "hash": _site.crowd.state_hash(),
		"formations": formations, "rosters": _site.rosters.duplicate(true), "records": _site._records.duplicate(true),
		"teams": _site.teams.duplicate(true), "site_data": _lab.terrain.site.duplicate(true), "controlled": _lab.controlled_person_id(),
		"executor": _ui.person_executor_id, "selected": _lab.selected_army_target,
		"order_calls": _site.order_calls}

func _unchanged(before: Dictionary, description: String) -> bool:
	var after := _snapshot()
	for key: String in before:
		if not _require(before[key] == after[key], description + ": preserves " + key): return false
	return true

func _focus(team_id: int, expected_identity: int, acting: bool, description: String) -> bool:
	var before := _snapshot()
	_ui._update_team_info()
	var card: Dictionary = _ui._team_info_cards[team_id]
	var leader: Dictionary = _ui._team_info_leader(team_id)
	if not _require(not card.button.disabled and int(leader.get("identity", -1)) == expected_identity and bool(leader.get("acting", false)) == acting, description + ": resolves the current original captain"): return false
	var state: Dictionary = _site.soldier_state(int(_site.crowd.soldier_index(expected_identity)))
	var target := Vector2(float(state.px), float(state.py)) * TerrainRenderer.CELL_PIXELS
	target += _lab.terrain.surface_visual_offset_at(target)
	var zoom_before := _lab.camera.zoom
	var window_position := _window.position
	var window_size := _window.size
	_lab.camera.position += Vector2(314, -271)
	card.button.pressed.emit()
	_lab.camera.force_update_scroll()
	var area := _ui._team_leader_focus_rect()
	var screen_position: Vector2 = _lab.get_viewport().get_canvas_transform() * target
	var covered := Rect2(Vector2(_window.position) - Vector2(4, 28), Vector2(_window.size) + Vector2(8, 32))
	if not _require(screen_position.distance_to(area.get_center()) < 1.0 and not covered.has_point(screen_position), description + ": the real native position appears in the visible map beside the information window"): return false
	if not _require(_lab.camera.zoom == zoom_before and _window.visible and _window.position == window_position and _window.size == window_size, description + ": preserves zoom and the open information window"): return false
	return _unchanged(before, description)

func _reject(team_id: int, description: String) -> bool:
	var before := _snapshot()
	var camera_before := _lab.camera.position
	var zoom_before := _lab.camera.zoom
	var window_position := _window.position
	var window_size := _window.size
	_ui._team_info_cards[team_id].button.pressed.emit()
	if not _require(_lab.camera.position == camera_before and _lab.camera.zoom == zoom_before and _window.visible and _window.position == window_position and _window.size == window_size, description + ": leaves the camera and information window unchanged"): return false
	_ui._update_team_info()
	if not _require(_ui._team_info_cards[team_id].button.disabled and _ui._team_info_leader(team_id).is_empty(), description + ": disables the unavailable locate button"): return false
	return _unchanged(before, description)
