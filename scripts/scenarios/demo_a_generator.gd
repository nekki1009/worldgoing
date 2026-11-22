extends RefCounted
## 示範劇本 A「開墾之地」generator (Claude Doc 示範劇本 A；Nekki 11/22: 30 settlements, 15 bands, 15 factions of two
## settlements each, the Taiwan map near the default start). Builds an author package on the natural Taiwan source:
## - Sites: the start, then `settlements` land Sites in rings around it (never adjacent to each other), then `bands` lair
##   Sites, each with 2–4 settlements within 2 Sites and not on a settlement;
## - each settlement: a centre, houses (5, a town 10), a warehouse with opening stock, a well; residents (each house's beds) with a
##   head and a 度支 by name; a militia team; factions 1..N own them two by two (the first of each pair is the main one,
##   whose head leads the faction); the first `towns` factions' main settlement has more houses;
## - each lair: one band team (a chief and its men) of its own bandit faction, with a hoard and heat.
## Everything is deterministic from `seed`. generate() returns {ok, path, sites, residents, bandits, seconds} or a refusal.
const Builder = preload("res://scripts/scenarios/scenario_builder.gd")
const Data = preload("res://scripts/region_lab/region_data.gd")
const START := Vector2i(1170, 13252)
const SURNAMES := ["陳", "林", "黃", "張", "李", "王", "吳", "劉", "蔡", "楊", "許", "鄭", "謝", "郭", "洪", "曾", "邱", "廖", "賴", "周"]
const GIVEN := ["阿", "水", "土", "金", "木", "春", "秋", "福", "旺", "順", "明", "清", "德", "成", "興", "財", "來", "生", "發", "義"]
const PLACE_A := ["溪", "林", "石", "竹", "田", "埔", "坑", "崙", "寮", "湖", "港", "山", "社", "厝", "圳"]
const PLACE_B := ["口", "頭", "尾", "仔", "腳", "內", "後", "前", "邊", "下"]
const BAND_NAMES := ["黑石", "青龍", "白虎", "赤狼", "鐵爪", "飛鷹", "雙刀", "斷崖", "野狐", "黃蜂", "鬼哭", "火燒", "冷泉", "亂石", "毒蛇"]

static func _name(rng: RandomNumberGenerator, taken: Dictionary) -> String:
	for _try: int in range(200):
		var made: String = SURNAMES[rng.randi_range(0, SURNAMES.size() - 1)] + GIVEN[rng.randi_range(0, GIVEN.size() - 1)] + GIVEN[rng.randi_range(0, GIVEN.size() - 1)]
		if not taken.has(made):
			taken[made] = true
			return made
	return "無名%d" % taken.size()

static func _land(source: RegionData, site: Vector2i) -> bool:
	var summary: Dictionary = source.get_site_summary(site.x, site.y)
	return bool(summary.get("ok", false)) and str(summary.get("status", "")) == "land" and bool(summary.get("has_terrain", false))

static func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

## Land Sites by distance from `center` (then y, x), up to `radius`.
static func _ring_sites(source: RegionData, center: Vector2i, radius: int) -> Array:
	var result: Array = []
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			var site := center + Vector2i(dx, dy)
			if _land(source, site): result.append(site)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := _distance(a, center)
		var db := _distance(b, center)
		return da < db or da == db and (a.y < b.y or a.y == b.y and a.x < b.x))
	return result

## A walkable cell of `site` near its middle, or (-1, -1).
static func _walkable_near_middle(source: RegionData, site: Vector2i) -> Vector2i:
	var built: Dictionary = source.make_terrain_data(site.x, site.y)
	if not bool(built.get("ok", false)): return Vector2i(-1, -1)
	var data: TerrainData = built.data
	for origin: Vector2i in Builder.spiral(Vector2i(49, 49), 1, 30, 2):
		if data.is_walkable(origin): return origin
	return Vector2i(-1, -1)

static func generate(source: RegionData, folder: String, package_name: String, settlements: int, bands: int, towns: int, seed_value: int, scenario_id: String = "demo_a_kaiken") -> Dictionary:
	var started := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Sites.
	var start := START if _land(source, START) else Vector2i(-1, -1)
	var pool := _ring_sites(source, START, 9)
	if start.x < 0 and not pool.is_empty(): start = pool[0]
	if start.x < 0: return {"ok": false, "code": "NO_LAND", "stage": "start"}
	var chosen: Array = []
	for site: Vector2i in pool:
		if chosen.size() >= settlements: break
		if site == start or _distance(site, start) < 1: continue
		var crowded := false
		for other: Vector2i in chosen: crowded = crowded or _distance(site, other) < 2
		if not crowded: chosen.append(site)
	if chosen.size() < settlements: return {"ok": false, "code": "NO_LAND", "stage": "settlements %d/%d" % [chosen.size(), settlements]}
	var lairs: Array = []
	for site: Vector2i in pool:
		if lairs.size() >= bands: break
		if site == start or chosen.has(site) or _distance(site, start) < 2: continue
		var near := 0
		for village: Vector2i in chosen: near += 1 if _distance(site, village) <= 2 else 0
		var crowded := false
		for other: Vector2i in lairs: crowded = crowded or _distance(site, other) < 2
		if near >= 2 and near <= 4 and not crowded: lairs.append(site)
	if lairs.size() < bands: return {"ok": false, "code": "NO_LAND", "stage": "lairs %d/%d" % [lairs.size(), bands]}
	var start_cell := _walkable_near_middle(source, start)
	if start_cell.x < 0: return {"ok": false, "code": "NO_LAND", "stage": "start cell"}
	# Settlements.
	var taken := {}
	var initial_states := {}
	var static_states := {}
	var factions: Array = []
	var teams: Array = []
	var offices: Array = []
	var stock: Array = []
	var residents_total := 0
	for index: int in range(settlements):
		var site: Vector2i = chosen[index]
		var faction := index / 2 + 1
		var main := index % 2 == 0
		var town := main and faction <= towns
		if main: factions.append({"id": faction, "name": PLACE_A[(faction - 1) % PLACE_A.size()] + PLACE_B[(faction * 7) % PLACE_B.size()] + ("鎮" if town else "莊"), "kind": "npc"})
		var work := Builder.new_work(source, site)
		var owner := {"owner_faction": faction}
		var center: Dictionary = Builder.place(source, work, "settlement_center", Builder.spiral(Vector2i(46, 46), 4, 6), Vector2i(5, 5), Vector2i(5, 5), owner)
		if not center.ok: return {"ok": false, "code": "BUILD", "stage": "%s centre at %s" % [str(center.stage), str(site)]}
		var houses: Array = []
		var origin_c: Vector2i = center.origin
		for _house: int in range(10 if town else 5):
			var house: Dictionary = Builder.place(source, work, "house", Builder.spiral(origin_c + Vector2i(8, 0), 5, 6), Vector2i(3, 3), Vector2i(3, 3), {"owner_faction": faction, "variant": "standard"})
			if not house.ok: return {"ok": false, "code": "BUILD", "stage": "%s house at %s" % [str(house.stage), str(site)]}
			houses.append(str(house.feature))
		var warehouse: Dictionary = Builder.place(source, work, "warehouse", Builder.spiral(origin_c + Vector2i(-8, 0), 4, 6), Vector2i(3, 2), Vector2i(3, 2), {"layout_version": 1, "quarter": 0, "owner_faction": faction})
		if not warehouse.ok: return {"ok": false, "code": "BUILD", "stage": "%s warehouse at %s" % [str(warehouse.stage), str(site)]}
		var well: Dictionary = Builder.place(source, work, "well", Builder.spiral(origin_c + Vector2i(0, 8), 3, 6), Vector2i(1, 1), Vector2i(1, 1), owner, {"foundation": 100, "groundwater": 100})
		if not well.ok: return {"ok": false, "code": "BUILD", "stage": "%s well at %s" % [str(well.stage), str(site)]}
		# Each house takes as many residents as its rest cells hold (SiteRuntime.house_layout capacity).
		var built_terrain := Builder.prepare(source, work)
		if not built_terrain.ok: return {"ok": false, "code": "BUILD", "stage": "settlement at %s: %s" % [str(site), str(built_terrain.stage)]}
		var rows: Array = []
		for house_key: String in houses:
			var layout: Dictionary = SiteRuntime.house_layout(built_terrain.terrain, house_key)
			for _person: int in range(int(layout.get("capacity", 0)) if layout.get("ok", false) else 0): rows.append({"name": _name(rng, taken), "faction_id": faction, "house": house_key})
		if rows.size() < 2: return {"ok": false, "code": "BUILD", "stage": "no beds at %s" % str(site)}
		residents_total += rows.size()
		initial_states["%d:%d" % [site.x, site.y]] = Builder.export_state(work, rows)
		static_states["%d:%d" % [site.x, site.y]] = work.terrain_static.duplicate(true)
		offices.append({"site": [site.x, site.y], "head": str(rows[0].name), "duties": {"settlement.finance": str(rows[1].name)}})
		# The opening stock, scaled to fit 80 % of the warehouse (SiteStockpiles.capacity).
		var wanted: Dictionary = {"grain": 400, "wood": 100, "stone": 60, "cloth": 40, "iron": 20} if town else {"grain": 150, "wood": 40}
		var room := int(SiteStockpiles.capacity(work.initial_state.features[str(warehouse.feature)]) * 0.8)
		var total := 0
		for item: String in wanted: total += int(wanted[item])
		var items := {}
		for item: String in wanted: items[item] = maxi(1, int(wanted[item]) * mini(room, total) / total)
		stock.append({"site": [site.x, site.y], "feature": str(warehouse.feature), "items": items})
		var militia: Array = [{"name": _name(rng, taken), "role": "officer"}]
		for _man: int in range(5 if town else 1): militia.append({"name": _name(rng, taken), "role": "soldier"})
		teams.append({"site": [site.x, site.y], "faction_id": faction, "cell": [origin_c.x + 2, origin_c.y + 10], "members": militia})
	# Bands.
	var bandits_total := 0
	for index: int in range(bands):
		var lair: Vector2i = lairs[index]
		var band := 100 + index + 1
		var cell := _walkable_near_middle(source, lair)
		if cell.x < 0: return {"ok": false, "code": "NO_LAND", "stage": "lair cell %s" % str(lair)}
		var hoard := {"iron": 6 + rng.randi_range(0, 6), "cloth": 10 + rng.randi_range(0, 20), "coin": 10 + rng.randi_range(0, 20), "grain": 20 + rng.randi_range(0, 40)}
		factions.append({"id": band, "name": str(BAND_NAMES[index % BAND_NAMES.size()]) + "寨", "kind": "bandit",
			"bandit": {"lair": {"site": [lair.x, lair.y], "cell": [cell.x, cell.y]}, "heat": 10 + rng.randi_range(0, 30), "raid_ai": true, "hoard": hoard}})
		var men: Array = [{"name": _name(rng, taken), "role": "officer"}]
		for _man: int in range(5 + rng.randi_range(0, 4)): men.append({"name": _name(rng, taken), "role": "soldier"})
		bandits_total += men.size()
		teams.append({"site": [lair.x, lair.y], "faction_id": band, "cell": [cell.x, cell.y], "members": men})
		var lair_work := Builder.new_work(source, lair)
		var prepared := Builder.prepare(source, lair_work)
		if not prepared.ok: return {"ok": false, "code": "BUILD", "stage": "lair %s: %s" % [str(lair), str(prepared.stage)]}
		initial_states["%d:%d" % [lair.x, lair.y]] = Builder.export_state(prepared.draft, [])
	# The start Site gets its own (empty) authored state, as every Site of the package.
	var start_work := Builder.prepare(source, Builder.new_work(source, start))
	if not start_work.ok: return {"ok": false, "code": "BUILD", "stage": "start: " + str(start_work.stage)}
	initial_states["%d:%d" % [start.x, start.y]] = Builder.export_state(start_work.draft, [])
	var scenario := {"format": 1, "factions": factions, "teams": teams, "offices": offices, "stock": stock}
	if not Data.author_scenario_valid(scenario): return {"ok": false, "code": "INVALID_AUTHOR_SCENARIO", "stage": "scenario"}
	var start_row := {"mode": "created_player", "site": [start.x, start.y], "cell": [start_cell.x, start_cell.y]}
	# A natural source with a paired resource layer lists that layer too (RegionData.load_author_package MISSING_RESOURCE_PAIR).
	var dependencies: Array = [{"path": RegionData.DEFAULT_MANIFEST, "id": "natural"}]
	if not source.resource_manifest_hash.is_empty(): dependencies.append({"path": str(RegionData.RESOURCE_SOURCE_PAIRS[source.manifest_hash].path), "id": "resources"})
	var exported: Dictionary = Data.export_author_initial_package(folder, package_name, dependencies, "natural", scenario_id, 1,
		"開墾之地", "示範劇本 A：%d 座聚落、%d 夥土匪" % [settlements, bands], start_row, initial_states, static_states, scenario)
	if not exported.ok: return exported
	return {"ok": true, "path": str(exported.path), "start": start, "settlements": chosen, "lairs": lairs, "residents": residents_total, "bandits": bandits_total, "seconds": float(Time.get_ticks_msec() - started) / 1000.0}
