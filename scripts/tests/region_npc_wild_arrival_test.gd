extends SceneTree
## A team that arrives on a Site nobody has ever visited (2026-11-25): households that leave, and a band going to the lair
## it moved to, walk onto Sites that have no saved file; the arrival was refused UNSELECTED_REGION_SOURCE and the step
## fault stopped the world. A new 落草 world: two cadres walk to the neighbouring wild Site and later back. Checks:
## - the team is in the wild Site, as a bound cold owner with a saved file of its own, with no step fault;
## - the world saves and an hour goes on with both Sites running;
## - the same team walks home into the Site the player stands in; the Site it left stands empty and the world goes on.
## Output: REGION_NPC_WILD_ARRIVAL_PASS on success; quit(1) on any failure or the deadline.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const RegionTravelSite = preload("res://scripts/region_lab/region_travel_site.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")

var checks := 0
var _finished := false
var lab: TerrainLab
var slot: RegionSaveSlot

func _initialize() -> void:
	create_timer(840.0).timeout.connect(func() -> void: _fail("840-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	push_error("REGION_NPC_WILD_ARRIVAL_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_NPC_WILD_ARRIVAL OK ", checks, ": ", message)
		return true
	return _fail(message, detail)

func _frame() -> bool:
	await process_frame
	if _finished: return false
	lab._process(1.0 / 30.0)
	lab.site_controller.person_actions.settle_after_contacts()
	if not lab.site_controller._original_step_fault.is_empty(): return _fail("a step fault", lab.site_controller._original_step_fault)
	return true

func _team_of(where: TerrainLab, person: int) -> Dictionary:
	if where.crowd_site == null or not where.crowd_site.active: return {}
	for team: Dictionary in where.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _role(where: TerrainLab, person: int) -> String:
	return SiteOffices.body_military_role(where.site_controller.person_actions._person(person, false).get("body"))

## The whole team of `person` in `where` leaves for `target`; asked again while somebody is still busy.
func _send(where: TerrainLab, person: int, target: Vector2i, token: String) -> bool:
	var last: Dictionary = {}
	for attempt: int in range(900):
		var team := _team_of(where, person)
		if team.is_empty(): return _fail("#%d stands in no team" % person)
		var here: Dictionary = slot._coordinate(where.terrain)
		var component: int = RegionTravelSite.start_component(slot, here.site, where.crowd_site.combat_target(person).cell, where.terrain)
		if where._region_point_pending.is_empty() and not where._region_point_consuming and not where._region_point_dispatching:
			last = slot.prepare_npc_region_dispatch(where, "captain:band", int(team.team_id), target, component, [], token)
			if last.get("ok", false):
				var committed: Dictionary = slot.commit_npc_region_dispatch(last)
				return _ok(committed.get("ok", false), "%s left" % token, committed)
		if not await _frame(): return false
	return _fail("%s could not leave" % token, last)

func _wait_entered(token: String, seconds: float) -> bool:
	var from := float(slot.control.logical_game_seconds)
	var phase := ""
	var moved_at := -1.0
	var still := 0
	for frame: int in range(20000):
		if not await _frame(): return false
		if float(slot.control.logical_game_seconds) != moved_at:
			moved_at = float(slot.control.logical_game_seconds)
			still = 0
		still += 1
		if still == 200: # the world stands: why
			for event: Dictionary in slot.region_registry().events:
				if str(event.status) != "pending" or float(event.at) > moved_at + 60.0: continue
				print("REGION_NPC_WILD_ARRIVAL STANDS %s point %d consuming %s dispatching %s bound %s file %s" % [JSON.stringify(event).left(300), lab._region_point_pending.size(), lab._region_point_consuming, lab._region_point_dispatching,
					slot._region_original_labs.keys(), slot._marker.sites.keys()])
				var told: Dictionary = slot.prepare_npc_region_arrival(event) if str(event.kind) == "arrival" else {}
				told.erase("lab")
				print("REGION_NPC_WILD_ARRIVAL TOLD ok=%s code=%s message=%s pending=%s keys=%s replay %s" % [str(told.get("ok")), str(told.get("code")), str(told.get("message", "")), str(told.get("pending", "")), str(told.keys()), JSON.stringify(told.get("cold_replay", {})).left(300)])
			print("REGION_NPC_WILD_ARRIVAL CLOCK now %.4f point %d consuming %s dispatching %s operation %s crossing %s remaining %s" % [moved_at, lab._region_point_pending.size(), lab._region_point_consuming, lab._region_point_dispatching, lab.site_controller.region_operation_pending(), lab.site_controller.ground_crossing_blocks_clock(), lab._action_step_remaining])
			var stepped: Dictionary = lab._advance_original_shared_step(1.0 / 90.0)
			print("REGION_NPC_WILD_ARRIVAL STEP ", str(stepped).left(900))
			if not lab._region_point_pending.is_empty(): print("REGION_NPC_WILD_ARRIVAL POINT ", str(lab.consume_region_point()).left(900))
			return _fail("the world stands", moved_at - from)
		phase = str(slot.region_registry().parties.get(token, {}).get("phase", ""))
		if phase in ["entered", ""]: break
		if float(slot.control.logical_game_seconds) - from > seconds: break
	return _ok(phase in ["entered", ""], "%s has arrived" % token, [phase, float(slot.control.logical_game_seconds) - from, slot.region_registry().events.filter(func(event: Dictionary) -> bool: return str(event.status) == "pending")])

func _run() -> void:
	var start := Vector2i(1170, 13252)
	if not _ok(RegionEntry.request_new_world(start, {}, "荒野到站", "", RegionData.DEFAULT_MANIFEST, {"mode": "bandit", "name": "老寨"}), "a 落草 world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	for frame: int in range(3000):
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _ok(lab != null, "the new world opens", RegionEntry.menu_message): return
	for frame: int in range(5): await process_frame
	slot = lab.site_controller.region_slot
	var player := int(lab.controlled_person_id())
	var cadres: Array[int] = []
	for person: Variant in _team_of(lab, player).person_ids:
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _ok(cadres.size() >= 3, "the player's band has cadres", cadres): return
	var band := int(_team_of(lab, player).faction)
	var trip: Dictionary = lab.crowd_site.detach_to_new_team(cadres[0], band)
	if not _ok(trip.ok and lab.crowd_site.join_team(cadres[1], int(trip.team_id)).ok, "two cadres form a team of their own", trip): return
	# One of them is a civilian: he stays one wherever he arrives.
	if not _ok(lab.crowd_site.native_set_military_role(cadres[1], "civilian").ok and _role(lab, cadres[1]) == "civilian", "one of them is a civilian"): return
	for frame: int in range(10):
		if not await _frame(): return
	var here: Dictionary = slot._coordinate(lab.terrain)
	var wild := Vector2i.ZERO
	for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		var next: Vector2i = here.site + step
		var summary: Dictionary = slot.source.get_site_summary(next.x, next.y)
		if not summary.get("ok", false) or str(summary.get("status", "")) not in ["land", "mixed"]: continue
		if slot._marker.sites.has("%d:%d" % [next.x, next.y]): continue
		wild = next
		break
	if not _ok(wild != Vector2i.ZERO, "a neighbouring land Site nobody has visited: %s" % str(wild)): return
	var wild_id := Grid.site_id(str(slot.pin.atlas_id), wild)
	# As a band that moves its lair does (SiteBanditDay.move_lair): its people go to the new one and stay there.
	var moved: Dictionary = Bandit.move_lair(slot.control.faction_registry, band, wild_id, Vector2i(50, 50), float(slot.control.logical_game_seconds))
	if not _ok(moved.ok and lab.site_controller._commit_diplomacy(moved, "").ok, "the band's lair is there now", moved): return
	lab.simulation_speed = 4.0

	# There.
	if not await _send(lab, cadres[0], wild, "wild_out"): return
	if not await _wait_entered("wild_out", 3600.0): return
	var field: TerrainLab = slot._region_original_labs.get(wild_id)
	if not _ok(is_instance_valid(field) and field != lab, "the wild Site is bound as a cold owner", slot._region_original_labs.keys()): return
	var team := _team_of(field, cadres[0])
	if not _ok(not team.is_empty() and team.person_ids.has(cadres[1]) and int(team.faction) == band, "the two cadres stand there in one team", team): return
	if not _ok(_role(field, cadres[1]) == "civilian" and _role(field, cadres[0]) != "civilian", "the civilian came as one", [_role(field, cadres[0]), _role(field, cadres[1])]): return
	if not _ok(slot._marker.sites.has("%d:%d" % [wild.x, wild.y]) and FileAccess.file_exists(slot.folder.path_join(str(slot._marker.sites["%d:%d" % [wild.x, wild.y]].path))), "it has a saved file of its own"): return
	var from := float(slot.control.logical_game_seconds)
	for frame: int in range(6000):
		if not await _frame(): return
		if float(slot.control.logical_game_seconds) - from > 3600.0: break
	if not _ok(float(slot.control.logical_game_seconds) - from > 3600.0, "an hour goes on with both Sites running"): return
	var saved: Dictionary = {}
	for attempt: int in range(300):
		saved = lab.site_controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "")
		if saved.get("ok", false): break
		if not await _frame(): return
	if not _ok(saved.get("ok", false), "the world saves", saved): return

	# And back.
	field = slot._region_original_labs.get(wild_id)
	if not _ok(is_instance_valid(field), "the wild Site is still bound"): return
	if not await _send(field, cadres[0], here.site, "wild_home"): return
	if not await _wait_entered("wild_home", 3600.0): return
	team = _team_of(lab, cadres[0])
	if not _ok(not team.is_empty() and team.person_ids.has(cadres[1]), "the two cadres are home", team): return
	if not _ok(_role(lab, cadres[1]) == "civilian" and _role(lab, cadres[0]) != "civilian", "the civilian came home as one", [_role(lab, cadres[0]), _role(lab, cadres[1])]): return
	from = float(slot.control.logical_game_seconds)
	for frame: int in range(6000):
		if not await _frame(): return
		if float(slot.control.logical_game_seconds) - from > 3600.0: break
	if not _ok(float(slot.control.logical_game_seconds) - from > 3600.0, "an hour goes on"): return
	for attempt: int in range(300):
		saved = lab.site_controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "")
		if saved.get("ok", false): break
		if not await _frame(): return
	if not _ok(saved.get("ok", false), "the world saves again", saved): return
	TerrainArmy.release_contact_source()
	await process_frame
	_finished = true
	print("REGION_NPC_WILD_ARRIVAL_PASS: ", checks, " checks")
	quit(0)
