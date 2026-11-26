extends SceneTree
## A household that leaves its settlement (SiteResidentExodus, 平民 C4b) walks onto the first land neighbour, where usually
## nobody has ever been (2026-11-25). A small generated scenario world; a settlement with residents is bound as a cold
## owner and one of its households is made to leave. Checks: they leave as civilians, arrive as civilians in one neutral
## team on a Site of their own file, the world goes on an hour and saves.
## Output: REGION_EMIGRANT_ARRIVAL_PASS on success; quit(1) on any failure or the deadline.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Exodus = preload("res://scripts/terrain_lab/site_resident_exodus.gd")
const Households = preload("res://scripts/terrain_lab/site_households.gd")

var checks := 0
var _finished := false
var lab: TerrainLab
var slot: RegionSaveSlot

func _initialize() -> void:
	create_timer(1500.0).timeout.connect(func() -> void: _fail("1500-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	push_error("REGION_EMIGRANT_ARRIVAL_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_EMIGRANT_ARRIVAL OK ", checks, ": ", message)
		return true
	return _fail(message, detail)

func _bind(id: String) -> Dictionary:
	lab.set_process(false)
	var bound: Dictionary = {}
	for attempt: int in range(6000):
		bound = lab._region_gameplay_owner_lab(id, "cold_exact")
		if bound.get("ok", false) or str(bound.get("code", "")) != "PENDING": break
		await process_frame
	lab.set_process(true)
	return bound

func _frame() -> bool:
	await process_frame
	if _finished: return false
	lab._process(1.0 / 30.0)
	lab.site_controller.person_actions.settle_after_contacts()
	if not lab.site_controller._original_step_fault.is_empty(): return _fail("a step fault", lab.site_controller._original_step_fault)
	return true

func _team_of(field: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in field.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

## The armed people of `faction` who are not captains, sorted.
func _soldiers(field: TerrainLab, faction: int) -> Array[int]:
	var found: Array[int] = []
	for team: Dictionary in field.crowd_site.teams:
		if bool(team.get("departed", false)) or int(team.get("faction", -1)) != faction or team.get("person_ids", []).size() < 2: continue
		var captain := int(field.site_controller.team_captain_of_team(int(team.team_id)))
		for person: Variant in team.get("person_ids", []):
			if int(person) == captain: continue
			var body: Dictionary = field.site_controller.person_actions._person(int(person), false)
			if body.is_empty() or float(body.get("hp", 0.0)) <= 0.0 or SiteOffices.body_military_role(body.get("body")) == "civilian": continue
			found.append(int(person))
	found.sort()
	return found

func _band_saved(band: int, lair: String, origin: String) -> bool:
	var registry: Dictionary = slot.control.faction_registry
	if not RegionFactionQuery.is_bandit(registry, band): return false
	var table: Dictionary = RegionFactionQuery.bandit_of(registry, band)
	return str(table.get("origin", "")) == origin and table.get("lair") is Dictionary and str(table.lair.site_id) == lair

func _household(field: TerrainLab, cold: SiteController, head: int, round: int) -> bool:
	var leaving: Array = []
	var houses: Dictionary = Households.membership(field.terrain.site)
	print("REGION_EMIGRANT_ARRIVAL HOUSES ", JSON.stringify(houses).left(400))
	for house: Variant in houses:
		if houses[house].has(head): continue
		var able: Array = houses[house].filter(func(p: Variant) -> bool: return SiteOffices.body_military_role(cold.person_actions._person(int(p), false).get("body")) == "civilian")
		if able.size() >= 2 and leaving.is_empty(): leaving = able.slice(0, 2)
	if not _ok(leaving.size() == 2, "two residents of one household, both civilians", houses.keys()): return false
	lab.set_process(false)
	# By day the household works in the fields (2026-11-26): its job ends here, or the timetable sends them back to it, and
	# a body that came off its work drifts for about fifteen seconds before it stands (at midnight, when the game judges,
	# they are at home).
	for entry: Dictionary in field.terrain.site.get("households", {}).values(): entry.job["feature"] = ""
	for person: Variant in leaving: cold.work_team.cancel(int(person))
	var gone: Dictionary = {}
	# A farmer worked his field until now (2026-11-26 A: a batch lasts a working shift): the walk home from it is long.
	for attempt: int in range(9000):
		gone = Exodus.depart(cold, leaving, false)
		if gone.get("ok", false) or str(gone.get("code", "")) not in ["NOT_READY", "BUSY"]: break
		if not await _frame(): return false
	if not _ok(gone.get("ok", false), "they leave", gone): return false
	var token := str(gone.get("token", ""))
	var last: Array = []
	for attempt: int in range(900):
		if not token.is_empty(): break
		last = Exodus.dispatch_pending(cold)
		for row: Dictionary in last:
			if row.get("ok", false): token = str(row.token)
		if not cold.has_meta(Exodus.PENDING) and token.is_empty(): break
		if not await _frame(): return false
	if not _ok(not token.is_empty() and slot.region_registry().parties.has(token), "their head takes them onto the map", [gone, last]): return false
	var target: Array = []
	var plan: Dictionary = slot._region_npc_plan(token)
	if plan.get("ok", false): target = plan.plan.steps.back().site
	var key := "%d:%d" % [int(target[0]), int(target[1])] if target.size() == 2 else ""
	var visited: bool = slot._marker.sites.has(key)
	if not _ok(visited == (round > 0), "household %d goes to %s, which has %s" % [round, key, "people" if visited else "never been visited"]): return false
	lab.set_process(true)
	lab.simulation_speed = 4.0
	var phase := ""
	var from := float(slot.control.logical_game_seconds)
	for frame: int in range(6000):
		if not await _frame(): return false
		phase = str(slot.region_registry().parties.get(token, {}).get("phase", ""))
		if phase in ["entered", ""] or float(slot.control.logical_game_seconds) - from > 7200.0: break
	if not _ok(phase == "entered", "they arrived", [phase, float(slot.control.logical_game_seconds) - from]): return false
	var there: TerrainLab = slot._region_original_labs.get("%s:%s" % [str(slot.pin.atlas_id), key])
	if not _ok(is_instance_valid(there) and there.crowd_site != null and there.crowd_site.active, "the Site is bound, its people are a crowd", slot._region_original_labs.keys()): return false
	var mapping: Dictionary = slot.region_registry().parties[token].get("arrival_mapping", {}).get("maps", {}).get("person", {})
	var team: Dictionary = {}
	var roles: Array = []
	for person: Variant in leaving:
		var now_id := int(mapping.get(str(int(person)), int(person)))
		var stands := _team_of(there, now_id)
		if team.is_empty(): team = stands
		roles.append(SiteOffices.body_military_role(there.site_controller.person_actions._person(now_id, false).get("body")))
		if not _ok(not stands.is_empty() and int(stands.team_id) == int(team.team_id) and int(stands.faction) == RegionFactionQuery.NEUTRAL_FACTION_ID, "#%d stands in the household's neutral team" % now_id, stands): return false
	if not _ok(roles == ["civilian", "civilian"], "they are civilians still", roles): return false
	from = float(slot.control.logical_game_seconds)
	for frame: int in range(6000):
		if not await _frame(): return false
		if float(slot.control.logical_game_seconds) - from > 3600.0: break
	if not _ok(float(slot.control.logical_game_seconds) - from > 3600.0, "an hour goes on"): return false
	var saved: Dictionary = {}
	for attempt: int in range(300):
		saved = lab.site_controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "")
		if saved.get("ok", false): break
		if not await _frame(): return false
	if not _ok(saved.get("ok", false) and slot._marker.sites.has(key), "the world saves, the Site has a file of its own", saved): return false
	return true

func _run() -> void:
	var folder := "user://emigrant_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _ok(DirAccess.make_dir_recursive_absolute(folder.path_join("demo_a")) == OK, "scratch folder"): return
	var natural := RegionData.new()
	if not _ok(bool(natural.load_manifest(RegionData.DEFAULT_MANIFEST).ok), "the Taiwan source loads"): return
	var built: Dictionary = Generator.generate(natural, folder.path_join("demo_a"), "demo_a.json", 6, 3, 1, 20261122)
	if not _ok(built.get("ok", false), "the generator builds a small world", built): return
	if not _ok(RegionEntry.request_new_world(built.start, {}, "出走到站", "", str(built.path)), "a new world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var open_deadline := Time.get_ticks_msec() + 900000
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
	# Every band lies low: nothing else is bound or raided meanwhile.
	for key: Variant in slot.control.faction_registry.entries:
		var lying := int(slot.control.faction_registry.entries[key].faction_id)
		if not RegionFactionQuery.is_bandit(slot.control.faction_registry, lying): continue
		var hot: Dictionary = Bandit.set_heat(slot.control.faction_registry, lying, 80, float(slot.control.logical_game_seconds))
		if not _ok(hot.ok and lab.site_controller._commit_diplomacy(hot, "").ok, "band %d lies low" % lying, hot): return
	# The settlement with the most soldiers, but not a town's garrison.
	var village := ""
	var most := 0
	for site: Variant in slot._marker.sites:
		var parts: PackedStringArray = str(site).split(":")
		if parts.size() != 2 or "%s:%s:%s" % [str(slot.pin.atlas_id), parts[0], parts[1]] == here: continue
		var loaded: Dictionary = slot._load_checked(slot.folder.path_join(str(slot._marker.sites[site].path)), Vector2i(int(parts[0]), int(parts[1])))
		if not loaded.ok or not Settlement.record(loaded.data).has("owner_faction"): continue
		var armed := 0
		for army: Variant in loaded.data.site.get("armies", []):
			if not army is Dictionary: continue
			for unit: Variant in army.get("units", []):
				if unit is Dictionary and str(unit.get("military_role", "")) != "civilian": armed += 1
		if armed > most:
			most = armed
			village = "%s:%s:%s" % [str(slot.pin.atlas_id), parts[0], parts[1]]
	if not _ok(not village.is_empty() and most >= 8, "a settlement with soldiers: %s (%d)" % [village, most]): return
	var bound: Dictionary = await _bind(village)
	if not _ok(bound.get("ok", false), "it is bound as a cold owner", bound): return
	var field: TerrainLab = slot._region_original_labs[village]
	var cold: SiteController = field.site_controller
	var owner := int(field.terrain.site.settlement.owner_faction)
	var head := int(SiteOffices.head_position(field.terrain.site.settlement.offices).get("holder", 0))
	# The settlement's head does not leave, not even alone.
	var refused: Dictionary = Exodus.depart(cold, [head], false)
	if not _ok(head > 0 and not refused.get("ok", false) and str(refused.get("code", "")) == "NO_TARGET" and int(_team_of(field, head).get("faction", -1)) == owner, "the settlement's head #%d stays" % head, refused): return
	# The first household comes where nobody has ever been, the second where the first one stands.
	for round: int in range(2):
		if not await _household(field, cold, head, round): return
	TerrainArmy.release_contact_source()
	await process_frame
	_finished = true
	print("REGION_EMIGRANT_ARRIVAL_PASS: ", checks, " checks")
	quit(0)
