extends "res://scripts/tests/site_work_team_clock_test.gd"
## Actual loose-ground loot -> original personal holder -> inventory UI deposit
## -> original NPC 5-second formal issue. No item/office is minted by the UI.

func _equipment_dialog(lab: TerrainLab, item_id: String) -> AcceptDialog:
	_press(lab.site_controller, "EquipmentInventory")
	var dialog := lab.get_node("SiteUI/EquipmentInventoryDialog") as AcceptDialog
	var items := dialog.find_child("OwnedEquipmentItems", true, false) as ItemList
	var found := false
	for index: int in range(items.item_count):
		if str(items.get_item_metadata(index).id) == item_id:
			items.select(index)
			found = true
	assert(found)
	return dialog

func _stock(lab: TerrainLab) -> Array:
	return [lab.character.item_state.duplicate(true), lab.npc.item_state.duplicate(true),
		lab.terrain.site.manual.cargo.duplicate(true), lab.terrain.site.worker.cargo.duplicate(true),
		lab.terrain.site.depot_items.duplicate(true), lab.terrain.site.inventory.duplicate(true),
		lab.terrain.site.item_records.duplicate(true), lab.terrain.site.item_definitions.duplicate(true)]

func _run() -> void:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.npc_retaliates = false
	var data := _fixture()
	data.site.worker_enabled = false
	data.site.depot_cell = data.index(Vector2i(20, 22))
	lab.bind_terrain(data)
	var controller: SiteController = lab.site_controller
	controller._auto_save_blocked = true
	var player := lab.character
	var recipient := lab.npc
	recipient.faction_id = player.faction_id
	recipient.issue_command(TerrainTestNPC.Command.STOP)
	assert(player.place(Vector2i(21, 22), true) and recipient.place(Vector2i(20, 21), true))
	var cargo: Dictionary = data.site.manual.cargo
	var holder: Dictionary = player.item_state
	var npc_holder: Dictionary = recipient.item_state
	var depot: Dictionary = data.site.depot_items
	var inventory: Dictionary = data.site.inventory
	var item_id := str(npc_holder.equipped.weapon)
	var definition_id := str(data.site.item_records[item_id].definition)
	var record_count: int = data.site.item_records.size()
	var next_item: int = data.site.next_item
	var original_owner := int(data.site.item_records[item_id].original_owner)
	# Explicit initial-world fixture: the original NPC has put their own weapon
	# into a loose ground bag. The actual player must still take it via timed UI.
	var dropped := Runtime.leave_ground_loot(data, npc_holder, data.site.worker.cargo,
		recipient.person_id, Vector2i(21, 21), "cargo", {}, [item_id], int(npc_holder.version))
	assert(dropped.ok)
	controller.equipment_changed(recipient.person_id)
	controller.select_cell(Vector2i(21, 21))
	_press(controller, "InspectLoot")
	var loot := lab.get_node("SiteUI/PersonInventoryDialog") as AcceptDialog
	var sources := loot.find_child("LootSource", true, false) as OptionButton
	var source_found := false
	for index: int in range(sources.item_count):
		if sources.get_item_metadata(index) == {"kind": "ground", "id": str(dropped.container_id)}:
			sources.select(index)
			sources.item_selected.emit(index)
			source_found = true
	assert(source_found)
	var loot_items := loot.find_child("LootItems", true, false) as ItemList
	assert(loot_items.item_count == 1 and loot_items.get_item_metadata(0) == item_id)
	loot_items.select(0)
	(loot.find_child("BeginLoot", true, false) as Button).pressed.emit()
	loot.free()
	assert(controller.person_actions.is_busy(player.person_id))
	var job: Dictionary = controller.person_actions.job_for(player.person_id)
	# Peaceful work settles on the retained 30 Hz common step (2 game seconds).
	# Advance through the first real step at/after completion, not a discarded fraction.
	lab._process(ceilf(float(job.duration) / (60.0 * TerrainLab.EXCHANGE_ACTION_STEP)) * TerrainLab.EXCHANGE_ACTION_STEP)
	assert(not controller.person_actions.is_busy(player.person_id) and holder.item_ids.has(item_id))
	assert(not holder.equipped.values().has(item_id) and not data.site.ground_loot.has(str(dropped.container_id)))
	var before := _stock(lab)
	assert(controller.deposit_owned_equipment(recipient.person_id, [item_id], int(npc_holder.version)).code == "NO_AUTHORITY")
	assert(controller.deposit_owned_equipment(player.person_id, [item_id], int(holder.version) - 1).code == "STALE_SOURCE")
	assert(_stock(lab) == before)
	# Worn items, full capacity, stale executor and equal-value depot replacement
	# all use the real UI callback and leave every original item in place.
	var worn := str(holder.equipped.weapon)
	var dialog := _equipment_dialog(lab, worn)
	(dialog.find_child("DepositOwnedEquipment", true, false) as Button).pressed.emit()
	assert(controller.message.text.begins_with(Runtime.fail("INVALID").message))
	dialog.free()
	assert(_stock(lab) == before)
	var capacity := int(data.site.capacity)
	data.site.capacity = Runtime.inventory_size(inventory) + depot.item_ids.size()
	dialog = _equipment_dialog(lab, item_id)
	(dialog.find_child("DepositOwnedEquipment", true, false) as Button).pressed.emit()
	assert(controller.message.text.begins_with(Runtime.fail("STORAGE_FULL").message))
	dialog.free()
	data.site.capacity = capacity
	assert(_stock(lab) == before)
	dialog = _equipment_dialog(lab, item_id)
	controller.select_cell(recipient.terrain_cell)
	_press(controller, "ChooseRecoveryWorker")
	assert(controller.person_executor_id == recipient.person_id)
	for name: String in ["WearOwnedItem", "RemoveOwnedItem", "DepositOwnedEquipment", "IssueEquipment"]:
		(dialog.find_child(name, true, false) as Button).pressed.emit()
		assert(controller.message.text.begins_with("STALE"))
	dialog.free()
	dialog = _equipment_dialog(lab, str(npc_holder.equipped.armor))
	(dialog.find_child("DepositOwnedEquipment", true, false) as Button).pressed.emit()
	assert(controller.message.text.begins_with(Runtime.fail("NO_AUTHORITY").message))
	dialog.free()
	_press(controller, "ChoosePlayerLooter")
	assert(_stock(lab) == before)
	dialog = _equipment_dialog(lab, item_id)
	data.site.depot_items = depot.duplicate(true)
	(dialog.find_child("DepositOwnedEquipment", true, false) as Button).pressed.emit()
	assert(controller.message.text.begins_with("STALE") and _stock(lab) == before)
	dialog.free()
	data.site.depot_items = depot
	var clock_before := Runtime.now(data)
	dialog = _equipment_dialog(lab, item_id)
	(dialog.find_child("DepositOwnedEquipment", true, false) as Button).pressed.emit()
	assert(not holder.item_ids.has(item_id) and depot.item_ids.has(item_id))
	assert(data.site.item_records[item_id].holder == "depot" and Runtime.now(data) == clock_before)
	(dialog.find_child("DepositOwnedEquipment", true, false) as Button).pressed.emit()
	assert(controller.message.text.begins_with("STALE") and depot.item_ids.count(item_id) == 1)
	dialog.free()
	assert(holder.equipped.weapon == worn and is_same(cargo, data.site.manual.cargo))
	assert(is_same(holder, player.item_state) and is_same(depot, data.site.depot_items) and is_same(inventory, data.site.inventory))
	# Political membership is explicit fixture context, never UI-created power.
	data.site.equipment_nations = {"depot_test": {"military_head": player.person_id,
		"members": [player.person_id, recipient.person_id], "standards": {}}}
	assert(controller.equipment_orders.set_standard(player.person_id, "depot_test", "recovered", "原回收實裝",
		{"weapon": {"definition": definition_id, "alternatives": []}}).ok)
	assert(not npc_holder.equipped.has("weapon"))
	controller.select_cell(recipient.terrain_cell)
	_press(controller, "ChooseRecoveryWorker")
	_press(controller, "EquipmentInventory")
	dialog = lab.get_node("SiteUI/EquipmentInventoryDialog") as AcceptDialog
	var standard := dialog.find_child("IssueStandard", true, false) as OptionButton
	assert(standard.item_count == 2 and standard.get_item_metadata(1) == ["depot_test", "recovered"])
	standard.select(1)
	(dialog.find_child("IssueEquipment", true, false) as Button).pressed.emit()
	assert(controller.person_actions.is_busy(recipient.person_id), controller.message.text)
	dialog.free()
	lab._process(ceilf(5.0 / (60.0 * TerrainLab.EXCHANGE_ACTION_STEP)) * TerrainLab.EXCHANGE_ACTION_STEP)
	assert(not controller.person_actions.is_busy(recipient.person_id), controller.message.text)
	assert(npc_holder.equipped.weapon == item_id and depot.item_ids.is_empty())
	assert(data.site.item_records[item_id].holder == "person:%d" % recipient.person_id)
	assert(int(data.site.item_records[item_id].original_owner) == original_owner)
	assert(data.site.item_records.size() == record_count and data.site.next_item == next_item)
	assert(is_same(npc_holder, recipient.item_state) and not holder.item_ids.has(item_id))
	assert(inventory == before[5] and cargo == before[2] and data.site.worker.cargo == before[3])
	assert(data.site.item_definitions == before[7])
	assert(controller.person_appearance(recipient.person_id).parts.weapon == data.site.item_definitions[definition_id].asset)
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE EQUIPMENT DEPOT UI PASS: actual ground loot/common clock, original owned loose item UI deposit, original NPC formal 5s issue, unchanged item identity/stock, authority/worn/capacity/version/stale-window guards; no automatic gear or political authority")
	quit(0)
