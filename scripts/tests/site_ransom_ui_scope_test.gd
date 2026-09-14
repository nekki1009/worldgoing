extends "res://scripts/tests/site_captivity_supply_test.gd"
## Real Controller child-window scope, using the existing original-row custody
## fixture. Capture animation and successful timed ransom have separate tests.

func _click(parent: Node, name: String) -> void:
	var button := parent.find_child(name, true, false) as Button
	assert(button != null and not button.disabled, "Missing original UI button: " + name)
	button.pressed.emit()

func _ransom_dialog(lab: TerrainLab, target_id: int, representative_id: int) -> AcceptDialog:
	var controller: SiteController = lab.site_controller
	controller.select_cell(lab._combat_target(target_id).cell)
	_click(controller.panel, "InspectLoot")
	var parent := lab.get_node("SiteUI/PersonInventoryDialog") as AcceptDialog
	var targets := parent.find_child("LootSource", true, false) as OptionButton
	var selected := false
	for index: int in range(targets.item_count):
		if targets.get_item_metadata(index) == {"kind": "person", "id": str(target_id)}:
			targets.select(index)
			targets.item_selected.emit(index)
			selected = true
	assert(selected)
	_click(parent, "BeginRansomDialog")
	var child := parent.get_node_or_null("RansomDialog") as AcceptDialog
	assert(child != null and child.visible and child.get_parent() == parent, "Ransom is a real exclusive child, not a competing root window")
	var representatives := child.find_child("RansomRepresentative", true, false) as OptionButton
	selected = false
	for index: int in range(1, representatives.item_count):
		if int(representatives.get_item_metadata(index)) == representative_id:
			representatives.select(index)
			selected = true
	assert(selected)
	return child

func _close_dialog(child: AcceptDialog) -> void:
	var parent := child.get_parent() as AcceptDialog
	parent.hide()
	parent.free()

func _run() -> void:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	var data := _fixture()
	data.site.worker_enabled = false
	lab.bind_terrain(data)
	var controller: SiteController = lab.site_controller
	controller._auto_save_blocked = true
	lab.character.faction_id = 1
	lab.npc.faction_id = 2
	assert(lab.character.place(Vector2i(16, 30), true) and lab.npc.place(Vector2i(18, 30), true))
	var first: TerrainArmy = lab.army
	var second: TerrainArmy = lab.opposing_army
	for team: TerrainArmy in [first, second]:
		team.roster_size = 40
		var cells: Array[Vector2i] = []
		var origin := Vector2i(16, 16) if team == first else Vector2i(22, 24)
		for index: int in range(40):
			cells.append(origin + Vector2i(index % 8, floori(float(index) / 8.0)))
		cells[0] = Vector2i(21, 23) if team == first else Vector2i(22, 23)
		assert(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false))
		team.set_process(false)
		team.faction_id = 1 if team == first else 2
		team.settle_combat_command()
	data.site.army_next_team = 3
	var payer_id := first.combat_identity(first.current_commander)
	var representative_id := second.combat_identity(second.current_commander)
	var captive: Dictionary = first.combat_units[1]
	var target_id := int(captive.person_id)
	captive.ko = 100.0
	# Reuse the established supply fixture's synchronous original relationship
	# commit, without pretending this UI-only test verifies the capture animation.
	var helper: Variant = controller.captivity_supply
	assert(helper.change_guard(target_id, representative_id, true).ok)
	_bind(helper, data, captive, representative_id, second.faction_id, true)
	var source: Dictionary = controller._supply_entry(first)
	var destination: Dictionary = controller._supply_entry(second)
	source.inventory.grain = 100 # Explicit original-team fixture stock, not private cargo.
	assert(helper.ransom_exchange_query(payer_id, target_id, representative_id).ok)
	# Only fixture control selection uses this callback; no living-family switch
	# is being claimed as a production inheritance action.
	assert(controller._control_family_person(null, payer_id).ok)
	var relation: Dictionary = data.site.captivity[str(target_id)]
	var relation_before := relation.duplicate(true)
	var captive_before := captive.duplicate(true)
	var source_before := source.duplicate(true)
	var destination_before := destination.duplicate(true)
	var source_inventory: Dictionary = source.inventory
	var destination_inventory: Dictionary = destination.inventory
	var alternative_id := first.combat_identity(2)
	for changed: String in ["control", "payer", "terrain"]:
		var child := _ransom_dialog(lab, target_id, representative_id)
		match changed:
			"control": data.site.controlled_person_id = alternative_id
			"payer": controller.person_executor_id = alternative_id
			"terrain":
				# Exact context-pointer fault injection only: do not bind or advance
				# another world. The UI must reject before resolving any of its data.
				var replacement := TerrainData.new()
				replacement.site = data.site.duplicate(true)
				lab.terrain = replacement
		_click(child, "BeginRansom")
		assert(controller.message.text.begins_with("STALE"), changed + ": " + controller.message.text)
		lab.terrain = data
		data.site.controlled_person_id = payer_id
		controller.person_executor_id = payer_id
		assert(controller.person_actions.save_guard().ok and controller.person_actions._jobs.is_empty())
		assert(source == source_before and destination == destination_before and captive == captive_before)
		assert(relation == relation_before and is_same(data.site.captivity[str(target_id)], relation))
		assert(is_same(source.inventory, source_inventory) and is_same(destination.inventory, destination_inventory))
		_close_dialog(child)
	# The valid original form still starts the real 10-game-second/100-ration job;
	# cancelling through the original button returns no food and releases no one.
	var valid := _ransom_dialog(lab, target_id, representative_id)
	_click(valid, "BeginRansom")
	var job: Dictionary = controller.person_actions.job_for(payer_id)
	assert(not job.is_empty(), controller.message.text)
	assert(job.kind == "ransom" and float(job.duration) == 10.0 and float(job.elapsed) == 0.0)
	assert(job.resources == {"grain": 100} and int(job.target_id) == target_id and int(job.representative_id) == representative_id)
	assert(source == source_before and destination == destination_before and captive == captive_before and relation == relation_before)
	_close_dialog(valid)
	_click(controller.panel, "CancelPersonAction")
	assert(controller.person_actions.save_guard().ok and controller.person_actions._jobs.is_empty())
	assert(source == source_before and destination == destination_before and captive == captive_before and relation == relation_before)
	assert(Runtime.now(data) == 0.0 and data.site.manual.cargo.is_empty() and data.site.worker.cargo.is_empty())
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE RANSOM UI SCOPE PASS: real child window, stale controlled person/payer/TerrainData rejected before jobs or food, original 10-second/100-ration start/cancel, unchanged captive and original team inventories; no timed completion or capture-animation claim")
	quit(0)
