extends RefCounted
## 全滅的土匪 (Nekki 2026-11-24 OQ2 "是"; reports/offscreen-battle-log-plan.md O3; bandit spec §6.6). A band whose last
## member at its lair died or was captured in a battle ends (extinct, lair cleared): until then it stayed active in the
## registry for ever, with its heat and its lair, and nobody led it. The commander of the largest official team in that
## battle gains Bandit.SUPPRESS_PRESTIGE, once per band (an ended band is never read again).
## Checked when a battle's effects are saved, and once a game minute of rest on the lair's own Site (`check`), so a band
## whose knocked out survivors die or are captured after the battle closed ends as well.
## A band with members anywhere else does not end: a travelling party, an open raid on another Site, or standing members
## on another bound Site. Members knocked out recover, so they count as members; captives and the dead do not.
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Attacked = preload("res://scripts/terrain_lab/site_bandit_attacked.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")

## True when `band` has a member on this Site who is neither dead nor a captive.
static func members_left(lab: Variant, band: int) -> bool:
	if lab == null or lab.crowd_site == null or not lab.crowd_site.active: return false
	for team: Dictionary in lab.crowd_site.teams:
		if bool(team.get("departed", false)) or int(team.get("faction", -1)) != band: continue
		for person: Variant in team.get("person_ids", []):
			if not lab.crowd_site._index_by_id.has(int(person)): continue
			var state: Dictionary = lab.crowd_site.soldier_state(int(lab.crowd_site._index_by_id[int(person)]))
			if float(state.get("captive", 0.0)) > 0.0: continue
			if float(state.get("hp", 0.0)) > 0.0 or float(state.get("ko", 0.0)) > 0.0: return true
	return false

## True when `band` has people away from `controller`'s Site: a party on the map, an open raid elsewhere, or standing
## members on another bound Site.
static func people_elsewhere(controller: Variant, band: int) -> bool:
	var slot: Variant = controller.region_slot
	var here := str(controller.lab.terrain.site.get("id", ""))
	for token: Variant in slot.region_registry().get("parties", {}):
		var party: Variant = slot.region_registry().parties[token]
		if party is Dictionary and str(party.get("phase", "")) != "arrived" and Bandit.party_faction(party) == band: return true
	var raid: Dictionary = slot.get_meta(&"bandit_raids_open", {}).get(band, {})
	if not raid.is_empty() and str(raid.get("site_id", "")) != here and Attacked.today_of(controller) - int(raid.get("day", -100)) <= Attacked.RAID_DAYS: return true
	var labs: Array = slot._region_original_labs.values()
	for other: Variant in labs:
		if not is_instance_valid(other) or other == controller.lab or other.terrain == null: continue
		if members_left(other, band): return true
	return false

## The official faction with the most standing people here and the captain of its largest team: {person} or {}.
static func official_captain(controller: Variant) -> Dictionary:
	var registry: Dictionary = controller.region_slot.control.get("faction_registry", {})
	var best := {}
	for team: Dictionary in controller.lab.crowd_site.teams:
		if bool(team.get("departed", false)) or not Attacked.official(registry, int(team.get("faction", -1))): continue
		var size: int = team.get("person_ids", []).size()
		if size <= int(best.get("size", 0)): continue
		best = {"size": size, "faction": int(team.faction), "person": int(controller.team_captain_of_team(int(team.team_id)))}
	return best

## Once a game minute of rest: the bands whose lair is this Site, where nobody of them is left and some were lost here in
## the last Attacked.RAID_DAYS days to an official attack. Returns the ended bands.
static func check(controller: Variant, saver: Variant) -> Array[int]:
	var slot: Variant = controller.region_slot
	if slot == null or saver == null or controller.lab == null or controller.lab.crowd_site == null or not controller.lab.crowd_site.active: return [] as Array[int]
	var now := float(slot.control.logical_game_seconds)
	if now - float(controller.get_meta(&"bandit_ended_at", -INF)) < Attacked.WATCH_SECONDS: return [] as Array[int]
	controller.set_meta(&"bandit_ended_at", now)
	var registry: Dictionary = slot.control.get("faction_registry", {})
	if registry.get("version") != RegionFactionQuery.VERSION: return [] as Array[int]
	var here := str(controller.lab.terrain.site.get("id", ""))
	var captain := official_captain(controller)
	var commanders := {int(captain.faction): {"person": int(captain.person)}} if not captain.is_empty() else {}
	var sides := {}
	for band: Variant in registry.entries:
		if not RegionFactionQuery.is_bandit(registry, int(band)) or registry.entries[band].get("status") != "active": continue
		var table := RegionFactionQuery.bandit_of(registry, int(band))
		if not table.get("lair") is Dictionary or str(table.lair.get("site_id", "")) != here: continue
		# Nobody of a band is dead or captive on a Site that was never attacked: an empty lair (its people are away) goes on.
		if Attacked.today_of(controller) - int(table.get("attacked_day", -100)) > Attacked.RAID_DAYS: continue
		sides[str(int(band))] = {"faction": int(band)}
	for faction: Variant in commanders: sides[str(int(faction))] = {"faction": int(faction)}
	return after_battle(controller, {"site_id": here, "sides": sides}, commanders, saver)

## Ends every band of `battle` ({site_id, sides}) that lost its last member at its own lair here. `commanders` = faction ->
## {person, ref}. `saver` = the active Site's controller, the only one that may save the registry. Returns the ended bands.
static func after_battle(controller: Variant, battle: Dictionary, commanders: Dictionary, saver: Variant) -> Array[int]:
	var ended: Array[int] = []
	var slot: Variant = controller.region_slot
	if slot == null or saver == null or controller.lab == null or controller.lab.terrain == null: return ended
	var here := str(controller.lab.terrain.site.get("id", ""))
	var sides: Array[int] = []
	for key: Variant in battle.get("sides", {}): sides.append(int(battle.sides[key].get("faction", -1)))
	sides.sort()
	for band: int in sides:
		var registry: Dictionary = slot.control.get("faction_registry", {})
		if registry.get("version") != RegionFactionQuery.VERSION or not RegionFactionQuery.is_bandit(registry, band): continue
		if registry.entries[str(band)].get("status") != "active": continue
		var lair: Variant = RegionFactionQuery.bandit_of(registry, band).get("lair")
		if lair is Dictionary and str(lair.get("site_id", "")) != here: continue
		if members_left(controller.lab, band) or people_elsewhere(controller, band): continue
		var next: Dictionary = Bandit.disperse(registry, band, float(slot.control.logical_game_seconds))
		if not next.ok or not saver._commit_diplomacy(next, "").ok: continue
		ended.append(band)
		var best := -1
		for faction: int in sides:
			if faction == band or not Attacked.official(registry, faction): continue
			var person := int(commanders.get(faction, {}).get("person", -1))
			if person > 0 and best < 0: best = person
		if best > 0: controller.adjust_reputation(best, float(Bandit.SUPPRESS_PRESTIGE), 0.0)
		if controller.lab.terrain.site.get("notices") is Array: controller.lab.terrain.site.notices.append("土匪「%s」全滅" % str(registry.entries[str(band)].get("name", "")))
	return ended
