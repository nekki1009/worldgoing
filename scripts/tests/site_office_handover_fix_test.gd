extends "res://scripts/tests/site_building_ui_test.gd"
## F04 / F09 regressions (v2 plan):
## F04 handing team.training to another seat keeps the accepted order running
##     (OFFICE plan 3.6); the new holder may stop it, the old issuer may not.
## F09 a captured non-head settlement holder keeps the seat while the head acts
##     (decision D1); the settlement head itself keeps its own capture rule.

const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")

func _center_cells(data: TerrainData, anchor: Vector2i) -> Array[int]:
	var placement := Runtime.building_cells(data, "settlement_center", anchor, Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	assert(placement.ok, str(placement))
	var cells: Array[int] = []
	cells.assign(placement.cells)
	return cells

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	var data := _building_fixture()
	var base := TerrainGenerator.generate(data.preset, data.seed_value, data.parameters)
	data.flags = base.flags.duplicate()
	data.ramp_edges = base.ramp_edges.duplicate()
	for y: int in range(8, 55):
		for x: int in range(8, 55):
			data.site.terrain_changes[str(data.index(Vector2i(x, y)))] = int(data.height_levels[data.index(Vector2i(x, y))])
	Runtime.rebuild_terrain_edges(data)
	var lab := _building_lab(data)
	lab.fixed_action_steps_enabled = false
	var controller: SiteController = lab.site_controller
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	team.faction_id = lab.character.faction_id
	assert(team.deploy_at(data, lab.character, lab.npc, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26), Vector2i(26, 26)]))
	assert(team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()
	data.site.army_next_team = team.team_id + 1
	var captain := team.combat_identity(team.current_commander)
	var coach := team.combat_identity(2)
	assert(team.set_military_role(coach, "officer").ok and team.record_officer_service([2], true).ok)
	# Start from the empty one-seat-per-duty layout: R1b auto-appointment seats
	# officers when they are promoted or enter service (user decision 2026-10-07).
	team.offices = SiteOffices.default_offices("team", -1, team.offices.duty_ai)
	team._mark_serving_dirty()
	assert(_formal_feature(data, "training_ground", Vector2i(20, 20), Vector2i(10, 10)) != "")
	var entry: Dictionary = controller._enable_team_supply(team)
	entry.inventory.grain = 30

	# --- F04: captain (head, 教頭 vacant) orders training, then hands the duty over.
	team.training = 0.0
	team.team_fatigue.fatigue = 0.0
	var ordered := controller.order_team_training(team, team.current_commander, true)
	assert(ordered.ok, str(ordered))
	assert(int(entry.training_requester) == captain)
	var offices := team.team_offices()
	assert(team.apply_office_plan(captain, int(offices.revision), [{"op": "appoint", "position_id": str(offices.duties["team.training"]), "person_id": coach}]).ok)
	var before := team.training
	lab._process(0.1)
	assert(entry.training_order, "Handing team.training over must not cancel the accepted order (3.6)")
	assert(team.training > before, "Training keeps progressing after the handover")
	var old_stop := controller.order_team_training(team, team.current_commander, false)
	assert(str(old_stop.code) == "NO_AUTHORITY" and entry.training_order, "The previous issuer can no longer stop it: " + str(old_stop))
	var new_stop := controller.order_team_training(team, team.index_for_identity(coach), false)
	assert(new_stop.ok and not entry.training_order, "The new holder controls the order: " + str(new_stop))

	# --- F09: settlement seat of a captured holder is kept; the head acts.
	data.site.inventory.wood = maxi(int(data.site.inventory.get("wood", 0)), 200)
	data.site.inventory.stone = maxi(int(data.site.inventory.get("stone", 0)), 200)
	var player := lab.character
	assert(player.place(Vector2i(32, 32), true))
	var founded := Settlement.found(lab, player.person_id, _center_cells(data, Vector2i(34, 34)), {"layout_version": 1, "quarter": 0}, Callable(), "測試聚落")
	assert(founded.ok, str(founded))
	_complete_key(data, str(founded.feature))
	var settlement_offices := Settlement.offices(lab)
	var warden_seat := str(settlement_offices.duties["settlement.prison"])
	var warden := team.combat_identity(3)
	assert(Settlement.apply_office_plan(lab, player.person_id, int(settlement_offices.revision), [{"op": "appoint", "position_id": warden_seat, "person_id": warden}]).ok)
	team.combat_hot_set(3, &"captive", true)
	Settlement.settle_offices(lab)
	assert(int(SiteOffices.position(Settlement.offices(lab), warden_seat).holder) == warden, "Captured 典獄 keeps the seat (D1)")
	var acting := Settlement.duty_resolve(lab, "settlement.prison")
	assert(bool(acting.ok) and int(acting.decider) == player.person_id and bool(acting.acting), "Head acts for the captured holder: " + str(acting))
	team.combat_hot_set(3, &"captive", false)
	acting = Settlement.duty_resolve(lab, "settlement.prison")
	assert(int(acting.decider) == warden and not bool(acting.acting), "Freed holder returns to duty automatically")
	# The head's own capture rule is unchanged: a captured head is vacated.
	player.captive = true
	Settlement.settle_offices(lab)
	assert(int(SiteOffices.head_position(Settlement.offices(lab)).holder) == -1, "Settlement head keeps its P0 capture rule")
	player.captive = false

	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_OFFICE_HANDOVER_FIX_PASS: training survives duty handover, new holder stops it, old issuer refused; captured settlement holder keeps seat with head acting; head capture rule unchanged")
	quit(0)
