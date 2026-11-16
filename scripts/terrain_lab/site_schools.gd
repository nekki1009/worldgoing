extends RefCounted
## Schools (考試學校 E1, reports/exam-and-school-plan.md §3–§4, §6, §9; Nekki 11/09 all A). A completed school seats a
## teacher and students named by the settlement's 學正 (settlement.education; the head acts while it is vacant). While
## the teacher and at least one student stand beside the door, ready, idle and not in combat, their shared seconds are
## lessons: every LESSON_SECONDS each present student gains 1 learning up to the school's cap. Each teacher is paid
## 1 grain a game day from the camp stock; an unpaid teacher teaches nothing that day. Learning lives in the person's
## social packet (PersonSocial `learning`), so it follows him. Missing art refuses the building (MISSING_ART); this file
## only works on schools that exist.
## Record per school feature: {version, teachers: [id], students: [id], paid_day, paid: [id], lesson: seconds,
## last_exam_day, exam}. `exam` is {} or the running exam {host, candidates: [id], elapsed, kind}.
## 考試學校 E2 (§5): the 學正 (or acting head) opens a 鄉試 at a 鄉學: EXAM_SECONDS of effective time with him at the
## door; the grain fee is paid at the start and refunded if he leaves (the exam is cancelled). Candidates: literate,
## no civil role, same faction, inside the jurisdiction, not examined in the last 30 days; at most twice the student
## seats. score = learning × 0.6 + mean(tactics, leadership, coach) × 0.2 + (diligence − 50) × 0.2 + roll(−10..10);
## 鄉試 passes at 60 → 文吏. The roll is fixed by the seed, the person and the day.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")

const VERSION := 1
const DAY_MINUTES := 1440
const LESSON_SECONDS := 300.0
const GRAIN_PER_DAY := 1
const DUTY := "settlement.education"
const PersonPersonality = preload("res://scripts/terrain_lab/person_personality.gd")
const EXAM_SECONDS := 300.0
## Exam kinds (§5.1): where, the fee, the school cooldown, the pass mark and the role it gives.
const EXAMS := {
	"district": {"school": "district_school", "fee": 5, "cooldown_days": 60, "pass": 60.0, "role": "clerk"},
	"state": {"school": "state_academy", "fee": 15, "cooldown_days": 120, "pass": 75.0, "role": "official"},
}
const PERSON_COOLDOWN_DAYS := 30
## Kind → seats, the learning cap, the settlement level it needs and the teacher's minimum (§3, §4.2).
const KINDS := {
	"village_school": {"teachers": 1, "students": 4, "cap": 40, "min_settlement_level": 2, "teacher_learning": 40, "teacher_role": "clerk"},
	"district_school": {"teachers": 1, "students": 6, "cap": 70, "min_settlement_level": 3, "teacher_learning": 70, "teacher_role": "clerk"},
	"state_academy": {"teachers": 2, "students": 8, "cap": 100, "min_settlement_level": 4, "teacher_learning": 80, "teacher_role": "official"},
}

static func empty_record() -> Dictionary:
	return {"version": VERSION, "teachers": [], "students": [], "paid_day": -1, "paid": [], "lesson": 0.0, "last_exam_day": -1, "exam": {}}

static func records(data: TerrainData) -> Dictionary:
	var value: Variant = data.site.get("schools", {}) if data != null else {}
	return value if value is Dictionary else {}

static func spec_of(data: TerrainData, key: String) -> Dictionary:
	return KINDS.get(str(data.site.get("features", {}).get(key, {}).get("kind", "")), {})

## Strict save validation. `people` holds the valid person ids of the state being checked.
static func validate(state: Dictionary, people: Dictionary) -> Dictionary:
	var raw: Variant = state.get("schools", {})
	if not raw is Dictionary: return Runtime.fail("CORRUPT_SAVE", "學校欄位")
	var everyone := {}
	for key: Variant in raw:
		var feature: Variant = state.get("features", {}).get(key, {}) if key is String else null
		if not feature is Dictionary or not KINDS.has(str(feature.get("kind", ""))): return Runtime.fail("CORRUPT_SAVE", "學校引用不存在")
		var record: Variant = raw[key]
		if not record is Dictionary or record.size() != 8 or int(record.get("version", 0)) != VERSION: return Runtime.fail("CORRUPT_SAVE", "學校版本")
		if not (record.get("last_exam_day") is int or record.get("last_exam_day") is float) or int(record.last_exam_day) < -1 or not record.get("exam") is Dictionary: return Runtime.fail("CORRUPT_SAVE", "學校考試")
		if not record.exam.is_empty():
			var exam: Dictionary = record.exam
			if exam.size() != 4 or not EXAMS.has(str(exam.get("kind", ""))) or not exam.get("candidates") is Array or not (exam.get("host") is int or exam.get("host") is float) or not people.has(int(exam.host)) \
				or not (exam.get("elapsed") is int or exam.get("elapsed") is float) or float(exam.elapsed) < 0.0 or float(exam.elapsed) >= EXAM_SECONDS: return Runtime.fail("CORRUPT_SAVE", "學校考試")
		var spec: Dictionary = KINDS[str(feature.kind)]
		if not record.get("teachers") is Array or record.teachers.size() > int(spec.teachers) or not record.get("students") is Array or record.students.size() > int(spec.students) or not record.get("paid") is Array:
			return Runtime.fail("CORRUPT_SAVE", "學校席位")
		var seen := {}
		for identity: Variant in record.teachers + record.students:
			if not (identity is int or identity is float) or float(identity) != floorf(float(identity)) or seen.has(int(identity)) or everyone.has(int(identity)) or not people.has(int(identity)):
				return Runtime.fail("CORRUPT_SAVE", "學校師生不存在或重複")
			seen[int(identity)] = true
			everyone[int(identity)] = true
		for identity: Variant in record.paid:
			if not record.teachers.has(identity) and not record.teachers.has(int(identity)): return Runtime.fail("CORRUPT_SAVE", "已領糧者不是老師")
		if not (record.paid_day is int or record.paid_day is float) or int(record.paid_day) < -1: return Runtime.fail("CORRUPT_SAVE", "學校領糧日")
		var lesson: Variant = record.get("lesson")
		if not (lesson is int or lesson is float) or not is_finite(float(lesson)) or float(lesson) < 0.0 or float(lesson) >= LESSON_SECONDS: return Runtime.fail("CORRUPT_SAVE", "學校課時")
	return Runtime.ok()

static func normalize(state: Dictionary) -> void:
	var raw: Variant = state.get("schools", {})
	if not raw is Dictionary: return
	for record: Variant in raw.values():
		if not record is Dictionary: continue
		record["version"] = int(record.get("version", 0))
		record["paid_day"] = int(record.get("paid_day", -1))
		record["lesson"] = float(record.get("lesson", 0.0))
		record["last_exam_day"] = int(record.get("last_exam_day", -1))
		if record.get("exam") is Dictionary and not record.exam.is_empty():
			record.exam["host"] = int(record.exam.get("host", -1))
			record.exam["elapsed"] = float(record.exam.get("elapsed", 0.0))
			if record.exam.get("candidates") is Array:
				for index: int in record.exam.candidates.size(): record.exam.candidates[index] = int(record.exam.candidates[index])
		for field: String in ["teachers", "students", "paid"]:
			if record.get(field) is Array:
				for index: int in record[field].size(): record[field][index] = int(record[field][index])

static func is_seated(data: TerrainData, identity: int) -> bool:
	for record: Dictionary in records(data).values():
		if record.teachers.has(identity) or record.students.has(identity): return true
	return false

## Why `identity` may not teach at school `key` ("" when he may): the civil track and learning of §4.2.
static func teacher_refusal(data: TerrainData, key: String, body: Variant) -> String:
	var spec := spec_of(data, key)
	if spec.is_empty(): return "不是學校"
	var role := PersonSocial.civil_role(body)
	if PersonSocial.civil_rank(role) < PersonSocial.civil_rank(str(spec.teacher_role)): return "老師須為%s" % ("文官" if str(spec.teacher_role) == "official" else "文吏以上")
	if PersonSocial.learning(body) < int(spec.teacher_learning): return "老師學業須達 %d" % int(spec.teacher_learning)
	return ""

## Seats or unseats a teacher or student. Authority, faction and jurisdiction are checked by the caller.
static func set_seat(data: TerrainData, key: String, identity: int, body: Variant, role: String, seated: bool) -> Dictionary:
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	var spec := spec_of(data, key)
	if spec.is_empty() or str(feature.get("stage", "")) != "complete" or not Runtime.feature_usable(feature): return Runtime.fail("NO_TARGET", "須是完工可用的學校")
	if role not in ["teacher", "student"]: return Runtime.fail("INVALID")
	if not data.site.has("schools"): data.site["schools"] = {}
	var record: Dictionary = data.site.schools.get(key, empty_record())
	var field := "teachers" if role == "teacher" else "students"
	var seats: Array = record[field]
	if not seated:
		if not seats.has(identity): return Runtime.fail("NO_TARGET")
		seats.erase(identity)
		record.paid.erase(identity)
		data.site.schools[key] = record
		return Runtime.ok("已離席")
	if seats.has(identity): return Runtime.ok("已在席")
	if is_seated(data, identity): return Runtime.fail("BUSY", "此人已在學校任教或就讀")
	if seats.size() >= int(spec.get(field, 0)): return Runtime.fail("LIMIT", "席位已滿")
	if role == "teacher":
		var why := teacher_refusal(data, key, body)
		if not why.is_empty(): return Runtime.fail("NOT_ELIGIBLE", why)
	elif PersonSocial.learning(body) >= int(spec.cap): return Runtime.fail("LIMIT", "學業已達本校上限 %d" % int(spec.cap))
	seats.append(identity)
	data.site.schools[key] = record
	data.environment_revision += 1
	return Runtime.ok("已入席")

## One accepted game interval. `actions` is the Site's PersonActions (person reads only).
static func advance(data: TerrainData, actions: Variant, seconds: float) -> Dictionary:
	var taught := {}
	if data == null or actions == null or not is_finite(seconds) or seconds <= 0.0 or records(data).is_empty(): return taught
	if float(data.site.get("combat_left", 0.0)) > 0.0: return taught # §4.4: the whole Site in combat cancels lessons
	var day := int(int(data.site.get("minute", 0)) / DAY_MINUTES)
	var keys: Array = records(data).keys()
	keys.sort()
	for key: String in keys:
		var feature: Dictionary = data.site.get("features", {}).get(key, {})
		var record: Dictionary = records(data)[key]
		var spec := spec_of(data, key)
		if spec.is_empty() or str(feature.get("stage", "")) != "complete" or not Runtime.feature_usable(feature): continue
		if int(record.paid_day) != day:
			record["paid_day"] = day
			record["paid"] = []
			for identity: int in record.teachers:
				var stock: Dictionary = data.site.get("inventory", {})
				if int(stock.get("grain", 0)) < GRAIN_PER_DAY: break
				stock["grain"] = int(stock.grain) - GRAIN_PER_DAY
				if data.site.get("depot_items") is Dictionary: data.site.depot_items["version"] = int(data.site.depot_items.version) + 1
				record.paid.append(identity)
		var entrance: Vector2i = data.cell_from_index(int(feature.get("entrance", -1)))
		if not record.exam.is_empty(): _advance_exam(data, actions, key, record, entrance, seconds, taught)
		var teacher_here := false
		for identity: int in record.paid:
			if _present(actions, identity, entrance): teacher_here = true
		if not teacher_here: continue
		var students: Array[Dictionary] = []
		for identity: int in record.students:
			if not _present(actions, identity, entrance): continue
			var person: Dictionary = actions._person(identity, false)
			if PersonSocial.learning(person.body) < int(spec.cap): students.append(person)
		if students.is_empty(): continue
		record["lesson"] = float(record.lesson) + seconds
		while float(record.lesson) >= LESSON_SECONDS:
			record["lesson"] = float(record.lesson) - LESSON_SECONDS
			for person: Dictionary in students:
				var learned := mini(int(spec.cap), PersonSocial.learning(person.body) + 1)
				PersonSocial.set_learning(person.body, learned)
				taught[int(person.person_id)] = learned
	return taught

static func _present(actions: Variant, identity: int, entrance: Vector2i) -> bool:
	var person: Dictionary = actions._person(identity, false)
	if person.is_empty() or person.get("body") == null or float(person.get("hp", 0.0)) <= 0.0 or not actions._ready(person) or actions.is_busy(identity): return false
	var cell: Vector2i = person.cell
	return absi(cell.x - entrance.x) + absi(cell.y - entrance.y) <= 1


## The exam score without the roll (the plan's preview, §8.3).
static func preview_score(body: Variant) -> float:
	var abilities: Variant = body.get("command_abilities", {}) if body is Dictionary else (body.get("command_abilities") if body is Object else {})
	var mean := 50.0
	if abilities is Dictionary and not abilities.is_empty():
		mean = (float(abilities.get("tactics", 50.0)) + float(abilities.get("leadership", 50.0)) + float(abilities.get("coach", 50.0))) / 3.0
	var personality: Variant = body.get("personality") if body is Dictionary else (body.get("personality") if body is Object else null)
	var diligence := int(PersonPersonality.read(personality).diligence)
	return float(PersonSocial.learning(body)) * 0.6 + mean * 0.2 + float(diligence - 50) * 0.2

## A roll in −10..10 from the seed, the person and the exam day.
static func exam_roll(world_seed: int, identity: int, day: int) -> int:
	return posmod(hash([world_seed, identity, day, "exam_roll"]), 21) - 10

## Why `body` cannot sit exam `kind` on `day` ("" when he can).
static func candidate_refusal(kind: String, body: Variant, day: int) -> String:
	var role := PersonSocial.civil_role(body)
	if kind == "district":
		if role != "none": return "已有文職資格"
		if PersonSocial.learning(body) < PersonSocial.LITERATE: return "不識字（學業未達 20）"
	elif kind == "state":
		if role != "clerk": return "國試須為文吏"
		if PersonSocial.learning(body) < 60: return "國試學業須達 60"
	var last := int(PersonSocial.read(body).get("last_exam_day", -1))
	if last >= 0 and day - last < PERSON_COOLDOWN_DAYS: return "落榜後 30 日內不能再考"
	return ""

## Opens an exam at school `key`. `host` hosts it (authority checked by the caller); `candidates` are person dicts
## (SitePersonActions._person) the caller has checked for faction and jurisdiction.
static func open_exam(data: TerrainData, key: String, kind: String, host: int, candidates: Array) -> Dictionary:
	var exam_spec: Dictionary = EXAMS.get(kind, {})
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if exam_spec.is_empty() or str(feature.get("kind", "")) != str(exam_spec.school) or str(feature.get("stage", "")) != "complete" or not Runtime.feature_usable(feature): return Runtime.fail("NO_TARGET", "須在完工可用的%s開考" % ("鄉學" if kind == "district" else "國學"))
	if not data.site.has("schools"): data.site["schools"] = {}
	var record: Dictionary = data.site.schools.get(key, empty_record())
	if not record.exam.is_empty(): return Runtime.fail("BUSY", "考試進行中")
	var day := int(int(data.site.get("minute", 0)) / DAY_MINUTES)
	if int(record.last_exam_day) >= 0 and day - int(record.last_exam_day) < int(exam_spec.cooldown_days): return Runtime.fail("COOLDOWN", "本校 %d 日內不能再開考" % int(exam_spec.cooldown_days))
	var limit := int(KINDS[str(feature.kind)].students) * 2
	if candidates.is_empty() or candidates.size() > limit: return Runtime.fail("LIMIT", "考生 1–%d 人" % limit)
	var ids: Array = []
	for person: Dictionary in candidates:
		var why := candidate_refusal(kind, person.body, day)
		if not why.is_empty(): return Runtime.fail("NOT_ELIGIBLE", "#%d %s" % [int(person.person_id), why])
		ids.append(int(person.person_id))
	var stock: Dictionary = data.site.get("inventory", {})
	if int(stock.get("grain", 0)) < int(exam_spec.fee): return Runtime.fail("INSUFFICIENT", "開考須 %d 糧" % int(exam_spec.fee))
	stock["grain"] = int(stock.grain) - int(exam_spec.fee)
	record.exam = {"host": host, "candidates": ids, "elapsed": 0.0, "kind": kind}
	data.site.schools[key] = record
	return Runtime.ok("已開考；主持者須在學校門口 %d 有效秒" % int(EXAM_SECONDS), {"candidates": ids})

## Cancels a running exam and refunds its fee.
static func cancel_exam(data: TerrainData, key: String, reason: String = "考試取消") -> void:
	var record: Dictionary = records(data).get(key, {})
	if record.is_empty() or record.exam.is_empty(): return
	var stock: Dictionary = data.site.get("inventory", {})
	stock["grain"] = int(stock.get("grain", 0)) + int(EXAMS[str(record.exam.kind)].fee)
	record.exam = {}
	if data.site.get("notices") is Array: data.site.notices.append(reason)

static func _advance_exam(data: TerrainData, actions: Variant, key: String, record: Dictionary, entrance: Vector2i, seconds: float, results: Dictionary) -> void:
	var host := int(record.exam.host)
	var host_person: Dictionary = actions._person(host, false)
	if host_person.is_empty() or float(host_person.get("hp", 0.0)) <= 0.0 or bool(host_person.get("captive", false)):
		cancel_exam(data, key, "主持者不在，考試取消、退糧")
		return
	if not _present(actions, host, entrance): return # he walks back to finish; time only counts at the door
	record.exam.elapsed = float(record.exam.elapsed) + seconds
	if float(record.exam.elapsed) < EXAM_SECONDS: return
	var exam_spec: Dictionary = EXAMS[str(record.exam.kind)]
	var day := int(int(data.site.get("minute", 0)) / DAY_MINUTES)
	var seed_value := hash(["worldgoing_exam", str(data.site.get("id", ""))])
	var passed: Array = []
	for identity: int in record.exam.candidates:
		var person: Dictionary = actions._person(identity, false)
		if person.is_empty() or person.get("body") == null: continue
		var packet := PersonSocial.read(person.body).duplicate(true)
		if packet.is_empty(): packet = {"version": 1, "capture_seq": 0}
		packet["last_exam_day"] = day
		if person.body is Dictionary: person.body.social_state = packet
		else: person.body.set("social_state", packet)
		var score := preview_score(person.body) + float(exam_roll(seed_value, identity, day))
		if score >= float(exam_spec.pass):
			PersonSocial.set_civil_role(person.body, str(exam_spec.role))
			passed.append(identity)
		if not results.has("exams"): results["exams"] = []
		results.exams.append({"person": identity, "exam": str(record.exam.kind), "score": score, "passed": score >= float(exam_spec.pass)})
	record.last_exam_day = day
	record.exam = {}
	if data.site.get("notices") is Array: data.site.notices.append("%s放榜：%d 人及格" % ["鄉試" if exam_spec.role == "clerk" else "國試", passed.size()])
