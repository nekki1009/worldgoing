extends SceneTree
## 土匪 B5 slice 3 (bandit spec §7): the market does not deal with bandits. A 落草 world opens (the player is a band's
## chief); a lawful faction 乙國 is founded and two of the cadres stand apart as its team. Checks:
## - a person's trade (SiteTradeSession.hostile): the band and 乙國 are hostile both ways; two people of 乙國 are not;
## - a caravan at a settlement of 乙國 (a stand-in record with a bound warehouse, never saved): a band's caravan is
##   refused HOSTILE before anything is looked at; 乙國's own caravan is not refused for hostility.
## Output: SITE_MARKET_BANDIT_B5_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Caravan = preload("res://scripts/terrain_lab/site_caravan.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_MARKET_BANDIT_B5_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_MARKET_BANDIT_B5 OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "市集世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "bandit", "name": "老寨"}), "a 落草 world is requested", RegionEntry.menu_message): return
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
	if not _check(cadres.size() >= 5 and RegionFactionQuery.is_bandit(slot.control.faction_registry, band), "the player chiefs a band with five cadres", cadres): return
	var prepared: Dictionary = slot.prepare_faction_creation(lab.terrain, int(slot.control.faction_registry.revision), [],
		{"name": "乙國", "kind": "npc", "leader_ref": JoinFaction._world_ref(controller, cadres[4]), "founded_at": float(slot.control.logical_game_seconds)})
	if not _check(prepared.ok and controller._commit_diplomacy(prepared, "").ok, "乙國 is saved", prepared): return
	var lawful := int(prepared.faction_id)
	var apart: Dictionary = lab.crowd_site.detach_to_new_team(cadres[0], lawful)
	if not _check(apart.ok and lab.crowd_site.join_team(cadres[1], int(apart.team_id), true).ok, "two cadres stand apart as 乙國's team", apart): return
	for _frame: int in range(3): await process_frame

	# A person's trade.
	var trade: Variant = controller._trade()
	var chief: Dictionary = controller.person_actions._person(player, false)
	var merchant: Dictionary = controller.person_actions._person(cadres[0], false)
	var clerk: Dictionary = controller.person_actions._person(cadres[1], false)
	if not _check(int(chief.faction) == band and int(merchant.faction) == lawful and int(clerk.faction) == lawful, "the chief is the band's, the two cadres 乙國's", [chief.faction, merchant.faction, clerk.faction]): return
	if not _check(trade.hostile(chief, merchant) and trade.hostile(merchant, chief) and not trade.hostile(merchant, clerk), "the band and 乙國 do not trade; two of 乙國 do"): return

	# A caravan at 乙國's market.
	var data := lab.terrain
	data.site["settlement"] = {"version": 1, "settlement_id": "market_village", "center_id": "c", "level": 2, "name": "市集村", "owner_faction": lawful,
		"offices": SiteOffices.default_offices("settlement", cadres[1], true), "fall_record": SiteSettlement.empty_fall_record(),
		"trade_sources": {"w": {"revision": 1, "limits": {"wood": {"per_trade": 10, "total": 100}}, "used": {}}}}
	var robbers := Caravan.sell_here(lab, controller, {"id": 1, "faction": band, "goods": {"grain": 5}}, player)
	var traders := Caravan.sell_here(lab, controller, {"id": 2, "faction": lawful, "goods": {"grain": 5}}, cadres[0])
	data.site.erase("settlement")
	if not _check(str(robbers.get("code", "")) == "HOSTILE", "a band's caravan is refused at 乙國's market", robbers): return
	if not _check(str(traders.get("code", "")) != "HOSTILE", "乙國's own caravan is not refused for hostility", traders): return
	_finished = true
	print("SITE_MARKET_BANDIT_B5_PASS: ", checks, " checks")
	quit(0)
