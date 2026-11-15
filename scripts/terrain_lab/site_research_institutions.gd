extends RefCounted
## Research institutions (Nekki 11/07, option C; plan approved as proposed).
## A completed 工法室 / 匠作院 / 考工院 seats named researchers. While a seated researcher stands
## beside the institution door, ready and otherwise idle, its game seconds become "research
## preparation" on its scope's active project. Each researcher is paid 1 grain per game day from
## the camp stock; an unpaid researcher prepares nothing that day. Preparation never teaches a
## person and never crosses scope or Site. Stage 3 reads `prepared()` to halve the trial.

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const CivilPromotion = preload("res://scripts/terrain_lab/site_civil_promotion.gd")

const VERSION := 1
const DAY_MINUTES := 1440
const PREPARED_SECONDS := 86400.0 # One researcher x one game day halves the trial requirement.
const GRAIN_PER_DAY := 1

static func empty_record() -> Dictionary:
	return {"version": VERSION, "researchers": [], "paid_day": -1, "paid": [], "preparation": {}}

static func records(data: TerrainData) -> Dictionary:
	var value: Variant = data.site.get("research_institutions", {}) if data != null else {}
	return value if value is Dictionary else {}

## Strict save validation. `people` holds the valid person ids of the state being checked.
static func validate(state: Dictionary, people: Dictionary) -> Dictionary:
	var raw: Variant = state.get("research_institutions", {})
	if not raw is Dictionary: return Runtime.fail("CORRUPT_SAVE", "研究機構欄位")
	for key: Variant in raw:
		var feature: Variant = state.get("features", {}).get(key, {}) if key is String else null
		if not feature is Dictionary or not Runtime.RESEARCH_INSTITUTIONS.has(str(feature.get("kind", ""))): return Runtime.fail("CORRUPT_SAVE", "研究機構引用不存在")
		var record: Variant = raw[key]
		if not record is Dictionary or record.size() != 5 or int(record.get("version", 0)) != VERSION: return Runtime.fail("CORRUPT_SAVE", "研究機構版本")
		var seats := int(Runtime.RESEARCH_INSTITUTIONS[str(feature.kind)].seats)
		if not record.get("researchers") is Array or record.researchers.size() > seats or not record.get("paid") is Array or not record.get("preparation") is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "研究機構名額")
		var seen := {}
		for identity: Variant in record.researchers:
			if not (identity is int or identity is float) or float(identity) != floorf(float(identity)) or seen.has(int(identity)) or not people.has(int(identity)):
				return Runtime.fail("CORRUPT_SAVE", "研究員不存在或重複")
			seen[int(identity)] = true
		for identity: Variant in record.paid:
			if not seen.has(int(identity)): return Runtime.fail("CORRUPT_SAVE", "已領糧者不在研究員名單")
		if not (record.paid_day is int or record.paid_day is float) or int(record.paid_day) < -1: return Runtime.fail("CORRUPT_SAVE", "研究機構領糧日")
		for ref: Variant in record.preparation:
			var parsed: Variant = JSON.parse_string(str(ref))
			var seconds: Variant = record.preparation[ref]
			if not parsed is Array or parsed.size() != 4 or not (seconds is float or seconds is int) or not is_finite(float(seconds)) or float(seconds) < 0.0:
				return Runtime.fail("CORRUPT_SAVE", "研究準備紀錄")
	return Runtime.ok()

static func normalize(state: Dictionary) -> void:
	var raw: Variant = state.get("research_institutions", {})
	if not raw is Dictionary: return
	for record: Dictionary in raw.values():
		record["version"] = int(record.version)
		record["paid_day"] = int(record.paid_day)
		for index: int in record.researchers.size(): record.researchers[index] = int(record.researchers[index])
		for index: int in record.paid.size(): record.paid[index] = int(record.paid[index])
		for ref: String in record.preparation: record.preparation[ref] = float(record.preparation[ref])

## The scope owner an institution kind serves on this Site: {owner, scope, scope_id} or {}.
static func scope_owner(data: TerrainData, kind: String) -> Dictionary:
	var scope := str(Runtime.RESEARCH_INSTITUTIONS.get(kind, {}).get("scope", ""))
	if scope == "family":
		var family: Variant = data.site.get("family", {})
		return {"owner": family, "scope": scope, "scope_id": str(family.get("family_id", ""))} if family is Dictionary and not family.is_empty() else {}
	if scope == "settlement":
		var settlement: Variant = data.site.get("settlement", {})
		return {"owner": settlement, "scope": scope, "scope_id": str(settlement.get("settlement_id", ""))} if settlement is Dictionary and not settlement.is_empty() else {}
	if scope == "nation":
		var nations: Variant = data.site.get("equipment_nations", {})
		if not nations is Dictionary or nations.is_empty(): return {}
		var ids: Array = nations.keys()
		ids.sort()
		return {"owner": nations[ids[0]], "scope": scope, "scope_id": str(ids[0])}
	return {}

static func project_ref(scope: String, scope_id: String, project: Dictionary) -> String:
	if project.is_empty(): return ""
	return JSON.stringify([scope, scope_id, int(project.get("id", 0)), int(project.get("epoch", 0))])

## Preparation seconds this Site's institutions hold for one scope project.
static func preparation(data: TerrainData, scope: String, scope_id: String, project: Dictionary) -> float:
	var ref := project_ref(scope, scope_id, project)
	if ref.is_empty(): return 0.0
	var total := 0.0
	for key: String in records(data):
		var feature: Dictionary = data.site.get("features", {}).get(key, {})
		if str(Runtime.RESEARCH_INSTITUTIONS.get(str(feature.get("kind", "")), {}).get("scope", "")) != scope: continue
		total += float(records(data)[key].preparation.get(ref, 0.0))
	return total

static func prepared(data: TerrainData, scope: String, scope_id: String, project: Dictionary) -> bool:
	return preparation(data, scope, scope_id, project) >= PREPARED_SECONDS - 0.000001

## Seat or unseat a researcher. Authority and consent are checked by the caller (PersonActions).
static func set_researcher(data: TerrainData, key: String, identity: int, seated: bool) -> Dictionary:
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	var kind := str(feature.get("kind", ""))
	if not Runtime.RESEARCH_INSTITUTIONS.has(kind) or str(feature.get("stage", "")) != "complete" or not Runtime.feature_usable(feature): return Runtime.fail("NO_TARGET")
	if not data.site.has("research_institutions"): data.site["research_institutions"] = {}
	var record: Dictionary = data.site.research_institutions.get(key, empty_record())
	var researchers: Array = record.researchers
	if seated:
		if researchers.has(identity): return Runtime.ok("已是本機構研究員")
		for other: Dictionary in data.site.research_institutions.values():
			if other.researchers.has(identity): return Runtime.fail("BUSY", "此人已在其他研究機構")
		if researchers.size() >= int(Runtime.RESEARCH_INSTITUTIONS[kind].seats): return Runtime.fail("LIMIT", "研究員名額已滿")
		researchers.append(identity)
	else:
		if not researchers.has(identity): return Runtime.fail("NO_TARGET")
		researchers.erase(identity)
		record.paid.erase(identity)
	data.site.research_institutions[key] = record
	data.environment_revision += 1
	return Runtime.ok("已更新研究員")

static func is_researcher(data: TerrainData, identity: int) -> bool:
	for record: Dictionary in records(data).values():
		if record.researchers.has(identity): return true
	return false

## One accepted game interval. `actions` is the Site's PersonActions (person reads only).
static func advance(data: TerrainData, actions: Variant, seconds: float) -> void:
	if data == null or actions == null or not is_finite(seconds) or seconds <= 0.0 or records(data).is_empty(): return
	var day := int(data.site.get("minute", 0)) / DAY_MINUTES
	for key: String in records(data):
		var feature: Dictionary = data.site.get("features", {}).get(key, {})
		var record: Dictionary = records(data)[key]
		if str(feature.get("stage", "")) != "complete" or not Runtime.feature_usable(feature): continue
		if int(record.paid_day) != day:
			record["paid_day"] = day
			record["paid"] = []
			for identity: int in record.researchers:
				var stock: Dictionary = data.site.get("inventory", {})
				if int(stock.get("grain", 0)) < GRAIN_PER_DAY: break
				stock["grain"] = int(stock.grain) - GRAIN_PER_DAY
				if data.site.get("depot_items") is Dictionary: data.site.depot_items["version"] = int(data.site.depot_items.version) + 1
				record.paid.append(identity)
		var owner := scope_owner(data, str(feature.kind))
		if owner.is_empty(): continue
		var project: Dictionary = Technology.active_project(owner.owner.get("technology", {}))
		var ref := project_ref(str(owner.scope), str(owner.scope_id), project)
		if ref.is_empty() or bool(project.get("closed", false)): continue
		var entrance: Vector2i = data.cell_from_index(int(feature.get("entrance", -1)))
		for identity: int in record.paid:
			var person: Dictionary = actions._person(identity, false)
			if person.is_empty() or not actions._ready(person) or actions.is_busy(identity): continue
			var cell: Vector2i = person.cell
			if absi(cell.x - entrance.x) + absi(cell.y - entrance.y) > 1: continue
			record.preparation[ref] = float(record.preparation.get(ref, 0.0)) + seconds
		# Crossing the threshold marks the live project for good (a later loss of the institution
		# never re-lengthens a trial already halved).
		if project.get("institution_halved") != true and prepared(data, str(owner.scope), str(owner.scope_id), project) and int(project.get("rules_version", 0)) == 2:
			project["institution_halved"] = true
			# 文武官 W3 (§5.3-3): the scope's paid researchers without a civil role become 文吏.
			var contributors: Array = []
			for other_key: String in records(data):
				var other: Dictionary = data.site.get("features", {}).get(other_key, {})
				if str(Runtime.RESEARCH_INSTITUTIONS.get(str(other.get("kind", "")), {}).get("scope", "")) != str(owner.scope): continue
				for identity: int in records(data)[other_key].paid:
					if not contributors.has(identity): contributors.append(identity)
			CivilPromotion.research_finished(actions, contributors)
