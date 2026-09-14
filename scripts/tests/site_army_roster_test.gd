extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "roster-fixture")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	var first := make_team(data, 1, Vector2i(20, 20))
	var second := make_team(data, 2, Vector2i(40, 20))
	var split := TerrainArmy.new()
	root.add_child(split)
	split.set_process(false)
	split.team_id = 3
	first.training = 90.0
	second.training = 30.0
	var cargo := {"grain": 3}
	var equipment := {"item_ids": ["original-sword"], "equipped": {"weapon": "original-sword"}}
	first.combat_units[1].cargo = cargo
	first.combat_units[1].item_state = equipment
	first.combat_units[1].hp = 61.5
	first.combat_units[1].fatigue = 72.25
	first.command_abilities[1] = {"tactics": 6, "leadership": 7, "coach": 8}
	first.officer_order.assign([1, 2])
	first.officer_service.assign([1, 2])
	first.combat_units[2].ko = 13.5
	first.combat_units[2].pose = "unconscious"
	first.combat_units[2].present = false
	first._cell_owners.erase(first.cells[2])
	var original_person: Dictionary = first.combat_units[1]
	var original_cell := first.cells[1]
	var original_id := first.combat_identity(1)
	var selected: Array[int] = []
	for index in range(1, 21):
		selected.append(first.combat_identity(index))
	var snapshot_before := first.capture_combat_state()
	var duplicate_team := second.capture_combat_state()
	duplicate_team.team_id = first.team_id
	assert(not SiteStore._validate_armies(data, {"armies": [snapshot_before, duplicate_team]}).ok, "Team IDs must also be globally unique")
	assert(not first.split_members_to(split, selected, 99).ok)
	assert(first.capture_combat_state() == snapshot_before)
	assert(first.split_members_to(split, selected, first.current_commander).ok)
	assert(first.roster_size == 80 and split.roster_size == 20)
	assert(first.combat_units.size() == 80 and split.combat_units.size() == 20)
	assert(first.index_for_identity(original_id) == -1 and split.index_for_identity(original_id) == 0)
	assert(is_same(split.combat_units[0], original_person), "Move original person rows, not restored clones")
	assert(is_same(split.combat_units[0].cargo, cargo) and is_same(split.combat_units[0].item_state, equipment))
	assert(split.cells[0] == original_cell and split.combat_units[0].hp == 61.5 and split.combat_units[0].fatigue == 72.25)
	assert(split.combat_units[1].ko == 13.5 and split.combat_units[1].pose == "unconscious")
	assert(split.training == 90.0 and first.training == 90.0)
	assert(not split._uses_live_presenter(0), "A male row becoming index zero does not become the original female captain")
	assert(split.command_abilities[0] == {"tactics": 6, "leadership": 7, "coach": 8})
	assert(TerrainArmy.valid_combat_state(JSON.parse_string(JSON.stringify(first.capture_combat_state())), data))
	assert(TerrainArmy.valid_combat_state(JSON.parse_string(JSON.stringify(split.capture_combat_state())), data))
	assert(split.merge_into(first, split.current_commander, first.current_commander).ok)
	assert(not split.has_army() and first.roster_size == 100 and first.training == 90.0)
	assert(is_same(first.combat_units[first.index_for_identity(original_id)], original_person))
	var before_ids := TerrainArmy.snapshot_person_ids(first.capture_combat_state())
	before_ids.append_array(TerrainArmy.snapshot_person_ids(second.capture_combat_state()))
	assert(second.merge_into(first, second.current_commander, first.current_commander).ok)
	assert(first.roster_size == 200 and not second.has_army() and first.training == 60.0)
	var after_ids := TerrainArmy.snapshot_person_ids(first.capture_combat_state())
	before_ids.sort()
	after_ids.sort()
	assert(before_ids == after_ids and TerrainArmy.valid_person_ids(after_ids, 200))
	var female_count := 0
	for unit: Dictionary in first.combat_units:
		female_count += int(unit.visual_role == "female_live")
	assert(female_count == 2, "Full merge retains both original female persons")
	assert(first.combat_identity(100) != TerrainArmy.PLAYER_MEMBER)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(first.capture_combat_state()))
	assert(TerrainArmy.valid_combat_state(saved, data))
	assert(SiteStore._validate_armies(data, {"armies": [saved]}).ok, "Transferred 100 + 100 is one valid 200-member roster")
	assert(not SiteStore._validate_armies(data, {"armies": [saved, snapshot_before]}).ok, "Two individually valid teams cannot exceed total Site capacity")
	var restored := TerrainArmy.new()
	root.add_child(restored)
	restored.set_process(false)
	restored.restore_combat_state(saved, data, null, null)
	assert(restored.roster_size == 200 and TerrainArmy.snapshot_person_ids(restored.capture_combat_state()) == TerrainArmy.snapshot_person_ids(saved))
	var invalid := saved.duplicate(true)
	invalid.units[1].person_id = invalid.units[0].person_id
	assert(not TerrainArmy.valid_combat_state(invalid, data))
	invalid = saved.duplicate(true)
	invalid.units[1].erase("person_id")
	assert(not TerrainArmy.valid_combat_state(invalid, data), "New missing IDs never refill from row indexes")
	invalid = saved.duplicate(true)
	invalid.formal_commander = 9999
	assert(not TerrainArmy.valid_combat_state(invalid, data), "Invalid command gaps cannot index arbitrary rows")
	invalid = saved.duplicate(true)
	invalid.units[0].work_resting = "false"
	assert(not TerrainArmy.valid_combat_state(invalid, data), "Work-rest latch must be a real bool")
	var legacy := snapshot_before.duplicate(true)
	legacy.erase("roster_version")
	for unit: Dictionary in legacy.units:
		unit.erase("person_id")
		unit.erase("visual_role")
	assert(TerrainArmy.valid_combat_state(legacy, data))
	assert(TerrainArmy.normalize_roster_snapshot(legacy).units[1].person_id == 1101)
	paused = true
	assert(not first.start_unit_attack(0, first.cells[0] + Vector2i.LEFT))
	assert(not first.merge_into(restored, first.current_commander, restored.current_commander).ok)
	paused = false
	for army: TerrainArmy in [first, second, split, restored]:
		army.free()
	TerrainArmy.release_contact_source()
	print("SITE_ARMY_ROSTER_PASS: actual split/reinforcement/full merge; unique stable IDs; row/gear references; weighted training; legacy save; command guards")
	quit(0)

func make_team(data: TerrainData, identity: int, origin: Vector2i) -> TerrainArmy:
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = identity
	var selected: Array[Vector2i] = []
	for index in range(100):
		selected.append(origin + Vector2i(index % 10, floori(float(index) / 10.0)))
	assert(team.deploy_at(data, null, null, selected))
	assert(team.enable_combat(false))
	return team
