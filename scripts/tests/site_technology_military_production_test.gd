extends "res://scripts/tests/site_technology_nation_material_test.gd"

const ReturnFailureGuard = preload("res://scripts/tests/fixtures/technology_return_failure_guard.gd")
var _return_errors: Variant = ReturnFailureGuard.new()

func _initialize() -> void:
	OS.add_logger(_return_errors)
	super._initialize()

func _finalize() -> void:
	OS.remove_logger(_return_errors)

func _process(delta: float) -> bool:
	if not _return_errors.accepts(self, true, ""): return false
	return super._process(delta)

func _require(condition: bool, message: String) -> bool:
	checks += 1
	return _return_errors.accepts(self, condition, message)

## True ordinary Runtime production supplies the certificate sample. Known
## archives and learned F07 are explicit legitimate saved-world preconditions.
## Direct productive intervals exclude travel/shared clock/Native/FPS proof.

func _military_fixture(first_research: bool) -> Dictionary:
	var data: TerrainData = _building_fixture()
	if not _return_errors.accepts(self, true, "callee failure"): return {}
	var home: String = _formal_feature(data, "house", Vector2i(13, 18), Vector2i(2, 2))
	if not _return_errors.accepts(self, true, "callee failure"): return {}
	var smithy: String = _formal_feature(data, "smithy", Vector2i(25, 18))
	if not _return_errors.accepts(self, true, "callee failure"): return {}
	var lab: TerrainLab = _building_lab(data)
	if not _return_errors.accepts(self, true, "callee failure"): return {}
	var controller: Variant = lab.site_controller
	var actions = controller.person_actions
	var orders = controller.equipment_orders
	var control: int = lab.controlled_person_id()
	var team: TerrainArmy = _army(lab, data)
	if not _return_errors.accepts(self, true, "callee failure"): return {}
	var executor: int = team.combat_identity(1)
	var row: Dictionary = team.combat_units[1]
	var refs: Array = []
	for identity: int in [control, executor]: refs.append({"site_id": str(data.site.id), "person_id": identity, "path": "", "label": "原成员", "age_years": -1})
	if not _require(controller.family_continuity.register_members(refs, true, control).ok and controller.family_continuity.appoint_head(control, control).ok, "Original Family registry names the actual actor and original NPC"): return {}
	var family_candidate: Dictionary = actions._technology_candidate()
	if not _require(not family_candidate.is_empty() and Family.validate_family(family_candidate, str(data.site.id)), "Original pure Family migration admits the same registered members and offices before the explicit saved archive"): return {}
	data.site.family = family_candidate
	data.site.family.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.family.technology.known = ["F07"]
	row.technology = Technology.learned_candidate(row.get("technology", {}), "F07")
	if not _require(Family.validate_family(data.site.family, str(data.site.id)) and Technology.valid_person(row.technology), "The explicit saved F07 archive/skill uses the true strict Family and person schemas"): return {}
	var center: Dictionary = Runtime.building_cells(data, "settlement_center", Vector2i(18, 10), Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	var cells: Array[int] = []
	cells.assign(center.cells)
	var founded: Dictionary = Settlement.found(lab, control, cells)
	if not _require(founded.ok, "The original settlement owner establishes the real center and offices"): return {}
	_complete_key(data, str(founded.feature))
	if not _return_errors.accepts(self, true, "callee failure"): return {}
	var lodging: Dictionary = Runtime.house_layout(data, home)
	data.site.housing = {str(executor): {"version": 1, "house_id": home, "cell": int(lodging.slots[0])}}
	if not _require(Homes.validate(data, data.site, {executor: {"hp": float(row.hp), "faction_id": 1}}).ok, "Initial housing belongs to the actual living original NPC"): return {}
	data.site.settlement.version = 2
	data.site.settlement.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.settlement.technology.known = ["S01", "S04", "S07"]
	var nation_tech: Variant = Technology.empty_scope_record(str(data.site.id))
	nation_tech.known = ["N04"] if first_research else ["N04", "N05"]
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", control), "members": [control, executor], "standards": {}, "technology": nation_tech}}
	var feature: Dictionary = data.site.features[smithy]
	if not _require(Runtime.request_feature_recipe(data, smithy, "bow", 1).ok and Runtime.operate_feature(data, smithy).ok, "Original recipe and work-zone APIs admit the genuine qualified S07 bow operation"): return {}
	var workers = controller.work_team
	var sample_workers: Array[int] = [executor]
	if not _require(workers.assign(team, sample_workers, team.duty_decider("team.work")).ok, "The original team.work duty selects the real ordinary workshop NPC"): return {}
	workers.prepare_work_requests(108.0)
	var task: Dictionary = row.work_task
	if not _require(task.get("target") == "feature:" + smithy and task.get("action") == "operate", "The original WT selector chooses its real active workshop zone"): return {}
	if not _arrive_workshop_operator(lab, team, executor, smithy): return {}
	var operator_before: PackedByteArray = var_to_bytes([data.site, row])
	var operator_facts: Dictionary = _sample_operator_facts(lab, team, executor, row, task)
	print("TECH_OPERATOR_DIAG " + JSON.stringify(operator_facts))
	if not _return_errors.accepts(self, true, "original sample operator probe"): return {}
	if not _require(var_to_bytes([data.site, row]) == operator_before, "Original operator diagnosis does not alter the paid sample, body or saved knowledge"): return {}
	if not _require(operator_facts.get("person_present") == true and operator_facts.get("owner_same_team") == true and operator_facts.get("body_same_row") == true and operator_facts.get("person_F07") == true, "Existing legitimate saved-world F07 precondition belongs to the same real sample maker, not only its Family archive"): return {}
	var sample_guard: Dictionary = Runtime.technology_batch_operator_guard(data, smithy, feature, task, executor)
	var sample_start: Dictionary = {"guard": sample_guard, "cell": int(task.cell), "work_cell": int(task.work_cell), "actual_cell": data.index(actions._person(executor).cell), "usable": Runtime.feature_usable(feature), "production": feature.get("production"), "batch_paid": feature.get("batch_paid"), "task_status": task.get("status", "")}
	var original_item: int = int(data.site.next_item)
	Runtime._feature_work(data, smithy, float(Runtime.feature_recipe(feature).cycle), Callable(), Callable(), task, row.cargo, Runtime.CARRY_CAPACITY, 1, executor)
	var sample_state_before: PackedByteArray = var_to_bytes([data.site, row])
	var sample_output: Dictionary = Runtime.prepare_feature_output(data, feature, task, row.cargo, Runtime.CARRY_CAPACITY, executor)
	if not _require(var_to_bytes([data.site, row]) == sample_state_before, "Sample diagnostic reads the original output preflight without gameplay mutation"): return {}
	print("TECH_SAMPLE_DIAG " + JSON.stringify({"test": "site_technology_military_production_test", "start": sample_start, "end": {"next_item_before": original_item, "next_item_after": data.site.next_item, "sample_exists": data.site.item_records.has(str(original_item)), "task_status": task.get("status", ""), "feature_status": feature.get("status", ""), "production": feature.get("production"), "batch_paid": feature.get("batch_paid"), "tech_batch": feature.get("tech_batch", {}), "technology_output": feature.get("technology_output", {}), "output_ok": sample_output.get("ok", false), "output_code": sample_output.get("code", ""), "output_message": sample_output.get("message", "")}}))
	if not _require(int(data.site.next_item) == original_item + 1 and data.site.item_records.has(str(original_item)) and feature.technology_output.receipts.size() == 1, "The original paid Runtime batch genuinely creates the sample bow and its canonical exact8 current receipt"): return {}
	var sample: Dictionary = feature.technology_output.receipts[0]
	if not _require(sample.operator_id == executor and sample.recipe_id == "bow" and sample.item_ids == [str(original_item)] and float(sample.work_seconds) == 108.0, "The certification sample carries only true named effort and the real original item"): return {}
	if not _require(workers.cancel(executor).ok, "The original WT owner releases its actual sample task"): return {}
	workers.discard_prepared_interval()
	Runtime._stop_feature_zones(data, smithy, "operate")
	if not _require(Runtime.request_feature_recipe(data, smithy, "", 1).ok and Stocks.set_local_supply(data, smithy, true, 1).ok, "The real idle workshop switches to its original local stock after completed output"): return {}
	if not _require(orders.certify_workshop(control, "n1", "cert", smithy, "S07", int(sample.id)).ok, "N04 certifies the actual Runtime sample, never a fabricated fixture receipt"): return {}
	if not _require(orders.set_standard(control, "n1", "bow_line", "原弓标准", {"weapon": {"definition": "weapon:bow_01", "alternatives": []}}).ok, "The original national standard references the actual admitted item definition"): return {}
	if first_research:
		if not _require(actions.prepare_scope_technology(control, executor, "N05", "n1").ok and actions.request_scope_technology_consent(control, "nation", "n1", executor).ok, "First N05 uses the real Scope purpose and original team consent before its material grant"): return {}
	var requested = orders.request_military_production_order(control, "n1", "cert", executor, executor, "bow_line")
	if not _require(requested.ok, "Original national production duty opens one actual finite military order"): return {}
	var order_id: String = str(requested.order_id)
	var stock: Variant = Stocks.stock_endpoint(data, smithy)
	var donor = actions._person(control)
	donor.cargo.wood = 4
	donor.cargo.fiber = 2
	var occupied_before: bool = team.cells[team.index_for_identity(executor)] == stock.cell
	if not _require(occupied_before and not lab.character.can_enter_cell(stock.cell), "The actual arrived sample maker still occupies the original stock entrance"): return {}
	if not _release_sample_station(lab, team, executor, stock.cell): return {}
	var donor_arrived: bool = _walk_military_donor(lab, stock.cell)
	if not _return_errors.accepts(self, true, "original donor movement"): return {}
	var grant_before: PackedByteArray = var_to_bytes([data.site, donor.cargo, donor.holder])
	var unauthorized: Dictionary = orders.authorize_military_materials(executor, "n1", order_id, {"wood": 4, "fiber": 2})
	if not _require(not unauthorized.ok and unauthorized.code == "NO_AUTHORITY" and var_to_bytes([data.site, donor.cargo, donor.holder]) == grant_before, "The real sample maker cannot grant the controlled donor's finite batch"): return {}
	var grant: Dictionary = orders.authorize_military_materials(control, "n1", order_id, {"wood": 4, "fiber": 2})
	print("TECH_DONOR_GRANT_DIAG " + JSON.stringify({"occupied_before": occupied_before, "arrived": donor_arrived, "cell": lab.character.terrain_cell, "stock_cell": stock.cell, "moving": lab.character.is_moving(), "grant": grant}))
	if not _require(donor_arrived and grant.ok, "The actual original donor explicitly grants this finite single batch"): return {}
	if not _require(orders.supply_military_production(control, "n1", order_id, {"wood": 4, "fiber": 2}, int(donor.holder.version), int(stock.holder.version)).ok, "Original Vehicle.transfer funds the SAME localstock and records the donor's real transfer"): return {}
	var work_slots: Array[Dictionary] = Runtime.feature_work_slots(data, feature)
	var worker_index: int = team.index_for_identity(executor)
	var worker_cell: Vector2i = team.cells[worker_index]
	if not _require(work_slots.size() == 1 and data.cell_from_index(int(work_slots[0].cell)) == stock.cell and lab.character.terrain_cell == stock.cell and workers._occupied(stock.cell, team, worker_index), "The actual donor occupies the sole original workshop station after transfer"): return {}
	var departure_before: PackedByteArray = var_to_bytes([row, donor.cargo, donor.holder])
	var vacated: bool = false
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var destination: Vector2i = stock.cell + direction
		if not data.can_step(stock.cell, destination) or not lab.character.can_enter_cell(destination) or lab.npc.occupies_cell(destination): continue
		if not _walk_military_donor(lab, destination): return {}
		vacated = not lab.character.occupies_cell(stock.cell)
		break
	if not _require(vacated and not workers._occupied(stock.cell, team, worker_index) and team.cells[worker_index] == worker_cell and var_to_bytes([row, donor.cargo, donor.holder]) == departure_before, "Original donor genuinely vacates the station without moving the away worker, changing its task or altering paid cargo and holder"): return {}
	var before: PackedByteArray = var_to_bytes([data.site, row])
	var initial = orders.military_work_preflight("n1", order_id)
	if not _require(initial.ok and feature.get("recipe_id", "").is_empty() and initial.person.cell != stock.cell and var_to_bytes([data.site, row]) == before, "True NPC initial preflight is read-only and does not require arrival or old recipe bow"): return {}
	if not _require(not orders.military_order_admission("n1", order_id, smithy, executor, Runtime.RANGED_RECIPES.bow.cost).ok and var_to_bytes([data.site, row]) == before, "Actual manufacturing admission still refuses before genuine recipe and station adoption"): return {}
	return {"data": data, "lab": lab, "team": team, "row": row, "executor": executor, "control": control, "actions": actions,
		"orders": orders, "smithy": smithy, "feature": feature, "stock": stock, "order_id": order_id, "donor": donor}

func _military_produce(first_research: bool) -> bool:
	var fixture: Dictionary = _military_fixture(first_research)
	if not _return_errors.accepts(self, true, "callee failure"): return false
	var data: TerrainData = fixture.data
	var lab: TerrainLab = fixture.lab
	var row: Dictionary = fixture.row
	var feature: Dictionary = fixture.feature
	var stock: Dictionary = fixture.stock
	var order: Dictionary = data.site.equipment_nations.n1.technology_operations.orders[fixture.order_id]
	var donor_spent: PackedByteArray = var_to_bytes(order.source.spent)
	var camp = data.site.inventory.duplicate()
	var before: PackedByteArray = var_to_bytes([data.site, row])
	var result = fixture.actions.begin_scope_technology_phase(int(fixture.control), "nation", "n1", "workshop_bow", "feature:" + str(fixture.smithy)) if first_research else Runtime.begin_nation_military_operation(data, "n1", str(fixture.order_id), true)
	if first_research:
		if not _require(result.ok, "First N05 binds a true military localstock source without a pre-existing Scope grant"): return false
	else:
		if not _require(result.ok and var_to_bytes([data.site, row]) == before, "Known N05 preview pays nothing and mutates neither original order nor recipe/task"): return false
		var available: int = int(stock.cargo.wood)
		stock.cargo.wood = 0
		before = var_to_bytes([data.site, row])
		var refused: Variant = Runtime.begin_nation_military_operation(data, "n1", str(fixture.order_id))
		if not _require(not refused.ok and var_to_bytes([data.site, row]) == before, "An abundant unrelated camp cannot conceal insufficient actual military localstock"): return false
		stock.cargo.wood = available
		result = Runtime.begin_nation_military_operation(data, "n1", str(fixture.order_id))
		if not _require(result.ok, "The true known military order publishes one real paid named workshop batch"): return false
	if not _require(data.site.inventory == camp and Runtime.inventory_size(stock.cargo) == 0 and var_to_bytes(order.source.spent) == donor_spent and row.work_task.version == 3 and row.work_task.named, "Manufacturing debits localstock once, never the donor again or the camp, and publishes the original named task"): return false
	if not _require(feature.technology_order == {"nation_id": "n1", "order_id": str(fixture.order_id)} and Runtime.validate_technology_target_storage(data, str(fixture.smithy), feature).ok, "The canonical military namespace and consumed payment ledger pass original strict target validation"): return false
	var source = fixture.actions.nation_operation_material_source_candidate("n1", str(fixture.order_id), "workshop_bow")
	if not first_research:
		if not _require(source.ok and source.source.spent.is_empty(), "Donor transfer history does not become a second manufactured batch payment"): return false
	before = var_to_bytes([data.site, row])
	var resumed = fixture.actions.begin_scope_technology_phase(int(fixture.control), "nation", "n1", "workshop_bow", "feature:" + str(fixture.smithy)) if first_research else Runtime.begin_nation_military_operation(data, "n1", str(fixture.order_id))
	if not _require(resumed.ok and resumed.resumed and resumed.already_working and var_to_bytes([data.site, row]) == before, "The actual accepted named military task resumes as an exact no-op with empty paid localstock"): return false
	var next_item: int = int(data.site.next_item)
	if not _arrive_workshop_operator(lab, fixture.team, int(fixture.executor), str(fixture.smithy)): return false
	Runtime._feature_work(data, str(fixture.smithy), float(Runtime.feature_recipe(feature).cycle), Callable(), Callable(), row.work_task, row.cargo, Runtime.CARRY_CAPACITY, int(fixture.team.faction_id), int(fixture.executor))
	if not _return_errors.accepts(self, true, "original paid workshop work"): return false
	order = data.site.equipment_nations.n1.technology_operations.orders[fixture.order_id]
	if not _require(order.status == "complete" and order.receipt_ids.size() == 1 and order.accepted_receipts.size() == 1 and int(data.site.next_item) == next_item + 1 and data.site.item_records[str(next_item)].definition == "weapon:bow_01", "True original manufacturing commits one actual bow plus one exact8 canonical and finite military accepted receipt"): return false
	if not _require(row.work_task.is_empty() and not lab.site_controller.work_team.is_assigned(int(fixture.executor)) and not feature.has("tech_batch") and not feature.has("technology_order") and var_to_bytes(order.source.spent) == donor_spent and data.site.inventory == camp, "Successful named output stops the finite original task and cannot silently begin another paid batch"): return false
	if first_research:
		var project: Dictionary = Technology.active_project(data.site.equipment_nations.n1.technology)
		if not _require(project.budget.spent == {"wood": 4, "fiber": 2} and project.budget.payments.size() == 1 and project.receipts.size() == 1 and not Technology.scope_known(data.site.equipment_nations.n1.technology, "N05"), "One actual new Scope payment and truthful bow phase are retained; N05 still needs its separate original five-second issue phase"): return false
	before = var_to_bytes([data.site, row])
	if not _require(not Runtime.begin_nation_military_operation(data, "n1", str(fixture.order_id)).ok and var_to_bytes([data.site, row]) == before, "Completed max1 order cannot create a second bow or receipt"): return false
	_cleanup_fixture(lab, fixture.team)
	if not _return_errors.accepts(self, true, "callee failure"): return false
	await process_frame
	return true

func _run() -> void:
	deadline = Time.get_ticks_msec() + 90000
	var returned_phase_0_next: bool = await _military_produce(false)
	if not returned_phase_0_next: return
	var returned_phase_0_first: bool = await _military_produce(true)
	if not returned_phase_0_first: return
	TerrainArmy.release_contact_source()
	if not _return_errors.accepts(self, true, "before PASS"): return
	print("SITE_TECHNOLOGY_MILITARY_PRODUCTION_PASS: %d checks; true ordinary sample/certification/donor transfer/N05 local payment/named original output/replay; issue phase, shared clock, Native and full40 excluded" % checks)
	quit(0)

func _sample_operator_facts(lab: TerrainLab, team: TerrainArmy, executor: int, row: Dictionary, task: Dictionary) -> Dictionary:
	var actions: SitePersonActions = lab.site_controller.person_actions
	var person: Dictionary = actions._person(executor)
	var operator: Dictionary = actions._technology_operator_for_task(task, executor)
	var facts: Dictionary = {"executor": executor, "row_id": row.get("person_id"), "row_F07": Technology.learned(row.get("technology", {}), "F07"),
		"runtime_actions_same": is_same(Runtime._technology_actions(lab.terrain), actions), "person_present": not person.is_empty(),
		"operator_present": not operator.is_empty(), "operator_id": operator.get("person_id"), "assigned": lab.site_controller.work_team.is_assigned(executor),
		"task_same": is_same(row.get("work_task"), task)}
	if not person.is_empty():
		facts.merge({"person_id": person.person_id, "owner_same_team": person.owner == team, "body_same_row": is_same(person.body, row),
			"person_F07": Technology.learned(actions._body_get(person, "technology"), "F07"), "person_technology": actions._body_get(person, "technology"),
			"hp": person.hp, "ko": person.ko, "moving": person.moving, "captive": person.captive,
			"can_act": team.combat_can_act(int(person.unit)), "pose": actions._body_get(person, "pose"), "attack": actions._body_get(person, "attack"),
			"stagger": actions._body_get(person, "exchange_stagger"), "threat": actions._threat(person, {})})
	return facts

func _arrive_workshop_operator(lab: TerrainLab, team: TerrainArmy, executor: int, key: String) -> bool:
	var workers: SiteWorkTeam = lab.site_controller.work_team
	var index: int = team.index_for_identity(executor)
	var row: Dictionary = team.combat_units[index]
	var feature: Dictionary = lab.terrain.site.features[key]
	var work_before: PackedByteArray = var_to_bytes([lab.terrain.site.inventory, lab.terrain.site.item_records, lab.terrain.site.next_item, feature.get("batch_paid"), feature.get("production"), feature.get("tech_batch", {}), row.technology])
	for step: int in range(128):
		if not _require(Time.get_ticks_msec() < deadline, "Original workshop arrival remains within the existing deadline"): return false
		workers.prepare_work_requests(0.5)
		if not _return_errors.accepts(self, true, "original WT route selection"): return false
		var task: Dictionary = row.work_task
		if not _require(task.get("target") == "feature:" + key and task.get("action") == "operate", "Original WT keeps the same actual workshop target while walking"): return false
		var operator: Dictionary = lab.site_controller.person_actions._technology_operator_for_task(task, executor)
		if not operator.is_empty():
			workers.discard_prepared_interval()
			if not _require(is_same(operator.body, row) and team.moving_to[index] == TerrainArmy.INVALID_CELL and lab.terrain.index(team.cells[index]) == int(task.work_cell), "Only the same genuinely arrived idle original maker becomes the real workshop operator"): return false
			if not _require(var_to_bytes([lab.terrain.site.inventory, lab.terrain.site.item_records, lab.terrain.site.next_item, feature.get("batch_paid"), feature.get("production"), feature.get("tech_batch", {}), row.technology]) == work_before, "Arrival alone neither pays nor produces nor changes original knowledge or receipts"): return false
			return true
		var next: Vector2i = team.moving_to[index]
		if not _require(next != TerrainArmy.INVALID_CELL and lab.terrain.can_step(team.cells[index], next) and int(team._reserved_cells.get(next, -1)) == index, "A not-yet-ready maker must own one genuine adjacent reserved movement step"): return false
		team.prepare_combat(float(team.move_duration[index]) + 0.00001)
		if not _return_errors.accepts(self, true, "original Army movement completion"): return false
		if not _require(team.cells[index] == next and team.moving_to[index] == TerrainArmy.INVALID_CELL, "Original Army completes its reserved workshop edge before another selection"): return false
	return _require(false, "Original workshop route did not arrive inside its finite step bound")

func _release_sample_station(lab: TerrainLab, team: TerrainArmy, executor: int, entrance: Vector2i) -> bool:
	var index: int = team.index_for_identity(executor)
	var data: TerrainData = lab.terrain
	var row: Dictionary = team.combat_units[index]
	var before: PackedByteArray = var_to_bytes([data.site.inventory, data.site.item_records, data.site.next_item, data.site.features, row.technology])
	if not _require(not lab.site_controller.work_team.is_assigned(executor) and row.work_task.is_empty() and team.cells[index] == entrance, "Only the original canceled sample worker leaves its real station"): return false
	for direction: Vector2i in TerrainData.DIRECTIONS:
		if not _require(Time.get_ticks_msec() < deadline, "Original sample departure stays within the existing deadline"): return false
		var destination: Vector2i = entrance + direction
		if not team._reserve_combat_step(index, destination): continue
		if not _require(team.moving_to[index] == destination and int(team._reserved_cells.get(destination, -1)) == index, "Sample departure owns a genuine original reserved Army edge"): return false
		team.prepare_combat(float(team.move_duration[index]) + 0.00001)
		if not _return_errors.accepts(self, true, "original sample departure"): return false
		return _require(team.cells[index] == destination and team.moving_to[index] == TerrainArmy.INVALID_CELL and lab.character.can_enter_cell(entrance) and var_to_bytes([data.site.inventory, data.site.item_records, data.site.next_item, data.site.features, row.technology]) == before, "Original Army departure frees the door without new payment, sample, knowledge or receipt")
	return _require(false, "Original sample worker has no legal departure edge")

func _walk_military_donor(lab: TerrainLab, entrance: Vector2i) -> bool:
	var actor: TerrainTestCharacter = lab.character
	var data: TerrainData = lab.terrain
	var donor: Dictionary = lab.site_controller.person_actions._person(lab.controlled_person_id())
	if not _require(not donor.is_empty() and is_same(donor.owner, actor) and is_same(donor.body, actor) and is_same(donor.cargo, data.site.manual.cargo) and is_same(donor.holder, actor.item_state), "Original donor resolution retains the actual Actor body, manual cargo and item holder"): return false
	var before: PackedByteArray = var_to_bytes([data.site.inventory, data.site.item_records, data.site.next_item, data.site.features, data.site.equipment_nations, donor.cargo])
	var blocked: Callable = func(cell: Vector2i) -> bool: return not actor.can_enter_cell(cell) or lab.npc.occupies_cell(cell)
	var path: Array[Vector2i] = data.path_between(actor.terrain_cell, entrance, blocked)
	if not _require(path.size() <= 128 and (actor.terrain_cell == entrance or not path.is_empty()), "Original donor path has a real reachable stock entrance and finite bound"): return false
	for destination: Vector2i in path:
		if not _require(Time.get_ticks_msec() < deadline and actor.step(destination - actor.terrain_cell), "Original donor accepts each legal Actor edge within the existing deadline"): return false
		actor.advance_combat(actor.get_move_interval() + 0.00001)
		if not _return_errors.accepts(self, true, "original donor step completion"): return false
		if not _require(actor.terrain_cell == destination and not actor.is_moving(), "Original Actor genuinely finishes each donor edge"): return false
	var arrived_donor: Dictionary = lab.site_controller.person_actions._person(lab.controlled_person_id())
	if not _require(not arrived_donor.is_empty() and is_same(arrived_donor.owner, actor) and is_same(arrived_donor.body, donor.body) and is_same(arrived_donor.cargo, donor.cargo) and is_same(arrived_donor.cargo, data.site.manual.cargo) and is_same(arrived_donor.holder, donor.holder) and is_same(arrived_donor.holder, actor.item_state), "Original donor movement cannot replace the body, cargo or item holder"): return false
	return _require(actor.terrain_cell == entrance and not actor.is_moving() and var_to_bytes([data.site.inventory, data.site.item_records, data.site.next_item, data.site.features, data.site.equipment_nations, arrived_donor.cargo]) == before, "Donor arrival alone changes no original cargo, payment, sample or authorization")
