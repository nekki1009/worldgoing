extends RefCounted
## 土匪 B5 slice 1 (bandit spec §7, trade plan §6.2): the route risk a settlement's head reckons with before sending a
## caravan. Pure; no class_name on purpose (callers preload it).
## - What he knows: the Sites where his strength receipts (RegionSiteStrength: value.factions) show people of a bandit
##   faction, and the Sites where a caravan of his faction was robbed (the caravan ledger's lost records, raided_by).
##   Never the faction registry's lairs themselves: not all-knowing.
## - The risk of a trip: PER_BAND percent for every known band (a faction at a Site) standing within REACH Sites of the
##   straight Site line from home to the destination; a band this settlement paid protection to (still in force) counts
##   nothing. Capped at 100.
## - What the head does with it (site_caravan): he sends the less risky destination first and loads (100 - risk) percent
##   of what he would have sent; nothing left to send means that destination is not worth the road.
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const STRENGTH_KIND := "officer_site_strength"
const PER_BAND := 15
const REACH := Bandit.REACH_SITES

static func _site(site_id: String) -> Variant:
	var parts := site_id.split(":")
	if parts.size() < 3 or not parts[parts.size() - 2].is_valid_int() or not parts[parts.size() - 1].is_valid_int(): return null
	return Vector2i(int(parts[parts.size() - 2]), int(parts[parts.size() - 1]))

## The Sites of the straight line between two Sites, both ends included (one Site per step of the longer axis).
static func route_sites(from_id: String, to_id: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var a: Variant = _site(from_id)
	var b: Variant = _site(to_id)
	if a == null or b == null: return result
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
	if steps == 0: return [a]
	for index: int in range(steps + 1):
		result.append(Vector2i(roundi(lerpf(float(a.x), float(b.x), float(index) / float(steps))), roundi(lerpf(float(a.y), float(b.y), float(index) / float(steps)))))
	return result

## {site_id: [band faction id, ...]} from the head's known receipts (RegionAI.view) and the lost caravans of `faction`.
static func known_bands(known: Dictionary, registry: Dictionary, lost: Array, faction: int) -> Dictionary:
	var result := {}
	for object: Variant in known:
		var receipt: Variant = known[object]
		if not receipt is Dictionary or receipt.get("observation_kind") != STRENGTH_KIND or not receipt.get("value") is Dictionary: continue
		var seen: Variant = receipt.value.get("factions", {})
		if not seen is Dictionary: continue
		for key: Variant in seen:
			if not str(key).is_valid_int() or int(seen[key]) <= 0 or not RegionFactionQuery.is_bandit(registry, int(str(key))): continue
			_add(result, str(object), int(str(key)))
	for record: Variant in lost:
		if not record is Dictionary or int(record.get("faction", -1)) != faction or int(record.get("raided_by", -1)) < 0: continue
		_add(result, str(record.get("at_site", "")), int(record.raided_by))
	return result

static func _add(result: Dictionary, site_id: String, band: int) -> void:
	if _site(site_id) == null: return
	var bands: Array = result.get(site_id, [])
	if not bands.has(band): bands.append(band)
	bands.sort()
	result[site_id] = bands

## The risk in percent (0..100) of the trip from `from_id` to `to_id` for a settlement at `from_id`.
static func risk(from_id: String, to_id: String, bands: Dictionary, registry: Dictionary, day: int) -> int:
	var route := route_sites(from_id, to_id)
	if route.is_empty(): return 0
	var total := 0
	var sites: Array = bands.keys()
	sites.sort()
	for site_id: String in sites:
		var at: Variant = _site(site_id)
		if at == null: continue
		var near := false
		for step: Vector2i in route:
			if maxi(absi(step.x - at.x), absi(step.y - at.y)) <= REACH:
				near = true
				break
		if not near: continue
		for band: Variant in bands[site_id]:
			if Bandit.protected(registry, int(band), from_id, day): continue
			total += PER_BAND
	return mini(100, total)

## What is still worth sending at that risk: (100 - risk) percent of each resource, whole units, empty ones dropped.
static func discounted(goods: Dictionary, risk_percent: int) -> Dictionary:
	var result := {}
	for resource: Variant in goods:
		var n := int(goods[resource]) * (100 - clampi(risk_percent, 0, 100)) / 100
		if n > 0: result[resource] = n
	return result
