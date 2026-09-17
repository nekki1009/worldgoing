extends SceneTree

const STEP := 1.0 / 30.0
const OUT := "res://output/site_battle_movement_exit_20260915"
const SAVE := "user://exit-regression.json"
var lab: TerrainLab
var baseline_save := ""
var capture_out := OUT

func _initialize() -> void:
	if "--retain-animation-cache" in OS.get_cmdline_user_args():
		preload("res://scripts/tests/fixtures/animation_cache_lifecycle_install.gd").install()
		capture_out += "/cache_%d" % int(Time.get_unix_time_from_system())
	_run.call_deferred()

func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void: push_error("Battle regression deadline"); quit(1))
	lab = (load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene).instantiate() as TerrainLab
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	SiteEnvironment.initialize(data, "movement-exit-probe")
	lab.bind_terrain(data)
	paused = false
	data.site.paused = false
	lab.site_controller.save_path = SAVE
	lab.site_controller.save_current()
	assert(SiteStore.load_site(SAVE).ok)
	baseline_save = FileAccess.get_file_as_string(SAVE)
	if "--safe-exit" in OS.get_cmdline_user_args():
		if "--retain-animation-cache" in OS.get_cmdline_user_args():
			assert(lab.army.deploy(data, lab.character, lab.npc) and lab.army.enable_combat(false))
			lab.army.set_process(false)
			preload("res://scripts/tests/fixtures/animation_cache_lifecycle_install.gd").assert_captain(lab.army)
			lab.army.combat_units[0].hp = 73.25
		root.close_requested.emit()
		assert(not is_instance_valid(lab.site_controller._exit_dialog))
		assert(SiteStore.load_site(SAVE).ok)
		if "--retain-animation-cache" in OS.get_cmdline_user_args():
			var saved: Dictionary = SiteStore.load_site(SAVE)
			assert(saved.data.site.armies.size() == 1 and saved.data.site.armies[0].units[0].hp == 73.25)
			print("CACHE_SAFE_EXIT_SAVED original_100_person_army=true captain_hp=73.25")
		print("SAFE_EXIT_PASS saved validated main scene; requested actual process quit")
		return
	# IO and busy guards also need a cancelable escape, not an uncloseable scene.
	lab.site_controller.save_path = SAVE + "/blocked.json"
	_check_cancel(false, false)
	lab.site_controller.save_path = SAVE
	lab.site_controller._pending_deaths[1] = true
	_check_cancel(false, false)
	lab.site_controller._pending_deaths.clear()
	var trial := lab.start_melee_trial()
	assert(trial.ok)
	if "--retain-animation-cache" in OS.get_cmdline_user_args():
		for team: TerrainArmy in lab.combat_armies:
			preload("res://scripts/tests/fixtures/animation_cache_lifecycle_install.gd").assert_captain(team)
	lab.site_controller.show_result(trial)
	var origins := []
	var visited := []
	var rear_contacts := [{}, {}]
	for team: TerrainArmy in lab.combat_armies:
		team.set_process(false)
		team.native_front_enabled = "--gd-front" not in OS.get_cmdline_user_args()
		origins.append(team.cells.duplicate())
		visited.append({})
	await _capture("before")
	for tick in range(900):
		lab._advance_action_time(STEP)
		for side in range(lab.combat_armies.size()):
			var team: TerrainArmy = lab.combat_armies[side]
			for index in range(team.cells.size()):
				if team.cells[index] != origins[side][index] or team.moving_to[index] != TerrainArmy.INVALID_CELL:
					visited[side][index] = true
				if index >= 50:
					for direction: Vector2i in TerrainData.DIRECTIONS:
						var next := team.cells[index] + direction
						if lab.combat_armies[1 - side]._cell_owners.has(next) and data.can_attack_across(team.cells[index], next):
							rear_contacts[side][index] = true
		_check_claims()
		if (tick + 1) % 150 == 0:
			for side in range(lab.combat_armies.size()):
				var team: TerrainArmy = lab.combat_armies[side]
				var rear := 0
				for index: int in visited[side]: rear += int(index >= 50)
				print("TRIAL_PROBE ", JSON.stringify({"seconds": (tick + 1) * STEP, "side": side, "ever_moved": visited[side].size(), "rear_ever_moved": rear, "moving": team.moving_count(), "order": team.combat_order, "encirclement": team.encirclement_steps, "exchanges": lab.exchange_count}))
	var summaries := []
	for side in range(lab.combat_armies.size()):
		var team: TerrainArmy = lab.combat_armies[side]
		var rear_displaced := 0
		for index in range(50, 100):
			rear_displaced += int(team.cells[index] != origins[side][index])
		assert(rear_displaced >= 40, "Dense main-scene rear must actually leave its original cells, not merely animate or oscillate")
		assert(rear_contacts[side].size() >= 10, "Rear soldiers must reach actual enemy contact, not just wander")
		summaries.append({"team": side, "rear_displaced": rear_displaced, "rear_total": 50,
			"rear_contacted": rear_contacts[side].size(), "ever_moved": visited[side].size()})
	print("BATTLE_REAR_PASS ", JSON.stringify(summaries))
	await _capture("after")
	for site_pause: bool in [false, true]:
		for tree_pause: bool in [false, true]:
			_check_cancel(site_pause, tree_pause)
	assert(FileAccess.get_file_as_string(SAVE) == baseline_save)
	root.close_requested.emit()
	await _capture("exit")
	assert(lab.site_controller._exit_dialog.visible)
	print("UNSAVED_EXIT_PASS combat/busy/IO guards; repeated X; cancel restores both pause states; previous save unchanged; pressing exit now")
	lab.site_controller._exit_dialog.get_ok_button().pressed.emit()
	# Do not call quit here: the production button must actually close this process.

func _check_cancel(site_pause: bool, tree_pause: bool) -> void:
	lab.terrain.site.paused = site_pause
	paused = tree_pause
	var orders := [lab.npc_retaliates, lab.npc.command, lab.army.combat_order, lab.opposing_army.combat_order]
	root.close_requested.emit()
	var dialog: ConfirmationDialog = lab.site_controller._exit_dialog
	assert(is_instance_valid(dialog) and dialog.visible and dialog.can_process())
	assert(paused and lab.terrain.site.paused and lab.site_controller._exit_pending)
	root.close_requested.emit()
	assert(lab.site_controller._exit_dialog == dialog, "Repeated X must reuse one prompt")
	dialog.get_cancel_button().pressed.emit()
	assert(not lab.site_controller._exit_pending and not is_instance_valid(lab.site_controller._exit_dialog))
	assert(paused == tree_pause and lab.terrain.site.paused == site_pause)
	assert(orders == [lab.npc_retaliates, lab.npc.command, lab.army.combat_order, lab.opposing_army.combat_order])
	assert(FileAccess.get_file_as_string(SAVE) == baseline_save)

func _check_claims() -> void:
	var sources := {}
	var claims := {}
	for team: TerrainArmy in lab.combat_armies:
		for cell: Vector2i in team._cell_owners:
			assert(not sources.has(cell), "No body overlap")
			sources[cell] = true
	for team: TerrainArmy in lab.combat_armies:
		for cell: Vector2i in team._reserved_cells:
			var index: int = team._reserved_cells[cell]
			assert(not sources.has(cell) and not claims.has(cell), "No stealing sources or reservations")
			assert(team.moving_to[index] == cell and lab.terrain.can_step(team.cells[index], cell))
			claims[cell] = true

func _capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	for team: TerrainArmy in lab.combat_armies: team.advance_frame(0.0)
	for team: TerrainArmy in lab.combat_armies:
		assert(team._batch_view != null and team._batch_view.rendered_count == team.roster_size - 1,
			"Current main must retain the real ordinary-soldier batch, not silently fall back to sprites")
	lab.site_controller.update_ui()
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_out)) == OK)
	assert(root.get_texture().get_image().save_png(capture_out + "/" + label + ".png") == OK)
	print("BATTLE_EXIT_CAPTURE ", capture_out, "/", label, ".png")
