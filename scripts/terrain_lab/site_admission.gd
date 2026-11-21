extends RefCounted
## R7 D (pure, plan 10.3 with the command-center decisions): admission of a companion invitation after a contest. Decisions:
## disqualified (失格) = captive, or no longer a member of the organization at contest time; a voter is eligible when it is in the
## contest's member list, loaded on the same Site, alive, awake and free (not captive); the effective member set (denominator) is the
## organization's member list at contest open, minus remote (not loaded), dead and disqualified, controlled abstainers included; the
## numerator is the eligible members whose ballot in this contest went to the loser (the loser's own ballot counts if cast);
## unresponsive members are abstainers, not supporters; the rounding is the exact test numerator * 5 >= denominator; a denominator
## of 0 gives no invitation. Admission needs ambition > 70 and lawfulness < 40 (plan 10.3). Each supporter joins only through its
## own departure rule (SiteDepartureDecision, plan 8.4/10.2) and the batch cap (SiteDefectionBatch, 10 per batch).

const Decision = preload("res://scripts/terrain_lab/site_departure_decision.gd")
const Batch = preload("res://scripts/terrain_lab/site_defection_batch.gd")
const AMBITION_MIN_EXCLUSIVE := 70
const LAWFUL_MAX_EXCLUSIVE := 40

## member: {id, loaded, alive, awake, free, captive, in_list, controlled, ballot (0 = none)}
static func disqualified(member: Dictionary) -> bool:
	return bool(member.captive) or not bool(member.in_list)

static func voter_eligible(member: Dictionary) -> bool:
	return bool(member.in_list) and bool(member.loaded) and bool(member.alive) and bool(member.awake) and bool(member.free) and not bool(member.captive)

static func denominator(members: Array) -> int:
	var count := 0
	for member: Dictionary in members:
		if bool(member.loaded) and bool(member.alive) and not disqualified(member): count += 1
	return count

static func numerator(members: Array, loser_id: int) -> int:
	var count := 0
	for member: Dictionary in members:
		if voter_eligible(member) and int(member.ballot) == loser_id: count += 1
	return count

## The admission of a loser's invitation (plan 10.3): the personality gate, then the ratio (exact integer test).
static func admission(ambition: int, lawful: int, members: Array, loser_id: int) -> Dictionary:
	if not (ambition > AMBITION_MIN_EXCLUSIVE and lawful < LAWFUL_MAX_EXCLUSIVE):
		return {"ok": false, "code": "NOT_ADMITTED", "message": "未達同行邀請的野心與守法條件"}
	var total := denominator(members)
	if total == 0:
		return {"ok": false, "code": "NO_RATIO", "message": "有效成員為 0，不作比例"}
	var supporters := numerator(members, loser_id)
	if supporters * 5 < total:
		return {"ok": false, "code": "BELOW_RATIO", "message": "支持者未達有效成員的 20%"}
	return {"ok": true, "code": "", "message": "", "numerator": supporters, "denominator": total}

## The invitation: the supporters that pass their own departure rule and are willing, in stable order, capped at 10 per batch.
## supporter: {id, ambition, lawful, g, intent, observed_days, blocked, controlled, willing, holds_captives, carries_treasury}.
static func invitation(supporters: Array) -> Dictionary:
	var people: Array = []
	for supporter: Dictionary in supporters:
		var decision: Dictionary = Decision.decide(int(supporter.ambition), int(supporter.lawful), int(supporter.g), bool(supporter.intent), int(supporter.observed_days), bool(supporter.blocked), bool(supporter.controlled))
		if str(decision.action) != "depart": continue
		people.append({"id": int(supporter.id), "ambition": int(supporter.ambition), "lawfulness": int(supporter.lawful), "g": int(supporter.g),
			"intent": bool(supporter.intent), "observed_days": int(supporter.observed_days), "blocked": bool(supporter.blocked),
			"controlled": bool(supporter.controlled), "willing": bool(supporter.willing), "holds_captives": bool(supporter.holds_captives), "carries_treasury": bool(supporter.carries_treasury)})
	return Batch.select(people, [])
