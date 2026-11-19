extends "res://scripts/tests/site_technology_nation_material_test.gd"
## Actual original controlled donor, two real Vehicle transfers and the original
## nation_administration job/Fatigue planner. This is not a whole Lab/Native run.
const NationFatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
const NationCatalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")

func _original_admin_point(lab: TerrainLab, seconds: float) -> Dictionary:
	var actions = lab.site_controller.person_actions
	var requests = actions.work_requests(seconds)
	var planned := NationFatigue.plan_work_interval(requests, seconds)
	_check(planned.ok, "Original planner admits only the original PA job and body pools")
	for pool: Dictionary in planned.pools:
		if float(pool.effort_seconds) <= 0.0: continue
		NationFatigue.write(pool.body, "fatigue", float(pool.fatigue))
		NationFatigue.write(pool.body, "fatigue_rest", float(pool.fatigue_rest))
	actions.advance(seconds, {"jobs": planned.jobs.get("person_actions", {})})
	var results = actions.settle_after_contacts()
	return {"plan": planned, "results": results}

func _finish_original_admin(lab: TerrainLab, identity: int) -> void:
	var actions = lab.site_controller.person_actions
	var points := 0
	while actions.is_busy(identity) and points < 30:
		_check(Time.get_ticks_msec() < deadline, "Real original administration finishes inside the internal deadline")
		_original_admin_point(lab, 30.0)
		points += 1
	_check(points < 30 and not actions.is_busy(identity), "Original admitted effective work reaches the genuine job endpoint")

func _procurement_fixture() -> Dictionary:
	var data := _building_fixture()
	var warehouse := _formal_feature(data, "warehouse", Vector2i(13, 13))
	var lab := _building_lab(data)
	var actions = lab.site_controller.person_actions
	var orders = lab.site_controller.equipment_orders
	var control := int(lab.controlled_person_id())
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", control),
		"members": [control, int(lab.npc.person_id)], "standards": {}, "technology": Technology.empty_scope_record(str(data.site.id))}}
	_check(Stocks.ensure_storage(data, warehouse, 1).ok, "True original Warehouse owns its stock endpoint")
	_check(lab.character.place(data.cell_from_index(int(data.site.features[warehouse].entrance)), true), "True donor stands at the original warehouse contact")
	_check(bool(NationCatalog.get_node("N01").get("enabled", false)), "Positive execution requires Root's isolated enabled N01 candidate, never a formal flag change")
	_check(actions.prepare_scope_technology(control, control, "N01", "n1").ok and actions.request_scope_technology_consent(control, "nation", "n1", control).ok,
		"True current national research duty prepares first N01 with an initially empty archive")
	var person = actions._person(control)
	person.cargo.clear() # Explicit finite initial fixture stock; no transfer bypass.
	person.cargo.wood = 2
	person.cargo.grain = 2
	var limits := {"wood": {"batch": 1, "total": 2}, "grain": {"batch": 1, "total": 2}}
	_check(orders.publish_procurement_spec(control, "n1", "measure", "兩次本原人的有限採購", warehouse, limits, {}).ok,
		"True original procurement duty declares the finite two-delivery specification")
	return {"data": data, "lab": lab, "actions": actions, "orders": orders, "control": control,
		"warehouse": warehouse, "person": person, "stock": Stocks.storage(data, warehouse)}

func _procurement_bytes(f: Dictionary) -> PackedByteArray:
	return var_to_bytes([f.data.site, f.lab.character.capture_state(), f.actions._jobs.keys()])

func _earned_nation_cleanup(lab: TerrainLab, team: TerrainArmy = null) -> void:
	var controller := lab.site_controller
	for identity: int in controller.work_team.active_ids(): controller.work_team.cancel(identity)
	controller.work_team.discard_prepared_interval()
	controller.work_team.unavailable = Callable()
	controller.work_team.vehicle_blocked = Callable()
	controller.equipment_orders.nation_arsenal_request = Callable()
	controller.equipment_orders.nation_owner_receipt_query = Callable()
	if team != null:
		team.controlled_person_query = Callable()
		team.person_busy_query = Callable()
		team.queue_free()
	lab.queue_free()

func _n01_real_two_deliveries() -> void:
	var f := _procurement_fixture()
	var nation: Dictionary = f.data.site.equipment_nations.n1
	var operations: Dictionary = nation.technology_operations
	var spec: Dictionary = operations.specs.measure
	var initial_source_version := int(f.person.holder.version)
	var initial_destination_version := int(f.stock.holder.version)
	var before := _procurement_bytes(f)
	_check(not f.orders.accept_procurement_delivery(f.control, "n1", "measure", {"wood": 1, "grain": 1}, [], initial_source_version + 1, initial_destination_version, "stale").ok
		and _procurement_bytes(f) == before, "Stale true source CAS rejects before stock, Scope attempt, spec or job changes")
	_check(f.orders.accept_procurement_delivery(f.control, "n1", "measure", {"wood": 1, "grain": 1}, [], initial_source_version, initial_destination_version, "delivery_1").ok,
		"First genuine original transfer delivers one wood and one grain")
	var project := Technology.active_project(nation.technology)
	_check(is_same(operations, nation.technology_operations) and is_same(spec, operations.specs.measure) and spec.receipts.size() == 1,
		"Original Nops/spec refs survive the first publication")
	_check(project.next_attempt == 2 and project.budget.payments.is_empty() and project.receipts.is_empty() and not f.actions.is_busy(f.control),
		"First physical delivery reserves one original attempt but does not manufacture a payment, effort or research receipt")
	_check(f.person.cargo.wood == 1 and f.person.cargo.grain == 1 and f.stock.cargo.wood == 1 and f.stock.cargo.grain == 1,
		"True original donor and Warehouse conserve the first real batch")
	var people := {int(f.control): true, int(f.lab.npc.person_id): true}
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(f.data.site))
	_check(Orders.validate_nation_operations(f.data, decoded, people).ok and Orders.normalize_nation_operations(decoded).ok,
		"Partial original token/project/spec references survive strict JSON admission and normalization, without a second saved job queue")
	var malformed: Dictionary = decoded.equipment_nations.n1.technology_operations.specs.measure.duplicate(true)
	malformed.receipts = [1]
	_check(not Orders._valid_procurement_spec(malformed, f.data.site.item_definitions, people), "Malformed receipt element rejects before typed field access")
	malformed = decoded.equipment_nations.n1.technology_operations.specs.measure.duplicate(true)
	malformed.tech_trial.permission = true
	_check(not Orders._valid_procurement_spec(malformed, f.data.site.item_definitions, people), "An extra caller permission cannot enter the immutable token")
	before = _procurement_bytes(f)
	_check(f.orders.accept_procurement_delivery(f.control, "n1", "measure", {"wood": 1, "grain": 1}, [], initial_source_version, initial_destination_version, "delivery_1").code == "NO_CHANGE"
		and _procurement_bytes(f) == before, "Duplicate delivery key cannot double-transfer or reserve another attempt")
	var filler := Stocks.capacity(f.data.site.features[f.warehouse]) - int(Runtime.carried_load(f.data.site, f.stock.cargo, f.stock.holder))
	f.stock.cargo.clay = filler
	before = _procurement_bytes(f)
	_check(not f.orders.accept_procurement_delivery(f.control, "n1", "measure", {"wood": 1, "grain": 1}, [], int(f.person.holder.version), int(f.stock.holder.version), "delivery_2").ok
		and _procurement_bytes(f) == before, "Full original Warehouse rejects the second transfer, Scope payment and 300-second job together")
	f.stock.cargo.erase("clay")
	_check(f.orders.accept_procurement_delivery(f.control, "n1", "measure", {"wood": 1, "grain": 1}, [], int(f.person.holder.version), int(f.stock.holder.version), "delivery_2").ok,
		"Second genuine original transfer and one full Scope payment commit together")
	project = Technology.active_project(nation.technology)
	var job: Dictionary = f.actions._jobs[str(f.control)]
	_check(project.next_attempt == 2 and project.budget.payments.size() == 1 and project.budget.spent == {"wood": 2, "grain": 2}
		and project.budget.holder == "nation-order:" + JSON.stringify([str(f.data.site.id), "n1", "procurement:measure"]),
		"Exactly one immutable original payment accounts for both already-transferred physical deliveries")
	_check(job.kind == "nation_administration" and job.duration == 300.0 and is_same(job.nation_order_ref, spec)
		and f.person.cargo.is_empty() and f.stock.cargo.wood == 2 and f.stock.cargo.grain == 2,
		"Same original spec starts the original 300-second job; material movement happens only twice")
	_check(int(f.person.holder.version) == initial_source_version + 2 and int(f.stock.holder.version) == initial_destination_version + 2
		and not Technology.scope_known(nation.technology, "N01"), "No third physical debit or premature knowledge occurs")
	_original_admin_point(f.lab, 30.0)
	_check(float(job.elapsed) > 0.0 and float(job.elapsed) < 300.0 and not Technology.scope_known(nation.technology, "N01"), "Only actual original planned work advances administration")
	_check(f.actions.cancel(f.control).ok and not Technology.scope_known(nation.technology, "N01"), "Original cancellation keeps paid deliveries without awarding knowledge")
	before = _procurement_bytes(f)
	_check(not f.actions.begin_nation_administration(int(f.lab.npc.person_id), "n1", "procurement:measure", "procurement").ok and _procurement_bytes(f) == before,
		"Noncontrolled person cannot impersonate the actual national duty")
	_check(f.lab.site_controller._nation_ui_command("n1", "administration_spec", {"spec": "measure"}).ok, "The original public form resumes stopped administration from its true spec and existing payment, with empty donor cargo")
	job = f.actions._jobs[str(f.control)]
	_check(job.elapsed == 0.0 and Technology.active_project(nation.technology).budget.payments.size() == 1 and Technology.active_project(nation.technology).next_attempt == 2,
		"Restart changes neither Scope payment nor attempt and does not repeat delivery")
	var conserved := var_to_bytes([f.person.cargo, f.person.holder, f.stock.cargo, f.stock.holder])
	_finish_original_admin(f.lab, f.control)
	_check(Technology.scope_known(nation.technology, "N01") and nation.technology.projects[0].receipts.size() == 1
		and is_equal_approx(float(nation.technology.projects[0].receipts[0].work_seconds), 300.0) and not spec.has("tech_trial"),
		"Two real deliveries plus genuine effective 300 seconds earn first N01 once; the temporary source token is released")
	_check(var_to_bytes([f.person.cargo, f.person.holder, f.stock.cargo, f.stock.holder]) == conserved, "Administration receipt never re-debits already-delivered materials")
	before = _procurement_bytes(f)
	_check(not f.actions.begin_nation_administration(f.control, "n1", "procurement:measure", "procurement").ok and _procurement_bytes(f) == before,
		"Completed first research cannot replay its historical deliveries to earn a second receipt")
	_earned_nation_cleanup(f.lab)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	await _n01_real_two_deliveries()
	TerrainArmy.release_contact_source()
	print("N01_ORIGINAL_TWO_DELIVERIES_ADMIN_EARNED_FIXTURE_PASS: checks=", checks, "; real transfers + original PA/Fatigue; no Native/whole-Lab/Region/full40 acceptance")
	quit(0)
