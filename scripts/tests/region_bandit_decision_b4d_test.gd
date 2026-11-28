extends SceneTree
## 土匪 B4d (bandit spec §4 B, §11, §12): the chief's daily decision and rout bands, rules only. Checks:
## - a raid needs reach (2 Sites), 1.2 times the strength, and no paid fee or pass; the nearest then weakest target wins;
## - the day's one action follows the spec's order: move lair, rise, accept amnesty, demand protection, raid, rest;
## - rout survivors form a band only after 7 days, with 3 or more, when homeless; the most prestigious leads; the
##   controlled person is never taken.
## Output: REGION_BANDIT_DECISION_B4D_PASS on success; quit(1) on failure.
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_BANDIT_DECISION_B4D OK ", checks, ": ", message)
		return true
	printerr("REGION_BANDIT_DECISION_B4D_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _run() -> void:
	var registry := {"version": RegionFactionQuery.VERSION, "revision": 1, "next_faction_id": 3, "migration_complete": true,
		"entries": {"2": {"faction_id": 2, "name": "匪", "color": "7a6650ff", "kind": "bandit", "leader_ref": RegionPeerage.world_person_ref("w1", 9), "nation_ref": null,
			"status": "active", "merged_into": null, "founded_at": 0.0, "ended_at": null, "duty_ai": false,
			"bandit": {"origin": "scenario", "lair": {"site_id": "atlas:10:10", "cell": [5, 5]}, "raid_ai": true, "heat": 0, "converted_from": null,
				"protection": {"atlas:11:10": {"asked": 1, "until": 31}}, "passes": {"p-paid": 9}}}},
		"coverage": {"complete": false, "sources": [], "counts": null}}
	if not _ok(RegionFactionQuery.validate(registry, 1.0e9).ok, "the registry validates", RegionFactionQuery.validate(registry, 1.0e9)): return
	var near := {"kind": "party", "id": "a", "token": "p1", "site_id": "atlas:10:11", "strength": 10.0}
	var far := {"kind": "party", "id": "b", "token": "p2", "site_id": "atlas:13:10", "strength": 1.0}
	var strong := {"kind": "party", "id": "c", "token": "p3", "site_id": "atlas:10:10", "strength": 11.0}
	var paid_village := {"kind": "settlement", "id": "d", "site_id": "atlas:11:10", "strength": 2.0}
	var paid_party := {"kind": "party", "id": "e", "token": "p-paid", "site_id": "atlas:10:10", "strength": 2.0}
	var weak_two := {"kind": "settlement", "id": "f", "site_id": "atlas:12:10", "strength": 3.0}
	var raids := [Bandit.may_raid(registry, 2, near, 12.0, 5), Bandit.may_raid(registry, 2, far, 12.0, 5), Bandit.may_raid(registry, 2, strong, 12.0, 5),
		Bandit.may_raid(registry, 2, paid_village, 12.0, 5), Bandit.may_raid(registry, 2, paid_village, 12.0, 32), Bandit.may_raid(registry, 2, paid_party, 12.0, 5), Bandit.may_raid(registry, 2, paid_party, 12.0, 10)]
	if not _ok(raids == [true, false, false, false, true, false, true], "reach, strength, fee and pass gate a raid", raids): return
	var picked := Bandit.pick_raid(registry, 2, [far, weak_two, near, strong, paid_village], 12.0, 5)
	if not _ok(picked.get("id") == "a", "the nearest qualifying target wins", picked): return
	# Nekki 2026-11-22 B: hot and attacked in the last ATTACK_MEMORY_DAYS days -> move; hot and not attacked -> lie low
	# (after rise and amnesty, before protection and raids).
	var quiet := {"day": 30, "heat": 80, "can_rise": false, "amnesty_score": -1.0, "protection_due": ["atlas:12:10"], "targets": [near], "strength": 12.0}
	var hot_quiet := [Bandit.daily_decision(registry, 2, quiet).action]
	quiet["attacked_day"] = 30 - Bandit.ATTACK_MEMORY_DAYS - 1
	hot_quiet.append(Bandit.daily_decision(registry, 2, quiet).action)
	quiet["attacked_day"] = 30 - Bandit.ATTACK_MEMORY_DAYS
	hot_quiet.append(Bandit.daily_decision(registry, 2, quiet).action)
	quiet.erase("attacked_day")
	quiet.amnesty_score = 70.0
	hot_quiet.append(Bandit.daily_decision(registry, 2, quiet).action)
	if not _ok(hot_quiet == ["lie_low", "lie_low", "move_lair", "accept_amnesty"], "a hot band moves only after a recent official attack, else lies low (amnesty still accepted)", hot_quiet): return
	var facts := {"day": 5, "heat": 80, "attacked_day": 5, "can_rise": true, "amnesty_score": 70.0, "protection_due": ["atlas:12:10", "atlas:11:11"], "targets": [near], "strength": 12.0}
	var order: Array = []
	order.append(Bandit.daily_decision(registry, 2, facts).action)
	facts.heat = 10
	order.append(Bandit.daily_decision(registry, 2, facts).action)
	facts.can_rise = false
	order.append(Bandit.daily_decision(registry, 2, facts).action)
	facts.amnesty_score = 40.0
	var demand := Bandit.daily_decision(registry, 2, facts)
	order.append(demand.action)
	facts.protection_due = []
	order.append(Bandit.daily_decision(registry, 2, facts).action)
	facts.targets = [far]
	order.append(Bandit.daily_decision(registry, 2, facts).action)
	if not _ok(order == ["move_lair", "rise", "accept_amnesty", "demand_protection", "raid", "rest"] and demand.site_id == "atlas:11:11", "one action a day in the spec's order", [order, demand]): return
	var men := [{"id": 5, "prestige": 3}, {"id": 4, "prestige": 9}, {"id": 6, "prestige": 9}, {"id": 1, "prestige": 50, "controlled": true}]
	var formed := Bandit.rout_band(men, 10, 17, true, false, false)
	if not _ok(formed.ok and formed.chief == 4 and formed.members == [4, 6, 5], "after 7 days three homeless survivors form a band under the most prestigious; never the controlled person", formed): return
	var reasons := [Bandit.rout_band(men, 10, 16, true, false, false).reason, Bandit.rout_band(men, 10, 17, false, false, false).reason, Bandit.rout_band(men, 10, 17, true, false, true).reason, Bandit.rout_band(men.slice(0, 2), 10, 17, false, true, false).reason]
	if not _ok(reasons == ["waiting", "has_home", "returned", "too_few"], "no band while waiting, with a home, after returning, or with too few", reasons): return
	print("REGION_BANDIT_DECISION_B4D_PASS checks=", checks)
	quit(0)
