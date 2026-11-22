extends RefCounted
## 土匪：被官方攻打 (Nekki 2026-11-22 B; bandit spec §5.2, §12). A band is attacked when it fights a battle against an
## official faction (a registered faction that is neither a band nor a rebel, nor the neutral side), unless that battle
## is the band's own raid (its raid on that Site, ordered in the last RAID_DAYS days). Each attacked band's heat rises by
## Bandit.HEAT_ATTACKED and its table keeps the day (`attacked_day`); only a band attacked in the last
## Bandit.ATTACK_MEMORY_DAYS days moves its lair when hot (Bandit.daily_decision), a hot band never attacked lies low.
## Battles close inside the Site's Region point, where the registry cannot be saved: the rise waits on the controller
## (meta `bandit_attacked_due`, {band: day}) and is saved at rest with the daily hooks (flush), as fence heat is.
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")

const RAID_DAYS := 2

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
	var raids: Dictionary = controller.get_meta(&"bandit_raids_open", {})
	raids[band] = {"site_id": site_id, "day": today}
	controller.set_meta(&"bandit_raids_open", raids)

static func today_of(controller: Variant) -> int:
	return int(float(controller.region_slot.control.logical_game_seconds) / float(Bandit.DAY)) if controller.region_slot != null else 0

## Queues the bands `closed` (SiteController.close_battle's result) counts as attacked. Returns them.
static func note_battle(controller: Variant, closed: Dictionary) -> Array[int]:
	var result: Array[int] = []
	if controller.region_slot == null or not closed.get("battle") is Dictionary: return result
	var registry: Dictionary = controller.region_slot.control.get("faction_registry", {})
	if registry.get("version") != RegionFactionQuery.VERSION: return result
	var today := today_of(controller)
	result = attacked_bands(closed.battle, registry, controller.get_meta(&"bandit_raids_open", {}), today)
	for band: int in result: queue(controller, band, today)
	return result

static func queue(controller: Variant, band: int, day: int) -> void:
	var due: Dictionary = controller.get_meta(&"bandit_attacked_due", {})
	due[band] = maxi(int(due.get(band, -1)), day)
	controller.set_meta(&"bandit_attacked_due", due)

## Saves every queued attack in one registry commit (heat +20 each, attacked_day). {ok, flushed: {band: day}} or a refusal
## (kept queued).
static func flush(controller: Variant) -> Dictionary:
	var due: Dictionary = controller.get_meta(&"bandit_attacked_due", {})
	if due.is_empty(): return Runtime.ok("", {"flushed": {}})
	var slot: Variant = controller.region_slot
	if slot == null: return Runtime.fail("UNSUPPORTED")
	var lab: Variant = controller.lab
	if lab != null and (not lab._region_point_pending.is_empty() or lab._region_point_consuming or lab._region_point_dispatching): return Runtime.fail("REGION_EFFECT_RUNNING")
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
	controller.remove_meta(&"bandit_attacked_due")
	return Runtime.ok("", {"flushed": due})
