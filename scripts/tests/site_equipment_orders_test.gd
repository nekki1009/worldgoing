extends SceneTree

const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const PersonTest = preload("res://scripts/tests/site_person_actions_test.gd")

func _initialize() -> void:
	call_deferred("run")

func _fixture() -> Dictionary:
	var lab := PersonTest.Fixture.new()
	lab.terrain.site["inventory"] = {}
	lab.terrain.site["capacity"] = 8
	lab.terrain.site["depot_cell"] = lab.terrain.index(Vector2i(5, 4))
	var orders := Orders.new()
	orders.init(lab, lab.actions)
	orders.equipment_apply_guard = func(_person_id: int, _equipped: Dictionary) -> Dictionary:
		return SiteRuntime.ok() if lab.removal_allowed else SiteRuntime.fail("UNSUPPORTED")
	var old_item := _item(lab, lab.character.item_state, "weapon", "longsword_01", 1, true)
	var new_item := _item(lab, lab.terrain.site.depot_items, "weapon", "spear_01", 2)
	return {"lab": lab, "orders": orders, "old_item": old_item, "new_item": new_item}

func _item(lab: Variant, holder: Dictionary, slot: String, asset: String, original_owner: int, equipped: bool = false) -> String:
	var definition := {"slot": slot, "asset": asset, "tint": [1.0, 1.0, 1.0, 1.0]}
	var result := SiteRuntime.create_equipment(lab.terrain, holder, slot + ":" + asset, definition, original_owner, slot if equipped else "")
	assert(result.ok)
	return str(result.item_id)

func _nation(fixture: Dictionary) -> void:
	fixture.lab.terrain.site["equipment_nations"] = {"n1": {"military_head": 2, "members": [1, 2, 3], "standards": {}}}
	assert(fixture.orders.set_standard(2, "n1", "line", "正式槍兵", {"weapon": {"definition": "weapon:spear_01"}}).ok)

func _close(fixture: Dictionary) -> void:
	fixture.lab.actions.equipment_orders = null
	fixture.orders.equipment_apply_guard = Callable()
	fixture.orders.actions = null
	fixture.orders.lab = null
	fixture.lab.close()

func run() -> void:
	_check_authority_and_issue()
	_check_atomic_refusals()
	_check_personal()
	_check_substitutions()
	_check_controlled_personal()
	print("SITE EQUIPMENT ORDERS PASS: actual national-head authority, future-only standards, no default substitutes, shared 5s action clock, post-contact atomic swaps, original cargo/ownership, personal capacity and renderer refusal; no nation creation or visual proof")
	quit(0)

func _check_controlled_personal() -> void:
	var fixture := _fixture()
	var lab: Variant = fixture.lab
	var orders: Variant = fixture.orders
	var npc_item := _item(lab, lab.npc.item_state, "weapon", "spear_01", 2)
	var npc_cargo: Dictionary = lab.terrain.site.worker.cargo
	lab.controlled_id = 2
	assert(orders.begin_personal(1, "weapon", "").code == "NO_AUTHORITY")
	lab.terrain.site.worker.target = "actual-npc-work"
	assert(not orders.begin_personal(2, "weapon", npc_item).ok)
	lab.terrain.site.worker.target = ""
	lab.terrain.site.manual.target = "former-body-work"
	lab.npc.fatigue = 90.0
	assert(orders.begin_personal(2, "weapon", npc_item).ok)
	lab.actions.advance(5.0)
	lab.actions.settle_after_contacts()
	assert(lab.npc.item_state.equipped.weapon == npc_item and is_same(lab.terrain.site.worker.cargo, npc_cargo))
	assert(lab.character.item_state.equipped.weapon == fixture.old_item)
	lab.terrain.site.manual.target = ""
	var row: Dictionary = lab.army.combat_units[0]
	var army_item := _item(lab, row.item_state, "weapon", "spear_01", 3)
	var army_cargo: Dictionary = row.cargo
	lab.controlled_id = 3
	assert(orders.begin_personal(2, "weapon", "").code == "NO_AUTHORITY")
	assert(orders.begin_personal(3, "weapon", army_item).ok)
	lab.actions.advance(5.0)
	lab.actions.settle_after_contacts()
	assert(row.item_state.equipped.weapon == army_item and is_same(row.cargo, army_cargo))
	assert(lab.npc.item_state.equipped.weapon == npc_item, "Controlling a new original body cannot move or replace old-body gear")
	_close(fixture)

func _check_authority_and_issue() -> void:
	var fixture := _fixture()
	var lab: Variant = fixture.lab
	var orders: Variant = fixture.orders
	assert(orders.begin_issue(1, "n1", "line").code == "NO_AUTHORITY")
	assert(orders.set_standard(1, "n1", "line", "未授權", {"weapon": {"definition": "weapon:spear_01"}}).code == "NO_AUTHORITY")
	assert(not lab.terrain.site.has("equipment_nations"), "Opening equipment rules cannot create a nation or office")
	_nation(fixture)
	lab.npc.captive = true
	assert(orders.set_standard(2, "n1", "line", "被俘首長", {"weapon": {"definition": "weapon:spear_01"}}).code == "NO_AUTHORITY")
	lab.npc.captive = false
	lab.npc.knockout_left = 30.0
	assert(orders.set_standard(2, "n1", "line", "昏迷首長", {"weapon": {"definition": "weapon:spear_01"}}).code == "NO_AUTHORITY")
	lab.npc.knockout_left = 0.0
	var before := JSON.stringify([lab.character.item_state, lab.terrain.site.depot_items, lab.terrain.site.item_records])
	assert(orders.set_standard(1, "n1", "line", "玩家不是首長", {"weapon": {"definition": "weapon:spear_01"}}).code == "NO_AUTHORITY")
	assert(orders.set_standard(3, "n1", "line", "隊長不是首長", {"weapon": {"definition": "weapon:spear_01"}}).code == "NO_AUTHORITY")
	assert(orders.set_standard(2, "n1", "line", "重訂槍兵", {"weapon": {"definition": "weapon:spear_01"}}).ok)
	assert(JSON.stringify([lab.character.item_state, lab.terrain.site.depot_items, lab.terrain.site.item_records]) == before)
	assert(lab.changed.is_empty(), "A standard edit cannot change any current presentation")
	assert(lab.terrain.site.equipment_nations.n1.standards.line.slots.weapon.alternatives.is_empty())
	assert(Orders.valid_nations(lab.terrain.site.equipment_nations, lab.terrain.site.item_definitions, {1: true, 2: true, 3: true}))
	assert(Orders.valid_nations(JSON.parse_string(JSON.stringify(lab.terrain.site.equipment_nations)), lab.terrain.site.item_definitions, {1: true, 2: true, 3: true}), "Integral JSON person IDs and revisions retain the same authority")
	var invalid: Dictionary = lab.terrain.site.equipment_nations.duplicate(true)
	invalid["../bad"] = invalid.n1
	assert(not Orders.valid_nations(invalid, lab.terrain.site.item_definitions, {1: true, 2: true, 3: true}))
	invalid = lab.terrain.site.equipment_nations.duplicate(true)
	invalid.n1.members.append(1)
	assert(not Orders.valid_nations(invalid, lab.terrain.site.item_definitions, {1: true, 2: true, 3: true}))
	assert(not orders.set_standard(2, "n1", "bad", "跨槽", {"armor": {"definition": "weapon:spear_01"}}).ok)
	var armor := _item(lab, lab.character.item_state, "armor", "armor_iron_01", 1, true)
	var original_cargo: Dictionary = lab.terrain.site.manual.cargo
	var registry_count: int = lab.terrain.site.item_records.size()
	assert(orders.begin_issue(1, "n1", "line").seconds == 5.0)
	assert(lab.actions.is_busy(1) and not lab.actions.save_guard().ok)
	lab.actions.advance(4.999)
	assert(lab.actions.settle_after_contacts().is_empty() and lab.character.item_state.equipped.weapon == fixture.old_item)
	lab.actions.advance(0.001)
	assert(lab.actions.settle_after_contacts()[0].ok)
	assert(lab.character.item_state.equipped.weapon == fixture.new_item and lab.character.item_state.equipped.armor == armor)
	assert(lab.terrain.site.depot_items.item_ids == [fixture.old_item])
	assert(lab.terrain.site.item_records[fixture.new_item].holder == "person:1" and lab.terrain.site.item_records[fixture.new_item].original_owner == 2)
	assert(lab.terrain.site.item_records[fixture.old_item].holder == "depot")
	assert(lab.terrain.site.item_records.size() == registry_count and is_same(original_cargo, lab.character.ammo_inventory))
	assert(lab.actions.settle_after_contacts().is_empty() and orders.begin_issue(1, "n1", "line").code == "NO_CHANGE")
	_close(fixture)

func _check_atomic_refusals() -> void:
	for reason: String in ["hit", "move", "combat", "version", "standard", "capacity", "owner", "renderer", "member"]:
		var fixture := _fixture()
		_nation(fixture)
		var lab: Variant = fixture.lab
		assert(fixture.orders.begin_issue(1, "n1", "line").ok)
		lab.actions.advance(5.0)
		match reason:
			"hit": lab.character.apply_contact({"result": {"hp": 0.0, "stun": 1.0, "guard_break": false}, "shield": false})
			"move": lab.character.terrain_cell = Vector2i(4, 5)
			"combat": lab.terrain.site["combat_left"] = 10.0
			"version": lab.terrain.site.depot_items.version += 1
			"standard": assert(fixture.orders.set_standard(2, "n1", "line", "新版本", {"weapon": {"definition": "weapon:spear_01"}}).ok)
			"capacity": lab.terrain.site.capacity = 0
			"owner": lab.terrain.site.item_records[fixture.new_item].holder = "person:2"
			"renderer": lab.removal_allowed = false
			"member": lab.terrain.site.equipment_nations.n1.members.erase(1)
		var before := JSON.stringify([lab.character.item_state, lab.terrain.site.depot_items, lab.terrain.site.item_records])
		var result: Dictionary = lab.actions.settle_after_contacts()[0]
		assert(not result.ok, reason)
		assert(JSON.stringify([lab.character.item_state, lab.terrain.site.depot_items, lab.terrain.site.item_records]) == before, reason)
		assert(lab.character.item_state.equipped.weapon == fixture.old_item and lab.changed.is_empty())
		_close(fixture)

func _check_personal() -> void:
	var fixture := _fixture()
	var lab: Variant = fixture.lab
	var orders: Variant = fixture.orders
	var loose := _item(lab, lab.character.item_state, "weapon", "axe_01", 1)
	var holder: Dictionary = lab.character.item_state
	lab.terrain.site.manual.cargo["wood"] = 19
	assert(SiteRuntime.carried_size(lab.terrain.site.manual.cargo, holder) == 20)
	assert(not orders.begin_personal(2, "weapon", fixture.new_item).ok)
	assert(not orders.begin_personal(1, "weapon", fixture.new_item).ok, "The player cannot equip an unowned depot piece remotely")
	assert(orders.begin_personal(1, "weapon", loose).ok)
	lab.actions.advance(5.0)
	assert(lab.actions.settle_after_contacts()[0].ok and holder.equipped.weapon == loose)
	assert(holder.item_ids.has(fixture.old_item) and SiteRuntime.carried_size(lab.terrain.site.manual.cargo, holder) == 20)
	assert(orders.begin_personal(1, "weapon", "").code == "STORAGE_FULL")
	lab.terrain.site.manual.cargo.wood = 18
	assert(orders.begin_personal(1, "weapon", "").ok)
	lab.actions.advance(5.0)
	assert(lab.actions.settle_after_contacts()[0].ok and holder.equipped.is_empty())
	assert(holder.item_ids.size() == 2 and SiteRuntime.carried_size(lab.terrain.site.manual.cargo, holder) == 20)
	_close(fixture)

func _check_substitutions() -> void:
	var fixture := _fixture()
	_nation(fixture)
	var lab: Variant = fixture.lab
	var orders: Variant = fixture.orders
	# An actual axe is available, but the requested spear is held by a different person.
	var moved := SiteRuntime.transfer_items(lab.terrain, lab.terrain.site.depot_items, lab.terrain.site.inventory,
		lab.npc.item_state, lab.terrain.site.worker.cargo, {}, [fixture.new_item], int(lab.terrain.site.depot_items.version), 0)
	assert(moved.ok)
	var axe := _item(lab, lab.terrain.site.depot_items, "weapon", "axe_01", 2)
	assert(orders.begin_issue(1, "n1", "line").code == "MATERIALS")
	assert(lab.character.item_state.equipped.weapon == fixture.old_item)
	assert(orders.set_standard(2, "n1", "line", "明示戰斧替代", {"weapon": {"definition": "weapon:spear_01", "alternatives": ["weapon:axe_01"]}}).ok)
	assert(orders.begin_issue(1, "n1", "line").ok)
	lab.actions.advance(5.0)
	assert(lab.actions.settle_after_contacts()[0].ok and lab.character.item_state.equipped.weapon == axe)
	var fake := {"slot": "weapon", "asset": "invented_sword", "tint": [1.0, 1.0, 1.0, 1.0]}
	assert(not Orders.valid_definition("fake", fake))
	lab.terrain.site.item_definitions["fake"] = fake
	assert(not orders.set_standard(2, "n1", "bad", "不存在素材", {"weapon": {"definition": "fake"}}).ok)
	_close(fixture)
