extends RefCounted
## 隊伍範本（幹部卡）(開局流程規劃 §2「5 名幹部」, Nekki 2026-11-22 好): the start team's cadre cards. A team template is a
## title and one slot per start cadre (TerrainLab.INITIAL_CADRES); a slot is empty (the cadre is generated as before) or a
## card. A card is taken from a character template (CharacterTemplates) and keeps only what a cadre takes from it: name,
## look (body, face, hair, dye), 武力 and the three command abilities, and personality. Skills and 學業 are not on a card:
## cadres keep the start seeding by age and main weapon, and the 200-point budget stays the player's (each ability is
## 0–100, the range the generated cadres draw from). The last slot is the 文武兼備 cadre (INITIAL_CIVIL_CADRES).
## One JSON file per template under ROOT, with a format version: {version, title, cadres: [{} | card]}.
const Templates = preload("res://scripts/main_menu/character_templates.gd")

const VERSION := 1
const ROOT := "user://team_templates"
const SLOTS := 5 # TerrainLab.INITIAL_CADRES (checked by the tests)
const MAX_TEMPLATES := 200
const CARD_KEYS: Array[String] = ["name", "body", "face", "hair", "hair_dye", "hair_dyed", "combat_ability", "command_abilities", "personality"]

## A cadre card from a character_data() dictionary (a character template's `character`).
static func card_of(character: Dictionary) -> Dictionary:
	var normalized := Templates.normalized_character(character)
	var card := {}
	for key: String in CARD_KEYS:
		if normalized.has(key): card[key] = normalized[key]
	return card

## Problems of one card (Traditional Chinese); empty when usable. The card has no skills, so no point budget applies.
static func card_problems(card: Variant) -> Array[String]:
	var found: Array[String] = []
	if not card is Dictionary:
		found.append("幹部卡格式不合法")
		return found
	for key: Variant in card:
		if not str(key) in CARD_KEYS: found.append("幹部卡有多餘欄位：%s" % str(key))
	var checked: Dictionary = card.duplicate(true)
	checked["free_points"] = true # abilities each 0–100, no budget: the generated cadres' range
	found.append_array(Templates.character_problems(checked))
	return found

## Problems that keep `template` from starting a game; empty when it is usable.
static func problems(template: Variant) -> Array[String]:
	var found: Array[String] = []
	if not template is Dictionary or not Templates._integer(template.get("version"), VERSION, VERSION):
		found.append("隊伍範本格式版本不符")
		return found
	if not template.get("title") is String or str(template.title).strip_edges().is_empty() or str(template.title).length() > Templates.MAX_TITLE:
		found.append("範本名稱要 1–%d 字" % Templates.MAX_TITLE)
	var cadres: Variant = template.get("cadres")
	if not cadres is Array or cadres.size() != SLOTS:
		found.append("要有 %d 個幹部位置" % SLOTS)
		return found
	var filled := 0
	for at: int in range(SLOTS):
		var card: Variant = cadres[at]
		if card is Dictionary and card.is_empty(): continue
		filled += 1
		for problem: String in card_problems(card): found.append("第 %d 位：%s" % [at + 1, problem])
	if filled == 0: found.append("至少要放一張幹部卡")
	return found

## A template from a title and SLOTS cards ({} = generated).
static func make(title: String, cards: Array) -> Dictionary:
	var cadres: Array = []
	for at: int in range(SLOTS):
		var card: Variant = cards[at] if at < cards.size() else {}
		cadres.append(card_of(card) if card is Dictionary and not card.is_empty() else {})
	return {"version": VERSION, "title": title.strip_edges(), "cadres": cadres}

## The cards a new world takes (SLOTS entries, {} = generated), JSON numbers back to integers.
static func cards_of(template: Dictionary) -> Array:
	var result: Array = []
	var cadres: Array = template.get("cadres", []) if template.get("cadres") is Array else []
	for at: int in range(SLOTS):
		var card: Variant = cadres[at] if at < cadres.size() else {}
		result.append(card_of(card) if card is Dictionary and not card.is_empty() else {})
	return result

## Every team template under `root`: [{id, title, template, problems}], by title then id.
static func list(root: String = ROOT) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var directory := DirAccess.open(root)
	if directory == null: return rows
	for file: String in directory.get_files():
		if not file.ends_with(".json"): continue
		var id := file.get_basename()
		var loaded := load_template(id, root)
		rows.append({"id": id, "title": str(loaded.template.get("title", id)) if loaded.template is Dictionary else id,
			"template": loaded.template, "problems": loaded.problems})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id) if str(a.title) == str(b.title) else str(a.title) < str(b.title))
	return rows

## {ok, template, problems}; ok when the file exists and parses (a template with problems still loads).
static func load_template(id: String, root: String = ROOT) -> Dictionary:
	if not Templates.valid_id(id): return {"ok": false, "template": {}, "problems": ["範本編號不合法"]}
	var path := root.path_join(id + ".json")
	if not FileAccess.file_exists(path): return {"ok": false, "template": {}, "problems": ["範本檔不存在"]}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {"ok": false, "template": {}, "problems": ["範本檔無法讀取（JSON 損毀）"]}
	var template: Dictionary = json.data
	if template.get("version") is float: template["version"] = int(template.version)
	if template.get("cadres") is Array:
		var cadres: Array = []
		for card: Variant in template.cadres: cadres.append(Templates.normalized_character(card) if card is Dictionary and not card.is_empty() else card)
		for card: Variant in cadres:
			if card is Dictionary and not card.is_empty():
				card.erase("learning") # normalized_character adds the player-only fields; a card never has them
				card.erase("free_points")
		template["cadres"] = cadres
	return {"ok": true, "template": template, "problems": problems(template)}

## Writes `template` (refused with its problems when it is not usable). A new id when `id` is "". {ok, id, problems}.
static func save_template(template: Dictionary, id: String = "", root: String = ROOT) -> Dictionary:
	var found := problems(template)
	if not found.is_empty(): return {"ok": false, "id": id, "problems": found}
	if id.is_empty():
		if list(root).size() >= MAX_TEMPLATES: return {"ok": false, "id": "", "problems": ["範本已達 %d 個上限" % MAX_TEMPLATES]}
		id = Templates.new_id(root)
	if not Templates.valid_id(id): return {"ok": false, "id": id, "problems": ["範本編號不合法"]}
	if DirAccess.make_dir_recursive_absolute(root) != OK and not DirAccess.dir_exists_absolute(root):
		return {"ok": false, "id": id, "problems": ["無法建立範本資料夾"]}
	var file := FileAccess.open(root.path_join(id + ".json"), FileAccess.WRITE)
	if file == null: return {"ok": false, "id": id, "problems": ["無法寫入範本檔"]}
	file.store_string(JSON.stringify(template, "\t", true))
	file.close()
	return {"ok": true, "id": id, "problems": []}

## Removes one team template file (the editor asks first). {ok, problems}.
static func delete_template(id: String, root: String = ROOT) -> Dictionary:
	if not Templates.valid_id(id): return {"ok": false, "problems": ["範本編號不合法"]}
	var path := root.path_join(id + ".json")
	if not FileAccess.file_exists(path): return {"ok": false, "problems": ["範本檔不存在"]}
	if DirAccess.remove_absolute(path) != OK: return {"ok": false, "problems": ["無法刪除範本檔"]}
	return {"ok": true, "problems": []}
