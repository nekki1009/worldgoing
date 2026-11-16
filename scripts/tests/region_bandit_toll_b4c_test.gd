extends SceneTree
## 土匪 B4c (bandit spec §5.1, §12): the toll rules. Checks: the fee (people x 2 days); the offer needs 1.5 times the
## strength and no paid pass; an NPC pays unless bold or short of food; a paid toll joins the hoard and passes the
## party for 3 days; the registry with passes validates and a broken pass is refused.
## Output: REGION_BANDIT_TOLL_B4C_PASS on success; quit(1) on failure.
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_BANDIT_TOLL_B4C OK ", checks, ": ", message)
		return true
	printerr("REGION_BANDIT_TOLL_B4C_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _run() -> void:
	var registry := {"version": RegionFactionQuery.VERSION, "revision": 1, "next_faction_id": 3, "migration_complete": true,
		"entries": {"2": {"faction_id": 2, "name": "匪", "color": "7a6650ff", "kind": "bandit", "leader_ref": RegionPeerage.world_person_ref("w1", 9), "nation_ref": null,
			"status": "active", "merged_into": null, "founded_at": 0.0, "ended_at": null, "duty_ai": false,
			"bandit": {"origin": "scenario", "lair": {"site_id": "atlas:1:1", "cell": [5, 5]}, "raid_ai": true, "heat": 0, "converted_from": null}}},
		"coverage": {"complete": false, "sources": [], "counts": null}}
	if not _ok(Bandit.toll_fee(6) == 12 and Bandit.toll_fee(0) == 0, "the fee is people x 2 days"): return
	if not _ok(Bandit.toll_offer(registry, 2, "p1", 15.0, 10.0, 5) and not Bandit.toll_offer(registry, 2, "p1", 14.0, 10.0, 5) and not Bandit.toll_offer(registry, 1, "p1", 99.0, 10.0, 5), "the offer needs 1.5 times the strength and a band"): return
	if not _ok(Bandit.npc_pays_toll(40, 12, 12) and not Bandit.npc_pays_toll(70, 12, 12) and not Bandit.npc_pays_toll(40, 11, 12), "an NPC pays unless bold or short of food"): return
	var paid: Dictionary = Bandit.toll_paid(registry, 2, "p1", 5, {"grain": 12}, 1.0e9)
	if not _ok(paid.ok and RegionFactionQuery.validate(paid.registry, 1.0e9).ok, "a paid toll gives a valid registry", paid): return
	var table: Dictionary = RegionFactionQuery.bandit_of(paid.registry, 2)
	if not _ok(table.hoard == {"grain": 12} and table.passes == {"p1": 8} and not Bandit.toll_offer(paid.registry, 2, "p1", 99.0, 10.0, 8) and Bandit.toll_offer(paid.registry, 2, "p1", 99.0, 10.0, 9) and Bandit.toll_offer(paid.registry, 2, "p2", 99.0, 10.0, 6), "the food joins the hoard; that party passes for 3 days, others do not", table): return
	var later: Dictionary = Bandit.toll_paid(paid.registry, 2, "p2", 20, {"grain": 4}, 1.0e9)
	if not _ok(later.ok and RegionFactionQuery.bandit_of(later.registry, 2).passes == {"p2": 23} and int(RegionFactionQuery.bandit_of(later.registry, 2).hoard.grain) == 16, "expired passes are dropped"): return
	var broken: Dictionary = paid.registry.duplicate(true)
	broken.entries["2"].bandit.passes["p9"] = -4
	if not _ok(not RegionFactionQuery.validate(broken, 1.0e9).ok, "a broken pass is refused"): return
	print("REGION_BANDIT_TOLL_B4C_PASS checks=", checks)
	quit(0)
