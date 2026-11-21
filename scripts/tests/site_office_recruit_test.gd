extends SceneTree
## v2 plan 3.4 募兵, first source: a retired row of the same team is enlisted
## again by whoever exercises team.recruit (the captain acts while the 募兵官
## seat is vacant), with the person's consent. Nobody else may; the controlled
## person must confirm themselves; a busy person refuses; no row is created.

class ControlStub extends RefCounted:
	var id := -1
	func controlled_person_id() -> int:
		return id

func _initialize() -> void:
	call_deferred("run")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func run() -> void:
	create_timer(40.0).timeout.connect(func() -> void: _fail("SITE OFFICE RECRUIT deadline"))
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "office-recruit")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	var control := ControlStub.new()
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = 1
	team.controlled_person_query = Callable(control, "controlled_person_id")
	var selected: Array[Vector2i] = []
	for index in range(100): selected.append(Vector2i(20 + index % 10, 20 + floori(float(index) / 10.0)))
	if not (team.deploy_at(data, null, null, selected) and team.enable_combat(false)): return _fail("deploy")
	team.settle_combat_command()
	var offices := team.team_offices()
	if not offices.duties.has("team.recruit") or str(SiteOffices.position(offices, str(offices.duties["team.recruit"])).office_class) != "military":
		return _fail("team.recruit sits on a 武官 seat")
	var head := team.combat_identity(team.formal_commander)
	var rows_before := team.combat_units.size()
	# Two people leave the team themselves (each while controlled).
	for index: int in [6, 7]:
		control.id = team.combat_identity(index)
		var left := team.leave_row(team.combat_identity(index))
		if not left.ok: return _fail("leave %d: %s" % [index, str(left)])
	control.id = team.combat_identity(7) # Person 7 is still the controlled one.
	var candidates := team.recruit_candidates()
	if candidates != ([team.combat_identity(6)] as Array[int]): return _fail("Candidates: retired, free, not controlled: %s" % str(candidates))
	if str(team.recruit_row(team.combat_identity(3), team.combat_identity(6)).code) != "NO_AUTHORITY": return _fail("Only the team.recruit decider recruits")
	if str(team.recruit_row(head, team.combat_identity(7)).code) != "NEEDS_CONSENT": return _fail("The controlled person confirms themselves")
	var enlisted := team.recruit_row(head, team.combat_identity(6))
	if not enlisted.ok or not team.is_member(6): return _fail("Captain (acting for the vacant 募兵官) enlists: %s" % str(enlisted))
	if team.combat_units.size() != rows_before: return _fail("No new row is created")
	if str(team.recruit_row(head, team.combat_identity(6)).code) != "NO_TARGET": return _fail("Already a member")
	var saved := JSON.parse_string(JSON.stringify(team.capture_combat_state())) as Dictionary
	if not TerrainArmy.valid_combat_state(saved, data): return _fail("Save validates")
	team.clear()
	team.queue_free()
	await process_frame
	print("SITE OFFICE RECRUIT PASS: team.recruit 武官 seat, retired-row source only, decider-only, controlled person consents themselves, no new row, already-member refused, save validates")
	TerrainArmy.release_contact_source() # Free the shared combat rig before exit (headless dummy-renderer teardown noise).
	quit(0)
