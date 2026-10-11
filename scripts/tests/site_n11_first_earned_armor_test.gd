extends "res://scripts/tests/site_nation_first_earned_base.gd"
## N11 route=armor starts unknown. Real original grade3 smithy/tannery in a
## legally upgraded level3 settlement; only N04/S13/F04 are prior inputs.
## Actual finite public order transfer -> real armor900 -> original acceptance300.
## This entry does not claim the separate S11/ballista5400 alternative.

func _run() -> void:
	var f := _earned_fixture("N11", false, true)
	_earned_speed(f)
	_check(Settlement.status(f.lab).level == 3 and Settlement.status(f.lab).effective and Settlement.residents(f.lab).size() == 40
		and Runtime.building_grade(f.data.site.features[f.smithy]) == 3 and Runtime.building_grade(f.data.site.features[f.tannery]) == 3,
		"Actual original upgrades, forty real housing relations and both grade3 real workshops meet S13's physical industry requirements")
	_earned_prepare(f, "N11", "armor")
	_check(f.team._member_can_serve(f.team.index_for_identity(int(f.executor))), "The named N11 operator is present within the team's own command radius before the job")
	var cap := {"iron": 4, "leather": 2, "charcoal": 2}
	var learned: Dictionary = f.row.technology
	f.row.technology = {}
	var before := _earned_bytes(f)
	var unskilled: Dictionary = f.controller._nation_ui_command("n1", "arsenal", {"arsenal_route": "armor", "host": f.smithy, "operator": f.executor, "reserve": f.warehouse})
	_check(not unskilled.ok and str(unskilled.code) == "NO_SKILL"
		and _earned_bytes(f) == before, "Actual unskilled operator fails NO_SKILL at the already valid real Warehouse destination without borrowing S13/N04 archives")
	f.row.technology = learned
	before = _earned_bytes(f)
	_check(not f.controller._nation_ui_command("n1", "arsenal", {"arsenal_route": "siege", "host": f.smithy, "operator": f.executor, "reserve": f.warehouse}).ok
		and _earned_bytes(f) == before, "Explicit armor-route first project cannot silently substitute the absent S11/ballista route")
	var registered: Dictionary = f.controller._nation_ui_command("n1", "arsenal", {"arsenal_route": "armor", "host": f.smithy, "operator": f.executor, "reserve": f.warehouse})
	_check(registered.ok, "True public arsenal form previews the same actual qualified smithy before granting or paying anything: " + str(registered))
	var order_id := str(registered.order_id)
	var operations: Dictionary = f.nation.technology_operations
	var order: Dictionary = operations.public_orders[order_id]
	var project := Technology.active_project(f.nation.technology)
	_check(order.project_id == project.id and order.payload.operator_id == f.executor and order.payload.host_id == f.smithy
		and not order.payload.consents.is_empty() and project.budget.is_empty() and order.receipts.is_empty(), "Original first order/project/operator/real consent exist without a manufactured permission/source/output")
	before = _earned_bytes(f)
	_check(not f.controller._nation_ui_command("n1", "administration", {"order": order_id}).ok and _earned_bytes(f) == before,
		"Acceptance300 cannot precede actual paid armor output")
	before = _earned_bytes(f)
	_check(not f.controller._nation_ui_command("n1", "begin_arsenal", {"order": order_id}).ok and _earned_bytes(f) == before,
		"Abundant camp stocks cannot conceal an unfunded finite private arsenal source")
	_check(Stocks.ensure_storage(f.data, f.warehouse, 1).ok, "Original Warehouse owns the actual finite physical endpoint")
	var reserve := Stocks.storage(f.data, f.warehouse)
	var person: Dictionary = f.actions._person(f.control)
	_check(f.lab.character.place(f.data.cell_from_index(int(f.data.site.features[f.warehouse].entrance)), true), "The actual controlled donor reaches the actual original Warehouse contact")
	for resource: String in cap: person.cargo[resource] = int(person.cargo.get(resource, 0)) + int(cap[resource]) # Explicit finite initial donor stock.
	_check(f.controller._nation_ui_command("n1", "grant_source", {"order": order_id, "resources": cap}).ok, "Original donor explicitly authorizes exactly one finite armor purpose")
	var donor_version := int(person.holder.version)
	var warehouse_version := int(reserve.holder.version)
	before = _earned_bytes(f)
	_check(not f.orders.fund_public_order(f.control, "n1", order_id, cap, donor_version + 1, warehouse_version).ok and _earned_bytes(f) == before,
		"Stale actual donor CAS refuses the original transfer, order spent, Scope grant and batch together")
	_check(f.controller._nation_ui_command("n1", "fund", {"order": order_id, "resources": cap}).ok, "Public fund form performs the true original physical donor-to-Warehouse transfer")
	_check(int(person.holder.version) == donor_version + 1 and int(reserve.holder.version) == warehouse_version + 1
		and order.payload.source.spent == cap and Technology.active_project(f.nation.technology).budget.is_empty(), "Original funding conserves real stock and is distinct from manufacture Scope payment")
	var selection: Dictionary = f.actions._nation_phase_token("n1", order_id, "iron_armor", "feature:" + f.smithy)
	_check(selection.ok and not selection.token.is_empty(), "First research derives its token only from the actual stored order and same current Scope phase")
	var source: Dictionary = f.actions.technology_phase_material_source_candidate(selection.token)
	_check(source.ok and source.source.size() == 13 and is_same(source.source.physical_holder, reserve.holder) and is_same(source.source.physical_cargo, reserve.cargo),
		"The original source provider identifies the actual raw13 source/physical holder/cargo rather than a caller paid flag")
	var host: Dictionary = f.data.site.features[f.smithy]
	var next_item := int(f.data.site.next_item)
	var iron := int(f.data.site.inventory.iron)
	var charcoal := int(f.data.site.inventory.charcoal)
	var physical_version := int(reserve.holder.version)
	var started: Dictionary = f.controller._nation_ui_command("n1", "begin_arsenal", {"order": order_id})
	_check(started.ok and is_same(f.data.site.features[f.smithy], host) and host.recipe_id == "iron_armor" and host.batch_paid,
		"Actual original recipe, SAME host/zone, named worker, private debit and Scope accounting start atomically: " + str(started))
	project = Technology.active_project(f.nation.technology)
	_check(project.budget.spent == cap and project.budget.payments.size() == 1 and int(reserve.holder.version) == physical_version + 1
		and int(reserve.cargo.get("iron", 0)) == 0 and int(reserve.cargo.get("leather", 0)) == 0 and int(reserve.cargo.get("charcoal", 0)) == 0
		and f.data.site.inventory.iron == iron and f.data.site.inventory.charcoal == charcoal, "Exactly one real new manufacture consumes the same original Warehouse stock, not unrelated camp material or donor twice")
	_at_feature(f.lab, f.team, f.executor, f.smithy)
	_check(Runtime.technology_existing_paid_phase_source(f.data, host.tech_trial).ok and float(Runtime.feature_recipe(host).cycle) * 60.0 == 900.0,
		"Actual original paid target has the canonical historical source proof and genuine900 cycle")
	before = _earned_bytes(f)
	_check(not f.controller._nation_ui_command("n1", "begin_arsenal", {"order": order_id}).ok and _earned_bytes(f) == before,
		"Started arsenal order cannot pay its finite material purpose twice")
	_earned_until_idle(f)
	var output: Dictionary = host.technology_output.receipts[0]
	project = Technology.active_project(f.nation.technology)
	_check(f.data.site.next_item == next_item + 1 and output.item_ids == [str(next_item)] and f.data.site.item_records[str(next_item)].definition == "armor:armor_iron_01"
		and f.row.item_state.item_ids.has(str(next_item)) and f.row.work_task.is_empty() and not host.batch_paid, "Real ItemSeq creates one actual armor item on the actual original named worker, then ends this batch")
	_check(project.receipts.size() == 1 and project.receipts[0].phase_id == "one_real_iron_armor_order" and is_equal_approx(float(project.receipts[0].work_seconds), float(order.receipts[0].work_seconds))
		and is_equal_approx(float(order.receipts[0].get("effective_seconds", order.receipts[0].work_seconds)), 900.0)
		and order.receipts.size() == 1 and order.receipts[0].item_ids == [str(next_item)] and not Technology.scope_known(f.nation.technology, "N11"), "True900 effective armor output (grade-3 work at its building productivity) earns only the first Scope/public phase, never an invented ready-product receipt")
	_earned_cold(f, "N11", false)
	var paid_stock := var_to_bytes([reserve.cargo, reserve.holder, person.cargo, person.holder])
	_check(f.controller._nation_ui_command("n1", "administration", {"order": order_id}).ok, "Actual public acceptance form begins the original300 job bound to this actual original armor item")
	var job: Dictionary = f.actions._jobs[str(f.executor)]
	_check(job.kind == "nation_administration" and job.duration == 300.0 and job.nation_items == [str(next_item)] and is_same(job.nation_order_ref, order),
		"The same original operator/order/item are rechecked by the real acceptance job")
	_check(f.actions.save_guard().code == "BUSY" and not Technology.scope_known(f.nation.technology, "N11"), "Pending original acceptance cannot be cold-saved as a parallel timer or grant early knowledge")
	_earned_true_step(f)
	_check(float(job.elapsed) > 0.0 and float(job.elapsed) < 300.0 and not Technology.scope_known(f.nation.technology, "N11"), "One real shared point is insufficient to counterfeit acceptance300")
	_earned_until_idle(f)
	_check(Technology.scope_known(f.nation.technology, "N11") and f.nation.technology.projects[0].receipts.size() == 2
		and f.nation.technology.projects[0].receipts[1].phase_id == "armor_acceptance" and is_equal_approx(float(f.nation.technology.projects[0].receipts[1].work_seconds), 300.0)
		and order.status == "complete" and order.receipts.size() == 2 and order.receipts[1].item_ids == [str(next_item)], "True original armor900 and acceptance300 earn the initially unknown N11 once, with the same genuine Scope/public completion")
	_check(var_to_bytes([reserve.cargo, reserve.holder, person.cargo, person.holder]) == paid_stock and f.data.site.next_item == next_item + 1
		and f.nation.technology.projects[0].budget.payments.size() == 2 and f.nation.technology.projects[0].budget.payments[1].materials.is_empty(), "Acceptance does not replay physical manufacture, funding, item sequence or finite source debit")
	_earned_cold(f, "N11")
	before = _earned_bytes(f)
	_check(not f.controller._nation_ui_command("n1", "administration", {"order": order_id}).ok and _earned_bytes(f) == before,
		"Completed original armor acceptance cannot replay its Scope/public evidence")
	_earned_finish()
	await process_frame
	print("N11_FIRST_EARNED_ARMOR_ORIGINAL_LAB_POINT_FIXTURE_PASS: checks=", checks, "; true finite donor-transfer/armor900/acceptance300/cold; only armor route, NOT siege/Native/GPU/performance/full40 acceptance")
	quit(0)
