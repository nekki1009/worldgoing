extends SceneTree
## The character template library (開局流程規劃 §2, scripts/main_menu/character_templates.gd), headless and file-level.
## Checks, in a scratch folder under user://:
## - a default character (four abilities 50, 學業 0, lines and aptitudes 50) is a usable template; it saves, lists and
##   loads back equal (JSON floats become integers again);
## - over 200 points is a problem unless the template was made with 自由分配; a missing face part, a bad name, a broken
##   personality and a malformed skills packet are listed as problems, and a template with problems is not saved;
## - copy, rename and delete; a corrupt file is listed with its problem, not hidden; ids are checked;
## - the family blueprint: the name, else "<姓氏>家".
## Output: CHARACTER_TEMPLATES_PASS on success; quit(1) on failure.

const Templates = preload("res://scripts/main_menu/character_templates.gd")
const PersonPersonality = preload("res://scripts/terrain_lab/person_personality.gd")
const Skills = preload("res://scripts/terrain_lab/person_skills.gd")
const ROOT := "user://character_templates_test"

var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("CHARACTER_TEMPLATES OK ", checks, ": ", message)
		return true
	push_error("CHARACTER_TEMPLATES_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _character() -> Dictionary:
	var face := ""
	for option: Dictionary in HumanCharacter3DEditor.PART_SLOTS[0].options:
		if str(option.id) != "none" and face.is_empty(): face = str(option.id)
	var hair := ""
	for option: Dictionary in HumanCharacter3DEditor.HAIR_OPTIONS[0]:
		if str(option.id) != "none" and hair.is_empty(): hair = str(option.id)
	var personality := PersonPersonality.neutral()
	personality.risk = 80
	return {"name": "林範本", "body": 0, "face": face, "hair": hair, "hair_dye": "9b775dff", "hair_dyed": false,
		"combat_ability": 50, "command_abilities": {"tactics": 50, "leadership": 50, "coach": 50}, "personality": personality,
		"learning": 0, "skills": Skills.start_packet({"farming": 40}, {"body": 60, "mind": 50}), "free_points": false}

func _clear() -> void:
	var directory := DirAccess.open(ROOT)
	if directory == null: return
	for file: String in directory.get_files(): DirAccess.remove_absolute(ROOT.path_join(file))

func _run() -> void:
	_clear()
	var plain := Templates.make("農家子弟", _character(), {"surname": "林", "name": ""})
	if not _ok(Templates.problems(plain).is_empty(), "a 200-point character is a usable template", Templates.problems(plain)): return
	var saved := Templates.save_template(plain, "", ROOT)
	if not _ok(saved.ok and Templates.valid_id(str(saved.id)), "it saves under a new id", saved): return
	var loaded := Templates.load_template(str(saved.id), ROOT)
	if not _ok(loaded.ok and loaded.problems.is_empty() and loaded.template.character == plain.character and loaded.template.family == plain.family, "it loads back equal, numbers as integers", [loaded, plain]): return
	if not _ok(loaded.template.character.combat_ability is int and loaded.template.character.skills.lines.farming is int, "JSON floats are integers again", loaded.template.character): return
	# Budget: 武力 90 is 240 points.
	var strong := _character()
	strong.combat_ability = 90
	var over := Templates.make("猛將", strong)
	var listed := Templates.problems(over)
	if not _ok(listed.size() == 1 and "240" in listed[0], "over 200 points is a problem", listed): return
	if not _ok(not Templates.save_template(over, "", ROOT).ok, "a template with problems is not saved"): return
	strong.free_points = true
	if not _ok(Templates.problems(Templates.make("猛將", strong)).is_empty(), "made with 自由分配 it is usable"): return
	var broken := _character()
	broken.face = "face_does_not_exist"
	broken.name = ""
	broken.personality = {"risk": 50}
	broken.skills = {"version": 1, "lines": {"farming": 100001}}
	var issues := Templates.problems(Templates.make("壞範本", broken))
	if not _ok(issues.size() == 4, "a missing face part, an empty name, a broken personality and a bad skills packet are each listed", issues): return
	if not _ok(not Templates.problems({"version": 2}).is_empty() and not Templates.problems(Templates.make("", _character())).is_empty(), "a wrong version and an empty title are problems"): return
	# Copy, rename, delete; a corrupt file.
	var copied := Templates.copy_template(str(saved.id), ROOT)
	var renamed := Templates.rename_template(str(saved.id), "林家長子", ROOT)
	var file := FileAccess.open(ROOT.path_join("t1_9.json"), FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	var rows := Templates.list(ROOT)
	var titles: Array = rows.map(func(row: Dictionary) -> String: return str(row.title))
	var corrupt: Array = rows.filter(func(row: Dictionary) -> bool: return str(row.id) == "t1_9")
	if not _ok(copied.ok and renamed.ok and rows.size() == 3 and titles.has("林家長子") and titles.has("農家子弟 副本"), "copy and rename", [copied, renamed, titles]): return
	if not _ok(corrupt.size() == 1 and not corrupt[0].problems.is_empty(), "a corrupt file is listed with its problem", corrupt): return
	if not _ok(Templates.delete_template(str(copied.id), ROOT).ok and Templates.list(ROOT).size() == 2 and not Templates.delete_template(str(copied.id), ROOT).ok, "delete removes one file, once"): return
	if not _ok(not Templates.valid_id("../x") and not Templates.valid_id("") and not Templates.load_template("../x", ROOT).ok, "ids are checked"): return
	# Family blueprint.
	if not _ok(Templates.family_name_of(plain) == "林家" and Templates.family_name_of(Templates.make("x", _character(), {"surname": "林", "name": "西河林氏"})) == "西河林氏" and Templates.family_name_of(Templates.make("x", _character())).is_empty(), "the family name: the blueprint's, else <姓氏>家, else none"): return
	_clear()
	print("CHARACTER_TEMPLATES_PASS checks=", checks)
	quit(0)
