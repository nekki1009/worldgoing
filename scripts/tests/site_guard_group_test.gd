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
	assert(lab.character.place(Vector2i(20, 20), true))
	var remote := data.spawn_cell
	for y: int in range(40, data.size.y - 5):
		for x: int in range(40, data.size.x - 5):
			if data.is_walkable(Vector2i(x, y)):
				remote = Vector2i(x, y)
				break
		if remote.y >= 40:
			break
	assert(remote.y >= 40 and lab.npc.place(remote, true))
	var positions: Array[Vector2i] = []
	for y: int in range(5, 15):
		for x: int in range(5, data.size.x - 5):
			var cell := Vector2i(x, y)
			if positions.size() < 100 and data.is_walkable(cell):
				positions.append(cell)
	assert(positions.size() == 100)
	for index: int in range(1, 5):
		positions[index] = [Vector2i(19, 20), Vector2i(18, 20), Vector2i(19, 21), Vector2i(18, 21)][index - 1]
	var team: TerrainArmy = lab.opposing_army
	assert(team.deploy_at(data, lab.character, lab.npc, positions) and team.enable_combat(false))
	controller.initialize_team_items(team)
	var originals := {}
	for index: int in range(1, 5):
		var identity := team.combat_identity(index)
		var row: Dictionary = team.combat_units[index]
		row.captive = true
		data.site.captivity[str(identity)] = {"version": 1, "captor_id": lab.character.person_id,
			"guard_id": lab.character.person_id, "captor_faction": lab.character.faction_id, "sealed_container": ""}
		originals[identity] = {"body": row, "holder": row.item_state, "cargo": row.cargo,
			"items": row.item_state.duplicate(true), "hp": row.hp}
		assert(controller.person_actions.has_effective_guard(identity))
	assert(controller.captive_escort.begin(lab.character.person_id, lab.character.person_id, Vector2i(24, 20)).ok)
	var starts: Array[Vector2i] = team.cells.duplicate()
	for frame: int in range(240):
		var before: Array[Vector2i] = team.cells.duplicate()
		lab._process(0.05)
		for index: int in range(1, 5):
			var identity := team.combat_identity(index)
			assert(before[index] == team.cells[index] or data.can_step(before[index], team.cells[index]))
			assert(controller.person_actions.has_effective_guard(identity))
			assert(is_same(team.combat_units[index], originals[identity].body))
			assert(is_same(team.combat_units[index].cargo, originals[identity].cargo))
			assert(is_same(team.combat_units[index].item_state, originals[identity].holder))
			assert(team.combat_units[index].item_state == originals[identity].items and team.combat_units[index].hp == originals[identity].hp)
		if data.site.escort_orders.is_empty() and not lab.character.is_moving() and team.moving_count() == 0:
			break
	assert(lab.character.terrain_cell == Vector2i(24, 20) and data.site.escort_orders.is_empty(), "Four captives must follow through original legal steps")
	for index: int in range(1, 5):
		assert(team.cells[index] != starts[index])
	# The original guard becomes autonomous when control selects another original
	# person. Guard work reaches 80 once and loses effective watch until rested.
	data.site.controlled_person_id = lab.npc.person_id
	lab.character.fatigue = 79.999
	lab.character.fatigue_rest = 0.0
	lab.character.work_resting = false
	var effort: Dictionary = controller.advance_guard_work(20.0)
	assert(float(effort.get(lab.character.person_id, 0.0)) > 0.0 and float(effort[lab.character.person_id]) < 1.0)
	assert(is_equal_approx(lab.character.fatigue, 80.0) and lab.character.work_resting)
	for identity: int in originals:
		assert(not controller.person_actions.has_effective_guard(identity))
	var unchanged := lab.character.fatigue
	assert(controller.advance_guard_work(20.0).is_empty())
	assert(lab.character.fatigue == unchanged, "Resting guard is not charged another work interval")
	# Exact boundary fixture: recovery itself is covered by common fatigue tests.
	lab.character.fatigue = 50.0
	assert(controller.advance_guard_work(1.0).has(lab.character.person_id))
	assert(not lab.character.work_resting)
	for identity: int in originals:
		assert(controller.person_actions.has_effective_guard(identity))
	data.site.controlled_person_id = lab.character.person_id
	lab.character.fatigue = 99.0
	assert(is_equal_approx(float(controller.advance_guard_work(20.0)[lab.character.person_id]), 20.0))
	assert(not lab.character.work_resting and lab.character.fatigue > 99.0)
	print("SITE_GUARD_GROUP_PASS four original captive rows, actual common-clock escort and legal occupancy, unchanged body/cargo/items, original guard work 80/50 and controlled-person exemption")
	lab.free()
	quit()
