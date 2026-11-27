extends RefCounted
## 土匪 B4d-3b (bandit spec §5.1, §5.2): after a raid. When a battle closes on the live crowd Site and a band still has
## people standing while the settlement owner here has none, the band takes what it can carry from the Site's stock
## (CARRY per standing bandit, food first, then the rest by name) into its lair hoard; the settlement's owner does not
## change (bandits never occupy). Every day after, a band whose teams stand on a Site other than its lair sends one of its
## multi-person teams home toward the lair on its captain's word (captain:band) until none is left; never during a fight.
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Attacked = preload("res://scripts/terrain_lab/site_bandit_attacked.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")

const CARRY := 20
const FOOD_FIRST := ["grain", "fish", "meat", "wild_food"]
## Nekki 2026-11-27 「土匪搬種子依建議」: a band leaves the seed and the farm tools, so a raided village can still farm
## (the shipped demo A lost its whole farming camp to the first raid).
const LEFT_BEHIND := ["seeds", "tools"]

## Whether `inventory` holds anything a band would carry off (LEFT_BEHIND is not). Pure.
static func worth_taking(inventory: Dictionary) -> bool:
	for item: Variant in inventory:
		if not LEFT_BEHIND.has(str(item)) and int(inventory[item]) > 0: return true
	return false

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
	var rest: Array = inventory.keys().filter(func(item: Variant) -> bool: return not FOOD_FIRST.has(str(item)) and not LEFT_BEHIND.has(str(item)))
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

## The warehouses of the settlement `owner` on this Site (their keys, ordered): spec §5.1, a band that wins takes the
## warehouse stock. Every complete warehouse of that faction, private family estates included: a band takes no notice of
## whose goods they are. Their item records (gear) stay; only bulk resources are carried off, as from the camp stock.
static func warehouses(site: Dictionary, owner: int) -> Array[String]:
	var keys: Array[String] = []
	for key: Variant in site.get("stockpiles", {}):
		var feature: Variant = site.get("features", {}).get(key, {})
		if not feature is Dictionary or str(feature.get("kind", "")) != "warehouse": continue
		if str(feature.get("stage", "")) != "complete" or int(feature.get("owner_faction", -1)) != owner: continue
		keys.append(str(key))
	keys.sort()
	return keys

## Every resource the settlement has here, camp stock and warehouses together.
static func stock_of(site: Dictionary, owner: int) -> Dictionary:
	var total := {}
	for item: Variant in site.get("inventory", {}): total[str(item)] = int(total.get(str(item), 0)) + int(site.inventory[item])
	for key: String in warehouses(site, owner):
		for item: Variant in site.stockpiles[key].cargo: total[str(item)] = int(total.get(str(item), 0)) + int(site.stockpiles[key].cargo[item])
	return total

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
		return {"band": band, "owner": owner, "taken": plunder(stock_of(lab.terrain.site, owner), int(standing[band]))}
	return {}

## Moves `verdict.taken` from the Site's stock into the band's hoard, saved in one commit. Returns {ok, band, taken}.
static func apply(controller: Variant, verdict: Dictionary, saver: Variant = null) -> Dictionary:
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	var band := int(verdict.band)
	var taken: Dictionary = verdict.taken
	if taken.is_empty(): return {"ok": true, "band": band, "taken": {}}
	var site: Dictionary = lab.terrain.site
	var owner := int(verdict.get("owner", -1))
	var available := stock_of(site, owner)
	for item: String in taken:
		if int(available.get(item, 0)) < int(taken[item]): return Runtime.fail("STALE_PLUNDER", "倉庫存貨已變")
	var registry: Dictionary = slot.control.faction_registry
	var stored := Bandit._with_table(registry, band, func(table: Dictionary) -> void:
		var hoard: Dictionary = table.get("hoard", {})
		for item: String in taken: hoard[item] = mini(100000000, int(hoard.get(item, 0)) + int(taken[item]))
		table["hoard"] = hoard
		Bandit.note_raided(table, str(site.get("id", "")), Attacked.today_of(controller), {}, ""), float(slot.control.logical_game_seconds))
	if not stored.ok: return stored
	# The camp stock first, then the warehouses in order. Kept to undo when the save is refused: nothing then left the Site.
	var keys := warehouses(site, owner)
	var before := {"inventory": site.get("inventory", {}).duplicate(), "cargo": {}, "version": {}}
	for key: String in keys:
		before.cargo[key] = site.stockpiles[key].cargo.duplicate()
		before.version[key] = int(site.stockpiles[key].holder.version)
	if not site.get("inventory") is Dictionary: site["inventory"] = {}
	for item: String in taken:
		var left := int(taken[item])
		for source: String in ["inventory"] + keys:
			if left <= 0: break
			var holder: Dictionary = site.inventory if source == "inventory" else site.stockpiles[source].cargo
			var n := mini(left, int(holder.get(item, 0)))
			if n <= 0: continue
			holder[item] = int(holder[item]) - n
			if int(holder[item]) <= 0: holder.erase(item)
			left -= n
			if source != "inventory": site.stockpiles[source].holder.version = int(site.stockpiles[source].holder.version) + 1
	lab.terrain.environment_revision += 1
	var saved: Dictionary = (saver if saver != null else controller)._commit_diplomacy(stored, "")
	if not saved.ok:
		site["inventory"] = before.inventory
		for key: String in keys:
			site.stockpiles[key]["cargo"] = before.cargo[key]
			site.stockpiles[key].holder["version"] = before.version[key]
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
	if Attacked.raid_open(controller, band): return Runtime.fail("RAID_OPEN", "遠征還沒打")
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
		if not prepared.ok: refusals.append([team_id, str(prepared.get("code", "")), str(prepared.get("message", "")), prepared.get("preflight", {})]); continue
		var committed: Dictionary = slot.commit_npc_region_dispatch(prepared)
		if not committed.ok: return committed
		return {"ok": true, "team": team_id, "token": token}
	return Runtime.fail("NO_DEPARTURE", "隊伍尚不能出發").merged({"refusals": refusals}, true)
