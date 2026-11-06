extends SceneTree
## Trade T1-a (reports/trade-plan.md TR-10, TR-11, TR-12, TR-14, TR-1B, TR-1C as decided 2026-11-06 "A"). In a new world
## the player (a crowd person) trades face to face with one of his cadres (a crowd NPC). Checks:
## - a crowd person is a legal trade endpoint in peace;
## - TR-11: an NPC with 2 grain refuses to give 1 (food floor), nothing changes, and the round costs one concession;
## - TR-14: 4 wood for 3 grain is countered deterministically (the NPC gives 2), and the same offer gets the same counter;
## - TR-10: 1 iron for 2 grain is accepted; the delivery job makes both busy, and on completion both cargos change once;
## - TR-12: a holder version change during delivery cancels it with nothing moved;
## - the open offer, job and concessions validate as a saved trade snapshot.
## Output: SITE_TRADE_T1A_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Trade = preload("res://scripts/terrain_lab/site_trade.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_TRADE_T1A_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_TRADE_T1A OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _set_cargo(person: Dictionary, values: Dictionary) -> void:
	var cargo: Dictionary = person.cargo
	cargo.clear()
	for key: String in values: cargo[key] = int(values[key])

func _wait_trade(controller: SiteController, identity: int) -> bool:
	for _frame: int in range(1200):
		await process_frame
		if _finished: return false
		if not controller.person_actions.is_busy(identity): return true
	return false

func _run() -> void:
	var requested: bool = RegionEntry.request_new_world(START, {}, "交易測試世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "neutral"})
	if not _check(requested, "a new world is requested", RegionEntry.menu_message): return
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
	for _frame: int in range(240): await process_frame # the start team settles into its slots
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var player := int(lab.controlled_person_id())
	var npc := -1
	var me: Dictionary = actions._person(player)
	for person: Variant in lab.crowd_site._team_by_id(int(me.owner.team_id)).person_ids:
		var candidate := actions._person(int(person))
		if int(person) != player and npc < 0 and Vector2(candidate.cell).distance_to(Vector2(me.cell)) <= 2.0: npc = int(person)
	if not _check(npc > 0, "a cadre stands next to the player", me.cell): return
	var them: Dictionary = actions._person(npc)
	if not _check(SiteRuntime.trade_endpoint(lab.terrain, "person:%d" % npc).ok and lab.crowd_site.contains_person(npc), "a crowd person is a legal trade endpoint in peace", SiteRuntime.trade_endpoint(lab.terrain, "person:%d" % npc)): return

	var neutral := {"version": 1}
	for axis: String in preload("res://scripts/terrain_lab/person_personality.gd").AXES: neutral[axis] = 50
	them.body["personality"] = neutral # thrift 50: the first required margin is 10%
	# TR-11: the food floor.
	_set_cargo(me, {"iron": 2, "wood": 8})
	_set_cargo(them, {"grain": 2})
	var refused: Dictionary = controller.trade_propose(npc, {"iron": 1}, {"grain": 1})
	if not _check(refused.ok and refused.decision == "REJECT" and int(them.cargo.grain) == 2 and int(me.cargo.iron) == 2, "an NPC with 2 grain refuses to give 1 and nothing moves", refused): return
	if not _check(int(refused.concessions) == 1 and controller.trade_session.concessions(npc, player) == 1, "a failed round costs one concession today", refused): return

	# TR-14: a deterministic counter.
	_set_cargo(them, {"grain": 10})
	var countered: Dictionary = controller.trade_propose(npc, {"wood": 4}, {"grain": 3})
	if not _check(countered.ok and countered.decision == "COUNTER" and int(countered.npc_gives.resources.get("grain", 0)) == 2, "4 wood for 3 grain is countered with 2 grain", countered): return
	var again: Dictionary = controller.trade_propose(npc, {"wood": 4}, {"grain": 3})
	if not _check(again.ok and again.decision == "COUNTER" and again.npc_gives == countered.npc_gives and int(again.concessions) == 3, "the same offer gets the same counter; rounds keep counting", again): return

	# TR-10: accept and deliver.
	var accepted: Dictionary = controller.trade_propose(npc, {"iron": 1}, {"grain": 2})
	if not _check(accepted.ok and accepted.decision == "ACCEPT", "1 iron for 2 grain is accepted", accepted): return
	var versions := [int(me.holder.version), int(them.holder.version)]
	var started: Dictionary = controller.trade_accept(str(accepted.offer_id))
	if not _check(started.ok and actions.is_busy(player) and actions.is_busy(npc), "the delivery job makes both busy", started): return
	var saved_state: Dictionary = lab.terrain.site.duplicate(true)
	saved_state["trade"]["action_cursor"] = float(lab.fire_action_cursor)
	if not _check(Trade.validate_snapshot(saved_state, float(lab.fire_action_cursor), lab.terrain).ok, "the offer, job and concessions validate as a saved trade snapshot", Trade.validate_snapshot(saved_state, float(lab.fire_action_cursor), lab.terrain)): return
	if not _check(int(me.cargo.get("iron", 0)) == 2 and int(them.cargo.get("grain", 0)) == 10, "nothing moves before the delivery completes"): return
	if not _check(await _wait_trade(controller, player), "the delivery completes", lab.terrain.site.get("trade")): return
	if not _check(int(me.cargo.get("iron", 0)) == 1 and int(me.cargo.get("grain", 0)) == 2 and int(them.cargo.get("grain", 0)) == 8 and int(them.cargo.get("iron", 0)) == 1, "both cargos change once", [me.cargo, them.cargo, controller.trade_session.last_results]): return
	if not _check(int(me.holder.version) == versions[0] + 1 and int(them.holder.version) == versions[1] + 1, "each holder version rises by one", [me.holder.version, them.holder.version, versions]): return

	# TR-12: an interruption moves nothing.
	var second: Dictionary = controller.trade_propose(npc, {"iron": 1}, {"grain": 2})
	if not _check(second.ok and second.decision == "ACCEPT" and controller.trade_accept(str(second.offer_id)).ok, "a second trade starts"): return
	them.holder["version"] = int(them.holder.version) + 1
	if not _check(await _wait_trade(controller, player), "the changed holder ends the delivery"): return
	if not _check(int(me.cargo.get("iron", 0)) == 1 and int(them.cargo.get("grain", 0)) == 8, "a cancelled delivery moves nothing", [me.cargo, them.cargo]): return
	_finished = true
	print("SITE_TRADE_T1A_PASS: ", checks, " checks; crowd endpoint, floor refusal, counter, delivery, busy and cancel hold")
	quit(0)
