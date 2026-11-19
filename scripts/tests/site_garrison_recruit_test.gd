extends "res://scripts/tests/site_garrison_test.gd"
## v2 plan 3.4 募兵, fourth source (user decision 2026-10-08): garrisoned original
## soldiers join an existing team through SiteGarrison.recruit, authorized by the
## barracks authority and the receiving team's team.recruit decider, with the
## soldier's consent. Rows, presenters and feeding cohorts move together; the
## settlement catalog carries 營務官 (settlement.garrison) as a later duty.

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var key := _formal_feature(data, "barracks", Vector2i(20, 20), Vector2i(10, 10))
	var source: TerrainArmy = lab.army
	var receiver: TerrainArmy = lab.opposing_army
	_make_garrison_team(lab, source, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26)])
	_make_garrison_team(lab, receiver, [Vector2i(24, 27), Vector2i(25, 27)])
	for team: TerrainArmy in [source, receiver]:
		assert(not controller._enable_team_supply(team).is_empty())
	var soldier := source.combat_identity(1)
	var soldier_row: Dictionary = source.combat_units[1]
	assert(Garrison.admit(lab, key, source.team_id).ok, "Whole source team garrisons")
	assert(not source.garrison_feature_id.is_empty())
	var receiver_head := receiver.combat_identity(receiver.formal_commander)
	assert(SiteOffices.duty_ids("settlement").has("settlement.garrison") and SiteOffices.LATER_DUTIES.settlement.has("settlement.garrison"), "營務官 is a settlement later duty")
	# The controlled requester must exercise the receiver's team.recruit.
	data.site.controlled_person_id = receiver.combat_identity(1)
	assert(str(Garrison.recruit(lab, key, [soldier], receiver.team_id).code) == "NO_AUTHORITY", "Only the receiving recruit decider")
	data.site.controlled_person_id = receiver_head
	assert(str(Garrison.recruit(lab, key, [soldier], source.team_id).code) == "INVALID_TEAM", "A garrison is not a receiving team")
	var rows_before := receiver.combat_units.size()
	var enlisted := Garrison.recruit(lab, key, [soldier], receiver.team_id)
	assert(enlisted.ok, str(enlisted))
	var index := receiver.index_for_identity(soldier)
	assert(index >= rows_before and receiver.is_member(index) and source.index_for_identity(soldier) == -1, "Original soldier moved into the receiving team")
	assert(is_same(receiver.combat_units[index], soldier_row), "The original row moved; nothing was created")
	assert(not receiver.officer_service.has(index), "Arrives as an ordinary member (plan 3.5)")
	_meal_history(controller) # Feeding owners still validate after the move.
	data.site.erase("controlled_person_id")
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_GARRISON_RECRUIT_PASS: 營務官 later duty, recruit decider only, garrison not a receiver, original garrisoned soldier moves into an existing team as an ordinary member, feeding owners valid")
	quit(0)
