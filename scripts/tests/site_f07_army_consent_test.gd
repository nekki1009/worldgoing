extends SceneTree
## A20 uses two true deployed TerrainArmies, their current original offices,
## original Family registration and PA. No manufactured accepted consent.
## This is a direct-owner fixture, not formal TerrainLab/whole-clock proof.
const Research = preload("res://scripts/tests/site_f07_research_test.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")

var checks := 0

func _initialize() -> void:
	call_deferred("run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	assert(condition, message)

func _teams(fixture: Research.Fixture, manual_decider: bool = false) -> Array[int]:
	var positions: Array[Array] = [
		[Vector2i(6, 3), Vector2i(5, 3), Vector2i(7, 3)],
		[Vector2i(6, 5), Vector2i(6, 4), Vector2i(7, 5)]]
	if manual_decider: positions[0] = [Vector2i(5, 3), Vector2i(6, 4), Vector2i(7, 3)]
	var refs: Array = []
	for identity: int in [1, 2]:
		refs.append({"site_id": fixture.terrain.site.id, "person_id": identity, "path": "", "label": "原 Actor", "age_years": -1})
	var participants: Array[int] = []
	for number: int in 2:
		var team := TerrainArmy.new()
		root.add_child(team)
		team.set_process(false)
		team.team_id = number + 1
		team.roster_size = 3
		team.faction_id = 1
		var cells: Array[Vector2i] = []
		cells.assign(positions[number])
		_check(team.deploy_at(fixture.terrain, null, null, cells) and team.enable_combat(false), "True Army deploy and combat/body owner initialization")
		for row: Dictionary in team.combat_units:
			# Same explicit real empty holder initialization as original
			# site_building_runtime_contract_test CrewFixture, not surrogate people.
			row.cargo = {}
			row.item_state = Runtime.new_item_state("person:" + str(row.person_id))
			refs.append({"site_id": fixture.terrain.site.id, "person_id": int(row.person_id), "path": "", "label": "原隊員", "age_years": -1})
		fixture.combat_armies.append(team)
		team.controlled_person_query = fixture.controlled_person_id
		team.person_busy_query = fixture.actions.is_busy
		team.settle_combat_command()
		_check(team.duty_decider("team.work") == team.combat_identity(team.current_commander), "Real vacant-work-seat fallback identifies original commander")
		participants.append(team.combat_identity(1))
	# The manual variant chooses its INITIAL controlled person before any
	# family establishment/request. It never changes control during A20.
	if manual_decider:
		fixture.controlled_id = fixture.combat_armies[0].combat_identity(0)
		fixture.terrain.site.controlled_person_id = fixture.controlled_id
	_check(fixture.site_controller.family_continuity.register_members(refs, true, fixture.controlled_id).ok, "Explicit original owner registers actual local persons")
	_check(fixture.site_controller.family_continuity.appoint_head(fixture.controlled_id, fixture.controlled_id).ok, "Explicit current original person establishes the family office")
	return participants

func _learn(fixture: Research.Fixture, executor: int) -> void:
	fixture.prepare(executor)
	for index: int in 3:
		_check(fixture.actions.begin_technology_trial(fixture.controlled_id, executor).ok, "True formal member's accepted trial begins")
		fixture.step(120.0)
		var settled := fixture.actions.settle_after_contacts()
		_check(settled.size() == 1 and settled[0].ok, "Formal member pays and commits an original bow")
	_check(Technology.learned(fixture.actions._person(executor).body.get("technology", {})), "Army teacher learned through actual own receipts")

func run() -> void:
	_check_npc_flags_and_two_team_consent()
	_check_accepted_consent_rechecks_original_tasks()
	_check_current_manual_decider_and_revoke()
	_check_legal_long_site_reference()
	print("SITE_F07_ARMY_CONSENT_PASS: %d checks; true original Army/Family A20 opening, flag refusal, accepted off/handover and manual off; complete formal UI/shared clock remain separate" % checks)
	TerrainArmy.release_contact_source()
	quit(0)

func _check_npc_flags_and_two_team_consent() -> void:
	for closed_team: int in [0, 1]:
		var f := Research.Fixture.new(false)
		var people := _teams(f)
		var teacher := people[0]
		var student := people[1]
		var control := f.controlled_id
		_learn(f, teacher)
		f.prepare(student, "relearn")
		var blocked_team: TerrainArmy = f.combat_armies[closed_team]
		var captain := blocked_team.combat_identity(blocked_team.formal_commander)
		_check(blocked_team.set_duty_ai_enabled(captain, false).ok, "Original commander sets the original flag off")
		var before := f.commit_snapshot()
		var cells_a := f.combat_armies[0].cells.duplicate()
		var cells_b := f.combat_armies[1].cells.duplicate()
		var refused := f.actions.begin_technology_lesson(control, teacher, student)
		_check(not refused.ok and str(refused.get("code", "")) == "DUTY_AI_OFF", "Either original NPC team's false flag denies new lesson: " + str(refused))
		_check(not f.actions.is_busy(teacher) and not f.actions.is_busy(student) and f.commit_snapshot() == before, "One refused candidate leaves both original people unoccupied and all costs/skills intact")
		_check(f.controlled_id == control and f.combat_armies[0].cells == cells_a and f.combat_armies[1].cells == cells_b, "All actors remain alive and controlled person/cells unchanged")
		_check(not bool(blocked_team.offices.duty_ai), "Research never opens the original flag")
		_check(blocked_team.set_duty_ai_enabled(captain, true).ok, "Original legal head can enable and explicitly resend")
		_check(f.actions.begin_technology_lesson(control, teacher, student).ok, "Both different NPC original deciders accept one named course")
		_check(f.actions.is_busy(teacher) and f.actions.is_busy(student), "Exactly one job maps to both true Army participants")
		var course := f.actions.job_for(teacher)
		_check(course.consents.size() == 2 and int(course.consents[0].team_id) != int(course.consents[1].team_id), "Each participant has its own original team's actual decision")
		_check(not f.actions.begin_technology_lesson(control, teacher, student).ok and f.actions.job_for(teacher) == course, "Resending cannot open or replay another accepted course")
		_check(blocked_team.set_duty_ai_enabled(captain, false).ok, "Close original flag after acceptance")
		var office: Dictionary = blocked_team.team_offices()
		# 文武官 W2: a 文官 seat needs a 文吏 (a 武官 seat an officer); the fixture qualifies its holder first.
		blocked_team.set_civil_role(blocked_team.combat_identity(2), "clerk")
		var changed := blocked_team.apply_office_plan(captain, int(office.revision),
			[{"op": "appoint", "position_id": str(office.duties["team.work"]), "person_id": blocked_team.combat_identity(2)}])
		_check(changed.ok and blocked_team.duty_decider("team.work") == blocked_team.combat_identity(2), "Original legitimate team duty handover")
		_check(f.actions.grant_technology_budget(control, {}, "revoke").ok and f.actions.is_busy(teacher) and f.actions.is_busy(student), "A19 free original grantor revokes trial budget without canceling independent material-free course")
		f.step(300.0)
		var settled := f.actions.settle_after_contacts()
		_check(settled.size() == 1 and settled[0].ok and Technology.learned(f.actions._person(student).body.get("technology", {})), "Scope-valid accepted dual consent survives legitimate handover and flag off")
		_check(f.controlled_id == control and f.bow_count() == 3, "No control change or extra lesson prize")
		f.close()

func _check_accepted_consent_rechecks_original_tasks() -> void:
	var f := Research.Fixture.new(false)
	var people := _teams(f)
	var team: TerrainArmy = f.combat_armies[0]
	f.prepare(people[0])
	_check(f.project().consents.size() == 1 and not f.actions.is_busy(people[0]), "Accepted named request reserves no original person")
	# Negative fixtures alter the ORIGINAL task/supply record observed by the
	# real consent guard, never its decision/result or a replacement validator.
	f.terrain.site["team_supply"] = {str(team.team_id): {"training_order": true}}
	var before := f.commit_snapshot()
	_check(not f.actions.begin_technology_trial(f.controlled_id, people[0]).ok, "Accepted consent rechecks training that began before occupation")
	_check(not f.actions.is_busy(people[0]) and f.commit_snapshot() == before, "Research cannot steal an already accepted original training assignment")
	f.terrain.site.team_supply[str(team.team_id)].training_order = false
	team.combat_units[1].logistics = true
	before = f.commit_snapshot()
	_check(not f.actions.begin_technology_trial(f.controlled_id, people[0]).ok, "Accepted consent rechecks an original logistics assignment")
	_check(not f.actions.is_busy(people[0]) and f.commit_snapshot() == before, "Research cannot override current original logistics role")
	team.combat_units[1].logistics = false
	_check(f.actions.begin_technology_trial(f.controlled_id, people[0]).ok, "Scope-valid accepted consent resumes after original blocking duty ends")
	f.step(120.0)
	team.combat_units[1].logistics = true
	before = f.commit_snapshot()
	var result := f.actions.settle_after_contacts()
	_check(result.size() == 1 and not result[0].ok and f.commit_snapshot() == before and f.bow_count() == 0, "Post-contact original task change wins over ready research completion")
	f.close()

func _check_current_manual_decider_and_revoke() -> void:
	var f := Research.Fixture.new(false)
	var people := _teams(f, true)
	var team: TerrainArmy = f.combat_armies[0]
	var control := f.controlled_id
	_check(team.duty_decider("team.work") == control, "Actual currently controlled original person is the work decider")
	_check(team.set_duty_ai_enabled(control, false).ok, "Manual work decider's original flag is off")
	f.prepare(people[0])
	_check(f.project().consents.size() == 1 and int(f.project().consents[0].decider_id) == control, "Current original controlled decider confirms through actual API with AI off")
	_check(f.actions.begin_technology_trial(control, people[0]).ok, "Manual accepted consent authorizes only this trial")
	f.step(10.0)
	_check(f.actions.revoke_technology_consent(control, people[0]).ok, "True current team work decider explicitly revokes")
	_check(not f.actions.is_busy(people[0]) and f.bow_count() == 0 and f.project().receipts.is_empty(), "Explicit revocation cancels unfinished trial with no product or success")
	_check(f.project().consents[0].status == "revoked" and f.controlled_id == control, "Revocation is persistent on the original purpose and never changes control")
	f.close()

func _check_legal_long_site_reference() -> void:
	var f := Research.Fixture.new(false)
	f.terrain.site.id = "original-site-" + "x".repeat(72)
	var people := _teams(f)
	_learn(f, people[0])
	f.prepare(people[1], "relearn")
	_check(str(f.project().purpose).length() > 64, "Original valid site/person reference makes a valid canonical relearn purpose longer than 64")
	_check(f.actions.begin_technology_lesson(f.controlled_id, people[0], people[1]).ok, "Legal original long site reference cannot self-lock both genuine teams course")
	f.step(300.0)
	var settled := f.actions.settle_after_contacts()
	_check(settled.size() == 1 and settled[0].ok, "Long original reference remains valid through true teaching completion")
	f.close()

