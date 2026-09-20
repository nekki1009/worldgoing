extends SceneTree

const Store = preload("res://scripts/terrain_lab/site_store.gd")

var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 30000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("SITE BATTLE SPAWN DIRECTION test timed out")
		quit(1)
	return false

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

	# 1. Test find_melee_trial_layout with legacy default (unspecified directions -> adjacent front)
	var default_layout := lab.find_melee_trial_layout(12, 8)
	assert(not default_layout.is_empty(), "Default layout must succeed")

	# 2. Test independent directional entry sectors (Friendly vs Enemy)
	# Case A: Friendly West, Enemy East (Horizontal standard)
	var we_layout := lab.find_melee_trial_layout(100, 100, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, 0, TerrainArmy.INVALID_CELL, 0.0, 0.0, "", "west", "east")
	assert(not we_layout.is_empty(), "Layout for West vs East must succeed")
	assert(we_layout.friendly[0].x < terrain.size.x * 0.45, "Friendly must be in West sector (x < 45%%)")
	assert(we_layout.enemy[0].x > terrain.size.x * 0.55, "Enemy must be in East sector (x > 55%%)")

	# Case B: Friendly East, Enemy West (Horizontal inverted)
	var ew_layout := lab.find_melee_trial_layout(100, 100, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, 0, TerrainArmy.INVALID_CELL, 0.0, 0.0, "", "east", "west")
	assert(not ew_layout.is_empty(), "Layout for East vs West must succeed")
	assert(ew_layout.friendly[0].x > terrain.size.x * 0.55, "Friendly must be in East sector (x > 55%%)")
	assert(ew_layout.enemy[0].x < terrain.size.x * 0.45, "Enemy must be in West sector (x < 45%%)")

	# Case C: Friendly North, Enemy South (Vertical standard)
	var ns_layout := lab.find_melee_trial_layout(100, 100, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, 0, TerrainArmy.INVALID_CELL, 0.0, 0.0, "", "north", "south")
	assert(not ns_layout.is_empty(), "Layout for North vs South must succeed")
	assert(ns_layout.friendly[0].y < terrain.size.y * 0.45, "Friendly must be in North sector (y < 45%%)")
	assert(ns_layout.enemy[0].y > terrain.size.y * 0.55, "Enemy must be in South sector (y > 55%%)")

	# Case D: Friendly South, Enemy North (Vertical inverted)
	var sn_layout := lab.find_melee_trial_layout(100, 100, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, 0, TerrainArmy.INVALID_CELL, 0.0, 0.0, "", "south", "north")
	assert(not sn_layout.is_empty(), "Layout for South vs North must succeed")
	assert(sn_layout.friendly[0].y > terrain.size.y * 0.55, "Friendly must be in South sector (y > 55%%)")
	assert(sn_layout.enemy[0].y < terrain.size.y * 0.45, "Enemy must be in North sector (y < 45%%)")

	# Case E: 3 Teams with independent directions (Friendly West, Enemy East, Third North)
	var wet_layout := lab.find_melee_trial_layout(100, 100, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, 50, TerrainArmy.INVALID_CELL, 0.0, 0.0, "", "west", "east", "north")
	assert(not wet_layout.is_empty(), "3-team layout must succeed")
	assert(wet_layout.friendly[0].x < terrain.size.x * 0.45, "Friendly in West")
	assert(wet_layout.enemy[0].x > terrain.size.x * 0.55, "Enemy in East")
	assert(wet_layout.third[0].y < terrain.size.y * 0.45, "Third in North")

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

	# Test deploying via controller UI setup
	var deploy_res: Dictionary = lab.start_melee_trial(setup)
	assert(deploy_res.ok, "Deploy via controller._trial_setup() must succeed: %s" % deploy_res.get("message", ""))
	assert(deploy_res.friendly_spawn.x < terrain.size.x * 0.45, "Friendly spawn must be on West edge, not top right corner")
	assert(deploy_res.enemy_spawn.x > terrain.size.x * 0.55, "Enemy spawn must be on East edge, not top right corner")

	print("SITE BATTLE SPAWN DIRECTION PASS: true directional edge deployment, empty slot auto-deploy, facings, UI integration verified")
	lab.queue_free()
	await process_frame
	quit(0)
