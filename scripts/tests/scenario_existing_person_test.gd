extends SceneTree
## 選現成人物 v1 (Nekki 2026-11-27 「都依建議」, 第六節「1.開放 2.依建議 3.清單加地圖」). Births the shipped demo A package for
## a scenario person of one role (`-- --role=leader|head|chief|captain`, default leader; `--rename` gives him a new name)
## through the real boot path and checks:
## - the package's people: 15 faction leaders, 15 other settlement heads, 15 band chiefs, one captain per other team;
## - the request is born on his Site with no created player and no cadres; he is the controlled person, under his new name;
## - a head (leader or head) captains his own one-person team of his faction and still holds his house and his post;
##   a chief or captain still captains his scenario team;
## - a leader or chief leads his faction in the registry, and the NPC diplomacy and the formula raids skip it;
## - his family is named after his surname, world.json records the start, and the world saves and reads back.
## Prints SCENARIO_EXISTING_PASS; quit(1) on any failure or the deadline.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const ScenarioPeople = preload("res://scripts/main_menu/scenario_people.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const PACKAGE := "res://assets/scenarios/demo_a/demo_a.json"

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(900.0).timeout.connect(func() -> void: _fail("900-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	push_error("SCENARIO_EXISTING_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SCENARIO_EXISTING OK ", checks, ": ", message)
		return true
	return _fail(message, detail)

func _role() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--role="): return argument.get_slice("=", 1)
	return "leader"

func _run() -> void:
	var listed := ScenarioPeople.people(PACKAGE)
	if not _ok(listed.get("ok", false), "the package's people are read", listed): return
	var by_role := {}
	for row: Dictionary in listed.people: by_role[row.role] = int(by_role.get(row.role, 0)) + 1
	if not _ok(int(by_role.get("leader", 0)) == 15 and int(by_role.get("head", 0)) == 15 and int(by_role.get("chief", 0)) == 15 and int(by_role.get("captain", 0)) == 33,
		"15 leaders, 15 heads, 15 chiefs, 33 captains (30 militia, 3 garrisons)", by_role): return
	var names := {}
	for row: Dictionary in listed.people: names[str(row.name)] = true
	if not _ok(names.size() == listed.people.size(), "every listed name is unique"): return
	var role := _role()
	var person: Dictionary = {}
	for row: Dictionary in listed.people:
		if str(row.role) == role:
			person = row
			break
	if not _ok(not person.is_empty(), "a %s is listed" % role): return
	print("SCENARIO_EXISTING picked %s %s at %s (%d people)" % [str(person.name), str(person.title), str(person.site), int(person.people)])
	var new_name := ("新" + str(person.name)).left(24) if "--rename" in OS.get_cmdline_user_args() else str(person.name)
	# The menu refuses a mismatched request before any world exists.
	if not _ok(not RegionEntry.request_new_world(person.site + Vector2i(1, 0), {"name": new_name}, "選人測試", "", PACKAGE, {"mode": "neutral"}, {}, {}, [], {"name": str(person.name)}), "a request on another Site is refused"): return
	if not _ok(not RegionEntry.request_new_world(person.site, {"name": new_name}, "選人測試", "", PACKAGE, {"mode": "neutral"}, {}, {}, [], {"name": "沒有這個人"}), "an unknown person is refused"): return
	var record := {"free_points": false, "template": "", "scenario": {"id": "demo_a_kaiken", "version": 1}}
	if not _ok(RegionEntry.request_new_world(person.site, {"name": new_name}, "選人測試", "", PACKAGE, {"mode": "neutral"}, {"surname": new_name.left(1)}, record, [], {"name": str(person.name)}), "the request is accepted", RegionEntry.menu_message): return
	var world_id := str(RegionEntry.pending.world_id)
	if not _ok(RegionEntry.pending.get("existing", {}).get("name", "") == str(person.name), "the request carries the person"): return
	var started := Time.get_ticks_msec()
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	var deadline := Time.get_ticks_msec() + 600000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
		if current_scene != null and current_scene.scene_file_path == RegionEntry.MAIN_MENU:
			var shown: Label = current_scene.find_child("MenuMessage", true, false) as Label
			_fail("back to the menu", shown.text if shown != null else RegionEntry.menu_message)
			return
	if not _ok(lab != null, "the world is born and opens (%.1f s)" % [float(Time.get_ticks_msec() - started) / 1000.0], RegionEntry.menu_message): return
	for _frame: int in range(5): await process_frame
	var controller: SiteController = lab.site_controller
	var slot: RegionSaveSlot = controller.region_slot
	var here: Variant = slot._coordinate(lab.terrain).get("site")
	if not _ok(here == person.site, "the world opens on his Site %s" % str(person.site), here): return
	var player := int(lab.controlled_person_id())
	var body: Dictionary = controller.person_actions._person(player, false)
	var shown := str(body.get("body", {}).get("name", "")) if body.get("body") is Dictionary else ""
	if not _ok(player > 0 and shown == new_name, "he is the controlled person, named %s" % new_name, [player, shown]): return
	# No created player, no cadres: no team of the neutral faction is on his Site.
	var team: Dictionary = {}
	for crowd_team: Dictionary in lab.crowd_site.teams:
		if bool(crowd_team.get("departed", false)): continue
		if not _ok(int(crowd_team.get("faction", -1)) != RegionFactionQuery.NEUTRAL_FACTION_ID, "no neutral start team on the Site", crowd_team): return
		if crowd_team.get("person_ids", []).has(player): team = crowd_team
	if not _ok(not team.is_empty() and int(team.faction) == int(person.faction_id), "his team is of his faction %d" % int(person.faction_id), team): return
	if not _ok(controller.team_captain_of_team(int(team.team_id)) == player, "he captains his team"): return
	if role in ["leader", "head"]:
		if not _ok(team.get("person_ids", []).size() == 1, "a head captains his own one-person team", team): return
		var housing: Dictionary = lab.terrain.site.get("housing", {})
		if not _ok(housing.has(str(player)), "he keeps his house"): return
		var head := int(SiteOffices.head_position(lab.terrain.site.get("settlement", {}).get("offices", {})).get("holder", -1))
		if not _ok(head == player, "he keeps the settlement head post", head): return
	else:
		if not _ok(team.get("person_ids", []).size() == int(person.people), "his scenario team is whole (%d)" % int(person.people), team): return
	var registry: Dictionary = slot.control.faction_registry
	var entry: Dictionary = registry.entries.get(str(int(person.faction_id)), {})
	var player_ref: Dictionary = JoinFaction._world_ref(controller, player)
	var leads := RegionPeerage.same_ref(entry.get("leader_ref"), player_ref)
	if role in ["leader", "chief"]:
		if not _ok(leads, "he leads his faction", entry.get("leader_ref")): return
		if role == "leader":
			if not _ok(controller.player_led_faction() == int(person.faction_id), "the NPC diplomacy and the official suppression skip his faction (player-led %d)" % controller.player_led_faction()): return
	else:
		if not _ok(not leads, "he does not lead the faction"): return
	var family: Dictionary = lab.terrain.site.get("family", {})
	if not _ok(str(family.get("name", "")) == new_name.left(1) + "家", "his family is %s家" % new_name.left(1), family.get("name", "")): return
	var meta := RegionEntry.read_world(world_id)
	if not _ok(str(meta.get("start", {}).get("existing", {}).get("name", "")) == str(person.name), "world.json records whom he took over", meta.get("start", {})): return
	var saved: Dictionary = controller.save_to(controller.save_path)
	if not _ok(saved.get("ok", false), "the world saves", saved): return
	var reread: Dictionary = slot._load_checked(slot.site_path(person.site), person.site)
	if not _ok(reread.get("ok", false) and int(reread.data.site.get("controlled_person_id", -1)) == player, "his Site reads back with him in control", reread.get("code", "")): return
	_finished = true
	TerrainArmy.release_contact_source()
	await process_frame
	print("SCENARIO_EXISTING_PASS: %d checks (%s)" % [checks, role])
	quit(0)
