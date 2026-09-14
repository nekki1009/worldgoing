extends "res://scripts/tests/site_workflow_test.gd"

const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")

func near(actual: float, expected: float, label: String = "") -> void:
	assert(absf(actual - expected) < 0.00001, "%s: %.10f != %.10f" % [label, actual, expected])

func _run() -> void:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var data := _fixture()
	lab.bind_terrain(data)
	lab.npc.faction_id = lab.character.faction_id
	lab.npc.place(Vector2i(18, 20), true)
	lab.character.place(Vector2i(21, 22), true)
	var team := lab.army
	team.roster_size = 4
	var cells: Array[Vector2i] = [Vector2i(22, 22), Vector2i(23, 22), Vector2i(22, 23), Vector2i(23, 23)]
	assert(team.deploy_at(data, lab.character, lab.npc, cells))
	assert(team.enable_combat(false))
	team.set_process(false)
	team.faction_id = lab.character.faction_id
	team.settle_combat_command()
	var controller: SiteController = lab.site_controller
	assert(controller._supply_entry(team).is_empty(), "Not enabled by bind/deploy/query")
	data.site.manual.cargo = {"grain": 8}
	lab.character.ammo_inventory = data.site.manual.cargo
	var depot_before: Dictionary = data.site.inventory.duplicate()
	assert(not controller.begin_team_food(team, 1, -1).ok)
	assert(controller._supply_entry(team).is_empty())
	assert(controller.begin_team_food(team, 4, team.combat_identity(0)).ok)
	var entry: Dictionary = controller._supply_entry(team)
	assert(not controller.supply_save_guard().ok)
	controller.advance_team_sustain(team, 2.0)
	assert(data.site.manual.cargo.grain == 8 and entry.inventory.is_empty())
	var before_pause := entry.duplicate(true)
	data.site.paused = true
	controller.advance_team_sustain(team, 20.0)
	assert(entry == before_pause)
	data.site.paused = false
	controller.advance_team_sustain(team, 1.0)
	assert(data.site.manual.cargo.grain == 8 and entry.delivery.pending, "Time completion cannot precede contact settlement")
	controller.settle_supply_deliveries()
	assert(entry.delivery.is_empty() and data.site.manual.cargo.grain == 4)
	near(Sustain.rations(entry.sustain, entry.inventory), 4.0 - 4.0 * (21600.0 - 3.0) / 86400.0, "only post-contact remaining meal credit is eaten")
	assert(data.site.inventory == depot_before, "Food donation never appropriates depot stock")
	assert(controller.supply_save_guard().ok)
	var conserved := Sustain.rations(entry.sustain, entry.inventory)
	controller.advance_team_sustain(team, 0.01)
	controller.settle_supply_deliveries()
	near(Sustain.rations(entry.sustain, entry.inventory), conserved, "completion cannot duplicate food")
	# Effective hit in the SAME contact step as the deadline wins over commit.
	assert(controller.begin_team_food(team, 1, team.combat_identity(0)).ok)
	controller.advance_team_sustain(team, 2.2)
	assert(entry.delivery.pending and data.site.manual.cargo.grain == 4)
	team.apply_unit_contact(0, {"result": {"hp": 1.0, "stun": 0.0, "guard_break": false}, "shield": false})
	controller.settle_supply_deliveries()
	assert(entry.delivery.is_empty() and data.site.manual.cargo.grain == 4)
	data.site.combat_left = 0.0
	assert(controller.begin_team_food(team, 1, team.combat_identity(0)).ok)
	lab.character.apply_contact({"result": {"hp": 1.0, "stun": 0.0, "guard_break": false}, "shield": false})
	controller.advance_team_sustain(team, 5.0)
	assert(entry.delivery.is_empty() and data.site.manual.cargo.grain == 4, "real hit interrupts before deduct")
	data.site.combat_left = 0.0
	assert(controller.begin_team_food(team, 1, team.combat_identity(0)).ok)
	assert(controller.cancel_team_food().ok)
	assert(data.site.manual.cargo.grain == 4)
	# Same original owner, same physical capacity guards and source changes.
	assert(controller.begin_team_food(team, 1, team.combat_identity(0)).ok)
	data.site.manual.cargo.grain = 3
	controller.advance_team_sustain(team, 5.0)
	assert(entry.delivery.is_empty() and data.site.manual.cargo.grain == 3)
	for index: int in [1, 2, 3]:
		team.combat_units[index].ko = 20.0
	assert(not controller.begin_team_food(team, 1, team.combat_identity(0)).ok)
	for index: int in [1, 2, 3]:
		team.combat_units[index].ko = 0.0
	assert(not controller.order_team_training(team, TerrainArmy.PLAYER_MEMBER, true).ok)
	assert(controller.order_team_training(team, team.current_commander, true).ok)
	# Legacy gameplay reads its actual fixed rendered/query weapon. Once a real
	# holder is initialized, an empty equipped slot is authoritative, not refilled.
	assert(controller._armed(team.combat_units[1]))
	# This fixture explicitly registers items; the controller never mints gear.
	data.site["item_definitions"] = {"fixture-sword": {"slot": "weapon", "asset": "longsword_01", "tint": [1.0, 1.0, 1.0, 1.0]}}
	data.site["item_records"] = {}
	for index: int in team.combat_units.size():
		var id := team.combat_identity(index)
		var item := "sustain-fixture-%d" % id
		var owner := "person:%d" % id
		data.site.item_records[item] = {"definition": "fixture-sword", "original_owner": id, "holder": owner}
		team.combat_units[index].item_state = {"holder": owner, "version": 1, "item_ids": [item], "equipped": {"weapon": item}}
	team.combat_units[1].item_state.equipped.clear()
	team.combat_units[2].captive = true
	team.combat_units[3].ko = 20.0
	team.combat_units[0].fatigue = 79.9
	var body: Dictionary = team.combat_units[0]
	var before_training := team.training
	var result: Dictionary = controller.advance_team_sustain(team, 3600.0)
	assert(is_same(body, team.combat_units[0]), "Training mutates original army dictionary")
	assert(result.handled_ids == [team.combat_identity(0)])
	assert(team.training > before_training and body.work_resting and body.fatigue > 50.0 and body.fatigue < 80.0)
	assert(team.combat_units[1].fatigue == 0.0, "No weapon is not an eligible armed trainee")
	assert(controller.order_team_training(team, team.current_commander, false).ok)
	# Nonfatal hunger uses the original life entrypoint without combat speed/hit
	# spam. Fatal hunger reaches original dead pose and clears original attack.
	entry.inventory.clear()
	entry.sustain.open_rations = 0.0
	for cohort: Dictionary in entry.sustain.cohorts:
		cohort.hunger = 49.0
		cohort.coverage = 0.0
		cohort.meal_until = (floorf(float(entry.sustain.at) / 21600.0) + 1.0) * 21600.0
	body.hp = 0.1
	body.attack = true
	var prior_hit := int(body.get("hit_revision", 0))
	data.site.combat_left = 0.0
	controller.advance_team_sustain(team, 720.0)
	assert(body.hp == 0.0 and body.pose == "down" and not body.attack)
	assert(int(body.get("hit_revision", 0)) == prior_hit)
	assert(data.site.combat_left == 0.0, "Starvation does not manufacture combat")
	# Actual original join/leave callbacks move only eating history. Rejoining
	# cannot wash hunger or duplicate the prepaid current-period half-meal.
	# This isolated fixture advanced the supply controller directly, not the
	# Site owner. Align its already elapsed clock before testing a real command;
	# the separate actual-Lab clock test must not need this fixture repair.
	data.site.minute = floori(float(entry.sustain.at) / 60.0)
	data.site.phase = fposmod(float(entry.sustain.at), 60.0) / 60.0
	assert(team.join_player(lab.character).ok)
	var player_cohort: Dictionary = {}
	for cohort: Dictionary in entry.sustain.cohorts:
		if lab.character.person_id in cohort.ids:
			player_cohort = cohort
	assert(not player_cohort.is_empty(), "Original join path invokes supply ownership hook")
	player_cohort.hunger = 7.5
	player_cohort.coverage = 0.5
	player_cohort.meal_until = (floorf(float(entry.sustain.at) / 21600.0) + 1.0) * 21600.0
	var private_before: Dictionary = data.site.manual.cargo.duplicate()
	assert(team.leave_player().ok)
	var personal: Dictionary = data.site.person_supply[str(lab.character.person_id)]
	near(float(personal.cohorts[0].hunger), 7.5)
	near(float(personal.cohorts[0].coverage), 0.5)
	assert(data.site.manual.cargo == private_before)
	assert(team.join_player(lab.character).ok)
	assert(personal.cohorts.is_empty())
	player_cohort = {}
	for cohort: Dictionary in entry.sustain.cohorts:
		if lab.character.person_id in cohort.ids:
			player_cohort = cohort
	near(float(player_cohort.hunger), 7.5)
	near(float(player_cohort.coverage), 0.5)
	assert(data.site.manual.cargo == private_before)
	# A stopped, unconscious original joined Actor is not a moving army. The
	# original body remains unqualified to receive food or perform an action.
	lab.character.apply_contact({"result": {"hp": 0.0, "stun": 110.0, "guard_break": false}, "shield": false, "environmental": true})
	assert(lab.character.knockout_left > 0.0 and not controller._supply_actor_ready(lab.character))
	assert(controller._team_stopped(team), "A stationary KO member cannot lock the whole living team out of stopped commands")
	entry.inventory.grain = 7
	entry.sustain.open_rations = 0.25
	controller.before_clear_team_supply(team)
	team.clear()
	assert(entry.sustain.cohorts.is_empty() and entry.life_checkpoint.is_empty())
	near(Sustain.rations(entry.sustain, entry.inventory), 7.25, "explicit clear preserves orphan supply stock")
	assert(not entry.training_order and entry.training_requester == -1)
	assert(not personal.cohorts.is_empty(), "Clearing NPC test roster preserves actual player's eating history")
	controller.update_ui()
	assert(lab.find_child("DeliverTeamFood", true, false) != null and lab.find_child("CancelTeamFood", true, false) != null and lab.find_child("TrainPlayerTeam", true, false) != null)
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE TEAM SUSTAIN FLOW PASS: original controller physical atomic food/delivery/cancel/hit/pause, explicit supply/gear, original-row training80/50, environmental death and orphan-stock retention; common-clock/full-save integration separately required")
	quit(0)
