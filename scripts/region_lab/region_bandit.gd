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
