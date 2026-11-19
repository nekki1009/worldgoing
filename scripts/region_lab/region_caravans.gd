extends RefCounted
## 貿易 T5 slice 1 (trade plan §7.2): NPC caravan missions, an optional `caravans` field of the Region gameplay
## registry (RegionSaveSlot.region_registry(); absent in older saves = none), edited in place and published with it like
## parties and events. {version, next_id, missions}
## mission: {id, token, faction, from_site, warehouse, to_site, captain_ref, goods {item: n}, phase "out"|"back", day,
##   sold {item: n} (optional: what the destination paid, set once when the caravan traded there)}
##   risk (optional, 1..100: the route risk in percent the head reckoned with, 土匪 B5)
## lost (optional): the last MAX_LOST caravans that never came home, oldest first (TR-55, 土匪 B5):
##   {id, faction, from_site, at_site, day, raided_by (the band's faction id, or -1 when nobody is known)}
## At most MAX_ACTIVE missions in the world (the plan's initial cap: loading, on the road, at the destination, returning).
const VERSION := 1
const MAX_ACTIVE := 8
const MAX_LOST := 16
const PHASES := ["out", "back"]

static func empty() -> Dictionary:
	return {"version": VERSION, "next_id": 1, "missions": []}

static func section(registry: Dictionary) -> Dictionary:
	var value: Variant = registry.get("caravans")
	return value if value is Dictionary else empty()

static func missions(registry: Dictionary) -> Array:
	return section(registry).missions

static func _fail(message: String) -> Dictionary:
	return RegionFactionQuery.fail("CORRUPT_SAVE", message)

static func validate(value: Variant) -> Dictionary:
	var section_fields := ["version", "next_id", "missions"]
	if value is Dictionary and value.has("lost"): section_fields.append("lost")
	if not value is Dictionary or not RegionFactionQuery.keys(value, section_fields): return _fail("caravans fields")
	if value.has("lost"):
		if not value.lost is Array or value.lost.is_empty() or value.lost.size() > MAX_LOST: return _fail("caravans lost")
		for record: Variant in value.lost:
			if not record is Dictionary or not RegionFactionQuery.keys(record, ["id", "faction", "from_site", "at_site", "day", "raided_by"]): return _fail("lost caravan fields")
			if not RegionFactionQuery.whole(record.id, 1, 2147483646) or not RegionFactionQuery.whole(record.faction, 0, RegionFactionQuery.MAX_ID) or not RegionFactionQuery.whole(record.day, 0, 2147483646): return _fail("lost caravan")
			if not RegionFactionQuery.whole(record.raided_by, -1, RegionFactionQuery.MAX_ID): return _fail("lost caravan band")
			for field: String in ["from_site", "at_site"]:
				if not record[field] is String or str(record[field]).is_empty(): return _fail("lost caravan site")
	if not RegionFactionQuery.whole(value.version, VERSION, VERSION) or not RegionFactionQuery.whole(value.next_id, 1, 2147483646): return _fail("caravans version")
	if not value.missions is Array or value.missions.size() > MAX_ACTIVE: return _fail("caravans missions")
	var ids := {}
	for mission: Variant in value.missions:
		var fields := ["id", "token", "faction", "from_site", "warehouse", "to_site", "captain_ref", "goods", "phase", "day"]
		if mission is Dictionary and mission.has("sold"): fields.append("sold") # slice 2: what the destination paid
		if mission is Dictionary and mission.has("risk"):
			fields.append("risk")
			if not RegionFactionQuery.whole(mission.risk, 1, 100): return _fail("caravan risk")
		if not mission is Dictionary or not RegionFactionQuery.keys(mission, fields): return _fail("caravan fields")
		if mission.has("sold"):
			if not mission.sold is Dictionary or mission.sold.size() > 32: return _fail("caravan sale")
			for item: Variant in mission.sold:
				if not item is String or not RegionFactionQuery.whole(mission.sold[item], 1, 100000): return _fail("caravan sale")
		if not RegionFactionQuery.whole(mission.id, 1, int(value.next_id) - 1) or ids.has(int(mission.id)): return _fail("caravan id")
		ids[int(mission.id)] = true
		for field: String in ["token", "from_site", "warehouse", "to_site"]:
			if not mission[field] is String or str(mission[field]).is_empty(): return _fail("caravan endpoint")
		if not RegionFactionQuery.whole(mission.faction, 0, RegionFactionQuery.MAX_ID) or not RegionFactionQuery.ref_valid(mission.captain_ref, "person"): return _fail("caravan captain")
		if not mission.goods is Dictionary or mission.goods.is_empty() or mission.goods.size() > 32: return _fail("caravan goods")
		for item: Variant in mission.goods:
			if not item is String or not RegionFactionQuery.whole(mission.goods[item], 1, 100000): return _fail("caravan goods")
		if not mission.phase in PHASES or not RegionFactionQuery.whole(mission.day, 0, 2147483646): return _fail("caravan phase")
	return {"ok": true}

static func normalize(value: Dictionary) -> void:
	value["version"] = int(value.get("version", VERSION))
	value["next_id"] = int(value.get("next_id", 1))
	for mission: Variant in value.get("missions", []):
		if not mission is Dictionary: continue
		for field: String in ["id", "faction", "day"]: mission[field] = int(mission.get(field, 0))
		for item: Variant in mission.get("goods", {}): mission.goods[item] = int(mission.goods[item])
		for item: Variant in mission.get("sold", {}): mission.sold[item] = int(mission.sold[item])
		if mission.has("risk"): mission["risk"] = int(mission.risk)
	for record: Variant in value.get("lost", []):
		if not record is Dictionary: continue
		for field: String in ["id", "faction", "day", "raided_by"]: record[field] = int(record.get(field, 0))

## The ledger's caravans field, created when missing.
static func ensure(ledger: Dictionary) -> Dictionary:
	if not ledger.get("caravans") is Dictionary: ledger["caravans"] = empty()
	return ledger.caravans

static func add(ledger: Dictionary, mission: Dictionary) -> Dictionary:
	var caravans := ensure(ledger)
	if caravans.missions.size() >= MAX_ACTIVE: return RegionFactionQuery.fail("FULL", "商隊任務已滿")
	var stored := mission.duplicate(true)
	stored["id"] = int(caravans.next_id)
	caravans.next_id = int(caravans.next_id) + 1
	caravans.missions.append(stored)
	return {"ok": true, "id": int(stored.id)}

static func find(ledger: Dictionary, id: int) -> Dictionary:
	for mission: Dictionary in section(ledger).missions:
		if int(mission.id) == id: return mission
	return {}

static func remove(ledger: Dictionary, id: int) -> void:
	if not ledger.get("caravans") is Dictionary: return
	ledger.caravans.missions = ledger.caravans.missions.filter(func(mission: Dictionary) -> bool: return int(mission.id) != id)
	if ledger.caravans.missions.is_empty() and not ledger.caravans.has("lost"): ledger.erase("caravans")

## The lost caravans on record (oldest first).
static func lost(registry: Dictionary) -> Array:
	var records: Variant = section(registry).get("lost", [])
	return records if records is Array else []

## TR-55: the mission ends unfinished where it was beaten; its place in the cap is free and the loss is remembered.
static func lose(ledger: Dictionary, id: int, at_site: String, day: int, raided_by: int) -> Dictionary:
	var mission: Dictionary = find(ledger, id)
	if mission.is_empty(): return RegionFactionQuery.fail("NO_TARGET", "沒有這個商隊任務")
	var record := {"id": id, "faction": int(mission.faction), "from_site": str(mission.from_site), "at_site": at_site, "day": maxi(0, day), "raided_by": raided_by}
	var records: Array = ledger.caravans.get("lost", [])
	records.append(record)
	while records.size() > MAX_LOST: records.pop_front()
	ledger.caravans["lost"] = records
	remove(ledger, id)
	return {"ok": true, "record": record}
