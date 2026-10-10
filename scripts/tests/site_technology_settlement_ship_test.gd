extends "res://scripts/tests/site_technology_shipyard_physical_test.gd"
## Genuine original two Army stations, Actor carrier, local holder debit,
## original pooled Fatigue, Ships.make_record and strict Store. NOT_RUN.
## Requires S12 guarded-enabled + Root sourcev2/transfer/Time AND function union.

func _ship_order_fixture(known: bool = true) -> Dictionary:
	var f := _shipyard_fixture()
	f.data.site.family.technology.known = ["F13"]
	f.data.site.settlement.technology.known = ["S12"] if known else []
	f.helper = f.team.combat_identity(2)
	_check(Stocks.ensure_storage(f.data, str(f.warehouse), 1).ok, "Original source Warehouse has its actual holder")
	var actor: Dictionary = f.actions._person(int(f.control))
	var cost := Runtime.Ships.build_cost("ferry")
	actor.cargo.clear()
	for item: String in cost: actor.cargo[item] = int(cost[item])
	_check(f.lab.character.place(f.data.cell_from_index(int(f.data.site.features[f.warehouse].entrance)), true), "Actual head/carrier reaches original donor contact")
	var stock := Stocks.storage(f.data, str(f.warehouse))
	_check(f.lab.site_controller.vehicles.transfer("person:" + str(f.control), "feature:" + str(f.warehouse), cost, [], int(actor.holder.version), int(stock.holder.version), int(f.control)).ok, "Explicit original starting cargo is deposited into the real donor once")
	return f

func _adopt_ship_order(f: Dictionary, project_id: int = 0) -> String:
	var before := var_to_bytes([f.data.site, f.team.capture_combat_state()])
	var preview := Runtime.request_settlement_ship_order(f.data, str(f.yard), int(f.executor), int(f.helper), int(f.control), "feature:" + str(f.warehouse), int(f.control), project_id, true)
	_check(preview.ok and var_to_bytes([f.data.site, f.team.capture_combat_state()]) == before, "Two real workers/one carrier adoption preview is readonly")
	var requested := Runtime.request_settlement_ship_order(f.data, str(f.yard), int(f.executor), int(f.helper), int(f.control), "feature:" + str(f.warehouse), int(f.control), project_id)
	_check(requested.ok, "True original head adopts one finite ferry with two actual people and scoped consent")
	_check(Stocks.ensure_storage(f.data, str(f.yard), 1).ok, "Original Stockpiles enables the physically adopted shore holder")
	return str(requested.order_id)

func _deliver_ship_order(f: Dictionary, id: String) -> void:
	var first := Runtime.prepare_settlement_ship_delivery(f.data, str(f.settlement_id), id, int(f.control))
	_check(first.ok and Runtime.publish_settlement_ship_delivery(first).ok, "First actual source-to-carrier transfer publishes one physical leg")
	var order: Dictionary = f.data.site.settlement.technology_operations.orders[id]
	_check(order.payload.delivery_receipts.size() == 1 and order.payload.spent.is_empty(), "Physical supply is not a second manufacture payment")
	var state := var_to_bytes(f.data.site)
	_check(not Runtime.publish_settlement_ship_delivery(first).ok and var_to_bytes(f.data.site) == state, "One actual prepared delivery cannot replay")
	_check(not Runtime.prepare_settlement_ship_delivery(f.data, str(f.settlement_id), id, int(f.control)).ok and var_to_bytes(f.data.site) == state, "Remote second contact cannot copy carrier cargo into the yard")
	_check(f.lab.character.place(f.data.cell_from_index(int(f.data.site.features[f.yard].entrance)), true), "Same actual carrier reaches the original shipyard")
	var second := Runtime.prepare_settlement_ship_delivery(f.data, str(f.settlement_id), id, int(f.control))
	_check(second.ok and Runtime.publish_settlement_ship_delivery(second).ok, "Second original carrier-to-yard contact transfers actual material once")
	_check(order.payload.delivery_receipts.size() == 2 and order.payload.spent.is_empty(), "Finite two physical legs retain their own bounded original history")
	_check(Runtime.grant_settlement_operation_source(f.data, str(f.settlement_id), id, int(f.control), str(f.yard)).ok, "Head at the real yard explicitly grants the finite manufacturing source without resetting cap/spent")

func _place_ship_workers(f: Dictionary) -> void:
	for identity: int in [int(f.executor), int(f.helper)]:
		var row: Dictionary = f.team.combat_units[f.team.index_for_identity(identity)]
		var task: Dictionary = row.work_task
		f.team.cells[f.team.index_for_identity(identity)] = f.data.cell_from_index(int(task.work_cell))
		task.cell = int(task.work_cell)
		task.mode = "work"
		_check(SiteWorkTeam.valid_task(f.data, f.data.site, task), "True named shore task resolves its original adopted slot")
	_check(f.row.work_task.work_slot != f.team.combat_units[2].work_task.work_slot, "True workers occupy two distinct saved cells")

func _known_ship_once_and_resume() -> void:
	var f := _ship_order_fixture()
	var data: TerrainData = f.data
	var id := _adopt_ship_order(f)
	_deliver_ship_order(f, id)
	var yard: Dictionary = data.site.features[f.yard]
	var local := Stocks.storage(data, str(f.yard))
	var camp := var_to_bytes([data.site.inventory, data.site.depot_items])
	var version := int(local.holder.version)
	var before := var_to_bytes([data.site, f.team.capture_combat_state()])
	_check(Runtime.begin_settlement_ship_operation(data, str(f.settlement_id), id, true).ok and var_to_bytes([data.site, f.team.capture_combat_state()]) == before, "Full local cost/two original tasks/launch candidates pass purely before payment")
	_check(Runtime.begin_settlement_ship_operation(data, str(f.settlement_id), id).ok, "Actual named ferry begins in the original ship owner")
	var order: Dictionary = data.site.settlement.technology_operations.orders[id]
	_check(local.cargo.is_empty() and int(local.holder.version) == version + 1 and var_to_bytes([data.site.inventory, data.site.depot_items]) == camp, "True whole hull material debits the SAME yard once; camp pays nothing")
	_check(yard.ship_build.total_work == 600.0 and yard.technology_ship_method == {"version": 1} and order.payload.spent == order.payload.cap, "Original baseline remains 600; one F13 marker and one full manufacturing debit")
	_place_ship_workers(f)
	var master = f.actions._person(int(f.executor))
	var checked := Runtime.work_preflight(data, f.row.work_task, master.cargo, Runtime.CARRY_CAPACITY, 1, int(f.executor), f.lab.site_controller.reserves_cell)
	_check(checked.ok and is_equal_approx(float(checked.productivity), 10.0 / 9.0), "Real F13 original work contributes exactly one ten-percent time benefit")
	var archive := var_to_bytes([data.site.family.technology, data.site.settlement.technology, f.row.technology])
	var last := _shipyard_work_point(f, 30.0)
	_check(last.runtime.size() == 2 and is_equal_approx(float(yard.production), 10.0 / 9.0), "Two true thirty-second contributions advance exactly 66.6667 original baseline seconds")
	var paid = yard.tech_batch.duplicate(true)
	var progress := float(yard.production)
	var output_identity := str(data.site.next_vehicle)
	_check(Runtime.stop_settlement_ship_order(data, str(f.settlement_id), id, int(f.control)).ok, "Original head pauses only the two named ship tasks")
	_check(yard.ship_build.total_work == 600.0 and yard.tech_batch == paid and float(yard.production) == progress, "Pause preserves full original paid ledger and physical progress")
	_check(not Runtime.cancel_ship_build(data, str(f.yard), 1).ok and var_to_bytes([data.site.inventory, data.site.depot_items]) == camp, "Legacy cancel cannot refund private shipyard stock into camp")
	_check(Runtime.begin_settlement_ship_operation(data, str(f.settlement_id), id).ok and int(local.holder.version) == version + 1 and yard.tech_batch == paid, "Paid resume truly reassigns both original workers without new material/attempt/effect")
	_place_ship_workers(f)
	f.lab.site_controller._capture_positions()
	_check(ShipStore.save(data, "user://technology_s12_finite_paid.json").ok, "Original Store saves the real finite order/paid hull/two task refs")
	var natural_fingerprint := data.fingerprint()
	var natural_conditions := _shipyard_source_bytes(data)
	var loaded := ShipStore.load_site("user://technology_s12_finite_paid.json")
	_check(loaded.ok, "Strict original loader admits this actual finite paid order and method marker")
	var cold_data: TerrainData=loaded.get("data",loaded.get("terrain"))
	_check(cold_data != null and cold_data.fingerprint()==natural_fingerprint and _shipyard_source_bytes(cold_data)==natural_conditions,"Finite paid hull cold source is true original generation, never patched water/soil")
	var intervals := 1
	while yard.has("ship_build") and intervals < 20:
		_shipyard_work_point(f, 30.0)
		intervals += 1
	_check(intervals == 9 and not yard.has("ship_build"), "Exactly 540 aggregate original productive seconds complete 600 baseline once, never 486")
	_check(data.site.vehicles.has(output_identity) and data.site.vehicles[output_identity].kind == "ship" and data.site.vehicles[output_identity].ship_type == "ferry" and int(data.site.next_vehicle) == int(output_identity) + 1, "Original Ships.make_record adopts exactly one actual ferry with its real ID")
	_check(order.status == "completed" and order.receipts.size() == 1 and order.receipts[0].ship_id == output_identity and is_equal_approx(float(order.receipts[0].work_seconds), 270.0), "Finite order stores true output ID and only named operator's 270 unweighted seconds")
	_check(not yard.has("technology_settlement_order") and not yard.has("technology_ship_method") and f.row.get("work_task", {}).is_empty() and f.team.combat_units[2].get("work_task", {}).is_empty(), "Original completion clears only active links/effect and stops both named tasks")
	_check(var_to_bytes([data.site.family.technology, data.site.settlement.technology, f.row.technology]) == archive, "Known ship cooperation fabricates no personal learning/research receipt")
	before = var_to_bytes(data.site)
	_check(not Runtime.begin_settlement_ship_operation(data, str(f.settlement_id), id).ok and var_to_bytes(data.site) == before, "Finite completed ship order cannot produce a second hull")
	_cleanup_fixture(f.lab, f.team)
	await process_frame

func _unknown_scope_and_current_guard() -> void:
	var f := _ship_order_fixture(false)
	var data: TerrainData = f.data
	var prepared = f.actions.prepare_scope_technology(int(f.control), int(f.executor), "S12", str(f.settlement_id))
	_check(prepared.ok, "Actual original unknown settlement registers S12 without requiring its own knowledge/config")
	var project := Technology.active_project(data.site.settlement.technology)
	var id := _adopt_ship_order(f, int(project.id))
	_deliver_ship_order(f, id)
	_check(f.actions.begin_scope_technology_phase(int(f.control), "settlement", str(f.settlement_id), "ferry_build", "feature:" + str(f.yard), {"order_id": id}).ok, "True Scope phase adopts the finite original order and full yard material before two actual tasks")
	var yard: Dictionary = data.site.features[f.yard]
	var token: Dictionary = yard.tech_trial
	var order: Dictionary = data.site.settlement.technology_operations.orders[id]
	_check(Runtime.technology_existing_paid_phase_source(data, token).ok and Runtime.settlement_operation_paid_source_candidate(data, token, id).ok, "Continuation derives historical paid proof from SAME original target/order")
	_place_ship_workers(f)
	_shipyard_work_point(f, 30.0)
	var paid_before = yard.tech_batch.duplicate(true)
	var physical_before := float(yard.production)
	var original_project_id := int(project.id)
	var original_purpose := str(project.purpose)
	_check(f.actions.stop_scope_technology(int(f.control), "settlement", str(f.settlement_id)).ok, "Actual Scope pause parks both original named shore tasks through the Runtime release candidate")
	_check(f.row.get("work_task", {}).is_empty() and f.team.combat_units[2].get("work_task", {}).is_empty(), "Personal project stop cannot leave its actual helper busy on the paid hull")
	_check(f.actions.prepare_scope_technology(int(f.control), int(f.executor), "S12", str(f.settlement_id)).ok, "Original unfinished Scope project can explicitly resume")
	project = Technology.active_project(data.site.settlement.technology)
	_check(project.id == original_project_id and project.purpose == original_purpose, "Resume preserves the original project/purpose rather than creating a second payment source")
	_check(f.actions.begin_scope_technology_phase(int(f.control), "settlement", str(f.settlement_id), "ferry_build", "feature:" + str(f.yard), {"order_id": id}).ok and yard.tech_batch == paid_before and float(yard.production) == physical_before, "Public Scope next-attempt proposal resolves the SAME retained paid token and truly reassigns two original workers")
	_place_ship_workers(f)
	var learned: Dictionary = f.row.technology
	f.row.technology = {}
	var before := var_to_bytes([data.site, f.team.capture_combat_state()])
	var person: Dictionary = f.actions._person(int(f.executor))
	_check(not Runtime.work_preflight(data, f.row.work_task, person.cargo, Runtime.CARRY_CAPACITY, 1, int(f.executor), f.lab.site_controller.reserves_cell).ok and var_to_bytes([data.site, f.team.capture_combat_state()]) == before, "Lost original F13 master stops work with no paid progress/knowledge loss")
	f.row.technology = learned
	for index: int in range(8): _shipyard_work_point(f, 30.0)
	_check(order.status == "completed" and order.receipts.size() == 1 and Technology.scope_known(data.site.settlement.technology, "S12"), "One genuine completed ship and true personal phase receipt close only this actual S12 Scope")
	project = Technology.active_project(data.site.settlement.technology)
	_check(project.is_empty() or project.get("receipts", []).size() == 1, "Scope output is accepted once; helper creates no duplicate evidence")
	_check(not Technology.learned(f.team.combat_units[2].get("technology", {}), "F13"), "Original helper remains unlearned while contributing real permitted work")
	_cleanup_fixture(f.lab, f.team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	await _known_ship_once_and_resume()
	await _unknown_scope_and_current_guard()
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_SETTLEMENT_SHIP_PASS: %d checks; actual finite ferry/two shore people/carrier two contacts/SAME local debit/600baseline 540effort/F13 once/Scope/Store; formal UI/fullLab/Native/travel/all40 excluded" % checks)
	quit(0)
