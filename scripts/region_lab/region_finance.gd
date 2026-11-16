extends RefCounted
## World-level finance (軍餉與稅收 P3, reports/pay-and-tax-plan.md §3.4, §4.3, §8): an optional `finance` section of the
## faction registry, committed with it through RegionSaveSlot.checkpoint_region_site (like peerage and diplomacy).
## {version, next_id, seats, transit, exemptions}
## - seats: {person_key → site_id}: where a titled person's fief treasury is — the Site of the settlement he heads whose
##   finance record has a bound treasury. Tribute to him is delivered there.
## - transit: [{id, kind, from_site, to_site, to, items, tenths, arrive_day, season, payer}] goods on the road: "tribute"
##   (a settlement to its head's liege, to = person_key) or "fund" (to = "team:<id>"). Delivered on or after
##   arrive_day when the destination Site is live; never instant across Sites (§3.4).
## - exemptions: {site_id → [season]} seasons a faction head waived a fief's tribute (§4.3).
## Pure candidates; the Site code commits them.
const VERSION := 1
const KINDS := ["tribute", "fund"]
const MAX_SEATS := 1024
const MAX_TRANSIT := 1024
const MAX_EXEMPTIONS := 16
## Road speed for goods on the road: about 30 km a game day (150 Sites of 200 m).
const SITES_PER_DAY := 150

static func empty() -> Dictionary:
	return {"version": VERSION, "next_id": 1, "seats": {}, "transit": [], "exemptions": {}}

static func section(registry: Dictionary) -> Dictionary:
	var value: Variant = registry.get("finance")
	return value if value is Dictionary else empty()

static func _fail(message: String) -> Dictionary:
	return RegionFactionQuery.fail("CORRUPT_SAVE", message)

static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary or not RegionFactionQuery.keys(value, ["version", "next_id", "seats", "transit", "exemptions"]): return _fail("finance fields")
	if not RegionFactionQuery.whole(value.version, VERSION, VERSION) or not RegionFactionQuery.whole(value.next_id, 1, 2147483646): return _fail("finance version")
	if not value.seats is Dictionary or value.seats.size() > MAX_SEATS: return _fail("finance seats")
	for key: Variant in value.seats:
		if not key is String or str(key).is_empty() or not value.seats[key] is String or str(value.seats[key]).is_empty(): return _fail("finance seat")
	if not value.transit is Array or value.transit.size() > MAX_TRANSIT: return _fail("finance transit")
	var ids := {}
	for entry: Variant in value.transit:
		if not entry is Dictionary or not RegionFactionQuery.keys(entry, ["id", "kind", "from_site", "to_site", "to", "items", "tenths", "arrive_day", "season", "payer"]): return _fail("finance transit fields")
		if not RegionFactionQuery.whole(entry.id, 1, int(value.next_id) - 1) or ids.has(int(entry.id)) or not KINDS.has(entry.kind): return _fail("finance transit id")
		ids[int(entry.id)] = true
		for field: String in ["from_site", "to_site", "to", "payer"]:
			if not entry[field] is String or str(entry[field]).is_empty(): return _fail("finance transit endpoint")
		if not entry.items is Dictionary or entry.items.is_empty(): return _fail("finance transit goods")
		for item: Variant in entry.items:
			if not item is String or not RegionFactionQuery.whole(entry.items[item], 1, 1000000): return _fail("finance transit goods")
		if not RegionFactionQuery.whole(entry.tenths, 0, 2000000000) or not RegionFactionQuery.whole(entry.arrive_day, 0, 2147483646) or not RegionFactionQuery.whole(entry.season, -1, 2147483646): return _fail("finance transit time")
	if not value.exemptions is Dictionary or value.exemptions.size() > MAX_SEATS: return _fail("finance exemptions")
	for site_id: Variant in value.exemptions:
		var seasons: Variant = value.exemptions[site_id]
		if not site_id is String or not seasons is Array or seasons.is_empty() or seasons.size() > MAX_EXEMPTIONS: return _fail("finance exemption")
		var previous := -1
		for season: Variant in seasons:
			if not RegionFactionQuery.whole(season, 0, 2147483646) or int(season) <= previous: return _fail("finance exemption order")
			previous = int(season)
	return {"ok": true}

## JSON / var round trips may load whole numbers as floats.
static func normalize(value: Dictionary) -> void:
	value["version"] = int(value.get("version", VERSION))
	value["next_id"] = int(value.get("next_id", 1))
	for entry: Variant in value.get("transit", []):
		if not entry is Dictionary: continue
		for field: String in ["id", "tenths", "arrive_day", "season"]: entry[field] = int(entry.get(field, 0))
		for item: Variant in entry.get("items", {}): entry.items[item] = int(entry.items[item])
	for site_id: Variant in value.get("exemptions", {}):
		var seasons: Array = value.exemptions[site_id]
		for index: int in seasons.size(): seasons[index] = int(seasons[index])

## A registry candidate with its finance section ready to edit and its revision advanced.
static func candidate(registry: Dictionary) -> Dictionary:
	var result: Dictionary = registry.duplicate(true)
	if not result.get("finance") is Dictionary: result["finance"] = empty()
	result.revision = int(result.get("revision", 0)) + 1
	return result

static func site_coordinate(site_id: String) -> Vector2i:
	var parts := site_id.split(":")
	if parts.size() < 3 or not parts[parts.size() - 2].is_valid_int() or not parts[parts.size() - 1].is_valid_int(): return Vector2i(-2147483647, -2147483647)
	return Vector2i(int(parts[parts.size() - 2]), int(parts[parts.size() - 1]))

## Whole game days goods need between two Sites: at least one.
static func travel_days(from_site: String, to_site: String) -> int:
	var a := site_coordinate(from_site)
	var b := site_coordinate(to_site)
	if a.x == -2147483647 or b.x == -2147483647: return 1
	var sites := maxi(absi(a.x - b.x), absi(a.y - b.y))
	return maxi(1, ceili(float(sites) / float(SITES_PER_DAY)))

static func add_transit(candidate_registry: Dictionary, entry: Dictionary) -> Dictionary:
	var finance: Dictionary = candidate_registry.finance
	if finance.transit.size() >= MAX_TRANSIT: return RegionFactionQuery.fail("FULL", "在途貨物已滿")
	var stored := entry.duplicate(true)
	stored["id"] = int(finance.next_id)
	finance.next_id = int(finance.next_id) + 1
	finance.transit.append(stored)
	return {"ok": true, "id": int(stored.id)}

## Transit due at `site_id` on or before `day`, oldest first.
static func due(registry: Dictionary, site_id: String, day: int) -> Array:
	var result: Array = []
	for entry: Dictionary in section(registry).transit:
		if str(entry.to_site) == site_id and int(entry.arrive_day) <= day: result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	return result

static func remove_transit(candidate_registry: Dictionary, ids: Array) -> void:
	var kept: Array = []
	for entry: Dictionary in candidate_registry.finance.transit:
		if not ids.has(int(entry.id)): kept.append(entry)
	candidate_registry.finance.transit = kept

static func seat_of(registry: Dictionary, person_key: String) -> String:
	return str(section(registry).seats.get(person_key, ""))

static func exempt(registry: Dictionary, site_id: String, season: int) -> bool:
	return section(registry).exemptions.get(site_id, []).has(season)
