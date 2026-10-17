extends SceneTree
## G0 (R2 F10/F11): the political day clock advances only on proven days.
## F10: a completed day is evaluated only from its own start-of-day evidence and
## only when observed again the next day; any other completed day since the last
## settlement is recorded as unexecuted (no G/L/obs change, pending events dropped
## and counted). No 60-day skip, no current-state back-fill, no double counting.
## F11: the three-day observation counts proven days from the first proven
## settlement with G >= H (obs_from stamp); a controlled day pauses the omen and
## keeps progress and intent; the NPC resumes the normal rule afterwards.
## Also: save round trip with JSON float normalisation, and an old v2 save loads
## with no proven progress and no error.

const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")
const PP = preload("res://scripts/terrain_lab/person_personality.gd")

var team: Dictionary = SiteSocial.team_ref("s1", 3)

func _initialize() -> void:
	call_deferred("run")

func body() -> Dictionary:
	return {"person_id": 7, "personality": PP.neutral()}

func ctx(minute: int, affiliated: bool = true, controlled: bool = false) -> Dictionary:
	var affiliations: Array = []
	if affiliated: affiliations.append(team)
	return {"minute": minute, "controlled": controlled, "affiliations": affiliations, "captive_relation": {},
		"team_ref": team, "holds_post": true, "eligible_for_post": false}

func entry(person: Dictionary) -> Dictionary:
	return person.social_state.orgs[SiteSocial.org_key(team)]

func run() -> void:
	var failures: Array[String] = []
	for result: String in [_case_gap_recorded_not_evaluated(), _case_no_write_back_mid_day(), _case_backlog_not_skipped(),
		_case_observation_start_and_three_days(), _case_controlled_pauses_and_resumes(), _case_round_trip_normalised(),
		_case_old_v2_save_no_proven_progress(), _case_two_days_not_merged()]:
		if not result.is_empty(): failures.append(result)
	if not failures.is_empty():
		var message := "SITE SOCIAL PROVEN DAY FAIL:"
		for failure: String in failures: message += " [" + failure + "]"
		push_error(message)
		quit(1)
		return
	print("SITE SOCIAL PROVEN DAY PASS: gap recorded not evaluated, start-of-day evidence (no write-back), 99-day backlog recorded not skipped, F11 obs start stamp and three proven days, controlled pause keeps G/L/intent, JSON round trip normalised, v2 save loads with no proven progress, two days not merged")
	quit(0)

## F10: days 1..12 were never observed on both ends; they change nothing and are counted.
func _case_gap_recorded_not_evaluated() -> String:
	var person := body()
	SiteSocial.settle_person(person, ctx(0))
	entry(person).G = 50
	SiteSocial.record(person, team, "gap", 5, "gap-e1", 1440 + 5)
	SiteSocial.settle_person(person, ctx(1440))
	if int(entry(person).G) != 49: return "gap: day 0 proven from its own evidence should decay G to 49, got %d" % int(entry(person).G)
	SiteSocial.settle_person(person, ctx(13 * 1440))
	var unexecuted: Dictionary = person.social_state.unexecuted
	if int(entry(person).G) != 49: return "gap: unexecuted days must not change G, got %d" % int(entry(person).G)
	if int(unexecuted.days) != 12 or int(unexecuted.events) != 1 or not person.social_state.pending.is_empty():
		return "gap: days 1-12 must be recorded as not executed with their event dropped and counted: %s" % str(unexecuted)
	SiteSocial.settle_person(person, ctx(14 * 1440))
	if int(entry(person).G) != 48 or int(person.social_state.settled_day) != 13: return "gap: day 13 proven after its own end observation: G %d settled %d" % [int(entry(person).G), int(person.social_state.settled_day)]
	if not PersonSocial.valid(person.social_state): return "gap: packet invalid"
	return ""

## Start-of-day evidence: leaving the team mid-day is not written back to the day.
func _case_no_write_back_mid_day() -> String:
	var person := body()
	SiteSocial.settle_person(person, ctx(0, true))
	SiteSocial.settle_person(person, ctx(600, false))
	SiteSocial.settle_person(person, ctx(1440, false))
	var loyalty := int(entry(person).L)
	if loyalty != 6050: return "mid-day change: day 0 must use its start-of-day affiliation (serving +50), got L %d" % loyalty
	return ""

## A long gap is recorded as not executed, never skipped silently and never back-filled.
func _case_backlog_not_skipped() -> String:
	var person := body()
	SiteSocial.settle_person(person, ctx(0))
	entry(person).G = 50
	SiteSocial.settle_person(person, ctx(1440))
	var before := int(entry(person).G)
	SiteSocial.settle_person(person, ctx(100 * 1440))
	var unexecuted: Dictionary = person.social_state.unexecuted
	if int(unexecuted.days) != 99 or int(entry(person).G) != before: return "backlog: 99 days must be recorded as not executed, got %s, G %d" % [str(unexecuted), int(entry(person).G)]
	return ""

## F11: the observation starts at the first proven settlement with G >= H (H 70 neutral).
func _case_observation_start_and_three_days() -> String:
	var person := body()
	SiteSocial.settle_person(person, ctx(0))
	entry(person).G = 80
	SiteSocial.settle_person(person, ctx(1440))
	if int(entry(person).obs) != 86400 or int(entry(person).obs_from) != 1440 or bool(entry(person).intent): return "F11 day 1: obs %d from %d" % [int(entry(person).obs), int(entry(person).obs_from)]
	SiteSocial.settle_person(person, ctx(2 * 1440))
	if int(entry(person).obs) != 2 * 86400 or bool(entry(person).intent): return "F11 day 2: two proven days must not form an intent (one second short)"
	SiteSocial.settle_person(person, ctx(3 * 1440))
	if not bool(entry(person).intent) or int(entry(person).obs_from) != 1440: return "F11 day 3: three proven days form the intent, start stamp kept"
	if str(SiteSocial.status(person, team).label) != "已提出離開意向": return "F11: visible label"
	return ""

## Controlled days pause: G/L still settle, but intent and progress are neither cleared nor formed.
func _case_controlled_pauses_and_resumes() -> String:
	var person := body()
	SiteSocial.settle_person(person, ctx(0))
	entry(person).G = 80
	for day in range(1, 4):
		SiteSocial.settle_person(person, ctx(day * 1440))
	if not bool(entry(person).intent): return "controlled setup: intent expected"
	SiteSocial.settle_person(person, ctx(4 * 1440, true, true))
	entry(person).G = 10
	SiteSocial.settle_person(person, ctx(5 * 1440, true, true))
	if not bool(entry(person).intent) or int(entry(person).obs) != 3 * 86400: return "controlled: intent and proven progress must be kept while controlled"
	SiteSocial.settle_person(person, ctx(6 * 1440))
	if not bool(entry(person).intent): return "controlled: the first NPC day after control must not clear the intent yet (day 5 was controlled)"
	SiteSocial.settle_person(person, ctx(7 * 1440))
	if bool(entry(person).intent) or int(entry(person).obs) != 0: return "NPC resumes: G below H−10 on a proven NPC day clears the intent as usual"
	return ""

## Save round trip: JSON floats normalise to integer ids and stamps; settling continues identically.
func _case_round_trip_normalised() -> String:
	var person := body()
	SiteSocial.settle_person(person, ctx(0))
	entry(person).G = 80
	SiteSocial.record(person, team, "x", 3, "rt-e1", 1440 + 1)
	for day in range(1, 4):
		SiteSocial.settle_person(person, ctx(day * 1440))
	var parsed: Variant = JSON.parse_string(JSON.stringify(person.social_state))
	if not PersonSocial.valid(parsed): return "round trip: JSON packet must validate"
	var restored := {"person_id": 7, "personality": PP.neutral(), "social_state": PersonSocial.normalized(parsed)}
	var packet: Dictionary = restored.social_state
	if typeof(packet.evidence.day) != TYPE_INT or typeof(packet.evidence.start) != TYPE_INT or (not packet.proven.is_empty() and typeof(packet.proven.day) != TYPE_INT):
		return "round trip: evidence/proven stamps must be integers after normalisation"
	if typeof(entry(restored).obs_from) != TYPE_INT or typeof(entry(restored).obs) != TYPE_INT: return "round trip: obs stamps must be integers"
	if not PersonSocial.valid(packet): return "round trip: normalised packet invalid"
	SiteSocial.settle_person(person, ctx(4 * 1440))
	SiteSocial.settle_person(restored, ctx(4 * 1440))
	var a := entry(person)
	var b := entry(restored)
	if int(a.G) != int(b.G) or int(a.L) != int(b.L) or int(a.obs) != int(b.obs) or bool(a.intent) != bool(b.intent) or int(a.obs_from) != int(b.obs_from):
		return "round trip: restored settlement differs: %s vs %s" % [str(a), str(b)]
	return ""

## An old v2 save (no evidence, no stamps) loads with no proven progress: unproven
## observation restarts at 0 and no error; G, L, and the formed intent are kept.
func _case_old_v2_save_no_proven_progress() -> String:
	var key := SiteSocial.org_key(team)
	var v2 := {"version": 2, "capture_seq": 0, "settled_day": 4, "no_post_days": 0, "pending": [], "seen": [],
		"orgs": {key: {"ref": {"kind": "team", "site_id": "s1", "org_id": "3"}, "G": 40, "L": 5000, "obs": 86400, "intent": false}}}
	if not PersonSocial.valid(v2): return "old save: v2 packet must still validate"
	var old := {"person_id": 7, "personality": PP.neutral(), "social_state": v2}
	SiteSocial.state_of(old)
	var packet: Dictionary = old.social_state
	if int(packet.version) != 3 or not packet.evidence.is_empty() or not packet.proven.is_empty() or int(packet.unexecuted.days) != 0:
		return "old save: must upgrade to v3 with no proven evidence: %s" % str(packet)
	if int(entry(old).obs) != 0 or int(entry(old).obs_from) != -1 or int(entry(old).G) != 40 or int(entry(old).L) != 5000:
		return "old save: unproven progress must restart at 0, G/L kept: %s" % str(entry(old))
	SiteSocial.settle_person(old, ctx(5 * 1440))
	SiteSocial.settle_person(old, ctx(6 * 1440))
	if int(entry(old).G) != 39 or int(packet.settled_day) != 5 or not PersonSocial.valid(packet): return "old save: day 5 proven on the second observation only"
	return ""

## Two different days of +15 are settled on their own days (cap 20 is per day).
func _case_two_days_not_merged() -> String:
	var person := body()
	SiteSocial.settle_person(person, ctx(0))
	if not SiteSocial.record(person, team, "a", 15, "two-d0", 0): return "two days: record day 0 refused"
	if not SiteSocial.record(person, team, "b", 15, "two-d1", 1440 + 1): return "two days: record day 1 refused"
	SiteSocial.settle_person(person, ctx(1440))
	if int(entry(person).G) != 14: return "two days: day 0 +15 − 1 = 14, got %d" % int(entry(person).G)
	SiteSocial.settle_person(person, ctx(2 * 1440))
	if int(entry(person).G) != 28: return "two days: day 1 +15 − 1 gives 28 (not merged to one cap 20), got %d" % int(entry(person).G)
	return ""
