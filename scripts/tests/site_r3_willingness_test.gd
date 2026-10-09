extends SceneTree
## R3 §6.2 willingness against the plan's fixed examples: neutral threshold 30,
## loyalty 60 reaches it after 30 complete custody days (unsettled days count as
## candidate, nothing is mutated), the boundary is inclusive, a record without a
## loyal organization never auto-qualifies, and pre-v3 records are rejected.

const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const PP = preload("res://scripts/terrain_lab/person_personality.gd")

func _initialize() -> void:
	call_deferred("run")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func body(axes: Dictionary = {}) -> Dictionary:
	var packet := PP.neutral()
	packet.merge(axes, true)
	return {"person_id": 9, "personality": packet}

func run() -> void:
	var team := SiteSocial.team_ref("s1", 2)
	var relation := {"version": 3, "captured_at_game_seconds": 0.0, "loyal_org": team, "settled_days": 0}
	var neutral := body()
	var day_29 := SiteSocial.surrender_willingness(neutral, relation, 29 * 1440)
	if bool(day_29.willing) or int(day_29.L) != 3100: return _fail("29 days: L 31 > 30: %s" % str(day_29))
	var day_30 := SiteSocial.surrender_willingness(neutral, relation, 30 * 1440)
	if not bool(day_30.willing) or int(day_30.L) != 3000 or int(day_30.T) != 3000: return _fail("30 days: L 30 = T, willing (inclusive): %s" % str(day_30))
	if int(relation.settled_days) != 0 or neutral.has("social_state"): return _fail("Pure: nothing settled or written")
	var lawful := body({"lawful": 100})
	if bool(SiteSocial.surrender_willingness(lawful, relation, 30 * 1440).willing): return _fail("守法 100 (T 20) still loyal at 30")
	if not bool(SiteSocial.surrender_willingness(lawful, relation, 40 * 1440).willing): return _fail("守法 100 willing at 40 days")
	var ambitious := body({"ambition": 100})
	if not bool(SiteSocial.surrender_willingness(ambitious, relation, 20 * 1440).willing): return _fail("野心 100 (T 40) willing at 20 days")
	var orphan := relation.duplicate()
	orphan.loyal_org = null
	if bool(SiteSocial.surrender_willingness(neutral, orphan, 99 * 1440).willing): return _fail("No loyal organization never auto-qualifies")
	if bool(SiteSocial.surrender_willingness(neutral, {"version": 2}, 99 * 1440).willing): return _fail("Pre-v3 record rejected")
	print("SITE R3 WILLINGNESS PASS: neutral 60→30 at 30 days (inclusive), 守法 40 days, 野心 20 days, pure candidate, no loyal org / pre-v3 never willing")
	quit(0)
