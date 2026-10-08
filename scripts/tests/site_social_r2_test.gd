extends SceneTree
## R2 social state against the v2 plan's fixed examples: §6.2 willingness
## threshold table, §8.1 decay and 20 cap, §8.3 loyalty (−50·P, +50 serving,
## 100 per complete custody day: neutral 60 → 30 after 30 days), §8.4 leave
## threshold H, three observed days with hysteresis, controlled persons never
## form an intent, event dedupe, and PersonSocial v1/v2 validation.

const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")
const PP = preload("res://scripts/terrain_lab/person_personality.gd")

func _initialize() -> void:
	call_deferred("run")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func body(axes: Dictionary = {}) -> Dictionary:
	var packet := PP.neutral()
	packet.merge(axes, true)
	return {"person_id": 7, "personality": packet}

func run() -> void:
	# §6.2 threshold table (萬分位).
	var table := [[{}, 3000], [{"ambition": 100}, 4000], [{"lawful": 100}, 2000], [{"risk": 100}, 2500],
		[{"ambition": 100, "lawful": 0, "risk": 0}, 5500], [{"ambition": 0, "lawful": 100, "risk": 100}, 1000]]
	for row: Array in table:
		if SiteSocial.surrender_threshold(body(row[0])) != int(row[1]): return _fail("T %s = %d" % [str(row[0]), SiteSocial.surrender_threshold(body(row[0]))])
	# §8.1 decay; §8.4 H.
	if SiteSocial.decay(body()) != 1 or SiteSocial.decay(body({"ambition": 0})) != 3 or SiteSocial.decay(body({"lawful": 100})) != 3 or SiteSocial.decay(body({"ambition": 0, "lawful": 100})) != 5: return _fail("decay table")
	var h_table := [[{}, 70], [{"ambition": 100}, 50], [{"lawful": 100}, 90], [{"ambition": 100, "lawful": 0}, 30], [{"ambition": 0, "lawful": 100}, 95]]
	for row: Array in h_table:
		if SiteSocial.leave_threshold(body(row[0])) != int(row[1]): return _fail("H %s" % str(row[0]))
	var team := SiteSocial.team_ref("s1", 3)
	var free := {"minute": 0, "controlled": false, "affiliations": [team], "captive_relation": {}, "team_ref": team, "holds_post": true, "eligible_for_post": false}
	# Day events: +10 dismissal and +8 + +8 hunger-like would cap at 20; decay 1; L −50·P.
	var person := body()
	SiteSocial.settle_person(person, free) # starts today (day 0), no invented past
	var ctx := free.duplicate()
	if not SiteSocial.record(person, team, "dismissed", 10, "e1", 0) or SiteSocial.record(person, team, "dismissed", 10, "e1", 0): return _fail("record + dedupe")
	SiteSocial.record(person, team, "x", 15, "e2", 0)
	ctx.minute = 1440
	SiteSocial.settle_person(person, ctx)
	var entry: Dictionary = person.social_state.orgs[SiteSocial.org_key(team)]
	if int(entry.G) != 19 or int(entry.L) != 6000 - 50 * 20: return _fail("G cap 20 − decay 1 = 19, L −1000: %s" % str(entry))
	ctx.minute = 2880
	SiteSocial.settle_person(person, ctx) # no events: decay 1, serving +50
	if int(entry.G) != 18 or int(entry.L) != 5050: return _fail("Quiet day: G −1, L +50: %s" % str(entry))
	if not PersonSocial.valid(person.social_state): return _fail("v2 packet validates")
	if not PersonSocial.valid(JSON.parse_string(JSON.stringify(person.social_state))): return _fail("v2 survives JSON")
	if not PersonSocial.valid({"version": 1, "capture_seq": 2}) or PersonSocial.valid({"version": 2, "capture_seq": 0}): return _fail("v1 valid, partial v2 invalid")

	# §8.3 example: neutral prisoner L=60, 30 complete custody days → 30 (= threshold).
	var prisoner := body()
	var relation := {"version": 3, "captured_at_game_seconds": 0.0, "loyal_org": team, "settled_days": 0}
	SiteSocial.state_of(prisoner)
	SiteSocial.relation(prisoner.social_state, team)
	var captive_ctx := {"minute": 30 * 1440 + 30, "controlled": false, "affiliations": [], "captive_relation": relation, "team_ref": null}
	SiteSocial.settle_person(prisoner, captive_ctx)
	var loyalty := int(prisoner.social_state.orgs[SiteSocial.org_key(team)].L)
	if loyalty != 3000 or int(relation.settled_days) != 30: return _fail("30 days: L 6000 → 3000, settled 30: %d / %d" % [loyalty, int(relation.settled_days)])
	if loyalty > SiteSocial.surrender_threshold(prisoner): return _fail("Neutral reaches willingness at 30")
	SiteSocial.settle_person(prisoner, captive_ctx)
	if int(prisoner.social_state.orgs[SiteSocial.org_key(team)].L) != 3000: return _fail("Same days never charged twice")
	var early := {"version": 3, "captured_at_game_seconds": 6.0 * 3600.0, "loyal_org": team, "settled_days": 0}
	SiteSocial.settle_before_release(prisoner, early, 18 * 60 + 8 * 60 + 1440 - 18 * 60) # D1 08:00 after D0 06:00 = 26 h
	if int(early.settled_days) != 1: return _fail("Release after 26 h settles exactly one custody day")

	# §8.4 omen: G ≥ H (neutral 70) for three days → intent; drop below 60 clears.
	var restless := body()
	var day_ctx := free.duplicate()
	day_ctx.holds_post = true
	SiteSocial.settle_person(restless, day_ctx)
	var rel: Dictionary = restless.social_state.orgs[SiteSocial.org_key(team)]
	rel.G = 80
	for day in range(1, 4):
		day_ctx.minute = day * 1440
		SiteSocial.settle_person(restless, day_ctx)
		if day < 3 and bool(rel.intent): return _fail("No intent before three observed days (day %d)" % day)
	if not bool(rel.intent): return _fail("Intent after three days at G ≥ H")
	if str(SiteSocial.status(restless, team).label) != "已提出離開意向": return _fail("Visible intent label")
	rel.G = 61
	day_ctx.minute = 4 * 1440
	SiteSocial.settle_person(restless, day_ctx)
	if not bool(rel.intent): return _fail("Hysteresis: G 60 still above H−10 keeps the intent")
	rel.G = 50
	day_ctx.minute = 5 * 1440
	SiteSocial.settle_person(restless, day_ctx)
	if bool(rel.intent): return _fail("Below H−10 clears the intent")
	var player := body()
	var player_ctx := day_ctx.duplicate()
	player_ctx.controlled = true
	SiteSocial.settle_person(player, player_ctx)
	player.social_state.orgs[SiteSocial.org_key(team)].G = 100
	for day in range(6, 10):
		player_ctx.minute = day * 1440
		SiteSocial.settle_person(player, player_ctx)
	if bool(player.social_state.orgs[SiteSocial.org_key(team)].intent): return _fail("The controlled person never forms an intent")
	print("SITE SOCIAL R2 PASS: §6.2 T table, §8.1 decay/cap, §8.3 L (−50·P, +50, custody 60→30 in 30 days, 26 h release = 1 day, no double charge), §8.4 H table, 3-day intent with hysteresis, controlled exempt, dedupe, v1/v2 validation")
	quit(0)
