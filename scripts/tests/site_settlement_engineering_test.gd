extends "res://scripts/tests/site_building_ui_test.gd"

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

## Root named source cohort only. No Godot was run by this package.
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const Catalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")

func _engineering_fixture() -> Dictionary:
	var data = _building_fixture()
	if not _disabled_contract.poll(self): return {}
	var lab = _building_lab(data)
	if not _disabled_contract.poll(self): return {}
	var control = lab.controlled_person_id()
	# Real camp adjacency. Initial building fixture's diagonal (10,10) is not
	# sufficient for the original finite camp-source command.
	assert(lab.character.place(Vector2i(9, 10), true))
	var placement = Runtime.building_cells(data, "settlement_center", Vector2i(18, 10), Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	var cells: Array[int] = []
	cells.assign(placement.cells)
	var founded = Settlement.found(lab, control, cells)
	assert(founded.ok, str(founded))
	_complete_key(data, str(founded.feature))
	if not _disabled_contract.poll(self): return {}
	data.site.settlement.version = 2
	data.site.settlement.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.settlement.technology.known = ["S09", "S10"] # Saved-world precondition, no research claim.
	var team: TerrainArmy = lab.army
	team.faction_id = 1
	team.roster_size = 2
	assert(team.deploy_at(data, lab.character, lab.npc, [Vector2i(12, 12), Vector2i(13, 12)]) and team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()
	if not lab.combat_armies.has(team): lab.combat_armies.append(team)
	team.controlled_person_query = lab.controlled_person_id
	team.person_busy_query = lab.site_controller.person_actions.is_busy
	assert(team.join_player(lab.character).ok)
	var offices: Dictionary = team.team_offices()
	var appointment = team.apply_office_plan(team.combat_identity(team.formal_commander), int(offices.revision), [
		{"op": "add", "name": "施工主持", "office_class": "civil", "ref": "engineering_work"},
		{"op": "appoint", "position_id": "engineering_work", "person_id": control},
		{"op": "assign", "position_id": "engineering_work", "duty_id": "team.work"}])
	assert(appointment.ok, str(appointment))
	assert(team.duty_resolve_readonly("team.work").get("decider") == control)
	assert(Settlement.status(lab).effective)
	return {"data": data, "lab": lab, "team": team, "control": control, "actions": lab.site_controller.person_actions}

func _set_named_station(f: Dictionary, index: int) -> Dictionary:
	var task: Dictionary = f.team.combat_units[index].work_task
	f.team.cells[index] = f.data.cell_from_index(int(task.work_cell))
	task.cell = int(task.work_cell)
	task.mode = "work"
	return task

func _run() -> void:
	if not _disabled_contract.begin(self, ["S09", "S10"]): return
	var f = _engineering_fixture()
	if not _disabled_contract.poll(self): return
	var data: TerrainData = f.data
	var source = _formal_feature(data, "stone_wall", Vector2i(20, 18))
	if not _disabled_contract.poll(self): return
	var before = var_to_bytes(data.site)
	if Catalog.get_node("S09").get("enabled") != true or Catalog.get_node("S10").get("enabled") != true:
		assert(not Runtime.save_settlement_blueprint(data, int(f.control), source, "城牆", true).ok)
		assert(var_to_bytes(data.site) == before, "Disabled engineering changed original state")
		# The already successful original stock wall and original repair remain legal.
		var part: String = data.site.features[source].parts.keys()[0]
		assert(Runtime.damage_structure_part(data, source, part, 1.0).ok)
		assert(Runtime.request_repair(data, source, part, 1).ok)
		f.lab.queue_free()
		await process_frame
		if not _disabled_contract.poll(self): return
		if not _disabled_contract.ready(self): return
		print("S09_S10_DISABLED_BOUNDARY_PASS; PRODUCTIVE_CASES_NOT_RUN_ACTIVATION_REQUIRED")
		if not _disabled_contract.emit_disabled(self, "site_settlement_engineering_test", 4): return
		quit(0)
		return
	assert(Runtime.save_settlement_blueprint(data, int(f.control), source, "城牆", true).ok)
	assert(var_to_bytes(data.site) == before)
	var saved = Runtime.save_settlement_blueprint(data, int(f.control), source, "城牆")
	assert(saved.ok, str(saved))
	var plan_id = str(saved.plan_id)
	var plan: Dictionary = data.site.settlement.technology_operations.plans[plan_id]
	assert(not plan.has("progress") and not plan.has("cost") and not plan.has("person_ids"))
	before = var_to_bytes(data.site)
	assert(not Runtime.reuse_settlement_blueprint(data, int(f.control), plan_id, Vector2i(20, 18)).ok)
	assert(var_to_bytes(data.site) == before, "Occupied plan reuse changed original stock or plan")
	assert(Runtime.reuse_settlement_blueprint(data, int(f.control), plan_id, Vector2i(22, 20), true).ok)
	assert(var_to_bytes(data.site) == before)
	var reused = Runtime.reuse_settlement_blueprint(data, int(f.control), plan_id, Vector2i(22, 20))
	assert(reused.ok and str(reused.feature) != source)
	_complete_key(data, str(reused.feature))
	if not _disabled_contract.poll(self): return
	var npc = int(f.team.combat_identity(1))
	var steps = [{"action": "construct", "plan_id": plan_id, "anchor": [20, 22], "feature_id": "", "part": "", "operator_id": npc}]
	var target = Runtime.settlement_blueprint_target(data, plan_id, Vector2i(20, 22))
	var preview = Runtime.preview_build(data, target.kind, target.cells, f.lab.site_controller.reserves_cell, target.options)
	assert(preview.ok, str(preview))
	var cost: Dictionary = preview.cost
	var stock = data.site.inventory.duplicate()
	var ordered = Runtime.request_settlement_defense_order(data, int(f.control), steps, [npc], cost)
	assert(ordered.ok, str(ordered))
	var order_id = str(ordered.order_id)
	var operations: Dictionary = data.site.settlement.technology_operations
	var order: Dictionary = operations.orders[order_id]
	assert(order.spent.is_empty() and data.site.inventory == stock and order.consents[0].person_id == npc)
	before = var_to_bytes([data.site, f.team.combat_units[1]])
	assert(Runtime.begin_settlement_defense_step(data, int(f.control), order_id, true).ok)
	assert(var_to_bytes([data.site, f.team.combat_units[1]]) == before, "Preview mutated true row, ops or source")
	var begun = Runtime.begin_settlement_defense_step(data, int(f.control), order_id)
	assert(begun.ok, str(begun))
	assert(is_same(operations, data.site.settlement.technology_operations) and is_same(order, operations.orders[order_id]))
	var task = _set_named_station(f, 1)
	if not _disabled_contract.poll(self): return
	var key = str(task.target).trim_prefix("feature:")
	var feature: Dictionary = data.site.features[key]
	for resource: String in cost: assert(int(data.site.inventory[resource]) == int(stock[resource]) - int(cost[resource]))
	assert(Runtime.valid_settlement_work_storage(data, key, feature) and order.status == "active")
	Runtime._feature_work(data, key, float(feature.work) * 0.5, Callable(), Callable(), task, f.team.combat_units[1].cargo, Runtime.CARRY_CAPACITY, 1, npc)
	assert(float(feature.progress) > 0.0 and feature.stage != "complete" and order.receipts.is_empty())
	stock = data.site.inventory.duplicate()
	assert(Runtime.resume_settlement_defense_step(data, int(f.control), order_id).get("already_working", false))
	assert(data.site.inventory == stock)
	f.lab.site_controller._capture_positions()
	var snapshot = Store.save(data, "res://.godot-temp/site_settlement_engineering_v2/active.json")
	assert(snapshot.ok, str(snapshot))
	var loaded = Store.load_site("res://.godot-temp/site_settlement_engineering_v2/active.json")
	assert(loaded.ok, str(loaded))
	assert(Settlement.valid_technology_operations(loaded.data, loaded.data.site.settlement.technology_operations))
	assert(Runtime.valid_settlement_work_storage(loaded.data, key, loaded.data.site.features[key]))
	assert(float(loaded.data.site.features[key].progress) == float(feature.progress) and loaded.data.site.inventory == stock)
	var corrupt: Dictionary = operations.duplicate(true)
	corrupt.orders[order_id].spent = {}
	assert(not Settlement.valid_technology_operations(data, corrupt), "Unrecorded paid costs accepted")
	corrupt = operations.duplicate(true)
	corrupt.orders[order_id].extra = true
	assert(not Settlement.valid_technology_operations(data, corrupt), "Unknown new fields accepted")
	var foreign: Dictionary = task.duplicate(true)
	foreign.operation_ref = {"settlement_id": str(data.site.settlement.settlement_id), "order_id": order_id, "nation_id": "x"}
	assert(not SiteWorkTeam.valid_task(data, data.site, foreign))
	Runtime._feature_work(data, key, float(feature.work), Callable(), Callable(), task, f.team.combat_units[1].cargo, Runtime.CARRY_CAPACITY, 1, npc)
	assert(feature.stage == "complete" and not feature.has("settlement_work") and order.status == "completed" and order.receipts.size() == 1)
	assert(data.site.inventory == stock and not f.lab.site_controller.work_team.is_assigned(npc))
	assert(Runtime.remove_finished_settlement_defense_order(data, int(f.control), order_id).ok)
	assert(not operations.orders.has(order_id) and int(operations.next_order) == 2)
	# Paid repair cancellation preserves physical progress/cost and releases only
	# this finite worklist. Basic original repair can then finish normally.
	var part: String = feature.parts.keys()[0]
	assert(Runtime.damage_structure_part(data, key, part, 4.0).ok)
	var repair_preview = Runtime.prepare_feature_repair_request(data, key, part, 1)
	assert(repair_preview.ok)
	steps = [{"action": "repair", "plan_id": "", "anchor": [], "feature_id": key, "part": part, "operator_id": npc}]
	ordered = Runtime.request_settlement_defense_order(data, int(f.control), steps, [npc], repair_preview.repair.cost)
	assert(ordered.ok)
	order_id = str(ordered.order_id)
	assert(Runtime.begin_settlement_defense_step(data, int(f.control), order_id).ok)
	task = _set_named_station(f, 1)
	if not _disabled_contract.poll(self): return
	var repair: Dictionary = feature.repair
	stock = data.site.inventory.duplicate()
	Runtime._feature_work(data, key, float(repair.work) * 0.5, Callable(), Callable(), task, f.team.combat_units[1].cargo, Runtime.CARRY_CAPACITY, 1, npc)
	var progress = float(repair.progress)
	assert(progress > 0.0 and Runtime.cancel_settlement_defense_order(data, int(f.control), order_id).ok)
	assert(is_same(repair, feature.repair) and float(repair.progress) == progress and data.site.inventory == stock and not feature.has("settlement_work"))
	Runtime.assign_task(data, Runtime.ok("", {"target": "feature:" + key, "action": "repair", "cell": repair.work_cell}))
	data.site.worker.cell = int(repair.work_cell)
	data.site.worker.mode = "work"
	Runtime._feature_work(data, key, float(repair.work), Callable(), Callable(), data.site.worker, data.site.worker.cargo, Runtime.CARRY_CAPACITY, 1)
	assert(not feature.has("repair") and data.site.inventory == stock)
	f.lab.queue_free()
	await process_frame
	if not _disabled_contract.ready(self): return
	print("S09_S10_ACTIVATED_ORIGINAL_PLAN_NAMED_WORK_COLD_CANCEL_PASS; direct GD intervals only, no Scope/shared-clock/Native/GPU/UI acceptance")
	quit(0)
