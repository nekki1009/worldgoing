extends "res://scripts/tests/site_technology_targeted_vehicle_test.gd"
## Actual original provider registries, not mocked permission dictionaries.
## Simulated original contact damage is a fixture event, not Native proof.
## Requires Time's WT/PA checked-prefix functions and Runtime candidate pack.

func _checked_controlled_endpoint() -> void:
	var data := _building_fixture()
	var key := _formal_feature(data, "charcoal", Vector2i(20, 20))
	var lab := _building_lab(data)
	var actions = lab.site_controller.person_actions
	var control := lab.controlled_person_id()
	var refs: Array = []
	for identity: int in [control, int(lab.npc.person_id)]:
		refs.append({"site_id": str(data.site.id), "person_id": identity, "path": "", "label": "原人物", "age_years": -1})
	_check(lab.site_controller.family_continuity.register_members(refs, true, control).ok and lab.site_controller.family_continuity.appoint_head(control, control).ok, "Actual Family owner registers the actual original Actors")
	_check(lab.character.place(Vector2i(9, 10), true) and actions.prepare_scope_technology(control, control, "F03").ok, "Original controlled person prepares this real F03 project at camp")
	var family_id := str(data.site.family.family_id)
	_check(actions.request_scope_technology_consent(control, "family", family_id, control).ok and actions.grant_scope_technology_budget(control, "family", family_id, {"wood": 12}).ok, "Original consent and full finite source allowance are established")
	var feature: Dictionary = data.site.features[key]
	_check(lab.character.place(data.cell_from_index(int(feature.entrance)), true) and actions.begin_scope_technology_phase(control, "family", family_id, "charcoal", "feature:" + key).ok, "True stationed actor starts the genuine paid batch")
	var requests = actions.work_requests(600.0)
	# The shared preflight runs against the original WorkTeam interval of the same step; the
	# real main caller prepares it (with the PA requests) before the refresh.
	var wt_requests = lab.site_controller.work_team.prepare_work_requests(600.0, 0.0, requests)
	_check(wt_requests.is_empty(), "No ordinary WorkTeam request competes with the held actor task")
	lab._shared_work_requests.assign(requests)
	_check(lab._refresh_shared_work_preflight().ok and lab._shared_work_requests.size() == 1, "Original final shared preflight admits exactly one held actor task")
	requests = lab._shared_work_requests
	var captured = actions.prepare_shared_work_prefix(requests, 600.0)
	var planned := PersonalFatigue.plan_work_interval(requests, 600.0)
	_check(captured.ok and planned.ok, "Original actor start refs and complete fatigue plan are captured before contact damage")
	var person = actions._person(control)
	var original_hp := float(person.hp)
	actions._body_set(person, "hp", 0.0)
	_check(actions._technology_operator_for_task(actions._jobs[str(control)].work_task, control).is_empty(), "The real current actor is dead and cannot obtain normal endpoint permission")
	var before := var_to_bytes([data.site, lab.character.technology, lab.character.ammo_inventory])
	var admitted = actions.validate_shared_work_prefix(captured, planned, requests)
	var priors: Array = []
	# The original registry now registers the allocation first, then validates the Runtime prefix.
	var registered = actions.prepare_checked_controlled_prefix_allocations(admitted, priors) if admitted.ok else admitted
	var checked = actions.validate_checked_controlled_runtime_prefixes(registered) if registered.ok else registered
	_check(admitted.ok and checked.ok and var_to_bytes([data.site, lab.character.technology, lab.character.ammo_inventory]) == before, "The real registry prepares only the earlier legal prefix without cost, products or progress")
	_check(priors.size() == 1 and is_same(priors[0], checked.checked.runtime[0]), "Sole original provider appends its real Runtime candidate to the same finite sequence")
	var candidate: Dictionary = priors[0]
	var duplicate: Dictionary = candidate.prefix_ref.duplicate(false)
	_check(not Runtime.prepare_checked_work_prefix(data, candidate.task, float(duplicate.applied_productive_seconds), float(duplicate.actual_seconds), duplicate).ok, "A shallow copied prefix is not the original provider's registered reference")
	lab._shared_work_plan = planned
	lab.site_controller._shared_work_plan = planned
	lab._shared_work_pools_committed = false
	lab._commit_shared_work_pools()
	var fatigue := PersonalFatigue.read(lab.character)
	actions.begin_shared_work_prefix_consumption(admitted)
	actions.publish_checked_controlled_prefixes(checked)
	_check(float(feature.production) == float(Runtime.feature_recipe(feature).cycle) and float(feature.tech_batch.work_seconds) > 0.0 and _project(lab).receipts.is_empty(), "True admitted completed progress and actual unweighted effort are saved without fabricating a receipt")
	var retained := var_to_bytes([feature, _project(lab).budget])
	var settled := Runtime.settle_checked_work_prefix(candidate)
	_check(not settled.ok and settled.code == "WAITING" and var_to_bytes([feature, _project(lab).budget]) == retained and _project(lab).receipts.is_empty(), "Current dead endpoint rejects output and learning while preserving fully paid completed work")
	actions.publish_checked_controlled_prefixes(checked)
	lab._commit_shared_work_pools()
	_check(var_to_bytes([feature, _project(lab).budget]) == retained and PersonalFatigue.read(lab.character) == fatigue, "The same original progress and fatigue cannot be published twice")
	actions.finish_checked_controlled_prefixes(checked)
	actions.end_shared_work_prefix_consumption()
	_check(_project(lab).receipts.is_empty() and not Technology.learned(lab.character.technology, "F03"), "Checked prefix alone grants neither a stage nor a skill")
	actions._body_set(actions._person(control), "hp", original_hp)
	_cleanup_fixture(lab, null)
	await process_frame

func _checked_npc_prefix() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var team := _vehicle_team(lab, false)
	var actions = lab.site_controller.person_actions
	var executor := team.combat_identity(1)
	var family_id := _vehicle_family(lab, team, executor)
	var key := str(int(data.site.get("next_vehicle", 1)))
	_check(actions.begin_scope_technology_phase(lab.controlled_person_id(), "family", family_id, "ballista_build", "vehicle:" + key, {"anchor": Vector2i(20, 20), "facing": Vector2i.RIGHT, "team_id": int(team.team_id)}).ok, "Original paid vehicle owns the real named NPC task")
	var vehicle: Dictionary = data.site.vehicles[key]
	var row: Dictionary = team.combat_units[1]
	var task: Dictionary = row.work_task
	team.cells[1] = data.cell_from_index(int(task.work_cell))
	task.cell = int(task.work_cell)
	task.mode = "work"
	var workers = lab.site_controller.work_team
	var requests = workers.prepare_work_requests(30.0)
	lab._shared_work_requests = requests
	_check(lab._refresh_shared_work_preflight().ok, "Original WorkTeam final physical preflight admits this stationed NPC")
	var captured = workers.prepare_shared_work_prefix(30.0)
	var planned := PersonalFatigue.plan_work_interval(lab._shared_work_requests, 30.0)
	_check(captured.ok and planned.ok, "Actual NPC refs and original planner create a qualified prefix")
	var original_hp := float(row.hp)
	team.combat_hot_set(1, &"hp", 0.0)
	var before := var_to_bytes([data.site, row.cargo, row.item_state])
	var priors: Array = []
	var admitted = workers.validate_shared_work_prefix(captured, planned, priors)
	_check(admitted.ok and priors.size() == 1 and var_to_bytes([data.site, row.cargo, row.item_state]) == before, "True dead NPC keeps the same original rows/tasks but pure preparation changes no gameplay state")
	var candidate: Dictionary = admitted.runtime[0]
	_check(not Runtime.prepare_checked_work_prefix(data, task, float(candidate.prefix_ref.applied_productive_seconds) + 1.0, float(candidate.prefix_ref.actual_seconds), candidate.prefix_ref).ok, "Caller cannot inflate the original applied prefix seconds")
	lab._shared_work_plan = planned
	lab.site_controller._shared_work_plan = planned
	lab._shared_work_pools_committed = false
	lab._commit_shared_work_pools()
	var published = workers.publish_shared_work_prefix(admitted)
	_check(float(vehicle.build.progress) == float(candidate.progress) and float(vehicle.tech_batch.work_seconds) == float(candidate.prefix_ref.productive_seconds) and float(published.handled_seconds.get(executor, -1.0)) == float(candidate.prefix_ref.actual_seconds), "Actual WT prefix writes progress once and only the named original person's unweighted contribution")
	var retained := var_to_bytes(vehicle)
	workers.publish_shared_work_prefix(admitted)
	_check(var_to_bytes(vehicle) == retained and _project(lab).receipts.is_empty(), "Repeated original WT publication has no extra physical work or research receipt")
	workers.finish_shared_work_prefix(admitted)
	team.combat_hot_set(1, &"hp", original_hp)
	_cleanup_fixture(lab, team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 90000
	await _checked_controlled_endpoint()
	await _checked_npc_prefix()
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_CHECKED_WORK_PREFIX_PASS: %d checks; true Actor/Army/Family/provider/planner refs, pure candidates, exact prefix effort, current endpoint rejection; Native contacts/frame/save/full40 excluded" % checks)
	quit(0)
