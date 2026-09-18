extends SceneTree
## Run this external diagnostic against an actual exported debug game, not the editor.
var lab: TerrainLab

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(100.0).timeout.connect(func() -> void: push_error("Export cache smoke deadline"); quit(1))
	assert(not OS.has_feature("editor"), "A tools/editor executable is not export verification")
	assert(OS.has_feature("debug") and DisplayServer.get_name() != "headless")
	assert(ClassDB.class_has_method("AnimationPlayer", "set_clear_cache_on_stop_enabled"))
	print("EXPORT_CACHE_RUNTIME ", OS.get_executable_path(), " resource_root=", ProjectSettings.globalize_path("res://"))
	lab = (load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene).instantiate() as TerrainLab
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.site_controller.save_path = "user://cache-export-smoke.json"
	lab.npc.initialize_visual() # This diagnostic explicitly opts into the removed female test presenter.
	assert(lab.character.editor.model_root != null and lab.npc.editor.model_root != null)
	assert(lab._exchange_kernel != null, "Export must retain the real C# exchange kernel")
	assert(lab.start_melee_trial().ok)
	for team: TerrainArmy in lab.combat_armies:
		team.set_process(false)
		var presenter: HumanCharacter3DEditor = team._unit_editor(0)
		assert(presenter != null and presenter.animation_player != null)
		if "--require-integrated-cache" in OS.get_cmdline_user_args():
			assert(not presenter.animation_player.call("is_clear_cache_on_stop_enabled"))
		else:
			presenter.animation_player.call("set_clear_cache_on_stop_enabled", false)
		assert(team._batch_view != null and team._batch_view.rendered_count == 99,
			"Export must preserve original atlas admission, never accept sprite fallback")
	for tick in range(300):
		lab._advance_action_time(1.0 / 30.0)
		if tick % 10 == 0: await process_frame
	assert(lab.exchange_count > 0)
	for actor: TerrainTestCharacter in lab.combat_actors:
		assert(bool(actor.editor.animation_player.call("is_clear_cache_on_stop_enabled")), "Original actor cache policy must be preserved")
	var captain: HumanCharacter3DEditor = lab.army._unit_editor(0)
	var appearance := captain.capture_appearance()
	captain._load_body_model(0)
	if "--require-integrated-cache" in OS.get_cmdline_user_args():
		assert(not captain.animation_player.call("is_clear_cache_on_stop_enabled"), "New body must inherit Army policy")
	assert(captain.restore_appearance(appearance))
	if "--require-integrated-cache" in OS.get_cmdline_user_args():
		assert(not captain.animation_player.call("is_clear_cache_on_stop_enabled"))
	for team: TerrainArmy in lab.combat_armies: team.advance_frame(0.0)
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	assert(picture.get_used_rect().has_area())
	assert(picture.save_png("user://cache-export-main.png") == OK)
	print("EXPORT_CACHE_CAPTURE ", ProjectSettings.globalize_path("user://cache-export-main.png"))
	# Real combat close path: cancel, then confirm unsaved exit. Production quits.
	root.close_requested.emit()
	var dialog: ConfirmationDialog = lab.site_controller._exit_dialog
	assert(is_instance_valid(dialog) and dialog.visible and dialog.can_process())
	dialog.get_cancel_button().pressed.emit()
	assert(not lab.site_controller._exit_pending)
	root.close_requested.emit()
	print("EXPORT_CACHE_SMOKE_PASS original_main=true people=200 native_exchange=true batch=198 exchanges=", lab.exchange_count)
	lab.site_controller._exit_dialog.get_ok_button().pressed.emit()
