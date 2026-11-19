extends SceneTree
## v2 plan §3.3 「空缺隊長就任」: when the captaincy is permanently vacant and no
## qualified post holder can succeed, the controlled member of the team names a
## present, able officer (no post needed). Refusals: not vacant, not the
## controlled member, a soldier candidate. One commit sets captain and lists.

class ControlStub extends RefCounted:
	var id := -1
	func controlled_person_id() -> int:
		return id

func _initialize() -> void:
	call_deferred("run")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func make_team(data: TerrainData, identity: int) -> TerrainArmy:
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = identity
	var selected: Array[Vector2i] = []
	for index in range(100): selected.append(Vector2i(20 + index % 10, 20 + floori(float(index) / 10.0)))
	assert(team.deploy_at(data, null, null, selected) and team.enable_combat(false))
	team.settle_combat_command()
	return team

func run() -> void:
	create_timer(40.0).timeout.connect(func() -> void: _fail("SITE OFFICE VACANT CLAIM deadline"))
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "office-vacant-claim")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	var control := ControlStub.new()
	var team := make_team(data, 1)
	team.controlled_person_query = Callable(control, "controlled_person_id")
	var officer := 5
	if not team.set_military_role(team.combat_identity(officer), "officer").ok: return _fail("promote")
	# Empty every post: the officer has no post, so nobody can succeed.
	team.offices = SiteOffices.default_offices("team", -1, false)
	team._mark_serving_dirty()
	var member := team.combat_identity(7)
	control.id = member
	if str(team.claim_vacant_captaincy(member, team.combat_identity(officer)).code) != "NOT_VACANT": return _fail("A living captain is not vacant")
	team.apply_unit_contact(0, {"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
	team._command_dirty = true
	team.settle_combat_command()
	if team.formal_commander != -1: return _fail("No post holder: captaincy stays vacant (R1b)")
	if str(team.claim_vacant_captaincy(team.combat_identity(8), team.combat_identity(officer)).code) != "NO_AUTHORITY": return _fail("Only the controlled member submits")
	if str(team.claim_vacant_captaincy(member, team.combat_identity(9)).code) != "NOT_ELIGIBLE": return _fail("A soldier cannot take the captaincy")
	var claimed := team.claim_vacant_captaincy(member, team.combat_identity(officer))
	if not claimed.ok: return _fail("Claim: %s" % str(claimed))
	if team.formal_commander != officer or team.current_commander != officer or not team.command_eligible(officer) or team.officer_service.has(officer):
		return _fail("New captain commands and leaves the cadre list")
	if int(SiteOffices.head_position(team.team_offices()).get("holder", -1)) > 0: return _fail("Head seat stays a projection of formal_commander (no stored holder)")
	var saved := JSON.parse_string(JSON.stringify(team.capture_combat_state())) as Dictionary
	if not TerrainArmy.valid_combat_state(saved, data): return _fail("Save after claim validates")
	if str(team.claim_vacant_captaincy(member, team.combat_identity(officer)).code) != "NOT_VACANT": return _fail("Second claim refused")
	team.clear()
	team.queue_free()
	await process_frame
	print("SITE OFFICE VACANT CLAIM PASS: vacancy only after death with no post holder, controlled member only, officer candidate only, one commit sets captain and lists, save validates")
	TerrainArmy.release_contact_source() # Free the shared combat rig before exit (headless dummy-renderer teardown noise).
	quit(0)
