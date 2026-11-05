extends SceneTree
## Diplomacy (FACTION_DIPLOMACY_SPECIFICATION §11), pure data over the faction registry. Checks:
## - different active factions are hostile; neutral can neither propose nor be at peace;
## - a truce letter travels by distance, is replied within 7 days, the answer travels back, and takes effect on arrival;
## - one open letter per pair and kind; a rejection puts a 3-day cooldown; an unanswered letter expires after 7 days;
## - a truce ends on its own (no breach); peace replaces a running truce;
## - declaring war on a pair at peace is a breach: treaties end, open letters are invalidated, 30/10-day windows;
## - next_event_at, the registry validator and a JSON round trip.
## Output: REGION_DIPLOMACY_PASS on success; quit(1) on any failure.

var checks := 0
const DAY := 86400.0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_DIPLOMACY OK ", checks, ": ", message)
		return true
	printerr("REGION_DIPLOMACY_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _person(lineage: int) -> Dictionary:
	return {"type": "person", "namespace": "diplomacy_test", "lineage": lineage}

func _step(result: Dictionary, message: String) -> Dictionary:
	if not _check(result.get("ok", false), message, result): return {}
	return result.registry

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
	var neutral := RegionFactionQuery.NEUTRAL_FACTION_ID
	var t := 1000.0
	if not _check(RegionDiplomacy.hostile(reg, fa, fb, t) and not RegionDiplomacy.hostile(reg, fa, fa, t) and RegionDiplomacy.hostile(reg, neutral, neutral, t), "different factions are hostile, a faction is not hostile to itself, neutral teams stay apart"): return
	if not _check(not RegionDiplomacy.propose(reg, neutral, fb, "truce", 10, A, 0.0, t).ok, "neutral cannot propose"): return
	if not _check(not RegionDiplomacy.propose(reg, fa, fb, "truce", 2, A, 0.0, t).ok and not RegionDiplomacy.propose(reg, fa, fb, "truce", 61, A, 0.0, t).ok, "a truce must last 3 to 60 days"): return

	# 4000 m of letter travel = 3600 game seconds each way.
	var sent: Dictionary = RegionDiplomacy.propose(reg, fa, fb, "truce", 10, A, 4000.0, t)
	reg = _step(sent, "甲 sends 乙 a 10-day truce letter")
	if reg.is_empty(): return
	var id := int(sent.proposal_id)
	if not _check(RegionDiplomacy.table(reg).proposals[str(id)].deliver_at == t + 3600.0, "delivery after 3600 s for 4000 m"): return
	if not _check(not RegionDiplomacy.propose(reg, fb, fa, "truce", 5, B, 4000.0, t).ok, "one open letter per pair and kind, either direction"): return
	if not _check(is_equal_approx(RegionDiplomacy.next_event_at(reg, t), t + 3600.0), "the next event is the delivery"): return
	if not _check(not RegionDiplomacy.reply(reg, id, true, B, 4000.0, t + 100.0).ok, "a letter cannot be answered before it arrives"): return
	reg = _step(RegionDiplomacy.reply(reg, id, true, B, 4000.0, t + 3600.0 + 50.0), "乙 accepts on arrival")
	if reg.is_empty(): return
	if not _check(RegionDiplomacy.hostile(reg, fa, fb, t + 3700.0), "an accepted answer still on its way changes nothing yet"): return
	var arrive := t + 3600.0 + 50.0 + 3600.0
	var settled: Dictionary = RegionDiplomacy.settle(reg, arrive)
	reg = _step(settled, "the answer arrives")
	if reg.is_empty(): return
	var truce: Dictionary = RegionDiplomacy.treaty_between(reg, fa, fb, arrive)
	if not _check(truce.get("kind") == "truce" and is_equal_approx(float(truce.ends_at), arrive + 10.0 * DAY) and not RegionDiplomacy.hostile(reg, fa, fb, arrive), "the truce starts when the answer arrives and lasts 10 days", truce): return
	if not _check(RegionDiplomacy.hostile(reg, fa, fc, arrive), "a third faction is still hostile"): return

	# Peace replaces the truce.
	sent = RegionDiplomacy.propose(reg, fa, fb, "peace", 0, A, 0.0, arrive)
	reg = _step(sent, "甲 proposes peace in person (no delay)")
	if reg.is_empty(): return
	reg = _step(RegionDiplomacy.settle(reg, arrive), "the peace letter arrives at once")
	if reg.is_empty(): return
	reg = _step(RegionDiplomacy.reply(reg, int(sent.proposal_id), true, B, 0.0, arrive), "乙 accepts peace")
	if reg.is_empty(): return
	reg = _step(RegionDiplomacy.settle(reg, arrive), "the peace takes effect")
	if reg.is_empty(): return
	if not _check(RegionDiplomacy.treaty_between(reg, fa, fb, arrive + 30.0 * DAY).get("kind") == "peace", "peace replaced the truce and has no end"): return

	# Rejection cooldown and expiry with the third faction.
	sent = RegionDiplomacy.propose(reg, fa, fc, "truce", 5, A, 0.0, arrive)
	reg = _step(sent, "甲 sends 丙 a truce letter")
	if reg.is_empty(): return
	reg = _step(RegionDiplomacy.settle(reg, arrive), "delivered")
	if reg.is_empty(): return
	reg = _step(RegionDiplomacy.reply(reg, int(sent.proposal_id), false, C, 0.0, arrive), "丙 refuses")
	if reg.is_empty(): return
	reg = _step(RegionDiplomacy.settle(reg, arrive), "the refusal arrives")
	if reg.is_empty(): return
	if not _check(RegionDiplomacy.propose(reg, fc, fa, "truce", 5, C, 0.0, arrive + DAY).get("code") == "COOLDOWN", "3-day cooldown after a refusal, in both directions"): return
	sent = RegionDiplomacy.propose(reg, fc, fa, "truce", 5, C, 0.0, arrive + 3.0 * DAY)
	reg = _step(sent, "after 3 days 丙 may send one")
	if reg.is_empty(): return
	reg = _step(RegionDiplomacy.settle(reg, arrive + 3.0 * DAY + 8.0 * DAY), "unanswered for 7 days")
	if reg.is_empty(): return
	if not _check(RegionDiplomacy.table(reg).proposals[str(int(sent.proposal_id))].status == "expired", "an unanswered letter expires after 7 days"): return

	# War on a pair at peace is a breach.
	var now := arrive + 20.0 * DAY
	var war: Dictionary = RegionDiplomacy.declare_war(reg, fa, fb, A, now)
	reg = _step(war, "甲 declares war on 乙 while at peace")
	if reg.is_empty(): return
	if not _check(war.breach and RegionDiplomacy.hostile(reg, fa, fb, now) and RegionDiplomacy.table(reg).breaches.size() == 1, "a breach is recorded and the pair is hostile"): return
	if not _check(RegionDiplomacy.in_breach_window(reg, fa, fb, now + 29.0 * DAY) and not RegionDiplomacy.in_breach_window(reg, fa, fb, now + 30.0 * DAY), "the victim refuses the breaker for 30 days"): return
	if not _check(RegionDiplomacy.in_breach_window(reg, fa, fc, now + 9.0 * DAY) and not RegionDiplomacy.in_breach_window(reg, fa, fc, now + 10.0 * DAY), "others refuse the breaker for 10 days"): return
	var again: Dictionary = RegionDiplomacy.declare_war(reg, fa, fb, A, now + 1.0)
	if not _check(again.ok and not again.changed, "war on an already hostile pair changes nothing and is no breach"): return

	# A truce running out on its own is no breach.
	var bc_now := now + DAY
	sent = RegionDiplomacy.propose(reg, fb, fc, "truce", 3, B, 0.0, bc_now)
	reg = _step(sent, "乙 offers 丙 a 3-day truce")
	if reg.is_empty(): return
	reg = _step(RegionDiplomacy.settle(reg, bc_now), "delivered")
	if reg.is_empty(): return
	reg = _step(RegionDiplomacy.reply(reg, int(sent.proposal_id), true, C, 0.0, bc_now), "丙 accepts")
	if reg.is_empty(): return
	reg = _step(RegionDiplomacy.settle(reg, bc_now), "the truce starts")
	if reg.is_empty(): return
	reg = _step(RegionDiplomacy.settle(reg, bc_now + 3.0 * DAY), "three days later")
	if reg.is_empty(): return
	if not _check(RegionDiplomacy.hostile(reg, fb, fc, bc_now + 3.0 * DAY) and RegionDiplomacy.table(reg).breaches.size() == 1, "the truce ended by itself without a breach"): return

	var parsed: Variant = JSON.parse_string(JSON.stringify(reg))
	if not _check(parsed is Dictionary and RegionFactionQuery.validate(parsed, bc_now + 3.0 * DAY).ok, "the registry stays valid after JSON"): return
	if not _check(RegionFactionQuery.canonical_registry(parsed).diplomacy == RegionDiplomacy.canonical(reg.diplomacy), "the canonical table after JSON equals the original"): return
	var corrupt: Dictionary = reg.duplicate(true)
	corrupt.diplomacy.treaties[corrupt.diplomacy.treaties.keys()[0]].kind = "alliance"
	if not _check(not RegionFactionQuery.validate(corrupt, bc_now + 3.0 * DAY).ok, "an unknown treaty kind is refused"): return
	print("REGION_DIPLOMACY_PASS: ", checks, " checks")
	quit(0)
