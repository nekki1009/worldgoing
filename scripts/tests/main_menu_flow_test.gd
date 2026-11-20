extends SceneTree
## Main-menu entry flow (MAIN_MENU_PLAN P1–P4): New Game → start Site on the
## Taiwan map → character → confirm → fixed world; in-game Region view and
## return; back to menu; Continue and Load World; personality/name save rules.

const MENU := "res://scenes/main_menu/MainMenu.tscn"
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const REGION := "res://scenes/region_lab/RegionLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const PersonPersonality = preload("res://scripts/terrain_lab/person_personality.gd")
const START := Vector2i(1170, 13252)
var deadline := 0
var _finished := false

class MainFlowErrors extends Logger:
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

var _errors := MainFlowErrors.new()

func _initialize() -> void:
	OS.add_logger(_errors)
	deadline = Time.get_ticks_msec() + 280000
	_run.call_deferred()

func _finalize() -> void:
	OS.remove_logger(_errors)

func _process(_delta: float) -> bool:
	if not _healthy(): return false
	if Time.get_ticks_msec() > deadline: _fail("deadline")
	return false

func _healthy() -> bool:
	if _finished: return false
	var error: String = _errors.first_error()
	if not error.is_empty(): return _fail("script/engine error: " + error)
	return true

func _fail(reason: String) -> bool:
	if _finished: return false
	_finished = true
	push_error("MAIN MENU FLOW FAIL: " + reason)
	quit(1)
	return false

func _scene_is(path: String, frames: int = 600) -> bool:
	for i: int in range(frames):
		await process_frame
		if not _healthy(): return false
		if current_scene != null and current_scene.scene_file_path == path and current_scene.is_node_ready(): break
	await process_frame
	if not _healthy(): return false
	return current_scene != null and current_scene.scene_file_path == path

func _press(node_name: String) -> bool:
	if not _healthy(): return false
	var button := current_scene.find_child(node_name, true, false) as Button
	if button == null or button.disabled or not button.is_visible_in_tree(): return _fail("button unavailable: " + node_name)
	button.pressed.emit()
	return _healthy()

func _press_text(text: String) -> bool:
	if not _healthy(): return false
	for node: Node in current_scene.find_children("*", "Button", true, false):
		if (node as Button).text == text and not (node as Button).disabled and (node as Button).is_visible_in_tree():
			(node as Button).pressed.emit()
			return _healthy()
	return _fail("button text unavailable: " + text)

func _page_visible(page: String) -> bool:
	var node := current_scene.find_child("Page_" + page, true, false) as Control
	return node != null and node.visible

func _run() -> void:
	if not _unit_checks(): return
	if str(ProjectSettings.get_setting("application/run/main_scene")) != MENU: return _fail("main scene is not MainMenu")
	change_scene_to_file(MENU)
	if not await _scene_is(MENU): return _fail("MainMenu did not load")
	if not (current_scene.find_child("ContinueGame", true, false) as Button).disabled: return _fail("Continue enabled without a world")
	# P2: map → start Site.
	if not _press("NewGame") or not _page_visible("map"): return _fail("map page not shown")
	if not _press("PickStart"): return
	if not await _scene_is(REGION): return _fail("start picker did not open")
	if str(current_scene.get("_mode")) != "pick_start": return _fail("RegionLab not in pick_start mode")
	for hidden: String in ["開啟所選 Site", "返回地圖"]:
		for node: Node in current_scene.find_children("*", "Button", true, false):
			if (node as Button).text == hidden and (node as Button).is_visible_in_tree(): return _fail("lab button visible in game mode: " + hidden)
	current_scene.call("select_site", START)
	if not _press_text("以所選地點為起點"): return
	if not await _scene_is(MENU): return _fail("did not return to the menu after picking")
	if not _page_visible("character"): return _fail("character page not shown after picking")
	# P3: character.
	var menu: Node = current_scene
	(menu.find_child("CharacterNext", true, false) as Button).pressed.emit()
	if _page_visible("confirm"): return _fail("empty name accepted")
	(menu.find_child("CharacterName", true, false) as LineEdit).text = "林測試"
	var body := menu.find_child("CharacterBody", true, false) as OptionButton
	body.select(1)
	body.item_selected.emit(1)
	var hair := menu.find_child("CharacterHair", true, false) as OptionButton
	hair.select(2)
	var face := menu.find_child("CharacterFace", true, false) as OptionButton
	face.select(3)
	(menu.find_child("CharacterHairDyed", true, false) as CheckBox).button_pressed = true
	(menu.find_child("CharacterHairDye", true, false) as ColorPickerButton).color = Color("2050c0")
	var abilities := {"combat_ability": 80, "tactics": 70, "leadership": 20, "coach": 90}
	for kind: String in abilities:
		(menu.find_child("Ability_" + kind, true, false) as HSlider).value = abilities[kind]
	var traits := {"risk": 90, "mercy": 10, "innovation": 75}
	for axis: String in traits:
		(menu.find_child("Personality_" + axis, true, false) as HSlider).value = traits[axis]
	# 技能 K5: 260 points are over the 200 budget until 自由分配 is ticked or other items give points back.
	(menu.find_child("CharacterNext", true, false) as Button).pressed.emit()
	if _page_visible("confirm") or int(menu.call("start_points")) != 260: return _fail("over-budget character accepted (%s points)" % menu.call("start_points"))
	var free := menu.find_child("CharacterFreePoints", true, false) as CheckBox
	free.button_pressed = true
	if not bool(menu.call("points_within_limit")): return _fail("自由分配 did not lift the cap")
	free.button_pressed = false
	var skills := {"Skill_farming": 10, "Skill_riding": 10, "Skill_learning": 10, "Aptitude_mind": 60}
	for node_name: String in skills:
		(menu.find_child(node_name, true, false) as HSlider).value = skills[node_name]
	if int(menu.call("start_points")) != 200 or not bool(menu.call("points_within_limit")): return _fail("lines and aptitude did not give points back (%s)" % menu.call("start_points"))
	var expected: Dictionary = menu.call("character_data")
	if expected.skills != {"version": 1, "start": 1, "lines": {"farming": 10000, "riding": 10000}, "aptitude": {"body": 50, "mind": 60}} or int(expected.learning) != 10:
		return _fail("start packet %s" % expected.skills)
	(menu.find_child("CharacterNext", true, false) as Button).pressed.emit()
	if not _page_visible("confirm"): return _fail("confirm page not shown")
	var summary := (menu.find_child("NewGameSummary", true, false) as Label).text
	if "林測試" not in summary or "(1170, 13252)" not in summary or "勇猛 90" not in summary or "農牧 10" not in summary or "悟性 60" not in summary: return _fail("summary incomplete: " + summary)
	(menu.find_child("WorldName", true, false) as LineEdit).text = "測試世界"
	if not _press("StartGame"): return
	if not await _scene_is(SITE): return _fail("new game did not open TerrainLab")
	if not await _frames(20): return
	var lab := current_scene as TerrainLab
	var slot: RegionSaveSlot = lab.site_controller.region_slot
	if slot == null: return _fail("world not opened: " + lab.site_controller.message.text)
	var world_id := str(slot.pin.world_instance_id)
	if not str(slot.control.active_site_id).ends_with(":%d:%d" % [START.x, START.y]): return _fail("wrong start " + str(slot.control.active_site_id))
	if not _player_matches(lab, expected): return
	if _files_under("user://sites") > 0: return _fail("placeholder Site was archived or saved under user://sites")
	var meta := RegionEntry.read_world(world_id)
	if str(meta.get("name", "")) != "測試世界": return _fail("world meta name " + str(meta))
	print("MAIN MENU FLOW new world ", world_id, " ", meta)
	# In-game Region view and return.
	if not _press("OpenRegionMap"): return
	if not await _scene_is(REGION): return _fail("in-game map did not open")
	if str(current_scene.get("_mode")) != "view" or RegionEntry.view.get("active") != START or START not in RegionEntry.view.get("visited", []):
		return _fail("view context wrong: " + str(RegionEntry.view))
	if not _press_text("返回遊戲"): return
	if not await _scene_is(SITE): return _fail("map return did not open TerrainLab")
	if not await _frames(20): return
	lab = current_scene as TerrainLab
	if lab.site_controller.region_slot == null or str(lab.site_controller.region_slot.pin.world_instance_id) != world_id: return _fail("map return did not resume the world")
	if not _player_matches(lab, expected): return
	# P1: back to menu, Continue.
	if not _press("ReturnMainMenu"): return
	if not await _scene_is(MENU): return _fail("back-to-menu failed")
	var note := ""
	for node: Node in current_scene.find_children("*", "Label", true, false):
		if "測試世界" in (node as Label).text: note = (node as Label).text
	if note.is_empty() or (current_scene.find_child("ContinueGame", true, false) as Button).disabled: return _fail("Continue does not offer the world")
	if not _press("ContinueGame"): return
	if not await _scene_is(SITE): return _fail("Continue did not open TerrainLab")
	if not await _frames(20): return
	lab = current_scene as TerrainLab
	if lab.site_controller.region_slot == null or str(lab.site_controller.region_slot.pin.world_instance_id) != world_id: return _fail("Continue opened another world")
	if not _player_matches(lab, expected): return
	# P4: Load World list.
	if not _press("ReturnMainMenu"): return
	if not await _scene_is(MENU): return _fail("second back-to-menu failed")
	if not _press("LoadWorld") or not _page_visible("load"): return _fail("load page not shown")
	var list := current_scene.find_child("WorldList", true, false) as ItemList
	if list.item_count != 1 or "測試世界" not in list.get_item_text(0): return _fail("world list wrong")
	list.select(0)
	list.item_selected.emit(0)
	if not _press("LoadSelectedWorld"): return
	if not await _scene_is(SITE): return _fail("Load World did not open TerrainLab")
	if not await _frames(20): return
	lab = current_scene as TerrainLab
	if lab.site_controller.region_slot == null or not _player_matches(lab, expected): return _fail("loaded world mismatch")
	if not _healthy(): return
	_finished = true
	print("MAIN MENU FLOW PASS")
	quit(0)

func _frames(count: int) -> bool:
	for i: int in range(count):
		await process_frame
		if not _healthy(): return false
	return true

## Neutral part 2: the created player is roster unit 0 and captain of a one-person crowd team (host control), not an actor.
## Name, abilities, personality and appearance are read back from that crowd person's record and native soldier.
func _army_summary(armies: Array) -> Array:
	var result: Array = []
	for army: Variant in armies:
		if army is Dictionary: result.append({"name": army.get("name"), "role": army.get("role"), "faction": army.get("faction_id"), "crowd": army.get("crowd"), "ids": army.get("units", []).map(func(row: Variant) -> Variant: return row.get("person_id") if row is Dictionary else null)})
	return result

func _player_matches(lab: TerrainLab, expected: Dictionary) -> bool:
	var identity := int(lab.controlled_person_id())
	var crowd: Variant = lab.crowd_site
	if crowd == null or not crowd.active or not crowd._records.has(identity) or crowd._actors.has(identity): return _fail("player is not a crowd roster person %s" % JSON.stringify({"id": identity, "crowd": crowd != null, "active": crowd != null and crowd.active, "record": crowd != null and crowd._records.has(identity), "actor": crowd != null and crowd._actors.has(identity), "armies": lab.terrain.site.get("armies", []).size(), "site_actors": lab.terrain.site.get("actors", {}).keys(), "armies0": _army_summary(lab.terrain.site.get("armies", [])), "teams": crowd.teams if crowd != null else null, "people": crowd.crowd.person_ids() if crowd != null and crowd.active else null}))
	if lab.actor_present(lab.character): return _fail("player also present as an actor")
	var index := int(crowd._index_by_id.get(identity, -1))
	if index < 0 or index != int(crowd.player_index): return _fail("host control is not on the player")
	var roster: Dictionary = {}
	for row: Dictionary in crowd.rosters:
		if crowd._roster_index_for_person(row, identity) >= 0: roster = row
	if roster.is_empty() or roster.units.size() != 1 + TerrainLab.INITIAL_CADRES or int(roster.get("formal_commander", -1)) != 0 or int(roster.faction_id) != RegionFactionQuery.NEUTRAL_FACTION_ID:
		return _fail("player is not the captain of a one-person neutral team")
	var record: Dictionary = crowd._records[identity]
	if str(record.get("name", "")) != str(expected.name): return _fail("name " + str(record.get("name", "")))
	if int(record.get("combat_ability", -1)) != int(expected.combat_ability): return _fail("combat ability %s" % record.get("combat_ability"))
	var native: Dictionary = crowd.soldier_state(index)
	for kind: String in ["tactics", "leadership", "coach"]:
		if int(native.get(kind, -1)) != int(expected.command_abilities.get(kind, -2)): return _fail("command abilities %s" % native)
	if PersonPersonality.read(record.get("personality", {})) != expected.personality: return _fail("personality %s" % record.get("personality"))
	var skills: Dictionary = record.get("skills", {})
	if skills.get("lines") != expected.skills.lines or skills.get("aptitude") != expected.skills.aptitude or int(skills.get("start", 0)) != 1 \
		or TerrainTestCharacter.PersonSocial.learning(record) != int(expected.learning): return _fail("skills %s learning %s" % [skills, record.get("social_state")])
	var appearance: Dictionary = record.appearance
	if int(appearance.body) != int(expected.body) or str(appearance.parts.hair) != str(expected.hair) or str(appearance.parts.face) != str(expected.face) \
		or str(appearance.hair_dye) != str(expected.hair_dye) or not bool(appearance.hair_dyed): return _fail("appearance %s" % appearance)
	if "林測試" not in lab.site_controller.player_status_label.text:
		lab.site_controller.update_ui()
		if "林測試" not in lab.site_controller.player_status_label.text: return _fail("status bar lacks the name")
	return true

func _files_under(root: String) -> int:
	var directory := DirAccess.open(root)
	if directory == null: return 0
	var count := directory.get_files().size()
	for child: String in directory.get_directories():
		count += _files_under(root.path_join(child))
	return count

func _unit_checks() -> bool:
	if not _creation_whitelist_check(): return false
	var neutral := PersonPersonality.neutral()
	if not PersonPersonality.valid(neutral) or not PersonPersonality.saved(neutral).is_empty(): return _fail("neutral packet")
	var bad := neutral.duplicate()
	bad.risk = 101
	if PersonPersonality.valid(bad): return _fail("out-of-range accepted")
	bad = neutral.duplicate()
	bad.erase("innovation")
	if PersonPersonality.valid(bad): return _fail("missing axis accepted")
	bad = neutral.duplicate()
	bad["extra"] = 1
	if PersonPersonality.valid(bad): return _fail("extra key accepted")
	bad = neutral.duplicate()
	bad.mercy = 12.5
	if PersonPersonality.valid(bad): return _fail("fraction accepted")
	return true

func _creation_whitelist_check() -> bool:
	# MAIN_MENU_PLAN P3 permits these explicit new-game choices, not old-world state.
	var traits := PersonPersonality.neutral()
	traits.risk = 90
	traits.mercy = 10
	traits.innovation = 75
	var approved := {"body": 1, "face": "face_standard_04", "hair": "hair_standard_03",
		"hair_dye": "2050c0", "hair_dyed": true, "name": "林測試", "combat_ability": 80,
		"command_abilities": {"tactics": 70, "leadership": 20, "coach": 90}, "personality": traits,
		"learning": 10, "skills": {"version": 1, "start": 1, "aptitude": {"body": 50, "mind": 60}}, "free_points": false}
	var source := approved.duplicate(true)
	for forbidden: String in ["hp", "faction_id", "technology", "item_state", "equipment", "family"]:
		source[forbidden] = {"old_world": true}
	var before := var_to_bytes(source)
	var controller := SiteController.new()
	var filtered: Dictionary = controller._initial_creation_appearance(source)
	controller.free()
	if not _healthy(): return false
	if filtered != approved: return _fail("creation whitelist dropped approved fields or admitted old-world fields")
	if var_to_bytes(source) != before: return _fail("creation whitelist mutated input")
	return true
