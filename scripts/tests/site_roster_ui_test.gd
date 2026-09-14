extends "res://scripts/tests/site_workflow_test.gd"

func _run() -> void:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	var data := _fixture()
	lab.bind_terrain(data)
	var controller: SiteController = lab.site_controller
	controller._auto_save_blocked = true
	controller.release_worker()
	var positions: Array[Vector2i] = []
	for y: int in range(5, 15):
		for x: int in range(5, data.size.x - 5):
			var cell := Vector2i(x, y)
			if positions.size() < 100 and data.is_walkable(cell) and not lab.character.occupies_cell(cell) and not lab.npc.occupies_cell(cell):
				positions.append(cell)
	assert(positions.size() == 100, "Use original natural legal cells, not unsaved flattened terrain")
	var source: TerrainArmy = lab.army
	var target: TerrainArmy = lab.opposing_army
	assert(source.deploy_at(data, lab.character, lab.npc, positions) and source.enable_combat(false))
	controller.initialize_team_items(source)
	data.site.controlled_person_id = source.combat_identity(source.current_commander)
	var originals := {}
	for index: int in range(1, 4):
		var row: Dictionary = source.combat_units[index]
		originals[source.combat_identity(index)] = {"body": row, "cargo": row.cargo, "holder": row.item_state, "cell": source.cells[index]}
	controller._open_roster()
	var dialog := lab.get_node("SiteUI/RosterDialog") as AcceptDialog
	var members := dialog.find_child("RosterMembers", true, false) as ItemList
	assert(members.item_count == 100)
	for index: int in range(1, 4):
		members.select(index, false)
	(dialog.find_child("AssignRosterWorkers", true, false) as Button).pressed.emit()
	assert(controller.work_team.active_ids().size() == 3)
	(dialog.find_child("CancelRosterWorkers", true, false) as Button).pressed.emit()
	assert(controller.work_team.active_ids().is_empty())
	(dialog.find_child("TransferRosterMembers", true, false) as Button).pressed.emit()
	assert(source.combat_units.size() == 97 and target.combat_units.size() == 3)
	for identity: int in originals:
		var index := target.index_for_identity(identity)
		assert(index >= 0 and source.index_for_identity(identity) == -1)
		assert(is_same(target.combat_units[index], originals[identity].body))
		assert(is_same(target.combat_units[index].cargo, originals[identity].cargo))
		assert(is_same(target.combat_units[index].item_state, originals[identity].holder))
		assert(target.cells[index] == originals[identity].cell)
	# Stale list metadata cannot command another team's moved people.
	(dialog.find_child("AssignRosterWorkers", true, false) as Button).pressed.emit()
	assert(controller.work_team.active_ids().is_empty())
	dialog.free()
	controller._open_roster()
	dialog = lab.get_node("SiteUI/RosterDialog") as AcceptDialog
	members = dialog.find_child("RosterMembers", true, false) as ItemList
	assert(members.item_count == 97)
	(dialog.find_child("MergeRosterTeam", true, false) as Button).pressed.emit()
	assert(source.combat_units.size() == 97 and target.combat_units.size() == 3, "No implicit receiving-commander authority")
	(dialog.find_child("ReceiverCommanderConfirmation", true, false) as CheckButton).button_pressed = true
	# Only the confirmation-identity race is injected here; actual command
	# succession/death is covered by the original command contracts.
	var original_commander := target.current_commander
	target.current_commander = (original_commander + 1) % target.combat_units.size()
	(dialog.find_child("MergeRosterTeam", true, false) as Button).pressed.emit()
	assert(source.combat_units.size() == 97 and target.combat_units.size() == 3, "A replaced commander never inherits an earlier UI consent")
	target.current_commander = original_commander
	(dialog.find_child("ReceiverCommanderConfirmation", true, false) as CheckButton).button_pressed = true
	(dialog.find_child("MergeRosterTeam", true, false) as Button).pressed.emit()
	assert(not source.has_army() and target.combat_units.size() == 100)
	assert(lab.player_army() == target, "Controlled original row follows membership, not old array index")
	for identity: int in originals:
		assert(is_same(target.combat_units[target.index_for_identity(identity)], originals[identity].body))
	controller._capture_positions()
	var saved := Store.save(data, "user://roster-ui/original.json")
	assert(saved.ok, str(saved))
	var loaded := Store.load_site("user://roster-ui/original.json")
	assert(loaded.ok, str(loaded))
	lab.bind_terrain(loaded.data)
	assert(lab.player_army().combat_units.size() == 100)
	print("SITE_ROSTER_UI_PASS actual multi-select workers, original split/merge rows and cargo, stale list rejection, receiving-commander confirmation, controlled identity and canonical save/load")
	lab.free()
	quit()
