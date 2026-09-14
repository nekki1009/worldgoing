extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "officer-service-fixture")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	var selected: Array[Vector2i] = []
	for index in range(100):
		selected.append(Vector2i(10 + index % 10, 10 + floori(float(index) / 10)))
	assert(team.deploy_at(data, null, null, selected) and team.enable_combat(false))
	assert(team.record_officer_service([3, 1], true).ok)
	assert(team.officer_service == [1, 3] and team.officer_order == [1, 3], "Simultaneous appointments use stable IDs")
	assert(team.record_officer_service([2], true).ok)
	assert(team.officer_service == [1, 3, 2])
	assert(team.reorder_officers(0, [2, 1, 3]).ok)
	assert(team.record_officer_service([5, 4], true).ok)
	assert(team.officer_order == [2, 1, 3, 4, 5] and team.officer_service == [1, 3, 2, 4, 5])
	var abilities: Dictionary = team.command_abilities[1].duplicate()
	assert(team.record_officer_service([1], false).ok and team.record_officer_service([1], true).ok)
	assert(team.officer_order == [2, 3, 4, 5, 1] and team.command_abilities[1] == abilities)
	var before := team.officer_service.duplicate()
	assert(not team.record_officer_service([6, 6], true).ok and team.officer_service == before)
	team.apply_unit_contact(3, {"result": {"hp": 1.0, "stun": 110.0, "guard_break": false}, "shield": false})
	team.settle_combat_command()
	assert(team.officer_service == before, "Temporary KO preserves the current service period")
	var saved := JSON.parse_string(JSON.stringify(team.capture_combat_state())) as Dictionary
	assert(TerrainArmy.valid_combat_state(saved, data))
	var corrupt := saved.duplicate(true)
	corrupt.officer_service.append(1)
	assert(not TerrainArmy.valid_combat_state(corrupt, data))
	team.restore_combat_state(saved, data, null, null)
	assert(team.officer_service == before and team.officer_order == [2, 3, 4, 5, 1])
	saved.erase("officer_service")
	assert(TerrainArmy.valid_combat_state(saved, data))
	team.restore_combat_state(saved, data, null, null)
	assert(team.officer_service == team.officer_order, "Older ranking becomes a single fixed chronology fallback")
	team.apply_unit_contact(3, {"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
	team.settle_combat_command()
	assert(not team.officer_order.has(3) and not team.officer_service.has(3))
	team.clear()
	team.queue_free()
	await process_frame
	print("SITE OFFICER SERVICE PASS: stable event order, append missing ranks, preserve edits/KO, revoke/reappoint, retained abilities, save/legacy/corruption")
	quit(0)
