extends RefCounted
## Bandit band transactions on the faction registry (reports/bandit-faction-spec.md §5.3, §6, §8). Pure candidates;
## RegionSaveSlot owns publication (callers checkpoint the returned registry with the Site in one Region checkpoint).
## No class_name on purpose: callers preload it.
## Fewer free members than this left in a band disperses it (bandit spec §12).
const MIN_BAND := 3
## Bandit spec §6.6: the official who brings a band in, or who wipes one out, gains prestige once per band.
const AMNESTY_PRESTIGE := 3
const SUPPRESS_PRESTIGE := 3

static func fail(code: String, message: String = "") -> Dictionary:
	return {"ok": false, "code": code, "message": message}

static func _active_band(registry: Dictionary, band: int) -> Dictionary:
	if not RegionFactionQuery.is_bandit(registry, band): return fail("NOT_BANDIT", "不是土匪")
	var entry: Dictionary = registry.entries[str(band)]
	if entry.status != "active": return fail("NO_FACTION", "這伙土匪已不存在")
	return {"ok": true, "entry": entry}

static func _candidate(registry: Dictionary) -> Dictionary:
	if int(registry.get("revision", 0)) >= RegionFactionQuery.MAX_REVISION: return {}
	var candidate: Dictionary = registry.duplicate(true)
	candidate.revision = int(candidate.get("revision", 0)) + 1
	return candidate

static func _finish(candidate: Dictionary, now: float) -> Dictionary:
	if candidate.is_empty(): return fail("FACTION_REVISION_EXHAUSTED")
	var checked: Dictionary = RegionFactionQuery.validate(candidate, now)
	if not checked.ok: return checked
	return {"ok": true, "registry": candidate}

## §5.3: the new chief (the present member with the highest prestige, chosen by the caller) takes over at once.
static func succeed(registry: Dictionary, band: int, heir_ref: Variant, now: float) -> Dictionary:
	var current: Dictionary = _active_band(registry, band)
	if not current.ok: return current
	if not RegionFactionQuery.ref_valid(heir_ref, "person"): return fail("INVALID_HEIR", "接任的頭目沒有世界身分")
	var candidate := _candidate(registry)
	if candidate.is_empty(): return fail("FACTION_REVISION_EXHAUSTED")
	candidate.entries[str(band)].leader_ref = RegionPeerage.canonical_ref(heir_ref)
	return _finish(candidate, now)

## §8: the band disperses. Its id ends as extinct (never reused) and its lair is cleared; the caller turns the people into
## one-person neutral teams in the same transaction.
static func disperse(registry: Dictionary, band: int, now: float) -> Dictionary:
	var current: Dictionary = _active_band(registry, band)
	if not current.ok: return current
	var candidate := _candidate(registry)
	if candidate.is_empty(): return fail("FACTION_REVISION_EXHAUSTED")
	var entry: Dictionary = candidate.entries[str(band)]
	entry.status = "extinct"
	entry.ended_at = now
	var table: Dictionary = RegionFactionQuery.canonical_bandit(entry.get("bandit", {}))
	table.lair = null
	entry.bandit = table
	return _finish(candidate, now)

## §6.4–6.5: the end of an amnesty for the band entry. Nobody stays: merged into the accepting faction. Fewer than MIN_BAND
## stay: dispersed. Otherwise `heir_ref` leads the rest.
static func amnesty_end(registry: Dictionary, band: int, accepting_faction: int, staying: int, heir_ref: Variant, now: float) -> Dictionary:
	var current: Dictionary = _active_band(registry, band)
	if not current.ok: return current
	if RegionFactionQuery.is_bandit(registry, accepting_faction) or not RegionFactionQuery.active(registry, accepting_faction).ok or accepting_faction == RegionFactionQuery.NEUTRAL_FACTION_ID: return fail("NO_FACTION", "招安方須是有效的正式勢力")
	if staying >= MIN_BAND: return succeed(registry, band, heir_ref, now)
	if staying > 0: return disperse(registry, band, now)
	var candidate := _candidate(registry)
	if candidate.is_empty(): return fail("FACTION_REVISION_EXHAUSTED")
	var entry: Dictionary = candidate.entries[str(band)]
	entry.status = "merged"
	entry.merged_into = accepting_faction
	entry.ended_at = now
	var table: Dictionary = RegionFactionQuery.canonical_bandit(entry.get("bandit", {}))
	table.lair = null
	entry.bandit = table
	return _finish(candidate, now)

## §6.3: the chief's will to come in: the officer follow score towards the official, plus heat / 5 (hunted bands give in).
static func chief_score(chief_mind: Variant, official_mind: Variant, heat: int) -> float:
	return RegionPeerage.follow_score(chief_mind, official_mind, chief_mind) + float(heat) / 5.0

## --- B4a: heat, lair moves and kind conversion (bandit spec §5.2, §9, §11, §12) ---
const HEAT_RAID := 10
const HEAT_FENCE := 5
const HEAT_ATTACKED := 20
const HEAT_DECAY := 5
const HEAT_DECAY_DAYS := 10
const HEAT_MOVE := 70
const HEAT_AFTER_MOVE := 30
const RISE_PRESTIGE := 30
const RISE_MEMBERS := 30
const RISE_MAX_HEAT := 50
const RISE_NPC_AMBITION := 60
const FALL_NPC_DAYS := 30
const DAY := 86400.0

## Heat after an event: "raid" +10, "attacked" +20, "fence" +5 (one sale of stolen goods, B5b §7.1), or `days` of
## quiet (-5 per whole 10 days); 0..100.
static func heat_after(heat: int, event: String, days: int = 0) -> int:
	match event:
		"raid": heat += HEAT_RAID
		"fence": heat += HEAT_FENCE
		"attacked": heat += HEAT_ATTACKED
		"quiet": heat -= HEAT_DECAY * int(maxi(0, days) / HEAT_DECAY_DAYS)
	return clampi(heat, 0, RegionFactionQuery.BANDIT_HEAT_MAX)

static func _with_table(registry: Dictionary, band: int, change: Callable, now: float) -> Dictionary:
	var current: Dictionary = _active_band(registry, band)
	if not current.ok: return current
	var candidate := _candidate(registry)
	if candidate.is_empty(): return fail("FACTION_REVISION_EXHAUSTED")
	var entry: Dictionary = candidate.entries[str(band)]
	var table: Dictionary = RegionFactionQuery.canonical_bandit(entry.get("bandit", {}))
	change.call(table)
	entry.bandit = table
	return _finish(candidate, now)

static func set_heat(registry: Dictionary, band: int, heat: int, now: float) -> Dictionary:
	return _with_table(registry, band, func(table: Dictionary) -> void: table.heat = clampi(heat, 0, RegionFactionQuery.BANDIT_HEAT_MAX), now)

## §5.2: a new lair ({site_id, cell}) or none; a move at heat >= 70 drops the heat to 30.
static func move_lair(registry: Dictionary, band: int, site_id: String, cell: Vector2i, now: float) -> Dictionary:
	var hot := int(RegionFactionQuery.bandit_of(registry, band).get("heat", 0)) >= HEAT_MOVE
	return _with_table(registry, band, func(table: Dictionary) -> void:
		table.lair = {"site_id": site_id, "cell": [cell.x, cell.y]}
		if hot: table.heat = HEAT_AFTER_MOVE, now)

## §9.1 gate: chief prestige >= 30, members >= 30, heat < 50; an NPC chief also needs ambition >= 60.
static func may_rise(registry: Dictionary, band: int, chief_prestige_shown: int, members: int, npc_ambition: int = -1) -> Dictionary:
	var current: Dictionary = _active_band(registry, band)
	if not current.ok: return current
	var heat := int(RegionFactionQuery.bandit_of(registry, band).heat)
	if chief_prestige_shown < RISE_PRESTIGE: return fail("RISE_PRESTIGE", "頭目威望須至少 %d" % RISE_PRESTIGE)
	if members < RISE_MEMBERS: return fail("RISE_MEMBERS", "須至少 %d 人" % RISE_MEMBERS)
	if heat >= RISE_MAX_HEAT: return fail("RISE_HEAT", "官府追剿太緊（heat %d）" % heat)
	if npc_ambition >= 0 and npc_ambition < RISE_NPC_AMBITION: return fail("RISE_AMBITION", "頭目沒有起義的野心")
	return {"ok": true}

## §9.1: same faction id, kind rebel, the sub-table gone, the chief crowned king of it. Hostility stays; treaties become
## possible from now on. The caller checks may_rise and that the chief is free and out of any fight.
static func rise(registry: Dictionary, band: int, now: float) -> Dictionary:
	var current: Dictionary = _active_band(registry, band)
	if not current.ok: return current
	var candidate := _candidate(registry)
	if candidate.is_empty(): return fail("FACTION_REVISION_EXHAUSTED")
	var entry: Dictionary = candidate.entries[str(band)]
	var chief: Variant = entry.leader_ref
	entry.kind = "rebel"
	entry.erase("bandit")
	var checked := _finish(candidate, now)
	if not checked.ok: return checked
	if RegionPeerage.record_of(checked.registry, chief).is_empty():
		return RegionPeerage.crown_founder(checked.registry, band, RegionPeerage.canonical_ref(chief), now)
	return checked

## §9.2: a rebel faction without settlements, fiefs or nation (the caller proves those) falls to banditry: kind bandit,
## sub-table {origin fallen_rebel, converted_from {rebel, now}}, every treaty of it ends, every open letter is
## invalidated, and every peerage record of the faction ends (titles lose their power; vassals are released).
static func fall(registry: Dictionary, rebel_faction: int, lair: Variant, now: float) -> Dictionary:
	var resolved: Dictionary = RegionFactionQuery.active(registry, rebel_faction)
	if not resolved.ok: return resolved
	var entry_now: Dictionary = registry.entries.get(str(rebel_faction), {})
	if entry_now.get("kind") != "rebel": return fail("NOT_REBEL", "只有叛軍會落草")
	if entry_now.get("nation_ref") != null: return fail("HAS_NATION", "有國家須先解散")
	if not RegionFactionQuery.ref_valid(entry_now.get("leader_ref"), "person"): return fail("NO_HEAD", "叛軍沒有首長")
	var candidate := _candidate(registry)
	if candidate.is_empty(): return fail("FACTION_REVISION_EXHAUSTED")
	if candidate.has("diplomacy"):
		var diplomacy: Dictionary = candidate.diplomacy
		for treaty: Dictionary in diplomacy.get("treaties", {}).values():
			if treaty.status == "active" and (int(treaty.a) == rebel_faction or int(treaty.b) == rebel_faction):
				treaty.status = "ended"
				treaty.ended_at = now
		for proposal: Dictionary in diplomacy.get("proposals", {}).values():
			if proposal.status not in RegionDiplomacy.TERMINAL and (int(proposal.from) == rebel_faction or int(proposal.to) == rebel_faction):
				proposal.status = "invalidated"
				proposal.reason = "FELL_TO_BANDITRY"
	if candidate.has("peerage"):
		var kept := {}
		for key: String in candidate.peerage:
			if int(candidate.peerage[key].faction_id) != rebel_faction: kept[key] = candidate.peerage[key]
		candidate.peerage = kept
	var entry: Dictionary = candidate.entries[str(rebel_faction)]
	entry.kind = "bandit"
	entry.duty_ai = false
	entry["bandit"] = RegionFactionQuery.canonical_bandit({"origin": "fallen_rebel", "lair": lair, "converted_from": {"kind": "rebel", "at": now}})
	return _finish(candidate, now)

# --- B4b: protection money (bandit spec §5.1, §12) -------------------------------------------------------------------
const PROTECTION_DAYS := 30
const REACH_SITES := 2

## Chebyshev distance in Sites between two "atlas:x:y" Site ids; a large number when either is not a world Site.
static func site_distance(a: String, b: String) -> int:
	var pa := a.split(":")
	var pb := b.split(":")
	if pa.size() < 3 or pb.size() < 3 or not pa[pa.size() - 2].is_valid_int() or not pb[pb.size() - 2].is_valid_int() or not pa[pa.size() - 1].is_valid_int() or not pb[pb.size() - 1].is_valid_int(): return 1000000
	return maxi(absi(int(pa[pa.size() - 2]) - int(pb[pb.size() - 2])), absi(int(pa[pa.size() - 1]) - int(pb[pb.size() - 1])))

## The bands that may ask `site_id` for protection money today: active, raiding, lair within REACH_SITES, not asked in the
## last PROTECTION_DAYS and not currently paid. Sorted by faction id.
static func protection_due(registry: Dictionary, site_id: String, day: int) -> Array[int]:
	var result: Array[int] = []
	for key: String in registry.get("entries", {}):
		var entry: Dictionary = registry.entries[key]
		if entry.get("kind") != "bandit" or entry.get("status") != "active": continue
		var table: Dictionary = RegionFactionQuery.canonical_bandit(entry.get("bandit", {}))
		if not bool(table.raid_ai) or not table.lair is Dictionary or site_distance(str(table.lair.site_id), site_id) > REACH_SITES: continue
		var row: Dictionary = table.get("protection", {}).get(site_id, {})
		if not row.is_empty() and (day - int(row.asked) < PROTECTION_DAYS or int(row.until) >= day): continue
		result.append(int(key))
	result.sort()
	return result

## Population x 1 day of grain (§12).
static func protection_fee(population: int) -> int:
	return maxi(0, population)

static func protected(registry: Dictionary, band: int, site_id: String, day: int) -> bool:
	return int(RegionFactionQuery.bandit_of(registry, band).get("protection", {}).get(site_id, {}).get("until", -1)) >= day

## Records the answer: paid goods join the lair's hoard and protection lasts PROTECTION_DAYS; a refusal records until -1.
static func protection_answer(registry: Dictionary, band: int, site_id: String, day: int, paid: Dictionary, now: float) -> Dictionary:
	return _with_table(registry, band, func(table: Dictionary) -> void:
		var rows: Dictionary = table.get("protection", {})
		rows[site_id] = {"asked": day, "until": day + PROTECTION_DAYS if not paid.is_empty() else -1}
		table["protection"] = rows
		if not paid.is_empty():
			var hoard: Dictionary = table.get("hoard", {})
			for item: String in paid: hoard[item] = int(hoard.get(item, 0)) + int(paid[item])
			table["hoard"] = hoard, now)

# --- B4c: toll on the road (bandit spec §5.1, §12) -------------------------------------------------------------------
const TOLL_STRENGTH := 1.5
const TOLL_DAYS_PER_PERSON := 2
const TOLL_PASS_DAYS := 3

## People x 2 days of travel rations.
static func toll_fee(people: int) -> int:
	return maxi(0, people) * TOLL_DAYS_PER_PERSON

## May the band offer a toll to this party: the band is at least 1.5 times as strong and the party holds no paid pass.
static func toll_offer(registry: Dictionary, band: int, party_token: String, band_strength: float, party_strength: float, day: int) -> bool:
	if not RegionFactionQuery.is_bandit(registry, band) or party_strength <= 0.0 or band_strength < party_strength * TOLL_STRENGTH: return false
	return int(RegionFactionQuery.bandit_of(registry, band).get("passes", {}).get(party_token, -1)) < day

## An NPC party's answer (§5.1: the chief's greed against the party's nerve): it pays when it carries the fee and its
## captain is not bold (risk under 60); a bold captain, or one who cannot pay, fights.
static func npc_pays_toll(captain_risk: int, carried_food: int, fee: int) -> bool:
	return carried_food >= fee and captain_risk < 60

## A paid toll: the food joins the hoard and the party passes for TOLL_PASS_DAYS; expired passes are dropped.
static func toll_paid(registry: Dictionary, band: int, party_token: String, day: int, paid: Dictionary, now: float) -> Dictionary:
	return _with_table(registry, band, func(table: Dictionary) -> void:
		var passes: Dictionary = table.get("passes", {})
		for token: Variant in passes.keys():
			if int(passes[token]) < day: passes.erase(token)
		if passes.size() >= 64: passes.erase(passes.keys()[0])
		passes[party_token] = day + TOLL_PASS_DAYS
		table["passes"] = passes
		var hoard: Dictionary = table.get("hoard", {})
		for item: String in paid: hoard[item] = int(hoard.get(item, 0)) + int(paid[item])
		if not hoard.is_empty(): table["hoard"] = hoard, now)

## BA-12: the lairs a player may see on the Region map: active bands whose lair stands on a Site the player has visited
## (a saved generation there). [{site: Vector2i, name}], in faction id order. Pure.
static func known_lairs(registry: Dictionary, visited: Array) -> Array:
	var result: Array = []
	if registry.get("version") != RegionFactionQuery.VERSION: return result
	var keys: Array = registry.get("entries", {}).keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for key: Variant in keys:
		var entry: Dictionary = registry.entries[key]
		if str(entry.get("status", "")) != "active" or not RegionFactionQuery.is_bandit(registry, int(entry.faction_id)): continue
		var lair: Variant = RegionFactionQuery.bandit_of(registry, int(entry.faction_id)).get("lair")
		if not lair is Dictionary: continue
		var parts := str(lair.get("site_id", "")).split(":")
		if parts.size() < 3 or not parts[parts.size() - 2].is_valid_int() or not parts[parts.size() - 1].is_valid_int(): continue
		var site := Vector2i(int(parts[parts.size() - 2]), int(parts[parts.size() - 1]))
		if site in visited: result.append({"site": site, "name": str(RegionFactionQuery.display(registry, int(entry.faction_id)).get("name", ""))})
	return result

# --- B4c step two: the toll on a travelling party's own content -------------------------------------------------------
const TOLL_FOODS := ["grain", "wild_food", "fish", "meat"]

## The faction of a travelling party: its first army's (a party of actors only has none: -1).
static func party_faction(party: Dictionary) -> int:
	for army: Variant in party.get("content", {}).get("armies", []):
		if army is Dictionary and army.has("faction_id"): return int(army.faction_id)
	return -1

## Living bodies of a travelling party (its strength for the toll: one per person able to stand).
static func party_people(party: Dictionary) -> int:
	var count := 0
	var content: Dictionary = party.get("content", {})
	for actor: Variant in content.get("actors", {}).values():
		if actor is Dictionary and float(actor.get("hp", 0.0)) > 0.0: count += 1
	for army: Variant in content.get("armies", []):
		if not army is Dictionary: continue
		for unit: Variant in army.get("units", []):
			if unit is Dictionary and float(unit.get("hp", 0.0)) > 0.0: count += 1
	return count

## The unopened food inventories of a party's shared supplies (the same dictionaries; whole units only).
static func _party_food_stores(party: Dictionary) -> Array:
	var stores: Array = []
	var supplies: Dictionary = party.get("content", {}).get("team_supply", {})
	var keys: Array = supplies.keys()
	keys.sort()
	for key: Variant in keys:
		var supply: Variant = supplies[key]
		if not supply is Dictionary: continue
		if int(supply.get("version", 0)) == 3:
			var places: Array = supply.get("locations", {}).keys()
			places.sort()
			for place: Variant in places:
				var location: Variant = supply.locations[place]
				if location is Dictionary and location.get("inventory") is Dictionary: stores.append(location.inventory)
		elif supply.get("inventory") is Dictionary: stores.append(supply.inventory)
	# The controlled person's own bag travels as the party's manual cargo; a party without a shared supply pays from it.
	if party.get("content", {}).get("manual_cargo") is Dictionary: stores.append(party.content.manual_cargo)
	return stores

static func party_food(party: Dictionary) -> int:
	var total := 0
	for store: Dictionary in _party_food_stores(party):
		for food: String in TOLL_FOODS: total += int(store.get(food, 0))
	return total

## Takes `fee` whole units of food from the party's shared supplies (grain first). Returns what was taken, or {} (and
## changes nothing) when the party carries less than the fee.
static func take_party_food(party: Dictionary, fee: int) -> Dictionary:
	if fee <= 0 or party_food(party) < fee: return {}
	var taken := {}
	var rest := fee
	for food: String in TOLL_FOODS:
		for store: Dictionary in _party_food_stores(party):
			if rest <= 0: break
			var units := mini(rest, int(store.get(food, 0)))
			if units <= 0: continue
			store[food] = int(store[food]) - units
			if int(store[food]) == 0: store.erase(food)
			taken[food] = int(taken.get(food, 0)) + units
			rest -= units
	return taken

# --- B4d: the chief's daily decision and band formation (bandit spec §4 B, §11, §12) ----------------------------------
const RAID_STRENGTH := 1.2
const FORM_MIN := 3
const FORM_WAIT_DAYS := 7

## May the band raid this target: within REACH_SITES of the lair, at least 1.2 times as strong, not protected by a paid
## fee (a settlement) or a paid pass (a party).
static func may_raid(registry: Dictionary, band: int, target: Dictionary, band_strength: float, day: int) -> bool:
	var table: Dictionary = RegionFactionQuery.bandit_of(registry, band)
	if table.is_empty() or not table.lair is Dictionary or not bool(table.raid_ai): return false
	if site_distance(str(table.lair.site_id), str(target.get("site_id", ""))) > REACH_SITES: return false
	if float(target.get("strength", 0.0)) <= 0.0 or band_strength < float(target.strength) * RAID_STRENGTH: return false
	if str(target.get("kind", "")) == "settlement" and protected(registry, band, str(target.site_id), day): return false
	if str(target.get("kind", "")) == "party" and int(table.get("passes", {}).get(str(target.get("token", "")), -1)) >= day: return false
	return true

## The best raid target: the nearest, then the weakest against the band, then the lower id. {} when none qualifies.
## A target: {kind "party"|"settlement", id, site_id, strength, token (party)}.
static func pick_raid(registry: Dictionary, band: int, targets: Array, band_strength: float, day: int) -> Dictionary:
	var lair: Variant = RegionFactionQuery.bandit_of(registry, band).get("lair")
	var best := {}
	var best_key: Array = []
	for target: Variant in targets:
		if not target is Dictionary or not may_raid(registry, band, target, band_strength, day): continue
		var key := [site_distance(str(lair.site_id), str(target.site_id)), float(target.strength) / band_strength, str(target.get("id", ""))]
		if best.is_empty() or key < best_key:
			best = target
			best_key = key
	return best

## The one action of the day for a band chief (§11), in the order of the spec: move the lair (heat >= 70), rise (§9.1),
## accept an amnesty on the table, ask the settlements whose fee is due, raid, else rest. `facts`:
## {day, heat, can_rise (bool), amnesty_score (float, < 0 none), amnesty_gate (float), protection_due ([site_id]),
##  targets ([target]), strength (float)}. Returns {action, ...}.
static func daily_decision(registry: Dictionary, band: int, facts: Dictionary) -> Dictionary:
	var day := int(facts.get("day", 0))
	if int(facts.get("heat", 0)) >= HEAT_MOVE: return {"action": "move_lair"}
	if bool(facts.get("can_rise", false)): return {"action": "rise"}
	if float(facts.get("amnesty_score", -1.0)) >= 0.0 and float(facts.amnesty_score) >= float(facts.get("amnesty_gate", 55.0)): return {"action": "accept_amnesty"}
	var due: Array = facts.get("protection_due", [])
	if not due.is_empty():
		var sites: Array = due.duplicate()
		sites.sort()
		return {"action": "demand_protection", "site_id": str(sites[0])}
	var target := pick_raid(registry, band, facts.get("targets", []), float(facts.get("strength", 0.0)), day)
	if not target.is_empty(): return {"action": "raid", "target": target}
	return {"action": "rest"}

## §4 B: do the survivors of a rout form a band today? At least FORM_MIN free living people of one side, FORM_WAIT_DAYS
## since the rout without returning to any settlement or team of their faction, and their faction is gone or their
## team no longer exists; never the controlled person. `survivors`: [{id, prestige, controlled (bool)}].
## Returns {ok, chief, members} or {ok false, reason}.
static func rout_band(survivors: Array, rout_day: int, day: int, faction_gone: bool, team_gone: bool, returned_home: bool) -> Dictionary:
	if returned_home: return {"ok": false, "reason": "returned"}
	if not (faction_gone or team_gone): return {"ok": false, "reason": "has_home"}
	if day - rout_day < FORM_WAIT_DAYS: return {"ok": false, "reason": "waiting"}
	var members: Array = []
	for person: Variant in survivors:
		if person is Dictionary and not bool(person.get("controlled", false)): members.append(person)
	if members.size() < FORM_MIN: return {"ok": false, "reason": "too_few"}
	members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("prestige", 0)) > int(b.get("prestige", 0)) or int(a.get("prestige", 0)) == int(b.get("prestige", 0)) and int(a.id) < int(b.id))
	var ids: Array = []
	for person: Dictionary in members: ids.append(int(person.id))
	return {"ok": true, "chief": int(members[0].id), "members": ids}

