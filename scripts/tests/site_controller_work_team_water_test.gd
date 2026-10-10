extends "res://scripts/tests/site_technology_controller_prefix_test.gd"
## True TerrainLab/Controller/Actor/Army/farm/well owners. The finite external
## ledger's MATERIALS verdict is explicit fixture input; no mocked Controller
## request, substituted task/body, new timer or full Native/Region claim.

func _run() -> void:
	deadline = Time.get_ticks_msec() + 90000
	var data: TerrainData = _building_fixture()
	var left: String = _formal_feature(data, "farm", Vector2i(10, 40), Vector2i(6, 6))
	var right: String = _formal_feature(data, "farm", Vector2i(16, 40), Vector2i(6, 6))
	_formal_feature(data, "well", Vector2i(14, 38))
	_check(Runtime.operate_feature(data, left).ok and Runtime.operate_feature(data, right).ok, "True original production owners enable both real six-by-six farms")
	var left_slots: Array = Runtime.feature_work_slots(data, data.site.features[left])
	var right_slots: Array = Runtime.feature_work_slots(data, data.site.features[right])
	_check(left_slots.size() == 1 and right_slots.size() == 1, "Both original farms have one real service station")
	var lab: TerrainLab = _building_lab(data)
	var controller: SiteController = lab.site_controller
	var team: TerrainArmy = _army(lab, data)
	var crew := controller.work_team
	var executor: int = team.combat_identity(1)
	_check(crew.assign(team, [executor], team.duty_decider("team.work")).ok, "Original captain assigns this true same Army member")
	team.cells[1] = data.cell_from_index(int(right_slots[0].cell))
	var row: Dictionary = team.combat_units[1]
	Runtime.assign_task(data, Runtime.ok("True original fixture fixes the actual right farm slot", {"target": "feature:" + right, "action": "operate", "work_slot": 0, "cell": int(right_slots[0].cell), "zone": -1}), row.work_task)
	row.work_task.cell = int(right_slots[0].cell)
	row.work_task.mode = "work"
	_check(lab.npc.place(data.cell_from_index(int(left_slots[0].cell)), true), "Original camp Actor stands at the distinct actual left farm station")
	Runtime.assign_task(data, Runtime.ok("True original fixture fixes the actual camp farm slot", {"target": "feature:" + left, "action": "operate", "work_slot": 0, "cell": int(left_slots[0].cell), "zone": -1}))
	data.site.worker.cell = int(left_slots[0].cell)
	data.site.worker.mode = "work"
	data.site.worker_enabled = true
	lab.npc.issue_command(TerrainTestNPC.Command.STOP)
	controller._shared_worker_inputs = controller._prepare_original_work_inputs()
	var requests: Array = controller.prepare_shared_owner_work_requests(1.0)
	requests.append_array(crew.prepare_work_requests(1.0, 1.0 / 1800.0))
	requests = crew.apply_shared_preflight(requests)
	var camp: Dictionary = {}
	var denied: Dictionary = {}
	for request: Dictionary in requests:
		if str(request.provider) == "runtime" and str(request.key) == "worker": camp = request
		elif str(request.provider) == "work_team" and str(request.key) == "feature:" + right + ":operate": denied = request
	_check(not camp.is_empty() and not denied.is_empty() and camp.productive_kind == "sum" and camp.participants.size() == 1 and is_same(camp.task, data.site.worker) and is_same(camp.participants[0].body, lab.npc), "Only true Controller/WorkTeam sources create these same held demands and original bodies")
	var initial_weight: float = float(camp.participants[0].progress_multiplier)
	_check(initial_weight > 0.0 and initial_weight < 36.0 and int(Runtime.feature_production_info(data, left).workers) == 1 and int(Runtime.feature_production_info(data, right).workers) == 1, "Camp starts with the true scarce water shared by both original accepted stations")
	var inventory: Dictionary = data.site.inventory.duplicate(true)
	var camp_task: Dictionary = data.site.worker
	var army_task: Dictionary = row.work_task
	var npc_fatigue: float = PersonalFatigue.read(lab.npc)
	denied.paused = "MATERIALS" # Explicit original all-provider admission verdict.
	var refreshed: Array = crew.apply_shared_preflight(requests)
	_check(is_same(refreshed[0], requests[0]) and is_same(camp.task, camp_task) and is_same(row.work_task, army_task) and str(denied.paused) == "MATERIALS", "Original reprojection retains every held request/task and never revives the denied group")
	_check(is_equal_approx(float(camp.participants[0].progress_multiplier), 36.0) and int(Runtime.feature_production_info(data, right).workers) == 0 and int(Runtime.feature_production_info(data, left).workers) == 1, "Controller's actual request sees all released water before Fatigue planning")
	_check(data.site.inventory == inventory and float(data.site.features[left].production) == 0.0 and not data.site.features[left].batch_paid and PersonalFatigue.read(lab.npc) == npc_fatigue, "True water/source refresh spends no time, materials, progress or fatigue")
	var plan: Dictionary = PersonalFatigue.plan_work_interval(refreshed, 1.0)
	var captured: Dictionary = controller.prepare_shared_runtime_work_prefix(refreshed, 1.0)
	var priors: Array = []
	var admitted: Dictionary = controller.validate_shared_runtime_work_prefix(captured, plan, priors)
	_check(plan.ok and captured.ok and admitted.ok and priors.size() == 1 and float(plan.jobs.work_team[denied.key].actual_seconds) == 0.0, "One true camp prefix and zero denied effort pass the real Runtime registry before first cost")
	var clock: Dictionary = controller.checked_runtime_clock_interval()
	Runtime.advance(data, 1.0 / 1800.0, true, false, controller.reserves_cell, Callable(), Callable(), Runtime.CARRY_CAPACITY, Runtime.CARRY_CAPACITY, 1.0, 1, 1.0, true, clock)
	lab._shared_work_plan = plan
	controller._shared_work_plan = plan
	lab._shared_work_pools_committed = false
	lab._commit_shared_work_pools()
	var after_fatigue: float = PersonalFatigue.read(lab.npc)
	controller.publish_shared_runtime_work_prefix(admitted)
	_check(is_equal_approx(float(data.site.features[left].production), 0.6) and data.site.features[left].batch_paid and int(data.site.inventory.seeds) == int(inventory.seeds) - 1 and float(data.site.features[right].production) == 0.0 and not data.site.features[right].batch_paid, "Real Runtime publishes only this admitted 36-cell second and pays exactly one original seed")
	_check(PersonalFatigue.read(lab.npc) == after_fatigue and is_equal_approx(after_fatigue, npc_fatigue + PersonalFatigue.WORK_RATE), "Actual camp prefix uses its single original pool charge and no publisher charge")
	controller.finish_shared_runtime_work_prefix(admitted)
	controller.finish_shared_runtime_clock()
	_cleanup_fixture(lab, team)
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE_CONTROLLER_WORK_TEAM_WATER_PASS %d checks; true Controller camp+Army stations, same held request reprojection, finite MATERIALS pause, original water/productivity/one seed/progress/pool; Native/Region/full40 excluded" % checks)
	quit(0)
