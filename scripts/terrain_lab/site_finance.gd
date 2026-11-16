extends RefCounted
## Organization finance records (軍餉與稅收 P0, reports/pay-and-tax-plan.md §2, §8; Nekki 2026-11-09 都依建議). Data only:
## no payment, tax, tribute or event code yet (P1–P3). Site section `finance` {org_key → record}, org_key as
## SiteSocial.org_key of a team, settlement or nation (a family is not an employer). A missing section or record means
## "no tax levied, no pay source bound, 1.0× pay" (§8 old-save rule), so old saves need no migration.
## Record v1: {version, ref, since_day, pay_source, tax_source, treasury, pay_rate, tax_rate, last_payday, last_taxday,
## tax_lord, auto_fund, exemptions, served, accrued_day, tax_carry, receipts}.
## - ref: the organization's {kind, site_id, org_id}; the key must be its org_key.
## - since_day: the calendar day the record began; arrears events start GRACE_DAYS after it (PT-14).
## - pay_source / tax_source / treasury: {} (unbound) or a holder reference {kind "stock", site_id, feature_id} (a Site
##   stockpile) or {kind "vehicle", site_id, vehicle_id} (a vehicle hold). One small organization may name the same holder
##   for all three; no holder may be bound by two organizations (§2). Camp `site.inventory` is never a source.
## - pay_rate: percent from SitePayTable.PAY_RATES; tax_rate: percent from SitePayTable.TAX_RATES.
## - last_payday: the payday index (months since the epoch) last settled, -1 none; last_taxday: the season index, -1 none.
## - tax_lord: {} or {kind "nation"|"person", id} the tribute goes to (§4.3); auto_fund: the nation/lord funds its
##   teams' pay (§3.4); exemptions: season indexes the head waived (§4.3), sorted, unique.
## - served: {person_id → days} eligible days in the current pay period (§3.3 step 1: pay in proportion to days served;
##   captivity and incapacity days do not count); accrued_day: the last calendar day counted, -1 none.
## - tax_carry: {feature_id → {resource → n}} a settlement's production tax remainders: amount × rate accumulates in
##   hundredths and every full hundred is one whole unit taxed (§4.2: no fraction of an item is taken; it carries).
## - receipts: {season, current, previous} season totals in tenths of a point per receipt kind (RECEIPT_KINDS); a new
##   season moves current to previous (§8: only this season and the last are kept). Totals, never a balance.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const PayTable = preload("res://scripts/terrain_lab/site_pay_table.gd")

const VERSION := 1
const KINDS := ["team", "settlement", "nation"]
const SOURCE_KINDS := ["stock", "vehicle"]
const LORD_KINDS := ["nation", "person"]
const MAX_RECORDS := 256
const MAX_EXEMPTIONS := 16
const MAX_SERVED := 20000
const MAX_CARRY_FEATURES := 512
const RECEIPT_KINDS := ["produce_tax", "market", "tariff", "tribute_in", "tribute_out", "pay", "fund"]
const FIELDS := ["version", "ref", "since_day", "pay_source", "tax_source", "treasury", "pay_rate", "tax_rate",
	"last_payday", "last_taxday", "tax_lord", "auto_fund", "exemptions", "served", "accrued_day", "tax_carry", "receipts"]

static func org_key(ref: Dictionary) -> String:
	return "%s:%s:%s" % [str(ref.kind), str(ref.site_id), str(ref.org_id)]

## A fresh record: nothing bound, no tax levied, 1.0× pay. A nation funds its teams by default (§9).
static func empty_record(ref: Dictionary, day: int) -> Dictionary:
	return {"version": VERSION, "ref": ref.duplicate(), "since_day": maxi(0, day), "pay_source": {}, "tax_source": {},
		"treasury": {}, "pay_rate": 100, "tax_rate": 0, "last_payday": -1, "last_taxday": -1, "tax_lord": {},
		"auto_fund": str(ref.get("kind", "")) == "nation", "exemptions": [], "served": {}, "accrued_day": -1,
		"tax_carry": {}, "receipts": {"season": -1, "current": {}, "previous": {}}}

static func records(data: TerrainData) -> Dictionary:
	var value: Variant = data.site.get("finance", {}) if data != null else {}
	return value if value is Dictionary else {}

## The organization's record, or the default record (not stored) when it has none.
static func record_of(data: TerrainData, ref: Dictionary, day: int) -> Dictionary:
	var found: Variant = records(data).get(org_key(ref))
	return found if found is Dictionary else empty_record(ref, day)

## The stored record, created on first use.
static func ensure(data: TerrainData, ref: Dictionary, day: int) -> Dictionary:
	if not valid_ref(ref): return Runtime.fail("INVALID", "財政紀錄的組織引用")
	if not data.site.has("finance"): data.site["finance"] = {}
	var key := org_key(ref)
	if not data.site.finance.has(key):
		if data.site.finance.size() >= MAX_RECORDS: return Runtime.fail("FULL", "財政紀錄已滿")
		data.site.finance[key] = empty_record(ref, day)
	return Runtime.ok("", {"record": data.site.finance[key]})

## Days before an organization's first arrears event (PT-14): 0 once the grace has passed.
static func grace_left(record: Dictionary, day: int) -> int:
	return maxi(0, int(record.since_day) + PayTable.GRACE_DAYS - day)

static func valid_ref(ref: Variant) -> bool:
	return ref is Dictionary and ref.size() == 3 and KINDS.has(str(ref.get("kind", ""))) and ref.get("site_id") is String \
		and ref.get("org_id") is String and not str(ref.org_id).is_empty()

static func valid_source(source: Variant) -> bool:
	if not source is Dictionary: return false
	if source.is_empty(): return true
	if source.size() != 3 or not SOURCE_KINDS.has(str(source.get("kind", ""))) or not source.get("site_id") is String or str(source.site_id).is_empty(): return false
	var field := "feature_id" if str(source.kind) == "stock" else "vehicle_id"
	return source.get(field) is String and not str(source[field]).is_empty()

static func source_key(source: Dictionary) -> String:
	return "%s:%s:%s" % [str(source.kind), str(source.site_id), str(source.get("feature_id", source.get("vehicle_id", "")))]

static func valid_lord(lord: Variant) -> bool:
	if not lord is Dictionary: return false
	if lord.is_empty(): return true
	return lord.size() == 2 and LORD_KINDS.has(str(lord.get("kind", ""))) and lord.get("id") is String and not str(lord.id).is_empty()

static func _integer(value: Variant, lower: int, upper: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) \
		and float(value) >= lower and float(value) <= upper

static func valid_record(key: Variant, record: Variant) -> bool:
	if not key is String or not record is Dictionary or record.size() != FIELDS.size(): return false
	for field: String in FIELDS:
		if not record.has(field): return false
	if not _integer(record.version, VERSION, VERSION) or not valid_ref(record.ref) or org_key(record.ref) != key: return false
	if not _integer(record.since_day, 0, 2147483646) or not _integer(record.last_payday, -1, 2147483646) or not _integer(record.last_taxday, -1, 2147483646): return false
	if not PayTable.valid_pay_rate(record.pay_rate) or not PayTable.valid_tax_rate(record.tax_rate): return false
	for field: String in ["pay_source", "tax_source", "treasury"]:
		if not valid_source(record[field]): return false
	if not valid_lord(record.tax_lord) or not record.auto_fund is bool or not record.exemptions is Array or record.exemptions.size() > MAX_EXEMPTIONS: return false
	var previous := -1
	for season: Variant in record.exemptions:
		if not _integer(season, 0, 2147483646) or int(season) <= previous: return false
		previous = int(season)
	if not _integer(record.accrued_day, -1, 2147483646) or not record.served is Dictionary or record.served.size() > MAX_SERVED: return false
	for identity: Variant in record.served:
		if not identity is String or not str(identity).is_valid_int() or int(identity) <= 0 or not _integer(record.served[identity], 1, 31): return false
	if not record.tax_carry is Dictionary or record.tax_carry.size() > MAX_CARRY_FEATURES: return false
	for feature_id: Variant in record.tax_carry:
		var carry: Variant = record.tax_carry[feature_id]
		if not feature_id is String or str(feature_id).is_empty() or not carry is Dictionary or carry.is_empty(): return false
		for resource: Variant in carry:
			if not resource is String or str(resource).is_empty() or not _integer(carry[resource], 1, 99): return false
	return valid_receipts(record.receipts)

static func valid_receipts(receipts: Variant) -> bool:
	if not receipts is Dictionary or receipts.size() != 3 or not _integer(receipts.get("season"), -1, 2147483646): return false
	for field: String in ["current", "previous"]:
		var totals: Variant = receipts.get(field)
		if not totals is Dictionary: return false
		for kind: Variant in totals:
			if not RECEIPT_KINDS.has(kind) or not _integer(totals[kind], 1, 2000000000): return false
	return true

## Adds `tenths` of a point of `kind` to the record's season totals, rolling the season first when it changed.
static func add_receipt(record: Dictionary, kind: String, tenths: int, season: int) -> void:
	var receipts: Dictionary = record.receipts
	if int(receipts.season) != season:
		receipts["previous"] = receipts.current.duplicate() if int(receipts.season) == season - 1 else {}
		receipts["current"] = {}
		receipts["season"] = season
	if tenths > 0: receipts.current[kind] = mini(2000000000, int(receipts.current.get(kind, 0)) + tenths)

## This season's (or, with `previous`, the last season's) receipts of `kind` in tenths, as of `season`.
static func receipts_of(record: Dictionary, kind: String, season: int, previous: bool = false) -> int:
	var receipts: Dictionary = record.get("receipts", {})
	var stored := int(receipts.get("season", -1))
	if previous:
		if stored == season: return int(receipts.get("previous", {}).get(kind, 0))
		return int(receipts.get("current", {}).get(kind, 0)) if stored == season - 1 else 0
	return int(receipts.get("current", {}).get(kind, 0)) if stored == season else 0

## Strict save validation: every record well formed, no holder bound by two organizations, and a holder on this Site
## must exist (a stockpile, or a vehicle). Holders on other Sites are checked by their own Site.
static func validate(state: Dictionary) -> Dictionary:
	var raw: Variant = state.get("finance", {})
	if not raw is Dictionary or raw.size() > MAX_RECORDS: return Runtime.fail("CORRUPT_SAVE", "財政紀錄欄位")
	var site_id := str(state.get("id", ""))
	var claims := {}
	for key: Variant in raw:
		var record: Variant = raw[key]
		if not valid_record(key, record): return Runtime.fail("CORRUPT_SAVE", "財政紀錄格式")
		for field: String in ["pay_source", "tax_source", "treasury"]:
			var source: Dictionary = record[field]
			if source.is_empty(): continue
			var claim := source_key(source)
			if claims.has(claim) and claims[claim] != key: return Runtime.fail("CORRUPT_SAVE", "同一來源綁給兩個組織")
			claims[claim] = key
			if str(source.site_id) != site_id: continue
			if str(source.kind) == "stock" and not state.get("stockpiles", {}).has(str(source.feature_id)): return Runtime.fail("CORRUPT_SAVE", "財政來源庫存不存在")
			if str(source.kind) == "vehicle" and not _has_vehicle(state, str(source.vehicle_id)): return Runtime.fail("CORRUPT_SAVE", "財政來源車輛不存在")
	return Runtime.ok()

static func _has_vehicle(state: Dictionary, vehicle_id: String) -> bool:
	var vehicles: Variant = state.get("vehicles", {})
	return vehicles is Dictionary and vehicles.has(vehicle_id)

## JSON loads numbers as floats; the store calls this after validation.
static func normalize(state: Dictionary) -> void:
	var raw: Variant = state.get("finance", {})
	if not raw is Dictionary: return
	for record: Variant in raw.values():
		if not record is Dictionary: continue
		for field: String in ["version", "since_day", "pay_rate", "tax_rate", "last_payday", "last_taxday", "accrued_day"]:
			if record.get(field) is float: record[field] = int(record[field])
		if record.get("exemptions") is Array:
			for index: int in record.exemptions.size(): record.exemptions[index] = int(record.exemptions[index])
		if record.get("served") is Dictionary:
			for identity: Variant in record.served: record.served[identity] = int(record.served[identity])
		if record.get("tax_carry") is Dictionary:
			for carry: Variant in record.tax_carry.values():
				if carry is Dictionary:
					for resource: Variant in carry: carry[resource] = int(carry[resource])
		if record.get("receipts") is Dictionary:
			if record.receipts.get("season") is float: record.receipts.season = int(record.receipts.season)
			for field: String in ["current", "previous"]:
				if record.receipts.get(field) is Dictionary:
					for kind: Variant in record.receipts[field]: record.receipts[field][kind] = int(record.receipts[field][kind])
