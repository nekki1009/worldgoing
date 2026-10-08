extends RefCounted
## Versioned social state on the original person (v2 plan 4.1–4.2): it lives on
## the Army row / Actor and travels with that person's payload, never in a
## second person table. A missing packet means "never captured, no relations"
## and is not written back.
## v1 (R0): only the person's capture sequence.
## v2 (R2): plus per-organization grievance G / loyalty L, leave observation,
## pending day events and their dedupe ids (SiteSocial).

const VERSION := 2
const RANKS := ["commoner", "officer", "head", "unknown"]
const ORG_KINDS := ["team", "nation", "family", "settlement"]
const MAX_ORGS := 16
const MAX_PENDING := 64
const MAX_SEEN := 128

static func valid(packet: Variant) -> bool:
	if not packet is Dictionary or not _integer(packet.get("capture_seq"), 0, 2147483647): return false
	if _integer(packet.get("version"), 1, 1): return packet.size() == 2
	if not _integer(packet.get("version"), 2, 2) or packet.size() != 7: return false
	if not _integer(packet.get("settled_day"), -2, 2147483647) or not _integer(packet.get("no_post_days"), 0, 1000000): return false
	var orgs: Variant = packet.get("orgs")
	if not orgs is Dictionary or orgs.size() > MAX_ORGS: return false
	for key: Variant in orgs:
		var entry: Variant = orgs[key]
		if not key is String or not entry is Dictionary or entry.size() != 5 or not valid_org_ref(entry.get("ref")): return false
		if str(key) != "%s:%s:%s" % [entry.ref.kind, entry.ref.site_id, entry.ref.org_id]: return false
		if not _integer(entry.get("G"), 0, 100) or not _integer(entry.get("L"), 0, 10000) or not _integer(entry.get("obs"), 0, 3 * 86400) or not entry.get("intent") is bool: return false
	var pending: Variant = packet.get("pending")
	if not pending is Array or pending.size() > MAX_PENDING: return false
	for event: Variant in pending:
		if not event is Dictionary or event.size() != 6 or not _integer(event.get("day"), 0, 2147483647) or not event.get("org") is String \
			or not orgs.has(event.org) or not event.get("kind") is String or not _integer(event.get("amount"), -100, 100) \
			or not _integer(event.get("l"), -10000, 10000) or not event.get("id") is String: return false
	var seen: Variant = packet.get("seen")
	if not seen is Array or seen.size() > MAX_SEEN: return false
	for id: Variant in seen:
		if not id is String: return false
	return true

static func read(body: Variant) -> Dictionary:
	var packet: Variant = body.get("social_state", {}) if body is Dictionary else (body.get("social_state") if body is Object else {})
	return packet if packet is Dictionary else {}

static func upgraded(packet: Dictionary) -> Dictionary:
	return {"version": VERSION, "capture_seq": int(packet.get("capture_seq", 0)), "orgs": {}, "settled_day": -2,
		"no_post_days": 0, "pending": [], "seen": []}

## Increments the person's own capture sequence and returns the new value.
static func next_capture_seq(body: Variant) -> int:
	var packet := read(body).duplicate(true)
	if packet.is_empty(): packet = {"version": 1, "capture_seq": 0}
	packet.capture_seq = int(packet.capture_seq) + 1
	if body is Dictionary: body.social_state = packet
	elif body is Object: body.set("social_state", packet)
	return int(packet.capture_seq)

## JSON numbers load as floats; restore integer types (packet already valid).
static func normalized(packet: Dictionary) -> Dictionary:
	var result := packet.duplicate(true)
	for field: String in ["version", "capture_seq", "settled_day", "no_post_days"]:
		if result.has(field): result[field] = int(result[field])
	for entry: Dictionary in result.get("orgs", {}).values():
		for field: String in ["G", "L", "obs"]: entry[field] = int(entry[field])
	for event: Dictionary in result.get("pending", []):
		for field: String in ["day", "amount", "l"]: event[field] = int(event[field])
	return result

static func valid_org_ref(value: Variant) -> bool:
	return value is Dictionary and value.size() == 3 and ORG_KINDS.has(str(value.get("kind", ""))) \
		and value.get("site_id") is String and value.get("org_id") is String and not str(value.org_id).is_empty()

static func _integer(value: Variant, lower: int, upper: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) \
		and float(value) >= lower and float(value) <= upper
