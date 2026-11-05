extends SceneTree
## Battle log and personal records, pure (Nekki 2026-11-05). Checks:
## - the tracker opens, collects deaths / KOs / captures with strikers and captors, routs, and closes after 60 quiet
##   game seconds; a one-faction skirmish is no battle;
## - close builds sides (people, deaths, KOs, captured, commander), the winner (the only unbroken side still standing),
##   and personal deltas (battles, wins, losses, routs, kills, KOs dealt, captures, nobles captured, captured, KO'd,
##   commanded);
## - RegionBattleLog.add keeps pair_last for diplomacy, trims to 200, validates and survives JSON;
## - PersonSocial.combat_record adds deltas and stays valid.
## Output: REGION_BATTLE_LOG_PASS on success; quit(1) on any failure.

const Tracker = preload("res://scripts/terrain_lab/site_battle_tracker.gd")
const Social = preload("res://scripts/terrain_lab/person_social.gd")
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_BATTLE_LOG OK ", checks, ": ", message)
		return true
	printerr("REGION_BATTLE_LOG_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _run() -> void:
	var t: Tracker = Tracker.new()
	if not _check(not t.tick(true, 0.0), "a closed tracker does nothing"): return
	t.begin("site_a", 100.0)
	# Faction 1: persons 11 (captain), 12, 13. Faction 2: persons 21 (captain), 22.
	t.join(11, 1); t.join(21, 2)
	t.on_event(0, 22, 2, 12, 1, -1, -1, false) # 12 kills 22
	t.on_event(1, 13, 1, 21, 2, -1, -1, false) # 21 knocks out 13
	t.on_event(4, 21, 2, -1, -1, 11, 1, true) # 11 captures the titled 21
	t.on_rout(7, 2, [21, 22])
	if not _check(not t.tick(true, 110.0) and not t.tick(false, 120.0) and not t.tick(false, 179.0) and t.tick(false, 180.0), "the battle closes after 60 quiet game seconds"): return
	var closed: Dictionary = t.close(180.0, {1: 3, 2: 0}, {1: {"person": 11, "ref": null}, 2: {"person": 21, "ref": null}})
	var battle: Dictionary = closed.get("battle", {})
	if not _check(RegionBattleLog.valid_battle(battle) and battle.winner == 1 and battle.routed_teams == [7], "faction 1 wins: faction 2 routed and has nobody standing", battle): return
	if not _check(battle.sides["2"].deaths == 1 and battle.sides["2"].captured == 1 and battle.sides["1"].kos == 1 and battle.sides["1"].people == 3 and battle.sides["2"].people == 2, "sides count deaths, KOs, captures and people", battle.sides): return
	var d: Dictionary = closed.deltas
	if not _check(d[12].kills == 1 and d[21].kos_dealt == 1 and d[13].kod == 1 and d[11].captures == 1 and d[11].nobles_captured == 1 and d[21].captured == 1, "kills, KOs dealt, KO'd, captures, nobles captured and captured are credited", d): return
	if not _check(d[11].wins == 1 and d[13].wins == 1 and d[22].losses == 1 and d[21].routs == 1 and d[11].commanded == 1 and d[21].commanded == 1 and d[12].battles == 1, "battles, wins, losses, routs and command are credited", d): return
	var lonely: Tracker = Tracker.new()
	lonely.begin("site_b", 0.0)
	lonely.join(11, 1)
	if not _check(lonely.close(70.0, {}, {}).is_empty(), "a one-faction skirmish is no battle"): return

	var reg: Dictionary = {"version": 1, "revision": 0, "next_faction_id": 3, "migration_complete": true, "entries": {}, "coverage": {"complete": false, "sources": [], "counts": null}}
	var added: Dictionary = RegionBattleLog.add(reg, battle, 200.0)
	if not _check(added.ok and RegionBattleLog.last_fight(added.registry, 2, 1) == 180.0 and RegionBattleLog.last_fight(added.registry, 1, 3) == -1.0, "the log keeps the pair's last fight for diplomacy", added): return
	reg = added.registry
	for index in range(205):
		var more: Dictionary = battle.duplicate(true)
		more.started_at = 200.0 + index
		more.ended_at = 200.0 + index
		reg = RegionBattleLog.add(reg, more, 1000.0).registry
	if not _check(RegionBattleLog.table(reg).records.size() == RegionBattleLog.MAX_RECORDS and RegionBattleLog.last_fight(reg, 1, 2) == 404.0, "the log keeps the newest 200 battles and the latest pair time"): return
	var parsed: Variant = JSON.parse_string(JSON.stringify(reg))
	if not _check(parsed is Dictionary and RegionFactionQuery.validate(parsed, 1000.0).ok and RegionFactionQuery.canonical_registry(parsed).battles == RegionBattleLog.canonical(reg.battles), "the log survives JSON and validates"): return

	var body := {}
	Social.add_combat_record(body, d[11])
	Social.add_combat_record(body, {"battles": 1, "wins": 1})
	var record: Dictionary = Social.combat_record(body)
	if not _check(Social.valid(body.social_state) and record.battles == 2 and record.wins == 2 and record.captures == 1 and record.commanded == 1, "personal records add up on the person and stay valid", record): return
	var v3: Dictionary = Social.upgraded(body.social_state)
	if not _check(Social.valid(v3) and v3.combat_record.battles == 2, "the v1 -> v3 upgrade keeps the record"): return
	print("REGION_BATTLE_LOG_PASS: ", checks, " checks")
	quit(0)
