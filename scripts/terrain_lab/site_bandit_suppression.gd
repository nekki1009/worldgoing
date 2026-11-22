extends RefCounted
## 官方剿匪 (Nekki 2026-11-22 B, heat-driven; bandit spec BQ8). Once a day, the official faction that owns this Site's
## settlement looks for a band to put down: an active band with heat >= HEAT_PURSUE whose lair is within REACH Sites of this
## Site. It sends its largest combat team here (two or more people, a captain, not the player's) when that team has at least
## FORCE times the band's people at its lair, and at most one expedition per faction every COOLDOWN_DAYS days (the day is
## kept in the band's table, `pursued` {faction: day}, saved before the team leaves). The team leaves on its captain's word
## (captain:suppress) toward the lair Site; the battle there is an official attack on the band (site_bandit_attacked.gd).
## Live crowd Sites only (as the band AI); the way home and off-screen battles at a cold lair are later stages.
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Attacked = preload("res://scripts/terrain_lab/site_bandit_attacked.gd")

const HEAT_PURSUE := 50
const REACH := 2
const FORCE := 1.5
const COOLDOWN_DAYS := 30

## The latest expedition day of `faction` against any band (-1 when none). Pure.
static func last_expedition(registry: Dictionary, faction: int) -> int:
	var last := -1
	for key: Variant in registry.get("entries", {}):
		var entry: Dictionary = registry.entries[key]
		if entry.get("kind") != "bandit" or not entry.get("bandit") is Dictionary: continue
		var pursued: Variant = entry.bandit.get("pursued", {})
		if pursued is Dictionary: last = maxi(last, int(pursued.get(str(faction), -1)))
	return last

## The expedition to send today, or {} with `reason`. `teams` = [{team_id, size}] of the faction's combat teams here;
## `bands` = [{band, heat, lair_site, members}]. Pure: the hottest band in reach (then the nearest, then the lowest id),
## the largest team (then the lowest id) when it is at least FORCE times the band's people.
static func choose(here_site: String, teams: Array, bands: Array, last_day: int, today: int) -> Dictionary:
	if last_day >= 0 and today - last_day < COOLDOWN_DAYS: return {"reason": "COOLDOWN"}
	var candidates: Array = []
	for row: Dictionary in bands:
		var distance := Bandit.site_distance(here_site, str(row.lair_site))
		if int(row.heat) >= HEAT_PURSUE and distance >= 0 and distance <= REACH and int(row.members) > 0:
			candidates.append({"band": int(row.band), "heat": int(row.heat), "distance": distance, "members": int(row.members), "lair_site": str(row.lair_site)})
	if candidates.is_empty(): return {"reason": "NO_BAND"}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.heat) != int(b.heat): return int(a.heat) > int(b.heat)
		if int(a.distance) != int(b.distance): return int(a.distance) < int(b.distance)
		return int(a.band) < int(b.band))
	var target: Dictionary = candidates[0]
	var best: Dictionary = {}
	for team: Dictionary in teams:
		if int(team.size) < 2: continue
		if best.is_empty() or int(team.size) > int(best.size) or int(team.size) == int(best.size) and int(team.team_id) < int(best.team_id): best = team
	if best.is_empty(): return {"reason": "NO_TEAM"}
	if float(best.size) < FORCE * float(target.members): return {"reason": "TOO_WEAK", "band": int(target.band), "team_id": int(best.team_id)}
	return {"band": int(target.band), "team_id": int(best.team_id), "lair_site": str(target.lair_site), "members": int(target.members), "size": int(best.size)}

## The band's people at its lair Site: the live crowd when the lair is here, else the lair Site's saved armies.
static func band_members(controller: Variant, band: int, lair_site: String) -> int:
	var lab: Variant = controller.lab
	var count := 0
	if lair_site == str(lab.terrain.site.get("id", "")):
		for team: Dictionary in lab.crowd_site.teams:
			if not bool(team.get("departed", false)) and int(team.get("faction", -1)) == band: count += team.get("person_ids", []).size()
		return count
	var coordinate: Vector2i = _coordinate(lair_site)
	if coordinate.x == -2147483648: return 0
	var slot: Variant = controller.region_slot
	var loaded: Dictionary = slot._load_checked(slot.site_path(coordinate), coordinate)
	if not loaded.get("ok", false): return 0
	for army: Variant in loaded.data.site.get("armies", []):
		if army is Dictionary and int(army.get("faction_id", -1)) == band: count += army.get("units", []).size()
	return count

static func _coordinate(site_id: String) -> Vector2i:
	var parts := site_id.split(":")
	if parts.size() < 3 or not parts[parts.size() - 2].is_valid_int() or not parts[parts.size() - 1].is_valid_int(): return Vector2i(-2147483648, 0)
	return Vector2i(int(parts[parts.size() - 2]), int(parts[parts.size() - 1]))

## The daily pass, once per controller per day (meta `suppress_day`). Returns {day, sent?, reason?} or {} when already run.
static func day(controller: Variant) -> Dictionary:
	if controller == null or controller.region_slot == null or controller.lab == null: return {}
	var today := Attacked.today_of(controller)
	if int(controller.get_meta(&"suppress_day", -1)) == today: return {}
	controller.set_meta(&"suppress_day", today)
	return run(controller, today)

static func run(controller: Variant, today: int) -> Dictionary:
	var result := {"day": today}
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	if lab.crowd_site == null or not lab.crowd_site.active: return _with_reason(result, "NOT_LIVE")
	var registry: Dictionary = slot.control.get("faction_registry", {})
	if registry.get("version") != RegionFactionQuery.VERSION: return _with_reason(result, "NO_REGISTRY")
	var settlement: Dictionary = Settlement.record(lab.terrain)
	var faction := int(settlement.get("owner_faction", -1))
	if settlement.is_empty() or not Attacked.official(registry, faction): return _with_reason(result, "NO_OFFICIAL_SETTLEMENT")
	var here := str(lab.terrain.site.get("id", ""))
	var player := int(lab.controlled_person_id())
	var teams: Array = []
	for team: Dictionary in lab.crowd_site.teams:
		if bool(team.get("departed", false)) or bool(team.get("solo", false)) or int(team.get("faction", -1)) != faction: continue
		var people: Array = team.get("person_ids", [])
		if people.has(player) or int(controller.team_captain_of_team(int(team.team_id))) <= 0: continue
		teams.append({"team_id": int(team.team_id), "size": people.size()})
	var bands: Array = []
	for key: Variant in registry.get("entries", {}):
		var entry: Dictionary = registry.entries[key]
		if entry.get("status") != "active" or not RegionFactionQuery.is_bandit(registry, int(entry.faction_id)): continue
		var table: Dictionary = RegionFactionQuery.bandit_of(registry, int(entry.faction_id))
		var lair: Variant = table.get("lair")
		if not lair is Dictionary or int(table.get("heat", 0)) < HEAT_PURSUE: continue
		var distance := Bandit.site_distance(here, str(lair.site_id))
		if distance < 0 or distance > REACH: continue
		bands.append({"band": int(entry.faction_id), "heat": int(table.get("heat", 0)), "lair_site": str(lair.site_id), "members": band_members(controller, int(entry.faction_id), str(lair.site_id))})
	var chosen := choose(here, teams, bands, last_expedition(registry, faction), today)
	if chosen.has("reason"): return _with_reason(result, str(chosen.reason))
	# The expedition day is saved first (the cooldown holds even if the departure is refused below).
	var marked: Dictionary = Bandit.pursued(registry, int(chosen.band), faction, today, float(slot.control.logical_game_seconds))
	if not marked.ok: return _with_reason(result, str(marked.get("code", "PURSUED_REFUSED")))
	var saved: Dictionary = controller._commit_diplomacy(marked, "")
	if not saved.ok: return _with_reason(result, str(saved.get("code", "PURSUED_REFUSED")))
	var captain := int(controller.team_captain_of_team(int(chosen.team_id)))
	var person: Dictionary = lab.crowd_site.combat_target(captain) if captain > 0 else {}
	if person.is_empty(): return _with_reason(result, "NO_COMMANDER")
	var at: Dictionary = slot._coordinate(lab.terrain)
	if not at.ok: return _with_reason(result, str(at.get("code", "")))
	var component: int = RegionTravelSite.start_component(slot, at.site, person.cell, lab.terrain)
	var token := "suppress_%s" % Crypto.new().generate_random_bytes(12).hex_encode()
	var prepared: Dictionary = slot.prepare_npc_region_dispatch(lab, "captain:suppress", int(chosen.team_id), _coordinate(str(chosen.lair_site)), component, [], token)
	if not prepared.ok: return _with_reason(result, str(prepared.get("code", "DISPATCH_REFUSED")))
	var committed: Dictionary = slot.commit_npc_region_dispatch(prepared)
	if not committed.ok: return _with_reason(result, str(committed.get("code", "DISPATCH_REFUSED")))
	if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("官兵出發剿匪")
	result["sent"] = {"band": int(chosen.band), "faction": faction, "team": int(chosen.team_id), "token": token, "lair_site": str(chosen.lair_site), "members": int(chosen.members), "size": int(chosen.size)}
	return result

static func _with_reason(result: Dictionary, reason: String) -> Dictionary:
	result["reason"] = reason
	return result
