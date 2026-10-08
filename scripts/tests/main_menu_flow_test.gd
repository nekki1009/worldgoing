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

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 280000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("MAIN MENU FLOW deadline")
		quit(1)
	return false

func _fail(reason: String) -> bool:
	push_error("MAIN MENU FLOW FAIL: " + reason)
	quit(1)
	return false

func _scene_is(path: String, frames: int = 600) -> bool:
	for i: int in range(frames):
		await process_frame
		if current_scene != null and current_scene.scene_file_path == path and current_scene.is_node_ready(): break
	await process_frame
	return current_scene != null and current_scene.scene_file_path == path

func _press(node_name: String) -> bool:
	var button := current_scene.find_child(node_name, true, false) as Button
	if button == null or button.disabled or not button.is_visible_in_tree(): return _fail("button unavailable: " + node_name)
	button.pressed.emit()
	return true

func _press_text(text: String) -> bool:
	for node: Node in current_scene.find_children("*", "Button", true, false):
		if (node as Button).text == text and not (node as Button).disabled and (node as Button).is_visible_in_tree():
			(node as Button).pressed.emit()
			return true
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
	var expected: Dictionary = menu.call("character_data")
	(menu.find_child("CharacterNext", true, false) as Button).pressed.emit()
	if not _page_visible("confirm"): return _fail("confirm page not shown")
	var summary := (menu.find_child("NewGameSummary", true, false) as Label).text
	if "林測試" not in summary or "(1170, 13252)" not in summary or "勇猛 90" not in summary: return _fail("summary incomplete: " + summary)
	(menu.find_child("WorldName", true, false) as LineEdit).text = "測試世界"
	if not _press("StartGame"): return
	if not await _scene_is(SITE): return _fail("new game did not open TerrainLab")
	await _frames(20)
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
	await _frames(20)
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
	await _frames(20)
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
	await _frames(20)
	lab = current_scene as TerrainLab
	if lab.site_controller.region_slot == null or not _player_matches(lab, expected): return _fail("loaded world mismatch")
	print("MAIN MENU FLOW PASS")
	quit(0)

func _frames(count: int) -> void:
	for i: int in range(count):
		await process_frame

func _player_matches(lab: TerrainLab, expected: Dictionary) -> bool:
	var actor := lab.character
	var state := actor.capture_state()
	if actor.display_name != str(expected.name): return _fail("name " + actor.display_name)
	if int(actor.combat_ability) != int(expected.combat_ability): return _fail("combat ability %s" % actor.combat_ability)
	if actor.command_abilities != expected.command_abilities: return _fail("command abilities %s" % actor.command_abilities)
	if PersonPersonality.read(actor.personality) != expected.personality: return _fail("personality %s" % actor.personality)
	var appearance: Dictionary = state.appearance
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
