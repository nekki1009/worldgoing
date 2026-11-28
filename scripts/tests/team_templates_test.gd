extends SceneTree
## 隊伍範本（幹部卡）(開局流程規劃 §2, Nekki 2026-11-22). Checks:
## - the format: a card is a character template's name, look, 武力, command abilities and personality (no skills or 學業);
##   each ability 0–100 with no point budget; SLOTS slots, empty = generated; at least one card; a card with an extra field
##   or an ability over 100 is refused; save, list, load and delete under a scratch root;
## - the real main menu: the templates page lists team templates; 新建隊伍 opens the editor, whose slot menus list the
##   character templates; saving writes the card; New Game's confirm page offers the team template and the summary names it;
## - a new world started with cards: the cadres in birth order take each card (name, look, 武力, command abilities,
##   personality), an empty slot keeps its generated cadre, and the world saves.
## Output: TEAM_TEMPLATES_PASS on success; quit(1) on failure.

const MENU := "res://scenes/main_menu/MainMenu.tscn"
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Templates = preload("res://scripts/main_menu/character_templates.gd")
const TeamTemplates = preload("res://scripts/main_menu/team_templates.gd")
const START := Vector2i(1170, 13252)
const SCRATCH := "user://team_templates_test_scratch"

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	push_error("TEAM_TEMPLATES_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("TEAM_TEMPLATES OK ", checks, ": ", message)
		return true
	return _fail(message, detail)

func _find(node_name: String) -> Node:
	return current_scene.find_child(node_name, true, false)

func _press(node_name: String) -> void:
	(_find(node_name) as Button).pressed.emit()

func _visible(page: String) -> bool:
	var node := _find("Page_" + page) as Control
	return node != null and node.visible

func _clear(root: String) -> void:
	var directory := DirAccess.open(root)
	if directory == null: return
	for file: String in directory.get_files(): DirAccess.remove_absolute(root.path_join(file))

func _run() -> void:
	_clear(Templates.ROOT)
	_clear(TeamTemplates.ROOT)
	_clear(SCRATCH)
	RegionEntry.draft = {}
	if not _ok(TeamTemplates.SLOTS == TerrainLab.INITIAL_CADRES, "one slot per start cadre"): return
	change_scene_to_file(MENU)
	for _frame: int in range(60):
		await process_frame
		if current_scene != null and current_scene.has_method("show_page"): break
	if not _ok(current_scene != null and current_scene.has_method("show_page"), "the main menu opens"): return
	var menu: Node = current_scene

	# A character from the menu's own form, then two cards from it.
	menu.call("_reset_character_form")
	(_find("CharacterName") as LineEdit).text = "趙卡"
	var character: Dictionary = menu.call("character_data")
	var card := TeamTemplates.card_of(character)
	if not _ok(not card.has("skills") and not card.has("learning") and not card.has("free_points") and str(card.name) == "趙卡", "a card keeps only the cadre fields", card): return
	var strong := card.duplicate(true)
	strong["name"] = "錢卡"
	strong["combat_ability"] = 100
	strong["command_abilities"] = {"tactics": 100, "leadership": 100, "coach": 100}
	if not _ok(TeamTemplates.card_problems(strong).is_empty(), "abilities 100 each: no point budget on a card", TeamTemplates.card_problems(strong)): return
	var over := strong.duplicate(true)
	over["combat_ability"] = 101
	var extra := card.duplicate(true)
	extra["skills"] = {}
	if not _ok(not TeamTemplates.card_problems(over).is_empty() and not TeamTemplates.card_problems(extra).is_empty(), "an ability over 100 or an extra field is refused"): return

	# The format under a scratch root.
	var team := TeamTemplates.make("先鋒隊", [card, {}, {}, {}, strong])
	if not _ok(TeamTemplates.problems(team).is_empty() and team.cadres.size() == TeamTemplates.SLOTS, "a team with two cards and three generated slots is usable", TeamTemplates.problems(team)): return
	if not _ok(not TeamTemplates.problems(TeamTemplates.make("空隊", [])).is_empty(), "a team without any card is refused"): return
	var short := team.duplicate(true)
	short.cadres.pop_back()
	if not _ok(not TeamTemplates.problems(short).is_empty(), "a team with fewer slots is refused"): return
	var saved := TeamTemplates.save_template(team, "", SCRATCH)
	var listed := TeamTemplates.list(SCRATCH)
	if not _ok(saved.ok and listed.size() == 1 and listed[0].problems.is_empty() and TeamTemplates.cards_of(listed[0].template) == TeamTemplates.cards_of(team), "it saves, lists and loads back the same cards", [saved, listed]): return
	if not _ok(TeamTemplates.delete_template(str(saved.id), SCRATCH).ok and TeamTemplates.list(SCRATCH).is_empty(), "it deletes"): return

	# The real menu: a character template, then a team template made from it.
	var made := Templates.save_template(Templates.make("趙將", character))
	if not _ok(made.ok, "a character template is saved", made): return
	menu.call("show_page", "templates")
	if not _ok((_find("TeamTemplateList") as ItemList).item_count == 1 and not (_find("TeamTemplateList") as ItemList).is_item_selectable(0), "the templates page lists no team template yet"): return
	_press("TeamTemplateNew")
	var slot1 := _find("TeamSlot1") as OptionButton
	if not _ok(_visible("team_template") and slot1.item_count == 2 and slot1.get_item_text(1).contains("趙將"), "新建隊伍 opens the editor; each slot lists 自動產生 and the character template", slot1.item_count if slot1 != null else -1): return
	_press("TeamTemplateSave")
	if not _ok(TeamTemplates.list().is_empty() and not str((_find("TeamTemplateError") as Label).text).is_empty(), "without a title or a card nothing is saved"): return
	(_find("TeamTemplateTitle") as LineEdit).text = "趙家軍"
	slot1.select(1)
	_press("TeamTemplateSave")
	var teams := TeamTemplates.list()
	if not _ok(_visible("templates") and teams.size() == 1 and str(teams[0].template.cadres[0].get("name", "")) == "趙卡" and teams[0].template.cadres[1].is_empty(), "the team template saves the card in slot 1", teams): return
	# New Game's confirm page offers it.
	RegionEntry.draft = {"step": "confirm", "map": "taiwan", "site": START, "character": character}
	menu.call("show_page", "confirm")
	var pick := _find("StartTeam") as OptionButton
	if not _ok(pick.item_count == 2 and pick.selected == 0, "the confirm page offers 自動產生 and the team template", pick.item_count): return
	pick.select(1)
	pick.item_selected.emit(1)
	var summary := (_find("NewGameSummary") as Label).text
	var choice: Dictionary = menu.call("start_team_choice")
	if not _ok("幹部：趙家軍" in summary and choice.cards.size() == TeamTemplates.SLOTS and str(choice.cards[0].name) == "趙卡", "the summary names the team and the request gets its cards", [summary, choice]): return
	_clear(Templates.ROOT)
	_clear(TeamTemplates.ROOT)
	RegionEntry.draft = {}

	# A new world started with cards.
	strong["face"] = card.face
	if not _ok(RegionEntry.request_new_world(START, {}, "隊伍範本世界", "", RegionData.DEFAULT_MANIFEST, {}, {}, {}, [card, {}, {}, {}, strong]), "a new world is requested with two cards", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	for _frame: int in range(900):
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	var shown: Node = current_scene.find_child("MenuMessage", true, false) if current_scene != null else null
	if not _ok(lab != null, "the world opens", [RegionEntry.menu_message, current_scene.name if current_scene != null else "", (shown as Label).text if shown is Label else ""]): return
	for _frame: int in range(5): await process_frame
	var player := int(lab.controlled_person_id())
	var cadres: Array[int] = []
	for team_row: Dictionary in lab.crowd_site.teams:
		if team_row.get("person_ids", []).has(player):
			for person: Variant in team_row.person_ids:
				if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _ok(cadres.size() == TeamTemplates.SLOTS, "the start team has its cadres", cadres): return
	var first: Dictionary = lab.crowd_site._records[cadres[0]]
	var last: Dictionary = lab.crowd_site._records[cadres[4]]
	var middle: Dictionary = lab.crowd_site._records[cadres[1]]
	if not _ok(str(first.get("name", "")) == "趙卡" and str(first.appearance.parts.face) == str(card.face) and str(first.appearance.parts.hair) == str(card.hair) and int(first.appearance.body) == int(card.body),
		"the first cadre takes card 1's name and look", [first.get("name"), first.appearance]): return
	if not _ok(str(last.get("name", "")) == "錢卡" and is_equal_approx(float(last.combat_ability), 100.0) and int(last.command_abilities.get("tactics", 0)) == 100 and int(last.command_abilities.get("coach", 0)) == 100,
		"the last cadre (文武兼備) takes card 5's abilities", [last.get("name"), last.get("combat_ability"), last.get("command_abilities")]): return
	if not _ok(str(middle.get("name", "")) != "趙卡" and str(middle.get("name", "")) != "錢卡", "an empty slot keeps its generated cadre", middle.get("name")): return
	var index := int(lab.crowd_site._index_by_id.get(cadres[4], -1))
	var native: Dictionary = lab.crowd_site.soldier_state(index) if index >= 0 else {}
	if not _ok(int(native.get("tactics", -1)) == 100 and int(native.get("leadership", -1)) == 100, "the native crowd has card 5's command abilities", native.get("tactics")): return
	var saved_world: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _ok(saved_world.ok, "the world saves with the cards", saved_world): return
	_finished = true
	print("TEAM_TEMPLATES_PASS checks=", checks)
	quit(0)
