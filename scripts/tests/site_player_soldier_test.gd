extends SceneTree

const Store = preload("res://scripts/terrain_lab/site_store.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "player-soldier-fixture")
	data.resource_base.clear()
	data.resources_at.clear()
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	lab.bind_terrain(data)
	lab.character.place(Vector2i(50, 50), true)
	lab.npc.place(Vector2i(52, 50), true)
	assert(lab.start_melee_trial().ok)
	for team: TerrainArmy in lab.combat_armies:
		team.set_process(false)
		team.combat_attacking = false
		team.enemy_query = Callable()
	var player := lab.character
	var army := lab.army
	var enemy := lab.opposing_army
	assert(lab.join_player_army().ok)
	army.training = 60.0
	player.training = 0.0
	assert(player.place(enemy.cells[10] + Vector2i.UP, true))
	var original_position := player.position
	assert(lab.select_army_target(enemy.cells[10]))
	assert(player.position == original_position)
	assert(lab.attack_selected_soldier())
	assert(player.attack_target_id == enemy.combat_identity(10))
	assert(player._attack_target(false).owner == enemy and player._attack_target(false).cell == enemy.cells[10])
	assert(is_equal_approx(player._training_reduction, SiteCombatRules.diminishing(60.0, 0.15)), "Player reads the same team's training, not personal XP")
	var target_before := player._attack_target(true)
	enemy.combat_units[10].pose = "guard"
	var target_after := player._attack_target(true)
	assert(target_after.bodies == enemy.combat_shapes(10, "body") and target_before.bodies != target_after.bodies)
	var attack_save := JSON.parse_string(JSON.stringify(player.capture_state())) as Dictionary
	assert(TerrainTestCharacter.valid_state(attack_save, data))
	player.restore_state(attack_save)
	assert(player._attack_target(false).owner == enemy and player.attack_target_id == enemy.combat_identity(10))
	player.reset_combat()
	assert(player.place(army.cells[10] + Vector2i.UP, true))
	var down := {"result": {"hp": 7.5, "stun": 110.0, "guard_break": false}, "shield": false}
	army.apply_unit_contact(10, down)
	assert(lab.select_army_target(army.cells[10]) and lab.rescue_selected_soldier())
	assert(not army.start_unit_rescue(0, 10), "An ordinary helper cannot duplicate the player's rescue")
	player.advance_combat(1.0)
	army.settle_combat_command()
	lab.site_controller._capture_positions()
	var saved := JSON.parse_string(JSON.stringify(data.site)) as Dictionary
	var armies_result := Store._validate_armies(data, saved)
	assert(armies_result.ok, str(armies_result))
	var actors_result := Store._validate_actors(data, saved)
	assert(actors_result.ok, str(actors_result))
	var corrupt := saved.duplicate(true)
	corrupt.actors.player.attack_target = 999999999
	assert(not Store._validate_actors(data, corrupt).ok)
	player.restore_state(saved.actors.player)
	army.restore_combat_state(saved.armies[0], data, player, lab.npc)
	player.restore_links(saved.actors.player, {player.person_id: player, lab.npc.person_id: lab.npc})
	assert(player._rescue_army == army and army._external_rescuers[10] == player)
	player.advance_combat(2.9)
	assert(army.combat_units[10].ko > 0.0)
	player.advance_combat(0.1)
	assert(army.combat_units[10].ko == 0.0, "KO=%s rescue_left=%.18f" % [army.combat_units[10].ko, player._rescue_left])
	assert(army.combat_units[10].hp == 92.5 and not army.combat_can_act(10))
	army.prepare_combat(2.3)
	army.apply_unit_contact(10, down)
	assert(player.start_rescue_unit(army, 10))
	army.apply_unit_contact(10, {"result": {"hp": 0.0, "stun": 1.0, "guard_break": false}, "shield": false})
	assert(player._rescue_left == 0.0 and army._external_rescuers.is_empty())
	assert(player.start_rescue_unit(army, 10))
	paused = true
	player.advance_combat(5.0)
	assert(player._rescue_left == 4.0)
	paused = false
	assert(player.step(Vector2i.LEFT))
	assert(player._rescue_left == 0.0 and army._external_rescuers.is_empty())
	assert(not player.start_rescue_unit(enemy, 10))
	lab.clear_army()
	lab.queue_free()
	await process_frame
	print("SITE PLAYER SOLDIER PASS: direct identity/pose targeting, shared training, saved help/attack target, unique rescuer, hit/move/pause interruption, no heal or surrogate")
	quit(0)
