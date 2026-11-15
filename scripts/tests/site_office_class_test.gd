extends SceneTree
## R1a (v2 plan): offices v2 office_class. v1 records load and upgrade; duties
## that need a 武官 only sit on military seats; a soldier may hold a 文官 seat
## (派工／名冊) without gaining command rights; 文官 名冊 really splits the team;
## reclassifying rechecks the holder; v2 saves round-trip; other orgs upgrade.

func _initialize() -> void:
	call_deferred("run")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: _fail("SITE OFFICE CLASS deadline"))
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "office-class")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = 1
	var selected: Array[Vector2i] = []
	for index in range(100): selected.append(Vector2i(20 + index % 10, 20 + floori(float(index) / 10.0)))
	if not (team.deploy_at(data, null, null, selected) and team.enable_combat(false)): return _fail("deploy")
	if not team.set_military_role(team.combat_identity(1), "officer").ok or not team.record_officer_service([1], true).ok: return _fail("officer")
	team.settle_combat_command()
	var head := team.combat_identity(team.formal_commander)
	var soldier := team.combat_identity(10)
	var clerk := team.combat_identity(11)
	# 文武官 W2: 文官 seats need 文吏; the fixture's civil holders are raised first.
	for index: int in [10, 11, 12]: TerrainTestCharacter.PersonSocial.set_civil_role(team.combat_units[index], "clerk")

	# v1 record (pre-R1a) is valid and upgrades on first use.
	var v1 := SiteOffices.default_offices("team", -1, false)
	v1.version = 1
	for seat: Dictionary in v1.positions: seat.erase("office_class")
	if not SiteOffices.validate(v1, "team", false): return _fail("v1 offices still load")
	team.offices = v1
	var offices := team.team_offices()
	if int(offices.version) != 2 or not SiteOffices.validate(offices, "team", false): return _fail("upgrade to v2")
	var class_of := func(duty_id: String) -> String: return str(SiteOffices.position(team.offices, str(team.offices.duties[duty_id])).office_class)
	if class_of.call("team.training") != "military" or class_of.call("team.work") != "civil" or class_of.call("team.roster") != "civil" or class_of.call("team.logistics") != "military":
		return _fail("Upgrade classes follow the duty table")

	# 2026-10-07 (Nekki: 文官也可以帶兵): 訓練 may sit on a 文官 seat, but its holder
	# still needs officer qualification.
	var bad := team.apply_office_plan(head, int(offices.revision), [{"op": "assign", "duty_id": "team.training", "position_id": str(offices.duties["team.work"])},
		{"op": "appoint", "position_id": str(offices.duties["team.work"]), "person_id": soldier}])
	if str(bad.code) != "NOT_ELIGIBLE": return _fail("A soldier cannot take 訓練 on a 文官 seat: %s" % str(bad))
	var mixed := offices.duplicate(true)
	SiteOffices.position(mixed, str(mixed.duties["team.training"])).office_class = "civil"
	if not SiteOffices.validate(mixed, "team", false): return _fail("Saved v2 with training on a 文官 seat is valid")

	# A soldier holds 工頭 (文官) without becoming an officer; 教頭 (武官) refuses him.
	if str(team.apply_office_plan(head, int(offices.revision), [{"op": "appoint", "position_id": str(offices.duties["team.training"]), "person_id": soldier}]).code) != "NOT_ELIGIBLE":
		return _fail("Soldier cannot hold a 武官 seat")
	if not team.apply_office_plan(head, int(offices.revision), [{"op": "appoint", "position_id": str(offices.duties["team.work"]), "person_id": soldier},
		{"op": "appoint", "position_id": str(offices.duties["team.roster"]), "person_id": clerk}]).ok: return _fail("Soldiers hold 文官 seats")
	if team.duty_decider("team.work") != soldier or not team.duty_authority("team.work", soldier).is_empty(): return _fail("文官 exercises 派工")
	if team.command_eligible(team.index_for_identity(soldier)) or team.military_role(team.index_for_identity(soldier)) != "soldier":
		return _fail("A 文官 post gives no command rights or officer rank")

	# Reclassify: 軍需 becomes 文官 and takes a soldier in the same plan; 教頭 cannot become 文官.
	offices = team.team_offices()
	var equip_seat := str(offices.duties["team.equip"])
	var quarter := team.combat_identity(12)
	if not team.apply_office_plan(head, int(offices.revision), [{"op": "classify", "position_id": equip_seat, "office_class": "civil"},
		{"op": "appoint", "position_id": equip_seat, "person_id": quarter}]).ok: return _fail("Reclassify then appoint")
	offices = team.team_offices()
	if str(team.apply_office_plan(head, int(offices.revision), [{"op": "classify", "position_id": equip_seat, "office_class": "military"}]).code) != "NOT_ELIGIBLE":
		return _fail("Turning a soldier's seat 武官 rechecks the holder")
	# An officer on a 文官 教頭 seat leads: trains, and counts as 在任幹部 for command.
	var training_seat := str(offices.duties["team.training"])
	var officer := team.combat_identity(1)
	if not team.apply_office_plan(head, int(offices.revision), [{"op": "classify", "position_id": training_seat, "office_class": "civil"},
		{"op": "appoint", "position_id": training_seat, "person_id": officer}]).ok: return _fail("教頭 may become 文官 with an officer")
	if class_of.call("team.training") != "civil" or team.duty_decider("team.training") != officer or not team.command_eligible(1) or not team.officer_order.has(1):
		return _fail("文官 教頭 officer trains and has command rights")
	offices = team.team_offices()
	if str(team.apply_office_plan(head, int(offices.revision), [{"op": "set_role", "person_id": officer, "role": "soldier"}]).code) != "HAS_APPOINTMENT":
		return _fail("The 訓練 holder keeps officer qualification")

	# 文官 書記 really splits; the captain is refused (roster belongs to the clerk).
	var split := TerrainArmy.new()
	root.add_child(split)
	split.set_process(false)
	split.team_id = 2
	var moving: Array[int] = [team.combat_identity(60), team.combat_identity(61)]
	var refused := team.split_members_to(split, moving, team.formal_commander)
	if str(refused.code) != "NO_AUTHORITY" or not str(refused.message).contains("書記"): return _fail("Captain refused, roster is the clerk's: %s" % str(refused))
	var done := team.split_members_to(split, moving, team.index_for_identity(clerk))
	if not done.ok: return _fail("文官 書記 splits the team: %s" % str(done))
	# A departing 文官 holder vacates; the others keep their seats.
	var leaving: Array[int] = [quarter]
	# (The officer-less split team has no captain, so its own 名冊 duty is paused
	# and it cannot confirm receiving people; move him into another new team.)
	var split2 := TerrainArmy.new()
	root.add_child(split2)
	split2.set_process(false)
	split2.team_id = 3
	var moved := team.split_members_to(split2, leaving, team.index_for_identity(clerk))
	if not moved.ok: return _fail("Move the 文官 holder out: %s" % str(moved))
	if int(SiteOffices.position(team.team_offices(), equip_seat).holder) != -1: return _fail("Departed 文官 holder vacates")
	if team.duty_decider("team.work") != soldier: return _fail("Remaining 文官 keeps his seat")

	# v2 save round-trip.
	var saved := JSON.parse_string(JSON.stringify(team.capture_combat_state())) as Dictionary
	if not TerrainArmy.valid_combat_state(saved, data) or int(saved.offices.version) != 2: return _fail("v2 save")

	# Other organisations upgrade the same way.
	var nation := SiteOffices.legacy_nation_offices(7)
	nation.version = 1
	for seat: Dictionary in nation.positions: seat.erase("office_class")
	if not SiteOffices.validate(nation, "nation") or not SiteOffices.upgrade(nation) or not SiteOffices.validate(nation, "nation"): return _fail("nation v1 → v2")
	if str(SiteOffices.head_position(nation).office_class) != "military": return _fail("元首 (軍團編成) is 武官")
	var family := SiteOffices.default_offices("family", 3, false)
	if str(SiteOffices.head_position(family).office_class) != "civil": return _fail("家主 is 文官")

	for army: TerrainArmy in [team, split, split2]:
		army.clear()
		army.queue_free()
	await process_frame
	print("SITE OFFICE CLASS PASS: v1 upgrade, class table, 訓練 needs an officer on any seat class, 文官 officer leads, 文官 soldiers without command rights, reclassify recheck, 文官 roster split, vacancy, v2 save, nation/family classes")
	TerrainArmy.release_contact_source() # Free the shared combat rig before exit (headless dummy-renderer teardown noise).
	quit(0)
