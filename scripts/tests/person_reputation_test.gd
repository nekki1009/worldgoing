extends SceneTree
## Reputation rules (plan "聲望系統規劃"), pure: tiers, rank floors, gains and caps, daily prestige decay, credit
## recovery, inheritance, event amounts and the formula terms. The neutral start (0, 0) adds nothing to the agreed
## acceptance and follow scores.
## Output: PERSON_REPUTATION_PASS on success; quit(1) on any failure.

const R = preload("res://scripts/terrain_lab/person_reputation.gd")
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("PERSON_REPUTATION OK ", checks, ": ", message)
		return true
	printerr("PERSON_REPUTATION_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _run() -> void:
	if not _check(R.prestige_name(0) == "無名" and R.prestige_name(1000) == "小有名氣" and R.prestige_name(5000) == "威震一州" and R.prestige_name(10000) == "名動天下", "prestige tiers"): return
	if not _check(R.credit_name(-10000) == "背信棄義" and R.credit_name(-4900) == "反覆無常" and R.credit_name(0) == "尋常" and R.credit_name(1500) == "守信" and R.credit_name(5000) == "信義昭著", "credit tiers"): return
	if not _check(R.credit_name(-5000) == "背信棄義" and R.credit_name(-1500) == "反覆無常" and R.credit_name(-1400) == "尋常" and R.credit_name(1400) == "尋常", "credit tier edges -50 / -15 / +14"): return
	if not _check(R.floor_of("king") == 5000 and R.floor_of("baron") == 1200 and R.floor_of("none") == 0, "rank floors"): return
	if not _check(R.add_prestige(0, 40) == 1500 and R.add_prestige(9900, 15) == 10000 and R.add_prestige(100, -5) == 0, "a gain is capped at +15, the value clamped"): return
	if not _check(R.add_credit(0, -40) == -4000 and R.add_credit(-9000, -40) == -10000, "credit clamps at -100"): return
	if not _check(R.decay_prestige(1200, "baron") == 1200 and R.decay_prestige(2200, "baron") == 2190 and R.decay_prestige(1250, "baron") == 1249 and R.decay_prestige(500, "king") == 5000, "prestige falls 1% of the excess over the floor a day, never below the floor"): return
	if not _check(R.recover_credit(-4000, 9) == -4000 and R.recover_credit(-4000, 10) == -3900 and R.recover_credit(-2050, 100) == -2000 and R.recover_credit(-1000, 100) == -1000, "credit recovers 1 per 10 days, only up to -20"): return
	if not _check(R.inherited_prestige(500, 6000) == 1800 and R.inherited_prestige(3000, 6000) == 3000, "the heir keeps max(own, predecessor x 0.3)"): return
	if not _check(R.settlement_change(5, false) == 8.0 and R.settlement_change(5, true) == -4.0 and R.settlement_change(2, false) == 2.0, "taking or losing a settlement"): return
	if not _check(is_equal_approx(R.victory_gain(200, 300), 5.0) and is_equal_approx(R.victory_gain(40, 20), 3.0) and is_equal_approx(R.victory_gain(20, 100), 1.0), "victory gain: min(5, enemy / 20), x1.5 when outnumbered"): return
	if not _check(is_equal_approx(R.noble_taken_gain("duke"), 8.0) and R.revoke_loss("count", "baron") == -13.0, "noble taken and revoke loss"): return
	if not _check(R.accept_bonus(0, 0) == 0.0 and R.follow_bonus(0, 0) == 0.0, "the neutral start adds nothing to the agreed formulas"): return
	if not _check(is_equal_approx(R.accept_bonus(5000, -4000), 4.0) and is_equal_approx(R.accept_bonus(10000, 10000), 25.0), "acceptance terms: credit x 0.15 + min(10, prestige / 5)"): return
	if not _check(is_equal_approx(R.follow_bonus(-4000, 0), -4.0) and is_equal_approx(R.follow_bonus(10000, -10000), 20.0), "follow term: (player - acceptor credit) x 0.1"): return
	if not _check(R.diplomacy_allows("peace", -5000) and not R.diplomacy_allows("peace", -5100) and R.diplomacy_allows("trade", -2000) and not R.diplomacy_allows("trade", -2100) and R.diplomacy_allows("submit", -10000), "diplomacy credit gates -50 / -20; submission always"): return
	if not _check(R.promotion_allowed(1800, "viscount") and not R.promotion_allowed(1700, "viscount"), "promotion needs prestige at the new floor"): return
	var aged: Dictionary = R.aged({"prestige": 7000, "credit": -4000}, "king", 10)
	var expected := 7000
	for _day: int in range(10): expected = R.decay_prestige(expected, "king")
	if not _check(int(aged.prestige) == expected and expected < 7000 and expected > 5000 and int(aged.credit) == -3900, "ten days: prestige decays toward the king floor, credit -40 recovers to -39", [aged, expected]): return
	if not _check(R.aged({"prestige": 7000, "credit": -4000}, "king", 0) == {"prestige": 7000, "credit": -4000}, "no day passed, no change"): return
	var Social = preload("res://scripts/terrain_lab/person_social.gd")
	var body := {}
	if not _check(Social.reputation(body, 1200) == {"prestige": 1200, "credit": 0, "day": -1}, "a person without a packet reads the rank floor and neutral credit"): return
	Social.set_reputation(body, {"prestige": 3000, "credit": -4000, "day": 5})
	if not _check(Social.valid(body.social_state) and body.social_state.version == 1 and Social.reputation(body).credit == -4000, "set_reputation writes a valid v1 packet", body): return
	var v3: Dictionary = Social.upgraded(body.social_state)
	if not _check(Social.valid(v3) and v3.reputation.prestige == 3000, "the v1 -> v3 upgrade keeps the reputation", v3): return
	var parsed: Dictionary = Social.normalized(JSON.parse_string(JSON.stringify(v3)))
	if not _check(Social.valid(parsed) and parsed.reputation.credit is int, "a JSON round trip stays valid with integer reputation"): return
	var bad: Dictionary = v3.duplicate(true)
	bad.reputation.credit = 20000
	if not _check(not Social.valid(bad), "an out-of-range credit is refused"): return
	if not _check(Social.reputation({"social_state": v3}, 5000).prestige == 5000, "the rank floor lifts a lower stored prestige"): return
	print("PERSON_REPUTATION_PASS: ", checks, " checks")
	quit(0)
