class_name RegionDiplomacy
extends RefCounted
## Diplomacy between factions (FACTION_DIPLOMACY_SPECIFICATION §11). Pure candidates over the faction registry's optional
## `diplomacy` table; RegionSaveSlot owns publication. Relations are not stored: two different active factions are hostile
## unless an active truce or peace treaty joins them (§11.1). The neutral side is never at peace with anyone.
## Table: {version, next_id, treaties {id: treaty}, proposals {id: proposal}, breaches [breach], cooldowns {key: until}}.
## - treaty: {id, a, b, kind ("truce" | "peace"), starts_at, ends_at (null for peace), status ("active" | "ended"), ended_at}
## - proposal: {id, from, to, kind ("truce" | "peace"), days, status, sent_at, deliver_at, reply_deliver_at, accepted, by_ref,
##   reply_ref, reason}. Status: outbound -> delivered -> reply_in_transit -> accepted / rejected; outbound or delivered may
##   become invalidated; delivered past the 7-day reply window becomes expired (§11.4).
## - breach: {id, breaker, victim, at, by_ref, ended_treaties} (§11.5).
const VERSION := 1
const KINDS := ["truce", "peace"]
const TRUCE_MIN_DAYS := 3
const TRUCE_MAX_DAYS := 60
const DAY := 86400.0
const REPLY_WINDOW_DAYS := 7
const REJECT_COOLDOWN_DAYS := 3
const VICTIM_WINDOW_DAYS := 30
const OTHER_WINDOW_DAYS := 10
## Letters travel at the abstract walking speed of RegionTravel (§11.3 baseline): 4000 m per 3600 game seconds.
const MESSAGE_SPEED_MPS := 4000.0 / 3600.0
const TERMINAL := ["accepted", "rejected", "invalidated", "expired"]
## The UI keeps the latest 100 terminal proposals; active ones are never trimmed (§11.8).
const MAX_TERMINAL := 100

static func fail(code: String, message: String = "") -> Dictionary:
	return {"ok": false, "code": code, "message": message}

static func empty() -> Dictionary:
	return {"version": VERSION, "next_id": 1, "treaties": {}, "proposals": {}, "breaches": [], "cooldowns": {}}

static func table(registry: Dictionary) -> Dictionary:
	var value: Variant = registry.get("diplomacy")
	return value if value is Dictionary else empty()

static func pair_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]

static func _pair(record: Dictionary, a: int, b: int) -> bool:
	return pair_key(int(record.a), int(record.b)) == pair_key(a, b)

static func _active_faction(registry: Dictionary, id: int) -> bool:
	return id != RegionFactionQuery.NEUTRAL_FACTION_ID and RegionFactionQuery.active(registry, id).ok

## The active truce or peace between two factions at `now`, or {}.
static func treaty_between(registry: Dictionary, a: int, b: int, now: float) -> Dictionary:
	for treaty: Dictionary in table(registry).treaties.values():
		if treaty.status != "active" or not _pair(treaty, a, b): continue
		if treaty.kind == "truce" and float(treaty.ends_at) <= now: continue
		return treaty
	return {}

static func at_peace(registry: Dictionary, a: int, b: int, now: float) -> bool:
	return a != b and not treaty_between(registry, a, b, now).is_empty()

## §11.1: the same active faction is never hostile to itself (neutral teams excepted); peace or truce ends hostility.
static func hostile(registry: Dictionary, a: int, b: int, now: float) -> bool:
	if RegionFactionQuery.same_side(a, b): return false
	return not at_peace(registry, a, b, now)

## A breacher is refused by its victim for 30 days and by everyone else for 10 (§11.5), half-open windows.
static func in_breach_window(registry: Dictionary, breaker: int, judge: int, now: float) -> bool:
	for breach: Dictionary in table(registry).breaches:
		if int(breach.breaker) != breaker: continue
		var days := VICTIM_WINDOW_DAYS if int(breach.victim) == judge else OTHER_WINDOW_DAYS
		if now >= float(breach.at) and now < float(breach.at) + days * DAY: return true
	return false

static func _candidate(registry: Dictionary) -> Dictionary:
	var candidate: Dictionary = registry.duplicate(true)
	candidate["diplomacy"] = table(registry).duplicate(true)
	candidate.revision = int(candidate.get("revision", 0)) + 1
	return candidate

static func _finish(candidate: Dictionary, now: float, extra: Dictionary = {}) -> Dictionary:
	_trim(candidate.diplomacy)
	var checked: Dictionary = RegionFactionQuery.validate(candidate, now)
	if not checked.ok: return checked
	var result := {"ok": true, "registry": candidate}
	result.merge(extra)
	return result

static func _trim(diplomacy: Dictionary) -> void:
	var terminal: Array = []
	for proposal: Dictionary in diplomacy.proposals.values():
		if proposal.status in TERMINAL: terminal.append(proposal)
	if terminal.size() <= MAX_TERMINAL: return
	terminal.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.id) < int(y.id))
	for index in range(terminal.size() - MAX_TERMINAL): diplomacy.proposals.erase(str(int(terminal[index].id)))

static func _end_pair(diplomacy: Dictionary, a: int, b: int, now: float) -> Array:
	var ended: Array = []
	for treaty: Dictionary in diplomacy.treaties.values():
		if treaty.status == "active" and _pair(treaty, a, b):
			treaty.status = "ended"
			treaty.ended_at = now
			ended.append(int(treaty.id))
	return ended

static func _invalidate_pair(diplomacy: Dictionary, a: int, b: int, reason: String) -> void:
	for proposal: Dictionary in diplomacy.proposals.values():
		if proposal.status not in TERMINAL and _pair({"a": proposal.from, "b": proposal.to}, a, b):
			proposal.status = "invalidated"
			proposal.reason = reason

## §11.5: a head declares war at once. Against a pair at peace it is a breach: every treaty of the pair ends, open letters
## are invalidated, a breach is recorded. Already hostile: unchanged, no breach.
static func declare_war(registry: Dictionary, by_faction: int, target: int, by_ref: Variant, now: float) -> Dictionary:
	if not _active_faction(registry, by_faction) or not _active_faction(registry, target) or by_faction == target: return fail("INVALID", "雙方須是不同的有效勢力（中立不能宣戰）")
	if not at_peace(registry, by_faction, target, now): return {"ok": true, "registry": registry, "breach": false, "changed": false}
	var candidate := _candidate(registry)
	var diplomacy: Dictionary = candidate.diplomacy
	var ended := _end_pair(diplomacy, by_faction, target, now)
	_invalidate_pair(diplomacy, by_faction, target, "WAR_DECLARED")
	var id := int(diplomacy.next_id)
	diplomacy.next_id = id + 1
	diplomacy.breaches.append({"id": id, "breaker": by_faction, "victim": target, "at": now, "by_ref": by_ref, "ended_treaties": ended})
	return _finish(candidate, now, {"breach": true, "changed": true})

## Distance in metres between two Region positions (cells of RegionGrid metres), 0 in the same Site.
static func delay_seconds(distance_m: float) -> float:
	return maxf(0.0, distance_m) / MESSAGE_SPEED_MPS

## §11.4 step 1: a head proposes a truce (3..60 days) or peace. One open letter per unordered pair and kind; a rejection
## puts the pair and kind on a 3-day cooldown. Truce and peace need the pair hostile and not fighting (caller checks combat).
static func propose(registry: Dictionary, from: int, to: int, kind: String, days: int, by_ref: Variant, distance_m: float, now: float) -> Dictionary:
	if not _active_faction(registry, from) or not _active_faction(registry, to) or from == to: return fail("INVALID", "雙方須是不同的有效勢力（中立不能外交）")
	if kind not in KINDS: return fail("INVALID", "未開放的提議種類")
	if kind == "truce" and (days < TRUCE_MIN_DAYS or days > TRUCE_MAX_DAYS): return fail("INVALID", "停戰須 3–60 日")
	var current := treaty_between(registry, from, to, now)
	if kind == "truce" and not current.is_empty(): return fail("ALREADY_AT_PEACE", "雙方已在和平中")
	if kind == "peace" and not current.is_empty() and current.kind == "peace": return fail("ALREADY_AT_PEACE", "雙方已講和")
	var diplomacy := table(registry)
	var key := pair_key(from, to) + ":" + kind
	if float(diplomacy.cooldowns.get(key, -1.0)) > now: return fail("COOLDOWN", "對方剛拒絕過，3 日內不能再提")
	for proposal: Dictionary in diplomacy.proposals.values():
		if proposal.status not in TERMINAL and proposal.kind == kind and _pair({"a": proposal.from, "b": proposal.to}, from, to): return fail("PENDING", "同一提議仍在往返中")
	var candidate := _candidate(registry)
	var id := int(candidate.diplomacy.next_id)
	candidate.diplomacy.next_id = id + 1
	candidate.diplomacy.proposals[str(id)] = {"id": id, "from": from, "to": to, "kind": kind, "days": days if kind == "truce" else 0,
		"status": "outbound", "sent_at": now, "deliver_at": now + delay_seconds(distance_m), "reply_deliver_at": null, "accepted": null,
		"by_ref": by_ref, "reply_ref": null, "reason": ""}
	return _finish(candidate, now, {"proposal_id": id})

## §11.4 step 3: the receiving head replies within 7 days of delivery. The answer travels back with the same delay rule.
static func reply(registry: Dictionary, proposal_id: int, accept: bool, by_ref: Variant, distance_m: float, now: float) -> Dictionary:
	var proposal: Dictionary = table(registry).proposals.get(str(proposal_id), {})
	if proposal.is_empty(): return fail("NO_TARGET", "找不到這封信")
	var settled := settle(registry, now)
	proposal = settled.registry.diplomacy.proposals.get(str(proposal_id), {}) if settled.ok else proposal
	if proposal.status != "delivered": return fail("NOT_DELIVERED", "這封信目前不能回覆（%s）" % str(proposal.status))
	var candidate := _candidate(settled.registry)
	var mine: Dictionary = candidate.diplomacy.proposals[str(proposal_id)]
	mine.status = "reply_in_transit"
	mine.accepted = accept
	mine.reply_ref = by_ref
	mine.reply_deliver_at = now + delay_seconds(distance_m)
	return _finish(candidate, now)

## Advances letters and treaties to `now` (lazy endpoints): deliveries, reply windows, answers arriving, truce expiry.
## An accepted answer takes effect only if the pair is still hostile-or-truce as proposed and both factions are active.
static func settle(registry: Dictionary, now: float) -> Dictionary:
	var changed := false
	var candidate := _candidate(registry)
	var work: Dictionary = candidate.diplomacy
	var ids: Array = work.proposals.keys()
	ids.sort_custom(func(x: Variant, y: Variant) -> bool: return int(x) < int(y))
	for id: Variant in ids:
		var proposal: Dictionary = work.proposals[id]
		if proposal.status == "outbound" and now >= float(proposal.deliver_at):
			proposal.status = "delivered"
			changed = true
		if proposal.status == "delivered" and now >= float(proposal.deliver_at) + REPLY_WINDOW_DAYS * DAY:
			proposal.status = "expired"
			changed = true
		if proposal.status == "reply_in_transit" and now >= float(proposal.reply_deliver_at):
			changed = true
			var a := int(proposal.from)
			var b := int(proposal.to)
			if not bool(proposal.accepted):
				proposal.status = "rejected"
				work.cooldowns[pair_key(a, b) + ":" + str(proposal.kind)] = float(proposal.reply_deliver_at) + REJECT_COOLDOWN_DAYS * DAY
				continue
			if not _active_faction(candidate, a) or not _active_faction(candidate, b):
				proposal.status = "invalidated"
				proposal.reason = "FACTION_GONE"
				continue
			var start := float(proposal.reply_deliver_at)
			if proposal.kind == "peace": _end_pair(work, a, b, start) # peace replaces a running truce
			var id_treaty := int(work.next_id)
			work.next_id = id_treaty + 1
			work.treaties[str(id_treaty)] = {"id": id_treaty, "a": mini(a, b), "b": maxi(a, b), "kind": proposal.kind, "starts_at": start,
				"ends_at": start + float(proposal.days) * DAY if proposal.kind == "truce" else null, "status": "active", "ended_at": null}
			proposal.status = "accepted"
	for treaty: Dictionary in work.treaties.values():
		if treaty.status == "active" and treaty.kind == "truce" and float(treaty.ends_at) <= now:
			treaty.status = "ended"
			treaty.ended_at = float(treaty.ends_at)
			changed = true
	if not changed: return {"ok": true, "registry": registry, "changed": false}
	var finished := _finish(candidate, now)
	if finished.ok: finished["changed"] = true
	return finished

## Structural validation of the optional table (RegionFactionQuery.validate calls it).
static func validate(value: Variant, registry: Dictionary, now: float) -> Dictionary:
	var fields: Array = ["version", "next_id", "treaties", "proposals", "breaches", "cooldowns"]
	if value is Dictionary and value.has("falls"): fields.append("falls")
	if not value is Dictionary or not RegionFactionQuery.keys(value, fields): return fail("CORRUPT_SAVE", "diplomacy fields")
	if value.has("falls"):
		if not value.falls is Dictionary: return fail("CORRUPT_SAVE", "diplomacy falls")
		for site_id: Variant in value.falls:
			var fall: Variant = value.falls[site_id]
			if not site_id is String or not fall is Dictionary or not RegionFactionQuery.keys(fall, ["owner", "lost_by", "at"]) or not fall.lost_by is Array or float(fall.at) > now: return fail("CORRUPT_SAVE", "diplomacy fall record")
	if not RegionFactionQuery.whole(value.version, VERSION, VERSION) or not RegionFactionQuery.whole(value.next_id, 1, RegionFactionQuery.MAX_REVISION): return fail("CORRUPT_SAVE", "diplomacy version")
	if not value.treaties is Dictionary or not value.proposals is Dictionary or not value.breaches is Array or not value.cooldowns is Dictionary: return fail("CORRUPT_SAVE", "diplomacy tables")
	for key: Variant in value.treaties:
		var treaty: Variant = value.treaties[key]
		if not treaty is Dictionary or not RegionFactionQuery.keys(treaty, ["id", "a", "b", "kind", "starts_at", "ends_at", "status", "ended_at"]) or str(int(treaty.id)) != str(key) or int(treaty.id) >= int(value.next_id): return fail("CORRUPT_SAVE", "diplomacy treaty")
		if treaty.kind not in KINDS or treaty.status not in ["active", "ended"] or int(treaty.a) >= int(treaty.b): return fail("CORRUPT_SAVE", "diplomacy treaty kind")
		if (treaty.kind == "truce") != (treaty.ends_at != null): return fail("CORRUPT_SAVE", "diplomacy treaty end")
		if treaty.status == "active" and not (_active_faction(registry, int(treaty.a)) and _active_faction(registry, int(treaty.b))): return fail("CORRUPT_SAVE", "diplomacy treaty faction")
	for key: Variant in value.proposals:
		var proposal: Variant = value.proposals[key]
		if not proposal is Dictionary or not RegionFactionQuery.keys(proposal, ["id", "from", "to", "kind", "days", "status", "sent_at", "deliver_at", "reply_deliver_at", "accepted", "by_ref", "reply_ref", "reason"]) or str(int(proposal.id)) != str(key) or int(proposal.id) >= int(value.next_id): return fail("CORRUPT_SAVE", "diplomacy proposal")
		if proposal.kind not in KINDS or proposal.status not in ["outbound", "delivered", "reply_in_transit"] + TERMINAL: return fail("CORRUPT_SAVE", "diplomacy proposal status")
		if float(proposal.deliver_at) < float(proposal.sent_at) or float(proposal.sent_at) > now: return fail("CORRUPT_SAVE", "diplomacy proposal time")
	for breach: Variant in value.breaches:
		if not breach is Dictionary or not RegionFactionQuery.keys(breach, ["id", "breaker", "victim", "at", "by_ref", "ended_treaties"]) or float(breach.at) > now: return fail("CORRUPT_SAVE", "diplomacy breach")
	return {"ok": true}

## JSON-loaded numbers are floats; ids and factions back to int.
static func canonical(value: Dictionary) -> Dictionary:
	var result: Dictionary = value.duplicate(true)
	result.version = int(result.get("version", VERSION))
	result.next_id = int(result.get("next_id", 1))
	for treaty: Dictionary in result.get("treaties", {}).values():
		for field: String in ["id", "a", "b"]: treaty[field] = int(treaty[field])
	for proposal: Dictionary in result.get("proposals", {}).values():
		for field: String in ["id", "from", "to", "days"]: proposal[field] = int(proposal[field])
		if proposal.by_ref is Dictionary: proposal.by_ref = RegionPeerage.canonical_ref(proposal.by_ref)
		if proposal.reply_ref is Dictionary: proposal.reply_ref = RegionPeerage.canonical_ref(proposal.reply_ref)
	for fall: Dictionary in result.get("falls", {}).values():
		fall.owner = int(fall.owner)
		fall.at = float(fall.at)
		var lost: Array = []
		for faction: Variant in fall.lost_by: lost.append(int(faction))
		fall.lost_by = lost
	for breach: Dictionary in result.get("breaches", []):
		for field: String in ["id", "breaker", "victim"]: breach[field] = int(breach[field])
		var ended: Array = []
		for id: Variant in breach.get("ended_treaties", []): ended.append(int(id))
		breach.ended_treaties = ended
		if breach.by_ref is Dictionary: breach.by_ref = RegionPeerage.canonical_ref(breach.by_ref)
	return result

## The earliest pending endpoint (delivery, reply window, answer arrival, truce end) after `now`, or INF.
static func next_event_at(registry: Dictionary, now: float) -> float:
	var next := INF
	var diplomacy := table(registry)
	for proposal: Dictionary in diplomacy.proposals.values():
		match str(proposal.status):
			"outbound": next = minf(next, float(proposal.deliver_at))
			"delivered": next = minf(next, float(proposal.deliver_at) + REPLY_WINDOW_DAYS * DAY)
			"reply_in_transit": next = minf(next, float(proposal.reply_deliver_at))
	for treaty: Dictionary in diplomacy.treaties.values():
		if treaty.status == "active" and treaty.kind == "truce": next = minf(next, float(treaty.ends_at))
	return next

## --- Settlement falls (§11.6 收復宣戰: "沿原 fall_to 成功收據更新追索紀錄") ---
## Each fall records the new owner and adds the loser to the site's lost_by list; retaking a site removes the
## retaker from it. Only falls proven by fall_to after this record existed are known; nothing is inferred.
static func record_fall(registry: Dictionary, site_id: String, from: int, to: int, now: float) -> Dictionary:
	if site_id.is_empty() or from == to: return {"ok": true, "registry": registry, "changed": false}
	var candidate := _candidate(registry)
	var falls: Dictionary = candidate.diplomacy.get("falls", {})
	var fall: Dictionary = falls.get(site_id, {"owner": to, "lost_by": [], "at": now})
	var lost: Array = fall.lost_by.duplicate()
	if from >= 0 and from != RegionFactionQuery.NEUTRAL_FACTION_ID and not lost.has(from): lost.append(from)
	lost.erase(to)
	falls[site_id] = {"owner": to, "lost_by": lost, "at": now}
	candidate.diplomacy["falls"] = falls
	return _finish(candidate, now, {"changed": true})

## Does `other` hold a settlement that fell from `me` (and that `me` has not retaken)?
static func holds_fallen_of(registry: Dictionary, me: int, other: int) -> bool:
	for fall: Dictionary in table(registry).get("falls", {}).values():
		if int(fall.owner) == other and fall.lost_by.has(me): return true
	return false
