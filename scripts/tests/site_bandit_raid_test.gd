extends SceneTree
## 土匪 B4d-3a in a live world (reports/bandit-faction-spec.md §5.1, §11, §12): a band raids the settlement of its Site.
## A 落草 world opens (the player chiefs a band of himself and five cadres, lair here). Two cadres leave as a lawful
## faction 乙國 (one its king); the player hands the captaincy and the chief's seat to a cadre and leaves, so the band is
## an NPC band of three in one team. A test-only stand-in settlement of 乙國 stands on this Site (never saved). Checks:
## - with 3 bandits against 2 defenders (1.5 >= 1.2) the chief's daily move is a raid: every band team gets an ATTACK
##   order on a 乙國 defender, the native formation holds the order, a notice is written;
## - without a settlement there is nothing to raid (the band rests);
## - a band that holds a paid protection for this Site does not raid it.
## Output: SITE_BANDIT_RAID_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const BanditDay = preload("res://scripts/terrain_lab/site_bandit_day.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const START := Vector2i(1170, 13252)
## The native formation order code of ATTACK (CrowdSite.issue_order maps TerrainArmy.CombatOrder.ATTACK to 2).
const NATIVE_ATTACK := 2

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_BANDIT_RAID_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_BANDIT_RAID OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _found(controller: SiteController, fields: Dictionary, people: Array[int]) -> int:
	var lab: TerrainLab = controller.lab
	var slot: RegionSaveSlot = controller.region_slot
	var prepared: Dictionary = slot.prepare_faction_creation(lab.terrain, int(slot.control.faction_registry.revision), [], fields)
	if not _check(prepared.ok, "faction %s is prepared" % str(fields.name), prepared): return -1
	var faction := int(prepared.faction_id)
	if not _check(controller._commit_diplomacy(prepared, "").ok, "faction %s is saved" % str(fields.name)): return -1
	for person: int in people:
		var left: Dictionary = lab.crowd_site.detach_to_new_team(person, faction)
		if not _check(left.ok, "#%d joins %s" % [person, str(fields.name)], left): return -1
	if not _check(controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "").ok, "the teams of %s are saved" % str(fields.name)): return -1
	return faction

func _run() -> void:
	var requested: bool = RegionEntry.request_new_world(START, {}, "劫掠世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "bandit", "name": "老寨"})
	if not _check(requested, "a 落草 world is requested", RegionEntry.menu_message): return
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
	var own_band := int(_team_of(lab, player).faction)
	var cadres: Array[int] = []
	for person: Variant in _team_of(lab, player).person_ids:
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _check(cadres.size() >= 5, "the player's band has five cadres", cadres): return
	var site_id := str(lab.terrain.site.id)
	var now := float(slot.control.logical_game_seconds)
	var lawful := _found(controller, {"name": "乙國", "kind": "npc", "leader_ref": JoinFaction._world_ref(controller, cadres[0]), "founded_at": now}, [cadres[0], cadres[1]])
	if lawful < 0: return
	var chief := cadres[2]
	var band := own_band
	var team_id := int(_team_of(lab, player).team_id)
	if not _check(lab.crowd_site.hand_over_captain(team_id, chief).ok, "the player hands the captaincy to a cadre"): return
	var left: Dictionary = lab.crowd_site.detach_to_new_team(player, RegionFactionQuery.NEUTRAL_FACTION_ID)
	if not _check(left.ok, "the player leaves the band", left): return
	var succeeded: Dictionary = Bandit.succeed(slot.control.faction_registry, band, JoinFaction._world_ref(controller, chief), now)
	if not _check(succeeded.ok and controller._commit_diplomacy(succeeded, "").ok, "the cadre is the band's chief now", succeeded): return
	# A 落草 band starts with its raid AI off (the player decides); the NPC chief's band raids on its own.
	var raiding: Dictionary = Bandit._with_table(slot.control.faction_registry, band, func(table: Dictionary) -> void: table.raid_ai = true, now)
	if not _check(raiding.ok and controller._commit_diplomacy(raiding, "").ok, "the band's raid AI is on", raiding): return
	var lair: Variant = RegionFactionQuery.bandit_of(slot.control.faction_registry, band).lair
	if not _check(lair is Dictionary and str(lair.site_id) == site_id, "the band's lair is this Site", lair): return
	var visible: Dictionary = controller.visible_strength()
	if not _check(int(visible.get(band, 0)) == 3 and int(visible.get(lawful, 0)) == 2, "3 bandits and 2 defenders stand here", visible): return

	# No settlement: nothing to raid.
	var quiet: Dictionary = BanditDay.run(controller, 3)
	if not _check(not quiet.actions.any(func(a: Dictionary) -> bool: return str(a.action) == "raid"), "without a settlement the band rests", quiet): return

	# A paid protection keeps the band away (saved before the stand-in settlement exists).
	var paid: Dictionary = Bandit.protection_answer(slot.control.faction_registry, band, site_id, 4, {"grain": 1}, now)
	if not _check(paid.ok and controller._commit_diplomacy(paid, "").ok, "the settlement has paid this band"): return
	lab.terrain.site["settlement"] = {"version": 1, "settlement_id": "raid_test_village", "center_id": "raid_test_center", "level": 2, "name": "測試村",
		"owner_faction": lawful, "offices": SiteOffices.default_offices("settlement", cadres[0], false), "fall_record": SiteSettlement.empty_fall_record()}
	var spared: Dictionary = BanditDay.run(controller, 5)
	if not _check(not spared.actions.any(func(a: Dictionary) -> bool: return str(a.action) == "raid"), "a protected settlement is not raided", spared): return

	# The protection lapses (day 40): the band raids.
	var notices_before: int = lab.terrain.site.get("notices", []).size()
	var raided: Dictionary = BanditDay.run(controller, 40)
	var row: Dictionary = {}
	for action: Dictionary in raided.actions:
		if int(action.band) == band: row = action
	if not _check(str(row.get("action", "")) == "raid" and row.ok and row.orders.size() == 1 and int(row.orders[0].team) == team_id, "the band raids: its team gets an attack order", raided): return
	for order: Dictionary in row.orders:
		var team: Dictionary = lab.crowd_site._team_by_id(int(order.team))
		var state: Dictionary = lab.crowd_site.formation_state(int(team.formation))
		if not _check(int(_team_of(lab, int(order.target)).faction) == lawful and int(state.get("order", -1)) == NATIVE_ATTACK, "team %d attacks a defender of 乙國" % int(order.team), [order, state.get("order")]): return
	var noticed := false
	for notice: Variant in lab.terrain.site.get("notices", []).slice(notices_before):
		if str(notice).contains("劫掠本地聚落"): noticed = true
	if not _check(noticed, "a notice tells of the raid"): return
	lab.terrain.site.erase("settlement")
	_finished = true
	print("SITE_BANDIT_RAID_PASS: ", checks, " checks; a band raids its Site's settlement when strong enough and unpaid")
	quit(0)
