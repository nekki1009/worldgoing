extends SceneTree
## Trade T1-b (TR-17, with the diplomacy table): trade between factions. The player founds 甲國; a cadre leaves as king
## of 乙國 in the same Site. Checks:
## - while the two factions are hostile, a trade offer is refused (HOSTILE) and nothing moves;
## - after the NPC's truce letter is accepted, the same trade is accepted and delivered;
## - a war declared during a delivery cancels it with nothing moved.
## Output: REGION_TRADE_T1B_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
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
	printerr("REGION_TRADE_T1B_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_TRADE_T1B OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _neutral(lab: TerrainLab, person: int) -> void:
	var packet := {"version": 1}
	for axis: String in preload("res://scripts/terrain_lab/person_personality.gd").AXES: packet[axis] = 50
	lab.site_controller.person_actions._person(person).body["personality"] = packet

func _wait_idle(controller: SiteController, identity: int) -> bool:
	for _frame: int in range(1200):
		await process_frame
		if _finished: return false
		if not controller.person_actions.is_busy(identity): return true
	return false

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "跨勢力交易測試", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a new world with a founded faction is requested"): return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	for _frame: int in range(900):
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _check(lab != null, "the new world opens"): return
	for _frame: int in range(240): await process_frame
	var controller: SiteController = lab.site_controller
	var slot: RegionSaveSlot = controller.region_slot
	var actions: SitePersonActions = controller.person_actions
	var player := int(lab.controlled_person_id())
	var me: Dictionary = actions._person(player)
	var mine := controller.diplomacy_head_faction()
	var official := -1
	for person: Variant in lab.crowd_site._team_by_id(int(me.owner.team_id)).person_ids:
		var candidate := actions._person(int(person))
		if int(person) != player and official < 0 and Vector2(candidate.cell).distance_to(Vector2(me.cell)) <= 2.0: official = int(person)
	if not _check(mine >= 0 and official > 0, "the player heads 甲國 and a cadre stands next to him"): return
	var official_ref: Dictionary = JoinFaction._world_ref(controller, official)
	var prepared: Dictionary = slot.prepare_faction_creation(lab.terrain, int(slot.control.faction_registry.get("revision", 0)), [], {"name": "乙國", "kind": "npc", "leader_ref": official_ref, "founded_at": float(slot.control.logical_game_seconds)})
	if not _check(prepared.ok, "乙國 is prepared with the cadre as king", prepared): return
	var other := int(prepared.faction_id)
	if not _check(lab.crowd_site.detach_to_new_team(official, other).ok, "the cadre leaves as captain of 乙國's team"): return
	var captured: Dictionary = controller.capture_region_checkpoint("region_checkpoint", true)
	if not _check(captured.ok and slot.checkpoint_region_site(lab.terrain, captured.context, captured.owners, prepared.registry, false, captured).ok, "the new faction saves"): return
	_neutral(lab, official)
	var them: Dictionary = actions._person(official)
	me.cargo.clear()
	me.cargo["iron"] = 2
	them.cargo.clear()
	them.cargo["grain"] = 10

	var refused: Dictionary = controller.trade_propose(official, {"iron": 1}, {"grain": 2})
	if not _check(not refused.ok and refused.code == "HOSTILE" and int(them.cargo.grain) == 10, "hostile factions cannot trade", refused): return

	controller._npc_diplomacy_day = -1
	controller.npc_diplomacy_day()
	controller.settle_diplomacy()
	if not _check(controller.answer_oldest_letter(true).ok, "the player accepts 乙國's truce letter"): return
	controller.settle_diplomacy()
	if not _check(not RegionDiplomacy.hostile(slot.control.faction_registry, mine, other, float(slot.control.logical_game_seconds)), "the two factions are at truce"): return
	var offer: Dictionary = controller.trade_propose(official, {"iron": 1}, {"grain": 2})
	if not _check(offer.ok and offer.decision == "ACCEPT" and controller.trade_accept(str(offer.offer_id)).ok, "at truce the trade is accepted and the delivery starts", offer): return
	if not _check(await _wait_idle(controller, player), "the delivery completes"): return
	if not _check(int(me.cargo.get("iron", 0)) == 1 and int(them.cargo.get("grain", 0)) == 8, "the goods moved across factions", [me.cargo, them.cargo, controller.trade_session.last_results]): return

	var second: Dictionary = controller.trade_propose(official, {"iron": 1}, {"grain": 2})
	if not _check(second.ok and controller.trade_accept(str(second.offer_id)).ok, "a second delivery starts"): return
	if not _check(controller.declare_war_on(other).ok, "the player declares war during the delivery"): return
	if not _check(await _wait_idle(controller, player), "the war ends the delivery"): return
	if not _check(int(me.cargo.get("iron", 0)) == 1 and int(them.cargo.get("grain", 0)) == 8 and str(controller.trade_session.last_results[0].message).contains("敵對"), "the cancelled delivery moved nothing", [me.cargo, them.cargo, controller.trade_session.last_results]): return
	_finished = true
	print("REGION_TRADE_T1B_PASS: ", checks, " checks; hostile refusal, trade at truce, cancel on war")
	quit(0)
