extends SceneTree
## v2 plan 3.5: posts belong to the organization. An officer who holds a post in
## team A and is transferred into existing team B leaves A's post vacant and
## arrives in B as an ordinary member: not cadre, no command rights, until B
## gives them a post of its own.

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
	team.faction_id = 1
	var selected: Array[Vector2i] = []
	for index in range(100): selected.append(origin + Vector2i(index % 10, floori(float(index) / 10.0)))
	assert(team.deploy_at(data, null, null, selected) and team.enable_combat(false))
	team.settle_combat_command()
	return team

func run() -> void:
	create_timer(40.0).timeout.connect(func() -> void: _fail("SITE OFFICE TRANSFER CADRE deadline"))
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "office-transfer-cadre")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	var a := make_team(data, 1, Vector2i(10, 10))
	var b := make_team(data, 2, Vector2i(30, 10))
	b.combat_units.map(func(row: Dictionary) -> int: row.person_id = int(row.person_id) + 100000; return 0)
	b._invalidate_combat_identity_cache()
	var officer := 4
	if not a.set_military_role(a.combat_identity(officer), "officer").ok: return _fail("promote")
	var mover := a.combat_identity(officer)
	var seat := SiteOffices.position_of(a.team_offices(), mover)
	if seat.is_empty() or not a.officer_service.has(officer): return _fail("Officer auto-seated in A")
	var moved := a.transfer_members_to(b, [mover] as Array[int], a.formal_commander, b.index_for_identity(b.duty_decider("team.roster")))
	if not moved.ok: return _fail("transfer: %s" % str(moved))
	var index_b := b.index_for_identity(mover)
	if index_b < 0 or b.officer_service.has(index_b) or b.officer_order.has(index_b): return _fail("Arrives in B as an ordinary member (no copied cadre)")
	if b.command_eligible(index_b): return _fail("No command rights in B without a B post")
	if int(SiteOffices.position(a.team_offices(), str(seat.id)).holder) > 0: return _fail("A's post is vacant")
	if b.pending_cadre().has(mover): return _fail("Not a pending (migration) cadre either")
	for army: TerrainArmy in [a, b]:
		army.clear()
		army.queue_free()
	await process_frame
	print("SITE OFFICE TRANSFER CADRE PASS: transferred officer vacates source post, arrives as ordinary member without cadre/command, not pending")
	TerrainArmy.release_contact_source() # Free the shared combat rig before exit (headless dummy-renderer teardown noise).
	quit(0)
