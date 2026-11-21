extends SceneTree
## 土匪 BA-12 (bandit spec §15): the Region map shows a band's lair only where the player knows it. A 落草 world opens
## (the player's band has its lair here). Checks:
## - known_lairs lists the lair when its Site is among the visited Sites, with the band's name, and not otherwise;
## - an extinct band's lair is never listed;
## - opening the Region map from the Site puts the known lairs into the map view (the Site has a saved generation).
## Output: REGION_BANDIT_LAIR_MAP_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
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
	printerr("REGION_BANDIT_LAIR_MAP_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_BANDIT_LAIR_MAP OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "山寨地圖世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "bandit", "name": "老寨"}), "a 落草 world is requested", RegionEntry.menu_message): return
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
	var registry: Dictionary = slot.control.faction_registry
	var here: Vector2i = slot._coordinate(lab.terrain).site
	var known: Array = Bandit.known_lairs(registry, [here])
	if not _check(known.size() == 1 and known[0].site == here and str(known[0].name).begins_with("老寨"), "a lair on a visited Site is listed with the band's name", known): return
	if not _check(Bandit.known_lairs(registry, [here + Vector2i(5, 5)]).is_empty(), "a lair on an unvisited Site is not listed"): return
	var gone: Dictionary = registry.duplicate(true)
	for key: Variant in gone.entries: if RegionFactionQuery.is_bandit(gone, int(key)): gone.entries[key]["status"] = "extinct"
	if not _check(Bandit.known_lairs(gone, [here]).is_empty(), "an extinct band's lair is never listed"): return
	var world_id := str(slot.pin.world_instance_id)
	var slot_id := str(slot.pin.slot_id)
	if not _check(here in RegionEntry.visited_sites(world_id, slot_id), "this Site has a saved generation", RegionEntry.visited_sites(world_id, slot_id)): return
	var lairs: Array = Bandit.known_lairs(registry, RegionEntry.visited_sites(world_id, slot_id))
	if not _check(lairs.size() == 1 and lairs[0].site == here, "the map view gets the known lair", lairs): return
	_finished = true
	print("REGION_BANDIT_LAIR_MAP_PASS: ", checks, " checks; known lairs on the Region map")
	quit(0)
