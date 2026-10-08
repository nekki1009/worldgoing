extends SceneTree
## OFFICE plan appendix D.6 fixed-input tables (one axis at a time, others 50):
## pure knob values, neutral equals the pre-appendix constants, and the head
## personnel decisions on a real TerrainArmy (野心 delay, 守法 cancel, 仁厚 wait,
## 勤勉 cadence, 野心/重家族 candidate choice).

const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")
const PP = preload("res://scripts/terrain_lab/person_personality.gd")

func _initialize() -> void:
	call_deferred("run")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _mind(values: Dictionary) -> Dictionary:
	var packet := PP.neutral()
	for axis: String in values: packet[axis] = int(values[axis])
	return packet

func run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: _fail("SITE DUTY AXES deadline"))
	var n := PP.neutral()
	# Neutral equals the constants used before appendix D.
	if DutyAI.review_period(n) != 1 or DutyAI.fill_delay(n) != 0 or DutyAI.stranded_wait(n) != 0 or DutyAI.acting_band(n, true) != 1.0 \
		or DutyAI.logistics_target_units(n) != 30000 or DutyAI.restart_fatigue(n) != 50.0 or DutyAI.heavy_bonus(n) != 0.0 \
		or DutyAI.revision_threshold(n, 20) != 2 or DutyAI.revision_threshold(n, 50) != 5 or DutyAI.candidate_bonus(n, n, true) != 0:
		return _fail("Neutral knobs must equal the previous behavior")
	# D.6 table rows.
	var rows := [
		["勤勉 0 period", DutyAI.review_period(_mind({"diligence": 0})), 3],
		["勤勉 25 period", DutyAI.review_period(_mind({"diligence": 25})), 2],
		["勤勉 100 period", DutyAI.review_period(_mind({"diligence": 100})), 1],
		["野心 100 delay", DutyAI.fill_delay(_mind({"ambition": 100})), 5],
		["野心 0 delay", DutyAI.fill_delay(_mind({"ambition": 0})), 0],
		["野心+守法 100 delay", DutyAI.fill_delay(_mind({"ambition": 100, "lawful": 100})), 0],
		["仁厚 100 wait (retired proxy)", DutyAI.stranded_wait(_mind({"mercy": 100})), 0],
		["仁厚 0 wait", DutyAI.stranded_wait(_mind({"mercy": 0})), 0],
		["節儉 100 target", DutyAI.logistics_target_units(_mind({"thrift": 100})), 27500],
		["節儉 0 target", DutyAI.logistics_target_units(_mind({"thrift": 0})), 32500],
		["勤勉 100 restart", int(DutyAI.restart_fatigue(_mind({"diligence": 100}))), 60],
		["勤勉 0 restart", int(DutyAI.restart_fatigue(_mind({"diligence": 0}))), 50],
		["求新 100 threshold", DutyAI.revision_threshold(_mind({"innovation": 100}), 20), 1],
		["求新 0 threshold", DutyAI.revision_threshold(_mind({"innovation": 0}), 20), 3],
		["野心候選 100 bonus", DutyAI.candidate_bonus(_mind({"ambition": 100}), n, false), 500],
		["重家族首長 100 kin bonus", DutyAI.candidate_bonus(n, _mind({"kinship": 100}), true), 1000],
		["重家族首長 100 non-kin", DutyAI.candidate_bonus(n, _mind({"kinship": 100}), false), 0],
	]
	for row: Array in rows:
		if row[1] != row[2]: return _fail("%s: %s != %s" % [row[0], str(row[1]), str(row[2])])
	if not is_equal_approx(DutyAI.acting_band(_mind({"lawful": 100}), true), 1.5) or DutyAI.acting_band(_mind({"lawful": 100}), false) != 1.0 \
		or DutyAI.acting_band(_mind({"lawful": 0}), true) != 1.0:
		return _fail("守法 band only widens while acting")
	if not is_equal_approx(DutyAI.heavy_bonus(_mind({"thrift": 0})), 0.125) or not is_equal_approx(DutyAI.heavy_bonus(_mind({"thrift": 100})), -0.125) \
		or not is_equal_approx(DutyAI.heavy_bonus(_mind({"risk": 0})), 0.25):
		return _fail("節儉 heavy bonus is half of 謹慎")
	DutyAI.review_round = 3
	if not DutyAI.due(_mind({"diligence": 0})) or not DutyAI.due(n):
		return _fail("Round 3 is due for period 3 and 1")
	DutyAI.review_round = 4
	if DutyAI.due(_mind({"diligence": 0})) or not DutyAI.due(n): return _fail("Round 4 skips a period-3 decider")
	DutyAI.review_round = 0

	# Real team: head personnel.
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "duty-axes-fixture")
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
	for index in range(1, 4):
		if not team.set_military_role(team.combat_identity(index), "officer").ok: return _fail("officer")
	if not team.record_officer_service([1, 2], true).ok: return _fail("service")
	team.settle_combat_command()
	# Start from the empty one-seat-per-duty layout: R1b auto-appointment seats
	# officers when they are promoted or enter service (user decision 2026-10-07).
	team.offices = SiteOffices.default_offices("team", -1, true)
	team._mark_serving_dirty()
	var head_row: int = team.formal_commander
	var head := team.combat_identity(head_row)
	var seats_held := func() -> int:
		var count := 0
		for seat: Dictionary in team.team_offices().positions: count += int(int(seat.holder) > 0)
		return count

	# 野心 100 head: five rounds keep the seat, the sixth appoints.
	team.combat_units[head_row].personality = _mind({"ambition": 100})
	DutyAI._seat_waits.clear()
	for round_index: int in range(5):
		if not DutyAI.review_team_personnel(team, -1).is_empty() or int(seats_held.call()) != 0: return _fail("野心 head appointed early at round %d" % round_index)
	if not bool(DutyAI.review_team_personnel(team, -1).get("ok", false)) or int(seats_held.call()) != 1: return _fail("野心 head appoints on round 6")
	# 守法 cancels the delay: immediate appointment.
	team.offices = SiteOffices.default_offices("team", -1, true)
	team.combat_units[head_row].personality = _mind({"ambition": 100, "lawful": 100})
	DutyAI._seat_waits.clear()
	if not bool(DutyAI.review_team_personnel(team, -1).get("ok", false)): return _fail("守法 cancels 野心 delay")

	# 仁厚 100 head waits five rounds before replacing a captive holder (neutral: first round).
	var captive := team.combat_identity(1)
	var replaced_at := func(mind: Dictionary) -> int:
		team.offices = SiteOffices.default_offices("team", -1, true)
		var seat: String = str(team.offices.duties["team.logistics"])
		var head_seat: String = str(SiteOffices.head_position(team.offices).id)
		var ops: Array = [{"op": "appoint", "position_id": seat, "person_id": captive}]
		for duty_id: String in SiteOffices.duty_ids("team"):
			if duty_id != "team.logistics": ops.append({"op": "assign", "duty_id": duty_id, "position_id": head_seat})
		if not team.apply_office_plan(head, int(team.offices.revision), ops).ok: return -2
		team.combat_units[head_row].personality = mind
		team.combat_hot_set(1, &"captive", true)
		DutyAI._seat_waits.clear()
		var at := -1
		for round_index: int in range(8):
			if bool(DutyAI.review_team_personnel(team, -1).get("ok", false)) and int(SiteOffices.position(team.offices, seat).holder) != captive:
				at = round_index
				break
		team.combat_hot_set(1, &"captive", false)
		return at
	var replaced: int = replaced_at.call(n)
	if replaced != 0: return _fail("Neutral head replaces a captive holder at once: %d" % replaced)
	replaced = replaced_at.call(_mind({"mercy": 100}))
	if replaced != 0: return _fail("仁厚 now reads the prison duty (D.7); captive holders are replaced at once: %d" % replaced)

	# Candidate choice: 野心 candidate, then 重家族 head with registered kin.
	team.command_abilities[1] = {"tactics": 0, "leadership": 0, "coach": 60}
	team.command_abilities[2] = {"tactics": 0, "leadership": 0, "coach": 57}
	var pair: Array[int] = [team.combat_identity(1), team.combat_identity(2)]
	team.combat_units[head_row].erase("personality")
	if DutyAI._best(team, pair, ["team.training"], n) != pair[0]: return _fail("Neutral picks coach 60")
	team.combat_units[2].personality = _mind({"ambition": 100})
	if DutyAI._best(team, pair, ["team.training"], n) != pair[1]: return _fail("野心 100 candidate wins 57+5 over 60")
	team.combat_units[2].erase("personality")
	team.command_abilities[2] = {"tactics": 0, "leadership": 0, "coach": 52}
	data.site.family = {"version": 2, "complete": true, "members": [{"site_id": str(data.site.id), "person_id": head}, {"site_id": str(data.site.id), "person_id": pair[1]}], "offices": {}}
	if DutyAI._best(team, pair, ["team.training"], n) != pair[0]: return _fail("Neutral head ignores kinship")
	if DutyAI._best(team, pair, ["team.training"], _mind({"kinship": 100})) != pair[1]: return _fail("重家族 head prefers registered kin 52+10 over 60")
	data.site.family.erase("offices")
	if DutyAI._best(team, pair, ["team.training"], _mind({"kinship": 100})) != pair[0]: return _fail("Unestablished family gives no kin bonus")
	data.site.erase("family")

	team.clear()
	team.queue_free()
	await process_frame
	print("SITE DUTY AXES PASS: D.6 table values, neutral = previous constants, cadence, 野心 delay, 守法 cancel, captive holder replaced at once (round %d; 仁厚 moved to prison duty), 野心/重家族 candidate choice" % replaced)
	quit(0)
