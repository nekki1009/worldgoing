extends RefCounted
## 軍餉與稅收 P3b (reports/pay-and-tax-plan.md §4.5): the nation's tax teams and what they collected. An optional
## `tax_routes` field of the Region gameplay registry (RegionSaveSlot.region_registry(); absent in older saves = none),
## edited in place and published with it, like the caravan ledger (RegionCaravans). The plan put the route on the tax
## team's own finance record; a team on the road has no Site record, so the route lives in the world ledger with the
## party it names. {version, next_id, routes, collected}
## route: {id, token (the party on the road), faction, season, home_site (the capital: the treasury), captain_ref,
##   envoy_ref (the team's 稅使), stops [site_id] (direct fiefs in visiting order), done {site_id: outcome}, phase
##   "out" | "back", day, carried {item: n} (optional: the tax goods its people carry home)}. outcome: "full" | "partial" | "refused" | "room" (only part fitted) | "none" (nothing due).
## collected: per (faction, site, season) what the fief owed and what tax teams took: [{faction, site, season, due,
##   paid}] (tenths of a point). A second team the same season takes only due − paid (PT-19); one fief is never
##   collected twice for the same share. The last MAX_COLLECTED are kept.
## factions (optional, slice 3): the factions that collect their nation-level tribute by tax teams; from a faction's
##   first round on, its direct fiefs owe no tribute on the road on their tax day (§4.3: the book transfer stops).
## lords (optional, Q9-A): the same for lords (peerage person keys) who collect from their own vassals by tax teams.
const VERSION := 1
const MAX_ROUTES := 16
const MAX_STOPS := 16
const MAX_COLLECTED := 256
const PHASES := ["out", "back"]
const OUTCOMES := ["full", "partial", "refused", "room", "none"]

static func empty() -> Dictionary:
	return {"version": VERSION, "next_id": 1, "routes": [], "collected": []}

static func section(registry: Dictionary) -> Dictionary:
	var value: Variant = registry.get("tax_routes")
	return value if value is Dictionary else empty()

static func routes(registry: Dictionary) -> Array:
	return section(registry).routes

static func _fail(message: String) -> Dictionary:
	return RegionFactionQuery.fail("CORRUPT_SAVE", message)

static func _site_id(value: Variant) -> bool:
	return value is String and not str(value).is_empty() and str(value).length() <= 256

static func validate(value: Variant) -> Dictionary:
	var section_fields := ["version", "next_id", "routes", "collected"]
	if value is Dictionary and value.has("factions"): section_fields.append("factions")
	if value is Dictionary and value.has("lords"): section_fields.append("lords")
	if not value is Dictionary or not RegionFactionQuery.keys(value, section_fields): return _fail("tax routes fields")
	if value.has("factions"):
		if not value.factions is Array or value.factions.is_empty() or value.factions.size() > 256: return _fail("tax factions")
		for faction: Variant in value.factions:
			if not RegionFactionQuery.whole(faction, 0, RegionFactionQuery.MAX_ID): return _fail("tax factions")
	if value.has("lords"):
		if not value.lords is Array or value.lords.is_empty() or value.lords.size() > 1024: return _fail("tax lords")
		for lord: Variant in value.lords:
			if not _site_id(lord): return _fail("tax lords")
	if not RegionFactionQuery.whole(value.version, VERSION, VERSION) or not RegionFactionQuery.whole(value.next_id, 1, 2147483646): return _fail("tax routes version")
	if not value.routes is Array or value.routes.size() > MAX_ROUTES or not value.collected is Array or value.collected.size() > MAX_COLLECTED: return _fail("tax routes lists")
	var ids := {}
	for route: Variant in value.routes:
		var fields := ["id", "token", "faction", "season", "home_site", "captain_ref", "envoy_ref", "stops", "done", "phase", "day"]
		if route is Dictionary and route.has("carried"): # slice 2: the tax goods its people carry home {item: n}
			fields.append("carried")
			if not route.carried is Dictionary or route.carried.size() > 8: return _fail("tax route carried")
			for item: Variant in route.carried:
				if not item is String or not RegionFactionQuery.whole(route.carried[item], 1, 100000): return _fail("tax route carried")
		if not route is Dictionary or not RegionFactionQuery.keys(route, fields): return _fail("tax route fields")
		if not RegionFactionQuery.whole(route.id, 1, int(value.next_id) - 1) or ids.has(int(route.id)): return _fail("tax route id")
		ids[int(route.id)] = true
		if not _site_id(route.token) or not _site_id(route.home_site) or not RegionFactionQuery.whole(route.faction, 0, RegionFactionQuery.MAX_ID) \
				or not RegionFactionQuery.whole(route.season, 0, 2147483646) or not RegionFactionQuery.whole(route.day, 0, 2147483646): return _fail("tax route")
		if not RegionFactionQuery.ref_valid(route.captain_ref, "person") or not RegionFactionQuery.ref_valid(route.envoy_ref, "person"): return _fail("tax route people")
		if not route.stops is Array or route.stops.is_empty() or route.stops.size() > MAX_STOPS: return _fail("tax route stops")
		var seen := {}
		for stop: Variant in route.stops:
			if not _site_id(stop) or seen.has(stop) or str(stop) == str(route.home_site): return _fail("tax route stop")
			seen[stop] = true
		if not route.done is Dictionary: return _fail("tax route done")
		for stop: Variant in route.done:
			if not seen.has(stop) or not str(route.done[stop]) in OUTCOMES: return _fail("tax route outcome")
		if not route.phase in PHASES: return _fail("tax route phase")
	for record: Variant in value.collected:
		if not record is Dictionary or not RegionFactionQuery.keys(record, ["faction", "site", "season", "due", "paid"]): return _fail("tax collected fields")
		if not RegionFactionQuery.whole(record.faction, 0, RegionFactionQuery.MAX_ID) or not _site_id(record.site) or not RegionFactionQuery.whole(record.season, 0, 2147483646) \
				or not RegionFactionQuery.whole(record.due, 0, 100000000) or not RegionFactionQuery.whole(record.paid, 0, int(record.due)): return _fail("tax collected")
	return {"ok": true}

static func normalize(value: Dictionary) -> void:
	value["version"] = int(value.get("version", VERSION))
	value["next_id"] = int(value.get("next_id", 1))
	for route: Variant in value.get("routes", []):
		if not route is Dictionary: continue
		for field: String in ["id", "faction", "season", "day"]: route[field] = int(route.get(field, 0))
		for item: Variant in route.get("carried", {}): route.carried[item] = int(route.carried[item])
	for record: Variant in value.get("collected", []):
		if not record is Dictionary: continue
		for field: String in ["faction", "season", "due", "paid"]: record[field] = int(record.get(field, 0))
	if value.get("factions") is Array:
		for index: int in value.factions.size(): value.factions[index] = int(value.factions[index])

## The ledger's field, created when missing.
static func ensure(ledger: Dictionary) -> Dictionary:
	if not ledger.get("tax_routes") is Dictionary: ledger["tax_routes"] = empty()
	return ledger.tax_routes

static func add(ledger: Dictionary, route: Dictionary) -> Dictionary:
	var section_value := ensure(ledger)
	if section_value.routes.size() >= MAX_ROUTES: return RegionFactionQuery.fail("FULL", "稅隊已滿")
	var stored := route.duplicate(true)
	stored["id"] = int(section_value.next_id)
	section_value.next_id = int(section_value.next_id) + 1
	section_value.routes.append(stored)
	return {"ok": true, "id": int(stored.id)}

static func find(ledger: Dictionary, id: int) -> Dictionary:
	for route: Dictionary in section(ledger).routes:
		if int(route.id) == id: return route
	return {}

static func remove(ledger: Dictionary, id: int) -> void:
	if not ledger.get("tax_routes") is Dictionary: return
	ledger.tax_routes.routes = ledger.tax_routes.routes.filter(func(route: Dictionary) -> bool: return int(route.id) != id)
	if ledger.tax_routes.routes.is_empty() and ledger.tax_routes.collected.is_empty() and not ledger.tax_routes.has("factions") and not ledger.tax_routes.has("lords"): ledger.erase("tax_routes")

## Does `faction` collect its nation-level tribute by tax teams (it has sent one)?
static func uses_teams(registry: Dictionary, faction: int) -> bool:
	return section(registry).get("factions", []).has(faction)

## Does the lord `person_key` collect from his vassals by tax teams?
static func lord_uses_teams(registry: Dictionary, person_key: String) -> bool:
	return section(registry).get("lords", []).has(person_key)

static func mark_lord(ledger: Dictionary, person_key: String) -> void:
	var section_value := ensure(ledger)
	var lords: Array = section_value.get("lords", [])
	if lords.has(person_key): return
	lords.append(person_key)
	lords.sort()
	section_value["lords"] = lords

static func mark_faction(ledger: Dictionary, faction: int) -> void:
	var section_value := ensure(ledger)
	var factions: Array = section_value.get("factions", [])
	if factions.has(faction): return
	factions.append(faction)
	factions.sort()
	section_value["factions"] = factions

## What `faction` has collected from `site` for `season`: {due, paid} ({} when nothing yet).
static func collected_of(registry: Dictionary, faction: int, site: String, season: int) -> Dictionary:
	for record: Dictionary in section(registry).collected:
		if int(record.faction) == faction and str(record.site) == site and int(record.season) == season: return record
	return {}

## Is `site` already on the road of another route of `faction` this season (not yet visited)?
static func planned(registry: Dictionary, faction: int, site: String, season: int) -> bool:
	for route: Dictionary in section(registry).routes:
		if int(route.faction) == faction and int(route.season) == season and route.stops.has(site) and not route.done.has(site): return true
	return false

## Records a handover: the fief's due for the season (kept from the first visit) and what was taken in all.
static func record_collection(ledger: Dictionary, faction: int, site: String, season: int, due: int, paid_now: int) -> Dictionary:
	var section_value := ensure(ledger)
	for record: Dictionary in section_value.collected:
		if int(record.faction) == faction and str(record.site) == site and int(record.season) == season:
			record.paid = mini(int(record.due), int(record.paid) + maxi(0, paid_now))
			return record
	var stored := {"faction": faction, "site": site, "season": season, "due": maxi(0, due), "paid": clampi(paid_now, 0, maxi(0, due))}
	section_value.collected.append(stored)
	while section_value.collected.size() > MAX_COLLECTED: section_value.collected.pop_front()
	return stored
