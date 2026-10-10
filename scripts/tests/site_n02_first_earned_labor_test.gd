extends "res://scripts/tests/site_nation_first_earned_base.gd"
## N02 starts unknown. Actual public form -> original NPC labor300 -> original
## paid one-cell road180. The full original GD shared point owns all time/work.

func _run() -> void:
	var f := _earned_fixture("N02")
	_earned_speed(f)
	_earned_prepare(f, "N02")
	var before := _earned_bytes(f)
	_check(not f.controller._nation_ui_command("n1", "labor", {"people": [int(f.lab.npc.person_id)]}).ok and _earned_bytes(f) == before,
		"A living but genuinely unhoused/nonmember original Actor cannot become labor by caller selection")
	_check(f.team.set_duty_ai_enabled(f.team.combat_identity(f.team.formal_commander), false).ok, "Original captain explicitly closes the actual team duty flag")
	before = _earned_bytes(f)
	_check(not f.controller._nation_ui_command("n1", "labor", {"people": [f.executor]}).ok and _earned_bytes(f) == before,
		"Actual NPC public-purpose consent rejects a closed true original duty flag without publishing any order")
	_check(f.team.set_duty_ai_enabled(f.team.combat_identity(f.team.formal_commander), true).ok, "Same living original captain explicitly reopens its true duty flag")
	var registered: Dictionary = f.controller._nation_ui_command("n1", "labor", {"people": [f.executor]})
	_check(registered.ok, "Original public labor form registers the same real housed resident after true consent: " + str(registered))
	var order_id := str(registered.order_id)
	var operations: Dictionary = f.nation.technology_operations
	var order: Dictionary = operations.public_orders[order_id]
	var project := Technology.active_project(f.nation.technology)
	_check(int(order.project_id) == int(project.id) and order.payload.person_ids == [f.executor] and not order.payload.consents.is_empty(),
		"One true first-order binds the original Scope project/person and real original team consent")
	before = _earned_bytes(f)
	_check(not f.controller._nation_ui_command("n1", "construction", {"order": order_id, "x": 30, "y": 25}).ok and _earned_bytes(f) == before,
		"Road cannot skip the first original effective300 labor phase or consume stone/create a task")
	_check(f.controller._nation_ui_command("n1", "administration", {"order": order_id}).ok, "Public administration begins the actual first labor job")
	var job: Dictionary = f.actions._jobs[str(f.executor)]
	_check(job.kind == "nation_administration" and job.duration == 300.0 and is_same(job.nation_order_ref, order) and job.executor_id == f.executor,
		"The original PA job retains the SAME labor order and SAME original resident executor")
	_check(f.actions.save_guard().code == "BUSY", "Original manual-save admission keeps pending labor BUSY rather than creating a second saved research queue")
	_earned_true_step(f)
	_check(float(job.elapsed) > 0.0 and float(job.elapsed) < 300.0 and not Technology.scope_known(f.nation.technology, "N02"),
		"One true accepted main point contributes only actual labor effort, with no premature knowledge")
	_earned_until_idle(f)
	project = Technology.active_project(f.nation.technology)
	_check(project.receipts.size() == 1 and project.receipts[0].phase_id == "register_real_labor_and_consent" and is_equal_approx(float(project.receipts[0].work_seconds), 300.0)
		and order.receipts.size() == 1 and not Technology.scope_known(f.nation.technology, "N02"), "Actual300 labor publishes one real Scope/Nops phase together, without earning the road phase")
	_check(project.budget.payments.size() == 1 and project.budget.payments[0].materials.is_empty(), "Actual labor payment is truly zero-material")
	_earned_cold(f, "N02", false)
	_earned_depot_grant(f, {"stone": 1})
	var geometry := _earned_road_preview(f, Vector2i(30, 25))
	var road_cell: Vector2i = geometry.fixture_cell
	var stone := int(f.data.site.inventory.stone)
	var next_feature := int(f.data.site.next_feature)
	var started: Dictionary = f.controller._nation_ui_command("n1", "construction", {"order": order_id, "x": road_cell.x, "y": road_cell.y})
	_check(started.ok and f.data.site.inventory.stone == stone - 1 and f.data.site.next_feature == next_feature + 1,
		"Actual public Scope road start debits exactly one original stone and adopts one original feature: " + str(started))
	var key := str(next_feature)
	var feature: Dictionary = f.data.site.features[key]
	var task := _at_feature(f.lab, f.team, f.executor, key)
	_check(int(feature.entrance) == int(geometry.entrance) and task.operation_ref == {"nation_id": "n1", "order_id": order_id}
		and int(feature.tech_trial.person.person_id) == f.executor and Runtime.technology_existing_paid_phase_source(f.data, feature.tech_trial).ok,
		"True named original task/order/feature use the one real geometry and the actual original paid source proof")
	before = _earned_bytes(f)
	_check(not f.controller._nation_ui_command("n1", "construction", {"order": order_id, "x": road_cell.x, "y": road_cell.y}).ok and _earned_bytes(f) == before,
		"A started original road cannot replay payment, feature sequence or named task")
	_earned_until_idle(f)
	_check(feature.stage == "complete" and f.row.work_task.is_empty() and not feature.has("tech_trial") and not feature.has("technology_order"),
		"Only true original common-point road work completes and releases the original named job")
	_check(Technology.scope_known(f.nation.technology, "N02") and f.nation.technology.projects[0].receipts.size() == 2
		and is_equal_approx(float(f.nation.technology.projects[0].receipts[1].work_seconds), 180.0) and order.status == "complete" and order.receipts.size() == 2,
		"The genuinely unknown N02 earns once from real labor300 and real original road180, with the same Scope/public completion tail")
	_check(f.data.site.inventory.stone == stone - 1 and f.nation.technology.projects[0].budget.payments.size() == 2,
		"Completed labor/road has one zero payment and one actual stone payment, without a second debit")
	_earned_cold(f, "N02")
	before = _earned_bytes(f)
	_check(not f.controller._nation_ui_command("n1", "administration", {"order": order_id}).ok and _earned_bytes(f) == before,
		"Completed original labor history cannot be replayed as new first research")
	_earned_finish()
	await process_frame
	print("N02_FIRST_EARNED_ORIGINAL_LAB_POINT_FIXTURE_PASS: checks=", checks, "; original labor300+road180, true GD shared clock/cold; NOT Native/GPU/performance/full40 acceptance")
	quit(0)
