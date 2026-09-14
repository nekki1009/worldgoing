extends "res://scripts/tests/site_work_team_clock_test.gd"
## GPU UI acceptance only. Existing data-layer/action tests own combat, timed
## equipment swaps and death-only continuity. This fixture invents no production
## nation, office or kinship: it explicitly supplies those test inputs below.

const OUTPUT := "res://.visual_captures/site_institutions_ui/"
const UI_SAVE := "res://.godot-temp/site_resources_contract/institutions_ui.json"
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const Visual = preload("res://scripts/ui/human_character_3d_editor.gd")

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 100000 # New GPU test; canonical helper bound is 120 seconds.
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("SITE INSTITUTIONS UI exceeded its 100-second deadline")
		quit(1)
	return false

func _dialog(lab: TerrainLab, node_name: String) -> AcceptDialog:
	var dialog := lab.get_node("SiteUI").find_child(node_name, true, false) as AcceptDialog
	assert(dialog != null and dialog.visible, "Original visible dialog missing: " + node_name)
	return dialog

func _click(parent: Node, button_name: String) -> void:
	var button := parent.find_child(button_name, true, false) as Button
	assert(button != null and not button.disabled, "Original enabled button missing: " + button_name)
	button.pressed.emit()

func _confirm(dialog: AcceptDialog) -> void:
	dialog.get_ok_button().pressed.emit()
	await process_frame
	assert(not is_instance_valid(dialog), "The original confirmation must close its dialog")

func _capture(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	assert(not picture.is_empty() and picture.save_png(OUTPUT + label + ".png") == OK)
	assert(Time.get_ticks_msec() < deadline)

func _stock(lab: TerrainLab) -> Dictionary:
	var site: Dictionary = lab.terrain.site
	var people := {}
	for actor: TerrainTestCharacter in [lab.character, lab.npc]:
		people[str(actor.person_id)] = actor.item_state.duplicate(true)
	for team: TerrainArmy in lab.combat_armies:
		for row: Dictionary in team.combat_units:
			people[str(int(row.person_id))] = {"holder": row.item_state.duplicate(true), "cargo": row.cargo.duplicate(true)}
	return {"definitions": site.item_definitions.duplicate(true), "records": site.item_records.duplicate(true),
		"depot": site.depot_items.duplicate(true), "inventory": site.inventory.duplicate(true),
		"manual_cargo": site.manual.cargo.duplicate(true), "worker_cargo": site.worker.cargo.duplicate(true),
		"next_item": site.next_item, "people": people, "at": Runtime.now(lab.terrain)}

func _assert_saved_ui(lab: TerrainLab, stock: Dictionary, nations: Dictionary, family: Dictionary) -> void:
	var current := _stock(lab)
	for field: String in stock:
		assert(current[field] == stock[field], "Saved UI changed original %s: before=%s after=%s" % [field, JSON.stringify(stock[field]), JSON.stringify(current[field])])
	assert(lab.terrain.site.equipment_nations == nations, "Saved national requirements changed: before=%s after=%s" % [JSON.stringify(nations), JSON.stringify(lab.terrain.site.equipment_nations)])
	assert(lab.terrain.site.family == family, "Saved family references changed: before=%s after=%s" % [JSON.stringify(family), JSON.stringify(lab.terrain.site.family)])

func _catalog(data: TerrainData) -> void:
	# Definition-only fixture catalog of actual existing asset IDs. No item is
	# minted, no stock credited, and existing shared definitions cannot change.
	for slot: Dictionary in Visual.PART_SLOTS:
		if str(slot.id) not in Runtime.EQUIPMENT_SLOTS:
			continue
		for option: Dictionary in slot.options:
			if str(option.id) == "none":
				continue
			var key := str(slot.id) + ":" + str(option.id)
			var definition := {"slot": str(slot.id), "asset": str(option.id), "tint": [1.0, 1.0, 1.0, 1.0]}
			assert(Orders.valid_definition(key, definition))
			if data.site.item_definitions.has(key):
				assert(data.site.item_definitions[key] == definition)
			else:
				data.site.item_definitions[key] = definition

func _choose_standard(dialog: AcceptDialog) -> void:
	var choice := dialog.find_child("EditStandard", true, false) as OptionButton
	assert(choice.item_count == 2 and str(choice.get_item_metadata(1)) == "unit_1")
	choice.select(1)
	choice.item_selected.emit(1)

func _check_reopened(lab: TerrainLab, expected: Dictionary) -> void:
	_press(lab.site_controller, "EquipmentStandards")
	var dialog := _dialog(lab, "EquipmentStandardsDialog")
	_choose_standard(dialog)
	for slot: String in Runtime.EQUIPMENT_SLOTS:
		var primary := dialog.find_child("StandardSlot_" + slot, true, false) as OptionButton
		assert(str(primary.get_item_metadata(primary.selected)) == str(expected[slot].definition), slot)
		_click(dialog, "StandardAlternatives_" + slot)
		var alternatives := _dialog(lab, "StandardAlternativesDialog")
		var list := alternatives.find_child("StandardAlternativeItems", true, false) as ItemList
		assert(list.select_mode == ItemList.SELECT_MULTI)
		var selected: Array = []
		for index: int in range(list.item_count):
			var candidate := str(list.get_item_metadata(index))
			assert(candidate != str(expected[slot].definition), "Primary is never its own alternative")
			assert(str(lab.terrain.site.item_definitions[candidate].slot) == slot)
			if list.is_selected(index):
				selected.append(candidate)
		assert(selected == expected[slot].alternatives, "Reopen lost explicit alternatives for " + slot)
		await _confirm(alternatives)
	# Submitting the unchanged existing standard must preserve all selections.
	_click(dialog, "CommitStandard")
	assert(lab.terrain.site.equipment_nations.ui_fixture.standards.unit_1.slots == expected)
	await _confirm(dialog)

func _register_family(lab: TerrainLab) -> void:
	var controller: SiteController = lab.site_controller
	assert(not lab.terrain.site.has("family"))
	_press(controller, "RegisterFamily")
	var dialog := _dialog(lab, "FamilyRegistryDialog")
	var person_input := dialog.find_child("FamilyPersonId", true, false) as SpinBox
	var label_input := dialog.find_child("FamilyMemberLabel", true, false) as LineEdit
	var age_input := dialog.find_child("FamilyMemberAge", true, false) as SpinBox
	# Explicit test references only; no faction/name/appearance kinship inference.
	for entry: Array in [[lab.character.person_id, "測試本人", 30], [lab.npc.person_id, "明確登錄的原家人", 16]]:
		person_input.value = int(entry[0])
		label_input.text = str(entry[1])
		age_input.value = int(entry[2])
		_click(dialog, "AddFamilyReference")
	var members := dialog.find_child("FamilyRegistryMembers", true, false) as ItemList
	assert(members.item_count == 2 and not lab.terrain.site.has("family"), "Draft UI is not a committed family")
	(dialog.find_child("FamilyRegistryComplete", true, false) as CheckBox).button_pressed = true
	await _capture("05_family_registration")
	_click(dialog, "CommitFamilyRegistry")
	await process_frame
	assert(lab.terrain.site.family.complete and lab.terrain.site.family.members.size() == 2)
	dialog = _dialog(lab, "FamilyDialog")
	members = dialog.find_child("FamilyMembers", true, false) as ItemList
	assert(members.item_count == 2 and int(members.get_item_metadata(1).age_years) == 16)
	members.select(1)
	var before_id := lab.controlled_person_id()
	_click(dialog, "ChooseFamilySuccessor")
	assert(controller.message.text.begins_with("NOT_DEAD") and lab.controlled_person_id() == before_id)
	assert(not paused and not bool(lab.terrain.site.paused), "An alive-person family page cannot pause or replace the body")
	await _capture("06_family_continuity_alive_guard")
	await _confirm(dialog)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("GPU display required for actual institutions UI captures")
		quit(1)
		return
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT)) == OK)
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	root.content_scale_size = Vector2i(1600, 1000)
	root.gui_embed_subwindows = true # Capture real embedded dialogs in the actual root viewport.
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.npc_retaliates = false
	var fixture := _work_fixture()
	var data: TerrainData = fixture.data
	lab.bind_terrain(data)
	var controller: SiteController = lab.site_controller
	controller._auto_save_blocked = true
	lab.npc.faction_id = lab.character.faction_id
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	var positions: Array[Vector2i] = []
	positions.assign(fixture.cells)
	assert(team.deploy_at(data, lab.character, lab.npc, positions) and team.enable_combat(false))
	team.set_process(false)
	team.faction_id = lab.character.faction_id
	team.settle_combat_command()
	controller.initialize_team_items(team)
	data.site.army_next_team = team.team_id + 1
	_press(controller, "JoinPlayerArmy")
	assert(team.player_member == lab.character)
	var player_id := lab.character.person_id
	var captain_id := team.combat_identity(team.current_commander)
	assert(captain_id != player_id)
	_press(controller, "EquipmentStandards")
	assert(controller.message.text.begins_with("NO_AUTHORITY") and data.site.get("equipment_nations", {}).is_empty())
	assert(lab.get_node_or_null("SiteUI/EquipmentStandardsDialog") == null)
	assert(controller._control_family_person(null, captain_id).ok) # Fixture control hook, not a family/death claim.
	_press(controller, "EquipmentStandards")
	assert(controller.message.text.begins_with("NO_AUTHORITY") and data.site.get("equipment_nations", {}).is_empty())
	assert(controller._control_family_person(null, player_id).ok)
	_catalog(data)
	# A real production office must arrive from existing nation data. Only this
	# fixture supplies explicit national membership and an original military head.
	data.site.equipment_nations = {"ui_fixture": {"military_head": player_id,
		"members": [player_id, lab.npc.person_id, captain_id], "standards": {}}}
	var unchanged := _stock(lab)
	_press(controller, "EquipmentStandards")
	var dialog := _dialog(lab, "EquipmentStandardsDialog")
	(dialog.find_child("StandardName", true, false) as LineEdit).text = "首版步兵 · 明列替代實物"
	var expected := {}
	for slot: String in Runtime.EQUIPMENT_SLOTS:
		var primary := dialog.find_child("StandardSlot_" + slot, true, false) as OptionButton
		assert(primary.item_count > 1, "Actual definition catalog missing slot: " + slot)
		primary.select(1)
		var primary_id := str(primary.get_item_metadata(1))
		_click(dialog, "StandardAlternatives_" + slot)
		var alternatives := _dialog(lab, "StandardAlternativesDialog")
		var list := alternatives.find_child("StandardAlternativeItems", true, false) as ItemList
		assert(list.select_mode == ItemList.SELECT_MULTI and list.item_count == primary.item_count - 2)
		var allowed: Array = []
		for index: int in range(list.item_count):
			var candidate := str(list.get_item_metadata(index))
			assert(candidate != primary_id and str(data.site.item_definitions[candidate].slot) == slot)
			if index < 2:
				list.select(index, false)
				allowed.append(candidate)
		if slot == "weapon":
			assert(allowed.size() == 2)
			await _capture("02_weapon_explicit_alternatives")
		await _confirm(alternatives)
		expected[slot] = {"definition": primary_id, "alternatives": allowed}
	_click(dialog, "CommitStandard")
	assert(data.site.equipment_nations.ui_fixture.standards.unit_1.slots == expected)
	assert(_stock(lab) == unchanged, "Editing a standard cannot rewrite definitions, equipment or stock")
	await _confirm(dialog)
	await _check_reopened(lab, expected)
	_press(controller, "EquipmentStandards")
	dialog = _dialog(lab, "EquipmentStandardsDialog")
	_choose_standard(dialog)
	var weapon := dialog.find_child("StandardSlot_weapon", true, false) as OptionButton
	var next_primary := str(expected.weapon.alternatives[0])
	for index: int in range(1, weapon.item_count):
		if str(weapon.get_item_metadata(index)) == next_primary:
			weapon.select(index)
	expected.weapon.definition = next_primary
	expected.weapon.alternatives.erase(next_primary)
	_click(dialog, "CommitStandard")
	assert(data.site.equipment_nations.ui_fixture.standards.unit_1.slots == expected)
	await _capture("01_equipment_standards_seven_slots")
	# The already-open form must recheck authority at actual submission time.
	var national_before: Dictionary = data.site.equipment_nations.duplicate(true)
	assert(controller._control_family_person(null, captain_id).ok)
	_click(dialog, "CommitStandard")
	assert(controller.message.text.begins_with("NO_AUTHORITY") and data.site.equipment_nations == national_before)
	assert(controller._control_family_person(null, player_id).ok)
	await _confirm(dialog)
	await _register_family(lab)
	assert(_stock(lab) == unchanged)
	var saved_family: Dictionary = data.site.family.duplicate(true)
	var saved_nations: Dictionary = data.site.equipment_nations.duplicate(true)
	controller.save_path = UI_SAVE
	controller.save_current()
	controller._auto_save_blocked = true
	assert(controller.message.text == "地圖已保存", controller.message.text)
	controller.load_current()
	controller._auto_save_blocked = true
	assert(lab.terrain != data, controller.message.text)
	data = lab.terrain
	team = lab.army
	_assert_saved_ui(lab, unchanged, saved_nations, saved_family)
	await _check_reopened(lab, expected)
	assert(_stock(lab) == unchanged)
	_press(controller, "EquipmentInventory")
	dialog = _dialog(lab, "EquipmentInventoryDialog")
	var owned := dialog.find_child("OwnedEquipmentItems", true, false) as ItemList
	assert(owned.item_count == lab.character.item_state.item_ids.size() and owned.item_count > 0)
	assert((dialog.find_child("IssueStandard", true, false) as OptionButton).item_count == 2)
	owned.select(0)
	await _capture("03_original_person_equipment_inventory")
	await _confirm(dialog)
	_press(controller, "ManagePlayerRoster")
	dialog = _dialog(lab, "RosterDialog")
	var roster := dialog.find_child("RosterMembers", true, false) as ItemList
	assert(roster.item_count == 3 and roster.select_mode == ItemList.SELECT_MULTI)
	roster.select(1, false)
	roster.select(2, false)
	assert(roster.get_selected_items().size() == 2)
	assert(int(roster.get_item_metadata(1)) == team.combat_identity(1) and int(roster.get_item_metadata(2)) == team.combat_identity(2))
	await _capture("04_original_roster_multi_selection")
	await _confirm(dialog)
	assert(_stock(lab) == unchanged and lab.controlled_person_id() == player_id)
	var report := {"scope": "Actual TerrainLab/SiteController GPU UI; no timed swap, death transition, political creation or army performance claim",
		"fixture_authority": "Explicit existing-person military_head and two explicit original family references; never inferred by production",
		"captures": 6, "slots": expected, "no_item_or_stock_mutation": true,
		"canonical_save_load_bind": true, "alive_successor_refused": true, "deadline_seconds": 100}
	var report_file := FileAccess.open(OUTPUT + "report.json", FileAccess.WRITE)
	assert(report_file != null)
	report_file.store_string(JSON.stringify(report, "\t", true, true))
	report_file.close()
	print("SITE INSTITUTIONS UI PASS: seven-slot primary and explicit alternatives, reopen/save/load, no implicit authority or item mutation, actual inventory/roster/family pages; inspect six PNGs")
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	quit(0)
