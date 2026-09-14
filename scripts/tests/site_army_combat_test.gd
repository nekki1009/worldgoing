extends SceneTree

const Store = preload("res://scripts/terrain_lab/site_store.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "army-combat-fixture")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	var lab := TerrainLab.new()
	lab.terrain = data
	var teams: Array[TerrainArmy] = [TerrainArmy.new(), TerrainArmy.new()]
	lab.combat_armies.assign(teams)
	for team_index in range(2):
		var team := teams[team_index]
		root.add_child(team)
		team.set_process(false)
		team.team_id = team_index + 1
		team.faction_id = team_index
		var selected: Array[Vector2i] = []
		for index in range(100):
			selected.append(Vector2i(10 + team_index * 30 + index % 10, 40 + floori(float(index) / 10)))
		selected[1] = Vector2i(20 + team_index, 20)
		assert(team.deploy_at(data, null, null, selected))
		assert(team.enable_combat(false))
		assert(team.get_child_count() == 0, "Headless soldiers are rows, not actor Nodes")
		team.contact_query = lab._collect_unit_contacts
		team.combat_target_query = lab._combat_target
		team.contact_sink = func(packet: Dictionary) -> void: lab._combat_contacts.append(packet)
		team.external_blocker = teams[1 - team_index].blocks_cell
	var a := teams[0]
	var b := teams[1]
	a.facing[1] = Vector2i.RIGHT
	b.facing[1] = Vector2i.LEFT
	assert(a.combat_units.size() == 100 and b.combat_units.size() == 100)
	assert(a.combat_identity(1) != b.combat_identity(1))
	for pose: Dictionary in preload("res://scripts/tests/site_army_contact_source_test.gd").load_reference_poses():
		for kind: String in ["body", "shield"]:
			for shape: PackedVector2Array in pose[kind]:
				for point: Vector2 in shape:
					assert(absf(point.x) < 224.0 and absf(point.y) < 224.0, "Broad phase must contain every baked hurtbox plus stance")
	# Collision follows exact time even when presentation stays on one atlas tile.
	a.combat_units[1].pose = "walk_slash"
	a.combat_units[1].age = 0.513
	var tile := a.combat_frame(1)
	var first := a.combat_shapes(1, "weapon")
	a.combat_units[1].age = 0.517
	assert(a.combat_frame(1) == tile)
	var second := a.combat_shapes(1, "weapon")
	assert(first != second, "Ordinary collision must not snap to atlas time")
	a.combat_units[1].pose = "idle"
	a.combat_units[1].age = 0.0
	assert(a.start_unit_attack(1, b.cells[1], b.combat_identity(1)))
	var saved := JSON.parse_string(JSON.stringify(a.capture_combat_state())) as Dictionary
	assert(TerrainArmy.valid_combat_state(saved, data))
	assert(saved.units[1].aim.size() == 2)
	var frozen_aim: Array = a.combat_units[1].aim.duplicate()
	var malformed := saved.duplicate(true)
	malformed.units[1].aim = [0, "not a coordinate"]
	assert(not TerrainArmy.valid_combat_state(malformed, data))
	a.restore_combat_state(saved, data, null, null)
	var restored_aim: Array = a.combat_units[1].aim
	assert(Vector2(restored_aim[0], restored_aim[1]).distance_to(Vector2(frozen_aim[0], frozen_aim[1])) < 0.001, "JSON coordinates retain subpixel aim")
	frozen_aim = restored_aim.duplicate()
	assert(not a.start_unit_attack(1, b.cells[1]), "No recovery cancel")
	var packets := 0
	for tick in range(360):
		a.prepare_combat(1.0 / 120.0)
		b.prepare_combat(1.0 / 120.0)
		assert(a.combat_units[1].aim == frozen_aim, "Aim belongs to this swing, not a shared rig or target update")
		if tick % 30 == 0:
			var previous: Array[PackedVector2Array] = []
			previous.assign(a.combat_units[1].previous)
			var current := a.combat_shapes(1, "weapon")
			var filtered := lab._collect_army_contacts(previous, current, a.cells[1], a.combat_ground(1), a, 1)
			assert(filtered == unfiltered_contacts(lab, a, previous, current), "Pose bounds must preserve the full candidate result and order")
		a.sample_combat()
		packets += lab._combat_contacts.size()
		lab._resolve_combat_contacts()
		lab._combat_contacts.clear()
	assert(packets == 1 and a.combat_units[1].hits.has(b.combat_identity(1)), "Actual continuous swing must contact adjacent enemy exactly once; packets=%d" % packets)
	var enemy_hp := float(b.combat_units[1].hp)
	a.prepare_combat(1.0)
	b.faction_id = a.faction_id
	assert(a.start_unit_attack(1, b.cells[1]))
	for tick in range(360):
		a.prepare_combat(1.0 / 120.0)
		b.prepare_combat(1.0 / 120.0)
		a.sample_combat()
		assert(lab._combat_contacts.is_empty(), "Friendly melee cannot apply HP or stun")
	assert(a.combat_units[1].blocked and a.combat_units[1].status == "Ally obstructs melee")
	assert(float(b.combat_units[1].hp) == enemy_hp)
	var knockout := {"result": {"hp": 7.5, "stun": 110.0, "guard_break": false}, "shield": false}
	b.apply_unit_contact(1, knockout)
	assert(not b.combat_can_act(1) and not b.blocks_cell(b.cells[1]))
	assert(float(b.combat_units[1].hp) == enemy_hp - 7.5 and b.combat_units[1].pose == "down")
	b.external_blocker = func(cell: Vector2i) -> bool: return cell == b.cells[1]
	b.prepare_combat(31.0)
	assert(float(b.combat_units[1].ko) > 0.0, "Cannot stand inside an occupant")
	b.external_blocker = a.blocks_cell
	b.prepare_combat(0.2)
	assert(b.combat_units[1].pose == "get_up" and not b.combat_can_act(1) and b.blocks_cell(b.cells[1]))
	b.prepare_combat(2.3)
	assert(b.combat_can_act(1) and float(b.combat_units[1].hp) == enemy_hp - 7.5, "Wake never heals")
	var lethal := {"hp": 100.0, "stun": 0.0, "guard_break": false}
	lab._combat_contacts.assign([
		{"attacker": a, "attacker_unit": 1, "target": b, "target_unit": 1, "result": lethal, "shield": false, "fraction": 0.5},
		{"attacker": b, "attacker_unit": 1, "target": a, "target_unit": 1, "result": lethal, "shield": false, "fraction": 0.5}])
	lab._resolve_combat_contacts()
	assert(float(a.combat_units[1].hp) == 0.0 and float(b.combat_units[1].hp) == 0.0, "Army rows share equal-time trade semantics")
	a.prepare_combat(40.0)
	assert(not a.combat_can_act(1) and not a.blocks_cell(a.cells[1]))
	data.site["army_trial_active"] = true
	assert(not Store.save(data, "res://.godot-temp/site_combat/army-must-not-save.json").ok)
	assert(not a.issue_command(TerrainArmy.Command.FOLLOW_PLAYER), "Unintegrated marching cannot revive or move fallen rows")
	for team: TerrainArmy in teams:
		team.clear()
		assert(team.combat_units.is_empty() and not team.combat_enabled)
		team.queue_free()
	lab.free()
	TerrainArmy.release_contact_source()
	await process_frame
	print("SITE ARMY COMBAT PASS: 200 data rows, exact-time contact, frozen aim JSON/invalid-value guard, once-per-swing, friendly obstruction, KO/death/occupancy, no heal, simultaneous trades, explicit save guard")
	quit(0)

func unfiltered_contacts(lab: TerrainLab, source: TerrainArmy, previous: Array[PackedVector2Array], current: Array[PackedVector2Array]) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for team: TerrainArmy in lab.combat_armies:
		for index in range(team.combat_units.size()):
			if team == source and index == 1:
				continue
			if not SiteCombatRules.terrain_line_clear(lab.terrain, source.cells[1], team.cells[index]):
				continue
			var hit := team.combat_contact(index, previous, current)
			if not hit.is_empty():
				hit["distance"] = source.combat_ground(1).distance_squared_to(hit.point)
				hits.append(hit)
	lab._sort_contacts(hits)
	return hits
