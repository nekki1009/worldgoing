extends SceneTree
## 文武官 W1+W2 (reports/civil-military-office-plan.md §5.1–5.4, §8; Nekki 11/09 all as suggested). Checks:
## - W1: `civil_role` is an optional social-packet field ("clerk"/"official"; missing = none); bad values are invalid;
##   it survives the v1→v3 upgrade and a JSON round trip; setting "none" removes it;
## - W2: required_class reads military / civil (文吏+) / civil_official (文官: 制度研究, 財政); qualified() checks the track;
## - a team: a soldier without 文吏 is refused a 文官 seat (NOT_ELIGIBLE), takes it once raised to clerk; an officer without
##   文吏 is refused too (a 儒將 needs both tracks); a 武官 seat still needs the officer rank whatever the civil track;
##   a seat carrying 訓練 on a civil class still needs the officer rank;
## - duty AI: the civil pool only offers qualified members.
## Output: SITE_OFFICE_CIVIL_ROLE_PASS on success; quit(1) on any failure.

const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")

var checks := 0

func _initialize() -> void:
	call_deferred("run")

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_OFFICE_CIVIL_ROLE OK ", checks, ": ", message)
		return true
	printerr("SITE_OFFICE_CIVIL_ROLE_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func run() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		printerr("SITE_OFFICE_CIVIL_ROLE_FAIL: deadline")
		quit(1))
	# W1 packet.
	var row := {}
	if not _check(PersonSocial.civil_role(row) == "none" and PersonSocial.set_civil_role(row, "none") and not row.has("social_state"), "no packet reads none; setting none writes nothing"): return
	if not _check(PersonSocial.set_civil_role(row, "clerk") and PersonSocial.civil_role(row) == "clerk" and PersonSocial.valid(row.social_state), "a clerk packet is valid", row): return
	if not _check(not PersonSocial.set_civil_role(row, "minister") and PersonSocial.civil_role(row) == "clerk", "an unknown role is refused"): return
	var bad: Dictionary = row.social_state.duplicate(true)
	bad.civil_role = "none"
	if not _check(not PersonSocial.valid(bad), "a stored 'none' is invalid (absence means none)"): return
	bad.civil_role = 1
	if not _check(not PersonSocial.valid(bad), "a non-text role is invalid"): return
	var upgraded := PersonSocial.upgraded(row.social_state)
	if not _check(PersonSocial.valid(upgraded) and upgraded.get("civil_role") == "clerk", "the v3 upgrade keeps the role", upgraded): return
	var wire: Variant = JSON.parse_string(JSON.stringify(upgraded))
	if not _check(PersonSocial.valid(PersonSocial.normalized(wire)) and PersonSocial.normalized(wire).civil_role == "clerk", "a JSON round trip keeps the role"): return
	if not _check(PersonSocial.set_civil_role(row, "none") and not row.social_state.has("civil_role") and PersonSocial.valid(row.social_state), "setting none removes the role"): return

	# W2 class table.
	var nation := SiteOffices.legacy_nation_offices(7)
	SiteOffices.ensure_catalog(nation, "nation")
	var finance_seat := SiteOffices.position(nation, str(nation.duties.get("nation.finance", "")))
	var head_seat := SiteOffices.head_position(nation)
	if not _check(not finance_seat.is_empty() and SiteOffices.required_class(nation, finance_seat) == "civil_official", "財政 asks a 文官", finance_seat): return
	if not _check(SiteOffices.qualified("civil_official", "officer", "official") and not SiteOffices.qualified("civil_official", "officer", "clerk") and SiteOffices.qualified("civil", "soldier", "clerk") and not SiteOffices.qualified("civil", "officer", "none") and SiteOffices.qualified("military", "officer", "none") and not SiteOffices.qualified("military", "soldier", "official"), "qualified() checks the asked track only"): return
	if not _check(SiteOffices.required_class(nation, head_seat) == "military", "元首 (軍團編成) stays a 武官 seat"): return

	# A team.
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "office-civil-role")
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
	if not _check(team.deploy_at(data, null, null, selected) and team.enable_combat(false), "a team deploys"): return
	if not _check(team.set_military_role(team.combat_identity(1), "officer").ok and team.record_officer_service([1], true).ok, "member 1 is an officer"): return
	team.settle_combat_command()
	var head := team.combat_identity(team.formal_commander)
	# An unseated officer (member 1 already holds a seat from his service record).
	if not _check(team.set_military_role(team.combat_identity(2), "officer").ok, "member 2 is an unseated officer"): return
	var officer := team.combat_identity(2)
	var soldier := team.combat_identity(10)
	var offices := team.team_offices()
	var work_seat := str(offices.duties["team.work"])
	var training_seat := str(offices.duties["team.training"])
	if not _check(SiteOffices.required_class(offices, SiteOffices.position(offices, work_seat)) == "civil", "工頭 asks a 文吏"): return
	var refused := team.apply_office_plan(head, int(offices.revision), [{"op": "appoint", "position_id": work_seat, "person_id": soldier}])
	if not _check(str(refused.code) == "NOT_ELIGIBLE" and str(refused.message).contains("文吏"), "a soldier without 文吏 is refused a 文官 seat", refused): return
	# (Officers are seated by their service record, so the track is read through the owner's own candidate check.)
	if not _check(not team.office_candidate_ok(officer, "civil") and team.office_candidate_ok(officer, "military"), "an officer without 文吏 does not fit a 文官 seat (a 儒將 needs both tracks)"): return
	if not _check(team.civil_role(10) == "none" and PersonSocial.set_civil_role(team.combat_units[10], "clerk") and team.civil_role(10) == "clerk", "the soldier is raised to 文吏"): return
	var seated := team.apply_office_plan(head, int(offices.revision), [{"op": "appoint", "position_id": work_seat, "person_id": soldier}])
	if not _check(seated.ok and team.duty_decider("team.work") == soldier and team.military_role(10) == "soldier", "the 文吏 soldier takes 工頭 and stays a soldier", seated): return
	offices = team.team_offices()
	var clerk_military := team.apply_office_plan(head, int(offices.revision), [{"op": "appoint", "position_id": training_seat, "person_id": team.combat_identity(11)}])
	PersonSocial.set_civil_role(team.combat_units[11], "official")
	clerk_military = team.apply_office_plan(head, int(offices.revision), [{"op": "appoint", "position_id": training_seat, "person_id": team.combat_identity(11)}])
	if not _check(str(clerk_military.code) == "NOT_ELIGIBLE", "a 文官 soldier still cannot take 教頭 (武官)", clerk_military): return
	var civil_training := team.apply_office_plan(head, int(offices.revision), [{"op": "classify", "position_id": training_seat, "office_class": "civil"},
		{"op": "appoint", "position_id": training_seat, "person_id": team.combat_identity(11)}])
	if not _check(str(civil_training.code) == "NOT_ELIGIBLE", "訓練 on a civil seat still needs the officer rank", civil_training): return

	# Duty AI pool: of the unseated members only the qualified ones fit a civil seat.
	var roster_seat := SiteOffices.position(offices, str(offices.duties["team.roster"]))
	var fits: Array[int] = []
	for index: int in range(team.combat_units.size()):
		var identity := team.combat_identity(index)
		if index == team.formal_commander or identity == soldier: continue
		if team.office_candidate_ok(identity, SiteOffices.required_class(offices, roster_seat)): fits.append(identity)
	if not _check(fits == [team.combat_identity(11)], "only the 文官 member fits the 書記 seat", fits): return

	team.clear()
	team.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE_OFFICE_CIVIL_ROLE_PASS checks=", checks)
	quit(0)
