extends SceneTree
## Formal Lab/UI deployment, actual holders, homogeneous troops and Site restore.
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const OUT := "res://output/ranged_behavior_fix_20260918/deployment"
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 90000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Ranged deployment integration deadline")
		quit(1)
	return false

func _assert_team(team: TerrainArmy, weapon: String, women: int, spent_first: int = 0) -> void:
	var ammo := "arrow" if weapon == "bow_01" else "bolt"
	var female_count := 0
	for index in range(team.combat_units.size()):
		var row: Dictionary = team.combat_units[index]
		var appearance := team.equipment_appearance(index)
		assert(appearance.parts.weapon == weapon and appearance.parts.shield == "none")
		female_count += int(appearance.body == 1)
		assert(str(row.visual_role).begins_with("female") == (appearance.body == 1))
		assert(row.cargo == {ammo: 20 - (spent_first if index == 0 else 0)}, "Only actual carried test ammo is initialized; restore cannot refill it")
		assert(SiteRuntime.carried_size(row.cargo, row.item_state) <= SiteRuntime.CARRY_CAPACITY)
		var record: Dictionary = team.data.site.item_records[row.item_state.equipped.weapon]
		assert(str(record.holder) == "person:%d" % team.combat_identity(index))
		assert(team.data.site.item_definitions[record.definition].asset == weapon)
		if not team._uses_live_presenter(index):
			assert(team.supports_equipment_recipe(appearance))
	assert(female_count == women)
	assert(TerrainArmy.single_troop_class(team.combat_units, team.data, team._troop_exempt_ids()) == (&"bow" if weapon == "bow_01" else &"crossbow"))

func _run() -> void:
	assert(DisplayServer.get_name() == "headless")
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	var controller: SiteController = lab.site_controller
	for prefix: String in ["friendly", "enemy", "third"]:
		var choice: OptionButton = controller.trial_troop_types[prefix]
		assert(controller.combat_window.is_ancestor_of(choice) and choice.item_count == 3)
		assert(choice.name == prefix.capitalize() + "TroopType")
		choice.select(2)
		controller.trial_roles[prefix].select(1)
		controller._trial_role_changed(prefix)
		assert(choice.disabled and choice.selected == 0)
		assert(controller._trial_setup()[prefix + "_troop_type"] == "melee_infantry")
		controller.trial_roles[prefix].select(2)
		controller._trial_role_changed(prefix)
		assert(choice.disabled and choice.selected == 0)
		controller.trial_roles[prefix].select(0)
		controller._trial_role_changed(prefix)
		assert(not choice.disabled)
	for invalid: Dictionary in [
		{"friendly_troop_type": "mixed"}, {"enemy_troop_type": true},
		{"friendly_role": "work", "friendly_troop_type": "bow"},
		{"enemy_role": "logistics", "enemy_troop_type": "crossbow"},
		{"third_enabled": true, "third_troop_type": "invalid"},
	]:
		var before := var_to_bytes(lab.terrain.site)
		assert(lab.start_melee_trial(invalid).code == "INVALID")
		assert(var_to_bytes(lab.terrain.site) == before and not lab.army.has_army())
	controller.trial_friendly_count.value = 6
	controller.trial_enemy_count.value = 4
	controller.trial_third_count.value = 3
	controller.trial_friendly_female_percent.value = 50
	controller.trial_enemy_female_percent.value = 50
	controller.trial_third_female_percent.value = 100
	controller.trial_troop_types.friendly.select(1)
	controller.trial_troop_types.enemy.select(2)
	controller.trial_troop_types.third.select(1)
	controller.trial_friendly_order.select(0)
	controller.trial_enemy_order.select(0)
	controller.trial_third_order.select(0)
	controller.trial_third_enabled.button_pressed = true
	var setup := controller._trial_setup()
	assert(setup.friendly_troop_type == "bow" and setup.enemy_troop_type == "crossbow" and setup.third_troop_type == "bow")
	controller._deploy_melee_trial()
	assert(lab.army.combat_units.size() == 6 and lab.opposing_army.combat_units.size() == 4 and lab.third_army.combat_units.size() == 3, controller.message.text)
	assert(lab.army.cells[0].distance_to(lab.opposing_army.cells[0]) == 6.0, "Automatic ranged deployment leaves six cells between fronts")
	_assert_team(lab.army, "bow_01", 3)
	_assert_team(lab.opposing_army, "crossbow_01", 2)
	_assert_team(lab.third_army, "bow_01", 3)
	var mixed := lab.army.equipment_appearance(1).duplicate(true)
	mixed.parts.weapon = "crossbow_01"
	var person := controller.person_actions._person(lab.army.combat_identity(1))
	var held_before := var_to_bytes(lab.terrain.site.item_records)
	assert(controller._equipment_recipe_guard(person, mixed).code == "MIXED_TROOP")
	assert(var_to_bytes(lab.terrain.site.item_records) == held_before)
	assert(lab.army.ranged_fire(0, lab.opposing_army.cells[0], 7001))
	assert(lab.army.combat_units[0].cargo.arrow == 19 and controller.supply_save_guard().code == "BUSY")
	lab._advance_ranged(2.0)
	for tick in range(450): lab._process(TerrainLab.EXCHANGE_ACTION_STEP)
	assert(not lab.has_ranged_projectiles() and is_zero_approx(float(lab.terrain.site.combat_left)))
	_assert_team(lab.army, "bow_01", 3, 1)
	controller._capture_positions()
	assert(Store.save(lab.terrain, OUT + "/three_troops.json").ok)
	var loaded := Store.load_site(OUT + "/three_troops.json")
	assert(loaded.ok and loaded.data.site.armies.size() == 3)
	lab.bind_terrain(loaded.data)
	controller._auto_save_blocked = true
	_assert_team(lab.army, "bow_01", 3, 1)
	_assert_team(lab.opposing_army, "crossbow_01", 2)
	_assert_team(lab.third_army, "bow_01", 3)
	lab.clear_army()
	assert(not lab.army.has_army() and not lab.third_army.has_army())
	var invalid_spawn := {"friendly_count": 3, "enemy_count": 3, "friendly_troop_type": "bow", "enemy_troop_type": "crossbow",
		"friendly_spawn": lab.character.terrain_cell, "enemy_spawn": lab.character.terrain_cell + Vector2i(6, 0)}
	var before_spawn := var_to_bytes(lab.terrain.site)
	assert(not lab.start_melee_trial(invalid_spawn).ok)
	assert(var_to_bytes(lab.terrain.site) == before_spawn and not lab.army.has_army())
	var first_two := {"friendly_count": 3, "enemy_count": 3, "friendly_troop_type": "bow", "enemy_troop_type": "crossbow",
		"friendly_female_percent": 0, "enemy_female_percent": 100, "friendly_attack": false, "enemy_attack": false}
	var deployed := lab.start_melee_trial(first_two)
	assert(deployed.ok, str(deployed))
	var first_cargo: Dictionary = lab.army.combat_units[0].cargo
	var site_alias: Dictionary = lab.terrain.site
	var original_site := var_to_bytes(lab.terrain.site)
	var first_snapshot := lab.army.capture_combat_state()
	var original_initializer: Callable = lab.third_army.equipment_initializer
	lab.third_army.equipment_initializer = func(team: TerrainArmy) -> void:
		original_initializer.call(team)
		team.combat_units[0].cargo.wood = 1 # Force the final real capacity guard, after initial items/IDs were allocated.
	var third := {"third_count": 3, "third_female_percent": 100, "third_troop_type": "crossbow", "third_attack": false}
	var failed := lab.add_melee_trial_team(third)
	lab.third_army.equipment_initializer = original_initializer
	assert(not failed.ok and failed.code == "DEPLOY_FAILED", str(failed))
	assert(not lab.third_army.has_army() and lab.army.capture_combat_state() == first_snapshot)
	assert(is_same(lab.terrain.site, site_alias) and is_same(lab.army.combat_units[0].cargo, first_cargo))
	assert(var_to_bytes(lab.terrain.site) == original_site, "Late capacity failure preserves items, allocators and existing ammo")
	var added := lab.add_melee_trial_team(third)
	assert(added.ok and added.third_troop_type == "crossbow", str(added))
	assert(lab.army.capture_combat_state() == first_snapshot and is_same(lab.army.combat_units[0].cargo, first_cargo))
	_assert_team(lab.third_army, "crossbow_01", 3)
	controller._capture_positions()
	assert(Store.save(lab.terrain, OUT + "/appended_troop.json").ok)
	lab.clear_army()
	var support := lab.start_melee_trial({"friendly_count": 2, "enemy_count": 3, "friendly_role": "work", "enemy_role": "logistics",
		"enemy_cart_count": 1, "friendly_attack": false, "enemy_attack": false})
	assert(support.ok and lab.army.role == "work" and lab.opposing_army.role == "logistics", str(support))
	for team: TerrainArmy in [lab.army, lab.opposing_army]:
		for index in range(team.combat_units.size()):
			assert(team.equipment_appearance(index).parts.weapon == "longsword_01")
			assert(int(team.combat_units[index].cargo.get("arrow", 0)) == 0 and int(team.combat_units[index].cargo.get("bolt", 0)) == 0)
	controller._capture_positions()
	assert(Store.save(lab.terrain, OUT + "/support_unchanged.json").ok)
	print("SITE RANGED DEPLOYMENT PASS: UI three troop selectors; formal mixed-gender bow/crossbow teams; real 20-round holders; six-cell deployment; spent ammo save/restore; homogeneous guard; atomic invalid/late-failed/third append; original work/logistics")
	lab.queue_free()
	await process_frame
	quit(0)
