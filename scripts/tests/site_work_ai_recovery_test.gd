extends "res://scripts/tests/site_work_team_clock_test.gd"
## Explicit boundary setup; subsequent 80 -> 50 recovery is all original clock.
const OUT := "res://output/npc_ai_acceptance_20260918/work"

func _run() -> void:
	deadline = Time.get_ticks_msec() + 45000
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	var controller: SiteController = lab.site_controller
	controller._auto_save_blocked = true
	var fixture := _work_fixture()
	var data: TerrainData = fixture.data
	lab.bind_terrain(data)
	lab.npc.faction_id = lab.character.faction_id # Isolated fixture, not main proof.
	var team := lab.army
	team.roster_size = 3
	var positions: Array[Vector2i] = []
	positions.assign(fixture.cells)
	assert(team.deploy_at(data, lab.character, lab.npc, positions) and team.enable_combat(false))
	team.set_process(false)
	team.faction_id = lab.character.faction_id
	team.settle_combat_command()
	assert(controller._control_family_person(null, team.combat_identity(team.current_commander)).ok)
	var identities: Array[int] = [team.combat_identity(1), team.combat_identity(2)]
	for identity: int in identities:
		lab.selected_army_target = identity
		_press(controller, "AssignSelectedWorker")
		assert(controller.work_team.is_assigned(identity))
	var first: Dictionary = team.combat_units[1]
	var original_cargo: Dictionary = first.cargo
	# The only initial-state injection: begin at the threshold. Never directly
	# lower fatigue, clear resting or advance a second worker clock afterward.
	PersonFatigue.write(first, "fatigue", 79.999)
	lab.change_simulation_speed(1)
	lab.change_simulation_speed(1)
	assert(lab.simulation_speed == 4.0)
	lab._process(0.1)
	assert(first.work_resting and first.work_task.mode == "rest")
	var rest_progress := float(first.work_task.progress)
	var initial_fatigue := PersonFatigue.read(first)
	assert(is_equal_approx(initial_fatigue, 80.0))
	var rested_frames := 0
	var previous_fatigue := initial_fatigue
	for frame in range(1000):
		lab._process(0.05)
		rested_frames += 1
		var fatigue := PersonFatigue.read(first)
		if not bool(first.work_resting): break
		assert(fatigue <= previous_fatigue + 0.000001 and fatigue > 50.0, "Safe original rest must monotonically recover before threshold")
		assert(float(first.work_task.progress) == rest_progress and is_same(first.cargo, original_cargo))
		previous_fatigue = fatigue
		if frame % 100 == 0: await process_frame
	assert(not first.work_resting and PersonFatigue.read(first) <= 50.05 and float(first.work_task.progress) > rest_progress, "Same original work order must naturally resume after actual 80-to-50 recovery")
	var item := str(Env.ITEMS[int(fixture.kind)])
	var depot_before := int(data.site.inventory.get(item, 0))
	var cargo_seen := false
	for frame in range(400):
		lab._process(0.05)
		cargo_seen = cargo_seen or int(first.cargo.get(item, 0)) > 0
		if cargo_seen: break
	assert(cargo_seen)
	# Cancel/assign original UI command with the genuine captain identity in
	# this declared control-binding fixture; reject without captain authority
	# in the original clock test, not by changing the formal scene's player.
	assert(Runtime.inventory_size(first.cargo) > 0)
	var cargo_before: Dictionary = first.cargo.duplicate(true)
	lab.selected_army_target = identities[0]
	_press(controller, "CancelSelectedWorker")
	assert(not controller.work_team.is_assigned(identities[0]) and first.work_task.is_empty())
	for frame in range(20): lab._process(0.05)
	assert(first.cargo == cargo_before and is_same(first.cargo, original_cargo))
	var stock_on_resume := int(data.site.inventory.get(item, 0))
	_press(controller, "AssignSelectedWorker")
	assert(controller.work_team.is_assigned(identities[0]))
	for frame in range(300):
		lab._process(0.05)
		if first.cargo.is_empty(): break
	assert(first.cargo.is_empty() and int(data.site.inventory.get(item, 0)) >= stock_on_resume + int(cargo_before[item]))
	assert(int(data.site.inventory.get(item, 0)) > depot_before)
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	var report := {"fixture_boundary_not_formal_map": true, "initial_fatigue": 79.999, "stopped_at": initial_fatigue,
		"resumed_below": 50.05, "recovery_action_seconds": rested_frames * 0.05, "simulation_speed": 4,
		"original_clock_only_after_initial_boundary": true, "resumed_harvest_and_deposit": true,
		"actual_cancel_assign_controls": true, "canceled_cargo_preserved_then_deposited": cargo_before}
	var file := FileAccess.open(OUT + "/recovery_result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SITE_WORK_AI_RECOVERY_PASS ", JSON.stringify(report))
	lab.queue_free()
	await process_frame
	quit(0)
