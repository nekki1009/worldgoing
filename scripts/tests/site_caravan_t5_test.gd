extends SceneTree
## 貿易 T5 slice 1: caravan rules and the mission ledger. A world opens (a founded faction; no settlement of its own).
## Checks:
## - goods_for: per bound resource at most its per-trade limit, what remains of its total and half the stock, within
##   the room; unbound resources never;
## - dispatch refuses plainly: no settlement trade sources; a player head; the world's 8-mission cap;
## - the Region ledger's optional caravans field: added missions validate with the Region registry, a malformed one is
##   refused, an older registry without the field still validates, removing the last mission drops the field;
## - evaluate leaves a mission alone while its captain is not on this Site.
## Output: SITE_CARAVAN_T5_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Caravan = preload("res://scripts/terrain_lab/site_caravan.gd")
const Caravans = preload("res://scripts/region_lab/region_caravans.gd")
const GameplayClock = preload("res://scripts/region_lab/region_gameplay_clock.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_CARAVAN_T5_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_CARAVAN_T5 OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _mission(n: int) -> Dictionary:
	return {"token": "caravan_t%d" % n, "faction": 1, "from_site": "a:0:%d" % n, "warehouse": "w", "to_site": "a:1:%d" % n,
		"captain_ref": RegionPeerage.world_person_ref("w1", 900 + n), "goods": {"grain": 10}, "phase": "out", "day": 3}

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "商隊世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
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
	var controller: SiteController = lab.site_controller
	var slot: RegionSaveSlot = controller.region_slot
	var player := int(lab.controlled_person_id())

	# goods_for over a stand-in settlement record (never saved).
	var data := lab.terrain
	data.site["settlement"] = {"version": 1, "settlement_id": "caravan_village", "center_id": "c", "level": 2, "name": "測試村", "owner_faction": 1,
		"offices": SiteOffices.default_offices("settlement", player, false), "fall_record": SiteSettlement.empty_fall_record(),
		"trade_sources": {"w": {"revision": 1, "limits": {"grain": {"per_trade": 30, "total": 100}, "salt": {"per_trade": 5, "total": 5}}, "used": {"salt": 5}}}}
	var goods := Caravan.goods_for(data, "w", {"grain": 200, "salt": 50, "wood": 90}, 100)
	if not _check(goods == {"grain": 30}, "per-trade limit; a used-up total and an unbound resource give nothing", goods): return
	if not _check(Caravan.goods_for(data, "w", {"grain": 40}, 100) == {"grain": 20} and Caravan.goods_for(data, "w", {"grain": 200}, 12) == {"grain": 12}, "half the stock; the room"): return
	if not _check(str(Caravan.dispatch(controller).get("reason", "")) == "no_npc_head", "a player head sends no caravan"): return
	data.site.settlement.erase("trade_sources")
	if not _check(str(Caravan.dispatch(controller).get("reason", "")) == "no_trade", "no trade sources: no caravan"): return
	data.site.erase("settlement")

	# The ledger.
	var ledger: Dictionary = slot.region_registry()
	var world := float(slot.control.logical_game_seconds)
	if not _check(GameplayClock.validate_registry(ledger, world).ok and not ledger.has("caravans"), "a registry without caravans validates"): return
	for n: int in range(Caravans.MAX_ACTIVE):
		if not _check(Caravans.add(ledger, _mission(n)).ok, "mission %d is added" % n): return
	if not _check(not Caravans.add(ledger, _mission(99)).ok and GameplayClock.validate_registry(ledger, world).ok, "the 9th is refused; eight validate"): return
	data.site["settlement"] = {"version": 1, "settlement_id": "caravan_village", "center_id": "c", "level": 2, "name": "測試村", "owner_faction": 1,
		"offices": SiteOffices.default_offices("settlement", player + 100000, false), "fall_record": SiteSettlement.empty_fall_record(),
		"trade_sources": {"w": {"revision": 1, "limits": {"grain": {"per_trade": 30, "total": 100}}, "used": {}}}}
	var full := Caravan.dispatch(controller)
	data.site.erase("settlement")
	if not _check(str(full.get("reason", "")) in ["full", "no_npc_head"], "with eight missions out no ninth caravan", full): return
	var broken: Dictionary = ledger.duplicate(true)
	broken.caravans.missions[0]["phase"] = "lost"
	if not _check(not GameplayClock.validate_registry(broken, world).ok, "a malformed mission is refused"): return
	var turned := Caravan.evaluate(slot, lab)
	if not _check(turned.turned.is_empty() and turned.home.is_empty() and Caravans.missions(ledger).size() == Caravans.MAX_ACTIVE, "captains not on this Site: nothing changes", turned): return
	for mission: Dictionary in Caravans.missions(ledger).duplicate(): Caravans.remove(ledger, int(mission.id))
	if not _check(not ledger.has("caravans") and GameplayClock.validate_registry(ledger, world).ok, "removing the last mission drops the field"): return
	_finished = true
	print("SITE_CARAVAN_T5_PASS: ", checks, " checks; caravan rules and ledger")
	quit(0)
