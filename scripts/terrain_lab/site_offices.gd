class_name SiteOffices
extends RefCounted
## Positions are custom-named seats people hold; duties are system-defined
## authority packages bound to real command entries. Every wired duty belongs to
## exactly one position. Duties only answer "who may"; each entry keeps its
## original presence/stop/material checks. Pure data owner: no people, clocks
## or orders are stored or issued here.

const VERSION := 2 # v2 adds office_class (v2 plan R1a); v1 records load and upgrade on first use.
const CLASSES := ["civil", "military"]
# Duties whose holder needs officer qualification (軍官資格). Since 2026-10-07
# (Nekki: 文官也可以帶兵) they may sit on a 文官 or 武官 seat; 文官/武官 is a label
# and the default for new seats, never a command restriction.
const MILITARY_DUTIES := ["team.succession", "team.training", "team.recruit", "nation.corps", "nation.dispatch", "nation.fleet"]
# Class a seat gets when created for this duty (default layout, catalog growth, v1 upgrade).
const DEFAULT_CLASS := {"team.succession": "military", "team.work": "civil", "team.roster": "civil", "team.logistics": "military",
	"team.training": "military", "team.recruit": "military", "team.equip": "military", "team.salvage": "military", "team.ship": "military",
	"nation.corps": "military", "nation.dispatch": "military", "nation.equip_standard": "military", "nation.culture": "civil", "nation.dye": "civil", "nation.institutions": "civil",
	"nation.procurement": "civil", "nation.labor": "civil", "nation.relief": "civil", "nation.workshop": "civil", "nation.production": "civil", "nation.public_works": "civil", "nation.education": "civil", "nation.transport": "civil", "nation.finance": "civil", "nation.administration": "civil", "nation.arsenal": "civil", "nation.fleet": "military", "nation.admission": "civil", "nation.ransom": "civil",
	"family.roster": "civil", "family.research": "civil", "family.teach": "civil", "settlement.head": "civil", "settlement.prison": "civil", "settlement.ecology": "civil", "settlement.garrison": "military"}
const NAME_MAX := 16
const MAX_SEQ := 2147483646

# Only duties whose real entry already checks SiteOffices appear here
# (OFFICE_POSITIONS_AND_DUTIES_PLAN 4). team.command stays the commander's
# original power until P4; family offices start with P3.
const CATALOG := {
	"team": [
		{"id": "team.succession", "name": "隊長", "head": true},
		{"id": "team.work", "name": "工頭"},
		{"id": "team.logistics", "name": "後勤官"},
		{"id": "team.training", "name": "教頭"},
		{"id": "team.equip", "name": "軍需"},
		{"id": "team.roster", "name": "書記"},
		{"id": "team.salvage", "name": "收繳官"},
		{"id": "team.ship", "name": "船頭"},
		# v2 plan 3.1/3.4: formally enlist an existing original person (never makes one).
		{"id": "team.recruit", "name": "募兵官"},
	],
	"nation": [
		{"id": "nation.corps", "name": "元首", "head": true},
		{"id": "nation.equip_standard", "name": "軍事首長"},
		{"id": "nation.culture", "name": "禮官"},
		{"id": "nation.dye", "name": "司服"},
		{"id": "nation.dispatch", "name": "行軍官"},
		{"id": "nation.institutions", "name": "典章官"},
		{"id": "nation.procurement", "name": "採購"},
		{"id": "nation.labor", "name": "勞役"},
		{"id": "nation.relief", "name": "賑濟"},
		{"id": "nation.workshop", "name": "作坊驗收"},
		{"id": "nation.production", "name": "標準生產"},
		{"id": "nation.public_works", "name": "公共工程"},
		{"id": "nation.education", "name": "教養"},
		{"id": "nation.transport", "name": "公共運輸"},
		{"id": "nation.finance", "name": "財產徵支"},
		{"id": "nation.administration", "name": "地方委任"},
		{"id": "nation.arsenal", "name": "軍器驗收"},
		{"id": "nation.fleet", "name": "船隊編入"},
		# v2 plan 3.1/6.3 (R3): admitting a captive who is willing to surrender.
		{"id": "nation.admission", "name": "戶籍官"},
		# v2 plan 12 (R4b-1): binds the nation's own treasury; coin payment is R4c.
		{"id": "nation.ransom", "name": "贖務官"},
	],
	# OFFICE plan P3: only the registry has a real entry; research/teaching/heir
	# order join when their entries exist. Created on the first explicit head.
	"family": [
		{"id": "family.roster", "name": "家主", "head": true},
		{"id": "family.research", "name": "研習"},
		{"id": "family.teach", "name": "授徒"},
		# Trade plan §4.1 (Q5 A): the family estate's trade.
		{"id": "family.estate", "name": "管家"},
	],
	# SETTLEMENT_CENTER_LEVELS_PLAN P0: head only; the default title follows the level.
	"settlement": [
		{"id": "settlement.head", "name": "聚落長", "head": true},
		# Appendix D.7: the prison camp belongs to the settlement, not a team.
		{"id": "settlement.prison", "name": "典獄"},
		{"id": "settlement.ecology", "name": "虞衡"},
		# User decision 2026-10-08: barracks rosters belong to the settlement's 營務官.
		{"id": "settlement.garrison", "name": "營務官"},
		# Trade plan T2: the settlement's trade from its warehouses.
		{"id": "settlement.trade", "name": "市正"},
	],
}
# Legacy nation records (no offices) keep all three equipment powers on the
# original military_head; this is also the one migration exception (6.3).
const LEGACY_NATION_DUTIES := ["nation.equip_standard", "nation.culture", "nation.dye"]
const SUFFIXES := ["二", "三", "四", "五", "六", "七", "八", "九", "十"]
# Display names of duties (system-defined, not renamable; plan 4).
const DUTY_LABELS := {
	"team.succession": "接任順位", "team.work": "派工", "team.logistics": "專職後勤", "team.training": "訓練令", "team.equip": "整隊領裝",
	"nation.corps": "軍團編成", "nation.dispatch": "跨地派遣", "nation.equip_standard": "配裝標準", "nation.culture": "國家裝備文化", "nation.dye": "本國人物配色", "nation.institutions": "制度研究",
	"nation.procurement": "採購", "nation.labor": "勞役", "nation.relief": "賑濟", "nation.workshop": "作坊驗收", "nation.production": "標準生產", "nation.public_works": "公共工程", "nation.education": "教養", "nation.transport": "公共運輸", "nation.finance": "財產徵支", "nation.administration": "地方委任", "nation.arsenal": "軍器驗收", "nation.fleet": "船隊編入", "nation.admission": "收受歸降", "nation.ransom": "贖金收支",
	"settlement.head": "聚落首長", "family.roster": "家族名冊", "family.research": "研習", "family.teach": "授徒", "family.estate": "家產",
	"team.roster": "名冊調整", "team.salvage": "搜刮調度", "team.ship": "船務", "team.recruit": "募兵", "settlement.prison": "俘虜看管", "settlement.ecology": "生態管理", "settlement.garrison": "軍營名冊", "settlement.trade": "聚落交易",
}
# Duties wired after a kind's first release. A saved record may lack them;
# ensure_catalog() adds each as a vacant seat on first use (3.2), so the head
# keeps exercising it and old saves behave exactly as before.
const LATER_DUTIES := {"team": ["team.roster", "team.salvage", "team.ship", "team.recruit"], "settlement": ["settlement.prison", "settlement.ecology", "settlement.garrison", "settlement.trade"], "nation": ["nation.dispatch", "nation.institutions", "nation.procurement", "nation.labor", "nation.relief", "nation.workshop", "nation.production", "nation.public_works", "nation.education", "nation.transport", "nation.finance", "nation.administration", "nation.arsenal", "nation.fleet", "nation.admission", "nation.ransom"], "family": ["family.research", "family.teach", "family.estate"]}
# Duties the AI never executes (plan A.3, D15); the decider is always a player.
const MANUAL_ONLY := ["family.roster", "family.teach"] # research uses original SiteDutyAI / PersonActions.

static func duty_ids(kind: String) -> Array[String]:
	var result: Array[String] = []
	for duty: Dictionary in CATALOG.get(kind, []): result.append(str(duty.id))
	return result

static func head_duty(kind: String) -> String:
	for duty: Dictionary in CATALOG.get(kind, []):
		if bool(duty.get("head", false)): return str(duty.id)
	return ""

static func default_name(duty_id: String) -> String:
	for duties: Array in CATALOG.values():
		for duty: Dictionary in duties:
			if str(duty.id) == duty_id: return str(duty.name)
	return duty_id

## One position per duty: the head holds its starred duty, every other duty gets
## a vacant position with its default name (so the head still exercises all).
static func default_offices(kind: String, head_holder: int = -1, duty_ai: bool = false) -> Dictionary:
	var offices := {"version": VERSION, "revision": 0, "next_seq": 1, "duty_ai": duty_ai, "positions": [], "duties": {}}
	for duty: Dictionary in CATALOG.get(kind, []):
		var head := bool(duty.get("head", false))
		var id := _add_position(offices, str(duty.name), head, head_holder if head else -1, default_class(str(duty.id)))
		offices.duties[str(duty.id)] = id
	return offices

static func legacy_nation_offices(military_head: int) -> Dictionary:
	var offices := {"version": VERSION, "revision": 0, "next_seq": 1, "duty_ai": false, "positions": [], "duties": {}}
	offices.duties["nation.corps"] = _add_position(offices, default_name("nation.corps"), true, -1, "military")
	var keeper := _add_position(offices, default_name("nation.equip_standard"), false, military_head, "military")
	for duty_id: String in LEGACY_NATION_DUTIES: offices.duties[duty_id] = keeper
	return offices

static func default_class(duty_id: String) -> String:
	return str(DEFAULT_CLASS.get(duty_id, "civil"))

static func _add_position(offices: Dictionary, wanted: String, head: bool, holder: int, office_class: String = "civil") -> String:
	var id := "pos_%d" % int(offices.next_seq)
	offices["next_seq"] = int(offices.next_seq) + 1
	offices.positions.append({"id": id, "name": unique_name(offices, wanted), "head": head, "holder": holder, "office_class": office_class})
	return id

## v1 → v2 in place: each seat gets 武官 if any of its duties needs it or its
## first duty defaults to military, else 文官. Holders and duties are unchanged.
static func upgrade(offices: Dictionary) -> bool:
	if offices.is_empty() or int(offices.get("version", VERSION)) >= VERSION: return false
	for entry: Dictionary in offices.get("positions", []):
		if entry.has("office_class"): continue
		var duties := duties_of_position(offices, str(entry.id))
		var military := false
		for duty_id: String in duties:
			military = military or MILITARY_DUTIES.has(duty_id) or default_class(duty_id) == "military"
		entry["office_class"] = "military" if military else "civil"
	offices["version"] = VERSION
	return true

## Does this seat's holder need officer qualification: a 武官 seat, or any seat
## carrying an officer duty (訓練/軍團編成), whatever its class.
static func needs_officer(offices: Dictionary, entry: Dictionary) -> bool:
	if str(entry.get("office_class", "military")) == "military": return true
	for duty_id: String in duties_of_position(offices, str(entry.get("id", ""))):
		if MILITARY_DUTIES.has(duty_id): return true
	return false

static func unique_name(offices: Dictionary, wanted: String) -> String:
	var taken := {}
	for position_value: Dictionary in offices.get("positions", []): taken[str(position_value.name)] = true
	if not taken.has(wanted): return wanted
	for suffix: String in SUFFIXES:
		if not taken.has(wanted + suffix) and (wanted + suffix).length() <= NAME_MAX: return wanted + suffix
	var index := 11
	while taken.has("%s%d" % [wanted.left(NAME_MAX - 6), index]): index += 1
	return "%s%d" % [wanted.left(NAME_MAX - 6), index]

## A game version that wires a new duty adds one vacant position for it (3.2).
static func ensure_catalog(offices: Dictionary, kind: String) -> bool:
	var changed := false
	for duty: Dictionary in CATALOG.get(kind, []):
		if offices.duties.has(str(duty.id)): continue
		offices.duties[str(duty.id)] = head_position(offices).get("id", "") if bool(duty.get("head", false)) \
			else _add_position(offices, str(duty.name), false, -1, default_class(str(duty.id)) if int(offices.get("version", VERSION)) >= 2 else "civil")
		if int(offices.get("version", VERSION)) < 2:
			for entry: Dictionary in offices.positions: entry.erase("office_class") # v1 shape stays uniform until upgrade().
		changed = true
	return changed

static func name_valid(value: Variant) -> bool:
	if not value is String: return false
	var trimmed: String = value.strip_edges()
	if trimmed != value or trimmed.is_empty() or trimmed.length() > NAME_MAX: return false
	for character: String in trimmed:
		if character.unicode_at(0) < 32 or character.unicode_at(0) == 127: return false
	return true

static func position(offices: Dictionary, position_id: String) -> Dictionary:
	for entry: Dictionary in offices.get("positions", []):
		if str(entry.id) == position_id: return entry
	return {}

static func head_position(offices: Dictionary) -> Dictionary:
	for entry: Dictionary in offices.get("positions", []):
		if bool(entry.head): return entry
	return {}

static func position_of(offices: Dictionary, person_id: int) -> Dictionary:
	if person_id <= 0: return {}
	for entry: Dictionary in offices.get("positions", []):
		if int(entry.holder) == person_id: return entry
	return {}

static func duties_of_position(offices: Dictionary, position_id: String) -> Array[String]:
	var result: Array[String] = []
	for duty_id: String in offices.get("duties", {}):
		if str(offices.duties[duty_id]) == position_id: result.append(duty_id)
	result.sort()
	return result

## Strict structural contract (6.1). `stored_head_holder`: a team head's holder
## is derived from formal_commander and never stored.
static func validate(offices: Variant, kind: String, stored_head_holder: bool = true) -> bool:
	if not offices is Dictionary or offices.size() != 6 or not _int(offices.get("version"), 1, VERSION) \
		or not _int(offices.get("revision"), 0, MAX_SEQ) or not _int(offices.get("next_seq"), 1, MAX_SEQ) \
		or not offices.get("duty_ai") is bool or not offices.get("positions") is Array or not offices.get("duties") is Dictionary:
		return false
	var ids := {}
	var names := {}
	var holders := {}
	var heads := 0
	var versioned := int(offices.version) >= 2
	for entry: Variant in offices.positions:
		if not entry is Dictionary or entry.size() != (5 if versioned else 4) or not entry.get("id") is String or not entry.get("head") is bool \
			or not name_valid(entry.get("name")) or not _int(entry.get("holder"), -1, MAX_SEQ) or int(entry.holder) == 0:
			return false
		if versioned and not CLASSES.has(entry.get("office_class")): return false
		var id: String = entry.id
		if not id.begins_with("pos_") or not id.substr(4).is_valid_int() or int(id.substr(4)) < 1 or int(id.substr(4)) >= int(offices.next_seq) \
			or ids.has(id) or names.has(entry.name):
			return false
		ids[id] = true
		names[entry.name] = true
		heads += int(entry.head)
		if bool(entry.head) and not stored_head_holder and int(entry.holder) != -1: return false
		if int(entry.holder) > 0:
			if int(entry.holder) == 1000000000 or holders.has(int(entry.holder)): return false
			holders[int(entry.holder)] = true
	if heads != 1: return false
	var expected := duty_ids(kind)
	var later: Array = LATER_DUTIES.get(kind, [])
	for duty_id: Variant in offices.duties:
		if not expected.has(str(duty_id)): return false
	var loaded := {}
	for duty_id: String in expected:
		if not offices.duties.has(duty_id) and later.has(duty_id): continue
		if not offices.duties.get(duty_id) is String or not ids.has(offices.duties[duty_id]): return false
		loaded[offices.duties[duty_id]] = true
	for entry: Dictionary in offices.positions:
		# Held positions keep at least one duty; vacant ones may hold none (3.3).
		if int(entry.holder) > 0 and not loaded.has(entry.id): return false
	return true

## JSON numbers load as floats; restore exact integer types after validation.
static func normalize_numbers(offices: Dictionary) -> void:
	for field: String in ["version", "revision", "next_seq"]:
		if offices.has(field): offices[field] = int(offices[field])
	for entry: Variant in offices.get("positions", []):
		if entry is Dictionary and entry.has("holder"): entry.holder = int(entry.holder)

static func _int(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) \
		and float(value) >= float(low) and float(value) <= float(high)

## Who exercises `duty_id` now (3.4): an eligible holder; otherwise the head's
## executor acts. `head_executor` <= 0 means the head itself is vacant/unfit.
## `holder_ok(person_id) -> bool` is the organization's eligibility rule.
static func resolve(offices: Dictionary, duty_id: String, head_executor: int, holder_ok: Callable, head_acting: bool = false) -> Dictionary:
	var position_id := str(offices.get("duties", {}).get(duty_id, ""))
	var seat := position(offices, position_id)
	var result := {"ok": false, "code": "DUTY_ORPHAN", "duty_id": duty_id, "position_id": position_id,
		"position_name": str(seat.get("name", "")), "holder": int(seat.get("holder", -1)), "decider": -1,
		"acting": false, "revision": int(offices.get("revision", 0))}
	if seat.is_empty():
		result["message"] = "職責沒有負責職位"
		return result
	if bool(seat.head):
		result["acting"] = head_acting
	elif int(seat.holder) > 0 and holder_ok.is_valid() and bool(holder_ok.call(int(seat.holder))):
		result["ok"] = true
		result["code"] = ""
		result["decider"] = int(seat.holder)
		return result
	else:
		result["acting"] = true
	if head_executor <= 0:
		result["code"] = "OFFICE_PAUSED"
		result["message"] = "「%s」空缺或失格，首長亦無法代行" % seat.name
		return result
	result["ok"] = true
	result["code"] = ""
	result["decider"] = head_executor
	return result

static func refusal(resolved: Dictionary, requester_id: int, offices: Dictionary) -> Dictionary:
	if not bool(resolved.get("ok", false)):
		return SiteRuntime.fail(str(resolved.get("code", "OFFICE_PAUSED")), str(resolved.get("message", "職責暫停")))
	var own := position_of(offices, requester_id)
	var acting := "（代行：%d）" % int(resolved.decider) if bool(resolved.acting) else ""
	var mine := "；你目前是「%s」" % own.name if not own.is_empty() else ""
	return SiteRuntime.fail("NO_AUTHORITY", "此事由「%s」負責%s%s" % [resolved.position_name, acting, mine])

## Duties a person exercises now, own and by head fallback, in catalog order.
static func exercised_by(offices: Dictionary, kind: String, person_id: int, head_executor: int, holder_ok: Callable, head_acting: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for duty_id: String in duty_ids(kind):
		var resolved := resolve(offices, duty_id, head_executor, holder_ok, head_acting)
		if bool(resolved.ok) and int(resolved.decider) == person_id: result.append(resolved)
	return result

## Automatic events (death, departure, loss of qualification) only vacate (3.3).
static func vacate_unless(offices: Dictionary, keep: Callable) -> bool:
	var changed := false
	for entry: Dictionary in offices.get("positions", []):
		if int(entry.holder) > 0 and not bool(keep.call(int(entry.holder))):
			entry.holder = -1
			changed = true
	if changed: offices["revision"] = mini(MAX_SEQ, int(offices.revision) + 1)
	return changed

## Whole personnel plan, validated once on its final state (3.3), pure.
## ops: {op: rename|add|abolish|appoint|dismiss|assign, ...}; `add` may carry a
## `ref` later ops use as position_id. `candidate_ok(person_id) -> bool` checks a
## newly appointed holder's qualification. Head holders never change here.
static func apply_plan(offices: Dictionary, kind: String, expected_revision: int, ops: Array, candidate_ok: Callable, stored_head_holder: bool = true) -> Dictionary:
	if int(offices.get("revision", -1)) != expected_revision:
		return _plan_fail("STALE_REVISION", "人事已變更，請重新檢視方案")
	if ops.is_empty(): return _plan_fail("NO_CHANGE", "方案沒有變更")
	var draft := offices.duplicate(true)
	upgrade(draft)
	var refs := {}
	var appointed: Array[int] = []
	var failed := _apply_ops(draft, ops, refs, appointed)
	if not failed.is_empty(): return failed
	for entry: Dictionary in draft.positions:
		for other: Dictionary in draft.positions:
			if entry != other and entry.name == other.name: return _plan_fail("NAME_DUPLICATE", "同組織內職位不可重名：「%s」" % entry.name)
	for duty_id: String in draft.duties:
		if position(draft, str(draft.duties[duty_id])).is_empty():
			return _plan_fail("DUTY_ORPHAN", "裁撤前須在同一方案移走職責：%s" % duty_label(duty_id))
	for entry: Dictionary in draft.positions:
		if int(entry.holder) > 0 and duties_of_position(draft, str(entry.id)).is_empty():
			return _plan_fail("EMPTY_POSITION", "「%s」仍有任職者，至少需保留一項職責" % entry.name)
	for person: int in appointed:
		var seat := position_of(draft, person)
		if seat.get("holder", -1) == person:
			var count := 0
			for entry: Dictionary in draft.positions: count += int(int(entry.holder) == person)
			if count > 1: return _plan_fail("DUPLICATE_HOLDER", "同一人在同一組織最多擔任一個職位")
			if not candidate_ok.is_valid() or not bool(candidate_ok.call(person, "military" if needs_officer(draft, seat) else str(seat.office_class))):
				return _plan_fail("NOT_ELIGIBLE", "人物 #%d 不具「%s」（%s）的任職資格" % [person, str(seat.name), class_label(str(seat.office_class))])
	# A sitting holder whose seat now needs officer qualification (reclassified or
	# given 訓練/軍團編成) must have it too.
	for entry: Dictionary in draft.positions:
		var holder := int(entry.holder)
		if bool(entry.head) or holder <= 0 or appointed.has(holder) or not needs_officer(draft, entry): continue
		if not candidate_ok.is_valid() or not bool(candidate_ok.call(holder, "military")):
			return _plan_fail("NOT_ELIGIBLE", "「%s」負責的職責須由具軍官資格者擔任（人物 #%d）" % [str(entry.name), holder])
	draft["revision"] = mini(MAX_SEQ, int(draft.revision) + 1)
	if not validate(draft, kind, stored_head_holder): return _plan_fail("INVALID", "方案結果不符合職位契約")
	return {"ok": true, "code": "", "message": "已套用人事方案", "offices": draft, "refs": refs}

## Pending-plan view for the position page: the ops applied to a copy with no
## final-state rules, so a half-built plan can still be shown. Never committed.
static func class_label(office_class: String) -> String:
	return "武官" if office_class == "military" else "文官"

static func preview_plan(offices: Dictionary, ops: Array) -> Dictionary:
	var draft := offices.duplicate(true)
	upgrade(draft)
	var failed := _apply_ops(draft, ops, {}, [])
	return {"ok": failed.is_empty(), "offices": draft, "code": str(failed.get("code", "")), "message": str(failed.get("message", ""))}

static func duty_label(duty_id: String) -> String:
	return str(DUTY_LABELS.get(duty_id, duty_id))

static func _apply_ops(draft: Dictionary, ops: Array, refs: Dictionary, appointed: Array[int]) -> Dictionary:
	for op: Variant in ops:
		if not op is Dictionary: return _plan_fail("INVALID", "方案格式不合法")
		var target := str(refs.get(str(op.get("position_id", "")), str(op.get("position_id", ""))))
		var seat := position(draft, target)
		match str(op.get("op", "")):
			"rename":
				if seat.is_empty(): return _plan_fail("NO_TARGET", "職位不存在")
				if not name_valid(op.get("name")): return _plan_fail("NAME_INVALID", "職位名稱須為 1–%d 字且不含控制字元" % NAME_MAX)
				seat.name = op.name
			"add":
				if not name_valid(op.get("name")) or int(draft.next_seq) >= MAX_SEQ: return _plan_fail("NAME_INVALID", "職位名稱須為 1–%d 字且不含控制字元" % NAME_MAX)
				var added_class := str(op.get("office_class", "civil"))
				if not CLASSES.has(added_class): return _plan_fail("INVALID", "職位分類須為文官或武官")
				var id := "pos_%d" % int(draft.next_seq)
				draft["next_seq"] = int(draft.next_seq) + 1
				draft.positions.append({"id": id, "name": op.name, "head": false, "holder": -1, "office_class": added_class})
				if op.has("ref"): refs[str(op.ref)] = id
			"abolish":
				if seat.is_empty() or bool(seat.head): return _plan_fail("NO_AUTHORITY", "首長職位不可裁撤")
				draft.positions.erase(seat)
			"appoint":
				var person := int(op.get("person_id", -1))
				if seat.is_empty() or bool(seat.head) or person <= 0 or person == 1000000000: return _plan_fail("NO_TARGET", "只能任命非首長職位的真實原人物")
				seat.holder = person
				appointed.append(person)
			"dismiss":
				if seat.is_empty() or bool(seat.head): return _plan_fail("NO_TARGET", "首長職位不經人事方案任免")
				seat.holder = -1
			"classify":
				# Head seats keep their class; a held seat's holder is rechecked for the new class.
				var wanted_class := str(op.get("office_class", ""))
				if seat.is_empty() or bool(seat.head) or not CLASSES.has(wanted_class): return _plan_fail("NO_TARGET", "只能變更非首長職位的分類（文官／武官）")
				seat.office_class = wanted_class
				if int(seat.holder) > 0 and not appointed.has(int(seat.holder)): appointed.append(int(seat.holder))
			"assign":
				var duty_id := str(op.get("duty_id", ""))
				if not draft.duties.has(duty_id) or seat.is_empty(): return _plan_fail("NO_TARGET", "職責或職位不存在")
				draft.duties[duty_id] = target
			_:
				return _plan_fail("INVALID", "未知的人事操作")
	return {}

static func _plan_fail(code: String, message: String) -> Dictionary:
	return SiteRuntime.fail(code, message)
