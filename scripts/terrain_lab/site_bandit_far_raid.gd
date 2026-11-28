extends RefCounted
## 土匪 B4d-3c (bandit spec §5.1, §11): raids on another Site. The chief knows the settlements within REACH_SITES and their
## rough strength (Nekki 2026-11-25 A, region_bandit_formula.gd); of others he knows only what he
## or someone who told him saw there (RegionSiteStrength receipts, object = that Site, value.settlement_owner). A known
## settlement of another faction within the band's reach is a raid target with the strength seen there of its owner's
## faction. Raiding it sends every multi-person team of the band from the lair Site toward it on its captain's word
## (RegionAI captain dispatch, reason "band"); the fight starts when they meet the defenders there. Heat +10 when at
## least one team leaves.
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Strength = preload("res://scripts/region_lab/region_site_strength.gd")
const RegionAI = preload("res://scripts/region_lab/region_gameplay_ai.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Formula = preload("res://scripts/region_lab/region_bandit_formula.gd")

## Settlements of other Sites the chief knows, as raid targets: [{kind "settlement", id, site_id, strength, faction, far}].
static func targets(controller: Variant, band: int, chief: int) -> Array:
	var result: Array = []
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	var scope := str(lab.terrain.site.id)
	var now := float(slot.control.logical_game_seconds)
	var near := {}
	for target: Dictionary in Formula.known_settlements(slot, band, scope):
		if str(target.site_id) == scope: continue # this Site's own settlement: BanditDay.raid_facts
		near[str(target.site_id)] = true
		result.append(target)
	var known := RegionAI.view(slot.region_registry(), chief, now, scope, RegionAI.person_ref(lab.terrain.site, chief))
	var objects: Array = known.keys()
	objects.sort()
	for object: String in objects:
		var receipt: Dictionary = known[object]
		if receipt.get("observation_kind") != Strength.KIND or object == scope or near.has(object): continue
		var owner := int(receipt.value.get("settlement_owner", -1))
		if owner < 0 or owner == band: continue
		var strength := float(int(receipt.value.get("factions", {}).get(str(owner), 0)))
		result.append({"kind": "settlement", "id": object, "site_id": object, "strength": strength, "faction": owner, "far": true})
	return result

## Sends the band's teams toward `target.site_id`. Returns {ok, sent: [{team, token}], heat_saved, refusals}.
static func raid(controller: Variant, band: int, target: Dictionary) -> Dictionary:
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	if lab.crowd_site == null or not lab.crowd_site.active: return {"ok": false, "code": "UNSUPPORTED"}
	var parts := str(target.get("site_id", "")).split(":")
	if parts.size() < 3 or not parts[parts.size() - 2].is_valid_int() or not parts[parts.size() - 1].is_valid_int(): return {"ok": false, "code": "NO_TARGET"}
	var goal := Vector2i(int(parts[parts.size() - 2]), int(parts[parts.size() - 1]))
	var here: Dictionary = slot._coordinate(lab.terrain)
	if not here.ok: return here
	var sent: Array = []
	var refusals: Array = []
	var team_ids: Array = []
	for team: Dictionary in lab.crowd_site.teams:
		if bool(team.get("departed", false)) or bool(team.get("solo", false)) or int(team.get("faction", -1)) != band: continue
		if team.get("person_ids", []).size() < 2: continue
		team_ids.append(int(team.team_id))
	team_ids.sort()
	for team_id: int in team_ids:
		var captain := int(controller.team_captain_of_team(team_id))
		var person: Dictionary = lab.crowd_site.combat_target(captain) if captain > 0 else {}
		if person.is_empty(): refusals.append([team_id, "NO_COMMANDER"]); continue
		var component: int = RegionTravelSite.start_component(slot, here.site, person.cell, lab.terrain)
		var token := "band_raid_%s" % Crypto.new().generate_random_bytes(12).hex_encode()
		var prepared: Dictionary = slot.prepare_npc_region_dispatch(lab, "captain:band", team_id, goal, component, [], token)
		if not prepared.ok: refusals.append([team_id, str(prepared.get("code", "")), str(prepared.get("message", ""))]); continue
		var committed: Dictionary = slot.commit_npc_region_dispatch(prepared)
		if not committed.ok: return committed
		sent.append({"team": team_id, "token": token})
		break # One team per dispatch: the departure saves the Site; the next team leaves on a later day.
	if sent.is_empty(): return {"ok": false, "code": "NO_DEPARTURE", "refusals": refusals}
	var registry: Dictionary = slot.control.faction_registry
	var hotter := Bandit.set_heat(registry, band, Bandit.heat_after(int(RegionFactionQuery.bandit_of(registry, band).get("heat", 0)), "raid"), float(slot.control.logical_game_seconds))
	var saved: Dictionary = controller.registry_saver()._commit_diplomacy(hotter, "") if hotter.ok else hotter
	if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("土匪出寨劫掠")
	return {"ok": true, "sent": sent, "heat_saved": bool(saved.get("ok", false)), "refusals": refusals}
