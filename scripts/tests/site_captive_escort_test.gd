extends "res://scripts/tests/site_workflow_test.gd"

func _run() -> void:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	var data := _fixture()
	lab.bind_terrain(data)
	var controller: SiteController = lab.site_controller
	controller._auto_save_blocked = true
	controller.release_worker()
	var guard: TerrainTestCharacter = lab.character
	var prisoner: TerrainTestNPC = lab.npc
	guard.place(Vector2i(35, 35), true)
	prisoner.place(Vector2i(34, 35), true)
	guard.faction_id = 1
	prisoner.faction_id = 2
	prisoner.captive = true
	prisoner.issue_command(TerrainTestNPC.Command.STOP)
	data.site.captivity[str(prisoner.person_id)] = {"version": 1, "captor_id": guard.person_id,
		"guard_id": guard.person_id, "captor_faction": 1, "sealed_container": ""}
	var original_items := prisoner.item_state.duplicate(true)
	var original_hp := prisoner.hp
	var escort: Variant = controller.captive_escort
	assert(not prisoner.step(Vector2i.DOWN))
	assert(not prisoner.step(Vector2i.DOWN, false, guard.person_id))
	assert(not escort.begin(prisoner.person_id, guard.person_id, Vector2i(35, 40)).ok)
	assert(escort.begin(guard.person_id, guard.person_id, Vector2i(35, 40)).ok)
	var start := prisoner.terrain_cell
	data.site.paused = true
	escort.advance(60.0)
	assert(prisoner.terrain_cell == start and guard.terrain_cell == Vector2i(35, 35))
	data.site.paused = false
	for frame in range(120):
		var old_guard := guard.terrain_cell
		var old_prisoner := prisoner.terrain_cell
		lab._advance_combat(0.05, 0.0)
		assert(old_guard == guard.terrain_cell or data.can_step(old_guard, guard.terrain_cell))
		assert(old_prisoner == prisoner.terrain_cell or data.can_step(old_prisoner, prisoner.terrain_cell))
		assert(prisoner.captive and prisoner.hp == original_hp and prisoner.item_state == original_items)
		assert(controller.person_actions.has_effective_guard(prisoner.person_id))
		if data.site.escort_orders.is_empty() and not prisoner.is_moving() and not guard.is_moving():
			break
	assert(guard.terrain_cell == Vector2i(35, 40) and data.site.escort_orders.is_empty())
	assert(prisoner.terrain_cell != start and prisoner.captive)
	assert(escort.begin(guard.person_id, guard.person_id, Vector2i(40, 40)).ok)
	controller._capture_positions()
	assert(Store.save(data, "user://escort/original.json").ok)
	var loaded := Store.load_site("user://escort/original.json")
	assert(loaded.ok and loaded.data.site.escort_orders == data.site.escort_orders)
	guard.apply_contact({"result": {"hp": 1000.0, "stun": 0.0, "guard_break": false}, "shield": false})
	escort.advance(1.0)
	assert(data.site.escort_orders.is_empty() and prisoner.captive)
	assert(not controller.person_actions.has_effective_guard(prisoner.person_id))
	# A former row remains the same person, but its old captain loses authority.
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	var cells: Array[Vector2i] = [Vector2i(20, 20), Vector2i(21, 20), Vector2i(22, 20)]
	assert(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()
	var original_id := team.combat_identity(1)
	var captain_id := team.combat_identity(team.current_commander)
	var original_person: Dictionary = controller.person_actions._person(original_id)
	assert(escort._authority(captain_id, original_person))
	data.site.controlled_person_id = original_id # Explicit control fixture, not death-only succession proof.
	assert(team.leave_row(original_id).ok)
	assert(not escort._authority(captain_id, original_person) and escort._authority(original_id, original_person))
	assert(escort.begin(captain_id, original_id, Vector2i(22, 22)).code == "NO_AUTHORITY")
	print("SITE_CAPTIVE_ESCORT_PASS original edges, pause, custody, no refill, save/load, guard death")
	lab.free()
	quit()
