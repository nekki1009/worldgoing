extends SceneTree
## 開局流程規劃 §1–§3 (Claude Doc 2026-11-09, Nekki 11/09 A) in the real main menu, headless, without opening a world:
## - 角色編輯器: a new template over 200 points is refused, then saved within 200; it lists, copies, renames and is
##   deleted only on the second press; 設定 is shown but not open yet;
## - New Game: after the start Site, 選人物 lists the usable template; using it fills the character page (name, family
##   blueprint, abilities) and the confirm page shows the family name and the template;
## - with no usable template the character page opens as before;
## - RegionEntry.delete_world removes one world folder and clears the last-world pointer; bad ids are refused.
## Output: MAIN_MENU_TEMPLATES_PASS on success; quit(1) on failure.

const MENU := "res://scenes/main_menu/MainMenu.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Templates = preload("res://scripts/main_menu/character_templates.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void: _fail("120-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	push_error("MAIN_MENU_TEMPLATES_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("MAIN_MENU_TEMPLATES OK ", checks, ": ", message)
		return true
	return _fail(message, detail)

func _menu() -> Node:
	return current_scene

func _find(node_name: String) -> Node:
	return _menu().find_child(node_name, true, false)

func _press(node_name: String) -> void:
	(_find(node_name) as Button).pressed.emit()

func _visible(page: String) -> bool:
	var node := _find("Page_" + page) as Control
	return node != null and node.visible

func _open_menu() -> bool:
	change_scene_to_file(MENU)
	for _frame: int in range(60):
		await process_frame
		if current_scene != null and current_scene.has_method("show_page"): return true
	return false

func _clear_templates() -> void:
	var directory := DirAccess.open(Templates.ROOT)
	if directory == null: return
	for file: String in directory.get_files(): DirAccess.remove_absolute(Templates.ROOT.path_join(file))

func _run() -> void:
	_clear_templates()
	RegionEntry.draft = {}
	if not _ok(await _open_menu(), "the main menu opens"): return
	if not _ok(_find("CharacterEditor") != null and (_find("Settings") as Button).disabled, "角色編輯器 is there; 設定 is shown, not open yet"): return
	_press("CharacterEditor")
	if not _ok(_visible("templates") and (_find("TemplateList") as ItemList).item_count == 1 and not (_find("TemplateList") as ItemList).is_item_selectable(0), "the editor lists no template yet"): return
	_press("TemplateNew")
	if not _ok(_visible("character") and (_find("TemplateTitle") as LineEdit).is_visible_in_tree() and not (_find("CharacterNext") as Button).visible, "新建 opens the character page as a template editor"): return
	(_find("TemplateTitle") as LineEdit).text = "猛將"
	(_find("CharacterName") as LineEdit).text = "張範本"
	(_find("CharacterSurname") as LineEdit).text = "張"
	(_find("Ability_combat_ability") as HSlider).value = 80
	_press("CharacterSaveTemplate")
	var refusal := str(_menu().get("_character_error").text)
	if not _ok(Templates.list().is_empty() and "230" in refusal, "230 points are refused, nothing is written", [refusal, Templates.list()]): return
	(_find("Skill_gathering") as HSlider).value = 20
	_press("CharacterSaveTemplate")
	var rows := Templates.list()
	if not _ok(rows.size() == 1 and rows[0].problems.is_empty() and str(rows[0].template.character.name) == "張範本" and int(rows[0].template.character.combat_ability) == 80 and str(rows[0].template.family.surname) == "張",
		"200 points (樵採 20 pays for 武力 80) save as a template", rows): return
	_press("TemplateEditorBack")
	var list := _find("TemplateList") as ItemList
	if not _ok(_visible("templates") and list.item_count == 1 and "猛將" in list.get_item_text(0), "back on the list it shows the template", list.item_count): return
	list.select(0)
	list.item_selected.emit(0)
	_press("TemplateCopy")
	if not _ok(Templates.list().size() == 2 and list.item_count == 2, "copy"): return
	list.select(0)
	list.item_selected.emit(0)
	(_find("TemplateRenameInput") as LineEdit).text = "猛將甲"
	_press("TemplateRename")
	var titles: Array = Templates.list().map(func(row: Dictionary) -> String: return str(row.title))
	if not _ok(titles.has("猛將甲") and titles.has("猛將 副本"), "rename", titles): return
	list.select(1)
	list.item_selected.emit(1)
	_press("TemplateDelete")
	if not _ok(Templates.list().size() == 2, "the first delete press only asks"): return
	_press("TemplateDelete")
	if not _ok(Templates.list().size() == 1, "the second press deletes", Templates.list()): return
	_press("TemplatesBack")
	# New Game after the start Site (the RegionLab pick leaves this draft): 選人物 lists the template.
	RegionEntry.draft = {"step": "character", "map": "taiwan", "site": START}
	_menu().call("show_page", str(_menu().call("_character_entry_page")))
	var pick := _find("PickTemplateList") as ItemList
	if not _ok(_visible("pick_character") and pick.item_count == 1 and (_find("PickExisting") as Button).disabled, "選人物 lists the usable template; 選現成人物 is not open yet"): return
	pick.select(0)
	_press("PickTemplateUse")
	if not _ok(_visible("character") and (_find("CharacterName") as LineEdit).text == "張範本" and int((_find("Ability_combat_ability") as HSlider).value) == 80 and (_find("CharacterSurname") as LineEdit).text == "張" and (_find("CharacterNext") as Button).visible,
		"the template fills the character page"): return
	_press("CharacterNext")
	var summary := (_find("NewGameSummary") as Label).text
	if not _ok(_visible("confirm") and "家族：張家" in summary and "範本：猛將" in summary, "the confirm page shows the family name and the template", summary): return
	# No usable template: the character page opens directly, as before.
	_clear_templates()
	RegionEntry.draft = {"step": "character", "map": "taiwan", "site": START}
	if not _ok(str(_menu().call("_character_entry_page")) == "character", "with no template the character page opens directly"): return
	# RegionEntry.delete_world.
	var root := RegionEntry.WORLDS.path_join("menu_delete_probe")
	DirAccess.make_dir_recursive_absolute(root.path_join("slots/s1"))
	for written: Array in [[root.path_join("world.json"), "{}"], [root.path_join("slots/s1/manifest.json"), "{}"],
			[RegionEntry.LAST_WORLD, JSON.stringify({"world_id": "menu_delete_probe", "slot_id": "s1"})]]:
		DirAccess.make_dir_recursive_absolute(str(written[0]).get_base_dir())
		var file := FileAccess.open(str(written[0]), FileAccess.WRITE)
		file.store_string(str(written[1]))
		file.close()
	if not _ok(not RegionEntry.delete_world("") and not RegionEntry.delete_world("..") and not RegionEntry.delete_world("no_such_world"), "bad or unknown ids are refused"): return
	if not _ok(RegionEntry.delete_world("menu_delete_probe") and not DirAccess.dir_exists_absolute(root) and not FileAccess.file_exists(RegionEntry.LAST_WORLD), "a world folder is removed with its last-world pointer"): return
	RegionEntry.draft = {}
	_finished = true
	print("MAIN_MENU_TEMPLATES_PASS checks=", checks)
	quit(0)
