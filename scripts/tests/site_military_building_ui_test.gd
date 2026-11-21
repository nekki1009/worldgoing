extends "res://scripts/tests/site_building_ui_test.gd"
## Formal UI signals must reach the original people, supply and cargo owners.
const Garrison = preload("res://scripts/terrain_lab/site_garrison.gd")
const UI_OUTPUT := "res://output/site_military_buildings_20261003/ui/"
var ui_captures: Array[String] = []

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 150000
	_run.call_deferred()

func _team_fixture(lab: TerrainLab, positions: Array[Vector2i]) -> TerrainArmy:
	var team: TerrainArmy = lab.army
	team.roster_size = positions.size()
	team.faction_id = 1
	assert(team.deploy_at(lab.terrain, lab.character, lab.npc, positions) and team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()
	lab.terrain.site.army_next_team = 4
	return team

func _select_metadata(choice: OptionButton, value: Variant) -> void:
	for index: int in choice.item_count:
		if choice.get_item_metadata(index) == value:
			choice.select(index)
			choice.item_selected.emit(index)
			return
	assert(false, "Formal choice lacks the original identity: %s" % str(value))

func _capture_ui(label: String, target: Control = null) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	assert(DisplayServer.get_name() != "headless", "--capture requires the original GPU renderer")
	assert(DirAccess.make_dir_recursive_absolute(UI_OUTPUT) == OK)
	for _frame: int in range(3): await process_frame
	if target != null:
		var parent: Node = target.get_parent()
		while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
		if parent is ScrollContainer: parent.ensure_control_visible(target)
	for _frame: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	assert(not picture.is_empty() and picture.save_png(UI_OUTPUT + label + ".png") == OK)
	ui_captures.append(label + ".png")

func _garrison_buttons() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var key := _formal_feature(data, "barracks", Vector2i(20, 20), Vector2i(10, 10))
	var team := _team_fixture(lab, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26)])
	var captain := team.combat_identity(0)
	var promote := team.combat_identity(1)
	var soldier := team.combat_identity(2)
	var originals := {}
	for identity: int in [captain, promote, soldier]:
		var person: Dictionary = controller.person_actions._person(identity)
		originals[identity] = {"body": person.body, "holder": person.holder, "cargo": person.cargo, "cell": person.cell}
	controller.feature_key = key
	controller.update_ui()
	controller.open_window("construction")
	_press(lab, "ManageGarrison")
	assert(controller._ui_dialogs.has("garrison"))
	var dialog: Window = controller._ui_dialogs.garrison.dialog
	_press(lab, "ManageGarrison")
	assert(controller._ui_dialogs.garrison.dialog == dialog, "Repeated clicks reuse the scoped original dialog")
	var source := dialog.find_child("GarrisonSourceTeam", true, false) as OptionButton
	_select_metadata(source, team.team_id)
	_press(lab, "AdmitGarrison")
	assert(team.garrison_feature_id == key and team.current_commander == -1 and team.formal_commander == -1)
	var officers := dialog.find_child("GarrisonOfficers", true, false) as ItemList
	var status := dialog.find_child("GarrisonStatus", true, false) as Label
	var summary := dialog.find_child("GarrisonSoldierSummary", true, false) as Label
	assert(officers.item_count == 1 and int(officers.get_item_metadata(0)) == captain)
	assert(status.text.contains("軍官 1 · 士兵 2") and summary.text.contains("清醒士兵 2 人"))
	var promotion := dialog.find_child("GarrisonPromotionCandidate", true, false) as OptionButton
	_select_metadata(promotion, promote)
	_press(lab, "PromoteGarrisonOfficer")
	assert(team.military_role(team.index_for_identity(promote)) == "officer" and officers.item_count == 2)
	_press(lab, "RefreshGarrison")
	assert(status.text.contains("軍官 2 · 士兵 1") and summary.text.contains("清醒士兵 1 人"))
	await _capture_ui("garrison_officers_and_soldiers")
	var commander := dialog.find_child("GarrisonCommander", true, false) as OptionButton
	_select_metadata(commander, captain)
	var count := dialog.find_child("GarrisonSoldierCount", true, false) as SpinBox
	count.value = 1
	var target := dialog.find_child("GarrisonTargetTeam", true, false) as OptionButton
	assert(target.item_count > 0)
	target.select(0)
	_press(lab, "FormGarrisonTeam")
	var captain_person: Dictionary = controller.person_actions._person(captain)
	var formed: TerrainArmy = captain_person.owner
	assert(formed != team and formed.garrison_feature_id.is_empty() and formed.combat_units.size() == 2)
	assert(formed.combat_identity(formed.current_commander) == captain and formed.index_for_identity(soldier) >= 0)
	assert(team.combat_units.size() == 1 and team.combat_identity(0) == promote and team.garrison_feature_id == key)
	for identity: int in originals:
		var person: Dictionary = controller.person_actions._person(identity)
		assert(is_same(person.body, originals[identity].body) and is_same(person.holder, originals[identity].holder))
		assert(is_same(person.cargo, originals[identity].cargo) and person.cell == originals[identity].cell)
	assert(status.text.contains("軍官 1 · 士兵 0"))
	_select_metadata(source, formed.team_id)
	_press(lab, "AdmitGarrison")
	var query := Garrison.query(lab, key)
	assert(query.ok and query.people_count == 3 and query.officers.size() == 2 and query.soldier_count == 1)
	controller.feature_key = ""
	_press(lab, "RefreshGarrison")
	assert(controller.message.text.contains("軍營或控制人物已變更"))
	controller.invalidate_ui_context()
	assert(not controller._ui_dialogs.has("garrison"))
	lab.free()
	await process_frame

func _training_buttons() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var key := _formal_feature(data, "training_ground", Vector2i(20, 20), Vector2i(10, 10))
	var team := _team_fixture(lab, [Vector2i(23, 26), Vector2i(24, 26)])
	var captain := team.combat_identity(team.current_commander)
	data.site.controlled_person_id = captain
	controller.feature_key = key
	controller.update_ui()
	controller.open_window("construction")
	_press(lab, "TrainAtGround")
	var entry: Dictionary = controller._supply_entry(team)
	assert(not entry.is_empty() and entry.training_order and entry.training_requester == captain and entry.training_feature_id == key)
	assert(controller.building_selection.text.contains("可用站位"))
	await _capture_ui("training_ground_formal_action", controller.building_actions.training)
	_press(lab, "StopPlayerTeamTraining")
	assert(not entry.training_order and entry.training_requester == -1 and entry.training_feature_id.is_empty())
	_press(lab, "TrainPlayerTeam")
	assert(entry.training_order and entry.training_requester == captain and entry.training_feature_id == key)
	_press(lab, "StopPlayerTeamTraining")
	controller.feature_key = ""
	controller.update_ui()
	assert(controller.building_actions.training.disabled and controller.building_actions.garrison.disabled)
	lab.free()
	await process_frame

func _finish_ui_job(controller: SiteController, identity: int, kind: String, seconds: float) -> Array[Dictionary]:
	assert(str(controller.person_actions.job_for(identity).get("kind", "")) == kind, str(controller.person_actions.job_for(identity)))
	controller.person_actions.advance(seconds)
	var results := controller.person_actions.settle_after_contacts()
	assert(results.size() == 1 and results[0].ok and not controller.person_actions.is_busy(identity), str(results))
	return results

func _tent_buttons() -> void:
	var data := _building_fixture()
	data.site.inventory.erase("camp_tent") # A paid recipe, rather than fixture stock, supplies this package.
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var team := _team_fixture(lab, [Vector2i(9, 10)])
	var identity := team.combat_identity(0)
	team.combat_units[0].logistics = true
	data.site.controlled_person_id = identity
	controller.update_ui()
	controller.open_window("transport")
	_press(lab, "RefreshTentLogistics")
	var choice := lab.find_child("TentLogisticPerson", true, false) as OptionButton
	_select_metadata(choice, identity)
	var cargo: Dictionary = team.combat_units[0].cargo
	var holder: Dictionary = team.combat_units[0].item_state
	var before: Dictionary = data.site.inventory.duplicate(true)
	_press(lab, "CraftCampTent")
	assert(data.site.inventory == before)
	_finish_ui_job(controller, identity, "ranged_craft", 150.0)
	assert(int(data.site.inventory.camp_tent) == 1 and int(data.site.inventory.cloth) == int(before.cloth) - 4)
	assert(int(data.site.inventory.wood) == int(before.wood) - 2 and int(data.site.inventory.fiber) == int(before.fiber) - 2)
	_press(lab, "TakeCampTent")
	assert(int(cargo.get("camp_tent", 0)) == 1 and int(data.site.inventory.get("camp_tent", 0)) == 0)
	_press(lab, "ReturnCampTent")
	assert(int(cargo.get("camp_tent", 0)) == 0 and int(data.site.inventory.get("camp_tent", 0)) == 1)
	_press(lab, "TakeCampTent")
	# Explicit parked fixture; the four formal transfer buttons use the real vehicle owner.
	data.site.vehicles["1"] = {"id": "1", "kind": "cart", "cell": data.index(Vector2i(8, 10)), "facing": [1, 0],
		"team_id": team.team_id, "operator_id": 0, "holder": Runtime.new_item_state("vehicle:1"), "cargo": {}, "move": {}, "stop_pending": false}
	controller._refresh_vehicle_controls()
	_select_metadata(controller.vehicle_choice, "1")
	var car: Dictionary = data.site.vehicles["1"]
	_press(lab, "LoadCampTent")
	assert(int(cargo.get("camp_tent", 0)) == 0 and int(car.cargo.get("camp_tent", 0)) == 1)
	_press(lab, "UnloadCampTent")
	assert(int(cargo.get("camp_tent", 0)) == 1 and int(car.cargo.get("camp_tent", 0)) == 0)
	var direction := lab.find_child("TentDirection", true, false) as OptionButton
	direction.select(3)
	direction.item_selected.emit(3)
	controller.selected = Vector2i(9, 11)
	_press(lab, "DeployCampTent")
	assert(str(controller.person_actions.job_for(identity).get("kind", "")) == "tent_deploy")
	_press(lab, "CancelCampTentWork")
	assert(not controller.person_actions.is_busy(identity) and int(cargo.get("camp_tent", 0)) == 1 and data.site.features.is_empty())
	_press(lab, "DeployCampTent")
	var results := _finish_ui_job(controller, identity, "tent_deploy", 31.0)
	var key := str(results[0].feature)
	assert(data.site.features.has(key) and int(data.site.features[key].quarter) == 3 and int(cargo.get("camp_tent", 0)) == 0)
	controller.feature_key = key
	controller.update_ui()
	_press(lab, "RefreshTentLogistics")
	var tent_status := lab.find_child("TentLogisticStatus", true, false) as Label
	assert(tent_status.text.contains("帳篷包 0"))
	var pack_button := lab.find_child("PackCampTent", true, false) as Button
	assert(pack_button != null)
	await _capture_ui("tent_formal_transport_controls", pack_button)
	_press(lab, "PackCampTent")
	_finish_ui_job(controller, identity, "tent_pack", 31.0)
	assert(not data.site.features.has(key) and int(cargo.get("camp_tent", 0)) == 1)
	assert(is_same(team.combat_units[0].cargo, cargo) and is_same(team.combat_units[0].item_state, holder))
	assert(team.cells[0] == Vector2i(9, 10), "Formal tent controls must not relocate the original logistic person")
	lab.free()
	await process_frame

func _run() -> void:
	await _garrison_buttons()
	await _training_buttons()
	await _tent_buttons()
	TerrainArmy.release_contact_source()
	if "--capture" in OS.get_cmdline_user_args():
		assert(ui_captures.size() == 3)
		var report := FileAccess.open(UI_OUTPUT + "captures.json", FileAccess.WRITE)
		assert(report != null)
		report.store_string(JSON.stringify({"status": "SITE_MILITARY_BUILDING_UI_PASS", "captures": ui_captures,
			"scope": "Formal signal-to-owner garrison, training and tent logistics contract; manual image review is separate."}, "\t"))
		report.close()
	print("SITE_MILITARY_BUILDING_UI_PASS: formal garrison dialog/reuse/stale guard, admit/promote/refresh/officer-plus-soldier formation, original row/holder/cargo/cell preservation, facility training start/stop, paid tent craft/depot/vehicle transfer/cancel/deploy/pack; captures=", ui_captures.size())
	quit(0)
