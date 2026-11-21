extends SceneTree
## 土匪 B5 slice 2 (bandit spec §7, TR-55): a caravan beaten on a Site is lost and remembered. A 落草 world opens (the
## player's band stands here); a second faction 乙國 is founded and two of the cadres stand apart as its two-person team,
## the captain of a caravan mission bound for this Site. Checks:
## - while its people stand, the caravan is not lost;
## - with both dead, the sweep ends the mission unfinished: it leaves the active missions (its place in the cap is
##   free), a lost record names this Site and the band standing here (raided_by), and the Region ledger still validates;
## - the head's risk reckoning now counts this Site for 乙國's caravans (15 for a road next to it) and not for others';
## - the Site's Region evaluation does the same sweep (a second caravan, its lone captain dead);
## - the ledger keeps the last 16 losses, a loss nobody is known for has raided_by -1, a malformed record is refused, and
##   the caravans field stays while there are losses to remember.
## Output: SITE_CARAVAN_LOST_B5_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Caravan = preload("res://scripts/terrain_lab/site_caravan.gd")
const Caravans = preload("res://scripts/region_lab/region_caravans.gd")
const Risk = preload("res://scripts/region_lab/region_caravan_risk.gd")
const GameplayClock = preload("res://scripts/region_lab/region_gameplay_clock.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_CARAVAN_LOST_B5_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_CARAVAN_LOST_B5 OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _kill(lab: TerrainLab, person: int) -> bool:
	var index := int(lab.crowd_site._index_by_id.get(person, -1))
	return index >= 0 and bool(lab.crowd_site.set_soldier_fields(index, {"hp": 0.0}))

func _mission(controller: SiteController, token: String, faction: int, from_site: String, to_site: String, captain: int) -> Dictionary:
	return {"token": token, "faction": faction, "from_site": from_site, "warehouse": "w", "to_site": to_site,
		"captain_ref": JoinFaction._world_ref(controller, captain), "goods": {"grain": 6}, "phase": "out", "day": 0}

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "劫商世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "bandit", "name": "老寨"}), "a 落草 world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	for _frame: int in range(900):
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _check(lab != null, "the new world opens", RegionEntry.menu_message): return
	for _frame: int in range(5): await process_frame
	var controller: SiteController = lab.site_controller
	var slot: RegionSaveSlot = controller.region_slot
	var player := int(lab.controlled_person_id())
	var band := int(_team_of(lab, player).faction)
	var cadres: Array[int] = []
	for person: Variant in _team_of(lab, player).person_ids:
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _check(cadres.size() >= 5 and RegionFactionQuery.is_bandit(slot.control.faction_registry, band), "the player's band has five cadres", cadres): return
	var now := float(slot.control.logical_game_seconds)
	var prepared: Dictionary = slot.prepare_faction_creation(lab.terrain, int(slot.control.faction_registry.revision), [],
		{"name": "乙國", "kind": "npc", "leader_ref": JoinFaction._world_ref(controller, cadres[4]), "founded_at": now})
	if not _check(prepared.ok and controller._commit_diplomacy(prepared, "").ok, "乙國 is saved", prepared): return
	var lawful := int(prepared.faction_id)
	var scope := str(lab.terrain.site.id)
	var here: Dictionary = slot._coordinate(lab.terrain)
	var home := Grid.site_id(str(slot.pin.atlas_id), here.site + Vector2i(1, 0))
	var far := Grid.site_id(str(slot.pin.atlas_id), here.site + Vector2i(9, 0))
	var ledger: Dictionary = slot.region_registry()

	# The caravan: two cadres stand apart as 乙國's team; the first is its captain.
	var apart: Dictionary = lab.crowd_site.detach_to_new_team(cadres[0], lawful)
	if not _check(apart.ok and lab.crowd_site.join_team(cadres[1], int(apart.team_id), true).ok, "two cadres stand apart as 乙國's caravan", apart): return
	var added := Caravans.add(ledger, _mission(controller, "lost_a", lawful, home, scope, cadres[0]))
	if not _check(added.ok and Caravan.sweep_lost(slot, lab).is_empty() and Caravans.missions(ledger).size() == 1, "while its people stand the caravan is not lost", added): return
	if not _check(_kill(lab, cadres[0]) and _kill(lab, cadres[1]), "both of its people are dead"): return
	var swept: Array = Caravan.sweep_lost(slot, lab)
	if not _check(swept.size() == 1 and int(swept[0].raided_by) == band and str(swept[0].at_site) == scope and int(swept[0].faction) == lawful and str(swept[0].from_site) == home,
		"the caravan is lost here, robbed by the band standing here", swept): return
	if not _check(Caravans.missions(ledger).is_empty() and Caravans.lost(ledger).size() == 1 and GameplayClock.validate_registry(ledger, float(slot.control.logical_game_seconds)).ok,
		"TR-54/55: the mission is over, the loss is on record, the ledger validates", ledger.get("caravans")): return

	# The loss is known danger to 乙國's heads, and to nobody else.
	var registry: Dictionary = slot.control.faction_registry
	if not _check(Risk.known_bands({}, registry, Caravans.lost(ledger), lawful) == {scope: [band]} and Risk.known_bands({}, registry, Caravans.lost(ledger), lawful + 50).is_empty(),
		"the Site it was robbed at is a known band's ground for its own faction only"): return
	var risks: Dictionary = Caravan.route_risks(controller, cadres[2], lawful, [home, far])
	if not _check(risks == {home: 15, far: 15}, "a head of 乙國 reckons 15 for a road that starts beside it", risks): return

	# The Site's own Region evaluation sweeps too.
	var lone: Dictionary = lab.crowd_site.detach_to_new_team(cadres[2], lawful)
	if not _check(lone.ok and Caravans.add(ledger, _mission(controller, "lost_b", lawful, home, scope, cadres[2])).ok and _kill(lab, cadres[2]), "a second caravan's lone captain dies here", lone): return
	var evaluated: Dictionary = Caravan.evaluate(slot, lab)
	if not _check(evaluated.get("lost", []).size() == 1 and Caravans.lost(ledger).size() == 2 and Caravans.missions(ledger).is_empty(), "the evaluation ends that mission as lost", evaluated): return

	# The ledger's memory: the last 16, unknown raiders, malformed records.
	for n: int in range(Caravans.MAX_LOST):
		var mission := {"token": "lost_n%d" % n, "faction": lawful, "from_site": home, "warehouse": "w", "to_site": far,
			"captain_ref": RegionPeerage.world_person_ref(str(slot.pin.world_instance_id), 900000 + n), "goods": {"grain": 1}, "phase": "back", "day": n}
		var extra := Caravans.add(ledger, mission)
		if not _check(extra.ok and Caravans.lose(ledger, int(extra.id), far, n, -1).ok, "loss %d is recorded" % n): return
	var kept: Array = Caravans.lost(ledger)
	if not _check(kept.size() == Caravans.MAX_LOST and int(kept[0].raided_by) == -1 and str(kept[0].at_site) == far and ledger.has("caravans") and Caravans.missions(ledger).is_empty()
		and GameplayClock.validate_registry(ledger, float(slot.control.logical_game_seconds)).ok, "the last 16 losses are kept, the oldest dropped; the field stays", kept.size()): return
	var broken: Dictionary = ledger.duplicate(true)
	broken.caravans.lost[0]["raided_by"] = -2
	if not _check(not GameplayClock.validate_registry(broken, float(slot.control.logical_game_seconds)).ok and not Caravans.lose(ledger, 123456, far, 0, -1).ok, "a malformed loss is refused; an unknown mission cannot be lost"): return
	_finished = true
	print("SITE_CARAVAN_LOST_B5_PASS: ", checks, " checks")
	quit(0)
