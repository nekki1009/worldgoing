extends RefCounted
## T6 S3: pure treaty-rate lookup (trade-plan Q12 A). No Region Slot read and no Site read.
## F2/F6 will supply the inputs from the Region Slot (faction-plan §11.8):
##   relation  = faction_relations[pair_key(a, b)] ("peace" or "hostile"; an unrecorded pair is hostile)
##   treaty    = the trade entry of diplomacy.treaties for that pair, or null when none is signed
## Q12 A: peace allows every face-to-face trade. A trade agreement only changes the tax percent.
## Expiry or revocation returns the trade to the peace baseline; it never bans trade.
## Hostile (war, or no recorded peace) refuses trade. Nothing here moves goods or writes state.

const VERSION := 1
const TRADE_TAX_MAX := 50
const MAX_FACTION := 100000000
const MAX_MINUTE := 2147483646
const RELATIONS := ["peace", "hostile"]
const TREATY_FIELDS := ["kind", "a", "b", "tax_percent", "expires_minute", "signed_minute", "status"]
const TREATY_STATUSES := ["active", "revoked"]

static func fail(code: String, message: String = "") -> Dictionary:
	return {"ok": false, "code": code, "message": message}

static func ok(state: String, tax_percent: int) -> Dictionary:
	return {"ok": true, "code": "OK", "state": state, "tax_percent": tax_percent}

static func _int(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) \
		and float(value) >= float(low) and float(value) <= float(high)

## Order-insensitive key for a faction pair; the same key is used for faction_relations and treaties.
static func pair_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]

## Relation between two factions. Same faction is peace (never hostile to itself, faction-plan §11.2).
## An unrecorded pair is hostile (trade-plan §5.5). Any recorded value must be a known relation.
static func relation_of(faction_relations: Variant, a: Variant, b: Variant) -> Dictionary:
	if not _int(a, 0, MAX_FACTION) or not _int(b, 0, MAX_FACTION): return fail("INVALID", "勢力編號")
	if int(a) == int(b): return {"ok": true, "code": "OK", "relation": "peace"}
	if not faction_relations is Dictionary: return fail("INVALID", "勢力關係表")
	var key: String = pair_key(int(a), int(b))
	if not faction_relations.has(key): return {"ok": true, "code": "OK", "relation": "hostile"}
	var stored: Variant = faction_relations[key]
	if not stored is String or str(stored) not in RELATIONS: return fail("INVALID", "未知勢力關係")
	return {"ok": true, "code": "OK", "relation": str(stored)}

## Strict shape of one trade entry of diplomacy.treaties (exact keys; kind "trade").
static func valid_trade_treaty(entry: Variant) -> bool:
	if not entry is Dictionary or entry.size() != TREATY_FIELDS.size(): return false
	for field: String in TREATY_FIELDS:
		if not entry.has(field): return false
	if entry.kind != "trade" or not _int(entry.a, 0, MAX_FACTION) or not _int(entry.b, 0, MAX_FACTION) or int(entry.a) >= int(entry.b): return false
	if not _int(entry.tax_percent, 0, TRADE_TAX_MAX): return false
	if not _int(entry.signed_minute, 0, MAX_MINUTE): return false
	if not _int(entry.expires_minute, -1, MAX_MINUTE): return false
	if int(entry.expires_minute) >= 0 and int(entry.expires_minute) <= int(entry.signed_minute): return false
	return str(entry.status) in TREATY_STATUSES

## Trade terms for one pair at one minute. `base_percent` is the settlement's own rate (S2).
## States: "hostile" is refused; "none" (never signed), "expired", "revoked" use the base rate;
## "active" uses the treaty rate. Expiry at minute == expires_minute counts as expired.
static func trade_terms(relation: Variant, treaty: Variant, base_percent: Variant, minute: Variant) -> Dictionary:
	if not relation is String or str(relation) not in RELATIONS: return fail("INVALID", "未知勢力關係")
	if not _int(base_percent, 0, TRADE_TAX_MAX) or not _int(minute, 0, MAX_MINUTE): return fail("INVALID", "基準稅率或時刻")
	if str(relation) == "hostile": return fail("HOSTILE", "敵對勢力之間不可交易")
	if treaty == null: return ok("none", int(base_percent))
	if not valid_trade_treaty(treaty): return fail("INVALID", "通商協定格式")
	if int(minute) < int(treaty.signed_minute): return fail("INVALID", "協定尚未生效")
	if treaty.status == "revoked": return ok("revoked", int(base_percent))
	if int(treaty.expires_minute) >= 0 and int(minute) >= int(treaty.expires_minute): return ok("expired", int(base_percent))
	return ok("active", int(treaty.tax_percent))
