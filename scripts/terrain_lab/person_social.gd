extends RefCounted
## Versioned social state on the original person (v2 plan 4.1–4.2): it lives on
## the Army row / Actor and travels with that person's payload, never in a
## second person table. A missing packet means "never captured, no relations"
## and is not written back.
## v1 (R0): only the person's capture sequence.
## v2 (R2): plus per-organization grievance G / loyalty L, leave observation,
## pending day events and their dedupe ids (SiteSocial).
## v3 (G0 F10/F11): plus the start-of-day evidence of the last observed political
## day, the last proven day's start/end stamps, the unexecuted-day counter, and
## per-organization observation start (obs_from). v2 loads with no proven progress.

const VERSION := 3
const RANKS := ["commoner", "officer", "head", "unknown"]
const ORG_KINDS := ["team", "nation", "family", "settlement"]
const MAX_ORGS := 16
const MAX_PENDING := 64
const MAX_SEEN := 128

static func valid(packet: Variant) -> bool:
	if not packet is Dictionary or not _integer(packet.get("capture_seq"), 0, 2147483647): return false
	if _integer(packet.get("version"), 1, 1): return packet.size() == 2
	if _integer(packet.get("version"), 2, 2): return _valid_common(packet, 7, 5) and not packet.has("evidence")
	if not _integer(packet.get("version"), 3, 3) or packet.size() != 10: return false
	if not _valid_common(packet, 10, 6): return false
	if not _valid_evidence(packet.get("evidence")) or not _valid_proven(packet.get("proven")): return false
	var unexecuted: Variant = packet.get("unexecuted")
	return unexecuted is Dictionary and unexecuted.size() == 2 and _integer(unexecuted.get("days"), 0, 2147483647) and _integer(unexecuted.get("events"), 0, 2147483647)

static func _valid_common(packet: Dictionary, size: int, entry_size: int) -> bool:
	if not _integer(packet.get("settled_day"), -2, 2147483647) or not _integer(packet.get("no_post_days"), 0, 1000000): return false
	var orgs: Variant = packet.get("orgs")
	if not orgs is Dictionary or orgs.size() > MAX_ORGS: return false
	for key: Variant in orgs:
		var entry: Variant = orgs[key]
		if not key is String or not entry is Dictionary or entry.size() != entry_size or not valid_org_ref(entry.get("ref")): return false
		if str(key) != "%s:%s:%s" % [entry.ref.kind, entry.ref.site_id, entry.ref.org_id]: return false
		if not _integer(entry.get("G"), 0, 100) or not _integer(entry.get("L"), 0, 10000) or not _integer(entry.get("obs"), 0, 3 * 86400) or not entry.get("intent") is bool: return false
		if entry_size == 6 and not _integer(entry.get("obs_from"), -1, 2147483647): return false
	var pending: Variant = packet.get("pending")
	if not pending is Array or pending.size() > MAX_PENDING: return false
	for event: Variant in pending:
		if not event is Dictionary or event.size() != 6 or not _integer(event.get("day"), 0, 2147483647) or not event.get("org") is String 			or not orgs.has(event.org) or not event.get("kind") is String or not _integer(event.get("amount"), -100, 100) 			or not _integer(event.get("l"), -10000, 10000) or not event.get("id") is String: return false
	var seen: Variant = packet.get("seen")
	if not seen is Array or seen.size() > MAX_SEEN: return false
	for id: Variant in seen:
		if not id is String: return false
	return packet.size() == size

## Start-of-day evidence of the last observed day: empty, or the eight fields
## recorded at its first observation (affiliations, captivity, post, eligibility, control, team).
static func _valid_evidence(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if value.size() != 8 or not _integer(value.get("day"), 0, 2147483647) or not _integer(value.get("start"), 0, 2147483647): return false
	var affiliations: Variant = value.get("affiliations")
	if not affiliations is Array or affiliations.size() > MAX_ORGS: return false
	for ref: Variant in affiliations:
		if not valid_org_ref(ref): return false
	for field: String in ["captive", "controlled", "holds_post", "eligible_for_post"]:
		if not value.get(field) is bool: return false
	var team: Variant = value.get("team_ref")
	return team is Dictionary and (team.is_empty() or valid_org_ref(team))

## Stamps of the last proven political day (day, start minute, end minute), or empty.
static func _valid_proven(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	return value.size() == 3 and _integer(value.get("day"), 0, 2147483647) and _integer(value.get("start"), 0, 2147483647) and _integer(value.get("end"), 0, 2147483647)

static func read(body: Variant) -> Dictionary:
	var packet: Variant = body.get("social_state", {}) if body is Dictionary else (body.get("social_state") if body is Object else {})
	return packet if packet is Dictionary else {}

static func upgraded(packet: Dictionary) -> Dictionary:
	return {"version": VERSION, "capture_seq": int(packet.get("capture_seq", 0)), "orgs": {}, "settled_day": -2,
		"no_post_days": 0, "pending": [], "seen": [], "evidence": {}, "proven": {}, "unexecuted": {"days": 0, "events": 0}}

## v2 → v3: keeps every v2 field; no proven political day exists yet, so the
## evidence is empty, existing observation has no recorded start (obs_from -1) and
## unproven progress (obs) restarts at 0 unless an intent was already formed.
static func migrated_v2(packet: Dictionary) -> Dictionary:
	var result := packet.duplicate(true)
	result["version"] = VERSION
	result["evidence"] = {}
	result["proven"] = {}
	result["unexecuted"] = {"days": 0, "events": 0}
	for entry: Dictionary in result.orgs.values():
		entry.obs_from = -1
		if not bool(entry.intent): entry.obs = 0 # Unproven observation progress is not carried over; a formed intent stays.
	return result

## Increments the person's own capture sequence and returns the new value.
static func next_capture_seq(body: Variant) -> int:
	var packet := read(body).duplicate(true)
	if packet.is_empty(): packet = {"version": 1, "capture_seq": 0}
	packet["capture_seq"] = int(packet.capture_seq) + 1
	if body is Dictionary: body.social_state = packet
	elif body is Object: body.set("social_state", packet)
	return int(packet.capture_seq)

## JSON numbers load as floats; restore integer types (packet already valid).
static func normalized(packet: Dictionary) -> Dictionary:
	var result := packet.duplicate(true)
	for field: String in ["version", "capture_seq", "settled_day", "no_post_days"]:
		if result.has(field): result[field] = int(result[field])
	for entry: Dictionary in result.get("orgs", {}).values():
		for field: String in ["G", "L", "obs", "obs_from"]:
			if entry.has(field): entry[field] = int(entry[field])
	for event: Dictionary in result.get("pending", []):
		for field: String in ["day", "amount", "l"]: event[field] = int(event[field])
	if result.get("evidence", {}).is_empty() == false:
		for field: String in ["day", "start"]: result.evidence[field] = int(result.evidence[field])
	if result.get("proven", {}).is_empty() == false:
		for field: String in ["day", "start", "end"]: result.proven[field] = int(result.proven[field])
	if result.has("unexecuted"):
		for field: String in ["days", "events"]: result.unexecuted[field] = int(result.unexecuted[field])
	return result

static func valid_org_ref(value: Variant) -> bool:
	return value is Dictionary and value.size() == 3 and ORG_KINDS.has(str(value.get("kind", ""))) \
		and value.get("site_id") is String and value.get("org_id") is String and not str(value.org_id).is_empty()

static func _integer(value: Variant, lower: int, upper: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) \
		and float(value) >= lower and float(value) <= upper
