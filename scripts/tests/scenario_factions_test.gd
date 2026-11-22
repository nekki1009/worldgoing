extends "res://scripts/tests/map_editor_undo_contract_test.gd"
## 示範劇本 step 1: an author package's scenario document names and types its factions in a new world. Built on the P5B
## author fixture (one Site: a house, a settlement centre of faction 1, two residents). Checks:
## - RegionData.author_scenario_valid refuses a bad document (neutral id, duplicate id, bandit fields on an npc faction, a
##   band without a lair, an unknown key), and the export refuses it with nothing written;
## - the export with a scenario writes it as the package's one "scenario" file; the loader reads it back unchanged;
## - the real boot settle (SiteController._settle_boot_request after open_fixed_world) gives faction 1 its name and kind
##   npc and makes faction 2 the band 黑石寨 (lair Site id, cell, heat, raid AI, hoard), hostile to the village;
## - step 2: the scenario teams are born armed and named (the band of three, the militia of two), and the band's chief is
##   its first team's captain; the world saves and reopens with the registry.
## Output: SCENARIO_FACTIONS_PASS on success; quit(1) on any failure or the deadline.
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const BaseFixture = preload("res://scripts/tests/map_editor_undo_contract_test.gd")

var checks := 0

func _check(value: bool, message: String) -> bool:
	if _failed: return false
	checks += 1
	if value:
		print("SCENARIO_FACTIONS OK ", checks, ": ", message)
		return true
	_failed = true
	push_error("SCENARIO_FACTIONS_FAIL: " + message)
	quit(1)
	return false

func _freeze(lab: TerrainLab) -> void:
	lab.set_process(false)
	lab.set_process_input(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true

func _run() -> void:
	create_timer(240.0).timeout.connect(func() -> void: push_error("SCENARIO_FACTIONS_TIMEOUT"); quit(1))
	folder = "user://scenario_factions_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _check(DirAccess.make_dir_recursive_absolute(folder) == OK, "fixture folder"): return
	if not _natural(): return
	BaseFixture.DraftFixtureSource.natural_path = str(natural_record.path)
	var editor: Variant = load("res://scripts/map_editor/map_editor.gd").new()
	editor.source = BaseFixture.DraftFixtureSource.new()
	root.add_child(editor)
	if not _check(not editor.draft.is_empty(), "actual editor draft"): return
	var at: Vector2i = Vector2i(int(editor.draft.site[0]), int(editor.draft.site[1]))
	var land: Dictionary = editor.draft.duplicate(true)
	land.format = 2
	land["terrain_static"] = editor.empty_terrain_static()
	for rectangle: Rect2i in [Rect2i(12, 12, 3, 3), Rect2i(20, 20, 5, 5)]:
		for y: int in range(rectangle.position.y, rectangle.end.y):
			for x: int in range(rectangle.position.x, rectangle.end.x): land.terrain_static.terrain[str(editor.terrain.index(Vector2i(x, y)))] = {"foundation": 100}
	land.revision = int(land.revision) + 1
	if not _check(editor._commit_work(land, "scenario fixture land"), "original terrain command"): return
	var house_cells: Dictionary = SiteRuntime.building_cells(editor.terrain, "house", Vector2i(12, 12), Vector2i(3, 3), {"owner_faction": 1, "variant": "standard"})
	var center_cells: Dictionary = SiteRuntime.building_cells(editor.terrain, "settlement_center", Vector2i(20, 20), Vector2i(5, 5), {"owner_faction": 1})
	var cells: Array[int] = []
	cells.assign(house_cells.cells)
	var house: Dictionary = editor.edit_building("place", "", "house", cells, house_cells.options)
	cells.assign(center_cells.cells)
	var center: Dictionary = editor.edit_building("place", "", "settlement_center", cells, center_cells.options)
	if not _check(house.ok and center.ok, "a house and a settlement centre of faction 1"): return
	editor._residents_text.text = JSON.stringify([{"name": "甲", "faction_id": 1, "house": house.feature}, {"name": "乙", "faction_id": 1, "house": house.feature}])
	editor.get_node("AuthorColumn").find_child("ApplyResidents", true, false).pressed.emit()
	if not _check(editor.draft.initial_state.get("residents", []).size() == 2, "two residents"): return
	var key: String = "%d:%d" % [at.x, at.y]
	var start: Dictionary = {"mode": "created_player", "site": [at.x, at.y], "cell": [49, 49]}

	# The scenario document.
	var band := {"id": 2, "name": "黑石寨", "kind": "bandit", "bandit": {"lair": {"site": [at.x, at.y], "cell": [80, 80]}, "heat": 20, "raid_ai": true, "hoard": {"iron": 12, "cloth": 30}}}
	var teams := [{"site": [at.x, at.y], "faction_id": 2, "cell": [80, 80], "members": [{"name": "黑虎", "role": "officer"}, {"name": "甲匪", "role": "soldier"}, {"name": "乙匪", "role": "soldier"}]},
		{"site": [at.x, at.y], "faction_id": 1, "cell": [30, 70], "members": [{"name": "鄉勇長", "role": "officer"}, {"name": "鄉勇甲", "role": "soldier"}]}]
	var scenario := {"format": 1, "factions": [{"id": 1, "name": "溪口莊", "kind": "npc"}, band], "teams": teams}
	if not _check(Data.author_scenario_valid(scenario), "the scenario document is valid"): return
	var bad: Array = []
	bad.append({"format": 1, "factions": [{"id": 255, "name": "中立", "kind": "npc"}]})
	bad.append({"format": 1, "factions": [{"id": 1, "name": "甲", "kind": "npc"}, {"id": 1, "name": "乙", "kind": "npc"}]})
	bad.append({"format": 1, "factions": [{"id": 1, "name": "甲", "kind": "npc", "bandit": band.bandit}]})
	bad.append({"format": 1, "factions": [{"id": 2, "name": "寨", "kind": "bandit", "bandit": {"heat": 0, "raid_ai": true, "hoard": {}}}]})
	bad.append({"format": 1, "factions": [], "start": {}})
	bad.append({"format": 1, "factions": [band]}) # a band without a team has no chief
	bad.append({"format": 1, "factions": [band], "teams": [{"site": [at.x, at.y], "faction_id": 2, "cell": [80, 80], "members": [{"name": "甲匪", "role": "soldier"}]}]}) # the captain must be an officer
	bad.append({"format": 1, "factions": [band], "teams": [{"site": [at.x, at.y], "faction_id": 9, "cell": [80, 80], "members": [{"name": "黑虎", "role": "officer"}]}]}) # an unknown faction
	var refused_all := true
	for document: Dictionary in bad: refused_all = refused_all and not Data.author_scenario_valid(document)
	if not _check(refused_all, "neutral or duplicate ids, a band table on an npc faction, a band without a lair or a team, a soldier captain, an unknown team faction and unknown keys are refused"): return
	var refused_export: Dictionary = Data.export_author_initial_package(folder, "bad.json", [{"path": natural_record.path, "id": "natural"}], "natural", "scenario_bad", 1, "壞劇本", "refused", start, {key: editor.draft.initial_state}, {key: editor.draft.terrain_static}, bad[0])
	if not _check(not refused_export.ok and str(refused_export.code) == "INVALID_AUTHOR_SCENARIO" and not FileAccess.file_exists(folder.path_join("bad.json")), "the export refuses a bad scenario with nothing written"): return
	var exported: Dictionary = Data.export_author_initial_package(folder, "author.json", [{"path": natural_record.path, "id": "natural"}], "natural", "scenario_a_fixture", 1, "劇本勢力", "step 1", start, {key: editor.draft.initial_state}, {key: editor.draft.terrain_static}, scenario)
	if not _check(exported.ok and int(exported.files) == 3, "the export writes static, initial and scenario files (" + str(exported) + ")"): return
	var source: RegionData = RegionData.new()
	var loaded: Dictionary = source.load_manifest(str(exported.path))
	if not _check(loaded.ok and source.author_scenario() == JSON.parse_string(JSON.stringify(scenario)), "the loader reads the scenario back unchanged"): return

	# The real boot settle.
	if not _check(RegionEntry.request_new_world(at, {}, "劇本勢力世界", "", str(exported.path)), "a new world is requested from the package"): return
	var request: Dictionary = RegionEntry.take_pending()
	var lab: TerrainLab = (load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene).instantiate() as TerrainLab
	lab.restore_only = true
	lab.pause_when_unfocused = false
	lab.visible = false
	root.add_child(lab)
	var old: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 18373, {"size": Vector2i(32, 32)})
	SiteEnvironment.initialize(old, "scenario_old")
	lab.bind_terrain(old)
	lab.restore_only = false
	lab.crowd_startup_requested = TerrainLab.CrowdSiteScript.requested()
	lab.site_controller.save_root = folder.path_join("archives")
	_freeze(lab)
	lab.site_controller._boot_request = request
	var opened: Dictionary = lab.site_controller.open_fixed_world(str(request.manifest), str(request.world_id), str(request.slot_id), at, true)
	if not _check(opened.ok, "the world is born: " + str(opened)): return
	lab.site_controller._settle_boot_request(opened)
	_freeze(lab)
	var slot: RegionSaveSlot = lab.site_controller.region_slot
	var registry: Dictionary = slot.control.faction_registry
	var village: Dictionary = registry.entries.get("1", {})
	var bandits: Dictionary = RegionFactionQuery.bandit_of(registry, 2)
	if not _check(str(village.get("name", "")) == "溪口莊" and str(village.get("kind", "")) == "npc", "faction 1 is named 溪口莊, kind npc: " + str(village) + " | menu=" + RegionEntry.menu_message + " | source_scenario=" + str(slot.source.author_scenario() if slot.source != null else "no source") + " | direct=" + str(lab.site_controller.apply_scenario_factions(scenario.factions))): return
	if not _check(RegionFactionQuery.is_bandit(registry, 2) and str(registry.entries["2"].name) == "黑石寨" and str(bandits.lair.site_id) == RegionGrid.site_id(str(slot.pin.atlas_id), at) and bandits.lair.cell == [80, 80] and int(bandits.heat) == 20 and bool(bandits.raid_ai) and int(bandits.hoard.get("iron", 0)) == 12 and str(bandits.origin) == "scenario",
		"faction 2 is the band 黑石寨 with its lair, heat, raid AI and hoard: " + str(bandits)): return
	if not _check(RegionDiplomacy.hostile(registry, 2, 1, float(slot.control.logical_game_seconds)), "the band is hostile to the village"): return
	# Step 2: the teams are born armed, named, and the band's chief is its first team's captain.
	var band_people: Array = []
	var militia_people: Array = []
	for crowd_team: Dictionary in lab.crowd_site.teams:
		if int(crowd_team.get("faction", -1)) == 2: band_people.append_array(crowd_team.person_ids)
		if int(crowd_team.get("faction", -1)) == 1 and crowd_team.person_ids.size() == 2 and str(lab.crowd_site._records[int(crowd_team.person_ids[0])].get("military_role", "")) != "civilian": militia_people.append_array(crowd_team.person_ids)
	var band_names: Array = band_people.map(func(person: Variant) -> String: return str(lab.crowd_site._records[int(person)].get("name", "")))
	if not _check(band_people.size() == 3 and band_names.has("黑虎") and band_names.has("甲匪"), "the band's team of three is born with its names: " + str(band_names)): return
	if not _check(militia_people.size() == 2, "the village's militia of two is born armed: " + str(militia_people)): return
	var chief: int = RegionPeerage.world_person_id(registry.entries["2"].leader_ref)
	if not _check(chief > 0 and str(lab.crowd_site._records.get(chief, {}).get("name", "")) == "黑虎", "the band's chief is 黑虎, its team's captain"): return
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(saved.ok, "the world saves: " + str(saved)): return
	var reopened: Dictionary = lab.site_controller.open_fixed_world(str(exported.path), str(request.world_id), str(request.slot_id), at, false)
	_freeze(lab)
	var again: Dictionary = lab.site_controller.region_slot.control.faction_registry
	if not _check(reopened.ok and str(again.entries.get("1", {}).get("name", "")) == "溪口莊" and RegionFactionQuery.is_bandit(again, 2), "the reopened world keeps the scenario factions"): return
	TerrainArmy.release_contact_source()
	await process_frame
	print("SCENARIO_FACTIONS_PASS: ", checks, " checks")
	quit(0)
