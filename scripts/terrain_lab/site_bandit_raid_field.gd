extends RefCounted
## 土匪遠征的現場 (2026-11-24; bandit spec §5.1, reports/offscreen-battle-log-plan.md O2). A far raid (site_bandit_far_raid)
## sends a band's team to a settlement on another Site and nothing more: it arrived with no order, and the first daily pass
## of that Site's owner sent every band team standing off its lair home. It never fought anybody. Here, once a game minute
## of rest, on a Site where the band's raid is open (SiteBanditAttacked.note_raid, not done):
## - its teams that stand here are ordered to attack the nearest defender (the owner faction's people who can fight,
##   civilians included), again every ORDER_AGAIN seconds while nobody fights;
## - once half of the defenders who stood there at first are down, the band carries off the stock at once
##   (SiteBanditAftermath) and breaks off (spec §11 劫完就撤，不追擊); with more than half of its own down it breaks off
##   with nothing (10A.3: a commander withdraws). Half of either side is left to pick up its knocked out: by the rule of
##   2026-09-29 the knocked out bleed to death in four hours unless somebody of theirs rescues them, and a raid fought to
##   the last killed the whole village, or the whole band (measured 2026-11-25).
## A band whose raid is done walks back to where it came in and leaves for the lair as soon as the Site lets it (a knocked
## out man keeps the whole team; tried again every HOME_AGAIN seconds). A raid older than RAID_DAYS leaves with the daily
## pass.
const Attacked = preload("res://scripts/terrain_lab/site_bandit_attacked.gd")
const Aftermath = preload("res://scripts/terrain_lab/site_bandit_aftermath.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")

const ORDER_AGAIN := 600.0
const HOME_AGAIN := 900.0

static func _able(lab: Variant, person: int) -> bool:
	if not lab.crowd_site._index_by_id.has(person): return false
	var state: Dictionary = lab.crowd_site.soldier_state(int(lab.crowd_site._index_by_id[person]))
	return float(state.get("hp", 0.0)) > 0.0 and float(state.get("ko", 0.0)) <= 0.0 and float(state.get("captive", 0.0)) <= 0.0

## Orders and, with no defender left, the plunder of every open raid here. `saver` = the active Site's controller. Returns
## [{band, orders, plundered}].
static func watch(controller: Variant, saver: Variant) -> Array:
	var result: Array = []
	var slot: Variant = controller.region_slot
	if slot == null or controller.lab == null or controller.lab.crowd_site == null or not controller.lab.crowd_site.active: return result
	var now := float(slot.control.logical_game_seconds)
	if now - float(controller.get_meta(&"bandit_raid_at", -INF)) < Attacked.WATCH_SECONDS: return result
	controller.set_meta(&"bandit_raid_at", now)
	var registry: Dictionary = slot.control.get("faction_registry", {})
	if registry.get("version") != RegionFactionQuery.VERSION: return result
	var lab: Variant = controller.lab
	var settlement: Dictionary = Settlement.record(lab.terrain)
	if settlement.is_empty() or not settlement.has("owner_faction"): return result
	var owner := int(settlement.owner_faction)
	for band: Variant in slot.get_meta(&"bandit_raids_open", {}):
		if int(band) == owner: continue
		var raid: Dictionary = slot.get_meta(&"bandit_raids_open", {})[band]
		if str(raid.get("site_id", "")) != str(lab.terrain.site.get("id", "")): continue
		if not Attacked.raid_open(controller, int(band)):
			if not bool(raid.get("done", false)) or not RegionFactionQuery.is_bandit(registry, int(band)): continue
			_break_off(controller, int(band), raid, now, result)
			continue
		var row := {"band": int(band), "orders": [], "plundered": {}}
		var defenders: Array[Dictionary] = []
		var raiders: Array[Dictionary] = []
		for team: Dictionary in lab.crowd_site.teams:
			if bool(team.get("departed", false)): continue
			for person: Variant in team.get("person_ids", []):
				if not _able(lab, int(person)): continue
				var body: Dictionary = lab.crowd_site.combat_target(int(person))
				if body.is_empty(): continue
				if int(team.get("faction", -1)) == owner: defenders.append({"id": int(person), "cell": body.cell})
				elif int(team.get("faction", -1)) == int(band): raiders.append({"team": int(team.team_id), "id": int(person), "cell": body.cell})
		if not raid.has("raiders"):
			if raiders.is_empty(): continue # not here yet
			raid["raiders"] = raiders.size() # who came, whom they met, and where they came in (the way back)
			raid["defenders"] = defenders.size()
			raid["from"] = raiders[0].cell
		if defenders.size() * 2 <= int(raid.defenders) and not raiders.is_empty():
			var verdict: Dictionary = Aftermath.judge(controller, {int(band): raiders.size(), owner: 0})
			if not verdict.is_empty():
				var saved: Dictionary = Aftermath.apply(controller, verdict, saver)
				if saved.get("ok", false): row.plundered = saved.taken
				else: continue # tried again at the next look
			row["outcome"] = {"won": true, "raiders": raiders.size(), "of": int(raid.raiders), "defenders": defenders.size(), "against": int(raid.defenders)}
		elif raiders.size() * 2 < int(raid.raiders):
			row["outcome"] = {"won": false, "raiders": raiders.size(), "of": int(raid.raiders), "defenders": defenders.size(), "against": int(raid.defenders)}
		if row.has("outcome"):
			Attacked.raid_done(controller, int(band))
			slot.set_meta(&"bandit_raid_outcome", row)
			result.append(row)
			_break_off(controller, int(band), raid, now, result)
			continue
		if float(lab.terrain.site.get("combat_left", 0.0)) > 0.0: continue
		var ordered: Dictionary = controller.get_meta(&"bandit_raid_ordered", {})
		if now - float(ordered.get(int(band), -INF)) < ORDER_AGAIN: continue
		for team: Dictionary in lab.crowd_site.teams:
			if bool(team.get("departed", false)) or bool(team.get("solo", false)) or int(team.get("faction", -1)) != int(band) or team.get("person_ids", []).size() < 2: continue
			var captain := int(controller.team_captain_of_team(int(team.team_id)))
			var from: Dictionary = lab.crowd_site.combat_target(captain if captain > 0 else int(team.person_ids[0]))
			if from.is_empty(): continue
			var best: Dictionary = defenders[0]
			for defender: Dictionary in defenders:
				if Vector2(defender.cell - from.cell).length_squared() < Vector2(best.cell - from.cell).length_squared(): best = defender
			var done: Dictionary = lab.crowd_site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.ATTACK, best.cell, int(best.id), "bandit_raid")
			if done.ok: row.orders.append({"team": int(team.team_id), "target": int(best.id)})
		if not row.orders.is_empty():
			ordered[int(band)] = now
			controller.set_meta(&"bandit_raid_ordered", ordered)
			if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("%s 劫掠本地聚落" % str(RegionFactionQuery.display(registry, int(band)).name))
			result.append(row)
	return result

## The band's teams here walk back to where they came in (again every ORDER_AGAIN seconds), and out of the fight one of
## them is sent home every HOME_AGAIN seconds until none is left (a refused try costs a whole capture of the Site).
static func _break_off(controller: Variant, band: int, raid: Dictionary, now: float, result: Array) -> void:
	var lab: Variant = controller.lab
	var away: Array = Aftermath.away_teams(controller, band)
	if away.is_empty(): return
	if raid.has("from") and now - float(raid.get("back_at", -INF)) >= ORDER_AGAIN:
		raid["back_at"] = now
		var moved: Array = []
		for team_id: int in away:
			if lab.crowd_site.issue_order(team_id, TerrainArmy.CombatOrder.MOVE, raid.from, -1, "bandit_raid").ok: moved.append(team_id)
		result.append({"band": band, "orders": [], "plundered": {}, "back": moved})
	if float(lab.terrain.site.get("combat_left", 0.0)) > 0.0 or now - float(raid.get("home_at", -INF)) < HOME_AGAIN: return
	raid["home_at"] = now
	var home: Dictionary = Aftermath.go_home(controller, band)
	var row := {"band": band, "orders": [], "plundered": {}, "home": bool(home.get("ok", false)), "code": str(home.get("code", "")), "refusals": home.get("refusals", [])}
	result.append(row)
	controller.region_slot.set_meta(&"bandit_raid_home", row)
