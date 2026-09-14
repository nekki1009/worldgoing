extends "res://scripts/tests/site_workflow_test.gd"
## Original row transfer + original feeding-owner helper, not combat geometry.

const Feeding = preload("res://scripts/terrain_lab/site_captivity_supply.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")

func _history(state: Dictionary, identity: int) -> Dictionary:
	for cohort: Dictionary in state.cohorts:
		if identity in cohort.ids:
			var copy := cohort.duplicate(true)
			copy.erase("ids")
			return copy
	return {}

func _check(helper: Variant) -> void:
	var states: Array = []
	for owner: Dictionary in helper._states().values():
		states.append(owner.state)
	assert(Sustain.validate_owners(states, helper._all_members()), "Each real ID has at most one feeding owner")

func _run() -> void:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	var data := _fixture()
	data.site.minute = 180
	data.site.phase = 0.0
	lab.bind_terrain(data)
	var controller: SiteController = lab.site_controller
	controller._auto_save_blocked = true
	controller.release_worker()
	assert(lab.character.place(Vector2i(16, 30), true))
	assert(lab.npc.place(Vector2i(18, 30), true))
	lab.npc.faction_id = 2
	lab.character.faction_id = 1
	var source: TerrainArmy = lab.army
	var target: TerrainArmy = lab.opposing_army
	for team: TerrainArmy in [source, target]:
		team.roster_size = 6
		team.faction_id = 1
		var cells: Array[Vector2i] = []
		for index: int in 6:
			cells.append(Vector2i(18 + index % 3, 19 + floori(float(index) / 3.0) + (4 if team == target else 0)))
		assert(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false))
		team.set_process(false)
		team.settle_combat_command()
	data.site.army_next_team = 3
	var helper := Feeding.new()
	helper.init(controller)
	# Use the production hook, not direct row mutation. The explicit assignment
	# also isolates this helper test if Controller's one-line forwarding is queued.
	source.roster_transfer_hook = helper.move_roster
	target.roster_transfer_hook = helper.move_roster
	var receiving: Dictionary = controller._enable_team_supply(target)
	receiving.inventory.grain = 9
	receiving.sustain.open_rations = 0.375
	var captive: Dictionary = source.combat_units[1]
	var captive_id := int(captive.person_id)
	var free_id := source.combat_identity(2)
	var captor_id := source.combat_identity(0)
	var guard_id := source.combat_identity(3)
	var original_cargo: Dictionary = captive.cargo
	var original_gear: Dictionary = captive.item_state
	# A valid existing state: source never opted in; its one captured row is
	# already fed by the actual standalone NPC. This is the former add_members
	# duplicate-owner branch, with real prior partial meal/hunger, not new food.
	captive.captive = true
	captive.ko = 100.0
	captive.pose = "unconscious"
	var personal := Sustain.create(10800.0)
	assert(Sustain.add_members(personal, helper._all_members(), [lab.npc.person_id, captive_id]).ok)
	personal.open_rations = 0.625
	personal.cohorts[0].hunger = 7.5
	personal.cohorts[0].coverage = 0.5
	personal.cohorts[0].meal_until = 21600.0
	data.site.person_supply = {str(lab.npc.person_id): personal}
	data.site.captivity[str(captive_id)] = {"version": 1, "captor_id": lab.npc.person_id,
		"guard_id": lab.npc.person_id, "captor_faction": 2, "sealed_container": ""}
	source._command_dirty = true
	source.settle_combat_command()
	var history := _history(personal, captive_id)
	var personal_before := personal.duplicate(true)
	assert(controller._supply_entry(source).is_empty())
	var transferred := source.transfer_members_to(target, [captive_id, free_id], source.current_commander, target.current_commander)
	assert(transferred.ok, str(transferred))
	assert(is_same(target.combat_units[target.index_for_identity(captive_id)], captive))
	assert(is_same(captive.cargo, original_cargo) and is_same(captive.item_state, original_gear))
	assert(personal == personal_before and _history(receiving.sustain, captive_id).is_empty())
	assert(not _history(receiving.sustain, free_id).is_empty())
	assert(controller._supply_entry(source).is_empty(), "Transferring a captive must not opt its old army into duplicate meals")
	assert(receiving.inventory.grain == 9 and receiving.sustain.open_rations == 0.375)
	_check(helper)
	# Release uses the new military registration while retaining the old meal.
	assert(helper.change_guard(captive_id, lab.npc.person_id, false).ok)
	captive.captive = false
	data.site.captivity.erase(str(captive_id))
	helper.commit_change(captive_id, lab.npc.person_id, false)
	assert(_history(receiving.sustain, captive_id) == history)
	assert(_history(personal, captive_id).is_empty() and personal.open_rations == 0.625)
	# The actual hostile NPC is now captured by the original source commander.
	# This helper fixture does not claim PersonActions' separate four-second bind.
	lab.npc.knockout_left = 100.0
	assert(helper.change_guard(lab.npc.person_id, captor_id, true).ok)
	lab.npc.captive = true
	data.site.captivity[str(lab.npc.person_id)] = {"version": 1, "captor_id": captor_id,
		"guard_id": guard_id, "captor_faction": 1, "sealed_container": ""}
	helper.commit_change(lab.npc.person_id, captor_id, true)
	var supplying: Dictionary = controller._supply_entry(source)
	supplying.inventory.fish = 6
	supplying.sustain.open_rations = 0.25
	var npc_history := _history(supplying.sustain, lab.npc.person_id)
	var guard_move := source.transfer_members_to(target, [guard_id], source.current_commander, target.current_commander)
	assert(guard_move.ok, str(guard_move))
	assert(_history(supplying.sustain, lab.npc.person_id) == npc_history,
		"A temporary guard does not own the captor's feeding obligation")
	var original_npc_cargo: Dictionary = data.site.worker.cargo
	var original_npc_gear: Dictionary = lab.npc.item_state
	var original_npc_hp := lab.npc.hp
	# Both failure paths run the real transfer entrypoint and must preserve every
	# owner/checkpoint/row. A later success may proceed without releasing captives.
	receiving.delivery = {"fixture": true}
	var before := data.site.duplicate(true)
	var source_rows := source.combat_units.duplicate()
	var target_rows := target.combat_units.duplicate()
	assert(source.transfer_members_to(target, [captor_id], source.current_commander, target.current_commander).code == "BUSY")
	assert(data.site == before and source.combat_units == source_rows and target.combat_units == target_rows)
	receiving.delivery = {}
	supplying.sustain.at -= 1.0
	before = data.site.duplicate(true)
	assert(source.transfer_members_to(target, [captor_id], source.current_commander, target.current_commander).code == "BUSY")
	assert(data.site == before)
	supplying.sustain.at += 1.0
	controller.person_actions._jobs["fixture"] = {"executor_id": lab.character.person_id, "target_id": lab.npc.person_id}
	before = data.site.duplicate(true)
	assert(source.transfer_members_to(target, [captor_id], source.current_commander, target.current_commander).code == "BUSY")
	assert(data.site == before)
	controller.person_actions._jobs.clear()
	var captor_history := _history(supplying.sustain, captor_id)
	var before_relation: Dictionary = data.site.captivity[str(lab.npc.person_id)].duplicate(true)
	var moved := source.transfer_members_to(target, [captor_id], source.current_commander, target.current_commander)
	assert(moved.ok, str(moved))
	assert(_history(receiving.sustain, captor_id) == captor_history)
	assert(_history(receiving.sustain, lab.npc.person_id) == npc_history)
	assert(_history(supplying.sustain, lab.npc.person_id).is_empty())
	assert(data.site.captivity[str(lab.npc.person_id)] == before_relation and lab.npc.captive)
	assert(lab.npc.hp == original_npc_hp and is_same(lab.npc.item_state, original_npc_gear))
	assert(is_same(data.site.worker.cargo, original_npc_cargo))
	assert(supplying.inventory == {"fish": 6} and supplying.sustain.open_rations == 0.25)
	assert(receiving.inventory == {"grain": 9} and receiving.sustain.open_rations == 0.375)
	assert(not supplying.life_checkpoint.has(str(lab.npc.person_id)) and receiving.life_checkpoint.has(str(lab.npc.person_id)))
	assert(is_same(helper.team_members(target, helper._original_members(target))[lab.npc.person_id].item_state, lab.npc.item_state))
	_check(helper)
	# The original row may become an independent person in the SAME simulation
	# container, retaining its own actual cargo and the captor's dependants.
	target.membership_change_hook = helper.membership_change
	data.site.controlled_person_id = captor_id
	var captor_body: Dictionary = target.combat_units[target.index_for_identity(captor_id)]
	var captor_cargo: Dictionary = captor_body.cargo
	var captor_gear: Dictionary = captor_body.item_state
	var leave_result := target.leave_row(captor_id)
	assert(leave_result.ok, str(leave_result))
	assert(not bool(captor_body.member) and helper._original_team(captor_id) == null)
	assert(helper._home(captor_id).key == "person:%d" % captor_id)
	var captor_personal: Dictionary = data.site.person_supply[str(captor_id)]
	assert(_history(captor_personal, captor_id) == captor_history and _history(captor_personal, lab.npc.person_id) == npc_history)
	assert(not helper.team_members(target, helper._original_members(target)).has(captor_id))
	assert(is_same(helper.personal_members_id(captor_id)[captor_id], captor_body))
	assert(is_same(captor_body.cargo, captor_cargo) and is_same(captor_body.item_state, captor_gear))
	assert(supplying.inventory == {"fish": 6} and receiving.inventory == {"grain": 9})
	captor_personal.open_rations = 0.125 # Existing private opened stock, not an item transfer.
	captor_personal.at -= 1.0
	before = data.site.duplicate(true)
	assert(target.join_row(captor_id).code == "BUSY" and data.site == before and not bool(captor_body.member))
	captor_personal.at += 1.0
	assert(target.join_row(captor_id).ok)
	assert(bool(captor_body.member) and helper._original_team(captor_id) == target)
	assert(captor_personal.cohorts.is_empty() and captor_personal.open_rations == 0.125)
	assert(_history(receiving.sustain, captor_id) == captor_history and _history(receiving.sustain, lab.npc.person_id) == npc_history)
	assert(is_same(target.combat_units[target.index_for_identity(captor_id)], captor_body))
	_check(helper)
	# Releasing after a captor move returns exactly the original personal owner.
	assert(helper.change_guard(lab.npc.person_id, captor_id, false).ok)
	lab.npc.captive = false
	data.site.captivity.erase(str(lab.npc.person_id))
	helper.commit_change(lab.npc.person_id, captor_id, false)
	assert(_history(personal, lab.npc.person_id) == npc_history and personal.open_rations == 0.625)
	_check(helper)
	# Existing Actor join/leave uses the SAME helper, including its original
	# captive dependants, not the old one-ID-only player_supply_change path.
	data.site.controlled_person_id = lab.character.person_id
	assert(helper.change_guard(lab.npc.person_id, lab.character.person_id, true).ok)
	lab.npc.captive = true
	data.site.captivity[str(lab.npc.person_id)] = {"version": 1, "captor_id": lab.character.person_id,
		"guard_id": guard_id, "captor_faction": 1, "sealed_container": ""}
	helper.commit_change(lab.npc.person_id, lab.character.person_id, true)
	var actor_personal: Dictionary = data.site.person_supply[str(lab.character.person_id)]
	var actor_history := _history(actor_personal, lab.character.person_id)
	target.player_supply_hook = func(team: TerrainArmy, actor: TerrainTestCharacter, joining: bool) -> Dictionary:
		return helper.membership_change(team, actor.person_id, joining)
	assert(target.join_player(lab.character).ok)
	assert(actor_personal.cohorts.is_empty() and _history(receiving.sustain, lab.npc.person_id) == npc_history)
	assert(target.leave_player().ok)
	assert(_history(actor_personal, lab.character.person_id) == actor_history)
	assert(_history(actor_personal, lab.npc.person_id) == npc_history)
	assert(_history(receiving.sustain, lab.npc.person_id).is_empty())
	assert(lab.npc.hp == original_npc_hp and is_same(lab.npc.item_state, original_npc_gear))
	assert(is_same(data.site.worker.cargo, original_npc_cargo))
	_check(helper)
	assert(source.combat_units.size() + target.combat_units.size() == 12)
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE CAPTIVITY ROSTER SUPPLY PASS: original transfer/row leave-rejoin/Actor join-leave; captured military registration preserves actual feeding, unfed joins once, captor's dependants retain meal/hunger without moving stock, guard alone does not; busy/lag/job rejection atomic; original personal history and body/cargo/gear references survive")
	quit(0)
