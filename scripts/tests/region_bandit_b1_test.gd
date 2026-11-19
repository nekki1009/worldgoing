extends SceneTree
## Bandit faction B1 (reports/bandit-faction-spec.md §3, §15 BA-01/02/03/10), pure data over the faction registry. Checks:
## - kind bandit validates; its sub-table fills defaults; unknown sub-keys, a non-bandit `bandit` key, a bandit nation,
##   duty AI on, a chief-less active band, bad heat/lair/conversion are CORRUPT_SAVE;
## - allocate gives a bandit no title (no king record) and fixes duty_ai false;
## - a bandit is hostile to every faction, the neutral side and another band, never at peace, has no breach window;
##   propose / declare_war / reply with a bandit answer BANDIT_NO_DIPLOMACY and write nothing;
## - crown_founder, swear to a bandit acceptor and rebel into a band are refused; a peerage record inside a band is corrupt;
## - an active treaty or open letter that names a band is corrupt;
## - JSON round trip keeps the band (canonical ints), an old registry without bands is unchanged by canonicalising.
## Output: REGION_BANDIT_B1_PASS on success; quit(1) on any failure.

var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_BANDIT_B1 OK ", checks, ": ", message)
		return true
	printerr("REGION_BANDIT_B1_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _person(lineage: int) -> Dictionary:
	return {"type": "person", "namespace": "bandit_test", "lineage": lineage}

func _code(result: Dictionary) -> String:
	return str(result.get("code", "OK" if result.get("ok", false) else ""))

func _corrupt(reg: Dictionary, mutate: Callable, message: String) -> bool:
	var copy: Dictionary = reg.duplicate(true)
	mutate.call(copy)
	var checked: Dictionary = RegionFactionQuery.validate(copy, 1000.0)
	return _check(not checked.ok and checked.code == "CORRUPT_SAVE", message, checked)

func _run() -> void:
	var reg: Dictionary = {"version": 1, "revision": 0, "next_faction_id": 1, "migration_complete": true, "entries": {}, "coverage": {"complete": false, "sources": [], "counts": null}}
	var old_reg: Dictionary = reg.duplicate(true)
	if not _check(RegionFactionQuery.canonical_registry(old_reg) == old_reg, "a registry without bands is unchanged by canonicalising"): return
	var A := _person(1)
	var B := _person(2)
	var C := _person(3)
	var made: Dictionary = RegionFactionQuery.allocate(reg, 0, 0.0, {"name": "官", "kind": "npc", "leader_ref": A, "founded_at": 0.0})
	reg = made.registry
	var lawful := int(made.faction_id)
	made = RegionFactionQuery.allocate(reg, int(reg.revision), 0.0, {"name": "黑風寨", "kind": "bandit", "leader_ref": B, "founded_at": 0.0, "duty_ai": true, "bandit": {"origin": "rout", "lair": {"site_id": "s1", "cell": [4, 7]}}})
	if not _check(made.get("ok", false), "a bandit band is allocated", made): return
	reg = made.registry
	var band := int(made.faction_id)
	var entry: Dictionary = reg.entries[str(band)]
	if not _check(entry.kind == "bandit" and entry.duty_ai == false and entry.nation_ref == null, "the band has no nation and duty AI off", entry): return
	if not _check(entry.bandit == {"origin": "rout", "lair": {"site_id": "s1", "cell": [4, 7]}, "raid_ai": true, "heat": 0, "converted_from": null}, "missing sub-table keys take the defaults", entry.bandit): return
	if not _check(RegionPeerage.record_of(reg, B).is_empty() and RegionPeerage.record_of(reg, A).get("rank") == "king", "a bandit chief gets no title; a lawful founder is still crowned"): return
	if not _check(RegionFactionQuery.is_bandit(reg, band) and not RegionFactionQuery.is_bandit(reg, lawful) and not RegionFactionQuery.is_bandit(reg, RegionFactionQuery.NEUTRAL_FACTION_ID) and not RegionFactionQuery.is_bandit(reg, 999), "is_bandit is the band only"): return
	made = RegionFactionQuery.allocate(reg, int(reg.revision), 0.0, {"name": "白虎幫", "kind": "bandit", "leader_ref": C, "founded_at": 0.0})
	reg = made.registry
	var band2 := int(made.faction_id)
	if not _check(RegionFactionQuery.bandit_of(reg, band2) == RegionFactionQuery.BANDIT_DEFAULTS, "a band without a sub-table reads the defaults"): return
	if not _check(not RegionFactionQuery.allocate(reg, int(reg.revision), 0.0, {"name": "錯", "kind": "npc", "bandit": {}}).ok, "a bandit table on a lawful faction is refused at allocation"): return
	if not _check(not RegionFactionQuery.allocate(reg, int(reg.revision), 0.0, {"name": "無頭", "kind": "bandit"}).ok, "a band without a chief is refused"): return

	# BA-01 validator.
	var partial: Dictionary = reg.duplicate(true)
	partial.entries[str(band)].bandit = {"origin": "scenario"}
	if not _check(RegionFactionQuery.validate(partial, 1000.0).ok and RegionFactionQuery.bandit_of(partial, band).heat == 0, "a partial sub-table validates and reads defaults"): return
	if not _corrupt(reg, func(r: Dictionary) -> void: r.entries[str(lawful)]["bandit"] = {}, "a lawful faction with a bandit key"): return
	if not _corrupt(reg, func(r: Dictionary) -> void: r.entries[str(band)].nation_ref = {"type": "nation", "namespace": "n", "lineage": 1}, "a band bound to a nation"): return
	if not _corrupt(reg, func(r: Dictionary) -> void: r.entries[str(band)].duty_ai = true, "a band with duty AI on"): return
	if not _corrupt(reg, func(r: Dictionary) -> void: r.entries[str(band)].leader_ref = null, "an active band without a chief"): return
	if not _corrupt(reg, func(r: Dictionary) -> void: r.entries[str(band)].erase("bandit"), "a band without its sub-table key"): return
	if not _corrupt(reg, func(r: Dictionary) -> void: r.entries[str(band)].bandit["loot"] = 1, "an unknown sub-table key"): return
	if not _corrupt(reg, func(r: Dictionary) -> void: r.entries[str(band)].bandit.heat = 101, "heat above 100"): return
	if not _corrupt(reg, func(r: Dictionary) -> void: r.entries[str(band)].bandit.origin = "pirates", "an unknown origin"): return
	if not _corrupt(reg, func(r: Dictionary) -> void: r.entries[str(band)].bandit.lair = {"site_id": "", "cell": [1, 2]}, "a lair without a Site"): return
	if not _corrupt(reg, func(r: Dictionary) -> void: r.entries[str(band)].bandit.converted_from = {"kind": "npc", "at": 1.0}, "a conversion from a lawful kind"): return
	if not _corrupt(reg, func(r: Dictionary) -> void: r.entries[str(band)].kind = "outlaw", "an unknown kind"): return

	# BA-02 always hostile, no diplomacy.
	var t := 500.0
	var neutral := RegionFactionQuery.NEUTRAL_FACTION_ID
	if not _check(RegionDiplomacy.hostile(reg, band, lawful, t) and RegionDiplomacy.hostile(reg, lawful, band, t) and RegionDiplomacy.hostile(reg, band, neutral, t) and RegionDiplomacy.hostile(reg, band, band2, t), "a band is hostile to a faction, to neutral and to another band"): return
	if not _check(not RegionDiplomacy.hostile(reg, band, band, t), "a band is not hostile to itself"): return
	if not _check(not RegionDiplomacy.at_peace(reg, band, lawful, t) and RegionDiplomacy.treaty_between(reg, band, lawful, t).is_empty() and not RegionDiplomacy.in_breach_window(reg, band, lawful, t), "no peace, no treaty, no breach window"): return
	var before: Dictionary = reg.duplicate(true)
	for refused: Dictionary in [RegionDiplomacy.propose(reg, lawful, band, "truce", 10, A, 0.0, t), RegionDiplomacy.propose(reg, band, lawful, "peace", 0, B, 0.0, t), RegionDiplomacy.declare_war(reg, lawful, band, A, t), RegionDiplomacy.declare_war(reg, band, lawful, B, t), RegionDiplomacy.propose(reg, band, band2, "truce", 5, B, 0.0, t)]:
		if not _check(_code(refused) == "BANDIT_NO_DIPLOMACY" and not refused.has("registry"), "diplomacy with a band is refused with BANDIT_NO_DIPLOMACY", refused): return
	if not _check(reg == before, "refusals write nothing"): return
	var letter: Dictionary = reg.duplicate(true)
	letter["diplomacy"] = RegionDiplomacy.empty()
	letter.diplomacy.next_id = 2
	letter.diplomacy.proposals["1"] = {"id": 1, "from": lawful, "to": band, "kind": "truce", "days": 5, "status": "delivered", "sent_at": 0.0, "deliver_at": 0.0, "reply_deliver_at": null, "accepted": null, "by_ref": A, "reply_ref": null, "reason": ""}
	if not _check(RegionFactionQuery.validate(letter, 1000.0).get("code") == "CORRUPT_SAVE", "an open letter naming a band is corrupt"): return
	if not _check(_code(RegionDiplomacy.reply(letter, 1, true, B, 0.0, t)) == "BANDIT_NO_DIPLOMACY", "a band cannot answer a letter"): return
	var treaty: Dictionary = reg.duplicate(true)
	treaty["diplomacy"] = RegionDiplomacy.empty()
	treaty.diplomacy.next_id = 2
	treaty.diplomacy.treaties["1"] = {"id": 1, "a": mini(lawful, band), "b": maxi(lawful, band), "kind": "peace", "starts_at": 0.0, "ends_at": null, "status": "active", "ended_at": null}
	if not _check(RegionFactionQuery.validate(treaty, 1000.0).get("code") == "CORRUPT_SAVE", "an active treaty with a band is corrupt"): return

	# BA-03 (data side): no title, no fealty, no rebellion into a band.
	if not _check(_code(RegionPeerage.crown_founder(reg, band, B, t)) == "BANDIT_NO_NATION", "a chief cannot be crowned"): return
	var titled: Dictionary = reg.duplicate(true)
	titled.peerage = RegionPeerage.table(titled).duplicate(true)
	titled.peerage[RegionPeerage.key_of(B)] = {"person_ref": B, "faction_id": band, "rank": "king", "liege_ref": null, "granted_at": 0.0}
	if not _check(RegionFactionQuery.validate(titled, 1000.0).get("code") == "CORRUPT_SAVE", "a peerage record inside a band is corrupt"): return
	if not _check(_code(RegionPeerage.swear(titled, B, _person(9), t)) == "BANDIT_NO_DIPLOMACY", "nobody swears fealty to a band"): return
	var D := _person(4)
	var vassal: Dictionary = RegionPeerage.grant(reg, A, D, "baron", [2], t)
	if not _check(vassal.ok, "a lawful baron is granted", vassal): return
	if not _check(_code(RegionPeerage.rebel(vassal.registry, D, "defect", band, B, {}, t)) == "BANDIT_NO_NATION", "a noble cannot rebel into a band"): return

	# BA-10: JSON round trip.
	var hot: Dictionary = reg.duplicate(true)
	hot.entries[str(band)].bandit.heat = 40
	hot.entries[str(band)].bandit.converted_from = {"kind": "rebel", "at": 12.0}
	var wire: Variant = JSON.parse_string(JSON.stringify(hot))
	if not _check(wire is Dictionary and wire.entries[str(band)].bandit.heat is float, "JSON turns heat into a float"): return
	var back: Dictionary = RegionFactionQuery.canonical_registry(wire)
	var row: Dictionary = back.entries[str(band)].bandit
	if not _check(row.heat is int and row.heat == 40 and row.lair.cell[0] is int and row.lair.cell == [4, 7] and row.converted_from.at == 12.0, "canonical ints come back", row): return
	if not _check(RegionFactionQuery.validate(back, 1000.0).ok and RegionDiplomacy.hostile(back, band, lawful, t), "the round-tripped registry validates and keeps the band hostile"): return
	var back_partial: Dictionary = RegionFactionQuery.canonical_registry(partial)
	if not _check(back_partial.entries[str(band)].bandit.size() == RegionFactionQuery.BANDIT_DEFAULTS.size(), "canonicalising fills a partial sub-table"): return
	print("REGION_BANDIT_B1_PASS checks=", checks)
	quit(0)
