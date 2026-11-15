extends "res://scripts/tests/site_building_ui_test.gd"
## F08 (v2 plan R0): cancelling a team re-equip job re-checks the canceller now.
## The 整隊領裝 holder may cancel; after the duty moves to someone else, the old
## holder's window is refused and the new holder may cancel; the representative
## may abort their own job; a request from someone no longer controlled is refused.
## The job record is injected (the real batch needs GPU atlas preparation); the
## authority path and the original cancel are the production ones.

func _job(lab: TerrainLab, team: TerrainArmy, representative: int) -> void:
	lab.site_controller.person_actions._jobs[str(representative)] = {"kind": "equipment",
		"order": {"mode": "team_issue", "team": team, "terrain": lab.terrain, "target_ids": [representative]}}

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
	var orders: SiteEquipmentOrders = lab.site_controller.equipment_orders
	var actions: SitePersonActions = lab.site_controller.person_actions
	var head := team.combat_identity(team.formal_commander)
	# The controlled person here is an ordinary member (index 1) holding the 文官 seat.
	var player := team.combat_identity(1)
	data.site.controlled_person_id = player
	var representative := team.combat_identity(3)
	var other := team.combat_identity(2)
	assert(head != player and representative != player and other != player and other != head)
	# 整隊領裝 on a 文官 seat held by the player.
	var offices := team.team_offices()
	var seat := str(offices.duties["team.equip"])
	# 文武官 W2: a 文官 seat needs a 文吏 (a 武官 seat an officer); the fixture qualifies its holder first.
	team.set_civil_role(player, "clerk")
	var given := team.apply_office_plan(head, int(offices.revision), [{"op": "classify", "position_id": seat, "office_class": "civil"},
		{"op": "appoint", "position_id": seat, "person_id": player}])
	assert(given.ok, str(given))
	_job(lab, team, representative)
	assert(orders.cancel_team_issue(player, representative).ok, "Current holder cancels")
	assert(not actions.is_busy(representative))
	# Hand the duty to another member: the old holder's window is refused, the new holder may cancel.
	_job(lab, team, representative)
	offices = team.team_offices()
	# 文武官 W2: a 文官 seat needs a 文吏 (a 武官 seat an officer); the fixture qualifies its holder first.
	team.set_civil_role(other, "clerk")
	assert(team.apply_office_plan(head, int(offices.revision), [{"op": "dismiss", "position_id": seat}, {"op": "appoint", "position_id": seat, "person_id": other}]).ok)
	var refused := orders.cancel_team_issue(player, representative)
	assert(str(refused.code) == "NO_AUTHORITY" and actions.is_busy(representative), "Old holder after handover is refused: %s" % str(refused))
	data.site.controlled_person_id = other
	assert(orders.cancel_team_issue(other, representative).ok, "New holder cancels the same job")
	# The representative aborts their own job; a stale requester (no longer controlled) is refused.
	_job(lab, team, representative)
	assert(str(orders.cancel_team_issue(player, representative).code) == "NO_AUTHORITY", "A window from a person no longer controlled is refused")
	data.site.controlled_person_id = representative
	assert(orders.cancel_team_issue(representative, representative).ok, "Representative aborts their own job")
	assert(str(orders.cancel_team_issue(representative, representative).code) == "NO_TARGET")
	data.site.erase("controlled_person_id")
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_TEAM_EQUIP_CANCEL_PASS: holder cancels, old holder refused after handover, new holder cancels, stale controlled requester refused, representative self-abort")
	quit(0)
