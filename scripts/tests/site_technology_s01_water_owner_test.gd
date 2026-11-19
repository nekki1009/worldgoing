extends "res://scripts/tests/site_technology_natural_cold_fixture.gd"
## Genuine original Settlement/head/Actor/PA/clock/Fatigue/Store/Window fixture.
## A disabled Catalog is checked first. The explicit strict initial Scope project
## below is an OWNER PROBE, never evidence that the public research UI is open.
## Direct checked points exclude Native/contact/travel and whole Lab frame proof.
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const Catalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Homes = preload("res://scripts/terrain_lab/site_housing.gd")
const PersonalFatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
const COLD_SAVE := "res://.godot-temp/site_s01_owner/schedule.v1.json"
var checks = 0

func _check(condition: bool, message: String) -> void:
	checks += 1
	assert(condition, message)

func _s01_fixture(intakes: bool = false) -> Dictionary:
	if intakes: return _s01_component_intake_fixture()
	var specs: Array = [
		{"kind": "settlement_center", "anchor": Vector2i(27, 27), "extent": Vector2i(5, 5)},
		{"kind": "house", "anchor": Vector2i(24, 17), "extent": Vector2i.ONE, "options": {"variant": "standard"}},
		{"kind": "house", "anchor": Vector2i(24, 23), "extent": Vector2i.ONE, "options": {"variant": "small"}},
		{"kind": "farm", "anchor": Vector2i(15, 15), "extent": Vector2i(6, 12)},
		{"kind": "farm", "anchor": Vector2i(32, 15), "extent": Vector2i(6, 12)},
		{"kind": "tannery", "anchor": Vector2i(27, 21), "extent": Vector2i.ONE},
		{"kind": "well", "anchor": Vector2i(22, 22), "extent": Vector2i.ONE},
		{"kind": "well", "anchor": Vector2i(23, 22), "extent": Vector2i.ONE},
		{"kind": "warehouse", "anchor": Vector2i(14, 10), "extent": Vector2i.ONE},
		{"kind": "warehouse", "anchor": Vector2i(27, 17), "extent": Vector2i.ONE}, # Inside the radius-12 jurisdiction (S06 destination).
	]
	var extras: Array[Vector2i] = [Vector2i(21, 20)]
	var selected = _cold_natural_template(specs, "technology-s01-natural", extras, 8)
	var data: TerrainData = selected.data
	var offset: Vector2i = selected.offset
	data.site.depot_cell = data.index(Vector2i(21, 20) + offset)
	var lab = _cold_natural_lab(data)
	var actions: SitePersonActions = lab.site_controller.person_actions
	var control = int(lab.controlled_person_id())
	var center: Dictionary = selected.plans[0]
	_check(lab.character.place(data.cell_from_index(int(center.preview.entrance)), true), "Actual original founder reaches the natural center contact")
	for key: String in center.preview.get("clearing", []): Env.change(data, key, {"cleared": true, "remaining": 0})
	var cells: Array[int] = []
	cells.assign(center.geometry.cells)
	var founded = Settlement.found(lab, control, cells)
	_check(founded.ok, "Original founding owner admits the unchanged natural source")
	_complete_key(data, str(founded.feature))
	var house = _cold_natural_feature(data, "house", Vector2i(24, 17) + offset, Vector2i.ONE, {"variant": "standard"})
	var foreign = _cold_natural_feature(data, "house", Vector2i(24, 23) + offset, Vector2i.ONE, {"variant": "small"})
	data.site.features[foreign].owner_faction = 2 # Explicit original starting ownership only.
	var farm = _cold_natural_feature(data, "farm", Vector2i(15, 15) + offset, Vector2i(6, 12))
	var other_farm = _cold_natural_feature(data, "farm", Vector2i(32, 15) + offset, Vector2i(6, 12))
	var workshop = _cold_natural_feature(data, "tannery", Vector2i(27, 21) + offset)
	var pumps: Array[String] = [_cold_natural_feature(data, "well", Vector2i(22, 22) + offset), _cold_natural_feature(data, "well", Vector2i(23, 22) + offset)]
	var home = Runtime.house_layout(data, house)
	_check(home.ok, "Actual original natural-source house supplies the true head's resident slot")
	data.site.housing = {str(control): {"version": 1, "house_id": house, "cell": int(home.slots[0])}}
	_check(Homes.validate(data, data.site, {control: {"hp": lab.character.hp, "faction_id": 1}}).ok and Settlement.status(lab).effective, "Strict original Housing/current head keep the natural settlement effective")
	lab.site_controller.release_worker()
	data.site.worker.target = ""
	data.site.worker.progress = 0.0
	data.site.manual.target = ""
	data.site.manual.progress = 0.0
	Runtime.rebuild_water(data)
	return {"data": data, "lab": lab, "actions": actions, "control": control, "center": str(founded.feature), "house": house,
		"foreign": foreign, "farm": farm, "other_farm": other_farm, "workshop": workshop, "pumps": pumps, "natural_offset": offset}

func _initial_s01_project(fixture: Dictionary) -> Dictionary:
	var data: TerrainData = fixture.data
	var actions: SitePersonActions = fixture.actions
	var owner: Dictionary = Settlement.record(data)
	var before = var_to_bytes(data.site)
	if Catalog.get_node("S01").get("enabled") != true:
		var refused = actions.prepare_scope_technology(int(fixture.control), int(fixture.control), "S01")
		_check(not refused.ok and refused.code == "UNIMPLEMENTED" and var_to_bytes(data.site) == before, "Disabled Catalog keeps true public research closed; owner probe does not bypass the public UI")
	var authority = actions._technology_scope_command(int(fixture.control), "settlement", owner)
	_check(authority.ok, "The initial fixture project belongs to the actual current Settlement head")
	if Catalog.get_node("S01").get("enabled") == true:
		_check(actions.prepare_scope_technology(int(fixture.control), int(fixture.control), "S01").ok, "Enabled public owner creates its actual research project")
	else:
		var prepared = Technology.scope_prepare_candidate({}, "settlement", "S01", {"site_id": str(data.site.id), "person_id": int(fixture.control)})
		_check(prepared.ok and Technology.valid_scope_record(prepared.state, "settlement"), "Explicit starting owner-probe project uses the complete strict original Scope candidate")
		owner.version = 2
		owner.technology = prepared.state
	var project = Technology.active_project(owner.technology)
	var phase = Technology.scope_next_phase(project, project.executor)
	return {"scope": "settlement", "scope_id": str(owner.settlement_id), "project_id": int(project.id), "epoch": int(owner.technology.epoch),
		"purpose": str(project.purpose), "tech_id": "S01", "phase_id": str(phase.id), "attempt": int(project.next_attempt),
		"person": project.executor.duplicate(), "binding": str(phase.binding), "target_id": "feature:" + str(fixture.center), "materials": phase.materials.duplicate()}

func _start_s01(fixture: Dictionary) -> Dictionary:
	var token = _initial_s01_project(fixture)
	var actions: SitePersonActions = fixture.actions
	var before = var_to_bytes(fixture.data.site)
	var invalid = actions.begin_water_schedule_trial(token, ["house", "house", "workshop"], true)
	_check(not invalid.ok and var_to_bytes(fixture.data.site) == before, "Duplicate categories reject purely before job/payment/schedule")
	var preview = actions.begin_water_schedule_trial(token, ["farm", "house", "workshop"], true)
	_check(preview.ok and float(preview.seconds) == 300.0 and var_to_bytes(fixture.data.site) == before, "Actual source/head/binding preflight preview is read-only")
	var begun = actions.begin_water_schedule_trial(token, ["farm", "house", "workshop"])
	_check(begun.ok and float(begun.seconds) == 300.0, "Original PA starts exactly one genuine 300-second water scheduling job")
	var job: Dictionary = actions._jobs[str(int(fixture.control))]
	var project = Technology.active_project(fixture.data.site.settlement.technology)
	_check(job.kind == "water_schedule" and is_same(job.executor_body, actions._person(int(fixture.control)).body) and is_same(job.water_center, fixture.data.site.features[str(fixture.center)]), "Job retains SAME original body, center and Settlement refs")
	_check(project.budget.holder == "no_materials" and project.budget.cap.is_empty() and project.budget.payments.size() == 1 and project.receipts.is_empty(), "Zero-material phase has one original payment record and no fabricated financial quota/receipt")
	_check(actions.water_schedule_active(job.water_schedule), "Only the genuine currently valid original job enables its trial schedule")
	return job

func _s01_point(fixture: Dictionary, seconds: float, endpoint: String = "") -> Dictionary:
	# Keep the original clock's minute-end bound even for a 300-second caller.
	# A caller partition changes no source owner, clock or job-selection rule.
	var left = seconds
	var last = {}
	while left > PersonalFatigue.WORK_PLAN_EPS:
		var boundary = (1.0 - float(fixture.data.site.phase)) * 60.0
		var actual = minf(left, boundary)
		_check(actual > 0.0, "Original minute-end clipping makes positive progress")
		last = _s01_prefix_point(fixture, actual, endpoint if actual >= left - PersonalFatigue.WORK_PLAN_EPS else "")
		left -= actual
	return last

func _s01_prefix_point(fixture: Dictionary, seconds: float, endpoint: String = "") -> Dictionary:
	var data: TerrainData = fixture.data
	var lab: TerrainLab = fixture.lab
	var actions: SitePersonActions = fixture.actions
	var controller: SiteController = lab.site_controller
	controller._shared_worker_inputs = controller._prepare_original_work_inputs()
	var runtime_requests: Array[Dictionary] = controller.prepare_shared_owner_work_requests(seconds)
	_check(runtime_requests.is_empty(), "Idle original camp/manual add no assignment-wait effort")
	var requests = actions.work_requests(seconds)
	_check(requests.size() == 1 and requests[0].provider == "person_actions" and requests[0].productive_kind == "single", "Original PA projects the real water job and productive remaining time")
	lab._shared_work_requests = requests
	var clock_capture = controller.prepare_shared_runtime_work_prefix(requests, seconds)
	var captured = actions.prepare_shared_work_prefix(requests, seconds)
	var plan = PersonalFatigue.plan_work_interval(requests, seconds)
	_check(clock_capture.ok and captured.ok and plan.ok and plan.pools.size() == 1, "True source capture and original planner share one actual body pool")
	var actor = lab.character
	var fatigue_before = actor.fatigue
	var elapsed_before = float(actions._jobs[str(int(fixture.control))].elapsed)
	if endpoint == "death": actor.hp = 0.0
	var admitted = actions.validate_shared_work_prefix(captured, plan, requests)
	_check(admitted.ok and float(actions._jobs[str(int(fixture.control))].elapsed) == elapsed_before and actor.fatigue == fatigue_before, "Post-contact validation keeps real spent-prefix eligibility without publishing cost/time")
	lab._shared_work_plan = plan
	controller._shared_work_plan = plan
	lab._shared_work_pools_committed = false
	var clock = controller.checked_runtime_clock_interval()
	var now_before = Runtime.now(data)
	Runtime.advance(data, seconds / 60.0, false, false, controller.reserves_cell, Callable(), Callable(), Runtime.CARRY_CAPACITY, Runtime.CARRY_CAPACITY, 1.0, 1, seconds, true, clock)
	_check(bool(clock.advanced) and is_equal_approx(Runtime.now(data), now_before + seconds / 60.0), "Only original Runtime minute/phase advances this accepted interval once")
	if endpoint == "threat": Runtime.mark_combat(data)
	lab._commit_shared_work_pools()
	var charged = actor.fatigue
	lab._commit_shared_work_pools()
	_check(is_equal_approx(charged, fatigue_before + seconds * PersonalFatigue.WORK_RATE) and actor.fatigue == charged, "The genuine pool is charged once for real effort; repeated pool publication is inert")
	actions.begin_shared_work_prefix_consumption(admitted)
	var published = actions.publish_shared_job_prefix_timers(admitted)
	var elapsed = float(actions._jobs[str(int(fixture.control))].elapsed)
	actions.publish_shared_job_prefix_timers(admitted)
	_check(is_equal_approx(elapsed, elapsed_before + seconds) and float(actions._jobs[str(int(fixture.control))].elapsed) == elapsed and is_equal_approx(float(published.handled_seconds[int(fixture.control)]), seconds), "Original timer publication consumes its actual allocation once")
	actions.end_shared_work_prefix_consumption()
	actions.finish_shared_job_prefix_timers(admitted)
	actions.finish_shared_work_prefix(admitted)
	# Only the water schedule job has a water receipt; S06 reuses this point for its food order job.
	if elapsed >= 300.0 - PersonalFatigue.WORK_PLAN_EPS and endpoint.is_empty() and str(actions._jobs[str(int(fixture.control))].get("kind", "")) == "water_schedule":
		var job: Dictionary = actions._jobs[str(int(fixture.control))]
		var samples = actions.water_schedule_receipt_query(job.nation_token, actions._water_schedule_event(job))
		_check(samples.ok and is_same(samples.first, job.water_first_sample) and not is_same(samples.first.allocation, samples.second.allocation), "Original current completion query reads stored first sample and computes a fresh second allocation")
	var results = actions.settle_after_contacts()
	controller.finish_shared_runtime_clock()
	_check(controller.checked_runtime_clock_interval().is_empty(), "Original discrete clock endpoint is released only after current PA settlement")
	lab._clear_shared_work_step()
	return {"plan": plan, "elapsed": elapsed, "results": results}

func _close_s01(fixture: Dictionary) -> void:
	var lab: TerrainLab = fixture.lab
	for identity: String in fixture.actions._jobs.keys().duplicate(): fixture.actions.cancel(int(identity))
	lab.site_controller.work_team.discard_prepared_interval()
	lab._clear_shared_work_step()
	lab.queue_free()

func _finite_sources_and_partition() -> void:
	for intakes: bool in [false, true]:
		var fixture = _s01_fixture(intakes)
		# Farm water demand is the projection of operators at real farm work slots
		# (Runtime.set_operating_slots); stage both original farms as operated.
		var fixture_operating: Array = []
		for fixture_farm: String in [str(fixture.farm), str(fixture.other_farm)]:
			for fixture_slot: Dictionary in Runtime.feature_work_slots(fixture.data, fixture.data.site.features[fixture_farm]):
				fixture_operating.append({"task": {"target": "feature:" + fixture_farm, "action": "operate", "work_slot": int(fixture_slot.slot)}})
		Runtime.set_operating_slots(fixture.data, fixture_operating)
		var sample: Dictionary = Runtime.water_allocation_sample(fixture.data, ["farm", "house", "workshop"])
		var expected = 6.0 if intakes else 2.0
		_check(Runtime.valid_water_allocation_sample(sample) and is_equal_approx(float(sample.source_capacity), expected) and float(sample.total_supply) <= expected, "Two SAME-source original pumps retain finite %s capacity rather than multiplying it" % expected)
		var keys: Array = fixture.data.site.features.keys()
		keys.sort()
		var baseline = Runtime._water_consumer_order(fixture.data, keys, [])
		var reordered = Runtime._water_consumer_order(fixture.data, keys, ["farm", "house", "workshop"])
		_check(reordered[0] == "camp" and reordered.find(fixture.foreign) == baseline.find(fixture.foreign) and reordered.size() == baseline.size(), "Priority replaces only original local positions; foreign/camp positions and population do not expand")
		var house_first: Dictionary = Runtime.water_allocation_sample(fixture.data, ["house", "farm", "workshop"])
		_check(sample.allocation.camp == house_first.allocation.camp, "True camp baseline always retains its original demand/supply")
		if not intakes:
			_check(float(sample.total_demand) > expected and float(sample.allocation[str(fixture.house)].supplied) < float(house_first.allocation[str(fixture.house)].supplied), "Actual scarce well water changes local supply through the chosen genuine category priority")
		_close_s01(fixture)
		await process_frame

func _positive_partition(chunks: Array[float]) -> Dictionary:
	var fixture = _s01_fixture()
	var job = _start_s01(fixture)
	var first: Dictionary = job.water_first_sample.duplicate(true)
	var inventory: Dictionary = fixture.data.site.inventory.duplicate(true)
	for seconds: float in chunks: _s01_point(fixture, seconds)
	var record: Dictionary = fixture.data.site.settlement.technology
	var project: Dictionary = record.projects[0]
	_check(Technology.scope_known(record, "S01") and int(record.active) == 0 and project.receipts.size() == 1 and is_equal_approx(float(project.receipts[0].work_seconds), 300.0), "True completed original job publishes exactly one S01 Scope receipt and knowledge")
	_check(fixture.actions._jobs.is_empty() and fixture.data.site.inventory == inventory, "Completion releases the real job and consumes no research materials")
	var second: Dictionary = Runtime.water_allocation_sample(fixture.data, job.water_schedule.categories)
	_check(Runtime.valid_water_allocation_sample(first) and Runtime.valid_water_allocation_sample(second) and first.categories == second.categories and float(second.total_supply) <= 2.0, "Receipt corresponds to two genuine bounded original allocation samples")
	_check(Runtime._water_schedule_categories(fixture.data) == ["farm", "house", "workshop"], "Known original S01 preserves the same selected schedule after the job disappears")
	return fixture

func _zero_cancel_and_endpoints() -> void:
	var fixture = _s01_fixture()
	var job = _start_s01(fixture)
	var fatigue = fixture.lab.character.fatigue
	fixture.actions.advance(0.0)
	fixture.actions.advance(300.0)
	fixture.actions.advance(300.0, {"jobs": {}})
	_check(float(job.elapsed) == 0.0 and fixture.lab.character.fatigue == fatigue, "Zero/no-plan/missing allocation never create water work or fatigue")
	_s01_point(fixture, 100.0)
	var project = Technology.active_project(fixture.data.site.settlement.technology)
	var paid = project.budget.payments.duplicate(true)
	var stopped = fixture.actions.stop_scope_technology(int(fixture.control), "settlement", str(fixture.data.site.settlement.settlement_id))
	_check(stopped.ok and fixture.actions._jobs.is_empty() and project.receipts.is_empty() and project.budget.payments == paid and not Technology.scope_known(fixture.data.site.settlement.technology, "S01"), "Actual head cancels its own true job without receipt, repayment or deletion of its payment history")
	Runtime.allocate_water(fixture.data)
	_check(Runtime._water_schedule_categories(fixture.data).is_empty() and Runtime.validate_water_schedule_storage(fixture.data, fixture.data.site).ok, "Cancelled saved configuration is valid history but has no active scheduling effect")
	_close_s01(fixture)
	await process_frame
	for endpoint: String in ["death", "threat"]:
		fixture = _s01_fixture()
		_start_s01(fixture)
		_s01_point(fixture, 300.0, endpoint)
		project = Technology.active_project(fixture.data.site.settlement.technology)
		_check(project.receipts.is_empty() and not Technology.scope_known(fixture.data.site.settlement.technology, "S01") and fixture.actions._jobs.is_empty(), "True current %s endpoint preserves spent fatigue but grants no receipt/knowledge" % endpoint)
		_close_s01(fixture)
		await process_frame

func _two_samples_live_source() -> void:
	var fixture = _s01_fixture()
	var job = _start_s01(fixture)
	_s01_point(fixture, 100.0)
	var foreign: Dictionary = fixture.data.site.features[str(fixture.foreign)]
	_check(Runtime.damage_structure_part(fixture.data, str(fixture.foreign), "body", float(foreign.parts.body.hp)).ok, "The actual structure owner changes one real foreign consumer; direct damage is not a contact proof")
	var current: Dictionary = Runtime.water_allocation_sample(fixture.data, job.water_schedule.categories)
	_check(float(job.water_first_sample.total_demand) > float(current.total_demand) and current.allocation[str(fixture.foreign)].demand == 0.0, "Real second sample observes changed original demand instead of replaying the captured first allocation")
	_s01_point(fixture, 200.0)
	_check(Technology.scope_known(fixture.data.site.settlement.technology, "S01"), "Current legitimate changed-source allocation still completes the genuine phase")
	_close_s01(fixture)
	await process_frame

func _window_selection(fixture: Dictionary) -> void:
	var window: SiteTechWindow = fixture.lab.site_controller._tech_window
	var node: OptionButton = window._scope_node
	for index: int in node.item_count:
		if str(node.get_item_metadata(index)) == "S01": node.select(index)
	window._refresh_scope_controls()
	_check(window._scope_target.item_count == 7, "Real Window displays one placeholder and all six original water-category permutations")
	for index: int in range(1, 7):
		window._scope_target.select(index)
		var picked: Dictionary = window._scope_target.get_item_metadata(index)
		var categories: Array = picked.work_target.categories.duplicate()
		window._refresh_scope_controls()
		var actual: Dictionary = window._scope_target.get_item_metadata(window._scope_target.selected)
		_check(actual.work_target.categories == categories and is_same(actual.target_ref, fixture.data.site.features[str(fixture.center)]), "Real option refresh preserves this exact selected permutation and SAME center")
	if Catalog.get_node("S01").get("enabled") != true:
		_check(window._scope_buttons.ScopeApplyWater.disabled, "Disabled public apply stays visibly unavailable; rendering six choices is not publicUI acceptance")

func _cold_known(fixture: Dictionary) -> void:
	_window_selection(fixture)
	var data: TerrainData = fixture.data
	fixture.lab.site_controller._capture_positions()
	var saved = Store.save(data, COLD_SAVE)
	_check(saved.ok, "Original Store saves completed strict S01 record and actual center schedule: " + str(saved))
	var source_fingerprint = data.fingerprint()
	var source_conditions = _cold_natural_conditions(data)
	var loaded = Store.load_site(COLD_SAVE)
	_check(loaded.ok, "Original cold Store reconstructs the same validated owner data: " + str(loaded))
	_check(loaded.data.fingerprint() == source_fingerprint and _cold_natural_conditions(loaded.data) == source_conditions, "Cold must retain the same original natural terrain and all five original conditions")
	fixture.lab.bind_terrain(loaded.data)
	fixture.data = loaded.data
	fixture.actions = fixture.lab.site_controller.person_actions
	var original: Dictionary = loaded.data.site.features[str(fixture.center)]
	_check(Runtime.valid_water_schedule(original.technology_water_schedule, loaded.data.site) and Technology.scope_known(loaded.data.site.settlement.technology, "S01") and fixture.actions._jobs.is_empty(), "True bind restores known schedule without a second job or receipt")
	_check(Runtime._water_schedule_categories(loaded.data) == ["farm", "house", "workshop"] and loaded.data.site.water_status == Runtime.water_allocation_sample(loaded.data, ["farm", "house", "workshop"]).allocation, "Original Controller bind applies saved known priority through actual allocator")
	_window_selection(fixture)
	var before = var_to_bytes(loaded.data.site)
	var apply: Dictionary = fixture.actions.set_water_use_priority(int(fixture.control), ["workshop", "house", "farm"])
	if Catalog.get_node("S01").get("enabled") == true:
		_check(apply.ok and Runtime._water_schedule_categories(loaded.data) == ["workshop", "house", "farm"], "Enabled ordinary known apply uses the true head transaction")
	else:
		_check(not apply.ok and apply.code == "UNIMPLEMENTED" and var_to_bytes(loaded.data.site) == before, "Cold known archive does not bypass the still-disabled public apply guard")
	var corrupt: Dictionary = loaded.data.site.duplicate(true)
	corrupt.features[str(fixture.center)].technology_water_schedule.categories = ["farm", "farm", "workshop"]
	_check(not Runtime.validate_water_schedule_storage(loaded.data, corrupt).ok, "Original cold schema rejects repeated category configuration")
	var original_categories: Array = original.technology_water_schedule.categories
	original.technology_water_schedule.categories = ["farm", "farm", "workshop"]
	var checksum = FileAccess.get_sha256(COLD_SAVE)
	var rejected = Store.save(loaded.data, COLD_SAVE)
	_check(not rejected.ok and rejected.code == "CORRUPT_SAVE" and FileAccess.get_sha256(COLD_SAVE) == checksum, "Actual Store rejects invalid schedule before overwriting the valid cold save")
	original.technology_water_schedule.categories = original_categories

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	await _finite_sources_and_partition()
	var long_frame: Dictionary = _positive_partition([300.0])
	var divided: Dictionary = _positive_partition([100.0, 200.0])
	_check(is_equal_approx(long_frame.lab.character.fatigue, divided.lab.character.fatigue) and Runtime.now(long_frame.data) == Runtime.now(divided.data) and long_frame.data.site.water_status == divided.data.site.water_status, "300 and 100+200 use equal real effort, original elapsed clock and final original allocations")
	_cold_known(divided)
	_close_s01(long_frame)
	_close_s01(divided)
	await process_frame
	await _zero_cancel_and_endpoints()
	await _two_samples_live_source()
	print("SITE_TECHNOLOGY_S01_WATER_OWNER_PASS: %d checks; OWNER_PROBE_IF_CATALOG_DISABLED, original head/pumps/PA/pool/clock/receipt/cold-bind and six selection permutations; Native/contacts/publicUI/full40 excluded" % checks)
	quit(0)

# Existing allocation-only synthetic intake component is never saved/loaded.
func _s01_component_intake_fixture(intakes: bool = true) -> Dictionary:
	var data = _building_fixture()
	data.site.depot_cell = data.index(Vector2i(21, 20))
	var lab = _building_lab(data)
	var actions: SitePersonActions = lab.site_controller.person_actions
	var control: int = lab.controlled_person_id()
	_check(lab.character.place(Vector2i(25, 25), true), "Actual founder stands in the original center's jurisdiction")
	var geometry = Runtime.building_cells(data, "settlement_center", Vector2i(27, 27), Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	_check(geometry.ok, "Original center geometry is usable")
	var cells: Array[int] = []
	cells.assign(geometry.cells)
	var founded = Settlement.found(lab, control, cells)
	_check(founded.ok, "Actual Settlement.found creates the original center and founder head")
	_complete_key(data, str(founded.feature))
	var house = _formal_feature(data, "house", Vector2i(24, 17), Vector2i.ONE, {"variant": "standard"})
	var foreign = _formal_feature(data, "house", Vector2i(24, 23), Vector2i.ONE, {"variant": "small"})
	# Explicit starting-world foreign ownership after genuine construction. This
	# tests allocation jurisdiction, not an unimplemented transfer/takeover command.
	data.site.features[foreign].owner_faction = 2
	var farm = _formal_feature(data, "farm", Vector2i(15, 15), Vector2i(6, 12))
	var other_farm = _formal_feature(data, "farm", Vector2i(32, 15), Vector2i(6, 12))
	var workshop = _formal_feature(data, "tannery", Vector2i(27, 21))
	var pumps: Array[String] = []
	if intakes:
		# Two real adjacent fresh-water cells belong to one original water_body.
		# This is explicit fixture geography, rather than copied pump source data.
		for cell: Vector2i in [Vector2i(24, 22), Vector2i(32, 13)]:
			data.water_kind[data.index(cell)] = 1
			data.water_body[data.index(cell)] = 77
			data.flags[data.index(cell)] = 0
		pumps.append(_formal_feature(data, "intake", Vector2i(22, 22)))
		pumps.append(_formal_feature(data, "intake", Vector2i(30, 13)))
		_check(data.site.features[pumps[0]].source == data.site.features[pumps[1]].source, "Original placement resolves the SAME actual fresh-water body")
	else:
		pumps.append(_formal_feature(data, "well", Vector2i(22, 22)))
		pumps.append(_formal_feature(data, "well", Vector2i(23, 22)))
	var home = Runtime.house_layout(data, house)
	_check(home.ok, "Actual completed house supplies the head's original housing slot")
	data.site.housing = {str(control): {"version": 1, "house_id": house, "cell": int(home.slots[0])}}
	_check(Homes.validate(data, data.site, {control: {"hp": lab.character.hp, "faction_id": 1}}).ok, "Original Housing validates the real Actor resident")
	_check(Settlement.status(lab).effective and int(Settlement.status(lab).head) == control, "Original usable level-one center has its genuine present head")
	lab.site_controller.release_worker()
	data.site.worker.target = ""
	data.site.worker.progress = 0.0
	data.site.manual.target = ""
	data.site.manual.progress = 0.0
	Runtime.rebuild_water(data)
	return {"data": data, "lab": lab, "actions": actions, "control": control, "center": str(founded.feature), "house": house,
		"foreign": foreign, "farm": farm, "other_farm": other_farm, "workshop": workshop, "pumps": pumps}
