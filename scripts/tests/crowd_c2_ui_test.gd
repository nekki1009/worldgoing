extends SceneTree
## Formal UI-path contract. No command is sent directly to the native crowd.
## Default: B-sized 25+25 x 100; --crowd-ui-small selects 1+1 x 100 for diagnosis.
## --crowd-ui-motion additionally enforces MOVE arrival and ATTACK contact deadlines.
## --crowd-ui-hold runs an independent natural six-cell HOLD calibration and 20-second observation.
const DT := 1.0 / 30.0
var lab: TerrainLab
var controller: SiteController
var site: Node
var captured: Dictionary = {}
var result_serial := 0
var checks: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var failed := false
var out_dir := ""
var elapsed := 0.0
var small := false
var motion := false
var captures := false
var hold_only := false
var hold_complete := false
var capture_frames: Array[Dictionary] = []
var capture_dialog: AcceptDialog

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String, data: Variant = null) -> bool:
	checks.append({"ok": ok, "check": label, "data": data})
	print("C2_UI ", "OK " if ok else "FAIL ", label, " ", str(data) if data != null else "")
	if not ok:
		failed = true
		_write_result()
		printerr("GATE FAIL: ", label, " ", str(data))
		quit(2)
	return ok

func _capture_result(result: Dictionary) -> void:
	captured = result.duplicate(true)
	result_serial += 1

func _write_result() -> void:
	if out_dir.is_empty(): return
	var file := FileAccess.open(out_dir.path_join("orders_ui.json"), FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"ok": not failed, "small": small, "teams": 2 if small else 50,
		"people_per_team": 100, "motion_deadlines_enabled": motion, "hold_only": hold_only, "hold_observation_complete": hold_complete, "checks": checks, "samples": samples, "capture_frames": capture_frames,
		"coverage": "Formal controller deployment, UI selection/order/AI/drag, exact result codes and transaction state",
		"not_covered": (["MOVE/ATTACK motion in this separate HOLD run"] if hold_only else ["HOLD calibration requires separate --crowd-ui-hold run"]) + ["full D5/D6 runtime acceptance", "performance acceptance"]}, "\t", true, true))
	file.close()

func _select(team_id: int) -> bool:
	for index in range(controller.trial_command_team.item_count):
		if int(controller.trial_command_team.get_item_metadata(index)) == team_id:
			controller.trial_command_team.select(index)
			controller.trial_command_team.item_selected.emit(index)
			return true
	return _check(false, "UI team exists", team_id)

func _team(team_id: int) -> Dictionary:
	for entry: Dictionary in site.command_teams():
		if int(entry.team_id) == team_id: return entry
	return {}

func _state(team_id: int) -> Dictionary:
	return site.formation_state(int(_team(team_id).formation))

func _sample(label: String, team_id: int, result: Dictionary = {}) -> void:
	var state := _state(team_id)
	var stats: PackedFloat64Array = site.crowd.stats() # Read-only evidence, never a command.
	samples.append({"label": label, "action_seconds": elapsed, "team_id": team_id,
		"centre": [state.cx, state.cy], "goal": [state.goal_x, state.goal_y], "order": state.order,
		"ai_enabled": bool(state.ai_enabled), "current_person": state.current_person,
		"exchange_pairs": stats[10], "result": result, "ui": controller.trial_ai_status_label.text})

func _result(expected: String, label: String, before_serial: int, team_id: int) -> bool:
	var actual := "MISSING" if before_serial == result_serial else ("OK" if bool(captured.get("ok", false)) else str(captured.get("code", "MISSING_CODE")))
	_sample(label, team_id, captured)
	if not _check(actual == expected, label + " exact show_result", {"expected": expected, "actual": actual, "result": captured}): return false
	return _ui_ai(team_id, label)

func _ui_ai(team_id: int, label: String) -> bool:
	controller._update_combat_window()
	var is_ai := bool(_state(team_id).ai_enabled)
	var marker := "｜AI｜" if is_ai else "｜手動｜"
	var label_text := controller.trial_ai_status_label.text
	var selected_text := controller.trial_command_team.get_item_text(controller.trial_command_team.selected)
	return _check(label_text.contains(marker) and selected_text.contains(marker), label + " UI AI matches rule state", {"ai": is_ai, "label": label_text, "choice": selected_text})

func _order(team_id: int, kind: int, expected: String, label: String) -> bool:
	if not _select(team_id): return false
	var before := result_serial
	controller._trial_team_order(kind)
	return _result(expected, label, before, team_id)

func _ai(team_id: int, enabled: bool, label: String) -> bool:
	if not _select(team_id): return false
	var before := result_serial
	controller._trial_team_ai(enabled)
	return _result("OK", label, before, team_id) and _check(bool(_state(team_id).ai_enabled) == enabled, label + " native AI flag", enabled)

func _nearest_enemies(team_id: int) -> Array[int]:
	var state := _state(team_id)
	var origin: Dictionary = site.soldier_state(int(site._index_by_id[int(state.current_person)]))
	var position := Vector2(float(origin.px), float(origin.py))
	var best := INF
	var identities: Array[int] = []
	for owner in site.person_owners():
		if owner.faction_id == int(_team(team_id).faction): continue
		for index: int in owner.combat_units:
			if not owner.combat_can_act(index): continue
			var person: Dictionary = site.soldier_state(index)
			var distance := position.distance_squared_to(Vector2(float(person.px), float(person.py)))
			if distance < best - 0.000001:
				best = distance
				identities.assign([int(person.person_id)])
			elif absf(distance - best) <= 0.000001:
				identities.append(int(person.person_id))
	return identities

func _far_enemy_cell(team_id: int) -> Vector2i:
	var state := _state(team_id)
	var origin := Vector2(float(state.ref_x), float(state.ref_y)) if bool(state.ref_valid) else Vector2(float(state.cx), float(state.cy))
	for owner in site.person_owners():
		if owner.faction_id == int(_team(team_id).faction): continue
		for index: int in owner.combat_units:
			if not owner.combat_can_act(index): continue
			var person: Dictionary = site.soldier_state(index)
			var position := Vector2(float(person.px), float(person.py))
			if origin.distance_to(position) >= 25.0:
				return Vector2i(floori(float(person.px)), floori(float(person.py)))
	return Vector2i(-1, -1)

func _move_goal(team_id: int) -> Vector2i:
	var state := _state(team_id)
	var leader: Dictionary = site.soldier_state(int(site._index_by_id[int(state.current_person)]))
	var start := Vector2i(floori(float(leader.px)), floori(float(leader.py)))
	var centre := Vector2(float(state.cx), float(state.cy))
	var queue: Array[Vector2i] = [start]
	var visited := {start: true}
	var at := 0
	while at < queue.size():
		var cell := queue[at]
		at += 1
		if (Vector2(cell) + Vector2.ONE * 0.5).distance_to(centre) >= 20.0:
			return cell
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if not visited.has(next) and lab.terrain.contains(next) and lab.terrain.can_step(cell, next):
				visited[next] = true
				queue.append(next)
	return Vector2i(-1, -1)

func _rejected_move(team_id: int, expected_ai: bool, label: String) -> bool:
	if not _select(team_id): return false
	var before_hash: int = site.crowd.state_hash()
	var before_calls: int = site.order_calls
	var before_state := _state(team_id)
	controller.selected = Vector2i(-10, -10)
	var before_serial := result_serial
	controller._trial_team_order(TerrainArmy.CombatOrder.MOVE)
	if not _result("BLOCKED", label, before_serial, team_id): return false
	return _check(site.order_calls == before_calls and site.crowd.state_hash() == before_hash and _state(team_id) == before_state and bool(_state(team_id).ai_enabled) == expected_ai,
		label + " preflight does not call native or alter any state", {"calls_before": before_calls, "calls_after": site.order_calls, "expected_ai": expected_ai, "actual_ai": _state(team_id).ai_enabled})

func _drag_move(team_id: int, goal: Vector2i) -> bool:
	if not _select(team_id): return false
	controller.selected = goal
	controller._begin_facing_move("trial")
	if not _check(controller._crowd_facing, "UI facing drag enters production mode"): return false
	var direction := Vector2i.RIGHT if goal.x + 3 < lab.terrain.size.x else Vector2i.LEFT
	var before := result_serial
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		var cell := goal if pressed else goal + direction * 3
		event.position = lab.renderer.get_global_transform_with_canvas() * lab.renderer.cell_center(cell)
		if not _check(controller.handle_input(event), "production UI handles drag edge", pressed): return false
	if not _result("OK", "UI facing drag MOVE", before, team_id): return false
	var state := _state(team_id)
	return _check(not controller._crowd_facing and absf(wrapf(float(state.goal_facing) - Vector2(direction).angle(), -PI, PI)) < 0.00001,
		"drag release preserves requested facing", {"expected": Vector2(direction).angle(), "actual": state.goal_facing})

func _capture_image(name: String) -> void:
	if not captures or DisplayServer.get_name() == "headless": return
	# Exercise the original camera/window/scroll APIs. Framing is presentation only.
	lab.fit_map()
	var was_open := controller.combat_window.visible
	var status_visible := controller.status_panel.visible
	controller._open_combat_window()
	controller.status_panel.hide()
	var viewport := lab.get_viewport_rect().size
	controller.combat_window.size = Vector2i(790, mini(1160, int(viewport.y) - 64))
	controller.combat_window.position = Vector2i(int(viewport.x) - controller.combat_window.size.x - 20, 105)
	var ancestor: Node = controller.trial_command_team.get_parent()
	while ancestor != null and not ancestor is ScrollContainer:
		ancestor = ancestor.get_parent()
	if not _check(ancestor is ScrollContainer, "original command ScrollContainer exists"): return
	var scroll := ancestor as ScrollContainer
	var last_command := controller.combat_window.find_child("TrialTeamPursue", true, false) as Control
	if not _check(last_command != null, "original command buttons exist"): return
	await process_frame # The original container must have laid out its scroll range.
	scroll.ensure_control_visible(last_command)
	scroll.ensure_control_visible(controller.trial_command_team)
	await process_frame
	var visible := scroll.get_global_rect()
	var framed := visible.encloses(controller.trial_command_team.get_global_rect()) and visible.encloses(controller.trial_ai_status_label.get_global_rect()) and visible.encloses(last_command.get_global_rect())
	capture_frames.append({"name": name, "camera_position": lab.camera.position, "camera_zoom": lab.camera.zoom,
		"window_position": controller.combat_window.position, "window_size": controller.combat_window.size,
		"scroll": visible, "team_choice": controller.trial_command_team.get_global_rect(),
		"ai_status": controller.trial_ai_status_label.get_global_rect(), "last_command": last_command.get_global_rect(),
		"controls_inside_scroll": framed})
	if not _check(framed, "selection, AI and command controls visible for " + name, capture_frames.back()): return
	site.render(0.0)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty() and image.save_png(out_dir.path_join(name + ".png")) == OK, "capture " + name)
	controller.status_panel.visible = status_visible
	if not was_open: controller.combat_window.hide()

func _advance(ticks: int, team_id: int) -> void:
	for tick in range(ticks):
		lab._advance_action_time(DT)
		elapsed += DT
		if tick % 30 == 0:
			_sample("motion", team_id)
			if captures: site.render(DT)
			await process_frame
		if failed: return

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	small = args.has("--crowd-ui-small")
	hold_only = args.has("--crowd-ui-hold")
	motion = args.has("--crowd-ui-motion") and not hold_only
	captures = args.has("--crowd-ui-captures")
	var base := "res://output/crowd_c2_c3_20261001"
	var at := args.find("--crowd-output")
	if at >= 0 and at + 1 < args.size(): base = args[at + 1]
	var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
	out_dir = base.path_join(("ui_hold_" if hold_only else "ui_") + "%s_%s_%d" % ["small" if small else "B50", stamp, Time.get_ticks_msec()])
	if not _check((base.begins_with("res://output/") or base.begins_with("res://native/crowd10k/out_c2/")) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(out_dir)), "new named evidence folder", out_dir): return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var ignore := FileAccess.open(out_dir.path_join(".gdignore"), FileAccess.WRITE)
	if ignore != null: ignore.close()
	create_timer(600.0).timeout.connect(func() -> void:
		failed = true
		_write_result()
		printerr("GATE FAIL: UI script deadline 600 seconds")
		quit(3))
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "formal crowd and isolated save flags required"): return
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.pause_when_unfocused = false
	if captures: root.gui_embed_subwindows = true
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	controller = lab.site_controller
	site = lab.crowd_site
	if not _check(not controller.crowd_test_run_id.is_empty() and str(lab.terrain.site.id).begins_with("crowd_test_"), "formal scene starts in isolated Site"): return
	capture_dialog = AcceptDialog.new()
	controller._equipment_dialog = capture_dialog
	controller._equipment_result = _capture_result
	controller.trial_friendly_teams.set_value_no_signal(1 if small else 25)
	controller.trial_enemy_teams.set_value_no_signal(1 if small else 25)
	controller.trial_third_teams.set_value_no_signal(0)
	for prefix: String in ["friendly", "enemy"]:
		controller.trial_roles[prefix].select(0)
		controller.trial_ai_enabled[prefix].set_pressed_no_signal(true)
		controller.trial_troop_types[prefix].select(1 if prefix == "friendly" else 0)
		controller.trial_carts[prefix].set_value_no_signal(0)
		controller.trial_wagons[prefix].set_value_no_signal(0)
	controller.trial_friendly_training.set_value_no_signal(50)
	controller.trial_enemy_training.set_value_no_signal(50)
	controller.trial_friendly_order.select(1)
	controller.trial_enemy_order.select(1)
	controller.trial_friendly_entry.select(2)
	controller.trial_enemy_entry.select(0)
	var before := result_serial
	controller._deploy_trial_armies()
	var deployment_code := "OK" if bool(captured.get("ok", false)) else str(captured.get("code", "MISSING"))
	if not _check(result_serial > before and deployment_code == "OK" and site.active, "deployment through original controller UI", captured): return
	var teams: Array[Dictionary] = site.command_teams()
	var count := 2 if small else 50
	if not _check(teams.size() == count and controller.trial_command_team.item_count == count and site.crowd.soldier_count() == count * 100 + 1, "UI team count excludes solo actor", {"expected": count, "ui": controller.trial_command_team.item_count, "actual": teams.size(), "soldiers": site.crowd.soldier_count()}): return
	for team: Dictionary in teams:
		if not _check(bool(_state(int(team.team_id)).ai_enabled), "deployed team initially AI", team.team_id): return
	var first := int(teams[0].team_id)
	var enemy := int(teams[floori(count * 0.5)].team_id)
	if not _select(first): return
	await _capture_image("before_orders")
	if failed: return
	if hold_only:
		await _hold_near_enemy(int(teams[0 if small else 1].team_id))
		if not failed: await _finish_run(count)
		return
	var goal := _move_goal(first)
	if not _check(goal != Vector2i(-1, -1), "reachable MOVE goal at least 20 cells away", goal): return
	controller.selected = goal
	if not _order(first, TerrainArmy.CombatOrder.MOVE, "OK", "step 1 MOVE AI takeover"): return
	if not _check(not bool(_state(first).ai_enabled) and int(_state(first).order) == 1, "successful UI MOVE is manual with native MOVE state"): return
	if not _order(first, TerrainArmy.CombatOrder.HOLD, "OK", "step 2 HOLD entry"): return
	var nearest := _nearest_enemies(first)
	if not _order(first, TerrainArmy.CombatOrder.ATTACK, "OK", "step 3 ATTACK without explicit target"): return
	if not _check(int(_state(first).target_person) in nearest, "ATTACK chooses nearest eligible enemy to current commander", {"expected_candidates": nearest, "actual": _state(first).target_person}): return
	controller.selected = _far_enemy_cell(first)
	if not _check(controller.selected != Vector2i(-1, -1), "PURSUE fixture target is at least 25 cells away", controller.selected): return
	var hash_before: int = site.crowd.state_hash()
	if not _order(first, TerrainArmy.CombatOrder.PURSUE, "NO_TARGET", "step 4 distant PURSUE"): return
	if not _check(site.crowd.state_hash() == hash_before, "PURSUE rejection preserves state hash"): return
	hash_before = site.crowd.state_hash()
	if not _order(first, TerrainArmy.CombatOrder.RETREAT, "NOT_ROUTED", "step 5 un-routed RETREAT"): return
	if not _check(site.crowd.state_hash() == hash_before, "RETREAT rejection preserves state hash"): return
	if not _ai(first, true, "step 7 enable AI before takeover"): return
	controller.selected = goal
	if not _order(first, TerrainArmy.CombatOrder.MOVE, "OK", "step 7 UI MOVE takes AI ownership"): return
	if not _check(not bool(_state(first).ai_enabled), "second UI MOVE keeps AI disabled"): return
	if not _rejected_move(enemy, true, "step 9a AI invalid destination"): return
	if not _rejected_move(first, false, "step 9b manual invalid destination"): return
	if not _drag_move(first, goal): return
	if motion:
		await _advance(60, first)
		await _capture_image("move_midway")
		if failed: return
		var arrived := false
		for segment in range(23):
			var state := _state(first)
			if Vector2(float(state.cx), float(state.cy)).distance_to(Vector2(goal) + Vector2.ONE * 0.5) <= 1.5 and int(state.order) == 0:
				arrived = true
				break
			await _advance(30, first)
		var arrived_state := _state(first)
		arrived = arrived or (Vector2(float(arrived_state.cx), float(arrived_state.cy)).distance_to(Vector2(goal) + Vector2.ONE * 0.5) <= 1.5 and int(arrived_state.order) == 0)
		if not _check(arrived, "MOVE arrives within 25 action seconds at 1.5-cell threshold and HOLD", {"goal": goal, "state": arrived_state}): return
		var pairs_before: float = site.crowd.stats()[10]
		if not _order(first, TerrainArmy.CombatOrder.ATTACK, "OK", "motion ATTACK"): return
		await _advance(600, first)
		await _capture_image("combat")
		if failed: return
		if not _check(float(site.crowd.stats()[10]) > pairs_before, "ATTACK contacts increase within 20 action seconds", {"before": pairs_before, "after": site.crowd.stats()[10]}): return
	await _finish_run(count)

func _finish_run(count: int) -> void:
	var stats: PackedFloat64Array = site.crowd.stats()
	if not _check(stats[14] == 0.0 and stats[15] == 0.0 and stats[16] == 0.0, "UI run simulation invariants", [stats[14], stats[15], stats[16]]): return
	_write_result()
	controller._equipment_result = Callable()
	controller._equipment_dialog = null
	capture_dialog.free()
	lab.queue_free()
	await process_frame
	print("GATE OK: formal controller UI contract ", count, " teams; motion_deadlines=", motion, "; hold_observation=", hold_complete, "; evidence=", out_dir)
	quit(0)

func _centre_enemy(team_id: int, enemy_indices: Array[int]) -> Dictionary:
	var state := _state(team_id)
	var centre := Vector2(float(state.cx), float(state.cy))
	var nearest := {"distance": INF, "person_id": -1, "centre": centre}
	for index: int in enemy_indices:
		var person: PackedFloat64Array = site.crowd.get_soldier_state(index) # Read-only calibration.
		if person.size() < 25 or person[0] <= 0.0 or person[3] > 0.0 or person[4] > 0.0 or bool(person[6]): continue
		var position := Vector2(person[14], person[15])
		var distance := centre.distance_to(position)
		if distance < float(nearest.distance):
			nearest = {"distance": distance, "person_id": int(site.crowd.soldier_refs(index)[0]), "centre": centre, "enemy_position": position}
	return nearest

func _hold_near_enemy(team_id: int) -> void:
	# Separate run: preserve the already-passing MOVE/ATTACK path and all-AI deployment.
	var enemy_indices: Array[int] = []
	for owner in site.person_owners():
		if owner.faction_id != int(_team(team_id).faction):
			for index: int in owner.combat_units: enemy_indices.append(index)
	var encounter := {}
	var last_distance := INF
	for tenth in range(900):
		encounter = _centre_enemy(team_id, enemy_indices)
		last_distance = minf(last_distance, float(encounter.distance))
		if float(encounter.distance) >= 5.5 and float(encounter.distance) <= 6.5: break
		await _advance(3, team_id)
		if failed: return
	if not _check(float(encounter.distance) >= 5.5 and float(encounter.distance) <= 6.5, "HOLD enemy naturally approaches six-cell calibration within 90 action seconds", {"encounter": encounter, "closest_seen": last_distance, "action_seconds": elapsed}): return
	var initial: Vector2 = encounter.centre
	var began_at := elapsed
	var began_step := int(site.crowd.stats()[36])
	encounter.geometry = _hold_geometry(team_id)
	if not _order(team_id, TerrainArmy.CombatOrder.HOLD, "OK", "step 2 calibrated HOLD takes UI ownership"): return
	if not _check(not bool(_state(team_id).ai_enabled) and int(_state(team_id).order) == 0, "calibrated HOLD leaves manual ownership and HOLD order"): return
	_sample("HOLD start at six cells", team_id, encounter)
	await _capture_image("hold_start")
	if failed: return
	var maximum := 0.0
	for tick in range(600):
		lab._advance_action_time(DT)
		elapsed += DT
		var state := _state(team_id)
		var centre := Vector2(float(state.cx), float(state.cy))
		maximum = maxf(maximum, centre.distance_to(initial))
		if not (int(state.order) == 0 and not bool(state.ai_enabled) and maximum <= 1.5):
			_check(false, "HOLD stays within 1.5 cells with manual HOLD for all 20 seconds", {"observed_seconds": elapsed - began_at, "max_displacement": maximum, "state": state, "geometry": _hold_geometry(team_id)})
			return
		if tick % 30 == 29:
			_sample("HOLD stationary observation", team_id, {"observed_seconds": elapsed - began_at, "max_displacement": maximum, "enemy": _centre_enemy(team_id, enemy_indices), "geometry": _hold_geometry(team_id)})
			if captures: site.render(DT)
			await process_frame
		if failed: return
	hold_complete = _check(elapsed - began_at >= 20.0 - 0.00001 and int(site.crowd.stats()[36]) - began_step == 600 and maximum <= 1.5, "HOLD completes 20 action seconds within 1.5 cells", {"seconds": elapsed - began_at, "native_steps": int(site.crowd.stats()[36]) - began_step, "max_displacement": maximum, "start_encounter": encounter, "team_id": team_id})
	await _capture_image("hold_after_20_seconds")
func _hold_geometry(team_id: int) -> Dictionary:
	# Evidence only: native centre is a slot-grid anchor; keep real-person centroid
	# and nearby allied anchors to diagnose spacing without relaxing the gate.
	var team := _team(team_id)
	var state := _state(team_id)
	var anchor := Vector2(float(state.cx), float(state.cy))
	var total := Vector2.ZERO
	var ready_total := Vector2.ZERO
	var count := 0
	var ready_count := 0
	for owner in site.person_owners():
		if int(owner.formation_index) != int(team.formation): continue
		for index: int in owner.combat_units:
			var person: PackedFloat64Array = site.crowd.get_soldier_state(index)
			var position := Vector2(person[14], person[15])
			total += position
			count += 1
			if person[0] > 0.0 and person[3] <= 0.0 and person[4] <= 0.0 and not bool(person[6]):
				ready_total += position
				ready_count += 1
	var allies: Array[Dictionary] = []
	for other: Dictionary in site.command_teams():
		if int(other.team_id) == team_id or int(other.faction) != int(team.faction): continue
		var formation: Dictionary = site.formation_state(int(other.formation))
		var centre := Vector2(float(formation.cx), float(formation.cy))
		var distance := anchor.distance_to(centre)
		if distance <= 20.0:
			allies.append({"team_id": other.team_id, "centre": centre, "distance": distance, "order": formation.order})
	return {"anchor": anchor, "member_centroid": total / maxi(1, count), "member_count": count,
		"able_centroid": ready_total / maxi(1, ready_count), "able_count": ready_count, "allied_centres_within_20": allies}