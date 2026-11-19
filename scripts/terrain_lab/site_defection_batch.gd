extends RefCounted
## R7 S1 (pure, plan R6/R7 and 10.2): the group defection batch. Supporters do not follow automatically: each person joins only
## when its own decision is "depart" (its own threshold, SiteDepartureDecision, plan 8.4) and it is willing to go along. A batch
## holds at most BATCH_MAX people in stable person-id order; the rest form the next batch. A person holding captives is not taken
## along, and a person carrying nation treasury is excluded. A duplicate person id refuses the whole selection (no clone). An id
## that already departed is not reused. Commit is all-or-nothing: any invalid member refuses the whole batch.

const Decision = preload("res://scripts/terrain_lab/site_departure_decision.gd")
const BATCH_MAX := 10

## people: Array of dictionaries {id, ambition, lawfulness, g, intent, observed_days, blocked, controlled, willing,
## holds_captives, carries_treasury}. departed: Array of person ids already gone.
static func select(people: Array, departed: Array) -> Dictionary:
	var ordered: Array = people.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	var seen := {}
	var members: Array = []
	var next: Array = []
	var excluded: Array = []
	for person: Dictionary in ordered:
		var id := int(person.id)
		if seen.has(id): return {"ok": false, "code": "DUPLICATE_ID", "message": "同一人不可重複列入", "members": [], "next": [], "excluded": []}
		seen[id] = true
		if departed.has(id):
			excluded.append({"id": id, "code": "ALREADY_DEPARTED"})
			continue
		var decision: Dictionary = Decision.decide(int(person.ambition), int(person.lawfulness), int(person.g), bool(person.intent), int(person.observed_days), bool(person.blocked), bool(person.controlled))
		if str(decision.action) != "depart":
			excluded.append({"id": id, "code": "NOT_DECIDED"})
			continue
		if not bool(person.willing):
			excluded.append({"id": id, "code": "NOT_WILLING"})
			continue
		if bool(person.holds_captives):
			excluded.append({"id": id, "code": "CAPTIVES_HELD"})
			continue
		if bool(person.carries_treasury):
			excluded.append({"id": id, "code": "TREASURY_CARRIED"})
			continue
		if members.size() < BATCH_MAX: members.append(id)
		else: next.append(id)
	return {"ok": true, "code": "", "message": "", "members": members, "next": next, "excluded": excluded}

## validity: person id -> bool from the original-side guards (body, items, supply owners, ship, Actor). Any member that is
## not valid refuses the whole batch; nothing is committed half-way.
static func commit(selection: Dictionary, validity: Dictionary) -> Dictionary:
	for member: Variant in selection.members:
		if not bool(validity.get(int(member), false)):
			return {"ok": false, "code": "BATCH_INVALID", "message": "整批未提交", "committed": [], "failed": int(member)}
	return {"ok": true, "code": "", "message": "", "committed": selection.members.duplicate(), "failed": -1}
