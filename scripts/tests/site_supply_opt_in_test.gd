extends "res://scripts/tests/site_workflow_test.gd"
## Explicit existing private histories + first team opt-in, never reset meals.

const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")

func _history(state: Dictionary, identity: int) -> Dictionary:
	for cohort: Dictionary in state.cohorts:
		if identity in cohort.ids:
			var result := cohort.duplicate(true)
			result.erase("ids")
			return result
	return {}

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
	var team: TerrainArmy = lab.army
	team.roster_size = 6
	var cells: Array[Vector2i] = []
	for index: int in 6:
		cells.append(Vector2i(18 + index % 3, 23 + floori(float(index) / 3.0)))
	assert(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false))
	team.set_process(false)
	controller.initialize_team_items(team)
	data.site.army_next_team = team.team_id + 1 # Direct deployment fixture reserves its original ID.
	var first_id := team.combat_identity(1)
	var second_id := team.combat_identity(2)
	var row: Dictionary = team.combat_units[1]
	row.cargo.grain = 3
	var personal := Sustain.create(10800.0)
	var delayed := Sustain.create(10799.0)
	var members: Dictionary = controller.captivity_supply._all_members()
	# A legal preexisting snapshot can hold private meal history before explicit
	# group opt-in. The captive was already assigned to this original captor.
	lab.npc.captive = true
	lab.npc.faction_id = 2
	assert(Sustain.add_members(personal, members, [first_id, lab.npc.person_id]).ok)
	assert(Sustain.add_members(delayed, members, [second_id]).ok)
	personal.open_rations = 0.75
	personal.cohorts[0].hunger = 7.5
	personal.cohorts[0].coverage = 0.5
	personal.cohorts[0].meal_until = 21600.0
	delayed.cohorts[0].hunger = 3.0
	delayed.cohorts[0].coverage = 0.25
	delayed.cohorts[0].meal_until = 21600.0
	data.site.person_supply = {str(first_id): personal, str(second_id): delayed}
	data.site.captivity[str(lab.npc.person_id)] = {"version": 1, "captor_id": first_id,
		"guard_id": first_id, "captor_faction": team.faction_id, "sealed_container": ""}
	var original_personal := personal.duplicate(true)
	var original_delayed := delayed.duplicate(true)
	var original_cargo: Dictionary = row.cargo
	var original_holder: Dictionary = row.item_state
	assert(controller._enable_team_supply(team).is_empty(), "Stale populated time cannot be silently skipped")
	assert(personal == original_personal and delayed == original_delayed and controller._supply_entry(team).is_empty(), "Whole first opt-in fails without partial meal movement")
	delayed.at = 10800.0 # Repair only the deliberately stale test snapshot.
	var first_history := _history(personal, first_id)
	var captive_history := _history(personal, lab.npc.person_id)
	var second_history := _history(delayed, second_id)
	var entry: Dictionary = controller._enable_team_supply(team)
	assert(not entry.is_empty())
	assert(_history(entry.sustain, first_id) == first_history)
	assert(_history(entry.sustain, lab.npc.person_id) == captive_history)
	assert(_history(entry.sustain, second_id) == second_history)
	assert(Sustain._ids(entry.sustain).size() == 7 and personal.cohorts.is_empty() and delayed.cohorts.is_empty())
	assert(personal.open_rations == 0.75 and entry.sustain.open_rations == 0.0 and entry.inventory.is_empty())
	assert(is_same(row.cargo, original_cargo) and is_same(row.item_state, original_holder) and row.cargo.grain == 3)
	var before_repeat := entry.duplicate(true)
	assert(is_same(controller._enable_team_supply(team), entry) and entry == before_repeat)
	var states: Array = [entry.sustain, personal, delayed]
	assert(Sustain.validate_owners(states, controller.captivity_supply._all_members()))
	# Pure opened food uses its original pool and a single original sparse bag.
	var version := int(original_holder.version)
	var dropped := Runtime.leave_ground_loot(data, original_holder, original_cargo, first_id,
		team.cells[1], "cargo", {}, [], version, personal, 0.5)
	assert(dropped.ok, str(dropped))
	var container: Dictionary = data.site.ground_loot[dropped.container_id]
	assert(container.open_rations == 0.5 and container.cargo.is_empty() and container.item_ids.is_empty())
	assert(personal.open_rations == 0.25 and original_cargo.grain == 3)
	assert(Runtime.clear_empty_ground_loot(data, dropped.container_id).code == "BUSY")
	var before_failure := JSON.stringify([original_holder, original_cargo, personal, data.site.ground_loot, data.site.next_loot])
	assert(not Runtime.leave_ground_loot(data, original_holder, original_cargo, first_id,
		team.cells[1], "cargo", {}, [], version, personal, 0.25).ok)
	assert(not Runtime.leave_ground_loot(data, original_holder, original_cargo, first_id,
		team.cells[1], "cargo", {"grain": 1}, ["missing"], int(original_holder.version), personal, 0.25).ok)
	assert(not Runtime.leave_ground_loot(data, original_holder, original_cargo, first_id,
		team.cells[1], "cargo", {}, [], int(original_holder.version), personal, NAN).ok)
	assert(JSON.stringify([original_holder, original_cargo, personal, data.site.ground_loot, data.site.next_loot]) == before_failure)
	team.combat_units[1].logistics = true # Explicit saved role fixture, UI authority tested separately.
	controller._capture_positions()
	var saved := Store.save(data, "user://supply-opt-in/original.json")
	assert(saved.ok, str(saved))
	var loaded := Store.load_site("user://supply-opt-in/original.json")
	assert(loaded.ok, str(loaded))
	assert(loaded.data.site.ground_loot[dropped.container_id].open_rations == 0.5)
	assert(loaded.data.site.armies[0].units[1].logistics == true)
	var invalid: Dictionary = data.site.duplicate(true)
	invalid.ground_loot[dropped.container_id].open_rations = -0.01
	assert(not Store._validate_items(data, invalid).ok)
	invalid = data.site.duplicate(true)
	invalid.ground_loot[dropped.container_id].unknown = true
	assert(not Store._validate_items(data, invalid).ok)
	invalid = data.site.duplicate(true)
	invalid.armies[0].units[1].logistics = "true"
	assert(not Store._validate_armies(data, invalid).ok)
	print("SITE_SUPPLY_OPT_IN_PASS original row and captive private meal history, atomic stale rejection, no stock movement, pure opened-food bag, failed-drop conservation, strict original save/load roles and fractions")
	lab.free()
	quit()
