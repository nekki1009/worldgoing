extends "res://scripts/tests/site_nation_first_earned_base.gd"
## N10 starts unknown with N02/N09 as prior-world institutions. Genuine fixed
## World/Slot main steps expire and renew the current local head's finite mandate.
## No test writes logical_game_seconds, a pin, elapsed, an office or an approval.

func _run() -> void:
	var f := _earned_fixture("N10", true)
	_earned_speed(f)
	_check(f.executor == f.control and Settlement.head_executor(f.lab) == f.control and Settlement.residents(f.lab).has(f.control),
		"The same real original Actor is legally housed, currently local head and the first project's executor")
	_earned_prepare(f, "N10")
	var slot: RegionSaveSlot = f.controller.region_slot
	var original_pin: Dictionary = slot.pin.duplicate(true)
	var world_begin := float(slot.control.logical_game_seconds)
	var before := _earned_bytes(f)
	_check(not f.controller._nation_ui_command("n1", "mandate", {"local": f.team.combat_identity(1), "minutes": 60.0}).ok and _earned_bytes(f) == before,
		"A resident NPC cannot impersonate the current original local head or acquire an office from this form")
	var granted: Dictionary = f.controller._nation_ui_command("n1", "mandate", {"local": f.control, "minutes": 0.1})
	_check(granted.ok, "Original national form gives only this actual local head a finite six-World-second task: " + str(granted))
	var order_id := str(granted.order_id)
	var operations: Dictionary = f.nation.technology_operations
	var order: Dictionary = operations.public_orders[order_id]
	var project := Technology.active_project(f.nation.technology)
	var purpose := str(project.purpose)
	_check(order.project_id == project.id and order.payload.local_person_id == f.executor and order.payload.expires_game_seconds == world_begin + 6.0
		and order.payload.clock_ref == {"world_instance_id": str(original_pin.world_instance_id), "slot_id": str(original_pin.slot_id)},
		"The real original order binds its project/person/current office revision and actual immutable Slot identity")
	before = _earned_bytes(f)
	_check(not f.controller._nation_ui_command("n1", "construction", {"order": order_id, "x": 30, "y": 25}).ok and _earned_bytes(f) == before,
		"Mandate cannot skip its genuine300 administration phase")
	_check(f.controller._nation_ui_command("n1", "administration", {"order": order_id}).ok, "Original first mandate administration starts on that same true Actor")
	var expired_job: Dictionary = f.actions._jobs[str(f.executor)]
	_check(expired_job.duration == 300.0 and is_same(expired_job.nation_order_ref, order), "Original PA holds the SAME finite order and a real300 job")
	var accepted_seconds := 0.0
	var points := 0
	while float(slot.control.logical_game_seconds) < float(order.payload.expires_game_seconds):
		var step := _earned_true_step(f)
		accepted_seconds += float(step.game_seconds)
		points += 1
		_check(points < 50, "Actual main-step expiry is finite without assigning any World seconds")
	_check(absf(float(slot.control.logical_game_seconds) - world_begin - accepted_seconds) < 0.000001 and slot.pin == original_pin,
		"Only completed original common points advanced the true World clock once; the real pin remains unchanged")
	_check(not f.orders._mandate_effective(order) and not Technology.scope_known(f.nation.technology, "N10")
		and Technology.active_project(f.nation.technology).receipts.is_empty() and float(expired_job.elapsed) < 300.0,
		"Actual expiry rejects endpoint authority while retaining only previously admitted effort, no institution or road receipt")
	if f.actions.is_busy(f.executor): _check(f.actions.cancel(f.executor).ok, "Original human cancellation releases the expired actual job without granting a receipt")
	_earned_cold(f, "N10", false)
	before = _earned_bytes(f)
	_check(not f.controller._nation_ui_command("n1", "administration", {"order": order_id}).ok and _earned_bytes(f) == before,
		"Expired original mandate cannot start new work or payment")
	before = _earned_bytes(f)
	_check(not f.controller._nation_ui_command("n1", "construction", {"order": order_id, "x": 30, "y": 25}).ok and _earned_bytes(f) == before,
		"Expired original mandate cannot debit materials, create road geometry or publish controlled work")
	var payments_before = Technology.active_project(f.nation.technology).budget.payments.size()
	var renewed: Dictionary = f.controller._nation_ui_command("n1", "renew_mandate", {"order": order_id, "local": f.control, "minutes": 60.0})
	_check(renewed.ok and is_same(f.nation.technology_operations, operations) and is_same(operations.public_orders[order_id], order)
		and f.orders._mandate_effective(order) and Technology.active_project(f.nation.technology).purpose == purpose,
		"Actual national form renews the SAME order/current local head and original research purpose using the current real World time")
	_check(Technology.active_project(f.nation.technology).budget.payments.size() == payments_before and order.receipts.is_empty(),
		"Renewal itself creates no material payment, clock jump or research receipt")
	_check(f.controller._nation_ui_command("n1", "administration", {"order": order_id}).ok, "Same current local head explicitly restarts actual administration under the renewed real deadline")
	_earned_until_idle(f)
	project = Technology.active_project(f.nation.technology)
	_check(project.receipts.size() == 1 and project.receipts[0].phase_id == "grant_limited_original_settlement_mandate" and is_equal_approx(float(project.receipts[0].work_seconds), 300.0)
		and order.receipts.size() == 1 and not Technology.scope_known(f.nation.technology, "N10"), "Actual300 current mandate work earns only the first phase")
	_earned_depot_grant(f, {"stone": 1})
	var geometry := _earned_road_preview(f, Vector2i(30, 25))
	var road_cell: Vector2i = geometry.fixture_cell
	var stone := int(f.data.site.inventory.stone)
	var next_feature := int(f.data.site.next_feature)
	before = _earned_bytes(f)
	_check(not f.controller._nation_ui_command("n1", "construction", {"order": order_id, "x": road_cell.x, "y": road_cell.y}).ok and _earned_bytes(f) == before,
		"Actual controlled executor outside the original prospective work station rejects the entire paid start")
	_check(_earned_place_controlled(f.lab, f.data.cell_from_index(int(geometry.entrance))), "The same true original Actor reaches the actual road construction entrance; no automatic worker replacement")
	var built: Dictionary = f.controller._nation_ui_command("n1", "construction", {"order": order_id, "x": road_cell.x, "y": road_cell.y})
	_check(built.ok and f.data.site.inventory.stone == stone - 1 and f.data.site.next_feature == next_feature + 1,
		"Actual one-cell road and one original material payment start together: " + str(built))
	var feature: Dictionary = f.data.site.features[str(next_feature)]
	var controlled_job: Dictionary = f.actions._jobs[str(f.executor)]
	_check(controlled_job.kind == "technology_feature" and is_same(controlled_job.feature_ref, feature) and controlled_job.work_task.operation_ref == {"nation_id": "n1", "order_id": order_id}
		and is_same(controlled_job.zone_ref, f.data.site.zones[int(controlled_job.work_task.zone)]), "The original PA job/feature/zone are the SAME paid original operation; job elapsed cannot produce a road")
	_earned_until_idle(f)
	_check(feature.stage == "complete" and Technology.scope_known(f.nation.technology, "N10") and f.nation.technology.projects[0].receipts.size() == 2
		and is_equal_approx(float(f.nation.technology.projects[0].receipts[1].work_seconds), 180.0) and order.status == "complete" and order.receipts.size() == 2,
		"Actual current mandate300 plus real original controlled road180 earn N10 once, with Scope/Nops/geometry in the same successful tail")
	_check(f.data.site.inventory.stone == stone - 1 and float(slot.control.logical_game_seconds) > world_begin + 480.0 and slot.pin == original_pin,
		"Actual World time includes the expired prefix/restarted productive work, without a duplicate stone debit or fake clock")
	_earned_cold(f, "N10")
	before = _earned_bytes(f)
	_check(not f.controller._nation_ui_command("n1", "renew_mandate", {"order": order_id, "local": f.control, "minutes": 60.0}).ok and _earned_bytes(f) == before,
		"Completed first mandate cannot replay its accepted evidence or grant another identical original task")
	_earned_finish()
	await process_frame
	print("N10_FIRST_EARNED_TRUE_SLOT_MANDATE_FIXTURE_PASS: checks=", checks, "; actual fixed World/Slot expiry-renewal + original300/180 GD point; NOT Native/GPU/performance/full40 acceptance")
	quit(0)
