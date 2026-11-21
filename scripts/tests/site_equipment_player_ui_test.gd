extends "res://scripts/tests/site_work_team_clock_test.gd"
## Actual main-scene buttons and common clock; no default worker or invented gear.

const UI_SAVE := "res://.godot-temp/site_resources_contract/equipment_player_ui.json"
var lab: TerrainLab
var controller: SiteController

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 90000
	_run.call_deferred()

func _press(ui: SiteController, button_name: String) -> void:
	var category := "people" if button_name in ["ChooseRecoveryWorker", "ChoosePlayerLooter", "InspectLoot"] else "equipment"
	ui.open_window(category)
	var window: Window = ui.formal_windows[category]
	var button := window.find_child(button_name, true, false) as Button
	assert(button != null and not button.disabled and button.is_visible_in_tree(), "Actual formal control missing or unavailable: " + button_name)
	button.pressed.emit()

func _select_item(dialog: AcceptDialog, item_id: String, worn: bool) -> void:
	var items := dialog.find_child("OwnedEquipmentItems", true, false) as ItemList
	items.deselect_all()
	for index: int in items.item_count:
		if str(items.get_item_metadata(index).id) == item_id:
			assert(items.get_item_text(index).contains("穿戴" if worn else "行囊"), "The same window must refresh the actual holder")
			items.select(index)
			items.multi_selected.emit(index, true)
			return
	assert(false, "Original item disappeared from the same inventory window: " + item_id)

func _click(dialog: AcceptDialog, button_name: String) -> void:
	var button := dialog.find_child(button_name, true, false) as Button
	assert(button != null and not button.disabled, "Expected enabled original equipment control: " + button_name)
	button.pressed.emit()

func _open(item_id: String, worn: bool = true) -> AcceptDialog:
	_press(controller, "EquipmentInventory")
	var dialog := lab.get_node("SiteUI/EquipmentInventoryDialog") as AcceptDialog
	assert(dialog.visible)
	assert(dialog.title.contains("#%d" % lab.controlled_person_id()), "Personal equipment must follow the controlled person, not the looting executor")
	_select_item(dialog, item_id, worn)
	return dialog

func _snapshot() -> Array:
	var holders := []
	for actor: TerrainTestCharacter in lab.combat_actors:
		holders.append([actor.item_state.duplicate(true), lab.terrain.site["manual" if actor == lab.character else "worker"].cargo.duplicate(true)])
	for team: TerrainArmy in lab.combat_armies:
		for row: Dictionary in team.combat_units:
			holders.append([row.item_state.duplicate(true), row.cargo.duplicate(true)])
	return [holders, lab.terrain.site.item_records.duplicate(true), lab.terrain.site.item_definitions.duplicate(true),
		lab.terrain.site.depot_items.duplicate(true), lab.terrain.site.inventory.duplicate(true), lab.terrain.site.next_item]

func _finish(dialog: AcceptDialog, identity: int, before: Array) -> void:
	assert(controller.person_actions.is_busy(identity), controller.message.text)
	controller.update_ui()
	assert((dialog.find_child("WearOwnedItem", true, false) as Button).disabled)
	assert((dialog.find_child("RemoveOwnedItem", true, false) as Button).disabled)
	var digest := FileAccess.get_sha256(UI_SAVE)
	controller.save_current()
	assert(controller.supply_save_guard().code == "BUSY" and FileAccess.get_sha256(UI_SAVE) == digest, "Formal save must preserve the last good file while changing gear")
	lab._process(2.0 * TerrainLab.EXCHANGE_ACTION_STEP)
	assert(controller.person_actions.is_busy(identity) and _snapshot() == before, "No equipment commits before five game seconds")
	lab._process(TerrainLab.EXCHANGE_ACTION_STEP)
	controller.update_ui()
	assert(not controller.person_actions.is_busy(identity), controller.message.text)
	assert(is_instance_valid(dialog) and lab.get_node("SiteUI/EquipmentInventoryDialog") == dialog, "Successful work refreshes the same dialog")
	assert(not (dialog.find_child("WearOwnedItem", true, false) as Button).disabled or not (dialog.find_child("RemoveOwnedItem", true, false) as Button).disabled)
	assert(controller.supply_save_guard().ok)

func _scenario_equipment(captain: int) -> void:
	var before := _snapshot()
	var nation_id := "trial_team_%d" % lab.army.team_id
	var registered := controller.register_trial_equipment_nation(lab.army, nation_id, captain, [captain], "western")
	assert(registered.ok and _snapshot() == before, str(registered))
	var nations: Dictionary = lab.terrain.site.equipment_nations.duplicate(true)
	assert(controller.register_trial_equipment_nation(lab.army, nation_id, captain, [captain], "japanese").code == "INVALID")
	assert(lab.terrain.site.equipment_nations == nations and _snapshot() == before)
	var capacity := int(lab.terrain.site.capacity)
	lab.terrain.site.capacity = Runtime.carried_size(lab.terrain.site.inventory, lab.terrain.site.depot_items)
	assert(controller.stock_trial_equipment(lab.army, "weapon", "spear_01", 2, captain).code == "STORAGE_FULL")
	assert(_snapshot() == before, "Failed explicit test stock cannot partially create definitions or items")
	lab.terrain.site.capacity = capacity
	var next_item := int(lab.terrain.site.next_item)
	assert(controller.stock_trial_equipment(lab.army, "weapon", "spear_01", 2, captain).ok)
	assert(lab.terrain.site.item_records.size() == before[1].size() + 2 and lab.terrain.site.next_item == next_item + 2)
	for serial: int in range(next_item, next_item + 2):
		var record: Dictionary = lab.terrain.site.item_records[str(serial)]
		assert(record.original_owner == captain and record.holder == "depot" and record.definition == "weapon:spear_01")
		assert(lab.terrain.site.depot_items.item_ids.has(str(serial)))
	var stocked := _snapshot()
	assert(controller.revoke_trial_equipment_nation(lab.army, nation_id).ok)
	assert(not lab.terrain.site.equipment_nations.has(nation_id) and _snapshot() == stocked)
	# Clear only after releasing the explicit national reference, returning control
	# to the original actor so the real clear command does not remove our player.
	assert(controller._control_family_person(null, lab.character.person_id).ok)
	lab.clear_army()
	assert(not lab.army.has_army() and lab.terrain.site.item_records.size() == stocked[1].size(), "Clearing a retired test team cannot delete equipment")
	for item_id: String in stocked[1]:
		var old: Dictionary = stocked[1][item_id].duplicate(true)
		var current: Dictionary = lab.terrain.site.item_records[item_id].duplicate(true)
		old.erase("holder")
		current.erase("holder")
		assert(current == old, "Only the actual holder may change when original gear moves to ground cargo")

func _run() -> void:
	# The main scene is the main menu now (開局流程); the formal Site entry is the TerrainLab scene itself.
	var scene := "res://scenes/terrain_lab/TerrainLab.tscn"
	lab = (load(scene) as PackedScene).instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	controller = lab.site_controller
	controller.set_process(false)
	controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	assert(lab.npc == null and lab.combat_actors.size() == 1, "The formal startup must not recreate the removed worker")
	# Explicit placement of one real Army captain supplies a second existing body,
	# never a fabricated national office or spare equipment item.
	var positions: Array[Vector2i] = []
	for index: int in lab.terrain.flags.size():
		var cell := lab.terrain.cell_from_index(index)
		if lab.terrain.is_walkable(cell) and not lab.character.occupies_cell(cell):
			positions.append(cell)
			break
	assert(positions.size() == 1)
	lab.army.roster_size = 1
	assert(lab.army.deploy_at(lab.terrain, lab.character, null, positions) and lab.army.enable_combat(false))
	lab.army.faction_id = lab.character.faction_id
	lab.army.settle_combat_command()
	controller.initialize_team_items(lab.army)
	lab.terrain.site.army_next_team = lab.army.team_id + 1
	var captain := lab.army.combat_identity(0)
	var player := lab.character.person_id
	assert(captain != player, "The controlled captain must have a real person ID distinct from the starting player")
	var original_holder: Dictionary = lab.character.item_state
	var weapon := str(original_holder.equipped.weapon)
	var original_records: Dictionary = lab.terrain.site.item_records.duplicate(true)
	var record_count: int = original_records.size()
	var next_item: int = lab.terrain.site.next_item
	controller.save_path = UI_SAVE
	controller.save_current()
	controller._auto_save_blocked = true
	assert(controller.message.text == "地圖已保存", controller.message.text)
	# The old bug opened this captain's inventory after selecting a looter.
	controller.select_cell(lab.army.cells[0])
	_press(controller, "ChooseRecoveryWorker")
	assert(controller.person_executor_id == captain)
	var dialog := _open(weapon)
	for button_name: String in ["RemoveOwnedItem", "WearOwnedItem", "RemoveOwnedItem"]:
		var before := _snapshot()
		_click(dialog, button_name)
		_finish(dialog, player, before)
		var worn := button_name == "WearOwnedItem"
		assert(original_holder.equipped.get("weapon", "") == (weapon if worn else ""))
		assert(controller.person_appearance(player).parts.weapon == (lab.terrain.site.item_definitions[original_records[weapon].definition].asset if worn else "none"))
		_select_item(dialog, weapon, worn)
	assert(lab.terrain.site.item_records == original_records and is_same(original_holder, lab.character.item_state))
	# Put the real loose item into an adjacent existing depot. No new item is seeded.
	var depot_cell := TerrainArmy.INVALID_CELL
	for direction: Vector2i in TerrainData.DIRECTIONS:
		if lab.terrain.can_step(lab.character.terrain_cell, lab.character.terrain_cell + direction):
			depot_cell = lab.character.terrain_cell + direction
			break
	assert(depot_cell != TerrainArmy.INVALID_CELL)
	lab.terrain.site.depot_cell = lab.terrain.index(depot_cell)
	_click(dialog, "DepositOwnedEquipment")
	assert(not original_holder.item_ids.has(weapon) and lab.terrain.site.depot_items.item_ids.has(weapon), controller.message.text)
	var items := dialog.find_child("OwnedEquipmentItems", true, false) as ItemList
	for index: int in items.item_count: assert(str(items.get_item_metadata(index).id) != weapon)
	dialog.free()
	# True stale contexts still reject; merely changing the looting executor was
	# deliberately not one of these identity/ownership changes.
	var helmet := str(original_holder.equipped.helmet)
	for reason: String in ["control", "holder", "depot", "version"]:
		dialog = _open(helmet)
		var depot: Dictionary = lab.terrain.site.depot_items
		var version := int(original_holder.version)
		var before := _snapshot()
		match reason:
			"control": assert(controller._control_family_person(null, captain).ok)
			"holder": lab.character.item_state = original_holder.duplicate(true)
			"depot": lab.terrain.site.depot_items = depot.duplicate(true)
			"version": original_holder.version += 1
		if reason == "control":
			assert(not is_instance_valid(dialog) and not controller._ui_dialogs.has("equipment"), "Control change must dispose the original inventory dispatch scope")
			assert(_snapshot() == before and not controller.person_actions.is_busy(player), reason)
		else:
			before = _snapshot()
			(dialog.find_child("RemoveOwnedItem", true, false) as Button).pressed.emit()
			assert(controller.message.text.begins_with("STALE") and _snapshot() == before and not controller.person_actions.is_busy(player), reason)
			dialog.free()
		lab.character.item_state = original_holder
		lab.terrain.site.depot_items = depot
		original_holder.version = version
		assert(controller._control_family_person(null, player).ok)
	dialog = _open(helmet)
	_click(dialog, "RemoveOwnedItem")
	assert(controller.person_actions.is_busy(player))
	original_holder.version += 1 # A real concurrent revision must not be absorbed by UI refresh.
	var interrupted := _snapshot()
	lab._process(3.0 * TerrainLab.EXCHANGE_ACTION_STEP)
	controller.update_ui()
	assert(not controller.person_actions.is_busy(player) and _snapshot() == interrupted)
	assert((dialog.find_child("EquipmentStatus", true, false) as Label).text.contains("STALE"), "Failure must remain visible after original settlement and UI refresh")
	dialog.free()
	# The current player can be an original Army body with an ID other than 1.
	assert(controller._control_family_person(null, captain).ok)
	controller.person_executor_id = player
	var captain_holder: Dictionary = lab.army.combat_units[0].item_state
	var captain_weapon := str(captain_holder.equipped.weapon)
	dialog = _open(captain_weapon)
	for button_name: String in ["RemoveOwnedItem", "WearOwnedItem"]:
		var before := _snapshot()
		_click(dialog, button_name)
		_finish(dialog, captain, before)
		_select_item(dialog, captain_weapon, button_name == "WearOwnedItem")
	assert(not original_holder.equipped.has("weapon") and captain_holder.equipped.weapon == captain_weapon)
	dialog.free()
	assert(lab.terrain.site.item_records.size() == record_count and lab.terrain.site.next_item == next_item)
	var expected := _snapshot()
	controller.save_current()
	controller._auto_save_blocked = true
	assert(controller.message.text == "地圖已保存", controller.message.text)
	controller.load_current()
	controller._auto_save_blocked = true
	assert(lab.controlled_person_id() == captain and _snapshot() == expected, controller.message.text)
	assert(lab.npc == null)
	_scenario_equipment(captain)
	print("SITE EQUIPMENT PLAYER UI PASS: formal startup without worker, controlled-person routing including original Army captain, same-window remove/wear/deposit, five-second common clock, true stale refusals, formal busy-save and exact item roundtrip")
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	quit(0)
