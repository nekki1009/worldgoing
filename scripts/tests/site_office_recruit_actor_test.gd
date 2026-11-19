extends "res://scripts/tests/site_building_ui_test.gd"
## v2 plan 3.4 募兵, second source: a free original Actor of the same faction
## joins through the original join_player path, authorized by team.recruit with
## consent (the controlled character must confirm themselves). No body copy.

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var data := _building_fixture()
	var lab := _building_lab(data)
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	team.faction_id = 1
	assert(team.deploy_at(data, lab.character, lab.npc, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26), Vector2i(26, 26)]))
	assert(team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()
	var head := team.combat_identity(team.formal_commander)
	var worker: TerrainTestCharacter = lab.npc
	assert(worker != null and not is_instance_valid(team.player_member), "Fixture: free worker, empty Actor slot")
	worker.faction_id = team.faction_id
	assert(str(team.recruit_actor(team.combat_identity(2), worker).code) == "NO_AUTHORITY", "Only the team.recruit decider")
	assert(str(team.recruit_actor(head, lab.character).code) == "NEEDS_CONSENT", "The controlled character confirms themselves")
	var rows_before := team.combat_units.size()
	var enlisted := team.recruit_actor(head, worker)
	assert(enlisted.ok, str(enlisted))
	assert(team.player_member == worker and team.combat_units.size() == rows_before, "Original Actor joins its slot; no row is created")
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_OFFICE_RECRUIT_ACTOR_PASS: free same-faction Actor enlisted through join_player by the recruit decider, controlled character needs own consent, no row created")
	quit(0)
