extends "res://scripts/tests/site_technology_natural_cold_fixture.gd"

const DisabledCatalogContract = preload("res://scripts/tests/fixtures/disabled_catalog_test_contract.gd")
var _disabled_contract := DisabledCatalogContract.new()

func _finalize() -> void:
	OS.remove_logger(_disabled_contract)

func _initialize() -> void:
	OS.add_logger(_disabled_contract)
	super._initialize()

func _process(delta: float) -> bool:
	if not _disabled_contract.poll(self): return false
	return super._process(delta)

## Original productive PA collector + original Vehicle prepared transfer. Root
## runs only after the shared processing/transfer/source/metal cohort is merged.
## This file does not enable Catalog, fabricate production, or launch Godot.
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const Catalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")

func _metal_fixture() -> Dictionary:
	var specs: Array = [
		{"kind": "smelter", "anchor": Vector2i(25, 18), "extent": Vector2i.ONE},
		{"kind": "smithy", "anchor": Vector2i(34, 18), "extent": Vector2i.ONE},
		{"kind": "settlement_center", "anchor": Vector2i(18, 10), "extent": Vector2i(5, 5)},
	]
	var selected = _cold_natural_template(specs, "technology-s04-natural")
	if not _disabled_contract.poll(self): return {}
	var data: TerrainData = selected.data
	var offset: Vector2i = selected.offset
	var smelter = _cold_natural_feature(data, "smelter", Vector2i(25, 18) + offset)
	if not _disabled_contract.poll(self): return {}
	var smithy = _cold_natural_feature(data, "smithy", Vector2i(34, 18) + offset)
	if not _disabled_contract.poll(self): return {}
	var lab = _cold_natural_lab(data)
	if not _disabled_contract.poll(self): return {}
	var actions = lab.site_controller.person_actions
	var control = int(lab.controlled_person_id())
	var refs: Array = [{"site_id": str(data.site.id), "person_id": control, "path": "", "label": "原冶鐵者", "age_years": -1}]
	assert(lab.site_controller.family_continuity.register_members(refs, true, control).ok)
	assert(lab.site_controller.family_continuity.appoint_head(control, control).ok)
	data.site.family = actions._technology_candidate()
	data.site.family.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.family.technology.known = ["F04"] # Legitimate strict saved-world prerequisite, never S04 evidence.
	lab.character.technology = Technology.learned_candidate(lab.character.technology, "F04")
	assert(Family.validate_family(data.site.family, str(data.site.id)))
	var center = Runtime.building_cells(data, "settlement_center", Vector2i(18, 10) + offset, Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	var cells: Array[int] = []
	cells.assign(center.cells)
	assert(lab.character.place(data.cell_from_index(int(selected.plans[2].preview.entrance)), true))
	for key: String in selected.plans[2].preview.get("clearing", []): Env.change(data, key, {"cleared": true, "remaining": 0})
	var founded = Settlement.found(lab, control, cells)
	assert(founded.ok, str(founded))
	_complete_key(data, str(founded.feature))
	if not _disabled_contract.poll(self): return {}
	data.site.settlement.version = 2
	data.site.settlement.technology = Technology.empty_scope_record(str(data.site.id))
	assert(Settlement.status(lab).effective)
	assert(Stocks.set_local_supply(data, smelter, true, 1).ok and Stocks.set_local_supply(data, smithy, true, 1).ok)
	var person: Dictionary = actions._person(control)
	person.cargo.clear()
	person.cargo.merge({"iron_ore": 3, "charcoal": 3, "wood": 1}) # Explicit finite original actor inventory precondition.
	var stock = Stocks.stock_endpoint(data, smelter)
	assert(lab.character.place(stock.cell, true))
	assert(lab.site_controller.vehicles.transfer("person:" + str(control), "feature:" + smelter, {"iron_ore": 3, "charcoal": 2}, [], int(person.holder.version), int(stock.holder.version), control).ok)
	assert(stock.cargo == {"iron_ore": 3, "charcoal": 2} and person.cargo == {"charcoal": 1, "wood": 1})
	return {"data": data, "lab": lab, "actions": actions, "control": control, "smelter": smelter, "smithy": smithy, "stock": stock, "person": person}

func _metal_interval(f: Dictionary, seconds: float) -> void:
	var requests: Array = f.actions.work_requests(seconds)
	assert(requests.size() == 1 and requests[0].provider == "person_actions")
	var plan = Fatigue.plan_work_interval(requests, seconds)
	assert(plan.ok, str(plan))
	f.lab._shared_work_plan = plan
	f.lab._shared_work_pools_committed = false
	f.lab.site_controller._shared_work_plan = plan
	var owned = {"jobs": plan.jobs.get("person_actions", {})}
	f.actions.advance(seconds, owned)
	f.lab._commit_shared_work_pools()
	var before = var_to_bytes([f.data.site, f.lab.character.capture_state(), f.actions._jobs])
	f.actions.advance(seconds, owned)
	f.lab._commit_shared_work_pools()
	assert(var_to_bytes([f.data.site, f.lab.character.capture_state(), f.actions._jobs]) == before, "Repeated accepted interval changed mass/progress/payment/fatigue")

func _metal_finish(f: Dictionary, key: String) -> void:
	for tick: int in 100:
		if not f.data.site.features[key].has("tech_batch"): break
		assert(f.actions.is_busy(int(f.control)))
		_metal_interval(f, 60.0)
		if not _disabled_contract.poll(self): return
	assert(not f.data.site.features[key].has("tech_batch") and not f.actions.is_busy(int(f.control)))
	f.lab._clear_shared_work_step()

func _metal_scope_begin(f: Dictionary, order_id: String, binding: String, key: String) -> Dictionary:
	return f.actions.begin_scope_technology_phase(int(f.control), "settlement", str(f.data.site.settlement.settlement_id), binding, "feature:" + key, {"order_id": order_id})

## Holders keep an emptied resource at 0 (add_items never erases); compare the real contents.
func _metal_nonzero(cargo: Dictionary) -> Dictionary:
	var result := {}
	for item: Variant in cargo:
		if int(cargo[item]) != 0: result[item] = int(cargo[item])
	return result

func _metal_mass(f: Dictionary) -> int:
	var total = int(f.actions._person(int(f.control)).cargo.get("iron", 0))
	for stock: Dictionary in f.data.site.stockpiles.values(): total += int(stock.cargo.get("iron", 0))
	return total

func _metal_negative_schema(f: Dictionary, order: Dictionary) -> void:
	var before = var_to_bytes(f.data.site)
	for field: String in ["carrier_id", "source", "carry_receipts", "project_id", "cap"]:
		var malformed: Dictionary = order.duplicate(true)
		malformed.payload.erase(field)
		assert(not Runtime.valid_settlement_metal_order(f.data, f.data.site, malformed), field)
	var malformed: Dictionary = order.duplicate(true)
	malformed.payload.cap.iron = 2
	assert(not Runtime.valid_settlement_metal_order(f.data, f.data.site, malformed), "Transaction cap collapsed transfer and consumption")
	malformed = order.duplicate(true)
	malformed.payload.carrier_id = int(order.payload.operator_id) + 1
	assert(not Runtime.valid_settlement_metal_order(f.data, f.data.site, malformed), "First slice invented executor-handoff authority")
	malformed = order.duplicate(true)
	malformed.payload.source.status = "paid"
	assert(not Runtime.valid_settlement_metal_order(f.data, f.data.site, malformed))
	if not order.payload.carry_receipts.is_empty():
		for field: String in ["token", "payment_id", "source_version"]:
			malformed = order.duplicate(true)
			malformed.payload.carry_receipts[0].erase(field)
			assert(not Runtime.valid_settlement_metal_order(f.data, f.data.site, malformed))
		malformed = order.duplicate(true)
		malformed.payload.carry_receipts[0].person_cell = [1, 1]
		assert(not Runtime.valid_settlement_metal_order(f.data, f.data.site, malformed), "Remote forged contact became accepted evidence")
	assert(var_to_bytes(f.data.site) == before, "Malformed cold validation mutated an original owner")

func _metal_known_chain() -> void:
	var f = _metal_fixture()
	if not _disabled_contract.poll(self): return
	var data: TerrainData = f.data
	data.site.settlement.technology.known = ["S04"] # Explicit pre-existing institution, not a research result.
	var id_scope = str(data.site.settlement.settlement_id)
	var request: Dictionary = f.actions.request_settlement_metal_order(int(f.control), str(f.smelter), str(f.smithy), int(f.control))
	assert(request.ok, str(request))
	var id = str(request.order_id)
	var order: Dictionary = data.site.settlement.technology_operations.orders[id]
	var scope_before = var_to_bytes(data.site.settlement.technology)
	var before = var_to_bytes([data.site, f.actions._jobs])
	assert(Runtime.begin_settlement_metal_operation(data, id_scope, id, true).ok and var_to_bytes([data.site, f.actions._jobs]) == before, "Known preview mutated original owners")
	assert(f.actions.begin_settlement_metal_operation(int(f.control), id_scope, id).ok)
	_metal_finish(f, str(f.smelter))
	if not _disabled_contract.poll(self): return
	var pending = Runtime.prepare_settlement_metal_transfer(data, id_scope, id, int(f.control))
	assert(pending.ok, str(pending))
	before = var_to_bytes([data.site, f.actions._jobs])
	var forged = pending.duplicate()
	forged.transfer = pending.transfer.duplicate()
	forged.transfer.source = pending.transfer.source.duplicate(true)
	assert(not Runtime.validate_settlement_metal_transfer(forged).ok, "Equal copied holder was accepted as the original source")
	forged = pending.duplicate()
	forged.transfer = pending.transfer.duplicate()
	forged.transfer.source_version = int(pending.transfer.source_version) + 1
	assert(not Runtime.validate_settlement_metal_transfer(forged).ok, "Stale transfer version passed before publication")
	assert(not Runtime.prepare_settlement_metal_transfer(data, id_scope, id, int(f.control) + 1).ok)
	assert(not f.lab.site_controller.vehicles.prepare_transfer("depot", "person:" + str(int(f.control)), {"iron": 2}, [], int(data.site.depot_items.version), int(f.person.holder.version), int(f.control)).ok, "Metal work broadened the original Actor camp logistics guard")
	assert(var_to_bytes([data.site, f.actions._jobs]) == before)
	assert(f.actions.begin_settlement_metal_operation(int(f.control), id_scope, id).ok and _metal_mass(f) == 2)
	var smithy = Stocks.stock_endpoint(data, str(f.smithy))
	assert(f.lab.character.place(smithy.cell, true))
	assert(f.actions.begin_settlement_metal_operation(int(f.control), id_scope, id).ok and _metal_mass(f) == 2)
	assert(f.lab.site_controller.vehicles.transfer("person:" + str(int(f.control)), "feature:" + str(f.smithy), {"charcoal": 1, "wood": 1}, [], int(f.person.holder.version), int(smithy.holder.version), int(f.control)).ok)
	assert(f.actions.grant_settlement_metal_source(int(f.control), id_scope, id).ok)
	assert(f.actions.begin_settlement_metal_operation(int(f.control), id_scope, id).ok)
	_metal_finish(f, str(f.smithy))
	if not _disabled_contract.poll(self): return
	assert(order.status == "completed" and order.payload.spent == Runtime.SETTLEMENT_METAL_CAP and _metal_nonzero(smithy.cargo) == {"tools": 1})
	assert(var_to_bytes(data.site.settlement.technology) == scope_before and order.payload.carry_receipts[0].token.is_empty(), "Known operation fabricated new research evidence")
	f.lab.queue_free()
	await process_frame
	if not _disabled_contract.poll(self): return

func _run() -> void:
	if not _disabled_contract.begin(self, ["S04"]): return
	var f = _metal_fixture()
	if not _disabled_contract.poll(self): return
	var data: TerrainData = f.data
	var scope_id = str(data.site.settlement.settlement_id)
	var before = var_to_bytes([data.site, f.lab.character.capture_state(), f.actions._jobs])
	var node = f.lab.find_child("ScopeTechnologyNode", true, false) as OptionButton
	assert(node != null)
	for index: int in node.item_count:
		if node.get_item_metadata(index) == "S04": node.select(index); node.item_selected.emit(index); break
	var request_button = f.lab.find_child("MetalRequestOrder", true, false) as Button
	assert(request_button != null)
	if Catalog.get_node("S04").get("enabled") != true:
		assert(request_button.disabled)
		assert(not f.actions.prepare_scope_technology(int(f.control), int(f.control), "S04", scope_id).ok)
		assert(not f.actions.request_settlement_metal_order(int(f.control), str(f.smelter), str(f.smithy), int(f.control)).ok)
		assert(var_to_bytes([data.site, f.lab.character.capture_state(), f.actions._jobs]) == before, "Disabled S04 changed bytes or charged materials")
		var original = Runtime.feature_recipe(data.site.features[f.smelter])
		assert(original.input == {"iron_ore": 3, "charcoal": 2} and original.output == {"iron": 2} and str(data.site.features[f.smelter].get("recipe_id", "")).is_empty())
		f.lab.queue_free()
		await process_frame
		if not _disabled_contract.poll(self): return
		if not _disabled_contract.ready(self): return
		print("S04_DISABLED_BYTE_BOUNDARY_PASS; PRODUCTIVE_CASES_NOT_RUN_ACTIVATION_REQUIRED")
		if not _disabled_contract.emit_disabled(self, "site_settlement_metal_chain_test", 6): return
		quit(0)
		return
	assert(f.actions.prepare_scope_technology(int(f.control), int(f.control), "S04", scope_id).ok)
	assert(f.actions.request_scope_technology_consent(int(f.control), "settlement", scope_id, int(f.control)).ok)
	var project = Technology.active_project(data.site.settlement.technology)
	var opened: Dictionary = f.actions.request_settlement_metal_order(int(f.control), str(f.smelter), str(f.smithy), int(f.control), int(project.id))
	assert(opened.ok, str(opened))
	var id = str(opened.order_id)
	var order: Dictionary = data.site.settlement.technology_operations.orders[id]
	assert(Runtime.valid_settlement_metal_order(data, data.site, order) and order.payload.cap == Runtime.SETTLEMENT_METAL_CAP)
	_metal_negative_schema(f, order)
	if not _disabled_contract.poll(self): return
	var camp: Dictionary = data.site.inventory.duplicate()
	var stock = Stocks.stock_endpoint(data, str(f.smelter))
	assert(f.lab.character.place(stock.cell, true))
	var iron_begun: Dictionary = _metal_scope_begin(f, id, "iron", str(f.smelter))
	assert(iron_begun.ok, str(iron_begun))
	# add_items keeps an emptied resource at 0 rather than erasing it; the debit is what counts.
	var stock_left := 0
	for item: String in stock.cargo: stock_left += int(stock.cargo[item])
	assert(stock_left == 0 and data.site.inventory == camp and not Technology.scope_known(data.site.settlement.technology, "S04"), "first iron step pays from the order source only: stock=%s camp_same=%s" % [str(stock.cargo), str(data.site.inventory == camp)])
	assert(f.actions.is_busy(int(f.control)) and not f.actions.save_guard().ok)
	_metal_finish(f, str(f.smelter))
	if not _disabled_contract.poll(self): return
	assert(order.payload.completed == 1 and order.receipts.size() == 1 and _metal_mass(f) == 2 and _metal_nonzero(stock.cargo) == {"iron": 2}, "iron stage completes once: completed=%s receipts=%s mass=%s stock=%s status=%s" % [order.payload.completed, order.receipts.size(), _metal_mass(f), str(stock.cargo), order.status])
	assert(not data.site.features[f.smelter].has("technology_settlement_order") and not Technology.scope_known(data.site.settlement.technology, "S04"))
	assert(Technology.active_project(data.site.settlement.technology).receipts.size() == 1)
	assert(_metal_scope_begin(f, id, "transfer", str(f.smelter)).ok)
	assert(_metal_nonzero(stock.cargo).is_empty() and int(f.person.cargo.iron) == 2 and _metal_mass(f) == 2 and order.payload.carry_receipts.size() == 1)
	assert(order.payload.spent == {"iron_ore": 3, "charcoal": 2, "iron": 2})
	assert(Technology.active_project(data.site.settlement.technology).receipts.size() == 1, "First contact alone completed transfer")
	before = var_to_bytes([data.site, f.lab.character.capture_state()])
	assert(not _metal_scope_begin(f, id, "transfer", str(f.smelter)).ok)
	assert(var_to_bytes([data.site, f.lab.character.capture_state()]) == before, "Remote second contact changed original bytes")
	_metal_negative_schema(f, order)
	if not _disabled_contract.poll(self): return
	# No PA timer remains. The original saved Actor owns its physical iron and
	# the original bounded order retains the first accepted transfer fact.
	f.lab.site_controller._capture_positions()
	assert(Store.save(data, "res://.godot-temp/site_settlement_metal_chain_v1/carry.json").ok)
	var source_fingerprint = data.fingerprint()
	var source_conditions = _cold_natural_conditions(data)
	var loaded = Store.load_site("res://.godot-temp/site_settlement_metal_chain_v1/carry.json")
	assert(loaded.ok, str(loaded))
	assert(loaded.data.fingerprint() == source_fingerprint and _cold_natural_conditions(loaded.data) == source_conditions, "Metal carry cold source/land conditions were not reconstructed")
	assert(Runtime.valid_settlement_metal_order(loaded.data, loaded.data.site, loaded.data.site.settlement.technology_operations.orders[id]))
	assert(int(loaded.data.site.manual.cargo.iron) == 2, "Original Actor cargo lives in the original Site manual record")
	f.lab.bind_terrain(loaded.data) # Real load→original Actor/Army→current offices/meta binding.
	f.data = loaded.data
	data = loaded.data
	f.actions = f.lab.site_controller.person_actions
	f.person = f.actions._person(int(f.control))
	order = data.site.settlement.technology_operations.orders[id]
	var smithy = Stocks.stock_endpoint(data, str(f.smithy))
	assert(f.lab.character.place(smithy.cell, true))
	var payments = Technology.active_project(data.site.settlement.technology).budget.payments.size()
	assert(_metal_scope_begin(f, id, "transfer", str(f.smelter)).ok)
	assert(_metal_mass(f) == 2 and not f.person.cargo.has("iron") and int(smithy.cargo.iron) == 2 and order.payload.carry_receipts.size() == 2)
	project = Technology.active_project(data.site.settlement.technology)
	assert(project.receipts.size() == 2 and project.receipts[1].work_seconds == 0.0 and project.budget.payments.size() == payments)
	assert(order.payload.feature_id == f.smithy and order.payload.spent.iron == 2)
	assert(f.lab.site_controller.vehicles.transfer("person:" + str(int(f.control)), "feature:" + str(f.smithy), {"charcoal": 1, "wood": 1}, [], int(f.person.holder.version), int(smithy.holder.version), int(f.control)).ok)
	before = var_to_bytes([data.site, f.actions._jobs])
	assert(not _metal_scope_begin(f, id, "tools", str(f.smithy)).ok)
	assert(var_to_bytes([data.site, f.actions._jobs]) == before, "Tools silently swapped a finite source without head grant")
	assert(f.actions.grant_settlement_metal_source(int(f.control), scope_id, id).ok)
	assert(order.payload.source.holder == "feature:" + str(f.smithy) and order.payload.spent.iron == 2)
	assert(_metal_scope_begin(f, id, "tools", str(f.smithy)).ok)
	assert(_metal_nonzero(smithy.cargo).is_empty() and _metal_mass(f) == 0 and data.site.inventory == camp)
	_metal_finish(f, str(f.smithy))
	if not _disabled_contract.poll(self): return
	assert(order.status == "completed" and order.receipts.size() == 2 and order.payload.spent == Runtime.SETTLEMENT_METAL_CAP)
	assert(_metal_nonzero(smithy.cargo) == {"tools": 1} and Technology.scope_known(data.site.settlement.technology, "S04"))
	project = data.site.settlement.technology.projects[0]
	assert(project.receipts.size() == 3 and project.budget.payments.size() == 3 and project.budget.spent.iron == 4)
	before = var_to_bytes([data.site, f.actions._jobs])
	assert(not _metal_scope_begin(f, id, "tools", str(f.smithy)).ok and var_to_bytes([data.site, f.actions._jobs]) == before, "Completed order manufactured again")
	_metal_negative_schema(f, order)
	if not _disabled_contract.poll(self): return
	# Accepted history does not borrow live artifacts as its permanent source.
	var cold: Dictionary = data.site.duplicate(true)
	cold.features.erase(str(f.smelter))
	cold.features.erase(str(f.smithy))
	cold.stockpiles.erase(str(f.smelter))
	cold.stockpiles.erase(str(f.smithy))
	assert(Runtime.valid_settlement_metal_order(data, cold, cold.settlement.technology_operations.orders[id]), "Legal host removal retroactively erased accepted history")
	f.lab.queue_free()
	await process_frame
	if not _disabled_contract.poll(self): return
	await _metal_known_chain()
	if not _disabled_contract.poll(self): return
	await process_frame
	if not _disabled_contract.ready(self): return
	print("SITE_SETTLEMENT_METAL_CHAIN_PASS: actual original 900/transfer0/720; known and first research; finite private material conservation; two physical contacts; one phase payment per stage; strict cold/replay; Native/AI/full40 excluded")
	quit(0)
