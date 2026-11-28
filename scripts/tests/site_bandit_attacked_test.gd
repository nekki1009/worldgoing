extends SceneTree
## 土匪：被官方攻打 (Nekki 2026-11-22 B; site_bandit_attacked.gd). Pure checks of which bands a closed battle counts as
## attacked: a battle against an official faction (not a band, not a rebel, not neutral) counts; a battle among bands,
## against rebels or the neutral side does not; the band's own raid on that Site in the last RAID_DAYS days does not.
## Output: SITE_BANDIT_ATTACKED_PASS on success; quit(1) on any failure.
const Attacked = preload("res://scripts/terrain_lab/site_bandit_attacked.gd")

var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_BANDIT_ATTACKED OK ", checks, ": ", message)
		return true
	push_error("SITE_BANDIT_ATTACKED_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _battle(site_id: String, factions: Array) -> Dictionary:
	var sides := {}
	for faction: int in factions: sides[str(faction)] = {"faction": faction, "people": 3}
	return {"site_id": site_id, "sides": sides}

## attacked_bands as a plain Array (it returns Array[int]).
func _bands(battle: Dictionary, registry: Dictionary, raids: Dictionary, today: int) -> Array:
	var result: Array = []
	result.assign(Attacked.attacked_bands(battle, registry, raids, today))
	return result

func _run() -> void:
	var registry := {"entries": {
		"2": {"faction_id": 2, "kind": "bandit", "status": "active"},
		"3": {"faction_id": 3, "kind": "npc", "status": "active"},
		"4": {"faction_id": 4, "kind": "rebel", "status": "active"},
		"5": {"faction_id": 5, "kind": "bandit", "status": "active"},
		"6": {"faction_id": 6, "kind": "player", "status": "active"},
		"7": {"faction_id": 7, "kind": "bandit", "status": "extinct"}}}
	var here := "atlas:10:10"
	if not _ok(Attacked.official(registry, 3) and Attacked.official(registry, 6) and not Attacked.official(registry, 2) and not Attacked.official(registry, 4)
		and not Attacked.official(registry, RegionFactionQuery.NEUTRAL_FACTION_ID) and not Attacked.official(registry, 99), "official = a registered faction that is not a band, a rebel or neutral"): return
	if not _ok(_bands(_battle(here, [2, 3]), registry, {}, 20) == [2], "a band fighting an NPC faction is attacked"): return
	if not _ok(_bands(_battle(here, [2, 6]), registry, {}, 20) == [2], "a band fighting the player's faction is attacked"): return
	if not _ok(_bands(_battle(here, [2, 5, 3]), registry, {}, 20) == [2, 5], "every band in a battle with an official faction is attacked"): return
	if not _ok(_bands(_battle(here, [2, 4]), registry, {}, 20).is_empty(), "a battle against rebels is no official attack"): return
	if not _ok(_bands(_battle(here, [2, 5]), registry, {}, 20).is_empty(), "a battle among bands is no official attack"): return
	if not _ok(_bands(_battle(here, [2, RegionFactionQuery.NEUTRAL_FACTION_ID]), registry, {}, 20).is_empty(), "a battle against the neutral side is no official attack"): return
	if not _ok(_bands(_battle(here, [7, 3]), registry, {}, 20).is_empty(), "an ended band is not counted"): return
	var raids := {2: {"site_id": here, "day": 19}}
	if not _ok(_bands(_battle(here, [2, 3]), registry, raids, 20).is_empty(), "the band's own raid on this Site (yesterday) is not an attack on it"): return
	if not _ok(_bands(_battle(here, [2, 3]), registry, {2: {"site_id": here, "day": 20 - Attacked.RAID_DAYS - 1}}, 20) == [2], "an older raid there no longer covers the battle"): return
	if not _ok(_bands(_battle("atlas:11:10", [2, 3]), registry, raids, 20) == [2], "a raid elsewhere does not cover a battle on another Site"): return
	print("SITE_BANDIT_ATTACKED_PASS: ", checks, " checks")
	quit(0)
