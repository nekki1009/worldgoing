class_name SiteSettlement
extends RefCounted
## Settlement center P0 (SETTLEMENT_CENTER_LEVELS_PLAN). One Site holds at most
## one settlement record in site.settlement; its center is an ordinary feature.
## Population, jurisdiction and suspension are derived from the live Site and
## never stored. Missing record = un-founded Site: every original rule stays.

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const CrowdOwner = preload("res://scripts/terrain_lab/crowd_person_owner.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const VERSION := 1
const FIELDS := ["version", "settlement_id", "center_id", "level", "name", "owner_faction", "offices", "fall_record"]
## Version 3 adds the nullable equipment-nation key (String key of equipment_nations, null = none). v1/v2 never carry it.
const FIELDS_V3 := ["version", "settlement_id", "center_id", "level", "name", "owner_faction", "offices", "fall_record", "nation_id"]
## Version 4 adds the trade tax rate: an integer percent 0..TRADE_TAX_MAX on the resource stacks received at this settlement's trades (S2: stored and validated only; no collection yet). v1-v3 never carry it.
const FIELDS_V4 := ["version", "settlement_id", "center_id", "level", "name", "owner_faction", "offices", "fall_record", "nation_id", "trade_tax_percent"]
const VERSION_MAX := 4 # The v4 candidate ceiling and setter write version (D-V1).
const VERSION_LATEST := 5 # R5 S1B (D-V1): load ceiling and designation upgrade. Optional succession section only.
const Succession = preload("res://scripts/terrain_lab/site_succession.gd")
const TRADE_TAX_MAX := 50
const NAME_MAX := 16
const RADIUS := {1: 12, 2: 20, 3: 30}
const RESIDENTS := {1: 0, 2: 12, 3: 40}
const WORKSHOP_KINDS := ["saltworks", "kiln", "charcoal", "smelter", "smithy", "tannery", "weaver"]
const REQUIRED_BUILDINGS := {
	2: [{"label": "住宅", "kinds": ["house"], "count": 4}, {"label": "水井或取水站", "kinds": ["well", "intake"], "count": 1}, {"label": "農田", "kinds": ["farm", "fiber_farm", "fodder_farm"], "count": 1}],
	3: [{"label": "住宅", "kinds": ["house"], "count": 10}, {"label": "倉庫", "kinds": ["warehouse"], "count": 1}, {"label": "任一加工作坊", "kinds": WORKSHOP_KINDS, "count": 2}],
}
const CAPTURE_SECONDS := 60.0
const CAPTURE_MARGIN := 2
const MAX_FACTION := 100000000
const MAX_PERSON := 2147483647

# --- Saved record ------------------------------------------------------------

static func record(data: TerrainData) -> Dictionary:
	var value: Variant = data.site.get("settlement", {}) if data != null else {}
	return value if value is Dictionary else {}

static func empty_fall_record() -> Dictionary:
	return {"version": 2, "contest_faction": -1, "contest_seconds": 0.0, "last_fall": {}}

static func _int(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= float(low) and float(value) <= float(high)

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func name_valid(value: Variant) -> bool:
	return SiteOffices.name_valid(value) and str(value).length() <= NAME_MAX

## Strict load contract. `people[id]` carries `_housing_faction` (Store's
## housing projection). Illegal level, duplicate or missing center: reject.
static func validate(data: TerrainData, state: Dictionary, people: Dictionary) -> Dictionary:
	var centers: Array[String] = []
	for key: String in state.get("features", {}):
		if str(state.features[key].get("kind", "")) == "settlement_center": centers.append(key)
	if not state.has("settlement"):
		return Runtime.fail("CORRUPT_SAVE", "聚落中心沒有對應聚落紀錄") if not centers.is_empty() else Runtime.ok()
	var settlement: Variant = state.settlement
	if not settlement is Dictionary or not _int(settlement.get("version"), 1, VERSION_LATEST): return Runtime.fail("CORRUPT_SAVE", "聚落紀錄版本")
	var expected_fields: Array = _fields_for_version(int(settlement.version)).duplicate()
	if int(settlement.version) >= 2:
		expected_fields.append("technology")
		if settlement.has("technology_operations"): expected_fields.append("technology_operations")
	if int(settlement.version) >= 5 and settlement.has("succession"): expected_fields.append("succession")
	if not Technology.keys(settlement, expected_fields): return Runtime.fail("CORRUPT_SAVE", "聚落紀錄欄位")
	if int(settlement.version) >= 2 and (not Technology.valid_scope_record(settlement.technology, "settlement") or str(settlement.technology.holder_site_id) != str(state.get("id", ""))): return Runtime.fail("CORRUPT_SAVE", "聚落科技版本／本原Site歸屬")
	if int(settlement.version) >= 3 and not valid_nation_reference(settlement.get("nation_id"), state): return Runtime.fail("CORRUPT_SAVE", "聚落國家引用")
	if int(settlement.version) >= 4 and not valid_trade_tax_percent(settlement.get("trade_tax_percent")): return Runtime.fail("CORRUPT_SAVE", "聚落貿易稅率")
	if settlement.has("technology_operations") and not valid_technology_operations(data, settlement.technology_operations, state): return Runtime.fail("CORRUPT_SAVE", "聚落有限用途格式")
	if not settlement.settlement_id is String or str(settlement.settlement_id).is_empty() or str(settlement.settlement_id).length() > 96: return Runtime.fail("CORRUPT_SAVE", "聚落身分")
	if centers.size() != 1: return Runtime.fail("CORRUPT_SAVE", "每個 Site 必須恰有一座聚落中心")
	if not settlement.center_id is String or str(settlement.center_id) != centers[0]: return Runtime.fail("CORRUPT_SAVE", "聚落中心 ID 不存在")
	var center_feature: Dictionary = state.features[centers[0]]
	if not _int(settlement.level, 0, Runtime.SETTLEMENT_MAX_LEVEL): return Runtime.fail("CORRUPT_SAVE", "聚落等級非法")
	var complete := str(center_feature.get("stage", "")) == "complete"
	if complete != (int(settlement.level) > 0): return Runtime.fail("CORRUPT_SAVE", "聚落等級與中心施工階段不符")
	if complete and int(settlement.level) != Runtime.settlement_center_invested_level(data, center_feature): return Runtime.fail("CORRUPT_SAVE", "聚落等級與中心已付投入不符")
	if not name_valid(settlement.name): return Runtime.fail("CORRUPT_SAVE", "聚落名稱")
	if not _int(settlement.owner_faction, 0, MAX_FACTION) or int(settlement.owner_faction) != int(center_feature.get("owner_faction", -1)): return Runtime.fail("CORRUPT_SAVE", "聚落陣營須等於中心管理方")
	if not SiteOffices.validate(settlement.offices, "settlement", true): return Runtime.fail("CORRUPT_SAVE", "聚落職位")
	if not valid_succession(settlement, people): return Runtime.fail("CORRUPT_SAVE", "聚落繼承人")
	var head := int(SiteOffices.head_position(settlement.offices).get("holder", -1))
	if head > 0:
		var holder: Dictionary = people.get(head, {})
		if holder.is_empty() or int(holder.get("_housing_faction", holder.get("faction_id", -1))) != int(settlement.owner_faction): return Runtime.fail("CORRUPT_SAVE", "聚落首長須是同陣營原人物")
	var fall: Variant = settlement.fall_record
	if not fall is Dictionary or fall.size() != 4 or not _int(fall.get("version"), 1, 2) or not _int(fall.get("contest_faction"), -1, MAX_FACTION) \
		or not _number(fall.get("contest_seconds"), 0.0, CAPTURE_SECONDS) or not fall.get("last_fall") is Dictionary:
		return Runtime.fail("CORRUPT_SAVE", "聚落陷落紀錄")
	if int(fall.contest_faction) == int(settlement.owner_faction) or int(fall.contest_faction) < 0 and float(fall.contest_seconds) != 0.0 or int(fall.contest_faction) >= 0 and int(settlement.level) == 0:
		return Runtime.fail("CORRUPT_SAVE", "聚落攻陷計時")
	var last: Dictionary = fall.last_fall
	if not last.is_empty():
		if not valid_last_fall(last, int(settlement.owner_faction), int(fall.version), int(state.get("minute", 0))):
			return Runtime.fail("CORRUPT_SAVE", "聚落最後陷落紀錄")
	return Runtime.ok()

## JSON numbers load as floats; restore exact integer types after validation.

## JSON numbers load as floats; restore exact integer types after validation.
## Null or an existing equipment_nations key (never a trial_team_ nation).
static func valid_nation_reference(value: Variant, state: Dictionary) -> bool:
	if value == null: return true
	if not value is String or str(value).is_empty() or str(value).length() > 96 or str(value).begins_with("trial_team_"): return false
	return state.get("equipment_nations", {}) is Dictionary and state.get("equipment_nations", {}).has(value)

## T6 S2: version-4 settlement trade tax (integer percent). Pure helpers; no collection here.
static func _fields_for_version(version: int) -> Array:
	return FIELDS_V4 if version >= 4 else (FIELDS_V3 if version == 3 else FIELDS)

## D-V1: a setter writes the higher of the v4 ceiling and the current version, so a v5 record keeps its succession.
static func setter_version(current: int) -> int:
	return maxi(VERSION_MAX, current)

## R5 S1B (D-S1): the optional succession section of a v5 record. The heir is a living person of the owner faction.
static func valid_succession(settlement: Dictionary, people: Dictionary) -> bool:
	if not settlement.has("succession"): return true
	if int(settlement.get("version", 0)) < 5 or not settlement.get("offices") is Dictionary: return false
	var seats: Array = []
	var head := SiteOffices.head_position(settlement.offices)
	if not head.is_empty(): seats.append(str(head.id))
	var faction := int(settlement.get("owner_faction", -1))
	var members := {}
	for identity: Variant in people:
		var projection: Variant = people[identity]
		if projection is Dictionary and int(projection.get("_housing_faction", -2)) == faction: members[int(identity)] = true
	return Succession.valid_record(settlement.succession, seats, members)

## R5 S1B: the candidate of a settlement heir designation. Authority = the settlement head; v4 or later.
static func designate_heir_candidate(settlement: Dictionary, requester_id: int, person_id: int, members: Dictionary, alive: Callable) -> Dictionary:
	if not settlement.get("offices") is Dictionary or int(settlement.get("version", 0)) < 4: return {"ok": false, "code": "NO_TARGET"}
	var head := SiteOffices.head_position(settlement.offices)
	var holder := int(head.get("holder", -1))
	if holder <= 0 or requester_id != holder: return {"ok": false, "code": "NO_AUTHORITY"}
	var record: Dictionary = settlement.succession if settlement.has("succession") else Succession.empty_record()
	var designated: Dictionary = Succession.designate(record, str(head.id), person_id, [str(head.id)], members, holder, alive)
	if not bool(designated.ok): return designated
	var candidate: Dictionary = settlement.duplicate(true)
	candidate["version"] = VERSION_LATEST
	candidate["succession"] = designated.record
	candidate.offices.revision = mini(SiteOffices.MAX_SEQ, int(candidate.offices.revision) + 1)
	return {"ok": true, "code": "", "settlement": candidate}

## Living persons of the owner faction on this Site (from the lab).
static func faction_members(lab: Variant, faction: int) -> Dictionary:
	var result := {}
	for actor: Variant in lab.combat_actors:
		if is_instance_valid(actor) and int(actor.faction_id) == faction and int(actor.person_id) > 0: result[int(actor.person_id)] = true
	# P1a: team_owners() is the grid armies, or the native crowd owners (actors included) while the crowd is active.
	for team: Variant in lab.team_owners():
		if is_instance_valid(team) and int(team.faction_id) == faction:
			var indices: Array = []
			if team.combat_units is Dictionary:
				indices = team.combat_units.keys()
			else:
				for slot in range(team.combat_units.size()): indices.append(slot)
			for index: Variant in indices:
				if team.is_member(int(index)) and int(team.combat_identity(int(index))) > 0: result[int(team.combat_identity(int(index)))] = true
	return result

## R5 S1B: the lab command. The head designates a living person of the owner faction, in place, in one commit.
static func designate_heir(lab: Variant, requester_id: int, person_id: int) -> Dictionary:
	var settlement: Dictionary = record(lab.terrain)
	if settlement.is_empty(): return Runtime.fail("NO_TARGET", "沒有聚落紀錄")
	var members: Dictionary = faction_members(lab, int(settlement.get("owner_faction", -1)))
	var checked: Dictionary = designate_heir_candidate(settlement, requester_id, person_id, members, func(identity: int) -> bool: return office_person_ok(lab, identity))
	if not bool(checked.get("ok", false)): return Runtime.fail(str(checked.code), "聚落繼承人指定未通過；原狀未變")
	settlement.clear()
	settlement.merge(checked.settlement, true)
	return Runtime.ok("已指定聚落繼承人", {"person_id": person_id})

static func valid_trade_tax_percent(value: Variant) -> bool:
	return _int(value, 0, TRADE_TAX_MAX)

## Shape of a version-4 candidate record (does not touch the Site). Technology must be the Site's own scope record.
static func valid_trade_tax_candidate(candidate: Dictionary, state: Dictionary) -> bool:
	var fields: Array = FIELDS_V4.duplicate()
	fields.append("technology")
	if candidate.has("technology_operations"): fields.append("technology_operations")
	var candidate_version := int(candidate.get("version", 0))
	if candidate_version == VERSION_LATEST and candidate.has("succession"): fields.append("succession")
	if (candidate_version != VERSION_MAX and candidate_version != VERSION_LATEST) or not Technology.keys(candidate, fields): return false
	return valid_nation_reference(candidate.get("nation_id"), state) and valid_trade_tax_percent(candidate.get("trade_tax_percent")) \
		and Technology.valid_scope_record(candidate.technology, "settlement") and str(candidate.technology.holder_site_id) == str(state.get("id", ""))

## P4 S3: the settlement's formal equipment nation (a key of equipment_nations, or null).
## Only the settlement head may set it, as set_trade_tax_percent does. The record is upgraded
## to the current version in the same candidate (empty technology scope and trade tax 0 if
## absent) and validated as a whole before commit. Owner faction, residents and center
## features are never touched: only the settlement record changes.
static func set_nation(data: TerrainData, requester_id: int, nation_id: Variant) -> Dictionary:
	var state: Dictionary = data.site if data != null else {}
	var current: Variant = state.get("settlement")
	if not current is Dictionary: return Runtime.fail("NO_TARGET", "沒有聚落紀錄")
	var version: int = int(current.get("version", 0))
	if version < 1 or version > VERSION_LATEST: return Runtime.fail("UNSUPPORTED", "聚落版本未知")
	var holder: int = int(SiteOffices.head_position(current.get("offices", {})).get("holder", -1))
	if holder <= 0 or requester_id != holder: return Runtime.fail("NO_AUTHORITY", "只有聚落首長可設定所屬國家")
	if nation_id != null and not valid_nation_reference(nation_id, state): return Runtime.fail("NATION_UNKNOWN", "所屬國家須是現有正式國家（非測試國別）")
	var candidate: Dictionary = current.duplicate(true)
	candidate["version"] = setter_version(version)
	candidate["nation_id"] = nation_id
	if not candidate.has("technology"): candidate["technology"] = Technology.empty_scope_record(str(state.get("id", "")))
	if not candidate.has("trade_tax_percent"): candidate["trade_tax_percent"] = 0
	if not valid_trade_tax_candidate(candidate, state): return Runtime.fail("CORRUPT_SAVE", "聚落紀錄格式")
	current.clear()
	current.merge(candidate, true)
	return Runtime.ok("聚落所屬國家已設定", {"nation_id": nation_id})

## Only the settlement head (holder of the head position) may set the rate. The record is upgraded to v4 in the same candidate: nation_id null if absent, and an empty technology scope record for this Site if absent (founded v1 settlements have none, per the existing empty-record convention). Refusal changes nothing.
static func set_trade_tax_percent(data: TerrainData, requester_id: int, percent: Variant) -> Dictionary:
	var state: Dictionary = data.site if data != null else {}
	var record: Variant = state.get("settlement")
	if not record is Dictionary: return Runtime.fail("NO_TARGET", "沒有聚落紀錄")
	var version: int = int(record.get("version", 0))
	if version < 1 or version > VERSION_LATEST: return Runtime.fail("UNSUPPORTED", "聚落版本未知")
	var holder: int = int(SiteOffices.head_position(record.get("offices", {})).get("holder", -1))
	if holder <= 0 or requester_id != holder: return Runtime.fail("NO_AUTHORITY", "只有聚落首長可設定貿易稅率")
	if not valid_trade_tax_percent(percent): return Runtime.fail("INVALID", "稅率須為 0 至 50 的整數百分比")
	var candidate: Dictionary = record.duplicate(true)
	candidate["version"] = setter_version(version)
	if not candidate.has("nation_id"): candidate["nation_id"] = null
	if not candidate.has("technology"): candidate["technology"] = Technology.empty_scope_record(str(state.get("id", "")))
	candidate["trade_tax_percent"] = int(percent)
	if not valid_trade_tax_candidate(candidate, state): return Runtime.fail("CORRUPT_SAVE", "聚落紀錄格式")
	record.clear()
	record.merge(candidate, true)
	return Runtime.ok("聚落貿易稅率已設定", {"trade_tax_percent": int(percent)})

static func normalize(state: Dictionary) -> void:
	var settlement: Variant = state.get("settlement")
	if not settlement is Dictionary: return
	for field: String in ["version", "level", "owner_faction"]:
		if settlement.has(field): settlement[field] = int(settlement[field])
	if settlement.get("offices") is Dictionary: SiteOffices.normalize_numbers(settlement.offices)
	if settlement.get("succession") is Dictionary: Succession.normalize_numbers(settlement.succession)
	var fall: Variant = settlement.get("fall_record")
	if fall is Dictionary:
		for field: String in ["version", "contest_faction"]:
			if fall.has(field): fall[field] = int(fall[field])
		if fall.has("contest_seconds"): fall.contest_seconds = float(fall.contest_seconds)
		if fall.get("last_fall") is Dictionary:
			for field: String in fall.last_fall: fall.last_fall[field] = int(fall.last_fall[field])
	if settlement.has("trade_tax_percent"): settlement.trade_tax_percent = int(settlement.trade_tax_percent)
	if int(settlement.get("version", 0)) >= 2 and settlement.get("technology") is Dictionary:
		settlement.technology = Technology.normalize_scope_record(settlement.technology, "settlement")
	if settlement.get("technology_operations") is Dictionary: normalize_technology_operations(settlement.technology_operations)

# --- Derived projections -----------------------------------------------------


# --- Derived projections -----------------------------------------------------

static func center(data: TerrainData) -> Dictionary:
	var settlement := record(data)
	if settlement.is_empty(): return {}
	var feature: Variant = data.site.get("features", {}).get(str(settlement.center_id), {})
	return feature if feature is Dictionary else {}

static func radius(level: int) -> int:
	return int(RADIUS.get(clampi(level, 1, Runtime.SETTLEMENT_MAX_LEVEL), 12))

static func _distance_to_rect(rect: Rect2i, cell: Vector2i) -> int:
	var dx := maxi(0, maxi(rect.position.x - cell.x, cell.x - (rect.end.x - 1)))
	var dy := maxi(0, maxi(rect.position.y - cell.y, cell.y - (rect.end.y - 1)))
	return maxi(dx, dy)

## Jurisdiction: Chebyshev distance from the center footprint (P0: one Site).
static func cell_in_jurisdiction(data: TerrainData, cell: Vector2i) -> bool:
	var feature := center(data)
	if feature.is_empty() or not data.contains(cell): return false
	return _distance_to_rect(Runtime._cell_bounds(data, feature.cells), cell) <= radius(int(record(data).level))

static func feature_in_jurisdiction(data: TerrainData, feature: Dictionary) -> bool:
	for index: Variant in feature.get("cells", []):
		if cell_in_jurisdiction(data, data.cell_from_index(int(index))): return true
	return false

## Living same-faction residents whose registered house lies in jurisdiction.
static func residents(lab: Variant) -> Array[int]:
	var result: Array[int] = []
	var data: TerrainData = lab.terrain
	var settlement := record(data)
	if settlement.is_empty() or int(settlement.level) <= 0: return result
	for key: String in data.site.get("housing", {}):
		var house: Dictionary = data.site.features.get(str(data.site.housing[key].house_id), {})
		if int(house.get("owner_faction", -1)) != int(settlement.owner_faction) or not feature_in_jurisdiction(data, house): continue
		var person: Dictionary = lab.site_controller.person_actions._person(int(key), false)
		if person.is_empty() or float(person.hp) <= 0.0 or int(person.faction) != int(settlement.owner_faction): continue
		result.append(int(key))
	result.sort()
	return result

static func status(lab: Variant) -> Dictionary:
	var data: TerrainData = lab.terrain
	var settlement := record(data)
	if settlement.is_empty(): return {"founded": false, "effective": false, "level": 0, "reasons": ["未建制聚落"]}
	var level := int(settlement.level)
	var feature := center(data)
	var population := residents(lab).size()
	var reasons: Array[String] = []
	if level <= 0: reasons.append("中心尚未完工")
	elif not Runtime.feature_usable(feature): reasons.append("中心本體受損（耐久 0）")
	var threshold := int(RESIDENTS.get(maxi(1, level), 0))
	if level > 0 and population < threshold: reasons.append("登記居民 %d／%d 人" % [population, threshold])
	return {"founded": true, "effective": reasons.is_empty(), "level": level, "population": population, "threshold": threshold,
		"radius": radius(level), "reasons": reasons, "name": str(settlement.name), "owner_faction": int(settlement.owner_faction),
		"head": int(SiteOffices.head_position(settlement.offices).get("holder", -1)), "head_title": str(SiteOffices.head_position(settlement.offices).get("name", ""))}

## New civil grade upgrades only; existing grades and un-founded Sites unchanged.
static func grade_cap(lab: Variant, feature: Dictionary) -> int:
	var settlement := record(lab.terrain)
	if settlement.is_empty() or int(feature.get("owner_faction", -1)) != int(settlement.owner_faction): return Runtime.CIVIL_MAX_GRADE
	var state := status(lab)
	return clampi(int(state.level), 1, Runtime.CIVIL_MAX_GRADE) if bool(state.effective) else 1

static func _count_buildings(data: TerrainData, owner_faction: int, kinds: Array) -> int:
	var count := 0
	for key: String in data.site.get("features", {}):
		var feature: Dictionary = data.site.features[key]
		if str(feature.get("kind", "")) in kinds and str(feature.get("stage", "")) == "complete" and int(feature.get("owner_faction", -1)) == owner_faction \
			and Runtime.feature_usable(feature) and feature_in_jurisdiction(data, feature):
			count += 1
	return count

## What the next level still lacks: people, buildings, materials (work is fixed).
static func next_level(lab: Variant) -> Dictionary:
	var data: TerrainData = lab.terrain
	var settlement := record(data)
	if settlement.is_empty() or int(settlement.level) <= 0: return {"ok": false, "target": 0, "missing": ["中心尚未完工"]}
	var target := int(settlement.level) + 1
	if target > Runtime.SETTLEMENT_MAX_LEVEL: return {"ok": false, "target": target, "missing": ["P0 最高 %d 級" % Runtime.SETTLEMENT_MAX_LEVEL]}
	var missing: Array[String] = []
	var population := residents(lab).size()
	if population < int(RESIDENTS[target]): missing.append("登記居民 %d／%d 人" % [population, int(RESIDENTS[target])])
	for requirement: Dictionary in REQUIRED_BUILDINGS[target]:
		var have := _count_buildings(data, int(settlement.owner_faction), requirement.kinds)
		if have < int(requirement.count): missing.append("%s %d／%d" % [str(requirement.label), have, int(requirement.count)])
	var terms := Runtime.settlement_level_terms(target)
	if not Runtime.can_pay(data.site.inventory, terms.cost): missing.append("材料 " + Runtime.items_text(terms.cost))
	return {"ok": missing.is_empty(), "target": target, "missing": missing, "cost": terms.cost, "work": float(terms.work)}

# --- Commands ----------------------------------------------------------------

static func _crowd_active(lab: Variant) -> bool:
	return lab.get("crowd_site") != null and lab.crowd_site.active

static func _fit(person: Dictionary) -> bool:
	return not person.is_empty() and float(person.hp) > 0.0 and float(person.ko) <= 0.0 and not bool(person.captive) and not bool(person.get("surrender_pending", false)) \
		and person.body.get("site_exited") != true and person.body.get("departed") != true

static func _head_check(lab: Variant, requester_id: int) -> Dictionary:
	if _crowd_active(lab): return Runtime.fail("CROWD_ACTIVE", "群眾戰鬥中聚落頁唯讀")
	var settlement := record(lab.terrain)
	if settlement.is_empty(): return Runtime.fail("NO_TARGET", "尚未建制聚落")
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY")
	var head := SiteOffices.head_position(settlement.offices)
	if int(head.get("holder", -1)) != requester_id: return Runtime.fail("NO_AUTHORITY", "此事由「%s」負責" % str(head.get("name", "首長")))
	var person: Dictionary = lab.site_controller.person_actions._person(requester_id, false)
	if not _fit(person) or int(person.faction) != int(settlement.owner_faction): return Runtime.fail("BUSY", "首長須存活清醒自由")
	return Runtime.ok("", {"settlement": settlement, "person": person})

## Founding = building the center (level 1 terms) with the founder present.
static func found(lab: Variant, founder_id: int, cells: Array[int], options: Dictionary = {}, occupied: Callable = Callable(), settlement_name: String = "新聚落") -> Dictionary:
	if _crowd_active(lab): return Runtime.fail("CROWD_ACTIVE", "群眾戰鬥中不能建立聚落")
	var data: TerrainData = lab.terrain
	if data.site.has("settlement"): return Runtime.fail("INVALID", "每個 Site 最多一座聚落中心")
	if founder_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY", "須由受控本人建立聚落")
	if not name_valid(settlement_name): return Runtime.fail("NAME_INVALID", "聚落名稱須為 1–%d 字且不含控制字元" % NAME_MAX)
	var founder: Dictionary = lab.site_controller.person_actions._person(founder_id, false)
	if not _fit(founder): return Runtime.fail("BUSY", "首長須存活清醒自由")
	var settings := options.duplicate(true)
	settings["owner_faction"] = int(founder.faction)
	if cells.is_empty() or _distance_to_rect(Runtime._cell_bounds(data, cells), Vector2i(founder.cell)) > radius(1):
		return Runtime.fail("TOO_FAR", "首長須在中心周圍 %d 格內在場" % radius(1))
	settings["settlement_found"] = true
	var built := Runtime.request_build(data, "settlement_center", cells, occupied, settings)
	if not built.ok: return built
	var key := str(built.feature)
	data.site["settlement"] = {"version": VERSION, "settlement_id": "settlement_%s_%s" % [str(data.site.get("id", "site")).left(64), key],
		"center_id": key, "level": 0, "name": settlement_name, "owner_faction": int(founder.faction),
		"offices": SiteOffices.default_offices("settlement", founder_id, not bool(founder.player)), "fall_record": empty_fall_record()}
	return Runtime.ok("已預留材料並排入聚落中心施工；完工即成為 1 級聚落", {"feature": key})

static func request_upgrade(lab: Variant, requester_id: int, occupied: Callable = Callable(), preview: bool = false) -> Dictionary:
	var checked := _head_check(lab, requester_id)
	if not checked.ok: return checked
	var terms := next_level(lab)
	if not bool(terms.ok): return Runtime.fail("REQUIREMENTS", "升 %d 級尚缺：%s" % [int(terms.target), "、".join(terms.missing)])
	return Runtime.request_settlement_level(lab.terrain, str(checked.settlement.center_id), int(terms.target), int(checked.person.faction), occupied, preview)

## A vacant head seat may be taken by a fit same-faction person in jurisdiction.
static func claim_head(lab: Variant, requester_id: int) -> Dictionary:
	if _crowd_active(lab): return Runtime.fail("CROWD_ACTIVE", "群眾戰鬥中聚落頁唯讀")
	var data: TerrainData = lab.terrain
	var settlement := record(data)
	if settlement.is_empty() or int(settlement.level) <= 0: return Runtime.fail("NO_TARGET", "尚未建制聚落")
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY")
	var head := SiteOffices.head_position(settlement.offices)
	if int(head.holder) > 0: return Runtime.fail("BUSY", "首長在任")
	var person: Dictionary = lab.site_controller.person_actions._person(requester_id, false)
	if not _fit(person) or int(person.faction) != int(settlement.owner_faction) or not cell_in_jurisdiction(data, Vector2i(person.cell)): return Runtime.fail("NO_AUTHORITY", "須是在管轄內清醒自由的同陣營原人物")
	SiteOffices.vacate_unless(settlement.offices, func(holder: int) -> bool: return holder != requester_id)
	head.holder = requester_id
	settlement.offices.duty_ai = not bool(person.player)
	settlement.offices.revision = mini(SiteOffices.MAX_SEQ, int(settlement.offices.revision) + 1)
	return Runtime.ok("已就任「%s」" % str(head.name))

static func rename(lab: Variant, requester_id: int, wanted: String) -> Dictionary:
	var checked := _head_check(lab, requester_id)
	if not checked.ok: return checked
	if not name_valid(wanted): return Runtime.fail("NAME_INVALID", "聚落名稱須為 1–%d 字且不含控制字元" % NAME_MAX)
	checked.settlement.name = wanted
	return Runtime.ok("聚落已更名為「%s」" % wanted)

## Automatic vacancy (death, capture, departure, faction): same rule as offices.
static func settle_offices(lab: Variant) -> bool:
	var settlement := record(lab.terrain)
	if settlement.is_empty(): return false
	var head_holder := int(SiteOffices.head_position(settlement.offices).get("holder", -1))
	return SiteOffices.vacate_unless(settlement.offices, func(holder: int) -> bool:
		var person: Dictionary = lab.site_controller.person_actions._person(holder, false)
		# Head: captivity vacates (settlement P0 rule). Other seats keep a captive
		# holder; the head acts meanwhile (OFFICE plan D1, 3.4).
		return not person.is_empty() and float(person.hp) > 0.0 and (not bool(person.captive) or holder != head_holder) 			and int(person.faction) == int(settlement.owner_faction))

# --- Capture -----------------------------------------------------------------

static func capture_zone(data: TerrainData) -> Dictionary:
	var zone := {}
	var feature := center(data)
	if feature.is_empty(): return zone
	var rect := Runtime._cell_bounds(data, feature.cells)
	for y: int in range(rect.position.y - CAPTURE_MARGIN, rect.end.y + CAPTURE_MARGIN):
		for x: int in range(rect.position.x - CAPTURE_MARGIN, rect.end.x + CAPTURE_MARGIN):
			var cell := Vector2i(x, y)
			if data.contains(cell) and not rect.has_point(cell): zone[cell] = true
	zone[data.cell_from_index(int(feature.entrance))] = true
	return zone

static func _role(person: Dictionary) -> String:
	var owner: Variant = person.owner
	if owner is TerrainArmy: return owner.military_role(int(person.unit))
	if owner is CrowdOwner: return str(owner._cold_get(int(person.unit), "military_role", "soldier"))
	return str(owner.get("military_role")) if owner != null and owner.get("military_role") != null else "civilian"

static func _leader_of(_lab: Variant, person: Dictionary) -> int:
	var owner: Variant = person.owner
	if owner is TerrainArmy and owner.current_commander >= 0 and owner.command_eligible(owner.current_commander): return owner.combat_identity(owner.current_commander)
	if owner is CrowdOwner: return int(owner.crowd_site.formation_state(int(owner.formation_index)).get("current_person", person.person_id))
	return int(person.person_id)

## People standing in the capture zone, read from their original owners.
static func zone_people(lab: Variant, zone: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var actions: RefCounted = lab.site_controller.person_actions
	var seen := {}
	var identities: Array[int] = []
	if _crowd_active(lab):
		for owner: RefCounted in lab.crowd_site.person_owners():
			for unit: int in owner.combat_units: identities.append(owner.combat_identity(unit))
	else:
		for actor: TerrainTestCharacter in lab.combat_actors:
			if is_instance_valid(actor) and zone.has(actor.terrain_cell): identities.append(actor.combat_identity())
		for team: TerrainArmy in lab.combat_armies:
			if not team.combat_enabled: continue
			for unit in range(team.combat_units.size()):
				if not team.member_gone(unit) and zone.has(lab._army_effective_cell(team, unit)): identities.append(team.combat_identity(unit))
	for identity: int in identities:
		if identity <= 0 or seen.has(identity): continue
		seen[identity] = true
		var person: Dictionary = actions._person(identity, false)
		if person.is_empty() or not zone.has(Vector2i(person.cell)): continue
		person["role"] = _role(person)
		result.append(person)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.person_id) < int(b.person_id))
	return result

## Eligibility is sampled before the interval. The original fall_record owns
## elapsed progress; handoff never resamples old time using a new roster.
static func capture_sample(lab: Variant) -> Dictionary:
	var data: TerrainData = lab.terrain
	var settlement := record(data)
	if settlement.is_empty() or int(settlement.level) <= 0: return {}
	var owner := int(settlement.owner_faction)
	var defended := false
	var attackers := {}
	var first_attacker := {}
	for person: Dictionary in zone_people(lab, capture_zone(data)):
		var conscious := float(person.hp) > 0.0 and float(person.ko) <= 0.0
		if int(person.faction) == owner:
			defended = defended or conscious and not bool(person.captive)
		elif _fit(person) and str(person.role) != "civilian":
			attackers[int(person.faction)] = int(attackers.get(int(person.faction), 0)) + 1
			if not first_attacker.has(int(person.faction)): first_attacker[int(person.faction)] = person
	var attacker := -1
	if not defended:
		for faction: int in attackers:
			if attacker < 0 or int(attackers[faction]) > int(attackers[attacker]) or int(attackers[faction]) == int(attackers[attacker]) and faction < attacker: attacker = faction
	return {"owner": owner, "attacker": attacker,
		"leader": _leader_of(lab, first_attacker[attacker]) if attacker >= 0 else -1}

static func capture_interval_limit(data: TerrainData, sample: Dictionary, maximum: float) -> float:
	var settlement := record(data)
	if settlement.is_empty() or sample.is_empty() or int(sample.attacker) < 0: return maximum
	var fall: Dictionary = settlement.fall_record
	var accrued := float(fall.contest_seconds) if int(fall.contest_faction) == int(sample.attacker) else 0.0
	return minf(maximum, maxf(0.0, CAPTURE_SECONDS - accrued))

## Integrate [begin,end) only. The exact completed endpoint is retained in the
## same original fall_record until contacts/player events have been consumed.
static func advance_capture_sample(data: TerrainData, sample: Dictionary, game_seconds: float) -> Dictionary:
	if not is_finite(game_seconds) or game_seconds < 0.0: return Runtime.fail("INVALID_TIME")
	var settlement := record(data)
	if settlement.is_empty() or sample.is_empty(): return Runtime.ok()
	if int(sample.get("owner", -1)) != int(settlement.owner_faction): return Runtime.fail("STALE_CAPTURE_SAMPLE")
	var fall: Dictionary = settlement.fall_record
	var attacker := int(sample.get("attacker", -1))
	if attacker < 0:
		if int(fall.contest_faction) >= 0: data.site.notices.append("%s攻陷計時中斷" % str(settlement.name))
		fall["contest_faction"] = -1
		fall["contest_seconds"] = 0.0
		return Runtime.ok()
	if int(fall.contest_faction) != attacker:
		fall["contest_faction"] = attacker
		fall["contest_seconds"] = 0.0
	fall["contest_seconds"] = minf(CAPTURE_SECONDS, float(fall.contest_seconds) + game_seconds)
	return Runtime.ok("", {"pending": float(fall.contest_seconds) >= CAPTURE_SECONDS})

static func settle_capture(lab: Variant) -> Dictionary:
	var data: TerrainData = lab.terrain
	var settlement := record(data)
	# The shared-step producers stop paying once the remaining capture time is within the
	# action epsilon (1e-12); a total that lands that close below 60 is the completed endpoint.
	if settlement.is_empty() or float(settlement.fall_record.contest_seconds) < CAPTURE_SECONDS - 0.000000000001: return {}
	var sample := capture_sample(lab)
	if sample.is_empty(): return Runtime.fail("STALE_CAPTURE_SAMPLE")
	if int(sample.attacker) != int(settlement.fall_record.contest_faction):
		return advance_capture_sample(data, sample, 0.0)
	return fall_to(lab, int(sample.attacker), int(sample.leader))

## Existing direct callers keep their one-shot contract; shared-step callers
## use the pre-interval sample and the original zero-time settlement separately.
static func advance_capture(lab: Variant, game_seconds: float) -> Dictionary:
	if game_seconds <= 0.0: return {}
	var advanced := advance_capture_sample(lab.terrain, capture_sample(lab), game_seconds)
	return advanced if not advanced.ok else settle_capture(lab)

static func _keeps_defender(data: TerrainData, key: String, feature: Dictionary) -> bool:
	if feature.has("ship_build"): return true
	if str(feature.get("kind", "")) == "barracks" and Runtime._barracks_in_use(data, key): return true
	if str(feature.get("kind", "")) == "prison" and Runtime._prison_in_use(data, key): return true
	return false

## Fall: defender buildings in jurisdiction change owner; residents' house
## registrations end; all settlement positions are vacated; the capturing
## leader becomes the provisional head. Level is kept.
static func fall_to(lab: Variant, attacker: int, leader_id: int) -> Dictionary:
	var data: TerrainData = lab.terrain
	var settlement := record(data)
	var defender := int(settlement.owner_faction)
	var changed: Array[String] = []
	var kept: Array[String] = []
	for key: String in data.site.features:
		var feature: Dictionary = data.site.features[key]
		if int(feature.get("owner_faction", -1)) != defender or not feature_in_jurisdiction(data, feature) and key != str(settlement.center_id): continue
		if key != str(settlement.center_id) and _keeps_defender(data, key, feature): kept.append(key); continue
		feature["owner_faction"] = attacker
		changed.append(key)
	var released: Array[int] = []
	for identity: String in data.site.get("housing", {}).keys():
		if str(data.site.housing[identity].house_id) in changed:
			data.site.housing.erase(identity)
			released.append(int(identity))
	for supply: Dictionary in data.site.get("team_supply", {}).values():
		if str(supply.get("training_feature_id", "")) in changed:
			supply.training_order = false
			supply.training_requester = -1
			supply.training_feature_id = ""
	settlement.owner_faction = attacker
	SiteOffices.vacate_unless(settlement.offices, func(_holder: int) -> bool: return false)
	var head := SiteOffices.head_position(settlement.offices)
	head.holder = leader_id if leader_id > 0 else -1
	settlement.offices.duty_ai = leader_id != int(lab.controlled_person_id())
	settlement.offices.revision = mini(SiteOffices.MAX_SEQ, int(settlement.offices.revision) + 1)
	settlement.fall_record = {"version": 2, "contest_faction": -1, "contest_seconds": 0.0,
		"last_fall": {"from": defender, "to": attacker, "leader": leader_id if leader_id > 0 else -1, "minute": int(data.site.get("minute", 0))}}
	data.environment_revision += 1
	var message := "%s已陷落：陣營 %d 取得 %d 座建物；%d 名原居民住宅登記解除" % [str(settlement.name), attacker, changed.size(), released.size()]
	if not kept.is_empty(): message += "；%d 座仍有原守方人物引用而保留" % kept.size()
	data.site.notices.append(message)
	return Runtime.ok(message, {"changed": changed, "kept": kept, "released": released, "leader": leader_id})

# --- Offices beyond the head (OFFICE plan appendix D.7) ------------------------
# Settlements may hold ordinary positions; the only wired one is the prison duty
# (典獄). A record saved before it existed gains the vacant seat on first use,
# exercised by the head, so behavior is unchanged until someone is appointed.

static func offices(lab: Variant, read_only: bool = false) -> Dictionary:
	var settlement := record(lab.terrain)
	if settlement.is_empty() or not settlement.get("offices") is Dictionary: return {}
	var current: Dictionary = settlement.offices.duplicate(true) if read_only else settlement.offices
	SiteOffices.ensure_catalog(current, "settlement")
	SiteOffices.upgrade(current)
	return current

static func office_person_ok(lab: Variant, person_id: int) -> bool:
	var settlement := record(lab.terrain)
	if settlement.is_empty() or person_id <= 0: return false
	var person: Dictionary = lab.site_controller.person_actions._person(person_id, false)
	return _fit(person) and int(person.faction) == int(settlement.owner_faction)

static func head_executor(lab: Variant, read_only: bool = false) -> int:
	var head := int(SiteOffices.head_position(offices(lab, read_only)).get("holder", -1))
	return head if office_person_ok(lab, head) else -1

static func duty_resolve(lab: Variant, duty_id: String, read_only: bool = false) -> Dictionary:
	var current := offices(lab, read_only)
	if current.is_empty(): return {"ok": false, "code": "UNESTABLISHED", "message": "尚未建制聚落", "duty_id": duty_id}
	var head := int(SiteOffices.head_position(current).get("holder", -1))
	return SiteOffices.resolve(current, duty_id, head if office_person_ok(lab, head) else -1, func(identity: int) -> bool: return office_person_ok(lab, identity))

## Head-only, non-delegable adjustment (3.5); candidates are living same-faction people.
static func apply_office_plan(lab: Variant, requester_id: int, expected_revision: int, ops: Array) -> Dictionary:
	if _crowd_active(lab): return Runtime.fail("CROWD_ACTIVE", "群眾戰鬥中聚落頁唯讀")
	var current := offices(lab)
	if requester_id <= 0 or current.is_empty() or requester_id != head_executor(lab): return Runtime.fail("NO_AUTHORITY", "只有清醒自由的聚落首長可調整聚落職位")
	var settlement := record(lab.terrain)
	var result := SiteOffices.apply_plan(current, "settlement", expected_revision, ops, func(identity: int, _office_class: String) -> bool:
		var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
		return not person.is_empty() and float(person.hp) > 0.0 and int(person.faction) == int(settlement.owner_faction))
	if not bool(result.ok): return result
	settlement.offices = result.offices
	return Runtime.ok("已套用聚落人事方案", {"revision": int(settlement.offices.revision), "refs": result.refs})

static func set_duty_ai_enabled(lab: Variant, requester_id: int, enabled: bool) -> Dictionary:
	var current := offices(lab)
	if requester_id <= 0 or current.is_empty() or requester_id != head_executor(lab): return Runtime.fail("NO_AUTHORITY", "職責 AI 開關屬聚落首長的組織設定")
	current.duty_ai = enabled
	return Runtime.ok("已%s聚落職責 AI" % ("開啟" if enabled else "關閉"))

## A prison camp is governed by settlement.prison when it is the settlement's
## faction and inside its jurisdiction; any other camp keeps the original rules.
static func prison_governed(lab: Variant, prison_id: String) -> bool:
	var settlement := record(lab.terrain)
	var feature: Dictionary = lab.terrain.site.get("features", {}).get(prison_id, {})
	return not settlement.is_empty() and str(feature.get("kind", "")) == "prison" \
		and int(feature.get("owner_faction", -1)) == int(settlement.owner_faction) and feature_in_jurisdiction(lab.terrain, feature)

## User decision 2026-10-08: a completed barracks of the settlement's faction
## inside its jurisdiction is governed by 營務官 (head acts while vacant).
static func garrison_governed(lab: Variant, feature_id: String) -> bool:
	var settlement := record(lab.terrain)
	var feature: Dictionary = lab.terrain.site.get("features", {}).get(feature_id, {})
	return not settlement.is_empty() and str(feature.get("kind", "")) == "barracks" \
		and int(feature.get("owner_faction", -1)) == int(settlement.owner_faction) and feature_in_jurisdiction(lab.terrain, feature)

## {} when `requester_id` may decide for this barracks' roster; a refusal otherwise.
static func garrison_authority(lab: Variant, feature_id: String, requester_id: int) -> Dictionary:
	if not garrison_governed(lab, feature_id): return {}
	var resolved := duty_resolve(lab, "settlement.garrison")
	if bool(resolved.ok) and int(resolved.decider) == requester_id: return {}
	return SiteOffices.refusal(resolved, requester_id, offices(lab))

## {} when `requester_id` may decide for this camp; a refusal otherwise.
static func prison_authority(lab: Variant, prison_id: String, requester_id: int) -> Dictionary:
	if not prison_governed(lab, prison_id): return {}
	var resolved := duty_resolve(lab, "settlement.prison")
	if bool(resolved.ok) and int(resolved.decider) == requester_id: return {}
	return SiteOffices.refusal(resolved, requester_id, offices(lab))

## The original offices decide; source policy never grants land or work authority.
static func ecology_authority(lab: Variant, key: String, requester_id: int, expected_revision: int = -1) -> Dictionary:
	if lab == null or lab.get("terrain") == null: return Runtime.fail("NO_TARGET")
	var data: TerrainData = lab.terrain
	if Runtime._ship_runtime_pending(data): return Runtime.fail("BUSY", "原 Region／航行交接仍待提交，生態命令稍後再試")
	if not SiteEnvironment.ecology_active(data): return Runtime.fail("ECOLOGY_PENDING", "生態狀態仍待原存檔交接准入")
	var resource := SiteEnvironment.resource(data, key)
	if resource.is_empty() or int(resource.kind) not in SiteEnvironment.ECOLOGY_KINDS: return Runtime.fail("NO_TARGET", "此來源不適用生態管理")
	if _crowd_active(lab): return Runtime.fail("CROWD_ACTIVE", "群眾戰鬥中生態命令尚未准入")
	var person: Dictionary = lab.site_controller.person_actions._person(requester_id, false)
	if not _fit(person): return Runtime.fail("BUSY", "管理者須存活清醒自由")
	var settlement := record(data)
	if not settlement.is_empty():
		var original_center := center(data)
		if str(original_center.get("kind", "")) != "settlement_center" or original_center.get("cells", []).is_empty(): return Runtime.fail("INVALID_OWNER", "聚落中心引用失效，無法判定管轄")
		if cell_in_jurisdiction(data, data.cell_from_index(int(resource.cell))):
			var current := offices(lab, true)
			if expected_revision >= 0 and int(current.get("revision", -1)) != expected_revision: return Runtime.fail("STALE_OFFICE", "職位已變更，請重新確認生態命令")
			var resolved := duty_resolve(lab, "settlement.ecology", true)
			if not bool(resolved.ok) or int(resolved.decider) != requester_id: return SiteOffices.refusal(resolved, requester_id, current)
			return Runtime.ok("", {"revision": int(resolved.revision), "decider": int(resolved.decider), "acting": bool(resolved.acting), "position_name": str(resolved.position_name)})
	if expected_revision >= 0: return Runtime.fail("STALE_OFFICE", "原管轄已變更，請重新確認生態命令")
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY", "無聚落管轄的來源由當前受控人物設定")
	return Runtime.ok("", {"revision": -1, "decider": requester_id, "acting": false, "position_name": "受控人物"})

static func set_ecology_modes(lab: Variant, requester_id: int, keys: Array[String], mode: String, expected_revision: int = -1, expected_revisions: Dictionary = {}) -> Dictionary:
	if keys.is_empty() or mode not in SiteEnvironment.ECOLOGY_MODES: return Runtime.fail("INVALID")
	var unique: Array[String] = []
	for key: String in keys:
		if unique.has(key): continue
		var revision: Variant = expected_revisions.get(key, expected_revision)
		if not revision is int: return Runtime.fail("INVALID")
		var checked := ecology_authority(lab, key, requester_id, int(revision))
		if not checked.ok: return checked
		unique.append(key)
	# Resolve again at the original synchronous commit, including every source.
	for key: String in unique:
		var checked := ecology_authority(lab, key, requester_id, int(expected_revisions.get(key, expected_revision)))
		if not checked.ok: return checked
	return Runtime.ecology_set_modes(lab.terrain, unique, mode)

static func restore_ecology_zone(lab: Variant, requester_id: int, area: Rect2i, kind: int = -1, expected_revision: int = -1) -> Dictionary:
	if lab == null or lab.get("terrain") == null: return Runtime.fail("NO_TARGET")
	var data: TerrainData = lab.terrain
	var keys := SiteEnvironment.resources_in(data, area, kind)
	var found := false
	for key: String in keys:
		var resource := SiteEnvironment.resource(data, key)
		if int(resource.kind) not in SiteEnvironment.RESTORABLE_KINDS: continue
		var checked := ecology_authority(lab, key, requester_id, expected_revision)
		if not checked.ok: return checked
		if bool(resource.cleared): found = true
	if not found: return Runtime.fail("NO_TARGET", "框選內沒有已清除的原生植被來源")
	return Runtime.add_zone(data, area, kind, "restore")

static func valid_technology_operations(data: TerrainData, raw: Variant, state: Dictionary = {}) -> bool:
	var site: Dictionary = data.site if state.is_empty() else state
	if not Technology.keys(raw, ["version", "next_plan", "plans", "next_order", "orders"]) \
		or not _int(raw.version, 1, 1) or not _int(raw.next_plan, 1, MAX_PERSON) or not _int(raw.next_order, 1, MAX_PERSON) \
		or not raw.plans is Dictionary or raw.plans.size() > ENGINEERING_PLAN_LIMIT or not raw.orders is Dictionary or raw.orders.size() > ENGINEERING_ORDER_LIMIT: return false
	for key: Variant in raw.plans:
		if not key is String or not key.begins_with("plan_") or not key.trim_prefix("plan_").is_valid_int() \
			or str(int(key.trim_prefix("plan_"))) != key.trim_prefix("plan_") or not _int(int(key.trim_prefix("plan_")), 1, int(raw.next_plan) - 1) \
			or not valid_engineering_plan(data, raw.plans[key]) or raw.plans[key].id != key: return false
	var defense_count := 0
	for key: Variant in raw.orders:
		var order: Variant = raw.orders[key]
		if not key is String or not valid_technology_order_header(order, int(raw.next_order)) or order.id != key: return false
		if order.kind != "defense":
			if not _valid_other_technology_order(data, site, order): return false
			continue
		defense_count += 1
		if defense_count > DEFENSE_ORDER_LIMIT: return false
		if not Technology.keys(order, ["id", "kind", "revision", "authorizer_id", "owner_faction", "person_ids", "consents", "steps", "next_step", "status", "cap", "spent", "receipts", "purpose", "paid"]) \
			or order.id != key or not _int(order.authorizer_id, 1, MAX_PERSON) or not _int(order.owner_faction, 0, MAX_FACTION) \
			or not order.person_ids is Array or order.person_ids.is_empty() or order.person_ids.size() > ENGINEERING_STEP_LIMIT \
			or not order.consents is Array or order.consents.size() != order.person_ids.size() or not order.steps is Array or order.steps.is_empty() or order.steps.size() > ENGINEERING_STEP_LIMIT \
			or not _int(order.next_step, 0, order.steps.size()) or order.status not in ["prepared", "active", "completed", "cancelled"] \
			or not order.purpose is String or order.purpose != "S10:work:" + JSON.stringify([str(site.get("id", "")), str(site.get("settlement", {}).get("settlement_id", "")), key]) \
			or not Technology.material_stack(order.cap) or not Technology.material_stack(order.spent) or not order.receipts is Array \
			or order.receipts.size() != int(order.next_step) or not order.paid is Dictionary: return false
		if (order.status == "completed") != (int(order.next_step) == order.steps.size()) and order.status != "cancelled": return false
		var people := {}
		for identity: Variant in order.person_ids:
			if not _int(identity, 1, MAX_PERSON) or people.has(int(identity)): return false
			people[int(identity)] = true
		for index: int in order.steps.size():
			var step: Variant = order.steps[index]
			if not Technology.keys(step, ["action", "plan_id", "anchor", "feature_id", "part", "operator_id"]) or step.action not in ["construct", "repair"] \
				or not step.plan_id is String or not step.anchor is Array or not step.feature_id is String or not step.part is String \
				or not _int(step.operator_id, 1, MAX_PERSON) or not people.has(int(step.operator_id)): return false
			if step.action == "construct":
				if not raw.plans.has(step.plan_id) or raw.plans[step.plan_id].kind not in DEFENSE_ENGINEERING_KINDS or step.anchor.size() != 2 \
					or not _int(step.anchor[0], 0, data.size.x - 1) or not _int(step.anchor[1], 0, data.size.y - 1) or not step.part.is_empty(): return false
			elif not step.plan_id.is_empty() or not step.anchor.is_empty() or step.feature_id.is_empty() or step.part.is_empty() or step.part.length() > 128: return false
			if not step.feature_id.is_empty() and (not step.feature_id.is_valid_int() or str(int(step.feature_id)) != step.feature_id or int(step.feature_id) <= 0): return false
			if index < int(order.next_step) and step.feature_id.is_empty(): return false
		for index: int in order.person_ids.size():
			var consent: Variant = order.consents[index]
			if not Technology.keys(consent, ["site_id", "team_id", "person_id", "purpose", "decider_id", "revision", "status"]) \
				or consent.site_id != str(site.get("id", "")) or not _int(consent.team_id, 1, MAX_PERSON) or consent.person_id != order.person_ids[index] \
				or not _int(consent.decider_id, 1, MAX_PERSON) or not _int(consent.revision, 0, MAX_PERSON) or consent.purpose != order.purpose or consent.status != "accepted": return false
		for resource: String in order.spent:
			if int(order.spent[resource]) > int(order.cap.get(resource, 0)): return false
		var spent := {}
		for index: int in order.receipts.size():
			var receipt: Variant = order.receipts[index]
			if not Technology.keys(receipt, ["step", "feature_id", "operator_id", "action", "materials", "work_seconds"]) or not _int(receipt.step, index, index) \
				or receipt.feature_id != order.steps[index].feature_id or receipt.operator_id != order.steps[index].operator_id or receipt.action != order.steps[index].action \
				or not Technology.material_stack(receipt.materials) or not Technology.finite_number(receipt.work_seconds, 0.000000001): return false
			Runtime.add_items(spent, receipt.materials)
		if not order.paid.is_empty():
			if int(order.next_step) >= order.steps.size() or not Technology.keys(order.paid, ["feature_id", "materials", "work_seconds", "operator_id"]) \
				or order.paid.feature_id != order.steps[int(order.next_step)].feature_id or not Technology.material_stack(order.paid.materials) \
				or not Technology.finite_number(order.paid.work_seconds, 0.000000001) or order.paid.operator_id != order.steps[int(order.next_step)].operator_id: return false
			Runtime.add_items(spent, order.paid.materials)
		if not Technology.material_equal(spent, order.spent) or order.status == "active" and order.paid.is_empty() \
			or order.status in ["prepared", "completed"] and not order.paid.is_empty(): return false
	return true


static func normalize_technology_operations(raw: Dictionary) -> void:
	# Called only after strict admission. Historical receipts never need a live
	# host, body or inventory to normalize their already accepted finite truth.
	for field: String in ["version", "next_plan", "next_order"]: raw[field] = int(raw[field])
	for plan: Dictionary in raw.plans.values():
		for index: int in plan.cells.size(): plan.cells[index] = int(plan.cells[index])
		plan.options = engineering_options(plan.options)
	for order: Dictionary in raw.orders.values():
		order.authorizer_id = int(order.authorizer_id)
		order.revision = int(order.revision)
		if order.kind != "defense": _normalize_other_technology_order(order); continue
		for field: String in ["owner_faction", "next_step"]: order[field] = int(order[field])
		for index: int in order.person_ids.size(): order.person_ids[index] = int(order.person_ids[index])
		for consent: Dictionary in order.consents:
			for field: String in ["team_id", "person_id", "decider_id", "revision"]: consent[field] = int(consent[field])
		for step: Dictionary in order.steps:
			step.operator_id = int(step.operator_id)
			for index: int in step.anchor.size(): step.anchor[index] = int(step.anchor[index])
		for receipt: Dictionary in order.receipts:
			receipt.step = int(receipt.step)
			receipt.operator_id = int(receipt.operator_id)
			receipt.work_seconds = float(receipt.work_seconds)
			for resource: String in receipt.materials: receipt.materials[resource] = int(receipt.materials[resource])
		for materials: Dictionary in [order.cap, order.spent]:
			for resource: String in materials: materials[resource] = int(materials[resource])
		if not order.paid.is_empty():
			order.paid.operator_id = int(order.paid.operator_id)
			order.paid.work_seconds = float(order.paid.work_seconds)
			for resource: String in order.paid.materials: order.paid.materials[resource] = int(order.paid.materials[resource])


static func _valid_other_technology_order(data: TerrainData, state: Dictionary, raw: Dictionary) -> bool:
	if not Technology.keys(raw, ["id", "kind", "authorizer_id", "status", "payload", "receipts", "revision"]) or not raw.payload is Dictionary: return false
	var runtime: Variant = Runtime
	var method := "valid_settlement_processing_order" if raw.kind in ["charcoal_batch", "textile_batch"] else "valid_settlement_ship_order" if raw.kind == "ship_cooperation" else "valid_settlement_metal_order" if raw.kind == "metal_chain" else "valid_settlement_food_order" if raw.kind == "food_order" else ""
	var normalizer := "normalize_settlement_processing_order" if raw.kind in ["charcoal_batch", "textile_batch"] else "normalize_settlement_ship_order" if raw.kind == "ship_cooperation" else "normalize_settlement_metal_order" if raw.kind == "metal_chain" else "normalize_settlement_food_order" if raw.kind == "food_order" else ""
	return not method.is_empty() and runtime.has_method(method) and runtime.has_method(normalizer) and runtime.call(method, data, state, raw) == true


static func valid_engineering_plan(data: TerrainData, raw: Variant) -> bool:
	if not Technology.keys(raw, ["id", "name", "kind", "cells", "options", "source_feature"]) or not raw.id is String \
		or not raw.id.begins_with("plan_") or not raw.name is String or raw.name.strip_edges().is_empty() or raw.name.length() > 48 \
		or not raw.kind is String or raw.kind not in ENGINEERING_KINDS or not raw.cells is Array or raw.cells.is_empty() or raw.cells.size() > 36 \
		or not raw.source_feature is String or not raw.source_feature.is_valid_int() or int(raw.source_feature) <= 0: return false
	var options := engineering_options(raw.options)
	if options.is_empty(): return false
	var seen := {}
	for index: Variant in raw.cells:
		if not _int(index, 0, data.size.x * data.size.y - 1) or seen.has(int(index)): return false
		seen[int(index)] = true
	return Runtime.validate_building_layout(data, str(raw.kind), raw.cells, options).ok


static func valid_technology_order_header(raw: Variant, next_order: int) -> bool:
	# Shared primitive only. Exact typed payloads below remain mandatory; an
	# unknown kind never becomes valid merely by carrying this header.
	if not raw is Dictionary: return false
	for field: String in ["id", "kind", "authorizer_id", "status", "receipts", "revision"]:
		if not raw.has(field): return false
	if not raw.id is String or not raw.kind is String or raw.kind.is_empty() or raw.kind.length() > 32 \
		or not _int(raw.authorizer_id, 1, MAX_PERSON) or not raw.status is String or raw.status.is_empty() or raw.status.length() > 24 \
		or not raw.receipts is Array or raw.receipts.size() > 32 or not _int(raw.revision, 0, MAX_PERSON): return false
	for index: int in raw.kind.length():
		if "abcdefghijklmnopqrstuvwxyz0123456789_".find(raw.kind.substr(index, 1)) < 0: return false
	var prefix := str(raw.kind) + "_"
	var serial := str(raw.id).trim_prefix(prefix)
	return str(raw.id).begins_with(prefix) and serial.is_valid_int() and serial == str(int(serial)) and _int(int(serial), 1, next_order - 1)


static func _normalize_other_technology_order(raw: Dictionary) -> void:
	# Paired with the strict typed branches. Unknown fields cannot reach restore.
	var runtime: Variant = Runtime
	var method := "normalize_settlement_processing_order" if raw.kind in ["charcoal_batch", "textile_batch"] else "normalize_settlement_ship_order" if raw.kind == "ship_cooperation" else "normalize_settlement_metal_order" if raw.kind == "metal_chain" else "normalize_settlement_food_order" if raw.kind == "food_order" else ""
	assert(not method.is_empty() and runtime.has_method(method), "UNSUPPORTED Settlement operation normalization")
	runtime.call(method, raw)


static func engineering_options(raw: Variant) -> Dictionary:
	if not raw is Dictionary or raw.size() != 5: return {}
	if not Technology.keys(raw, ["layout_version", "quarter", "owner_faction", "material", "variant"]) \
		or not _int(raw.layout_version, 1, 1) or not _int(raw.quarter, 0, 3) or not _int(raw.owner_faction, 0, MAX_FACTION) \
		or not raw.material is String or raw.material not in ["wood", "stone"] or not raw.variant is String: return {}
	var result: Dictionary = raw.duplicate()
	for field: String in ["layout_version", "quarter", "owner_faction"]: result[field] = int(result[field])
	return result


static func empty_technology_operations() -> Dictionary:
	return {"version": 1, "next_plan": 1, "plans": {}, "next_order": 1, "orders": {}}


static func publish_technology_operations(settlement: Dictionary, candidate: Dictionary) -> void:
	# Original synchronous checked owner tail keeps accepted SAME refs alive.
	if not settlement.has("technology_operations"):
		settlement["technology_operations"] = candidate
		return
	var original: Dictionary = settlement.technology_operations
	for collection: String in ["plans", "orders"]:
		var kept: Dictionary = original[collection]
		for key: String in kept.keys():
			if not candidate[collection].has(key): kept.erase(key)
		for key: String in candidate[collection]:
			if kept.has(key):
				var value: Dictionary = kept[key]
				value.clear()
				value.merge(candidate[collection][key], true)
			else: kept[key] = candidate[collection][key]
	original["version"] = int(candidate.version)
	original["next_plan"] = int(candidate.next_plan)
	original["next_order"] = int(candidate.next_order)


const ENGINEERING_PLAN_LIMIT := 8


const ENGINEERING_ORDER_LIMIT := 16


const DEFENSE_ORDER_LIMIT := 4


const ENGINEERING_STEP_LIMIT := 4


const ENGINEERING_KINDS := ["house", "warehouse", "stone_wall", "gate", "wall_stairs", "siege_ladder"]


const DEFENSE_ENGINEERING_KINDS := ["stone_wall", "gate", "wall_stairs", "siege_ladder"]


## v1 retains its historical/current coupling. v2 validates history independently.
static func valid_last_fall(last: Dictionary, owner_faction: int, version: int, now_minute: int) -> bool:
	if version not in [1, 2]: return false
	if last.is_empty(): return true
	return last.size() == 4 and _int(last.get("from"), 0, MAX_FACTION) and _int(last.get("to"), 0, MAX_FACTION) and int(last.from) != int(last.to) and (version != 1 or int(last.to) == owner_faction) and _int(last.get("leader"), -1, MAX_PERSON) and _int(last.get("minute"), 0, 1000000000) and (version == 1 or int(last.minute) <= now_minute)
