extends "res://scripts/tests/site_building_ui_test.gd"
## R2 through the real owners: a head dismisses a post holder through the team
## position plan (one +10 event, deduplicated), the next game day is settled by
## the duty-AI tick (G 10 − decay 1 = 9, L 6000 − 500), a move between seats is
## not a dismissal, and the team snapshot with social_state stays valid.

const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")

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
	var holder := team.combat_identity(2)
	var mover := team.combat_identity(3)
	# 文武官 W2: 文官 seats need 文吏; both civil holders are raised first.
	for index: int in [2, 3]: TerrainTestCharacter.PersonSocial.set_civil_role(team.combat_units[index], "clerk")
	var offices := team.team_offices()
	var work := str(offices.duties["team.work"])
	var roster := str(offices.duties["team.roster"])
	assert(team.apply_office_plan(head, int(offices.revision), [{"op": "appoint", "position_id": work, "person_id": holder}, {"op": "appoint", "position_id": roster, "person_id": mover}]).ok)
	offices = team.team_offices()
	assert(team.apply_office_plan(head, int(offices.revision), [{"op": "dismiss", "position_id": work}, {"op": "dismiss", "position_id": roster},
		{"op": "appoint", "position_id": work, "person_id": mover}]).ok, "Dismiss one, move the other to another seat")
	var holder_row: Dictionary = team.combat_units[2]
	var mover_row: Dictionary = team.combat_units[3]
	assert(holder_row.social_state.pending.size() == 1 and str(holder_row.social_state.pending[0].kind) == "dismissed", str(holder_row.get("social_state")))
	assert(not mover_row.has("social_state") or mover_row.social_state.get("pending", []).is_empty(), "A move between seats is not a dismissal")
	DutyAI.reset_site_state()
	DutyAI.review(lab) # day 0: everyone starts now
	data.site.minute = int(data.site.minute) + 1440
	DutyAI.review(lab)
	var status := SiteSocial.status(holder_row, SiteSocial.team_ref(str(data.site.id), team.team_id))
	assert(int(status.G) == 9 and int(status.L) == 5500, "Next day: G 10 − 1, L −50·10: %s" % str(status))
	# §8.1 battle casualties: 1 of the 4-person day cohort killed by a real hit = 25% → +10.
	assert(int(team.social_cohort.day) == 1 and team.social_cohort.base.size() == 4, str(team.social_cohort))
	team.apply_unit_contact(3, {"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
	assert(int(team.combat_units[3].combat_death_minute) == int(data.site.minute))
	data.site.minute = int(data.site.minute) + 1440
	DutyAI.review(lab)
	status = SiteSocial.status(holder_row, SiteSocial.team_ref(str(data.site.id), team.team_id))
	assert(int(status.G) == 18, "Day with 25%% battle deaths: G 9 + 10 − 1 = 18: %s" % str(status))
	data.site.minute = int(data.site.minute) + 1440
	DutyAI.review(lab)
	status = SiteSocial.status(holder_row, SiteSocial.team_ref(str(data.site.id), team.team_id))
	assert(int(status.G) == 17, "Next day without deaths: only decay: %s" % str(status))
	var saved := JSON.parse_string(JSON.stringify(team.capture_combat_state())) as Dictionary
	assert(TerrainArmy.valid_combat_state(saved, data), "Snapshot with social_state validates")
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_SOCIAL_LAB_PASS: plan dismissal records one event, seat move does not, duty-AI tick settles the next day (G 9, L 5500), snapshot validates, 25% battle deaths +10 once")
	quit(0)
