extends SceneTree
## Offices contract (OFFICE_POSITIONS_AND_DUTIES_PLAN 3, 6, 10) on a real
## TerrainArmy: default one-seat-per-duty, head fallback, whole-plan validation,
## automatic vacancy, head-only adjustment, save/legacy, nation migration shape,
## and the duty AI head filling a vacancy through the same plan entry.
const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")

func _initialize() -> void:
	call_deferred("run")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: _fail("SITE OFFICES deadline"))
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "offices-fixture")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	var selected: Array[Vector2i] = []
	for index in range(100):
		selected.append(Vector2i(10 + index % 10, 10 + floori(float(index) / 10)))
	if not (team.deploy_at(data, null, null, selected) and team.enable_combat(false)): return _fail("fixture deploy")
	for index in range(1, 6):
		if not team.set_military_role(team.combat_identity(index), "officer").ok: return _fail("officer role")
	if not team.record_officer_service([1, 2, 3], true).ok: return _fail("service")
	team.settle_combat_command()
	# Start from the empty one-seat-per-duty layout: R1b auto-appointment seats
	# officers when they are promoted or enter service (user decision 2026-10-07).
	team.offices = SiteOffices.default_offices("team", -1, true)
	team._mark_serving_dirty()
	var head := team.combat_identity(team.formal_commander)
	var officer_a := team.combat_identity(1)
	var officer_b := team.combat_identity(2)
	var officer_c := team.combat_identity(3)
	var soldier := team.combat_identity(10)

	# 5.1 default: head + one vacant seat per other duty; head exercises everything.
	var offices := team.team_offices()
	if offices.positions.size() != SiteOffices.duty_ids("team").size() or not SiteOffices.validate(offices, "team", false): return _fail("default layout")
	if not bool(offices.duty_ai): return _fail("NPC-headed new team defaults duty AI on (D17)")
	for duty_id: String in SiteOffices.duty_ids("team"):
		var resolved := team.duty_resolve(duty_id)
		if not bool(resolved.ok) or int(resolved.decider) != head: return _fail("head exercises %s" % duty_id)
		if SiteOffices.position(offices, str(resolved.position_id)).name != SiteOffices.default_name(duty_id): return _fail("default name %s" % duty_id)
	var logistics_seat := str(offices.duties["team.logistics"])
	var work_seat := str(offices.duties["team.work"])

	# Whole-plan rules.
	var revision := int(offices.revision)
	if str(team.apply_office_plan(officer_a, revision, [{"op": "rename", "position_id": work_seat, "name": "x"}]).code) != "NO_AUTHORITY": return _fail("only head adjusts")
	if str(team.apply_office_plan(head, revision + 1, [{"op": "rename", "position_id": work_seat, "name": "x"}]).code) != "STALE_REVISION": return _fail("stale revision")
	if str(team.apply_office_plan(head, revision, [{"op": "appoint", "position_id": logistics_seat, "person_id": soldier}]).code) != "NOT_ELIGIBLE": return _fail("soldier cannot hold")
	# v2 §3.2: a 武官 post needs officer rank, not prior cadre service (an officer outside service may be appointed).
	var outside := team.apply_office_plan(head, revision, [{"op": "appoint", "position_id": logistics_seat, "person_id": team.combat_identity(4)}])
	if not outside.ok: return _fail("Officer outside cadre service may hold a 武官 post: %s" % str(outside))
	team.offices = SiteOffices.default_offices("team", -1, true)
	team._mark_serving_dirty()
	offices = team.team_offices()
	revision = int(offices.revision)
	if str(team.apply_office_plan(head, revision, [{"op": "abolish", "position_id": str(SiteOffices.head_position(offices).id)}]).code) != "NO_AUTHORITY": return _fail("head seat permanent")
	if str(team.apply_office_plan(head, revision, [{"op": "abolish", "position_id": work_seat}]).code) != "DUTY_ORPHAN": return _fail("abolish keeps duties")
	if str(team.apply_office_plan(head, revision, [{"op": "rename", "position_id": work_seat, "name": "後勤官"}]).code) != "NAME_DUPLICATE": return _fail("unique names")
	if str(team.apply_office_plan(head, revision, [{"op": "rename", "position_id": work_seat, "name": ""}]).code) != "NAME_INVALID": return _fail("name rule")
	if team.offices.revision != revision: return _fail("rejected plans leave no partial change")
	var appointed := team.apply_office_plan(head, revision, [{"op": "appoint", "position_id": logistics_seat, "person_id": officer_a}])
	if not appointed.ok: return _fail("appoint: %s" % str(appointed))
	var resolved := team.duty_resolve("team.logistics")
	if int(resolved.decider) != officer_a or bool(resolved.acting): return _fail("holder exercises own duty")
	var refused := team.duty_authority("team.logistics", head)
	if str(refused.get("code", "")) != "NO_AUTHORITY" or not str(refused.message).contains("後勤官"): return _fail("head cannot bypass a fit holder: %s" % str(refused))
	revision = int(team.offices.revision)
	if str(team.apply_office_plan(head, revision, [{"op": "assign", "duty_id": "team.logistics", "position_id": work_seat}]).code) != "EMPTY_POSITION": return _fail("held seat keeps one duty")
	if str(team.apply_office_plan(head, revision, [{"op": "appoint", "position_id": work_seat, "person_id": officer_a}]).code) != "DUPLICATE_HOLDER": return _fail("one seat per person")
	# Swap duties in one plan: intermediate states are never checked.
	var swapped := team.apply_office_plan(head, revision, [
		{"op": "assign", "duty_id": "team.logistics", "position_id": work_seat},
		{"op": "assign", "duty_id": "team.work", "position_id": logistics_seat}])
	if not swapped.ok or team.duty_decider("team.work") != officer_a or team.duty_decider("team.logistics") != head: return _fail("swap plan")
	revision = int(team.offices.revision)
	var added := team.apply_office_plan(head, revision, [{"op": "add", "name": "兵部", "ref": "new"},
		{"op": "assign", "duty_id": "team.logistics", "position_id": "new"}, {"op": "appoint", "position_id": "new", "person_id": officer_b},
		{"op": "abolish", "position_id": work_seat}])
	if not added.ok or team.duty_decider("team.logistics") != officer_b: return _fail("add/abolish plan: %s" % str(added))

	# 3.4 temporary incapacity: head acts, seat retained, returns automatically.
	var b_index := team.index_for_identity(officer_b)
	team.apply_unit_contact(b_index, {"result": {"hp": 1.0, "stun": 110.0, "guard_break": false}, "shield": false})
	team.settle_combat_command()
	resolved = team.duty_resolve("team.logistics")
	if int(resolved.decider) != head or not bool(resolved.acting) or int(resolved.holder) != officer_b: return _fail("KO holder: head acts, seat kept")
	if DutyAI.review_team_personnel(team, -1).size() != 0 and int(SiteOffices.position_of(team.offices, officer_b).get("holder", -1)) != officer_b: return _fail("AI head does not dismiss a temporarily unfit holder")

	# Save, corruption, legacy.
	var saved := JSON.parse_string(JSON.stringify(team.capture_combat_state())) as Dictionary
	if not saved.has("offices") or not TerrainArmy.valid_combat_state(saved, data): return _fail("save offices")
	var corrupt := saved.duplicate(true)
	corrupt.offices.duties.erase("team.work")
	if TerrainArmy.valid_combat_state(corrupt, data): return _fail("duty conservation on load")
	corrupt = saved.duplicate(true)
	corrupt.offices.positions[0].holder = head
	if TerrainArmy.valid_combat_state(corrupt, data): return _fail("team head holder is derived, never stored")
	team.restore_combat_state(saved, data, null, null)
	team.settle_combat_command()
	if team.offices != saved.offices and int(team.offices.revision) != int(saved.offices.revision): return _fail("restore offices")
	if int(SiteOffices.position_of(team.offices, officer_b).get("holder", -1)) != officer_b: return _fail("holder survives save")
	var legacy := saved.duplicate(true)
	legacy.erase("offices")
	if not TerrainArmy.valid_combat_state(legacy, data): return _fail("legacy save valid")
	team.restore_combat_state(legacy, data, null, null)
	team.settle_combat_command()
	if bool(team.team_offices().duty_ai) or team.duty_decider("team.logistics") != team.combat_identity(team.current_commander): return _fail("legacy: default layout, duty AI off, behavior unchanged")

	# Automatic loss of appointment vacates; the AI head refills by ability.
	team.offices = SiteOffices.default_offices("team", -1, true)
	revision = int(team.offices.revision)
	logistics_seat = str(team.offices.duties["team.logistics"])
	if not team.apply_office_plan(head, revision, [{"op": "appoint", "position_id": logistics_seat, "person_id": officer_c}]).ok: return _fail("appoint c")
	if not team.record_officer_service([team.index_for_identity(officer_c)], false).ok: return _fail("revoke c")
	if int(SiteOffices.position(team.team_offices(), logistics_seat).holder) != -1: return _fail("revoked holder vacated")
	var filled := DutyAI.review_team_personnel(team, -1)
	if not bool(filled.get("ok", false)): return _fail("AI head fills vacancy: %s" % str(filled))
	var seated := 0
	for seat: Dictionary in team.offices.positions: seated += int(int(seat.holder) > 0)
	if seated != 1 or team.duty_traces.is_empty() or str(team.duty_traces[-1].duty_id) != "office.adjust": return _fail("one appointment per round, traced")
	if DutyAI.review_team_personnel(team, head).size() != 0: return _fail("player-controlled head is never driven by AI")

	# Later-wired duties: a first-release record (no roster/salvage/ship) still
	# loads and gains one vacant seat per new duty; the head keeps exercising them.
	var first_release := SiteOffices.default_offices("team", -1, false)
	for later: String in SiteOffices.LATER_DUTIES.team:
		var seat_id := str(first_release.duties[later])
		first_release.duties.erase(later)
		first_release.positions.erase(SiteOffices.position(first_release, seat_id))
	if not SiteOffices.validate(first_release, "team", false): return _fail("first-release team offices stay loadable")
	team.offices = first_release
	var grown := team.team_offices()
	if grown.duties.size() != SiteOffices.duty_ids("team").size() or not SiteOffices.validate(grown, "team", false): return _fail("ensure_catalog adds later duties")
	for later: String in SiteOffices.LATER_DUTIES.team:
		if team.duty_decider(later) != head or SiteOffices.position(grown, str(grown.duties[later])).name != SiteOffices.default_name(later): return _fail("later duty %s vacant, head acts" % later)
	# Roster authority follows the 書記 seat.
	var clerk_seat := str(grown.duties["team.roster"])
	var clerk := team.combat_identity(team.officer_service[0])
	if not team.apply_office_plan(head, int(grown.revision), [{"op": "appoint", "position_id": clerk_seat, "person_id": clerk}]).ok: return _fail("appoint clerk")
	var empty_team := TerrainArmy.new()
	var moved := team.transfer_members_to(empty_team, [soldier], team.formal_commander)
	empty_team.free()
	if str(moved.code) != "NO_AUTHORITY" or not str(moved.message).contains("書記"): return _fail("roster belongs to the clerk: %s" % str(moved))

	# Nation: legacy migration keeps the three equipment duties on military_head.
	var nation_offices := SiteOffices.legacy_nation_offices(7)
	if not SiteOffices.validate(nation_offices, "nation"): return _fail("legacy nation offices valid")
	var fit := func(person_id: int) -> bool: return person_id == 7
	for duty_id: String in SiteOffices.LEGACY_NATION_DUTIES:
		if int(SiteOffices.resolve(nation_offices, duty_id, -1, fit).decider) != 7: return _fail("legacy nation %s" % duty_id)
	if str(SiteOffices.resolve(nation_offices, "nation.corps", -1, fit).code) != "OFFICE_PAUSED": return _fail("vacant head pauses its own duty")
	if str(SiteOffices.resolve(nation_offices, "nation.dye", -1, func(_p: int) -> bool: return false).code) != "OFFICE_PAUSED": return _fail("unfit holder with vacant head pauses")
	var new_nation := SiteOffices.default_offices("nation", 9, true)
	if int(SiteOffices.resolve(new_nation, "nation.equip_standard", 9, fit).decider) != 9: return _fail("new nation head acts for vacant seats")
	team.clear()
	team.queue_free()
	await process_frame
	print("SITE OFFICES PASS: default layout, head fallback, plan rules, KO acting, save/corrupt/legacy, auto vacancy, AI head refill, nation legacy migration")
	quit(0)
