extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")

var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 90000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("SITE BATTLE SPAWN DIRECTION test timed out")
		quit(1)
	return false

func _assert_entry(cells: Array[Vector2i], direction: String, terrain: TerrainData, count: int) -> void:
	assert(cells.size() == count, "Every original person must have a legal spawn")
	var entry := cells[0]
	match direction:
		"north": assert(entry.y == 0, "North must originate on the actual north edge: %s" % entry)
		"south": assert(entry.y == terrain.size.y - 1, "South must originate on the actual south edge")
		"west": assert(entry.x == 0, "West must originate on the actual west edge")
		"east": assert(entry.x == terrain.size.x - 1, "East must originate on the actual east edge")
	var connected := {}
	for cell: Vector2i in cells:
		assert(terrain.is_walkable(cell) and not connected.has(cell), "No overlapping or illegal deployment")
		var joins_source := connected.is_empty()
		for step: Vector2i in TerrainData.DIRECTIONS:
			joins_source = joins_source or connected.has(cell + step) and terrain.can_step(cell, cell + step)
		assert(joins_source, "Every spawned cell must connect to the selected entrance")
		connected[cell] = true

func _assert_existing_teams(lab: TerrainLab, before: Array[Dictionary]) -> void:
	assert(lab.army.capture_combat_state() == before[0], "Appending must preserve original friendly people, items, commands and claims")
	assert(lab.opposing_army.capture_combat_state() == before[1], "Appending must preserve original enemy people, items, commands and claims")

func _run() -> void:
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
	var terrain: TerrainData = lab.terrain
	for toggle: CheckBox in controller.trial_ai_enabled.values():
		toggle.button_pressed = false

	# 1. Test find_melee_trial_layout with legacy default (unspecified directions -> adjacent front)
	var default_layout := lab.find_melee_trial_layout(12, 8)
	assert(not default_layout.is_empty(), "Default layout must succeed")

	# 2. Test independent directional entry sectors (Friendly vs Enemy)
	# Case A: Friendly West, Enemy East (Horizontal standard)
	var we_layout := lab.find_melee_trial_layout(100, 100, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, 0, TerrainArmy.INVALID_CELL, 0.0, 0.0, "", "west", "east")
	assert(not we_layout.is_empty(), "Layout for West vs East must succeed")
	assert(we_layout.friendly[0].x < terrain.size.x * 0.45, "Friendly must be in West sector (x < 45%%)")
	assert(we_layout.enemy[0].x > terrain.size.x * 0.55, "Enemy must be in East sector (x > 55%%)")
	_assert_entry(we_layout.friendly, "west", terrain, 100)
	_assert_entry(we_layout.enemy, "east", terrain, 100)

	# Case B: Friendly East, Enemy West (Horizontal inverted)
	var ew_layout := lab.find_melee_trial_layout(100, 100, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, 0, TerrainArmy.INVALID_CELL, 0.0, 0.0, "", "east", "west")
	assert(not ew_layout.is_empty(), "Layout for East vs West must succeed")
	assert(ew_layout.friendly[0].x > terrain.size.x * 0.55, "Friendly must be in East sector (x > 55%%)")
	assert(ew_layout.enemy[0].x < terrain.size.x * 0.45, "Enemy must be in West sector (x < 45%%)")
	_assert_entry(ew_layout.friendly, "east", terrain, 100)
	_assert_entry(ew_layout.enemy, "west", terrain, 100)

	# Case C: Friendly North, Enemy South (Vertical standard)
	var ns_layout := lab.find_melee_trial_layout(100, 100, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, 0, TerrainArmy.INVALID_CELL, 0.0, 0.0, "", "north", "south")
	assert(not ns_layout.is_empty(), "Layout for North vs South must succeed")
	assert(ns_layout.friendly[0].y < terrain.size.y * 0.45, "Friendly must be in North sector (y < 45%%)")
	assert(ns_layout.enemy[0].y > terrain.size.y * 0.55, "Enemy must be in South sector (y > 55%%)")
	_assert_entry(ns_layout.friendly, "north", terrain, 100)
	_assert_entry(ns_layout.enemy, "south", terrain, 100)

	# Case D: Friendly South, Enemy North (Vertical inverted)
	var sn_layout := lab.find_melee_trial_layout(100, 100, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, 0, TerrainArmy.INVALID_CELL, 0.0, 0.0, "", "south", "north")
	assert(not sn_layout.is_empty(), "Layout for South vs North must succeed")
	assert(sn_layout.friendly[0].y > terrain.size.y * 0.55, "Friendly must be in South sector (y > 55%%)")
	assert(sn_layout.enemy[0].y < terrain.size.y * 0.45, "Enemy must be in North sector (y < 45%%)")
	_assert_entry(sn_layout.friendly, "south", terrain, 100)
	_assert_entry(sn_layout.enemy, "north", terrain, 100)

	# Case E: 3 Teams with independent directions (Friendly West, Enemy East, Third North)
	var wet_layout := lab.find_melee_trial_layout(100, 100, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, 100, TerrainArmy.INVALID_CELL, 0.0, 0.0, "", "west", "east", "north")
	assert(not wet_layout.is_empty(), "3-team layout must succeed")
	assert(wet_layout.friendly[0].x < terrain.size.x * 0.45, "Friendly in West")
	assert(wet_layout.enemy[0].x > terrain.size.x * 0.55, "Enemy in East")
	assert(wet_layout.third[0].y < terrain.size.y * 0.45, "Third in North")
	_assert_entry(wet_layout.third, "north", terrain, 100)
	var third_only := lab.find_melee_trial_layout(12, 8, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, 6, TerrainArmy.INVALID_CELL, 0.0, 0.0, "", "", "", "north")
	assert(not third_only.is_empty(), "An explicit third direction cannot be discarded by the legacy two-team defaults")
	_assert_entry(third_only.third, "north", terrain, 6)
	assert(lab.find_melee_trial_layout(12, 8, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, 0, TerrainArmy.INVALID_CELL, 0.0, 0.0, "", "invalid", "east").is_empty())

	# 3. Test deploy & facing with start_melee_trial
	# Test North vs South facing
	lab.clear_army()
	var res_ns: Dictionary = lab.start_melee_trial({"friendly_count": 100, "enemy_count": 100, "friendly_entry": "north", "enemy_entry": "south"})
	assert(res_ns.ok, "Deploy North vs South must succeed: %s" % res_ns.get("message", ""))
	assert(lab.army.combat_units.size() == 100, "Friendly units count")
	assert(lab.opposing_army.combat_units.size() == 100, "Enemy units count")
	assert(lab.army.facing[0] == Vector2i.DOWN, "Friendly on North must face DOWN toward South")
	assert(lab.opposing_army.facing[0] == Vector2i.UP, "Enemy on South must face UP toward North")

	# Test East vs West facing
	lab.clear_army()
	var res_ew: Dictionary = lab.start_melee_trial({"friendly_count": 100, "enemy_count": 100, "friendly_entry": "east", "enemy_entry": "west"})
	assert(res_ew.ok, "Deploy East vs West must succeed: %s" % res_ew.get("message", ""))
	assert(lab.army.facing[0] == Vector2i.LEFT, "Friendly on East must face LEFT toward West")
	assert(lab.opposing_army.facing[0] == Vector2i.RIGHT, "Enemy on West must face RIGHT toward East")

	# 4. Test UI integration in site_controller
	lab.clear_army()
	assert(controller.trial_friendly_entry != null, "trial_friendly_entry OptionButton must exist")
	assert(controller.trial_enemy_entry != null, "trial_enemy_entry OptionButton must exist")
	assert(controller.trial_third_entry != null, "trial_third_entry OptionButton must exist")

	# Friendly West (index 2), Enemy East (index 0), Third North (index 3)
	controller.trial_friendly_entry.select(2) # 西
	controller.trial_enemy_entry.select(0)    # 東
	controller.trial_third_entry.select(3)    # 北
	controller._update_combat_window()

	assert("從【西】方空位自動部署" in controller.trial_friendly_spawn_label.text, "Friendly label must show West")
	assert("從【東】方空位自動部署" in controller.trial_enemy_spawn_label.text, "Enemy label must show East")
	assert("從【北】方空位自動部署" in controller.trial_third_spawn_label.text, "Third label must show North")

	var setup: Dictionary = controller._trial_setup()
	assert(setup.get("friendly_entry") in ["west", "西"], "Setup friendly_entry must be west")
	assert(setup.get("enemy_entry") in ["east", "東"], "Setup enemy_entry must be east")
	assert(setup.get("third_entry") == "north", "The actual UI setup must retain third north")

	# Test deploying via controller UI setup
	var deploy_res: Dictionary = lab.start_melee_trial(setup)
	assert(deploy_res.ok, "Deploy via controller._trial_setup() must succeed: %s" % deploy_res.get("message", ""))
	assert(deploy_res.friendly_spawn.x < terrain.size.x * 0.45, "Friendly spawn must be on West edge, not top right corner")
	assert(deploy_res.enemy_spawn.x > terrain.size.x * 0.55, "Enemy spawn must be on East edge, not top right corner")

	# Both real UI handlers must honour the same entry setting for a full third team.
	lab.clear_army()
	for count: SpinBox in [controller.trial_friendly_count, controller.trial_enemy_count, controller.trial_third_count]:
		count.value = 100
	controller.trial_third_enabled.button_pressed = true
	controller._deploy_melee_trial()
	_assert_entry(lab.third_army.cells, "north", terrain, 100)
	lab.clear_army()
	controller.trial_third_enabled.button_pressed = false
	controller._deploy_melee_trial()
	assert(lab.army.combat_units.size() == 100 and lab.opposing_army.combat_units.size() == 100)
	var before: Array[Dictionary] = [lab.army.capture_combat_state(), lab.opposing_army.capture_combat_state()]
	controller._add_third_melee_trial()
	_assert_entry(lab.third_army.cells, "north", terrain, 100)
	_assert_existing_teams(lab, before)
	print("NORTH_THIRD_UI_100_PASS entry=", lab.third_army.cells[0])

	# Mixed-support deployment uses the same entry source while retaining camp/safety exclusions.
	for support_role: String in ["work", "logistics"]:
		lab.clear_army()
		var support_setup := {"friendly_count": 12, "enemy_count": 12, "third_count": 12,
			"friendly_entry": "west", "enemy_entry": "east", "third_entry": "north",
			"friendly_role": support_role, "friendly_attack": false, "third_enabled": true}
		var support_result := lab.start_melee_trial(support_setup)
		assert(support_result.ok, "Mixed support must honour explicit sides: %s" % support_result)
		_assert_entry(lab.army.cells, "west", terrain, 12)
		_assert_entry(lab.third_army.cells, "north", terrain, 12)
		lab.clear_army()
		support_setup.third_enabled = false
		assert(lab.start_melee_trial(support_setup).ok)
		before = [lab.army.capture_combat_state(), lab.opposing_army.capture_combat_state()]
		assert(lab.add_melee_trial_team(support_setup).ok, "Appending beside support teams must retain north")
		_assert_entry(lab.third_army.cells, "north", terrain, 12)
		_assert_existing_teams(lab, before)

	# A blocked north edge may not fall back to a perfectly usable western interior.
	lab.clear_army()
	var fixture := Helper.build_flat_map(40, 40)
	for x in range(fixture.size.x):
		fixture.static_blocked[fixture.index(Vector2i(x, 0))] = 1
	lab.terrain = fixture
	assert(lab._find_directional_team_formation("north", 12, {}).is_empty(), "Blocked north must never become west")
	assert(not lab._find_directional_team_formation("west", 12, {}).is_empty(), "The blocked-side fixture must have genuine western space")
	assert(lab.find_melee_trial_layout(12, 12, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, 12,
		TerrainArmy.INVALID_CELL, 0.0, 0.0, "", "west", "east", "north").is_empty(), "Together deployment cannot bypass a blocked requested side")
	var north_support := lab._trial_side_settings({"third_count": 12, "third_role": "logistics", "third_entry": "north"}, "third")
	assert(north_support.ok and lab._independent_trial_formations([north_support.side]).is_empty(), "Support placement cannot fall back to camp when its requested edge is blocked")
	assert(lab.find_melee_trial_layout(12, 8).size() == 2, "Unspecified legacy adjacent-front placement remains usable")
	lab.terrain = terrain
	var invalid := lab.start_melee_trial({"third_enabled": true, "third_entry": "upwards"})
	assert(not invalid.ok and invalid.code == "INVALID", "Invalid explicit direction must fail before deployment")
	assert(not lab.army.has_army() and not lab.opposing_army.has_army() and not lab.third_army.has_army())
	print("SITE BATTLE SPAWN DIRECTION PASS: four actual edges, north third 100 together/append UI, preserved teams, mixed support, blocked-side rejection and legacy placement")
	lab.queue_free()
	await process_frame
	quit(0)
