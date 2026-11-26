extends RefCounted
## 官方剿匪 (Nekki 2026-11-22 B, heat-driven; bandit spec BQ8). Once a day, the official faction that owns this Site's
## settlement looks for a band to put down: an active band with heat >= HEAT_PURSUE whose lair is within REACH Sites of this
## Site. It sends its largest combat team here (two or more people, a captain, not the player's) when that team has at least
## FORCE times the band's people at its lair, and at most one expedition per faction every COOLDOWN_DAYS days (the day is
## kept in the band's table, `pursued` {faction: day}, saved before the team leaves). The team leaves on its captain's word
## (captain:suppress) toward the lair Site; the battle there is an official attack on the band (site_bandit_attacked.gd).
## Stage 2: the faction's teams standing away from the home of its latest expedition (pursued {day, home}, within
## COOLDOWN_DAYS) go home on the same word, one team a day, once no band person stands there (go_home, before the
## expedition choice). Stage 3: before that, a team here whose faction's latest expedition is against a band with living
## people on this Site gets an ATTACK order on the nearest of them (attack); the battle closes through
## SiteController.close_battle, which queues the official attack on the band. The daily pass runs on every bound crowd
## Site, live or cold (cold crowd Sites step natively off-screen), so an expedition fights at a lair nobody watches.
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
		var row: Variant = pursued.get(str(faction)) if pursued is Dictionary else null
		if row is Dictionary: last = maxi(last, int(row.get("day", -1)))
	return last

## The home Site of `faction`'s latest expedition in the last COOLDOWN_DAYS days ("" when none). Pure.
static func home_of(registry: Dictionary, faction: int, today: int) -> String:
	var best := -1
	var home := ""
	for key: Variant in registry.get("entries", {}):
		var entry: Dictionary = registry.entries[key]
		if entry.get("kind") != "bandit" or not entry.get("bandit") is Dictionary or not entry.bandit.get("pursued") is Dictionary: continue
		var row: Variant = entry.bandit.pursued.get(str(faction))
		if row is Dictionary and int(row.get("day", -1)) > best and today - int(row.get("day", -1)) <= COOLDOWN_DAYS:
			best = int(row.day)
			home = str(row.get("home", ""))
	return home

## The expedition to send today, or {} with `reason`. `teams` = [{team_id, size}] of the faction's combat teams here;
## `bands` = [{band, heat, lair_site, members}]. Pure: the hottest band in reach (then the nearest, then the lowest id),
## the largest team (then the lowest id) when it is at least FORCE times the band's people.
static func choose(here_site: String, teams: Array, bands: Array, last_day: int, today: int) -> Dictionary:
	if last_day >= 0 and today - last_day < COOLDOWN_DAYS: return {"reason": "COOLDOWN"}
	var candidates: Array = []
	for row: Dictionary in bands:
		var distance := Bandit.site_distance(here_site, str(row.lair_site))
		# A lair on this very Site is no expedition: its people stand here and any fight is local.
		if int(row.heat) >= HEAT_PURSUE and distance >= 1 and distance <= REACH and int(row.members) > 0:
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
	Attacked.watch(controller) # a fight on a Site nobody watches is read from the standing people (once a game minute)
	var today := Attacked.today_of(controller)
	var crowd: Variant = controller.lab.crowd_site
	var team_count: int = crowd.teams.size() if crowd != null and crowd.active else -1
	if int(controller.get_meta(&"suppress_day", -1)) == today:
		# An expedition that stopped its attack to go home leaves on a later look of the same day.
		if bool(controller.get_meta(&"suppress_home_wait", false)):
			var later: Dictionary = go_home(controller, today)
			if str(later.get("reason", "")) != "HOLDING": controller.set_meta(&"suppress_home_wait", false)
			if later.has("sent"): return {"day": today, "home": later.sent}
		# The day's pass has run. An expedition that entered since (a team was added to this Site) attacks at once: a
		# cold lair Site runs its day's pass at its bind, before the arriving expedition is put in. An order the Site
		# could not take yet is asked again on the next look.
		if team_count >= 0 and team_count != int(controller.get_meta(&"suppress_teams", -1)):
			var fight: Dictionary = attack(controller, today)
			if int(fight.get("wanted", 0)) <= fight.orders.size(): controller.set_meta(&"suppress_teams", team_count)
			if not fight.orders.is_empty(): return {"day": today, "attack": fight.orders}
		return {}
	controller.set_meta(&"suppress_day", today)
	var result := run(controller, today)
	controller.set_meta(&"suppress_home_wait", bool(result.get("home_wait", false)))
	# An attack the Site could not take yet (asked for but not ordered) is asked again on the next look.
	controller.set_meta(&"suppress_teams", -1 if bool(result.get("attack_refused", false)) else team_count)
	return result

static func run(controller: Variant, today: int) -> Dictionary:
	var result := {"day": today}
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	if lab.crowd_site == null or not lab.crowd_site.active: return _with_reason(result, "NOT_LIVE")
	var registry: Dictionary = slot.control.get("faction_registry", {})
	if registry.get("version") != RegionFactionQuery.VERSION: return _with_reason(result, "NO_REGISTRY")
	# Stage 3 first: an expedition standing with its band attacks it.
	var fight: Dictionary = attack(controller, today)
	if not fight.orders.is_empty():
		result["attack"] = fight.orders
		return result
	if int(fight.get("wanted", 0)) > 0: result["attack_refused"] = true
	# Stage 2: an expedition standing here (a lair Site has no settlement of its own) goes home.
	var homeward: Dictionary = go_home(controller, today)
	if homeward.has("sent"):
		result["home"] = homeward.sent
		return result
	if str(homeward.get("reason", "")) == "HOLDING":
		result["home_wait"] = true
		return result
	var settlement: Dictionary = Settlement.record(lab.terrain)
	var faction := int(settlement.get("owner_faction", -1))
	if settlement.is_empty() or not Attacked.official(registry, faction): return _with_reason(result, "NO_OFFICIAL_SETTLEMENT")
	# The player's own faction (kind player) sends troops on the player's word, never on the AI's.
	if str(registry.entries[str(faction)].get("kind", "")) == "player": return _with_reason(result, "PLAYER_FACTION")
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
		if distance < 1 or distance > REACH: continue # a lair here is a local fight, not an expedition
		bands.append({"band": int(entry.faction_id), "heat": int(table.get("heat", 0)), "lair_site": str(lair.site_id), "members": band_members(controller, int(entry.faction_id), str(lair.site_id))})
	var chosen := choose(here, teams, bands, last_expedition(registry, faction), today)
	if chosen.has("reason"): return _with_reason(result, str(chosen.reason))
	var sent := send(controller, faction, chosen, today)
	if not sent.ok: return _with_reason(result, str(sent.code))
	result["sent"] = sent.sent
	return result

## Sends `chosen` ({band, team_id, lair_site, members?, size?}, a team of `faction` standing here) toward the band's lair:
## the expedition day and its home (this Site) are saved first (the cooldown holds even if the departure is refused), then
## the team leaves on its captain's word (captain:suppress). {ok, sent: {band, faction, team, token, lair_site, home}} or
## {ok false, code}.
static func send(controller: Variant, faction: int, chosen: Dictionary, today: int) -> Dictionary:
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	var here := str(lab.terrain.site.get("id", ""))
	# The captain and his start are read before the save below (as a fence team's are): the save's checkpoint capture
	# rebuilds the crowd's rosters.
	var captain := int(controller.team_captain_of_team(int(chosen.team_id)))
	var person: Dictionary = lab.crowd_site.combat_target(captain) if captain > 0 else {}
	if person.is_empty(): return {"ok": false, "code": "NO_COMMANDER", "captain": captain}
	var at: Dictionary = slot._coordinate(lab.terrain)
	if not at.ok: return {"ok": false, "code": str(at.get("code", "NO_SITE"))}
	var component: int = RegionTravelSite.start_component(slot, at.site, person.cell, lab.terrain)
	var marked: Dictionary = Bandit.pursued(slot.control.faction_registry, int(chosen.band), faction, today, here, float(slot.control.logical_game_seconds))
	if not marked.ok: return {"ok": false, "code": str(marked.get("code", "PURSUED_REFUSED"))}
	var saved: Dictionary = controller.registry_saver()._commit_diplomacy(marked, "")
	if not saved.ok: return {"ok": false, "code": str(saved.get("code", "PURSUED_REFUSED"))}
	var token := "suppress_%s" % Crypto.new().generate_random_bytes(12).hex_encode()
	var prepared: Dictionary = slot.prepare_npc_region_dispatch(lab, "captain:suppress", int(chosen.team_id), _coordinate(str(chosen.lair_site)), component, [], token)
	if not prepared.ok: return {"ok": false, "code": str(prepared.get("code", "DISPATCH_REFUSED")), "message": str(prepared.get("message", ""))}
	var committed: Dictionary = slot.commit_npc_region_dispatch(prepared)
	if not committed.ok: return {"ok": false, "code": str(committed.get("code", "DISPATCH_REFUSED")), "message": str(committed.get("message", ""))}
	if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("官兵出發剿匪")
	return {"ok": true, "sent": {"band": int(chosen.band), "faction": faction, "team": int(chosen.team_id), "token": token, "lair_site": str(chosen.lair_site), "home": here,
		"members": int(chosen.get("members", 0)), "size": int(chosen.get("size", 0))}}

## The band (of `bands`, the bands with living people here) that `faction`'s latest expedition within COOLDOWN_DAYS is
## against, or -1. Pure.
static func pursued_band(registry: Dictionary, faction: int, bands: Array, today: int) -> int:
	var best := -1
	var best_day := -1
	for band: Variant in bands:
		var table: Dictionary = RegionFactionQuery.bandit_of(registry, int(band))
		var row: Variant = table.get("pursued", {}).get(str(faction)) if table.get("pursued") is Dictionary else null
		if not row is Dictionary: continue
		var day := int(row.get("day", -1))
		if day < 0 or today - day > COOLDOWN_DAYS: continue
		if day > best_day or day == best_day and int(band) < best:
			best = int(band)
			best_day = day
	return best

## Stage 3: every team here of an official non-player faction whose latest expedition is against a band with living
## people on this Site gets an ATTACK order on the nearest of them. {orders: [{team, faction, band, target}]}.
static func attack(controller: Variant, today: int) -> Dictionary:
	var lab: Variant = controller.lab
	var registry: Dictionary = controller.region_slot.control.get("faction_registry", {})
	if registry.get("version") != RegionFactionQuery.VERSION or lab.crowd_site == null or not lab.crowd_site.active: return {"orders": [], "wanted": 0}
	var player := int(lab.controlled_person_id())
	var band_people := {}
	for team: Dictionary in lab.crowd_site.teams:
		if bool(team.get("departed", false)): continue
		var band := int(team.get("faction", -1))
		if not RegionFactionQuery.is_bandit(registry, band): continue
		for person: Variant in team.get("person_ids", []):
			var body: Dictionary = lab.crowd_site.combat_target(int(person))
			if body.is_empty() or float(body.get("hp", 0.0)) <= 0.0: continue
			var rows: Array = band_people.get(band, [])
			rows.append({"id": int(person), "cell": body.cell})
			band_people[band] = rows
	var orders: Array = []
	var wanted := 0
	if band_people.is_empty(): return {"orders": orders, "wanted": 0}
	var bands: Array = band_people.keys()
	bands.sort()
	for team: Dictionary in lab.crowd_site.teams:
		if bool(team.get("departed", false)) or bool(team.get("solo", false)): continue
		var faction := int(team.get("faction", -1))
		if not Attacked.official(registry, faction) or str(registry.entries[str(faction)].get("kind", "")) == "player" or team.get("person_ids", []).has(player): continue
		var band := pursued_band(registry, faction, bands, today)
		if band < 0: continue
		wanted += 1
		var captain := int(controller.team_captain_of_team(int(team.team_id)))
		var from: Dictionary = lab.crowd_site.combat_target(captain if captain > 0 else int(team.person_ids[0]))
		if from.is_empty(): continue
		var best: Dictionary = band_people[band][0]
		for foe: Dictionary in band_people[band]:
			if Vector2(foe.cell - from.cell).length_squared() < Vector2(best.cell - from.cell).length_squared(): best = foe
		var ordered: Dictionary = lab.crowd_site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.ATTACK, best.cell, int(best.id), "suppress")
		if ordered.ok: orders.append({"team": int(team.team_id), "faction": faction, "band": band, "target": int(best.id)})
		else: controller.set_meta(&"suppress_refused", str(ordered.get("code", ""))) # why the last order was not taken (read by tests)
	if not orders.is_empty() and lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("官兵進剿山寨")
	return {"orders": orders, "wanted": wanted}

## Stage 2: one of the expedition teams standing here goes home ({sent: {faction, team, home, token}} or {reason, detail?}).
## Not while any living band person stands here; only teams of official non-player factions whose latest expedition's
## home is another Site. A team still under its attack order is first told to hold (reason HOLDING): Travel takes only a
## team standing at its post (found 2026-11-26: the order outlived the band, and the team never left).
static func go_home(controller: Variant, today: int) -> Dictionary:
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	var registry: Dictionary = slot.control.get("faction_registry", {})
	var here := str(lab.terrain.site.get("id", ""))
	var player := int(lab.controlled_person_id())
	var by_faction := {}
	for team: Dictionary in lab.crowd_site.teams:
		if bool(team.get("departed", false)): continue
		var faction := int(team.get("faction", -1))
		var living := 0
		for person: Variant in team.get("person_ids", []):
			var target: Dictionary = lab._original_person_target(int(person))
			if not target.is_empty() and float(target.get("hp", 0.0)) > 0.0: living += 1
		if RegionFactionQuery.is_bandit(registry, faction) and living > 0: return {"reason": "BAND_HERE", "team": int(team.team_id), "living": living}
		if bool(team.get("solo", false)) or living < 2 or team.get("person_ids", []).has(player) or not Attacked.official(registry, faction): continue
		if str(registry.entries[str(faction)].get("kind", "")) == "player" or int(controller.team_captain_of_team(int(team.team_id))) <= 0: continue
		var rows: Array = by_faction.get(faction, [])
		rows.append({"team_id": int(team.team_id), "size": living, "formation": int(team.get("formation", -1))})
		by_faction[faction] = rows
	var factions: Array = by_faction.keys()
	factions.sort()
	for faction: int in factions:
		var home := home_of(registry, faction, today)
		if home.is_empty() or home == here: continue
		var rows: Array = by_faction[faction]
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.size) > int(b.size) or int(a.size) == int(b.size) and int(a.team_id) < int(b.team_id))
		var team_id := int(rows[0].team_id)
		var captain := int(controller.team_captain_of_team(team_id))
		var person: Dictionary = lab.crowd_site.combat_target(captain) if captain > 0 else {}
		if person.is_empty(): continue
		if int(lab.crowd_site.formation_state(int(rows[0].formation)).get("order", 0)) != 0:
			var held: Dictionary = lab.crowd_site.issue_order(team_id, TerrainArmy.CombatOrder.HOLD, Vector2i(-1, -1), -1, "suppress")
			if held.get("ok", false): return {"reason": "HOLDING", "team": team_id}
			return {"reason": "HOLD_REFUSED", "detail": {"code": str(held.get("code", "")), "message": str(held.get("message", ""))}}
		var at: Dictionary = slot._coordinate(lab.terrain)
		if not at.ok: return {"reason": str(at.get("code", ""))}
		var component: int = RegionTravelSite.start_component(slot, at.site, person.cell, lab.terrain)
		var token := "suppress_home_%s" % Crypto.new().generate_random_bytes(12).hex_encode()
		var prepared: Dictionary = slot.prepare_npc_region_dispatch(lab, "captain:suppress", team_id, _coordinate(home), component, [], token)
		if not prepared.ok: return {"reason": str(prepared.get("code", "DISPATCH_REFUSED")), "detail": prepared.get("preflight", str(prepared.get("message", "")))}
		var committed: Dictionary = slot.commit_npc_region_dispatch(prepared)
		if not committed.ok: return {"reason": str(committed.get("code", "DISPATCH_REFUSED"))}
		if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("官兵剿匪收兵回營")
		return {"sent": {"faction": faction, "team": team_id, "home": home, "token": token}}
	return {"reason": "NONE"}

static func _with_reason(result: Dictionary, reason: String) -> Dictionary:
	result["reason"] = reason
	return result
