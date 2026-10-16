extends "res://scripts/tests/site_workflow_test.gd"
## UI dispatch/identity regression; provider tests own timing and atomic commit.
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")

func _click(parent: Node, node_name: String) -> void:
	var button := parent.find_child(node_name, true, false) as Button
	assert(button != null and not button.disabled, "Actual enabled UI button missing: " + node_name)
	button.pressed.emit()

func _open(lab: TerrainLab) -> AcceptDialog:
	lab.site_controller.open_window("supply")
	var supply: Window = lab.site_controller.formal_windows.supply
	assert(supply.visible)
	_click(supply, "OpenLogistics")
	var dialog := lab.get_node_or_null("SiteUI/LogisticsDialog") as AcceptDialog
	assert(dialog != null and dialog.visible)
	return dialog

func _select(dialog: AcceptDialog, node_name: String, metadata: Variant) -> void:
	var choice := dialog.find_child(node_name, true, false) as OptionButton
	assert(choice != null)
	for index: int in range(choice.item_count):
		if choice.get_item_metadata(index) == metadata:
			choice.select(index)
			choice.item_selected.emit(index)
			return
	assert(false, "Actual metadata missing from " + node_name + ": " + str(metadata))

func _quantity(dialog: AcceptDialog, text: String, all_opened: bool = false) -> void:
	(dialog.find_child("LogisticsQuantity", true, false) as LineEdit).text = text
	(dialog.find_child("LogisticsAllOpened", true, false) as CheckBox).button_pressed = all_opened

func _run() -> void:
	var lab := TerrainLab.new()
	lab.npc = TerrainTestNPC.new() # Explicit original ground-owner fixture; formal startup has no worker.
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.npc_retaliates = false
	var data := _fixture()
	lab.bind_terrain(data)
	var controller: SiteController = lab.site_controller
	controller._auto_save_blocked = true
	var player_placed: bool = lab.character.place(Vector2i(21, 22), true)
	assert(player_placed)
	var npc_placed: bool = lab.npc.place(Vector2i(15, 15), true)
	assert(npc_placed)
	lab.npc.issue_command(TerrainTestNPC.Command.STOP)
	lab.npc.faction_id = 2 # The remote original ground owner is not allied.
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	var cells: Array[Vector2i] = [Vector2i(22, 22), Vector2i(22, 23), Vector2i(22, 24), Vector2i(22, 25)]
	var team_deployed: bool = team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false)
	assert(team_deployed)
	team.set_process(false)
	team.faction_id = lab.character.faction_id
	team.settle_combat_command()
	controller.initialize_team_items(team)
	var source_team: TerrainArmy = lab.opposing_army
	source_team.roster_size = 3
	var source_cells: Array[Vector2i] = [Vector2i(23, 22), Vector2i(23, 23), Vector2i(23, 24)]
	var source_deployed: bool = source_team.deploy_at(data, lab.character, lab.npc, source_cells) and source_team.enable_combat(false)
	assert(source_deployed)
	source_team.set_process(false)
	source_team.faction_id = team.faction_id
	source_team.settle_combat_command()
	controller.initialize_team_items(source_team)
	var receiver := team.combat_identity(0)
	var captain := team.combat_identity(team.current_commander)
	var donor := source_team.combat_identity(source_team.current_commander)
	data.site.manual.cargo["fish"] = 16
	var cargo: Dictionary = data.site.manual.cargo
	var holder: Dictionary = lab.character.item_state
	var private := Sustain.create(0.0)
	private.open_rations = 0.123456789123 # Exact initial fixture stock, not clock advancement.
	data.site["person_supply"] = {str(lab.character.person_id): private}
	var source_entry := controller._enable_team_supply(source_team)
	source_entry.inventory["fish"] = 4
	source_entry.sustain.open_rations = 0.625
	data.site.worker.cargo["fish"] = 4
	var ground_open := {"open_rations": 0.375}
	var drop := Runtime.leave_ground_loot(data, lab.npc.item_state, data.site.worker.cargo,
		lab.npc.person_id, Vector2i(21, 22), "cargo", {"fish": 4}, [], int(lab.npc.item_state.version), ground_open, 0.375)
	assert(drop.ok and float(ground_open.open_rations) == 0.0)
	var container: Dictionary = data.site.ground_loot[str(drop.container_id)]
	var base_capacity := controller.team_food_capacity(team)
	var item_count: int = data.site.item_records.size()
	var dialog := _open(lab)
	_select(dialog, "LogisticsTargetTeam", team.team_id)
	_select(dialog, "LogisticsReceiver", receiver)
	var list := dialog.find_child("LogisticsMembers", true, false) as ItemList
	assert(list.item_count == 4 and list.select_mode == ItemList.SELECT_MULTI)
	list.select(1, false)
	list.select(2, false)
	_click(dialog, "AssignLogisticsMembers")
	assert(controller.message.text.begins_with("NO_AUTHORITY"))
	assert(not team.combat_units[1].logistics and not team.combat_units[2].logistics)
	_select(dialog, "LogisticsSource", {})
	_quantity(dialog, "2")
	_click(dialog, "BeginLogisticsFood")
	var entry := controller._supply_entry(team)
	assert(not entry.delivery.is_empty() and float(entry.delivery.quantity) == 2.0, controller.message.text)
	assert(cargo.fish == 16 and is_same(cargo, data.site.manual.cargo) and is_same(holder, lab.character.item_state))
	_click(dialog, "CancelLogisticsFood")
	assert(entry.delivery.is_empty() and cargo.fish == 16)
	_quantity(dialog, "ignored in exact-all-open mode", true)
	_click(dialog, "BeginLogisticsFood")
	assert(not entry.delivery.is_empty() and float(entry.delivery.quantity) == float(private.open_rations), controller.message.text)
	assert(float(entry.delivery.quantity) == 0.123456789123, "UI must never round opened food through a display string or SpinBox step")
	_click(dialog, "CancelLogisticsFood")
	_quantity(dialog, "not a number")
	_click(dialog, "BeginLogisticsFood")
	assert(entry.delivery.is_empty() and controller.message.text.begins_with(Runtime.fail("INVALID").message))
	_quantity(dialog, "13") # Original source has enough; the four-person target only carries 12.
	_click(dialog, "BeginLogisticsFood")
	assert(entry.delivery.is_empty() and controller.message.text.begins_with(Runtime.fail("STORAGE_FULL").message))
	# An already-open form cannot become the newly controlled captain's order.
	var captain_control: Dictionary = controller._control_family_person(null, captain)
	assert(captain_control.ok)
	assert(lab.controlled_person_id() == captain)
	assert(is_instance_valid(dialog) and not dialog.visible and not dialog.is_inside_tree() and dialog.get_parent() == null and dialog.is_queued_for_deletion() and not controller._ui_dialogs.has("logistics"), "Changing control must immediately detach and invalidate the old logistics scope")
	for stale_action: String in ["AssignLogisticsMembers", "ReleaseLogisticsMembers", "BeginLogisticsFood", "CancelLogisticsFood"]:
		controller.message.text = ""
		_click(dialog, stale_action)
		assert(controller.message.text.begins_with(Runtime.fail("STALE").message), "Detached old logistics callbacks must refuse changed control: " + stale_action)
		assert(controller.team_food_capacity(team) == base_capacity and not team.combat_units[1].logistics and not team.combat_units[2].logistics)
		assert(entry.delivery.is_empty() and cargo.fish == 16 and float(private.open_rations) == 0.123456789123)
	# queue_free is deferred; two frame signals cross the deletion flush from either entry phase.
	await process_frame
	await process_frame
	assert(not is_instance_valid(dialog) and not controller._ui_dialogs.has("logistics"), "Changing control must dispose the old logistics dispatch scope")
	assert(controller.team_food_capacity(team) == base_capacity and not team.combat_units[1].logistics and not team.combat_units[2].logistics)
	assert(entry.delivery.is_empty() and cargo.fish == 16 and float(private.open_rations) == 0.123456789123)
	dialog = _open(lab)
	_select(dialog, "LogisticsTargetTeam", team.team_id)
	_select(dialog, "LogisticsReceiver", receiver)
	list = dialog.find_child("LogisticsMembers", true, false) as ItemList
	list.select(1, false)
	list.select(2, false)
	_click(dialog, "AssignLogisticsMembers")
	assert(team.combat_units[1].logistics and team.combat_units[2].logistics, controller.message.text)
	assert(controller.team_food_capacity(team) == base_capacity + 6.0)
	assert(Runtime.CARRY_CAPACITY == 20 and data.site.item_records.size() == item_count, "Six team rations are not a second personal bag or new items")
	# Refreshing roster labels must not lose explicit multi-selection.
	list = dialog.find_child("LogisticsMembers", true, false) as ItemList
	assert(list.get_selected_items().size() == 2)
	_click(dialog, "ReleaseLogisticsMembers")
	assert(not team.combat_units[1].logistics and not team.combat_units[2].logistics)
	assert(controller.team_food_capacity(team) == base_capacity)
	# Depot stock is displayed even when physically unreachable; only provider
	# proximity checks may accept or reject a transfer, never the UI itself.
	_select(dialog, "LogisticsSource", {"kind": "depot"})
	_quantity(dialog, "1")
	var depot_before: Dictionary = data.site.inventory.duplicate(true)
	_click(dialog, "BeginLogisticsFood")
	assert(entry.delivery.is_empty() and controller.message.text.begins_with(Runtime.fail("UNREACHABLE").message))
	assert(data.site.inventory == depot_before)
	data.site.depot_cell = data.index(Vector2i(21, 22)) # Explicit fixture stock location, not a delivery teleport.
	_click(dialog, "RefreshLogisticsStock")
	_click(dialog, "BeginLogisticsFood")
	assert(not entry.delivery.is_empty() and float(entry.delivery.quantity) == 1.0, controller.message.text)
	assert(data.site.inventory == depot_before)
	_click(dialog, "CancelLogisticsFood")
	_select(dialog, "LogisticsSource", {"kind": "ground", "container_id": str(drop.container_id)})
	_quantity(dialog, "unused", true)
	_click(dialog, "BeginLogisticsFood")
	assert(not entry.delivery.is_empty() and float(entry.delivery.quantity) == 0.375, controller.message.text)
	assert(container.cargo.fish == 4 and float(container.open_rations) == 0.375 and lab.npc.faction_id != team.faction_id)
	_click(dialog, "CancelLogisticsFood")
	dialog.free()
	# The actual source team's commander selects its own real representative.
	var donor_control: Dictionary = controller._control_family_person(null, donor)
	assert(donor_control.ok)
	dialog = _open(lab)
	_select(dialog, "LogisticsTargetTeam", team.team_id)
	_select(dialog, "LogisticsReceiver", receiver)
	_select(dialog, "LogisticsSource", {"kind": "team", "team_id": source_team.team_id})
	_select(dialog, "LogisticsSourceRepresentative", donor)
	_quantity(dialog, "unused", true)
	_click(dialog, "BeginLogisticsFood")
	assert(not entry.delivery.is_empty() and float(entry.delivery.quantity) == 0.625, controller.message.text)
	assert(source_entry.inventory.fish == 4 and float(source_entry.sustain.open_rations) == 0.625)
	_click(dialog, "CancelLogisticsFood")
	assert(entry.delivery.is_empty() and data.site.item_records.size() == item_count)
	assert(cargo.fish == 16 and float(private.open_rations) == 0.123456789123 and Runtime.now(data) == 0.0)
	dialog.free()
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE LOGISTICS UI PASS: actual team/member/source metadata, no implicit commander authority, exact fractional opened food, stale-control rejection, original 3/6 capacity roles, provider distance/capacity guards, no UI stock debit; timed commit tested separately")
	quit(0)
