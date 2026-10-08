extends SceneTree

const OUT := "res://output/site_knockout_recovery_20260926/visual"
const CENTER := Vector2i(60, 60)
var lab: TerrainLab
var caption: Label

func _initialize() -> void:
	create_timer(100.0).timeout.connect(func() -> void: push_error("KO visual internal timeout"); quit(1))
	_run.call_deferred()

func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/terrain_lab/TerrainLab.tscn")
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT)) == OK)
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	lab = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate() as TerrainLab
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller._auto_save_blocked = true
	lab.site_controller.set_process(false)
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "knockout-visual")
	data.resource_base.clear()
	data.resources_at.clear()
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	lab.bind_terrain(data)
	lab.get_node("SiteUI").hide()
	assert(not lab.has_node("TerrainLabUI"), "Legacy debug panel must not be constructed")
	if is_instance_valid(lab.site_test_window): lab.site_test_window.hide()
	var player := lab.character
	player.set_process(false)
	player.faction_id = 0
	assert(player.place(CENTER + Vector2i(1, -1), true))
	var friendly := lab.army
	var enemy := lab.opposing_army
	for team: TerrainArmy in [friendly, enemy]:
		team.set_process(false)
		team.exchange_enabled = true
	friendly.faction_id = 0
	friendly.roster_size = 2
	friendly.initialize_visual()
	var friend_cells: Array[Vector2i] = [CENTER, CENTER + Vector2i.RIGHT]
	assert(friendly.deploy_at(data, player, null, friend_cells) and friendly.enable_combat(true, 1))
	enemy.faction_id = 1
	enemy.roster_size = 1
	enemy.initialize_visual()
	var enemy_cells: Array[Vector2i] = [CENTER + Vector2i(2, 0)]
	assert(enemy.deploy_at(data, player, null, enemy_cells) and enemy.enable_combat(true, 1))
	lab.combat_armies.assign([friendly, enemy])
	friendly.external_blocker = enemy.blocks_cell
	enemy.external_blocker = friendly.blocks_cell
	lab.camera.zoom = Vector2.ONE * 3.1
	lab.camera.position = (Vector2(CENTER) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	lab.camera.force_update_scroll()
	var overlay := CanvasLayer.new()
	lab.add_child(overlay)
	caption = Label.new()
	caption.position = Vector2(30, 20)
	caption.add_theme_font_size_override("font_size", 24)
	overlay.add_child(caption)
	var hit := {"shield": false, "result": {"hp": 1.0, "stun": 110.0, "guard_break": false}}
	friendly.apply_unit_contact(0, hit)
	friendly.apply_unit_contact(1, hit)
	enemy.apply_unit_contact(0, hit)
	friendly.settle_combat_command()
	enemy.settle_combat_command()
	assert(friendly.needs_attack_order and enemy.needs_attack_order)
	friendly.prepare_combat(3.0, 3.0)
	enemy.prepare_combat(3.0, 3.0)
	friendly.advance_frame(0.0)
	enemy.advance_frame(0.0)
	caption.text = "昏迷中｜原隊長與普通兵，待令守位"
	await _capture("01_unconscious.png")
	assert(player.start_rescue_unit(friendly, 1))
	player.advance_combat(4.0)
	assert(friendly.combat_units[1].ko == 3600.0 and friendly.combat_units[1].pose == "unconscious")
	friendly.advance_frame(0.0)
	caption.text = "救助完成｜普通兵仍昏迷，剩餘一遊戲小時"
	await _capture("02_rescued_still_unconscious.png")
	friendly.prepare_combat(0.1, 14397.0)
	enemy.prepare_combat(0.1, 14397.0)
	assert(friendly.combat_units[0].pose == "get_up" and friendly.combat_units[1].pose == "get_up" and enemy.combat_units[0].pose == "get_up")
	friendly.prepare_combat(1.1, 0.0)
	enemy.prepare_combat(1.1, 0.0)
	friendly.advance_frame(1.1)
	enemy.advance_frame(1.1)
	caption.text = "自然甦醒｜起身動作中，尚不能交鋒"
	await _capture("03_get_up.png")
	friendly.prepare_combat(1.1, 0.0)
	enemy.prepare_combat(1.1, 0.0)
	var before := lab.exchange_count
	lab._resolve_exchanges()
	assert(lab.exchange_count > before and friendly.combat_order == TerrainArmy.CombatOrder.HOLD and friendly.needs_attack_order)
	friendly.advance_frame(0.0)
	enemy.advance_frame(0.0)
	caption.text = "起身後｜待令守位，合法相鄰近身自衛"
	await _capture("04_melee_self_defense.png")
	var report := {"main_scene": ProjectSettings.get_setting("application/run/main_scene"),
		"captures": ["01_unconscious.png", "02_rescued_still_unconscious.png", "03_get_up.png", "04_melee_self_defense.png"],
		"friendly_visual_mode": friendly.visual_mode(), "enemy_visual_mode": enemy.visual_mode(),
		"rescued_ko": 3600.0, "exchange_count": lab.exchange_count,
		"scope": "Formal TerrainLab scene, original Actor and Army owners, game-time boundary fast-forward; visual posture only, not wall-clock four hours or FPS."}
	var file := FileAccess.open(OUT + "/result.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SITE_KNOCKOUT_VISUAL_PASS ", JSON.stringify(report))
	lab.queue_free()
	await process_frame
	quit(0)

func _capture(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUT + "/" + filename) == OK)
