extends "res://scripts/tests/site_technology_armor_recipes_test.gd"
## Genuine original residents/head/Army/Family and two real completed workshops.
## Each paid output consumes a true WorkTeam held prefix + original Fatigue pool.
## This isolated fixture excludes movement, Native contacts, formal UI/full Lab
## clock and full40 acceptance. S03/S05 require guarded enabled candidates.
const ProcessingStore = preload("res://scripts/terrain_lab/site_store.gd")

func _processing_fixture(known: bool) -> Dictionary:
	var fixture := _armor_fixture(false, false)
	var data: TerrainData = fixture.data
	data.site.family.technology.known = ["F03", "F04", "F06", "F14"]
	fixture.row.technology = Technology.learned_candidate(Technology.learned_candidate(fixture.row.technology, "F03"), "F06")
	data.site.settlement.technology.known = ["S03", "S05"] if known else []
	fixture.kiln = _cold_natural_feature(data, "charcoal", Vector2i(15, 29) + Vector2i(fixture.natural_offset))
	fixture.weaver = _cold_natural_feature(data, "weaver", Vector2i(24, 33) + Vector2i(fixture.natural_offset))
	# The weaver needs a water supply now; a real well beside it serves its demand.
	_cold_natural_feature(data, "well", Vector2i(24, 31) + Vector2i(fixture.natural_offset))
	Runtime.rebuild_water(data)
	data.site.inventory["wool"] = 12 # Explicit real starting-world camp stock (bracket write keeps a String key).
	_check(fixture.lab.character.place(Vector2i(9, 10) + Vector2i(fixture.natural_offset), true), "Actual head reaches original camp contact for the finite source grant")
	_check(Family.validate_family(data.site.family, str(data.site.id)), "Real fixture Family/person prerequisites use the original strict validator")
	return fixture

func _processing_point(fixture: Dictionary, seconds: float = 30.0) -> Dictionary:
	var lab: TerrainLab = fixture.lab
	var workers = lab.site_controller.work_team
	lab._shared_work_requests = workers.prepare_work_requests(seconds)
	_check(lab._refresh_shared_work_preflight().ok, "Actual current named source/task/skill revalidate before this original interval")
	var captured = workers.prepare_shared_work_prefix(seconds)
	var planned := PersonFatigue.plan_work_interval(lab._shared_work_requests, seconds)
	_check(captured.ok and planned.ok, "Original WorkTeam and pure Fatigue prepare the actual same-person interval")
	var priors: Array = []
	var before := var_to_bytes([lab.terrain.site, fixture.team.capture_combat_state()])
	var admitted = workers.validate_shared_work_prefix(captured, planned, priors)
	_check(admitted.ok and var_to_bytes([lab.terrain.site, fixture.team.capture_combat_state()]) == before, "Every real Runtime prefix candidate is pure before material/fatigue publication")
	lab._shared_work_plan = planned
	lab.site_controller._shared_work_plan = planned
	lab._shared_work_pools_committed = false
	lab._commit_shared_work_pools()
	workers.publish_shared_work_prefix(admitted)
	var state := var_to_bytes([lab.terrain.site, fixture.team.team_fatigue])
	workers.publish_shared_work_prefix(admitted)
	lab._commit_shared_work_pools()
	_check(var_to_bytes([lab.terrain.site, fixture.team.team_fatigue]) == state, "One genuine interval publishes pooled fatigue and physical work only once")
	workers.finish_shared_work_prefix(admitted)
	return admitted

func _processing_finish(fixture: Dictionary, key: String) -> void:
	var feature: Dictionary = fixture.data.site.features[key]
	_at_feature(fixture.lab, fixture.team, int(fixture.executor), key)
	var intervals := 0
	while feature.batch_paid and intervals < 200:
		_processing_point(fixture)
		intervals += 1
	_check(not feature.batch_paid, "Real original output endpoint ends this paid finite batch: production=%s water=%s" % [feature.get("production"), str(fixture.data.site.get("water_status", {}).get(key, {}))] + " preflight=" + str(Runtime.work_preflight(fixture.data, fixture.row.get("work_task", {}), fixture.row.get("cargo", {}), 40, 1, int(fixture.executor))).left(300) + " task=" + str(fixture.row.get("work_task", {}).get("status")) + " intervals=" + str(intervals))
	_check(not fixture.row.has("work_task") or fixture.row.work_task.is_empty(), "Actual original named worker stops after one batch")
	_check(not Runtime._feature_operation_active(fixture.data, key), "The original zone cannot automatically buy a fourth or third batch")

func _known_finite_batches() -> void:
	var fixture := _processing_fixture(true)
	var data: TerrainData = fixture.data
	var scope_id := str(fixture.settlement_id)
	for selection: Dictionary in [{"kind": "charcoal_batch", "key": fixture.kiln, "max": 3, "cost": {"wood": 4}, "output": "charcoal", "recipe": "controlled_fire", "seconds": 540.0}, {"kind": "textile_batch", "key": fixture.weaver, "max": 2, "cost": {"wool": 3}, "output": "cloth", "recipe": "wool_cloth", "seconds": 900.0}]:
		var before := var_to_bytes([data.site, fixture.row])
		var preview := Runtime.request_settlement_processing_order(data, str(selection.kind), str(selection.key), int(fixture.executor), int(selection.max), int(fixture.control), "", 0, true)
		_check(preview.ok and var_to_bytes([data.site, fixture.row]) == before, "True bounded adoption/source preview changes no original gameplay state")
		_check(not Runtime.request_settlement_processing_order(data, str(selection.kind), str(selection.key), int(fixture.executor), int(selection.max) + 1, int(fixture.control)).ok and var_to_bytes([data.site, fixture.row]) == before, "Caller cannot extend the finite configured batch quota")
		var requested := Runtime.request_settlement_processing_order(data, str(selection.kind), str(selection.key), int(fixture.executor), int(selection.max), int(fixture.control))
		_check(requested.ok, "Actual current head adopts the original usable local workshop and learned named worker")
		var order: Dictionary = data.site.settlement.technology_operations.orders[requested.order_id]
		var archive := var_to_bytes([data.site.family.technology, data.site.settlement.technology, fixture.row.technology])
		for index: int in int(selection.max):
			var stock = data.site.inventory.duplicate(true)
			var version := int(data.site.depot_items.version)
			var produced := int(fixture.row.cargo.get(selection.output, 0))
			var started := Runtime.begin_settlement_processing_operation(data, scope_id, str(requested.order_id))
			_check(started.ok and int(data.site.depot_items.version) == version + 1, "Each adopted real batch debits the original holder exactly once: " + str(started))
			for item: String in selection.cost: _check(int(data.site.inventory[item]) == int(stock[item]) - int(selection.cost[item]), "Actual complete per-batch %s input is paid once" % item)
			var feature: Dictionary = data.site.features[selection.key]
			_check(feature.recipe_id == selection.recipe and is_equal_approx(float(Runtime.feature_recipe(feature).cycle) * 60.0, float(selection.seconds)), "True original recipe uses one personal duration effect without an extra settlement multiplier")
			_check(Runtime.valid_settlement_processing_target(data, str(selection.key), feature), "Original strict active target/order link is valid")
			_processing_finish(fixture, str(selection.key))
			_check(int(fixture.row.cargo.get(selection.output, 0)) == produced + 2 and int(order.payload.completed) == index + 1 and order.receipts.size() == index + 1, "Actual paid output enters the real person's original cargo and bounded historical order once")
		_check(order.status == "completed" and order.payload.spent == order.payload.cap, "Only all real paid batches complete the original finite adoption order")
		before = var_to_bytes([data.site, fixture.row])
		_check(not Runtime.begin_settlement_processing_operation(data, scope_id, str(requested.order_id)).ok and var_to_bytes([data.site, fixture.row]) == before, "A completed finite original order cannot purchase another batch")
		_check(var_to_bytes([data.site.family.technology, data.site.settlement.technology, fixture.row.technology]) == archive, "Ordinary known operations do not create research evidence or teach another person")
	_cleanup_fixture(fixture.lab, fixture.team)
	await process_frame

func _pause_resume_and_guarded_source() -> void:
	var fixture := _processing_fixture(true)
	var data: TerrainData = fixture.data
	var key := str(fixture.kiln)
	var issued := Runtime.request_settlement_processing_order(data, "charcoal_batch", key, int(fixture.executor), 1, int(fixture.control))
	_check(issued.ok and Runtime.begin_settlement_processing_operation(data, str(fixture.settlement_id), str(issued.order_id)).ok, "Original finite source and named paid batch start")
	_at_feature(fixture.lab, fixture.team, int(fixture.executor), key)
	_processing_point(fixture)
	var progress := float(data.site.features[key].production)
	var stock = data.site.inventory.duplicate(true)
	var version := int(data.site.depot_items.version)
	_check(Runtime.stop_settlement_processing_order(data, str(fixture.settlement_id), str(issued.order_id), int(fixture.control)).ok, "Actual head pauses only this original named job")
	_check(progress > 0.0 and data.site.features[key].batch_paid and fixture.row.get("work_task", {}).is_empty(), "Pause retains original paid physical progress while removing the old named job")
	var order: Dictionary = data.site.settlement.technology_operations.orders[issued.order_id]
	var cap: Dictionary = order.payload.cap.duplicate(true)
	var spent: Dictionary = order.payload.spent.duplicate(true)
	_check(Runtime.grant_settlement_operation_source(data, str(fixture.settlement_id), str(issued.order_id), int(fixture.control), "", true).ok and order.payload.cap == cap and order.payload.spent == spent, "Explicit lawful source revocation never resets the finite cap or already-spent history")
	var source_before := var_to_bytes(data.site)
	_check(not Runtime.settlement_operation_material_source_candidate(data, str(fixture.settlement_id), str(issued.order_id)).ok and var_to_bytes(data.site) == source_before, "Revoked source cannot authorize a new payment")
	_check(Runtime.grant_settlement_operation_source(data, str(fixture.settlement_id), str(issued.order_id), int(fixture.control)).ok and order.payload.cap == cap and order.payload.spent == spent, "Original head at real camp contact can explicitly regrant the same finite source without replenishing budget")
	var technology: Dictionary = fixture.row.technology
	fixture.row.technology = {}
	var before := var_to_bytes([data.site, fixture.row])
	_check(not Runtime.begin_settlement_processing_operation(data, str(fixture.settlement_id), str(issued.order_id)).ok and var_to_bytes([data.site, fixture.row]) == before, "Loss of actual worker skill stops effect without free effort, source or knowledge mutation")
	fixture.row.technology = technology
	_check(Runtime.begin_settlement_processing_operation(data, str(fixture.settlement_id), str(issued.order_id)).ok and data.site.inventory == stock and int(data.site.depot_items.version) == version and is_equal_approx(float(data.site.features[key].production), progress), "Resume recreates a true original task without recharging or resetting paid progress")
	_processing_finish(fixture, key)
	var operations: Dictionary = data.site.settlement.technology_operations
	var damaged := operations.duplicate(true)
	damaged.orders[issued.order_id].payload.spent.wood = 100
	_check(not Settlement.valid_technology_operations(data, damaged), "Strict original cold validator rejects impossible cumulative spend")
	damaged = operations.duplicate(true)
	damaged.orders[issued.order_id].receipts.append(damaged.orders[issued.order_id].receipts[0].duplicate(true))
	_check(not Settlement.valid_technology_operations(data, damaged), "Duplicating an accepted current producer receipt cannot grant another finite batch")
	_cleanup_fixture(fixture.lab, fixture.team)
	await process_frame

func _true_scope_research_batches() -> void:
	var fixture := _processing_fixture(false)
	var data: TerrainData = fixture.data
	var scope_id := str(fixture.settlement_id)
	for selection: Dictionary in [{"tech": "S03", "kind": "charcoal_batch", "key": fixture.kiln, "count": 3, "binding": "charcoal", "spent": {"wood": 12}}, {"tech": "S05", "kind": "textile_batch", "key": fixture.weaver, "count": 2, "binding": "wool_cloth", "spent": {"wool": 6}}]:
		_check(fixture.actions.prepare_scope_technology(int(fixture.control), int(fixture.executor), str(selection.tech), scope_id).ok, "True unknown settlement technology project uses existing person/head/Family prerequisites")
		var project := Technology.active_project(data.site.settlement.technology)
		_check(fixture.actions.request_scope_technology_consent(int(fixture.control), "settlement", scope_id, int(fixture.executor)).ok, "Actual original team accepts only this immutable research purpose")
		var issued := Runtime.request_settlement_processing_order(data, str(selection.kind), str(selection.key), int(fixture.executor), int(selection.count), int(fixture.control), "", int(project.id))
		_check(issued.ok, "Original finite workshop adoption is legal while the corresponding settlement method is still unknown")
		for index: int in int(selection.count):
			var started = fixture.actions.begin_scope_technology_phase(int(fixture.control), "settlement", scope_id, str(selection.binding), "feature:" + str(selection.key), {"order_id": str(issued.order_id)})
			_check(started.ok, "Actual Scope phase binds its unique adopted order and full original per-batch payment")
			_processing_finish(fixture, str(selection.key))
			for actual: Dictionary in data.site.settlement.technology.projects:
				if int(actual.id) == int(project.id): project = actual; break
			_check(project.receipts.size() == index + 1 and project.budget.payments.size() == index + 1, "Only the real named paid output contributes one research phase")
		_check(Technology.scope_known(data.site.settlement.technology, str(selection.tech)) and project.budget.spent == selection.spent, "Exact real repeated outputs close original settlement knowledge without a shortcut")
		_check(not Technology.learned(fixture.row.technology, str(selection.tech)), "Settlement adoption remains institutional knowledge")
	_cleanup_fixture(fixture.lab, fixture.team)
	await process_frame

func _paid_history_survives_source_demolition() -> void:
	var fixture := _processing_fixture(false)
	var data: TerrainData = fixture.data
	var scope_id := str(fixture.settlement_id)
	var actions: SitePersonActions = fixture.actions
	_check(actions.prepare_scope_technology(int(fixture.control), int(fixture.executor), "S03", scope_id).ok, "Actual original S03 project prepares before workshop adoption")
	var project_id := int(Technology.active_project(data.site.settlement.technology).id)
	_check(actions.request_scope_technology_consent(int(fixture.control), "settlement", scope_id, int(fixture.executor)).ok, "The real original team accepts this named source/history test purpose")
	_check(Stocks.ensure_storage(data, str(fixture.warehouse), 1).ok, "Original Stockpiles owns the genuine named Warehouse source")
	var actor: Dictionary = actions._person(int(fixture.control))
	actor.cargo.clear()
	actor.cargo.wood = 4 # Actual bounded starting-person stock, then true transfer.
	var stock := Stocks.storage(data, str(fixture.warehouse))
	_check(fixture.lab.character.place(data.cell_from_index(int(data.site.features[fixture.warehouse].entrance)), true), "True head/grantor contacts the original Warehouse")
	_check(fixture.lab.site_controller.vehicles.transfer("person:" + str(fixture.control), "feature:" + str(fixture.warehouse), {"wood": 4}, [], int(actor.holder.version), int(stock.holder.version), int(fixture.control)).ok, "Actual source funding transfers four real wood once, without paying manufacture")
	var issued := Runtime.request_settlement_processing_order(data, "charcoal_batch", str(fixture.kiln), int(fixture.executor), 3, int(fixture.control), str(fixture.warehouse), project_id)
	_check(issued.ok, "Real contact grants finite three-batch cap without reserving nonexistent future wood")
	var camp = data.site.inventory.duplicate(true)
	_check(actions.begin_scope_technology_phase(int(fixture.control), "settlement", scope_id, "charcoal", "feature:" + str(fixture.kiln), {"order_id": str(issued.order_id)}).ok and stock.cargo.is_empty() and data.site.inventory == camp, "Actual private manufacture debits the real Warehouse once and leaves camp unchanged")
	_at_feature(fixture.lab, fixture.team, int(fixture.executor), str(fixture.kiln))
	_processing_point(fixture)
	var feature: Dictionary = data.site.features[fixture.kiln]
	var token: Dictionary = feature.tech_trial
	var paid: Dictionary = feature.tech_batch.duplicate(true)
	var progress := float(feature.production)
	_check(fixture.lab.site_controller.work_team.cancel(int(fixture.executor)).ok, "Original work owner removes the old task while preserving true paid target progress")
	Runtime._stop_feature_zones(data, str(fixture.kiln), "operate")
	_check(Runtime.cancel_feature(data, str(fixture.warehouse), Callable(), 1).ok, "Original faction legally demolishes the now-empty source after the real payment")
	_check(Runtime.settlement_operation_paid_source_candidate(data, token, str(issued.order_id)).ok and Runtime.validate_technology_target_storage(data, str(fixture.kiln), feature).ok, "True immutable original payment history remains provable without the former live holder")
	fixture.lab.site_controller._capture_positions()
	_check(ProcessingStore.save(data, "user://technology_processing_paid_source_removed.json").ok, "Original Store accepts the legal original paid history after source demolition")
	var source_fingerprint := data.fingerprint()
	var source_conditions := _cold_natural_conditions(data)
	var restored := ProcessingStore.load_site("user://technology_processing_paid_source_removed.json")
	_check(restored.ok, "Strict original loader does not reimpose live-source availability on paid history")
	_check(restored.data.fingerprint() == source_fingerprint and _cold_natural_conditions(restored.data) == source_conditions, "Actual paid-history Store replay reconstructs the same natural terrain and all five land conditions")
	var before := var_to_bytes([data.site, fixture.row])
	_check(not Runtime.settlement_operation_material_source_candidate(data, scope_id, str(issued.order_id), "charcoal").ok and var_to_bytes([data.site, fixture.row]) == before, "A new payment still rejects the missing real source without camp fallback")
	var resumed := Runtime.begin_technology_operation(data, token, false, {"order_id": str(issued.order_id)})
	_check(resumed.ok and feature.tech_batch == paid and is_equal_approx(float(feature.production), progress) and data.site.inventory == camp, "True paid resume recreates a named original task without double cost, attempt or progress reset")
	_processing_finish(fixture, str(fixture.kiln))
	var project := Technology.active_project(data.site.settlement.technology)
	_check(project.receipts.size() == 1 and project.budget.payments.size() == 1 and project.budget.spent == {"wood": 4} and not Technology.scope_known(data.site.settlement.technology, "S03"), "The original current endpoint accepts exactly this real output/payment history and no imaginary remaining batches")
	_cleanup_fixture(fixture.lab, fixture.team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	await _known_finite_batches()
	await _pause_resume_and_guarded_source()
	await _true_scope_research_batches()
	await _paid_history_survives_source_demolition()
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_SETTLEMENT_PROCESSING_PASS: %d checks; original finite S03/S05 paid batches, genuine WorkTeam/Fatigue prefixes, pause/reassign, strict finite receipts and real repeated Scope phases; Native/whole Lab/formal UI/all40 excluded" % checks)
	quit(0)
