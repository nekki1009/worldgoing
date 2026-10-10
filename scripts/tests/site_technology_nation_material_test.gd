extends "res://scripts/tests/site_technology_work_credit_test.gd"
## Real original TerrainLab, Army, Settlement, Housing, Nation offices, public
## orders, source transfers, WorkTeam tasks and Runtime outputs. Known archives
## and one valid prior housing relation are explicit starting-world fixtures.
## Direct productive Runtime intervals exclude clock/Fatigue/travel/UI proof.
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Homes = preload("res://scripts/terrain_lab/site_housing.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")

func _state_bytes(data: TerrainData, row: Dictionary) -> PackedByteArray:
	return var_to_bytes([data.site, row])

func _fund(lab: TerrainLab, order_id: String, cap: Dictionary, warehouse: String) -> Dictionary:
	var actions: SitePersonActions = lab.site_controller.person_actions
	var orders: SiteEquipmentOrders = lab.site_controller.equipment_orders
	var control = lab.controlled_person_id()
	var actor = actions._person(control)
	var reserve = Stocks.storage(lab.terrain, warehouse)
	for item: String in cap: actor.cargo[item] = int(actor.cargo.get(item, 0)) + int(cap[item])
	_check(orders.authorize_public_source(control, "n1", order_id, cap).ok, "Actual controlled original donor names this finite source purpose")
	_check(orders.fund_public_order(control, "n1", order_id, cap, int(actor.holder.version), int(reserve.holder.version)).ok, "Real source transfer funds the actual Warehouse, without paying manufacture yet")
	return reserve

func _at_feature(lab: TerrainLab, team: TerrainArmy, executor: int, key: String) -> Dictionary:
	var row: Dictionary = team.combat_units[team.index_for_identity(executor)]
	var task: Dictionary = row.get("work_task", {})
	_check(task.get("version") == 3 and task.get("named") == true and task.target == "feature:" + key, "Runtime published the true original named task in the same paid commit")
	# Move only the true fixture hot position to its genuinely computed work slot;
	# this excludes route/movement acceptance and does not replace the task/body.
	team.cells[team.index_for_identity(executor)] = lab.terrain.cell_from_index(int(task.work_cell))
	task.cell = int(task.work_cell)
	task.mode = "work"
	return task

func _finish_feature(lab: TerrainLab, team: TerrainArmy, executor: int, key: String, minutes: float) -> void:
	var row: Dictionary = team.combat_units[team.index_for_identity(executor)]
	var task = _at_feature(lab, team, executor, key)
	Runtime._feature_work(lab.terrain, key, minutes, Callable(), Callable(), task, row.cargo, Runtime.CARRY_CAPACITY, int(team.faction_id), executor)

func _nation_fixture(known: Array[String]) -> Dictionary:
	var data = _material_natural_data()
	for item: String in Env.ITEM_NAMES: data.site.inventory[item] = 10000
	data.site.capacity = 1000000
	var lab = _material_natural_lab(data)
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var orders: SiteEquipmentOrders = controller.equipment_orders
	var control = int(lab.controlled_person_id())
	# The same script also verifies real known N11 armor. Its actual level-three
	# and two-workshop requirements need true forty-person prior infrastructure.
	var team = _material_army(lab, 40)
	var executor = team.combat_identity(1)
	var row: Dictionary = team.combat_units[1]
	var center = _material_setup_geometry(lab, "settlement_center", Vector2i(25, 25), Vector2i(5, 5))
	var excluded: Array = center.cells.duplicate()
	excluded.append(int(center.fixture_preview.entrance))
	var houses: Array[String] = []
	for y: int in [10, 40]:
		for x: int in [10, 17, 24, 31, 38]: houses.append(_material_setup_feature(lab, "house", Vector2i(x, y), Vector2i.ONE, {"variant": "large"}, excluded))
	var warehouse = _material_setup_feature(lab, "warehouse", Vector2i(8, 18), Vector2i.ONE, {}, excluded)
	var smithy = _material_setup_feature(lab, "smithy", Vector2i(25, 18), Vector2i.ONE, {}, excluded)
	var tannery = _material_setup_feature(lab, "tannery", Vector2i(34, 18), Vector2i.ONE, {}, excluded)
	_material_setup_feature(lab, "well", Vector2i(9, 25), Vector2i.ONE, {}, excluded)
	_material_setup_feature(lab, "farm", Vector2i(15, 25), Vector2i(2, 2), {}, excluded)
	_check(lab.character.place(data.cell_from_index(int(center.fixture_preview.entrance)), true), "Actual controlled founder reaches the original natural center contact")
	for key: String in center.fixture_preview.get("clearing", []): Env.change(data, key, {"cleared": true, "remaining": 0})
	var center_cells: Array[int] = []
	center_cells.assign(center.cells)
	var founded = Settlement.found(lab, control, center_cells)
	_check(founded.ok, "Original founder creates the actual natural-source Settlement")
	_complete_key(data, str(founded.feature))
	var slots: Array[Dictionary] = []
	# Fixture worlds carry generated natural resources; clear any on each house's
	# entrance row (as for the center clearing) so its real slots are counted.
	for fixture_house: String in houses:
		var fixture_feature: Dictionary = data.site.features[fixture_house]
		for fixture_pair: Dictionary in Runtime._building_entrances(data, fixture_feature.cells, int(fixture_feature.quarter)):
			for fixture_key: String in Env.resources_in(data, Rect2i(fixture_pair.cell, Vector2i.ONE)): Env.change(data, fixture_key, {"cleared": true, "remaining": 0})
	Env.rebuild_indexes(data)
	for home: String in houses:
		var lodging = Runtime.house_layout(data, home)
		_check(lodging.ok, "Original completed large house owns its actual finite resident slots")
		for cell: int in lodging.slots: slots.append({"house_id": home, "cell": cell})
	if slots.size() < team.combat_units.size():
		# Ten houses fell short on this generated world (height step / edge overlap);
		# one more genuine large house keeps a real house slot for every resident.
		var extra_house: String = _material_setup_feature(lab, "house", Vector2i(10, 25), Vector2i.ONE, {"variant": "large"}, excluded)
		var extra_feature: Dictionary = data.site.features[extra_house]
		for fixture_pair: Dictionary in Runtime._building_entrances(data, extra_feature.cells, int(extra_feature.quarter)):
			for fixture_key: String in Env.resources_in(data, Rect2i(fixture_pair.cell, Vector2i.ONE)): Env.change(data, fixture_key, {"cleared": true, "remaining": 0})
		Env.rebuild_indexes(data)
		houses.append(extra_house)
		for cell: int in Runtime.house_layout(data, extra_house).slots: slots.append({"house_id": extra_house, "cell": cell})
	_check(slots.size() >= team.combat_units.size(), "Real houses contain all forty actual original people")
	var people = {}
	var housing = {}
	var members: Array = [control]
	for index: int in team.combat_units.size():
		var identity = team.combat_identity(index)
		members.append(identity)
		housing[str(identity)] = {"version": 1, "house_id": str(slots[index].house_id), "cell": int(slots[index].cell)}
		people[identity] = {"hp": float(team.combat_units[index].hp), "faction_id": 1}
	data.site.housing = housing
	_check(Homes.validate(data, data.site, people).ok and Settlement.residents(lab).size() == 40, "Strict original Housing resolves forty real prior residents, without forging a population field")
	for level: int in [2, 3]:
		var upgraded = Settlement.request_upgrade(lab, control)
		_check(upgraded.ok, "Real original Settlement requirements and full payment admit level " + str(level) + ": " + str(upgraded))
		_complete_key(data, str(founded.feature))
		_check(Settlement.status(lab).effective and int(Settlement.status(lab).level) == level, "The same original center completes its true city upgrade")
	# New optional technology must have the original strict v2 outer schema.
	data.site.settlement.version = 2
	var settlement_tech = Technology.empty_scope_record(str(data.site.id))
	settlement_tech.known = ["S01", "S06", "S09", "S13"]
	data.site.settlement.technology = settlement_tech
	_check(Runtime.technology_armor_workshop_context(data, smithy, "iron_armor").ok, "Actual S13 eligibility uses level3 and both real in-jurisdiction workshops, not a fabricated workshop grade")
	var nation_tech = Technology.empty_scope_record(str(data.site.id))
	nation_tech.known = known.duplicate()
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", control), "members": members, "standards": {}, "technology": nation_tech}}
	_check(Stocks.ensure_storage(data, warehouse, 1).ok, "Original Warehouse owns its actual cargo and holder")
	var entrance = data.cell_from_index(int(data.site.features[warehouse].entrance))
	_check(lab.character.place(entrance, true), "Actual donor reaches the original Warehouse contact")
	var labor = orders.register_nation_labor(control, "n1", [executor])
	_check(labor.ok, "Actual national duty registers this real housed NPC after its real team accepts the finite purpose: " + str(labor))
	return {"data": data, "lab": lab, "warehouse": warehouse, "smithy": smithy, "controller": controller,
		"actions": actions, "orders": orders, "control": control, "team": team, "executor": executor, "row": row,
		"labor": labor, "nation_tech": nation_tech, "entrance": entrance}

func _cleanup_fixture(lab: TerrainLab, team: TerrainArmy) -> void:
	var controller = lab.site_controller
	for identity: int in controller.work_team.active_ids(): controller.work_team.cancel(identity)
	controller.work_team.discard_prepared_interval()
	controller.work_team.unavailable = Callable()
	controller.work_team.vehicle_blocked = Callable()
	controller.equipment_orders.nation_arsenal_request = Callable()
	controller.equipment_orders.nation_owner_receipt_query = Callable()
	team.controlled_person_query = Callable()
	team.person_busy_query = Callable()
	team.queue_free()
	lab.queue_free()

func _research_private_source() -> void:
	var fixture = _nation_fixture(["N01", "N02"])
	var data: TerrainData = fixture.data
	var lab: TerrainLab = fixture.lab
	var actions: SitePersonActions = fixture.actions
	var orders: SiteEquipmentOrders = fixture.orders
	var control = int(fixture.control)
	var executor = int(fixture.executor)
	var team: TerrainArmy = fixture.team
	var row: Dictionary = fixture.row
	_check(actions.prepare_scope_technology(control, executor, "N06", "n1").ok, "A different original initial world starts true first N06 research without an inherited N06 archive")
	_check(actions.request_scope_technology_consent(control, "nation", "n1", executor).ok, "Actual original team accepts this research purpose separately from the actual public labor order")
	var registered = orders.request_public_work_order(control, "n1", "house", str(fixture.labor.order_id), [executor], str(fixture.warehouse))
	_check(registered.ok, "An actual first-research public order is registered before its private source or phase budget is granted")
	var reserve = _fund(lab, str(registered.order_id), {"wood": 8, "stone": 4}, str(fixture.warehouse))
	var nation: Dictionary = data.site.equipment_nations.n1
	var project = Technology.active_project(nation.technology)
	_check(project.budget.is_empty(), "No fabricated depot grant/budget is needed before the first private source admission")
	var options = {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	var geometry = _material_setup_geometry(lab, "house", Vector2i(28, 20), Vector2i(2, 2), options)
	var cells: Array[int] = []
	cells.assign(geometry.cells)
	var target_id = "feature:" + str(int(data.site.next_feature))
	var phase = Technology.scope_next_phase(project, project.executor)
	var token = {"scope": "nation", "scope_id": "n1", "project_id": int(project.id), "epoch": int(nation.technology.epoch),
		"purpose": str(project.purpose), "tech_id": "N06", "phase_id": str(phase.id), "attempt": int(project.next_attempt),
		"person": project.executor.duplicate(), "binding": "house_build", "target_id": target_id, "materials": phase.materials.duplicate()}
	var before = _state_bytes(data, row)
	var preview = Runtime.begin_technology_operation(data, token, true, {"cells": cells, "options": options})
	_check(preview.ok and _state_bytes(data, row) == before and project.budget.is_empty(), "Original true source preflight allows a first N06 preview without publishing grant/attempt/feature/zone/task")
	var source_version = int(reserve.holder.version)
	var camp = data.site.inventory.duplicate()
	var started = actions.begin_scope_technology_phase(control, "nation", "n1", "house_build", target_id, {"cells": cells, "options": options})
	_check(started.ok, "Original source and named admission avoid a first-phase budget self-lock: " + str(started))
	project = Technology.active_project(nation.technology)
	var feature: Dictionary = data.site.features[target_id.trim_prefix("feature:")]
	_check(project.budget.holder == "nation-order:" + JSON.stringify([str(data.site.id), "n1", str(registered.order_id)]) \
		and project.budget.spent == {"wood": 8, "stone": 4} and project.budget.payments.size() == 1 \
		and int(reserve.holder.version) == source_version + 1 and data.site.inventory == camp,
		"One true physical debit and one original Scope payment/grant are published together")
	_check(Runtime.technology_existing_paid_phase_source(data, feature.tech_trial).ok, "Only the current actual paid target supplies a paid phase source witness")
	var copied = feature.tech_trial.duplicate(true)
	_check(not Runtime.technology_existing_paid_phase_source(data, copied).ok, "A caller copy of a paid token cannot substitute for the SAME original target token")
	# Legal destruction of a consumed source is a historical-owner boundary, not
	# a new manufacture input. The strict original demolition command owns it.
	var demolition = Runtime.cancel_feature(data, str(fixture.warehouse), fixture.controller.reserves_cell, 1)
	_check(demolition.ok, "The original demolition transaction legally removes the now-empty private Warehouse: " + str(demolition))
	_check(Runtime.validate_technology_target_storage(data, target_id.trim_prefix("feature:"), feature).ok \
		and Runtime.technology_existing_paid_phase_source(data, feature.tech_trial).ok,
		"Consumed physical source identity/version stays strict payment history after legal demolition")
	var active = actions.technology_phase_active_guard(feature.tech_trial)
	_check(active.ok, "True paid-source proof plus current project/payment/authority/consent permits this already-paid phase without a live source")
	before = _state_bytes(data, row)
	var resumed = actions.begin_scope_technology_phase(control, "nation", "n1", "house_build", target_id)
	_check(resumed.ok and resumed.resumed and _state_bytes(data, row) == before, "Already-paid resume cannot re-request a destroyed source, re-debit or invent a new attempt")
	_finish_feature(lab, team, executor, target_id.trim_prefix("feature:"), float(feature.work))
	_check(Technology.scope_known(nation.technology, "N06") and nation.technology.projects[0].receipts.size() == 1 \
		and nation.technology.projects[0].budget.payments.size() == 1 \
		and nation.technology_operations.public_orders[str(registered.order_id)].receipts.size() == 1,
		"Actual paid original house completion commits one first N06 phase and one true public receipt, with no second source payment")
	_cleanup_fixture(lab, team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 90000
	var fixture = _nation_fixture(["N01", "N02", "N06", "N11"])
	var data: TerrainData = fixture.data
	var lab: TerrainLab = fixture.lab
	var controller: SiteController = fixture.controller
	var actions: SitePersonActions = fixture.actions
	var orders: SiteEquipmentOrders = fixture.orders
	var control = int(fixture.control)
	var team: TerrainArmy = fixture.team
	var executor = int(fixture.executor)
	var row: Dictionary = fixture.row
	var warehouse = str(fixture.warehouse)
	var smithy = str(fixture.smithy)
	var labor: Dictionary = fixture.labor
	var nation_tech: Dictionary = fixture.nation_tech
	var entrance: Vector2i = fixture.entrance
	var issued = orders.request_public_work_order(control, "n1", "house", str(labor.order_id), [executor], warehouse)
	_check(issued.ok, "Original public owner registers an actual known N06 order: " + str(issued))
	var order_id = str(issued.order_id)
	var reserve = _fund(lab, order_id, {"wood": 8, "stone": 4}, warehouse)
	var selector = {"nation_id": "n1", "order_id": order_id}
	var options = {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	var geometry = _material_setup_geometry(lab, "house", Vector2i(28, 20), Vector2i(2, 2), options)
	_check(geometry.ok, "Original actual house geometry fits the current real jurisdiction")
	var cells: Array[int] = []
	cells.assign(geometry.cells)
	var request = {"cells": cells, "options": options}
	# An abundant unrelated camp must not hide a missing original private source.
	var held_wood = int(reserve.cargo.wood)
	reserve.cargo.wood = 0
	var before = _state_bytes(data, row)
	var bad = Runtime.begin_nation_technology_operation(data, "n1", order_id, false, request)
	_check(not bad.ok and _state_bytes(data, row) == before, "Private source insufficiency cannot debit camp, allocate a feature/zone, bind an order or publish a task")
	reserve.cargo.wood = held_wood
	var actual = actions.nation_operation_material_source_candidate("n1", order_id, "house_build")
	_check(actual.ok and actual.source.size() == 13 and is_same(actual.source.physical_holder, reserve.holder) and is_same(actual.source.physical_cargo, reserve.cargo), "Provider returns exact13 over the true original Warehouse refs")
	var forged: Dictionary = actual.source.duplicate()
	forged.holder_version = int(forged.holder_version) + 1
	before = _state_bytes(data, row)
	_check(not Runtime.request_build(data, "house", cells, Callable(), options, forged, selector).ok and _state_bytes(data, row) == before, "Forged/stale source CAS rejects before every original mutation")
	forged = actual.source.duplicate()
	forged.physical_cargo = reserve.cargo.duplicate(true)
	_check(not Runtime.request_build(data, "house", cells, Callable(), options, forged, selector).ok and _state_bytes(data, row) == before, "A copied cargo with matching amounts is not the original source owner")
	var order: Dictionary = data.site.equipment_nations.n1.technology_operations.public_orders[order_id]
	var consent: Array = order.payload.consents
	order.payload.consents = []
	before = _state_bytes(data, row)
	_check(not Runtime.begin_nation_technology_operation(data, "n1", order_id, false, request).ok and _state_bytes(data, row) == before, "Missing actual team consent cannot consume private stock")
	order.payload.consents = consent
	var prepared = Runtime.prepare_build_request(data, "house", cells, controller.reserves_cell, options, {}, selector)
	_check(prepared.ok, "Complete prospective feature/zone, exact real source, true order and named NPC all preflight: " + str(prepared))
	var entry_cell = data.cell_from_index(int(prepared.feature.entrance))
	_check(lab.character.place(entry_cell, true), "A real original person occupies the one actual construction slot")
	before = _state_bytes(data, row)
	bad = Runtime.begin_nation_technology_operation(data, "n1", order_id, false, request)
	_check(not bad.ok and _state_bytes(data, row) == before, "Occupied/unreachable original named slot rejects before private debit and before feature/zone adoption")
	_check(lab.character.place(entrance, true), "Donor leaves the true reserved construction slot")
	before = _state_bytes(data, row)
	var preview = Runtime.begin_nation_technology_operation(data, "n1", order_id, true, request)
	_check(preview.ok and _state_bytes(data, row) == before, "Full public preview allocates no feature/zone/sequence/task/budget/stock")
	prepared = Runtime.prepare_build_request(data, "house", cells, controller.reserves_cell, options, {}, selector)
	_check(prepared.ok, "Recomputed original candidates remain valid before the no-yield commit")
	var camp = data.site.inventory.duplicate()
	var camp_version = int(data.site.depot_items.version)
	var source_version = int(reserve.holder.version)
	var prior_next = int(data.site.next_feature)
	var same_operations: Dictionary = data.site.equipment_nations.n1.technology_operations
	var same_order: Dictionary = same_operations.public_orders[order_id]
	var built = Runtime.publish_build_request(data, prepared)
	_check(built.ok and is_same(data.site.features[built.feature], prepared.feature) and is_same(data.site.zones[prepared.named.assignment.zone_index], prepared.zone), "Original commit adopts the SAME complete feature and SAME zone used in WT preparation")
	_check(data.site.inventory == camp and int(data.site.depot_items.version) == camp_version and int(reserve.holder.version) == source_version + 1, "Only the actual private holder CAS advances once; camp/tools remain original catalytic ownership")
	_check(int(reserve.cargo.get("wood", 0)) == held_wood - 8 and int(reserve.cargo.get("stone", 0)) == 0 and int(data.site.next_feature) == prior_next + 1, "Exact full house cost is consumed once with one original sequence")
	_check(is_same(data.site.equipment_nations.n1.technology_operations, same_operations) and is_same(same_operations.public_orders[order_id], same_order), "Original Nops publication preserves source authority refs across the same paid tail")
	var feature: Dictionary = data.site.features[built.feature]
	_check(feature.tech_batch.source_holder == reserve.holder.holder and int(feature.tech_batch.source_version) == source_version and feature.tech_batch.token.is_empty(), "Ledger records actual physical source/predebit version; known project0 creates no research token")
	before = _state_bytes(data, row)
	_check(not Runtime.begin_nation_technology_operation(data, "n1", order_id, false, request).ok and _state_bytes(data, row) == before, "Retry cannot double-pay or create a second feature/order binding")
	_check(Runtime.validate_technology_target_storage(data, str(built.feature), feature).ok, "Active paid source and order cross-reference pass strict original target validation")
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(feature))
	decoded.tech_batch.source_holder = actual.source.holder
	_check(not Runtime.validate_technology_target_storage(data, str(built.feature), decoded).ok, "Budget namespace cannot masquerade as a saved physical source holder")
	_finish_feature(lab, team, executor, str(built.feature), float(feature.work))
	_check(feature.stage == "complete" and not feature.has("tech_batch") and not feature.has("technology_order") and row.work_task.is_empty(), "Real named work completes one actual house and stops; no next automatic batch")
	_check(same_order.status == "complete" and same_order.receipts.size() == 1 and same_order.receipts[0].operator_id == executor and same_order.receipts[0].target_id == "feature:" + str(built.feature), "Actual original public owner accepts this true paid named output once")
	_check(data.site.equipment_nations.n1.technology == nation_tech and row.get("technology", {}).is_empty(), "Known ordinary public production adds no research/learning evidence")
	# N11 uses a real bounded order, real actual host and same original source;
	# this initial learned F04 is a truthful prerequisite fixture, not earned here.
	row.technology = Technology.learned_candidate({}, "F04")
	_check(Technology.valid_person(row.technology), "Explicit pre-existing skill lives on the original NPC body")
	orders.nation_arsenal_request = func(nation_id: String, selected_order: String, prospective_order: Dictionary, preview_only: bool) -> Dictionary:
		if preview_only and not data.site.equipment_nations[nation_id].technology_operations.public_orders.has(selected_order):
			return orders._arsenal_workshop_context(prospective_order) # True original planning preview only; no paid/complete claim.
		return Runtime.begin_nation_technology_operation(data, nation_id, selected_order, preview_only)
	var armor_order = orders.request_arsenal_order(control, "n1", "armor", smithy, executor, warehouse)
	_check(armor_order.ok, "Original N11 request previews an actual qualified host before source funding, without a grant self-lock: " + str(armor_order))
	reserve = _fund(lab, str(armor_order.order_id), {"iron": 4, "leather": 2, "charcoal": 2}, warehouse)
	var same_host: Dictionary = data.site.features[smithy]
	var next_item = int(data.site.next_item)
	camp = data.site.inventory.duplicate()
	var started = Runtime.begin_nation_technology_operation(data, "n1", str(armor_order.order_id), false)
	_check(started.ok and is_same(data.site.features[smithy], same_host) and same_host.recipe_id == "iron_armor" and same_host.batch_paid and same_host.tech_batch.token.is_empty(), "True known N11 source/recipe/host/zone/order/named task start in one original paid commit: " + str(started))
	_check(data.site.inventory == camp and int(reserve.cargo.get("iron", 0)) == 0 and int(reserve.cargo.get("leather", 0)) == 0 and int(reserve.cargo.get("charcoal", 0)) == 0, "Iron armor consumes its exact original private recipe once")
	_finish_feature(lab, team, executor, smithy, float(Runtime.feature_recipe(same_host).cycle))
	var latest: Dictionary = same_host.technology_output.receipts[0]
	_check(int(data.site.next_item) == next_item + 1 and latest.item_ids == [str(next_item)] and data.site.item_records[str(next_item)].definition == "armor:armor_iron_01", "Actual original ItemSeq produces exactly one real iron armor item")
	_check(row.item_state.item_ids.has(str(next_item)) and row.work_task.is_empty() and not same_host.batch_paid and not same_host.has("technology_order"), "Original worker holds the original item and named production stops after one batch")
	_check(data.site.equipment_nations.n1.technology_operations.public_orders[str(armor_order.order_id)].receipts.size() == 1 and not Technology.learned(row.technology, "F06"), "Ordinary public armor yields one actual production receipt without teaching armor research")
	_cleanup_fixture(lab, team)
	await process_frame
	await _research_private_source()
	TerrainArmy.release_contact_source()
	print("TECHNOLOGY_NATION_SOURCE_BUILD_OUTPUT_FIXTURE_PASS: checks=", checks, "; actual first N06 + known N06/N11 armor source, same prospective feature/zone/task transaction and consumed source history; natural source / strict Settlementv2 / no clock/travel/UI/full40 PASS")
	quit(0)

# Immutable fixture-only natural source helpers; original production above is unchanged.
func _material_natural_data() -> TerrainData:
	var data = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345)
	Env.initialize(data, "nation-material-natural")
	# Bound/loaded/visited Sites carry item storage; Core building payment reads its depot.
	var fixture_item_storage = Runtime.initialize_item_storage(data.site)
	assert(fixture_item_storage.ok, "Fixture natural world carries original item storage")
	return data # No generated terrain or land-condition field is overwritten.

func _material_natural_lab(data: TerrainData) -> TerrainLab:
	var lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.site_controller._auto_save_blocked = true
	lab.bind_terrain(data)
	lab.character.faction_id = 1
	lab.npc.faction_id = 1
	var camp = data.cell_from_index(int(data.site.depot_cell))
	_check(lab.character.place(camp, true), "Actual Actor reaches the original generated camp")
	var npc_cell = Vector2i(-1, -1)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var cell = camp + direction
		if data.contains(cell) and data.is_walkable(cell) and data.can_step(camp, cell):
			npc_cell = cell
			break
	_check(npc_cell.x >= 0 and lab.npc.place(npc_cell, true), "The second original Actor has a distinct legal camp contact")
	lab.site_controller.release_worker()
	return lab

func _material_setup_geometry(lab: TerrainLab, kind: String, near: Vector2i, extent: Vector2i, options: Dictionary = {}, excluded: Array = []) -> Dictionary:
	var data = lab.terrain
	var settings = {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	settings.merge(options, true)
	for radius: int in range(9):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if absi(x) + absi(y) != radius: continue
				var anchor = near + Vector2i(x, y)
				var geometry = Runtime.building_cells(data, kind, anchor, extent, settings)
				if not geometry.ok: continue
				if geometry.cells.any(func(index: int) -> bool: return excluded.has(index)): continue
				var preview = Runtime.preview_build(data, kind, geometry.cells, lab.site_controller.reserves_cell, settings)
				if not preview.ok: continue
				geometry["fixture_anchor"] = anchor
				geometry["fixture_options"] = settings
				geometry["fixture_preview"] = preview
				return geometry
	_check(false, "Original finite setup scan must find a legal " + kind + " near " + str(near))
	return {}

func _material_setup_feature(lab: TerrainLab, kind: String, near: Vector2i, extent: Vector2i = Vector2i.ONE, options: Dictionary = {}, excluded: Array = []) -> String:
	var geometry = _material_setup_geometry(lab, kind, near, extent, options, excluded)
	# Explicit prior-world infrastructure: sparse resource clearing is through
	# its original Env owner, never an unrecorded terrain/soil array mutation.
	for key: String in geometry.fixture_preview.get("clearing", []): Env.change(lab.terrain, key, {"cleared": true, "remaining": 0})
	return _formal_feature(lab.terrain, kind, geometry.fixture_anchor, extent, options)

func _material_army(lab: TerrainLab, count: int) -> TerrainArmy:
	var team = TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = 402 if count == 40 else 301
	team.roster_size = count
	team.faction_id = 1
	team.person_id_allocator = Callable(lab, "_allocate_army_person_ids")
	var cells: Array[Vector2i] = []
	for index: int in range(count):
		var near = Vector2i(10 + index % 20, 48 + floori(float(index) / 20.0)) if count == 40 else Vector2i(11 + index, 11)
		var chosen = Vector2i(-1, -1)
		for radius: int in range(5):
			for y: int in range(-radius, radius + 1):
				for x: int in range(-radius, radius + 1):
					if absi(x) + absi(y) != radius: continue
					var candidate = near + Vector2i(x, y)
					if lab.terrain.contains(candidate) and lab.terrain.is_walkable(candidate) and not cells.has(candidate) and candidate not in [lab.character.terrain_cell, lab.npc.terrain_cell]:
						chosen = candidate
						break
				if chosen.x >= 0: break
			if chosen.x >= 0: break
		_check(chosen.x >= 0, "Original generated terrain has one distinct legal deployment cell for each initial original NPC")
		cells.append(chosen)
	_check(team.deploy_at(lab.terrain, lab.character, lab.npc, cells) and team.enable_combat(false), "Original finite Army plus actual Lab person allocator creates the real pre-existing NPC rows")
	for row: Dictionary in team.combat_units:
		row.cargo = {}
		row.item_state = Runtime.new_item_state("person:" + str(row.person_id))
	lab.combat_armies.append(team)
	team.controlled_person_query = lab.controlled_person_id
	team.person_busy_query = lab.site_controller.person_actions.is_busy
	team.settle_combat_command()
	_check(team.set_duty_ai_enabled(team.combat_identity(team.formal_commander), true).ok, "The true living original captain explicitly admits reactive duty AI")
	return team

