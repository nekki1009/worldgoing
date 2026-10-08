extends "res://scripts/tests/site_building_ui_test.gd"
## Appendix D.7: settlement.prison (典獄). Old head-only records gain the vacant
## seat; the head (player) keeps the original escort path while the seat is
## vacant; an appointed NPC 典獄 owns escort/release authority; the prison duty
## AI with 仁厚 100 waits exactly 10 days, walks to the contact cell and releases.

const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")
const PP = preload("res://scripts/terrain_lab/person_personality.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")

func _center_cells(data: TerrainData, anchor: Vector2i) -> Array[int]:
	var placement := Runtime.building_cells(data, "settlement_center", anchor, Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	assert(placement.ok, str(placement))
	var cells: Array[int] = []
	cells.assign(placement.cells)
	return cells

func _run() -> void:
	deadline = Time.get_ticks_msec() + 240000
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var player: TerrainTestCharacter = lab.character
	var captive: TerrainTestNPC = lab.npc
	var actions: SitePersonActions = controller.person_actions
	var player_id := player.person_id
	assert(lab.controlled_person_id() == player_id)

	# Same-faction team that will provide the 典獄.
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	team.faction_id = player.faction_id
	assert(team.deploy_at(data, null, null, [Vector2i(28, 30), Vector2i(29, 30), Vector2i(30, 30)]))
	assert(team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()
	var warden := team.combat_identity(1)

	# Settlement: the player founds and heads it; the prison is in its jurisdiction.
	data.site.inventory.wood = maxi(int(data.site.inventory.get("wood", 0)), 200)
	data.site.inventory.stone = maxi(int(data.site.inventory.get("stone", 0)), 200)
	assert(player.place(Vector2i(26, 22), true))
	var founded := Settlement.found(lab, player_id, _center_cells(data, Vector2i(20, 20)), {"layout_version": 1, "quarter": 0}, Callable(), "測試聚落")
	assert(founded.ok, str(founded))
	_complete_key(data, str(founded.feature))
	var prison_key := _formal_feature(data, "prison", Vector2i(35, 35))
	data.site.features[prison_key].owner_faction = player.faction_id
	assert(Settlement.prison_governed(lab, prison_key), "Camp in jurisdiction of the same faction is governed")

	# Old head-only record: still valid, gains the vacant 典獄 seat on first use.
	var record: Dictionary = data.site.settlement
	var old_shape := SiteOffices.default_offices("settlement", player_id, false)
	for later: String in SiteOffices.LATER_DUTIES.settlement:
		var seat_id := str(old_shape.duties[later])
		old_shape.duties.erase(later)
		old_shape.positions.erase(SiteOffices.position(old_shape, seat_id))
	assert(SiteOffices.validate(old_shape, "settlement", true), "Pre-D.7 settlement offices still load")
	record.offices = old_shape
	var offices := Settlement.offices(lab)
	assert(offices.duties.has("settlement.prison") and int(SiteOffices.position(offices, str(offices.duties["settlement.prison"])).holder) == -1)
	var resolved := Settlement.duty_resolve(lab, "settlement.prison")
	assert(bool(resolved.ok) and int(resolved.decider) == player_id and bool(resolved.acting), "Vacant 典獄: the head acts")

	# Capture as in the original prison test, then the head escorts in (player path).
	assert(player.place(Vector2i(35, 38), true) and captive.place(Vector2i(34, 38), true))
	captive.faction_id = 2
	captive.knockout_left = 30.0
	captive.issue_command(TerrainTestNPC.Command.STOP)
	assert(actions.begin_capture(player_id, captive.person_id, player_id).ok)
	actions.advance(4.0)
	assert(actions.settle_after_contacts()[0].ok and captive.captive)
	captive.knockout_left = 0.0
	captive.stun = 0.0
	captive._getting_up = false
	captive.action_time = 0.0
	# An appointed 典獄 takes the decision away from the head.
	assert(Settlement.apply_office_plan(lab, player_id, int(offices.revision), [{"op": "appoint", "position_id": str(offices.duties["settlement.prison"]), "person_id": warden}]).ok)
	var refused := controller.captive_escort.begin_prison(player_id, player_id, prison_key)
	assert(str(refused.code) == "NO_AUTHORITY" and str(refused.message).contains("典獄"), str(refused))
	assert(Settlement.apply_office_plan(lab, player_id, int(Settlement.offices(lab).revision), [{"op": "dismiss", "position_id": str(offices.duties["settlement.prison"])}]).ok)
	var started := controller.captive_escort.begin_prison(player_id, player_id, prison_key)
	assert(started.ok, "Head (player) path still works while 典獄 is vacant: " + str(started))
	var layout := Runtime.prison_layout(data, prison_key)
	var slot: Dictionary = layout.slots[0]
	for _frame: int in range(3600):
		lab._advance_action_time(TerrainLab.ACTION_STEP)
		if not str(data.site.captivity[str(captive.person_id)].get("prison_id", "")).is_empty(): break
	assert(str(data.site.captivity[str(captive.person_id)].get("prison_id", "")) == prison_key, "Escort admitted the captive")
	controller.captive_escort.cancel(player_id)

	# NPC 典獄 with 仁厚 100; the player's own release is now refused.
	offices = Settlement.offices(lab)
	assert(Settlement.apply_office_plan(lab, player_id, int(offices.revision), [{"op": "appoint", "position_id": str(offices.duties["settlement.prison"]), "person_id": warden}]).ok)
	assert(player.terrain_cell == slot.contact_cell)
	var player_release := actions.begin_prison_release(player_id, captive.person_id, player_id)
	assert(str(player_release.code) == "NO_AUTHORITY", str(player_release))
	assert(player.place(Vector2i(26, 22), true), "Player steps away from the contact cell")
	team.combat_units[1].personality = PP.neutral()
	team.combat_units[1].personality.mercy = 100
	assert(Settlement.set_duty_ai_enabled(lab, player_id, true).ok)

	# Hold table: 仁厚 100 → 10 days, neutral → 30, 嚴酷 0 → 50.
	assert(DutyAI.prison_hold_minutes(team.combat_units[1].personality) == 14400)
	assert(DutyAI.prison_hold_minutes(PP.neutral()) == 43200)
	var harsh := PP.neutral()
	harsh.mercy = 0
	assert(DutyAI.prison_hold_minutes(harsh) == 72000)
	assert(DutyAI.stranded_wait(team.combat_units[1].personality) == 0, "Captive-holder wait proxy retired to keep two 仁厚 readers")

	DutyAI._inmate_since.clear()
	DutyAI.review_round = 0
	assert(DutyAI.review_prison(lab, player_id).is_empty(), "Day 0: still held")
	# Back-date the saved admission minute (F02: captivity v3) instead of jumping
	# the game clock (the clock must stay in step with supply pools, which
	# releases re-check).
	var key := str(captive.person_id)
	var now := int(data.site.minute)
	assert(int(data.site.captivity[key].version) == 3 and float(data.site.captivity[key].admitted_at_game_seconds) <= float(now + 1) * 60.0, "Admission time saved")
	data.site.captivity[key].admitted_at_game_seconds = float(now - 14399) * 60.0
	assert(DutyAI.review_prison(lab, player_id).is_empty(), "One minute short of 10 days: still held")
	data.site.captivity[key].admitted_at_game_seconds = float(now - 14400) * 60.0
	var walk := DutyAI.review_prison(lab, player_id)
	assert(bool(walk.get("ok", false)) and controller.captive_escort.is_release_walking(warden), "仁厚 典獄 walks to release at 10 days: " + str(walk))
	assert(int(DutyAI.settlement_traces[-1].decider_person_id) == warden and not bool(DutyAI.settlement_traces[-1].acting))
	var released := false
	for _frame: int in range(6000):
		lab._advance_action_time(TerrainLab.ACTION_STEP)
		if not data.site.captivity.has(str(captive.person_id)) or str(data.site.captivity[str(captive.person_id)].get("prison_id", "")).is_empty():
			released = true
			break
	assert(released, "Walk then four-second release completed through the original job")

	# Position page lists the settlement with an editable 典獄 seat.
	var settlement_org := {}
	for org: Dictionary in controller._office_orgs():
		if str(org.kind) == "settlement": settlement_org = org
	assert(not settlement_org.is_empty() and settlement_org.apply.is_valid() and settlement_org.candidates.has(warden))
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_SETTLEMENT_PRISON_PASS: old head-only record gains vacant 典獄, head acts, player head path, 典獄 owns escort/release, hold table, 10-day 仁厚 release via walk, position page")
	quit(0)
