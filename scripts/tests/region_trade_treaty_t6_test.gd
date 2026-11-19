extends SceneTree
## 貿易 T6 S7 (reports/trade-plan.md T6 TR-60/61, Q12 A; faction plan §11): the trade treaty, pure data over the faction
## registry (RegionDiplomacy), as region_diplomacy_test. Checks:
## - TR-60: a trade letter needs the pair at peace (a hostile pair is refused NOT_AT_PEACE), 30–365 days, a rate 0–50%;
## - delivered and answered, it takes effect on arrival with its rate; it never makes a pair peaceful by itself
##   (treaty_between stays the peace base); a second one is refused ALREADY_TRADING;
## - peace replacing the truce keeps the trade treaty; when the trade treaty's own term runs out it ends (the pair stays
##   at peace); a truce that runs out with no peace behind it ends the trade treaty too (FA-29);
## - declaring war ends it with a breach (FA-14);
## - the NPC accepts at peace with a rate no higher than its lowest other trade treaty, and refuses a breacher;
## - the registry validator and a JSON round trip keep the treaty's rate.
## Output: REGION_TRADE_TREATY_T6_PASS on success; quit(1) on any failure.

var checks := 0
const DAY := 86400.0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_TRADE_TREATY_T6 OK ", checks, ": ", message)
		return true
	printerr("REGION_TRADE_TREATY_T6_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _person(lineage: int) -> Dictionary:
	return {"type": "person", "namespace": "trade_treaty_test", "lineage": lineage}

func _step(result: Dictionary, message: String) -> Dictionary:
	if not _check(result.get("ok", false), message, result): return {}
	return result.registry

## Proposes, delivers, answers and settles a letter at distance 0; returns the registry after the answer arrives.
func _agree(reg: Dictionary, from: int, to: int, kind: String, days: int, tax: int, by: Dictionary, to_ref: Dictionary, t: float, label: String) -> Dictionary:
	var sent: Dictionary = RegionDiplomacy.propose(reg, from, to, kind, days, by, 0.0, t, tax)
	reg = _step(sent, label + ": sent")
	if reg.is_empty(): return {}
	reg = _step(RegionDiplomacy.settle(reg, t), label + ": delivered")
	if reg.is_empty(): return {}
	reg = _step(RegionDiplomacy.reply(reg, int(sent.proposal_id), true, to_ref, 0.0, t), label + ": accepted")
	if reg.is_empty(): return {}
	return _step(RegionDiplomacy.settle(reg, t), label + ": answer arrives")

func _run() -> void:
	var reg: Dictionary = {"version": 1, "revision": 0, "next_faction_id": 1, "migration_complete": true, "entries": {}, "coverage": {"complete": false, "sources": [], "counts": null}}
	var A := _person(1)
	var B := _person(2)
	var C := _person(3)
	var made: Dictionary = RegionFactionQuery.allocate(reg, 0, 0.0, {"name": "甲", "kind": "player", "leader_ref": A, "founded_at": 0.0})
	reg = made.registry
	var fa := int(made.faction_id)
	made = RegionFactionQuery.allocate(reg, int(reg.revision), 0.0, {"name": "乙", "kind": "npc", "leader_ref": B, "founded_at": 0.0})
	reg = made.registry
	var fb := int(made.faction_id)
	made = RegionFactionQuery.allocate(reg, int(reg.revision), 0.0, {"name": "丙", "kind": "npc", "leader_ref": C, "founded_at": 0.0})
	reg = made.registry
	var fc := int(made.faction_id)
	var t := 1000.0

	# TR-60: hostile pairs cannot sign; terms are bounded.
	var hostile_try: Dictionary = RegionDiplomacy.propose(reg, fa, fb, "trade", 90, A, 0.0, t, 5)
	if not _check(not hostile_try.ok and str(hostile_try.code) == "NOT_AT_PEACE", "a hostile pair cannot sign a trade treaty", hostile_try): return
	reg = _agree(reg, fa, fb, "truce", 20, 0, A, B, t, "甲 and 乙 make a 20-day truce")
	if reg.is_empty(): return
	if not _check(not RegionDiplomacy.propose(reg, fa, fb, "trade", 29, A, 0.0, t, 5).ok and not RegionDiplomacy.propose(reg, fa, fb, "trade", 366, A, 0.0, t, 5).ok
		and not RegionDiplomacy.propose(reg, fa, fb, "trade", 90, A, 0.0, t, 51).ok, "a trade treaty lasts 30–365 days at a rate 0–50%"): return

	# At peace (truce): the trade treaty takes effect on arrival with its rate; it stacks on the peace base.
	reg = _agree(reg, fa, fb, "trade", 90, 5, A, B, t, "甲 and 乙 sign a 90-day trade treaty at 5%")
	if reg.is_empty(): return
	var trading: Dictionary = RegionDiplomacy.trade_treaty_between(reg, fb, fa, t)
	if not _check(not trading.is_empty() and int(trading.tax_percent) == 5 and is_equal_approx(float(trading.ends_at), t + 90.0 * DAY), "the trade treaty stands at 5% for 90 days", trading): return
	if not _check(str(RegionDiplomacy.treaty_between(reg, fa, fb, t).get("kind", "")) == "truce", "the peace base is still the truce (a trade treaty is no peace by itself)"): return
	var again: Dictionary = RegionDiplomacy.propose(reg, fb, fa, "trade", 60, B, 0.0, t, 3)
	if not _check(not again.ok and str(again.code) == "ALREADY_TRADING", "a second trade treaty is refused", again): return

	# Peace replaces the truce and keeps the trade treaty.
	reg = _agree(reg, fa, fb, "peace", 0, 0, A, B, t + DAY, "甲 and 乙 make peace")
	if reg.is_empty(): return
	if not _check(str(RegionDiplomacy.treaty_between(reg, fa, fb, t + DAY).get("kind", "")) == "peace" and not RegionDiplomacy.trade_treaty_between(reg, fa, fb, t + DAY).is_empty(), "peace replaces the truce; the trade treaty stands"): return
	# Its own term ends it; the pair stays at peace.
	var past_term := t + 91.0 * DAY
	reg = _step(RegionDiplomacy.settle(reg, past_term), "the clock passes the trade treaty's term")
	if reg.is_empty(): return
	if not _check(RegionDiplomacy.trade_treaty_between(reg, fa, fb, past_term).is_empty() and RegionDiplomacy.at_peace(reg, fa, fb, past_term), "the trade treaty ended on its term; the pair is still at peace"): return

	# FA-29: a truce running out with no peace behind it ends the trade treaty.
	var t2 := past_term + DAY
	reg = _agree(reg, fa, fc, "truce", 10, 0, A, C, t2, "甲 and 丙 make a 10-day truce")
	if reg.is_empty(): return
	reg = _agree(reg, fa, fc, "trade", 60, 4, A, C, t2, "甲 and 丙 sign a 60-day trade treaty at 4%")
	if reg.is_empty(): return
	var after_truce := t2 + 11.0 * DAY
	reg = _step(RegionDiplomacy.settle(reg, after_truce), "the truce runs out")
	if reg.is_empty(): return
	if not _check(RegionDiplomacy.hostile(reg, fa, fc, after_truce) and RegionDiplomacy.trade_treaty_between(reg, fa, fc, after_truce).is_empty(), "the truce's end leaves the pair hostile and ends their trade treaty"): return

	# FA-14: war ends a trade treaty with a breach.
	var t3 := after_truce + DAY
	reg = _agree(reg, fb, fc, "peace", 0, 0, B, C, t3, "乙 and 丙 make peace")
	if reg.is_empty(): return
	reg = _agree(reg, fb, fc, "trade", 120, 2, B, C, t3, "乙 and 丙 sign a trade treaty at 2%")
	if reg.is_empty(): return
	# NPC rule: 丙 accepts from 甲? (hostile now) no; 乙 accepts a rate no higher than its lowest (2%) and refuses 3%.
	if not _check(not RegionDiplomacy.npc_accepts_trade(reg, fc, fa, 0, t3) and RegionDiplomacy.npc_accepts_trade(reg, fb, fc, 2, t3)
		and not RegionDiplomacy.npc_accepts_trade(reg, fb, fc, 3, t3), "the NPC accepts only at peace, at no more than its lowest rate"): return
	var war: Dictionary = RegionDiplomacy.declare_war(reg, fc, fb, C, t3 + 10.0)
	reg = _step(war, "丙 declares war on 乙")
	if reg.is_empty(): return
	if not _check(bool(war.breach) and RegionDiplomacy.trade_treaty_between(reg, fb, fc, t3 + 10.0).is_empty(), "the war is a breach and ends the trade treaty"): return
	if not _check(not RegionDiplomacy.npc_accepts_trade(reg, fb, fc, 0, t3 + 20.0), "乙 refuses a trade treaty from the breacher"): return

	# Validation and a JSON round trip keep the treaty's rate.
	var now := t3 + 20.0
	var checked: Dictionary = RegionFactionQuery.validate(reg, now)
	if not _check(checked.ok, "the registry with trade treaties validates", checked): return
	var wire: Dictionary = JSON.parse_string(JSON.stringify(RegionDiplomacy.table(reg)))
	var canon: Dictionary = RegionDiplomacy.canonical(wire)
	var rates: Array = []
	for treaty: Dictionary in canon.treaties.values():
		if str(treaty.kind) == "trade": rates.append(treaty.tax_percent)
	if not _check(rates.size() == 3 and rates.all(func(rate: Variant) -> bool: return rate is int), "a JSON round trip keeps every trade treaty's rate as an integer", rates): return
	var bad: Dictionary = reg.duplicate(true)
	for treaty: Dictionary in bad.diplomacy.treaties.values():
		if str(treaty.kind) == "trade": treaty["tax_percent"] = 80
	if not _check(not RegionFactionQuery.validate(bad, now).ok, "a trade treaty rate above 50% is refused"): return

	print("REGION_TRADE_TREATY_T6_PASS: ", checks, " checks; peace-only, bounded terms, stacks on the peace base, own term, truce end, war breach, NPC rule, validation")
	quit(0)
