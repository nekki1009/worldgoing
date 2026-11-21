extends RefCounted
## The character template library (開局流程規劃, Claude Doc 2026-11-09, Nekki 11/09 A; §2 角色編輯器): templates made in
## the main menu's character editor and picked at New Game. One JSON file per template under ROOT, with a format version.
## A template keeps only what a new world takes from its player, so one template can start many worlds:
##   {version, title, character: {name, body, face, hair, hair_dye, hair_dyed, combat_ability, command_abilities,
##    personality, learning, skills, free_points}, family: {surname, name}}
## `character` is exactly the main menu's character_data() (技能 K5: 學業, the eight lines and the aptitudes in one
## 200-point budget; free_points = made with 自由分配). `family` is the v1 family blueprint: the head himself and the
## family name (relatives come in v2). Never ids, faction, place, items, titles or prestige.
## A template that fails validation is listed with its problems and cannot start a game.

const PersonPersonality = preload("res://scripts/terrain_lab/person_personality.gd")
const PersonSkills = preload("res://scripts/terrain_lab/person_skills.gd")

const VERSION := 1
const ROOT := "user://character_templates"
const MAX_TITLE := 32
const MAX_FAMILY_NAME := 32 # SiteFamilyContinuity.NAME_MAX
const MAX_SURNAME := 8
const MAX_TEMPLATES := 200
const ABILITY_KEYS: Array[String] = ["tactics", "leadership", "coach"]

## Problems that keep `template` from starting a game (Traditional Chinese, for the list); empty when it is usable.
static func problems(template: Variant) -> Array[String]:
	var found: Array[String] = []
	if not template is Dictionary or not _integer(template.get("version"), VERSION, VERSION):
		found.append("範本格式版本不符")
		return found
	if not template.get("title") is String or str(template.title).strip_edges().is_empty() or str(template.title).length() > MAX_TITLE:
		found.append("範本名稱要 1–%d 字" % MAX_TITLE)
	var family: Variant = template.get("family")
	if not family is Dictionary or not family.get("surname", "") is String or not family.get("name", "") is String \
		or str(family.get("surname", "")).length() > MAX_SURNAME or str(family.get("name", "")).length() > MAX_FAMILY_NAME:
		found.append("家族設定不合法（姓氏最多 %d 字、家族名最多 %d 字）" % [MAX_SURNAME, MAX_FAMILY_NAME])
	var character: Variant = template.get("character")
	if not character is Dictionary:
		found.append("缺少人物資料")
		return found
	found.append_array(character_problems(character))
	return found

## Problems of one character_data() dictionary (the same rules the New Game character step applies).
static func character_problems(character: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var person_name: Variant = character.get("name")
	if not person_name is String or str(person_name).strip_edges().is_empty() or str(person_name).length() > TerrainTestCharacter.MAX_NAME_LENGTH:
		found.append("名字要 1–%d 字" % TerrainTestCharacter.MAX_NAME_LENGTH)
	if not _integer(character.get("body"), 0, 1):
		found.append("性別不合法")
		return found
	var body := int(character.body)
	if not _option_ids(HumanCharacter3DEditor.PART_SLOTS[0].options).has(str(character.get("face", ""))): found.append("臉型部件不存在")
	if not _option_ids(HumanCharacter3DEditor.HAIR_OPTIONS[body]).has(str(character.get("hair", ""))): found.append("髮型部件不存在")
	if not character.get("hair_dye") is String or not Color.html_is_valid(str(character.hair_dye)) or not character.get("hair_dyed") is bool:
		found.append("髮色不合法")
	var command: Variant = character.get("command_abilities")
	var abilities_ok: bool = _integer(character.get("combat_ability"), 0, 100) and command is Dictionary and command.size() == ABILITY_KEYS.size()
	if abilities_ok:
		for key: String in ABILITY_KEYS: abilities_ok = abilities_ok and _integer(command.get(key), 0, 100)
	if not abilities_ok: found.append("武力、戰術、統御、教練要是 0–100 的整數")
	if not PersonPersonality.valid(character.get("personality")): found.append("性格資料不完整")
	var learning: Variant = character.get("learning", 0)
	if not _integer(learning, 0, 100): found.append("學業要是 0–100 的整數")
	var packet: Variant = character.get("skills", {})
	var skills_ok: bool = packet is Dictionary and (packet.is_empty() or (PersonSkills.valid(packet) and packet.get("aptitude") is Dictionary))
	if not skills_ok: found.append("熟練或資質資料不合法")
	if not character.get("free_points", false) is bool: found.append("自由分配標記不合法")
	if abilities_ok and skills_ok and _integer(learning, 0, 100) and not bool(character.get("free_points", false)):
		var used := PersonSkills.packet_points(_normalized_skills(packet), int(character.combat_ability), _ints(command), int(learning))
		if used > PersonSkills.START_POINTS: found.append("能力點已用 %d，超過 %d（未開自由分配）" % [used, PersonSkills.START_POINTS])
	return found

## A template from a character_data() dictionary and the family blueprint.
static func make(title: String, character: Dictionary, family: Dictionary = {}) -> Dictionary:
	return {"version": VERSION, "title": title.strip_edges(), "character": normalized_character(character),
		"family": {"surname": str(family.get("surname", "")).strip_edges(), "name": str(family.get("name", "")).strip_edges()}}

## The character with JSON numbers back to integers (a loaded file has floats), keys in the menu's shape.
static func normalized_character(character: Dictionary) -> Dictionary:
	var result := character.duplicate(true)
	for key: String in ["body", "combat_ability", "learning"]:
		if result.get(key) is float: result[key] = int(result[key])
	if result.get("command_abilities") is Dictionary: result["command_abilities"] = _ints(result.command_abilities)
	if result.get("personality") is Dictionary: result["personality"] = _ints(result.personality)
	if result.get("skills") is Dictionary: result["skills"] = _normalized_skills(result.skills)
	if not result.has("learning"): result["learning"] = 0
	if not result.has("free_points"): result["free_points"] = false
	return result

## The family name a new world takes: the blueprint's name, else "<姓氏>家", else "" (no family name).
static func family_name_of(template: Dictionary) -> String:
	var family: Dictionary = template.get("family", {}) if template.get("family") is Dictionary else {}
	var named := str(family.get("name", "")).strip_edges()
	if not named.is_empty(): return named
	var surname := str(family.get("surname", "")).strip_edges()
	return surname + "家" if not surname.is_empty() else ""

## Every template file under `root`: [{id, title, template, problems}], by title then id. Unreadable files are listed
## with their problem so the list never hides them.
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

## {ok, template, problems}; ok only when the file exists and parses. A template with problems still loads (ok true).
static func load_template(id: String, root: String = ROOT) -> Dictionary:
	if not valid_id(id): return {"ok": false, "template": {}, "problems": ["範本編號不合法"]}
	var path := root.path_join(id + ".json")
	if not FileAccess.file_exists(path): return {"ok": false, "template": {}, "problems": ["範本檔不存在"]}
	var json := JSON.new() # an instance parse reports a corrupt file here instead of printing an engine error
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {"ok": false, "template": {}, "problems": ["範本檔無法讀取（JSON 損毀）"]}
	var template: Dictionary = json.data
	if template.get("character") is Dictionary: template["character"] = normalized_character(template.character)
	if template.get("version") is float: template["version"] = int(template.version)
	return {"ok": true, "template": template, "problems": problems(template)}

## Writes `template` (refused with its problems when it is not usable). A new id when `id` is "". {ok, id, problems}.
static func save_template(template: Dictionary, id: String = "", root: String = ROOT) -> Dictionary:
	var found := problems(template)
	if not found.is_empty(): return {"ok": false, "id": id, "problems": found}
	if id.is_empty():
		if list(root).size() >= MAX_TEMPLATES: return {"ok": false, "id": "", "problems": ["範本已達 %d 個上限" % MAX_TEMPLATES]}
		id = new_id(root)
	if not valid_id(id): return {"ok": false, "id": id, "problems": ["範本編號不合法"]}
	if DirAccess.make_dir_recursive_absolute(root) != OK and not DirAccess.dir_exists_absolute(root):
		return {"ok": false, "id": id, "problems": ["無法建立範本資料夾"]}
	var file := FileAccess.open(root.path_join(id + ".json"), FileAccess.WRITE)
	if file == null: return {"ok": false, "id": id, "problems": ["無法寫入範本檔"]}
	file.store_string(JSON.stringify(template, "\t", true))
	file.close()
	return {"ok": true, "id": id, "problems": []}

## A copy under a new id titled "<title> 副本" (cut to MAX_TITLE). {ok, id, problems}.
static func copy_template(id: String, root: String = ROOT) -> Dictionary:
	var loaded := load_template(id, root)
	if not loaded.ok: return {"ok": false, "id": "", "problems": loaded.problems}
	var copied: Dictionary = loaded.template.duplicate(true)
	copied["title"] = (str(copied.get("title", "")) + " 副本").left(MAX_TITLE)
	return save_template(copied, "", root)

static func rename_template(id: String, title: String, root: String = ROOT) -> Dictionary:
	var loaded := load_template(id, root)
	if not loaded.ok: return {"ok": false, "id": id, "problems": loaded.problems}
	var renamed: Dictionary = loaded.template.duplicate(true)
	renamed["title"] = title.strip_edges()
	return save_template(renamed, id, root)

## Removes one template file (the editor asks first). {ok, problems}.
static func delete_template(id: String, root: String = ROOT) -> Dictionary:
	if not valid_id(id): return {"ok": false, "problems": ["範本編號不合法"]}
	var path := root.path_join(id + ".json")
	if not FileAccess.file_exists(path): return {"ok": false, "problems": ["範本檔不存在"]}
	if DirAccess.remove_absolute(path) != OK: return {"ok": false, "problems": ["無法刪除範本檔"]}
	return {"ok": true, "problems": []}

static func valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > 40: return false
	for character: String in id:
		if not (character >= "a" and character <= "z" or character >= "0" and character <= "9" or character == "_"): return false
	return true

## "t<unix seconds>_<n>": the first n that is free under `root`.
static func new_id(root: String = ROOT) -> String:
	var stem := "t%d" % int(Time.get_unix_time_from_system())
	var n := 1
	while FileAccess.file_exists(root.path_join("%s_%d.json" % [stem, n])): n += 1
	return "%s_%d" % [stem, n]

static func _normalized_skills(packet: Variant) -> Dictionary:
	if not packet is Dictionary: return {}
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(packet))
	return PersonSkills.normalized(parsed) if PersonSkills.valid(parsed) else parsed

static func _ints(values: Dictionary) -> Dictionary:
	var result := {}
	for key: Variant in values: result[key] = int(values[key]) if values[key] is float else values[key]
	return result

static func _option_ids(options: Array) -> Array[String]:
	var ids: Array[String] = []
	for option: Dictionary in options:
		if str(option.id) != "none": ids.append(str(option.id))
	return ids

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) \
		and float(value) >= low and float(value) <= high
