extends SceneTree

const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE := "res://.godot-temp/site_battle_window/state.json"

var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 30000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("SITE BATTLE WINDOW test timed out")
		quit(1)
	return false

func _run() -> void:
	assert(DisplayServer.get_name() == "headless")
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies:
		team.set_process(false)
	var controller: SiteController = lab.site_controller
	assert(controller.top_banner.get_parent() == lab.get_node("SiteUI"))
	assert(controller.top_banner.is_ancestor_of(controller.clock_label))
	assert(controller.top_banner.is_ancestor_of(controller.pause_button))
	assert(controller.top_banner.is_ancestor_of(controller.player_status_label))
	assert(not controller.panel.is_ancestor_of(controller.clock_label))
	assert(not controller.panel.is_ancestor_of(controller.pause_button))
	assert(controller.panel.is_ancestor_of(lab.find_child("SaveSite", true, false)))
	assert(controller.panel.is_ancestor_of(lab.find_child("LoadSite", true, false)))
	assert(lab.find_child("SlowerSite", true, false) != null and lab.find_child("FasterSite", true, false) != null)
	controller._layout()
	assert(controller.top_banner.position.x + controller.top_banner.size.x <= controller.panel.position.x - 16.0 + 0.01)
	_assert_status_layout(controller, lab.get_viewport_rect().size, SiteController.PANEL_SCALE)
	var original_size := root.size
	var original_content_scale_size := root.content_scale_size
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	lab.get_node("TerrainLabUI").show()
	controller._layout()
	_assert_status_layout(controller, lab.get_viewport_rect().size, SiteController.PANEL_SCALE - 0.01)
	lab.get_node("TerrainLabUI").hide()
	root.size = original_size
	root.content_scale_size = original_content_scale_size
	controller._layout()
	controller.update_ui()
	assert(("#%d" % lab.controlled_person_id()) in controller.player_status_label.text)
	assert("攜帶" in controller.player_status_label.text and "疲勞" in controller.player_status_label.text and "手動作業" in controller.player_status_label.text)
	assert("本人" not in controller.stock_label.text and "營地" in controller.stock_label.text)
	var time_before := SiteRuntime.now(lab.terrain)
	assert(lab.change_simulation_speed(-1) == 0.5 and "0.5" in controller.speed_label.text)
	lab._process(1.0)
	assert(is_equal_approx(SiteRuntime.now(lab.terrain) - time_before, 0.5), "Half speed advances the peaceful Site clock by half a game minute")
	assert(lab.change_simulation_speed(1) == 1.0)
	assert(lab.change_simulation_speed(2) == 2.0 and lab.change_simulation_speed(2) == 4.0)
	lab.character.exchange_stagger = 1.0
	time_before = SiteRuntime.now(lab.terrain)
	lab._process(0.3)
	assert(is_equal_approx(lab.character.exchange_stagger, 0.7) and is_equal_approx(lab.character.action_time, 0.7), "Time speed must not accelerate a person's action seconds")
	assert(is_equal_approx(SiteRuntime.now(lab.terrain) - time_before, 1.2), "Four-times speed advances the peaceful Site clock and work by four")
	lab.terrain.site.combat_left = 0.1
	lab.character.exchange_stagger = 1.0
	time_before = SiteRuntime.now(lab.terrain)
	lab._process(0.3)
	assert(is_equal_approx(lab.character.exchange_stagger, 0.7) and is_equal_approx(lab.character.action_time, 0.7)
		and is_zero_approx(float(lab.terrain.site.combat_left)), "Combat boundary and action seconds remain on the unaccelerated real-time clock")
	assert(is_equal_approx(SiteRuntime.now(lab.terrain) - time_before, (0.1 + 0.2 * 60.0) * 4.0 / 60.0), "Four-times Site time integrates the combat-to-peace boundary without accelerating actions")
	assert(lab.change_simulation_speed(-3) == 2.0 and lab.change_simulation_speed(-2) == 1.0)
	assert(controller.status_panel.is_ancestor_of(controller.details))
	assert(controller.status_panel.is_ancestor_of(controller.message))
	assert(not controller.panel.is_ancestor_of(controller.details))
	assert(controller.combat_window.is_ancestor_of(lab.find_child("StartMeleeTrial", true, false)))
	assert(not controller.panel.is_ancestor_of(lab.find_child("StartMeleeTrial", true, false)))
	assert(lab.npc.editor == null and lab.npc.player_sprite == null)
	assert(lab.npc.visual_state.body_index == 1, "Hidden worker must retain the existing save appearance contract")
	for invalid: Dictionary in [
		{"friendly_count": 1.5},
		{"friendly_count": true},
		{"enemy_count": "8"},
		{"friendly_training": NAN},
		{"enemy_training": 250.5},
		{"friendly_tactics": 50.5},
		{"enemy_leadership": 101},
		{"friendly_coach": true},
		{"friendly_female_percent": -1},
		{"enemy_female_percent": 101},
		{"friendly_female_percent": 33.3},
		{"friendly_female_percent": NAN},
		{"enemy_female_percent": true},
	]:
		var invalid_result := lab.start_melee_trial(invalid)
		assert(not invalid_result.ok and not lab.army.has_army() and not lab.opposing_army.has_army())
	var layout := lab.find_melee_trial_layout(12, 8)
	assert(not layout.is_empty())
	assert(lab.find_melee_trial_layout(1, 1, layout.friendly[0], layout.enemy[2]).is_empty(),
		"Separated custom spawns must be rejected because ATTACK intentionally has no whole-map pursuit")
	controller.trial_friendly_count.value = 12
	controller.trial_enemy_count.value = 8
	controller.trial_friendly_female_percent.value = 25
	controller.trial_enemy_female_percent.value = 100
	assert(controller.trial_friendly_gender_label.text == "男 9／女 3")
	assert(controller.trial_enemy_gender_label.text == "男 0／女 8")
	controller.trial_friendly_training.value = 250
	controller.trial_enemy_training.value = 500
	controller.trial_friendly_tactics.value = 80
	controller.trial_friendly_leadership.value = 60
	controller.trial_friendly_coach.value = 40
	controller.trial_enemy_tactics.value = 20
	controller.trial_enemy_leadership.value = 30
	controller.trial_enemy_coach.value = 70
	controller.trial_friendly_order.select(0)
	controller.trial_enemy_order.select(1)
	controller.selected = layout.friendly[0]
	controller._set_trial_spawn(true)
	controller.selected = layout.enemy[0]
	controller._set_trial_spawn(false)
	controller._deploy_melee_trial()
	assert(lab.army.combat_units.size() == 12 and lab.opposing_army.combat_units.size() == 8)
	_assert_genders(lab.army.combat_units, 3)
	_assert_genders(lab.opposing_army.combat_units, 8)
	assert(lab.army.cells[0] == layout.friendly[0] and lab.opposing_army.cells[0] == layout.enemy[0])
	assert(lab.army.training == 250.0 and lab.opposing_army.training == 500.0)
	assert(TerrainArmy.TROOP_TYPE_ID == &"melee_infantry" and TerrainArmy.TROOP_TYPE_NAME == "近戰步兵"
		and TerrainArmy.TROOP_COMBAT_ABILITY == 50.0)
	lab.army.combat_units[1].combat_ability = 0.0
	lab.army.combat_units[2].combat_ability = 100.0
	assert(lab.army.exchange_stats(1).ability == TerrainArmy.TROOP_COMBAT_ABILITY
		and lab.army.exchange_stats(2).ability == TerrainArmy.TROOP_COMBAT_ABILITY,
		"Ordinary rows share the one troop-type base despite legacy per-row values")
	assert(lab.army.command_abilities[lab.army.formal_commander] == {"tactics": 80, "leadership": 60, "coach": 40})
	assert(lab.opposing_army.command_abilities[lab.opposing_army.formal_commander] == {"tactics": 20, "leadership": 30, "coach": 70})
	assert(not lab.army.combat_attacking and lab.opposing_army.combat_attacking)
	assert(lab.army.combat_order == TerrainArmy.CombatOrder.HOLD and lab.opposing_army.combat_order == TerrainArmy.CombatOrder.ATTACK)
	assert("前排牽制" in lab.opposing_army.command_status and "後排" in lab.opposing_army.command_status)
	controller._show_melee_trial_status()
	assert("\n" not in controller.message.text and "戰鬥測試視窗" in controller.message.text)
	assert("我方：" in controller.combat_summary_label.text and "敵方：" in controller.combat_summary_label.text)
	controller._capture_positions()
	assert(Store.save(lab.terrain, SAVE).ok, "Variable team sizes must satisfy the Site save contract")
	var loaded := Store.load_site(SAVE)
	assert(loaded.ok and loaded.data.site.armies.size() == 2)
	assert(loaded.data.site.armies[0].units.size() == 12 and loaded.data.site.armies[1].units.size() == 8)
	_assert_genders(loaded.data.site.armies[0].units, 3)
	_assert_genders(loaded.data.site.armies[1].units, 8)
	assert(int(loaded.data.site.actors.npc.appearance.body) == 1, "Hidden worker appearance changed in save/load")
	lab.clear_army()
	assert(not lab.army.has_army() and not lab.opposing_army.has_army())
	var rejected := lab.start_melee_trial({
		"friendly_count": 12,
		"enemy_count": 8,
		"friendly_spawn": lab.character.terrain_cell,
		"enemy_spawn": layout.enemy[0],
	})
	assert(not rejected.ok and not lab.army.has_army() and not lab.opposing_army.has_army())
	var allocator_before := int(lab.terrain.site.next_person_id)
	var item_records_before := JSON.stringify(lab.terrain.site.item_records)
	var ground_loot_before := JSON.stringify(lab.terrain.site.ground_loot)
	lab.terrain.site.next_person_id = 2147483600
	var exhausted := lab.start_melee_trial({"friendly_count": 100, "enemy_count": 100})
	assert(not exhausted.ok and exhausted.code == "NO_IDS")
	assert(int(lab.terrain.site.next_person_id) == 2147483600)
	assert(JSON.stringify(lab.terrain.site.item_records) == item_records_before and JSON.stringify(lab.terrain.site.ground_loot) == ground_loot_before)
	assert(not lab.army.has_army() and not lab.opposing_army.has_army())
	lab.terrain.site.next_person_id = allocator_before
	var legacy := lab.start_melee_trial()
	assert(legacy.ok)
	assert(lab.army.combat_units.size() == 100 and lab.opposing_army.combat_units.size() == 100)
	_assert_genders(lab.army.combat_units, 50)
	_assert_genders(lab.opposing_army.combat_units, 50)
	lab.clear_army()
	for sample: Array in [[7, 50, 4], [1, 0, 0], [1, 100, 1], [100, 0, 0], [100, 100, 100]]:
		var result := lab.start_melee_trial({"friendly_count": sample[0], "enemy_count": 1, "friendly_female_percent": sample[1], "enemy_female_percent": 0, "friendly_attack": false, "enemy_attack": false})
		assert(result.ok)
		_assert_genders(lab.army.combat_units, sample[2])
		_assert_genders(lab.opposing_army.combat_units, 0)
		controller._capture_positions()
		assert(Store.save(lab.terrain, SAVE).ok)
		lab.clear_army()
	# The old automatic 20x10 contract rejected a cliff through the center seam.
	for index in range(lab.terrain.flags.size()):
		lab.terrain.flags[index] = 0
		lab.terrain.static_blocked[index] = 0
	var player_cell := lab.terrain.size - Vector2i(3, 3)
	var worker_cell := lab.terrain.size - Vector2i(4, 3)
	for actor_cell: Vector2i in [player_cell, worker_cell]:
		var actor_index := lab.terrain.index(actor_cell)
		lab.terrain.flags[actor_index] = TerrainData.Flag.WALKABLE
		lab.terrain.height_levels[actor_index] = 0
	assert(lab.character.place(player_cell, true) and lab.npc.place(worker_cell, true))
	var origin := Vector2i(2, 2)
	for row in range(10):
		for column in range(20):
			var cell := origin + Vector2i(column, row)
			var index := lab.terrain.index(cell)
			lab.terrain.flags[index] = TerrainData.Flag.WALKABLE
			lab.terrain.height_levels[index] = 0 if column < 10 else 3
	assert(lab.find_melee_trial_layout(100, 100).is_empty(), "Automatic deployment crossed a blocked center seam")
	print("SITE BATTLE WINDOW PASS: responsive status layout, top banner ownership/player status, popup ownership, validated inputs, 12v8 save/load, atomic rejection, connected 100v100 compatibility, no female main presenter")
	lab.queue_free()
	await process_frame
	quit(0)

func _assert_genders(units: Array, expected_female: int) -> void:
	var female := 0
	for index in range(units.size()):
		var unit: Dictionary = units[index]
		female += int(unit.appearance.body == 1)
		assert(str(unit.visual_role).begins_with("female") == (unit.appearance.body == 1))
		assert(str(unit.visual_role).ends_with("live") == (index == 0))
	assert(female == expected_female, "Actual people and persisted appearances must match the ratio")

func _assert_status_layout(controller: SiteController, screen: Vector2, maximum_scale: float) -> void:
	assert(controller.status_panel.visible, "status hidden screen=%s panel=%s top=%s status_position=%s status_size=%s status_scale=%s debug=%s" % [screen, controller.panel.position, controller.top_banner.size, controller.status_panel.position, controller.status_panel.size, controller.status_panel.scale, controller.lab.get_node("TerrainLabUI").visible])
	assert(controller.status_panel.scale.x <= maximum_scale + 0.01)
	var status_end := controller.status_panel.position + controller.status_panel.size * controller.status_panel.scale
	assert(status_end.x <= controller.panel.position.x - 16.0 + 0.01)
	assert(controller.status_panel.position.y >= controller.top_banner.position.y + controller.top_banner.size.y + 16.0 - 0.01)
	assert(status_end.y <= screen.y - 16.0 + 0.01)
