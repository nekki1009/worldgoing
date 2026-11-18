extends RefCounted
## 貿易 T5 slice 1 (trade plan §7.2): NPC caravan missions, an optional `caravans` field of the Region gameplay
## registry (RegionSaveSlot.region_registry(); absent in older saves = none), edited in place and published with it like
## parties and events. {version, next_id, missions}
## mission: {id, token, faction, from_site, warehouse, to_site, captain_ref, goods {item: n}, phase "out"|"back", day}
## At most MAX_ACTIVE missions in the world (the plan's initial cap: loading, on the road, at the destination, returning).
const VERSION := 1
const MAX_ACTIVE := 8
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
	if not value is Dictionary or not RegionFactionQuery.keys(value, ["version", "next_id", "missions"]): return _fail("caravans fields")
	if not RegionFactionQuery.whole(value.version, VERSION, VERSION) or not RegionFactionQuery.whole(value.next_id, 1, 2147483646): return _fail("caravans version")
	if not value.missions is Array or value.missions.size() > MAX_ACTIVE: return _fail("caravans missions")
	var ids := {}
	for mission: Variant in value.missions:
		if not mission is Dictionary or not RegionFactionQuery.keys(mission, ["id", "token", "faction", "from_site", "warehouse", "to_site", "captain_ref", "goods", "phase", "day"]): return _fail("caravan fields")
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
	if ledger.caravans.missions.is_empty(): ledger.erase("caravans")
