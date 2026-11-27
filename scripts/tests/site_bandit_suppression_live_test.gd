extends SceneTree
## 官方剿匪 stages 1–2 in a live world (Nekki 2026-11-22 B; site_bandit_suppression.gd). A small generated scenario world
## (6 settlements, 3 bands, 1 town) opens on its empty start Site with the player and five cadres. Checks:
## - three cadres stand as a team of the scenario's NPC faction 1 (official); SiteBanditSuppression.send sends it toward
##   band 101's lair: the expedition day and its home (this Site) are saved in the band's table first, the team leaves on
##   its captain's word (its journey is in the Region registry) and is gone from this Site, a notice is written; the
##   faction's next expedition is in cooldown;
## - the player's team stands with faction 1 (a faction 1 team beside a neutral one would fight); two more cadres stand as a
##   second team of faction 1 whose latest expedition's home is faction 1's second settlement Site: with no band person
##   here, go_home sends them home on the same word; the player's own team is never sent; this Site stands as band 102's
##   current lair with a hoard, so the team carries it (Nekki 2026-11-27 A): the goods are on its people, the hoard has
##   them no more, and a caravan mission (spoils, phase back) takes them to the home settlement's warehouse;
## - the world saves.
## Output: SITE_BANDIT_SUPPRESSION_LIVE_PASS on success; quit(1) on any failure or the deadline.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const Suppression = preload("res://scripts/terrain_lab/site_bandit_suppression.gd")
const Caravans = preload("res://scripts/region_lab/region_caravans.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(1500.0).timeout.connect(func() -> void: _fail("1500-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	push_error("SITE_BANDIT_SUPPRESSION_LIVE_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_BANDIT_SUPPRESSION_LIVE OK ", checks, ": ", message)
		return true
	return _fail(message, detail)

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _standing(lab: TerrainLab, team_id: int) -> bool:
	for team: Dictionary in lab.crowd_site.teams:
		if int(team.team_id) == team_id and not bool(team.get("departed", false)): return true
	return false

## A team of `faction` made of `people` (the first leads it), saved.
func _team(controller: SiteController, faction: int, people: Array) -> int:
	var lab: TerrainLab = controller.lab
	var apart: Dictionary = lab.crowd_site.detach_to_new_team(int(people[0]), faction)
	if not _ok(apart.ok, "#%d stands apart as faction %d" % [int(people[0]), faction], apart): return -1
	var team_id := int(apart.team_id)
	for person: Variant in people.slice(1):
		var joined: Dictionary = lab.crowd_site.join_team(int(person), team_id, true)
		if not _ok(joined.ok, "#%d joins faction %d's team" % [int(person), faction], joined): return -1
	var led: Dictionary = lab.crowd_site.hand_over_captain(team_id, int(people[0]))
	if not _ok(led.ok and int(controller.team_captain_of_team(team_id)) == int(people[0]), "#%d leads faction %d's team" % [int(people[0]), faction], led): return -1
	if not _ok(controller._commit_diplomacy({"ok": true, "registry": controller.region_slot.control.faction_registry}, "").ok, "faction %d's team is saved" % faction): return -1
	return team_id

func _run() -> void:
	var folder := "user://suppression_live_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _ok(DirAccess.make_dir_recursive_absolute(folder.path_join("demo_a")) == OK, "scratch folder"): return
	var natural := RegionData.new()
	if not _ok(bool(natural.load_manifest(RegionData.DEFAULT_MANIFEST).ok), "the Taiwan source loads"): return
	var built: Dictionary = Generator.generate(natural, folder.path_join("demo_a"), "demo_a.json", 6, 3, 1, 20261122)
	if not _ok(built.get("ok", false), "the generator builds a small world", built): return
	if not _ok(RegionEntry.request_new_world(built.start, {}, "剿匪", "", str(built.path)), "a new world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	var open_deadline := Time.get_ticks_msec() + 1200000 # by the clock: beside another run the birth takes more frames
	while Time.get_ticks_msec() < open_deadline:
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _ok(lab != null, "the world is born and opens"): return
	for _frame: int in range(5): await process_frame
	var controller: SiteController = lab.site_controller
	var slot: RegionSaveSlot = controller.region_slot
	var here := str(lab.terrain.site.id)
	var today := int(float(slot.control.logical_game_seconds) / Bandit.DAY)
	var player := int(lab.controlled_person_id())
	var cadres: Array = []
	for person: Variant in _team_of(lab, player).get("person_ids", []):
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _ok(cadres.size() >= 5, "the player has five cadres", cadres): return
	var registry: Dictionary = slot.control.faction_registry
	if not _ok(str(registry.entries.get("1", {}).get("kind", "")) == "npc" and str(registry.entries.get("2", {}).get("kind", "")) == "npc" and RegionFactionQuery.is_bandit(registry, 101), "factions 1 and 2 are NPC factions, 101 is a band"): return
	var lair := str(RegionFactionQuery.bandit_of(registry, 101).lair.site_id)
	# The player's team stands with faction 1 first: a team of faction 1 next to a neutral team is hostile and fights
	# (found with the native state S_FIGHT), and no fighting person can leave the Site.
	var relabeled: Dictionary = lab.relabel_team_faction(int(_team_of(lab, player).team_id), 1)
	if not _ok(relabeled.ok and controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "").ok, "the player's team stands with faction 1", relabeled): return

	# Stage 1: an expedition of faction 1 toward band 101's lair.
	var expedition := _team(controller, 1, cadres.slice(0, 3))
	if expedition < 0: return
	for _frame: int in range(300): await process_frame # the native seats the new captain on its next step; the team regroups and stands still
	# A freshly formed team may still be settling (the native exit gate): try again every 60 frames, up to 1800 frames.
	var sent: Dictionary = {}
	for attempt: int in range(31):
		sent = Suppression.send(controller, 1, {"band": 101, "team_id": expedition, "lair_site": lair}, today)
		if sent.ok or str(sent.get("code", "")) != "NOT_READY": break
		for _frame: int in range(60): await process_frame
	if not sent.ok:
		var states: Array = []
		for person: Variant in lab.crowd_site.native_roster(expedition).get("units", []):
			var pid := int(person.person_id)
			states.append({"id": pid, "state": lab.crowd_site.soldier_state(int(lab.crowd_site._index_by_id.get(pid, -1))) if lab.crowd_site._index_by_id.has(pid) else {}})
		print("SITE_BANDIT_SUPPRESSION_LIVE SEND_HEX ", str(sent.get("message", "")).to_utf8_buffer().hex_encode(), " STATES ", JSON.stringify(states).left(3000))
	if not _ok(sent.ok, "faction 1's team is sent toward band 101's lair", sent): return
	var pursued: Dictionary = RegionFactionQuery.bandit_of(slot.control.faction_registry, 101).get("pursued", {})
	if not _ok(pursued.get("1") == {"day": today, "home": here}, "the expedition day and its home are saved in the band's table", pursued): return
	if not _ok(slot.region_registry().parties.has(str(sent.sent.token)) and not _standing(lab, expedition), "the team is on its way (its journey is in the Region registry) and gone from this Site", sent): return
	if not _ok(lab.terrain.site.get("notices", []).has("官兵出發剿匪"), "a notice is written"): return
	var again := Suppression.choose(here, [{"team_id": 1, "size": 20}], [{"band": 101, "heat": 90, "lair_site": lair, "members": 1}], Suppression.last_expedition(slot.control.faction_registry, 1), today + 5)
	if not _ok(str(again.get("reason", "")) == "COOLDOWN", "faction 1's next expedition waits for its 30 days", again): return

	# Stage 2: another team of faction 1 here goes home to faction 1's second settlement, the home of its latest expedition.
	var home_site: Vector2i = built.settlements[1]
	var home := Grid.site_id(str(slot.pin.atlas_id), home_site)
	var returning := _team(controller, 1, cadres.slice(3, 5))
	if returning < 0: return
	for _frame: int in range(300): await process_frame # the native seats the new captain on its next step; the team regroups and stands still
	var marked: Dictionary = Bandit.pursued(slot.control.faction_registry, 102, 1, today + 1, home, float(slot.control.logical_game_seconds))
	if not _ok(marked.ok and controller._commit_diplomacy(marked, "").ok, "faction 1's latest expedition left from its second settlement %s" % home, marked): return
	# Nekki 2026-11-27 A: from the band's current lair the expedition carries its hoard home. Here stands as band 102's lair.
	var hoarded: Dictionary = Bandit._with_table(slot.control.faction_registry, 102, func(table: Dictionary) -> void:
		table["lair"] = {"site_id": here, "cell": [int(table.lair.cell[0]), int(table.lair.cell[1])]}
		table["hoard"] = {"grain": 30, "iron": 5}, float(slot.control.logical_game_seconds))
	if not _ok(hoarded.ok and controller._commit_diplomacy(hoarded, "").ok, "band 102's lair is here with 30 grain and 5 iron", hoarded): return
	var homeward: Dictionary = {}
	for attempt: int in range(31):
		homeward = Suppression.go_home(controller, today)
		if homeward.has("sent") or str(homeward.get("reason", "")) != "NOT_READY": break
		for _frame: int in range(60): await process_frame
	if not _ok(homeward.has("sent") and int(homeward.sent.faction) == 1 and int(homeward.sent.team) == returning and str(homeward.sent.home) == home, "the second team of faction 1 is sent home", homeward): return
	if not _ok(slot.region_registry().parties.has(str(homeward.sent.token)) and not _standing(lab, returning) and _standing(lab, int(_team_of(lab, player).team_id)), "it is on its way home; the player's own team stays", homeward): return
	var spoils: Dictionary = homeward.sent.get("spoils", {})
	var left: Dictionary = RegionFactionQuery.bandit_of(slot.control.faction_registry, 102).get("hoard", {})
	var taken_all := not spoils.is_empty()
	for item: String in ["grain", "iron"]: taken_all = taken_all and int(spoils.get(item, 0)) + int(left.get(item, 0)) == {"grain": 30, "iron": 5}[item]
	if not _ok(taken_all and int(spoils.get("grain", 0)) > 0, "it carries the band's hoard, food first (%s; the hoard keeps %s)" % [JSON.stringify(spoils), JSON.stringify(left)]): return
	var mission: Dictionary = {}
	for row: Dictionary in Caravans.missions(slot.region_registry()):
		if str(row.token) == str(homeward.sent.token): mission = row
	if not _ok(not mission.is_empty() and mission.get("spoils") == true and str(mission.phase) == "back" and str(mission.from_site) == home and not str(mission.warehouse).is_empty() and mission.goods == spoils,
		"a caravan mission takes it to the home warehouse", mission): return
	var none: Dictionary = Suppression.go_home(controller, today)
	if not _ok(str(none.get("reason", "")) == "NONE", "nobody else here has a home elsewhere", none): return

	var saved: Dictionary = controller.save_to(controller.save_path)
	if not _ok(saved.ok, "the world saves", saved): return
	_finished = true
	TerrainArmy.release_contact_source()
	await process_frame
	print("SITE_BANDIT_SUPPRESSION_LIVE_PASS: ", checks, " checks")
	quit(0)
