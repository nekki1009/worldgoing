extends SceneTree
## Idle release of bound cold Sites (2026-11-25, RegionSaveSlot.release_idle_cold_owner). A small generated scenario world
## (6 settlements, 3 bands, 1 town) opens on its empty start Site; a settlement and a lair are bound as cold owners with the
## world standing still, as an arrival does. Checks:
## - what keeps a bound Site: the active Site itself, combat, an open raid on it, a guest team standing there; none of them
##   once it is cleared;
## - it is not released before IDLE_RELEASE_SECONDS of no use, and released after, one a step; the published file is the
##   one of the released body (people, camp and warehouse stock);
## - its hourly evaluations are gone with it (nothing binds it again), its frames no longer cost anything;
## - bound again it is the same people and stock, and the world goes on with no step fault.
## Output: REGION_IDLE_RELEASE_PASS on success; quit(1) on any failure or the deadline.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Aftermath = preload("res://scripts/terrain_lab/site_bandit_aftermath.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")

var checks := 0
var _finished := false
var lab: TerrainLab
var slot: RegionSaveSlot

func _initialize() -> void:
	create_timer(2400.0).timeout.connect(func() -> void: _fail("2400-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	push_error("REGION_IDLE_RELEASE_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_IDLE_RELEASE OK ", checks, ": ", message)
		return true
	return _fail(message, detail)

## What a Site holds: its people, its owner's stock.
func _held(site_lab: TerrainLab) -> Dictionary:
	var owner := int(Settlement.record(site_lab.terrain).get("owner_faction", -1))
	var people: Array = site_lab.crowd_site._index_by_id.keys() if site_lab.crowd_site != null and site_lab.crowd_site.active else []
	people.sort()
	return {"people": people, "stock": Aftermath.stock_of(site_lab.terrain.site, owner)}

func _bind(id: String) -> Dictionary:
	lab.set_process(false) # the world stands still while a Site is caught up (a replay has one fixed target)
	var bound: Dictionary = {}
	var began := Time.get_ticks_msec()
	for attempt: int in range(6000):
		bound = lab._region_gameplay_owner_lab(id, "cold_exact")
		if bound.get("ok", false) or str(bound.get("code", "")) != "PENDING": break
		await process_frame
	lab.set_process(true)
	print("REGION_IDLE_RELEASE BIND %s ok=%s code=%s %d ms" % [id, str(bound.get("ok")), str(bound.get("code", "")), Time.get_ticks_msec() - began])
	return bound

func _frame() -> bool:
	await process_frame
	if _finished: return false
	lab._process(1.0 / 30.0)
	lab.site_controller.person_actions.settle_after_contacts()
	if not lab.site_controller._original_step_fault.is_empty(): return _fail("a step fault", lab.site_controller._original_step_fault)
	return true

func _run() -> void:
	var folder := "user://idle_release_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _ok(DirAccess.make_dir_recursive_absolute(folder.path_join("demo_a")) == OK, "scratch folder"): return
	var natural := RegionData.new()
	if not _ok(bool(natural.load_manifest(RegionData.DEFAULT_MANIFEST).ok), "the Taiwan source loads"): return
	var built: Dictionary = Generator.generate(natural, folder.path_join("demo_a"), "demo_a.json", 6, 3, 1, 20261122)
	if not _ok(built.get("ok", false), "the generator builds a small world", built): return
	if not _ok(RegionEntry.request_new_world(built.start, {}, "閒置釋放", "", str(built.path)), "a new world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var open_deadline := Time.get_ticks_msec() + 1200000
	while Time.get_ticks_msec() < open_deadline:
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _ok(lab != null, "the world is born and opens"): return
	for _warm: int in range(5): await process_frame
	slot = lab.site_controller.region_slot
	var here := str(lab.terrain.site.id)
	# The first settlement without a garrison and the first lair.
	var lairs := {}
	var registry: Dictionary = slot.control.faction_registry
	for key: Variant in registry.entries:
		var lair: Variant = RegionFactionQuery.bandit_of(registry, int(registry.entries[key].faction_id)).get("lair") if RegionFactionQuery.is_bandit(registry, int(registry.entries[key].faction_id)) else null
		if lair is Dictionary: lairs[str(lair.site_id)] = int(registry.entries[key].faction_id)
	var village := ""
	var lair_site := ""
	for site: Variant in slot._marker.sites:
		var parts: PackedStringArray = str(site).split(":")
		if parts.size() != 2: continue
		var id := "%s:%s:%s" % [str(slot.pin.atlas_id), parts[0], parts[1]]
		if id == here: continue
		if lairs.has(id):
			if lair_site.is_empty(): lair_site = id
			continue
		if not village.is_empty(): continue
		var loaded: Dictionary = slot._load_checked(slot.folder.path_join(str(slot._marker.sites[site].path)), Vector2i(int(parts[0]), int(parts[1])))
		if not loaded.ok or not Settlement.record(loaded.data).has("owner_faction"): continue
		var soldiers := 0
		for army: Variant in loaded.data.site.get("armies", []):
			if army is Dictionary: soldiers += army.get("units", []).size()
		if soldiers < 30: village = id
	if not _ok(not village.is_empty() and not lair_site.is_empty(), "a village %s and a lair %s" % [village, lair_site]): return
	# Every band lies low (heat 80, nobody attacked it): a bound lair's chief knows the village and would raid it at once.
	for key: Variant in slot.control.faction_registry.entries:
		var band := int(slot.control.faction_registry.entries[key].faction_id)
		if not RegionFactionQuery.is_bandit(slot.control.faction_registry, band): continue
		var hot: Dictionary = Bandit.set_heat(slot.control.faction_registry, band, 80, float(slot.control.logical_game_seconds))
		if not _ok(hot.ok and lab.site_controller._commit_diplomacy(hot, "").ok, "band %d lies low" % band, hot): return
	for id: String in [village, lair_site]:
		var bound: Dictionary = await _bind(id)
		if not _ok(bound.get("ok", false), "%s is bound as a cold owner" % id, bound): return
	var field: TerrainLab = slot._region_original_labs[village]
	var held := {village: _held(field), lair_site: _held(slot._region_original_labs[lair_site])}
	if not _ok(held[village].people.size() > 3 and held[lair_site].people.size() >= 3, "people stand there: %d and %d" % [held[village].people.size(), held[lair_site].people.size()]): return
	if not _ok(slot.region_registry().events.any(func(event: Dictionary) -> bool: return str(event.owner) == village and str(event.kind) == "evaluation" and str(event.status) == "pending"), "the bound village is evaluated hourly"): return

	# What keeps it.
	if not _ok(slot.idle_release_block(here) == "ACTIVE", "the active Site is never released"): return
	if not _ok(slot.idle_release_block("nowhere:1:2") == "NOT_BOUND", "an unknown Site is not bound"): return
	if not _ok(slot.idle_release_block(village) == "" and slot.idle_release_block(lair_site) == "", "nothing keeps the quiet village and the lair", [slot.idle_release_block(village), slot.idle_release_block(lair_site)]): return
	slot.set_meta(&"bandit_raids_open", {int(lairs[lair_site]): {"site_id": village, "day": 0}})
	if not _ok(slot.idle_release_block(village) == "RAID", "an open raid keeps the village"): return
	slot.remove_meta(&"bandit_raids_open")
	field.terrain.site["combat_left"] = 5.0
	if not _ok(slot.idle_release_block(village) == "COMBAT", "combat keeps the village"): return
	field.terrain.site["combat_left"] = 0.0
	var first_team: Dictionary = field.crowd_site.teams[0]
	var first_faction := int(first_team.faction)
	first_team["faction"] = int(lairs[lair_site])
	if not _ok(slot.idle_release_block(village) == "GUESTS", "a band's team standing there keeps the village"): return
	first_team["faction"] = first_faction
	if not _ok(slot.idle_release_block(village) == "", "and nothing again after that"): return

	# The world runs: nothing before the time, released after it.
	lab.simulation_speed = 16.0
	var started := float(slot.control.logical_game_seconds)
	var before_ms := Time.get_ticks_msec()
	var before_frames := 0
	var release_at := {}
	var longest := 0
	for frame: int in range(8000):
		var frame_began := Time.get_ticks_msec()
		if not await _frame(): return
		var hours := (float(slot.control.logical_game_seconds) - started) / 3600.0
		if slot._region_original_labs.size() == 2: before_frames += 1
		for id: String in [village, lair_site]:
			if not slot._region_original_labs.has(id) and not release_at.has(id):
				release_at[id] = hours
				longest = maxi(longest, Time.get_ticks_msec() - frame_began)
				print("REGION_IDLE_RELEASE RELEASED %s at %.2f hours, that frame took %d ms; frames before: %.1f ms each" % [id, hours, Time.get_ticks_msec() - frame_began, float(Time.get_ticks_msec() - before_ms) / maxf(1.0, float(before_frames))])
		if release_at.size() == 2: break
		if hours > 9.0: break
	if not _ok(release_at.size() == 2, "both were released", [release_at, lab.get_meta(&"idle_release_last", {}), slot.idle_release_block(village), slot.idle_release_block(lair_site)]): return
	for id: String in release_at:
		if not _ok(float(release_at[id]) >= 6.0 and float(release_at[id]) < 6.6, "%s was released after 6 hours of no use (%.2f)" % [id, float(release_at[id])]): return
	if not _ok(not slot.region_registry().events.any(func(event: Dictionary) -> bool: return str(event.owner) in [village, lair_site] and str(event.kind) == "evaluation" and str(event.status) == "pending"), "their evaluations ended"): return
	if not _ok(not slot._fire_cold_candidates.has(village) and not slot._fire_cold_candidates.has(lair_site), "no checkpoint candidate is left of them"): return

	# Nothing binds them again for hours, and the frames are cheap.
	var quiet_from := float(slot.control.logical_game_seconds)
	var quiet_ms := Time.get_ticks_msec()
	var quiet_frames := 0
	while float(slot.control.logical_game_seconds) - quiet_from < 3.0 * 3600.0:
		if not await _frame(): return
		quiet_frames += 1
		if quiet_frames > 4000: break
	print("REGION_IDLE_RELEASE QUIET %.1f ms a frame over %d frames" % [float(Time.get_ticks_msec() - quiet_ms) / float(maxi(1, quiet_frames)), quiet_frames])
	if not _ok(slot._region_original_labs.is_empty(), "nothing bound them again in three hours", slot._region_original_labs.keys()): return

	# Bound again: the same people, the stock of the published body or less (they ate), and the world goes on.
	for id: String in [village, lair_site]:
		var again: Dictionary = await _bind(id)
		if not _ok(again.get("ok", false), "%s is bound again" % id, again): return
		var now_held := _held(slot._region_original_labs[id])
		if not _ok(now_held.people == held[id].people, "%s has the same people" % id, [now_held.people.size(), held[id].people.size()]): return
		print("REGION_IDLE_RELEASE STOCK %s %s -> %s" % [id, JSON.stringify(held[id].stock), JSON.stringify(now_held.stock)])
		for item: String in now_held.stock:
			if not _ok(int(now_held.stock[item]) <= int(held[id].stock.get(item, 0)) + 60, "%s %s did not come from nowhere" % [id, item], [now_held.stock, held[id].stock]): return
	var on_from := float(slot.control.logical_game_seconds)
	for frame: int in range(1200):
		if not await _frame(): return
		if float(slot.control.logical_game_seconds) - on_from > 3600.0: break
	if not _ok(float(slot.control.logical_game_seconds) - on_from > 3600.0 and slot._region_original_labs.size() == 2, "an hour goes on with both bound again"): return
	TerrainArmy.release_contact_source()
	await process_frame
	_finished = true
	print("REGION_IDLE_RELEASE_PASS: ", checks, " checks")
	quit(0)
