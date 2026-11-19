extends "res://scripts/tests/site_building_ui_test.gd"
## Original nation/schema and real original procurement transfer. This does not
## claim N04/N05 positive production until the Runtime receipt owner is merged.
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const Tech = preload("res://scripts/terrain_lab/site_technology.gd")
const Stockpiles = preload("res://scripts/terrain_lab/site_stockpiles.gd")

func _run() -> void:
	deadline = Time.get_ticks_msec() + 90000
	_check_schema_and_invalid()
	_check_retained_history_schema()
	_check_original_procurement()
	print("NATION_TECHNOLOGY_SCHEMA_N01_TRANSFER_PASS: strict old/optional/JSON state; current original offices; true definitions/substitutes; original supplier/warehouse/version/capacity/cumulative quotas/replay; N04/N05 positive production and whole research/UI excluded")
	quit(0)

func _definitions() -> Dictionary:
	return {"weapon:bow_01": {"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]},
		"weapon:crossbow_01": {"slot": "weapon", "asset": "crossbow_01", "tint": [1.0, 1.0, 1.0, 1.0]}}

func _schema_nation() -> Dictionary:
	var technology := Tech.empty_scope_record("nation_test_site")
	technology.known = ["N01", "N04", "N05"]
	var operations := Orders.empty_nation_operations()
	operations.specs["procure"] = {"revision": 1, "authorizer_id": 1, "name": "真批量採購", "destination_feature_id": "warehouse_1",
		"resources": {"wood": {"batch": 2, "total": 2}}, "items": {"weapon": {"definition": "weapon:bow_01", "alternatives": ["weapon:crossbow_01"], "batch": 1, "total": 2}},
		"receipts": [{"id": "delivery_1", "source_person_id": 1, "resources": {"wood": 2}, "items": {"7": "weapon:crossbow_01"}}]}
	operations.certificates["cert"] = {"revision": 1, "authorizer_id": 1, "settlement_id": "settlement_1", "feature_id": "smithy_1",
		"industry_id": "S07", "operator_id": 2, "receipt_id": 1, "status": "active", "reason": ""}
	operations.next_seq = 2
	operations.orders["production_1"] = {"revision": 1, "authorizer_id": 1, "certificate_id": "cert", "certificate_revision": 1,
		"feature_id": "smithy_1", "operator_id": 2, "recipient_id": 3, "standard_id": "bow_line", "standard_revision": 1, "recipe_id": "bow", "max_batches": 1,
		"status": "complete", "source": {"site_id": "nation_test_site", "person_id": 1, "holder": "person:1", "status": "granted", "cap": {"wood": 4, "fiber": 2}, "spent": {"wood": 4, "fiber": 2}},
		"receipt_ids": [2], "issued_item_ids": [], "reason": "", "work_consent": {}}
	return {"military_head": 1, "members": [1, 2, 3], "standards": {"bow_line": {"name": "原弓標準", "revision": 1, "slots": {"weapon": {"definition": "weapon:bow_01", "alternatives": []}}}},
		"technology": technology, "technology_operations": operations}

func _check_schema_and_invalid() -> void:
	var definitions := _definitions()
	var people := {1: true, 2: true, 3: true}
	var old := {"military_head": 1, "members": [1, 2, 3], "standards": {}}
	assert(Orders.valid_nations({"n1": old}, definitions, people))
	var state := {"equipment_nations": {"n1": old.duplicate(true)}, "item_definitions": definitions}
	var before := JSON.stringify(state)
	assert(Orders.normalize_nation_operations(state).ok and JSON.stringify(state) == before, "Old record does not gain technology or orders")
	var nation := _schema_nation()
	assert(Orders.valid_nations({"n1": nation}, definitions, people), "Pure shape fixture; procurement=%s certificate=%s military_source=%s military_order=%s" % [
		Orders._valid_procurement_spec(nation.technology_operations.specs.procure, definitions, people),
		Orders._valid_workshop_certificate(nation.technology_operations.certificates.cert, people),
		Orders._valid_military_source(nation.technology_operations.orders.production_1.source, people),
		Orders._valid_military_order(nation.technology_operations.orders.production_1, nation.technology_operations.certificates, people)])
	var json: Dictionary = JSON.parse_string(JSON.stringify({"equipment_nations": {"n1": nation}, "item_definitions": definitions}))
	assert(Orders.valid_nations(json.equipment_nations, definitions, people))
	assert(Orders.normalize_nation_operations(json).ok and json.equipment_nations.n1.technology_operations.orders.production_1.source.person_id is int)

	var invalid := nation.duplicate(true)
	invalid.technology = {}
	assert(not Orders.valid_nations({"n1": invalid}, definitions, people), "Present invalid technology cannot become legacy")
	invalid = nation.duplicate(true)
	invalid.erase("technology")
	assert(not Orders.valid_nations({"n1": invalid}, definitions, people), "Operations cannot hide under a legacy nation")
	invalid = nation.duplicate(true)
	invalid.technology.known = ["F07"]
	assert(not Orders.valid_nations({"n1": invalid}, definitions, people))
	invalid = nation.duplicate(true)
	invalid.technology_operations.version = 99
	assert(not Orders.valid_nations({"n1": invalid}, definitions, people))
	invalid = nation.duplicate(true)
	invalid.technology_operations.parallel_stock = {"wood": 100}
	assert(not Orders.valid_nations({"n1": invalid}, definitions, people))
	invalid = nation.duplicate(true)
	invalid.technology_operations.specs.procure.items.weapon.alternatives = ["weapon:fictional"]
	assert(not Orders.valid_nations({"n1": invalid}, definitions, people))
	invalid = nation.duplicate(true)
	invalid.technology_operations.specs.procure.resources.wood.batch = -1
	assert(not Orders.valid_nations({"n1": invalid}, definitions, people))
	invalid = nation.duplicate(true)
	invalid.technology_operations.specs.procure.receipts.append(invalid.technology_operations.specs.procure.receipts[0].duplicate(true))
	assert(not Orders.valid_nations({"n1": invalid}, definitions, people), "Receipt replay cannot increase accepted counts")
	invalid = nation.duplicate(true)
	invalid.technology_operations.orders.production_1.source.spent.wood = 5
	assert(not Orders.valid_nations({"n1": invalid}, definitions, people), "Actual source spending cannot exceed cap")
	invalid = nation.duplicate(true)
	invalid.technology_operations.orders.production_1.source.holder = "depot"
	assert(not Orders.valid_nations({"n1": invalid}, definitions, people), "A controlled personal grant is not a national depot")
	invalid = nation.duplicate(true)
	invalid.technology_operations.orders.production_1.receipt_ids = [2, 2]
	assert(not Orders.valid_nations({"n1": invalid}, definitions, people))
	invalid = nation.duplicate(true)
	invalid.technology_operations.next_seq = 3
	invalid.technology_operations.orders.production_2 = invalid.technology_operations.orders.production_1.duplicate(true)
	assert(not Orders.valid_nations({"n1": invalid}, definitions, people), "One original output cannot complete two orders")
	invalid = nation.duplicate(true)
	invalid.technology_operations.orders.production_1.status = "issued"
	assert(not Orders.valid_nations({"n1": invalid}, definitions, people), "Issued state needs the original item receipt")
	var bad_state := {"equipment_nations": {"n1": invalid}, "item_definitions": definitions}
	before = JSON.stringify(bad_state)
	assert(not Orders.normalize_nation_operations(bad_state).ok and JSON.stringify(bad_state) == before, "Invalid present state stays unchanged")
	var data := TerrainData.new()
	var missing_refs := {"id": "nation_test_site", "equipment_nations": {"n1": nation}, "item_definitions": definitions, "features": {}, "stockpiles": {}}
	assert(not Orders.validate_nation_operations(data, missing_refs, people).ok, "Shape-valid paper receipts do not prove true original feature output")
	var wrong_holder := old.duplicate(true)
	wrong_holder.technology = Tech.empty_scope_record("other_site")
	var wrong_scope := {"id": "nation_test_site", "equipment_nations": {"n1": wrong_holder}, "item_definitions": definitions, "features": {}, "stockpiles": {}}
	assert(Orders.valid_nations(wrong_scope.equipment_nations, definitions, people))
	assert(not Orders.validate_nation_operations(data, wrong_scope, people).ok, "Even technology without operations must belong to this original Site")
	var malformed_receipt := missing_refs.duplicate(true)
	malformed_receipt.stockpiles.warehouse_1 = {}
	malformed_receipt.features.warehouse_1 = {"kind": "warehouse"}
	malformed_receipt.features.smithy_1 = {"kind": "smithy", "technology_output": {"version": 1, "next_seq": 2, "receipts": [1]}}
	assert(not Orders.validate_nation_operations(data, malformed_receipt, people).ok, "Malformed original receipt types reject before typed field access")

func _make_item(data: TerrainData, holder: Dictionary, asset: String, original_owner: int) -> String:
	var made := Runtime.create_equipment(data, holder, "weapon:" + asset, {"slot": "weapon", "asset": asset, "tint": [1.0, 1.0, 1.0, 1.0]}, original_owner)
	assert(made.ok, str(made))
	return str(made.item_id)

## Retained bodies are schema fixtures; acceptance is only the original Runtime
## output/certification transaction. This tests legal later producer removal.
func _check_retained_history_schema() -> void:
	var nation := _schema_nation()
	var operations: Dictionary = nation.technology_operations
	operations.version = Orders.NATION_PUBLIC_VERSION
	operations.public_orders = {}
	operations.certificates.cert.accepted_receipt = {"id": 1, "site_id": "nation_test_site", "feature_id": "smithy_1", "operator_id": 2,
		"recipe_id": "bow", "resources": {}, "item_ids": ["6"], "work_seconds": 108.0}
	operations.orders.production_1.accepted_receipts = [{"id": 2, "site_id": "nation_test_site", "feature_id": "smithy_1", "operator_id": 2,
		"recipe_id": "bow", "resources": {}, "item_ids": ["7"], "work_seconds": 108.0}]
	var people := {1: true, 2: true, 3: true}
	assert(Orders.valid_nation_operation_record(operations, _definitions(), people))
	var state := {"id": "nation_test_site", "equipment_nations": {"n1": nation}, "item_definitions": _definitions(),
		"features": {"warehouse_1": {"kind": "warehouse"}}, "stockpiles": {"warehouse_1": {}}, "item_records": {}}
	assert(Orders.validate_nation_operations(TerrainData.new(), state, people).ok, "Accepted certificate/order histories survive legal host and consumed product removal")
	var invalid := operations.duplicate(true)
	invalid.certificates.cert.erase("accepted_receipt")
	assert(not Orders.valid_nation_operation_record(invalid, _definitions(), people), "Malformed v2 cannot fall back to legacy certificate lookup")
	invalid = operations.duplicate(true)
	invalid.orders.production_1.accepted_receipts = []
	assert(not Orders.valid_nation_operation_record(invalid, _definitions(), people))
	invalid = operations.duplicate(true)
	invalid.orders.production_1.accepted_receipts[0].operator_id = 3
	assert(not Orders.valid_nation_operation_record(invalid, _definitions(), people))
	invalid = operations.duplicate(true)
	invalid.orders.production_1.accepted_receipts.append(invalid.orders.production_1.accepted_receipts[0].duplicate(true))
	assert(not Orders.valid_nation_operation_record(invalid, _definitions(), people), "One finite production order cannot grow an unbounded product ledger")

func _check_original_procurement() -> void:
	assert(SiteOffices.duty_ids("nation").has("nation.procurement"), "Region must wire the actual new duty first")
	var data := _building_fixture()
	var warehouse := _formal_feature(data, "warehouse", Vector2i(13, 13))
	var lab := _building_lab(data)
	var actor_id := int(lab.controlled_person_id())
	var npc_id := int(lab.npc.person_id)
	var actions: SitePersonActions = lab.site_controller.person_actions
	var orders: SiteEquipmentOrders = lab.site_controller.equipment_orders
	var technology := Tech.empty_scope_record(str(data.site.id))
	technology.known = ["N01"] # Fixture authoring; whole earned-research proof is a separate test.
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", actor_id), "members": [actor_id, npc_id], "standards": {}, "technology": technology}}
	assert(Stockpiles.ensure_storage(data, warehouse, 1).ok)
	var person := actions._person(actor_id)
	var source_cargo: Dictionary = person.cargo
	source_cargo.wood = 2
	source_cargo.grain = 2
	var bow := _make_item(data, person.holder, "bow_01", actor_id)
	var crossbow := _make_item(data, person.holder, "crossbow_01", actor_id)
	var limits := {"wood": {"batch": 2, "total": 2}, "grain": {"batch": 2, "total": 2}}
	var requirements := {"weapon": {"definition": "weapon:bow_01", "alternatives": ["weapon:crossbow_01"], "batch": 1, "total": 2}}
	var snapshot := JSON.stringify(data.site.equipment_nations)
	assert(not orders.publish_procurement_spec(npc_id, "n1", "batch", "未獲原職責", warehouse, limits, requirements).ok)
	assert(JSON.stringify(data.site.equipment_nations) == snapshot)
	assert(orders.appoint_nation_head("n1", npc_id).ok, "Original scenario appointment prepares a real NPC duty holder")
	assert(orders._nation_duty_ok(npc_id, data.site.equipment_nations.n1, "nation.procurement"))
	snapshot = JSON.stringify(data.site.equipment_nations)
	assert(not orders.publish_procurement_spec(npc_id, "n1", "batch", "不可冒用NPC授權", warehouse, limits, requirements).ok)
	assert(JSON.stringify(data.site.equipment_nations) == snapshot, "A true NPC office still cannot be impersonated by a manual command")
	assert(orders.appoint_nation_head("n1", actor_id).ok)
	assert(orders.publish_procurement_spec(actor_id, "n1", "batch", "原公開採購", warehouse, limits, requirements).ok)
	limits.wood.total = 999
	assert(data.site.equipment_nations.n1.technology_operations.specs.batch.resources.wood.total == 2)
	assert(data.site.equipment_nations.n1.standards.is_empty())
	assert(lab.character.place(data.cell_from_index(int(data.site.features[warehouse].entrance)), true))
	var destination: Dictionary = Stockpiles.storage(data, warehouse)
	var destination_cargo: Dictionary = destination.cargo
	var source_version := int(person.holder.version)
	var destination_version := int(destination.holder.version)
	snapshot = JSON.stringify([source_cargo, person.holder, destination, data.site.equipment_nations])
	assert(not orders.accept_procurement_delivery(npc_id, "n1", "batch", {"wood": 2, "grain": 2}, [crossbow], source_version, destination_version, "wrong_person").ok)
	assert(JSON.stringify([source_cargo, person.holder, destination, data.site.equipment_nations]) == snapshot)
	assert(not orders.accept_procurement_delivery(actor_id, "n1", "batch", {"wood": 2, "grain": 2}, [crossbow], source_version + 1, destination_version, "stale_source").ok)
	assert(JSON.stringify([source_cargo, person.holder, destination, data.site.equipment_nations]) == snapshot)
	assert(not orders.accept_procurement_delivery(actor_id, "n1", "batch", {"wood": 2, "grain": 2}, [crossbow], source_version, destination_version + 1, "stale_destination").ok)
	assert(JSON.stringify([source_cargo, person.holder, destination, data.site.equipment_nations]) == snapshot)
	assert(orders.accept_procurement_delivery(actor_id, "n1", "batch", {"wood": 2, "grain": 2}, [crossbow], source_version, destination_version, "delivery_1").ok)
	assert(is_same(source_cargo, actions._person(actor_id).cargo) and is_same(destination_cargo, Stockpiles.storage(data, warehouse).cargo))
	assert(int(source_cargo.get("wood", 0)) == 0 and int(source_cargo.get("grain", 0)) == 0)
	assert(destination_cargo.wood == 2 and destination_cargo.grain == 2 and destination.holder.item_ids.has(crossbow))
	assert(data.site.item_records[crossbow].holder == "feature:" + warehouse)
	snapshot = JSON.stringify([source_cargo, person.holder, destination, data.site.equipment_nations])
	assert(orders.accept_procurement_delivery(actor_id, "n1", "batch", {"wood": 2, "grain": 2}, [crossbow], source_version, destination_version, "delivery_1").code == "NO_CHANGE")
	assert(JSON.stringify([source_cargo, person.holder, destination, data.site.equipment_nations]) == snapshot)
	source_cargo.wood = 1
	snapshot = JSON.stringify([source_cargo, person.holder, destination, data.site.equipment_nations])
	assert(not orders.accept_procurement_delivery(actor_id, "n1", "batch", {"wood": 1}, [], int(person.holder.version), int(destination.holder.version), "over_cap").ok)
	assert(JSON.stringify([source_cargo, person.holder, destination, data.site.equipment_nations]) == snapshot)
	destination_cargo.clay = Stockpiles.capacity(data.site.features[warehouse]) - int(Runtime.carried_load(data.site, destination_cargo, destination.holder))
	snapshot = JSON.stringify([source_cargo, person.holder, destination, data.site.equipment_nations])
	assert(orders.accept_procurement_delivery(actor_id, "n1", "batch", {}, [bow], int(person.holder.version), int(destination.holder.version), "full_destination").code == "STORAGE_FULL")
	assert(JSON.stringify([source_cargo, person.holder, destination, data.site.equipment_nations]) == snapshot)
	destination_cargo.erase("clay")
	assert(orders.accept_procurement_delivery(actor_id, "n1", "batch", {}, [bow], int(person.holder.version), int(destination.holder.version), "delivery_2").ok)
	assert(destination.holder.item_ids.has(bow) and data.site.item_records[bow].holder == "feature:" + warehouse)
	assert(data.site.equipment_nations.n1.technology_operations.specs.batch.receipts.size() == 2)
	lab.free()
