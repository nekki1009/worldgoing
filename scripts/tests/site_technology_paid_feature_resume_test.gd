extends "res://scripts/tests/site_technology_nation_material_test.gd"
## Original held Actor job and original Army/WT task, genuine feature/zone and
## paid source. The controlled branch uses the real shared preflight, planner,
## original complete-pool publisher and PA allocation. This local adapter does
## not assert full TerrainLab frame/Region clock, travel, UI or save/load IO.
const PersonalFatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")

func _has_actor_work_task(actor: TerrainTestCharacter) -> bool:
	for property: Dictionary in actor.get_property_list():
		if property.name == "work_task": return true
	return false

func _controlled_step(lab: TerrainLab, seconds: float) -> Dictionary:
	var actions = lab.site_controller.person_actions
	var requests = actions.work_requests(seconds)
	_check(requests.size() == 1 and requests[0].provider == "person_actions", "Original PA contributes the one actual held feature job")
	# The shared preflight belongs to a prepared step: the WorkTeam prepares its own (here empty) requests first, as
	# TerrainLab._collect_original_shared_work_requests does.
	var team_requests: Array = lab.site_controller.work_team.prepare_work_requests(seconds)
	lab._shared_work_requests = requests + team_requests
	var refreshed = lab._refresh_shared_work_preflight()
	_check(refreshed.ok and str(lab._shared_work_requests[0].get("paused", "")).is_empty(), "Original shared preflight admits this SAME PA task and its actual final water context: %s / %s" % [str(refreshed), str(lab._shared_work_requests[0].get("paused", ""))])
	var planned = PersonalFatigue.plan_work_interval(lab._shared_work_requests, seconds)
	_check(planned.ok, "The original complete-pool planner accepts actual effort, without a surrogate body")
	lab._shared_work_plan = planned
	lab.site_controller._shared_work_plan = planned
	lab._shared_work_pools_committed = false
	lab._commit_shared_work_pools()
	var before_second_pool = PersonalFatigue.read(lab.character)
	lab._commit_shared_work_pools()
	_check(PersonalFatigue.read(lab.character) == before_second_pool, "The original shared pool publisher commits only once")
	var jobs: Dictionary = planned.jobs.get("person_actions", {})
	var handled = actions.advance(seconds, {"jobs": jobs})
	var after = var_to_bytes([lab.terrain.site, lab.character.technology, lab.character.fatigue, lab.character.ammo_inventory])
	actions.advance(seconds, {"jobs": jobs})
	_check(var_to_bytes([lab.terrain.site, lab.character.technology, lab.character.fatigue, lab.character.ammo_inventory]) == after, "The SAME original admitted allocation cannot be consumed twice")
	return {"plan": planned, "handled": handled.handled_seconds}

func _controlled_resume() -> void:
	var data = _building_fixture()
	var key = _formal_feature(data, "charcoal", Vector2i(20, 20))
	var lab = _building_lab(data)
	var team = _army(lab, data)
	var actions = lab.site_controller.person_actions
	var control = lab.controlled_person_id()
	var refs: Array = []
	for identity: int in [control, int(lab.npc.person_id)]:
		refs.append({"site_id": str(data.site.id), "person_id": identity, "path": "", "label": "真原人物", "age_years": -1})
	_check(lab.site_controller.family_continuity.register_members(refs, true, control).ok \
		and lab.site_controller.family_continuity.appoint_head(control, control).ok, "Original registry and duty explicitly establish the family; no test ID window supplies authority")
	_check(lab.character.place(Vector2i(9, 10), true), "Actual Actor reaches the camp material grant contact")
	var prepared_f03: Dictionary = actions.prepare_scope_technology(control, control, "F03")
	_check(prepared_f03.ok, "Original controlled member prepares F03: " + str(prepared_f03))
	var family_id = str(data.site.family.family_id)
	_check(actions.request_scope_technology_consent(control, "family", family_id, control).ok \
		and actions.grant_scope_technology_budget(control, "family", family_id, {"wood": 12}).ok, "Actual original person accepts the purpose and grants the finite full three-batch budget")
	var feature: Dictionary = data.site.features[key]
	var target = "feature:" + key
	var before = var_to_bytes([data.site, lab.character.technology, lab.character.fatigue, actions._jobs])
	var refused = actions.begin_scope_technology_phase(control, "family", family_id, "charcoal", target)
	_check(not refused.ok and refused.code == "UNREACHABLE" and var_to_bytes([data.site, lab.character.technology, lab.character.fatigue, actions._jobs]) == before,
		"Actor away from the real station fails before payment, attempt, zone/job mutation or fatigue")
	var station = data.cell_from_index(int(feature.entrance))
	_check(lab.character.place(station, true), "The actual Actor walks/stands at the original computed entrance fixture")
	var inventory = data.site.inventory.duplicate()
	var started = actions.begin_scope_technology_phase(control, "family", family_id, "charcoal", target)
	_check(started.ok and actions.is_busy(control) and actions.save_guard().code == "BUSY", "One genuine controlled job is published with the real paid batch and blocks save")
	var token: Dictionary = feature.tech_trial
	var job: Dictionary = actions._jobs[str(control)]
	var zone: Dictionary = data.site.zones[int(job.work_task.zone)]
	_check(job.kind == "technology_feature" and is_same(job.feature_ref, feature) and is_same(job.zone_ref, zone) \
		and is_same(job.operation_selector.token, token) and not _has_actor_work_task(lab.character),
		"Original PA owns the SAME held task/feature/zone/token; no Actor work-task schema is added")
	_check(int(data.site.inventory.wood) == int(inventory.wood) - 4 and _project(lab).budget.payments.size() == 1, "Real full input is paid once")
	var state_before_timer = var_to_bytes([feature, lab.character.technology, lab.character.ammo_inventory, lab.character.fatigue])
	actions.advance(600.0, {})
	actions.settle_after_contacts()
	_check(var_to_bytes([feature, lab.character.technology, lab.character.ammo_inventory, lab.character.fatigue]) == state_before_timer,
		"No canonical collector allocation means no Runtime progress, timer product, knowledge or fatigue")
	var step = _controlled_step(lab, 60.0)
	_check(is_equal_approx(float(feature.production), 1.0) and is_equal_approx(float(feature.tech_batch.work_seconds), 60.0) \
		and float(step.handled.get(control, -1.0)) == 60.0 and is_equal_approx(PersonalFatigue.read(lab.character), 60.0 * PersonalFatigue.WORK_RATE),
		"Only original Runtime advances real production; original effort and fatigue are charged once")
	var payment_bytes = var_to_bytes(_project(lab).budget)
	var attempt = int(_project(lab).next_attempt)
	var progress = float(feature.production)
	_check(actions.cancel(control).ok and not actions.is_busy(control), "Original PA cancellation releases the actual held job, preserving the paid target")
	_check(lab.character.place(Vector2i(9, 10), true), "Actual Actor leaves the work station after cancellation")
	before = var_to_bytes([data.site, actions._jobs, lab.character.technology, lab.character.fatigue])
	refused = actions.begin_scope_technology_phase(control, "family", family_id, "charcoal", target)
	_check(not refused.ok and refused.code == "UNREACHABLE" and var_to_bytes([data.site, actions._jobs, lab.character.technology, lab.character.fatigue]) == before,
		"Paid resume still requires the real controlled station and cannot mutate anything on rejection")
	_check(lab.character.place(station, true), "The actual Actor returns to the SAME original station")
	before = var_to_bytes([data.site, actions._jobs, lab.character.technology])
	var proposed = _token(lab, control, target)
	var preview = Runtime.begin_technology_operation(data, proposed, true)
	_check(preview.ok and preview.resumed and var_to_bytes([data.site, actions._jobs, lab.character.technology]) == before, "Canceled paid resume previews the actual new job without publishing it")
	started = actions.begin_scope_technology_phase(control, "family", family_id, "charcoal", target)
	job = actions._jobs.get(str(control), {})
	_check(started.ok and started.resumed and not bool(started.already_working) and actions.is_busy(control) \
		and is_same(feature.tech_trial, token) and is_same(job.zone_ref, zone) and is_same(job.feature_ref, feature) \
		and float(feature.production) == progress and int(_project(lab).next_attempt) == attempt and var_to_bytes(_project(lab).budget) == payment_bytes,
		"Canceled paid resume actually republishes the original job, with SAME zone/token, no stock/attempt/credit/payment reset")
	before = var_to_bytes([data.site, actions._jobs, lab.character.technology])
	started = actions.begin_scope_technology_phase(control, "family", family_id, "charcoal", target)
	_check(started.ok and started.already_working and var_to_bytes([data.site, actions._jobs, lab.character.technology]) == before, "Already-existing true task resumes as a byte-equivalent no-op")
	_check(actions.stop_scope_technology(control, "family", family_id).ok and not actions.is_busy(control) and actions._jobs.is_empty(), "Original Scope stop immediately releases its SAME controlled job")
	_check(actions.prepare_scope_technology(control, control, "F03").ok, "Original project preparation reactivates the SAME retained purpose")
	started = actions.begin_scope_technology_phase(control, "family", family_id, "charcoal", target)
	_check(started.ok and actions.is_busy(control) and is_same(feature.tech_trial, token) and is_same(actions._jobs[str(control)].zone_ref, zone), "Scope stop then resume rebuilds a real task at the SAME original inactive zone")
	_controlled_step(lab, 540.0)
	_check(not actions.is_busy(control) and not feature.has("tech_trial") and not feature.has("tech_batch") \
		and _project(lab).receipts.size() == 1 and _project(lab).budget.payments.size() == 1 \
		and int(lab.character.ammo_inventory.get("charcoal", 0)) == 2 and not Technology.learned(lab.character.technology, "F03"),
		"The one real paid output commits one personal phase and stops the named job; unfinished F03 stays unlearned")
	for _batch: int in 2:
		started = actions.begin_scope_technology_phase(control, "family", family_id, "charcoal", target)
		_check(started.ok and actions.is_busy(control), "The next original phase explicitly starts its own genuinely paid batch")
		_controlled_step(lab, 600.0)
	_check(Technology.scope_known(data.site.family.technology, "F03") and Technology.learned(lab.character.technology, "F03") \
		and data.site.family.technology.projects[0].receipts.size() == 3 and data.site.family.technology.projects[0].budget.payments.size() == 3 \
		and int(data.site.inventory.wood) == int(inventory.wood) - 12 and int(lab.character.ammo_inventory.get("charcoal", 0)) == 6 \
		and not actions.is_busy(control), "All three true batches earn F03 once; original finite full material budget and real outputs balance")
	_cleanup_fixture(lab, team)
	await process_frame

func _npc_paid_resume() -> void:
	var fixture = _nation_fixture(["N01", "N02"])
	var data: TerrainData = fixture.data
	var lab: TerrainLab = fixture.lab
	var actions: SitePersonActions = fixture.actions
	var control = int(fixture.control)
	var executor = int(fixture.executor)
	var team: TerrainArmy = fixture.team
	var row: Dictionary = fixture.row
	_check(actions.prepare_scope_technology(control, executor, "N06", "n1").ok \
		and actions.request_scope_technology_consent(control, "nation", "n1", executor).ok, "The actual NPC accepts this true N06 research purpose")
	var registered = fixture.orders.request_public_work_order(control, "n1", "house", str(fixture.labor.order_id), [executor], str(fixture.warehouse))
	_check(registered.ok, "The original national duty records the real finite public house order")
	_fund(lab, str(registered.order_id), {"wood": 8, "stone": 4}, str(fixture.warehouse))
	var options = {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	var geometry = Runtime.building_cells(data, "house", Vector2i(28, 20), Vector2i(2, 2), options)
	var cells: Array[int] = []
	cells.assign(geometry.cells)
	var target = "feature:" + str(int(data.site.next_feature))
	_check(actions.begin_scope_technology_phase(control, "nation", "n1", "house_build", target, {"cells": cells, "options": options}).ok, "The true private source and original named WT assignment begin together")
	var key = target.trim_prefix("feature:")
	var feature: Dictionary = data.site.features[key]
	var token: Dictionary = feature.tech_trial
	var task = _at_feature(lab, team, executor, key)
	Runtime._feature_work(data, key, 1.0, Callable(), Callable(), task, row.cargo, Runtime.CARRY_CAPACITY, 1, executor)
	var progress = float(feature.progress)
	var project = Technology.active_project(data.site.equipment_nations.n1.technology)
	var paid = var_to_bytes(project.budget)
	var attempt = int(project.next_attempt)
	var camp = data.site.inventory.duplicate()
	_check(actions.stop_scope_technology(control, "nation", "n1").ok and not fixture.controller.work_team.is_assigned(executor) and row.work_task.is_empty(), "Original Scope stop cancels the actual NPC WT task")
	_check(Runtime.cancel_feature(data, str(fixture.warehouse), fixture.controller.reserves_cell, 1).ok, "Original demolition legally removes the consumed empty Warehouse")
	_check(actions.prepare_scope_technology(control, executor, "N06", "n1").ok, "The true national project reactivates its retained purpose without recreating a demolished source")
	var started = actions.begin_scope_technology_phase(control, "nation", "n1", "house_build", target)
	project = Technology.active_project(data.site.equipment_nations.n1.technology)
	_check(started.ok and started.resumed and not bool(started.already_working) and fixture.controller.work_team.is_assigned(executor) \
		and row.work_task.target == target and row.work_task.version == 3 and is_same(feature.tech_trial, token) \
		and float(feature.progress) == progress and int(project.next_attempt) == attempt and var_to_bytes(project.budget) == paid and data.site.inventory == camp,
		"Canceled NPC paid resume republishes a real original WT task after source demolition, preserving cost/attempt/progress")
	var before = _state_bytes(data, row)
	started = actions.begin_scope_technology_phase(control, "nation", "n1", "house_build", target)
	_check(started.ok and started.already_working and _state_bytes(data, row) == before, "A true approaching NPC named task is preserved as no-op")
	_finish_feature(lab, team, executor, key, float(feature.work) - float(feature.progress))
	_check(Technology.scope_known(data.site.equipment_nations.n1.technology, "N06") \
		and not fixture.controller.work_team.is_assigned(executor) and data.site.equipment_nations.n1.technology.projects[0].budget.payments.size() == 1,
		"Resumed true WT work reaches the original completed house and one research receipt without double payment")
	_cleanup_fixture(lab, team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 90000
	await _controlled_resume()
	await _npc_paid_resume()
	print("TECHNOLOGY_PAID_FEATURE_RESUME_PASS checks=", checks)
	quit()
