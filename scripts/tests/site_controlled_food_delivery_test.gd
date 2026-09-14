extends "res://scripts/tests/site_workflow_test.gd"

const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")

func _near(actual: float, expected: float) -> void:
	assert(absf(actual - expected) < 0.000001, "%.10f != %.10f" % [actual, expected])

func _food_total(entry: Dictionary) -> float:
	var total := Sustain.rations(entry.sustain, entry.inventory)
	for cohort: Dictionary in entry.sustain.cohorts:
		total += cohort.ids.size() * float(cohort.coverage) * (float(cohort.meal_until) - float(entry.sustain.at)) / 86400.0
	return total

func _run() -> void:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	var controller: SiteController = lab.site_controller
	controller._auto_save_blocked = true
	var data := _fixture()
	lab.bind_terrain(data)
	lab.character.place(Vector2i(18, 20), true)
	lab.npc.place(Vector2i(21, 22), true)
	lab.npc.issue_command(TerrainTestNPC.Command.STOP)
	lab.npc.faction_id = lab.character.faction_id
	var team: TerrainArmy = lab.combat_armies[0]
	team.roster_size = 4
	var cells: Array[Vector2i] = [Vector2i(22, 22), Vector2i(23, 22), Vector2i(22, 23), Vector2i(23, 23)]
	assert(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false))
	team.set_process(false)
	team.faction_id = lab.npc.faction_id
	team.settle_combat_command()
	controller.initialize_team_items(team)
	data.site.manual.cargo = {"grain": 13}
	data.site.worker.cargo = {"fish": 8}
	var depot: Dictionary = data.site.inventory.duplicate(true)
	assert(controller._control_family_person(null, lab.npc.person_id).ok)
	assert(controller.begin_team_food(team, 4, team.combat_identity(0)).ok)
	var entry := controller._supply_entry(team)
	assert(int(entry.delivery.player_id) == lab.npc.person_id)
	assert(is_same(entry.delivery.source_cargo, data.site.worker.cargo))
	var original_player_fatigue := lab.character.fatigue
	lab.npc.fatigue = 40.0
	lab.npc.fatigue_rest = 10.0
	lab._advance_fatigue(0.5)
	_near(lab.npc.fatigue, 40.0 + 0.5 * Fatigue.WORK_RATE)
	assert(lab.npc.fatigue_rest == 0.0 and lab.character.fatigue == original_player_fatigue)
	assert(data.site.worker.cargo.fish == 8 and data.site.manual.cargo.grain == 13)
	data.site.paused = true
	var left_before := float(entry.delivery.left)
	var paused_fatigue := lab.npc.fatigue
	lab._advance_combat(10.0)
	controller.settle_supply_deliveries()
	assert(float(entry.delivery.left) == left_before and data.site.worker.cargo.fish == 8 and lab.npc.fatigue == paused_fatigue)
	data.site.paused = false
	controller.advance_team_sustain(team, 5.0)
	assert(entry.delivery.pending and data.site.worker.cargo.fish == 8)
	var total_before := _food_total(entry)
	controller.settle_supply_deliveries()
	assert(entry.delivery.is_empty() and data.site.worker.cargo.fish == 4 and data.site.manual.cargo.grain == 13)
	_near(_food_total(entry), total_before + 4.0)
	var after_commit := _food_total(entry)
	controller.settle_supply_deliveries()
	_near(_food_total(entry), after_commit)
	# Same amounts in a replacement container are still not the original source.
	assert(controller.begin_team_food(team, 1, team.combat_identity(0)).ok)
	data.site.worker.cargo = data.site.worker.cargo.duplicate(true)
	controller.advance_team_sustain(team, 5.0)
	assert(entry.delivery.is_empty() and data.site.worker.cargo.fish == 4)
	assert(controller.begin_team_food(team, 1, team.combat_identity(0)).ok)
	data.site.controlled_person_id = lab.character.person_id
	controller.advance_team_sustain(team, 5.0)
	assert(entry.delivery.is_empty() and data.site.worker.cargo.fish == 4 and data.site.manual.cargo.grain == 13)
	# A real ordinary member uses its own cargo and shared handled-seconds path.
	var sender: Dictionary = team.combat_units[1]
	sender.cargo = {"grain": 6}
	sender.fatigue = 41.0
	sender.fatigue_rest = 10.0
	assert(controller._control_family_person(null, int(sender.person_id)).ok)
	assert(not controller.begin_team_food(team, 1, int(sender.person_id)).ok)
	assert(controller.begin_team_food(team, 2, team.combat_identity(0)).ok)
	entry.training_order = true
	entry.training_requester = team.combat_identity(team.current_commander)
	var receiver: Dictionary = team.combat_units[0]
	var receiver_fatigue := float(receiver.fatigue)
	lab._advance_fatigue(0.5)
	_near(float(sender.fatigue), 41.0 + 0.5 * Fatigue.WORK_RATE)
	_near(float(receiver.fatigue), receiver_fatigue + 0.5 * Fatigue.WORK_RATE)
	assert(sender.fatigue_rest == 0.0 and receiver.fatigue_rest == 0.0, "Neither original row also rests/trains during delivery")
	controller.advance_team_sustain(team, 5.0)
	assert(entry.delivery.pending and sender.cargo.grain == 6)
	total_before = _food_total(entry)
	controller.settle_supply_deliveries()
	assert(entry.delivery.is_empty() and sender.cargo.grain == 4)
	_near(_food_total(entry), total_before + 2.0)
	assert(data.site.worker.cargo.fish == 4 and data.site.manual.cargo.grain == 13 and data.site.inventory == depot)
	# Actual sender hit at the completion boundary cancels without spending.
	entry.training_order = false
	assert(controller.begin_team_food(team, 1, team.combat_identity(0)).ok)
	controller.advance_team_sustain(team, 5.0)
	assert(entry.delivery.pending)
	team.apply_unit_contact(1, {"result": {"hp": 1.0, "stun": 0.0, "guard_break": false}, "shield": false})
	controller.settle_supply_deliveries()
	assert(entry.delivery.is_empty() and sender.cargo.grain == 4)
	lab.queue_free()
	await process_frame
	print("SITE CONTROLLED FOOD DELIVERY PASS: original NPC cargo and Army row cargo, original sender identity/hit/holder guards, no self transfer, same-valued source replacement cancels, pause/post-contact commit, sender/receiver fatigue handled once, actual food plus meal-credit conservation; family selection and full UI separately verified")
	quit(0)
