extends SceneTree
## Formal main scene, original commands and action clock, untouched generated map.
const OUT := "res://output/npc_ai_acceptance_20260918/navigation"
var lab: TerrainLab
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 45000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("NPC navigation acceptance deadline")
		quit(1)
	return false

func _advance(seconds: float) -> void:
	for tick in range(ceili(seconds / TerrainLab.EXCHANGE_ACTION_STEP)):
		lab._process(TerrainLab.EXCHANGE_ACTION_STEP)

func _goal(origin: Vector2i, minimum: int = 3) -> Vector2i:
	for radius in range(minimum, minimum + 7):
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var cell := origin + direction * radius
			if not lab.terrain.is_walkable(cell) or lab.site_controller._worker_blocked(cell): continue
			var route := lab.terrain.path_between(origin, cell, lab.site_controller._worker_blocked)
			if route.size() >= minimum and route.size() <= radius + 4: return cell
	return TerrainArmy.INVALID_CELL

func _press(name: String) -> void:
	var button := lab.site_controller.combat_window.find_child(name, true, false) as Button
	assert(button != null, name)
	button.pressed.emit()

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	lab.camera.zoom = Vector2.ONE * 1.25
	lab.camera.position = (Vector2(lab.npc.target_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS + Vector2(250, 0)
	lab.camera.force_update_scroll()
	for team: TerrainArmy in lab.combat_armies: team.advance_frame(0.0)
	lab.site_controller.update_ui()
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUT + "/" + name + ".png") == OK)

func _run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/terrain_lab/TerrainLab.tscn")
	root.size = Vector2i(1800, 1100)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	lab = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	var ui := lab.site_controller
	ui._auto_save_blocked = true
	ui.release_worker()
	var initial := lab.npc.terrain_cell
	var goal := _goal(initial)
	assert(goal != TerrainArmy.INVALID_CELL)
	assert(lab.issue_npc_command(TerrainTestNPC.Command.MOVE_TO_CELL, goal))
	_advance(0.1)
	assert(lab.npc.is_moving())
	var paused := JSON.stringify(lab.npc.capture_state())
	ui.toggle_pause()
	lab._process(1.0)
	assert(JSON.stringify(lab.npc.capture_state()) == paused, "Pause must freeze original navigation and committed motion")
	ui.toggle_pause()
	_advance(7.0)
	assert(lab.npc.terrain_cell == goal and not lab.npc.is_moving() and lab.npc.command == TerrainTestNPC.Command.STOP)
	assert(lab.npc.command_status.begins_with("Arrived"))
	var blocked_goal := _goal(goal)
	assert(blocked_goal != TerrainArmy.INVALID_CELL and lab.issue_npc_command(TerrainTestNPC.Command.MOVE_TO_CELL, blocked_goal))
	# A genuinely spawned original teammate occupies a previously legal destination.
	# No terrain edits, teleported occupants, mocked path queries or cleared claims.
	for prefix: String in ["friendly", "enemy"]:
		ui.trial_roles[prefix].select(2)
		ui.trial_roles[prefix].item_selected.emit(2)
	ui.trial_friendly_count.value = 1
	ui.trial_enemy_count.value = 1
	ui.trial_friendly_spawn = blocked_goal
	ui.trial_enemy_spawn = _goal(lab.character.terrain_cell, 16)
	assert(ui.trial_enemy_spawn != TerrainArmy.INVALID_CELL)
	_press("StartMeleeTrial")
	assert(lab.army.has_army() and lab.army.cells[0] == blocked_goal, ui.message.text)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	_advance(4.0)
	assert(lab.npc.terrain_cell != blocked_goal)
	assert(lab.npc.command == TerrainTestNPC.Command.MOVE_TO_CELL and not lab.npc.command_status.begins_with("Arrived"), "An occupied destination is not arrival; keep the original pending order")
	await _capture("blocked_not_arrived")
	var pending_id := lab.npc.person_id
	var pending_cell := lab.npc.terrain_cell
	ui._capture_positions()
	var saved := SiteStore.save(lab.terrain, OUT + "/blocked_order.json")
	assert(saved.ok, str(saved))
	var loaded := SiteStore.load_site(OUT + "/blocked_order.json")
	assert(loaded.ok, str(loaded))
	lab.bind_terrain(loaded.data)
	assert(lab.npc.person_id == pending_id and lab.npc.terrain_cell == pending_cell)
	assert(lab.npc.command == TerrainTestNPC.Command.MOVE_TO_CELL and lab.npc.target_cell == blocked_goal, "Save/load retains the original blocked order and person")
	_advance(1.0)
	assert(lab.npc.command == TerrainTestNPC.Command.MOVE_TO_CELL and lab.npc.terrain_cell != blocked_goal)
	var leave := _goal(blocked_goal, 3)
	assert(leave != TerrainArmy.INVALID_CELL)
	ui.trial_command_team.select(0)
	ui.selected = leave
	_press("TrialTeamMove")
	var resumed_status := false
	for tick in range(300):
		lab._process(TerrainLab.EXCHANGE_ACTION_STEP)
		if lab.npc.is_moving() and lab.npc.command_status.begins_with("Moving to"): resumed_status = true
	assert(resumed_status, "Once a blocked original command resumes walking, its status must stop claiming Blocked")
	assert(lab.army.cells[0] == leave and lab.army.moving_count() == 0, "Original blocking teammate must actually walk away")
	assert(lab.npc.terrain_cell == blocked_goal and lab.npc.command == TerrainTestNPC.Command.STOP, "Original NPC must finish the same pending order once space is free")
	await _capture("unblocked_arrived")
	goal = _goal(lab.npc.terrain_cell)
	assert(goal != TerrainArmy.INVALID_CELL and lab.issue_npc_command(TerrainTestNPC.Command.MOVE_TO_CELL, goal))
	_advance(0.1)
	var committed := lab.npc.terrain_cell # Actor reserves its destination immediately; its original interpolation must finish.
	assert(lab.npc.is_moving() and lab.issue_npc_command(TerrainTestNPC.Command.STOP))
	_advance(2.0)
	assert(lab.npc.terrain_cell == committed and lab.npc.terrain_cell != goal and not lab.npc.is_moving(), "STOP finishes only the original committed step, never the old route")
	assert(lab.issue_npc_command(TerrainTestNPC.Command.FOLLOW_PLAYER))
	_advance(12.0)
	assert(lab.npc.terrain_cell != lab.character.terrain_cell and lab.npc.terrain_cell.distance_to(lab.character.terrain_cell) == 1.0, "Follow stops beside the actual player without overlap")
	var follow_before := lab.npc.terrain_cell
	var player_goal := _goal(lab.character.terrain_cell, 3)
	assert(player_goal != TerrainArmy.INVALID_CELL)
	var route := lab.terrain.path_between(lab.character.terrain_cell, player_goal, func(cell: Vector2i) -> bool: return not lab.character.can_enter_cell(cell))
	assert(not route.is_empty())
	for next: Vector2i in route:
		lab._try_move(next - lab.character.terrain_cell)
		_advance(0.5)
		assert(lab.character.terrain_cell == next)
	_advance(5.0)
	assert(lab.npc.terrain_cell != follow_before and lab.npc.terrain_cell.distance_to(player_goal) == 1.0)
	assert(not lab.issue_npc_command(TerrainTestNPC.Command.MOVE_TO_CELL, Vector2i(-1, -2)))
	var stopped := lab.npc.terrain_cell
	_advance(1.0)
	assert(lab.npc.terrain_cell == stopped and not lab.npc.command_status.begins_with("Arrived"))
	var result := {"passed": true, "formal_main": true, "untouched_terrain": true, "move_actual_arrival": true, "pause": true,
		"dynamic_occupied_goal_never_false_arrival": true, "blocked_order_save_load": true, "same_order_recovers": true, "resumed_status": resumed_status, "stop_committed_step_only": true,
		"follow_actual_player_moves": true, "invalid_goal_rejected": true, "initial": str(initial), "final": str(stopped)}
	var file := FileAccess.open(OUT + "/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("NPC_NAVIGATION_ACCEPTANCE_PASS ", JSON.stringify(result))
	lab.queue_free()
	await process_frame
	quit(0)
