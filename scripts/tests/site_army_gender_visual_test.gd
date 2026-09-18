extends SceneTree
const OUT := "res://output/terrain_army_gender_20260918/visual"

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void: push_error("Gender visual deadline"); quit(1))
	_run.call_deferred()

func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	root.size = Vector2i(1600, 1000)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	DirAccess.make_dir_recursive_absolute(OUT)
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	var result := lab.start_melee_trial({"friendly_count": 20, "enemy_count": 20, "friendly_female_percent": 50, "enemy_female_percent": 100, "friendly_attack": false, "enemy_attack": false})
	assert(result.ok)
	assert(lab.army.has_army() and lab.opposing_army.has_army() and not lab.third_army.has_army())
	for team: TerrainArmy in lab.combat_armies:
		if not team.has_army(): continue
		team.set_process(false)
		team._visual_dirty = true
		team.advance_frame(0.0)
		assert(team._batch_view == null, "Small rosters retain the Sprite path")
		assert(team._live_presenters.size() == 1)
		for index in range(team.roster_size):
			var appearance := team.equipment_appearance(index)
			assert(appearance.has("equipment_dyes"))
			if index == 0:
				assert(int(team._unit_editor(index).capture_appearance().body) == int(appearance.body))
			else:
				assert(team._sprites[index] != null and team._sprites[index].texture != null, "Every male/female ordinary soldier must render")
	lab.camera.zoom = Vector2.ONE * 1.05
	lab.camera.position += Vector2(200, 0)
	lab.camera.force_update_scroll()
	for index in range(8): await process_frame
	await _capture("mixed_and_female_teams")
	lab.site_controller._open_combat_window()
	lab.site_controller.trial_friendly_count.value = 20
	lab.site_controller.trial_enemy_count.value = 20
	lab.site_controller.trial_friendly_female_percent.value = 50
	lab.site_controller.trial_enemy_female_percent.value = 100
	await _capture("gender_menu")
	lab.site_controller.combat_window.hide()
	lab.clear_army()
	assert(not lab.army.has_army())
	result = lab.start_melee_trial({"friendly_count": 100, "enemy_count": 100, "friendly_female_percent": 0, "enemy_female_percent": 100, "friendly_attack": false, "enemy_attack": false})
	assert(result.ok)
	assert(lab.army._unit_editor(0).capture_appearance().body == 0 and lab.opposing_army._unit_editor(0).capture_appearance().body == 1)
	for team: TerrainArmy in lab.combat_armies:
		if not team.has_army(): continue
		team.set_process(false)
		team._visual_dirty = true
		team.advance_frame(0.0)
		assert(team._batch_view != null and team._batch_view.rendered_count == 99)
		for index in range(1, 100): assert(team._batch_view._page[index] >= 0)
	print("ARMY GENDER VISUAL PASS: mixed/female 20-person Sprite teams; 100v100 batch teams with 198 atlas soldiers + 2 live captains, dyes, 0/100-percent captain body switch; inspect PNG")
	lab.queue_free()
	await process_frame
	quit()

func _capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUT + "/" + label + ".png") == OK)
