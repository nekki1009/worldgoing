extends RefCounted
## 土匪：被官方攻打 (Nekki 2026-11-22 B; bandit spec §5.2, §12). A band is attacked when it fights a battle against an
## official faction (a registered faction that is neither a band nor a rebel, nor the neutral side), unless that battle
## is the band's own raid (its raid on that Site, ordered in the last RAID_DAYS days). Each attacked band's heat rises by
## Bandit.HEAT_ATTACKED and its table keeps the day (`attacked_day`); only a band attacked in the last
## Bandit.ATTACK_MEMORY_DAYS days moves its lair when hot (Bandit.daily_decision), a hot band never attacked lies low.
## Battles close inside the Site's Region point, where the registry cannot be saved: the rise waits on the Region slot
## (meta `bandit_attacked_due`, {band: day}; the slot, so an attack noted on a cold Site is not left on an owner that never
## stands at rest) and the active Site's owner saves it at rest with the daily hooks (flush), as fence heat is.
## A Site nobody watches has no battle log (its battle tracker follows the shared world combat clock and never opens),
## so `watch` reads the standing people there: once a game minute, where an active band's people and an official
## faction's people stand on one Site, a drop on either side since the last look is their fight. One record per band,
## Site and day (meta `bandit_attacked_marked`), shared with the battle log's own note. A band's open raid is kept on
## the Region slot (meta `bandit_raids_open`), so the owner of the Site it raids reads it too.
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")

const RAID_DAYS := 2
const WATCH_SECONDS := 60.0

## True for a registered official faction: not neutral, not a band, not a rebel.
static func official(registry: Dictionary, faction: int) -> bool:
	if faction < 0 or faction == RegionFactionQuery.NEUTRAL_FACTION_ID: return false
	var entry: Variant = registry.get("entries", {}).get(str(faction))
	if not entry is Dictionary: return false
	return str(entry.get("kind", "")) not in ["bandit", "rebel"]

## The bands a closed battle (RegionBattleLog entry: {site_id, sides}) counts as attacked on `today`. `raids` = the
## controller's open raids {band: {site_id, day}}. Pure.
static func attacked_bands(battle: Dictionary, registry: Dictionary, raids: Dictionary, today: int) -> Array[int]:
	var sides: Array[int] = []
	for key: Variant in battle.get("sides", {}): sides.append(int(battle.sides[key].get("faction", -1)))
	var has_official := false
	for faction: int in sides: has_official = has_official or official(registry, faction)
	var result: Array[int] = []
	if not has_official: return result
	for faction: int in sides:
		if not RegionFactionQuery.is_bandit(registry, faction) or registry.entries[str(faction)].get("status") != "active": continue
		var raid: Dictionary = raids.get(faction, {})
		if not raid.is_empty() and str(raid.get("site_id", "")) == str(battle.get("site_id", "")) and today - int(raid.get("day", -100)) <= RAID_DAYS: continue
		result.append(faction)
	result.sort()
	return result

## Notes a band's raid on `site_id` (site_bandit_day.run), so the battle it starts there is not counted as an attack.
static func note_raid(controller: Variant, band: int, site_id: String, today: int) -> void:
	if controller.region_slot == null: return
	var raids: Dictionary = controller.region_slot.get_meta(&"bandit_raids_open", {})
	raids[band] = {"site_id": site_id, "day": today}
	controller.region_slot.set_meta(&"bandit_raids_open", raids)

## Queues `band` as attacked today on this Site, once per band and day here. False when already noted.
static func _mark(controller: Variant, band: int, today: int) -> bool:
	var marked: Dictionary = controller.get_meta(&"bandit_attacked_marked", {})
	if int(marked.get(band, -1)) == today: return false
	marked[band] = today
	controller.set_meta(&"bandit_attacked_marked", marked)
	queue(controller, band, today)
	return true

## The standing people of each active band and of the official factions together on this Site: {bands: {band: n}, official: n}.
static func standing(controller: Variant, registry: Dictionary) -> Dictionary:
	var lab: Variant = controller.lab
	var bands := {}
	var officials := 0
	for team: Dictionary in lab.crowd_site.teams:
		if bool(team.get("departed", false)): continue
		var faction := int(team.get("faction", -1))
		var band: bool = RegionFactionQuery.is_bandit(registry, faction) and registry.entries[str(faction)].get("status") == "active"
		if not band and not official(registry, faction): continue
		var alive := 0
		for person: Variant in team.get("person_ids", []):
			var body: Dictionary = lab.crowd_site.combat_target(int(person))
			if not body.is_empty() and float(body.get("hp", 0.0)) > 0.0: alive += 1
		if band: bands[faction] = int(bands.get(faction, 0)) + alive
		else: officials += alive
	return {"bands": bands, "official": officials}

## Once a game minute: where an active band and an official faction stood on this Site at the last look, a drop in
## either side's standing people is their fight (the band's own raid here excepted). Returns the bands noted now.
static func watch(controller: Variant) -> Array:
	var noted: Array = []
	if controller == null or controller.region_slot == null or controller.lab == null: return noted
	var lab: Variant = controller.lab
	if lab.crowd_site == null or not lab.crowd_site.active or lab.terrain == null: return noted
	var now := float(controller.region_slot.control.logical_game_seconds)
	if now - float(controller.get_meta(&"bandit_watch_at", -INF)) < WATCH_SECONDS: return noted
	controller.set_meta(&"bandit_watch_at", now)
	var registry: Dictionary = controller.region_slot.control.get("faction_registry", {})
	if registry.get("version") != RegionFactionQuery.VERSION: return noted
	var seen: Dictionary = controller.get_meta(&"bandit_watch_seen", {})
	var current := standing(controller, registry)
	controller.set_meta(&"bandit_watch_seen", current)
	if seen.is_empty() or int(seen.get("official", 0)) <= 0: return noted
	var today := today_of(controller)
	var here := str(lab.terrain.site.get("id", ""))
	var raids: Dictionary = controller.region_slot.get_meta(&"bandit_raids_open", {})
	var official_fell: bool = int(current.official) < int(seen.official)
	var before: Dictionary = seen.get("bands", {})
	for band: Variant in before:
		if int(before[band]) <= 0: continue
		if int(current.bands.get(band, 0)) >= int(before[band]) and not official_fell: continue
		var raid: Dictionary = raids.get(band, {})
		if not raid.is_empty() and str(raid.get("site_id", "")) == here and today - int(raid.get("day", -100)) <= RAID_DAYS: continue
		if _mark(controller, int(band), today): noted.append(int(band))
	return noted

static func today_of(controller: Variant) -> int:
	return int(float(controller.region_slot.control.logical_game_seconds) / float(Bandit.DAY)) if controller.region_slot != null else 0

## Queues the bands `closed` (SiteController.close_battle's result) counts as attacked. Returns them.
static func note_battle(controller: Variant, closed: Dictionary) -> Array[int]:
	var result: Array[int] = []
	if controller.region_slot == null or not closed.get("battle") is Dictionary: return result
	var registry: Dictionary = controller.region_slot.control.get("faction_registry", {})
	if registry.get("version") != RegionFactionQuery.VERSION: return result
	var today := today_of(controller)
	result = attacked_bands(closed.battle, registry, controller.region_slot.get_meta(&"bandit_raids_open", {}), today)
	for band: int in result: _mark(controller, band, today)
	return result

static func queue(controller: Variant, band: int, day: int) -> void:
	if controller.region_slot == null: return
	var due: Dictionary = controller.region_slot.get_meta(&"bandit_attacked_due", {})
	due[band] = maxi(int(due.get(band, -1)), day)
	controller.region_slot.set_meta(&"bandit_attacked_due", due)

## Saves every queued attack in one registry commit (heat +20 each, attacked_day). {ok, flushed: {band: day}} or a refusal
## (kept queued).
static func flush(controller: Variant) -> Dictionary:
	var slot: Variant = controller.region_slot
	if slot == null: return Runtime.fail("UNSUPPORTED")
	var due: Dictionary = slot.get_meta(&"bandit_attacked_due", {})
	if due.is_empty(): return Runtime.ok("", {"flushed": {}})
	var lab: Variant = controller.lab
	# Only the active Site's owner saves it (a cold owner's settle runs inside its own Region point).
	if lab == null or lab.terrain == null or str(slot.control.active_site_id) != str(lab.terrain.site.get("id", "")): return Runtime.fail("NOT_ACTIVE_SITE")
	if not lab._region_point_pending.is_empty() or lab._region_point_consuming or lab._region_point_dispatching: return Runtime.fail("REGION_EFFECT_RUNNING")
	var now := float(slot.control.logical_game_seconds)
	var bands: Array = due.keys()
	bands.sort()
	var candidate := {"ok": true, "registry": slot.control.faction_registry}
	for band: Variant in bands:
		if not RegionFactionQuery.is_bandit(candidate.registry, int(band)) or candidate.registry.entries[str(int(band))].get("status") != "active": continue # ended meanwhile
		candidate = Bandit.attacked(candidate.registry, int(band), int(due[band]), now)
		if not candidate.ok: return candidate
	var committed: Dictionary = controller._commit_diplomacy(candidate, "")
	if not committed.ok: return committed
	slot.remove_meta(&"bandit_attacked_due")
	return Runtime.ok("", {"flushed": due})
