extends SceneTree
## Original deployment menu and commands; physical AI behavior has its own test.
var lab: TerrainLab
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 60000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() >= deadline:
		push_error("Tactical AI UI deadline")
		quit(1)
	return false

func _run() -> void:
	assert(OS.get_cmdline_user_args().has("--site-test-ui"), "Tactical AI controls require --site-test-ui")
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/terrain_lab/TerrainLab.tscn")
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	lab = scene.instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	var ui: SiteController = lab.site_controller
	var test_host: Window = lab.site_test_window
	_show_page("deployment")
	for prefix: String in ["friendly", "enemy", "third"]:
		assert(ui.trial_ai_enabled[prefix].button_pressed and not ui.trial_ai_enabled[prefix].disabled)
		assert(ui._trial_setup()[prefix + "_ai_enabled"])
		for role_index in [1, 2]:
			ui.trial_roles[prefix].select(role_index)
			ui._trial_role_changed(prefix)
			assert(ui.trial_ai_enabled[prefix].disabled and not ui._trial_setup()[prefix + "_ai_enabled"], "Support teams cannot start tactical AI")
		ui.trial_roles[prefix].select(0)
		ui._trial_role_changed(prefix)
		ui.trial_ai_enabled[prefix].button_pressed = true
		assert(not ui.trial_ai_enabled[prefix].disabled and ui._trial_setup()[prefix + "_ai_enabled"])
	_press("TrialTeamAIEnable") # Empty slots reject through the original UI.
	assert(not lab.army.tactical_ai_enabled)
	_show_page("deployment")
	ui.trial_third_enabled.button_pressed = true
	ui.trial_third_faction.select(2)
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1800, 1100)
		test_host.size = root.size - Vector2i(80, 120)
		await process_frame
		await process_frame
		test_host.position = Vector2i((Vector2(root.size) - Vector2(test_host.size)) * 0.5)
		await process_frame
		await RenderingServer.frame_post_draw
		var capture_dir := "res://output/three_faction_ai_20260928/ui/run_%d" % int(Time.get_unix_time_from_system())
		DirAccess.make_dir_recursive_absolute(capture_dir)
		assert(test_host.get_texture().get_image().save_png(capture_dir + "/options.png") == OK)
		print("TACTICAL_AI_UI_CAPTURE=" + capture_dir + "/options.png")
	for count: SpinBox in [ui.trial_friendly_count, ui.trial_enemy_count, ui.trial_third_count]: count.value = 1
	for percentage: SpinBox in [ui.trial_friendly_female_percent, ui.trial_enemy_female_percent, ui.trial_third_female_percent]: percentage.value = 0
	var layout := lab.find_melee_trial_layout(1, 1, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, 1)
	assert(not layout.is_empty(), "Original map must provide a legal three-team test layout")
	ui.selected = layout.friendly[0]
	ui._set_trial_spawn(true)
	ui.selected = layout.enemy[0]
	ui._set_trial_spawn(false)
	ui.selected = layout.third[0]
	ui._set_third_trial_spawn()
	_press("StartMeleeTrial")
	_show_page("command")
	for team_index in range(3):
		var team: TerrainArmy = lab.combat_armies[team_index]
		assert(team.has_army() and team.tactical_ai_enabled, ui.message.text)
		assert(team.faction_id == team_index)
		ui.trial_command_team.select(team_index)
		ui.trial_command_team.item_selected.emit(team_index)
		assert(not ui.trial_ai_status_label.text.contains("尚未部署"))
		_press("TrialTeamAIDisable")
		assert(not team.tactical_ai_enabled and ui.trial_ai_status_label.text.contains("手動指揮"))
		_press("TrialTeamAIEnable")
		assert(team.tactical_ai_enabled)
		ui.selected = TerrainArmy.INVALID_CELL
		assert(ui.trial_retreat_button.disabled and ui.trial_retreat_button.tooltip_text.contains("士氣尚未崩潰"))
		assert(ui.test_retreat_button.disabled and ui.test_retreat_button.tooltip_text.contains("士氣尚未崩潰"))
		assert(ui.player_retreat_button.disabled, "The autonomous player has no commander retreat authority before joining")
		_press("TrialTeamRetreat")
		assert(team.tactical_ai_enabled, "A disabled pre-collapse retreat cannot disable AI even if its signal is invoked directly")
		ui.selected = team.cells[0]
		_press("TrialTeamPursue")
		assert(team.tactical_ai_enabled, "Friendly target rejection cannot disable AI")
		var goal := _adjacent_goal(team)
		assert(goal != TerrainArmy.INVALID_CELL)
		for entry: Array in [["TrialTeamHold", TerrainArmy.CombatOrder.HOLD],
			["TrialTeamAttack", TerrainArmy.CombatOrder.ATTACK],
			["TrialTeamMove", TerrainArmy.CombatOrder.MOVE],
			["TrialTeamPursue", TerrainArmy.CombatOrder.PURSUE]]:
			_press("TrialTeamAIEnable")
			assert(team.tactical_ai_enabled)
			ui.selected = lab.combat_armies[(team_index + 1) % 3].cells[0] if int(entry[1]) == TerrainArmy.CombatOrder.PURSUE else goal
			if int(entry[1]) == TerrainArmy.CombatOrder.PURSUE:
				assert(ui._selected_enemy_identity(team) == lab.combat_armies[(team_index + 1) % 3].combat_identity(0))
			_press(str(entry[0]))
			assert(team.combat_order == int(entry[1]), str(entry[0]) + ": " + ui.message.text)
			assert(not team.tactical_ai_enabled, "Successful manual order must take over only its selected team")
			assert(ui.trial_ai_status_label.text.contains("手動指揮"))
		_press("TrialTeamHold")
		_press("TrialTeamAIEnable")
		team.tactical_ai_reason = "UI reason probe"
		ui._update_combat_window()
		assert(ui.trial_ai_status_label.text.contains("UI reason probe") and ui.combat_summary_label.text.contains("UI reason probe"))
		for other_index in range(3):
			assert(lab.combat_armies[other_index].tactical_ai_enabled, "Selected manual controls cannot change another team's AI")
	# A live original Actor is also a legal pursuit target, even outside an Army row.
	var pursuing_team: TerrainArmy = lab.opposing_army
	var target_actor: TerrainTestCharacter = lab.character
	var actor_goal := _adjacent_goal(pursuing_team)
	assert(actor_goal != TerrainArmy.INVALID_CELL and target_actor.place(actor_goal, true))
	assert(target_actor.can_act() and target_actor.faction_id != pursuing_team.faction_id)
	ui.trial_command_team.select(1)
	ui.trial_command_team.item_selected.emit(1)
	ui.selected = target_actor.terrain_cell
	_press("TrialTeamAIEnable")
	assert(ui._selected_enemy_identity(pursuing_team) == target_actor.person_id, "Enemy Actor must be selected through the same original person identity")
	_press("TrialTeamPursue")
	assert(pursuing_team.combat_order == TerrainArmy.CombatOrder.PURSUE
		and pursuing_team.pursuit_target == target_actor.person_id and not pursuing_team.tactical_ai_enabled,
		"The real pursuit button must accept the enemy Actor and hand control to the user")
	_press("TrialTeamHold")
	_press("TrialTeamAIEnable")
	var actor_faction := target_actor.faction_id
	target_actor.faction_id = pursuing_team.faction_id
	assert(ui._selected_enemy_identity(pursuing_team) == -1, "Same-faction Actor must be excluded")
	_press("TrialTeamPursue")
	assert(pursuing_team.tactical_ai_enabled and pursuing_team.combat_order == TerrainArmy.CombatOrder.HOLD,
		"Rejected same-faction Actor pursuit must preserve AI and its accepted HOLD")
	target_actor.faction_id = actor_faction
	lab.queue_free()
	await process_frame
	print("SITE_TACTICAL_AI_UI_PASS: three default AI options, support exclusion, original deployment button, per-team enable/disable, disabled pre-collapse retreat reason, rejected commands preserve AI, four legal manual orders take over, selected reasons, enemy Actor pursuit and friendly Actor exclusion")
	quit(0)

func _show_page(page: String) -> void:
	var window: Window = lab.site_test_window
	assert(window != null and window.force_native)
	var pages: Dictionary = window.get("pages")
	(window.get("tabs") as TabContainer).current_tab = pages[page].get_parent().get_index()
	window.call("open")
	lab.site_controller.update_ui()

func _press(button_name: String) -> void:
	_show_page("deployment" if button_name == "StartMeleeTrial" else "command")
	var button := lab.site_test_window.find_child(button_name, true, false) as Button
	assert(button != null, button_name)
	assert(button.is_visible_in_tree(), "Actual trial control must be on the active tab: " + button_name)
	button.pressed.emit()

func _adjacent_goal(team: TerrainArmy) -> Vector2i:
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var candidate := team.cells[0] + direction
		if not lab.terrain.can_step(team.cells[0], candidate): continue
		if lab.site_controller.reserves_cell(candidate): continue
		if lab.site_controller._actor_blocked(candidate, null): continue
		return candidate
	return TerrainArmy.INVALID_CELL
