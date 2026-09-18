extends "res://scripts/tests/site_work_team_clock_test.gd"
## One original Lab, two explicitly initialized fixtures. Only Lab._process
## advances time/actions; inherited internal 15 s bound, canonical headless 20 s.
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")

func _run() -> void:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	for owner: Node in [lab, lab.character, lab.npc, lab.army, lab.opposing_army]:
		owner.set_process(false)
	lab.npc_retaliates = false
	var controller: SiteController = lab.site_controller
	controller._auto_save_blocked = true
	_row_delivery_duty(lab)
	_npc_delivery_duty(lab)
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE DELIVERY DUTY PASS: original Lab common clock; ordinary row delivery excludes automatic adjacent-KO rescue, cancel restores rescue; original joined NPC delivery excludes due automatic resource assignment, commit restores choose_task; original body/cargo references and food/meal conservation, no substitute people; not GPU or long-run proof")
	quit(0)

func _row_delivery_duty(lab: TerrainLab) -> void:
	var controller: SiteController = lab.site_controller
	var data := _fixture()
	lab.bind_terrain(data)
	controller.release_worker()
	assert(lab.character.place(Vector2i(17, 17), true))
	assert(lab.npc.place(Vector2i(15, 15), true))
	lab.npc.faction_id = lab.character.faction_id
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	var cells: Array[Vector2i] = [Vector2i(21, 22), Vector2i(22, 22), Vector2i(22, 23)]
	assert(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false))
	team.faction_id = lab.character.faction_id
	team.settle_combat_command()
	data.site.army_next_team = team.team_id + 1
	var sender: Dictionary = team.combat_units[0]
	var receiver: Dictionary = team.combat_units[1]
	var patient: Dictionary = team.combat_units[2]
	var cargo: Dictionary = sender.cargo
	cargo["grain"] = 4 # Explicit original sender stock, not an output reward.
	assert(controller._control_family_person(null, int(sender.person_id)).ok)
	team.apply_unit_contact(2, {"result": {"hp": 0.0, "stun": 110.0, "guard_break": false}, "shield": false})
	team.settle_combat_command()
	assert(float(patient.hp) == 100.0 and float(patient.ko) > 0.0)
	assert(team._rescue_reachable(1, 2) and team.enemy_query.is_valid())
	assert(lab._nearest_unit_enemy(team, 1).is_empty())
	receiver.think = 0.0 # Review is due now; do not bypass the actual AI branch.
	assert(controller.begin_team_food(team, 1.0, int(receiver.person_id)).ok)
	var entry := controller._supply_entry(team)
	var left_before := float(entry.delivery.left)
	lab._process(0.1)
	assert(not entry.delivery.is_empty() and float(entry.delivery.left) < left_before)
	assert(str(receiver.pose) == "idle" and not team._unit_rescues.has(1), "Due automatic rescue must not take the original delivery worker")
	assert(float(receiver.think) > 0.0, "The original AI actually reviewed this ordinary row")
	assert(cargo == {"grain": 4} and is_same(sender.cargo, cargo))
	_near(PersonFatigue.read(receiver), 0.1 * PersonFatigue.effort_rate(receiver), "delivery effort once in the actual shared team pool while original AI runs")
	_near(float(entry.sustain.at), Runtime.now(data) * 60.0, "delivery uses original Site clock")
	assert(controller.cancel_team_food().ok and entry.delivery.is_empty())
	lab._process(0.6) # Existing 0.5 s AI review, shorter than the 4 s rescue.
	assert(str(receiver.pose) == "rescue" and team._unit_rescues.has(1))
	assert(int(team._unit_rescues[1].patient) == 2, "Cancel releases duty to the original eligible rescue")
	assert(is_same(team.combat_units[0], sender) and is_same(team.combat_units[1], receiver) and is_same(team.combat_units[2], patient))
	assert(cargo == {"grain": 4} and float(patient.hp) == 100.0 and float(receiver.hp) == 100.0)
	assert(data.site.manual.cargo.is_empty() and data.site.worker.cargo.is_empty())

func _npc_delivery_duty(lab: TerrainLab) -> void:
	var controller: SiteController = lab.site_controller
	var fixture := _work_fixture() # Existing generated, reachable nonfood resources.
	var data: TerrainData = fixture.data
	lab.bind_terrain(data)
	controller.release_worker()
	lab.npc.faction_id = lab.character.faction_id
	var npc_cell: Vector2i = fixture.cells[1]
	assert(lab.npc.place(npc_cell, true))
	var captain_cell := TerrainArmy.INVALID_CELL
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var candidate := npc_cell + direction
		if candidate != lab.character.terrain_cell and data.can_step(npc_cell, candidate):
			captain_cell = candidate
			break
	assert(captain_cell != TerrainArmy.INVALID_CELL, "Real resource worker needs a legal adjacent original sender")
	var team: TerrainArmy = lab.army
	team.roster_size = 1
	var cells: Array[Vector2i] = [captain_cell]
	assert(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false))
	team.faction_id = lab.character.faction_id
	team.settle_combat_command()
	data.site.army_next_team = team.team_id + 1
	assert(controller._control_family_person(null, lab.npc.person_id).ok)
	assert(lab.join_player_army().ok and team.player_member == lab.npc)
	var captain: Dictionary = team.combat_units[0]
	assert(controller._control_family_person(null, int(captain.person_id)).ok)
	var sender_cargo: Dictionary = captain.cargo
	var worker: Dictionary = data.site.worker
	var npc_cargo: Dictionary = worker.cargo
	var original_npc: TerrainTestNPC = lab.npc
	sender_cargo["grain"] = 4 # Second independent fixture's initial owned food.
	assert(npc_cargo.is_empty())
	var depot_before: Dictionary = data.site.inventory.duplicate(true)
	var choice := Runtime.choose_task(data, npc_cell, controller._worker_blocked, null, null, controller.work_team.reserved_targets())
	assert(choice.ok and not Env.resource(data, str(choice.target)).is_empty(), "Actual original choose_task can find a real source now")
	assert(int(choice.cell) == data.index(npc_cell), "Recovery uses the original worker already beside the resource")
	controller.enable_worker() # Also makes the original selection review due.
	assert(bool(data.site.worker_enabled) and controller._work_elapsed >= 0.5)
	assert(controller.begin_team_food(team, 2.0, lab.npc.person_id).ok)
	var entry := controller._supply_entry(team)
	var before_clock := Runtime.now(data) * 60.0
	var before_fatigue := PersonFatigue.read(lab.npc)
	assert(lab.exchange_enabled and lab._action_time_remainder == 0.0)
	for step in range(3):
		lab._process(TerrainLab.EXCHANGE_ACTION_STEP / 4.0)
		assert(not entry.delivery.is_empty() and worker.target == "", "Due automatic choose_task must not steal the joined Actor delivery")
		assert(lab.npc.command == TerrainTestNPC.Command.STOP and not lab.npc.is_moving())
	_near(Runtime.now(data) * 60.0 - before_clock, 0.0, "three quarter-inputs do not advance the original 30Hz owner early")
	_near(PersonFatigue.read(lab.npc), before_fatigue, "no shadow Actor fatigue update before an actual common step")
	lab._process(TerrainLab.EXCHANGE_ACTION_STEP / 4.0)
	assert(not entry.delivery.is_empty() and worker.target == "")
	_near(Runtime.now(data) * 60.0 - before_clock, 2.0, "four quarter-inputs make one original peaceful common step")
	_near(PersonFatigue.read(lab.npc) - before_fatigue, 2.0 * PersonFatigue.effort_rate(lab.npc), "joined original Actor charges its real team fatigue owner once")
	for step in range(8):
		lab._process(TerrainLab.EXCHANGE_ACTION_STEP)
		assert(worker.target == "", "Selection stays excluded until the post-contact commit")
		if entry.delivery.is_empty():
			break
	assert(entry.delivery.is_empty() and sender_cargo == {"grain": 2})
	var credited := 0.0
	for cohort: Dictionary in entry.sustain.cohorts:
		credited += cohort.ids.size() * float(cohort.coverage) * (float(cohort.meal_until) - float(entry.sustain.at)) / 86400.0
	_near(Sustain.rations(entry.sustain, entry.inventory) + credited, 2.0, "two actual donated rations become stock plus original meal credit exactly once")
	assert(not controller._person_has_duty(lab.npc.person_id))
	lab._process(TerrainLab.EXCHANGE_ACTION_STEP)
	assert(str(worker.target) == str(choice.target) and str(worker.mode) == "work" and float(worker.progress) > 0.0, "Completion releases the same Actor to original due choose_task and work")
	assert(lab.npc == original_npc and team.player_member == original_npc and team.combat_units.size() == 1)
	assert(is_same(controller.person_actions._person(lab.npc.person_id).cargo, npc_cargo) and is_same(captain.cargo, sender_cargo))
	assert(sender_cargo == {"grain": 2} and npc_cargo.is_empty() and data.site.manual.cargo.is_empty() and data.site.inventory == depot_before)
	assert(float(captain.hp) == 100.0 and lab.npc.hp == 100.0)
	_near(float(entry.sustain.at), Runtime.now(data) * 60.0, "resumed worker and feeding keep the original common clock")
	controller.release_worker()
