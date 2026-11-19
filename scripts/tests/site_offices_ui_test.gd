extends "res://scripts/tests/site_building_ui_test.gd"
## Position page (OFFICE_POSITIONS_AND_DUTIES_PLAN 8) through the formal team
## window: real buttons build one pending plan, the live check reports rule
## violations, apply goes through the original owners, non-heads only view,
## and a migrated nation is edited through the same page.

func _click(parent: Node, node_name: String) -> void:
	var button := parent.find_child(node_name, true, false) as Button
	assert(button != null and not button.disabled, "Enabled UI button missing: " + node_name)
	button.pressed.emit()

func _pick(list: ItemList, prefix: String) -> void:
	for index: int in range(list.item_count):
		if list.get_item_text(index).begins_with(prefix):
			list.select(index)
			list.item_selected.emit(index)
			return
	assert(false, "List row missing: " + prefix)

func _choose_option(dialog: Window, node_name: String, metadata: Variant) -> void:
	var choice := dialog.find_child(node_name, true, false) as OptionButton
	for index: int in range(choice.item_count):
		if choice.get_item_metadata(index) == metadata:
			choice.select(index)
			choice.item_selected.emit(index)
			return
	assert(false, "Option missing from %s: %s" % [node_name, str(metadata)])

func _open_page(lab: TerrainLab) -> Window:
	lab.site_controller.open_window("team")
	_click(lab.site_controller.formal_windows.team, "OfficesPage")
	var dialog := lab.get_node_or_null("SiteUI/OfficesDialog") as Window
	assert(dialog != null and dialog.visible, "Position page opens from the formal team window")
	return dialog

func _text(dialog: Window, node_name: String) -> String:
	return (dialog.find_child(node_name, true, false) as Label).text

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	var data := _building_fixture()
	var lab := _building_lab(data)
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	team.faction_id = 1
	assert(team.deploy_at(data, lab.character, lab.npc, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26), Vector2i(26, 26)]))
	assert(team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()
	data.site.army_next_team = team.team_id + 1
	var captain := team.combat_identity(team.current_commander)
	var coach := team.combat_identity(2)
	assert(team.set_military_role(coach, "officer").ok and team.record_officer_service([2], true).ok)
	data.site.controlled_person_id = captain
	assert(lab.player_army() == team)
	# Start from the empty one-seat-per-duty layout: R1b auto-appointment seats
	# officers when they are promoted or enter service (user decision 2026-10-07).
	team.offices = SiteOffices.default_offices("team", -1, false)
	team._mark_serving_dirty()

	var dialog := _open_page(lab)
	var seats := dialog.find_child("OfficePositions", true, false) as ItemList
	var duties := dialog.find_child("OfficeDuties", true, false) as ItemList
	assert(seats.item_count == SiteOffices.duty_ids("team").size() and duties.item_count == seats.item_count, "One seat per duty by default")
	var training_row := ""
	for index: int in range(duties.item_count):
		if duties.get_item_text(index).begins_with("訓練令"): training_row = duties.get_item_text(index)
	assert(training_row.contains("教頭") and training_row.contains("代行：#%d" % captain), "Vacant seat shows the acting head: " + training_row)

	# Appoint through the pending plan, then apply.
	_pick(seats, "教頭")
	_choose_option(dialog, "OfficeCandidate", coach)
	_click(dialog, "OfficeAppoint")
	assert(_text(dialog, "OfficePlan").contains("任命 #%d" % coach), _text(dialog, "OfficePlan"))
	assert(_text(dialog, "OfficeCheck").begins_with("✓"), _text(dialog, "OfficeCheck"))
	assert(team.duty_decider("team.training") == captain, "Pending plan changes nothing before apply")
	_click(dialog, "OfficeApply")
	assert(team.duty_decider("team.training") == coach, "Applied through TerrainArmy.apply_office_plan")
	assert(_text(dialog, "OfficePlan").ends_with("無"))

	# Live rule check: moving the holder's only duty away is flagged and refused.
	var revision := int(team.offices.revision)
	_pick(duties, "訓練令")
	_pick(seats, "隊長")
	_click(dialog, "OfficeAssignDuty")
	assert(_text(dialog, "OfficeCheck").begins_with("⚠") and _text(dialog, "OfficeCheck").contains("教頭"), _text(dialog, "OfficeCheck"))
	_click(dialog, "OfficeApply")
	assert(int(team.offices.revision) == revision and team.duty_decider("team.training") == coach, "Rejected plan leaves offices untouched")
	_click(dialog, "OfficeClear")

	# Rename and add in one plan.
	_pick(seats, "工頭")
	(dialog.find_child("OfficeName", true, false) as LineEdit).text = "營造官"
	_click(dialog, "OfficeRename")
	(dialog.find_child("OfficeName", true, false) as LineEdit).text = "參謀"
	_click(dialog, "OfficeAdd")
	_click(dialog, "OfficeApply")
	assert(team.offices.positions.size() == SiteOffices.duty_ids("team").size() + 1)
	assert(SiteOffices.position(team.offices, str(team.offices.duties["team.work"])).name == "營造官")

	# Duty AI toggle is the head's organization setting.
	var toggle := dialog.find_child("OfficeDutyAI", true, false) as CheckButton
	var before_ai := bool(team.offices.duty_ai)
	toggle.button_pressed = not before_ai
	assert(bool(team.offices.duty_ai) != before_ai, "Head toggles duty AI from the page")
	dialog.queue_free()
	await process_frame

	# A non-head member only views.
	data.site.controlled_person_id = coach
	dialog = _open_page(lab)
	var apply := dialog.find_child("OfficeApply", true, false) as Button
	assert(apply.disabled and (dialog.find_child("OfficeAppoint", true, false) as Button).disabled, "Non-head cannot edit")
	assert(_text(dialog, "OfficeNote").contains("僅能查看"))
	dialog.queue_free()
	await process_frame

	# Nation: legacy record shows read-only; after the head is set it is edited here.
	data.site.equipment_nations = {"n1": {"military_head": coach, "members": [captain, coach], "standards": {}}}
	data.site.controlled_person_id = captain
	dialog = _open_page(lab)
	_choose_index(dialog, 1)
	assert((dialog.find_child("OfficeApply", true, false) as Button).disabled and _text(dialog, "OfficeNote").contains("舊國別"), "Legacy nation is read-only")
	dialog.queue_free()
	await process_frame
	assert(lab.site_controller.equipment_orders.appoint_nation_head("n1", captain).ok)
	dialog = _open_page(lab)
	_choose_index(dialog, 1)
	seats = dialog.find_child("OfficePositions", true, false) as ItemList
	# Its two seats keep their holders and duties; every other catalog duty gains
	# its own vacant seat on migration (the head acts for it, plan 3.2).
	assert(seats.item_count == 2 + SiteOffices.duty_ids("nation").size() - 1 - SiteOffices.LEGACY_NATION_DUTIES.size(), "Migrated legacy nation keeps its two seats plus vacant later-duty seats")
	_pick(seats, "元首")
	(dialog.find_child("OfficeName", true, false) as LineEdit).text = "國王"
	_click(dialog, "OfficeRename")
	_click(dialog, "OfficeApply")
	assert(SiteOffices.head_position(data.site.equipment_nations.n1.offices).name == "國王")
	assert(SiteEquipmentOrders.military_head(data.site.equipment_nations.n1) == coach, "Equipment duties stay with the original military head")
	dialog.queue_free()
	await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_OFFICES_UI_PASS: formal entry, acting display, appoint/apply, live rule check, reject keeps state, rename/add, duty AI toggle, non-head view, legacy and migrated nation")
	quit(0)

func _choose_index(dialog: Window, index: int) -> void:
	var choice := dialog.find_child("OfficeOrg", true, false) as OptionButton
	assert(choice.item_count > index, "Org missing")
	choice.select(index)
	choice.item_selected.emit(index)
