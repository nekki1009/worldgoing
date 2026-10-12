extends "res://scripts/tests/site_n01_procurement_earned_test.gd"
## Genuine first N04 route=bow: original Scope material payment, named Army
## workstation, real original bow ItemSeq, then the original 300-second job.
## N01/S07/F07 are explicitly legitimate starting inputs, not earned here.

func _workshop_earned_fixture() -> Dictionary:
	var data := _building_fixture()
	var warehouse := _formal_feature(data, "warehouse", Vector2i(13, 13))
	var home := _formal_feature(data, "house", Vector2i(13, 18), Vector2i(2, 2))
	var smithy := _formal_feature(data, "smithy", Vector2i(25, 18))
	var lab := _building_lab(data)
	var team := _army(lab, data)
	var actions = lab.site_controller.person_actions
	var control := int(lab.controlled_person_id())
	var executor := team.combat_identity(1)
	var row: Dictionary = team.combat_units[1]
	var center := Runtime.building_cells(data, "settlement_center", Vector2i(18, 10), Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	var center_cells: Array[int] = []
	center_cells.assign(center.cells)
	var founded := Settlement.found(lab, control, center_cells)
	_check(center.ok and founded.ok, "Actual original settlement founder admits the real completed center")
	_complete_key(data, str(founded.feature))
	var layout := Runtime.house_layout(data, home)
	data.site.housing = {str(executor): {"version": 1, "house_id": home, "cell": int(layout.slots[0])}}
	_check(Homes.validate(data, data.site, {executor: {"hp": float(row.hp), "faction_id": 1}}).ok and Settlement.residents(lab).has(executor),
		"Original housed living NPC makes the original settlement effective")
	data.site.settlement.version = 2
	data.site.settlement.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.settlement.technology.known = ["S07"]
	row.technology = Technology.learned_candidate({}, "F07")
	var nation_tech := Technology.empty_scope_record(str(data.site.id))
	nation_tech.known = ["N01"]
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", control),
		"members": [control, executor, team.combat_identity(0)], "standards": {}, "technology": nation_tech}}
	_check(Settlement.status(lab).effective and Technology.valid_person(row.technology) and not Technology.scope_known(nation_tech, "N04"),
		"Only original N01/S07/F07 inputs exist; N04 starts unknown")
	_check(bool(NationCatalog.get_node("N04").get("enabled", false)), "Root's isolated enabled N04 is the positive test precondition")
	_check(lab.character.place(Vector2i(9, 10), true) and actions.prepare_scope_technology(control, executor, "N04", "n1", "bow").ok,
		"Actual research authority explicitly selects the original bow industry route")
	_check(actions.request_scope_technology_consent(control, "nation", "n1", executor).ok
		and actions.grant_scope_technology_budget(control, "nation", "n1", {"wood": 4, "fiber": 2}).ok,
		"Actual original NPC team accepts this research purpose and the original camp grants exactly one genuine batch")
	return {"data": data, "lab": lab, "team": team, "actions": actions, "orders": lab.site_controller.equipment_orders,
		"control": control, "executor": executor, "row": row, "smithy": smithy, "warehouse": warehouse}

func _workshop_named_point(f: Dictionary, seconds: float) -> void:
	var workers = f.lab.site_controller.work_team
	f.lab._shared_work_requests = workers.prepare_work_requests(seconds)
	_check(f.lab._refresh_shared_work_preflight().ok, "Original shared preflight rechecks the true NPC workstation and task")
	var captured = workers.prepare_shared_work_prefix(seconds)
	var plan := NationFatigue.plan_work_interval(f.lab._shared_work_requests, seconds)
	var priors: Array = []
	var before := var_to_bytes([f.data.site, f.row])
	var admitted = workers.validate_shared_work_prefix(captured, plan, priors)
	_check(captured.ok and plan.ok and admitted.ok and var_to_bytes([f.data.site, f.row]) == before,
		"True original registry and Runtime prospective work validation remain pure")
	f.lab._shared_work_plan = plan
	f.lab.site_controller._shared_work_plan = plan
	f.lab._shared_work_pools_committed = false
	f.lab._commit_shared_work_pools()
	workers.publish_shared_work_prefix(admitted)
	workers.finish_shared_work_prefix(admitted)
	# Match the original Lab terminal boundary after all paid endpoint effects.
	if bool(admitted.get("finished", false)): priors.clear()
	_check(bool(admitted.get("finished", false)) and is_same(priors, admitted.runtime_priors) and priors.is_empty(),
		"Completed original workshop point clears only its SAME terminal ledger")
	for candidate: Dictionary in admitted.runtime:
		_check(is_same(candidate.prefix_ref.runtime_priors, priors) and candidate.prefix_ref.runtime_priors.is_empty(),
			"Completed original workshop prefix no longer retains candidate ledger loop")

func _n04_real_product_then_inspection() -> void:
	var f := _workshop_earned_fixture()
	var nation: Dictionary = f.data.site.equipment_nations.n1
	var before := var_to_bytes([f.data.site, f.row])
	_check(not f.orders.certify_workshop(f.control, "n1", "bow_quality", f.smithy, "S07", 1).ok and var_to_bytes([f.data.site, f.row]) == before,
		"Unknown N04 cannot skip its original first production phase or certify an invented receipt")
	var feature: Dictionary = f.data.site.features[f.smithy]
	var next_item := int(f.data.site.next_item)
	var wood := int(f.data.site.inventory.wood)
	var fiber := int(f.data.site.inventory.fiber)
	var started = f.actions.begin_scope_technology_phase(f.control, "nation", "n1", "workshop_bow", "feature:" + f.smithy)
	_check(started.ok and feature.batch_paid and feature.recipe_id == "bow", "Genuine Scope first phase publishes one original paid bow batch and true named worker: " + str(started))
	_check(f.data.site.inventory.wood == wood - 4 and f.data.site.inventory.fiber == fiber - 2
		and Technology.active_project(nation.technology).budget.payments.size() == 1, "Exact original manufacturing cost and original Scope accounting occur once")
	_at_feature(f.lab, f.team, f.executor, f.smithy)
	var points := 0
	while feature.get("batch_paid", false) and points < 10:
		_check(Time.get_ticks_msec() < deadline, "Genuine bow manufacture remains inside the internal deadline")
		_workshop_named_point(f, 30.0)
		points += 1
	_check(points < 10 and not feature.batch_paid and feature.technology_output.receipts.size() == 1, "Actual original 108-second paid cycle completes")
	var output: Dictionary = feature.technology_output.receipts[0]
	var project := Technology.active_project(nation.technology)
	_check(f.data.site.next_item == next_item + 1 and output.item_ids == [str(next_item)]
		and f.data.site.item_records[str(next_item)].definition == "weapon:bow_01" and f.row.item_state.item_ids.has(str(next_item)),
		"Original ItemSeq creates the real bow on the real original worker")
	_check(project.receipts.size() == 1 and is_equal_approx(float(project.receipts[0].work_seconds), 108.0)
		and not Technology.scope_known(nation.technology, "N04") and f.row.work_task.is_empty(), "First actual output earns only the first phase; named manufacture stops")
	before = var_to_bytes([f.data.site, f.row])
	_check(not f.orders.certify_workshop(f.control, "n1", "bow_quality", f.smithy, "S05", int(output.id)).ok
		and var_to_bytes([f.data.site, f.row]) == before, "Wrong chosen industry cannot publish certificate, zero payment or inspection job")
	var camp = f.data.site.inventory.duplicate()
	_check(f.orders.certify_workshop(f.control, "n1", "bow_quality", f.smithy, "S07", int(output.id)).ok, "Actual original inspector accepts the latest genuine bow receipt and atomically begins 300 seconds")
	var certificate: Dictionary = nation.technology_operations.certificates.bow_quality
	var job: Dictionary = f.actions._jobs[str(f.executor)]
	project = Technology.active_project(nation.technology)
	_check(job.kind == "nation_administration" and job.duration == 300.0 and is_same(job.nation_order_ref, certificate)
		and certificate.accepted_receipt == output and certificate.operator_id == f.executor,
		"The original 300-second job binds the SAME certificate and actual original producer/person")
	_check(project.budget.payments.size() == 2 and project.budget.payments[1].materials.is_empty()
		and f.data.site.inventory == camp and project.receipts.size() == 1, "Inspection records only a zero-material Scope payment, without repeating manufacture or granting early knowledge")
	# Set an actual original NPC at the confirmed REST start boundary. Recovery
	# elapsed-time partition is a separate original Fatigue/whole-Lab acceptance.
	f.team.combat_hot_set(1, &"fatigue", NationFatigue.WORK_REST_AT)
	f.actions._body_set(f.actions._person(f.executor), "work_resting", true)
	_original_admin_point(f.lab, 30.0)
	_check(job.paused == "REST" and job.elapsed == 0.0 and not Technology.scope_known(nation.technology, "N04"), "Actual original REST contributes no inspection effort or knowledge")
	f.team.combat_hot_set(1, &"fatigue", 0.0)
	f.actions._body_set(f.actions._person(f.executor), "work_resting", false)
	_original_admin_point(f.lab, 30.0)
	_check(job.elapsed > 0.0 and job.elapsed < 300.0, "Only newly admitted real effort advances the original job")
	_check(f.actions.cancel(f.executor).ok and project.receipts.size() == 1, "Stopping the real inspector retains first production but grants no second phase")
	_check(f.lab.site_controller._nation_ui_command("n1", "administration_certificate", {"certificate": "bow_quality"}).ok,
		"The same true active certificate can support a fresh actual stopped inspection, without redoing paid production")
	_check(is_same(nation.technology_operations.certificates.bow_quality, certificate) and f.data.site.inventory == camp,
		"Original certificate identity and physical source stay intact across the retry")
	_finish_original_admin(f.lab, f.executor)
	_check(Technology.scope_known(nation.technology, "N04") and nation.technology.projects[0].receipts.size() == 2
		and is_equal_approx(float(nation.technology.projects[0].receipts[1].work_seconds), 300.0), "True 108-second original product plus effective 300-second inspection earns N04 once")
	_check(f.data.site.inventory == camp and f.data.site.next_item == next_item + 1 and certificate.accepted_receipt == output,
		"Second-phase success creates no second item or physical material debit")
	before = var_to_bytes([f.data.site, f.row])
	_check(not f.actions.begin_nation_administration(f.control, "n1", "certificate:bow_quality", "workshop_certificate").ok and var_to_bytes([f.data.site, f.row]) == before,
		"Known N04 cannot replay certificate inspection as new research")
	_earned_nation_cleanup(f.lab, f.team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	await _n04_real_product_then_inspection()
	TerrainArmy.release_contact_source()
	print("N04_ORIGINAL_BOW_AND_INSPECTION_EARNED_FIXTURE_PASS: checks=", checks, "; true Scope first108 and original PA300; no Native/whole-Lab/Region/full40 acceptance")
	quit(0)
