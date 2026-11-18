extends SceneTree
## 土匪 B5 slice 1 (bandit spec §7): the route risk a caravan's head reckons with. A 落草 world opens (its registry holds
## one real band). Pure rules over that registry. Checks:
## - route_sites: the straight Site line, both ends included;
## - known_bands: a strength receipt showing people of the band marks that Site; people of an ordinary faction do not;
##   a lost caravan of the head's own faction marks the Site it was robbed at, another faction's loss does not;
## - risk: 15 per known band within 2 Sites of the line, none beyond; two Sites with the band count twice; a paid
##   protection of the home settlement (in force) counts nothing, an expired one counts again; capped at 100;
## - discounted: (100 - risk) percent of each resource, whole units, emptied resources dropped.
## Output: REGION_CARAVAN_RISK_B5_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Risk = preload("res://scripts/region_lab/region_caravan_risk.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("REGION_CARAVAN_RISK_B5_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CARAVAN_RISK_B5 OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _receipt(factions: Dictionary) -> Dictionary:
	return {"observation_kind": Risk.STRENGTH_KIND, "value": {"power": 3, "factions": factions, "settlement_owner": -1}}

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "風險世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "bandit", "name": "老寨"}), "a 落草 world is requested", RegionEntry.menu_message): return
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
	var slot: RegionSaveSlot = lab.site_controller.region_slot
	var registry: Dictionary = slot.control.faction_registry
	var now := float(slot.control.logical_game_seconds)
	var band := -1
	for key: Variant in registry.entries:
		if RegionFactionQuery.is_bandit(registry, int(key)): band = int(key)
	if not _check(band >= 0, "the world has a band", registry.entries.keys()): return

	var line := Risk.route_sites("a:0:5", "a:4:7")
	if not _check(line == [Vector2i(0, 5), Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 7), Vector2i(4, 7)] and Risk.route_sites("a:3:3", "a:3:3") == [Vector2i(3, 3)] and Risk.route_sites("bad", "a:1:1").is_empty(),
		"the straight Site line, both ends included", line): return

	var known := {"a:5:7": _receipt({str(band): 3, "1": 4}), "a:9:9": _receipt({"1": 6}), "a:5:1": {"observation_kind": "other", "value": {"factions": {str(band): 9}}}}
	var bands := Risk.known_bands(known, registry, [], 1)
	if not _check(bands == {"a:5:7": [band]}, "a receipt showing the band marks its Site; ordinary factions and other receipts do not", bands): return
	var lost := [{"faction": 1, "at_site": "a:2:2", "raided_by": band}, {"faction": 7, "at_site": "a:8:8", "raided_by": band}, {"faction": 1, "at_site": "a:6:6", "raided_by": -1}]
	var with_lost := Risk.known_bands(known, registry, lost, 1)
	if not _check(with_lost == {"a:5:7": [band], "a:2:2": [band]}, "a lost caravan of the head's own faction marks where it was robbed", with_lost): return

	if not _check(Risk.risk("a:0:5", "a:10:5", bands, registry, 0) == 15 and Risk.risk("a:0:5", "a:10:5", {"a:5:8": [band]}, registry, 0) == 0 and Risk.risk("a:0:5", "a:10:5", {}, registry, 0) == 0,
		"15 for a band within 2 Sites of the line, nothing beyond", [Risk.risk("a:0:5", "a:10:5", bands, registry, 0), Risk.risk("a:0:5", "a:10:5", {"a:5:8": [band]}, registry, 0)]): return
	if not _check(Risk.risk("a:0:5", "a:10:5", {"a:5:7": [band], "a:9:4": [band]}, registry, 0) == 30, "two Sites with the band count twice"): return
	var many := {}
	for x: int in range(8): many["a:%d:5" % x] = [band]
	if not _check(Risk.risk("a:0:5", "a:10:5", many, registry, 0) == 100, "capped at 100"): return
	var paid: Dictionary = Bandit.protection_answer(registry, band, "a:0:5", 3, {"grain": 5}, now)
	if not _check(paid.ok, "the home settlement pays the band", paid): return
	if not _check(Risk.risk("a:0:5", "a:10:5", bands, paid.registry, 10) == 0 and Risk.risk("a:0:5", "a:10:5", bands, paid.registry, 3 + Bandit.PROTECTION_DAYS + 1) == 15
		and Risk.risk("a:1:5", "a:10:5", bands, paid.registry, 10) == 15, "paid protection in force counts nothing; expired, or another settlement's, counts"): return

	if not _check(Risk.discounted({"grain": 20, "salt": 3, "wood": 1}, 15) == {"grain": 17, "salt": 2} and Risk.discounted({"grain": 20}, 0) == {"grain": 20} and Risk.discounted({"grain": 20}, 100).is_empty(),
		"(100 - risk) percent, whole units, emptied resources dropped", Risk.discounted({"grain": 20, "salt": 3, "wood": 1}, 15)): return
	_finished = true
	print("REGION_CARAVAN_RISK_B5_PASS: ", checks, " checks")
	quit(0)
