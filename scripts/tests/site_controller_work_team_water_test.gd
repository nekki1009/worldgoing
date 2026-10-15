extends "res://scripts/tests/site_technology_controller_prefix_test.gd"
## True TerrainLab/Controller/Actor/Army/farm/well owners. The finite external
## ledger's MATERIALS verdict is explicit fixture input; no mocked Controller
## request, substituted task/body, new timer or full Native/Region claim.

class WaterFaultLog extends Logger:
	var _mutex: Mutex = Mutex.new()
	var _first: String = ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING: return
		_mutex.lock()
		if _first.is_empty(): _first = "%s:%d %s: %s %s" % [file, line, function, code, rationale]
		_mutex.unlock()

	func first_error() -> String:
		_mutex.lock()
		var result: String = _first
		_mutex.unlock()
		return result

var _water_fault_log: WaterFaultLog = WaterFaultLog.new()
var _water_failed: bool = false

func _initialize() -> void:
	OS.add_logger(_water_fault_log)
	super._initialize()

func _finalize() -> void:
	OS.remove_logger(_water_fault_log)

func _water_ok() -> bool:
	if _water_failed: return false
	var fault: String = _water_fault_log.first_error()
	if not fault.is_empty(): _check(false, fault)
	return not _water_failed

func _process(delta: float) -> bool:
	if not _water_ok(): return false
	return super._process(delta)

func _check(condition: bool, message: String) -> void:
	if _water_failed: return
	checks += 1
	var fault: String = _water_fault_log.first_error()
	if not fault.is_empty(): condition = false; message = fault
	if Time.get_ticks_msec() > deadline: condition = false; message = "unchanged 90-second water test deadline"
	if condition: return
	_water_failed = true
	push_error(message)
	quit(1)

func _army(lab: TerrainLab, data: TerrainData) -> TerrainArmy:
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = 301
	team.roster_size = 2
	team.faction_id = 1
	var cells: Array[Vector2i] = [Vector2i(11, 11), Vector2i(12, 11)]
	_check(team.deploy_at(data, null, null, cells) and team.enable_combat(false), "Original finite Army creates and initializes its real NPC rows")
	if not _water_ok(): return null
	for row: Dictionary in team.combat_units:
		row.cargo = {}
		row.item_state = Runtime.new_item_state("person:" + str(row.person_id))
	lab.combat_armies.append(team)
	team.controlled_person_query = lab.controlled_person_id
	team.person_busy_query = lab.site_controller.person_actions.is_busy
	team.settle_combat_command()
	_check(team.set_duty_ai_enabled(team.combat_identity(team.formal_commander), true).ok, "Actual original captain explicitly enables the actual duty flag")
	if not _water_ok(): return null
	return team

func _run() -> void:
	deadline = Time.get_ticks_msec() + 90000
	var data: TerrainData = _building_fixture()
	if not _water_ok(): return
	var right: String = _formal_feature(data, "farm", Vector2i(16, 40), Vector2i(6, 6))
	if not _water_ok(): return
	var left: String = _formal_feature(data, "farm", Vector2i(10, 40), Vector2i(6, 6))
	if not _water_ok(): return
	_formal_feature(data, "well", Vector2i(14, 38))
	if not _water_ok(): return
	# Natural immutable feature IDs retain the original allocator priority.
	var feature_order: Array = data.site.features.keys()
	feature_order.sort()
	_check(feature_order.find(right) < feature_order.find(left), "Original right Army farm is naturally allocated before the same-position camp farm; no key override")
	if not _water_ok(): return
	_check(Runtime.operate_feature(data, left).ok and Runtime.operate_feature(data, right).ok, "True original production owners enable both real six-by-six farms")
	if not _water_ok(): return
	var left_slots: Array = Runtime.feature_work_slots(data, data.site.features[left])
	if not _water_ok(): return
	var right_slots: Array = Runtime.feature_work_slots(data, data.site.features[right])
	if not _water_ok(): return
	_check(left_slots.size() == 1 and right_slots.size() == 1, "Both original farms have one real service station")
	if not _water_ok(): return
	var lab: TerrainLab = _building_lab(data)
	if not _water_ok(): return
	var controller: SiteController = lab.site_controller
	if not _water_ok(): return
	var team: TerrainArmy = _army(lab, data)
	if not _water_ok(): return
	var crew := controller.work_team
	if not _water_ok(): return
	var executor: int = team.combat_identity(1)
	if not _water_ok(): return
	_check(crew.assign(team, [executor], team.duty_decider("team.work")).ok, "Original captain assigns this true same Army member")
	if not _water_ok(): return
	team.cells[1] = data.cell_from_index(int(right_slots[0].cell))
	if not _water_ok(): return
	var row: Dictionary = team.combat_units[1]
	if not _water_ok(): return
	Runtime.assign_task(data, Runtime.ok("True original fixture fixes the actual right farm slot", {"target": "feature:" + right, "action": "operate", "work_slot": 0, "cell": int(right_slots[0].cell), "zone": -1}), row.work_task)
	if not _water_ok(): return
	row.work_task.cell = int(right_slots[0].cell)
	if not _water_ok(): return
	row.work_task.mode = "work"
	if not _water_ok(): return
	_check(lab.npc.place(data.cell_from_index(int(left_slots[0].cell)), true), "Original camp Actor stands at the distinct actual left farm station")
	if not _water_ok(): return
	Runtime.assign_task(data, Runtime.ok("True original fixture fixes the actual camp farm slot", {"target": "feature:" + left, "action": "operate", "work_slot": 0, "cell": int(left_slots[0].cell), "zone": -1}))
	if not _water_ok(): return
	data.site.worker.cell = int(left_slots[0].cell)
	if not _water_ok(): return
	data.site.worker.mode = "work"
	if not _water_ok(): return
	data.site.worker_enabled = true
	if not _water_ok(): return
	lab.npc.issue_command(TerrainTestNPC.Command.STOP)
	if not _water_ok(): return
	controller._shared_worker_inputs = controller._prepare_original_work_inputs()
	if not _water_ok(): return
	var requests: Array = controller.prepare_shared_owner_work_requests(1.0)
	if not _water_ok(): return
	requests.append_array(crew.prepare_work_requests(1.0, 1.0 / 1800.0))
	if not _water_ok(): return
	requests = crew.apply_shared_preflight(requests)
	if not _water_ok(): return
	var camp: Dictionary = {}
	if not _water_ok(): return
	var denied: Dictionary = {}
	if not _water_ok(): return
	for request: Dictionary in requests:
		if str(request.provider) == "runtime" and str(request.key) == "worker": camp = request
		elif str(request.provider) == "work_team" and str(request.key) == "feature:" + right + ":operate": denied = request
	_check(not camp.is_empty() and not denied.is_empty() and camp.productive_kind == "sum" and camp.participants.size() == 1 and is_same(camp.task, data.site.worker) and is_same(camp.participants[0].body, lab.npc), "Only true Controller/WorkTeam sources create these same held demands and original bodies")
	if not _water_ok(): return
	var initial_weight: float = float(camp.participants[0].progress_multiplier)
	if not _water_ok(): return
	var camp_water: Dictionary = data.site.water_status.get(left, {}).get("slots", {}).get("0", {})
	var army_water: Dictionary = data.site.water_status.get(right, {}).get("slots", {}).get("0", {})
	_check(float(camp_water.get("supplied", 0.0)) > 0.0 and float(camp_water.get("supplied", 0.0)) < float(camp_water.get("demand", 0.0)) and float(army_water.get("supplied", 0.0)) > 0.0, "Original real water projection proves camp gets a positive scarce remainder while both original stations are served")
	if not _water_ok(): return
	_check(initial_weight > 0.0 and initial_weight < 36.0 and int(Runtime.feature_production_info(data, left).workers) == 1 and int(Runtime.feature_production_info(data, right).workers) == 1, "Camp starts with the true scarce water shared by both original accepted stations")
	if not _water_ok(): return
	var inventory: Dictionary = data.site.inventory.duplicate(true)
	if not _water_ok(): return
	var camp_task: Dictionary = data.site.worker
	if not _water_ok(): return
	var army_task: Dictionary = row.work_task
	if not _water_ok(): return
	var npc_fatigue: float = PersonalFatigue.read(lab.npc)
	if not _water_ok(): return
	denied.paused = "MATERIALS" # Explicit original all-provider admission verdict.
	if not _water_ok(): return
	var refreshed: Array = crew.apply_shared_preflight(requests)
	if not _water_ok(): return
	_check(is_same(refreshed[0], requests[0]) and is_same(camp.task, camp_task) and is_same(row.work_task, army_task) and str(denied.paused) == "MATERIALS", "Original reprojection retains every held request/task and never revives the denied group")
	if not _water_ok(): return
	_check(is_equal_approx(float(camp.participants[0].progress_multiplier), 36.0) and int(Runtime.feature_production_info(data, right).workers) == 0 and int(Runtime.feature_production_info(data, left).workers) == 1, "Controller's actual request sees all released water before Fatigue planning")
	if not _water_ok(): return
	_check(data.site.inventory == inventory and float(data.site.features[left].production) == 0.0 and not data.site.features[left].batch_paid and PersonalFatigue.read(lab.npc) == npc_fatigue, "True water/source refresh spends no time, materials, progress or fatigue")
	if not _water_ok(): return
	var plan: Dictionary = PersonalFatigue.plan_work_interval(refreshed, 1.0)
	if not _water_ok(): return
	var captured: Dictionary = controller.prepare_shared_runtime_work_prefix(refreshed, 1.0)
	if not _water_ok(): return
	var priors: Array = []
	if not _water_ok(): return
	var admitted: Dictionary = controller.validate_shared_runtime_work_prefix(captured, plan, priors)
	if not _water_ok(): return
	_check(plan.ok and captured.ok and admitted.ok and priors.size() == 1 and float(plan.jobs.work_team[denied.key].actual_seconds) == 0.0, "One true camp prefix and zero denied effort pass the real Runtime registry before first cost")
	if not _water_ok(): return
	var clock: Dictionary = controller.checked_runtime_clock_interval()
	if not _water_ok(): return
	Runtime.advance(data, 1.0 / 1800.0, true, false, controller.reserves_cell, Callable(), Callable(), Runtime.CARRY_CAPACITY, Runtime.CARRY_CAPACITY, 1.0, 1, 1.0, true, clock)
	if not _water_ok(): return
	lab._shared_work_plan = plan
	if not _water_ok(): return
	controller._shared_work_plan = plan
	if not _water_ok(): return
	lab._shared_work_pools_committed = false
	if not _water_ok(): return
	lab._commit_shared_work_pools()
	if not _water_ok(): return
	var after_fatigue: float = PersonalFatigue.read(lab.npc)
	if not _water_ok(): return
	controller.publish_shared_runtime_work_prefix(admitted)
	if not _water_ok(): return
	_check(is_equal_approx(float(data.site.features[left].production), 0.6) and data.site.features[left].batch_paid and int(data.site.inventory.seeds) == int(inventory.seeds) - 1 and float(data.site.features[right].production) == 0.0 and not data.site.features[right].batch_paid, "Real Runtime publishes only this admitted 36-cell second and pays exactly one original seed")
	if not _water_ok(): return
	_check(PersonalFatigue.read(lab.npc) == after_fatigue and is_equal_approx(after_fatigue, npc_fatigue + PersonalFatigue.WORK_RATE), "Actual camp prefix uses its single original pool charge and no publisher charge")
	if not _water_ok(): return
	controller.finish_shared_runtime_work_prefix(admitted)
	if not _water_ok(): return
	controller.finish_shared_runtime_clock()
	if not _water_ok(): return
	_cleanup_fixture(lab, team)
	if not _water_ok(): return
	await process_frame
	if not _water_ok(): return
	TerrainArmy.release_contact_source()
	if not _water_ok(): return
	print("SITE_CONTROLLER_WORK_TEAM_WATER_PASS %d checks; true Controller camp+Army stations, same held request reprojection, finite MATERIALS pause, original water/productivity/one seed/progress/pool; Native/Region/full40 excluded" % checks)
	quit(0)
