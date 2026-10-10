extends "res://scripts/tests/site_technology_nation_material_test.gd"
## True ordinary Runtime production supplies the certificate sample. Known
## archives and learned F07 are explicit legitimate saved-world preconditions.
## Direct productive intervals exclude travel/shared clock/Native/FPS proof.

func _military_fixture(first_research: bool) -> Dictionary:
	var data := _building_fixture()
	var home := _formal_feature(data, "house", Vector2i(13, 18), Vector2i(2, 2))
	var smithy := _formal_feature(data, "smithy", Vector2i(25, 18))
	var lab := _building_lab(data)
	var controller := lab.site_controller
	var actions = controller.person_actions
	var orders = controller.equipment_orders
	var control := lab.controlled_person_id()
	var team := _army(lab, data)
	var executor := team.combat_identity(1)
	var row: Dictionary = team.combat_units[1]
	var refs: Array = []
	for identity: int in [control, executor]: refs.append({"site_id": str(data.site.id), "person_id": identity, "path": "", "label": "原成员", "age_years": -1})
	_check(controller.family_continuity.register_members(refs, true, control).ok and controller.family_continuity.appoint_head(control, control).ok, "Original Family registry names the actual actor and original NPC")
	data.site.family.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.family.technology.known = ["F07"]
	row.technology = Technology.learned_candidate(row.get("technology", {}), "F07")
	_check(Family.validate_family(data.site.family, str(data.site.id)) and Technology.valid_person(row.technology), "The explicit saved F07 archive/skill uses the true strict Family and person schemas")
	var center := Runtime.building_cells(data, "settlement_center", Vector2i(18, 10), Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	var cells: Array[int] = []
	cells.assign(center.cells)
	var founded := Settlement.found(lab, control, cells)
	_check(founded.ok, "The original settlement owner establishes the real center and offices")
	_complete_key(data, str(founded.feature))
	var lodging := Runtime.house_layout(data, home)
	data.site.housing = {str(executor): {"version": 1, "house_id": home, "cell": int(lodging.slots[0])}}
	_check(Homes.validate(data, data.site, {executor: {"hp": float(row.hp), "faction_id": 1}}).ok, "Initial housing belongs to the actual living original NPC")
	data.site.settlement.version = 2
	data.site.settlement.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.settlement.technology.known = ["S01", "S04", "S07"]
	var nation_tech := Technology.empty_scope_record(str(data.site.id))
	nation_tech.known = ["N04"] if first_research else ["N04", "N05"]
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", control), "members": [control, executor], "standards": {}, "technology": nation_tech}}
	var feature: Dictionary = data.site.features[smithy]
	_check(Runtime.request_feature_recipe(data, smithy, "bow", 1).ok and Runtime.operate_feature(data, smithy).ok, "Original recipe and work-zone APIs admit the genuine qualified S07 bow operation")
	var workers = controller.work_team
	_check(workers.assign(team, [executor], team.duty_decider("team.work")).ok, "The original team.work duty selects the real ordinary workshop NPC")
	workers.prepare_work_requests(108.0)
	var task: Dictionary = row.work_task
	_check(task.get("target") == "feature:" + smithy and task.get("action") == "operate", "The original WT selector chooses its real active workshop zone")
	team.cells[1] = data.cell_from_index(int(task.work_cell))
	task.cell = int(task.work_cell)
	task.mode = "work"
	var original_item := int(data.site.next_item)
	Runtime._feature_work(data, smithy, float(Runtime.feature_recipe(feature).cycle), Callable(), Callable(), task, row.cargo, Runtime.CARRY_CAPACITY, 1, executor)
	_check(int(data.site.next_item) == original_item + 1 and data.site.item_records.has(str(original_item)) and feature.technology_output.receipts.size() == 1, "The original paid Runtime batch genuinely creates the sample bow and its canonical exact8 current receipt")
	var sample: Dictionary = feature.technology_output.receipts[0]
	_check(sample.operator_id == executor and sample.recipe_id == "bow" and sample.item_ids == [str(original_item)] and float(sample.work_seconds) == 108.0, "The certification sample carries only true named effort and the real original item")
	_check(workers.cancel(executor).ok, "The original WT owner releases its actual sample task")
	workers.discard_prepared_interval()
	Runtime._stop_feature_zones(data, smithy, "operate")
	_check(Runtime.request_feature_recipe(data, smithy, "", 1).ok and Stocks.set_local_supply(data, smithy, true, 1).ok, "The real idle workshop switches to its original local stock after completed output")
	_check(orders.certify_workshop(control, "n1", "cert", smithy, "S07", int(sample.id)).ok, "N04 certifies the actual Runtime sample, never a fabricated fixture receipt")
	_check(orders.set_standard(control, "n1", "bow_line", "原弓标准", {"weapon": {"definition": "weapon:bow_01", "alternatives": []}}).ok, "The original national standard references the actual admitted item definition")
	if first_research:
		_check(actions.prepare_scope_technology(control, executor, "N05", "n1").ok and actions.request_scope_technology_consent(control, "nation", "n1", executor).ok, "First N05 uses the real Scope purpose and original team consent before its material grant")
	var requested = orders.request_military_production_order(control, "n1", "cert", executor, executor, "bow_line")
	_check(requested.ok, "Original national production duty opens one actual finite military order")
	var order_id := str(requested.order_id)
	var stock := Stocks.stock_endpoint(data, smithy)
	var donor = actions._person(control)
	donor.cargo.wood = 4
	donor.cargo.fiber = 2
	_check(lab.character.place(stock.cell, true) and orders.authorize_military_materials(control, "n1", order_id, {"wood": 4, "fiber": 2}).ok, "The actual original donor explicitly grants this finite single batch")
	_check(orders.supply_military_production(control, "n1", order_id, {"wood": 4, "fiber": 2}, int(donor.holder.version), int(stock.holder.version)).ok, "Original Vehicle.transfer funds the SAME localstock and records the donor's real transfer")
	team.cells[1] = Vector2i(12, 11)
	var before := var_to_bytes([data.site, row])
	var initial = orders.military_work_preflight("n1", order_id)
	_check(initial.ok and feature.get("recipe_id", "").is_empty() and initial.person.cell != stock.cell and var_to_bytes([data.site, row]) == before, "True NPC initial preflight is read-only and does not require arrival or old recipe bow")
	_check(not orders.military_order_admission("n1", order_id, smithy, executor, Runtime.RANGED_RECIPES.bow.cost).ok and var_to_bytes([data.site, row]) == before, "Actual manufacturing admission still refuses before genuine recipe and station adoption")
	return {"data": data, "lab": lab, "team": team, "row": row, "executor": executor, "control": control, "actions": actions,
		"orders": orders, "smithy": smithy, "feature": feature, "stock": stock, "order_id": order_id, "donor": donor}

func _military_produce(first_research: bool) -> void:
	var fixture := _military_fixture(first_research)
	var data: TerrainData = fixture.data
	var lab: TerrainLab = fixture.lab
	var row: Dictionary = fixture.row
	var feature: Dictionary = fixture.feature
	var stock: Dictionary = fixture.stock
	var order: Dictionary = data.site.equipment_nations.n1.technology_operations.orders[fixture.order_id]
	var donor_spent := var_to_bytes(order.source.spent)
	var camp = data.site.inventory.duplicate()
	var before := var_to_bytes([data.site, row])
	var result = fixture.actions.begin_scope_technology_phase(int(fixture.control), "nation", "n1", "workshop_bow", "feature:" + str(fixture.smithy)) if first_research else Runtime.begin_nation_military_operation(data, "n1", str(fixture.order_id), true)
	if first_research:
		_check(result.ok, "First N05 binds a true military localstock source without a pre-existing Scope grant")
	else:
		_check(result.ok and var_to_bytes([data.site, row]) == before, "Known N05 preview pays nothing and mutates neither original order nor recipe/task")
		var available := int(stock.cargo.wood)
		stock.cargo.wood = 0
		before = var_to_bytes([data.site, row])
		var refused := Runtime.begin_nation_military_operation(data, "n1", str(fixture.order_id))
		_check(not refused.ok and var_to_bytes([data.site, row]) == before, "An abundant unrelated camp cannot conceal insufficient actual military localstock")
		stock.cargo.wood = available
		result = Runtime.begin_nation_military_operation(data, "n1", str(fixture.order_id))
		_check(result.ok, "The true known military order publishes one real paid named workshop batch")
	_check(data.site.inventory == camp and Runtime.inventory_size(stock.cargo) == 0 and var_to_bytes(order.source.spent) == donor_spent and row.work_task.version == 3 and row.work_task.named, "Manufacturing debits localstock once, never the donor again or the camp, and publishes the original named task")
	_check(feature.technology_order == {"nation_id": "n1", "order_id": str(fixture.order_id)} and Runtime.validate_technology_target_storage(data, str(fixture.smithy), feature).ok, "The canonical military namespace and consumed payment ledger pass original strict target validation")
	var source = fixture.actions.nation_operation_material_source_candidate("n1", str(fixture.order_id), "workshop_bow")
	if not first_research: _check(source.ok and source.source.spent.is_empty(), "Donor transfer history does not become a second manufactured batch payment")
	before = var_to_bytes([data.site, row])
	var resumed = fixture.actions.begin_scope_technology_phase(int(fixture.control), "nation", "n1", "workshop_bow", "feature:" + str(fixture.smithy)) if first_research else Runtime.begin_nation_military_operation(data, "n1", str(fixture.order_id))
	_check(resumed.ok and resumed.resumed and resumed.already_working and var_to_bytes([data.site, row]) == before, "The actual accepted named military task resumes as an exact no-op with empty paid localstock")
	var next_item := int(data.site.next_item)
	_finish_feature(lab, fixture.team, int(fixture.executor), str(fixture.smithy), float(Runtime.feature_recipe(feature).cycle))
	order = data.site.equipment_nations.n1.technology_operations.orders[fixture.order_id]
	_check(order.status == "complete" and order.receipt_ids.size() == 1 and order.accepted_receipts.size() == 1 and int(data.site.next_item) == next_item + 1 and data.site.item_records[str(next_item)].definition == "weapon:bow_01", "True original manufacturing commits one actual bow plus one exact8 canonical and finite military accepted receipt")
	_check(row.work_task.is_empty() and not lab.site_controller.work_team.is_assigned(int(fixture.executor)) and not feature.has("tech_batch") and not feature.has("technology_order") and var_to_bytes(order.source.spent) == donor_spent and data.site.inventory == camp, "Successful named output stops the finite original task and cannot silently begin another paid batch")
	if first_research:
		var project := Technology.active_project(data.site.equipment_nations.n1.technology)
		_check(project.budget.spent == {"wood": 4, "fiber": 2} and project.budget.payments.size() == 1 and project.receipts.size() == 1 and not Technology.scope_known(data.site.equipment_nations.n1.technology, "N05"), "One actual new Scope payment and truthful bow phase are retained; N05 still needs its separate original five-second issue phase")
	before = var_to_bytes([data.site, row])
	_check(not Runtime.begin_nation_military_operation(data, "n1", str(fixture.order_id)).ok and var_to_bytes([data.site, row]) == before, "Completed max1 order cannot create a second bow or receipt")
	_cleanup_fixture(lab, fixture.team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 90000
	await _military_produce(false)
	await _military_produce(true)
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_MILITARY_PRODUCTION_PASS: %d checks; true ordinary sample/certification/donor transfer/N05 local payment/named original output/replay; issue phase, shared clock, Native and full40 excluded" % checks)
	quit(0)
