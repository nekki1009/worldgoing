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

## Heat after an event: "raid" +10, "attacked" +20, or `days` of quiet (-5 per whole 10 days); 0..100.
static func heat_after(heat: int, event: String, days: int = 0) -> int:
	match event:
		"raid": heat += HEAT_RAID
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

