extends RefCounted
## Skill packet (技能系統 K0, reports/skill-system-plan.md V0.7 §4, §5.1, §5.6, §8). A sparse `skills` packet on the
## person that travels the same path as the personality packet (Actor state, Army rows, Crowd cold rows, SiteStore
## validation), so it follows the person through team changes, captivity, travel and save/load:
##   {version: 1, lines?: {line: 0..100000}, aptitude?: {body: 0..100, mind: 0..100}}
## - lines: proficiency of each of the eight lines in thousandths (50000 = 50, the current behaviour). A missing line
##   reads as 50 and only lines that differ from 50 are stored.
## - aptitude: 根骨 (body) and 悟性 (mind). People met at world creation never store it: it is derived from the world
##   seed and the person id (normal, mean 50, sd 15, clamped 0..100), like TC7 age. Only people born in play store it.
## K0 only carries and shows the data: nothing reads a line for speed or ability yet, so behaviour is unchanged.

const VERSION := 1
const SCALE := 1000
const NEUTRAL := 50000
const MAX_VALUE := 100000
const LINES: Array[String] = ["farming", "gathering", "building", "craft", "medicine", "melee", "archery", "riding"]
const LINE_LABELS := {"farming": "農牧", "gathering": "樵採", "building": "營造", "craft": "工藝", "medicine": "醫護",
	"melee": "近戰", "archery": "弓弩", "riding": "騎乘"}
const MARTIAL: Array[String] = ["melee", "archery", "riding"]
const LEVEL_GRADES: Array[String] = ["生手", "學徒", "熟手", "老手", "名手"]
const APTITUDES: Array[String] = ["body", "mind"]
const APTITUDE_LABELS := {"body": "根骨", "mind": "悟性"}
const APTITUDE_GRADES := {"body": ["孱弱", "單薄", "尋常", "強健", "魁偉"], "mind": ["愚鈍", "遲鈍", "尋常", "聰穎", "奇才"]}
const APTITUDE_MEAN := 50
const APTITUDE_SD := 15
## Irwin-Hall: the sum of 12 uniform draws in 0..999 has mean 5994 and sd ~1000, an integer-only normal approximation
## so the derivation never depends on float transcendental functions.
const NORMAL_DRAWS := 12
const NORMAL_SPAN := 1000
const NORMAL_MEAN_SUM := 5994
const COMMAND_LABELS := {"tactics": "戰術", "leadership": "統御", "coach": "教練"}
const TECHNOLOGY_LABELS := {"F01": "農事記錄", "F02": "適地留種", "F03": "炭化控火", "F04": "冶煉鍛打", "F05": "纖維處理",
	"F06": "毛紡織造", "F07": "弓作工法", "F08": "弩機裝配", "F09": "丈量放樣", "F10": "木石營造", "F11": "器械木作",
	"F12": "配重機構", "F13": "舟楫工法", "F14": "鞣革", "F15": "引火配方"}

## Strict: version 1 plus optional `lines` and `aptitude`; never coerces a bad packet.
static func valid(packet: Variant) -> bool:
	if not packet is Dictionary or not _integer(packet.get("version"), VERSION, VERSION): return false
	var extra := 0
	if packet.has("lines"):
		if not _valid_lines(packet.lines): return false
		extra += 1
	if packet.has("aptitude"):
		if not _valid_aptitude(packet.aptitude): return false
		extra += 1
	return packet.size() == 1 + extra

static func _valid_lines(lines: Variant) -> bool:
	if not lines is Dictionary or lines.is_empty(): return false
	for line: Variant in lines:
		if not line is String or not LINES.has(line) or not _integer(lines[line], 0, MAX_VALUE): return false
	return true

static func _valid_aptitude(value: Variant) -> bool:
	if not value is Dictionary or value.size() != APTITUDES.size(): return false
	for kind: String in APTITUDES:
		if not _integer(value.get(kind), 0, 100): return false
	return true

static func normalized(packet: Dictionary) -> Dictionary:
	var result := {"version": VERSION}
	if packet.get("lines") is Dictionary:
		var lines := {}
		for line: String in LINES:
			if packet.lines.has(line): lines[line] = int(packet.lines[line])
		if not lines.is_empty(): result["lines"] = lines
	if packet.get("aptitude") is Dictionary:
		result["aptitude"] = {"body": int(packet.aptitude.body), "mind": int(packet.aptitude.mind)}
	return result

## Sparse save form: lines at 50 are dropped; empty when nothing differs from the default and no aptitude is stored.
static func saved(packet: Dictionary) -> Dictionary:
	if packet.is_empty() or not valid(packet): return {}
	var result := normalized(packet)
	if result.has("lines"):
		for line: String in LINES:
			if int(result.lines.get(line, NEUTRAL)) == NEUTRAL: result.lines.erase(line)
		if result.lines.is_empty(): result.erase("lines")
	return {} if result.size() == 1 else result

## Read side: the packet of a body (Dictionary row or Actor object); a missing or bad packet reads as empty (all 50).
static func of(body: Variant) -> Dictionary:
	var packet: Variant = null
	if body is Dictionary: packet = body.get("skills")
	elif body is Object and "skills" in body: packet = body.get("skills")
	return normalized(packet) if valid(packet) else {}

## Proficiency of `line` in thousandths (50000 when not stored).
static func level_milli(packet: Dictionary, line: String) -> int:
	return int(packet.get("lines", {}).get(line, NEUTRAL))

static func level(packet: Dictionary, line: String) -> float:
	return float(level_milli(packet, line)) / float(SCALE)

## A new sparse packet with `line` set to `milli` (clamped 0..100000); {} when it ends up all default.
static func with_level(packet: Dictionary, line: String, milli: int) -> Dictionary:
	if not LINES.has(line): return saved(packet)
	var result := normalized(packet) if valid(packet) else {"version": VERSION}
	var lines: Dictionary = result.get("lines", {})
	lines[line] = clampi(milli, 0, MAX_VALUE)
	result["lines"] = lines
	return saved(result)

## The world seed for aptitude, from the Region world instance (same source as the TC7 vital seed).
static func world_seed(world_instance_id: String) -> int:
	return hash(["worldgoing_aptitude", world_instance_id])

## Derived aptitude for a person met at world creation: normal(50, 15) clamped 0..100, from the seed and the id.
static func derived_aptitude(seed_value: int, identity: int, kind: String) -> int:
	var total := 0
	for draw: int in range(NORMAL_DRAWS):
		total += posmod(hash([seed_value, identity, "aptitude", kind, draw]), NORMAL_SPAN)
	var scaled := APTITUDE_MEAN * NORMAL_SPAN + APTITUDE_SD * (total - NORMAL_MEAN_SUM)
	return clampi(floori(float(scaled) / float(NORMAL_SPAN) + 0.5), 0, 100)

## {body, mind}: the stored aptitude (born in play) or the derived one.
static func aptitude(packet: Dictionary, seed_value: int, identity: int) -> Dictionary:
	if packet.get("aptitude") is Dictionary and _valid_aptitude(packet.aptitude):
		return {"body": int(packet.aptitude.body), "mind": int(packet.aptitude.mind), "stored": true}
	return {"body": derived_aptitude(seed_value, identity, "body"), "mind": derived_aptitude(seed_value, identity, "mind"), "stored": false}

## A new packet that stores `values` {body, mind} as this person's aptitude (people born in play).
static func with_aptitude(packet: Dictionary, values: Dictionary) -> Dictionary:
	var stored := {"body": int(values.get("body", -1)), "mind": int(values.get("mind", -1))}
	if not _valid_aptitude(stored): return saved(packet)
	var result := normalized(packet) if valid(packet) else {"version": VERSION}
	result["aptitude"] = stored
	return saved(result)

static func _band(value: float) -> int:
	return clampi(floori(value / 20.0), 0, 4)

## 生手／學徒／熟手／老手／名手; 80+ reads 名匠 for craft and 精通 for the martial lines.
static func level_grade(line: String, value: float) -> String:
	var band := _band(value)
	if band < 4: return LEVEL_GRADES[band]
	if line == "craft": return "名匠"
	return "精通" if MARTIAL.has(line) else LEVEL_GRADES[4]

static func aptitude_grade(kind: String, value: int) -> String:
	return str(APTITUDE_GRADES.get(kind, LEVEL_GRADES)[_band(float(value))])

## The skills page (人物頁「技能」): sections of [label, text] rows. `learned` is the person's learned F ids.
static func page(packet: Dictionary, aptitude_values: Dictionary, combat_ability: float, learning: int, command: Dictionary, learned: Array) -> Array:
	var talent: Array = []
	for kind: String in APTITUDES:
		var value := int(aptitude_values.get(kind, APTITUDE_MEAN))
		talent.append([str(APTITUDE_LABELS[kind]), "%d %s" % [value, aptitude_grade(kind, value)]])
	var lines: Array = []
	for line: String in LINES:
		var value := level(packet, line)
		lines.append([str(LINE_LABELS[line]), "%s %s" % [_number(value), level_grade(line, value)]])
	var abilities: Array = [["武力", _number(combat_ability)], ["學業", str(learning)]]
	for kind: String in COMMAND_LABELS:
		abilities.append([str(COMMAND_LABELS[kind]), str(int(command[kind])) if command.has(kind) else "未任命"])
	var techniques: Array = []
	for tech_id: Variant in learned:
		techniques.append([str(tech_id), str(TECHNOLOGY_LABELS.get(str(tech_id), ""))])
	if techniques.is_empty(): techniques.append(["工法", "尚未學會"])
	return [{"title": "資質", "rows": talent}, {"title": "技能", "rows": lines}, {"title": "武力・學業・統率", "rows": abilities},
		{"title": "工法", "rows": techniques}]

static func _number(value: float) -> String:
	return str(int(value)) if value == floorf(value) else "%.1f" % value

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) \
		and float(value) >= low and float(value) <= high
