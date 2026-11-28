extends SceneTree
## 選現成人物 v1 menu (Nekki 2026-11-27 「清單加地圖」): New Game → 選現成人物（劇本） → the scenario's people on a list beside
## its map → a pick by map click and by list → a new name and look (the character page shows the look only) → confirm (no
## start faction, team or scenario choice; the summary names whom he takes over) → Start → born as him.
## Prints MAIN_MENU_EXISTING_PASS; quit(1) on a failure, a script error or the deadline.
const MENU := "res://scenes/main_menu/MainMenu.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const ScenarioPeople = preload("res://scripts/main_menu/scenario_people.gd")
const PACKAGE := "res://assets/scenarios/demo_a/demo_a.json"

class MenuErrors extends Logger:
	var _mutex := Mutex.new()
	var _first := ""
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING: return
		_mutex.lock()
		if _first.is_empty(): _first = "%s:%d %s: %s %s" % [file, line, function, code, rationale]
		_mutex.unlock()
	func first_error() -> String:
		_mutex.lock()
		var result := _first
		_mutex.unlock()
		return result

var _errors := MenuErrors.new()
var _finished := false
var checks := 0

func _initialize() -> void:
	OS.add_logger(_errors)
	create_timer(600.0).timeout.connect(func() -> void: _fail("600-second deadline"))
	_run.call_deferred()

func _finalize() -> void:
	OS.remove_logger(_errors)

func _fail(reason: String) -> bool:
	if _finished: return false
	_finished = true
	push_error("MAIN_MENU_EXISTING_FAIL: " + reason)
	quit(1)
	return false

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	var error: String = _errors.first_error()
	if not error.is_empty(): return _fail("script/engine error: " + error)
	if condition:
		print("MAIN_MENU_EXISTING OK ", checks, ": ", message)
		return true
	return _fail("%s %s" % [message, str(detail)])

func _press(node_name: String) -> bool:
	var button := current_scene.find_child(node_name, true, false) as Button
	if not _ok(button != null and not button.disabled and button.is_visible_in_tree(), "button %s is there" % node_name): return false
	button.pressed.emit()
	return true

func _page(page: String) -> bool:
	var node := current_scene.find_child("Page_" + page, true, false) as Control
	return node != null and node.visible

func _shown(node_name: String) -> bool:
	var node := current_scene.find_child(node_name, true, false) as Control
	return node != null and node.is_visible_in_tree()

func _run() -> void:
	RegionEntry.draft = {}
	change_scene_to_file(MENU)
	for _frame: int in range(30): await process_frame
	if not _ok(current_scene != null and current_scene.scene_file_path == MENU, "the menu opens"): return
	var menu: Node = current_scene
	if not _press("NewGame") or not _ok(_page("map"), "the map page"): return
	if not _press("MapPickExisting") or not _ok(_page("pick_existing"), "選現成人物 opens from the map page"): return
	var listed := ScenarioPeople.people(PACKAGE)
	var scenario := menu.find_child("ExistingScenario", true, false) as OptionButton
	if not _ok(scenario.item_count >= 1 and str(menu.call("picked_existing_package").get("path", "")) == PACKAGE, "the scenario list holds demo A"): return
	var list := menu.find_child("ExistingPeopleList", true, false) as ItemList
	if not _ok(list.item_count == listed.people.size() + ScenarioPeople.ROLES.size(), "the list holds every person under four headers (%d)" % list.item_count): return
	var map: Control = menu.find_child("ExistingPeopleMap", true, false)
	if not _ok(map.sites.size() == 46 and map.counts.size() == 45, "the map marks 30 settlements, 15 lairs and the start (%d Sites, %d with people)" % [map.sites.size(), map.counts.size()]): return
	# A click on a lair picks its chief.
	var chief: Dictionary = listed.people.filter(func(row: Dictionary) -> bool: return str(row.role) == "chief")[0]
	map.site_clicked.emit(chief.site)
	if not _ok(str(RegionEntry.draft.get("existing", {}).get("name", "")) == str(chief.name) and list.get_selected_items().size() == 1, "a map click picks the chief %s" % str(chief.name)): return
	# A list pick moves the map mark.
	var leader: Dictionary = listed.people[0]
	var at := -1
	for index: int in list.item_count:
		if list.get_item_text(index).begins_with(str(leader.name)): at = index
	list.select(at)
	list.item_selected.emit(at)
	if not _ok(map.picked == leader.site and str(RegionEntry.draft.existing.name) == str(leader.name), "a list pick of %s marks his Site %s" % [str(leader.name), str(leader.site)]): return
	if not _ok((menu.find_child("ExistingName", true, false) as LineEdit).text == str(leader.name), "his name is offered for editing"): return
	(menu.find_child("ExistingName", true, false) as LineEdit).text = "王測試"
	# The look page shows the look only.
	if not _press("ExistingLook") or not _ok(_page("character"), "改外觀 opens the character page"): return
	if not _ok(not _shown("Ability_combat_ability") and not _shown("Personality_risk") and not _shown("CharacterSurname") and not _shown("CharacterSaveTemplate"), "only the look and the name are on the page"): return
	if not _ok((menu.find_child("CharacterName", true, false) as LineEdit).text == "王測試", "the new name is on the look page"): return
	var body := menu.find_child("CharacterBody", true, false) as OptionButton
	body.select(1)
	body.item_selected.emit(1)
	if not _press("CharacterNext") or not _ok(_page("pick_existing"), "back on the pick page"): return
	if not _ok(bool(RegionEntry.draft.get("existing_look", false)) and int(RegionEntry.draft.character.body) == 1 and not RegionEntry.draft.character.has("combat_ability"), "the draft keeps his new look, no abilities"): return
	if not _press("ExistingNext") or not _ok(_page("confirm"), "the confirm page"): return
	var summary := (menu.find_child("NewGameSummary", true, false) as Label).text
	if not _ok(summary.contains(str(leader.title)) and summary.contains("改名為 王測試") and summary.contains("王家"), "the summary names whom he takes over", summary): return
	if not _ok(not _shown("StartFaction") and not _shown("StartTeam") and not _shown("InitialArtisanScenario"), "no start faction, team or scenario choice"): return
	if not _press("ConfirmBack") or not _ok(_page("pick_existing"), "上一步 returns to the pick page"): return
	if not _press("ExistingNext") or not _press("StartGame"): return
	if not _ok(str(RegionEntry.pending.get("existing", {}).get("name", "")) == str(leader.name) and str(RegionEntry.pending.character.get("name", "")) == "王測試", "Start requests him under his new name"): return
	var lab: TerrainLab = null
	var deadline := Time.get_ticks_msec() + 420000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
		if current_scene != null and current_scene.scene_file_path == MENU and Time.get_ticks_msec() > deadline - 400000:
			var shown: Label = current_scene.find_child("MenuMessage", true, false) as Label
			if shown != null and shown.visible:
				_fail("back to the menu: " + shown.text)
				return
	if not _ok(lab != null, "the world is born"): return
	for _frame: int in range(5): await process_frame
	var player := int(lab.controlled_person_id())
	var record: Dictionary = lab.crowd_site._records.get(player, {})
	if not _ok(str(record.get("name", "")) == "王測試" and int(record.get("appearance", {}).get("body", -1)) == 1, "he is born as 王測試 with the new look", [record.get("name"), record.get("appearance", {}).get("body")]): return
	_finished = true
	TerrainArmy.release_contact_source()
	await process_frame
	print("MAIN_MENU_EXISTING_PASS: %d checks" % checks)
	quit(0)
