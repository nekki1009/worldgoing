extends SceneTree
## Real original Family/Actor authority; no forged duty decider or consent.
const Research = preload("res://scripts/tests/site_f07_research_test.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")

var checks := 0

func _initialize() -> void:
	call_deferred("run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	assert(condition, message)

func _trial(fixture: Research.Fixture, identity: int) -> void:
	var started := fixture.actions.begin_technology_trial(1, identity)
	_check(started.ok, "Genuine authorized trial: " + str(started))
	fixture.step(120.0)
	var settled := fixture.actions.settle_after_contacts()
	_check(settled.size() == 1 and settled[0].ok, "Genuine paid trial transaction")

func run() -> void:
	_check_budget_command_admission()
	_check_budget_regrant_revoke_and_unrelated_jobs()
	_check_accepted_family_handover_and_distinct_material_rights()
	print("SITE_F07_AUTHORITY_PASS: %d checks; original Family authority, finite camp budgets, revocation and accepted handover; A20 true Army integration remains its own fixture" % checks)
	quit(0)

func _check_budget_command_admission() -> void:
	var f := Research.Fixture.new()
	var before := f.commit_snapshot()
	_check(not f.actions.prepare_technology(2, 2).ok and f.commit_snapshot() == before, "Only truly controlled family research decider prepares")
	_check(f.actions.prepare_technology(1, 2).ok, "Preparation occupies no original person")
	before = f.commit_snapshot()
	_check(f.actions.begin_technology_trial(1, 2).get("code", "") == "NO_BUDGET", "A02 material authority is distinct from choosing research")
	_check(f.commit_snapshot() == before and not f.actions.is_busy(2), "Rejected unbudgeted trial spends and occupies nothing")
	for cap: Dictionary in [{"wood": 12, "fiber": 6, "iron": 1}, {"wood": -1, "fiber": 6},
			{"wood": 1.5, "fiber": 6}, {"wood": 1000001, "fiber": 6},
			{"wood": "12", "fiber": 6}, {"wood": NAN, "fiber": 6}]:
		_check(not f.actions.grant_technology_budget(1, cap).ok and f.commit_snapshot() == before, "A19 reject malformed or nonfinite total cap without mutation")
	_check(not f.actions.grant_technology_budget(2, {"wood": 12, "fiber": 6}).ok and f.commit_snapshot() == before, "A19 physically eligible NPC cannot impersonate the manual grantor")
	_check(f.actions.grant_technology_budget(1, {"wood": 12, "fiber": 6}).ok, "True controlled camp user grants explicit bounded use")
	_check(f.actions.save_guard().ok and f.project().budget.spent == {"wood": 0, "fiber": 0}, "Choose and grant do not self-lock, reserve or spend")
	f.close()
	for blocked: String in ["pause", "combat", "ko", "captive", "away", "action_lock", "queued_npc_move", "ordinary_busy", "holder"]:
		f = Research.Fixture.new()
		f.prepare(2)
		match blocked:
			"pause": f.terrain.site.paused = true
			"combat": f.terrain.site.combat_left = 1.0
			"ko": f.character.knockout_left = 1.0
			"captive": f.character.captive = true
			"away": f.character.terrain_cell = Vector2i(1, 1)
			"action_lock": f.character.action_time = 1.0
			"queued_npc_move":
				# This is the existing controlled-NPC camp predicate, not a free
				# control transition acceptance claim.
				f.controlled_id = 2
				f.terrain.site.controlled_person_id = 2
				f.npc.command = 1
			"ordinary_busy": _check(f.actions.begin_ranged_craft(1, "arrow").ok, "Actual ordinary job occupies grantor")
			"holder": f.character.item_state = {}
		before = f.commit_snapshot()
		var job := f.actions.job_for(1)
		for operation: String in ["grant", "increase", "revoke"]:
			_check(not f.actions.grant_technology_budget(f.controlled_id, {"wood": 20, "fiber": 10}, operation).ok, "A19 shared camp admission rejects " + blocked + "/" + operation)
			_check(f.commit_snapshot() == before and f.actions.job_for(1) == job, "Rejected material operation cannot change spend or current job")
		f.close()

func _check_budget_regrant_revoke_and_unrelated_jobs() -> void:
	var f := Research.Fixture.new()
	f.prepare(2)
	_trial(f, 2)
	_trial(f, 2)
	var purpose := str(f.project().purpose)
	var before := f.commit_snapshot()
	_check(not f.actions.grant_technology_budget(1, {"wood": 4, "fiber": 2}, "increase").ok and f.commit_snapshot() == before, "Cap cannot shrink below historical spend")
	_check(f.actions.begin_technology_trial(1, 2).ok, "Third trial begins without spending in advance")
	f.step(20.0)
	_check(f.actions.grant_technology_budget(1, {}, "revoke").ok, "Free genuine source grantor may explicitly revoke another maker's unfinished trial")
	_check(not f.actions.is_busy(2) and f.project().receipts.size() == 2 and f.project().budget.spent == {"wood": 8, "fiber": 4}, "Revocation frees only the unfinished trial and preserves paid goods/evidence")
	_check(f.bow_count() == 2 and not Technology.learned(f.npc.technology), "Canceled third attempt grants no knowledge")
	_check(f.actions.grant_technology_budget(1, {"wood": 12, "fiber": 6}).ok, "Explicit regrant can restore the same purpose")
	_check(str(f.project().purpose) == purpose and f.project().budget.spent == {"wood": 8, "fiber": 4}, "Regrant does not mint fresh budget or reset its spend")
	_trial(f, 2)
	_check(f.bow_count() == 3 and Technology.learned(f.npc.technology), "One remaining true success completes the same person's research")
	f.close()

	f = Research.Fixture.new()
	f.prepare(2)
	_check(f.actions.begin_ranged_craft(2, "arrow").ok, "Unrelated ordinary work is an actual original job")
	before = f.commit_snapshot()
	var ordinary := f.actions.job_for(2)
	_check(not f.actions.stop_technology(1, 2).ok and f.actions.job_for(2) == ordinary, "Technology stop cannot cancel an ordinary arrow job")
	_check(f.commit_snapshot() == before, "Refused technology stop does not edit project state")
	# job_for() deep-copies the job with its live site_state; the revoke itself changes
	# that site, so compare the ordinary job without it.
	var ordinary_job := ordinary.duplicate()
	ordinary_job.erase("site_state")
	var revoked := f.actions.grant_technology_budget(1, {}, "revoke")
	var after_job := f.actions.job_for(2)
	after_job.erase("site_state")
	_check(revoked.ok and f.actions.is_busy(2) and after_job == ordinary_job, "Budget revocation cancels only related technology trials")
	f.close()

func _check_accepted_family_handover_and_distinct_material_rights() -> void:
	var f := Research.Fixture.new()
	f.prepare()
	_trial(f, 1)
	_trial(f, 1)
	_check(f.actions.begin_technology_trial(1, 1).ok, "A16 genuine third trial accepted by old decider")
	var office: Dictionary = f.terrain.site.family.offices
	var seat := str(office.duties["family.research"])
	var moved := f.site_controller.family_continuity.apply_office_plan(1, int(office.revision),
		[{"op": "appoint", "position_id": seat, "person_id": 2}])
	_check(moved.ok, "Legitimate original Family personnel entry hands research to another local person")
	_check(f.actions.technology_query().research_decider == 2, "API derives the current original decider")
	var job := f.actions.job_for(1)
	_check(not f.actions.stop_technology(1, 1).ok and f.actions.job_for(1) == job, "Old research duty cannot cancel the accepted job")
	f.step(120.0)
	var settled := f.actions.settle_after_contacts()
	_check(settled.size() == 1 and settled[0].ok and Technology.learned(f.character.technology), "Accepted scope-valid trial survives legal duty handover")
	f.close()

	f = Research.Fixture.new()
	f.prepare(2)
	office = f.terrain.site.family.offices
	seat = str(office.duties["family.research"])
	_check(f.site_controller.family_continuity.apply_office_plan(1, int(office.revision),
		[{"op": "appoint", "position_id": seat, "person_id": 2}]).ok, "A19 genuine research handover")
	var before := f.commit_snapshot()
	_check(not f.actions.begin_technology_trial(1, 2).ok and f.commit_snapshot() == before, "Previous decider cannot issue new research")
	_check(f.actions.grant_technology_budget(1, {"wood": 20, "fiber": 10}, "increase").ok, "Still-controlled qualified camp user keeps independent material increase right")
	_check(f.project().budget.cap == {"wood": 20, "fiber": 10} and f.project().budget.spent == {"wood": 0, "fiber": 0}, "Material increase is the same authorization, not research approval")
	_check(f.actions.grant_technology_budget(1, {}, "revoke").ok, "Independent source right can revoke after research handover")
	f.close()

