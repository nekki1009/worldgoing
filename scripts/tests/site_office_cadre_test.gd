extends SceneTree
## R1b remainder (v2 plan §3.2/§3.5): cadre list derived from posts; soldier 文官
## cadre get troop exemption but no cape; officer 文官 cadre lead (2026-10-07); two-phase rank + post plans; NO_POSITION;
## pre-R1b cadre beyond the free posts stay visible as MIGRATION_REQUIRED pending
## cadre without command rights; saves with 文官 cadre validate.

const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")

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

func plan(team: TerrainArmy, ops: Array) -> Dictionary:
	return team.apply_office_plan(team.combat_identity(team.formal_commander), int(team.team_offices().revision), ops)

func run() -> void:
	create_timer(40.0).timeout.connect(func() -> void: _fail("SITE OFFICE CADRE deadline"))
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "office-cadre")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	var team := make_team(data, 1)
	var offices := team.team_offices()
	var work_seat := str(offices.duties["team.work"])
	var training_seat := str(offices.duties["team.training"])

	# A soldier on a 文官 post is cadre (exempt) but not in succession, no command, no cape.
	var clerk := 10
	if not plan(team, [{"op": "appoint", "position_id": work_seat, "person_id": team.combat_identity(clerk)}]).ok: return _fail("appoint 文官")
	if not team.officer_service.has(clerk) or team.officer_order.has(clerk): return _fail("文官 holder is cadre but not in the succession order")
	if not team._troop_exempt_ids().has(team.combat_identity(clerk)): return _fail("文官 cadre get the troop-type exemption")
	if team.command_eligible(clerk): return _fail("A soldier on a 文官 post has no command rights")
	if Orders.rank_grants_cape(clerk, team.formal_commander, team.officer_service, team.officer_order): return _fail("A 文官 post never grants a cape")
	var saved := JSON.parse_string(JSON.stringify(team.capture_combat_state())) as Dictionary
	if not TerrainArmy.valid_combat_state(saved, data): return _fail("Save with 文官 cadre (service ⊃ order) validates")

	# Two-phase: promote a soldier and seat him as 教頭 in one plan.
	var coach := 11
	var promoted := plan(team, [{"op": "set_role", "person_id": team.combat_identity(coach), "role": "officer"},
		{"op": "appoint", "position_id": training_seat, "person_id": team.combat_identity(coach)}])
	if not promoted.ok: return _fail("promote + appoint: %s" % str(promoted))
	if team.military_role(coach) != "officer" or not team.officer_order.has(coach) or not team.command_eligible(coach):
		return _fail("Promoted 教頭 is a serving 武官")
	if not Orders.rank_grants_cape(coach, team.formal_commander, team.officer_service, team.officer_order): return _fail("武官 cadre keep the cape right")
	# Demoting the 教頭 while he keeps the 武官 post is refused, atomically.
	var revision := int(team.team_offices().revision)
	var refused := plan(team, [{"op": "set_role", "person_id": team.combat_identity(coach), "role": "soldier"}])
	if str(refused.code) != "HAS_APPOINTMENT" or team.military_role(coach) != "officer" or int(team.team_offices().revision) != revision:
		return _fail("Demotion with a 武官 post is refused and nothing changes: %s" % str(refused))
	# A 文官 cadre officer may drop officer rank and keep the post (v2 §3.5).
	var scribe := 12
	if not team.set_military_role(team.combat_identity(scribe), "officer").ok: return _fail("promote scribe")
	if not plan(team, [{"op": "dismiss", "position_id": str(SiteOffices.position_of(team.team_offices(), team.combat_identity(scribe)).id)},
		{"op": "appoint", "position_id": str(team.team_offices().duties["team.roster"]), "person_id": team.combat_identity(scribe)}]).ok: return _fail("move scribe to 文官 書記")
	# 2026-10-07 (Nekki: 文官也可以帶兵): an officer on a 文官 post leads and wears the cape.
	if not team.officer_order.has(scribe) or not team.command_eligible(scribe) or not Orders.rank_grants_cape(scribe, team.formal_commander, team.officer_service, team.officer_order):
		return _fail("Officer on a 文官 post is in succession, has command rights and the cape")
	if not team.prepare_military_role(team.combat_identity(scribe), "soldier").ok: return _fail("文官 cadre may be demoted")
	if not team.set_military_role(team.combat_identity(scribe), "soldier").ok or SiteOffices.position_of(team.team_offices(), team.combat_identity(scribe)).is_empty():
		return _fail("Demoted 文官 keeps the post")
	if team.officer_order.has(scribe) or team.command_eligible(scribe) or not team.officer_service.has(scribe): return _fail("Demoted 文官 stays cadre without command")

	# NO_POSITION when every 武官 post is filled.
	var filler := 20
	while team._free_military_seats() > 0:
		if not team.set_military_role(team.combat_identity(filler), "officer").ok: return _fail("fill posts")
		filler += 1
	var spare := filler
	if not team.set_military_role(team.combat_identity(spare), "officer").ok: return _fail("spare officer")
	if team.officer_service.has(spare): return _fail("No free post: the promoted officer is not cadre")
	if str(team.record_officer_service([spare], true).code) != "NO_POSITION": return _fail("Cadre appointment needs a free 武官 post")

	# Pre-R1b save with more cadre than posts: extras become visible pending cadre.
	var legacy := make_team(data, 2)
	for index in range(1, 9):
		if not legacy.set_military_role(legacy.combat_identity(index), "officer").ok: return _fail("legacy officer")
	var old := JSON.parse_string(JSON.stringify(legacy.capture_combat_state())) as Dictionary
	old.erase("offices")
	old.erase("cadre_seated")
	old.officers = [1, 2, 3, 4, 5, 6, 7, 8]
	old.officer_service = [1, 2, 3, 4, 5, 6, 7, 8]
	if not TerrainArmy.valid_combat_state(old, data): return _fail("Old save with 8 cadre is loadable")
	legacy.restore_combat_state(old, data, null, null)
	legacy.settle_combat_command()
	# Every 武官 post with duties seats one legacy officer; the rest wait (5 posts before
	# 募兵官 joined the catalog, 6 since).
	var military_posts := 0
	for seat: Dictionary in legacy.team_offices().positions:
		if not bool(seat.head) and str(seat.get("office_class", "")) == "military" and not SiteOffices.duties_of_position(legacy.team_offices(), str(seat.id)).is_empty(): military_posts += 1
	var pending := legacy.pending_cadre()
	if pending.size() != 8 - military_posts: return _fail("%d posts seated, %d pending: %s" % [military_posts, 8 - military_posts, str(pending)])
	var pending_index := legacy.index_for_identity(pending[0])
	if legacy.command_eligible(pending_index): return _fail("Pending cadre have no command rights (R1b)")
	if not legacy.officer_service.has(pending_index): return _fail("Pending cadre are not silently dropped")
	if not legacy.record_officer_service([pending_index], false).ok or legacy.pending_cadre().has(pending[0]): return _fail("Head releases a pending cadre member")

	for army: TerrainArmy in [team, legacy]:
		army.clear()
		army.queue_free()
	await process_frame
	print("SITE OFFICE CADRE PASS: cadre follow posts, 文官 exempt without cape, two-phase promote+appoint, atomic refused demotion, officer on 文官 post leads with cape, 文官 demotion keeps post without command, NO_POSITION, old save posts seated / rest pending without command rights, release")
	quit(0)
