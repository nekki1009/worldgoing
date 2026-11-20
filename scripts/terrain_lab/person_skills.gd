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
## K1a (reports/skill-k1-implementation.md) adds three optional growth fields, all keyed by line:
## - pending: effective work credited since the last daily settlement (credit()), in whole microseconds so a save and a
##   load keep the exact value (JSON integers);
## - toward: at 80 and above, effective work gathered toward the next yearly roll (3600 effective hours), microseconds;
## - rolls: how many yearly rolls a line has had (the roll seed, so a reload never re-rolls).

const VERSION := 1
const SCALE := 1000
const NEUTRAL := 50000
const MAX_VALUE := 100000
const LINES: Array[String] = ["farming", "gathering", "building", "craft", "medicine", "melee", "archery", "riding"]
const LINE_LABELS := {"farming": "農牧", "gathering": "樵採", "building": "營造", "craft": "工藝", "medicine": "醫護",
	"melee": "近戰", "archery": "弓弩", "riding": "騎乘"}
const MARTIAL: Array[String] = ["melee", "archery", "riding"]
## K3b: 武力 grows like a line (key "ability", §6) but its value lives in the person's combat_ability.
const ABILITY := "ability"
const GROWTH_KEYS: Array[String] = ["farming", "gathering", "building", "craft", "medicine", "melee", "archery", "riding", "ability"]
const ABILITY_PACE := 3.0 # one round of 武力 = 3 full-time years of the same events
const BATTLE_SECONDS := 70.0 * 3600.0 # §5.3: a battle with real exchange counts 70 hours
const WeaponMaterials = preload("res://scripts/ui/weapon_materials.gd")
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
## K1a growth (§5.3, §5.6). Below 80 each effective hour adds RATE x (1 - L/100)^2 x (0.5 + aptitude/100); from 80,
## every YEAR_SECONDS of effective work rolls ROLLS times at aptitude %, +1 for each success, up to 100.
const RATE := 0.0074
const PLATEAU := 80000
const YEAR_SECONDS := 3600.0 * 3600.0
const ROLLS := 5
const MICROS := 1000000.0
const MAX_MICROS := 1000000000000000 # about 31 years of seconds
const MAX_ROLLS := 1000000
const APTITUDE_OF := {"farming": "body", "gathering": "body", "building": "both", "craft": "both", "medicine": "mind",
	"melee": "body", "archery": "body", "riding": "body"}
const FARM_FEATURES: Array[String] = ["farm", "fiber_farm", "fodder_farm", "pasture", "horse_ranch"]
const CRAFT_FEATURES: Array[String] = ["saltworks", "kiln", "charcoal", "smelter", "smithy", "tannery", "weaver"]
const BUILD_FEATURES: Array[String] = ["shipyard"]
## K1c starting values (§5.5): the four work lines start at 30 except the trade's, which is worked from age 15.
const WORK_LINES: Array[String] = ["farming", "gathering", "building", "craft"]
const OTHER_START := 30000
## K1d titles (§5.8): earned when a line reaches 100, kept for life. Keys beyond the eight lines are for K3/K4.
const TITLE_KEYS: Array[String] = ["farming", "gathering", "building", "craft", "medicine", "melee", "archery", "riding",
	"ability", "learning", "tactics", "leadership", "coach"]
const TITLE_NAMES := {"farming": "農神", "gathering": "樵神", "building": "築神", "craft": "匠神", "medicine": "醫神",
	"melee": "戰神", "archery": "箭神", "riding": "騎神", "ability": "武神", "learning": "文曲", "tactics": "謀神",
	"leadership": "軍神", "coach": "兵神"}
const TITLE_PRESTIGE := 5.0
const START_AGE := 15
const TRADE_RATE := 0.5
const SOLDIER_RATE := 0.25
const COMMAND_LABELS := {"tactics": "戰術", "leadership": "統御", "coach": "教練"}
const TECHNOLOGY_LABELS := {"F01": "農事記錄", "F02": "適地留種", "F03": "炭化控火", "F04": "冶煉鍛打", "F05": "纖維處理",
	"F06": "毛紡織造", "F07": "弓作工法", "F08": "弩機裝配", "F09": "丈量放樣", "F10": "木石營造", "F11": "器械木作",
	"F12": "配重機構", "F13": "舟楫工法", "F14": "鞣革", "F15": "引火配方"}

## Strict: version 1 plus optional `lines`, `aptitude`, `pending`, `toward` and `rolls`; never coerces a bad packet.
static func valid(packet: Variant) -> bool:
	if not packet is Dictionary or not _integer(packet.get("version"), VERSION, VERSION): return false
	var extra := 0
	if packet.has("lines"):
		if not _valid_lines(packet.lines): return false
		extra += 1
	if packet.has("aptitude"):
		if not _valid_aptitude(packet.aptitude): return false
		extra += 1
	for field: String in ["pending", "toward", "rolls"]:
		if packet.has(field):
			if not _valid_counts(packet[field], MAX_ROLLS if field == "rolls" else MAX_MICROS): return false
			extra += 1
	if packet.has("start"):
		if not _integer(packet.start, 1, 1): return false
		extra += 1
	if packet.has("titles"):
		if not packet.titles is Array or packet.titles.is_empty(): return false
		var seen := {}
		for key: Variant in packet.titles:
			if not key is String or not TITLE_KEYS.has(key) or seen.has(key): return false
			seen[key] = true
		extra += 1
	return packet.size() == 1 + extra

static func _valid_counts(value: Variant, high: int) -> bool:
	if not value is Dictionary: return false
	for line: Variant in value:
		if not line is String or not GROWTH_KEYS.has(line) or not _integer(value[line], 0, high): return false
	return true

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
	for field: String in ["pending", "toward", "rolls"]:
		if not packet.get(field) is Dictionary: continue
		var values := {}
		for line: String in GROWTH_KEYS:
			if packet[field].has(line): values[line] = int(packet[field][line])
		result[field] = values
	if packet.has("start"): result["start"] = 1
	if packet.get("titles") is Array and not packet.titles.is_empty():
		var titles: Array = []
		for key: Variant in packet.titles: titles.append(str(key))
		result["titles"] = titles
	return result

## Sparse save form: lines at 50 are dropped; empty when nothing differs from the default and no aptitude is stored.
static func saved(packet: Dictionary) -> Dictionary:
	if packet.is_empty() or not valid(packet): return {}
	var result := normalized(packet)
	if result.has("lines"):
		for line: String in LINES:
			if int(result.lines.get(line, NEUTRAL)) == NEUTRAL: result.lines.erase(line)
		if result.lines.is_empty(): result.erase("lines")
	for field: String in ["pending", "toward", "rolls"]:
		if not result.has(field): continue
		for line: String in GROWTH_KEYS:
			if result[field].has(line) and int(result[field][line]) <= 0: result[field].erase(line)
		if result[field].is_empty(): result.erase(field)
	return {} if result.size() == 1 else result

## Read side: the packet of a body (Dictionary row or Actor object); a missing or bad packet reads as empty (all 50).
static func of(body: Variant) -> Dictionary:
	var packet: Variant = null
	if body is Dictionary: packet = body.get("skills")
	elif body is Object and "skills" in body: packet = body.get("skills")
	return normalized(packet) if valid(packet) else {}

## Writes `packet` as the body's packet (a Dictionary row's "skills" or an Actor's `skills`); {} removes it.
static func write(body: Variant, packet: Dictionary) -> void:
	if body is Dictionary:
		if packet.is_empty(): body.erase("skills")
		else: body["skills"] = packet
	elif body is Object and "skills" in body: body.set("skills", packet)

## K1a: the line a work task trains (reports/skill-k1-implementation.md); "" when it trains none.
static func line_for_task(state: Dictionary, task: Dictionary) -> String:
	var action := str(task.get("action", ""))
	if action in ["construct", "repair"]: return "building"
	if action in ["harvest", "clear"]: return "gathering"
	if action == "capture": return "farming"
	var target := str(task.get("target", ""))
	if action != "operate" or not target.begins_with("feature:"): return ""
	var kind := str(state.get("features", {}).get(target.trim_prefix("feature:"), {}).get("kind", ""))
	if FARM_FEATURES.has(kind): return "farming"
	if CRAFT_FEATURES.has(kind): return "craft"
	return "building" if BUILD_FEATURES.has(kind) else ""

## K1a: credits `seconds` of effective work on `line` to the body's pending work, in place (called on hot work paths, so
## it never copies the packet). The daily settlement turns pending work into proficiency.
static func credit(body: Variant, line: String, seconds: float) -> void:
	if body == null or not GROWTH_KEYS.has(line) or not is_finite(seconds) or seconds <= 0.0: return
	var packet: Variant = null
	if body is Dictionary: packet = body.get("skills")
	elif body is Object and "skills" in body: packet = body.get("skills")
	else: return
	if not packet is Dictionary: packet = {}
	if packet.is_empty():
		packet["version"] = VERSION
		write(body, packet)
	var pending: Variant = packet.get("pending")
	if not pending is Dictionary:
		pending = {}
		packet["pending"] = pending
	pending[line] = mini(MAX_MICROS, int(pending.get(line, 0)) + roundi(seconds * MICROS))

## K1b (§5.2): a worker's speed on `line`, 0.5 + proficiency / 100 (x1.0 at 50). A raw read for hot work paths: no
## packet, no line or an unknown line is 1.0.
static func work_factor(body: Variant, line: String) -> float:
	if line.is_empty() or body == null: return 1.0
	var packet: Variant = null
	if body is Dictionary: packet = body.get("skills")
	elif body is Object and "skills" in body: packet = body.get("skills")
	if not packet is Dictionary: return 1.0
	var lines: Variant = packet.get("lines")
	if not lines is Dictionary or not lines.has(line): return 1.0
	return 0.5 + float(clampi(int(lines[line]), 0, MAX_VALUE)) / float(MAX_VALUE)

## K3/K2b (§4, §5.2; Nekki 2026-11-20 A): the native crowd inputs of a person, [melee, riding, ranged, rescue]:
## 武力 + (近戰 / 騎乘 / 弓弩 - 50) x 0.5, clamped 0..100, and his medicine speed. Ordinary soldiers fight at 50 (Q5 A:
## no personal martial for them); everyone's medicine counts.
static func combat_inputs(body: Variant) -> Array:
	if body == null: return [50.0, 50.0, 50.0, 1.0]
	var role: Variant = body.get("military_role")
	var result: Array = [50.0, 50.0, 50.0]
	if str(role) != "soldier":
		var raw: Variant = body.get("combat_ability")
		var ability := clampf(float(raw), 0.0, 100.0) if raw is float or raw is int else 50.0
		var packet := of(body)
		result = []
		for line: String in ["melee", "riding", "archery"]: result.append(clampf(ability + (level(packet, line) - 50.0) * 0.5, 0.0, 100.0))
	result.append(work_factor(body, "medicine"))
	return result

## The aptitude that governs `line`: 根骨, 悟性, or their average for building and craft (§5.6).
static func talent_for(aptitude_values: Dictionary, line: String) -> float:
	var kind := str(APTITUDE_OF.get(line, "body"))
	if kind == "both": return (float(aptitude_values.get("body", APTITUDE_MEAN)) + float(aptitude_values.get("mind", APTITUDE_MEAN))) * 0.5
	return float(aptitude_values.get(kind, APTITUDE_MEAN))

## Effective seconds that take a line from `from_milli` to `to_milli` below the plateau (closed form of §5.3).
static func seconds_between(from_milli: int, to_milli: int, talent: float) -> float:
	var rate := RATE * (0.5 + talent / 100.0)
	return (1.0 / (1.0 - float(to_milli) / 100000.0) - 1.0 / (1.0 - float(from_milli) / 100000.0)) * 100.0 / rate * 3600.0

## One yearly roll from 80 (§5.3): ROLLS draws at `talent` %, fixed by the world seed, the person, the line and the count.
static func yearly_gain(seed_value: int, identity: int, line: String, count: int, talent: float) -> int:
	var gain := 0
	for draw: int in range(ROLLS):
		if float(posmod(hash([seed_value, identity, "skill_roll", line, count, draw]), 1000000)) < talent * 10000.0: gain += 1
	return gain

## K1a daily settlement: turns the pending work into proficiency and returns the new sparse packet. Below 80 the line
## grows by the closed-form curve to the last whole thousandth it reaches; the seconds not yet worth one thousandth stay
## pending. From 80 the seconds gather in `toward`, and every full year of them rolls once.
static func settle(packet: Dictionary, seed_value: int, identity: int) -> Dictionary:
	var result := normalized(packet) if valid(packet) else {"version": VERSION}
	var pending: Dictionary = result.get("pending", {})
	if pending.is_empty(): return saved(result)
	var talents := aptitude(result, seed_value, identity)
	var lines: Dictionary = result.get("lines", {})
	var toward: Dictionary = result.get("toward", {})
	var rolls: Dictionary = result.get("rolls", {})
	var left := {}
	if pending.has(ABILITY): left[ABILITY] = int(pending[ABILITY]) # 武力 settles in settle_ability()
	for line: String in LINES:
		if not pending.has(line): continue
		var seconds := float(pending[line]) / MICROS
		var talent := talent_for(talents, line)
		var milli := int(lines.get(line, NEUTRAL))
		if milli < PLATEAU:
			var rate := RATE * (0.5 + talent / 100.0)
			var u := 1.0 / (1.0 / (1.0 - float(milli) / 100000.0) + rate * seconds / 3600.0 / 100.0)
			var reached := mini(PLATEAU, floori(100000.0 * (1.0 - u)))
			seconds = maxf(0.0, seconds - seconds_between(milli, reached, talent))
			milli = reached
			if milli < PLATEAU:
				if floori(seconds * MICROS) > 0: left[line] = floori(seconds * MICROS)
				lines[line] = milli
				continue
		if milli < MAX_VALUE:
			var gathered := float(toward.get(line, 0)) / MICROS + seconds
			while gathered >= YEAR_SECONDS and milli < MAX_VALUE:
				var count := int(rolls.get(line, 0))
				milli = mini(MAX_VALUE, milli + SCALE * yearly_gain(seed_value, identity, line, count, talent))
				rolls[line] = count + 1
				gathered -= YEAR_SECONDS
			toward[line] = mini(MAX_MICROS, floori(gathered * MICROS)) if milli < MAX_VALUE else 0
		if milli >= MAX_VALUE: _earn_title(result, line)
		lines[line] = milli
	if lines.is_empty(): result.erase("lines") # only 武力 was pending: no line to store (an empty lines map is invalid)
	else: result["lines"] = lines
	result["pending"] = left
	result["toward"] = toward
	result["rolls"] = rolls
	return saved(result)

## K1c (§5.5): the starting packet of a person met at world creation, aged `age`. The four work lines he has no value
## for start at 30; each line in `trades` starts at 0 and is worked `rate` of a full-time year every year from 15, run
## through settle() (curve, aptitude and the yearly rolls from 80). Marks the packet `start` so it is seeded once.
static func initial(packet: Dictionary, age: int, trades: Array, rate: float, seed_value: int, identity: int) -> Dictionary:
	var result := normalized(packet) if valid(packet) else {"version": VERSION}
	var lines: Dictionary = result.get("lines", {})
	var pending: Dictionary = result.get("pending", {})
	var worked := roundi(float(maxi(0, age - START_AGE)) * rate * YEAR_SECONDS * MICROS)
	for line: String in WORK_LINES:
		if lines.has(line): continue
		if trades.has(line):
			lines[line] = 0
			if worked > 0: pending[line] = mini(MAX_MICROS, int(pending.get(line, 0)) + worked)
		else: lines[line] = OTHER_START
	result["lines"] = lines
	result["pending"] = pending
	result["start"] = 1
	return settle(result, seed_value, identity)

## K1d (§5.8): records the title of `key` once, in the order earned.
static func _earn_title(result: Dictionary, key: String) -> void:
	var titles: Array = result.get("titles", [])
	if titles.has(key): return
	titles.append(key)
	result["titles"] = titles

## Titles earned, in order (§5.8: a list shows the first, the skills page all of them).
static func titles_of(packet: Dictionary) -> Array:
	return packet.get("titles", []).duplicate() if packet.get("titles") is Array else []

## K1d (§5.4): the New Year decline of `points` (the drop of his age base) on every line he has, never below 0.
static func age_decline(packet: Dictionary, points: float) -> Dictionary:
	if not valid(packet): return {}
	var result := normalized(packet)
	if points <= 0.0 or not result.get("lines") is Dictionary: return saved(result)
	var loss := roundi(points * SCALE)
	for line: String in result.lines.keys(): result.lines[line] = maxi(0, int(result.lines[line]) - loss)
	return saved(result)

## K3b (§6): 武力's growth. `ability` is his combat_ability (0..100); the pending "ability" work grows it on the §5.3
## curve at a third of the pace (aptitude: 根骨), and from 80 one roll per 3 years' worth. Returns {packet, ability}.
static func settle_ability(packet: Dictionary, ability: float, seed_value: int, identity: int) -> Dictionary:
	var result := normalized(packet) if valid(packet) else {"version": VERSION}
	var pending: Dictionary = result.get("pending", {})
	if not pending.has(ABILITY): return {"packet": saved(result), "ability": ability}
	var seconds := float(pending[ABILITY]) / MICROS / ABILITY_PACE
	pending.erase(ABILITY)
	var talent := float(aptitude(result, seed_value, identity).body)
	var milli := clampi(roundi(ability * float(SCALE)), 0, MAX_VALUE)
	var start_milli := milli
	if milli < PLATEAU:
		var rate := RATE * (0.5 + talent / 100.0)
		var u := 1.0 / (1.0 / (1.0 - float(milli) / 100000.0) + rate * seconds / 3600.0 / 100.0)
		var reached := mini(PLATEAU, maxi(milli, floori(100000.0 * (1.0 - u))))
		seconds = maxf(0.0, seconds - seconds_between(milli, reached, talent))
		milli = reached
		if milli < PLATEAU:
			if floori(seconds * ABILITY_PACE * MICROS) > 0: pending[ABILITY] = floori(seconds * ABILITY_PACE * MICROS)
			seconds = 0.0
	if milli >= PLATEAU and milli < MAX_VALUE and seconds > 0.0:
		var toward: Dictionary = result.get("toward", {})
		var rolls: Dictionary = result.get("rolls", {})
		var gathered := float(toward.get(ABILITY, 0)) / MICROS + seconds
		while gathered >= YEAR_SECONDS and milli < MAX_VALUE:
			var count := int(rolls.get(ABILITY, 0))
			milli = mini(MAX_VALUE, milli + SCALE * yearly_gain(seed_value, identity, ABILITY, count, talent))
			rolls[ABILITY] = count + 1
			gathered -= YEAR_SECONDS
		toward[ABILITY] = mini(MAX_MICROS, floori(gathered * MICROS)) if milli < MAX_VALUE else 0
		result["toward"] = toward
		result["rolls"] = rolls
	if milli >= MAX_VALUE: _earn_title(result, ABILITY)
	result["pending"] = pending
	# Below 80 the curve only reaches whole thousandths; keep the stored value when it did not move.
	return {"packet": saved(result), "ability": float(milli) / float(SCALE) if milli != start_milli else ability}

## K3b: the martial line a person fights on: 弓弩 with a bow or crossbow, 騎乘 when mounted, else 近戰.
static func martial_line(body: Variant) -> String:
	var appearance: Variant = null
	if body is Dictionary: appearance = body.get("appearance")
	elif body is Object: appearance = body.get("_saved_appearance")
	if not appearance is Dictionary: return "melee"
	var weapon := str(appearance.get("parts", {}).get("weapon", "none"))
	if str(WeaponMaterials.family(StringName(weapon))).contains("bow"): return "archery"
	return "riding" if bool(appearance.get("mounted", false)) else "melee"

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
	var sections: Array = [{"title": "資質", "rows": talent}, {"title": "技能", "rows": lines}, {"title": "武力・學業・統率", "rows": abilities},
		{"title": "工法", "rows": techniques}]
	var titles: Array = []
	for key: Variant in titles_of(packet): titles.append([str(TITLE_NAMES.get(str(key), "")), str(LINE_LABELS.get(str(key), key)) + " 100"])
	if not titles.is_empty(): sections.insert(0, {"title": "名號", "rows": titles})
	return sections

static func _number(value: float) -> String:
	return str(int(value)) if value == floorf(value) else "%.1f" % value

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) \
		and float(value) >= low and float(value) <= high
