extends RefCounted
## 土匪：畫面外公式遠征 (Nekki 2026-11-25 B; bandit spec §5.1, §11, §12, BQ10). Binding a lair and a settlement costs
## seconds of stillness each, so a lair nobody has opened raids by formula: once a game day the chief picks a settlement
## within Bandit.REACH_SITES that is not open either and that he can beat, and the raid is settled at once from the two
## Sites' saved files. A lair or a settlement that is open (the active Site or a bound cold owner) is never settled here:
## there the band really goes and fights (site_bandit_far_raid.gd, site_bandit_raid_field.gd).
## - What a file holds (summary): its people by faction and role, its settlement's owner, its stock. Read once per file.
## - The chief knows the settlements within REACH_SITES and their rough strength (Nekki 2026-11-25 A).
## - Strength: the able soldiers there and half of the other grown people (CIVIL_WEIGHT, the 10A.3 coefficient of residents
##   who fight; SiteCombatRules.UNARMED_IMPACT is set so that the live fights agree). The stronger side wins more often
##   (odds of the eighth power; 8 against 7 win about three times in four). Both sides break off at half, as a live raid
##   does (site_bandit_raid_field.gd): a band that wins keeps sqrt(A² - 3/4 D²) on their feet, a band that loses gets half
##   of its people home, a settlement's people come to (measured 2026-11-25: 7 against 12 villagers won with 6 on their
##   feet, all 12 came to, one raider died; nobody is left to bleed to death on either side).
## - The loot goes to the hoard at once; it leaves the settlement when its Site is next opened, before its catch-up is
##   replayed (apply_to): the band's table keeps it under `raided` {site: {day, taken, source}}, and it counts only while
##   the Site's saved file is still `source` (a newer file of that Site already went without it). Every loot is at most
##   what that file still holds, so nothing is made from nothing.
## No class_name on purpose: callers preload it.
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Aftermath = preload("res://scripts/terrain_lab/site_bandit_aftermath.gd")
const RegionTravelRules = preload("res://scripts/region_lab/region_travel.gd")
const SiteFiles = preload("res://scripts/terrain_lab/site_store.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")

const CIVIL_WEIGHT := 0.5
const ODDS := 8.0
## Of a band that loses, this share comes home: it breaks off when half of it is down.
const LOSER_SURVIVES := 0.5
const CACHE_LIMIT := 512

# --- What a saved Site holds ------------------------------------------------------------------------------------------
## {owner (faction or -1), stock, people: {"faction": {armed, civil}}} of a saved Site state: able people only. Pure.
static func summary_of(state: Dictionary) -> Dictionary:
	var settlement: Variant = state.get("settlement", {})
	var owner := int(settlement.get("owner_faction", -1)) if settlement is Dictionary and settlement.has("owner_faction") else -1
	var people := {}
	for army: Variant in state.get("armies", []):
		if not army is Dictionary: continue
		var faction := str(int(army.get("faction_id", -1)))
		for unit: Variant in army.get("units", []):
			if not unit is Dictionary or not RegionTravelRules._able(unit): continue
			if not people.has(faction): people[faction] = {"armed": 0, "civil": 0}
			people[faction]["civil" if str(unit.get("military_role", "")) == "civilian" else "armed"] += 1
	for actor: Variant in state.get("actors", {}).values():
		if not actor is Dictionary or not RegionTravelRules._able(actor): continue
		var faction := str(int(actor.get("faction_id", -1)))
		if not people.has(faction): people[faction] = {"armed": 0, "civil": 0}
		people[faction]["civil" if str(actor.get("military_role", "")) == "civilian" else "armed"] += 1
	return {"owner": owner, "stock": Aftermath.stock_of(state, owner) if owner >= 0 else {}, "people": people}

## The summary of the Site file `key` ("x:y") names now: {ok, summary} or a refusal. A file is read once (its sha256 is the
## key): 2 to 5 ms for an unopened Site of the demo scenario (measured 2026-11-25).
static func summary(slot: Variant, key: String) -> Dictionary:
	var entry: Dictionary = slot._marker.get("sites", {}).get(key, {})
	if entry.is_empty(): return {"ok": false, "code": "NO_FILE"}
	var sha := str(entry.get("sha256", ""))
	var cache: Dictionary = slot.get_meta(&"bandit_site_summaries", {})
	var known: Dictionary = cache.get(key, {})
	if not known.is_empty() and str(known.sha) == sha: return known.value
	var read: Dictionary = SiteFiles._read(slot.folder.path_join(str(entry.path)))
	var value := {"ok": true, "summary": summary_of(read.payload.state)} if read.get("ok", false) else {"ok": false, "code": str(read.get("code", "READ"))}
	if cache.size() >= CACHE_LIMIT and not cache.has(key): cache.erase(cache.keys()[0])
	cache[key] = {"sha": sha, "value": value}
	slot.set_meta(&"bandit_site_summaries", cache)
	return value

# --- Which Sites --------------------------------------------------------------------------------------------------------
static func site_key(site_id: String) -> String:
	var parts := site_id.split(":")
	if parts.size() < 3 or not parts[parts.size() - 2].is_valid_int() or not parts[parts.size() - 1].is_valid_int(): return ""
	return "%s:%s" % [parts[parts.size() - 2], parts[parts.size() - 1]]

static func site_id(slot: Variant, key: String) -> String:
	return "%s:%s" % [str(slot.pin.atlas_id), key]

## An open Site has real bodies: the active one, a bound cold owner, or a cold result waiting for its checkpoint.
static func is_open(slot: Variant, id: String) -> bool:
	return id == str(slot.control.active_site_id) or slot._region_original_labs.has(id) or slot._fire_cold_candidates.has(id) \
		or bool(slot.control.get("fire_clock", {}).get("index", {}).get(id, {}).get("fire_active", false))

## The saved Sites (keys) within reach of `lair`, sorted.
static func near_keys(slot: Variant, lair: String) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in slot._marker.get("sites", {}):
		if Bandit.site_distance(lair, site_id(slot, str(key))) <= Bandit.REACH_SITES: result.append(str(key))
	result.sort()
	return result

## What is left of a saved stock after the loots that have not left it yet.
static func stock_left(slot: Variant, id: String, stock: Dictionary) -> Dictionary:
	var left := stock.duplicate()
	var owed := debts(slot, id)
	for item: String in owed.taken:
		left[item] = maxi(0, int(left.get(item, 0)) - int(owed.taken[item]))
		if int(left[item]) == 0: left.erase(item)
	return left

## The people who stand against `band` there: everybody able but the band's own and the neutral side, the unarmed ones
## counted CIVIL_WEIGHT each.
static func defence(people: Dictionary, band: int) -> float:
	var total := 0.0
	for faction: String in people:
		if int(faction) == band or int(faction) == RegionFactionQuery.NEUTRAL_FACTION_ID: continue
		total += float(people[faction].armed) + CIVIL_WEIGHT * float(people[faction].civil)
	return total

## What the chief reckons with.
static func estimate(people: Dictionary, band: int) -> float:
	return maxf(0.5, defence(people, band))

static func attack(people: Dictionary, band: int) -> int:
	return int(people.get(str(band), {}).get("armed", 0))

## The settlements within reach of `lair` the chief of `band` knows about, as raid targets.
## A target: {kind "settlement", id, site_id, strength (the chief's estimate), defence, faction, far true, open, stock}. An open Site is counted from its bodies.
static func known_settlements(slot: Variant, band: int, lair: String) -> Array:
	var targets: Array = []
	for key: String in near_keys(slot, lair):
		var id := site_id(slot, key)
		if is_open(slot, id):
			var seen := open_settlement(slot, id, band)
			if not seen.is_empty(): targets.append(seen)
			continue
		var read := summary(slot, key)
		if not read.ok: continue
		var owner := int(read.summary.owner)
		if owner < 0 or owner == band: continue
		var people: Dictionary = read.summary.people
		if not people.has(str(owner)): continue # nobody of the owner's is left to lose anything
		targets.append({"kind": "settlement", "id": id, "site_id": id, "strength": estimate(people, band), "defence": defence(people, band), "faction": owner, "far": true, "open": false,
			"stock": stock_left(slot, id, read.summary.stock)})
	return targets

## The same for an open Site (the active one or a bound cold owner), from its living people; {} when it is no settlement.
static func open_settlement(slot: Variant, id: String, band: int) -> Dictionary:
	var lab: Variant = slot._region_original_labs.get(id)
	if id == str(slot.control.active_site_id) and slot.region_contact_active_data.is_valid():
		var active: Variant = slot.region_contact_active_data.call()
		lab = slot._region_bound_original_lab(active.data) if active is Dictionary and active.get("ok", false) else null
	if lab == null or not is_instance_valid(lab) or lab.terrain == null or lab.crowd_site == null or not lab.crowd_site.active: return {}
	var settlement: Variant = lab.terrain.site.get("settlement", {})
	if not settlement is Dictionary or not settlement.has("owner_faction") or int(settlement.owner_faction) == band: return {}
	var owner := int(settlement.owner_faction)
	var people := {}
	for team: Dictionary in lab.crowd_site.teams:
		if bool(team.get("departed", false)): continue
		var faction := str(int(team.get("faction", -1)))
		for person: Variant in team.get("person_ids", []):
			var body: Dictionary = lab.crowd_site.combat_target(int(person))
			if body.is_empty() or float(body.get("hp", 0.0)) <= 0.0: continue
			var role: String = SiteOffices.body_military_role(lab.site_controller.person_actions._person(int(person), false).get("body"))
			if not people.has(faction): people[faction] = {"armed": 0, "civil": 0}
			people[faction]["civil" if role == "civilian" else "armed"] += 1
	if not people.has(str(owner)): return {}
	return {"kind": "settlement", "id": id, "site_id": id, "strength": estimate(people, band), "defence": defence(people, band), "faction": owner, "far": true, "open": true,
		"stock": Aftermath.stock_of(lab.terrain.site, owner)}

# --- The raid -----------------------------------------------------------------------------------------------------------
## The outcome of `attackers` against a defence of `defenders` strength with a roll in 0..1:
## {won, standing (raiders on their feet after it)}: the chance to win is A^8 / (A^8 + D^8), the winner keeps
## sqrt(A² - 3/4 D²) on their feet (at least one; the fight ends with half of the defenders down). Pure.
static func outcome(attackers: int, defenders: float, roll: float) -> Dictionary:
	var a := float(maxi(0, attackers))
	var d := maxf(0.0, defenders)
	if a <= 0.0: return {"won": false, "standing": 0}
	var won := roll < pow(a, ODDS) / (pow(a, ODDS) + pow(d, ODDS))
	return {"won": won, "standing": maxi(1, floori(sqrt(maxf(0.0, a * a - 0.75 * d * d)) + 0.5)) if won else 0}

## The same raid on the same day always rolls the same (a reload changes nothing).
static func roll(slot: Variant, band: int, id: String, day: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s|%d|%s|%d" % [str(slot.pin.get("world_instance_id", "")), band, id, day]).hash()
	return rng.randf()

## `band` raids the settlement `target` (known_settlements) with `attackers` people: a registry candidate with the heat,
## the hoard and the debt of the Site. Returns {ok, registry, won, standing, taken}.
static func settle(slot: Variant, registry: Dictionary, band: int, target: Dictionary, attackers: int, day: int) -> Dictionary:
	var now := float(slot.control.logical_game_seconds)
	var id := str(target.site_id)
	var result := outcome(attackers, float(target.defence), roll(slot, band, id, day))
	var taken: Dictionary = Aftermath.plunder(target.get("stock", {}), int(result.standing)) if result.won else {}
	var lost := 0 if result.won else attackers - floori(float(attackers) * LOSER_SURVIVES)
	var source := str(slot._marker.get("sites", {}).get(site_key(id), {}).get("path", ""))
	var raided := Bandit.raided(registry, band, id, day, taken, source, now, lost)
	if not raided.ok: return raided
	return {"ok": true, "registry": raided.registry, "won": bool(result.won), "standing": int(result.standing), "taken": taken, "lost": lost}

# --- What the Site still owes -------------------------------------------------------------------------------------------
## What left the Site `id` by formula raids and is still in its saved file: {taken {item: n}, rows [{band, day, taken}]}.
static func debts(slot: Variant, id: String) -> Dictionary:
	var result := {"taken": {}, "rows": []}
	var entry: Dictionary = slot._marker.get("sites", {}).get(site_key(id), {})
	if entry.is_empty(): return result
	var registry: Dictionary = slot.control.get("faction_registry", {})
	var keys: Array = registry.get("entries", {}).keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for key: Variant in keys:
		var table: Variant = registry.entries[key].get("bandit")
		if not table is Dictionary or not table.get("raided") is Dictionary: continue
		var row: Variant = table.raided.get(id)
		if not row is Dictionary or row.get("taken", {}).is_empty() or str(row.get("source", "")) != str(entry.get("path", "")): continue
		result.rows.append({"band": int(registry.entries[key].faction_id), "day": int(row.day), "taken": row.taken.duplicate()})
		for item: String in row.taken: result.taken[item] = int(result.taken.get(item, 0)) + int(row.taken[item])
	return result

## Takes what the Site owes out of its opened body (the camp stock first, then the warehouses): called once when the
## Site's saved file becomes living bodies, before its catch-up runs. Returns the rows applied.
static func apply_to(slot: Variant, data: TerrainData) -> Array:
	if slot == null or data == null or data.site.is_empty(): return []
	var id := str(data.site.get("id", ""))
	var owed := debts(slot, id)
	if owed.rows.is_empty(): return []
	var site: Dictionary = data.site
	var settlement: Variant = site.get("settlement", {})
	var owner := int(settlement.get("owner_faction", -1)) if settlement is Dictionary else -1
	if not site.get("inventory") is Dictionary: site["inventory"] = {}
	var keys: Array[String] = Aftermath.warehouses(site, owner)
	for item: String in owed.taken:
		var left := int(owed.taken[item])
		for source: String in ["inventory"] + keys:
			if left <= 0: break
			var holder: Dictionary = site.inventory if source == "inventory" else site.stockpiles[source].cargo
			var n := mini(left, int(holder.get(item, 0)))
			if n <= 0: continue
			holder[item] = int(holder[item]) - n
			if int(holder[item]) <= 0: holder.erase(item)
			left -= n
			if source != "inventory": site.stockpiles[source].holder["version"] = int(site.stockpiles[source].holder.version) + 1
	data.environment_revision += 1
	# A Site's notices are not kept over its catch-up: the news waits on the slot until somebody stands there (tell).
	var news: Dictionary = slot.get_meta(&"bandit_loot_news", {})
	news[id] = []
	for row: Dictionary in owed.rows:
		var goods: Array = []
		for item: String in row.taken: goods.append("%s %d" % [item, int(row.taken[item])])
		news[id].append("第 %d 日遭 %s 劫掠，失去 %s" % [int(row.day), str(RegionFactionQuery.display(slot.control.faction_registry, int(row.band)).name), "、".join(goods)])
	slot.set_meta(&"bandit_loot_news", news)
	return owed.rows

## The news of the raids on the Site the player stands in, once. Called at rest by its owner.
static func tell(controller: Variant) -> Array:
	var slot: Variant = controller.region_slot
	if slot == null or controller.lab == null or controller.lab.terrain == null or not slot.has_meta(&"bandit_loot_news"): return []
	var news: Dictionary = slot.get_meta(&"bandit_loot_news")
	var told: Array = news.get(str(controller.lab.terrain.site.get("id", "")), [])
	if told.is_empty(): return []
	news.erase(str(controller.lab.terrain.site.id))
	if controller.lab.terrain.site.get("notices") is Array: controller.lab.terrain.site.notices.append_array(told)
	return told

## The lair of a band with lost people is open (the active Site or a bound cold owner): they die there, soldiers first,
## then officers, the chief last, each by the same way hunger or age kills; the registry is saved without them. `saver` =
## the active Site's controller. Called at rest. Returns the ids that died now.
static func settle_fallen(controller: Variant, saver: Variant) -> Array:
	var died: Array = []
	var slot: Variant = controller.region_slot
	var lab: Variant = controller.lab
	if slot == null or lab == null or lab.terrain == null or lab.crowd_site == null or not lab.crowd_site.active: return died
	var registry: Dictionary = slot.control.get("faction_registry", {})
	if registry.get("version") != RegionFactionQuery.VERSION: return died
	var here := str(lab.terrain.site.get("id", ""))
	var now := float(slot.control.logical_game_seconds)
	if now < float(controller.get_meta(&"bandit_fallen_after", -INF)): return died
	for key: Variant in registry.get("entries", {}):
		var band := int(registry.entries[key].faction_id)
		var table: Variant = registry.entries[key].get("bandit")
		if not table is Dictionary or int(table.get("fallen", 0)) <= 0 or not table.get("lair") is Dictionary or str(table.lair.site_id) != here: continue
		var done: Dictionary = controller.get_meta(&"bandit_fallen_dead", {})
		if not done.has(band):
			var chief: int = slot.person_id_of_ref(registry.entries[key].get("leader_ref"))
			var rows: Array = []
			for team: Dictionary in lab.crowd_site.teams:
				if bool(team.get("departed", false)) or int(team.get("faction", -1)) != band: continue
				for person: Variant in team.get("person_ids", []):
					var body: Dictionary = controller.person_actions._person(int(person), false)
					if body.is_empty() or float(body.get("hp", 0.0)) <= 0.0: continue
					rows.append([2 if int(person) == chief else (1 if SiteOffices.body_military_role(body.get("body")) == "officer" else 0), int(person), float(body.hp)])
			rows.sort()
			for row: Array in rows.slice(0, int(table.fallen)):
				controller._apply_supply_damage(int(row[1]), float(row[2]))
				died.append(int(row[1]))
			done[band] = died.size()
			controller.set_meta(&"bandit_fallen_dead", done)
			if lab.terrain.site.get("notices") is Array and not died.is_empty(): lab.terrain.site.notices.append("%s 有 %d 人沒有從劫掠回來" % [str(RegionFactionQuery.display(registry, band).name), died.size()])
		var settled: Dictionary = Bandit.fallen_settled(slot.control.faction_registry, band, now)
		var saved: Dictionary = saver._commit_diplomacy(settled, "") if settled.ok else settled
		if not saved.get("ok", false):
			controller.set_meta(&"bandit_fallen_after", now + 600.0) # the deaths are still settling: saved later
			return died
		done.erase(band)
		controller.set_meta(&"bandit_fallen_dead", done)
		registry = slot.control.faction_registry
	return died

# --- The day ------------------------------------------------------------------------------------------------------------
## Once a game day at rest, by the active Site's owner: every band whose lair is not open makes its raid move. A chosen
## settlement that is open musters the lair instead: it is bound at the next hour's evaluation and its band then really goes. Returns {day, raids: [...]} when the day was settled, else {}.
static func day(controller: Variant) -> Dictionary:
	var slot: Variant = controller.region_slot
	if slot == null or controller.lab == null or controller.lab.terrain == null: return {}
	if str(slot.control.active_site_id) != str(controller.lab.terrain.site.get("id", "")): return {}
	var now := float(slot.control.logical_game_seconds)
	var today := int(now / float(Bandit.DAY))
	if today < 1 or int(slot.get_meta(&"bandit_formula_day", -1)) == today: return {}
	if now < float(slot.get_meta(&"bandit_formula_after", -INF)): return {}
	var registry: Dictionary = slot.control.get("faction_registry", {})
	if registry.get("version") != RegionFactionQuery.VERSION: return {}
	var player_ref: Dictionary = JoinFaction._world_ref(controller, int(controller.lab.controlled_person_id()))
	var moves: Array = []
	var keys: Array = registry.get("entries", {}).keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for key: Variant in keys:
		var entry: Dictionary = registry.entries[key]
		var band := int(entry.faction_id)
		if str(entry.get("status", "")) != "active" or not RegionFactionQuery.is_bandit(registry, band): continue
		if not player_ref.is_empty() and RegionPeerage.same_ref(entry.get("leader_ref"), player_ref): continue
		var table: Dictionary = RegionFactionQuery.bandit_of(registry, band)
		if not table.lair is Dictionary or not bool(table.raid_ai) or int(table.heat) >= Bandit.HEAT_MOVE or not Bandit.raid_rested(table, today): continue
		var lair := str(table.lair.site_id)
		if is_open(slot, lair): continue
		var home := summary(slot, site_key(lair))
		if not home.ok: continue
		var attackers := attack(home.summary.people, band) - int(table.get("fallen", 0))
		if attackers < 2: continue
		moves.append({"band": band, "lair": lair, "attackers": attackers, "targets": known_settlements(slot, band, lair)})
	var candidate := registry
	var result := {"day": today, "raids": [], "mustered": []}
	for move: Dictionary in moves:
		var targets: Array = []
		for target: Dictionary in move.targets:
			var row := target.duplicate()
			if not bool(row.open): row["stock"] = _left(candidate, str(row.site_id), row.stock, slot)
			if not row.stock.is_empty(): targets.append(row) # nothing to carry off: not worth the way
		var chosen := Bandit.pick_raid(candidate, int(move.band), targets, float(move.attackers), today)
		if chosen.is_empty(): continue
		if bool(chosen.open):
			result.mustered.append({"band": int(move.band), "lair": str(move.lair), "target": str(chosen.site_id)})
			continue
		var settled := settle(slot, candidate, int(move.band), chosen, int(move.attackers), today)
		if not settled.ok:
			result.raids.append({"band": int(move.band), "target": str(chosen.site_id), "ok": false, "code": str(settled.get("code", ""))})
			continue
		candidate = settled.registry
		result.raids.append({"band": int(move.band), "target": str(chosen.site_id), "ok": true, "attackers": int(move.attackers), "strength": float(chosen.strength), "defence": float(chosen.defence), "won": bool(settled.won), "standing": int(settled.standing), "taken": settled.taken, "lost": int(settled.lost)})
	if not is_same(candidate, registry):
		var committed: Dictionary = controller._commit_diplomacy({"ok": true, "registry": candidate}, "")
		if not committed.get("ok", false):
			slot.set_meta(&"bandit_formula_after", now + 3600.0) # tried again in an hour
			slot.set_meta(&"bandit_formula_refused", {"at": now, "code": str(committed.get("code", "")), "message": str(committed.get("message", ""))})
			return {"day": today, "refused": str(committed.get("code", "")), "raids": []}
	for muster: Dictionary in result.mustered:
		var next: float = (floorf(now / slot.REGION_EVALUATION_SECONDS) + 1.0) * slot.REGION_EVALUATION_SECONDS
		slot.queue_region_event("evaluation:%s:%.6f" % [str(muster.lair), next], "evaluation", next, str(muster.lair))
		var open: Dictionary = slot.get_meta(&"bandit_musters", {})
		open[str(muster.lair)] = today
		slot.set_meta(&"bandit_musters", open)
	slot.set_meta(&"bandit_formula_day", today)
	slot.set_meta(&"bandit_formula_last", result)
	return result

## The saved stock of `id` after the loots already written in the candidate registry (an earlier band's raid this day).
static func _left(registry: Dictionary, id: String, stock: Dictionary, slot: Variant) -> Dictionary:
	var left := stock.duplicate()
	var source := str(slot._marker.get("sites", {}).get(site_key(id), {}).get("path", ""))
	for key: Variant in registry.get("entries", {}):
		var now_row: Variant = _row(registry, key, id)
		var old_row: Variant = _row(slot.control.faction_registry, key, id)
		if not now_row is Dictionary or str(now_row.get("source", "")) != source or now_row == old_row: continue
		for item: String in now_row.get("taken", {}):
			var before := int(old_row.taken.get(item, 0)) if old_row is Dictionary and str(old_row.get("source", "")) == source else 0
			left[item] = maxi(0, int(left.get(item, 0)) - (int(now_row.taken[item]) - before))
			if int(left[item]) == 0: left.erase(item)
	return left

static func _row(registry: Dictionary, key: Variant, id: String) -> Variant:
	var table: Variant = registry.get("entries", {}).get(key, {}).get("bandit")
	return table.raided.get(id) if table is Dictionary and table.get("raided") is Dictionary else null
