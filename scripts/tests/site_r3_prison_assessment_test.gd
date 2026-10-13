extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## Genuine accepted game steps cross the 10-day threshold; no clock jump or
## fabricated release. Nation AI remains off so assessment is isolated.
const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")
const Personality = preload("res://scripts/terrain_lab/person_personality.gd")

func _run() -> void:
	deadline = Time.get_ticks_msec() + 300000
	var fixture := _r3_prison_fixture(10000)
	if not _r3_check(not _r3_failed and not fixture.is_empty(), "Inherited R3 fixture failed"): return
	var lab: TerrainLab = fixture.lab
	var data: TerrainData = fixture.data
	var controller: SiteController = fixture.controller
	var player: TerrainTestCharacter = fixture.player
	var home: TerrainArmy = fixture.home
	var enemy: TerrainArmy = fixture.enemy
	var target := int(fixture.target)
	var requester := int(fixture.requester)
	var keeper := int(fixture.keeper)
	var original_row: Dictionary = enemy.combat_units[enemy.index_for_identity(target)]
	var relation: Dictionary = data.site.captivity[str(target)]
	var hold_from := float(relation.admitted_at_game_seconds)
	var offices := Settlement.offices(lab)
	var appointed := Settlement.apply_office_plan(lab, requester, int(offices.revision), [{"op": "appoint", "position_id": str(offices.duties["settlement.prison"]), "person_id": keeper}])
	if not _r3_check(appointed.ok): return
	var keeper_index := home.index_for_identity(keeper)
	home.combat_units[keeper_index].personality = Personality.neutral()
	home.combat_units[keeper_index].personality.mercy = 100
	var policy := Settlement.set_duty_ai_enabled(lab, requester, true)
	if not _r3_check(policy.ok): return
	if not _r3_check(not bool(data.site.equipment_nations.n1.offices.duty_ai), "Country consent remains disabled, no other side can supply it"): return
	# Authored initial finite food remains on the original owners; no money or
	# automatic refill is introduced. The actual time driver settles every step.
	if not _r3_check(is_same(player.ammo_inventory, data.site.manual.cargo), "Actor cargo remains on the original manual owner"): return
	player.ammo_inventory.grain = 20
	for entry: Dictionary in data.site.team_supply.values(): entry.inventory.grain = 20
	lab.simulation_speed = 60.0
	var now := Runtime.now(data) * 60.0
	var step_limit := ceili(10.0 * 86400.0 / (TerrainLab.ACTION_STEP * 60.0 * lab.simulation_speed)) + 3600
	for step: int in range(step_limit):
		if now - hold_from >= 10.0 * 86400.0: break
		if not _r3_check(true): return
		if Time.get_ticks_msec() > deadline:
			_r3_check(false, "Original assessment 300-second wall deadline exhausted")
			return
		var previous := now
		lab._advance_action_time(TerrainLab.ACTION_STEP)
		if not _r3_check(true): return
		now = Runtime.now(data) * 60.0
		if not _r3_check(now >= previous, "Original time driver cannot run backwards"): return
		if step % 120 == 0:
			await process_frame
			if not _r3_check(true): return
	lab.simulation_speed = 1.0
	if not _r3_check(now - hold_from >= 10.0 * 86400.0, "Original time owner crossed the real 10-day boundary"): return
	if not _r3_check(data.site.captivity.has(str(target)), "No automatic expiry release of admitted GD row"): return
	# One authored social input isolates unwillingness from incidental food and
	# personnel events; it does not alter time, custody episode or its outcome.
	var packet := Social.state_of(original_row)
	Social.relation(packet, relation.loyal_org).L = 10000
	var willingness := Social.surrender_willingness(original_row, relation, int(data.site.minute))
	if not _r3_check(not bool(willingness.willing), str(willingness)): return
	var assessment := DutyAI.review_prison(lab, requester)
	if not _r3_check(not bool(assessment.get("ok", false))): return
	if not _r3_check(data.site.captivity.has(str(target)) and not controller.captive_escort.is_release_walking(keeper), "Unwilling expired captive stays held; no walk-to-free queued"): return
	if not _r3_check(DutyAI.settlement_traces[-1].issued.code == "WAIT"): return
	# The real controlled head resumes prison duty by a lawful personnel plan;
	# explicit human release still uses the unchanged four-action-second job.
	offices = Settlement.offices(lab)
	var dismissed := Settlement.apply_office_plan(lab, requester, int(offices.revision), [{"op": "dismiss", "position_id": str(offices.duties["settlement.prison"])}])
	if not _r3_check(dismissed.ok): return
	var slot := controller.person_actions.prison_slot(target)
	if not _r3_check(slot.ok): return
	var placed := player.place(slot.slot.contact_cell, true)
	if not _r3_check(placed): return
	var released := controller.person_actions.begin_prison_release(requester, target, requester)
	if not _r3_check(released.ok, str(released)): return
	if not _r3_check(data.site.captivity.has(str(target)), "Starting manual release does not clear custody"): return
	for step: int in range(600):
		if not _r3_check(true): return
		if Time.get_ticks_msec() > deadline:
			_r3_check(false, "Original manual release exceeded 300-second deadline")
			return
		lab._advance_action_time(TerrainLab.ACTION_STEP)
		if not _r3_check(true): return
		if not data.site.captivity.has(str(target)): break
	if not _r3_check(not data.site.captivity.has(str(target)), "Original four-second human release completes"): return
	if not _r3_check(is_same(enemy.combat_units[enemy.index_for_identity(target)], original_row)): return
	lab.free()
	TerrainArmy.release_contact_source()
	if not _r3_check(true): return
	print("SITE_R3_PRISON_ASSESSMENT_PASS: real ten-day boundary, unwilling GD captive stays held, country AI-off consent retained, pending visible, lawful original human four-second release remains")
	quit(0)
