extends SceneTree
## A real fight in a Region world leaves its battle log and personal records (2026-11-24). Until then no test fought a real
## battle: CrowdSite.step ticked its battle tracker only outside a native work point, which every crowd step runs.
## A world opens with a founded faction (the player captains his cadres). One cadre leaves as a one-person neutral team
## beside them and is hostile to them. Checks:
## - the fight opens the Site's battle tracker and its people join it;
## - once nobody has clashed for RegionBattleLog.QUIET_SECONDS the battle closes: it waits on the Region slot, and the next
##   registry commit writes one record with both factions, the right dead or knocked out, and the player's side as winner;
## - the player's side and the loser carry personal records (battles, wins / losses); NPC diplomacy sees the last fight;
## - what a battle saves to the registry was flushed between two steps; no step fault; the world saves.
## With `-- --band` the cadre is a bandit band of one whose lair is this Site (O3, Nekki 2026-11-24 OQ2): when he falls the
## band ends (extinct, no lair) and the commander who wiped it out gains Bandit.SUPPRESS_PRESTIGE.
## Output: SITE_BATTLE_LOG_LIVE_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Social = preload("res://scripts/terrain_lab/person_social.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const Reputation = preload("res://scripts/terrain_lab/person_reputation.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false
var lab: TerrainLab
var controller: SiteController

func _initialize() -> void:
	create_timer(420.0).timeout.connect(func() -> void: _fail("420-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	printerr("SITE_BATTLE_LOG_LIVE_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_BATTLE_LOG_LIVE OK ", checks, ": ", message, " ", str(detail) if detail != null else "")
		return true
	return _fail(message, detail)

func _team_of(person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _hp(person: int) -> float:
	var body: Dictionary = lab.crowd_site.combat_target(person)
	return float(body.get("hp", 0.0)) if not body.is_empty() else 0.0

## The native state of a person: hp, knockout left, captive, fight state and the Site clock.
func _fate(person: int) -> Dictionary:
	var state: Dictionary = lab.crowd_site.soldier_state(int(lab.crowd_site._index_by_id[person]))
	return {"hp": state.get("hp"), "ko": state.get("ko"), "getup": state.get("getup"), "captive": state.get("captive"), "clock": float(controller.region_slot.control.logical_game_seconds), "combat_left": float(lab.terrain.site.get("combat_left", 0.0))}

## Dead or knocked out: out of this fight.
func _down(person: int) -> bool:
	var fate := _fate(person)
	return float(fate.hp) <= 0.0 or float(fate.ko) > 0.0

func _record(person: int) -> Dictionary:
	var found: Dictionary = controller.person_actions._person(person, false)
	return Social.combat_record(found.body) if not found.is_empty() else {}

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "戰報世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	for _frame: int in range(900):
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _check(lab != null, "the new world opens", RegionEntry.menu_message): return
	for _frame: int in range(5): await process_frame
	controller = lab.site_controller
	var slot: RegionSaveSlot = controller.region_slot
	var player := int(lab.controlled_person_id())
	var home := int(_team_of(player).faction)
	var rebel := -1
	for person: Variant in _team_of(player).person_ids:
		if int(person) != player and rebel < 0: rebel = int(person)
	for _frame: int in range(600):
		var owner: Variant = lab.crowd_site.person_owner(rebel)
		if owner != null and lab.crowd_site._split_exit_ready(owner, int(lab.crowd_site._index_by_id[rebel])): break
		await process_frame
	var as_band := OS.get_cmdline_user_args().has("--band")
	var entry := {"name": "乙國", "kind": "npc", "leader_ref": JoinFaction._world_ref(controller, rebel), "founded_at": float(slot.control.logical_game_seconds)}
	if as_band:
		var stand: Vector2i = lab.crowd_site.combat_target(rebel).cell
		entry.merge({"kind": "bandit", "name": "乙寨", "bandit": {"origin": "refugee", "lair": {"site_id": str(lab.terrain.site.get("id", "")), "cell": [stand.x, stand.y]}}}, true)
	var prepared: Dictionary = slot.prepare_faction_creation(lab.terrain, int(slot.control.faction_registry.revision), [], entry)
	if not _check(prepared.ok and controller._commit_diplomacy(prepared, "").ok, "the cadre's faction is founded", prepared.get("code")): return
	var enemy := int(prepared.faction_id)
	var left: Dictionary = lab.crowd_site.detach_to_new_team(rebel, enemy)
	if not _check(left.ok, "a cadre stands apart as 乙國's team", left): return
	if not _check(RegionDiplomacy.hostile(slot.control.faction_registry, home, enemy, float(slot.control.logical_game_seconds)), "the two factions are hostile"): return
	lab.crowd_site._apply_slot_alliances()
	var ordered: Dictionary = {}
	for _frame: int in range(120):
		await process_frame
		if _finished: return
		ordered = lab.crowd_site.issue_order(int(_team_of(player).team_id), TerrainArmy.CombatOrder.ATTACK, lab.crowd_site.person_owner(rebel).person(int(lab.crowd_site._index_by_id[rebel]), false).get("cell", Vector2i(-1, -1)) if lab.crowd_site.person_owner(rebel) != null else Vector2i(-1, -1), rebel)
		if ordered.get("ok", false): break
	print("SITE_BATTLE_LOG_LIVE order ", ordered.get("ok"), " ", ordered.get("code"))
	var battles_before: int = RegionBattleLog.table(slot.control.faction_registry).records.size()

	var prestige_before := int(controller.reputation_of(player).prestige)
	# The fight.
	var opened := false
	for _frame: int in range(1800):
		await process_frame
		if _finished: return
		if lab.crowd_site.battle.open:
			opened = true
			break
	if not _check(opened, "the fight opens the battle tracker", {"combat_left": lab.terrain.site.get("combat_left"), "hp": _hp(rebel)}): return
	# Weakened, so the next blow of the real fight brings him down.
	lab.crowd_site.apply_environment_damage(rebel, maxf(0.0, _hp(rebel) - 4.0))
	for _frame: int in range(9000):
		await process_frame
		if _finished: return
		if _down(rebel): break
	if not _check(_down(rebel), "the lone cadre is brought down", _fate(rebel)): return
	var participants: Dictionary = lab.crowd_site.battle.participants.duplicate()
	if not _check(participants.has(rebel) and participants.size() >= 2, "both sides joined the battle", participants): return

	print("SITE_BATTLE_LOG_LIVE down ", _fate(rebel))
	# A blow may knock him out instead of killing him; a band only ends when its people are dead or captive.
	if as_band:
		lab.crowd_site.apply_environment_damage(rebel, 10000.0)
		for _frame: int in range(30): await process_frame
		if not _check(float(_fate(rebel).hp) <= 0.0, "the band's only man is dead", _fate(rebel)): return

	# Quiet: the battle closes and is queued on the slot.
	var closed := false
	for _frame: int in range(9000):
		await process_frame
		if _finished: return
		if not lab.crowd_site.battle.open:
			closed = true
			break
	if not _check(closed, "the battle closes once it is quiet", {"combat_left": lab.terrain.site.get("combat_left"), "quiet": lab.crowd_site.battle.quiet_since}): return
	print("SITE_BATTLE_LOG_LIVE at close ", _fate(rebel))
	for _frame: int in range(5): await process_frame
	if not _check(controller.battle_effects_due.is_empty(), "what the battle saves was flushed between two steps", controller.battle_effects_due): return
	var committed: Dictionary = controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "")
	if not _check(committed.ok, "the world saves", committed): return
	var log := RegionBattleLog.table(slot.control.faction_registry)
	if not _check(log.records.size() == battles_before + 1, "the registry has one new battle record", log.records.size()): return
	var battle: Dictionary = log.records.back()
	var mine: Dictionary = battle.sides.get(str(home), {})
	var theirs: Dictionary = battle.sides.get(str(enemy), {})
	if not _check(not mine.is_empty() and not theirs.is_empty() and str(battle.site_id) == str(lab.terrain.site.id), "the record names both factions and this Site", battle): return
	if not _check(int(theirs.deaths) + int(theirs.kos) + int(theirs.captured) >= 1, "the record counts the lone cadre's loss", theirs): return
	if not _check(int(battle.winner) == home, "the player's faction won", battle.winner): return
	if not _check(RegionBattleLog.last_fight(slot.control.faction_registry, home, enemy) > 0.0, "diplomacy sees the last fight"): return
	var won := 0
	for person: Variant in participants:
		if int(participants[person]) == home and int(_record(int(person)).get("wins", 0)) == 1: won += 1
	if not _check(won >= 1, "the winners carry a won battle", won): return
	if not _check(int(_record(rebel).get("battles", 0)) == 1 and int(_record(rebel).get("losses", 0)) == 1, "the lone cadre carries a lost battle", _record(rebel)): return
	if as_band:
		var ended: Dictionary = slot.control.faction_registry.entries.get(str(enemy), {})
		if not _check(str(ended.get("status", "")) == "extinct" and RegionFactionQuery.canonical_bandit(ended.get("bandit", {})).get("lair") == null, "the wiped-out band ended and has no lair", [ended.get("status"), ended.get("bandit")]): return
		if not _check(Reputation.shown(int(controller.reputation_of(player).prestige)) == Reputation.shown(prestige_before) + 3, "the commander who wiped it out gained 3 prestige", [prestige_before, controller.reputation_of(player).prestige]): return
	if not _check(controller._original_step_fault.is_empty(), "no step fault", controller._original_step_fault): return
	_finished = true
	print("SITE_BATTLE_LOG_LIVE_PASS: ", checks, " checks; a real fight leaves its battle log and personal records")
	quit(0)
