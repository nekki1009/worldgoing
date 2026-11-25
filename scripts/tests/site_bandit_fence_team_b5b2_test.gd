extends SceneTree
## 土匪 B5b-2 NPC 銷贓隊 (reports/bandit-faction-spec.md §7.1 item 7). A 落草 world opens (the player chiefs a band of
## himself and five cadres, lair here); a cadre takes the chief's seat with one cadre beside him, two cadres form a team of
## their own, the player keeps his team with the last cadre. Checks:
## - the daily turn: with goods in the hoard and no food but no known settlement, nothing is sent; with a neighbouring
##   settlement of another faction too strong to raid, the chief sends the two-cadre team (never his own, never the
##   player's) with the hoard's goods: the hoard gives them up, a caravan mission marked `fence` is in the ledger, the team's
##   journey is in the Region registry and it has left the Site;
## - the sale at the destination (SiteCaravan.sell_here on a fence mission, here on the live Site with a stand-in
##   settlement): one civilian of the settlement buys at the fence price, paying grain from above his food reserve; with
##   an armed man of the settlement in sight nothing is sold (WATCHED);
## - home (SiteBanditFenceTeam.home): what the team carries of the goods and the grain goes into the hoard, heat rises by 5
##   for the sale, the mission ends; all in one saved commit.
## Output: SITE_BANDIT_FENCE_TEAM_B5B2_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const BanditDay = preload("res://scripts/terrain_lab/site_bandit_day.gd")
const FarRaid = preload("res://scripts/terrain_lab/site_bandit_far_raid.gd")
const FenceTeam = preload("res://scripts/terrain_lab/site_bandit_fence_team.gd")
const Fence = preload("res://scripts/terrain_lab/site_bandit_fence.gd")
const Caravan = preload("res://scripts/terrain_lab/site_caravan.gd")
const Caravans = preload("res://scripts/region_lab/region_caravans.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Strength = preload("res://scripts/region_lab/region_site_strength.gd")
const RegionAI = preload("res://scripts/region_lab/region_gameplay_ai.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var last_refusal := {}
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_BANDIT_FENCE_TEAM_B5B2_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_BANDIT_FENCE_TEAM_B5B2 OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _receipt(chief: int, scope: String, object: String, owner: int, seen: int, now: float) -> Dictionary:
	return {"id": "test-fence:%s:%d" % [object, owner], "source": "report", "observation_kind": Strength.KIND, "observer": chief, "receiver": chief,
		"observer_scope": object, "receiver_scope": scope, "object_scope": object, "object": object,
		"value": {"power": seen, "factions": {str(owner): seen}, "settlement_owner": owner}, "game_time": now, "expires_at": now + 7.0 * 86400.0, "confidence": 1.0}

func _row(day: Dictionary, band: int) -> Dictionary:
	for action: Dictionary in day.get("actions", []):
		if int(action.band) == band: return action
	return {}

## Orders `team_id` to a passable cell about six cells from `centre` (east first).
func _move_off(lab: TerrainLab, team_id: int, centre: Vector2i) -> bool:
	for distance: int in [6, 5, 7, 4, 8]:
		for side: int in [1, -1]:
			for dy: int in [0, 1, -1, 2, -2]:
				var ordered: Dictionary = lab.crowd_site.issue_order(team_id, TerrainArmy.CombatOrder.MOVE, centre + Vector2i(side * distance, dy), -1, "test")
				if ordered.ok: return true
				last_refusal = ordered
	return false

## Waits until every person of the band on the Site stands out of melee reach (1.5 cells) of each of `others` and both `seller` and
## `buyer` can trade (no fight on them). {ok, closest}.
func _calm(lab: TerrainLab, actions: SitePersonActions, band: int, others: Array, seller: int, buyer: int) -> Dictionary:
	var closest := 0.0
	for _frame: int in range(1800):
		await process_frame
		if _finished: return {"ok": false}
		closest = 99.0
		for team: Dictionary in lab.crowd_site.teams:
			if bool(team.get("departed", false)) or int(team.faction) != band: continue
			for own: Variant in team.person_ids:
				for other: Variant in others:
					closest = minf(closest, Vector2(actions._person(int(own), false).cell).distance_to(Vector2(actions._person(int(other), false).cell)))
		if closest >= 1.5 and Runtime.trade_endpoint(lab.terrain, "person:%d" % seller).get("ok", false) and Runtime.trade_endpoint(lab.terrain, "person:%d" % buyer).get("ok", false):
			return {"ok": true, "closest": closest}
	return {"ok": false, "closest": closest, "seller": Runtime.trade_endpoint(lab.terrain, "person:%d" % seller), "buyer": Runtime.trade_endpoint(lab.terrain, "person:%d" % buyer)}

## The player walks (held key, as the keyboard does) until he stands at least `gap` cells from each of `others`; the gap reached.
func _walk_apart(lab: TerrainLab, actions: SitePersonActions, player: int, others: Array, gap: float) -> float:
	var reached := 0.0
	for direction: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		lab._held_directions[KEY_F24] = direction
		lab._last_direction_key = KEY_F24
		for _frame: int in range(400):
			await process_frame
			reached = _gap(actions, player, others)
			if reached >= gap: break
		lab._held_directions.erase(KEY_F24)
		for _frame: int in range(20): await process_frame
		reached = _gap(actions, player, others)
		if reached >= gap: return reached
	return reached

func _gap(actions: SitePersonActions, player: int, others: Array) -> float:
	var nearest := 99.0
	for other: Variant in others: nearest = minf(nearest, Vector2(actions._person(player, false).cell).distance_to(Vector2(actions._person(int(other), false).cell)))
	return nearest

func _hoard(slot: RegionSaveSlot, band: int) -> Dictionary:
	return RegionFactionQuery.bandit_of(slot.control.faction_registry, band).get("hoard", {})

func _run() -> void:
	var requested: bool = RegionEntry.request_new_world(START, {}, "銷贓隊世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "bandit", "name": "老寨"})
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
	var actions: SitePersonActions = controller.person_actions
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
	var chief_team: Dictionary = lab.crowd_site.detach_to_new_team(chief, band)
	if not _check(chief_team.ok and lab.crowd_site.join_team(cadres[1], int(chief_team.team_id)).ok, "the chief stands apart with one cadre", chief_team): return
	var trip: Dictionary = lab.crowd_site.detach_to_new_team(cadres[2], band)
	if not _check(trip.ok and lab.crowd_site.join_team(cadres[3], int(trip.team_id)).ok, "two cadres form a team of their own", trip): return
	var trip_team := int(trip.team_id)
	var succeeded: Dictionary = Bandit.succeed(slot.control.faction_registry, band, JoinFaction._world_ref(controller, chief), now)
	if not _check(succeeded.ok and controller._commit_diplomacy(succeeded, "").ok, "the cadre is the band's chief now", succeeded): return
	var stocked: Dictionary = Bandit._with_table(slot.control.faction_registry, band, func(table: Dictionary) -> void:
		table.raid_ai = true
		table["hoard"] = {"iron": 10, "cloth": 20}, now)
	if not _check(stocked.ok and controller._commit_diplomacy(stocked, "").ok, "the band's raid AI is on and its hoard holds iron and cloth, no food", stocked): return
	for _frame: int in range(10): await process_frame # the native seats the new captains on its next step

	var quiet: Dictionary = BanditDay.run(controller, 3)
	if not _check(str(_row(quiet, band).get("action", "")) != "fence" and FenceTeam.missions(slot, band).is_empty(), "knowing no settlement nearby, nothing is sent", quiet): return

	var here: Dictionary = slot._coordinate(lab.terrain)
	var neighbour := ""
	for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		var next: Vector2i = here.site + step
		var summary: Dictionary = slot.source.get_site_summary(next.x, next.y)
		if not summary.get("ok", false) or str(summary.get("status", "")) not in ["land", "mixed"]: continue
		neighbour = Grid.site_id(str(slot.pin.atlas_id), next)
		break
	if not _check(not neighbour.is_empty(), "this Site has a land neighbour", neighbour): return
	var other := band + 1000
	if not _check(RegionAI.observe(slot.region_registry(), _receipt(chief, scope, neighbour, other, 40, now)).ok, "the chief is told of a neighbouring settlement with forty of its people"): return
	var wanted: Dictionary = FenceTeam.want(controller, band, chief)
	if not _check(str(wanted.get("site_id", "")) == neighbour, "with goods worth 75 grain and no food, the chief wants to fence them there", wanted): return

	for _frame: int in range(900):
		var ready := true
		for person: Variant in _team_of(lab, cadres[2]).person_ids:
			var owner: Variant = lab.crowd_site.person_owner(int(person))
			if owner == null or not lab.crowd_site._split_exit_ready(owner, int(lab.crowd_site._index_by_id[int(person)])): ready = false
		if ready: break
		await process_frame
	var sent: Dictionary = BanditDay.run(controller, 40)
	var row := _row(sent, band)
	if not _check(str(row.get("action", "")) == "fence" and row.ok and str(row.target) == neighbour and row.goods == {"iron": 10, "cloth": 20}, "the chief sends the goods to the fence", [sent, FenceTeam.last_result]): return
	var missions: Array = FenceTeam.missions(slot, band)
	if not _check(missions.size() == 1 and str(missions[0].phase) == "out" and str(missions[0].warehouse) == FenceTeam.WAREHOUSE and str(missions[0].to_site) == neighbour, "a fence caravan mission is in the ledger", missions): return
	if not _check(slot.region_registry().parties.has(str(row.token)) and _team_of(lab, cadres[2]).is_empty() and not _team_of(lab, chief).is_empty() and not _team_of(lab, player).is_empty(),
		"the two-cadre team left; the chief's and the player's stay", slot.region_registry().parties.keys()): return
	if not _check(_hoard(slot, band).is_empty(), "the hoard gave the goods up", _hoard(slot, band)): return
	if not _check(Caravans.validate(slot.region_registry().get("caravans", {})).ok, "the ledger with a fence mission validates"): return

	# The sale at a destination: the player's team stands in for the fence team, the last cadre for a civilian of 乙國.
	var prepared: Dictionary = slot.prepare_faction_creation(lab.terrain, int(slot.control.faction_registry.revision), [],
		{"name": "乙國", "kind": "npc", "leader_ref": JoinFaction._world_ref(controller, cadres[1]), "founded_at": float(slot.control.logical_game_seconds)})
	if not _check(prepared.ok and controller._commit_diplomacy(prepared, "").ok, "乙國 is saved", prepared): return
	var lawful := int(prepared.faction_id)
	var me: Dictionary = actions._person(player, false)
	me.cargo.clear()
	me.cargo["iron"] = 4
	var buyer_id := cadres[4]
	var lookout := cadres[1]
	# Placing first, while all are the band's: the chief's companion joins the player's team and the player walks it six
	# cells from the chief; then the last cadre and the companion change to 乙國 where they stand and the player steps three
	# cells off. Hostile people within melee reach exchange blows even under HOLD, and a person in a fight cannot trade.
	# The sale itself is abstracted as a caravan's (no face to face).
	if not _check(lab.crowd_site.join_team(lookout, int(_team_of(lab, player).team_id), true).ok, "the chief's companion joins the player's team"): return
	for _frame: int in range(3): await process_frame
	var off_chief: float = await _walk_apart(lab, actions, player, [chief], 6.0)
	if not _check(off_chief >= 6.0, "the player's team walks off the chief (%.1f cells)" % off_chief): return
	var shop: Dictionary = lab.crowd_site.detach_to_new_team(buyer_id, lawful)
	if not _check(shop.ok and lab.crowd_site.join_team(lookout, int(shop.team_id), true).ok, "the two change to 乙國 where they stand", shop): return
	var off_buyer: float = await _walk_apart(lab, actions, player, [buyer_id, lookout], 3.0)
	if not _check(off_buyer >= 3.0, "the player steps off 乙國's two (%.1f cells)" % off_buyer): return
	var calm: Dictionary = await _calm(lab, actions, band, [buyer_id, lookout], player, buyer_id)
	if not _check(bool(calm.ok), "nobody of the band stands within reach of 乙國 and both can trade", calm): return
	var civilian: Dictionary = lab.crowd_site.native_set_military_role(buyer_id, "civilian")
	var unarmed: Dictionary = lab.crowd_site.native_set_military_role(lookout, "civilian")
	if not _check(civilian.ok and unarmed.ok, "both become civilians of 乙國", [civilian, unarmed]): return
	actions._person(lookout, false).cargo.clear()
	var buyer: Dictionary = actions._person(buyer_id, false)
	buyer.cargo.clear()
	buyer.cargo["grain"] = 12
	lab.terrain.site["settlement"] = {"version": 1, "settlement_id": "fence_town", "center_id": "c", "level": 2, "name": "收贓鎮", "owner_faction": lawful,
		"offices": SiteOffices.default_offices("settlement", chief, true), "fall_record": SiteSettlement.empty_fall_record()}
	var mission := {"id": 999, "token": "test", "faction": band, "from_site": scope, "warehouse": FenceTeam.WAREHOUSE, "to_site": scope,
		"captain_ref": JoinFaction._world_ref(controller, player), "goods": {"iron": 4}, "phase": "out", "day": 0, "fence": true}
	var sold: Dictionary = Caravan.sell_here(lab, controller, mission, player)
	var got := int(sold.get("got", {}).get("grain", 0))
	if not _check(sold.get("ok", false) and int(sold.civilian) == buyer_id and got > 0 and got <= 11, "the civilian buys at the fence price, paying grain (%d)" % got, [sold, FenceTeam.last_result]): return
	if not _check(int(me.cargo.get("grain", 0)) == got and int(me.cargo.get("iron", 0)) + int(sold.gave.get("iron", 0)) == 4 and int(buyer.cargo.get("grain", 0)) == 12 - got,
		"the goods moved between the two", [me.cargo, buyer.cargo]): return
	me.cargo["iron"] = int(me.cargo.get("iron", 0)) + 4 # more goods to sell
	var armed: Dictionary = lab.crowd_site.native_set_military_role(lookout, "soldier")
	var seen: Dictionary = Caravan.sell_here(lab, controller, mission, player)
	if not _check(armed.ok and str(seen.get("code", "")) == "WATCHED" and int(me.cargo.get("grain", 0)) == got, "with an armed man of the settlement in sight nothing is sold", seen): return
	lab.terrain.site.erase("settlement") # the stand-in is never saved

	# Home: the player's team stands in for the returned trip.
	var heat_before := int(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).get("heat", 0))
	var back: Dictionary = Caravans.add(slot.region_registry(), {"token": "fence_back_test", "faction": band, "from_site": scope, "warehouse": FenceTeam.WAREHOUSE,
		"to_site": neighbour, "captain_ref": JoinFaction._world_ref(controller, player), "goods": {"iron": 4}, "phase": "back", "day": 0, "fence": true, "sold": {"grain": got}})
	if not _check(back.ok, "a returned fence trip is on the ledger", back): return
	var iron_left := int(me.cargo.get("iron", 0))
	# The band's daily turn runs between steps; called here directly it may meet a Region point still open
	# (REGION_EFFECTS_PENDING: nothing moves, the trip stays on the ledger), so it is asked again a frame later.
	var waited_from := float(slot.control.logical_game_seconds)
	var waited_ms := Time.get_ticks_msec()
	var returned: Dictionary = FenceTeam.home(controller, band)
	for _frame: int in range(3600):
		if not returned.refusals.is_empty() and str(returned.refusals[0].code) in ["REGION_EFFECTS_PENDING", "REGION_EFFECT_RUNNING"]:
			await process_frame
			returned = FenceTeam.home(controller, band)
		else: break
	if returned.home.is_empty(): # why: what is due and not settled, and whether the world moves at all
		print("SITE_BANDIT_FENCE_TEAM_B5B2 STUCK game %s -> %s ms %d point %d consuming %s dispatching %s paused %s fault %s" % [waited_from, float(slot.control.logical_game_seconds), Time.get_ticks_msec() - waited_ms,
			lab._region_point_pending.size(), lab._region_point_consuming, lab._region_point_dispatching, paused, str(controller._original_step_fault).left(200)])
		for event: Dictionary in slot.region_registry().events:
			if str(event.status) == "pending" and float(event.at) <= float(slot.control.logical_game_seconds) + 120.0: print("SITE_BANDIT_FENCE_TEAM_B5B2 DUE ", JSON.stringify(event).left(300))
	if not _check(returned.ok and returned.home.size() == 1 and returned.refusals.is_empty(), "the trip comes home", returned): return
	var hoard := _hoard(slot, band)
	if not _check(int(hoard.get("grain", 0)) == got and int(hoard.get("iron", 0)) == iron_left and int(me.cargo.get("grain", 0)) == 0 and int(me.cargo.get("iron", 0)) == 0,
		"what it carries of the goods and the grain goes into the hoard", [hoard, me.cargo]): return
	if not _check(int(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).get("heat", 0)) == Bandit.heat_after(heat_before, "fence"), "heat rises by 5 for the sale"): return
	var left_missions: Array = FenceTeam.missions(slot, band)
	if not _check(left_missions.size() == 1 and str(left_missions[0].phase) == "out", "the returned mission ended; the trip on the road remains", left_missions): return
	_finished = true
	print("SITE_BANDIT_FENCE_TEAM_B5B2_PASS: ", checks, " checks")
	quit(0)
