extends SceneTree
## Bandit B4a (reports/bandit-faction-spec.md §5.2, §9, §11, §12; BA-07, BA-08 data side), pure data. Checks:
## - heat: raid +10, attacked +20, -5 per whole 10 quiet days, clamped 0..100;
## - a lair move at heat >= 70 drops heat to 30; a cooler move keeps it;
## - the rise gate (prestige 30, members 30, heat < 50, NPC ambition 60) names the missing condition;
## - rise: same id, kind rebel, the sub-table gone, the chief crowned king; from then on the pair may propose a truce;
## - fall: a lawless rebel becomes a band (origin fallen_rebel, converted_from rebel/now), its treaty ends, its open letter is
##   invalidated, its peerage records end; a faction with a nation, a lawful kind or no head is refused.
## Output: REGION_BANDIT_B4A_PASS on success; quit(1) on any failure.

const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_BANDIT_B4A OK ", checks, ": ", message)
		return true
	printerr("REGION_BANDIT_B4A_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _person(lineage: int) -> Dictionary:
	return {"type": "person", "namespace": "b4a_test", "lineage": lineage}

func _run() -> void:
	if not _check(Bandit.heat_after(0, "raid") == 10 and Bandit.heat_after(95, "attacked") == 100 and Bandit.heat_after(40, "quiet", 19) == 35 and Bandit.heat_after(3, "quiet", 30) == 0, "heat rules"): return
	var reg: Dictionary = {"version": 1, "revision": 0, "next_faction_id": 1, "migration_complete": true, "entries": {}, "coverage": {"complete": false, "sources": [], "counts": null}}
	var A := _person(1)
	var B := _person(2)
	var C := _person(3)
	var made: Dictionary = RegionFactionQuery.allocate(reg, 0, 0.0, {"name": "官", "kind": "npc", "leader_ref": A})
	reg = made.registry
	var lawful := int(made.faction_id)
	made = RegionFactionQuery.allocate(reg, int(reg.revision), 0.0, {"name": "匪", "kind": "bandit", "leader_ref": B, "bandit": {"heat": 75}})
	reg = made.registry
	var band := int(made.faction_id)
	var moved: Dictionary = Bandit.move_lair(reg, band, "s2", Vector2i(3, 4), 10.0)
	if not _check(moved.ok and RegionFactionQuery.bandit_of(moved.registry, band).heat == 30 and RegionFactionQuery.bandit_of(moved.registry, band).lair == {"site_id": "s2", "cell": [3, 4]}, "a hot band moves its lair and cools to 30", moved): return
	var cool: Dictionary = Bandit.move_lair(Bandit.set_heat(reg, band, 20, 10.0).registry, band, "s3", Vector2i(1, 1), 10.0)
	if not _check(cool.ok and RegionFactionQuery.bandit_of(cool.registry, band).heat == 20, "a cooler move keeps the heat"): return
	reg = cool.registry
	if not _check(Bandit.may_rise(reg, band, 29, 40).code == "RISE_PRESTIGE" and Bandit.may_rise(reg, band, 30, 29).code == "RISE_MEMBERS" and Bandit.may_rise(Bandit.set_heat(reg, band, 50, 10.0).registry, band, 30, 30).code == "RISE_HEAT" and Bandit.may_rise(reg, band, 30, 30, 59).code == "RISE_AMBITION", "the rise gate names the missing condition"): return
	if not _check(Bandit.may_rise(reg, band, 30, 30, 60).ok and Bandit.may_rise(reg, band, 30, 30).ok, "the gate opens at the thresholds"): return
	var risen: Dictionary = Bandit.rise(reg, band, 20.0)
	if not _check(risen.ok and risen.registry.entries[str(band)].kind == "rebel" and not risen.registry.entries[str(band)].has("bandit") and not RegionFactionQuery.is_bandit(risen.registry, band), "the band rises as a rebel faction", risen): return
	if not _check(RegionPeerage.record_of(risen.registry, B).get("rank") == "king", "its chief is crowned king"): return
	var truce: Dictionary = RegionDiplomacy.propose(risen.registry, lawful, band, "truce", 10, A, 0.0, 30.0)
	if not _check(truce.ok and RegionDiplomacy.hostile(risen.registry, lawful, band, 30.0), "the rebels stay hostile but may now be offered a truce", truce): return
	# A treaty and an open letter, then the fall.
	var signed: Dictionary = RegionDiplomacy.settle(truce.registry, 30.0)
	var replied: Dictionary = RegionDiplomacy.reply(signed.registry, int(truce.proposal_id), true, B, 0.0, 30.0)
	var settled: Dictionary = RegionDiplomacy.settle(replied.registry, 30.0)
	if not _check(settled.ok and not RegionDiplomacy.treaty_between(settled.registry, lawful, band, 31.0).is_empty(), "a truce is signed with the rebels", settled): return
	var open_letter: Dictionary = RegionDiplomacy.propose(settled.registry, lawful, band, "peace", 0, A, 4000.0, 31.0)
	if not _check(open_letter.ok, "a peace letter is on its way", open_letter): return
	var lair := {"site_id": "s9", "cell": [5, 5]}
	var fell: Dictionary = Bandit.fall(open_letter.registry, band, lair, 40.0)
	if not _check(fell.ok and RegionFactionQuery.is_bandit(fell.registry, band), "the rebels fall to banditry", fell): return
	var table: Dictionary = RegionFactionQuery.bandit_of(fell.registry, band)
	if not _check(table.origin == "fallen_rebel" and table.converted_from == {"kind": "rebel", "at": 40.0} and table.lair == lair, "the fallen band records where it came from", table): return
	var diplomacy: Dictionary = RegionDiplomacy.table(fell.registry)
	var treaty_ended := true
	for treaty: Dictionary in diplomacy.treaties.values(): treaty_ended = treaty_ended and treaty.status == "ended"
	if not _check(treaty_ended and diplomacy.proposals[str(int(open_letter.proposal_id))].status == "invalidated", "its truce ends and its open letter is invalidated"): return
	if not _check(RegionPeerage.record_of(fell.registry, B).is_empty() and RegionDiplomacy.hostile(fell.registry, lawful, band, 41.0), "its king's title ends; the band is hostile again"): return
	if not _check(Bandit.fall(fell.registry, band, null, 41.0).code == "NOT_REBEL" and Bandit.fall(fell.registry, lawful, null, 41.0).code == "NOT_REBEL", "only a rebel falls"): return
	print("REGION_BANDIT_B4A_PASS checks=", checks)
	quit(0)
