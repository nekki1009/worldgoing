extends RefCounted
## 土匪 B4d-1 (reports/bandit-faction-spec.md §5.2, §9.1, §11, §12): once a game day, every NPC band chief makes one move.
## This step wires the record-level moves: heat cools by 5 every 10th day, a band at heat >= 70 moves its lair to the
## nearest land Site next to it (heat back to 30), and an NPC chief standing in the active Site rises when the §9.1 gate
## and his ambition allow. B4d-3a: a chief here raids this Site's settlement of another faction (raid_facts / raid).
## Amnesty offers are not wired yet; protection money is asked from the
## settlement side (SiteBanditProtection). A band the controlled person chiefs never acts here (the player decides), and
## nothing is decided for a chief who is not in the active Site where the decision needs his person ("no made-up
## history", §11).
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Reputation = preload("res://scripts/terrain_lab/person_reputation.gd")
const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const BanditAmnesty = preload("res://scripts/terrain_lab/site_bandit_amnesty.gd")
const BanditRout = preload("res://scripts/terrain_lab/site_bandit_rout.gd") # B4d-2: routed survivors form a band.
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Aftermath = preload("res://scripts/terrain_lab/site_bandit_aftermath.gd") # B4d-3b: away teams go home.
const Famine = preload("res://scripts/terrain_lab/site_famine_refugees.gd")
const Desertion = preload("res://scripts/terrain_lab/site_desertion.gd")
const Drifters = preload("res://scripts/terrain_lab/site_bandit_drifters.gd")
const FarRaid = preload("res://scripts/terrain_lab/site_bandit_far_raid.gd") # B4d-3c: raids on another Site.

const COOL_EVERY_DAYS := 10
## The four neighbours of a lair Site, in the order a move tries them.
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

## Runs the day once per controller; returns {day, actions: [{band, action, ...}]} or {} when already run today.
static func day(controller: Variant) -> Dictionary:
	if controller == null or controller.region_slot == null: return {}
	var today := int(float(controller.region_slot.control.logical_game_seconds) / Bandit.DAY)
	if int(controller.get_meta(&"bandit_day", -1)) == today: return {}
	controller.set_meta(&"bandit_day", today)
	return run(controller, today)

static func run(controller: Variant, today: int) -> Dictionary:
	var result := {"day": today, "actions": []}
	var slot: Variant = controller.region_slot
	result["rout"] = BanditRout.day(controller, today)
	result["deserted"] = Desertion.day(controller) # source C: a standing leave intent is carried out (退隊).
	result["famine"] = Famine.day(controller, today) # source E: famine makes refugees.
	result["drifters"] = Drifters.day(controller, today) # B4e: unaffiliated people gather into a band.
	var registry: Dictionary = slot.control.get("faction_registry", {})
	if registry.get("version") != RegionFactionQuery.VERSION: return result
	var bands: Array[int] = []
	for key: Variant in registry.get("entries", {}):
		var entry: Dictionary = registry.entries[key]
		if entry.get("status") == "active" and RegionFactionQuery.is_bandit(registry, int(entry.faction_id)): bands.append(int(entry.faction_id))
	bands.sort()
	var player_ref: Dictionary = JoinFaction._world_ref(controller, int(controller.lab.controlled_person_id()))
	var now := float(slot.control.logical_game_seconds)
	for band: int in bands:
		registry = slot.control.faction_registry
		var entry: Dictionary = registry.entries[str(band)]
		if not player_ref.is_empty() and RegionPeerage.same_ref(entry.get("leader_ref"), player_ref): continue
		var table: Dictionary = RegionFactionQuery.bandit_of(registry, band)
		# raid_ai false is a player-made band (落草) whose chief decides himself. Once an NPC holds the chief's seat (the player
		# is not its leader: checked above) the band runs on its own, and the switch is saved so it stays on.
		if not bool(table.get("raid_ai", true)):
			var switched := Bandit._with_table(registry, band, func(row: Dictionary) -> void: row.raid_ai = true, now)
			if not switched.ok or not controller._commit_diplomacy(switched, "").ok: continue
			registry = slot.control.faction_registry
			table = RegionFactionQuery.bandit_of(registry, band)
			result.actions.append({"band": band, "action": "npc_takes_over", "ok": true, "code": ""})
		var heat := int(table.get("heat", 0))
		if heat > 0 and today > 0 and today % COOL_EVERY_DAYS == 0:
			var cooled := Bandit.set_heat(registry, band, Bandit.heat_after(heat, "quiet", COOL_EVERY_DAYS), now)
			if cooled.ok and controller._commit_diplomacy(cooled, "").ok:
				registry = slot.control.faction_registry
				heat = int(RegionFactionQuery.bandit_of(registry, band).heat)
		# B4d-3b: teams away from the lair (after a raid) go home first, one team a day.
		if controller.lab.crowd_site != null and controller.lab.crowd_site.active and not Aftermath.away_teams(controller, band).is_empty():
			var home: Dictionary = Aftermath.go_home(controller, band)
			result.actions.append({"band": band, "action": "go_home", "ok": bool(home.get("ok", false)), "code": str(home.get("code", "")), "team": int(home.get("team", -1)), "refusals": home.get("refusals", [])})
			continue
		var chief: int = controller.region_slot.person_id_of_ref(entry.get("leader_ref")) # a world or a Site lineage ref
		# Only the live crowd Site decides for a chief standing there (a cold original Lab settling points does not).
		var here: bool = chief > 0 and controller.lab.crowd_site != null and controller.lab.crowd_site.active and not controller.lab._original_person_target(chief).is_empty()
		var can_rise := false
		if here:
			var mind: Dictionary = DutyAI.personality(chief, null, controller.lab)
			var prestige := Reputation.shown(int(controller.reputation_of(chief).prestige))
			can_rise = Bandit.may_rise(registry, band, prestige, BanditAmnesty._members(controller.lab, band).size(), int(mind.get("ambition", 50))).ok
		var seen := raid_facts(controller, band) if here else {"targets": [], "strength": 0.0}
		if here: seen.targets.append_array(FarRaid.targets(controller, band, chief))
		var decision := Bandit.daily_decision(registry, band, {"day": today, "heat": heat, "can_rise": can_rise,
			"amnesty_score": -1.0, "protection_due": [], "targets": seen.targets, "strength": float(seen.strength)})
		var done := {}
		match str(decision.action):
			"move_lair": done = move_lair(controller, band)
			"rise":
				done = controller._commit_diplomacy(Bandit.rise(registry, band, now), "")
				if done.ok: controller.adjust_reputation(chief, float(Reputation.FOUND_KING), 0.0)
			"raid": done = FarRaid.raid(controller, band, decision.target) if bool(decision.target.get("far", false)) else raid(controller, band, decision.target)
			_: continue
		var row := {"band": band, "action": str(decision.action), "ok": bool(done.get("ok", false)), "code": str(done.get("code", ""))}
		if str(decision.action) == "raid": row.merge({"orders": done.get("orders", []), "sent": done.get("sent", []), "refusals": done.get("refusals", []), "target": str(decision.target.get("site_id", "")), "heat_saved": bool(done.get("heat_saved", false))})
		result.actions.append(row)
	return result

## The nearest land neighbour of the lair Site (east, north, west, south) keeps the same cell inside its Site; with no
## land neighbour the band stays. Heat drops to 30 (Bandit.move_lair).
static func move_lair(controller: Variant, band: int) -> Dictionary:
	var slot: Variant = controller.region_slot
	var registry: Dictionary = slot.control.faction_registry
	var lair: Variant = RegionFactionQuery.bandit_of(registry, band).get("lair")
	if not lair is Dictionary: return {"ok": false, "code": "NO_LAIR"}
	var parts := str(lair.site_id).split(":")
	if parts.size() < 3 or not parts[parts.size() - 2].is_valid_int() or not parts[parts.size() - 1].is_valid_int(): return {"ok": false, "code": "NO_LAIR"}
	var at := Vector2i(int(parts[parts.size() - 2]), int(parts[parts.size() - 1]))
	var atlas := str(lair.site_id).substr(0, str(lair.site_id).length() - parts[parts.size() - 2].length() - parts[parts.size() - 1].length() - 2)
	for step: Vector2i in NEIGHBOURS:
		var next := at + step
		var summary: Dictionary = slot.source.get_site_summary(next.x, next.y) if slot.source != null else {}
		if not summary.get("ok", false) or str(summary.get("status", "")) not in ["land", "mixed"]: continue
		var site_id := "%s:%d:%d" % [atlas, next.x, next.y]
		var moved := Bandit.move_lair(registry, band, site_id, Vector2i(int(lair.cell[0]), int(lair.cell[1])), float(slot.control.logical_game_seconds))
		if not moved.ok: return moved
		return controller._commit_diplomacy(moved, "")
	return {"ok": false, "code": "NO_LAND_NEIGHBOUR"}

# --- B4d-3a: a raid on the settlement of the band's own Site (bandit spec §5.1, §11, §12) ------------------------------
## What the chief sees here: the band's visible people against the settlement owner's (one target: this Site's
## settlement of another faction). Other Sites: B4d-3c (site_bandit_far_raid.gd).
static func raid_facts(controller: Variant, band: int) -> Dictionary:
	var lab: Variant = controller.lab
	var settlement: Dictionary = Settlement.record(lab.terrain)
	var visible: Dictionary = controller.visible_strength()
	var result := {"targets": [], "strength": float(visible.get(band, 0))}
	if settlement.is_empty() or not settlement.has("owner_faction"): return result
	var owner := int(settlement.owner_faction)
	if owner == band: return result
	var site_id := str(lab.terrain.site.get("id", ""))
	result.targets.append({"kind": "settlement", "id": site_id, "site_id": site_id, "strength": float(visible.get(owner, 0)), "faction": owner})
	return result

## Every team of the band attacks the defender nearest to its captain; heat rises by 10 (saved with the Site when the
## Site can be saved). Returns {ok, orders: [{team, target}], heat_saved}.
static func raid(controller: Variant, band: int, target: Dictionary) -> Dictionary:
	var lab: Variant = controller.lab
	if lab.crowd_site == null or not lab.crowd_site.active: return {"ok": false, "code": "UNSUPPORTED"}
	var defenders: Array[Dictionary] = []
	for team: Dictionary in lab.crowd_site.teams:
		if bool(team.get("departed", false)) or int(team.get("faction", -1)) != int(target.get("faction", -1)): continue
		for person: Variant in team.get("person_ids", []):
			var body: Dictionary = lab.crowd_site.combat_target(int(person))
			if not body.is_empty() and float(body.get("hp", 0.0)) > 0.0: defenders.append({"id": int(person), "cell": body.cell})
	if defenders.is_empty(): return {"ok": false, "code": "NO_TARGET"}
	var orders: Array = []
	for team: Dictionary in lab.crowd_site.teams:
		if bool(team.get("departed", false)) or bool(team.get("solo", false)) or int(team.get("faction", -1)) != band: continue
		var captain := int(controller.team_captain_of_team(int(team.team_id)))
		var from: Dictionary = lab.crowd_site.combat_target(captain if captain > 0 else int(team.person_ids[0]))
		if from.is_empty(): continue
		var best: Dictionary = defenders[0]
		for defender: Dictionary in defenders:
			if Vector2(defender.cell - from.cell).length_squared() < Vector2(best.cell - from.cell).length_squared(): best = defender
		var ordered: Dictionary = lab.crowd_site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.ATTACK, best.cell, int(best.id), "bandit_raid")
		if ordered.ok: orders.append({"team": int(team.team_id), "target": int(best.id)})
	if orders.is_empty(): return {"ok": false, "code": "NO_ORDER"}
	var slot: Variant = controller.region_slot
	var registry: Dictionary = slot.control.faction_registry
	var hotter := Bandit.set_heat(registry, band, Bandit.heat_after(int(RegionFactionQuery.bandit_of(registry, band).get("heat", 0)), "raid"), float(slot.control.logical_game_seconds))
	var saved: Dictionary = controller._commit_diplomacy(hotter, "") if hotter.ok else hotter
	if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("%s 劫掠本地聚落" % str(RegionFactionQuery.display(registry, band).name))
	return {"ok": true, "orders": orders, "heat_saved": bool(saved.get("ok", false))}
