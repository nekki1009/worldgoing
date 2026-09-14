extends "res://scripts/tests/site_workflow_test.gd"

const Feeding = preload("res://scripts/terrain_lab/site_captivity_supply.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")

func _history(state: Dictionary, identity: int) -> Dictionary:
	for cohort: Dictionary in state.cohorts:
		if identity in cohort.ids:
			var result := cohort.duplicate(true)
			result.erase("ids")
			return result
	return {}

func _bind(helper: Variant, data: TerrainData, body: Dictionary, captor_id: int, faction: int, capturing: bool) -> void:
	# Same synchronous ordering as PersonActions: relationship/body first, then
	# the already prepared feeding commit. No fixture substitute person is made.
	if capturing:
		data.site.captivity[str(body.person_id)] = {"version": 1, "captor_id": captor_id,
			"guard_id": captor_id, "captor_faction": faction, "sealed_container": ""}
	else:
		data.site.captivity.erase(str(body.person_id))
	body.captive = capturing
	helper.commit_change(int(body.person_id), captor_id, capturing)

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
	lab.character.faction_id = 1
	lab.npc.faction_id = 2
	lab.character.place(Vector2i(16, 30), true)
	lab.npc.place(Vector2i(18, 30), true)
	data.site.minute = 180
	data.site.phase = 0.0
	data.site.captivity = {}
	data.site.manual.cargo = {"grain": 5}
	data.site.worker.cargo = {"grain": 3}
	var controller: SiteController = lab.site_controller
	var first: TerrainArmy = lab.combat_armies[0]
	var second: TerrainArmy = lab.combat_armies[1]
	for team: TerrainArmy in [first, second]:
		team.roster_size = 40
		var cells: Array[Vector2i] = []
		var origin := Vector2i(16, 16) if team == first else Vector2i(22, 24)
		for index: int in 40:
			cells.append(origin + Vector2i(index % 8, floori(float(index) / 8.0)))
		assert(team.deploy_at(data, lab.character, lab.npc, cells))
		assert(team.enable_combat(false))
		team.set_process(false)
		team.faction_id = 1 if team == first else 2
		team.settle_combat_command()
	assert(first.join_player(lab.character).ok)
	first.player_present = true
	var helper := Feeding.new()
	helper.init(controller)
	var private := Sustain.create(10800.0)
	assert(Sustain.add_members(private, helper._all_members(), [lab.character.person_id]).ok)
	private.open_rations = 0.625
	private.cohorts[0].hunger = 7.5
	private.cohorts[0].coverage = 0.5
	private.cohorts[0].meal_until = 21600.0
	data.site.person_supply = {str(lab.character.person_id): private}
	var player_history := _history(private, lab.character.person_id)
	# Capturing explicitly opts in the two original teams; no new team/food/person.
	var first_captor := first.combat_identity(0)
	var initial_target: Dictionary = second.combat_units[1]
	initial_target.ko = 100.0
	var pristine := data.site.duplicate(true)
	assert(helper.change_guard(int(initial_target.person_id), first_captor, true).ok)
	assert(data.site == pristine, "Capture preflight is read-only, including pending owner initialization")
	_bind(helper, data, initial_target, first_captor, first.faction_id, true)
	var first_entry: Dictionary = controller._supply_entry(first)
	var second_entry: Dictionary = controller._supply_entry(second)
	assert(Sustain._ids(first_entry.sustain).size() == 42 and Sustain._ids(second_entry.sustain).size() == 39)
	assert(first_entry.inventory.is_empty() and second_entry.inventory.is_empty())
	assert(private.cohorts.is_empty() and private.open_rations == 0.625)
	assert(_history(first_entry.sustain, lab.character.person_id) == player_history)
	assert(data.site.manual.cargo == {"grain": 5} and data.site.worker.cargo == {"grain": 3})
	assert(helper.change_guard(int(initial_target.person_id), first_captor, false).ok)
	_bind(helper, data, initial_target, first_captor, first.faction_id, false)
	initial_target.ko = 0.0
	# Transfer the opposite way with an already-eaten partial meal and hunger.
	var target: Dictionary = first.combat_units[1]
	var target_id := int(target.person_id)
	var captor_id := second.combat_identity(0)
	target.ko = 100.0
	for cohort: Dictionary in first_entry.sustain.cohorts:
		if target_id in cohort.ids:
			cohort.hunger = 7.5
			cohort.coverage = 0.5
			cohort.meal_until = 21600.0
			cohort.bonus_pending = true
	first_entry.inventory = {"fish": 20, "meat": 20, "wild_food": 20, "grain": 50}
	first_entry.sustain.open_rations = 0.75
	first_entry.sustain.morale = 10.0
	first_entry.sustain.routed = true
	second_entry.inventory = {"grain": 19}
	second_entry.sustain.open_rations = 0.25
	var history := _history(first_entry.sustain, target_id)
	pristine = data.site.duplicate(true)
	assert(helper.change_guard(target_id, captor_id, true).ok and data.site == pristine)
	_bind(helper, data, target, captor_id, second.faction_id, true)
	assert(not helper.team_members(first, helper._original_members(first)).has(target_id))
	assert(is_same(helper.team_members(second, helper._original_members(second))[target_id], target))
	assert(_history(second_entry.sustain, target_id) == history)
	assert(second_entry.sustain.morale == 100.0 and not second_entry.sustain.routed,
		"A captured routed enemy is not a personnel merger and cannot rout its captor")
	assert(first_entry.sustain.open_rations == 0.75 and second_entry.sustain.open_rations == 0.25)
	assert(first_entry.inventory.grain == 50 and second_entry.inventory.grain == 19)
	assert(not helper.change_guard(target_id, captor_id, true).ok, "Cannot capture a captive twice")
	# Existing populated clock lag cannot skip hunger or consume catch-up food.
	second_entry.sustain.at = 10799.0
	pristine = data.site.duplicate(true)
	assert(not helper.change_guard(target_id, captor_id, false).ok and data.site == pristine)
	second_entry.sustain.at = 10800.0
	second_entry.delivery = {"fixture": true}
	assert(helper.change_guard(target_id, captor_id, false).code == "BUSY")
	second_entry.delivery = {}
	# Actual 100-ration ransom. Authority and opened-stock capacity are checked
	# here; adjacency/action timing remain PersonActions' separate acceptance.
	assert(helper.ransom_exchange_query(first.combat_identity(2), target_id, captor_id).code == "AUTHORITY")
	second_entry.inventory.grain = 20
	assert(helper.ransom_exchange_query(first_captor, target_id, captor_id).code == "STORAGE_FULL")
	second_entry.inventory.grain = 19
	assert(helper.ransom_exchange_query(lab.character.person_id, target_id, captor_id).ok,
		"Only the original eligible player_member may represent its qualified commander")
	assert(helper.change_guard(target_id, captor_id, false).ok)
	var query: Dictionary = helper.ransom_exchange_query(first_captor, target_id, captor_id)
	assert(query.ok and is_same(query.source, first_entry.inventory) and is_same(query.destination, second_entry.inventory))
	var source_revision := int(query.source_revision)
	var destination_revision := int(query.destination_revision)
	var food := {"fish": 20, "meat": 20, "wild_food": 20, "grain": 40}
	Runtime.add_items(query.source, food, -1)
	Runtime.add_items(query.destination, food)
	helper.ransom_exchange_committed(query)
	_bind(helper, data, target, captor_id, second.faction_id, false)
	assert(Sustain.rations(first_entry.sustain, first_entry.inventory) == 10.75)
	assert(Sustain.rations(second_entry.sustain, second_entry.inventory) == 119.25,
		"Prepared membership commit cannot overwrite the actual ransom inventory transfer")
	assert(first_entry.revision == source_revision + 2 and second_entry.revision == destination_revision + 2)
	assert(_history(first_entry.sustain, target_id) == history)
	assert(helper.ransom_exchange_query(first_captor, target_id, captor_id).code == "AUTHORITY")
	# A standalone original NPC has its original personal feeding owner/cargo.
	assert(helper.change_guard(target_id, lab.npc.person_id, true).ok)
	_bind(helper, data, target, lab.npc.person_id, lab.npc.faction_id, true)
	var personal: Dictionary = data.site.person_supply[str(lab.npc.person_id)]
	assert(_history(personal, target_id) == history)
	assert(is_same(helper.personal_members(lab.npc)[target_id], target))
	assert(not helper.team_members(first, helper._original_members(first)).has(target_id))
	assert(data.site.worker.cargo == {"grain": 3}, "Capture does not confiscate or pre-eat original cargo")
	lab.npc.hp = 0.0
	assert(data.site.captivity.has(str(target_id)) and bool(target.captive), "Dead captor does not auto-release its captive")
	var probe := personal.duplicate(true)
	probe.at = 21600.0
	for cohort: Dictionary in probe.cohorts:
		cohort.meal_until = 21600.0
	var stock := {"grain": 3}
	var meal := Sustain.resupply(probe, helper.personal_members(lab.npc), stock, true)
	assert(meal.ok and absf(float(meal.consumed_rations) - 0.25) < 0.000001, "Dead captor consumes nothing; one living captive eats once")
	# Release follows original feeding history even though the captor is dead.
	assert(helper.change_guard(target_id, lab.npc.person_id, false).ok)
	_bind(helper, data, target, lab.npc.person_id, lab.npc.faction_id, false)
	assert(_history(first_entry.sustain, target_id) == history)
	assert(_history(personal, target_id).is_empty())
	# Former empty personal owners may align forwards without losing open food.
	private.at = 0.0
	assert(first.leave_player().ok)
	assert(private.at == 10800.0 and private.open_rations == 0.625)
	assert(_history(private, lab.character.person_id) == player_history)
	var states: Array = []
	for entry: Dictionary in data.site.team_supply.values():
		states.append(entry.sustain)
	for state: Dictionary in data.site.person_supply.values():
		states.append(state)
	assert(Sustain.validate_owners(states, helper._all_members()))
	assert(is_same(first.combat_units[1], target) and first.combat_units.size() == 40 and second.combat_units.size() == 40)
	# The CURRENT original controller dispatches a captive's hunger damage to
	# their actual other-army body, then its existing death/loot entry point.
	var dying: Dictionary = first.combat_units[2]
	var dying_id := int(dying.person_id)
	dying.ko = 100.0
	assert(helper.change_guard(dying_id, captor_id, true).ok)
	_bind(helper, data, dying, captor_id, second.faction_id, true)
	for cohort: Dictionary in second_entry.sustain.cohorts:
		if dying_id in cohort.ids:
			cohort.hunger = 49.0
			cohort.coverage = 0.0
			cohort.meal_until = 21600.0
	dying.hp = 0.01
	dying.attack = true
	var prior_hit := int(dying.get("hit_revision", 0))
	controller.advance_team_sustain(second, 36.0)
	assert(dying.hp == 0.0 and dying.pose == "down" and not dying.attack,
		"Original hunger death must commit: hp=%.18f pose=%s attack=%s supply_at=%.6f message=%s" %
		[float(dying.hp), str(dying.pose), str(dying.attack), float(second_entry.sustain.at), controller.message.text])
	assert(int(dying.get("hit_revision", 0)) == prior_hit and data.site.combat_left == 0.0)
	controller.settle_person_deaths(3.0)
	assert(not data.site.captivity.has(str(dying_id)))
	assert(helper.team_members(second, helper._original_members(second)).has(dying_id))
	assert(not helper.team_members(first, helper._original_members(first)).has(dying_id),
		"Clearing a dead captive relationship cannot reassign/refund their original eating history")
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE CAPTIVITY SUPPLY PASS: original team/personal food owners, read-only preflight and synchronous history-only capture/release, 100 real rations and authority/open capacity, dead captor retention, cross-army original hunger death dispatch, original IDs and no food/person copies; action timing/save/GPU separately required")
	quit(0)
