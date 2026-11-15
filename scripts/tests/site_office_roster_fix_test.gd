extends SceneTree
## F07 regression (v2 plan): splitting or reinforcing a team must keep both
## teams' own offices and duty_ai; only holders who actually left vacate, and a
## new split team never inherits the source's appointments.

func _initialize() -> void:
	call_deferred("run")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

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

func appoint(team: TerrainArmy, duty_id: String, index: int) -> bool:
	var offices := team.team_offices()
	return bool(team.apply_office_plan(team.combat_identity(team.formal_commander), int(offices.revision),
		[{"op": "appoint", "position_id": str(offices.duties[duty_id]), "person_id": team.combat_identity(index)}]).ok)

func holder(team: TerrainArmy, duty_id: String) -> int:
	var offices := team.team_offices()
	return int(SiteOffices.position(offices, str(offices.duties[duty_id])).holder)

func run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: _fail("SITE OFFICE ROSTER FIX deadline"))
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "office-roster-fix")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	var first := make_team(data, 1, Vector2i(20, 20))
	var second := make_team(data, 2, Vector2i(40, 20))
	for team: TerrainArmy in [first, second]:
		for index in [1, 2]:
			if not team.set_military_role(team.combat_identity(index), "officer").ok: return _fail("officer role")
		if not team.record_officer_service([1, 2], true).ok: return _fail("service")
		team.settle_combat_command()
		# Old-save team: duty AI off; it must never flip on by itself (D17).
		team.offices = SiteOffices.default_offices("team", -1, false)
	if not appoint(first, "team.logistics", 1) or not appoint(first, "team.training", 2): return _fail("appoint first")
	# 文武官 W2: a 文官 seat needs a 文吏 (a 武官 seat an officer); the fixture qualifies its holder first.
	second.set_civil_role(second.combat_identity(1), "clerk")
	if not appoint(second, "team.work", 1): return _fail("appoint second")
	var keeper := first.combat_identity(1)
	var leaver := first.combat_identity(2)
	var second_holder := second.combat_identity(1)

	# Split: officer 2 (training holder) and nine soldiers leave into a new team.
	var split := TerrainArmy.new()
	root.add_child(split)
	split.set_process(false)
	split.team_id = 3
	var moving: Array[int] = [leaver]
	for index in range(50, 59): moving.append(first.combat_identity(index))
	var revision_before := int(first.team_offices().revision)
	var result := first.split_members_to(split, moving, first.current_commander)
	if not result.ok: return _fail("split: %s" % str(result))
	if holder(first, "team.logistics") != keeper: return _fail("Remaining holder keeps the seat after a split")
	if holder(first, "team.training") != -1: return _fail("Holder who left vacates the seat")
	if bool(first.team_offices().duty_ai): return _fail("duty_ai must not flip on after a split (D17)")
	if int(first.team_offices().revision) <= revision_before: return _fail("Vacancy is a personnel change: revision bumps")
	for seat: Dictionary in split.team_offices().positions:
		if int(seat.holder) > 0: return _fail("New split team must not inherit appointments")

	# Reinforce: soldiers from first join existing second; both keep their offices.
	var joining: Array[int] = [first.combat_identity(60), first.combat_identity(61)]
	result = first.transfer_members_to(second, joining, first.current_commander, second.current_commander)
	if not result.ok: return _fail("reinforce: %s" % str(result))
	if holder(second, "team.work") != second_holder or bool(second.team_offices().duty_ai): return _fail("Receiving team keeps its offices and duty_ai")
	if holder(first, "team.logistics") != keeper or bool(first.team_offices().duty_ai): return _fail("Source keeps its offices after reinforcing another team")
	# The saved snapshot round-trips with the kept appointment.
	var saved := JSON.parse_string(JSON.stringify(first.capture_combat_state())) as Dictionary
	if not TerrainArmy.valid_combat_state(saved, data) or bool(saved.offices.duty_ai): return _fail("save after transfers")

	for team: TerrainArmy in [first, second, split]:
		team.clear()
		team.queue_free()
	await process_frame
	print("SITE OFFICE ROSTER FIX PASS: split keeps remaining holders and duty_ai, leaver vacates, new team inherits nothing, reinforcement keeps both teams' offices")
	TerrainArmy.release_contact_source() # Free the shared combat rig before exit (headless dummy-renderer teardown noise).
	quit(0)
