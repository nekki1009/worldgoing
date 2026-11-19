extends SceneTree
## v2 plan 3.4 募兵, third source: a person who left team A is recruited into
## team B by B's recruit decider, with A's 名冊 decider (NPC) accepting and the
## person (NPC, idle) consenting. The original row moves, keeps its identity and
## joins B; nobody else may, the controlled person must confirm themselves.

class ControlStub extends RefCounted:
	var id := -1
	func controlled_person_id() -> int:
		return id

func _initialize() -> void:
	call_deferred("run")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func make_team(data: TerrainData, identity: int, origin: Vector2i, control: ControlStub) -> TerrainArmy:
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = identity
	team.faction_id = 1
	team.controlled_person_query = Callable(control, "controlled_person_id")
	var selected: Array[Vector2i] = []
	for index in range(100): selected.append(origin + Vector2i(index % 10, floori(float(index) / 10.0)))
	assert(team.deploy_at(data, null, null, selected) and team.enable_combat(false))
	team.settle_combat_command()
	return team

func run() -> void:
	create_timer(40.0).timeout.connect(func() -> void: _fail("SITE OFFICE RECRUIT CROSS deadline"))
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "office-recruit-cross")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	var control := ControlStub.new()
	var a := make_team(data, 1, Vector2i(10, 10), control)
	var b := make_team(data, 2, Vector2i(30, 10), control)
	b.combat_units.map(func(row: Dictionary) -> int: row.person_id = int(row.person_id) + 100000; return 0)
	b._invalidate_combat_identity_cache()
	var leaver := a.combat_identity(6)
	var other := a.combat_identity(7)
	for identity: int in [leaver, other]:
		control.id = identity
		if not a.leave_row(identity).ok: return _fail("leave %d" % identity)
	control.id = other # The second leaver stays the controlled person.
	var b_head := b.combat_identity(b.formal_commander)
	if str(b.recruit_from_team(a, b.combat_identity(3), leaver).code) != "NO_AUTHORITY": return _fail("Only B's recruit decider")
	if str(b.recruit_from_team(a, b_head, other).code) != "NEEDS_CONSENT": return _fail("Controlled person confirms themselves")
	if str(b.recruit_from_team(a, b_head, a.combat_identity(8)).code) != "NO_TARGET": return _fail("Only retired rows of A")
	var a_rows := a.combat_units.size()
	var b_rows := b.combat_units.size()
	var row: Dictionary = a.combat_units[a.index_for_identity(leaver)]
	var recruited := b.recruit_from_team(a, b_head, leaver)
	if not recruited.ok: return _fail("recruit: %s" % str(recruited))
	var index_b := b.index_for_identity(leaver)
	if index_b < 0 or not b.is_member(index_b) or a.index_for_identity(leaver) >= 0: return _fail("Row moved to B and joined")
	if not is_same(b.combat_units[index_b], row) or a.combat_units.size() != a_rows - 1 or b.combat_units.size() != b_rows + 1: return _fail("Original row moved, nothing created")
	for army: TerrainArmy in [a, b]:
		var saved := JSON.parse_string(JSON.stringify(army.capture_combat_state())) as Dictionary
		if not TerrainArmy.valid_combat_state(saved, data): return _fail("Save validates for team %d" % army.team_id)
		army.clear()
		army.queue_free()
	await process_frame
	print("SITE OFFICE RECRUIT CROSS PASS: recruit decider only, controlled person consents themselves, retired rows only, original row moves and joins, saves validate")
	TerrainArmy.release_contact_source() # Free the shared combat rig before exit (headless dummy-renderer teardown noise).
	quit(0)
