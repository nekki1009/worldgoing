extends "res://scripts/tests/site_prison_roster_query_test.gd"

const PRISON_UI_OUTPUT := "res://output/site_building_implementation_20261003/prison_ui/"
var _prison_ui_captures: Array[Dictionary] = []

func _capture_prison_window(dialog: Window, label: String, bottom: bool = false) -> void:
	if DisplayServer.get_name() == "headless": return
	assert(DirAccess.make_dir_recursive_absolute(PRISON_UI_OUTPUT) == OK)
	var scroll := dialog.get_child(0) as ScrollContainer
	assert(scroll != null)
	scroll.scroll_vertical = 10000 if bottom else 0
	for _frame: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var picture := dialog.get_texture().get_image()
	assert(not picture.is_empty() and picture.save_png(PRISON_UI_OUTPUT + label + ".png") == OK)
	_prison_ui_captures.append({"file": label + ".png", "case": "actual original prison window",
		"counts": (dialog.find_child("PrisonStatus", true, false) as Label).text,
		"officer_details": (dialog.find_child("PrisonOfficerDetails", true, false) as Label).text,
		"action": (dialog.find_child("PrisonActionStatus", true, false) as Label).text})

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var prison_key := _formal_feature(data, "prison", Vector2i(35, 35), Vector2i(3, 4))
	var layout := Runtime.prison_layout(data, prison_key)
	assert(layout.slots.size() == 6)
	var deployed := lab.deploy_trial_armies([{"faction": 2, "count": 4, "female_percent": 0,
		"attack": false, "ai_enabled": false, "spawn": Vector2i(20, 30)}])
	assert(deployed.ok, str(deployed))
	var team: TerrainArmy = lab.army
	team.set_process(false)
	team.formal_commander = 0
	team.acting_commander = -1
	team.current_commander = 0
	team.officer_service.assign([0])
	team.officer_order.assign([0])
	team.command_abilities[0] = {"tactics": 71, "leadership": 62, "coach": 53}
	var guard: TerrainTestCharacter = lab.character
	var slots := [1, 0, 4]
	for index: int in range(4):
		var identity := team.combat_identity(index)
		var captor: int = guard.person_id if index < slots.size() else lab.npc.person_id
		var supply := controller.captivity_supply.change_guard(identity, captor, true)
		assert(supply.ok, str(supply))
		team.combat_hot_set(index, &"captive", true)
		if index < slots.size(): team.cells[index] = layout.slots[slots[index]].cell
		data.site.captivity[str(identity)] = _relation(prison_key if index < slots.size() else "", captor)
		controller.captivity_supply.commit_change(identity, captor, true)
	data.site.escort_orders[str(lab.npc.person_id)] = {"version": 2, "kind": "prison", "prison_id": prison_key,
		"destination": data.index(layout.entry), "captives": [team.combat_identity(3)],
		"targets": {str(team.combat_identity(3)): data.index(layout.slots[5].cell)}}
	controller.feature_key = prison_key
	controller.person_executor_id = guard.person_id
	controller._open_prison()
	var dialog: Window = controller._ui_dialogs.prison.dialog
	var choices := dialog.find_child("PrisonInmates", true, false) as OptionButton
	var status := dialog.find_child("PrisonStatus", true, false) as Label
	var regular := dialog.find_child("PrisonRegularCount", true, false) as Label
	var detail := dialog.find_child("PrisonOfficerDetails", true, false) as Label
	var activity := dialog.find_child("PrisonActionStatus", true, false) as Label
	assert(choices.item_count == 1 and int(choices.get_item_metadata(0)) == team.combat_identity(0))
	assert(status.text.contains("軍官 1 · 一般俘虜 2 · 已用 3／共用容量 6"), status.text)
	assert(status.text.contains("押送預留：軍官 0 · 一般 1"), status.text)
	assert(regular.text.begins_with("一般俘虜：2 人") and not regular.text.contains("#"))
	assert(detail.text.contains("戰術 71／領導 62／教練 53") and detail.text.contains("原外觀："), detail.text)
	assert(actions.job_for(guard.person_id).is_empty())
	await _capture_prison_window(dialog, "prison_roles_top")
	await _capture_prison_window(dialog, "prison_roles_actions", true)
	# A distant ordinary person is never picked merely because it appears first.
	assert(guard.place(Vector2i(30, 30), true))
	_press(lab, "ReleaseRegularPrisoner")
	assert(actions.job_for(guard.person_id).is_empty() and activity.text.contains("出監接觸格"), activity.text)
	await _capture_prison_window(dialog, "prison_release_unreachable", true)
	assert(guard.place(layout.slots[4].contact_cell, true))
	var near_id := team.combat_identity(2)
	var far_id := team.combat_identity(1)
	var hp := float(team.combat_hot_get(2, &"hp"))
	var cargo: Dictionary = team.combat_units[2].cargo.duplicate(true)
	_press(lab, "ReleaseRegularPrisoner")
	var job := actions.job_for(guard.person_id)
	assert(str(job.kind) == "prison_release" and int(job.target_id) == near_id and float(job.duration) == 4.0, str(job))
	assert(data.site.captivity.has(str(near_id)) and data.site.captivity.has(str(far_id)))
	actions.advance(2.0)
	assert(actions.settle_after_contacts().is_empty() and data.site.captivity.has(str(near_id)))
	_press(lab, "RefreshPrison")
	assert(activity.text.contains("2.0／4.0 秒") and regular.text.begins_with("一般俘虜：2 人"), activity.text)
	await _capture_prison_window(dialog, "prison_release_in_progress", true)
	actions.advance(2.0)
	var settled := actions.settle_after_contacts()
	assert(settled.size() == 1 and settled[0].ok, str(settled))
	assert(not data.site.captivity.has(str(near_id)) and data.site.captivity.has(str(far_id)))
	assert(float(team.combat_hot_get(2, &"hp")) == hp and team.combat_units[2].cargo == cargo)
	_press(lab, "RefreshPrison")
	assert(regular.text.begins_with("一般俘虜：1 人") and choices.item_count == 1, regular.text)
	assert(status.text.contains("已用 2／共用容量 6"), status.text)
	assert(actions.job_for(guard.person_id).is_empty(), "No automatic batch or next release job")
	await _capture_prison_window(dialog, "prison_after_one_release_top")
	await _capture_prison_window(dialog, "prison_after_one_release_actions", true)
	# Officer release uses the same original four-second job and current contact.
	assert(guard.place(layout.slots[1].contact_cell, true))
	_press(lab, "ReleasePrisoner")
	assert(int(actions.job_for(guard.person_id).target_id) == team.combat_identity(0))
	assert(actions.cancel(guard.person_id).ok)
	assert(data.site.captivity.has(str(team.combat_identity(0))))
	var executor_before := controller.person_executor_id
	var control_before := lab.controlled_person_id()
	_press(lab, "FocusPrisonOfficer")
	assert(not dialog.visible and controller.person_executor_id == executor_before and lab.controlled_person_id() == control_before)
	assert(actions.job_for(guard.person_id).is_empty(), "Appearance lookup only changes camera focus")
	if DisplayServer.get_name() != "headless":
		assert(_prison_ui_captures.size() == 6)
		var report := FileAccess.open(PRISON_UI_OUTPUT + "summary.json", FileAccess.WRITE)
		assert(report != null)
		report.store_string(JSON.stringify({"status": "SITE_PRISON_UI_PASS", "captures": _prison_ui_captures,
			"limits": "Original prison UI with one officer, two ordinary inmates and one ordinary reservation; one timed release. No aggregate storage, new renderer, automated batch release or scaled performance proof."}, "\t"))
		report.close()
	print("SITE_PRISON_UI_PASS officer-only roster, original abilities/appearance, shared count/capacity, reserved classes, contact-selected ordinary person, four-second single release, no batch, original officer release and camera-only focus")
	lab.free()
	quit()
