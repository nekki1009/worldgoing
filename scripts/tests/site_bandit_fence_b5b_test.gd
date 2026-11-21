extends SceneTree
## 土匪 B5b-1 銷贓 (reports/bandit-faction-spec.md §7.1, A 市集暗盤). A 落草 world opens (the player chiefs a band); a
## lawful faction 乙國 is founded and three cadres stand apart as its team; a stand-in settlement of 乙國 (never saved)
## gives the Site an owner. Checks:
## - a lawful person facing the band keeps the plain hostile refusal; a band member facing a soldier of 乙國 is refused;
## - a civilian of 乙國 refuses while an office holder or a soldier of 乙國 can see (WATCHED), and is admitted once none can;
## - goods: the band side gives no coin, the civilian pays food or coin only (FENCE_GOODS);
## - price: the civilian wants twice the value (Trade.accept price factor 2), and the best grain he pays for the same goods
##   drops to about half;
## - a fence deal at that price is accepted, delivered, the goods move, and the band's heat rises by 5 (queued during
##   the step, saved at rest);
## - a soldier coming into sight during a delivery cancels it with nothing moved and no heat;
## - the trade dialog names the deal 暗盤 and states the rules; a band's caravan is still refused at 乙國's market.
## Output: SITE_BANDIT_FENCE_B5B_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Caravan = preload("res://scripts/terrain_lab/site_caravan.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const Trade = preload("res://scripts/terrain_lab/site_trade.gd")
const TradeSession = preload("res://scripts/terrain_lab/site_trade_session.gd")
const Fence = preload("res://scripts/terrain_lab/site_bandit_fence.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_BANDIT_FENCE_B5B_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_BANDIT_FENCE_B5B OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _neutral(body: Dictionary) -> void:
	var packet := {"version": 1}
	for axis: String in preload("res://scripts/terrain_lab/person_personality.gd").AXES: packet[axis] = 50
	body["personality"] = packet

func _wait_idle(controller: SiteController, identity: int) -> bool:
	for _frame: int in range(1200):
		await process_frame
		if _finished: return false
		if not controller.person_actions.is_busy(identity): return true
	return false

func _role(lab: TerrainLab, identity: int, role: String) -> bool:
	var record: Dictionary = lab.crowd_site._records.get(identity, {})
	if str(record.get("military_role", "")) == role: return true
	var changed: Dictionary = lab.crowd_site.native_set_military_role(identity, role)
	if not changed.ok: printerr("role change refused: ", identity, " ", role, " ", changed)
	return changed.ok

## Orders `team_id` to a passable cell about six cells east (side 1) or west (side -1) of `centre`.
func _move_off(lab: TerrainLab, team_id: int, centre: Vector2i, side: int) -> bool:
	for distance: int in [6, 5, 7, 4, 8]:
		for dy: int in [0, 1, -1, 2, -2]:
			var goal := centre + Vector2i(side * distance, dy)
			if lab.crowd_site.issue_order(team_id, TerrainArmy.CombatOrder.MOVE, goal, -1, "test").ok: return true
	return false

## Waits until the merchant is the only one of `others` (乙國-to-be) within 2.5 cells of any other band member, stands within
## the trade reach of the chief, and nobody is busy. {ok, ...} with the last distances.
func _settle(lab: TerrainLab, actions: SitePersonActions, player: int, merchant: int, others: Array) -> Dictionary:
	var last := {}
	for _frame: int in range(1800):
		await process_frame
		if _finished: return {"ok": false}
		var me: Dictionary = actions._person(player, false)
		var band := int(me.faction)
		var them: Dictionary = actions._person(merchant, false)
		var pair := Vector2(me.cell).distance_to(Vector2(them.cell))
		var closest := 99.0
		for mine: Dictionary in lab.crowd_site.teams:
			if bool(mine.get("departed", false)) or int(mine.faction) != band: continue
			for own: Variant in mine.person_ids:
				if others.has(int(own)): continue
				for raw_other: Variant in others:
					var other := int(raw_other)
					if int(own) == player and other == merchant: continue
					var gap := Vector2(actions._person(int(own), false).cell).distance_to(Vector2(actions._person(other, false).cell))
					if gap < closest:
						closest = gap
						last["closest_pair"] = [int(own), other]
		last.merge({"pair": pair, "closest_other": closest, "me": me.cell, "merchant": them.cell}, true)
		if pair <= 2.0 and closest >= 2.5 and not actions.is_busy(player) and not actions.is_busy(merchant): return {"ok": true, "distances": last}
	return {"ok": false, "distances": last}

## The chief walks (held key, as the keyboard does) until he stands outside melee reach (1.15 cells) of the merchant but
## within the trade reach (2 cells). {ok, pair}.
func _step_apart(lab: TerrainLab, actions: SitePersonActions, player: int, merchant: int) -> Dictionary:
	var pair := 0.0
	for direction: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		lab._held_directions[KEY_F24] = direction
		lab._last_direction_key = KEY_F24
		for _frame: int in range(240):
			await process_frame
			pair = Vector2(actions._person(player, false).cell).distance_to(Vector2(actions._person(merchant, false).cell))
			if pair > 1.2: break
		lab._held_directions.erase(KEY_F24)
		for _frame: int in range(30): await process_frame
		pair = Vector2(actions._person(player, false).cell).distance_to(Vector2(actions._person(merchant, false).cell))
		if pair > 1.2 and pair <= 2.0: return {"ok": true, "pair": pair}
	return {"ok": false, "pair": pair}

## Fence sales recorded for `band` since `heat_before`: queued rises plus the saved ones.
func _sales(slot: RegionSaveSlot, controller: SiteController, band: int, heat_before: int) -> int:
	return int(controller.get_meta(&"fence_heat_due", {}).get(band, 0)) + (_heat(slot, band) - heat_before) / Bandit.HEAT_FENCE

func _heat(slot: RegionSaveSlot, band: int) -> int:
	return int(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).get("heat", 0))

## The most grain the civilian pays for `iron` at `factor` (his own haggling terms, no concession yet).
func _best_grain(trade: Variant, them: Dictionary, iron: int, factor: float, site: Dictionary) -> int:
	var terms: Dictionary = trade._npc_terms(them)
	for grain: int in range(int(them.cargo.get("grain", 0)), 0, -1):
		var answer: Dictionary = Trade.accept(TradeSession.goods({"iron": iron}), TradeSession.goods({"grain": grain}), terms.stock, terms.targets, float(terms.thrift), 0, site, {}, factor)
		if answer.ok and str(answer.decision) == "ACCEPT": return grain
	return 0

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "銷贓世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "bandit", "name": "老寨"}), "a 落草 world is requested", RegionEntry.menu_message): return
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
	var me: Dictionary = actions._person(player, false)
	var cadres: Array[int] = []
	for person: Variant in _team_of(lab, player).person_ids:
		if int(person) != player: cadres.append(int(person))
	# The nearest cadre becomes the civilian merchant, so the face-to-face reach holds.
	cadres.sort_custom(func(x: int, y: int) -> bool:
		var dx := Vector2(actions._person(x, false).cell).distance_to(Vector2(me.cell))
		var dy := Vector2(actions._person(y, false).cell).distance_to(Vector2(me.cell))
		return dx < dy or dx == dy and x < y)
	if not _check(cadres.size() >= 5 and RegionFactionQuery.is_bandit(slot.control.faction_registry, band), "the player chiefs a band with five cadres", cadres): return
	var prepared: Dictionary = slot.prepare_faction_creation(lab.terrain, int(slot.control.faction_registry.revision), [],
		{"name": "乙國", "kind": "npc", "leader_ref": JoinFaction._world_ref(controller, cadres[4]), "founded_at": float(slot.control.logical_game_seconds)})
	if not _check(prepared.ok and controller._commit_diplomacy(prepared, "").ok, "乙國 is saved", prepared): return
	var lawful := int(prepared.faction_id)
	var merchant := cadres[0]
	var soldier := cadres[1]
	var clerk := cadres[2]
	# Placing first, while everyone is still the band's: the merchant stays in the chief's team, face to face with him;
	# the clerk and the soldier form a team that moves a few cells east (in sight, out of melee reach) and the band's other
	# cadres form one that moves a few cells west. Only then do the three change to 乙國 where they stand (a formal
	# captain cannot leave alone, so members leave): hostile people within melee reach (native reach 1.15 cells) exchange
	# blows even under HOLD, which would end a delivery.
	var guards: Dictionary = lab.crowd_site.detach_to_new_team(clerk, band)
	if not _check(guards.ok and lab.crowd_site.join_team(soldier, int(guards.team_id), true).ok, "the clerk and the soldier form a team", guards): return
	var rest: Dictionary = lab.crowd_site.detach_to_new_team(cadres[3], band)
	if not _check(rest.ok, "the band's other cadres form a team", rest): return
	for index: int in range(4, cadres.size()):
		if not _check(lab.crowd_site.join_team(cadres[index], int(rest.team_id), true).ok, "cadre %d joins them" % cadres[index]): return
	for _frame: int in range(3): await process_frame
	var centre := Vector2i(me.cell)
	if not _check(_move_off(lab, int(guards.team_id), centre, 1), "the guards move a few cells east"): return
	if not _check(_move_off(lab, int(rest.team_id), centre, -1), "the band's other cadres move a few cells west"): return
	var settled: Dictionary = await _settle(lab, actions, player, merchant, [merchant, soldier, clerk])
	if not _check(bool(settled.ok), "only the merchant stands near the chief, the guards in sight", settled): return
	var watch: Dictionary = lab.crowd_site.detach_to_new_team(soldier, lawful)
	var joined: Dictionary = lab.crowd_site.join_team(clerk, int(watch.get("team_id", -1)), true) if watch.ok else watch
	var shop: Dictionary = lab.crowd_site.detach_to_new_team(merchant, lawful)
	if not _check(watch.ok and joined.ok and shop.ok, "the three change to 乙國 where they stand", [watch, joined, shop]): return
	var stepped: Dictionary = await _step_apart(lab, actions, player, merchant)
	if not _check(bool(stepped.ok), "the chief steps out of melee reach and stays face to face", stepped): return
	for _frame: int in range(3): await process_frame
	var soldier_role := str(lab.crowd_site._records.get(soldier, {}).get("military_role", "soldier"))
	# Roles go through the native setter (the save compares the native role with the person record).
	if not _check(soldier_role != "civilian" and _role(lab, merchant, "civilian") and _role(lab, clerk, "civilian"), "乙國 has two civilians and an armed guard", soldier_role): return
	var them: Dictionary = actions._person(merchant, false)
	var guard: Dictionary = actions._person(soldier, false)
	var official: Dictionary = actions._person(clerk, false)
	me = actions._person(player, false)
	_neutral(them.body)
	var data := lab.terrain
	data.site["settlement"] = {"version": 1, "settlement_id": "fence_village", "center_id": "c", "level": 2, "name": "暗盤村", "owner_faction": lawful,
		"offices": SiteOffices.default_offices("settlement", clerk, true), "fall_record": SiteSettlement.empty_fall_record()}
	me.cargo.clear()
	me.cargo["iron"] = 6 # a person carries little: keep room for the grain he receives
	me.cargo["coin"] = 1
	them.cargo.clear()
	them.cargo["grain"] = 14 # a person carries at most 20 units (SiteRuntime.CARRY_CAPACITY)
	them.cargo["tools"] = 2
	var trade: Variant = controller._trade()
	if not _check(trade.hostile(me, them) and Vector2(them.cell).distance_to(Vector2(me.cell)) <= TradeSession.REACH, "the band and 乙國 are hostile and the merchant stands face to face", [me.cell, them.cell]): return

	# Who may buy.
	# The admission rule itself (the soldier and the clerk may stand beyond the face-to-face reach).
	var lawful_side: Dictionary = Fence.admit(controller, them, me, player, "", "")
	if not _check(str(lawful_side.get("code", "")) == "HOSTILE" and str(lawful_side.message).ends_with(Fence.HOSTILE_TEXT), "a lawful person facing the band keeps the plain hostile refusal", lawful_side): return
	var to_soldier: Dictionary = Fence.admit(controller, me, guard, soldier, "", "")
	if not _check(str(to_soldier.get("code", "")) == "HOSTILE" and str(to_soldier.message).contains("平民") and Fence.civilian_refusal(controller, soldier, guard) == "NOT_CIVILIAN", "a soldier of 乙國 does not buy stolen goods", to_soldier): return
	var to_official: Dictionary = Fence.admit(controller, me, official, clerk, "", "")
	if not _check(str(to_official.get("code", "")) == "HOSTILE" and Fence.civilian_refusal(controller, clerk, official) == "OFFICIAL", "the settlement's office holder does not buy stolen goods", to_official): return
	var from_warehouse: Dictionary = Fence.admit(controller, me, them, merchant, "feature:w", "")
	if not _check(str(from_warehouse.get("code", "")) == "HOSTILE", "a settlement store never buys stolen goods", from_warehouse): return
	var seen: Dictionary = controller.trade_propose(merchant, {"iron": 1}, {"grain": 1})
	if not _check(str(seen.get("code", "")) == "WATCHED" and Fence.watched(controller, [me.cell, them.cell]), "the civilian refuses while the office holder and the soldier can see", seen): return
	data.site.settlement["offices"] = SiteOffices.default_offices("settlement", cadres[4], true) # the head is away from 乙國's team
	if not _check(Fence.watched(controller, [me.cell, them.cell]), "the soldier alone still watches"): return
	if not _check(_role(lab, soldier, "civilian"), "the soldier's role is set to civilian"): return
	if not _check(not Fence.watched(controller, [me.cell, them.cell]), "with no office holder or soldier of 乙國 in sight, nobody watches"): return

	# Goods.
	var with_coin: Dictionary = controller.trade_propose(merchant, {"iron": 1, "coin": 1}, {"grain": 1})
	if not _check(str(with_coin.get("code", "")) == "FENCE_GOODS", "the band side may not pay coin (sell only)", with_coin): return
	var for_tools: Dictionary = controller.trade_propose(merchant, {"iron": 1}, {"tools": 1})
	if not _check(str(for_tools.get("code", "")) == "FENCE_GOODS", "the civilian pays food or coin only", for_tools): return
	if not _check(int(me.cargo.iron) == 6 and int(them.cargo.grain) == 14, "refusals moved nothing"): return

	# Price.
	var factor_one: Dictionary = Trade.accept(TradeSession.goods({"iron": 4}), TradeSession.goods({"grain": 6}), them.cargo, {"food": 3.0}, 50.0, 0, data.site, {}, 1.0)
	var factor_two: Dictionary = Trade.accept(TradeSession.goods({"iron": 4}), TradeSession.goods({"grain": 6}), them.cargo, {"food": 3.0}, 50.0, 0, data.site, {}, 2.0)
	if not _check(factor_one.ok and factor_two.ok and is_equal_approx(float(factor_two.required_value), 2.0 * float(factor_one.required_value)), "the fence price factor doubles what the civilian must receive", [factor_one, factor_two]): return
	if not _check(not Trade.accept(TradeSession.goods({"iron": 4}), TradeSession.goods({"grain": 6}), them.cargo, {"food": 3.0}, 50.0, 0, data.site, {}, 0.5).ok, "a price factor below 1 is refused"): return
	var normal := _best_grain(trade, them, 2, 1.0, data.site)
	var fenced := _best_grain(trade, them, 2, 2.0, data.site)
	if not _check(fenced > 0 and fenced < normal and fenced * 2 <= normal + 2, "the civilian pays about half the grain for the same goods (%d vs %d)" % [fenced, normal], [fenced, normal]): return

	# A deal at the fence price.
	var heat_before := _heat(slot, band)
	var offer: Dictionary = controller.trade_propose(merchant, {"iron": 2}, {"grain": fenced})
	if not _check(offer.ok and str(offer.decision) == "ACCEPT" and bool(offer.get("fence", false)), "the civilian accepts the deal at the fence price", offer): return
	if not _check(controller.trade_accept(str(offer.offer_id)).ok, "the delivery starts"): return
	if not _check(await _wait_idle(controller, player), "the delivery completes"): return
	var done: Dictionary = controller.trade_session.last_results[0] if not controller.trade_session.last_results.is_empty() else {}
	if not _check(done.get("ok", false) and str(done.message) == "暗盤交易完成" and int(done.get("fence", -1)) == band, "the delivery commits as a fence deal", [done, controller.trade_session.last_results]): return
	if not _check(int(me.cargo.get("iron", 0)) == 4 and int(me.cargo.get("grain", 0)) == fenced and int(them.cargo.get("grain", 0)) == 14 - fenced and int(them.cargo.get("iron", 0)) == 2,
		"the goods moved", [me.cargo, them.cargo]): return
	# The stand-in settlement is never saved, so the heat stays queued here; it is saved at the end, once it is gone.
	if not _check(_sales(slot, controller, band, heat_before) == 1, "the sale's heat is recorded once", [controller.get_meta(&"fence_heat_due", {}), _heat(slot, band)]): return

	# A soldier comes into sight during the next delivery.
	var second: Dictionary = controller.trade_propose(merchant, {"iron": 1}, {"grain": 1})
	if not _check(second.ok and str(second.decision) == "ACCEPT" and controller.trade_accept(str(second.offer_id)).ok, "a second fence delivery starts", second): return
	if not _check(_role(lab, soldier, soldier_role), "the guard takes up his arms again"): return
	if not _check(await _wait_idle(controller, player), "the second delivery ends"): return
	var cancelled: Dictionary = controller.trade_session.last_results[0] if not controller.trade_session.last_results.is_empty() else {}
	if not _check(str(cancelled.get("code", "")) == "CANCELLED" and str(cancelled.message).contains("不敢收贓"), "a watching soldier cancels the delivery", cancelled): return
	if not _check(int(me.cargo.get("iron", 0)) == 4 and int(them.cargo.get("grain", 0)) == 14 - fenced and _sales(slot, controller, band, heat_before) == 1, "the cancelled delivery moved nothing and added no heat", [me.cargo, them.cargo]): return

	# The dialog and the market.
	if not _check(_role(lab, soldier, "civilian"), "the soldier's role is set to civilian"): return
	var opened: Dictionary = controller.open_trade_dialog(merchant)
	var dialog: Variant = opened.get("dialog")
	var hint: Variant = dialog.find_child("TradeFenceHint", true, false) if dialog is Node else null
	if not _check(opened.ok and dialog is AcceptDialog and str(dialog.title).begins_with("暗盤") and hint is Label and str(hint.text).contains("只賣不買"), "the trade dialog names the deal 暗盤 and states its rules"): return
	dialog.queue_free()
	data.site.settlement["trade_sources"] = {"w": {"revision": 1, "limits": {"wood": {"per_trade": 10, "total": 100}}, "used": {}}}
	var robbers := Caravan.sell_here(lab, controller, {"id": 1, "faction": band, "goods": {"grain": 5}}, player)
	data.site.erase("settlement")
	if not _check(str(robbers.get("code", "")) == "HOSTILE", "a band's caravan is still refused at 乙國's market", robbers): return
	for _frame: int in range(600):
		if not controller.has_meta(&"fence_heat_due"): break
		await process_frame
	if not _check(not controller.has_meta(&"fence_heat_due") and _heat(slot, band) == mini(heat_before + 5, RegionFactionQuery.BANDIT_HEAT_MAX), "the band's heat rises by 5, saved at rest (%d -> %d)" % [heat_before, _heat(slot, band)],
		[controller.get_meta(&"fence_heat_due", {}), Fence.flush(controller) if controller.has_meta(&"fence_heat_due") else {}]): return
	_finished = true
	print("SITE_BANDIT_FENCE_B5B_PASS: ", checks, " checks")
	quit(0)
