extends "res://scripts/tests/site_building_ui_test.gd"
## Shape fixtures below are only schema evidence. Positive physical evidence
## uses the real original VehicleTransport and original Controller control path.
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const Tech = preload("res://scripts/terrain_lab/site_technology.gd")
const Stockpiles = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")

func _run() -> void:
	deadline = Time.get_ticks_msec() + 90000
	_check_public_schema()
	_check_nation_namespace()
	_check_original_grain_transfers()
	print("NATION_PUBLIC_SCHEMA_GRAIN_TRANSFER_PASS: all nine strict public operation schemas; JSON/no-normalization-on-rejection; current original offices/control/source limits; N03 two true original recipients; N09 true collect and spend; unsupported owner seams do not claim completed research/build/course/route/arsenal/fleet")
	quit(0)

func _source(cap: Dictionary, spent: Dictionary = {}) -> Dictionary:
	return {"site_id": "public_test", "person_id": 1, "holder": "person:1", "status": "granted", "cap": cap, "spent": spent}

func _public_order(tech_id: String, payload: Dictionary) -> Dictionary:
	return {"tech_id": tech_id, "project_id": 0, "revision": 1, "authorizer_id": 1, "status": "prepared", "scope_site_id": "public_test", "scope_nation_id": "n1", "payload": payload, "receipts": [], "reason": ""}

func _public_operations() -> Dictionary:
	var ops := Orders.empty_nation_operations()
	ops.version = Orders.NATION_PUBLIC_VERSION
	ops.next_seq = 10
	ops.public_orders = {
		"public_1": _public_order("N02", {"settlement_id": "原聚落", "person_ids": [2], "consents": [], "feature_id": ""}),
		"public_2": _public_order("N03", {"reserve_feature_id": "reserve", "source": _source({"grain": 4}), "recipient_ids": [2, 3]}),
		"public_3": _public_order("N06", {"settlement_id": "原聚落", "blueprint_id": "house", "labor_order_id": "public_1", "worker_ids": [2], "consents": [], "reserve_feature_id": "reserve", "source": _source({"wood": 8, "stone": 4}), "feature_id": ""}),
		"public_4": _public_order("N07", {"reserve_feature_id": "reserve", "source": _source({"grain": 4}), "teacher_id": 1, "student_ids": [2, 3], "skill_id": "F07"}),
		"public_5": _public_order("N08", {"reserve_feature_id": "reserve", "source": _source({"grain": 4}), "route_id": "route", "destination_site_id": "destination", "destination_holder": "feature:warehouse", "vehicle_id": "1", "driver_id": 2,
			"route_ref": {"world_instance_id": "world", "slot_id": "slot", "source_site_id": "public_test", "destination_site_id": "destination", "route_id": "route"}, "travel_token": "", "loaded": false}),
		"public_6": _public_order("N09", {"reserve_feature_id": "reserve", "source": _source({"grain": 1}), "recipient_id": 3}),
		"public_7": _public_order("N10", {"settlement_id": "原聚落", "local_person_id": 2, "office_revision": 1, "expires_game_seconds": 1000.0, "clock_ref": {"world_instance_id": "world", "slot_id": "slot"}, "feature_id": "", "consents": []}),
		"public_8": _public_order("N11", {"settlement_id": "原聚落", "route": "armor", "host_id": "smithy", "operator_id": 2, "consents": [], "reserve_feature_id": "reserve", "source": _source({"iron": 4, "leather": 2, "charcoal": 2}), "target_id": ""}),
		"public_9": _public_order("N12", {"corps_id": "first", "ship_ids": ["1", "2"], "steps": {}})
	}
	return ops

func _receipt(event_id: String, binding: String, operator_id: int, target: String) -> Dictionary:
	return {"id": event_id, "site_id": "public_test", "binding": binding, "operator_id": operator_id, "target_id": target, "work_seconds": Orders._public_receipt_seconds(binding), "item_ids": []}

func _check_public_schema() -> void:
	var people := {1: true, 2: true, 3: true}
	var ops := _public_operations()
	assert(Orders.valid_nation_operation_record(ops, {}, people), "Only legal shape, no fake successful owner operation")
	var json: Dictionary = JSON.parse_string(JSON.stringify(ops))
	assert(Orders.valid_nation_operation_record(json, {}, people), "JSON integer values remain legal")
	var state := {"equipment_nations": {"n1": {"technology_operations": json}}}
	assert(Orders.normalize_nation_operations(state).ok)
	assert(state.equipment_nations.n1.technology_operations.public_orders.public_4.payload.student_ids[0] is int)
	for order_id: String in ops.public_orders:
		var bad := ops.duplicate(true)
		bad.public_orders[order_id].payload.parallel_owner = {}
		assert(not Orders.valid_nation_operation_record(bad, {}, people), "Every operation payload uses exact keys")
		bad = ops.duplicate(true)
		bad.public_orders[order_id].project_id = true
		assert(not Orders.valid_nation_operation_record(bad, {}, people), "Bool is not an original project ID")
	var bad := ops.duplicate(true)
	bad.public_orders.public_2.payload.recipient_ids = [2, 2]
	assert(not Orders.valid_nation_operation_record(bad, {}, people))
	bad = ops.duplicate(true)
	bad.public_orders.public_4.payload.student_ids = [2, 3, 1]
	assert(not Orders.valid_nation_operation_record(bad, {}, people), "Finite two-seat course")
	bad = ops.duplicate(true)
	bad.public_orders.public_4.payload.student_ids = [1]
	assert(not Orders.valid_nation_operation_record(bad, {}, people), "Teacher cannot be own student")
	bad = ops.duplicate(true)
	bad.public_orders.public_3.payload.labor_order_id = "missing"
	assert(not Orders.valid_nation_operation_record(bad, {}, people))
	bad = ops.duplicate(true)
	bad.public_orders.public_5.payload.route_ref.destination_site_id = "public_test"
	assert(not Orders.valid_nation_operation_record(bad, {}, people), "Local transfer is not a cross-Site route")
	bad = ops.duplicate(true)
	bad.public_orders.public_7.payload.expires_game_seconds = NAN
	assert(not Orders.valid_nation_operation_record(bad, {}, people))
	bad = ops.duplicate(true)
	bad.public_orders.public_9.payload.ship_ids = ["1", "1"]
	assert(not Orders.valid_nation_operation_record(bad, {}, people), "Two original ships, not one duplicated ID")
	bad = ops.duplicate(true)
	bad.public_orders.public_2.payload.source.cap.grain = 5
	assert(not Orders.valid_nation_operation_record(bad, {}, people), "No unlimited public treasury")
	bad = ops.duplicate(true)
	bad.public_orders.public_2.status = "complete"
	bad.public_orders.public_2.receipts = [_receipt(Orders._public_event_id(bad.public_orders.public_2, "public_2", "share", "person:2"), "aid_order", 2, "person:2"), _receipt(Orders._public_event_id(bad.public_orders.public_2, "public_2", "share", "person:3"), "aid_order", 3, "person:3")]
	assert(not Orders.valid_nation_operation_record(bad, {}, people), "Paper share before true source payment rejects")
	bad.public_orders.public_2.payload.source.spent["grain"] = 4
	var strict_history := bad.duplicate(true)
	assert(Orders.valid_nation_operation_record(strict_history, {}, people), "Strict paid N03 history: source=%s, order=%s" % [Orders._valid_public_source(strict_history.public_orders.public_2.payload.source, {"grain": 4}, people), Orders._valid_public_order(strict_history.public_orders.public_2, people, strict_history.public_orders, "public_2")])
	strict_history.public_orders.public_2.receipts[0].erase("site_id")
	assert(not Orders.valid_nation_operation_record(strict_history, {}, people), "New v2 cannot fall back to old five-field public evidence")
	strict_history = bad.duplicate(true)
	strict_history.public_orders.public_2.receipts[0].work_seconds = NAN
	assert(not Orders.valid_nation_operation_record(strict_history, {}, people))
	assert(Orders.valid_nation_operation_record(bad, {}, people), "Pure historical shape only; not runtime proof")
	bad.public_orders.public_2.receipts[1].operator_id = 2
	assert(not Orders.valid_nation_operation_record(bad, {}, people), "Receipt cannot be reassigned to another recipient")
	bad = ops.duplicate(true)
	bad.public_orders.public_1.receipts = [_receipt("register", "labor_register", 1, Orders._public_order_target(bad.public_orders.public_1, "public_1")), _receipt("road", "road_build", 3, "feature:road")]
	assert(not Orders.valid_nation_operation_record(bad, {}, people), "Unbound road/worker receipt rejects")
	bad = ops.duplicate(true)
	bad.public_orders.public_6.payload.source.spent["grain"] = 1
	bad.public_orders.public_6.receipts = [_receipt(Orders._public_event_id(bad.public_orders.public_6, "public_6", "tax_collect", "reserve"), "tax", 2, "feature:reserve")]
	assert(not Orders.valid_nation_operation_record(bad, {}, people), "True consenting source identity is mandatory")
	bad = ops.duplicate(true)
	bad.public_orders.public_7.status = "revoked"
	bad.public_orders.public_7.reason = "原人明示撤銷"
	assert(Orders.valid_nation_operation_record(bad, {}, people), "Expired/revoked history remains saveable without granting live authority")
	bad.public_orders.public_7.payload.local_person_id = "wrong"
	state.equipment_nations.n1.technology_operations = bad
	var before := JSON.stringify(state)
	assert(not Orders.normalize_nation_operations(state).ok and JSON.stringify(state) == before, "Malformed input cannot mutate any previous operation")

func _version(stock: Dictionary) -> int:
	return int(stock.holder.version)

func _check_nation_namespace() -> void:
	var first := _public_operations()
	var second := _public_operations()
	var state := {"id": "public_test", "item_definitions": {}, "equipment_nations": {"n1": {"technology_operations": first}, "n2": {"technology_operations": second}}}
	assert(not Orders._site_operation_claims_valid(state), "Pasted public_1 must retain its real original nation key")
	for order: Dictionary in second.public_orders.values(): order.scope_nation_id = "n2"
	assert(Orders._site_operation_claims_valid(state), "Independent national local counters are valid")
	var consent := {"site_id": "public_test", "team_id": 1, "person_id": 2, "purpose": Orders._public_purpose(first.public_orders.public_1, "public_1"), "decider_id": 1, "revision": 1, "status": "accepted"}
	first.public_orders.public_1.payload.consents = [consent]
	second.public_orders.public_1.payload.consents = [consent.duplicate(true)]
	assert(not Orders.valid_nation_operation_record(second, {}, {1: true, 2: true, 3: true}), "Two nations cannot borrow one true team.work request")
	second.public_orders.public_1.payload.consents[0].purpose = Orders._public_purpose(second.public_orders.public_1, "public_1")
	assert(Orders._site_operation_claims_valid(state), "Distinct explicitly accepted original purposes coexist")
	for order: Dictionary in [first.public_orders.public_3, second.public_orders.public_3]:
		order.payload.feature_id = "42"
		order.payload.source.spent = {"wood": 8, "stone": 4}
		order.receipts = [_receipt("true_original_house_event", "house_build", 2, "feature:42")]
		order.status = "complete"
	assert(not Orders._site_operation_claims_valid(state), "One true original paid building receipt cannot fulfil two nations")
	var before := JSON.stringify(state)
	second.public_orders.public_3.scope_nation_id = "wrong"
	assert(not Orders._site_operation_claims_valid(state))
	second.public_orders.public_3.scope_nation_id = "n2"
	assert(JSON.stringify(state) == before, "Pure claim checks preserve all original packets")

func _check_original_grain_transfers() -> void:
	assert(SiteOffices.duty_ids("nation").has("nation.relief") and SiteOffices.duty_ids("nation").has("nation.finance"), "Region must install actual original duties")
	var data := _building_fixture()
	var warehouse := _formal_feature(data, "warehouse", Vector2i(13, 13))
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var orders: SiteEquipmentOrders = controller.equipment_orders
	var actor_id := int(lab.character.person_id)
	var npc_id := int(lab.npc.person_id)
	var placement := Runtime.building_cells(data, "settlement_center", Vector2i(18, 10), Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	assert(placement.ok)
	var center_cells: Array[int] = []
	center_cells.assign(placement.cells)
	var founded := Settlement.found(lab, actor_id, center_cells)
	assert(founded.ok, str(founded))
	_complete_key(data, str(founded.feature))
	var settlement_tech := Tech.empty_scope_record(str(data.site.id))
	settlement_tech.known = ["S01", "S06"]
	data.site.settlement.technology = settlement_tech # Fixture initial known technology, not earned-research proof.
	var nation_tech := Tech.empty_scope_record(str(data.site.id))
	nation_tech.known = ["N01", "N02", "N03", "N09"]
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", actor_id), "members": [actor_id, npc_id], "standards": {}, "technology": nation_tech}}
	assert(Stockpiles.ensure_storage(data, warehouse, 1).ok)
	var reserve := Stockpiles.storage(data, warehouse)
	var entrance: Vector2i = data.cell_from_index(int(data.site.features[warehouse].entrance))
	assert(lab.character.place(entrance, true))
	var actor := actions._person(actor_id)
	actor.cargo.grain = 5
	var issued := orders.request_aid_order(actor_id, "n1", warehouse, [actor_id, npc_id])
	assert(issued.ok, str(issued))
	var aid := str(issued.order_id)
	var before := JSON.stringify([data.site.equipment_nations, actor.cargo, reserve])
	assert(not orders.authorize_public_source(npc_id, "n1", aid, {"grain": 4}).ok)
	assert(JSON.stringify([data.site.equipment_nations, actor.cargo, reserve]) == before)
	assert(orders.authorize_public_source(actor_id, "n1", aid, {"grain": 4}).ok)
	before = JSON.stringify([data.site.equipment_nations, actor.cargo, reserve])
	assert(not orders.fund_public_order(actor_id, "n1", aid, {"grain": 4}, _version(actor) + 1, _version(reserve)).ok)
	assert(JSON.stringify([data.site.equipment_nations, actor.cargo, reserve]) == before)
	assert(orders.fund_public_order(actor_id, "n1", aid, {"grain": 4}, _version(actor), _version(reserve)).ok)
	assert(int(actor.cargo.grain) == 1 and int(reserve.cargo.grain) == 4)
	assert(orders.deliver_public_share(actor_id, "n1", aid, actor_id, _version(reserve), _version(actor)).ok)
	assert(int(actor.cargo.grain) == 3 and int(reserve.cargo.grain) == 2)
	before = JSON.stringify([data.site.equipment_nations, actor.cargo, reserve])
	assert(not orders.deliver_public_share(actor_id, "n1", aid, actor_id, _version(reserve), _version(actor)).ok)
	assert(JSON.stringify([data.site.equipment_nations, actor.cargo, reserve]) == before)
	before = JSON.stringify([data.site.equipment_nations, reserve, actions._person(npc_id).cargo])
	assert(not orders.deliver_public_share(actor_id, "n1", aid, npc_id, _version(reserve), _version(actions._person(npc_id))).ok, "Original independent recipient requires own actual control")
	assert(JSON.stringify([data.site.equipment_nations, reserve, actions._person(npc_id).cargo]) == before)
	assert(lab.character.place(entrance + Vector2i.LEFT, true))
	assert(lab.npc.place(entrance, true))
	assert(controller._control_family_person(null, npc_id).ok, "Real original Controller selects the same original NPC, no fake control callback")
	var npc := actions._person(npc_id)
	assert(orders.deliver_public_share(npc_id, "n1", aid, npc_id, _version(reserve), _version(npc)).ok, "Accepted original authorizer scope survives this legitimate control switch")
	assert(int(npc.cargo.grain) == 2 and int(reserve.cargo.get("grain", 0)) == 0)
	assert(data.site.equipment_nations.n1.technology_operations.public_orders[aid].status == "complete")
	before = JSON.stringify([data.site.equipment_nations, reserve, npc.cargo])
	assert(not orders.deliver_public_share(npc_id, "n1", aid, npc_id, _version(reserve), _version(npc)).ok)
	assert(JSON.stringify([data.site.equipment_nations, reserve, npc.cargo]) == before)
	assert(lab.npc.place(entrance + Vector2i.RIGHT, true))
	assert(lab.character.place(entrance, true))
	assert(controller._control_family_person(null, actor_id).ok)
	actor = actions._person(actor_id)
	var tax := orders.declare_tax_source(actor_id, "n1", warehouse, actor_id)
	assert(tax.ok, str(tax))
	assert(orders.authorize_public_source(actor_id, "n1", str(tax.order_id), {"grain": 1}).ok)
	assert(orders.fund_public_order(actor_id, "n1", str(tax.order_id), {"grain": 1}, _version(actor), _version(reserve)).ok)
	assert(int(reserve.cargo.grain) == 1)
	assert(orders.deliver_public_share(actor_id, "n1", str(tax.order_id), actor_id, _version(reserve), _version(actor)).ok)
	assert(int(reserve.cargo.get("grain", 0)) == 0 and int(actor.cargo.grain) == 3)
	assert(data.site.equipment_nations.n1.technology_operations.public_orders[str(tax.order_id)].receipts.size() == 2)
	before = JSON.stringify([data.site.equipment_nations, reserve, actor.cargo])
	assert(not orders.fund_public_order(actor_id, "n1", str(tax.order_id), {"grain": 1}, _version(actor), _version(reserve)).ok)
	assert(JSON.stringify([data.site.equipment_nations, reserve, actor.cargo]) == before)
	var people := {actor_id: true, npc_id: true}
	assert(Orders.valid_nations(data.site.equipment_nations, data.site.item_definitions, people))
	assert(Orders.validate_nation_operations(data, data.site, people).ok)
	lab.free()

