extends SceneTree
## Actual P2/P6 controls, original NPC office and real items; no mocked owners.
## One live captain keeps this headless wiring check independent of GPU capture.

var deadline := 0
var lab: TerrainLab
var controller: SiteController
var test_host: Window

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 90000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		_check(false, "90-second UI test deadline exceeded")
	return false

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("SITE EQUIPMENT TRIAL UI: " + message)
		quit(1)
	return condition

func _click(parent: Node, name: String) -> bool:
	var button := parent.find_child(name, true, false) as Button
	if not _check(button != null, "Missing visible button " + name): return false
	if not _check(not button.disabled and button.is_visible_in_tree(), "Unavailable button " + name): return false
	button.pressed.emit()
	return true

func _pick(parent: Node, name: String, metadata: Variant) -> bool:
	var choice := parent.find_child(name, true, false) as OptionButton
	if not _check(choice != null and not choice.disabled, "Missing enabled choice " + name): return false
	for index: int in choice.item_count:
		if choice.get_item_metadata(index) == metadata:
			choice.select(index)
			choice.item_selected.emit(index)
			return true
	return _check(false, "Choice %s lacks %s" % [name, str(metadata)])

func _items() -> Array:
	return [lab.character.item_state.duplicate(true), lab.army.combat_units[0].item_state.duplicate(true),
		lab.terrain.site.item_records.duplicate(true), lab.terrain.site.item_definitions.duplicate(true),
		lab.terrain.site.depot_items.duplicate(true), lab.terrain.site.next_item]

func _run() -> void:
	if not _check(OS.get_cmdline_user_args().has("--site-test-ui"), "Run this explicit developer UI contract with --site-test-ui"): return
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
	if not _check(lab.npc == null and lab.combat_actors.size() == 1, "Formal startup must have no default worker"): return
	# Deploy through the original Army API on unmodified generated terrain. The
	# depot is placed beside that original body; no nation, holder or stock seed.
	var positions: Array[Vector2i] = []
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var cell: Vector2i = lab.character.terrain_cell + direction
		if lab.terrain.can_step(lab.character.terrain_cell, cell):
			positions.append(cell)
			break
	if not _check(positions.size() == 1, "No legal original deployment cell beside player"): return
	lab.army.roster_size = 1
	if not _check(lab.army.deploy_at(lab.terrain, lab.character, null, positions), "Original Army deployment refused"): return
	if not _check(lab.army.enable_combat(false), "Original captain initialization refused"): return
	lab.army.faction_id = lab.character.faction_id
	lab.army.settle_combat_command()
	controller.initialize_team_items(lab.army)
	lab.terrain.site.army_next_team = lab.army.team_id + 1
	lab.terrain.site.depot_cell = lab.terrain.index(lab.character.terrain_cell)
	var captain: int = lab.army.combat_identity(0)
	var player: int = lab.controlled_person_id()
	var holder: Dictionary = lab.army.combat_units[0].item_state
	var old_weapon: String = str(holder.equipped.get("weapon", ""))
	if not _check(captain != player and not old_weapon.is_empty() and lab.army._uses_live_presenter(0), "Requires an original NPC live captain with real weapon"): return
	if not _check(str(lab.terrain.site.item_records[old_weapon].definition) != "weapon:spear_01", "Fixture already has requested spear"): return
	var original_player: Dictionary = lab.character.item_state.duplicate(true)
	var before: Array = _items()
	test_host = lab.site_test_window
	if not _check(test_host != null, "Explicit developer window was not installed"): return
	test_host.call("open")
	(test_host.find_child("TestTabs", true, false) as TabContainer).current_tab = 3
	controller.trial_command_team.select(lab.combat_armies.find(lab.army))
	if not _click(test_host, "TrialEquipmentSetup"): return
	var setup := test_host.get_node_or_null("TrialEquipmentSetupDialog") as AcceptDialog
	if not _check(setup != null and setup.visible, "Trial setup did not open"): return
	if not _pick(setup, "TrialEquipmentTeam", lab.army): return
	if not _pick(setup, "TrialEquipmentHead", captain): return
	if not _pick(setup, "TrialEquipmentCulture", "western"): return
	var members := setup.find_child("TrialEquipmentMembers", true, false) as ItemList
	if not _check(members != null and members.item_count == 1 and int(members.get_item_metadata(0)) == captain, "Setup must list the original captain"): return
	members.deselect_all()
	members.select(0)
	members.multi_selected.emit(0, true)
	var nation_field := setup.find_child("TrialEquipmentNationId", true, false) as LineEdit
	if not _check(nation_field != null, "Missing explicit trial nation id"): return
	var nation_id: String = "trial_team_%d" % lab.army.team_id
	nation_field.text = nation_id
	if not _click(setup, "RegisterTrialEquipmentNation"): return
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not _check(nation.get("military_head", -1) == captain and nation.get("members", []) == [captain] and nation.get("culture", "") == "western", "UI nation registration failed: " + controller.message.text): return
	if not _check(_items() == before and lab.controlled_person_id() == player, "Registering office must not equip, create items or take control"): return
	if not _pick(setup, "TrialEquipmentCatalog", {"slot": "weapon", "asset": "spear_01"}): return
	var quantity := setup.find_child("TrialEquipmentQuantity", true, false) as SpinBox
	if not _check(quantity != null, "Missing explicit stock quantity"): return
	quantity.value = 1
	var next_item: int = lab.terrain.site.next_item
	if not _click(setup, "StockTrialEquipment"): return
	var new_weapon: String = str(next_item)
	var record: Dictionary = lab.terrain.site.item_records.get(new_weapon, {})
	if not _check(record.get("definition", "") == "weapon:spear_01" and record.get("original_owner", -1) == captain and record.get("holder", "") == "depot", "Stock button must create the selected real item: " + controller.message.text): return
	if not _check(lab.terrain.site.next_item == next_item + 1 and lab.terrain.site.item_records.size() == before[2].size() + 1 and lab.terrain.site.depot_items.item_ids.has(new_weapon), "Exactly one new ledger item must be in the depot"): return
	if not _check(holder == before[1] and lab.character.item_state == original_player, "Stocking must not change either original holder"): return
	before = _items()
	if not _click(setup, "TrialEquipmentStandards"): return
	var standards := test_host.get_node_or_null("EquipmentStandardsDialog") as AcceptDialog
	if not _check(standards != null and standards.visible and standards.title.contains("#%d" % captain), "NPC authority must open its actual standards editor"): return
	if not _pick(standards, "StandardSlot_weapon", "weapon:spear_01"): return
	if not _pick(standards, "StandardPalette", "blue"): return
	var title := standards.find_child("StandardName", true, false) as LineEdit
	var palette := standards.find_child("StandardPalette", true, false) as OptionButton
	if not _check(title != null and palette.item_count == 16, "NPC editor must expose the original sixteen palettes"): return
	title.text = "UI explicit spear standard"
	if not _click(standards, "CommitStandard"): return
	var standard: Dictionary = nation.standards.get("unit_1", {})
	if not _check(standard.get("slots", {}).get("weapon", {}).get("definition", "") == "weapon:spear_01", "Visible standard commit failed: " + controller.message.text): return
	if not _check(_items() == before and lab.controlled_person_id() == player, "NPC standard authoring must not move items or change control"): return
	standards.free()
	setup.free()
	if not _click(test_host, "TrialTeamEquipment"): return
	var equipment := test_host.get_node_or_null("TeamEquipmentDialog") as AcceptDialog
	if not _check(equipment != null and equipment.visible, "Trial team equipment did not open"): return
	if not _pick(equipment, "TeamEquipmentNation", nation_id): return
	if not _pick(equipment, "TeamEquipmentStandard", "unit_1"): return
	if not _pick(equipment, "TeamEquipmentRepresentative", captain): return
	var simulation := equipment.find_child("TeamEquipmentSimulateNpcCommander", true, false) as CheckBox
	var report := equipment.find_child("TeamEquipmentResult", true, false) as Label
	if not _check(simulation != null and report != null, "Trial UI must explicitly disclose NPC command simulation"): return
	simulation.button_pressed = true
	if not _click(equipment, "PreviewTeamEquipment"): return
	if not _check(report.text.contains("目標 1 人") and report.text.contains("需換 1 人") and report.text.contains("領 1 件") and report.text.contains("退 1 件"), "Actual batch preview failed: " + report.text): return
	if not _check(_items() == before and not controller.person_actions.is_busy(captain), "UI preview must reserve or mutate nothing"): return
	if not _click(equipment, "BeginTeamEquipment"): return
	var job: Dictionary = controller.person_actions.job_for(captain)
	if not _check(not job.is_empty(), "UI begin created no original job: " + report.text): return
	var order: Dictionary = job.get("order", {})
	if not _check(order.get("mode", "") == "team_issue" and order.get("requester_id", -1) == captain and order.get("representative_id", -1) == captain and order.get("target_ids", []) == [captain], "UI must route real requester, representative and original team targets"): return
	if not _check(not bool(job.get("preparing", false)), "HEADLESS BOUNDARY: UI begin accepted, but this recipe requires GPU atlas preparation; completion is not verified"): return
	if not _check(_items() == before and controller.supply_save_guard().get("code", "") == "BUSY", "Beginning must retain items and block formal save"): return
	lab._process(2.0 * TerrainLab.EXCHANGE_ACTION_STEP)
	controller.update_ui()
	if not _check(controller.person_actions.is_busy(captain) and _items() == before, "No batch transfer before five game seconds"): return
	equipment.free()
	if not _click(test_host, "TrialTeamEquipment"): return
	equipment = test_host.get_node_or_null("TeamEquipmentDialog") as AcceptDialog
	report = equipment.find_child("TeamEquipmentResult", true, false) as Label if equipment != null else null
	if not _check(report != null and report.text.contains("整隊換裝") and controller.person_actions.is_busy(captain), "Reopened team panel must resume the original job's progress and cancel scope"): return
	lab._process(TerrainLab.EXCHANGE_ACTION_STEP)
	var unrelated := {"ok": false, "code": "OTHER", "message": "其他人物作業的結果", "executor_id": player}
	controller.show_result(unrelated)
	controller.update_ui()
	if not _check(not controller.person_actions.is_busy(captain) and holder.equipped.get("weapon", "") == new_weapon, "Common clock did not settle original batch: " + report.text): return
	if not _check(not holder.item_ids.has(old_weapon) and holder.item_ids.has(new_weapon) and lab.terrain.site.depot_items.item_ids.has(old_weapon) and not lab.terrain.site.depot_items.item_ids.has(new_weapon), "Exact old/new physical IDs did not exchange holders"): return
	if not _check(lab.terrain.site.item_records.size() == before[2].size() and lab.terrain.site.next_item == before[5] and int(lab.terrain.site.depot_items.version) == int(before[4].version) + 1, "Batch must conserve records and publish one depot revision"): return
	if not _check(lab.character.item_state == original_player and lab.controlled_person_id() == player and controller.supply_save_guard().ok, "Explicit NPC command must preserve player and release save guard"): return
	if not _check(report.text.begins_with("OK："), "Completion must remain visible in the original dialog: " + report.text): return
	if DisplayServer.get_name() != "headless":
		var capture_path := "res://output/site_equipment_change_20260926/trial_ui_gpu.png"
		DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
		await RenderingServer.frame_post_draw
		if not _check(test_host.get_texture().get_image().save_png(capture_path) == OK, "Could not save actual native-window viewport capture"): return
	var issued_records: Dictionary = lab.terrain.site.item_records.duplicate(true)
	controller.save_path = "res://.godot-temp/site_resources_contract/equipment_trial_ui.json"
	controller.save_current()
	if not _check(controller.message.text == "地圖已保存", "Completed team issue must be savable: " + controller.message.text): return
	controller.load_current()
	if not _check(lab.army.combat_identity(0) == captain and lab.army.combat_units[0].item_state.equipped.get("weapon", "") == new_weapon and lab.terrain.site.item_records == issued_records, "Save/load must retain the exact team item identities"): return
	if not _check(lab.terrain.site.get("equipment_nations", {}).get(nation_id, {}).get("standards", {}).has("unit_1") and lab.controlled_person_id() == player, "Save/load must retain the explicit nation, standard and player identity"): return
	print("SITE EQUIPMENT TRIAL UI PASS: actual setup/head/member/culture/stock/standard controls, explicit NPC requester, pure preview, timed real-ID batch exchange; one live captain only, no GPU atlas or multi-person atomicity claim")
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	quit(0)
