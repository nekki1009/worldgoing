extends SceneTree
## Real generator/UI contracts; vehicle motion and production have separate owner tests.
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const OUT := "res://output/site_support_teams_20260918/trial"
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 80000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Trial roles verification deadline")
		quit(1)
	return false

func _choose_role(controller: SiteController, prefix: String, index: int) -> void:
	var option: OptionButton = controller.trial_roles[prefix]
	option.select(index)
	option.item_selected.emit(index)

func _press(controller: SiteController, name: String) -> void:
	var button := controller.combat_window.find_child(name, true, false) as Button
	assert(button != null, "Actual trial control missing: " + name)
	button.pressed.emit()

func _run() -> void:
	assert(DisplayServer.get_name() == "headless")
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	var controller: SiteController = lab.site_controller
	controller.set_process(false)
	controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	for invalid: Dictionary in [{"friendly_role": "ship"}, {"friendly_role": 1}, {"friendly_cart_count": 1},
		{"friendly_role": "work", "friendly_cart_count": 1}, {"friendly_role": "logistics", "friendly_cart_count": -1},
		{"friendly_role": "logistics", "friendly_wagon_count": 100}, {"friendly_role": "logistics", "friendly_cart_count": true},
		{"friendly_role": "logistics", "friendly_cart_count": 0.5}, {"friendly_role": "logistics", "friendly_count": 1, "friendly_cart_count": 1},
		{"friendly_role": "logistics", "friendly_count": 10, "friendly_cart_count": 5, "friendly_wagon_count": 5}]:
		assert(not lab._trial_side_settings(invalid, "friendly").ok, "Invalid role/slot setup accepted: " + str(invalid))
	for count in [0, 1, 2, 7, 50, 99]:
		var parsed := lab._trial_side_settings({"friendly_role": "logistics", "friendly_cart_count": count, "friendly_count": 100}, "friendly")
		assert(parsed.ok and parsed.side.count == 100 - count and parsed.side.slot_count == 100)
		assert(parsed.side.female_count == roundi(float(100 - count) * 0.5) and not parsed.side.attack)
	_choose_role(controller, "friendly", 1)
	_choose_role(controller, "enemy", 2)
	controller.trial_friendly_count.value = 4
	controller.trial_enemy_count.value = 7
	controller.trial_carts.enemy.value = 5
	controller.trial_wagons.enemy.value = 1
	controller.trial_friendly_female_percent.value = 0
	controller.trial_enemy_female_percent.value = 0
	assert(controller.trial_friendly_order.selected == 0 and controller.trial_enemy_order.selected == 0)
	assert(controller.trial_enemy_gender_label.text.contains("男 1／女 0") and controller.trial_enemy_gender_label.text.contains("車 6"))
	var setup := controller._trial_setup()
	var checked_custom_camp := false
	for cell: Vector2i in lab._trial_camp_access():
		if lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell): continue
		var custom := lab._trial_side_settings({"friendly_role": "work", "friendly_count": 1, "friendly_spawn": cell}, "friendly")
		var custom_formation := lab._independent_trial_formations([custom.side])
		assert(not custom_formation.is_empty() and custom_formation[0][0] == cell, "Explicit legal camp-near spawn must stay exactly where chosen")
		checked_custom_camp = true
		break
	assert(checked_custom_camp)
	var isolated_seed: Vector2i = lab._independent_trial_formations([lab._trial_side_settings({"friendly_role": "work", "friendly_count": 1}, "friendly").side])[0][0]
	var isolated_claims := {}
	for direction: Vector2i in TerrainData.DIRECTIONS: isolated_claims[isolated_seed + direction] = true
	assert(lab._trial_connected_formation(isolated_seed, 2, isolated_claims).is_empty(), "Failed connected formation returns a typed empty array without a runtime error")
	var original_site := lab.terrain.site.duplicate(true)
	var site_alias := lab.terrain.site
	var cargo_alias := lab.character.ammo_inventory
	var allocator := lab.opposing_army.person_id_allocator
	lab.opposing_army.person_id_allocator = func(_count: int) -> Array[int]: return []
	assert(lab.start_melee_trial(setup).code == "DEPLOY_FAILED")
	assert(lab.terrain.site == original_site and controller.work_team.active_ids().is_empty(), "Rollback leaked original worker identities or Site data")
	assert(is_same(site_alias, lab.terrain.site) and is_same(cargo_alias, lab.terrain.site.manual.cargo))
	lab.opposing_army.person_id_allocator = allocator
	var next_vehicle := int(lab.terrain.site.next_vehicle)
	lab.terrain.site.next_vehicle = 2147483646
	original_site = lab.terrain.site.duplicate(true)
	assert(lab.start_melee_trial(setup).code == "DEPLOY_FAILED")
	assert(lab.terrain.site == original_site and controller.work_team.active_ids().is_empty() and controller.vehicles.records().is_empty())
	lab.terrain.site.next_vehicle = next_vehicle
	_press(controller, "StartMeleeTrial")
	assert(lab.army.role == "work" and lab.opposing_army.role == "logistics", controller.message.text)
	assert(lab.army.combat_units.size() == 4 and lab.opposing_army.combat_units.size() == 1)
	assert(lab.army.combat_order == TerrainArmy.CombatOrder.HOLD and lab.opposing_army.combat_order == TerrainArmy.CombatOrder.HOLD)
	assert(controller.work_team.active_ids().size() == 3 and not controller.work_team.is_assigned(lab.army.combat_identity(0)))
	for index in range(1, 4):
		assert(controller.work_team.is_assigned(lab.army.combat_identity(index)) and not lab.army.combat_units[index].logistics)
	assert(lab.opposing_army.combat_units[0].logistics and controller.vehicles.records().size() == 6)
	var operated := 0
	var vehicle_kinds := {"cart": 0, "wagon": 0}
	for vehicle: Dictionary in controller.vehicles.records().values():
		operated += int(int(vehicle.operator_id) > 0)
		vehicle_kinds[vehicle.kind] += 1
		assert(vehicle.cargo.is_empty(), "Deployment must not invent supplies")
	assert(operated <= 1 and vehicle_kinds == {"cart": 5, "wagon": 1})
	for first: Vector2i in lab.army.cells:
		for second: Vector2i in lab.opposing_army.cells:
			assert(absi(first.x - second.x) + absi(first.y - second.y) > 8, "Support spawn must not force workers into enemy threat")
	var first_state := lab.army.capture_combat_state()
	var second_state := lab.opposing_army.capture_combat_state()
	var vehicles_before := controller.vehicles.records().duplicate(true)
	_choose_role(controller, "third", 1)
	controller.trial_third_count.value = 2
	controller.trial_third_female_percent.value = 0
	controller.trial_third_faction.select(0)
	allocator = lab.third_army.person_id_allocator
	lab.third_army.person_id_allocator = func(_count: int) -> Array[int]: return []
	assert(lab.add_melee_trial_team(controller._trial_setup()).code == "DEPLOY_FAILED")
	assert(lab.army.capture_combat_state() == first_state and lab.opposing_army.capture_combat_state() == second_state)
	assert(controller.work_team.active_ids().size() == 3 and controller.vehicles.records() == vehicles_before)
	lab.third_army.person_id_allocator = allocator
	_press(controller, "AddThirdMeleeTrial")
	assert(lab.third_army.combat_units.size() == 2 and lab.third_army.role == "work", controller.message.text)
	assert(controller.work_team.active_ids().size() == 4)
	assert(lab.army.capture_combat_state() == first_state and lab.opposing_army.capture_combat_state() == second_state)
	controller.trial_command_team.select(2)
	controller.selected = lab.third_army.cells[0]
	_press(controller, "TrialTeamHold")
	assert(lab.third_army.combat_order == TerrainArmy.CombatOrder.HOLD)
	controller._capture_positions()
	var saved := Store.save(lab.terrain, OUT + "/roles.json")
	assert(saved.ok, str(saved))
	var loaded := Store.load_site(OUT + "/roles.json")
	assert(loaded.ok, str(loaded))
	lab.bind_terrain(loaded.data)
	assert(lab.army.role == "work" and lab.opposing_army.role == "logistics" and lab.third_army.role == "work")
	assert(controller.vehicles.records().size() == 6 and controller.work_team.active_ids().size() == 4)
	assert(controller.combat_summary_label.text.contains("工作隊") and controller.combat_summary_label.text.contains("後勤隊"))
	print("SITE TRIAL ROLES PASS: actual generator controls, slots/person/gender counts, arbitrary 0..99 vehicles, excess parked/no hidden operators, original work assignments, safe independent formations, late human/vehicle rollback with aliases, append preserves owners, three-role Store/bind roundtrip; not vehicle movement or production proof")
	lab.queue_free()
	await process_frame
	# Exercise the maximum with real original terrain and 99 real vehicle records,
	# not only settings parsing. The one operator is an existing NPC row.
	lab = TerrainLab.new()
	root.add_child(lab)
	lab.set_process(false)
	controller = lab.site_controller
	controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	var original_flags := lab.terrain.flags.duplicate()
	var original_sources := lab.terrain.resource_base.duplicate(true)
	var maximum := lab.start_melee_trial({"friendly_role": "logistics", "friendly_count": 100,
		"friendly_cart_count": 99, "friendly_female_percent": 100, "enemy_role": "work", "enemy_count": 1})
	assert(maximum.ok, "Original main terrain must accommodate this actual maximum test: " + str(maximum))
	assert(lab.army.combat_units.size() == 1 and lab.army.combat_units[0].appearance.body == 1)
	assert(controller.vehicles.records().size() == 99 and lab.terrain.flags == original_flags and lab.terrain.resource_base == original_sources)
	operated = 0
	for vehicle: Dictionary in controller.vehicles.records().values():
		operated += int(int(vehicle.operator_id) > 0)
		assert(vehicle.kind == "cart" and vehicle.cargo.is_empty())
	assert(operated == 1, "Exactly the one real NPC may operate; the remaining 98 cars stay parked")
	controller._capture_positions()
	saved = Store.save(lab.terrain, OUT + "/maximum_99.json")
	assert(saved.ok, str(saved))
	loaded = Store.load_site(OUT + "/maximum_99.json")
	assert(loaded.ok, str(loaded))
	lab.bind_terrain(loaded.data)
	assert(lab.army.combat_units.size() == 1 and controller.vehicles.records().size() == 99)
	print("SITE_TRIAL_MAXIMUM_PASS: actual original map deployment and Store/bind of 1 real woman plus 99 carts, exactly 1 operator and 98 parked; original terrain/resources unchanged")
	lab.queue_free()
	await process_frame
	quit(0)
