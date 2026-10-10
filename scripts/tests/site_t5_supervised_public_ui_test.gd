extends "res://scripts/tests/site_t5_captive_production_test.gd"
## True original capture/learned work and original Window buttons. The parent
## PA/Fatigue component interval is explicit; not whole Lab/Native clock proof.
const SupervisedWindow = preload("res://scripts/terrain_lab/site_tech_window.gd")

func _select_supervised(choice: OptionButton, field: String, value: Variant) -> void:
	for index: int in range(1, choice.item_count):
		if choice.get_item_metadata(index).get(field) == value:
			choice.select(index)
			choice.item_selected.emit(index)
			return
	assert(false, "Original explicit choice not found: " + str(value))

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void: quit(1))
	var data = _building_fixture()
	var lab = _building_lab(data)
	lab.restore_only = true
	_learn_original_npc(lab)
	_capture_original(lab)
	var controller = lab.site_controller
	var actions = controller.person_actions
	# T5 is a true original custody operation; it must remain visible without
	# a family registry. The skill above came from three actual original bows.
	var family: Dictionary = data.site.family
	data.site.erase("family")
	var column = VBoxContainer.new()
	root.add_child(column)
	var window = SupervisedWindow.new()
	var before = var_to_bytes([data.site, actions._jobs, lab.character.capture_state(), lab.npc.capture_state()])
	window.install(controller, column)
	assert(var_to_bytes([data.site, actions._jobs, lab.character.capture_state(), lab.npc.capture_state()]) == before)
	assert(window._supervised_form.captive.selected == 0 and window._supervised_form.supervisor.selected == 0)
	assert(window._supervised_form.begin_captive.disabled and window._supervised_form.begin_analysis.disabled)
	window._supervised_form.begin_captive.pressed.emit() # Forced incomplete UI input still does nothing.
	assert(var_to_bytes([data.site, actions._jobs, lab.character.capture_state(), lab.npc.capture_state()]) == before)
	_select_supervised(window._supervised_form.captive, "person_id", lab.npc.person_id)
	assert(window._supervised_form.supervisor.selected == 0 and window._supervised_form.begin_captive.disabled, "No guard is automatically selected")
	_select_supervised(window._supervised_form.supervisor, "person_id", lab.character.person_id)
	assert(not window._supervised_form.begin_captive.disabled and var_to_bytes([data.site, actions._jobs, lab.character.capture_state(), lab.npc.capture_state()]) == before, "Real choices only query original owners")
	var relation: Dictionary = data.site.captivity[str(lab.npc.person_id)]
	data.site.captivity[str(lab.npc.person_id)] = relation.duplicate(true)
	before = var_to_bytes([data.site, actions._jobs])
	window._supervised_form.begin_captive.pressed.emit()
	assert(var_to_bytes([data.site, actions._jobs]) == before, "Equal replacement custody cannot authorize held original UI selections")
	data.site.captivity[str(lab.npc.person_id)] = relation
	window.refresh()
	_select_supervised(window._supervised_form.captive, "person_id", lab.npc.person_id)
	_select_supervised(window._supervised_form.supervisor, "person_id", lab.character.person_id)
	var stock: Dictionary = data.site.inventory.duplicate()
	var bows = _bows(data)
	window._supervised_form.begin_captive.pressed.emit()
	assert(actions.is_busy(lab.character.person_id) and actions.is_busy(lab.npc.person_id) and lab.npc.captive)
	assert(data.site.inventory == stock and str(actions.save_guard().code) == "BUSY")
	assert(not window._supervised_form.stop_captive.disabled)
	window._supervised_form.stop_captive.pressed.emit()
	assert(not actions.is_busy(lab.character.person_id) and not actions.is_busy(lab.npc.person_id) and lab.npc.captive and data.site.inventory == stock)
	window._supervised_form.begin_captive.pressed.emit()
	assert(actions.is_busy(lab.npc.person_id) and is_equal_approx(float(actions.job_for(lab.npc.person_id).duration), 108.0))
	_plan_step(lab, 108.0)
	var completed = actions.settle_after_contacts()
	assert(completed.size() == 1 and completed[0].ok and _bows(data) == bows + 1)
	assert(int(data.site.inventory.wood) == int(stock.wood) - 4 and int(data.site.inventory.fiber) == int(stock.fiber) - 2)
	assert(lab.npc.captive and not lab.npc.can_act() and Technology.learned(lab.npc.technology, "F07"))
	assert(data.site.captivity[str(lab.npc.person_id)] == relation and actions.save_guard().ok)
	assert(not data.site.has("family"), "Opening/submitting supervised UI never manufactures family registration")
	data.site.family = family
	before = var_to_bytes([data.site, actions._jobs])
	window.context_changed()
	window._supervised_form.begin_captive.pressed.emit()
	assert(var_to_bytes([data.site, actions._jobs]) == before, "Cleared original context cannot submit an old operator")
	column.free()
	lab.free()
	print("SITE_T5_SUPERVISED_PUBLIC_UI_PASS original learned three bows/capture/current guard, explicit two choices/no family, stale equal custody and forced empty input refusal, original stop/busy/joint108/cost4-2/one bow/captive retained; PA component clock only")
	quit(0)
