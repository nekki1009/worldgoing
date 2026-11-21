extends SceneTree
## 土匪 B4d-3c in a live world (bandit spec §5.1, §11): a band raids a settlement on another Site it knows of. A 落草
## world opens (the player chiefs a band of himself and five cadres, lair here); a cadre takes the chief's seat and leads
## three cadres in a team of his own (the player keeps his team with the last cadre). Checks:
## - knowing nothing of other Sites the band rests;
## - a receipt about a Site whose settlement is the band's own is no target;
## - with a strength receipt (RegionSiteStrength) about a neighbouring Site whose settlement belongs to another faction
##   and shows 2 of its people there, the chief's daily move is a far raid: the chief's team leaves (the player's team is never sent) for that Site on the
##   chief's word (its journey is in the Region registry), heat rises by 10, a notice is written.
## Output: SITE_BANDIT_FAR_RAID_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const BanditDay = preload("res://scripts/terrain_lab/site_bandit_day.gd")
const FarRaid = preload("res://scripts/terrain_lab/site_bandit_far_raid.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Strength = preload("res://scripts/region_lab/region_site_strength.gd")
const RegionAI = preload("res://scripts/region_lab/region_gameplay_ai.gd")
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
	printerr("SITE_BANDIT_FAR_RAID_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_BANDIT_FAR_RAID OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _receipt(chief: int, scope: String, object: String, owner: int, seen: int, now: float) -> Dictionary:
	return {"id": "test-far:%s:%d" % [object, owner], "source": "report", "observation_kind": Strength.KIND, "observer": chief, "receiver": chief,
		"observer_scope": object, "receiver_scope": scope, "object_scope": object, "object": object,
		"value": {"power": seen, "factions": {str(owner): seen}, "settlement_owner": owner}, "game_time": now, "expires_at": now + 7.0 * 86400.0, "confidence": 1.0}

func _run() -> void:
	var requested: bool = RegionEntry.request_new_world(START, {}, "遠劫世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "bandit", "name": "老寨"})
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
	var band := int(_team_of(lab, player).faction)
	var cadres: Array[int] = []
	for person: Variant in _team_of(lab, player).person_ids:
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _check(cadres.size() >= 5, "the player's band has five cadres", cadres): return
	var scope := str(lab.terrain.site.id)
	var now := float(slot.control.logical_game_seconds)
	var chief := cadres[0]
	# The chief leads three cadres in a team of his own; the player keeps his team with the last cadre (a band never
	# fights its own, and the player's team cannot be sent: it holds the player).
	var apart: Dictionary = lab.crowd_site.detach_to_new_team(chief, band)
	if not _check(apart.ok, "the chief stands apart in a team of the band", apart): return
	var team_id := int(apart.team_id)
	for person: int in cadres.slice(1, 4):
		if not _check(lab.crowd_site.join_team(person, team_id).ok, "#%d joins the chief" % person): return
	var succeeded: Dictionary = Bandit.succeed(slot.control.faction_registry, band, JoinFaction._world_ref(controller, chief), now)
	if not _check(succeeded.ok and controller._commit_diplomacy(succeeded, "").ok, "the cadre is the band's chief now", succeeded): return
	var raiding: Dictionary = Bandit._with_table(slot.control.faction_registry, band, func(table: Dictionary) -> void: table.raid_ai = true, now)
	if not _check(raiding.ok and controller._commit_diplomacy(raiding, "").ok, "the band's raid AI is on", raiding): return
	for _frame: int in range(10): await process_frame # the native seats the new captain on its next step

	var quiet: Dictionary = BanditDay.run(controller, 3)
	if not _check(not quiet.actions.any(func(a: Dictionary) -> bool: return str(a.action) == "raid"), "knowing nothing of other Sites the band rests", quiet): return

	var here: Dictionary = slot._coordinate(lab.terrain)
	var neighbour := ""
	var far_side := ""
	for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		var next: Vector2i = here.site + step
		var summary: Dictionary = slot.source.get_site_summary(next.x, next.y)
		if not summary.get("ok", false) or str(summary.get("status", "")) not in ["land", "mixed"]: continue
		if neighbour.is_empty(): neighbour = Grid.site_id(str(slot.pin.atlas_id), next)
		elif far_side.is_empty(): far_side = Grid.site_id(str(slot.pin.atlas_id), next)
	if not _check(not neighbour.is_empty() and not far_side.is_empty(), "this Site has two land neighbours", [neighbour, far_side]): return
	var other := band + 1000
	var registry: Dictionary = slot.region_registry()
	if not _check(RegionAI.observe(registry, _receipt(chief, scope, far_side, band, 2, now)).ok, "the chief knows a Site of his own band"): return
	var own_only: Array = FarRaid.targets(controller, band, chief)
	if not _check(own_only.is_empty(), "his own band's settlement is no target", own_only): return
	if not _check(RegionAI.observe(registry, _receipt(chief, scope, neighbour, other, 2, now)).ok, "the chief is told of a neighbouring settlement with two of its people"): return
	var known: Array = FarRaid.targets(controller, band, chief)
	if not _check(known.size() == 1 and str(known[0].site_id) == neighbour and is_equal_approx(float(known[0].strength), 2.0) and bool(known[0].far), "it is a far raid target", known): return

	# The band settles after the hand-over (a departing member must stand still with no action in progress).
	for _frame: int in range(900):
		var ready := true
		for person: Variant in _team_of(lab, chief).person_ids:
			var owner: Variant = lab.crowd_site.person_owner(int(person))
			if owner == null or not lab.crowd_site._split_exit_ready(owner, int(lab.crowd_site._index_by_id[int(person)])): ready = false
		if ready: break
		await process_frame
	if not _check(int(controller.visible_strength().get(band, 0)) >= 6, "the band counts six here"): return
	var heat_before := int(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).get("heat", 0))
	var notices_before: int = lab.terrain.site.get("notices", []).size()
	var raided: Dictionary = BanditDay.run(controller, 40)
	var row: Dictionary = {}
	for action: Dictionary in raided.actions:
		if int(action.band) == band: row = action
	if not _check(str(row.get("action", "")) == "raid" and row.ok and str(row.target) == neighbour and row.sent.size() == 1 and int(row.sent[0].team) == team_id, "the band's team leaves to raid it", [raided, lab.crowd_site.native_roster(team_id).get("units", []).map(func(u: Dictionary) -> Array:
		var who := int(u.person_id)
		var owner: Variant = lab.crowd_site.person_owner(who)
		var index := int(lab.crowd_site._index_by_id.get(who, -1))
		return [who, index, owner != null, owner != null and index >= 0 and lab.crowd_site._split_exit_ready(owner, index), lab.crowd_site.soldier_state(index).get("hp", -1) if index >= 0 else -1,
			lab.crowd_site.soldier_state(index).get("vx", 0) if index >= 0 else 0, lab.crowd_site.soldier_state(index).get("action", "") if index >= 0 else ""]), _team_of(lab, chief).get("person_ids", [])]): return
	var token := str(row.sent[0].token)
	if not _check(slot.region_registry().parties.has(token) and _team_of(lab, chief).is_empty(), "its journey is in the Region registry; the chief has left the Site", slot.region_registry().parties.keys()): return
	if not _check(int(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).get("heat", 0)) == Bandit.heat_after(heat_before, "raid") and row.heat_saved, "heat rises and is saved"): return
	var noticed := false
	for notice: Variant in lab.terrain.site.get("notices", []).slice(notices_before):
		if str(notice).contains("出寨劫掠"): noticed = true
	if not _check(noticed, "a notice tells of the raid"): return
	_finished = true
	print("SITE_BANDIT_FAR_RAID_PASS: ", checks, " checks; a band raids a settlement it knows on another Site")
	quit(0)
