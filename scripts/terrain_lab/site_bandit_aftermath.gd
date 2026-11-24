extends RefCounted
## 土匪 B4d-3b (bandit spec §5.1, §5.2): after a raid. When a battle closes on the live crowd Site and a band still has
## people standing while the settlement owner here has none, the band takes what it can carry from the Site's stock
## (CARRY per standing bandit, food first, then the rest by name) into its lair hoard; the settlement's owner does not
## change (bandits never occupy). Every day after, a band whose teams stand on a Site other than its lair sends one of its
## multi-person teams home toward the lair on its captain's word (captain:band) until none is left; never during a fight.
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")

const CARRY := 20
const FOOD_FIRST := ["grain", "fish", "meat", "wild_food"]

static func _bands(registry: Dictionary) -> Array[int]:
	var bands: Array[int] = []
	for key: Variant in registry.get("entries", {}):
		var entry: Dictionary = registry.entries[key]
		if entry.get("status") == "active" and RegionFactionQuery.is_bandit(registry, int(entry.faction_id)): bands.append(int(entry.faction_id))
	bands.sort()
	return bands

## What `band` takes from `inventory` with `standing` people: {item: n}. Pure.
static func plunder(inventory: Dictionary, standing: int) -> Dictionary:
	var room := maxi(0, standing) * CARRY
	var taken := {}
	var order: Array = FOOD_FIRST.duplicate()
	var rest: Array = inventory.keys().filter(func(item: Variant) -> bool: return not FOOD_FIRST.has(str(item)))
	rest.sort()
	order.append_array(rest)
	for item: Variant in order:
		if room <= 0: break
		var have := int(inventory.get(item, 0))
		if have <= 0: continue
		var n := mini(have, room)
		taken[str(item)] = n
		room -= n
	return taken

## Called when a battle closes on the live crowd Site with `standing` {faction: able people}. Returns
## {ok, band, taken} or {} when no band won a raid here.
## `saver` = the active Site's controller: a Site nobody watches may not save the registry itself (its stock and the hoard
## are saved in the one publication, which collects the bound cold Sites).
static func after_battle(controller: Variant, standing: Dictionary, saver: Variant = null) -> Dictionary:
	var verdict := judge(controller, standing)
	return apply(controller, verdict, saver) if not verdict.is_empty() else {}

## Which band won a raid here and what it takes: {band, taken} or {}. Reads the settlement; changes nothing.
static func judge(controller: Variant, standing: Dictionary) -> Dictionary:
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	if slot == null or lab.crowd_site == null or not lab.crowd_site.active: return {}
	var settlement: Dictionary = Settlement.record(lab.terrain)
	if settlement.is_empty() or not settlement.has("owner_faction"): return {}
	var owner := int(settlement.owner_faction)
	if int(standing.get(owner, 0)) > 0: return {}
	var registry: Dictionary = slot.control.get("faction_registry", {})
	if registry.get("version") != RegionFactionQuery.VERSION: return {}
	for band: int in _bands(registry):
		if band == owner or int(standing.get(band, 0)) <= 0: continue
		return {"band": band, "taken": plunder(lab.terrain.site.get("inventory", {}), int(standing[band]))}
	return {}

## Moves `verdict.taken` from the Site's stock into the band's hoard, saved in one commit. Returns {ok, band, taken}.
static func apply(controller: Variant, verdict: Dictionary, saver: Variant = null) -> Dictionary:
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	var band := int(verdict.band)
	var taken: Dictionary = verdict.taken
	if taken.is_empty(): return {"ok": true, "band": band, "taken": {}}
	var inventory: Dictionary = lab.terrain.site.get("inventory", {})
	for item: String in taken:
		if int(inventory.get(item, 0)) < int(taken[item]): return Runtime.fail("STALE_PLUNDER", "倉庫存貨已變")
	var registry: Dictionary = slot.control.faction_registry
	var stored := Bandit._with_table(registry, band, func(table: Dictionary) -> void:
		var hoard: Dictionary = table.get("hoard", {})
		for item: String in taken: hoard[item] = mini(100000000, int(hoard.get(item, 0)) + int(taken[item]))
		table["hoard"] = hoard, float(slot.control.logical_game_seconds))
	if not stored.ok: return stored
	for item: String in taken:
		inventory[item] = int(inventory[item]) - int(taken[item])
		if int(inventory[item]) <= 0: inventory.erase(item)
	var saved: Dictionary = (saver if saver != null else controller)._commit_diplomacy(stored, "")
	if not saved.ok:
		for item: String in taken: inventory[item] = int(inventory.get(item, 0)) + int(taken[item]) # nothing left the Site
		return saved
	if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("土匪劫走倉庫存貨")
	return {"ok": true, "band": band, "taken": taken}

## The band's multi-person teams standing on this Site when its lair is elsewhere (team ids, sorted).
static func away_teams(controller: Variant, band: int) -> Array:
	var lab: Variant = controller.lab
	var registry: Dictionary = controller.region_slot.control.faction_registry
	var lair: Variant = RegionFactionQuery.bandit_of(registry, band).get("lair")
	if not lair is Dictionary or str(lair.site_id) == str(lab.terrain.site.id): return []
	var result: Array = []
	for team: Dictionary in lab.crowd_site.teams:
		if bool(team.get("departed", false)) or bool(team.get("solo", false)) or int(team.get("faction", -1)) != band: continue
		if team.get("person_ids", []).size() >= 2: result.append(int(team.team_id))
	result.sort()
	return result

## Sends one away team of `band` home. Returns {ok, team, token} or a refusal (NO_TEAM, IN_BATTLE, NO_LAIR, ...).
static func go_home(controller: Variant, band: int) -> Dictionary:
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	if lab.crowd_site == null or not lab.crowd_site.active: return Runtime.fail("UNSUPPORTED", "群眾未啟用")
	if float(lab.terrain.site.get("combat_left", 0.0)) > 0.0: return Runtime.fail("IN_BATTLE", "戰鬥中不撤")
	var teams := away_teams(controller, band)
	if teams.is_empty(): return Runtime.fail("NO_TEAM", "沒有在外的隊伍")
	var lair: Dictionary = RegionFactionQuery.bandit_of(slot.control.faction_registry, band).lair
	var parts := str(lair.site_id).split(":")
	if parts.size() < 3 or not parts[parts.size() - 2].is_valid_int() or not parts[parts.size() - 1].is_valid_int(): return Runtime.fail("NO_LAIR", "山寨位置無效")
	var goal := Vector2i(int(parts[parts.size() - 2]), int(parts[parts.size() - 1]))
	var here: Dictionary = slot._coordinate(lab.terrain)
	if not here.ok: return here
	var refusals: Array = []
	for team_id: int in teams:
		var captain := int(controller.team_captain_of_team(team_id))
		var person: Dictionary = lab.crowd_site.combat_target(captain) if captain > 0 else {}
		if person.is_empty(): refusals.append([team_id, "NO_COMMANDER"]); continue
		var component: int = RegionTravelSite.start_component(slot, here.site, person.cell, lab.terrain)
		var token := "band_home_%s" % Crypto.new().generate_random_bytes(12).hex_encode()
		var prepared: Dictionary = slot.prepare_npc_region_dispatch(lab, "captain:band", team_id, goal, component, [], token)
		if not prepared.ok: refusals.append([team_id, str(prepared.get("code", ""))]); continue
		var committed: Dictionary = slot.commit_npc_region_dispatch(prepared)
		if not committed.ok: return committed
		return {"ok": true, "team": team_id, "token": token}
	return Runtime.fail("NO_DEPARTURE", "隊伍尚不能出發").merged({"refusals": refusals}, true)
