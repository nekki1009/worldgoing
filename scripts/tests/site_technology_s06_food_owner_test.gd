extends "res://scripts/tests/site_technology_s01_water_owner_test.gd"
## Genuine original founder/head, warehouse holders, physical two-leg transfer,
## PA shared productive timer, Scope paid history, Store and real Window.
## Disabled Catalog creates a strict starting OWNER_PROBE project only.
## Explicit Actor placement is fixture geography/contact, not travel proof.
const Stockpiles = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const FOOD_SAVE := "res://.godot-temp/site_s06_owner/food.v1.json"

func _food_fixture() -> Dictionary:
	var fixture := _s01_fixture()
	fixture.source = _cold_natural_feature(fixture.data, "warehouse", Vector2i(14, 10) + Vector2i(fixture.natural_offset))
	fixture.warehouse = _cold_natural_feature(fixture.data, "warehouse", Vector2i(25, 10) + Vector2i(fixture.natural_offset))
	_check(Stockpiles.ensure_storage(fixture.data, str(fixture.source), 1).ok and Stockpiles.ensure_storage(fixture.data, str(fixture.warehouse), 1).ok, "Original constructed warehouses initialize their true original holders")
	fixture.source_stock = Stockpiles.storage(fixture.data, str(fixture.source))
	fixture.destination_stock = Stockpiles.storage(fixture.data, str(fixture.warehouse))
	# Explicit starting inventory in the genuine original warehouse. Every tested
	# later mutation is the actual transfer owner; no extra inventory is created.
	fixture.source_stock.cargo.grain = 16
	_check(fixture.lab.character.place(Stockpiles.stock_endpoint(fixture.data, str(fixture.source)).cell, true), "Real head physically touches the named original source")
	fixture.actions = fixture.lab.site_controller.person_actions
	return fixture

func _food_order(fixture: Dictionary) -> Dictionary:
	var actions: SitePersonActions = fixture.actions
	var owner := Settlement.record(fixture.data)
	var before := var_to_bytes(fixture.data.site)
	if Catalog.get_node("S06").get("enabled") != true:
		var rejected := actions.prepare_scope_technology(int(fixture.control), int(fixture.control), "S06")
		_check(not rejected.ok and rejected.code == "UNIMPLEMENTED" and var_to_bytes(fixture.data.site) == before, "Disabled Catalog keeps public S06 closed")
		var initial := Technology.scope_prepare_candidate({}, "settlement", "S06", {"site_id": str(fixture.data.site.id), "person_id": int(fixture.control)})
		_check(initial.ok, "Explicit starting owner probe uses the complete original strict Scope candidate")
		owner.version = 2
		owner.technology = initial.state
	else:
		_check(actions.prepare_scope_technology(int(fixture.control), int(fixture.control), "S06").ok, "Enabled public original owner creates S06 project")
	var project := Technology.active_project(owner.technology)
	var preview := actions.request_warehouse_food_order(int(fixture.control), str(fixture.warehouse), int(fixture.control), "feature:" + str(fixture.source), int(project.id), true)
	_check(preview.ok, "True original source/contact/head/carrier and finite cap preflight purely")
	var created := actions.request_warehouse_food_order(int(fixture.control), str(fixture.warehouse), int(fixture.control), "feature:" + str(fixture.source), int(project.id))
	_check(created.ok, "Original adopted food order is registered without debit")
	fixture.order_id = str(created.order_id)
	var order: Dictionary = owner.technology_operations.orders[fixture.order_id]
	_check(order.size() == 7 and order.payload.source.size() == 4 and order.payload.cap == {"grain": 8} and order.payload.spent.is_empty() and order.receipts.is_empty(), "Exact shared seven-field header and finite common four-field source")
	var phase := Technology.scope_next_phase(project, project.executor)
	fixture.token = {"scope": "settlement", "scope_id": str(owner.settlement_id), "project_id": int(project.id), "epoch": int(owner.technology.epoch), "purpose": str(project.purpose),
		"tech_id": "S06", "phase_id": str(phase.id), "attempt": int(project.next_attempt), "person": project.executor.duplicate(), "binding": "food_order",
		"target_id": Runtime.settlement_food_target(str(fixture.data.site.id), str(owner.settlement_id), fixture.order_id), "materials": {"grain": 8}}
	return order

func _food_load(fixture: Dictionary) -> Dictionary:
	var order := _food_order(fixture)
	var actions: SitePersonActions = fixture.actions
	var before := var_to_bytes(fixture.data.site)
	var pure := Runtime.prepare_settlement_food_transfer(fixture.data, str(order.payload.settlement_id), str(order.id), "load", int(fixture.control), fixture.token)
	_check(pure.ok and var_to_bytes(fixture.data.site) == before and actions._jobs.is_empty(), "First-leg candidate is pure and allocates no assignment-wait effort")
	_check(Runtime.validate_settlement_food_transfer(pure).ok, "All actual payment/transfer/Scope guards recheck before first cost")
	var loaded := Runtime.publish_settlement_food_transfer(pure)
	var person := actions._person(int(fixture.control))
	_check(loaded.ok and fixture.source_stock.cargo.grain == 8 and int(person.cargo.get("grain", 0)) == 8 and fixture.destination_stock.cargo.is_empty(), "Actual first transfer moves eight source grain into the SAME original carrier; warehouse stays empty")
	_check(order.payload.spent == {"grain": 8} and order.receipts.size() == 1 and order.payload.stage == "carrier", "Only actual first transfer records finite spend and loading evidence")
	var project := Technology.active_project(Settlement.record(fixture.data).technology)
	_check(project.budget.payments.size() == 1 and project.budget.spent == {"grain": 8} and project.receipts.is_empty(), "Scope payment publishes in the same original first-transfer tail once")
	var paid_before := var_to_bytes(fixture.data.site)
	_check(Runtime.publish_settlement_food_transfer(pure).get("duplicate", false) and var_to_bytes(fixture.data.site) == paid_before, "Same synchronous candidate publisher replay pays zero")
	_check(not Runtime.validate_settlement_food_transfer(pure).ok, "Consumed first-leg candidate cannot pass admission again")
	var far := actions.transfer_settlement_food_order(int(fixture.control), str(order.payload.settlement_id), str(order.id), "arrive", order.payload.token)
	_check(not far.ok and var_to_bytes(fixture.data.site) == paid_before, "Remote warehouse transfer rejects at real physical contact before cost/job")
	_check(actions.work_requests(300.0).is_empty(), "Paid cargo waiting for actual delivery is not fictitious work")
	_food_window(fixture, order)
	return order

func _food_window(fixture: Dictionary, order: Dictionary) -> void:
	var window: SiteTechWindow = fixture.lab.site_controller._tech_window
	for index: int in window._scope_node.item_count:
		if window._scope_node.get_item_metadata(index) == "S06": window._scope_node.select(index)
	window._refresh_scope_controls()
	_check(window._scope_target.item_count == 2, "Actual Window lists only the one genuine adopted finite food order and placeholder")
	window._scope_target.select(1)
	var selected: Dictionary = window._scope_target.get_item_metadata(1)
	_check(is_same(selected.target_ref, order), "UI target metadata retains SAME original order instead of a fabricated warehouse trial")
	window._refresh_scope_controls()
	var refreshed: Dictionary = window._scope_target.get_item_metadata(window._scope_target.selected)
	_check(refreshed.key == order.id and is_same(refreshed.target_ref, order), "Original UI refresh retains the selected exact order")
	var query = fixture.actions.scope_technology_query("S06")
	_check(query.ok and window._scope_food_selection(query, refreshed).ok, "Submission pure query rechecks the actual owner/order/project")
	var cloned: Dictionary = refreshed.duplicate(true)
	_check(not window._scope_food_selection(query, cloned).ok, "Cloned UI row cannot replace the actual adopted order ref")
	if Catalog.get_node("S06").get("enabled") != true:
		_check(window._scope_buttons.ScopeBeginPhase.disabled, "Catalog-disabled ordinary/public work remains visibly closed; owner metadata probe is not publicUI PASS")

func _food_arrive(fixture: Dictionary, order: Dictionary) -> Dictionary:
	_check(fixture.lab.character.place(Stockpiles.stock_endpoint(fixture.data, str(fixture.warehouse)).cell, true), "Actual carrier now touches the real destination entrance")
	var result = fixture.actions.transfer_settlement_food_order(int(fixture.control), str(order.payload.settlement_id), str(order.id), "arrive", order.payload.token)
	_check(result.ok and int(fixture.actions._person(int(fixture.control)).cargo.get("grain", 0)) == 0 and int(fixture.destination_stock.cargo.get("grain", 0)) == 8, "Actual second transfer unloads the real carrier into the original warehouse")
	_check(fixture.source_stock.cargo.grain == 8 and order.payload.spent == {"grain": 8} and order.receipts.size() == 2 and order.payload.stage == "arrived", "Second leg never consumes source or cap twice")
	var job: Dictionary = fixture.actions._jobs[str(int(fixture.control))]
	_check(job.kind == "food_order" and job.duration == 300.0 and job.elapsed == 0.0 and is_same(job.food_order, order) and is_same(job.food_holder, fixture.destination_stock.holder), "Only real arrival creates original PA 300-second job with SAME actual refs")
	return job

func _food_positive(partition: Array) -> Dictionary:
	var fixture := _food_fixture()
	var order := _food_load(fixture)
	var job := _food_arrive(fixture, order)
	fixture.actions.advance(0.0)
	fixture.actions.advance(30.0)
	_check(job.elapsed == 0.0 and order.payload.work_seconds == 0.0 and job.paused == "CLOCK_NOT_READY", "Zero/no-plan calls cannot steal original productive time or charge native fallback")
	for seconds: float in partition: _s01_point(fixture, seconds)
	_check(order.status == "completed" and order.payload.work_seconds == 300.0 and order.receipts.size() == 3, "Real shared planner/timer finishes the finite original order once")
	_check(Technology.scope_known(Settlement.record(fixture.data).technology, "S06") and fixture.actions._jobs.is_empty(), "Current genuine Scope receipt completes knowledge exactly once")
	var snapshot := var_to_bytes(fixture.data.site)
	fixture.actions.settle_after_contacts()
	_check(var_to_bytes(fixture.data.site) == snapshot, "Repeated zero endpoint publishes no product, payment or knowledge twice")
	return fixture

func _food_cold(fixture: Dictionary) -> void:
	var order: Dictionary = Settlement.record(fixture.data).technology_operations.orders[fixture.order_id]
	_check(Runtime.damage_structure_part(fixture.data, str(fixture.source), "body", float(fixture.data.site.features[str(fixture.source)].parts.body.hp)).ok, "True source owner is destroyed after historical load")
	_check(Runtime.settlement_food_existing_paid_source(fixture.data, order.payload.token).ok, "Paid history survives loss of live source without a new debit")
	_check(not fixture.actions.save_guard().ok, "Actual active food PA job keeps the original public save guard BUSY")
	_check(fixture.actions.cancel(int(fixture.control)).ok and fixture.actions.save_guard().ok, "Original cancel releases only the transient held job before cold save")
	_check(order.payload.work_seconds == 100.0 and order.payload.spent == {"grain": 8}, "Cancelling preserves canonical productive history and the single paid source debit")
	fixture.lab.site_controller._capture_positions()
	_check(Store.save(fixture.data, FOOD_SAVE).ok, "Original Store saves strict order and real carrier/warehouse holders")
	var source_fingerprint = fixture.data.fingerprint()
	var source_conditions := _cold_natural_conditions(fixture.data)
	var loaded := Store.load_site(FOOD_SAVE)
	_check(loaded.ok, "True cold Store accepts typed finite food history")
	_check(loaded.data.fingerprint() == source_fingerprint and _cold_natural_conditions(loaded.data) == source_conditions, "Cold food history retains the same natural source and five original land conditions")
	fixture.lab.bind_terrain(loaded.data)
	fixture.data = loaded.data
	fixture.actions = fixture.lab.site_controller.person_actions
	fixture.source_stock = Stockpiles.storage(fixture.data, str(fixture.source))
	fixture.destination_stock = Stockpiles.storage(fixture.data, str(fixture.warehouse))
	order = Settlement.record(fixture.data).technology_operations.orders[fixture.order_id]
	_check(Runtime.valid_settlement_food_order(fixture.data, fixture.data.site, order) and is_same(order.payload.token, order.payload.paid.token), "JSON numbers normalize and true bind restores ONE token reference on original order")
	_check(order.payload.work_seconds == 100.0 and fixture.actions._jobs.is_empty(), "Original saved productive evidence remains 100; bind never invents another timer")
	var resumed = fixture.actions.begin_settlement_food_work(int(fixture.control), str(order.payload.settlement_id), str(order.id))
	_check(resumed.ok and resumed.remaining == 200.0 and fixture.actions._jobs[str(int(fixture.control))].elapsed == 100.0, "Explicit actual head resumes original saved progress without source repayment")
	_s01_point(fixture, 200.0)
	_check(order.status == "completed" and order.payload.spent == {"grain": 8} and order.receipts.size() == 3, "Cold continuation completes original 300 seconds and one finite transfer history")
	var window: SiteTechWindow = fixture.lab.site_controller._tech_window
	for index: int in window._scope_node.item_count:
		if window._scope_node.get_item_metadata(index) == "S06": window._scope_node.select(index)
	window._refresh_scope_controls()
	if Catalog.get_node("S06").get("enabled") != true:
		var refused = fixture.actions.request_warehouse_food_order(int(fixture.control), str(fixture.warehouse), int(fixture.control), "feature:" + str(fixture.source))
		_check(not refused.ok and refused.code == "NO_TECHNOLOGY", "Known cold archive keeps disabled ordinary public S06 unavailable")

func _food_negative() -> void:
	var fixture := _food_fixture()
	var order := _food_load(fixture)
	var corrupt: Dictionary = order.duplicate(true)
	corrupt.payload.cap.grain = 9
	_check(not Runtime.valid_settlement_food_order(fixture.data, fixture.data.site, corrupt), "Maximum source spend is the true fixed eight, not a caller-grown budget")
	corrupt = order.duplicate(true)
	corrupt.payload.source.cap = {"grain": 8}
	_check(not Runtime.valid_settlement_food_order(fixture.data, fixture.data.site, corrupt), "Source common shape stays exact four; cap/spent exist only in typed payload")
	var job := _food_arrive(fixture, order)
	_s01_point(fixture, 100.0)
	_check(fixture.actions.cancel_settlement_food_order(int(fixture.control), str(order.payload.settlement_id), str(order.id)).ok, "Current real head cancels its own actual food job")
	fixture.actions.settle_after_contacts()
	_check(order.status == "cancelled" and order.payload.spent == {"grain": 8} and order.payload.work_seconds == 100.0 and order.receipts.size() == 2 and not Technology.scope_known(Settlement.record(fixture.data).technology, "S06"), "Cancel retains real spend/progress and emits no completion receipt")
	_close_s01(fixture)
	await process_frame
	fixture = _food_fixture()
	order = _food_load(fixture)
	job = _food_arrive(fixture, order)
	_s01_point(fixture, 300.0, "death")
	_check(order.receipts.size() == 2 and order.payload.work_seconds == 300.0 and not Technology.scope_known(Settlement.record(fixture.data).technology, "S06"), "Contact-end death retains true spent prefix and refuses current knowledge receipt")
	_close_s01(fixture)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	var continuous := _food_positive([300.0])
	var partitioned := _food_positive([100.0, 200.0])
	_check(continuous.lab.character.fatigue == partitioned.lab.character.fatigue and Runtime.now(continuous.data) == Runtime.now(partitioned.data), "Original 300 and 100+200 partitions produce equal effort and clock")
	_close_s01(continuous)
	_close_s01(partitioned)
	await process_frame
	var cold := _food_fixture()
	var order := _food_load(cold)
	_food_arrive(cold, order)
	_s01_point(cold, 100.0)
	_food_cold(cold)
	_close_s01(cold)
	await process_frame
	await _food_negative()
	print("SITE_TECHNOLOGY_S06_FOOD_OWNER_PASS: %d checks; OWNER_PROBE_IF_CATALOG_DISABLED, true physical two-leg transfer/finite cap/shared PA timer/Scope/Store/bind; Native, actual travel, publicUI/full40 excluded" % checks)
	quit(0)
