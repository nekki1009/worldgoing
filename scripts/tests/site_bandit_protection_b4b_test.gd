extends "res://scripts/tests/site_building_ui_test.gd"
## 土匪 B4b (bandit spec §5.1, §12): protection money. A level 2 NPC settlement of faction 1 with two registered
## residents; a band (faction 2) whose lair is one Site away. Checks:
## - the registry's new hoard / protection keys validate, and a broken one is refused;
## - reach: a lair 3 Sites away, a band without raid_ai, or the settlement's own faction is never asked;
## - an NPC head with 3 fees of grain pays: grain leaves the camp, joins the hoard, protection lasts 30 days and no
##   new demand comes before it ends; with too little grain he refuses and is not asked again for 30 days;
## - a settlement headed by the controlled person gets a pending demand and answers it.
## Output: SITE_BANDIT_PROTECTION_B4B_PASS on success; quit(1) on failure.
const Protection = preload("res://scripts/terrain_lab/site_bandit_protection.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")

var checks := 0
var ctx := {}

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_BANDIT_PROTECTION_B4B OK ", checks, ": ", message)
		return true
	push_error("SITE_BANDIT_PROTECTION_B4B_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _commit(candidate: Dictionary) -> Dictionary:
	var checked := RegionFactionQuery.validate(candidate, 1.0e12)
	if not checked.ok: return checked
	ctx.registry = candidate
	return SiteRuntime.ok()

func _entry(id: int, kind: String, lair_site: String) -> Dictionary:
	var entry := {"faction_id": id, "name": "f%d" % id, "color": "336699ff", "kind": kind, "leader_ref": RegionPeerage.world_person_ref("w1", 900 + id), "nation_ref": null,
		"status": "active", "merged_into": null, "founded_at": 0.0, "ended_at": null, "duty_ai": false}
	if kind == "bandit": entry["bandit"] = {"origin": "scenario", "lair": {"site_id": lair_site, "cell": [5, 5]}, "raid_ai": true, "heat": 0, "converted_from": null}
	return entry

func _run() -> void:
	var data := _building_fixture()
	var center := _formal_feature(data, "warehouse", Vector2i(14, 14))
	var house := _formal_feature(data, "house", Vector2i(16, 26), Vector2i.ONE, {"variant": "small"})
	var lab := _building_lab(data)
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	team.faction_id = 1
	if not _ok(team.deploy_at(data, null, null, [Vector2i(30, 26), Vector2i(31, 26), Vector2i(32, 26)]) and team.enable_combat(false), "a three-person team deploys"): return
	team.set_process(false)
	team.settle_combat_command()
	var head := team.combat_identity(0)
	data.site.id = "atlas:100:100"
	var site_id := "atlas:100:100"
	data.site["settlement"] = {"settlement_id": "s1", "owner_faction": 1, "level": 2, "center_id": center, "offices": SiteOffices.default_offices("settlement", head, false)}
	data.site["housing"] = {str(team.combat_identity(1)): {"version": 1, "house_id": house, "cell": 0}, str(team.combat_identity(2)): {"version": 1, "house_id": house, "cell": 1}}
	ctx = {"registry": {"version": RegionFactionQuery.VERSION, "revision": 1, "next_faction_id": 5, "migration_complete": true,
		"entries": {"1": _entry(1, "npc", ""), "2": _entry(2, "bandit", "atlas:101:100"), "3": _entry(3, "bandit", "atlas:103:100"), "4": _entry(4, "bandit", "atlas:100:101")},
		"coverage": {"complete": false, "sources": [], "counts": null}}, "world": "w1", "commit": _commit}
	ctx.registry.entries["4"].bandit.raid_ai = false
	if not _ok(RegionFactionQuery.validate(ctx.registry, 1.0e12).ok, "the registry validates", RegionFactionQuery.validate(ctx.registry, 1.0e12)): return
	var broken: Dictionary = ctx.registry.duplicate(true)
	broken.entries["2"].bandit["protection"] = {site_id: {"asked": 1}}
	if not _ok(not RegionFactionQuery.validate(broken, 1.0e12).ok, "a broken protection row is refused"): return
	var day := Calendar.day_of(1, 3, 10)
	data.site.minute = Calendar.day_start_minute(day) + 600
	if not _ok(Bandit.protection_due(ctx.registry, site_id, day) == [2] and Protection.population(data) == 2, "only the raiding band within two Sites asks; two residents", Bandit.protection_due(ctx.registry, site_id, day)): return
	# The NPC head pays.
	data.site.inventory["grain"] = 6
	var first := Protection.demand(lab, day, ctx)
	var table: Dictionary = RegionFactionQuery.bandit_of(ctx.registry, 2)
	if not _ok(first.paid == [2] and int(data.site.inventory.grain) == 4 and table.hoard == {"grain": 2} and Bandit.protected(ctx.registry, 2, site_id, day + 30) and not Bandit.protected(ctx.registry, 2, site_id, day + 31), "the head pays 2 grain: hoard +2, protected 30 days", [first, table]): return
	if not _ok(Bandit.protection_due(ctx.registry, site_id, day + 29).is_empty() and Bandit.protection_due(ctx.registry, site_id, day + 31) == [2], "no new demand while protected; due again afterwards"): return
	# Too little grain: refuses.
	data.site.inventory["grain"] = 5
	var second := Protection.demand(lab, day + 31, ctx)
	if not _ok(second.refused == [2] and int(data.site.inventory.grain) == 5 and not Bandit.protected(ctx.registry, 2, site_id, day + 32) and Bandit.protection_due(ctx.registry, site_id, day + 40).is_empty(), "with under three fees he refuses; not asked again for 30 days", second): return
	# The player's settlement.
	data.site.settlement.offices = SiteOffices.default_offices("settlement", int(lab.controlled_person_id()), false)
	lab.character.faction_id = 1
	var third := Protection.demand(lab, day + 62, ctx)
	if not _ok(third.asked == [2] and int(Protection.pending.get(site_id, {}).get(2, 0)) == 2, "the player's settlement gets a pending demand", [third, Protection.pending]): return
	var answered := Protection.answer(lab, 2, true, day + 62, ctx)
	if not _ok(answered.ok and int(data.site.inventory.grain) == 3 and int(RegionFactionQuery.bandit_of(ctx.registry, 2).hoard.grain) == 4 and not Protection.pending[site_id].has(2), "the player pays: grain 5 to 3, hoard 4", answered): return
	data.site.erase("housing")
	Protection.pending.clear()
	print("SITE_BANDIT_PROTECTION_B4B_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
