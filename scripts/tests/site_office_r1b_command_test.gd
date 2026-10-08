extends SceneTree
## R1b (v2 plan, user decisions 2026-10-07) on a fixed roster:
## - acting, succession and command ability sums count only the formal captain
##   plus 在任武官 (cadre holding a non-head 武官 seat); before/after printed;
## - 自動任命: officers who are promoted / enter service, and every officer of a
##   save made before R1b, are seated into vacant 武官 posts so captain-down acting
##   and succession work as before; a post the head emptied stays empty on reload.

func _initialize() -> void:
	call_deferred("run")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

const CAP := 0.4
const ABILITIES := [{"tactics": 40, "leadership": 30, "coach": 20}, {"tactics": 50, "leadership": 50, "coach": 50},
	{"tactics": 60, "leadership": 10, "coach": 0}, {"tactics": 20, "leadership": 70, "coach": 30}]

var data: TerrainData

func make_team(identity: int) -> TerrainArmy:
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = identity
	var selected: Array[Vector2i] = []
	for index in range(100): selected.append(Vector2i(20 + index % 10, 20 + floori(float(index) / 10.0)))
	assert(team.deploy_at(data, null, null, selected) and team.enable_combat(false))
	for index in range(1, 4):
		assert(team.set_military_role(team.combat_identity(index), "officer").ok)
	assert(team.record_officer_service([1, 2, 3], true).ok)
	for index in range(4): team.command_abilities[index] = ABILITIES[index].duplicate()
	team.settle_combat_command()
	return team

func empty_layout(team: TerrainArmy) -> void:
	# Equivalent to the head having dismissed every officer from his post.
	team.offices = SiteOffices.default_offices("team", -1, false)
	team._mark_serving_dirty()

func sum_of(indices: Array, kind: String) -> float:
	var total := 0.0
	for index: int in indices: total += float(ABILITIES[index][kind])
	return total

func seat(team: TerrainArmy, duty_id: String, index: int) -> bool:
	var offices := team.team_offices()
	return bool(team.apply_office_plan(team.combat_identity(team.formal_commander), int(offices.revision),
		[{"op": "appoint", "position_id": str(offices.duties[duty_id]), "person_id": team.combat_identity(index)}]).ok)

func seated_count(team: TerrainArmy) -> int:
	var count := 0
	for position: Dictionary in team.team_offices().positions: count += int(int(position.holder) > 0)
	return count

func knock(team: TerrainArmy, index: int, lethal: bool) -> void:
	team.apply_unit_contact(index, {"result": {"hp": 100.0 if lethal else 1.0, "stun": 0.0 if lethal else 110.0, "guard_break": false}, "shield": false})
	team._command_dirty = true
	team.settle_combat_command()

func run() -> void:
	create_timer(40.0).timeout.connect(func() -> void: _fail("SITE OFFICE R1B deadline"))
	data = TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "office-r1b")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)

	# 自動任命 on promotion / service: three officers fill 武官 posts (教頭 first).
	var team := make_team(1)
	if team.formal_commander != 0 or team.current_commander != 0: return _fail("New team founds its captain")
	if seated_count(team) != 3 or team.duty_decider("team.training") != team.combat_identity(1): return _fail("Officers auto-seated, 教頭 first: %d" % seated_count(team))
	var before := SiteCombatRules.diminishing(sum_of([0, 1, 2, 3], "tactics"), CAP) # every present officer (old rule)
	if not is_equal_approx(team.command_effect("tactics", CAP), before): return _fail("Auto-seated officers keep the old aggregate")
	knock(team, 0, false)
	if team.acting_commander != 1: return _fail("Captain KO: first officer in order acts as before: %d" % team.acting_commander)
	knock(team, 0, true)
	if team.formal_commander != 1: return _fail("Captain death: first officer succeeds as before: %d" % team.formal_commander)

	# The aggregation rule itself, with posts emptied by the head.
	var rule := make_team(2)
	empty_layout(rule)
	var after_none := SiteCombatRules.diminishing(sum_of([0], "tactics"), CAP)
	if not is_equal_approx(rule.command_effect("tactics", CAP), after_none): return _fail("Unseated officers add nothing")
	if not seat(rule, "team.training", 2): return _fail("seat officer 2")
	var after_one := SiteCombatRules.diminishing(sum_of([0, 2], "tactics"), CAP)
	if not is_equal_approx(rule.command_effect("tactics", CAP), after_one): return _fail("Captain + seated 武官 only")
	var offices := rule.team_offices()
	if not rule.apply_office_plan(rule.combat_identity(0), int(offices.revision), [{"op": "classify", "position_id": str(offices.duties["team.equip"]), "office_class": "civil"},
		{"op": "appoint", "position_id": str(offices.duties["team.equip"]), "person_id": rule.combat_identity(3)}]).ok: return _fail("officer on a 文官 seat")
	# 2026-10-07 (Nekki: 文官也可以帶兵): an officer-qualified 文官 holder counts too.
	var after_civil := SiteCombatRules.diminishing(sum_of([0, 2, 3], "tactics"), CAP)
	if not is_equal_approx(rule.command_effect("tactics", CAP), after_civil) or not rule.command_eligible(3): return _fail("Officer on a 文官 seat adds command ability")
	var leadership_before := SiteCombatRules.diminishing(sum_of([0, 1, 2, 3], "leadership"), CAP)
	var leadership_after := rule.command_effect("leadership", CAP)
	knock(rule, 0, false)
	if rule.acting_commander != 2: return _fail("Only seated officers act (officer 1 is first in order but unseated)")
	knock(rule, 2, false)
	if rule.acting_commander != 3: return _fail("The officer on the 文官 seat acts next: %d" % rule.acting_commander)
	var bare := make_team(3)
	empty_layout(bare)
	knock(bare, 0, false)
	if bare.current_commander != -1: return _fail("No 在任武官: nobody acts")
	knock(bare, 0, true)
	if bare.formal_commander != -1: return _fail("No 在任武官: captaincy stays vacant, no random pick")

	# Old save (made before R1b, no marker): officers auto-appointed once, behavior as before.
	var legacy := make_team(4)
	var saved := JSON.parse_string(JSON.stringify(legacy.capture_combat_state())) as Dictionary
	saved.erase("offices")
	saved.erase("cadre_seated")
	if not TerrainArmy.valid_combat_state(saved, data): return _fail("Pre-R1b save stays loadable")
	legacy.restore_combat_state(saved, data, null, null)
	legacy.settle_combat_command()
	if seated_count(legacy) != 3: return _fail("Old save: all three officers appointed: %d" % seated_count(legacy))
	if not is_equal_approx(legacy.command_effect("tactics", CAP), before): return _fail("Old save keeps its aggregate")
	knock(legacy, 0, false)
	if legacy.acting_commander != 1: return _fail("Old save: captain KO deputy as before")
	knock(legacy, 0, true)
	if legacy.formal_commander != 1: return _fail("Old save: succession as before")

	# Saved after R1b: a post the head emptied is not refilled on reload.
	var kept := make_team(5)
	offices = kept.team_offices()
	var dismissed_seat := str(SiteOffices.position_of(offices, kept.combat_identity(3)).id)
	if not kept.apply_office_plan(kept.combat_identity(0), int(offices.revision), [{"op": "dismiss", "position_id": dismissed_seat}]).ok: return _fail("dismiss")
	var resaved := JSON.parse_string(JSON.stringify(kept.capture_combat_state())) as Dictionary
	if resaved.get("cadre_seated") != true: return _fail("marker saved")
	kept.restore_combat_state(resaved, data, null, null)
	kept.settle_combat_command()
	if int(SiteOffices.position(kept.team_offices(), dismissed_seat).holder) != -1: return _fail("Dismissed post stays empty after reload")

	for army: TerrainArmy in [team, rule, bare, legacy, kept]:
		army.clear()
		army.queue_free()
	await process_frame
	print("SITE OFFICE R1B PASS: tactics cap %.1f, all officers seated %.4f (= old rule); posts emptied: captain only %.4f, +1 seated 武官 %.4f, +1 officer on 文官 seat %.4f; leadership old %.4f vs captain+1 %.4f; auto-appointment keeps KO deputy and succession; no 在任武官 → no acting/succession; old save appointed once; dismissed post not refilled" % [CAP, before, after_none, after_one, after_civil, leadership_before, leadership_after])
	quit(0)
