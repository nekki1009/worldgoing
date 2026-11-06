extends SceneTree
## Trade T1-a TR-13: save and reload during a delivery. The player (crowd) agrees 1 iron for 2 grain with an adjacent
## cadre and the delivery starts; the world is checkpointed at once and reopened. Checks:
## - the saved Site carries the offer and the job, and the reopened world still has them (both people busy);
## - the delivery completes after the reload and moves the goods exactly once.
## Output: SITE_TRADE_T1A_SAVE_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(400.0).timeout.connect(func() -> void: _fail("400-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_TRADE_T1A_SAVE_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_TRADE_T1A_SAVE OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _open() -> TerrainLab:
	change_scene_to_file(SITE)
	for _frame: int in range(900):
		await process_frame
		if _finished: return null
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			return scene
	return null

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "交易存讀測試", "", RegionData.DEFAULT_MANIFEST, {"mode": "neutral"}), "a new world is requested", RegionEntry.menu_message): return
	var lab: TerrainLab = await _open()
	if not _check(lab != null, "the new world opens", RegionEntry.menu_message): return
	for _frame: int in range(240): await process_frame
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var player := int(lab.controlled_person_id())
	var me: Dictionary = actions._person(player)
	var npc := -1
	for person: Variant in lab.crowd_site._team_by_id(int(me.owner.team_id)).person_ids:
		var candidate := actions._person(int(person))
		if int(person) != player and npc < 0 and Vector2(candidate.cell).distance_to(Vector2(me.cell)) <= 2.0: npc = int(person)
	if not _check(npc > 0, "a cadre stands next to the player"): return
	var them: Dictionary = actions._person(npc)
	me.cargo.clear()
	me.cargo["iron"] = 1
	them.cargo.clear()
	them.cargo["grain"] = 10
	var neutral := {"version": 1}
	for axis: String in preload("res://scripts/terrain_lab/person_personality.gd").AXES: neutral[axis] = 50
	them.body["personality"] = neutral
	var offer: Dictionary = controller.trade_propose(npc, {"iron": 1}, {"grain": 2})
	if not _check(offer.ok and offer.decision == "ACCEPT" and controller.trade_accept(str(offer.offer_id)).ok, "the trade is agreed and the delivery starts", offer): return
	var captured: Dictionary = controller.capture_region_checkpoint("region_checkpoint", true)
	if not _check(captured.ok, "the Site captures during the delivery", captured): return
	var saved: Dictionary = controller.region_slot.checkpoint_region_site(lab.terrain, captured.context, captured.owners, controller.region_slot.control.faction_registry, false, captured)
	if not _check(saved.ok, "the checkpoint with an open trade job saves", saved): return
	if not _check(RegionEntry.request_resume(), "the saved world can be reopened"): return
	lab = await _open()
	if not _check(lab != null, "the world reopens", RegionEntry.menu_message): return
	controller = lab.site_controller
	actions = controller.person_actions
	var trade: Dictionary = lab.terrain.site.get("trade", {})
	if not _check(trade.get("jobs", {}).size() == 1 and trade.get("offers", {}).size() == 1, "the reopened Site still has the offer and the job", trade): return
	controller._trade()
	if not _check(actions.is_busy(player) and actions.is_busy(npc), "both people are busy again after the reload"): return
	me = actions._person(player)
	them = actions._person(npc)
	if not _check(int(me.cargo.get("iron", 0)) == 1 and int(them.cargo.get("grain", 0)) == 10, "nothing moved before the reload completed it", [me.cargo, them.cargo]): return
	var done := false
	for _frame: int in range(1200):
		await process_frame
		if not actions.is_busy(player):
			done = true
			break
	if not _check(done, "the delivery completes after the reload", controller.trade_session.last_results): return
	me = actions._person(player)
	them = actions._person(npc)
	if not _check(int(me.cargo.get("iron", 0)) == 0 and int(me.cargo.get("grain", 0)) == 2 and int(them.cargo.get("grain", 0)) == 8 and int(them.cargo.get("iron", 0)) == 1, "the goods moved exactly once", [me.cargo, them.cargo, controller.trade_session.last_results]): return
	_finished = true
	print("SITE_TRADE_T1A_SAVE_PASS: ", checks, " checks; a delivery saved mid-way resumes and completes once")
	quit(0)
